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
ARGS=()
for a in "$@"; do
  case "$a" in
    --warnings) WARNINGS_MODE=1 ;;
    *) ARGS+=("$a") ;;
  esac
done
set -- ${ARGS+"${ARGS[@]}"}

LOG="${1:?usage: verify_test_log.sh [--warnings] <log> [max-age-minutes] [file…]}"
MAX_AGE_MIN="${2:-60}"
shift $(( $# > 2 ? 2 : $# ))
CLAIMED_FILES=("$@")

fail() { echo "VERIFY-FAIL: $1" >&2; exit 1; }
note() { echo "VERIFY-NOTE: $1"; }

[ -f "$LOG" ] || fail "log does not exist: $LOG"

# Freshness — a stale log at the same path has produced a false green before.
if [ -n "$(find "$LOG" -mmin +"$MAX_AGE_MIN" 2>/dev/null)" ]; then
  fail "log is older than ${MAX_AGE_MIN}m (mtime $(stat -f '%Sm' "$LOG")) — stale artifact, not evidence"
fi

# Provenance, if run_tests.sh stamped it. The screen width is here because every verification
# run in this project's history until 2026-08-02 used a 402 pt or wider screen, and two map
# tests fail at 390 pt that pass at 402 (#183). A judgment that does not say how wide the
# screen was is not a judgment about the app on every device it ships to.
STAMP_DEVICE=$(grep -m1 '^CYPRESS-RUN: device ' "$LOG" | sed 's/^CYPRESS-RUN: device //')
STAMP_WIDTH=$(grep -m1 '^CYPRESS-RUN: screen-width-pt ' "$LOG" | sed 's/^CYPRESS-RUN: screen-width-pt //')
STAMP_STATE=$(grep -m1 '^CYPRESS-RUN: device-state ' "$LOG" | sed 's/^CYPRESS-RUN: device-state //')
if [ -n "$STAMP_DEVICE" ]; then
  note "device ${STAMP_DEVICE} — screen ${STAMP_WIDTH:-unknown}"
  [ -n "$STAMP_STATE" ] && note "device-state ${STAMP_STATE}"
else
  note "no CYPRESS-RUN header — this log was not produced by Tools/run_tests.sh, so its device, screen width and device state are unknown"
fi
grep -q '^CYPRESS-RUN: PREFLIGHT SKIPPED' "$LOG" && \
  note "PREFLIGHT SKIPPED — the collision and E202 device-state guards did not run for this log"

# Compile evidence (E203). Reported always; load-bearing only in --warnings mode.
COMPILE_TASKS=$(grep -c '^[[:space:]]*SwiftCompile ' "$LOG")
note "SwiftCompile tasks=${COMPILE_TASKS}"

HAS_TEST_MARKER=0
grep -qE '\*\* TEST (SUCCEEDED|FAILED) \*\*|Test run with [0-9]+ tests? .*(passed|failed)' "$LOG" && HAS_TEST_MARKER=1

if [ "$WARNINGS_MODE" = 1 ]; then
  # A build that compiled nothing cannot have reported a warning. Refuse to certify from it.
  if [ "$COMPILE_TASKS" -eq 0 ]; then
    fail "cannot certify a warning count: the log has 0 SwiftCompile tasks (E203). A reused DerivedData recompiles nothing and reports nothing — build into a fresh directory."
  fi
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

grep -q '\*\* TEST FAILED \*\*' "$LOG" && fail "** TEST FAILED ** present"

# A real pass line: Swift Testing's count is the only meaningful unit-test line —
# and it must be NONZERO: "Test run with 0 tests passed" is a missed -only-testing
# filter wearing a green line (found by the #144 agent, 2026-08-02). Same rule as
# XCTest's executed count.
SWIFT_LINE=$(grep -E 'Test run with [1-9][0-9]* tests?' "$LOG" | tail -1)
grep -qE 'Test run with 0 tests' "$LOG" && [ -z "$SWIFT_LINE" ] && \
  fail "Swift Testing ran 0 tests — an -only-testing filter matched nothing; a zero-count green is not evidence"
XCTEST_LINE=$(grep -E 'Executed [1-9][0-9]* tests?' "$LOG" | tail -1)

if [ -z "$SWIFT_LINE" ] && [ -z "$XCTEST_LINE" ]; then
  fail "nothing actually executed ('Executed 0 tests' green is XCTest blind to Swift Testing, or an empty scheme/filter)"
fi
if printf '%s' "$SWIFT_LINE" | grep -q 'failed'; then
  fail "Swift Testing reports failures: $SWIFT_LINE"
fi

echo "VERIFY-OK: ${SWIFT_LINE:-$XCTEST_LINE}"
