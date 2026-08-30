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

    /// **How a contribution's `tree_uuid` meets the inventory's, and why it is not `COLLATE NOCASE`.**
    ///
    /// The two sides genuinely differ in case: `UUID.bind` stores Foundation's uppercase canonical
    /// string in `main`, and every seed file `Tools/build_seed.py` writes stores `trees.uuid`
    /// lowercase. So the comparison has to normalize one side or match nothing at all.
    ///
    /// It was `t.uuid = c.tree_uuid COLLATE NOCASE`, which is *correct* and cannot be answered by
    /// an index: `trees.uuid` is `NOT NULL UNIQUE`, so `sqlite_autoindex_trees_1` is a **BINARY**
    /// index and no NOCASE comparison can seek it, whichever operand carries the collation. The
    /// planner's fallback was to drive from the seed instead — `SEARCH t USING INDEX
    /// idx_trees_species_current` over 173,538 trees, probing the contributor's a hundred rows once
    /// per tree, the inverse of the right plan. Cost tracked the size of the *city*, so a brand-new
    /// contributor with one visit paid the same 290 ms as one with forty.
    ///
    /// `lower()` on the **contributions** side leaves the indexed column bare, so the seek is back:
    /// `SCAN c | SEARCH t USING INDEX sqlite_autoindex_trees_1 (uuid=?)`. Measured over the bundled
    /// seed with a 40-tree grove, identical answers: `residentNeighborhood` 73 → 0.2 ms,
    /// `knownSpecies` 116 → 0.2 ms.
    ///
    /// **It is sound only while every inventory file stores its uuids lowercase**, which is a
    /// property of the published files rather than of anything in this repository — so it is
    /// asserted rather than assumed. `DataGates.seedContract` checks it **per arm**, so the bundled
    /// seed and every downloaded pack are each answerable for it, and
    /// `GroveQueryPlanTests.theLowercaseUUIDContractCanFailOnAPack` is the negative control that
    /// shows the check can actually fail. A file that broke it would make this join match nothing —
    /// an empty Grove rather than a slow one — and that is a failure the gate must catch and not
    /// the reader.
    ///
    /// `TreeQueries` and `SpeciesQueries` already carry the same finding for their own joins; this
    /// file is the one that never got the treatment.
    private static let treeJoin = "t.uuid = lower(c.tree_uuid)"

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
        let statement = try connection.cachedStatement(residentNeighborhoodSQL)
        _ = try statement.bind([":device": deviceID.uuidString, ":user": userID?.uuidString])
        return try statement.fetchOne { row in
            (id: try row.int("neighborhood_id"), name: try row.string("neighborhood_name"))
        }
    }

    /// **The statements are properties so the gate can explain the text the app runs.**
    ///
    /// `MapQueryPlanTests`' own header records what happened when they were not: the plans were
    /// pinned against SQL hand-copied into `DataGates.swift`, so changing the real query left the
    /// gate explaining the paraphrase. `GroveQueryPlanTests` reads these, and nothing else builds
    /// them.
    var residentNeighborhoodSQL: String {
        """
        SELECT n.id AS neighborhood_id, n.name AS neighborhood_name
          FROM (\(Self.ownContributions)) c
          JOIN \(seed).trees t ON \(Self.treeJoin)
          JOIN \(seed).neighborhoods n ON n.id = t.neighborhood_id
         WHERE t.deleted_at IS NULL
         GROUP BY n.id
         ORDER BY COUNT(*) DESC, n.name
         LIMIT 1
        """
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
        let statement = try connection.cachedStatement(mostVisitedTreeSQL)
        _ = try statement.bind([":device": deviceID.uuidString, ":user": userID?.uuidString])
        return try statement.fetchOne { row in
            Coordinate(latitude: try row.double("lat"), longitude: try row.double("lon"))
        }
    }

    /// See `residentNeighborhoodSQL` for why this is a property.
    var mostVisitedTreeSQL: String {
        """
        SELECT t.lat AS lat, t.lon AS lon
          FROM (\(Self.ownContributions)) c
          JOIN \(seed).trees t ON \(Self.treeJoin)
         WHERE t.deleted_at IS NULL
         GROUP BY t.uuid
         ORDER BY COUNT(*) DESC, t.uuid
         LIMIT 1
        """
    }

    // MARK: - The ring's denominator

    /// Every distinct species the city inventory records standing in one area.
    ///
    /// `limit: nil` reads it whole, which is the only way the caller gets a `totalCount` to divide
    /// by. A page here would make the denominator too small and therefore the ring too full — the
    /// error would flatter the contributor, which is the direction nobody notices (ERRATA E38).
    ///
    /// Takes an `AlmanacScope` rather than a `neighborhoodID` since R29 reached this screen: for a
    /// `.radius` fallback the rendered predicate is the same bounding-box-plus-squared-distance test
    /// every almanac read uses, so the two screens cannot disagree about what "within a 15-minute
    /// walk" holds. The `.neighborhood` arm renders the same *question* against a different
    /// relation — see below.
    ///
    /// ── Why this reads `trees_area` and not `trees` (RULINGS R84, ERRATA E216-adjacent) ─────────
    /// The obvious spelling of this query is `FROM seed.trees t WHERE \(scope.predicate("t"))`, and
    /// it is what shipped. Under the union `trees` projects `neighborhood_id` as `hx.canon_id` — a
    /// LEFT JOIN output — so that predicate can never reach `idx_trees_neighborhood` inside an arm.
    /// The planner falls back to driving the whole `species` catalog and probing
    /// `idx_trees_species_current` once per species, which walks the city:
    ///
    ///     through `trees`, canonical predicate    92–181 ms   SEARCH t USING idx_trees_species_current
    ///     through `trees_area`, arm-local          2 ms       SEARCH t USING idx_trees_neighborhood
    ///
    /// Same 186 species over the bundled seed's Castro/Upper Market, ~20× apart. `trees_area` is the
    /// `trees_geo` idiom (`InventoryUnionSQL.treesAreaSQL`): a narrow relation carrying each arm's
    /// **own** neighborhood and species keys, with shadowing and soft deletes already applied inside
    /// the arm — which is why neither predicate appears here any more and why a downloaded pack
    /// still hides the bundle's rows on this path.
    ///
    /// ── The subquery is load-bearing and is not a stylistic choice ──────────────────────────────
    /// Written flat — `FROM trees_area t JOIN cypress_hood_xlat hx … JOIN cypress_species_xlat sx …`
    /// — the planner still chose `sx` as the outer loop and went back through
    /// `idx_trees_species_current`, at the same 92 ms; `CROSS JOIN` and scalar-subquery spellings
    /// did too. A `SELECT DISTINCT` subquery cannot be flattened into the outer join, so the area's
    /// species are settled first, as a few hundred arm-local ids, and only then translated. The
    /// plan that costs 2 ms is:
    ///
    ///     CO-ROUTINE a
    ///       SEARCH hx USING PRIMARY KEY (inv=?)
    ///       SEARCH t USING INDEX idx_trees_neighborhood (neighborhood_id=?)
    ///     SEARCH sx USING PRIMARY KEY (inv=? AND local_id=?)
    ///
    /// `GroveQueryPlanTests` pins it, because this is exactly the shape that regressed silently once
    /// already — PR #120 re-pointed it without editing a line of this file.
    ///
    /// The uuid comes off `cypress_species_xlat` rather than a fourth join to `species`: the
    /// translation table carries the canonical species' identity string beside the id it resolves
    /// to, for exactly this reason.
    public func speciesIDs(
        scope: AlmanacScope,
        limit: Int? = nil,
        connection: SQLiteConnection
    ) throws -> Series<UUID> {
        let statement = try connection.cachedStatement(speciesIDsSQL(scope: scope))
        _ = try statement.bind(scope.bindings.merging(
            [":limit": ContributionStore.rowsToRead(for: limit)] as [String: SQLiteBindable?]
        ) { a, _ in a })
        let rows = try statement.fetchAll { try $0.uuid("species_uuid") }
        return ContributionStore.series(rows, limit: limit)
    }

    /// See `residentNeighborhoodSQL` for why this is a property. Takes the scope because the two
    /// arms plan differently and the gate has to explain both.
    func speciesIDsSQL(scope: AlmanacScope) -> String {
        let area: (join: String, predicate: String)
        switch scope {
        case .neighborhood:
            // The canonical id the caller holds names one `(inv, local_id)` pair and only one —
            // neighborhoods are appended and renumbered rather than merged, so `canon_id` is unique
            // across the whole translation table (`InventoryUnionSQL.createNeighborhoods`).
            area = (
                join: """
                JOIN \(seed).cypress_hood_xlat hx
                          ON hx.inv = t.inv AND hx.local_id = t.neighborhood_local
                """,
                predicate: "hx.canon_id = :areaNeighborhood"
            )
        case .radius:
            // `lat`/`lon` are the arm's own columns in this relation as in `trees`, so the box and
            // the squared-distance test are the identical string screen 12 runs.
            area = (join: "", predicate: scope.predicate("t"))
        }
        return """
        SELECT DISTINCT sx.uuid AS species_uuid
          FROM (SELECT DISTINCT t.inv AS inv, t.species_local AS species_local
                  FROM \(seed).trees_area t
                  \(area.join)
                 WHERE \(area.predicate)) a
          JOIN \(seed).cypress_species_xlat sx
            ON sx.inv = a.inv AND sx.local_id = a.species_local
         LIMIT :limit
        """
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
        let statement = try connection.cachedStatement(knownSpeciesSQL)
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

    /// See `residentNeighborhoodSQL` for why this is a property.
    var knownSpeciesSQL: String {
        """
        SELECT s.\(schema.speciesIdentityColumn) AS species_uuid,
               s.scientific_name AS species_scientific_name,
               s.common_name AS species_common_name,
               MIN(c.captured_at) AS first_met_at,
               t.address AS first_met_address
          FROM (\(Self.ownContributions)) c
          JOIN \(seed).trees t ON \(Self.treeJoin)
          JOIN \(seed).species s ON s.id = t.species_current
         WHERE t.deleted_at IS NULL
         GROUP BY s.id
         ORDER BY first_met_at, s.scientific_name
         LIMIT :limit
        """
    }
}
