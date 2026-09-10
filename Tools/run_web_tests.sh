#!/bin/bash
# Run the web suite to a log with its provenance on the front of it.
#
# The web analogue of `Tools/run_tests.sh`, and it copies that script's DISCIPLINE rather than
# its Xcode specifics: refuse before writing a log, stamp what produced the log into the log,
# run every phase whether or not an earlier one went red, and hand the judgment to a separate
# script that reads the file. Nothing here decides whether the run passed. `npm` exit codes are
# collected and written down, and they are evidence about a phase, not a verdict about a run —
# this project's signature failure mode is a green wrapper over a suite that did not run
# (docs/investigations/repeat-failures-postmortem.md), and a different language does not change
# that. It gets worse here, in fact: `node --test` given a glob that matches no file exits 0 and
# prints a complete, entirely green TAP summary reporting zero tests. Reproduced on Node 24.13.1
# while writing this script; see `Tools/verify_web_test_log.sh`, which refuses it.
#
# Usage: Tools/run_web_tests.sh <log> [phase…]
#
#   phases, in order, and all four by default:
#     install    npm ci          — the lockfile exactly, into a wiped node_modules
#     typecheck  npm run typecheck  (astro check, then tsc --noEmit)
#     test       npm test        — node --test over test/
#     build      npm run build   — the SSR bundle the Dockerfile runs
#
#   Tools/run_web_tests.sh /tmp/web.log                     # all four, fresh install
#   Tools/run_web_tests.sh /tmp/web.log typecheck test      # a local loop, warm node_modules
#
# `install` is first and is the default for the same reason the iOS side certifies warnings on a
# fresh DerivedData: a dependency tree that was already on disk certifies nothing about the
# lockfile. Leaving it out is legitimate for a fast local loop and the log says so, in a line
# `verify_web_test_log.sh` reads and repeats in its verdict.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
WEB="$REPO/web"

usage() {
  echo "usage: $0 <log> [install|typecheck|test|build …]" >&2
  exit 2
}

LOG="${1:-}"
[ -n "$LOG" ] || usage
shift

# An absolute path, resolved against the caller's cwd before anything cd's. A relative log path
# that lands somewhere the reader does not expect is how a stale log at a reused path gets read
# as evidence for the wrong run.
case "$LOG" in
  /*) ;;
  *) LOG="$PWD/$LOG" ;;
esac

PHASES=("$@")
if [ "${#PHASES[@]}" -eq 0 ]; then
  PHASES=(install typecheck test build)
fi
for phase in "${PHASES[@]}"; do
  case "$phase" in
    install|typecheck|test|build) ;;
    *) echo "unknown phase: $phase" >&2; usage ;;
  esac
done

# ── Refusals, all of them BEFORE the log is created ─────────────────────────────────────────
# A refused run must leave no half-log behind: a file with a CYPRESS-WEB-RUN header and nothing
# after it is exactly the artifact someone mistakes for a run that started.

[ -d "$WEB" ] || { echo "no web/ directory at $WEB" >&2; exit 1; }
[ -f "$WEB/package.json" ] || { echo "no package.json in $WEB" >&2; exit 1; }
command -v node >/dev/null 2>&1 || { echo "node is not on PATH" >&2; exit 1; }
command -v npm  >/dev/null 2>&1 || { echo "npm is not on PATH" >&2; exit 1; }

# `npm ci` deletes node_modules before it repopulates it, so a second run in the same directory
# pulls the tree out from under the first one mid-build. The symptom is a module-not-found error
# naming a package that is plainly in the lockfile — a defect report about the app, from a
# collision between two runs. Same failure shape as E202 on the iOS side, one directory instead
# of one simulator.
#
# `grep -F` with a fixed string, and this is not stylistic: `grep [n]pm` — the trick used to keep
# a pattern from matching its own grep — GLOB-EXPANDS under zsh, matches nothing, and the guard
# passes vacuously. CLAUDE.md records that trap costing a debugging round on this project. So the
# process list is filtered by ANCESTRY instead, which is the only thing that works here:
#
# **a bash subshell keeps its parent's argv.** The `$( … )` that runs this very check is a fork
# of this script, so `ps` lists a second process whose command line is character-for-character
# `/bin/bash Tools/run_web_tests.sh <log>` under a DIFFERENT pid from `$$` — and so does the
# `grep` inside it. Excluding `$$` and its ancestors is not enough and the first version of this
# guard refused every run it was asked to protect, naming the run itself as the collision. That
# failure was loud. The same mistake in the other direction — a guard that quietly excludes too
# much and never refuses anything — is this project's dominant test-suite defect class, which is
# why the refusal below is red-proved in the pull request rather than assumed.
#
# A candidate is this run's own business when it is `$$`, a DESCENDANT of `$$` (walk its parents
# and arrive at us), or an ANCESTOR of `$$` (a parent shell whose command line legitimately
# contains this script's name). Anything else sharing `web/node_modules` is a genuine collision.
#
# **The whole process table is snapshotted ONCE and the walk happens inside the snapshot.**
# `run_tests.sh` does the same and the reason is sharper here: those transient subshells exit
# within milliseconds, so a walk that re-runs `ps` per hop finds their parent link already gone,
# concludes "not a descendant of mine", and refuses. Re-asking the kernel a question about a
# process that has since exited is not a stricter check, it is a different one.
PS_SNAPSHOT="$(ps -eo pid=,ppid=,command= 2>/dev/null)"
ppid_of() {
  printf '%s\n' "$PS_SNAPSHOT" | awk -v want="$1" '$1 == want { print $2; exit }'
}
MY_ANCESTORS="|"
probe="$$"
hops=0
while [ -n "$probe" ] && [ "$probe" -gt 1 ] 2>/dev/null; do
  probe="$(ppid_of "$probe")"
  [ -n "$probe" ] || break
  MY_ANCESTORS="${MY_ANCESTORS}${probe}|"
  hops=$((hops + 1))
  [ "$hops" -gt 64 ] && break
done

is_own_business() {
  local pid="$1" hops=0
  case "$MY_ANCESTORS" in *"|$pid|"*) return 0 ;; esac
  while [ -n "$pid" ] && [ "$pid" -gt 1 ] 2>/dev/null; do
    [ "$pid" = "$$" ] && return 0
    # Bounded, because a walk with no ceiling is a hang waiting for a pid table this script does
    # not control. Nothing on this machine is 64 processes deep.
    hops=$((hops + 1))
    [ "$hops" -gt 64 ] && break
    pid="$(ppid_of "$pid")"
  done
  return 1
}

# Deliberately NOT narrowed to runs writing this log path: two runs collide because they share
# node_modules, whatever logs they write.
OTHERS=""
while IFS= read -r line; do
  [ -n "$line" ] || continue
  pid="$(printf '%s' "$line" | awk '{print $1}')"
  is_own_business "$pid" && continue
  OTHERS="${OTHERS}${line}"$'\n'
done <<EOF
$(printf '%s\n' "$PS_SNAPSHOT" | grep -F "run_web_tests.sh" || true)
EOF
if [ -n "$OTHERS" ]; then
  echo "REFUSING: another run_web_tests.sh is live and would share $WEB/node_modules:" >&2
  printf '%s' "$OTHERS" | sed 's/^/  /' >&2
  echo "  Wait for it, or run the phases you need in a separate checkout." >&2
  exit 1
fi

# Astro's first run in a fresh checkout prints a telemetry notice and, unset, phones home. Off
# here rather than in package.json so that the setting travels with the harness and a developer
# running `npm run build` by hand still sees whatever they have configured for themselves.
export ASTRO_TELEMETRY_DISABLED=1
# npm's own progress bar and update check write control characters and a network round trip into
# a file nobody will read them from.
export NPM_CONFIG_FUND=false
export NPM_CONFIG_AUDIT=false
export NPM_CONFIG_UPDATE_NOTIFIER=false
export CI=1

cd "$WEB" || exit 1

LOCK_HASH="$( { shasum -a 256 package-lock.json 2>/dev/null || sha256sum package-lock.json 2>/dev/null; } | cut -c1-12)"
GIT_HEAD="$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo unknown)"
GIT_BRANCH="$(git -C "$REPO" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
DIRTY="clean"
[ -n "$(git -C "$REPO" status --porcelain -- "$WEB" 2>/dev/null)" ] && DIRTY="DIRTY"

{
  echo "CYPRESS-WEB-RUN: started $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo "CYPRESS-WEB-RUN: node $(node --version)"
  echo "CYPRESS-WEB-RUN: npm $(npm --version)"
  echo "CYPRESS-WEB-RUN: platform $(uname -s) $(uname -m)"
  echo "CYPRESS-WEB-RUN: worktree $REPO"
  echo "CYPRESS-WEB-RUN: web-dir $WEB ($DIRTY)"
  echo "CYPRESS-WEB-RUN: head $GIT_HEAD $GIT_BRANCH"
  echo "CYPRESS-WEB-RUN: package-lock sha256:${LOCK_HASH:-unknown}"
  echo "CYPRESS-WEB-RUN: phases ${PHASES[*]}"
  case " ${PHASES[*]} " in
    *" install "*) ;;
    # Read back by verify_web_test_log.sh and repeated in its verdict. A warm tree is a
    # legitimate way to run this and an illegitimate thing to certify a dependency graph from.
    *) echo "CYPRESS-WEB-RUN: INSTALL SKIPPED — node_modules was whatever this checkout already had" ;;
  esac
  echo "CYPRESS-WEB-RUN: ---"
} >"$LOG"

run_phase() {
  local name="$1"; shift
  echo "CYPRESS-WEB-RUN: phase-begin $name :: $*" >>"$LOG"
  echo "==> $name" >&2
  "$@" >>"$LOG" 2>&1
  local rc=$?
  echo "CYPRESS-WEB-RUN: phase-end $name status=$rc" >>"$LOG"
  return $rc
}

# **Every phase runs, whatever the one before it did**, and that is the same argument as
# `fail-fast: false` on the UI shard matrix in testflight.yml: the point of a gate is to learn
# everything that is wrong in one run. A typecheck error that stops the suite from running turns
# two findings into one and costs a whole round to discover the second.
WORST=0
for phase in "${PHASES[@]}"; do
  case "$phase" in
    install)   run_phase install   npm ci ;;
    typecheck) run_phase typecheck npm run typecheck ;;
    test)      run_phase test      npm test ;;
    build)     run_phase build     npm run build ;;
  esac
  rc=$?
  [ "$rc" -gt "$WORST" ] && WORST=$rc
done

# **The terminus.** Absent from any log whose run was killed, timed out, or died between
# phases — which is precisely the artifact that has been read as a pass on this project before.
# `verify_web_test_log.sh` refuses a log without it, so a truncated log cannot be mistaken for a
# short one.
echo "CYPRESS-WEB-RUN: phases-complete ${PHASES[*]}" >>"$LOG"
echo "CYPRESS-WEB-RUN: finished $(date '+%Y-%m-%d %H:%M:%S %Z')" >>"$LOG"

# The judgment, and its status carried through rather than flattened — the same handoff
# run_tests.sh makes. If the verifier and the exit codes disagree, the verifier wins, because the
# verifier read the log.
"$HERE/verify_web_test_log.sh" "$LOG" 5
VERIFY_RC=$?
[ "$VERIFY_RC" -eq 0 ] || exit "$VERIFY_RC"
exit "$WORST"
