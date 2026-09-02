import Foundation
import Testing
@testable import Cypress

/// **What migration v20 does to a database that already has rows in it.**
///
/// `SchemaV20Tests` is `SchemaV19Tests` aimed at the two families v19 scoped out, and it is written
/// to the same shape for the same reason: `DataGates.sqliteStore` runs the whole ladder on an empty
/// in-memory database and picks up a new version for free, so it would pass on this migration the
/// day it was written. What it cannot see is that **one of v20's two statements replaces an index
/// and changes its collation.** A recollated index is a different index; a reader whose answers
/// depend on collation would answer differently afterwards, silently, on a database that has
/// already been migrated and cannot be un-migrated.
///
/// So this file does four things `DataGates` cannot:
///
/// 1. runs the migration against a **v19 database with rows already in it**, written as rows rather
///    than through the shipping API, and asserts that v20 and only v20 is what runs;
/// 2. asks the five readers whose access paths v20 moves for their answers **before and after**, on
///    rows whose indexed ids are stored lower case while every reader binds `uuidString`'s upper —
///    the case difference the recollation is *for* — and requires the two to be identical as
///    *ordered* sequences over a fixture big enough for an order to exist — PR #146's review found
///    v19's fixture at one row per table, where "the same rows before and after" is satisfied by
///    any answer at all;
/// 3. asserts the DDL landed: the recollated index carries `COLLATE NOCASE`, and the added one
///    exists and carries it too;
/// 4. asserts the index v20 deliberately **did not** touch still has its BINARY collation.
///
/// The fourth is the one that would not occur to a reader of the diff, and it is the reason this
/// round is two statements rather than three. `idx_species_assertions_head` is a partial **UNIQUE**
/// index — v14's "one current claim per tree", D15's instrument for `tree_names` applied to the
/// same kind of invariant. Recollating it would change *which pairs of rows the schema calls a
/// conflict*, which is a decision about the invariant and not about an access path; two
/// un-superseded rows whose `tree_uuid` differs only by case are legal today and would stop being
/// legal, on databases already in the field. `theHeadIndexKeepsItsBinaryCollation` is what keeps a
/// future round from "finishing the job" without meeting that argument.
///
/// ── Calibration ─────────────────────────────────────────────────────────────────────────────
/// With v20's statement body replaced by `SELECT 1` — the migration still present, still applied,
/// doing nothing — `theIndexesCarryTheirCollation` fails with **3 issues**, measured:
/// `idx_species_assertions_tree` is stored without `COLLATE NOCASE`, and `idx_community_trees_id`
/// is absent altogether, which is two on its own (missing, and therefore no collation to check).
///
/// The other three tests stay green under that revert, and that is correct rather than a gap:
/// `aV19DatabaseRunsOnlyV20` is about the version ladder and not about what the step does;
/// `recollationChangesNoAnswer` is a *no-change* assertion that a migration doing nothing trivially
/// satisfies — it exists to catch a recollation that changes an answer, not one that is missing;
/// and the head index is BINARY before and after, so `theHeadIndexKeepsItsBinaryCollation` cannot
/// distinguish them. Under the **SQL-only** revert this whole suite stays green, because `species`
/// lives in the read-only seed and no migration touches it. The full distribution of both v20
/// reverts is in `SpeciesAccessPlanTests`.
@Suite("AppSchema · v20")
struct SchemaV20Tests {

    private static let moment = Date(timeIntervalSince1970: 1_790_000_000)
    private static let deviceID = UUID(uuidString: "9E00B47C-0000-4000-8000-000000000620")!

    /// The version this file is about, read from the code rather than written down twice.
    private static var version: Int32 { 20 }

    // MARK: - The upgrade

    /// A v19 database carrying **several** rows in each table v20 touches.
    ///
    /// **The two columns v20 indexes are stored lower case, and that is the real-world case rather
    /// than a weaker one.** `community_trees.id` and `species_assertions.tree_uuid` are written
    /// `uuidString.lowercased()` here because that is how every file this app reads stores a uuid,
    /// while every reader binds Foundation's upper-case `uuidString` — so the fixture is exactly the
    /// lower-stored / upper-bound mismatch the recollation exists to bridge, and
    /// `theFixtureIsGenuinelyMixedCase` pins it.
    ///
    /// This comment used to say "with ids in mixed case", and PR #148's review showed that was a
    /// claim about the wrong columns: `mixedID` reaches `community_trees.client_uuid` and
    /// `species_assertions.id`, neither of which either v20 index covers. The fixture was right and
    /// the sentence over it was not.
    ///
    /// Written with `execute` rather than through the shipping stores for
    /// `PhotoProvenanceTests.upgradedFromV15`'s reason: the shipping write path is not what an
    /// already-installed database was filled by, and handing the migration rows in the exact shape
    /// the current code produces tests the migration against its own author's assumptions.
    private static func v19Database(
        trees: [UUID],
        assertionTree: UUID
    ) async throws -> CypressStore {
        let store = try await CypressStore.inMemory(
            migrations: AppSchema.migrations.filter { $0.version <= 19 }
        )
        let stamp = SQLiteTimestamp.string(from: moment)
        let device = deviceID.uuidString.lowercased()

        /// Ids alternating upper and lower case. **These are the columns v20 does *not* index** —
        /// `community_trees.client_uuid` and `species_assertions.id` — so this varies the payload
        /// the migration carries across, not the access path it changes. The indexed columns are
        /// spelled lower case at their call sites, deliberately; see this function's own comment.
        func mixedID(_ index: Int) -> String {
            let raw = UUID().uuidString
            return index.isMultiple(of: 2) ? raw.lowercased() : raw
        }
        func at(_ index: Int) -> String {
            SQLiteTimestamp.string(from: moment.addingTimeInterval(-Double(index) * 3600))
        }

        try await store.queue.write { connection in
            let opened = try connection.userVersion
            #expect(opened == 19, "the fixture opened at user_version \(opened), not 19")

            // Community rows, stored lower case while every reader binds `uuidString`'s upper.
            for (index, tree) in trees.enumerated() {
                try connection.execute("""
                    INSERT INTO community_trees
                        (id, client_uuid, lat, lon, status, verification_state,
                         created_at, updated_at)
                    VALUES ('\(tree.uuidString.lowercased())','\(mixedID(index))',
                            \(37.77 + Double(index) / 1000.0), \(-122.42 - Double(index) / 1000.0),
                            'alive','unverified','\(at(index))','\(stamp)');
                    """)
            }

            // A species chain: four assertions on one tree, three superseded and one head. The
            // partial UNIQUE index permits exactly one un-superseded row per `tree_uuid`, so the
            // chain is built stamped rather than left with four heads.
            let treeText = assertionTree.uuidString.lowercased()
            let ids = (0..<4).map { mixedID($0) }
            for index in 0..<4 {
                let successor = index < 3 ? "'\(ids[index + 1])'" : "NULL"
                try connection.execute("""
                    INSERT INTO species_assertions
                        (id, tree_uuid, species_uuid, source, user_id, device_id,
                         superseded_by, created_at, updated_at)
                    VALUES ('\(ids[index])','\(treeText)',NULL,'community',NULL,'\(device)',
                            \(successor),'\(at(3 - index))','\(stamp)');
                    """)
            }
        }
        return store
    }

    /// Everything the five readers v20 moves answer, as comparable values.
    ///
    /// Ids and not whole models: a model's equality would drag in every column and turn a collation
    /// question into a decoding question. What has to be identical across the migration is *which
    /// rows come back, in what order*.
    private static func answers(
        trees: [UUID],
        assertionTree: UUID,
        store: CypressStore
    ) async throws -> (chain: [UUID], current: UUID?, one: UUID?, many: [UUID], exists: [Bool]) {
        try await store.queue.read { connection in
            let assertions = SpeciesAssertionStore()
            let community = CommunityTreeStore()
            return (
                chain: try assertions.chain(treeID: assertionTree, connection: connection).map(\.id),
                current: try assertions.current(treeID: assertionTree, connection: connection)?.id,
                one: try community.tree(id: trees[0], connection: connection)?.id,
                many: try community.trees(ids: trees, connection: connection)
                    .keys.sorted { $0.uuidString < $1.uuidString },
                exists: try trees.map { try community.exists(id: $0, connection: connection) }
            )
        }
    }

    /// **v20 runs, alone, on a database that already holds rows.**
    ///
    /// `applied == [20]` is the assertion and the whole of it: a v19 database must reach 20 by
    /// running exactly one step. A migration that had been mis-numbered, or a `currentVersion` that
    /// had drifted from the table, shows up here as a different list rather than as a silent extra
    /// pass over data.
    @Test("a v19 database with rows in it is carried to 20 by exactly one migration")
    func aV19DatabaseRunsOnlyV20() async throws {
        let trees = [UUID(), UUID(), UUID()]
        let store = try await Self.v19Database(trees: trees, assertionTree: UUID())

        let applied = try await store.queue.write { connection in
            try SchemaMigrator.migrate(AppSchema.migrations, on: connection)
        }
        #expect(
            applied == [Self.version],
            """
            a v19 database applied \(applied) rather than [\(Self.version)]. If this is a longer \
            list, another migration was added without this fixture being moved forward; if it is \
            empty, v20 is not in `AppSchema.migrations`
            """
        )

        let version = try await store.queue.read { try $0.userVersion }
        #expect(version == AppSchema.currentVersion, "user_version is \(version)")
        #expect(
            AppSchema.currentVersion == Self.version,
            """
            `AppSchema.currentVersion` is \(AppSchema.currentVersion) and this file is written about \
            \(Self.version). One of the two moved without the other — the fixture above still opens \
            at 19 and no longer proves what it says it proves
            """
        )
    }

    /// **The DDL landed as written: the recollated index is NOCASE and the new one exists.**
    ///
    /// Read out of `sqlite_master`, which holds the `CREATE INDEX` text SQLite actually stored.
    /// Asserting the *effect* — that a `COLLATE NOCASE` predicate now seeks — is
    /// `SpeciesAccessPlanTests`' job; this is the half that fails on a `DROP` that ran without its
    /// `CREATE`.
    @Test("every index v20 writes is stored with the collation it was written for")
    func theIndexesCarryTheirCollation() async throws {
        let store = try await CypressStore.inMemory()
        let expected = ["idx_species_assertions_tree", "idx_community_trees_id"]

        let stored = try await Self.storedIndexes(store)

        for name in expected {
            let sql = stored[name]
            #expect(
                sql != nil,
                "\(name) is not in the migrated schema — a DROP ran without its CREATE: \(stored.keys.sorted())"
            )
            #expect(
                sql?.uppercased().contains("COLLATE NOCASE") == true,
                """
                \(name) is stored without a NOCASE collation, so the readers that spell their \
                predicate `COLLATE NOCASE` still cannot seek it and v20 bought nothing — \
                \(sql ?? "<missing>")
                """
            )
        }
    }

    /// **The index v20 deliberately left alone still has the collation that makes it an invariant.**
    ///
    /// `idx_species_assertions_head` is `UNIQUE … WHERE superseded_by IS NULL` — one current claim
    /// per tree. Its collation decides *which pairs of rows conflict*, so recollating it is a change
    /// to the invariant and not to an access path, and it would make the migration able to fail on
    /// data already in the field. The measurement that made refusing it free is in `AppSchema.v20`:
    /// with `idx_species_assertions_tree` recollated, `current(treeID:)` seeks that index instead
    /// and never reads this one.
    ///
    /// This test is the trip-wire on "finish the job", and it is written as the presence of BINARY
    /// rather than the absence of NOCASE so it says what it means: the index must still be there,
    /// still UNIQUE, still partial.
    @Test("the head index is still the BINARY partial UNIQUE index v14 wrote")
    func theHeadIndexKeepsItsBinaryCollation() async throws {
        let store = try await CypressStore.inMemory()
        let stored = try await Self.storedIndexes(store)
        let sql = try #require(
            stored["idx_species_assertions_head"],
            "idx_species_assertions_head is gone: \(stored.keys.sorted())"
        )
        let upper = sql.uppercased()
        #expect(upper.contains("UNIQUE"), "the head index stopped being UNIQUE — \(sql)")
        #expect(
            upper.contains("WHERE") && upper.contains("SUPERSEDED_BY IS NULL"),
            "the head index stopped being partial on the head, so it no longer says one claim per tree — \(sql)"
        )
        #expect(
            !upper.contains("COLLATE NOCASE"),
            """
            idx_species_assertions_head has been recollated NOCASE. That changes which pairs of \
            rows the schema calls a conflict — two un-superseded assertions whose tree_uuid differs \
            only by case are legal today and would not be — which is a decision about v14's \
            invariant, not an access path, and it can make a migration fail on a database in the \
            field. `current(treeID:)` does not need it: since v20 it seeks \
            idx_species_assertions_tree. See `AppSchema.v20` — \(sql)
            """
        )
    }

    /// The `CREATE INDEX` text SQLite stored, by index name.
    private static func storedIndexes(_ store: CypressStore) async throws -> [String: String] {
        try await store.queue.read { connection -> [String: String] in
            let statement = try connection.prepare("""
                SELECT name, sql FROM main.sqlite_master WHERE type = 'index' AND name LIKE 'idx_%'
                """)
            defer { statement.finalize() }
            var found: [String: String] = [:]
            _ = try statement.fetchAll { row -> Void in
                found[try row.string("name")] = try row.stringIfPresent("sql") ?? ""
            }
            return found
        }
    }

    // MARK: - The change of access path, asked from both sides

    /// **Moving these reads onto an index changes no answer.**
    ///
    /// The five readers v20 moves are asked for their rows on a database at v19, then the migration
    /// is run against that same database, then they are asked again. Anything other than an
    /// identical answer means an index was carrying semantics rather than an access path — which is
    /// the risk a collation change runs, and the reason it is asked rather than argued.
    ///
    /// `current(treeID:)` is the one worth the fixture. Before v20 it was answered by
    /// `idx_species_assertions_head` and after it is answered by `idx_species_assertions_tree` —
    /// not a recollation of one index but a *different index*, reached through a different
    /// predicate, on a table whose rows are a chain. If any of that changed which assertion the app
    /// calls current, this is where it shows.
    ///
    /// The fixture spells every id in lower case and the readers bind the upper-case `uuidString`,
    /// so every one of these lookups is a genuine cross-case match. If a future change made both
    /// sides agree on case, this test would still pass and would be proving much less —
    /// `theFixtureIsGenuinelyMixedCase` is what keeps that visible.
    @Test("the readers v20 moves onto an index answer identically before and after")
    func recollationChangesNoAnswer() async throws {
        let trees = [UUID(), UUID(), UUID()]
        let assertionTree = UUID()
        let store = try await Self.v19Database(trees: trees, assertionTree: assertionTree)

        let before = try await Self.answers(trees: trees, assertionTree: assertionTree, store: store)
        try #require(
            before.chain.count > 1 && before.current != nil
                && before.one != nil && before.many.count > 1
                && before.exists.allSatisfy { $0 },
            """
            the readers answered too little for an ordering change to be detectable — chain \
            \(before.chain.count), current \(String(describing: before.current)), one \
            \(String(describing: before.one)), many \(before.many.count), exists \(before.exists). \
            Two empty answers compare equal, and so do two one-element ones however they are \
            ordered; this fixture writes a four-link chain and three community rows so that `==` \
            on an ordered array means something
            """
        )

        _ = try await store.queue.write { connection in
            try SchemaMigrator.migrate(AppSchema.migrations, on: connection)
        }
        let after = try await Self.answers(trees: trees, assertionTree: assertionTree, store: store)

        // Ordered comparisons, and the order is the reader's own. A recollation that changed which
        // index answers an ORDER BY would show up here and nowhere else in this file.
        #expect(
            before.chain == after.chain,
            """
            chain(treeID:) answers differently after v20: \(before.chain) became \(after.chain). \
            Same rows in a different order is a failure here too — the reader's `ORDER BY \
            created_at ASC, id ASC` is answered against `idx_species_assertions_tree`, which is the \
            index v20 recollates
            """
        )
        #expect(
            before.current == after.current,
            """
            current(treeID:) answers differently after v20 — \(String(describing: before.current)) \
            became \(String(describing: after.current)). This read changed index, not just \
            collation: it was answered by idx_species_assertions_head and is now answered by \
            idx_species_assertions_tree, so it is the one most likely to have changed answer
            """
        )
        #expect(before.one == after.one, "tree(id:) answers differently after v20")
        #expect(
            before.many == after.many,
            "trees(ids:) answers differently after v20: \(before.many) became \(after.many)"
        )
        #expect(before.exists == after.exists, "exists(id:) answers differently after v20")
    }

    /// **The fixture really does put the two spellings on opposite sides of the lookup.**
    ///
    /// Without this, a fixture whose stored uuids happened to match the bound ones byte for byte
    /// would make every assertion above true for a reason that has nothing to do with collation,
    /// and the file would go on passing while proving nothing. This project's dominant test defect
    /// is a guard that stays green because the case it guards stopped being present.
    @Test("the fixture stores its uuids in the case the readers do not bind")
    func theFixtureIsGenuinelyMixedCase() async throws {
        let trees = [UUID(), UUID(), UUID()]
        let assertionTree = UUID()
        let store = try await Self.v19Database(trees: trees, assertionTree: assertionTree)

        let stored = try await store.queue.read { connection -> [String] in
            let statement = try connection.prepare("""
                SELECT id AS spelling FROM community_trees
                 UNION ALL
                SELECT tree_uuid AS spelling FROM species_assertions
                """)
            defer { statement.finalize() }
            return try statement.fetchAll { try $0.string("spelling") }
        }
        let bound = Set((trees + [assertionTree]).map(\.uuidString))
        #expect(!stored.isEmpty, "the fixture wrote no row")
        for spelling in stored {
            #expect(
                !bound.contains(spelling),
                """
                the fixture stored \(spelling), which is byte-identical to what the readers bind. \
                Every lookup in this file is then a BINARY match and the NOCASE path — the thing \
                v20 changes — is never exercised
                """
            )
            #expect(
                bound.contains(where: { $0.caseInsensitiveCompare(spelling) == .orderedSame }),
                "the fixture stored \(spelling), which is not one of the bound uuids in any case"
            )
        }
    }
}
