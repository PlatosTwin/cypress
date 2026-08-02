# The AX5 reflow defects: 02/11 overflow, 19/10/15/07/grid fragmentation (#171, #172)

**UNNUMBERED — orchestrator splices under the real next number at merge.**

## The defects (E196 inventory)

At accessibility text size 5 (AX5), several screens either drew wider than the phone (clipped at
both edges) or truncated their own copy with an ellipsis, mid-word split, or vertical collapse.
Verified against the pre-fix tree (`main` @ 7634648) with 235 before-renders in
`<scratchpad>/shots-before/`, and against the fixed tree (branch `p1/ax5-fixes` @ b4f92c3, the
last fix commit before this verification pass) with 319 after-renders in
`<scratchpad>/shots-after/`.

| # | Screen | Cause | Fix | Verdict |
|---|--------|-------|-----|---------|
| 1 | 02 identify (populated shortlist) | `VisitAmberStatusChip` was `.fixedSize()` both axes, forcing the row (and the whole screen) wide | Chip wraps; AX corner shape follows `Chip.chipShape` | **FIXED** — before/after render diff confirms |
| 2 | e02 identify, denied notice | Compressed `Text` truncated its own sentence with an ellipsis | `VisitIdentifyNotice`: `ViewThatFits(.vertical)` — centered layout where it fits, `ScrollView` where it does not | **FIXED** — before showed a permanent ellipsis; after shows the full sentence, reachable by scroll (the static top-of-scroll capture shows the tail clipped at the `ScrollView`'s own frame boundary, not overlapped by the footer button — confirmed by pixel-level crop and by `VStack(spacing: 0)` sibling layout in `VisitIdentifyView.body`, not a `ZStack`) |
| 3 | 11 growth history | Log rows (intrinsic-width `MethodBadge` + date) forced the row, and the screen, wide | `GrowthHistoryView.logRow`: `ViewThatFits(.horizontal)` — one row where value+badge+date fit, a stacked `VStack` where they do not | **FIXED**, with a verification gap — see below |
| 4 | 19 memorial name / e19 bare | Name collapsed beside the status badge (`Juda` for `Judah Street`) | `MemorialView.identity`: `ViewThatFits` — name beside badge only when the whole name fits, else stacked | **FIXED** — before/after render diff confirms |
| 5 | 10 share captions | Destination captions fragmented (`Message` / `s`) — shape changed post-#146 (three destinations now, not two) | `ShareView`: one destination per row at AX, circle beside caption | **FIXED** — before/after render diff confirms. Share-card URL keeps its existing 2-line cap + ellipsis (`ShareMetrics.urlLineLimit`) — left as-is, a **judgment call flagged for the orchestrator**, not a defect: the full URL is always reachable via Copy Link/system share, and no mock shows an uncapped card. |
| 6 | 15 account CTA | `AccountProviderButton`'s label vertically compressed inside the content-sized `.account` sheet, truncating `Continue with Google` to `Continue with Goo…` | `.fixedSize(horizontal: false, vertical: true)` on the label | **FIXED** — before/after render diff confirms. Whole-sheet overflow at AX5 remains out of scope — that is #173's CTA-reachability territory. |
| 7 | 07 species chips / e07 | `SpeciesView.taxonomyChips` split chip text mid-word (`Cupressac` / `eae`) | `ViewThatFits`: row of chips falls back to a column | **FIXED** — before/after render diff confirms |
| 8 | City-record grid + quad row (c01–c06, and shared by 03/14/14b) | `StatGrid` 2-column and `QuadActionRow` 1-row-of-4 both forced ellipsis/word-mangled wraps at AX | `StatGrid.columnCount` = 1 column at AX; `QuadActionRow.rows` = 2×2 at AX; both reflow decisions are values, per the `QuadActionRow.appearance` precedent | **FIXED** — before/after render diff confirms on c01, c02, c06; spot-checked clean on 03, 14, c03–c05, e146-4 |
| 9a | 18 next-tree subtitle | Subtitle text drawn flush to the screen edges (no gutter) | `VisitSavedView.subtitle` now carries gutter padding | **FIXED** — before/after render diff confirms |
| 9b | 09 care log placeholder ellipsis | Reported defect — screen 09 was rebuilt by #168/#147 before this ticket started; the well is now a wrapping caption over `ContributionExtras`, not the placeholder that used to ellipsize | **STALE — no code change made.** Before-render (`09-care-log-light-ax5.png`) already shows the caption wrapping cleanly, no ellipsis present pre-fix. |

## Verification gap: #3 (growth history log rows)

The log-row fix (`GrowthHistoryView.logRow`, `ViewThatFits(.horizontal)`) is the one item in this
table **not** independently confirmed by a scrolled AX5 screenshot. `ScreenSweepShots.capture`
renders each screen at a fixed phone-height viewport and does not scroll — its own doc comment
says so ("a screen whose subject is below the fold — a `ScrollView` rendered off-screen cannot be
scrolled"). The `11-growth-history-*-ax5` renders show only the chart (the top of the scroll); the
log rows this fix actually touches sit further down and are not captured by any named shot.

What stands in place of a render:

- Code review: `logRow`'s `ViewThatFits(in: .horizontal)` between a single `HStack` and a stacked
  `VStack` is the same shape as `StatCard.cityRecordValue` (item 8 above), which *is*
  render-verified on c01/c02/c06.
- The original `AX5ReflowTests` guard for this ("screen 11 stays inside the phone's width") was
  proven **unable to fail** against the pre-fix layout — a vertical `ScrollView` clamps the width
  it reports to the width it is proposed, so `sizeThatFits` never saw the overflow. That test was
  deleted in b4f92c3 rather than left as false assurance; see
  `CypressTests/AX5ReflowTests.swift`'s comment block above `identifyFitsThePhoneWidthAtAX5` for
  the full reasoning.

Net: the fix is structurally sound and follows a proven pattern, but nobody has looked at the
scrolled log rows on AX5 with their own eyes. A follow-up that either scrolls
`ScreenSweepShots.capture` for screen 11 specifically, or adds a targeted `sizeThatFits` probe on
`logRow` in isolation (the same technique `AX5ReflowTests.amberStatusPillWrapsAtAX5` uses for the
amber pill), would close this.

## Tests

`CypressTests/AX5ReflowTests.swift` — 6 guards after deleting the cannot-fail screen-11 width
test (b4f92c3):

- **Re-run, this session:** `VERIFY-OK: ✔ Test run with 6 tests in 1 suite passed after 1.011
  seconds` (`<scratchpad>/dd-w4ax5/ax5-rerun.log`).
- Green-before-deletion and red-under-mutant-revert logs from the predecessor session:
  `<scratchpad>/dd-w4ax5/ax5-green.log`, `<scratchpad>/dd-w4ax5/ax5-red.log`.

Full unit suite, this session, with after-renders produced in the same run
(`TEST_RUNNER_CYPRESS_SHOT_DIR` exported before `Tools/run_tests.sh`, per the trap noted below):

- **`VERIFY-OK: ✔ Test run with 1011 tests in 96 suites passed after 116.140 seconds`**
  (`<scratchpad>/dd-w4ax5/full-unit.log`).
- 319 PNGs landed in `<scratchpad>/shots-after/`, all at mtimes 10:24–10:26 (matching the log's
  10:26 mtime) — checked for stale/fossil files before trusting them; none found.

UI suites (`SheetHeightUITests`, `DeepLinkVoiceOverTests`, `AccessibilityTreeTests` — the ones
touching Share/growth/memorial deep links and labels), this session:

- **`VERIFY-OK: Executed 34 tests, with 0 failures (0 unexpected) in 298.701 (298.762) seconds`**
  — `** TEST SUCCEEDED **` present, nonzero executed count (3 + 28 + 3 = 34 across the three
  suites) confirmed directly against `<scratchpad>/dd-w4ax5/ui-suites.log`.

## Regeneration

```
export TEST_RUNNER_CYPRESS_SHOT_DIR=<scratchpad>/shots-after
Tools/run_tests.sh 3A1F212D-8F3A-41F1-AF72-EC95E155A4C9 <scratchpad>/dd-w4ax5/full-unit.log \
  -derivedDataPath <scratchpad>/dd-w4ax5 -only-testing:CypressTests
```

The env var must be `export`ed in the calling shell before `Tools/run_tests.sh` runs — passing it
as an `xcodebuild` argument does not reach the test runner process (it lands in the app
container's own tmp dir instead; the predecessor session hit this once and had to copy shots out
by hand).

## Flagged for the orchestrator

1. **ShareView overlap with `w4-sheet-exit`.** That branch is modifying `BottomSheet.swift` and
   may touch `ShareView`. This branch's `ShareView` diff is confined to
   `destinationRow`/`targetLabel`/`well` — worth a compile-and-fix pass at merge regardless.
2. **The share-card URL 2-line cap** (`ShareMetrics.urlLineLimit`) is a deliberate judgment call,
   not a defect — see item 5 in the table above. Flagging in case product wants a different
   answer for very long URLs.
3. **The #3 verification gap above** — log-row fix is code-review-verified only, not
   render-verified, because of a real limitation in the sweep harness (not something this branch
   introduced).
