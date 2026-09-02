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
/// With `lower()` on the contributions side both arms planned
/// `SCAN v | … | SEARCH t USING INDEX sqlite_autoindex_trees_1 (uuid=?)`: drive from the
/// contributor's own visits, seek the inventory once per visit, build nothing. The statement went
/// from 3.06–4.53 ms to 0.01–0.02 ms in the polygon arm and from 22.9–33.7 ms to 0.12–0.26 ms in the
/// radius arm, on a device with no contributions at all — `AlmanacQueries.bloomTreeJoin` carries the
/// figures and how they were taken.
///
/// **Since `AppSchema` v19 the leading `SCAN v` is a `SEARCH` as well**, in both arms:
/// `SEARCH v USING INDEX idx_visits_captured (captured_at>?)`. Nothing in `AlmanacQueries` changed
/// for it. v19 added `idx_visits_captured` on `(captured_at DESC, id COLLATE NOCASE DESC)` for the
/// journal's page query, and this statement already bounded `captured_at` to the current year
/// (SCREENS.md 12 §2), so the year bound became a range seek. It is recorded here because it is a
/// plan this file explains that moved without this file's subject moving, and because it is half of
/// why `scannable` no longer carries `visits` — see that property.
///
/// ── The rules ───────────────────────────────────────────────────────────────────────────────
/// The first two are `GroveQueryPlanTests`', and its header states why each is written the way it
/// is; they are not restated here. The third is this file's:
///
/// 1. **The seek that answers the statement is in the plan**, named, as a `SEARCH`.
/// 2. **Nothing may scan the inventory, and nothing may materialize it**, stated as an allowlist of
///    relations permitted to be walked, each with a reason.
/// 3. **Nothing may build an index at run time.** A step reading `AUTOMATIC PARTIAL COVERING INDEX`
///    or `AUTOMATIC COVERING INDEX` is SQLite constructing a transient b-tree over a relation
///    *because the query gave it no usable one*, and it pays for it on every execution.
///
/// **Rule 3 is not what would have caught the defect above, and this paragraph said it was.** The
/// first draft argued that the radius arm's `SEARCH t USING AUTOMATIC PARTIAL COVERING INDEX
/// (uuid=?)` was "a full pass over the merged inventory that both of the other rules would have
/// certified". That is false, and the calibration four paragraphs down says so in the same file:
/// `firstBloom` is pinned on `sqlite_autoindex_trees_1`, which is exactly the index the transient
/// one stands in for, so **rule 1 fires on both arms** and rule 3 is redundant there. PR #145's
/// review caught it; a confident comment about a query plan is precisely the artifact this file
/// exists to replace with a measurement, and it was wrong here first.
///
/// What rule 3 is actually for is **the other eight statements**, which are pinned on a *scope*
/// index — `idx_trees_neighborhood`, `idx_trees_lat_lon`, `idx_trees_species_current` — rather than
/// on the identity index a uuid join would lose. An `AUTOMATIC` step on one of those would sit
/// beside a scope seek that is still there and still named, so rule 1 is satisfied; and because the
/// step is spelled `SEARCH` rather than `SCAN`, `scannedRelation` returns nil for it and rule 2 does
/// not see it either. Both rules would certify a plan that rebuilds a b-tree over a relation on
/// every execution.
///
/// No such plan has been observed on these eight — stated plainly, because a rule justified by a
/// defect that did not happen is how the sentence above went wrong. Rule 3 is written against a
/// shape the other two are structurally blind to, not against a measurement.
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
/// Two issues per arm rather than one is the redundancy the rules paragraph above admits to: on this
/// statement rule 1 alone would have gone red, and rule 3 reports the same regression a second time.
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
    /// One entry, and the shortness is the point: **the inventory is not on this list under any
    /// alias.** `json_each` is a co-routine over a bound array. Every relation an almanac statement
    /// touches other than that one is either the merged inventory, a translation table beside it, or
    /// the contributor's own `visits` — and walking any of them is now a regression this file
    /// catches.
    ///
    /// **`visits` and `v` were on this list until `AppSchema` v19, and were taken off by
    /// measurement rather than by tidying.** They were here because both statements that touch the
    /// contributor's record walked it: `firstBloom` drove from `visits` end to end, and
    /// `youngTreesWithoutVisits` walked it once per candidate tree because its `COLLATE NOCASE`
    /// could not reach a BINARY `idx_visits_tree`. v19 ended both, and the second one was not
    /// predicted — the round expected only the young-tree flip:
    ///
    /// - `youngTreesWithoutVisits` → `SEARCH v USING INDEX idx_visits_tree (tree_uuid=? AND
    ///   captured_at>?)`, from the recollation. `theYoungTreeSubquerySeeksTheRecollatedIndex` pins it.
    /// - `firstBloom` → `SEARCH v USING INDEX idx_visits_captured (captured_at>?)`, in both arms,
    ///   from an index v19 added for the *journal*: the statement bounds `captured_at` to this year
    ///   (SCREENS.md 12 §2), and `idx_visits_captured` leads on `captured_at`, so the year bound
    ///   became a range seek. Nothing in `AlmanacQueries` changed for it.
    ///
    /// Keeping the two entries would have left a permission nothing used, which is the same artifact
    /// as a stale pin: a later edit could put either walk back and rule 2 would certify it. The
    /// narrowing was verified before it was written — with this list cut to `["json_each"]`,
    /// `plansStayIndexedAndBuildNothing` passes on all nine statements in both arms.
    private static let scannable: Set<String> = ["json_each"]

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

    // MARK: - The one collated join that stays, pinned as the seek v19 gave it

    /// **The young-tree subquery's plan, pinned as the seek `AppSchema` v19 made available.**
    ///
    /// This gate was written to pin a `SCAN v`, and it pinned one honestly:
    /// `AlmanacQueries.youngTreesWithoutVisitsSQL(scope:)` compares
    /// `v.tree_uuid = t.uuid COLLATE NOCASE`, and while `idx_visits_tree` was `BINARY` no NOCASE
    /// comparison could seek it. That pin named the event that would end it — "the day a migration
    /// gives `visits.tree_uuid` a case-insensitive index … this test goes red on the first half and
    /// the paragraph has to be rewritten deliberately, rather than staying wrong."
    ///
    /// **v19 is that migration**, and it is the reason this is a rewrite rather than a relaxation.
    /// It recreates `idx_visits_tree` as `(tree_uuid COLLATE NOCASE, captured_at DESC)`, so the
    /// statement — unchanged, still collated, still right about a mixed-case `visits` row — reaches
    /// it. Both of R29's arms now plan
    /// `SEARCH v USING INDEX idx_visits_tree (tree_uuid=? AND captured_at>?)`, measured
    /// 0.319 ms → 0.008 ms per candidate tree; a §4 card with 200 candidates goes 64 ms → 1.5 ms.
    /// The pin is therefore inverted: it **requires** the seek, requires both of the constraints the
    /// index can carry, and forbids the walk.
    ///
    /// Rule 2 now forbids that walk too — v19 took `visits` and `v` off `scannable`, because it also
    /// gave `firstBloom` a seek and left the almanac with no walk of the contributor's record at
    /// all. That is deliberate overlap and it is worth its cost: rule 2 catches the walk coming back
    /// on any statement, and this test says which index the walk is supposed to have been replaced
    /// by, which rule 2 cannot.
    ///
    /// ── The counterfactual, which v19 inverted too ──────────────────────────────────────────────
    /// The old form of this test built `v.tree_uuid = upper(t.uuid)` by substitution and showed that
    /// it *would* seek: against a BINARY index, normalizing the seed side up was the only way to
    /// reach one, and the statement declined to because nothing constrains the case of a stored
    /// `visits` uuid. That is now backwards, and being backwards is the cleanest proof available
    /// that the collation is what does the work. `upper(t.uuid)` leaves `v.tree_uuid` bare, so the
    /// comparison takes the **column's** collation — still `BINARY`, because v19 recollated the
    /// index and not the column — and a BINARY comparison cannot reach a NOCASE index. Measured,
    /// both arms: `SEARCH v USING INDEX idx_visits_captured (captured_at>?)`, a range on the wrong
    /// index.
    ///
    /// Two substitutions are checked, because they are the two edits that would silently undo this:
    /// `upper()` on the seed side (the rewrite this statement used to be tempted by) and simply
    /// deleting the `COLLATE NOCASE` (the "simplification"). Neither may reach `idx_visits_tree`.
    /// Each `#require`s that its substitution matched, which is what keeps a counterfactual from
    /// quietly explaining the shipped statement instead.
    ///
    /// **Calibration.** With only v19's DDL reverted — `AppSchema.v19`'s index statements, nothing
    /// else, so `idx_visits_tree` goes back to BINARY — this test goes red in both arms on the seek
    /// it requires, reporting the `SCAN v` it used to pin, *and* on the `upper()` counterfactual,
    /// which reaches `idx_visits_tree` again exactly as the old test asserted. Four issues. The
    /// verbatim messages are in the pull request. No expectation here passes vacuously.
    @Test("the young-tree subquery seeks the recollated visits index, and neither rewrite of it can")
    func theYoungTreeSubquerySeeksTheRecollatedIndex() async throws {
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

                let seeks = steps.filter { $0.contains("SEARCH") && $0.contains("idx_visits_tree") }
                #expect(
                    !seeks.isEmpty,
                    """
                    the young-tree subquery no longer seeks `idx_visits_tree` in the \(arm.name) \
                    arm, so every candidate tree walks the reader's visits again — the plan \
                    AppSchema v19 recollated that index to remove, at 0.319 ms per tree against \
                    0.008 — \(plan)
                    """
                )
                #expect(
                    seeks.contains(where: { $0.contains("tree_uuid=?") && $0.contains("captured_at") }),
                    """
                    the \(arm.name) arm reaches `idx_visits_tree` on fewer of its columns than the \
                    subquery bounds: `captured_at >= t.planted_on` is a range this index carries \
                    beside `tree_uuid`, and a seek that drops it re-reads rows the index could have \
                    skipped — \(seeks.joined(separator: " | "))
                    """
                )
                #expect(
                    !steps.contains(where: { GroveQueryPlanTests.scannedRelation(in: $0) == "v" }),
                    """
                    the young-tree subquery walks `visits` end to end in the \(arm.name) arm — the \
                    plan v19 removed, at one pass over the reader's whole record per candidate \
                    tree. Rule 2 reports this too, since v19 took `v` off the allowlist; this \
                    expectation is the one that names the index it should have used — \(plan)
                    """
                )

                // The two rewrites that would give the seek back to BINARY, each built by
                // substitution from the shipped text so a statement rewrite is reported, not
                // explained away.
                let collated = "v.tree_uuid = t.\(schema.treeIdentityColumn) COLLATE NOCASE"
                let rewrites = [
                    ("`upper()` on the seed side", "v.tree_uuid = upper(t.\(schema.treeIdentityColumn))"),
                    ("bare, with the collation deleted", "v.tree_uuid = t.\(schema.treeIdentityColumn)")
                ]
                for (name, replacement) in rewrites {
                    let hypothetical = sql.replacingOccurrences(of: collated, with: replacement)
                    try #require(
                        hypothetical != sql,
                        """
                        the substitution matched nothing, so the \(name) counterfactual below is \
                        explaining the shipped statement rather than a rewrite of it. The collated \
                        comparison in `youngTreesWithoutVisitsSQL` has been rewritten — re-derive \
                        this test
                        """
                    )
                    let wouldBe = try connection.queryPlan(for: hypothetical)
                    #expect(
                        !wouldBe.contains(where: { $0.contains("SEARCH") && $0.contains("idx_visits_tree") }),
                        """
                        the \(name) form still seeks `idx_visits_tree` in the \(arm.name) arm, so \
                        the statement's `COLLATE NOCASE` is not what buys the seek and the \
                        expectation above is measuring something else. `visits.tree_uuid` is a \
                        BINARY column; v19 recollated its index, not the column — \
                        \(wouldBe.joined(separator: " | "))
                        """
                    )
                }
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
