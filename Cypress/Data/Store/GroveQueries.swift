import Foundation

/// The reads behind screen 08 — the Species tab of My Grove.
///
/// These straddle the two databases: what the contributor did lives in `main` (the app's own
/// contribution tables), what a tree *is* lives in the attached seed. That is why they are here
/// rather than in `ContributionStore` (which owns `main` alone) or `TreeQueries` (which owns the
/// seed alone), and it is also why every join is written explicitly rather than resolved in Swift:
/// screen 08 asks one question per launch and it should cost one statement.
///
/// **Nothing here counts contributions.** Every aggregate is `DISTINCT` over species or `MIN` over
/// dates. There is no `COUNT(*)` in this file that reaches a screen — D1's "no public counts of
/// user actions", and the one place it would be easy to write one by accident is exactly here
/// (ARCHITECTURE §5.1).
public struct GroveQueries {
    private let schema: SeedSchema
    private let seed = SeedDatabase.schemaName

    public init(schema: SeedSchema) {
        self.schema = schema
    }

    /// Every contribution this device (or this account) made, as `(tree_uuid, captured_at)`.
    ///
    /// The four kinds are unioned rather than queried separately because "met a species" is not
    /// specific to one of them: standing in front of a tree with the camera, rating it, taping it
    /// and watering it are all having been there. `UNION ALL` keeps duplicates, which is harmless —
    /// everything downstream is `DISTINCT` or `MIN`.
    ///
    /// Privacy is the shape of the query, exactly as in `ContributionStore.privateReminders`: the
    /// caller states who it is and there is no form of this SQL that returns somebody else's rows
    /// (D11).
    private static let ownContributions = """
        SELECT tree_uuid, captured_at FROM visits
         WHERE deleted_at IS NULL
           AND (device_id = :device COLLATE NOCASE
                OR (:user IS NOT NULL AND user_id = :user COLLATE NOCASE))
        UNION ALL
        SELECT tree_uuid, captured_at FROM observations
         WHERE deleted_at IS NULL
           AND (device_id = :device COLLATE NOCASE
                OR (:user IS NOT NULL AND user_id = :user COLLATE NOCASE))
        UNION ALL
        SELECT tree_uuid, captured_at FROM measurements
         WHERE deleted_at IS NULL
           AND (device_id = :device COLLATE NOCASE
                OR (:user IS NOT NULL AND user_id = :user COLLATE NOCASE))
        UNION ALL
        SELECT tree_uuid, captured_at FROM care_events
         WHERE deleted_at IS NULL
           AND (device_id = :device COLLATE NOCASE
                OR (:user IS NOT NULL AND user_id = :user COLLATE NOCASE))
        """

    // MARK: - Resident neighborhood

    /// A4, verbatim: "'your area' and neighborhood names: SF Analysis Neighborhoods polygons,
    /// **resident neighborhood inferred from most-visited**, overridable in settings."
    ///
    /// So it is inferred rather than asked for, and nothing on screen 08 needs a location
    /// permission. The settings override A4 also promises has no screen yet (BUILD-PLAN §9 M2 puts
    /// the You tab in this milestone), so it is not read here; when it lands it belongs in front of
    /// this call rather than inside it.
    ///
    /// ERRATA E44 records that screen 07 could not use A4's stated mechanism at all: it needs an
    /// area on a fresh install, where no visit history exists, so it derives one from the nearest
    /// inventoried tree. Screen 08 is the opposite case — it has nothing *but* contribution
    /// history, and a grove with none renders nothing anyway (E48) — so here the mechanism A4
    /// actually names is the one that applies.
    ///
    /// Ties break on name so the answer does not flicker between two neighborhoods a contributor
    /// splits their walking between.
    ///
    /// Returns `nil` when the contributor has contributed nothing, or has only contributed to trees
    /// the city has not placed in a neighborhood. Both are "there is no answer", which is a
    /// different thing from zero — and since R29 reached this screen the second case is no longer
    /// terminal: the caller falls back to `mostVisitedTree(userID:deviceID:)` and a stated radius,
    /// so a contributor whose whole record is in a city without polygons still has an area. The
    /// polygon path stays preferred and stays this exact query, which is why San Francisco's answer
    /// cannot move.
    public func residentNeighborhood(
        userID: UUID?,
        deviceID: UUID,
        connection: SQLiteConnection
    ) throws -> (id: Int, name: String)? {
        let statement = try connection.cachedStatement("""
            SELECT n.id AS neighborhood_id, n.name AS neighborhood_name
              FROM (\(Self.ownContributions)) c
              JOIN \(seed).trees t ON t.uuid = c.tree_uuid COLLATE NOCASE
              JOIN \(seed).neighborhoods n ON n.id = t.neighborhood_id
             WHERE t.deleted_at IS NULL
             GROUP BY n.id
             ORDER BY COUNT(*) DESC, n.name
             LIMIT 1
            """)
        _ = try statement.bind([":device": deviceID.uuidString, ":user": userID?.uuidString])
        return try statement.fetchOne { row in
            (id: try row.int("neighborhood_id"), name: try row.string("neighborhood_name"))
        }
    }

    /// The single city-inventory tree this contributor has been at most — R29's fallback center
    /// for screen 08.
    ///
    /// A4's inference is "resident neighborhood inferred from most-visited", and where every
    /// contribution lands on a tree the city placed in no polygon (all 52,788 San Jose rows), the
    /// same inference still has a most-visited *tree* even though it has no most-visited
    /// *neighborhood*. The radius the caller draws around this coordinate is the same inference
    /// with R29's geometry, and it still needs no location permission — the center is where the
    /// contributor's own record says they go, not where they are standing.
    ///
    /// Called only after `residentNeighborhood` returned `nil`, so the polygon path is preferred
    /// exactly as R29 orders the two. Ties break on the tree's uuid for the same reason that query
    /// ties break on name: the answer must not flicker between two trees a contributor splits
    /// their visits between.
    ///
    /// Returns `nil` when the contributor has contributed nothing the seed knows about, which is
    /// the cold start and renders nothing (E48).
    public func mostVisitedTree(
        userID: UUID?,
        deviceID: UUID,
        connection: SQLiteConnection
    ) throws -> Coordinate? {
        let statement = try connection.cachedStatement("""
            SELECT t.lat AS lat, t.lon AS lon
              FROM (\(Self.ownContributions)) c
              JOIN \(seed).trees t ON t.uuid = c.tree_uuid COLLATE NOCASE
             WHERE t.deleted_at IS NULL
             GROUP BY t.uuid
             ORDER BY COUNT(*) DESC, t.uuid
             LIMIT 1
            """)
        _ = try statement.bind([":device": deviceID.uuidString, ":user": userID?.uuidString])
        return try statement.fetchOne { row in
            Coordinate(latitude: try row.double("lat"), longitude: try row.double("lon"))
        }
    }

    // MARK: - The ring's denominator

    /// Every distinct species the city inventory records standing in one area.
    ///
    /// `limit: nil` reads it whole, which is the only way the caller gets a `totalCount` to divide
    /// by. A page here would make the denominator too small and therefore the ring too full — the
    /// error would flatter the contributor, which is the direction nobody notices (ERRATA E38).
    ///
    /// Takes an `AlmanacScope` rather than a `neighborhoodID` since R29 reached this screen: for a
    /// `.neighborhood` scope the rendered predicate is the identical
    /// `t.neighborhood_id = :areaNeighborhood` string, and for the `.radius` fallback it is the
    /// same bounding-box-plus-squared-distance test every almanac read uses, so the two screens
    /// cannot disagree about what "within a 15-minute walk" holds.
    public func speciesIDs(
        scope: AlmanacScope,
        limit: Int? = nil,
        connection: SQLiteConnection
    ) throws -> Series<UUID> {
        let statement = try connection.cachedStatement("""
            SELECT DISTINCT s.\(schema.speciesIdentityColumn) AS species_uuid
              FROM \(seed).trees t
              JOIN \(seed).species s ON s.id = t.species_current
             WHERE \(scope.predicate("t")) AND t.deleted_at IS NULL
             LIMIT :limit
            """)
        _ = try statement.bind(scope.bindings.merging(
            [":limit": ContributionStore.rowsToRead(for: limit)] as [String: SQLiteBindable?]
        ) { a, _ in a })
        let rows = try statement.fetchAll { try $0.uuid("species_uuid") }
        return ContributionStore.series(rows, limit: limit)
    }

    // MARK: - The species the contributor knows

    /// The species this contributor has met, oldest first, with where and when they first met each.
    ///
    /// `MIN(c.captured_at)` with `t.address` selected bare is not sloppy SQL: SQLite documents that
    /// when a query uses `min()` or `max()`, the bare columns come from the row that produced it.
    /// So the address is the address of the tree the contributor was actually standing at the first
    /// time they met the species, which is what the celebration callout says out loud.
    ///
    /// City-inventory trees only, matching `speciesIDs(scope:)` — see `GroveNeighborhood.species`
    /// for why a self-asserted species on a community-added tree does not count as one you know.
    public func knownSpecies(
        userID: UUID?,
        deviceID: UUID,
        limit: Int? = nil,
        connection: SQLiteConnection
    ) throws -> Series<KnownSpecies> {
        let statement = try connection.cachedStatement("""
            SELECT s.\(schema.speciesIdentityColumn) AS species_uuid,
                   s.scientific_name AS species_scientific_name,
                   s.common_name AS species_common_name,
                   MIN(c.captured_at) AS first_met_at,
                   t.address AS first_met_address
              FROM (\(Self.ownContributions)) c
              JOIN \(seed).trees t ON t.uuid = c.tree_uuid COLLATE NOCASE
              JOIN \(seed).species s ON s.id = t.species_current
             WHERE t.deleted_at IS NULL
             GROUP BY s.id
             ORDER BY first_met_at, s.scientific_name
             LIMIT :limit
            """)
        _ = try statement.bind([
            ":device": deviceID.uuidString,
            ":user": userID?.uuidString,
            ":limit": ContributionStore.rowsToRead(for: limit)
        ])
        let rows = try statement.fetchAll { row -> KnownSpecies in
            let scientificName = try row.string("species_scientific_name")
            return KnownSpecies(
                speciesID: try row.uuid("species_uuid"),
                scientificName: scientificName,
                // Same fallback `SpeciesQueries.decodeIfPresent` uses, for the same reason.
                commonName: try row.stringIfPresent("species_common_name") ?? scientificName,
                firstMetAt: try row.date("first_met_at"),
                firstMetAddress: try row.stringIfPresent("first_met_address")
            )
        }
        return ContributionStore.series(rows, limit: limit)
    }
}
