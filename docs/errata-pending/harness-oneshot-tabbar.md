### `DeepLinkHarness.check()`'s tab-bar witness was one-shot, the same race E245 fixed elsewhere (task #243)

#### The premise, checked

PR #40 fixed a push-transition race in `DeepLinkSweepTests.testEveryPushedScreenSaysWhereItIsFirst`
(ERRATA E245, CI runs 31074532263, 31082691131): `arrive()`'s `waitForExistence` on a pushed
screen's anchor text is satisfied the instant the incoming view enters the accessibility tree —
early in the `NavigationStack` slide transition, not once it settles — while the outgoing screen
(its tab bar, its own rows) is still present, still hittable, and still ahead of the incoming
screen in `debugDescription`'s depth-first order.

Its reviewer flagged the same shape, still latent, in `DeepLinkHarness.check()`
(`CypressUITests/DeepLinkHarness.swift`): the `pushed` branch read
`app.buttons["My Grove"].isHittable` with a single `XCTAssertFalse` immediately after `arrive()`
returned — no wait in front of it. Checked against the code, not assumed from the ticket: `check()`
is called directly, with `pushed: true`, from twelve methods in `DeepLinkVoiceOverTests.swift`
(`testTreeProfile`, `testVacantSite`, `testSpecies`, `testCheckIn`, `testReport`,
`testGrowthHistory`, `testActivity`, `testMeasure`, `testOutbox`, `testMemorial`, `testPhotos`,
`testPhotoHero`), and none of those call sites sit behind any wait of their own — `launch` then
`arrive` then `check`, nothing between. The window E245 diagnosed was reachable there, not merely
structurally similar in theory. No failure has been recorded on these methods yet; the refutation
this entry would otherwise contain does not hold — the premise was correct.

#### The fix

Hoisted E245's wait — `XCTNSPredicateExpectation(predicate: "hittable == false", object:
app.buttons["My Grove"])` awaited through `XCTWaiter.wait(timeout: 30)` — out of
`DeepLinkSweepTests.swift` and into `DeepLinkHarness.swift` as
`waitForPushedScreenToArrive(_:screen:file:line:)`, so `check()`'s pushed branch and the sweep test
now share one definition instead of each carrying its own copy of the same wait. `check()` calls it
in place of the old one-shot `XCTAssertFalse`; `DeepLinkSweepTests.testEveryPushedScreenSaysWhereItIsFirst`
calls the same function where its inline `XCTNSPredicateExpectation`/`XCTWaiter` block used to be.

**Nothing weakened.** The wait establishes only that the outgoing tab root is gone — never that
`Back` is reachable, never anything about the incoming screen's own contents — so a tab bar that
never departs still fails loudly, on timeout, with a message naming the reason
(`"...still hittable 30s after the anchor appeared — this is still a tab root rather than the
pushed screen the test asked for"`), not a silent pass.

**Red-proofed.** Pointed the witness at `app.buttons["Back"]` (hittable throughout a pushed screen,
so it never satisfies `hittable == false`) and dropped the timeout to 8s; ran
`CypressUITests/DeepLinkVoiceOverTests/testTreeProfile` alone. It failed for the expected reason —
the tab-bar-still-hittable message above — not on an unrelated assertion. Restored, then
`DeepLinkVoiceOverTests` (26 tests, all twelve `pushed: true` call sites) reran green.

Full `CypressUITests` suite, device iPhone 16 Pro Max `DE8E11AE-4375-4C3B-A296-9B60A7DF1DB3`:
`** TEST SUCCEEDED **`, `Executed 92 tests, with 0 failures`, `XCTest skipped=0`
(`Tools/verify_test_log.sh`). Warnings certified on a fresh DerivedData build
(`Tools/verify_test_log.sh --warnings`): `SwiftCompile tasks=438`, `source=0` warnings,
`files-checked=2` confirming both `DeepLinkHarness.swift` and `DeepLinkSweepTests.swift` were
compiled.
