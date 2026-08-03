import XCTest

/// **A deliberate pan survives Map → Journal → Map** (task #128).
///
/// The mechanism the ticket suspected is real and was verified in code: `RootView` builds each tab
/// root on a `switch`, so a tab switch destroys `MapHomeView` and every `@State` on it —
/// `hasCenteredOnUser` included — and the remade screen re-ran the one-shot fly-to-you over the
/// camera the reader had just panned somewhere else. E168's `Coordinator.echo` fix is about camera
/// writes landing; it never covered a one-shot that re-arms.
///
/// Both directions are tested, because the fix has a forbidden overcorrection on each side:
///
///   · a camera the reader deliberately moved is **theirs** — re-centering it is this ticket's bug;
///   · a camera they never touched **may still center on them** — never centering again is closed
///     ticket #85's fix overshooting into #115's regression.
///
/// ── How the camera is witnessed, black-box ───────────────────────────────────────────────────
/// The recenter control's `accessibilityValue` is the one sentence the app publishes about where
/// the camera is (`MapRecenterCopy.value`): `Centered on you` / `Not centered`. Reading it is
/// `MapCenteredStateUITests`' own technique, skips and all: with no fix there is nothing to be
/// centered on, and both tests here skip with that file's honesty rather than fail.
///
///     xcrun simctl privacy <udid> grant location app.cypress.Cypress
///     xcrun simctl location <udid> set 37.7599,-122.4148
final class MapPanTabSwitchUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private static let controlLabel = "Center the map on you"
    private static let centered = "Centered on you"
    private static let notCentered = "Not centered"

    /// `MapRecenterCopy.value`'s three fixless states, copied exactly (see
    /// `MapCenteredStateUITests` for the day this list was one word wrong).
    private static let fixless = [
        "Location is off",
        "Finding you",
        "Cypress has not been given your location",
    ]

    private func value(_ control: XCUIElement) -> String { control.value as? String ?? "" }

    /// Launches, and waits for the opening camera to settle on the reader. Skips when this
    /// simulator has no fix to settle on.
    private func launchCentered() throws -> (XCUIApplication, XCUIElement) {
        let app = XCUIApplication()
        app.launch()
        let control = app.buttons[Self.controlLabel]
        XCTAssertTrue(
            control.waitForExistence(timeout: 15),
            "screen 01 has no control labeled “\(Self.controlLabel)”"
        )
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline, value(control) != Self.centered {
            usleep(250_000)
        }
        let seen = value(control)
        if Self.fixless.contains(seen) {
            throw XCTSkip(
                "this simulator never gave Cypress a fix (the control reads “\(seen)”), so a pan "
                    + "and a re-center are both undefined here: xcrun simctl privacy <udid> grant "
                    + "location app.cypress.Cypress && xcrun simctl location <udid> set "
                    + "37.7599,-122.4148"
            )
        }
        XCTAssertEqual(
            seen, Self.centered,
            "the map never settled on the reader, so this test cannot tell a preserved pan from "
                + "a launch that failed #115 — see MapCenteredStateUITests"
        )
        return (app, control)
    }

    /// Drags the middle of the map. Mid-screen, nowhere near an edge (edge swipes are OS
    /// gestures), and short enough to stay a pan.
    private func pan(_ app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.6))
        start.press(forDuration: 0.1, thenDragTo: end)
    }

    private func switchTabs(_ app: XCUIApplication, away: String = "Journal", home: String = "Map") {
        let awayTab = app.buttons[away]
        XCTAssertTrue(awayTab.waitForExistence(timeout: 10), "no \(away) tab")
        awayTab.tap()
        // The other screen has to actually arrive, or the Map tap below is a no-op on a screen
        // that never left.
        XCTAssertTrue(
            app.buttons[home].waitForExistence(timeout: 10),
            "the tab bar vanished on \(away)"
        )
        _ = wait(timeout: 2) { !app.buttons[Self.controlLabel].exists }
        app.buttons[home].tap()
        XCTAssertTrue(
            app.buttons[Self.controlLabel].waitForExistence(timeout: 15),
            "returning to Map drew no recenter control"
        )
    }

    @discardableResult
    private func wait(timeout: TimeInterval, for condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            usleep(200_000)
        }
        return condition()
    }

    /// Direction one — the defect. Pan, leave, come back: the camera stays where the reader put
    /// it, which the control reports as still not centered. Before the fix the remade screen's
    /// one-shot flew the camera back to the fix within a second or two of reappearing, so the
    /// assertion holds the window open long enough for that regression to hang itself.
    func testADeliberatePanSurvivesLeavingForJournalAndBack() throws {
        let (app, control) = try launchCentered()

        pan(app)
        XCTAssertTrue(
            wait(timeout: 10) { self.value(control) == Self.notCentered },
            "panning the map did not move the camera off the reader (the control reads "
                + "“\(value(control))”), so there is no deliberate camera to preserve"
        )

        switchTabs(app)
        let control2 = app.buttons[Self.controlLabel]

        // Not a race: the pre-fix failure mode is the camera coming back to the fix shortly after
        // the screen remounts, so the claim is "it never re-centers", watched for long enough that
        // the one-shot (which fires on appearance or on the first availability change) has no
        // window left.
        let recentered = wait(timeout: 8) { self.value(control2) == Self.centered }
        XCTAssertFalse(
            recentered,
            "the reader panned the map away, visited Journal, came back — and the screen "
                + "re-centered on them. A camera the reader deliberately moved is theirs (#128; "
                + "this is #85's defect through the tab bar)."
        )
        XCTAssertEqual(
            value(control2), Self.notCentered,
            "after the round trip the control reads “\(value(control2))”, which is neither "
                + "preserved-pan nor re-centered — something else moved the camera"
        )
    }

    /// Direction two — the overcorrection. No pan, leave, come back: the map may (and, with the
    /// one-shot re-armed on a camera nobody owns, does) settle on the reader again. A fix that
    /// suppressed centering wholesale would fail here.
    func testAnUntouchedCameraStillCentersOnTheReaderAfterTheRoundTrip() throws {
        let (app, _) = try launchCentered()

        switchTabs(app)
        let control = app.buttons[Self.controlLabel]
        XCTAssertTrue(
            wait(timeout: 15) { self.value(control) == Self.centered },
            "the reader never touched the camera, and the returning map is not on them: the "
                + "control reads “\(value(control))”. #128's fix has overshot into #115's "
                + "regression."
        )
    }
}
