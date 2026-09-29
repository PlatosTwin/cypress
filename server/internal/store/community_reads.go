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
	// CreatedAt is **when this viewer may say the tree was added** (the orchestrator's V1 ruling
	// on decision 13): the tree's own `created_at` for its adder, and `published_at` for everybody
	// else, including the tile, which has no viewer. A tree added in March and published in
	// September was, to a stranger, added in September; the private months are the adder's. The
	// history's `added` event says the same day, so the two cannot disagree on one screen.
	CreatedAt time.Time
	UpdatedAt time.Time
	Published bool
	// PublishedAt is when the tree went live; nil while it is private.
	PublishedAt *time.Time
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
		tree        CommunityTreeRecord
		authority   treeRow
		publishedAt *time.Time
	)
	err := q.QueryRow(ctx, `
		SELECT lat, lon, address, species_id, placement, land_context, created_at, updated_at,
		       published_at, user_id, device_id, anonymized_at, deleted_at
		  FROM community_trees WHERE id = $1
	`, id).Scan(&tree.Lat, &tree.Lon, &tree.Address, &tree.SpeciesID, &tree.Placement,
		&tree.LandContext, &tree.CreatedAt, &tree.UpdatedAt, &publishedAt,
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
	tree.Published = publishedAt != nil
	tree.PublishedAt = publishedAt
	tree.AddedByViewer = authority.isAddedBy(viewer)
	if !tree.Published && !tree.AddedByViewer {
		return CommunityTreeHidden, nil, nil
	}
	if !tree.AddedByViewer {
		// Visible and not the adder's, so published: the stranger's "added" is going live.
		tree.CreatedAt = *publishedAt
	}
	return CommunityTreeVisible, &tree, nil
}

// treeHiddenFromViewerSQL is `communityTreeFor`'s "hidden" answer as a SQL predicate, for a read
// that has to decide it for many trees in one query (the grove's hero). `tree` is the SQL
// expression naming the tree's id; `$1` and `$2` must be the viewer's user and device ids, as they
// are in every per-owner query in this package.
//
// It is a second spelling of one rule, so it is checked against the first:
// `TestTheGroveHeroPassesThePhotographGate` builds every hidden state and the visible ones, and
// asserts that the grove draws a hero exactly where `TreeIsHiddenFrom` says the tree is visible.
// The clauses, in `communityTreeFor`'s order: tombstoned; withdrawn or taken down; unpublished and
// not added by this viewer, where "added by" is `treeRow.isAddedBy` (never an anonymized tree; the
// account when the caller has one, the device only when it does not). `coalesce(…, false)` because
// `user_id = $1` is NULL for a device-owned tree, and a NULL here would read as "visible".
func treeHiddenFromViewerSQL(tree string) string {
	return `(EXISTS (SELECT 1 FROM withdrawn_community_trees w WHERE w.id = ` + tree + `)
	      OR EXISTS (SELECT 1 FROM community_trees c
	                  WHERE c.id = ` + tree + `
	                    AND (c.deleted_at IS NOT NULL
	                         OR (c.published_at IS NULL
	                             AND NOT (c.anonymized_at IS NULL
	                                      AND CASE WHEN $1::uuid IS NOT NULL THEN coalesce(c.user_id = $1, false)
	                                               ELSE coalesce($2::uuid IS NOT NULL AND c.device_id = $2, false)
	                                          END)))))`
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
// **What is reported as removed:** a tree that was public and no longer is — withdrawn by its adder
// or taken down by an operator (both soft, `deleted_at`, and once-public exactly when
// `published_at` is set: nothing unpublishes, decision 10, and a tree born withdrawn is never
// published) — plus every erase-door tombstone whose tree had been public
// (`withdrawn_community_trees.was_public`). A tree that was **never** published is never reported,
// not even as an id: no phone but its adder's ever held it, and a removal is still a statement that
// a tree existed (the #190 review's F2 and F3).
//
// **Which trees count as "in the tile":** the ones whose head is in it, and the ones any of whose
// earlier **public** positions were (`community_tree_locations.was_public`). A pin moved across a
// tile edge would otherwise leave a stale copy in every cache that fetched only the old tile, so
// such a tree is served in the old tile too, with its **current** coordinate, which is outside the
// tile; the client keys its cache on the tree id. A position the tree held only while private is
// never a reason to report it anywhere (decision 13: history starts at going live).
//
// Tombstones carry no position (the erase door keeps nothing that could say whose it was, and a
// position is exactly that), so they cannot be scoped to a tile: every delta reports every
// once-public tombstone after its cursor, wherever in the world the tree stood.
//
// ── Two query texts, each shaped for 007's partial indexes (performance precedence) ───────────
//
// The first version was one text with `($n IS NULL OR …)` around the keyset and an `OR EXISTS`
// chain arm. The review measured it at 320–480 ms warm per snapshot over 100k trees and 403 ms for
// a delta on a generic plan, because neither the OR nor the NULL test can use an index. Now:
//
//   - tile membership is a UNION of two arms, each carrying its index's predicate literally —
//     `published_at IS NOT NULL` on `community_trees (lat, lon)` and `was_public` on
//     `community_tree_locations (lat, lon)` — so the planner reaches the tile's trees by position,
//     O(trees in the tile), under a custom plan or a generic one;
//   - the keyset is always bound (the beginning is the zero time and the nil uuid), so there is no
//     NULL test for a generic plan to be unable to use;
//   - the removal list is `idx_withdrawn_community_trees_public`'s own shape, ordered and limited;
//   - a snapshot and a delta are different texts, so the snapshot's `since` filter is spelled only
//     where it applies rather than switched off by a NULL.
//
// The page is `Limit` entries; the second return is whether more matched beyond it.
func (s *Store) CommunityTreeTile(ctx context.Context, q TileQuery) ([]TileEntry, bool, error) {
	var after TileKey
	if q.After != nil {
		after = *q.After
	}
	query, args := tileDeltaQuery, []any{after.At, after.ID,
		q.Bounds.South, q.Bounds.North, q.Bounds.West, q.Bounds.East, q.Limit + 1}
	if q.WithdrawnSince != nil {
		query, args = tileSnapshotQuery, append(args, *q.WithdrawnSince)
	}
	rows, err := s.pool.Query(ctx, query, args...)
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

// tileInTile is the membership arms both texts share. $3..$6 are south, north, west, east; the
// box is half-open (TileBounds).
const tileInTile = `
	in_tile AS (
	    SELECT id FROM community_trees
	     WHERE published_at IS NOT NULL
	       AND lat > $3 AND lat <= $4 AND lon >= $5 AND lon < $6
	    UNION
	    SELECT tree_id FROM community_tree_locations
	     WHERE was_public
	       AND lat > $3 AND lat <= $4 AND lon >= $5 AND lon < $6
	)`

// tileDeltaQuery: every change after the cursor — live trees to draw, once-public trees removed
// since, and once-public tombstones since.
const tileDeltaQuery = `
	WITH` + tileInTile + `,
	changed AS (
	    SELECT t.id, t.updated_at AS at, t.lat, t.lon, t.species_id, t.placement, t.land_context,
	           t.published_at AS created_at, t.deleted_at IS NULL AS live
	      FROM community_trees t JOIN in_tile ON in_tile.id = t.id
	     WHERE t.published_at IS NOT NULL
	       AND (t.updated_at, t.id) > ($1::timestamptz, $2::uuid)
	     ORDER BY t.updated_at, t.id
	     LIMIT $7
	),
	gone AS (
	    SELECT id, withdrawn_at AS at FROM withdrawn_community_trees
	     WHERE was_public AND (withdrawn_at, id) > ($1::timestamptz, $2::uuid)
	     ORDER BY withdrawn_at, id
	     LIMIT $7
	)
	SELECT id, at, lat, lon, species_id, placement, land_context, created_at, live FROM changed
	UNION ALL
	SELECT id, at, NULL::double precision, NULL::double precision, NULL::uuid, NULL::text, NULL::text,
	       NULL::timestamptz, false FROM gone
	 ORDER BY at, id
	 LIMIT $7`

// tileSnapshotQuery is the delta with `since` ($8): a first fetch holds nothing, so a removal is
// reported only if it happened after the snapshot began — which catches a tree served on page one
// and withdrawn before page three.
const tileSnapshotQuery = `
	WITH` + tileInTile + `,
	changed AS (
	    SELECT t.id, t.updated_at AS at, t.lat, t.lon, t.species_id, t.placement, t.land_context,
	           t.published_at AS created_at, t.deleted_at IS NULL AS live
	      FROM community_trees t JOIN in_tile ON in_tile.id = t.id
	     WHERE t.published_at IS NOT NULL
	       AND (t.updated_at, t.id) > ($1::timestamptz, $2::uuid)
	       AND (t.deleted_at IS NULL OR t.updated_at > $8::timestamptz)
	     ORDER BY t.updated_at, t.id
	     LIMIT $7
	),
	gone AS (
	    SELECT id, withdrawn_at AS at FROM withdrawn_community_trees
	     WHERE was_public AND (withdrawn_at, id) > ($1::timestamptz, $2::uuid)
	       AND withdrawn_at > $8::timestamptz
	     ORDER BY withdrawn_at, id
	     LIMIT $7
	)
	SELECT id, at, lat, lon, species_id, placement, land_context, created_at, live FROM changed
	UNION ALL
	SELECT id, at, NULL::double precision, NULL::double precision, NULL::uuid, NULL::text, NULL::text,
	       NULL::timestamptz, false FROM gone
	 ORDER BY at, id
	 LIMIT $7`

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

// CommunityTreeHistory returns the tree's **public** history for one viewer, newest first,
// restricted to `kinds` and capped at `limit`; the second return is whether that is all of it.
//
// Public is `in_public_history` (decision 13: history starts at going live), spelled in the query so
// no caller can forget it. The adder gets the same public history as everybody else: their own
// record of the tree's private life is on their phone, and a route whose answer depended on who
// asked would be two contracts under one name. So the adder's own **unpublished** tree has a
// history with no events in it.
//
// Newest first is `occurred_at` (the act's own time — a late correction sorts where it happened,
// not where it arrived), then `recorded_at`, then the id, so two events on one day keep a stable
// order on the wire even though the wire's dates are truncated to the day.
func (s *Store) CommunityTreeHistory(ctx context.Context, id uuid.UUID, viewer Owner, kinds []string, limit int) ([]HistoryEvent, bool, error) {
	visibility, tree, err := communityTreeFor(ctx, s.pool, id, viewer)
	if err != nil {
		return nil, false, err
	}
	if visibility != CommunityTreeVisible {
		return nil, false, ErrHistoryNotFound
	}
	// **No public event is dated before the tree went live** (the orchestrator's L1 ruling on
	// decision 13). An act the adder made while the tree was private — a move queued on a phone
	// that was signed out or declining — can arrive after publication, and S1 then records it as
	// public, because the pin really did move in public. Its `occurred_at` is still the private
	// day, which would put a day of the tree's private life on the public record, below its own
	// "added". So the served date is `GREATEST(occurred_at, published_at)`, and the order is by the
	// served date too: the late act sits above "added", tied on the instant and broken by
	// `recorded_at`, which is when the public learned of it. `GREATEST` ignores a NULL, so a tree
	// that is not published (the adder's own, which has no public events anyway) is unchanged.
	rows, err := s.pool.Query(ctx, `
		SELECT id, kind, GREATEST(occurred_at, $4::timestamptz) AS served_at, before, after
		  FROM community_tree_events
		 WHERE tree_id = $1 AND in_public_history AND kind = ANY ($2::text[])
		 ORDER BY served_at DESC, recorded_at DESC, id DESC
		 LIMIT $3
	`, id, kinds, limit+1, tree.PublishedAt)
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
