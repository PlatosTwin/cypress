import Foundation
import Testing
@testable import Cypress

/// **What `LocalAPI.journal()` actually runs, counted from inside the database.**
///
/// Every other gate in this round asks a question this one does not. `JournalQueryPlanTests`
/// explains the *text* of four statements; `JournalBatchReadTests` compares *answers*. PR #143's
/// review showed by experiment that neither can see the two things the change is about:
///
/// 1. it appended `" -- drift"` to the string `ContributionStore.journal` hands to
///    `cachedStatement`, so the app ran a statement the plan gate had never seen, and the whole
///    unit suite stayed green. Referencing `ContributionStore.journalSQL` from a test makes the
///    *property* exist; it does not make the property be what runs.
/// 2. it put the per-tree N+1 loop back into `journal()` — the defect this change exists to
///    remove — and the suite stayed green, because the loop and the batch answer identically. That
///    is the whole point of the batch, so no answer-comparing test can ever catch it.
///
/// `StatementCensus` closes both by recording prepares and queue hops as they happen. A gate over
/// it is bound to executed text, and to how many times each text executed.
///
/// ── What is pinned, exactly ─────────────────────────────────────────────────────────────────
/// **Two hops onto the queue, and five statements, one execution each** — whatever the page holds.
/// Five and not four: `heroPhotoIDs(treeIDs:attribution:)` is two statements, the candidates and
/// the vote tallies, and the tallies are skipped when no candidate survives. The fixture below
/// carries photographs precisely so all five run and the count is not quietly four.
///
/// Both halves matter and they fail differently. The set catches drift — a statement whose text
/// changed without this file changing. The count catches an N+1 — a statement whose text is still
/// explained but which now runs once per row.
@Suite("Journal · what the page actually runs")
struct JournalStatementCensusTests {

    private static let deviceID = UUID(uuidString: "9E00B47C-0000-4000-8000-000000000253")!
    private static let moment = Date(timeIntervalSince1970: 1_780_000_000)

    private static func photoDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cypress-journal-census-\(UUID().uuidString)", isDirectory: true)
    }

    /// A page drawn from **several distinct trees**, some with photographs.
    ///
    /// The distinct-tree count is load-bearing: a page whose rows are all one tree would run one
    /// name lookup either way, so the N+1 and the batch would be indistinguishable and this gate
    /// would pass on the defect. Eight trees, two rows each.
    private static func seeded() async throws -> (api: LocalAPI, store: CypressStore, trees: [UUID]) {
        let url = try #require(InventoryContractTests.seedURL, "no seed database; set CYPRESS_SEED_PATH")
        let store = try await CypressStore.inMemory(seedURL: url)
        let api = LocalAPI(store: store, deviceID: deviceID, photoDirectory: photoDirectory())

        let candidates = try await api.treesNear(
            Coordinate(latitude: 37.7694, longitude: -122.4862), radiusM: 1500, limit: 200
        )
        let trees = Array(candidates.prefix(8)).map(\.tree.id)
        try #require(trees.count == 8, "the fixture needs eight distinct seed trees, got \(trees.count)")

        let attribution = await api.attribution
        for (index, tree) in trees.enumerated() {
            for repetition in 0..<2 {
                try await store.queue.write { connection in
                    try ContributionStore().insert(
                        Visit(
                            treeID: tree,
                            attribution: attribution,
                            capturedAt: moment.addingTimeInterval(-Double(index * 2 + repetition) * 3600)
                        ),
                        connection: connection
                    )
                }
            }
            // Photographs on half of them, so the tally statement has candidates to tally and the
            // fifth statement is genuinely reached.
            if index < 4 { _ = try await api.debugSeedPhotos(treeID: tree, count: 2) }
        }
        return (api, store, trees)
    }

    /// The five statements a page runs, read off the types the app reads them off.
    private static func expected(_ store: CypressStore) throws -> [String] {
        let schema = try #require(store.seed, "the store opened without a seed attached")
        let trees = TreeQueries(schema: schema, seedHasSoftDeletedTrees: store.seedHasSoftDeletedTrees)
        return [
            ContributionStore.journalSQL,
            trees.treesSQL(),
            ContributionStore.activeNamesSQL,
            ContributionStore.scopedHeroPhotoCandidatesSQL,
            ContributionStore.scopedHeroPhotoTalliesSQL
        ]
    }

    // MARK: - The gate

    @Test("one journal page is two queue hops and five statements, each run exactly once")
    func thePageRunsTwoHopsAndFiveStatementsOnce() async throws {
        let (api, store, _) = try await Self.seeded()
        let expected = try Self.expected(store)

        let census = StatementCensus()
        await store.queue.installCensus(census)
        let page = try await api.journal(cursor: nil, limit: JournalLimits.pageSize)
        await store.queue.installCensus(nil)

        // The fixture has to have produced a page over several trees, or the counts below are
        // counting an empty read.
        try #require(page.items.count == 16, "the fixture produced \(page.items.count) rows, not 16")
        try #require(
            Set(page.items.map(\.treeID)).count == 8,
            """
            the page covers \(Set(page.items.map(\.treeID)).count) distinct trees, so an N+1 and \
            a batch would be indistinguishable here
            """
        )

        let ran = census.statements
        #expect(
            census.readCount == 2,
            """
            `journal()` made \(census.readCount) hops onto the database queue for one page over 8 \
            distinct trees, not 2. One hop per tree is the N+1 this change removed — see \
            `LocalAPI.journal()`'s header, whose "two round-trips" this asserts
            """
        )
        #expect(
            ran.count == expected.count,
            """
            \(ran.count) statements ran for one page, not \(expected.count). A statement running \
            more than once per page is an N+1 whatever its text says: \
            \(Self.histogram(ran))
            """
        )
        #expect(
            Set(ran) == Set(expected),
            """
            the page ran statements this repository does not explain, or stopped running ones it \
            does. Unexplained: \(Self.label(Set(ran).subtracting(expected))). Explained but not \
            run: \(Self.label(Set(expected).subtracting(ran))). `JournalQueryPlanTests` reads the \
            five texts off the same properties, so a text that drifts from the app is caught here \
            rather than left explained forever
            """
        )
    }

    /// **`Show earlier` costs the same as the first page**, which is the half a first-paint-only
    /// gate would miss: a per-row read added to the paging path is paid on every press.
    @Test("Show earlier is also two hops and five statements")
    func theSecondPageCostsTheSame() async throws {
        let (api, store, _) = try await Self.seeded()
        let expected = try Self.expected(store)

        let first = try await api.journal(cursor: nil, limit: 8)
        let cursor = try #require(first.nextCursor, "the fixture produced no second page to ask for")

        let census = StatementCensus()
        await store.queue.installCensus(census)
        let second = try await api.journal(cursor: cursor, limit: 8)
        await store.queue.installCensus(nil)

        try #require(!second.items.isEmpty, "the second page came back empty")
        #expect(census.readCount == 2, "a later page cost \(census.readCount) hops")
        #expect(
            census.statements.count == expected.count,
            "a later page ran \(census.statements.count) statements: \(Self.histogram(census.statements))"
        )
        #expect(Set(census.statements) == Set(expected))
    }

    /// **The calibration: the census can see an N+1, and reports the shape of one.**
    ///
    /// Without this the two tests above could both be passing because the census records nothing.
    /// `displayNames(for:)`'s per-id predecessor is still in the codebase as
    /// `displayNameIfPresent(for:)`, so the loop this change removed can be run for real — and it
    /// has to come back as one hop and one `treeSQL()` per tree, against the batch's one of each.
    @Test("the census reports the per-tree loop as the per-tree loop")
    func theCensusSeesAnNPlusOne() async throws {
        let (api, store, trees) = try await Self.seeded()

        let census = StatementCensus()
        await store.queue.installCensus(census)
        for id in trees { _ = try await api.displayNameIfPresent(for: id) }
        await store.queue.installCensus(nil)

        #expect(
            census.readCount == trees.count,
            """
            eight per-tree lookups were recorded as \(census.readCount) hops. If this is not 8 the \
            census is not counting, and the two gates above prove nothing
            """
        )
        let schema = try #require(store.seed)
        let oneTree = TreeQueries(schema: schema, seedHasSoftDeletedTrees: store.seedHasSoftDeletedTrees)
            .treeSQL()
        #expect(
            census.statements.filter { $0 == oneTree }.count == trees.count,
            """
            the single-tree projection ran \(census.statements.filter { $0 == oneTree }.count) \
            times for eight trees. That count is exactly what the batched form reduces to one, and \
            a census that cannot see it cannot see the defect either
            """
        )

        // …and the batched form, on the same trees, on the same census.
        census.reset()
        await store.queue.installCensus(census)
        _ = await api.displayNames(for: trees)
        await store.queue.installCensus(nil)
        #expect(census.readCount == 1, "the batched form took \(census.readCount) hops for eight trees")
        #expect(
            census.statements.filter { $0 == oneTree }.isEmpty,
            "the batched form still runs the single-tree projection"
        )
    }

    // MARK: - Failure text

    private static func histogram(_ statements: [String]) -> String {
        Dictionary(grouping: statements, by: { $0 })
            .map { "\($0.value.count)× \(firstLine(of: $0.key))" }
            .sorted()
            .joined(separator: "; ")
    }

    private static func label(_ statements: Set<String>) -> String {
        statements.isEmpty ? "none" : statements.map(firstLine(of:)).sorted().joined(separator: "; ")
    }

    /// A statement's first non-empty line, so a failure names it without printing a page of SQL.
    private static func firstLine(of sql: String) -> String {
        sql.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty }) ?? "<empty>"
    }
}
