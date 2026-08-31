import XCTest

/// **The neighborhood/city picker, driven on the shipped binary** — the owner's 2026-08-28 backlog
/// item and the designated fix for tester report F17.
///
/// Every other test of this change is a value test, and a value test cannot see the thing F17 is
/// actually about: what a person reads on the screen and what they can do about it. The report is
/// one sentence — *"I am nowhere near Castro/upper market … Why does this page seem to default to
/// showing stats for Castro/market?"* — and the answer has to be legible in the app, not correct in
/// a payload. So this file asserts the sentences and taps the buttons.
///
/// It also writes a PNG per state, for `AlmanacGroupTapTests`' reason: the result of a tap should be
/// something a person can look at rather than a string a test agreed with. Set `CYPRESS_SHOT_DIR`
/// (as `TEST_RUNNER_CYPRESS_SHOT_DIR` on the `xcodebuild` command line) to choose where.
///
/// **The coarse-fix case is launched, not simulated.** `CYPRESS_LOCATION=lat,lon,accuracy` is R58's
/// own hook and it takes a stated accuracy, so the state F17 comes from — a fix in hand that is too
/// rough to place the reader — is reachable here as a launch argument rather than as a mock.
///
/// **Black-box like the rest of this target**: nothing imports `Cypress`, and every anchor is a word
/// the app says out loud. If the copy changes this fails, which is correct — the reader's map of the
/// screen changed too.
final class AreaPickerUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: - 1 · The default says where it came from, and can be changed

    func testTheAlmanacSaysWhereItsAreaCameFromAndLetsTheReaderChangeIt() {
        let app = launch(fix: Self.westernAddition)
        reachSegment(app, named: "Neighborhood", waitingFor: composition(app))
        record(app, named: "picker-1-local-default")

        // The half of the fix that is not the picker: the screen now accounts for its own area.
        XCTAssertTrue(
            app.staticTexts[Self.fromFixNote].exists,
            "the almanac named an area and said nothing about where the name came from — F17's own complaint"
        )

        // The control for the assertion after the pick: §4 is here while the area is the reader's.
        let coverage = app.staticTexts[Self.coverageLabel]
        XCTAssertTrue(
            coverage.waitForExistence(timeout: 20),
            "§4 is absent for the reader's own area, so its absence after a pick would prove nothing"
        )

        let change = app.buttons[Self.change]
        XCTAssertTrue(change.exists, "the almanac offers no way to change its area")
        change.tap()

        XCTAssertTrue(
            app.staticTexts[Self.neighborhoodSheetTitle].waitForExistence(timeout: 20),
            "tapping “\(Self.change)” opened no picker"
        )
        record(app, named: "picker-2-sheet-open")
        XCTAssertTrue(app.buttons[Self.here].exists, "the picker offers no way back to the reader's own area")

        // ── The picker is modal, and these are the assertions that say so ────────────────────────
        //
        // PR #132's review opened this sheet and then tapped `City` on the C5 segmented control
        // *through the scrim*: the segment switched, the sheet vanished with no dismissal and no
        // `onClose`, and the scrim had never covered that control in the first place. It was drawn
        // as a `ZStack` layer inside the tab's own content rather than presented over it.
        //
        // `isHittable` is the property that separates the two, and it is checked at both ends of the
        // screen because the old layer left the segmented control and the tab bar equally live. An
        // element behind a modal presentation still **exists** — this must not be an existence check.
        //
        // ── What this pair does NOT prove, stated where the next reader meets it ──────────────────
        // It catches a sheet drawn **inside the tab's content**, which is the defect that shipped,
        // and nothing narrower than that. It was red-proved against that exact arrangement, and it
        // was also tried against a full-window `.overlay` on the `NavigationStack`, where it
        // **passed** — correctly, since such an overlay does cover both controls. So this cannot
        // tell a `fullScreenCover` from any other full-window layer, and it is not a proof that the
        // presentation is a system modal. It also says nothing about VoiceOver: the background stays
        // in the accessibility hierarchy behind a cover, so only hittability is being witnessed here.
        XCTAssertFalse(
            app.buttons["City"].isHittable,
            "the segmented control is tappable behind the picker's scrim, so the sheet is not modal"
        )
        XCTAssertFalse(
            app.buttons["Journal"].isHittable,
            "the tab bar is tappable behind the picker's scrim, so the sheet is not modal"
        )

        let elsewhere = app.buttons[Self.otherNeighborhood]
        XCTAssertTrue(
            elsewhere.waitForExistence(timeout: 20),
            "“\(Self.otherNeighborhood)” is not in the picker, which reads the whole inventory"
        )
        elsewhere.tap()

        // The header pill is the screen naming its own subject, and it is what a reader checks.
        XCTAssertTrue(
            app.staticTexts[Self.otherNeighborhood].waitForExistence(timeout: 20),
            "the almanac did not take the neighborhood that was picked"
        )
        record(app, named: "picker-3-picked-neighborhood")

        XCTAssertTrue(
            app.staticTexts[Self.byChoiceNote].exists,
            "the screen is showing a place the reader is not in and does not say so"
        )
        // §4 asks the reader to go and look at particular trees. Pointed across town it has no
        // addressee, and the control above proves this absence is the pick rather than the seed.
        XCTAssertFalse(
            coverage.exists,
            "“\(Self.coverageLabel)” is asking somebody to walk to a neighborhood they are not in"
        )
    }

    // MARK: - 2 · The City segment picks a city, and names it

    func testTheCitySegmentPicksACityAndNamesIt() {
        let app = launch(fix: Self.westernAddition)
        reachSegment(app, named: "City", waitingFor: composition(app))
        record(app, named: "picker-4-city-default")

        XCTAssertTrue(
            app.staticTexts[Self.homeCity].exists,
            "the City segment does not name the city it is about, which the record now carries"
        )

        let change = app.buttons[Self.change]
        XCTAssertTrue(change.exists, "the City segment offers no way to change its city")
        change.tap()

        let other = app.buttons[Self.otherCity]
        XCTAssertTrue(
            other.waitForExistence(timeout: 20),
            "“\(Self.otherCity)” is not in the city picker, and the bundled record is fused across two cities"
        )
        other.tap()

        XCTAssertTrue(
            app.staticTexts[Self.otherCity].waitForExistence(timeout: 20),
            "the City segment did not take the city that was picked"
        )
        record(app, named: "picker-5-picked-city")
        XCTAssertTrue(
            app.staticTexts[Self.byChoiceCityNote].exists,
            "the segment is showing a city the reader is not in and does not say so"
        )
    }

    // MARK: - 3 · The other `.fromFix` mechanism: a city the record holds no polygons for

    /// **R29's radius fallback, which is every reader in San Jose, permanently** — all 52,788 of that
    /// city's rows carry `neighborhood_id IS NULL`.
    ///
    /// The first version of this round printed "Chosen from the tree nearest you in the city record."
    /// here, directly above a sentence saying no boundary exists and the almanac was drawn around
    /// you instead. Two adjacent sentences about one area, and the new one was the false one
    /// (PR #132 review, F1). This drives that state on the device and reads both lines.
    func testASanJoseReaderIsToldWhatActuallyChoseItsArea() {
        let app = launch(fix: Self.downtownSanJose)
        reachSegment(app, named: "Neighborhood", waitingFor: composition(app), throughPins: false)
        record(app, named: "picker-10-san-jose-fallback")

        // The pill is a distance rather than a place, which is what says this is the fallback and
        // not some other screen agreeing with the assertions below.
        XCTAssertTrue(
            app.staticTexts[Self.radiusPill].exists,
            "this reader is not in the radius fallback, so the sentences below are not under test"
        )
        XCTAssertTrue(
            app.staticTexts[Self.fromFixRadiusNote].exists,
            "the fallback does not say what chose its area"
        )
        XCTAssertFalse(
            app.staticTexts[Self.fromFixNote].exists,
            "the screen claims a nearest tree chose a circle that was drawn around the reader — "
                + "F17's own defect, in the sentence written to fix it"
        )
        // The line it has to agree with, still there and still directly under it. **Matched by
        // prefix**: an exact anchor of this length is rejected by XCUITest outright — "Invalid query
        // - string identifier …" — which reads as a failing assertion rather than as a malformed
        // one, and cost this test a red run to learn.
        XCTAssertTrue(
            app.staticTexts
                .matching(NSPredicate(format: "label BEGINSWITH %@", Self.noBoundariesNote))
                .firstMatch.exists
        )
        // And the picker is offered here too: this reader has 41 neighborhoods to choose from and no
        // polygon of their own.
        XCTAssertTrue(app.buttons[Self.change].exists)
    }

    // MARK: - 4 · Outside every inventory, the picker is the one door open

    /// A good, precise fix in Sacramento: the record does not reach it, so no area resolves and the
    /// screen says so. Before this round that was a dead end with nothing on it to press.
    func testAReaderOutsideEveryInventoryIsOfferedThePicker() {
        let app = launch(fix: Self.sacramento)
        reachSegment(
            app,
            named: "Neighborhood",
            waitingFor: app.staticTexts[Self.outOfRangeTitle],
            throughPins: false
        )
        record(app, named: "picker-8-out-of-range")

        XCTAssertTrue(
            app.staticTexts[Self.outOfRangeTitle].exists,
            "a precise fix outside every inventory did not reach the out-of-range state"
        )
        let pick = app.buttons[Self.pickAnArea]
        XCTAssertTrue(pick.exists, "the out-of-range state offers nothing to do, as it always did")
        pick.tap()
        let elsewhere = app.buttons[Self.otherNeighborhood]
        XCTAssertTrue(elsewhere.waitForExistence(timeout: 20))
        elsewhere.tap()
        XCTAssertTrue(
            composition(app).waitForExistence(timeout: 20),
            "picking an area from outside every inventory produced no almanac"
        )
        record(app, named: "picker-9-out-of-range-recovered")
    }

    // MARK: - 5 · A fix too rough to place the reader (F17's own mechanism)

    /// The state the report came from, reproduced: location granted, a fix in hand, and the fix's
    /// own error circle wider than the search that would name a neighborhood inside it.
    ///
    /// Before this round the screen named a neighborhood anyway. It now says what it knows and
    /// offers the one thing the reader can do.
    func testACoarseFixNamesNoNeighborhoodAndOffersThePicker() {
        let app = launch(fix: Self.coarseWesternAddition)
        reachSegment(app, named: "Neighborhood", waitingFor: app.staticTexts[Self.coarseTitle])
        record(app, named: "picker-6-coarse-fix")

        XCTAssertTrue(
            app.staticTexts[Self.coarseTitle].exists,
            "a ±3,000 m fix still produced a confidently named neighborhood — F17, unfixed"
        )
        // Not the location prompt: location is granted and a fix arrived. Telling the reader to turn
        // on something already on would be a second wrong sentence over the first.
        XCTAssertFalse(
            app.staticTexts[Self.locationPrompt].exists,
            "the screen is asking for location that was granted and has already answered"
        )

        let pick = app.buttons[Self.pickAnArea]
        XCTAssertTrue(pick.exists, "the only door out of this state is missing")
        pick.tap()
        XCTAssertTrue(
            app.staticTexts[Self.neighborhoodSheetTitle].waitForExistence(timeout: 20),
            "“\(Self.pickAnArea)” opened no picker"
        )

        let elsewhere = app.buttons[Self.otherNeighborhood]
        XCTAssertTrue(elsewhere.waitForExistence(timeout: 20))
        elsewhere.tap()
        XCTAssertTrue(
            composition(app).waitForExistence(timeout: 20),
            "picking an area out of the coarse-fix state produced no almanac"
        )
        record(app, named: "picker-7-coarse-fix-recovered")
    }

    // MARK: - Anchors
    //
    // Literals, because this target imports nothing from `Cypress`. Each names the constant it
    // mirrors, so a copy change has one place to look for its second home.

    /// `DebugLocationOverride.environmentKey`, and `DebugLocationFixtures.westernAddition`.
    private static let locationKey = "CYPRESS_LOCATION"
    private static let westernAddition = "37.78485,-122.4215"
    /// The same point at an accuracy far outside `AlmanacLimits.neighborhoodResolutionRadiusM` —
    /// roughly what iOS returns for an approximate-location grant.
    private static let coarseWesternAddition = "37.78485,-122.4215,3000"
    /// Precise, and outside every inventory in the record — `AlmanacCopy.outOfRangeTitle`'s state.
    private static let sacramento = "38.5816,-121.4944"
    /// Precise, inside the bundle's second city — whose 52,788 rows carry no neighborhood at all, so
    /// this is R29's radius fallback rather than a named polygon.
    private static let downtownSanJose = "37.3352,-121.8895"

    /// `AlmanacCopy.compositionLabel`'s prefix — §3, the block A9 says always renders from city
    /// data, which makes it the sound witness that the almanac (and the City segment's card 2, which
    /// reuses it) has an area at all.
    ///
    /// **Matched by PREFIX and not by equality**, and that distinction cost a red run to learn: the
    /// label carries a species count (`Who lives here · 200 species`), so an exact anchor matches
    /// nothing and reports it as the screen being empty. `AlmanacGroupTapTests.cityTreePins` carries
    /// the same warning about the same kind of anchor.
    private static let compositionLabel = "Who lives here"
    /// `AlmanacCopy.coverageLabel` — §4, the app's one directed ask. Exact: it carries no count.
    private static let coverageLabel = "Where eyes are needed"
    /// `AlmanacCopy.locationPromptTitle`.
    private static let locationPrompt = "See your neighborhood"

    /// `AreaPickerCopy`, each one.
    private static let fromFixNote = "Chosen from the tree nearest you in the city record."
    /// `AreaPickerCopy.resolvedFromFixRadius`, and `AlmanacCopy.areaPill`'s fallback string.
    private static let fromFixRadiusNote = "Centered on where you are."
    private static let radiusPill = "Within a 15-minute walk"
    /// `AlmanacCopy.areaNote`'s opening — the sentence the provenance line has to agree with.
    /// A prefix, not the whole of it: see the assertion that uses it.
    private static let noBoundariesNote = "No neighborhood boundaries are on file for where you are"
    /// Two of them: the two segments withhold different sections, so they say different sentences.
    private static let byChoiceNote =
        "You're reading a place you're not in, so the section asking you to go and look is left out."
    private static let byChoiceCityNote =
        "You're reading a city you're not in, so the comparison with your own streets is left out."
    private static let change = "Change"
    private static let here = "Where I am"
    private static let neighborhoodSheetTitle = "Neighborhood"
    private static let coarseTitle = "Your location is too rough to place you."
    private static let pickAnArea = "Pick an area"
    /// `AlmanacCopy.outOfRangeTitle`.
    private static let outOfRangeTitle = "No inventory reaches here yet."

    /// A neighborhood the pinned fix does **not** resolve (that is Western Addition), high enough up
    /// the largest-first list to be on the first screenful of chips. `dim_city.display_name` for the
    /// two cities the bundled seed is fused across.
    private static let otherNeighborhood = "Sunset/Parkside"
    private static let homeCity = "San Francisco"
    private static let otherCity = "San Jose"

    // MARK: - Harness

    private func launch(fix: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment[Self.locationKey] = fix
        app.launch()
        return app
    }

    /// Gets to one of the Journal's segments the way a person does — `AlmanacGroupTapTests
    /// .reachAlmanac`'s route, generalized to either stats segment.
    ///
    /// Waits on screen 01's pins first for that method's reason: the tab bar is reachable before the
    /// store has finished opening, and a tap that lands early lands on a screen still assembling.
    /// **`throughPins` is off for exactly one caller and the reason is geography, not flakiness.**
    /// Screen 01 opens on the reader's fix, and this file's out-of-range case pins that fix in
    /// Sacramento — where the record has no trees, so waiting for a pin waits forever for a correct
    /// screen. The wait's real job (do not tap a tab bar that is up before the store has opened) is
    /// done for that caller by the 30-second wait on `content` at the bottom of this method.
    private func reachSegment(
        _ app: XCUIApplication,
        named segment: String,
        waitingFor content: XCUIElement,
        throughPins: Bool = true
    ) {
        if throughPins {
            XCTAssertTrue(
                wait(timeout: 30, for: { self.cityTreePins(app) > 0 }),
                "screen 01 drew no tree pins in thirty seconds, which it does with a fix and without one"
            )
        }

        app.buttons["Journal"].tap()
        let control = app.buttons[segment]
        XCTAssertTrue(
            control.waitForExistence(timeout: 20),
            "the Journal tab draws no “\(segment)” segment, so that screen has no entrance"
        )
        control.tap()

        _ = content.waitForExistence(timeout: 30)
    }

    /// §3's micro-label, matched by prefix — see `compositionLabel`.
    private func composition(_ app: XCUIApplication) -> XCUIElement {
        app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH %@", Self.compositionLabel))
            .firstMatch
    }

    /// `MapSearchUITests.cityTreePins`, in its own words — matched on `label` and by prefix.
    private func cityTreePins(_ app: XCUIApplication) -> Int {
        app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "City tree"))
            .count
    }

    private func wait(timeout: TimeInterval, for condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            _ = XCTWaiter.wait(for: [XCTestExpectation(description: "poll")], timeout: 0.25)
        }
        return condition()
    }

    /// A PNG per state, plus the same image on the result bundle —
    /// `AlmanacGroupTapTests.record(_:named:note:)`, verbatim in intent.
    private func record(_ app: XCUIApplication, named name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let directory = ProcessInfo.processInfo.environment["CYPRESS_SHOT_DIR"] ?? NSTemporaryDirectory()
        let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
        try? shot.pngRepresentation.write(to: url)
        print("CYPRESS-SHOT: \(url.path)")
    }
}
