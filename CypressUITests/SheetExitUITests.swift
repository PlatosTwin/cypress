//
//  SheetExitUITests.swift
//  CypressUITests
//
//  Ticket #175: the owner could not leave 09 or 10 — "clicking outside of them does nothing,
//  and while you think you'd be able to drag the top of the page down … the page is stuck".
//
//  Diagnosis (iPhone 16 Pro simulator, taps injected at coordinates): the scrim tap was wired
//  and working, but a full-height card leaves only the 62pt status-bar strip of scrim exposed,
//  and the system's own status-bar hit region consumes roughly the top 54pt of it — taps at
//  y=30 and y=45 never reached the app; taps at y=58 dismissed. The one wired exit was an ~8pt
//  invisible sliver, and there was no drag despite the grabber promising one.
//
//  These tests pin both exits from the outside, through the same deep-link door as
//  `SheetHeightUITests` (ERRATA E117). Black-box: nothing here imports `Cypress`.
//
//  **Dismissal is asserted as presence, not absence**: the sheets are presented over the map
//  tab, so the map's search field arriving is the fact that the cover left. A vanished title
//  proves only that a query stopped matching.
//

import XCTest

final class SheetExitUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: - Drag down dismisses (the grabber's promise)

    /// A drag that starts in the handle band — the grabber row at the top of the card, below
    /// the 62pt scrim strip — and travels most of the display must dismiss the care log.
    func testCareLogDragDownDismisses() {
        let app = launch("careLog")
        let title = waitForTitle(app, "Care log")
        dragDown(app, fromY: title.frame.minY - 12)
        assertMapArrived(app, after: "dragging the care log down")
        app.terminate()
    }

    func testShareSheetDragDownDismisses() {
        let app = launch("share")
        let title = waitForTitle(app, "Share this tree")
        dragDown(app, fromY: title.frame.minY - 12)
        assertMapArrived(app, after: "dragging the share sheet down")
        app.terminate()
    }

    // MARK: - The scrim strip

    /// The strip of scrim between the system status bar's hit region and the card's top edge
    /// must genuinely dismiss. y=58 is inside the app-drawn 62pt strip and below the system's
    /// gate (measured ~54pt on the Dynamic Island simulators this suite runs on); taps higher
    /// than that are consumed by the OS and can never reach any app, which is the finding this
    /// test exists to hold in place from the app's side.
    func testCareLogScrimStripTapDismisses() {
        let app = launch("careLog")
        _ = waitForTitle(app, "Care log")
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: app.frame.midX, dy: 58))
            .tap()
        assertMapArrived(app, after: "tapping the scrim strip")
        app.terminate()
    }

    // MARK: - The note field is not a handle

    /// A drag that starts on 09's note field must not dismiss the sheet: below the handle band
    /// the card belongs to its `ScrollView` — scrolling, and the keyboard mechanism that rides
    /// on it (#146) — so the sheet must still be standing afterwards, note intact.
    ///
    /// The field is focused first (this is the "keyboard up" state; on runners with a hardware
    /// keyboard attached no software keyboard rises — `SheetHeightUITests` records why — but
    /// focus, and the field's claim on gestures, are the same either way).
    func testCareLogNoteFieldDragDoesNotDismiss() {
        let app = launch("careLog")
        _ = waitForTitle(app, "Care log")

        let field = app.textFields.firstMatch.waitForExistence(timeout: 5)
            ? app.textFields.firstMatch
            : app.textViews.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the note field never appeared")
        field.tap()
        field.typeText("Mulch ring rebuilt")

        dragDown(app, fromY: field.frame.midY)

        // The sheet is still standing and the note survived the drag.
        let title = app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Care log"))
            .firstMatch
        XCTAssertTrue(
            title.waitForExistence(timeout: 5),
            "a drag on the note field dismissed the care log — the handle band leaked into the content"
        )
        XCTAssertTrue(
            app.staticTexts["Mulch ring rebuilt"].exists || (field.value as? String) == "Mulch ring rebuilt",
            "the note did not survive the drag on the field"
        )
        app.terminate()
    }

    // MARK: - Harness

    private func launch(_ screen: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CYPRESS_SCREEN"] = screen
        app.launch()
        return app
    }

    private func waitForTitle(_ app: XCUIApplication, _ anchor: String) -> XCUIElement {
        let title = app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH %@", anchor))
            .firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 30), "'\(anchor)' never appeared")
        return title
    }

    /// A downward drag at the display's horizontal center, from `fromY` to 85% of the screen —
    /// far past the quarter-height commit line on every device class.
    private func dragDown(_ app: XCUIApplication, fromY: CGFloat) {
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: app.frame.midX, dy: fromY))
        let end = origin.withOffset(CGVector(dx: app.frame.midX, dy: app.frame.height * 0.85))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    /// The sheets are deep-linked over the map tab, so the map's own chrome becoming *hittable*
    /// is what a real dismissal looks like from out here. Hittable, not merely existing — the
    /// cover leaves the presenting screen in the element tree beneath it, so `exists` on the
    /// "What tree is this?" FAB is true while the sheet is still standing (this assertion was
    /// born vacuous and caught by its own red-proof: with the drag gesture deleted, an
    /// existence check still passed). And the FAB rather than a text field: 09 carries a text
    /// field of its own, so a field query would be satisfied by the very sheet that failed to
    /// leave.
    private func assertMapArrived(_ app: XCUIApplication, after action: String) {
        let fab = app.buttons["What tree is this?"]
        let uncovered = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND hittable == true"),
            object: fab
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [uncovered], timeout: 10), .completed,
            "after \(action), the map underneath never became reachable — the sheet did not dismiss"
        )
    }
}
