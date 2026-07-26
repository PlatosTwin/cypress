### the almanac's two group-tap tests blamed the almanac for a fix that was never going to be there (#63)

`AlmanacGroupTapTests` failed with two sentences that were not true — `§4's CTA is not on the almanac`
and `R10's row is not on the almanac` — and it failed with them on every machine, including one with a
simulated fix over San Francisco. Two separate things were wrong, and only the first was the one that
had been noticed.

**The guard that could not fire.** Without a coordinate there is no neighbourhood (A4, ERRATA E44) and
`AlmanacScreen` draws E123's `See your neighbourhood` prompt **in place of** all four blocks, so both
counted rows are correctly absent. `reachAlmanac` knew that and carried the right message; it detected
the state with `app.staticTexts["See your neighbourhood"].waitForExistence(timeout: 3)`. A fixed wait
on an *absence* is wrong in both directions at once — too short and it misses, which is what happened,
so the guard passed and the test walked into an assertion it had itself decided might be unanswerable;
too long and every healthy run pays for a state it does not have.

**So the wait is a race, and deliberately not a symmetric one.** `reachAlmanac` now takes the element
its caller is about to tap and polls for it, in the shape `MapSearchUITests.wait(timeout:for:)` already
uses on screen 01. The row ends the wait the instant it appears, so a run that is going to pass pays
nothing. The prompt does not end it early — it is a state screen 12 passes *through* — and only once
the row has failed to arrive does the prompt decide which report is honest. The report is then a skip
rather than a failure, which `MapSearchUITests.requireAMapWithPins` had already settled for the same
missing fix and in the same words: "a skip says 'not checked here', which is true, where a failure says
'broken', which is not". It carries the same literal command its neighbours do, `xcrun simctl location
<udid> set 37.78485,-122.4215`. The helper throws rather than returning `Bool`, which is what `XCTSkip`
needs and what removes the `guard … else { return }` at both call sites; nothing else called it.

**And then the tests still failed, with a fix, on a screen that was showing neither thing.** This is
the half that had not been noticed, and it is worth stating plainly: on the entrance these tests used,
`CYPRESS_SCREEN=journal`, they could never have passed. `AlmanacView` builds its `@State` model from
the coordinate it is handed and keeps it — E123 recorded that as a known limitation, phrased as "the
content appears on the next visit to the tab" — and the deep link puts screen 12 on the glass inside
the first frames of launch, before the ask has been answered and long before CoreLocation has published
anything. The model reads `almanac(near: nil)`, which is `.empty` by contract, and stays there. A
second later the fix does arrive, `showsLocationPrompt` (which is `coordinate == nil`, recomputed on
every pass) flips to false, and the prompt is withdrawn from a screen that has nothing to replace it
with. What is left is a header with no pill, the footnote, and eleven hundred points of nothing.

**That state is a defect in the app, not in the test, and it is left standing.** It is precisely what
ERRATA E126 built the failure sentence for — "a screen that draws its five blocks away and leaves a
footnote is reporting a quiet neighbourhood" — and it slips past both guards, because the read did not
fail and the coordinate is no longer nil. E123's own note is too kind to it: the prompt is *not* honest
either way, because by then the prompt is gone. The fix belongs with `AlmanacModel` — reload when the
coordinate it was built without turns up — and it is a product change with its own tests, not a line to
be smuggled into a test repair.

**What the tests do instead is use the app's own front door.** They launch on screen 01, which is the
one screen that asks for location on the shipping path (`MapHomeView.task` is the only caller of
`start()`), wait until the map has drawn individual pins, and then press `Journal` and `Neighborhood`.
Screen 12 is built at that press, from a coordinate that exists. This is not the test navigating around
the blank screen — it is the sequence in which the app is actually used, and the skip lands in a better
place for it: the map is the surface that knows whether there is a fix, and screen 12 is the one that
cannot be asked, since a neighbourhood with nothing in it and a screen that could not be told where it
is look identical on it.

**The obvious better witness was tried first and does not work, which is a finding of its own.**
`MapRecentreCopy.value` says `Centred on you` only by way of `camera.isCentred(on: coordinate)`, so it
cannot be true without a coordinate — an exact statement of the thing being waited for, in the app's
own words, with no basemap involved. Measured on a simulator with a fix set over Van Ness, the control
reads `Not centred` for the whole of a 39-second run, and a screenshot of that same launch shows the
camera sitting on the fix with the reader's blue dot in the middle of the screen. The control is
describing a camera that is not the one on screen. It belongs to screen 01, it is not this task's, and
it is filed rather than fixed here — but it means the recentre control's `accessibilityValue` is
telling a VoiceOver reader the map is not on them while it is, and `MapRecentreUITests` cannot catch it
because it only asserts the value is non-empty.

**The other candidate turns out not to mean what the codebase thinks it means either.**
`MapSearchUITests.requireAMapWithPins` treats "the map drew individual pins" as "there is a fix", on
the reasoning that a fixless map opens on the whole city at a clustered zoom. It does not: screen 01
opens at `MapLayout.defaultSpanMetres`, 120 m across, whether or not there is a fix — only the centre
differs — and measured with location revoked outright for the app, the map opens on Dolores Park and
draws pins there anyway. That skip cannot fire. It is harmless where it sits (those two tests then run
and pass), but it is not a fix detector and it is not used as one here. What the pin wait does in this
file is hold the test on the map until the map has finished its first read, which is the difference
between pressing `Journal` before CoreLocation has answered and pressing it after; the only skip is
the one screen 12 itself justifies, and it is the prompt that decides it.

**Verified by breaking it, in both directions.** With `xcrun simctl location … set 37.78485,-122.4215`
both tests pass and tap through to the group screens they were written for (Western Addition: `Walk the
two` → `Where eyes are needed`, `187 empty planting sites` → `Where a tree could go`). With the fix
cleared, both skip, and the skip names the command that undoes it. The row assertions were then made to
fail on purpose, with a fix set, by looking for a row the almanac does not draw — they report the row,
at the caller, as they did before. The blank-almanac state was photographed rather than deduced: the
app was installed and launched with `CYPRESS_SCREEN=journal` and screenshotted, showing `Almanac`, no
pill, no prompt, no blocks; one press to `Map` and back to `Journal` filled it.
