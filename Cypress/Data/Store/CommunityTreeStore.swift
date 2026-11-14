import Foundation

/// Reads and writes over `main.community_trees` — trees **this phone** added (`addTree`).
///
/// Deliberately a separate type from `TreeQueries` rather than a `UNION` inside it. The seed
/// queries are tuned against 195,309 rows and a covering index; this table holds one row per tree
/// this installation added. Unioning them would force the whole clustered viewport through a
/// materialized subquery and lose the covering index for the rows that come from the city. Merging
/// two small result sets in Swift costs nothing and keeps both plans optimal.
///
/// **Since `AppSchema` v23 this is one of two community tables, and the readers that answer "what
/// community trees are there" do not read it alone.** Other people's published trees arrive in
/// `community_tree_cache`, and `CommunityLayer` is the merge helper over the two. The reads here
/// are the *authored* half: they answer "is this a tree this phone added", which is the question
/// every write in `LocalAPI` that acts on the record itself — a species claim, a correction, a
/// report, a withdrawal, a moved pin — has to ask, because a cached tree is somebody else's and
/// none of those are this phone's to make on it.
///
/// **The row records its adder since v23**, `photos`' at-most-one-owner pair, and the pin is a chain
/// (`tree_locations`) whose head `lat`/`lon`/`placement` cache.
public struct CommunityTreeStore {
    public init() {}

    private let locations = TreeLocationStore()

    // MARK: - Writing

    /// Idempotent on `clientUUID`, like every other contribution.
    ///
    /// **It writes the chain's root in the same call**, so no writer can produce a tree whose pin
    /// has no chain behind it — the state `correctLocation` could not append to, and exactly the
    /// state v14 had to backfill for species. The root's id is the tree's id and its key is the
    /// add's (`AppSchema` v23). Written only when the tree was: a replayed add changes nothing.
    ///
    /// - Parameter adder: who added it. `.nobody` is the default because the callers that predate
    ///   v23 — test fixtures, and `debugAddCommunityTree` through `addTree` passes its own — did not
    ///   say, and nobody is the honest value for "not said" (R45 arm 3). `LocalAPI.addTree` passes
    ///   the attribution of the act.
    @discardableResult
    public func insert(
        _ tree: Tree,
        clientUUID: UUID,
        adder: ContributionOwner = .nobody,
        connection: SQLiteConnection
    ) throws -> ContributionStore.WriteOutcome {
        let statement = try connection.cachedStatement("""
            INSERT INTO community_trees
                (id, client_uuid, external_ref, source, lat, lon, address, site_type, status,
                 species_current, planted_year, dbh_city_cm_min, dbh_city_cm_max, site_lineage,
                 verification_state, placement, land_context, created_at, updated_at, deleted_at,
                 user_id, device_id)
            VALUES
                (:id, :client, :ref, 'community', :lat, :lon, :address, :site, :status,
                 :species, :planted, :dbhMin, :dbhMax, :lineage,
                 :verification, :placement, :landContext, :created, :updated, :deleted,
                 :user, :device)
            ON CONFLICT(client_uuid) DO NOTHING
            """)
        _ = try statement.bind([
            ":id": tree.id,
            ":client": clientUUID,
            ":ref": tree.externalRef,
            ":lat": tree.coordinate.latitude,
            ":lon": tree.coordinate.longitude,
            ":address": tree.address,
            ":site": tree.siteType,
            ":status": tree.status.rawValue,
            ":species": tree.speciesCurrentID,
            ":planted": tree.plantedYear,
            ":dbhMin": tree.dbhCityCmRange?.lowerBound,
            ":dbhMax": tree.dbhCityCmRange?.upperBound,
            ":lineage": tree.siteLineage,
            ":verification": tree.verificationState.rawValue,
            // Bound rather than left to the column default. The default is what an upgraded row that
            // predates the column gets; a row written *now* states its own provenance, and a writer
            // that let the default answer for it would record `gps` for a pin somebody placed by
            // hand — the one direction this column must never fail in (AppSchema v10).
            ":placement": tree.placement.rawValue,
            // NULL when the contributor did not say, and NULL is the stored value for that — see
            // AppSchema v11. Unlike `placement` there is no column default to fall back on, on
            // purpose: nothing may answer this question on a contributor's behalf.
            ":landContext": tree.statedLandContext?.rawValue,
            ":created": tree.createdAt,
            ":updated": tree.updatedAt,
            ":deleted": tree.deletedAt,
            ":user": adder.userID,
            ":device": adder.deviceID
        ])
        try statement.run()
        let inserted = connection.changes > 0
        _ = try statement.reset()
        guard inserted else { return .duplicate }

        try locations.insert(
            TreeLocation(
                id: tree.id,
                treeID: tree.id,
                clientUUID: clientUUID,
                coordinate: tree.coordinate,
                placement: tree.placement,
                owner: adder,
                occurredAt: tree.createdAt,
                createdAt: tree.createdAt,
                updatedAt: tree.createdAt
            ),
            connection: connection
        )
        return .inserted
    }

    /// Moves the read cache to the chain's new head — the second half of a correction, in the
    /// transaction that appended the head (`LocalAPI.correctLocation`).
    ///
    /// **Deliberately not a verb that decides anything**, `setSpecies`' shape: the chain is the
    /// record and these three columns follow it.
    ///
    /// - Returns: whether there was a live row to move. `false` means no such row, or it has been
    ///   withdrawn.
    public func move(
        treeID: UUID,
        to coordinate: Coordinate,
        placement: TreePlacement,
        at moment: Date,
        connection: SQLiteConnection
    ) throws -> Bool {
        let statement = try connection.cachedStatement("""
            UPDATE community_trees
               SET lat = :lat, lon = :lon, placement = :placement, updated_at = :updated
             WHERE id = :id COLLATE NOCASE
               AND deleted_at IS NULL
            """)
        _ = try statement.bind([
            ":lat": coordinate.latitude,
            ":lon": coordinate.longitude,
            ":placement": placement.rawValue,
            ":updated": moment,
            ":id": treeID
        ])
        try statement.run()
        let changed = connection.changes > 0
        _ = try statement.reset()
        return changed
    }

    /// Names the species on a row that has none. See `SpeciesClaim` for why that is the only species
    /// edit this table takes.
    ///
    /// - Returns: whether the claim landed. `false` means the row already had a species, or has been
    ///   soft-deleted, or is not here — three refusals the caller distinguishes by reading the row.
    ///
    /// **`species_current IS NULL` is in the `WHERE`, not in a preceding `SELECT`.** First-claim-wins
    /// enforced by a read-then-write leaves a window in which two callers both see NULL and the
    /// second one silently overwrites the first, which is the same race every other contribution
    /// write closes with `ON CONFLICT … DO NOTHING`. Here the engine decides, once.
    public func claimSpecies(
        treeID: UUID,
        speciesID: UUID,
        at moment: Date,
        connection: SQLiteConnection
    ) throws -> Bool {
        let statement = try connection.cachedStatement("""
            UPDATE community_trees
               SET species_current = :species, updated_at = :updated
             WHERE id = :id COLLATE NOCASE
               AND species_current IS NULL
               AND deleted_at IS NULL
            """)
        _ = try statement.bind([
            ":species": speciesID,
            ":updated": moment,
            ":id": treeID
        ])
        try statement.run()
        let changed = connection.changes > 0
        _ = try statement.reset()
        return changed
    }

    /// Moves the read cache to a species that is already claimed — the correction `claimSpecies`
    /// refuses (AppSchema v14, tickets #86/#124).
    ///
    /// **Deliberately not a widening of `claimSpecies`.** The `species_current IS NULL` in that
    /// method is first-claim-wins written in SQL, and a flag that switched it off would put this
    /// project's one race guard behind a boolean. Two methods, two names, and the one that can
    /// overwrite somebody's statement is reached only through `LocalAPI.correctSpecies`, which
    /// checks who is asking. What this method does *not* do is decide anything: the chain in
    /// `species_assertions` is the record, and this column follows it in the same transaction.
    ///
    /// - Returns: whether the row was there to move. `false` means no such row, or it is deleted.
    public func setSpecies(
        treeID: UUID,
        speciesID: UUID,
        at moment: Date,
        connection: SQLiteConnection
    ) throws -> Bool {
        let statement = try connection.cachedStatement("""
            UPDATE community_trees
               SET species_current = :species, updated_at = :updated
             WHERE id = :id COLLATE NOCASE
               AND deleted_at IS NULL
            """)
        _ = try statement.bind([
            ":species": speciesID,
            ":updated": moment,
            ":id": treeID
        ])
        try statement.run()
        let changed = connection.changes > 0
        _ = try statement.reset()
        return changed
    }

    /// Withdraws the record: the row is soft-deleted and stops being a tree anywhere in the app
    /// (task **#125**, `RULINGS R50`).
    ///
    /// **A soft delete, not a `DELETE`, and the difference is the whole claim being made.** Every
    /// read in this file already filters `deleted_at IS NULL` — `inBounds`, `near`, `claimSpecies`,
    /// `setSpecies` — so one column removes the pin, the profile and the correction routes in one
    /// write, without a single reader learning a new rule. It also leaves the row: a confirmed
    /// "this was never here" is a fact D16's merged inventory wants to publish, and a row that has
    /// been erased cannot be published. `tree(id:)` deliberately does **not** filter, so the
    /// withdrawal is still readable by the one caller that needs to see what it did.
    ///
    /// - Returns: whether there was a live row to withdraw. `false` means no such row, or it has
    ///   already been withdrawn — which is why the caller may treat a second confirmation as a
    ///   no-op rather than as a failure.
    public func withdraw(treeID: UUID, at moment: Date, connection: SQLiteConnection) throws -> Bool {
        let statement = try connection.cachedStatement("""
            UPDATE community_trees
               SET deleted_at = :now, updated_at = :now
             WHERE id = :id COLLATE NOCASE
               AND deleted_at IS NULL
            """)
        _ = try statement.bind([":now": moment, ":id": treeID])
        try statement.run()
        let changed = connection.changes > 0
        _ = try statement.reset()
        return changed
    }

    // MARK: - Reading

    /// Who added this tree, or nil when this phone holds no such row.
    ///
    /// `.nobody` is an answer, not an absence: every tree added before `AppSchema` v23, whose adder
    /// the phone never recorded, and every tree an account deletion anonymized. Nobody may move
    /// either pin (`LocalAPI.correctLocation`), for R45 arm 3's reason.
    ///
    /// Not a field on `Tree`, deliberately. `Tree` is the record every reader and the wire share,
    /// and the service serves it with no adder at all (history carries no actor, decision 4); an
    /// owner that rode on it would be one more place for a caller-relative fact to travel where it
    /// should not.
    public func adder(treeID: UUID, connection: SQLiteConnection) throws -> ContributionOwner? {
        let statement = try connection.cachedStatement("""
            SELECT user_id, device_id FROM community_trees WHERE id = :id COLLATE NOCASE
            """)
        _ = try statement.bind(treeID.uuidString, forName: ":id")
        return try statement.fetchOne { row -> ContributionOwner in
            if let user = try row.uuidIfPresent("user_id") { return .user(user) }
            if let device = try row.uuidIfPresent("device_id") { return .device(device) }
            return .nobody
        }
    }

    public func tree(id: UUID, connection: SQLiteConnection) throws -> Tree? {
        let statement = try connection.cachedStatement("""
            SELECT * FROM community_trees WHERE id = :id COLLATE NOCASE
            """)
        _ = try statement.bind(id.uuidString, forName: ":id")
        return try statement.fetchOne(Self.decode)
    }

    // `trees(ids:)` and its `treesSQL` moved to `CommunityLayer` in `AppSchema` v23: the grove
    // resolves a tree somebody else published as readily as one this phone added, so the set read
    // is the merged one. The `COLLATE NOCASE`-on-the-left-operand lesson moved with it.

    public func exists(id: UUID, connection: SQLiteConnection) throws -> Bool {
        let statement = try connection.cachedStatement("""
            SELECT 1 AS present FROM community_trees WHERE id = :id COLLATE NOCASE
            """)
        _ = try statement.bind(id.uuidString, forName: ":id")
        return try statement.fetchOne { _ in true } ?? false
    }

    /// Rows inside a bounding box. `limit: nil` reads every row in the box.
    ///
    /// ```
    /// SEARCH community_trees USING INDEX idx_community_trees_lat_lon (lat>? AND lat<?)
    /// ```
    public func inBounds(_ bounds: BoundingBox, limit: Int?, connection: SQLiteConnection) throws -> [Tree] {
        let statement = try connection.cachedStatement("""
            SELECT * FROM community_trees
             WHERE lat BETWEEN :minLat AND :maxLat
               AND lon BETWEEN :minLon AND :maxLon
               AND deleted_at IS NULL
             LIMIT :limit
            """)
        _ = try statement.bind([
            ":minLat": bounds.minLatitude,
            ":maxLat": bounds.maxLatitude,
            ":minLon": bounds.minLongitude,
            ":maxLon": bounds.maxLongitude,
            // A negative LIMIT is SQLite's documented "no upper bound".
            ":limit": limit ?? -1
        ])
        return try statement.fetchAll(Self.decode)
    }

    /// The 10 m proximity dedupe from `POST /trees`, over the community table. The seed half runs
    /// through `TreeQueries.nearest`.
    ///
    /// The box is read **unbounded** and the caller's limit is applied afterwards. `inBounds` has no
    /// `ORDER BY`, so a `LIMIT` inside it drops rows in storage order rather than by distance — the
    /// row it discards can be the one 3 m away, and a dedupe that misses its own duplicate admits a
    /// second record of the same tree. The box is a pre-filter; the circle and the limit are the
    /// answer, and they are applied to exact meters. This table holds tens of rows within any
    /// dedupe radius, so reading it whole costs nothing.
    public func near(_ coordinate: Coordinate, radiusM: Double, limit: Int, connection: SQLiteConnection) throws -> [Tree] {
        let bounds = BoundingBox(around: coordinate, radiusM: radiusM)
        return try inBounds(bounds, limit: nil, connection: connection)
            .filter { coordinate.distance(to: $0.coordinate) <= radiusM }
            .sorted { coordinate.distance(to: $0.coordinate) < coordinate.distance(to: $1.coordinate) }
            .prefix(limit)
            .map { $0 }
    }

    static func decode(_ row: SQLiteRow) throws -> Tree {
        let minimum = try row.intIfPresent("dbh_city_cm_min")
        let maximum = try row.intIfPresent("dbh_city_cm_max")
        return Tree(
            id: try row.uuid("id"),
            externalRef: try row.stringIfPresent("external_ref"),
            source: try row.value("source", TreeSource.self),
            coordinate: Coordinate(latitude: try row.double("lat"), longitude: try row.double("lon")),
            address: try row.stringIfPresent("address"),
            siteType: try row.stringIfPresent("site_type"),
            neighborhoodID: nil,
            status: try row.value("status", TreeStatus.self),
            speciesCurrentID: try row.uuidIfPresent("species_current"),
            plantedYear: try row.intIfPresent("planted_year"),
            dbhCityCmRange: (minimum != nil && maximum != nil)
                ? IntRange(lowerBound: minimum!, upperBound: maximum!) : nil,
            siteLineage: try row.uuidIfPresent("site_lineage"),
            verificationState: try row.value("verification_state", VerificationState.self),
            placement: try row.value("placement", TreePlacement.self),
            // A community tree is not in the city's inventory, so there is no city record to carry.
            cityRecord: nil,
            statedLandContext: try row.enumIfPresent("land_context", LandContext.self),
            createdAt: try row.date("created_at"),
            updatedAt: try row.date("updated_at"),
            deletedAt: try row.dateIfPresent("deleted_at")
        )
    }
}
