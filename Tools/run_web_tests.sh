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
# contains this script's name). Everything it leaves is then asked WHICH CHECKOUT it belongs to,
# below, because the answer to that is what makes a process a collision rather than a neighbour.
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

# ── Which of those processes is a collision, and which is a neighbour ────────────────────────
# The hazard is two runs in the SAME CHECKOUT: `npm ci` wipes that checkout's `web/node_modules`,
# `astro build` writes that checkout's `web/dist`, and both would be doing it to each other. A run
# in a different worktree shares none of those paths and is not a collision. This guard used to
# refuse on ANY process anywhere whose argv contained this script's name, and assert in the
# refusal that the two "would share $WEB/node_modules" — a sharing relationship it had not
# established and which, for two different worktrees, was false. Worse than the wrong refusal was
# its shape: every refused agent retried, and each retry was itself a matching process refusing
# the others. Two independent reviewers deadlocked on it on 2026-09-10.
#
# So the test is `$REPO`, the same way `run_tests.sh:collision_check` keys on `$UDID` and on
# `$REPO/Cypress.xcodeproj` rather than on the word `xcodebuild` alone — and the same way, it
# carries the TRAILING SLASH that keeps a sibling out: `$REPO` bare is a PREFIX of every
# worktree named after it (`…/cypress` and `…/cypress-w8b`), which is the same prefix trap
# `collision_check` records paying for — matching on it would recreate this bug one worktree over.
#
# Two facts about a candidate can put it in this checkout, and EITHER is enough — they cover
# different invocation shapes, and a guard that demanded both would miss each of them:
#   * its command line names a path inside `$REPO` — the usual shape, an agent invoking the
#     script by absolute path;
#   * its working directory is inside `$REPO` — the shape with no absolute path in argv
#     (`Tools/run_web_tests.sh /tmp/web.log` from the repo root). It is also the STRONGER fact
#     during the dangerous window, because this script cd's into `$WEB` before any phase runs.
#
# `$REPO` is asked for in both its logical and its physical form, and that is not belt-and-braces:
# on macOS `/tmp` is a symlink to `/private/tmp`, so a worktree at `/tmp/x` has `$REPO` = `/tmp/x`
# (bash's `cd`+`pwd` are logical) while the kernel reports its processes' cwd as `/private/tmp/x`.
# Measured, not assumed — both forms appeared in the refusals that prompted this fix, in the same
# message. A comparison against one form silently never matches for half the worktrees on this
# machine, which is a guard that cannot fire: this project's dominant defect class.
REPO_PHYS="$(cd "$REPO" 2>/dev/null && pwd -P)"
[ -n "$REPO_PHYS" ] || REPO_PHYS="$REPO"

# The only way to ask what directory another process is sitting in. Absent or restricted `lsof`
# returns nothing, and the caller treats that as "cannot tell", never as "no conflict" — measured
# by running this guard with `lsof` off PATH against a collision it otherwise refuses: it printed
# the unplaced note and ran, rather than silently clearing the process.
cwd_of() {
  lsof -a -p "$1" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -1
}
# "$1 is $2, or below it." The trailing slash is the whole point; see above.
is_under() {
  case "$1" in "$2"|"$2"/*) return 0 ;; esac
  return 1
}

# Prints why this candidate conflicts and returns 0; returns 1 when it does not, and 2 when it
# could not be placed at all. The three are different answers and the caller treats them so.
conflict_reason() {
  local pid="$1" cmd="$2" cwd
  case "$cmd" in
    *"$REPO/"*|*"$REPO_PHYS/"*) echo "same checkout ($REPO) — its command line names a path inside it"; return 0 ;;
  esac
  # Deliberately kept from the version this replaces: two runs writing one log file clobber each
  # other's evidence even from different checkouts, and a log with two runs interleaved in it is
  # exactly the artifact this harness exists to prevent being read as one run.
  case "$cmd" in
    *"$LOG"*) echo "same log path ($LOG)"; return 0 ;;
  esac
  cwd="$(cwd_of "$pid")"
  [ -n "$cwd" ] || return 2
  if is_under "$cwd" "$REPO" || is_under "$cwd" "$REPO_PHYS"; then
    echo "same checkout ($REPO) — its working directory is $cwd"
    return 0
  fi
  return 1
}

HITS=""
UNPLACED=""
while IFS= read -r line; do
  [ -n "$line" ] || continue
  pid="$(printf '%s' "$line" | awk '{print $1}')"
  is_own_business "$pid" && continue
  cmd="$(printf '%s' "$line" | awk '{ $1 = ""; $2 = ""; sub(/^ +/, ""); print }')"
  why="$(conflict_reason "$pid" "$cmd")"
  case $? in
    0) HITS="${HITS}  pid $pid — $why"$'\n'"      $cmd"$'\n' ;;
    2) UNPLACED="${UNPLACED}  pid $pid — could not read its working directory, and its command line names no path in this checkout"$'\n'"      $cmd"$'\n' ;;
  esac
done <<EOF
$(printf '%s\n' "$PS_SNAPSHOT" | grep -F "run_web_tests.sh" || true)
EOF
if [ -n "$UNPLACED" ]; then
  # Said out loud rather than folded into either verdict: a guard that cannot place a process has
  # not cleared it, and the reader deserves the difference.
  printf 'CYPRESS-WEB-RUN: the collision guard could not place these processes and did NOT refuse on them:\n%s' "$UNPLACED" >&2
fi
if [ -n "$HITS" ]; then
  printf 'REFUSING: another run_web_tests.sh conflicts with this one:\n%s' "$HITS" >&2
  echo "  Two runs in one checkout collide: 'npm ci' deletes $WEB/node_modules out from under the" >&2
  echo "  other one mid-phase, and both write $WEB/dist. The symptom is a module-not-found naming a" >&2
  echo "  package that is plainly in the lockfile." >&2
  echo "  Wait for it, or run in a DIFFERENT worktree — a run in another checkout shares none of" >&2
  echo "  these paths and is not refused." >&2
  echo "  Inspect with: ps -eo pid,lstart,command | grep -F run_web_tests.sh" >&2
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
