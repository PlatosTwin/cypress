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
`XCUIElement.isHittableWithoutRaising` (`CypressUITests/UIWait.swift`) asks `frameCanAnswerHittability`
first — finite, and with an interior — and returns `false` where the raw property would raise. Every
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

#### The red-proofs

*(filled in below from watched runs)*

#### Not done, and why

- **The raise itself is not synthesized in a test.** There is no way to make XCUITest report
  `{{inf, inf}, {0.0, 0.0}}` on demand from inside the suite — CLAUDE.md's own note that
  `.allowsHitTesting(false)` does not go red is the same wall from the other side, and an `.offset`
  off screen produces a perfectly finite frame that `isHittable` answers `false` to without raising.
  What is proved instead is split: the predicate is proved directly against the exact rectangle the
  CI log printed (`FrameFinitenessGateTests`), and the wiring — that every filter position calls it
  — is proved by breaking the gate. Neither is a substitute for reproducing the raise, and this is
  written here rather than left to be discovered.
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
