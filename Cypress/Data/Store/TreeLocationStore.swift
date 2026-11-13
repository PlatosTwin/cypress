import Foundation

/// Reads and writes over `main.tree_locations` — a community tree's pin, as a chain (`AppSchema`
/// v23).
///
/// `SpeciesAssertionStore`'s shape, and deliberately so: append, stamp the row replaced, read the
/// head. `insert` supersedes nothing, so a caller that forgets `supersede` leaves two heads and the
/// partial unique index refuses the insert rather than the database quietly holding two positions.
///
/// **Every statement names `main`**, for `SpeciesAssertionStore`'s reason stated once more: no
/// attached database carries this table today, and a query that silently read one that did would
/// be the failure that looks like working software.
public struct TreeLocationStore {
    public init() {}

    // MARK: - Writing

    /// Appends a position. Idempotent on `id`, so the root `CommunityTreeStore.insert` writes beside a
    /// tree that already had one — a replayed add — is a no-op rather than a failure inside the
    /// add's transaction.
    public func insert(_ location: TreeLocation, connection: SQLiteConnection) throws {
        let statement = try connection.cachedStatement("""
            INSERT INTO main.tree_locations
                (id, tree_id, client_uuid, lat, lon, placement, location_accuracy_m,
                 user_id, device_id, superseded_by, occurred_at, created_at, updated_at)
            VALUES (:id, :tree, :client, :lat, :lon, :placement, :accuracy,
                    :user, :device, :superseded, :occurred, :created, :updated)
            ON CONFLICT(id) DO NOTHING
            """)
        _ = try statement.bind([
            ":id": location.id,
            ":tree": location.treeID,
            ":client": location.clientUUID,
            ":lat": location.coordinate.latitude,
            ":lon": location.coordinate.longitude,
            ":placement": location.placement.rawValue,
            ":accuracy": location.locationAccuracyM,
            ":user": location.movedByUser,
            ":device": location.movedByDevice,
            ":superseded": location.supersededBy,
            ":occurred": location.occurredAt,
            ":created": location.createdAt,
            ":updated": location.updatedAt
        ])
        try statement.run()
        _ = try statement.reset()
    }

    /// Stamps `superseded_by` on the row a correction replaces, and only on the head: history does
    /// not get a second successor (`SpeciesAssertionStore.supersede`'s guard, for its reason).
    ///
    /// - Returns: whether the stamp landed. `false` means the row is not the head any more.
    public func supersede(
        id: UUID,
        with successor: UUID,
        at moment: Date,
        connection: SQLiteConnection
    ) throws -> Bool {
        let statement = try connection.cachedStatement("""
            UPDATE main.tree_locations
               SET superseded_by = :successor, updated_at = :updated
             WHERE id = :id COLLATE NOCASE
               AND superseded_by IS NULL
            """)
        _ = try statement.bind([":successor": successor, ":updated": moment, ":id": id])
        try statement.run()
        let changed = connection.changes > 0
        _ = try statement.reset()
        return changed
    }

    // MARK: - Reading

    /// The position in force. Nil only for a tree with no chain at all, which v23's backfill and
    /// `CommunityTreeStore.insert` together make a tree this table has never heard of.
    public func head(treeID: UUID, connection: SQLiteConnection) throws -> TreeLocation? {
        let statement = try connection.cachedStatement("""
            SELECT * FROM main.tree_locations
             WHERE tree_id = :tree COLLATE NOCASE AND superseded_by IS NULL
             LIMIT 1
            """)
        _ = try statement.bind([":tree": treeID])
        return try statement.fetchOne(Self.decode)
    }

    /// Every position the tree has held, oldest first. The root leads, because it is the oldest
    /// act; a tie on `occurred_at` falls back to `created_at` and then to the id, so the order is
    /// total.
    public func chain(treeID: UUID, connection: SQLiteConnection) throws -> [TreeLocation] {
        let statement = try connection.cachedStatement("""
            SELECT * FROM main.tree_locations
             WHERE tree_id = :tree COLLATE NOCASE
             ORDER BY occurred_at ASC, created_at ASC, id ASC
            """)
        _ = try statement.bind([":tree": treeID])
        return try statement.fetchAll(Self.decode)
    }

    // MARK: - Decoding

    static func decode(_ row: SQLiteRow) throws -> TreeLocation {
        let owner: ContributionOwner
        if let user = try row.uuidIfPresent("user_id") {
            owner = .user(user)
        } else if let device = try row.uuidIfPresent("device_id") {
            owner = .device(device)
        } else {
            owner = .nobody
        }
        return TreeLocation(
            id: try row.uuid("id"),
            treeID: try row.uuid("tree_id"),
            clientUUID: try row.uuid("client_uuid"),
            coordinate: Coordinate(latitude: try row.double("lat"), longitude: try row.double("lon")),
            placement: try row.value("placement", TreePlacement.self),
            locationAccuracyM: try row.doubleIfPresent("location_accuracy_m"),
            owner: owner,
            supersededBy: try row.uuidIfPresent("superseded_by"),
            occurredAt: try row.date("occurred_at"),
            createdAt: try row.date("created_at"),
            updatedAt: try row.date("updated_at")
        )
    }
}
