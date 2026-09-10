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
#
# ── What this script does NOT do, said once and plainly ─────────────────────────────────────
# It judges a log's INTERNAL CONSISTENCY. It reads the provenance stamps and repeats them; it
# does not and cannot verify that they name the tree you are asking about, because a log is
# routinely judged from somewhere other than the machine that wrote it (a CI artifact, another
# worktree). A log stamped `head deadbee some-other-branch` is certified on its own terms with
# that string printed in the verdict. CLAUDE.md's "never trust an artifact you did not watch
# being produced" is the reader's job; making the stamps impossible to miss is this script's.
#
# ── Why the TAP block below is as suspicious as it is ───────────────────────────────────────
# The first version of this script read `# fail N` with `grep -m1` and consulted the `not ok`
# lines only INSIDE the `fail > 0` branch, so it never once compared the summary against the body
# it summarises. Adversarial review walked three forged green logs straight past it, and all
# three are now specimens with a red-proof in the pull request that fixed them:
#
#   * a real red log with three `sed` substitutions and its `not ok` lines untouched;
#   * a green summary planted ABOVE the real one, which `grep -m1` reached first;
#   * a log typed by hand with a plausible header, three counters and no TAP body at all.
#
# The checks that refuse them are counter uniqueness, `# fail 0` against the `not ok` lines, and
# `ok + not ok == # tests + # suites` — none of them clever, all of them reading the rest of the
# file. This is the guard-green-while-the-defect-is-present class, in the newest guard in the
# repository, and it survived one round of the author's own calibration.

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

# **What this script can and cannot say about provenance, stated because the difference has
# already been claimed wrongly once.** It reads the stamps and PUTS THEM IN FRONT OF YOU. It does
# not refuse a log for missing them, and it cannot: `verify_test_log.sh` behaves the same way on
# the iOS side, and a log arriving as a CI artifact is legitimately being judged from a machine
# that is not the one that wrote it, so there is nothing here to compare a stamp against. That
# means a log stamped from a different commit, a different worktree or a different lockfile is
# certified on its own terms, and the reader is the one who has to check that the `head` and
# `worktree` in the notes are the tree the question was about. CLAUDE.md's rule — never trust an
# artifact you did not watch being produced — is not something a script can do for you; what a
# script can do is make the stamps impossible to miss, which is why they are also repeated in the
# one-line verdict.
if [ -n "$STAMP_NODE" ]; then
  note "node ${STAMP_NODE} — head ${STAMP_HEAD:-unknown} — worktree ${STAMP_WORKTREE:-unknown}"
  note "web-dir ${STAMP_WEBDIR:-unknown} — package-lock ${STAMP_LOCK:-unknown}"
  note "PROVENANCE IS REPORTED, NOT CHECKED — nothing here compares those stamps against the tree you are asking about. Read them."
else
  note "no CYPRESS-WEB-RUN header — this log was not produced by Tools/run_web_tests.sh, so the Node version, the commit and the working tree it came from are all unknown. NOT a refusal, and it is the strongest statement available: the stamps are the only provenance a log carries, and their absence is a fact about the log, not a fault in it."
fi

# The runner writes `(DIRTY)` into the web-dir stamp when `git status --porcelain -- web/` is
# non-empty. It used to be computed, written, and then never reach the verdict — a run over a
# tree with uncommitted web changes read exactly like a run over a clean one, which is the E203
# fresh-DerivedData argument in another form: what was measured was not what is committed.
case "$STAMP_WEBDIR" in
  *"(DIRTY)"*)
    DIRTY_NOTE=" | web/ was DIRTY"
    note "the web/ tree was DIRTY when this ran — uncommitted changes were in the working directory, so this log certifies what was on disk and NOT what is at ${STAMP_HEAD:-that commit}"
    ;;
  *) DIRTY_NOTE="" ;;
esac
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
    grep -q "^CYPRESS-WEB-RUN: phase-begin ${phase} ::" "$LOG" \
      || vacuous "the header announced phase '${phase}' and the log has no phase-begin line for it — that phase never started, or its output has been detached from the marker that says where it starts"
    grep -q "^CYPRESS-WEB-RUN: phase-end ${phase} status=" "$LOG" \
      || vacuous "the header announced phase '${phase}' and the log has no phase-end line for it — that phase's result is unknown"
  done
fi

# ── The phases that failed, by their own recorded status ────────────────────────────────────
# This is the ONE place an exit code is consulted, and it is consulted as evidence written into
# the log next to the phase that produced it, never as this script's verdict. It cannot make a
# run pass: a `status=0` on every phase still has to get past the test-count assertions below.
FAILED_PHASES="$(grep '^CYPRESS-WEB-RUN: phase-end ' "$LOG" | grep -v 'status=0$' || true)"

# ── The phase blocks ────────────────────────────────────────────────────────────────────────
# Everything below reads a phase's OWN output, not the whole file. A counter or a summary line
# is evidence about the phase that printed it, and a log is one file with several phases' output
# concatenated into it — so `grep` over the whole thing answers a question nobody asked. It also
# closes the cheapest plant there is: a `# fail 0` typed into the build phase's output, or into
# the header, is not something `node --test` printed.
#
# `awk` between the phase's own begin and end markers, which the runner writes and which the
# completeness check above has already established are present for every announced phase.
phase_block() {
  awk -v p="$1" '
    index($0, "CYPRESS-WEB-RUN: phase-begin " p " ::") == 1 { inside = 1; next }
    index($0, "CYPRESS-WEB-RUN: phase-end " p " status=") == 1 { inside = 0 }
    inside { print }
  ' "$LOG"
}

# ── The typecheck, judged by its own positive result line ───────────────────────────────────
# `astro check` prints a `Result (N files):` block; `tsc --noEmit` prints nothing at all when it
# is happy, which is why it is not judged on its own — silence is the shape of every false green
# in this repository, and the phase-end status is the only thing that speaks for it.
#
# **All three severities are read, and that is the finding this block was rewritten for.** It
# used to read `- N errors` alone while its own failure message claimed "the zero-warning line
# covers the web too". It did not: it covered errors. `astro check` prints, at column 0, in the
# same block —
#
#     Result (6 files):
#     - 0 errors
#     - 0 warnings
#     - 0 hints
#
# — and a log edited to `- 12 warnings` / `- 40 hints` certified `VERIFY-WEB-OK`. Reproduced on
# this tree before the fix. `npm run typecheck` now also passes `--minimumFailingSeverity
# warning`, so the phase's own status goes red as well; the two are independent on purpose, in
# the same way the test counters and `phase-end test status=` are.
#
# Hints are REPORTED, not refused. The zero-warning line is about warnings; a hint is astro's
# style suggestion and promoting one to a gate is a decision nobody has made. The number is put
# in front of the reader instead, which is what this file does everywhere it declines to judge.
case " ${STAMP_PHASES} " in
  *" typecheck "*)
    TYPECHECK_OUT="$(phase_block typecheck)"
    CHECK_RESULT="$(printf '%s\n' "$TYPECHECK_OUT" | grep -m1 -E '^Result \([0-9]+ files\):' || true)"
    severity() { printf '%s\n' "$TYPECHECK_OUT" | grep -m1 -E "^- [0-9]+ $1s?$" | grep -oE '^- [0-9]+' | grep -oE '[0-9]+' || true; }
    CHECK_ERRORS="$(severity error)"
    CHECK_WARNINGS="$(severity warning)"
    CHECK_HINTS="$(severity hint)"
    if [ -z "$CHECK_RESULT" ]; then
      vacuous "the typecheck phase ran but its output has no astro check 'Result (N files):' block — astro check did not reach its summary, so nothing here says the .astro files were checked"
    fi
    # A `Result` block with no severity lines under it is the same vacuity one level down: the
    # summary was reached and the counts were not read, which is indistinguishable from zero.
    if [ -z "$CHECK_ERRORS" ] || [ -z "$CHECK_WARNINGS" ]; then
      vacuous "astro check printed '${CHECK_RESULT}' but its error and warning lines could not be read (errors='${CHECK_ERRORS:-}' warnings='${CHECK_WARNINGS:-}') — the counts this verdict would rest on are not in the log, so it rests on nothing"
    fi
    if [ "$CHECK_ERRORS" != "0" ]; then
      echo "VERIFY-WEB-FAIL-DETAIL: the typecheck errors, from $LOG —" >&2
      grep -E '^\s*[^ ]+\.(astro|ts|mjs):[0-9]+:[0-9]+ - error' "$LOG" | head -n 25 | sed 's/^/  /' >&2
      fail "astro check reports ${CHECK_ERRORS} error(s)"
    fi
    if [ "$CHECK_WARNINGS" != "0" ]; then
      echo "VERIFY-WEB-FAIL-DETAIL: the typecheck warnings, from $LOG —" >&2
      grep -E '^\s*[^ ]+\.(astro|ts|mjs):[0-9]+:[0-9]+ - warning' "$LOG" | head -n 25 | sed 's/^/  /' >&2
      fail "astro check reports ${CHECK_WARNINGS} warning(s) — the zero-warning line covers the web too, and this is the check that makes that sentence true"
    fi
    note "astro check: ${CHECK_RESULT} 0 errors, 0 warnings, ${CHECK_HINTS:-unknown} hints"
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

# ── The TAP summary, and the body it claims to summarise ────────────────────────────────────
# **The summary is not taken at its word.** Everything from here to the verdict exists because
# adversarial review forged three separate green logs past the version of this block that did
# take it at its word, and all three were refused by two cheap consistency checks it was not
# doing. The three, each reproduced on this tree before the fix:
#
#   1. a REAL red log with `# pass 9`→`10`, `# fail 1`→`0` and `phase-end test status=1`→`0`
#      substituted, and the `not ok 1 - .nvmrc agrees with engines.node` line left in the file;
#   2. a green summary PLANTED ABOVE the real red one, which `grep -m1` reached first;
#   3. a log typed by hand, from a run that never happened: a plausible header, three counters,
#      and no TAP body at all.
#
# What refuses them is not cleverness, it is reading the rest of the file. `node --test` prints
# one result line per test and per suite, and the summary counts exactly those lines. A summary
# that disagrees with the body under it is not a pass and not a fail — it is a log that cannot be
# read as either, and the whole reason this script exists is that this project keeps reading the
# second kind as the first.
TEST_OUT="$(phase_block test)"
if [ -z "$TEST_OUT" ]; then
  vacuous "the header announced a test phase and there is nothing between its phase-begin and phase-end lines — no TAP output at all, so nothing here says a test ran"
fi

# **Each counter must appear exactly ONCE.** `grep -m1` takes the first match, so a summary
# planted above the real one wins — forgery 2, and it is the plainest edit of the three. One
# `node --test` invocation prints one summary; two summaries in one phase means either two runs
# concatenated or a plant, and in both cases this script does not know which one is the run's.
# Refusing is the only honest answer, and it is the answer for the legitimate case too.
counter() {
  local n; n="$(printf '%s\n' "$TEST_OUT" | grep -cE "^# $1 [0-9]+$")"
  if [ "$n" -gt 1 ]; then
    vacuous "the test phase contains ${n} '# $1' lines. node --test prints one TAP summary per run, so this log holds either two runs' output or a planted counter — either way there is no single summary to read, and the first match is not evidence."
  fi
  printf '%s\n' "$TEST_OUT" | grep -m1 -E "^# $1 [0-9]+$" | awk '{print $3}'
}
TESTS="$(counter tests)"
SUITES="$(counter suites)"
PASS="$(counter pass)"
FAILCOUNT="$(counter fail)"
CANCELLED="$(counter cancelled)"
SKIPPED="$(counter skipped)"
TODO="$(counter todo)"

if [ -z "$TESTS" ] || [ -z "$PASS" ] || [ -z "$FAILCOUNT" ] || [ -z "$SUITES" ]; then
  vacuous "the test phase produced no complete TAP summary (needs '# tests', '# suites', '# pass' and '# fail'; got tests='${TESTS:-}' suites='${SUITES:-}' pass='${PASS:-}' fail='${FAILCOUNT:-}') — node --test did not reach its own summary, so the suite did not finish"
fi

# The body: one `ok N - name` or `not ok N - name` per test AND per suite, indented by nesting.
OK_LINES="$(printf '%s\n' "$TEST_OUT" | grep -cE '^[[:space:]]*ok [0-9]+ - ' || true)"
NOTOK_LINES="$(printf '%s\n' "$TEST_OUT" | grep -cE '^[[:space:]]*not ok [0-9]+ - ' || true)"

# **The structural check.** Measured on this tree rather than assumed, and the calibration is the
# point: a specimen with a pass, a skip, a todo, a nested suite and a failure inside it gives
# `ok 5 + not ok 3 = 8` against `# tests 6 + # suites 2 = 8`. Every test emits exactly one result
# line whatever its outcome, every suite emits one, and the two counters count exactly those.
#
# Note what is deliberately NOT asserted here: that `# pass` plus `# suites` equals the `ok`
# count. That identity holds in a log with no skips and no failing suite and is arithmetic
# coincidence otherwise — in the specimen above it comes out right for two reasons that cancel
# (a skip and a todo print `ok` without counting as `pass`; two suites print `not ok`). A check
# that is true by accident is the thing this file is against.
EXPECTED_LINES=$((TESTS + SUITES))
ACTUAL_LINES=$((OK_LINES + NOTOK_LINES))
if [ "$ACTUAL_LINES" -ne "$EXPECTED_LINES" ]; then
  vacuous "the TAP summary counts ${TESTS} test(s) and ${SUITES} suite(s) — ${EXPECTED_LINES} result lines — and the test phase's output contains ${ACTUAL_LINES} of them (${OK_LINES} ok, ${NOTOK_LINES} not ok). A summary that does not match the body under it summarises nothing: the log was truncated mid-suite, two runs were concatenated, or the counters were written by something other than the run."
fi

# **The cross-check `# fail 0` never used to get.** The `not ok` lines were read only INSIDE the
# branch below, so a log claiming zero failures was never compared against the failures printed
# in it — forgery 1, one character's difference from a genuine red.
if [ "$FAILCOUNT" -eq 0 ] && [ "$NOTOK_LINES" -gt 0 ]; then
  echo "VERIFY-WEB-FAIL-DETAIL: the 'not ok' lines this log claims do not exist, from $LOG —" >&2
  printf '%s\n' "$TEST_OUT" | grep -E '^[[:space:]]*not ok [0-9]+ - ' | sed 's/^[[:space:]]*//' | head -n 25 | sed 's/^/  /' >&2
  fail "the TAP summary says '# fail 0' and the same phase printed ${NOTOK_LINES} 'not ok' line(s). The log contradicts itself; the failures above are what it actually recorded."
fi
# The converse, for completeness rather than for a known attack: a summary claiming failures
# whose per-test lines are absent is equally unreadable.
if [ "$FAILCOUNT" -gt 0 ] && [ "$NOTOK_LINES" -eq 0 ]; then
  vacuous "the TAP summary says '# fail ${FAILCOUNT}' and the test phase printed no 'not ok' line at all — the summary and the body disagree, so neither can be read as the run's result"
fi

# **The phase's own recorded exit code, cross-checked against the counters.** Forgery 1 with the
# `status=` line left alone used to produce `VERIFY-WEB-FAIL: the tests passed but another phase
# did not` — a red for the wrong reason, sending the reader to the wrong phase. The test phase's
# status is not "another phase", and when it disagrees with the counters the disagreement is the
# finding.
TEST_STATUS="$(grep -m1 '^CYPRESS-WEB-RUN: phase-end test status=' "$LOG" | sed 's/.*status=//')"
if [ "$FAILCOUNT" -eq 0 ] && [ -n "$TEST_STATUS" ] && [ "$TEST_STATUS" != "0" ]; then
  fail "the TAP summary says '# fail 0' and the runner recorded 'phase-end test status=${TEST_STATUS}' for the same phase. npm exited nonzero on a suite that claims nothing failed — the log contradicts itself and is not a pass."
fi

if [ "$FAILCOUNT" -gt 0 ]; then
  echo "VERIFY-WEB-FAIL-DETAIL: what failed, from $LOG —" >&2
  # `not ok N - name` is TAP's per-test failure line. The `# Subtest:` lines above it name the
  # same tests and would double every entry, so they are left out. Note that this count is `>=`
  # the `# fail` counter and not equal to it: a failing test makes every suite enclosing it
  # `not ok` too, which is why the structural check above compares against tests+suites and not
  # against pass/fail.
  printf '%s\n' "$TEST_OUT" | grep -E '^[[:space:]]*not ok [0-9]+ - ' | sed 's/^[[:space:]]*//' | head -n 25 | sed 's/^/  /' >&2
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

echo "VERIFY-WEB-OK: ${PASS} of ${TESTS} tests passed, 0 failed, ${SKIPPED:-0} skipped${INSTALL_NOTE} | ${ACTUAL_LINES} TAP result lines match ${TESTS} tests + ${SUITES} suites | phases: ${STAMP_PHASES:-unknown} | node ${STAMP_NODE:-unknown} | head ${STAMP_HEAD:-unknown}${DIRTY_NOTE}"
