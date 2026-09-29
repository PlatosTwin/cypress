package store

import (
	"context"
	"encoding/json"
	"errors"
	"time"

	"github.com/PlatosTwin/cypress/server/internal/uuid"
	"github.com/jackc/pgx/v5"
)

// ── Community trees: the reads (PR S2) ─────────────────────────────────────────────────────────
//
// Migration 007 made a community tree something other people can see. This file is every read
// that decides **who** sees it, and it is one predicate, `communityTreeFor`, used by all of them —
// the profile's community half, the public read, the photograph read and the history. The tile is
// the one read that does not take a viewer: it is caller-independent by design (§3C), so it serves
// exactly the published, live set and nothing that depends on who asked.
//
// Before this file, `TreeCommunityHalf` and `PublicTreeCommunityHalf` never consulted
// `community_trees` at all. They answered photographs and counts for any id, which was harmless
// while nobody's community tree was visible to anybody else, and stopped being harmless the moment
// 007 made "unpublished", "withdrawn" and "taken down" states a tree can be in.

// TreeVisibility is what one viewer may know about one tree id.
type TreeVisibility int

const (
	// NotACommunityTree is an id this service holds no community tree for and never did: a city
	// tree, or an id nobody sent. Everything about it is answered as before 007.
	NotACommunityTree TreeVisibility = iota
	// CommunityTreeHidden is a community tree this viewer may not see: somebody else's unpublished
	// tree, one withdrawn by its adder, one an operator took down, or one the erase door deleted
	// (tombstoned). **Every read answers it exactly as it answers an id it has never heard of**, so
	// that no read is an oracle for the tree's existence or its state.
	CommunityTreeHidden
	// CommunityTreeVisible is a live community tree that is published, or that this viewer added.
	CommunityTreeVisible
)

// CommunityTreeRecord is a community tree as the reads serve it.
type CommunityTreeRecord struct {
	ID          uuid.UUID
	Lat         float64
	Lon         float64
	Address     *string
	SpeciesID   *uuid.UUID
	Placement   string
	LandContext *string
	CreatedAt   time.Time
	UpdatedAt   time.Time
	Published   bool
	// AddedByViewer is §4's rule (`treeRow.isAddedBy`) for the viewer who asked: never true for an
	// anonymized tree, and never true for the public read, which has no viewer.
	AddedByViewer bool
}

// communityTreeFor is the one visibility predicate.
//
// `viewer` is the caller's owner; the zero Owner is "nobody" (the public read), for whom only a
// published, live tree is visible.
func communityTreeFor(ctx context.Context, q querier, id uuid.UUID, viewer Owner) (TreeVisibility, *CommunityTreeRecord, error) {
	var (
		tree      CommunityTreeRecord
		authority treeRow
	)
	err := q.QueryRow(ctx, `
		SELECT lat, lon, address, species_id, placement, land_context, created_at, updated_at,
		       published_at IS NOT NULL, user_id, device_id, anonymized_at, deleted_at
		  FROM community_trees WHERE id = $1
	`, id).Scan(&tree.Lat, &tree.Lon, &tree.Address, &tree.SpeciesID, &tree.Placement,
		&tree.LandContext, &tree.CreatedAt, &tree.UpdatedAt, &tree.Published,
		&authority.UserID, &authority.DeviceID, &authority.AnonymizedAt, &authority.DeletedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		// The erase door hard-deletes and leaves only the tombstone (decision 6). An erased tree is
		// hidden rather than "not a community tree": its photographs and contributions by *other*
		// people can outlive it only if it was kept, so in practice nothing is left to serve — but
		// the answer must not depend on that remaining true.
		var tombstoned bool
		if err := q.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM withdrawn_community_trees WHERE id = $1)`,
			id).Scan(&tombstoned); err != nil {
			return NotACommunityTree, nil, err
		}
		if tombstoned {
			return CommunityTreeHidden, nil, nil
		}
		return NotACommunityTree, nil, nil
	}
	if err != nil {
		return NotACommunityTree, nil, err
	}
	tree.ID = id
	if authority.DeletedAt != nil {
		// Withdrawn by its adder or taken down by an operator: gone for everybody, the adder
		// included (decision 8 — "withdraw a tree for everyone").
		return CommunityTreeHidden, nil, nil
	}
	tree.AddedByViewer = authority.isAddedBy(viewer)
	if !tree.Published && !tree.AddedByViewer {
		return CommunityTreeHidden, nil, nil
	}
	return CommunityTreeVisible, &tree, nil
}

// TreeIsHiddenFrom reports whether an id names a community tree this viewer may not see. The
// photograph read asks it about a photograph's tree.
func (s *Store) TreeIsHiddenFrom(ctx context.Context, treeID uuid.UUID, viewer Owner) (bool, error) {
	visibility, _, err := communityTreeFor(ctx, s.pool, treeID, viewer)
	return visibility == CommunityTreeHidden, err
}

// ── The tile ───────────────────────────────────────────────────────────────────────────────────

// TileBounds is a map tile's box, half-open the way the tile scheme assigns a point: a point on a
// shared edge belongs to exactly one tile. West is inclusive and east exclusive; north is inclusive
// and south exclusive (tile rows count southwards, and `floor` puts a point on a row's northern edge
// in that row).
type TileBounds struct {
	South, North, West, East float64
}

// TileKey is a position in the tile delta's keyset: `(updated_at, id)` for a tree, `(withdrawn_at,
// id)` for an erase-door tombstone. The two id sets are disjoint (a tombstoned id has no tree row
// and can never get one back — `insertCommunityTree`), so one keyset orders both.
type TileKey struct {
	At time.Time
	ID uuid.UUID
}

// Less orders keys the way Postgres orders the row `(timestamptz, uuid)`.
func (k TileKey) Less(other TileKey) bool {
	if !k.At.Equal(other.At) {
		return k.At.Before(other.At)
	}
	return uuidLess(k.ID, other.ID)
}

// TileEntry is one item of a tile page: a live, published tree to draw, or an id to drop.
type TileEntry struct {
	Key TileKey
	// Tree is set for a tree to draw and nil for an id to drop.
	Tree *CommunityTreeRecord
}

// TileQuery is one page request.
type TileQuery struct {
	Bounds TileBounds
	// After is the keyset position the page starts after; nil is the beginning.
	After *TileKey
	// WithdrawnSince bounds which removals are reported. A page of a **snapshot** (a first fetch,
	// whose client holds nothing for this tile yet) reports only removals after the snapshot began;
	// a **delta** page reports every removal after `After`. Nil is a delta.
	WithdrawnSince *time.Time
	Limit          int
}

// CommunityTreeTile is `GET /community-trees`' page (§3C), in keyset order.
//
// **What is served as a tree:** published and not deleted — the only community trees anybody but
// their adder may see, and the only ones any caller sees here, because this read is
// caller-independent so a phone can cache it (§3C). The adder's own unpublished trees are on the
// adder's phone already.
//
// **What is reported as removed:** a tree that was once public and no longer is — withdrawn by its
// adder or taken down by an operator (both soft, `deleted_at`), or published once and unpublished
// since — plus every erase-door tombstone. A tree that was **never** published is never reported,
// not even as an id to drop: no phone but its adder's ever held it, and a removal list is still a
// statement that a tree stood in this tile.
//
// **Which trees count as "in the tile":** the ones whose head is in it, and the ones any of whose
// earlier positions (the location chain) were. A pin moved across a tile edge would otherwise
// leave a stale copy in every cache that fetched only the old tile: the new tile's delta carries
// the new position, and the old tile's said nothing. So such a tree is served in the old tile too,
// with its **current** coordinate, which is outside the tile. The client must key its cache on the
// tree id and never assume a served tree lies inside the tile it came from.
//
// Tombstones carry no position (the erase door keeps nothing that could say whose it was, and a
// position is exactly that), so they cannot be scoped to a tile: every delta reports every
// tombstone after its cursor. A tombstone is an id and a time, and erasures are rare.
//
// The page is `Limit` entries; the second return is whether more matched beyond it.
func (s *Store) CommunityTreeTile(ctx context.Context, q TileQuery) ([]TileEntry, bool, error) {
	var afterAt *time.Time
	var afterID *uuid.UUID
	if q.After != nil {
		afterAt, afterID = &q.After.At, &q.After.ID
	}
	rows, err := s.pool.Query(ctx, `
		WITH candidates AS (
		    SELECT t.id, t.updated_at AS at,
		           t.lat, t.lon, t.species_id, t.placement, t.land_context, t.created_at,
		           (t.published_at IS NOT NULL AND t.deleted_at IS NULL) AS live,
		           (t.published_at IS NOT NULL
		            OR EXISTS (SELECT 1 FROM community_tree_events e
		                        WHERE e.tree_id = t.id AND e.kind = 'published')) AS was_public
		      FROM community_trees t
		     WHERE ($1::timestamptz IS NULL OR (t.updated_at, t.id) > ($1::timestamptz, $2::uuid))
		       AND ((t.lat > $3 AND t.lat <= $4 AND t.lon >= $5 AND t.lon < $6)
		            OR EXISTS (SELECT 1 FROM community_tree_locations l
		                        WHERE l.tree_id = t.id
		                          AND l.lat > $3 AND l.lat <= $4 AND l.lon >= $5 AND l.lon < $6))
		    UNION ALL
		    SELECT w.id, w.withdrawn_at,
		           NULL::double precision, NULL::double precision, NULL::uuid, NULL::text, NULL::text,
		           NULL::timestamptz,
		           false, true
		      FROM withdrawn_community_trees w
		     WHERE ($1::timestamptz IS NULL OR (w.withdrawn_at, w.id) > ($1::timestamptz, $2::uuid))
		)
		SELECT id, at, lat, lon, species_id, placement, land_context, created_at, live
		  FROM candidates
		 WHERE live OR (was_public AND ($7::timestamptz IS NULL OR at > $7::timestamptz))
		 ORDER BY at, id
		 LIMIT $8
	`, afterAt, afterID, q.Bounds.South, q.Bounds.North, q.Bounds.West, q.Bounds.East,
		q.WithdrawnSince, q.Limit+1)
	if err != nil {
		return nil, false, err
	}
	defer rows.Close()

	var entries []TileEntry
	for rows.Next() {
		var (
			key                TileKey
			lat, lon           *float64
			speciesID          *uuid.UUID
			placement, landCtx *string
			createdAt          *time.Time
			live               bool
		)
		if err := rows.Scan(&key.ID, &key.At, &lat, &lon, &speciesID, &placement, &landCtx,
			&createdAt, &live); err != nil {
			return nil, false, err
		}
		entry := TileEntry{Key: key}
		if live {
			entry.Tree = &CommunityTreeRecord{
				ID: key.ID, Lat: *lat, Lon: *lon, SpeciesID: speciesID, Placement: *placement,
				LandContext: landCtx, CreatedAt: *createdAt, UpdatedAt: key.At, Published: true,
			}
		}
		entries = append(entries, entry)
	}
	if err := rows.Err(); err != nil {
		return nil, false, err
	}
	if len(entries) > q.Limit {
		return entries[:q.Limit], true, nil
	}
	return entries, false, nil
}

// ── The history ────────────────────────────────────────────────────────────────────────────────

// HistoryEvent is one audit-log row as the history read serves it: **no actor**. Decision 4 keeps
// who did what, and from which device, on the server; the columns are not selected, so no handler
// can publish them by mistake.
type HistoryEvent struct {
	ID         uuid.UUID
	Kind       string
	OccurredAt time.Time
	Before     HistoryPosition
	After      HistoryPosition
}

// HistoryPosition is an event's `before` or `after`, as `position` writes it. Every field is
// optional: a species event carries only the species, a move only the place.
type HistoryPosition struct {
	Lat       *float64   `json:"lat"`
	Lon       *float64   `json:"lon"`
	Placement *string    `json:"placement"`
	SpeciesID *uuid.UUID `json:"species_id"`
}

// ErrHistoryNotFound is a history this viewer may not read: no community tree by that id, or one
// hidden from them. One error for both, so the answer is not an oracle.
var ErrHistoryNotFound = errors.New("no community tree history for this viewer")

// CommunityTreeHistory returns the tree's audit log for one viewer, newest first, restricted to
// `kinds` and capped at `limit`; the second return is whether that is all of it.
//
// Newest first is `occurred_at` (the act's own time — a late correction sorts where it happened,
// not where it arrived), then `recorded_at`, then the id, so two events on one day keep a stable
// order on the wire even though the wire's dates are truncated to the day.
func (s *Store) CommunityTreeHistory(ctx context.Context, id uuid.UUID, viewer Owner, kinds []string, limit int) ([]HistoryEvent, bool, error) {
	visibility, _, err := communityTreeFor(ctx, s.pool, id, viewer)
	if err != nil {
		return nil, false, err
	}
	if visibility != CommunityTreeVisible {
		return nil, false, ErrHistoryNotFound
	}
	rows, err := s.pool.Query(ctx, `
		SELECT id, kind, occurred_at, before, after
		  FROM community_tree_events
		 WHERE tree_id = $1 AND kind = ANY ($2::text[])
		 ORDER BY occurred_at DESC, recorded_at DESC, id DESC
		 LIMIT $3
	`, id, kinds, limit+1)
	if err != nil {
		return nil, false, err
	}
	defer rows.Close()
	var events []HistoryEvent
	for rows.Next() {
		var (
			event         HistoryEvent
			before, after []byte
		)
		if err := rows.Scan(&event.ID, &event.Kind, &event.OccurredAt, &before, &after); err != nil {
			return nil, false, err
		}
		if before != nil {
			if err := json.Unmarshal(before, &event.Before); err != nil {
				return nil, false, err
			}
		}
		if after != nil {
			if err := json.Unmarshal(after, &event.After); err != nil {
				return nil, false, err
			}
		}
		events = append(events, event)
	}
	if err := rows.Err(); err != nil {
		return nil, false, err
	}
	if len(events) > limit {
		return events[:limit], false, nil
	}
	return events, true, nil
}
