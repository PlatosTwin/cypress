### E?? — The false-red families are now preflight refusals, and the 390 pt premise did not survive the device (task #182)

*UNNUMBERED — the orchestrator splices the number at merge. Filed from branch `p1/round8-a`,
measured on iPhone 16e `3A1F212D-8F3A-41F1-AF72-EC95E155A4C9`, freshly erased, 2026-08-02.*

---

Task #182 moved four recurring false-red families out of prose and into `Tools/run_tests.sh` and
`Tools/verify_test_log.sh`, on the postmortem's finding that every mechanized rule stopped
recurring and every prose rule recurred two to five times. Two things were learned in the doing
that are not in the tickets that ordered it.

---

## 1 · E202-B's "too wide" is a function of the screen, not a constant — and the 16e is stricter

E202-B records a leftover `map.lastCamera` as a false red: screen 01 reopens where it was left, and
at a wide zoom it draws cluster badges rather than tree pins, so `cityTreePins(app) > 0` is never
true. What E202 could not say, because it was written on one device, is **where the boundary is**.

It is not a constant. `MapZoom.level` recovers the zoom from the span *and the view's width* —
`zoom = log2(360 · viewWidth / (256 · Δlon))` — and `MapViewport.shouldCluster` clusters at zoom
≤ 15 and draws individual pins at ≥ 16. So the widest camera that still draws pins is

    Δlon ≤ 360 · W / (256 · 2^16)

which is a different number on every device the agents use:

| Device | Width | Widest camera that still draws pins |
|---|---|---|
| iPhone 16e | 390 pt | 0.0083685° |
| iPhone 16 Pro | 402 pt | 0.0086260° |
| iPhone 16 Plus / Pro Max | 430 pt | 0.0092268° |

**A stored camera of 0.0085° is therefore a false red on the 16e and a clean run on the 16 Pro** —
measured, not reasoned: planted on the 16e it is refused as zoom 15, and the same value computes to
zoom 16 at 402 pt. Two agents handing each other a device, or one agent reusing a simulator another
sized, can produce a red that neither can reproduce.

`Tools/run_tests.sh` now computes this threshold per run from the device type's own
`mainScreenWidth ÷ mainScreenScale`, rather than from any remembered table of screen sizes, and
refuses to start on a camera below zoom 16 *for that screen*. It does not refuse on a camera that
is merely remembered: the full suite leaves `[37.759602, -122.426903, 0.001081, 0.001362]` behind
(zoom 18), and that is a legitimate state to run in.

## 2 · The two failures task #183 was created to fix did not occur on a 390 pt device

**This refutes the premise #182 was briefed with, and #183 should be re-scoped before it is worked.**

The brief for #182 stated that on the 16e's 390 pt screen two map tests fail that pass at 402 pt:
`MapFilterAccessibilityTests.swift:265` (the filter row's chips on two lines at default size,
against #166's one-row instruction) and `MapSearchUITests.swift:392` (a hit-area assertion
comparing floats exactly, `43.99999999999999 >= 44.0`). The full suite was run on a freshly erased
16e at a tree identical to `60afdf0` outside `Tools/`:

    Test run with 1068 tests in 101 suites passed after 118.047 seconds.
    Executed 68 tests, with 8 tests skipped and 0 failures (0 unexpected)
    ** TEST SUCCEEDED **

Neither assertion failed, and neither was skipped past — which is the check that matters, because
this device is fixless and eight UI tests do skip on it. The enclosing tests both ran and both
passed:

- line 265 sits in `testTheFilterRowIsReachableAndEveryChipIsALivePill` — **passed** (13.385 s)
- line 392 sits in `testTheClearControlAppearsOnlyWithTextAndCanBeTapped` — **passed** (8.902 s)

All eight skips are location-related and are the suite's documented eight: `AlmanacGroupTapTests`
×2, `MapCentredStateUITests` ×2, `MapPanTabSwitchUITests` ×2, `MapRecentreUITests` ×1, and
`MapSearchUITests.testTypingASpeciesNameNarrowsTheMap`.

What this does **not** establish is that the two assertions are safe. The hit-area assertion at
`MapSearchUITests.swift:392` compares a layout float to 44 with `XCTAssertGreaterThanOrEqual` and
no tolerance, which is fragile whatever it reported on one run; #183's second half is worth doing
on that argument alone. But it should be opened as "this assertion has no tolerance", not as
"this test fails on the 16e", because on a clean 16e it does not.

The narrow-device concern that motivated #182's fourth family survives the refutation intact: until
this run, no verification in this project's history had used a screen narrower than 402 pt, and
nothing in a log said so. That is now stamped (`CYPRESS-RUN: screen-width-pt`) and echoed by the
verifier on every judgment.

## 3 · The collision check an agent would write does not work in the shell it runs in

The `[x]codebuild` idiom — a bracket class so `grep` does not match its own command line — is a
bash idiom. Under `zsh`, unquoted, the bracket is a glob:

    % ps -eo command= | grep -c [x]codebuild
    (eval):1: no matches found: [x]codebuild

zsh aborts the command before `grep` runs at all, with a real `xcodebuild` live at that moment. An
`if` around it takes the else branch, and the check reports no collision while reporting nothing.
`Tools/run_tests.sh` therefore uses no pattern at all: it reads `ps -eo pid=,command=` in a `while`
loop and matches with a `case`, which has nothing to glob and nothing to self-match.

---

**Filed alongside:** `Tools/run_tests.sh` gains a stamped provenance header and three refusals
(collision, E202-A leftover city, E202-B too-wide camera); `Tools/verify_test_log.sh` gains a
`SwiftCompile` task count, a `--warnings` mode that refuses to certify a warning count from a build
that compiled nothing (E203), and provenance notes. Location state is deliberately not checked — a
fixless or location-denied device is a legitimate configuration and two tests skip on it by design
(#121).
