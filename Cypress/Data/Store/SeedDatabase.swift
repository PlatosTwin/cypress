import Foundation

/// The bundled, read-only SF inventory, and how it relates to the app's writable database.
///
/// # Decision: ATTACH the seed read-only. Do not copy it out on first launch.
///
/// The two candidate designs were:
///
/// **(a) Copy on first launch.** Copy `cypress-seed.sqlite` from the app bundle into Application
/// Support, then open that one file read-write and write contributions into it directly.
///
/// **(b) ATTACH.** Open a small writable database in Application Support as `main`, and
/// `ATTACH` the bundle's copy read-only as `seed`. Contributions go to `main`; the inventory is
/// read from `seed`; queries join across the two.
///
/// We implement **(b)**, for four reasons, in descending order of weight:
///
/// 1. **First launch cost.** The seed is ~92 MB. A copy is 92 MB of file I/O before the map can
///    render a single pin — on an older device with a nearly full disk that is several seconds of
///    a blank first-run screen, and it is the first thing a new user sees. ATTACH costs one `open`
///    and one `ATTACH`, both sub-millisecond.
/// 2. **Disk.** The bundle copy is not removable; iOS keeps it for the life of the install. Copying
///    means carrying ~184 MB instead of ~92 MB, permanently, on a device where the user did not
///    ask for a second copy of the same immutable data.
/// 3. **Upgrades.** Shipping a refreshed inventory is a new bundle resource and nothing else. With
///    (a), every app update that refreshes the seed has to re-copy 92 MB *and* merge it with the
///    user's contributions already living in the same file — a real migration, written by hand,
///    against the one file the user cannot afford to lose. With (b) the inventory is swapped and
///    the contributions are untouched, because they were never in the same file.
/// 4. **Blast radius.** The seed is genuinely immutable. Opening it `mode=ro&immutable=1` makes
///    that a property of the connection rather than a promise in a comment, and no bug in a DAO can
///    corrupt the city inventory.
///
/// **What (b) costs, stated plainly.** SQLite cannot declare a `REFERENCES` across an attached
/// database, so contribution rows carry `tree_uuid TEXT` and referential integrity against the
/// inventory is `LocalAPI`'s job rather than the engine's (see `AppSchema`). A transaction spanning
/// both databases is not the atomic multi-database commit SQLite would give two writable files —
/// but that case cannot arise here, because `seed` is never written. There is no other cost: the
/// query planner uses `seed`'s own indexes normally, and cross-database joins resolve exactly as
/// same-database ones do.
///
/// **`immutable=1` specifically.** It tells SQLite the file cannot change under it, so no locking,
/// no `-wal`/`-shm` sidecar files, and no attempt to create either. That last part matters: the app
/// bundle directory is not writable, and without `immutable=1` a plain read-only open still wants
/// to create a shared-memory file next to the database when the file's journal mode says WAL.
public enum SeedDatabase {
    /// The attached schema name. All inventory SQL is qualified with it.
    public static let schemaName = "seed"

    /// The resource name of the bundled seed, without extension.
    public static let resourceName = "cypress-seed"
    public static let resourceExtension = "sqlite"

    /// The newest seed schema generation this build was written against — R37.1's numbering
    /// (E176's "v14 pass" introduced `id_space`), the same integer `Tools/publish_cities.py`
    /// stamps as `SEED_SCHEMA_VERSION` and the manifest carries as `schema_version`. Bump it in
    /// the same change that teaches this layer a new generation's shape.
    ///
    /// A published city file with a newer generation is refused — never downloaded
    /// (`CityInstallState.needsNewerApp`) and never attached (`CityLibrary`'s validation).
    ///
    /// **15** is the pass that added `species_trigrams` (ERRATA E165). It is a pure addition:
    /// every s14 file already in the wild still opens, still attaches and still searches, because
    /// the search reads `SeedSchema.hasSpeciesTrigrams` and falls back to the substring match s14
    /// shipped with. The bump is what lets a *later* build tell the two apart without guessing.
    public static let newestKnownSchemaVersion = 15

    // MARK: - Locating

    public enum LocationError: Error, CustomStringConvertible {
        case notFoundInBundle(Bundle)
        case notFoundAtPath(URL)

        public var description: String {
            switch self {
            case let .notFoundInBundle(bundle):
                return """
                \(resourceName).\(resourceExtension) is not in \(bundle.bundleURL.lastPathComponent). \
                The seed is produced by Tools/build_seed.py into Fixtures/seed/ and must be added to \
                the app's Resources to ship.
                """
            case let .notFoundAtPath(url):
                return "no seed database at \(url.path)"
            }
        }
    }

    /// Finds the seed in a bundle. Returns `nil` rather than throwing so a caller can decide
    /// whether a missing inventory is fatal (it is, for the map) or merely empty (it is, for a
    /// unit test that only exercises the outbox).
    public static func urlInBundle(_ bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: resourceName, withExtension: resourceExtension)
    }

    /// The `file:` URI used to attach, with the read-only and immutable flags.
    ///
    /// `absoluteString` on a file URL is already percent-encoded, which is what SQLite's URI parser
    /// expects; a bundle path containing a space would otherwise truncate the filename.
    public static func readOnlyURI(for url: URL) -> String {
        url.absoluteString + "?mode=ro&immutable=1"
    }

    // MARK: - Attaching

    /// Attaches `url` as `seed` and returns the shape it turned out to have.
    ///
    /// `ATTACH` cannot run inside a transaction, which is why this takes a bare connection rather
    /// than going through `DatabaseQueue.write`.
    @discardableResult
    public static func attach(_ url: URL, to connection: SQLiteConnection) throws -> SeedSchema {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LocationError.notFoundAtPath(url)
        }
        try connection.attach(uri: readOnlyURI(for: url), as: schemaName)
        return try SeedSchema.introspect(connection, schema: schemaName)
    }

    public static func detach(from connection: SQLiteConnection) throws {
        try connection.detach(schemaName)
    }
}

/// The shape of the seed as it actually is on disk, read at open time.
///
/// The seed's identity model changed once already during development: `trees.id` was a TEXT uuid
/// primary key, and became `id INTEGER PRIMARY KEY` (an internal join key) plus
/// `uuid TEXT NOT NULL UNIQUE` (the stable external identity), to save roughly 90 MB. Rather than
/// hard-code the winner and break when a rebuild lands, the read layer asks the file which shape it
/// has and names its columns accordingly. Three cheap `PRAGMA table_info` reads at open time buy
/// immunity to that whole class of breakage.
///
/// This is not open-ended flexibility: exactly two shapes are recognized, and anything else fails
/// the seed contract test.
public struct SeedSchema: Equatable, Sendable {
    /// The column on `seed.trees` holding the stable, citable UUID — `uuid` in the current shape,
    /// `id` in the original TEXT-PK shape.
    public let treeIdentityColumn: String
    /// Same, for `seed.species`.
    public let speciesIdentityColumn: String
    /// The column on `seed.trees` that `seed.trees_rtree.id` equals — `id` in the current shape
    /// (an INTEGER PRIMARY KEY is a rowid alias and is stable across VACUUM), `rt_id` in the
    /// original shape, where the TEXT primary key made the implicit rowid unstable.
    public let rtreeJoinColumn: String
    /// Whether `trees.city_raw` is present. It is NULL in the shipped seed — the passthrough costs
    /// ~74 MB and is regenerable — so nothing in this layer reads it; the flag exists so the
    /// contract test can pin its presence rather than its content.
    public let hasCityRaw: Bool
    /// Whether `trees.inventory_source` is present — which of San Francisco's two street-tree
    /// inventories listed each row.
    ///
    /// It is a per-row column because the shipped seed is built from both: the living trees are SF
    /// Public Works' operational layer, and the vacant planting sites are the DataSF export, which
    /// is the only one of the two that has a vacant-site category at all. A seed built before #91's
    /// second round has no such column and every row in it came from one inventory, so the flag
    /// exists to let the read layer fall back to the seed-wide answer rather than fail.
    public let hasInventorySource: Bool
    /// Whether `trees.id_space` and the `id_spaces` / `inventories` tables are present — the v14
    /// seed pass (#129, ERRATA E176), which is what made a second city representable at all.
    ///
    /// Before it, `external_ref` was `INTEGER UNIQUE`: a global constraint on a source-local id, so
    /// San Jose FACILITYID 3 could not be a row beside San Francisco TreeID 3. After it, identity is
    /// unique over `(id_space, external_ref)` and the id space is a column rather than something a
    /// reader has to parse out of a qualified string.
    ///
    /// A seed built before that pass is still readable and still correct: every row in it is in one
    /// id space, and `seed_meta.identity_prefix` is the right answer for all of them. This flag is
    /// what lets the read layer and the contract test tell the two files apart rather than assume.
    public let hasIdSpace: Bool
    /// Whether `species_trigrams` is present — the v15 seed pass (ERRATA E165), the similarity
    /// index that lets the species search survive a typo or a name the catalog spells differently.
    ///
    /// A seed or city file built before that pass is still readable and still correct: the search
    /// simply runs the substring match E165 shipped and finds what it always found. This is the
    /// same shape as `hasIdSpace` above and exists for the same reason — the read layer asks the
    /// file what it carries rather than trusting a version integer stamped somewhere else. That
    /// matters more here than for the other flags, because the bundled seed and a downloaded city
    /// file are two different generations at the same time (R37.3): the app can be reading an s15
    /// bundle and an s14 San Jose in one session.
    public let hasSpeciesTrigrams: Bool
    /// Whether the identity model is the current INTEGER-PK one.
    public var usesIntegerPrimaryKeys: Bool { treeIdentityColumn == "uuid" }

    public enum ContractError: Error, CustomStringConvertible {
        case missingTable(String)
        case unrecognizedShape(columns: [String])

        public var description: String {
            switch self {
            case let .missingTable(name):
                return "the attached seed has no table '\(name)'; it is not a Cypress seed database"
            case let .unrecognizedShape(columns):
                return "seed.trees has columns \(columns), which match neither known identity model"
            }
        }
    }

    public static func introspect(_ connection: SQLiteConnection, schema: String) throws -> SeedSchema {
        for table in ["trees", "species", "neighborhoods", "trees_rtree"] {
            guard try connection.tableExists(table, in: schema) else {
                throw ContractError.missingTable(table)
            }
        }

        let treeColumns = try connection.columnNames(ofTable: "trees", in: schema)
        let speciesColumns = try connection.columnNames(ofTable: "species", in: schema)

        // `lat` and `lon` are the load-bearing columns for every spatial query and are the same in
        // both shapes; their absence means this is not a Cypress seed at all.
        guard treeColumns.contains("lat"), treeColumns.contains("lon"), treeColumns.contains("status") else {
            throw ContractError.unrecognizedShape(columns: treeColumns)
        }

        return SeedSchema(
            treeIdentityColumn: treeColumns.contains("uuid") ? "uuid" : "id",
            speciesIdentityColumn: speciesColumns.contains("uuid") ? "uuid" : "id",
            rtreeJoinColumn: treeColumns.contains("rt_id") ? "rt_id" : "id",
            hasCityRaw: treeColumns.contains("city_raw"),
            hasInventorySource: treeColumns.contains("inventory_source"),
            // All three together or none: the column and the two tables it and
            // `inventory_source` point at are one migration and are meaningless apart.
            hasIdSpace: try treeColumns.contains("id_space")
                && connection.tableExists("id_spaces", in: schema)
                && connection.tableExists("inventories", in: schema),
            hasSpeciesTrigrams: try connection.tableExists("species_trigrams", in: schema)
        )
    }
}
