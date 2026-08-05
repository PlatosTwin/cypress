## E231 — `Tools/verify_test_log.sh` false-greened an interrupted run that carried an XCTest failure

**The artifact.** An E139 (`perf/e139-basemap-invalidation`) run on the 16e simulator
(`3A1F212D-8F3A-41F1-AF72-EC95E155A4C9`, 390 pt screen), full unit + UI suite, killed mid-run. The
log ends `** BUILD INTERRUPTED **`, contains no `** TEST SUCCEEDED **` and no `** TEST FAILED **`
anywhere, and contains `Executed 26 tests, with 1 failure (0 unexpected)` — a genuine
`DeepLinkVoiceOverTests` failure earlier in the run. The unmodified verifier printed:

```
VERIFY-NOTE: device iPhone 16e 3A1F212D-8F3A-41F1-AF72-EC95E155A4C9 — screen 390 (1170 px @ 3.000000x)
VERIFY-NOTE: SwiftCompile tasks=431
VERIFY-NOTE: XCTest skipped=0 — a change in this number between two runs of the same tree is a device change, not a code change (E216)
VERIFY-OK: ✔ Test run with 1193 tests in 118 suites passed after 117.474 seconds. | XCTest: Executed 2 tests, with 0 failures (0 unexpected) in 8.687 (8.689) seconds
```

Exit 0. Premise reproduced exactly before any fix was applied.

### The mechanism — two independent bugs, both load-bearing

**1. Terminal completeness was an OR across two phases that do not share a terminus.**
`HAS_TEST_MARKER` was set by:

```
grep -qE '\*\* TEST (SUCCEEDED|FAILED) \*\*|Test run with [0-9]+ tests? .*(passed|failed)' "$LOG"
```

Swift Testing's own `Test run with N tests … passed` line is a real terminus — but only for the
Swift Testing (unit) phase. When both frameworks run in one invocation, the XCTest (UI) phase
starts *after* Swift Testing's line has already been printed, and only the invocation-level
`** TEST SUCCEEDED **` / `** TEST FAILED **` marker (printed once, at the very end of the whole
`xcodebuild test` action) speaks for whether the XCTest phase itself finished. The interrupted
E139 log has the Swift Testing line, satisfying the OR, while its XCTest phase never reaches its
own terminus. A Swift Testing pass earlier in the log was accepted as evidence about a phase that
ran after it and never finished.

**2. The one XCTest summary line the script did read was chosen by `tail -1`, and a genuinely
finished run's `tail -1` line is a coincidence, not a rule.**

```
XCTEST_LINE=$(grep -E 'Executed [1-9][0-9]* tests?' "$LOG" | tail -1)
```

`XCTEST_LINE` was captured — and then **never checked for failures at all**. In a run that reaches
its own end, XCTest prints one `Executed` line per suite as each finishes, then a final *aggregate*
line summing every suite in the invocation; that aggregate is always the last such line in the
file, so `tail -1` happens to be the right number to judge. An **interrupted** run never reaches
the aggregate. `tail -1` then falls back to whichever individual suite happened to finish last
before the kill — which can be, and in this artifact is, a suite that ran *after* the one that
failed and reported cleanly. `DeepLinkVoiceOverTests` finished with `Executed 26 tests, with 1
failure`; `MapCenteredStateUITests` then ran clean and is the line `tail -1` returned; the run was
then killed mid-`MapFilterAccessibilityTests` with no aggregate line ever printed. The one real
failure in the run was structurally invisible to a check that only ever looked at the last line.

Bug 2 is strictly narrower than bug 1: an interrupted run with **no** failures anywhere (nothing
for `tail -1` or a full scan to find) still false-greened under the unmodified script, off bug 1
alone. Confirmed by truncating a healthy log mid-`MapSearchUITests`, after an earlier suite
finished clean, with zero failures anywhere in the file — the unmodified script printed the same
`VERIFY-OK` shape. Both bugs had to be fixed.

### The fix

`Tools/verify_test_log.sh`:

- A new signal, `HAS_XCTEST_PHASE`, set by `grep -qE "^Test Case '-\["` — Swift Testing's XCTest
  bridge never emits that line shape for its own specimens, so its presence means a genuine XCTest
  suite (e.g. `CypressUITests`) started. If `HAS_XCTEST_PHASE=1` and the log has neither
  `** TEST SUCCEEDED **` nor `** TEST FAILED **`, verification refuses: that phase is incomplete
  (killed, interrupted, or still running), regardless of what a Swift Testing line elsewhere in
  the file says.
- `XCTEST_LINE` (the `tail -1` line) is still computed for the `VERIFY-OK` report and the skip-count
  note, but failure detection no longer trusts it alone: `XCTEST_FAILURE_LINES` now `grep`s **every**
  `Executed N tests, …` line in the file for a nonzero failure count and refuses if any exist,
  independent of which one `tail -1` would have picked.

Both guards are independently load-bearing — verified by disabling each in turn and re-running
against the kept artifact; each one alone still refuses it, for a different stated reason. Neither
was sufficient alone against the zero-failure interrupted case: the failure-scan guard has nothing
to find there, so completeness is the only thing that catches it.

### Sibling sweep

The kept artifact's `XCTEST_LINE` was one of two `tail -1` line captures in the script; the other is
`SWIFT_LINE` (`grep -E 'Test run with [1-9][0-9]* tests?' "$LOG" | tail -1`). Checked and left
unchanged: Swift Testing prints its `Test run with N tests in M suites …` line exactly once per
invocation — a true final aggregate, not a per-suite line — so there is no earlier line of the same
shape a truncation could hide behind. Confirmed empirically: not one log in the scratchpad's
collection of real historical runs (several dozen, spanning many rounds) contains more than one
`Test run with` line. The `-m1` (first-match) captures for the `CYPRESS-RUN:` provenance stamp
(`STAMP_DEVICE`, `STAMP_WIDTH`, `STAMP_STATE`) are a different shape — those are header lines
`run_tests.sh` writes once at the top of the log before any test runs, so "first match" is the
correct and only sensible read, not a last-line risk. `COMPILE_TASKS` and the `--warnings` mode's
`SRC_WARNINGS`/`OTHER_COUNT` all use `-c` (count) or `sort -u` over the whole file already, immune
to this class by construction.

### Red-proof matrix

All five cases run against the fixed script, log fixtures built from real captured logs (the kept
E139 artifact, an E139 healthy re-run `e139-suite2.log` used as the healthy-green base, and one
existing unit-only green log), never against a simulator or a build.

1. **Kept artifact → refuses.**
   ```
   VERIFY-FAIL: an XCTest phase started (Test Case lines present) but the log has neither ** TEST SUCCEEDED ** nor ** TEST FAILED ** — that phase is incomplete (killed/interrupted/still running), not passing
   ```
   (exit 1; unmodified script on the same file: `VERIFY-OK`, exit 0.)

2. **Interrupted, zero failures anywhere (healthy log truncated mid-`MapSearchUITests`, right
   after `MapRecenterUITests` finished clean) → refuses as incomplete.**
   ```
   VERIFY-FAIL: an XCTest phase started (Test Case lines present) but the log has neither ** TEST SUCCEEDED ** nor ** TEST FAILED ** — that phase is incomplete (killed/interrupted/still running), not passing
   ```
   (exit 1; unmodified script on the same file: `VERIFY-OK: ✔ Test run with 1193 tests in 118
   suites passed … | XCTest: Executed 2 tests, with 0 failures …`, exit 0 — the same false-green,
   with no failure line anywhere for a naive fix to have caught.)

3. **Healthy full green (E139 re-run, both phases complete, aggregate `Executed 87 tests, with 0
   failures`, `** TEST SUCCEEDED **`) → still VERIFY-OK, byte-identical to the unmodified script.**
   ```
   VERIFY-OK: ✔ Test run with 1193 tests in 118 suites passed after 118.881 seconds. | XCTest: Executed 87 tests, with 0 failures (0 unexpected) in 1234.362 (1238.930) seconds
   ```
   (exit 0, both scripts.)

4. **Healthy red (same log, one suite's `Executed` line and both aggregate lines edited to `1
   failure`, `** TEST SUCCEEDED **` → `** TEST FAILED **`) → still VERIFY-FAIL, identical reason.**
   ```
   VERIFY-FAIL: ** TEST FAILED ** present
   ```
   (exit 1, both scripts — the pre-existing `** TEST FAILED **` path is untouched.)

5. **Unit-only green (`CypressTests` only, no XCTest phase at all) → unchanged verdict.**
   ```
   VERIFY-OK: ✔ Test run with 8 tests in 1 suite passed after 0.540 seconds.
   ```
   (exit 0, both scripts — `HAS_XCTEST_PHASE=0`, the new guard never fires.)

### Cross-reference

The kept artifact is from the same round as the E139 investigation on
`perf/e139-basemap-invalidation`. `Tools/run_tests.sh` provenance stamping (device, screen width,
device state) is unrelated to this bug and untouched.
