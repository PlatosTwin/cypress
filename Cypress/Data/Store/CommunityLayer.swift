import Foundation

/// The community layer as the readers see it: the trees this phone added, **plus** other people's
/// published trees the service has sent down, as one set with one tree per id (`AppSchema` v23).
///
/// ── The one-id rule, and why it is a helper rather than a convention ───────────────────────────
///
/// A community tree has one identity on both sides: `Tree.id`, minted by `addTree` and stored by the
/// service as the tree's own id. So a tree this phone added and the same tree served back by a tile
/// are **one tree**, and every reader that asks "what community trees are there" has to see it once
/// — or the map draws two pins, the shortlist offers the tree twice, and the dedupe refuses a tree
/// for being within 10 m of itself.
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
/// `mapContent`, `treesNear` (and so the add dedupe and the move dedupe), `treeProfile`,
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
    /// was — a tree added before v23 is nobody's and still added here. A caller that needs the adder
    /// asks `CommunityTreeStore.adder(treeID:)`.
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
         LIMIT :limit
        """

    /// The proximity dedupe over the whole community layer: `CommunityTreeStore.near`'s rule — box
    /// read unbounded, then the circle and the limit applied in exact meters — over both tables.
    ///
    /// - Parameter excluding: a tree that is not its own neighbor. A moved pin is checked against
    ///   every other tree, and the tree being moved is 0 m from its own old position.
    public func near(
        _ coordinate: Coordinate,
        radiusM: Double,
        limit: Int,
        excluding: UUID? = nil,
        connection: SQLiteConnection
    ) throws -> [Tree] {
        let bounds = BoundingBox(around: coordinate, radiusM: radiusM)
        return try inBounds(bounds, limit: nil, connection: connection)
            .filter { $0.id != excluding }
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
