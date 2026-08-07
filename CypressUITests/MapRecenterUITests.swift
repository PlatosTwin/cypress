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

    /// AX5 with location denied — screen 01's longest standing notice
    /// (`MapLocationCopy.message`), the state task #250 measured the occlusion in.
    private func launchAtAX5(location: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment[Self.locationKey] = location
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()
        return app
    }

    /// The one string this file and the app have to agree on: `MapRecenterCopy.label`.
    private static let controlLabel = "Center the map on you"

    /// `MapFilterCopy.rowLabel` — the chip row's own named accessibility group.
    private static let chipRowLabel = "Filter trees"

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
        assertReachable(control, "screen 01's control labeled “\(Self.controlLabel)”")
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

    /// **Task #250.** Correcting `MapLayout.locateButtonHeightAX5` and `.fabHeightAX5`
    /// to their bare AX5 footprints (task #246) gave `MapLocationNotice` back the ~108 pt of scroll
    /// budget those inflated constants had been silently eating — the ticket's actual goal — and, as
    /// a measured side effect, let the notice grow tall enough at AX5 to push `bottomChrome`'s
    /// bottom-anchored `VStack` (recenter, then FAB, then notice) up far enough that the recenter
    /// control, first in the stack, rose behind the top-anchored filter chip row: present in the
    /// tree, `isHittable == false`.
    ///
    /// This is the state that showed it: the longest of the four `MapOpening.Standing` sentences
    /// (`MapLocationCopy.message`, location denied) forces the notice as close to its AX5 budget as
    /// any shipped copy gets. `MapLayout`'s reservation now also accounts for the room the top chrome
    /// (search bar + chip row) needs, so the recenter control's frame must clear the chip row's own
    /// frame — not merely happen to still be hittable, which a coincidence of this run's exact
    /// numbers could satisfy without the geometry actually being disjoint.
    func testTheRecenterControlClearsTheFilterChipRowAtAX5WithLocationDenied() {
        let app = launchAtAX5(location: "denied")

        // The row's named container rides on the `ScrollView` since the row became one (#166), and
        // which element type XCUITest files a labeled SwiftUI scroller under is not a contract worth
        // pinning (`MapFilterAccessibilityTests.rowContainer`) — both spellings are accepted.
        let other = app.otherElements[Self.chipRowLabel]
        let chipRow = other.exists ? other : app.scrollViews[Self.chipRowLabel]
        let chipRowFrame = settledFrame(chipRow, "the filter chip row (“\(Self.chipRowLabel)”)")

        let control = recenterControl(app)
        assertReachable(
            control,
            "screen 01's control labeled “\(Self.controlLabel)”, at AX5 with location denied"
        )
        let controlFrame = settledFrame(control, "the recenter control")

        XCTAssertFalse(
            controlFrame.intersects(chipRowFrame),
            "the recenter control \(controlFrame) overlaps the filter chip row \(chipRowFrame) — "
                + "the chrome the chips own now reaches down into the control's own space, which is "
                + "how it ends up present in the tree and not hittable"
        )
    }
}
