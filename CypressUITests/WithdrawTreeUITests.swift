//
//  WithdrawTreeUITests.swift
//  CypressUITests
//
//  The adder withdraws a community tree (the owner's answers of 2026-11-16), end to end on the
//  running app.
//
//  1. A tree this installation just added, signed out, offers `Withdraw this tree`. The alert asks
//     first, with the "only you" message. `Withdraw tree` takes the reader back off the profile, and
//     the tree's profile no longer opens.
//  2. Signed in and sharing, the alert carries the shared message.
//  3. With another account's visit on the tree, the reason line draws in place of the control.
//  4. After the service refuses (`debugRefuseTreeWithdrawal`), the Outbox row reads
//     `Tree withdrawn · …` with the owner's sentence.
//  5. A city tree offers no control.
//
//  The "Keep it" press is in `DialogCancelUITests`, with the app's other cancels.
//
//  Black-box like the rest of this target: nothing imports `Cypress`, and every literal is a copy
//  constant repeated by hand (`TreeProfileCopy`, `OutboxCopy`, `OutboxFailureReason`).
//

import XCTest

final class WithdrawTreeUITests: XCTestCase, DeepLinkHarness {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private enum Copy {
        static let action = "Withdraw this tree"
        static let title = "Withdraw this tree?"
        static let confirm = "Withdraw tree"
        static let onlyYouMessage = "Only you can see this tree. It comes off the map. This cannot be undone."
        static let sharedMessage = "Everyone using Cypress stops seeing this tree once this is sent. "
            + "If someone else has visited or photographed it, it stays. This cannot be undone."
        static let staysOnTheMap = "Other people have added to this tree, so it stays on the map."
        static let reportNoTree = "Report that there is no tree here"
        static let showWhere = "Show me where this is"
        static let outboxRowPrefix = "Tree withdrawn · "
    }

    /// Opens `screen` and waits for the profile's withdraw control, scrolled into reach.
    private func arriveAtControl(_ screen: String) -> (XCUIApplication, XCUIElement)? {
        let app = launch(screen)
        let action = app.buttons[Copy.action]
        guard action.waitForExistence(timeout: 60) else {
            XCTFail(
                deepLinkFailure(app).map { "\(screen): \($0)" }
                    ?? "\(screen): the profile of a tree this phone just added drew no '\(Copy.action)'"
            )
            return nil
        }
        reach(action, in: app)
        return (app, action)
    }

    // MARK: - 1 · Withdraw a tree only you can see

    func testWithdrawingATreeOnlyYouCanSeeAsksAndThenLeavesTheProfile() {
        guard let (app, action) = arriveAtControl("withdrawTree") else { return }

        // The control sits below "Report that there is no tree here", in the same column.
        let report = app.buttons[Copy.reportNoTree]
        if report.exists {
            XCTAssertLessThan(report.frame.midY, action.frame.midY, "the control is not below the report link")
            XCTAssertEqual(report.frame.minX, action.frame.minX, accuracy: 1, "the control is not in the report link's column")
        }

        action.tap()
        let title = app.staticTexts[Copy.title]
        XCTAssertTrue(title.waitForExistence(timeout: 10), "the control did not ask '\(Copy.title)' first")
        XCTAssertTrue(app.staticTexts[Copy.onlyYouMessage].exists,
                      "the alert for a tree only you can see does not carry the 'only you' message")
        attachScreenshot(app, "withdraw-alert-only-you")

        let confirm = app.buttons[Copy.confirm]
        assertReachable(confirm, "the alert's '\(Copy.confirm)'")
        confirm.tap()

        XCTAssertTrue(title.waitForNonExistence(timeout: 10), "the alert stayed after '\(Copy.confirm)'")
        XCTAssertTrue(
            action.waitForNonExistence(timeout: 15),
            "the profile of the withdrawn tree is still on screen"
        )
    }

    // MARK: - 2 · A shared tree's message

    func testTheAlertForASharedTreeCarriesTheSharedMessage() {
        guard let (app, action) = arriveAtControl("withdrawTreeShared") else { return }
        attachScreenshot(app, "withdraw-profile-control")
        action.tap()
        XCTAssertTrue(app.staticTexts[Copy.title].waitForExistence(timeout: 10), "the control did not ask first")
        // A subscript takes an identifier of at most 128 characters, and the shared message is
        // longer: XCUITest throws "Invalid query" on it. Match the label through a predicate.
        let shared = app.staticTexts.matching(NSPredicate(format: "label == %@", Copy.sharedMessage))
        XCTAssertTrue(shared.firstMatch.exists,
                      "the alert for a shared tree does not carry the shared message")
        attachScreenshot(app, "withdraw-alert-shared")
    }

    // MARK: - 3 · Somebody else built on it

    func testAnotherAccountsVisitDrawsTheReasonLineInPlaceOfTheControl() {
        let app = launch("withdrawTreeBuiltOn")
        let line = app.staticTexts[Copy.staysOnTheMap]
        guard line.waitForExistence(timeout: 60) || scrollUntilExists(line, in: app) else {
            XCTFail(
                deepLinkFailure(app).map { "withdrawTreeBuiltOn: \($0)" }
                    ?? "withdrawTreeBuiltOn: the profile drew no '\(Copy.staysOnTheMap)'"
            )
            return
        }
        XCTAssertFalse(app.buttons[Copy.action].exists, "the control is drawn beside its reason line")
        reach(line, in: app)
        attachScreenshot(app, "withdraw-profile-reason-line")
    }

    // MARK: - 4 · The Outbox after a refusal

    func testARefusedWithdrawalReadsTheOwnersSentenceInTheOutbox() {
        let app = launch("withdrawTreeRefused")
        let row = app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH %@", Copy.outboxRowPrefix))
            .firstMatch
        guard row.waitForExistence(timeout: 60) else {
            XCTFail(
                deepLinkFailure(app).map { "withdrawTreeRefused: \($0)" }
                    ?? "the Outbox drew no row titled '\(Copy.outboxRowPrefix)…'"
            )
            return
        }
        XCTAssertTrue(app.staticTexts[Copy.staysOnTheMap].waitForExistence(timeout: 10),
                      "the refused row does not carry the owner's sentence")
        attachScreenshot(app, "withdraw-outbox-refused")
    }

    // MARK: - 5 · The largest text size

    /// At AX5 the control is still reachable, and the alert still draws its title and both buttons
    /// where they can be pressed. The test presses `Keep it`, so it withdraws nothing.
    func testTheControlAndTheAlertAtTheLargestTextSize() {
        let app = XCUIApplication()
        app.launchEnvironment[Self.deepLinkScreenKey] = "withdrawTree"
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        DebugMapCamera.pin(app)
        app.launch()

        let action = app.buttons[Copy.action]
        guard action.waitForExistence(timeout: 60) else {
            XCTFail(deepLinkFailure(app).map { "withdrawTree: \($0)" } ?? "no '\(Copy.action)' at AX5")
            return
        }
        reach(action, in: app)
        attachScreenshot(app, "withdraw-profile-control-ax5")
        action.tap()

        XCTAssertTrue(app.staticTexts[Copy.title].waitForExistence(timeout: 10), "no alert at AX5")
        let confirm = app.buttons[Copy.confirm]
        let keep = app.buttons["Keep it"]
        // At this size iOS lays the alert out as a scrolling sheet; each button must be pressable.
        for _ in 0..<4 where !keep.isHittableWithoutRaising(onScreen: app.frame) { app.alerts.firstMatch.swipeUp() }
        assertReachable(keep, "the alert's 'Keep it' at AX5")
        XCTAssertTrue(confirm.exists, "the alert's '\(Copy.confirm)' is missing at AX5")
        attachScreenshot(app, "withdraw-alert-ax5")
        keep.tap()
        XCTAssertTrue(app.staticTexts[Copy.title].waitForNonExistence(timeout: 10), "Keep it left the alert up")
        XCTAssertTrue(action.waitForExistence(timeout: 10), "Keep it withdrew the tree anyway")
    }

    // MARK: - 6 · Not on a city tree

    func testACityTreeOffersNoWithdrawal() {
        let app = launch("treeProfile")
        let showWhere = app.buttons[Copy.showWhere]
        guard showWhere.waitForExistence(timeout: 60) else {
            XCTFail(deepLinkFailure(app).map { "treeProfile: \($0)" } ?? "treeProfile: the profile never drew")
            return
        }
        for _ in 0..<6 { app.swipeUp() }
        XCTAssertFalse(app.buttons[Copy.action].exists, "a city tree from the seed offers a withdrawal")
    }

    // MARK: - Harness

    /// Swipes up, a bounded number of times, until `element` can be pressed where it is drawn.
    private func reach(_ element: XCUIElement, in app: XCUIApplication) {
        let screen = app.frame
        for _ in 0..<6 where !element.isHittableWithoutRaising(onScreen: screen) {
            app.swipeUp()
        }
        assertReachable(element, "'\(element.label)'", timeout: 10)
    }

    private func scrollUntilExists(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        for _ in 0..<6 where !element.exists { app.swipeUp() }
        return element.exists
    }

    /// Keeps a screenshot with the test's result, and writes it to `CYPRESS_SHOT_DIR` when the run
    /// sets one, so the state can be looked at after the run.
    private func attachScreenshot(_ app: XCUIApplication, _ name: String) {
        let shot = app.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["CYPRESS_SHOT_DIR"], !dir.isEmpty {
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }
}
