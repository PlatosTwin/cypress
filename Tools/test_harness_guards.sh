#!/bin/bash
# Calibrate the shell guards in Tools/ against cases whose answers are already known.
#
# Usage: Tools/test_harness_guards.sh          (runs everything; ~40 s)
#        Tools/test_harness_guards.sh <substring>   (only checks whose name contains it)
#
# WHY THIS FILE EXISTS. `Tools/run_tests.sh`, `Tools/verify_test_log.sh` and
# `Tools/fetch_seed.sh` are how every claim in this repository is verified, and they are the one
# part of it with no test target: `CypressTests` runs on a simulator and cannot execute a shell
# script, and the checks that read `Tools/` from Swift (`UITestShardCoverageTests`,
# `DeployPathsAgreeTests`) read those files as TEXT. CLAUDE.md names the gap out loud — "this
# project's tooling is gated; the commands you type to make claims about that tooling are not" —
# and every guard below was written after a wrong conclusion drawn from one of them.
#
# So each check here constructs the failing condition deliberately and asserts what the script
# does with it, and every one is paired with a CONTROL: the healthy case, or the refusal that
# must keep refusing. A guard proved only on the case it was written for is a guard that could be
# passing vacuously, which is this project's dominant test-suite defect.
#
# It touches no simulator, builds nothing, and takes no network: the process table is substituted
# by defining a shell function named `ps` (bash resolves a function before an external command),
# and the one download is served from a local `python3 -m http.server` over 127.0.0.1.
#
# NOT a replacement for running the suite. It proves the guards; only `Tools/run_tests.sh` on a
# device proves the app.

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
FILTER="${1:-}"
WORK="$(mktemp -d -t cypress-harness-guards)"
trap 'rm -rf "$WORK"; jobs -p | xargs kill 2>/dev/null' EXIT

PASSED=0
FAILED=0
SKIPPED=0
CURRENT=""

check() {
  CURRENT="$1"
  case "$CURRENT" in *"$FILTER"*) return 0 ;; esac
  return 1
}
ok()   { PASSED=$((PASSED + 1)); printf '  ok   %s\n' "$CURRENT"; }
bad()  { FAILED=$((FAILED + 1)); printf '  FAIL %s\n         %s\n' "$CURRENT" "$1"; }
skip() { SKIPPED=$((SKIPPED + 1)); printf '  skip %s — %s\n' "$CURRENT" "$1"; }

# `expect_contains <haystack> <needle>` / `expect_missing` / `expect_rc`, each naming what it
# looked for when it fails. A failing assertion that does not print the text it judged sends the
# reader back to run the thing by hand, which is where an afternoon goes.
expect_rc() {
  if [ "$1" = "$2" ]; then return 0; fi
  bad "expected exit $2, got $1"
  return 1
}
expect_contains() {
  case "$1" in *"$2"*) return 0 ;; esac
  bad "output does not contain '$2'. Output was:
$(printf '%s' "$1" | sed 's/^/         | /')"
  return 1
}
expect_missing() {
  case "$1" in
    *"$2"*)
      bad "output should NOT contain '$2'. Output was:
$(printf '%s' "$1" | sed 's/^/         | /')"
      return 1 ;;
  esac
  return 0
}

FAKE_UDID="00000000-DEAD-BEEF-0000-000000000000"

# ═══════════════════════════════════════════════════════════════════════════════════════════
# Part 1 — run_tests.sh's guards, driven directly.
#
# `CYPRESS_RUN_TESTS_LIB_ONLY=1 . run_tests.sh <udid> <log>` defines the functions and stops
# before the run. `ps` and `pid_is_live` are then redefined here, so every branch below is
# exercised against a process table whose answer is known rather than against whatever the
# machine happens to be doing while the test runs.
# ═══════════════════════════════════════════════════════════════════════════════════════════
CYPRESS_RUN_TESTS_SKIP_PREFLIGHT=0
export CYPRESS_RUN_TESTS_SKIP_PREFLIGHT
# shellcheck disable=SC1090
CYPRESS_RUN_TESTS_LIB_ONLY=1 . "$HERE/run_tests.sh" "$FAKE_UDID" "$WORK/unused.log"

if [ "$(type -t collision_check 2>/dev/null)" != "function" ]; then
  echo "FATAL: sourcing Tools/run_tests.sh did not define collision_check — the lib seam is broken." >&2
  exit 1
fi

PS_FIXTURE=""
ps() { printf '%s\n' "$PS_FIXTURE"; }
DEAD_PIDS=""
pid_is_live() { case " $DEAD_PIDS " in *" $1 "*) return 1 ;; esac; return 0; }

# The ancestor chain the fixtures share: this shell, a wrapper that mentions both `xcodebuild`
# and the UDID (E283's exact shape), and launchd.
WRAPPER_PID=90001
fixture_ancestors() {
  cat <<EOF
$$ $WRAPPER_PID 00:12 bash $HERE/test_harness_guards.sh
$WRAPPER_PID 1 00:20 zsh -c Tools/run_tests.sh $FAKE_UDID /tmp/x.log; ps aux | grep -F xcodebuild
1 0 10-01:02:03 /sbin/launchd
EOF
}

XCB="/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild"

echo "run_tests.sh — elapsed-time parsing"
if check "etime_seconds parses the four ps shapes"; then
  got="$(etime_seconds 05):$(etime_seconds 01:30):$(etime_seconds 02:00:00):$(etime_seconds 1-00:00:01)"
  if [ "$got" = "5:90:7200:86401" ]; then ok; else bad "expected 5:90:7200:86401, got $got"; fi
fi

echo "run_tests.sh — collision guard (E283, roadmap items (b) and (c))"

# THE DEFECT. Before this round the only excluded pid was `$$`, so the launching shell — which
# holds the UDID because it is the script's own first argument, and the word `xcodebuild` because
# an agent appends a `grep -F xcodebuild` to the same line — matched itself. Three consecutive
# refusals on 2026-09-02, each naming a pid that was gone a second later.
if check "(b) a wrapper shell that merely mentions xcodebuild is not a collision"; then
  PS_FIXTURE="$(fixture_ancestors)"
  DEAD_PIDS=""
  out="$(collision_check 2>&1)"; rc=$?
  expect_rc "$rc" 0 && expect_contains "${out}(no output)" "(no output)" && ok
fi

# THE CONTROL. The same guard, the same fixture, plus one genuine foreign build. It must still
# refuse — a fix for a false positive that removes the true positive is worse than the bug.
if check "(b) control: a real foreign xcodebuild on the same simulator still refuses"; then
  PS_FIXTURE="$(fixture_ancestors)
9991 1 00:30 $XCB test -project /elsewhere/Cypress.xcodeproj -destination platform=iOS Simulator,id=$FAKE_UDID"
  DEAD_PIDS=""
  out="$(collision_check 2>&1)"; rc=$?
  expect_rc "$rc" 1 \
    && expect_contains "$out" "pid 9991" \
    && expect_contains "$out" "same simulator" \
    && expect_missing "$out" "pid $WRAPPER_PID" \
    && ok
fi

if check "(b) control: a real foreign xcodebuild on the same worktree still refuses"; then
  PS_FIXTURE="$(fixture_ancestors)
9992 1 00:44 $XCB test -project $REPO/Cypress.xcodeproj -destination platform=iOS Simulator,id=SOMEONE-ELSE"
  DEAD_PIDS=""
  out="$(collision_check 2>&1)"; rc=$?
  expect_rc "$rc" 1 && expect_contains "$out" "same worktree" && ok
fi

# `nohup xcodebuild …&` has argv[0] `nohup`. E283 offered "require the command to start with an
# xcodebuild binary path" as an alternative fix; this is the case that rules it out, and it is
# pinned here so that nobody re-introduces it as a tidy-up.
if check "(b) a build launched under nohup is still detected (argv[0] is not xcodebuild)"; then
  PS_FIXTURE="$(fixture_ancestors)
9993 1 03:00 nohup $XCB test -destination platform=iOS Simulator,id=$FAKE_UDID"
  DEAD_PIDS=""
  out="$(collision_check 2>&1)"; rc=$?
  expect_rc "$rc" 1 && expect_contains "$out" "pid 9993" && ok
fi

if check "(c) a pid that exited between the scan and the verdict is reported, not refused on"; then
  PS_FIXTURE="$(fixture_ancestors)
9991 1 00:30 $XCB test -destination platform=iOS Simulator,id=$FAKE_UDID"
  DEAD_PIDS="9991"
  out="$(collision_check 2>&1)"; rc=$?
  expect_rc "$rc" 0 && expect_contains "$out" "had already exited" && ok
fi

if check "(c) a young hit is named as the tail of a wrapper that just returned"; then
  PS_FIXTURE="$(fixture_ancestors)
9991 1 00:30 $XCB test -destination platform=iOS Simulator,id=$FAKE_UDID"
  DEAD_PIDS=""
  out="$(collision_check 2>&1)"; rc=$?
  expect_rc "$rc" 1 \
    && expect_contains "$out" "running 00:30 (30s)" \
    && expect_contains "$out" "OUTLIVES" \
    && expect_contains "$out" "WAIT for it" \
    && ok
fi

if check "(c) an old hit is named as a live build or an orphan, not as a tail"; then
  PS_FIXTURE="$(fixture_ancestors)
9991 1 02:00:00 $XCB test -destination platform=iOS Simulator,id=$FAKE_UDID"
  DEAD_PIDS=""
  out="$(collision_check 2>&1)"; rc=$?
  expect_rc "$rc" 1 \
    && expect_contains "$out" "running 02:00:00 (7200s)" \
    && expect_contains "$out" "older than" \
    && expect_missing "$out" "OUTLIVES" \
    && ok
fi

echo "run_tests.sh — concurrency count (roadmap item (d))"
if check "(d) the load count counts real invocations and not mentions of the word"; then
  PS_FIXTURE="$(fixture_ancestors)
9991 1 00:30 $XCB test -destination platform=iOS Simulator,id=AAA
9992 1 00:31 $XCB test -destination platform=iOS Simulator,id=BBB
9993 1 00:32 bash -c echo xcodebuild is a word in this command line
9994 1 00:33 /usr/bin/swift-frontend -c /tmp/dd/xcodebuild-ish/File.swift"
  DEAD_PIDS=""
  take_ps_snapshot; read_ancestors
  got="$(count_live_xcodebuilds)"
  if [ "$got" = "2" ]; then ok; else bad "expected 2 live xcodebuilds, got '$got'"; fi
fi

echo "run_tests.sh — bootstatus (roadmap item (a))"
if check "(a) a leftover simctl bootstatus against this device is refused, with its age"; then
  PS_FIXTURE="$(fixture_ancestors)
9995 1 41:07 /usr/bin/xcrun simctl bootstatus $FAKE_UDID -b"
  DEAD_PIDS=""
  out="$(boot_device 2>&1)"; rc=$?
  expect_rc "$rc" 1 \
    && expect_contains "$out" "pid 9995" \
    && expect_contains "$out" "(2467s)" \
    && expect_contains "$out" "wedged" \
    && ok
fi

if check "(a) control: a bootstatus against a DIFFERENT device is not this device's problem"; then
  PS_FIXTURE="$(fixture_ancestors)
9995 1 41:07 /usr/bin/xcrun simctl bootstatus SOME-OTHER-DEVICE -b"
  DEAD_PIDS=""
  # `bootstatus_watchers` alone: `boot_device` would go on to really boot a device that does not
  # exist, which is a different question from the one this check asks.
  take_ps_snapshot; read_ancestors
  out="$(bootstatus_watchers)"
  if [ -z "$out" ]; then ok; else bad "matched another device's bootstatus: $out"; fi
fi

if check "(a) control: our own launching shell is not mistaken for a leftover bootstatus"; then
  PS_FIXTURE="$(fixture_ancestors)
$WRAPPER_PID 1 00:20 zsh -c xcrun simctl bootstatus $FAKE_UDID -b; Tools/run_tests.sh $FAKE_UDID /tmp/x.log"
  DEAD_PIDS=""
  take_ps_snapshot; read_ancestors
  out="$(bootstatus_watchers)"
  if [ -z "$out" ]; then ok; else bad "matched an ancestor: $out"; fi
fi

# Restore the real process table BEFORE the bound is exercised, and this ordering is itself a
# receipt. Run with the fixture still installed, `bounded_run` reported 124 and left the `sleep`
# behind: the kill walks the process tree by asking `ps` for children, and the fixture answered
# "nobody". That is a guard reading a substituted instrument and certifying a repair it did not
# make — the same shape as everything else in this file, arrived at from the wrong side. The
# fixture belongs to the guards that reason about OTHER processes; the bound kills a real one.
unset -f ps
unset -f pid_is_live

echo "run_tests.sh — the bound itself"
# 3007 rather than a round number: `pgrep -f` searches every process on a shared machine, and a
# check that can be answered by somebody else's `sleep 300` is not a check.
BOUND_SLEEP=3007
if check "(a) bounded_run kills a command that never returns and reports 124"; then
  marker="$WORK/bounded-marker"
  start="$(date +%s)"
  bounded_run 2 bash -c "echo running >'$marker'; sleep $BOUND_SLEEP"; rc=$?
  elapsed=$(( $(date +%s) - start ))
  if [ "$rc" != "124" ]; then
    bad "expected 124, got $rc"
  elif [ "$elapsed" -gt 12 ]; then
    bad "the bound took ${elapsed}s to fire against a 2s limit"
  elif [ ! -f "$marker" ]; then
    bad "the command never started, so the timeout proves nothing"
  else
    # And the child is actually gone — a bound that returns while the process keeps running is
    # the leftover this round exists to stop creating, and it is what the guard would then refuse
    # on next time.
    sleep 1
    if pgrep -f "sleep $BOUND_SLEEP" >/dev/null 2>&1; then
      bad "bounded_run returned 124 but left 'sleep $BOUND_SLEEP' running"
    else
      ok
    fi
  fi
fi

if check "(a) control: bounded_run passes a fast command's own status through"; then
  bounded_run 10 true; a=$?
  bounded_run 10 false; b=$?
  bounded_run 10 bash -c 'exit 7'; c=$?
  if [ "$a:$b:$c" = "0:1:7" ]; then ok; else bad "expected 0:1:7, got $a:$b:$c"; fi
fi

# ═══════════════════════════════════════════════════════════════════════════════════════════
# Part 2 — run_tests.sh end to end, as a real process.
#
# Part 1 drove the functions. These two run the actual script, because the seam that lets Part 1
# work is itself a thing that can be wrong: a guard that passes when called by hand and never
# runs in the real path is the shape CLAUDE.md warns about.
# ═══════════════════════════════════════════════════════════════════════════════════════════
echo "run_tests.sh — end to end"

FAKEBIN="$WORK/fakebin"
mkdir -p "$FAKEBIN"
cat >"$FAKEBIN/xcrun" <<'FAKE'
#!/bin/bash
# A CoreSimulator that has wedged: `bootstatus` never returns; everything else answers at once.
for a in "$@"; do
  if [ "$a" = "bootstatus" ]; then sleep 600; fi
done
exit 1
FAKE
chmod +x "$FAKEBIN/xcrun"

if check "(a) end to end: a wedged bootstatus is bounded, and the refusal says what to do"; then
  start="$(date +%s)"
  out="$(PATH="$FAKEBIN:$PATH" CYPRESS_BOOTSTATUS_TIMEOUT_S=3 \
         "$HERE/run_tests.sh" "$FAKE_UDID" "$WORK/e2e-a.log" 2>&1)"; rc=$?
  elapsed=$(( $(date +%s) - start ))
  if [ "$elapsed" -gt 60 ]; then
    bad "took ${elapsed}s against a 3s bound — the bound is not bounding"
  else
    expect_rc "$rc" 1 \
      && expect_contains "$out" "did not return within 3s" \
      && expect_contains "$out" "What it was waiting for" \
      && expect_contains "$out" "simctl erase" \
      && expect_contains "$out" "CYPRESS_BOOTSTATUS_TIMEOUT_S" \
      && ok
  fi
fi

# E283 end to end: the launching command line holds both `xcodebuild` and the UDID. The run must
# now get PAST the collision guard — which it proves by failing at the next step instead, on the
# fake xcrun, with a different message. "It failed differently" is the assertion, because "it
# failed" is what the defect looked like too.
if check "(b) end to end: a caller whose own command line says 'xcodebuild' is not a collision"; then
  out="$(PATH="$FAKEBIN:$PATH" CYPRESS_BOOTSTATUS_TIMEOUT_S=3 bash -c \
         "'$HERE/run_tests.sh' '$FAKE_UDID' '$WORK/e2e-b.log' 2>&1; echo rc=\$? # xcodebuild")"
  expect_contains "$out" "rc=1" \
    && expect_missing "$out" "already live against this simulator" \
    && expect_contains "$out" "bootstatus" \
    && ok
fi

if check "the lib seam refuses rather than exiting 0 when the file is executed, not sourced"; then
  out="$(CYPRESS_RUN_TESTS_LIB_ONLY=1 "$HERE/run_tests.sh" "$FAKE_UDID" "$WORK/libonly.log" 2>&1)"; rc=$?
  expect_rc "$rc" 1 && expect_contains "$out" "only means anything when this file is SOURCED" && ok
fi

# ═══════════════════════════════════════════════════════════════════════════════════════════
# Part 3 — verify_test_log.sh's three verdicts (roadmap item (d)).
#
# Synthetic logs, each one line different from the next, so that what separates the verdicts is
# visible in the fixture rather than argued about in prose.
# ═══════════════════════════════════════════════════════════════════════════════════════════
echo "verify_test_log.sh — pass, red, and environment refusal"

write_log() {
  local path="$1"; shift
  {
    echo "CYPRESS-RUN: started $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "CYPRESS-RUN: device iPhone-16-Pro-Max FAKE"
    echo "CYPRESS-RUN: screen-width-pt 430 (1290 px @ 3.000000x)"
    echo "CYPRESS-RUN: concurrent-xcodebuilds 2 (besides this run; the cap is 3 machine-wide)"
    echo "CYPRESS-RUN: ---"
    printf '%s\n' "$@"
  } >"$path"
}

SYNTH_TIMEOUT="<unknown>:0: error: -[CypressUITests.MapSearchTests testTypingNarrows] : Failed to get matching snapshot: Timed out while synthesizing event."
SYNTH_ASSERT="/Users/x/CypressUITests/MapSearchTests.swift:88: error: -[CypressUITests.MapSearchTests testTypingNarrows] : XCTAssertTrue failed - the result list never narrowed"

if check "(d) a run whose every failure is an event-synthesis timeout exits 2"; then
  write_log "$WORK/env.log" \
    "Test Case '-[CypressUITests.MapSearchTests testTypingNarrows]' started." \
    "$SYNTH_TIMEOUT" \
    "Executed 3 tests, with 1 failure (0 unexpected) in 12.0 (12.1) seconds" \
    "** TEST FAILED **"
  out="$("$HERE/verify_test_log.sh" "$WORK/env.log" 2>&1)"; rc=$?
  expect_rc "$rc" 2 \
    && expect_contains "$out" "VERIFY-ENV-REFUSED" \
    && expect_contains "$out" "Concurrent xcodebuilds when this run started: 2" \
    && expect_missing "$out" "VERIFY-OK" \
    && ok
fi

if check "(d) control: a genuine assertion failure is still a red, exit 1"; then
  write_log "$WORK/red.log" \
    "Test Case '-[CypressUITests.MapSearchTests testTypingNarrows]' started." \
    "$SYNTH_ASSERT" \
    "Executed 3 tests, with 1 failure (0 unexpected) in 12.0 (12.1) seconds" \
    "** TEST FAILED **"
  out="$("$HERE/verify_test_log.sh" "$WORK/red.log" 2>&1)"; rc=$?
  expect_rc "$rc" 1 \
    && expect_contains "$out" "VERIFY-FAIL" \
    && expect_missing "$out" "VERIFY-ENV-REFUSED" \
    && ok
fi

# The one that matters most: an environment refusal must never be able to carry a real failure
# out of the log with it. One assertion among the timeouts makes the whole run a red.
if check "(d) control: a real failure ALONGSIDE a timeout is a red, not an environment refusal"; then
  write_log "$WORK/mixed.log" \
    "Test Case '-[CypressUITests.MapSearchTests testTypingNarrows]' started." \
    "$SYNTH_TIMEOUT" \
    "$SYNTH_ASSERT" \
    "Executed 3 tests, with 2 failures (0 unexpected) in 12.0 (12.1) seconds" \
    "** TEST FAILED **"
  out="$("$HERE/verify_test_log.sh" "$WORK/mixed.log" 2>&1)"; rc=$?
  expect_rc "$rc" 1 \
    && expect_contains "$out" "VERIFY-FAIL" \
    && expect_missing "$out" "VERIFY-ENV-REFUSED" \
    && ok
fi

if check "(d) control: a green log is still a pass, exit 0"; then
  write_log "$WORK/green.log" \
    "Test Case '-[CypressUITests.MapSearchTests testTypingNarrows]' started." \
    "Test Case '-[CypressUITests.MapSearchTests testTypingNarrows]' passed (2.0 seconds)." \
    "Executed 3 tests, with 0 failures (0 unexpected) in 12.0 (12.1) seconds" \
    "** TEST SUCCEEDED **"
  out="$("$HERE/verify_test_log.sh" "$WORK/green.log" 2>&1)"; rc=$?
  expect_rc "$rc" 0 \
    && expect_contains "$out" "VERIFY-OK" \
    && expect_contains "$out" "concurrent xcodebuilds at start: 2" \
    && ok
fi

# The completeness guards must still win. A killed run that happens to contain a synthesis
# timeout is incomplete first and environment-refused never — it has no terminal marker, so
# nothing is known about it at all.
if check "(d) control: an incomplete run is refused for being incomplete, not classified"; then
  write_log "$WORK/killed.log" \
    "Test Case '-[CypressUITests.MapSearchTests testTypingNarrows]' started." \
    "$SYNTH_TIMEOUT" \
    "** BUILD INTERRUPTED **"
  out="$("$HERE/verify_test_log.sh" "$WORK/killed.log" 2>&1)"; rc=$?
  expect_rc "$rc" 1 \
    && expect_contains "$out" "no terminal result marker" \
    && expect_missing "$out" "VERIFY-ENV-REFUSED" \
    && ok
fi

# ═══════════════════════════════════════════════════════════════════════════════════════════
# Part 4 — fetch_seed.sh's exit paths (ROADMAP chip 3).
#
# A real end-to-end fetch against a local HTTP server, so the failing condition is reached the
# way it is reached in life: through the download and the hash check, with the scope check as the
# last thing standing between a verified file and the copy.
# ═══════════════════════════════════════════════════════════════════════════════════════════
echo "fetch_seed.sh — every exit path names itself"

if ! command -v sqlite3 >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
  check "fetch_seed.sh checks" && skip "needs sqlite3 and python3"
else
  SERVE="$WORK/serve"
  mkdir -p "$SERVE"
  PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
  ( cd "$SERVE" && python3 -m http.server "$PORT" --bind 127.0.0.1 >/dev/null 2>&1 ) &
  SERVER_PID=$!
  # Wait for it rather than sleeping at it: a fixed sleep is how a check starts depending on how
  # loaded the machine is.
  for _ in $(seq 1 40); do
    curl -fsS "http://127.0.0.1:$PORT/" >/dev/null 2>&1 && break
    sleep 0.25
  done

  # `<name>` → a seed at $SERVE/<name>.sqlite and a root at $WORK/root-<name> whose pin names it.
  # `$2`, if given, is the value of seed_meta.id_spaces_in_file; absent means the row is missing,
  # which is the condition that used to kill the script in silence.
  make_seed_and_pin() {
    local name="$1" spaces="${2-}" claim="$3" file root sha bytes
    file="$SERVE/$name.sqlite"
    root="$WORK/root-$name"
    rm -f "$file"
    mkdir -p "$root/Fixtures/seed"
    sqlite3 "$file" "CREATE TABLE seed_meta(key TEXT PRIMARY KEY, value TEXT);"
    sqlite3 "$file" "INSERT INTO seed_meta VALUES('generated_at','2026-09-09T00:00:00Z');"
    if [ -n "${spaces}" ]; then
      sqlite3 "$file" "INSERT INTO seed_meta VALUES('id_spaces_in_file','$spaces');"
    fi
    sha="$(shasum -a 256 "$file" | cut -d' ' -f1)"
    bytes="$(wc -c <"$file" | tr -d ' ')"
    python3 - "$root/Fixtures/seed/pinned-seed.json" "$name.sqlite" "$sha" "$bytes" "$claim" <<'PY'
import json, sys
out, path, sha, size, claim = sys.argv[1:6]
json.dump({"path": path, "sha256": sha, "bytes": int(size),
           "id_spaces": claim.split(",")}, open(out, "w"), indent=2)
PY
    printf '%s' "$root"
  }

  run_fetch() {
    CYPRESS_CITIES_BASE="http://127.0.0.1:$PORT" "$HERE/fetch_seed.sh" "$1" 2>&1
  }

  # THE DEFECT ITSELF. `grep -v '^$'` selects nothing from an empty scope string, exits 1, and
  # `pipefail` + `set -e` take the script down inside a command substitution — no message, no
  # placed seed, exit 1. Before this round the assertion below was `output is empty`.
  if check "chip 3: an unreadable scope names itself instead of dying silently"; then
    root="$(make_seed_and_pin noscope "" "sf,sj")"
    out="$(run_fetch "$root")"; rc=$?
    expect_rc "$rc" 1 \
      && expect_contains "$out" "scope UNREADABLE" \
      && expect_contains "$out" "seed_meta" \
      && expect_missing "$out" "no diagnostic of its own" \
      && ok
  fi

  if check "chip 3: control — a scope that disagrees with the pin still refuses, as before"; then
    root="$(make_seed_and_pin wrongscope "nyc,sf,sj" "sf,sj")"
    out="$(run_fetch "$root")"; rc=$?
    expect_rc "$rc" 1 && expect_contains "$out" "scope mismatch" && ok
  fi

  if check "chip 3: control — a matching scope is confirmed and the seed is placed"; then
    root="$(make_seed_and_pin goodscope "sf,sj" "sf,sj")"
    out="$(run_fetch "$root")"; rc=$?
    expect_rc "$rc" 0 \
      && expect_contains "$out" "scope confirmed" \
      && expect_contains "$out" "verified sha256" \
      || true
    if [ "$rc" = "0" ] && [ -f "$root/Cypress/Resources/cypress-seed.sqlite" ] \
       && [ -f "$root/Fixtures/seed/cypress-seed.sqlite" ]; then
      ok
    elif [ "$rc" = "0" ]; then
      bad "exit 0 but the seed was not placed in both destinations"
    fi
  fi

  if check "chip 3: control — a hash mismatch keeps its own three-cause message"; then
    root="$(make_seed_and_pin badhash "sf,sj" "sf,sj")"
    python3 - "$root/Fixtures/seed/pinned-seed.json" <<'PY'
import json, sys
p = sys.argv[1]
pin = json.load(open(p))
pin["sha256"] = "0" * 64
json.dump(pin, open(p, "w"), indent=2)
PY
    out="$(run_fetch "$root")"; rc=$?
    expect_rc "$rc" 1 \
      && expect_contains "$out" "sha256 mismatch" \
      && expect_missing "$out" "no diagnostic of its own" \
      && ok
  fi

  # And the backstop itself, calibrated: a copy of the script with one silent-failure command
  # spliced in must produce the new "died with no diagnostic" report, naming the line. Without
  # this the trap is a claim; with it, it is a measurement.
  if check "chip 3: an unforeseen silent death is reported, with its line"; then
    poisoned="$WORK/fetch_seed_poisoned.sh"
    awk '{ print }
         /^say "resolved from \$origin"$/ { print "  printf \x27\x27 | grep -q nothing-here" }' \
      "$HERE/fetch_seed.sh" >"$poisoned"
    chmod +x "$poisoned"
    if ! grep -q 'nothing-here' "$poisoned"; then
      bad "the poison was not spliced in — the anchor line in fetch_seed.sh moved"
    else
      root="$(make_seed_and_pin poison "sf,sj" "sf,sj")"
      out="$(CYPRESS_CITIES_BASE="http://127.0.0.1:$PORT" "$poisoned" "$root" 2>&1)"; rc=$?
      expect_rc "$rc" 1 \
        && expect_contains "$out" "no diagnostic of its own" \
        && expect_contains "$out" "grep -q nothing-here" \
        && ok
    fi
  fi

  kill "$SERVER_PID" 2>/dev/null
  wait "$SERVER_PID" 2>/dev/null
fi

echo
printf 'harness guards: %d passed, %d failed, %d skipped\n' "$PASSED" "$FAILED" "$SKIPPED"
[ "$FAILED" -eq 0 ] || exit 1
[ "$PASSED" -gt 0 ] || { echo "nothing ran — a filter that matches nothing is not a pass" >&2; exit 1; }
exit 0
