### The camera guard certified a camera the tests cannot use, and a red CI run would not say what failed (task #71)

#### The occurrence

`DeepLinkVoiceOverTests.testPinAdjust`, on iPhone 16 Pro `EA0AD796-…` (402 pt), fails on contact:

    <unknown>:0: error: -[CypressUITests.DeepLinkVoiceOverTests testPinAdjust] :
    Failed to determine hittability of "City tree, Southern Magnolia" Button:
    Activation point invalid and no suggested hit points based on element frame

The only thing wrong with the device is its remembered `map.lastCamera`,
`[37.759899,-122.414803]` at zoom 18. `Tools/run_tests.sh` looked straight at that camera, stamped
`camera-trees=501` and `camera-auto-healed no` in the header, and ran the suite on it. This is
CLAUDE.md's own signature shape living inside the harness: **a guard reporting green precisely when
its condition is present.**

#### What the camera actually does, which is not what the E216 guard asks about

The E202-B and E216 branches ask two geometric questions of the remembered camera — is it narrow
enough for pins, and does the seed cover the ground under it. This camera answers both correctly.
The mechanism has nothing to do with its own geometry:

- Screen 18 (`pinAdjust`) is **presented over the map tab root**, not pushed — `DeepLinkVoiceOver
  Tests`'s own file comment says so. Screen 01's annotations therefore stay in the accessibility
  tree behind it, drawn at whatever `map.lastCamera` says.
- `DeepLinkHarness.assertEveryControlIsLabeled` walks `app.buttons` — **every button in the app**,
  background map pins included — and reads `element.isHittable` as its filter. An annotation the
  remembered camera happens to place where XCUITest can compute no activation point does not answer
  `false`; it **raises**, and the raise is the test failure.

Which cameras do that is a fact about MapKit's layout of one particular block. It is not a
geometry a rule can enumerate, and this was the *third* geometry after "too wide" (E202-B) and
"over nothing" (E216).

#### Two premises in the brief, checked rather than inherited

Both were wrong, and one of them would have sent the repair to the wrong place.

**"Only the stored camera differed."** The isolation run that passed came from a device that had
been *erased*, which clears the location fix as well as the camera. Ran the missing cell: bad camera
+ the good fix at `37.7596,-122.4269`. It fails **identically**, same species, same message. The fix
is not a variable here at all, and the reason is in the app: `DebugDeepLink.pinAdjustFix` anchors
screen 18 to `MapLayout.defaultCenter` unconditionally, so the pin screen's own contents do not move
with the device's location. Only the map *behind* it does.

That also disposes of one of the two repairs the brief floated — "validate the deep-link fixtures'
own targets fall within the computed camera". The fixtures resolve from a fixed anchor
(`DebugDeepLink.center = MapLayout.defaultCenter`) no matter where the camera is pointed, so there
is nothing there to validate.

**"CI never uploads the UI log."** It does, and it has since `47b7d12` (2026-08-03): `unit` and
every `ui` shard carry a `Keep the log, whatever happened` step with `if: always()`. The artifacts
are present on all four red runs checked (31294993494, 31291434427, 31241508337, 31229960422), and
`ui-1.log` from the first of those holds the full assertion — test name, source line, message.

The *symptom* was real all the same. What GitHub shows a reader in the failing job is:

    VERIFY-FAIL: ** TEST FAILED ** present

and nothing else. The evidence existed and cost a download, an unzip and a grep to reach, so three
red runs were written off as flake by people who never opened one. **A verdict a reader will not
act on is a verdict that does not count** — which is a different defect from the missing upload
that was reported, and it is fixed at `verify_test_log.sh` rather than in the workflow.

#### The repairs

**1. The guard normalizes instead of certifying (`Tools/run_tests.sh`).** The burden is inverted.
Rather than listing bad cameras and certifying the rest — a blacklist, which is the shape that
failed here — exactly one camera is admitted: the app's own `MapLayout.defaultCenter` at
`MapLayout.defaultSpanMeters`, **parsed out of `MapKitBasemap.swift` at run time**, never a literal
in the script. Anything else is replaced with it before the suite runs. `compute_safe_camera` now
prefers that point and keeps its densest-seed-bin computation as the fallback for a city whose
inventory does not reach the app's default.

What this claims is deliberately weaker than what the old header implied. It does **not** claim the
default camera can serve any given test; nothing in a shell script can know that. It claims that
every run starts from **one** known camera — the one the suite is green on — instead of inheriting
whichever of infinitely many the last run left behind. A result that then moves between two runs of
the same tree is a device change somewhere else, not here.

**2. A red verdict carries its own evidence (`Tools/verify_test_log.sh`).** `VERIFY-FAIL-DETAIL`
prints the failing test names and their messages — deduped, first 25, each clipped to 400 columns —
at all three failure verdicts (`** TEST FAILED **`, an XCTest `Executed … N failures` line, and a
Swift Testing failure). It appears in the CI job log, in a local run, and on every later re-read of
the artifact.

**3. Retention and result bundles (`.github/workflows/testflight.yml`).** The existing log uploads
gain `retention-days: 14` instead of the 90-day repository default — a CI log is read within days
of the run or never, and a two-month-old log under a familiar name is exactly what CLAUDE.md's
"never trust an artifact you did not watch being produced" rule is about. A new failure-only step
keeps the `.xcresult` for `unit` and each `ui` shard (`if: failure()`, `if-no-files-found: ignore`),
which carries the attachments and per-test source locations the text log cannot.

#### The red-proofs

*Guard, four cases, each run through the real script against real device state:*

| stored camera | expected | observed |
| --- | --- | --- |
| `37.759899,-122.414803` z18, 501 trees (the ticket's) | heal | `camera-auto-healed yes reason=#71 not the app default` |
| the app default, immediately after | **leave alone** | `camera-auto-healed no` |
| `37.7596,-122.4269` spans `0.20/0.25` (zoom 11) | heal, E202-B branch | `reason=E202-B too-wide` |
| `37.769402,-122.486198` (Golden Gate Park, 0 trees) | heal, E216 branch | `reason=E216 uncovered` |

The second row is the one that matters as much as the first: a guard that refuses everything is not
a fix, and the E202-B/E216 rows show the two existing branches still fire with their own
diagnostics rather than being swallowed by the new one.

*End to end, same test, same camera, same tree:*

- before — `VERIFY-FAIL: ** TEST FAILED ** present`, the hittability message quoted at the top.
- after — the guard heals, and `Executed 1 test, with 0 failures (0 unexpected) in 12.524s`.

*Failure excerpt, calibrated before it was believed* (CLAUDE.md: run the instrument against a case
whose answer you already know). Four logs: a local UI log with one known failure → 1 line, the right
one; a CI unit log of 1,317 passing tests → silent; a CI UI log with one known failure → 1 line, the
right one; a green CI UI shard → silent. A looser pattern (`error:` or `failed` alone) reports 37
lines on that green unit log, because xcodebuild prints both words routinely in builds that are
fine. The Swift Testing branch was red-proved separately by breaking
`MapOpeningCameraTests.noteDoesNotWrite` and running it alone; it printed the suite, the test, the
file and line, and the expectation, and the break was reverted.

#### Not done, and why

- **The test's own fragility is untouched.** `assertEveryControlIsLabeled` asserting over elements
  of a screen it does not own — the map behind a presented cover — is the deeper defect, and the
  brief's other option (have the deep-link tests pin their own opening camera, the way R58's
  `CYPRESS_LOCATION` pins location) is the fix for it. That needs a DEBUG seam in app code and its
  own unit tests, which is a second ticket, not a rider on a harness change. Until it exists, a
  device state the harness does not model can still reach these tests.
- **The tolerance is a width, not a claim.** `CAMERA_CENTER_TOLERANCE_M=50` exists to absorb
  MapKit's own readback drift (a device left at the default reads back ~0.2 m off, with spans a
  fraction of a percent out). It is not an assertion that everything inside 50 m is equally good.
