//
//  JournalPresentationTests.swift
//  CypressTests
//
//  The contributions journal, closing ERRATA E99.
//
//  ── What this suite is actually guarding ──────────────────────────────────────────────────
//  Two rules, and both of them are rules about what the screen may not say.
//
//  **ERRATA E38 — a page of results must not be presented as a complete series.** `journal(cursor:
//  limit:)` is a cursor read: it cannot know a total, and E38 is the entry about a screen that
//  printed one anyway (`30 photos · since 2024` on a tree with 214 photographs going back to 2019).
//  What it *can* prove is the opposite — a cursor comes back only when the page came back full — so
//  every honest sentence this screen has about how much it is showing is derived from that one fact.
//  The assertions below are on both halves: a page says so, and a series that ended says nothing.
//
//  **D1 / ARCHITECTURE §5.1 — nothing counts a person's actions.** A time-ordered list of your own
//  contributions is, as E99 put it, one design decision away from a streak. The check is blunt and
//  deliberately so: no string this screen draws may contain a digit.
//
//  ── The trap this suite is written around ────────────────────────────────────────────────
//  The almanac round's lesson: a test that iterates the same collection the bug empties passes
//  trivially. So the page assertions here are made against **what the read said** — the cursor,
//  which is the source — rather than against `rows.count`, which is the thing a paging bug changes.
//  A presentation that dropped every row would still have to answer the cursor question correctly.
//

import CoreTransferable
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Cypress

@Suite("The journal list")
struct JournalPresentationTests {

    // MARK: - Fixtures

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
        return calendar
    }

    static let locale = Locale(identifier: "en_US")

    static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date()
    }

    static let now = date(2026, 7, 20)

    static func entry(
        _ index: Int,
        kind: JournalEntry.Kind = .visit,
        tree: String = "Grandmother Cypress",
        at date: Date = JournalPresentationTests.date(2026, 7, 12),
        summary: String = "Fog on the crown",
        heroPhotoID: UUID? = nil
    ) -> JournalEntry {
        JournalEntry(
            id: UUID(uuidString: String(format: "13000000-0000-4000-8000-%012d", index))!,
            kind: kind,
            treeID: UUID(uuidString: String(format: "13000000-0000-4000-8000-%012d", 900 + index))!,
            treeDisplayName: tree,
            capturedAt: date,
            summary: summary,
            heroPhotoID: heroPhotoID
        )
    }

    static func presentation(
        _ entries: [JournalEntry],
        nextCursor: String?
    ) -> JournalPresentation {
        JournalPresentation(
            entries: entries,
            nextCursor: nextCursor,
            now: now,
            calendar: calendar,
            locale: locale
        )
    }

    // MARK: - ERRATA E38 · a page is not a series

    /// The cursor is the source, and the sentence is derived from it. Asserted in both directions in
    /// one test, because "says so when there is more" and "says nothing when there is not" are the
    /// same rule and a screen that got one right and the other wrong would be worse than one that
    /// got both wrong.
    @Test("a page that came back full says so, and a series that ended says nothing")
    func theCursorDecidesTheSentence() {
        let rows = (1...JournalLimits.pageSize).map { Self.entry($0) }

        let page = Self.presentation(rows, nextCursor: "2026-06-01T12:00:00Z")
        #expect(page.hasOlder, "a cursor came back and the presentation did not carry it")
        #expect(
            page.olderNote != nil,
            "a full page draws no sentence about being a page, which is E38's defect"
        )

        // The same rows with no cursor. `journal` returns one only when the page came back full, so
        // this is a read that reached the end — and the end of a list needs no apology.
        let whole = Self.presentation(rows, nextCursor: nil)
        #expect(whole.hasOlder == false)
        #expect(whole.olderNote == nil, "a finished read is being described as a page")
    }

    /// **The empty page.** E38's own warning is against letting a page's emptiness be phrased as
    /// "you have done nothing", and the empty state is exactly that sentence. It is therefore gated
    /// on the cursor rather than on `rows.isEmpty`.
    @Test("an empty read with more behind it is not phrased as an empty journal")
    func emptinessIsNotClaimedFromAPage() {
        let stopped = Self.presentation([], nextCursor: "2026-06-01T12:00:00Z")
        #expect(
            stopped.emptyState == nil,
            "a read that stopped is being reported as a person who has recorded nothing"
        )
        #expect(stopped.olderNote != nil, "the reader is told neither that there is more nor that there is not")

        let proved = Self.presentation([], nextCursor: nil)
        #expect(proved.emptyState != nil, "a read that reached the end of an empty journal says nothing at all")
    }

    // MARK: - D1 · no counts

    /// Blunt on purpose. Every string this screen can draw, checked for a digit — which catches a
    /// count, a total, a rank and a streak in one assertion, and would have caught E38's
    /// `30 photos` too.
    @Test("nothing the journal draws contains a number")
    func noCountsAnywhere() {
        var strings = [
            JournalCopy.screenTitle,
            JournalCopy.journalSegment,
            JournalCopy.almanacSegment,
            JournalCopy.explanation,
            JournalCopy.seeAllOnMap,
            JournalCopy.olderNote,
            JournalCopy.olderAction,
            JournalCopy.olderFailed,
            JournalCopy.emptyState,
            JournalCopy.loadFailed,
            JournalCopy.loadRetry,
            JournalCopy.exportLabel,
            JournalCopy.exportBody
        ]
        for format in ExportFormat.allCases {
            strings.append(JournalCopy.exportAction(format))
            strings.append(JournalCopy.exportTitle(format))
            strings.append(JournalCopy.exportFileName(format))
        }

        for string in strings {
            #expect(
                string.rangeOfCharacter(from: .decimalDigits) == nil,
                "\(string) prints a number on the one screen D1 forbids one on"
            )
        }
    }

    // MARK: - Rows

    @Test("each kind gets its own verb and the accent screen 13 already gives it")
    func rowsNameWhatWasDone() {
        let kinds: [JournalEntry.Kind] = [.visit, .observation, .measurement, .careEvent]
        let rows = Self.presentation(
            kinds.enumerated().map { Self.entry($0.offset + 1, kind: $0.element, summary: "") },
            nextCursor: nil
        ).rows

        // **The verb is the title now, not a clause inside a gray second line.** A journal row is a
        // sentence about something that happened; My Grove's rows are titled with a tree's name, and
        // when these were too, the two lists read as one.
        #expect(rows[0].title.hasPrefix("Visited"))
        #expect(rows[1].title.hasPrefix("Observed"))
        #expect(rows[2].title.hasPrefix("Measured"))
        #expect(rows[3].title.hasPrefix("Cared for"))
        #expect(rows[0].title == "Visited Grandmother Cypress")

        // Three of the four are screen 13's own assignments, so the same kind of contribution is the
        // same color on both screens. The fourth may not be `vacantSite`, which R7 reserves for a
        // basin with no tree in it (ERRATA E119).
        #expect(rows[1].accent == .newGrowth)
        #expect(rows[2].accent == .record)
        #expect(rows[3].accent == .water)
        let noVacantSite = rows.allSatisfy { $0.accent != .vacantSite }
        #expect(noVacantSite)
    }

    @Test("the note is a line that is left out rather than a placeholder")
    func absentSummaryIsAbsent() {
        let withNote = Self.presentation([Self.entry(1, summary: "Fog on the crown")], nextCursor: nil)
        let without = Self.presentation([Self.entry(1, summary: "   ")], nextCursor: nil)

        #expect(withNote.rows[0].subtitle == "Fog on the crown")
        // Empty, not a placeholder and not the date the header now carries. `IconTextRow` draws no
        // second line at all for this, rather than reserving a line's height for nothing.
        #expect(without.rows[0].subtitle == "")
    }

    // MARK: - Days

    /// **The structural half of telling a chronology from a collection.** My Grove's list has no
    /// dates on it at all now; this one is organized by nothing else.
    ///
    /// Grouping is by *consecutive run* rather than by key, which is what keeps the store's order
    /// (`captured_at DESC`) intact — see `JournalPresentation.Day`. The fixture is deliberately not
    /// in date order within a day and not one-row-per-day: three acts on one day, then one on
    /// another, then one back on the first date, which a `Dictionary(grouping:)` would silently
    /// merge into two sections and reorder. It must draw three.
    @Test("rows are grouped under the day they happened, by run and not by key")
    func rowsAreGroupedByDay() {
        let entries = [
            Self.entry(1, at: Self.date(2026, 7, 12)),
            Self.entry(2, kind: .careEvent, at: Self.date(2026, 7, 12)),
            Self.entry(3, kind: .measurement, at: Self.date(2026, 7, 3)),
            // Out of order in the read, which the derivation must not repair by regrouping.
            Self.entry(4, at: Self.date(2026, 7, 12))
        ]
        let days = Self.presentation(entries, nextCursor: nil).days

        #expect(days.count == 3, "the days were merged by key, which reorders the reader's list")
        #expect(days.map(\.rows.count) == [2, 1, 1])
        #expect(days[0].header == "Jul 12")
        #expect(days[1].header == "Jul 3")
        #expect(days[2].header == "Jul 12")
        // Flat order is the store's, and the groups are that same sequence cut into runs.
        #expect(days.flatMap(\.rows).map(\.id) == entries.map(\.id))
    }

    /// Two records on one day are one header, not two — which is the whole point of a header rather
    /// than a per-row date, and is also what makes a page boundary inside a day invisible.
    @Test("a day with several acts on it is written once")
    func oneHeaderPerDay() {
        let entries = (1...4).map { Self.entry($0, at: Self.date(2026, 7, 12)) }
        let days = Self.presentation(entries, nextCursor: nil).days
        #expect(days.count == 1)
        #expect(days[0].rows.count == 4)
    }

    @Test("a journal spans years, so a day outside this one carries its year")
    func datesOutsideTheYearKeepTheirYear() {
        let thisYear = Self.presentation(
            [Self.entry(1, at: Self.date(2026, 7, 12), summary: "")],
            nextCursor: nil
        )
        let lastYear = Self.presentation(
            [Self.entry(2, at: Self.date(2025, 7, 12), summary: "")],
            nextCursor: nil
        )

        #expect(thisYear.days[0].header == "Jul 12")
        #expect(
            lastYear.days[0].header.contains("2025"),
            "two different Julys are drawn under the same label"
        )
    }

    @Test("a tree the city named neither way is called what its own page calls it")
    func unnamedTreeUsesTheProfileFallback() {
        let rows = Self.presentation([Self.entry(1, tree: "")], nextCursor: nil).rows
        #expect(rows[0].title == "Visited \(TreeProfilePresentation.fallbackTitle)")
    }

    /// #176: a row draws its own tree's photograph instead of the accent tile when one is chosen.
    /// The derivation's job here is passthrough — `theHeroPhotoComesFromTheStore` below covers
    /// where the id actually comes from — so this only asserts it survives the trip from
    /// `JournalEntry` to `Row`.
    @Test("a row carries its tree's hero photo id through, and a tree with none carries none")
    func rowsCarryTheHeroPhotoID() {
        let photoID = UUID(uuidString: "13000000-0000-4000-8000-0000000000F1")!
        let rows = Self.presentation(
            [Self.entry(1, heroPhotoID: photoID), Self.entry(2, heroPhotoID: nil)],
            nextCursor: nil
        ).rows

        #expect(rows[0].heroPhotoID == photoID, "the tree's own photo id did not survive the derivation")
        #expect(rows[1].heroPhotoID == nil, "a tree with no live photograph was handed one anyway")
    }

    /// **The id as the store actually chooses it**, over a real database — the way
    /// `exportPayloadIsReal` and `GroveTreesTests.theHeroPhotoComesFromTheStore` prove their own
    /// numbers rather than a fixture's.
    @Test("the hero photo id on a journal row is what the store's own rule chose")
    func theHeroPhotoComesFromTheStore() async throws {
        let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-0000000000C7")!
        let attribution = Attribution.anonymous(deviceID: deviceID)
        let store = try await CypressStore.inMemory()
        // A real directory for the binaries `debugSeedPhotos` writes — an in-memory store's default
        // `photoDirectory` resolves to the root of a read-only volume (`PhotoHeroTests.harness`).
        let photos = FileManager.default.temporaryDirectory
            .appendingPathComponent("cypress-journal-hero-\(UUID().uuidString)", isDirectory: true)
        let api = LocalAPI(store: store, deviceID: deviceID, photoDirectory: photos)

        let tree = try await api.addTree(
            TreeDraft(
                coordinate: Coordinate(latitude: 37.7821, longitude: -122.4464),
                photoLocalPath: "/tmp/cypress-journal-hero.jpg",
                attribution: attribution
            )
        ).id
        let ids = try await api.debugSeedPhotos(treeID: tree, count: 3)
        try await store.queue.write { connection in
            try ContributionStore().insert(
                Visit(treeID: tree, attribution: attribution, capturedAt: Self.date(2026, 7, 15)),
                connection: connection
            )
        }

        let page = try await api.journal(cursor: nil, limit: JournalLimits.pageSize)
        let row = try #require(page.items.first { $0.treeID == tree })
        #expect(row.heroPhotoID == ids[0])

        let presented = JournalPresentation(entries: page.items, nextCursor: page.nextCursor)
        let presentedRow = try #require(presented.rows.first { $0.treeID == tree })
        #expect(presentedRow.heroPhotoID == ids[0])
    }

    @Test("every row carries the tree it is about, so every row has somewhere to go")
    func everyRowHasADestination() {
        let entries = (1...4).map { Self.entry($0) }
        let rows = Self.presentation(entries, nextCursor: nil).rows
        let drawn = rows.map(\.treeID)
        let read = entries.map(\.treeID)
        #expect(drawn == read)
    }

    /// The store orders by `captured_at DESC` and the cursor is the last row's timestamp, so a
    /// derivation that re-sorted would be a second ordering — and the first time the two disagreed,
    /// `Show earlier` would insert rows into the middle of a list somebody was reading.
    ///
    /// The names are distinct and not alphabetical for the reason `GroveTreesTests.orderIsTheStores`
    /// gives at length: with every fixture on one name, a sort by name is invisible to the
    /// assertion, and a test that cannot see the mutation it is written against is not a test.
    @Test("the store's order is the screen's order")
    func orderIsTheStores() {
        let entries = [
            Self.entry(1, tree: "Zelkova", at: Self.date(2026, 7, 12)),
            Self.entry(2, tree: "Almond", at: Self.date(2026, 1, 3)),
            Self.entry(3, tree: "Magnolia", at: Self.date(2025, 11, 30))
        ]
        let drawn = Self.presentation(entries, nextCursor: nil).rows.map(\.id)
        let read = entries.map(\.id)
        #expect(drawn == read)
    }

    // MARK: - The model

    @Test("a journal that could not be read is not an empty journal")
    @MainActor
    func failureIsItsOwnState() async {
        let failed = JournalModel(api: JournalPreviewAPI(fails: true), now: { Self.now })
        await failed.load()
        #expect(failed.hasFailed)
        #expect(failed.presentation == nil)

        let empty = JournalModel(api: JournalPreviewAPI(), now: { Self.now })
        await empty.load()
        #expect(empty.hasFailed == false)
        #expect(empty.presentation != nil)
        #expect(empty.presentation?.emptyState != nil)
    }

    @Test("Show earlier appends the next page and stops when the cursor does")
    @MainActor
    func showOlderAppends() async {
        let first = Page(items: (1...3).map { Self.entry($0) }, nextCursor: "cursor")
        let second = Page(items: (4...5).map { Self.entry($0) })
        let model = JournalModel(
            api: JournalPreviewAPI(page: first, older: second),
            now: { Self.now }
        )

        await model.load()
        #expect(model.presentation?.rows.count == 3)
        #expect(model.presentation?.hasOlder == true)

        await model.loadOlder()
        #expect(model.presentation?.rows.count == 5)
        #expect(model.presentation?.hasOlder == false, "the second page's silence was not believed")
        #expect(model.presentation?.olderNote == nil)
    }

    /// Without the cursor guard, `loadOlder` would re-read page one and draw every row twice. The
    /// assertion is on the read count rather than on the rows, because a duplicate-suppressing list
    /// would hide the second read while still paying for it.
    @Test("Show earlier cannot re-read page one")
    @MainActor
    func showOlderNeedsACursor() async {
        let reads = JournalReadCounter()
        let model = JournalModel(
            api: JournalPreviewAPI(page: Page(items: [Self.entry(1)]), reads: reads),
            now: { Self.now }
        )

        await model.load()
        #expect(reads.count == 1)

        await model.loadOlder()
        #expect(reads.count == 1, "a journal with no cursor asked for a page anyway")
        #expect(model.presentation?.rows.count == 1)
    }

    @Test("a failed Show earlier leaves the rows that were read successfully on screen")
    @MainActor
    func failedOlderKeepsWhatItHas() async {
        let model = JournalModel(
            api: JournalPreviewAPI(
                page: Page(items: (1...3).map { Self.entry($0) }, nextCursor: "cursor"),
                olderFails: true
            ),
            now: { Self.now }
        )

        await model.load()
        await model.loadOlder()

        #expect(model.hasFailed == false, "one page failing took the whole screen down with it")
        #expect(model.presentation?.rows.count == 3)
        #expect(model.hasFailedOlder)
    }

    @Test("Try again re-runs the journal read and clears the failure")
    @MainActor
    func retryRecovers() async {
        let reads = JournalReadCounter()
        let model = JournalModel(
            api: JournalPreviewAPI(page: Page(items: [Self.entry(1)]), failsOnce: true, reads: reads),
            now: { Self.now }
        )

        await model.load()
        #expect(model.hasFailed)

        await model.retry()
        #expect(reads.count == 2)
        #expect(model.hasFailed == false)
        #expect(model.presentation != nil)
    }

    /// The `.task` behind this segment fires on every reappearance, so a `load()` that *replaced*
    /// the list would silently discard pages the reader had asked for by pressing `Show earlier`.
    ///
    /// **It does re-read, and that is the owner's ruling rather than a regression.** A revisit
    /// paints what was there and refreshes behind it, so the assertion is on the rows and not on
    /// the read count — `JournalModel.refresh()` reconciles a fresh page one against the deeper
    /// pages instead of overwriting them. `JournalModelLifetimeTests` covers the reconciliation
    /// itself, including the case where something actually changed underneath.
    @Test("switching away and back does not throw away the pages already fetched")
    @MainActor
    func loadIsIdempotentOnceLoaded() async {
        let reads = JournalReadCounter()
        let model = JournalModel(
            api: JournalPreviewAPI(
                page: Page(items: (1...3).map { Self.entry($0) }, nextCursor: "cursor"),
                older: Page(items: (4...5).map { Self.entry($0) }),
                reads: reads
            ),
            now: { Self.now }
        )

        await model.load()
        await model.loadOlder()
        let five = model.presentation?.rows.map(\.id)
        #expect(five?.count == 5)

        await model.load()
        #expect(reads.count == 3, "returning to the segment did not refresh behind the list")
        #expect(
            model.presentation?.rows.map(\.id) == five,
            "the earlier page the reader asked for was discarded"
        )
    }

    // MARK: - The export, given an entrance at last

    /// `exportLatest` has been finished, tested and callable since ERRATA E39, and its only caller
    /// was a test file. Its own doc comment names the **account-data request**, so a subject-access
    /// export with no surface is a privacy commitment nobody can invoke.
    ///
    /// What is asserted here is that each of the two share payloads really carries its own format
    /// through to the API — the failure this shape is prone to is one control quietly exporting the
    /// other one's bytes, which is why the two are separate `Transferable` types at all.
    /// **Built from the row's own payloads, not from payloads the test wrote.**
    ///
    /// The version this replaces constructed `JournalCSVExport { try await api.exportLatest(.csv) }`
    /// in the test body and asserted it came back with CSV. That proves `.csv` returns CSV, which
    /// nothing threatened. It says nothing about the row, and it was proved to say nothing: swapping
    /// the two `ShareLink` arguments in `JournalExportRows` — the CSV control quietly handing over the
    /// map export's bytes, the exact failure that file's comment says the two types exist to prevent —
    /// left this assertion green. So the payloads now come from `JournalExportRows.payloads`, which is
    /// what the body itself builds, and the format each one asks for is what is recorded.
    @Test("each export row asks for its own format, not the other row's")
    func exportsCarryTheirFormat() async throws {
        let asked = FormatRecorder()
        let payloads = JournalExportRows.payloads { format in
            asked.record(format)
            return Data(format.rawValue.utf8)
        }

        #expect(try await payloads.csv.load() == Data(ExportFormat.csv.rawValue.utf8))
        #expect(try await payloads.geoJSON.load() == Data(ExportFormat.geojson.rawValue.utf8))
        #expect(asked.formats == [.csv, .geojson], "a row asked the API for the other row's format")
    }

    /// **The bytes as the system fetches them, through the `TransferRepresentation` itself.**
    ///
    /// Every other assertion here calls `load()` directly, which is the closure and not the path a
    /// share sheet takes: the sheet resolves the payload through `transferRepresentation`, and a
    /// representation whose body returned `Data()` would hand over an empty file while every
    /// `load()`-based assertion stayed green. `NSItemProvider.register` plus a read of the registered
    /// type is the same round trip, so this is the one test here that would notice.
    @Test("the share sheet's own round trip returns the file, not an empty one")
    func theTransferRepresentationCarriesTheBytes() async throws {
        let payloads = JournalExportRows.payloads { format in Data("body:\(format.rawValue)".utf8) }

        let csvProvider = NSItemProvider()
        csvProvider.register(payloads.csv)
        let csvBytes = try await Self.data(from: csvProvider, ofType: UTType.commaSeparatedText.identifier)
        #expect(csvBytes == Data("body:csv".utf8), "the share sheet would have received the wrong file")

        let geoProvider = NSItemProvider()
        geoProvider.register(payloads.geoJSON)
        let geoBytes = try await Self.data(from: geoProvider, ofType: UTType.json.identifier)
        #expect(geoBytes == Data("body:geojson".utf8))
    }

    /// Records which formats the export closure was asked for, in order. A locked class rather than
    /// an actor for the reason `JournalReadCounter` gives.
    final class FormatRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var value: [ExportFormat] = []

        var formats: [ExportFormat] {
            lock.lock()
            defer { lock.unlock() }
            return value
        }

        func record(_ format: ExportFormat) {
            lock.lock()
            defer { lock.unlock() }
            value.append(format)
        }
    }

    /// Pulls the registered representation's bytes back out, which is what a share sheet does.
    static func data(from provider: NSItemProvider, ofType type: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: type) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: data ?? Data())
                }
            }
        }
    }

    @Test("the two formats are named apart, in the label and in the file that lands")
    func exportNamesAreDistinct() {
        #expect(JournalCopy.exportAction(.csv) != JournalCopy.exportAction(.geojson))
        #expect(JournalCopy.exportFileName(.csv).hasSuffix(".csv"))
        #expect(JournalCopy.exportFileName(.geojson).hasSuffix(".geojson"))
        // Every format the API offers has a row. A third format added to `ExportFormat` without a
        // label would otherwise ship as a control with no name on it.
        let everyFormatNamed = ExportFormat.allCases.allSatisfy { !JournalCopy.exportAction($0).isEmpty }
        #expect(everyFormatNamed)
    }

    /// **The bytes the button hands over are the real export, over a real store.**
    ///
    /// The two assertions above use a double, so they prove the wiring and nothing about the
    /// content. This one goes through `LocalAPI` against an actual database with an actual
    /// contribution in it, and reads the file the share sheet would receive. A `ShareLink` that
    /// hands over zero bytes looks exactly like one that works until somebody opens the file.
    @Test("the export button's bytes are this device's real contributions, not an empty document")
    func exportPayloadIsReal() async throws {
        let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-0000000000B1")!
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: deviceID)
        let tree = try await api.addTree(
            TreeDraft(
                coordinate: Coordinate(latitude: 37.7761, longitude: -122.4464),
                photoLocalPath: "/tmp/cypress-export-row-test.jpg",
                attribution: Attribution.anonymous(deviceID: deviceID)
            )
        )
        try await store.queue.write { connection in
            try ContributionStore().insert(
                Visit(
                    treeID: tree.id,
                    attribution: Attribution.anonymous(deviceID: deviceID),
                    note: "Fog on the crown",
                    capturedAt: Self.now
                ),
                connection: connection
            )
        }

        // Exactly the closure `RootView` hands the You tab, wrapped in exactly the payloads the
        // row builds — `payloads`, not a pair the test wrote, so the format each control asks for is
        // part of what is under test here too.
        let payloads = JournalExportRows.payloads { [api] format in try await api.exportLatest(format) }
        let bytes = try await payloads.csv.load()
        let text = try #require(String(data: bytes, encoding: .utf8))

        #expect(!bytes.isEmpty, "the share sheet would have received an empty file")
        // The CSV's own header, so this asserts a spreadsheet rather than merely "some bytes
        // mentioning the note". Without it, the GeoJSON document satisfies every line below —
        // which it did, when the CSV row was made to ask for the other format.
        #expect(
            text.contains("kind,tree_id,captured_at,summary,verification_state"),
            "the row named a spreadsheet and handed over something else"
        )
        #expect(text.contains("Fog on the crown"), "the contribution this device made is not in its own export")
        #expect(text.contains(tree.id.uuidString), "the export names no tree")
        // D12: the disclaimer and the verification state travel with it.
        #expect(text.contains(StructureFlag.disclaimer))
        #expect(text.contains(VerificationState.unverified.rawValue))

        let root = try #require(
            try JSONSerialization.jsonObject(with: try await payloads.geoJSON.load()) as? [String: Any]
        )
        let features = try #require(root["features"] as? [[String: Any]])
        #expect(features.count == 1, "the map export carried no features")
    }

    // MARK: - The failure sentence

    /// The same rule E126 wrote for screens 08 and 12, applied to the third screen of that shape
    /// before it has a chance to become the fourth defect.
    @Test("the failure sentence says the read failed and claims nothing about the journal")
    func failureCopyStatesOneFact() {
        #expect(JournalCopy.loadFailed.hasSuffix("."))
        for forbidden in ["yet", "nothing", "empty", "quiet"] {
            #expect(
                JournalCopy.loadFailed.lowercased().contains(forbidden) == false,
                "\(JournalCopy.loadFailed) reads as a statement about the subject, not about the read"
            )
        }
        #expect(JournalCopy.loadRetry == "Try again")
    }

    // MARK: - The almanac's entrance (ERRATA E57, and not reopening it)

    /// **The one thing this round could have broken silently.**
    ///
    /// `Route.almanac` has no `push` call site anywhere in the app; the Journal tab is screen 12's
    /// only entrance. A journal that took the tab for itself would have removed a finished screen
    /// from the product without deleting a line of its code, and every other test here would still
    /// have passed. So the tab's segment list is asserted to still contain the almanac.
    @Test("the Journal tab still contains the almanac, which has no other way in")
    func theAlmanacKeepsItsOnlyEntrance() {
        #expect(JournalSegment.allCases.contains(.almanac))
        #expect(JournalSegment.allCases.contains(.journal))
        // Named apart, so neither segment's label is the other's.
        #expect(JournalSegment.journal.label != JournalSegment.almanac.label)
    }
}
