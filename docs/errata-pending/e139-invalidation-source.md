## E139's last open item was closed by E140, and four comments went on saying it was not (task #226)

**Task #226 was opened to find the source of the basemap's ~200 body evaluations a second at rest and
stop it. The measurement was taken first, and there is nothing left to stop.** E139's "What is
honestly still open" — "the basemap still re-evaluates its body around 200 times a second at rest
once a fix has arrived … so it is cheap, and it is still wrong. It is not fixed here." — describes a
state the app has not been in since E140. E139 guessed the residual and the unpannable map might
share a root cause. E140 confirmed they did and recorded the rate going to zero. Nobody went back and
amended E139, and four code comments still asserted the old rate in the present tense.

### What was measured, before anything was changed

`origin/release/0.2` at `1fb0e6a`, unmodified. iPhone 16e (`3A1F212D…`), location **granted** with a
fix set at `37.7599,-122.4148` — the condition E139 exists to insist on, since both of its
predecessors were measured with location declined. The instrument is E139's own: `MapFrameProbe`'s
`body` counter, incremented inside `MapKitBasemap.body`, printed once a second by the display link
under `CYPRESS_MAP_PROBE=1`.

**141 consecutive one-second windows, 87 markers at z18:**

| | at rest | during interaction |
|---|---|---|
| basemap body passes / second | **0** (135 of 141 windows) | 1–10 |
| frame rate | 60 fps | 58–60 fps |
| worst frame | 16.7 ms | 80.9 ms (launch) |
| gps publishes / second | 0 | 1 (the fix landing) |

Every one of the six windows that is not zero is an interaction: the launch (`body=10 gps=1
fetch=1`), a ten-point pan (`body=3` then `body=5`, `fetch=2` each, markers 87 → 88 → 75), a filter
chip (`body=1`), and a recenter press (`body=2 fetch=1`, markers back to 87). Before/after over a
fixed window is therefore **~200/sec → 0/sec**, and the "after" was already true at the base commit.

### The instrument was calibrated, and this is the part that matters

A counter reading zero because it is broken is indistinguishable from a counter reading zero because
the defect is gone, and this project has believed the wrong one of those before. The calibration is
in the same process and the same run as the measurement: **the same counter that reads 0 for 135
windows reads 10, 5, 3, 2 and 1 in the six windows where the map is doing something**, with `fetch`
and the marker count moving alongside it. It is alive, it is attached to the body it claims to
count, and its zero is a measurement.

`Self._printChanges()` was not needed and was not used. It answers "what invalidated this view", and
nothing is invalidating it.

### What is actually wrong: the prose

Four comments asserted the retired rate as present fact. Fixed in `MapKitBasemap`, `MapHomeView`,
`MapAnnotationLayer` (×2) and the three in `MapCameraOwnershipTests`. One of them was not merely
stale — **it was a safety argument that E140 quietly invalidated**:

> `MapAnnotationLayer.FirstLayoutMapView` justified its existence with "screen 01 re-runs its body 240
> times a second and would have produced another pass on its own, but the two other screens that draw
> this basemap are quiet".

Screen 01 is now exactly as quiet as the other two. The first-layout callback did not become more
correct, but it went from load-bearing on two screens to load-bearing on **all three**, and anyone
removing it on the reasoning written beside it would strand the app's default screen on MapKit's
whole-world default region (E168).

This is the same failure the standing rules already name — a confident comment is where bugs survive
here — with the twist that the comment was true when written. **A measured number in a comment is a
measurement with a date on it, and E140 was the date.**

### The guard, and what could not honestly be guarded

There is **no honest automated pin for the at-rest evaluation rate itself.** SwiftUI exposes no
public body-evaluation hook. The app has a counter, but it is `#if DEBUG`, armed only by an
environment variable, and `MapProbeOverlay` is deliberately `allowsHitTesting(false)` and
`accessibilityHidden(true)` — "an instrument must not be a participant in what it measures" — so a UI
test cannot read it without undoing that decision and disturbing the reading-order suite on the same
screen. A test asserting an at-rest rate was not written, because the only ways to write one are to
break the instrument or to fake it.

What *is* pinnable is the mechanism, and one load-bearing piece of it was untested.
`MapCameraRequest.opening(_:)` must not mint a ticket, because `VisitPinAdjustView` and
`PinSetMapView` both rebuild it inside a `Binding` getter on every pass — three separate comments say
so and nothing tested it. `opening(_:)` is three lines and reads like a convenience beside
`move(to:)`; collapsing the two is an inviting tidy-up whose cost is invisible at the call site.
`MapCameraOwnershipTests.rebuiltOpeningCameraNeverBecomesANewRequest` rebuilds the request 240 times
after a pan and asserts the camera does not move. **Red-proved** by giving `opening(_:)` a real
ticket: it fails at 550.6 m — the exact distance from the pan to the fix — while all four existing
tests in the suite stay green, because none of them ever rebuilds the request.

### One thing noticed and not chased

The probe's `markers` figure counts *fetched* content (`MapModel.content.markerCount`, set from
`.onChange(of: model.content)`), not drawn pins. The species/condition filters narrow pins downstream
without a re-fetch, so with "In bloom" active the overlay read `75 markers` over a map drawing one.
The `body` counter this report rests on is incremented inside the body itself and is unaffected.
