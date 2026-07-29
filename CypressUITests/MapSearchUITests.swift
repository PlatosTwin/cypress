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
    ///
    /// ── This guard is the wrong guard for `testTypingASpeciesNameNarrowsTheMap` (task #104) ──────
    /// **Not fixed here** — recorded because it was reproduced rather than theorised. This asks "did
    /// the map draw any pins", and the test below needs "does this viewport hold any *London
    /// Planes*". Those come apart, and by a lot: with the fix at `37.7505,-122.4950` — Sunset Blvd
    /// at 37th, a screenful of Monterey Cypress and Monterey Pine — the seed holds **0** London
    /// Planes in view and `testTypingASpeciesNameNarrowsTheMap` fails on
    /// `narrowing … emptied the map`, having sailed through this guard on forty-odd pins of the
    /// wrong species. Move the fix to `37.78485,-122.4215` and the same box holds **488**, and it
    /// passes. Both runs are on this branch, minutes apart, with no code change between them.
    ///
    /// So #104's "intermittent and unexplained" is neither: it is deterministic in the simulator's
    /// last `simctl location`, which no code in this file reads and nothing in CI pins. The fix is a
    /// second guard that skips when the *species being typed* has nothing in view — which is a
    /// change to what these tests assume, and belongs to #104 rather than to a search-matching
    /// branch.
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
        let narrowed = cityTreePins(app)
        XCTAssertGreaterThan(narrowed, 0, "narrowing to the commonest species in San Francisco emptied the map")

        // Clearing it puts the neighbourhood back — through the ✕ the bar now draws (task #110,
        // ruling R15), which is also the only way a person without a hardware keyboard could do it.
        app.buttons["Clear search"].tap()
        XCTAssertTrue(
            wait { self.cityTreePins(app) == before },
            "clearing the search left the map narrowed (\(self.cityTreePins(app)) pins, expected \(before))"
        )
    }

    /// **The keyboard has a drawn way out.** The owner: "it's possible to get stuck in the search bar
    /// — cursor active and no way to exit out of keyboard". Screen 01 has nothing behind the bar that
    /// can be tapped to dismiss it: the map is an `MKMapView`, and a tap-catcher over it would take
    /// the pan and the pinch with it. So the bar provides two, and this checks the visible one.
    func testTheKeyboardCanBeDismissed() throws {
        let app = launch()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 20), "the map's search field never appeared")

        field.tap()
        field.typeText("cy")

        // **Focus, not `app.keyboards`, is what this asserts, and the difference is not pedantry.**
        // A simulator with `Connect Hardware Keyboard` on never draws the software keyboard at all,
        // so a test written against `keyboards.count` reports "the keyboard never came up" on a
        // machine where the bar is working perfectly — a red test for a setting. The `Done` item is
        // the honest proxy: it is a keyboard toolbar, so it is in the tree exactly while a field of
        // this app's is focused, whatever the keyboard itself is doing.
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10), "there is no drawn way out of the keyboard")
        XCTAssertTrue(done.isHittable, "the way out of the keyboard is in the tree but cannot be tapped")
        done.tap()

        XCTAssertTrue(
            wait(timeout: 10) { !done.exists },
            "tapping the way out of the keyboard did not take the field out of focus"
        )
        // And it did not clear the query on the way out: leaving the keyboard is not abandoning the
        // search, and a map that un-narrowed itself here would lose what the reader just typed.
        XCTAssertEqual(field.value as? String, "cy", "dismissing the keyboard changed the query")
    }

    // **There is deliberately no test for the return key here, and that is a finding.**
    //
    // One was written — type, press return, assert the field lost focus — and it passed. It also
    // passed with `onSubmit` deleted, and then with `focused`, `submitLabel` and `onSubmit` all
    // deleted, which is `SearchBar` exactly as it shipped before task #110. So the return key was
    // never broken: SwiftUI resigns focus on submit for a single-line `TextField` by default, and
    // the test was asserting the platform's behaviour, not this app's. It could not fail, and a test
    // that cannot fail is worse than no test on a project where a green suite has ratified a real
    // defect before.
    //
    // What #110 actually changes about that key is its *label* — `Search` instead of `return` —
    // which XCUITest cannot read off the keyboard. `testTheKeyboardCanBeDismissed` covers the part
    // that is ours and can fail: the `Done` affordance.

    /// The ✕ the owner asked for: present only when there is something to clear, labelled for
    /// VoiceOver, and genuinely touchable. That last clause is not a formality — a control has
    /// reported `isHittable` true on this project while sitting under a `.clipped()` that made it
    /// untouchable, and task #100 is open on a map control that lies to VoiceOver about its state.
    func testTheClearControlAppearsOnlyWithTextAndCanBeTapped() throws {
        let app = launch()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 20), "the map's search field never appeared")

        let clear = app.buttons["Clear search"]
        XCTAssertFalse(clear.exists, "the clear control is drawn over an empty field, with nothing to clear")

        field.tap()
        field.typeText("cypress")
        XCTAssertTrue(clear.waitForExistence(timeout: 10), "typing drew no clear control")
        XCTAssertTrue(clear.isHittable, "the clear control is in the tree but nothing can touch it")

        // A 44 pt target, ARCHITECTURE §6 — measured, because the glyph is 16 pt and the enlargement
        // is the whole reason a thumb can hit it.
        XCTAssertGreaterThanOrEqual(clear.frame.width, 44, "the clear control's hit area is \(clear.frame.width) pt wide")
        XCTAssertGreaterThanOrEqual(clear.frame.height, 44, "the clear control's hit area is \(clear.frame.height) pt tall")

        clear.tap()
        XCTAssertTrue(
            wait(timeout: 10) { (field.value as? String ?? "").isEmpty || field.value as? String == field.placeholderValue },
            "tapping the clear control left “\(field.value as? String ?? "")” in the field"
        )
        XCTAssertFalse(clear.exists, "the clear control stayed on screen over an empty field")
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
