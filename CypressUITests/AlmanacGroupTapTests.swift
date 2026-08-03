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

        // `Walk `, not `Walk the ` — **the anchor was count-sensitive and the corpus moved under
        // it.** `AlmanacPresentation.coverageCTA` reads `Walk to it` for one tree and
        // `Walk the <n>` for more, because "walk the one" is not a sentence. Under the DataSF export
        // the neighborhood these tests land in (Western Addition, from the simulated fix at
        // 37.78485,-122.4215) held two young trees, so the plural branch was the only one anybody
        // saw. #91 cut the seed's planting dates from 70,067 to 28,747 and that count fell to one, so
        // the CTA started rendering in its singular voice and this test began failing on a screen
        // that was drawing the button correctly.
        //
        // It failed with `§4's CTA is not on the almanac`, which is a true sentence about the
        // predicate and a false one about the app — the exact "blame the almanac for something else"
        // failure E153 removed from these tests one round earlier. The count belongs in the
        // assertions below, which read `ctaLabel` and the destination's own sentence; it does not
        // belong in the locator that decides whether the control exists at all.
        let walk = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Walk "))
            .firstMatch
        try reachAlmanac(app, waitingFor: walk)

        // `reachAlmanac` has already waited for this and skipped if the screen was showing the
        // location prompt instead, so a failure here is the real one: the almanac has a
        // neighborhood and §4's CTA is missing from it.
        XCTAssertTrue(walk.exists, "§4's CTA is not on the almanac, which does have a neighborhood")
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

        // See the sibling test: past `reachAlmanac` the neighborhood is there and this is R10's row
        // genuinely missing from it.
        XCTAssertTrue(row.exists, "R10's row is not on the almanac, which does have a neighborhood")
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

    /// **Screen 01, not `CYPRESS_SCREEN=journal`, and that is the whole of the second half of this
    /// fix** (ERRATA E153).
    ///
    /// These two tests used to deep link straight to the journal tab, and on that entrance they could
    /// not pass on any machine, with a fix or without one. `AlmanacView` builds its `@State` model from
    /// the coordinate it is handed and keeps it (E123 records this as a known limitation), and the deep
    /// link puts screen 12 on the glass inside the first frames — before CoreLocation has published
    /// anything, and before the ask has even been answered. The model reads `almanac(near: nil)`, which
    /// is `.empty` by contract, and the screen is then blank for the rest of the launch: no rows,
    /// because there is no neighborhood, and no prompt either, because the fix *does* arrive a moment
    /// later and `showsLocationPrompt` is `coordinate == nil`.
    ///
    /// So the app is launched the way it launches for a person: on the map, which is the one screen
    /// that asks for location (`MapHomeView.task` is the only caller of `start()` on the shipping
    /// path), and the journal is reached by pressing the tab bar afterwards. That is not a workaround
    /// for the empty screen — it is the sequence in which the app is used, and the only one in which
    /// screen 12 is built from a coordinate that exists. The blank almanac is left as it is, on
    /// purpose: it is a defect in the app rather than in this test, and a test that navigated around it
    /// twice would be the thing that keeps it invisible.
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        return app
    }

    /// Screen 12's `AlmanacCopy.locationPromptTitle` — what the screen draws *instead of* its blocks
    /// when there is no fix. Repeated here as a literal because these tests import nothing from
    /// `Cypress`; if the copy changes this stops matching, which is the same bargain every other
    /// anchor in this file makes.
    /// American spelling since ERRATA E182 — this literal is the reason a copy change to that
    /// string has to be made in two places, and the bargain the doc comment above describes.
    private static let locationPrompt = "See your neighborhood"

    /// Screen 12's `§3` label, which is the almanac saying it has a neighborhood.
    ///
    /// A9 — "species mix always renders from city data" — is what makes it a sound witness: §2, §4 and
    /// the vacant block can each be absent on their own merits, and this one cannot. Matched by prefix
    /// because it carries a count (`Who lives here · 135 species`).
    private static let neighborhoodBlock = "Who lives here"

    /// How many individual tree pins screen 01 has drawn — the same proxy, in the same words, as
    /// `MapSearchUITests.cityTreePins`, including its warning that this must match `label` rather than
    /// `identifier` and must be a prefix rather than an equality.
    private func cityTreePins(_ app: XCUIApplication) -> Int {
        app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "City tree"))
            .count
    }

    /// Gets to a populated almanac the way a person does, and **skips** rather than fails when there is
    /// no fix for it to be populated from.
    ///
    /// The location ask belongs to Springboard rather than to Cypress, so it is tapped through
    /// Springboard's own element tree — an `addUIInterruptionMonitor` fires only on the next
    /// interaction with the app, which is too late when the thing being waited for is behind the alert.
    ///
    /// Without a fix there is no neighborhood and therefore neither of the two rows (A4, ERRATA E44):
    /// `AlmanacScreen` draws E123's location prompt in place of all four blocks, so both rows are
    /// *correctly* absent. That is an environment fact and not a defect, so it is an `XCTSkip` — the
    /// judgment `MapSearchUITests.requireAMapWithPins` already made for the same missing fix, in the
    /// same words: a skip says "not checked here", which is true, where a failure says "broken", which
    /// is not. The first skip is decided on the map, before the almanac is opened at all, because
    /// arriving on screen 12 before there is a fix is what produces the blank screen described on
    /// `launch()` — and a blank screen cannot be asked anything.
    ///
    /// **The map is asked in pins, not in words, and the obvious alternative was measured and
    /// rejected.** `MapRecenterCopy.value` looked like the better witness — `Centered on you` is
    /// reachable only through `camera.isCentered(on: coordinate)`, so it cannot be true without a
    /// coordinate — and it does not work. Measured on a simulator with a fix set over Van Ness: the
    /// control reads `Not centered` for a whole 39-second run, and a screenshot of that same launch has
    /// the camera on the fix and the reader's blue dot in the middle of the screen. Something between
    /// the settled region and `MapRecenter.Camera` disagrees with the picture; whatever it is, it
    /// belongs to screen 01 and not here.
    ///
    /// **And the pin wait below is not a fix detector, whatever its neighbor says.**
    /// `MapSearchUITests.requireAMapWithPins` reads "individual pins are drawn" as "there is a fix",
    /// because a fixless map supposedly opens on the whole city at a clustered zoom. It does not:
    /// screen 01 opens at `MapLayout.defaultSpanMeters` — 120 m across — either way, and only the
    /// center differs. Measured with location revoked outright for this app, the map opens on Dolores
    /// Park and draws pins there anyway. So the wait here claims nothing about a fix; it holds the test
    /// on the map until the map has finished its first read, which is the difference between pressing
    /// `Journal` before CoreLocation has answered and pressing it after.
    ///
    /// **The second wait is a race, and deliberately not a symmetric one.** What it used to be was
    /// `waitForExistence(timeout: 3)` on the prompt, which is a fixed wait on an *absence*: too long
    /// for a healthy run to pay and too short to catch the state it was looking for, so the guard
    /// missed and both tests failed on a row they had themselves decided might not be there. Now
    /// `content` — the row this particular test is about — ends the wait the moment it appears, so a
    /// run that is going to pass pays nothing for the guard. The prompt does not end it early. It is
    /// the state screen 12 is drawn in until a coordinate turns up, and this file has already been
    /// wrong once about how long that takes; letting it decide only after the row has failed to arrive
    /// costs a machine with a fix nothing and cannot misfire on one without.
    private func reachAlmanac(_ app: XCUIApplication, waitingFor content: XCUIElement) throws {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = ["Allow While Using App", "Allow Once", "Allow"].map { springboard.buttons[$0] }
        // Whichever of the three this iOS draws, or none at all when permission is already answered —
        // polled together rather than waited for one at a time, so the already-answered case costs one
        // window instead of three.
        if wait(timeout: 8, for: { allow.contains { $0.exists } }) {
            allow.first { $0.exists }?.tap()
        }

        XCTAssertTrue(
            wait(timeout: 30, for: { self.cityTreePins(app) > 0 }),
            "screen 01 drew no tree pins in thirty seconds, which it does with a fix and without one"
        )

        app.buttons["Journal"].tap()
        let neighborhood = app.buttons["Neighborhood"]
        XCTAssertTrue(
            neighborhood.waitForExistence(timeout: 20),
            "the Journal tab draws no “Neighborhood” segment, so screen 12 has no entrance"
        )
        neighborhood.tap()

        guard app.staticTexts["Almanac"].waitForExistence(timeout: 30) else {
            XCTFail("the Journal tab did not draw the almanac")
            return
        }

        if wait(timeout: 30, for: { content.exists }) { return }

        if app.staticTexts[Self.locationPrompt].exists {
            throw XCTSkip(
                "screen 12 drew “\(Self.locationPrompt)” instead of its neighborhood, so neither "
                    + "counted row exists to tap — this needs a simulated GPS fix over San Francisco: "
                    + "xcrun simctl location <udid> set 37.78485,-122.4215"
            )
        }

        // Neither the row nor the prompt, and the three states that produces are not one report.
        //
        // With §3 on screen the almanac has a neighborhood and is simply missing this row, which is
        // the defect these tests are for; that is left to the caller's own assertion, which names the
        // row. Without §3 the screen is *blank* — no blocks, no prompt, no failure sentence — which is
        // the state the deep-link entrance produced every time and the reason this test no longer uses
        // it. Naming it here rather than reporting it as a missing row is the whole point of the
        // exercise: the last thing this file should do is blame the almanac for it twice.
        let hasNeighborhood = app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH %@", Self.neighborhoodBlock))
            .firstMatch
            .exists
        if !hasNeighborhood {
            XCTFail(
                "screen 12 drew neither its neighborhood nor “\(Self.locationPrompt)”: a blank "
                    + "almanac, which is what a coordinate arriving after `AlmanacModel` was built "
                    + "leaves behind (E123's known limitation; ERRATA E155)"
            )
        }
    }

    /// Waits for a condition, polling. Mirrors `MapSearchUITests.wait(timeout:for:)` — same reason,
    /// same shape: what is worth asserting about this screen is where it settles, never when. Copied
    /// rather than lifted, because that one is `private` to its own file and making it shared would be
    /// a change to a file this task has no other business in; a third caller is the point at which it
    /// should become one helper for the target.
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
