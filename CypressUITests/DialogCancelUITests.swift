//
//  DialogCancelUITests.swift
//  CypressUITests
//
//  ROADMAP item 77: every question that asks before something is deleted or taken back must draw
//  the button that does nothing, and that button must leave the thing where it was.
//
//  ── Why this file exists ───────────────────────────────────────────────────────────────────
//  PR #185 found that on iOS 26 a `confirmationDialog` is drawn as a popover with its title and its
//  destructive action, and **without its `.cancel` button**. The only way out is a tap outside it,
//  which nothing on screen tells a reader about. #185 moved its own question to an `.alert`, which
//  draws both buttons on iOS 18 and on iOS 26. The other questions in the app were still dialogs
//  and no test pressed their cancel, so nothing went red. Each test here opens one question,
//  presses its cancel, and checks that the question went away and the thing it asked about is
//  still there.
//
//  ── How the cancel is found ────────────────────────────────────────────────────────────────
//  By its label anywhere in the app, not inside `app.alerts`. That keeps the claim about the
//  reader ("is there a button that says Keep it?") rather than about the presentation, so the same
//  query reads a dialog and an alert. Each test first checks that no button with that label is on
//  screen before the question opens, so the button it then finds can only be the question's own.
//
//  Black-box like the rest of this target: nothing imports `Cypress`, and every literal is a copy
//  constant repeated by hand. If a string is renamed this fails, which is correct.
//
//  ── The one site with no test ──────────────────────────────────────────────────────────────
//  `AccountDeletionSheet`'s *Erase everything you have added?* is drawn only for a signed-in
//  account, and no deep link signs in (`AppleSignInUITests` says why: sign-in is a real
//  `POST /auth/oidc`). It got the same change as the six below.
//

import XCTest

final class DialogCancelUITests: XCTestCase, DeepLinkHarness {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: - The words, repeated by hand

    private enum Copy {
        // GrowthHistoryCopy
        static let growthLink = "See every reading"
        static let growthTitle = "Growth"
        static let withdrawPrefix = "Withdraw "
        static let withdrawTitle = "Withdraw this reading?"
        static let keepIt = "Keep it"
        // CheckInCopy / ObservationStatusLabel
        static let checkInTitle = "Check-in"
        static let statuses = ["Alive", "Declining", "Appears dead", "Removed?"]
        static let appearsDead = "Appears dead"
        static let deadTitle = "Report this tree as dead?"
        static let checkInCancel = "Cancel"
        // TreePhotosCopy / PhotoViewerCopy / TreeProfileCopy
        static let hero = "Photo of this tree"
        static let photoPillFragment = " · since "
        static let photoRowPrefix = "Photo · "
        static let browserDeletePrefix = "Delete, "
        static let viewerDelete = "Delete this photo"
        static let deleteTitle = "Delete this photo?"
        static let close = "Close"
        // ModerationCopy
        static let moderationAnchor = "Reported removed"
        static let confirmRemoved = "Confirm removed"
        static let removedTitle = "Mark this tree as removed?"
        static let dismiss = "Dismiss"
        static let dismissTitle = "Dismiss this report?"
        static let moderationCancel = "Cancel"
    }

    // MARK: - Screen 11: withdraw a reading

    func testKeepItOnWithdrawingAReadingKeepsTheReading() {
        let app = launch("fullyMeasured")
        let link = app.buttons[Copy.growthLink]
        guard link.waitForExistence(timeout: 60) else {
            XCTFail(deepLinkFailure(app) ?? "the fully measured tree drew no See every reading link")
            return
        }
        reach(link, in: app)
        link.tap()
        XCTAssertTrue(
            app.staticTexts[Copy.growthTitle].waitForExistence(timeout: 10),
            "See every reading did not open screen 11"
        )

        let withdraws = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", Copy.withdrawPrefix)
        )
        let withdraw = withdraws.firstMatch
        XCTAssertTrue(
            withdraw.waitForExistence(timeout: 10),
            "screen 11 offered no reading to withdraw, though this device wrote both of them"
        )
        let label = withdraw.label
        let before = withdraws.count
        reach(withdraw, in: app)

        openAndCancel(
            app, trigger: withdraw, title: Copy.withdrawTitle, cancel: Copy.keepIt,
            what: "Withdraw on a reading"
        )

        XCTAssertTrue(
            app.buttons[label].waitForExistence(timeout: 5),
            "Keep it withdrew the reading anyway: '\(label)' is gone"
        )
        XCTAssertEqual(withdraws.count, before, "Keep it changed how many readings screen 11 lists")
    }

    // MARK: - Screen 05: report a tree as dead

    func testCancelOnReportingATreeAsDeadLeavesTheStatus() {
        let app = launch("checkIn")
        guard arrive(app, screen: "checkIn", anchor: Copy.checkInTitle) else { return }

        let dead = app.buttons[Copy.appearsDead]
        XCTAssertTrue(dead.waitForExistence(timeout: 10), "screen 05 drew no Appears dead segment")
        let selectedBefore = selectedStatuses(app)
        XCTAssertFalse(
            selectedBefore.contains(Copy.appearsDead),
            "the check-in opened with Appears dead already chosen, so this cannot test leaving it"
        )
        reach(dead, in: app)

        openAndCancel(
            app, trigger: dead, title: Copy.deadTitle, cancel: Copy.checkInCancel,
            what: "Appears dead"
        )

        XCTAssertEqual(
            selectedStatuses(app), selectedBefore,
            "Cancel changed the status the check-in had chosen"
        )
    }

    // MARK: - Screen 20: delete a photograph from the browser

    func testKeepItOnDeletingAPhotoInTheBrowserKeepsThePhoto() {
        let app = launch("communityPhotos")
        guard app.buttons[Copy.hero].waitForExistence(timeout: 60) else {
            XCTFail(deepLinkFailure(app) ?? "the community add drew no photograph to delete")
            return
        }
        let pill = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", Copy.photoPillFragment))
            .firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 10), "screen 03 drew no photo-count pill")
        assertReachable(pill, "the photo-count pill")
        pill.tap()

        let rows = app.images.matching(NSPredicate(format: "label BEGINSWITH %@", Copy.photoRowPrefix))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10), "the pill did not open screen 20")
        let before = rows.count
        let trash = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", Copy.browserDeletePrefix))
            .firstMatch
        XCTAssertTrue(
            trash.waitForExistence(timeout: 10),
            "screen 20 offered no delete on this device's photograph"
        )
        assertReachable(trash, "the browser's delete")

        openAndCancel(
            app, trigger: trash, title: Copy.deleteTitle, cancel: Copy.keepIt,
            what: "the browser's delete"
        )

        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5), "Keep it deleted the photograph anyway")
        XCTAssertEqual(rows.count, before, "Keep it changed how many photographs screen 20 lists")
    }

    // MARK: - The photo viewer: delete the photograph on screen

    func testKeepItOnDeletingAPhotoInTheViewerKeepsThePhoto() {
        let app = launch("communityPhotos")
        let hero = app.buttons[Copy.hero]
        guard hero.waitForExistence(timeout: 60) else {
            XCTFail(deepLinkFailure(app) ?? "the community add drew no photograph to delete")
            return
        }
        assertReachable(hero, "the hero photograph")
        hero.tap()
        XCTAssertTrue(
            app.buttons[Copy.close].waitForExistence(timeout: 10),
            "the photograph did not open the viewer"
        )
        let delete = app.buttons[Copy.viewerDelete]
        XCTAssertTrue(
            delete.waitForExistence(timeout: 10),
            "the viewer offered no delete on this device's photograph"
        )
        assertReachable(delete, "the viewer's delete")

        openAndCancel(
            app, trigger: delete, title: Copy.deleteTitle, cancel: Copy.keepIt,
            what: "the viewer's delete"
        )

        // The viewer closes itself after a deletion, so both of these being here is the photograph
        // still existing.
        XCTAssertTrue(app.buttons[Copy.close].exists, "Keep it closed the viewer, which a deletion does")
        XCTAssertTrue(app.buttons[Copy.viewerDelete].exists, "Keep it left the viewer without its delete")
    }

    // MARK: - The You tab: a lead's review queue

    func testCancelOnConfirmingAReviewKeepsTheReview() {
        let app = launch("moderationReview")
        guard arrive(app, screen: "moderationReview", anchor: Copy.moderationAnchor) else { return }

        let confirms = app.buttons.matching(NSPredicate(format: "label == %@", Copy.confirmRemoved))
        let confirm = confirms.firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "the review queue drew no Confirm removed")
        let before = confirms.count
        reach(confirm, in: app)

        openAndCancel(
            app, trigger: confirm, title: Copy.removedTitle, cancel: Copy.moderationCancel,
            what: "Confirm removed"
        )

        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Cancel confirmed the review anyway")
        XCTAssertEqual(confirms.count, before, "Cancel changed how many removals wait for review")
    }

    func testCancelOnDismissingAReviewKeepsTheReview() {
        let app = launch("moderationReview")
        guard arrive(app, screen: "moderationReview", anchor: Copy.moderationAnchor) else { return }

        let dismissals = app.buttons.matching(NSPredicate(format: "label == %@", Copy.dismiss))
        let dismiss = dismissals.firstMatch
        XCTAssertTrue(dismiss.waitForExistence(timeout: 10), "the review queue drew no Dismiss")
        let before = dismissals.count
        reach(dismiss, in: app)

        openAndCancel(
            app, trigger: dismiss, title: Copy.dismissTitle, cancel: Copy.moderationCancel,
            what: "Dismiss"
        )

        XCTAssertTrue(dismiss.waitForExistence(timeout: 5), "Cancel dismissed the review anyway")
        XCTAssertEqual(dismissals.count, before, "Cancel changed how many reviews wait")
    }

    // MARK: - Harness

    /// Taps `trigger`, waits for the question titled `title`, presses its `cancel`, and checks the
    /// question went away. The cancel is looked for by label anywhere in the app; see the file
    /// header for why, and for why nothing with that label may be on screen first.
    private func openAndCancel(
        _ app: XCUIApplication,
        trigger: XCUIElement,
        title: String,
        cancel: String,
        what: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(
            app.buttons[cancel].exists,
            "a '\(cancel)' button is on screen before the question opens, so the question's own "
                + "could not be told apart from it",
            file: file, line: line
        )
        trigger.tap()

        let question = app.staticTexts[title]
        XCTAssertTrue(
            question.waitForExistence(timeout: 10),
            "\(what) did not ask '\(title)' first",
            file: file, line: line
        )

        let keep = app.buttons[cancel].firstMatch
        assertReachable(
            keep,
            "the question '\(title)' was drawn, and its cancel button '\(cancel)'",
            timeout: 10, file: file, line: line
        )
        keep.tap()

        XCTAssertTrue(
            question.waitForNonExistence(timeout: 10),
            "'\(cancel)' was pressed and the question '\(title)' stayed on screen",
            file: file, line: line
        )
    }

    /// The status segments that carry the selected trait, by label.
    private func selectedStatuses(_ app: XCUIApplication) -> [String] {
        Copy.statuses.filter { app.buttons[$0].exists && app.buttons[$0].isSelected }
    }

    /// Swipes up, a bounded number of times, until `element` can be pressed where it is drawn.
    private func reach(_ element: XCUIElement, in app: XCUIApplication) {
        let screen = app.frame
        for _ in 0..<6 where !element.isHittableWithoutRaising(onScreen: screen) {
            app.swipeUp()
        }
        assertReachable(element, "'\(element.label)'", timeout: 10)
    }
}
