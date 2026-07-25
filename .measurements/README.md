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
