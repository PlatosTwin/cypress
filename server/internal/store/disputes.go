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
// ── The three answers ──────────────────────────────────────────────────────────────────────────
//
// They are `withdrawMeasurement`'s, with the `UPDATE` at the end of it removed and its
// "already tombstoned" arm gone with it — nothing writes `contributions.deleted_at` for a dispute,
// so there is no such state to answer for.
//
//   - **no matching dispute** — nothing to own, and a success. Reachable and not exotic: the raise
//     may still be in the phone's outbox, or that phone may never have drained at all
//     (`TestAWithdrawalOfADisputeThisServiceNeverHeldIsApplied` pins it). Refusing here would put a
//     permanent red row on screen 17 for a dispute the person has already taken back locally.
//   - **at least one match is this identity's** — the withdrawal is theirs to make.
//   - **matches exist and none of them are this identity's** — `ErrDisputeNotOwned`.
//
// ── Two routes past this gate, and the list above is the ordinary case, not every case ─────────
//
// Neither route below is a defect in the three answers — they are what those three answers *are*,
// followed to their edges — and neither is written down because it needs fixing here. They are
// written down because a reader takes the list above to mean "a withdrawal of somebody else's
// dispute is refused", and the unqualified form of that sentence is false. Both were reproduced
// against a throwaway Postgres by PR #159's second reviewer and again before this paragraph was
// written, each with the control that shows the gate firing in the ordinary case — the controls
// are the half that says the probe is measuring the gate and not a broken harness.
//
//   - **Mint yourself into the match set.** `matched == 0 || mine > 0` is a property of the whole
//     match set, which is the point of counting — and nothing makes `payload ->> 'id'` unique. An
//     identity that first raises its *own* `data_dispute` carrying somebody else's dispute id, on
//     any tree, is thereafter in that set, and its withdrawal of the original answers `applied`.
//     Without the twin raise the same withdrawal is `forbidden`, which is the control.
//   - **Arrive before the raise.** This gate can only refuse a withdrawal that reaches this service
//     *after* the raise it names. Before it, the first bullet is the answer: success, the
//     withdrawal's row is stored, and nothing revisits it when the raise lands afterwards. The same
//     withdrawal sent once the raise is present is `forbidden`, which is the control.
//
// Neither is exploitable as this service stands, and that is a fact about the surface rather than
// about this function: a dispute id is minted on the client and never generated here, and the only
// read that serves it back — `GET /me/journal` — is owner-scoped, so nothing in this service hands
// one identity another's dispute id to name.
//
// **The second is the sibling kind's arrival-order problem, and this round deliberately does not
// import the half that closes it.** `measurementWasWithdrawn` exists for exactly this ordering and
// its header argues the order is "reachable rather than merely possible" — `OutboxStore.dueItems`
// orders by what is *due*, so an item in backoff drains after one enqueued later — by having the
// *reading* look for its own withdrawal on the way in and be born tombstoned. That half is not
// written here because there is nothing for it to write on: a reading is born tombstoned into
// `contributions.deleted_at`, the column every read already filters on, whereas a dispute
// materializes nothing and nothing tombstones one (see `syncKinds` in `internal/api/sync.go`). So
// what an early withdrawal leaves is a stored row with no raise beside it, and reconciling that
// residue belongs to the round that first serves these rows back — the badge round, which is where
// E280's read gate and the tombstone are already owed. Adding the lookup here would answer for one
// kind, against no read, a question that round has to answer for all of them.
//
// ── Why it counts rather than reading one row ──────────────────────────────────────────────────
//
// The reason is `withdrawMeasurement`'s, one kind over. This lookup is not on a key: it matches a
// value inside a JSONB payload, and nothing in this schema makes `payload ->> 'id'` unique — the
// same dispute re-enqueued under a second `client_uuid` is two rows here. A `QueryRow` would
// silently decide ownership from whichever row the planner returned first. Counting makes the
// answer a property of the whole match set.
//
// Compared as **text under `upper()`** rather than cast to `uuid`, and the reason that decides it
// is the one this round measured: **the same id reaches this service in two spellings.** The
// payload is stored verbatim, and the client mints a UUID as `SQLiteValue`'s uppercase `uuidString`
// coming out of a stored row and as `JSONEncoder`'s lowercase coming out of a queued one. That is
// the case split `AppSchema` v13 declares `COLLATE NOCASE` for on `anonymized_contributions`'
// `client_uuid`, and the one `internal/uuid.Parse` is deliberately case-insensitive for. The
// withdrawal's own id arrives through `Parse` and is re-spelled lowercase by `String()`, so it is
// the **stored** side that can differ. Under a plain `=` a dispute raised in the other spelling
// would simply not be found — and "not found" is the *first* answer above, a success. The gate
// would stop refusing and would look exactly like a gate that works.
// `TestTheOwnershipLookupMatchesADisputeInEitherSpelling` is that difference, and it is the only
// case that goes red when the `upper()` is dropped from both query and index.
//
// 004's other argument for text is kept here as a **caution, and it is explicitly unverified**:
// that `(payload ->> 'id')::uuid` could *error* rather than merely miss, if Postgres evaluated the
// cast on a row of some other kind before the `kind` qual excluded it. Nothing in this tree
// exhibits that, and an attempt to reproduce it on Postgres 16.15 failed in three shapes — a
// kind-qualled cast over a two-row table, over a 5 001-row table of which 5 000 are poison after
// `ANALYZE`, and through a flattenable subquery — all three returning the matching row with no
// error. The probe does detect the failure when it happens: the same cast with the `kind` qual
// removed errors `invalid input syntax for type uuid` (`22P02`) on cue, which is the calibration
// that makes the three passes worth reporting. So this is *not measured*, not *measured absent*:
// the standard promises no qual ordering in either direction, and three passes are not a guarantee
// to lean on. What is not in doubt is that comparing text cannot error at all, which is why the design
// stands on the spelling argument above and takes this one as a bonus.
//
// `docs/errata-pending/grove-species-known-unscoped-cast.md` is **not** an instance of this hazard,
// and calling it one is a category slip worth not repeating: `GroveSpeciesKnown` carries no `kind`
// qual at all, so its cast reaches every kind's payload by construction rather than by any choice a
// planner makes.
//
// The expression is written identically to `contributions_disputed_record_id` in
// `005_data_dispute_kinds.sql`; an index whose expression differs from the query's is dead weight
// that looks like a plan.
//
// ── What "this identity's" means, and the divergence it inherits ───────────────────────────────
//
// Ownership is this table's two columns, exactly as it is for a photograph and for a reading: a
// `user_id` match or a `device_id` match, and an anonymized row — `AccountDeletionChoice
// .leaveRecords` clears both — is owned by nobody and therefore refused (measured by
// `TestAnAnonymizedDisputeIsWithdrawableByNobody`). The consequence is
// `withdrawMeasurement`'s documented divergence reached through a third kind: signed out on the
// phone that raised the dispute *while signed in*, `ClaimDevice` has already moved the row's
// `device_id` to a `user_id` and this service cannot tell that installation apart, so the
// withdrawal comes back `forbidden`. `docs/ROADMAP.md`'s chip "Decide what a signed-out phone can
// take back" is where that question lives; this function does not answer it and does not widen it.
func disputeIsThisIdentitys(ctx context.Context, tx pgx.Tx, id uuid.UUID, owner Owner) error {
	var matched, mine int
	err := tx.QueryRow(ctx, `
		SELECT count(*),
		       -- No coalesce around this, unlike withdrawMeasurement's, and the difference is worth
		       -- a line because the two queries are otherwise the same shape. That one has to tell
		       -- "live and mine" from "live and not mine" with two FILTERs, so an ownership
		       -- comparison that evaluates to NULL -- an anonymized row, both columns cleared --
		       -- would fall out of both counts and read as "not here". This one asks a single
		       -- question, and FILTER excludes a NULL exactly as it excludes false: an anonymized
		       -- row counts in matched, not in mine, and is refused. That is the answer wanted, and
		       -- it is the one AccountDeletionChoice.leaveRecords implies -- a record owned by
		       -- nobody is not withdrawable by anybody.
		       count(*) FILTER (WHERE ($2::uuid IS NOT NULL AND user_id = $2)
		                           OR ($3::uuid IS NOT NULL AND device_id = $3))
		  FROM contributions
		 WHERE kind = 'data_dispute' AND upper(payload ->> 'id') = upper($1)
	`, id.String(), owner.UserID, owner.DeviceID).Scan(&matched, &mine)
	if err != nil {
		return err
	}
	if matched == 0 || mine > 0 {
		return nil
	}
	return ErrDisputeNotOwned
}
