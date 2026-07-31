import Foundation
import Testing
@testable import Cypress

/// **The map's level of detail, which for six rounds did not exist.**
///
/// A1 puts individual pins at zoom ≥ 16 and clusters at ≤ 15, and between zoom 16 and 21 there was
/// no rule at all: `MapModel` read five latitude bands of 260 pins each and drew every one of the
/// 1,300, so the annotation count tracked the viewport's *area*. The camera opens at 120 m; one
/// pinch out is four times the ground and two is sixteen, and the second pinch is where the map
/// stopped answering. Further out it went fast again, because clustering caps the badges — which is
/// why the report was "SUPER slow when you zoom out **a bit**", and why the cause was never the SQL,
/// whose cost runs the other way (104 ms for the whole city clustered, single-digit milliseconds for
/// one zoom-16 screenful of pins).
///
/// Measured on the iPhone 16 Pro simulator with `MapFrameProbe`, a `CADisplayLink` counting
/// main-thread frames, over the same pinch from the opening camera out to zoom 16:
///
/// | window | before | after |
/// |---|---|---|
/// | arriving at zoom 16 | 14.3 fps, worst frame 753 ms | see ERRATA E130 |
/// | the window after it | 0.5 fps, worst frame 2,061 ms | |
///
/// A frame counter cannot be a unit test, so these are the two halves of the rule that *can* be
/// held: the drawn count is bounded and does not grow with the viewport, and what it drops is the
/// density rather than the north of the screen.
@Suite("Map level of detail")
struct MapDetailTests {

    // MARK: - Fixtures

    /// iPhone 16 Pro, logical points. **The screen is what sets the grid** — the box is the same
    /// 402 × 874 pt at every zoom, so the cell count is too, and that is the property under test.
    private static let screen = (width: 402.0, height: 874.0)

    /// The densest zoom-16 screenful in the seed, found by counting all 195,309 inventoried trees
    /// into fetched-box-sized cells at every quarter-box offset. 8,150 trees in one fetched box, in
    /// the Mission.
    private static let densest = Coordinate(latitude: 37.778_756, longitude: -122.424_661)

    /// What MapKit reports for a screen of `screen` at this zoom, centred here — *before*
    /// `MapModel`'s own 8 % pad, which is the model's business and not the camera's.
    private static func bounds(around centre: Coordinate, zoom: Int) -> BoundingBox {
        let degreesPerPoint = 360.0 / (256.0 * pow(2.0, Double(zoom)))
        let longitudeSpan = degreesPerPoint * screen.width
        let latitudeSpan = degreesPerPoint * cos(centre.latitude * .pi / 180) * screen.height
        return BoundingBox(
            minLatitude: centre.latitude - latitudeSpan / 2,
            maxLatitude: centre.latitude + latitudeSpan / 2,
            minLongitude: centre.longitude - longitudeSpan / 2,
            maxLongitude: centre.longitude + longitudeSpan / 2
        )
    }

    private static func api() async throws -> LocalAPI {
        let seedURL = try #require(SeedContractTests.seedURL, "no seed database; set CYPRESS_SEED_PATH")
        let store = try await CypressStore.inMemory(seedURL: seedURL)
        return LocalAPI(store: store, deviceID: UUID())
    }

    /// The map as the user gets it: the model driven through the same camera callback
    /// `MapKitBasemap` calls, then asked what it would draw.
    @MainActor
    private static func drawn(at zoom: Int, around centre: Coordinate, api: LocalAPI) async -> (
        model: MapModel, markers: Int
    ) {
        let model = MapModel(api: api)
        model.cameraDidChange(bounds: bounds(around: centre, zoom: zoom), zoom: zoom)
        await model.fetch()
        return (model, model.pins.count + model.clusters.count)
    }

    /// Every tree the same viewport holds, with the level-of-detail rule switched off — the number
    /// the annotation count used to chase.
    private static func treesInView(at zoom: Int, around centre: Coordinate, api: LocalAPI) async throws -> Int {
        let viewport = MapViewport(
            bounds: bounds(around: centre, zoom: zoom).expanded(by: 0.08),
            zoom: zoom,
            pinLimit: 100_000
        )
        return try await api.mapContent(in: viewport).pinCount
    }

    /// How many 44 pt cells the fetched box can touch, computed here from the box and the zoom rather
    /// than asked of the code under test.
    ///
    /// **This is the bound that says the answer does not scale with the viewport.** A cell is
    /// `markerCellPoints` square *on screen*, and the screen is 402 × 874 pt at every zoom, so this
    /// number is the same at zoom 16 as at zoom 21 however much ground the camera covers. The grid is
    /// absolute rather than aligned to the box's corner — which is what keeps a pin from flickering
    /// under a pan — so a box 10.6 cells wide touches 11 columns or 12 depending on where it falls,
    /// and the count is taken off the cell indices themselves rather than from the span.
    private static func cellBound(_ viewport: MapViewport) -> Int {
        let centreLatitude = (viewport.bounds.minLatitude + viewport.bounds.maxLatitude) / 2
        let cell = TreeQueries.cellSize(
            zoom: viewport.zoom,
            centreLatitude: centreLatitude,
            points: MapModel.markerCellPoints
        )
        func cells(_ lower: Double, _ upper: Double, offset: Double, size: Double) -> Int {
            Int((upper + offset) / size) - Int((lower + offset) / size) + 1
        }
        return cells(viewport.bounds.minLatitude, viewport.bounds.maxLatitude, offset: 90, size: cell.latitude)
            * cells(viewport.bounds.minLongitude, viewport.bounds.maxLongitude, offset: 180, size: cell.longitude)
    }

    // MARK: - The bound

    /// The tuning, written down as a number rather than as the constant that sets it.
    ///
    /// Comparing the drawn count against `MapModel.pinLimit` would be a tautology — the same constant
    /// is the query's own `LIMIT`, so raising it would raise the bar and the test would go on
    /// passing. This is the ceiling the round actually chose. A change to the tuning has to come here
    /// and say so.
    private static let drawnMarkerCeiling = 400

    /// The budget, over every zoom A1 draws individual pins at. Before E130 this is 1,300 markers at
    /// zoom 16 and 17 and 543 at zoom 18.
    @MainActor
    @Test("no zoom draws more markers than the budget", arguments: [16, 17, 18, 19, 20, 21])
    func markerCountStaysInsideTheBudget(zoom: Int) async throws {
        #expect(MapModel.pinLimit <= Self.drawnMarkerCeiling, "the budget was raised past the tuning")
        let api = try await Self.api()
        let (_, markers) = await Self.drawn(at: zoom, around: Self.densest, api: api)
        #expect(
            markers <= Self.drawnMarkerCeiling,
            "zoom \(zoom) drew \(markers) markers against a ceiling of \(Self.drawnMarkerCeiling)"
        )
    }

    /// **The property, stated directly: pulling the camera back stops adding annotations.**
    ///
    /// Zoom 16 holds fifteen times the trees zoom 18 does over the same screen — 8,150 against 543 —
    /// and before E130 that was fifteen times the work, capped only by a `LIMIT` that had nothing to
    /// do with the screen. The two counts must now be within a small factor of each other, because
    /// both are bounded by the same 402 × 874 pt of glass.
    @MainActor
    @Test("sixteen times the ground is not sixteen times the annotations")
    func theAnswerDoesNotGrowWithTheViewport() async throws {
        let api = try await Self.api()
        let near = try await Self.treesInView(at: 18, around: Self.densest, api: api)
        let far = try await Self.treesInView(at: 16, around: Self.densest, api: api)
        try #require(far > near * 8, "the fixture no longer gets denser as it zooms out: \(near) → \(far)")

        let (_, drawnNear) = await Self.drawn(at: 18, around: Self.densest, api: api)
        let (_, drawnFar) = await Self.drawn(at: 16, around: Self.densest, api: api)
        #expect(
            drawnFar <= drawnNear * 3,
            "zoom 18 drew \(drawnNear) markers and zoom 16 drew \(drawnFar) for \(far) trees"
        )
    }

    /// **The defect's own screen, asserted whole.** 8,150 trees in one zoom-16 viewport: before E130
    /// the map drew 1,300 of them and — because `idx_trees_lat_lon` orders by latitude and a `LIMIT`
    /// keeps the *southernmost* rows — put each band's 260 into a strip along the bottom of that
    /// band, which is the horizontal striping the map showed. Bounded, and spread, and still
    /// recognisably a thinning rather than a sample of a corner.
    @MainActor
    @Test("the densest screenful is bounded, and it is the whole screenful")
    func theDensestScreenfulIsBoundedAndWhole() async throws {
        let api = try await Self.api()
        let trees = try await Self.treesInView(at: 16, around: Self.densest, api: api)
        let (model, markers) = await Self.drawn(at: 16, around: Self.densest, api: api)
        let viewport = try #require(model.viewport)

        // A floor on how much the budget has to cope with, so it moves with the corpus rather than
        // pinning a number the inventory owns. 5,000 under the DataSF export; 4,000 under the city's
        // own layer, which holds 62,000 fewer records over the same streets. The assertion that
        // matters is the `#require` below it — the budget must actually be exceeded, or nothing
        // after this line is testing anything.
        let seedURL = try #require(SeedContractTests.seedURL, "no seed database; set CYPRESS_SEED_PATH")
        let corpus = try await SeedCorpus.current(try await CypressStore.inMemory(seedURL: seedURL))
        #expect(
            trees > corpus.densestScreenfulFloor,
            "the fixture is no longer the densest screenful: \(trees) trees"
        )
        try #require(trees > MapModel.pinLimit, "the budget is not exceeded, so nothing here is tested")
        #expect(markers < trees / 10, "zoom 16 drew \(markers) of \(trees) trees; the grid is not thinning")
        // The structural half of the bound, and the half a `LIMIT` cannot satisfy: past the budget
        // the answer is one marker per 44 pt of *screen*, and the screen is the same size at every
        // zoom.
        #expect(
            markers <= Self.cellBound(viewport),
            "zoom 16 drew \(markers) markers into a grid of \(Self.cellBound(viewport)) cells"
        )

        // Ten horizontal bands across the fetched box. The densest screenful in the Mission is street
        // grid the whole way down, so every band holds trees and every band must hold a drawn pin.
        // This is the assertion the five-band `LIMIT` could not have passed.
        let bands = 10
        let step = (viewport.bounds.maxLatitude - viewport.bounds.minLatitude) / Double(bands)
        let occupied = Set(model.pins.map { pin in
            min(Int((pin.coordinate.latitude - viewport.bounds.minLatitude) / step), bands - 1)
        })
        #expect(
            occupied.count == bands,
            "the \(markers) drawn pins reached \(occupied.count) of \(bands) latitude bands; the map is striped"
        )
    }

    // MARK: - What it thins, and what it does not

    /// The grid is a ceiling, not a rule: a viewport whose trees fit inside the budget is drawn
    /// whole. At zoom 19 over the densest block that is all 109 of them, where an unconditional grid
    /// would have drawn 53.
    @MainActor
    @Test("a viewport inside the budget loses nothing", arguments: [19, 20, 21])
    func nothingIsThinnedUnderTheBudget(zoom: Int) async throws {
        let api = try await Self.api()
        let trees = try await Self.treesInView(at: zoom, around: Self.densest, api: api)
        try #require(trees <= MapModel.pinLimit, "zoom \(zoom) holds \(trees) trees, which is over the budget")
        try #require(trees > 0, "zoom \(zoom) holds no trees, so nothing here is tested")
        let (_, markers) = await Self.drawn(at: zoom, around: Self.densest, api: api)
        #expect(markers == trees, "zoom \(zoom) drew \(markers) of \(trees) trees that all fit")
    }

    // MARK: - A1's threshold, and which side of it chooses a level of detail

    /// Clusters at 15 and below, individual pins at 16 and above — and `markerCellPoints` set on
    /// exactly the pin side, because a cluster badge is already one marker per 64 pt cell.
    @MainActor
    @Test("the clustering threshold is 15, and only the pin side grids", arguments: [13, 14, 15, 16, 17, 18])
    func theThresholdDecidesTheLevelOfDetail(zoom: Int) async throws {
        let api = try await Self.api()
        let (model, _) = await Self.drawn(at: zoom, around: Self.densest, api: api)
        let viewport = try #require(model.viewport)
        let clustered = zoom <= MapViewport.highestClusteringZoom

        #expect(viewport.shouldCluster == clustered)
        #expect(
            (viewport.markerCellPoints == nil) == clustered,
            "zoom \(zoom) asked for markerCellPoints \(String(describing: viewport.markerCellPoints))"
        )
        if clustered {
            #expect(model.pins.isEmpty, "zoom \(zoom) is a clustering zoom and returned individual pins")
            #expect(!model.clusters.isEmpty, "zoom \(zoom) is a clustering zoom and returned no badge")
        } else {
            #expect(model.clusters.isEmpty, "zoom \(zoom) is a pin zoom and returned cluster badges")
            #expect(!model.pins.isEmpty, "zoom \(zoom) is a pin zoom over dense city and returned no pin")
        }
    }

    /// A clustered viewport was always bounded — one badge per 64 pt cell — and still is. This is the
    /// half of the map that was never slow, held so that a change to the grid cannot make it so.
    @MainActor
    @Test("a clustered viewport draws badges, not thousands of them", arguments: [11, 13, 15])
    func clusteredViewportsStayBounded(zoom: Int) async throws {
        let api = try await Self.api()
        let (model, markers) = await Self.drawn(at: zoom, around: Self.densest, api: api)
        #expect(markers <= Self.drawnMarkerCeiling, "zoom \(zoom) drew \(markers) cluster badges")
        // The badges still account for every tree in the box; thinning pins must never thin counts.
        #expect(model.content.pinCount > markers * 10, "the badges at zoom \(zoom) are not aggregating")
    }

    // MARK: - The community layer, through the grid

    /// A contributor's own tree survives the level-of-detail rule for the same reason it survives the
    /// budget (ERRATA E36): `LocalAPI` merges the community layer *after* the seed query, so the grid
    /// never gets the chance to drop it. Asserted here because the grid is a new way for it to go
    /// missing, and E36 is what happens when nobody checks.
    @MainActor
    @Test("a community tree is drawn even where the grid is dropping nine trees in ten")
    func communityTreeSurvivesTheGrid() async throws {
        let seedURL = try #require(SeedContractTests.seedURL, "no seed database; set CYPRESS_SEED_PATH")
        let store = try await CypressStore.inMemory(seedURL: seedURL)
        let api = LocalAPI(store: store, deviceID: UUID())

        let added = Tree(source: .community, coordinate: Self.densest)
        try await store.queue.write { connection in
            try CommunityTreeStore().insert(added, clientUUID: UUID(), connection: connection)
        }

        let (model, _) = await Self.drawn(at: 16, around: Self.densest, api: api)
        #expect(
            model.pins.contains { $0.id == added.id },
            "the contributor's own tree was thinned out of the viewport they added it in"
        )
    }

    // MARK: - The filter, which is now stored rather than recomputed per body pass

    /// `pins` stopped being a computed property (ERRATA E130) and the three things that can change
    /// its answer now write it. This is the one that is easy to forget: changing the chip with
    /// content already on screen.
    @MainActor
    @Test("changing the filter re-admits the pins without another read")
    func filterChangeRecomputesTheAdmittedPins() async throws {
        let api = try await Self.api()
        let (model, _) = await Self.drawn(at: 16, around: Self.densest, api: api)
        let all = model.pins.count
        #expect(all > 0)

        // The shipped seed carries no `declining` tree, so `Needs care` admits none of them — which
        // is the honest answer to the question the chip asks, and what makes it a clean assertion
        // that the filter ran at all.
        model.filter = .needsCare
        #expect(model.pins.allSatisfy { MapPinKind.needsCare(status: $0.status) })
        #expect(model.pins.count < all)

        model.filter = .all
        #expect(model.pins.count == all, "going back to All did not restore the pins")
    }

    // MARK: - The status-override cache, and the way it could go wrong

    /// `LocalAPI` now holds `tree_status_overrides` between the writes that can change it, because
    /// the map re-read that whole table on every camera change (ERRATA E130). A held answer is only
    /// as good as its invalidation, and this is the failure it would produce: a tree moderated to
    /// `removed` after the map has already drawn once, still drawing green.
    ///
    /// Driven through `debugMarkStatus` rather than through `confirmReview` because the moderation
    /// gate is `ModerationTests`' subject and not this one's; what is under test is that a write to
    /// the table reaches the next `mapContent`.
    @Test("a moderated tree changes its pin on the very next viewport read")
    func moderationInvalidatesTheHeldOverrides() async throws {
        let seedURL = try #require(SeedContractTests.seedURL, "no seed database; set CYPRESS_SEED_PATH")
        let store = try await CypressStore.inMemory(seedURL: seedURL)
        let api = LocalAPI(store: store, deviceID: UUID())

        // A block small enough that the un-thinned query runs, so the tree that gets moderated is
        // certain to still be one of the drawn pins afterwards.
        let block = BoundingBox(
            minLatitude: 37.7985, maxLatitude: 37.7995,
            minLongitude: -122.4445, maxLongitude: -122.4430
        )
        let viewport = MapViewport(bounds: block, zoom: 16, pinLimit: MapModel.pinLimit)

        guard case let .pins(before) = try await api.mapContent(in: viewport) else {
            Issue.record("a zoom-16 viewport did not return pins")
            return
        }
        let subject = try #require(before.first { $0.status == .alive })

        try await api.debugMarkStatus(treeID: subject.id, .removed)

        guard case let .pins(after) = try await api.mapContent(in: viewport) else {
            Issue.record("a zoom-16 viewport did not return pins")
            return
        }
        let redrawn = try #require(after.first { $0.id == subject.id }, "the moderated tree left the viewport")
        #expect(
            redrawn.status == .removed,
            "the map is still drawing the pre-moderation status; the held overrides were not invalidated"
        )
    }
}
