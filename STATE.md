# STATE — w4-ax5, tickets #171/#172 (branch p1/ax5-fixes)

Written for a successor agent. Worktree: /Users/nikitabogdanov/PycharmProjects/cypress-w4ax5,
simulator iPhone 16e `3A1F212D-8F3A-41F1-AF72-EC95E155A4C9`, private DerivedData
`<scratchpad>/dd-w4ax5/`. Scratchpad root:
`/private/tmp/claude-501/-Users-nikitabogdanov-PycharmProjects-cypress/0d7c1eed-65e3-4ed3-b24f-b64dc9fb8b1c/scratchpad`

DELETE THIS FILE before the branch is handed to the orchestrator.

## Evidence so far

- **Before-renders (pre-fix, tree at 7634648 = main):** `<scratchpad>/shots-before/` — 235 PNGs,
  all mtime 2026-08-02 02:08, produced by ScreenSweepShots on the 16e (log:
  `<scratchpad>/dd-w4ax5/sweep-before.log`, `Test run with 4 tests in 1 suite passed`).
  NOTE: shot-dir env var passed as an xcodebuild ARG does NOT reach the runner — the PNGs landed
  in the app container tmp and were copied out. To redirect properly, `export
  TEST_RUNNER_CYPRESS_SHOT_DIR=...` in the shell BEFORE calling Tools/run_tests.sh.
- **After-renders:** NOT YET PRODUCED. Next step below.

## Per-defect verdicts (E196 numbering)

1. **02 identify overflow — REAL, FIXED.** Cause: `VisitAmberStatusChip` was `.fixedSize()` both
   axes. Fix in `VisitIdentifyView.swift` (wrap + AX corner shape per Chip.chipShape).
   Before: `shots-before/02-identify-light-ax5.png`.
2. **e02 denied notice truncation — REAL, FIXED.** `VisitIdentifyNotice` now
   ViewThatFits(vertical): centered where it fits, ScrollView at AX5.
   Before: `shots-before/e02-identify-denied-light-ax5.png`.
3. **11 growth history overflow — REAL, FIXED.** Cause: log rows (intrinsic-width MethodBadge +
   date). Fix: ViewThatFits row→stack in `GrowthHistoryView.logRow`.
   Before: `shots-before/11-growth-history-light-ax5.png`.
4. **19 memorial name collapse — REAL, FIXED.** `MemorialView.identity` now ViewThatFits: name
   beside badge only when the whole name fits. Before: `shots-before/19-memorial-light-ax5.png`,
   `e19-memorial-bare-light-ax5.png`.
5. **10 share captions — REAL BUT CHANGED SHAPE (post-#146: three destinations now), FIXED.**
   Still fragmented pre-fix ("Message / s"). Fix in `ShareView`: one destination per row at AX,
   circle beside caption. The share-card URL keeps its 2-line cap + ellipsis — deliberate,
   documented at `ShareMetrics.urlLineLimit`; left as-is, flagged for the orchestrator.
   OVERLAP WARNING: w4-sheet-exit is modifying BottomSheet.swift and may touch ShareView.
   My ShareView diff is confined to destinationRow/targetLabel/well.
   Before: `shots-before/10-share-light-ax5.png`.
6. **15 account CTA ellipsis — REAL, FIXED.** Cause: vertical compression in the content-sized
   `.account` sheet. Fix: `.fixedSize(h:false,v:true)` on `AccountProviderButton`'s label.
   (Whole-sheet overflow at AX5 remains — that is #173's CTA-reachability territory, NOT ours.)
   Before: `shots-before/15-account-ask-light-ax5.png`.
7. **07 species chips mid-word split — REAL, FIXED.** `SpeciesView.taxonomyChips` ViewThatFits
   row→column. Before: `shots-before/07-species-light-ax5.png`.
8. **City-record grid + C8 quad row — REAL, FIXED.** `StatGrid` is 1 column at AX sizes
   (`StatGrid.columnCount`), `QuadActionRow` is 2×2 at AX (`QuadActionRow.rows`), labels
   un-ellipsized at AX. Before: `shots-before/c06-city-record-full-ramp-light-ax5.png`.
9. **Minors:** 18 subtitle flush right — REAL, FIXED (`VisitSavedView.subtitle` now has
   gutterSheet padding). 09 placeholder ellipsis — **STALE, SKIPPED**: screen 09 was rebuilt by
   #168/#147 (the well is now a wrapping caption over ContributionExtras); the before render
   shows the caption wrapping, no ellipsis (`shots-before/09-care-log-light-ax5.png`).

## Tests

`CypressTests/AX5ReflowTests.swift` — 7 guards, house sizeThatFits pattern + decision-as-value.
- GREEN on fixed tree: `VERIFY-OK: Test run with 7 tests in 1 suite passed after 1.102 seconds`
  (log `<scratchpad>/dd-w4ax5/ax5-green.log`).
- RED proven on mutant tree (pre-fix views restored + decision values flipped): 6 of 7 failed,
  log `<scratchpad>/dd-w4ax5/ax5-red.log`.
- **KNOWN GAP:** "screen 11 stays inside the phone's width" did NOT go red under the revert — a
  vertical ScrollView clamps its reported width, so sizeThatFits cannot see the log-row overflow.
  That test is currently a cannot-fail test and MUST be deleted or replaced (render evidence
  covers 11). THIS IS THE FIRST PENDING EDIT.

## Remaining steps, in order

1. Delete (or honestly replace) the screen-11 width test in AX5ReflowTests.swift; re-run suite
   (`-only-testing:CypressTests/AX5ReflowTests`), expect 6 green.
2. Full unit suite WITH after-renders in one run:
   `export TEST_RUNNER_CYPRESS_SHOT_DIR=<scratchpad>/shots-after` then
   `Tools/run_tests.sh 3A1F212D-8F3A-41F1-AF72-EC95E155A4C9 <scratchpad>/dd-w4ax5/full-unit.log
   -derivedDataPath <scratchpad>/dd-w4ax5 -only-testing:CypressTests`
   Judge ONLY by verify_test_log.sh (VERIFY-OK).
3. LOOK at after renders for every state named above (02, e02-denied, 11, 19, e19-bare, 10, 15,
   07/e07, c01–c06, 14, 03, 18) — confirm defects gone AND no new AX5 or drawn-size regressions
   (esp. 03/14 profile: StatGrid + quad row changed; 19 stats; 07 chips; sweep blank-guard).
4. UI suites touched: `-only-testing:CypressUITests/SheetHeightUITests
   -only-testing:CypressUITests/DeepLinkVoiceOverTests -only-testing:CypressUITests/AccessibilityTreeTests`
   (Share/growth/memorial deep links + labels).
5. Errata UNNUMBERED to `docs/errata-pending/ax5-fixes.md`: per-defect fixed/stale table, the
   render paths + regeneration instructions, the URL-cap judgment call, the screen-11 test gap,
   VERIFY-OK lines. Commit.
6. Report: per-defect verdict, test names, VERIFY-OK lines, branch + final commit. Flag the
   ShareView overlap with w4-sheet-exit.

## Rules that already bit this session

- Termination killed a run mid-flight once already; its log claimed success but shots were in
  the container dir (see Evidence). Check artifact mtimes + provenance before trusting.
- `git checkout <rev> -- file` STAGES the old version; restore with
  `git restore --source=HEAD --staged --worktree <file>` after mutant runs.
- Swift Testing `#expect` second arg is a `Comment` — no `+`-concatenated strings.
