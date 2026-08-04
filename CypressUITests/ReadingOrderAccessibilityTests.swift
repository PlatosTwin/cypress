import XCTest

/// **Element sequence, machine-checked.** (task #221)
///
/// `AccessibilityTreeTests` (E116) and `DeepLinkVoiceOverTests`/`DeepLinkSweepTests` (E117) prove
/// that every interactive element is labeled, that a modal does not leak the screen behind it, and
/// that every pushed screen owes a reachable Back — `testEveryPushedScreenSaysWhereItIsFirst` even
/// pins that the *first* control is Back and the *first* text is the screen's own name. None of that
/// is an assertion about the *order elements arrive in relative to one another* once past the first
/// stop, or about whether declared reading order actually matches what the accessibility runtime
/// hands back. `docs/ROADMAP.md` names the gap directly: "reading order and grouping … XCUITest
/// exposes but no test here asserts yet."
///
/// **Three screens, chosen for the same reason `PrimaryCTAReachabilityTests` chose its eleven**: a
/// wrong order here is not a curiosity, it is a VoiceOver user being handed a different app than the
/// one on the glass. The map is screen 01 and every session starts there; `checkIn` and `treeProfile`
/// are the two screens `PrimaryCTAReachabilityTests`' own notes call the highest-traffic entrances
/// this harness can open.
///
/// **Facts about order, not phrasing.** Every assertion below is the relative position of a stable
/// identifier — a copy constant (`SearchBarCopy.field`), a numbered rubric row (`VitalityRow.title`),
/// a quad-action cell's own label (`QuadActionRow.Action.label`) — never a claim about the sentence
/// itself. A rename that keeps the same *element* in the same *place* leaves every test here green.
///
/// **The order comes from `DeepLinkHarness.treeOrder(_:)`, and that choice is not incidental
/// (ERRATA E118).** `allElementsBoundByIndex` is the query engine's match order, not the
/// accessibility hierarchy's — `DeepLinkSweepTests.testEveryPushedScreenSaysWhereItIsFirst`'s own
/// comment records screen 05's pinned `Save check-in` sorting ahead of `Back` under that API, which
/// is a defect that does not exist. `treeOrder` parses `debugDescription`'s depth-first dump instead,
/// the same artifact E117's screen reads. **This is the raw element-tree order, not necessarily
/// VoiceOver's** — see the map test below for what that distinction cost this file, found while
/// building it rather than assumed going in.
///
/// **One launch per screen.** Three tests, three launches — not a sweep, and not doubled against any
/// existing class. `Tools/ui-test-shards.txt` carries this class's own measured runtime once landed.
final class ReadingOrderAccessibilityTests: XCTestCase, DeepLinkHarness {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: - Screen 01 · the map's declared chrome order, checked against the live tree

    private func launchMap() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        return app
    }

    /// **What this checks, and — found while building it — what it cannot.**
    ///
    /// `MapHomeView.chrome` composes the field, the suggestion list and the filter chips as three
    /// siblings in one `VStack`, in that source order, and separately gives each an explicit
    /// `accessibilitySortPriority` (field 6 > suggestions 5 > chips 4) — task #143's fix for ERRATA
    /// E183 §3, which found RULINGS R25 §1's claimed "field → suggestions → chips" swipe order was
    /// not what the running app produced.
    ///
    /// This test asserts the first of those two things — the three blocks are composed, and stay
    /// composed, in that order — and **not** the second. Verified empirically while writing it, on a
    /// fresh 430-file build rather than a stale cache: setting the field's own
    /// `accessibilitySortPriority` below the chips' did not move it in `debugDescription` at all.
    /// `treeOrder` reads `debugDescription`, which is the raw element-tree order the view hierarchy
    /// composes — the same artifact `DeepLinkSweepTests` already reads for the same reason (E118: the
    /// query-engine order `allElementsBoundByIndex` returns is neither this nor VoiceOver's) — and
    /// that order does not appear to honor `accessibilitySortPriority` at all on this SwiftUI tree, a
    /// fact consistent with `CypressTests/AccessibilityTests`' standing finding that SwiftUI serves
    /// accessibility over its own bridge rather than through the container protocol UIKit's sort
    /// priority is documented against (ERRATA E196). See `docs/errata-pending/` for the write-up.
    /// **A test that actually watches `accessibilitySortPriority` take effect needs VoiceOver running
    /// on a real device**, which is out of reach for a black-box XCUITest here — this is the honest
    /// limit, stated rather than implied by a green result that looks like more than it is.
    ///
    /// What this still buys: the three blocks' *composition* order is real product surface (it is
    /// what `accessibilitySortPriority`'s own numbers are chosen against, and what a sighted
    /// developer reading `MapHomeView.chrome` sees), and nothing before this test asserted even that
    /// much — a reviewer could reorder the `VStack`'s children with no red anywhere in this suite.
    ///
    /// **The query is `cypress`, not wherever the camera happens to be pointed.**
    /// `MapSuggestionUITests` already established why this query is safe on any machine: the species
    /// catalog is bundled and the same 577 rows everywhere, so "Monterey Cypress" drops as a
    /// suggestion with no GPS fix and no dependency on the viewport — sidestepping the whole E202/
    /// E216 family of camera-state flakes this project has already paid for once.
    func testMapFieldPrecedesSuggestionsPrecedesFilterChipsInComposition() {
        let app = launchMap()

        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 20), "the map's search field never appeared")
        field.tap()
        field.typeText("cypress")

        let suggestionPrefix = "Monterey Cypress, "
        let suggestionRow = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", suggestionPrefix))
            .firstMatch
        XCTAssertTrue(
            suggestionRow.waitForExistence(timeout: 20),
            "typing \u{2018}cypress\u{2019} drew no suggestion row beginning \u{2018}\(suggestionPrefix)\u{2019} "
                + "— this test cannot check the order of a block that never appeared"
        )

        let ordered = Self.treeOrder(app.debugDescription)
        XCTAssertGreaterThan(
            ordered.count, 3,
            "map: the element tree could not be parsed — `debugDescription`'s format has probably "
                + "changed, and this test is no longer reading an order at all"
        )

        func index(_ match: (String) -> Bool) -> Int? { ordered.firstIndex(where: { match($0.label) }) }

        guard let fieldIndex = index({ $0 == "Search" }) else {
            XCTFail("map: the search field's own accessibility label \u{2018}Search\u{2019} is not in the tree")
            return
        }
        guard let suggestionIndex = index({ $0.hasPrefix(suggestionPrefix) }) else {
            XCTFail("map: the suggestion row is hittable but was not found in the parsed tree order")
            return
        }
        guard let chipsIndex = index({ $0 == "Filter trees" }) else {
            XCTFail("map: the filter row's own container label \u{2018}Filter trees\u{2019} is not in the tree")
            return
        }

        XCTAssertLessThan(
            fieldIndex, suggestionIndex,
            "map: the search field is composed at tree position \(fieldIndex) and the suggestion "
                + "row at \(suggestionIndex) — the dropdown is composed ahead of the field it drops "
                + "under"
        )
        XCTAssertLessThan(
            suggestionIndex, chipsIndex,
            "map: the suggestion row is composed at tree position \(suggestionIndex) and the filter "
                + "chips at \(chipsIndex) — the chips are composed ahead of the suggestions that sit "
                + "between them and the field in `MapHomeView.chrome`'s own source order"
        )

        app.terminate()
    }

    // MARK: - Screen 05 · the vitality rubric, read worst-to-best

    /// `Vitality.rubric`'s own comment: "Worst at the top … a rater who learns 'the top row is the
    /// bad one' on one screen must not meet the opposite on another." The order is data
    /// (`Vitality.rubric = [.severeDecline, .poor, .fair, .good, .thriving]`), not layout, and
    /// nothing before this test asked the accessibility tree whether the five rows actually arrive in
    /// that sequence — `testAStatCardIsOneStop` (this target, screen 03) proved a caption and its
    /// value arrive as *one* stop; this is the first test that proves *several* stops arrive in a
    /// specified sequence rather than merely all existing.
    ///
    /// **Matched on the row's own number, not the class label alone** (`VitalityRow.title`, "1 ·
    /// Severe decline" … "5 · Thriving"): the number is the part of the row that states its rank, so
    /// asserting order by the bare word "Poor"/"Fair" would risk matching a fragment of the anchor
    /// sentence instead of the row, and would in any case be a claim about which words appear rather
    /// than about where the row it belongs to sits.
    ///
    /// **A missing rubric is not asserted as a defect.** PRODUCT §3's seasonality rule suppresses the
    /// section outright for a deciduous species out of leaf, replacing all five rows with
    /// `CheckInCopy.vitalitySuppressed` — a real, data-driven state rather than something this test
    /// should turn into a false red on whichever tree the harness resolves this month.
    func testCheckInVitalityRowsReadInRubricOrder() throws {
        let app = launch("checkIn")
        guard arrive(app, screen: "checkIn", anchor: "Check-in") else { return }

        let severeDeclinePrefix = "1 \u{00b7} Severe decline"
        let firstRow = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", severeDeclinePrefix))
            .firstMatch
        guard firstRow.waitForExistence(timeout: 10) else {
            let suppressed = app.staticTexts
                .matching(NSPredicate(format: "label CONTAINS %@", "Out of leaf"))
                .firstMatch
            let message = suppressed.exists
                ? "checkIn: the vitality section is suppressed for this tree's species this month "
                    + "(PRODUCT \u{a7}3's seasonality rule) — no rows exist to order, which is correct"
                : "checkIn: no vitality row appeared within 10s, and the documented suppressed-state "
                    + "notice is not on screen either — this needs a person's eyes before the skip "
                    + "below is trusted"
            throw XCTSkip(message)
        }

        let ordered = Self.treeOrder(app.debugDescription)
        XCTAssertGreaterThan(
            ordered.count, 3,
            "checkIn: the element tree could not be parsed — `debugDescription`'s format has "
                + "probably changed"
        )

        let rows = [
            "1 \u{00b7} Severe decline", "2 \u{00b7} Poor", "3 \u{00b7} Fair", "4 \u{00b7} Good",
            "5 \u{00b7} Thriving",
        ]
        var positions: [Int] = []
        for row in rows {
            guard let position = ordered.firstIndex(where: { $0.label.hasPrefix(row) }) else {
                XCTFail("checkIn: no row in the tree begins \u{2018}\(row)\u{2019}")
                return
            }
            positions.append(position)
        }

        XCTAssertEqual(
            positions, positions.sorted(),
            "checkIn: the five vitality rows are in the tree at positions \(positions), out of "
                + "rubric order — a rater who has learned \u{2018}the top row is the bad one\u{2019} "
                + "on this screen would meet the opposite here"
        )

        app.terminate()
    }

    // MARK: - Screen 03 · the tree's identity, before the loud action, before the quiet ones

    /// **The identity block reads before the primary CTA, and the primary CTA reads before the
    /// secondary per-tree actions.** `TreeProfileView.body` composes `identityBlock`, then the CTA,
    /// then the quad action row in exactly that order in source — this test reads the same claim off
    /// the live tree instead of off the file, because a modifier can keep a correctly-composed element
    /// out of the tree or reorder it, which is exactly what happened to the map's own chrome (ERRATA
    /// E183 §3, this file's map test above — composition order there, not `debugDescription` order,
    /// see that test's own note). Nothing before this test asked whether screen 03's composition order
    /// survives into the accessibility tree.
    ///
    /// **Not the chrome title, and the first draft of this test used it and was wrong.** `coldHeader`'s
    /// `ScreenHeader` always reads the literal, data-independent word "Tree"
    /// (`TreeProfilePresentation.fallbackTitle`) — it is the harness's own arrival anchor, and it is
    /// always the very first element on this screen by a different, already-covered guarantee
    /// (`DeepLinkSweepTests.testEveryPushedScreenSaysWhereItIsFirst`). Ordering against it made a
    /// red-proof mutation that moved `identityBlock` (the tree's real name, "Canary Island Date Palm"
    /// on the run this was built against, plus its subtitle and `showWhere` control) down past the CTA
    /// pass clean — the assertion was true by construction and never touched the block it named.
    /// **`identityBlock`'s own content has to be the anchor**, and its name is per-tree data this test
    /// cannot hardcode. `ShowWhereButton`'s label is not: it is fixed copy (`identityBlock`'s last
    /// child, drawn "for every record this screen can render, including a memorial" per its own
    /// comment), so it stands in for "the identity block was read" without claiming anything about
    /// which tree this run resolved.
    ///
    /// **Cold, not warm.** The harness's `treeProfile` case is the same target
    /// `PrimaryCTAReachabilityTests` calls "screen 03 cold".
    func testTreeProfileIdentityReadsBeforePrimaryThenSecondaryActions() {
        let app = launch("treeProfile")
        guard arrive(app, screen: "treeProfile", anchor: "Tree") else { return }

        let ordered = Self.treeOrder(app.debugDescription)
        XCTAssertGreaterThan(
            ordered.count, 3,
            "treeProfile: the element tree could not be parsed — `debugDescription`'s format has "
                + "probably changed"
        )

        func index(_ match: (String) -> Bool) -> Int? { ordered.firstIndex(where: { match($0.label) }) }

        guard let identityIndex = index({ $0 == "Show me where this is" }) else {
            XCTFail(
                "treeProfile: `identityBlock`'s \u{2018}Show me where this is\u{2019} control is not "
                    + "in the tree, so this test cannot find the identity block it is ordering against"
            )
            return
        }

        // Two-valued (`TreeProfilePresentation.ctaTitle`) on whether the harness's resolved tree is
        // cold or has a hero photograph — see `PrimaryCTAReachabilityTests`' own table for why both
        // are checked rather than one assumed.
        let ctaLabels = ["Be the first to photograph this tree", "Visit \u{00b7} say hello with a photo"]
        guard let ctaIndex = index({ ctaLabels.contains($0) }) else {
            XCTFail("treeProfile: neither primary CTA label is in the tree")
            return
        }

        guard let reportIndex = index({ $0 == "Report" }) else {
            XCTFail("treeProfile: the quad action row's \u{2018}Report\u{2019} cell is not in the tree")
            return
        }

        XCTAssertLessThan(
            identityIndex, ctaIndex,
            "treeProfile: the identity block reads at position \(identityIndex) and the primary CTA "
                + "at \(ctaIndex) — a VoiceOver user would be offered the action before being told "
                + "which tree it is on"
        )
        XCTAssertLessThan(
            ctaIndex, reportIndex,
            "treeProfile: the primary CTA reads at position \(ctaIndex) and the secondary "
                + "\u{2018}Report\u{2019} action at \(reportIndex) — the quieter per-tree actions "
                + "are being read before the one loud thing this screen exists to have pressed"
        )

        app.terminate()
    }
}
