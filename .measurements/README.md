# Screen 01's frame times, before and after the level-of-detail rule (ERRATA E130)

Raw `MapFrameProbe` output from two runs of the **same scripted gesture** on the same simulator,
one against the branch point (`5eb445a`) and one against this branch. `e130-before.txt` and
`e130-after.txt` are those two runs with the uneventful `fps=60.0` windows stripped out, so what is
left is every window in which the map dropped a frame.

## How it was taken

- iPhone 16 Pro simulator (`EA0AD796-…`), Debug build, **60 Hz** display.
- `MapFrameProbe` — `CADisplayLink` on the main run loop, reporting one line per second: frame count,
  effective fps, p50 / p95 / worst frame interval, and the annotation count on screen. Armed only by
  `CYPRESS_MAP_PROBE=1`, `#if DEBUG`.
- Launched with `SIMCTL_CHILD_CYPRESS_MAP_PROBE=1 xcrun simctl launch --console-pty …`.
- Location permission declined both times, so the camera opens at the fixed fallback centre (Mission
  Dolores Park) and the two runs start from the same picture: zoom 18, 10 markers, a flat 60 fps.
- Gesture: one two-finger pinch, sixteen steps of 60 ms, separation 240 pt → 60 pt (two zoom levels
  out), followed by one 0.9 s drag from (310, 520) to (90, 260). Identical coordinates and timings in
  both runs.

## What it says

| window | before | after |
|---|---|---|
| idle, zoom 18, 10 markers | 60.0 fps, worst 16.7 ms | 60.0 fps, worst 16.7 ms |
| the pinch itself | 38.0 fps, worst 325.0 ms | 44.6 fps, worst 138.3 ms |
| settling at zoom 16 | **14.3 fps, worst 753.5 ms** | 59.3 fps, worst 28.4 ms |
| the second after that | **0.5 fps, worst 2,060.8 ms** | 60.0 fps |
| one drag at zoom 16 | **18.7 fps, worst 1,286.0 ms** | 57.0 fps, worst 54.2 ms |
| markers drawn at zoom 16 | **1,300** | 101 |

## What it is not

A simulator composites through a Mac GPU and runs the main thread on a desktop core. The *ratio*
between two runs of one gesture is worth something and the shape of it — a two-second frozen frame
becoming a 28 ms one — is not ambiguous. The absolute milliseconds are not a device measurement and
must not be quoted as one.

---

# Screen 01 with a location fix, before and after the MKMapView layer (the E130 follow-up)

The owner installed E130's result on their own iPhone and reported the map still slow. Everything
above was taken with **location permission declined**, which opens the camera over Mission Dolores
Park — a park, in a *street* tree inventory, with ten markers on screen. None of it was a
measurement of a full screen of pins, and none of it could have been: a static `simctl location`
fires `didUpdateLocations` once and never again.

## How these were taken

- iPhone 16e simulator (`3A1F212D-…`), Debug build, 60 Hz.
- `MapFrameProbe`, armed with `SIMCTL_CHILD_CYPRESS_MAP_PROBE=1`, now also drawn on screen by
  `MapProbeOverlay` and carrying three counters per window: `gps` (publishes of
  `MapLocationProvider.availability`), `body` (evaluations of the basemap) and `fetch` (completed
  viewport reads).
- **Location granted**, which is the difference from every previous round. Two conditions:
  - *idle* — one static fix, `simctl location set 37.77875,-122.42466`, camera settled, nobody
    touching the glass. The map ends up over Fulton St with 184–194 markers.
  - *walking* — `simctl location start --speed=4 --interval=0.2 37.77875,-122.42466
    37.77875,-122.41800`, a route through the Mission at 4 m/s.

| file | condition |
|---|---|
| `e139-idle-before.txt` | one fix, idle, SwiftUI `Annotation` layer |
| `e139-idle-after.txt` | one fix, idle, `MKMapView` layer |
| `e139-walking-before.txt` | walking route, SwiftUI `Annotation` layer |
| `e139-walking-after.txt` | walking route, `MKMapView` layer |
| `e139-control-location-declined.txt` | **the control**: permission declined, nine markers |
| `e139-ablation-no-gps-dot.txt` | idle, GPS-dot annotation removed |
| `e139-ablation-no-pulse.txt` | idle, the amber pin's `repeatForever` pulse disabled |
| `e139-idle-mkmapview-before-camera-fix.txt` | idle, `MKMapView` layer, camera loop still present |

## What they say

| window | before | after |
|---|---|---|
| idle, one fix, 184–194 markers | **1.2–1.8 fps, worst 873 ms** | 40–49 fps, worst 40–49 ms |
| walking, 145 markers | **1.3–1.9 fps, worst 852 ms** | 50–59 fps, worst 35–53 ms |
| `gps` publishes per second, walking | 24–42 | 1 |
| `body` passes per second, idle | 12–18 (of a layer that had not changed) | 199–242 (each now ~1 ms) |
| control: permission declined, 9 markers | 60.0 fps, `body` 0 | unchanged |

## The three ablations, and why they are here

Each was built, installed and run, and each was reverted. They are the reason the cause is stated as
the annotation count rather than as any of the more obvious suspects:

- **without the GPS dot annotation** — 1.5–1.8 fps. Unchanged.
- **without the amber pin's pulse** — 1.2–1.8 fps. Unchanged.
- **with location declined** (nine markers) — a flat 60 fps and zero body passes.

## What is still wrong, and is not fixed here

`body` is 199–242 a second in the "after" runs with `gps 0` and `fetch 0`: something above the map
still invalidates the whole view tree continuously whenever a location fix has been received.
`Self._printChanges()` names it `RootView: @self changed`, so the trigger is at or above the
composition root rather than in the map. It costs about a fifth of the frame budget now that a pass
is ~1 ms instead of ~77 ms, and it is the next thing to go after.

## What none of this is

Still a simulator. The *rate* of location callbacks in particular is a simulator artifact — 24–42 a
second at 4 m/s is one fix every fifteen centimetres, which no GNSS receiver produces; a phone
delivers about one a second. What transfers is the **per-publish cost** and the **mechanism**, not
the absolute frame numbers. The instrument for the absolute numbers is now the on-screen overlay, on
the owner's own phone.

## Proved compiled out of Release — `e139-compiled-out.txt`

The on-screen readout is `#if DEBUG` in both of its own files and at every call site, and off unless
`CYPRESS_MAP_PROBE=1` on top of that. Proved the way ERRATA E117 proved the same thing of
`DebugDeepLink`, including its trap: Xcode puts Debug app code in `Cypress.debug.dylib` beside a
small stub named `Cypress`, so grepping the Debug *stub* finds nothing and looks like a pass while
measuring the wrong file. The control strings are what catch that — they are absent from the stub
too, and present in both real artifacts.

| | Debug dylib | Debug stub | Release |
|---|---|---|---|
| `CYPRESS_MAP_PROBE` | 1 | 0 | **0** |
| `[probe]` | 2 | 0 | **0** |
| `MapProbeOverlay` symbols | 102 | 0 | **0** |
| `MapFrameProbe` symbols | 365 | 0 | **0** |
| *control* `What tree is this?` | 1 | 0 | 2 |
| *control* `MapAnnotationLayer` | 3 | 0 | 6 |
| *control* `MapLocationProvider` | 5 | 0 | 8 |

## How the owner turns the readout on

It needs the environment variable, which on a device means a scheme, not a command line: Xcode →
Product → Scheme → Edit Scheme → Run → Arguments → Environment Variables, add `CYPRESS_MAP_PROBE`
= `1`, then Run onto the phone. The map draws a small dark badge under the filter chips with rolling
fps, the worst frame in the last second, the marker count and zoom, and the three counters. The fps
line turns amber whenever the worst frame in that second missed the display's cadence.
