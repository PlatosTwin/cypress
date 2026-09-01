//
//  JournalModelLifetimeTests.swift
//  CypressTests
//
//  Two claims `JournalModel` makes about itself that nothing in the suite could see.
//
//  ── 1. The guard that was true about the model and false about the screen ────────────────────
//  `JournalModel.load()` returns early when the phase is already `.loaded`, and its doc comment
//  said — for two rounds — that this is what stops a segment switch throwing away pages the reader
//  had asked for. The guard is correct. The sentence was not: the model it guarded was `@State` on
//  `JournalSection`, and `JournalSection` was mounted from inside `JournalTabView`'s `switch` on
//  the segment. SwiftUI ties `@State` to the identity of the declaring view, and a `switch` arm
//  that is not taken has no identity, so a glance at Neighborhood destroyed the model outright. The
//  next `.task` met a brand new one in `.loading` and re-read page one; everything `Show earlier`
//  had fetched was gone.
//
//  That is this project's named defect class — a confident comment asserting an invariant nobody
//  verified — and the model-level test alone cannot catch it, because at the model level the guard
//  works. What decides it is *which view declares the state*, which is a fact about the source. So
//  there are two tests: `loadIsIdempotent…` for the guard, and `theModelIsOwnedAboveTheSegment
//  Switch` for the structure the guard depends on.
//
//  ── 2. The derivation that ran on every body pass ────────────────────────────────────────────
//  `presentation` was a computed property. SwiftUI evaluates a body many times per visible change,
//  and each evaluation rebuilt every row title, the day fold, and a `DateFormatter` per day group.
//  `presentationIsDerivedOncePerPhaseChange` proves it is now derived once, using the one input the
//  derivation has that a repeated read could reveal: `now`, which decides whether a day header
//  carries its year.
//

import Foundation
import Testing
@testable import Cypress

@Suite("Journal · the model outlives the segment, and derives once")
struct JournalModelLifetimeTests {

    // MARK: - Fixtures

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private static func entry(_ index: Int, at capturedAt: Date = date(2026, 6, 1)) -> JournalEntry {
        JournalEntry(
            id: UUID(),
            kind: .visit,
            treeID: UUID(),
            treeDisplayName: "Tree \(index)",
            capturedAt: capturedAt,
            summary: "",
            heroPhotoID: nil
        )
    }

    // MARK: - 1 · The guard, and the structure it depends on

    /// The guard itself: a second `load()` on a model that already read does not read again.
    ///
    /// This is what a `.task` firing on every reappearance of the segment does, so the read count is
    /// the assertion rather than the row count — a model that re-read and happened to get the same
    /// page back would look identical on screen while paying for the trip.
    @Test("load is idempotent, so a reappearing segment does not re-read")
    @MainActor
    func loadIsIdempotentOnASuccessfulRead() async {
        let reads = JournalReadCounter()
        let model = JournalModel(
            api: JournalPreviewAPI(page: Page(items: [Self.entry(1)]), reads: reads),
            now: { Self.date(2026, 7, 1) }
        )

        await model.load()
        #expect(reads.count == 1)

        // Away to Neighborhood and back, twice.
        await model.load()
        await model.load()
        #expect(reads.count == 1, "a segment the reader looked away from re-read its first page")
    }

    /// And the pages `Show earlier` fetched survive that reappearance.
    ///
    /// The count is the point: `load()`'s guard returning early is only worth something if what it
    /// declines to overwrite is the *accumulated* list rather than page one.
    @Test("pages fetched by Show earlier survive a reappearance")
    @MainActor
    func showEarliersPagesSurviveAReappearance() async {
        let reads = JournalReadCounter()
        let model = JournalModel(
            api: JournalPreviewAPI(
                page: Page(items: (1...3).map { Self.entry($0) }, nextCursor: "cursor"),
                older: Page(items: (4...5).map { Self.entry($0) }),
                reads: reads
            ),
            now: { Self.date(2026, 7, 1) }
        )

        await model.load()
        await model.loadOlder()
        #expect(model.presentation?.rows.count == 5)
        #expect(reads.count == 2)

        await model.load()
        #expect(
            model.presentation?.rows.count == 5,
            "the reader came back to page one, which is exactly what the segment switch used to do"
        )
        #expect(reads.count == 2)
    }

    /// **The structural half: the model is declared above the segment `switch`, not inside it.**
    ///
    /// A source scan and not a rendered measurement, for `ScrollOverhangGuardTests`' reason: the
    /// defect is not in any value the suite can read back. It is which view declares the `@State`,
    /// and the rendered version of this check is a UI test that costs a device, an install and a
    /// launch to observe one `.task` not firing.
    ///
    /// Both halves are asserted, because either alone goes vacuous. `JournalTabView` must declare
    /// the state, and `JournalListView` — where `JournalSection` lives — must not declare a
    /// `JournalModel` at all: moving the declaration back down would satisfy a test that only
    /// looked for its absence somewhere, and adding a second one would satisfy a test that only
    /// looked for its presence here.
    @Test("the journal model is owned above the segment switch, not inside it")
    func theModelIsOwnedAboveTheSegmentSwitch() throws {
        let root = AppSourceLiterals.repositoryRoot()
        let tab = try String(
            contentsOf: root.appendingPathComponent("Cypress/Features/Journal/JournalTabView.swift"),
            encoding: .utf8
        )
        let list = try String(
            contentsOf: root.appendingPathComponent("Cypress/Features/Journal/JournalListView.swift"),
            encoding: .utf8
        )

        #expect(
            tab.contains("@State private var model: JournalModel"),
            """
            JournalTabView no longer declares the journal's model. It has to be declared above the \
            `switch` on the segment — see this file's header for what happens when it is not
            """
        )
        #expect(
            Self.declaresJournalModelState(in: list).isEmpty,
            """
            JournalListView declares SwiftUI state holding a JournalModel: \
            \(Self.declaresJournalModelState(in: list)). JournalSection is mounted from inside \
            JournalTabView's segment `switch`, so state it owns is destroyed by a glance at \
            Neighborhood
            """
        )
    }

    /// **The calibration for the scan above**, which is otherwise two `contains` calls that would
    /// both keep passing after a rename.
    ///
    /// Run against the two spellings this project actually writes: the declaration
    /// `JournalListView` used to carry, which must be reported, and the one `JournalTabView` carries
    /// now, which must also be reported when it is the file being scanned. A scanner that reported
    /// neither would make the second assertion above vacuously true forever.
    @Test("the ownership scan reports a state declaration it is shown")
    func theOwnershipScanCanSeeADeclaration() {
        let asItWas = """
            struct JournalSection: View {
                @State private var model: JournalModel
            }
            """
        #expect(
            Self.declaresJournalModelState(in: asItWas) == ["@State private var model: JournalModel"],
            "the scan cannot see the exact declaration this gate exists to forbid"
        )
        #expect(
            Self.declaresJournalModelState(in: "let model: JournalModel").isEmpty,
            "the scan reports a handed-in model as owned state, which would forbid the fix itself"
        )
    }

    /// Every line declaring SwiftUI state whose type is `JournalModel`.
    ///
    /// `@State` and `@StateObject` both, because both tie a value to the declaring view's identity,
    /// which is the property that matters here. A `let` or a plain `var` is a handed-in reference
    /// and is what the fixed code does.
    static func declaresJournalModelState(in source: String) -> [String] {
        source.components(separatedBy: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("@State") || trimmed.hasPrefix("@StateObject") else { return nil }
            guard trimmed.contains("JournalModel") else { return nil }
            return trimmed
        }
    }

    // MARK: - 2 · The derivation runs once per phase change

    /// **`presentation` is derived when the phase changes, not when it is read.**
    ///
    /// The proof uses the one input the derivation has that a second read could expose. `now` decides
    /// whether `JournalCopy.day` prints the year: inside the current year it writes `Jun 1`, outside
    /// it `Jun 1, 2026`. So a clock that answers 2026 once and 2030 afterwards makes a *computed*
    /// presentation change its header between two consecutive reads and leaves a *stored* one alone.
    ///
    /// The second half is the calibration, and without it this test would pass on a clock that never
    /// moved: it builds the same presentation directly with the later date and requires the header to
    /// actually differ. If those two are equal the experiment is inert, and `#require` says so
    /// instead of reporting a pass.
    @Test("the presentation is derived once per phase change, not once per read")
    @MainActor
    func presentationIsDerivedOncePerPhaseChange() async throws {
        let ticks = JournalReadCounter()
        let early = Self.date(2026, 7, 1)
        let late = Self.date(2030, 1, 1)
        let captured = Self.date(2026, 6, 1)

        // Calibration first: the two clocks have to produce different headers, or the experiment
        // below cannot fail.
        let entries = [Self.entry(1, at: captured)]
        let asRead = JournalPresentation(entries: entries, nextCursor: nil, now: early)
        let asReRead = JournalPresentation(entries: entries, nextCursor: nil, now: late)
        try #require(
            asRead.days.first?.header != asReRead.days.first?.header,
            """
            the two clocks format this date identically, so a re-derivation would be invisible and \
            this test could not fail — pick dates that straddle a year boundary
            """
        )

        let model = JournalModel(
            api: JournalPreviewAPI(page: Page(items: entries)),
            now: {
                let first = ticks.count == 0
                ticks.record()
                return first ? early : late
            }
        )
        await model.load()

        let first = model.presentation?.days.first?.header
        let second = model.presentation?.days.first?.header
        let third = model.presentation?.days.first?.header
        #expect(first == asRead.days.first?.header, "the first derivation did not use the load's clock")
        #expect(
            first == second && second == third,
            """
            reading `presentation` re-derived it: the header went \(first ?? "<nil>") → \
            \(second ?? "<nil>") → \(third ?? "<nil>") across three reads of an unchanged model
            """
        )
        #expect(ticks.count == 1, "the clock was sampled \(ticks.count) times for one loaded page")
    }

    /// A phase change *does* re-derive, which is the other half of "once per phase change" and the
    /// thing a presentation frozen at init would fail.
    @Test("a new page re-derives the presentation")
    @MainActor
    func aNewPageReDerives() async {
        let model = JournalModel(
            api: JournalPreviewAPI(
                page: Page(items: [Self.entry(1)], nextCursor: "cursor"),
                older: Page(items: [Self.entry(2), Self.entry(3)])
            ),
            now: { Self.date(2026, 7, 1) }
        )
        await model.load()
        #expect(model.presentation?.rows.count == 1)

        await model.loadOlder()
        #expect(model.presentation?.rows.count == 3, "Show earlier's rows never reached the derivation")

        await model.retry()
        #expect(model.presentation?.rows.count == 1, "a retry did not re-derive from the fresh first page")
    }

    /// **A failed retry clears the presentation it had**, which is the arm `setPhase` has to handle
    /// for a stored `presentation` not to outlive its phase.
    ///
    /// The transition has to be `.loaded` → `.failed` on **one** model, and that is why
    /// `JournalPreviewAPI.failsAfterFirst` exists: a model that never loaded has no presentation to
    /// lose, so asserting `nil` on one proves only that nothing was ever set. `retry()` is the only
    /// path that makes the transition — `loadOlder`'s failure deliberately keeps what is on screen
    /// (ERRATA E126, and this model's file comment).
    @Test("a failed retry clears the presentation rather than leaving the last one behind")
    @MainActor
    func aFailureClearsThePresentation() async throws {
        let reads = JournalReadCounter()
        let model = JournalModel(
            api: JournalPreviewAPI(
                page: Page(items: [Self.entry(1)]),
                failsAfterFirst: true,
                reads: reads
            ),
            now: { Self.date(2026, 7, 1) }
        )
        await model.load()
        try #require(
            model.presentation?.rows.count == 1,
            "the fixture did not load a page, so there is nothing for the failure to clear"
        )
        #expect(reads.count == 1)

        await model.retry()
        #expect(model.hasFailed, "the second read was supposed to fail")
        #expect(
            model.presentation == nil,
            """
            a journal that could not be re-read went on drawing the rows of the read before it, \
            under a screen that says it failed — ERRATA E126's own case
            """
        )
    }
}
