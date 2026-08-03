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
///
/// ── One rule this file learnt the hard way (tasks #101 and #104) ─────────────────────────────────
/// **A test here states its own preconditions or it does not have any.** Both defects it was sent to
/// fix were the same mistake wearing different clothes: a test depending on ambient machine state it
/// never named. One asserted that searching `Platanus` leaves pins drawn, which is true or false
/// depending on where `xcrun simctl location` last left the device — so it was red for one agent and
/// green for the next, on the same commit, and got filed as "intermittent". The other guarded that
/// with a skip whose stated condition — a fixless map opening on the clustered whole city — screen 01
/// cannot produce, so the guard never fired and the dependency stayed invisible.
///
/// What replaced both is a query: the pins name their own species (`MapSpeciesPalette`), so the tests
/// read what this viewport is holding and search for *that*. Nothing below hardcodes a species, a
/// coordinate, or an assumption about where the map opens — which also means task #115 can move the
/// opening camera without moving this file.
final class MapSearchUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// The slack allowed when a measured hit area is compared against the 44 pt minimum.
    ///
    /// A thousandth of a point. It exists to absorb the last bit of a float that came through the
    /// layout engine, and nothing else — see the assertions in
    /// `testTheClearControlAppearsOnlyWithTextAndCanBeTapped`, which are the only readers and carry
    /// the reasoning. Nothing in this app's spacing tokens can produce a size within this of 44
    /// without being 44, so widening it would start hiding real defects rather than float noise.
    private static let hitTargetTolerance: CGFloat = 0.001

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
            .matching(NSPredicate(format: "label BEGINSWITH %@", Self.pinPrefix))
            .count
    }

    /// `MapPin.Kind.cityTree`'s own word, and the first thing every tree pin's label says.
    private static let pinPrefix = "City tree"

    /// What a pin says once the map has coloured it **and** read back the species' name:
    /// `City tree, Sycamore, London Plane`. That name — the commonest tree in the city — contains a
    /// comma of its own, so what follows this prefix is taken whole rather than split on anything.
    private static let namedPinPrefix = "City tree, "

    /// What the same pin says in the window between the colour landing and the name arriving:
    /// `City tree, marked dot` (`MapPin.Kind.cityTreeSpecies`). That is a *slot*, not a species, and
    /// a helper that read it as one would spend this file's whole argument searching for
    /// “marked dot”.
    private static let unnamedSlotPrefix = "City tree, marked "

    /// `MapSpeciesSlot`'s four colours, which is the most species the map can name at once.
    private static let slotCount = 4

    /// Which species the map is naming on its pins right now, most pins first — the viewport's own
    /// answer to "what is actually drawn here".
    ///
    /// **This is the question task #104 never asked.** The map colours the commonest few species
    /// among the pins it has drawn and puts their names on those pins' labels
    /// (`MapSpeciesPalette`, `MapPinKind.accessibilityLabel(for:palette:)`). So the pins say what
    /// this viewport holds, and a black-box test can read it instead of assuming it. Assuming it —
    /// "Platanus, the commonest tree in the city" — is precisely what turned a deterministic failure
    /// into a mystery.
    ///
    /// **By exclusion, not by enumeration.** A screenful of San Francisco is up to 288 pins and
    /// reading a label off each is one query resolution each. At most four species are ever named at
    /// once, so this asks a few times over for "a named pin that is none of the ones already found"
    /// and then counts each name — a dozen resolutions rather than three hundred.
    private func namedSpecies(_ app: XCUIApplication) -> [(name: String, pins: Int)] {
        var names: [String] = []
        // One turn more than there are slots, so the loop ends by finding nothing rather than by
        // running out of turns: if a fifth slot is ever added this reads it instead of silently
        // reporting the first four as the whole truth.
        while names.count <= Self.slotCount {
            var format = "label BEGINSWITH %@ AND NOT label BEGINSWITH %@"
            var arguments: [Any] = [Self.namedPinPrefix, Self.unnamedSlotPrefix]
            for found in names {
                format += " AND NOT label == %@"
                arguments.append(Self.namedPinPrefix + found)
            }
            let pin = app.buttons
                .matching(NSPredicate(format: format, argumentArray: arguments))
                .firstMatch
            guard pin.exists else { break }
            let label = pin.label
            guard label.hasPrefix(Self.namedPinPrefix) else { break }
            names.append(String(label.dropFirst(Self.namedPinPrefix.count)))
        }
        return names
            .map { (name: $0, pins: pinsNamed($0, app)) }
            .sorted { $0.pins == $1.pins ? $0.name < $1.name : $0.pins > $1.pins }
    }

    /// How many pins the map is drawing for one named species.
    private func pinsNamed(_ name: String, _ app: XCUIApplication) -> Int {
        app.buttons
            .matching(NSPredicate(format: "label == %@", Self.namedPinPrefix + name))
            .count
    }

    /// The census, for a message. A failure that names what the map was actually showing is a
    /// failure somebody can act on without re-running it.
    private static func census(_ named: [(name: String, pins: Int)]) -> String {
        named.isEmpty
            ? "no species at all"
            : named.map { "\($0.name) (\($0.pins) pins)" }.joined(separator: ", ")
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        return app
    }

    /// Requires a map with individual pins on it, and **skips** rather than fails without one —
    /// which is the honest report for a test that has nothing to empty.
    ///
    /// ── What this guard used to claim, and why it was never true (task #101) ─────────────────────
    /// It was written as a *GPS-fix detector*: "screen 01 opens on the user when it has a fix and on
    /// the whole city when it does not, and the whole city is zoom ≤ 15, which is A1's clustered
    /// side: badges, not individual pins." Every clause after the first is wrong. Screen 01 opens at
    /// `MapLayout.defaultSpanMetres` — 120 m across — with a fix and without one; only the *centre*
    /// differs, and the fixless centre is `MapLayout.defaultCentre`, Mission Dolores Park. 120 m is
    /// far inside A1's pin threshold, so the clustered city this guard was watching for is a state
    /// launch cannot produce. `AlmanacGroupTapTests` had already measured and written this down —
    /// "measured with location revoked outright for this app, the map opens on Dolores Park and
    /// draws pins there anyway" — against this file, by name.
    ///
    /// So the guard could not fire for the reason it gave, and in practice did not fire at all: the
    /// two tests it stood in front of ran on every machine regardless of any fix, and one of them
    /// then failed for a reason the guard had just certified was absent (see
    /// `requireTwoSpeciesTheMapIsNaming`). A guard that cannot fire is the same defect as a test
    /// that cannot fail, and this file has already retired one of those.
    ///
    /// ── What it guards now ───────────────────────────────────────────────────────────────────────
    /// The one thing `testAWordNoSpeciesMatchesSaysSo` actually needs, stated as itself: pins to
    /// watch go away. A viewport genuinely holding none of them — the seed is the *street* tree
    /// list, and Dolores Park at 120 m holds exactly zero of it — leaves that test asserting that
    /// nothing became nothing. It can still check the other half, which is why this skips loudly
    /// instead of passing quietly.
    private func requireAMapWithPins(_ app: XCUIApplication) throws {
        guard wait(timeout: 25, for: { self.cityTreePins(app) > 0 }) else {
            throw XCTSkip(
                "the map is drawing no individual tree pins, so there is nothing here for a search "
                    + "to empty. The seed is the street-tree inventory and the map opens 120 m "
                    + "across, so a viewport over a park or the ocean legitimately holds none. Put "
                    + "it over some streets: xcrun simctl location <udid> set 37.78485,-122.4215 "
                    + "(and note that `simctl location clear` does not unfix a device — revoke the "
                    + "app's location grant to do that)"
            )
        }
    }

    /// Two species **this viewport is actually holding**: one to search for, one to watch disappear.
    ///
    /// ── Why the narrowing test needed a different guard (task #104) ──────────────────────────────
    /// `requireAMapWithPins` asks "did the map draw any pins". The test below then typed `Platanus`
    /// and asserted the map was not empty. Those are claims about two different sets, and the gap
    /// between them is the entire defect. Measured on this branch: with the fix at
    /// `37.7505,-122.4950` — Sunset Blvd at 37th — the seed holds 264 trees inside the opening
    /// viewport and **not one** of them is a London Plane, so the guard sailed through on 95
    /// Monterey Cypresses and the assertion failed on `narrowing … emptied the map`. Move the fix to
    /// `37.78485,-122.4215` and the same box holds 47 planes, and the same binary passes. Minutes
    /// apart, no code change between.
    ///
    /// So #104's "intermittent and unexplained" was neither. It was deterministic in whatever
    /// `xcrun simctl location` the machine had last been left at — which no code in this file read,
    /// no failure message mentioned, and every agent had set differently.
    ///
    /// **The repair is not a better coordinate.** A coordinate that happens to hold London Planes
    /// today is the same bug with a longer fuse, and where screen 01 opens is itself being changed
    /// underneath this file (task #115). So the test stops assuming what is in the viewport and asks
    /// it. `namedSpecies` is the asking, and it is black-box: the pins say their own species.
    ///
    /// **Two species, not one**, because "narrows" is a claim about something *going away*. The one
    /// that is typed is watched surviving; the other is watched disappearing. A single species could
    /// only show that pins are still drawn afterwards, which a search bar wired to nothing also
    /// manages — and that was C20's original defect.
    ///
    /// The second must not be a substring relative of the first in either direction: species
    /// matching has been `LIKE '%query%'` over both names since E165, so typing `Plum` would keep
    /// `Cherry Plum` on the map and the disappearance asserted below would be a false alarm.
    private func requireTwoSpeciesTheMapIsNaming(
        _ app: XCUIApplication
    ) throws -> (searched: String, other: String) {
        _ = wait(timeout: 25) { self.namedSpecies(app).count >= 2 }
        let named = namedSpecies(app)
        guard let searched = named.first,
              let other = named.dropFirst().first(where: { !Self.overlap($0.name, searched.name) })
        else {
            throw XCTSkip(
                "screen 01 is naming \(Self.census(named)) on its pins, and this needs two species "
                    + "that are not each other's substring — one to search for, one to watch "
                    + "disappear. The map colours a species only where it has drawn at least two of "
                    + "its pins (MapSpeciesPalette.minimumPinsForASlot), so an empty or "
                    + "one-species viewport has nothing here to narrow. A mixed one: xcrun simctl "
                    + "location <udid> set 37.78485,-122.4215"
            )
        }
        return (searched.name, other.name)
    }

    /// Whether one species' name contains the other's, which is what would make a search for one of
    /// them also match the other. Case-insensitive, because the query is.
    private static func overlap(_ one: String, _ other: String) -> Bool {
        let first = one.lowercased(), second = other.lowercased()
        return first.contains(second) || second.contains(first)
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

    /// Type the name of a species **this viewport is holding**; watch the map narrow to it and the
    /// others go. Clear it; watch the neighbourhood come back.
    ///
    /// The species is not written down here on purpose. It used to be `Platanus`, on the true but
    /// irrelevant grounds that the London Plane is the commonest tree in San Francisco; what the
    /// test needed was a species commonest *on this screen*, and the two differ over most of the
    /// city. See `requireTwoSpeciesTheMapIsNaming` for the whole of task #104.
    func testTypingASpeciesNameNarrowsTheMap() throws {
        let app = launch()

        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 20), "the map's search field never appeared")

        // What this map is holding, asked rather than assumed.
        let (searched, other) = try requireTwoSpeciesTheMapIsNaming(app)
        let before = cityTreePins(app)
        let searchedBefore = pinsNamed(searched, app)
        let otherBefore = pinsNamed(other, app)

        field.tap()
        field.typeText(searched)

        // **What went into the field, not what was aimed at it.** Species names in this seed carry
        // apostrophes — `Indian Laurel Fig Tree 'Green Gem'` is 45 trees deep at the map's own
        // opening centre — and iOS smart punctuation rewrites a typed `'` into `’`, which matches no
        // row in the catalogue. A test that skipped this check would report the substitution as
        // "narrowing emptied the map": the exact misdiagnosis this whole change is about, arriving
        // by a different door. Checked rather than avoided, so awkward names stay covered.
        XCTAssertEqual(
            field.value as? String, searched,
            "the field holds “\(field.value as? String ?? "")” after typing “\(searched)”, so what "
                + "the map was asked for is not what this test asked for"
        )

        // Both halves under one wait, for `testAWordNoSpeciesMatchesSaysSo`'s reason: they are two
        // reads of one settling map, and asserting either the instant it comes true races the other.
        _ = wait { self.pinsNamed(other, app) == 0 && self.pinsNamed(searched, app) > 0 }

        // It narrowed. The other species had pins on this screen a moment ago and the query does
        // not match it, so every one of them must be gone — the half a search bar wired to nothing
        // (C20, as it shipped) cannot fake.
        XCTAssertEqual(
            pinsNamed(other, app), 0,
            "typing “\(searched)” left \(pinsNamed(other, app)) of \(other)'s \(otherBefore) pins on "
                + "the map, so the map is not narrowed to what was typed"
        )
        // **And it narrowed to something.** This is task #104's assertion, now made about a species
        // the map itself said was here rather than about one this file hoped would be.
        XCTAssertGreaterThan(
            pinsNamed(searched, app), 0,
            "narrowing to \(searched) — which this very viewport was drawing \(searchedBefore) pins "
                + "of a moment ago — emptied the map of it"
        )
        let narrowed = cityTreePins(app)
        XCTAssertGreaterThan(
            narrowed, 0,
            "narrowing to \(searched), which is in view, left no tree pins drawn at all"
        )
        // A narrowing cannot *add* trees: the pins drawn for a subset of the species come from a
        // subset of the 44 pt cells the whole set filled (`MapModel.markerCellPoints`). A count that
        // went up would mean the map is answering some other question than the one typed.
        XCTAssertLessThanOrEqual(
            narrowed, before,
            "narrowing to \(searched) drew \(narrowed) pins where the unnarrowed map drew \(before)"
        )

        // Clearing it puts the neighbourhood back — through the ✕ the bar now draws (task #110,
        // ruling R16), which is also the only way a person without a hardware keyboard could do it.
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
        //
        // **Compared with a tolerance, and that is the point of the tolerance rather than a
        // softening of the assertion.** `.cypressTapTarget()` sets `minWidth`/`minHeight` to
        // `CypressSpacing.minTapTarget`, which is exactly 44, so this control's measured size lands
        // *on* the constant it is being compared against rather than above it — 44.0 × 44.0 at
        // (376, 70) on a 440 pt iPhone 16 Pro Max, measured before this line was written. A value
        // that has come through the layout engine and across the accessibility boundary carries
        // float noise (the suggestion row in `MapSuggestionUITests` measures 78.33333333333331 pt
        // on the same device), and an exact `>=` against the number it is supposed to equal is
        // decided by the last bit: this assertion read 43.99999999999999 once. The tolerance is a
        // thousandth of a point — some eleven orders of magnitude above that noise and three below
        // anything this layout can express, so a control that is genuinely short still fails here.
        // Sub-44 is a real accessibility defect and must stay red; one ulp is not a defect at all.
        XCTAssertGreaterThanOrEqual(
            clear.frame.width, 44 - Self.hitTargetTolerance,
            "the clear control's hit area is \(clear.frame.width) pt wide"
        )
        XCTAssertGreaterThanOrEqual(
            clear.frame.height, 44 - Self.hitTargetTolerance,
            "the clear control's hit area is \(clear.frame.height) pt tall"
        )

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
