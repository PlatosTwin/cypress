import Foundation
import Testing
@testable import Cypress

/// **The s17 round — `dim_region`, the unit a pack is *published* in.**
///
/// RULING D1 makes New York's published unit the borough. `Tools/publish_cities.py` had always
/// narrowed the fused seed on `trees.id_space`, and an id space cannot express a unit smaller
/// than a city, so the publisher needed a finer column to narrow on and a borough needed
/// somewhere to keep its own name. It could not ride `trees.city_raw`: that column family renders
/// through `CityRecordPresentation`, whose `caretaker` label reads "Cared for by …", and *Cared
/// for by Queens* is a sentence the app would be shipping to a reader as fact. So s17 is a real
/// `dim_region` table plus a NOT NULL `trees.region_id` (RULING D17).
///
/// **Three version spaces move in this round and only two of them are here.** This suite is about
/// `SeedDatabase.newestKnownSchemaVersion` (the published seed/city file, R37.1's `s<n>`, 16 → 17)
/// and `CityManifest.knownFormat` (the envelope, 1 → 2). `AppSchema.currentVersion` — the
/// *writable* database's `PRAGMA user_version` — is a third space and **nothing in this round
/// touches it**; every table here lives in a read-only published file.
///
/// ── Why this suite builds its own fixtures rather than reading the shipped seed ──────────────────
/// Same reason as `DimCityTests`, `CivicShortNameTests` and `SpeciesTrigramTests`: the canonical
/// seed every tree gets (`Tools/setup_worktree.sh` copies it, CI fetches the same published
/// artifact) is **s16** as this is written and carries no `dim_region` at all. The conditional
/// test below asks the real seed the question it can answer today, and the unconditional ones
/// prove the mechanism against built fixtures covering the s16 shape, the s17 shape, and the two
/// half-migrated shapes that must not be mistaken for either.
@Suite("s17 — dim_region, the published unit")
struct RegionGenerationTests {

    // MARK: - The generation number itself

    /// The two spaces that move, pinned to the numbers the Python side stamps.
    ///
    /// **This is not a tautology test.** `Tools/publish_cities.py` writes `SEED_SCHEMA_VERSION`
    /// into every published file's `seed_meta.publish_schema_version` and into every manifest
    /// entry's `schema_version`, and `MANIFEST_FORMAT` into the envelope; this build compares
    /// against its own constants and refuses a file from the future. The two sides agreeing is
    /// the whole compatibility contract, and the only thing that can hold them together is a
    /// number asserted in both places — `Tools/test_publish_cities.py` asserts the Python half.
    @Test("the published-seed generation and the manifest format are the numbers this round set")
    func theGenerationNumbersAreWhatThisRoundSet() {
        #expect(SeedDatabase.newestKnownSchemaVersion == 17)
        #expect(CityManifest.knownFormat == 2)
        // Format 1 is still read during RULING D8's dual-publish window, and dropping it would
        // break this build against the format-1 object still in the bucket.
        #expect(CityManifest.knownFormats == [1, 2])
    }

    // MARK: - Which of these the seed on this machine can answer

    /// Same instrument as `DimCityTests.seedCarriesDimCity`: the file is asked directly, with the
    /// same `SeedDatabase.attach` introspection the app itself uses.
    static var seedCarriesRegions: Bool {
        guard let seedURL = SeedContractTests.seedURL,
              let connection = try? SQLiteConnection(path: ":memory:"),
              let schema = try? SeedDatabase.attach(seedURL, to: connection)
        else { return false }
        return schema.hasRegions
    }

    /// **What the real seed on this tree must answer today, honestly.** Not skipped: this is the
    /// fallback case itself, proved against the actual canonical file rather than a fixture, so
    /// the day the seed silently gains `dim_region` without `hasRegions` noticing would be caught
    /// here.
    @Test("today's canonical seed answers hasRegions honestly")
    func theCanonicalSeedAnswersHonestly() async throws {
        let seedURL = try #require(SeedContractTests.seedURL, "no seed database; set CYPRESS_SEED_PATH")
        let store = try await CypressStore.inMemory(seedURL: seedURL)
        let schema = try #require(store.seed)
        #expect(
            schema.hasRegions == Self.seedCarriesRegions,
            "the flag and the gate disagree about the same file"
        )
    }

    /// **An s16 file still opens, still attaches, and still names its city.** The compatibility
    /// half of the story, and the one a generation bump most often breaks: s17 is a pure addition,
    /// so nothing an s16 file carries has moved and the read layer must simply notice the absence
    /// rather than fail on it.
    @Test("an s16 seed still attaches and still resolves its city, with hasRegions false")
    func anS16SeedStillWorks() async throws {
        let url = try Self.miniSeed(shape: .noRegions)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = try await CypressStore.inMemory(seedURL: url)
        let schema = try #require(store.seed)
        #expect(!schema.hasRegions, "the fixture was built without dim_region after all")
        #expect(schema.hasDimCity, "the s16 fixture must still carry dim_city")
        #expect(schema.hasIdSpace)

        let queries = TreeQueries(schema: schema, seedHasSoftDeletedTrees: store.seedHasSoftDeletedTrees)
        let record = try await store.queue.read { connection in
            try queries.tree(id: Self.sfTreeID, connection: connection)
        }
        #expect(record != nil, "the query itself failed against a file this build must still read")
        #expect(record?.cityShortName == "San Francisco")
    }

    // MARK: - The mechanism, proved against built fixtures

    @Test("a fixture built with dim_region and trees.region_id reads hasRegions true")
    func aFixtureWithRegionsReadsTrue() async throws {
        let url = try Self.miniSeed(shape: .regions)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = try await CypressStore.inMemory(seedURL: url)
        let schema = try #require(store.seed)
        #expect(schema.hasRegions)
        #expect(schema.hasDimCity, "s17 is additive: dim_city does not go away")

        // The table is really there and really joined — the control that proves this suite reads
        // the new table rather than the flag reading true by coincidence. A pack's identity is
        // `pack_id`, which is deliberately NOT `dim_city.slug` (`sf` here is `us-ca-sf` there).
        let (packID, level, slug) = try await store.queue.read {
            connection -> (String, String, String) in
            let statement = try connection.cachedStatement("""
                SELECT r.pack_id AS pack_id, r.level AS level, c.slug AS slug
                  FROM \(SeedDatabase.schemaName).trees t
                  JOIN \(SeedDatabase.schemaName).dim_region r ON r.id = t.region_id
                  JOIN \(SeedDatabase.schemaName).dim_city c ON c.id = r.city_id
                 WHERE t.uuid = '\(Self.sfTreeID.uuidString)'
                """)
            return try #require(try statement.fetchOne {
                (try $0.string("pack_id"), try $0.string("level"), try $0.string("slug"))
            })
        }
        #expect(packID == "sf")
        #expect(level == "city", "a one-region city is level `city`, not a special case (RULING D2)")
        #expect(slug == "us-ca-sf")
        #expect(
            packID != slug,
            """
            the pack id and the city slug are separate facts, and for San Francisco they are \
            separate strings — which is why they are separate columns
            """
        )
    }

    /// **The adversarial half-shape, and the reason `hasRegions` is `&&` rather than either half
    /// alone.** `trees.region_id` exists but `dim_region` does not, so the column is an integer
    /// naming nothing. A flag gated on the column alone would read true here and every join
    /// through it would throw at prepare against a table that is not there.
    @Test("region_id without dim_region reads false, not true")
    func regionColumnWithoutDimRegionReadsFalse() async throws {
        let url = try Self.miniSeed(shape: .regionColumnOnly)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = try await CypressStore.inMemory(seedURL: url)
        let schema = try #require(store.seed)
        #expect(!schema.hasRegions, "a region_id with no dim_region to join is not a region dimension")

        // And the file still reads, which is the point of noticing rather than failing.
        let queries = TreeQueries(schema: schema, seedHasSoftDeletedTrees: store.seedHasSoftDeletedTrees)
        let record = try await store.queue.read { connection in
            try queries.tree(id: Self.sfTreeID, connection: connection)
        }
        #expect(record != nil)
    }

    /// The other half-shape: `dim_region` exists but no row points at it. A flag gated on the
    /// table alone would read true and describe a partition no row is in.
    @Test("dim_region without trees.region_id reads false, not true")
    func dimRegionWithoutTreeColumnReadsFalse() async throws {
        let url = try Self.miniSeed(shape: .dimRegionOnly)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = try await CypressStore.inMemory(seedURL: url)
        let schema = try #require(store.seed)
        #expect(!schema.hasRegions, "a dim_region no column points at describes nothing")
    }

    // MARK: - The manifest envelope (`manifest_format` 2)

    @Test("a format-2 entry decodes its region identity")
    func formatTwoDecodesRegion() throws {
        let manifest = try CityManifest.decode(Data(Self.manifestJSON(format: 2, regionJSON: """
            , "region": {
                "level": "borough",
                "parent_city": "us-ny-nyc",
                "parent_city_display_name": "New York City"
            }
            """).utf8))
        #expect(manifest.format == 2)
        let city = try #require(manifest.cities.first)
        let region = try #require(city.region, "format 2 carries a region and it did not decode")
        #expect(region.level == "borough")
        #expect(region.parentCity == "us-ny-nyc")
        #expect(region.parentCityDisplayName == "New York City")
        // The pack id and the parent city are different strings for a borough, which is the whole
        // reason `region` has to exist: nothing else on the entry can answer "which city".
        #expect(city.id != region.parentCity)
    }

    /// **A format-1 manifest still decodes, and its nil region is an answer rather than a gap.**
    /// RULING D8 keeps a format-1 object in the bucket for a release cycle and it lists whole-city
    /// packs only, so "no region stated" and "this is a whole city" are the same fact there.
    @Test("a format-1 entry decodes, with a nil region")
    func formatOneDecodesWithNilRegion() throws {
        let manifest = try CityManifest.decode(Data(Self.manifestJSON(format: 1).utf8))
        #expect(manifest.format == 1)
        let city = try #require(manifest.cities.first)
        #expect(city.region == nil)
        // Everything else still decodes — the format-1 entry is not degraded, only smaller.
        #expect(city.id == "sf")
        #expect(city.displayName == "San Francisco")
        #expect(city.schemaVersion == 17)
    }

    /// The rule that did **not** soften: an unknown format is still refused outright, before
    /// anything else is read. Accepting 1 and 2 is not the same as accepting whatever arrives.
    @Test("a format this build does not know is still refused outright")
    func anUnknownFormatIsStillRefused() throws {
        #expect(throws: CityManifest.DecodeError.unknownFormat(3)) {
            _ = try CityManifest.decode(Data(Self.manifestJSON(format: 3).utf8))
        }
        #expect(throws: CityManifest.DecodeError.unknownFormat(0)) {
            _ = try CityManifest.decode(Data(Self.manifestJSON(format: 0).utf8))
        }
    }

    /// **An unknown `level` must not take the catalog offline.** The level is the publisher's
    /// vocabulary and may gain a member without a format bump (R37.4's additive rule applies to a
    /// value as much as to a key). A Swift enum here would turn that into a decode failure across
    /// the whole manifest — every city gone over one string.
    @Test("an unrecognized region level decodes rather than failing the manifest")
    func anUnknownLevelStillDecodes() throws {
        let manifest = try CityManifest.decode(Data(Self.manifestJSON(format: 2, regionJSON: """
            , "region": {
                "level": "arrondissement",
                "parent_city": "fr-75-paris",
                "parent_city_display_name": "Paris"
            }
            """).utf8))
        let region = try #require(manifest.cities.first?.region)
        #expect(region.level == "arrondissement")
    }

    // MARK: - The compatibility gate, both directions

    /// **An s17 file is refused by a build that reads s16, and the refusal is per-city.** This is
    /// R37.1's rule and the fossil-install lesson pointed forward: a file from the future must
    /// never be downloaded, let alone attached. Stated here as the s17 case specifically, because
    /// "what does an old app do with a v17 city file" is the question this round has to answer.
    @Test("an s17 pack is refused by an s16-reading build, and an s16 pack is not")
    func generationGateRefusesForwardOnly() {
        let s17 = CityManifest.City(
            id: "sf", displayName: "San Francisco", coverage: "full", treeCount: 1,
            schemaVersion: 17, version: "s17-r2026-07-31-abcd1234",
            path: "cities/sf/x/sf.sqlite", bytes: 1, sha256: "00"
        )
        // The build that has not shipped this round yet.
        #expect(
            CityInstallState(published: s17, installedVersion: nil, newestKnownSchemaVersion: 16)
                == .needsNewerApp(installedVersion: nil)
        )
        #expect(
            !CityInstallState(published: s17, installedVersion: nil, newestKnownSchemaVersion: 16)
                .allowsDownload,
            "a file from the future must not be downloadable"
        )
        // This build reads it.
        #expect(
            CityInstallState(published: s17, installedVersion: nil,
                             newestKnownSchemaVersion: SeedDatabase.newestKnownSchemaVersion)
                == .notInstalled
        )
        // And an older generation stays readable — the bump does not orphan what is installed.
        let s16 = CityManifest.City(
            id: "sf", displayName: "San Francisco", coverage: "full", treeCount: 1,
            schemaVersion: 16, version: "s16-r2026-07-31-abcd1234",
            path: "cities/sf/x/sf.sqlite", bytes: 1, sha256: "00"
        )
        #expect(
            CityInstallState(published: s16, installedVersion: nil,
                             newestKnownSchemaVersion: SeedDatabase.newestKnownSchemaVersion)
                == .notInstalled
        )
    }

    // MARK: - The manifest fallback (the other direction of RULING D8's window)

    /// **A new build against an old bucket.** D8 protects an unupdated *install* against a
    /// republished bucket; nothing in it protects a *new build* against a bucket that has not been
    /// republished yet — and that is the ordinary state of the world between shipping this round
    /// and running the next publish. Without the fallback, every install of this build would show
    /// "Couldn't check what's available" until someone remembered to republish.
    @Test("a base URL serving only the format-1 manifest still yields a catalog")
    func fallsBackToTheFormatOneManifest() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("s17-fallback-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // Only the legacy object exists — the shape of the bucket right now.
        try Data(Self.manifestJSON(format: 1).utf8)
            .write(to: directory.appendingPathComponent(CityDownloader.legacyManifestName))

        let manifest = try await CityDownloader(baseURL: directory).fetchManifest()
        #expect(manifest.format == 1)
        #expect(manifest.cities.map(\.id) == ["sf"])
        #expect(manifest.cities.first?.region == nil)
    }

    /// And when both exist, the format-2 object wins — otherwise the fallback would be a
    /// permanent downgrade to the whole-cities-only catalog rather than a transitional one.
    @Test("the format-2 manifest is preferred when both are published")
    func prefersTheFormatTwoManifest() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("s17-prefer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try Data(Self.manifestJSON(format: 1).utf8)
            .write(to: directory.appendingPathComponent(CityDownloader.legacyManifestName))
        try Data(Self.manifestJSON(format: 2, regionJSON: """
            , "region": {
                "level": "borough",
                "parent_city": "us-ny-nyc",
                "parent_city_display_name": "New York City"
            }
            """).utf8)
            .write(to: directory.appendingPathComponent(CityDownloader.manifestName))

        let manifest = try await CityDownloader(baseURL: directory).fetchManifest()
        #expect(manifest.format == 2, "the fallback fired even though format 2 was published")
        #expect(manifest.cities.first?.region?.level == "borough")
    }

    /// **The fallback is on absence and on nothing else.** A manifest that is present but does not
    /// decode is a fact about *that object*, and retrying it against the legacy path would turn
    /// one honest error into a confusing second one — and would silently downgrade a reader to the
    /// whole-cities-only catalog whenever the real catalog had a bad byte.
    @Test("a malformed format-2 manifest propagates rather than falling back")
    func aMalformedManifestDoesNotFallBack() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("s17-nofallback-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // A perfectly good legacy manifest sits beside a broken new one. If the fallback fired on
        // anything but absence, this would succeed — and hide the broken object indefinitely.
        try Data(Self.manifestJSON(format: 1).utf8)
            .write(to: directory.appendingPathComponent(CityDownloader.legacyManifestName))
        try Data("{ not json".utf8)
            .write(to: directory.appendingPathComponent(CityDownloader.manifestName))

        await #expect(throws: (any Error).self) {
            _ = try await CityDownloader(baseURL: directory).fetchManifest()
        }
    }

    // MARK: - Fixture

    private static let sfTreeID = UUID(uuidString: "00000000-0000-4000-8000-0000000CAFE1")!

    private enum Shape: Equatable {
        /// `dim_region` present and `trees.region_id` present — s17.
        case regions
        /// Neither — s16, the shape the canonical seed still has.
        case noRegions
        /// `trees.region_id` present, `dim_region` absent. Half-migrated, must read false.
        case regionColumnOnly
        /// `dim_region` present, `trees.region_id` absent. The other half, must read false.
        case dimRegionOnly
    }

    /// A minimal but complete `TreeQueries.tree(id:)` fixture, the same builder shape as
    /// `DimCityTests.miniSeed` so the query under test runs the SQL production runs.
    private static func miniSeed(shape: Shape) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("s17-\(UUID().uuidString)")
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
                (1, 'us-ca-sf', 'San Francisco', 'CA', 'San Francisco',
                 'https://example.invalid/sf-forestry');
            INSERT INTO id_spaces VALUES ('sf', '', 'test fixture', 1);
            INSERT INTO inventories VALUES
                ('sf_city', 'sf', 'test SF inventory', 'https://example.invalid/sf');
            """)

        let hasDimRegion = shape == .regions || shape == .dimRegionOnly
        let hasRegionColumn = shape == .regions || shape == .regionColumnOnly

        if hasDimRegion {
            try connection.execute("""
                CREATE TABLE dim_region (
                    id INTEGER PRIMARY KEY, pack_id TEXT NOT NULL UNIQUE,
                    display_name TEXT NOT NULL, level TEXT NOT NULL,
                    city_id INTEGER NOT NULL REFERENCES dim_city(id)
                );
                INSERT INTO dim_region VALUES (1, 'sf', 'San Francisco', 'city', 1);
                """)
        }

        // `region_id` is NOT NULL in the real schema. The fixture declares it nullable on purpose
        // for `.regionColumnOnly`, where there is no `dim_region` for a value to reference — the
        // shape under test is a half-migration, and a half-migration is not required to satisfy
        // the finished schema's constraints.
        let regionColumn = hasRegionColumn ? "region_id INTEGER," : ""
        try connection.execute("""
            CREATE TABLE trees (
                id INTEGER PRIMARY KEY, uuid TEXT NOT NULL UNIQUE,
                external_ref TEXT, id_space TEXT REFERENCES id_spaces(id),
                \(regionColumn)
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
        let regionInsertColumn = hasRegionColumn ? "region_id," : ""
        let regionInsertValue = hasRegionColumn ? "1," : ""
        try connection.execute("""
            INSERT INTO trees (
                uuid, external_ref, id_space, \(regionInsertColumn)
                source, lat, lon, address, site_type, status,
                verification_state, created_at, updated_at
            ) VALUES (
                '\(Self.sfTreeID.uuidString)', '1', 'sf', \(regionInsertValue)
                'city_import', 37.7, -122.4, 'Test Address', NULL, 'alive',
                'city_record', '\(now)', '\(now)'
            );
            """)

        return url
    }

    /// One manifest entry, with the envelope's format and an optional region blob spliced in.
    /// Written as text rather than encoded from the Swift type on purpose: the thing under test is
    /// this build's ability to read what **`Tools/publish_cities.py`** writes, and encoding it
    /// from the reader's own type would prove only that the reader agrees with itself.
    private static func manifestJSON(format: Int, regionJSON: String = "") -> String {
        """
        {
          "manifest_format": \(format),
          "generated_at": "2026-08-22T00:00:00+00:00",
          "generator": "Tools/publish_cities.py",
          "source_seed": {"tree_count": 1, "sha256": "ab", "build_id": "abcd1234",
                          "path": "seed/abcd1234/cypress-seed.sqlite", "bytes": 1},
          "cities": [
            {
              "id": "sf",
              "display_name": "San Francisco",
              "coverage": "full",
              "tree_count": 145837,
              "schema_version": 17,
              "content_rev": "2026-07-31",
              "version": "s17-r2026-07-31-abcd1234",
              "bbox": {"min_lat": 37.7, "max_lat": 37.8, "min_lon": -122.5, "max_lon": -122.4},
              "centroid": {"lat": 37.75, "lon": -122.45},
              "path": "cities/sf/s17-r2026-07-31-abcd1234/sf.sqlite",
              "bytes": 81000000,
              "sha256": "00"\(regionJSON)
            }
          ]
        }
        """
    }
}
