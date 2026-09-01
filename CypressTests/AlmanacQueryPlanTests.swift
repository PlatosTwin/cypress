import Foundation
import Testing
@testable import Cypress

/// **Screen 12's reads, explained — the instrument `GroveQueryPlanTests` is for screen 08 and
/// `JournalQueryPlanTests` is for the Journal, aimed at the almanac.**
///
/// The almanac carried the same defect PR #131 took out of the Grove, on a screen nothing gated.
/// `firstBloom` joined the contributor's visits to the inventory with `COLLATE NOCASE`, which is
/// *correct* and cannot be answered by an index — `trees.uuid` is `NOT NULL UNIQUE`, so
/// `sqlite_autoindex_trees_1` is BINARY and no NOCASE comparison can seek it, whichever operand
/// carries the collation. Measured on the shipped seed, before this change:
///
/// - the **polygon** arm drove from the seed and probed the contributor:
///   `SEARCH t USING INDEX idx_trees_neighborhood (neighborhood_id=?) | SEARCH v USING AUTOMATIC
///   PARTIAL COVERING INDEX (tree_uuid=?)` — every tree in the neighborhood walked, and a transient
///   index built over `visits` per execution to survive it. That is the inverse of the right plan
///   and its cost tracks the size of the *neighborhood* rather than of the reader's own record.
/// - the **radius** arm drove the right way round and paid on the other side:
///   `SCAN v | … | SEARCH t USING AUTOMATIC PARTIAL COVERING INDEX (uuid=?)` — a transient index
///   built over `temp.trees`, the whole merged inventory, per execution.
///
/// With `lower()` on the contributions side both arms plan
/// `SCAN v | … | SEARCH t USING INDEX sqlite_autoindex_trees_1 (uuid=?)`: drive from the
/// contributor's own visits, seek the inventory once per visit, build nothing. The statement goes
/// from 3.06–4.53 ms to 0.01–0.02 ms in the polygon arm and from 22.9–33.7 ms to 0.12–0.26 ms in the
/// radius arm, on a device with no contributions at all — `AlmanacQueries.bloomTreeJoin` carries the
/// figures and how they were taken.
///
/// ── The rules ───────────────────────────────────────────────────────────────────────────────
/// The first two are `GroveQueryPlanTests`', and its header states why each is written the way it
/// is; they are not restated here. The third is this file's, and it is here because the defect above
/// **would have passed rules 1 and 2 in one of its two arms**:
///
/// 1. **The seek that answers the statement is in the plan**, named, as a `SEARCH`.
/// 2. **Nothing may scan the inventory, and nothing may materialize it**, stated as an allowlist of
///    relations permitted to be walked, each with a reason.
/// 3. **Nothing may build an index at run time.** A step reading `AUTOMATIC PARTIAL COVERING INDEX`
///    or `AUTOMATIC COVERING INDEX` is SQLite constructing a transient b-tree over a relation
///    *because the query gave it no usable one*, and it pays for it on every execution. It is
///    spelled `SEARCH`, so rule 1 counts it as a seek and rule 2 does not see it as a scan — the
///    radius arm's `SEARCH t USING AUTOMATIC PARTIAL COVERING INDEX (uuid=?)` is a full pass over
///    the merged inventory that both of the other rules would have certified.
///
/// Every statement is explained in **both of R29's arms**, because `AlmanacScope.predicate(_:)` is
/// two different `WHERE` clauses with two different plans — a gate that explained one would be
/// silent about the other, and the polygon arm is the one the collation defect was worst in.
///
/// ── Calibration ─────────────────────────────────────────────────────────────────────────────
/// With only `AlmanacQueries.bloomTreeJoin` reverted to `t.uuid = v.tree_uuid COLLATE NOCASE` and
/// nothing else changed, `plansStayIndexedAndBuildNothing` fails with **four issues**: `first bloom`
/// in each arm loses its `sqlite_autoindex_trees_1` seek (rule 1) and gains an `AUTOMATIC` step
/// (rule 3), and the two `AUTOMATIC` steps are different relations in the two arms — `v` under the
/// polygon, `t` under the radius. The verbatim messages are in the pull request.
///
/// The three tests below that are *not* about the collation carry their own calibration in their own
/// doc comments, for the reason `GroveQueryPlanTests`' header gives: a calibration claim nobody
/// re-derives is the same artifact as an uncalibrated gate.
///
/// The lowercase-uuid contract `bloomTreeJoin` stands on is not re-asserted here.
/// `GroveQueryPlanTests.theBundledSeedIsLowercase` and `.theLowercaseUUIDContractCanFailOnAPack`
/// already ask it of the bundle and of a pack, and `DataGates.seedContract` runs it on every CI run;
/// a second copy would be a second thing to keep in step, not a second measurement.
@Suite("Almanac · query plans")
struct AlmanacQueryPlanTests {

    // MARK: - Fixtures

    static func store() async throws -> CypressStore {
        let seedURL = try #require(SeedContractTests.seedURL, "no seed database; set CYPRESS_SEED_PATH")
        return try await CypressStore.inMemory(seedURL: seedURL)
    }

    /// A neighborhood the shipped seed actually holds, read out of the seed rather than written
    /// down here — `GroveQueryPlanTests.anyNeighborhood`'s reason: a hard-coded id would silently
    /// stop being a neighborhood after a rebuild and the gate would go on explaining a query that
    /// matches nothing.
    static func anyNeighborhood(_ store: CypressStore) async throws -> (id: Int, name: String) {
        try await store.queue.read { connection in
            let statement = try connection.prepare("""
                SELECT n.id AS id, n.name AS name
                  FROM \(SeedDatabase.schemaName).neighborhoods n
                 ORDER BY n.id LIMIT 1
                """)
            defer { statement.finalize() }
            return try statement.fetchOne { (id: try $0.int("id"), name: try $0.string("name")) }
                ?? (id: -1, name: "")
        }
    }

    /// A coordinate inside Sunset/Parkside, the same fix `GroveQueryPlanTests` uses for the radius
    /// arm of the ring's denominator.
    static let fix = Coordinate(latitude: 37.7694, longitude: -122.4862)

    /// Relations a plan may walk end to end, and why each one is small.
    ///
    /// Two entries, and the shortness is the point: **the inventory is not on this list under any
    /// alias.** `visits` is the contributor's own record, bounded by what one person did on one
    /// phone; `json_each` is a co-routine over a bound array. Every relation an almanac statement
    /// touches other than those two is the merged inventory or a translation table beside it, and
    /// walking any of them is the regression this file exists to catch.
    private static let scannable: Set<String> = ["visits", "v", "json_each"]

    /// label, the statement, and the index whose `SEARCH` must answer it in this arm.
    ///
    /// The indexes differ by arm because the scope's predicate does: R29's polygon arm narrows on
    /// `neighborhood_id` and its radius arm on a `lat`/`lon` box. `speciesMix` is the exception that
    /// narrows on neither — it groups by species and drives from `idx_trees_species_current` in both
    /// arms — and `firstBloom` is the other, because it drives from `visits` and seeks the
    /// inventory's own uuid index whatever the scope says.
    private static func statements(
        _ queries: AlmanacQueries,
        scope: AlmanacScope,
        scopeIndex: String
    ) -> [(label: String, sql: String, index: String)] {
        [
            ("whether the record reaches here", queries.holdsAnyRecordSQL(scope: scope), scopeIndex),
            ("the elder", queries.elderSQL(scope: scope), scopeIndex),
            ("this spring's plantings", queries.plantingsSQL(scope: scope), scopeIndex),
            ("this spring's plantings, as pins", queries.plantingPinsSQL(scope: scope), scopeIndex),
            ("who lives here", queries.speciesMixSQL(scope: scope), "idx_trees_species_current"),
            ("the young trees nobody has visited", queries.youngTreesWithoutVisitsSQL(scope: scope), scopeIndex),
            ("the first bloom", queries.firstBloomSQL(scope: scope), "sqlite_autoindex_trees_1"),
            ("how many sites are vacant", queries.vacantSiteCountSQL(scope: scope), scopeIndex),
            ("the vacant sites, as pins", queries.vacantSitePinsSQL(scope: scope), scopeIndex)
        ]
    }

    /// Both of R29's arms, each with the index its own `WHERE` fragment is answered by.
    ///
    /// The polygon arm's is `idx_trees_neighborhood` — the composite `idx_trees_neighborhood_planted`
    /// answers the four statements that also bound `planted_on`, and its name contains the shorter
    /// one, so a `contains` check is satisfied by either. That is deliberate: which of the two the
    /// planner picks is its business, and pinning the composite would fail the day a statement
    /// stopped filtering on a date without anything having got slower.
    private static func arms(_ hood: (id: Int, name: String)) -> [(name: String, scope: AlmanacScope, index: String)] {
        [
            (
                "polygon",
                .neighborhood(id: hood.id, name: hood.name),
                "idx_trees_neighborhood"
            ),
            (
                "radius",
                .radius(center: fix, meters: AlmanacLimits.fallbackRadiusM),
                "idx_trees_lat_lon"
            )
        ]
    }

    // MARK: - Rules 1, 2 and 3, over every almanac statement, in both arms

    @Test("every almanac statement seeks its index, walks nothing but the reader's own rows, and builds no index")
    func plansStayIndexedAndBuildNothing() async throws {
        let store = try await Self.store()
        let schema = try #require(store.seed, "the store opened without a seed attached")
        let queries = AlmanacQueries(schema: schema)
        let hood = try await Self.anyNeighborhood(store)
        try #require(hood.id > 0, "the seed carries no neighborhoods, so the polygon arm is untested")

        try await store.queue.read { connection in
            for arm in Self.arms(hood) {
                for (label, sql, index) in Self.statements(queries, scope: arm.scope, scopeIndex: arm.index) {
                    let steps = try connection.queryPlan(for: sql)
                    let plan = steps.joined(separator: " | ")
                    let named = "\(label), by \(arm.name)"

                    // Rule 1. A `SEARCH` naming the index, not the index's name anywhere in the text.
                    let seeks = steps.filter { $0.contains("SEARCH") && $0.contains(index) }
                    #expect(!seeks.isEmpty, "\(named): nothing SEARCHes \(index) — \(plan)")

                    // Rule 2a. Nothing is materialized.
                    let materialized = steps.filter { $0.contains("MATERIALIZE") }
                    #expect(
                        materialized.isEmpty,
                        "\(named): materializes a relation — \(materialized.joined(separator: " | "))"
                    )

                    // Rule 2b. Everything walked end to end is on the allowlist above, by name.
                    let scanned = steps.compactMap { GroveQueryPlanTests.scannedRelation(in: $0) }
                    let unexpected = scanned.filter { !Self.scannable.contains($0) }
                    #expect(
                        unexpected.isEmpty,
                        """
                        \(named): walks \(unexpected.sorted()) end to end, which is not on the \
                        permitted list \(Self.scannable.sorted()) — \(plan)
                        """
                    )

                    // Rule 3. Nothing is indexed at run time. See this file's header for why this
                    // is not covered by either rule above.
                    let automatic = steps.filter { $0.contains("AUTOMATIC") }
                    #expect(
                        automatic.isEmpty,
                        """
                        \(named): SQLite built a transient index because the statement gave it no \
                        usable one, and pays for it on every execution — \
                        \(automatic.joined(separator: " | ")) — \(plan)
                        """
                    )
                }
            }
        }
    }

    // MARK: - The one collated join that stays, pinned as what it is

    /// **The young-tree subquery's plan, pinned as the scan it is — and the seek it would have.**
    ///
    /// `AlmanacQueries.youngTreesWithoutVisitsSQL(scope:)` keeps its `COLLATE NOCASE`, and its doc
    /// comment argues why: the index that would answer it is `idx_visits_tree`, over a column in
    /// `main`, so seeking it means normalizing the **seed** side up — `v.tree_uuid = upper(t.uuid)`
    /// — which is correct only while every row in `visits` stores an upper-case uuid, and nothing
    /// asserts that. This is the line that makes both halves of that paragraph a measurement rather
    /// than a confident comment:
    ///
    /// - the shipped statement's correlated subquery is `SCAN v`, a full pass over the contributor's
    ///   visits per candidate tree;
    /// - the `upper()` form of the *same* statement, built here by substitution, is
    ///   `SEARCH v USING INDEX idx_visits_tree (tree_uuid=? AND captured_at>?)`.
    ///
    /// So the day a migration gives `visits.tree_uuid` a case-insensitive index — or gives the case
    /// a contract — this test goes red on the first half and the paragraph has to be rewritten
    /// deliberately, rather than staying wrong. It also fails if the substitution stops matching,
    /// which is what keeps the counterfactual honest.
    ///
    /// **Calibration.** Both halves have been run against the opposite state: deleting `COLLATE
    /// NOCASE` from the shipped statement (leaving `v.tree_uuid = t.uuid`) makes the first
    /// expectation red — the plan becomes the `idx_visits_tree` seek — while the substitution then
    /// finds nothing and the `#require` reports it. Neither expectation passes vacuously.
    @Test("the young-tree subquery scans the reader's visits, and would seek if the case were contracted")
    func theYoungTreeSubqueryIsTheKnownScan() async throws {
        let store = try await Self.store()
        let schema = try #require(store.seed, "the store opened without a seed attached")
        let queries = AlmanacQueries(schema: schema)
        let hood = try await Self.anyNeighborhood(store)
        try #require(hood.id > 0, "the seed carries no neighborhoods, so the polygon arm is untested")

        try await store.queue.read { connection in
            for arm in Self.arms(hood) {
                let sql = queries.youngTreesWithoutVisitsSQL(scope: arm.scope)
                let steps = try connection.queryPlan(for: sql)
                let plan = steps.joined(separator: " | ")

                #expect(
                    steps.contains(where: { GroveQueryPlanTests.scannedRelation(in: $0) == "v" }),
                    """
                    the young-tree subquery no longer walks `visits` end to end in the \(arm.name) \
                    arm. If it can now be seeked, `youngTreesWithoutVisitsSQL`'s doc comment saying \
                    it cannot is out of date and has to go with this gate — \(plan)
                    """
                )

                // The counterfactual: the same statement with the seed side normalized up.
                let hypothetical = sql.replacingOccurrences(
                    of: "v.tree_uuid = t.\(schema.treeIdentityColumn) COLLATE NOCASE",
                    with: "v.tree_uuid = upper(t.\(schema.treeIdentityColumn))"
                )
                try #require(
                    hypothetical != sql,
                    """
                    the substitution matched nothing, so the counterfactual below is explaining the \
                    shipped statement rather than the `upper()` form of it. The collated comparison \
                    in `youngTreesWithoutVisitsSQL` has been rewritten — re-derive this test
                    """
                )
                let wouldBe = try connection.queryPlan(for: hypothetical)
                #expect(
                    wouldBe.contains(where: { $0.contains("SEARCH") && $0.contains("idx_visits_tree") }),
                    """
                    the `upper()` form does not seek idx_visits_tree in the \(arm.name) arm either, \
                    so the cost this statement is documented as accepting is not the cost of the \
                    missing contract — \(wouldBe.joined(separator: " | "))
                    """
                )
            }
        }
    }

    // MARK: - The calibration

    /// **Every string this gate explains still parses and plans against the real schema.**
    ///
    /// `JournalQueryPlanTests.theStatementsAreTheOnesTheAppRuns`' reason, unchanged: a string naming
    /// a column a migration dropped fails here, on the shipped schema, rather than being explained
    /// forever. The stronger claim — that these are the statements screen 12 runs — is
    /// `AlmanacStatementCensusTests`' to make, and is not made here.
    @Test("every statement this gate explains prepares against the real schema, and no two are the same")
    func theStatementsPrepare() async throws {
        let store = try await Self.store()
        let schema = try #require(store.seed, "the store opened without a seed attached")
        let queries = AlmanacQueries(schema: schema)
        let hood = try await Self.anyNeighborhood(store)
        try #require(hood.id > 0, "the seed carries no neighborhoods, so the polygon arm is untested")

        for arm in Self.arms(hood) {
            let texts = Self.statements(queries, scope: arm.scope, scopeIndex: arm.index).map(\.sql)
            #expect(
                texts.count == Set(texts).count,
                "the \(arm.name) arm explains the same statement twice, so one of them is unexamined"
            )
            try await store.queue.read { connection in
                for sql in texts {
                    let steps = try connection.queryPlan(for: sql)
                    #expect(!steps.isEmpty, "EXPLAIN QUERY PLAN produced no steps for:\n\(sql)")
                }
            }
        }
    }
}
