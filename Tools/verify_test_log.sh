#!/bin/bash
# Judge an xcodebuild test log honestly. Exit 0 only if the log is fresh, terminally
# complete, and contains a REAL pass line.
#
# Why this exists (docs/investigations/repeat-failures-postmortem.md, class 1):
# exit codes and green lines have lied at least five separate times on this project —
# `nohup … &` returning the shell's success, killed builds leaving truncated logs under
# wrappers claiming success, stale logs at a reused path, and XCTest printing
# "Executed 0 tests / All tests passed" for a Swift Testing suite it cannot see.
#
# Usage: Tools/verify_test_log.sh [--warnings] <log> [max-age-minutes] [file…]
#          (default max age 60)
#
# Exit status, and there are THREE of them:
#   0  VERIFY-OK           — a real pass line, from a complete run
#   1  VERIFY-FAIL         — a red, or a log this script refuses to judge
#   2  VERIFY-ENV-REFUSED  — every failure in the log is an XCUITest event-synthesis timeout,
#                            which is a fact about the host and not about the app. Not a pass:
#                            any caller that treats nonzero as failure is unaffected. See the
#                            long comment above ENVIRONMENT_REFUSAL_PATTERN for why this is a
#                            separate verdict rather than a red or a silence.
#
# It also prints the XCTest skip count as a VERIFY-NOTE, and appends the XCTest summary to
# VERIFY-OK when both frameworks ran — see the block above that line for why the count is
# surfaced and deliberately not refused against an expectation (#121, E216).
#
# --warnings certifies a warning count instead of taking one on trust (E203). A green *test*
# line survives an incremental build; a *warning* line does not, so a reused DerivedData
# recompiles nothing and reports zero warnings whether or not any exist. This mode refuses to
# certify unless the log shows SwiftCompile tasks — and, if files are named, unless those
# files were among them. It exits nonzero when any source warning is present, which is the
# zero-warning line (CLAUDE.md, code) in enforceable form.
#
#   Tools/verify_test_log.sh --warnings full.log 5
#   Tools/verify_test_log.sh --warnings full.log 5 MapHomeView.swift MapModel.swift

set -u

WARNINGS_MODE=0
EXPECT_WIDTH=""
ARGS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --warnings) WARNINGS_MODE=1 ;;
    # `--expect-width <pt>`: refuse a log that did not come from a screen this width.
    #
    # WHY (#201). The release gate runs on whatever simulator the runner image happens to offer —
    # the workflow picks the first name on a candidate list, and that list exists because macos-26
    # had no iPhone 16 Pro at all. So the width the gate runs at is decided by GitHub's image, and
    # it moves without anyone choosing. This project has already spent an afternoon on #183, where
    # two failures were filed as a width defect that did not exist, and E202/E216 are both about
    # results that are only true at one width. A gate whose width can change silently is a gate
    # that can start testing something else.
    #
    # Deliberately an EXACT match and a hard failure, not a warning. If the image bumps and the
    # first candidate becomes a 430 pt phone, the right outcome is a red run that says the width
    # moved — someone then decides whether to accept it and change the number. That is a decision;
    # discovering it six weeks later from a mysterious CI-only failure is not.
    --expect-width) shift; EXPECT_WIDTH="${1:?--expect-width needs a width in points}" ;;
    *) ARGS+=("$1") ;;
  esac
  shift
done
set -- ${ARGS+"${ARGS[@]}"}

LOG="${1:?usage: verify_test_log.sh [--warnings] <log> [max-age-minutes] [file…]}"
shift
# The optional age is positional and the file list follows it, so `verify … <log> a.swift b.swift`
# used to bind "a.swift" to MAX_AGE_MIN and drop it from the file list. Both halves of that failed
# SILENTLY: `find -mmin +a.swift` errors, its stderr is discarded, the empty result reads as "not
# stale", and the freshness guard — the one that exists because a stale log at a reused path once
# reported a clean suite from an 8-hour-old run — was simply off. Meanwhile the file it swallowed
# went unchecked while the E203 certification still said OK.
#
# An age is always digits and a path never is, so the two are told apart by shape rather than by
# position. No caller has to remember the order, and there is no spelling of this command that
# quietly checks less than it was asked to.
MAX_AGE_MIN=60
case "${1:-}" in
  ''|*[!0-9]*) ;;
  *) MAX_AGE_MIN="$1"; shift ;;
esac
CLAIMED_FILES=("$@")

fail() { echo "VERIFY-FAIL: $1" >&2; exit 1; }
note() { echo "VERIFY-NOTE: $1"; }

# ── The failure itself, printed rather than left behind in a file (task #71) ────────────────
#
# WHY. Until this existed, a red shard said exactly one line in GitHub Actions:
#
#     VERIFY-FAIL: ** TEST FAILED ** present
#
# and nothing else. The log with the assertion in it IS uploaded — `testflight.yml` has kept a
# `Keep the log, whatever happened` step on `unit` and every `ui` shard since 47b7d12
# (2026-08-03), and the artifacts are on every red run — but reading it costs a download, an
# unzip and a grep, so in practice three red runs on 2026-08-08/09 were called flake by people
# who never opened one. A verdict a reader will not act on is a verdict that does not count.
#
# So the judgment now carries its own evidence: the same script that says a run failed says
# which test and what it said, into the job log, and locally, and on every re-read of the
# artifact afterwards. This does not replace the artifact — a truncated excerpt is not a log —
# it removes the step between seeing red and knowing why.
#
# The three shapes, and they are the three this repo actually produces:
#   XCTest, with a source location:  /…/IdentifyFABReachabilityTests.swift:205: error: -[…] : failed - …
#   XCTest, without one:             <unknown>:0: error: -[CypressUITests.X testY] : Failed to determine hittability of …
#   Swift Testing:                   ✘ Test "…" recorded an issue at File.swift:12:5: Expectation failed: …
#
# Calibrated before it was believed, per CLAUDE.md — run against two logs whose answers were
# already known: a UI log with exactly one known failure (1 line) and a green unit log of 1,317
# tests (0 lines). A pattern like `failed` or `error:` alone reports 37 lines on that green log,
# because xcodebuild prints both words routinely in builds that are fine.
FAILURE_EXCERPT_MAX=25
FAILURE_EXCERPT_COLUMNS=400

# The per-test failure lines, extracted ONCE and named, because two callers now ask the same
# question: the excerpt printer below, and the environment-refusal classifier further down. Two
# spellings of "what failed here" would be free to disagree, and the one that decided the verdict
# would not be the one the reader saw.
#
# Swift Testing prints FOUR `✘` lines per failing test — the issue, the test, its suite, and the
# run — and only the first names the expectation. Left in, a single failure spent four of the 25
# slots below and a dozen would have pushed the informative lines out with their own bookkeeping
# (#71 review, N9). The two aggregate shapes go: `✘ Suite …` and `✘ Test run with …` say only how
# many, which the VERIFY-FAIL line already says.
test_failure_lines() {
  grep -E 'error: -\[|recorded an issue|^[[:space:]]*✘ ' "$LOG" \
    | grep -vE '^[[:space:]]*✘ (Suite |Test run with )' \
    | sed 's/^[[:space:]]*//' | awk '!seen[$0]++'
}

print_test_failures() {
  local lines count
  lines="$(test_failure_lines)"
  if [ -z "$lines" ]; then
    echo "  (no per-test failure line matched in $LOG — read the log itself; the run may have" >&2
    echo "   died before any test reported, which is a different problem from a failing test)" >&2
    return 0
  fi
  count="$(printf '%s\n' "$lines" | grep -c .)"
  # Clipped because one XCTest message in this suite is a 400-character sentence and a wrapped
  # wall of them is as unreadable as no message at all.
  #
  # Clipped by CHARACTER, in perl, and the route there is worth recording because two shorter
  # spellings are wrong on this platform (#71 review, N9):
  #   - `cut -c1-400` counts BYTES. These messages are full of typographic quotes and em dashes —
  #     the CI failure quoted in this repo's errata contains both — so a byte cut lands inside a
  #     multi-byte sequence and emits a partial character. Verified: `cut -c1-5` of a line
  #     starting `aaa“` yields `aaa\xe2\x80`, a broken glyph.
  #   - `sed 's/\(.\{400\}\).*/\1 …/'` does not work at all. BSD sed caps interval repetition at
  #     255 and errors out with `RE error: maximum repetition exceeds 255`, which took the whole
  #     excerpt with it — a nit fix that removed the feature it was polishing.
  #   - macOS `awk` is byte-based too, even under a UTF-8 locale: `length` on that same line
  #     reports 15, not 11. So it is no better than `cut`.
  # Decoding explicitly with `FB_DEFAULT` also means a log holding invalid bytes gets U+FFFD and
  # keeps going, rather than printing `Malformed UTF-8` warnings into the middle of the failure
  # report — which the `-CSD` spelling does.
  printf '%s\n' "$lines" | head -n "$FAILURE_EXCERPT_MAX" \
    | perl -pe 'BEGIN { binmode(STDIN, ":raw"); } use Encode; no warnings;
                $_ = Encode::decode("UTF-8", $_, Encode::FB_DEFAULT);
                if (length($_) > '"$FAILURE_EXCERPT_COLUMNS"') {
                  $_ = substr($_, 0, '"$FAILURE_EXCERPT_COLUMNS"') . " \x{2026}\n";
                }
                $_ = Encode::encode("UTF-8", $_);' \
    | sed 's/^/  /' >&2
  if [ "$count" -gt "$FAILURE_EXCERPT_MAX" ]; then
    echo "  … and $((count - FAILURE_EXCERPT_MAX)) more failure line(s) — full log: $LOG" >&2
  fi
}

[ -f "$LOG" ] || fail "log does not exist: $LOG"

# Freshness — a stale log at the same path has produced a false green before.
#
# `find`'s failure is fatal rather than discarded. An empty result from a `find` that never ran
# is indistinguishable from an empty result meaning "not stale", and the second reading is the
# one that lets an eight-hour-old log through: this guard spent an unknown period switched off
# because a bad argument made `find` error into a suppressed stderr.
if ! stale="$(find "$LOG" -mmin +"$MAX_AGE_MIN")"; then
  fail "could not test the age of $LOG (max-age ${MAX_AGE_MIN}m) — refusing to treat an unrun freshness check as a fresh log"
fi
if [ -n "$stale" ]; then
  fail "log is older than ${MAX_AGE_MIN}m (mtime $(stat -f '%Sm' "$LOG")) — stale artifact, not evidence"
fi

# Provenance, if run_tests.sh stamped it. The screen width is here because every verification
# run in this project's history until 2026-08-02 used a 402 pt or wider screen, and two map
# tests fail at 390 pt that pass at 402 (#183). A judgment that does not say how wide the
# screen was is not a judgment about the app on every device it ships to.
STAMP_DEVICE=$(grep -m1 '^CYPRESS-RUN: device ' "$LOG" | sed 's/^CYPRESS-RUN: device //')
STAMP_WIDTH=$(grep -m1 '^CYPRESS-RUN: screen-width-pt ' "$LOG" | sed 's/^CYPRESS-RUN: screen-width-pt //')
STAMP_STATE=$(grep -m1 '^CYPRESS-RUN: device-state ' "$LOG" | sed 's/^CYPRESS-RUN: device-state //')
if [ -n "$EXPECT_WIDTH" ]; then
  # The stamp is `402 (1206 px @ 3.000000x)`; the width is the first field.
  got_width="${STAMP_WIDTH%% *}"
  if [ -z "$got_width" ]; then
    fail "--expect-width ${EXPECT_WIDTH} was asked of a log with no CYPRESS-RUN screen-width stamp, so the width it ran at is unknown"
  elif [ "$got_width" != "$EXPECT_WIDTH" ]; then
    fail "this log ran at ${got_width} pt, not the ${EXPECT_WIDTH} pt it was asked to certify (device ${STAMP_DEVICE:-unknown}). The gate's screen changed. Decide whether to accept the new width and update the caller — do not delete the check (#201)."
  fi
  note "width ${got_width} pt confirmed against --expect-width ${EXPECT_WIDTH}"
fi

if [ -n "$STAMP_DEVICE" ]; then
  note "device ${STAMP_DEVICE} — screen ${STAMP_WIDTH:-unknown}"
  [ -n "$STAMP_STATE" ] && note "device-state ${STAMP_STATE}"
else
  note "no CYPRESS-RUN header — this log was not produced by Tools/run_tests.sh, so its device, screen width and device state are unknown"
fi
grep -q '^CYPRESS-RUN: PREFLIGHT SKIPPED' "$LOG" && \
  note "PREFLIGHT SKIPPED — the collision and E202 device-state guards did not run for this log"

# Machine load at the start of the run. Reported on every judgment, not only on the refusal path
# below, because it is the number that makes a UI result comparable to another one: the
# event-synthesis timeouts this script now classifies were all seen at the three-build cap and
# never below it, and a reader comparing two runs needs to know they met different machines.
STAMP_CONCURRENCY=$(grep -m1 '^CYPRESS-RUN: concurrent-xcodebuilds ' "$LOG" \
                      | sed 's/^CYPRESS-RUN: concurrent-xcodebuilds //')
[ -n "$STAMP_CONCURRENCY" ] && note "concurrent xcodebuilds at start: ${STAMP_CONCURRENCY}"

# Compile evidence (E203). Reported always; load-bearing only in --warnings mode.
COMPILE_TASKS=$(grep -c '^[[:space:]]*SwiftCompile ' "$LOG")
note "SwiftCompile tasks=${COMPILE_TASKS}"

HAS_TEST_MARKER=0
grep -qE '\*\* TEST (SUCCEEDED|FAILED) \*\*|Test run with [0-9]+ tests? .*(passed|failed)' "$LOG" && HAS_TEST_MARKER=1

# Did an XCTest phase (CypressUITests, or any XCTest target) actually start? Swift Testing's
# XCTest bridge never emits this line shape for its own specimens — only genuine XCTest suites
# print `Test Case '-[Target.Suite testName]' ...` — so this is a clean signal that a *second*,
# independent phase began after whatever Swift Testing did or didn't finish.
HAS_XCTEST_PHASE=0
grep -qE "^Test Case '-\[" "$LOG" && HAS_XCTEST_PHASE=1

if [ "$WARNINGS_MODE" = 1 ]; then
  # A build that compiled nothing cannot have reported a warning. Refuse to certify from it.
  if [ "$COMPILE_TASKS" -eq 0 ]; then
    fail "cannot certify a warning count: the log has 0 SwiftCompile tasks (E203). A reused DerivedData recompiles nothing and reports nothing — build into a fresh directory."
  fi
  # A "filename" with a space in it is not a filename. It is a whole list that arrived as ONE
  # argument, and the caller's shell is why: **zsh does not word-split an unquoted expansion**, so
  # `FILES=$(cat list.txt); verify --warnings "$log" $FILES` passes one enormous argument under zsh
  # and twenty-five under bash. Without this the failure below names every file at once and blames
  # each of them for not being compiled — which sends the reader to look at the build, where
  # nothing is wrong. Same family as the `grep [x]codebuild` and `for c in $line` traps already in
  # CLAUDE.md; this is the third time the shell difference has cost a debugging round here.
  for f in ${CLAIMED_FILES+"${CLAIMED_FILES[@]}"}; do
    case "$f" in
      *" "*)
        fail "one argument contains spaces, so it is a file LIST that reached this script as a single argument, not a filename: '${f}'. Under zsh an unquoted \$VAR does not word-split. Pass the names as separate arguments — 'xargs $0 --warnings $LOG < list.txt' does it correctly from a file."
        ;;
    esac
  done
  missing=""
  for f in ${CLAIMED_FILES+"${CLAIMED_FILES[@]}"}; do
    grep -q "^[[:space:]]*SwiftCompile .*${f}" "$LOG" || missing+=" $f"
  done
  [ -n "$missing" ] && \
    fail "cannot certify a warning count for:${missing} — no SwiftCompile task for those files in this log (E203)"

  # A source warning is anchored to a file, line and column. The three
  # `appintentsmetadataprocessor` "Metadata extraction skipped" lines are not source warnings
  # and cannot be removed without editing project.pbxproj (forbidden), so they are excluded
  # structurally rather than by name: they carry no file:line:col.
  SRC_WARNINGS=$(grep -oE '/[^[:space:]]+\.(swift|h|m|mm|c|cc|cpp):[0-9]+:[0-9]+: warning: .*' "$LOG" | sort -u)
  SRC_COUNT=$(printf '%s' "$SRC_WARNINGS" | grep -c . )
  OTHER_COUNT=$(grep -c 'warning: ' "$LOG")
  OTHER_COUNT=$(( OTHER_COUNT - $(grep -cE '/[^[:space:]]+\.(swift|h|m|mm|c|cc|cpp):[0-9]+:[0-9]+: warning: ' "$LOG") ))
  echo "VERIFY-WARNINGS: source=${SRC_COUNT} non-source=${OTHER_COUNT} compile-tasks=${COMPILE_TASKS}${CLAIMED_FILES+ files-checked=${#CLAIMED_FILES[@]}}"
  if [ "$SRC_COUNT" -gt 0 ]; then
    printf '%s\n' "$SRC_WARNINGS" | sed 's/^/  /' >&2
    fail "${SRC_COUNT} source warning(s) in a build that compiled ${COMPILE_TASKS} files — the zero-warning line covers both targets"
  fi
  if [ "$HAS_TEST_MARKER" = 0 ]; then
    # A build log, not a test log. Certify the warnings under a token that can never be
    # mistaken for a passing suite.
    echo "VERIFY-WARNINGS-OK: 0 source warnings across ${COMPILE_TASKS} compile tasks (build log — no test result in this file)"
    exit 0
  fi
fi

# Terminal completeness — a killed or still-running build has no terminal marker.
[ "$HAS_TEST_MARKER" = 1 ] || \
  fail "no terminal result marker — build was killed, is still running, or never ran tests"

# E139/E231: terminal completeness above is satisfied by Swift Testing's own "Test run with N
# tests ... passed" line ALONE, because that regex is an OR. That line only speaks for the Swift
# Testing phase. If an XCTest phase (CypressUITests) started after it, that phase needs its OWN
# terminus — the invocation-level `** TEST SUCCEEDED **` / `** TEST FAILED **` markers, which are
# printed once, at the end of the whole xcodebuild invocation, after every phase it ran. Their
# absence here means the XCTest phase that started is not finished: killed, interrupted, or still
# running — exactly the shape of the E139 artifact, which ends `** BUILD INTERRUPTED **` with an
# XCTest suite mid-test and no `** TEST SUCCEEDED **`/`FAILED` anywhere in the file. A Swift
# Testing pass earlier in the same log is not evidence about a phase that came after it.
if [ "$HAS_XCTEST_PHASE" = 1 ]; then
  grep -qE '\*\* TEST (SUCCEEDED|FAILED) \*\*' "$LOG" || \
    fail "an XCTest phase started (Test Case lines present) but the log has neither ** TEST SUCCEEDED ** nor ** TEST FAILED ** — that phase is incomplete (killed/interrupted/still running), not passing"
fi

# ── An environment refusal is not a red, and it is not a pass either (roadmap item (d)) ──────
#
# WHAT THIS IS. At the sanctioned three-concurrent-`xcodebuild` cap the UI phase produces
#
#     <unknown>:0: error: -[CypressUITests.X testY] : Failed to get matching snapshot:
#         Timed out while synthesizing event.
#
# Three of these across two runs on 2026-09-02, all green at lower concurrency, alongside a
# 1,043 s accessibility stall in the same conditions (ROADMAP, perf-campaign leftovers). The
# sentence is a fact about the HOST: XCUITest asked the simulator to deliver a tap and the event
# never arrived. Nothing was asserted about the app, and nothing about the app was learned.
#
# In the log it is indistinguishable, by shape, from an assertion the app failed — same
# `error: -[…]` prefix, same `** TEST FAILED **`, same nonzero exit. So three of them were read
# as reds, re-run, and called flake, which is the reading CLAUDE.md warns about from the other
# direction: a green re-run proves a failure was intermittent, never why it happened.
#
# WHAT IT DELIBERATELY DOES NOT DO. It does not exit 0, it does not print VERIFY-OK, and it does
# not suppress anything. It is a THIRD verdict with its own exit status (2) and its own token, so
# a caller that treats nonzero as failure — CI's `set -euo pipefail`, every wrapper in this repo —
# behaves exactly as before. What changes is that the reader is told which of the two things
# happened, next to the concurrency the run started at.
#
# WHY NOT LOWER THE CONCURRENCY INSTEAD. That was the other option on the ticket. It was not
# taken: the cap of three is written into CLAUDE.md and is the orchestrator's to set, a lock
# taken inside this script would serialize agents in a way nothing else can see, and — decisively
# — it would not classify the failures that still got through. This does not stop the flake; it
# stops the flake from being mistaken for a defect, which is the part a script can be right about.
#
# THE PATTERN IS NARROW ON PURPOSE. Only event synthesis. `Timed out while evaluating UI query`
# and `never appeared` are NOT here and must not be added without evidence: a control that never
# appears is what a genuine layout defect looks like, and E216's own symptom is a pin that never
# arrives. Widening this pattern is how a guard starts hiding the defects it was built beside.
ENVIRONMENT_REFUSAL_PATTERN='Timed out while synthesizing event|Failed to synthesize event'
FAILURE_LINES="$(test_failure_lines)"
if [ -n "$FAILURE_LINES" ]; then
  ENV_LINES=$(printf '%s\n' "$FAILURE_LINES" | grep -cE "$ENVIRONMENT_REFUSAL_PATTERN")
  # The complement, and it is what decides. One real assertion failure anywhere in the run makes
  # this a red, however many synthesis timeouts came with it — a mixed run is a red run, because
  # the environment did not refuse the test that failed on its own merits.
  OTHER_LINES="$(printf '%s\n' "$FAILURE_LINES" | grep -vE "$ENVIRONMENT_REFUSAL_PATTERN")"
  if [ "${ENV_LINES:-0}" -gt 0 ] && [ -z "$OTHER_LINES" ]; then
    echo "VERIFY-ENV-REFUSED: this run was refused by the environment, not by the code." >&2
    echo "  All ${ENV_LINES} failure line(s) in $LOG are XCUITest event-synthesis timeouts: the host never" >&2
    echo "  delivered the event to the simulator. Nothing was asserted about the app, so this log is" >&2
    echo "  evidence about the machine and about nothing else." >&2
    echo "  Concurrent xcodebuilds when this run started: ${STAMP_CONCURRENCY:-unknown (no CYPRESS-RUN stamp)}" >&2
    echo "  Every occurrence on record was at the three-build cap and green below it. Re-run this" >&2
    echo "  shard alone before concluding anything; a re-run at the same concurrency proves nothing." >&2
    echo "VERIFY-ENV-REFUSED-DETAIL: the timeouts, from $LOG —" >&2
    print_test_failures
    echo "  This is NOT a pass (exit 2). It is also not a red — do not file it as one." >&2
    exit 2
  fi
fi

if grep -q '\*\* TEST FAILED \*\*' "$LOG"; then
  echo "VERIFY-FAIL-DETAIL: what failed, from $LOG —" >&2
  print_test_failures
  fail "** TEST FAILED ** present"
fi

# A real pass line: Swift Testing's count is the only meaningful unit-test line —
# and it must be NONZERO: "Test run with 0 tests passed" is a missed -only-testing
# filter wearing a green line (found by the #144 agent, 2026-08-02). Same rule as
# XCTest's executed count.
SWIFT_LINE=$(grep -E 'Test run with [1-9][0-9]* tests?' "$LOG" | tail -1)
grep -qE 'Test run with 0 tests' "$LOG" && [ -z "$SWIFT_LINE" ] && \
  fail "Swift Testing ran 0 tests — an -only-testing filter matched nothing; a zero-count green is not evidence"
XCTEST_LINE=$(grep -E 'Executed [1-9][0-9]* tests?' "$LOG" | tail -1)

# E139/E231: XCTEST_LINE above is only the LAST "Executed" line in the file, and it was never
# checked for failures at all — a run that finishes normally prints one final AGGREGATE line
# summing every suite, so tail -1 happens to be the right number to judge. An INTERRUPTED run
# never reaches that aggregate: tail -1 then lands on whichever individual suite happened to run
# (and finish) last, which can easily be a clean suite that started *after* an earlier one failed.
# The kept E139 artifact is exactly this: `DeepLinkVoiceOverTests` finishes with "Executed 26
# tests, with 1 failure", then `MapCenteredStateUITests` runs clean and is what tail -1 sees,
# then the run is killed mid-`MapFilterAccessibilityTests` with no aggregate line ever printed.
# Scan every "Executed" line the log contains, not just the last one.
XCTEST_FAILURE_LINES=$(grep -E 'Executed [0-9]+ tests?,' "$LOG" | grep -E '[1-9][0-9]* failures?')
if [ -n "$XCTEST_FAILURE_LINES" ]; then
  echo "VERIFY-FAIL-DETAIL: what failed, from $LOG —" >&2
  print_test_failures
  fail "XCTest reports failures: $(printf '%s' "$XCTEST_FAILURE_LINES" | sed 's/^[[:space:]]*//' | paste -sd '; ' -)"
fi

if [ -z "$SWIFT_LINE" ] && [ -z "$XCTEST_LINE" ]; then
  fail "nothing actually executed ('Executed 0 tests' green is XCTest blind to Swift Testing, or an empty scheme/filter)"
fi
if printf '%s' "$SWIFT_LINE" | grep -q 'failed'; then
  echo "VERIFY-FAIL-DETAIL: what failed, from $LOG —" >&2
  print_test_failures
  fail "Swift Testing reports failures: $SWIFT_LINE"
fi

# The skip count, surfaced rather than buried (task #121, E216).
#
# A skipped test is invisible in the line this project judges a run by: `Test run with N tests
# passed` does not distinguish "ran and passed" from "declined to run", and in a run of BOTH
# targets the Swift Testing line wins the VERIFY-OK below, so XCTest's own "with M tests skipped"
# clause disappears from the judgment entirely. That is how a refusal path went unexercised under
# a green number for as long as it did.
#
# E216 records the other half: the count is a DEVICE signal. A run on a device whose location fix
# sat on a treeless block reported `70 tests, with 4 tests skipped` where a healthy one reports 2.
# **A UI log whose skip count changed between two runs of the same tree is reporting a device
# change, not a code change.**
#
# **Reported, deliberately not refused against a recorded expectation.** A threshold would have to
# live somewhere, and there is nowhere honest to put it: the legitimate count moves whenever a test
# is added, removed, or — as in #121 — stops skipping, so the number would be edited on most
# branches and would spend its life wrong or stale. Worse, a wrong expectation refuses runs that
# are fine, which is the failure mode that gets a guard switched off. What a reader needs is the
# number in front of them next to the device that produced it, which is what this line is. Judging
# it is a person's job and takes one glance.
SKIPPED=$(printf '%s' "$XCTEST_LINE" | sed -n 's/.*with \([0-9][0-9]*\) test[s]* skipped.*/\1/p')
if [ -n "$XCTEST_LINE" ]; then
  note "XCTest skipped=${SKIPPED:-0} — a change in this number between two runs of the same tree is a device change, not a code change (E216)"
fi

echo "VERIFY-OK: ${SWIFT_LINE:-$XCTEST_LINE}${SWIFT_LINE:+${XCTEST_LINE:+ | XCTest: $(printf '%s' "$XCTEST_LINE" | sed 's/^[[:space:]]*//')}}"
