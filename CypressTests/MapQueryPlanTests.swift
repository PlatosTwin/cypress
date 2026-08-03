import Foundation
import Testing
@testable import Cypress

/// **The gates two comments promised and nobody wrote.**
///
/// `SQLiteConnection.queryPlan(for:)` says a plan that degrades to `SCAN trees` is a 195,309-row
/// table scan on the map's critical path and "must fail CI, not the field". `TreeQueries`'
/// `SpatialIndexStrategy` said the seed contract test ran the map queries through both strategies
/// and asserted set equality. Both point at `SeedContractTests`, which reaches
/// `DataGates.seedContract` — and something is there, which is why this is a gap rather than a hole:
///
/// - The plans **are** explained, but over SQL **hand-copied into `DataGates.swift`**, not the text
///   `TreeQueries` emits. Change the real query and the gate goes on explaining the paraphrase.
/// - The strategies **are** compared, but on `pins` alone, over one viewport. `clusters` was never
///   run through both, and the marker grid did not exist.
///
/// So the tuning those comments describe — which index answers the viewport, and which columns may
/// be asked for without turning a covering index walk into a probe per row — was pinned against a
/// copy of itself. These are the gates ERRATA E130 installs: the same two rules `DataGates` states,
/// over the statements the app actually runs.
@Suite("Map query plans")
struct MapQueryPlanTests {

    /// A block of the Mission wide enough that the planner has a real range to choose an index for.
    private static let bounds = BoundingBox(
        minLatitude: 37.7647, maxLatitude: 37.7823,
        minLongitude: -122.4291, maxLongitude: -122.4189
    )

    private static func store() async throws -> CypressStore {
        let seedURL = try #require(SeedContractTests.seedURL, "no seed database; set CYPRESS_SEED_PATH")
        return try await CypressStore.inMemory(seedURL: seedURL)
    }

    private static func queries(_ store: CypressStore) throws -> TreeQueries {
        let schema = try #require(store.seed, "the store opened without a seed attached")
        return TreeQueries(schema: schema, seedHasSoftDeletedTrees: store.seedHasSoftDeletedTrees)
    }

    /// The gridded viewport screen 01 actually asks for: A1's pin side, with the level-of-detail cell
    /// `MapModel` passes.
    private static func viewport(zoom: Int = 16, gridded: Bool = true) -> MapViewport {
        MapViewport(
            bounds: bounds,
            zoom: zoom,
            pinLimit: MapModel.pinLimit,
            markerCellPoints: gridded ? MapModel.markerCellPoints : nil
        )
    }

    // MARK: - Plans

    /// Both rules, over every statement the map runs, on both strategies.
    ///
    /// The expected index is the same for all of them because there is only one spatial index worth
    /// using here — that ranking is measured in `SpatialIndexStrategy.default`, and the R*Tree path
    /// reaches `idx_trees_lat_lon` too, as the exact re-check that makes its conservative pre-filter
    /// correct.
    @Test("every map statement resolves through idx_trees_lat_lon and never scans a table")
    func plansStayIndexed() async throws {
        let store = try await Self.store()
        let queries = try Self.queries(store)

        try await store.queue.read { connection in
            for strategy in SpatialIndexStrategy.allCases {
                let statements: [(String, String)] = [
                    ("every pin in the box", queries.everyPinSQL(strategy)),
                    ("one pin per marker cell", queries.markerCellsSQL(strategy)),
                    ("cluster badges", queries.clustersSQL(strategy))
                ]
                for (label, sql) in statements {
                    let steps = try connection.queryPlan(for: sql)
                    let plan = steps.joined(separator: " | ")
                    #expect(
                        plan.contains("idx_trees_lat_lon"),
                        "\(label) (\(strategy.rawValue)) does not use idx_trees_lat_lon: \(plan)"
                    )
                    // A `SCAN` step is only acceptable when it walks an index that answers the query
                    // outright. A bare `SCAN trees` is 195,309 rows under the user's thumb.
                    let tableScans = steps.filter {
                        $0.contains("SCAN") && !$0.contains("COVERING INDEX") && !$0.contains("VIRTUAL TABLE")
                    }
                    #expect(
                        tableScans.isEmpty,
                        "\(label) (\(strategy.rawValue)) degraded to a table scan: \(tableScans.joined(separator: " | "))"
                    )
                }
            }
        }
    }

    /// **The word `COVERING` is the whole tuning, and only two statements are entitled to it.**
    ///
    /// `clusters` and `markerCells` group tens of thousands of rows and ask for nothing outside
    /// `(lat, lon, rowid)`, so SQLite answers them from the index without touching the table. Adding
    /// one column it does not carry costs a probe per row: `MIN(t.uuid)` for a cluster representative
    /// takes the whole-city query from 104 ms to 355 ms, and `t.deleted_at` takes it to 427 ms. Both
    /// are recorded in prose on those methods; this is the assertion that stops a future column
    /// quietly undoing them.
    @Test("the two grouping queries answer from the index alone")
    func groupingQueriesAreCovering() async throws {
        let store = try await Self.store()
        let queries = try Self.queries(store)

        try await store.queue.read { connection in
            for (label, sql) in [
                ("cluster badges", queries.clustersSQL(.coveringIndex)),
                ("one pin per marker cell", queries.markerCellsSQL(.coveringIndex))
            ] {
                let plan = try connection.queryPlan(for: sql).joined(separator: " | ")
                #expect(
                    plan.contains("COVERING INDEX idx_trees_lat_lon"),
                    "\(label) stopped being covered by the index: \(plan)"
                )
            }
        }
    }

    // MARK: - The two strategies are interchangeable

    /// What makes the R*Tree path safe to keep: it stores 32-bit floats and rounds every rectangle
    /// *outward*, so it is a conservative pre-filter, and the exact `lat`/`lon` re-check on both
    /// paths is what turns that back into the same answer. Asserted over all three map queries, which
    /// is what `SpatialIndexStrategy`'s own comment has claimed since it was written.
    @Test("both spatial strategies return the same trees")
    func strategiesAgree() async throws {
        let store = try await Self.store()
        let queries = try Self.queries(store)

        try await store.queue.read { connection in
            let plain = Self.viewport(gridded: false)
            let viaIndex = try queries.pins(in: plain, strategy: .coveringIndex, connection: connection)
            let viaRTree = try queries.pins(in: plain, strategy: .rtreePrefilter, connection: connection)
            #expect(!viaIndex.isEmpty, "the test viewport returned no pins")
            #expect(
                Set(viaIndex.map(\.id)) == Set(viaRTree.map(\.id)),
                "pins disagree: \(viaIndex.count) via the covering index, \(viaRTree.count) via the R*Tree"
            )

            // The grid too: it picks by `MIN(rowid)` within a cell, and the cell is absolute, so the
            // two strategies must pick the *same* representative and not merely the same count.
            let gridded = Self.viewport()
            let gridIndex = try queries.pins(in: gridded, strategy: .coveringIndex, connection: connection)
            let gridRTree = try queries.pins(in: gridded, strategy: .rtreePrefilter, connection: connection)
            #expect(!gridIndex.isEmpty, "the gridded viewport returned no pins")
            #expect(
                Set(gridIndex.map(\.id)) == Set(gridRTree.map(\.id)),
                "the grid disagrees: \(gridIndex.count) via the covering index, \(gridRTree.count) via the R*Tree"
            )

            let clusterViewport = MapViewport(bounds: Self.bounds, zoom: 13)
            let clusterIndex = try queries.clusters(in: clusterViewport, strategy: .coveringIndex, connection: connection)
            let clusterRTree = try queries.clusters(in: clusterViewport, strategy: .rtreePrefilter, connection: connection)
            #expect(!clusterIndex.isEmpty, "the test viewport returned no cluster badges")
            #expect(
                Set(clusterIndex) == Set(clusterRTree),
                "clusters disagree: \(clusterIndex.count) cells via the covering index, \(clusterRTree.count) via the R*Tree"
            )
        }
    }

    /// The grid's picks are a subset of the un-gridded answer, one per occupied cell, and their
    /// member counts add up to every tree in the box. That last part is what says the grid *thins*
    /// the drawing without losing track of what is there — a `LIMIT` cannot say it, because a `LIMIT`
    /// does not know what it dropped.
    @Test("the grid picks one real tree per cell and accounts for all of them")
    func gridIsAFaithfulSubset() async throws {
        let store = try await Self.store()
        let queries = try Self.queries(store)

        try await store.queue.read { connection in
            let everything = try queries.pins(
                in: MapViewport(bounds: Self.bounds, zoom: 16, pinLimit: 100_000),
                connection: connection
            )
            let cells = try queries.markerCells(
                in: Self.viewport(),
                cellPoints: MapModel.markerCellPoints,
                connection: connection
            )
            let picks = try queries.pins(in: Self.viewport(), connection: connection)

            try #require(
                everything.count > MapModel.pinLimit,
                "the fixture box holds \(everything.count) trees, which is inside the budget, so the grid never ran"
            )
            #expect(picks.count == cells.count, "\(cells.count) occupied cells produced \(picks.count) pins")
            #expect(
                cells.reduce(0) { $0 + $1.memberCount } == everything.count,
                "the cells account for \(cells.reduce(0) { $0 + $1.memberCount }) of \(everything.count) trees"
            )
            let all = Set(everything.map(\.id))
            #expect(picks.allSatisfy { all.contains($0.id) }, "the grid returned a tree the box does not hold")
        }
    }

    /// The grid is stable under a pan, which is what keeps a pin from flickering and re-animating as
    /// the user drags: the cell indices come from absolute `+90`/`+180` offsets rather than from the
    /// box's own corner, so a tree that wins its cell goes on winning it in an overlapping box.
    ///
    /// **The comparison is over the interior only, and that is not a hedge.** A cell that straddles
    /// the edge of a box holds different trees in each box — the query only ever sees the part inside
    /// the bounds — so its `MIN(rowid)` winner is genuinely allowed to differ, and it does: one row of
    /// cells at each box's edge, about 22 of them here, changed hands when this was first written
    /// against the whole overlap. That is the fetch pad's job, not the grid's; `MapModel` reads 8 %
    /// more than the screen precisely so the edge is off-camera. What must not move is everything the
    /// user is looking at, so the region is shrunk by one cell on each side and then compared
    /// exactly.
    @Test("a tree that wins its cell keeps winning it when the box moves")
    func theGridIsStableUnderAPan() async throws {
        let store = try await Self.store()
        let queries = try Self.queries(store)

        // A quarter-box nudge north: most of the screen is the same ground seen from a new corner.
        let shift = (Self.bounds.maxLatitude - Self.bounds.minLatitude) / 4
        let panned = BoundingBox(
            minLatitude: Self.bounds.minLatitude + shift,
            maxLatitude: Self.bounds.maxLatitude + shift,
            minLongitude: Self.bounds.minLongitude,
            maxLongitude: Self.bounds.maxLongitude
        )
        let cell = TreeQueries.cellSize(
            zoom: 16,
            centerLatitude: (Self.bounds.minLatitude + Self.bounds.maxLatitude) / 2,
            points: MapModel.markerCellPoints
        )
        // The overlap, less one cell at each end where partial membership is expected.
        let interior = (low: panned.minLatitude + cell.latitude, high: Self.bounds.maxLatitude - cell.latitude)

        try await store.queue.read { connection in
            let before = try queries.pins(in: Self.viewport(), connection: connection)
            let after = try queries.pins(
                in: MapViewport(
                    bounds: panned,
                    zoom: 16,
                    pinLimit: MapModel.pinLimit,
                    markerCellPoints: MapModel.markerCellPoints
                ),
                connection: connection
            )
            try #require(!before.isEmpty && !after.isEmpty, "one of the two boxes returned no pins")

            func inside(_ pins: PinAnswer) -> Set<UUID> {
                Set(pins.lazy
                    .filter { $0.coordinate.latitude >= interior.low && $0.coordinate.latitude <= interior.high }
                    .map(\.id))
            }
            let keptBefore = inside(before)
            let keptAfter = inside(after)
            #expect(keptBefore.count > 50, "only \(keptBefore.count) pins fell in the interior; the fixture is too thin")
            #expect(
                keptBefore == keptAfter,
                "\(keptBefore.symmetricDifference(keptAfter).count) interior pins changed identity under a pan"
            )
        }
    }

    /// The same property on the other side of A1's threshold, where it had been claimed and was
    /// **not true**.
    ///
    /// `TreeCluster.id` says it is "stable across pans at the same zoom, because the grid is absolute
    /// rather than relative to the viewport's corner — the same cell keeps the same id as the user
    /// drags, so the badge does not flicker and re-animate". The `+90`/`+180` offsets do make the
    /// grid independent of the corner. They do not make it independent of the *box*, because
    /// `cellSize` took the viewport's own centre latitude and `cos` moved with it — see that method
    /// for the arithmetic and for how far thirty-odd cells of slide goes. The badge has been
    /// re-keying on every pan since it was written; this is the assertion that says it does not
    /// (ERRATA E130).
    @Test("a cluster cell keeps its id when the box moves")
    func clusterIDsAreStableUnderAPan() async throws {
        let store = try await Self.store()
        let queries = try Self.queries(store)

        let shift = (Self.bounds.maxLatitude - Self.bounds.minLatitude) / 4
        let panned = BoundingBox(
            minLatitude: Self.bounds.minLatitude + shift,
            maxLatitude: Self.bounds.maxLatitude + shift,
            minLongitude: Self.bounds.minLongitude,
            maxLongitude: Self.bounds.maxLongitude
        )

        try await store.queue.read { connection in
            let before = try queries.clusters(in: MapViewport(bounds: Self.bounds, zoom: 14), connection: connection)
            let after = try queries.clusters(in: MapViewport(bounds: panned, zoom: 14), connection: connection)
            try #require(!before.isEmpty && !after.isEmpty, "one of the two boxes produced no badges")

            // Any cell both boxes reached must be *the same cell* — same id — and not merely a badge
            // at a similar place. Counts and centres are allowed to differ at the box edges, where
            // each box sees only part of the cell.
            let shared = Set(before.map(\.id)).intersection(after.map(\.id))
            #expect(
                shared.count >= before.count / 2,
                "only \(shared.count) of \(before.count) cluster cells survived a quarter-box pan with their id"
            )
        }
    }

    // MARK: - The narrowed statements (ERRATA E134)

    /// `Platanus x hispanica`, the densest species in the seed.
    private static let londonPlane = UUID(uuidString: "7d22dcda-354d-5f7d-9be0-3739ea8c6688")!

    /// A narrowed map statement must still resolve through an index and must never scan a table —
    /// the same two rules as every other map statement, over the statements the search bar produces.
    ///
    /// **The index it lands on is deliberately not pinned, and that is the point.** Every other map
    /// query is asserted to use `idx_trees_lat_lon`, because there is one spatial index worth using
    /// and no predicate selective enough to beat it. A species predicate *is* that selective, and the
    /// right plan genuinely differs by query: one species over the whole city is answered from
    /// `idx_trees_species_current` in 21 ms where forcing the spatial index costs 386, and a hundred
    /// species at once inverts it. `TreeQueries.speciesPredicate` has the table. Pinning either index
    /// here would pin the wrong one half the time.
    @Test("a narrowed map statement resolves through an index and never scans a table")
    func narrowedPlansStayIndexed() async throws {
        let store = try await Self.store()
        let queries = try Self.queries(store)

        try await store.queue.read { connection in
            let viewport = MapViewport(
                bounds: Self.bounds,
                zoom: 16,
                pinLimit: MapModel.pinLimit,
                markerCellPoints: MapModel.markerCellPoints,
                speciesIDs: [Self.londonPlane]
            )
            let narrowing = try queries.narrowing(for: viewport, connection: connection)
            #expect(narrowing != .matchesNothing, "the London Plane did not resolve; the uuid lookup is broken")

            for strategy in SpatialIndexStrategy.allCases {
                let statements: [(String, String)] = [
                    ("narrowed pins", queries.everyPinSQL(strategy, narrowing: narrowing)),
                    ("narrowed marker cells", queries.markerCellsSQL(strategy, narrowing: narrowing)),
                    ("narrowed cluster badges", queries.clustersSQL(strategy, narrowing: narrowing))
                ]
                for (label, sql) in statements {
                    let steps = try connection.queryPlan(for: sql)
                    let plan = steps.joined(separator: " | ")
                    let tableScans = steps.filter {
                        $0.contains("SCAN") && !$0.contains("COVERING INDEX") && !$0.contains("VIRTUAL TABLE")
                    }
                    #expect(
                        tableScans.isEmpty,
                        "\(label) (\(strategy.rawValue)) degraded to a table scan: \(plan)"
                    )
                    #expect(
                        plan.contains("idx_trees_lat_lon") || plan.contains("idx_trees_species_current"),
                        "\(label) (\(strategy.rawValue)) reached neither useful index: \(plan)"
                    )
                }
            }
        }
    }

    /// **The seed must carry `ANALYZE` statistics, and this is not a tidiness rule.**
    ///
    /// The narrowed queries are the only ones in the app whose right plan depends on the *data* — a
    /// selective species wants `idx_trees_species_current`, a broad prefix matching a hundred species
    /// wants `idx_trees_lat_lon` — and `sqlite_stat1` is the only thing that lets SQLite tell those
    /// apart. Measured over the shipped seed, zoom-16 marker cells narrowed to the hundred densest
    /// species, which is 85 % of the inventory:
    ///
    ///     with sqlite_stat1     18.3 ms   SEARCH … idx_trees_lat_lon
    ///     without it           266.0 ms   SEARCH … idx_trees_species_current
    ///
    /// Fourteen times slower, on the map's critical path, from a table that is easy to lose: it does
    /// not survive a rebuild that forgets to run `ANALYZE`, and `Tools/build_seed.py` is the only
    /// thing that puts it there. Nothing else in the app notices, which is exactly why this is worth
    /// asserting rather than trusting — every other query has one sane plan and gets it either way.
    @Test("the seed carries the statistics the narrowed queries are planned with")
    func theSeedCarriesItsStatistics() async throws {
        let store = try await Self.store()

        try await store.queue.read { connection in
            let statement = try connection.cachedStatement("""
            SELECT count(*) AS n
              FROM \(SeedDatabase.schemaName).sqlite_stat1
             WHERE tbl = 'trees' AND idx = 'idx_trees_species_current'
            """)
            let rows = try statement.fetchOne { try $0.int("n") } ?? 0
            #expect(
                rows > 0,
                "the seed has no ANALYZE statistics for idx_trees_species_current, so a broad species search will be planned blind — run ANALYZE in Tools/build_seed.py"
            )
        }
    }
}
