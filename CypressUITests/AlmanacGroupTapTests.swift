import XCTest

/// **Screen 12's two counted rows, tapped** (ERRATA E129).
///
/// Every other test of this change is a value test, and value tests are exactly what let the defect
/// ship. The coverage card's count was right, its copy was right, its button worked, and its
/// destination rendered — the button just went to one tree's page. Four defects in this project have
/// passed a green suite and been found by a person tapping a build (E103, E110, E118, E126), and this
/// is the same shape: nothing is broken, the wrong screen arrives.
///
/// So this drives the shipped binary. It taps `Walk the …`, reads what arrives, taps
/// `… empty planting sites`, and reads what arrives. It also writes a PNG per stop, so the result of a
/// tap is something a person can look at rather than a string a test agreed with — set
/// `CYPRESS_SHOT_DIR` in the runner's environment to choose where; otherwise the paths are printed.
///
/// **What it deliberately does not do is tap a pin.** `DeepLinkVoiceOverTests` states the reason:
/// a MapKit annotation "is not a thing a test can do reliably, because the basemap renders
/// asynchronously and puts its pins wherever the camera settles". Where a pin goes is asserted at the
/// value level instead, in `PinSetDestinationTests.eachRecordKeepsItsOwnPin`, against the same
/// `MapHomeView.route(for:)` the composition root calls.
///
/// **Black-box, like the other UI tests here**: nothing imports `Cypress`, and every anchor is a word
/// the app says out loud. If the copy changes, this fails, which is correct — a reader's map of the
/// screen changed too.
final class AlmanacGroupTapTests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// `Where eyes are needed` → a map of every young tree the card counted.
    ///
    /// The two assertions that matter are the two the broken build would have failed: the screen that
    /// arrives is the *block's* screen and not a tree's profile, and it says how much of the group is
    /// on it. The profile that used to arrive has neither string on it — it has `A young tree nobody
    /// has visited`, which is asserted absent for exactly that reason.
    func testWalkTheNineOpensAMapOfThemAll() throws {
        let app = launch()

        let walk = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Walk the "))
            .firstMatch
        try reachAlmanac(app, waitingFor: walk)

        // `reachAlmanac` has already waited for this and skipped if the screen was showing the
        // location prompt instead, so a failure here is the real one: the almanac has a
        // neighbourhood and §4's CTA is missing from it.
        XCTAssertTrue(walk.exists, "§4's CTA is not on the almanac, which does have a neighbourhood")
        let ctaLabel = walk.label
        walk.tap()

        XCTAssertTrue(
            app.staticTexts["Where eyes are needed"].waitForExistence(timeout: 20),
            "'\(ctaLabel)' did not open the coverage block's own screen"
        )
        let onThisMap = text(in: app, endingWith: "on this map.")
        XCTAssertNotNil(onThisMap, "the destination does not say how many records are on its map")
        XCTAssertTrue(
            app.staticTexts["A young tree nobody has visited."].exists == false,
            "'\(ctaLabel)' still lands on one tree's cold profile"
        )

        // The count the row printed is repeated on its destination, from the same function — so the
        // two screens cannot come to disagree. `Walk the seventeen` ⇢ `17 young trees …`.
        let subject = text(in: app, containing: "young tree")
        XCTAssertNotNil(subject, "the destination does not repeat the card's own sentence")

        record(app, named: "e129-coverage-group", note: "\(ctaLabel) → \(onThisMap ?? "?")")
    }

    /// `Where a tree could go` → a map of the nearest basins, saying how many of the 1,474 it holds.
    ///
    /// This is the E38 half. The row's own count stays on screen and the map holds a page of it, so the
    /// page has to name its own size in the same breath. A destination that said `All 1,474 are on this
    /// map.` over twenty pins would be the defect E38 exists for, and it is asserted against directly.
    func testTheVacantRowOpensAMapAndNamesThePage() throws {
        let app = launch()

        let row = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "empty planting site"))
            .firstMatch
        try reachAlmanac(app, waitingFor: row)

        // See the sibling test: past `reachAlmanac` the neighbourhood is there and this is R10's row
        // genuinely missing from it.
        XCTAssertTrue(row.exists, "R10's row is not on the almanac, which does have a neighbourhood")
        let rowLabel = row.label
        row.tap()

        XCTAssertTrue(
            app.staticTexts["Where a tree could go"].waitForExistence(timeout: 20),
            "'\(rowLabel)' did not open the vacant block's own screen"
        )
        // The site screen is what this row used to open, and its own line is the tell.
        XCTAssertFalse(
            app.staticTexts["No tree at this site"].exists,
            "the row still opens one basin"
        )

        let line = text(in: app, endingWith: "on this map.")
        XCTAssertNotNil(line, "the destination does not say how many basins are on its map")
        if let line {
            XCTAssertTrue(
                line.hasPrefix("The ") && line.contains("nearest"),
                "a page of 1,474 presented itself as the whole set: \(line)"
            )
        }

        record(app, named: "e129-vacant-group", note: "\(rowLabel) → \(line ?? "?")")
    }

    // MARK: - Harness

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CYPRESS_SCREEN"] = "journal"
        app.launch()
        return app
    }

    /// Screen 12's `AlmanacCopy.locationPromptTitle` — what the screen draws *instead of* its blocks
    /// when there is no fix. Repeated here as a literal because these tests import nothing from
    /// `Cypress`; if the copy changes this stops matching, which is the same bargain every other
    /// anchor in this file makes.
    private static let locationPrompt = "See your neighbourhood"

    /// Gets to a populated almanac, dismissing the location ask on the way, and **skips** rather than
    /// fails when there is no fix for it to be populated from.
    ///
    /// The ask belongs to Springboard rather than to Cypress, so it is tapped through Springboard's own
    /// element tree — an `addUIInterruptionMonitor` fires only on the next interaction with the app,
    /// which is too late when the thing being waited for is behind the alert.
    ///
    /// Without a fix there is no neighbourhood and therefore neither of the two rows (A4, ERRATA E44):
    /// `AlmanacScreen` draws E123's location prompt in place of all four blocks, so both rows are
    /// *correctly* absent. That is an environment fact and not a defect, so it is an `XCTSkip` — the
    /// judgement `MapSearchUITests.requireAMapWithPins` already made for the same missing fix, in the
    /// same words: a skip says "not checked here", which is true, where a failure says "broken", which
    /// is not.
    ///
    /// **The wait is a race, and it is deliberately not symmetric** (ERRATA — see
    /// docs/errata-pending/almanac-location.md). What it used to be was `waitForExistence(timeout: 3)`
    /// on the prompt, which is a fixed wait on an *absence*: three seconds is longer than a healthy run
    /// should ever pay and shorter than the almanac takes to settle, so the guard missed and the test
    /// went on to fail on a row it had itself decided might not be there. Now `content` — the row this
    /// particular test is about — ends the wait the moment it appears, so a machine with a fix pays
    /// nothing. The prompt does **not** end it early, because "the prompt is on screen" is the state
    /// screen 12 opens in whether or not a fix is coming: `showsLocationPrompt` is `coordinate == nil`
    /// and the coordinate arrives from CoreLocation after the screen is already drawn. Only once the
    /// content has failed to arrive does the prompt decide *which* report is honest — skip, or the
    /// caller's own assertion.
    private func reachAlmanac(_ app: XCUIApplication, waitingFor content: XCUIElement) throws {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = ["Allow While Using App", "Allow Once", "Allow"].map { springboard.buttons[$0] }
        // Whichever of the three this iOS draws, or none at all when permission is already answered —
        // polled together rather than waited for one at a time, so the already-answered case costs one
        // window instead of three.
        if wait(timeout: 5, for: { allow.contains { $0.exists } }) {
            allow.first { $0.exists }?.tap()
        }

        guard app.staticTexts["Almanac"].waitForExistence(timeout: 30) else {
            XCTFail("the Journal tab did not draw the almanac")
            return
        }

        if wait(timeout: 30, for: { content.exists }) { return }

        if app.staticTexts[Self.locationPrompt].exists {
            throw XCTSkip(
                "screen 12 drew “\(Self.locationPrompt)” instead of its neighbourhood, so neither "
                    + "counted row exists to tap — this needs a simulated GPS fix over San Francisco: "
                    + "xcrun simctl location <udid> set 37.78485,-122.4215"
            )
        }
        // Neither the content nor the prompt: the almanac claims a neighbourhood and is missing the
        // row anyway, which is a defect. Left to the caller's own assertion, which names the row.
    }

    /// Waits for a condition, polling. Mirrors `MapSearchUITests.wait(timeout:for:)` — same reason,
    /// same shape: what is worth asserting about this screen is where it settles, never when. Copied
    /// rather than shared because that one is `private` to a file two other tasks are editing this
    /// week; if a third caller appears it should become one helper for the target.
    @discardableResult
    private func wait(timeout: TimeInterval = 30, for condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            usleep(200_000)
        }
        return condition()
    }

    /// The first static text on screen ending with `suffix`, or nil.
    private func text(in app: XCUIApplication, endingWith suffix: String) -> String? {
        app.staticTexts
            .matching(NSPredicate(format: "label ENDSWITH %@", suffix))
            .firstMatch
            .exists
            ? app.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", suffix)).firstMatch.label
            : nil
    }

    private func text(in app: XCUIApplication, containing fragment: String) -> String? {
        let match = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", fragment))
            .firstMatch
        return match.exists ? match.label : nil
    }

    /// A PNG per stop, plus the same image on the result bundle.
    ///
    /// Written to a real path as well as attached, because an attachment inside an `.xcresult` is not
    /// something anybody opens. `TEST_RUNNER_CYPRESS_SHOT_DIR` chooses the directory — the
    /// `TEST_RUNNER_` prefix is what forwards an `xcodebuild` variable into the runner's environment.
    private func record(_ app: XCUIApplication, named name: String, note: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let directory = ProcessInfo.processInfo.environment["CYPRESS_SHOT_DIR"] ?? NSTemporaryDirectory()
        let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
        try? shot.pngRepresentation.write(to: url)
        print("E129 SHOT \(url.path) — \(note)")
    }
}
