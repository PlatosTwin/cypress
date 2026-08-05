import Foundation
import Testing
@testable import Cypress

/// **ERRATA E209/#233 — Shape A's one surviving member.** The share card (and nothing else, per
/// E209's own sweep) hardcoded `"San Francisco"` as the city half of its location line, true only
/// while the seed held one city; once San Jose shipped, every one of its 52,788 trees was
/// captioned with the wrong city on every share. `Tools/build_seed.py` now writes a hand-maintained
/// short civic name (`"San Francisco"`, `"San Jose"`) into `id_spaces.short_name`, and the read
/// layer reaches it through `SeedSchema.hasCivicShortNames` — introspected off the file, the same
/// shape as `hasSpeciesTrigrams` — rather than assuming any seed has it.
///
/// ── Why this suite builds its own fixtures rather than reading the shipped seed ──────────────────
/// Same reason as `SpeciesTrigramTests`: the canonical seed on every tree (`Tools/setup_worktree.sh`
/// copies it, CI fetches the same published artifact) is s14 and was published before this pass —
/// verified against the live manifest, both cities still `schema_version: 14` — so it carries no
/// `id_spaces.short_name` at all. The conditional tests below ask the real seed the question it can
/// answer today (nothing, honestly) and the unconditional ones prove the mechanism itself against
/// fixtures built with and without the column, which is the only way to prove both branches without
/// waiting on a seed rebuild.
@Suite("Civic short names (E209 Shape A / #233)")
struct CivicShortNameTests {

    // MARK: - Which of these the seed on this machine can answer

    /// Same instrument as `SpeciesTrigramTests.seedCarriesTrigrams`: the file is asked directly,
    /// with the same `SeedDatabase.attach` introspection the app itself uses.
    static var seedCarriesShortNames: Bool {
        guard let seedURL = SeedContractTests.seedURL,
              let connection = try? SQLiteConnection(path: ":memory:"),
              let schema = try? SeedDatabase.attach(seedURL, to: connection)
        else { return false }
        return schema.hasCivicShortNames
    }

    static let shortNameSeedRequired: Comment = """
        the seed on this tree is s14 and carries no id_spaces.short_name column. This activates on \
        its own once a seed built by this branch's Tools/build_seed.py is the canonical one — that \
        activation is the acceptance check that E209/#233's fix went live.
        """

    /// **What the real seed on this tree must answer today, honestly.** Not skipped: this is the
    /// fallback case itself, proved against the actual canonical file rather than a fixture, so the
    /// day the seed silently gains the column without `hasCivicShortNames` noticing would be caught
    /// here even though the four conditional tests above stay disabled.
    @Test("today's canonical seed has no short names, and the flag says so honestly")
    func theCanonicalSeedAnswersHonestly() async throws {
        let seedURL = try #require(SeedContractTests.seedURL, "no seed database; set CYPRESS_SEED_PATH")
        let store = try await CypressStore.inMemory(seedURL: seedURL)
        let schema = try #require(store.seed)
        // If this ever flips true, `seedCarriesShortNames` above flips with it and the four
        // conditional tests reactivate on their own — see their doc comments.
        #expect(
            schema.hasCivicShortNames == Self.seedCarriesShortNames,
            "the flag and the gate disagree about the same file"
        )
    }

    @Test(
        "a known id space's row carries its own short name on the real seed",
        .enabled(if: CivicShortNameTests.seedCarriesShortNames, CivicShortNameTests.shortNameSeedRequired)
    )
    func aKnownRowCarriesItsShortNameOnTheRealSeed() async throws {
        let seedURL = try #require(SeedContractTests.seedURL)
        let store = try await CypressStore.inMemory(seedURL: seedURL)
        let schema = try #require(store.seed)
        let queries = TreeQueries(schema: schema, seedHasSoftDeletedTrees: store.seedHasSoftDeletedTrees)

        let uuid = try await store.queue.read { connection -> UUID in
            let statement = try connection.cachedStatement("""
                SELECT \(schema.treeIdentityColumn) AS tree_uuid
                  FROM \(SeedDatabase.schemaName).trees WHERE id_space = 'us-ca-sj' LIMIT 1
                """)
            return try #require(try statement.fetchOne { try $0.uuid("tree_uuid") })
        }
        let record = try await store.queue.read { connection in
            try queries.tree(id: uuid, connection: connection)
        }
        #expect(record?.cityShortName == "San Jose")
    }

    // MARK: - The mechanism, proved against built fixtures

    /// **The fixture with the column present**, proving the introspection-gated path end to end:
    /// the flag reads true, the join fires, and the row's own id space names the row.
    @Test("a fixture built with id_spaces.short_name resolves the row's own city")
    func aFixtureWithShortNamesResolvesTheCity() async throws {
        let url = try Self.miniSeed(idSpacesShape: .withShortNames)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = try await CypressStore.inMemory(seedURL: url)
        let schema = try #require(store.seed)
        #expect(schema.hasCivicShortNames, "the fixture was built without the column after all")
        #expect(schema.hasIdSpace, "the fixture must also carry id_space for the join to mean anything")

        let queries = TreeQueries(schema: schema, seedHasSoftDeletedTrees: store.seedHasSoftDeletedTrees)
        let (sf, sj) = try await store.queue.read { connection in
            (
                try queries.tree(id: Self.sfTreeID, connection: connection),
                try queries.tree(id: Self.sjTreeID, connection: connection)
            )
        }
        #expect(sf?.cityShortName == "San Francisco")
        #expect(sj?.cityShortName == "San Jose")
        // Two different rows, two different id spaces, two different answers — the control that
        // proves this is a per-row join and not a seed-wide constant, which is the exact shape of
        // defect E209 recorded.
        #expect(sf?.cityShortName != sj?.cityShortName)
    }

    /// **The fixture with `id_spaces` but no `short_name` column** — an s14-shaped file, `id_space`
    /// and all, built before this pass. The join partner exists; the column on it does not.
    /// `hasCivicShortNames` must read false and the row must resolve to nil, never to a guess.
    @Test("a fixture with id_space but no short_name column degrades to nil, not a guess")
    func aFixtureWithIdSpaceButNoShortNameDegradesToNil() async throws {
        let url = try Self.miniSeed(idSpacesShape: .withoutShortNames)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = try await CypressStore.inMemory(seedURL: url)
        let schema = try #require(store.seed)
        #expect(!schema.hasCivicShortNames, "the fixture carries short_name after all")
        #expect(schema.hasIdSpace, "this fixture is meant to have id_space without short_name")

        let queries = TreeQueries(schema: schema, seedHasSoftDeletedTrees: store.seedHasSoftDeletedTrees)
        let sf = try await store.queue.read { connection in
            try queries.tree(id: Self.sfTreeID, connection: connection)
        }
        #expect(sf?.cityShortName == nil)
    }

    /// **The fixture with no `id_spaces`/`inventories` at all** — a pre-v14 file, before `id_space`
    /// existed on `trees`. The dangerous version of this bug is a `LEFT JOIN` against a table that
    /// is not there, which is a SQL error and not a null result; this proves the join itself is
    /// omitted rather than merely its column, and that the query still runs.
    @Test("a fixture with no id_spaces table at all still runs, and resolves to nil")
    func aFixtureWithNoIdSpacesTableStillRuns() async throws {
        let url = try Self.miniSeed(idSpacesShape: .absent)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = try await CypressStore.inMemory(seedURL: url)
        let schema = try #require(store.seed)
        #expect(!schema.hasIdSpace)
        #expect(!schema.hasCivicShortNames)

        let queries = TreeQueries(schema: schema, seedHasSoftDeletedTrees: store.seedHasSoftDeletedTrees)
        // The only row this shape's fixture carries — see `miniSeed` — has no id space column at
        // all, so it is looked up by its uuid alone.
        let record = try await store.queue.read { connection in
            try queries.tree(id: Self.sfTreeID, connection: connection)
        }
        #expect(record != nil, "the query itself failed rather than merely losing the city name")
        #expect(record?.cityShortName == nil)
        #expect(record?.tree.idSpace == nil)
    }

    // MARK: - Fixture

    private static let sfTreeID = UUID(uuidString: "00000000-0000-4000-8000-00000000CAFE")!
    private static let sjTreeID = UUID(uuidString: "00000000-0000-4000-8000-0000000005A1")!

    private enum IDSpacesShape: Equatable {
        /// `id_spaces` and `inventories` present, `id_spaces.short_name` populated — the shape this
        /// ticket adds.
        case withShortNames
        /// `id_spaces` and `inventories` present, no `short_name` column — the v14 shape E209 found
        /// with nothing to answer it.
        case withoutShortNames
        /// Neither table exists, and `trees` has no `id_space` column — pre-v14.
        case absent
    }

    /// A minimal but complete `TreeQueries.tree(id:)` fixture: every column `treeColumns` and the
    /// species/neighborhood/site-lineage joins read, so the query under test runs exactly the SQL
    /// production does rather than a simplified stand-in.
    private static func miniSeed(idSpacesShape: IDSpacesShape) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("e233-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("cypress-seed.sqlite")

        let connection = try SQLiteConnection(path: url.path)
        try connection.execute("""
            CREATE TABLE species (
                id INTEGER PRIMARY KEY, uuid TEXT NOT NULL UNIQUE,
                scientific_name TEXT NOT NULL, common_name TEXT, family TEXT,
                leaf_retention TEXT, id_tips TEXT NOT NULL DEFAULT '[]',
                seasonal TEXT NOT NULL DEFAULT '{}', care_notes TEXT NOT NULL DEFAULT '[]',
                curated INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT
            );
            CREATE TABLE neighborhoods (id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE);
            CREATE TABLE trees_rtree (id INTEGER PRIMARY KEY);
            """)

        let idSpaceColumn: String
        switch idSpacesShape {
        case .withShortNames, .withoutShortNames:
            idSpaceColumn = "id_space TEXT REFERENCES id_spaces(id),"
        case .absent:
            idSpaceColumn = ""
        }

        switch idSpacesShape {
        case .withShortNames:
            try connection.execute("""
                CREATE TABLE id_spaces (
                    id TEXT PRIMARY KEY, identity_prefix TEXT NOT NULL, note TEXT NOT NULL,
                    short_name TEXT NOT NULL
                );
                CREATE TABLE inventories (
                    id TEXT PRIMARY KEY, id_space TEXT NOT NULL REFERENCES id_spaces(id),
                    name TEXT NOT NULL, url TEXT NOT NULL
                );
                INSERT INTO id_spaces VALUES
                    ('sf', '', 'test fixture', 'San Francisco'),
                    ('us-ca-sj', 'us-ca-sj:', 'test fixture', 'San Jose');
                INSERT INTO inventories VALUES
                    ('sf_city', 'sf', 'test SF inventory', 'https://example.invalid/sf'),
                    ('sj_street_tree', 'us-ca-sj', 'test SJ inventory', 'https://example.invalid/sj');
                """)
        case .withoutShortNames:
            try connection.execute("""
                CREATE TABLE id_spaces (
                    id TEXT PRIMARY KEY, identity_prefix TEXT NOT NULL, note TEXT NOT NULL
                );
                CREATE TABLE inventories (
                    id TEXT PRIMARY KEY, id_space TEXT NOT NULL REFERENCES id_spaces(id),
                    name TEXT NOT NULL, url TEXT NOT NULL
                );
                INSERT INTO id_spaces VALUES ('sf', '', 'test fixture');
                INSERT INTO inventories VALUES
                    ('sf_city', 'sf', 'test SF inventory', 'https://example.invalid/sf');
                """)
        case .absent:
            break
        }

        try connection.execute("""
            CREATE TABLE trees (
                id INTEGER PRIMARY KEY, uuid TEXT NOT NULL UNIQUE,
                external_ref TEXT, \(idSpaceColumn)
                source TEXT NOT NULL, lat REAL NOT NULL, lon REAL NOT NULL,
                address TEXT, site_type TEXT, status TEXT NOT NULL,
                species_current INTEGER, planted_year INTEGER,
                dbh_city_cm_min INTEGER, dbh_city_cm_max INTEGER,
                site_lineage INTEGER, verification_state TEXT NOT NULL,
                legal_status TEXT, caretaker TEXT, care_assistant TEXT,
                plant_type TEXT, plot_size TEXT, permit_notes TEXT,
                created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT
            );
            """)

        let now = "2026-01-01T00:00:00+00:00"
        func insertTree(uuid: UUID, idSpace: String?) throws {
            let idSpaceValue = idSpace.map { "'\($0)'" } ?? "NULL"
            let idSpaceInsert = idSpacesShape == .absent ? "" : "\(idSpaceValue),"
            try connection.execute("""
                INSERT INTO trees (
                    uuid, external_ref, \(idSpacesShape == .absent ? "" : "id_space,")
                    source, lat, lon, address, site_type, status,
                    verification_state, created_at, updated_at
                ) VALUES (
                    '\(uuid.uuidString)', '1', \(idSpaceInsert)
                    'city_import', 37.7, -122.4, 'Test Address', NULL, 'alive',
                    'city_record', '\(now)', '\(now)'
                );
                """)
        }
        try insertTree(uuid: Self.sfTreeID, idSpace: idSpacesShape == .absent ? nil : "sf")
        if idSpacesShape == .withShortNames {
            // Only this shape registers `us-ca-sj` in `id_spaces` at all — `.withoutShortNames`
            // deliberately carries only `sf`, so a second row here would reference an id space
            // the fixture never declared.
            try insertTree(uuid: Self.sjTreeID, idSpace: "us-ca-sj")
        }

        return url
    }
}
