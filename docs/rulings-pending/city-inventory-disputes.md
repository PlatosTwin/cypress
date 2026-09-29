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

**Disputes raised while signed out are untouched, and this ruling does not reach them.** The
deletion predicate is `raised_by = :user`, which a NULL never matches, so nothing about such a row
changes and no tombstone is ever written for it. On the client it stays this installation's to take
back, before and after signing in, which is what R-a above describes;
`ContributionStore.claimDevice` does not touch `tree_data_disputes` either — there is no device
column on it to re-home — so the row is still `raised_by IS NULL` and still un-tombstoned after a
claim and a deletion both. `AccountDeletionTests.theLeavingDoorAnonymizesADispute` asserts the whole
chain — the un-naming, the surviving children, the refusal of the withdrawal to the next account
**and** to the signed-out phone, and the untouched signed-out dispute beside it — with a
`review_flags` row raised by the same account as calibration, so a green cannot mean the harness
looked at nothing.

**Where that leaves the two halves disagreeing, said plainly rather than left to be discovered.**
The ruling above holds only for the dispute raised *while signed in* and then anonymized, because
that is the only row a `raised_by = :user` tombstone can ever mark. For a dispute raised before
sign-in the client and the service part company after a `claimDevice` and a `.leaveRecords`
deletion: the client's profile still offers the withdrawal and the next account on the phone can
take it back, while the service — whose `ClaimDevice` folded that row's `device_id` into a `user_id`
before the deletion cleared both — answers `forbidden`. That is the same E280-shaped dead end this
ruling avoids for the signed-in row, reached from the other direction, and **it is parked rather
than solved.** It belongs to `docs/ROADMAP.md`'s chip "Decide what a signed-out phone can take back"
— the same chip `store.disputeIsThisIdentitys` defers its own copy of this divergence to. Closing it
here would mean narrowing the `raised_by IS NULL` arm, which is D9's arm: a signed-out contributor
would lose the ability to retract their own standing objections, which is a decision neither half of
this round was given.

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

---

# Part 2 — the dispute screen (PR-C, 2026-09-28)

### R??? — The dispute screen's shape: four plain choices, screen 06's chips, a pushed screen

**Date:** 2026-09-28. **Decided by:** owner, via decision round. **Status:** decided.

Three rulings, taken together, on the screen R79 calls "checkboxes":

1. **Four plain options**, not R79's three with a submenu under "wrong other metadata":
   *Pin is in the wrong place* · *Wrong species* · *Wrong planted year* · *There's no tree here*.
   **Storage is unchanged** — the last two both file under `wrong_metadata`, the planted year as a
   `planted_year` suggestion and the empty plot as a `status` suggestion of `vacant_site`.
   `DataDisputeChoice.issue` is the one place the mapping is written.
2. **Screen 06's multi-select chips**, not literal checkboxes — the existing `Chip` component, in the
   neighborly pair (`structureFlagIdle` / `structureFlagOn`) that ERRATA E22 chose as those chips'
   selected appearance.
3. **A pushed screen modeled on screen 06** (SCREENS.md §06): C1 header, micro-labelled sections, a
   C14 dashed disclosure, a C6 primary button pinned under the scrolling form the way screen 05 pins
   its own. Not a bottom sheet. The route is `Route.dataDispute(UUID)`; its one entrance is the
   record-defect text action on screen 03, per the 2026-09-10 entry-point ruling above.

## The author's decisions on the screen, which are PR-C's and not the owner's

### R??? — A fix over the 10 m floor is refused out loud and left off the report

**Date:** 2026-09-28. **Decided by:** PR-C's author. **Status:** awaiting review.

The 2026-09-10 ruling keeps `DataDisputeLimits`' floor and requires the refusal to be explained.
There were two ways to honor that at the moment the reporter taps *Use my current location* with a
coarse fix: hold the fix in the draft and refuse the whole report at *Send*, or refuse the fix on the
spot and leave it off. The screen does the second. The location block replaces its hint with the
refusal sentence — both numbers, "so it was not used", and *Turn on Precise Location for Cypress in
Settings, then try again* — and offers *Open Settings*. The report stays sendable, because "the pin
is wrong and my phone cannot say where the tree is" is a report the record model already admits
(every suggestion is optional).

The sentence is `DataDisputeCopy.refusal(.locationFixTooCoarse)`, computed by asking
`DataDisputeLimits.refusal` itself about the fix, so the words under the control and the rule the
API enforces cannot disagree. The alternative would have held a report hostage to a fix the reporter
may not be able to improve standing where they are.

### R??? — The take-back has no confirmation dialog

**Date:** 2026-09-28. **Decided by:** PR-C's author. **Status:** **overruled** by the owner the same
day — see "The take-back asks first" below. Kept here as the record of what was proposed.

*Take back your report* withdraws at once, like the record-defect block's other text actions. It is
recoverable — the offer returns to *Report a mistake in the city's record* and a new report can be
raised — and a confirmation in front of the one control the owner has said must exist would put a
step between an author and their own retraction.

### R??? — The number pad gets a keyboard-toolbar *Done*

**Date:** 2026-09-28. **Decided by:** PR-C's author. **Status:** awaiting review.

The planted-year field uses the number pad, which has no return key. Without a way to put it away it
covers the notes, the disclosure and, on a small phone, the button. A keyboard-toolbar *Done* is the
platform's own answer; it is one more string for the owner's copy ruling.

---

## PR-C's rulings after review (2026-09-28)

Rulings 1–4 are the owner's, taken on the screenshots before the adversarial review. Ruling 5 is the
owner's, after it. Rulings 6–10 are the orchestrator's, after the review, implementing the owner's
standing instruction that the floor's refusal be explained. The numbers are this list's own, for
cross-reference in PR #185; they are not RULINGS numbers.

### R??? — "There's no tree here" stands alone (ruling 1)

**Date:** 2026-09-28. **Decided by:** owner. **Status:** decided.

Choosing *There's no tree here* clears the other three chips and disables them; unticking it enables
them again, unticked. An empty plot has no position, species or planted year to correct, and a report
claiming both was two contradicting statements (PR #185's own open question). It also closes review
finding 4: *no tree* plus an empty *Wrong planted year* used to store exactly what *no tree* alone
stored. **As built:** `DataDisputeDraft.toggle` and `isDisabled`; a value typed under a cleared chip
is still held and comes back if the chip is chosen again, because `suggestions` reads a value only
under its own chip.

### R??? — Each opened section says what the city has (ruling 2)

**Date:** 2026-09-28. **Decided by:** owner. **Status:** decided.

Under each opened section, one quiet line: *The city has: …* — the species, the planted year, the
position. **As built:** `DataDisputeOnFile`, drawn in `body135` / `textMuted`, the register of the
notes under screen 03's *What the city has on file*. The species is named as the profile names it
(common name, else scientific; a stub the ingest never read is quoted in the city's own wording, or
not at all — R54). The position is the record's street address, else its coordinate.

**A value the record lacks draws no line**, rather than "The city has no planted year". `nil` on this
phone means the copy of the inventory here carries none, which is not the same statement as the city
having none — a seed built before a column existed answers `nil` for a city that publishes it — and
DECISIONS constraint 15 forbids inventing civic content.

### R??? — The take-back asks first (ruling 3)

**Date:** 2026-09-28. **Decided by:** owner. **Status:** decided. **Overrules** the author's "no
confirmation dialog" above.

*Take back your report* opens *Take back your report?* before anything is withdrawn. **As built:**
the app's existing take-back question, `GrowthHistoryView`'s `confirmationDialog` — a destructive
action repeating the link's words, and *Keep it*. The owner kept the author's other two calls: a
coarse fix blocks only the pin part (refined by rulings 6–9 below), and the number pad's *Done*.

### R??? — The copy stands as shown (ruling 4)

**Date:** 2026-09-28. **Decided by:** owner. **Status:** decided.

The strings in PR #185's copy table are approved as shown in the screenshots. Only rulings 1–10 may
change or add strings, and every such string is listed in the PR body.

### R??? — A mistake report does not enroll a tree in *Yours* (ruling 5)

**Date:** 2026-09-28. **Decided by:** owner, after the review. **Status:** decided; **server change,
separate PR.**

Review finding 1 showed the server enrolling a disputed city tree in the reporter's *Yours* filter and
Grove, and keeping it there after the take-back. The owner ruled the enrolment wrong rather than the
copy: *Nothing on the map changes* stays, and the server stops counting dispute kinds as membership.
Until that PR merges, the disclosure's clause is false against the live service.

### R??? — The refusal sentence is true about why (ruling 6)

**Date:** 2026-09-28. **Decided by:** orchestrator. **Status:** decided.

The refusal names Precise Location and offers *Open Settings* **only when accuracy is reduced**
(`CLLocationManager.accuracyAuthorization == .reducedAccuracy`). With Precise Location on, a coarse fix
is the sky's doing, and the sentence says so: *Try again in the open, or wait a moment.* **As built:**
`MapLocationProvider.Precision.isReduced`, read in `apply(authorization:)` — which iOS also calls when
Precise Location changes — and carried to the screen in `DataDisputeFixReading`; the sentence is
`DataDisputeCopy.locationRefusal`. `CoreLocation` stays in `Features`; nothing in `Data` changed
(ARCHITECTURE §2). The rule's own `.locationFixTooCoarse` sentence, unreachable from the screen, no
longer names Settings, because that refusal cannot know whether Precise Location is off.

### R??? — A later, better fix replaces a refused one (ruling 7)

**Date:** 2026-09-28. **Decided by:** orchestrator. **Status:** decided.

While the screen is open the location block follows the provider in every state the reporter asked
for and did not get — waiting, refused, and off — so the coarse first fix after `start()` no longer
fixes the block on its refusal for good (review finding 2's repro). A **captured** fix is still not
replaced: it is the position the reporter accepted. **As built:** `DataDisputeLocation
.followsTheProvider`.

### R??? — No silent drops: Send waits for a pending fix (ruling 8)

**Date:** 2026-09-28. **Decided by:** orchestrator. **Status:** decided.

While the pin chip is on and the fix is still pending, *Send report* is disabled and the block says
*Finding your location…*. Review finding 3: sending then filed "the pin is wrong" without the position
and popped the screen. Once the fix resolves — captured, or refused out loud — the author's call 1
holds: a refused fix blocks only the pin part. **As built:** `DataDisputeDraft.isAwaitingFix`,
`DataDisputeModel.canSend`, and the same guard in `raise()`.

### R??? — An unstated accuracy is refused, and the substitute is never quoted (ruling 9)

**Date:** 2026-09-28. **Decided by:** orchestrator. **Status:** decided.

A fix CoreLocation stated no radius for (a negative `horizontalAccuracy`) reaches the app as 25 m,
`VisitShortlist.assumedAccuracyM`, so that D6 excludes it by arithmetic. The screen treats it as
refused and says *Your phone couldn't say how accurate your location is* — it never quotes 25 m, which
is the app's number and not the phone's. **As built:** `MapLocationProvider.Precision.accuracyIsKnown`,
set by the delegate beside the substitution; `DataDisputeLocationRefusal.accuracyUnknown`.

### R??? — The take-back is guarded against a double tap; the UI tests scroll (ruling 10)

**Date:** 2026-09-28. **Decided by:** orchestrator. **Status:** decided.

A second take-back while one is in flight does nothing, rather than reaching the API and drawing
*That report was already taken back.* beside the restored action (review finding 6). **As built:**
`TreeProfileModel.isWithdrawingDataDispute`, held across the reload. `DataDisputeUITests` scrolls to
every control before touching it, so it passes at the accessibility text sizes (review finding 7).

