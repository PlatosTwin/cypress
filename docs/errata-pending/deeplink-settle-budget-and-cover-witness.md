### The settle-under-load family gets two more members: an undersized budget (#244) and a cover with no departing predecessor to watch (#245)

#### #244 — the premise, checked against CI, not assumed from the ticket

The ticket cited main run 31096120555 (post-PR #41 merge, tree `73b4850`, shard `ui (3)`,
2026-08-06) as a `DeepLinkSweepTests.testNothingIsAnnouncedTwice` failure on `treeProfile`. `gh run
view` shows that run as `success`, and its `ui (3)` job as `success` — because the run's *second*
attempt (`run_attempt=2`) is what `gh run view` shows by default, and attempt 2 passed. Attempt 1's
`ui (3)` job (id `92598515285`) genuinely failed; its log, pulled by artifact ID rather than by
name (both attempts uploaded an artifact called `ui-log-3`), reads:

```
DeepLinkSweepTests.swift:170: error: -[CypressUITests.DeepLinkSweepTests testNothingIsAnnouncedTwice]
: failed - treeProfile's static text #5 ("DBH, 30–35 cm, from the city record") is in the
accessibility tree but never became hittable within 5s — it is present and cannot be activated
```

So the failure is real. What it is *not* is a missing settle-or-finite treatment: `settledFrame`
(task #239) already wraps every frame this method reads, `assertReachable`-first. The defect is the
`timeout: 5` this call site passed to it — five seconds, against every other hittability wait in
the suite's 10–30s, on a method that launches the app six times and, on CI, shares its shard with
three other classes. The log's own timestamps confirm the shape: the predicate wait starts at
t=30.75s and the failure lands at t≈35.8s — a clean 5s window, not a permanently-stuck element (the
same static text is found and read again later in the same run, at t=60s+).

#### #244 — the fix

`DeepLinkSweepTests.swift`, `testNothingIsAnnouncedTwice`: `timeout: 5` → `timeout: 30`, matching
`assertReachable`'s own default and every other call site in the suite. Nothing else about the
method changed — the settle-or-finite treatment was already correct. Per `UIWait.swift`'s own
rationale for the 30s default, this costs nothing when elements are reachable and only extends how
long a genuine defect takes to report.

**Red-proofed.** Temporarily read every static text on the `treeProfile` screen unfiltered (dropping
the `isHittable` pre-filter, so genuinely off-screen elements reach `settledFrame`) and ran
`CypressUITests/DeepLinkSweepTests/testNothingIsAnnouncedTwice` alone. It failed for the expected
reason, at the new 30s budget:

```
DeepLinkSweepTests.swift:174: error: ... failed - treeProfile's static text #6 ("The city's street
tree inventory records pruning by block, not by tree, so it says nothing about when this tree was
last pruned.") is in the accessibility tree but never became hittable within 30s — it is present
and cannot be activated
```

(four more off-screen texts failed the same way in the same run). Restored.

#### #245 — the premise, checked against the code

Found in PR #42 review, no recorded CI failure: `DeepLinkVoiceOverTests.testAModalIsolatesTheScreenBehindIt`
reads `tab.isHittable` on the four tab-bar buttons immediately after `arrive()` returns, with no
wait between them — checked directly against `DeepLinkVoiceOverTests.swift`, not assumed. The
premise holds: `arrive()`'s existence check on the cover's own anchor text (`"Care log"`/`"Share
this tree"`) is satisfied the instant that text enters the tree, and `BottomSheet`
(`Cypress/DesignSystem/Components/BottomSheet.swift`) puts it there from the view's very first
frame — the whole card sits at `.opacity(settled ? 1 : 0)` with `settled` (`hasRisen`) starting
`false` and flipping only inside the `onAppear` animation. The anchor exists before the sheet has
risen at all, not merely before it finishes rising, so a one-shot tab-bar check right after
`arrive()` can land in that pre-rise instant, where the screen behind is still genuinely, correctly
hittable — a false failure on a fast test, and on a loaded runner a wider window to land in.

**The witness has to differ from the push side's, and does.** `waitForPushedScreenToArrive`
(#243) waits for a known-hittable predecessor (the tab bar) to go *not* hittable — safe there
because the tab bar was hittable a moment earlier, on the tab root the push started from. A
`fullScreenCover` has no such predecessor to watch depart: 09 and 10 draw no close button (see
`BottomSheet.swift`'s file header), and per `UIWait.swift`'s own rule, waiting on the negative
predicate directly ("hittable == false") risks a slow runner satisfying it by never having drawn
anything at all. `BottomSheet` gives VoiceOver a named "Dismiss" scrim control instead
(`.accessibilityLabel("Dismiss")`, `.accessibilityAddTraits(.isButton)`, hidden only when there is
no dismissal to offer) — present and traited as a button as soon as the cover mounts, but only
*hittable* once `settled` has actually flipped. Waiting for `app.buttons["Dismiss"]` to become
hittable is therefore a positive read of "the cover has risen," the correct departure signal for
this presentation.

#### #245 — the fix, and a first version that had to be thrown out

Added `DeepLinkHarness.waitForCoverToArrive(_:screen:file:line:)` (`DeepLinkHarness.swift`).
`testAModalIsolatesTheScreenBehindIt` calls it right after `arrive()`, before reading the tab bar's
`isHittable` state.

**The first version was wrong, not merely early, and stayed that way through a clean red-proof.**
It waited for `BottomSheet`'s named "Dismiss" scrim control to become hittable, structured like
`waitForPushedScreenToArrive`. Red-proofed clean in isolation (pointed the witness at a button that
would never exist; failed with the expected "never became hittable" message; restored) — and then
failed for real, twice, against the *real* "Dismiss" control: once buried in a full-scheme run
(1 failure among 1348 tests), once alone in a `CypressUITests`-only run, both on device
`DE8E11AE-4375-4C3B-A296-9B60A7DF1DB3`, both the same test, both the full 30s:

```
DeepLinkVoiceOverTests.swift:402: error: ... failed - careLog: the cover's own "Dismiss" scrim
control never became hittable within 30s — this is still the pre-rise frame rather than the
settled cover the test asked for
```

Not a race: `BottomSheet.swift`'s own file header explains why a full-height `.standard` card
leaves only a thin status-bar strip of scrim exposed (`SheetExitUITests`'s header calls it "~8pt"),
so the scrim's center — where `XCUIElement.isHittable` samples — sits under the opaque card for the
entire life of the cover, forever, not just during the rise. VoiceOver's own traversal reaches
"Dismiss" without hit-testing it (the drag-zone comment in `BottomSheet.swift` says so directly);
`XCUIElement.isHittable` has no such exemption. A clean red-proof against a fabricated failure mode
did not catch this, because the red-proof never exercised the *real* control — only the discipline
of actually running the fix against a real screen did.

Replaced with the witness `SheetExitUITests.waitForTitle` already uses successfully for these same
two screens: `settledFrame` on the cover's own anchor text, which is ordinary card content, not
covered by anything.

**Red-proofed (the version that shipped).** Pointed `waitForCoverToArrive`'s anchor at text that
will never exist and ran `testAModalIsolatesTheScreenBehindIt` alone. It failed for the expected
reason:

```
DeepLinkVoiceOverTests.swift:403: error: ... failed - careLog: the cover's own
"RedProof245v2NeverOnScreen" title never appeared in the accessibility tree at all within 30s
```

Restored, then ran clean alone (`Executed 1 test, with 0 failures`).

#### Full-suite verification

Full `CypressUITests` suite, device iPhone 16 Pro Max `DE8E11AE-4375-4C3B-A296-9B60A7DF1DB3`, tree
`8f21eb1`, fresh DerivedData: `** TEST SUCCEEDED **`, `Executed 92 tests, with 0 failures`,
`skipped=0` (`Tools/verify_test_log.sh`). Warnings certified on the same fresh build
(`Tools/verify_test_log.sh --warnings`): `SwiftCompile tasks=438`, `source=0` warnings,
`files-checked=3`, confirming `DeepLinkHarness.swift`, `DeepLinkSweepTests.swift` and
`DeepLinkVoiceOverTests.swift` were all compiled. No app-code changes — `CypressUITests` only.

A prior attempt at this same full-suite verification produced a false read: its log path
(a generic `full-suite.log` in the shared scratchpad) was clobbered mid-run by an unrelated,
concurrently running agent's process that reused the identical absolute path for a different
worktree. The corruption was caught by cross-checking the log's own `CYPRESS-RUN` provenance header
— it named the wrong worktree and device — and by reading results back out of this run's own
`.xcresult` bundle (inside a uniquely-named DerivedData directory nothing else touched) instead of
trusting the shared text log. Every log cited above came from a uniquely-named path.
