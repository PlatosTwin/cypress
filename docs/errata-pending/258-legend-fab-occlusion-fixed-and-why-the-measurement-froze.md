### The species legend stops covering the identify FAB, and the reason the measured repair froze: `onChange` out of a `GeometryReader` is edge-triggered over a value SwiftUI is free to change without an edge (task #258)

This closes the defect the previous round diagnosed and could not land. That round's entry is the
diagnosis; this one is the mechanism it left open, the repair, and what the repair costs.

#### The defect, re-measured on this branch before anything was changed

`Tools/run_tests.sh EA0AD796-… fab258-repro-16pro.log -only-testing:CypressUITests/IdentifyFABReachabilityTests`,
iPhone 16 Pro (402 pt), AX5, `CYPRESS_LOCATION=denied`, at this branch's merge-base with `main`:

    the identify control (22.0, 371.0, 364.33, 83.0) overlaps the species legend
    (16.0, 230.0, 344.33, 262.67)

    the top chrome ends at y 492.67 and the bottom chrome begins at y 315.0

and, in the same run, `testTheFABIsReachableAtAX5WithLocationDenied` **passed in 4.596 s**. One
launch, one device: the occlusion is there, the rectangles see it, `isHittable` does not. Every
frame matches the previous round's to the hundredth of a point, so the diagnosis is confirmed rather
than assumed.

#### Why the measured repair froze — the best explanation, and what it rests on

The repair that was built and not landed measured the top block's real bottom edge in a
`GeometryReader` inside a `.background`, and handed it to `@State` through
`.onChange(of: proxy.frame(in:).maxY, initial: true)`. It froze on some launches, at whatever the
legend's height had been on an early pass, for the whole life of the process. Which launch froze
moved with the wiring, and four wirings were tried.

It was instrumented rather than reasoned about. The branch `diag/258-freeze` carries the abandoned
repair plus three probes published into the accessibility tree behind `CYPRESS_MAP_PROBE=1`:

| probe | what it renders | where it renders |
|---|---|---|
| `chrome-live` | `proxy.frame(in:).maxY` | inside the measuring `GeometryReader`'s own closure |
| `chrome-written` | the last value the `onChange` **action** was given | same closure, from plain non-observed storage |
| `chrome-state` | what reached `@State` | outside the `GeometryReader` entirely |

Two runs of 16 launches each on the iPhone 16 Pro, sampling at 3 s and again at 11 s after launch
(`fab258-freeze-16pro.log`, `fab258-freeze2-16pro.log`). Three launches of the 32 froze, and they
all say the same thing:

    launch=4  live=492.667  written=425.0  state=425.0  writes=6  legendMaxY=492.667  overlap=true
    launch=11 live=492.667                 state=357.33            legendMaxY=492.667  overlap=true

against a healthy launch:

    launch=5  live=492.667  written=492.667 state=492.667 writes=7 legendMaxY=492.667 overlap=false

Three facts, each read off the probes:

1. **No `@State` write was ever lost.** `state == written` on every launch, frozen or not. The
   "SwiftUI discarded the write" hypothesis — E168's shape, and the obvious one to reach for in this
   view — is **wrong**.
2. **The `onChange` action was never called with the final value.** On the frozen launches its last
   argument was a stale *intermediate*: 425.0 is the top block with a three-row legend, 357.33 with
   a two-row one, against the four rows the legend actually had.
3. **The closure it lives in did re-render with the final value**, because `chrome-live` — computed
   from the same `proxy`, inside the same closure — reads 492.667 at both samples.

So the geometry reached the `GeometryReader` and the transition did not reach `onChange`. The
observed value was silently advanced without the action running. The `writes` count varies from
launch to launch (5, 6, 7 across the healthy ones), which is the same thing seen from the other
side: how many of the legend's growth passes SwiftUI coalesces is not fixed, and a coalesced last
pass is a transition nobody is told about.

**On that reading it never converges because `onChange` is edge-triggered and the value has no
further edges.** Once the last transition is absorbed, the legend's height never changes again, so
there is nothing left to re-deliver it — which is why the stuck launches were stuck from the first
sample to the last, and why a longer settle would not have helped.

**This is the best explanation available and it is not the only one the probes admit** (PR #60
review, N1). `chrome-written` is written from inside the measuring closure into non-observed storage
and read back out through the same render that publishes `chrome-live`, so it is not an independent
witness. An alternative fitting all three facts equally well: the action *did* run with 492.667, and
the probe's own write and the publication that exposes it were reordered, so `chrome-written` shows
the previous value — which predicts `state == written` (both read from one stale publication) and
`chrome-live == 492.667` just as well. Separating the two needs a witness outside the render that
publishes it, and this entry does not have one. **Stated as inferred, not established.**

What is **not** in doubt, and is what the design turns on: four wirings of the same idea were built
and all four flaked, and all four deliver a layout measurement back into state as a *difference*.
Which of the two mechanisms eats the difference does not change what to do about it.

**This generalizes past `onChange`, which is why all four wirings flaked.** A `PreferenceKey` is
delivered on change too. Any channel that carries a layout measurement back into state as a
*difference* has this failure mode; the only question between wirings is which pass gets coalesced,
which is what "which launch freezes moved with the wiring" was reporting.

**The rule worth keeping — it survives either mechanism: do not close a layout loop through an
edge-triggered channel.** If a number is needed before layout, take it from something that is known
before layout.

#### The repair

The palette is known before layout. `MapSpeciesPalette` is model state `MapHomeView` already
observes, so the number of chips the legend will draw is available without asking the layout system
anything, and there is no channel to drop anything.

`MapLayout` now splits the room below the filter chip row between the two things that grow into it:

- `chromeSlackBelowChipRow(screenHeight:topInset:isAccessibilitySize:)` — the whole of that room, once.
- `noticeFloor(isAccessibilitySize:)` — taken off it first, so the card below can never be zeroed.
- `legendNaturalHeight(namedSpecies:isAccessibilitySize:)` — `count` chips and `count − 1` gaps. An
  **upper bound by construction**: `FlowRow` puts at most one chip per line and every chip is one
  line tall (`.lineLimit(1)`), so `count` chips take at most `count` lines. A legend whose names pair
  up on a line is over-reserved, never under-reserved.
- `legendReserved(…)` / `noticeMaxHeight(…)` — complementary halves of what is left, so no
  arrangement of them hands the same point to both blocks.
- `chromeBudgetShortfall(…)` — how far short a screen is of housing both, when it is.

Every reservation on this screen is now a function of `dynamicTypeSize.isAccessibilitySize`, with
both ends of the ramp measured through a harness that offers each control **the width screen 01
actually gives it**:

| reservation | AX5 | `.xxxLarge` |
|---|---|---|
| `searchBarHeight` | 77 (measures 76.67) | 50 (49.0) |
| `chipRowHeight` | 60 (59.67) | 36 (34.67) |
| `locateButtonHeight` | 44 (44.0, a fixed square) | 44 |
| `fabHeight` | **136** (135.67) | **55** (54.0) |
| `legendChipHeight` | 60 (59.67) | 36 (34.67) |
| `noticeFloor` | **93** (92.67) | **66** (65.0) |

#### The measurement that was wrong, and the harness that could not see it (PR #60 review B2)

**`MapLayout.fabHeightAX5 = 83` was not a bound.** On any phone at or below 393 pt the FAB's label
takes a third line and the control occupies **135.67 pt** — 52.67 pt past what
`bottomSlotReservedAbove` reserved. Read off a running iPhone 16e (390 pt): `(127, 503.33, 247.33,
135.67)`, against `(60, 571, 364.33, 83)` on an iPhone 16 Pro Max. It put the recenter control 30 pt
up inside the species legend and **turned this ticket's own new guard red on a device it had not
been run on** — the same defect one device over, found by a reviewer given 390 and 440 pt precisely
because the author had 402 and 430.

**Why no unit guard saw it, and why widening the sweep alone did not either.** The first repair was
to sweep `ax5Size` over six widths. It found nothing: the FAB measured 83.0 pt at 375 pt just as at
440. Width was never the blind spot by itself — **`ax5Size` offers the control the phone's width,
and screen 01 offers it the phone's width less `sideInset` on each side.** The label wraps between
361 pt and 370 pt of *content*, which is 393 pt and 402 pt of phone, and `phoneWidth = 393` sits
three points on the safe side of a threshold that is not about phones at all.

With the inset applied the harness reports 135.67 × 247.33 at 375/390/393 and 83.0 × 364 at
402/430/440 — the two frames the reviewer read off two running devices. **That is the calibration:
the instrument was believed only once it reproduced an answer already known.** Height bounds now go
through `AX5ReflowTests.widestReflow(of:horizontalInset:)`; `ax5Size` stays the right instrument for
a *width* guard, where the proposal is the claim being tested.

`fabHeightAX5` is one number (136) rather than a `fabHeightAX5(contentWidth:)` with a wrap threshold
in it: the threshold is a constant that moves the next time the label, the font or the glyph changes,
and moves silently. The bound over-reserves 53 pt on phones wider than 393 pt, out of
`MapLocationNotice`'s scroll budget and out of nothing else, and buys back margin on exactly the
narrow phones where the review measured only 25.67 pt between the legend and this control. **E243's
correction of this constant (137 → 83) was right about the safe-area inset it removed and wrong about
the number it landed on; the width blindness came in with it unnoticed.**

#### The constant this ticket "corrected" and should not have (PR #60 review B3)

An earlier revision of this branch raised `searchBarHeightAX5` from 77 to 85, and said in this entry
that #250's reservation "has been short since it landed". **That was wrong, and it was wrong by the
same mechanism as B2 above.** The derivation was `158.33 − 12 − 62` from an iPhone 16 Pro's chip-row
frame, with the 62 built from `topInset = 54` — and 54 is E243's *synthetic-window* inset, the exact
number E243 exists to warn is not the app's. An iPhone 16 Pro Max reports the same chip-row `minY` of
158.33 with a real inset of 62, so the subtraction was 8 pt out. Measured directly through the swept
harness, the bar is **76.67 pt at all six widths**, which the original 77 bounds. Reverted.

Worth keeping for the shape of it: the error was not in the arithmetic but in reading a number off
the *measuring window* and using it as the *device's*, which is the failure this entry spends its
first half describing in someone else's code.

#### The notice can no longer be given nothing (PR #60 review B4)

The first version of this split served the legend first out of the whole slack and gave
`MapLocationNotice` the remainder — which on a 667 pt screen is **0.0 at every inset**.
`MapHomeView.standingNotice` passes that straight into `MapLocationNotice(maxHeight:)` for all four
arms, including the refused arm whose `Settings` button is the reader's only way to fix the
permission the card is about. A `ScrollView` at `frame(maxHeight: 0)` draws nothing. **A fix for an
unreachable FAB that makes the permission remedy unreachable instead has not fixed anything**, and
R53 §6 ruled that this card *scrolls*, not that it disappears. The ordering guard was green
throughout, because removing a control from the screen satisfies an ordering — the same failure
class this ticket exists to close.

`noticeFloorAX5` is now taken off the slack **before** the legend is served. The number is the card
at its smallest that still carries an action — a one-line title, no message, the button — 92.67 pt,
identical at all six widths. At that budget the button sits inside the visible window and is fully
pressable without scrolling; the message and a second title line are what scroll.

And because a split can genuinely fail, it now says so: `chromeBudgetShortfall(screenHeight:topInset:
isAccessibilitySize:)` returns how many points short a screen is of housing both, and
`AX5ReflowTests.theChromeBudgetCanHouseBothOccupants` asserts it is 0 for every screen and inset the
app runs on. A device or a type-size change that makes screen 01 unhousable now fails the unit suite
with a number instead of shipping a zero-height control.

#### One reservation being AX5-only was affordable; six were not

Correcting `fabHeightAX5` to 136 exposed a second-order defect immediately, in the ordinary-size half
of the legend's own ceiling guard: `bottomSlotReservedAbove` is subtracted whatever the reader's text
size is, on the standing argument that at ordinary sizes the notice is nowhere near its budget. True
at 83, false at 136 — on a 667 pt phone the AX5 reservation put `MapSpeciesLegend` into a `ScrollView`
**at the default content size**, a scroller over the map for a reader who had asked for nothing. So
`bottomSlotReservedAbove`, `topChromeReserved` and `noticeFloor` all take `isAccessibilitySize` now,
and every constant in the table above has a measured twin. The over-reservation that was harmless
while it was one term stopped being harmless when it doubled.

#### What it costs, at every width, said plainly

`MapLocationNotice`'s AX5 budget, with location denied and a full four-species palette. These are
computed from `MapLayout`, not read off five running screens — the model's credibility is that PR
#60's reviewer independently predicted the *previous* revision's 75.0 pt budget from the same
arithmetic and found exactly 75.0 on a running iPhone 16e.

| phone | budget before #258 | this revision | legend |
|---|---|---|---|
| iPhone SE 375 × 667 | 301 (and wrong — see the coordinate-space note) | **93** | scrolls, ~51 pt of one chip |
| iPhone 16e 390 × 844 | 301 | **93** | scrolls, 201 of 264 pt |
| iPhone 16 Pro 402 × 874 | 301 | **93** | scrolls, 224 of 264 pt |
| iPhone 16 Plus 430 × 932 | 301 | **103** | whole, 264 pt |
| iPhone 16 Pro Max 440 × 956 | 301 | **127** | whole, 264 pt |

**An earlier revision of this entry said 90 pt on a 402 pt phone and that number is withdrawn**; the
review measured the shipped behavior at 75 pt on a 390 pt phone, with `Location is off` clipped
mid-glyph and only the word "Location" legible. The floor is what answers that: at 93 pt the card's
`Settings` button is fully visible and pressable without scrolling, and the *first* line of the title
is legible. The second title line and the whole message scroll — on every phone at AX5. That is R53
§6 applied where it bites, and it is a real reduction in what the reader sees, in this one state.
**It is a trade rather than a free fix and the owner may want to look at it.**

The direction is the one that matters: the alternative is the identify FAB covered, which is screen
01's only entrance to the visit flow.

#### The squeeze, and the one behavioral change — which is wider than first reported

At AX5 with a full palette the chrome wants more than the glass has on the narrow phones, and
arithmetic cannot conjure the points: something must yield. `MapSpeciesLegend` gains a `maxHeight:`
and scrolls when it binds, on the argument R53 §6 made for the notice — a scrolled chip is reachable
and a covered control is not, and the legend is also the species filter (#116), so its chips must
stay pressable.

**An earlier revision of this entry said the ceiling binds on no device the suite runs. That was true
then and is not true now**, and the change is a direct consequence of correcting `fabHeightAX5`
(+53 pt of reservation) and adding the notice's floor (+93). The boundary now sits **between 402 pt
and 430 pt**: a four-chip AX5 legend needs 264 pt, the ceiling is 224 pt on an iPhone 16 Pro and
274 pt on an iPhone 16 Plus. So the SE, the 16e and the 16 Pro scroll the legend at AX5 with a full
palette; the 16 Plus and 16 Pro Max do not. At ordinary content sizes **none** of them do, on any
supported screen, and that is asserted separately because it is the property worth defending: a
scroller over the map costs the pan, and no reader at the default text size should pay it.

**`MapLayout.legendMaxHeight` returns `nil` unless the ceiling actually binds**, and that `nil` is
load-bearing rather than tidy. A non-nil ceiling puts the legend inside a `ScrollView`, and a
`ScrollView` over a map takes touches across its whole frame where the bare `FlowRow` takes them only
on the chips — `MapHomeView.chrome`'s own note, "the empty width beside a chip has never taken a
touch". `AX5ReflowTests.theLegendCeilingBindsWhereTheArithmeticSaysItDoes` carries the boundary as a
table of five named phones rather than a rule, so moving a constant across it is a decision somebody
makes rather than a side effect somebody discovers.

`MapSpeciesLegend`'s clamping branch is now tested — `theSpeciesLegendClampsToItsCeilingAtAX5`, using
R53 §6's own bare-hosting pattern, because `ax5Size` mounts in a real window and reads a capped
`ScrollView` as its unclamped content. PR #60's review measured that clamp independently
(`unbounded=262.667 budget=131.333 bounded=131.333`) and was right that the branch shipped uncovered.

#### Still not reserved, and now named rather than denied

- **The `Needs care` toast.** `MapToast`'s doc claimed it "cannot cover the chips, the legend, the
  recenter control, the FAB or the bottom card at any Dynamic Type size". The first two are true and
  the rest never were — being in the flow of the top block says nothing about the *other* block, and
  the card pushes everything below it in its own stack down by its own height. Reserving for it would
  cost the notice that room in every second the toast is not on screen, which is almost all of them.
  The comment is corrected; the gap is open. **PR #60's review sharpened what the gap is worth**: on
  a 390 pt phone the margin between the legend's bottom edge and the FAB was 25.67 pt, not the ~78 pt
  the arithmetic believed, so every toast re-created this ticket's occlusion there for three seconds.
  Correcting `fabHeightAX5` is what buys that margin back; the toast is still unreserved.
- **`MapSearchStatus`**, on the same reasoning, and with the additional one that it only exists while
  a search is running — the state R25/#143 deliberately lets the top block draw over the bottom in.
- **`MapTreeCard`** shares the bottom slot and is still not given `noticeMaxHeight` — only the four
  `MapLocationNotice` arms are. Carried forward unchanged from the previous round's entry.

#### E248's "Scope held" paragraph is false and should be struck when this is spliced

`docs/ERRATA.md`'s #250 entry says the species legend "sits *below* the chip row … so it needed no
reservation of its own for this control's reachability". **That is the claim this ticket refutes**,
and it is the sentence that made the legend invisible to the round that wrote it. It is not a
numbering matter and not something a branch may edit; naming it here so the orchestrator strikes or
annotates it at merge, and so the next reader does not re-derive it from an entry that still asserts
it.

#### The guard

`CypressUITests/IdentifyFABReachabilityTests` is the previous round's file, restored from
`89f5001`/`5a2112f`, together with `settledFrame(requireHittable:)` — a guard against occlusion must
not gate its measurements on the thing an occlusion removes. Red-proved three ways on an iPhone 16
Pro, each fired for its own reason:

| break | what went red |
|---|---|
| `legendReserved` returns 0 | *"the identify control (22.0, 295.0, 364.33, 83.0) overlaps the species legend (16.0, 230.0, 344.33, 262.67)"* — and `testTheFABIsReachableAtAX5WithLocationDenied` **passed in 4.636 s** in the same run |
| the recenter control's bottom padding → `-10` | *"the identify control (22.0, 571.0, …) overlaps the recenter control (342.33, 537.0, 44, 44)"* |
| `IdentifyFAB.offset(x: 2000)` | *"is in the accessibility tree but never became hittable within 30s"* (33.2 s) |

`.allowsHitTesting(false)` does **not** make an element unhittable to XCUITest, which is why the
third proof uses an offset (measured independently in PR #51's review).

#### Why three launches of a guard were not enough evidence, and what was

The abandoned repair passed this same guard. A defect at one launch in eight is invisible to three
launches. So the fix was run through a temporary 40-launch check on each of two devices
(`fab258-repeat-16pro.log`, `fab258-repeat-16plus.log`): **80 launches, 0 overlaps.**

At the freeze rate actually measured (3 of 32, ≈ 9.4 %), 80 clean launches would happen by luck with
probability 0.906⁸⁰ ≈ 3.6 × 10⁻⁴; at the ~1-in-4 rate the previous round reported, ≈ 10⁻¹⁰.

**An earlier revision of this entry also argued that byte-identical geometry across those 80 launches
disproved a race. It does not, and the sentence is withdrawn** (PR #60 review, N2). A race that
resolves the same way under a warm process and a warm asset cache produces exactly one number every
time; identical output is evidence that nothing varied in those runs, not that nothing *can*. The
launch count carries the claim on its own, and the stronger half of the argument was always that the
channel which dropped the value no longer exists.

**And 80 launches on two devices is not four widths.** The guard is red on a 390 pt phone at the
revision that ran them — that is PR #60's B1 — so those 80 launches say nothing about the 16e. The
run table at the end of this entry is the four-width verification.

#### One more instrument-calibration note, paid for on the way

The unit suite failed **twice in a row** on the iPhone 16 Pro on this branch, with no `✘` and no
`Expectation failed` anywhere in either log — the test process exited mid-run
(`Restarting after unexpected exit, crash, or test timeout`, preceded by `CAMetalLayer ignoring
invalid setDrawableSize width=0.000000 height=0.000000`). Two failures at the same commit is not the
shape of a flake, and the obvious reading was that this branch's four new `ax5Size` measurements had
broken it.

They had not. The controls:

| tree | device | result |
|---|---|---|
| this branch | 16 Pro, busy machine | died mid-run, twice |
| this branch | 16 Plus, quiet | `✔ Test run with 1286 tests in 127 suites passed` |
| `origin/main` | 16 Pro, quiet | `✔ Test run with 1292 tests in 130 suites passed` |
| this branch, merged | 16 Pro, quiet | `✔ Test run with 1297 tests in 130 suites passed` |

Both failures fell inside a window when two other agents' reviewer worktrees were building on this
machine; both greens are from a quiet one. `run_tests.sh`'s collision guard runs **at start**, so a
run that is already going when a second one begins gets no warning at all — the guard cannot refuse
on a collision that has not happened yet. **A crash with no failed assertion in the log is a
machine-state report until a control says otherwise**, and the control that settles it is the same
tree on a quiet machine plus a known-green tree on the same device. 1292 + 5 new tests = 1297, which
is the other half of reading that table.

And a smaller one, in the same family as the four ad-hoc-command errors CLAUDE.md lists: a progress
poll built on `grep -c 'Test Case .* passed$'` reported **0** for nine minutes of a healthy run,
because the line ends in `(4.596 seconds).` and not in `passed`. It had been calibrated against a
looser pattern minutes earlier and then tightened without re-calibrating. The run was fine; the
instrument was not.

#### Verified on four widths, on the merged tree

PR #60's review found this ticket's own guard red on an iPhone 16e, on a change verified only at
402 pt and 430 pt — the two widths it had been tuned against. **A layout fix verified only on the
widths it was tuned against is not verified**, and that is the durable lesson of the round rather
than any one constant. All four now, every log carrying its own `CYPRESS-RUN` header, `head 2b63daf`,
`active-city=none`, `camera-auto-healed no`, `XCTest skipped=0`:

| log | device | width | result |
|---|---|---|---|
| `fab258-r3-16e.log` | iPhone 16e `3A1F212D` | 390 | `Executed 99 tests, with 0 failures in 1517.169s` |
| `fab258-r3-16pro.log` | iPhone 16 Pro `EA0AD796` | 402 | `Executed 99 tests, with 0 failures in 1434.302s` |
| `fab258-r3-16plus.log` | iPhone 16 Plus `24D1629F` | 430 | `Executed 99 tests, with 0 failures in 1456.284s` |
| `fab258-r3-16promax.log` | iPhone 16 Pro Max `DE8E11AE` | 440 | `Executed 99 tests, with 0 failures in 1500.089s` |
| `fab258-r3-unit.log` | 16 Pro Max | — | `Test run with 1310 tests in 132 suites passed` |
| `fab258-r3-fresh-warnings.log` | 16e, **fresh** DerivedData | — | `VERIFY-WARNINGS: source=0 non-source=3 compile-tasks=446 files-checked=7` |

The warnings certifier was calibrated before it was believed (E203): naming a file the build did not
compile returns `VERIFY-FAIL: cannot certify a warning count for: … — no SwiftCompile task for those
files in this log`, so the green above is a certification rather than a no-op.

#### The measurement artifact the four-width run found, which was not a layout defect

Worth carrying, because it cost a wrong conclusion for ten minutes and the screenshot is what settled
it. With the ceiling binding on the 16e, `testTheTopChromeStaysClearOfTheBottomChromeAtAX5WithLocationDenied`
went red — legend `maxY` 477.67 against a bottom chrome at 429.33. The arithmetic said it should not:
the notice was rendering at exactly its 92.67 pt floor, which only happens when the legend *is*
clamped.

A screenshot of the running app resolved it in one look: three legend chips, the fourth scrolled
away, the FAB fully clear, the `Settings` button visible. **The layout was correct and the frame was
not.** `.accessibilityElement(children: .contain)` sat on the `FlowRow` *inside* the `ScrollView`,
so the labeled element's frame was the scroll **content** — 262.67 pt of rows — rather than the
201 pt window that clips them. XCUITest measured the content, and so would VoiceOver's cursor.

That is a real accessibility defect in its own right, not merely a test artifact: an element whose
frame extends 48 pt over controls it does not draw on is wrong for every consumer of that frame. The
label now sits on the outermost view in both branches. The guard was right to be red — it was
reporting a rectangle that really was where it said it was.

**And the rule underneath it is the one this whole ticket keeps paying for: look at the running
screen.** The numbers said "clamped" and "not clamped" at the same time; only the screenshot said
which half was lying.
