//
//  AppleSignInUITests.swift
//  CypressUITests
//
//  Screen 15's `Continue with Apple`, on a running phone (#158 spec §10 step 5).
//

import XCTest

/// **The proof boundary, and this file is the far edge of it.**
///
/// Nobody may sign a real Apple Account into a simulator, and this suite does not try: the real
/// end-to-end tap is the owner's, on a device, after merge. What a UI test can prove is what the
/// unit suites cannot — that the control is *there*, that it is *reachable*, and that the two
/// outcomes which are about **drawing** draw what SCREENS.md 15 says they draw.
///
/// - `AppleSignInRecipeTests` proves what Apple is handed and what the callback becomes.
/// - `AccountLinkTests` proves everything from the callback to the stored session, over a scripted
///   transport.
/// - This proves that a person can get to the button, and that a dismissed sheet leaves the screen
///   alone while a failed authorization does not.
///
/// The refusals are pinned with `CYPRESS_APPLE_SIGN_IN` (`DebugAppleSignInOverride`). **There is no
/// value that pins a success**, deliberately: a pinned success would hand `AppSession` a forged
/// credential.
///
/// ── What makes this suite hermetic, corrected (review of PR #84, F1) ─────────────────────────────
///
/// This paragraph used to end "so this suite is hermetic — it opens no socket, exactly like
/// `RemoteGateComplaintUITests`", and that was a claim about the pins rather than about the build.
/// It was false twice over. `DataLayer.boot` built its `AppSession` on `AuthClient()`'s live
/// defaults, outside the `CYPRESS_REMOTE` gate entirely, so the app under test dialled production
/// the moment anything asked for a credential; and `DebugAppleSignInOverride.resolve` answered `nil`
/// for an unrecognized value, which restores the **real Apple sheet** — so a typo in either the key
/// or the value below put a live system sheet in front of a runner whose simulator may have an Apple
/// Account signed in.
///
/// Both are closed, and the guarantee now comes from the gate rather than from this file: a DEBUG
/// launch resolves `RemoteAccess.disabled`, `boot` gives the session an `OfflineSession`, and
/// `RemoteAccessSignInTests` proves no socket opens with the interception calibrated first. A
/// mistyped pin refuses and draws a complaint instead of the sheet. This suite is hermetic because
/// of those two facts, not because of the values it happens to pass.
///
/// ── How screen 15 is reached ─────────────────────────────────────────────────────────────────────
///
/// `CYPRESS_SCREEN=accountAsk`, which presents it over the tab root the same way `RootView` presents
/// it for the You tab's `Sign in` row. **Taking that row instead was tried and rejected**: whether it
/// is drawn depends on whether this device is signed in, and `DebugDeepLink`'s `.moderationReview`
/// case promotes the account — so a test using that door reads whichever run went before it, which
/// is E216's family of failure. The deep link depends on no device state and writes none.
final class AppleSignInUITests: XCTestCase {

    private enum Copy {
        static let apple = "Continue with Apple"
        static let decline = "Not now · keep saving to this phone only"
        /// `AccountAskCopy.noticeFailed`, matched on its distinctive opening clause rather than
        /// whole, so a revision to the second sentence does not fail this test for the wrong reason.
        static let failed = "That did not go through"
        /// `AccountAskCopy.noticeUnavailable`'s opening clause.
        static let unavailable = "Accounts are not ready yet"
    }

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Opens screen 15 and **waits for the sheet to stop moving**, returning the app.
    ///
    /// The arrival is confirmed on §7's decline control rather than on the Apple button, so that a
    /// build which drew the sheet *without* the Apple button fails in the test that is about the
    /// Apple button rather than in this helper.
    ///
    /// ── Why this waits for a fact instead of sampling a property ───────────────────────────────
    ///
    /// `testTheAppleButtonIsDrawnAndHittable` flaked at roughly 50% on CI — three failures across
    /// three unrelated trees (`f17e650`, `fa12518`, `fc3420b`), each greening on re-run, each the
    /// same assertion and the same sentence, and none of the three diffs able to reach this screen.
    ///
    /// **The mechanism is not what it looks like, and the screen recording is what settled it.** The
    /// obvious reading is a presentation race: `waitForExistence` returns while a `fullScreenCover`
    /// is still sliding up, so the controls exist before they can be touched. That reading is wrong
    /// here. The xcresult from run 31900590782 carries a recording of the failing test, and the
    /// frames either side of the failure instant (t = 6.0 s and t = 6.3 s, the assertion at 6.29 s)
    /// are identical and completely settled: the card is at its final position, every control is
    /// drawn, there is no system alert, and nothing is moving. The button was **fully presented and
    /// unobstructed at the moment `isHittable` answered false.**
    ///
    /// So what failed is the *measurement*, not the screen. `isHittable` is one sample of a derived
    /// property, computed from an accessibility snapshot, and on a contended runner that sample can
    /// come back false for an element that is perfectly reachable a moment later — `UIWait`'s own
    /// header says the neighbouring half of this ("`frame` and `isHittable` are two separate
    /// snapshots, so an element can still move between them on a contended runner"). The failures
    /// cluster with other load symptoms: the third one shared its run with
    /// `DeepLinkSweepTests.testNothingIsAnnouncedTwice` failing on `Timed out while evaluating UI
    /// query`, which is #202's documented loaded-runner class.
    ///
    /// `settledFrame` — and `assertReachable` inside it — is a **predicate wait** on
    /// `exists && hittable`, re-evaluated until it holds. It absorbs a transient false; a bare
    /// property read cannot, because it has already returned. That is the whole repair, and the
    /// claim the test makes is unchanged: this button can be tapped. What changed is that the test
    /// now waits for that to be true rather than asking once and believing the first answer.
    ///
    /// The frame is read afterwards and printed beside the assertion, so a genuine failure reports
    /// *where* the control ended up rather than only that it could not be reached.
    ///
    /// ── And why the location state is pinned ────────────────────────────────────────────────────
    ///
    /// A second mechanism, **not** the cause of the three failures above — no alert appears in the
    /// recording — but one that produces the identical symptom and had to be ruled out rather than
    /// argued away. `CYPRESS_SCREEN=accountAsk` presents this sheet over the **map** tab root, and
    /// the map asks for location permission when it appears. In run 31899550700 the first test in
    /// this class met SpringBoard's `Allow "Cypress" to use your location?` alert over the sheet and
    /// spent three seconds in an interruption monitor answering it:
    ///
    ///     t = 24.04s  Found 1 interrupting element:
    ///     t = 24.04s      Find the "Allow “Cypress” to use your location?" Alert
    ///     t = 26.97s  Confirmed successful handling of interrupting element
    ///
    /// A `tap()` survives that, because tapping runs the interruption monitors. **Reading
    /// `isHittable` does not** — it returns false for a button underneath a system alert and logs
    /// nothing at all, so that mechanism and the one above are indistinguishable in a log.
    ///
    /// Pinning was verified rather than assumed, by resetting this simulator's location permission
    /// to undecided and running the class both ways on the same commit:
    ///
    ///     no pin, permission undecided   → 4 `use your location` alert lines, class 21.4 s
    ///     pinned, permission undecided   → 0 alert lines,                     class 19.8 s
    ///
    /// `denied` because this class has nothing to do with a fix: it is the most inert state that
    /// still keeps the provider from asking, and what the map draws underneath is covered anyway
    /// (RULINGS **R58**, task #121).
    private func launchAccountAsk(applePinnedTo pinned: String?) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CYPRESS_SCREEN"] = "accountAsk"
        app.launchEnvironment["CYPRESS_LOCATION"] = "denied"
        if let pinned { app.launchEnvironment["CYPRESS_APPLE_SIGN_IN"] = pinned }
        app.launch()

        // A predicate wait, not `waitForExistence` — see the header. This is the line the flake
        // was in, and the difference is that this one re-asks until the screen agrees.
        _ = settledFrame(
            app.buttons[Copy.decline].firstMatch,
            "screen 15's `\(Copy.decline)` control",
            timeout: 30
        )
        return app
    }

    /// The control exists and can be tapped.
    ///
    /// `isHittable` and not merely `exists`: a button under a scrim, off the bottom of a
    /// content-sized sheet, or behind another view exists in the tree and cannot be used, which is
    /// the failure this project has hit often enough to have a note about it.
    ///
    /// **The hittability is waited for, then asserted, and the settled frame is printed beside the
    /// assertion that uses it.** This is the repair for a ~50% CI flake whose evidence is in
    /// `launchAccountAsk`'s header — including the recording that shows the button fully drawn and
    /// unobstructed at the instant the old single-sample read called it untappable. The claim is
    /// unchanged; what changed is that the test waits for it instead of believing one answer.
    func testTheAppleButtonIsDrawnAndHittable() {
        let app = launchAccountAsk(applePinnedTo: nil)

        let apple = app.buttons[Copy.apple].firstMatch
        XCTAssertTrue(apple.exists, "screen 15 drew no `\(Copy.apple)`")

        // Settles the element under test in its own right, rather than inheriting the sheet's
        // settle from the helper: this is the button the assertion below is about.
        let frame = settledFrame(apple, "screen 15's `\(Copy.apple)`", timeout: 30)

        XCTAssertTrue(
            apple.isHittableWithoutRaising(in: app),
            """
            `\(Copy.apple)` is in the tree and cannot be tapped. Its settled frame is \(frame) on a \
            \(app.frame) screen. SCREENS.md 15 draws it as the sheet's filled primary control, above \
            the two outlined ones and above the consent row.
            """
        )

        // The label is Apple's own approved wording and the mock's, character for character. Asserted
        // here as well as in the unit suite because this is the string a person actually reads.
        XCTAssertEqual(apple.label, Copy.apple)
    }

    /// **The cancel path, which is the only reason this file needs a device.**
    ///
    /// SCREENS.md 15 draws no state for a dismissed provider sheet, and both alternatives to silence
    /// invent one: `noticeFailed` claims something went wrong when nothing did, and a new sentence is
    /// what DECISIONS constraint 21 forbids. So the screen must be **unchanged** afterwards — which
    /// is a claim about pixels and cannot be made anywhere but here.
    ///
    /// The assertions are positive-then-negative on purpose. "No failure notice" alone would pass on
    /// a build that drew the *unavailable* line, and "no notice" alone would pass on a build where
    /// the whole sheet had gone away.
    func testACancelledSheetLeavesScreenFifteenExactlyAsDrawn() {
        let app = launchAccountAsk(applePinnedTo: "cancel")

        app.buttons[Copy.apple].firstMatch.tap()

        // The sheet is still the sheet: every drawn control is still there and still usable.
        let apple = app.buttons[Copy.apple].firstMatch
        XCTAssertTrue(apple.waitForExistence(timeout: 10), "a cancelled sheet closed screen 15")
        // Same discipline as the hittability test: settle, then assert, and say where it settled.
        let settled = settledFrame(apple, "screen 15's `\(Copy.apple)` after a cancelled sheet", timeout: 30)
        XCTAssertTrue(
            apple.isHittableWithoutRaising(in: app),
            "a cancelled sheet left the Apple button untappable; it settled at \(settled)"
        )
        XCTAssertTrue(
            app.buttons[Copy.decline].firstMatch.exists,
            "a cancelled sheet took §7's decline control with it"
        )

        // And it says nothing about what happened, because nothing happened.
        for sentence in [Copy.failed, Copy.unavailable] {
            let notice = app.staticTexts
                .matching(NSPredicate(format: "label CONTAINS %@", sentence))
                .firstMatch
            XCTAssertFalse(
                notice.exists,
                """
                dismissing Apple's sheet drew "\(sentence)…". Nobody failed and nothing is \
                unavailable — a person closed a sheet, and screen 15 has nothing true to add.
                """
            )
        }
    }

    /// The control for the test above, and the half that makes it a measurement.
    ///
    /// Without this, a build that drew **no** notice for any outcome would pass the cancel test while
    /// swallowing every real failure — a control that acts and says nothing, which is the dishonesty
    /// `AccountAskPresentation.Notice` exists to prevent.
    func testAFailedAuthorizationDrawsTheNoticeThatCancellingDoesNot() {
        let app = launchAccountAsk(applePinnedTo: "fail")

        app.buttons[Copy.apple].firstMatch.tap()

        let notice = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", Copy.failed))
            .firstMatch
        XCTAssertTrue(
            notice.waitForExistence(timeout: 15),
            """
            an authorization that failed drew nothing. Screen 15 then has a control that acts and \
            says nothing, which is the same dishonesty as one claiming an account it did not create.
            """
        )
    }
}
