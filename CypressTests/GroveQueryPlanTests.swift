import Foundation
import Testing
@testable import Cypress

/// **The gate that makes My Grove's collapse unrepeatable.**
///
/// Screen 08 took 13.2 s to draw forty trees and 291 ms to draw its ring, and not one line of
/// `GroveQueries` had been edited since it was written. PR #120 changed `SeedDatabase.schemaName`
/// from `"seed"` to `"temp"`, so every `\(seed).trees` stopped resolving to an attached table with
/// its own indexes and started resolving to a compound view — and the two statements that depended
/// on an index over a column the view now *computes* lost it silently. `git diff` over both query
/// files across that merge is empty. A correctness suite cannot see that, and did not: everything
/// stayed green while the screen became unusable.
///
/// So this is the same instrument `MapQueryPlanTests` is for the map, aimed at the reads behind My
/// Grove and the tree profile, and it is written to the two rules that file states:
///
/// 1. **The seek that answers the statement must be in the plan**, named, as a `SEARCH`. Not merely
///    the index's *name* somewhere in the text — `mostVisitedTree` regressed to
///    `SCAN t USING INDEX sqlite_autoindex_trees_1`, which walks the whole index and contains the
///    string a `contains` check would have accepted.
/// 2. **Nothing may scan the inventory, and nothing may materialize it.** Both are stated as an
///    allowlist of relations that are *permitted* to be scanned, each with a reason, so a plan that
///    scans anything else fails by name. That direction matters: an exclusion list goes quietly
///    vacuous the day an alias is renamed, and this project's dominant test defect is a guard that
///    stays green while the defect is present.
///
/// ── Calibration ─────────────────────────────────────────────────────────────────────────────
/// Run against the branch base (`f85ddcf`), with only the SQL reverted, **all eight** statements
/// below fail, with **14 issues** between them, and each fails for its own reason: the three uuid
/// joins and `exists` lose the `sqlite_autoindex_trees_1` seek (`mostVisitedTree` and `exists` also
/// walk `t`), the polygon arm loses `idx_trees_neighborhood`, the radius arm loses
/// `idx_trees_lat_lon`, and the two tree lookups add `MATERIALIZE temp.trees` and a `SCAN t` on top
/// of the missing seek. The distribution is in PR #131.
///
/// That is what separates this from a gate that has only ever been seen to pass — and the sentence
/// is worth stating exactly, because **it was wrong here first.** This paragraph said "five of the
/// eight" until PR #131's reviewer re-ran the experiment and counted. A calibration claim nobody
/// re-derives is the same artifact as an uncalibrated gate: in a file whose whole argument is that
/// its instrument has been shown to fail, the one sentence that must not be approximate is this one.
@Suite("My Grove · query plans")
struct GroveQueryPlanTests {

    // MARK: - Fixtures

    private static func store() async throws -> CypressStore {
        let seedURL = try #require(SeedContractTests.seedURL, "no seed database; set CYPRESS_SEED_PATH")
        return try await CypressStore.inMemory(seedURL: seedURL)
    }

    private static func schema(_ store: CypressStore) throws -> SeedSchema {
        try #require(store.seed, "the store opened without a seed attached")
    }

    /// A neighborhood the shipped seed actually holds, read out of the seed rather than written
    /// down here: a hard-coded id would silently stop being a neighborhood after a rebuild and the
    /// gate would go on explaining a query that matches nothing.
    private static func anyNeighborhood(_ store: CypressStore) async throws -> (id: Int, name: String) {
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

    /// Relations a plan may walk end to end, and why each one is small.
    ///
    /// Everything here is either the contributor's **own** rows — bounded by what one person did,
    /// tens to hundreds — or a co-routine over an answer that has already been narrowed. The
    /// inventory is not on this list under any alias, which is the whole of rule 2.
    private static let scannable: Set<String> = [
        // The four contribution tables `GroveQueries.ownContributions` unions, and the subquery
        // alias it gives them.
        //
        // **These are the tuned plan, not a concession.** This list used to say "one person's
        // record", which is true and is the wrong argument: it reads as "small enough to get away
        // with" and invites the next author to index the predicate and take them off the list. That
        // was measured in the v19 index round and it is a pessimization. `ownContributions` selects
        // by `device_id`/`user_id`, and on a personal database the caller owns most of the rows —
        // so an owner index is a covering-index walk plus a row lookup for nearly every row, in
        // place of a straight scan. At 16,000 rows and 90 % ownership, NOCASE indexes on
        // `(device_id, captured_at DESC)` and its `user_id` twin were picked up through
        // `MULTI-INDEX OR` with no query change and cost: `ownContributions` 4.72 → 7.35 ms,
        // `ContributionStore.groveRecords` 9.43 → 11.85, `groveTreeIDs` 2.20 → 2.57, the journal
        // page 6.85 → 8.75. (At 10 % ownership — a handed-down phone — they win. That is the corner
        // case, and it is not what this list is written for.)
        //
        // `noPlanUsesMultiIndexOr` below is the falsifiable half of this paragraph: it fails the
        // day somebody adds one, rather than leaving this comment to be re-derived.
        "visits", "observations", "measurements", "care_events", "c",
        // `speciesIDs`' inner `SELECT DISTINCT` — a few hundred arm-local species ids, already
        // filtered to the area. Scanning it is the plan that costs 2 ms.
        "a",
        // The `IN` list of a batched read, a virtual table over a bound JSON array.
        "json_each"
    ]

    // MARK: - Rule 1 and rule 2, over every hot statement

    /// The eight statements this file gates, read off the objects the app builds them from.
    ///
    /// Factored out of `plansStayIndexed` so `noPlanUsesMultiIndexOr` runs over the identical set:
    /// a second list would drift, and a rule that covers seven of eight statements is a rule with a
    /// hole in it that nothing reports.
    private static func gatedStatements(
        _ store: CypressStore
    ) async throws -> [(label: String, sql: String, index: String)] {
        let schema = try Self.schema(store)
        let grove = GroveQueries(schema: schema)
        let trees = TreeQueries(schema: schema, seedHasSoftDeletedTrees: store.seedHasSoftDeletedTrees)
        let hood = try await Self.anyNeighborhood(store)
        try #require(hood.id > 0, "the seed carries no neighborhoods, so the polygon arm is untested")

        /// label, the statement the app runs, and the index whose `SEARCH` must answer it.
        return [
            // The three uuid joins. `sqlite_autoindex_trees_1` is the index SQLite derives from
            // `trees.uuid NOT NULL UNIQUE`; a NOCASE comparison cannot seek it, which is cause A.
            ("the resident neighborhood", grove.residentNeighborhoodSQL, "sqlite_autoindex_trees_1"),
            ("the most-visited tree", grove.mostVisitedTreeSQL, "sqlite_autoindex_trees_1"),
            ("the species the contributor knows", grove.knownSpeciesSQL, "sqlite_autoindex_trees_1"),
            // The ring's denominator, both of R29's arms. The polygon arm is the one #120 broke.
            (
                "the ring's denominator, by polygon",
                grove.speciesIDsSQL(scope: .neighborhood(id: hood.id, name: hood.name)),
                "idx_trees_neighborhood"
            ),
            (
                "the ring's denominator, by radius",
                grove.speciesIDsSQL(scope: .radius(
                    center: Coordinate(latitude: 37.7694, longitude: -122.4862),
                    meters: AlmanacLimits.fallbackRadiusM
                )),
                "idx_trees_lat_lon"
            ),
            // The tree reads. `treeSQL` is the profile's; `treesSQL` is the Grove's batched form;
            // `existsSQL` stands in front of every write.
            ("one tree by uuid", trees.treeSQL(), "sqlite_autoindex_trees_1"),
            ("a grove's worth of trees by uuid", trees.treesSQL(), "sqlite_autoindex_trees_1"),
            ("whether a tree is in the inventory", trees.existsSQL, "sqlite_autoindex_trees_1")
        ]
    }

    @Test("every hot Grove and tree statement seeks its index, and none of them walks the inventory")
    func plansStayIndexed() async throws {
        let store = try await Self.store()
        let statements = try await Self.gatedStatements(store)

        try await store.queue.read { connection in
            for (label, sql, index) in statements {
                let steps = try connection.queryPlan(for: sql)
                let plan = steps.joined(separator: " | ")

                // Rule 1. A `SEARCH` naming the index, not the index's name anywhere in the text.
                let seeks = steps.filter { $0.contains("SEARCH") && $0.contains(index) }
                #expect(!seeks.isEmpty, "\(label): nothing SEARCHes \(index) — \(plan)")

                // Rule 2a. Nothing is materialized. Under the union this is the signature of a
                // statement that made the view the right operand of a LEFT JOIN, and it costs the
                // whole inventory copied into a temp b-tree per execution.
                let materialized = steps.filter { $0.contains("MATERIALIZE") }
                #expect(
                    materialized.isEmpty,
                    "\(label): materializes a relation — \(materialized.joined(separator: " | "))"
                )

                // Rule 2b. Everything walked end to end is on the allowlist above, by name.
                let scanned = steps.compactMap { Self.scannedRelation(in: $0) }
                let unexpected = scanned.filter { !Self.scannable.contains($0) }
                #expect(
                    unexpected.isEmpty,
                    """
                    \(label): walks \(unexpected.sorted()) end to end, which is not on the \
                    permitted list \(Self.scannable.sorted()) — \(plan)
                    """
                )
            }
        }
    }

    // MARK: - Rule 3, which is the allowlist's argument made falsifiable

    /// **No Grove plan may answer the owner predicate through `MULTI-INDEX OR`.**
    ///
    /// This is the one shape that turns the allowlist above from an admission into a claim. The
    /// four contribution tables are scanned because scanning them is *right* — the caller owns most
    /// of the rows on their own phone — and the comment on `scannable` carries the measurements. An
    /// author who reads "walks `visits` end to end" as a defect will reach for the obvious fix, an
    /// index on `device_id` and `user_id`; SQLite will accept it with no query change at all,
    /// through `MULTI-INDEX OR`; every one of these plans will stop scanning; and every one of them
    /// will get slower. Nothing else in this file would notice — the allowlist only *permits*
    /// scans, it does not require them, and rule 1 keeps passing because the seek it names is on
    /// the inventory side.
    ///
    /// So the tuning is asserted by naming the plan that replaces it. `MULTI-INDEX OR` appears in
    /// `EXPLAIN QUERY PLAN` output only when SQLite unions two index lookups for one `OR`, which is
    /// exactly the construction here and is not a shape any of these statements has a legitimate
    /// use for.
    ///
    /// If a future round establishes that owner indexes are right — the handed-down-phone case,
    /// where the caller owns a tenth of the rows, measures the other way — the correct response is
    /// to delete this test and rewrite `scannable`'s comment with the new numbers, not to widen it.
    @Test("no Grove plan answers the owner predicate through MULTI-INDEX OR")
    func noPlanUsesMultiIndexOr() async throws {
        let store = try await Self.store()
        let statements = try await Self.gatedStatements(store)

        try await store.queue.read { connection in
            for (label, sql, _) in statements {
                let steps = try connection.queryPlan(for: sql)
                let offending = steps.filter { $0.contains("MULTI-INDEX OR") }
                #expect(
                    offending.isEmpty,
                    """
                    \(label): answers an OR through MULTI-INDEX OR — \
                    \(offending.joined(separator: " | ")). On a personal database that is slower \
                    than the scan it replaces; see the measurements on `scannable`. Full plan: \
                    \(steps.joined(separator: " | "))
                    """
                )
            }
        }
    }

    /// The relation a `SCAN` step walks, or nil for any other step.
    ///
    /// A step reads `SCAN t`, `SCAN t USING INDEX …`, `SCAN temp.cypress_hood_xlat` or
    /// `SCAN json_each VIRTUAL TABLE INDEX 1:`, sometimes behind a co-routine's tree-drawing
    /// prefix. The relation is the token after `SCAN`, minus any schema qualifier.
    ///
    /// **A `SCAN … USING COVERING INDEX` is still a scan and is still reported.** That is a
    /// deliberate difference from `MapQueryPlanTests`, which exempts it because walking
    /// `idx_trees_lat_lon` end to end is the plan the map's grouping queries are *tuned* for.
    /// Nothing here groups the whole city, so a covering walk of the inventory would be a
    /// regression here even though it is the goal there — and `mostVisitedTree`'s
    /// `SCAN t USING INDEX sqlite_autoindex_trees_1` is exactly that walk.
    static func scannedRelation(in step: String) -> String? {
        guard let range = step.range(of: "SCAN ") else { return nil }
        let rest = step[range.upperBound...]
        guard let token = rest.split(separator: " ", maxSplits: 1).first else { return nil }
        return String(token.split(separator: ".").last ?? token)
    }

    // MARK: - The seed contract the collation fix stands on

    /// **The property `lower()` depends on, asked of the shipped seed.**
    ///
    /// Three joins now normalize the *contributions* side and leave `trees.uuid` bare so its BINARY
    /// index can answer them. That is correct exactly while every published file stores its uuids
    /// in lower case. It is true of the bundle — 0 of 198,625 — and it was, until this round, an
    /// unasserted property of a file this repository does not build.
    ///
    /// A file that broke it would not be slow. The join would match nothing: no species known, no
    /// area, no tree profile. Silence, on a screen with no error state for it.
    @Test("the bundled seed stores its tree uuids in lower case")
    func theBundledSeedIsLowercase() async throws {
        let store = try await Self.store()
        let arms = store.inventory?.arms ?? []
        #expect(!arms.isEmpty, "no inventory is attached, so this gate examined nothing")
        let shouty = try await DataGates.armsWithUppercaseUUIDs(store)
        #expect(shouty.isEmpty, "\(shouty) store trees.uuid in something other than lower case")
    }

    /// **And the same question put to a downloaded pack, with the answer known in advance both
    /// times.**
    ///
    /// The gate above loops over one arm and always will, because the suite opens the bundle alone.
    /// The shape it exists to catch is a *pack* — R84 attaches downloaded files beside the bundle
    /// and their rows reach the same three joins — so this asks it of a union: a pack that keeps the
    /// contract is accepted, and the same pack with its uuids upper-cased is named. The second half
    /// is the negative control, and it is here rather than in a red-proof on purpose: a red-proof
    /// shows the instrument worked on the day somebody ran it, this shows it works on every run.
    ///
    /// The pack is a **copy of the shipped seed** for the reason
    /// `MapQueryPlanTests.theStatisticsGateRunsOverEveryArm` gives at length — the catalog merges
    /// species on uuid, so a hand-built fixture beside the real seed is refused by the union and the
    /// test would quietly be back to examining one file.
    @Test("the lowercase-uuid contract is asked of each arm, and can fail on a pack")
    func theLowercaseUUIDContractCanFailOnAPack() async throws {
        let seedURL = try #require(SeedContractTests.seedURL, "no seed database; set CYPRESS_SEED_PATH")
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("groveplan-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let wellFormed = dir.appendingPathComponent("lower.sqlite")
        let shouty = dir.appendingPathComponent("upper.sqlite")
        try FileManager.default.copyItem(at: seedURL, to: wellFormed)
        try FileManager.default.copyItem(at: seedURL, to: shouty)
        // The one difference. Upper-casing every uuid keeps the file valid in every other respect —
        // still 36 characters, still unique, still parsing as a UUID — which is precisely why no
        // other gate would notice.
        let scrub = try SQLiteConnection(path: shouty.path)
        try scrub.execute("UPDATE trees SET uuid = upper(uuid)")

        let good = try await CypressStore.inMemory(inventories: [
            .bundled(url: seedURL),
            InventoryFile(id: "manhattan", url: wellFormed, isBundled: false)
        ])
        let goodArms = good.inventory?.arms.count ?? 0
        let goodRefused = good.inventory?.refused ?? []
        try #require(
            goodArms == 2,
            """
            the union opened \(goodArms) arms, not 2 — the pack was refused, so this proves \
            nothing about n > 1: \(goodRefused)
            """
        )
        let accepted = try await DataGates.armsWithUppercaseUUIDs(good)
        #expect(accepted.isEmpty, "a pack that keeps the contract was reported as breaking it: \(accepted)")

        let bad = try await CypressStore.inMemory(inventories: [
            .bundled(url: seedURL),
            InventoryFile(id: "manhattan", url: shouty, isBundled: false)
        ])
        let badArms = bad.inventory?.arms.count ?? 0
        try #require(badArms == 2, "the upper-cased pack was refused rather than opened")
        let caught = try await DataGates.armsWithUppercaseUUIDs(bad)
        #expect(
            caught == ["manhattan"],
            """
            the gate reported \(caught) for a union whose pack stores upper-case uuids. It has to \
            be exactly the pack: an empty answer means the gate cannot fail at n > 1, and an answer \
            naming the bundle means it is reading the wrong file
            """
        )
    }
}
