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
/// **Six screens, chosen for the same reason `PrimaryCTAReachabilityTests` chose its eleven**: a
/// wrong order here is not a curiosity, it is a VoiceOver user being handed a different app than the
/// one on the glass. The map is screen 01 and every session starts there; `checkIn` and `treeProfile`
/// are the two screens `PrimaryCTAReachabilityTests`' own notes call the highest-traffic entrances
/// this harness can open.
///
/// **The three added since (06 report, 16 measure, 09 care log) are the screens that WRITE**, which
/// is the line drawn deliberately rather than sweeping every screen the harness can open. On a
/// reading screen a wrong order costs a reader a second pass; on these three it costs them a filed
/// report under the wrong heading (06, ERRATA E131), a measurement saved as a zero or under the
/// wrong kind (16), or a care visit that records nothing (09). Each is asserted from one launch
/// with no interaction, so none of them pays for a state this suite would then have to pin.
///
/// **Screens deliberately NOT added, so the next person does not re-derive it.** 11 growth history
/// and 13 activity both resolved to a tree with no rows at all on the survey run — their order is
/// only as rich as the seed's measurements for whichever record the deep link lands on, which is a
/// test that asserts different things on different devices. 17 outbox reads a queue whose contents
/// are device state, not code. 19 memorial cannot be reached at all from this seed: it holds only
/// `alive` and `vacant_site`, and `DebugDeepLink.memorial` writes a device-side `removed` override
/// to manufacture one (ERRATA E217), which is state this suite must not order against.
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
/// **One launch per screen.** Six tests, six launches — not a sweep, and not doubled against any
/// existing class. `Tools/ui-test-shards.txt` carries this class's own measured runtime.
///
/// **`debugDescription` is composition order, and that is now measured rather than suspected.** The
/// map test below records what E230 found; the erratum filed with the coverage extension pushes it
/// further — the query engine under both binding strategies, the snapshot's own `children` arrays
/// and `.children(matching:)` walked level by level all report the same order, and a purely
/// geometric inversion (an element drawn 125 pt higher, composition untouched) moves none of them.
/// Nothing this target can call sees a computed reading order, so every assertion in this file is
/// a claim about composition and says so. `CypressTests/MapSwipeOrderDeclarationTests` guards the
/// one thing that makes those claims worth making: that screen 01's declared sort priorities
/// descend in the same order it composes.
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
    /// priority is documented against (ERRATA E196). The full write-up ships as an erratum with
    /// task #221; until it carries a number, E196 is the citable record of the in-process half.
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

    // MARK: - Reading the tree, shared by the three screens below

    /// Arrive, parse, and refuse to conclude anything from a tree that did not parse.
    ///
    /// The three tests below each read one screen's whole order, so the "did `debugDescription`'s
    /// format change" check that each of the three tests above writes inline is one function here
    /// rather than a fourth, fifth and sixth copy of it.
    private func orderedTree(
        _ app: XCUIApplication,
        screen: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> [(kind: String, label: String)]? {
        let ordered = Self.treeOrder(app.debugDescription)
        guard ordered.count > 3 else {
            XCTFail(
                "\(screen): the element tree parsed to \(ordered.count) entries — "
                    + "`debugDescription`'s format has probably changed, and this test is no longer "
                    + "reading an order at all",
                file: file, line: line
            )
            return nil
        }
        return ordered
    }

    /// The position of the first entry whose label matches, or a failure that names what is missing.
    ///
    /// **`kind` is a parameter and not a convenience.** Screen 16 draws a static `0` in its readout
    /// and a `0` key on its keypad; matching on the label alone finds the readout, which sits above
    /// the keypad, and the assertion "every digit reads before Save" would then pass on an element
    /// that is not a digit at all. `treeOrder` returns the kind beside the label precisely so a
    /// caller can say which of the two it means.
    private func position(
        of label: String,
        kind: String? = nil,
        in ordered: [(kind: String, label: String)],
        screen: String,
        role: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Int? {
        let found = ordered.firstIndex { entry in
            entry.label == label && (kind.map { $0 == entry.kind } ?? true)
        }
        if found == nil {
            XCTFail(
                "\(screen): nothing in the element tree is \(kind.map { "a \($0) " } ?? "")labeled "
                    + "\u{2018}\(label)\u{2019} (\(role)), so this test cannot order against it",
                file: file, line: line
            )
        }
        return found
    }

    // MARK: - Screen 06 · the hazard vocabulary, before the one that stays home

    /// **Two vocabularies on one screen, and only their headings tell them apart.**
    ///
    /// Screen 06 draws a safety-hazard picker whose chips reach the city's crew, and directly under
    /// it a neighborly-note picker whose chips reach nobody: ERRATA **E131** found the note chips
    /// highlight under a storage promise nothing keeps, and settled that they stay drawn, inert,
    /// exactly as SCREENS.md 06 §3 draws them. A sighted reader is told which is which by two
    /// micro-labels and by the fact that the note pills do not depress. A listener has the labels
    /// and, in the tree, the element kind — nothing else. If a chip ever crossed the boundary
    /// between the two headings, a reader would choose \u{2018}Needs water\u{2019} under
    /// \u{2018}for the city\u{2019}s crew\u{2019} and believe a hazard was filed. That is the
    /// failure this asserts against, and nothing in this suite asserted it before.
    ///
    /// **Chosen over the branch below it.** The hazard panel, the 311 CTA, the reminder and the
    /// disclosure are all gated on `ReportPresentation.showsHazardBranch` — a selection this test
    /// would have to make first, which turns one launch into an interaction sequence for a claim no
    /// stronger than this one. The two pickers are unconditional.
    ///
    /// **Facts, not phrasing.** Every anchor here is a section micro-label or a hazard/note category
    /// name — `ReportCopy.hazardSectionLabel`, `HazardCategoryLabel.text(for:)` — copied by hand
    /// because nothing in this black-box target imports `Cypress` (E116). The assertions are about
    /// which side of a heading a chip falls on; rewording a chip moves nothing.
    func testReportKeepsEachVocabularyUnderItsOwnHeading() {
        let app = launch("report")
        guard arrive(app, screen: "report", anchor: "Report an issue") else { return }
        guard waitForPushedScreenToArrive(app, screen: "report") else {
            app.terminate()
            return
        }
        guard let ordered = orderedTree(app, screen: "report") else {
            app.terminate()
            return
        }

        // `ReportCopy.hazardSectionLabel` / `.noteSectionLabel`.
        let hazardHeading = "Safety hazard \u{00b7} for the city\u{2019}s crew"
        let noteHeading = "Neighborly note \u{00b7} stays in Cypress"
        // `HazardCategoryLabel.text(for:)` over `ReportPresentation.hazardCategories`, and
        // `CommunityNoteCategoryLabel.text(for:)` over `.noteCategories`.
        let hazardChips = ["Hanging limb", "Uprooted", "Struck by vehicle", "Blocking a sightline"]
        let noteChips = ["Needs water", "Pest suspected", "Vandalism"]

        guard let hazardHeadingIndex = position(
            of: hazardHeading, in: ordered, screen: "report", role: "the hazard section's heading"
        ) else { return }
        guard let noteHeadingIndex = position(
            of: noteHeading, in: ordered, screen: "report", role: "the note section's heading"
        ) else { return }

        var hazardPositions: [Int] = []
        for chip in hazardChips {
            guard let index = position(
                of: chip, in: ordered, screen: "report", role: "a hazard category"
            ) else { return }
            hazardPositions.append(index)
        }
        var notePositions: [Int] = []
        for chip in noteChips {
            guard let index = position(
                of: chip, in: ordered, screen: "report", role: "a neighborly-note category"
            ) else { return }
            notePositions.append(index)
        }

        XCTAssertLessThan(
            hazardHeadingIndex, hazardPositions.min()!,
            "report: the hazard heading reads at \(hazardHeadingIndex) and the first hazard chip "
                + "at \(hazardPositions.min()!) — a listener meets a hazard category before being "
                + "told the section sends it to the city"
        )
        XCTAssertLessThan(
            hazardPositions.max()!, noteHeadingIndex,
            "report: a hazard chip reads at \(hazardPositions.max()!), past the neighborly-note "
                + "heading at \(noteHeadingIndex) — it has crossed into the section ERRATA E131 "
                + "established goes nowhere, where a reader would take it for a note that stays in "
                + "Cypress"
        )
        XCTAssertLessThan(
            noteHeadingIndex, notePositions.min()!,
            "report: the neighborly-note heading reads at \(noteHeadingIndex) and the first note "
                + "chip at \(notePositions.min()!) — a listener meets an inert note category while "
                + "still inside the section that reaches the city\u{2019}s crew, and would believe "
                + "a hazard had been filed (ERRATA E131)"
        )

        app.terminate()
    }

    // MARK: - Screen 16 · say what, say how, then the digits, then the save

    /// **The one screen in the app that takes a number and writes it to the record**, and its
    /// spine is an order: what are you measuring, how did you measure it, what did it say, save.
    /// Every stop is load-bearing in a way a listener cannot recover from out of sequence — the
    /// keypad is identical for a trunk diameter and a height (`MeasureCopy.kindSegment`), and
    /// `Method \u{00b7} required` is required, so a reader handed the digits before either control
    /// types a number into whichever kind and method happened to be selected, and a reader handed
    /// `Save measurement` before the keypad saves the readout's zero.
    ///
    /// **Why not the anomaly and chart-notice lines**, which `MeasureView.body`'s own comment says
    /// "sit *above* the CTA, because both are things to read before the tap rather than after it".
    /// That is the sharpest ordering claim on the screen and it is deliberately not asserted here:
    /// both are conditional on device state this suite does not pin — the chart notice appeared in
    /// the survey run only because the 16e had no location fix, and CLAUDE.md's own rule is that a
    /// result which changes with the device's fix is reporting the device. Asserting it would be a
    /// test that goes red on a healthy phone.
    ///
    /// **Unconditional anchors only.** The kind control, the method control, the keypad and the CTA
    /// are drawn for every state of this screen; the readout, the unit switch and the
    /// `Last recorded \u{2026}` line are not asserted because they carry per-tree data.
    func testMeasureAsksWhatAndHowBeforeItOffersDigitsOrSave() {
        let app = launch("measure")
        guard arrive(app, screen: "measure", anchor: "Measure") else { return }
        guard waitForPushedScreenToArrive(app, screen: "measure") else {
            app.terminate()
            return
        }
        guard let ordered = orderedTree(app, screen: "measure") else {
            app.terminate()
            return
        }

        // `MeasureCopy.kindLabel`, `.kindSegment(_:)`, `.methodLabel`, `.saveCTA`, and
        // `SegmentedControl.method`'s three options — copied by hand (E116, no `import Cypress`).
        guard let kindHeadingIndex = position(
            of: "What are you measuring?", in: ordered, screen: "measure",
            role: "the kind control's heading"
        ) else { return }
        guard let methodHeadingIndex = position(
            of: "Method \u{00b7} required", in: ordered, screen: "measure",
            role: "the method control's heading"
        ) else { return }
        guard let saveIndex = position(
            of: "Save measurement", kind: "Button", in: ordered, screen: "measure",
            role: "the primary CTA"
        ) else { return }

        var kindPositions: [Int] = []
        for option in ["Trunk \u{00b7} DBH", "Height"] {
            guard let index = position(
                of: option, kind: "Button", in: ordered, screen: "measure",
                role: "a measurement-kind option"
            ) else { return }
            kindPositions.append(index)
        }
        var methodPositions: [Int] = []
        for option in ["Tape", "Caliper", "Estimate"] {
            guard let index = position(
                of: option, kind: "Button", in: ordered, screen: "measure",
                role: "a measurement-method option"
            ) else { return }
            methodPositions.append(index)
        }
        // `MeasureKey.pad`'s ten digits. Matched as Buttons: the readout above draws a static `0`
        // too, and it is the one this would otherwise find.
        var digitPositions: [Int] = []
        for digit in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"] {
            guard let index = position(
                of: digit, kind: "Button", in: ordered, screen: "measure", role: "a keypad digit"
            ) else { return }
            digitPositions.append(index)
        }

        XCTAssertLessThan(
            kindHeadingIndex, kindPositions.min()!,
            "measure: the kind heading reads at \(kindHeadingIndex) and its first option at "
                + "\(kindPositions.min()!) — the question arrives after its own answers"
        )
        XCTAssertLessThan(
            kindPositions.max()!, methodHeadingIndex,
            "measure: a kind option reads at \(kindPositions.max()!), past the method heading at "
                + "\(methodHeadingIndex) — the two controls have interleaved, and a listener "
                + "cannot tell which segment belongs to which question"
        )
        XCTAssertLessThan(
            methodHeadingIndex, methodPositions.min()!,
            "measure: the method heading reads at \(methodHeadingIndex) and its first option at "
                + "\(methodPositions.min()!) — the same defect one control down"
        )
        XCTAssertLessThan(
            methodPositions.max()!, digitPositions.min()!,
            "measure: a method option reads at \(methodPositions.max()!), after the first keypad "
                + "digit at \(digitPositions.min()!) — a reader reaches the digits before the "
                + "required method, and types a number whose method is whatever was selected for "
                + "them"
        )
        XCTAssertLessThan(
            digitPositions.max()!, saveIndex,
            "measure: a keypad digit reads at \(digitPositions.max()!), after "
                + "\u{2018}Save measurement\u{2019} at \(saveIndex) — a reader is offered the save "
                + "before the keys that give it something to save, and saves the readout\u{2019}s "
                + "zero"
        )

        app.terminate()
    }

    // MARK: - Screen 09 · the four things you did, before the optional well, before Done

    /// **The care log's entry *is* its four toggles**, and `Done` with none of them on writes a
    /// visit that records nothing. Screen 09's own instruction line says the shape out loud
    /// ("Toggle what you did. Thirty seconds, then back to your walk"), and the order that sentence
    /// describes has never been asserted.
    ///
    /// The second half of this is ERRATA **E185**'s: the photo/note well under the toggles is
    /// optional, and the only thing that says so is the micro-label
    /// `Photo or note (optional)` immediately above it. A listener who met the note field first
    /// would have no reason to think it could be skipped — and E185 is the entry recording that
    /// this well shipped drawn and inert once already, so its labeling is not a hypothetical
    /// concern on this screen.
    ///
    /// **A cover, and waited for as one (ERRATA E245).** Screen 09 is presented over the map rather
    /// than pushed, so its anchor enters the tree from `BottomSheet`'s first frame — before the
    /// card has risen. `waitForCoverToArrive` is the settle this suite already uses for exactly
    /// these two screens; reading `debugDescription` without it reads a tree mid-animation.
    ///
    /// **The map behind it is in the tree, and that is fine.** Every anchor below is unique to the
    /// care log, and the assertions are relative positions among them — the map's own element
    /// count varies with the camera and with how many pins it drew, and nothing here depends on it.
    func testCareLogRecordsWhatYouDidBeforeOfferingToFinish() {
        let app = launch("careLog")
        guard arrive(app, screen: "careLog", anchor: "Care log") else { return }
        guard waitForCoverToArrive(app, screen: "careLog", anchor: "Care log") else {
            XCTFail("careLog: the sheet never settled, so nothing below is reading a stable tree")
            app.terminate()
            return
        }
        guard let ordered = orderedTree(app, screen: "careLog") else {
            app.terminate()
            return
        }

        // `CareActionLabel` (in `Chip.swift`), `CareLogCopy.optionalWell` and `.doneCTA` — copied
        // by hand (E116).
        var actionPositions: [Int] = []
        for action in ["Watered", "Mulched", "Weeded basin", "Litter cleared"] {
            guard let index = position(
                of: action, kind: "Button", in: ordered, screen: "careLog", role: "a care action"
            ) else { return }
            actionPositions.append(index)
        }
        guard let wellHeadingIndex = position(
            of: "Photo or note (optional)", in: ordered, screen: "careLog",
            role: "the optional well\u{2019}s own label"
        ) else { return }
        guard let noteFieldIndex = position(
            of: "Note", kind: "TextField", in: ordered, screen: "careLog",
            role: "the optional well\u{2019}s note field"
        ) else { return }
        guard let doneIndex = position(
            of: "Done", kind: "Button", in: ordered, screen: "careLog", role: "the primary CTA"
        ) else { return }

        XCTAssertLessThan(
            actionPositions.max()!, wellHeadingIndex,
            "careLog: a care action reads at \(actionPositions.max()!), after the optional well\u{2019}s "
                + "heading at \(wellHeadingIndex) — the toggles that ARE the entry have fallen "
                + "inside the section marked optional, where a reader may skip them"
        )
        XCTAssertLessThan(
            wellHeadingIndex, noteFieldIndex,
            "careLog: the note field reads at \(noteFieldIndex), before the "
                + "\u{2018}(optional)\u{2019} label at \(wellHeadingIndex) that is the only thing "
                + "telling a listener it can be left empty (ERRATA E185)"
        )
        XCTAssertLessThan(
            actionPositions.max()!, doneIndex,
            "careLog: a care action reads at \(actionPositions.max()!), after \u{2018}Done\u{2019} "
                + "at \(doneIndex) — a reader is offered the finish before the toggles, and files a "
                + "visit that records nothing"
        )
        XCTAssertLessThan(
            wellHeadingIndex, doneIndex,
            "careLog: the optional photo/note well reads at \(wellHeadingIndex), after "
                + "\u{2018}Done\u{2019} at \(doneIndex) — it is past the control that ends the "
                + "screen, so a listener never reaches it"
        )

        app.terminate()
    }
}
