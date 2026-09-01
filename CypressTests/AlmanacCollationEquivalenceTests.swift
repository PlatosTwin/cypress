import Foundation
import Testing
@testable import Cypress

/// **The answers, before and after the collation change — including the case the collation existed
/// for.**
///
/// `AlmanacQueryPlanTests` proves `firstBloom` got faster. This file is the other half, and it is
/// the half that decides whether the change is allowed at all: `t.uuid = lower(v.tree_uuid)` and
/// `t.uuid = v.tree_uuid COLLATE NOCASE` have to return **the same rows**, on rows whose case
/// actually differs. If they did not, the almanac would not be slow, it would be wrong — the bloom
/// row is the one line on screen 12 that names a specific tree by its address.
///
/// The fixture is built to be hostile to the change on purpose. `ContributionStore.insert` binds a
/// `UUID` through `SQLiteValue`, which stores Foundation's **upper-case** canonical spelling, so a
/// suite that only inserted normally would compare two statements over rows that all spell a uuid
/// one way — and `t.uuid = v.tree_uuid` with no normalization at all would pass it. So the rows are
/// re-spelled afterwards, by `UPDATE`, into all three shapes a `visits` row could hold: upper, lower
/// and mixed. **Mixed is the one that matters**, because it is the only spelling that neither
/// `lower()` on one side nor a bare comparison can be right about by accident.
///
/// ── The second half: the join that did *not* change ─────────────────────────────────────────
/// `youngTreesWithoutVisits` keeps its `COLLATE NOCASE`, and
/// `AlmanacQueries.youngTreesWithoutVisitsSQL(scope:)` argues why at length: seeking `idx_visits_tree`
/// means normalizing the seed side **up**, which is only correct while every `visits` row stores an
/// upper-case uuid, and nothing asserts that. `mixedCaseVisitsStillSuppressAYoungTree` is that
/// argument as a fact rather than as a paragraph — a visit whose row spells the uuid the other way
/// still has to take its tree off §4's list, which is exactly what an `upper()` rewrite would break
/// and no plan gate would notice.
@Suite("Almanac · the collated joins answer the same rows")
struct AlmanacCollationEquivalenceTests {

    private static let deviceID = UUID(uuidString: "12000000-0000-4000-8000-000000000913")!
    private static let fix = AlmanacQueryPlanTests.fix

    /// How a `visits` row spells its `tree_uuid`, and the SQL that re-spells it that way.
    ///
    /// `mixed` upper-cases only the first block, which is enough to be neither of the other two and
    /// still a well-formed 36-character uuid — the shape no other check would notice, which is the
    /// point.
    private enum Spelling: String, CaseIterable {
        case upper, lower, mixed

        var rewrite: String {
            switch self {
            case .upper: "upper(tree_uuid)"
            case .lower: "lower(tree_uuid)"
            case .mixed: "upper(substr(tree_uuid, 1, 8)) || lower(substr(tree_uuid, 9))"
            }
        }
    }

    // MARK: - Fixture

    /// Three seed trees near the fix, each carrying one `flowering` visit, each visit's row spelled
    /// a different way — and the **earliest** of the three is the mixed-case one.
    ///
    /// That ordering is load-bearing: `firstBloom` returns one row, so if the earliest visit were
    /// the ordinary upper-case one the statement could ignore the other two entirely and still
    /// answer correctly. With the mixed spelling first, the row is only reachable by a comparison
    /// that genuinely normalizes.
    private static func seeded() async throws -> (
        store: CypressStore, queries: AlmanacQueries, scope: AlmanacScope,
        trees: [Spelling: UUID], since: Date, youngSince: String
    ) {
        let store = try await AlmanacQueryPlanTests.store()
        let schema = try #require(store.seed, "the store opened without a seed attached")
        let api = LocalAPI(
            store: store,
            deviceID: deviceID,
            photoDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("almanac-collation-\(UUID().uuidString)", isDirectory: true)
        )

        let species = SpeciesQueries(schema: schema)
        let polygon = try await store.queue.read { connection in
            try species.resolveNeighborhood(near: fix, connection: connection)
        }
        let found = try #require(polygon, "the fix resolves no neighborhood, so there is no polygon arm to test")
        let scope = AlmanacScope.neighborhood(id: found.id, name: found.name)

        // Trees the scope actually contains, read through the same predicates the statements use, so
        // a tree that is near the fix but in the next neighborhood cannot make this vacuous.
        //
        // **The three most recently planted**, and that is not decoration: `youngTreesWithoutVisits`
        // takes a `plantedOnOrAfter` bound and a row limit, so a tree can be missing from its answer
        // for two entirely different reasons — because a visit suppressed it, which is what this
        // file asserts, or because 200 younger trees came first. Taking the newest three and setting
        // the bound at the oldest of them makes the candidate set those three (plus any tie), so
        // absence means suppression and the control below can prove it.
        let candidates: [(id: UUID, plantedOn: String)] = try await store.queue.read { connection in
            let statement = try connection.prepare("""
                SELECT t.\(schema.treeIdentityColumn) AS tree_uuid, t.planted_on AS planted_on
                  FROM \(SeedDatabase.schemaName).trees t
                 WHERE t.neighborhood_id = :hood
                   AND t.planted_on IS NOT NULL
                   AND t.deleted_at IS NULL
                   AND t.status IN ('alive','declining')
                 ORDER BY t.planted_on DESC
                 LIMIT 3
                """)
            defer { statement.finalize() }
            _ = try statement.bind(found.id, forName: ":hood")
            return try statement.fetchAll {
                (id: try $0.uuid("tree_uuid"), plantedOn: try $0.string("planted_on"))
            }
        }
        try #require(
            candidates.count == 3,
            "'\(found.name)' holds \(candidates.count) standing trees with a planting date, not 3"
        )
        let youngSince = try #require(candidates.map(\.plantedOn).min())

        // The mixed-case row is the earliest, then lower, then upper.
        let order: [Spelling] = [.mixed, .lower, .upper]
        let base = Date(timeIntervalSince1970: 1_800_000_000) // 2027-01-15
        let attribution = await api.attribution
        var trees: [Spelling: UUID] = [:]
        for (index, spelling) in order.enumerated() {
            let tree = candidates[index].id
            trees[spelling] = tree
            let visit = Visit(
                treeID: tree,
                attribution: attribution,
                phenologyTags: [.flowering],
                capturedAt: base.addingTimeInterval(Double(index) * 86_400)
            )
            try await store.queue.write { connection in
                try ContributionStore().insert(visit, connection: connection)
                // The one thing `ContributionStore` cannot produce: a row spelling its uuid any way
                // but Foundation's. Rewritten here rather than bound, so the insert path under test
                // elsewhere is the one that ran.
                try connection.execute("""
                    UPDATE visits SET tree_uuid = \(spelling.rewrite)
                     WHERE id = '\(visit.id.uuidString)'
                    """)
            }
        }

        // The fixture is only a fixture if the three spellings really are three spellings.
        let spellings: Set<String> = try await store.queue.read { connection in
            let statement = try connection.prepare("SELECT tree_uuid AS u FROM visits")
            defer { statement.finalize() }
            return Set(try statement.fetchAll { try $0.string("u") })
        }
        try #require(spellings.count == 3, "the fixture holds \(spellings.count) visit rows, not 3")
        try #require(
            spellings.contains(where: { $0 != $0.lowercased() && $0 != $0.uppercased() }),
            "no visit row spells its uuid in mixed case, so the case this file exists for is untested"
        )

        return (
            store, AlmanacQueries(schema: schema), scope, trees,
            base.addingTimeInterval(-86_400), youngSince
        )
    }

    /// The shipped statement with its join put back the way it was.
    private static func collated(_ sql: String, schema: SeedSchema) throws -> String {
        let reverted = sql.replacingOccurrences(
            of: "t.\(schema.treeIdentityColumn) = lower(v.tree_uuid)",
            with: "t.\(schema.treeIdentityColumn) = v.tree_uuid COLLATE NOCASE"
        )
        try #require(
            reverted != sql,
            """
            the substitution matched nothing, so the "before" statement below is the shipped one and \
            this test compares a statement with itself. `AlmanacQueries.bloomTreeJoin` has been \
            rewritten — re-derive this test
            """
        )
        return reverted
    }

    // MARK: - The bloom join

    /// **`lower()` and `COLLATE NOCASE` return the same row, on rows whose case differs.**
    @Test("the first bloom is the same row before and after the collation change")
    func theFirstBloomIsUnchanged() async throws {
        let (store, queries, scope, trees, since, _) = try await Self.seeded()
        let schema = try #require(store.seed)
        let shipped = queries.firstBloomSQL(scope: scope)
        let before = try Self.collated(shipped, schema: schema)

        let answers: [String: [String]] = try await store.queue.read { connection in
            var found: [String: [String]] = [:]
            for (label, sql) in [("after", shipped), ("before", before)] {
                let statement = try connection.prepare(sql)
                defer { statement.finalize() }
                _ = try statement.bind(scope.bindings.merging([
                    ":since": since,
                    ":flowering": PhenologyTag.flowering.rawValue
                ] as [String: SQLiteBindable?]) { a, _ in a })
                found[label] = try statement.fetchAll { row in
                    "\(try row.uuid("tree_uuid")) @ \(try row.string("first_seen_at")) ×\(try row.int("observer_count"))"
                }
            }
            return found
        }

        let after = try #require(answers["after"])
        let old = try #require(answers["before"])
        #expect(
            after == old,
            """
            the collation change moved the bloom row. after: \(after); before: \(old). These two \
            statements differ only in how the visit's uuid meets the inventory's, so any difference \
            here is a difference in which trees the join can reach
            """
        )
        let mixed = try #require(trees[.mixed])
        #expect(
            after.count == 1 && after[0].hasPrefix(mixed.uuidString),
            """
            the first bloom is \(after), not the tree whose visit row spells its uuid in mixed case \
            (\(mixed)). That row carries the earliest flowering visit in the fixture, so a statement \
            that cannot reach it answers with a later one — which is the defect a bare, \
            un-normalized comparison would have
            """
        )
    }

    /// **All three spellings are reachable, not just the earliest one.**
    ///
    /// The test above proves the join reaches the mixed-case row. This proves it reaches every row,
    /// by asking for a window that starts after each visit in turn: the answer has to walk the
    /// fixture in order, mixed then lower then upper. A join that reached only two of the three
    /// would satisfy the first test and fail here.
    @Test("every spelling of a visit's tree uuid is reachable by the bloom join")
    func everySpellingIsReachable() async throws {
        let (store, queries, scope, trees, since, _) = try await Self.seeded()
        let order: [Spelling] = [.mixed, .lower, .upper]

        var window = since
        for (index, spelling) in order.enumerated() {
            let expected = try #require(trees[spelling])
            let found: UUID? = try await store.queue.read { [window] connection in
                try queries.firstBloom(scope: scope, since: window, connection: connection)?.treeID
            }
            #expect(
                found == expected,
                """
                asking for the first bloom since \(window) answered \(String(describing: found)), \
                not the \(spelling.rawValue)-cased row's tree \(expected). The fixture's visits are \
                a day apart in the order mixed, lower, upper, so answer \(index) is the \
                \(spelling.rawValue) one
                """
            )
            // Step past the visit just found, so the next spelling is the earliest remaining.
            window = window.addingTimeInterval(86_400)
        }
    }

    // MARK: - The young-tree join, which deliberately did not change

    /// **A mixed-case visit row still takes its tree off §4's list.**
    ///
    /// This is the fact `youngTreesWithoutVisitsSQL`'s doc comment turns on. The subquery's
    /// `COLLATE NOCASE` is what makes it true; the `upper(t.uuid)` rewrite that would let it seek
    /// `idx_visits_tree` makes it false for exactly the rows this fixture holds, and it fails
    /// *silently* — the tree comes back as one nobody has visited, and screen 12 asks a reader to go
    /// and look at a tree that has already been looked at.
    /// **Absence, with the control that makes absence mean something.** The three trees are the
    /// newest the neighborhood holds and the `plantedOnOrAfter` bound is the oldest of the three, so
    /// nothing but suppression can keep them off the answer — and the second half proves it by
    /// soft-deleting the three visits and watching all three trees come back.
    @Test("a visit whose row spells the uuid in mixed case still suppresses its young tree")
    func mixedCaseVisitsStillSuppressAYoungTree() async throws {
        let (store, queries, scope, trees, _, youngSince) = try await Self.seeded()

        func unvisited() async throws -> [UUID] {
            try await store.queue.read { connection in
                try queries.youngTreesWithoutVisits(
                    scope: scope,
                    plantedOnOrAfter: youngSince,
                    limit: AlmanacLimits.coverageRowLimit,
                    connection: connection
                ).map(\.id)
            }
        }

        // The subquery compares `v.captured_at >= t.planted_on`, and the fixture's visits are dated
        // 2027, after every planting date the seed carries — so each visit is one "since planting".
        let suppressed = try await unvisited()
        for (spelling, tree) in trees {
            #expect(
                !suppressed.contains(tree),
                """
                the tree whose only visit row spells its uuid in \(spelling.rawValue) case \
                (\(tree)) is still on §4's list of trees nobody has visited. The visit exists; the \
                subquery cannot see it. That is the failure an `upper()` rewrite of this join \
                produces, and no query-plan gate can see it
                """
            )
        }

        // The control. Without it every expectation above passes on a query that returned nothing,
        // or on trees the row limit truncated away — this project's dominant test defect.
        try await store.queue.write { connection in
            try connection.execute("UPDATE visits SET deleted_at = '2027-02-01T00:00:00Z'")
        }
        let released = try await unvisited()
        for (spelling, tree) in trees {
            #expect(
                released.contains(tree),
                """
                with its only visit soft-deleted, the \(spelling.rawValue)-cased row's tree \
                (\(tree)) still does not appear among the young trees nobody has visited. So its \
                absence above was not suppression — the assertions in the first half of this test \
                were vacuous. Answer: \(released)
                """
            )
        }
    }
}
