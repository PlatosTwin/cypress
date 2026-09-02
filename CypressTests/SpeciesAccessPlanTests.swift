import Foundation
import Testing
@testable import Cypress

/// **The reads v20 moved onto an index, explained — and the contract one half of them stands on.**
///
/// Three families, all dead the same way before this round: an index existed, or a primary key did,
/// and the reader could not reach it because a `COLLATE NOCASE` comparison overrides the BINARY
/// collation the index was built with. `GroveQueryPlanTests` states the two rules this file uses
/// and its header carries the argument for each; they are not restated here. What is different is
/// how the statements are obtained.
///
/// ── The statements are the ones the app runs, and that is measured rather than asserted ──────
/// `JournalQueryPlanTests`' header records the experiment that matters here: appending `" -- drift"`
/// to a statement the app builds makes it run text no plan gate has ever seen, while a gate that
/// reads the SQL off a property stays green. Referencing a property from a test makes the property
/// exist; it does not make the property be what runs.
///
/// So this file does not read any SQL off a property. It installs a `StatementCensus`, **calls the
/// readers**, and plans the text they actually prepared. A statement whose text drifts is planned
/// in its drifted form; a reader that stops being called at all fails the count assertion before
/// any plan is examined.
///
/// **Thirteen statements, and the number is the `#require`s rather than a tally kept by hand.**
/// `theSpeciesChainSeeks` requires 2, `theCommunityRowsSeek` 6, `theSpeciesLookupsSeek` 4, and
/// `theSpeciesFilterSeeks` 1 — 2 + 6 + 4 + 1 = 13. This said "the eleven readers" until PR #148's
/// review counted them; the DDL-revert distribution below confirms the thirteen arithmetically,
/// since its 19 issues are 12 + 4 + 3 over those same statements. A count in prose beside four
/// assertions that carry the real one is exactly the thing CONTRIBUTING's pass 4 is looking for.
///
/// ── Calibration ─────────────────────────────────────────────────────────────────────────────
/// v20 has two halves that revert independently, and both were reverted separately on this branch.
/// **They fail different tests**, which is what says this file measures two things rather than one
/// thing twice. Run with `SchemaV20Tests` beside it, 9 tests:
///
/// - **DDL only** (v20's statement body replaced by `SELECT 1`, so the migration still runs and
///   does nothing; the `lower()` query changes left in place): **3 tests fail, 19 issues.**
///   `theCommunityRowsSeek` takes 12 — six statements, each failing twice, once for the missing
///   `SEARCH` and once for walking `community_trees`, and the six plans in the messages are the
///   three `UPDATE`s and `tree(id:)` at `SCAN community_trees`, `trees(ids:)` at
///   `SCAN community_trees | LIST SUBQUERY 1 | SCAN json_each …`, and `exists(id:)` at
///   `SCAN community_trees USING COVERING INDEX sqlite_autoindex_community_trees_1` — the covering
///   walk that wears the index's name, which is why the rule asks for `SEARCH` and not for the
///   name. `theSpeciesChainSeeks` takes 4, the same two-per-statement shape, at
///   `SCAN main.species_assertions | USE TEMP B-TREE FOR ORDER BY` and
///   `SCAN main.species_assertions USING INDEX idx_species_assertions_head`.
///   `SchemaV20Tests.theIndexesCarryTheirCollation` takes 3 — `idx_species_assertions_tree` stored
///   without the collation, and `idx_community_trees_id` absent, which is two on its own. The
///   species half stays **green** throughout: it is the seed's own index and no migration touches
///   it.
/// - **SQL only** (the five `lower()` comparisons put back to `COLLATE NOCASE`; the v20 DDL left in
///   place): **3 tests fail, 7 issues**, and not one of them is a test the DDL revert failed.
///   `theSpeciesLookupsSeek` takes 4, one per statement it plans; `theSpeciesFilterSeeks` takes 1,
///   which is the fifth reader; `theProbeMatchesTheComparisonTheAppMakes` takes 2, one for the
///   missing `lower(:uuid)` and one for the `COLLATE NOCASE` that came back. `SchemaV20Tests`
///   stays green — the indexes are there, nothing is asking for them — and so do the two migration
///   plan tests, because `species` is in the read-only seed and the migration never touched it.
///
/// The two distributions share no failing test, which is the property that says the round's two
/// halves are independently gated rather than both resting on one assertion.
///
/// Both reverts were restored by copying the files back and the suite re-run green, because
/// `git checkout --` on a file carrying both the revert and the fix takes the fix with it.
@Suite("Species and community · access plans")
struct SpeciesAccessPlanTests {

    private static let moment = Date(timeIntervalSince1970: 1_790_000_000)

    private static func store() async throws -> CypressStore {
        let seedURL = try #require(SeedContractTests.seedURL, "no seed database; set CYPRESS_SEED_PATH")
        return try await CypressStore.inMemory(seedURL: seedURL)
    }

    /// Runs `body` with a census installed and returns the distinct statements it prepared, in
    /// order of first appearance.
    private static func captured(
        _ store: CypressStore,
        _ body: @Sendable (CypressStore) async throws -> Void
    ) async throws -> [String] {
        let census = StatementCensus()
        await store.queue.installCensus(census)
        defer { Task { await store.queue.installCensus(nil) } }
        try await body(store)
        var seen: Set<String> = []
        return census.statements.filter { seen.insert($0).inserted }
    }

    /// Plans every statement and returns them paired, failing loudly on a statement that no longer
    /// prepares against the real schema.
    private static func plans(
        _ statements: [String],
        _ store: CypressStore
    ) async throws -> [(sql: String, steps: [String])] {
        try await store.queue.read { connection in
            try statements.map { sql in
                let steps = try connection.queryPlan(for: sql)
                #expect(!steps.isEmpty, "EXPLAIN QUERY PLAN produced no steps for:\n\(sql)")
                return (sql, steps)
            }
        }
    }

    /// Asserts every statement seeks `index`, and that none of them walks `table` or builds an
    /// index at run time.
    ///
    /// `SEARCH` **and** the index name, together: `GroveQueryPlanTests`' rule 1 exists because
    /// `SCAN t USING INDEX x` contains the index's name while walking the whole relation, so a
    /// gate that looked for the name alone would pass on the defect it is written to catch.
    private static func expectSeeks(
        _ planned: [(sql: String, steps: [String])],
        index: String,
        table: String,
        was: String,
        gain: String
    ) {
        for (sql, steps) in planned {
            let plan = steps.joined(separator: " | ")
            let seeks = steps.filter { $0.contains("SEARCH") && $0.contains(index) }
            #expect(
                !seeks.isEmpty,
                """
                this statement does not SEARCH \(index). Before v20 it planned `\(was)`, and the \
                measured cost of losing the seek again is \(gain). The collation on that index is \
                what lets the predicate reach it — a plan without the seek has lost the round's \
                whole effect.
                \(sql)
                — \(plan)
                """
            )
            #expect(
                !steps.contains(where: { GroveQueryPlanTests.scannedRelation(in: $0) == table }),
                "this statement walks \(table) end to end as well as seeking it:\n\(sql)\n— \(plan)"
            )
            // `AUTOMATIC PARTIAL COVERING INDEX` is SQLite deciding mid-execution that a relation is
            // walked often enough to index on the spot: a missing index reported as a `SEARCH`,
            // which is the exact spelling every rule above looks for. `AlmanacQueryPlanTests` is
            // where this check was written.
            let automatic = steps.filter { $0.contains("AUTOMATIC") }
            #expect(
                automatic.isEmpty,
                "SQLite builds an index at run time — \(automatic.joined(separator: " | ")):\n\(sql)"
            )
        }
    }

    // MARK: - 1. The species chain

    /// **Both `SpeciesAssertionStore` readers seek `idx_species_assertions_tree`.**
    ///
    /// Measured before v20 on the shipped schema: `chain` planned `SCAN species_assertions` plus a
    /// full `USE TEMP B-TREE FOR ORDER BY`, and `current` planned
    /// `SCAN species_assertions USING INDEX idx_species_assertions_head` — a walk of the whole head
    /// index wearing that index's name.
    ///
    /// **Both are pinned to the same index on purpose.** `current` reaching
    /// `idx_species_assertions_tree` rather than the head index is the measurement that let v20
    /// leave the head index's BINARY collation alone, and leaving it alone is what keeps v14's
    /// partial UNIQUE invariant meaning what it meant (`SchemaV20Tests
    /// .theHeadIndexKeepsItsBinaryCollation`). If `current` ever goes back to the head index this
    /// fails, and the argument in `AppSchema.v20` has to be re-made rather than assumed.
    @Test("the species chain's two readers seek the recollated index")
    func theSpeciesChainSeeks() async throws {
        let store = try await Self.store()
        let tree = UUID()
        let statements = try await Self.captured(store) { store in
            try await store.queue.read { connection in
                let assertions = SpeciesAssertionStore()
                _ = try assertions.chain(treeID: tree, connection: connection)
                _ = try assertions.current(treeID: tree, connection: connection)
            }
        }
        try #require(
            statements.count == 2,
            "expected the two chain readers to prepare two statements, got \(statements.count): \(statements)"
        )
        Self.expectSeeks(
            try await Self.plans(statements, store),
            index: "idx_species_assertions_tree",
            table: "species_assertions",
            was: "SCAN species_assertions",
            gain: "the whole chain table per tree profile opened"
        )
    }

    // MARK: - 2. The community rows

    /// **All six `CommunityTreeStore` statements that predicate on `id` seek `idx_community_trees_id`.**
    ///
    /// Every one of them planned a bare `SCAN community_trees` before v20, in both the `=` and the
    /// `id COLLATE NOCASE IN (SELECT value FROM json_each(:ids))` forms — `community_trees.id` is a
    /// rowid table's `TEXT PRIMARY KEY`, so its index is `sqlite_autoindex_community_trees_1`,
    /// SQLite's own, BINARY, with no `CREATE INDEX` text to recollate. v20 puts a NOCASE index
    /// beside it rather than rebuilding the table.
    ///
    /// **Six, and the count is asserted.** These are three writes and three reads; a seventh
    /// statement appearing means a new `community_trees` path nobody planned, and a sixth going
    /// missing means a reader stopped being exercised and its plan stopped being gated.
    @Test("every community-tree statement that names an id seeks the id index")
    func theCommunityRowsSeek() async throws {
        let store = try await Self.store()
        let tree = UUID(), species = UUID()
        let statements = try await Self.captured(store) { store in
            try await store.queue.write { connection in
                let community = CommunityTreeStore()
                _ = try community.claimSpecies(
                    treeID: tree, speciesID: species, at: Self.moment, connection: connection
                )
                _ = try community.setSpecies(
                    treeID: tree, speciesID: species, at: Self.moment, connection: connection
                )
                _ = try community.withdraw(treeID: tree, at: Self.moment, connection: connection)
                _ = try community.tree(id: tree, connection: connection)
                _ = try community.trees(ids: [tree], connection: connection)
                _ = try community.exists(id: tree, connection: connection)
            }
        }
        try #require(
            statements.count == 6,
            """
            expected the six id-predicated community statements, got \(statements.count). A \
            seventh is a path nobody planned; a fifth means a reader stopped being exercised and \
            its plan stopped being gated: \(statements)
            """
        )
        Self.expectSeeks(
            try await Self.plans(statements, store),
            index: "idx_community_trees_id",
            table: "community_trees",
            was: "SCAN community_trees",
            gain: "a walk of every community row the contributor has added, per lookup"
        )
    }

    // MARK: - 3. The species lookups

    /// **The five `species.uuid` readers seek `sqlite_autoindex_species_1`.**
    ///
    /// This is the half of v20 that is not a migration: `species` lives in the read-only seed, so
    /// there is no index to recollate and the comparison had to move instead. All five planned a
    /// walk of the seed's 731 species before the change — `SCAN s` for the bare lookup, and
    /// `SCAN s USING COVERING INDEX sqlite_autoindex_species_1` for the ones whose projection the
    /// index covers, which is the same walk wearing the index's name.
    ///
    /// Measured on the bundled seed, per statement: `species(id:)` 0.044 → 0.010 ms,
    /// `speciesRowIDs` 0.063 → 0.034 for 25 uuids, `cityTreeCount` 1.13 → 1.10,
    /// `treeCount` 5.75 → 1.10 on the 1,200 m radius arm and 1.46 → 0.94 on the neighborhood arm,
    /// and `nearest(speciesID:)` 10.36 → 1.38 at `AlmanacLimits.fallbackRadiusM`.
    @Test("every species-by-uuid reader seeks the seed's identity index")
    func theSpeciesLookupsSeek() async throws {
        let store = try await Self.store()
        let schema = try #require(store.seed, "the store opened without a seed attached")
        let species = SpeciesQueries(schema: schema)
        let trees = TreeQueries(schema: schema, seedHasSoftDeletedTrees: store.seedHasSoftDeletedTrees)
        let id = UUID()

        let statements = try await Self.captured(store) { store in
            try await store.queue.read { connection in
                _ = try species.species(id: id, connection: connection)
                _ = try species.cityTreeCount(speciesID: id, connection: connection)
                _ = try species.treeCount(
                    speciesID: id,
                    scope: .radius(
                        center: Coordinate(latitude: 37.7694, longitude: -122.4862),
                        meters: AlmanacLimits.fallbackRadiusM
                    ),
                    connection: connection
                )
                _ = try trees.nearest(
                    to: Coordinate(latitude: 37.7694, longitude: -122.4862),
                    radiusM: AlmanacLimits.fallbackRadiusM,
                    limit: 20,
                    speciesID: id,
                    connection: connection
                )
            }
        }
        // **Four here, and the fifth reader is in the next test.** The four public readers above
        // are what a census can call directly, and they prepare one statement each. `speciesRowIDs`
        // is the fifth; it is private, reached through the map's species filter, and planned by
        // `theSpeciesFilterSeeks` below. This comment used to say "Five statements" immediately
        // above the `#require(count == 4)` on the next line — it was counting readers in a sentence
        // about statements (PR #148 review).
        try #require(
            statements.count == 4,
            "expected four species-by-uuid statements, got \(statements.count): \(statements)"
        )
        Self.expectSeeks(
            try await Self.plans(statements, store),
            index: "sqlite_autoindex_species_1",
            table: "species",
            was: "SCAN s",
            gain: "all 731 species walked per lookup"
        )
    }

    /// **The map's species filter, which reaches `speciesRowIDs` — the fifth reader.**
    ///
    /// Private, so it is exercised through the public call that uses it rather than named directly.
    /// It is the one written as an `IN` over a bound list, and it is where the placement lesson
    /// lives: `… IN (…) COLLATE NOCASE` binds the collation to the subquery rather than to the
    /// comparison and answers zero, so v20 normalizes the list with `lower(value)` instead of
    /// collating anything.
    @Test("the map's species filter seeks rather than walking the catalogue")
    func theSpeciesFilterSeeks() async throws {
        let store = try await Self.store()
        let schema = try #require(store.seed, "the store opened without a seed attached")
        let trees = TreeQueries(schema: schema, seedHasSoftDeletedTrees: store.seedHasSoftDeletedTrees)

        let viewport = MapViewport(
            bounds: BoundingBox(
                minLatitude: 37.76, maxLatitude: 37.79,
                minLongitude: -122.45, maxLongitude: -122.41
            ),
            zoom: 16,
            pinLimit: 500,
            speciesIDs: [UUID(), UUID()]
        )
        let statements = try await Self.captured(store) { store in
            try await store.queue.read { connection in
                _ = try trees.narrowing(for: viewport, connection: connection)
            }
        }
        let rowIDStatements = statements.filter { $0.contains("species_rowid") }
        try #require(
            rowIDStatements.count == 1,
            """
            the species filter no longer prepares `speciesRowIDs`, so this gate planned nothing — \
            \(statements)
            """
        )
        Self.expectSeeks(
            try await Self.plans(rowIDStatements, store),
            index: "sqlite_autoindex_species_1",
            table: "species",
            was: "SCAN sp USING COVERING INDEX sqlite_autoindex_species_1",
            gain: "all 731 species walked per viewport with a filter on"
        )
    }

    // MARK: - 4. The contract the species half stands on

    /// **`species.uuid` is stored lower case in the shipped seed.**
    ///
    /// `lower(:uuid)` matches only what is already lower case, so the five readers above are correct
    /// exactly while every published file keeps that property. It is true of the bundle — 0 of 731 —
    /// and was, until this round, an unasserted property of a file this repository does not build.
    ///
    /// A file that broke it would not be slow. The comparison would match nothing: no field guide
    /// entry, no `In this inventory` or `Near you` count, no `Nearby individuals`, and an empty
    /// species filter on the map. Silence, on screens with no error state for it.
    @Test("the bundled seed stores its species uuids in lower case")
    func theBundledSeedHasLowercaseSpeciesUUIDs() async throws {
        let store = try await Self.store()
        let arms = store.inventory?.arms ?? []
        #expect(!arms.isEmpty, "no inventory is attached, so this gate examined nothing")
        let shouty = try await DataGates.armsWithUppercaseSpeciesUUIDs(store)
        #expect(shouty.isEmpty, "\(shouty) store species.uuid in something other than lower case")
    }

    /// **And the same question put to a downloaded pack, with the answer known in advance both
    /// times.**
    ///
    /// `GroveQueryPlanTests.theLowercaseUUIDContractCanFailOnAPack`'s shape, for its reasons. The
    /// gate above loops over one arm and always will, because the suite opens the bundle alone; the
    /// shape it exists to catch is a *pack*, whose rows reach the same five comparisons. So this
    /// asks it of a union: a pack that keeps the contract is accepted, and the same pack with its
    /// species uuids upper-cased is named. The negative control is here rather than in a red-proof
    /// on purpose — a red-proof shows the instrument worked on the day somebody ran it, this shows
    /// it works on every run.
    ///
    /// The pack is a **copy of the shipped seed**, for the reason that file gives at length: the
    /// catalogue merges species on uuid, so a hand-built fixture beside the real seed is refused by
    /// the union and the test would quietly be back to examining one file.
    ///
    /// ── Why the broken pack carries ONE ADDED species and not 731 upper-cased ones ────────────
    /// The trees gate breaks its pack with `UPDATE trees SET uuid = upper(uuid)`, and the obvious
    /// translation here — `UPDATE species SET uuid = upper(uuid)` — **cannot be attached at all**,
    /// which the first draft of this test discovered by being red: `badArms → 1`, the pack refused.
    /// That is the union working exactly as `InventoryUnionSQL.createSpecies` documents.
    /// `species.uuid` is the key later arms merge on, so upper-casing all 731 makes every one of
    /// them unknown to the catalogue and re-inserted — and each re-insert carries a
    /// `scientific_name` the catalogue already has, against a UNIQUE index. The arm's own `INSERT`
    /// throws inside its `contributing` block and the file is refused, whole.
    ///
    /// So a pack cannot break this contract on a species the bundle already knows. What it *can*
    /// do, and what this fixture is, is carry a **new** species — one the catalogue has never seen,
    /// with a scientific name that collides with nothing — whose uuid is upper case. That merges
    /// cleanly, attaches, and reaches all five comparisons as a species no `lower(:uuid)` will ever
    /// match. It is the reachable failure, and it is the one worth a control.
    @Test("the lowercase species-uuid contract is asked of each arm, and can fail on a pack")
    func theSpeciesContractCanFailOnAPack() async throws {
        let seedURL = try #require(SeedContractTests.seedURL, "no seed database; set CYPRESS_SEED_PATH")
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("speciesplan-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let wellFormed = dir.appendingPathComponent("lower.sqlite")
        let shouty = dir.appendingPathComponent("upper.sqlite")
        try FileManager.default.copyItem(at: seedURL, to: wellFormed)
        try FileManager.default.copyItem(at: seedURL, to: shouty)
        // The one difference: one species the catalogue has never seen, whose uuid is upper case.
        // Valid in every other respect — 36 characters, unique, parses as a UUID, and its
        // scientific name collides with nothing — which is precisely why no other gate notices it.
        // See the doc comment for why this is an added row rather than `upper(uuid)` over all 731.
        let scrub = try SQLiteConnection(path: shouty.path)
        try scrub.execute("""
            INSERT INTO species
                (id, uuid, scientific_name, common_name, id_tips, seasonal, care_notes,
                 curated, created_at, updated_at)
            VALUES ((SELECT MAX(id) + 1 FROM species),
                    'AAAAAAAA-0000-4000-8000-00000000FFFF',
                    'Cypressus nonexistentia', NULL, '[]', '{}', '[]', 0,
                    '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z');
            """)

        let good = try await CypressStore.inMemory(inventories: [
            .bundled(url: seedURL),
            InventoryFile(id: "manhattan", url: wellFormed, isBundled: false)
        ])
        let goodArms = good.inventory?.arms.count ?? 0
        try #require(
            goodArms == 2,
            """
            the union opened \(goodArms) arms, not 2 — the pack was refused, so this proves \
            nothing about n > 1: \(good.inventory?.refused ?? [])
            """
        )
        let accepted = try await DataGates.armsWithUppercaseSpeciesUUIDs(good)
        #expect(accepted.isEmpty, "a pack that keeps the contract was reported as breaking it: \(accepted)")

        let bad = try await CypressStore.inMemory(inventories: [
            .bundled(url: seedURL),
            InventoryFile(id: "manhattan", url: shouty, isBundled: false)
        ])
        let badArms = bad.inventory?.arms.count ?? 0
        try #require(
            badArms == 2,
            """
            the pack carrying an upper-case species uuid was refused rather than opened, so this \
            proves nothing: \(bad.inventory?.refused ?? []). A refusal here means the fixture broke \
            the catalogue merge instead of the collation contract — see this test's doc comment, \
            which records the version of it that did exactly that
            """
        )
        let caught = try await DataGates.armsWithUppercaseSpeciesUUIDs(bad)
        #expect(
            caught == ["manhattan"],
            """
            the gate reported \(caught) for a union whose pack stores upper-case species uuids. It \
            has to be exactly the pack: an empty answer means the gate cannot fail at n > 1, and an \
            answer naming the bundle means it is reading the wrong file
            """
        )
    }

    /// **The seed-contract probe compares the way the app compares.**
    ///
    /// `DataGates.seedContract` carries a list of index-availability probes, and the species one
    /// read `s.uuid = 'x'` — a BINARY equality no statement in `Cypress/` emits. It passed
    /// throughout the years the five real readers were walking the table, because the index it
    /// names is perfectly reachable from a comparison nobody writes. That is this project's
    /// dominant test defect exactly: a guard green because the case it guards is not present.
    ///
    /// This pins the repair rather than trusting it — the probe must use `lower(`, so a future
    /// edit that quietly puts the BINARY literal back fails here instead of going unnoticed for
    /// another few rounds.
    ///
    /// ── It did not, for one round, and the shape of that miss is the point ──────────────────────
    /// As first written this test read `SpeciesQueries.species(id:)`'s captured SQL and asserted on
    /// **that**. So the test named for the probe never read the probe: reverting only
    /// `DataGates.speciesIdentityProbeSQL` to `s.uuid = 'x'` — the exact literal this round
    /// identifies as the years-long defect — left the whole suite green, which PR #148's review
    /// demonstrated. A guard green because the case it guards is not present, in the guard written
    /// to close exactly that. It is the third instance of the family in this round's own diff.
    ///
    /// **Both halves are asserted now, and they are the two that can drift apart.** The probe is
    /// read out of `DataGates` rather than restated here, so this fails on a one-line edit there;
    /// the app statement is captured from a real call, so it fails on a one-line edit in
    /// `SpeciesQueries`. Asserting only one of them is what went wrong, so neither is dropped for
    /// being redundant with the other — they are two different files.
    @Test("the seed contract's species probe uses the comparison the app makes")
    func theProbeMatchesTheComparisonTheAppMakes() async throws {
        // ── 1. The probe the gate actually runs, read out of the gate ───────────────────────────
        let probe = DataGates.speciesIdentityProbeSQL
        #expect(
            probe.contains("lower("),
            """
            `DataGates.speciesIdentityProbeSQL` no longer normalizes with `lower()`, so the \
            `species by uuid` plan probe is back to a BINARY equality no statement in `Cypress/` \
            emits. It will keep certifying a seek the app's own comparison cannot reach, which is \
            what it did for years before v20 — \(probe)
            """
        )
        #expect(
            !probe.uppercased().contains("COLLATE NOCASE"),
            """
            the `species by uuid` probe collates, so it is no longer the comparison the app makes \
            and the seek it certifies is not the one the five readers need — \(probe)
            """
        )

        // ── 2. The app's own statement, captured from a real call ───────────────────────────────
        let store = try await Self.store()
        let schema = try #require(store.seed, "the store opened without a seed attached")
        let species = SpeciesQueries(schema: schema)

        let statements = try await Self.captured(store) { store in
            try await store.queue.read { connection in
                _ = try species.species(id: UUID(), connection: connection)
            }
        }
        let sql = try #require(statements.first, "species(id:) prepared nothing")
        #expect(
            sql.contains("lower(:uuid)"),
            """
            `SpeciesQueries.species(id:)` no longer normalizes with `lower(:uuid)`. If it went back \
            to `COLLATE NOCASE` the seek is gone and the doc comment above it is false again; if it \
            moved the normalization into Swift, the plan gates above are explaining a statement the \
            app does not run — \(sql)
            """
        )
        #expect(
            !sql.uppercased().contains("COLLATE NOCASE"),
            "the species lookup still collates, so it cannot reach the seed's BINARY index — \(sql)"
        )

        // ── 3. And that the two are the same comparison, which is the property the name claims ──
        // Neither half above notices if one file normalizes and the other stops: each is checked
        // against a constant, not against the other. This is the assertion that makes the two
        // travel together, and it is why the probe is a property rather than a literal.
        #expect(
            probe.contains("s.uuid = lower(") && sql.contains("= lower(:uuid)"),
            """
            the probe and the app no longer compare `species.uuid` the same way, so the gate is \
            certifying an access path the app does not use — probe: \(probe) — app: \(sql)
            """
        )
    }
}
