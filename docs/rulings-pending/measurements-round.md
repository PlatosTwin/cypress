# Rulings pending — the measurements round (F26, F27, F28, and F16's refusal) (2026-08-31)

Unnumbered, per CLAUDE.md "Numbering and shared files". The orchestrator splices these under real
numbers at merge and rewrites any comment that cites this filename. Nothing in `Cypress/`,
`CypressTests/` or `CypressUITests/` cites it — the code comments name the reports (F26, F28) and
the rules they turn on, never this file.

Four entries. **One is an owner ruling already made** (F26), **one is an owner refusal already
made** (F16), and **two are this round's proposals** (F28's affordance, F27's blocked design),
implemented or written down so they can be looked at rather than imagined. A reviewer who disagrees
with either proposal is disagreeing with a branch, not with a decision.

---

### R??? — The unit flip keeps the typed digits and annotates them (owner ruling)

**Date:** 2026-08-31. **Decided by:** the owner, via the orchestrator, answering tester report F26.
**Status:** ruled; the copy and its placement are the branch's and await ratification.

#### What was reported

Screen 16 emptied the keypad whenever the reader tapped `switch to inches`. A tester reported it as
data loss: four digits typed one-handed against a tape, gone for a tap that was meant to change how
they were labeled.

#### What was decided

**Keep the digits, and annotate.** Switching cm↔in or m↔ft leaves the entry exactly as typed — 5
stays 5, never converted — and the screen states that the meaning under it moved.

#### The argument the ruling answers rather than overrules

The clear was not arbitrary. Its comment made a real case: `64 cm` silently becoming `64 in` is a
2.5× error written to an append-only record "with nothing on screen to catch it", and retyping four
digits was called the cheap half of that trade. **The annotation is the something on screen.** With
it, the dangerous outcome the clear was guarding against is the one outcome the reader is told
about; without it, keeping the digits would be precisely the error that comment describes. The two
halves are one ruling, and `MeasurePresentationTests` asserts them in one test for that reason.

#### The premise that was wrong, corrected here

ROADMAP's F26 entry said keeping the digits "would falsify" `Quantity.value`'s invariant — "the
number as the human typed it, in `unitEntered`. Never silently converted for display". **It would
not, and the distinction matters enough to write down.** That invariant governs the *stored record*.
A `Quantity` is only ever built at save, out of whatever digits and unit the pad holds in that
moment, so a reader who types 5, flips to feet and saves stores `value: 5, unitEntered: ft` — the
number as typed, in the unit it was typed in, which is what the invariant asks for and all it asks
for. What would break it is converting the digits on the flip, and nothing converts.

What the flip genuinely risks is a *reader* who does not notice the meaning moved under an unchanged
number. That is a screen problem, and it has a screen answer. `Quantity.value`'s doc comment now
records this so the next person to read the invariant does not re-derive the wrong conclusion from
it.

#### The copy, and what it deliberately does not say — **awaiting ratification**

> Typed in centimeters, now read as inches.

**NOT SPECIFIED** by SCREENS.md; proposed under DECISIONS constraint 21.

- **Both units are named.** Neither is left to be inferred from the label above it, because the
  whole safeguard is that the reader can see the change rather than reconstruct it.
- **Two facts and no instruction.** It does not say "retype if you meant something else", because
  retyping is only one of two correct responses and the screen cannot tell which the reader meant:
  somebody who typed the number under the wrong unit and then fixed the unit is already looking at
  what they wanted.
- **Placed under the readout, not above the CTA.** It describes the number on screen now, rather
  than something to weigh before saving, and a sentence about `64` belongs beside the 64. The
  anomaly line and the chart notice keep their place above the CTA.
- **Drawn in the anomaly line's amber** (`CypressColor.amberChipSelectedText`), reusing that line's
  treatment for its own stated reason: Signal Amber is the screen asking about a number (§1.1),
  which is exactly what this is. No new token, no new component.

#### When it withdraws

It stands until the digits are gone, and dies with them:

- **Cleared when the entry empties** — by backspace, by saving, or by changing the measurement kind.
- **Not cleared by a partial edit.** Backspacing `64` to `6` leaves a digit that was still typed
  under the old unit, and appending to it makes a number that is partly old, so no edit short of
  emptying the field makes these digits honestly the current unit's. The conservative rule is the
  one that cannot leave the annotation off a number that needs it.
- **Withdrawn by a second flip back**, which returns the digits to the unit they were typed in.
  There is then nothing to annotate, and a notice that stayed would be a stale sentence about a
  number it no longer describes.

Changing the *kind* still clears the entry outright, and this ruling does not reach it: a unit flip
asks the same question in other units, where the digits are still an answer worth keeping; changing
kind asks a different question, and a trunk's 64 is not an answer about a height.

#### What holds it

`MeasurePresentationTests` — four tests: the digits and the annotation together, the flip back, the
empty pad, and the backspace boundary. Red-proved twice, because the two halves fail independently:
reverting `switchUnit` to the old clear failed with `(draft.entry → "") == "64"` and
`(unitFlipNotice → nil) == "Typed in centimeters, now read as inches."`; suppressing only the
annotation while keeping the digits failed with the second of those alone, which is the safety
property stated as a test.

---

### R??? — Screen 03 keeps a door into screen 16 when no stat card is one (proposed)

**Date:** 2026-08-31. **Proposed by:** this round, from tester report F28. **Status:** awaiting the
owner.

#### What was reported

> adding a reading on a tree holding both height and DBH is two small-text taps deep

#### Why it was two taps

R15 gave each measurement its own door — the empty stat card, which opens screen 16 on the kind it
names. R15 also said plainly what that leaves behind: the slot "exists only while its own
measurement is missing", so a tree carrying both a height and a DBH has no card door at all. The way
through was `See every reading` into screen 11, then screen 11's own `Add a reading`. Both are 13 pt
text links, which is the "small-text" half of the report.

That tree is the one with the most growth left to record, and it is the one the app made hardest to
measure.

#### What is proposed

**While a tree accepts contributions, screen 03 offers exactly one way into screen 16 — and never
two.** Usually that way is an empty stat card. When every measurement is already on file there is no
empty card to be one, and an `Add a reading` link is drawn instead, directly under
`See every reading`.

- **Built as `growthLink`'s twin**, down to the token: same `CypressFont.body13Bold`, same
  `CypressColor.ctaFill`, same 44 pt hit area, same gutter, no top gap when it follows that link so
  the two read as one block. C1–C30 has no link component and a screen-local control from tokens is
  what this codebase does where the catalog has no entry (E46), so the way to make two neighboring
  links read as one kind of thing is to build them the same.
- **Same three words the rest of the app uses.** `Add a reading` is the empty slot's phrase and
  screen 11's; a reader who met it on a half-measured tree meets the identical phrase here.
- **Opens on DBH**, borrowed from `GrowthHistoryPresentation.addReadingKind` rather than restated,
  so the two general entrances cannot drift apart. This entrance names no measurement, as screen
  11's does not (R15); 16 §2's drawn selection is `Trunk · DBH` and the kind control is the first
  thing on that screen.
- **Keyed off the stat items, not off the measurements.** The DBH slot is also suppressed by a
  published city bucket, and a reader looking at a city range has no card door either. Asking the
  items is asking the question the reader can actually see.

**NOT SPECIFIED** — no mock draws this link — so it goes to the owner under DECISIONS constraint 21,
by ARCHITECTURE §5 rule 8's practice of going to the nearest specified thing, which here is the link
one block up.

#### What was considered and not done

- **Making a filled stat card open screen 16 again.** It is where the sentence reads most naturally
  and it cannot keep its promise: R15 deliberately points a card holding a reading at screen 11, so
  a reader who wants the history would lose the only door to it. Trading one missing door for
  another is not a fix.
- **Drawing the link always.** Two invitations a card apart, both reading `Add a reading`, is F28
  answered by making the screen worse. The second half of the rule exists to forbid it, and a UI
  test asserts it on an unmeasured tree.

#### What holds it

`MeasureEntranceKindTests` asserts the invariant across six states — nothing on file, a height only,
a DBH only, both, a city bucket with a height, a city bucket with nothing — rather than on the
fully-measured branch alone. **The invariant in that test is not the one this round started with.**
The first draft asserted "exactly one door in total" and went red on the empty tree, which has two
empty slots, one per measurement — R15's per-kind door working correctly. The rule that survived
measurement is "never none, and the link only where no card is one". The city-bucket row is the one
a narrower test would have missed.

`AddReadingReachabilityTests` walks it on the device, because a presentation flag proves a struct
and not a finger: it checks the tree really is fully measured first, then that the link exists, is
hittable, and that pressing it opens screen 16 with its keypad. Red-proved both ways — suppressing
the link failed with "a tree carrying every measurement offered no way into screen 16 from its own
profile"; drawing it unconditionally failed the unmeasured-tree test with "the profile now invites
the same contribution twice".

---

### R??? — Withdrawing a measurement: the design, and why no code ships with it (proposed, blocked)

**Date:** 2026-08-31. **Proposed by:** this round, from tester report F27. **Status:** blocked on a
writable-schema migration this round was not authorized to write. Nothing here is implemented.

#### The half of F27 that needs nothing built

F27 reads "measurements can be neither edited nor deleted". **"Edited" is not a gap in the measure
surface; it is the app's design, everywhere.** There is no edit verb for any contributed record:
`CypressAPI`'s write surface is append-or-withdraw end to end, species corrections supersede rather
than overwrite and keep the superseded row pointing forward, and every capture screen carries the
whole burden in its pre-submit confirmation precisely because nothing can be amended afterwards.
Changing a reading is adding a reading, which screen 16 already does — and F28's link, shipped in
this round, is what makes that one tap on the tree where it was two.

If the owner wants measurements to be genuinely editable, that is a change to the append-only
premise the record is built on, and it is a much larger question than F27 as filed. This entry
assumes it is not.

#### The half that is real: withdrawal

`measurements.deleted_at` exists, `TreeMeasurement.deletedAt` is honored by `isChartable` and by
every list on screen 11 and screen 03 — and nothing anywhere sets it. The design, matching photo
withdrawal beat for beat, would be:

1. **`OutboxItem.Kind.measurementWithdrawal = "measurement_withdrawal"`**, a kind of its own.
2. **A `MeasurementWithdrawal` payload** beside `PhotoWithdrawal` in `CommunityMutations.swift`:
   `clientUUID`, `measurementID`, `treeID`, `attribution`, `occurredAt`. The act, not its report —
   no counts travel, for `PhotoWithdrawal`'s stated reason.
3. **`LocalAPI.withdrawMeasurement(id:)`**, tombstoning the row and queueing the withdrawal **in one
   transaction**, after the ownership gate has matched and before anything else — so the queued row
   exists only for a withdrawal that was allowed and committed. `isAppliedBeforeItIsQueued` is true
   for it, as for every §3.4 kind, so the drain owes it the send and the apply sink refuses it.
4. **A row-level affordance on screen 11's growth log**, which is the only place a single reading is
   drawn. `TreePhotosView`'s idiom: a trash control on the row, one tap opening a
   `confirmationDialog` with a destructive confirm and a `Keep it` cancel, drawn in the amber hazard
   ramp because this palette has no red. Copy would need to say what withdrawal does to a chart,
   which the photo copy has no equivalent of.
5. **`OutboxPresentation.kindLabel`** gains a row title, as `photoWithdrawal`'s "Photo removed" did.

#### Why the code is not here

**Step 1 is a writable-schema migration.** `outbox.kind` is a closed `CHECK` vocabulary and SQLite
cannot widen a `CHECK` in place, so a new kind is a table rebuild — `AppSchema` v4 and v17 are both
exactly that, and v17's comment says so. The writable schema's migration counter is
`AppSchema.currentVersion`, computed as the highest entry in `AppSchema.migrations`; reading it from
the code rather than from any prose, the next number is the one after v18.

This is not avoidable by care. `CommunityOutboxKindTests`' "every kind the app can build is one the
outbox can store" iterates `OutboxItem.Kind.allCases` and inserts each, deliberately so that an
eleventh case added to the enum and forgotten in the migration fails loudly — "the symptom is a
mutation that succeeds locally and cannot be queued". Adding the enum case without the migration
turns that test red, correctly.

**CLAUDE.md: one migration author per round, named explicitly, and this round was not named.** So
the design is written down and the code is not.

#### The two shortcuts, and why both are wrong

- **Ride the existing `.measurement` kind with a discriminator in the payload.** The payload column
  is `json_valid` only, so this needs no migration — and `OutboxItem.Kind`'s own comment forbids it
  in terms that fit this case exactly. The review-dismissal pair is kept as two cases rather than
  one-with-a-boolean because collapsing them "would put that distinction inside a payload field
  where `outbox.kind` cannot see it", and `outbox.kind` is what screen 17 groups by and what the
  server dispatches on. A withdrawal arriving as a `measurement` would also be a false statement on
  an append-only server record.
- **Ship the UI and the tombstone, leave the sync for later.** This re-creates the Class L debt that
  spec §3.4's nine mutations were queued to pay off, and it does so on the worst possible surface: a
  delete the reader is shown, believes, and which never leaves the phone. A missing delete is a
  known gap; a delete that lies is a defect.

**Recommended:** schedule F27's withdrawal in the next round with a named migration author, and hand
them this entry. The work above it is small once the vocabulary can hold the kind.

---

### For the record — F16 refused (owner)

**Date:** 2026-08-31. **Decided by:** the owner, via the orchestrator. **Status:** refused; no code.

F16 asked for trees-seen counters — 30 days, this year, lifetime. It was carried on the backlog as
BLOCKED ON A RULING because it needed the owner to amend or refuse the rule it runs into, rather
than because anyone was unsure what the rule said.

**Refused. The rule stands as written.** ARCHITECTURE §5 rule 1, which is D1 in DECISIONS §3: "No
streaks, points, ranks, badges, or public counts of user actions. If you find yourself writing
`visitCount` into a user-visible string, stop." The report asked for the one thing that rule names,
so there was no version of it to build that would not have been the rule being set aside.

Recorded here rather than deleted from the backlog because a refusal is a decision, and the next
person to have the idea should find the answer rather than the idea. ROADMAP's entry is struck with
the citation.
