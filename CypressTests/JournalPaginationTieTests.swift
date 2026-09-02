import Foundation
import Testing
@testable import Cypress

/// **Paging the journal must return the journal.**
///
/// The Yours segment reads its history a page at a time, and the cursor it pages on is the last
/// row's `captured_at`. That is a *partial* order: `captured_at` is not unique, and two
/// contributions recorded in the same millisecond are ordinary — a walk where somebody taps
/// through three trees, an import, a check-in and a measurement saved together. When a run of rows
/// sharing one `captured_at` straddles a page boundary, the strict `captured_at < :cursor` the next
/// page asks with steps over **every remaining row of that run**. They are not shown later; they
/// are not shown at all. Nothing on screen says a row is missing, because nothing on screen knows.
///
/// Two facts make this worth a gate of its own rather than a paragraph:
///
/// 1. **it is silent.** A dropped row is indistinguishable from a row that was never written, and
///    the list this happens to is the contributor's own record of what they did. `Export` follows
///    the same cursor (`LocalAPI.wholeJournal`), so a subject-access request comes back short for
///    the same reason and equally quietly — the shape ERRATA E39 already caught once, from a
///    different cause;
/// 2. **which rows a page shows is a property of the query plan, not of the data.** Within a tie
///    the old ordering had nothing to break on, so SQLite was free to return the tied rows in
///    whatever order the plan produced them. An index round changes plans. That means an
///    *optimization* could change what a person reads, which is not a trade this project gets to
///    make silently.
///
/// The fix is a total order — `ORDER BY captured_at DESC, id COLLATE NOCASE DESC`, with the cursor
/// carrying the pair — so that "the row after this one" is a fact about the row rather than about
/// the plan. **The collation is part of the fix and not a flourish**; `theCursorIsCaseSafe` is the
/// second defect of this exact shape, found in review, and its own comment carries the argument.
///
/// ── What this file asserts, and why it is a comparison ──────────────────────────────────────
/// Every test here compares **paginating** against **one unpaginated read of the same statement**.
/// That is deliberate: it does not restate the ordering rule, so it stays true if the ordering rule
/// is ever changed on purpose, and it cannot pass by agreeing with itself — the two sides run
/// different limits through different cursor states. What it pins is the only property paging owes
/// the reader: *the pages, concatenated, are the list.*
///
/// ── Red-proof ───────────────────────────────────────────────────────────────────────────────
/// Run against this branch's base (`ecf8879`, PR #143 merged), **two of the five tests fail with
/// two issues each**, and the counts are the measured ones:
///
/// - `pagingAcrossATieDropsNothing`: 40 rows written, 40 read unpaginated, **32** read across
///   pages. Page one ends four rows into the twelve-row tie, the cursor carries that timestamp,
///   and the strict `<` steps over the remaining **8**. It fails on `dropped.isEmpty` and again on
///   the sequence comparison;
/// - `theExportIsNotTruncatedByATie`: 240 rows written, **232** in the CSV — the same 8, at the
///   `Page.maximumLimit` boundary `wholeJournal` pages on.
///
/// Two of the remaining three pass on that build and say in their own comments why: one asserts the
/// fixture, one is the negative control. The tie itself is asserted by
/// `theFixtureReallyStraddlesAPageBoundary`, so a fixture that stopped containing one would fail
/// loudly rather than let the pair above pass vacuously.
///
/// The fifth, `theCursorIsCaseSafe`, is about a different precondition and has its own red-proof
/// against the BINARY tie-break — see its comment. It passes on `ecf8879` for a reason worth
/// stating: that build had no tie-break at all, so there was no collation to get wrong yet.
@Suite("Journal · paging across a tie")
struct JournalPaginationTieTests {

    private static let deviceID = UUID(uuidString: "9E00B47C-0000-4000-8000-000000000519")!

    /// The page size these tests page at. Small, so a tie can straddle a boundary without writing
    /// hundreds of rows, and not `JournalLimits.pageSize` — the defect is about the boundary, not
    /// about any particular page size.
    private static let pageSize = 10

    /// How many rows share one `captured_at`. More than `pageSize` on purpose: the run cannot fit
    /// inside a single page, so it must straddle a boundary however the page falls.
    private static let tieWidth = 12

    /// See `JournalBatchReadTests.photoDirectory()` — an in-memory store's `databaseURL` resolves
    /// to the root of a read-only volume, so the photo directory has to be a real one.
    private static func photoDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cypress-journal-tie-\(UUID().uuidString)", isDirectory: true)
    }

    private static func openSeeded() async throws -> (api: LocalAPI, store: CypressStore) {
        let url = try #require(InventoryContractTests.seedURL, "no seed database; set CYPRESS_SEED_PATH")
        let store = try await CypressStore.inMemory(seedURL: url)
        return (LocalAPI(store: store, deviceID: deviceID, photoDirectory: photoDirectory()), store)
    }

    /// A history whose middle is one run of rows sharing a single `captured_at`.
    ///
    /// Written as rows through `ContributionStore.insert` rather than through the capture screens,
    /// for `PhotoProvenanceTests`' reason: what is under test is what the reader gets back out, and
    /// a fixture that can only be built by the UI cannot express the state that breaks it.
    ///
    /// By default the tie sits at rows 6…17 of 40, so with `pageSize` 10 it opens inside page one
    /// and closes inside page two — the exact geometry the cursor cannot express. `tieStart` is a
    /// parameter because the export pages at `Page.maximumLimit`, not at `pageSize`, and has to be
    /// handed a tie straddling *its* boundary to be tested at all.
    @discardableResult
    private static func seedHistory(
        api: LocalAPI,
        store: CypressStore,
        total: Int = 40,
        tieStart: Int = 6
    ) async throws -> [UUID] {
        let tree = UUID(uuidString: "F0000000-0000-4000-8000-00000000051A")!
        let attribution = await api.attribution
        let newest = Date(timeIntervalSince1970: 1_780_000_000)
        let tieMoment = newest.addingTimeInterval(-Double(tieStart) * 60)

        var written: [UUID] = []
        try await store.queue.write { connection in
            let contributions = ContributionStore()
            for index in 0..<total {
                let capturedAt: Date
                if index >= tieStart && index < tieStart + tieWidth {
                    capturedAt = tieMoment
                } else {
                    capturedAt = newest.addingTimeInterval(-Double(index) * 60)
                }
                let record = Visit(
                    treeID: tree,
                    attribution: attribution,
                    note: "row \(index)",
                    capturedAt: capturedAt
                )
                try contributions.insert(record, connection: connection)
                written.append(record.id)
            }
        }
        return written
    }

    /// Reads the whole journal a page at a time, exactly as `Show earlier` does.
    ///
    /// Bounded by `maxPages` rather than by `while cursor != nil` so a cursor that stops advancing
    /// fails as a wrong answer instead of hanging the suite.
    private static func paginate(
        _ api: LocalAPI,
        limit: Int = pageSize,
        maxPages: Int = 20
    ) async throws -> [JournalEntry] {
        var seen: [JournalEntry] = []
        var cursor: String?
        for _ in 0..<maxPages {
            let page = try await api.journal(cursor: cursor, limit: limit)
            seen.append(contentsOf: page.items)
            guard let next = page.nextCursor else { return seen }
            cursor = next
        }
        return seen
    }

    // MARK: - The fixture, asserted before anything is concluded from it

    /// **The rows this file writes really do tie, and the tie really does cross a page boundary.**
    ///
    /// Without this, a change that made `capturedAt` unique — a jittered fixture, a rounded
    /// timestamp column — would leave every test below passing over data that cannot exhibit the
    /// defect they exist to catch. That is this project's dominant test failure: a guard that stays
    /// green because the case it guards stopped being present.
    @Test("the fixture writes a run of tied rows that crosses a page boundary")
    func theFixtureReallyStraddlesAPageBoundary() async throws {
        let (api, store) = try await Self.openSeeded()
        try await Self.seedHistory(api: api, store: store)

        let all = try await api.journal(cursor: nil, limit: Page<JournalEntry>.maximumLimit)
        let counts = Dictionary(grouping: all.items, by: \.capturedAt).mapValues(\.count)
        let widest = counts.values.max() ?? 0
        #expect(
            widest == Self.tieWidth,
            """
            the widest run of rows sharing one capturedAt is \(widest), not \(Self.tieWidth). The \
            fixture no longer contains the state these tests are about, so nothing below proves \
            anything — counts: \(counts.values.sorted(by: >).prefix(4))
            """
        )
        #expect(
            widest > Self.pageSize,
            """
            the tie is \(widest) rows and a page is \(Self.pageSize), so the run can fit inside one \
            page and need not straddle a boundary
            """
        )

        // And it opens before the first boundary: the first page's last row is inside the tie.
        let firstPage = try await api.journal(cursor: nil, limit: Self.pageSize)
        let lastOfPageOne = try #require(firstPage.items.last, "page one came back empty")
        #expect(
            counts[lastOfPageOne.capturedAt] == Self.tieWidth,
            """
            page one's last row is not inside the tie, so the boundary this file is about is not \
            where the fixture puts it — it ends at \(lastOfPageOne.capturedAt)
            """
        )
    }

    // MARK: - The defect

    /// **Every row written comes back, exactly once, in the order one unpaginated read gives.**
    ///
    /// The two sides are the same statement at different limits, so this asserts the property and
    /// not the ordering rule: change the ordering deliberately and both sides move together;
    /// break paging and only one does.
    @Test("paging the whole journal returns the whole journal, in the unpaginated order")
    func pagingAcrossATieDropsNothing() async throws {
        let (api, store) = try await Self.openSeeded()
        let written = try await Self.seedHistory(api: api, store: store)

        let unpaginated = try await api.journal(
            cursor: nil, limit: Page<JournalEntry>.maximumLimit
        ).items
        try #require(
            unpaginated.count == written.count,
            """
            one unpaginated read returned \(unpaginated.count) of the \(written.count) rows \
            written, so the comparison below would be against a short list rather than the journal
            """
        )

        let paged = try await Self.paginate(api)

        let pagedIDs = paged.map(\.id)
        let dropped = Set(unpaginated.map(\.id)).subtracting(pagedIDs)
        let repeated = Set(pagedIDs.filter { id in pagedIDs.filter { $0 == id }.count > 1 })

        #expect(
            dropped.isEmpty,
            """
            paging dropped \(dropped.count) of \(unpaginated.count) rows — they are in the journal \
            and no page shows them. A run of rows sharing one capturedAt straddles a page boundary, \
            and a cursor that carries only the timestamp cannot ask for "the rest of that run"
            """
        )
        #expect(
            repeated.isEmpty,
            "paging returned \(repeated.count) rows more than once, so a page overlapped its predecessor"
        )
        #expect(
            pagedIDs == unpaginated.map(\.id),
            """
            the pages concatenated are not the unpaginated list: \(pagedIDs.count) rows across \
            pages against \(unpaginated.count) in one read. Order and membership are both asserted \
            here because a tie with no tie-break can change either
            """
        )
    }

    // MARK: - The same defect, one layer down

    /// **A tie-break is only a total order if both sides agree about case.**
    ///
    /// This is PR #146's review finding, and it is the file's own defect class under a precondition
    /// nobody had written down. `UUID.uuidString` is always upper case, so the cursor `LocalAPI`
    /// re-emits is upper case. Nothing in `AppSchema` constrains the case of a stored `id` — this
    /// suite's sibling `SchemaV19Tests` writes lower-case ones on purpose — and under BINARY every
    /// upper-case hex letter (0x41–0x46) sorts *below* its lower-case twin (0x61–0x66). So a
    /// lower-case row is "greater than" the upper-case cursor that was made from a row above it,
    /// `id < :cursorID` excludes it, and it is dropped exactly as the timestamp-only cursor dropped
    /// ties.
    ///
    /// **Rows written as rows, and lower case on purpose.** `ContributionStore.insert` takes a
    /// `Visit` whose `id` is a `UUID`, so the shipping write path physically cannot produce the
    /// state under test — the case is lost at the type. Going around it is the only way to express
    /// a database this app can encounter but not currently create, which is the same argument
    /// `SchemaV19Tests` makes for its own fixture.
    ///
    /// **Red-proof, measured.** With the three `COLLATE NOCASE` declarations removed — the index's,
    /// the `ORDER BY`'s and the row value's — this fails with two issues and the paging returns
    /// **1 of 3**:
    ///
    ///     Expectation failed: (paged.map(\.id) → [F1111111-…])
    ///       == (unpaginated.map(\.id) → [F1111111-…, E2222222-…, D3333333-…])
    ///
    /// and nothing else in this file moves — the other four tests stay green, because their
    /// fixtures go through `ContributionStore.insert` and get upper-case ids, which is the case a
    /// BINARY tie-break handles correctly. That is the discrimination worth having: this test is
    /// the only one that can see the precondition. `LIMIT 1` is deliberate — it makes every row a
    /// page boundary, so the tie cannot be crossed by luck.
    @Test("paging a tie is exact when the stored ids are not in the case UUID.uuidString writes")
    func theCursorIsCaseSafe() async throws {
        let (api, store) = try await Self.openSeeded()
        let tree = UUID(uuidString: "F0000000-0000-4000-8000-00000000051C")!
        let deviceID = Self.deviceID
        let moment = Date(timeIntervalSince1970: 1_780_000_000)
        let stamp = SQLiteTimestamp.string(from: moment)

        // Three rows on one capture time, ids stored LOWER case and leading with a hex letter —
        // the two properties that make BINARY and the cursor disagree.
        let ids = [
            "f1111111-1111-4111-8111-111111111111",
            "e2222222-2222-4222-8222-222222222222",
            "d3333333-3333-4333-8333-333333333333"
        ]
        try await store.queue.write { connection in
            for (index, id) in ids.enumerated() {
                try connection.execute("""
                    INSERT INTO visits (id, tree_uuid, device_id, client_uuid, note,
                                        captured_at, created_at, updated_at)
                    VALUES ('\(id)','\(tree.uuidString)','\(deviceID.uuidString)',
                            '\(UUID().uuidString)','tied \(index)','\(stamp)','\(stamp)','\(stamp)');
                    """)
            }
        }

        let stored = try await store.queue.read { connection -> [String] in
            let statement = try connection.prepare("SELECT id FROM visits")
            defer { statement.finalize() }
            return try statement.fetchAll { try $0.string("id") }
        }
        try #require(
            stored.allSatisfy { $0 == $0.lowercased() } && stored.count == ids.count,
            """
            the fixture no longer stores lower-case ids (\(stored)), so the case disagreement this \
            test is about is not present and it would pass over the wrong state
            """
        )

        // LIMIT 1: every row is a page boundary, so the tie cannot be crossed by luck.
        let paged = try await Self.paginate(api, limit: 1)
        let unpaginated = try await api.journal(
            cursor: nil, limit: Page<JournalEntry>.maximumLimit
        ).items

        #expect(
            paged.map(\.id) == unpaginated.map(\.id),
            """
            paging three tied rows one at a time returned \(paged.count) of \(unpaginated.count). \
            The cursor carries `UUID.uuidString`, which is upper case; a BINARY tie-break sorts \
            that below every lower-case id, so `id < :cursorID` excludes the rows it was added to \
            include. The collation has to match in three places — `idx_<table>_captured`, the \
            ORDER BY, and the row-value comparison
            """
        )
        #expect(
            Set(paged.map { $0.id.uuidString.lowercased() }) == Set(ids),
            "the rows returned are not the three that were written: \(paged.map(\.id))"
        )
    }

    /// **The same property with the tie sitting on the boundary itself**, rather than across it.
    ///
    /// `pageSize` rows of history in front of a `pageSize`-wide tie puts the run's first row at
    /// exactly the start of page two, so the whole run lands on one page and the strict cursor has
    /// nothing to step over. **It therefore passes on a build with the defect, and it is kept
    /// anyway as the negative control** — it is the case a fix must not break, and a fix that
    /// over-corrected by making the cursor inclusive would return the tie twice and fail here on
    /// the repeat. Stated because a test whose only recorded behavior is passing proves nothing
    /// about the instrument.
    @Test("paging is exact when a tie begins precisely at a page boundary")
    func pagingWithATieOnTheBoundaryDropsNothing() async throws {
        let (api, store) = try await Self.openSeeded()
        let tree = UUID(uuidString: "F0000000-0000-4000-8000-00000000051B")!
        let attribution = await api.attribution
        let newest = Date(timeIntervalSince1970: 1_780_000_000)
        let tieMoment = newest.addingTimeInterval(-Double(Self.pageSize) * 60)

        try await store.queue.write { connection in
            let contributions = ContributionStore()
            for index in 0..<Self.pageSize {
                try contributions.insert(
                    Visit(
                        treeID: tree,
                        attribution: attribution,
                        note: "head \(index)",
                        capturedAt: newest.addingTimeInterval(-Double(index) * 60)
                    ),
                    connection: connection
                )
            }
            for index in 0..<Self.pageSize {
                try contributions.insert(
                    Visit(
                        treeID: tree,
                        attribution: attribution,
                        note: "tie \(index)",
                        capturedAt: tieMoment
                    ),
                    connection: connection
                )
            }
        }

        let unpaginated = try await api.journal(
            cursor: nil, limit: Page<JournalEntry>.maximumLimit
        ).items
        let paged = try await Self.paginate(api)
        #expect(
            paged.map(\.id) == unpaginated.map(\.id),
            """
            a tie beginning exactly at a page boundary is paged as \(paged.count) rows against \
            \(unpaginated.count) in one read
            """
        )
    }

    /// **The export follows the same cursor, so it inherits the same answer.**
    ///
    /// `LocalAPI.wholeJournal` is private and reached through `exportLatest(.csv)`, which is D12's
    /// subject-access route. E39 is the record of what a short export costs: the person holding it
    /// cannot tell it is short. This asserts the row count in the CSV against the row count in the
    /// database rather than against a page.
    ///
    /// **The fixture is 240 rows with the tie at 96…107, not the 40 the tests above use**, because
    /// the export pages at `Page.maximumLimit` — 100 — and a 40-row history comes back in one page
    /// with no cursor at all. Written at 40 rows this test passes on a build with the defect,
    /// having exercised no boundary. Its red-proof count is at the bottom of this file's header.
    @Test("the CSV export carries every row, not every row up to the first tie")
    func theExportIsNotTruncatedByATie() async throws {
        let (api, store) = try await Self.openSeeded()
        let written = try await Self.seedHistory(
            api: api, store: store, total: 240, tieStart: Page<JournalEntry>.maximumLimit - 4
        )

        let csv = String(decoding: try await api.exportLatest(.csv), as: UTF8.self)
        // Two header lines — the structure-flag disclaimer and the column names — then one line per
        // row. The notes this fixture writes carry no comma, quote or newline, so `csvEscape` adds
        // nothing and a line count is a row count here.
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: true)
        #expect(
            lines.count == written.count + 2,
            """
            the export holds \(lines.count - 2) rows against \(written.count) written. An export \
            that stops early is worse than one that fails — nothing in the file says it is short \
            (ERRATA E39's rule, reached here through a tie rather than through a dropped cursor)
            """
        )
    }
}
