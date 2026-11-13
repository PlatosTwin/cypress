# The Grove ring follows the reader's location (F38)

**Owner decision 2026-11-12: the ring follows the reader's location (constraint-21 exception);
strings drafted for ratification.** **Owner ruling 2026-11-13** (through AskUserQuestion) settled
the fallbacks and the polygon wording, below. ROADMAP item 99, PR #207.

## The report

A tester in Washington, D.C. opened My Grove > Species (screen 08) and read "you can recognize in
the Castro/Upper Market". `LocalAPI.groveSpecies` never read location. It drew the ring around A4's
inferred resident neighborhood (the most-visited one) and the caption presented that as plain fact.
F17 (PR #132) fixed the same complaint on the Journal's stats and did not reach screen 08.

## The rule

`GroveModel` asks the shared `MapLocationProvider` for the reader's fix at each read. It applies
the Almanac's rule for `.here`: a fix is usable only when
`AlmanacLimits.fixCanResolveAnArea(accuracyM:withinM: neighborhoodResolutionRadiusM)` holds
(400 m). Then:

1. **A usable fix inside a polygon, where the reader has met at least one of its species.** The
   ring is that neighborhood. The caption keeps the mock's words (owner ruling 2026-11-13, (c)).
2. **A usable fix where no polygon exists** (all of Washington, D.C. today; ROADMAP chip 88), when
   R29's 1,200 m radius around the reader holds a record and the reader has met at least one of its
   species. The ring is that radius.
3. **Every other case falls back to the most-visited ring**, which is A4's inference unchanged (the
   most-visited polygon, else a radius around the most-visited tree), and its caption says
   "most-visited", so it is never read as the reader's location:
   - no usable fix (location denied, not asked, no fix yet, or a fix coarser than 400 m);
   - **(a)** a usable fix that no tree inventory on the phone covers (owner ruling 2026-11-13: do
     not show a "no inventory here" note; fall back instead);
   - **(b)** a usable fix in covered ground where the reader has met none of the area's species, so
     the ring would read zero (owner ruling 2026-11-13: fall back rather than draw an empty ring).
     The test is against this phone's species; the account's half, merged later, does not change
     the area.

The background merge (`RoutedAPI.refreshedGroveSpecies(near:)`) is read with the same fix, so it
cannot repaint the ring about a different area.

## Strings for ratification

| State | Caption under the ring |
| --- | --- |
| Fix, polygon | `you can recognize in the ‹neighborhood›` (unchanged, the mock's words; ruling (c)) |
| Fix, no polygon, record nearby | `you can recognize within a 15-minute walk of where you are` (new) |
| Most-visited fallback, polygon | `you can recognize in the ‹neighborhood›, your most-visited neighborhood` (new; was the unlabeled first row) |
| Most-visited fallback, no polygon | `you can recognize within a 15-minute walk of your most-visited tree` (unchanged) |

The draft of 2026-11-12 also proposed a sentence in place of the ring for case (a), `No city tree
inventory on this phone covers where you are yet.` Ruling (a) withdrew it; it was never shipped.

## What stays unbuilt

- A4's "overridable in settings" resident neighborhood stays unbuilt.
- F17's area picker (`AreaPickerSheet`) is not added to screen 08.
- The model reads the fix when the tab loads (every visit to the tab). It does not follow a fix
  that arrives while the tab is already open; the next visit picks it up.
