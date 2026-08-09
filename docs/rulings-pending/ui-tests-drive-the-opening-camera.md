### A UI test drives screen 01's opening camera; it does not inherit it

*Pending. Cite this file as `RULINGS <this file>` until the orchestrator splices a number.*

#### The ruling

**`CYPRESS_MAP_CAMERA` in the launch environment replaces the camera screen 01 opens on, and
suppresses the write-back that would leave it on the device.** The grammar is
`DebugMapCameraOverride.parse`:

    CYPRESS_MAP_CAMERA=37.78485,-122.4215       at MapLayout.defaultSpanMeters
    CYPRESS_MAP_CAMERA=37.78485,-122.4215,300   300 m across

Anything else — one field, four fields, a word, a coordinate off the globe, a non-positive span, or
a span so wide `MapCameraMemory` would refuse to remember it — draws
`MAP CAMERA OVERRIDE FAILED · <raw> · <reason>` over the app rather than falling through, for
`DebugDeepLink.Failure`'s and R58's reason: a seam that quietly did nothing would leave a test
reading a screen drawn over whatever the last launch left, which is the state it exists to remove.

`#if DEBUG`, read from the process environment and not from `launchArguments` (which `UserDefaults`
also consumes), unreachable from the app — R58's three constraints, unchanged.

#### Why this is the same ruling as R58, one screen over

R58's argument was that **a test which detects state is cured by letting it drive the state**. It
applied that to location. The same sentence was true of the camera and nobody had said it:

- `MapOpeningCamera` remembers the camera the reader left, which is right for the product (#115) and
  means **every UI test inherits screen 01's camera from whatever ran before it** — the last test,
  the last run, or another agent's suite on a shared simulator;
- screens 09, 10 and 18 are presented *over* the map tab root rather than pushed, so screen 01's
  annotations stay in the accessibility tree behind them, and `DeepLinkHarness
  .assertEveryControlIsLabeled` walks `app.buttons`, which is every button in the app;
- `MapSpeciesLegend` draws nothing when it has colored nothing, so whether the legend is in the tree
  at all is a fact about how many trees the camera has in view.

So a test about a form's labels, and a test about AX5 chrome geometry, both had a hidden dependency
on where a map they never mention was pointed. Two CI failure families came out of it, and the
tests' own failure messages sent readers to E216 and to the harness — where there was nothing to
find, because nothing was wrong with the device.

#### What it deliberately does not do

**It does not put trees under the camera.** It moves the camera; the seed decides what is there.
`DebugMapCameraFixtures.westernAddition` is offered by name for that reason, and it is the *same
string* `DebugLocationFixtures.westernAddition` holds — one measured coordinate (780 trees in the
±250 m box) under two names, asserted equal by `DebugMapCameraOverrideTests`.

**`MapLayout.defaultCenter` is deliberately not offered.** The app's own fallback is Mission Dolores
Park, whose 120 × 261 m opening view contains no inventoried tree — `defaultSpanMeters`' doc comment
says so and every `CYPRESS-RUN` header stamps `viewport-trees=0` for it. It is the right place for
the app to open and the wrong place for a test that needs a pin, a species color or a legend.

**It does not replace `Tools/run_tests.sh`'s camera preflight (task #71), and the two are not the
same guarantee.** The preflight normalizes the device's stored camera once, before `xcodebuild`
starts. It cannot say anything about the camera the twentieth app launch inside a UI run inherits
from the nineteenth — and `IdentifyFABReachabilityTests` failed on exactly that gap, its first test
passing and its third failing on the same install, minutes apart. The preflight is about the device;
this is about the launch.

**It does not freeze the camera within a session.** `MapCameraMemory.sessionSnapshot` still tracks a
pan the test itself performs, so a pinned run does not quietly change what
`MapPanTabSwitchUITests` asserts about a pan surviving a tab switch (task #128).

#### The two decisions inside it that are not obvious

**A pinned run writes nothing.** `flush()` returns early. A seam that left its camera in
`map.lastCamera` would hand the *next* run — a run that pinned nothing — a remembered camera it
never chose, which is the inheritance this ruling removes rather than relocates. A test seam that
changes the state of the device it ran on is E216's and task #71's shape.

**A pinned camera is not a camera the reader left.** `hasRememberedCamera` answers `false` while
pinned, so `MapOpeningCopy.showing` produces the fallback sentence — "The map is over the middle of
the city." — rather than "The map is where you last left it." The two differ by five characters, the
location notice is the taller of them at AX5, and its height is what pushes the bottom chrome up
against the top chrome, which is precisely what `IdentifyFABReachabilityTests` measures. A pinned
launch is not a reader returning to a camera they chose; it is the state CI is actually in — a fresh
install with no history — with the camera aimed. Answering `false` keeps that class measuring the
longer sentence deterministically, where before its first test got one sentence and its third the
other, on the same install.

#### The cost, stated rather than left to be found

The app now carries a second DEBUG launch seam that changes what screen 01 shows. Both are inert
without their environment variable and both refuse loudly rather than fall through, but the surface
is bigger than it was, and a reader debugging a UI test's screen has two variables to check instead
of one. `MapOpeningCamera`'s `MapCameraMemory.shared` is the single place the pin is applied, and
the `#if DEBUG` is at that construction site rather than inside the type, so a Release build has no
branch to take.
