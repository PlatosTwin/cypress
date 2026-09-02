//
//  JournalModelLifetimeTests.swift
//  CypressTests
//
//  Two claims `JournalModel` makes about itself that nothing in the suite could see.
//
//  ── 1. The claim that was true about the model and false about the screen ────────────────────
//  `JournalModel.load()` declines to overwrite a list it already has, and its doc comment said —
//  for two rounds — that this is what stops a segment switch throwing away pages the reader asked
//  for. The behavior was right. The sentence was not: the model was `@State` on `JournalSection`,
//  and `JournalSection` was mounted from inside `JournalTabView`'s `switch` on the segment. SwiftUI
//  ties `@State` to the identity of the declaring view, and a `switch` arm that is not taken has no
//  identity, so a glance at Neighborhood destroyed the model outright. The next `.task` met a brand
//  new one in `.loading`; everything `Show earlier` had fetched was gone.
//
//  That is this project's named defect class — a confident comment asserting an invariant nobody
//  verified — and a model-level test alone cannot catch it, because at the model level the behavior
//  works. What decides it is *which view declares the state*, which is a fact about the source. So
//  it takes both: `aReappearancePaintsWhatItHad` / `showEarliersPagesSurvive…` for the behavior,
//  and `theModelIsOwnedAboveTheSegmentSwitch` for the structure it depends on.
//
//  ── 1b. And the other half of the owner's ruling ─────────────────────────────────────────────
//  "Pages survive AND refresh in the background." PR #143's review pointed out that the first
//  version delivered only the first half, and had in fact *removed* an accidental refresh: before
//  the lifetime fix, a segment flip re-read everything because it destroyed the model. So `load()`
//  now repaints instantly and re-reads page one behind the list, reconciling it against the deeper
//  pages rather than replacing them. Four tests: the new contribution appears, the kept pages stay,
//  a failed refresh disturbs nothing, and a journal that shrank drops what is gone.
//
//  ── 2. The derivation that ran on every body pass ────────────────────────────────────────────
//  `presentation` was a computed property. SwiftUI evaluates a body many times per visible change,
//  and each evaluation rebuilt every row title, the day fold, and a `DateFormatter` per day group.
//  `presentationIsDerivedOncePerPhaseChange` proves it is now derived once.
//
//  Memoizing it froze three environment inputs, not one — `now`, `locale` and `calendar` — and the
//  last of those decides the day fold itself. `aTimeZoneChangeReDerivesTheList` and
//  `aLocaleChangeReDerivesTheList` are what make "sampled at phase change" safe rather than stale:
//  the model re-derives on the system's own notifications.
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

    /// A gregorian calendar in a named zone.
    ///
    /// At type scope rather than as a local function inside the tests: the tests are `@MainActor`,
    /// so a local `func` in one is main-actor isolated and a `@Sendable` closure handed to
    /// `JournalModel` cannot call it.
    private static func gregorian(in identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
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

    /// **A reappearance never passes through `.loading` and never changes what is on screen when
    /// nothing changed underneath.**
    ///
    /// The owner's ruling has two halves — a revisit paints what was there, *and* refreshes behind
    /// it — so a re-entry does read again, and a read count is no longer the right assertion. What
    /// it must not do is what the destroyed-model version did: blank the screen and start over.
    /// `aReappearanceRefreshesBehindTheListItKeeps` asserts the other half.
    @Test("a reappearing segment paints what it had, with no loading state")
    @MainActor
    func aReappearancePaintsWhatItHad() async throws {
        let entries = (1...3).map { Self.entry($0) }
        let model = JournalModel(
            api: JournalPreviewAPI(page: Page(items: entries)),
            now: { Self.date(2026, 7, 1) }
        )

        await model.load()
        let drawn = try #require(model.presentation?.rows.map(\.id))
        try #require(drawn.count == 3)

        // Away to Neighborhood and back, twice.
        for _ in 0..<2 {
            await model.load()
            #expect(model.phase != .loading, "a reappearance blanked the screen")
            #expect(model.hasFailed == false)
            #expect(
                model.presentation?.rows.map(\.id) == drawn,
                "a reappearance changed the rows on screen when nothing had changed underneath"
            )
        }
    }

    /// And the pages `Show earlier` fetched survive that reappearance.
    ///
    /// This is the property the whole lifetime change exists for, and the refresh arm must not cost
    /// it: `JournalModel.refresh()`'s reconciliation keeps every held row the fresh page one does
    /// not cover. Nothing changed underneath here, so all five have to still be there — and the
    /// read count has to show the refresh actually ran, or this passes for the wrong reason.
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
        let five = model.presentation?.rows.map(\.id)
        #expect(five?.count == 5)
        #expect(reads.count == 2)

        await model.load()
        #expect(
            model.presentation?.rows.map(\.id) == five,
            """
            the reader came back to page one — exactly what the segment switch used to do — or the \
            refresh dropped rows its reconciliation was supposed to keep
            """
        )
        #expect(reads.count == 3, "the reappearance did not refresh behind the list")
    }

    // MARK: - 1b · The other half of the ruling: it refreshes behind what it keeps

    /// **A contribution written while the reader was elsewhere appears on re-entry, and the pages
    /// they had fetched are still under it.**
    ///
    /// This is the owner's ruling in one assertion. The fixture is the real sequence: read page
    /// one, press `Show earlier`, leave the segment, two new contributions land, come back. The
    /// list must then be `new, new, page one…, page two…` — newest first, nothing duplicated,
    /// nothing lost.
    ///
    /// The ids are what is compared rather than the count, because a count of seven is also what
    /// you get from the wrong list.
    @Test("a contribution written while the reader was away appears on re-entry, above the pages they kept")
    @MainActor
    func aReappearanceRefreshesBehindTheListItKeeps() async throws {
        let base = Self.date(2026, 6, 1)
        // Distinct, descending capture times — the order the store returns and the paging is built
        // on. `refresh()`'s reconciliation is written against exactly this ordering.
        func entry(_ index: Int) -> JournalEntry {
            Self.entry(index, at: base.addingTimeInterval(-Double(index) * 3600))
        }
        let pageOne = (1...3).map(entry)
        let pageTwo = (4...5).map(entry)
        let arrivedWhileAway = [entry(-2), entry(-1)]

        // The counter is not decoration: `JournalPreviewAPI` keys `refreshed` on the attempt
        // number, so without one every read is attempt zero and page one never changes. That is
        // how the first draft of this test passed against an unchanged list.
        let reads = JournalReadCounter()
        let model = JournalModel(
            api: JournalPreviewAPI(
                page: Page(items: pageOne, nextCursor: "cursor"),
                older: Page(items: pageTwo, nextCursor: "cursor2"),
                refreshed: Page(items: arrivedWhileAway + pageOne.prefix(1), nextCursor: "cursor"),
                reads: reads
            ),
            now: { Self.date(2026, 7, 1) }
        )

        await model.load()
        await model.loadOlder()
        try #require(
            model.presentation?.rows.map(\.id) == (pageOne + pageTwo).map(\.id),
            "the fixture did not produce the two-page list this test is about"
        )

        // Away to Neighborhood, and back.
        await model.load()
        try #require(reads.count == 3, "the re-entry did not read at all, so nothing is being tested")

        #expect(
            model.presentation?.rows.map(\.id)
                == (arrivedWhileAway + pageOne + pageTwo).map(\.id),
            """
            re-entry did not reconcile. Expected the two new contributions above the seven rows the \
            reader already had, newest first; got \
            \(model.presentation?.rows.map(\.title) ?? [])
            """
        )
        #expect(
            model.presentation?.hasOlder == true,
            """
            the reconciled list still runs down to the old tail, so it keeps the cursor it had \
            rather than the fresh page's — asking from the fresh page's cursor would re-fetch rows \
            already on screen
            """
        )
    }

    /// **A refresh that fails changes nothing** — not the rows, not `hasFailed`, and not
    /// `hasFailedOlder`, which belongs to `Show earlier` and would put a note on screen about a read
    /// the reader never asked for.
    @Test("a failed background refresh leaves the screen exactly as it was")
    @MainActor
    func aFailedRefreshChangesNothing() async throws {
        let reads = JournalReadCounter()
        let model = JournalModel(
            api: JournalPreviewAPI(
                page: Page(items: (1...3).map { Self.entry($0) }, nextCursor: "cursor"),
                older: Page(items: (4...5).map { Self.entry($0) }),
                refreshFails: true,
                reads: reads
            ),
            now: { Self.date(2026, 7, 1) }
        )

        await model.load()
        await model.loadOlder()
        let before = try #require(model.presentation?.rows.map(\.id))
        try #require(before.count == 5)

        await model.load()
        try #require(reads.count == 3, "the refusing read never happened, so nothing is being tested")
        #expect(model.presentation?.rows.map(\.id) == before, "a failed refresh disturbed the list")
        #expect(model.hasFailed == false, "a background refresh took the whole screen down")
        #expect(
            model.hasFailedOlder == false,
            """
            a failed background refresh raised `Show earlier`'s flag, putting a note on screen \
            about a read the reader never asked for
            """
        )
    }

    /// **A journal that shrank to less than a page loses the rows that are gone.**
    ///
    /// The reconciliation's second case, and the one a "keep everything held" merge gets wrong: a
    /// fresh page one that comes back with no cursor *is* the whole journal, so anything held
    /// beyond it has been deleted and must not linger.
    @Test("a refresh that reaches the end of the journal drops rows that no longer exist")
    @MainActor
    func aRefreshThatReachesTheEndDropsDeletedRows() async throws {
        let reads = JournalReadCounter()
        let base = Self.date(2026, 6, 1)
        func entry(_ index: Int) -> JournalEntry {
            Self.entry(index, at: base.addingTimeInterval(-Double(index) * 3600))
        }
        let pageOne = (1...3).map(entry)
        let pageTwo = (4...5).map(entry)

        let model = JournalModel(
            api: JournalPreviewAPI(
                page: Page(items: pageOne, nextCursor: "cursor"),
                older: Page(items: pageTwo),
                // Everything but the first two rows has been deleted, and the page says so by
                // coming back without a cursor.
                refreshed: Page(items: Array(pageOne.prefix(2))),
                reads: reads
            ),
            now: { Self.date(2026, 7, 1) }
        )

        await model.load()
        await model.loadOlder()
        try #require(model.presentation?.rows.count == 5)

        await model.load()
        try #require(reads.count == 3, "the re-entry did not read at all, so nothing is being tested")
        #expect(
            model.presentation?.rows.map(\.id) == pageOne.prefix(2).map(\.id),
            "deleted contributions survived a refresh that had told the model the journal was shorter"
        )
        #expect(model.presentation?.hasOlder == false)
    }

    /// **A refresh keeps a held row that ties with page one's last, because that row is page two.**
    ///
    /// `refresh()`'s reconciliation drops held rows *newer* than the fresh page's last row — that
    /// is how a deletion inside the fresh window is noticed — and the boundary is `<=`, so a row
    /// tying with `oldest` is kept. Until `AppSchema` v19 that boundary was nearly unreachable and
    /// its own doc comment said so: the cursor asked for `captured_at < :cursor`, so page two never
    /// held a row tying with page one's last. **It never held one because those rows were being
    /// dropped from the journal entirely**, which is the defect `JournalPaginationTieTests`
    /// records. Now that the cursor carries `(captured_at, id)`, a tie straddling the boundary is
    /// the ordinary shape of a second page — so this boundary is on the common path and needs a
    /// test rather than a paragraph.
    ///
    /// The fixture is the smallest thing that has it: page one ends on a tie, page two opens on the
    /// other half of that tie, and the refresh returns a page one that is unchanged. The tie-mate
    /// is held, absent from the fresh page, and exactly equal to `oldest` — the one case `<` and
    /// `<=` disagree about.
    ///
    /// **Red-proof, measured.** Changing `refresh()`'s `$0.capturedAt <= oldest` to `<` fails here
    /// on four rows against five, having dropped `tieMate` — a real contribution, off a screen the
    /// reader was looking at, on a refresh they did not ask for:
    ///
    ///     Expectation failed: (model.presentation?.rows.map(\.id) → [460908A7…, 297B4590…,
    ///       22A493BA…, 464E3F07…]) == (whole → […five ids…])
    ///
    /// `aReappearanceKeepsThePagesItHad` goes red on the same edit, which is worth stating rather
    /// than treating as noise: its fixture leaves every row on one capture time, so under a strict
    /// `<` the refresh discards the whole held list. Two tests, one boundary.
    @Test("a background refresh keeps a held row that ties with page one's last row")
    @MainActor
    func aRefreshKeepsATieMateThatLivesOnPageTwo() async throws {
        let reads = JournalReadCounter()
        let base = Self.date(2026, 6, 1)
        let boundary = base.addingTimeInterval(-3 * 3600)

        // Page one's last row and page two's first share `boundary` — the tie continues across the
        // page break, which is what v19's cursor made possible and what the old cursor skipped.
        let head = [Self.entry(1, at: base), Self.entry(2, at: base.addingTimeInterval(-3600))]
        let lastOfPageOne = Self.entry(3, at: boundary)
        let tieMate = Self.entry(4, at: boundary)
        let deeper = Self.entry(5, at: base.addingTimeInterval(-9 * 3600))

        let model = JournalModel(
            api: JournalPreviewAPI(
                page: Page(items: head + [lastOfPageOne], nextCursor: "cursor"),
                older: Page(items: [tieMate, deeper]),
                // Nothing changed underneath: the fresh page one is the same three rows.
                refreshed: Page(items: head + [lastOfPageOne], nextCursor: "cursor"),
                reads: reads
            ),
            now: { Self.date(2026, 7, 1) }
        )

        await model.load()
        await model.loadOlder()
        let whole = (head + [lastOfPageOne, tieMate, deeper]).map(\.id)
        try #require(
            model.presentation?.rows.map(\.id) == whole,
            "the fixture did not produce the tie-straddling two-page list this test is about"
        )
        try #require(
            tieMate.capturedAt == lastOfPageOne.capturedAt,
            """
            the fixture's page-two row no longer ties with page one's last, so the `<=` boundary \
            this test exists for is never reached
            """
        )

        await model.load()
        try #require(reads.count == 3, "the re-entry did not refresh, so nothing is being tested")
        #expect(
            model.presentation?.rows.map(\.id) == whole,
            """
            the refresh dropped a held row that ties with page one's last. Since v19 that row is an \
            ordinary page-two row and not a transient — `refresh()`'s boundary has to be `<=`, and \
            a strict `<` loses a real contribution off a screen the reader is looking at
            """
        )
    }

    // MARK: - 2 · The structure the guard depends on

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

    /// **The memoization must not outlive the settings it sampled.**
    ///
    /// `presentation` freezes three environment inputs, not one: `now`, `locale` and `calendar`.
    /// The last two decide the header's format, and `calendar` decides the day fold itself through
    /// `startOfDay(for:)` — so a time-zone change can restack which rows sit under which header.
    /// They used to be re-read on every body pass; memoizing them would have meant a list formatted
    /// and grouped under settings the reader has since changed, for as long as the model lives —
    /// which this round's other half makes strictly longer.
    ///
    /// **The assertion is the day fold, not the label**, because the fold is the stronger effect
    /// and the one no formatter cache could ever fix: two contributions on either side of a
    /// midnight in one zone are one group in another. Two rows ten hours apart on the evening of
    /// 1 June UTC are one day in UTC and two in Tokyo.
    ///
    /// The `#require` is the calibration and it has already earned its place: the first version of
    /// this test compared headers, and headers were identical in both zones — `JournalCopy.day`
    /// did not set the formatter's zone at all, which is a real inconsistency this round fixed
    /// rather than a fact about the two calendars.
    @Test("a time-zone change re-derives the list under the new calendar")
    @MainActor
    func aTimeZoneChangeReDerivesTheList() async throws {
        // 2026-06-01 20:00Z and 2026-06-01 10:00Z. UTC calls both 1 June; Tokyo (+09:00) calls the
        // first 2 June and the second 1 June.
        let evening = Date(timeIntervalSince1970: 1_780_344_000)
        let morning = Date(timeIntervalSince1970: 1_780_308_000)
        // Newest first, which is the order the store returns and the fold is built on.
        let entries = [Self.entry(1, at: evening), Self.entry(2, at: morning)]

        let inUTC = JournalPresentation(
            entries: entries, nextCursor: nil, now: evening,
            calendar: Self.gregorian(in: "UTC"), locale: Locale(identifier: "en_US")
        )
        let inTokyo = JournalPresentation(
            entries: entries, nextCursor: nil, now: evening,
            calendar: Self.gregorian(in: "Asia/Tokyo"), locale: Locale(identifier: "en_US")
        )
        try #require(
            inUTC.days.count == 1 && inTokyo.days.count == 2,
            """
            the two zones fold these rows the same way (\(inUTC.days.count) and \
            \(inTokyo.days.count) groups), so a re-derivation would be invisible here and this \
            test could not fail — pick capture times that straddle a midnight in one zone only
            """
        )

        let zone = ZoneBox(identifier: "UTC")
        let model = JournalModel(
            api: JournalPreviewAPI(page: Page(items: entries)),
            now: { evening },
            calendar: { Self.gregorian(in: zone.identifier) },
            locale: { Locale(identifier: "en_US") }
        )
        await model.load()
        try #require(model.presentation?.days.count == 1, "the fixture did not load under UTC")

        // The reader crosses a time zone, or changes it in Settings.
        zone.identifier = "Asia/Tokyo"
        NotificationCenter.default.post(name: .NSSystemTimeZoneDidChange, object: nil)
        // The observer is registered on the main queue; let it run.
        await Task.yield()

        #expect(
            model.presentation?.days.count == 2,
            """
            the list is still folded under the zone it was read in: \
            \(model.presentation?.days.map(\.header) ?? []) where the new zone puts these rows \
            under \(inTokyo.days.map(\.header))
            """
        )
        #expect(
            model.presentation?.rows.count == 2,
            """
            re-deriving on a zone change lost rows, which it must never do — it re-labels and \
            re-folds the entries the model already holds
            """
        )
    }

    /// The same, for the locale notification, which is what a Region or Calendar change posts.
    @Test("a locale change re-derives the list under the new locale")
    @MainActor
    func aLocaleChangeReDerivesTheList() async throws {
        let captured = Self.date(2026, 6, 1)
        let entry = Self.entry(1, at: captured)
        let calendar = Self.calendar

        let inUS = JournalPresentation(
            entries: [entry], nextCursor: nil, now: captured,
            calendar: calendar, locale: Locale(identifier: "en_US")
        )
        let inJP = JournalPresentation(
            entries: [entry], nextCursor: nil, now: captured,
            calendar: calendar, locale: Locale(identifier: "ja_JP")
        )
        try #require(
            inUS.days.first?.header != inJP.days.first?.header,
            "the two locales write this day identically, so the experiment is inert"
        )

        let box = ZoneBox(identifier: "en_US")
        let model = JournalModel(
            api: JournalPreviewAPI(page: Page(items: [entry])),
            now: { captured },
            calendar: { calendar },
            locale: { Locale(identifier: box.identifier) }
        )
        await model.load()
        try #require(model.presentation?.days.first?.header == inUS.days.first?.header)

        box.identifier = "ja_JP"
        NotificationCenter.default.post(name: NSLocale.currentLocaleDidChangeNotification, object: nil)
        await Task.yield()

        #expect(
            model.presentation?.days.first?.header == inJP.days.first?.header,
            "the header is still written in the locale the list was read in"
        )
    }

    /// A mutable identifier a `@Sendable` closure can read, so a test can move the environment
    /// under a model the way Settings does. `NSLock` for the reason `JournalReadCounter` gives.
    final class ZoneBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: String
        init(identifier: String) { self.value = identifier }
        var identifier: String {
            get { lock.lock(); defer { lock.unlock() }; return value }
            set { lock.lock(); defer { lock.unlock() }; value = newValue }
        }
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
