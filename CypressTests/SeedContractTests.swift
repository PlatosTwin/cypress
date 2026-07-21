#if canImport(Testing)
import Foundation
import Testing

/// **Acceptance gate (ARCHITECTURE §7).** "The bundled seed database's schema and row invariants are
/// pinned; a diff fails the test."
///
/// Extended with the query plans, because a plan that quietly stops using `idx_trees_lat_lon` is a
/// 195,309-row table scan on the map's critical path and passes every correctness assertion.
///
/// > No test target is configured yet, so these do not run in CI. `DataGates.seedContract(seedURL:)`
/// > is the same check driven from a plain executable, which is how it was verified.
@Suite("Seed contract")
struct SeedContractTests {

    /// Where the seed lives when these run.
    ///
    /// In a test bundle it is a resource. Until a test target exists, `CYPRESS_SEED_PATH` points at
    /// `Fixtures/seed/cypress-seed.sqlite` — which is also how the executable harness finds it.
    static var seedURL: URL? {
        if let path = ProcessInfo.processInfo.environment["CYPRESS_SEED_PATH"] {
            return URL(fileURLWithPath: path)
        }
        return SeedDatabase.urlInBundle(Bundle(for: BundleToken.self))
            ?? SeedDatabase.urlInBundle()
    }

    private final class BundleToken {}

    @Test("the seed's schema and row invariants are pinned")
    func contract() async throws {
        let seedURL = try #require(Self.seedURL, "no seed database; set CYPRESS_SEED_PATH")
        let failures = try await DataGates.seedContract(seedURL: seedURL)
        #expect(failures.isEmpty, "\(failures.count) gate failures:\n" + failures.joined(separator: "\n"))
    }

    @Test("the seed is attached read-only and cannot be written")
    func seedIsReadOnly() async throws {
        let seedURL = try #require(Self.seedURL, "no seed database; set CYPRESS_SEED_PATH")
        let store = try await CypressStore.inMemory(seedURL: seedURL)
        await #expect(throws: (any Error).self) {
            try await store.queue.withConnection { connection in
                try connection.execute("UPDATE \(SeedDatabase.schemaName).trees SET status = 'removed' WHERE id = 1")
            }
        }
    }

    @Test("A1: clusters at zoom 15 and below, individual pins at 16 and above")
    func clusteringThreshold() {
        let bounds = BoundingBox(minLatitude: 37.77, maxLatitude: 37.78, minLongitude: -122.45, maxLongitude: -122.44)
        for zoom in 0...15 {
            #expect(MapViewport(bounds: bounds, zoom: zoom).shouldCluster, "zoom \(zoom) should cluster")
        }
        for zoom in 16...22 {
            #expect(!MapViewport(bounds: bounds, zoom: zoom).shouldCluster, "zoom \(zoom) should show pins")
        }
    }

    @Test("cluster cells shrink by a factor of two per zoom step")
    func clusterCellScaling() {
        let coarse = TreeQueries.cellSize(zoom: 12, centreLatitude: 37.77)
        let fine = TreeQueries.cellSize(zoom: 13, centreLatitude: 37.77)
        #expect(abs(coarse.longitude / fine.longitude - 2) < 0.000_001)
        // Latitude degrees are shorter than longitude degrees on a mercator screen by cos(lat).
        #expect(coarse.latitude < coarse.longitude)
    }

    @Test("a bounding box around a point covers the requested radius")
    func boundingBoxAroundPoint() {
        let centre = Coordinate(latitude: 37.7761, longitude: -122.4464)
        let bounds = BoundingBox(around: centre, radiusM: 50)
        #expect(bounds.contains(centre))
        // Due north at exactly the radius must be inside; well beyond it must not.
        let north = Coordinate(latitude: centre.latitude + 49 / 111_320.0, longitude: centre.longitude)
        let farNorth = Coordinate(latitude: centre.latitude + 500 / 111_320.0, longitude: centre.longitude)
        #expect(bounds.contains(north))
        #expect(!bounds.contains(farNorth))
    }

    @Test("an unauthored leaf_retention never produces a fall-colour claim (D5)")
    func unauthoredLeafRetentionIsSafe() {
        // The shipped seed leaves `leaf_retention` NULL for all 577 species. Whatever the read
        // layer resolves it to must not let a fall-colour chip appear.
        let resolved = SpeciesQueries.leafRetention(stored: nil, seasonal: .empty)
        #expect(!resolved.canShowFallColor)

        // …but if the row does carry fall-colour months, calling it evergreen would be wrong and
        // would make Species.init throw its D5 validation.
        let withFallColor = SpeciesQueries.leafRetention(
            stored: nil,
            seasonal: SeasonalCalendar(fallColorMonths: [10, 11])
        )
        #expect(withFallColor == .deciduous)

        // An authored value always wins.
        #expect(SpeciesQueries.leafRetention(stored: "semi_deciduous", seasonal: .empty) == .semiDeciduous)
    }
}
#endif
