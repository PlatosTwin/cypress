//
//  GroveStatementCensusTests.swift
//  CypressTests
//
//  **Two censuses over one read, and they answer different questions.** They arrived on two
//  branches in the same round and are unioned here rather than reconciled, because neither
//  contains the other:
//
//  - `GroveStatementCensusTests` asks what the **unbounded** `grove()` runs — two queue hops and
//    seven statements, each exactly once, every one of them pinned to the property that names it.
//    It is the gate that would catch an N+1 coming back, and no answer-comparing test can.
//  - `GrovePagedStatementCensusTests` asks whether the **first page** avoids building the whole
//    projection. That is invisible to the suite above by construction: a `grove()` cut to fifty
//    runs exactly the same seven statements as a `grove()`, which is the whole reason paging
//    needed a gate of its own.
//
//  Deleting either one leaves a real regression unguarded, so both are here. They share a subject
//  and nothing else — separate fixtures, separate device ids, separate helpers.
//

import Foundation
import Testing
@testable import Cypress

/// **What `LocalAPI.grove()` actually runs, counted from inside the database.**
///
/// The Trees pill of My Grove is the screen `grove()` draws, and its read is the one this
/// repository has already had to de-N+1 twice: `treeSQL()` once per tree through `treeProfile(id:)`
/// (13–22 s for a forty-tree grove, recorded in `LocalAPI.grove()`'s own header) and the unscoped
/// `heroPhotoIDs()` sweeping the whole photo library (#176). Both are now batched, and *nothing that
/// compares answers can tell whether they still are* — a per-tree loop and a batched read return the
/// same grove by construction, which is the entire reason the batch was allowed to replace the loop.
///
/// This is the grove analogue of `JournalStatementCensusTests`, and it exists for the two failures
/// that file records from PR #143's review, both demonstrated on a fully green suite:
///
/// 1. a statement's *text* can drift out from under a gate that names the property it is built
///    from — referencing `ContributionStore.journalSQL` makes the property exist, it does not make
///    the property be what runs;
/// 2. the N+1 can be put back and every answer-comparing test stays green.
///
/// `StatementCensus` closes both by recording prepares and queue hops as they happen, so a gate over
/// it is bound to executed text and to how many times each text executed.
///
/// ── What is pinned, exactly ─────────────────────────────────────────────────────────────────
/// **Two hops onto the queue, and seven statements, one execution each.** `grove()` is written as
/// two `store.queue.read` closures and the split is deliberate — the first names the trees (and can
/// only scope the photo reads once it has), the second resolves those names against the two
/// inventories. Seven statements, in the order they run:
///
///   hop 1 — `groveTreeIDs`, `groveRecords`, and `heroPhotoIDs(treeIDs:)`, which is **two**
///           statements (the candidates and the vote tallies);
///   hop 2 — `TreeQueries.trees(ids:)`, `CommunityTreeStore.trees(ids:)`, `activeNames(treeIDs:)`.
///
/// The tallies statement is skipped when no candidate survives — `heroPhotoIDs(treeIDs:)` returns
/// early on an empty `photos` fetch — so the fixture puts photographs on every tree precisely so the
/// count is seven and not quietly six. That is the mistake `JournalStatementCensusTests.seeded()`
/// records making, and it is the same method's early return that causes it.
///
/// Both halves matter and they fail differently. The count catches an N+1 — a statement that now
/// runs once per row, whatever its text says. The set catches drift — a statement whose text changed
/// without this file changing.
///
/// ── How the expected texts are obtained: off the properties, all seven ─────────────────────────
/// **This file used to derive four of the seven by probe, and no longer does.** The probe ran the
/// store's own methods under a second census and took whatever they prepared, because four of the
/// texts lived as string literals inside those methods and there was no property to hold them to.
/// It certified that `grove()` ran the store's statements and no others; what it could not certify,
/// and its header said so, was that a store method's own text had not changed — a rewrite moved
/// probe and app together.
///
/// The three ways to write this test are still three (PR #147's review, F4): copy the literals into
/// the test, which is the gate PR #143's review disproved — a test explaining its own copy; probe,
/// which is what this file did; or **hoist the literals to named properties on the store and pin
/// the test to those**, which is what `AlmanacStatementCensusTests` does for all nine of its
/// statements. That third horn was called the better one and left unbuilt because it is a
/// production change. It is now built: `ContributionStore.groveRecordsSQL`,
/// `ContributionStore.ownHeroPhotoCandidatesSQL` and `CommunityTreeStore.treesSQL` are the hoists,
/// `ContributionStore.groveTreeIDsSQL` already existed for `GrovePagedStatementCensusTests`, and
/// the second copy of the tallies text inside `heroPhotoIDs(treeIDs:connection:)` — the production
/// defect the earlier header reported rather than fixed — is gone, so both scoped hero reads now
/// prepare `scopedHeroPhotoTalliesSQL` itself.
///
/// So `Self.expected(_:)` is a list of seven properties, read off the same types the app reads them
/// off. Every one of the seven is now a genuine drift gate: appending a comment to a store method's
/// prepared text without changing the property leaves this red, which is the specimen PR #143's
/// review used and the calibration this file is re-proved with.
///
/// **What that does not cover, stated rather than implied.** Changing a property changes the app
/// and this gate together, and is invisible here — deliberately. That is what the property *is*:
/// one text, one place. The drift this catches is the divergence between what a method prepares and
/// what the repository says it prepares, which is the only kind a census can see.
@Suite("My Grove · what the list actually runs")
struct GroveStatementCensusTests {

    private static let deviceID = UUID(uuidString: "9E00B47C-0000-4000-8000-000000000902")!
    private static let moment = Date(timeIntervalSince1970: 1_780_000_000)

    /// How many statements one grove read is allowed to be. Named so the failure text can say the
    /// number the file is about rather than repeat a literal in four places.
    private static let statementCount = 7

    private static func photoDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cypress-grove-census-\(UUID().uuidString)", isDirectory: true)
    }

    /// A grove over **several distinct trees**, each carrying photographs.
    ///
    /// The distinct-tree count is load-bearing for the same reason it is in the journal file: a
    /// grove whose rows were all one tree would run one name lookup either way, so an N+1 and a
    /// batch would be indistinguishable and this gate would pass on the defect. Eight trees.
    ///
    /// A visit is what puts a tree in the grove — `groveTreeIDs` reads the visits and favorites
    /// arms — so this is `GroveCityFileBatchTests.visit(_:api:store:)`'s idiom, one visit per tree.
    /// Photographs go on every tree so the tallies statement is genuinely reached (see the header).
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
            try await store.queue.write { connection in
                try ContributionStore().insert(
                    Visit(
                        treeID: tree,
                        attribution: attribution,
                        capturedAt: moment.addingTimeInterval(-Double(index) * 3600)
                    ),
                    connection: connection
                )
            }
            _ = try await api.debugSeedPhotos(treeID: tree, count: 2)
        }
        return (api, store, trees)
    }

    /// The seven statements a grove read runs, each read off the property that names it on its own
    /// store — see the suite header for what replacing the probe with this list buys and what it
    /// does not.
    ///
    /// Listed in the order `grove()` runs them, which is documentation rather than assertion: the
    /// gates below compare sets and per-text counts, because a census records prepares and SQLite
    /// is free to prepare a cached statement once and run it later.
    ///
    /// `TreeQueries.treesSQL()` is a function of the seed's schema, so it is built from the store's
    /// own seed rather than named — the same construction `LocalAPI` makes.
    private static func expected(_ store: CypressStore) throws -> [String] {
        let schema = try #require(store.seed, "the store opened without a seed attached")
        let treeQueries = TreeQueries(
            schema: schema, seedHasSoftDeletedTrees: store.seedHasSoftDeletedTrees
        )
        return [
            // hop 1
            ContributionStore.groveTreeIDsSQL,
            ContributionStore.groveRecordsSQL,
            ContributionStore.ownHeroPhotoCandidatesSQL,
            ContributionStore.scopedHeroPhotoTalliesSQL,
            // hop 2
            treeQueries.treesSQL(),
            CommunityTreeStore.treesSQL,
            ContributionStore.activeNamesSQL
        ]
    }

    // MARK: - The gate

    @Test("one grove read is two queue hops and seven statements, each run exactly once")
    func theGroveRunsTwoHopsAndSevenStatementsOnce() async throws {
        let (api, store, trees) = try await Self.seeded()
        let expected = try Self.expected(store)

        // The list has to still name seven statements, or the comparison below is being made
        // against a shorter list and would accept a `grove()` that had stopped running one of them.
        try #require(
            expected.count == Self.statementCount,
            """
            the properties this file names are \(expected.count) statements, not \
            \(Self.statementCount): \(Self.histogram(expected))
            """
        )

        // **"each run exactly once" is only implied by the assertions below if the seven texts are
        // distinct** (PR #147's review, F4b). `ran.count == expected.count` plus
        // `Set(ran) == Set(expected)` permits a duplicate on both sides: if a refactor made two of
        // the seven texts equal, `expected.count` would stay 7 while `Set(expected)` dropped to 6,
        // and a `ran` carrying one text twice would satisfy both. `AlmanacStatementCensusTests` has
        // the same line for the same reason.
        try #require(
            expected.count == Set(expected).count,
            """
            two of the seven statements hold the same text, so "each run exactly once" no longer \
            follows from the count and the set together: \(Self.histogram(expected))
            """
        )

        let census = StatementCensus()
        await store.queue.installCensus(census)
        let entries = try await api.grove()
        await store.queue.installCensus(nil)

        // The fixture has to have produced a grove over several trees, or the counts below are
        // counting an empty read.
        try #require(
            entries.count == trees.count,
            "the fixture produced \(entries.count) grove rows, not \(trees.count)"
        )
        try #require(
            Set(entries.map(\.treeID)).count == trees.count,
            """
            the grove covers \(Set(entries.map(\.treeID)).count) distinct trees, so an N+1 and a \
            batch would be indistinguishable here
            """
        )

        let ran = census.statements
        #expect(
            census.readCount == 2,
            """
            `grove()` made \(census.readCount) hops onto the database queue for a grove over \
            \(trees.count) distinct trees, not 2. One hop per tree is the N+1 this read was \
            rewritten to remove — see `TreeQueries.treesSQL()`'s header, which records what the \
            per-tree form cost
            """
        )
        #expect(
            ran.count == expected.count,
            """
            \(ran.count) statements ran for one grove, not \(expected.count). A statement running \
            more than once per read is an N+1 whatever its text says: \(Self.histogram(ran))
            """
        )
        #expect(
            Set(ran) == Set(expected),
            """
            the grove ran statements this repository does not explain, or stopped running ones it \
            does. Unexplained: \(Self.label(Set(ran).subtracting(expected))). Explained but not \
            run: \(Self.label(Set(expected).subtracting(ran)))
            """
        )
    }

    /// **Every one of the seven is pinned to the property that names it**, per text rather than as
    /// a set — which is what makes "each run exactly once" an assertion rather than an inference.
    ///
    /// The gate above compares `Set(ran)` against `Set(expected)` and `ran.count` against
    /// `expected.count`, and those two together imply one-execution-each only while the seven texts
    /// stay distinct (which it requires, separately). This says it directly, and says *which*
    /// statement broke when it breaks: zero means the property no longer describes what the grove
    /// runs — the drift PR #143's review demonstrated by appending a comment to a shipping
    /// statement — and more than one is a per-statement N+1.
    ///
    /// It used to cover two of the seven, because five were string literals with no property to
    /// hold them to. `ContributionStore.groveRecordsSQL`, `ownHeroPhotoCandidatesSQL` and
    /// `CommunityTreeStore.treesSQL` are this round's hoists and close that gap.
    @Test("each of the seven statements the repository names runs exactly once, off its property")
    func thePropertyBackedTextsAreTheOnesThatRun() async throws {
        let (api, store, _) = try await Self.seeded()
        let expected = try Self.expected(store)

        let census = StatementCensus()
        await store.queue.installCensus(census)
        _ = try await api.grove()
        await store.queue.installCensus(nil)

        let ran = census.statements
        for sql in expected {
            #expect(
                ran.filter { $0 == sql }.count == 1,
                """
                \(Self.firstLine(of: sql)) ran \(ran.filter { $0 == sql }.count) times for one \
                grove, not once. Zero means the property naming it no longer describes what the \
                grove runs; more than one is a statement per row. Ran: \(Self.histogram(ran))
                """
            )
        }
    }

    /// **The calibration: the census can see an N+1 on this path, and reports the shape of one.**
    ///
    /// Without this the two tests above could both be passing because the census records nothing.
    /// The loop `grove()` removed is still in the codebase as `treeProfile(id:)` — one tree, one
    /// `readConsistently`, one `treeSQL()` — and `RoutedAPI.resolvedCityFileRows` is documented as
    /// having run exactly that per row until #250. So the defect can be run for real here, and it
    /// has to come back as one hop and one `treeSQL()` per tree.
    ///
    /// The batched form on the other side is `groveCityFileRows(for:)`, which is `grove()`'s second
    /// hop exactly — the same three statements over the same ids in one `queue.read`. One hop, no
    /// `treeSQL()` at all, and `treesSQL()` once.
    @Test("the census reports the per-tree profile loop as the per-tree loop")
    func theCensusSeesAnNPlusOne() async throws {
        let (api, store, trees) = try await Self.seeded()
        let schema = try #require(store.seed, "the store opened without a seed attached")
        let queries = TreeQueries(schema: schema, seedHasSoftDeletedTrees: store.seedHasSoftDeletedTrees)
        let oneTree = queries.treeSQL()
        let manyTrees = queries.treesSQL()

        let census = StatementCensus()
        await store.queue.installCensus(census)
        for id in trees { _ = try await api.treeProfile(id: id) }
        await store.queue.installCensus(nil)

        #expect(
            census.readCount == trees.count,
            """
            \(trees.count) per-tree profile reads were recorded as \(census.readCount) hops. If \
            this is not \(trees.count) the census is not counting, and the two gates above prove \
            nothing
            """
        )
        #expect(
            census.statements.filter { $0 == oneTree }.count == trees.count,
            """
            the single-tree projection ran \(census.statements.filter { $0 == oneTree }.count) \
            times for \(trees.count) trees. That count is exactly what the batched form reduces to \
            one, and a census that cannot see it cannot see the defect either
            """
        )

        // …and the batched form, on the same trees, on the same census.
        census.reset()
        await store.queue.installCensus(census)
        _ = await api.groveCityFileRows(for: trees)
        await store.queue.installCensus(nil)

        #expect(
            census.readCount == 1,
            "the batched form took \(census.readCount) hops for \(trees.count) trees"
        )
        #expect(
            census.statements.filter { $0 == oneTree }.isEmpty,
            "the batched form still runs the single-tree projection: \(Self.histogram(census.statements))"
        )
        #expect(
            census.statements.filter { $0 == manyTrees }.count == 1,
            """
            the batched form ran the set projection \
            \(census.statements.filter { $0 == manyTrees }.count) times, not once: \
            \(Self.histogram(census.statements))
            """
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

    /// A statement's first non-empty line and its length, so a failure names it without printing a
    /// page of SQL.
    ///
    /// **The length is not decoration.** The drift this gate exists to catch is often a change too
    /// far into the text to show in a first line — the review's own specimen appended `-- drift` to
    /// the end — so without it the two halves of the failure print the same string and read as a
    /// contradiction rather than as a diff.
    private static func firstLine(of sql: String) -> String {
        let head = sql.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty }) ?? "<empty>"
        return "\(head) […\(sql.count) chars]"
    }
}


// MARK: - The paged read

/// **Every other gate on this read compares answers, and a page and a whole grove cut to a page
/// have the same answer.** `GrovePaginationTests` proves the pages concatenate to the unbounded
/// read — which is exactly what a `grove()` followed by `Array(all.prefix(50))` would also do,
/// while still building a thousand `GroveEntry`s to hand back fifty. That implementation is not
/// hypothetical: it is the protocol-extension default in `CypressAPI`, it is correct, and it is
/// what this round exists to keep off screen 08.
///
/// So the question here is not "what does the page contain" but "which statements ran, and over
/// how many trees". `StatementCensus` (#143) answers the first from the inside. The second is
/// answered by the store read itself, whose result *is* the projection's input: `LocalAPI`'s
/// projection is a `for` over `rows`, so bounding `rows` bounds the entries, the four scoped
/// statements' id lists, and the array SwiftUI is handed.
@Suite("My Grove · the first page does not build the whole grove")
struct GrovePagedStatementCensusTests {

    private static let deviceID = UUID(uuidString: "9E00B47C-0000-4000-8000-0000000002C0")!

    /// Big enough that a page is a small fraction of it — a fixture of sixty against a page of
    /// fifty would let a whole-grove read pass for a paged one.
    private static let groveSize = 180

    private static func seededGrove() async throws -> (api: LocalAPI, store: CypressStore, trees: Int) {
        let url = try #require(InventoryContractTests.seedURL, "no seed database; set CYPRESS_SEED_PATH")
        let store = try await CypressStore.inMemory(seedURL: url)
        let api = LocalAPI(store: store, deviceID: deviceID)

        let candidates = try await api.treesNear(
            Coordinate(latitude: 37.7694, longitude: -122.4862), radiusM: 1_600, limit: 400
        )
        try #require(
            candidates.count >= groveSize,
            "the seed gave \(candidates.count) trees near the fixture center; the grove needs \(groveSize)"
        )
        let ids = candidates.prefix(groveSize).map(\.tree.id)
        let attribution = await api.attribution
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        try await store.queue.write { connection in
            let contributions = ContributionStore()
            for (offset, tree) in ids.enumerated() {
                try contributions.insert(
                    Visit(
                        treeID: tree,
                        attribution: attribution,
                        capturedAt: start.addingTimeInterval(Double(60 * (offset + 1)))
                    ),
                    connection: connection
                )
            }
        }
        return (api, store, ids.count)
    }

    // MARK: - The control, which is the unbounded form

    /// **Calibration.** The census can see the unbounded statement, and does, when the unbounded
    /// read runs. Without this line the gate below — "the unbounded text did not run" — passes just
    /// as well against a census that records nothing at all.
    @Test("the census sees the unbounded id read when the unbounded read runs")
    func theCensusSeesTheUnboundedRead() async throws {
        let (api, store, trees) = try await Self.seededGrove()

        let census = StatementCensus()
        await store.queue.installCensus(census)
        let whole = try await api.grove()
        await store.queue.installCensus(nil)

        try #require(whole.count == trees, "the fixture built \(whole.count) entries, not \(trees)")
        #expect(
            census.statements.contains(ContributionStore.groveTreeIDsSQL),
            "the unbounded read did not run the unbounded statement — this census is not recording"
        )
        #expect(
            !census.statements.contains(ContributionStore.groveTreeIDsPageSQL),
            "the unbounded read ran the paged statement"
        )
    }

    // MARK: - The gate

    /// **The first page runs the bounded statement and never the unbounded one.**
    ///
    /// The two texts differ by a `WHERE` and a `LIMIT` and nothing else — they are built from one
    /// shared fragment (`ContributionStore.groveOwnedTreesSQL`) so that they cannot come to
    /// disagree about which trees are in a grove — which is what makes their *identity* a usable
    /// signal: seeing one and not the other says which read ran, and says nothing else.
    @Test("the first page runs the bounded id statement, and the unbounded one does not appear")
    func theFirstPageRunsTheBoundedStatement() async throws {
        let (api, store, trees) = try await Self.seededGrove()

        let census = StatementCensus()
        await store.queue.installCensus(census)
        let page = try await api.grovePage(cursor: nil, limit: GroveLimits.pageSize)
        await store.queue.installCensus(nil)

        try #require(
            trees > GroveLimits.pageSize * 3,
            "the fixture is only \(trees) trees; a page of \(GroveLimits.pageSize) is not a page of it"
        )
        #expect(
            page.items.count == GroveLimits.pageSize,
            "the first page returned \(page.items.count) of a \(trees)-tree grove"
        )
        #expect(
            !census.statements.contains(ContributionStore.groveTreeIDsSQL),
            """
            the first page ran the unbounded id read. Every projection statement is scoped to the \
            ids it returns, so the page would be built out of all \(trees) trees and cut afterwards \
            — which is the protocol default, not the paged read
            """
        )
        #expect(
            census.statements.contains(ContributionStore.groveTreeIDsPageSQL),
            "the first page did not run the paged id statement at all"
        )
        #expect(
            census.readCount == 2,
            """
            one page made \(census.readCount) hops onto the database queue, not 2. One hop per tree \
            is the N+1 task #250 removed from this read, and a paged read is where it would come \
            back
            """
        )
    }

    /// **And the bounded statement really is bounded**, which is the other half and the one the
    /// census cannot see: it records statement texts, not how many ids were bound to them.
    ///
    /// This reads the store directly, because the store's answer *is* the projection's input —
    /// `LocalAPI.groveEntries` is a `for` over exactly these rows and hands exactly these ids to
    /// `TreeQueries.trees(ids:)`, `activeNames(treeIDs:)` and `heroPhotoIDs(treeIDs:)`. Fifty rows
    /// out of a hundred and eighty is the claim "the first page does not build the full projection"
    /// with nothing left to infer.
    @Test("the bounded id read returns a page of ids, not a grove of them")
    func theBoundedReadReturnsAPageOfIDs() async throws {
        let (api, store, trees) = try await Self.seededGrove()
        _ = api

        let (paged, whole) = try await store.queue.read { connection in
            let contributions = ContributionStore()
            return (
                try contributions.groveTreeIDs(
                    userID: nil,
                    deviceID: Self.deviceID,
                    after: nil,
                    limit: GroveLimits.pageSize,
                    connection: connection
                ),
                try contributions.groveTreeIDs(
                    userID: nil, deviceID: Self.deviceID, connection: connection
                )
            )
        }

        #expect(
            whole.count == trees,
            "the control read \(whole.count) ids of \(trees) — the fixture is not what this test thinks"
        )
        #expect(
            paged.count == GroveLimits.pageSize,
            """
            the bounded read handed the projection \(paged.count) ids for a page of \
            \(GroveLimits.pageSize) out of \(trees) trees
            """
        )
        #expect(
            paged.map(\.treeID) == Array(whole.prefix(GroveLimits.pageSize)).map(\.treeID),
            "the bounded read's page is not the head of the unbounded read's answer"
        )
    }

    /// **A later page costs what the first one costs**, which is the half a first-paint-only gate
    /// would miss: a per-row read added to the paging path is paid on every press of `Show more`.
    /// `JournalStatementCensusTests.theSecondPageCostsTheSame` is the same assertion one screen
    /// over.
    @Test("Show more is also two hops and the bounded statement")
    func theSecondPageCostsTheSame() async throws {
        let (api, store, _) = try await Self.seededGrove()
        let first = try await api.grovePage(cursor: nil, limit: GroveLimits.pageSize)
        let cursor = try #require(first.nextCursor, "the fixture produced no second page to ask for")

        let census = StatementCensus()
        await store.queue.installCensus(census)
        let second = try await api.grovePage(cursor: cursor, limit: GroveLimits.pageSize)
        await store.queue.installCensus(nil)

        #expect(second.items.count == GroveLimits.pageSize, "the second page came back short")
        #expect(census.readCount == 2, "a later page cost \(census.readCount) hops")
        #expect(!census.statements.contains(ContributionStore.groveTreeIDsSQL))
        #expect(census.statements.contains(ContributionStore.groveTreeIDsPageSQL))
    }

    /// **A negative limit must not become the unbounded read wearing the paged statement's name.**
    ///
    /// In SQLite a negative `LIMIT` is no limit at all, so before the clamp
    /// `grovePage(cursor: nil, limit: -1)` ran `groveTreeIDsPageSQL` and came back with the entire
    /// grove — the whole projection built for one page, which is the exact cost this round exists
    /// to remove. Every other gate in this file stayed green through it, because they ask *which
    /// statement ran* and the paged one is what ran. That is why this one asks about the size of
    /// the answer instead.
    ///
    /// The protocol default in `CypressAPI` already refused a non-positive limit and returned an
    /// empty page; `LocalAPI` returning the whole grove for the same call meant the two
    /// implementations disagreed on an input `GrovePaginationTests`' equivalence sweep never uses.
    @Test("a non-positive limit returns nothing, not everything", arguments: [-1, 0])
    func aNonPositiveLimitIsNotTheUnboundedRead(_ limit: Int) async throws {
        let (api, store, trees) = try await Self.seededGrove()
        try #require(trees > GroveLimits.pageSize, "the fixture cannot show the difference")

        let census = StatementCensus()
        await store.queue.installCensus(census)
        let page = try await api.grovePage(cursor: nil, limit: limit)
        await store.queue.installCensus(nil)

        #expect(
            page.items.isEmpty,
            """
            a limit of \(limit) returned \(page.items.count) of \(trees) trees. A negative LIMIT \
            is no limit in SQLite, so this is the unbounded read running through the paged \
            statement — invisible to every gate that asks which text ran
            """
        )
        #expect(page.nextCursor == nil, "an empty page carried a cursor")
        #expect(
            !census.statements.contains(ContributionStore.groveTreeIDsSQL),
            "the clamp sent this down the unbounded path instead of returning nothing"
        )
    }

    /// The same clamp on the journal, which had the identical shape one screen over. `journal()`
    /// is not this file's subject, so this asserts only the property the clamp is for.
    @Test("the journal's limit is clamped the same way", arguments: [-1, 0])
    func theJournalsLimitIsClampedToo(_ limit: Int) async throws {
        let (api, _, _) = try await Self.seededGrove()
        let page = try await api.journal(cursor: nil, limit: limit)
        #expect(
            page.items.isEmpty,
            "the journal returned \(page.items.count) rows for a limit of \(limit)"
        )
    }
}
