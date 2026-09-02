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
/// ── How the expected texts are obtained, and the one thing that is honestly weaker here ────────
/// `JournalStatementCensusTests` reads all five of its texts off `static let …SQL` properties, so
/// its set assertion is a genuine drift gate on every one of them. The grove's read is not built
/// that way: **three** of its seven statements have a named property today
/// (`TreeQueries.treesSQL()`, `ContributionStore.activeNamesSQL`, and
/// `ContributionStore.scopedHeroPhotoTalliesSQL`, which is byte-identical to the literal
/// `heroPhotoIDs` prepares). The other four are string literals inside their store methods.
///
/// **There are three ways to write this test, not two, and an earlier draft of this header claimed
/// two** (PR #147's review, F4). They are: copy the literals into the test — which is exactly the
/// gate PR #143's review disproved, a test explaining its own copy; **hoist the literals to named
/// properties on the store and pin the test to those**, which is what
/// `AlmanacStatementCensusTests` does for all nine of its statements and what `journalSQL` and
/// `activeNamesSQL` already are; or probe. The third horn is the better one and it is available —
/// it is a production change, and this round is not the round for it (see the PR's out-of-scope
/// notes), but nothing about the grove's read prevents it.
///
/// So the four literal-only texts are obtained by the remaining route that binds them to
/// production: by **running the store methods themselves** under a second census, on the same store,
/// in the order `grove()` calls them, and taking the texts they prepare. `Self.expected(…)` is that
/// probe. What it certifies is that `grove()` runs the store's statements and no others — the shape
/// of drift that matters, since a hand-rolled statement inlined into `grove()` would diverge from
/// the store method the rest of the app reads through. What it cannot certify, and nothing in this
/// file claims it does, is that `groveTreeIDs`' own text has not changed; a rewrite of that method
/// moves probe and app together. The three property-backed texts are asserted against their
/// properties directly, below, where the stronger statement is available.
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

    /// The seven statements a grove read runs, taken off the production store methods by running
    /// them — see the suite header for why five of them cannot be read off a property.
    ///
    /// Run in the order `grove()` runs them, and scoped the way `grove()` scopes them: the photo
    /// reads take the tree ids the *first* statement returned, not the fixture's list, because that
    /// is what `grove()` passes and a differently-scoped probe would prepare the same text anyway
    /// but would stop being a description of the same call.
    private static func expected(api: LocalAPI, store: CypressStore) async throws -> [String] {
        let schema = try #require(store.seed, "the store opened without a seed attached")
        let softDeletes = store.seedHasSoftDeletedTrees
        let userID = await api.userID

        let probe = StatementCensus()
        await store.queue.installCensus(probe)
        try await store.queue.read { connection -> Void in
            // Built inside the closure, out of two `Sendable` values: `TreeQueries` is a plain
            // struct with no `Sendable` conformance, so capturing a ready-made one would be sending
            // a non-`Sendable` value into an actor.
            let treeQueries = TreeQueries(schema: schema, seedHasSoftDeletedTrees: softDeletes)
            let contributions = ContributionStore()
            let rows = try contributions.groveTreeIDs(
                userID: userID, deviceID: deviceID, connection: connection
            )
            _ = try contributions.groveRecords(userID: userID, deviceID: deviceID, connection: connection)
            _ = try contributions.heroPhotoIDs(treeIDs: Set(rows.map(\.treeID)), connection: connection)

            let treeIDs = rows.map(\.treeID)
            _ = try treeQueries.trees(ids: treeIDs, connection: connection)
            _ = try CommunityTreeStore().trees(ids: treeIDs, connection: connection)
            _ = try contributions.activeNames(treeIDs: treeIDs, connection: connection)
        }
        await store.queue.installCensus(nil)
        return probe.statements
    }

    /// The statements that have a named property on their store, and can therefore be pinned to it
    /// rather than to the probe.
    ///
    /// `scopedHeroPhotoTalliesSQL` is in here on PR #147's review (F4): `heroPhotoIDs` prepares a
    /// literal that is byte-identical to that property after Swift's multiline indent-stripping, so
    /// pinning it costs nothing and is strictly stronger than the probe. That `ContributionStore`
    /// holds two copies of one statement is a production defect this test does not fix and the PR
    /// reports.
    private static func propertyBacked(_ store: CypressStore) throws -> [String] {
        let schema = try #require(store.seed, "the store opened without a seed attached")
        let trees = TreeQueries(schema: schema, seedHasSoftDeletedTrees: store.seedHasSoftDeletedTrees)
        return [
            trees.treesSQL(),
            ContributionStore.activeNamesSQL,
            ContributionStore.scopedHeroPhotoTalliesSQL
        ]
    }

    // MARK: - The gate

    @Test("one grove read is two queue hops and seven statements, each run exactly once")
    func theGroveRunsTwoHopsAndSevenStatementsOnce() async throws {
        let (api, store, trees) = try await Self.seeded()
        let expected = try await Self.expected(api: api, store: store)

        // The probe itself has to have found seven distinct statements, or the comparison below is
        // being made against a shorter list and would accept a `grove()` that had stopped running
        // one of them.
        try #require(
            expected.count == Self.statementCount,
            """
            the probe over the store's own methods prepared \(expected.count) statements, not \
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

        // The three that have a property are pinned to it rather than to the probe — a genuine
        // text-drift gate on those, which the probe cannot be.
        for sql in try Self.propertyBacked(store) {
            try #require(
                expected.contains(sql),
                """
                a statement this repository names in a property is not among the ones the store's \
                own methods prepare: \(Self.firstLine(of: sql))
                """
            )
        }

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

    /// **The two texts that do have a property are pinned to that property**, which is the drift
    /// gate the probe in `expected(…)` cannot be.
    ///
    /// `TreeQueries.treesSQL()` and `ContributionStore.activeNamesSQL` are read here off the same
    /// types the app reads them off, and asserted to be among the statements `grove()` actually ran
    /// — so appending a comment to either one, the specimen PR #143's review used, moves the app and
    /// leaves this red. The remaining five are literals inside their store methods and there is no
    /// property to hold them to; the suite header says so rather than implying otherwise.
    @Test("the grove runs the two statements this repository names, off the properties that name them")
    func thePropertyBackedTextsAreTheOnesThatRun() async throws {
        let (api, store, _) = try await Self.seeded()
        let schema = try #require(store.seed, "the store opened without a seed attached")
        let treesSQL = TreeQueries(schema: schema, seedHasSoftDeletedTrees: store.seedHasSoftDeletedTrees)
            .treesSQL()

        let census = StatementCensus()
        await store.queue.installCensus(census)
        _ = try await api.grove()
        await store.queue.installCensus(nil)

        let ran = census.statements
        #expect(
            ran.filter { $0 == treesSQL }.count == 1,
            """
            the batched seed projection ran \(ran.filter { $0 == treesSQL }.count) times, not once. \
            Zero means `TreeQueries.treesSQL()` no longer describes what the grove runs; more than \
            one is the per-tree form returning. Ran: \(Self.histogram(ran))
            """
        )
        #expect(
            ran.filter { $0 == ContributionStore.activeNamesSQL }.count == 1,
            """
            the batched nickname lookup ran \
            \(ran.filter { $0 == ContributionStore.activeNamesSQL }.count) times, not once: \
            \(Self.histogram(ran))
            """
        )
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
