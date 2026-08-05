## E196's remaining AX5 punch list no longer reproduces — E199 already closed it; one verification gap of E199's own closed here (task #228), plus a hardened pan-precondition retry (task #230)

### Part A — #228

The brief for this round carried E196's "Defects found at AX5 (find, don't fix)" list — screen 02
overflow and denied-state truncation, screen 07 fact chips, screen 09 placeholder, screen 10 action
captions, screen 11 overflow, screen 18 mono subtitle, screen 19 name column, and the 03/14 §9b
two-column grid — as still-open work. It is not: **E199** (tasks #171, #172, merged) fixed every one
of those items already, on the base this branch started from (`origin/release/0.2`). E196 is a
point-in-time record and this round's premise had drifted; per the brief's own instruction, each item
was re-verified at AX5 rather than assumed, and none needed a production-code change.

**R53's `MapLocationNotice`-past-y=0 item was excluded, untouched, per the brief.**

#### Per-item verdicts, this session

Verified by re-running `CypressTests/AX5ReflowTests` (the 6 structural guards E199 built) and
`CypressTests/ScreenSweepShots` with `TEST_RUNNER_CYPRESS_SHOT_DIR` exported, then looking at the
renders — not trusting the green alone. Calibration: the same 10-test run (6 + 4) was run twice,
once before any change here and once after, both green, so the harness itself was exercised before
being trusted (the CLAUDE.md instrument-calibration rule).

| # | Item (E196) | Verdict | Evidence looked at |
|---|---|---|---|
| 1 | Screen 02 (identify, populated) overflow | **No longer reproduces** — E199 #1 | `02-identify-light-ax5.png`: title, status pill, callout, footer all inside the phone width |
| 2 | Screen 02 denied-state truncation | **No longer reproduces** — E199 #2 | `e02-identify-denied-light-ax5.png`: no ellipsis; the sentence is cut only by the sweep's non-scrolling static capture at the `ScrollView`'s own frame boundary, immediately above the footer CTA — confirmed structurally, `VisitIdentifyView.body` is `VStack(spacing: 0)` (header / statusChips / content / footer as siblings), not a `ZStack`, so the CTA cannot be overlapping the notice |
| 3 | Screen 07 fact chips | **No longer reproduces** — E199 #7 | `07-species-light-ax5.png`: "Cupressaceae" and "Evergreen" each in their own full-width row, no mid-word split |
| 4 | Screen 09 placeholder | **No longer reproduces — already stale at E199's own writing** | `09-care-log-light-ax5.png` + code read: `CareLogCopy.optionalWell` renders through a plain `Text` with no `lineLimit`, not a field placeholder — #168/#147 rebuilt this well before E199 started |
| 5 | Screen 10 action captions | **No longer reproduces** — E199 #5 | `10-share-light-ax5.png`: "Messages", "Copy link", "Share…" each intact, one destination per row |
| 6 | Screen 11 overflow | **No longer reproduces** — E199 #3, **and its own flagged verification gap closed here** | see below |
| 7 | Screen 18 mono subtitle | **No longer reproduces** — E199 #9a | `18-next-tree-light-ax5.png`: "1 of 4 on today's list" wraps with gutter padding, not flush to the glass edge |
| 8 | Screen 19 name column | **No longer reproduces** — E199 #4 | `19-memorial-light-ax5.png`: "Judah Street" renders on its own full-width line, not squeezed beside the badge |
| 9 | 03/14 §9b two-column grid | **No longer reproduces** — E199 #8 | `c06-city-record-full-ramp-light-ax5.png` (E196's own "representative" shot): `QuadActionRow` draws 2×2, `StatGrid` draws one column, "#221277", "Sidewalk: Curb side : Cutout", "DPW Maintained", "A private party", "Friends of the Urban Forest" all render whole; `AX5ReflowTests.statGridColumnCount` / `.quadActionRowRows` (shared component, used identically on 03 and 14) pass |

#### Screen 11's verification gap, closed

E199 fixed `GrowthHistoryView.logRow`'s overflow (`ViewThatFits(in: .horizontal)`) but flagged it as
**code-review-verified only**: `ScreenSweepShots.capture` rendered screen 11 at the default
phone-height AX5 viewport, and the log rows the fix touches sit below the fold in an unscrolled
`ScrollView` — nobody had looked at them. E199 named two ways to close this: scroll the capture for
screen 11 specifically, or add an isolated `sizeThatFits` probe on `logRow`.

The scroll route was taken, matching the technique `02b-add-tree` and `c06-city-record-full-ramp`
already use in the same file: `ScreenSweepShots.everyScreen`'s `"11-growth-history"` sweep now passes
`ax5ViewportHeight: Self.tallestViewport`, so the AX5 legs get a 2,700pt window instead of 852pt.
This is safe for screen 11 specifically because its `ScrollView` is *always* present regardless of
available height — unlike `VisitIdentifyNotice` (item 2 above), which switches structure
(`ViewThatFits`) based on the height it is offered, where inflating the capture window would change
which branch renders and stop testing the AX5-cramped case. That is why item 2 was verified a
different way (structural sibling-layout read) instead of the same viewport trick.

Looked at `11-growth-history-light-ax5.png` after: every log row's value+badge+date sits inside the
393pt phone width; rows too wide for one line stack value+badge over the date instead of clipping;
the chart's end values (`64`, `18`) and leading unit-label digits (`47 cm`, `14 m`) are intact,
matching E199's separately-confirmed chart fix. `CypressTests/AX5ReflowTests` (6/6) and
`CypressTests/ScreenSweepShots` (4/4) both green after the change —
`<scratchpad>/ax5-baseline.log` (before), `<scratchpad>/ax5-after.log` (after, `SwiftCompile
tasks=2`, confirming the file actually recompiled).

No production code changed for Part A — the only diff is the test harness's capture height for one
sweep call.

### Part B — #230

`MapPanTabSwitchUITests.testADeliberatePanSurvivesLeavingForJournalAndBack` flaked 3× in CI this
round, every time on its own precondition: *"panning the map did not move the camera off the
reader."* `deliberateDrag` (#200/#209, commit `62c83f2`, `DragGestureGateTests`) already fixed the
systematic version of a synthesized drag reading as nothing — too few intermediate touch events for
the gesture recognizer to see on a loaded runner. This is the same family one level further down:
even through `deliberateDrag`, a three-core CI runner can occasionally coalesce or delay the touch
stream for one attempt and catch up on the next. That is contention, not a broken recognizer — the
same shape `UIWait.swift` documents for hittability (`AccessibilityTreeTests
.testTheFourTabsAreReachable`, run 30871836674) and CLAUDE.md records for device-state flakiness
(E202): occasional, never reproduced locally, and not something a longer single wait fixes, because
the drag never happened at all — there is nothing for a longer wait to catch up to.

**The fix.** `panUntilMoved` retries the drag itself (not just the settle wait) up to three times,
polling the recenter control's own `accessibilityValue` between attempts, with a half-second pause so
a retry does not queue a second unlucky touch stream on a runner still catching up from the last one.
Every attempt calls the existing `pan(_:)`, which is `deliberateDrag` — no second spelling of the
gesture was introduced; `DragGestureGateTests` still passes. The final failure message is byte-for-
byte the original precondition sentence, so a camera that is genuinely immovable after every attempt
still fails exactly as before — nothing about direction one's assertion (`switchTabs`, the
not-recentered check) changed.

**Red-proofed both ways**, by temporarily making `pan(_:)`'s call inside `panUntilMoved` a no-op
(first attempt only, then all attempts) and restoring it after each:

- **Attempt 1 swallowed, attempt 2 real** → `testADeliberatePanSurvivesLeavingForJournalAndBack`
  **passed**, 29.209s versus a ~14s per-test baseline (`<scratchpad>/pan-baseline-green.log`:
  "Executed 2 tests… in 29.050s" for both tests together) — the extra ~15s is attempt 1's exhausted
  10s settle window plus the 0.5s pause, which is the retry doing the recovering, not luck
  (`<scratchpad>/pan-redproof-recovery.log`).
- **Every attempt swallowed** → the test **failed** at 36.236s (three 10s settle windows plus two
  0.5s pauses), with the unchanged message: *"panning the map did not move the camera off the reader
  (the control reads "Centered on you"), so there is no deliberate camera to preserve"*
  (`<scratchpad>/pan-redproof-immovable.log`) — a genuinely immovable camera is still a failure, for
  the original reason.

Real-code baseline and post-fix runs, both green: `<scratchpad>/pan-baseline-green.log` and
`<scratchpad>/pan-final-green.log`, both `** TEST SUCCEEDED **` with `Executed 2 tests, with 0
failures`. `DragGestureGateTests` green after: `<scratchpad>/drag-gate.log`.

### Verification

Full suite, this session, foreground, judged by `Tools/verify_test_log.sh` and a manual log-tail read
for `** TEST SUCCEEDED **` / `Test run with N tests passed` (ticket #231 established the verifier
alone can false-green an interrupted run) — see the PR body for the exact log line and path.
