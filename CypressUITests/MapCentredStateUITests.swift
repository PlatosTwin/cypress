import XCTest

/// **The recentre control has to be telling the truth about the map it is sitting on (#100).**
///
/// `CypressTests/MapRecentreTests` proves `MapRecentre.engagement(availability:camera:)` is a correct
/// function of its two arguments. It cannot prove that screen 01 hands it the camera the reader is
/// actually looking at, and that is where the defect was: `AlmanacGroupTapTests` recorded the
/// measurement in its own header — "the control reads `Not centred` for a whole 39-second run, and a
/// screenshot of that same launch has the camera on the fix and the reader's blue dot in the middle of
/// the screen".
///
/// A VoiceOver reader has no blue dot. The `accessibilityValue` is the *whole* of what they are told
/// about where the map is, so a value that says "not centred" over a map that is centred is not a
/// cosmetic slip — it is the one sentence they have, and it is false.
///
/// The check has to be black-box and it has to press the control, because the press is the only thing
/// that puts the camera on the fix without depending on when CoreLocation answers.
///
///     xcrun simctl privacy <udid> grant location app.cypress.Cypress
///     xcrun simctl location <udid> set 37.7599,-122.4148
///
/// Without a fix there is nothing to be centred on, so the test **skips** rather than fails —
/// `MapSearchUITests.requireAMapWithPins`' judgement, in its own words: a skip says "not checked
/// here", which is true, where a failure would say "broken", which is not.
final class MapCentredStateUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// `MapRecentreCopy.label`, the one string this file and the app have to agree on.
    private static let controlLabel = "Centre the map on you"
    /// `MapRecentreCopy.value(.centred)`.
    private static let centred = "Centred on you"

    /// The two states that mean "this simulator has no fix for the app to centre on", spoken by
    /// `MapRecentreCopy.value`. Either one makes the assertion below meaningless rather than false.
    private static let fixless = ["Location is off", "Finding you", "Not centred yet"]

    /// **The owner's sentence, as a test: "opening the app should open on where you're located right
    /// now" (#115).**
    ///
    /// Nothing is pressed. The app is launched and the control is asked, in the words a VoiceOver
    /// reader would hear, whether the map it opened is on the reader. On a simulator with a fix the
    /// answer has to be yes, and before #115 it was not: screen 01 opened on `MapLayout.defaultCentre`
    /// — Mission Dolores Park — and moved only if `location.availability` happened to *change* after
    /// this screen's `.onChange` was installed. A provider some other screen had already started was
    /// therefore a map that never centred at all.
    func testTheMapOpensOnTheReaderWithoutBeingAsked() throws {
        let app = XCUIApplication()
        app.launch()

        let control = app.buttons[Self.controlLabel]
        XCTAssertTrue(
            control.waitForExistence(timeout: 15),
            "screen 01 has no control labelled “\(Self.controlLabel)”"
        )

        // The fix has to arrive and the opening camera has to settle on it. Polled rather than slept
        // through, so a launch that is going to pass pays only what CoreLocation costs.
        let deadline = Date().addingTimeInterval(20)
        var seen = ""
        while Date() < deadline {
            seen = control.value as? String ?? ""
            if seen == Self.centred { break }
            usleep(250_000)
        }

        if Self.fixless.contains(seen) {
            throw XCTSkip(
                "this simulator never gave Cypress a fix (the control reads “\(seen)”), so there is "
                    + "nothing the map could have opened on: xcrun simctl privacy <udid> grant "
                    + "location app.cypress.Cypress && xcrun simctl location <udid> set "
                    + "37.7599,-122.4148"
            )
        }

        XCTAssertEqual(
            seen,
            Self.centred,
            """
            the app was launched on a phone that knows where it is, nobody touched anything, and \
            twenty seconds later the map still tells VoiceOver “\(seen)”. This is #115: the app \
            opened somewhere that is not you.
            """
        )
    }

    func testTheControlSaysCentredOnceTheMapIsOnYou() throws {
        let app = XCUIApplication()
        app.launch()

        let control = app.buttons[Self.controlLabel]
        XCTAssertTrue(
            control.waitForExistence(timeout: 15),
            "screen 01 has no control labelled “\(Self.controlLabel)”"
        )

        let before = control.value as? String ?? ""
        if Self.fixless.contains(before) {
            throw XCTSkip(
                "this simulator has no location fix for Cypress (the control reads “\(before)”), so "
                    + "there is nothing for the map to be centred on: xcrun simctl privacy <udid> "
                    + "grant location app.cypress.Cypress && xcrun simctl location <udid> set "
                    + "37.7599,-122.4148"
            )
        }

        // The press is the app's own promise that the camera is now on the reader —
        // `MapRecentre.press` returns `.centre` or `.centreAndZoomIn`, and `MapHomeView.flyTo`
        // drives the camera to the fix. Whatever the control says afterwards, it is saying it about
        // a map it has just itself put on the user.
        control.tap()

        // The camera flies, and the settled region is what the control reads. A poll rather than a
        // fixed sleep: a run that is going to pass pays only the animation.
        let deadline = Date().addingTimeInterval(15)
        var seen = control.value as? String ?? ""
        while Date() < deadline {
            seen = control.value as? String ?? ""
            if seen == Self.centred { break }
            usleep(250_000)
        }

        XCTAssertEqual(
            seen,
            Self.centred,
            """
            the recentre control was pressed, the map flew to the reader's own fix, and the control \
            still tells VoiceOver “\(seen)”. This is #100: the only sentence a VoiceOver reader gets \
            about where the map is, and it contradicts the map.
            """
        )
    }
}
