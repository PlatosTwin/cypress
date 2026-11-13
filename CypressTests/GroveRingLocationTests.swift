//
//  GroveRingLocationTests.swift
//  CypressTests
//
//  **F38: the Species ring follows the reader's location** (owner decisions of 2026-11-12 and
//  2026-11-13).
//
//  A tester in Washington, D.C. opened My Grove > Species and read "you can recognize in the
//  Castro/Upper Market". `LocalAPI.groveSpecies` never read location: it always drew the ring
//  around the contributor's most-visited neighborhood and captioned it as if that were where they
//  were. These tests pin the rule the owner set:
//
//  1. A usable fix inside a polygon: the ring is that neighborhood, even when the reader's
//     most-visited neighborhood is a different one.
//  2. A usable fix where no polygon exists: R29's radius around the reader, captioned "of where you
//     are". San Jose stands in for D.C. here: the shipped seed has no D.C. rows, and San Jose is the
//     city whose rows carry no `neighborhood_id`, which is D.C.'s state (ROADMAP chip 88).
//  3. Everything else falls back to the most-visited ring, captioned "most-visited": no usable fix
//     (denied, none, or too coarse); (a) a fix no inventory on the phone covers (Sacramento); and
//     (b) a fix whose area holds none of the species the reader has met.
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

    static let mostVisitedSunset = "you can recognize in the Sunset/Parkside, your most-visited neighborhood"

    private static let deviceID = UUID(uuidString: "01410000-0000-4000-8000-000000000f38")!

    private static func store() async throws -> CypressStore {
        let url = try #require(seedURL, "no seed database; set CYPRESS_SEED_PATH")
        return try await CypressStore.inMemory(seedURL: url)
    }

    private static func api(_ store: CypressStore) -> LocalAPI {
        LocalAPI(store: store, deviceID: deviceID, now: { now })
    }

    private static func scalar(_ sql: String, on store: CypressStore) async throws -> Int {
        try await store.queue.read { connection in
            let statement = try connection.prepare(sql)
            defer { statement.finalize() }
            return try statement.fetchOne { try $0.int("n") } ?? -1
        }
    }

    private struct Probe {
        let id: UUID
        let speciesID: UUID
        let coordinate: Coordinate
    }

    /// One tree with a species, chosen by the seed rather than pinned. `whereSQL` filters
    /// `seed.trees t` left-joined to `seed.neighborhoods n`, so San Jose rows qualify; `orderSQL`
    /// picks which.
    private static func probe(
        _ whereSQL: String,
        orderBy orderSQL: String = "t.uuid",
        offset: Int = 0,
        on store: CypressStore
    ) async throws -> Probe {
        let found = try await store.queue.read { connection -> Probe? in
            let statement = try connection.prepare("""
                SELECT t.uuid AS tree_uuid, s.uuid AS species_uuid, t.lat AS lat, t.lon AS lon
                  FROM \(seed).trees t
                  JOIN \(seed).species s ON s.id = t.species_current
                  LEFT JOIN \(seed).neighborhoods n ON n.id = t.neighborhood_id
                 WHERE t.deleted_at IS NULL AND (\(whereSQL))
                 ORDER BY \(orderSQL) LIMIT 1 OFFSET \(offset)
                """)
            defer { statement.finalize() }
            return try statement.fetchOne { row in
                Probe(
                    id: try row.uuid("tree_uuid"),
                    speciesID: try row.uuid("species_uuid"),
                    coordinate: Coordinate(latitude: try row.double("lat"), longitude: try row.double("lon"))
                )
            }
        }
        return try #require(found, "no tree matches \(whereSQL); the probe cannot fire")
    }

    private static func tree(in neighborhood: String, offset: Int = 0, on store: CypressStore) async throws -> Probe {
        try await probe("n.name = '\(neighborhood)'", offset: offset, on: store)
    }

    /// The San Jose tree nearest downtown, so its species stands inside the circle around a reader
    /// there.
    private static func sanJoseTreeNearDowntown(on store: CypressStore) async throws -> Probe {
        let lat = downtownSanJose.latitude, lon = downtownSanJose.longitude
        return try await probe(
            "t.id_space = 'us-ca-sj'",
            orderBy: "(t.lat - \(lat)) * (t.lat - \(lat)) + (t.lon - \(lon)) * (t.lon - \(lon))",
            on: store
        )
    }

    /// A Sunset/Parkside tree whose species has no tree in `other`, for ruling (b).
    private static func sunsetTreeAbsentFrom(_ other: String, on store: CypressStore) async throws -> Probe {
        try await probe(
            """
            n.name = 'Sunset/Parkside' AND t.species_current NOT IN (
                SELECT t2.species_current FROM \(seed).trees t2
                  JOIN \(seed).neighborhoods n2 ON n2.id = t2.neighborhood_id
                 WHERE n2.name = '\(other)' AND t2.deleted_at IS NULL AND t2.species_current IS NOT NULL)
            """,
            on: store
        )
    }

    private static func visit(_ trees: [Probe], on store: CypressStore) async throws {
        try await store.queue.write { connection in
            for tree in trees {
                try ContributionStore().insert(
                    Visit(treeID: tree.id, attribution: .anonymous(deviceID: Self.deviceID), capturedAt: Self.now),
                    connection: connection
                )
            }
        }
    }

    /// Two visits in Sunset/Parkside, so it is the most-visited neighborhood, and one at each of
    /// `extra`, so the reader has met a species where that tree stands.
    private static func contributor(alsoVisiting extra: [Probe] = [], on store: CypressStore) async throws {
        let sunsetA = try await tree(in: "Sunset/Parkside", offset: 0, on: store)
        let sunsetB = try await tree(in: "Sunset/Parkside", offset: 1, on: store)
        try await visit([sunsetA, sunsetB] + extra, on: store)
    }

    private static func requireSanJoseCarriesNoPolygons(_ store: CypressStore) async throws {
        let assigned = try await scalar(
            """
            SELECT COUNT(*) AS n FROM \(seed).trees
             WHERE id_space = 'us-ca-sj' AND neighborhood_id IS NOT NULL
            """,
            on: store
        )
        #expect(assigned == 0, "San Jose now carries polygons; this test is measuring the wrong path")
    }

    private static func caption(_ grove: GroveSpecies) throws -> String {
        let neighborhood = try #require(grove.neighborhood, "no area")
        return GroveCopy.caption(area: neighborhood.area, basis: neighborhood.basis)
    }

    // MARK: - 1. The fix wins over the most-visited area

    @Test("a reader standing in the Mission whose most-visited area is the Sunset sees the Mission")
    func theRingNamesWhereTheReaderIs() async throws {
        let store = try await Self.store()
        let mission = try await Self.tree(in: "Mission", on: store)
        try await Self.contributor(alsoVisiting: [mission], on: store)

        let grove = try await Self.api(store).groveSpecies(near: mission.coordinate)
        let neighborhood = try #require(grove.neighborhood, "a located reader got no area")
        #expect(neighborhood.area == .named("Mission"), "the ring is not about where the reader is")
        #expect(neighborhood.basis == .whereYouAre)
        #expect(try Self.caption(grove) == "you can recognize in the Mission")
    }

    // MARK: - 2. A city with no polygons (D.C.'s state)

    @Test("a reader in a city with no polygons gets a radius around them, not their most-visited place")
    func aCityWithoutPolygonsDrawsAroundTheReader() async throws {
        let store = try await Self.store()
        try await Self.requireSanJoseCarriesNoPolygons(store)
        let sanJose = try await Self.sanJoseTreeNearDowntown(on: store)
        try await Self.contributor(alsoVisiting: [sanJose], on: store)

        let grove = try await Self.api(store).groveSpecies(near: Self.downtownSanJose)
        let neighborhood = try #require(grove.neighborhood, "a reader in San Jose got no area")
        #expect(neighborhood.area == .radius(meters: AlmanacLimits.fallbackRadiusM))
        #expect(neighborhood.basis == .whereYouAre)

        // The circle is centered on the reader: its species are exactly the ones R29's radius
        // around downtown San Jose holds. A circle of the same radius centered anywhere else has
        // the same `.radius(meters:)` and a nonzero total, so only this comparison tells them apart.
        let queries = GroveQueries(schema: try #require(store.seed, "no seed attached"))
        let aroundTheReader = try await store.queue.read { connection -> Series<UUID> in
            try queries.speciesIDs(
                scope: .radius(center: Self.downtownSanJose, meters: AlmanacLimits.fallbackRadiusM),
                connection: connection
            )
        }
        #expect(!aroundTheReader.items.isEmpty, "the circle around downtown San Jose holds no species")
        #expect(
            Set(neighborhood.species.items) == Set(aroundTheReader.items),
            "the radius is not centered on the reader"
        )

        let caption = try Self.caption(grove)
        #expect(caption == "you can recognize within a 15-minute walk of where you are")
        #expect(!caption.contains("Sunset"), "the caption named the most-visited place (F38)")
    }

    // MARK: - 3. The fallbacks: most-visited, and said so

    @Test("(a) a reader no inventory on the phone covers gets the most-visited ring, labeled so")
    func uncoveredFixFallsBackToMostVisited() async throws {
        let store = try await Self.store()
        try await Self.contributor(on: store)

        let grove = try await Self.api(store).groveSpecies(near: Self.sacramento)
        let neighborhood = try #require(grove.neighborhood, "an uncovered reader got no ring (owner ruling (a))")
        #expect(neighborhood.area == .named("Sunset/Parkside"))
        #expect(neighborhood.basis == .mostVisited)
        #expect(try Self.caption(grove) == Self.mostVisitedSunset)
    }

    @Test("(b) a reader in covered ground who met none of its species gets the most-visited ring")
    func noSpeciesMetHereFallsBackToMostVisited() async throws {
        let store = try await Self.store()
        let sunsetOnly = try await Self.sunsetTreeAbsentFrom("Mission", on: store)
        try await Self.visit([sunsetOnly], on: store)
        let mission = try await Self.tree(in: "Mission", on: store)

        // The precondition, read back rather than assumed: the Mission holds a record, and none of
        // it is the one species this reader has met.
        let inMission = try await Self.scalar(
            """
            SELECT COUNT(*) AS n FROM \(Self.seed).trees t
              JOIN \(Self.seed).neighborhoods n ON n.id = t.neighborhood_id
              JOIN \(Self.seed).species s ON s.id = t.species_current
             WHERE n.name = 'Mission' AND t.deleted_at IS NULL
               AND s.uuid = '\(sunsetOnly.speciesID.uuidString.lowercased())'
            """,
            on: store
        )
        #expect(inMission == 0, "the probe's species grows in the Mission; the test is vacuous")

        let grove = try await Self.api(store).groveSpecies(near: mission.coordinate)
        let neighborhood = try #require(grove.neighborhood, "no ring at all")
        #expect(neighborhood.area == .named("Sunset/Parkside"), "an empty ring was drawn where the reader stands")
        #expect(neighborhood.basis == .mostVisited)
        let presentation = GrovePresentation(grove: grove, now: Self.now, calendar: .current)
        #expect(try #require(presentation.progress, "the fallback ring did not draw").caption == Self.mostVisitedSunset)
    }

    @Test("with no fix, the ring is the most-visited neighborhood and the caption says so")
    func noFixSaysMostVisited() async throws {
        let store = try await Self.store()
        try await Self.contributor(on: store)

        let grove = try await Self.api(store).groveSpecies(near: nil)
        let neighborhood = try #require(grove.neighborhood)
        #expect(neighborhood.area == .named("Sunset/Parkside"))
        #expect(neighborhood.basis == .mostVisited)
        #expect(try Self.caption(grove) == Self.mostVisitedSunset)
    }

    /// The wiring: `GroveModel` asks the provider at each read and applies F17's accuracy rule.
    /// Denied, coarse and precise fixes are read through the same model against the same store.
    @MainActor
    @Test("the model reads the fix: denied and coarse fall back to most-visited, precise follows")
    func theModelAppliesTheFixRule() async throws {
        let store = try await Self.store()
        let mission = try await Self.tree(in: "Mission", on: store)
        try await Self.contributor(alsoVisiting: [mission], on: store)
        let api = Self.api(store)

        func caption(_ fix: MapLocationProvider.Availability) async throws -> String {
            let model = GroveModel(api: api, now: { Self.now }, currentFix: { fix })
            await model.load()
            return try #require(model.presentation?.progress, "no ring for \(fix)").caption
        }

        #expect(try await caption(.denied) == Self.mostVisitedSunset)
        #expect(try await caption(.notAsked) == Self.mostVisitedSunset)
        // ±3,000 m is iOS's approximate-location tile (F17): too coarse to name a neighborhood.
        #expect(try await caption(.located(mission.coordinate, accuracyM: 3_000)) == Self.mostVisitedSunset)
        #expect(try await caption(.located(mission.coordinate, accuracyM: 10)) == "you can recognize in the Mission")
    }

    // MARK: - The background merge keeps the paint's area

    /// A router over the real seed-backed phone and a service that knows the contributor's first
    /// species, so `refreshedGroveSpecies(near:)` takes its merge path, not its fallback.
    private static func router(_ store: CypressStore, log: RemoteReadLog) async throws -> RoutedAPI {
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

    @Test("the merge at a fix in the Mission keeps the Mission, not the most-visited Sunset")
    func theMergeKeepsTheReadersNeighborhood() async throws {
        let store = try await Self.store()
        let mission = try await Self.tree(in: "Mission", on: store)
        try await Self.contributor(alsoVisiting: [mission], on: store)
        let log = RemoteReadLog()

        let merged = try await Self.router(store, log: log).refreshedGroveSpecies(near: mission.coordinate)
        #expect(await log.outcome(of: .groveSpecies) == .live, "the merge path did not run")
        let neighborhood = try #require(merged.neighborhood, "the merge lost the area")
        #expect(neighborhood.area == .named("Mission"), "the merge repainted a different area")
        #expect(neighborhood.basis == .whereYouAre)
    }

    @Test("the merge at a fix in San Jose keeps the radius around the reader")
    func theMergeKeepsTheReadersRadius() async throws {
        let store = try await Self.store()
        let sanJose = try await Self.sanJoseTreeNearDowntown(on: store)
        try await Self.contributor(alsoVisiting: [sanJose], on: store)
        let log = RemoteReadLog()

        let merged = try await Self.router(store, log: log).refreshedGroveSpecies(near: Self.downtownSanJose)
        #expect(await log.outcome(of: .groveSpecies) == .live, "the merge path did not run")
        let neighborhood = try #require(merged.neighborhood, "the merge lost the area")
        #expect(
            neighborhood.area == .radius(meters: AlmanacLimits.fallbackRadiusM),
            "the merge repainted a different area"
        )
        #expect(neighborhood.basis == .whereYouAre)
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
