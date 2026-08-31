import Foundation
import Testing
@testable import Cypress

/// **Task #237 — `dim_city`, the city dimension table.** `id_spaces.short_name` (ERRATA
/// E209/#233) put one civic string beside an id space; this pass replaces it with a real table —
/// slug (the "us-ca-sf" convention), display name, state, county, the city's own official
/// street-tree/urban-forestry page — joined through the new `id_spaces.city_id`, and *drops*
/// `short_name` from `id_spaces` so the display name has one source of truth instead of two.
///
/// `id_spaces.id` itself is untouched and stays FROZEN — it is `trees.id_space`'s foreign key and
/// `Tools/inventory_contract.py`'s `IdSpace.identity_prefix` is frozen per space (`sf`'s is the
/// empty string, and every shipped uuid is derived from it, DECISIONS 13). The "us-ca-sf"
/// convention lives only on `dim_city.slug`; this suite never asserts a slug equal to an
/// `id_spaces.id` value, on purpose — the two are deliberately not the same string for `sf`
/// (`"sf"` vs `"us-ca-sf"`), which is the whole point of the table existing.
///
/// ── Why this suite builds its own fixtures rather than reading the shipped seed ──────────────────
/// Same reason as `CivicShortNameTests` and `SpeciesTrigramTests`: the canonical seed every tree
/// gets (`Tools/setup_worktree.sh` copies it, CI fetches the same published artifact via
/// `Tools/fetch_seed.sh`) is s15 as of this writing and carries `id_spaces.short_name`, not
/// `dim_city` — this branch's own worktree rebuild is the first file that does. The conditional
/// tests below ask the real seed the question it can answer today, and the unconditional ones
/// prove the mechanism itself against built fixtures covering s14 (no `id_spaces` at all), s15
/// (`short_name`, no `dim_city`) and s16 (`dim_city`) shapes.
@Suite("dim_city — the city dimension table (task #237)")
struct DimCityTests {

    // MARK: - Which of these the seed on this machine can answer

    /// Same instrument as `CivicShortNameTests.seedCarriesShortNames`: the file is asked directly,
    /// with the same `SeedDatabase.attach` introspection the app itself uses.
    static var seedCarriesDimCity: Bool {
        guard let seedURL = SeedContractTests.seedURL,
              let connection = try? SQLiteConnection(path: ":memory:"),
              let schema = try? SeedDatabase.attach(seedURL, to: connection)
        else { return false }
        return schema.hasDimCity
    }

    static let dimCitySeedRequired: Comment = """
        the seed on this tree does not yet carry dim_city (a pre-s16 build). This activates on \
        its own once a seed built by this branch's Tools/build_seed.py is the canonical one — \
        that activation is the acceptance check that task #237's addition went live.
        """

    /// **What the real seed on this tree must answer today, honestly.** Not skipped: this is the
    /// fallback case itself, proved against the actual canonical file rather than a fixture, so the
    /// day the seed silently gains `dim_city` without `hasDimCity` noticing would be caught here
    /// even though the conditional test below stays disabled until then.
    @Test("today's canonical seed answers hasDimCity honestly")
    func theCanonicalSeedAnswersHonestly() async throws {
        let seedURL = try #require(SeedContractTests.seedURL, "no seed database; set CYPRESS_SEED_PATH")
        let store = try await CypressStore.inMemory(seedURL: seedURL)
        let schema = try #require(store.seed)
        // If this ever flips true, `seedCarriesDimCity` above flips with it and the conditional
        // test below reactivates on its own — see its doc comment.
        #expect(
            schema.hasDimCity == Self.seedCarriesDimCity,
            "the flag and the gate disagree about the same file"
        )
    }

    @Test(
        "a known id space's row resolves its city through dim_city on the real seed",
        .enabled(if: DimCityTests.seedCarriesDimCity, DimCityTests.dimCitySeedRequired)
    )
    func aKnownRowResolvesThroughDimCityOnTheRealSeed() async throws {
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

        // The slug is the "us-ca-sf" convention and is never `id_spaces.id` — assert the dim_city
        // row directly, the control that proves this suite is reading the new table and not the
        // dropped `short_name` column reappearing by coincidence.
        let slug = try await store.queue.read { connection -> String in
            let statement = try connection.cachedStatement("""
                SELECT dc.slug AS slug FROM \(SeedDatabase.schemaName).id_spaces isp
                  JOIN \(SeedDatabase.schemaName).dim_city dc ON dc.id = isp.city_id
                 WHERE isp.id = 'us-ca-sj'
                """)
            return try #require(try statement.fetchOne { try $0.string("slug") })
        }
        #expect(slug == "us-ca-sj")
    }

    // MARK: - The mechanism, proved against built fixtures

    /// **The fixture with `dim_city` present** (s16), proving the introspection-gated path end to
    /// end: `hasDimCity` reads true, the join fires through `id_spaces.city_id`, and the row's own
    /// id space resolves to its own city — never a seed-wide constant, the exact defect ERRATA
    /// E209 recorded for the mechanism this table now carries.
    @Test("a fixture built with dim_city resolves the row's own city through it")
    func aFixtureWithDimCityResolvesTheCity() async throws {
        let url = try Self.miniSeed(shape: .dimCity)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = try await CypressStore.inMemory(seedURL: url)
        let schema = try #require(store.seed)
        #expect(schema.hasDimCity, "the fixture was built without dim_city after all")
        #expect(!schema.hasCivicShortNames, "the s16 fixture must not also carry short_name")
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
        // Two different rows, two different id spaces, two different answers — the per-row-join
        // control, same shape as `CivicShortNameTests.aFixtureWithShortNamesResolvesTheCity`.
        #expect(sf?.cityShortName != sj?.cityShortName)
    }

    /// **The fixture with `id_spaces.short_name` but no `dim_city`** — the s15 shape this pass
    /// leaves behind for a file it does not touch. `hasDimCity` must read false and the row must
    /// still resolve through the s15 fallback, proving the new code did not regress the old path.
    @Test("a fixture with short_name but no dim_city still resolves through the s15 fallback")
    func aFixtureWithShortNameButNoDimCityFallsBack() async throws {
        let url = try Self.miniSeed(shape: .shortNameOnly)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = try await CypressStore.inMemory(seedURL: url)
        let schema = try #require(store.seed)
        #expect(!schema.hasDimCity, "this fixture is meant to have no dim_city")
        #expect(schema.hasCivicShortNames, "this fixture is meant to carry short_name")

        let queries = TreeQueries(schema: schema, seedHasSoftDeletedTrees: store.seedHasSoftDeletedTrees)
        let sf = try await store.queue.read { connection in
            try queries.tree(id: Self.sfTreeID, connection: connection)
        }
        #expect(sf?.cityShortName == "San Francisco")
    }

    /// **The fixture with neither `id_spaces` nor `dim_city` at all** — pre-v14, before `id_space`
    /// existed on `trees`. The dangerous version of this bug is a `LEFT JOIN` against a table that
    /// is not there, which is a SQL error and not a null result; this proves both joins are omitted
    /// rather than merely their columns, and that the query still runs.
    @Test("a fixture with neither id_spaces nor dim_city still runs, and resolves to nil")
    func aFixtureWithNeitherTableStillRuns() async throws {
        let url = try Self.miniSeed(shape: .preIdSpace)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = try await CypressStore.inMemory(seedURL: url)
        let schema = try #require(store.seed)
        #expect(!schema.hasIdSpace)
        #expect(!schema.hasCivicShortNames)
        #expect(!schema.hasDimCity)

        let queries = TreeQueries(schema: schema, seedHasSoftDeletedTrees: store.seedHasSoftDeletedTrees)
        let record = try await store.queue.read { connection in
            try queries.tree(id: Self.sfTreeID, connection: connection)
        }
        #expect(record != nil, "the query itself failed rather than merely losing the city name")
        #expect(record?.cityShortName == nil)
    }

    /// **The adversarial shape, mirrored from PR #29's finding against `short_name`.** `dim_city`
    /// exists and `id_spaces.city_id` is populated — so `hasDimCity` reads true — but `trees` has
    /// no `id_space` column at all, so `hasIdSpace` reads false and the `LEFT JOIN` that would
    /// provide the `isp` alias (and therefore `dc`, which is joined *through* `isp.city_id`) is
    /// never emitted. Before a fix shaped like this one, projecting `dc.display_name` gated on
    /// `hasDimCity` alone would throw `no such column: isp.city_id` (or `dc` itself unresolved) at
    /// prepare, not return a null result — this proves the query still prepares and still runs.
    @Test("a fixture with dim_city but no trees.id_space column still prepares, and resolves to nil")
    func aFixtureWithDimCityButNoTreeIDSpaceStillPrepares() async throws {
        let url = try Self.miniSeed(shape: .dimCityButNoTreeIDSpace)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = try await CypressStore.inMemory(seedURL: url)
        let schema = try #require(store.seed)
        #expect(schema.hasDimCity, "the fixture is meant to carry dim_city")
        #expect(!schema.hasIdSpace, "the fixture is meant to have no trees.id_space column")

        let queries = TreeQueries(schema: schema, seedHasSoftDeletedTrees: store.seedHasSoftDeletedTrees)
        // The assertion is that this does not throw. Pre-fix (gating the projection on
        // `hasDimCity` alone), this threw at prepare against the alias the join never emitted.
        let record = try await store.queue.read { connection in
            try queries.tree(id: Self.sfTreeID, connection: connection)
        }
        #expect(record != nil, "the query itself failed rather than merely losing the city name")
        #expect(record?.cityShortName == nil, "there is no isp/dc row joined in to have named one")
    }

    /// Pins the plan's `dc` step against `treeSQL()` itself, the same discipline
    /// `CivicShortNameTests.queryPlanMatchesTheProfileQuery` uses for `isp`. `dim_city.id` is an
    /// `INTEGER PRIMARY KEY` — a rowid alias, unlike `id_spaces.id` (`TEXT PRIMARY KEY`) — so the
    /// plan for `dc` must read as a rowid lookup, not an index search.
    @Test("the profile query's dim_city join resolves by rowid, not an index search")
    func queryPlanJoinsDimCityByRowid() async throws {
        let url = try Self.miniSeed(shape: .dimCity)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = try await CypressStore.inMemory(seedURL: url)
        let schema = try #require(store.seed)
        let queries = TreeQueries(schema: schema, seedHasSoftDeletedTrees: store.seedHasSoftDeletedTrees)

        let plan = try await store.queue.read { connection in
            try connection.queryPlan(for: queries.treeSQL())
        }
        let joined = plan.joined(separator: " | ")
        #expect(
            joined.contains("SEARCH dc USING INTEGER PRIMARY KEY (rowid=?)"),
            "the dim_city join no longer matches the pinned plan: \(joined)"
        )
    }

    // MARK: - Fixture

    private static let sfTreeID = UUID(uuidString: "00000000-0000-4000-8000-0000000BEEF1")!
    private static let sjTreeID = UUID(uuidString: "00000000-0000-4000-8000-0000000BEEF2")!

    private enum Shape: Equatable {
        /// `id_spaces`/`inventories` present, `dim_city` present, `id_spaces.city_id` populated,
        /// `trees.id_space` present — the shape this ticket adds (s16).
        case dimCity
        /// `id_spaces`/`inventories` present with `short_name`, no `dim_city` — the s15 shape this
        /// pass leaves working for a file it does not touch.
        case shortNameOnly
        /// None of `id_spaces`/`inventories`/`dim_city` exist, and `trees` has no `id_space`
        /// column — pre-v14.
        case preIdSpace
        /// **The adversarial shape.** `dim_city` and `id_spaces.city_id` both exist — so
        /// `hasDimCity` reads true — but `trees` has no `id_space` column at all, so `hasIdSpace`
        /// reads false and the join that would provide `isp` (and, through it, `dc`) is never
        /// emitted. Proves the two flags can disagree and that the query still prepares anyway.
        case dimCityButNoTreeIDSpace
    }

    /// A minimal but complete `TreeQueries.tree(id:)` fixture: every column `treeColumns` and the
    /// species/neighborhood/site-lineage joins read, so the query under test runs exactly the SQL
    /// production does rather than a simplified stand-in. Structurally the same builder as
    /// `CivicShortNameTests.miniSeed`, extended with `dim_city`.
    private static func miniSeed(shape: Shape) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("t237-\(UUID().uuidString)")
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

        let treesHaveIDSpaceColumn = shape != .preIdSpace && shape != .dimCityButNoTreeIDSpace
        let idSpaceColumn = treesHaveIDSpaceColumn ? "id_space TEXT REFERENCES id_spaces(id)," : ""

        switch shape {
        case .dimCity, .dimCityButNoTreeIDSpace:
            try connection.execute("""
                CREATE TABLE dim_city (
                    id INTEGER PRIMARY KEY, slug TEXT NOT NULL UNIQUE, display_name TEXT NOT NULL,
                    state TEXT NOT NULL, county TEXT NOT NULL, urban_forestry_url TEXT NOT NULL
                );
                CREATE TABLE id_spaces (
                    id TEXT PRIMARY KEY, identity_prefix TEXT NOT NULL, note TEXT NOT NULL,
                    city_id INTEGER NOT NULL REFERENCES dim_city(id)
                );
                CREATE TABLE inventories (
                    id TEXT PRIMARY KEY, id_space TEXT NOT NULL REFERENCES id_spaces(id),
                    name TEXT NOT NULL, url TEXT NOT NULL
                );
                INSERT INTO dim_city VALUES
                    (1, 'us-ca-sf', 'San Francisco', 'CA', 'San Francisco', 'https://example.invalid/sf-forestry'),
                    (2, 'us-ca-sj', 'San Jose', 'CA', 'Santa Clara', 'https://example.invalid/sj-forestry');
                INSERT INTO id_spaces VALUES
                    ('sf', '', 'test fixture', 1),
                    ('us-ca-sj', 'us-ca-sj:', 'test fixture', 2);
                INSERT INTO inventories VALUES
                    ('sf_city', 'sf', 'test SF inventory', 'https://example.invalid/sf'),
                    ('sj_street_tree', 'us-ca-sj', 'test SJ inventory', 'https://example.invalid/sj');
                """)
        case .shortNameOnly:
            try connection.execute("""
                CREATE TABLE id_spaces (
                    id TEXT PRIMARY KEY, identity_prefix TEXT NOT NULL, note TEXT NOT NULL,
                    short_name TEXT NOT NULL
                );
                CREATE TABLE inventories (
                    id TEXT PRIMARY KEY, id_space TEXT NOT NULL REFERENCES id_spaces(id),
                    name TEXT NOT NULL, url TEXT NOT NULL
                );
                INSERT INTO id_spaces VALUES ('sf', '', 'test fixture', 'San Francisco');
                INSERT INTO inventories VALUES
                    ('sf_city', 'sf', 'test SF inventory', 'https://example.invalid/sf');
                """)
        case .preIdSpace:
            break
        }

        try connection.execute("""
            CREATE TABLE trees (
                id INTEGER PRIMARY KEY, uuid TEXT NOT NULL UNIQUE,
                external_ref TEXT, \(idSpaceColumn)
                source TEXT NOT NULL, lat REAL NOT NULL, lon REAL NOT NULL,
                address TEXT, site_type TEXT, neighborhood_id INTEGER, status TEXT NOT NULL,
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
            let idSpaceInsert = treesHaveIDSpaceColumn ? "\(idSpaceValue)," : ""
            try connection.execute("""
                INSERT INTO trees (
                    uuid, external_ref, \(treesHaveIDSpaceColumn ? "id_space," : "")
                    source, lat, lon, address, site_type, status,
                    verification_state, created_at, updated_at
                ) VALUES (
                    -- **Lower case, because every published inventory file is.** `trees.uuid`
                    -- is `NOT NULL UNIQUE`, so its index is BINARY, and `TreeQueries` seeks it with
                    -- `lower(:uuid)` rather than a `COLLATE NOCASE` comparison no index can answer.
                    -- `Tools/build_seed.py` writes lower case (0 of 198,625 rows disagree) and
                    -- `DataGates.seedContract` now asserts it per arm; a fixture that wrote
                    -- Foundation's uppercase canonical string would be standing in for a file that
                    -- cannot exist, and would be the only thing in the suite asking for a collation
                    -- the app no longer uses.
                    '\(uuid.uuidString.lowercased())', '1', \(idSpaceInsert)
                    'city_import', 37.7, -122.4, 'Test Address', NULL, 'alive',
                    'city_record', '\(now)', '\(now)'
                );
                """)
        }
        try insertTree(uuid: Self.sfTreeID, idSpace: treesHaveIDSpaceColumn ? "sf" : nil)
        if shape == .dimCity {
            // Only this shape registers `us-ca-sj` in `id_spaces` at all — `.shortNameOnly`
            // deliberately carries only `sf`, so a second row here would reference an id space
            // the fixture never declared.
            try insertTree(uuid: Self.sjTreeID, idSpace: "us-ca-sj")
        }

        return url
    }
}
