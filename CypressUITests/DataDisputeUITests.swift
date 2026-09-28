//
//  DataDisputeUITests.swift
//  CypressUITests
//
//  RULINGS R79, part 2 — reporting a mistake in a city record, end to end on the running app.
//
//  ── What these hold ────────────────────────────────────────────────────────────────────────
//  1. The whole trip a tester takes: the action on screen 03, the screen it pushes, a dispute with
//     every choice on and a suggestion under each, the profile it returns to drawing the
//     reporter's own standing dispute, and the take-back putting the action back. The take-back is
//     the half the owner has already reported missing from the community flow, so it is driven,
//     not assumed.
//  2. The 10 m floor refusing **out loud**. `CYPRESS_LOCATION`'s third field states a fix's
//     accuracy (`DebugLocationOverride.parse`), so a coarse fix is pinned rather than faked: the
//     app's one location provider reports 40 m, and the screen has to say both numbers and name
//     Precise Location. A floor that refused silently is the defect the owner ruled against.
//  3. An empty report is refused with its own sentence rather than sent or silently ignored.
//
//  Black-box like the rest of this target: nothing imports `Cypress`, and every literal is a copy
//  constant repeated by hand — `DataDisputeCopy` / `TreeProfileCopy`. If a string is renamed this
//  fails, which is correct: the words a reader acts on changed.
//
//  ── Screenshots ────────────────────────────────────────────────────────────────────────────
//  Each state is written as a PNG for the owner's copy-and-layout ruling. `export
//  TEST_RUNNER_CYPRESS_SHOT_DIR=<dir>` in the shell **before** `Tools/run_tests.sh` chooses the
//  directory (that script's header has the one spelling that works); run once under
//  `xcrun simctl ui <udid> appearance dark` for the dark set — the file names carry the appearance
//  the runner read, so a light and a dark run into one directory do not overwrite each other.
//

import UIKit
import XCTest

final class DataDisputeUITests: XCTestCase, DeepLinkHarness {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: - The words, repeated by hand

    private enum Copy {
        static let action = "Report a mistake in the city’s record"
        static let raised = "You reported a mistake in the city’s record for this tree."
        static let takeBack = "Take back your report"
        static let screenTitle = "Report a mistake"
        static let wrongPlace = "Pin is in the wrong place"
        static let wrongSpecies = "Wrong species"
        static let wrongYear = "Wrong planted year"
        static let noTree = "There’s no tree here"
        static let useLocation = "Use my current location"
        static let captured = "Your location is recorded, good to within 6 m."
        static let chooseSpecies = "Choose the species"
        static let changeSpecies = "Choose a different species"
        static let plantedYear = "Planted year"
        static let send = "Send report"
        static let noIssue = "Choose at least one thing that’s wrong."
        static let openSettings = "Open Settings"
    }

    /// `MapLayout.defaultCenter`, the deep link's own resolution point, spelled out because a UI
    /// test cannot import the app target. The camera stays inside the seed's coverage (E216).
    private static let goodFix = "37.7596,-122.4269,6"
    private static let coarseFix = "37.7596,-122.4269,40"

    // MARK: - 1 · Raise, see it on the profile, take it back

    func testRaisingADisputeShowsItOnTheProfileAndItCanBeTakenBack() {
        let app = launch(fix: Self.goodFix)
        let action = app.buttons[Copy.action]
        guard arriveOnProfile(app, action: action) else { return }
        record(app, named: "01-profile-raisable")

        action.tap()
        guard arriveOnScreen(app) else { return }
        record(app, named: "02-screen-empty")

        for chip in [Copy.wrongPlace, Copy.wrongSpecies, Copy.wrongYear, Copy.noTree] {
            let button = app.buttons[chip]
            assertReachable(button, "the '\(chip)' chip")
            button.tap()
        }

        // The location answer comes from the pinned provider: 6 m is under the floor, so it is
        // attached and the block says so with the number.
        let useLocation = app.buttons[Copy.useLocation]
        assertReachable(useLocation, "the use-my-location control")
        useLocation.tap()
        XCTAssertTrue(
            app.staticTexts[Copy.captured].waitForExistence(timeout: 10),
            "a 6 m fix was not reported as recorded — the location block did not take the provider's fix"
        )

        // The species comes from the app's own picker, not a second one.
        let choose = app.buttons[Copy.chooseSpecies]
        assertReachable(choose, "the choose-the-species control")
        choose.tap()
        let search = app.textFields.firstMatch
        assertReachable(search, "the species picker's search field")
        search.tap()
        search.typeText("Platanus")
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Platanus")).firstMatch
        assertReachable(row, "a Platanus row in the species picker")
        row.tap()
        assertReachable(
            app.buttons[Copy.changeSpecies],
            "the species section after a pick (it should offer to choose a different one)"
        )

        let year = app.textFields[Copy.plantedYear]
        assertReachable(year, "the planted-year field")
        year.tap()
        year.typeText("1998")
        // The number pad has no return key; the keyboard toolbar's Done is the way to put it away,
        // and the screenshot needs the form rather than the pad.
        let done = app.toolbars.buttons["Done"]
        assertReachable(done, "the keyboard's Done control")
        done.tap()
        XCTAssertTrue(
            app.buttons[Copy.send].waitForExistence(timeout: 10),
            "the Send report button is gone after the keyboard was put away"
        )
        record(app, named: "03-screen-filled")

        let send = app.buttons[Copy.send]
        assertReachable(send, "the Send report button")
        send.tap()

        // Back on the profile, which re-read itself: the reporter's own dispute is standing.
        let raised = app.staticTexts[Copy.raised]
        XCTAssertTrue(
            raised.waitForExistence(timeout: 30),
            "after Send report the profile does not say a report was made — either the raise did "
                + "not land, or the profile did not re-read its offer"
        )
        XCTAssertFalse(
            app.buttons[Copy.action].exists,
            "the profile still offers to report a mistake while this reader's own report stands"
        )
        record(app, named: "04-profile-raised")

        let takeBack = app.buttons[Copy.takeBack]
        assertReachable(takeBack, "the take-back control")
        takeBack.tap()
        XCTAssertTrue(
            app.buttons[Copy.action].waitForExistence(timeout: 30),
            "after taking the report back the profile does not offer to report again — the "
                + "withdrawal did not land, or the profile did not re-read its offer"
        )
        XCTAssertFalse(raised.exists, "the profile still says a report was made after it was taken back")
        record(app, named: "05-profile-taken-back")
    }

    // MARK: - 2 · The floor refuses out loud

    func testACoarseFixIsRefusedWithBothNumbersAndPreciseLocation() {
        let app = launch(fix: Self.coarseFix)
        let action = app.buttons[Copy.action]
        guard arriveOnProfile(app, action: action) else { return }
        action.tap()
        guard arriveOnScreen(app) else { return }

        // Nothing chosen: refused with its own sentence, and the screen stays.
        let send = app.buttons[Copy.send]
        assertReachable(send, "the Send report button")
        send.tap()
        XCTAssertTrue(
            app.staticTexts[Copy.noIssue].waitForExistence(timeout: 10),
            "an empty report was not refused with its own sentence"
        )
        XCTAssertTrue(app.staticTexts[Copy.screenTitle].exists, "an empty report left the screen")

        app.buttons[Copy.wrongPlace].tap()
        let useLocation = app.buttons[Copy.useLocation]
        assertReachable(useLocation, "the use-my-location control")
        useLocation.tap()

        let refusal = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", "only good to within 40 m"))
            .firstMatch
        XCTAssertTrue(
            refusal.waitForExistence(timeout: 10),
            "a 40 m fix was not refused out loud with its own accuracy"
        )
        XCTAssertTrue(
            refusal.label.contains("within 10 m"),
            "the refusal does not quote the floor it refused against: '\(refusal.label)'"
        )
        XCTAssertTrue(
            refusal.label.contains("Precise Location"),
            "the refusal does not name Precise Location: '\(refusal.label)'"
        )
        assertReachable(app.buttons[Copy.openSettings], "the Open Settings control under the refusal")
        assertEveryControlIsLabeled(app, screen: "dataDispute (coarse fix)")
        record(app, named: "06-screen-coarse-fix")
    }

    // MARK: - Harness

    private func launch(fix: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment[Self.deepLinkScreenKey] = "dataDispute"
        app.launchEnvironment["CYPRESS_LOCATION"] = fix
        DebugMapCamera.pin(app)
        app.launch()
        return app
    }

    private func arriveOnProfile(_ app: XCUIApplication, action: XCUIElement) -> Bool {
        guard action.waitForExistence(timeout: 60) else {
            XCTFail(
                deepLinkFailure(app).map { "dataDispute: \($0)" }
                    ?? "dataDispute: the profile never drew '\(Copy.action)' — the city tree is not "
                        + "offered as raisable, or the deep link opened something else"
            )
            return false
        }
        assertReachable(action, "the profile's report-a-mistake action")
        return true
    }

    private func arriveOnScreen(_ app: XCUIApplication) -> Bool {
        guard arrive(app, screen: "dataDispute", anchor: Copy.screenTitle) else { return false }
        assertEveryControlIsLabeled(app, screen: "dataDispute")
        assertReachable(app.buttons["Back"], "dataDispute: the Back control")
        return true
    }

    /// A PNG per state, plus the same image on the result bundle — `AreaPickerUITests.record`.
    private func record(_ app: XCUIApplication, named name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let appearance = UITraitCollection.current.userInterfaceStyle == .dark ? "dark" : "light"
        let directory = ProcessInfo.processInfo.environment["CYPRESS_SHOT_DIR"] ?? NSTemporaryDirectory()
        let url = URL(fileURLWithPath: directory).appendingPathComponent("dispute-\(appearance)-\(name).png")
        try? shot.pngRepresentation.write(to: url)
        print("CYPRESS-SHOT: \(url.path)")
    }
}
