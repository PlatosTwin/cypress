-- 006 — photographs an account adopted while they were `pending` are approved, and an account's live
-- photograph can no longer be stored `pending`.
--
-- The owner's ruling of 2026-09-28: "Fix the sign-in approval gap now." `store.ClaimDevice` now
-- approves the pending photographs it adopts, in the statement that adopts them. That reaches every
-- claim from this deploy on and nobody whose claim has already happened — their photographs were
-- adopted `pending` and nothing in the service ever revisits a row's moderation state. This file is
-- the other half: it gives those rows the state the fixed claim would have given them.
--
-- ── What this does not do, because R77 forbids it ──────────────────────────────────────────────
--
-- Nothing is uploaded, and nothing here could cause an upload. RULINGS R77 forbids any backfill of
-- data that never left the phone; a photograph that never reached this service stays on the phone.
-- This file changes the visibility of rows **already in this table** and touches no other table.
--
-- ── The predicate selects exactly the adopted-while-pending set ────────────────────────────────
--
-- `user_id IS NOT NULL AND moderation_state = 'pending' AND deleted_at IS NULL AND
-- anonymized_at IS NULL`. The argument, read from the code at 005 rather than asserted:
--
--   * `moderation_state` has two writers before this round. `BeginPhoto`'s INSERT — the only INSERT
--     into `photos` in the service — writes `approved` when the caller is an account and `pending`
--     only when it is a device. `RejectPhoto` writes `rejected`. Nothing writes `pending` onto an
--     existing row, so a row that is `pending` now has been `pending` since it was inserted, and
--     was inserted by a device.
--   * `user_id` has three writers. That INSERT (an account, hence `approved`); `ClaimDevice`'s
--     adoption; and the two account-deletion statements plus `ON DELETE SET NULL`, all of which
--     write NULL. So a row that is `pending` with an owner got the owner from a claim, and was
--     `pending` when the claim ran — which is the set.
--   * `deleted_at IS NULL` leaves withdrawn rows alone: nobody is served one either way, and
--     approving it would record an approval of something its contributor took back.
--   * `anonymized_at IS NULL` is defense in depth. Anonymization writes `user_id = NULL` in the same
--     statement, so no anonymized row reaches `user_id IS NOT NULL` through the code.
--   * `rejected` is not `pending`, so an operator's takedown stands; an `approved` row is not
--     `pending`, so its existing reason is left alone.
--
-- The reason written is `auto_approved_launch`, because that is what the row would carry had its
-- account begun it: a first-party photograph, published unscreened and unblurred, from a signed-in
-- account. The column exists to keep screened and unscreened apart for a future pipeline, and that
-- distinction survives; no consumer in the service or the app needs "approved at upload" told apart
-- from "approved at sign-in", and a third value would cost a CHECK change for nothing.
--
-- ── Why this file adds a constraint, and why that is not only for the guard ────────────────────
--
-- 001's rule, restated in 004's header, is that a migration fails loudly if it is applied twice, and
-- `TestOnlyPendingMigrationsRun` works by re-running the newest file and requiring it to fail. A
-- bare `UPDATE` re-applies silently — its WHERE simply finds nothing the second time — and would
-- give that test nothing to observe.
--
-- The `ADD CONSTRAINT` below is what fails the second time (the name already exists). It is not
-- there *only* for that. It states the invariant this round establishes — an account's live
-- photograph is never `pending` — in the one place a future writer cannot forget it, which is
-- `photos_approval_reason`'s argument in 001 ("the obligation made structural rather than
-- remembered"). An adoption path that moves a photograph onto an account without approving it is
-- then refused by the database instead of silently making a photograph private for good, which is
-- the defect this file exists to repair. And because it is validated against the table as the
-- `UPDATE` just left it, inside the same transaction, the migration checks its own work: had the
-- predicate missed a row, the constraint would refuse to be added, the whole file would roll back,
-- and the service would refuse to boot with the database still at 005 rather than half-applied.
--
-- **The constraint encodes R72 ruling 5's launch rule.** The screening round that ends
-- auto-approval — the one that will write `screened_and_passed` — will want an account's upload to
-- wait in `pending`, and has to drop this constraint to do it. That is intended: ending the launch
-- rule should be a decision somebody writes down, not a side effect.

UPDATE photos
   SET moderation_state = 'approved',
       approval_reason  = 'auto_approved_launch',
       updated_at       = now()
 WHERE user_id IS NOT NULL
   AND moderation_state = 'pending'
   AND deleted_at IS NULL
   AND anonymized_at IS NULL;

ALTER TABLE photos ADD CONSTRAINT photos_owned_live_photograph_is_not_pending CHECK (
    user_id IS NULL
    OR moderation_state <> 'pending'
    OR deleted_at IS NOT NULL
    OR anonymized_at IS NOT NULL
);
