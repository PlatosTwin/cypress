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
    private func cityTreePins(_ app: XCUIApplication) -> Int {
        app.buttons.matching(identifier: "City tree").count
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        return app
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
    func testTypingASpeciesNameNarrowsTheMap() {
        let app = launch()

        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 20), "the map's search field never appeared")

        // The map has to have drawn something before narrowing it means anything.
        XCTAssertTrue(
            wait { self.cityTreePins(app) > 0 },
            "the map drew no city-tree pins at launch, so this test cannot tell narrowing from an empty map"
        )
        let before = cityTreePins(app)

        field.tap()
        // The scientific name of the London Plane, prefix-matched — the commonest tree in the city.
        field.typeText("Platanus")

        XCTAssertTrue(
            wait { self.cityTreePins(app) != before },
            "typing a real species name into the search bar changed nothing on the map (it drew \(before) pins before and after)"
        )
        let narrowed = cityTreePins(app)
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
    func testAWordNoSpeciesMatchesSaysSo() {
        let app = launch()

        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 20), "the map's search field never appeared")
        XCTAssertTrue(wait { self.cityTreePins(app) > 0 }, "the map drew nothing at launch")

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
