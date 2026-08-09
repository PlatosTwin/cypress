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
# - a device-state refusal (E202-A): a leftover `active-city` marker survives reinstall and
#   points every San-Francisco deep link at the wrong inventory. This one still REFUSES — it is
#   a live collision with a prior smoke/run, the same family as the xcodebuild collision above,
#   and there is no "correct" city to pick on the operator's behalf.
# - a device-state SELF-HEAL (E202-B, E216, #225): a remembered `map.lastCamera` too wide for
#   THIS screen draws cluster badges where a test waits for tree pins, and a camera narrow
#   enough but pointed at a patch of the city the inventory does not cover draws nothing at
#   all — the same symptom from the opposite geometry. Both used to refuse and hand the
#   operator a manual repair command. They no longer do: the script computes a covered,
#   correctly-narrow camera from the seed itself (`compute_safe_camera`), writes it
#   (`write_safe_camera`), re-reads the device state to confirm it converged, and proceeds.
#   Whether the device HAS a fix is still deliberately NOT checked — a fixless or
#   location-denied device is a legitimate configuration and two tests skip on it (#121). What
#   is healed is a good fix in the wrong place, which is neither of those states. A healed run
#   says so in its own header (`CYPRESS-RUN: camera-auto-healed`), so a log reader can tell an
#   auto-healed run from an untouched one without diffing two runs (E202-B's own lesson).
# - a camera NORMALIZATION (#71): the two heals above name known-bad geometries and certify
#   everything else, which let through a camera that is narrow, covered, and still breaks
#   `DeepLinkVoiceOverTests.testPinAdjust` on contact. So the remaining rule admits exactly one
#   camera — the app's own `MapLayout.defaultCenter`, read out of the app's source — and replaces
#   anything else with it. A device already there is untouched. See the long comment on that
#   branch in `device_state_check` for the mechanism and for what the rule does not claim.
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
ACTIVE_CITY="none"; LAST_CAMERA="none"; CAMERA_ZOOM=""; CONTAINER=""
# The remembered camera's four numbers, kept apart from the display string so the checks below
# can do arithmetic on them rather than re-splitting the header line they print.
CAM_LAT=""; CAM_LON=""; CAM_LAT_SPAN=""; CAM_LON_SPAN=""
read_device_state() {
  local container
  container="$(xcrun simctl get_app_container "$UDID" "$APP_ID" data 2>/dev/null)" || container=""
  CONTAINER="$container"
  LAST_CAMERA="none"; CAMERA_ZOOM=""; CAMERA_TREES="n/a"
  CAM_LAT=""; CAM_LON=""; CAM_LAT_SPAN=""; CAM_LON_SPAN=""
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
  CAM_LAT="$(printf '%s\n' "$vals" | sed -n '1p')"
  CAM_LON="$(printf '%s\n' "$vals" | sed -n '2p')"
  CAM_LAT_SPAN="$(printf '%s\n' "$vals" | sed -n '3p')"
  CAM_LON_SPAN="$(printf '%s\n' "$vals" | sed -n '4p')"
  local lat_span; lat_span="$CAM_LAT_SPAN"
  local lon_span; lon_span="$CAM_LON_SPAN"
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
# Counted over a fixed ±250 m box around the camera's CENTER, not over the camera's own rectangle.
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
SEED="$REPO/Cypress/Resources/cypress-seed.sqlite"

# The question above, asked of any coordinate and ANSWERED ON STDOUT — a plain integer, or empty
# when it could not be asked. Split out from `count_camera_trees` (#71) because the safe-camera
# computation below now needs to ask it of a candidate it is considering, and a helper that can
# only write to one global cannot be asked twice.
trees_within_250m() {
  local lat="$1" lon="$2" box
  command -v sqlite3 >/dev/null 2>&1 || return 1
  [ -f "$SEED" ] || return 1
  box="$(awk -v la="$lat" -v lo="$lon" 'BEGIN{
    pi = 3.14159265358979;
    dlat = 250 / 111320;
    dlon = 250 / (111320 * cos(la * pi / 180));
    printf "%.6f %.6f %.6f %.6f", la-dlat, la+dlat, lo-dlon, lo+dlon }')"
  set -- $box
  sqlite3 "$SEED" \
    "SELECT count(*) FROM trees WHERE lat BETWEEN $1 AND $2 AND lon BETWEEN $3 AND $4;" 2>/dev/null
}

count_camera_trees() {
  local lat="$1" lon="$2" n
  command -v sqlite3 >/dev/null 2>&1 || { CAMERA_TREES="n/a (no sqlite3)"; return 0; }
  # Not an error: `setup_worktree.sh` copies the git-ignored seed in, and a worktree without it
  # already fails 13 tests for its own reasons. Say so rather than refuse on the wrong grounds.
  [ -f "$SEED" ] || { CAMERA_TREES="n/a (no seed in this worktree)"; return 0; }
  n="$(trees_within_250m "$lat" "$lon")" && [ -n "$n" ] || { CAMERA_TREES="n/a (seed unreadable)"; return 0; }
  CAMERA_TREES="$n"
}

# ---------------------------------------------------------------------------
# The app's own opening camera, READ OUT OF THE APP'S SOURCE (#71).
#
# `MapLayout.defaultCenter` / `.defaultSpanMeters` are where screen 01 opens with nothing
# remembered, they are the coordinate E216 names as its repair, and they are the anchor
# `DebugDeepLink.center` resolves every deep-linked fixture from. Parsed rather than copied,
# for the reason CLAUDE.md gives about the schema-version bullet that spent a round being wrong:
# a literal in this script goes stale the day the app moves its default and nothing tells anyone.
# ---------------------------------------------------------------------------
APP_DEFAULT_LAT=""; APP_DEFAULT_LON=""; APP_DEFAULT_SPAN_M=""
read_app_default_camera() {
  local src="$REPO/Cypress/Features/Map/MapKitBasemap.swift"
  [ -f "$src" ] || return 1
  APP_DEFAULT_LAT="$(sed -n 's/.*defaultCenter *= *Coordinate(latitude: *\(-\{0,1\}[0-9.]*\).*/\1/p' "$src" | head -1)"
  APP_DEFAULT_LON="$(sed -n 's/.*defaultCenter *= *Coordinate(latitude: *-\{0,1\}[0-9.]*, *longitude: *\(-\{0,1\}[0-9.]*\).*/\1/p' "$src" | head -1)"
  APP_DEFAULT_SPAN_M="$(sed -n 's/.*defaultSpanMeters *: *CLLocationDistance *= *\([0-9.]*\).*/\1/p' "$src" | head -1)"
  [ -n "$APP_DEFAULT_LAT" ] && [ -n "$APP_DEFAULT_LON" ] && [ -n "$APP_DEFAULT_SPAN_M" ]
}

# Is the remembered camera the app's own default, near enough that writing it again would be a
# no-op? Center within `CAMERA_CENTER_TOLERANCE_M`, and span within half to double the app's.
#
# The tolerance absorbs MapKit's own readback drift and nothing more: a device left at the
# default reads back `37.759602,-122.426903` against a source that says `37.7596,-122.4269`
# (~0.2 m), with spans of 0.001081/0.001362 against a computed 0.001078/0.001363. It is NOT a
# claim that everything inside 50 m is equally good — it is the width of "the same camera".
CAMERA_CENTER_TOLERANCE_M=50
camera_is_app_default() {
  [ -n "$CAM_LAT" ] && [ -n "$CAM_LON" ] && [ -n "$CAM_LON_SPAN" ] || return 1
  [ -n "$APP_DEFAULT_LAT" ] || return 1
  awk -v la="$CAM_LAT" -v lo="$CAM_LON" -v dlon="$CAM_LON_SPAN" \
      -v ra="$APP_DEFAULT_LAT" -v ro="$APP_DEFAULT_LON" -v m="$APP_DEFAULT_SPAN_M" \
      -v tol="$CAMERA_CENTER_TOLERANCE_M" 'BEGIN{
    pi = 3.14159265358979;
    dy = (la - ra) * 111320;
    dx = (lo - ro) * 111320 * cos(ra * pi / 180);
    if (sqrt(dx*dx + dy*dy) > tol) exit 1;
    want = m / (111320 * cos(ra * pi / 180));
    if (want <= 0 || dlon <= 0) exit 1;
    r = dlon / want;
    if (r < 0.5 || r > 2) exit 1;
    exit 0 }'
}

# ---------------------------------------------------------------------------
# #225 / E216 "worth mechanizing": compute a camera instead of just refusing a bad one.
#
# Only the CAMERA class heals (E202-B too wide, E216 pointed at nothing). The collision guard
# above and the E202-A `active-city` check below are a live-collision signal, not a camera
# fact — there is no safe value to compute on the operator's behalf for "another xcodebuild is
# using this simulator" or "this device is reading San Jose", so both keep refusing untouched.
#
# The center is DERIVED FROM THE SEED at run time, never a literal coordinate: bin every tree
# onto a ~0.002°  (~220 m) grid, keep the densest bin, and use that bin's own centroid. A
# hardcoded point goes stale the day the seed changes (CLAUDE.md); a query does not. The span
# is `MapLayout.defaultSpanMeters` (120 m, Cypress/Features/Map/MapKitBasemap.swift) converted
# to degrees the same way `MKCoordinateRegion(center:latitudinalMeters:longitudinalMeters:)`
# does — the app's own narrow default, not a number invented for this script. At 120 m that
# span computes to zoom ≈18 for every device profile this repo runs on (all comfortably ≥ the
# pin threshold of 16), so it does not need to be solved per-screen-width to clear the E202-B
# gate; it is checked anyway below rather than trusted.
# ---------------------------------------------------------------------------
SAFE_LAT=""; SAFE_LON=""; SAFE_LAT_SPAN=""; SAFE_LON_SPAN=""; SAFE_TREES=""; SAFE_SOURCE=""
compute_safe_camera() {
  command -v sqlite3 >/dev/null 2>&1 || return 1
  [ -f "$SEED" ] || return 1
  SAFE_LAT=""; SAFE_LON=""; SAFE_TREES=""; SAFE_SOURCE=""
  local span_m=120

  # First choice, and the only one that matters in practice: the app's own opening default
  # (#71). Preferred over the densest bin because it is the camera the suite is known green on
  # and the anchor `DebugDeepLink` resolves fixtures from — a heal that lands somewhere else,
  # however tree-rich, still leaves the map and the fixtures looking at different parts of the
  # city. Taken only if the seed actually covers it, so a city whose inventory does not reach
  # the app's default still gets a working camera rather than a principled empty one.
  if read_app_default_camera; then
    span_m="$APP_DEFAULT_SPAN_M"
    local n
    n="$(trees_within_250m "$APP_DEFAULT_LAT" "$APP_DEFAULT_LON")"
    if [ -n "${n:-}" ] && [ "$n" -gt 0 ] 2>/dev/null; then
      SAFE_LAT="$APP_DEFAULT_LAT"; SAFE_LON="$APP_DEFAULT_LON"; SAFE_TREES="$n"
      SAFE_SOURCE="app default center (MapLayout.defaultCenter)"
    fi
  fi

  # Fallback: the densest ~220 m bin in the seed, derived at run time and never a literal.
  if [ -z "$SAFE_LAT" ]; then
    local row
    row="$(sqlite3 -separator '|' "$SEED" "
      SELECT avg(lat), avg(lon), count(*)
        FROM trees
       GROUP BY CAST(lat/0.002 AS INT), CAST(lon/0.002 AS INT)
       ORDER BY count(*) DESC
       LIMIT 1;
    " 2>/dev/null)" || return 1
    [ -n "$row" ] || return 1
    SAFE_LAT="$(printf '%s' "$row" | awk -F'|' '{print $1}')"
    SAFE_LON="$(printf '%s' "$row" | awk -F'|' '{print $2}')"
    SAFE_TREES="$(printf '%s' "$row" | awk -F'|' '{print $3}')"
    SAFE_SOURCE="densest seed bin"
  fi
  [ -n "$SAFE_LAT" ] && [ -n "$SAFE_LON" ] || return 1
  read -r SAFE_LAT_SPAN SAFE_LON_SPAN <<<"$(awk -v la="$SAFE_LAT" -v m="$span_m" 'BEGIN{
    pi = 3.14159265358979
    printf "%.8f %.8f", m/111320, m/(111320*cos(la*pi/180)) }')"
  [ -n "$SAFE_LAT_SPAN" ] && [ -n "$SAFE_LON_SPAN" ]
}

# Writes the computed camera into the app's own preferences file (same encoding
# `MapCameraMemory.encode` uses: four doubles, lat/lon/latSpan/lonSpan, MapOpeningCamera.swift)
# and moves the device's location fix to the same point, so a reader who launches the app by
# hand sees the same covered ground the suite was healed onto. Uses PlistBuddy, matching every
# other read/repair in this script — not `defaults write`, which goes through cfprefsd and this
# script already has no dependency on that cache being warm or cold.
write_safe_camera() {
  [ -n "$CONTAINER" ] || return 1
  local prefs="$CONTAINER/Library/Preferences/$APP_ID.plist"
  mkdir -p "$(dirname "$prefs")" 2>/dev/null || true
  [ -f "$prefs" ] || plutil -create xml1 "$prefs" 2>/dev/null || return 1
  /usr/libexec/PlistBuddy -c "Delete :map.lastCamera" "$prefs" >/dev/null 2>&1
  /usr/libexec/PlistBuddy -c "Add :map.lastCamera array" "$prefs" >/dev/null 2>&1 || return 1
  local v
  for v in "$SAFE_LAT" "$SAFE_LON" "$SAFE_LAT_SPAN" "$SAFE_LON_SPAN"; do
    /usr/libexec/PlistBuddy -c "Add :map.lastCamera: real $v" "$prefs" >/dev/null 2>&1 || return 1
  done
  xcrun simctl location "$UDID" set "$SAFE_LAT,$SAFE_LON" >/dev/null 2>&1
  return 0
}

CAMERA_HEALED="no"; CAMERA_HEAL_REASON=""; CAMERA_BEFORE=""; CAMERA_AFTER=""
# Computes, writes, then re-reads device state through the SAME functions `device_state_check`
# trusts (`read_device_state` → `count_camera_trees`) — the only convergence proof worth having
# is the one asked in the instrument's own voice, not a fresh assertion invented for this path.
heal_camera() {
  local reason="$1"
  CAMERA_BEFORE="map.lastCamera=[${LAST_CAMERA}]${CAMERA_ZOOM:+ zoom=$CAMERA_ZOOM} camera-trees=${CAMERA_TREES}"
  compute_safe_camera || refuse "camera heal ($reason): could not derive a safe camera from the seed."
  write_safe_camera || refuse "camera heal ($reason): could not write the computed camera to the device."
  read_device_state
  if [ -n "$CAMERA_ZOOM" ] && [ "$CAMERA_ZOOM" -lt 16 ]; then
    refuse "camera heal ($reason): computed camera is still too wide after healing — zoom $CAMERA_ZOOM."
  fi
  if [ "$CAMERA_TREES" = "0" ]; then
    refuse "camera heal ($reason): computed camera still finds 0 seed trees within 250 m after healing."
  fi
  # #71: when the heal aimed at the app's own default, converge on that too — otherwise the very
  # next run re-reads the device, finds a camera that is still not the default, and heals again,
  # forever, with every log claiming a repair that did not take.
  case "$SAFE_SOURCE" in
    "app default"*)
      camera_is_app_default || refuse \
        "camera heal ($reason): wrote the app's default camera but the device still reads back [${LAST_CAMERA}], which is not it." ;;
  esac
  CAMERA_HEALED="yes"
  CAMERA_HEAL_REASON="$reason"
  CAMERA_AFTER="map.lastCamera=[${LAST_CAMERA}]${CAMERA_ZOOM:+ zoom=$CAMERA_ZOOM} camera-trees=${CAMERA_TREES} (source=${SAFE_SOURCE}, n=${SAFE_TREES})"
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
  # #225: both camera refusals below now SELF-HEAL instead of exiting. Neither is a live
  # collision — nothing else is touching this device — so there is a safe value to compute and
  # no reason to hand it to the operator by hand.
  if [ -n "$CAMERA_ZOOM" ] && [ "$CAMERA_ZOOM" -lt 16 ]; then
    echo "camera too wide for its own screen (E202-B): map.lastCamera = [$LAST_CAMERA] →" \
         "zoom $CAMERA_ZOOM at ${SCREEN_PT} pt; pins need zoom ≥ 16. Healing…" >&2
    heal_camera "E202-B too-wide"
  # Zero is the only refusing value. "n/a …" means the question could not be asked — a fresh
  # install with no remembered camera, or a worktree without the seed — and an unasked question
  # must not read as an answered one, so it is stamped in the header either way. A worktree with
  # no seed cannot heal either (`compute_safe_camera` needs the same file), so that case still
  # reaches `heal_camera`, which then refuses with a clear reason rather than looping silently.
  elif [ "$CAMERA_TREES" = "0" ]; then
    echo "camera over uncovered ground (E216): map.lastCamera = [$LAST_CAMERA] → zoom" \
         "$CAMERA_ZOOM, and the seed holds 0 trees within 250 m of it. Healing…" >&2
    heal_camera "E216 uncovered"
  # ── The rule that replaces certification with normalization (task #71) ────────────────────
  #
  # THE DEFECT THIS CLOSES. Both branches above name a KNOWN-BAD geometry and pass everything
  # else. A stored camera of [37.759899,-122.414803] at zoom 18 with 501 seed trees inside 250 m
  # satisfies both, was stamped `camera-trees=501 / camera-auto-healed no` — and
  # `DeepLinkVoiceOverTests.testPinAdjust` fails on it, every time, reproduced here on the 16 Pro:
  #
  #     Failed to determine hittability of "City tree, Southern Magnolia" Button:
  #     Activation point invalid and no suggested hit points based on element frame
  #
  # The mechanism is not about that camera's own geometry at all. Screen 18 is presented OVER the
  # map tab root, so screen 01's annotations stay in the accessibility tree behind it, drawn at
  # whatever `map.lastCamera` says — and `DeepLinkHarness.assertEveryControlIsLabeled` reads
  # `isHittable` on every button in the app, background pins included. An annotation the remembered
  # camera happens to place where XCUITest can compute no activation point raises, rather than
  # answering false. Which cameras do that is a fact about MapKit's layout of a particular block,
  # not something a rule can enumerate: this was the THIRD geometry after "too wide" (E202-B) and
  # "over nothing" (E216), and there is no reason to think it is the last.
  #
  # So the burden is inverted. Instead of listing bad cameras and certifying the rest — a blacklist,
  # which is exactly the "guard green precisely when its condition is present" shape CLAUDE.md
  # warns about — exactly one camera is admitted: the app's own opening default, which is where a
  # fresh install opens, where E216's repair points, and the anchor `DebugDeepLink` resolves every
  # deep-linked fixture from. Anything else is REPLACED with it before the suite runs.
  #
  # WHAT THIS DOES AND DOES NOT CLAIM. It does not claim the default camera can serve any test —
  # nothing in a shell script can know that. It claims something weaker and checkable: every run
  # starts from ONE known camera, the one the suite is green on, instead of inheriting whichever
  # of infinitely many the last run happened to leave. A result that moves between two runs of the
  # same tree is then a device change somewhere else, not here.
  #
  # It is not a refusal of everything, either — a device already at the default is left untouched
  # and stamps `camera-auto-healed no`, which is the ordinary case on a healthy machine and in CI
  # (where the app is not yet installed and there is no camera to normalize).
  elif [ -n "$CAM_LAT" ] && read_app_default_camera && ! camera_is_app_default; then
    echo "camera is not the app's own opening default (#71): map.lastCamera = [$LAST_CAMERA] →" \
         "zoom $CAMERA_ZOOM, camera-trees=$CAMERA_TREES — narrow and covered, and still not a" \
         "state the suite is known green on. Normalizing onto" \
         "${APP_DEFAULT_LAT},${APP_DEFAULT_LON}…" >&2
    heal_camera "#71 not the app default"
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
  # #225: legible on its own face whether this device's camera was touched — E202-B's own
  # lesson is that a skip-count (or here, a camera) that changed between two runs of the same
  # tree is reporting a device change, not a code change, and must not be silent about it.
  if [ "$CAMERA_HEALED" = "yes" ]; then
    echo "CYPRESS-RUN: camera-auto-healed yes reason=${CAMERA_HEAL_REASON} before={${CAMERA_BEFORE}} after={${CAMERA_AFTER}}"
  else
    echo "CYPRESS-RUN: camera-auto-healed no"
  fi
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
