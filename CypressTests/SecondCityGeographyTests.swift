//
//  SecondCityGeographyTests.swift
//  CypressTests
//
//  **The two screens R29 had no standing to fix** — task #141, closing the holes E182 §5 recorded
//  and deliberately left: screen 07's `Near you` card and screen 08's recognition ring were still
//  scoped to `seed.neighborhoods`, which is San Francisco's 41 polygons and nothing else, so both
//  were blind in San Jose — the same defect family E182 closed for screen 12.
//
//  ── The same three claims as `AlmanacGeographyTests`, on the two remaining surfaces ─────────
//
//  1. **San Francisco did not move.** The polygon path is preferred wherever it resolves and
//     renders the identical predicate, so both screens' SF numbers are asserted equal to a direct
//     SQL read of the same join — not to "something non-nil".
//  2. **San Jose now has an answer.** Screen 07: a reader downtown gets a `Near you` count over
//     R29's stated radius. Screen 08: a contributor whose whole record is in San Jose gets a ring
//     whose denominator is the species within the same radius of their most-visited tree — A4's
//     inference with R29's geometry, still no location permission.
//  3. **The fallback never dresses itself as a place.** The payload carries `AlmanacArea.radius`,
//     never a name, and screen 08's caption states the distance in screen 12's own words.
//
//  Each San Jose test checks its precondition — that no San Jose row carries a `neighborhood_id` —
//  for `sanJoseResolvesTheFallback`'s stated reason: if a San Jose polygon layer ever lands, a
//  suite that claims to test the fallback must fail loudly rather than silently measure the
//  polygon path.
//

import Foundation
import Testing
@testable import Cypress

@Suite("Second city · the Near you card and the recognition ring")
struct SecondCityGeographyTests {

    // MARK: - Harness (AlmanacGeographyTests', verbatim)

    static var seedURL: URL? {
        if let path = ProcessInfo.processInfo.environment["CYPRESS_SEED_PATH"] {
            return URL(fileURLWithPath: path)
        }
        return SeedDatabase.urlInBundle(Bundle(for: BundleToken.self)) ?? SeedDatabase.urlInBundle()
    }

    private final class BundleToken {}

    private static let seed = SeedDatabase.schemaName

    private static func store() async throws -> CypressStore {
        let url = try #require(seedURL, "no seed database; set CYPRESS_SEED_PATH")
        return try await CypressStore.inMemory(seedURL: url)
    }

    private static func scalar(_ sql: String, on store: CypressStore) async throws -> Int {
        try await store.queue.read { connection in
            let statement = try connection.prepare(sql)
            defer { statement.finalize() }
            return try statement.fetchOne { try $0.int("n") } ?? -1
        }
    }

    /// The fixes `AlmanacGeographyTests` established for the family.
    static let downtownSanJose = Coordinate(latitude: 37.3352, longitude: -121.8895)
    static let outerSunset = Coordinate(latitude: 37.7533, longitude: -122.4934)
    static let sacramento = Coordinate(latitude: 38.5816, longitude: -121.4944)

    static let now = Date(timeIntervalSince1970: 1_784_505_600) // 2026-07-20
    static let locale = Locale(identifier: "en_US")

    private static let deviceID = UUID(uuidString: "01410000-0000-4000-8000-000000000141")!

    private static func api(_ store: CypressStore) -> LocalAPI {
        LocalAPI(store: store, deviceID: deviceID, now: { now })
    }

    /// If a San Jose polygon layer ever lands, every fallback assertion below would silently start
    /// measuring the polygon path; this makes them fail loudly instead.
    private static func requireSanJoseCarriesNoPolygons(_ store: CypressStore) async throws {
        let assigned = try await scalar(
            """
            SELECT COUNT(*) AS n FROM \(seed).trees
             WHERE id_space = 'us-ca-sj' AND neighborhood_id IS NOT NULL
            """,
            on: store
        )
        #expect(assigned == 0, "San Jose now carries polygons; this suite is measuring the wrong path")
    }

    // MARK: - Probes, resolved from the seed rather than pinned

    /// A species standing in Sunset/Parkside, by whichever id the seed's own inventory says is the
    /// most common there — resolved at runtime so the test is about the read, not about one row.
    private static func speciesCommonIn(
        _ neighborhood: String,
        on store: CypressStore
    ) async throws -> UUID {
        let found = try await store.queue.read { connection -> UUID? in
            let statement = try connection.prepare("""
                SELECT s.uuid AS species_uuid
                  FROM \(seed).trees t
                  JOIN \(seed).species s ON s.id = t.species_current
                  JOIN \(seed).neighborhoods n ON n.id = t.neighborhood_id
                 WHERE n.name = '\(neighborhood)' AND t.deleted_at IS NULL
                 GROUP BY s.uuid ORDER BY COUNT(*) DESC LIMIT 1
                """)
            defer { statement.finalize() }
            return try statement.fetchOne { try $0.uuid("species_uuid") }
        }
        return try #require(found, "no species stands in \(neighborhood); the probe cannot fire")
    }

    /// A San Jose tree that has a species, with its coordinate — the fallback centre for screen 08
    /// and the species whose membership in the denominator is asserted.
    private static func sanJoseTree(
        on store: CypressStore
    ) async throws -> (treeID: UUID, speciesID: UUID)? {
        try await store.queue.read { connection in
            let statement = try connection.prepare("""
                SELECT t.uuid AS tree_uuid, s.uuid AS species_uuid
                  FROM \(seed).trees t
                  JOIN \(seed).species s ON s.id = t.species_current
                 WHERE t.id_space = 'us-ca-sj' AND t.deleted_at IS NULL
                 ORDER BY t.uuid LIMIT 1
                """)
            defer { statement.finalize() }
            return try statement.fetchOne { row in
                (treeID: try row.uuid("tree_uuid"), speciesID: try row.uuid("species_uuid"))
            }
        }
    }

    // MARK: - Screen 07 · the Near you card

    /// The polygon path renders the identical predicate, asserted in the numbers: the card's count
    /// for a Sunset/Parkside reader equals a direct SQL read of the same join.
    @Test("a San Francisco reader's Near you card is scoped to the same polygon it always was")
    func sanFranciscoNearYouIsUnchanged() async throws {
        let store = try await Self.store()
        let speciesID = try await Self.speciesCommonIn("Sunset/Parkside", on: store)

        let guide = try await Self.api(store).speciesGuide(id: speciesID, near: Self.outerSunset)
        let nearYou = try #require(guide.nearYou, "a Sunset/Parkside reader lost the Near you card")
        #expect(nearYou.area == .named("Sunset/Parkside"))

        let direct = try await Self.scalar(
            """
            SELECT COUNT(*) AS n
              FROM \(Self.seed).trees t
              JOIN \(Self.seed).species s ON s.id = t.species_current
              JOIN \(Self.seed).neighborhoods n2 ON n2.id = t.neighborhood_id
             WHERE s.uuid = '\(speciesID.uuidString)' COLLATE NOCASE
               AND n2.name = 'Sunset/Parkside' AND t.deleted_at IS NULL
            """,
            on: store
        )
        #expect(direct > 0, "the probe species is not in the neighbourhood; the control cannot fire")
        #expect(nearYou.count == direct, "the polygon-scoped count moved")
    }

    /// The hole itself: `speciesGuide` resolved a polygon or nothing, so every San Jose reader's
    /// card silently did not draw. Now the reader downtown gets a count over R29's stated radius.
    @Test("a San Jose reader's Near you card draws, counted over the stated radius")
    func sanJoseGetsANearYouCard() async throws {
        let store = try await Self.store()
        try await Self.requireSanJoseCarriesNoPolygons(store)

        let sanJose = try #require(try await Self.sanJoseTree(on: store))
        let guide = try await Self.api(store).speciesGuide(id: sanJose.speciesID, near: Self.downtownSanJose)

        let nearYou = try #require(guide.nearYou, "San Jose still has no Near you card at all")
        #expect(nearYou.area == .radius(meters: AlmanacLimits.fallbackRadiusM))
        #expect(nearYou.count > 0, "a species the city records downtown counted to nothing")

        // And the whole-city card beside it still counts the whole merged inventory.
        let city = try #require(guide.cityTreeCount)
        #expect(city >= nearYou.count, "an area count exceeded the whole inventory's")
    }

    /// R29's third area: a circle around a reader the record does not cover is no area at all. The
    /// card not drawing is the honest state, and it must come from the coverage guard rather than
    /// from an error.
    @Test("outside the record there is no Near you card, not a card counting uncovered ground")
    func outsideTheRecordHasNoNearYouCard() async throws {
        let store = try await Self.store()
        let speciesID = try await Self.speciesCommonIn("Sunset/Parkside", on: store)

        let guide = try await Self.api(store).speciesGuide(id: speciesID, near: Self.sacramento)
        #expect(guide.nearYou == nil, "a card drew over ground the inventory has never covered")
        #expect(guide.cityTreeCount != nil, "the whole-city card does not depend on where you stand")
    }

    // MARK: - Screen 07 · the other count card (task #181)

    /// **The fourth member of the family, and the one where naming the reader's city is also wrong.**
    ///
    /// `SpeciesQueries.cityTreeCount` carries no id-space predicate: it is `COUNT(*)` over the
    /// whole attached inventory, and the built-in bundle is fused across `sf` and `us-ca-sj`. So
    /// the card labelled `In San Francisco` was printing a two-city number — for Crape Myrtle, 97
    /// San Francisco trees and 3,649 San Jose ones under San Francisco's name alone.
    ///
    /// The test asserts the fact first and the copy second, in that order deliberately: **because
    /// the number provably spans two cities, no city name can label it**, which is why the fix is
    /// not "say San Jose to a San Jose reader". The probe species is resolved at runtime as one the
    /// seed holds in both spaces, so the assertion is about the read rather than about one row.
    @Test("the whole-inventory count spans both cities, and its label names neither")
    func theCountCardNamesThePopulationItCounted() async throws {
        let store = try await Self.store()

        let probe = try await store.queue.read { connection -> (uuid: UUID, sf: Int, sj: Int)? in
            let statement = try connection.prepare("""
                SELECT s.uuid AS species_uuid,
                       SUM(CASE WHEN t.id_space = 'sf' THEN 1 ELSE 0 END) AS sf_count,
                       SUM(CASE WHEN t.id_space = 'us-ca-sj' THEN 1 ELSE 0 END) AS sj_count
                  FROM \(Self.seed).trees t
                  JOIN \(Self.seed).species s ON s.id = t.species_current
                 WHERE t.deleted_at IS NULL
                 GROUP BY s.uuid
                HAVING sf_count > 0 AND sj_count > 0
                 ORDER BY sj_count DESC LIMIT 1
                """)
            defer { statement.finalize() }
            return try statement.fetchOne { row in
                (uuid: try row.uuid("species_uuid"), sf: try row.int("sf_count"), sj: try row.int("sj_count"))
            }
        }
        let species = try #require(probe, "no species stands in both cities; the probe cannot fire")

        let guide = try await Self.api(store).speciesGuide(id: species.uuid, near: nil)
        let counted = try #require(guide.cityTreeCount)

        // 1 · the number is both cities' trees, which is what makes any single city name a lie.
        #expect(
            counted == species.sf + species.sj,
            "the card's count is not the whole attached inventory: \(counted) != \(species.sf) + \(species.sj)"
        )
        #expect(species.sf > 0 && species.sj > 0, "the probe stopped spanning two cities")

        // 2 · so the label names the inventory it counted, and no city in it. Markers rather than a
        //     fixed string, so swapping one hardcoded city for another cannot satisfy this.
        for marker in ["San Francisco", "San Jose", "SF", "DataSF"] {
            #expect(
                !SpeciesCopy.cityCountLabel.contains(marker),
                "07 §5's count card says \(marker) over a number counting \(species.sf + species.sj) trees in two cities"
            )
        }
    }

    // MARK: - Screen 08 · the recognition ring

    /// One visit to a Sunset/Parkside tree, and the ring's denominator is the polygon's own species
    /// list — equal to a direct SQL read, so the resident-neighbourhood path provably did not move.
    @Test("a San Francisco contributor's ring is the polygon's, unchanged")
    func sanFranciscoRingIsUnchanged() async throws {
        let store = try await Self.store()
        let attribution = Attribution.anonymous(deviceID: Self.deviceID)

        let sunsetTree = try await store.queue.read { connection -> UUID? in
            let statement = try connection.prepare("""
                SELECT t.uuid AS tree_uuid
                  FROM \(Self.seed).trees t
                  JOIN \(Self.seed).neighborhoods n ON n.id = t.neighborhood_id
                 WHERE n.name = 'Sunset/Parkside' AND t.deleted_at IS NULL
                   AND t.species_current IS NOT NULL
                 ORDER BY t.uuid LIMIT 1
                """)
            defer { statement.finalize() }
            return try statement.fetchOne { try $0.uuid("tree_uuid") }
        }
        let treeID = try #require(sunsetTree)
        try await store.queue.write { connection in
            try ContributionStore().insert(
                Visit(treeID: treeID, attribution: attribution, capturedAt: Self.now),
                connection: connection
            )
        }

        let grove = try await Self.api(store).groveSpecies()
        let neighborhood = try #require(grove.neighborhood, "one Sunset visit resolved no area")
        #expect(neighborhood.area == .named("Sunset/Parkside"))

        let direct = try await Self.scalar(
            """
            SELECT COUNT(DISTINCT s.uuid) AS n
              FROM \(Self.seed).trees t
              JOIN \(Self.seed).species s ON s.id = t.species_current
              JOIN \(Self.seed).neighborhoods n2 ON n2.id = t.neighborhood_id
             WHERE n2.name = 'Sunset/Parkside' AND t.deleted_at IS NULL
            """,
            on: store
        )
        #expect(neighborhood.species.totalCount == direct, "the ring's denominator moved")
        #expect(GroveCopy.caption(area: neighborhood.area) == "you can recognize in the Sunset/Parkside")
    }

    /// The hole itself: `residentNeighborhood` joins through `seed.neighborhoods`, so every San
    /// Jose contribution was dropped and the ring never rendered in that city. Now the same
    /// inference — most-visited — centres R29's radius, and the ring renders.
    @Test("a San Jose contributor gets a ring, drawn around their most-visited tree")
    func sanJoseContributorGetsARing() async throws {
        let store = try await Self.store()
        try await Self.requireSanJoseCarriesNoPolygons(store)
        let attribution = Attribution.anonymous(deviceID: Self.deviceID)

        let sanJose = try #require(try await Self.sanJoseTree(on: store))
        try await store.queue.write { connection in
            try ContributionStore().insert(
                Visit(treeID: sanJose.treeID, attribution: attribution, capturedAt: Self.now),
                connection: connection
            )
        }

        let grove = try await Self.api(store).groveSpecies()
        let neighborhood = try #require(grove.neighborhood, "a San Jose contributor still has no area")
        #expect(neighborhood.area == .radius(meters: AlmanacLimits.fallbackRadiusM))

        // The denominator holds the species standing around the visited tree — including, by
        // construction, the visited tree's own.
        let denominator = try #require(neighborhood.species.totalCount, "an incomplete denominator (E38)")
        #expect(denominator > 0)
        #expect(
            neighborhood.species.items.contains(sanJose.speciesID),
            "the visited tree's own species is missing from the area it centres"
        )

        // And the ring actually renders: the visit is a meeting, the meeting is in the area, so
        // the numerator crosses A9's floor of one.
        let presentation = GrovePresentation(grove: grove, now: Self.now, calendar: .current)
        let progress = try #require(presentation.progress, "the ring did not render for a San Jose contributor")
        #expect(progress.caption.contains("15-minute walk"), "the fallback caption does not state its distance")
        #expect(progress.caption.contains("in the") == false, "the fallback dressed itself as a place (R29)")
    }
}
