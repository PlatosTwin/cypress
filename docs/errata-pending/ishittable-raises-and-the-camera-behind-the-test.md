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
> One of the three run numbers above never failed this test at all. Read "Correction: the legend was
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
directions: six real spellings it must catch, five it must leave alone.

**2. The tests stop inheriting the camera (`CYPRESS_MAP_CAMERA`).** The seam R58's `CYPRESS_LOCATION`
is the model for, applied to the camera; the design decisions are in `docs/rulings-pending/`. A
pinned launch opens on the named coordinate and **writes nothing back**, so a run neither inherits a
camera nor leaves one. `DeepLinkHarness.launch`, `DeepLinkOverrideReset.performOnce`,
`PrimaryCTAReachabilityTests.launchAtAX5` and `IdentifyFABReachabilityTests.launchAtAX5Denied` all
pin, through one spelling (`DebugMapCamera`) rather than four copied literals.

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
- **The gate reads one line at a time.** A filter split across two lines — the keyword on one, the
  read on the next — passes it. Two of those existed (`DeepLinkHarness.waitForCoverToArrive`'s
  `return`, `PrimaryCTAReachabilityTests.buttonLabels`' `.map`) and both were found by reading rather
  than by the gate; both now call the helper. The blind spot is recorded for the same reason
  `DragGestureGateTests` records its block-comment one: a gate whose limits are written down is a
  gate, and one whose limits are assumed is a false green.
- **Nothing was done about the underlying design.** `assertEveryControlIsLabeled` asserting over
  elements of a screen it does not own is still the deeper defect; pinning the camera makes what it
  reads deterministic rather than making it read the right thing. Scoping the walk to the presented
  screen's own subtree is a larger change to what that helper claims, and it is not this ticket.

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

- **31300530216 never failed this test.** All three `IdentifyFABReachabilityTests` tests passed
  (7.930 s, 5.673 s, 6.850 s). That run's failure is the `DeepLinkSweepTests` raise, which is
  occurrence One. The citation was wrong.
- **31291434427 and 31294993494 are the same defect as 31332870414, in the opposite direction.**
  In both, the failing test's single un-waited read at t = 5.93 s and t = 7.29 s found **no**
  `Other`, fell through to `scrollViews`, and then waited 30 s for a `ScrollView` — while the two
  earlier tests of the same class, on the same install minutes before, had found the legend as an
  **`Other`** and passed. Whatever the camera was doing in those runs, the third test was already
  bound to a spelling that camera's legend does not use, and could not have passed if the legend had
  arrived a millisecond later.

Both of those runs also report `device-state active-city=n/a (app not installed)`: the CI runner
installs the app fresh, so there is no camera inherited from a previous *run* to blame. The
within-run inheritance this entry describes is real and is not what these logs show.

**The lesson worth keeping is the one about the message.** "…never appeared in the accessibility
tree at all within 30s" is what `assertReachable` and `settledFrame` print for a genuinely absent
element, and it is also what they print for an element that is present under a name the test is not
asking about. One sentence, two causes, and the entry above spent a whole round on the wrong one —
after correctly refusing the brief's *first* mis-attribution three sections earlier. Reading the log
caught that one. Not reading these three caught nothing.
