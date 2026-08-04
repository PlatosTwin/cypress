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
