import Foundation
import Testing
@testable import Cypress

/// Screen 01's pin budget, and the case in which the community layer used to vanish from it.
///
/// Seed pins come back already capped at `viewport.pinLimit`; community trees were appended after
/// them and the result cut with `prefix(pinLimit)`, so whenever the seed query hit its cap — which
/// it does in normal SF density, `MapModel` reading each band at 260 against a zoom-16 band of
/// around 264 — every community tree was dropped, with no error and no log (ERRATA E36).
///
/// The fixture below sets a deliberately tiny `pinLimit` so the cap is reached over a real seeded
/// block. That is the same condition, produced in a millisecond instead of over the Sunset.
@Suite("Map content budget")
struct MapContentBudgetTests {

    private static let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-0000000000C1")!

    /// A block of the Marina dense enough to overrun any small budget.
    private static let bounds = BoundingBox(
        minLatitude: 37.7985, maxLatitude: 37.7995,
        minLongitude: -122.4445, maxLongitude: -122.4430
    )

    private static var center: Coordinate {
        Coordinate(
            latitude: (bounds.minLatitude + bounds.maxLatitude) / 2,
            longitude: (bounds.minLongitude + bounds.maxLongitude) / 2
        )
    }

    private static func pins(_ content: MapContent) -> [TreePin] {
        guard case let .pins(pins) = content else { return [] }
        return pins.items
    }

    @Test("a community tree survives a viewport whose seed query is already at its cap")
    func communityTreeSurvivesASeedAtItsCap() async throws {
        let seedURL = try #require(SeedContractTests.seedURL, "no seed database; set CYPRESS_SEED_PATH")
        let store = try await CypressStore.inMemory(seedURL: seedURL)
        let api = LocalAPI(store: store, deviceID: Self.deviceID)

        // Zoom 16: individual pins, per A1.
        let limit = 3
        let viewport = MapViewport(bounds: Self.bounds, zoom: 16, pinLimit: limit)

        // The precondition the bug needed: the seed alone fills the budget exactly.
        let seedOnly = Self.pins(try await api.mapContent(in: viewport))
        #expect(seedOnly.count == limit, "the fixture block is not dense enough to reach the cap")

        let added = Tree(source: .community, coordinate: Self.center)
        try await store.queue.write { connection in
            try CommunityTreeStore().insert(added, clientUUID: UUID(), connection: connection)
        }

        let withCommunity = Self.pins(try await api.mapContent(in: viewport))
        #expect(
            withCommunity.contains { $0.id == added.id },
            "the contributor's own tree was dropped from the viewport they added it in"
        )
        // The budget is still a budget: the community tree took a seed pin's place, it was not
        // added on top of a full response.
        #expect(withCommunity.count == limit)
        #expect(withCommunity.filter { $0.source == .community }.count == 1)

        // And it stays on its own layer (DECISIONS §3.16) — the pin carries what makes it dashed.
        let pin = try #require(withCommunity.first { $0.id == added.id })
        #expect(MapPinKind.kind(for: pin) == .community)
    }

    @Test("many community trees never crowd out more of the budget than the budget holds")
    func communityTreesCannotOverrunTheBudget() async throws {
        let seedURL = try #require(SeedContractTests.seedURL, "no seed database; set CYPRESS_SEED_PATH")
        let store = try await CypressStore.inMemory(seedURL: seedURL)
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let community = CommunityTreeStore()

        let limit = 3
        let viewport = MapViewport(bounds: Self.bounds, zoom: 16, pinLimit: limit)

        // More community trees than the whole viewport is allowed to return.
        var added: Set<UUID> = []
        for index in 0..<(limit + 2) {
            let tree = Tree(
                source: .community,
                coordinate: Coordinate(
                    latitude: Self.center.latitude + Double(index) * 0.000_02,
                    longitude: Self.center.longitude
                )
            )
            added.insert(tree.id)
            try await store.queue.write { connection in
                try community.insert(tree, clientUUID: UUID(), connection: connection)
            }
        }

        let content = Self.pins(try await api.mapContent(in: viewport))
        #expect(content.count <= limit, "the viewport returned \(content.count) pins for a budget of \(limit)")
        #expect(content.allSatisfy { added.contains($0.id) })
    }

    @Test("a clustered viewport still counts the community tree in its badge")
    func clustersStillMerge() async throws {
        let seedURL = try #require(SeedContractTests.seedURL, "no seed database; set CYPRESS_SEED_PATH")
        let store = try await CypressStore.inMemory(seedURL: seedURL)
        let api = LocalAPI(store: store, deviceID: Self.deviceID)

        let viewport = MapViewport(bounds: Self.bounds, zoom: 14, pinLimit: 3)
        let before = try await api.mapContent(in: viewport).pinCount

        let added = Tree(source: .community, coordinate: Self.center)
        try await store.queue.write { connection in
            try CommunityTreeStore().insert(added, clientUUID: UUID(), connection: connection)
        }

        let after = try await api.mapContent(in: viewport).pinCount
        #expect(after == before + 1)
    }
}
