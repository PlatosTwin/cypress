//
//  WithdrawTreeUITests.swift
//  CypressUITests
//
//  The adder withdraws a community tree (the owner's answers of 2026-11-16), end to end on the
//  running app.
//
//  1. A tree this installation just added, signed out, offers `Withdraw this tree`. The alert asks
//     first, with the "only you" message. `Withdraw tree` takes the reader back off the profile, and
//     the tree's profile no longer opens. While the control shows, `Report that there is no tree
//     here` does not (the owner's answer of 2026-11-16).
//  2. Signed in and sharing, the alert carries the shared message.
//  3. Signed in and sharing, with another account's visit on the tree, the reason line draws in
//     place of the control, below the report link that comes back in this state, and the profile
//     does not say only the reader can see the tree.
//  4. After the service refuses (`debugRefuseTreeWithdrawal`), the Outbox row reads
//     `Tree withdrawn · Sycamore, London Plane` with the owner's sentence, and that row draws no
//     Retry.
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
        static let onlyYouPrefix = "Only you can see this tree"
        static let reportNoTree = "Report that there is no tree here"
        static let cityRecordReport = "Report a mistake in the city’s record"
        static let showWhere = "Show me where this is"
        /// The debug tree is added with the seed's first `Platanus` match, whose common name is
        /// "Sycamore, London Plane". Rows name an added tree by its species (the owner's answer of
        /// 2026-11-16, "Use the species"), as its profile title does.
        static let outboxRowTitle = "Tree withdrawn · Sycamore, London Plane"
        /// `OutboxCopy.retryAction`, the retry control's accessibility label.
        static let retry = "Retry"
    }

    /// `DebugLocationOverride.westernAddition`, the same point `DebugMapCamera.dense` pins the
    /// camera to, spelled out because a UI test cannot import the app target.
    private static let fix = "37.78485,-122.4215"

    /// `launch(_:)` with the location pinned (`CYPRESS_LOCATION`).
    ///
    /// **Pinned because an unpinned launch can block the app's main thread for 30 s and more**
    /// (found 2026-11-16). `MapLocationProvider.init` reads `CLLocationManager.authorizationStatus`,
    /// a synchronous call to the location daemon, on the main thread. On a fresh install the
    /// daemon was seen to hold that reply long enough that XCUITest reported "main thread busy for
    /// 30.0s", most often in `withdrawTreeBuiltOn` run alone. The pinned provider never makes that
    /// call.
    private func launchPinned(
        _ screen: String, contentSize: String? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment[Self.deepLinkScreenKey] = screen
        app.launchEnvironment["CYPRESS_LOCATION"] = Self.fix
        if let contentSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize]
        }
        DebugMapCamera.pin(app)
        app.launch()
        return app
    }

    /// Opens `screen` and waits for the profile's withdraw control, scrolled into reach.
    private func arriveAtControl(_ screen: String) -> (XCUIApplication, XCUIElement)? {
        let app = launchPinned(screen)
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

        // The control is present (`arriveAtControl`) and sits in the column of the links above it,
        // with `Show me where this is` as the reference: it is drawn on every profile. While the
        // control shows, the report link is not drawn (the owner's answer of 2026-11-16, "Hide it
        // while withdraw shows"); the control's presence is what makes that absence a fact.
        let showWhere = app.buttons[Copy.showWhere]
        XCTAssertTrue(showWhere.exists, "the profile drew no '\(Copy.showWhere)' to measure the column by")
        XCTAssertLessThan(showWhere.frame.midY, action.frame.midY, "the control is not below the column's first link")
        XCTAssertEqual(showWhere.frame.minX, action.frame.minX, accuracy: 1, "the control is not in the links' column")
        XCTAssertFalse(app.buttons[Copy.reportNoTree].exists,
                       "'\(Copy.reportNoTree)' is drawn beside '\(Copy.action)'")
        attachScreenshot(app, "withdraw-profile-control-only-you")

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
        let app = launchPinned("withdrawTreeBuiltOn")
        let line = app.staticTexts[Copy.staysOnTheMap]
        guard line.waitForExistence(timeout: 60) || scrollUntilExists(line, in: app) else {
            XCTFail(
                deepLinkFailure(app).map { "withdrawTreeBuiltOn: \($0)" }
                    ?? "withdrawTreeBuiltOn: the profile drew no '\(Copy.staysOnTheMap)'"
            )
            return
        }
        // The report link comes back in this state, as the adder's way to say the tree is gone (the
        // owner's answer of 2026-11-16), and the reason line sits below it.
        let report = app.buttons[Copy.reportNoTree]
        XCTAssertTrue(report.exists, "the reason line is drawn without '\(Copy.reportNoTree)' above it")
        XCTAssertLessThan(report.frame.midY, line.frame.midY, "the reason line is not below the report link")
        XCTAssertFalse(app.buttons[Copy.action].exists, "the control is drawn beside its reason line")
        // A screen a person can reach: another account can only build on a tree everyone sees, so
        // the profile must not also say that only the reader can see it.
        let onlyYou = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", Copy.onlyYouPrefix))
        XCTAssertFalse(onlyYou.firstMatch.exists, "the reason line is drawn on a tree only the reader can see")
        reach(line, in: app)
        attachScreenshot(app, "withdraw-profile-reason-line")
    }

    /// The reason line at AX5, for its spacing under the report link's caption. A screenshot only:
    /// the line's presence is test 3's assertion.
    func testTheReasonLineAtTheLargestTextSize() {
        let app = launchPinned(
            "withdrawTreeBuiltOn", contentSize: "UICTContentSizeCategoryAccessibilityXXXL"
        )

        let line = app.staticTexts[Copy.staysOnTheMap]
        guard line.waitForExistence(timeout: 60) || scrollUntilExists(line, in: app) else {
            XCTFail(deepLinkFailure(app).map { "withdrawTreeBuiltOn: \($0)" } ?? "no reason line at AX5")
            return
        }
        reach(line, in: app)
        attachScreenshot(app, "withdraw-profile-reason-line-ax5")
    }

    // MARK: - 4 · The Outbox after a refusal

    func testARefusedWithdrawalReadsTheOwnersSentenceInTheOutbox() {
        let app = launchPinned("withdrawTreeRefused")
        let row = app.staticTexts
            .matching(NSPredicate(format: "label == %@", Copy.outboxRowTitle))
            .firstMatch
        guard row.waitForExistence(timeout: 60) else {
            XCTFail(
                deepLinkFailure(app).map { "withdrawTreeRefused: \($0)" }
                    ?? "the Outbox drew no row titled '\(Copy.outboxRowTitle)'"
            )
            return
        }
        let reason = app.staticTexts[Copy.staysOnTheMap]
        XCTAssertTrue(reason.waitForExistence(timeout: 10),
                      "the refused row does not carry the owner's sentence")
        // No Retry in that row (the owner's answers of 2026-11-16, "Row stays, reason only"). The
        // row's state word sits at the top of the row, beside its title, about 45 pt above the
        // reason at this size; 60 pt covers it and stops short of the row above.
        reach(reason, in: app)
        let band = (reason.frame.minY - 60)...(reason.frame.maxY + 4)
        let retries = app.buttons
            .matching(NSPredicate(format: "label == %@", Copy.retry))
            .allElementsBoundByIndex
        XCTAssertFalse(retries.contains { band.contains($0.frame.midY) },
                       "the refused row draws '\(Copy.retry)'")
        attachScreenshot(app, "withdraw-outbox-refused")
    }

    // MARK: - 5 · The largest text size

    /// At AX5 the control is still reachable, and the alert still draws its title and both buttons
    /// where they can be pressed. The test presses `Keep it`, so it withdraws nothing.
    func testTheControlAndTheAlertAtTheLargestTextSize() {
        let app = launchPinned(
            "withdrawTree", contentSize: "UICTContentSizeCategoryAccessibilityXXXL"
        )

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
        let app = launchPinned("treeProfile")
        let showWhere = app.buttons[Copy.showWhere]
        guard showWhere.waitForExistence(timeout: 60) else {
            XCTFail(deepLinkFailure(app).map { "treeProfile: \($0)" } ?? "treeProfile: the profile never drew")
            return
        }
        // First the presence of the block the control would sit in: a city tree's record controls
        // end with the data-dispute link (RULINGS R79). Only then is the control's absence a fact
        // about the control rather than about a screen that never drew the block.
        let anchor = app.buttons[Copy.cityRecordReport]
        XCTAssertTrue(scrollUntilExists(anchor, in: app),
                      "the city tree's profile drew no '\(Copy.cityRecordReport)', the block's last control")
        reach(anchor, in: app)
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
