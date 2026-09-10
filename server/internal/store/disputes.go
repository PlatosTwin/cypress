package store

import (
	"context"
	"errors"

	"github.com/PlatosTwin/cypress/server/internal/uuid"
	"github.com/jackc/pgx/v5"
)

// ErrDisputeNotOwned is returned when the dispute a withdrawal names is here and was raised by
// somebody else.
//
// A third sentinel beside `ErrNotOwned` and `ErrMeasurementNotOwned` for the reason the second one
// gives: the caller turns each into a sentence somebody reads on screen 17, and "That photo belongs
// to a different contributor" on an item about a dispute is a message nobody can act on.
//
// The caller maps it to `forbidden` — non-retryable, so the item fails on the spot rather than
// spending 48 h on an answer that will not change.
var ErrDisputeNotOwned = errors.New("dispute belongs to another contributor")

// disputeIsThisIdentitys refuses a withdrawal of a dispute somebody else raised.
//
// ── Why this exists on a kind that materializes nothing ────────────────────────────────────────
//
// Nothing here adjudicates a dispute, so there is no dispute table to guard. The read that does
// serve these rows — `GET /me/journal`, which selects `contributions` with no kind filter — is
// owner-scoped, so a stranger's withdrawal is not something the raiser is ever shown; that is why
// this is a low-blast-radius gap rather than an E280 one.
//
// What is at stake is narrower and still real: the `contributions` row **is** the record, and a
// `data_dispute_withdrawal` answered `applied` under Bob's identity for a dispute Alice raised
// writes "Bob withdrew this" into the record the moderation round will read. That is a false
// statement stored, and it is cheaper to refuse now than to unpick from rows a later round has
// already believed.
//
// ── The three answers, which are `withdrawMeasurement`'s three minus the tombstone ─────────────
//
//   - **no matching dispute** — nothing to own, and a success. Reachable and not exotic: the raise
//     may still be in the phone's outbox, or that phone may never have drained at all
//     (`TestAWithdrawalOfADisputeThisServiceNeverHeldIsApplied` pins it). Refusing here would put a
//     permanent red row on screen 17 for a dispute the person has already taken back locally.
//   - **at least one match is this identity's** — the withdrawal is theirs to make.
//   - **matches exist and none of them are this identity's** — `ErrDisputeNotOwned`.
//
// ── Why it counts rather than reading one row ──────────────────────────────────────────────────
//
// The reason is `withdrawMeasurement`'s, one kind over. This lookup is not on a key: it matches a
// value inside a JSONB payload, and nothing in this schema makes `payload ->> 'id'` unique — the
// same dispute re-enqueued under a second `client_uuid` is two rows here. A `QueryRow` would
// silently decide ownership from whichever row the planner returned first. Counting makes the
// answer a property of the whole match set.
//
// Compared as **text under `upper()`** rather than cast to `uuid`, which is 004's argument and its
// second half is the one that decides it: `(payload ->> 'id')::uuid` can *error* rather than merely
// miss, because nothing promises Postgres evaluates the `kind` qual first, and a payload of some
// other kind carrying a non-UUID `id` would fail the whole request. That is not hypothetical —
// `docs/errata-pending/grove-species-known-unscoped-cast.md` is the instance already in the tree.
// The expression is written identically to `contributions_disputed_record_id` in
// `005_data_dispute_kinds.sql`; an index whose expression differs from the query's is dead weight
// that looks like a plan.
//
// ── What "this identity's" means, and the divergence it inherits ───────────────────────────────
//
// Ownership is this table's two columns, exactly as it is for a photograph and for a reading: a
// `user_id` match or a `device_id` match, and an anonymized row — `AccountDeletionChoice
// .leaveRecords` clears both — is owned by nobody and therefore refused. The consequence is
// `withdrawMeasurement`'s documented divergence reached through a third kind: signed out on the
// phone that raised the dispute *while signed in*, `ClaimDevice` has already moved the row's
// `device_id` to a `user_id` and this service cannot tell that installation apart, so the
// withdrawal comes back `forbidden`. `docs/ROADMAP.md`'s chip "Decide what a signed-out phone can
// take back" is where that question lives; this function does not answer it and does not widen it.
func disputeIsThisIdentitys(ctx context.Context, tx pgx.Tx, id uuid.UUID, owner Owner) error {
	var matched, mine int
	err := tx.QueryRow(ctx, `
		SELECT count(*), count(*) FILTER (WHERE mine)
		  FROM (
		      SELECT
		             -- The coalesce is load-bearing, for withdrawMeasurement's reason: with a user
		             -- id supplied and the row's own column NULL the comparison is NULL rather than
		             -- false, a NULL is counted by no FILTER, and an anonymized row would then read
		             -- as "not here" instead of "not yours" -- so the withdrawal would answer
		             -- applied on somebody's cleared record.
		             coalesce(($2::uuid IS NOT NULL AND user_id = $2)
		                   OR ($3::uuid IS NOT NULL AND device_id = $3), false) AS mine
		        FROM contributions
		       WHERE kind = 'data_dispute' AND upper(payload ->> 'id') = upper($1)
		  ) matched
	`, id.String(), owner.UserID, owner.DeviceID).Scan(&matched, &mine)
	if err != nil {
		return err
	}
	if matched == 0 || mine > 0 {
		return nil
	}
	return ErrDisputeNotOwned
}
