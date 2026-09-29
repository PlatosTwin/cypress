package store

import (
	"context"
	"time"

	"github.com/PlatosTwin/cypress/server/internal/uuid"
	"github.com/jackc/pgx/v5"
)

// The Class R reads (spec §3.1): the community layer and the account's own rows, where liveness
// buys something real. What a local fallback loses for the R-degraded four is *other devices of
// the same account*, which is exactly what these queries return that the phone cannot.

// GroveEntry is a row of `GET /me/grove`.
type GroveEntry struct {
	TreeUUID      uuid.UUID
	LastVisitedAt *time.Time
	IsFavorite    bool
	// HeroPhotoID is the photograph the row draws instead of the accent tile (#176) — a photo fact
	// the phone cannot answer for a photograph it never wrote, which is the class of thing this
	// service exists to supply. Nil when the tree has no live photograph.
	HeroPhotoID *uuid.UUID
	// Record is the per-kind tally, or nil when this read could not prove it counted everything
	// (ERRATA E38). Zero is a claim about a person's history; nil is "this read did not answer
	// that", and the Trees list draws no tally for nil.
	Record map[string]int
}

// Grove returns every tree this identity has touched.
func (s *Store) Grove(ctx context.Context, owner Owner) ([]GroveEntry, error) {
	rows, err := s.pool.Query(ctx, `
		WITH mine AS (
		    SELECT tree_uuid, kind, occurred_at
		      FROM contributions
		     WHERE (($1::uuid IS NOT NULL AND user_id = $1) OR ($2::uuid IS NOT NULL AND device_id = $2))
		       AND deleted_at IS NULL
		       AND kind <> 'private_reminder'
		)
		, tallied AS (
		SELECT m.tree_uuid,
		       max(m.occurred_at) FILTER (WHERE m.kind = 'visit') AS last_visited_at,
		       coalesce(bool_or(f.is_favorite), false) AS is_favorite,
		       count(*) FILTER (WHERE m.kind = 'visit')       AS visits,
		       count(*) FILTER (WHERE m.kind = 'observation') AS observations,
		       count(*) FILTER (WHERE m.kind = 'measurement') AS measurements,
		       count(*) FILTER (WHERE m.kind = 'care_event')  AS care_events
		  FROM mine m
		  LEFT JOIN favorites f
		         ON f.tree_uuid = m.tree_uuid
		        AND f.is_favorite
		        AND (($1::uuid IS NOT NULL AND f.user_id = $1) OR ($2::uuid IS NOT NULL AND f.device_id = $2))
		 GROUP BY m.tree_uuid
		)
		SELECT t.tree_uuid, t.last_visited_at, t.is_favorite,
		       t.visits, t.observations, t.measurements, t.care_events,
		       hero.id AS hero_photo_id
		  FROM tallied t
		  -- The hero (#176). Visible means the same two rules the profile applies: publicly visible,
		  -- or this contributor's own and not deleted (ERRATA E37, E215). A row that drew a
		  -- stranger's unmoderated photograph as its hero is the disagreement E215 exists to stop.
		  LEFT JOIN LATERAL (
		      SELECT p.id FROM photos p
		       WHERE p.tree_uuid = t.tree_uuid
		         AND p.deleted_at IS NULL
		         AND (p.moderation_state = 'approved'
		              OR ($1::uuid IS NOT NULL AND p.user_id = $1)
		              OR ($2::uuid IS NOT NULL AND p.device_id = $2))
		       ORDER BY p.captured_at DESC
		       LIMIT 1
		  ) hero ON true
		 ORDER BY t.last_visited_at DESC NULLS LAST
	`, owner.UserID, owner.DeviceID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var entries []GroveEntry
	for rows.Next() {
		var entry GroveEntry
		var visits, observations, measurements, careEvents int
		if err := rows.Scan(&entry.TreeUUID, &entry.LastVisitedAt, &entry.IsFavorite,
			&visits, &observations, &measurements, &careEvents, &entry.HeroPhotoID); err != nil {
			return nil, err
		}
		// Not nil: this query counted every kind it reports, over the whole set rather than a page,
		// which is the condition E38 attaches to being allowed to state a total.
		// **`GroveRecord`'s names, not this table's.** The client's field is `checkIns`, and its own
		// comment says so explicitly — "named for the control, not for the `observations` table".
		// A response spelling it `observations` maps three of four and silently drops check-ins to
		// zero, which is the claim E38 spends a whole type making unwritable.
		entry.Record = map[string]int{
			"visits": visits, "checkIns": observations,
			"measurements": measurements, "careEvents": careEvents,
		}
		entries = append(entries, entry)
	}
	return entries, rows.Err()
}

// IsFavorite is `GET /me/grove` narrowed to one tree (#167).
//
// A separate query rather than a filter over Grove, which is the whole reason #167 exists: screen
// 03's heart re-reads after every write, and deriving it from the grove would make that a whole-list
// scan. The client's protocol makes the same split for the same reason.
func (s *Store) IsFavorite(ctx context.Context, owner Owner, treeUUID uuid.UUID) (bool, error) {
	var favorite bool
	err := s.pool.QueryRow(ctx, `
		SELECT coalesce((
		    SELECT is_favorite FROM favorites
		     WHERE tree_uuid = $3
		       AND (($1::uuid IS NOT NULL AND user_id = $1) OR ($2::uuid IS NOT NULL AND device_id = $2))
		     LIMIT 1), false)
	`, owner.UserID, owner.DeviceID, treeUUID).Scan(&favorite)
	return favorite, err
}

// MapMembership answers screen 01's two chips (#116, R23.1).
//
// `yours` is trees this identity contributed to — and community-added trees, which the contribution
// kinds do not cover: a tree you added is the most emphatically yours there is. Photographs are in
// by their visit rather than on their own, the same rule `DeviceContributions` states.
//
// `favorites` excludes tombstones: an un-favorited tree is not one anybody would say they have.
func (s *Store) MapMembership(ctx context.Context, owner Owner, kind string) ([]uuid.UUID, error) {
	var query string
	switch kind {
	case "yours":
		query = `
			SELECT DISTINCT tree_uuid FROM contributions
			 WHERE (($1::uuid IS NOT NULL AND user_id = $1) OR ($2::uuid IS NOT NULL AND device_id = $2))
			   AND deleted_at IS NULL AND kind <> 'private_reminder'
			UNION
			-- community_trees.id IS the client's tree UUID (see the table's own comment in
			-- server/migrations/001_initial.sql), so this arm and the one above are the same
			-- id space. They were not always, which is the defect that put a tree on screen 01
			-- under a name no other route answered to.
			SELECT DISTINCT id FROM community_trees
			 WHERE (($1::uuid IS NOT NULL AND user_id = $1) OR ($2::uuid IS NOT NULL AND device_id = $2))
			   AND deleted_at IS NULL`
	case "favorites":
		query = `
			SELECT tree_uuid FROM favorites
			 WHERE is_favorite
			   AND (($1::uuid IS NOT NULL AND user_id = $1) OR ($2::uuid IS NOT NULL AND device_id = $2))`
	default:
		return nil, ErrNotFound
	}

	rows, err := s.pool.Query(ctx, query, owner.UserID, owner.DeviceID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var ids []uuid.UUID
	for rows.Next() {
		var id uuid.UUID
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}
	return ids, rows.Err()
}

// JournalRow is one entry of `GET /me/journal`.
type JournalRow struct {
	ClientUUID uuid.UUID
	Kind       string
	TreeUUID   uuid.UUID
	OccurredAt time.Time
	Payload    []byte
}

// Journal is the paged personal timeline.
//
// The cursor is the `(occurred_at, client_uuid)` pair of the last row returned, not an offset. An
// offset over a table that is still being written to skips rows silently when something lands
// between two pages, and a journal that drops an entry with no error is the failure this app's
// `Series` type exists to make unwritable elsewhere.
func (s *Store) Journal(ctx context.Context, owner Owner, cursorAt *time.Time, cursorID *uuid.UUID, limit int) ([]JournalRow, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT client_uuid, kind, tree_uuid, occurred_at, payload
		  FROM contributions
		 WHERE (($1::uuid IS NOT NULL AND user_id = $1) OR ($2::uuid IS NOT NULL AND device_id = $2))
		   AND deleted_at IS NULL
		   AND ($3::timestamptz IS NULL OR (occurred_at, client_uuid) < ($3, $4))
		 ORDER BY occurred_at DESC, client_uuid DESC
		 LIMIT $5
	`, owner.UserID, owner.DeviceID, cursorAt, cursorID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var entries []JournalRow
	for rows.Next() {
		var entry JournalRow
		if err := rows.Scan(&entry.ClientUUID, &entry.Kind, &entry.TreeUUID,
			&entry.OccurredAt, &entry.Payload); err != nil {
			return nil, err
		}
		entries = append(entries, entry)
	}
	return entries, rows.Err()
}

// KnownSpecies is one row of the Species tab (screen 08).
type KnownSpecies struct {
	SpeciesID uuid.UUID
	FirstMet  time.Time
}

// GroveSpeciesKnown returns every species this contributor has met, oldest first.
//
// The species id is read out of the payload rather than a column, because a contribution's species
// is a fact about the mutation the client sent and this service does not hold the inventory to
// join against — R36 keeps the city layer local, so there is no `species` table here to normalize
// into.
func (s *Store) GroveSpeciesKnown(ctx context.Context, owner Owner) ([]KnownSpecies, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT (payload->>'speciesID')::uuid AS species_id, min(occurred_at) AS first_met
		  FROM contributions
		 WHERE (($1::uuid IS NOT NULL AND user_id = $1) OR ($2::uuid IS NOT NULL AND device_id = $2))
		   AND deleted_at IS NULL
		   AND payload->>'speciesID' IS NOT NULL
		 GROUP BY species_id
		 ORDER BY first_met ASC
	`, owner.UserID, owner.DeviceID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var known []KnownSpecies
	for rows.Next() {
		var entry KnownSpecies
		if err := rows.Scan(&entry.SpeciesID, &entry.FirstMet); err != nil {
			return nil, err
		}
		known = append(known, entry)
	}
	return known, rows.Err()
}

// ── The community half of `treeProfile(id:)` ───────────────────────────────────────────────────

// TreeCommunity is what a tree profile's community half carries.
//
// This is the R-required grade of spec §3.1, and the distinction is not pedantic: for `grove` a
// local fallback is a complete answer to the same question for one device, but for this read the
// local answer is missing *precisely the thing the read is for*. "The photo propagates to all other
// users" is somebody else's profile returning a photograph their device never wrote.
type TreeCommunity struct {
	Photos     []PhotoRecord
	VisitCount int
	// Tree is the community tree itself, when the id names one this viewer may see (S2, §3D). Nil
	// for a city tree, an id nobody sent, and a community tree hidden from this viewer — three
	// cases this read answers identically.
	Tree *CommunityTreeRecord
}

// TreeCommunityHalf reads it, for one viewer.
//
// **A community tree hidden from the viewer answers the zero value, with nothing else read**:
// somebody else's unpublished tree, a withdrawn one, a taken-down one, an erased one. Before S2
// this read never consulted `community_trees`, so it served the photographs and the visit count of
// a tree its adder had withdrawn, or had never published, to anybody who asked by id. The zero
// value is exactly what an id this service has never heard of produces, so the answer is not an
// oracle for the hidden tree's existence (`communityTreeFor`).
func (s *Store) TreeCommunityHalf(ctx context.Context, treeUUID uuid.UUID, viewer Owner) (TreeCommunity, error) {
	visibility, tree, err := communityTreeFor(ctx, s.pool, treeUUID, viewer)
	if err != nil {
		return TreeCommunity{}, err
	}
	if visibility == CommunityTreeHidden {
		return TreeCommunity{}, nil
	}
	photos, err := s.PhotosForTree(ctx, treeUUID)
	if err != nil {
		return TreeCommunity{}, err
	}
	var visits int
	err = s.pool.QueryRow(ctx, `
		SELECT count(*) FROM contributions
		 WHERE tree_uuid = $1 AND kind = 'visit' AND deleted_at IS NULL
	`, treeUUID).Scan(&visits)
	if err != nil {
		return TreeCommunity{}, err
	}
	return TreeCommunity{Photos: photos, VisitCount: visits, Tree: tree}, nil
}

// ── `POST /trees` and the 10 m proximity dedupe ────────────────────────────────────────────────

// NearbyTree is a dedupe candidate, carrying what the client's `NearbyTree` needs to be built.
//
// The client type wraps a whole `Tree`, not an id, so a candidate list of bare ids cannot construct
// one — and a *community-added* tree is by definition absent from the installed city file, so the
// phone cannot fill the gap locally either. Everything a `Tree` needs that this service actually
// knows is therefore carried here; see `proximityCandidate` in the api package for the mapping and
// for what is deliberately fixed rather than stored.
type NearbyTree struct {
	ID          uuid.UUID
	Lat         float64
	Lon         float64
	Address     *string
	SpeciesID   *uuid.UUID
	Placement   string
	LandContext *string
	CreatedAt   time.Time
	UpdatedAt   time.Time
	DistanceM   float64
}

// ProximityDedupeRadiusM is `TreeDraft.proximityDedupeRadiusM`: 10 m, any species (BUILD-PLAN §6).
const ProximityDedupeRadiusM = 10.0

// TreesWithin returns community trees within radius metres of a point, nearest first, that the
// viewer can see: published ones and the viewer's own (§3F, migration 007).
//
// A bounding-box prefilter over `idx_community_trees_position`, then a haversine — no PostGIS,
// which R72 declines because no server-side spatial query exists under R36's local read path and
// carrying an extension for a query nothing makes is not continuity.
//
// The latitude term of the box is constant; the longitude term is divided by cos(lat), which is
// what keeps the box a box rather than a shape that narrows to nothing near the poles. Both cities
// in the corpus are near 37°N, where the factor is ~1.25 — large enough that omitting it would
// quietly shrink the search and let a duplicate through. The query is `treesWithin`, shared with
// the transaction that moves a pin.
func (s *Store) TreesWithin(ctx context.Context, lat, lon, radiusM float64, viewer Owner) ([]NearbyTree, error) {
	return treesWithin(ctx, s.pool, lat, lon, radiusM, viewer, nil)
}

// CommunityTreeExists reports whether this exact tree has already been recorded.
//
// `POST /trees` calls it **before** the proximity query. Without that ordering a byte-identical
// retry — the flap-replay case the outbox exists for — runs the 10 m dedupe against the row it
// created moments ago, matches itself at zero metres, and comes back `conflict`. That code is
// non-retryable, so the item fails terminally and the contributor is offered a resolution sheet
// listing their own submission.
//
// A tree the erase door deleted counts as recorded: its id is in `withdrawn_community_trees`, and a
// replay of its add is a duplicate, not a second life.
func (s *Store) CommunityTreeExists(ctx context.Context, id uuid.UUID) (bool, error) {
	var found bool
	err := s.pool.QueryRow(ctx, `
		SELECT EXISTS (SELECT 1 FROM community_trees WHERE id = $1)
		    OR EXISTS (SELECT 1 FROM withdrawn_community_trees WHERE id = $1)
	`, id).Scan(&found)
	return found, err
}

// NewCommunityTree is what `POST /trees` records.
//
// The fields are `TreeDraft`'s, minus the ones that are not this table's business. `Placement` is
// non-empty by construction — the handler defaults it to `TreeDraft`'s own default — because
// `Tree.placement` is **non-optional** on the client and its raw values are frozen by `AppSchema`
// v10's CHECK. A row that stored nothing there produced `"unknown"` on the wire, which is not a
// `TreePlacement`, which threw the whole `Tree`, the whole `[NearbyTree]` and the whole
// `ProximityConflict` — on every candidate, always.
type NewCommunityTree struct {
	ID          uuid.UUID
	Lat         float64
	Lon         float64
	Address     *string
	SpeciesID   *uuid.UUID
	Placement   string
	LandContext *string
	// LocationAccuracyM is the fix's accuracy (D6), optional: nil is "the phone did not say".
	LocationAccuracyM *float64
}

// AddTree inserts a community tree under the client's own id, for `POST /trees`.
//
// It is `insertCommunityTree` in a transaction of its own — the same publication rule, root
// location and events as the sync path, with no contribution to carry the act's key.
func (s *Store) AddTree(ctx context.Context, tree NewCommunityTree, owner Owner, actor Actor) (ApplyOutcome, error) {
	outcome := Duplicate
	err := s.Tx(ctx, func(tx pgx.Tx) error {
		now := s.now()
		inserted, err := insertCommunityTree(ctx, tx, tree, newTreeAct{
			Owner: owner, Actor: actor, OccurredAt: now,
		}, now)
		if inserted {
			outcome = Applied
		}
		return err
	})
	return outcome, err
}
