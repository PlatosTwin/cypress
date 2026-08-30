//
//  CityQueriesTests.swift
//  CypressTests
//
//  Query-layer tests for `CityQueries` and `LocalAPI.city(near:)`, against the real shipped seed —
//  the same harness `SecondCityGeographyTests` uses and for the same reason: a fixture written for
//  this test cannot catch a disagreement between the query and the fused bundle it actually reads.
//
//  Four things this suite exists to prove, each one a defect this family has shipped before under a
//  different name:
//  1. **The fused-bundle case.** A citywide count must not span both `sf` and `us-ca-sj`
//     (RULINGS R48).
//  2. **The vacant-site exclusion.** `oldestOnFile` must not let a `vacant_site`'s `planted_year`
//     stand in for a tree's.
//  3. **The stub-species exclusion.** `oldestOnFile` must not surface a species the ingest could not
//     read (RULINGS R47, R54).
//  4. **`resolveIDSpace` is a fact off a row, bounded by distance** — it answers inside the record's
//     reach and answers nothing outside it, never a guessed city.
//

import Foundation
import Testing
@testable import Cypress

@Suite("City segment · queries")
struct CityQueriesTests {

    // MARK: - Harness (`SecondCityGeographyTests`', verbatim)

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

    private static func cityQueries(_ store: CypressStore) throws -> CityQueries {
        let schema = try #require(store.seed, "the store opened without a seed attached")
        return CityQueries(schema: schema)
    }

    private static func scalar(_ sql: String, on store: CypressStore) async throws -> Int {
        try await store.queue.read { connection in
            let statement = try connection.prepare(sql)
            defer { statement.finalize() }
            return try statement.fetchOne { try $0.int("n") } ?? -1
        }
    }

    static let downtownSanJose = Coordinate(latitude: 37.3352, longitude: -121.8895)
    static let outerSunset = Coordinate(latitude: 37.7533, longitude: -122.4934)
    static let sacramento = Coordinate(latitude: 38.5816, longitude: -121.4944)

    static let now = Date(timeIntervalSince1970: 1_784_505_600) // 2026-07-20
    private static let deviceID = UUID(uuidString: "02040000-0000-4000-8000-000000000204")!

    private static func api(_ store: CypressStore) -> LocalAPI {
        LocalAPI(store: store, deviceID: deviceID, now: { now })
    }

    // MARK: - 1 · `resolveIDSpace` is a fact off a row, bounded by distance

    @Test("a San Francisco reader resolves sf")
    func sanFranciscoResolvesSF() async throws {
        let store = try await Self.store()
        let queries = try Self.cityQueries(store)
        let space = try await store.queue.read { connection in
            try queries.resolveIDSpace(
                near: Self.outerSunset, radiusM: AlmanacLimits.fallbackRadiusM, connection: connection
            )
        }
        #expect(space == "sf")
    }

    @Test("a San Jose reader resolves us-ca-sj")
    func sanJoseResolvesItsOwnSpace() async throws {
        let store = try await Self.store()
        let queries = try Self.cityQueries(store)
        let space = try await store.queue.read { connection in
            try queries.resolveIDSpace(
                near: Self.downtownSanJose, radiusM: AlmanacLimits.fallbackRadiusM, connection: connection
            )
        }
        #expect(space == "us-ca-sj")
    }

    @Test("a reader outside both cities resolves no city, never a guessed one")
    func outsideBothCitiesResolvesNothing() async throws {
        let store = try await Self.store()
        let queries = try Self.cityQueries(store)
        let space = try await store.queue.read { connection in
            try queries.resolveIDSpace(
                near: Self.sacramento, radiusM: AlmanacLimits.fallbackRadiusM, connection: connection
            )
        }
        #expect(space == nil, "Sacramento resolved a city; the radius bound stopped working")
    }

    // MARK: - 2 · The fused-bundle case (RULINGS R48's shape, applied to a citywide read)

    /// Measures the fused bundle directly, then proves `speciesMix(idSpace:)` matches the scoped
    /// half rather than the whole — and, deliberately, that the whole is bigger than either half, so
    /// this test cannot pass by accident on a seed that turns out to hold only one city.
    @Test("a citywide species mix is scoped to its own id_space, and does not span both cities")
    func speciesMixDoesNotSpanBothCities() async throws {
        let store = try await Self.store()
        let queries = try Self.cityQueries(store)

        let (sfMix, sjMix) = try await store.queue.read { connection in
            (
                try queries.speciesMix(idSpace: "sf", connection: connection),
                try queries.speciesMix(idSpace: "us-ca-sj", connection: connection)
            )
        }
        let sfTotal = sfMix.reduce(0) { $0 + $1.treeCount }
        let sjTotal = sjMix.reduce(0) { $0 + $1.treeCount }

        let directSF = try await Self.scalar(
            """
            SELECT COUNT(*) AS n FROM \(Self.seed).trees t
             WHERE t.id_space = 'sf' AND t.status IN ('alive','declining')
               AND t.deleted_at IS NULL AND t.species_current IS NOT NULL
            """,
            on: store
        )
        let directSJ = try await Self.scalar(
            """
            SELECT COUNT(*) AS n FROM \(Self.seed).trees t
             WHERE t.id_space = 'us-ca-sj' AND t.status IN ('alive','declining')
               AND t.deleted_at IS NULL AND t.species_current IS NOT NULL
            """,
            on: store
        )

        #expect(directSF > 0 && directSJ > 0, "one of the two cities has nothing standing; the probe cannot fire")
        #expect(sfTotal == directSF, "the sf-scoped mix does not match a direct sf-only count")
        #expect(sjTotal == directSJ, "the us-ca-sj-scoped mix does not match a direct us-ca-sj-only count")
        #expect(sfTotal != sjTotal, "the two cities' counts coincide; this cannot prove scoping worked")
        #expect(
            sfTotal < sfTotal + sjTotal && sjTotal < sfTotal + sjTotal,
            "each city's own count should be strictly less than the fused total"
        )
    }

    /// The same claim, read through the segment's own API rather than through `CityQueries` directly
    /// — the shape `SecondCityGeographyTests.theCountCardNamesThePopulationItCounted` uses for R48.
    @Test("LocalAPI.city(near:) scopes card 2's composition to the reader's own city")
    func cityAPIScopesCompositionToOneCity() async throws {
        let store = try await Self.store()

        let sfCity = try await Self.api(store).city(near: Self.outerSunset, in: .here)
        let sjCity = try await Self.api(store).city(near: Self.downtownSanJose, in: .here)

        let sfComposition = try #require(sfCity.snapshot?.cityComposition, "no composition for a San Francisco reader")
        let sjComposition = try #require(sjCity.snapshot?.cityComposition, "no composition for a San Jose reader")

        #expect(sfComposition.treeCount != sjComposition.treeCount, "both readers saw the same count")

        let directSF = try await Self.scalar(
            """
            SELECT COUNT(*) AS n FROM \(Self.seed).trees t
             WHERE t.id_space = 'sf' AND t.status IN ('alive','declining')
               AND t.deleted_at IS NULL AND t.species_current IS NOT NULL
            """,
            on: store
        )
        #expect(sfComposition.treeCount == directSF, "the API's composition drifted from a direct sf-only count")
    }

    // MARK: - 3 · The vacant-site exclusion

    /// **`planted_year` alone cannot tell this story — measured, not assumed.** San Francisco's
    /// oldest-dated vacant site and its oldest-dated standing tree share a `planted_year` of 1955:
    /// `1955-09-19` (a vacant site) sorts before `1955-10-20` (a standing tree) once `planted_on` is
    /// compared at day grain, which is what `CityQueries.oldestOnFile`'s `ORDER BY t.planted_on`
    /// actually does. So this reads the true raw-oldest row (status and all, ordered the same way the
    /// query orders) and checks it by identity rather than by year, which a coincidental tie would
    /// pass either way.
    @Test("oldestOnFile never lets a vacant site's planting date stand in for a tree's")
    func oldestOnFileExcludesVacantSites() async throws {
        let store = try await Self.store()
        let queries = try Self.cityQueries(store)
        let schema = try #require(store.seed)

        var exercisedThePreconditionAtLeastOnce = false

        for space in ["sf", "us-ca-sj"] {
            let rawRow = try await store.queue.read { connection -> (uuid: UUID, status: String)? in
                let statement = try connection.prepare("""
                    SELECT t.\(schema.treeIdentityColumn) AS tree_uuid, t.status AS status
                      FROM \(Self.seed).trees t
                     WHERE t.id_space = '\(space)' AND t.planted_on IS NOT NULL AND t.deleted_at IS NULL
                     ORDER BY t.planted_on LIMIT 1
                    """)
                defer { statement.finalize() }
                return try statement.fetchOne { row in
                    (uuid: try row.uuid("tree_uuid"), status: try row.string("status"))
                }
            }
            let raw = try #require(rawRow, "\(space) has no dated row at all; the probe cannot fire")

            let found = try await store.queue.read { connection in
                try queries.oldestOnFile(idSpace: space, limit: 1, connection: connection)
            }
            let top = try #require(found.first, "\(space) has no oldest-on-file row at all")

            if raw.status == "vacant_site" {
                // The precondition this test exists to exercise: the raw oldest-dated row in this
                // city really is a vacant site, so a regression that dropped the status filter would
                // have returned it as "the oldest on file" — this is what would have caught that.
                exercisedThePreconditionAtLeastOnce = true
                #expect(top.treeID != raw.uuid, "\(space)'s oldest-on-file row is the vacant site itself")
            } else {
                // The raw-oldest row already happens to be standing, so there is nothing here for
                // the exclusion to change — the query's answer should simply agree with it.
                #expect(top.treeID == raw.uuid, "\(space)'s top row moved even though the raw oldest was already standing")
            }
        }

        #expect(
            exercisedThePreconditionAtLeastOnce,
            "no city's raw-oldest row was a vacant site; this suite never exercised the exclusion"
        )
    }

    // MARK: - 4 · The stub-species exclusion (RULINGS R47, R54)

    /// Reads with a limit wide enough to cover every dated, standing tree in the city, so a stub
    /// species is excluded because the predicate excluded it — not because it never would have
    /// ranked high enough to appear.
    ///
    /// **Checked by tree identity, not by the printed name.** `COALESCE(s.common_name,
    /// s.scientific_name)` — this query's own projection — never surfaces the `':: '` marker for a
    /// stub species, because R54 measured that every stub row's `common_name` is sound (`9662`,
    /// `Magnolia`, …). So a name-shaped assertion on the result would pass whether or not the `WHERE`
    /// clause excluded anything; this instead reads which *trees* the ingest could not name and
    /// proves none of their ids reached the result.
    @Test("oldestOnFile never surfaces a species the ingest could not read")
    func oldestOnFileExcludesStubSpecies() async throws {
        let store = try await Self.store()
        let queries = try Self.cityQueries(store)
        let schema = try #require(store.seed)

        let stubTreeIDs = try await store.queue.read { connection -> [UUID] in
            let statement = try connection.prepare("""
                SELECT t.\(schema.treeIdentityColumn) AS tree_uuid
                  FROM \(Self.seed).trees t
                  JOIN \(Self.seed).species s ON s.id = t.species_current
                 WHERE t.id_space = 'sf' AND t.status IN ('alive','declining') AND t.deleted_at IS NULL
                   AND t.planted_on IS NOT NULL AND s.scientific_name LIKE ':: %'
                """)
            defer { statement.finalize() }
            return try statement.fetchAll { try $0.uuid("tree_uuid") }
        }

        let wideCount = try await Self.scalar(
            """
            SELECT COUNT(*) AS n FROM \(Self.seed).trees t
             WHERE t.id_space = 'sf' AND t.status IN ('alive','declining') AND t.deleted_at IS NULL
               AND t.planted_on IS NOT NULL
            """,
            on: store
        )

        let found = try await store.queue.read { connection in
            try queries.oldestOnFile(idSpace: "sf", limit: wideCount, connection: connection)
        }
        let foundIDs = Set(found.map(\.treeID))

        // Presence check: if the corpus stops carrying a dated stub-species tree, this test still
        // guards the query but no longer proves the guard did anything — recorded rather than hidden.
        #expect(!stubTreeIDs.isEmpty, "no dated stub-species sf tree exists; this suite guards nothing")
        #expect(found.count == wideCount - stubTreeIDs.count, "the exclusion did not remove exactly the stub rows")
        for stubID in stubTreeIDs {
            #expect(!foundIDs.contains(stubID), "a stub-species tree (\(stubID)) reached the oldest-on-file list")
        }
    }
}
