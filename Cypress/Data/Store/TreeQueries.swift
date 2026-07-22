import Foundation

/// How a bounding-box filter reaches the rows.
///
/// Both strategies produce **identical** result sets; they differ only in which index does the
/// work. The seed contract test runs the map queries through both and asserts set equality, which
/// is what proves the R*Tree re-check below is correct.
public enum SpatialIndexStrategy: String, Sendable, CaseIterable {
    /// `idx_trees_lat_lon ON trees(lat, lon, id)`. A plain composite B-tree.
    case coveringIndex
    /// `trees_rtree`, an R*Tree used as a conservative pre-filter.
    case rtreePrefilter

    /// The measured default.
    ///
    /// Against the shipped 195,309-row seed (macOS 15, warm cache, sqlite3 CLI):
    ///
    /// | query | covering index | R*Tree pre-filter |
    /// |---|---|---|
    /// | 1,321 pins in a zoom-16 viewport | 4 ms | 5 ms |
    /// | 199 clusters over the whole city | 104 ms | 1,232 ms |
    ///
    /// The R*Tree loses because `idx_trees_lat_lon` is a *covering* index for exactly these
    /// columns: SQLite answers a clustered viewport without touching the `trees` table at all,
    /// while the R*Tree can only hand back rowids and forces a probe into the table per row. The
    /// planner agrees — given both, it picks `idx_trees_lat_lon` as the outer loop and demotes the
    /// R*Tree to a rowid lookup, which is pure overhead.
    ///
    /// The R*Tree path is kept, exercised, and tested because it is the seed's documented spatial
    /// index and because this ranking is a property of *this* index set: drop `lon` from
    /// `idx_trees_lat_lon` and it inverts.
    public static let `default` = SpatialIndexStrategy.coveringIndex
}

/// Reads over the attached, read-only city inventory.
///
/// Every query here is index-driven; none of them may degrade to a table scan, because all of them
/// sit on a screen the user is dragging with their thumb. `SQLiteConnection.queryPlan(for:)` and the
/// seed contract test pin that.
public struct TreeQueries {
    private let schema: SeedSchema
    private let seed = SeedDatabase.schemaName
    /// See `CypressStore.seedHasSoftDeletedTrees`.
    private let seedHasSoftDeletedTrees: Bool

    public init(schema: SeedSchema, seedHasSoftDeletedTrees: Bool) {
        self.schema = schema
        self.seedHasSoftDeletedTrees = seedHasSoftDeletedTrees
    }

    /// The cluster cell, in screen points, at any zoom. 64 pt keeps badges from overlapping at the
    /// sizes SCREENS.md draws them.
    public static let clusterCellPoints: Double = 64

    // MARK: - Viewport

    /// Map content for a viewport, clustered or not according to A1.
    public func mapContent(
        in viewport: MapViewport,
        strategy: SpatialIndexStrategy = .default,
        connection: SQLiteConnection
    ) throws -> MapContent {
        viewport.shouldCluster
            ? .clusters(try clusters(in: viewport, strategy: strategy, connection: connection))
            : .pins(try pins(in: viewport, strategy: strategy, connection: connection))
    }

    /// Individual pins, zoom ≥ 16.
    ///
    /// ```
    /// SEARCH t USING INDEX idx_trees_lat_lon (lat>? AND lat<?)
    /// SEARCH s USING INTEGER PRIMARY KEY (rowid=?) LEFT-JOIN
    /// ```
    public func pins(
        in viewport: MapViewport,
        strategy: SpatialIndexStrategy = .default,
        connection: SQLiteConnection
    ) throws -> [TreePin] {
        let sql = """
        SELECT t.\(schema.treeIdentityColumn) AS tree_uuid,
               t.lat AS lat, t.lon AS lon,
               t.status AS status, t.source AS source,
               t.verification_state AS verification_state,
               s.\(schema.speciesIdentityColumn) AS species_uuid
        \(bboxSource(strategy, joins: speciesJoin, extraPredicates: "AND t.deleted_at IS NULL"))
         LIMIT :limit
        """

        let statement = try connection.cachedStatement(sql)
        _ = try statement.bind(bindings(for: viewport.bounds))
        _ = try statement.bind(viewport.pinLimit, forName: ":limit")

        return try statement.fetchAll { row in
            TreePin(
                id: try row.uuid("tree_uuid"),
                coordinate: Coordinate(latitude: try row.double("lat"), longitude: try row.double("lon")),
                status: try row.value("status", TreeStatus.self),
                source: try row.value("source", TreeSource.self),
                verificationState: try row.value("verification_state", VerificationState.self),
                speciesID: try row.uuidIfPresent("species_uuid")
            )
        }
    }

    /// Clustered cells, zoom ≤ 15.
    ///
    /// ```
    /// SEARCH t USING COVERING INDEX idx_trees_lat_lon (lat>? AND lat<?)
    /// USE TEMP B-TREE FOR GROUP BY
    /// ```
    ///
    /// **Nothing outside `(lat, lon, id)` may be selected here.** The word `COVERING` in that plan
    /// is the whole point: adding a single column the index does not carry — `MIN(t.uuid)` for a
    /// cluster representative, `t.status` for a filter — costs a table probe per row and takes this
    /// from 104 ms to 355 ms over the whole city. That is why `TreeCluster` has no representative
    /// tree id.
    ///
    /// The `deleted_at IS NULL` predicate is applied only when the seed actually contains a
    /// soft-deleted row (`CypressStore.seedHasSoftDeletedTrees`, measured once at open). That is
    /// not an optimization for its own sake: `deleted_at` is not in `idx_trees_lat_lon`, so
    /// including it costs a table probe for every one of the 195,309 rows and takes the whole-city
    /// cluster query from 104 ms to 427 ms. When no row is soft-deleted the two queries are exactly
    /// equivalent, so the fast one is not an approximation of the slow one.
    public func clusters(
        in viewport: MapViewport,
        strategy: SpatialIndexStrategy = .default,
        connection: SQLiteConnection
    ) throws -> [TreeCluster] {
        let centreLatitude = (viewport.bounds.minLatitude + viewport.bounds.maxLatitude) / 2
        let cell = Self.cellSize(zoom: viewport.zoom, centreLatitude: centreLatitude)
        let deletionFilter = seedHasSoftDeletedTrees ? "AND t.deleted_at IS NULL" : ""

        // CAST(… AS INTEGER) truncates toward zero, which is not floor for negative values. The
        // +90/+180 offsets move every coordinate on Earth into the positive quadrant first, where
        // truncation *is* floor, so a cell never straddles the equator or the prime meridian.
        let sql = """
        SELECT CAST((t.lat + 90.0) / :latCell AS INTEGER) AS cell_y,
               CAST((t.lon + 180.0) / :lonCell AS INTEGER) AS cell_x,
               COUNT(*) AS member_count,
               AVG(t.lat) AS centre_lat,
               AVG(t.lon) AS centre_lon
        \(bboxSource(strategy, joins: "", extraPredicates: deletionFilter))
         GROUP BY cell_y, cell_x
        """

        let statement = try connection.cachedStatement(sql)
        _ = try statement.bind(bindings(for: viewport.bounds))
        _ = try statement.bind([":latCell": cell.latitude, ":lonCell": cell.longitude])

        return try statement.fetchAll { row in
            let cellY = try row.int("cell_y")
            let cellX = try row.int("cell_x")
            return TreeCluster(
                id: "z\(viewport.zoom):\(cellY):\(cellX)",
                coordinate: Coordinate(
                    latitude: try row.double("centre_lat"),
                    longitude: try row.double("centre_lon")
                ),
                count: try row.int("member_count")
            )
        }
    }

    /// Cluster cell size in degrees, sized so a cell is `clusterCellPoints` square on screen.
    ///
    /// A web-mercator pixel spans `360 / (256 · 2^zoom)` degrees of longitude everywhere, and
    /// `cos(latitude)` times that in latitude — hence two different cell sizes.
    static func cellSize(zoom: Int, centreLatitude: Double) -> (latitude: Double, longitude: Double) {
        let clampedZoom = max(0, min(zoom, 22))
        let degreesPerPoint = 360.0 / (256.0 * pow(2.0, Double(clampedZoom)))
        let longitude = degreesPerPoint * clusterCellPoints
        let latitude = longitude * max(cos(centreLatitude * .pi / 180), 0.05)
        return (latitude: latitude, longitude: longitude)
    }

    // MARK: - Nearest N

    /// The what-tree-is-this shortlist: `GET /trees?near=lng,lat&radius=m`, ordered by distance.
    ///
    /// ```
    /// SEARCH t USING INDEX idx_trees_lat_lon (lat>? AND lat<?)
    /// USE TEMP B-TREE FOR ORDER BY
    /// ```
    ///
    /// Ordering is by *squared* distance with a `cos(latitude)` correction on the longitude term —
    /// no `sqrt`, no trigonometry per row, and monotonically identical to true distance over a
    /// neighbourhood-sized box. The metres each row reports are then computed exactly, once per
    /// returned row, by `Coordinate.distance(to:)`, so the number the UI renders is the real one
    /// and the list is re-sorted on it.
    ///
    /// **The box is a pre-filter and the circle is the answer.** `BoundingBox(around:radiusM:)`
    /// builds a square whose half-width is the radius on both axes, so it circumscribes the circle
    /// and admits a tree on the diagonal out to `radius·√2` — 14.1 m for a 10 m ask. This query
    /// used to return those, and `LocalAPI.addTree` reads a non-empty candidate list as the 10 m
    /// proximity conflict: standing 12 m from an inventoried tree, adding a genuinely new one came
    /// back `conflict`, which is not retryable, so the outbox item went terminal on the spot and
    /// the contributor was refused for good — with a real nearby tree named as the reason, so the
    /// error looked right (ERRATA E35). The exact re-check below is the same shape the R*Tree path
    /// already uses on `bboxSource`: a conservative index filter, then the true predicate.
    ///
    /// `LIMIT` runs before the re-check, which is safe **because the ordering is by distance**: any
    /// row the circle rejects is farther than every row it keeps.
    ///
    /// `speciesID` narrows the answer to one species — screen 07 §6's `Nearby individuals`, which
    /// is the same question the shortlist asks with the species already known. It is an optional
    /// parameter rather than a second query because the box, the ordering, the `LIMIT`-then-recheck
    /// and the exact-distance pass are all the same work, and a copy of them would be a second
    /// place for the ERRATA E35 bug to come back.
    public func nearest(
        to coordinate: Coordinate,
        radiusM: Double,
        limit: Int,
        speciesID: UUID? = nil,
        strategy: SpatialIndexStrategy = .default,
        connection: SQLiteConnection
    ) throws -> [NearbyTree] {
        let bounds = BoundingBox(around: coordinate, radiusM: radiusM)
        // Longitude degrees are shorter than latitude degrees by cos(lat); squaring the ratio makes
        // the two terms comparable before they are added.
        let longitudeWeight = pow(cos(coordinate.latitude * .pi / 180), 2)

        // A `LEFT JOIN` with a predicate on the right-hand table is an inner join, which is what
        // narrowing to one species means: a tree the city recorded no species for is not one of
        // them.
        let speciesPredicate = speciesID == nil
            ? ""
            : "AND s.\(schema.speciesIdentityColumn) = :speciesUUID COLLATE NOCASE"

        let sql = """
        SELECT \(treeColumns),
               s.\(schema.speciesIdentityColumn) AS species_uuid,
               s.scientific_name AS species_scientific_name,
               s.common_name AS species_common_name,
               s.id_tips AS species_id_tips
        \(bboxSource(strategy, joins: speciesJoin, extraPredicates: "AND t.deleted_at IS NULL \(speciesPredicate)"))
         ORDER BY (t.lat - :lat) * (t.lat - :lat)
                + (t.lon - :lon) * (t.lon - :lon) * :lonWeight
         LIMIT :limit
        """

        let statement = try connection.cachedStatement(sql)
        _ = try statement.bind(bindings(for: bounds))
        _ = try statement.bind([
            ":lat": coordinate.latitude,
            ":lon": coordinate.longitude,
            ":lonWeight": longitudeWeight,
            ":limit": limit
        ])
        if let speciesID {
            _ = try statement.bind(speciesID.uuidString, forName: ":speciesUUID")
        }

        let rows = try statement.fetchAll { row -> NearbyTree in
            let tree = try Self.decodeTree(row)
            return NearbyTree(
                tree: tree,
                distanceM: coordinate.distance(to: tree.coordinate),
                speciesScientificName: try row.stringIfPresent("species_scientific_name"),
                speciesCommonName: try row.stringIfPresent("species_common_name"),
                tell: Self.firstIDTip(try row.stringIfPresent("species_id_tips"))
            )
        }
        return rows
            .filter { $0.distanceM <= radiusM }
            .sorted { $0.distanceM < $1.distanceM }
    }

    // MARK: - Profile

    /// One inventory row plus its species, neighbourhood, and site lineage.
    public struct TreeRecord: Sendable {
        public let tree: Tree
        public let species: Species?
        public let neighborhoodName: String?
        public let siteLineageID: UUID?
    }

    /// `GET /trees/{id}`, the inventory half. `LocalAPI` adds the contributions.
    ///
    /// ```
    /// SEARCH t USING INDEX sqlite_autoindex_trees_1 (uuid=?)
    /// SEARCH s USING INTEGER PRIMARY KEY (rowid=?) LEFT-JOIN
    /// SEARCH n USING INTEGER PRIMARY KEY (rowid=?) LEFT-JOIN
    /// SEARCH lin USING INTEGER PRIMARY KEY (rowid=?) LEFT-JOIN
    /// ```
    public func tree(id: UUID, connection: SQLiteConnection) throws -> TreeRecord? {
        let sql = """
        SELECT \(treeColumns),
               \(SpeciesQueries.projection(identityColumn: schema.speciesIdentityColumn)),
               n.name AS neighborhood_name,
               lin.\(schema.treeIdentityColumn) AS site_lineage_uuid
          FROM \(seed).trees t
          LEFT JOIN \(seed).species s ON s.id = t.species_current
          LEFT JOIN \(seed).neighborhoods n ON n.id = t.neighborhood_id
          LEFT JOIN \(seed).trees lin ON lin.id = t.site_lineage
         WHERE t.\(schema.treeIdentityColumn) = :uuid COLLATE NOCASE
        """

        let statement = try connection.cachedStatement(sql)
        _ = try statement.bind(id.uuidString, forName: ":uuid")

        return try statement.fetchOne { row in
            TreeRecord(
                tree: try Self.decodeTree(row),
                species: try SpeciesQueries.decodeIfPresent(row),
                neighborhoodName: try row.stringIfPresent("neighborhood_name"),
                siteLineageID: try row.uuidIfPresent("site_lineage_uuid")
            )
        }
    }

    /// Whether a tree id exists in the inventory. Checked before accepting a contribution, since no
    /// foreign key can span the attached seed (see `AppSchema`).
    public func exists(id: UUID, connection: SQLiteConnection) throws -> Bool {
        let statement = try connection.cachedStatement(
            "SELECT 1 AS present FROM \(seed).trees WHERE \(schema.treeIdentityColumn) = :uuid COLLATE NOCASE"
        )
        _ = try statement.bind(id.uuidString, forName: ":uuid")
        return try statement.fetchOne { _ in true } ?? false
    }

    // MARK: - SQL fragments

    private var speciesJoin: String {
        "LEFT JOIN \(seed).species s ON s.id = t.species_current"
    }

    /// The `FROM … JOIN … WHERE` clause for a bounding box, per strategy.
    ///
    /// **The exact re-check is not optional on the R*Tree path.** SQLite's rtree module stores
    /// coordinates as 32-bit floats and rounds every rectangle *outward*, so it is a conservative
    /// filter: it never drops a true hit, but it returns rows up to ~1.7 m outside the requested
    /// box. `t.lat BETWEEN … AND t.lon BETWEEN …` is what makes the answer exact. It is present on
    /// both paths, which is what lets the contract test assert the two are interchangeable.
    private func bboxSource(
        _ strategy: SpatialIndexStrategy,
        joins: String,
        extraPredicates: String
    ) -> String {
        switch strategy {
        case .coveringIndex:
            return """
              FROM \(seed).trees t
              \(joins)
             WHERE t.lat BETWEEN :minLat AND :maxLat
               AND t.lon BETWEEN :minLon AND :maxLon
               \(extraPredicates)
            """
        case .rtreePrefilter:
            return """
              FROM \(seed).trees_rtree r
              JOIN \(seed).trees t ON t.\(schema.rtreeJoinColumn) = r.id
              \(joins)
             WHERE r.max_lat >= :minLat AND r.min_lat <= :maxLat
               AND r.max_lon >= :minLon AND r.min_lon <= :maxLon
               AND t.lat BETWEEN :minLat AND :maxLat
               AND t.lon BETWEEN :minLon AND :maxLon
               \(extraPredicates)
            """
        }
    }

    private func bindings(for bounds: BoundingBox) -> [String: SQLiteBindable?] {
        [
            ":minLat": bounds.minLatitude,
            ":maxLat": bounds.maxLatitude,
            ":minLon": bounds.minLongitude,
            ":maxLon": bounds.maxLongitude
        ]
    }

    /// The `trees` projection, aliased to shape-independent names so the decoder never has to know
    /// which identity model the file on disk uses.
    private var treeColumns: String {
        """
        t.\(schema.treeIdentityColumn) AS tree_uuid,
               t.external_ref AS external_ref, t.source AS source,
               t.lat AS lat, t.lon AS lon, t.address AS address, t.site_type AS site_type,
               t.status AS status, t.planted_year AS planted_year,
               t.dbh_city_cm_min AS dbh_city_cm_min, t.dbh_city_cm_max AS dbh_city_cm_max,
               t.verification_state AS verification_state,
               t.created_at AS created_at, t.updated_at AS updated_at, t.deleted_at AS deleted_at
        """
    }

    // MARK: - Decoding

    /// Decodes a `Tree` from any projection built on `treeColumns`.
    ///
    /// `species_uuid` and `site_lineage_uuid` are read leniently: some projections select them and
    /// some do not, and "this query did not ask for it" is not a contract break. Every column that
    /// `treeColumns` does select is read strictly, so a genuine schema drift still throws.
    static func decodeTree(_ row: SQLiteRow) throws -> Tree {
        let minimum = try row.intIfPresent("dbh_city_cm_min")
        let maximum = try row.intIfPresent("dbh_city_cm_max")
        // The seed's CHECK guarantees the two are NULL together; `IntRange` rejects an empty range,
        // so a degenerate bucket resolves to nil rather than to a range claiming a point value.
        let dbhRange: IntRange? = {
            guard let minimum, let maximum else { return nil }
            return IntRange(lowerBound: minimum, upperBound: maximum)
        }()

        return Tree(
            id: try row.uuid("tree_uuid"),
            // INTEGER in the current seed, TEXT in the original; sqlite renders either as text.
            externalRef: try row.stringIfPresent("external_ref"),
            source: try row.value("source", TreeSource.self),
            coordinate: Coordinate(latitude: try row.double("lat"), longitude: try row.double("lon")),
            address: try row.stringIfPresent("address"),
            siteType: try row.stringIfPresent("site_type"),
            // The seed keys neighborhoods by `name`, not by a uuid, so there is no id to carry.
            // `TreeProfile.neighborhoodName` is where the neighbourhood actually surfaces.
            neighborhoodID: nil,
            status: try row.value("status", TreeStatus.self),
            speciesCurrentID: row.optionalUUID("species_uuid"),
            plantedYear: try row.intIfPresent("planted_year"),
            dbhCityCmRange: dbhRange,
            siteLineage: row.optionalUUID("site_lineage_uuid"),
            verificationState: try row.value("verification_state", VerificationState.self),
            createdAt: try row.date("created_at"),
            updatedAt: try row.date("updated_at"),
            deletedAt: try row.dateIfPresent("deleted_at")
        )
    }

    /// The one `id_tip` a shortlist row shows as its tell (D6).
    static func firstIDTip(_ json: String?) -> IDTip? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([IDTip].self, from: data).first
    }
}

extension SQLiteRow {
    /// A UUID that may or may not be in the projection at all. Absent and NULL both read as nil.
    func optionalUUID(_ column: String) -> UUID? {
        (try? uuidIfPresent(column)) ?? nil
    }

    /// A string that may or may not be in the projection at all.
    func optionalString(_ column: String) -> String? {
        (try? stringIfPresent(column)) ?? nil
    }
}
