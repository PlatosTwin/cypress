import Foundation

/// Writes over `main.community_tree_cache` and `main.community_tree_cache_tiles` — other people's
/// published community trees, as `GET /community-trees` serves them (`AppSchema` v23).
///
/// This round adds the store; the round that fetches tiles (C2, the sync-down) is its caller. The
/// rules it implements are the service's contract, in `server/testdata/README.md`, and each is a
/// statement here rather than a convention the caller has to remember:
///
/// - **A page is one transaction.** The trees it served, the removals it reported and the cursor it
///   returned land together or not at all, so a cursor never claims a page whose trees are not
///   here. The caller wraps `apply` in the queue's write.
/// - **The cache keys on the tree id and nothing else.** A tree served by a tile can lie outside it
///   (a pin moved out after going live), so nothing here checks a position against a tile.
/// - **A removal drops the id from the whole cache**, whichever tile served it; erase-door
///   tombstones carry no position, so every tile reports every one. An id the cache never held is
///   ignored, never an error.
/// - **A refused cursor drops the cursor and the trees fetched through it together**
///   (`dropTile`), so the next fetch is a snapshot and a removal missed while the cursor was bad
///   cannot leave a pin standing.
/// - **The phone's own row wins.** An id `community_trees` holds is not stored: the schema's trigger
///   ignores it, which is why `apply` reports how many trees it actually stored.
/// - **`updatedAt` is stored and never used to decide anything.** Community-tree dates are served at
///   day precision; the cursor, not a cached tree's `updatedAt`, says what changed (the S2 ruling).
public struct CommunityTreeCacheStore {
    public init() {}

    /// What one page did, in rows, so a caller or a test can check it rather than assume it.
    public struct PageOutcome: Sendable, Equatable {
        /// Trees written or refreshed. Fewer than the page held when some were this phone's own.
        public var stored: Int = 0
        /// Cached trees the page's removal list dropped.
        public var removed: Int = 0
    }

    // MARK: - Writing

    /// Applies one page of one tile.
    ///
    /// A tree that is not a community tree is skipped rather than stored: the route serves only
    /// community trees, and a city row in this table would draw a dashed pin over the city's own.
    @discardableResult
    public func apply(
        tile: String,
        trees: [Tree],
        withdrawnTreeIDs: [UUID],
        nextCursor: String,
        at moment: Date,
        connection: SQLiteConnection
    ) throws -> PageOutcome {
        var outcome = PageOutcome()
        let upsert = try connection.cachedStatement(Self.upsertSQL)
        for tree in trees where tree.source == .community {
            _ = try upsert.bind([
                ":id": tree.id,
                ":lat": tree.coordinate.latitude,
                ":lon": tree.coordinate.longitude,
                ":placement": tree.placement.rawValue,
                ":status": tree.status.rawValue,
                ":species": tree.speciesCurrentID,
                ":landContext": tree.statedLandContext?.rawValue,
                ":verification": tree.verificationState.rawValue,
                ":created": tree.createdAt,
                ":updated": tree.updatedAt,
                ":tile": tile,
                ":fetched": moment
            ])
            try upsert.run()
            outcome.stored += connection.changes
            _ = try upsert.reset()
        }

        outcome.removed = try remove(ids: withdrawnTreeIDs, connection: connection)

        let cursor = try connection.cachedStatement("""
            INSERT INTO main.community_tree_cache_tiles (tile, next_cursor, fetched_at)
            VALUES (:tile, :cursor, :fetched)
            ON CONFLICT(tile) DO UPDATE SET next_cursor = excluded.next_cursor,
                                            fetched_at = excluded.fetched_at
            """)
        _ = try cursor.bind([":tile": tile, ":cursor": nextCursor, ":fetched": moment])
        try cursor.run()
        _ = try cursor.reset()
        return outcome
    }

    static let upsertSQL = """
        INSERT INTO main.community_tree_cache
            (id, lat, lon, placement, status, species_current, land_context, verification_state,
             created_at, updated_at, tile, fetched_at)
        VALUES (:id, :lat, :lon, :placement, :status, :species, :landContext, :verification,
                :created, :updated, :tile, :fetched)
        ON CONFLICT(id) DO UPDATE SET
            lat = excluded.lat, lon = excluded.lon, placement = excluded.placement,
            status = excluded.status, species_current = excluded.species_current,
            land_context = excluded.land_context, verification_state = excluded.verification_state,
            created_at = excluded.created_at, updated_at = excluded.updated_at,
            tile = excluded.tile, fetched_at = excluded.fetched_at
        """

    /// Drops cached trees by id, from the whole cache. Returns how many were there.
    @discardableResult
    public func remove(ids: [UUID], connection: SQLiteConnection) throws -> Int {
        guard !ids.isEmpty else { return 0 }
        let statement = try connection.cachedStatement("""
            DELETE FROM main.community_tree_cache
             WHERE id IN (SELECT value FROM json_each(:ids))
            """)
        _ = try statement.bind(
            "[\(ids.map { "\"\($0.uuidString)\"" }.joined(separator: ","))]", forName: ":ids"
        )
        try statement.run()
        let removed = connection.changes
        _ = try statement.reset()
        return removed
    }

    /// Forgets a tile: its cursor and every tree it last served, together.
    @discardableResult
    public func dropTile(_ tile: String, connection: SQLiteConnection) throws -> Int {
        let trees = try connection.cachedStatement(
            "DELETE FROM main.community_tree_cache WHERE tile = :tile"
        )
        _ = try trees.bind([":tile": tile])
        try trees.run()
        let dropped = connection.changes
        _ = try trees.reset()

        let cursor = try connection.cachedStatement(
            "DELETE FROM main.community_tree_cache_tiles WHERE tile = :tile"
        )
        _ = try cursor.bind([":tile": tile])
        try cursor.run()
        _ = try cursor.reset()
        return dropped
    }

    // MARK: - Reading

    /// The cursor to send back for a tile, unchanged, or nil for a tile never fetched (a snapshot).
    public func cursor(tile: String, connection: SQLiteConnection) throws -> String? {
        let statement = try connection.cachedStatement(
            "SELECT next_cursor FROM main.community_tree_cache_tiles WHERE tile = :tile"
        )
        _ = try statement.bind([":tile": tile])
        return try statement.fetchOne { try $0.string("next_cursor") }
    }
}
