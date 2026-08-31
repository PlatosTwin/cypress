//
//  AreaPickerTests.swift
//  CypressTests
//
//  The neighborhood/city picker: the two lists, the reads a chosen area produces, and the rule that
//  a fix too coarse to place the reader is not used to place the reader (tester report F17).
//
//  Against the real shipped seed wherever a number is involved, for `CityQueriesTests`' reason: a
//  fixture written for this test cannot catch a disagreement between the query and the fused bundle
//  it actually reads.
//
//  ── The one property this suite exists to protect ─────────────────────────────────────────────
//  **Picking an area changes what a number is computed over, and must not change what the number
//  means.** Every count on both segments comes out of `AlmanacQueries.speciesMix(scope:)` and
//  `CityQueries.speciesMix(idSpace:)`, unchanged, with one binding traded for another. So the tests
//  below do not assert a literal — literals here go stale silently (#122, #198) and a stale one
//  reads exactly like a fresh one. They assert **agreement**: the picker's row count equals the
//  card's sum, and a city read by choice equals the same city read by standing in it.
//

import Foundation
import Testing
@testable import Cypress

@Suite("Journal · pick an area")
struct AreaPickerTests {

    // MARK: - Harness (`CityQueriesTests`', verbatim)

    static var seedURL: URL? {
        if let path = ProcessInfo.processInfo.environment["CYPRESS_SEED_PATH"] {
            return URL(fileURLWithPath: path)
        }
        return SeedDatabase.urlInBundle(Bundle(for: BundleToken.self)) ?? SeedDatabase.urlInBundle()
    }

    private final class BundleToken {}

    private static func store() async throws -> CypressStore {
        let url = try #require(seedURL, "no seed database; set CYPRESS_SEED_PATH")
        return try await CypressStore.inMemory(seedURL: url)
    }

    private static func areaQueries(_ store: CypressStore) throws -> AreaQueries {
        let schema = try #require(store.seed, "the store opened without a seed attached")
        return AreaQueries(schema: schema)
    }

    static let outerSunset = Coordinate(latitude: 37.7533, longitude: -122.4934)
    static let downtownSanJose = Coordinate(latitude: 37.3352, longitude: -121.8895)
    static let sacramento = Coordinate(latitude: 38.5816, longitude: -121.4944)

    static let now = Date(timeIntervalSince1970: 1_784_505_600) // 2026-07-20
    private static let deviceID = UUID(uuidString: "02040000-0000-4000-8000-000000000205")!

    private static func api(_ store: CypressStore) -> LocalAPI {
        LocalAPI(store: store, deviceID: deviceID, now: { now })
    }

    // MARK: - 1 · The two lists

    @Test("the neighborhood list offers every polygon the record can answer for, largest first")
    func neighborhoodListIsOrderedAndComplete() async throws {
        let store = try await Self.store()
        let queries = try Self.areaQueries(store)
        let rows = try await store.queue.read { try queries.neighborhoods(connection: $0) }

        #expect(rows.count > 1, "no neighborhoods at all; the list read is answering the wrong question")
        #expect(Set(rows.map(\.id)).count == rows.count, "a neighborhood appeared twice")
        #expect(rows.allSatisfy { $0.treeCount > 0 }, "an area with nothing to count was offered")
        // Largest first, ties broken by name — the order `AreaQueries.neighborhoods` documents, and
        // the only thing `treeCount` is used for on screen.
        let ordered = zip(rows, rows.dropFirst()).allSatisfy { first, second in
            first.treeCount > second.treeCount
                || (first.treeCount == second.treeCount && first.name <= second.name)
        }
        #expect(ordered, "the list is not largest-first")
    }

    /// **The denominator gate.** The number the picker orders by has to be the number the card
    /// prints, or the reader is looking at two answers to one question with no way to tell which is
    /// real. Checked against the card's own query rather than against a literal.
    @Test("a picker row's count is exactly what the composition card sums to for that area")
    func pickerCountAgreesWithTheCompositionCard() async throws {
        let store = try await Self.store()
        let schema = try #require(store.seed)
        let queries = AreaQueries(schema: schema)
        let almanac = AlmanacQueries(schema: schema)

        let rows = try await store.queue.read { try queries.neighborhoods(connection: $0) }
        let largest = try #require(rows.first)
        let mix = try await store.queue.read {
            try almanac.speciesMix(
                scope: .neighborhood(id: largest.id, name: largest.name),
                connection: $0
            )
        }
        #expect(mix.reduce(0) { $0 + $1.treeCount } == largest.treeCount)
    }

    @Test("the city list names cities from the record and its counts agree with the city card")
    func cityListNamesAndCounts() async throws {
        let store = try await Self.store()
        let schema = try #require(store.seed)
        let queries = AreaQueries(schema: schema)
        let city = CityQueries(schema: schema)

        let rows = try await store.queue.read { try queries.cities(connection: $0) }
        #expect(rows.count > 1, "fewer than two cities; the bundled seed is fused across two")
        // A name off `dim_city`, never composed from the id space — the id and the name differ, and
        // that difference is the whole point of the join.
        #expect(rows.allSatisfy { !$0.name.isEmpty && $0.name != $0.id })

        for row in rows {
            let mix = try await store.queue.read { try city.speciesMix(idSpace: row.id, connection: $0) }
            #expect(mix.reduce(0) { $0 + $1.treeCount } == row.treeCount, "\(row.id)'s count disagrees")
        }
    }

    @Test("one neighborhood resolves to its own name and a center inside its own bounds")
    func neighborhoodResolvesNameAndCenter() async throws {
        let store = try await Self.store()
        let queries = try Self.areaQueries(store)
        let rows = try await store.queue.read { try queries.neighborhoods(connection: $0) }
        let chosen = try #require(rows.first)

        let found = try await store.queue.read { try queries.neighborhood(id: chosen.id, connection: $0) }
        let resolved = try #require(found)
        #expect(resolved.name == chosen.name)

        // The center has to be inside the polygon's own stored box, which is the box the seed wrote
        // at ingest — read here rather than recomputed, so this is a check and not a restatement.
        let bounds: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) =
            try await store.queue.read { connection in
                let statement = try connection.prepare("""
                    SELECT min_lat, max_lat, min_lon, max_lon
                      FROM \(SeedDatabase.schemaName).neighborhoods WHERE id = \(chosen.id)
                    """)
                defer { statement.finalize() }
                let row = try #require(try statement.fetchOne { row in
                    (
                        try row.double("min_lat"), try row.double("max_lat"),
                        try row.double("min_lon"), try row.double("max_lon")
                    )
                })
                return (row.0, row.1, row.2, row.3)
            }
        #expect(resolved.center.latitude >= bounds.minLat && resolved.center.latitude <= bounds.maxLat)
        #expect(resolved.center.longitude >= bounds.minLon && resolved.center.longitude <= bounds.maxLon)
    }

    @Test("an id no live inventory carries resolves to nothing, never to a neighborhood")
    func unknownNeighborhoodResolvesNothing() async throws {
        let store = try await Self.store()
        let queries = try Self.areaQueries(store)
        let found = try await store.queue.read { try queries.neighborhood(id: 987_654, connection: $0) }
        #expect(found == nil)
    }

    // MARK: - 2 · What a chosen area reads

    /// The owner's ask, at its hardest: a reader nowhere near any inventory, reading a neighborhood
    /// anyway. Before this round the screen could only say the record does not reach here.
    @Test("a reader outside every inventory can still read a chosen neighborhood")
    func sacramentoCanReadAChosenNeighborhood() async throws {
        let store = try await Self.store()
        let queries = try Self.areaQueries(store)
        let rows = try await store.queue.read { try queries.neighborhoods(connection: $0) }
        let chosen = try #require(rows.first)

        let here = try await Self.api(store).almanac(near: Self.sacramento, in: .here)
        #expect(here.neighborhood == nil, "Sacramento resolved an area; the radius bound broke")

        let picked = try await Self.api(store).almanac(
            near: Self.sacramento,
            in: .neighborhood(id: chosen.id)
        )
        let area = try #require(picked.neighborhood, "a chosen neighborhood produced no almanac")
        #expect(area.area == .named(chosen.name))
        #expect(area.resolution == .picked)
        #expect(area.composition?.treeCount == chosen.treeCount)
    }

    /// §4 is the app's one directed ask and its body sentence measures the reader's own walk. Both
    /// are about the reader, so neither survives a neighborhood the reader is not in.
    @Test("a chosen area withholds the coverage ask, and the reader's own area does not")
    func chosenAreaWithholdsTheCoverageAsk() async throws {
        let store = try await Self.store()
        let queries = try Self.areaQueries(store)
        let rows = try await store.queue.read { try queries.neighborhoods(connection: $0) }
        let chosen = try #require(rows.first)

        let picked = try await Self.api(store).almanac(
            near: Self.outerSunset,
            in: .neighborhood(id: chosen.id)
        )
        #expect(picked.neighborhood?.coverage == nil, "the ask was pointed at a place nobody is in")

        // The control: the same read for the reader's own area does produce the block, so the
        // expectation above is about the choice rather than about the seed having nothing to say.
        let here = try await Self.api(store).almanac(near: Self.outerSunset, in: .here)
        #expect(here.neighborhood?.coverage != nil, "the coverage block is absent even for `.here`")
    }

    @Test("a chosen neighborhood overrides the fix, and is a different area from the local one")
    func chosenAreaOverridesTheFix() async throws {
        let store = try await Self.store()
        let queries = try Self.areaQueries(store)
        let rows = try await store.queue.read { try queries.neighborhoods(connection: $0) }
        let here = try await Self.api(store).almanac(near: Self.outerSunset, in: .here)
        let localName = try #require(here.neighborhood?.area)

        // Any neighborhood that is not the one the fix resolves — so the assertion below cannot pass
        // by the two being the same place.
        let elsewhere = try #require(rows.first { .named($0.name) != localName })
        let picked = try await Self.api(store).almanac(
            near: Self.outerSunset,
            in: .neighborhood(id: elsewhere.id)
        )
        #expect(picked.neighborhood?.area == .named(elsewhere.name))
        #expect(picked.neighborhood?.composition?.treeCount == elsewhere.treeCount)
    }

    @Test("a chosen id the record no longer carries falls back to the reader's own area")
    func removedPackFallsBackToHere() async throws {
        let store = try await Self.store()
        let here = try await Self.api(store).almanac(near: Self.outerSunset, in: .here)
        let stale = try await Self.api(store).almanac(
            near: Self.outerSunset,
            in: .neighborhood(id: 987_654)
        )
        #expect(stale.neighborhood?.area == here.neighborhood?.area)
        #expect(stale.neighborhood?.resolution == .fromFix)
    }

    // MARK: - 3 · The city segment, and the denominator that must not move

    /// **The denominators statement, as a test.** A city read by choosing it and the same city read
    /// by standing in it must produce the same citywide numbers — the predicate is `id_space` in
    /// both cases and nothing else changed.
    @Test("a city read by choice and the same city read by standing in it agree exactly")
    func chosenCityMatchesTheLocalRead() async throws {
        let store = try await Self.store()
        let standing = try await Self.api(store).city(near: Self.downtownSanJose, in: .here)
        let chosen = try await Self.api(store).city(
            near: Self.outerSunset,
            in: .city(idSpace: "us-ca-sj")
        )

        let a = try #require(standing.snapshot?.cityComposition)
        let b = try #require(chosen.snapshot?.cityComposition)
        #expect(a.treeCount == b.treeCount)
        #expect(a.distinctSpeciesCount == b.distinctSpeciesCount)
        #expect(a.leading == b.leading)
        // And the reads really were made from different places, or the equality above proves nothing.
        #expect(standing.snapshot?.resolution == .fromFix)
        #expect(chosen.snapshot?.resolution == .picked)
    }

    @Test("a chosen city withholds card 1, whose sentence compares the reader's own streets")
    func chosenCityWithholdsTheContrast() async throws {
        let store = try await Self.store()
        let chosen = try await Self.api(store).city(
            near: Self.outerSunset,
            in: .city(idSpace: "us-ca-sj")
        )
        #expect(chosen.snapshot?.localComposition == nil)
        #expect(CityPresentation(city: chosen).contrast == nil)

        // The control: standing in the city, the same card does draw.
        let standing = try await Self.api(store).city(near: Self.outerSunset, in: .here)
        #expect(CityPresentation(city: standing).contrast != nil, "card 1 is absent even for `.here`")
    }

    @Test("a chosen city needs no fix at all")
    func chosenCityNeedsNoFix() async throws {
        let store = try await Self.store()
        let chosen = try await Self.api(store).city(near: nil, in: .city(idSpace: "sf"))
        #expect(chosen.snapshot?.cityComposition != nil)
        #expect(chosen.snapshot?.resolution == .picked)
    }

    @Test("the city segment names the city from the record")
    func cityIsNamedFromTheRecord() async throws {
        let store = try await Self.store()
        let queries = try Self.areaQueries(store)
        let rows = try await store.queue.read { try queries.cities(connection: $0) }
        let sf = try #require(rows.first { $0.id == "sf" })

        let read = try await Self.api(store).city(near: Self.outerSunset, in: .here)
        #expect(read.snapshot?.cityName == sf.name)
        #expect(CityPresentation(city: read).cityName == sf.name)
    }

    // MARK: - 4 · The fix that cannot name a place (F17's mechanism)

    @Test("a fix is allowed to name an area exactly while its error circle fits inside the search")
    func accuracyBoundary() {
        let radius = AlmanacLimits.neighborhoodResolutionRadiusM
        #expect(AlmanacLimits.fixCanResolveAnArea(accuracyM: radius, withinM: radius))
        #expect(AlmanacLimits.fixCanResolveAnArea(accuracyM: radius - 1, withinM: radius))
        #expect(!AlmanacLimits.fixCanResolveAnArea(accuracyM: radius + 1, withinM: radius))
        // An approximate-location fix, which is where F17 comes from.
        #expect(!AlmanacLimits.fixCanResolveAnArea(accuracyM: 3_000, withinM: radius))
        // Unknown accuracy is permitted, which is what leaves previews and tests unchanged.
        #expect(AlmanacLimits.fixCanResolveAnArea(accuracyM: nil, withinM: radius))
    }

    /// PR #132 review, F3. The two segments search different distances, so a fix between them is
    /// good enough for one and not the other — and the City segment is the one that can still
    /// answer.
    @MainActor
    @Test("each segment's coarse-fix gate is keyed on the radius its own resolution searches")
    func eachSegmentUsesItsOwnRadius() async throws {
        let between = (AlmanacLimits.neighborhoodResolutionRadiusM + AlmanacLimits.fallbackRadiusM) / 2
        #expect(
            AlmanacLimits.neighborhoodResolutionRadiusM < between
                && between < AlmanacLimits.fallbackRadiusM,
            "the two bounds stopped straddling this accuracy, so the test below proves nothing"
        )

        let store = try await Self.store()
        let city = CityModel(api: Self.api(store), coordinate: Self.outerSunset, accuracyM: between)
        await city.load()
        #expect(!city.needsAreaChoice, "the City segment blanked for a fix its own 1,200 m search covers")
        #expect(city.presentation?.hasCity == true, "and it really can answer for that coordinate")

        let almanac = AlmanacModel(api: Self.api(store), coordinate: Self.outerSunset, accuracyM: between)
        await almanac.load()
        #expect(almanac.needsAreaChoice, "the almanac accepted a fix wider than its own 400 m search")
    }

    /// The recorder: `almanac(near:in:)` is asked **what coordinate it was handed**, because the
    /// whole of the fix is that a coarse fix must not reach the read at all. A double that answered
    /// an almanac and was checked for its contents would pass whether or not the coordinate was
    /// filtered — the filtering is invisible downstream of `.empty`.
    ///
    /// The stub list is `AlmanacLateFixTests.FixSensitive`'s, copied rather than shared for the
    /// reason that file's own double is private: a conformance stub list is what makes a *new*
    /// protocol requirement visible as a compile error in every suite that has one, and one shared
    /// base class would answer for all of them at once.
    ///
    /// `@unchecked Sendable` records rather than assumes single-threading: it is touched only from
    /// `AlmanacModel`, which is `@MainActor`.
    private final class CoordinateRecorder: CypressAPI, @unchecked Sendable {
        private(set) var received: [Coordinate?] = []

        func almanac(near coordinate: Coordinate?, in area: AreaSelection) async throws -> Almanac {
            received.append(coordinate)
            return .empty
        }

        func mapContent(in viewport: MapViewport) async throws -> MapContent { .pins([]) }
        func treesNear(_ c: Coordinate, radiusM: Double, limit: Int) async throws -> [NearbyTree] { [] }
        func treeProfile(id: UUID) async throws -> TreeProfile { throw APIError.notFound }
        func addTree(_ draft: TreeDraft) async throws -> Tree { throw APIError.forbidden }
        func species(id: UUID) async throws -> Species { throw APIError.notFound }
        func searchSpecies(query: String, limit: Int) async throws -> [Species] { [] }
        func sync(_ items: [OutboxItem]) async throws -> [SyncResult] { [] }
        func beginPhotoUpload(_ r: PhotoUploadRequest) async throws -> PhotoUploadTicket {
            throw APIError.forbidden
        }
        func uploadPhoto(at localPath: String, ticket: PhotoUploadTicket) async throws {}
        func grove() async throws -> [GroveEntry] { [] }
        func journal(cursor: String?, limit: Int) async throws -> Page<JournalEntry> { Page(items: []) }
        func claimDevice(deviceUUID: UUID, userID: UUID) async throws {}
        func deleteAccount(_ choice: AccountDeletionChoice) async throws -> AccountDeletion.Outcome {
            throw APIError.unauthorized
        }
        func logHazardRedirect(_ event: HazardRedirectEvent) async throws {}
        func exportLatest(_ format: ExportFormat) async throws -> Data { Data() }
    }

    @MainActor
    @Test("a fix too coarse to place the reader never reaches the read")
    func coarseFixIsNotUsed() async throws {
        let recorder = CoordinateRecorder()
        let model = AlmanacModel(api: recorder, coordinate: Self.outerSunset, accuracyM: 3_000)
        await model.load()

        #expect(recorder.received == [nil], "the coarse fix was handed to the read anyway")
        #expect(model.needsAreaChoice, "the screen would say nothing about why it is blank")
        #expect(!model.needsLocation, "it would ask the reader to turn on location that is already on")
    }

    @MainActor
    @Test("a precise fix reaches the read exactly as it always has")
    func preciseFixIsUsed() async throws {
        let recorder = CoordinateRecorder()
        let model = AlmanacModel(api: recorder, coordinate: Self.outerSunset, accuracyM: 8)
        await model.load()

        #expect(recorder.received == [Self.outerSunset])
        #expect(!model.needsAreaChoice)
    }

    @MainActor
    @Test("the accuracy boundary is a reload boundary, and walking is still not")
    func accuracyIsAReloadBoundary() {
        let a = Coordinate(latitude: 37.75, longitude: -122.49)
        let b = Coordinate(latitude: 37.7501, longitude: -122.49)
        #expect(!AlmanacModel.isFixAvailabilityTransition(
            from: .located(a, accuracyM: 8), to: .located(b, accuracyM: 9)
        ), "walking five meters would reload the whole almanac")
        #expect(AlmanacModel.isFixAvailabilityTransition(
            from: .located(a, accuracyM: 3_000), to: .located(a, accuracyM: 8)
        ), "turning Precise Location on would leave the reader stuck on `pick an area`")
        #expect(AlmanacModel.isFixAvailabilityTransition(
            from: .notAsked, to: .located(a, accuracyM: 8)
        ), "the fix boundary this predicate was written for stopped working")
    }

    // MARK: - 5 · The picker's options round-trip

    @Test("`Where I am` is always offered, first, and every option maps back to its own selection")
    func optionsRoundTrip() {
        let choices = [
            NeighborhoodChoice(id: 40, name: "West of Twin Peaks", treeCount: 10_420),
            NeighborhoodChoice(id: 3, name: "Castro/Upper Market", treeCount: 1)
        ]
        let options = AreaPickerSheet.options(choices)
        #expect(options.first?.id == AreaPickerCopy.hereID)
        #expect(options.count == choices.count + 1)
        #expect(AreaPickerSheet.areaSelection(for: options[0]) == .here)
        #expect(AreaPickerSheet.areaSelection(for: options[1]) == .neighborhood(id: 40))
        #expect(AreaPickerSheet.optionID(.neighborhood(id: 3)) == options[2].id)
        #expect(AreaPickerSheet.optionID(AreaSelection.here) == options[0].id)

        let cities = [CityChoice(id: "us-ca-sj", name: "San Jose", treeCount: 40_199)]
        let cityOptions = AreaPickerSheet.options(cities)
        #expect(cityOptions.first?.id == AreaPickerCopy.hereID)
        #expect(AreaPickerSheet.citySelection(for: cityOptions[0]) == CitySelection.here)
        #expect(AreaPickerSheet.citySelection(for: cityOptions[1]) == .city(idSpace: "us-ca-sj"))
        #expect(AreaPickerSheet.optionID(.city(idSpace: "us-ca-sj")) == cityOptions[1].id)
    }

    /// PR #132 review, F4. The union deliberately does not merge neighborhoods across arms, so two
    /// live inventories can each contribute a `Downtown`; unqualified they are two identical chips.
    @Test("a neighborhood name two cities share is qualified, and one only one city has is not")
    func collidingNamesAreQualified() {
        let choices = [
            NeighborhoodChoice(id: 1, name: "Downtown", treeCount: 900, cityName: "San Francisco"),
            NeighborhoodChoice(id: 2, name: "Downtown", treeCount: 800, cityName: "San Jose"),
            NeighborhoodChoice(id: 3, name: "Mission", treeCount: 700, cityName: "San Francisco")
        ]
        let labels = AreaPickerSheet.options(choices).map(\.label)
        #expect(Set(labels).count == labels.count, "two chips share a label: \(labels)")
        #expect(labels.contains(AreaPickerCopy.qualified("Downtown", city: "San Francisco")))
        #expect(labels.contains(AreaPickerCopy.qualified("Downtown", city: "San Jose")))
        // The name only one city carries is left alone — qualifying all 41 of San Francisco's would
        // print a city nobody is choosing between.
        #expect(labels.contains("Mission"))

        // A record with no city name on file cannot be qualified, and is left as it is rather than
        // given an empty suffix.
        let nameless = [
            NeighborhoodChoice(id: 1, name: "Downtown", treeCount: 900),
            NeighborhoodChoice(id: 2, name: "Downtown", treeCount: 800)
        ]
        #expect(AreaPickerSheet.options(nameless).map(\.label).allSatisfy { !$0.contains("·") })
    }

    // MARK: - 6 · The sentence that answers the report

    /// **One fixture per mechanism**, which is the whole repair. The version this replaces built both
    /// of its fixtures from `.named("Mission")`, so R29's radius fallback — the state every San Jose
    /// reader is permanently in — was never handed to `AlmanacPresentation` at all, and a sentence
    /// claiming a nearest tree chose a circle drawn around the reader passed a green suite
    /// (PR #132 review, F1).
    @Test("each of the three ways an area is reached states its own provenance")
    func provenanceIsStated() {
        let polygon = AlmanacPresentation(
            almanac: Almanac(neighborhood: AlmanacNeighborhood(area: .named("Mission"))),
            now: Self.now
        )
        let fallback = AlmanacPresentation(
            almanac: Almanac(
                neighborhood: AlmanacNeighborhood(area: .radius(meters: AlmanacLimits.fallbackRadiusM))
            ),
            now: Self.now
        )
        let picked = AlmanacPresentation(
            almanac: Almanac(neighborhood: AlmanacNeighborhood(area: .named("Mission"), resolution: .picked)),
            now: Self.now
        )

        #expect(polygon.provenanceNote == AreaPickerCopy.resolvedFromFix)
        #expect(fallback.provenanceNote == AreaPickerCopy.resolvedFromFixRadius)
        #expect(picked.provenanceNote == AreaPickerCopy.resolvedByChoice)

        // All three different — one sentence reused across two mechanisms is exactly the defect.
        let notes = [polygon.provenanceNote, fallback.provenanceNote, picked.provenanceNote]
        #expect(Set(notes.compactMap { $0 }).count == 3)

        // And the fallback's own sentence does not contradict the line drawn directly under it.
        #expect(fallback.areaNote != nil, "the fallback lost the sentence this one has to agree with")
        #expect(fallback.provenanceNote != AreaPickerCopy.resolvedFromFix)

        #expect(!polygon.isPickedArea)
        #expect(picked.isPickedArea)

        // No area, no provenance to state.
        #expect(AlmanacPresentation(almanac: .empty, now: Self.now).provenanceNote == nil)
    }

    /// **The two VoiceOver hints the header pill wears**, since the owner's 2026-08-31 ruling made
    /// the pill itself the picker and retired the boxed `Change` button.
    ///
    /// XCUITest cannot read an accessibility *hint* — `XCUIElement` exposes the label, the traits
    /// and the value, and nothing else — so `AreaPickerUITests` can witness that the pill is a
    /// button carrying the place name, and cannot witness what it says the press will do. This is
    /// the part that is checkable here, and the failure it is aimed at is the plausible one: two
    /// hints written together, one pasted from the other, both naming neighborhoods. That reads
    /// correctly on the segment it was written for and wrongly on the other, where nothing on
    /// screen contradicts it.
    @Test("each segment's pill hint names its own list")
    func theHeaderPillHintsNameTheirOwnLists() {
        let area = AreaPickerCopy.changeAreaHint
        let city = AreaPickerCopy.changeCityHint

        #expect(area != city, "both segments' pills promise the same list")
        // Each names the noun its own sheet is full of, and not the other's.
        #expect(area.contains("neighborhood"))
        #expect(!area.contains("cities"))
        #expect(city.contains("cities"))
        #expect(!city.contains("neighborhood"))
    }

    /// The seed fact that makes F1 a permanent state for a whole city rather than an edge case.
    @Test("every San Jose row carries no neighborhood, so its readers are always in the fallback")
    func sanJoseIsAlwaysTheFallback() async throws {
        let store = try await Self.store()
        let counted: (total: Int, null: Int) = try await store.queue.read { connection in
            let statement = try connection.prepare(
                "SELECT COUNT(*) AS n, SUM(neighborhood_id IS NULL) AS m "
                    + "FROM \(SeedDatabase.schemaName).trees WHERE id_space = 'us-ca-sj'"
            )
            defer { statement.finalize() }
            let row = try #require(try statement.fetchOne { (try $0.int("n"), try $0.int("m")) })
            return (row.0, row.1)
        }
        #expect(counted.total > 0, "no San Jose rows at all; this test is measuring nothing")
        #expect(counted.null == counted.total)

        // So the read really does produce the radius area for that city, and the sentence over it is
        // the fallback's rather than the nearest tree's.
        let almanac = try await Self.api(store).almanac(near: Self.downtownSanJose, in: .here)
        let area = try #require(almanac.neighborhood)
        #expect(area.area == .radius(meters: AlmanacLimits.fallbackRadiusM))
        #expect(
            AlmanacPresentation(almanac: almanac, now: Self.now).provenanceNote
                == AreaPickerCopy.resolvedFromFixRadius
        )
    }
}
