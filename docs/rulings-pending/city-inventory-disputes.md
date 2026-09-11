# Rulings pending — city-inventory disputes, part 1 (R79, 2026-09-10)

Unnumbered, per CLAUDE.md "Numbering and shared files". The orchestrator splices these under real
numbers at merge. Nothing in `Cypress/`, `CypressTests/` or `CypressUITests/` cites this filename —
the code comments name `RULINGS R79`, which is already numbered, and the rules they turn on.

**R79 is the owner's spec and is not restated here.** What follows is the round's own decisions: the
owner's three, taken in a decision round on 2026-09-10 after R79 was written, and the orchestrator's
three, which are the round's and not the owner's. The three orchestrator rulings are the ones that
need review.

---

### R??? — City-inventory disputes ship in four PRs, and part 1 is the record

**Date:** 2026-09-10. **Decided by:** owner, via decision round. **Status:** decided.

R79 describes one feature with five surfaces. The owner split it:

1. **Part 1 (this round).** The writable-schema migration, the dispute record and its two verbs, and
   city rows ceasing to answer `.unavailable` on the tree profile. Client (PR-A) and the server's
   sync vocabulary (PR-B); the dispute sheet itself is PR-C.
2. **Deferred to their own PRs**, each scheduled separately: the flag **badge** on the map and the
   list, the **"trees with data issues"** filter, the **missing-tree entry point** (the defect the
   profile screen cannot host, because there is no record to open), and the **community-flagging
   redesign**.

### R??? — Disputes queue to `cypress-sync`; they are not local-only

**Date:** 2026-09-10. **Decided by:** owner, via decision round. **Status:** decided.

A dispute is a contribution and reaches an account the way every other one does — a new
`OutboxItem.Kind`, a new server sync kind, a server migration. The alternative on the table was
storing disputes on the device alone until an adjudication surface exists; the owner refused it.

### R??? — The community flagging flow is a separate later round

**Date:** 2026-09-10. **Decided by:** owner, via decision round. **Status:** decided.

R79's addendum records two owner reports against the shipped community flagging view: bad copy
throughout, and a flag that its author cannot retract. Both go through a design pass with owner
decision rounds — the copy, the retractability, and the report/withdraw/keep state machine — rather
than being touched here. **Today's community boolean flags are untouched by this round**, and part 1
asserts that rather than assuming it (`DataDisputeTests.theRoundDisputesCityRowsOnly`).

### R??? — The entry point, the location answer, and the two metadata examples

**Date:** 2026-09-10. **Decided by:** owner, via decision round, after the authors were briefed.
**Status:** decided. **This is what fixes `tree_dispute_suggestions.field`'s vocabulary.**

1. **Entry point (PR-C).** The dispute action goes exactly where the community flag actions already
   sit on screen 03 — the text-action area that today draws "Report the species as wrong" / "Report
   that there is no tree here". A city tree draws the dispute action there instead. Not under the
   City record block, and not through the quad row's `Report`, which stays the 311/neighborly door.
2. **"Pin in wrong location" is answered with the reporter's own fix, not a map picker.** You are
   standing at the tree; the GPS fix is the correction. It refuses a fix too coarse to mean anything,
   on the precedent of `AlmanacLimits.fixCanResolveAnArea(accuracyM:withinM:)`. No map picker in
   part 1.
3. **"Wrong other metadata" is the owner's two examples and nothing else**: a clearly wrong planted
   year, and a recorded tree whose plot is actually empty. The second is **not a boolean** — it is a
   status suggestion of `vacant_site`, which is already in the status vocabulary, so the profile's
   existing vacant-site handling means something when a dispute is one day adjudicated.

Therefore `tree_dispute_suggestions.field` is CHECKed against exactly `lat`, `lon`,
`location_accuracy_m`, `species_id`, `planted_year`, `status`.

---

## The orchestrator's three, which are this round's and not the owner's

### R??? — Part 1 ships raise **and** withdraw

**Date:** 2026-09-10. **Decided by:** the round's orchestrator. **Status:** awaiting review.

The owner's standing complaint about the community flagging flow is that a flag cannot be retracted
by its author (R79's addendum). Shipping a new dispute surface with the same defect repeats it on
new ground, and a dispute is the worse place for it: a community flag has a lead who can dismiss it,
where a city dispute has nobody on this device who can do anything with it at all.

The cost is a verb and a payload, not a second migration seat: `outbox.kind`'s `CHECK` is one
statement whether it admits one value or two, and `AppSchema` v22 writes it once.

**As built:** `withdrawDataDispute(disputeID:)` stamps `withdrawn_at`, deletes nothing, and queues
`data_dispute_withdrawal`. The authorship rule is `TreeDataDispute.isAuthored(by:)` — a leading
refusal for a row the leaving door un-named (see the deletion-door ruling below), then the account
arm, plus a `raised_by IS NULL` arm that is this *installation's* own anonymous row and stays its own
to take back after signing in (D9). A signed-out reader is not handed an account's dispute, which is
`LocalAPI.withdrawMeasurement`'s asymmetry kept deliberately.

### R??? — City rows only, this round

**Date:** 2026-09-10. **Decided by:** the round's orchestrator. **Status:** awaiting review.

R79 gives community trees location and species disputes too. They are not built here. Community rows
keep `flagWrongSpecies` / `flagNeverExisted` exactly as they are, and the two verbs added by this
round are the mirror image of those two: they refuse a **community** row with `.forbidden` and serve
a city one.

The reason for the split is that community disputes converge with the community flagging redesign —
"location and species only" is a *narrowing* of a surface that already exists and is already ruled
not-quality, not an addition to it. Building it here would mean designing the convergence twice.

### R??? — An anonymized dispute is withdrawable by nobody

**Date:** 2026-09-10. **Decided by:** the round's orchestrator, adjudicating PR #165's review.
**Status:** awaiting review.

`tree_data_disputes` is one more table carrying a user column, and when v22 added it neither
account-deletion door could see it. Both now do: the leaving door nulls `raised_by`, the erasing
door deletes the row and the two `ON DELETE CASCADE` children go with it.

The half that is a decision rather than an omission repaired is **what the leaving door's NULL then
means**. It is not a free choice, and that is the whole of this ruling: **the other half of the
system has already answered, and it is the half that cannot move.**
`server/internal/store/disputes.go`'s `disputeIsThisIdentitys` counts a dispute as the caller's on a
`user_id` or a `device_id` match; `.leaveRecords` clears both; a comparison against two NULLs falls
out of its `FILTER`, so an anonymized row counts in `matched` and not in `mine` and is refused. The
function's own comment states the rule — "a record owned by nobody is not withdrawable by anybody" —
and `TestAnAnonymizedDisputeIsWithdrawableByNobody` measures it. The service could not adopt the
client's other answer even in principle: `ClaimDevice` has already folded the row's `device_id` into
its `user_id`, so after the deletion there is no installation identity left on the row to compare a
signed-out phone against.

So an anonymized dispute is authored by nobody: not withdrawable, and **no withdraw affordance is
offered for it**. Had the client kept the opposite answer, the sequence would have been: the phone
offers the withdrawal, applies it locally, queues `data_dispute_withdrawal`, and the service answers
`forbidden` — landing on the screen-17 dead end `docs/ROADMAP.md` already carries as a chip ("Decide
what a signed-out phone can take back"), with the phone showing the dispute as withdrawn while the
service went on holding it. That is this project's signature failure applied to a withdrawal, and
the shape ERRATA **E280** records for `photo_withdrawal`, reached through a third verb.

**How the two NULLs are told apart, and why no new table was needed.** The leaving door's NULL lands
the row in exactly the shape D9's ordinary case occupies — a dispute raised on this phone before it
had an account — so `raised_by` alone cannot carry the answer. That is the same problem `measurements`
has (`device_id` is NOT NULL there, so a reading is never ownerless by columns) and it gets the same
existing mechanism: the `client_uuid` goes into `anonymized_contributions`, `AppSchema` v13's
tombstone, before the `UPDATE` that stops the predicate matching.
`TreeDataDispute.isAuthored(by:)` refuses on it as its first line — R3 is not a clause in an `||`,
which is `PhotoOwner.permitsRemoval`'s ordering — and `DataDisputeStore`'s `WHERE` clauses carry the
same refusal so the Swift gate and the SQL gate cannot say different things.

**Disputes raised while signed out are untouched.** The deletion predicate is `raised_by = :user`,
which a NULL never matches, so nothing about such a row changes and no tombstone is written for it.
It stays this installation's to take back, before and after signing in, which is what R-a above
describes. `AccountDeletionTests.theLeavingDoorAnonymizesADispute` asserts the whole chain — the
un-naming, the surviving children, the refusal of the withdrawal to the next account **and** to the
signed-out phone, and the untouched signed-out dispute beside it — with a `review_flags` row raised
by the same account as calibration, so a green cannot mean the harness looked at nothing.

**Owed to the badge round, not to this one:** no guard enumerates the tables carrying a user column.
`forgetAccount` has gone stale three times in this repo — twice on the outbox kind list, once here on
a whole table — and each time the omission matched nothing and failed silently. The outbox half was
fixed by making the enum exhaustive so the compiler asks the question; the table half has no
equivalent, and designing one is the fix worth making rather than a fourth hand-audit. It is in
`docs/ROADMAP.md`.

### R??? — The server records a dispute; it does not materialize one

**Date:** 2026-09-10. **Decided by:** the round's orchestrator. **Status:** awaiting review.

No dispute tables server-side. PR-B widens `contributions.kind` and `syncKinds` and validates the
payload, and that is all — the same position `sync.go` already takes for the eight kinds it records
without evaluating. Adjudication is a web deliverable (ARCHITECTURE §8), and a service that guessed
at a dispute's effect would move city data on a say-so nobody weighed.

The consequence worth stating: **the badge round is what needs a read endpoint.** Part 1's profile
offer is answered entirely from this device's own rows, which is correct for "may I dispute this,
and is mine standing" and is not enough for "does this tree carry other people's flags".

---

## One place this round departed from the contract it was given, and why

`tree_data_disputes.tree_source` was specified as `CHECK (tree_source IN ('city','community'))`. It
is built as `CHECK (tree_source IN ('city_import','community'))`, which is `TreeSource`'s two raw
values — measured against the shipped seed, whose `trees.source` holds `city_import` for all 198,625
rows, and against `community_trees.source`'s own `CHECK (source = 'community')`.

`'city'` would have been a third spelling of a two-valued fact, in a column no other layer reads as
text. Nothing outside PR-A depends on the literal: PR-B stores no dispute rows at all (the ruling
above), and PR-C reads a `TreeSource`. `SchemaV22Tests.theDisputeTablesCarryTheirVocabularies`
asserts the column refuses `'city'`, so the choice is pinned rather than assumed.
