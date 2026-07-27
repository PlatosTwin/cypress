import XCTest

/// **The search bar, driven the way a person drives it.**
///
/// `CypressTests/MapSearchTests` proves the *query* is right — that the set the map draws equals the
/// set the seed holds — by reading the database back. It cannot prove the search bar is connected to
/// any of it, because it never touches one: it builds a `MapViewport` and hands it to the API. This
/// launches the real app, taps the real field, types a real species name, and watches the map change.
///
/// That distinction is the whole defect being fixed. C20 was a `@Binding` to a `String` with two
/// references in the repository — its declaration and its binding — and every unit test in the suite
/// passed while typing into it did nothing at all. A test that constructs its own viewport would have
/// gone on passing.
///
/// Black-box, like the rest of `CypressUITests`: it imports nothing from `Cypress` and knows the app
/// only as a tree of labelled elements.
final class MapSearchUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Screen 01's pins, as the accessibility tree exposes them. `MapPin.Kind.accessibilityLabel`
    /// is the catalogue; a city tree is the overwhelming majority of the seed and the only kind the
    /// Mission fixture reliably draws.
    ///
    /// **A prefix, not an equality, and the difference is a real defect this test caught.** Task #80
    /// gives a city tree whose species holds one of the four viewport colour slots the label
    /// `City tree, London Plane` — the third channel of the species grouping, and the only one a
    /// reader with the screen off gets. Narrowing the search to one species makes *every* visible pin
    /// that species, so it wins slot A and every label gains its name: an exact match on
    /// `"City tree"` counted zero pins and this test read that as "narrowing emptied the map".
    ///
    /// What the helper is a proxy for is "how many tree pins are drawn", so it matches the vocabulary
    /// rather than one word of it. Still black-box — a predicate over labels is not a reach into the
    /// app's types.
    ///
    /// **`label`, not `identifier`.** `matching(identifier:)` falls back to the accessibility label for
    /// an element that sets no identifier, and screen 01's pins set none — so the obvious translation of
    /// this helper into `NSPredicate(format: "identifier BEGINSWITH …")` matches **nothing**, and the
    /// two tests below then skip on "the map drew no individual pins" and report themselves green
    /// without having checked anything. Matching `label` is what the original was doing all along.
    private func cityTreePins(_ app: XCUIApplication) -> Int {
        app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "City tree"))
            .count
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        return app
    }

    /// Requires a simulated fix over San Francisco, and **skips** rather than fails without one.
    ///
    /// Screen 01 opens on the user when it has a fix and on the whole city when it does not, and the
    /// whole city is zoom ≤ 15, which is A1's clustered side: badges, not individual pins. So a
    /// narrowing that is plainly visible with a fix has nothing to be visible *on* without one, and
    /// these two tests would fail for a reason that is nothing to do with the search bar.
    ///
    /// `AlmanacGroupTapTests` already carries this dependency and reports it as two red tests on any
    /// machine that has not run `xcrun simctl location <udid> set 37.78,-122.42`. Skipping is the
    /// honest form: a skip says "not checked here", which is true, where a failure says "broken",
    /// which is not. Run with a fix — as the live verification for ERRATA E134 did — and they check
    /// the thing they were written for.
    private func requireAMapWithPins(_ app: XCUIApplication) throws {
        guard wait(timeout: 25, for: { self.cityTreePins(app) > 0 }) else {
            throw XCTSkip(
                "the map drew no individual pins at launch — this needs a simulated GPS fix over "
                    + "San Francisco: xcrun simctl location <udid> set 37.78485,-122.4215"
            )
        }
    }

    /// Waits for a condition, polling. The map debounces the camera and the search independently and
    /// then reads a 195,309-row database; what is worth asserting is where it settles, never when.
    @discardableResult
    private func wait(
        timeout: TimeInterval = 30,
        for condition: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            usleep(200_000)
        }
        return condition()
    }

    /// Type a species name; watch the map narrow. Clear it; watch it come back.
    func testTypingASpeciesNameNarrowsTheMap() throws {
        let app = launch()

        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 20), "the map's search field never appeared")

        // The map has to have drawn something before narrowing it means anything.
        try requireAMapWithPins(app)
        let before = cityTreePins(app)

        field.tap()
        // The scientific name of the London Plane, prefix-matched — the commonest tree in the city.
        field.typeText("Platanus")

        XCTAssertTrue(
            wait { self.cityTreePins(app) != before },
            "typing a real species name into the search bar changed nothing on the map (it drew \(before) pins before and after)"
        )
        // **Wait for the narrowed map to settle, not merely to change.** The wait above returns on
        // the first count that differs from `before`, and the annotation layer passes through zero on
        // its way from the unnarrowed set to the narrowed one — it removes the old pins, then adds
        // the new ones, and the accessibility tree is readable in between. Reading `narrowed`
        // straight after the change therefore sampled a redraw in progress, and this test failed
        // intermittently on **both** corpora for that reason: it passed and then failed on the same
        // 145,837-row city seed forty minutes apart, and failed on a DataSF seed built before any of
        // #91 existed.
        //
        // This does not weaken the assertion below. A narrowing that genuinely empties the map never
        // satisfies this wait, so it fails here after the timeout and then fails the same assertion,
        // with the same meaning — what is gone is the sampling race, not the check.
        let settled = wait { self.cityTreePins(app) > 0 }
        let narrowed = cityTreePins(app)
        XCTAssertTrue(settled, "narrowing to the commonest species in San Francisco emptied the map")
        XCTAssertGreaterThan(narrowed, 0, "narrowing to the commonest species in San Francisco emptied the map")

        // Clearing it puts the neighbourhood back. `typeText` cannot delete, so the field is cleared
        // one keystroke at a time — there is no clear button in C20 and SCREENS.md draws none.
        for _ in 0..<"Platanus".count {
            field.typeText(XCUIKeyboardKey.delete.rawValue)
        }
        XCTAssertTrue(
            wait { self.cityTreePins(app) == before },
            "clearing the search left the map narrowed (\(self.cityTreePins(app)) pins, expected \(before))"
        )
    }

    /// A word no species matches empties the map **and says so**. An empty map with no explanation is
    /// indistinguishable from a broken one, which is the reason `MapSearchCopy` exists.
    func testAWordNoSpeciesMatchesSaysSo() throws {
        let app = launch()

        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 20), "the map's search field never appeared")
        try requireAMapWithPins(app)

        field.tap()
        field.typeText("zzzznotatree")

        // Both halves, and the wait covers both — the status line is set the moment the query
        // resolves, which is *before* the refetch that empties the map lands. Asserting the pin count
        // as soon as the message appears reads the previous answer and fails on a race of the test's
        // own making.
        let message = app.staticTexts["No species matches “zzzznotatree”"]
        XCTAssertTrue(
            wait { message.exists && self.cityTreePins(app) == 0 },
            "a search matching no species left \(cityTreePins(app)) pins drawn, or drew no explanation for the empty map"
        )
        XCTAssertTrue(message.exists, "the map went empty with nothing on screen saying why")
        XCTAssertEqual(cityTreePins(app), 0, "a search matching no species still drew trees")
    }

    /// C20 must stay a real text field in the accessibility tree, and it must not promise what it
    /// cannot do.
    ///
    /// The first half is `AccessibilityTreeTests`' rule and this change had every opportunity to
    /// break it — the obvious way to build a search results surface is a button that opens a sheet.
    /// The second half is new: the placeholder read `Species, street, or neighborhood…` while the bar
    /// was inert, and only species is implemented. See `SearchBar` for why the other two are the
    /// ingest pipeline's work rather than a missing `if`.
    func testTheFieldIsAFieldAndPromisesOnlyWhatItDoes() {
        let app = launch()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 20), "C20 is no longer a text field in the accessibility tree")
        XCTAssertEqual(field.label, "Search", "C20's accessibility label changed; VoiceOver ordering tests depend on it")

        let placeholder = field.placeholderValue ?? ""
        XCTAssertFalse(
            placeholder.lowercased().contains("street") || placeholder.lowercased().contains("neighborhood"),
            "the search bar still offers street and neighborhood search, which it cannot do: “\(placeholder)”"
        )
        XCTAssertTrue(
            placeholder.lowercased().contains("species"),
            "the search bar no longer says what it does search: “\(placeholder)”"
        )
    }
}
