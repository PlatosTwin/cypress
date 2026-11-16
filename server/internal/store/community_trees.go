package store

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
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

// querier is what both a pool and a transaction can do, so a read helper can run inside a
// transaction as well as outside one.
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
	if err != nil || version == nil || !IsKnownLicenseVersion(*version) {
		// A stored value that is not a known version is not an acceptance, whenever it was written.
		return nil, err
	}
	return version, nil
}

// knownLicenseVersions is every license version an acceptance may name (the #187 verification's L2).
//
// **Only a real, known version publishes anything.** Before this, `consent` took any string, so a
// `license_version` of `""` (or a typo, or a client bug) published the account's trees and wrote
// `""` into the `published` event as the license they went out under — and that event is decision
// 10's whole record of "accepted at publication". The one version is the client's
// `LicenseConsent.currentVersion` (`Cypress/Core/AccountLinkRecord.swift`); the api package's
// `TestTheServerKnowsTheClientsLicenseVersion` reads it out of the Swift source, so a client that
// moves the constant goes red here instead of every new acceptance silently becoming a decline.
// When legal review changes the license, the new version is added here in the same change.
var knownLicenseVersions = map[string]bool{"odbl-1.0": true}

// IsKnownLicenseVersion reports whether a version string names a license this service publishes
// under.
func IsKnownLicenseVersion(version string) bool { return knownLicenseVersions[version] }

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

// publishTrees is what every publication does after setting `published_at`: it marks each tree's
// head location `was_public` and writes the `published` event, in the caller's transaction.
//
// The event's `after` carries two things. The license version the account had accepted at that
// moment — decision 10 makes the license one-way, so "accepted at publication" is the invariant,
// and `users` keeps only the current answer; the event is where the answer at the time is kept.
// And the position the tree stood at when it went public — decision 13: history starts at going
// live, so this event, not `added`, is the public record's "added", and it says where.
//
// The head is the only row marked: rows it superseded were positions the tree held while private,
// and they stay the adder's (decision 13). The UPDATE only ever turns `was_public` on, once, the
// same set-once shape as `superseded_by`; no position is rewritten.
func publishTrees(ctx context.Context, tx pgx.Tx, ids []uuid.UUID, version string, actor Actor, now time.Time) error {
	for _, id := range ids {
		var lat, lon float64
		var placement string
		var accuracyM *float64
		if err := tx.QueryRow(ctx, `
			UPDATE community_tree_locations SET was_public = true
			 WHERE tree_id = $1 AND superseded_by IS NULL
			RETURNING lat, lon, placement, location_accuracy_m
		`, id).Scan(&lat, &lon, &placement, &accuracyM); err != nil {
			return fmt.Errorf("publishing %s: its head location: %w", id, err)
		}
		after := at(lat, lon, placement, accuracyM)
		after.LicenseVersion = &version
		if err := writeEvent(ctx, tx, event{
			TreeID: id, Kind: "published", Actor: actor, OccurredAt: now, After: after, Public: true,
		}, now); err != nil {
			return err
		}
	}
	return nil
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
	return publishTrees(ctx, tx, ids, version, actor, now)
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
	if len(published) == 0 {
		return nil
	}
	return publishTrees(ctx, tx, published, *version, Actor{UserID: &userID, DeviceID: &deviceID}, now)
}

// ── The "added" day ─────────────────────────────────────────────────────────────────────────────

// earliestAddedDay is the first day a community tree can have been added: the day this project
// began (its first commit, 2026-07-21). No build of the app existed before it, so an earlier day is
// a phone clock that was wrong. Migration 008's backfill spells the same date.
var earliestAddedDay = time.Date(2026, 7, 21, 0, 0, 0, 0, time.UTC)

// utcDay is midnight UTC of the instant's UTC date.
func utcDay(t time.Time) time.Time {
	year, month, day := t.UTC().Date()
	return time.Date(year, month, day, 0, 0, 0, 0, time.UTC)
}

// addedDay is `community_trees.added_on`: the day other people, and the adder, are told the tree
// was added. The owner's decision of 2026-11-15 makes it one rule for every community tree, "the
// day the person added it on their phone", whenever it went public.
//
//   - `stated` is the phone's own local calendar date of the add (`addedOn`, midnight UTC of it),
//     nil for a build that does not send one. It is believed only within one day of the instant's
//     UTC date, because a local date never differs from the UTC date of the same instant by more
//     (decision 14a's argument for `captured_on`). Further off, it is not this add's day, and the
//     instant's own UTC date is used instead. The add is never refused for its date: the tree is
//     good even when the phone's calendar is not.
//   - Without a stated day, the day is the UTC date of `occurredAt`. The service holds no time zone
//     for the add, so a tree added at 23:30 Pacific time (07:30 UTC the next day) shows the next
//     day. That is what every build before the key shows.
//   - An instant after `received` is a phone clock running fast; the add cannot have happened
//     after the service received it, so `received` stands in for it. The result is therefore never
//     later than one day past the receipt's UTC date, which is the receipt day in the phone's own
//     zone (008's CHECK holds the same bound).
//   - A day before earliestAddedDay is a phone clock that was wrong in the other direction, and
//     there is no true day to recover. The receipt's UTC date is used: it is the latest the add can
//     have happened, and the day the service has always shown in its place.
func addedDay(stated *time.Time, occurredAt, received time.Time) time.Time {
	if occurredAt.After(received) {
		occurredAt = received
	}
	day := utcDay(occurredAt)
	if stated != nil {
		gap := utcDay(*stated).Sub(day)
		if gap >= -24*time.Hour && gap <= 24*time.Hour {
			day = utcDay(*stated)
		}
	}
	if day.Before(earliestAddedDay) {
		return utcDay(received)
	}
	return day
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
// born withdrawn — see `treeWasWithdrawnBy` — and is **never published**: no `published_at`, no
// `published` event, nothing public in its chain or history. It was never visible to anybody, so no
// read may report it as a removal either (review of #190, F3).
func insertCommunityTree(ctx context.Context, tx pgx.Tx, tree NewCommunityTree, act newTreeAct, now time.Time) (bool, error) {
	var tombstoned bool
	if err := tx.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM withdrawn_community_trees WHERE id = $1)`,
		tree.ID).Scan(&tombstoned); err != nil {
		return false, err
	}
	if tombstoned {
		return false, nil
	}

	withdrawn, err := treeWasWithdrawnBy(ctx, tx, tree.ID, act.Owner)
	if err != nil {
		return false, err
	}
	var publishedAt *time.Time
	var licenseVersion *string
	if !withdrawn {
		if publishedAt, licenseVersion, err = publicationStamp(ctx, tx, act.Owner, now); err != nil {
			return false, err
		}
	}
	tag, err := tx.Exec(ctx, `
		INSERT INTO community_trees
		    (id, lat, lon, address, species_id, placement, land_context, location_accuracy_m,
		     user_id, device_id, published_at, created_at, updated_at, added_on)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $12, $13)
		ON CONFLICT (id) DO NOTHING
	`, tree.ID, tree.Lat, tree.Lon, tree.Address, tree.SpeciesID, tree.Placement, tree.LandContext,
		tree.LocationAccuracyM, act.Owner.UserID, act.Owner.DeviceID, publishedAt, now,
		addedDay(tree.AddedOn, act.OccurredAt, now))
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
		     actor_user_id, actor_device_id, occurred_at, recorded_at, was_public)
		VALUES ($1, $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, false)
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
		if err := publishTrees(ctx, tx, []uuid.UUID{tree.ID}, *licenseVersion, actor, now); err != nil {
			return false, err
		}
	}
	if withdrawn {
		if err := markTreeDeleted(ctx, tx, tree.ID, "withdrawn", nil, actor, now, now, false); err != nil {
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
	PublishedAt  *time.Time
	// SpeciesSetBy is migration 009's `species_set_by`: "adder", "contributor" or "operator". Empty
	// is NULL, which every rule reads as the adder.
	SpeciesSetBy string
	// SpeciesNamer is the account whose contributor naming is in force, or nil.
	SpeciesNamer *uuid.UUID
	// ReportsClearedAt is `species_reports_cleared_at`, or nil when nobody ever cleared them.
	ReportsClearedAt *time.Time
}

// hiddenFrom is the reads' rule for who may know the tree exists (review of #190, F6): its adder
// always; anybody else only while it is published and not removed. An act by somebody it is hidden
// from is answered exactly as the same act on an id this service never held, so the answer is not
// an oracle for a withdrawn, taken-down or unpublished tree.
func (t treeRow) hiddenFrom(owner Owner) bool {
	return !t.isAddedBy(owner) && (t.DeletedAt != nil || t.PublishedAt == nil)
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
	var setBy *string
	err := tx.QueryRow(ctx, `
		SELECT user_id, device_id, species_id, anonymized_at, deleted_at, published_at,
		       species_set_by, species_namer_user_id, species_reports_cleared_at
		  FROM community_trees WHERE id = $1 FOR UPDATE
	`, id).Scan(&row.UserID, &row.DeviceID, &row.SpeciesID, &row.AnonymizedAt, &row.DeletedAt, &row.PublishedAt,
		&setBy, &row.SpeciesNamer, &row.ReportsClearedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return treeRow{}, ErrTreeNotFound
	}
	if setBy != nil {
		row.SpeciesSetBy = *setBy
	}
	return row, err
}

// othersHaveBuiltOn reports whether any identity other than `self` has met the tree: a live
// contribution of one of `MetSpeciesKinds`, or a live photograph. It is decision 8's condition (the
// adder may withdraw only while this is false) and decision 6's (the erase door anonymizes rather
// than deletes while it is true).
//
// The owner's own words for both decisions were "if anyone else has a visit or photo on the
// tree", and the orchestrator's ruling after #187's fix round holds the code to them. Favorites,
// photo votes, private reminders, species statements, reports, disputes and review flags are not
// a visit or a photo, and do not count.
//
// **The kinds are `MetSpeciesKinds` (`store/reads.go`, #184), by the orchestrator's ruling, which
// names that set: a visit, an observation, a measurement and a care event are all having stood in
// front of the tree. This PR carried its own copy while #184 was unmerged; they are now one list.
// The two answer neighbouring questions (met this species; met this tree), so a change to that list
// changes this rule too — `TestOnlyAVisitOrAPhotoKeepsATreeFromItsAdder` and its erase-door twin
// name every kind on both sides, and go red if either question's answer moves under the other.
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
	`, treeID, self.UserID, self.DeviceID, MetSpeciesKinds).Scan(&found)
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
// sorts after the head becomes the head and moves the tree's cached position. One that sorts before
// it arrived late (the outbox in backoff), so it is spliced into the chain **already superseded**
// and leaves the cache alone. Either way it writes a `location_corrected` event whose `before` is
// the row it follows.
//
// A move is not refused for landing near another tree. The owner ruled on 2026-11-14 that a pin
// "can go anywhere, and also fine to go within 10m of another tree".
func applyLocationCorrection(ctx context.Context, tx pgx.Tx, c LocationCorrection, act newTreeAct, now time.Time) error {
	tree, err := lockTree(ctx, tx, c.TreeID)
	if err != nil {
		return err
	}
	if tree.hiddenFrom(act.Owner) {
		return ErrTreeNotFound // what an id nobody sent answers
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

	// Decision 13: a row is a public position only if it becomes the head while the tree is
	// published. A move made while private stays private; so does a late correction spliced in
	// already superseded, which never moved the pin anybody saw.
	public := isNewHead && tree.PublishedAt != nil

	var before position
	if isNewHead {
		// The old head stops being one before the new row exists: the head index is not
		// deferrable, the foreign key is.
		if _, err := tx.Exec(ctx, `
			UPDATE community_tree_locations SET superseded_by = $2 WHERE id = $1
		`, head.ID, c.ID); err != nil {
			return err
		}
		if err := insertChainRow(ctx, tx, c, act, actor, nil, public, now); err != nil {
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
		if err := insertChainRow(ctx, tx, c, act, actor, &successor.ID, false, now); err != nil {
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
		After: at(c.Lat, c.Lon, c.Placement, c.AccuracyM), Public: public,
	}, now)
}

func insertChainRow(ctx context.Context, tx pgx.Tx, c LocationCorrection, act newTreeAct, actor Actor, supersededBy *uuid.UUID, wasPublic bool, now time.Time) error {
	_, err := tx.Exec(ctx, `
		INSERT INTO community_tree_locations
		    (id, tree_id, lat, lon, placement, location_accuracy_m, contribution_client_uuid,
		     actor_user_id, actor_device_id, occurred_at, recorded_at, superseded_by, was_public)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
	`, c.ID, c.TreeID, c.Lat, c.Lon, c.Placement, c.AccuracyM, act.ClientUUID,
		actor.UserID, actor.DeviceID, act.OccurredAt, now, supersededBy, wasPublic)
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

// ── Withdrawal and takedown ─────────────────────────────────────────────────────────────────────

// withdrawCommunityTree is decision 8: the adder withdraws a tree for everyone, while nobody else
// has built on it.
//
// **Soft, through `deleted_at`, and not the erase door's delete-and-tombstone.** The event this act
// must write lives in `community_tree_events`, which cascades from the tree — a hard delete would
// take the record of the withdrawal away with the thing withdrawn. Every read that serves a
// community tree already filters `deleted_at` (`communityTreeFor`, `MapMembership`), and S2's tile
// delta reports it as withdrawn exactly as it reports a tombstone.
//
// Answers, in order: a tree this service never held is a success that changes nothing (its add
// may still be in the adder's queue — `treeWasWithdrawnBy` makes that add arrive withdrawn). A tree
// the caller may not know exists answers the same (review of #190, F6): one a deletion door
// tombstoned (its account is gone, so nobody is its adder), and somebody else's withdrawn,
// taken-down or unpublished tree. Somebody else's visible tree is `ErrNotTheAdder`; the adder's own
// already withdrawn or taken-down tree is a success that changes nothing; somebody else's visit or
// photo on it is `ErrOthersBuiltOnTree`.
func withdrawCommunityTree(ctx context.Context, tx pgx.Tx, treeID uuid.UUID, act newTreeAct, now time.Time) error {
	tree, err := lockTree(ctx, tx, treeID)
	if errors.Is(err, ErrTreeNotFound) {
		return nil // never held, or tombstoned: the same answer
	}
	if err != nil {
		return err
	}
	if tree.hiddenFrom(act.Owner) {
		return nil // what an id nobody sent answers
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
	return markTreeDeleted(ctx, tx, treeID, "withdrawn", act.ClientUUID, actorOr(act.Actor, act.Owner), act.OccurredAt, now,
		tree.PublishedAt != nil)
}

// markTreeDeleted soft-removes a tree. `public` is whether the removal belongs to the public
// history: it does exactly when the tree had been published (decision 13).
func markTreeDeleted(ctx context.Context, tx pgx.Tx, treeID uuid.UUID, kind string, clientUUID *uuid.UUID, actor Actor, occurredAt, now time.Time, public bool) error {
	if _, err := tx.Exec(ctx, `
		UPDATE community_trees SET deleted_at = $2, updated_at = $2 WHERE id = $1
	`, treeID, now); err != nil {
		return err
	}
	return writeEvent(ctx, tx, event{
		TreeID: treeID, Kind: kind, ClientUUID: clientUUID, Actor: actor, OccurredAt: occurredAt,
		Public: public,
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
		return markTreeDeleted(ctx, tx, id, "taken_down", nil, Actor{}, now, now, tree.PublishedAt != nil)
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
//
// It returns the ids of the trees it kept, anonymized, and of the trees it deleted. `DELETE /me`
// sends both lists to the phone, which acts on them instead of its own guess (`ROADMAP` 104 and
// 105): the phone cannot see publication (decision 12), and it cannot see other people's rows that
// never reached it (decision 6). Both slices are non-nil, so the response says `[]` and never
// `null` when the account added nothing.
func deleteAccountTrees(ctx context.Context, tx pgx.Tx, userID uuid.UUID, choice DeletionChoice, now time.Time) (anonymized, deleted []uuid.UUID, err error) {
	anonymized, deleted = []uuid.UUID{}, []uuid.UUID{}
	type owned struct {
		ID        uuid.UUID
		Published bool
	}
	rows, err := tx.Query(ctx, `
		SELECT id, published_at IS NOT NULL FROM community_trees WHERE user_id = $1 FOR UPDATE
	`, userID)
	if err != nil {
		return nil, nil, err
	}
	var trees []owned
	for rows.Next() {
		var tree owned
		if err := rows.Scan(&tree.ID, &tree.Published); err != nil {
			rows.Close()
			return nil, nil, err
		}
		trees = append(trees, tree)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return nil, nil, err
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
					return nil, nil, err
				}
			}
		}
		if keep {
			if _, err := tx.Exec(ctx, `
				UPDATE community_trees
				   SET user_id = NULL, device_id = NULL, anonymized_at = $2, updated_at = $2
				 WHERE id = $1
			`, tree.ID, now); err != nil {
				return nil, nil, err
			}
			anonymized = append(anonymized, tree.ID)
			continue
		}
		// `was_public` is the tree's own answer, never a constant: an unpublished tree (decision 12)
		// must never be reported to anybody (review of #190, F2). Nothing unpublishes (decision
		// 10), so `published_at IS NOT NULL` is "was ever public".
		if _, err := tx.Exec(ctx, `
			INSERT INTO withdrawn_community_trees (id, withdrawn_at, was_public) VALUES ($1, $2, $3)
			ON CONFLICT (id) DO NOTHING
		`, tree.ID, now, tree.Published); err != nil {
			return nil, nil, err
		}
		if _, err := tx.Exec(ctx, `DELETE FROM community_trees WHERE id = $1`, tree.ID); err != nil {
			return nil, nil, err
		}
		deleted = append(deleted, tree.ID)
	}

	// ── Species on other people's trees (migration 009) ─────────────────────────────────────────
	//
	// **A naming this account made on somebody else's tree stays, and stops being anybody's.** The
	// species stays on the tree, under both doors, and the naming loses its namer, so nobody but the
	// adder and the operator can change it afterwards. The owner's decision of 2026-11-16 ("The
	// species stays": the name stays for everyone, with nothing that links it to the person) is
	// held here and by the actor sweep below. This statement is the one place that decides it; a
	// later rule that reverted the species would go here instead.
	// The foreign key's `ON DELETE SET NULL` would clear the namer anyway when `users` loses the
	// row; this is said here so the rule has a place to change.
	if _, err := tx.Exec(ctx, `
		UPDATE community_trees SET species_namer_user_id = NULL WHERE species_namer_user_id = $1
	`, userID); err != nil {
		return nil, nil, err
	}
	// **A report this account made counts until its record is gone.** Under `leaveRecords` the
	// report stays, anonymized, so it still counts, like every other record that door leaves.
	// Under `eraseEverything` the report's contribution is deleted above, and its `species_reported`
	// event goes with it here, so the report stops counting. Before the actor sweep below, which
	// would otherwise leave the event with no name to find it by.
	if choice == EraseEverything {
		if _, err := tx.Exec(ctx, `
			DELETE FROM community_tree_events
			 WHERE kind = 'species_reported'
			   AND (actor_user_id = $1
			        OR (actor_user_id IS NULL AND actor_device_id IN (SELECT id FROM devices WHERE user_id = $1)))
		`, userID); err != nil {
			return nil, nil, err
		}
	}

	// The account's name comes off every chain row and event it or any device it claimed performed,
	// on every tree, its own and anybody else's. Since migration 009 that includes other people's
	// trees: a contributor's naming, correction or report on a tree somebody else added. Full detail
	// was the server's to keep while the account existed (decision 4), not after.
	for _, table := range []string{"community_tree_locations", "community_tree_events"} {
		if _, err := tx.Exec(ctx, `
			UPDATE `+table+`
			   SET actor_user_id = NULL, actor_device_id = NULL, anonymized_at = coalesce(anonymized_at, $2)
			 WHERE actor_user_id = $1
			    OR actor_device_id IN (SELECT id FROM devices WHERE user_id = $1)
		`, userID, now); err != nil {
			return nil, nil, err
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
	// By is set only on a species event's `after` (migration 009): who acted, as `SpeciesByAdder`,
	// `SpeciesByContributor` or `SpeciesByOperator`. Absent on every species event written before
	// 009, when only the adder could act, so the history reads absent as the adder.
	By string `json:"by,omitempty"`
}

// at is a position with a place in it. Pointers rather than values so a tree on the equator or the
// prime meridian is not written as a tree with no position.
func at(lat, lon float64, placement string, accuracyM *float64) position {
	return position{Lat: &lat, Lon: &lon, Placement: placement, AccuracyM: accuracyM}
}

func (p position) isZero() bool {
	return p.Lat == nil && p.Lon == nil && p.Placement == "" && p.AccuracyM == nil && p.SpeciesID == nil &&
		p.LicenseVersion == nil && p.By == ""
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
	// Public is `in_public_history` (decision 13). The zero value is private, so a writer that
	// forgets to decide withholds rather than leaks.
	Public bool
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
		     occurred_at, recorded_at, before, after, in_public_history)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9::jsonb, $10::jsonb, $11)
	`, id, e.TreeID, e.Kind, e.ClientUUID, e.Actor.UserID, e.Actor.DeviceID, e.OccurredAt, now,
		nullableJSON(before), nullableJSON(after), e.Public)
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
