#!/bin/bash
# Judge a web test log honestly. Exit 0 only if the log is fresh, terminally complete, and
# contains a REAL pass line with a nonzero test count.
#
# The web analogue of `Tools/verify_test_log.sh`, and it exists for the same reason: on this
# project exit codes and green lines have lied at least five separate times
# (docs/investigations/repeat-failures-postmortem.md, class 1). Nothing about that changes in a
# different language, and one specific case is worse here than on the iOS side —
#
#     $ node --test --test-reporter=tap "test/**/*.nosuchthing.ts" ; echo $?
#     TAP version 13
#     1..0
#     # tests 0
#     # pass 0
#     # fail 0
#     0
#
# — a complete, entirely green summary, exit 0, from a glob that matched no file. Measured on
# Node 24.13.1 on 2026-09-10 while this script was being written, not quoted from anywhere. It is
# the exact shape of XCTest's `Executed 0 tests / All tests passed`, which is the false green
# CLAUDE.md names first. A typo in a path, a renamed directory, a `--test-only` left in: any of
# them produce it, and none of them looks like anything.
#
# Usage: Tools/verify_web_test_log.sh <log> [max-age-minutes]
#          (default max age 60)
#
# Exit status, and there are THREE of them:
#   0  VERIFY-WEB-OK        — a real pass line, from a complete run, with tests that ran
#   1  VERIFY-WEB-FAIL      — a red: something in the log reports failure
#   2  VERIFY-WEB-VACUOUS   — the log cannot support a claim either way: no terminus, or a run
#                             that executed zero tests. NOT a pass. Any caller that treats
#                             nonzero as failure is unaffected; the separate status exists so a
#                             reader is told "this proves nothing" rather than "this is broken",
#                             because the two send you to different places.
#
# **Note the difference from verify_test_log.sh, which also has an exit 2**: there it means an
# environment refusal (XCUITest event-synthesis timeouts). The scripts judge different logs and
# are never called on each other's, but do not assume the numbers mean the same thing.

set -u

fail()    { echo "VERIFY-WEB-FAIL: $1" >&2; exit 1; }
vacuous() { echo "VERIFY-WEB-VACUOUS: $1" >&2; exit 2; }
note()    { echo "VERIFY-WEB-NOTE: $1"; }

LOG="${1:?usage: verify_web_test_log.sh <log> [max-age-minutes]}"
shift
MAX_AGE_MIN=60
case "${1:-}" in
  ''|*[!0-9]*) ;;
  *) MAX_AGE_MIN="$1"; shift ;;
esac

[ -f "$LOG" ] || fail "log does not exist: $LOG"

# ── Freshness ───────────────────────────────────────────────────────────────────────────────
# A stale log at a reused path has produced a false green on this project. `find`'s own failure
# is fatal rather than discarded: an empty result from a find that never ran is indistinguishable
# from an empty result meaning "not stale", and the second reading is the one that lets an
# eight-hour-old log through.
if ! stale="$(find "$LOG" -mmin +"$MAX_AGE_MIN" 2>/dev/null)"; then
  fail "could not test the age of $LOG (max-age ${MAX_AGE_MIN}m) — refusing to treat an unrun freshness check as a fresh log"
fi
if [ -n "$stale" ]; then
  mtime="$(stat -f '%Sm' "$LOG" 2>/dev/null || stat -c '%y' "$LOG" 2>/dev/null || echo unknown)"
  fail "log is older than ${MAX_AGE_MIN}m (mtime ${mtime}) — stale artifact, not evidence"
fi

# ── Provenance ──────────────────────────────────────────────────────────────────────────────
stamp() { grep -m1 "^CYPRESS-WEB-RUN: $1 " "$LOG" | sed "s/^CYPRESS-WEB-RUN: $1 //"; }
STAMP_NODE="$(stamp node)"
STAMP_HEAD="$(stamp head)"
STAMP_WORKTREE="$(stamp worktree)"
STAMP_WEBDIR="$(stamp web-dir)"
STAMP_LOCK="$(stamp package-lock)"
STAMP_PHASES="$(stamp phases)"

if [ -n "$STAMP_NODE" ]; then
  note "node ${STAMP_NODE} — head ${STAMP_HEAD:-unknown} — worktree ${STAMP_WORKTREE:-unknown}"
  note "web-dir ${STAMP_WEBDIR:-unknown} — package-lock ${STAMP_LOCK:-unknown}"
else
  note "no CYPRESS-WEB-RUN header — this log was not produced by Tools/run_web_tests.sh, so the Node version, the commit and the working tree it came from are all unknown"
fi
if grep -q '^CYPRESS-WEB-RUN: INSTALL SKIPPED' "$LOG"; then
  INSTALL_NOTE=" (warm node_modules — this certifies the code, not the dependency tree)"
  note "INSTALL SKIPPED — node_modules was not rebuilt from the lockfile for this run, so nothing here says the lockfile installs"
else
  INSTALL_NOTE=""
fi

# ── Terminal completeness ───────────────────────────────────────────────────────────────────
# The runner writes this line after its last phase returns. A killed run, a run that timed out,
# a run whose shell died between phases: none of them have it. This is the guard against reading
# a truncated log as a short one — the failure that produced E139 on the iOS side.
grep -q '^CYPRESS-WEB-RUN: phases-complete ' "$LOG" \
  || vacuous "no terminus (no CYPRESS-WEB-RUN phases-complete line) — the run was killed, is still running, or died between phases. A log that stops is not a log that passed."

# Every phase the header announced must have both a begin and an end. A phase that vanished
# between the two lists is a phase whose result nobody has.
if [ -n "$STAMP_PHASES" ]; then
  for phase in $STAMP_PHASES; do
    grep -q "^CYPRESS-WEB-RUN: phase-end ${phase} status=" "$LOG" \
      || vacuous "the header announced phase '${phase}' and the log has no phase-end line for it — that phase's result is unknown"
  done
fi

# ── The phases that failed, by their own recorded status ────────────────────────────────────
# This is the ONE place an exit code is consulted, and it is consulted as evidence written into
# the log next to the phase that produced it, never as this script's verdict. It cannot make a
# run pass: a `status=0` on every phase still has to get past the test-count assertions below.
FAILED_PHASES="$(grep '^CYPRESS-WEB-RUN: phase-end ' "$LOG" | grep -v 'status=0$' || true)"

# ── The typecheck, judged by its own positive result line ───────────────────────────────────
# `astro check` prints `- 0 errors` in a `Result (N files):` block; `tsc --noEmit` prints nothing
# at all when it is happy, which is why it is not judged on its own — silence is the shape of
# every false green in this repository, and the phase-end status is the only thing that speaks
# for it.
case " ${STAMP_PHASES} " in
  *" typecheck "*)
    CHECK_RESULT="$(grep -m1 -E '^Result \([0-9]+ files\):' "$LOG" || true)"
    CHECK_ERRORS="$(grep -m1 -E '^- [0-9]+ errors?$' "$LOG" | grep -oE '[0-9]+' || true)"
    if [ -z "$CHECK_RESULT" ]; then
      vacuous "the typecheck phase ran but the log has no astro check 'Result (N files):' block — astro check did not reach its summary, so nothing here says the .astro files were checked"
    fi
    if [ "${CHECK_ERRORS:-0}" != "0" ]; then
      echo "VERIFY-WEB-FAIL-DETAIL: the typecheck errors, from $LOG —" >&2
      grep -E '^\s*[^ ]+\.(astro|ts|mjs):[0-9]+:[0-9]+ - error' "$LOG" | head -n 25 | sed 's/^/  /' >&2
      fail "astro check reports ${CHECK_ERRORS} error(s) — the zero-warning line covers the web too"
    fi
    note "astro check: ${CHECK_RESULT} 0 errors"
    ;;
esac

# ── The test phase ──────────────────────────────────────────────────────────────────────────
case " ${STAMP_PHASES} " in
  *" test "*) ;;
  *)
    # No test phase was asked for. That is a legitimate way to run the script and an illegitimate
    # thing to call a pass, so it gets the verdict that says "this proves nothing about the
    # tests" rather than the one that says "the tests are fine".
    if [ -n "$FAILED_PHASES" ]; then
      echo "VERIFY-WEB-FAIL-DETAIL: phases that reported failure, from $LOG —" >&2
      printf '%s\n' "$FAILED_PHASES" | sed 's/^/  /' >&2
      fail "phase(s) failed in a run that did not include the test phase"
    fi
    vacuous "no test phase in this run (phases: ${STAMP_PHASES:-unknown}) — the other phases are green, and no test was executed"
    ;;
esac

# node --test's TAP summary. Each counter is read on its own; the summary block as a whole is
# the test runner's own terminus, distinct from the runner script's.
counter() { grep -m1 -E "^# $1 [0-9]+$" "$LOG" | awk '{print $3}'; }
TESTS="$(counter tests)"
PASS="$(counter pass)"
FAILCOUNT="$(counter fail)"
CANCELLED="$(counter cancelled)"
SKIPPED="$(counter skipped)"
TODO="$(counter todo)"

if [ -z "$TESTS" ] || [ -z "$PASS" ] || [ -z "$FAILCOUNT" ]; then
  vacuous "the test phase produced no TAP summary (no '# tests' / '# pass' / '# fail' lines) — node --test did not reach its own summary, so the suite did not finish"
fi

if [ "$FAILCOUNT" -gt 0 ]; then
  echo "VERIFY-WEB-FAIL-DETAIL: what failed, from $LOG —" >&2
  # `not ok N - name` is TAP's per-test failure line. The `# Subtest:` lines above it name the
  # same tests and would double every entry, so they are left out.
  grep -E '^\s*not ok [0-9]+ - ' "$LOG" | sed 's/^[[:space:]]*//' | head -n 25 | sed 's/^/  /' >&2
  fail "node --test reports ${FAILCOUNT} failing test(s) of ${TESTS}"
fi

if [ "${CANCELLED:-0}" -gt 0 ]; then
  fail "node --test reports ${CANCELLED} cancelled test(s) — a cancelled test is not a passing test"
fi

# **The zero-count refusal.** See this file's header for the reproduction: `node --test` over a
# glob that matches nothing exits 0 with every counter at zero and no error anywhere.
if [ "$TESTS" -eq 0 ]; then
  vacuous "the suite executed 0 tests and reported success — a glob that matched no file, a renamed directory, or a filter that matched nothing. A zero-count green is not evidence."
fi
if [ "$PASS" -eq 0 ]; then
  vacuous "the suite reports ${TESTS} test(s) but 0 passing — nothing here executed and passed"
fi

# Reported, deliberately not refused against an expectation, for the reason verify_test_log.sh
# gives at length: a threshold lives nowhere honest, is edited on most branches, and spends its
# life stale. A number in front of the reader is what is wanted.
if [ "${SKIPPED:-0}" -gt 0 ] || [ "${TODO:-0}" -gt 0 ]; then
  note "skipped=${SKIPPED:-0} todo=${TODO:-0} — a change in these between two runs of the same tree is worth a second look"
fi

# A failing phase OUTSIDE the test phase — a build that broke, an install that could not resolve
# — is still a red, and it is checked after the test counters so the verdict names the tests
# first when both are wrong.
if [ -n "$FAILED_PHASES" ]; then
  echo "VERIFY-WEB-FAIL-DETAIL: phases that reported failure, from $LOG —" >&2
  printf '%s\n' "$FAILED_PHASES" | sed 's/^/  /' >&2
  fail "the tests passed but another phase did not — see the lines above"
fi

echo "VERIFY-WEB-OK: ${PASS} of ${TESTS} tests passed, 0 failed, ${SKIPPED:-0} skipped${INSTALL_NOTE} | phases: ${STAMP_PHASES:-unknown} | node ${STAMP_NODE:-unknown} | head ${STAMP_HEAD:-unknown}"
