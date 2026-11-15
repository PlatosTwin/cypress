import Foundation

/// The community layer as the readers see it: the trees this phone added, **plus** other people's
/// published trees the service has sent down, as one set with one tree per id (`AppSchema` v23).
///
/// ── The one-id rule, and why it is a helper rather than a convention ───────────────────────────
///
/// A community tree has one identity on both sides: `Tree.id`, minted by `addTree` and stored by the
/// service as the tree's own id. So a tree this phone added and the same tree served back by a tile
/// are **one tree**, and every reader that asks "what community trees are there" has to see it once
/// — or the map draws two pins, the shortlist offers the tree twice, and the add screen's note
/// names the tree as on record within 10 m of itself. (Since the owner's ruling of 2026-11-14 the
/// note does not refuse: the add screen notes a tree within 10 m and still adds.)
///
/// The schema already makes the double unstorable (two triggers, `AppSchema` v23). This type makes
/// it unreadable as well: every statement here reads `community_trees` and then only those cache
/// rows whose id `community_trees` does not hold, compared `COLLATE NOCASE` because the service's
/// JSON spells UUIDs in lowercase and this phone in uppercase. **The phone's own row wins**,
/// withdrawn or not — a tree this phone withdrew is not brought back by somebody's cached copy of
/// it.
///
/// ── Who reads through this, and who deliberately does not ──────────────────────────────────────
///
/// `mapContent`, `treesNear` (and so the add screen's within-10 m note), `treeProfile`,
/// `requireTree`, the grove's row resolution, `contributedPlaces`, the review queue and the name
/// resolver. Every *write* that acts on the record itself — a species claim or correction, a report,
/// a record withdrawal, a moved pin — reads `CommunityTreeStore` alone, because a cached tree is
/// somebody else's and none of those are this phone's to make on it.
///
/// ── Why one statement, not two reads merged in Swift ──────────────────────────────────────────
///
/// `CommunityTreeStore`'s header argues for merging in Swift against the *seed*, which is 195,309
/// rows behind a covering index. These two tables are both small and both local, and the exclusion
/// is a question about the whole of `community_trees` — a tree moved out of this viewport on this
/// phone still owns its id — which a Swift merge over two boxed reads cannot ask. A `UNION ALL` with
/// a `NOT EXISTS` on the NOCASE id index asks it in the engine, and it keeps each caller at the
/// statement count it had (`GroveStatementCensusTests`).
public struct CommunityLayer {
    public init() {}

    /// One community tree, and whether this phone added it.
    ///
    /// The flag is provenance, not ownership: "added here" is `community_trees`, whoever the adder
    /// was — a tree an account deletion anonymized is nobody's and still added here. A caller that
    /// needs the adder asks `CommunityTreeStore.adder(treeID:)`.
    public struct Row: Sendable, Equatable {
        public let tree: Tree
        public let isAddedHere: Bool
    }

    // MARK: - The shared projection

    /// Both arms project to `community_trees`' column names, so `CommunityTreeStore.decode` reads
    /// either. The cache holds only the tile's public facts; everything else a cached tree has is
    /// null on the wire (S2's §3C) and null here.
    private static let addedColumns = """
        id, external_ref, source, lat, lon, address, site_type, status, species_current,
        planted_year, dbh_city_cm_min, dbh_city_cm_max, site_lineage, verification_state,
        placement, land_context, created_at, updated_at, deleted_at, 0 AS cached
        """

    private static let cachedColumns = """
        k.id, NULL, 'community', k.lat, k.lon, NULL, NULL, k.status, k.species_current,
        NULL, NULL, NULL, NULL, k.verification_state,
        k.placement, k.land_context, k.created_at, k.updated_at, NULL, 1
        """

    /// The one clause every cache arm carries: the phone's own row wins.
    private static let notAddedHere = """
        NOT EXISTS (SELECT 1 FROM community_trees c WHERE c.id = k.id COLLATE NOCASE)
        """

    // MARK: - Reading

    /// Live community trees inside a bounding box. `limit: nil` reads every row in the box.
    ///
    /// Withdrawn trees this phone added are filtered, as `CommunityTreeStore.inBounds` always did; a
    /// cached tree has no `deleted_at` because the cache drops a removed tree outright.
    public func inBounds(_ bounds: BoundingBox, limit: Int?, connection: SQLiteConnection) throws -> [Tree] {
        let statement = try connection.cachedStatement(Self.inBoundsSQL)
        _ = try statement.bind([
            ":minLat": bounds.minLatitude,
            ":maxLat": bounds.maxLatitude,
            ":minLon": bounds.minLongitude,
            ":maxLon": bounds.maxLongitude,
            // A negative LIMIT is SQLite's documented "no upper bound".
            ":limit": limit ?? -1
        ])
        return try statement.fetchAll(CommunityTreeStore.decode)
    }

    /// **The phone's own trees come first, then other people's, each by id**, so a `limit` cuts
    /// other people's trees before this phone's own (ERRATA E36: a contributor's own pin must appear
    /// on the screen they added it from). `pinsSQL`, the map's read, keeps the same order after its
    /// narrowing. The order is fixed for a fixed box, so reading the same box twice cuts the same
    /// trees. **It does not hold across a pan**: a pan that brings in a tree with a lower id can push
    /// out a tree that is still on screen. Both tables are small and local; the sort is over the
    /// rows in one box.
    static let inBoundsSQL = """
        SELECT \(addedColumns) FROM community_trees
         WHERE lat BETWEEN :minLat AND :maxLat
           AND lon BETWEEN :minLon AND :maxLon
           AND deleted_at IS NULL
        UNION ALL
        SELECT \(cachedColumns) FROM community_tree_cache k
         WHERE k.lat BETWEEN :minLat AND :maxLat
           AND k.lon BETWEEN :minLon AND :maxLon
           AND \(notAddedHere)
         ORDER BY cached, id
         LIMIT :limit
        """

    // MARK: - The map's reads

    /// What a map viewport narrows the community layer to, already resolved to sets. `nil` in any
    /// field means "not narrowed by this"; an **empty** set means "narrowed to nothing" and matches
    /// no tree, the `[]` versus `nil` distinction `MapViewport` draws.
    ///
    /// `LocalAPI.mapContent` builds it from the viewport, so the rules live there: species is the
    /// typed species intersected with the blooming ones, and statuses is the intersection of what
    /// `Needs care`, the site kind and a planting year each admit.
    public struct Narrowing: Sendable, Equatable {
        public var speciesIDs: Set<UUID>?
        public var statuses: Set<TreeStatus>?
        public var treeIDs: Set<UUID>?
        /// A tree with no planting year never matches a year range, and a cached tree has none.
        public var plantedYears: ClosedRange<Int>?

        public init(
            speciesIDs: Set<UUID>? = nil,
            statuses: Set<TreeStatus>? = nil,
            treeIDs: Set<UUID>? = nil,
            plantedYears: ClosedRange<Int>? = nil
        ) {
            self.speciesIDs = speciesIDs
            self.statuses = statuses
            self.treeIDs = treeIDs
            self.plantedYears = plantedYears
        }

        public static let none = Narrowing()

        fileprivate var bindings: [String: SQLiteBindable?] {
            func json(_ values: [String]?) -> String? {
                values.map { "[\($0.map { "\"\($0)\"" }.joined(separator: ","))]" }
            }
            return [
                ":species": json(speciesIDs.map { $0.map(\.uuidString) }),
                ":statuses": json(statuses.map { $0.map(\.rawValue) }),
                ":ids": json(treeIDs.map { $0.map(\.uuidString) }),
                ":minYear": plantedYears?.lowerBound,
                ":maxYear": plantedYears?.upperBound,
            ]
        }
    }

    /// The community trees a pin answer may draw, and how many match in all.
    public struct PinRead: Sendable, Equatable {
        /// The phone's own trees first, then other people's, each by id, cut to the limit.
        public let trees: [Tree]
        /// Every narrowed tree in the box, before the cut.
        public let matches: Int
    }

    /// The narrowed community trees in a box, **narrowed and counted in the engine, then cut**
    /// (round C2's second review). One statement: the narrowing is in the `WHERE` of both arms,
    /// `COUNT(*) OVER ()` counts every match before the `LIMIT`, and only the rows the limit keeps
    /// are decoded into `Tree`. Decoding every tree in the box and narrowing in Swift cost about
    /// 430 ms at 5,000 cached trees and 3.8 s at 50,000, holding the one database queue the whole
    /// time.
    public func pins(
        in bounds: BoundingBox,
        narrowing: Narrowing,
        limit: Int,
        connection: SQLiteConnection
    ) throws -> PinRead {
        let statement = try connection.cachedStatement(Self.pinsSQL)
        _ = try statement.bind(Self.boxBindings(bounds).merging(narrowing.bindings) { first, _ in first })
        _ = try statement.bind(max(limit, 0), forName: ":limit")
        var matches = 0
        let trees = try statement.fetchAll { row -> Tree in
            matches = try row.int("matches")
            return try CommunityTreeStore.decode(row)
        }
        // A limit of zero keeps no row, so no row carries the count; ask for it on its own then.
        if trees.isEmpty, limit <= 0 {
            matches = try count(in: bounds, narrowing: narrowing, connection: connection)
        }
        return PinRead(trees: trees, matches: matches)
    }

    /// One clustered cell's share of the community layer: how many narrowed trees fall in it, and
    /// their mean position.
    public struct Cell: Sendable, Equatable {
        public let cellY: Int
        public let cellX: Int
        public let count: Int
        public let coordinate: Coordinate
    }

    /// The narrowed community trees in a box, **counted per cell in the engine**. The cell is
    /// `TreeQueries.cellSize`'s grid, keyed as `LocalAPI.mapContent` keys it:
    /// `Int((latitude + 90) / cellLatitude)` and `Int((longitude + 180) / cellLongitude)`, which
    /// SQLite's `CAST(… AS INTEGER)` computes the same way, truncating, on the same doubles. No
    /// `Tree` is built, so a badge counts every match at the cost of one aggregate.
    public func cells(
        in bounds: BoundingBox,
        narrowing: Narrowing,
        cellLatitude: Double,
        cellLongitude: Double,
        connection: SQLiteConnection
    ) throws -> [Cell] {
        let statement = try connection.cachedStatement(Self.cellsSQL)
        _ = try statement.bind(Self.boxBindings(bounds).merging(narrowing.bindings) { first, _ in first })
        _ = try statement.bind(cellLatitude, forName: ":cellLat")
        _ = try statement.bind(cellLongitude, forName: ":cellLon")
        return try statement.fetchAll { row in
            Cell(
                cellY: try row.int("cell_y"),
                cellX: try row.int("cell_x"),
                count: try row.int("n"),
                coordinate: Coordinate(latitude: try row.double("mean_lat"), longitude: try row.double("mean_lon"))
            )
        }
    }

    /// How many narrowed community trees are in the box.
    public func count(in bounds: BoundingBox, narrowing: Narrowing, connection: SQLiteConnection) throws -> Int {
        let statement = try connection.cachedStatement(Self.countSQL)
        _ = try statement.bind(Self.boxBindings(bounds).merging(narrowing.bindings) { first, _ in first })
        return try statement.fetchOne { try $0.int("n") } ?? 0
    }

    private static func boxBindings(_ bounds: BoundingBox) -> [String: SQLiteBindable?] {
        [
            ":minLat": bounds.minLatitude,
            ":maxLat": bounds.maxLatitude,
            ":minLon": bounds.minLongitude,
            ":maxLon": bounds.maxLongitude,
        ]
    }

    /// The narrowing, on the phone's own table. Each clause is true when its parameter is NULL.
    /// `COLLATE NOCASE` sits on the left operand, never on the `IN` list (`treesSQL`'s note).
    private static let addedNarrowing = """
           AND (:species IS NULL OR species_current COLLATE NOCASE IN (SELECT value FROM json_each(:species)))
           AND (:statuses IS NULL OR status IN (SELECT value FROM json_each(:statuses)))
           AND (:ids IS NULL OR id COLLATE NOCASE IN (SELECT value FROM json_each(:ids)))
           AND (:minYear IS NULL OR planted_year BETWEEN :minYear AND :maxYear)
        """

    /// The same narrowing on the cache. A cached tree has no planting year, so a year range
    /// excludes every cached tree, as the Swift filter did (ERRATA E175's nil-year rule).
    private static let cachedNarrowing = """
           AND (:species IS NULL OR k.species_current COLLATE NOCASE IN (SELECT value FROM json_each(:species)))
           AND (:statuses IS NULL OR k.status IN (SELECT value FROM json_each(:statuses)))
           AND (:ids IS NULL OR k.id IN (SELECT value FROM json_each(:ids)))
           AND :minYear IS NULL
        """

    private static let narrowedArms = """
        SELECT \(addedColumns) FROM community_trees
         WHERE lat BETWEEN :minLat AND :maxLat
           AND lon BETWEEN :minLon AND :maxLon
           AND deleted_at IS NULL
        \(addedNarrowing)
        UNION ALL
        SELECT \(cachedColumns) FROM community_tree_cache k
         WHERE k.lat BETWEEN :minLat AND :maxLat
           AND k.lon BETWEEN :minLon AND :maxLon
           AND \(notAddedHere)
        \(cachedNarrowing)
        """

    /// `inBoundsSQL`'s order, after the narrowing, with the count of every match on each row.
    static let pinsSQL = """
        SELECT *, COUNT(*) OVER () AS matches FROM (
        \(narrowedArms)
        )
         ORDER BY cached, id
         LIMIT :limit
        """

    static let cellsSQL = """
        SELECT CAST((lat + 90.0) / :cellLat AS INTEGER) AS cell_y,
               CAST((lon + 180.0) / :cellLon AS INTEGER) AS cell_x,
               COUNT(*) AS n, AVG(lat) AS mean_lat, AVG(lon) AS mean_lon
          FROM (
        \(narrowedArms)
        )
         GROUP BY cell_y, cell_x
        """

    static let countSQL = """
        SELECT COUNT(*) AS n FROM (
        \(narrowedArms)
        )
        """

    /// The nearby-tree lookup over the whole community layer: `CommunityTreeStore.near`'s rule —
    /// box read unbounded, then the circle and the limit applied in exact meters — over both
    /// tables. It feeds the add screen's within-10 m note, which does not refuse (the owner's
    /// ruling of 2026-11-14).
    public func near(
        _ coordinate: Coordinate,
        radiusM: Double,
        limit: Int,
        connection: SQLiteConnection
    ) throws -> [Tree] {
        let bounds = BoundingBox(around: coordinate, radiusM: radiusM)
        return try inBounds(bounds, limit: nil, connection: connection)
            .filter { coordinate.distance(to: $0.coordinate) <= radiusM }
            .sorted { coordinate.distance(to: $0.coordinate) < coordinate.distance(to: $1.coordinate) }
            .prefix(limit)
            .map { $0 }
    }

    /// One tree by id, whichever table holds it. Like `CommunityTreeStore.tree(id:)` this does
    /// **not** filter a withdrawn tree this phone added: the one caller that needs to see a
    /// withdrawal is why that method does not either.
    public func row(id: UUID, connection: SQLiteConnection) throws -> Row? {
        let statement = try connection.cachedStatement(Self.rowSQL)
        _ = try statement.bind(id.uuidString, forName: ":id")
        return try statement.fetchOne { row in
            Row(tree: try CommunityTreeStore.decode(row), isAddedHere: try row.int("cached") == 0)
        }
    }

    static let rowSQL = """
        SELECT \(addedColumns) FROM community_trees WHERE id = :id COLLATE NOCASE
        UNION ALL
        SELECT \(cachedColumns) FROM community_tree_cache k
         WHERE k.id = :id AND \(notAddedHere)
        """

    public func tree(id: UUID, connection: SQLiteConnection) throws -> Tree? {
        try row(id: id, connection: connection)?.tree
    }

    public func exists(id: UUID, connection: SQLiteConnection) throws -> Bool {
        try row(id: id, connection: connection) != nil
    }

    /// The same read for a set of ids, keyed by id — one statement, for the grove's reason
    /// (`LocalAPI.grove()` resolves every row in one hop, `GroveStatementCensusTests`).
    ///
    /// **`COLLATE NOCASE` on the left operand of the added arm, not on the `IN` list** —
    /// `TreeQueries.speciesRowIDs` records the day `id IN (…) COLLATE NOCASE` bound the collation to
    /// the subquery and answered zero. The cache arm needs no clause: its `id` column is declared
    /// `COLLATE NOCASE`, and a column's own collation governs the comparison.
    ///
    /// Like `row(id:)`, this does not filter a withdrawal.
    public func trees(ids: [UUID], connection: SQLiteConnection) throws -> [UUID: Tree] {
        guard !ids.isEmpty else { return [:] }
        let statement = try connection.cachedStatement(Self.treesSQL)
        _ = try statement.bind(
            "[\(ids.map { "\"\($0.uuidString)\"" }.joined(separator: ","))]", forName: ":ids"
        )
        var trees: [UUID: Tree] = [:]
        for tree in try statement.fetchAll(CommunityTreeStore.decode) { trees[tree.id] = tree }
        return trees
    }

    /// The text `trees(ids:)` runs, as a property, so `GroveStatementCensusTests` pins the statement
    /// the app prepares rather than a copy of it (PR #143's review).
    static let treesSQL = """
        SELECT \(addedColumns) FROM community_trees
         WHERE id COLLATE NOCASE IN (SELECT value FROM json_each(:ids))
        UNION ALL
        SELECT \(cachedColumns) FROM community_tree_cache k
         WHERE k.id IN (SELECT value FROM json_each(:ids))
           AND \(notAddedHere)
        """
}
