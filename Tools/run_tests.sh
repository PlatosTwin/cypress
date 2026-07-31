#!/bin/bash
# Run the Cypress suite against a simulator with a fresh log, then judge the log honestly.
# Prints VERIFY-OK/<pass line> or VERIFY-FAIL/<reason> — believe that line, never the exit
# code of any wrapper around this script.
#
# Usage: Tools/run_tests.sh <udid> <log-path> [extra xcodebuild args…]
#   e.g. Tools/run_tests.sh EA0AD796-… /path/dd-me/unit.log -only-testing:CypressTests
#
# What it mechanizes (docs/investigations/repeat-failures-postmortem.md):
# - rm -f of the log first: a stale log at a reused path once nearly reported a clean
#   suite from an 8-hour-old run.
# - bootstatus -b before anything: simctl against a Shutdown device fails quietly in && chains.
# - camera grant: the unit suite hangs forever on a simulator that never granted camera.
# - verify_test_log.sh at the end: the only judgment that counts.

set -u
UDID="${1:?usage: run_tests.sh <udid> <log-path> [xcodebuild args…]}"
LOG="${2:?usage: run_tests.sh <udid> <log-path> [xcodebuild args…]}"
shift 2

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

rm -f "$LOG"

xcrun simctl bootstatus "$UDID" -b || { echo "VERIFY-FAIL: simulator $UDID did not boot" >&2; exit 1; }
# Grant is idempotent when already granted and the app is not yet running for this test pass.
xcrun simctl privacy "$UDID" grant camera app.cypress.Cypress 2>/dev/null || true

xcodebuild test \
  -project "$REPO/Cypress.xcodeproj" \
  -scheme Cypress \
  -destination "platform=iOS Simulator,id=$UDID" \
  "$@" >"$LOG" 2>&1
XCODE_EXIT=$?

"$HERE/verify_test_log.sh" "$LOG" 5 || exit 1
exit $XCODE_EXIT
