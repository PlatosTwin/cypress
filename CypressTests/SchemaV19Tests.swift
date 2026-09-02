import Foundation
import Testing
@testable import Cypress

/// **What migration v19 does to a database that already has rows in it.**
///
/// v19 is DDL only and touches no data, which is exactly the shape that gets shipped without a
/// fixture: `DataGates.sqliteStore` already runs the whole ladder on an empty in-memory database
/// and picks up any new version for free, and it would have passed on this one the day it was
/// written. What it cannot see is the only interesting question here — **five of the six statements
/// replace an index that already exists, and the replacement changes its collation.** A recollated
/// index is a different index; a reader whose answers depend on collation would answer differently
/// afterwards, silently, on a database that has already been migrated and cannot be un-migrated.
///
/// So this file does two things `DataGates` cannot:
///
/// 1. runs the migration against a **v18 database with rows already in it**, written as rows rather
///    than through the shipping API, and asserts that v19 and only v19 is what runs;
/// 2. asks the four readers whose indexes were recollated for their answers **before and after**,
///    on rows deliberately spelled in mixed case, and requires the two to be identical.
///
/// The second is the one worth the file. `tree_uuid` reaches these tables in two spellings — the
/// upper-case `uuidString` a stored row carries and whatever a decoded payload holds — which is the
/// whole reason the readers say `COLLATE NOCASE` and the whole reason v19 recollates the indexes to
/// match. That makes case the axis the migration moves along, so it is the axis the fixture is
/// built on.
///
/// ── Calibration ─────────────────────────────────────────────────────────────────────────────
/// With v19's statement body replaced by `SELECT 1` — the migration still present, still applied,
/// doing nothing — `theIndexesCarryTheirCollation` fails with **7 issues**: five of the six index
/// names are stored without `COLLATE NOCASE`, and `idx_photo_votes_photo` is absent altogether,
/// which is two issues on its own (missing, and therefore no collation to check).
///
/// The other three tests here stay **green** under that revert, and that is correct rather than a
/// gap: `aV18DatabaseRunsOnlyV19` is about the version ladder and not about what the step does;
/// `recollationChangesNoAnswer` is a *no-change* assertion, so a migration that changes nothing
/// trivially satisfies it — it exists to catch a recollation that changes an answer, not one that
/// is missing. `theIndexesCarryTheirCollation` is the one that says the DDL landed, and it is the
/// one that goes red. The full distribution of both v19 reverts is in `JournalQueryPlanTests`.
@Suite("AppSchema · v19")
struct SchemaV19Tests {

    private static let moment = Date(timeIntervalSince1970: 1_780_000_000)
    private static let deviceID = UUID(uuidString: "9E00B47C-0000-4000-8000-000000000619")!

    /// The version this file is about, read from the code rather than written down twice.
    private static var version: Int32 { 19 }

    // MARK: - The upgrade

    /// A v18 database carrying a row in each table v19 touches, spelled in **lower case** —
    /// which is not how this app writes a uuid, and is the point.
    ///
    /// Written with `execute` rather than through `ContributionStore.insert` for
    /// `PhotoProvenanceTests.upgradedFromV15`'s reason: the shipping write path is not what an
    /// already-installed database was filled by, and handing the migration rows in the exact shape
    /// the current code produces tests the migration against its own author's assumptions.
    private static func v18Database(
        tree: UUID,
        photo: UUID
    ) async throws -> CypressStore {
        let store = try await CypressStore.inMemory(
            migrations: AppSchema.migrations.filter { $0.version <= 18 }
        )
        let stamp = SQLiteTimestamp.string(from: moment)
        // Lower-cased on purpose: the stored spelling and the spelling the readers bind differ by
        // case, which is the state `COLLATE NOCASE` exists for and the state a recollation moves.
        let treeText = tree.uuidString.lowercased()
        let device = deviceID.uuidString.lowercased()

        try await store.queue.write { connection in
            let opened = try connection.userVersion
            #expect(opened == 18, "the fixture opened at user_version \(opened), not 18")
            try connection.execute("""
                INSERT INTO app_state (key, value) VALUES ('device_uuid','\(deviceID.uuidString)');

                INSERT INTO visits (id, tree_uuid, device_id, client_uuid, note,
                                    captured_at, created_at, updated_at)
                VALUES ('\(UUID().uuidString.lowercased())','\(treeText)','\(device)',
                        '\(UUID().uuidString.lowercased())','a walk','\(stamp)','\(stamp)','\(stamp)');

                INSERT INTO observations (id, tree_uuid, device_id, client_uuid, captured_at,
                                          status, created_at, updated_at)
                VALUES ('\(UUID().uuidString.lowercased())','\(treeText)','\(device)',
                        '\(UUID().uuidString.lowercased())','\(stamp)','alive','\(stamp)','\(stamp)');

                INSERT INTO measurements (id, tree_uuid, device_id, client_uuid, captured_at, kind,
                                          value, unit_entered, si_value, method,
                                          created_at, updated_at)
                VALUES ('\(UUID().uuidString.lowercased())','\(treeText)','\(device)',
                        '\(UUID().uuidString.lowercased())','\(stamp)','height',12.0,'m',12.0,
                        'tape','\(stamp)','\(stamp)');

                INSERT INTO care_events (id, tree_uuid, device_id, client_uuid, captured_at,
                                         actions, created_at, updated_at)
                VALUES ('\(UUID().uuidString.lowercased())','\(treeText)','\(device)',
                        '\(UUID().uuidString.lowercased())','\(stamp)','["watering"]',
                        '\(stamp)','\(stamp)');

                INSERT INTO tree_names (id, tree_uuid, name, created_at, updated_at)
                VALUES ('\(UUID().uuidString.lowercased())','\(treeText)','Old Friend',
                        '\(stamp)','\(stamp)');

                INSERT INTO photos (id, tree_uuid, shot_type, moderation_state, device_id,
                                    taken_on_device, captured_at, created_at, updated_at)
                VALUES ('\(photo.uuidString.lowercased())','\(treeText)','full_tree','approved',
                        '\(device)','\(device)','\(stamp)','\(stamp)','\(stamp)');

                INSERT INTO photo_votes (id, photo_id, tree_uuid, device_id, vote,
                                         created_at, updated_at)
                VALUES ('\(UUID().uuidString.lowercased())','\(photo.uuidString.lowercased())',
                        '\(treeText)','\(device)',1,'\(stamp)','\(stamp)');
                """)
        }
        return store
    }

    /// Everything the four recollated readers answer for one tree, as comparable values.
    ///
    /// Ids and not whole models: a model's equality would drag in every column and turn a
    /// collation question into a decoding question. What has to be identical across the migration
    /// is *which rows come back*.
    private static func answers(
        tree: UUID,
        attribution: Attribution,
        store: CypressStore
    ) async throws -> (visits: [UUID], photos: [UUID], names: [UUID: UUID], heroes: [UUID: UUID]) {
        try await store.queue.read { connection in
            let contributions = ContributionStore()
            return (
                visits: try contributions.visits(treeID: tree, connection: connection).items.map(\.id),
                photos: try contributions.photos(treeID: tree, connection: connection).items.map(\.id),
                names: try contributions.activeNames(treeIDs: [tree], connection: connection)
                    .mapValues(\.id),
                heroes: try contributions.heroPhotoIDs(
                    treeIDs: [tree], attribution: attribution, connection: connection
                )
            )
        }
    }

    /// **v19 runs, alone, on a database that already holds rows.**
    ///
    /// `applied == [19]` is the assertion and the whole of it: a v18 database must reach 19 by
    /// running exactly one step. A migration that had been mis-numbered, or a `currentVersion` that
    /// had drifted from the table, shows up here as a different list rather than as a silent extra
    /// pass over data.
    @Test("a v18 database with rows in it is carried to 19 by exactly one migration")
    func aV18DatabaseRunsOnlyV19() async throws {
        let tree = UUID(), photo = UUID()
        let store = try await Self.v18Database(tree: tree, photo: photo)

        let applied = try await store.queue.write { connection in
            try SchemaMigrator.migrate(AppSchema.migrations, on: connection)
        }
        #expect(
            applied == [Self.version],
            """
            a v18 database applied \(applied) rather than [\(Self.version)]. If this is a longer \
            list, another migration was added without this fixture being moved forward; if it is \
            empty, v19 is not in `AppSchema.migrations`
            """
        )

        let version = try await store.queue.read { try $0.userVersion }
        #expect(version == AppSchema.currentVersion, "user_version is \(version)")
        #expect(
            AppSchema.currentVersion == Self.version,
            """
            `AppSchema.currentVersion` is \(AppSchema.currentVersion) and this file is written about \
            \(Self.version). One of the two moved without the other — the fixture above still opens \
            at 18 and no longer proves what it says it proves
            """
        )
    }

    /// **The DDL landed as written: the five recollated indexes are NOCASE, and the new one exists.**
    ///
    /// Read out of `sqlite_master`, which holds the `CREATE INDEX` text SQLite actually stored.
    /// Asserting the *effect* — that a `COLLATE NOCASE` predicate now seeks — is
    /// `JournalQueryPlanTests`' job for the two statements it gates; this is the half that covers
    /// the three no plan gate reads, and it fails on a `DROP` that ran without its `CREATE`.
    @Test("every index v19 rewrites is stored with the collation it was rewritten for")
    func theIndexesCarryTheirCollation() async throws {
        let store = try await CypressStore.inMemory()
        let expected = [
            "idx_visits_tree", "idx_observations_tree", "idx_measurements_tree",
            "idx_care_events_tree", "idx_photos_tree", "idx_photo_votes_photo"
        ]

        let stored = try await store.queue.read { connection -> [String: String] in
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
                predicate `COLLATE NOCASE` still cannot seek it and v19 bought nothing — \
                \(sql ?? "<missing>")
                """
            )
        }
    }

    // MARK: - The recollation, asked from both sides

    /// **Recollating an index changes no answer.**
    ///
    /// The four readers whose indexes v19 rewrites are asked for their rows on a database at v18,
    /// then the migration is run against that same database, then they are asked again. Anything
    /// other than an identical answer means the index was carrying semantics rather than an access
    /// path — which is the risk a collation change runs, and the reason it is asked rather than
    /// argued.
    ///
    /// The fixture spells `tree_uuid` in lower case and the readers bind the upper-case
    /// `uuidString`, so every one of these lookups is a genuine cross-case match. If a future
    /// change made both sides agree on case, this test would still pass and would be proving much
    /// less — `theFixtureIsGenuinelyMixedCase` is what keeps that visible.
    @Test("the readers whose indexes v19 recollates answer identically before and after")
    func recollationChangesNoAnswer() async throws {
        let tree = UUID(), photo = UUID()
        let store = try await Self.v18Database(tree: tree, photo: photo)
        let attribution = Attribution(userID: nil, deviceID: Self.deviceID)

        let before = try await Self.answers(tree: tree, attribution: attribution, store: store)
        try #require(
            !before.visits.isEmpty && !before.photos.isEmpty
                && !before.names.isEmpty && !before.heroes.isEmpty,
            """
            the v18 readers already answered nothing for this tree, so "identical afterwards" \
            would be satisfied by two empty answers — visits \(before.visits.count), photos \
            \(before.photos.count), names \(before.names.count), heroes \(before.heroes.count)
            """
        )

        _ = try await store.queue.write { connection in
            try SchemaMigrator.migrate(AppSchema.migrations, on: connection)
        }
        let after = try await Self.answers(tree: tree, attribution: attribution, store: store)

        #expect(before.visits == after.visits, "visits(treeID:) answers differently after v19")
        #expect(before.photos == after.photos, "photos(treeID:) answers differently after v19")
        #expect(before.names == after.names, "activeNames(treeIDs:) answers differently after v19")
        #expect(
            before.heroes == after.heroes,
            """
            heroPhotoIDs(treeIDs:attribution:) answers differently after v19 — \(before.heroes) \
            became \(after.heroes). That read is the one whose two statements both changed plan, \
            so it is the one most likely to have changed answer with them
            """
        )
    }

    /// **The fixture really does put the two spellings on opposite sides of the lookup.**
    ///
    /// Without this, a fixture whose stored uuids happened to match the bound ones byte for byte
    /// would make every assertion above true for a reason that has nothing to do with collation,
    /// and the file would go on passing while proving nothing. This project's dominant test defect
    /// is a guard that stays green because the case it guards stopped being present.
    @Test("the fixture stores its uuids in the case the readers do not bind")
    func theFixtureIsGenuinelyMixedCase() async throws {
        let tree = UUID(), photo = UUID()
        let store = try await Self.v18Database(tree: tree, photo: photo)

        let stored = try await store.queue.read { connection -> [String] in
            let statement = try connection.prepare("SELECT tree_uuid FROM visits")
            defer { statement.finalize() }
            return try statement.fetchAll { try $0.string("tree_uuid") }
        }
        let bound = tree.uuidString
        #expect(!stored.isEmpty, "the fixture wrote no visit")
        for spelling in stored {
            #expect(
                spelling != bound,
                """
                the fixture stored \(spelling), which is byte-identical to what the reader binds. \
                Every lookup in this file is then a BINARY match and the NOCASE path — the thing \
                v19 changes — is never exercised
                """
            )
            #expect(
                spelling.caseInsensitiveCompare(bound) == .orderedSame,
                "the fixture stored \(spelling), which is not the same uuid as \(bound) in any case"
            )
        }
    }
}
