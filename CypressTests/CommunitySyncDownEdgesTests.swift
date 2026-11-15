//
//  CommunitySyncDownEdgesTests.swift
//  CypressTests
//
//  Round C2, the sync down, at its edges: two refresh passes that overlap, a narrowing over more
//  community trees than the pin budget, the tile and page limits at exactly their values, the order
//  the community layer cuts in, and the order a dated photograph keeps. The round's main tests are
//  `CommunitySyncDownTests`; the helpers used here are defined there.
//

import Foundation
import MapKit
import Testing
@testable import Cypress

/// A door a scripted fetch waits at until the test opens it.
actor FetchGate {
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var opened = false
    private(set) var entered = 0
    private(set) var finished = 0

    /// Waits for `open()`, and ignores cancellation, the way a request already on the network does.
    func wait() async {
        entered += 1
        if opened { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func open() {
        opened = true
        waiting.forEach { $0.resume() }
        waiting = []
    }

    func isOpen() -> Bool { opened }
    func noteFinished() { finished += 1 }
    func nextCall() -> Int { entered += 1; return entered }
}

/// Polls `condition` every 5 ms, at most `attempts` times. For waits that `TestWait.settle` cannot
/// do, because the task being waited for is no longer one the model holds.
func pollC2(_ attempts: Int = 400, until condition: () async -> Bool) async throws {
    for _ in 0..<attempts {
        if await condition() { return }
        try await Task.sleep(nanoseconds: 5_000_000)
    }
}

// MARK: - Two passes at once

@Suite("Community sync down · overlapping passes")
struct CommunityOverlappingPassTests {

    static let tile = CommunityRefresherTests.tile
    static let box = CommunityRefresherTests.box

    /// The review's steps exactly: pass 1 marks the tile and waits on the network; the reader pans,
    /// so pass 1 is cancelled and pass 2 starts over the same tile; pass 1's request then comes back
    /// and its page is written. Pass 2 must not report "nothing to do" before pass 1 has finished,
    /// and pass 1's outcome must still report the write, so the map can draw it.
    ///
    /// Red-proof: remove `await beginPass()` from `CommunityTileRefresher.refresh(covering:)` — red
    /// on "pass 2 returned before pass 1 wrote its page".
    @Test("a second pass waits for the pass in flight, and the cancelled pass still reports its write")
    func aSecondPassWaitsForTheFirst() async throws {
        let store = try await CypressStore.inMemory()
        let gate = FetchGate()
        let tree = CommunityRefresherTests.tree()
        let page = CommunityRefresherTests.page([tree], cursor: "c1")
        let refresher = CommunityTileRefresher(queue: store.queue) { _, _ in
            await gate.wait()
            return page
        }

        let first = Task { await refresher.refresh(covering: Self.box) }
        try await pollC2 { await gate.entered == 1 }
        #expect(await gate.entered == 1, "calibration: pass 1 never reached the fetch")
        first.cancel()
        let opener = Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            await gate.open()
        }
        let second = await refresher.refresh(covering: Self.box)
        let cachedWhenPassTwoEnded = try await CommunityRefresherTests.cached(store)
        await opener.value
        let firstOutcome = await first.value

        #expect(cachedWhenPassTwoEnded[tree.id] != nil, "pass 2 returned before pass 1 wrote its page")
        #expect(firstOutcome.stored == 1)
        #expect(firstOutcome.changedCache, "the cancelled pass wrote a page and did not report it")
        #expect(await gate.entered == 1, "pass 2 asked again for a tile pass 1 had fetched")
        #expect(!second.changedCache)
    }

    /// The other branch of the same steps: the request honors the cancellation, so pass 1 learned
    /// nothing. Pass 2, which starts while pass 1 is still in flight, must ask for the tile.
    ///
    /// Red-proof: remove `lastAttempt[tile] = nil` from the cancellation arm of
    /// `refresh(covering:)` — red on "pass 2 skipped a tile pass 1 never fetched".
    @Test("a tile whose request was cancelled is asked again by the next pass")
    func aCancelledTileIsAskedAgain() async throws {
        let store = try await CypressStore.inMemory()
        let gate = FetchGate()
        let tree = CommunityRefresherTests.tree()
        let page = CommunityRefresherTests.page([tree], cursor: "c1")
        let refresher = CommunityTileRefresher(queue: store.queue) { _, _ in
            if await gate.nextCall() == 1 {
                // Waits for an `open` that never comes; the sleep throws when the pass is cancelled.
                while true { try await Task.sleep(nanoseconds: 5_000_000) }
            }
            return page
        }

        let first = Task { await refresher.refresh(covering: Self.box) }
        try await pollC2 { await gate.entered == 1 }
        #expect(await gate.entered == 1, "calibration: pass 1 never reached the fetch")
        first.cancel()
        let second = await refresher.refresh(covering: Self.box)
        let firstOutcome = await first.value

        #expect(firstOutcome.ending == .cancelled)
        #expect(await gate.entered == 2, "pass 2 skipped a tile pass 1 never fetched")
        #expect(second.changedCache)
        #expect(try await CommunityRefresherTests.cached(store)[tree.id] != nil)
    }
}

// MARK: - The map, when the refresh that wrote was cancelled

@Suite("Community sync down · the map draws what a cancelled refresh wrote")
@MainActor
struct CommunityCancelledRefreshMapTests {

    /// The review's map steps: refresh 1 is in flight for the first settle; the reader pans a
    /// little, so the second settle reads the map (before refresh 1 has written anything) and
    /// cancels refresh 1. Refresh 1's request then returns and writes a tree that is on the new
    /// screen too. The map must read again and draw it.
    ///
    /// Red-proof: put `!Task.isCancelled` back into `startCommunityRefresh`'s guard — red on "the
    /// tree a cancelled refresh wrote never reached the map".
    @Test("a tree a cancelled refresh wrote is drawn when the camera still covers it")
    func aCancelledRefreshStillRedraws() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: UUID())
        let gate = FetchGate()
        let arrived = UUID()
        // Inside the first box and the panned one.
        let spot = Coordinate(latitude: 37.7605, longitude: -122.5042)
        let model = MapModel(api: api, refreshCommunity: { _ in
            if await gate.nextCall() == 1 {
                await gate.wait()
                try? await CommunityRefresherTests.cache(arrived, at: spot, tile: "t", store)
                await gate.noteFinished()
                return true
            }
            return false
        })

        let first = CommunityRefresherTests.box
        model.cameraDidChange(bounds: first, zoom: 18)
        try await pollC2 { await gate.entered >= 1 }
        // Half a box east: overlaps the first, and is not inside the first viewport's margin.
        let width = first.maxLongitude - first.minLongitude
        let panned = BoundingBox(
            minLatitude: first.minLatitude, maxLatitude: first.maxLatitude,
            minLongitude: first.minLongitude + width / 2, maxLongitude: first.maxLongitude + width / 2
        )
        model.cameraDidChange(bounds: panned, zoom: 18)
        // `entered` counts the `wait` inside call 1 as well, so call 2 has started at 3.
        try await pollC2 { await gate.entered >= 3 }
        #expect(await gate.entered >= 3, "calibration: the second settle never started a refresh")
        #expect(model.viewport?.bounds.contains(spot) == true,
                "calibration: the tree is not on the panned screen")
        guard case let .pins(before) = model.content else { Issue.record("clusters"); return }
        #expect(!before.items.contains { $0.id == arrived }, "calibration: the tree was drawn before it was written")

        await gate.open()
        try await pollC2 { await gate.finished == 1 }
        try await pollC2 {
            guard case let .pins(pins) = model.content else { return false }
            return pins.items.contains { $0.id == arrived }
        }
        guard case let .pins(after) = model.content else { Issue.record("clusters"); return }
        #expect(after.items.contains { $0.id == arrived }, "the tree a cancelled refresh wrote never reached the map")
    }
}

// MARK: - Offline

@Suite("Community sync down · offline")
struct CommunityOfflineTests {

    /// What an offline phone sends: one request per pass, each for the next tile not tried in the
    /// interval, then nothing until the interval passes.
    ///
    /// Red-proof: reset `lastAttempt[tile]` on every error in `refresh(covering:)` — red on "the
    /// second pass asked the failed tile again".
    @Test("offline, each pass asks one tile not tried in the interval, then none")
    func offlineAsksOneTilePerPass() async throws {
        let store = try await CypressStore.inMemory()
        let service = ScriptedTileService()
        let clock = TestClock()
        let refresher = CommunityRefresherTests.make(store, service, clock: clock)
        let both = BoundingBox(minLatitude: 37.7600, maxLatitude: 37.7610, minLongitude: -122.5050, maxLongitude: -122.4800)
        let tiles = try #require(CommunityTile.covering(both, limit: 16))
        #expect(tiles.count == 2, "calibration: the box is not two tiles")

        // Nothing scripted: every request fails as `notConnectedToInternet`.
        _ = await refresher.refresh(covering: both)
        _ = await refresher.refresh(covering: both)
        _ = await refresher.refresh(covering: both)
        let calls = await service.calls.map(\.tile)
        #expect(calls == tiles.map(\.path), "the second pass asked the failed tile again: \(calls)")

        clock.advance(121)
        _ = await refresher.refresh(covering: both)
        #expect(await service.calls.count == 3)
    }
}

// MARK: - Limits at exactly their values

@Suite("Community sync down · limits at the boundary")
struct CommunityLimitBoundaryTests {

    /// A box over the middles of tiles `x0...x1` by `y0...y1`, at zoom 14.
    static func box(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) -> BoundingBox {
        let n = Double(CommunityTile.side)
        func lon(_ x: Double) -> Double { x / n * 360 - 180 }
        func lat(_ y: Double) -> Double { atan(sinh(Double.pi * (1 - 2 * y / n))) * 180 / .pi }
        return BoundingBox(minLatitude: lat(Double(y1) + 0.5), maxLatitude: lat(Double(y0) + 0.5),
                           minLongitude: lon(Double(x0) + 0.5), maxLongitude: lon(Double(x1) + 0.5))
    }

    /// Exactly the limit is asked; one row more is not.
    ///
    /// Red-proof: `columns * rows < limit` in `CommunityTile.covering` — red on the 3 × 3 and 4 × 4.
    @Test("a box of exactly the limit is asked, and one past it is not")
    func exactlyTheLimit() {
        #expect(CommunityTile.covering(Self.box(2616, 6333, 2618, 6335), limit: 9)?.count == 9)
        #expect(CommunityTile.covering(Self.box(2616, 6333, 2618, 6336), limit: 9) == nil)
        #expect(CommunityTile.covering(Self.box(2616, 6333, 2619, 6336), limit: 16)?.count == 16)
        #expect(CommunityTile.covering(Self.box(2616, 6333, 2619, 6337), limit: 16) == nil)
    }

    /// `has_more` is followed up to the page limit and no further; the next pass continues from the
    /// last page applied.
    ///
    /// Red-proof: `while pages <= policy.maxPagesPerTile` — red on "followed has_more past the limit".
    @Test("has_more stops at the page limit, and the cursor is the last page applied")
    func hasMoreStopsAtThePageLimit() async throws {
        let store = try await CypressStore.inMemory()
        let service = ScriptedTileService()
        let clock = TestClock()
        let refresher = CommunityRefresherTests.make(store, service, clock: clock, policy: .init(maxPagesPerTile: 2))
        for index in 1...3 {
            await service.enqueue(CommunityRefresherTests.tile, .success(CommunityRefresherTests.page(
                [CommunityRefresherTests.tree()], cursor: "p\(index)", hasMore: true)))
        }

        _ = await refresher.refresh(covering: CommunityRefresherTests.box)

        let calls = await service.calls
        #expect(calls.count == 2, "followed has_more past the limit: \(calls)")
        #expect(try await CommunityRefresherTests.cursor(CommunityRefresherTests.tile, store) == "p2")

        clock.advance(121)
        _ = await refresher.refresh(covering: CommunityRefresherTests.box)
        let next = await service.calls
        #expect(next.count >= 3 && next[2].cursor == "p2", "the next pass did not continue from the stored cursor: \(next)")
    }
}

// MARK: - From which zoom the phone fetches

@Suite("Community sync down · the zoom the phone fetches from")
struct CommunityFetchZoomTests {

    /// The four agent screens, portrait, in points. The map is full-bleed, so its size is the
    /// screen's (`MapHomeView`).
    static let screens: [(width: Double, height: Double)] = [(390, 844), (402, 874), (420, 912), (440, 956)]
    static let latitudes: [Double] = [0.3, 37.77, 64.1]

    /// The box `MapModel.cameraDidChange` asks the refresher about, for a map `width` × `height`
    /// points at fractional zoom `zoom`, centered at (`latitude`, `longitude`): MapKit's region
    /// (`MapZoom`'s formula for the width, the Mercator rows for the height) as
    /// `BoundingBox(MKCoordinateRegion)` converts it, grown by the 8 % margin.
    static func viewport(width: Double, height: Double, zoom: Double, latitude: Double, longitude: Double) -> BoundingBox {
        let world = MapZoom.tileSize * pow(2, zoom)
        let longitudeDelta = 360 * width / world
        func mercatorY(_ lat: Double) -> Double {
            let s = sin(lat * .pi / 180)
            return 0.5 - log((1 + s) / (1 - s)) / (4 * .pi)
        }
        func latitudeAt(_ y: Double) -> Double { atan(sinh(.pi * (1 - 2 * y))) * 180 / .pi }
        let center = mercatorY(latitude)
        let latitudeDelta = latitudeAt(center - height / 2 / world) - latitudeAt(center + height / 2 / world)
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
        )
        return BoundingBox(region).expanded(by: 0.08)
    }

    /// The most tiles any placement of the map touches at `zoom`, over every screen and latitude:
    /// the center is swept across one tile in 12 steps each way, so every alignment is tried.
    static func tileCounts(zoom: Double) -> [Int] {
        let n = Double(CommunityTile.side)
        var counts: [Int] = []
        for screen in screens {
            for base in latitudes {
                for i in 0..<12 {
                    for j in 0..<12 {
                        let longitude = -122.45 + Double(i) / 12 * 360 / n
                        let latitude = base - Double(j) / 12 * 0.9 * 360 / n * cos(base * .pi / 180)
                        let box = viewport(width: screen.width, height: screen.height, zoom: zoom,
                                           latitude: latitude, longitude: longitude)
                        counts.append(CommunityTile.covering(box, limit: .max)?.count ?? 0)
                    }
                }
            }
        }
        return counts
    }

    /// The owner's ruling of 2026-11-15: fetch from the first zoom that draws cluster badges, at
    /// about 2 km across. Every zoom-15 map (the widest is zoom 15.0) and every map a quarter step
    /// wider fetches; no zoom-13 map does.
    ///
    /// Red-proof: `maxTiles: Int = 9` in `CommunityTileRefresher.Policy` — red on zoom 14.25,
    /// "touched 15 tiles".
    @Test("the first clustered zoom fetches on every agent screen, and zoom 13 does not")
    func theFirstClusteredZoomFetches() {
        let limit = CommunityTileRefresher.Policy().maxTiles
        #expect(MapViewport(bounds: CommunityRefresherTests.box, zoom: 15).shouldCluster,
                "calibration: zoom 15 does not cluster")
        #expect(!MapViewport(bounds: CommunityRefresherTests.box, zoom: 16).shouldCluster,
                "calibration: zoom 16 clusters")

        for zoom in [15.0, 14.25] {
            let counts = Self.tileCounts(zoom: zoom)
            #expect(counts.allSatisfy { $0 > 0 }, "calibration: a box covered no tile at zoom \(zoom)")
            #expect(counts.max()! <= limit, "zoom \(zoom) touched \(counts.max()!) tiles, over the limit of \(limit)")
        }
        let wide = Self.tileCounts(zoom: 13)
        #expect(wide.min()! > limit, "a zoom-13 map touched only \(wide.min()!) tiles and would fetch")
    }
}

// MARK: - Narrowing before the cut

@Suite("Community sync down · narrowing before the cut")
struct CommunityNarrowBeforeCutTests {

    static let common = UUID()
    static let rare = UUID()

    /// Seven cached trees in one box: six of a common species with low ids, one of a rare species
    /// with the highest id.
    static func seeded() async throws -> (CypressStore, LocalAPI) {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: UUID())
        var trees: [Tree] = (0..<6).map { index in
            Tree(id: UUID(uuidString: "00000000-0000-4000-8000-00000000000\(index)")!, source: .community,
                 coordinate: Coordinate(latitude: 37.7605 + Double(index) * 0.00001, longitude: -122.5046),
                 speciesCurrentID: common)
        }
        trees.append(Tree(id: UUID(uuidString: "FFFFFFFF-0000-4000-8000-000000000000")!, source: .community,
                          coordinate: Coordinate(latitude: 37.7606, longitude: -122.5045), speciesCurrentID: rare))
        try await store.queue.write { connection in
            try CommunityTreeCacheStore().apply(tile: CommunityRefresherTests.tile.path, trees: trees, withdrawnTreeIDs: [],
                                                nextCursor: "c", at: Date(), connection: connection)
        }
        return (store, api)
    }

    /// The narrowing runs before the budget cuts anything.
    ///
    /// Red-proof: pass `limit: viewport.pinLimit` to `layer.inBounds` in `LocalAPI.mapContent` —
    /// red on "the only tree of the narrowed species is in view but not drawn".
    @Test("a narrowed map draws a matching community tree even when the box holds more than the budget")
    func narrowingRunsBeforeTheCut() async throws {
        let (_, api) = try await Self.seeded()
        let viewport = MapViewport(bounds: CommunityRefresherTests.box, zoom: 17, pinLimit: 4, speciesIDs: [Self.rare])

        guard case let .pins(answer) = try await api.mapContent(in: viewport) else { Issue.record("clusters"); return }

        #expect(answer.items.map(\.speciesID) == [Self.rare],
                "the only tree of the narrowed species is in view but not drawn: \(answer.items.count) pins")
    }

    /// A cluster badge counts every community tree in its cell, not the first `pinLimit` of them.
    ///
    /// Red-proof: the same break — red on "the badges counted 4 of 7".
    @Test("a cluster badge counts every community tree, past the pin budget")
    func clustersCountEveryTree() async throws {
        let (_, api) = try await Self.seeded()
        let viewport = MapViewport(bounds: CommunityRefresherTests.box, zoom: 14, pinLimit: 4)

        guard case let .clusters(clusters) = try await api.mapContent(in: viewport) else { Issue.record("pins at zoom 14"); return }

        let counted = clusters.map(\.count).reduce(0, +)
        #expect(counted == 7, "the badges counted \(counted) of 7")
    }

    /// The community layer's own order, without the budget: the phone's own trees first, then by
    /// id. Cached rows are written highest id first and placed so that the index on `(lat, lon)`
    /// also meets the highest id first, so without the `ORDER BY` the cut keeps the wrong ones,
    /// whatever order the arms come in.
    ///
    /// Red-proof: delete `ORDER BY cached, id` alone from `CommunityLayer.inBoundsSQL` — red on
    /// "the cut kept the highest ids".
    @Test("the community layer cuts by id, whatever order the rows were stored in")
    func theLayerCutsById() async throws {
        let store = try await CypressStore.inMemory()
        let ids = (0..<6).map { UUID(uuidString: "00000000-0000-4000-8000-00000000000\($0)")! }
        let trees = ids.enumerated().reversed().map { index, id in
            // The highest id gets the lowest latitude, and is written first.
            Tree(id: id, source: .community,
                 coordinate: Coordinate(latitude: 37.7601 + Double(5 - index) * 0.0001 / 6, longitude: -122.5046))
        }
        #expect(trees.first?.id == ids.last, "calibration: the highest id is not written first")
        try await store.queue.write { connection in
            try CommunityTreeCacheStore().apply(tile: "t", trees: trees, withdrawnTreeIDs: [],
                                                nextCursor: "c", at: Date(), connection: connection)
        }

        let cut = try await store.queue.read { connection in
            try CommunityLayer().inBounds(CommunityRefresherTests.box, limit: 2, connection: connection)
        }
        let all = try await store.queue.read { connection in
            try CommunityLayer().inBounds(CommunityRefresherTests.box, limit: nil, connection: connection)
        }

        #expect(all.count == 6, "calibration: not every tree is in the box")
        #expect(cut.map(\.id) == Array(ids.prefix(2)), "the cut kept the highest ids: \(cut.map(\.id))")
    }
}

// MARK: - The order a dated photograph keeps

@Suite("Community sync down · a dated photograph keeps its place")
struct CommunityDatedPhotoOrderTests {

    /// A photograph the reader took at 10:00 on another phone, served with its exact time and its
    /// `captured_on`, sorts before the one they took at 11:00 on this phone, as the profile sorts
    /// (`photos.sorted { $0.capturedAt > $1.capturedAt }` in `RoutedAPI.refreshedTreeProfile`).
    ///
    /// Red-proof: return `capturedOn.midday(in: zone)` from `RoutedAPI.datedForDisplay` — red on
    /// "the 10:00 photograph sorted as the newer".
    @Test("a photograph dated for the screen keeps its real order within its day")
    func aDatedPhotoKeepsItsOrder() throws {
        let zone = try CommunityCalendarDayTests.zone("America/Los_Angeles")
        let day = try #require(CalendarDay(isoDate: "2026-09-24"))
        let tree = UUID()
        let otherPhone = Photo(treeID: tree, shotType: .fullTree, moderationState: .approved,
                               capturedAt: try CommunityCalendarDayTests.instant("2026-09-24T17:00:00Z"))
        let thisPhone = Photo(treeID: tree, shotType: .leaf, moderationState: .approved,
                              capturedAt: try CommunityCalendarDayTests.instant("2026-09-24T18:00:00Z"))

        let dated = RoutedAPI.datedForDisplay(otherPhone, capturedOn: day, in: zone)

        #expect(CommunityCalendarDayTests.printed(dated.capturedAt, in: zone) == "2026-09-24")
        #expect(dated.capturedAt == otherPhone.capturedAt, "a photograph already on its day was moved")
        let sorted = [dated, thisPhone].sorted { $0.capturedAt > $1.capturedAt }
        #expect(sorted.map(\.id) == [thisPhone.id, otherPhone.id], "the 10:00 photograph sorted as the newer")
    }

    /// When the reader's zone puts the instant on another day, the photograph moves to the nearest
    /// edge of its own day, and no further.
    @Test("a photograph off its day moves to the nearest edge of it")
    func offItsDayMovesToTheEdge() throws {
        let day = try #require(CalendarDay(isoDate: "2026-09-22"))
        let noonUTC = try CommunityCalendarDayTests.instant("2026-09-22T12:00:00Z")

        // 02:00 on the 23rd at UTC+14: the last second of the 22nd there.
        let east = try CommunityCalendarDayTests.zone("Pacific/Kiritimati")
        let late = day.instant(nearest: noonUTC, in: east)
        #expect(CommunityCalendarDayTests.printed(late, in: east) == "2026-09-22")
        #expect(late == (try CommunityCalendarDayTests.instant("2026-09-22T09:59:59Z")))

        // An instant on the 21st at UTC−7 moves to the first second of the 22nd there.
        let west = try CommunityCalendarDayTests.zone("America/Los_Angeles")
        let early = day.instant(nearest: try CommunityCalendarDayTests.instant("2026-09-22T03:00:00Z"), in: west)
        #expect(early == (try CommunityCalendarDayTests.instant("2026-09-22T07:00:00Z")))
    }
}
