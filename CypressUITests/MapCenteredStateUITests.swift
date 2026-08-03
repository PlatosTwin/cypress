import XCTest

/// **The recenter control has to be telling the truth about the map it is sitting on (#100).**
///
/// `CypressTests/MapRecenterTests` proves `MapRecenter.engagement(availability:camera:)` is a correct
/// function of its two arguments. It cannot prove that screen 01 hands it the camera the reader is
/// actually looking at, and that is where the defect was: `AlmanacGroupTapTests` recorded the
/// measurement in its own header — "the control reads `Not centered` for a whole 39-second run, and a
/// screenshot of that same launch has the camera on the fix and the reader's blue dot in the middle of
/// the screen".
///
/// A VoiceOver reader has no blue dot. The `accessibilityValue` is the *whole* of what they are told
/// about where the map is, so a value that says "not centered" over a map that is centered is not a
/// cosmetic slip — it is the one sentence they have, and it is false.
///
/// The check has to be black-box and it has to press the control, because the press is the only thing
/// that puts the camera on the fix without depending on when CoreLocation answers.
///
///     xcrun simctl privacy <udid> grant location app.cypress.Cypress
///     xcrun simctl location <udid> set 37.7599,-122.4148
///
/// **The fix is pinned rather than inherited, and no fix is a failure (task #121).** These tests
/// used to `XCTSkip` when the simulator had given Cypress no location — `MapSearchUITests
/// .requireAMapWithPins`' judgment, in its own words: a skip says "not checked here", which is true,
/// where a failure would say "broken", which is not. That reasoning was correct and it was never the
/// problem. The problem is that a skipped test is invisible in `Test run with N tests passed`, so on
/// the ordinary fixless simulator #115's whole claim went unwatched inside a green number. The launch
/// environment now states the fix (`DebugLocationOverride`; ruling
/// `RULINGS R58`) and `MissingPinnedFix` is what a screen 01
/// that still reports itself fixless earns. The two `simctl` lines above are no longer required to
/// make these tests run; they remain the way to put a device in the *real* state, which is the thing
/// a pinned provider deliberately does not prove.
final class MapCenteredStateUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// `MapRecenterCopy.label`, the one string this file and the app have to agree on.
    private static let controlLabel = "Center the map on you"

    /// `DebugLocationOverride.environmentKey` and `DebugLocationFixtures.missionDolores`' neighbor —
    /// the coordinate this file's own skip message already named (task #121). Literals, because this
    /// target imports nothing from `Cypress`. The seed holds 501 trees within 250 m of it, measured
    /// over the same box `Tools/run_tests.sh` counts, so a run that leaves the camera here leaves a
    /// device the next run's E216 preflight accepts.
    private static let locationKey = "CYPRESS_LOCATION"
    private static let pinnedFix = "37.7599,-122.4148"

    /// `MapRecenterCopy.value(.centered)`.
    private static let centered = "Centered on you"

    /// The states that mean "screen 01 has no fix to center on", spoken by `MapRecenterCopy.value`.
    /// Any one of them, on a launch that pinned a fix, means the pin did not arrive — which is a
    /// defect and not an environment fact. See `MissingPinnedFix`.
    ///
    /// **Copied from `MapRecenterCopy.value` exactly, and it used to not be.** The list carried
    /// `"Not centered yet"`, which that function has never returned — a string one word away from
    /// `"Not centered"`, which is the failure this file exists to catch, sitting in the list of
    /// reasons not to look. And it was missing `askable` entirely, so a simulator that had never been
    /// granted location — the state every fresh simulator is in — did not skip. It **failed**, with
    /// a message blaming #115 for a phone that had simply never been asked.
    private static let fixless = [
        "Location is off",           // MapRecenter.Engagement.unavailable
        "Finding you",               // .searching
        "Cypress has not been given your location",  // .askable
    ]

    /// **The owner's sentence, as a test: "opening the app should open on where you're located right
    /// now" (#115).**
    ///
    /// Nothing is pressed. The app is launched and the control is asked, in the words a VoiceOver
    /// reader would hear, whether the map it opened is on the reader. On a simulator with a fix the
    /// answer has to be yes, and before #115 it was not: screen 01 opened on `MapLayout.defaultCenter`
    /// — Mission Dolores Park — and moved only if `location.availability` happened to *change* after
    /// this screen's `.onChange` was installed. A provider some other screen had already started was
    /// therefore a map that never centered at all.
    ///
    /// **This is the only witness in the suite for E168, and that was measured rather than assumed.**
    /// Two deliberate breaks were built and run against the whole of this file, on an iPhone 16 Pro
    /// with a static fix at 37.7599, −122.4148:
    ///
    /// - Restore the inline write in `MapAnnotationLayer.Coordinator.echo(_:)` — the actual defect —
    ///   and this test fails in 25 s with `("Not centered") is not equal to ("Centered on you")`. The
    ///   other test in this file, the one that presses first, **passes** on that same build, because
    ///   a press produces a real animated flight whose settle arrives outside the update pass and
    ///   therefore lands. That is the whole of "still not centered at launch, and a press fixes it",
    ///   and it is why the unpressed test is the one that matters.
    /// - Remove the main-queue hop from `AimableMapView.layoutSubviews` and aim re-entrantly from
    ///   inside the layout pass: both tests stay **green**. On screen 01 that hook never applies a
    ///   camera at all — `updateUIView` reaches `applyCameraIfChanged` first every launch and spends
    ///   the ticket — so there is nothing for a test to see. Recorded so nobody spends an afternoon
    ///   hunting for the test that guards it: there is none, and there is nothing to guard.
    ///
    /// **This used to be guarded by a skip, and the skip was a hole**: on a machine with no fix the
    /// regression went unwatched, silently, inside a green run, and every ordinary simulator is such
    /// a machine. The launch pins the fix now, so the guard below can only fire when the pin failed
    /// to arrive, and it fires as a failure.
    func testTheMapOpensOnTheReaderWithoutBeingAsked() throws {
        let app = XCUIApplication()
        app.launchEnvironment[Self.locationKey] = Self.pinnedFix
        app.launch()

        let control = app.buttons[Self.controlLabel]
        XCTAssertTrue(
            control.waitForExistence(timeout: 15),
            "screen 01 has no control labeled “\(Self.controlLabel)”"
        )

        // The fix has to arrive and the opening camera has to settle on it. Polled rather than slept
        // through, so a launch that is going to pass pays only what CoreLocation costs.
        let deadline = Date().addingTimeInterval(20)
        var seen = ""
        while Date() < deadline {
            seen = control.value as? String ?? ""
            if seen == Self.centered { break }
            usleep(250_000)
        }

        if Self.fixless.contains(seen) {
            throw MissingPinnedFix(seen: seen, pinned: Self.pinnedFix)
        }

        XCTAssertEqual(
            seen,
            Self.centered,
            """
            the app was launched on a phone that knows where it is, nobody touched anything, and \
            twenty seconds later the map still tells VoiceOver “\(seen)”. This is #115: the app \
            opened somewhere that is not you.
            """
        )
    }

    func testTheControlSaysCenteredOnceTheMapIsOnYou() throws {
        let app = XCUIApplication()
        app.launchEnvironment[Self.locationKey] = Self.pinnedFix
        app.launch()

        let control = app.buttons[Self.controlLabel]
        XCTAssertTrue(
            control.waitForExistence(timeout: 15),
            "screen 01 has no control labeled “\(Self.controlLabel)”"
        )

        let before = control.value as? String ?? ""
        if Self.fixless.contains(before) {
            throw MissingPinnedFix(seen: before, pinned: Self.pinnedFix)
        }

        // The press is the app's own promise that the camera is now on the reader —
        // `MapRecenter.press` returns `.center` or `.centerAndZoomIn`, and `MapHomeView.flyTo`
        // drives the camera to the fix. Whatever the control says afterwards, it is saying it about
        // a map it has just itself put on the user.
        control.tap()

        // The camera flies, and the settled region is what the control reads. A poll rather than a
        // fixed sleep: a run that is going to pass pays only the animation.
        let deadline = Date().addingTimeInterval(15)
        var seen = control.value as? String ?? ""
        while Date() < deadline {
            seen = control.value as? String ?? ""
            if seen == Self.centered { break }
            usleep(250_000)
        }

        XCTAssertEqual(
            seen,
            Self.centered,
            """
            the recenter control was pressed, the map flew to the reader's own fix, and the control \
            still tells VoiceOver “\(seen)”. This is #100: the only sentence a VoiceOver reader gets \
            about where the map is, and it contradicts the map.
            """
        )
    }
}
