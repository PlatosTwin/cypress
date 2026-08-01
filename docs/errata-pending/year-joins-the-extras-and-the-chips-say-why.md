# Year moves behind the expandable control, and the impossible chips carry their reasons (tasks #145, #136)

**Unnumbered — pending. The orchestrator assigns the E number at merge.**

## #145 — the row is the owner's three

Owner directive: the visible row is `Yours · In bloom · Needs care`; `Year` joins `Favorites` in
the expandable control. This supersedes R23.1's drawn row (`Yours · In bloom · Needs care · Year ▾
· More filters`) the way R23.1 superseded R23 §1's — the substance R23.1 argued is untouched and
now covers one more narrowing:

- `MapExtraFilter` grew a `year` case. The guard channels (`MapFilter.activeExtras` → collapsed
  count, fill, spoken value) reach it through the same single expression, so a decade set behind a
  shut control announces itself: `Collapsed, on: Year: 2010s`. The case's `label(in:)` carries the
  decade because the spoken value is the only channel a listener has while the drawer is shut.
- The drawer stopped assuming its contents are toggles: `year` is a value chosen from a menu, so
  the uniform `toggle(in:)` is gone; each case declares `isOn`/`label(in:)` and the drawer switch
  says which control draws it. `MapFilterCopy.moreValue` now takes names, not cases.
- The year chip's own contract (Menu, `Any year` value, decade label, E175 caveat) moved intact.

## #136 — R31 implemented, with one honest addition

The condition chips render disabled with the reason on the chip's surface (drawn under the label,
spoken as the chip's `accessibilityValue`), never spending a tap on the E126 card; each enables
itself when matching data exists (`MapConditionAvailability`, read once per appearance). The final
copy, drafted per R31's delegation, in R23 §6's register (em dashes unspaced, §5.7):

- `In bloom`, calendars missing (R31's debt): *"Our bloom calendars are still being written—no
  tree can match this yet."*
- `In bloom`, calendars present but nothing blooms this month (the state the seed measurement
  added — see the companion pending entry on the refuted `{}` premise): *"Nothing on the map is in
  its bloom months right now—this comes back when something is."*
- `Needs care` (the invitation): *"No one has reported a struggling tree yet—yours could be the
  first."*

The disabled chip is a fixed-width control (`MapLayout.unavailableChipWidth`) because `FlowRow`
measures children unconstrained and a sentence-bearing chip would otherwise hang off the phone —
E183's M10 by construction.

## Test changes

- `MapFilterAccessibilityTests` rewritten to the new arrangement. The file lost its machine-stable
  map-emptier: `In bloom` cannot be tapped while disabled and is *enabled* most of the year, so
  the empty-state tests drive `Favorites` through the drawer and guard-skip (announced) on a
  device that has favorites. `Needs care` is the stable R31 witness — disabled on every machine.
- `MapSuggestionUITests.testTheChipsUnderTheListAreNotCoveredButReachable` watches `Yours` instead
  of `In bloom` for the same month-dependence reason.
- Unit: `MapConditionAvailabilityTests` (availability pins, injected-data flips, copy-fact tests
  under R30's rule), plus the `MapFilterTests` drawer tests updated. Mutations M-A (year label
  drops its decade) and M-B (availability ignores overrides) each produced a distinct red.
