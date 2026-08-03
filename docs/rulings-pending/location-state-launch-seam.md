### R?? — A UI test drives the app's location state; it does not detect it (task #121, delegated)

*Pending. Cite this file as `docs/rulings-pending/location-state-launch-seam.md` until the
orchestrator splices a number; #121 delegated the shape of the state-driving mechanism.*

#### The ruling

**`CYPRESS_LOCATION` in the launch environment replaces the composition root's one shared
`MapLocationProvider` with a pinned double reporting exactly the availability it names.** The
grammar is `DebugLocationOverride.parse`:

    CYPRESS_LOCATION=denied                   the reader said no
    CYPRESS_LOCATION=servicesOff              Location Services off device-wide
    CYPRESS_LOCATION=notAsked                 the sheet has not been shown
    CYPRESS_LOCATION=waitingForFix            allowed, no fix yet
    CYPRESS_LOCATION=37.78485,-122.4215       a fix, at DebugLocationOverride.defaultAccuracyM
    CYPRESS_LOCATION=37.78485,-122.4215,25    a fix, at a stated accuracy

All five of `MapLocationProvider.Availability` are reachable. The named values are spelled exactly
as the enum's own cases, so there is one vocabulary rather than two.

The two tests that used to skip on ambient simulator state are now unconditional:
`MapRecenterUITests.testPressingItWithLocationDeniedExplainsRatherThanDoingNothing` launches with
`denied`; `AlmanacGroupTapTests` launches with `37.78485,-122.4215`.

#### The problem this fixes, stated narrowly

The two skips were **honest** and **correctly reasoned**. Both were documented at their site with
`MapSearchUITests`' argument — *a skip says "not checked here", which is true, where a failure would
say "broken", which is not* — and both could genuinely fire, which distinguishes them from #101's
guard that never could. Nothing here contradicts that reasoning.

The residual problem is about **reporting**. A skipped test is invisible in the line this project
judges a run by: `Test run with N tests passed` counts a test that declined to run exactly the same
as one that ran and passed. `MapRecenterUITests`' refusal test skipped whenever location was *not*
denied — which is the state of every simulator anybody has ever handed this suite — so the permission
refusal path, the sentence naming the limit and the Settings button, was unexercised in every
ordinary run, under a green number, and nobody reading that number would know.

The cure for a test that detects state is to let it drive the state. Both candidate fixes in the
ticket were available; this is the first and preferred one, and it turns two conditional tests into
two unconditional ones rather than making a skip louder.

#### What the seam proves, and what it does not

**It proves the app's behavior in each location state. It does not prove CoreLocation's behavior in
producing that state.** A pinned provider never talks to `CLLocationManager`: no delegate is
attached, `start()` and `stop()` are no-ops, and `authorization` is derived from the availability
rather than read. So `CYPRESS_LOCATION=denied` exercises everything downstream of "the app believes
location is denied" — the standing notice, the recenter refusal, the Settings affordance — and
nothing upstream of it.

What is therefore *not* covered, and was not covered by the skipping version either: that iOS
actually reports `.denied` after a revoke, that `MapLocationProvider.apply(authorization:)` maps the
status correctly, and that the Springboard permission sheet appears and can be answered. The first
two are `CypressTests/MapLocationChurnTests`' subject, driving `manager.delegate` directly. The
third is not tested anywhere and this ruling does not claim it is.

`xcrun simctl privacy <udid> revoke location app.cypress.Cypress` remains the way to put a device in
the real state, and remains worth doing by hand before believing anything about the permission
boundary itself.

#### Why the composition root and not the view

`RootView` owns the one shared provider (ARCHITECTURE §3), and every screen that reads a fix —
01, 05, 07, 12, 16, and the visit flow — reads that one. Pinning it there means one substitution
reaches all of them, and `MapHomeView`'s own comment about why it must not construct a provider
stays true. Substituting per screen would have been six seams and six chances for them to disagree.

#### Why `authorization` is derived rather than named separately

`.denied` with an `authorizedWhenInUse` status is not a state iOS can be in. A seam that let a test
construct one would be a seam for testing states the app will never see, and a failure found in such
a state is not a defect. The mapping is `notAsked → notDetermined`, `denied → denied`,
`servicesOff → restricted`, `waitingForFix`/`located → authorizedWhenInUse`.

#### Why a coordinate is a first-class value, and why the default accuracy is 8 m

`AlmanacGroupTapTests` needs the *presence* of a fix, not its absence, so "denied or fixless" would
not have made it unconditional. The default accuracy is 8 m because D6 excludes a reading worse than
15 m from growth charting: a pinned fix reporting a pessimistic accuracy would silently empty every
chart built on it, putting the app in a state no reader is ever in. A caller who wants the other side
of that gate says so with a third field.

#### The one cost, and how it is contained

**A pinned coordinate moves screen 01's camera, and that camera outlives the run.** `MapCameraMemory`
writes it out on the way to the background and the next run's E216 preflight reads it back — so a
test that pinned a fix over the ocean would leave the device refusing the following run. Both named
fixtures are inside the inventory's coverage and the counts were measured over the same ±250 m box
`Tools/run_tests.sh count_camera_trees` uses:

    37.78485, -122.4215   Western Addition                  780 trees
    37.7596,  -122.4269   Mission Dolores, the map's default 553 trees

`DebugLocationFixtures` carries both, with the measurement. A new coordinate must be measured the
same way before it is pinned.

#### An invalid value is a banner, never a fallback

`CYPRESS_LOCATION=Denied` does not quietly become the real provider. It draws
`LOCATION OVERRIDE FAILED · Denied · expected denied | servicesOff | …` over the app, which is
`DebugDeepLink.Failure`'s rule applied to the same class of mistake: a seam that fell back would let
a test assert the denied refusal path against a simulator with a perfectly good fix, and it would
then fail somewhere else entirely — or pass.

#### On `Tools/verify_test_log.sh` and the skip count (E216)

**Surfaced, deliberately not refused against a recorded expectation.** The script now prints
`VERIFY-NOTE: XCTest skipped=N` and, in a run of both targets, appends the XCTest summary to the
`VERIFY-OK` line — which it previously dropped entirely, because Swift Testing's line wins and
XCTest's `with M tests skipped` clause went with it.

Refusing on movement was considered and rejected. The expectation would have to live somewhere, and
there is nowhere honest to put it: the legitimate count changes whenever a test is added, removed, or
— as in this very ticket — stops skipping, so the number would be edited on most branches and would
spend its life either wrong or stale. A wrong expectation refuses runs that are fine, and a guard
that refuses good runs is a guard somebody switches off. E216's insight is real and worth keeping —
*a UI log whose skip count changed between two runs of the same tree is reporting a device change,
not a code change* — but it is an insight a reader applies, not a threshold a script enforces. What
the reader needs is the number in front of them, beside the device that produced it. That is now
what they get.

#### The proof

- `CypressTests/DebugLocationOverrideTests` — the grammar, every refusal, and that a pinned provider
  cannot be moved by `start()`.
- Red-proofed on the device, iPhone 16e `3A1F212D-…`, by breaking each half in turn:
  - the app's refusal path made inert (`case .explainRefusal: recenterAnswer = nil`) →
    `XCTAssertTrue failed - pressing the recenter control with location denied changed nothing on
    screen`
  - the state the tests used to skip on, driven deliberately (`CYPRESS_LOCATION=waitingForFix` for
    the refusal test, `notAsked` for the almanac) → both go **red** where they used to go
    **skipped**: `launched with location denied and screen 01 drew no standing notice about it` and
    `screen 12 drew "See your neighborhood" on a launch that pinned a fix … so the almanac never
    received a coordinate`.
- Before: these four cases contributed skips to every run. After: `Executed 4 tests, with 0
  failures`, no skips.
