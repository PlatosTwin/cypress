//
//  AddReadingReachabilityTests.swift
//  Cypress — UI tests
//
//  **Tester report F28, as an assertion about a finger rather than about a presentation.**
//
//  R15 gave each measurement its own door into screen 16, and said plainly what that left behind:
//  the empty stat card "exists only while its own measurement is missing", so a tree carrying both a
//  height and a DBH has no card door at all. The way through was `See every reading` and then screen
//  11's own `Add a reading` — two small-text taps, which is what the tester reported. The profile
//  now draws a door of its own in exactly that state.
//
//  ── Why this is not left to `MeasureEntranceKindTests` ───────────────────────────────────
//  That suite asserts `offersAddReadingLink` over the whole state space, which is the right unit
//  test and is not this one. `PhotoDeletionReachabilityTests` is the record of why: #78 built a
//  delete, proved it in unit tests that all passed, and shipped it where the owner's finger did not
//  go. A presentation flag that is `true` proves a property of a struct. It does not prove that a
//  control was drawn, that it was reachable, or that pressing it went anywhere — and F28 is a report
//  about exactly those three things.
//
//  So this file, like that one, does not stop at `exists`: the control is checked for hittability
//  (this project has shipped a control `isHittable` reported `true` for and no finger could press),
//  and then it is *used*, and screen 16 has to be what comes up.
//
//  ── Why `fullyMeasured` ──────────────────────────────────────────────────────────────────
//  No tree in the shipped seed carries a reading — the seed has no `measurements` rows and screen 16
//  is the only thing that writes one — so the state F28 is about cannot be reached by picking a
//  record. `DebugDeepLink.fullyMeasured` writes a DBH and a height through fixed client uuids, onto
//  a tree five eighths of the way out that no other case touches. That slot is E133's rule being
//  kept: `.measure`'s tree already accumulates a DBH from `testSavingAMeasurementLeavesTheScreen`,
//  and adding a height to it would flip the profile nine other cases read.
//

import XCTest

final class AddReadingReachabilityTests: XCTestCase {

    /// **The report, as an assertion.** A tree with nothing left to measure still has to offer a way
    /// to measure it, on the screen the reader is already looking at.
    func testAFullyMeasuredTreeReachesTheMeasureSheetInOneTap() {
        let app = launch()
        guard arrive(app) else { return }

        // The premise first, and it is the half a green test would otherwise assume: this tree is
        // fully measured, so neither stat card is a door. A card holding a reading goes to screen 11
        // (R15), and if one of these were still an empty `Add a reading` slot the tap below would
        // prove nothing about F28 — it would be R15's door working, on a tree the harness failed to
        // measure.
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "DBH, ")).firstMatch
                .waitForExistence(timeout: 10),
            "the harness did not leave a DBH reading on this tree, so it is not the fully measured "
                + "tree F28 is about and nothing below would be testing the report"
        )
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Height, ")).firstMatch
                .exists,
            "the harness did not leave a height reading on this tree, so it is not fully measured"
        )
        XCTAssertTrue(
            Self.emptySlotCards(app).isEmpty,
            "a stat card is still drawing the empty-slot invitation, so this tree has a card door "
                + "and is not in the state F28 reported"
        )

        let addReading = app.buttons[Self.addReadingLink]
        XCTAssertTrue(
            addReading.waitForExistence(timeout: 5),
            "a tree carrying every measurement offered no way into screen 16 from its own profile — "
                + "which is the whole of tester report F28"
        )
        XCTAssertTrue(
            addReading.isHittable,
            "the link is in the profile's tree but nothing could press it"
        )

        // Presence is not the claim. Pressing it, and arriving, is.
        addReading.tap()
        XCTAssertTrue(
            app.staticTexts[Self.measureTitle].waitForExistence(timeout: 10),
            "the link was pressed and screen 16 did not open, so the one tap is not a way in"
        )
        // And it opens on a measurement, with the keypad under it — a door onto a form that cannot
        // be filled in would satisfy every assertion above.
        XCTAssertTrue(
            app.buttons[Self.keypadDigit].waitForExistence(timeout: 5),
            "screen 16 opened without its keypad, so nothing could be entered on arrival"
        )
    }

    /// The other half of the ruling, and the reason it is here rather than only in the unit suite:
    /// a half-measured tree must **not** grow a second invitation. Two controls a card apart, both
    /// reading `Add a reading`, would be F28 answered by making the screen worse.
    ///
    /// `treeProfile` is the ordinary standing tree — no readings on it, so both stat cards are empty
    /// slots and the empty-slot door is the one that should be doing the work.
    func testAnUnmeasuredTreeKeepsItsCardDoorAndGrowsNoLink() {
        let app = launch(screen: "treeProfile")
        // A stat card combines its children, so the empty slot is a button labeled
        // `Height, Add a reading` — not a bare `Add a reading`. That difference is what makes the
        // assertion below able to tell a card apart from the link.
        guard app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Height, "))
            .firstMatch.waitForExistence(timeout: 60)
        else {
            XCTFail(failureBanner(app) ?? "the standing tree drew no Height stat card, so this "
                + "test could not have failed for its own reason")
            return
        }
        XCTAssertFalse(
            Self.emptySlotCards(app).isEmpty,
            "the standing tree drew no empty measurement slot, so it is not the half-measured "
                + "state this test is about"
        )

        XCTAssertFalse(
            app.buttons[Self.addReadingLink].exists,
            "a tree with empty measurement slots grew F28's link as well, so the profile now "
                + "invites the same contribution twice"
        )
    }

    /// The stat cards that are drawing the empty-slot invitation. Matched on the card's *combined*
    /// label containing the phrase, which is how an `Add a reading` card is told from the standalone
    /// link whose whole label is those three words.
    private static func emptySlotCards(_ app: XCUIApplication) -> [XCUIElement] {
        app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@ AND label != %@", emptySlotValue, addReadingLink))
            .allElementsBoundByIndex
    }

    // MARK: - Harness

    /// `TreeProfilePresentation` and `MeasureCopy` own these strings; they are spelled out rather
    /// than imported because a UI test drives the app from outside, and a label that changed without
    /// anybody noticing should fail here rather than follow the change silently.
    private static let addReadingLink = "Add a reading"
    private static let emptySlotValue = "Add a reading"
    private static let measureTitle = "Measure"
    private static let keypadDigit = "3"

    private func launch(screen: String = "fullyMeasured") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CYPRESS_SCREEN"] = screen
        app.launch()
        return app
    }

    /// `DebugDeepLink` draws its failures rather than logging them, so a harness failure can be
    /// reported as one: "no standing tree five eighths out" is an answer, and "the link is missing"
    /// would be a lie about the app.
    private func failureBanner(_ app: XCUIApplication) -> String? {
        let banner = app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH %@", "DEEP LINK FAILED"))
            .firstMatch
        return banner.exists ? banner.label : nil
    }

    /// Arrives on screen 03 over the fully measured tree. Generous, because a cold launch opens the
    /// database, runs migrations and attaches the seed before it can write two readings.
    private func arrive(_ app: XCUIApplication) -> Bool {
        guard app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "DBH, ")).firstMatch
            .waitForExistence(timeout: 60)
        else {
            XCTFail(failureBanner(app) ?? "screen 03 never drew a DBH stat card, so there was "
                + "nothing to measure and this test could not have failed for its own reason")
            return false
        }
        return true
    }
}
