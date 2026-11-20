//
//  CommunitySyncDownTests.swift
//  CypressTests
//
//  Round C2, the sync down: other people's community trees into the phone's cache, the profile
//  merge's new halves, the community share of the map's pin budget, and the calendar-day rules.
//  The wire itself is pinned by `GoldenWireCommunityReadsTests` against `server/testdata/`.
//

import Foundation
import Testing
@testable import Cypress

// MARK: - Calendar days

@Suite("Community sync down · calendar days")
struct CommunityCalendarDayTests {

    static func zone(_ identifier: String) throws -> TimeZone {
        try #require(TimeZone(identifier: identifier), "no zone \(identifier) on this runtime")
    }

    /// The day a formatter in `zone` prints for `instant`, as `YYYY-MM-DD`.
    static func printed(_ instant: Date, in zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: instant)
    }

    static func instant(_ iso: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: iso))
    }

    @Test("YYYY-MM-DD parses, and nothing else does")
    func isoDateParses() {
        #expect(CalendarDay(isoDate: "2026-09-22")?.isoDate == "2026-09-22")
        #expect(CalendarDay(isoDate: "2024-02-29") != nil)
        for bad in ["2026-02-30", "2026-13-01", "2026-9-22", "2026-09-22T00:00:00Z", "", "20260922", "２０２６-09-22"] {
            #expect(CalendarDay(isoDate: bad) == nil, "\(bad) parsed")
        }
    }

    /// A community-tree date is midnight UTC on the wire. Read as the UTC day it is the day it
    /// names in every zone, west of UTC and east of it. The control shows the naive reading: the
    /// same instant printed in the reader's zone is the day before at UTC−7.
    ///
    /// Red-proof: make `CalendarDay(utcDayOf:)` use `Calendar.current` — red when the test zone is
    /// west of UTC (the control below shows the shift the test is about).
    @Test("a community-tree date is the day it names in a zone west and a zone east of UTC")
    func midnightUTCIsTheDayItNames() throws {
        let wire = try Self.instant("2026-03-20T00:00:00Z")
        let day = CalendarDay(utcDayOf: wire)
        #expect(day.isoDate == "2026-03-20")

        let west = try Self.zone("America/Los_Angeles")
        let east = try Self.zone("Asia/Tokyo")
        // The control: the shift a naive conversion makes, so this test is about a real case.
        #expect(Self.printed(wire, in: west) == "2026-03-19", "calibration: the instant does not shift at UTC−7")
        #expect(Self.printed(wire, in: east) == "2026-03-20")

        // The day, shown in either zone, is the 20th.
        #expect(Self.printed(day.midday(in: west), in: west) == "2026-03-20")
        #expect(Self.printed(day.midday(in: east), in: east) == "2026-03-20")
    }

    /// `midday(in:)` is printed as its own day across the whole range of civil zones, the far
    /// east included, and across a daylight-saving change.
    @Test("a calendar day prints as itself in every zone from UTC−11 to UTC+14")
    func middayPrintsAsItself() throws {
        let days = ["2026-09-22", "2026-03-08", "2026-11-01", "2026-12-31", "2026-01-01"]
        let zones = ["Pacific/Pago_Pago", "America/Los_Angeles", "America/New_York", "UTC",
                     "Europe/Berlin", "Asia/Kolkata", "Asia/Tokyo", "Pacific/Auckland", "Pacific/Kiritimati"]
        for iso in days {
            let day = try #require(CalendarDay(isoDate: iso))
            for identifier in zones {
                let zone = try Self.zone(identifier)
                #expect(Self.printed(day.midday(in: zone), in: zone) == iso, "\(iso) printed wrong at \(identifier)")
            }
        }
    }

    /// Decision 14a's rendering rule. With `captured_on`, the photograph shows that date in every
    /// zone; the control shows that the noon-UTC instant the service sends a stranger prints as the
    /// next day at UTC+14. Without it, the photograph keeps `captured_at`, which the reader's zone
    /// formats as the shipped client always has.
    ///
    /// Red-proof: return `photo` unchanged from `RoutedAPI.datedForDisplay` — red at
    /// Pacific/Kiritimati, "printed 2026-09-23".
    @Test("a photograph's captured_on is shown as that date; without it, captured_at in the reader's zone")
    func capturedOnIsShownAsItsDate() throws {
        let noonUTC = try Self.instant("2026-09-22T12:00:00Z")
        let photo = Photo(treeID: UUID(), shotType: .fullTree, moderationState: .approved, capturedAt: noonUTC)
        let capturedOn = try #require(CalendarDay(isoDate: "2026-09-22"))

        let farEast = try Self.zone("Pacific/Kiritimati")
        #expect(Self.printed(noonUTC, in: farEast) == "2026-09-23", "calibration: noon UTC does not shift at UTC+14")
        for identifier in ["Pacific/Kiritimati", "Pacific/Pago_Pago", "America/Los_Angeles", "Asia/Tokyo"] {
            let zone = try Self.zone(identifier)
            let shown = RoutedAPI.datedForDisplay(photo, capturedOn: capturedOn, in: zone)
            #expect(Self.printed(shown.capturedAt, in: zone) == "2026-09-22", "printed \(Self.printed(shown.capturedAt, in: zone)) at \(identifier)")
            #expect(shown.id == photo.id)
            #expect(shown.moderationState == .approved)
        }

        // No date: the exact instant, untouched. Evening in San Francisco is the 23rd in UTC and
        // the 22nd where it was taken; the reader's zone prints the 22nd, a UTC calendar would not.
        let evening = try Self.instant("2026-09-23T02:30:00Z")
        let undated = Photo(treeID: UUID(), shotType: .leaf, capturedAt: evening)
        let kept = RoutedAPI.datedForDisplay(undated, capturedOn: nil, in: try Self.zone("America/Los_Angeles"))
        #expect(kept == undated)
        #expect(Self.printed(kept.capturedAt, in: try Self.zone("America/Los_Angeles")) == "2026-09-22")
    }
}

// MARK: - Tiles

@Suite("Community sync down · tiles")
struct CommunityTileTests {

    /// The service's fixture tile, from its own trees (`community_trees_tile.json`).
    @Test("a point maps to the tile the service names for it")
    func aPointMapsToItsTile() {
        let tile = CommunityTile(containing: Coordinate(latitude: 37.7605, longitude: -122.5046))
        #expect(tile.path == "14/2616/6333")
    }

    /// West and north edges are inclusive, east and south exclusive, as the service's `floor` is.
    @Test("tile membership is half-open, as the service's is")
    func membershipIsHalfOpen() throws {
        let n = Double(CommunityTile.side)
        let westEdge = 2616 / n * 360 - 180
        let northEdge = atan(sinh(Double.pi * (1 - 2 * 6333 / n))) * 180 / .pi
        let middle = Coordinate(latitude: 37.7605, longitude: -122.5046)

        #expect(CommunityTile(containing: Coordinate(latitude: middle.latitude, longitude: westEdge)).x == 2616)
        #expect(CommunityTile(containing: Coordinate(latitude: middle.latitude, longitude: westEdge - 1e-9)).x == 2615)
        #expect(CommunityTile(containing: Coordinate(latitude: northEdge - 1e-9, longitude: middle.longitude)).y == 6333)
        #expect(CommunityTile(containing: Coordinate(latitude: northEdge + 1e-9, longitude: middle.longitude)).y == 6332)
    }

    @Test("a box lists the tiles it touches, or nothing past the limit")
    func coveringListsTiles() throws {
        let inside = BoundingBox(minLatitude: 37.7600, maxLatitude: 37.7610, minLongitude: -122.5050, maxLongitude: -122.5040)
        #expect(CommunityTile.covering(inside, limit: 9)?.map(\.path) == ["14/2616/6333"])

        // About 3 km square across Golden Gate Park: more than one tile, at most nine.
        let park = BoundingBox(minLatitude: 37.755, maxLatitude: 37.780, minLongitude: -122.50, maxLongitude: -122.46)
        let tiles = try #require(CommunityTile.covering(park, limit: 9))
        #expect(tiles.count > 1 && tiles.count <= 9)
        #expect(Set(tiles).count == tiles.count)

        // The whole city is far more than nine.
        let city = BoundingBox(minLatitude: 37.70, maxLatitude: 37.82, minLongitude: -122.52, maxLongitude: -122.35)
        #expect(CommunityTile.covering(city, limit: 9) == nil)
    }
}

// MARK: - The pin budget

@Suite("Community sync down · the community share of the pin budget")
struct CommunityPinShareTests {

    /// At the boundary: half when both layers can fill the budget, the city's leftover when it
    /// cannot, and the odd pin to the city.
    ///
    /// Red-proof: return `communityPins` from `communityPinShare` (no cap) — red on the first row.
    @Test("the community layer takes at most half, plus what the city layer leaves")
    func shareAtTheBoundary() {
        // (pinLimit, city, community) → community kept
        let cases: [(Int, Int, Int, Int)] = [
            (400, 400, 300, 200),   // both full: half each
            (400, 400, 200, 200),   // exactly half fits
            (400, 400, 199, 199),   // under half: all of it
            (400, 200, 300, 200),   // the city uses exactly its half
            (400, 199, 300, 201),   // one pin the city did not use goes to the community
            (400, 30, 300, 300),    // a park: the city leaves most of the budget
            (400, 0, 500, 400),     // no city at all: the whole budget, and no more
            (401, 401, 300, 200),   // odd budget: the odd pin is the city's
            (400, 400, 0, 0),
            (0, 0, 5, 0),
        ]
        for (limit, city, community, expected) in cases {
            let kept = LocalAPI.communityPinShare(pinLimit: limit, cityPins: city, communityPins: community)
            #expect(kept == expected, "limit \(limit), city \(city), community \(community): kept \(kept)")
        }
    }

    /// A seeded block at a tiny budget: four cached trees and one of this phone's own cannot
    /// take more than half, the phone's own tree is among the kept ones, and the city keeps the
    /// rest.
    ///
    /// Red-proof: drop `ORDER BY cached, id` from `CommunityLayer.inBoundsSQL` and reverse the arms
    /// — red on "the phone's own tree was cut".
    @Test("over a seeded block, the community layer takes half the budget and the phone's own tree first")
    func seededBlockKeepsTheCityHalf() async throws {
        let seedURL = try #require(SeedContractTests.seedURL, "no seed database; set CYPRESS_SEED_PATH")
        let store = try await CypressStore.inMemory(seedURL: seedURL)
        let api = LocalAPI(store: store, deviceID: UUID())
        let bounds = BoundingBox(minLatitude: 37.7985, maxLatitude: 37.7995, minLongitude: -122.4445, maxLongitude: -122.4430)
        let limit = 4
        let viewport = MapViewport(bounds: bounds, zoom: 16, pinLimit: limit)

        let cityOnly = try await api.mapContent(in: viewport)
        guard case let .pins(cityAnswer) = cityOnly else { Issue.record("zoom 16 drew clusters"); return }
        #expect(cityAnswer.items.count == limit, "the fixture block is not dense enough to fill the budget")

        // Ids chosen to sort before the phone's own, so a missing ORDER BY would cut the own one.
        let cached = (0..<4).map { UUID(uuidString: "00000000-0000-4000-8000-00000000000\($0)")! }
        for (index, id) in cached.enumerated() {
            try await CommunityRefresherTests.cache(
                id, at: Coordinate(latitude: 37.7990 + Double(index) * 0.00002, longitude: -122.4437),
                tile: "t", store
            )
        }
        let own = Tree(
            id: UUID(uuidString: "FFFFFFFF-0000-4000-8000-000000000000")!,
            source: .community, coordinate: Coordinate(latitude: 37.7989, longitude: -122.4437)
        )
        try await store.queue.write { connection in
            try CommunityTreeStore().insert(own, clientUUID: UUID(), connection: connection)
        }

        guard case let .pins(answer) = try await api.mapContent(in: viewport) else { Issue.record("clusters"); return }
        let community = answer.items.filter { $0.source == .community }
        #expect(answer.items.count == limit)
        #expect(community.count == limit / 2, "the community layer took \(community.count) of \(limit)")
        #expect(community.contains { $0.id == own.id }, "the phone's own tree was cut")
        #expect(answer.items.count - community.count == limit / 2, "the city layer lost its half")
    }
}

// MARK: - The refresher

/// A scripted service for the refresher: answers per tile, records every call.
actor ScriptedTileService {
    struct Call: Equatable { let tile: String; let cursor: String? }
    private(set) var calls: [Call] = []
    private var answers: [String: [Result<CommunityTilePage, any Error>]] = [:]

    func enqueue(_ tile: CommunityTile, _ answer: Result<CommunityTilePage, any Error>) {
        answers[tile.path, default: []].append(answer)
    }

    func fetch(_ tile: CommunityTile, _ cursor: String?) throws -> CommunityTilePage {
        calls.append(Call(tile: tile.path, cursor: cursor))
        guard var queue = answers[tile.path], !queue.isEmpty else { throw URLError(.notConnectedToInternet) }
        let next = queue.removeFirst()
        answers[tile.path] = queue
        return try next.get()
    }
}

/// A clock a test moves by hand.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 1_790_000_000)
    var now: Date { lock.lock(); defer { lock.unlock() }; return value }
    func advance(_ seconds: TimeInterval) { lock.lock(); value += seconds; lock.unlock() }
}

@Suite("Community sync down · the tile refresher")
struct CommunityRefresherTests {

    static let tile = CommunityTile(x: 2616, y: 6333)!
    static let otherTile = CommunityTile(x: 2617, y: 6333)!
    /// Inside `tile` only.
    static let box = BoundingBox(minLatitude: 37.7600, maxLatitude: 37.7610, minLongitude: -122.5050, maxLongitude: -122.5040)
    static let spot = Coordinate(latitude: 37.7605, longitude: -122.5046)

    static func tree(_ id: UUID = UUID(), at coordinate: Coordinate = spot, updated: Date = Date()) -> Tree {
        Tree(id: id, source: .community, coordinate: coordinate, placement: .gps, createdAt: updated, updatedAt: updated)
    }

    static func page(_ trees: [Tree], withdrawn: [UUID] = [], cursor: String, hasMore: Bool = false) -> CommunityTilePage {
        CommunityTilePage(tile: tile.path, trees: trees, withdrawnTreeIDs: withdrawn, nextCursor: cursor, hasMore: hasMore)
    }

    static func make(
        _ store: CypressStore,
        _ service: ScriptedTileService,
        clock: TestClock = TestClock(),
        policy: CommunityTileRefresher.Policy = .init()
    ) -> CommunityTileRefresher {
        CommunityTileRefresher(queue: store.queue, policy: policy, now: { clock.now }) { tile, cursor in
            try await service.fetch(tile, cursor)
        }
    }

    static func cursor(_ tile: CommunityTile, _ store: CypressStore) async throws -> String? {
        try await store.queue.read { try CommunityTreeCacheStore().cursor(tile: tile.path, connection: $0) }
    }

    static func cached(_ store: CypressStore) async throws -> [UUID: Coordinate] {
        try await store.queue.read { connection in
            let statement = try connection.prepare("SELECT id, lat, lon FROM community_tree_cache")
            defer { statement.finalize() }
            var rows: [UUID: Coordinate] = [:]
            for row in try statement.fetchAll({ row in
                (UUID(uuidString: try row.string("id")), Coordinate(latitude: try row.double("lat"), longitude: try row.double("lon")))
            }) {
                if let id = row.0 { rows[id] = row.1 }
            }
            return rows
        }
    }

    /// A cached row as a tile would store it.
    ///
    /// `complete: true` also writes the tile's complete mark in the same transaction, as the
    /// refresher does with a tile's last page, so the tile counts as asked
    /// (`CommunityTreeCacheStore.hasAsked`). Without it the tile has a row and no mark, and reads as
    /// not asked: a test that needs "asked" must say so here.
    static func cache(
        _ id: UUID, at coordinate: Coordinate, tile: String, complete: Bool = false, _ store: CypressStore
    ) async throws {
        try await store.queue.write { connection in
            let cache = CommunityTreeCacheStore()
            try cache.apply(
                tile: tile, trees: [Tree(id: id, source: .community, coordinate: coordinate)],
                withdrawnTreeIDs: [], nextCursor: "seeded-\(tile)", at: Date(), connection: connection
            )
            if complete {
                try cache.markComplete(tile: tile, at: Date(), connection: connection)
            }
        }
    }

    /// A first visit asks for a snapshot and stores its trees and its cursor together; the next
    /// visit sends that cursor back and applies the delta.
    ///
    /// Red-proof: pass `nil` instead of the stored cursor in `CommunityTileRefresher.refresh(_:into:)`
    /// — red on "the second refresh did not send the stored cursor".
    @Test("a snapshot, then a delta from the stored cursor")
    func snapshotThenDelta() async throws {
        let store = try await CypressStore.inMemory()
        let service = ScriptedTileService()
        let clock = TestClock()
        let refresher = Self.make(store, service, clock: clock)
        let kept = Self.tree()
        let gone = Self.tree()
        await service.enqueue(Self.tile, .success(Self.page([kept, gone], cursor: "c1")))

        let first = await refresher.refresh(covering: Self.box)
        #expect(first.ending == .finished)
        #expect(first.tilesRefreshed == [Self.tile.path])
        #expect(first.changedCache)
        #expect(try await Self.cursor(Self.tile, store) == "c1")
        #expect(Set(try await Self.cached(store).keys) == [kept.id, gone.id])

        let fresh = Self.tree()
        await service.enqueue(Self.tile, .success(Self.page([fresh], withdrawn: [gone.id], cursor: "c2")))
        clock.advance(121)
        let second = await refresher.refresh(covering: Self.box)

        #expect(await service.calls == [.init(tile: Self.tile.path, cursor: nil), .init(tile: Self.tile.path, cursor: "c1")],
                "the second refresh did not send the stored cursor")
        #expect(second.removed == 1)
        #expect(try await Self.cursor(Self.tile, store) == "c2")
        #expect(Set(try await Self.cached(store).keys) == [kept.id, fresh.id])
    }

    /// The cursor advances only on success: a failed request leaves the cursor and the cache as
    /// they were, and the pass stops there.
    ///
    /// Red-proof: store the cursor before the fetch in `refresh(_:into:)` — red on the cursor.
    @Test("offline, the cursor and the cache stay as they were")
    func offlineChangesNothing() async throws {
        let store = try await CypressStore.inMemory()
        let service = ScriptedTileService()
        let clock = TestClock()
        let refresher = Self.make(store, service, clock: clock)
        let tree = Self.tree()
        await service.enqueue(Self.tile, .success(Self.page([tree], cursor: "c1")))
        _ = await refresher.refresh(covering: Self.box)

        // Nothing scripted: the service throws `notConnectedToInternet`.
        clock.advance(121)
        let offline = await refresher.refresh(covering: Self.box)

        #expect(offline.ending == .stoppedOnError)
        #expect(!offline.changedCache)
        #expect(offline.tilesRefreshed.isEmpty)
        #expect(try await Self.cursor(Self.tile, store) == "c1", "a failed request moved the cursor")
        #expect(try await Self.cached(store) == [tree.id: Self.spot])
    }

    /// A pass stops at the first failure: the next tile is not asked, so an offline phone makes
    /// one request per pass, not one per tile.
    @Test("a failure stops the pass before the next tile")
    func aFailureStopsThePass() async throws {
        let store = try await CypressStore.inMemory()
        let service = ScriptedTileService()
        let refresher = Self.make(store, service)
        // Two tiles side by side.
        let both = BoundingBox(minLatitude: 37.7600, maxLatitude: 37.7610, minLongitude: -122.5050, maxLongitude: -122.4800)
        #expect(CommunityTile.covering(both, limit: 9)?.count == 2, "calibration: the box is not two tiles")

        let outcome = await refresher.refresh(covering: both)

        #expect(outcome.ending == .stoppedOnError)
        let calls = await service.calls
        #expect(calls.count == 1, "the pass went on after a failure: \(calls)")
    }

    /// A refused cursor drops the cursor and the trees fetched through it together, then asks
    /// again from nothing. A tree another tile served stays.
    ///
    /// Red-proof: skip `dropTile` in the `validationFailed` arm — red on the stale tree.
    @Test("a refused cursor drops the tile's trees with it and takes a fresh snapshot")
    func aRefusedCursorDropsTheTile() async throws {
        let store = try await CypressStore.inMemory()
        let service = ScriptedTileService()
        let clock = TestClock()
        let refresher = Self.make(store, service, clock: clock)
        let stale = Self.tree()
        let elsewhere = UUID()
        try await Self.cache(elsewhere, at: Self.spot, tile: Self.otherTile.path, store)
        await service.enqueue(Self.tile, .success(Self.page([stale], cursor: "c1")))
        _ = await refresher.refresh(covering: Self.box)

        let current = Self.tree()
        await service.enqueue(Self.tile, .failure(APIError.validationFailed))
        await service.enqueue(Self.tile, .success(Self.page([current], cursor: "fresh")))
        clock.advance(121)
        let outcome = await refresher.refresh(covering: Self.box)

        #expect(outcome.ending == .finished)
        #expect(outcome.dropped == 1)
        #expect(await service.calls.suffix(2).map(\.cursor) == ["c1", nil])
        #expect(try await Self.cursor(Self.tile, store) == "fresh")
        #expect(Set(try await Self.cached(store).keys) == [current.id, elsewhere], "the stale tree outlived its cursor")
    }

    /// A snapshot that is itself refused is not retried in a loop.
    @Test("a refused snapshot is not retried")
    func aRefusedSnapshotIsNotRetried() async throws {
        let store = try await CypressStore.inMemory()
        let service = ScriptedTileService()
        let refresher = Self.make(store, service)
        await service.enqueue(Self.tile, .failure(APIError.validationFailed))
        await service.enqueue(Self.tile, .success(Self.page([], cursor: "never")))

        let outcome = await refresher.refresh(covering: Self.box)

        #expect(outcome.ending == .stoppedOnError)
        #expect(await service.calls.count == 1)
        #expect(try await Self.cursor(Self.tile, store) == nil)
    }

    /// A tile is left alone for the interval after an attempt, and asked again after it.
    ///
    /// Red-proof: remove the interval check — red on "asked twice inside the interval".
    @Test("a tile is asked at most once per interval")
    func theIntervalHolds() async throws {
        let store = try await CypressStore.inMemory()
        let service = ScriptedTileService()
        let clock = TestClock()
        let refresher = Self.make(store, service, clock: clock)
        await service.enqueue(Self.tile, .success(Self.page([], cursor: "c1")))
        await service.enqueue(Self.tile, .success(Self.page([], cursor: "c2")))

        _ = await refresher.refresh(covering: Self.box)
        clock.advance(119)
        let early = await refresher.refresh(covering: Self.box)
        #expect(await service.calls.count == 1, "asked twice inside the interval")
        #expect(early.tilesRefreshed.isEmpty)

        clock.advance(2)
        _ = await refresher.refresh(covering: Self.box)
        #expect(await service.calls.count == 2)
    }

    /// A zoomed-out viewport fetches nothing.
    @Test("a viewport over more tiles than the limit asks for nothing")
    func tooManyTilesAsksNothing() async throws {
        let store = try await CypressStore.inMemory()
        let service = ScriptedTileService()
        let refresher = Self.make(store, service)
        let city = BoundingBox(minLatitude: 37.70, maxLatitude: 37.82, minLongitude: -122.52, maxLongitude: -122.35)

        let outcome = await refresher.refresh(covering: city)

        #expect(outcome.ending == .tooManyTiles)
        #expect(await service.calls.isEmpty)
    }

    /// `has_more` is followed in the same pass, and the last page's cursor is the one stored.
    @Test("has_more is followed, and the last page's cursor is stored")
    func hasMoreIsFollowed() async throws {
        let store = try await CypressStore.inMemory()
        let service = ScriptedTileService()
        let refresher = Self.make(store, service)
        let first = Self.tree()
        let second = Self.tree()
        await service.enqueue(Self.tile, .success(Self.page([first], cursor: "p1", hasMore: true)))
        await service.enqueue(Self.tile, .success(Self.page([second], cursor: "p2")))

        _ = await refresher.refresh(covering: Self.box)

        #expect(await service.calls.map(\.cursor) == [nil, "p1"])
        #expect(try await Self.cursor(Self.tile, store) == "p2")
        #expect(Set(try await Self.cached(store).keys) == [first.id, second.id])
    }

    /// The cursor, not a cached tree's `updatedAt`, decides what changed: a tree the delta serves
    /// again is written as served, even when its day-precision `updatedAt` is not later.
    @Test("the cursor decides what changed, not a cached tree's updatedAt")
    func theCursorDecides() async throws {
        let store = try await CypressStore.inMemory()
        let service = ScriptedTileService()
        let clock = TestClock()
        let refresher = Self.make(store, service, clock: clock)
        let id = UUID()
        let day = Date(timeIntervalSince1970: 1_790_000_000)
        await service.enqueue(Self.tile, .success(Self.page([Self.tree(id, updated: day)], cursor: "c1")))
        _ = await refresher.refresh(covering: Self.box)

        let moved = Coordinate(latitude: 37.7606, longitude: -122.5047)
        await service.enqueue(Self.tile, .success(Self.page([Self.tree(id, at: moved, updated: day)], cursor: "c2")))
        clock.advance(121)
        _ = await refresher.refresh(covering: Self.box)

        #expect(try await Self.cached(store)[id] == moved)
    }

    /// A removal names an id from anywhere: it leaves the whole cache, whichever tile served it.
    @Test("a removal drops the tree whichever tile served it")
    func aRemovalReachesEveryTile() async throws {
        let store = try await CypressStore.inMemory()
        let service = ScriptedTileService()
        let refresher = Self.make(store, service)
        let elsewhere = UUID()
        try await Self.cache(elsewhere, at: Self.spot, tile: Self.otherTile.path, store)
        await service.enqueue(Self.tile, .success(Self.page([], withdrawn: [elsewhere, UUID()], cursor: "c1")))

        let outcome = await refresher.refresh(covering: Self.box)

        #expect(outcome.removed == 1)
        #expect(try await Self.cached(store).isEmpty)
    }

    /// The phone's own tree wins: a tile serving it back stores nothing, and the outcome says so.
    @Test("a tree this phone added is not stored when a tile serves it back")
    func theAddersOwnTreeWins() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: LocationCorrectionTests.deviceID)
        let mine = try await LocationCorrectionTests.add(api)
        let service = ScriptedTileService()
        let refresher = Self.make(store, service)
        var served = mine
        served.coordinate = Self.spot
        await service.enqueue(Self.tile, .success(Self.page([served], cursor: "c1")))

        let outcome = await refresher.refresh(covering: Self.box)

        #expect(outcome.stored == 0)
        #expect(try await Self.cached(store).isEmpty)
        #expect(try await api.treeProfile(id: mine.id).tree.coordinate == mine.coordinate, "the service's copy moved the phone's own tree")
    }
}

// MARK: - The profile merge

@Suite("Community sync down · the profile merge")
struct CommunityProfileMergeTests {

    static let base = URL(string: "https://service.invalid/api/v1")!

    static func router(local: LocalDouble, transport: ScriptedTransport) -> RoutedAPI {
        RoutedAPI(local: local, remote: RemoteAPI(baseURL: base, transport: transport, session: .shared))
    }

    static func profileBody(_ id: UUID, addedByYou: Bool, photos: String = "[]") -> String {
        """
        {"added_by_you":\(addedByYou),"community_tree":null,"deletable_photo_ids":[],"is_published":true,
         "own_photo_ids":[],"photo_count":0,"photos":\(photos),"tree_uuid":"\(id.uuidString.lowercased())",
         "visit_count":0}
        """
    }

    static func historyBody(_ id: UUID) -> String {
        """
        {"tree_uuid":"\(id.uuidString.lowercased())","events":[{"id":"a0d4e5f6-1111-4c2d-8e3f-000000000001",
         "kind":"added","occurred_at":"2026-09-21T00:00:00Z","from_coordinate":null,
         "to_coordinate":{"latitude":37.7601,"longitude":-122.505},"from_species_id":null,
         "to_species_id":null,"placement":"gps"}],"complete":true}
        """
    }

    /// A tree the reader's account added on another phone reaches this one only through the cache,
    /// so the phone says "not yours" and the service says yes. The service's yes is adopted, and
    /// the history rides along.
    ///
    /// Red-proof: drop `|| community.addedByYou` in `refreshedTreeProfile` — red on the adoption.
    @Test("the service's added_by_you is adopted, and the history is carried")
    func theAdderIsAdopted() async throws {
        let id = UUID()
        let local = LocalDouble(profile: TreeProfile(tree: Tree(id: id, source: .community, coordinate: CommunityRefresherTests.spot)))
        let transport = ScriptedTransport()
        transport.answer("GET /trees/\(id.uuidString)", with: Self.profileBody(id, addedByYou: true))
        transport.answer("GET /trees/\(id.uuidString)/history", with: Self.historyBody(id))

        let merged = try await Self.router(local: local, transport: transport).refreshedTreeProfile(id: id)

        #expect(merged.addedByYou, "the service's added_by_you was not adopted")
        let history = try #require(merged.communityHistory, "the history did not reach the profile")
        #expect(history.events.map(\.kind) == [.added])
        #expect(history.events.first?.day == CalendarDay(isoDate: "2026-09-21"))
        #expect(!merged.canMovePin, "a cache-only tree became movable")
    }

    /// The service's "no" never overrides the phone's yes: the service answers no for a tree it has
    /// not received, and one phone can get both answers for one tree.
    @Test("the service's no does not take the phone's yes away")
    func aServiceNoKeepsThePhonesYes() async throws {
        let id = UUID()
        let local = LocalDouble(profile: TreeProfile(tree: Tree(id: id, source: .community, coordinate: CommunityRefresherTests.spot), addedByYou: true))
        let transport = ScriptedTransport()
        transport.answer("GET /trees/\(id.uuidString)", with: Self.profileBody(id, addedByYou: false))

        let merged = try await Self.router(local: local, transport: transport).refreshedTreeProfile(id: id)

        #expect(merged.addedByYou)
        #expect(merged.communityHistory == nil, "an unscripted history (not_found) was not read as no history")
    }

    /// A city tree has no history, so none is asked for.
    ///
    /// Red-proof: remove the `source == .community` guard in `RoutedAPI.history(of:from:)` — red on
    /// the extra request.
    @Test("a city tree's refresh asks for no history")
    func aCityTreeAsksNoHistory() async throws {
        let id = UUID()
        let local = LocalDouble(profile: TreeProfile(tree: Tree(id: id, source: .cityImport, coordinate: CommunityRefresherTests.spot)))
        let transport = ScriptedTransport()
        transport.answer("GET /trees/\(id.uuidString)", with: Self.profileBody(id, addedByYou: false))

        _ = try await Self.router(local: local, transport: transport).refreshedTreeProfile(id: id)

        #expect(transport.calls.map(\.path) == ["/trees/\(id.uuidString)"], "asked: \(transport.calls.map(\.path))")
    }

    /// A history that fails costs the history, never the photographs.
    @Test("a failed history still merges the photographs")
    func aFailedHistoryKeepsThePhotos() async throws {
        let id = UUID()
        let photo = UUID()
        let local = LocalDouble(profile: TreeProfile(tree: Tree(id: id, source: .community, coordinate: CommunityRefresherTests.spot)))
        let transport = ScriptedTransport()
        transport.answer("GET /trees/\(id.uuidString)", with: Self.profileBody(id, addedByYou: false, photos: """
            [{"captured_at":"2026-09-22T12:00:00Z","captured_on":"2026-09-22","is_publicly_visible":true,
              "photo_id":"\(photo.uuidString.lowercased())","shot_type":"full_tree"}]
            """))
        transport.answer("GET /trees/\(id.uuidString)/history", throwing: APIError.serverError)

        let merged = try await Self.router(local: local, transport: transport).refreshedTreeProfile(id: id)

        #expect(merged.communityHistory == nil)
        let shown = try #require(merged.photos.items.first { $0.id == photo }, "the photograph was lost with the history")
        // Dated by `captured_on` in this runner's own zone: the 22nd, wherever the suite runs.
        #expect(CommunityCalendarDayTests.printed(shown.capturedAt, in: .current) == "2026-09-22")
    }
}

// MARK: - The wiring

@Suite("Community sync down · wiring")
struct CommunitySyncWiringTests {

    static func databaseURL() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cypress-c2-wiring-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("cypress.sqlite")
    }

    /// The gate shut (every DEBUG build, and the UI suite): no refresher, so nothing is fetched.
    ///
    /// Red-proof: build the refresher outside `if access.allowsNetwork` — red on "a gate-shut build
    /// wired a refresher".
    @Test("with the gate shut there is no refresher")
    func gateShutWiresNothing() async throws {
        let data = try await DataLayer.boot(databaseURL: try Self.databaseURL(), seedURL: nil, remoteAccess: .disabled)
        #expect(data.refreshCommunityTrees == nil, "a gate-shut build wired a refresher")
    }

    /// With a wire, the refresher asks the tile route through `RemoteAPI` and fills the cache the
    /// map reads.
    @Test("with a wire, the refresher fills the cache the map reads")
    func aWireFillsTheCache() async throws {
        let transport = ScriptedTransport()
        let id = UUID()
        transport.answer("GET /community-trees", with: """
            {"tile":"14/2616/6333","trees":[{"id":"\(id.uuidString.lowercased())","externalRef":null,"idSpace":null,
             "source":"community","coordinate":{"latitude":37.7605,"longitude":-122.5046},"address":null,
             "siteType":null,"neighborhoodID":null,"status":"alive","speciesCurrentID":null,"plantedYear":null,
             "dbhCityCmRange":null,"siteLineage":null,"verificationState":"unverified","placement":"gps",
             "cityRecord":null,"statedLandContext":null,"createdAt":"2026-09-21T00:00:00Z",
             "updatedAt":"2026-09-21T00:00:00Z","deletedAt":null}],
             "withdrawn_tree_ids":[],"next_cursor":"c1","has_more":false}
            """)
        let data = try await DataLayer.boot(
            databaseURL: try Self.databaseURL(),
            seedURL: nil,
            baseURL: URL(string: "https://cypress-sync.invalid/api/v1")!,
            transport: transport,
            storageSession: StubStorageProtocol.session()
        )
        let refresh = try #require(data.refreshCommunityTrees, "a wired build has no refresher")

        let changed = await refresh(CommunityRefresherTests.box)

        #expect(changed)
        #expect(transport.call("GET /community-trees")?.query?.contains("tile=14/2616/6333") == true)
        let content = try await data.api.mapContent(in: MapViewport(bounds: CommunityRefresherTests.box, zoom: 18))
        guard case let .pins(pins) = content else { Issue.record("clusters at zoom 18"); return }
        #expect(pins.items.contains { $0.id == id }, "the fetched tree is not on the map")
    }
}

// MARK: - The map

@Suite("Community sync down · the map reads again when trees arrive")
@MainActor
struct CommunityMapRefreshTests {

    /// The refresh runs behind a settled map, about the viewport just read, and a refresh that
    /// changed the cache makes the map read again, which draws the new tree.
    ///
    /// Red-proof: return early in `startCommunityRefresh` when `changed` — red on the missing pin.
    @Test("a refresh that changed the cache redraws the map with the new tree")
    func aChangedCacheRedraws() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: UUID())
        let arrived = UUID()
        let asked = Asked()
        let model = MapModel(api: api, refreshCommunity: { bounds in
            await asked.record(bounds)
            try? await CommunityRefresherTests.cache(arrived, at: CommunityRefresherTests.spot, tile: "t", store)
            return true
        })

        model.cameraDidChange(bounds: CommunityRefresherTests.box, zoom: 18)
        await TestWait.settle(model) {
            guard case let .pins(pins) = model.content else { return false }
            return pins.items.contains { $0.id == arrived }
        }

        let bounds = await asked.bounds
        #expect(bounds.count == 1, "the refresh ran \(bounds.count) times")
        #expect(bounds.first == model.viewport?.bounds, "the refresh was about another viewport")
    }

    /// A refresh that changed nothing does not read the map again.
    @Test("a refresh that changed nothing does not redraw")
    func anUnchangedCacheDoesNotRedraw() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: UUID())
        let written = UUID()
        let model = MapModel(api: api, refreshCommunity: { _ in
            // Written, but reported as no change: only a re-read could draw it.
            try? await CommunityRefresherTests.cache(written, at: CommunityRefresherTests.spot, tile: "t", store)
            return false
        })

        model.cameraDidChange(bounds: CommunityRefresherTests.box, zoom: 18)
        await TestWait.settle(model) { model.communityRefresh != nil }
        await model.communityRefresh?.value
        // Anything the refresh started has finished too.
        for task in model.outstandingTasks { await task.value }

        guard case let .pins(pins) = model.content else { Issue.record("clusters"); return }
        #expect(!pins.items.contains { $0.id == written }, "the map read again on an unchanged cache")
    }
}

/// What a refresh closure was asked, across the actor boundary.
actor Asked {
    private(set) var bounds: [BoundingBox] = []
    func record(_ box: BoundingBox) { bounds.append(box) }
}
