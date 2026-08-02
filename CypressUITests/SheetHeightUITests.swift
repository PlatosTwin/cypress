//
//  SheetHeightUITests.swift
//  CypressUITests
//
//  Ticket #146: the owner's device screenshot showed 09 and 10 "half-screened", and on 09 the
//  keyboard covering the note field being typed into. The mechanism is `BottomSheet` — `.standard`
//  sheets are now full-height with their content in a `ScrollView`, and the hosting screens
//  respect the keyboard safe area (`.ignoresSafeArea(.container)`, never the bare form).
//
//  These tests pin both halves of that mechanism from the outside, through the same deep-link
//  door as `DeepLinkVoiceOverTests` (ERRATA E117). Black-box: nothing here imports `Cypress`.
//
//  What is asserted is geometry, not phrasing: where the sheet's title sits on the display, and
//  where the focused field sits relative to the keyboard the system raised over it.
//

import XCTest

final class SheetHeightUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// A full-height sheet puts its title near the top of the display. The old content-sized card
    /// put "Share this tree" in the bottom half — which is the owner's screenshot — so the title's
    /// y-position is the single number that separates the two designs.
    ///
    /// The threshold is a third of the screen: the card's top edge sits at the 62pt status-bar
    /// inset, so the title lands well above it on every device class, while the half-screen layout
    /// put it below 0.5 on all of them. Between lies no legitimate layout.
    func testShareSheetIsFullHeight() {
        assertSheetTitleNearTop(screen: "share", anchor: "Share this tree")
    }

    func testCareLogSheetIsFullHeight() {
        assertSheetTitleNearTop(screen: "careLog", anchor: "Care log")
    }

    /// The keyboard must never cover the field being typed into (09's note field, owner's
    /// screenshot). The route to the field is the care log's own: focus the note field — directly
    /// visible since #168 — then pin where the field sits.
    ///
    /// **Why this asserts the field's position, not the keyboard's frame.** This machine's test
    /// runner cannot raise a software keyboard: with a hardware keyboard attached, `app.keyboards`
    /// exists but sits *below the screen* — measured at y=946 on an 874pt device — so
    /// `field.maxY <= keyboard.minY` is true of every layout including the broken one. That
    /// assertion passed against the pre-#146 build; it was a vacuous test, and it was deleted for
    /// it. What is falsifiable on every machine is the geometric fact that makes coverage
    /// impossible: on the full-height sheet the focused field sits in the top half of the display,
    /// above the top edge of any iOS keyboard (the tallest reach ~55% of the shortest supported
    /// screen). On the half-height layout this measured 0.81 of the screen — red.
    /// The frame comparison remains for machines whose keyboard does come up on screen.
    func testCareLogNoteFieldSitsAboveAnyKeyboardsReach() {
        let app = launch("careLog")
        let anchor = app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Care log"))
            .firstMatch
        XCTAssertTrue(anchor.waitForExistence(timeout: 30), "the care log never arrived")

        // Since #168 there is no reveal step: the note field is directly on the sheet.
        // A vertical-axis TextField can surface as either element type depending on OS version.
        let field = app.textFields.firstMatch.waitForExistence(timeout: 5)
            ? app.textFields.firstMatch
            : app.textViews.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the note field never appeared")
        field.tap()

        let screenHeight = app.frame.height
        XCTAssertGreaterThan(screenHeight, 0, "the app window has no height")
        XCTAssertLessThan(
            field.frame.maxY,
            screenHeight * 0.55,
            "the note field's bottom is at \(field.frame.maxY) of \(screenHeight) — low enough "
                + "for a keyboard to cover it, which is the #146 defect"
        )

        // Where a software keyboard actually rises on screen, hold the direct fact too. Offscreen
        // (y >= screen height) means this runner never presented one; the geometric assertion
        // above already carried the test.
        let keyboard = app.keyboards.firstMatch
        if keyboard.waitForExistence(timeout: 5), keyboard.frame.minY < screenHeight {
            XCTAssertLessThanOrEqual(
                field.frame.maxY,
                keyboard.frame.minY + 1,
                "the keyboard covers the note field: field bottom \(field.frame.maxY) is below "
                    + "the keyboard top \(keyboard.frame.minY)"
            )
        }
        app.terminate()
    }

    // MARK: - Harness

    private func assertSheetTitleNearTop(screen: String, anchor: String) {
        let app = launch(screen)
        let title = app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH %@", anchor))
            .firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 30), "\(screen): '\(anchor)' never appeared")

        let screenHeight = app.frame.height
        XCTAssertGreaterThan(screenHeight, 0, "\(screen): the app window has no height")
        XCTAssertLessThan(
            title.frame.minY,
            screenHeight / 3,
            "\(screen): the sheet title sits at y=\(title.frame.minY) of \(screenHeight) — a "
                + "content-sized bottom card, the half-screen layout #146 removed"
        )
        app.terminate()
    }

    private func launch(_ screen: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CYPRESS_SCREEN"] = screen
        app.launch()
        return app
    }
}
