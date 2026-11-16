package store

import (
	"context"
	"errors"
	"time"

	"github.com/PlatosTwin/cypress/server/internal/uuid"
	"github.com/jackc/pgx/v5"
)

// ── The species of a community tree (§3B, and ROADMAP 144 from migration 009) ──────────────────
//
// Who may do what, decided under the tree's row lock (`lockTree`), in the order the service commits
// the acts. No rule here compares two phones' clocks. The owner's decisions are in 009's header.
//
//   - **Name** (`species_claim` on a tree with no species): the adder, or any sharing account (signed
//     in, with an accepted, known license version) that can see the tree. The first one committed
//     wins; a later one is recorded and changes nothing.
//   - **Correct** (`species_correction`): the adder, always; the account whose contributor naming is
//     in force, until the adder corrects or keeps the species; and the operator, through its route.
//     An adder's `species_claim` on a tree a contributor named is applied as the adder's correction,
//     because builds 88 and older (and the adder's phone before it learns the name) send a claim.
//   - **Report** (`wrong_species_report`): any sharing account that can see a named tree and is not
//     its adder and not the namer in force. It counts while it disputes the species in force and
//     came after the last clear.
//   - **Keep** (`species_review_dismissal`): the adder. It clears the reported state for everyone and
//     ends the namer's right to correct.
//
// **Nothing here refuses.** Every other statement is recorded (its `contributions` row) and changes
// nothing, which is how every species act was answered before 007. A tree the sender may not see is
// answered exactly as an unknown id, so the answer is no oracle for it.

// Who set a species, as migration 009's `species_set_by` and a species event's `after.by` spell it.
const (
	SpeciesByAdder       = "adder"
	SpeciesByContributor = "contributor"
	SpeciesByOperator    = "operator"
)

// SpeciesStatement is a `species_claim` or `species_correction` read for materialization (§3B).
type SpeciesStatement struct {
	TreeID    uuid.UUID
	SpeciesID uuid.UUID
}

// SpeciesReport is a `wrong_species_report` read for materialization.
type SpeciesReport struct {
	TreeID uuid.UUID
	// DisputedSpeciesID is the payload's optional `disputedSpeciesID`: the species the reader saw
	// and said was wrong. Nil when the phone did not send one (every build before the phone half of
	// ROADMAP 144), and then the report disputes the species in force when it arrives.
	DisputedSpeciesID *uuid.UUID
}

// SpeciesKeep is a `species_review_dismissal` read for materialization: "Keep the species".
type SpeciesKeep struct {
	TreeID uuid.UUID
}

// sharesTreeRecords is the owner's rule of 2026-11-16, "Only people who share": a signed-in account
// that has accepted a known license version. A device credential never shares.
func sharesTreeRecords(ctx context.Context, tx pgx.Tx, owner Owner) (bool, error) {
	if owner.UserID == nil {
		return false, nil
	}
	version, err := accountLicense(ctx, tx, *owner.UserID)
	return version != nil, err
}

// lockVisibleTree is the opening every species act shares: the tree, locked, or nil when the act
// must change nothing because the tree is not a live community tree this sender may see.
func lockVisibleTree(ctx context.Context, tx pgx.Tx, id uuid.UUID, owner Owner) (*treeRow, error) {
	tree, err := lockTree(ctx, tx, id)
	if errors.Is(err, ErrTreeNotFound) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	if tree.DeletedAt != nil || tree.hiddenFrom(owner) {
		return nil, nil
	}
	return &tree, nil
}

// materializeSpecies applies a `species_claim` or `species_correction` by the rules above.
func materializeSpecies(ctx context.Context, tx pgx.Tx, kind string, s SpeciesStatement, act newTreeAct, now time.Time) error {
	tree, err := lockVisibleTree(ctx, tx, s.TreeID, act.Owner)
	if tree == nil || err != nil {
		return err
	}

	if tree.isAddedBy(act.Owner) {
		switch {
		case kind == "species_claim" && tree.SpeciesID == nil:
			return applySpecies(ctx, tx, *tree, s, "species_named", SpeciesByAdder, nil, false, act, now)
		case kind == "species_claim" && tree.SpeciesSetBy == SpeciesByContributor:
			return applySpecies(ctx, tx, *tree, s, "species_corrected", SpeciesByAdder, nil, true, act, now)
		case kind == "species_claim":
			return nil
		}
		stale, err := supersededByOwnStatement(ctx, tx, s.TreeID, act)
		if err != nil || stale {
			return err
		}
		return applySpecies(ctx, tx, *tree, s, "species_corrected", SpeciesByAdder, nil, true, act, now)
	}

	shares, err := sharesTreeRecords(ctx, tx, act.Owner)
	if err != nil || !shares {
		return err
	}
	namer := act.Owner.UserID
	if kind == "species_claim" {
		if tree.SpeciesID != nil {
			return nil // somebody's answer is already in force: the first committed wins
		}
		return applySpecies(ctx, tx, *tree, s, "species_named", SpeciesByContributor, namer, false, act, now)
	}
	// The namer's own correction. `SpeciesNamer` is nil once the adder corrected or kept the
	// species, once the operator set it, and once the namer's account is gone, so each of those
	// ends this arm without a clock.
	if tree.SpeciesSetBy != SpeciesByContributor || tree.SpeciesNamer == nil || *tree.SpeciesNamer != *namer {
		return nil
	}
	stale, err := supersededByOwnStatement(ctx, tx, s.TreeID, act)
	if err != nil || stale {
		return err
	}
	// It does not clear reports: the owner's rule is that the mark stays until the adder or the
	// operator acts. A report that disputed the old name stops counting by itself, because it
	// disputes a name the tree no longer has (`speciesReportCounts`); one that disputed nothing
	// named counts against the species in force.
	return applySpecies(ctx, tx, *tree, s, "species_corrected", SpeciesByContributor, namer, false, act, now)
}

// supersededByOwnStatement reports whether the same identity already made a species statement on
// this tree that its own phone dated later. It is the one place a phone's `occurred_at` decides
// anything, and it only ever compares a phone's clock with itself (or the same account's other
// phone): one outbox can drain out of order (an item in backoff), and its older correction must not
// undo its newer one. Between different people the later committed act wins, whatever their phones
// say.
func supersededByOwnStatement(ctx context.Context, tx pgx.Tx, treeID uuid.UUID, act newTreeAct) (bool, error) {
	var newer bool
	err := tx.QueryRow(ctx, `
		SELECT EXISTS (SELECT 1 FROM community_tree_events
		                WHERE tree_id = $1 AND kind IN ('species_named', 'species_corrected')
		                  AND occurred_at > $2
		                  AND CASE WHEN $3::uuid IS NOT NULL THEN coalesce(actor_user_id = $3, false)
		                           ELSE actor_user_id IS NULL AND coalesce(actor_device_id = $4, false) END)
	`, treeID, act.OccurredAt, act.Owner.UserID, act.Owner.DeviceID).Scan(&newer)
	return newer, err
}

// applySpecies moves the species and writes its event. `namer` is the account whose contributor
// naming is now in force, or nil. `clearReports` is true for the adder's correction.
func applySpecies(ctx context.Context, tx pgx.Tx, tree treeRow, s SpeciesStatement, eventKind, by string,
	namer *uuid.UUID, clearReports bool, act newTreeAct, now time.Time) error {
	if _, err := tx.Exec(ctx, `
		UPDATE community_trees
		   SET species_id = $2, updated_at = $3, species_set_by = $4, species_namer_user_id = $5
		 WHERE id = $1
	`, s.TreeID, s.SpeciesID, now, by, namer); err != nil {
		return err
	}
	if clearReports {
		if err := clearSpeciesReports(ctx, tx, s.TreeID, now); err != nil {
			return err
		}
	}
	return writeEvent(ctx, tx, event{
		TreeID: s.TreeID, Kind: eventKind, ClientUUID: act.ClientUUID,
		Actor: actorOr(act.Actor, act.Owner), OccurredAt: act.OccurredAt,
		Before: position{SpeciesID: tree.SpeciesID}, After: position{SpeciesID: &s.SpeciesID, By: by},
		// Decision 13: a species named while the tree was private is the adder's history, not the
		// public's. The species itself is public at publication through the tree's cache. Only the
		// adder can act on an unpublished tree, because it is hidden from everybody else.
		Public: tree.PublishedAt != nil,
	}, now)
}

// clearSpeciesReports ends every report recorded so far. A report counts only when it was recorded
// after `species_reports_cleared_at`.
//
// **The moment is never earlier than the newest report already here.** Both writers hold the tree's
// row lock, so whichever commits second sees the other. A report that committed first can carry a
// later `recorded_at` than this transaction's `now` (it started later and took the lock sooner), and
// a clear stamped at `now` would then leave it counting although the clear came after it. Raising
// the moment to that report's time makes "cleared" mean "committed before the clear".
func clearSpeciesReports(ctx context.Context, tx pgx.Tx, treeID uuid.UUID, now time.Time) error {
	_, err := tx.Exec(ctx, `
		UPDATE community_trees
		   SET species_reports_cleared_at = GREATEST($2::timestamptz,
		       (SELECT max(recorded_at) FROM community_tree_events
		         WHERE tree_id = $1 AND kind = 'species_reported'))
		 WHERE id = $1
	`, treeID, now)
	return err
}

// recordSpeciesReport makes a `wrong_species_report` count, when it may: from a sharing account
// that is not the adder and not the namer in force, on a named tree it can see. It writes a private
// `species_reported` event whose `before.species_id` is the species disputed, fixed at receipt.
func recordSpeciesReport(ctx context.Context, tx pgx.Tx, r SpeciesReport, act newTreeAct, now time.Time) error {
	tree, err := lockVisibleTree(ctx, tx, r.TreeID, act.Owner)
	if tree == nil || err != nil {
		return err
	}
	if tree.isAddedBy(act.Owner) || tree.SpeciesID == nil {
		return nil
	}
	shares, err := sharesTreeRecords(ctx, tx, act.Owner)
	if err != nil || !shares {
		return err
	}
	if tree.SpeciesNamer != nil && *tree.SpeciesNamer == *act.Owner.UserID {
		return nil // reporting your own answer: correct it instead
	}
	disputed := tree.SpeciesID
	if r.DisputedSpeciesID != nil {
		disputed = r.DisputedSpeciesID
	}
	// `clearSpeciesReports`' argument from the other side: a clear that committed first can carry a
	// later moment than this transaction's `now`, and this report came after it, so it must sort
	// after it. Postgres keeps microseconds, so the comparison is made at that precision.
	recorded := now.Truncate(time.Microsecond)
	if cleared := tree.ReportsClearedAt; cleared != nil && !recorded.After(*cleared) {
		recorded = cleared.Truncate(time.Microsecond).Add(time.Microsecond)
	}
	return writeEvent(ctx, tx, event{
		TreeID: r.TreeID, Kind: "species_reported", ClientUUID: act.ClientUUID,
		Actor: actorOr(act.Actor, act.Owner), OccurredAt: act.OccurredAt,
		Before: position{SpeciesID: disputed}, Public: false,
	}, recorded)
}

// keepSpecies is the adder's "Keep the species": the reported state clears for everyone, and the
// namer's right to correct ends. Anybody else's dismissal is recorded and changes nothing.
func keepSpecies(ctx context.Context, tx pgx.Tx, k SpeciesKeep, act newTreeAct, now time.Time) error {
	tree, err := lockVisibleTree(ctx, tx, k.TreeID, act.Owner)
	if tree == nil || err != nil || !tree.isAddedBy(act.Owner) {
		return err
	}
	if err := clearSpeciesReports(ctx, tx, k.TreeID, now); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, `
		UPDATE community_trees SET species_namer_user_id = NULL WHERE id = $1
	`, k.TreeID); err != nil {
		return err
	}
	return writeEvent(ctx, tx, event{
		TreeID: k.TreeID, Kind: "species_reports_cleared", ClientUUID: act.ClientUUID,
		Actor: actorOr(act.Actor, act.Owner), OccurredAt: act.OccurredAt,
		After: position{By: SpeciesByAdder}, Public: false,
	}, now)
}

// ── The operator ───────────────────────────────────────────────────────────────────────────────

// OperatorSetSpecies is the operator's species correction (the owner's rule of 2026-11-15: "The
// adder can correct the species, and so can the operator"). It sets the species, ends any namer's
// right to correct, clears the reported state, and writes a `species_corrected` event with no actor
// and `after.by = "operator"`. The event is public when the tree is published and the species
// changed; an unchanged species is still recorded, privately, because the clear happened.
//
// The service holds no species catalog, so the id is not checked against one: a mistyped id is
// stored, and no phone can name it. ErrNotFound for an id that names no live community tree.
func (s *Store) OperatorSetSpecies(ctx context.Context, id, speciesID uuid.UUID) error {
	return s.Tx(ctx, func(tx pgx.Tx) error {
		tree, err := lockTree(ctx, tx, id)
		if errors.Is(err, ErrTreeNotFound) || (err == nil && tree.DeletedAt != nil) {
			return ErrNotFound
		}
		if err != nil {
			return err
		}
		now := s.now()
		changed := tree.SpeciesID == nil || *tree.SpeciesID != speciesID
		if _, err := tx.Exec(ctx, `
			UPDATE community_trees
			   SET species_id = $2, species_set_by = 'operator', species_namer_user_id = NULL,
			       updated_at = CASE WHEN $3 THEN $4 ELSE updated_at END
			 WHERE id = $1
		`, id, speciesID, changed, now); err != nil {
			return err
		}
		if err := clearSpeciesReports(ctx, tx, id, now); err != nil {
			return err
		}
		return writeEvent(ctx, tx, event{
			TreeID: id, Kind: "species_corrected", OccurredAt: now,
			Before: position{SpeciesID: tree.SpeciesID}, After: position{SpeciesID: &speciesID, By: SpeciesByOperator},
			Public: changed && tree.PublishedAt != nil,
		}, now)
	})
}

// OperatorClearSpeciesReports clears the reported state without changing the species. It does not
// end a namer's right to correct: that is the adder's keep, and the operator's correction. ErrNotFound
// for an id that names no live community tree.
func (s *Store) OperatorClearSpeciesReports(ctx context.Context, id uuid.UUID) error {
	return s.Tx(ctx, func(tx pgx.Tx) error {
		tree, err := lockTree(ctx, tx, id)
		if errors.Is(err, ErrTreeNotFound) || (err == nil && tree.DeletedAt != nil) {
			return ErrNotFound
		}
		if err != nil {
			return err
		}
		now := s.now()
		if err := clearSpeciesReports(ctx, tx, id, now); err != nil {
			return err
		}
		return writeEvent(ctx, tx, event{
			TreeID: id, Kind: "species_reports_cleared", OccurredAt: now,
			After: position{By: SpeciesByOperator}, Public: false,
		}, now)
	})
}

// ── The read ───────────────────────────────────────────────────────────────────────────────────

// SpeciesState is what the profile says about a visible community tree's species beyond the species
// itself.
type SpeciesState struct {
	// Reported is whether a report counts now: "Somebody has reported this species as wrong."
	Reported bool
	// ReportFlagID is the newest counting report's `flagID`, for the adder's "Keep the species".
	// Nil when nothing counts or the payload's `flagID` is not a uuid. The caller serves it to the
	// adder only.
	ReportFlagID *uuid.UUID
	// NamedByViewer is whether the viewer's contributor naming is in force, so they may correct it.
	NamedByViewer bool
}

// speciesReportCounts is the rule, spelled in SQL over `community_tree_events e` and
// `community_trees t`: a `species_reported` event on a named tree that disputes the species in force
// and was recorded after the last clear. Whose report it is was decided when it was recorded.
const speciesReportCounts = `
	e.kind = 'species_reported' AND e.tree_id = t.id
	AND t.species_id IS NOT NULL
	AND (e.before ->> 'species_id')::uuid = t.species_id
	AND e.recorded_at > coalesce(t.species_reports_cleared_at, '-infinity'::timestamptz)`

// speciesStateFor reads SpeciesState for a tree the caller has already found visible to the viewer.
func speciesStateFor(ctx context.Context, q querier, treeID uuid.UUID, viewer Owner) (SpeciesState, error) {
	var (
		state  SpeciesState
		namer  *uuid.UUID
		found  *bool
		flagID *string
	)
	err := q.QueryRow(ctx, `
		SELECT t.species_namer_user_id, r.found, r.flag
		  FROM community_trees t
		  LEFT JOIN LATERAL (
		      SELECT true AS found, c.payload ->> 'flagID' AS flag
		        FROM community_tree_events e
		        LEFT JOIN contributions c ON c.client_uuid = e.contribution_client_uuid
		       WHERE `+speciesReportCounts+`
		       ORDER BY e.recorded_at DESC, e.id DESC
		       LIMIT 1) r ON true
		 WHERE t.id = $1
	`, treeID).Scan(&namer, &found, &flagID)
	if errors.Is(err, pgx.ErrNoRows) {
		return SpeciesState{}, nil
	}
	if err != nil {
		return SpeciesState{}, err
	}
	state.Reported = found != nil && *found
	if flagID != nil {
		if parsed, err := uuid.Parse(*flagID); err == nil {
			state.ReportFlagID = &parsed
		}
	}
	state.NamedByViewer = namer != nil && viewer.UserID != nil && *namer == *viewer.UserID
	return state, nil
}
