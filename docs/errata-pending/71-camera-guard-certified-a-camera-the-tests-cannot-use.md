### The camera guard certified a camera the tests cannot use, and a red CI run would not say what failed (task #71)

#### The occurrence

`DeepLinkVoiceOverTests.testPinAdjust`, on iPhone 16 Pro `EA0AD796-…`, **at 402 pt**, fails on
contact:

    <unknown>:0: error: -[CypressUITests.DeepLinkVoiceOverTests testPinAdjust] :
    Failed to determine hittability of "City tree, Southern Magnolia" Button:
    Activation point invalid and no suggested hit points based on element frame

The only thing wrong with the device is its remembered `map.lastCamera`,
`[37.759899,-122.414803]` at zoom 18. `Tools/run_tests.sh` looked straight at that camera, stamped
`camera-trees=501` and `camera-auto-healed no` in the header, and ran the suite on it. This is
CLAUDE.md's own signature shape living inside the harness: **a guard reporting green precisely when
its condition is present.**

**The width qualifier is not decoration.** The same camera, the same test and main's own harness run
`Executed 26 tests, with 0 failures` on a **430 pt** device — measured by this PR's reviewer, and the
first draft of this entry was wrong to say the camera "fails on contact, every time". It fails at
402 pt. E202 and E216 are both width-scoped for their own reasons, which is why `run_tests.sh`
stamps `screen-width-pt` on every log and why `verify_test_log.sh` has `--expect-width` at all; a
width-sensitive claim made without a width is not a claim about the app on the devices it ships to.

The opposite geometry showed up in the same review and is worth recording beside it. The camera the
reviewer used to break the guard's tolerance — `37.760040,-122.426903,0.001078,0.002590`, 49 m north
with the longitude span 1.9× — **fails at 430 pt and passes at 402 pt**, the mirror image of the
ticket's own camera. It does not pass cleanly: 254 s against 12.5 s for the same single test on the
same device at the normalized camera. Two cameras, opposite width sensitivities, one shared cause
underneath (`isHittable` raising on a background annotation), which is the argument for normalizing
the camera rather than enumerating the bad ones.

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
failed here — the admitted set is the app's own `MapLayout.defaultCenter` at
`MapLayout.defaultSpanMeters` plus the **measured readback drift** around it, and anything outside
is rewritten before the suite runs. `compute_safe_camera` prefers that point and keeps its
densest-seed-bin computation as the fallback for a city whose inventory does not reach the app's
default.

*The drift band, and why the first one was indefensible.* The first cut allowed 50 m of centre and a
0.5×–2× span band while justifying the number, in its own comment, by a readback drift measured at
~0.2 m and spans "a fraction of a percent" out — 250× and ~100× looser than its own evidence, and it
compared only the longitude span, never the latitude one. "Exactly one camera is admitted" was
therefore false in the script, the PR body and this entry: the admitted set was a 100 m disc crossed
with a 4× span range, and the reviewer found a camera inside it that the guard certified and that
then failed the ticket's own test. The band is now 2 m of centre and ±2 % on **both** spans — about
ten times the drift actually measured (writing the target and letting the app run leaves 0.3 m of
centre, 0.003 % and 0.05 % of span behind). A tolerance that contains the defect it was written for
is that defect one level up.

*The parse refuses rather than falls through.* `MapLayout.defaultCenter` is read out of the app's
source, never copied as a literal — but the first cut's three unanchored `sed`s failed **silently**
in every failure mode, and the caller read "could not parse" as "nothing to compare against",
dropping out of the chain and stamping a clean flag over an arbitrary camera. That is the
pre-existing false certification restored without a word. It now strips comments, scopes to
`enum MapLayout`'s own braces, insists on exactly one declaration of each, cross-checks the result
against `DebugLocationFixtures.missionDolores` in a different file, and **refuses** on any failure.
`MapLayoutDefaultsAgreeTests` asserts the cross-check's premise in Swift, so the agreement the
script leans on is itself guarded.

*Two header flags, not one.* `camera-auto-healed` keeps E202-B's meaning — this device was in one of
the two anomalous states — and stays rare, which is the only condition under which it discriminates.
The routine #71 rewrite reports as `camera-normalized`. The split exists because
`MapHomeView.swift` records that one granted launch at the project's canonical fix leaves
`map.lastCamera` holding `(37.759899, −122.414803, 0.001081, 0.001362)`: **the ticket's hostile
camera is what a healthy 402 pt device holds after a UI suite**, so normalization runs on most real
runs. Reporting that under the anomaly flag would have made it fire every time and mean nothing.

*Convergence is checked against whatever was written.* The first cut only verified convergence when
the target came from the app default, so the densest-bin fallback would have re-triggered on every
subsequent run and healed forever, each log claiming a repair.

What this claims is deliberately weaker than what the old header implied. It does **not** claim the
default camera can serve any given test; nothing in a shell script can know that, and the header now
says so out loud — `viewport-trees=0` at the app's own default, because the camera it normalizes onto
draws no pins inside its own 120 m rectangle. That is not a defect being hidden: `defaultSpanMeters`'
own doc comment says Mission Dolores Park is 390 m across and the nearest inventoried tree is a block
away, and the ±250 m `camera-trees` box cannot see it. Both counts are now printed, and neither is
refused on. What the guard claims is that every run starts from **one** known camera — the one the
suite is green on — instead of inheriting whichever of infinitely many the last run left behind.

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
| `37.759899,-122.414803` z18, 501 trees (the ticket's) | normalize | `camera-normalized yes`, `auto-healed no` |
| `37.760040,-122.426903,0.001078,0.002590` (the reviewer's, inside the old tolerance) | normalize | `camera-normalized yes`, `auto-healed no` |
| the target, immediately after | **leave alone** | `auto-healed no`, `normalized no` |
| `37.7596,-122.4269` spans `0.20/0.25` (zoom 11) | heal, E202-B branch | `auto-healed yes reason=E202-B too-wide`, `normalized no` |
| `37.769402,-122.486198` (Golden Gate Park, 0 trees) | heal, E216 branch | `auto-healed yes reason=E216 uncovered`, `normalized no` |

Rows 4 and 5 show the anomaly flag firing *without* the routine one, which is the split N1 asked
for. Row 3 is the one that matters as much as row 1.

*Parser, eight cases against a rig fed variants of the real file.* Control parses
`37.7596 / -122.4269 / 120`. A **doc comment above the declaration citing a historical coordinate**
— the rc=0 mis-parse the reviewer found, which under the old parser returned `37.7599,-122.4148`,
the ticket's own bad block — now parses correctly, because comments are stripped first. Five shapes
that break the anchor (`Coordinate(` split across lines, a wrapped `longitude:`,
`CLLocationDistance(120)`, a computed `var`, the file renamed) all refuse with a message naming which
declaration was not found. Making the two files disagree refuses with both coordinates quoted.

Building that rig found a bug in the parser it was built to test: with a value missing, the awk
`END` line printed an empty field, `read` split on whitespace runs, and every later field shifted
left — so the counts ended up holding coordinates and the refusal named the wrong declaration. The
counts are now emitted first and every value has a `-` placeholder, so the line's arity is fixed.

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
fine. The Swift Testing branch was red-proved separately by breaking a real test and running it
alone; it printed the test, the file and line, and the expectation, and the break was reverted.

*What the CI evidence does and does not show.* A first pass offered "the same grep finds failure
lines in this branch's job log and none in five pre-change ones" as proof the failures were
pre-existing. It is not: a grep for the new feature's own output over logs written before the
feature existed **must** return zero, so it measures the feature's absence and nothing about the
failures. It is good evidence for the *other* claim — that the job log genuinely never carried this
text — and it is only used for that now. The attribution rests on different evidence: pre-change run
`31294993494`'s `ui-1.log` fails on the same test with the same message, and both failing shards'
headers read `map.lastCamera=[n/a (app not installed)]`, so the new branch had no camera to act on
and demonstrably did not fire. The diff does change CI behaviour in one real way — it adds
`-resultBundlePath` to `xcodebuild` — so the inertness claim is made about the camera guard
specifically, not about the whole diff.

#### Not done, and why

- **The test's own fragility is untouched.** `assertEveryControlIsLabeled` asserting over elements
  of a screen it does not own — the map behind a presented cover — is the deeper defect, and the
  brief's other option (have the deep-link tests pin their own opening camera, the way R58's
  `CYPRESS_LOCATION` pins location) is the fix for it. That needs a DEBUG seam in app code and its
  own unit tests, which is a second ticket, not a rider on a harness change. Until it exists, a
  device state the harness does not model can still reach these tests.
- **The tolerance is a width, not a claim.** `CAMERA_CENTER_TOLERANCE_M=2` with `±2 %` on both
  spans exists to absorb MapKit's own readback drift, measured on a device. It is not an assertion
  that everything inside 2 m is equally good — it is the width of "the same camera".
- **Retention was set to 30 days for the text logs and 14 for the result bundles**, not 14 for
  both. An errata entry cites the run it was written from, and a citation whose artifact expires
  before the next reader follows it is its own small false green; 30 days outlives a review round.
  The bundles are ~110 MB each, so size is what gets rationed.
- **The excerpt still prints two lines per Swift Testing failure**, not one: the issue line (which
  carries the expectation) and the test line. Only the two aggregate shapes are dropped. Cutting
  further would mean parsing Swift Testing's output rather than filtering it.
- **`viewport-trees` is reported and never refused on.** A camera whose own rectangle holds no
  trees is the app's documented behaviour at its own default, so a guard that refused it would
  refuse the app. Whether the suite *should* open somewhere with pins in view is a product
  question, not a harness one.
