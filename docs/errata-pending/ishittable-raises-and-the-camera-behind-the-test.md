### `isHittable` raises rather than answering, and the map behind a test decided the test

#### The occurrences

Two UI tests, failing intermittently in CI within 24 hours of each other, filed as one shape. They
are not one shape. They have one cause.

**One — `isHittable` raises.** `DeepLinkSweepTests.testNothingIsAnnouncedTwice`, CI run
31300530216, shard `ui (3)`, attempt 1, iPhone 17 Pro at 402 pt:

    <unknown>:0: error: -[CypressUITests.DeepLinkSweepTests testNothingIsAnnouncedTwice] :
    Failed to determine hittability of StaticText at {{inf, inf}, {0.0, 0.0}}:
    Activation point invalid and no suggested hit points based on element frame

**Two — a legend that was never going to be drawn.**
`IdentifyFABReachabilityTests.testTheTopChromeStaysClearOfTheBottomChromeAtAX5WithLocationDenied`,
CI runs 31291434427, 31294993494 and 31300530216:

    IdentifyFABReachabilityTests.swift:205: error: … failed - the species legend (“Species shown in
    color on this map”) — absent only when the opening camera is showing no trees at all, which is a
    device-state question (E216) and not a layout one never appeared in the accessibility tree at
    all within 30s

> **The diagnosis of this second occurrence is wrong, and the correction is the last three sections
> of this entry.** The legend failures were not the inherited camera. They were an un-waited read
> that decides which *element type* the test then waits on — three lines, copied into three files.
> All three of the run numbers above failed this way, on `ScrollView`, including the one a later
> revision of this entry briefly claimed had never failed at all. Read "Correction: the legend was
> there, and the test was waiting for the wrong element" before taking anything between here and
> there as a finding about the camera.

**The brief for this ticket said both were `isHittable` raising. The second one is not**, and the
difference decides where the repair goes: a frame guard cannot fix a legend that is not in the tree.
Downloading the three shard logs was the whole of the check, and it took a minute — the artifacts
have been uploaded on every run since `47b7d12` and `verify_test_log.sh` has printed
`VERIFY-FAIL-DETAIL` since task #71. Reading the log is now cheap enough that not reading it has no
excuse left.

#### What is actually shared: the camera behind the screen

`MapOpeningCamera` remembers the camera the reader left and opens there next time. That is right for
the product (#115) and it means **every UI test inherits screen 01's camera from whatever ran
before it.** Two unrelated things downstream depend on that camera:

- **Which annotations MapKit draws, and where.** Screens 09, 10 and 18 are presented *over* the map
  tab root rather than pushed, so screen 01's annotations stay in the accessibility tree behind
  them. `DeepLinkHarness.assertEveryControlIsLabeled` walks `app.buttons` — every button in the app
  — and an annotation the camera happens to place where XCUITest can compute no activation point
  does not answer `false` to `isHittable`. **It raises**, and the raise is the test failure.
- **Whether the species legend exists at all.** `MapSpeciesLegend` "draws nothing when it has
  colored none", so a camera with no trees under it produces no legend, and a test that waits 30 s
  for one waits for something no amount of patience will produce.

So the failure the log reports depends on which test the inherited camera happened to reach first.

#### The second failure was reproducible in a way that named the cause

`IdentifyFABReachabilityTests` has three tests. On all three failing runs, the first two **passed**
— 7.8 s and 7.8 s — and the third failed after 30 s of waiting. Same tree, same install, same
device, minutes apart. The first test reads the same legend, through the same helper, with the same
timeout, and found it.

Nothing about the code changed between those launches. What changed is `map.lastCamera`: the app
writes the camera it was left on when it leaves the foreground, so launch *n+1* opens on what launch
*n* settled on. `Tools/run_tests.sh`'s camera preflight (task #71) normalizes the device's stored
camera **once, before `xcodebuild` starts**, and cannot say anything about the camera the twentieth
launch inside a run inherits from the nineteenth. That is the gap, and it is a gap the harness
cannot close in principle — it is not running while the suite is.

#### `isHittable` raising is a defect this project had already fixed, once, in one place

`AccessibilityTreeTests.testNoUnlabeledButtonsOnLaunch` found it on task #121's branch, diagnosed it
correctly, and fixed it — with a hand-rolled frame check and a fifteen-line comment explaining the
whole mechanism, at that one call site. It then came back twice under other tests' names:
`DeepLinkVoiceOverTests.testPinAdjust` (the run task #71 was written from, repaired there at the
harness level and explicitly *not* at the test level) and `DeepLinkSweepTests
.testNothingIsAnnouncedTwice`. Each read as a new mystery.

That is `DragGestureGateTests`' story exactly, with a property in place of a gesture, and it gets the
same answer: **make the careless spelling unrepresentable.**

#### The repairs

**1. One spelling of the filter, and a gate that keeps it that way.**
`XCUIElement.isHittableWithoutRaising(in:)` (`CypressUITests/UIWait.swift`) asks
`frameCanAnswerHittability` first — finite, with an interior, and intersecting the app's own frame —
and returns `false` where the raw property would raise. Every
filter position in `CypressUITests` now calls it: `DeepLinkHarness.assertEveryControlIsLabeled` and
`.waitForCoverToArrive`, `DeepLinkSweepTests.testNothingIsAnnouncedTwice`, `AccessibilityTreeTests`'
own site, `MapFilterAccessibilityTests.swipeRow`/`.revealedChip`,
`PrimaryCTAReachabilityTests.reach`/`.buttonLabels`, `AnonymizedPhotoNoticeUITests`.

*Nothing is weakened, because it is the same judgment.* An element with no interior is not reachable
by an assistive technology either — skipping it is exactly the answer `isHittable` was being asked
for, expressed in a way that cannot raise. That is `AccessibilityTreeTests`' own argument, now in the
one place that can hold it.

*Assertions keep the raw property, deliberately.* `XCTAssertTrue(delete.isHittable, "…")` is a
claim, not a filter: nothing is being skipped and the assertion's own message is what a reader
wants. `HittabilityFilterGateTests` (unit suite, `DragGestureGateTests`' reason — it runs on every
build and every shard, where a gate inside the UI suite could be skipped by the very sharding it
protects) fails the build if a *filter-position* read reappears, and is calibrated in both
directions: fourteen real spellings it must catch, nine it must leave alone. (It was six and five,
and the six had no `if` in them — see "Not done, and why".)

**2. Four launch helpers stop inheriting the camera (`CYPRESS_MAP_CAMERA`).** The seam R58's
`CYPRESS_LOCATION` is the model for, applied to the camera; the design decisions are in
`docs/rulings-pending/`. A pinned launch opens on the named coordinate and **writes nothing back**,
so a pinned launch neither inherits a camera nor leaves one. `DeepLinkHarness.launch`,
`DeepLinkOverrideReset.performOnce`, `PrimaryCTAReachabilityTests.launchAtAX5` and
`IdentifyFABReachabilityTests.launchAtAX5Denied` pin, through one spelling (`DebugMapCamera`) rather
than four copied literals.

> **Four launch helpers, not the suite** — this paragraph said "the tests stop inheriting the
> camera" for a round, and PR #66's reviewer measured that it does not. `map.lastCamera` was read
> off the device either side of a full UI run and it *changed*, while the pinned coordinate was
> never the value written: `flush()`'s early return works, and something else is still writing.
> `AccessibilityTreeTests`, `MapFilterAccessibilityTests`, `MapRecenterUITests`,
> `MapPanTabSwitchUITests` and `AlmanacGroupTapTests` all launch screen 01 with the map in the tree,
> none of them pin, and so each still opens on what the previous launch left and still leaves one
> for the next. The consequence that matters is
> `AccessibilityTreeTests.testNoUnlabeledButtonsOnLaunch`, which is where the raise was first found:
> it no longer raises, but *which* annotations it audits is still device state, silently. See "Not
> done, and why" for why those five were left unpinned rather than fixed here.

**3. A failure message that stopped being true.** `IdentifyFABReachabilityTests.legendDescription`
said an absent legend is "a device-state question (E216) and not a layout one". That sentence sent
three CI failures to the harness, where there was nothing to find. With the camera pinned it is no
longer true, and it now says so: an absent legend means the map did not color the trees that are
demonstrably under it.

#### Two things found while doing it, neither of which was the ticket

**A pinned camera would have quietly weakened the test it was fixing.** `MapOpeningCopy.showing`
ends the location notice with one of two sentences, and the fallback one — "The map is over the
middle of the city." — is five characters longer than "The map is where you last left it.". At AX5
the notice's height is what pushes the bottom chrome up against the top chrome, which is exactly
what `testTheTopChromeStaysClearOfTheBottomChromeAtAX5WithLocationDenied` measures. Pinning makes
`openingSnapshot` non-nil, which would have made `hasRememberedCamera` true and handed that class the
*shorter* sentence and the weaker version of its own guard. `hasRememberedCamera` therefore answers
`false` while pinned: a pinned launch is not a reader returning to a camera they chose, it is the
state CI is actually in — a fresh install with no history — with the camera aimed. Worth recording
because the mechanism is invisible from either file alone, and because the class was *already*
inconsistent about it: its first test got one sentence and its third the other, on the same install.

**A camera at the pole is refused, and not by a range check.** `-90,180` passes every latitude and
longitude range the parser has, and is then refused anyway: converting a fixed number of meters into
a longitude span degenerates as the meridians converge, and the result is wider than
`MapCameraMemory.maximumSpanDegrees`. The first draft of the test asserted it would parse, copying
`DebugLocationOverrideTests`' equivalent case — where it is a *fix* rather than a camera, and there
is no span to degenerate. The refusal comes from the app's own admission rule, which the parser asks
rather than restates; `MapCameraMemory.isWorthRemembering` and `maximumSpanDegrees` are `nonisolated`
for that reason, so the seam can consult them rather than keep a second copy of the threshold.

#### The guard as first written did not work, and only a watched run said so

This is the part worth reading. `frameCanAnswerHittability` was first written with two conditions —
finite, and with an interior — because those are the two the CI log's frame fails. The third,
**"somewhere on the screen"**, existed in `AccessibilityTreeTests` and was deliberately left out of
the shared helper, with a comment arguing that a control scrolled off the glass has a perfectly
finite frame and a perfectly good answer to `isHittable`, so excluding it is a choice about what
that test means rather than a guard against a raise.

That comment was wrong, and it was wrong in the direction that reads as careful. Reproduced on the
iPhone 16 Pro at 402 pt with the ticket camera written onto the device and the preflight skipped:

| state | result |
| --- | --- |
| raw `isHittable`, camera unpinned | **red** — `Failed to determine hittability of "City tree, Southern Magnolia" Button`, 16.0 s |
| two-condition guard, camera unpinned | **red** — same message, same test |
| three-condition guard, camera unpinned | green, 48.8 s |

Instrumenting the loop to print each frame immediately before the read that raised gives the reason
in one line:

    DIAG-FRAME button (-31.0, 850.0, 30.0, 30.0) finite=true label=City tree, Southern Magnolia

Finite, 30 × 30, a real rectangle in every respect — and x −31 to −1 on a 402 pt screen, so every
point of it is off the left edge. XCUITest's fallback is to sample points *inside the frame*; when
none is on the glass there is nothing to sample, which is what its own message has been saying all
along: "no suggested hit points based on element frame". **The two raises this suite has actually
seen have different frames**, and only one of them is decidable without knowing where the screen is.

The general lesson is the narrow one CLAUDE.md already states: a guard was written from the one
piece of evidence in hand, its comment reasoned confidently about the case it had *not* seen, and
the reasoning was only caught because the fix was driven red and then green rather than written and
believed. `AccessibilityTreeTests` had all three conditions from the start; hoisting two of them was
a regression dressed as a consolidation.

#### `app.frame` is a query, and the fix's first CI run failed on it

The repair passed the whole suite locally — unit, UI, warnings — and then failed CI on the very test
it was written for, with a message it had never produced before:

    Failed to get matching snapshot: No matches found for Element at index 25

Not a raise. `allElementsBoundByIndex` hands out proxies bound to an *index*, and index 25 stopped
resolving while the loop walked it. The cause is one line of the log, and it is the fix's own:

    t = 8.43s  Find the Target Application 'app.cypress.Cypress'
    t = 8.51s  Find the "A proven performer in San Francisco, …" StaticText
    t = 8.55s  Find the StaticText (Element at index 25)
    t = 9.58s      Find the StaticText (Element at index 25) (retry 1)

**`app.frame` is a query, not a stored property.** The first spelling of the helper took an
`XCUIApplication` and read `app.frame` inside itself, so a `filter` over every static text in the
app put an application query between every pair of element queries — the `Find the Target
Application` lines above, one per element. That doubled both the enumeration's elapsed time and the
number of moments at which the tree could change under it, and the enumeration lost its own index.

The repair is to make the primitive take the rectangle — `isHittableWithoutRaising(onScreen:)` — and
hoist `app.frame` above every loop; the `in app:` overload stays for the single named control, where
one extra query is nothing. Six loops were hoisted.

Two things worth keeping from it. **A guard that is correct can still be too expensive to be
correct**, when what it guards is an enumeration racing a live tree. And **the local suite was green
on this**, twice, on a quiet Mac: the failure needed CI's three-core runner to widen the window. That
is `assertReachable`'s founding observation arriving from a new direction, and it is the argument for
CI being part of the verification rather than a formality after it.

*(The hoisting also introduced, and caught in review before it ran, a shadowed `screen`: in
`DeepLinkSweepTests` the loop variable of that name is the screen's *name*, interpolated into every
failure message in the method. `let screen = app.frame` compiles and quietly rewrites six failure
messages to say `(0.0, 0.0, 402.0, 874.0)` where they said `treeProfile`. It is `appFrame` now.)*

#### The 48.8 s in that table is also a finding

Green, and four times the 12.5 s the same test takes at a normalized camera (measured under #71).
That is #71's own "pass and fail are a threshold on one continuous cost" arithmetic, unchanged: the
guard stops the raise, and XCUITest still spends retry budget on every annotation it cannot resolve.
**The frame guard makes the failure not happen; the camera pin makes the work not happen.** Neither
repair makes the other redundant, which is the argument for doing both rather than picking one.

#### The red-proofs

All watched, on iPhone 16 Pro `EA0AD796-…` at 402 pt, each restored afterwards.

*The gate (`HittabilityFilterGateTests`), both halves:*

| break | observed |
| --- | --- |
| a bare `.filter { $0.isHittable }` put back into `DeepLinkSweepTests` | red: `(offenders → ["DeepLinkSweepTests.swift [174]"]).isEmpty → false` — the right file and the right line |
| the helper's definition moved out of `UIWait.swift` (still compiling) | red on the helper-existence check only; the offenders check stayed quiet |

*The predicate (`FrameFinitenessGateTests`), body replaced with `true`:* all four negative
assertions red, each with its own message — the sweep's frame, the pin-adjust frame, the non-finite
rectangle with an interior, the finite rectangle without one — and
`testAnOrdinaryFrameCanAnswerHittability` **green**, which is the half that shows the guard is not
simply refusing everything.

*The camera seam (`DebugMapCameraOverrideTests`), one break at a time:*

| break | observed |
| --- | --- |
| `flush()` forgets it is pinned | red: "a pinned camera is never written back to the device" |
| `loadIfNeeded` ignores the pin | red: "a pinned camera is what the map opens on, whatever is on disk", printing the on-disk camera where the pin should be |
| `hasRememberedCamera` ignores the pin | red: "a pinned camera is not a camera the reader left", `.whereYouLeftOff` where `.theCityFallback` is required |

In each of those runs the other three camera tests stayed green, including the control
("with nothing pinned, the camera on disk is still read and still written") — without which all
three could have passed on a `MapCameraMemory` that had simply stopped working.

*End to end, on the device, `IdentifyFABReachabilityTests` with `map.lastCamera` written to Golden
Gate Park (`37.769402,-122.486198`, `camera-trees=0`) and the preflight skipped:*

- camera pin removed — **red**, two of the three tests, on the legend never appearing. The CI
  failure, reproduced locally on demand.
- camera pin restored, same device state — `Executed 3 tests, with 0 failures` in 21.2 s.
- and the device's `map.lastCamera` read back afterwards was **still Golden Gate Park, unchanged**,
  which is the write-back guard proved on a real device rather than in a `UserDefaults` double.

#### Not done, and why

- **The raise is reproduced but not synthesized.** Reproducing it needs a specific camera on a
  specific screen width, which is a device state a test cannot set for itself; there is no way to
  make XCUITest report an unresolvable activation point from inside the suite. CLAUDE.md's note that
  `.allowsHitTesting(false)` does not go red is the same wall from the other side, and an `.offset`
  off screen produces exactly the kind of frame the *third* condition catches — which is how that
  condition came to be tested at all, by accident of the failure rather than by design.
- **Assertion-position reads are untouched.** They can raise too, on an element specific enough that
  it has not happened. Changing them would change what they claim, which is a separate decision from
  this one.
- **The gate reads one line at a time, and the blind spot recorded here was the wrong one.** This
  bullet said the hole was "a filter split across two lines" and named
  `DeepLinkHarness.waitForCoverToArrive`'s `return` and `PrimaryCTAReachabilityTests.buttonLabels`'
  `.map` as the two instances. Both are *single-line* reads. PR #66's reviewer red-proved the actual
  hole with a probe and a control at one insertion point: the vocabulary had no `if`, so
  `if x.isHittable { … }` — the most ordinary filter spelling in Swift — passed while the same line
  written as `guard` failed, and `allSatisfy`, `map`, `reduce` and `switch` were missed too. A
  recorded blind spot that is not the real one is worse than none: it told a reader that keeping a
  filter on one line made it visible here, which was the opposite of true.

  Fixed by widening the instrument rather than by restating it. Keywords are matched as whole words
  in the part of a line that is code rather than prose (`delete` is not `let`, and `for` inside an
  assertion's message is English), calls are matched as calls, and both directions are calibrated —
  fourteen spellings it must catch, nine it must leave alone. Two holes remain and are on the gate
  itself: a `&&` composition on a bare continuation line of a multi-line assertion, which cannot be
  told from the assertion it is part of by a line-local instrument
  (`PrimaryCTAReachabilityTests:301` is one), and a filter genuinely split so the keyword and the
  read land on different lines, of which the suite has none.
- **`ContainerSpellingGateTests` had the same shape of hole, red-proved the same way.** Its
  instrument was the literal `.scrollViews`, so `app.descendants(matching: .scrollView)` passed it —
  and the un-waited two-line guess the helper replaced was therefore one `XCUIElementQuery` spelling
  away from being representable again. It now matches the element type in a *query* position, which
  leaves `FrameFinitenessGateTests`' `[.scrollView: frame]` dictionaries alone, and it carries a
  calibration fixture in each direction. The residual hole is written on the gate: an element type
  bound to a `let` first, or a call broken so `scrollView` lands on a line of its own.
- **Five classes still inherit the camera, and still write one.** Only the four launch helpers named
  under "The repairs" pin. `AccessibilityTreeTests`, `MapFilterAccessibilityTests`,
  `MapRecenterUITests`, `MapPanTabSwitchUITests` and `AlmanacGroupTapTests` do not, which the
  reviewer measured directly (`map.lastCamera` differed either side of a UI run, and never held the
  pinned coordinate). They were **deliberately** not pinned here: `MapPanTabSwitchUITests` pans on
  purpose and `AlmanacGroupTapTests` pins its own location fix, so a blind pin could change what
  they assert, and `AccessibilityTreeTests`' coverage question is the same underlying design defect
  as the bullet below rather than a camera one. What was fixed is the claim.
- **Nothing was done about the underlying design.** `assertEveryControlIsLabeled` asserting over
  elements of a screen it does not own is still the deeper defect; pinning the camera makes what it
  reads deterministic rather than making it read the right thing. Scoping the walk to the presented
  screen's own subtree is a larger change to what that helper claims, and it is not this ticket.
- ~~**The enumeration race is still live, and has now been seen twice.**~~ **Fixed** — three
  sightings, and the account is now the last section of this entry, "The enumeration race was an
  ordinal, and the ordinal is gone". Left here as a stub rather than deleted, because the two
  paragraphs above it are what a reader will have just read: hoisting `app.frame` narrowed this
  window and did not close it, and that was correct as far as it went.

#### Correction: the legend was there, and the test was waiting for the wrong element

Everything above about `isHittable` raising stands. The *second* occurrence — the species legend
that "never appeared in the accessibility tree at all within 30s" — was attributed to the inherited
camera, and that attribution is wrong. The camera is a real mechanism and it was red-proved (a
device pointed at Golden Gate Park, where the legend genuinely exists under neither element type,
went red and pinning turned it green). It is not what those CI runs were reporting.

**The failure came back on the branch that fixed the camera.** CI run 31332870414, shard `ui (1)`,
`claude/busy-newton-6aaab0` at `be80c04`, iPhone 17 Pro at 402 pt — the camera pinned by
`DebugMapCamera` on every launch in that class, and `CYPRESS-RUN: camera-normalized no`,
`device-state active-city=n/a (app not installed)`. Pass, pass, fail across three runs of the same
branch. The log says what happened, in two lines from two tests of the *same class on the same
install*:

    testTheFABClearsTheChromeAroundIt…   t = 6.92s  Checking existence of `"Species shown …" Other`
    (passed, 12.116 s)                   t = 8.29s  Expect `exists == 1` … ScrollView   → satisfied

    testTheTopChromeStaysClearOf…        t = 4.23s  Checking existence of `"Species shown …" Other`
    (failed, 36.354 s)                   t = 6.63s → 35.9s  Expect `exists == 1` … Other → never

The legend was in the tree the whole time. The test was waiting for the other spelling of it.

**The three lines, in three files.** `IdentifyFABReachabilityTests.container(_:_:)`,
`MapFilterAccessibilityTests.rowContainer(_:)`, and an inline copy inside
`MapRecenterUITests.testTheRecenterControlClearsTheFilterChipRowAtAX5WithLocationDenied`:

    let other = app.otherElements[label]
    return other.exists ? other : app.scrollViews[label]

One un-waited read of a still-loading screen, deciding which element every later wait is spent on.
Whichever way that single read lands is decided by how early it happens to run — and the two tests
above differ only in that the passing one reads the FAB first (t = 4.89 → 6.55 s) and therefore
asks about the legend 2.7 s later. This is E245's family: a one-shot read of a screen that has not
finished arriving.

#### Why the element type changes at all, which is the part that decides the repair

Not XCUITest being capricious about labeled SwiftUI groups — which is what two of those three files
asserted in a comment, and it is wrong. `MapSpeciesLegend.body` has **two branches**:

- `MapLayout.legendMaxHeight` does not bind → `chips.accessibilityElement(children: .contain)`,
  filed as an **`Other`**;
- it binds → `ScrollView { chips }.accessibilityElement(children: .contain)`, filed as a
  **`ScrollView`**. Task #258 put the label on the scroller deliberately, so the rectangle a test
  measures is the one the reader can see rather than the `FlowRow` overflowing it.

`legendMaxHeight` takes `namedSpecies count`, and that count **arrives asynchronously** as the map's
query returns and the species names resolve. So a launch genuinely renders the legend as an `Other`
first and a `ScrollView` once the palette outgrows the screen. The app is being honest; the test was
reading it once.

Measured on iPhone 16 Pro `EA0AD796-…` at 402 pt, polling both spellings at full query rate —
four launches, plus one that drives the palette by tapping a legend entry (which narrows the map to
one species, so the palette drops to one named entry and the ceiling stops binding):

| state | `otherElements` | `scrollViews` | frame |
| --- | --- | --- | --- |
| default content size, 10 s | **present** | absent | `(16.0, 159.67, 285.0, 117.33)` |
| AX5, full palette, 10 s | absent | **present** | `(16.0, 230.0, 370.0, 181.0)` |
| AX5, narrowed to one species, 15 s | **present** | absent | `(16.0, 230.0, 416.33, 59.67)` |
| AX5, filter cleared, 15 s | absent | **present** | `(16.0, 230.0, 370.0, 181.0)` |

Three things that decide the rule, and only the measurement could have said any of them:

- **`scrollViews` is not the safe default.** At the default content size the legend is an `Other`
  for the whole run, so "prefer the scroller" is guessing the other way.
- **The transient `Other` has an ordinary frame** — on the glass, finite, with an interior — so
  `frameCanAnswerHittability`, the other candidate for this predicate, accepts it every time.
- **It is stable while it lasts**: 117 consecutive samples of one unchanging rectangle in the
  narrowed state. A "two consecutive reads agree" rule does not reject it either. Both spellings
  flipped inside a single sample (< 0.65 s) when the palette changed.

So the only thing separating the transient from the answer is **how long it lasts**, and the rule
has to be a duration. That is not the predicate this ticket set out to write, and the measurement is
what changed it.

#### The repair

`XCTestCase.resolvedContainer(_:labeled:_:)` and `ContainerSpellingResolution`
(`CypressUITests/UIWait.swift`), called by all three sites, with the three hand-rolled copies
deleted. Both spellings are re-read every round; a spelling resolves when it has existed with an
unchanging, usable frame — `frameHasSettled` and `frameCanAnswerHittability`, the two predicates
already in that file — for `settlingWindow` seconds of continuous observation, and one that leaves
the tree loses whatever credit it had built up.

`settlingWindow` is four seconds, sized from the log above: the failing read at t = 4.23 s found an
`Other` and the passing read at t = 6.92 s found none, so the flip fell inside a ~2.7 s band. It is
also longer than `MapOpening.patience` (`.seconds(3)`), the app's own budget for state still
arriving after a launch.

**A genuine absence still says so.** A camera showing no trees draws no legend under either
spelling, and the failure for that keeps `assertReachable`'s sentence and now names both queries it
watched, so the two causes can no longer be told apart only by luck.

`ContainerSpellingGateTests` (unit suite, `DragGestureGateTests`' reason) fails the build if a
fourth copy appears. Its instrument is `.scrollViews` appearing anywhere in `CypressUITests/` outside
`UIWait.swift` — blunt on purpose, and `otherElements` is deliberately not the tell, because naming
an `Other` directly is an ordinary correct thing to do.

#### What the earlier logs actually say, now that they have been read

The three run numbers cited at the top of this entry were taken from the ticket rather than from the
logs. Downloaded and read:

- **All three are the same defect as 31332870414, in the opposite direction.** In each, the failing
  test's single un-waited read found **no** `Other`, fell through to `scrollViews`, and then waited
  30 s for a `ScrollView` — while the two earlier tests of the same class, on the same install
  minutes before, had found the legend as an **`Other`** and passed. Whatever the camera was doing in
  those runs, the third test was already bound to a spelling that camera's legend does not use, and
  could not have passed if the legend had arrived a millisecond later.

> **This bullet said, for one revision, that "31300530216 never failed this test — all three passed
> (7.930 s, 5.673 s, 6.850 s)." That is attempt 2.** The run has two `ui-log-1` artifacts under the
> same name, one per attempt, and the newer of the two is the passing re-run. Attempt 1 fails at
> `IdentifyFABReachabilityTests.swift:205` after 35.455 s, on `ScrollView`, exactly like the other
> two. Downloading "the artifact called `ui-log-1`" from a run that was retried gets the attempt that
> succeeded — which is the artifact-provenance rule in CLAUDE.md arriving in a shape it does not
> name: not a stale file, but the *right* file for the wrong attempt. Fetch
> `…/actions/runs/<id>/jobs?filter=all` first, read `run_attempt` per job, and pick the artifact by
> `created_at` against the attempt that failed.

Both of those runs also report `device-state active-city=n/a (app not installed)`: the CI runner
installs the app fresh, so there is no camera inherited from a previous *run* to blame. The
within-run inheritance this entry describes is real and is not what these logs show.

**The lesson worth keeping is the one about the message.** "…never appeared in the accessibility
tree at all within 30s" is what `assertReachable` and `settledFrame` print for a genuinely absent
element, and it is also what they print for an element that is present under a name the test is not
asking about. One sentence, two causes, and the entry above spent a whole round on the wrong one —
after correctly refusing the brief's *first* mis-attribution three sections earlier. Reading the log
caught that one. Not reading these three caught nothing.

#### The enumeration race was an ordinal, and the ordinal is gone

> **The ordinal is gone and the race was not.** This section's repair is correct about the binding
> and it moved the symptom rather than removing it: the very next CI run failed the same method on
> the same shard, this time with the enumeration returning the *map's* elements and every later
> `.exists` answering false. Read "The enumeration was running before the screen arrived" — the last
> section of this entry — before taking this one as the end of the story. Two repairs in a row aimed
> at how the enumeration is spelled, and the thing that needed fixing was **when** it runs.

Three sightings, all `DeepLinkSweepTests.testNothingIsAnnouncedTwice` on shard `ui (3)` of this
branch, all the same sentence with a different number in it:

| run | commit | message |
| --- | --- | --- |
| 31329045652 | `3143a5c` | `No matches found for Element at index 25` |
| 31338381219 | `7fbb818` | `No matches found for Element at index 3 from input {( StaticText, StaticText, StaticText )}` |
| 31340854135 | `885a044` | `No matches found for Element at index 17 from input {(` |

**The third is the one that settles what kind of failure this is.** `885a044` differs from
`58833e9` in one markdown file and nothing else — `git ls-tree` over `Cypress CypressTests
CypressUITests Tools` gives the same hash for both — and `58833e9`'s run (31339588378) passed
`ui (3)` in twelve minutes. Same code, same shard, one green and one red. There is no diff to
blame, and a green re-run would have proved only that it is intermittent.

**The mechanism is the binding, not the tree.** `allElementsBoundByIndex` returns proxies bound to
an *ordinal*. The proxy holds no reference to an element; every later `.frame`, `.isHittable` or
`.label` re-runs the query and takes the *n*th match of whatever it finds this time. When the tree
changes under the walk, *n* stops resolving — and XCUITest raises rather than answering, exactly as
`isHittable` does at the top of this entry. The second sighting's message says it out loud: four
matches when the count was taken, three by the time index 3 resolved.

That method gave the race an unusual amount of room. It launches six times per run and walks *every*
static text in the app each time, on a screen `arrive()` has only established the existence of. The
nested duplicate-check then read `.label` off an index-bound proxy once per element in the outer
loop and again for every pair in the inner one: on screen 18, with 29 reachable static texts, up to
about four hundred extra re-resolutions of a query against a live tree, for values that had already
been read.

**The repair, in the method** (`CypressUITests/DeepLinkSweepTests.swift`):

- `allElementsBoundByAccessibilityElement` in place of `allElementsBoundByIndex`. Each proxy is
  bound to the underlying accessibility element, so a later read resolves by identity; a *neighbor*
  leaving the tree no longer takes this element's handle with it. `AnonymizedPhotoNoticeUITests`
  already used that spelling.
- Each element's label and settled frame read **once**, into a plain `(String, CGRect)`. The pair
  comparison is arithmetic over those values and touches no proxy at all, which is where the O(n²)
  went.
- `.exists` before the hittability filter, the same spelling `assertEveryControlIsLabeled` uses, so
  an element that has already left is skipped rather than raised on.
- **A guard that the screen was examined at all.** There was none. An enumeration that returned an
  empty array — a query spelling that stopped matching, a screen that had not finished arriving —
  passed silently, which is this project's own signature defect shape.
- Containment asked in **both** orientations. The version replaced asked only whether the earlier
  entry contained the later one, which reads the sequence as if the query engine returned wrappers
  before leaves; it promises no such thing, and reading an order out of that sequence is what E118
  was filed for.

`settledFrame` is untouched and still gates every rectangle compared, on the same 30 s per-element
budget (#244). Nothing about what the method asserts is weaker.

#### The hazard in that spelling, ruled out on the device before it was relied on

`allElementsBoundByAccessibilityElement` de-duplicates by accessibility element. This method exists
to catch a labeled container that also exposes a labeled child saying the same words — if those
collapsed to one entry it would stop being able to find its own defect and stay green forever.

Measured on iPhone 16 Pro `EA0AD796-…` at 402 pt, by enumerating both spellings on all six screens
the method visits and printing `label@frame` for each. Hittable static texts:

| screen | `allElementsBoundByIndex` | `allElementsBoundByAccessibilityElement` | same labels and frames |
| --- | --- | --- | --- |
| treeProfile | 20 | 20 | yes |
| site | 17 | 17 | yes |
| species | 14 | 14 | yes |
| growthHistory (duplicate planted) | 5 | 5 | yes |
| activity | 3 | 3 | yes |
| outbox | 29 | 29 | yes |

The planted duplicate is the part that matters: two `Text`s carrying one label at two type sizes, so
that the larger rectangle strictly contains the smaller. Both spellings returned **two** entries for
it —

    PROBE@(158.5, 120.0, 85.0, 37.33)
    PROBE@(181.33, 129.67, 39.33, 18.0)

— so the de-duplication is by accessibility element and not by anything the defect shares.

**What no binding rescues, and it is worth writing down.** A labeled SwiftUI container is filed as an
`Other`, not as a `StaticText`. Both spellings tried —

    VStack { Text("…") }.accessibilityElement(children: .contain).accessibilityLabel("…")
    Text("…").padding(40).accessibilityElement(children: .contain).accessibilityLabel("…")

— produced an `Other` and a `StaticText` at the *same* rectangle, and `app.staticTexts` returns only
the child. So this method sees the E104 shape only when the wrapper is itself a `StaticText`. That
limit predates the binding change and is not repaired by it. (Also measured in passing, because it
was assumed otherwise while building the specimen: `.frame(width:…, height:…)` and `.padding(…)` do
**not** enlarge a `Text`'s accessibility frame — a padded `Text` and its unpadded twin came back as
the same rectangle to the pixel.)

#### The red-proofs

All watched on iPhone 16 Pro `EA0AD796-…` at 402 pt, each restored afterwards. The specimen is a
real duplicate announcement added to screen 11 — `ZStack { Text("PROBE").font(.treeNameHero);
Text("PROBE").font(.latinName13) }` — so the app genuinely says one thing twice.

| state | observed |
| --- | --- |
| specimen in, repaired method | **red**, and on the right sentence: `growthHistory: 'PROBE' is announced by an element at (158.5, 120.0, 85.0, 37.333…) and again by one inside it at (181.333…, 129.666…, 39.333…, 18.0), so it is heard twice` — one failure, from the one screen carrying the specimen |
| specimen in, `nesting` cut back to one direction | **red**, same sentence — so the query engine returned the container first here, and the one-directional version would have caught this specimen too |
| specimen reversed (leaf declared first), one direction | **green**, `Executed 2 tests, with 0 failures` — and legitimately: the probe shows only **one** hittable `PROBE` in that arrangement. A `Text` drawn under its twin stops being hittable and the filter drops it before any comparison |
| specimen removed | see the five repeat runs below |

**So the both-orientations change is not proved by a red run, and this entry does not claim it is.**
The reverse arrangement could not be synthesized at all: the contained element must be drawn on top
to be hittable, and drawn on top it enumerates second. The change is kept because it costs one
`contains` and because the alternative is a test whose correctness depends on an order E118 says
nothing may depend on — said plainly here rather than dressed as a measurement.

#### What this does not fix

The ROADMAP's "Also outstanding" entry on `assertEveryControlIsLabeled`'s **scope** stands
untouched. That helper audits every element in the app rather than the screen under test, and this
change makes a *different* method's enumeration survive a moving tree; it does not narrow what
either method looks at. The scope question is still owed, and deleting that entry on the strength of
this would be trading a design defect for a green.

#### What the repaired method was actually run through

All on iPhone 16 Pro `EA0AD796-…` at 402 pt, in this worktree, judged only by the `VERIFY-` line.

Five back-to-back runs of `DeepLinkSweepTests`, because one green run cannot disprove a race:

| run | load | result |
| --- | --- | --- |
| 1 | none | `Executed 2 tests, with 0 failures (0 unexpected) in 191.330` |
| 2 | none | `Executed 2 tests, with 0 failures (0 unexpected) in 191.520` |
| 3 | six busy loops | `Executed 2 tests, with 0 failures (0 unexpected) in 187.533` |
| 4 | six busy loops | `Executed 2 tests, with 0 failures (0 unexpected) in 185.684` |
| 5 | six busy loops | `Executed 2 tests, with 0 failures (0 unexpected) in 188.397` |

`grep -c "No matches found for Element at index"` is 0 on all five — and it is 1 on the downloaded
`ui (3)` log of run 31340854135, which is the calibration that makes those five zeroes a measurement
rather than a spelling mistake.

**The load did nothing measurable and the table says so.** Six spinning shells on a ten-core machine
left the run times inside four seconds of the unloaded pair, and if anything shortened them. Whatever
paces this method, it is not CPU on this Mac. So five green runs here are five green runs here; they
are not a reproduction of a three-core CI runner, and the run that decides this is the one on CI.

Suite, both into a **fresh** DerivedData at `94c2f30`:

    unit  VERIFY-OK: ✔ Test run with 1341 tests in 137 suites passed after 122.617 seconds.
    ui    VERIFY-OK: Executed 109 tests, with 0 failures (0 unexpected) in 1582.010 seconds
          VERIFY-NOTE: XCTest skipped=0
    both  VERIFY-WARNINGS: source=0 non-source=3 compile-tasks=452 files-checked=18

**One thing the round got wrong on the way, worth a line.** The first pass of the doc comment ended
with "recorded in `docs/errata-pending/`" — a code comment deferring to an erratum that has no number
yet, which CLAUDE.md forbids and `PendingCitationGuardTests` fails the build over. It did fail the
build, by file and line, on the first full unit run. The gate is not decoration.

#### The enumeration was running before the screen arrived

**The section above fixed the binding and the method failed again on the next CI run.** Run
31347748098, shard `ui (3)`, attempt 1, head `2b98462` — the required `gate` check red on it:

    DeepLinkSweepTests.swift:240: error: XCTAssertGreaterThan failed: ("0") is not greater than ("0")
      → growthHistory: not one static text was reachable, so no pair was compared and
        this screen was not actually examined

A different sentence from the three ordinals, and it is the guard that section *added* doing exactly
the job it was added for: an enumeration that came back empty no longer passes silently. What it
caught is not an empty screen. Twenty lines of the log say what was actually enumerated:

    t = 103.21s Get all elements bound by accessibility element for: Descendants matching type StaticText
    t = 103.54s Checking existence of `"What tree is this?" StaticText`
    t = 103.55s Checking existence of `StaticText (Identity Binding)`
    …six more, all within 80 ms, no frame read at all

Two things in that excerpt, and either one alone settles it. Every `.exists` answered **false**
milliseconds after the snapshot the proxies came from was taken — so the whole snapshot was
discarded, not one element out of it. And the labels that did resolve, `"What tree is this?"` and
`"N"`, are **screen 01's chrome**: the identify prompt and a map annotation. The enumeration ran
while the map was still the visible screen, and by the time the filter asked each proxy whether it
existed, the map was gone.

So `growthHistory` was never examined, and neither was any screen this method visited on that run —
the other five arms simply got their enumeration in late enough to find something, which is luck
rather than a check.

**Three symptoms, one cause, and the first two repairs each treated a symptom.**
`allElementsBoundByIndex` lost an ordinal mid-walk, so it became
`allElementsBoundByAccessibilityElement`, which cannot lose an ordinal and instead loses the entire
snapshot when the walk starts on a screen that is on its way out. Both repairs asked *how* the
enumeration is spelled. Neither asked *when* it runs, and that is the whole of it: `arrive()` waits
only for the anchor text to **exist**, which a `NavigationStack` push satisfies early in the slide
transition while the outgoing screen is still in the tree — the race E245 diagnosed for this file's
*other* sweep, in this file's other method, with the repair sitting one method away.

#### The repair, which is a wait this file already owned

`DeepLinkHarness.waitForPushedScreenToArrive(_:screen:)`, called after `arrive()` and before
anything is enumerated. It is the same call `testEveryPushedScreenSaysWhereItIsFirst` makes for
this reason and the same call `check()` makes for `pushed: true` (task #243); there is no new
mechanism here, only a third caller for the one definition.

**That it is the *pushed* wait and not the cover wait was checked rather than assumed**, because the
two are indistinguishable at the call site and the wrong one is a silent no-op — `waitForCoverToArrive`
on a screen that never presents a cover waits for a title that is already there and returns. Read out
of `DebugDeepLink.open`: `treeProfile`, `site`, `species`, `growthHistory` and `activity` are
`router.push`, and `outbox` sets `router.tab = .you` and then pushes. The two `router.present` cases
in that enum, `careLog` and `share`, are not in this method's loop at all. All six are pushed.

**What it does not do, said plainly.** It establishes that the tab root has left; it establishes
nothing about the incoming screen's own contents. A pushed screen whose rows are still resolving can
still change under a walk that reads every static text in the app six times a run, and the tab bar's
hittability can lapse *before* the slide finishes rather than at the end of it — the incoming screen
covers `My Grove`'s activation point partway across, not at the last frame. The window the log above
shows is closed. The window is not.

The count guard is what remains pointed at whatever is left, and keeping it fireable was a
requirement of this change rather than a side effect: a repair that made it unfireable would have
been worse than the defect, because this is the third time this method has failed and the guard is
the only reason anyone knows what it failed at.

#### The red-proofs

Both watched on iPhone 16e `3A1F212D-…` at 390 pt, in this worktree, each restored afterwards.

| break | observed |
| --- | --- |
| a real duplicate planted on screen 11 — `ZStack { Text("PROBE").font(CypressFont.treeNameHero); Text("PROBE").font(CypressFont.latinName13) }` | **red**, on the right sentence and the right arm: `growthHistory: 'PROBE' is announced by an element at (152.5, 47.0, 85.0, 37.33…) and again by one inside it at (175.33…, 56.66…, 39.33…, 17.99…), so it is heard twice` |
| the enumeration pointed at a query that matches nothing (`app.staticTexts.matching(identifier: "RED-PROOF-NO-SUCH-ELEMENT")`) | **red**, four times, with CI's exact sentence: `("0") is not greater than ("0") - treeProfile: not one static text was reachable…`, then `site`, `species`, `growthHistory` |

The first is the one that matters most, and it is the one the wait could have broken. `growthHistory`
is the arm run 31347748098 failed on; with the wait in place the method still reaches that screen,
still reads it, and still finds a duplicate the app genuinely announces. The second is the count
guard, proved fireable after the change, on the same assertion and the same words CI printed.

The log of the first also shows the wait doing its job six times and only six —
`Expect predicate 'hittable == 0' for object "My Grove" Button` at t = 5.19 s, 39.21 s, 68.20 s,
92.56 s, 104.59 s and 113.90 s, one per screen — and `grep -c "not one static text was reachable"`
is 0 across it, so no arm was skipped in the run that found the planted defect.

#### What this round was run through

All on iPhone 16e `3A1F212D-…` at 390 pt, in this worktree, judged only by the `VERIFY-` line.

Five back-to-back runs of `DeepLinkSweepTests`, because one green run cannot disprove a race:

| run | result |
| --- | --- |
| 1 | `Executed 2 tests, with 0 failures (0 unexpected) in 164.901` |
| 2 | `Executed 2 tests, with 0 failures (0 unexpected) in 164.667` |
| 3 | `Executed 2 tests, with 0 failures (0 unexpected) in 165.816` |
| 4 | `Executed 2 tests, with 0 failures (0 unexpected) in 165.660` |
| 5 | `Executed 2 tests, with 0 failures (0 unexpected) in 164.965` |

**Local green does not settle this and is not offered as if it did.** Three previous attempts failed
to reproduce this family on a quiet Mac, the previous round's five green runs did not stop the next
CI run going red, and the load experiment in that round moved the elapsed time by less than four
seconds. What these five show is that the wait did not break the method, on five consecutive tries.
What decides it is CI.

Suite:

    unit  VERIFY-OK: ✔ Test run with 1349 tests in 138 suites passed after 121.695 seconds.
    ui    VERIFY-OK: Executed 109 tests, with 0 failures (0 unexpected) in 1546.615 seconds
          VERIFY-NOTE: XCTest skipped=0
    warn  VERIFY-WARNINGS: source=0 non-source=3 compile-tasks=453 files-checked=16

The warnings line was taken from a unit run into a **fresh** DerivedData directory, and the
instrument was calibrated before it was believed: the same command with a made-up filename answers
`VERIFY-FAIL: cannot certify a warning count for: NoSuchFile.swift — no SwiftCompile task for those
files in this log (E203)`, and with a real one certifies. A count that cannot refuse is not a count.

CI, run 31353769578 at `580b671`: `plan` printed *"the suite runs — these are not prose:"*, so the
green `gate` on this one is evidence about the code rather than about the diff. `unit` and all four
`ui` shards pass; shard 3 — whose own log line says `shard 3 runs 4 class(es): DeepLinkSweepTests
PrimaryCTAReachabilityTests SheetHeightUITests AlmanacGroupTapTests` — reports `Executed 19 tests,
with 0 failures (0 unexpected) in 483.147 seconds` on iPhone 17 Pro at 402 pt. That is the shard and
the runner width the three ordinal failures and this one all came from.

**One green CI run does not close an intermittent failure either**, and the history in this entry is
the reason to say so out loud: the ordinal repair also had a green run behind it. What is different
is the diagnosis — the log named the outgoing screen's own elements — not the colour of the run.

#### A device failure in the middle of this, recorded because it looked exactly like a defect

The first attempt at the five runs above failed **fifteen times**, both tests, every screen:

    treeProfile: the app launched but 'Tree' never appeared in the accessibility tree —
    either the screen did not open, or its title is not exposed

No deep-link failure banner, no crash report, no static text of any kind in the tree for the full
30 s on every one of the fifteen arms. Nothing had changed in the tree since a run forty minutes
earlier on the same device that reached all six screens and found a planted duplicate on the fifth.

What had changed is the device. Another worktree's `xcodebuild` had run a full suite against this
same simulator in between — `Tools/run_tests.sh` refused the first five attempts on exactly that
collision, which is the guard working — and the failures began on the first run after it finished.
`xcrun simctl erase`, and the same tree went green five times in a row.

This is CLAUDE.md's "a simulator can degrade silently, and its first symptom looks like a real
defect", with the aggregate tell available immediately rather than over a day: fifteen failures at
once, all of them the *arrival* wait rather than anything the change touches, on a device a
neighbouring run had just finished with. It is worth a paragraph because the shape is so close to a
genuine one — a deep-link seam that stopped resolving would print these exact sentences.

#### The second CI run went red, and not here

Run 31357536798, `ui (3)`, on the same code (the only commit between the two runs is this file):

    AlmanacGroupTapTests.swift:257: error: … testWalkTheNineOpensAMapOfThemAll :
    XCTAssertTrue failed - the Journal tab draws no “Neighborhood” segment,
    so screen 12 has no entrance

`Executed 19 tests, with 1 failure`, and **both sweep tests are in the passing 18** —
`testEveryPushedScreenSaysWhereItIsFirst` in 59.2 s, `testNothingIsAnnouncedTwice` in 139.5 s. So the
required `gate` is red again on this PR and it is red on a different class: `AlmanacGroupTapTests` is
unchanged on this branch, runs *before* `DeepLinkSweepTests` in the shard's alphabetical order, and
passed on run 31353769578 minutes earlier on the same tree.

Its shape is a 30 s wait for `"Neighborhood" Button` that never arrives — the same family as the
legend failure this entry corrects further up, and the same family main is currently red on
(31355757575, `ui (1)`, `IdentifyFABReachabilityTests` at line 205). Recorded here because a reader
who follows this entry's run numbers will find a red `gate` on the run that proves the repair, and
the two facts have to sit next to each other: `testNothingIsAnnouncedTwice` passed on both CI runs;
the gate is red for something else.
