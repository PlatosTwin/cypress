import Foundation
import Testing
@testable import Cypress

/// **Acceptance gate (ARCHITECTURE §7).** "The bundled seed database's schema and row invariants are
/// pinned; a diff fails the test."
///
/// Extended with the query plans, because a plan that quietly stops using `idx_trees_lat_lon` is a
/// 195,309-row table scan on the map's critical path and passes every correctness assertion.
///
/// > `DataGates.seedContract(seedURL:)` is the same check driven from a plain executable, kept for
/// > verifying a seed rebuild without booting a simulator.
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
        #expect(failures.isEmpty, "\(failures.count) gate failures:\n\(failures.joined(separator: "\n"))")
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

    @Test("a NULL leaf_retention stays unknown all the way to the UI (ERRATA E9)")
    func unknownLeafRetentionStaysUnknown() throws {
        // The seed leaves `leaf_retention` NULL for 59 of its 569 species. The read layer resolves
        // nothing: NULL in, `nil` out. Any substitute would be a botanical claim nobody sourced.
        #expect(SpeciesQueries.leafRetention(stored: nil) == nil)
        #expect(SpeciesQueries.leafRetention(stored: "semi_deciduous") == .semiDeciduous)
        // A value outside the CHECK vocabulary means the seed and the enum have drifted; losing a
        // chip is the right failure for that, not inventing one.
        #expect(SpeciesQueries.leafRetention(stored: "evergreenish") == nil)

        let unknown = try Species(
            scientificName: "Ficus laurel",
            commonName: "Laurel Fig",
            leafRetention: nil,
            curated: true
        )

        // No phenology chip, anywhere: not fall colour, not a neutral one. What the chip row and
        // the season strip then do with an empty vocabulary is checked in `VisitGates`.
        #expect(unknown.availablePhenologyTags.isEmpty)
        #expect(PhenologyTag.validated(PhenologyTag.allCases, for: unknown).isEmpty)

        // No leaf-on window to state, and therefore no month in which the vitality UI is
        // suppressed — suppression asserts the tree is out of leaf, which nobody established.
        #expect(unknown.leafOnMonths == nil)
        for month in 1...12 {
            #expect(Vitality.isRatingPermitted(for: unknown, month: month))
            #expect(Vitality.suppression(for: unknown, month: month) == .none)
        }

        // D5's invariant does not fire on an unknown habit: the throw is about evergreens.
        #expect(throws: Never.self) {
            try Species(
                scientificName: "Ficus laurel",
                commonName: "Laurel Fig",
                leafRetention: nil,
                seasonal: SeasonalCalendar(fallColorMonths: [10, 11])
            )
        }
        #expect(throws: SpeciesValidationError.self) {
            try Species(
                scientificName: "Hesperocyparis macrocarpa",
                commonName: "Monterey Cypress",
                leafRetention: .evergreen,
                seasonal: SeasonalCalendar(fallColorMonths: [10, 11])
            )
        }
    }
}
