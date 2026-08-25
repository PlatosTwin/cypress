import Foundation

/// Several read-only inventory files, attached at once and presented to the query layer as one
/// inventory.
///
/// # Why a TEMP view and not a schema
///
/// SQLite refuses a view that references an attached database from anywhere except `temp`:
/// creating one in an attached in-memory schema is answered `view trees cannot reference objects
/// in database inv0`. So the union lives in `temp`, `SeedDatabase.schemaName` is `temp`, and every
/// `\(seed).trees` in the query layer keeps the text it always had.
///
/// # What is attached
///
/// One schema per file — `inv0`, `inv1`, … — with the bundled seed always at ordinal **0**. That
/// is not cosmetic: a tree's union-wide id is `ordinal * armStride + <the file's own id>`, so
/// ordinal 0 leaves every bundled tree's id exactly what it was before this type existed.
///
/// # The three things the union has to reconcile, and how
///
/// **Geometry** is re-keyed. `trees.id` is a rowid alias local to each file, so the union carries
/// `inv`, `local_id` and a composite `id`. Nothing may look a tree up by the composite id — see
/// `armStride`.
///
/// **Species** are re-keyed too, and they are the harder half. `species.uuid` is `uuid5` of a
/// scientific name and is stable across files; `species.id` is an integer assigned in
/// first-encounter order while `Tools/build_seed.py` streams its sources, so two builds over
/// different city sets number the same species differently. A literal union would let one file's
/// `species_current = 24` join another file's row 24 and put the wrong name on the tree. The
/// answer is a canonical catalogue materialized at open, keyed by uuid, plus a per-arm translation
/// table — see `canonicalSpeciesSQL`. Every existing `JOIN species s ON s.id = t.species_current`
/// and `GROUP BY s.id` then keeps working unchanged, which is why this shape was chosen over
/// re-keying fifteen join sites to uuid.
///
/// **Neighborhoods** are re-keyed and deliberately **not** de-duplicated. `neighborhoods.name` is
/// unique within a file, but two cities may both have a `Downtown`, and they are not the same
/// place. Species are shared authored content and merge; neighborhoods are city data and do not.
///
/// # What it costs, measured
///
/// The whole-of-San-Francisco cluster query at 64 pt cells, against the bundle plus a San
/// Francisco pack (sqlite3 3.51.0, macOS, warm):
///
/// | arrangement | time |
/// |---|---|
/// | the bundle alone, straight at the table | 58–60 ms |
/// | the union through `trees_geo`, shadowed by rowid range | 72–81 ms |
/// | the union through `trees_geo`, shadowed by `id_space` | 162 ms |
/// | the union through the full `trees` view | ~100 ms |
///
/// **A view's width is paid per row.** SQLite materializes a compound view as a co-routine and does
/// not prune result columns the outer query never reads, so a view carrying `species_current` loses
/// `COVERING INDEX idx_trees_lat_lon` and probes the table once per candidate. That is the whole
/// reason `trees_geo` exists beside `trees` and carries exactly the columns that index covers.
public struct InventoryUnion: Sendable, Equatable {

    // MARK: - Identity arithmetic

    /// The multiplier that separates one arm's ids from the next: 2^40.
    ///
    /// The largest published inventory holds about 1.1 million trees, so an arm's own ids are
    /// nowhere near this; the room is deliberate. `Int64` holds 2^63, which leaves space for
    /// 8,388,608 arms, and the attach limit is ten.
    ///
    /// **Nothing may look a tree up by the composite id.** `WHERE id IN (…)` against the union
    /// spells `WHERE ordinal * armStride + t.id IN (…)` inside each arm, which is not sargable and
    /// measures as `SCAN t` — a table scan per arm on the map's critical path. Hydration goes by
    /// `(inv, local_id)`, which measures as `SEARCH t USING INTEGER PRIMARY KEY (rowid=?)`.
    /// `TreeQueries.pins(rowIDs:connection:)` is the caller that has to honour this.
    public static let armStride: Int64 = 1 << 40

    public static func composedID(ordinal: Int, localID: Int64) -> Int64 {
        Int64(ordinal) * armStride + localID
    }

    /// Splits a composite id back into the arm that owns it and that arm's own row id.
    public static func decomposedID(_ id: Int64) -> (ordinal: Int, localID: Int64) {
        (ordinal: Int(id / armStride), localID: id % armStride)
    }

    // MARK: - The built union

    /// Every arm, in ordinal order. The bundled seed, when present, is `arms[0]`.
    public let arms: [InventoryArm]
    /// The shape of the **view**, which is what the query layer introspects. Uniform by
    /// construction: the view normalizes every generation's columns to one projection, so this is
    /// always the current identity model whatever the files on disk carry.
    public let schema: SeedSchema
    /// Whether any arm holds a soft-deleted tree. `trees_geo` filters them out inside the arms that
    /// have them, so the map queries no longer carry the predicate; `trees` still exposes the
    /// column, and `pins(rowIDs:)` still applies it.
    public let hasSoftDeletedTrees: Bool
    /// **Where the map should open when it has nothing better to go on** (RULING D3), or nil when
    /// the only inventory is the bundled one.
    ///
    /// D3's order is: a location fix inside any live inventory wins; failing that, the camera this
    /// install was last left on; failing that, the largest downloaded inventory. This is the third
    /// clause, and it is the only one the union had to supply — the first two are
    /// `MapOpening.openingRegion`'s existing behaviour and are unchanged by this round.
    ///
    /// **Nil is the whole of "degrades to today's behaviour".** With no downloaded city there is no
    /// third clause to apply, `MapLayout.defaultCenter` answers exactly as it always has, and a
    /// launch in the shipping configuration pays nothing to compute this.
    ///
    /// The centre is the mean of that arm's own coordinates — measured at 41 ms over 145,837 rows,
    /// once, at open, off the main thread. A mean rather than the densest cell: the cell would be a
    /// better answer and costs a grouped scan of the whole arm, and what this decides is where a
    /// reader who downloaded Manhattan and has never opened the map lands. The middle of Manhattan
    /// is good enough for that, and San Francisco is not.
    public let openingCenter: Coordinate?

    /// Files the caller offered that could not be attached, with the reason. A bad pack is skipped
    /// rather than fatal: launching without one downloaded city beats not launching, which is the
    /// same posture the boot path has always taken for an unreadable choice.
    public let refused: [RefusedInventory]

    public struct RefusedInventory: Sendable, Equatable {
        public let id: String
        public let reason: String
    }

    // MARK: - Building

    /// Attaches every file, builds the canonical catalogues and creates the views.
    ///
    /// `files` is taken in the order given except that the bundled file is moved to ordinal 0.
    /// Attaching happens outside any transaction, which `ATTACH` requires.
    public static func build(
        _ files: [InventoryFile],
        on connection: SQLiteConnection
    ) throws -> InventoryUnion {
        let ordered = files.filter(\.isBundled) + files.filter { !$0.isBundled }

        var arms: [InventoryArm] = []
        var refused: [RefusedInventory] = []

        for file in ordered {
            let ordinal = arms.count
            let schemaName = "inv\(ordinal)"
            do {
                guard FileManager.default.fileExists(atPath: file.url.path) else {
                    throw SeedDatabase.LocationError.notFoundAtPath(file.url)
                }
                try connection.attach(
                    uri: SeedDatabase.readOnlyURI(for: file.url), as: schemaName
                )
                let schema = try SeedSchema.introspect(connection, schema: schemaName)
                arms.append(
                    InventoryArm(
                        id: file.id,
                        ordinal: ordinal,
                        schemaName: schemaName,
                        isBundled: file.isBundled,
                        schema: schema,
                        idSpaces: try idSpaces(in: schemaName, schema: schema, on: connection),
                        treeColumns: Set(
                            try connection.columnNames(ofTable: "trees", in: schemaName)
                        ),
                        rtreeColumns: Set(
                            try connection.columnNames(ofTable: "trees_rtree", in: schemaName)
                        ),
                        hasSoftDeletedTrees: try hasSoftDeletes(in: schemaName, on: connection),
                        shadowed: []
                    )
                )
            } catch {
                // The attach may or may not have landed before the introspection threw; detaching
                // an unattached schema is itself an error, so this asks rather than assumes.
                if (try? connection.attachedSchemas())?.contains(schemaName) == true {
                    try? connection.detach(schemaName)
                }
                refused.append(RefusedInventory(id: file.id, reason: "\(error)"))
            }
        }

        arms = try applyShadowing(to: arms, on: connection)
        try createCanonicalCatalogues(arms: arms, on: connection)
        try createViews(arms: arms, on: connection)

        let schema = try SeedSchema.introspect(connection, schema: SeedDatabase.schemaName)
        return InventoryUnion(
            arms: arms,
            schema: schema,
            hasSoftDeletedTrees: arms.contains(where: \.hasSoftDeletedTrees),
            openingCenter: try openingCenter(among: arms, on: connection),
            refused: refused
        )
    }

    /// Drops every view and table this type created and detaches every arm.
    ///
    /// **The statement cache is cleared defensively, and neither reason it is easy to give for it
    /// survived being checked.**
    ///
    /// Two claims were written here and both were measured and withdrawn. *"A statement compiled
    /// against a view that is about to stop existing is a stale handle"* — it is not: SQLite
    /// re-prepares a cached statement by itself when the schema changes under it, and a rebuilt
    /// union answers correctly with this line removed. *"A live prepared statement makes `DETACH`
    /// fail"* — not for a merely prepared one: with the clear removed here **and** from
    /// `SQLiteConnection.detach`, every arm still detached and the suite stayed green. SQLite
    /// refuses a `DETACH` for a statement that is mid-step, which a rebuild between reads is not.
    ///
    /// It is kept because it costs nothing at the one moment the whole layer is being replaced, and
    /// because it removes the class of question rather than leaving it to a reasoning step. What it
    /// must not carry is a justification nothing tests — the comment is the thing being corrected
    /// here, not the code.
    public static func tearDown(_ union: InventoryUnion, on connection: SQLiteConnection) throws {
        try tearDownEverything(on: connection)
    }

    /// The same teardown, derived from the connection rather than from a value the caller kept.
    ///
    /// Which schemas are attached is a fact the connection already holds, so asking it is both
    /// simpler and more robust than trusting a record of what was attached: a build that threw
    /// half-way leaves arms behind that no `InventoryUnion` value describes.
    public static func tearDownEverything(on connection: SQLiteConnection) throws {
        connection.clearStatementCache()
        for name in viewNames {
            try? connection.execute("DROP VIEW IF EXISTS \(SeedDatabase.schemaName).\(name)")
        }
        for name in materializedNames {
            try? connection.execute("DROP TABLE IF EXISTS \(SeedDatabase.schemaName).\(name)")
        }
        let attached = (try? connection.attachedSchemas()) ?? []
        for schema in attached where schema.hasPrefix("inv") {
            try? connection.detach(schema)
        }
    }

    /// The mean coordinate of the largest **downloaded** inventory (RULING D3's third clause).
    ///
    /// Only downloaded arms are candidates: the bundled one already has an answer, and it is
    /// `MapLayout.defaultCenter`. Ties break on the arm's ordinal, which is its id order, so two
    /// equally large packs give the same answer on every launch.
    private static func openingCenter(
        among arms: [InventoryArm],
        on connection: SQLiteConnection
    ) throws -> Coordinate? {
        let downloaded = arms.filter { !$0.isBundled }
        guard !downloaded.isEmpty else { return nil }

        var best: (arm: InventoryArm, count: Int64)?
        for arm in downloaded {
            let statement = try connection.prepare(
                "SELECT COUNT(*) AS n FROM \(arm.schemaName).trees"
            )
            defer { statement.finalize() }
            let count = try statement.fetchOne { try $0.int64("n") } ?? 0
            if count > (best?.count ?? -1) { best = (arm, count) }
        }
        guard let best, best.count > 0 else { return nil }

        let statement = try connection.prepare(
            "SELECT AVG(lat) AS lat, AVG(lon) AS lon FROM \(best.arm.schemaName).trees"
        )
        defer { statement.finalize() }
        return try statement.fetchOne { row in
            guard let lat = try row.doubleIfPresent("lat"), let lon = try row.doubleIfPresent("lon")
            else { return nil as Coordinate? }
            return Coordinate(latitude: lat, longitude: lon)
        } ?? nil
    }

    // MARK: - Shadowing (RULING D1)

    /// Marks the bundled arm's rows that a downloaded pack now covers.
    ///
    /// **Only the bundled arm is ever shadowed, and that is load-bearing.** The five New York
    /// borough packs *share* the id space `us-ny-nyc`, so a rule that let one pack shadow another
    /// at id-space granularity would delete Brooklyn from the map the moment Manhattan was
    /// installed. A pack shadows the bundle and nothing else.
    private static func applyShadowing(
        to arms: [InventoryArm],
        on connection: SQLiteConnection
    ) throws -> [InventoryArm] {
        guard let bundledIndex = arms.firstIndex(where: \.isBundled) else { return arms }
        let bundle = arms[bundledIndex]
        let covered = Set(arms.filter { !$0.isBundled }.flatMap(\.idSpaces))
        let toShadow = bundle.idSpaces.filter(covered.contains).sorted()
        guard !toShadow.isEmpty else { return arms }

        var shadowed: [ShadowedSpace] = []
        for space in toShadow {
            shadowed.append(
                ShadowedSpace(
                    idSpace: space,
                    mechanism: try shadowMechanism(
                        forIDSpace: space, in: bundle.schemaName, on: connection
                    )
                )
            )
        }
        var updated = arms
        updated[bundledIndex] = bundle.shadowing(shadowed)
        return updated
    }

    /// How one id space's rows are excluded from the bundled arm.
    ///
    /// Rejecting them on `id_space` costs a table probe per candidate row and gives the covering
    /// index back (162 ms against 72–81 ms, measured over the whole of San Francisco). Rejecting
    /// them on a **rowid range** is answered from `idx_trees_lat_lon` itself, which carries `id`,
    /// so the covering index survives.
    ///
    /// **The range is only usable when the space's ids are contiguous, and that is a property of
    /// one build of one file rather than a contract** — `Tools/build_seed.py` promises nothing
    /// about it. It is measured here instead: a space's ids are contiguous exactly when its row
    /// count equals its span. That test also proves no *other* space's row sits inside the range,
    /// because ids are unique — n rows spanning n consecutive integers leave no room for an
    /// eleventh. Where it does not hold, the `id_space` predicate is correct and slower, and both
    /// paths are tested.
    private static func shadowMechanism(
        forIDSpace space: String,
        in schemaName: String,
        on connection: SQLiteConnection
    ) throws -> ShadowMechanism {
        let statement = try connection.prepare("""
        SELECT MIN(id) AS low, MAX(id) AS high, COUNT(*) AS n
          FROM \(schemaName).trees WHERE id_space = :space
        """)
        defer { statement.finalize() }
        _ = try statement.bind(space, forName: ":space")
        guard let row = try statement.fetchOne({
            (low: try $0.int64IfPresent("low"), high: try $0.int64IfPresent("high"), n: try $0.int64("n"))
        }), let low = row.low, let high = row.high, row.n > 0 else {
            // No row in that space at all: nothing to exclude, and the cheapest correct predicate
            // is the one that excludes nothing.
            return .idSpacePredicate
        }
        return row.n == high - low + 1 ? .rowIDRange(low: low, high: high) : .idSpacePredicate
    }

    // MARK: - Introspection helpers

    private static func idSpaces(
        in schemaName: String,
        schema: SeedSchema,
        on connection: SQLiteConnection
    ) throws -> [String] {
        guard schema.hasIdSpace else { return [] }
        let statement = try connection.prepare(
            "SELECT DISTINCT id_space AS s FROM \(schemaName).trees ORDER BY s"
        )
        defer { statement.finalize() }
        return try statement.fetchAll { try $0.string("s") }
    }

    private static func hasSoftDeletes(
        in schemaName: String,
        on connection: SQLiteConnection
    ) throws -> Bool {
        let statement = try connection.prepare(
            "SELECT EXISTS(SELECT 1 FROM \(schemaName).trees WHERE deleted_at IS NOT NULL) AS present"
        )
        defer { statement.finalize() }
        return try statement.fetchOne { try $0.bool("present") } ?? false
    }

    // MARK: - Names

    /// Every view this type creates. `tearDown` drops them first, because they read the tables.
    static let viewNames = ["trees", "trees_geo", "trees_rtree", "species_assertions"]

    /// Every table this type materializes.
    ///
    /// **Tables rather than views, and the reason is the planner.** `species` is joined and grouped
    /// by from a dozen call sites and searched through four indexes that
    /// `SpeciesSearchTests.searchStaysOnItsCoveringIndexes` and
    /// `CivicShortNameTests.queryPlanMatchesTheProfileQuery` pin **by name**; a compound view has
    /// none of them, and `CREATE TABLE … AS SELECT` copies columns while dropping every constraint
    /// those names are derived from. Materializing 731 species, 21,179 trigram rows, 41
    /// neighborhoods and six rows of dimension tables costs milliseconds once, at open.
    static let materializedNames = [
        "species", "species_trigrams", "neighborhoods", "dim_city", "id_spaces",
        "inventories", "species_map", "seed_meta",
        "cypress_species_xlat", "cypress_hood_xlat"
    ]
}

/// One attached inventory file.
public struct InventoryArm: Sendable, Equatable {
    /// The pack id — `CityLibrary`'s install directory name — or `InventoryFile.bundledID`.
    public let id: String
    public let ordinal: Int
    /// `inv0`, `inv1`, … The attached schema name, never shown to a reader.
    public let schemaName: String
    public let isBundled: Bool
    /// The shape **this file** turned out to have. Arms may be different generations at once
    /// (R37.3): an s16 bundle beside an s17 pack is the shipping configuration.
    public let schema: SeedSchema
    /// Every id space this file holds rows in, sorted.
    public let idSpaces: [String]
    /// The columns `trees` actually has in **this** file, and the columns `trees_rtree` has.
    ///
    /// **The view projects `NULL` for anything absent rather than naming it and failing.** That is
    /// the same posture `SeedSchema` takes everywhere else — ask the file what it carries — and it
    /// is what lets a union include a generation older than the one this build was written for
    /// without the `CREATE VIEW` itself throwing `no such column`.
    public let treeColumns: Set<String>
    public let rtreeColumns: Set<String>
    public let hasSoftDeletedTrees: Bool
    /// The bundled arm's rows a pack now covers (RULING D1). Always empty on a pack.
    public let shadowed: [ShadowedSpace]

    func shadowing(_ spaces: [ShadowedSpace]) -> InventoryArm {
        InventoryArm(
            id: id, ordinal: ordinal, schemaName: schemaName, isBundled: isBundled,
            schema: schema, idSpaces: idSpaces,
            treeColumns: treeColumns, rtreeColumns: rtreeColumns,
            hasSoftDeletedTrees: hasSoftDeletedTrees, shadowed: spaces
        )
    }
}

/// One id space of the bundled seed that a downloaded pack covers, and how it is excluded.
public struct ShadowedSpace: Sendable, Equatable {
    public let idSpace: String
    public let mechanism: ShadowMechanism
}

public enum ShadowMechanism: Sendable, Equatable {
    /// The space's ids are contiguous, so `id NOT BETWEEN low AND high` excludes it and
    /// `idx_trees_lat_lon` still answers the query without touching the table.
    case rowIDRange(low: Int64, high: Int64)
    /// The space's ids are interleaved with another's, so the only correct predicate is the
    /// column, which costs a table probe per candidate row.
    case idSpacePredicate
}

/// One inventory file offered to the union.
public struct InventoryFile: Sendable, Equatable, Hashable {
    /// The id the bundled seed answers to. Not a pack id and never a directory name — the bundle
    /// has no install directory, which is the whole of `CityInstallState`'s bundled case.
    public static let bundledID = "__bundled__"

    public let id: String
    public let url: URL
    public let isBundled: Bool

    public init(id: String, url: URL, isBundled: Bool) {
        self.id = id
        self.url = url
        self.isBundled = isBundled
    }

    /// The app's own bundled inventory.
    public static func bundled(url: URL) -> InventoryFile {
        InventoryFile(id: bundledID, url: url, isBundled: true)
    }
}
