package store

import (
	"context"
	"errors"
	"time"

	"github.com/PlatosTwin/cypress/server/internal/uuid"
	"github.com/jackc/pgx/v5"
)

// ErrMeasurementNotOwned is returned when the reading a withdrawal names is here and is somebody
// else's.
//
// A separate sentinel from `ErrNotOwned` rather than a reuse, because the two are refusals about
// different things and the caller turns each into a sentence a person reads on screen 17: "That
// photo belongs to a different contributor" is a lie when the item was about a number. The
// *argument* for having a third answer at all is `ErrNotOwned`'s and is not restated here — a
// withdrawal that is answered `applied` while the reading goes on being counted is ERRATA E280
// reached through `contributions` instead of `photos`.
//
// The caller maps it to `forbidden` — non-retryable, so the item fails on the spot rather than
// spending 48 h on an answer that will not change.
var ErrMeasurementNotOwned = errors.New("measurement belongs to another contributor")

// withdrawMeasurement tombstones one reading inside an already-open transaction.
//
// **The row it tombstones is a `contributions` row, and that is the whole of the mechanism.** Five
// of the six original kinds have no materialized table — a measurement *is* its contribution row,
// as `002_community_mutation_kinds.sql` says in as many words — and `contributions.deleted_at` is
// already the column every read narrows on: `Grove`'s tally, `Journal`, `GroveSpeciesKnown`,
// `MapMembership`, `TreeCommunityHalf`. Nothing has ever written it. So "the reading stops being
// served" needs no new table and no new column; it needs the `UPDATE` nobody had written yet.
//
// ── The three answers, which are `withdrawPhoto`'s three ───────────────────────────────────────
//
//   - **no row** — nothing to withdraw. Reachable and not exotic: the reading's own `measurement`
//     item may still be in the outbox (see `measurementWasWithdrawn`), or this phone may never have
//     drained at all. It is a success, and the contribution recording the act is still written —
//     the record of the act is the point, and it is what the late arrival then reads.
//   - **already tombstoned** — success, changing nothing. A drain that replays a withdrawal under a
//     *fresh* key after a flap must not fail on the second pass; the contribution dedupe cannot
//     answer that case because the key is new.
//   - **present and not this identity's** — `ErrMeasurementNotOwned`.
//
// ── Why this counts rather than reading one row ────────────────────────────────────────────────
//
// `withdrawPhoto` selects one row because `photos.id` is a primary key. This lookup is not on a
// key: it matches on a value inside a JSONB payload, and nothing in this schema makes it unique —
// the same reading re-enqueued under a second `client_uuid` would be two rows here. A `QueryRow`
// would then silently pick one of them and decide ownership from whichever the planner returned
// first. Counting instead makes the answer a property of the whole match set: any live row of mine
// is a withdrawal to perform, and a live row that is only somebody else's is a refusal.
//
// **Ownership is this table's two columns**, the same divergence `withdrawPhoto` records for
// photographs: the client's gate has an installation arm (`ContributionStore.withdrawalPredicate`)
// and this one cannot, because `ClaimDevice` moves a contribution's `device_id` to a `user_id` and
// nothing here remembers which phone took it. A reading recorded before sign-in, then claimed, then
// withdrawn from a signed-out installation is deletable locally and `ErrMeasurementNotOwned` here.
// An anonymized row — `AccountDeletionChoice.leaveRecords` clears both columns — is owned by
// nobody and therefore refused, which is the same answer the client's own `isAnonymized` guard
// gives before it writes anything.
func withdrawMeasurement(ctx context.Context, tx pgx.Tx, id uuid.UUID, owner Owner, now time.Time) error {
	var matched, liveAndMine, liveAndNotMine int
	err := tx.QueryRow(ctx, `
		SELECT count(*),
		       count(*) FILTER (WHERE deleted_at IS NULL AND mine),
		       count(*) FILTER (WHERE deleted_at IS NULL AND NOT mine)
		  FROM (
		      SELECT deleted_at,
		             -- The coalesce is load-bearing: with a user id supplied and the row's own
		             -- column NULL, the comparison is NULL rather than false, and a NULL is counted
		             -- by neither FILTER -- so an anonymized row would read as "not here" instead
		             -- of "not yours", and the withdrawal would answer applied.
		             coalesce(($2::uuid IS NOT NULL AND user_id = $2)
		                   OR ($3::uuid IS NOT NULL AND device_id = $3), false) AS mine
		        FROM contributions
		       WHERE kind = 'measurement' AND upper(payload ->> 'id') = upper($1)
		  ) matched
	`, id.String(), owner.UserID, owner.DeviceID).Scan(&matched, &liveAndMine, &liveAndNotMine)
	if err != nil {
		return err
	}
	if matched == 0 {
		return nil
	}
	if liveAndMine == 0 {
		if liveAndNotMine > 0 {
			return ErrMeasurementNotOwned
		}
		// Every match is already tombstoned.
		return nil
	}

	_, err = tx.Exec(ctx, `
		UPDATE contributions
		   SET deleted_at = $4, updated_at = $4
		 WHERE kind = 'measurement' AND upper(payload ->> 'id') = upper($1)
		   AND deleted_at IS NULL
		   AND (($2::uuid IS NOT NULL AND user_id = $2) OR ($3::uuid IS NOT NULL AND device_id = $3))
	`, id.String(), owner.UserID, owner.DeviceID, now)
	return err
}

// measurementWasWithdrawn reports whether this identity has already taken this reading back.
//
// ── The arrival-order hole this closes, and the narrower one it does not ───────────────────────
//
// **The claim, stated exactly, because half of it is the part that is easy to overstate.** What is
// closed is the ordering in which the withdrawal is *committed in an earlier drain* than the
// reading it withdraws — an earlier `POST /sync`, or an earlier position in the same batch, which
// `Apply` walks one mutation and one transaction at a time. What is **not** closed is two `Apply`
// transactions overlapping in time. That case is written out under "What this does not close"
// below rather than left to be inferred.
//
// A `photo_withdrawal` can name bytes this service has never held and never will, because no photo
// send path exists (ERRATA E264): a withdrawal that finds nothing is the end of the story. A
// **measurement** is not like that. `measurement` is one of the six original kinds and it drains
// through `POST /sync` today, so "the reading is not here yet" is a state that ends — and the way
// it ends decides whether the withdrawal was true.
//
// The client's queue makes the bad order reachable rather than merely possible.
// `OutboxStore.dueItems` is `WHERE state = 'pending' AND (next_attempt_at IS NULL OR
// next_attempt_at <= now) ORDER BY seq` — the ordering is over what is **due**, not over the
// queue. A `measurement` that failed once is in backoff and is not due; a withdrawal enqueued
// afterwards has a NULL `next_attempt_at` and is. So the withdrawal lands first, finds nothing,
// answers `applied` — screen 17 says the reading was withdrawn — and twenty minutes later the
// reading itself arrives and is counted by `GET /me/grove` forever. That is exactly the sentence
// E280 exists to prevent, arriving by the clock instead of by the code.
//
// So a reading looks for its own withdrawal on the way in, and is born tombstoned if it finds one.
// This mirrors `anonymized_contributions`, which is consulted before the insert for the same reason
// stated in `Apply`: an item written on Wednesday and drained on Thursday cannot be stopped by a
// column on a row that does not exist yet, so the mark has to be waiting for it.
//
// ── What this does not close: two drains overlapping in time ───────────────────────────────────
//
// The guard above is a lookup, not a lock, and it can only find a row that has **committed**.
// `Apply` runs each mutation in its own transaction at READ COMMITTED — `Store.Tx` calls
// `pool.Begin` with no `TxOptions`, so the isolation is the server's default — and nothing makes
// two transactions about the same reading block each other: neither
// `contributions_measurement_reading_id` nor `contributions_withdrawn_reading_id` is a unique
// index, and the reading id is not a key anywhere in this schema. So a reading in one open
// transaction and its own withdrawal in another are mutually invisible: `withdrawMeasurement`
// counts `matched == 0` and answers success, this function returns false and the reading is born
// live, both commit, and `GET /me/grove` counts it. That is E280's sentence again — a service
// reporting a removal it did not perform — at millisecond scale instead of at backoff scale, and
// it is reachable in the multi-device case `Mutation.WithdrawnMeasurementID`'s own comment
// invokes: one device draining the reading while another drains the withdrawal.
//
// It is **not** a regression — before this round the kind was refused outright, so nothing about
// it worked at all — and it is deliberately not fixed here. The direction is filed as the top
// server item in `docs/ROADMAP.md`'s chip backlog: a transaction-scoped advisory lock on the
// reading id taken at the top of both this function and `withdrawMeasurement`, which would
// serialise only same-reading pairs. **That shape is unverified** — nobody has built it or
// red-proved it — which is why it is a filed direction rather than a line of code here.
//
// **Scoped to the same owner**, which is the whole of the safety argument. Without it, an item
// naming any reading id at all would arm a tombstone for a reading nobody had sent yet, and a
// stranger could silence somebody else's number before it arrived by guessing nothing — the ids
// travel in every `GET /me/journal` payload. With it, the arm exists only where the withdrawal
// would have been allowed anyway.
func measurementWasWithdrawn(ctx context.Context, tx pgx.Tx, id uuid.UUID, owner Owner) (bool, error) {
	var withdrawn bool
	err := tx.QueryRow(ctx, `
		SELECT EXISTS (
		    SELECT 1 FROM contributions
		     WHERE kind = 'measurement_withdrawal'
		       AND upper(payload ->> 'measurementID') = upper($1)
		       AND (($2::uuid IS NOT NULL AND user_id = $2) OR ($3::uuid IS NOT NULL AND device_id = $3))
		)
	`, id.String(), owner.UserID, owner.DeviceID).Scan(&withdrawn)
	return withdrawn, err
}

// tombstoneOnArrival marks a reading that arrived after its own withdrawal.
//
// It is a second statement rather than a column on the insert because the insert is shared by every
// kind and this is a fact about one of them; and it runs in the transaction that inserted the row,
// so there is no moment at which the reading is stored, live, and readable.
func tombstoneOnArrival(ctx context.Context, tx pgx.Tx, key uuid.UUID, now time.Time) error {
	_, err := tx.Exec(ctx, `
		UPDATE contributions SET deleted_at = $2, updated_at = $2 WHERE client_uuid = $1
	`, key, now)
	return err
}
