### the almanac's two group-tap tests blamed the almanac for a missing GPS fix (#63)

`AlmanacGroupTapTests` failed on any machine with no simulated fix over San Francisco, and it failed
with two sentences that were not true: `§4's CTA is not on the almanac` and `R10's row is not on the
almanac`. The almanac was fine. Without a fix there is no coordinate, without a coordinate there is
no neighbourhood (A4, ERRATA E44), and `AlmanacScreen` draws E123's `See your neighbourhood` prompt
**in place of** all four blocks — so both counted rows are correctly absent and the test was reading
a working screen and reporting a broken one.

**The guard for this already existed and could not fire.** `reachAlmanac` ended with
`app.staticTexts["See your neighbourhood"].waitForExistence(timeout: 3)` and, one line below, the
right message. Three seconds is a fixed wait on an *absence*, which is wrong in both directions at
once: too short and it misses, which is what happened — the almanac had not finished settling when
the window closed, so the guard passed and the test walked on into an assertion it had itself
decided might be unanswerable. Too long and every healthy run pays for a state it does not have.

**So the wait is a race, and deliberately not a symmetric one.** `reachAlmanac` now takes the element
the caller is about to tap and polls for it, in the shape `MapSearchUITests.wait(timeout:for:)`
already uses on screen 01. The row ending the wait the instant it appears is what makes a machine
with a fix pay nothing. The prompt does *not* end the wait early, and that asymmetry is the part
worth writing down: `showsLocationPrompt` is `coordinate == nil`, the coordinate arrives from
CoreLocation some time after screen 12 has already drawn, and the map tab is what starts the provider
at all — so "the prompt is on screen" is the state this screen **opens** in, fix or no fix. A race
that let the prompt win would have skipped both tests on a perfectly good machine, which is a worse
outcome than the failure it replaces: a suite where both tests skip forever has quietly deleted them.
The prompt is therefore not evidence of anything until the row has failed to arrive, and only then
does it decide which report is honest.

**And the report is a skip, not a failure.** `MapSearchUITests.requireAMapWithPins` had already
settled this for the same missing fix and named these two tests as the outstanding offenders: "a skip
says 'not checked here', which is true, where a failure says 'broken', which is not". The skip
carries the same literal command as its neighbours — `xcrun simctl location <udid> set
37.78485,-122.4215` — so the machine that hits it is told exactly how to make the tests run. The
helper throws rather than returning `Bool`, which is what `XCTSkip` requires and what removes the
`guard … else { return }` at both call sites; nothing else in the target called it.

**What did not change is what happens when the almanac really is broken.** If neither the row nor the
prompt is on screen, the screen is claiming a neighbourhood and missing a row of it — a defect, and
the helper deliberately reports nothing, leaving the caller's own assertion to name the row it
wanted. Both messages gained the clause `, which does have a neighbourhood`, because that is now
something the failure knows.

**Verified by breaking it.** [FILLED IN BELOW]
