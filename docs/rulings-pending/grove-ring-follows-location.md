# The Grove ring follows the reader's location (F38)

**Owner decision 2026-11-12: the ring follows the reader's location (constraint-21 exception);
strings drafted for ratification.** ROADMAP item 99. Implemented on
`feat/f38-grove-ring-location`.

## The report

A tester in Washington, D.C. opened My Grove > Species (screen 08) and read "you can recognize in
the Castro/Upper Market". `LocalAPI.groveSpecies` never read location. It drew the ring around A4's
inferred resident neighborhood (the most-visited one) and the caption presented that as plain fact.
F17 (PR #132) fixed the same complaint on the Journal's stats and did not reach screen 08.

## The rule

`GroveModel` asks the shared `MapLocationProvider` for the reader's fix at each read. It applies
the Almanac's rule for `.here`: a fix is usable only when
`AlmanacLimits.fixCanResolveAnArea(accuracyM:withinM: neighborhoodResolutionRadiusM)` holds
(400 m). The area then resolves in three states, in R29's order:

1. **A usable fix inside a polygon.** The ring is that neighborhood. The caption keeps the mock's
   words, because the named place is where the reader is.
2. **A usable fix where no polygon exists** (all of Washington, D.C. today; ROADMAP chip 88). The
   ring is R29's 1,200 m radius around the reader, if that circle holds any record. If it holds
   none, there is no ring and the screen says so (R29: "where the area holds no record, say so").
3. **No usable fix** (location denied, not asked, no fix yet, or a fix coarser than 400 m). The ring
   is A4's most-visited inference, unchanged: the most-visited polygon, else a radius around the
   most-visited tree. The caption says "most-visited", so it is never read as the reader's
   location.

The background merge (`RoutedAPI.refreshedGroveSpecies(near:)`) is read with the same fix, so it
cannot repaint the ring about a different area.

## Strings for ratification

| State | Caption under the ring |
| --- | --- |
| Fix, polygon | `you can recognize in the ‹neighborhood›` (unchanged, the mock's words) |
| Fix, no polygon, record nearby | `you can recognize within a 15-minute walk of where you are` (new) |
| Fix, no record nearby | no ring; in its place: `No city tree inventory on this phone covers where you are yet.` (new) |
| No fix, polygon | `you can recognize in the ‹neighborhood›, your most-visited neighborhood` (new; was the unlabeled first row) |
| No fix, no polygon | `you can recognize within a 15-minute walk of your most-visited tree` (unchanged) |

The no-record sentence takes the caption's font, color and the ring block's padding. It draws only
when the reader has met at least one species; an empty grove keeps its own sentence (E48).

## What stays unbuilt

- A4's "overridable in settings" resident neighborhood stays unbuilt.
- F17's area picker (`AreaPickerSheet`) is not added to screen 08.
- The model reads the fix when the tab loads (every visit to the tab). It does not follow a fix
  that arrives while the tab is already open; the next visit picks it up.
