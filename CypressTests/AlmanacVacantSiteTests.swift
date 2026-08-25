import Foundation
import Testing
@testable import Cypress

/// **The 12,518 vacant planting sites, and what screen 12 does and does not do with them**
/// (ERRATA E11 → E107 → E113 → **E115**).
///
/// Two ERRATA entries record `AlmanacQueries` as excluding vacant sites "by construction (an inner
/// `JOIN` to species)". That is the wrong mechanism, and the difference is not academic: acting on
/// it — widening the join so the almanac can "see" sites — admits **no site at all**, admits 52
/// non-taxon trees into a denominator RULINGS R5 fixed at 11,026, and then throws before it draws,
/// taking the whole screen down. What excludes a site is `AlmanacQueries.standing`, deliberately,
/// and it is right.
///
/// So most of this suite is a guard rather than a regression: it pins the mechanism, in the seed's
/// own numbers, at the exact spot two documents point somebody at. The one thing here that *was*
/// broken is `firstBloom`, the only read in the file that starts from a contribution rather than
/// from the inventory and the only one that did not apply the file's own standing rule.
///
/// Every number below is measured against the shipped seed — 195,309 rows — and not against a
/// fixture, because a query that is right about ten rows is how E47 got a denominator of 40.
@Suite("Almanac · vacant planting sites")
struct AlmanacVacantSiteTests {

    // MARK: - Harness

    /// The bundled seed, or `CYPRESS_SEED_PATH`. Same resolution `SeedContractTests` uses.
    static var seedURL: URL? {
        if let path = ProcessInfo.processInfo.environment["CYPRESS_SEED_PATH"] {
            return URL(fileURLWithPath: path)
        }
        return SeedDatabase.urlInBundle(Bundle(for: BundleToken.self))
            ?? SeedDatabase.urlInBundle()
    }

    private final class BundleToken {}

    private static let seed = SeedDatabase.schemaName

    private static func store() async throws -> CypressStore {
        let url = try #require(seedURL, "no seed database; set CYPRESS_SEED_PATH")
        return try await CypressStore.inMemory(seedURL: url)
    }

    /// One scalar out of the attached seed, so a claim in prose can be a claim in SQL.
    private static func count(_ sql: String, on store: CypressStore) async throws -> Int {
        try await store.queue.read { connection in try scalar(sql, on: connection) }
    }

    private static func scalar(_ sql: String, on connection: SQLiteConnection) throws -> Int {
        let statement = try connection.prepare(sql)
        defer { statement.finalize() }
        return try statement.fetchOne { try $0.int("n") } ?? -1
    }

    private static func uuids(_ sql: String, on store: CypressStore) async throws -> [UUID] {
        try await store.queue.read { connection in
            let statement = try connection.prepare(sql)
            defer { statement.finalize() }
            return try statement.fetchAll { try $0.uuid("uuid") }
        }
    }

    private static func neighborhoodID(named name: String, on store: CypressStore) async throws -> Int {
        try await count("SELECT id AS n FROM \(seed).neighborhoods WHERE name = '\(name)'", on: store)
    }

    // MARK: - The population

    /// The number E107 and E11 are both about, checked in the scope the almanac reads in.
    ///
    /// If a seed rebuild ever stops producing these rows — BUILD-PLAN §7 makes them out of the
    /// `qSpecies` placeholder strings, which is exactly the kind of mapping that gets "cleaned up" —
    /// screen 12, screen 01's site card and the whole of E107 go quiet with nothing failing.
    @Test("the seed holds every vacant planting site inside a neighborhood")
    func population() async throws {
        let store = try await Self.store()
        let corpus = try await SeedCorpus.current(store)

        let total = try await Self.count(
            "SELECT COUNT(*) AS n FROM \(Self.seed).trees WHERE status = 'vacant_site'",
            on: store
        )
        #expect(total == corpus.vacantSites)

        // The almanac reads `neighborhood_id = ? AND deleted_at IS NULL`, so a site outside that
        // scope is a site no neighborhood surface could ever count.
        //
        // ── The hole a second city opened, asserted rather than left to be discovered ──────────
        // `seed.neighborhoods` is San Francisco's 41 Analysis Neighborhoods and nothing else, so
        // every San Jose row carries `neighborhood_id IS NULL` and is invisible to the almanac, the
        // coverage panel and the neighborhood species mix. Nothing renders wrongly — a whole city's
        // rows simply never appear. That is a known hole in the shipped build (ERRATA E176), and it
        // is pinned here as an exact number so that fixing it, or making it worse, is a red test
        // rather than a thing somebody notices in the field.
        let outOfScope = try await Self.count(
            """
            SELECT COUNT(*) AS n FROM \(Self.seed).trees
             WHERE status = 'vacant_site' AND neighborhood_id IS NULL
            """,
            on: store
        )
        #expect(
            outOfScope == corpus.vacantSitesWithNoNeighborhood,
            "\(outOfScope) vacant sites sit outside every neighborhood, expected \(corpus.vacantSitesWithNoNeighborhood); a neighborhood layer for the second city would change this"
        )

        let inScope = try await Self.count(
            """
            SELECT COUNT(*) AS n FROM \(Self.seed).trees
             WHERE status = 'vacant_site' AND neighborhood_id IS NOT NULL AND deleted_at IS NULL
            """,
            on: store
        )
        #expect(inScope == corpus.vacantSites - corpus.vacantSitesWithNoNeighborhood)

        // A site has no species. This is the fact the inner join is wrongly credited with acting on.
        let withSpecies = try await Self.count(
            """
            SELECT COUNT(*) AS n FROM \(Self.seed).trees
             WHERE status = 'vacant_site' AND species_current IS NOT NULL
            """,
            on: store
        )
        #expect(withSpecies == 0)

        // **This is the number the switch cost most.** Under the DataSF export every one of the 41
        // neighborhoods held vacant sites, so the block E115 proposes cleared a cold-start floor
        // everywhere in the city (ARCHITECTURE §5.6). SF Public Works' own layer has no vacant-site
        // category at all — `PlantType` is `Tree` on all 133,577 of its records — so 12,518 sites
        // become 153 and **17 neighborhoods now have none**. Screen 12's empty-site row will be
        // absent or tiny across most of the city. Pinned rather than relaxed, so the day the number
        // moves again somebody has to say why.
        let neighborhoodsWithNone = try await Self.count(
            """
            SELECT COUNT(*) AS n FROM (
              SELECT neighborhood_id FROM \(Self.seed).trees
               WHERE deleted_at IS NULL AND neighborhood_id IS NOT NULL
               GROUP BY neighborhood_id
              HAVING SUM(status = 'vacant_site') = 0)
            """,
            on: store
        )
        #expect(neighborhoodsWithNone == corpus.neighborhoodsWithNoVacantSite)

        let sunset = try await Self.neighborhoodID(named: "Sunset/Parkside", on: store)
        let here = try await Self.count(
            """
            SELECT COUNT(*) AS n FROM \(Self.seed).trees
             WHERE status = 'vacant_site' AND deleted_at IS NULL AND neighborhood_id = \(sunset)
            """,
            on: store
        )
        #expect(here == corpus.sunsetVacantSites)
    }

    // MARK: - What actually excludes them

    /// **The correction E115 records, stated as arithmetic.**
    ///
    /// `speciesMix`'s join is inner. Replacing it with a `LEFT JOIN` — the change both E107 and
    /// E113 point at — admits zero vacant sites, because `t.status IN ('alive','declining')` has
    /// already removed them, and because `s.id = t.species_current` evaluates to NULL rather than
    /// to true for the NULL `species_current` every site carries. It admits 52 non-taxon trees
    /// instead.
    @Test("widening the species join admits no vacant site and 52 non-taxon trees")
    func theJoinIsNotTheExclusion() async throws {
        let store = try await Self.store()
        let corpus = try await SeedCorpus.current(store)
        let sunset = try await Self.neighborhoodID(named: "Sunset/Parkside", on: store)
        let scope = "t.neighborhood_id = \(sunset) AND t.deleted_at IS NULL"

        // A vacant site cannot survive an inner join even with the status predicate removed, which
        // is the NULL-comparison claim proved rather than reasoned about (E89, E109).
        let vacantThroughInnerJoin = try await Self.count(
            """
            SELECT COUNT(*) AS n FROM \(Self.seed).trees t
              JOIN \(Self.seed).species s ON s.id = t.species_current
             WHERE t.status = 'vacant_site'
            """,
            on: store
        )
        #expect(vacantThroughInnerJoin == 0)

        // …and none survives a LEFT join with the status predicate in place either, which is the
        // whole point: the join was never the gate.
        let vacantThroughLeftJoin = try await Self.count(
            """
            SELECT COUNT(*) AS n FROM \(Self.seed).trees t
              LEFT JOIN \(Self.seed).species s ON s.id = t.species_current
             WHERE \(scope) AND t.status IN ('alive','declining') AND t.status = 'vacant_site'
            """,
            on: store
        )
        #expect(vacantThroughLeftJoin == 0)

        // What widening it *would* do to the two numbers screen 12 prints.
        let innerTrees = try await Self.count(
            """
            SELECT COUNT(*) AS n FROM \(Self.seed).trees t
              JOIN \(Self.seed).species s ON s.id = t.species_current
             WHERE \(scope) AND t.status IN ('alive','declining')
            """,
            on: store
        )
        let leftTrees = try await Self.count(
            """
            SELECT COUNT(*) AS n FROM \(Self.seed).trees t
              LEFT JOIN \(Self.seed).species s ON s.id = t.species_current
             WHERE \(scope) AND t.status IN ('alive','declining')
            """,
            on: store
        )
        #expect(innerTrees == corpus.sunsetTreesWithSpecies)
        #expect(leftTrees == corpus.sunsetTreesLeftJoined)
        #expect(
            leftTrees - innerTrees == corpus.sunsetTreesLeftJoined - corpus.sunsetTreesWithSpecies,
            "the widened join gains non-taxon trees, never sites"
        )
        #expect(leftTrees > innerTrees, "the control: this neighborhood does hold non-taxon trees")

        // And the group it would add cannot name itself: `SpeciesShare.name` is not optional and
        // `row.uuid("species_uuid")` on this row raises `unexpectedNull`, so `speciesMix` throws,
        // `AlmanacModel` catches it as `.failed`, and screen 12 draws `AlmanacCopy.loadFailed` and
        // a retry in place of the almanac (ERRATA E126) — the whole screen, not one group.
        let namelessGroups = try await Self.count(
            """
            SELECT COUNT(*) AS n FROM (
              SELECT s.uuid AS species_uuid FROM \(Self.seed).trees t
                LEFT JOIN \(Self.seed).species s ON s.id = t.species_current
               WHERE \(scope) AND t.status IN ('alive','declining')
               GROUP BY s.id
              HAVING species_uuid IS NULL)
            """,
            on: store
        )
        #expect(namelessGroups == 1)
    }

    /// The live query, at the numbers the widened one would move: 215 species over 11,026 trees.
    ///
    /// 215 is RULINGS **R5**, which ruled screen 08's denominator is 215 and stays there. Screen 12
    /// and screen 08 count the same population, so a join widened here silently reopens a ruling
    /// taken somewhere else.
    @Test("the live species mix is unchanged and complete")
    func speciesMixIsUnchangedAndComplete() async throws {
        let store = try await Self.store()
        let corpus = try await SeedCorpus.current(store)
        let schema = try #require(store.seed)
        let queries = AlmanacQueries(schema: schema)
        let sunset = try await Self.neighborhoodID(named: "Sunset/Parkside", on: store)

        let mix = try await store.queue.read { connection in
            try queries.speciesMix(scope: .neighborhood(id: sunset, name: "Sunset/Parkside"), connection: connection)
        }

        #expect(mix.count == corpus.sunsetSpeciesInMix)
        #expect(mix.reduce(0) { $0 + $1.treeCount } == corpus.sunsetTreesWithSpecies)
        #expect(mix.allSatisfy { !$0.name.isEmpty })
    }

    // MARK: - The four inventory reads

    /// A site is not an elder, not a newcomer and not a young tree anybody can go and look at — and
    /// under the DataSF export that was not incidental: **9,294 of the 12,518 sites carried a
    /// planting date**, so `planted_on` alone would put basins in two of screen 12's three season
    /// rows and in the coverage card.
    ///
    /// **Under `--source city` the three planting reads return nothing at all**, because SF Public
    /// Works' own layer publishes no `PlantDate` for any record. Every control in this test then
    /// fails to fire, so the exclusion it checks would be true of an empty answer and the test would
    /// pass having measured nothing. That is stated here rather than allowed to happen quietly: the
    /// controls run only where the source can support them, the darkness is asserted against
    /// `seed_meta.columns_absent_from_source`, and screen 12's elder, plantings and coverage rows are
    /// **empty for the whole city** on the shipped seed. It is one of the two real costs of #91.
    @Test("no inventory read returns a vacant site")
    func inventoryReadsExcludeSites() async throws {
        let store = try await Self.store()
        let corpus = try await SeedCorpus.current(store)
        let schema = try #require(store.seed)
        let queries = AlmanacQueries(schema: schema)
        let sunset = try await Self.neighborhoodID(named: "Sunset/Parkside", on: store)
        let hasPlantingDates = corpus.publishes("PlantDate")

        let datedSites = try await Self.count(
            """
            SELECT COUNT(*) AS n FROM \(Self.seed).trees
             WHERE status = 'vacant_site' AND planted_on IS NOT NULL
            """,
            on: store
        )
        // 9,294 under the DataSF export; 22 under the city's row set, because the export gives a
        // planting date to a site the city no longer lists as anything. Still non-zero, so the
        // exclusion below is still doing work rather than agreeing with an empty set.
        #expect(datedSites == corpus.datedVacantSites)
        #expect(corpus.datedVacantSites > 0, "the control: `planted_on` alone would put basins in the season rows")

        let vacantIDs = Set(try await Self.uuids(
            """
            SELECT uuid FROM \(Self.seed).trees
             WHERE status = 'vacant_site' AND neighborhood_id = \(sunset)
            """,
            on: store
        ))
        #expect(vacantIDs.count == corpus.sunsetVacantSites)

        // Every spring the seed knows about, not just the current one, so this does not pass by
        // landing outside the data.
        let standingWithDate = try await Self.count(
            """
            SELECT COUNT(*) AS n FROM \(Self.seed).trees
             WHERE neighborhood_id = \(sunset) AND deleted_at IS NULL
               AND planted_on IS NOT NULL AND status IN ('alive','declining')
            """,
            on: store
        )

        let elder = try await store.queue.read { connection in
            try queries.elder(scope: .neighborhood(id: sunset, name: "Sunset/Parkside"), connection: connection)
        }
        // `elder` is `MIN(planted_on)` within the neighborhood, so it is nil for every
        // neighborhood in a seed with no planting dates. Where the source has them, its being
        // non-nil is the control that makes the exclusion below mean something.
        #expect(
            (elder != nil) == hasPlantingDates,
            "elder is \(elder == nil ? "nil" : "set") while the source \(hasPlantingDates ? "does" : "does not") publish PlantDate"
        )
        #expect(elder.map { !vacantIDs.contains($0.treeID) } ?? !hasPlantingDates)

        let planted = try await store.queue.read { connection in
            try queries.plantings(
                scope: .neighborhood(id: sunset, name: "Sunset/Parkside"),
                from: "0000-01-01",
                to: "9999-12-31",
                connection: connection
            )
        }
        let plantedTotal = planted.reduce(0) { $0 + $1.treeCount }
        #expect(plantedTotal == standingWithDate)
        #expect(
            (plantedTotal > 0) == hasPlantingDates,
            "the control: dated plantings are \(plantedTotal), and the source \(hasPlantingDates ? "does" : "does not") publish PlantDate"
        )

        let young = try await store.queue.read { connection in
            try queries.youngTreesWithoutVisits(
                scope: .neighborhood(id: sunset, name: "Sunset/Parkside"),
                plantedOnOrAfter: "0000-01-01",
                limit: 5_000,
                connection: connection
            )
        }
        #expect(young.allSatisfy { !vacantIDs.contains($0.id) })
        #expect(
            !young.isEmpty == hasPlantingDates,
            "the control: the coverage read returned \(young.count) trees, and the source \(hasPlantingDates ? "does" : "does not") publish PlantDate"
        )
    }

    // MARK: - The read that was actually broken

    /// **`firstBloom` did not apply the standing rule** (ERRATA E115).
    ///
    /// It is the only read in `AlmanacQueries` that starts from a contribution rather than from the
    /// inventory, and it filtered `deleted_at` and nothing else. A `flowering` visit against a
    /// vacant site therefore produced `First bloom of the year` over a planting basin — on the one
    /// row of screen 12 that names a specific record by its street and is tappable.
    ///
    /// That the app cannot currently write such a visit is not a defense: it cannot only because
    /// E113 redirects a site away from the tree profile the camera opens from, which is the
    /// almanac's own rule being enforced in another feature's router.
    @Test("a flowering visit on a vacant site is not the first bloom")
    func vacantSiteCannotBloom() async throws {
        let store = try await Self.store()
        let schema = try #require(store.seed)
        let queries = AlmanacQueries(schema: schema)
        let sunset = try await Self.neighborhoodID(named: "Sunset/Parkside", on: store)

        let site = try #require(try await Self.uuids(
            """
            SELECT uuid FROM \(Self.seed).trees
             WHERE status = 'vacant_site' AND neighborhood_id = \(sunset)
             ORDER BY id LIMIT 1
            """,
            on: store
        ).first)

        try await Self.recordFloweringVisit(on: site, at: "2026-04-01T09:00:00Z", in: store)

        let bloom = try await store.queue.read { connection in
            try queries.firstBloom(
                scope: .neighborhood(id: sunset, name: "Sunset/Parkside"),
                since: Date(timeIntervalSince1970: 0),
                connection: connection
            )
        }
        #expect(bloom == nil, "a basin bloomed")
    }

    /// The control that keeps the assertion above from passing for the wrong reason: the same visit
    /// on a standing tree in the same neighborhood is still the first bloom, and it wins even
    /// though the site's sighting is the earlier of the two.
    @Test("a flowering visit on a standing tree is still the first bloom")
    func standingTreeStillBlooms() async throws {
        let store = try await Self.store()
        let schema = try #require(store.seed)
        let queries = AlmanacQueries(schema: schema)
        let sunset = try await Self.neighborhoodID(named: "Sunset/Parkside", on: store)

        let site = try #require(try await Self.uuids(
            """
            SELECT uuid FROM \(Self.seed).trees
             WHERE status = 'vacant_site' AND neighborhood_id = \(sunset) ORDER BY id LIMIT 1
            """,
            on: store
        ).first)
        let tree = try #require(try await Self.uuids(
            """
            SELECT uuid FROM \(Self.seed).trees
             WHERE status = 'alive' AND neighborhood_id = \(sunset) ORDER BY id LIMIT 1
            """,
            on: store
        ).first)

        try await Self.recordFloweringVisit(on: site, at: "2026-03-01T09:00:00Z", in: store)
        try await Self.recordFloweringVisit(on: tree, at: "2026-04-01T09:00:00Z", in: store)

        let bloom = try await store.queue.read { connection in
            try queries.firstBloom(
                scope: .neighborhood(id: sunset, name: "Sunset/Parkside"),
                since: Date(timeIntervalSince1970: 0),
                connection: connection
            )
        }
        #expect(bloom?.treeID == tree)
    }

    // MARK: - Where a tree could go (R10, ERRATA E121)

    /// The query behind screen 12's new block, checked against the number E115 measured.
    ///
    /// 1,474 is the Sunset/Parkside site count E115 recorded, and the block reports exactly that — no
    /// A8 floor, because it counts city records rather than user actions. The nearest is scoped to the
    /// same neighborhood, so the tap can never send the reader from one basin to a basin in the next
    /// neighborhood over: subject and destination are one set.
    @Test("the vacant-sites read counts the neighborhood's basins and its nearest is one of them")
    func vacantSitesQuery() async throws {
        let store = try await Self.store()
        let corpus = try await SeedCorpus.current(store)
        let schema = try #require(store.seed)
        let queries = AlmanacQueries(schema: schema)
        let sunset = try await Self.neighborhoodID(named: "Sunset/Parkside", on: store)

        // A fix inside Sunset/Parkside.
        let here = Coordinate(latitude: 37.7530, longitude: -122.4850)
        let result = try await store.queue.read { connection in
            try queries.vacantSites(
                scope: .neighborhood(id: sunset, name: "Sunset/Parkside"),
                near: here,
                limit: AlmanacLimits.vacantSiteRowLimit,
                connection: connection
            )
        }

        // The count is the whole set and the rows are a page of it, which is the shape ERRATA E129
        // needs and ERRATA E38 governs: 1,474 is a `COUNT(*)`, 20 is what a map can hold.
        #expect(result.count == corpus.sunsetVacantSites)
        // A page of the whole set, or the whole set when it is smaller than a page. Under
        // `--source city` this neighborhood holds 7 basins, fewer than the 20-row limit, so the
        // page *is* everything — the shape E129 needs either way.
        #expect(result.nearest.count == min(corpus.sunsetVacantSites, AlmanacLimits.vacantSiteRowLimit))
        #expect(result.nearest.allSatisfy { $0.status == .vacantSite })
        let nearest = try #require(result.nearest.first?.id)

        // The nearest is a vacant site, and it is in this neighborhood — not merely the nearest
        // basin in the city.
        let ownStatusAndArea = try await store.queue.read { connection -> (String, Int) in
            let statement = try connection.prepare(
                "SELECT status, neighborhood_id AS nid FROM \(Self.seed).trees WHERE uuid = '\(nearest.uuidString)' COLLATE NOCASE"
            )
            defer { statement.finalize() }
            return try statement.fetchOne { (try $0.string("status"), try $0.int("nid")) } ?? ("", -1)
        }
        #expect(ownStatusAndArea.0 == "vacant_site")
        #expect(ownStatusAndArea.1 == sunset)
    }

    /// The presentation turns the read into the drawn block, and refuses to draw a statement the
    /// reader cannot act on.
    @Test("the block states the count and inherits the site screen's line, or is absent")
    func vacantSitesPresentation() throws {
        // A real count with a destination draws the row.
        let site = AlmanacPresentationTests.pin(930, status: .vacantSite)
        let drawn = AlmanacPresentation(almanac: Almanac(
            neighborhood: AlmanacNeighborhood(area: .named("Sunset/Parkside"),
                vacantSites: VacantSites(count: 1_474, nearest: [site]))
        ))
        let block = try #require(drawn.vacantSites)
        #expect(block.label == "Where a tree could go")
        #expect(block.title == "1,474 empty planting sites")
        // The row hands over the group it counted, not one basin out of it (ERRATA E129).
        #expect(block.group.subject == .vacantSites)
        #expect(block.group.pins == [site])
        #expect(block.group.count == 1_474)
        #expect(!block.group.isComplete, "20 of 1,474 is a page and must say so")
        // Inherits SitePresentation's line and crosses none of it: no "yet", no ask, no notification.
        #expect(!block.subtitle.lowercased().contains("yet"))
        #expect(!block.subtitle.lowercased().contains("plant a"))
        #expect(!block.subtitle.lowercased().contains("notif"))

        // A count with no destination is not a statement the reader can act on, so it does not draw.
        let noDestination = AlmanacPresentation(almanac: Almanac(
            neighborhood: AlmanacNeighborhood(area: .named("X"),
                vacantSites: VacantSites(count: 9, nearest: []))
        ))
        #expect(noDestination.vacantSites == nil)

        // A neighborhood with no basins draws nothing, even though E115 found none like it today.
        let none = AlmanacPresentation(almanac: Almanac(
            neighborhood: AlmanacNeighborhood(area: .named("X"), vacantSites: nil)
        ))
        #expect(none.vacantSites == nil)
    }

    /// Singular, for the general case E115's floor of 4 does not actually guarantee in a rebuilt seed.
    @Test("one empty site reads in the singular")
    func vacantSingular() throws {
        let one = AlmanacPresentation(almanac: Almanac(
            neighborhood: AlmanacNeighborhood(area: .named("X"),
                vacantSites: VacantSites(count: 1, nearest: [AlmanacPresentationTests.pin(931, status: .vacantSite)]))
        ))
        #expect(one.vacantSites?.title == "1 empty planting site")
    }

    private static func recordFloweringVisit(
        on treeUUID: UUID,
        at capturedAt: String,
        in store: CypressStore
    ) async throws {
        try await store.queue.write { connection in
            let statement = try connection.prepare(
                """
                INSERT INTO visits
                       (id, tree_uuid, device_id, client_uuid, phenology_tags,
                        captured_at, created_at, updated_at)
                VALUES (:id, :tree, :device, :client, :tags, :at, :at, :at)
                """
            )
            defer { statement.finalize() }
            _ = try statement.bind([
                ":id": UUID().uuidString,
                ":tree": treeUUID.uuidString,
                ":device": UUID().uuidString,
                ":client": UUID().uuidString,
                ":tags": "[\"\(PhenologyTag.flowering.rawValue)\"]",
                ":at": capturedAt
            ])
            try statement.run()
        }
    }
}
