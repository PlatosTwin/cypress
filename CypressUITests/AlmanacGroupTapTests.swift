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
    func testWalkTheNineOpensAMapOfThemAll() {
        let app = launch()
        guard reachAlmanac(app) else { return }

        let walk = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Walk the "))
            .firstMatch
        XCTAssertTrue(walk.waitForExistence(timeout: 30), "§4's CTA is not on the almanac")
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
    func testTheVacantRowOpensAMapAndNamesThePage() {
        let app = launch()
        guard reachAlmanac(app) else { return }

        let row = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "empty planting site"))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30), "R10's row is not on the almanac")
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

    /// Gets to a populated almanac, dismissing the location ask on the way.
    ///
    /// The ask belongs to Springboard rather than to Cypress, so it is tapped through Springboard's own
    /// element tree — an `addUIInterruptionMonitor` fires only on the next interaction with the app,
    /// which is too late when the thing being waited for is behind the alert.
    ///
    /// Without a fix there is no neighbourhood and therefore neither of the two rows (A4, ERRATA E44),
    /// so a device with location refused reports that rather than failing an assertion about a row that
    /// is correctly absent.
    private func reachAlmanac(_ app: XCUIApplication) -> Bool {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow While Using App", "Allow Once", "Allow"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 5) {
                button.tap()
                break
            }
        }

        guard app.staticTexts["Almanac"].waitForExistence(timeout: 30) else {
            XCTFail("the Journal tab did not draw the almanac")
            return false
        }
        if app.staticTexts["See your neighbourhood"].waitForExistence(timeout: 3) {
            XCTFail("no location fix, so screen 12 has no neighbourhood and neither counted row exists")
            return false
        }
        return true
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
