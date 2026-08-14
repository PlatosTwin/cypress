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
/// credential and `POST /auth/oidc` at `cypress-sync`, which is a mutated build talking to
/// production. Both values below refuse before anything reaches the network, so this suite is
/// hermetic — it opens no socket, exactly like `RemoteGateComplaintUITests`.
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

    /// Opens screen 15, returning the app.
    ///
    /// The arrival is confirmed on §7's decline control rather than on the Apple button, so that a
    /// build which drew the sheet *without* the Apple button fails in the test that is about the
    /// Apple button rather than in this helper.
    private func launchAccountAsk(applePinnedTo pinned: String?) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CYPRESS_SCREEN"] = "accountAsk"
        if let pinned { app.launchEnvironment["CYPRESS_APPLE_SIGN_IN"] = pinned }
        app.launch()

        let decline = app.buttons[Copy.decline].firstMatch
        XCTAssertTrue(
            decline.waitForExistence(timeout: 30),
            "the account ask did not appear — CYPRESS_SCREEN=accountAsk presented nothing"
        )
        return app
    }

    /// The control exists and can be tapped.
    ///
    /// `isHittable` and not merely `exists`: a button under a scrim, off the bottom of a
    /// content-sized sheet, or behind another view exists in the tree and cannot be used, which is
    /// the failure this project has hit often enough to have a note about it.
    func testTheAppleButtonIsDrawnAndHittable() {
        let app = launchAccountAsk(applePinnedTo: nil)

        let apple = app.buttons[Copy.apple].firstMatch
        XCTAssertTrue(apple.exists, "screen 15 drew no `\(Copy.apple)`")
        XCTAssertTrue(
            apple.isHittable,
            """
            `\(Copy.apple)` is in the tree and cannot be tapped. SCREENS.md 15 draws it as the sheet's \
            filled primary control, above the two outlined ones and above the consent row.
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
        XCTAssertTrue(apple.isHittable, "a cancelled sheet left the Apple button untappable")
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
