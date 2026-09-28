package store

import (
	"context"
	"math"
	"time"

	"github.com/PlatosTwin/cypress/server/internal/uuid"
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

// MetSpeciesKinds are the contribution kinds whose `speciesID`, if a payload carries one, means
// "this person met this species" — and the only kinds `GroveSpeciesKnown` reads.
//
// They are the four the client's own Species tab unions, `GroveQueries.ownContributions`: a visit,
// an observation, a measurement and a care event are all having stood in front of the tree. The
// list is the product rule, not the set of kinds that happen to carry the key, and the two are
// different sets:
//
//   - **The kinds that really carry a `speciesID` are `add_tree`, `species_claim` and
//     `species_correction`**, and every one of them is a person *naming* a community tree's
//     species. The client refuses exactly those by rule: `GroveQueries.knownSpecies` reads
//     city-inventory trees only, because "a self-asserted species on a community-added tree does
//     not count as one you know" — counting one would let a contributor raise their own ring by
//     adding a tree. A server that counted them put species on the tab at refresh that the phone's
//     own paint had just left off.
//   - **The four kinds listed here carry no `speciesID` in any client payload today** (`Visit`,
//     `TreeObservation`, `TreeMeasurement`, `CareEvent`). So against today's clients this read
//     answers an empty list, and the phone's local half — which resolves the species of the trees
//     it visited from the city file it holds and this service does not (R36) — is the whole of the
//     Species tab. That is the correct answer to the question as the client defines it, and it was
//     already this read's answer for everyone who never named a community tree's species.
//
// A kind added to `syncKinds` is **out** of this read until somebody adds it here on purpose; a
// new kind can no longer reach the Species tab by carrying a key of the same spelling.
var MetSpeciesKinds = []string{"visit", "observation", "measurement", "care_event"}

// GroveSpeciesKnown returns every species this contributor has met, oldest first.
//
// The species id is read out of the payload rather than a column, because a contribution's species
// is a fact about the mutation the client sent and this service does not hold the inventory to
// join against — R36 keeps the city layer local, so there is no `species` table here to normalize
// into.
//
// ── Why the id is compared as text and parsed here, never cast in SQL ─────────────────────────
//
// This read used to select `(payload->>'speciesID')::uuid` over every kind. A cast can *error*
// rather than miss, so one stored payload carrying a non-UUID `speciesID` failed the whole query,
// and since that row is a contribution the phone cannot un-send, every later read of that
// identity's Species tab answered 500 until somebody deleted the row by hand. Migration 004 had
// already chosen extracted text over a cast for its lookups, for exactly this reason.
//
// So nothing in the SQL below can fail on a value it reads: `->` and `->>` on a `jsonb` answer NULL
// for a key that is absent or a payload that is not an object, `jsonb_typeof` answers NULL for NULL,
// and `lower` is total over text. The text is grouped case-insensitively — Swift's `JSONEncoder`
// writes a `UUID` uppercase — and parsed by `uuid.Parse`, the same canonical-form rule every other
// id on this service's wire is held to. A value that does not parse is **skipped, not reported**:
// it names no species, and failing the read over it would put back the defect this replaces.
//
// **Rows that are already poisoned in production are therefore harmless, whatever kind they are.**
// This does not depend on the kind filter, which is a statement about meaning; it would still be
// true with the filter removed. No migration and no index: `MetSpeciesKinds` narrows an owner-scoped
// scan the old query already ran.
func (s *Store) GroveSpeciesKnown(ctx context.Context, owner Owner) ([]KnownSpecies, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT lower(payload->>'speciesID') AS species_text, min(occurred_at) AS first_met
		  FROM contributions
		 WHERE (($1::uuid IS NOT NULL AND user_id = $1) OR ($2::uuid IS NOT NULL AND device_id = $2))
		   AND deleted_at IS NULL
		   AND kind = ANY($3::text[])
		   AND jsonb_typeof(payload->'speciesID') = 'string'
		 GROUP BY species_text
		 ORDER BY first_met ASC, species_text ASC
	`, owner.UserID, owner.DeviceID, MetSpeciesKinds)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var known []KnownSpecies
	for rows.Next() {
		var text string
		var entry KnownSpecies
		if err := rows.Scan(&text, &entry.FirstMet); err != nil {
			return nil, err
		}
		// Grouping on `lower(text)` and accepting only the canonical 36-character form means two
		// groups can never parse to one species, so no second pass is needed to merge them.
		parsed, parseErr := uuid.Parse(text)
		if parseErr != nil {
			continue
		}
		entry.SpeciesID = parsed
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
}

// TreeCommunityHalf reads it.
func (s *Store) TreeCommunityHalf(ctx context.Context, treeUUID uuid.UUID) (TreeCommunity, error) {
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
	return TreeCommunity{Photos: photos, VisitCount: visits}, nil
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

// TreesWithin returns community trees within radius metres of a point, nearest first.
//
// A bounding-box prefilter over `idx_community_trees_position`, then a haversine — no PostGIS,
// which R72 declines because no server-side spatial query exists under R36's local read path and
// carrying an extension for a query nothing makes is not continuity.
//
// The latitude term of the box is constant; the longitude term is divided by cos(lat), which is
// what keeps the box a box rather than a shape that narrows to nothing near the poles. Both cities
// in the corpus are near 37°N, where the factor is ~1.25 — large enough that omitting it would
// quietly shrink the search and let a duplicate through.
func (s *Store) TreesWithin(ctx context.Context, lat, lon, radiusM float64) ([]NearbyTree, error) {
	const metresPerDegreeLat = 111_320.0
	latDelta := radiusM / metresPerDegreeLat
	cosLat := math.Cos(lat * math.Pi / 180)
	if cosLat < 0.01 {
		cosLat = 0.01
	}
	lonDelta := radiusM / (metresPerDegreeLat * cosLat)

	rows, err := s.pool.Query(ctx, `
		SELECT id, lat, lon, address, species_id, placement, land_context,
		       created_at, updated_at,
		       6371000 * 2 * asin(sqrt(
		           power(sin(radians(lat - $1) / 2), 2) +
		           cos(radians($1)) * cos(radians(lat)) *
		           power(sin(radians(lon - $2) / 2), 2)
		       )) AS distance_m
		  FROM community_trees
		 WHERE deleted_at IS NULL
		   AND lat BETWEEN $1 - $3 AND $1 + $3
		   AND lon BETWEEN $2 - $4 AND $2 + $4
		 ORDER BY distance_m ASC
	`, lat, lon, latDelta, lonDelta)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var candidates []NearbyTree
	for rows.Next() {
		var tree NearbyTree
		if err := rows.Scan(&tree.ID, &tree.Lat, &tree.Lon, &tree.Address, &tree.SpeciesID,
			&tree.Placement, &tree.LandContext, &tree.CreatedAt, &tree.UpdatedAt,
			&tree.DistanceM); err != nil {
			return nil, err
		}
		// The box is a prefilter and admits corners beyond the radius; the haversine is the answer.
		if tree.DistanceM <= radiusM {
			candidates = append(candidates, tree)
		}
	}
	return candidates, rows.Err()
}

// CommunityTreeExists reports whether this exact tree has already been recorded.
//
// `POST /trees` calls it **before** the proximity query. Without that ordering a byte-identical
// retry — the flap-replay case the outbox exists for — runs the 10 m dedupe against the row it
// created moments ago, matches itself at zero metres, and comes back `conflict`. That code is
// non-retryable, so the item fails terminally and the contributor is offered a resolution sheet
// listing their own submission.
func (s *Store) CommunityTreeExists(ctx context.Context, id uuid.UUID) (bool, error) {
	var found bool
	err := s.pool.QueryRow(ctx,
		`SELECT EXISTS (SELECT 1 FROM community_trees WHERE id = $1)`, id).Scan(&found)
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
}

// AddTree inserts a community tree under the client's own id.
func (s *Store) AddTree(ctx context.Context, tree NewCommunityTree, owner Owner) (ApplyOutcome, error) {
	now := s.now()
	tag, err := s.pool.Exec(ctx, `
		INSERT INTO community_trees
		    (id, lat, lon, address, species_id, placement, land_context,
		     user_id, device_id, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $10)
		ON CONFLICT (id) DO NOTHING
	`, tree.ID, tree.Lat, tree.Lon, tree.Address, tree.SpeciesID, tree.Placement, tree.LandContext,
		owner.UserID, owner.DeviceID, now)
	if err != nil {
		return Applied, err
	}
	if tag.RowsAffected() == 0 {
		return Duplicate, nil
	}
	return Applied, nil
}
