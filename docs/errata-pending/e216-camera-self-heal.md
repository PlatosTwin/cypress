### `Tools/run_tests.sh` computes a safe camera instead of refusing a bad one (task #225)

*UNNUMBERED — the orchestrator splices the number at merge.*

*Built and calibrated 2026-08-04, iPhone 16 Plus `24D1629F-9FA8-4E3D-812E-F6BC85C9E668`, worktree at
commit `1fb0e6a` (`origin/release/0.2`), branch `tools/e216-compute-safe-camera`.*

---

#### What this mechanizes

E216's "worth mechanizing, not done here" note: `run_tests.sh` already knew the camera and the
worktree, and already refused a `map.lastCamera` too wide for the screen (E202-B) or narrow but
pointed at ground the seed's street-tree inventory does not cover (E216). Both used to stop and hand
the operator a manual repair command. They no longer do — the script now computes a covered,
correctly-narrow camera **from the seed itself** and writes it, then re-checks its own work before
proceeding.

**Only the CAMERA class heals.** The collision guard (another live `xcodebuild` against this
simulator or worktree) and the E202-A `active-city` marker check are untouched and still REFUSE —
both are a live-collision signal ("something else is using this device right now" / "this device is
reading the wrong city"), not a camera fact, and there is no safe value to compute on the operator's
behalf for either. Only `Tools/run_tests.sh` changed; no Swift file in this diff.

#### Where the camera comes from

The center is **derived from the seed at run time**, never a literal coordinate: `compute_safe_camera`
bins every row of `trees` onto a ~0.002° (~220 m) grid (`GROUP BY CAST(lat/0.002 AS INT), CAST(lon/0.002
AS INT)`), keeps the densest bin, and uses that bin's own `avg(lat), avg(lon)` as the center. A
hardcoded point goes stale the day the seed changes (the repo's standing lesson, CLAUDE.md); a query
against the seed that is already sitting in the worktree does not. On the seed present at HEAD the
densest bin holds 288 trees at `(37.7589434178774, -122.495377405412)` — nowhere near
`MapLayout.defaultCenter` (Dolores Park, the app's own hardcoded fallback, which the app's own
comments already document as having *no* trees inside its own 120 m view) — and a ±250 m box around it
holds 834, comfortably clear of the E216 gate.

The span is `MapLayout.defaultSpanMeters` (120 m, `Cypress/Features/Map/MapKitBasemap.swift`)
converted to degrees the same way `MKCoordinateRegion(center:latitudinalMeters:longitudinalMeters:)`
does — the app's own narrow default, not a number invented for this script. At 120 m that computes to
zoom ≈18 on every device profile this repo runs on, comfortably clear of the pin threshold of 16, so
it is not solved per-screen-width; it is *checked* per-screen-width anyway (see below) rather than
trusted on the strength of the arithmetic alone.

`write_safe_camera` writes the four doubles into `map.lastCamera` with `PlistBuddy` — the same tool
every other read and repair in this script already uses, not `defaults write`, which goes through
`cfprefsd` and this script has no standing dependency on that cache being warm. It also moves the
device's location fix to the same point (`xcrun simctl location … set`), so a reader who launches the
app by hand after a healed run sees the same covered ground the suite was healed onto.

`heal_camera` then **re-reads device state through the same functions `device_state_check` already
trusts** (`read_device_state` → `count_camera_trees`) and refuses if the computed camera does not
itself clear both gates — the only convergence proof worth having is the one asked in the instrument's
own voice, not a fresh assertion invented for this path.

#### Legibility in the log (E202-B's own lesson)

E202-B's finding was that a skip count that changed between two runs of the same tree is reporting a
device change, not a code change, and the log has to say so on its own face. A healed run now stamps:

    CYPRESS-RUN: camera-auto-healed yes reason=E202-B too-wide before={…} after={… (densest-bin n=288)}

An untouched run stamps `camera-auto-healed no`. The `device-state` line already carries the
**post-heal** values (the header is written after `device_state_check` returns), so the two lines
together answer both "what does this run's camera behave like" and "was it touched to get there."

#### Calibration (CLAUDE.md: prove the instrument before trusting the reading)

All three planted on the same device, `Tools/run_tests.sh` run un-mutated (no
`CYPRESS_RUN_TESTS_SKIP_PREFLIGHT`), predicted the camera in advance, then read it back.

**(a) A known-bad wide camera** — the exact E202 postmortem literal
`[37.065701, -122.166977, 1.659115, 1.065655]` (zoom 9) planted by hand. Predicted in advance from the
seed query above: center `(37.758942, -122.495377)`, zoom 18. Ran:

    camera too wide for its own screen (E202-B): map.lastCamera = [37.065701,-122.166977,1.659115,1.065655] →
      zoom 9 at 430 pt; pins need zoom ≥ 16. Healing…
    CYPRESS-RUN: device-state active-city=none map.lastCamera=[37.758942,-122.495377,0.001078,0.001364] zoom=18 camera-trees=834
    CYPRESS-RUN: camera-auto-healed yes reason=E202-B too-wide
      before={map.lastCamera=[37.065701,-122.166977,1.659115,1.065655] zoom=9 camera-trees=0}
      after={map.lastCamera=[37.758942,-122.495377,0.001078,0.001364] zoom=18 camera-trees=834 (densest-bin n=288)}
    VERIFY-OK: ✔ Test run with 6 tests in 1 suite passed after 1.282 seconds.

Set camera matched the prediction to the digit; the run proceeded to a real `xcodebuild test` and
finished green.

**(b) A narrow camera over uncovered ground** — E216's own literal, Golden Gate Park,
`[37.769402, -122.486198, 0.001081, 0.001362]` (zoom 18, confirmed 0 trees within ±250 m by direct
`sqlite3` query first). Ran:

    camera over uncovered ground (E216): map.lastCamera = [37.769402,-122.486198,0.001081,0.001362] →
      zoom 18, and the seed holds 0 trees within 250 m of it. Healing…
    CYPRESS-RUN: camera-auto-healed yes reason=E216 uncovered
      before={map.lastCamera=[37.769402,-122.486198,0.001081,0.001362] zoom=18 camera-trees=0}
      after={map.lastCamera=[37.758942,-122.495377,0.001078,0.001364] zoom=18 camera-trees=834 (densest-bin n=288)}
    VERIFY-OK: ✔ Test run with 6 tests in 1 suite passed after 1.046 seconds.

Same predicted camera, same convergence, distinct reason string — proof the two gates are still being
told apart, not collapsed into one generic "bad camera" heal.

**(c) A live-collision condition** — planted the E202-A marker (`echo -n "us-ca-sj" >
…/cities/active-city`) and ran the identical command:

    VERIFY-FAIL: this device has city 'us-ca-sj' selected (E202-A).
      Every San-Francisco deep link honestly returns 0 records; 33 of 64 UI tests read as a broken map.
      The marker survives reinstall. Clear it with:
        rm -f "$(xcrun simctl get_app_container … data)/Library/Application Support/Cypress/cities/active-city"
    SCRIPT-EXIT=1

Exit 1, no log file written (refused before the log exists, unchanged from before this ticket) — the
collision class still refuses, byte-for-byte the same message as before this diff.

#### End-to-end: a real full suite, judged by `verify_test_log.sh`

    CYPRESS-RUN: device-state active-city=n/a (app not installed) map.lastCamera=[n/a (app not installed)] camera-trees=n/a
    CYPRESS-RUN: camera-auto-healed no
    VERIFY-NOTE: XCTest skipped=0 — a change in this number between two runs of the same tree is a device change, not a code change (E216)
    VERIFY-OK: ✔ Test run with 1192 tests in 118 suites passed after 120.320 seconds. |
      XCTest: Executed 87 tests, with 0 failures (0 unexpected) in 1207.045 (1211.529) seconds

(Fresh install on this run, so nothing needed healing — `camera-auto-healed no` is the honest answer,
not a gap in coverage; (a)/(b) above are what exercise the heal path itself.)

#### A dead end this ticket ran into and ruled out, in case it recurs

The first full-suite attempt on this device (still holding a camera from repeated calibration writes,
not freshly erased) failed three `CypressUITests/MapSuggestionUITests` cases with device-state-shaped
symptoms ("a suggestion is drawn before anything has been typed" on a just-launched app; a tapped row
not updating the field; a tapped `Done` not closing the list). Before assigning any of that to this
diff: the same three cases reproduced **identically running bare `xcodebuild test` with no
`run_tests.sh` involved at all**, which this diff cannot influence one way or the other. Per CLAUDE.md's
simulator-degradation note, `xcrun simctl erase` on the same device cleared it — the rerun above is
post-erase and fully green. `MapSuggestionUITests` itself documents that it is deliberately
camera/viewport-independent, which is consistent with the cause being device degradation rather than
this ticket's change. Worth knowing if `MapSuggestionUITests` goes red again on a reused simulator: it
has now done so once for reasons this ticket traced to the device, not to any diff.
