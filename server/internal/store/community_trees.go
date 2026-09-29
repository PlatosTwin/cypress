package store

import (
	"context"
	"encoding/json"
	"errors"
	"math"
	"time"

	"github.com/PlatosTwin/cypress/server/internal/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

// ── Community trees: publication, the location chain, the audit log, withdrawal ──────────────────
//
// Migration 007 states the invariants; this file is where the half of them no CHECK can hold is
// held. Everything here runs on the caller's transaction, because each act writes a contribution,
// a chain or cache row and an event, and a window between them is a tree that moved with nobody
// recorded as moving it, or the reverse.

// Actor is who performed an act, for the audit log — not who owns the row.
//
// It differs from Owner in one way that is the reason it exists: a signed-in act carries the
// account **and** the device its session is bound to (`sessions.device_id`, the orchestrator's
// ruling of 2026-09-28), where Owner is exactly one of the two. The device is the one the session
// proved at `POST /auth/oidc`, never an item's own `device_id` claim.
type Actor struct {
	UserID   *uuid.UUID
	DeviceID *uuid.UUID
}

// actorOr falls back to the owner when the caller supplied no actor. Every production path sets
// one; the fallback keeps an older call site from writing an event with no actor at all.
func actorOr(actor Actor, owner Owner) Actor {
	if actor.UserID == nil && actor.DeviceID == nil {
		return Actor(owner)
	}
	return actor
}

// querier is what both a pool and a transaction can do, so the proximity query runs inside the
// transaction that is about to move a pin as well as outside it for `POST /trees`.
type querier interface {
	Query(ctx context.Context, sql string, args ...any) (pgx.Rows, error)
	QueryRow(ctx context.Context, sql string, args ...any) pgx.Row
	Exec(ctx context.Context, sql string, args ...any) (pgconn.CommandTag, error)
}

var (
	// ErrTreeNotFound is a community tree this service does not hold for the act: never received
	// (its `add_tree` conflicted), withdrawn by its adder, taken down, or erased. `not_found`.
	ErrTreeNotFound = errors.New("community tree not found")
	// ErrNotTheAdder is an act only the adder may perform, from somebody else — including from
	// anybody at all once the tree is anonymized. `forbidden`.
	ErrNotTheAdder = errors.New("only the tree's adder may do this")
	// ErrTooCloseToAnotherTree is a pin moved to within 10 m of another tree the caller can see.
	// `conflict`.
	ErrTooCloseToAnotherTree = errors.New("another tree is recorded within the dedupe radius")
	// ErrOthersBuiltOnTree is an adder's withdrawal of a tree somebody else has met — a live visit,
	// observation, measurement or care event, or a photograph (decision 8, `othersHaveBuiltOn`).
	// `conflict`: only an operator takedown removes it now.
	ErrOthersBuiltOnTree = errors.New("another identity has a visit or photo on this tree")
	// ErrCorrectionIDReused is a correction id already used for a different tree. `validation_failed`.
	ErrCorrectionIDReused = errors.New("that correction id already names another tree's location")
)

// ── Publication ─────────────────────────────────────────────────────────────────────────────────

// accountLicense reads `users.license_version`, whose NULL is a declined consent (001), and takes a
// share lock on the row for the rest of the caller's transaction.
//
// **`FOR SHARE` is what makes "published only while accepted" true under concurrency.** Without it,
// a signed-in add that read "declined" could commit after a concurrent acceptance whose publish
// sweep ran while the add was still uncommitted and invisible to it — leaving the tree unpublished
// under an account that has accepted, until some later acceptance (review of #187, F6). With it,
// `RecordLicenseConsent`'s `UPDATE users` waits for the add to commit, so its sweep sees the tree;
// or the add waits for the consent to commit, and reads the answer it recorded. The lock is on one
// row the transaction already references through a foreign key, and nothing else in the service
// updates `users` inside a transaction that also writes a community tree, so it adds a wait and no
// deadlock.
func accountLicense(ctx context.Context, q querier, userID uuid.UUID) (*string, error) {
	var version *string
	err := q.QueryRow(ctx, `SELECT license_version FROM users WHERE id = $1 FOR SHARE`, userID).Scan(&version)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	return version, err
}

// publicationStamp is `published_at` for a tree this owner is inserting, and the license version it
// is published under: now for an account that has accepted the license (decision 1: "visible to
// everyone … instantly"), nil for an account that has declined it (decision 7) and for a device
// (decision 1: "stays on the adder's phone until they sign in"). This is one of the three writers of
// `published_at` outside 007's backfill; 007's header names the other two.
func publicationStamp(ctx context.Context, q querier, owner Owner, now time.Time) (*time.Time, *string, error) {
	if owner.UserID == nil {
		return nil, nil, nil
	}
	version, err := accountLicense(ctx, q, *owner.UserID)
	if err != nil || version == nil {
		return nil, nil, err
	}
	return &now, version, nil
}

// publishedEvent is the `published` event every publication writes. Its `after` carries the license
// version the account had accepted at that moment — decision 10 makes the license one-way, so
// "accepted at publication" is the invariant, and `users` keeps only the current answer. The event
// is where the answer at the time is kept.
func publishedEvent(tree uuid.UUID, version string, actor Actor, at time.Time) event {
	return event{TreeID: tree, Kind: "published", Actor: actor, OccurredAt: at, After: position{LicenseVersion: &version}}
}

// publishAccountTrees publishes every live, unpublished tree an account owns, and writes a
// `published` event for each. It runs when the account accepts the license (decision 7: "they go
// live if/when the account later accepts").
//
// There is no inverse. Decision 10: the license is one-way — a later decline does not unpublish
// anything; it only keeps trees added after it private.
func publishAccountTrees(ctx context.Context, tx pgx.Tx, userID uuid.UUID, version string, actor Actor, now time.Time) error {
	ids, err := collectIDs(tx.Query(ctx, `
		UPDATE community_trees
		   SET published_at = $2, updated_at = $2
		 WHERE user_id = $1 AND published_at IS NULL AND deleted_at IS NULL
		RETURNING id
	`, userID, now))
	if err != nil {
		return err
	}
	for _, id := range ids {
		if err := writeEvent(ctx, tx, publishedEvent(id, version, actor, now), now); err != nil {
			return err
		}
	}
	return nil
}

// claimCommunityTrees is `ClaimDevice`'s tree sweep: the device's trees move onto the account and,
// if the account has accepted the license, go live in the same statement (decision 1: "then it goes
// live for everyone at once"). The actor is the account and the device being claimed.
func claimCommunityTrees(ctx context.Context, tx pgx.Tx, deviceID, userID uuid.UUID, now time.Time) error {
	version, err := accountLicense(ctx, tx, userID)
	if err != nil {
		return err
	}
	accepted := version != nil
	rows, err := tx.Query(ctx, `
		UPDATE community_trees
		   SET user_id = $1, device_id = NULL, updated_at = $2,
		       published_at = CASE WHEN $4 AND deleted_at IS NULL THEN $2::timestamptz ELSE NULL END
		 WHERE device_id = $3 AND user_id IS NULL
		RETURNING id, published_at IS NOT NULL
	`, userID, now, deviceID, accepted)
	if err != nil {
		return err
	}
	var published []uuid.UUID
	for rows.Next() {
		var id uuid.UUID
		var isPublished bool
		if err := rows.Scan(&id, &isPublished); err != nil {
			rows.Close()
			return err
		}
		if isPublished {
			published = append(published, id)
		}
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return err
	}
	actor := Actor{UserID: &userID, DeviceID: &deviceID}
	for _, id := range published {
		if err := writeEvent(ctx, tx, publishedEvent(id, *version, actor, now), now); err != nil {
			return err
		}
	}
	return nil
}

// ── Insert ──────────────────────────────────────────────────────────────────────────────────────

// newTreeAct is what an insert needs beyond the tree itself.
type newTreeAct struct {
	Owner      Owner
	Actor      Actor
	ClientUUID *uuid.UUID
	OccurredAt time.Time
}

// insertCommunityTree materializes an added tree, its root location, its `added` event and — when
// the owner publishes — its `published` event, in the caller's transaction.
//
// `ON CONFLICT (id) DO NOTHING`, and nothing else written, when the tree is already here: the same
// act queued twice. Whoever got here first is the row. A tree the erase door tombstoned is treated
// the same way, so a late `add_tree` or `POST /trees` cannot bring an erased tree back.
//
// A tree whose adder already withdrew it (the withdrawal drained first; the add was in backoff) is
// born withdrawn — see `treeWasWithdrawnBy`.
func insertCommunityTree(ctx context.Context, tx pgx.Tx, tree NewCommunityTree, act newTreeAct, now time.Time) (bool, error) {
	var tombstoned bool
	if err := tx.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM withdrawn_community_trees WHERE id = $1)`,
		tree.ID).Scan(&tombstoned); err != nil {
		return false, err
	}
	if tombstoned {
		return false, nil
	}

	publishedAt, licenseVersion, err := publicationStamp(ctx, tx, act.Owner, now)
	if err != nil {
		return false, err
	}
	tag, err := tx.Exec(ctx, `
		INSERT INTO community_trees
		    (id, lat, lon, address, species_id, placement, land_context, location_accuracy_m,
		     user_id, device_id, published_at, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $12)
		ON CONFLICT (id) DO NOTHING
	`, tree.ID, tree.Lat, tree.Lon, tree.Address, tree.SpeciesID, tree.Placement, tree.LandContext,
		tree.LocationAccuracyM, act.Owner.UserID, act.Owner.DeviceID, publishedAt, now)
	if err != nil {
		return false, err
	}
	if tag.RowsAffected() == 0 {
		return false, nil
	}

	actor := actorOr(act.Actor, act.Owner)
	if _, err := tx.Exec(ctx, `
		INSERT INTO community_tree_locations
		    (id, tree_id, lat, lon, placement, location_accuracy_m, contribution_client_uuid,
		     actor_user_id, actor_device_id, occurred_at, recorded_at)
		VALUES ($1, $1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
	`, tree.ID, tree.Lat, tree.Lon, tree.Placement, tree.LocationAccuracyM, act.ClientUUID,
		actor.UserID, actor.DeviceID, act.OccurredAt, now); err != nil {
		return false, err
	}
	if err := writeEvent(ctx, tx, event{
		ID: &tree.ID, TreeID: tree.ID, Kind: "added", ClientUUID: act.ClientUUID, Actor: actor,
		OccurredAt: act.OccurredAt,
		After: func() position {
			p := at(tree.Lat, tree.Lon, tree.Placement, tree.LocationAccuracyM)
			p.SpeciesID = tree.SpeciesID
			return p
		}(),
	}, now); err != nil {
		return false, err
	}
	if publishedAt != nil {
		if err := writeEvent(ctx, tx, publishedEvent(tree.ID, *licenseVersion, actor, now), now); err != nil {
			return false, err
		}
	}

	withdrawn, err := treeWasWithdrawnBy(ctx, tx, tree.ID, act.Owner)
	if err != nil {
		return false, err
	}
	if withdrawn {
		if err := markTreeDeleted(ctx, tx, tree.ID, "withdrawn", nil, actor, now, now); err != nil {
			return false, err
		}
	}
	return true, nil
}

// treeWasWithdrawnBy reports whether this owner has already sent a `tree_withdrawal` for this tree.
//
// `measurementWasWithdrawn`'s argument, one table over: the outbox drains due items in order, an
// item in backoff is not due, so a withdrawal can be committed before the `add_tree` it takes back.
// The withdrawal answered `applied` (there was nothing here to take down); without this the add
// would then publish a tree its adder had already withdrawn. Owner-matched, so a stranger who
// guessed an id cannot pre-empt somebody else's tree.
func treeWasWithdrawnBy(ctx context.Context, tx pgx.Tx, treeID uuid.UUID, owner Owner) (bool, error) {
	var found bool
	err := tx.QueryRow(ctx, `
		SELECT EXISTS (
		    SELECT 1 FROM contributions
		     WHERE kind = 'tree_withdrawal' AND tree_uuid = $1 AND deleted_at IS NULL
		       AND (($2::uuid IS NOT NULL AND user_id = $2) OR ($3::uuid IS NOT NULL AND device_id = $3)))
	`, treeID, owner.UserID, owner.DeviceID).Scan(&found)
	return found, err
}

// ── Reads the write path needs ──────────────────────────────────────────────────────────────────

// treeRow is the part of a community tree an act's authority check reads.
type treeRow struct {
	UserID       *uuid.UUID
	DeviceID     *uuid.UUID
	SpeciesID    *uuid.UUID
	AnonymizedAt *time.Time
	DeletedAt    *time.Time
}

// isAddedBy is §4's rule: the account that owns it, or — for a caller holding a device credential —
// the device that owns it. An anonymized tree has neither, so it is nobody's (the anonymized
// dispute's rule, `disputes.go`).
func (t treeRow) isAddedBy(owner Owner) bool {
	if t.AnonymizedAt != nil {
		return false
	}
	if owner.UserID != nil {
		return t.UserID != nil && *t.UserID == *owner.UserID
	}
	return owner.DeviceID != nil && t.DeviceID != nil && *t.DeviceID == *owner.DeviceID
}

// lockTree reads a tree FOR UPDATE, so two acts on one tree serialize. ErrTreeNotFound when absent.
func lockTree(ctx context.Context, tx pgx.Tx, id uuid.UUID) (treeRow, error) {
	var row treeRow
	err := tx.QueryRow(ctx, `
		SELECT user_id, device_id, species_id, anonymized_at, deleted_at
		  FROM community_trees WHERE id = $1 FOR UPDATE
	`, id).Scan(&row.UserID, &row.DeviceID, &row.SpeciesID, &row.AnonymizedAt, &row.DeletedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return treeRow{}, ErrTreeNotFound
	}
	return row, err
}

// treesWithin is the 10 m proximity query, scoped to what the viewer can see (§3F): published trees,
// and the viewer's own. Another device's unpublished tree was a candidate before 007 — a location
// leak through `POST /trees`' candidate list, and a `conflict` against a tree nobody could see.
//
// `excluding` leaves one tree out, so a moved pin is not a duplicate of itself.
func treesWithin(ctx context.Context, q querier, lat, lon, radiusM float64, viewer Owner, excluding *uuid.UUID) ([]NearbyTree, error) {
	const metresPerDegreeLat = 111_320.0
	latDelta := radiusM / metresPerDegreeLat
	cosLat := math.Cos(lat * math.Pi / 180)
	if cosLat < 0.01 {
		cosLat = 0.01
	}
	lonDelta := radiusM / (metresPerDegreeLat * cosLat)

	rows, err := q.Query(ctx, `
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
		   AND (published_at IS NOT NULL
		        OR ($5::uuid IS NOT NULL AND user_id = $5)
		        OR ($6::uuid IS NOT NULL AND device_id = $6))
		   AND ($7::uuid IS NULL OR id <> $7)
		 ORDER BY distance_m ASC
	`, lat, lon, latDelta, lonDelta, viewer.UserID, viewer.DeviceID, excluding)
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

// builtOnKinds are the contribution kinds that mean somebody met the tree: a visit, an
// observation, a measurement or a care event. They are the only contributions that count as
// "built on" (below). The set is the same as `MetSpeciesKinds` in `store/reads.go` on #184, which
// is unmerged; the two should become one constant when #184 and this PR are both on main.
var builtOnKinds = []string{"visit", "observation", "measurement", "care_event"}

// othersHaveBuiltOn reports whether any identity other than `self` has met the tree: a live
// contribution of one of `builtOnKinds`, or a live photograph. It is decision 8's condition (the
// adder may withdraw only while this is false) and decision 6's (the erase door anonymizes rather
// than deletes while it is true).
//
// The owner's own words for both decisions were "if anyone else has a visit or photo on the
// tree", and the orchestrator's ruling after #187's fix round holds the code to them. Favorites,
// photo votes, private reminders, species statements, reports, disputes and review flags are not
// a visit or a photo, and do not count.
//
// "Live" means not deleted. A withdrawn measurement is deleted by its withdrawal, so it does not
// count. A photograph an operator rejected is not live, and neither is one whose bytes never
// arrived: that is a reservation nobody can see. An anonymized row is somebody's work with the
// name taken off, so it counts.
func othersHaveBuiltOn(ctx context.Context, q querier, treeID uuid.UUID, self Owner) (bool, error) {
	var found bool
	err := q.QueryRow(ctx, `
		SELECT EXISTS (
		    SELECT 1 FROM contributions c
		     WHERE c.tree_uuid = $1 AND c.deleted_at IS NULL
		       AND c.kind = ANY($4::text[])
		       -- coalesce, because a NULL owner column compares NULL and NOT NULL is NULL, which
		       -- would drop exactly the anonymized rows this must count.
		       AND NOT coalesce(($2::uuid IS NOT NULL AND c.user_id = $2)
		                     OR ($3::uuid IS NOT NULL AND c.device_id = $3), false)
		) OR EXISTS (
		    SELECT 1 FROM photos p
		     WHERE p.tree_uuid = $1 AND p.deleted_at IS NULL AND p.moderation_state <> 'rejected'
		       AND p.bytes_received_at IS NOT NULL
		       AND NOT coalesce(($2::uuid IS NOT NULL AND p.user_id = $2)
		                     OR ($3::uuid IS NOT NULL AND p.device_id = $3), false)
		)
	`, treeID, self.UserID, self.DeviceID, builtOnKinds).Scan(&found)
	return found, err
}

// ── The location chain ──────────────────────────────────────────────────────────────────────────

// LocationCorrection is a `location_correction` item's materialized half (§3A).
type LocationCorrection struct {
	// ID is `TreeLocationCorrection.id`: the chain row's id and the event's.
	ID        uuid.UUID
	TreeID    uuid.UUID
	Lat       float64
	Lon       float64
	Placement string
	AccuracyM *float64
}

// chainRow is one row of `community_tree_locations`.
type chainRow struct {
	ID         uuid.UUID
	OccurredAt time.Time
	Lat        float64
	Lon        float64
	Placement  string
	AccuracyM  *float64
}

func (c chainRow) position() position {
	return at(c.Lat, c.Lon, c.Placement, c.AccuracyM)
}

func scanChainRow(row pgx.Row) (*chainRow, error) {
	var r chainRow
	err := row.Scan(&r.ID, &r.OccurredAt, &r.Lat, &r.Lon, &r.Placement, &r.AccuracyM)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &r, nil
}

// applyLocationCorrection appends a correction to the tree's chain (decision 2: a correction
// supersedes; the chain is append-only).
//
// Ordering is §3A's: the head is the row with the greatest `(occurred_at, id)`. A correction that
// sorts after the head becomes the head — it runs the 10 m dedupe and moves the tree's cached
// position. One that sorts before it arrived late (the outbox in backoff), so it is spliced into
// the chain **already superseded**, skips the dedupe (it never becomes the position anybody sees),
// and leaves the cache alone. Either way it writes a `location_corrected` event whose `before` is
// the row it follows.
func applyLocationCorrection(ctx context.Context, tx pgx.Tx, c LocationCorrection, act newTreeAct, now time.Time) error {
	tree, err := lockTree(ctx, tx, c.TreeID)
	if err != nil {
		return err
	}
	if !tree.isAddedBy(act.Owner) {
		return ErrNotTheAdder
	}
	if tree.DeletedAt != nil {
		return ErrTreeNotFound
	}

	// The same correction queued twice under two item keys. The contribution dedupe could not see
	// it (different `client_uuid`), and the chain row is already here: a success that changes
	// nothing, exactly as `insertCommunityTree` treats a tree sent twice.
	var existingTree uuid.UUID
	err = tx.QueryRow(ctx, `SELECT tree_id FROM community_tree_locations WHERE id = $1`, c.ID).Scan(&existingTree)
	switch {
	case err == nil && existingTree == c.TreeID:
		return nil
	case err == nil:
		return ErrCorrectionIDReused
	case !errors.Is(err, pgx.ErrNoRows):
		return err
	}

	head, err := scanChainRow(tx.QueryRow(ctx, `
		SELECT id, occurred_at, lat, lon, placement, location_accuracy_m
		  FROM community_tree_locations
		 WHERE tree_id = $1 AND superseded_by IS NULL
		 FOR UPDATE
	`, c.TreeID))
	if err != nil {
		return err
	}
	if head == nil {
		// 007 writes a root for every tree and every insert writes one, so this is a chain that lost
		// its head — not something to paper over by starting a new one.
		return errors.New("community tree has no head location")
	}

	actor := actorOr(act.Actor, act.Owner)
	isNewHead := act.OccurredAt.After(head.OccurredAt) ||
		(act.OccurredAt.Equal(head.OccurredAt) && uuidLess(head.ID, c.ID))

	var before position
	if isNewHead {
		nearby, err := treesWithin(ctx, tx, c.Lat, c.Lon, ProximityDedupeRadiusM, act.Owner, &c.TreeID)
		if err != nil {
			return err
		}
		if len(nearby) > 0 {
			return ErrTooCloseToAnotherTree
		}
		// The old head stops being one before the new row exists: the head index is not
		// deferrable, the foreign key is.
		if _, err := tx.Exec(ctx, `
			UPDATE community_tree_locations SET superseded_by = $2 WHERE id = $1
		`, head.ID, c.ID); err != nil {
			return err
		}
		if err := insertChainRow(ctx, tx, c, act, actor, nil, now); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `
			UPDATE community_trees
			   SET lat = $2, lon = $3, placement = $4, location_accuracy_m = $5, updated_at = $6
			 WHERE id = $1
		`, c.TreeID, c.Lat, c.Lon, c.Placement, c.AccuracyM, now); err != nil {
			return err
		}
		before = head.position()
	} else {
		predecessor, err := scanChainRow(tx.QueryRow(ctx, `
			SELECT id, occurred_at, lat, lon, placement, location_accuracy_m
			  FROM community_tree_locations
			 WHERE tree_id = $1 AND (occurred_at, id) < ($2, $3)
			 ORDER BY occurred_at DESC, id DESC LIMIT 1
		`, c.TreeID, act.OccurredAt, c.ID))
		if err != nil {
			return err
		}
		successor, err := scanChainRow(tx.QueryRow(ctx, `
			SELECT id, occurred_at, lat, lon, placement, location_accuracy_m
			  FROM community_tree_locations
			 WHERE tree_id = $1 AND (occurred_at, id) > ($2, $3)
			 ORDER BY occurred_at ASC, id ASC LIMIT 1
		`, c.TreeID, act.OccurredAt, c.ID))
		if err != nil {
			return err
		}
		if successor == nil {
			return errors.New("a correction older than the head has nothing after it")
		}
		if err := insertChainRow(ctx, tx, c, act, actor, &successor.ID, now); err != nil {
			return err
		}
		if predecessor != nil {
			if _, err := tx.Exec(ctx, `
				UPDATE community_tree_locations SET superseded_by = $2 WHERE id = $1
			`, predecessor.ID, c.ID); err != nil {
				return err
			}
			before = predecessor.position()
		}
	}

	return writeEvent(ctx, tx, event{
		ID: &c.ID, TreeID: c.TreeID, Kind: "location_corrected", ClientUUID: act.ClientUUID,
		Actor: actor, OccurredAt: act.OccurredAt, Before: before,
		After: at(c.Lat, c.Lon, c.Placement, c.AccuracyM),
	}, now)
}

func insertChainRow(ctx context.Context, tx pgx.Tx, c LocationCorrection, act newTreeAct, actor Actor, supersededBy *uuid.UUID, now time.Time) error {
	_, err := tx.Exec(ctx, `
		INSERT INTO community_tree_locations
		    (id, tree_id, lat, lon, placement, location_accuracy_m, contribution_client_uuid,
		     actor_user_id, actor_device_id, occurred_at, recorded_at, superseded_by)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
	`, c.ID, c.TreeID, c.Lat, c.Lon, c.Placement, c.AccuracyM, act.ClientUUID,
		actor.UserID, actor.DeviceID, act.OccurredAt, now, supersededBy)
	return err
}

// uuidLess is Postgres' `uuid` ordering (bytewise), so the Go and SQL halves of the tie-break agree.
func uuidLess(a, b uuid.UUID) bool {
	for i := range a {
		if a[i] != b[i] {
			return a[i] < b[i]
		}
	}
	return false
}

// ── Species, arm 1 ──────────────────────────────────────────────────────────────────────────────

// SpeciesStatement is a `species_claim` or `species_correction` read for materialization (§3B).
type SpeciesStatement struct {
	TreeID    uuid.UUID
	SpeciesID uuid.UUID
}

// materializeSpecies applies R45's arm 1 on the server: the adder of a community tree names or
// corrects its species, and the tree's `species_id` — a read cache — follows.
//
// It never refuses. Anybody else's statement, a statement about a tree this service does not hold
// as a live community tree, a claim on a tree that already has a species, and a correction older
// than the last one applied are all recorded (the contribution row) and change nothing — which is
// the pre-007 behaviour for every species act, so a lead-arm correction never becomes a red row.
func materializeSpecies(ctx context.Context, tx pgx.Tx, kind string, s SpeciesStatement, act newTreeAct, now time.Time) error {
	tree, err := lockTree(ctx, tx, s.TreeID)
	if errors.Is(err, ErrTreeNotFound) {
		return nil
	}
	if err != nil {
		return err
	}
	if tree.DeletedAt != nil || !tree.isAddedBy(act.Owner) {
		return nil
	}

	eventKind := "species_corrected"
	if kind == "species_claim" {
		if tree.SpeciesID != nil {
			return nil
		}
		eventKind = "species_named"
	} else {
		var newer bool
		if err := tx.QueryRow(ctx, `
			SELECT EXISTS (SELECT 1 FROM community_tree_events
			                WHERE tree_id = $1 AND kind IN ('species_named', 'species_corrected')
			                  AND occurred_at > $2)
		`, s.TreeID, act.OccurredAt).Scan(&newer); err != nil {
			return err
		}
		if newer {
			return nil
		}
	}

	if _, err := tx.Exec(ctx, `
		UPDATE community_trees SET species_id = $2, updated_at = $3 WHERE id = $1
	`, s.TreeID, s.SpeciesID, now); err != nil {
		return err
	}
	return writeEvent(ctx, tx, event{
		TreeID: s.TreeID, Kind: eventKind, ClientUUID: act.ClientUUID,
		Actor: actorOr(act.Actor, act.Owner), OccurredAt: act.OccurredAt,
		Before: position{SpeciesID: tree.SpeciesID}, After: position{SpeciesID: &s.SpeciesID},
	}, now)
}

// ── Withdrawal and takedown ─────────────────────────────────────────────────────────────────────

// withdrawCommunityTree is decision 8: the adder withdraws a tree for everyone, while nobody else
// has built on it.
//
// **Soft, through `deleted_at`, and not the erase door's delete-and-tombstone.** The event this act
// must write lives in `community_tree_events`, which cascades from the tree — a hard delete would
// take the record of the withdrawal away with the thing withdrawn. Every read that serves a
// community tree already filters `deleted_at` (`TreesWithin`, `MapMembership`), and S2's tile
// delta reports it as withdrawn exactly as it reports a tombstone.
//
// Answers, in order: a tree this service never held is a success that changes nothing (its add
// may still be in the adder's queue — `treeWasWithdrawnBy` makes that add arrive withdrawn), and a
// tree the erase door tombstoned is `ErrTreeNotFound`; not the adder is `ErrNotTheAdder`; already
// withdrawn or taken down is a success that changes nothing; somebody else's live work on it is
// `ErrOthersBuiltOnTree`.
func withdrawCommunityTree(ctx context.Context, tx pgx.Tx, treeID uuid.UUID, act newTreeAct, now time.Time) error {
	tree, err := lockTree(ctx, tx, treeID)
	if errors.Is(err, ErrTreeNotFound) {
		var tombstoned bool
		if err := tx.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM withdrawn_community_trees WHERE id = $1)`,
			treeID).Scan(&tombstoned); err != nil {
			return err
		}
		if tombstoned {
			return ErrTreeNotFound
		}
		return nil
	}
	if err != nil {
		return err
	}
	if !tree.isAddedBy(act.Owner) {
		return ErrNotTheAdder
	}
	if tree.DeletedAt != nil {
		return nil
	}
	built, err := othersHaveBuiltOn(ctx, tx, treeID, act.Owner)
	if err != nil {
		return err
	}
	if built {
		return ErrOthersBuiltOnTree
	}
	return markTreeDeleted(ctx, tx, treeID, "withdrawn", act.ClientUUID, actorOr(act.Actor, act.Owner), act.OccurredAt, now)
}

func markTreeDeleted(ctx context.Context, tx pgx.Tx, treeID uuid.UUID, kind string, clientUUID *uuid.UUID, actor Actor, occurredAt, now time.Time) error {
	if _, err := tx.Exec(ctx, `
		UPDATE community_trees SET deleted_at = $2, updated_at = $2 WHERE id = $1
	`, treeID, now); err != nil {
		return err
	}
	return writeEvent(ctx, tx, event{
		TreeID: treeID, Kind: kind, ClientUUID: clientUUID, Actor: actor, OccurredAt: occurredAt,
	}, now)
}

// TakeDownCommunityTree is the operator takedown (R72 ruling 5: "the way down ships with the way
// up"). It is the only way a tree comes down once somebody else has built on it (decision 8).
//
// `deleted_at`, for the reason `withdrawCommunityTree` gives, and a `taken_down` event with no actor:
// the operator is not an account or a device of this service. Idempotent: a tree already down is a
// success. ErrNotFound for an id that names no community tree.
func (s *Store) TakeDownCommunityTree(ctx context.Context, id uuid.UUID) error {
	return s.Tx(ctx, func(tx pgx.Tx) error {
		tree, err := lockTree(ctx, tx, id)
		if errors.Is(err, ErrTreeNotFound) {
			return ErrNotFound
		}
		if err != nil {
			return err
		}
		if tree.DeletedAt != nil {
			return nil
		}
		now := s.now()
		return markTreeDeleted(ctx, tx, id, "taken_down", nil, Actor{}, now, now)
	})
}

// ── Account deletion ────────────────────────────────────────────────────────────────────────────

// deleteAccountTrees applies the two doors to the trees an account added (§2, decision 6), and takes
// the account's name off the chain and the audit log. It must run before `devices.user_id` is
// nulled (the actor sweep finds the account's devices through it) and before `DELETE FROM users`
// (whose `ON DELETE SET NULL` on a tree nobody anonymized first would violate
// `community_trees_owner` and roll the whole deletion back — deliberately loud).
//
//   - An **unpublished** tree is deleted and tombstoned under both doors. It was never visible to
//     anybody but its adder (decision 7), and anonymizing it would leave a row no account can ever
//     publish, move, withdraw or erase.
//   - A published tree under `leaveRecords` is anonymized: ownerless, still published, and nobody
//     may move or withdraw it afterwards.
//   - A published tree under `eraseEverything` is deleted and tombstoned — unless another identity
//     has met it (`othersHaveBuiltOn`: a visit-like contribution or a photograph), when it is
//     anonymized instead (decision 6:
//     "a tree the erasing account added stays, anonymized, if anyone else has a live visit/
//     contribution or photo on it"). This runs after the account's own contributions and photos
//     are gone, so what remains is other people's.
func deleteAccountTrees(ctx context.Context, tx pgx.Tx, userID uuid.UUID, choice DeletionChoice, now time.Time) (anonymized, deleted int, err error) {
	type owned struct {
		ID        uuid.UUID
		Published bool
	}
	rows, err := tx.Query(ctx, `
		SELECT id, published_at IS NOT NULL FROM community_trees WHERE user_id = $1 FOR UPDATE
	`, userID)
	if err != nil {
		return 0, 0, err
	}
	var trees []owned
	for rows.Next() {
		var tree owned
		if err := rows.Scan(&tree.ID, &tree.Published); err != nil {
			rows.Close()
			return 0, 0, err
		}
		trees = append(trees, tree)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return 0, 0, err
	}

	self := UserOwner(userID)
	for _, tree := range trees {
		keep := false
		if tree.Published {
			switch choice {
			case LeaveRecords:
				keep = true
			case EraseEverything:
				keep, err = othersHaveBuiltOn(ctx, tx, tree.ID, self)
				if err != nil {
					return 0, 0, err
				}
			}
		}
		if keep {
			if _, err := tx.Exec(ctx, `
				UPDATE community_trees
				   SET user_id = NULL, device_id = NULL, anonymized_at = $2, updated_at = $2
				 WHERE id = $1
			`, tree.ID, now); err != nil {
				return 0, 0, err
			}
			anonymized++
			continue
		}
		if _, err := tx.Exec(ctx, `
			INSERT INTO withdrawn_community_trees (id, withdrawn_at) VALUES ($1, $2)
			ON CONFLICT (id) DO NOTHING
		`, tree.ID, now); err != nil {
			return 0, 0, err
		}
		if _, err := tx.Exec(ctx, `DELETE FROM community_trees WHERE id = $1`, tree.ID); err != nil {
			return 0, 0, err
		}
		deleted++
	}

	// The account's name comes off every chain row and event it or any device it claimed performed,
	// on every tree — its own and, for species or publication events, nobody else's (only the adder
	// may act, so in practice these are its own trees). Full detail was the server's to keep while
	// the account existed (decision 4), not after.
	for _, table := range []string{"community_tree_locations", "community_tree_events"} {
		if _, err := tx.Exec(ctx, `
			UPDATE `+table+`
			   SET actor_user_id = NULL, actor_device_id = NULL, anonymized_at = coalesce(anonymized_at, $2)
			 WHERE actor_user_id = $1
			    OR actor_device_id IN (SELECT id FROM devices WHERE user_id = $1)
		`, userID, now); err != nil {
			return 0, 0, err
		}
	}
	return anonymized, deleted, nil
}

// ── The audit log ───────────────────────────────────────────────────────────────────────────────

// position is an event's `before` / `after`: whichever of these the act moved. Nil fields are
// omitted, so a species event carries only the species and a move only the position.
type position struct {
	Lat       *float64   `json:"lat,omitempty"`
	Lon       *float64   `json:"lon,omitempty"`
	Placement string     `json:"placement,omitempty"`
	AccuracyM *float64   `json:"location_accuracy_m,omitempty"`
	SpeciesID *uuid.UUID `json:"species_id,omitempty"`
	// LicenseVersion is set only on a `published` event's `after`: the license the account had
	// accepted at the moment of publication (decision 10). 007's backfill writes the same key.
	LicenseVersion *string `json:"license_version,omitempty"`
}

// at is a position with a place in it. Pointers rather than values so a tree on the equator or the
// prime meridian is not written as a tree with no position.
func at(lat, lon float64, placement string, accuracyM *float64) position {
	return position{Lat: &lat, Lon: &lon, Placement: placement, AccuracyM: accuracyM}
}

func (p position) isZero() bool {
	return p.Lat == nil && p.Lon == nil && p.Placement == "" && p.AccuracyM == nil && p.SpeciesID == nil &&
		p.LicenseVersion == nil
}

type event struct {
	// ID is the event's own id when the act has one (the tree's for `added`, the correction's for
	// `location_corrected`); otherwise one is minted.
	ID         *uuid.UUID
	TreeID     uuid.UUID
	Kind       string
	ClientUUID *uuid.UUID
	Actor      Actor
	OccurredAt time.Time
	Before     position
	After      position
}

func writeEvent(ctx context.Context, tx pgx.Tx, e event, now time.Time) error {
	id := uuid.New()
	if e.ID != nil {
		id = *e.ID
	}
	var before, after []byte
	var err error
	if !e.Before.isZero() {
		if before, err = json.Marshal(e.Before); err != nil {
			return err
		}
	}
	if !e.After.isZero() {
		if after, err = json.Marshal(e.After); err != nil {
			return err
		}
	}
	_, err = tx.Exec(ctx, `
		INSERT INTO community_tree_events
		    (id, tree_id, kind, contribution_client_uuid, actor_user_id, actor_device_id,
		     occurred_at, recorded_at, before, after)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9::jsonb, $10::jsonb)
	`, id, e.TreeID, e.Kind, e.ClientUUID, e.Actor.UserID, e.Actor.DeviceID, e.OccurredAt, now,
		nullableJSON(before), nullableJSON(after))
	return err
}

func nullableJSON(raw []byte) *string {
	if raw == nil {
		return nil
	}
	text := string(raw)
	return &text
}

func collectIDs(rows pgx.Rows, err error) ([]uuid.UUID, error) {
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
