import XCTest

/// **The control, pressed.**
///
/// `CypressTests/MapRecentreTests` proves the *decision* is right — that every availability produces
/// something visible, and that the zoom rule steps the way it is written. It cannot prove the button
/// is wired to any of it, which is precisely the failure C20 had before ERRATA E134: a control drawn
/// on screen 01 whose binding nothing read, with a green suite either side of it.
///
/// So this launches the app, finds the control by the label a VoiceOver user would find it by, and
/// presses it. Black-box like the rest of `CypressUITests`: it imports nothing from `Cypress`.
///
/// The refusal test needs the permission actually revoked, which a UI test cannot do to itself:
///
///     xcrun simctl privacy <udid> revoke location app.cypress.Cypress
///
/// Without that it **skips** rather than fails, for `MapSearchUITests`' reason — a skip says "not
/// checked here", which is true, where a failure would say "broken", which is not.
final class MapRecenterUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        return app
    }

    /// The one string this file and the app have to agree on: `MapRecentreCopy.label`.
    private static let controlLabel = "Center the map on you"

    private func recenterControl(_ app: XCUIApplication) -> XCUIElement {
        app.buttons[Self.controlLabel]
    }

    private func text(containing fragment: String, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] %@", fragment)
        ).firstMatch
    }

    /// The control exists, is labelled, is reachable, and says what state it is in.
    ///
    /// `AccessibilityTreeTests.testNoUnlabelledButtonsOnLaunch` would catch a control with no label
    /// at all. It would not catch one that is drawn but not in the tree — an overlay behind the map,
    /// say, or one clipped out of its parent's bounds, both of which are live risks on a screen whose
    /// chrome is absolutely positioned over a full-bleed `Map` (ERRATA E110).
    func testTheRecenterControlIsInTheTreeAndSaysWhatItIsDoing() {
        let app = launch()
        let control = recenterControl(app)
        XCTAssertTrue(
            control.waitForExistence(timeout: 15),
            "screen 01 has no control labelled “\(Self.controlLabel)”"
        )
        XCTAssertTrue(control.isHittable, "the recentre control is present but cannot be activated")
        XCTAssertFalse(
            control.value as? String ?? "" == "",
            "the control has no accessibility value, so a VoiceOver reader cannot tell whether the "
                + "map is already centred"
        )
    }

    /// **The press that cannot move the camera must still answer.**
    ///
    /// This is the defect class the control was built against: with location denied, MapKit's own
    /// `MapUserLocationButton` is simply inert, and so was every hand-rolled version of this button
    /// that forgot the state. Pressing must put a sentence on screen naming the limit and pointing at
    /// Settings.
    func testPressingItWithLocationDeniedExplainsRatherThanDoingNothing() throws {
        let app = launch()
        let control = recenterControl(app)
        XCTAssertTrue(control.waitForExistence(timeout: 15))

        // The standing notice is how a black-box test can tell the permission was refused: screen 01
        // draws it, unprompted, in exactly that state.
        let standing = text(containing: "The map still works", in: app)
        guard standing.waitForExistence(timeout: 10) else {
            throw XCTSkip(
                "location is not denied for this app on this simulator, so there is no refusal to "
                    + "check: xcrun simctl privacy <udid> revoke location app.cypress.Cypress"
            )
        }

        control.tap()

        // `MapRecentreCopy.refusalMessage`. The fragment is the clause that makes it an answer to
        // *this* press rather than the standing notice repeated.
        let answer = text(containing: "nowhere to center the map", in: app)
        XCTAssertTrue(
            answer.waitForExistence(timeout: 5),
            "pressing the recentre control with location denied changed nothing on screen"
        )
        XCTAssertTrue(
            app.buttons["Settings"].exists,
            "the refusal names Settings as the way out and offers no way to get there"
        )
    }
}
