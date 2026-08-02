# STATE — w4-sheet-exit, ticket #175 (for a successor agent)

Branch `p1/sheet-exit` in this worktree. All work below is COMMITTED. Simulator: iPhone 16
Pro `EA0AD796-3052-4EE5-A7A8-A1DE807A3653` (mine alone). Private DerivedData:
`<scratchpad>/dd-w4sheet/` where scratchpad =
`/private/tmp/claude-501/-Users-nikitabogdanov-PycharmProjects-cypress/0d7c1eed-65e3-4ed3-b24f-b64dc9fb8b1c/scratchpad`.

## Diagnosis (VERIFIED on the running app, taps injected on the 16 Pro sim)

- Scrim tap on 09/10 is wired and WORKS. The defect is reachability: a `.standard` sheet
  exposes only the 62pt status-bar strip of scrim, and the system status bar's hit region
  consumes ~the top 54pt. Taps at (201,30) and (60,45): swallowed by OS, never reach the app.
  Taps at (60,58) and (201,58): reach the scrim, sheet dismisses. So the only exit was an
  ~8pt invisible sliver. Verdict: UNREACHABLE control, not broken control.
- No drag gesture existed anywhere; the grabber was decoration.

## Implemented (committed, builds clean, zero warnings)

- `Cypress/DesignSystem/Components/BottomSheet.swift`: full-width drag-handle overlay band
  (top 62pt of card = grabber row + title line) on `.standard` when `onScrimTap != nil`;
  card follows finger (`dragOffset`), spring-back on `czSheet` via `CypressMotion.resolved`
  (Reduce Motion honored); dismissal calls the same `onScrimTap` closure. Card height
  captured via `.onGeometryChange`. File header documents exits under "Exits (ticket #175)".
- `Cypress/DesignSystem/Components/SheetDismissRule.swift` (new): pure threshold math —
  dismiss at translation >= 0.25*cardHeight, or predictedEndTranslation >= 0.5*cardHeight;
  upward/unmeasured never; `cardOffset` clamps at 0.
- `Cypress/DesignSystem/Tokens/CypressSpacing.swift`: `Component.sheetDragZone = 62`.
- Hosts untouched (component-only fix). Inventory: only 09/10 use `.standard`; 15 is
  `.account` (reachable scrim + buttons, no grabber — fine); check-in 05 is pushed with a
  back control — fine.

## Tests (committed; ALL FOUR WATCHED RED, breaks restored)

- `CypressTests/SheetDismissRuleTests.swift` (Swift Testing, 8 tests) — red-proofed by
  breaking the threshold guard (2 issues), restored.
- `CypressUITests/SheetExitUITests.swift` (XCTest, 4 tests): drag dismisses 09; drag
  dismisses 10; strip tap at y=58 dismisses 09; drag on 09's note field (focused, text
  typed) does NOT dismiss and note survives. Red-proofed respectively by: deleting the
  gesture (both drag tests red), unwiring the scrim tap (strip test red), leaking the handle
  band to full-card height (field test red). IMPORTANT lesson baked into the harness:
  dismissal must be asserted as the map FAB ("What tree is this?") becoming HITTABLE —
  `exists` is true under a fullScreenCover and the first version of the assertion was
  vacuous (caught by its own red-proof).

## Manual on-screen verification (done, watched live)

09 drag-down leaves; 10 drag-down leaves; short slow drag springs back to y=62; typing in
note field then dragging on it does not dismiss and card doesn't move; strip tap at y=58
dismisses.

## Docs (committed)

- `docs/rulings-pending/sheet-exits.md` (UNNUMBERED — orchestrator splices at merge).
- `docs/errata-pending/sheet-exit-trap.md` (UNNUMBERED).

## Remaining work (the ONLY remaining step)

Run the FULL suite (unit + UI) and judge with the verifier:
  `Tools/run_tests.sh EA0AD796-3052-4EE5-A7A8-A1DE807A3653 <scratchpad>/dd-w4sheet/full.log -derivedDataPath <scratchpad>/dd-w4sheet`
  then believe only `Tools/verify_test_log.sh` output: need Swift Testing
  "Test run with N tests passed" (N>0) AND XCTest "** TEST SUCCEEDED **" with nonzero
  executed count. Machine cap 3 xcodebuilds — check `ps aux | grep xcodebuild` first.
  Camera grant is handled by run_tests.sh. If the slowest test hits SQLITE_IOERR_VNODE,
  that is simulator contention, not this change.

Then report: diagnosis, ruling shape, test names, VERIFY-OK lines, branch + final commit.
Delete this STATE.md in the final commit once the suite is green.
