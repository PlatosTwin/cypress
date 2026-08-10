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
		 ORDER BY last_visited_at DESC NULLS LAST
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
			&visits, &observations, &measurements, &careEvents); err != nil {
			return nil, err
		}
		// Not nil: this query counted every kind it reports, over the whole set rather than a page,
		// which is the condition E38 attaches to being allowed to state a total.
		entry.Record = map[string]int{
			"visits": visits, "observations": observations,
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
	Photos       []PhotoRecord
	VisitCount   int
	PhotoTallies map[uuid.UUID]int
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
	return TreeCommunity{Photos: photos, VisitCount: visits, PhotoTallies: map[uuid.UUID]int{}}, nil
}

// ── `POST /trees` and the 10 m proximity dedupe ────────────────────────────────────────────────

// NearbyTree is a dedupe candidate.
type NearbyTree struct {
	ID        uuid.UUID
	Lat       float64
	Lon       float64
	Name      string
	DistanceM float64
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
		SELECT id, lat, lon, coalesce(display_name, ''),
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
		if err := rows.Scan(&tree.ID, &tree.Lat, &tree.Lon, &tree.Name, &tree.DistanceM); err != nil {
			return nil, err
		}
		// The box is a prefilter and admits corners beyond the radius; the haversine is the answer.
		if tree.DistanceM <= radiusM {
			candidates = append(candidates, tree)
		}
	}
	return candidates, rows.Err()
}

// AddTree inserts a community tree, deduping on its client key.
func (s *Store) AddTree(ctx context.Context, clientUUID uuid.UUID, lat, lon float64, name string, owner Owner) (uuid.UUID, ApplyOutcome, error) {
	now := s.now()
	id := uuid.New()
	var stored uuid.UUID
	err := s.pool.QueryRow(ctx, `
		INSERT INTO community_trees
		    (id, client_uuid, lat, lon, display_name, user_id, device_id, created_at, updated_at)
		VALUES ($1, $2, $3, $4, nullif($5, ''), $6, $7, $8, $8)
		ON CONFLICT (client_uuid) DO UPDATE SET updated_at = community_trees.updated_at
		RETURNING id
	`, id, clientUUID, lat, lon, name, owner.UserID, owner.DeviceID, now).Scan(&stored)
	if err != nil {
		return uuid.Nil, Applied, err
	}
	if stored != id {
		return stored, Duplicate, nil
	}
	return stored, Applied, nil
}
