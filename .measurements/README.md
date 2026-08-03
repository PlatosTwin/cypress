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
- Location permission declined both times, so the camera opens at the fixed fallback center (Mission
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
second at 4 m/s is one fix every fifteen centimeters, which no GNSS receiver produces; a phone
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

---

# The species search, before and after it stopped matching prefixes only (task #108)

`species-search-108.txt`. The map's search bar matched a **prefix** of `scientific_name` or
`common_name`, so "cypress" matched exactly one of the seed's 577 species — `Cypress species /
Cupressus spp` — and missed Monterey, Italian, Leyland, Hinoki and Montezuma Cypress. The
replacement matches a substring of either name and ranks head matches above word matches above
matches inside a word.

The reason this needed measuring at all is the standing objection to a leading `%`: it forfeits the
index. Here it forfeits nothing, and the plan is why.

## How it was taken

- iPhone 16 Pro Max simulator (`DE8E11AE-…`), Debug build, the shipped 77 MB seed attached
  read-only (145,837 trees, 577 species).
- A throwaway `@Suite` in `CypressTests`, run through `xcodebuild test`, deleted afterwards. Both
  statements run on the same connection, in the same process, back to back, 200 iterations each,
  after a warm-up pass over every query so neither pays a cold page cache or a statement compile.
- Two numbers per query: the **whole read** (`fetchAll` + `Species` decoding — what
  `LocalAPI.searchSpecies` actually pays) and **SQL only** (every row stepped, nothing decoded —
  the part the index plan governs).

## The plans, which are the point

| | before | after |
|---|---|---|
| scientific name | `SCAN … USING COVERING INDEX idx_species_scientific_name` | *the same* |
| common name | `SCAN … USING COVERING INDEX idx_species_common_name` | *the same* |
| the matched rows | `SEARCH s USING INTEGER PRIMARY KEY (rowid=?)` | *the same* |

**The range scan was never seeking.** `COLLATE NOCASE` on the comparison does not match the `BINARY`
collation the seed's two name indexes were built with, so SQLite could not turn `name >= :q AND name
< :q || U+FFFF` into a range `SEARCH` and walked the whole index anyway. So there was no seek for a
leading wildcard to forfeit: the after plan is the same two covering walks with a different predicate
evaluated on each row, plus a `GROUP BY` to take a species' better rank when both names match.

## The numbers

| query | rows before | rows after | whole read before | whole read after | SQL only before | SQL only after |
|---|---|---|---|---|---|---|
| `c` | 100 | 100 | 14.950 ms | 15.308 ms | 0.254 ms | 0.699 ms |
| `cy` | 3 | 10 | 0.541 ms | 1.675 ms | 0.086 ms | 0.149 ms |
| `cyp` | 1 | 8 | 0.244 ms | 1.357 ms | 0.084 ms | 0.150 ms |
| `cypress` | 1 | 6 | 0.240 ms | **1.069 ms** | 0.083 ms | 0.140 ms |
| `oak` | 1 | 21 | 0.226 ms | 3.282 ms | 0.079 ms | 0.177 ms |
| `quercus` | 17 | 17 | 2.600 ms | 2.665 ms | 0.091 ms | 0.134 ms |
| `a` | 97 | 100 | 14.335 ms | 15.486 ms | 0.204 ms | **0.825 ms** |
| `platanus` | 10 | 11 | 1.567 ms | 1.832 ms | 0.088 ms | 0.153 ms |

## What it says

**The SQL cost roughly doubles and stays under a millisecond.** 0.08–0.25 ms becomes 0.13–0.83 ms
over the same 577-row covering walk; the extra is four `LIKE` evaluations per row where there were
two comparisons. The worst case is the one-letter query, which is also the one nobody means.

**The whole read is dominated by decoding, not by matching, and it always was.** `species` carries
four JSON columns, and decoding costs about 0.15 ms a row. Where the two queries return the same
rows they cost the same — `quercus` 2.600 → 2.665 ms, `c` 14.950 → 15.308 ms. Where the after column
is larger it is because the search **found more**: `oak` goes from one species to twenty-one, and
3.3 ms is the price of the twenty extra Oaks it was supposed to have been finding all along.

**Nothing here is on a frame budget.** This runs off the main actor behind
`MapModel.searchDebounce`'s 300 ms, and the one number a person could feel — the 15 ms single-letter
read — is unchanged, because it was already returning a full page of 100.

## What it is not

A device measurement, for the same reason every other file here is not: a simulator runs the main
thread on a desktop core and reads the seed through the Mac's page cache. What transfers is the
*plan*, which is the database's and not the machine's, and the *ratio* between two statements timed
in the same process.
