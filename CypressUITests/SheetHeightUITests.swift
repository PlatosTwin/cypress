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
    /// screenshot). The route to the field is the care log's own: open the optional well, focus
    /// the note field, let the system raise the keyboard, then compare frames.
    ///
    /// If no keyboard element ever appears this fails rather than skipping: a simulator with a
    /// hardware keyboard attached cannot exhibit the defect, and a green that never saw a keyboard
    /// would be this project's signature false green.
    func testCareLogNoteFieldStaysAboveTheKeyboard() {
        let app = launch("careLog")
        let anchor = app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Care log"))
            .firstMatch
        XCTAssertTrue(anchor.waitForExistence(timeout: 30), "the care log never arrived")

        let well = app.buttons["Photo or note (optional)"].firstMatch
        XCTAssertTrue(well.waitForExistence(timeout: 5), "the optional well is not in the tree")
        well.tap()

        // A vertical-axis TextField can surface as either element type depending on OS version.
        let field = app.textFields.firstMatch.waitForExistence(timeout: 5)
            ? app.textFields.firstMatch
            : app.textViews.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the note field never appeared")
        field.tap()

        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(
            keyboard.waitForExistence(timeout: 10),
            "no software keyboard rose — this test proved nothing; detach the hardware keyboard"
        )
        // Give the scroll-into-view animation its beat before freezing frames.
        _ = field.waitForExistence(timeout: 2)

        XCTAssertLessThanOrEqual(
            field.frame.maxY,
            keyboard.frame.minY + 1,
            "the keyboard covers the note field: field bottom \(field.frame.maxY) is below the "
                + "keyboard top \(keyboard.frame.minY) — the #146 defect, back"
        )
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
