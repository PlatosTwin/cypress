import Foundation
import Testing
@testable import Cypress

/// The union read layer: what several attached inventories add up to, and the two ways the bundled
/// arm's shadowed rows are excluded.
///
/// **Every fixture here is built by `seed(at:)` from an explicit row list**, rather than narrowed
/// from the shipped file, so a test that depends on ids being contiguous can say so and a test that
/// depends on them *not* being can build that too. The shipped seed's own contiguity is a property
/// of one build (`InventoryUnion.shadowMechanism`), and a suite that could only reproduce that
/// property would be testing one of the two paths.
@Suite("Cumulative inventories · the union read layer")
struct CumulativeInventoryTests {

    // MARK: - Fixtures

    static func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cuminv-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    struct TreeRow {
        let id: Int64
        let idSpace: String
        let lat: Double
        let lon: Double
        /// The **file-local** species id, which is the whole point of the divergent-arm case.
        let speciesID: Int64?
    }

    struct SpeciesRow {
        let id: Int64
        let uuid: String
        let scientificName: String
    }

    /// A seed shaped like the real one in every column the union reads.
    ///
    /// - Parameter packID: when given, the file is shaped like a **published s17 pack** — it carries
    ///   `dim_region` and a `trees.region_id`, which every one of the seven live packs does and
    ///   which the default fixture here deliberately does not (the bundled seed is s16). The
    ///   difference is not cosmetic: `dim_region` is the catalog the union's teardown once failed to
    ///   drop, so a test about teardown that used the default shape would examine the one file shape
    ///   the defect could not reach.
    static func seed(
        at url: URL,
        trees: [TreeRow],
        species: [SpeciesRow],
        neighborhoods: [(id: Int64, name: String)] = [],
        publishSchemaVersion: Int = 17,
        contentRev: String? = nil,
        packID: String? = nil
    ) throws {
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
            CREATE UNIQUE INDEX idx_species_scientific_name ON species(scientific_name);
            CREATE INDEX idx_species_common_name ON species(common_name);
            CREATE INDEX idx_species_curated ON species(curated);
            CREATE TABLE species_trigrams (
                trigram TEXT NOT NULL, species_id INTEGER NOT NULL,
                PRIMARY KEY (trigram, species_id)
            ) WITHOUT ROWID;
            CREATE TABLE neighborhoods (
                id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE, geom_geojson TEXT NOT NULL,
                min_lat REAL NOT NULL, max_lat REAL NOT NULL,
                min_lon REAL NOT NULL, max_lon REAL NOT NULL,
                created_at TEXT NOT NULL, updated_at TEXT NOT NULL
            );
            CREATE TABLE dim_city (
                id INTEGER PRIMARY KEY, slug TEXT NOT NULL UNIQUE, display_name TEXT NOT NULL,
                state TEXT NOT NULL, county TEXT NOT NULL, urban_forestry_url TEXT NOT NULL
            );
            CREATE TABLE id_spaces (
                id TEXT PRIMARY KEY, identity_prefix TEXT NOT NULL, note TEXT NOT NULL,
                city_id INTEGER NOT NULL REFERENCES dim_city(id)
            );
            CREATE TABLE inventories (
                id TEXT PRIMARY KEY, id_space TEXT NOT NULL, name TEXT NOT NULL, url TEXT NOT NULL
            );
            CREATE TABLE trees (
                id INTEGER PRIMARY KEY, uuid TEXT NOT NULL UNIQUE,
                id_space TEXT NOT NULL, external_ref TEXT NOT NULL, source TEXT NOT NULL,
                inventory_source TEXT NOT NULL, lat REAL NOT NULL, lon REAL NOT NULL,
                address TEXT, site_type TEXT, neighborhood_id INTEGER,
                status TEXT NOT NULL, species_current INTEGER REFERENCES species(id),
                planted_year INTEGER, planted_on TEXT,
                dbh_city_cm_min INTEGER, dbh_city_cm_max INTEGER,
                site_lineage INTEGER, verification_state TEXT NOT NULL,
                legal_status TEXT, caretaker TEXT, care_assistant TEXT, plant_type TEXT,
                plot_size TEXT, permit_notes TEXT, city_raw TEXT,
                created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT,
                UNIQUE (id_space, external_ref)
            );
            CREATE INDEX idx_trees_lat_lon ON trees(lat, lon, id);
            CREATE INDEX idx_trees_species_current ON trees(species_current);
            CREATE TABLE species_assertions (
                id INTEGER PRIMARY KEY, tree_id INTEGER NOT NULL, species_id INTEGER NOT NULL,
                source TEXT NOT NULL, confidence REAL, asserted_by INTEGER,
                superseded_by INTEGER, created_at TEXT NOT NULL
            );
            CREATE VIRTUAL TABLE trees_rtree USING rtree(id, min_lat, max_lat, min_lon, max_lon);
            CREATE TABLE seed_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
            """)

        try connection.execute(
            "INSERT INTO seed_meta VALUES ('publish_schema_version', '\(publishSchemaVersion)')"
        )
        if let contentRev {
            try connection.execute(
                "INSERT INTO seed_meta VALUES ('publish_content_rev', '\(contentRev)')"
            )
        }

        for row in species {
            try connection.execute("""
                INSERT INTO species (id, uuid, scientific_name, created_at, updated_at)
                VALUES (\(row.id), '\(row.uuid)', '\(row.scientificName)', 'x', 'x')
                """)
            try connection.execute(
                "INSERT INTO species_trigrams VALUES ('\(row.scientificName.prefix(3).lowercased())', \(row.id))"
            )
        }
        for hood in neighborhoods {
            try connection.execute("""
                INSERT INTO neighborhoods VALUES
                (\(hood.id), '\(hood.name)', '{}', 0, 1, 0, 1, 'x', 'x')
                """)
        }
        for space in Set(trees.map(\.idSpace)).sorted() {
            let cityID = abs(space.hashValue % 1000) + 1
            try connection.execute("""
                INSERT OR IGNORE INTO dim_city VALUES
                (\(cityID), '\(space)-city', '\(space.uppercased())', 'CA', 'C', 'https://x')
                """)
            try connection.execute(
                "INSERT INTO id_spaces VALUES ('\(space)', '', '', \(cityID))"
            )
            try connection.execute(
                "INSERT INTO inventories VALUES ('\(space)_src', '\(space)', 'n', 'https://x')"
            )
        }
        for tree in trees {
            let species = tree.speciesID.map(String.init) ?? "NULL"
            let hood = neighborhoods.first.map { String($0.id) } ?? "NULL"
            // A real uuid, because `TreeQueries.decodePin` parses one and a fixture that hands it
            // `sf-1` fails on the fixture rather than on the union. Derived from the id space and
            // the row id so it is stable across runs and distinct across arms — two files that
            // gave one tree two identities would hide a de-duplication defect.
            let uuid = Self.uuid(space: tree.idSpace, id: tree.id)
            try connection.execute("""
                INSERT INTO trees (
                    id, uuid, id_space, external_ref, source, inventory_source, lat, lon,
                    neighborhood_id, status, species_current, verification_state,
                    created_at, updated_at
                ) VALUES (
                    \(tree.id), '\(uuid)', '\(tree.idSpace)', '\(tree.id)',
                    'city_import', '\(tree.idSpace)_src', \(tree.lat), \(tree.lon),
                    \(hood), 'alive', \(species), 'city_record', 'x', 'x'
                )
                """)
            try connection.execute("""
                INSERT INTO trees_rtree VALUES
                (\(tree.id), \(tree.lat), \(tree.lat), \(tree.lon), \(tree.lon))
                """)
        }

        // The s17 pack dimension, in the shape `Tools/publish_cities.py` writes: one `dim_region`
        // row per pack, keyed by `pack_id`, and a `trees.region_id` pointing at it. Added after the
        // rows because the column is what makes this an s17 file, not what makes the rows valid.
        if let packID {
            let cityID = abs((trees.first?.idSpace ?? "sf").hashValue % 1000) + 1
            try connection.execute("""
                CREATE TABLE dim_region (
                    id INTEGER PRIMARY KEY, pack_id TEXT NOT NULL UNIQUE,
                    display_name TEXT NOT NULL, level TEXT NOT NULL,
                    city_id INTEGER NOT NULL REFERENCES dim_city(id),
                    CHECK (level IN ('city','borough','extent'))
                );
                INSERT INTO dim_region VALUES (1, '\(packID)', '\(packID)', 'city', \(cityID));
                ALTER TABLE trees ADD COLUMN region_id INTEGER REFERENCES dim_region(id);
                UPDATE trees SET region_id = 1;
                """)
        }
        try connection.execute("ANALYZE")
    }

    /// A stable, distinct uuid per `(id space, row id)`. Deterministic so a rerun compares equal.
    static func uuid(space: String, id: Int64) -> String {
        let tail = String(format: "%012d", id)
        let head = String(format: "%08x", abs(space.hashValue) % 0xFFFF_FFFF)
        return "\(head)-0000-4000-8000-\(tail)"
    }

    /// The two species every fixture shares, by uuid. Their *ids* are what a divergent arm changes.
    static let plane = SpeciesRow(id: 1, uuid: "aaaaaaaa-0000-0000-0000-000000000001",
                                  scientificName: "Platanus acerifolia")
    static let ginkgo = SpeciesRow(id: 2, uuid: "aaaaaaaa-0000-0000-0000-000000000002",
                                   scientificName: "Ginkgo biloba")

    static func file(_ url: URL, bundled: Bool = false, id: String = "pack") -> InventoryFile {
        bundled ? .bundled(url: url) : InventoryFile(id: id, url: url, isBundled: false)
    }

    static func store(_ files: [InventoryFile]) async throws -> CypressStore {
        try await CypressStore.inMemory(inventories: files)
    }

    static func count(_ store: CypressStore, _ sql: String) async throws -> Int64 {
        try await store.queue.read { connection in
            let statement = try connection.prepare(sql)
            defer { statement.finalize() }
            return try statement.fetchOne { try $0.int64("n") } ?? -1
        }
    }

    // MARK: - The union adds up

    /// Two inventories that cover different ground are simply both there, and the bundled arm keeps
    /// the ids it had before the union existed.
    @Test("two inventories are read as one, and arm 0 keeps its own ids")
    func twoInventoriesReadAsOne() async throws {
        let dir = try Self.tempDir()
        let bundleURL = dir.appendingPathComponent("bundle.sqlite")
        let packURL = dir.appendingPathComponent("pack.sqlite")
        try Self.seed(
            at: bundleURL,
            trees: (1...4).map {
                TreeRow(id: Int64($0), idSpace: "sf", lat: 37.7, lon: -122.4, speciesID: 1)
            },
            species: [Self.plane, Self.ginkgo]
        )
        try Self.seed(
            at: packURL,
            trees: (1...3).map {
                TreeRow(id: Int64($0), idSpace: "us-ny-nyc", lat: 40.7, lon: -74.0, speciesID: 2)
            },
            species: [Self.plane, Self.ginkgo]
        )

        let store = try await Self.store([
            Self.file(bundleURL, bundled: true), Self.file(packURL, id: "manhattan")
        ])
        let union = try #require(store.inventory)
        #expect(union.arms.map(\.id) == [InventoryFile.bundledID, "manhattan"])
        #expect(union.arms.map(\.ordinal) == [0, 1])
        #expect(union.refused.isEmpty, "an inventory was refused: \(union.refused)")

        let n1 = try await Self.count(store, "SELECT COUNT(*) AS n FROM temp.trees")
        #expect(n1 == 7)
        let distinct = try await Self.count(
            store, "SELECT COUNT(DISTINCT id) AS n FROM temp.trees"
        )
        #expect(distinct == 7, "two arms produced a colliding union id")
        // Arm 0 is the bundle, so `ordinal * armStride` is zero and every bundled tree's union id
        // is the id it always had. Nothing downstream has to be told the bundle moved, because it
        // did not.
        let bundledUnshifted = try await Self.count(
            store, "SELECT COUNT(*) AS n FROM temp.trees WHERE inv = 0 AND id = local_id"
        )
        #expect(bundledUnshifted == 4)
        let armOneUnshifted = try await Self.count(
            store, "SELECT COUNT(*) AS n FROM temp.trees WHERE inv = 1 AND id = local_id"
        )
        #expect(armOneUnshifted == 0, "a downloaded arm's ids collide with the bundle's")
        // And the geo view agrees with the full one, row for row.
        let n2 = try await Self.count(store, "SELECT COUNT(*) AS n FROM temp.trees_geo")
        #expect(n2 == 7)
    }

    // MARK: - Shadowing (RULING D1)

    /// **The bundled arm's rows for a downloaded city are excluded by a rowid range** when that
    /// space's ids are contiguous, which is what keeps `idx_trees_lat_lon` covering.
    @Test("a downloaded city shadows the bundle's copy of it, by rowid range")
    func shadowingUsesTheRowIDRangeWhenItCan() async throws {
        let dir = try Self.tempDir()
        let bundleURL = dir.appendingPathComponent("bundle.sqlite")
        let packURL = dir.appendingPathComponent("sf.sqlite")

        // Contiguous by construction: sf is 1…4, us-ca-sj is 5…7.
        var trees = (1...4).map {
            TreeRow(id: Int64($0), idSpace: "sf", lat: 37.7, lon: -122.4, speciesID: 1)
        }
        trees += (5...7).map {
            TreeRow(id: Int64($0), idSpace: "us-ca-sj", lat: 37.3, lon: -121.9, speciesID: 1)
        }
        try Self.seed(at: bundleURL, trees: trees, species: [Self.plane, Self.ginkgo])
        // The pack's San Francisco: two rows, and they are the ones that must be drawn.
        try Self.seed(
            at: packURL,
            trees: (1...2).map {
                TreeRow(id: Int64($0), idSpace: "sf", lat: 37.75, lon: -122.45, speciesID: 1)
            },
            species: [Self.plane, Self.ginkgo]
        )

        let store = try await Self.store([
            Self.file(bundleURL, bundled: true), Self.file(packURL, id: "sf")
        ])
        let union = try #require(store.inventory)
        let bundle = try #require(union.arms.first)
        #expect(
            bundle.shadowed.map(\.idSpace) == ["sf"],
            "the bundle shadowed \(bundle.shadowed) rather than San Francisco alone"
        )
        #expect(
            bundle.shadowed.first?.mechanism == .rowIDRange(low: 1, high: 4),
            "a contiguous id space did not take the rowid-range path: \(bundle.shadowed)"
        )
        // A pack never shadows: only the bundled arm carries an exclusion.
        #expect(union.arms.dropFirst().allSatisfy { $0.shadowed.isEmpty })

        // Three San Jose rows from the bundle, two San Francisco rows from the pack. Not one
        // bundled San Francisco tree survives, and not one San Jose tree is lost with them.
        let n3 = try await Self.count(store, "SELECT COUNT(*) AS n FROM temp.trees")
        #expect(n3 == 5)
        let packSF = try await Self.count(
            store, "SELECT COUNT(*) AS n FROM temp.trees WHERE id_space = 'sf' AND inv = 1"
        )
        #expect(packSF == 2)
        let bundledSF = try await Self.count(
            store, "SELECT COUNT(*) AS n FROM temp.trees WHERE id_space = 'sf' AND inv = 0"
        )
        #expect(bundledSF == 0, "the bundle's San Francisco rows were drawn beside the pack's")
        let sanJose = try await Self.count(
            store, "SELECT COUNT(*) AS n FROM temp.trees WHERE id_space = 'us-ca-sj'"
        )
        #expect(sanJose == 3, "shadowing San Francisco took San Jose with it")
        // The geo view shadows identically — the map and the profile must not disagree about
        // which trees exist.
        let n4 = try await Self.count(store, "SELECT COUNT(*) AS n FROM temp.trees_geo")
        #expect(n4 == 5)
    }

    /// **And by the `id_space` predicate when it cannot.** The rowid range is a property of one
    /// build of one file; interleave the two spaces and the only correct predicate is the column.
    ///
    /// The two paths must produce **the same rows**, which is the half that matters: the fast path
    /// is an optimization and an optimization that changes the answer is a defect.
    @Test("an interleaved id space falls back to the column, and both paths agree")
    func shadowingFallsBackToTheIDSpacePredicate() async throws {
        let dir = try Self.tempDir()
        let interleaved = dir.appendingPathComponent("interleaved.sqlite")
        let contiguous = dir.appendingPathComponent("contiguous.sqlite")
        let packURL = dir.appendingPathComponent("sf.sqlite")

        // sf holds 1, 3, 5; us-ca-sj holds 2, 4. Neither is a contiguous run.
        let mixed = [
            TreeRow(id: 1, idSpace: "sf", lat: 37.7, lon: -122.4, speciesID: 1),
            TreeRow(id: 2, idSpace: "us-ca-sj", lat: 37.3, lon: -121.9, speciesID: 1),
            TreeRow(id: 3, idSpace: "sf", lat: 37.71, lon: -122.41, speciesID: 1),
            TreeRow(id: 4, idSpace: "us-ca-sj", lat: 37.31, lon: -121.91, speciesID: 1),
            TreeRow(id: 5, idSpace: "sf", lat: 37.72, lon: -122.42, speciesID: 1)
        ]
        try Self.seed(at: interleaved, trees: mixed, species: [Self.plane, Self.ginkgo])
        // The same five rows, the same spaces, laid out contiguously: sf 1…3, us-ca-sj 4…5.
        try Self.seed(
            at: contiguous,
            trees: [
                TreeRow(id: 1, idSpace: "sf", lat: 37.7, lon: -122.4, speciesID: 1),
                TreeRow(id: 2, idSpace: "sf", lat: 37.71, lon: -122.41, speciesID: 1),
                TreeRow(id: 3, idSpace: "sf", lat: 37.72, lon: -122.42, speciesID: 1),
                TreeRow(id: 4, idSpace: "us-ca-sj", lat: 37.3, lon: -121.9, speciesID: 1),
                TreeRow(id: 5, idSpace: "us-ca-sj", lat: 37.31, lon: -121.91, speciesID: 1)
            ],
            species: [Self.plane, Self.ginkgo]
        )
        try Self.seed(
            at: packURL,
            trees: [TreeRow(id: 1, idSpace: "sf", lat: 37.75, lon: -122.45, speciesID: 1)],
            species: [Self.plane, Self.ginkgo]
        )

        let slow = try await Self.store([
            Self.file(interleaved, bundled: true), Self.file(packURL, id: "sf")
        ])
        let fast = try await Self.store([
            Self.file(contiguous, bundled: true), Self.file(packURL, id: "sf")
        ])

        let slowMechanism = try #require(slow.inventory?.arms.first).shadowed.first?.mechanism
        let fastMechanism = try #require(fast.inventory?.arms.first).shadowed.first?.mechanism
        #expect(
            slowMechanism == .idSpacePredicate,
            "an interleaved id space was excluded by a range, which would drop San Jose rows"
        )
        #expect(fastMechanism == .rowIDRange(low: 1, high: 3))

        // Both arrangements: two San Jose rows from the bundle plus one San Francisco row from the
        // pack. The layout of the file must not change what the reader sees.
        for (name, store) in [("interleaved", slow), ("contiguous", fast)] {
            let total = try await Self.count(store, "SELECT COUNT(*) AS n FROM temp.trees")
            let sanJose = try await Self.count(
                store, "SELECT COUNT(*) AS n FROM temp.trees WHERE id_space = 'us-ca-sj'"
            )
            let sanFrancisco = try await Self.count(
                store, "SELECT COUNT(*) AS n FROM temp.trees WHERE id_space = 'sf'"
            )
            #expect(total == 3, "\(name): wrong row count")
            #expect(sanJose == 2, "\(name): San Jose rows were lost with San Francisco's")
            #expect(sanFrancisco == 1, "\(name): the bundled San Francisco rows were not shadowed")
        }
    }

    /// **A pack never shadows another pack**, and the five New York boroughs are why: they share
    /// one id space, so an id-space rule applied between packs would delete Brooklyn the moment
    /// Manhattan was installed.
    @Test("two packs sharing an id space both survive")
    func packsDoNotShadowEachOther() async throws {
        let dir = try Self.tempDir()
        let bundleURL = dir.appendingPathComponent("bundle.sqlite")
        let manhattan = dir.appendingPathComponent("manhattan.sqlite")
        let brooklyn = dir.appendingPathComponent("brooklyn.sqlite")

        try Self.seed(
            at: bundleURL,
            trees: [TreeRow(id: 1, idSpace: "sf", lat: 37.7, lon: -122.4, speciesID: 1)],
            species: [Self.plane, Self.ginkgo]
        )
        try Self.seed(
            at: manhattan,
            trees: (1...2).map {
                TreeRow(id: Int64($0), idSpace: "us-ny-nyc", lat: 40.78, lon: -73.96, speciesID: 1)
            },
            species: [Self.plane, Self.ginkgo]
        )
        try Self.seed(
            at: brooklyn,
            trees: (1...3).map {
                TreeRow(id: Int64($0), idSpace: "us-ny-nyc", lat: 40.67, lon: -73.94, speciesID: 1)
            },
            species: [Self.plane, Self.ginkgo]
        )

        let store = try await Self.store([
            Self.file(bundleURL, bundled: true),
            Self.file(manhattan, id: "us-ny-nyc-manhattan"),
            Self.file(brooklyn, id: "us-ny-nyc-brooklyn")
        ])
        let union = try #require(store.inventory)
        #expect(union.arms.count == 3)
        let shadows = union.arms.map(\.shadowed)
        #expect(shadows.allSatisfy { $0.isEmpty }, "a pack shadowed something: \(shadows)")
        let boroughRows = try await Self.count(
            store, "SELECT COUNT(*) AS n FROM temp.trees WHERE id_space = 'us-ny-nyc'"
        )
        #expect(boroughRows == 5, "one borough deleted another: they share the id space us-ny-nyc")
        let n5 = try await Self.count(store, "SELECT COUNT(*) AS n FROM temp.trees")
        #expect(n5 == 6)
    }

    // MARK: - Species (RULING D6)

    /// **`species.id` is local to its file, and the union has to reconcile it.**
    ///
    /// `Tools/build_seed.py` assigns species ids in first-encounter order while it streams its
    /// sources, so two builds over different city sets number the same species differently. A
    /// literal union would let one file's `species_current = 1` join another file's row 1 and put
    /// the wrong name on the tree.
    ///
    /// The fixture makes that concrete: the pack numbers the two species the other way round. Every
    /// tree must still resolve to the species its **own file** says it is.
    @Test("a pack that numbers species differently still names every tree correctly")
    func speciesAreCanonicalAcrossDivergentArms() async throws {
        let dir = try Self.tempDir()
        let bundleURL = dir.appendingPathComponent("bundle.sqlite")
        let packURL = dir.appendingPathComponent("pack.sqlite")

        // The bundle: 1 = Plane, 2 = Ginkgo. Its one tree is a Plane.
        try Self.seed(
            at: bundleURL,
            trees: [TreeRow(id: 1, idSpace: "sf", lat: 37.7, lon: -122.4, speciesID: 1)],
            species: [Self.plane, Self.ginkgo]
        )
        // The pack: 1 = Ginkgo, 2 = Plane — the same two species, the opposite numbering. Its one
        // tree carries `species_current = 1`, which means Ginkgo in this file and Plane in the
        // other one.
        try Self.seed(
            at: packURL,
            trees: [TreeRow(id: 1, idSpace: "us-ny-nyc", lat: 40.7, lon: -74.0, speciesID: 1)],
            species: [
                SpeciesRow(id: 1, uuid: Self.ginkgo.uuid, scientificName: Self.ginkgo.scientificName),
                SpeciesRow(id: 2, uuid: Self.plane.uuid, scientificName: Self.plane.scientificName)
            ]
        )

        let store = try await Self.store([
            Self.file(bundleURL, bundled: true), Self.file(packURL, id: "manhattan")
        ])

        // One canonical row per species uuid — not one per attached inventory, which is what makes
        // a species list and every `GROUP BY s.id` mean anything at all.
        let n6 = try await Self.count(store, "SELECT COUNT(*) AS n FROM temp.species")
        #expect(n6 == 2)
        let distinctSpeciesUUIDs = try await Self.count(
            store, "SELECT COUNT(DISTINCT uuid) AS n FROM temp.species"
        )
        #expect(distinctSpeciesUUIDs == 2)

        let named: [(String, String)] = try await store.queue.read { connection in
            let statement = try connection.prepare("""
            SELECT t.id_space AS space, s.scientific_name AS name
              FROM temp.trees t JOIN temp.species s ON s.id = t.species_current
             ORDER BY t.id_space
            """)
            defer { statement.finalize() }
            return try statement.fetchAll { (try $0.string("space"), try $0.string("name")) }
        }
        #expect(
            named.first(where: { $0.0 == "sf" })?.1 == "Platanus acerifolia",
            "the bundled tree was renamed by the pack's numbering: \(named)"
        )
        #expect(
            named.first(where: { $0.0 == "us-ny-nyc" })?.1 == "Ginkgo biloba",
            "the pack's tree took the bundle's meaning of species id 1: \(named)"
        )

        // The denormalized uuid on the tree row agrees with the join, which is what the map's pins
        // read instead of joining.
        let disagreements = try await Self.count(store, """
        SELECT COUNT(*) AS n FROM temp.trees t JOIN temp.species s ON s.id = t.species_current
         WHERE s.uuid <> t.species_uuid
        """)
        #expect(disagreements == 0, "species_uuid and species_current disagree about a tree")

        // And the trigram index is re-keyed onto the canonical ids rather than left pointing at
        // whichever arm wrote it, so a search finds a species either file knows.
        let orphanTrigrams = try await Self.count(store, """
        SELECT COUNT(*) AS n FROM temp.species_trigrams g
         WHERE NOT EXISTS (SELECT 1 FROM temp.species s WHERE s.id = g.species_id)
        """)
        #expect(orphanTrigrams == 0, "a trigram points at a species the catalog does not have")
    }

    /// A species only the pack carries is **added** to the catalog rather than dropped, so search
    /// and the species list cover the union rather than the first arm.
    @Test("a species only one arm knows joins the canonical catalog")
    func aSpeciesOnlyOneArmKnowsIsKept() async throws {
        let dir = try Self.tempDir()
        let bundleURL = dir.appendingPathComponent("bundle.sqlite")
        let packURL = dir.appendingPathComponent("pack.sqlite")
        let honeyLocust = SpeciesRow(
            id: 7, uuid: "aaaaaaaa-0000-0000-0000-000000000007",
            scientificName: "Gleditsia triacanthos"
        )

        try Self.seed(
            at: bundleURL,
            trees: [TreeRow(id: 1, idSpace: "sf", lat: 37.7, lon: -122.4, speciesID: 1)],
            species: [Self.plane]
        )
        try Self.seed(
            at: packURL,
            trees: [TreeRow(id: 1, idSpace: "us-ny-nyc", lat: 40.7, lon: -74.0, speciesID: 7)],
            species: [Self.plane, honeyLocust]
        )

        let store = try await Self.store([
            Self.file(bundleURL, bundled: true), Self.file(packURL, id: "manhattan")
        ])
        let catalog = try await Self.count(store, "SELECT COUNT(*) AS n FROM temp.species")
        #expect(catalog == 2, "the pack's own species was dropped, or the shared one duplicated")
        let honeyLocustTrees = try await Self.count(store, """
        SELECT COUNT(*) AS n FROM temp.trees t JOIN temp.species s ON s.id = t.species_current
         WHERE s.scientific_name = 'Gleditsia triacanthos'
        """)
        #expect(honeyLocustTrees == 1)
    }

    // MARK: - Reading through TreeQueries

    /// The map's two-step — grid the viewport, then hydrate the winners — across two arms.
    ///
    /// **The composite id may never be bound into a `WHERE`**, which is why hydration splits by
    /// arm; this asserts the round trip rather than the plan, so it fails if the split is wrong in
    /// either direction: a winner from arm 1 looked up in arm 0 comes back as the wrong tree or as
    /// no tree at all.
    @Test("marker cells and pin hydration round-trip across two inventories")
    func mapHydrationCrossesArms() async throws {
        let dir = try Self.tempDir()
        let bundleURL = dir.appendingPathComponent("bundle.sqlite")
        let packURL = dir.appendingPathComponent("pack.sqlite")

        // Two trees in one place from the bundle, two from the pack, all in one viewport.
        try Self.seed(
            at: bundleURL,
            trees: [
                TreeRow(id: 1, idSpace: "sf", lat: 37.700, lon: -122.400, speciesID: 1),
                TreeRow(id: 2, idSpace: "sf", lat: 37.701, lon: -122.401, speciesID: 1)
            ],
            species: [Self.plane, Self.ginkgo]
        )
        try Self.seed(
            at: packURL,
            trees: [
                TreeRow(id: 1, idSpace: "us-ny-nyc", lat: 37.710, lon: -122.410, speciesID: 2),
                TreeRow(id: 2, idSpace: "us-ny-nyc", lat: 37.711, lon: -122.411, speciesID: 2)
            ],
            species: [Self.plane, Self.ginkgo]
        )

        let store = try await Self.store([
            Self.file(bundleURL, bundled: true), Self.file(packURL, id: "manhattan")
        ])
        let schema = try #require(store.seed)
        let queries = TreeQueries(
            schema: schema, seedHasSoftDeletedTrees: store.seedHasSoftDeletedTrees
        )
        let bounds = BoundingBox(
            minLatitude: 37.69, maxLatitude: 37.72,
            minLongitude: -122.42, maxLongitude: -122.39
        )

        // **The gridded path, forced.** `pinLimit: 2` against four trees is what makes
        // `pins(in:)` grid the viewport and then hydrate the winners, which is the only path that
        // reaches `pins(rowIDs:)`. Left at the default budget these four trees come back through
        // the un-gridded query and the hydration this test is named for never runs — which is
        // exactly what an earlier version of it did, and a break that hydrated from the wrong arm
        // stayed green.
        let gridded = MapViewport(bounds: bounds, zoom: 18, pinLimit: 2, markerCellPoints: 44)
        let cells = try await store.queue.read { connection in
            try queries.markerCells(in: gridded, cellPoints: 1, connection: connection)
        }
        #expect(cells.count == 4, "the grid produced \(cells.count) cells for four trees")
        let arms = Set(cells.map { InventoryUnion.decomposedID($0.rowID).ordinal })
        #expect(arms == [0, 1], "the winners came from \(arms), not from both inventories")

        let sampled = try await store.queue.read { connection in
            try queries.pins(in: gridded, connection: connection)
        }
        // Every winner hydrates, exactly once, into the tree it actually is. A hydration that
        // ignored the arm would read id 1 out of *both* files and hand back duplicates; one that
        // read the wrong file would hand back the other city's tree under this one's id.
        #expect(
            sampled.items.count == 4,
            "hydration returned \(sampled.items.count) pins for four winning cells"
        )
        let expected = Set(
            [("sf", Int64(1)), ("sf", 2), ("us-ny-nyc", 1), ("us-ny-nyc", 2)]
                .map { Self.uuid(space: $0.0, id: $0.1).lowercased() }
        )
        #expect(
            Set(sampled.items.map { $0.id.uuidString.lowercased() }) == expected,
            "hydration produced the wrong trees: \(sampled.items.map(\.id))"
        )
        // Both arms' species survive the round trip, so a pin drawn from arm 1 is arm 1's tree.
        #expect(
            Set(sampled.items.compactMap(\.speciesID)).count == 2,
            "both arms' species should be represented: \(sampled.items.map(\.speciesID))"
        )

        // And the un-gridded path over the same box still answers for both inventories.
        let whole = try await store.queue.read { connection in
            try queries.pins(in: MapViewport(bounds: bounds, zoom: 18), connection: connection)
        }
        #expect(whole.items.count == 4, "the union drew \(whole.items.count) pins for four trees")
    }

    // MARK: - The attach cap (RULING D5)

    /// The limit is **asked of SQLite**, never written down. This asserts it is a real, usable
    /// answer rather than a plausible constant — the number reaches a reader as a sentence.
    @Test("the attach limit is read from the library and leaves room for cities")
    func theAttachLimitIsReadFromSQLite() async throws {
        let dir = try Self.tempDir()
        let bundleURL = dir.appendingPathComponent("bundle.sqlite")
        try Self.seed(
            at: bundleURL,
            trees: [TreeRow(id: 1, idSpace: "sf", lat: 37.7, lon: -122.4, speciesID: 1)],
            species: [Self.plane]
        )
        let store = try await Self.store([Self.file(bundleURL, bundled: true)])
        #expect(
            store.attachedDatabaseLimit >= 2,
            "SQLITE_LIMIT_ATTACHED is \(store.attachedDatabaseLimit); the bundle alone fills it"
        )
        // The shipping catalog is the bundle plus seven packs. If this ever fails, the cap copy
        // is doing real work and the number in `docs/` has moved.
        #expect(
            store.attachedDatabaseLimit >= 8,
            "this platform's SQLite attaches at most \(store.attachedDatabaseLimit) databases"
        )
    }

    /// At the cap, the `Download` button is **replaced by a sentence that names the remedy** — and
    /// an update is not withheld, because replacing a city's file uses the slot it already holds.
    @Test("at the attach cap a new city loses its button and an update keeps its own")
    func theCapReplacesDownloadButNotUpdate() throws {
        let city = CityManifest.City(
            id: "us-ny-nyc-queens", displayName: "Queens", coverage: "full", treeCount: 1,
            schemaVersion: 17, version: "s17-r2026-08-22-aaaaaaaa", contentRev: "2026-08-22",
            path: "x", bytes: 81_000_000, sha256: String(repeating: "a", count: 64)
        )

        let blocked = CityDownloadRow.published(
            city: city, state: .notInstalled, hasInstallHeadroom: false,
            downloadingFraction: nil, lastAttemptFailed: false
        )
        #expect(!blocked.affordances.contains(.download))
        #expect(blocked.affordances.isEmpty)
        #expect(blocked.detailLine == "Remove a city to download another.")

        let permitted = CityDownloadRow.published(
            city: city, state: .notInstalled, hasInstallHeadroom: true,
            downloadingFraction: nil, lastAttemptFailed: false
        )
        #expect(permitted.affordances == [.download])
        #expect(permitted.detailLine == nil)

        // An update replaces the file in a slot this city already occupies, so the cap does not
        // reach it. A reader at the cap can still take a newer record for everything they hold.
        let updatable = CityDownloadRow.published(
            city: city, state: .updateAvailable(installedVersion: "s17-r2026-08-01-bbbbbbbb"),
            hasInstallHeadroom: false, downloadingFraction: nil, lastAttemptFailed: false
        )
        #expect(updatable.affordances == [.update, .remove])
        #expect(updatable.detailLine == nil)
    }

    // MARK: - Rendering a content_rev (RULING D10)

    /// **The counter suffix comes off in copy, and nothing else does.**
    ///
    /// The live catalog carries `2026-08-22.02` on all seven packs since the republish, so the
    /// first case is the shipping one rather than a hypothetical.
    @Test("a record date renders without its publisher counter, and only when it is one")
    func recordDateStripsOnlyTheCounter() {
        #expect(CityDownloadsCopy.recordDate("2026-08-22.02") == "2026-08-22")
        #expect(CityDownloadsCopy.recordDate("2026-08-22.2") == "2026-08-22")
        #expect(CityDownloadsCopy.recordDate("2026-08-22") == "2026-08-22")

        // **Anything it does not recognize survives whole.** Inventing a date out of a string this
        // does not understand is the direction that puts a wrong day on screen.
        #expect(CityDownloadsCopy.recordDate("2026-08-22.beta") == "2026-08-22.beta")
        #expect(CityDownloadsCopy.recordDate("2026-08-22.02.1") == "2026-08-22.02.1")
        #expect(CityDownloadsCopy.recordDate("snapshot.7") == "snapshot.7")
        #expect(CityDownloadsCopy.recordDate("") == "")

        // The sentences it lands in.
        #expect(
            CityDownloadsCopy.bundledLine(contentRev: "2026-08-22.02")
                == "Included in the app · record as of 2026-08-22"
        )
        #expect(
            CityDownloadsCopy.bundledUpdatedLine(contentRev: "2026-08-22.02")
                == "Updated · record as of 2026-08-22"
        )
    }

    /// **The comparison keeps the whole string**, which is the other half of D10 and the half a
    /// careless implementation breaks: strip the counter before comparing and a same-day republish
    /// stops being detectable at all.
    @Test("update detection compares the full opaque rev, counter and all")
    func updateDetectionKeepsTheWholeRev() {
        func entry(_ rev: String) -> CityManifest.City {
            CityManifest.City(
                id: "sf", displayName: "San Francisco", coverage: "full", treeCount: 1,
                schemaVersion: 17, version: "s17-r\(rev)-aaaaaaaa", contentRev: rev,
                path: "x", bytes: 1, sha256: String(repeating: "a", count: 64)
            )
        }
        let bundled = SeedCities.City(
            id: "sf", displayName: "San Francisco", contentRev: "2026-08-22"
        )

        // A same-day republish IS a newer record. Trimmed to the date first, these compare equal
        // and the update is never offered.
        let republished = CityInstallState(
            published: entry("2026-08-22.02"), installedVersion: nil,
            bundled: bundled, newestKnownSchemaVersion: 17
        )
        #expect(republished == .bundledOutdated(bundledContentRev: "2026-08-22"))
        #expect(republished.allowsDownload, "a same-day republish was not detected as newer")

        // And the same rev is not newer than itself.
        let level = CityInstallState(
            published: entry("2026-08-22"), installedVersion: nil,
            bundled: bundled, newestKnownSchemaVersion: 17
        )
        #expect(level == .bundled(contentRev: "2026-08-22"))
        #expect(!level.allowsDownload)
    }

    // MARK: - Where the map opens (RULING D3)

    /// With only the bundle attached there is no third clause to apply, and the map opens exactly
    /// where it always did.
    @Test("the opening center is nil with only the bundle, and the largest pack's otherwise")
    func openingCenterFollowsTheLargestDownloadedInventory() async throws {
        let dir = try Self.tempDir()
        let bundleURL = dir.appendingPathComponent("bundle.sqlite")
        let small = dir.appendingPathComponent("small.sqlite")
        let large = dir.appendingPathComponent("large.sqlite")

        try Self.seed(
            at: bundleURL,
            trees: (1...3).map {
                TreeRow(id: Int64($0), idSpace: "sf", lat: 37.7, lon: -122.4, speciesID: 1)
            },
            species: [Self.plane]
        )
        try Self.seed(
            at: small,
            trees: [TreeRow(id: 1, idSpace: "us-ma-bos", lat: 42.36, lon: -71.06, speciesID: 1)],
            species: [Self.plane]
        )
        try Self.seed(
            at: large,
            trees: (1...4).map {
                TreeRow(id: Int64($0), idSpace: "us-ny-nyc", lat: 40.75, lon: -73.98, speciesID: 1)
            },
            species: [Self.plane]
        )

        let bundleOnly = try await Self.store([Self.file(bundleURL, bundled: true)])
        #expect(
            bundleOnly.inventory?.openingCenter == nil,
            "a bundle-only launch computed an opening center; it must degrade to the default"
        )

        let withPacks = try await Self.store([
            Self.file(bundleURL, bundled: true),
            Self.file(small, id: "boston"),
            Self.file(large, id: "manhattan")
        ])
        let center = try #require(withPacks.inventory?.openingCenter)
        // The larger pack wins, and the bundle — larger than Boston, smaller than New York — is
        // never a candidate, because `MapLayout.defaultCenter` is already its answer.
        #expect(abs(center.latitude - 40.75) < 0.01, "opened at \(center), not on the larger pack")
        #expect(abs(center.longitude - -73.98) < 0.01, "opened at \(center)")

        // And the region built from it is centered there rather than on San Francisco.
        let region = MapOpening.openingRegion(remembered: nil, downloadedCityCenter: center)
        #expect(abs(region.center.latitude - 40.75) < 0.01)
        // A remembered camera still wins over it — D3's second clause outranks the third.
        let remembered = MapCameraMemory.Snapshot(
            center: Coordinate(latitude: 1, longitude: 2),
            latitudeSpan: 0.01, longitudeSpan: 0.01
        )
        let kept = MapOpening.openingRegion(
            remembered: remembered, downloadedCityCenter: center
        )
        #expect(abs(kept.center.latitude - 1) < 0.000_1, "the remembered camera lost to a fallback")
    }

    // MARK: - The screen's shape (RULING D2)

    /// **The built-in card opens `On this phone`, its own cities are drawn INSIDE it, and the
    /// downloaded packs follow as their own cards.**
    ///
    /// A bundled city is never a peer card beside the built-in inventory, and the built-in card and
    /// a per-city entry may never contradict each other — which the old screen did by drawing
    /// `In use` above a sibling `Use`.
    ///
    /// ── What this test asserted before, and why that was worthless ──────────────────────────────
    /// It asserted that the bundled cities sat in their own section with `isCityGroup == true` and
    /// an empty title. Both were true, and **together they were exactly what guaranteed the screen
    /// drew nothing differently**: `isCityGroup` reached `CityDownloadsView` through a single
    /// `.padding(.top, …)` on the section heading, and that modifier sits inside
    /// `if !section.title.isEmpty`. An empty title meant the flag was never read. The screen drew
    /// three cards of identical width, inset and spacing in one column, and this test was green.
    ///
    /// It now asserts `cards`, which is the arrangement the view draws from and its only source of
    /// cards — there is no path by which a row can be contained here and beside the card on screen.
    /// The remaining half, that a card's boundary really encloses the entry's pixels, is not
    /// something a value can answer and is checked on the device by
    /// `CypressUITests/CityCardContainmentUITests`.
    @Test("bundled cities are drawn inside the built-in card, and downloaded packs are not")
    func bundledCitiesNestUnderTheBuiltInCard() {
        let sanFrancisco = SeedCities.City(
            id: "sf", displayName: "San Francisco", contentRev: "2026-07-31"
        )
        let manhattan = CityManifest.City(
            id: "us-ny-nyc-manhattan", displayName: "Manhattan", coverage: "full", treeCount: 1,
            schemaVersion: 17, version: "s17-r2026-08-22-aaaaaaaa", contentRev: "2026-08-22",
            path: "x", bytes: 1, sha256: String(repeating: "a", count: 64)
        )
        let sfEntry = CityManifest.City(
            id: "sf", displayName: "San Francisco", coverage: "full", treeCount: 1,
            schemaVersion: 17, version: "s17-r2026-07-31-aaaaaaaa", contentRev: "2026-07-31",
            path: "x", bytes: 1, sha256: String(repeating: "a", count: 64)
        )

        let rows: [CityDownloadRow] = [
            .builtIn(cityNames: ["San Francisco", "San Jose"]),
            .published(
                city: sfEntry,
                state: CityInstallState(
                    published: sfEntry, installedVersion: nil, bundled: sanFrancisco,
                    newestKnownSchemaVersion: 17
                ),
                downloadingFraction: nil, lastAttemptFailed: false
            ),
            .published(
                city: manhattan,
                state: .installedCurrent(installedVersion: manhattan.version),
                downloadingFraction: nil, lastAttemptFailed: false
            )
        ]
        let sections = CityDownloadSection.sections(from: rows) { _ in nil }

        // Every card the screen draws, with what each one contains — compared as one shape rather
        // than subscripted, so a break that shortens the list fails rather than crashing the
        // process and taking the tests scheduled behind it down with it.
        let cards = sections.flatMap(\.cards)
        #expect(
            cards.map { ($0.row.id, $0.contained.map(\.id)) }.map(String.init(describing:))
                == [
                    // One card for the built-in inventory, with San Francisco inside it.
                    (CityDownloadRow.builtInID, ["sf"]),
                    // The downloaded pack is a card of its own and contains nothing.
                    ("us-ny-nyc-manhattan", [] as [String])
                ].map(String.init(describing:)),
            "the screen draws \(cards.map { ($0.row.id, $0.contained.map(\.id)) })"
        )
        #expect(sections.first?.title == "On this phone")

        // **A bundled city is not a card**, which is the arrangement decision 3 forbids stated as
        // the thing it forbids. Asserted over the cards rather than over a flag, because a card is
        // what a peer *is*.
        #expect(
            !cards.contains { $0.row.id == "sf" },
            "San Francisco is drawn as a card of its own beside the built-in inventory"
        )

        // **Decision 5, as a property of the whole screen**: no card may claim a state another card
        // contradicts. With `Use`/`In use` gone there is nothing left that could, and the built-in
        // card draws nothing at all.
        let everyRow = sections.flatMap(\.rows)
        #expect(everyRow.count == 3, "sectioning dropped or duplicated a row: \(everyRow.map(\.id))")
        let builtIn = everyRow.first { $0.id == CityDownloadRow.builtInID }
        #expect(builtIn?.affordances.isEmpty == true)
    }

    // MARK: - Lifecycle (RULING D8)

    /// **Removing an inventory tears the union down and rebuilds it**, and the rebuilt union
    /// answers for the file set it was given rather than for the one before it.
    ///
    /// The app does this by re-booting `DataLayer` whole (`AppModel.reboot`); this asserts the
    /// property that makes the reboot correct.
    ///
    /// **What it deliberately does NOT claim is anything about the statement cache.** An earlier
    /// version of this comment said the statements compiled against the old views "do not
    /// survive", and its red-proof — removing `clearStatementCache()` from the teardown — stayed
    /// green. So did a second one that removed the clear from `SQLiteConnection.detach` as well.
    /// SQLite re-prepares a cached statement when the schema changes under it, and it does not
    /// refuse a `DETACH` for a statement that is merely prepared. The clear is defensive and this
    /// test does not pretend to demonstrate a need for it — see `InventoryUnion.tearDownEverything`,
    /// where both withdrawn justifications are recorded.
    @Test("a rebuilt union answers for the new file set, with no stale statement")
    func rebuildingTheUnionDropsEverythingBehindIt() async throws {
        let dir = try Self.tempDir()
        let bundleURL = dir.appendingPathComponent("bundle.sqlite")
        let packURL = dir.appendingPathComponent("pack.sqlite")
        try Self.seed(
            at: bundleURL,
            trees: [TreeRow(id: 1, idSpace: "sf", lat: 37.7, lon: -122.4, speciesID: 1)],
            species: [Self.plane]
        )
        try Self.seed(
            at: packURL,
            trees: (1...2).map {
                TreeRow(id: Int64($0), idSpace: "us-ny-nyc", lat: 40.7, lon: -74.0, speciesID: 1)
            },
            species: [Self.plane]
        )

        let store = try await CypressStore.inMemory(inventories: [
            Self.file(bundleURL, bundled: true), Self.file(packURL, id: "manhattan")
        ])
        let n7 = try await Self.count(store, "SELECT COUNT(*) AS n FROM temp.trees")
        #expect(n7 == 3)

        // Warm the statement cache against the two-arm views, exactly as a screen would.
        _ = try await Self.count(store, "SELECT COUNT(*) AS n FROM temp.trees WHERE inv = 1")

        try await store.queue.withConnection { connection in
            let union = try #require(store.inventory)
            try InventoryUnion.tearDown(union, on: connection)
            _ = try InventoryUnion.build([Self.file(bundleURL, bundled: true)], on: connection)
        }

        let afterRebuild = try await Self.count(store, "SELECT COUNT(*) AS n FROM temp.trees")
        #expect(afterRebuild == 1, "the rebuilt union still answers for the removed file")
        let armOne = try await Self.count(
            store, "SELECT COUNT(*) AS n FROM temp.trees WHERE inv = 1"
        )
        #expect(armOne == 0, "the rebuilt union still returns rows for the detached file")
    }

    /// **Teardown leaves `temp` empty, so the next build on this connection has room.**
    ///
    /// The union used to drop a hand-written list of table names, and the list was missing
    /// `dim_region` — which is in **every** published pack, all seven of them s17. Nothing noticed,
    /// because the app makes a new connection per boot and a new connection's `temp` is empty
    /// anyway; the leak only bites a caller that tears down and builds again on one connection,
    /// which is what `SeedDatabase.detach` is for and what a removal between reads is.
    ///
    /// **The fixture has to be the shape the defect lived in.** A first version of this probe used
    /// the default s16-shaped fixture, rebuilt bundle-only, and passed — with the defect present.
    /// Both halves of that were wrong: no arm carried `dim_region`, so nothing leaked, and a
    /// bundle-only rebuild never reaches `mirrorFirstWins` at all. The arm below is a published
    /// pack's shape and the rebuild carries it too.
    ///
    /// The first assertion is the calibration: `dim_region` is *there* before the teardown. Without
    /// it, "temp is empty afterwards" is equally true of a union that never created it.
    @Test("tearing down leaves temp empty for the next build on the same connection")
    func tearingDownLeavesTempEmptyForTheNextBuild() async throws {
        let dir = try Self.tempDir()
        let bundleURL = dir.appendingPathComponent("bundle.sqlite")
        let packURL = dir.appendingPathComponent("pack.sqlite")
        try Self.seed(
            at: bundleURL,
            trees: [TreeRow(id: 1, idSpace: "sf", lat: 37.7, lon: -122.4, speciesID: 1)],
            species: [Self.plane]
        )
        try Self.seed(
            at: packURL,
            trees: (1...2).map {
                TreeRow(id: Int64($0), idSpace: "us-ny-nyc", lat: 40.7, lon: -74.0, speciesID: 1)
            },
            species: [Self.plane],
            packID: "us-ny-nyc-manhattan"
        )

        let files = [Self.file(bundleURL, bundled: true), Self.file(packURL, id: "manhattan")]
        let store = try await CypressStore.inMemory(inventories: files)

        try await store.queue.withConnection { connection in
            // Calibration. If this is empty the rest of the test is asserting nothing.
            let before = try InventoryUnion.ownObjects(
                in: SeedDatabase.schemaName, on: connection
            ).map(\.name)
            #expect(
                before.contains("dim_region"),
                """
                the fixture never built temp.dim_region, so this test cannot see the leak it is \
                about; temp holds \(before)
                """
            )

            let union = try #require(store.inventory)
            try InventoryUnion.tearDown(union, on: connection)

            let after = try InventoryUnion.ownObjects(in: SeedDatabase.schemaName, on: connection)
            #expect(
                after.isEmpty,
                """
                the teardown left \(after.map(\.name)) behind in temp; the next build on this \
                connection collides with them
                """
            )

            // The failure this actually causes, asserted as itself rather than inferred from the
            // list above: building again over the same pack must not throw.
            _ = try InventoryUnion.build(files, on: connection)
        }

        let rebuilt = try await Self.count(store, "SELECT COUNT(*) AS n FROM temp.trees")
        #expect(rebuilt == 3, "the rebuilt union does not answer for both files")
    }

    /// A file this build cannot read is **skipped, not fatal**: the rest of the union opens.
    @Test("an unreadable inventory is refused without taking the launch with it")
    func aBadInventoryIsSkipped() async throws {
        let dir = try Self.tempDir()
        let bundleURL = dir.appendingPathComponent("bundle.sqlite")
        let junk = dir.appendingPathComponent("junk.sqlite")
        try Self.seed(
            at: bundleURL,
            trees: [TreeRow(id: 1, idSpace: "sf", lat: 37.7, lon: -122.4, speciesID: 1)],
            species: [Self.plane]
        )
        try Data("not a database".utf8).write(to: junk)

        let store = try await Self.store([
            Self.file(bundleURL, bundled: true), Self.file(junk, id: "junk")
        ])
        let union = try #require(store.inventory)
        #expect(union.arms.map(\.id) == [InventoryFile.bundledID])
        #expect(union.refused.map(\.id) == ["junk"])
        let n8 = try await Self.count(store, "SELECT COUNT(*) AS n FROM temp.trees")
        #expect(n8 == 1)
    }
}
