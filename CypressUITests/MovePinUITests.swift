//
//  MovePinUITests.swift
//  CypressUITests
//
//  The owner's Move pin control (2026-11-12), end to end on the running app.
//
//  1. A tree this installation just added offers `Move pin`. The screen it opens says the pin has
//     not moved, two presses of the north nudge (5 m each) move it 10 m, Save writes it, and the
//     profile it returns to says the position is now placed by hand where it said GPS before: the
//     tree's stored position changed, read back through the profile.
//  2. A city tree from the seed offers no `Move pin`.
//
//  Black-box like the rest of this target: nothing imports `Cypress`, and every literal is a copy
//  constant repeated by hand (`MovePinCopy`, `VisitPinAdjustCopy`, `TreeProfilePresentation`). If a
//  string is renamed this fails, which is correct: the words a reader acts on changed.
//

import XCTest

final class MovePinUITests: XCTestCase, DeepLinkHarness {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private enum Copy {
        static let action = "Move pin"
        static let unmoved = "The pin has not moved."
        static let movedTenNorth = "10 m north of where it was."
        static let rulePrefix = "Drag the map to put the pin on the tree."
        static let nudgeNorth = "Move the pin north"
        static let save = "Save"
        static let showWhere = "Show me where this is"
        static let fromGPS = "position from GPS"
        static let byHand = "position placed by hand"
    }

    // MARK: - 1 · Move a tree you added

    func testMovingThePinOfATreeYouAddedPutsItWhereYouSaved() {
        let app = launch("movePin")

        let action = app.buttons[Copy.action]
        guard action.waitForExistence(timeout: 60) else {
            XCTFail(
                deepLinkFailure(app).map { "movePin: \($0)" }
                    ?? "movePin: the profile of a tree this phone just added drew no '\(Copy.action)'"
            )
            return
        }
        XCTAssertTrue(
            subtitle(containing: Copy.fromGPS, in: app).waitForExistence(timeout: 10),
            "a freshly added tree's profile does not say its position came from GPS"
        )
        assertReachable(action, "the profile's Move pin action")
        action.tap()

        XCTAssertTrue(
            app.staticTexts[Copy.unmoved].waitForExistence(timeout: 15),
            "the Move pin screen did not open on the tree's own spot"
        )
        let rule = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", Copy.rulePrefix)).firstMatch
        XCTAssertTrue(rule.exists, "the Move pin screen does not state its rule")
        let save = app.buttons[Copy.save]
        XCTAssertFalse(save.isEnabled, "Save is offered before the pin has moved")

        let north = app.buttons[Copy.nudgeNorth]
        assertReachable(north, "the north nudge")
        north.tap()
        north.tap()
        XCTAssertTrue(
            app.staticTexts[Copy.movedTenNorth].waitForExistence(timeout: 10),
            "two north nudges did not put the pin 10 m north of where it was"
        )

        assertReachable(save, "the Save button")
        XCTAssertTrue(save.isEnabled, "Save is not offered after the pin moved")
        save.tap()

        // Back on the profile, which re-reads the tree: the stored position is now the one placed
        // by hand. The control is still offered, because the tree is still this reader's.
        XCTAssertTrue(
            subtitle(containing: Copy.byHand, in: app).waitForExistence(timeout: 15),
            "after Save the profile still does not say the position was placed by hand"
        )
        XCTAssertTrue(app.buttons[Copy.action].exists, "the profile lost its Move pin action after a move")

        // Opened again, the screen starts from the saved spot: it has not moved from there.
        app.buttons[Copy.action].tap()
        XCTAssertTrue(
            app.staticTexts[Copy.unmoved].waitForExistence(timeout: 15),
            "the reopened Move pin screen did not start where the pin was saved"
        )
    }

    // MARK: - 2 · Not on a city tree

    func testACityTreeOffersNoMovePin() {
        let app = launch("treeProfile")
        // Arrival first, on a control every profile draws, so the absence below is a fact about a
        // loaded profile and not about a screen that never opened.
        let showWhere = app.buttons[Copy.showWhere]
        guard showWhere.waitForExistence(timeout: 60) else {
            XCTFail(deepLinkFailure(app).map { "treeProfile: \($0)" } ?? "treeProfile: the profile never drew")
            return
        }
        XCTAssertFalse(app.buttons[Copy.action].exists, "a city tree from the seed offers Move pin")
    }

    /// The subtitle is one line of text whose last part is the placement note.
    private func subtitle(containing note: String, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", note)).firstMatch
    }
}
