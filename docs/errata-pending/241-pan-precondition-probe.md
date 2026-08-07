### The pan precondition, reopened: no reachable app-side mechanism for "landed, then snapped back" — instrumented instead of guessed at (task #241)

#### The occurrence

E242's amendment set the rule that the next occurrence of `MapPanTabSwitchUITests
.testADeliberatePanSurvivesLeavingForJournalAndBack` failing on its own precondition reopens as its
own ticket rather than becoming another rerun note. It occurred: run 31074532263 (PR #38, updated
head `65b99e2`, shard `ui (4)`, 2026-08-06 ~05:59 UTC), with #230's retry (`panUntilMoved`, `c1501af`)
present in the tree and exhausted — the same sentence as before, *"panning the map did not move the
camera off the reader (the control reads 'Centered on you'), so there is no deliberate camera to
preserve"*. This is the second post-#230 occurrence; the first was run 31067670540, recorded in
E242's amendment. Both nights had heavily loaded runners (5+ concurrent full-suite runs).

#### What the brief asked, checked against the code rather than assumed

The brief's own framing was two candidate mechanisms: the synthesized drag never reaches the map, or
it reaches the map and the camera is driven back to center by something else. Reading
`MapHomeView.swift` and `MapAnnotationLayer.swift` end to end for every **writer of `position`** —
not merely every caller of `flyTo(_:meters:)`, which is where a first pass of this entry stopped and
why it claimed two — turns up **three**:

1. `centerOnUserIfNeeded()` → `flyTo`, called from `.task` on appear and from `.onChange(of:
   location.availability)`, gated by `hasCenteredOnUser` (a one-shot `@State`) and
   `MapCameraMemory.shared.readerMovedCamera`.
2. `recenter()` → `flyTo`, called only from a tap on the recenter control.
3. `zoom(into cluster:)` (`MapHomeView.swift:715`), which writes `position` directly rather than
   through `flyTo`. It is wired as `onSelectCluster:` and reached from
   `MapAnnotationLayer`'s `mapView(_:didSelect:)` whenever the tapped annotation is a
   `TreeClusterAnnotation`.

Neither is reachable inside `panUntilMoved`'s own window (before `switchTabs` runs). `launchCentered()`
already waits for the control to read `Centered on you` before returning, which means
`hasCenteredOnUser` is `true` — and therefore (1) is a no-op — before the first `pan(app)` call. (2)
never fires because the test never taps the control during `panUntilMoved`. That leaves
`.onChange(of: location.availability)` as the only thing that could still move the camera, and it only
fires when `location.availability` *changes* — and under `CYPRESS_LOCATION`, it cannot:
`MapLocationProvider(pinnedAvailability:)` (`MapLocationProvider.swift`) attaches no `CLLocationManager`
delegate and makes `start()`/`stop()` no-ops, so a pinned run publishes exactly one `Availability` for
the life of the process. `.onChange` never fires a second time.

Writer (3) is **not** ruled out by either of those latches, and the review of this branch was right
to say so. The app's own gesture recognizers are installed with `cancelsTouchesInView = false`, so
MapKit's selection handling runs on the same touch stream a synthesized drag travels on: a drag that
begins on a cluster badge can plausibly reach `didSelect`. What it cannot do is produce *this*
symptom in the obvious way — `zoom(into:)` moves the camera to the cluster's own region rather than
back to the reader, which is a camera that moved. The residue, stated rather than waved away: a
cluster sitting on the reader's own position would leave a camera that both moved and still reads as
centered, so writer (3) is a path this entry narrows by argument, not one it eliminates by latch.

**So, on the app's code as it stands today, "the gesture landed and the camera was driven back to
center" has no reachable path through the two `flyTo` callers during this precondition.** That does
not prove it cannot happen — a
future code change could add one, or `MKMapView` itself could exhibit UIKit-side rubber-banding this
investigation did not reproduce — but it means the far more likely mechanism, on the evidence
available, is that the synthesized drag is not being read as a pan at all under load: the same shape
#209 fixed once (too few intermediate touch events) and #230 retried around, just still possible on a
worse night than either fix was tuned against.

#### What was instrumented, and why a log line was tried first and dropped

`MapPanProbe` (`Cypress/Features/Map/MapAnnotationLayer.swift`, `#if DEBUG`, armed by
`CYPRESS_PAN_PROBE=1`) counts every state the reader's own pan/pinch recognizer reaches
(`readerGesture(_:)`; `panBegan`/`panEnded`/`panCancelled`/`panFailed`, plus the translation UIKit
itself measured at `.ended`) and every settle MapKit reports (`mapView(_:regionDidChangeAnimated:)`;
count, last center, last span). `MapHomeView` exposes its summary through a hidden, zero-opacity,
non-hit-testable accessibility element (`CypressPanProbe`), and `MapPanTabSwitchUITests.launchCentered()`
now arms the probe unconditionally, so the *next* occurrence carries the trace in its own `XCTFail`
text (`panUntilMoved`) instead of needing another investigation from zero.

`NSLog` was tried first and measured wrong: a run armed with `NSLog` produced zero matching lines in
`Tools/run_tests.sh`'s captured log, because `NSLog` writes to the unified log, which `xcodebuild
test`'s own captured text does not contain. Plain `print` from the *app* process fares no better —
the app under a UI test is a separate process from the one whose stdout `xcodebuild` captures, and
only the test-runner process's own `print` calls (confirmed to work) show up in the log. The
accessibility element has neither problem, and it is read the same way the test already reads the
recenter control's own state, so nothing new had to be taught to the harness.

**Why this one element is not `.accessibilityHidden(true)`, unlike `MapProbeOverlay`.** Review
raised the tension with ARCHITECTURE §7 — identifiers scattered through production views are a tax
this project declined to pay — and with this codebase's own precedent, `MapProbeOverlay`, which
hides itself on the principle that an instrument must not participate in what it measures. The
precedent does not transfer, for the reason that makes it a precedent: `MapProbeOverlay` is read by
a human eye, so hiding it costs nothing, while this probe is read *through* the accessibility tree
by XCUITest, and hiding it would make it unreadable — an instrument that cannot be read is not an
instrument. What keeps it from participating is the gate instead: it exists only under `#if DEBUG`
**and** only when `MapPanProbe.isEnabled` (the `CYPRESS_PAN_PROBE` launch variable) is set, so it is
absent from the tree of every other test in the suite, at zero size, non-hit-testable, and at the
lowest sort priority in the one run that asks for it. §7's tax is not paid by a view that does not
exist in any shipping or ordinary-test configuration.

**Red-proofed.** Temporarily made `pan(_:)` a no-op and ran
`testADeliberatePanSurvivesLeavingForJournalAndBack` alone: it failed for the expected reason, and the
`XCTFail` text read
`… probe: panBegan=0 panEnded=0 panCancelled=0 panFailed=0 lastEndedTranslation=none settles=2
lastSettleCenter=37.7599,-122.41480000000001 lastSettleSpan=0.0021063199576900615` — `panBegan=0`
correctly reporting that no gesture reached the map, and the two settles and their center matching the
opening fly-to rather than anything a pan would have produced. Restored `pan(_:)` before committing.

**One residual ambiguity, stated rather than papered over.** `MapPanProbe` counts *our own* pan
recognizer (added in `makeUIView`, `cancelsTouchesInView = false`), not MapKit's internal one — the
two are independent recognizers on the same view. A future occurrence reading `panBegan > 0` with
`settles` unchanged from the pre-drag baseline would say "a touch stream was read as a pan by
*something*, but MapKit's own camera-driving recognizer did not agree" — a third, narrower shape
between "never landed" and "landed then reverted" that this probe can surface but not itself resolve
further. Worth knowing before trusting `panBegan > 0` alone as "the drag definitely worked."

#### Local reproduction: attempted, not achieved

Built once (`xcodebuild build-for-testing`, private `DerivedData`), then ran
`testADeliberatePanSurvivesLeavingForJournalAndBack` alone 16 times against iPhone 16e
`3A1F212D-8F3A-41F1-AF72-EC95E155A4C9`, under synthetic CPU load escalating across three batches — 6,
then 16, then 26 concurrent `yes > /dev/null` processes on a 10-core Mac, standing in for the "3-core
runner, 5+ concurrent full-suite runs" CI has reported. All 16 passed (`0 failures`). Load did perturb
timing — one run under the heaviest batch took 77.9 s for a test that normally takes 19–30 s — so the
load model is not inert, it simply did not cross the failure threshold in 16 tries. **Not
reproduced.** A CPU-only busy-loop is not the same contention as several real `xcodebuild`/simulator
processes competing for touch-delivery IPC, disk and memory, and this investigation did not have
budget under the project's three-concurrent-`xcodebuild` cap to run enough real concurrent suites to
approximate that more closely.

#### What this round deliberately does not touch

No change to `attempts`, `settleTimeout`, or any of `deliberateDrag`'s three numbers. Tuning any of
them without a reproduction to test against would be a guess dressed as a fix, and the brief's own
instruction — decide where the fix belongs on evidence, not by default — cuts the other way here: the
evidence available rules out an app-side mechanism for this specific precondition and does not
identify a concrete test-idiom defect either, past what #230 already hardened. No app code changed
beyond the probe, which is inert (`#if DEBUG`, off unless armed, and armed only in this one test file)
everywhere else.

#### Verification

Zero-warning line certified on a fresh `DerivedData` build (`Tools/verify_test_log.sh --warnings`),
head `39600a7`: `SwiftCompile tasks=438`, `source=0` warnings, `files-checked=3`
(`MapAnnotationLayer.swift`, `MapHomeView.swift`, `MapPanTabSwitchUITests.swift` all confirmed
compiled).

Two full `CypressUITests` suite runs, iPhone 16e `3A1F212D-8F3A-41F1-AF72-EC95E155A4C9`, via
`Tools/run_tests.sh` + `Tools/verify_test_log.sh`:

- Head `0a35781`, `CYPRESS-RUN: started 2026-08-06 16:54:15 PDT` — `VERIFY-OK: Executed 92 tests,
  with 0 failures (0 unexpected) in 1371.898 (1376.480) seconds`, `XCTest skipped=0`,
  `** TEST SUCCEEDED **`. A first pass of this entry described this run as the scheme's default test
  plan, "so the `CypressTests` Swift Testing suite ran too." **The quoted line refutes that**, and
  the tool says why: `verify_test_log.sh` builds its `VERIFY-OK` as
  `${SWIFT_LINE:-$XCTEST_LINE}` and appends `| XCTest: …` whenever both ran, so a *bare*
  `Executed N tests` line is emitted only when Swift Testing did **not** run. This was an XCTest-only
  run, like the one below it. Read the shape of the line, not the intent of the command.
- Head `39600a7` (current, after the stale-comment fix — a doc-comment-only change inside
  `#if DEBUG`), `CYPRESS-RUN: started 2026-08-06 17:22:55 PDT`, `-only-testing:CypressUITests` —
  `VERIFY-OK: Executed 92 tests, with 0 failures (0 unexpected) in 1431.214 (1435.775) seconds`,
  `XCTest skipped=0`, `** TEST SUCCEEDED **`. `MapPanTabSwitchUITests`' both methods passed
  (`testADeliberatePanSurvivesLeavingForJournalAndBack` 19.344s,
  `testAnUntouchedCameraStillCentersOnTheReaderAfterTheRoundTrip` 8.944s).
