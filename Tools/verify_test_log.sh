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
# Usage: Tools/verify_test_log.sh <log> [max-age-minutes]   (default max age 60)

set -u
LOG="${1:?usage: verify_test_log.sh <log> [max-age-minutes]}"
MAX_AGE_MIN="${2:-60}"

fail() { echo "VERIFY-FAIL: $1" >&2; exit 1; }

[ -f "$LOG" ] || fail "log does not exist: $LOG"

# Freshness — a stale log at the same path has produced a false green before.
if [ -n "$(find "$LOG" -mmin +"$MAX_AGE_MIN" 2>/dev/null)" ]; then
  fail "log is older than ${MAX_AGE_MIN}m (mtime $(stat -f '%Sm' "$LOG")) — stale artifact, not evidence"
fi

# Terminal completeness — a killed or still-running build has no terminal marker.
if ! grep -qE '\*\* TEST (SUCCEEDED|FAILED) \*\*|Test run with [0-9]+ tests? .*(passed|failed)' "$LOG"; then
  fail "no terminal result marker — build was killed, is still running, or never ran tests"
fi

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
