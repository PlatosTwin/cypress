#!/bin/bash
# Run the Cypress suite against a simulator with a fresh log, then judge the log honestly.
# Prints VERIFY-OK/<pass line> or VERIFY-FAIL/<reason> — believe that line, never the exit
# code of any wrapper around this script.
#
# Usage: Tools/run_tests.sh <udid> <log-path> [extra xcodebuild args…]
#   e.g. Tools/run_tests.sh EA0AD796-… /path/dd-me/unit.log -only-testing:CypressTests
#
# Escape hatch: CYPRESS_RUN_TESTS_SKIP_PREFLIGHT=1 skips the collision and device-state
# refusals below. It does NOT skip the log header, which records that it was used — a log
# produced with the guards off says so, on its own face.
#
# What it mechanizes (docs/investigations/repeat-failures-postmortem.md):
# - rm -f of the log first: a stale log at a reused path once nearly reported a clean
#   suite from an 8-hour-old run.
# - a stamped header: every log carries its own provenance — device, screen width, worktree,
#   HEAD, and the device state that E202 showed can turn a healthy app into 33 red tests.
# - a collision refusal: a dead agent's xcodebuild keeps running, and a second run against the
#   same simulator or the same worktree fakes "app is not running" / "never appeared" /
#   "Test run with 0 tests" with no crash report (CLAUDE.md, simulators).
# - a device-state refusal (E202, E216): a leftover `active-city` marker survives reinstall; a
#   remembered `map.lastCamera` too wide for THIS screen draws cluster badges where a test
#   waits for tree pins; and a camera narrow enough but pointed at a patch of the city the
#   inventory does not cover draws nothing at all, which is the same symptom from the opposite
#   geometry. Whether the device HAS a fix is still deliberately NOT checked — a fixless or
#   location-denied device is a legitimate configuration and two tests skip on it (#121). What
#   is checked is a good fix in the wrong place, which is neither of those states.
# - bootstatus -b before anything: simctl against a Shutdown device fails quietly in && chains.
# - camera grant: the unit suite hangs forever on a simulator that never granted camera.
# - verify_test_log.sh at the end: the only judgment that counts.

set -u
UDID="${1:?usage: run_tests.sh <udid> <log-path> [xcodebuild args…]}"
LOG="${2:?usage: run_tests.sh <udid> <log-path> [xcodebuild args…]}"
shift 2

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
APP_ID=app.cypress.Cypress
SKIP_PREFLIGHT="${CYPRESS_RUN_TESTS_SKIP_PREFLIGHT:-0}"

refuse() { echo "VERIFY-FAIL: $1" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Collision guard — before booting anything.
#
# Deliberately no `grep` and no `[x]codebuild`: under zsh an unquoted bracket pattern
# glob-expands, matches nothing, and the check passes vacuously (which is exactly how one
# agent's collision check silently did nothing). Bash string matching over `ps` output has
# no pattern, no subshell, and nothing to self-match — `ps`'s own argv is `ps -eo …`.
# ---------------------------------------------------------------------------
collision_check() {
  local pid cmd hits=""
  while read -r pid cmd; do
    [ -n "${pid:-}" ] || continue
    [ "$pid" = "$$" ] && continue
    case "$cmd" in *xcodebuild*) ;; *) continue ;; esac
    # The worktree test matches the *project path*, not the repo root. `$REPO` alone is a
    # prefix of every sibling worktree — main is `…/cypress` and the agents' are
    # `…/cypress-w8b`, `…/cypress-w8c` — so `*"$REPO"*` made a run from main refuse
    # whenever any agent was building. Verified live against two running agents before the
    # fix; the guard was blocking the orchestrator, not a collision.
    case "$cmd" in
      *"$UDID"*)                   hits+="  pid $pid — same simulator ($UDID)"$'\n' ;;
      *"$REPO/Cypress.xcodeproj"*) hits+="  pid $pid — same worktree ($REPO)"$'\n' ;;
    esac
  done < <(ps -eo pid=,command=)
  if [ -n "$hits" ]; then
    printf 'VERIFY-FAIL: an xcodebuild is already live against this simulator or worktree:\n%s' "$hits" >&2
    echo "  Two runs on one device fake 'is not running' / 'never appeared' / 'Test run with 0 tests'." >&2
    echo "  Inspect with: ps -eo pid,lstart,command | grep -F xcodebuild" >&2
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# Screen width in points, measured from the device type's own profile — never a table of
# remembered numbers. It is stamped in the header (family 4: no suite can go green while
# never having been run narrow without the log admitting it) and it is the divisor in the
# camera threshold below, because clustering is a function of width, not of zoom alone.
# ---------------------------------------------------------------------------
DEVICE_NAME=""; SCREEN_PX=""; SCREEN_SCALE=""; SCREEN_PT=""
read_screen() {
  local dev_plist="$HOME/Library/Developer/CoreSimulator/Devices/$UDID/device.plist"
  local type_id profile b
  type_id="$(/usr/libexec/PlistBuddy -c 'Print :deviceType' "$dev_plist" 2>/dev/null)" || return 1
  DEVICE_NAME="${type_id##*.SimDeviceType.}"
  # Fast path: the profile bundle is almost always named for the identifier's tail.
  profile="/Library/Developer/CoreSimulator/Profiles/DeviceTypes/${DEVICE_NAME//-/ }.simdevicetype"
  if [ ! -f "$profile/Contents/Resources/profile.plist" ]; then
    profile=""
    for b in /Library/Developer/CoreSimulator/Profiles/DeviceTypes/*.simdevicetype; do
      if [ "$(plutil -extract CFBundleIdentifier raw "$b/Contents/Info.plist" 2>/dev/null)" = "$type_id" ]; then
        profile="$b"; break
      fi
    done
    [ -n "$profile" ] || return 1
  fi
  DEVICE_NAME="$(basename "$profile" .simdevicetype)"
  local p="$profile/Contents/Resources/profile.plist"
  SCREEN_PX="$(/usr/libexec/PlistBuddy -c 'Print :mainScreenWidth' "$p" 2>/dev/null)" || return 1
  SCREEN_SCALE="$(/usr/libexec/PlistBuddy -c 'Print :mainScreenScale' "$p" 2>/dev/null)" || return 1
  SCREEN_PT="$(awk -v w="$SCREEN_PX" -v s="$SCREEN_SCALE" 'BEGIN{ if (s>0) printf "%d", w/s }')"
  [ -n "$SCREEN_PT" ] && [ "$SCREEN_PT" -gt 0 ] 2>/dev/null
}

# ---------------------------------------------------------------------------
# Device state (E202). Both leftovers survive `xcodebuild test`, which replaces the app
# bundle and leaves the data container alone.
# ---------------------------------------------------------------------------
ACTIVE_CITY="none"; LAST_CAMERA="none"; CAMERA_ZOOM=""
read_device_state() {
  local container
  container="$(xcrun simctl get_app_container "$UDID" "$APP_ID" data 2>/dev/null)" || container=""
  if [ -z "$container" ]; then
    ACTIVE_CITY="n/a (app not installed)"; LAST_CAMERA="n/a (app not installed)"; return 0
  fi
  local marker="$container/Library/Application Support/Cypress/cities/active-city"
  if [ -f "$marker" ]; then
    ACTIVE_CITY="$(tr -d '\n' <"$marker")"
    [ -n "$ACTIVE_CITY" ] || ACTIVE_CITY="<empty marker file>"
  fi
  local prefs="$container/Library/Preferences/$APP_ID.plist"
  local raw
  raw="$(/usr/libexec/PlistBuddy -c 'Print :map.lastCamera' "$prefs" 2>/dev/null)" || return 0
  # Four doubles: latitude, longitude, latitude span, longitude span (MapCameraMemory.encode).
  local vals
  vals="$(printf '%s\n' "$raw" | awk '/^[[:space:]]*-?[0-9]/ {gsub(/[[:space:]]/,""); print}')"
  [ "$(printf '%s\n' "$vals" | grep -c .)" -eq 4 ] || return 0
  LAST_CAMERA="$(printf '%s\n' "$vals" | paste -sd, -)"
  local lat_span; lat_span="$(printf '%s\n' "$vals" | sed -n '3p')"
  local lon_span; lon_span="$(printf '%s\n' "$vals" | sed -n '4p')"
  # MapZoom.level: zoom = log2(360 · viewWidth / (256 · Δlon)), floored. MapViewport clusters
  # at zoom ≤ 15 and draws individual pins at ≥ 16, so the pin threshold on THIS screen is
  # Δlon ≤ 360·W/(256·2^16). Screen 01's map is full-bleed, so viewWidth is the screen width.
  CAMERA_ZOOM="$(awk -v d="$lon_span" -v w="$SCREEN_PT" 'BEGIN{
    if (d<=0 || w<=0) { print ""; exit }
    z = int(log(360*w/(256*d))/log(2));
    if (z>21) z=21; if (z<1) z=1; print z }')"
  count_camera_trees "$(printf '%s\n' "$vals" | sed -n '1p')" \
                     "$(printf '%s\n' "$vals" | sed -n '2p')"
}

# E216: a camera can be narrow enough for pins and still point somewhere the inventory does not
# cover. Screen 01 reopens on the remembered camera, draws nothing, and `cityTreePins(app) > 0`
# waits thirty seconds for a pin that was never coming — two red tests that name the map and read
# exactly like a defect in whatever you just changed. The coordinate was already stamped in every
# header; nothing read it against the seed.
#
# Counted over a fixed ±250 m box around the camera's CENTRE, not over the camera's own rectangle.
# The first draft used the rectangle, on the reasoning that it is what the map draws — and it
# refused a device that runs the full suite green, which is a worse failure than the one it
# prevents. Measured on the healthy 16 Pro at [37.759602,-122.426903]:
#
#     ±60 m   0 trees      ±150 m  177     ±300 m  889
#     ±100 m  45           ±200 m  342     ±500 m  2,573
#
# versus the treeless Golden Gate Park fix at [37.769402,-122.486198]: 0 at every radius out to
# ±300 m, and 198 only at ±500 m. So a camera can sit on a genuinely covered block and still hold
# no tree inside its own 120 m rectangle — the map pans, and the tests navigate. What separates
# the two states cleanly is the coarser question, and that is the one asked here: **is this part
# of the city covered by the inventory at all.** 250 m is chosen to sit inside the gap those two
# columns leave, not to model the viewport, and this comment says so because a threshold whose
# justification is lost becomes a number nobody dares change.
CAMERA_TREES="n/a"
count_camera_trees() {
  local lat="$1" lon="$2"
  local seed="$REPO/Cypress/Resources/cypress-seed.sqlite"
  command -v sqlite3 >/dev/null 2>&1 || { CAMERA_TREES="n/a (no sqlite3)"; return 0; }
  # Not an error: `setup_worktree.sh` copies the git-ignored seed in, and a worktree without it
  # already fails 13 tests for its own reasons. Say so rather than refuse on the wrong grounds.
  [ -f "$seed" ] || { CAMERA_TREES="n/a (no seed in this worktree)"; return 0; }
  local box
  box="$(awk -v la="$lat" -v lo="$lon" 'BEGIN{
    pi = 3.14159265358979;
    dlat = 250 / 111320;
    dlon = 250 / (111320 * cos(la * pi / 180));
    printf "%.6f %.6f %.6f %.6f", la-dlat, la+dlat, lo-dlon, lo+dlon }')"
  set -- $box
  CAMERA_TREES="$(sqlite3 "$seed" \
    "SELECT count(*) FROM trees WHERE lat BETWEEN $1 AND $2 AND lon BETWEEN $3 AND $4;" \
    2>/dev/null)" || CAMERA_TREES="n/a (seed unreadable)"
}

device_state_check() {
  case "$ACTIVE_CITY" in
    none|"n/a"*) ;;
    *)
      echo "VERIFY-FAIL: this device has city '$ACTIVE_CITY' selected (E202-A)." >&2
      echo "  Every San-Francisco deep link honestly returns 0 records; 33 of 64 UI tests read as a broken map." >&2
      echo "  The marker survives reinstall. Clear it with:" >&2
      echo "    rm -f \"\$(xcrun simctl get_app_container $UDID $APP_ID data)/Library/Application Support/Cypress/cities/active-city\"" >&2
      exit 1 ;;
  esac
  if [ -n "$CAMERA_ZOOM" ] && [ "$CAMERA_ZOOM" -lt 16 ]; then
    echo "VERIFY-FAIL: this device remembers a map camera too wide for its own screen (E202-B)." >&2
    echo "  map.lastCamera = [$LAST_CAMERA] → zoom $CAMERA_ZOOM at ${SCREEN_PT} pt; pins need zoom ≥ 16." >&2
    echo "  Screen 01 reopens there and draws cluster badges, so cityTreePins(app) > 0 is never true." >&2
    echo "  Clear it with the app not running, or it is rewritten on exit:" >&2
    echo "    /usr/libexec/PlistBuddy -c 'Delete :map.lastCamera' \"\$(xcrun simctl get_app_container $UDID $APP_ID data)/Library/Preferences/$APP_ID.plist\"" >&2
    exit 1
  fi
  # Zero is the only refusing value. "n/a …" means the question could not be asked — a fresh
  # install with no remembered camera, or a worktree without the seed — and an unasked question
  # must not read as an answered one, so it is stamped in the header either way.
  if [ "$CAMERA_TREES" = "0" ]; then
    echo "VERIFY-FAIL: this device's map camera points somewhere the inventory does not cover (E216)." >&2
    echo "  map.lastCamera = [$LAST_CAMERA] → zoom $CAMERA_ZOOM, and the seed holds 0 trees within 250 m of it." >&2
    echo "  Screen 01 reopens there and draws nothing, so tests waiting on a tree pin time out after 30 s." >&2
    echo "  This is NOT a missing fix — a fixless device is fine and #121's tests skip on it. It is a" >&2
    echo "  good fix in a place SF's street-tree inventory has no rows for (Golden Gate Park, the" >&2
    echo "  Presidio, Lake Merced, the ocean, anywhere outside the two shipped cities)." >&2
    echo "  Move the fix onto covered ground and relaunch the app once so it rewrites the camera:" >&2
    echo "    xcrun simctl location $UDID set 37.7596,-122.4269" >&2
    exit 1
  fi
}

# ---------------------------------------------------------------------------

rm -f "$LOG"

[ "$SKIP_PREFLIGHT" = "1" ] || collision_check

xcrun simctl bootstatus "$UDID" -b || refuse "simulator $UDID did not boot"
# Grant is idempotent when already granted and the app is not yet running for this test pass.
xcrun simctl privacy "$UDID" grant camera "$APP_ID" 2>/dev/null || true

read_screen || { DEVICE_NAME="${DEVICE_NAME:-unknown}"; SCREEN_PT=""; }
read_device_state

# Refuse before the log exists, so a refused run leaves no half-log to mistake for a run.
[ "$SKIP_PREFLIGHT" = "1" ] || device_state_check

{
  echo "CYPRESS-RUN: started $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo "CYPRESS-RUN: device ${DEVICE_NAME:-unknown} $UDID"
  echo "CYPRESS-RUN: screen-width-pt ${SCREEN_PT:-unknown} (${SCREEN_PX:-?} px @ ${SCREEN_SCALE:-?}x)"
  echo "CYPRESS-RUN: worktree $REPO"
  echo "CYPRESS-RUN: head $(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo unknown)" \
       "$(git -C "$REPO" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')"
  echo "CYPRESS-RUN: device-state active-city=${ACTIVE_CITY} map.lastCamera=[${LAST_CAMERA}]${CAMERA_ZOOM:+ zoom=$CAMERA_ZOOM} camera-trees=${CAMERA_TREES}"
  echo "CYPRESS-RUN: args $*"
  [ "$SKIP_PREFLIGHT" = "1" ] && echo "CYPRESS-RUN: PREFLIGHT SKIPPED (CYPRESS_RUN_TESTS_SKIP_PREFLIGHT=1) — guards did not run"
  echo "CYPRESS-RUN: ---"
} >"$LOG"

xcodebuild test \
  -project "$REPO/Cypress.xcodeproj" \
  -scheme Cypress \
  -destination "platform=iOS Simulator,id=$UDID" \
  "$@" >>"$LOG" 2>&1
XCODE_EXIT=$?

"$HERE/verify_test_log.sh" "$LOG" 5 || exit 1
exit $XCODE_EXIT
