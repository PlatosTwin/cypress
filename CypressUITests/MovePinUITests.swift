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
        static let movedFiveNorth = "5 m north of where it was."
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
        // One nudge at a time: a second tap sent while the first is still redrawing the screen was
        // lost once on a loaded CI runner (run 43536693607, ui shard 2).
        north.tap()
        XCTAssertTrue(
            app.staticTexts[Copy.movedFiveNorth].waitForExistence(timeout: 10),
            "one north nudge did not put the pin 5 m north of where it was"
        )
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

    // MARK: - 2 · Where the link sits on the profile

    /// The owner's TestFlight note on build 87 (2026-11-13): "Terrible spacing here", on a profile
    /// where `Move pin` floated about 62 pt from the links above and below it, center to center,
    /// while the other links in the column sat against each other.
    ///
    /// Two bounds, both on the distance between label centers. **At least 44 pt**, because each link
    /// has a 44 pt hit rect centered on its words, and closer than that one link takes taps meant
    /// for the other (`AddReadingReachabilityTests`). **At most 52 pt** (44 plus the 8 pt row gap),
    /// because anything more is the empty band the owner reported. Build 87's 62 pt fails the
    /// second bound by 10 pt; the fix draws about 46.5 pt.
    func testMovePinSitsOneTapTargetFromTheLinksBesideIt() {
        let app = launch("movePin")

        let action = app.buttons[Copy.action]
        guard action.waitForExistence(timeout: 60) else {
            XCTFail(
                deepLinkFailure(app).map { "movePin: \($0)" }
                    ?? "movePin: the profile of a tree this phone just added drew no '\(Copy.action)'"
            )
            return
        }
        let showWhere = app.buttons[Copy.showWhere]
        XCTAssertTrue(showWhere.waitForExistence(timeout: 10), "the profile drew no '\(Copy.showWhere)' above Move pin")

        let move = action.frame
        let above = showWhere.frame
        XCTAssertGreaterThan(move.height, 0, "Move pin has no frame to measure")
        XCTAssertLessThan(above.maxY, move.minY, "'\(Copy.showWhere)' is not above Move pin")
        assertPitch(from: above, to: move, "'\(Copy.showWhere)' to Move pin")

        // The next control down the same column, whichever the profile offers this tree: the
        // nearest button below Move pin whose left edge lines up with it.
        let below = app.buttons.allElementsBoundByIndex
            .map(\.frame)
            .filter { $0.minY > move.maxY && abs($0.minX - move.minX) < 1 && $0.height > 0 }
            .min { $0.minY < $1.minY }
        guard let below else {
            XCTFail("no link sits under Move pin in its column, so the gap below it was not measured")
            return
        }
        assertPitch(from: move, to: below, "Move pin to the link under it")
    }

    private func assertPitch(
        from upper: CGRect, to lower: CGRect, _ what: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let tapTarget: CGFloat = 44
        let rowGap: CGFloat = 8
        let pitch = lower.midY - upper.midY
        XCTAssertGreaterThanOrEqual(
            pitch, tapTarget,
            "\(what): the label centers are \(pitch) pt apart, so their 44 pt hit rects overlap",
            file: file, line: line
        )
        XCTAssertLessThanOrEqual(
            pitch, tapTarget + rowGap,
            "\(what): the label centers are \(pitch) pt apart, which leaves an empty band around "
                + "Move pin (build 87's spacing)",
            file: file, line: line
        )
    }

    // MARK: - 3 · Not on a city tree

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
