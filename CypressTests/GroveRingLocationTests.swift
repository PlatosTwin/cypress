//
//  GroveRingLocationTests.swift
//  CypressTests
//
//  **F38: the Species ring follows the reader's location** (owner decision 2026-11-12).
//
//  A tester in Washington, D.C. opened My Grove > Species and read "you can recognize in the
//  Castro/Upper Market". `LocalAPI.groveSpecies` never read location: it always drew the ring
//  around the contributor's most-visited neighborhood and captioned it as if that were where they
//  were. These tests pin the three states the owner's decision makes:
//
//  1. A usable fix inside a polygon: the ring is that neighborhood, even when the reader's
//     most-visited neighborhood is a different one.
//  2. A usable fix where no polygon exists: R29's radius around the reader, captioned "of where you
//     are". San Jose stands in for D.C. here: the shipped seed has no D.C. rows, and San Jose is the
//     city whose rows carry no `neighborhood_id`, which is D.C.'s state (ROADMAP chip 88). Where
//     the reader's spot holds no record at all (Sacramento), the screen says so.
//  3. No usable fix (denied, none, or too coarse): the most-visited area, captioned as most-visited.
//
//  The seed reads use the same harness as `SecondCityGeographyTests`.
//

import Foundation
import Testing
@testable import Cypress

@Suite("Grove ring · follows the reader's location (F38)")
struct GroveRingLocationTests {

    // MARK: - Harness

    static var seedURL: URL? {
        if let path = ProcessInfo.processInfo.environment["CYPRESS_SEED_PATH"] {
            return URL(fileURLWithPath: path)
        }
        return SeedDatabase.urlInBundle(Bundle(for: BundleToken.self)) ?? SeedDatabase.urlInBundle()
    }

    private final class BundleToken {}

    private static let seed = SeedDatabase.schemaName

    static let downtownSanJose = Coordinate(latitude: 37.3352, longitude: -121.8895)
    static let sacramento = Coordinate(latitude: 38.5816, longitude: -121.4944)
    static let now = Date(timeIntervalSince1970: 1_784_505_600) // 2026-07-20

    private static let deviceID = UUID(uuidString: "01410000-0000-4000-8000-000000000f38")!

    private static func store() async throws -> CypressStore {
        let url = try #require(seedURL, "no seed database; set CYPRESS_SEED_PATH")
        return try await CypressStore.inMemory(seedURL: url)
    }

    private static func api(_ store: CypressStore) -> LocalAPI {
        LocalAPI(store: store, deviceID: deviceID, now: { now })
    }

    /// One tree in the named polygon, with its coordinate, chosen by the seed rather than pinned.
    private static func tree(
        in neighborhood: String,
        on store: CypressStore
    ) async throws -> (id: UUID, coordinate: Coordinate) {
        let found = try await store.queue.read { connection -> (UUID, Coordinate)? in
            let statement = try connection.prepare("""
                SELECT t.uuid AS tree_uuid, t.lat AS lat, t.lon AS lon
                  FROM \(seed).trees t
                  JOIN \(seed).neighborhoods n ON n.id = t.neighborhood_id
                 WHERE n.name = '\(neighborhood)' AND t.deleted_at IS NULL
                   AND t.species_current IS NOT NULL
                 ORDER BY t.uuid LIMIT 1
                """)
            defer { statement.finalize() }
            return try statement.fetchOne { row in
                (
                    try row.uuid("tree_uuid"),
                    Coordinate(latitude: try row.double("lat"), longitude: try row.double("lon"))
                )
            }
        }
        let (id, coordinate) = try #require(found, "no tree in \(neighborhood); the probe cannot fire")
        return (id, coordinate)
    }

    /// A contributor whose whole record is one visit in Sunset/Parkside, so the most-visited area is
    /// Sunset/Parkside and any other answer can only have come from the fix.
    private static func sunsetContributor() async throws -> CypressStore {
        let store = try await store()
        let sunset = try await tree(in: "Sunset/Parkside", on: store)
        try await store.queue.write { connection in
            try ContributionStore().insert(
                Visit(
                    treeID: sunset.id,
                    attribution: .anonymous(deviceID: Self.deviceID),
                    capturedAt: Self.now
                ),
                connection: connection
            )
        }
        return store
    }

    private static func requireSanJoseCarriesNoPolygons(_ store: CypressStore) async throws {
        let assigned = try await store.queue.read { connection -> Int in
            let statement = try connection.prepare("""
                SELECT COUNT(*) AS n FROM \(seed).trees
                 WHERE id_space = 'us-ca-sj' AND neighborhood_id IS NOT NULL
                """)
            defer { statement.finalize() }
            return try statement.fetchOne { try $0.int("n") } ?? -1
        }
        #expect(assigned == 0, "San Jose now carries polygons; this test is measuring the wrong path")
    }

    // MARK: - 1. The fix wins over the most-visited area

    @Test("a reader standing in the Mission whose most-visited area is the Sunset sees the Mission")
    func theRingNamesWhereTheReaderIs() async throws {
        let store = try await Self.sunsetContributor()
        let mission = try await Self.tree(in: "Mission", on: store)

        let grove = try await Self.api(store).groveSpecies(near: mission.coordinate)
        let neighborhood = try #require(grove.neighborhood, "a located reader got no area")
        #expect(neighborhood.area == .named("Mission"), "the ring is not about where the reader is")
        #expect(neighborhood.basis == .whereYouAre)
        #expect(grove.readerIsOutsideRecord == false)
        #expect(
            GroveCopy.caption(area: neighborhood.area, basis: neighborhood.basis)
                == "you can recognize in the Mission"
        )
    }

    // MARK: - 2. A city with no polygons (D.C.'s state)

    @Test("a reader in a city with no polygons gets a radius around them, not their most-visited place")
    func aCityWithoutPolygonsDrawsAroundTheReader() async throws {
        let store = try await Self.sunsetContributor()
        try await Self.requireSanJoseCarriesNoPolygons(store)

        let grove = try await Self.api(store).groveSpecies(near: Self.downtownSanJose)
        let neighborhood = try #require(grove.neighborhood, "a reader in San Jose got no area")
        #expect(neighborhood.area == .radius(meters: AlmanacLimits.fallbackRadiusM))
        #expect(neighborhood.basis == .whereYouAre)
        let total = try #require(neighborhood.species.totalCount, "an incomplete denominator (E38)")
        #expect(total > 0, "the circle around downtown San Jose holds no species")

        // The circle is centered on the reader, not on the most-visited tree: its species are
        // exactly the ones R29's radius around downtown San Jose holds. A circle drawn around the
        // contributor's Sunset tree has the same radius and a nonzero total, so the two lines above
        // cannot tell the two apart; this one can.
        let queries = GroveQueries(schema: try #require(store.seed, "no seed attached"))
        let aroundTheReader = try await store.queue.read { connection -> Series<UUID> in
            try queries.speciesIDs(
                scope: .radius(center: Self.downtownSanJose, meters: AlmanacLimits.fallbackRadiusM),
                connection: connection
            )
        }
        #expect(
            Set(neighborhood.species.items) == Set(aroundTheReader.items),
            "the radius is not centered on the reader"
        )

        let caption = GroveCopy.caption(area: neighborhood.area, basis: neighborhood.basis)
        #expect(caption == "you can recognize within a 15-minute walk of where you are")
        #expect(!caption.contains("Sunset"), "the caption named the most-visited place (F38)")
    }

    @Test("a reader where no inventory on the phone reaches is told so, and no ring is drawn")
    func aReaderOutsideTheRecordIsToldSo() async throws {
        let store = try await Self.sunsetContributor()

        let grove = try await Self.api(store).groveSpecies(near: Self.sacramento)
        #expect(grove.neighborhood == nil, "an area was drawn around ground the record does not cover")
        #expect(grove.readerIsOutsideRecord)
        #expect(grove.known.items.count == 1, "the reader's own species went missing with the ring")

        let presentation = GrovePresentation(grove: grove, now: Self.now, calendar: .current)
        #expect(presentation.progress == nil)
        #expect(presentation.areaNote == "No city tree inventory on this phone covers where you are yet.")
        #expect(!presentation.isEmpty, "the grid of known species should still draw")
    }

    // MARK: - The background merge keeps the paint's area

    /// A router over the real seed-backed phone and a service that knows the contributor's one
    /// species, so `refreshedGroveSpecies(near:)` takes its merge path, not its fallback.
    private static func router(
        _ store: CypressStore,
        log: RemoteReadLog
    ) async throws -> RoutedAPI {
        let local = api(store)
        let met = try #require(try await local.groveSpecies(near: nil).known.items.first, "no species met")
        let transport = ScriptedTransport()
        transport.answer(
            "GET /me/grove/species",
            with: """
            {"known":[{"species_id":"\(met.speciesID.uuidString)","first_met":"\(ISO8601DateFormatter().string(from: now))"}],
             "total":1}
            """
        )
        return RoutedAPI(local: local, remote: RoutedAPITests.remote(transport), log: log)
    }

    @Test("the merge is read where the reader is, not around the most-visited neighborhood")
    func theMergeKeepsTheReadersArea() async throws {
        let store = try await Self.sunsetContributor()
        let mission = try await Self.tree(in: "Mission", on: store)
        let log = RemoteReadLog()

        let merged = try await Self.router(store, log: log).refreshedGroveSpecies(near: mission.coordinate)
        #expect(await log.outcome(of: .groveSpecies) == .live, "the merge path did not run")
        let neighborhood = try #require(merged.neighborhood, "the merge lost the area")
        #expect(neighborhood.area == .named("Mission"), "the merge repainted a different area")
        #expect(neighborhood.basis == .whereYouAre)
    }

    @Test("the merge keeps the sentence for a reader outside every inventory")
    func theMergeKeepsOutsideRecord() async throws {
        let store = try await Self.sunsetContributor()
        let log = RemoteReadLog()

        let merged = try await Self.router(store, log: log).refreshedGroveSpecies(near: Self.sacramento)
        #expect(await log.outcome(of: .groveSpecies) == .live, "the merge path did not run")
        #expect(merged.neighborhood == nil)
        #expect(merged.readerIsOutsideRecord, "the merge dropped the outside-the-record state")
    }

    // MARK: - 3. No usable fix: most-visited, and said so

    @Test("with no fix, the ring is the most-visited neighborhood and the caption says so")
    func noFixSaysMostVisited() async throws {
        let store = try await Self.sunsetContributor()

        let grove = try await Self.api(store).groveSpecies(near: nil)
        let neighborhood = try #require(grove.neighborhood)
        #expect(neighborhood.area == .named("Sunset/Parkside"))
        #expect(neighborhood.basis == .mostVisited)
        #expect(grove.readerIsOutsideRecord == false)
        #expect(
            GroveCopy.caption(area: neighborhood.area, basis: neighborhood.basis)
                == "you can recognize in the Sunset/Parkside, your most-visited neighborhood"
        )
    }

    /// The wiring: `GroveModel` asks the provider at each read and applies F17's accuracy rule.
    /// Denied, coarse and precise fixes are read through the same model against the same store.
    @MainActor
    @Test("the model reads the fix: denied and coarse fall back to most-visited, precise follows")
    func theModelAppliesTheFixRule() async throws {
        let store = try await Self.sunsetContributor()
        let api = Self.api(store)
        let mission = try await Self.tree(in: "Mission", on: store)

        func caption(_ fix: MapLocationProvider.Availability) async throws -> String {
            let model = GroveModel(api: api, now: { Self.now }, currentFix: { fix })
            await model.load()
            return try #require(model.presentation?.progress, "no ring for \(fix)").caption
        }

        let mostVisited = "you can recognize in the Sunset/Parkside, your most-visited neighborhood"
        #expect(try await caption(.denied) == mostVisited)
        #expect(try await caption(.notAsked) == mostVisited)
        // ±3,000 m is iOS's approximate-location tile (F17): too coarse to name a neighborhood.
        #expect(try await caption(.located(mission.coordinate, accuracyM: 3_000)) == mostVisited)
        #expect(try await caption(.located(mission.coordinate, accuracyM: 10)) == "you can recognize in the Mission")
    }

    // MARK: - The captions, as strings

    @Test("each area and basis has its own caption, and only the located ones omit most-visited")
    func theFourCaptions() {
        #expect(GroveCopy.caption(area: .named("Mission"), basis: .whereYouAre) == "you can recognize in the Mission")
        #expect(
            GroveCopy.caption(area: .radius(meters: 1_200), basis: .whereYouAre)
                == "you can recognize within a 15-minute walk of where you are"
        )
        #expect(
            GroveCopy.caption(area: .named("Mission"), basis: .mostVisited)
                == "you can recognize in the Mission, your most-visited neighborhood"
        )
        #expect(
            GroveCopy.caption(area: .radius(meters: 1_200), basis: .mostVisited)
                == "you can recognize within a 15-minute walk of your most-visited tree"
        )
    }
}
