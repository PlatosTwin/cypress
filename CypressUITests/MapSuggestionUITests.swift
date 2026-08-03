import XCTest

/// **The dropdown, driven the way a person drives it** (task #109, ruling R25).
///
/// `CypressTests/MapSuggestionTests` proves the list holds the right species and that its remainder
/// sentence never prints a total nobody counted. It cannot prove any of that reaches a finger or a
/// VoiceOver reader, because SwiftUI builds no in-process accessibility tree (ARCHITECTURE §7, E116):
/// only a launched app can be asked what it actually exposes. That is this file's whole job, and
/// there are three specific things here that a green unit suite would say nothing about:
///
///   1. **the rows are in the tree, as buttons, right after the field** — a suggestion list under a
///      text field is a classic accessibility trap, where the rows are drawn, are visible, are
///      hittable with a finger, and are somewhere a swipe never reaches;
///   2. **a row can be touched** — `isHittable` has reported true on this project for a control under
///      a `.clipped()` that answered nobody, and a card floating over an `MKMapView` is exactly that
///      shape of hazard;
///   3. **choosing one changes the field**, which is the sentence the ticket was written as.
///
/// ── The rule this file inherits from `MapSearchUITests` (tasks #101, #104) ───────────────────────
/// **A test states its own preconditions or it does not have any.** That file was red on one machine
/// and green on the next because it assumed the opening viewport held London Planes, which depends on
/// wherever `xcrun simctl location` last left the device. Nothing here depends on the viewport at
/// all: the *catalog* is bundled with the app and is the same 577 rows on every machine, so a query
/// typed into the field resolves to the same suggestions regardless of where the map is pointed. The
/// queries below are chosen for that property — they are claims about the seed's species list, never
/// about what is on screen.
final class MapSuggestionUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        return app
    }

    private func field(_ app: XCUIApplication) -> XCUIElement {
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 20), "the map's search field never appeared")
        return field
    }

    /// The bundled catalog holds six species whose name contains `cypress` and the genus ranks
    /// first (E165, and `SpeciesSearchTests` pins it). Every assertion below rests on the seed rather
    /// than on the viewport, which is what makes this file machine-independent.
    private static let query = "cypress"

    /// The common name of a species the catalog certainly holds for that query.
    private static let expectedName = "Monterey Cypress"

    /// **The scientific name is deliberately not written down, and the first draft of this file
    /// wrote it down.** It said `Monterey Cypress, Hesperocyparis macrocarpa`, copied out of
    /// `SCREENS.md` 02 — and the seed spells that species `Cupressus macrocarpa`, so three tests here
    /// went red reporting `typing “cypress” drew no suggestions`, which is a sentence about the
    /// dropdown being broken and was in fact a sentence about the mock. The same class of mistake as
    /// tasks #101 and #104: a test asserting something it had assumed rather than asked.
    ///
    /// What the row actually has to prove is *structural* — one element, the common name, a comma,
    /// and a second name after it — and that is provable without knowing which second name. So this
    /// matches a prefix and then asserts there is something behind it.
    private static var rowPrefix: String { expectedName + ", " }

    private func suggestionRow(_ app: XCUIApplication) -> XCUIElement {
        app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", Self.rowPrefix))
            .firstMatch
    }

    /// Polls. The bar debounces and then reads a 95 MB attached database; what is worth asserting is
    /// where the screen settles, never when.
    @discardableResult
    private func wait(timeout: TimeInterval = 20, for condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            usleep(200_000)
        }
        return condition()
    }

    /// A suggestion row, as the accessibility tree exposes it: one element, both names, a button.
    ///
    /// **Both names in one label is the assertion, not an implementation detail.** The owner asked for
    /// "species (as you type)" with the common and the scientific name, and a row that exposed two
    /// separate elements would make a VoiceOver reader swipe twice for one species and hear the latin
    /// name as an orphan. `MapSuggestionCopy.rowLabel` is the string; this is the proof it is on a
    /// real element.
    func testTypingDropsRowsCarryingBothNames() {
        let app = launch()
        let field = field(app)

        let row = suggestionRow(app)
        XCTAssertFalse(row.exists, "a suggestion is drawn before anything has been typed")

        field.tap()
        field.typeText(Self.query)

        XCTAssertTrue(
            row.waitForExistence(timeout: 20),
            "typing “\(Self.query)” drew no row beginning “\(Self.rowPrefix)”"
        )
        // The comma is matched by the prefix; this is the half after it. A row that announced only
        // the common name would satisfy an equality against the common name and would be exactly the
        // defect the owner's request is about — they asked for both names.
        let latin = String(row.label.dropFirst(Self.rowPrefix.count))
        XCTAssertFalse(
            latin.trimmingCharacters(in: .whitespaces).isEmpty,
            "the suggestion row announces “\(row.label)” — a common name and nothing behind the comma"
        )
        XCTAssertTrue(
            row.isHittable,
            "the suggestion row is in the accessibility tree but nothing can touch it"
        )
        // The row is the target, not the words in it (ARCHITECTURE §6's 44 pt minimum). Two serif
        // lines with the card's padding clear it comfortably; measured because "comfortably" is the
        // kind of claim that stops being true when somebody tightens a padding token.
        XCTAssertGreaterThanOrEqual(
            row.frame.height, 44,
            "a suggestion row is \(row.frame.height) pt tall"
        )
    }

    /// **Choosing a row selects the species rather than leaving the typed string in place.**
    ///
    /// The ticket's own sentence, and the one assertion a wiring mistake fails: the tap has to reach
    /// the button *through* a card floating over an `MKMapView`, and the field has to end up holding
    /// the chosen name rather than the six letters that were typed.
    func testChoosingARowPutsThatSpeciesInTheField() {
        let app = launch()
        let field = field(app)

        field.tap()
        field.typeText(Self.query)

        let row = suggestionRow(app)
        XCTAssertTrue(row.waitForExistence(timeout: 20), "typing “\(Self.query)” drew no suggestions")
        row.tap()

        XCTAssertTrue(
            wait { (field.value as? String) == Self.expectedName },
            "after choosing a suggestion the field holds “\(field.value as? String ?? "")”"
        )
        // And the list closes over its own answer, rather than sitting on the map the choice was made
        // to reveal.
        XCTAssertTrue(wait { !row.exists }, "the suggestion list stayed open after a row was chosen")
    }

    /// **E38 on the screen.** One letter matches a full page of the catalog — `a` contains-matches
    /// 555 of 577 species since task #108 — so the six rows on offer are six of *at least* a hundred,
    /// and the list must say so in words a reader and an assistive technology both get.
    ///
    /// This is the assertion the ticket named as the single most likely way to get the work wrong,
    /// made against the running app rather than against a value.
    func testAPageOfMatchesSaysItIsAPage() {
        let app = launch()
        let field = field(app)

        field.tap()
        field.typeText("a")

        let sentence = app.staticTexts[
            "Showing 6 of at least 100 matching species. Keep typing to narrow it."
        ]
        XCTAssertTrue(
            sentence.waitForExistence(timeout: 20),
            "a query matching a full page of the catalog drew six rows and said nothing about the "
                + "other ninety-four"
        )
    }

    /// **The list must not put the filter chips under a card while leaving them reachable.**
    ///
    /// This is the failure `DeepLinkVoiceOverTests.testAModalIsolatesTheScreenBehindIt` exists for,
    /// arriving through a different door: a dropdown drawn as an overlay covers the chips for anyone
    /// who can see and leaves them in the swipe order for anyone who cannot. R25 put the list in the
    /// flow instead, so the chips move down and stay both visible and hittable — which is a property
    /// worth asserting, because "fix it by hiding the chips" is the obvious repair and it is wrong.
    func testTheChipsUnderTheListAreNotCoveredButReachable() {
        let app = launch()
        let field = field(app)

        // `Yours`: the first chip in the row, on the glass without scrolling on every phone —
        // since #166 the row is one horizontally scrolling line, and this test only needs a chip
        // with a frame to watch move.
        let chip = app.buttons["Yours"]
        XCTAssertTrue(chip.waitForExistence(timeout: 20), "screen 01 drew no filter chips")
        let before = chip.frame.minY

        field.tap()
        field.typeText(Self.query)
        XCTAssertTrue(
            suggestionRow(app).waitForExistence(timeout: 20),
            "typing “\(Self.query)” drew no suggestions"
        )

        // The chips moved down rather than being covered, which is the whole difference between a
        // list in the flow and a list on top of one.
        XCTAssertTrue(
            wait { chip.frame.minY > before },
            "the suggestion list did not push the filter chips down, so it is drawn over them"
        )
        XCTAssertTrue(
            chip.isHittable,
            "a filter chip under the suggestion list is in the tree but cannot be activated"
        )
    }

    /// **The dropdown belongs to the act of typing.** R16 gave the bar a `Done` above the keyboard so
    /// a reader could get back to the map; a list still floating over that map afterwards would be
    /// the same complaint one layer up.
    func testLeavingTheKeyboardClosesTheList() {
        let app = launch()
        let field = field(app)

        field.tap()
        field.typeText(Self.query)

        let row = suggestionRow(app)
        XCTAssertTrue(row.waitForExistence(timeout: 20), "typing “\(Self.query)” drew no suggestions")

        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10), "there is no drawn way out of the keyboard")
        done.tap()

        XCTAssertTrue(
            wait(timeout: 10) { !row.exists },
            "leaving the keyboard left the suggestion list over the map"
        )
        // …and it did not throw the query away on the way out. The map is still narrowed; only the
        // list that was offering to change the query is gone.
        XCTAssertEqual(
            field.value as? String, Self.query,
            "dismissing the keyboard changed the query"
        )
    }
}
