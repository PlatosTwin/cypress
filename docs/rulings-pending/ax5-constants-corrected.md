### `MapLayout.locateButtonHeightAX5` and `.fabHeightAX5` are corrected to the bare footprints ERRATA E243 measured (owner ruling, 2026-08-06, task #246)

**The owner ruled, 2026-08-06, verbatim: "correct them."**

ERRATA E243 (task #30) found that `MapLayout.locateButtonHeightAX5 = 98` and `.fabHeightAX5 = 137`
were never measurements of `MapRecenterButton` and `IdentifyFAB` — each was the control's real AX5
footprint (44 pt and 83 pt) plus the 54 pt top safe-area inset that `AX5ReflowTests.ax5Size`'s
measuring window inherited from whichever simulator it happened to run on. That entry fixed the
test harness (`ax5Size` now subtracts the inherited inset, making the measurement
device-independent) but left the two shipped constants untouched, on the reasoning that they feed
`bottomSlotReservedAboveAX5` → `MapLayout.noticeMaxHeight(availableHeight:)`, which
`MapLocationNotice`'s AX5 scroll budget documents itself as deliberately conservative rather than
exact (RULINGS R53 §6). E243 flagged, but declined to take, the ~108 pt of scroll budget the
over-reservation was costing the notice, calling correcting the constants downward "a decision for
the owner, not for a ticket about a red simulator."

**This ruling answers that open question, for these two constants specifically: correct them.**
This supersedes R53 §6's conservative stance *only* for `locateButtonHeightAX5` and `.fabHeightAX5`
— nothing else R53 §6 or E183 §2 established about the notice's scroll behavior, or about
`MapLocationNotice` scrolling rather than growing off the screen (RULINGS R65), changes.

**What changed** (`Cypress/Features/Map/MapKitBasemap.swift`):
- `locateButtonHeightAX5`: `98` → `CypressSpacing.minTapTarget` (`44`). `MapRecenterButton` is a
  fixed `minTapTarget` square and measures exactly that at `.accessibility5`, device-independently
  — asserted by `AX5ReflowTests.bottomChromeControlsFitTheReservedBudgetAtAX5`.
- `fabHeightAX5`: `137` → `83`, `IdentifyFAB`'s real AX5 footprint, measured through
  `AX5ReflowTests.ax5Size` after E243's fix to that helper, device-independently on both the
  iPhone 16 Pro and the iPhone 16e. Verified directly for this ruling by temporarily setting
  `fabHeightAX5` to `1` and reading the resulting `AX5ReflowTests` failure message:
  `(fab.height → 83.0) <= (MapLayout.fabHeightAX5 → 1.0)`.

`bottomSlotReservedAboveAX5` and `noticeMaxHeight(availableHeight:)` are unchanged in shape — they
still sum the same six terms — but now sum to a smaller number, so `MapLocationNotice` at AX5
renders taller before it must scroll, on every one of the five call sites that pass a budget
through `MapHomeView`.

**Comments corrected**, not merely the numbers: the doc comments on both constants used to explain
the 98 and 137 as (in one case) iOS growing the control's minimum hit target across the
accessibility range, and (in both) a deliberately-left margin over the real footprint. Neither
claim was true before this ruling and neither is repeated after it — the comments now say what
E243 measured and cite it, without naming any document that has not been numbered yet.

**Tests.** `AX5ReflowTests.bottomChromeControlsFitTheReservedBudgetAtAX5`'s two `<=` guards (kept
as `<=`, not tightened to `==`, so a control that grows past its reservation in the future still
fails loudly) and its exact `recenter.height == CypressSpacing.minTapTarget` check all pass
unmodified against the corrected constants — they were already written against the bare footprints,
not the old inflated numbers. Red-proofed by temporarily adding `.padding(.top, 10)` to
`IdentifyFAB`'s body (inflating its real AX5 footprint to 93 pt, past the corrected 83 pt
reservation) and rerunning: one issue, on the intended expectation —
`Expectation failed: (fab.height → 93.0) <= (MapLayout.fabHeightAX5 → 83.0)` — restored, green
again.

Full `CypressTests`: `Test run with 1256 tests in 124 suites passed`. Full `CypressUITests`, iPhone
16 Pro Max `DE8E11AE-4375-4C3B-A296-9B60A7DF1DB3`: `** TEST SUCCEEDED **`,
`Executed 92 tests, with 0 failures`, `XCTest skipped=0`. Warnings certified on a fresh
DerivedData build-for-testing (`Tools/verify_test_log.sh --warnings`): `SwiftCompile tasks=438`,
`source=0` warnings, `files-checked=2` (both changed files actually compiled).

**On the running screen**, AX5, `CYPRESS_LOCATION=denied` (screen 01's longest standing notice):
with the old constants the notice's visible body text ran seven lines before the card's bottom
edge; with the corrected constants the same notice, same device, same launch state, ran ten to
eleven lines before the same cutoff — more of the sentence readable without scrolling, which is the
108 pt of budget this ruling gives back. See
`docs/errata-pending/ax5-recenter-occluded-after-reservation-correction.md` for a discovered side
effect of the larger notice: in that same denied-location state, the recenter control (first in
`bottomChrome`'s stack, so pushed furthest by the taller notice below it) lost hittability,
occluded by the filter chip row above it — an existing, separately-documented overlap
(`MapHomeView.chrome`'s own comment on the top/bottom chrome blocks overlapping "at accessibility
sizes, where they already did") that this ruling's correction measurably worsened for this one
control, in this one state. That was not a defect in what this ruling asked for — the two constants
say what E243 measured, exactly, and are untouched by what follows.

**Task #250 fixed the reachability question, in the same PR, rather than leaving it for a separate
ticket as first planned.** `MapLayout.noticeMaxHeight` gained a second reservation
(`topChromeReservedAX5(topInset:)`) for the room the search bar and filter chip row need, so the
notice's AX5 budget stops short of where the recenter control would rise back into that chrome. The
two constants this ruling corrected (`locateButtonHeightAX5`, `.fabHeightAX5`) are unchanged by
that fix. See the errata entry above for the mechanism and the receipts.
