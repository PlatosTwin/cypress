import XCTest

/// **The control, pressed.**
///
/// `CypressTests/MapRecenterTests` proves the *decision* is right — that every availability produces
/// something visible, and that the zoom rule steps the way it is written. It cannot prove the button
/// is wired to any of it, which is precisely the failure C20 had before ERRATA E134: a control drawn
/// on screen 01 whose binding nothing read, with a green suite either side of it.
///
/// So this launches the app, finds the control by the label a VoiceOver user would find it by, and
/// presses it. Black-box like the rest of `CypressUITests`: it imports nothing from `Cypress`.
///
/// ── The refusal test used to skip, and does not any more (task #121) ─────────────────────────
/// It needed the permission actually revoked, which a UI test cannot do to itself:
///
///     xcrun simctl privacy <udid> revoke location app.cypress.Cypress
///
/// Without that it threw `XCTSkip`, for `MapSearchUITests`' reason — a skip says "not checked here",
/// which is true, where a failure would say "broken", which is not. That reasoning was correct and
/// it was not the problem. The problem is that a skipped test is invisible in the line this project
/// judges a run by: `Test run with N tests passed` counts a test that declined to run exactly the
/// same as one that ran and passed. Since no simulator anybody hands this suite has location denied,
/// the refusal path — the sentence naming the limit, and the Settings button — went unexercised in
/// every ordinary run, under a green number.
///
/// `CYPRESS_LOCATION=denied` in the launch environment now *drives* the state instead of detecting
/// it (`DebugLocationOverride`, ruling `RULINGS R58`), so the
/// test is unconditional. What it proves is narrower than what the skip pretended to be waiting for,
/// and the ruling says so: this is the app's behavior in the denied state, not CoreLocation's
/// behavior in producing that state.
final class MapRecenterUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// The environment key that pins the app's idea of where the phone is. `DebugLocationOverride
    /// .environmentKey`, repeated as a literal because this target imports nothing from `Cypress` —
    /// the same bargain every other anchor in this suite makes.
    private static let locationKey = "CYPRESS_LOCATION"

    private func launch(location: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        if let location { app.launchEnvironment[Self.locationKey] = location }
        app.launch()
        return app
    }

    /// The one string this file and the app have to agree on: `MapRecenterCopy.label`.
    private static let controlLabel = "Center the map on you"

    private func recenterControl(_ app: XCUIApplication) -> XCUIElement {
        app.buttons[Self.controlLabel]
    }

    private func text(containing fragment: String, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] %@", fragment)
        ).firstMatch
    }

    /// The control exists, is labeled, is reachable, and says what state it is in.
    ///
    /// `AccessibilityTreeTests.testNoUnlabeledButtonsOnLaunch` would catch a control with no label
    /// at all. It would not catch one that is drawn but not in the tree — an overlay behind the map,
    /// say, or one clipped out of its parent's bounds, both of which are live risks on a screen whose
    /// chrome is absolutely positioned over a full-bleed `Map` (ERRATA E110).
    func testTheRecenterControlIsInTheTreeAndSaysWhatItIsDoing() {
        let app = launch()
        let control = recenterControl(app)
        XCTAssertTrue(
            control.waitForExistence(timeout: 15),
            "screen 01 has no control labeled “\(Self.controlLabel)”"
        )
        XCTAssertTrue(control.isHittable, "the recenter control is present but cannot be activated")
        XCTAssertFalse(
            control.value as? String ?? "" == "",
            "the control has no accessibility value, so a VoiceOver reader cannot tell whether the "
                + "map is already centered"
        )
    }

    /// **The press that cannot move the camera must still answer.**
    ///
    /// This is the defect class the control was built against: with location denied, MapKit's own
    /// `MapUserLocationButton` is simply inert, and so was every hand-rolled version of this button
    /// that forgot the state. Pressing must put a sentence on screen naming the limit and pointing at
    /// Settings.
    ///
    /// **Unconditional since task #121.** The state is driven, not detected — see the type comment.
    func testPressingItWithLocationDeniedExplainsRatherThanDoingNothing() {
        let app = launch(location: "denied")
        let control = recenterControl(app)
        XCTAssertTrue(control.waitForExistence(timeout: 15))

        // The standing notice is how a black-box test can tell the app believes the permission was
        // refused: screen 01 draws it, unprompted, in exactly that state. It used to be the guard
        // this test skipped on; it is now the first assertion, because the launch environment put
        // the app in that state and a screen 01 that did not draw it is a defect.
        let standing = text(containing: "The map still works", in: app)
        XCTAssertTrue(
            standing.waitForExistence(timeout: 15),
            "launched with location denied and screen 01 drew no standing notice about it, so "
                + "either the notice is gone or CYPRESS_LOCATION did not reach MapLocationProvider"
        )

        control.tap()

        // `MapRecenterCopy.refusalMessage`. The fragment is the clause that makes it an answer to
        // *this* press rather than the standing notice repeated.
        let answer = text(containing: "nowhere to center the map", in: app)
        XCTAssertTrue(
            answer.waitForExistence(timeout: 5),
            "pressing the recenter control with location denied changed nothing on screen"
        )
        XCTAssertTrue(
            app.buttons["Settings"].exists,
            "the refusal names Settings as the way out and offers no way to get there"
        )
    }
}
