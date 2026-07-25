import Foundation

/// How a bounding-box filter reaches the rows.
///
/// Both strategies produce **identical** result sets; they differ only in which index does the
/// work. `CypressTests/MapQueryPlanTests` runs every map query through both and asserts set
/// equality, which is what proves the R*Tree re-check below is correct.
///
/// That test exists as of ERRATA E130. Before it this paragraph named the seed contract test, which
/// checked no such thing — `SeedContractTests` held one zoom-threshold assertion and nothing else,
/// and the only place both strategies were compared was `DataGates`, over one viewport, on the pin
/// query alone.
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
    /// One of two queries, chosen by `MapViewport.markerCellPoints`. Without a cell, every pin in the
    /// box up to `pinLimit`:
    ///
    /// ```
    /// SEARCH t USING INDEX idx_trees_lat_lon (lat>? AND lat<?)
    /// SEARCH s USING INTEGER PRIMARY KEY (rowid=?) LEFT-JOIN
    /// ```
    ///
    /// With one, the grid decides — but only when it has to.
    ///
    /// **The cell is a ceiling, not a rule.** `markerCells` counts what is in the box while it grids
    /// it, at no extra cost, so the cheap question comes first: if every tree in view would fit
    /// inside `pinLimit` anyway, the un-thinned query runs and nothing is thinned. That is the answer
    /// at the zooms the app opens at, where the whole problem never existed; the grid takes over
    /// where the count runs away from the screen. Gridding unconditionally was the obvious version
    /// and it is wrong — it pays for a performance problem in the two places that never had one.
    public func pins(
        in viewport: MapViewport,
        strategy: SpatialIndexStrategy = .default,
        connection: SQLiteConnection
    ) throws -> [TreePin] {
        if let cellPoints = viewport.markerCellPoints {
            let cells = try markerCells(
                in: viewport,
                cellPoints: cellPoints,
                strategy: strategy,
                connection: connection
            )
            let treesInView = cells.reduce(0) { $0 + $1.memberCount }
            if treesInView > viewport.pinLimit {
                return try pins(rowIDs: cells.map(\.rowID), connection: connection)
            }
        }

        let statement = try connection.cachedStatement(everyPinSQL(strategy))
        _ = try statement.bind(bindings(for: viewport.bounds))
        _ = try statement.bind(viewport.pinLimit, forName: ":limit")
        return try statement.fetchAll(Self.decodePin)
    }

    /// One tree's rowid per occupied grid cell, and how many trees that cell stands for — the whole
    /// of the level-of-detail rule, and the reason the map's answer stopped growing with the viewport
    /// (ERRATA E130).
    ///
    /// ```
    /// SEARCH t USING COVERING INDEX idx_trees_lat_lon (lat>? AND lat<?)
    /// USE TEMP B-TREE FOR GROUP BY
    /// ```
    ///
    /// **It is the cluster query's plan, and it must stay that way.** `MIN(t.rowid)` and `COUNT(*)`
    /// are the only things asked for beyond the grouping keys, and a rowid is carried by every entry
    /// of every index, so this reads `idx_trees_lat_lon` and never touches the table. Ask it for
    /// `t.uuid` instead and the rowid is no longer enough — that is a table probe per candidate row,
    /// the same 3.4× that keeps a representative tree id out of `TreeCluster`. The winners are
    /// hydrated by rowid afterwards, a few hundred integer-primary-key lookups, which is why the
    /// two-step is cheaper than the one-step it would replace.
    ///
    /// `COUNT(*)` is free here — the rows are already grouped — and it is what lets `pins` decide
    /// whether to thin at all.
    ///
    /// `deleted_at IS NULL` is omitted on the same terms and for the same measured reason as in
    /// `clusters`: it is not in the index, so on a seed with no soft-deleted row it would cost a
    /// probe per row to change nothing. `pins(rowIDs:connection:)` applies it unconditionally, so a
    /// soft-deleted tree that wins a cell is dropped there rather than drawn — the cell goes empty,
    /// which is the honest picture and not a hole anyone can notice at one pin in 195,309.
    ///
    /// **Which tree wins its cell is arbitrary, and deliberately stable.** The lowest rowid in the
    /// cell is the seed's own insertion order, which says nothing about the tree; what matters is
    /// that the grid is absolute rather than relative to the viewport's corner (the `+90`/`+180`
    /// offsets, as in `clusters`), so the same tree keeps winning the same cell as the user pans and
    /// no pin flickers or re-animates under the drag. Preferring a status — drawing the amber
    /// needs-care pin over its neighbours — would mean reading `t.status`, which is the table probe
    /// this query exists to avoid. The shipped seed carries no `declining` tree at all, so there is
    /// no amber pin to lose today; when the curated pipeline gives it one, the honest fix is a second
    /// query for just those trees, not a column added here.
    func markerCells(
        in viewport: MapViewport,
        cellPoints: Double,
        strategy: SpatialIndexStrategy = .default,
        connection: SQLiteConnection
    ) throws -> [(rowID: Int64, memberCount: Int)] {
        let centreLatitude = (viewport.bounds.minLatitude + viewport.bounds.maxLatitude) / 2
        let cell = Self.cellSize(zoom: viewport.zoom, centreLatitude: centreLatitude, points: cellPoints)

        let statement = try connection.cachedStatement(markerCellsSQL(strategy))
        _ = try statement.bind(bindings(for: viewport.bounds))
        _ = try statement.bind([":latCell": cell.latitude, ":lonCell": cell.longitude])
        return try statement.fetchAll {
            (rowID: try $0.int64("marker_rowid"), memberCount: try $0.int("member_count"))
        }
    }

    /// The winners, as pins.
    ///
    /// ```
    /// SEARCH t USING INTEGER PRIMARY KEY (rowid=?)
    /// LIST SUBQUERY 1 · SCAN json_each VIRTUAL TABLE INDEX 1:
    /// SEARCH s USING INTEGER PRIMARY KEY (rowid=?) LEFT-JOIN
    /// ```
    ///
    /// The rowids arrive through `json_each` rather than as an interpolated `IN (…)` list, so the
    /// statement text is constant and `cachedStatement` holds one prepared copy of it across every
    /// camera change instead of compiling a fresh one per pan.
    private func pins(rowIDs: [Int64], connection: SQLiteConnection) throws -> [TreePin] {
        guard !rowIDs.isEmpty else { return [] }
        let statement = try connection.cachedStatement("""
        SELECT \(pinColumns)
          FROM \(seed).trees t
          \(speciesJoin)
         WHERE t.rowid IN (SELECT value FROM json_each(:rowids))
           AND t.deleted_at IS NULL
        """)
        _ = try statement.bind("[\(rowIDs.map(String.init).joined(separator: ","))]", forName: ":rowids")
        return try statement.fetchAll(Self.decodePin)
    }

    // MARK: - The statements, as text
    //
    // The three map statements are built by named methods rather than inline, so the plan gate can
    // explain the SQL the app actually runs. It used to explain SQL hand-copied into `DataGates`,
    // which is a gate on a paraphrase (ERRATA E130 — see `CypressTests/MapQueryPlanTests`).

    /// Every pin in the box, up to `pinLimit`.
    func everyPinSQL(_ strategy: SpatialIndexStrategy) -> String {
        """
        SELECT \(pinColumns)
        \(bboxSource(strategy, joins: speciesJoin, extraPredicates: "AND t.deleted_at IS NULL"))
         LIMIT :limit
        """
    }

    /// `markerCells`' statement. `CAST(… AS INTEGER)` truncates toward zero and the `+90`/`+180`
    /// offsets make that floor — see `clustersSQL`, which grids the same way at 64 points.
    ///
    /// No `LIMIT`, deliberately: the row count is already bounded by the viewport's area in screen
    /// points divided by the cell's, at every zoom. A `LIMIT` on this `GROUP BY` would truncate in
    /// cell order, which is latitude order, which is the strip along the bottom edge that this whole
    /// rule exists to stop drawing.
    func markerCellsSQL(_ strategy: SpatialIndexStrategy) -> String {
        """
        SELECT MIN(t.rowid) AS marker_rowid, COUNT(*) AS member_count
        \(bboxSource(strategy, joins: "", extraPredicates: seedHasSoftDeletedTrees ? "AND t.deleted_at IS NULL" : ""))
         GROUP BY CAST((t.lat + 90.0) / :latCell AS INTEGER),
                  CAST((t.lon + 180.0) / :lonCell AS INTEGER)
        """
    }

    /// `clusters`' statement. See that method for why nothing outside `(lat, lon, rowid)` may join
    /// this projection.
    ///
    /// `CAST(… AS INTEGER)` truncates toward zero, which is not floor for negative values. The
    /// `+90`/`+180` offsets move every coordinate on Earth into the positive quadrant first, where
    /// truncation *is* floor, so a cell never straddles the equator or the prime meridian.
    func clustersSQL(_ strategy: SpatialIndexStrategy) -> String {
        """
        SELECT CAST((t.lat + 90.0) / :latCell AS INTEGER) AS cell_y,
               CAST((t.lon + 180.0) / :lonCell AS INTEGER) AS cell_x,
               COUNT(*) AS member_count,
               AVG(t.lat) AS centre_lat,
               AVG(t.lon) AS centre_lon
        \(bboxSource(strategy, joins: "", extraPredicates: seedHasSoftDeletedTrees ? "AND t.deleted_at IS NULL" : ""))
         GROUP BY cell_y, cell_x
        """
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
        let statement = try connection.cachedStatement(clustersSQL(strategy))
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

    /// Cell size in degrees, sized so a cell is `points` square on screen. `clusterCellPoints` for a
    /// cluster badge; `MapViewport.markerCellPoints` for one drawn pin.
    ///
    /// A web-mercator pixel spans `360 / (256 · 2^zoom)` degrees of longitude everywhere, and
    /// `cos(latitude)` times that in latitude — hence two different cell sizes.
    ///
    /// ── Why the latitude is snapped to its degree band, which is not a rounding convenience ────
    /// The callers grid with `CAST((lat + 90) / latCell AS INTEGER)`: the origin is the **south
    /// pole**, so at San Francisco a cell index is around 171,000. Feed this the viewport's own
    /// centre and `latCell` moves a little with every pan — `cos` is continuous — and a relative
    /// change of one part in five thousand slides an index of 171,000 by more than thirty whole
    /// cells. The grid is then not absolute at all: it re-lays itself under the camera, and every
    /// cell hands its pin to a different tree.
    ///
    /// It is measurable. `CypressTests/MapQueryPlanTests` pans the box by a quarter of its height and
    /// compares the interior pin for pin: with the raw centre latitude, **67 of about 190** changed
    /// identity — a third of the map picking a new tree per refetch, which is the flicker
    /// `TreeCluster.id`'s own comment promises does not happen. That comment was written about the
    /// `+90`/`+180` offsets, which do make the grid independent of the *box's corner*; nobody noticed
    /// that the cell **size** was still a function of the box (ERRATA E130). The cluster badges have
    /// had it since they were written.
    ///
    /// Snapping to the middle of the whole-degree band fixes it, because no pan of a city-sized map
    /// crosses one: every viewport over San Francisco computes `cos(37.5°)` and gets exactly the same
    /// grid. `cos` varies 1.4 % across a degree of latitude here, so a cell is 44 × 44.1 pt instead of
    /// 44 × 44.0 — a difference nothing can see. What is left is one re-keying for a map panned
    /// across a whole degree of latitude, which this app cannot do.
    static func cellSize(
        zoom: Int,
        centreLatitude: Double,
        points: Double = clusterCellPoints
    ) -> (latitude: Double, longitude: Double) {
        let clampedZoom = max(0, min(zoom, 22))
        let degreesPerPoint = 360.0 / (256.0 * pow(2.0, Double(clampedZoom)))
        let longitude = degreesPerPoint * points
        let band = centreLatitude.rounded(.down) + 0.5
        let latitude = longitude * max(cos(band * .pi / 180), 0.05)
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

    /// The four facts a `TreePin` carries, plus the species it belongs to. Shared by both pin
    /// queries, so the un-thinned and the gridded answers cannot drift in what they select.
    private var pinColumns: String {
        """
        t.\(schema.treeIdentityColumn) AS tree_uuid,
               t.lat AS lat, t.lon AS lon,
               t.status AS status, t.source AS source,
               t.verification_state AS verification_state,
               s.\(schema.speciesIdentityColumn) AS species_uuid
        """
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

    /// Decodes a `TreePin` from any projection built on `pinColumns`.
    static func decodePin(_ row: SQLiteRow) throws -> TreePin {
        TreePin(
            id: try row.uuid("tree_uuid"),
            coordinate: Coordinate(latitude: try row.double("lat"), longitude: try row.double("lon")),
            status: try row.value("status", TreeStatus.self),
            source: try row.value("source", TreeSource.self),
            verificationState: try row.value("verification_state", VerificationState.self),
            speciesID: try row.uuidIfPresent("species_uuid")
        )
    }

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
