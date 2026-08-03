import Foundation
import Testing
@testable import Cypress

/// The 10 m add-a-tree proximity dedupe, and the corner of it that made the app refuse honest
/// contributions: **the diagonal**.
///
/// `BoundingBox(around:radiusM:)` is a square whose half-width is the radius on each axis, so it
/// circumscribes the circle and reaches `radius·√2` at the corners — 14.1 m for a 10 m ask.
/// `TreeQueries.nearest` never re-checked the true distance, `LocalAPI.addTree` reads a non-empty
/// candidate list as a conflict, and `conflict` is not retryable: the outbox item went terminal
/// immediately and the contributor was refused for good, with a real nearby tree shown as the
/// reason (ERRATA E35).
///
/// Every case below is on the diagonal on purpose. A test written due north passes against the
/// broken code.
@Suite("Proximity dedupe")
struct ProximityDedupeTests {

    private static let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-0000000000B1")!

    /// A point `metres` from `origin` along the north-east diagonal — the direction in which a
    /// square bounding box reaches furthest past its radius. Negative walks south-west.
    static func diagonal(from origin: Coordinate, meters: Double) -> Coordinate {
        let leg = meters / 2.0.squareRoot()
        let metersPerDegreeLatitude = 111_320.0
        let metersPerDegreeLongitude = metersPerDegreeLatitude * cos(origin.latitude * .pi / 180)
        return Coordinate(
            latitude: origin.latitude + leg / metersPerDegreeLatitude,
            longitude: origin.longitude + leg / metersPerDegreeLongitude
        )
    }

    private static func draft(at coordinate: Coordinate) -> TreeDraft {
        TreeDraft(
            coordinate: coordinate,
            photoLocalPath: "/tmp/cypress-proximity-test.jpg",
            attribution: Attribution.anonymous(deviceID: deviceID)
        )
    }

    // MARK: - The helper itself

    @Test("the diagonal fixture really is the distance it claims, and really is inside the box")
    func fixtureIsHonest() {
        let origin = Coordinate(latitude: 37.7761, longitude: -122.4464)
        let twelve = Self.diagonal(from: origin, meters: 12)
        #expect(abs(origin.distance(to: twelve) - 12) < 0.05)

        // The whole bug in two assertions: 12 m away, and inside the box a 10 m query builds.
        #expect(BoundingBox(around: twelve, radiusM: TreeDraft.proximityDedupeRadiusM).contains(origin))
        #expect(origin.distance(to: twelve) > TreeDraft.proximityDedupeRadiusM)
    }

    // MARK: - The community half

    @Test("a tree 12 m away on the diagonal is not a duplicate")
    func diagonalTwelveMetersIsNotAConflict() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)

        let first = Coordinate(latitude: 37.7761, longitude: -122.4464)
        _ = try await api.addTree(Self.draft(at: first))

        // SF street trees sit 6–10 m apart (D6), so this is the common case, not the edge.
        let second = Self.diagonal(from: first, meters: 12)
        let added = try await api.addTree(Self.draft(at: second))
        #expect(added.source == .community)
        #expect(added.verificationState == .unverified)

        let profile = try await api.treeProfile(id: added.id)
        #expect(profile.tree.id == added.id)
    }

    @Test("a tree 8 m away on the diagonal still is a duplicate")
    func diagonalEightMetersIsAConflict() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)

        let first = Coordinate(latitude: 37.7761, longitude: -122.4464)
        let existing = try await api.addTree(Self.draft(at: first))

        let second = Self.diagonal(from: first, meters: 8)
        do {
            _ = try await api.addTree(Self.draft(at: second))
            Issue.record("a tree 8 m from an existing one was accepted")
        } catch let conflict as ProximityConflict {
            #expect(conflict.candidates.map(\.tree.id) == [existing.id])
            #expect(conflict.candidates.allSatisfy { $0.distanceM <= TreeDraft.proximityDedupeRadiusM })
        }
    }

    @Test("the shortlist itself answers in a circle, not in a square")
    func shortlistIsACircle() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)

        let tree = Coordinate(latitude: 37.7761, longitude: -122.4464)
        _ = try await api.addTree(Self.draft(at: tree))
        let standingPoint = Self.diagonal(from: tree, meters: 12)

        let atTen = try await api.treesNear(standingPoint, radiusM: 10, limit: 20)
        #expect(atTen.isEmpty, "a tree 12 m away came back from a 10 m query")

        let atFifteen = try await api.treesNear(standingPoint, radiusM: 15, limit: 20)
        #expect(atFifteen.count == 1)
        #expect(abs((atFifteen.first?.distanceM ?? 0) - 12) < 0.05)
    }

    @Test("the dedupe reads the whole box, so its own duplicate cannot be cut by a LIMIT")
    func dedupeIsNotTruncatedByItsLimit() async throws {
        let store = try await CypressStore.inMemory()
        let community = CommunityTreeStore()
        let center = Coordinate(latitude: 37.7761, longitude: -122.4464)

        // Fifteen trees in the box, the nearest one written last. `inBounds` has no ORDER BY, so a
        // LIMIT applied inside SQL keeps rows in storage order — and the row it would drop is the
        // 2 m duplicate this query exists to find.
        for index in 0..<15 {
            let meters = Double(14 - index) * 0.6 + 2
            let tree = Tree(source: .community, coordinate: Self.diagonal(from: center, meters: meters))
            try await store.queue.write { connection in
                try community.insert(tree, clientUUID: UUID(), connection: connection)
            }
        }

        let found = try await store.queue.read { connection in
            try community.near(center, radiusM: TreeDraft.proximityDedupeRadiusM, limit: 10, connection: connection)
        }
        #expect(!found.isEmpty)
        #expect(found.allSatisfy { center.distance(to: $0.coordinate) <= TreeDraft.proximityDedupeRadiusM })
        // Nearest first, and the nearest of all is the one that must be in hand.
        let nearest = try #require(found.first)
        #expect(center.distance(to: nearest.coordinate) < 2.5)
    }

    // MARK: - The seed half

    @Test("a seeded tree 12 m away on the diagonal is not returned by a 10 m query")
    func seedNearestReChecksTheDistance() async throws {
        let seedURL = try #require(SeedContractTests.seedURL, "no seed database; set CYPRESS_SEED_PATH")
        let store = try await CypressStore.inMemory(seedURL: seedURL)
        let schema = try #require(store.seed)
        let queries = TreeQueries(schema: schema, seedHasSoftDeletedTrees: store.seedHasSoftDeletedTrees)

        // A real inventory row, whichever one is nearest the Marina fixture the previews use.
        let subject = try await store.queue.read { connection in
            try queries.nearest(
                to: Coordinate(latitude: 37.799005143246, longitude: -122.443869066799),
                radiusM: 60,
                limit: 1,
                connection: connection
            )
        }
        let tree = try #require(subject.first?.tree)

        // Stand 12 m south-west of it, so it sits at the corner of a 10 m box.
        let standingPoint = Self.diagonal(from: tree.coordinate, meters: -12)
        #expect(abs(standingPoint.distance(to: tree.coordinate) - 12) < 0.05)
        #expect(BoundingBox(around: standingPoint, radiusM: 10).contains(tree.coordinate))

        // Both index strategies, because the seed contract asserts the two answer identically and
        // an exact re-check that only one path applies would break that.
        for strategy in SpatialIndexStrategy.allCases {
            let atTen = try await store.queue.read { connection in
                try queries.nearest(to: standingPoint, radiusM: 10, limit: 50, strategy: strategy, connection: connection)
            }
            #expect(
                !atTen.contains { $0.tree.id == tree.id },
                "\(strategy): a tree 12 m away came back from a 10 m query"
            )
            #expect(
                atTen.allSatisfy { $0.distanceM <= 10 },
                "\(strategy): a 10 m query returned a row further than 10 m"
            )

            let atFifteen = try await store.queue.read { connection in
                try queries.nearest(to: standingPoint, radiusM: 15, limit: 50, strategy: strategy, connection: connection)
            }
            #expect(
                atFifteen.contains { $0.tree.id == tree.id },
                "\(strategy): widening the radius past the tree did not find it"
            )
        }
    }
}
