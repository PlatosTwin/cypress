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
        /// `AccountAskCopy.noticeUnavailable`'s opening clause, as the owner ruled it on 2026-08-14
        /// (ruling 4). It used to read "Accounts are not ready yet", which stopped being true in the
        /// round `Continue with Apple` started working.
        static let unavailable = "Google and email sign-in are coming later"
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
    /// **Two mechanisms, and they are complementary rather than rival.** An earlier version of this
    /// header claimed the recording refuted the presentation race. It does not, and the claim was
    /// made by comparing two extracted frames *by eye* rather than by measuring them — recorded here
    /// because it is the more instructive half of this repair.
    ///
    /// The xcresult from run 31900590782 carries a recording of the failing test. Decoded properly —
    /// every one of its 137 frames through `AVAssetReader`, hashing raw BGRA buffers, rather than
    /// sampling times through `AVAssetImageGenerator` — the last 300 ms read:
    ///
    ///     frame 129  pts=6.0100  changedFromPrev=100405
    ///     frame 131  pts=6.1067  changedFromPrev= 35578
    ///     frame 133  pts=6.1233  changedFromPrev=  9500
    ///     frame 136  pts=6.2967  changedFromPrev= 11378   <- last frame; assertion ≈ 6.253
    ///
    /// against a measured floor of 0 on a static stretch of the same recording (frames 72→73 are
    /// byte-identical, and a frame differenced with itself is 0). So those residuals are motion, and
    /// they decay monotonically **across the failure instant**: the presentation was still
    /// converging. The two frames the earlier claim called "identical" differ by 106,960 pixels
    /// (3.35%), 5,954 of them inside the Apple button's own rectangle.
    ///
    /// The method error is worth naming so it is not repeated: `AVAssetImageGenerator` on a
    /// variable-frame-rate recording collapses nearby requests onto one frame unless the tolerances
    /// are zero, and this recording **ends at 6.2967 s**, essentially at the assertion — so there is
    /// no "after" frame to compare against at all.
    ///
    /// What the artifact does support, and it is not nothing: at the failure instant the sheet was
    /// at its final position, every control was drawn, and there was **no system alert**. So the
    /// button was presented and unobstructed — and still not reported hittable.
    ///
    /// That leaves both mechanisms live, and either is sufficient:
    ///
    /// 1. **the presentation was still converging**, which is a perfectly good reason for a
    ///    compositor to answer "not hittable" for a control that is drawn where it will finally be;
    /// 2. **a single sample of a derived property is fragile under load** — `UIWait`'s own header
    ///    records the neighbouring half ("`frame` and `isHittable` are two separate snapshots, so an
    ///    element can still move between them on a contended runner"), and these failures cluster
    ///    with load symptoms; the third shared its run with `DeepLinkSweepTests
    ///    .testNothingIsAnnouncedTwice` failing on `Timed out while evaluating UI query`, #202's
    ///    documented class.
    ///
    /// **The repair does not need to choose between them, which is why it is the right repair.**
    /// `settledFrame` waits on `exists && hittable` (through `assertReachable`) and then for the
    /// frame to stop moving. A predicate wait re-evaluates, so it absorbs a transient false; the
    /// settle loop absorbs a presentation still converging. A bare property read absorbs neither,
    /// because it has already returned.
    ///
    /// **The wait is therefore the assertion**, and there is deliberately no second read *of the
    /// property it just proved*. That is the rule, and it is about derived properties recomputed
    /// from a snapshot — `isHittable`, `exists` — not about every line that follows a wait: the
    /// label equality in `testTheAppleButtonIsDrawnAndHittable` is a different claim about a static
    /// string, and it stays.
    /// The first version of this fix kept one — `XCTAssertTrue(apple.isHittableWithoutRaising(…))`
    /// on the line after the wait — which reintroduced the whole defect 310 ms later and, under
    /// `continueAfterFailure = false`, could never even report: a genuinely unhittable button aborts
    /// inside the wait, so that assertion's message was unreachable on every real defect and
    /// reachable only on the transient it was supposed to remove. The claim this test makes lives in
    /// the description passed to `settledFrame`, where a failure prints it.
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
            "screen 15's decline control (CYPRESS_SCREEN=accountAsk)",
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
    /// **The hittability is waited for, and the wait is the whole assertion.** This is the repair
    /// for a ~50% CI flake whose evidence is in `launchAccountAsk`'s header.
    ///
    /// The two failures a reader will want told apart are still told apart, by `assertReachable`
    /// inside the wait: *"never appeared in the accessibility tree at all"* is a button that is not
    /// drawn, and *"is in the accessibility tree but never became hittable"* is one that is drawn
    /// and cannot be used. That is why dropping the separate `exists` check costs nothing.
    func testTheAppleButtonIsDrawnAndHittable() {
        let app = launchAccountAsk(applePinnedTo: nil)

        let apple = app.buttons[Copy.apple].firstMatch

        // **This call is the assertion.** It waits on `exists && hittable` and then on the frame
        // holding still, and it fails with the description below if either never happens — so there
        // is deliberately nothing after it re-reading the same property. See the header for what
        // keeping that second read cost.
        //
        // The description carries the claim, because the description is what a failure prints.
        _ = settledFrame(
            apple,
            """
            screen 15's `\(Copy.apple)` (SCREENS.md 15 draws it as the sheet's filled primary \
            control, above the two outlined ones and above the consent row)
            """,
            timeout: 30
        )

        // The label is Apple's own approved wording and the mock's, character for character. Asserted
        // here as well as in the unit suite because this is the string a person actually reads.
        //
        // **It is also the assertion that the mark did not take the label's words.** The owner's
        // ruling 6 of 2026-08-14 put Apple's logo ahead of this title inside the same control, and
        // the accessible name of a button carrying an image and a label is whatever the two of them
        // contribute — an unhidden decorative `Shape` would have made it "Apple, Continue with
        // Apple" or worse. `AppleMark` is `accessibilityHidden`, and this equality is what says so
        // on a device rather than in a comment.
        //
        // **And it is a second claim, not a second sample of the one above.** The wait proves the
        // control can be reached; this proves what it is called, which no wait covers. It is
        // therefore exempt from the rule this file's header sets, and the exemption is the point:
        // `label` is a static string rather than a property recomputed from a snapshot, so it was
        // never exposed to the mechanism that made `isHittable` unreliable under load. The
        // flake repair deleted this line in passing and review caught it — which mattered, because
        // by then it was carrying the ruling above.
        XCTAssertEqual(apple.label, Copy.apple)
    }

    /// **Apple's minimum button size, measured on the running screen** — the one part of ruling 6's
    /// guidelines that no unit test can reach, because it is a property of the drawn control on a
    /// real width rather than of any value in the source.
    ///
    /// "Minimum width 140 pt, minimum height 30 pt", from the same HIG section the mark's geometry
    /// comes from (`AppleMark`'s header cites it). The app's own 44 pt target floor is stricter on
    /// height and is asserted with it, so a regression that shrank the control to Apple's floor
    /// while breaking this app's would still be red.
    ///
    /// The width is checked against the two outlined routes as well: 15 draws all three the same
    /// width, and a mark that had been allowed to shrink its own button — by hugging instead of
    /// filling — would leave the Apple route narrower than the two beneath it while every other
    /// assertion in this file passed.
    func testTheAppleButtonKeepsApplesMinimumSize() {
        let app = launchAccountAsk(applePinnedTo: nil)

        let apple = app.buttons[Copy.apple].firstMatch
        XCTAssertTrue(apple.exists, "screen 15 drew no `\(Copy.apple)`")
        let frame = apple.frame

        XCTAssertGreaterThanOrEqual(
            frame.width, 140,
            "the button is \(frame.width) pt wide, under Apple's 140 pt minimum for a Sign in with Apple button"
        )
        XCTAssertGreaterThanOrEqual(
            frame.height, 44,
            "the button is \(frame.height) pt tall, under this app's 44 pt target floor (Apple's own minimum is 30)"
        )

        let decline = app.buttons[Copy.decline].firstMatch
        XCTAssertTrue(decline.exists)
        XCTAssertGreaterThanOrEqual(
            frame.width, decline.frame.width,
            """
            the Apple route is \(frame.width) pt wide against \(decline.frame.width) pt for §7's \
            decline control, so it is no longer the full-width primary SCREENS.md 15 §3 draws — the \
            mark has taken width off its own button.
            """
        )
    }

    /// **The cancel path, which is the only reason this file needs a device.**
    ///
    /// ── The second intermittent, and why it is the same repair ─────────────────────────────────
    ///
    /// This test flaked too — run 31908706994, `ui (1)`, on a Python-only diff — with
    /// *"dismissing Apple's sheet drew `Accounts are not ready yet…`"*. A **cancel** cannot produce
    /// the **unavailable** notice: `AccountAskModel.link` draws that one for `onLink == nil` or for
    /// `AccountLinkRefusal.unavailable`, which `RootView.accountLink()` throws only for Google and
    /// email. So the tap had to have been routed somewhere other than the Apple button.
    ///
    /// The xcresult carries the answer, in the synthesized-event attachments rather than the video.
    /// The tap was delivered at **(201.0, 584.0)** — and the log shows *when*:
    ///
    ///     t = 14.27s  Tap "Continue with Apple" Button
    ///     t = 14.37s      Find the "Continue with Apple" Button      <- coordinate resolved here
    ///     t = 14.55s      Check for interrupting elements …
    ///     t = 15.31s      Found 1 interrupting element: … location Alert
    ///     t = 15.96s      Default interruption handler … tapping "Don’t Allow"
    ///     t = 18.26s      Synthesize event                           <- delivered here, 3.9 s later
    ///
    /// Decoding the recording per-frame: at **resolve** (t = 14.37 s) the button's fill had not
    /// reached full opacity — the presentation was still converging, the same finding as the
    /// hittability test's; by **delivery** (t = 18.26 s) the settled rect was y = 549.0…594.3 pt, so
    /// the stale coordinate landed 10.3 pt from its bottom edge. The notice appeared in the very
    /// next frames (dark pixels in the notice band 4,309 → 42,541 between t = 18.27 s and 18.60 s),
    /// so the tap caused it.
    ///
    /// **Both halves of this file's repair address that directly**, which is why there is no third
    /// change: settling the sheet before anything is tapped removes the resolve-while-converging
    /// half, and pinning `CYPRESS_LOCATION` removes the interruption that opened a 3.9-second gap
    /// between resolving a coordinate and delivering a touch to it. Without an alert there is no
    /// gap; without a gap the coordinate cannot go stale.
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
        // Same discipline as the hittability test, and the same reason there is no read after it:
        // this call asserts that the sheet is still standing and still usable.
        _ = settledFrame(
            apple,
            "screen 15's `\(Copy.apple)` after a cancelled sheet",
            timeout: 30
        )
        // Routed through the same wait rather than left as a bare read, because the header makes a
        // rule of that and a reader will apply it file-wide. Reachability is also the truer claim
        // here: §7's decline is a control a person is meant to be able to press, and "it is still
        // in the tree" would be satisfied by one that had become unpressable.
        assertReachable(
            app.buttons[Copy.decline].firstMatch,
            "screen 15's §7 decline control after a cancelled sheet"
        )

        // And it says nothing about what happened, because nothing happened.
        //
        // **A bounded wait, not `exists`.** An absence asserted by one instantaneous read is the
        // weakest kind of assertion in this file: it passes if the thing simply has not been drawn
        // *yet*. Giving it three seconds to be falsified is what makes "nothing appeared" a claim
        // rather than a coincidence — and it is the same lesson as the hittability read above,
        // pointing the other way.
        //
        // The real budget is wider than the 3 s suggests, because `settledFrame` and the first
        // sentence's wait run before the second's: measured from the tap, sentence 1's window is
        // tap+1.6 s → tap+4.7 s and sentence 2's is tap+4.8 s → tap+7.8 s. The failure that
        // motivated this was on `unavailable`, which gets the later window.
        //
        // **TRIPWIRE, because this bound is calibrated against a synchronous link path.** Today the
        // notice is set on a synchronous model update — `RemoteAccess.disabled` in DEBUG, an
        // `OfflineSession`, no socket — so a notice that is going to be drawn is drawn within a
        // frame or two of the tap, and 4.7 s is orders of magnitude more than it needs. If the
        // account-link path ever becomes genuinely **async** — a real exchange, a retry, anything
        // carrying a multi-second timeout — a late notice slips past this window and the test goes
        // green with the defect present, which is this repository's signature failure. Whoever makes
        // that change has to revisit this number.
        for sentence in [Copy.failed, Copy.unavailable] {
            let notice = app.staticTexts
                .matching(NSPredicate(format: "label CONTAINS %@", sentence))
                .firstMatch
            XCTAssertFalse(
                notice.waitForExistence(timeout: 3),
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
