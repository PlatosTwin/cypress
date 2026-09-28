#!/bin/bash
# Judge a `go test -json` stream from the sync service. Exit 0 only if every package that has
# tests ran at least one, nothing failed, and NOTHING SKIPPED.
#
# Why this exists: `go test ./...` prints `ok` for a package whose every test called `t.Skip`, and
# exits 0. With `CYPRESS_TEST_DATABASE_URL` unset the whole SQL half of this suite does exactly
# that — measured 67 pass / 134 skip / 0 fail at W-G's head — and the human output is
# indistinguishable from a real run. Every server change before this script was certified by
# someone standing up a throwaway Postgres and counting skips by hand (ROADMAP chip backlog 14).
#
# Why JSON rather than the `-v` text: Go indents a subtest's `--- PASS` / `--- SKIP` line, so an
# anchored `grep -c '^--- SKIP'` counts top-level tests only and under-reports by however many
# subtests there are. The JSON stream carries one event per test, subtests included, with the
# test's name in `Test` — nothing is inferred from indentation.
#
# Usage: server/ci/verify_test_json.sh <go-test-json-log>
#   Run it locally exactly as CI does:
#     cd server && CYPRESS_TEST_DATABASE_URL=… go test -json -count=1 ./... > /tmp/server.json
#     ci/verify_test_json.sh /tmp/server.json
#
# Exit status:
#   0  VERIFY-SERVER-OK    — tests ran, all passed, none skipped
#   1  VERIFY-SERVER-FAIL  — anything else, including a skip, zero passes, or a log that is not
#                            the complete stream of a run
#
# What it refuses, each on its own line of output so a red run says which:
#   * a missing or empty log;
#   * a line that is not JSON (a truncated write, or stderr mixed into stdout);
#   * any test-level `skip` event, top-level or subtest — the false green this exists to stop;
#   * any `fail` event, test-level or package-level (a build failure is a package-level fail);
#   * a package that `start`ed and never reported a terminal pass/fail/skip — a run cut short;
#   * a package that passed while running zero tests (a `TestMain` that exits early, a build tag
#     that hides every file) — `ok` with nothing behind it;
#   * a total pass count that is not positive.
#
# A package-level `skip` is `[no test files]` and is NOT refused: `server` (main) and `migrations`
# have none. They are listed, so a package that loses its tests shows up here as a new name.
set -uo pipefail

log="${1:-}"
fail() { echo "VERIFY-SERVER-FAIL: $*"; exit 1; }

command -v jq >/dev/null 2>&1 || fail "jq is not installed; this script cannot judge anything without it"
[ -n "$log" ] || fail "usage: $0 <go-test-json-log>"
[ -s "$log" ] || fail "log '$log' is missing or empty"

# Every line must be a JSON object. `try fromjson` rather than feeding the file to jq directly, so
# the count of bad lines is reported instead of jq stopping at the first one.
bad="$(jq -R -r 'try (fromjson | if type == "object" then empty else "x" end) catch "x"' "$log" | wc -l | tr -d ' ')"

count() { jq -s "$1" "$log" 2>/dev/null || echo "?"; }

test_pass="$(count '[.[] | select(.Test != null and .Action == "pass")] | length')"
test_fail="$(count '[.[] | select(.Test != null and .Action == "fail")] | length')"
test_skip="$(count '[.[] | select(.Test != null and .Action == "skip")] | length')"
pkg_fail="$(count '[.[] | select(.Test == null and .Action == "fail")] | length')"
top_skip="$(count '[.[] | select(.Test != null and .Action == "skip" and (.Test | contains("/") | not))] | length')"

echo "server tests: ${test_pass} passed, ${test_fail} failed, ${test_skip} skipped (${top_skip} of the skips top-level), ${pkg_fail} package failures, ${bad} non-JSON lines"

[ "$bad" = "0" ] || fail "${bad} line(s) are not JSON events — this is not the clean stdout of 'go test -json'"

# The skipped tests by name, before any verdict, so the red run's log says which.
if [ "$test_skip" != "0" ]; then
  echo "skipped:"
  jq -r 'select(.Test != null and .Action == "skip") | "  \(.Package | sub("^.*/server/?"; "")) \(.Test)"' "$log"
fi
if [ "$test_fail" != "0" ] || [ "$pkg_fail" != "0" ]; then
  echo "failed:"
  jq -r 'select(.Action == "fail") | "  \(.Package | sub("^.*/server/?"; "")) \(.Test // "(package)")"' "$log"
fi

# Per-package bookkeeping: started, terminal action, and how many tests passed inside it.
packages="$(jq -s -r '
  group_by(.Package)[] |
  {
    pkg: .[0].Package,
    started: any(.[]; .Action == "start"),
    terminal: ([.[] | select(.Test == null and (.Action == "pass" or .Action == "fail" or .Action == "skip")) | .Action] | last),
    passed: ([.[] | select(.Test != null and .Action == "pass")] | length)
  } | "\(.pkg)\t\(.started)\t\(.terminal // "none")\t\(.passed)"' "$log")"

unterminated=""; empty_pass=""; no_tests=""
while IFS=$'\t' read -r pkg started terminal passed; do
  [ -n "$pkg" ] || continue
  if [ "$terminal" = "none" ]; then unterminated="$unterminated $pkg"; fi
  if [ "$terminal" = "pass" ] && [ "$passed" = "0" ]; then empty_pass="$empty_pass $pkg"; fi
  if [ "$terminal" = "skip" ]; then no_tests="$no_tests $pkg"; fi
done <<< "$packages"

[ -z "$no_tests" ] || echo "packages with no test files (not a skip of any test):$no_tests"

[ "$test_skip" = "0" ] || fail "${test_skip} test(s) skipped — a skip is not a pass. If these are the SQL tests, CYPRESS_TEST_DATABASE_URL did not reach them"
[ "$test_fail" = "0" ] && [ "$pkg_fail" = "0" ] || fail "${test_fail} test failure(s), ${pkg_fail} package failure(s)"
[ -z "$unterminated" ] || fail "package(s) started and never finished — the run was cut short:$unterminated"
[ -z "$empty_pass" ] || fail "package(s) reported ok having run zero tests:$empty_pass"
case "$test_pass" in
  ''|*[!0-9]*) fail "could not count passes (got '$test_pass')" ;;
esac
[ "$test_pass" -gt 0 ] || fail "zero tests passed — zero tests run is not a pass"

echo "VERIFY-SERVER-OK: ${test_pass} passed, 0 skipped, 0 failed"
