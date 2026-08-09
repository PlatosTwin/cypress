### The species legend's AX5 ceiling lands part-way down a chip, so a clamped legend looks clamped (owner decision, task #72)

The ceiling task #258 gave `MapSpeciesLegend` is a subtraction, and a subtraction has no opinion
about where in the chip stack its answer falls. On the phones where it binds it landed, by
arithmetic accident, exactly where a reader cannot tell that it bound: on a whole number of chips,
or a few points past one. The legend is **also the species filter** (#116), so the screen was
telling the reader "these are the species this map has colored" when the truth was "these are three
of them, scroll". The owner decided this ticket rather than leaving it. **The size of the peek was
delegated**; it is a quarter of a chip, and the argument for that number is below.

#### What the ceiling actually did, measured before anything was changed

`MapLayout.legendCeiling` is `screenHeight − topInset − 596` at AX5, and the legend it clips is four
chips of 59.67 pt with 8 pt between them — so where the ceiling lands inside that stack is decided
by two numbers nobody chose together. Swept over every screen height and top inset the app runs on
(`AX5ReflowTests.supportedScreenHeights × .supportedTopInsets`, 24 pairs), **8 of the 24 clip the
legend somewhere a reader cannot see**:

| screen | inset | ceiling | whole chips shown | of the next chip | what it looks like |
|---|---|---|---|---|---|
| 667 | 20 | 51.0 | 0 | 51.0 of 59.67 | one chip, near enough whole — 3 filters hidden |
| 844 | 47 | 201.0 | 3 | **0.0** | three chips and clean surface — 1 filter hidden |
| 844 | 54 | 194.0 | 2 | 58.67 | three chips, the third 1 pt short — 1 filter hidden |
| 844 | 62 | 186.0 | 2 | 50.67 | as above |
| 852 | 47 | 209.0 | 3 | **6.0** | a 6 pt sliver, reads as a rendering seam |
| 852 | 54 | 202.0 | 3 | **0.0** | three chips and clean surface |
| 852 | 62 | 194.0 | 2 | 58.67 | |
| 874 | 20 | 258.0 | 3 | 55.0 | |

The real pairings this bites on are the iPhone SE (667/20 → 51 pt, less than one chip) and the
iPhone 16e (844/47 → 201 pt, three whole chips and **no part of the fourth**). An iPhone 16 Pro
(874/54 → 224 pt) already shows 20.67 pt of its fourth chip, which is a third of one and legible as
cut — **the ticket's premise that 375, 390 and 402 all hide the fourth chip behind a ~6 pt sliver is
wrong on two of the three.** The 6 pt sliver is real, and it belongs to an 852 pt screen.

Rendered rather than argued: at 390 pt the before-shot is three whole capsules over clean surface,
with `Chinese Elm` — a filter the reader can tap — nowhere on the screen.

#### The rule

`MapLayout.quantizedLegendCeiling(_:isAccessibilitySize:)` moves the ceiling **down** to the nearest
height whose bottom edge falls between `legendPeek` and a chip less `legendPeek` into whichever chip
it cuts. Two claims in one number, and they are the same claim from both sides: a quarter of a chip
showing is a slice of capsule wide enough to read as a chip, and a quarter of it hidden is a cut
deep enough to read as a cut. At 0 pt of peek the reader is told the list ends; at 59 of a 59.67 pt
chip they are told the same thing.

**Down only.** Up is where `MapLocationNotice`'s floor and the identify FAB's clearance live — E248
and #258's defect, and the reason there is a ceiling at all. A rule that could raise the ceiling
would be re-opening the thing that work closed. Down costs the legend chips and gives the notice
room, and both are safe directions.

**Applied on the binding branch only**, not inside `legendCeiling`. Quantizing the raw ceiling would
move the number `legendMaxHeight` compares the legend's natural height against, and the two widest
phones — where the whole legend fits with points to spare — would acquire a `ScrollView` over the
map because a quantized ceiling happened to fall under a natural height that was never in question.
The five-phone boundary table in `theLegendCeilingBindsWhereTheArithmeticSaysItDoes` is unchanged by
this ticket, and that is deliberate.

`legendReserved` is now *derived from* `legendMaxHeight` rather than computed beside it. What the
legend occupies is the ceiling when it binds and its natural height when it does not, which is what
that function already decides; the two disagreeing by even the quantization's few points would be
the reservation under-reading the view, which is #258's defect in its original form.

#### Why a quarter of a chip, and not a half

The peek is bought with chips. The quantized ceiling is the **largest** height that satisfies the
rule, so the smaller the required peek, the more of the legend stays on the screen — and the rule
only fires when the ceiling is *outside* the band, so a generous threshold does not buy a bigger
peek where there already is one, it evicts a whole chip to make one.

Concretely: an 874 pt screen shows 20.67 pt of its fourth chip today. At a quarter-chip threshold
that is inside the band and is left alone. At a half-chip threshold it is not, and the ceiling would
drop a whole row — the reader would lose the *third* species' name in order to see more of a fourth
one they could already see. By the measure this ticket is about, which is how many of the four
filters the reader knows exist, that is a worse screen.

A quarter is the least that is legible, and the least is what a rule like this should ask for. The
renders are what settled it rather than the arithmetic: at 20.67 pt the fourth chip shows its
capsule top and the tops of its glyphs; at 45.67 pt (what the rule lands on when it fires) the
partly-shown chip's name is fully readable and only its capsule bottom is cut, which is the best
outcome available — the reader gets the name *and* the signal.

#### What it costs, on the five named phones

Measured through `MapLayout`, and the two clamped cases rendered at AX5 and looked at:

| phone | ceiling before | after | what the reader sees |
|---|---|---|---|
| iPhone SE 375 × 667 | 51.0 | **45.0** | one chip, now visibly cut instead of near-whole |
| iPhone 16e 390 × 844 | 201.0 | **181.0** | two whole chips and 45.67 pt of the third — its name readable, its capsule cut. Before: three whole chips, no fourth |
| iPhone 16 Pro 402 × 874 | 224.0 | 224.0 (unchanged) | three whole chips and 20.67 pt of the fourth |
| iPhone 16 Plus 430 × 932 | no ceiling | no ceiling | the whole legend, no scroller |
| iPhone 16 Pro Max 440 × 956 | no ceiling | no ceiling | as above |

The cost is on the 16e: one species name moves from *whole* to *cut but readable*, and in exchange
the reader learns there is a fourth filter. Every clamped chip stays pressable — the legend is still
a `ScrollView` and every chip is still a filter. `MapLocationNotice`'s budget grows by the same
points the legend gives up (they are complementary halves of one number), so nothing else on screen
01 loses anything.

#### The guard, and the shape of guard it deliberately is not

`AX5ReflowTests.theLegendCeilingAlwaysCutsAChipAtAX5` takes the ceiling from
**`MapLayout.legendMaxHeight`** — the same call `MapHomeView` makes — and the chip height and row
gap from **`MapSpeciesLegend` itself**, measured through `widestReflow` at every width in
`heightBoundWidths`. It recomputes neither. A probe carrying its own copy of the ceiling arithmetic
would keep passing at whatever the production code did, which is this repo's dominant test-suite
defect (CLAUDE.md: *could this guard pass while the defect it names is present?*).

The three ways it could have passed while the defect was present, and what closes each:

- **Recomputing the ceiling.** Closed by reading it off `legendMaxHeight`; the red-proof below is the
  evidence, since the only difference between red and green is the production function.
- **A `nil` ceiling making every assertion vacuous.** If `legendMaxHeight` returns `nil` there is no
  clamp and nothing to cut, so the peek assertions are skipped — which would make "clamp nothing,
  ever" a way to pass. The `nil` branch therefore asserts the legend's *measured* height fits inside
  `legendCeiling`; a `nil` returned over a legend that does not fit is #258 back again and goes red.
- **The chips no longer being one per row**, which would make every row position in the test fiction.
  Asserted before anything is derived from it: a four-chip fixture must measure four chips and three
  gaps, or the test fails saying so.

**The thresholds are looser than the production rule on purpose.** `MapLayout` reserves in bounds
(`legendChipHeightAX5` = 60, a bound on a chip that measures 59.67), so its landing drifts by up to
a point per row against the chip the view draws; the guard asserts a fifth of a chip where
production targets a quarter. A fifth of a chip is the perceptibility claim being defended.

#### Red-proof

The guard was written first and run against the unquantized tree, so its first run is the proof.
`AX5ReflowTests` at `612d8ca^`, iPhone 16 Pro Max `DE8E11AE-…`, `redproof-72.log`: **8 issues, one
per defective screen**, each naming its own screen and inset. Two of the eight verbatim:

    ✘ Expectation failed: (peek → 0.0) >= (leastVisible → 11.933333333333332)
    ↳ a 844.0 pt screen with a 47.0 pt top inset: the 201.0 pt ceiling ends 0.0 pt into the chip
      below 3 whole one(s) — a 0.0 pt sliver of a 59.66666666666666 pt chip is not a chip the reader
      can see, so 1 species filter(s) are hidden behind what looks like the end of the list (task #72)

    ✘ Expectation failed: (peek → 51.0) <= (chip - leastVisible → 47.73333333333333)
    ↳ a 667.0 pt screen with a 20.0 pt top inset: the 51.0 pt ceiling shows 0 whole chip(s) and 51.0
      pt of the next — of a 59.66666666666666 pt chip, so it reads as a complete list with 4
      filter(s) hidden under it. The ceiling has to cut a chip by at least 11.933333333333332 pt for
      the reader to see there is more (task #72); MapLayout.quantizedLegendCeiling is what moves it
      off the boundary

Both fired on the assertion they were written for and named the screen that produced them — the
failure message, not the color, is what was read. With the quantization in place the same suite is
`✔ Test run with 24 tests in 1 suite passed`, and the rest of `AX5ReflowTests` — the reservation
bound, the binding boundary, the clamp, the shortfall, the two blocks never meeting — is green
throughout both runs.

#### The other way this guard could have passed while the defect was present, constructed and run

A guard that only asserts the peek *when there is a ceiling* can be satisfied by never handing out a
ceiling — and "stop clamping the legend" is a plausible thing for a later change to do. So it was
built: `legendMaxHeight` was made to return `nil` unconditionally, and the suite run.

    ✘ a 667.0 pt screen with a 20.0 pt top inset: MapLayout.legendMaxHeight returned nil, so
      MapSpeciesLegend draws its full 262.66666666666663 pt unclamped — but the room below the chip
      row is only 51.0 pt, so it is drawing over the identify FAB again (task #258)

Red on the branch that would otherwise have been vacuous, and #258's own guards went red beside it.
The probe was reverted and the unit suite re-run on the restored tree.

#### The third door, which the review found open (PR #63 review B1)

The two doors above were the ones this branch thought to construct. **There was a third, and it is
the one this repo's dominant defect class predicts**: the guard's perceptibility floor was gated
`if ceiling >= chip`, which reads the *ceiling that came back* — the very thing a broken quantizer
controls. A `legendMaxHeight` patched to `min(quantizedLegendCeiling(…), 5)` draws a 5 pt strip with
no chip in it on all 24 pairs, hides all four species filters, and **passed**, because a ceiling
under one chip exempted itself from the only assertion that would have caught it.

It was not hypothetical. The real tree already landed in the unguarded region: a 667 pt screen at a
62 pt inset has 9 pt of ceiling — under the guard's own `leastVisible` of 11.93 and under
production's own `legendPeek` of 15 — and was green, silently.

**The fix is to gate the exemption on the input rather than the output.** Both bounds now read
`MapLayout.legendCeiling` — the room the screen actually had below the chip row — which no change to
the quantizer can fake:

- `peek >= min(leastVisible, room)`. A fifth of a chip wherever the screen has a fifth of a chip to
  give, and otherwise every point it does have. The quantizer only ever moves down, so "this screen
  is too short" is the one honest exemption, and it is now stated as that rather than inferred from
  the answer.
- `ceiling > room − (row + 1)`. Quantizing means landing on the nearest qualifying height *below*,
  so at most one row is what it can ever cost. Same probe from the other side, and it is what fails
  a ceiling pinned at any constant.

The reviewer proposed `rawCeiling < chip || ceiling >= chip` and invited a better one. That
assertion is red on a legitimate quantization: a raw ceiling of 65 pt is one whole chip and 5 pt of
gap — no peek at all — and the rule correctly moves it to 45, a cut first chip, which the proposal's
second arm forbids. No pair in the sweep is in that band today, so it is a latent false alarm rather
than a current one; the `min(leastVisible, room)` form closes the same hole without it, and the
row-cost assertion adds a bound the proposal does not have.

**Both red-proved, each on its own assertion.** The reviewer's own mutation, 28 issues:

    ✘ Expectation failed: (peek → 5.0) >= (min(leastVisible, room) → 11.933333333333332)
    ↳ a 844.0 pt screen with a 47.0 pt top inset: the 5.0 pt ceiling ends 5.0 pt into the chip below
      0 whole one(s) … This screen had 201.0 pt below the chip row to work with (task #72)

and a ceiling pinned at 45 — which *does* cut a chip, so the peek bounds accept it and only the
row-cost assertion fires, which is why that assertion earns its place:

    ✘ Expectation failed: (ceiling → 45.0) > (room - (row + 1) → 132.33333333333334)
    ↳ a 844.0 pt screen with a 47.0 pt top inset: the ceiling came back at 45.0 pt out of 201.0 pt of
      room — 156.0 pt given up, where quantizing to the nearest qualifying height can cost at most
      one row (67.66666666666666 pt)

#### A legend under one chip is unreported, and no guard speaks for it

Named here rather than left to a guard that cannot see it (review N1). An earlier draft of
`quantizedLegendCeiling`'s doc said a screen that short "is a `chromeBudgetShortfall` report rather
than a quantization problem". **That is false.** `chromeBudgetShortfall` asks whether the slack
covers `chipRowTop + noticeFloor`, which says nothing about the legend's share of what remains — and
`theChromeBudgetCanHouseBothOccupants` asserts it is 0 for every screen and inset the app runs on, so
by construction it never speaks for any of them. A 667 pt screen leaves 24 pt of legend at a 47 pt
inset, 17 at 54 and 9 at 62, with a shortfall of **0.0** at all three.

No shipping phone is in that region: 667 pt is the home-button iPhone SE, whose inset is 20 and whose
ceiling is 45. The sweep crosses heights with insets anyway, because a reservation correct only on
today's pairings is one device away from being wrong — which is exactly how this was found. Whether
a legend that short should exist at all is a product question this ticket does not answer.

#### What the change costs the FAB's clearance: nothing, and structurally

An earlier draft of this branch's PR said the change "moves the top chrome further from the FAB".
**It does not, and the true property is the better one** (review N3). PR #63's reviewer measured it
on a running iPhone 16e at AX5: the legend's bottom edge moves 416 → 396 and the FAB's top edge
moves 485.33 → 465.33, so the clearance is **69.33 pt before and after**. `noticeMaxHeight` absorbs
the 20 pt the legend gives up, because the two are complementary halves of one number. The clearance
is not improved by this change; it is *preserved by construction*, which is what should be claimed
for it.

#### Verified on the merged tree

The branch contains `origin/main` at `fc68efc`, so the branch tree **is** the merged tree. Re-run in
full after review round 1: `head 068b83a` on every log below, iPhone 16 Pro Max `DE8E11AE-…`,
`active-city=none`, `camera-auto-healed no`.

| log | what | result |
|---|---|---|
| `unit-r2-72.log` | `CypressTests` | `✔ Test run with 1318 tests in 133 suites passed` |
| `ui-r2-72.log` | `CypressUITests` | `Executed 99 tests, with 0 failures`, `XCTest skipped=0` |
| `warnings-r2-72.log` | **fresh** DerivedData, `build-for-testing` | `VERIFY-WARNINGS: source=0 non-source=3 compile-tasks=447 files-checked=4` |
| `redproof-72.log` | the guard against the unquantized tree | 8 issues, one per defective screen |
| `vacuous-72.log` | the guard against an always-`nil` ceiling | red |
| `b1-probe-5pt.log` | the guard against `min(quantized…, 5)` (review B1) | 28 issues |
| `b1-probe-pinned.log` | the guard against a ceiling pinned at 45 | red on the row-cost bound only |

Round 1's own logs (`unit-final-72.log`, `ui-72.log`, `warnings-72.log`, `head cef0c26`) were green
on the same three counts; they are superseded rather than contradicted.

The warnings certifier was calibrated before it was believed (E203): asked to certify a file the
build did not compile it answers `VERIFY-FAIL: cannot certify a warning count for:
NoSuchFileHere.swift — no SwiftCompile task for those files in this log`, so the count above is a
certification rather than a no-op.

#### What could not be verified here, and is worth a reviewer's device

The three phones this ticket is about are 375, 390 and 402 pt, and this agent was assigned the
iPhone 16 Pro Max (440), where **the ceiling does not bind at all**. The clamped legend was
therefore rendered rather than photographed on a running phone: `MapSpeciesLegend` at
`.accessibility5`, at each phone's own content width, hosted in a real window and drawn with
`drawHierarchy` through `ShotBlankGuard` (`ImageRenderer` was tried first and returned a blank white
image for every case, clamped or not — a control shot with no ceiling at all is what caught it).
That is the view under its real ceiling, and it is not screen 01 in the reader's hand.
