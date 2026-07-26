import Foundation
import Testing
@testable import Cypress

/// **Screen 12's two counted rows, and where they go** (ERRATA E129).
///
/// The defect, in the project owner's words: "the button says walk the 11 but doesn't tell me where
/// they are or open a map; just takes me right to a tree's page." It was shipped twice —
/// `Where eyes are needed` (SCREENS.md 12 §4) handed out `firstTreeID`, and `Where a tree could go`
/// (RULINGS R10, ERRATA E121) handed out `nearestID` four commits later.
///
/// What makes that failure hard to test for is that both rows were *correct about everything else*.
/// The count was right, the copy was right, the destination rendered, and the tap worked. Nothing was
/// broken; the wrong question was being answered. So the assertions here are about the shape of the
/// answer rather than about its contents:
///
/// 1. **neither row carries one record any more** — the fields that held one id are gone, and what
///    replaced them holds the whole group the row counted;
/// 2. **the camera holds all of it**, because a map framed on the nearest few would be the same
///    defect one screen further along;
/// 3. **the sentence over the map says how much of the group is on it** (ERRATA E38), because the
///    vacant group is 1,474 records and 20 of them can be drawn.
///
/// The seed-backed half exists because a query that is right about a fixture is how ERRATA E47 got a
/// denominator of 40. Every number below is measured against the shipped 195,309 rows.
@Suite("Almanac · the two counted rows go to a map of the group")
struct PinSetDestinationTests {

    // MARK: - Fixtures

    private static let now = Date(timeIntervalSince1970: 1_784_505_600) // 2026-07-20
    /// `en_US` rather than `en_US_POSIX`, which the older almanac suite pins.
    ///
    /// POSIX is the right choice there — those tests are about window boundaries and a machine's own
    /// calendar. Here the assertions are about *grouping and spelling*, `1,474` and `nine`, and POSIX
    /// has no thousands separator, so pinning it would test a locale nobody reads the app in.
    private static let locale = Locale(identifier: "en_US")
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// One of `AlmanacPresentationTests`' pins, so the two suites cannot drift into describing
    /// different trees.
    private static func pin(_ index: Int, status: TreeStatus = .alive) -> TreePin {
        AlmanacPresentationTests.pin(index, status: status)
    }

    private static func present(
        coverage: CoverageGap? = nil,
        vacantSites: VacantSites? = nil
    ) -> AlmanacPresentation {
        AlmanacPresentation(
            almanac: Almanac(neighborhood: AlmanacNeighborhood(
                name: "Sunset/Parkside",
                coverage: coverage,
                vacantSites: vacantSites
            )),
            now: now,
            calendar: calendar,
            locale: locale
        )
    }

    /// A whole coverage read: `count` young trees, none of them visited, all within the walk radius.
    private static func coverageGap(_ count: Int) -> CoverageGap {
        CoverageGap(trees: Series(complete: (0..<count).map {
            CoverageTree(pin: pin(300 + $0), distanceM: Double(80 + $0 * 40))
        }))
    }

    /// `count` basins in the neighbourhood, of which `shown` are carried to the map.
    private static func vacant(count: Int, shown: Int) -> VacantSites {
        VacantSites(count: count, nearest: (0..<shown).map { pin(400 + $0, status: .vacantSite) })
    }

    // MARK: - Neither row carries one record

    /// **The assertion the whole round is for.** Nine trees counted, nine trees handed over.
    ///
    /// The old field was `Coverage.firstTreeID: UUID`, so this cannot compile against the broken app
    /// at all — which is the strongest form the check can take, and the reason it is written against
    /// the group rather than against a route enum.
    @Test("the coverage CTA hands over every tree it counted, not the nearest one")
    func coverageCTACarriesTheWholeGroup() throws {
        let block = try #require(Self.present(coverage: Self.coverageGap(9)).coverage)

        #expect(block.title == "9 young trees with no visits since planting")
        #expect(block.ctaTitle == "Walk the nine")

        #expect(block.group.subject == .coverageGap)
        #expect(block.group.pins.count == 9, "the walk went to one tree of the nine")
        #expect(block.group.count == 9)
        #expect(block.group.isComplete, "a whole coverage read is a whole group")
        #expect(block.group.neighborhoodName == "Sunset/Parkside")
    }

    /// The same, on the row that shipped the defect a second time.
    @Test("the vacant-sites row hands over the nearest basins, not the nearest basin")
    func vacantRowCarriesAGroup() throws {
        let block = try #require(Self.present(vacantSites: Self.vacant(count: 1_474, shown: 20)).vacantSites)

        #expect(block.title == "1,474 empty planting sites")
        #expect(block.group.subject == .vacantSites)
        #expect(block.group.pins.count == 20, "the row went to one basin of 1,474")
        #expect(block.group.count == 1_474)
        #expect(!block.group.isComplete)
    }

    /// Stated once, over both rows, because "it opens one record" is the defect and not a property of
    /// either row in particular. Anything counted plurally leaves with more than one place on it.
    @Test("no counted row on screen 12 resolves to a single record")
    func noCountedRowResolvesToOneRecord() throws {
        let presentation = Self.present(
            coverage: Self.coverageGap(11),
            vacantSites: Self.vacant(count: 1_474, shown: 20)
        )

        let groups = [
            try #require(presentation.coverage).group,
            try #require(presentation.vacantSites).group,
        ]
        for group in groups {
            #expect(group.pins.count > 1, "\(group.subject) still leaves with one record")
            #expect(Set(group.pins.map(\.id)).count == group.pins.count, "a record twice on one map")
        }
    }

    /// The one place a group legitimately holds one record: a neighbourhood with a single basin. E115
    /// found none like it in the shipped seed, but §5.6 is a rule about the general case, and the
    /// sentence for it has to be a sentence.
    @Test("a group of one is a group, and says so in the singular")
    func aGroupOfOne() throws {
        let block = try #require(Self.present(vacantSites: Self.vacant(count: 1, shown: 1)).vacantSites)
        #expect(block.title == "1 empty planting site")

        let screen = PinSetPresentation(set: block.group, locale: Self.locale)
        #expect(screen.coverage == "It is on this map.")

        let one = try #require(Self.present(coverage: Self.coverageGap(1)).coverage)
        #expect(one.ctaTitle == "Walk to it")
        #expect(PinSetPresentation(set: one.group, locale: Self.locale).coverage == "It is on this map.")
    }

    // MARK: - What the destination says (ERRATA E38)

    /// **E38 on this screen.** A page of 20 out of 1,474 must not read as the whole set, and the count
    /// above it is still allowed to be 1,474 because that number is a `COUNT(*)` the data stands
    /// behind rather than the size of the read.
    @Test("a map holding a page says how big the page is, and never says all of them")
    func aPageSaysItIsAPage() throws {
        let block = try #require(Self.present(vacantSites: Self.vacant(count: 1_474, shown: 20)).vacantSites)
        let screen = PinSetPresentation(set: block.group, locale: Self.locale)

        #expect(screen.subject == "1,474 empty planting sites")
        #expect(screen.coverage == "The 20 nearest are on this map.")
        #expect(!screen.coverage.lowercased().contains("all"), "a page called itself the series")
        #expect(screen.pins.count == 20)
    }

    @Test("a map holding the whole group says so, in the number the row spelled out")
    func awholeGroupSaysAllOfThem() throws {
        let block = try #require(Self.present(coverage: Self.coverageGap(9)).coverage)
        let screen = PinSetPresentation(set: block.group, locale: Self.locale)

        #expect(screen.subject == "9 young trees with no visits since planting")
        #expect(screen.coverage == "All nine are on this map.")
    }

    /// The destination's title and headline are the almanac's own strings, so there is one place the
    /// claim can be wrong rather than two. `Where eyes are needed` is SCREENS.md 12 §4's micro-label
    /// verbatim; `Where a tree could go` is R10's.
    @Test("the screen is named after the block the reader tapped")
    func theTitleIsTheBlocksOwnLabel() throws {
        let coverage = try #require(Self.present(coverage: Self.coverageGap(9)).coverage)
        let vacant = try #require(Self.present(vacantSites: Self.vacant(count: 1_474, shown: 20)).vacantSites)

        #expect(PinSetPresentation(set: coverage.group, locale: Self.locale).title == "Where eyes are needed")
        #expect(PinSetPresentation(set: vacant.group, locale: Self.locale).title == "Where a tree could go")
        #expect(PinSetPresentation(set: coverage.group, locale: Self.locale).subject == coverage.title)
        #expect(PinSetPresentation(set: vacant.group, locale: Self.locale).subject == vacant.title)
    }

    // MARK: - The camera

    /// A map that opened on the nearest three would be the same defect one screen further along, so
    /// the opening frame is asserted to hold every record.
    ///
    /// **Against the trees the card counted, not against the group's own array.** Written the obvious
    /// way — iterating `block.group.pins` — this test cannot fail for the reason it exists: a bug that
    /// drops records from the group also drops them from the loop, and the frame trivially holds what
    /// is left. That was checked by breaking it, and it passed. So the source list is the subject and
    /// the group is what is under test.
    @Test("the opening camera holds every tree the card counted")
    func theCameraHoldsEveryPin() throws {
        let counted = Self.coverageGap(11)
        let block = try #require(Self.present(coverage: counted).coverage)
        let frame = PinSetPresentation(set: block.group, locale: Self.locale).frame

        for tree in counted.trees.items {
            #expect(frame.contains(tree.pin.coordinate), "\(tree.id) is off screen when the map opens")
        }
    }

    /// The floor: a group of one must not open at a zoom with nothing on screen but its own pin.
    /// `MapLayout.defaultSpanMetres` is screen 01's opening scale and the scale ERRATA E12 measured as
    /// the point where pins stop fusing, so it is the floor rather than a number of my own.
    @Test("a group of one opens at screen 01's own scale, not on top of the pin")
    func aSinglePinGetsAReadableCamera() throws {
        let block = try #require(Self.present(vacantSites: Self.vacant(count: 1, shown: 1)).vacantSites)
        let frame = PinSetPresentation(set: block.group, locale: Self.locale).frame

        let acrossM = Coordinate(latitude: frame.minLatitude, longitude: frame.minLongitude)
            .distance(to: Coordinate(latitude: frame.maxLatitude, longitude: frame.minLongitude))
        #expect(acrossM >= MapLayout.defaultSpanMetres * 0.99)
        #expect(frame.contains(block.group.pins[0].coordinate))
    }

    // MARK: - What the map draws each record as

    /// **A basin must not be drawn as a tree.** RULINGS R7 gave the vacant site its own pin precisely
    /// because borrowing `removed`'s made the map the last surface still claiming a tree had been
    /// there (ERRATA E107, E113). This destination is a new map, and it is the obvious place for that
    /// claim to come back.
    @Test("a group of basins draws as basins and a group of trees draws as city trees")
    func eachRecordKeepsItsOwnPin() throws {
        let coverage = try #require(Self.present(coverage: Self.coverageGap(9)).coverage)
        let vacant = try #require(Self.present(vacantSites: Self.vacant(count: 1_474, shown: 20)).vacantSites)

        #expect(coverage.group.pins.allSatisfy { MapPinKind.kind(for: $0) == .cityTree })
        #expect(vacant.group.pins.allSatisfy { MapPinKind.kind(for: $0) == .vacantSite })
        #expect(vacant.group.pins.allSatisfy {
            MapPinKind.accessibilityLabel(for: $0) == SiteCopy.pinAccessibilityLabel
        })

        // And a tap on one goes where a tap on that pin goes on screen 01. The composition root routes
        // this map's pins through `MapHomeView.route(for:)` rather than through a branch of its own,
        // because a second copy of that mapping is how a basin comes to open a tree's profile — which
        // is precisely what ERRATA E113 removed.
        for pin in vacant.group.pins {
            #expect(MapHomeView.route(for: pin) == .site(pin.id))
        }
        for pin in coverage.group.pins {
            #expect(MapHomeView.route(for: pin) == .treeProfile(pin.id))
        }
    }

    // MARK: - Against the shipped seed

    /// The bundled seed, or `CYPRESS_SEED_PATH`. Same resolution `AlmanacVacantSiteTests` uses.
    private static var seedURL: URL? {
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

    /// **Every row of the seed is `city_import` / `city_record`**, which is what lets a fixture and a
    /// preview build a pin without inventing those two fields, and what makes the literal
    /// `NULL AS species_uuid` in `AlmanacQueries.vacantSites` a measurement rather than a shortcut.
    ///
    /// If a seed rebuild ever admits a community row, the reads that feed this map select `source` and
    /// `verification_state` from the row and will keep telling the truth; it is the *fixtures* that
    /// would go stale, and this is where that shows up.
    @Test("the seed is entirely city inventory, and no basin carries a species")
    func theSeedIsCityInventory() async throws {
        let store = try await Self.store()

        let notCity = try await Self.scalar(
            """
            SELECT COUNT(*) AS n FROM \(Self.seed).trees
             WHERE source <> 'city_import' OR verification_state <> 'city_record'
            """,
            on: store
        )
        #expect(notCity == 0)

        let basinsWithSpecies = try await Self.scalar(
            """
            SELECT COUNT(*) AS n FROM \(Self.seed).trees
             WHERE status = 'vacant_site' AND species_current IS NOT NULL
            """,
            on: store
        )
        #expect(basinsWithSpecies == 0)
    }

    /// The vacant read, at the numbers the running corpus holds: a whole-neighbourhood count and a
    /// page of it, every one of them a basin in this neighbourhood with a coordinate a map can draw.
    ///
    /// E115 measured 1,474 and a full page of 20 against the DataSF export. **Under `--source city`
    /// Sunset/Parkside holds 7 basins**, because the city's own layer has no vacant-site category —
    /// so the page is the whole set and the two-block radius the row limit was chosen against does
    /// not hold. Both facts are pinned per source rather than relaxed to an inequality.
    @Test("the vacant read returns a page of placeable basins and the neighbourhood's whole count")
    func vacantReadReturnsPlaceablePins() async throws {
        let store = try await Self.store()
        let corpus = try await SeedCorpus.current(store)
        let schema = try #require(store.seed)
        let queries = AlmanacQueries(schema: schema)
        let sunset = try await Self.scalar(
            "SELECT id AS n FROM \(Self.seed).neighborhoods WHERE name = 'Sunset/Parkside'",
            on: store
        )
        let here = Coordinate(latitude: 37.7530, longitude: -122.4850)

        let result = try await store.queue.read { connection in
            try queries.vacantSites(
                neighborhoodID: sunset,
                near: here,
                limit: AlmanacLimits.vacantSiteRowLimit,
                connection: connection
            )
        }

        let expectedPage = min(corpus.sunsetVacantSites, AlmanacLimits.vacantSiteRowLimit)
        #expect(result.count == corpus.sunsetVacantSites)
        #expect(result.nearest.count == expectedPage)
        #expect(result.nearest.allSatisfy { $0.status == .vacantSite })
        #expect(Set(result.nearest.map(\.id)).count == expectedPage)

        // Nearest first, which is the fact `The 20 nearest are on this map.` rests on.
        let distances = result.nearest.map { here.distance(to: $0.coordinate) }
        #expect(distances == distances.sorted(), "the page is not ordered by distance")

        // And they are actually near — where there are enough of them to be. 400 m is about two
        // blocks and is what `AlmanacLimits.vacantSiteRowLimit` was chosen against, on a corpus with
        // 1,474 basins in this neighbourhood. With 7 the nearest twenty are simply all of them,
        // spread across the whole of Sunset/Parkside, and a tight radius is not a property the read
        // can have. The city-wide bound is what is left to assert.
        let radius = corpus.sunsetVacantSites >= AlmanacLimits.vacantSiteRowLimit ? 400.0 : 12_000.0
        #expect((distances.max() ?? .infinity) < radius)

        // The frame the destination opens on holds all twenty.
        let group = PinSet(
            subject: .vacantSites,
            pins: result.nearest,
            count: result.count,
            neighborhoodName: "Sunset/Parkside"
        )
        let frame = PinSetPresentation(set: group, locale: Self.locale).frame
        #expect(result.nearest.allSatisfy { frame.contains($0.coordinate) })
    }

    /// The coverage read now returns whole pins, and the coordinate it returns is one it has always
    /// selected — `LocalAPI` needed it to check §4's walking claim and dropped it one line later.
    @Test("the coverage read returns standing trees a map can place")
    func coverageReadReturnsPlaceablePins() async throws {
        let store = try await Self.store()
        let schema = try #require(store.seed)
        let queries = AlmanacQueries(schema: schema)
        let sunset = try await Self.scalar(
            "SELECT id AS n FROM \(Self.seed).neighborhoods WHERE name = 'Sunset/Parkside'",
            on: store
        )

        let young = try await store.queue.read { connection in
            try queries.youngTreesWithoutVisits(
                neighborhoodID: sunset,
                plantedOnOrAfter: "0000-01-01",
                limit: AlmanacLimits.coverageRowLimit + 1,
                connection: connection
            )
        }

        // No `PlantDate` in the source means no young trees anywhere, so screen 12's coverage row
        // is empty across the whole city under `--source city`. Asserted against the source's own
        // column list, so an emptied column is still a failure rather than an expected zero.
        let corpus = try await SeedCorpus.current(store)
        #expect(
            !young.isEmpty == corpus.publishes("PlantDate"),
            "the coverage read returned \(young.count) trees, and the source "
                + "\(corpus.publishes("PlantDate") ? "does" : "does not") publish PlantDate"
        )
        #expect(young.allSatisfy { $0.status == .alive || $0.status == .declining })
        // Inside San Francisco, so nothing arrived at 0, 0 — the failure a dropped column produces.
        #expect(young.allSatisfy { $0.coordinate.latitude > 37 && $0.coordinate.longitude < -122 })
        #expect(young.allSatisfy { MapPinKind.kind(for: $0) != .vacantSite })
    }
}
