import Foundation

/// Reads and writes over `main.species_assertions` — the device's half of the species chain
/// (AppSchema v14, BUILD-PLAN §4).
///
/// **Every statement names `main` explicitly, and that is not style.** `species_assertions` is the
/// one table name that exists in *both* attached databases: the bundled seed holds the city's
/// `city_import` rows in its own copy. SQLite would resolve an unqualified name to `main` today —
/// temp, then main, then attachments in order — so the qualifier changes nothing about which table
/// is read. It changes what happens the day somebody writes a query here without thinking about the
/// seed, or the day the resolution order is not what this comment says: a wrong answer from a
/// read-only table full of the city's claims is exactly the failure that would look like working
/// software. The seed's copy is reached through `SeedDatabase.schemaName`, deliberately never from
/// here.
public struct SpeciesAssertionStore {
    public init() {}

    // MARK: - Writing

    /// Appends an assertion. Nothing here supersedes anything: `supersede(_:with:)` is the separate
    /// verb, so a caller that forgets it leaves two heads and the partial unique index refuses the
    /// insert rather than the database quietly holding two current claims.
    public func insert(_ assertion: SpeciesAssertion, connection: SQLiteConnection) throws {
        let statement = try connection.cachedStatement("""
            INSERT INTO main.species_assertions
                (id, tree_uuid, species_uuid, source, confidence, user_id, device_id,
                 superseded_by, created_at, updated_at)
            VALUES (:id, :tree, :species, :source, :confidence, :user, :device,
                    :superseded, :created, :updated)
            """)
        _ = try statement.bind([
            ":id": assertion.id,
            ":tree": assertion.treeID,
            ":species": assertion.speciesID,
            ":source": assertion.source.rawValue,
            ":confidence": assertion.confidence,
            ":user": assertion.assertedByUser,
            ":device": assertion.assertedByDevice,
            ":superseded": assertion.supersededBy,
            ":created": assertion.createdAt,
            ":updated": assertion.updatedAt
        ])
        try statement.run()
        _ = try statement.reset()
    }

    /// Stamps `superseded_by` on the row a correction replaces.
    ///
    /// Guarded on `superseded_by IS NULL` — the head of the chain and nothing else. An assertion
    /// that has already been superseded is history, and history does not get a second successor;
    /// without the guard, two corrections racing would both stamp the same row and the chain would
    /// fork with no way to say which branch the tree took. The engine decides, once, exactly as
    /// `CommunityTreeStore.claimSpecies` puts first-claim-wins in the `WHERE`.
    ///
    /// - Returns: whether the stamp landed. `false` means somebody got there first.
    public func supersede(
        id: UUID,
        with successor: UUID,
        at moment: Date,
        connection: SQLiteConnection
    ) throws -> Bool {
        let statement = try connection.cachedStatement("""
            UPDATE main.species_assertions
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

    /// The claim in force: the one nothing supersedes. Nil when this tree has no assertion in `main`
    /// at all, which is every city row and every community row nobody has named.
    ///
    /// The partial unique index makes "the head" singular; `LIMIT 1` is belt to its braces, not a
    /// choice between candidates.
    public func current(treeID: UUID, connection: SQLiteConnection) throws -> SpeciesAssertion? {
        let statement = try connection.cachedStatement("""
            SELECT * FROM main.species_assertions
             WHERE tree_uuid = :tree COLLATE NOCASE AND superseded_by IS NULL
             LIMIT 1
            """)
        _ = try statement.bind([":tree": treeID])
        return try statement.fetchOne(Self.decode)
    }

    /// The whole chain for a tree, oldest first — what was claimed, and what replaced it.
    public func chain(treeID: UUID, connection: SQLiteConnection) throws -> [SpeciesAssertion] {
        let statement = try connection.cachedStatement("""
            SELECT * FROM main.species_assertions
             WHERE tree_uuid = :tree COLLATE NOCASE
             ORDER BY created_at ASC, id ASC
            """)
        _ = try statement.bind([":tree": treeID])
        return try statement.fetchAll(Self.decode)
    }

    public func assertion(id: UUID, connection: SQLiteConnection) throws -> SpeciesAssertion? {
        let statement = try connection.cachedStatement("""
            SELECT * FROM main.species_assertions WHERE id = :id COLLATE NOCASE
            """)
        _ = try statement.bind([":id": id])
        return try statement.fetchOne(Self.decode)
    }

    // MARK: - Decoding

    static func decode(_ row: SQLiteRow) throws -> SpeciesAssertion {
        var assertion = SpeciesAssertion(
            id: try row.uuid("id"),
            treeID: try row.uuid("tree_uuid"),
            speciesID: try row.uuidIfPresent("species_uuid"),
            source: try row.value("source", SpeciesAssertionSource.self),
            confidence: try row.doubleIfPresent("confidence"),
            owner: try owner(row),
            createdAt: try row.date("created_at"),
            updatedAt: try row.date("updated_at")
        )
        assertion.supersededBy = try row.uuidIfPresent("superseded_by")
        return assertion
    }

    /// At most one of the two columns, both null meaning nobody — the CHECK read back as the fact it
    /// encodes.
    private static func owner(_ row: SQLiteRow) throws -> ContributionOwner {
        if let userID = try row.uuidIfPresent("user_id") { return .user(userID) }
        if let deviceID = try row.uuidIfPresent("device_id") { return .device(deviceID) }
        return .nobody
    }
}
