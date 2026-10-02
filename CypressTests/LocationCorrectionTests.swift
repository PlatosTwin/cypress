import Foundation
import Testing
@testable import Cypress

/// A community tree's pin move, and the adder it depends on (`AppSchema` v23, the community-trees
/// round C1).
///
/// The sentences the round has to make true, one group of tests each:
///
/// 1. **`addTree` records who added the tree and where** — the adder on the row and the root of the
///    location chain, whose id is the tree's.
/// 2. **The adder moves the pin, and nobody else does.** A move appends a head, stamps the old one,
///    moves the tree's read cache and queues a `location_correction`, in one transaction; somebody
///    else, nobody, a signed-out phone on its account's tree, a cached tree and an unknown id are
///    each refused with the answer the service would give.
/// 3. **The move runs the 10 m dedupe against every other tree**, cached ones included, and not
///    against the tree itself.
/// 4. **`claimDevice` adopts the tree and its chain**, so the account moves it and the signed-out
///    phone no longer can.
///
/// The deletion doors over the same rows are `CommunityTreeDeletionTests`.
@Suite("Community trees · location corrections")
struct LocationCorrectionTests {

    static let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-0000000C1001")!
    static let otherDeviceID = UUID(uuidString: "D0000000-0000-4000-8000-0000000C1002")!
    static let userID = UUID(uuidString: "0E000000-0000-4000-8000-0000000C1003")!

    /// West of Ocean Beach, where the street-tree inventory has nothing within 10 m
    /// (`CommunityOutboxKindTests.offshore`'s argument). These tests run without a seed anyway.
    static let offshore = Coordinate(latitude: 37.7600, longitude: -122.5400)

    /// A staged capture `addTree` can strip. A real file, because the strip reads it.
    static func capture(_ name: String) -> String {
        let path = NSTemporaryDirectory() + "cypress-c1-\(name)-\(UUID().uuidString).jpg"
        FileManager.default.createFile(atPath: path, contents: Data([0xFF, 0xD8, 0xFF, 0xD9]))
        return path
    }

    static func add(
        _ api: LocalAPI,
        at coordinate: Coordinate = offshore,
        clientUUID: UUID = UUID()
    ) async throws -> Tree {
        try await api.addTree(
            TreeDraft(
                clientUUID: clientUUID,
                coordinate: coordinate,
                photoLocalPath: capture("add"),
                attribution: .anonymous(deviceID: deviceID)
            )
        )
    }

    static func chain(_ store: CypressStore, _ treeID: UUID) async throws -> [TreeLocation] {
        try await store.queue.read { try TreeLocationStore().chain(treeID: treeID, connection: $0) }
    }

    static func adder(_ store: CypressStore, _ treeID: UUID) async throws -> ContributionOwner? {
        try await store.queue.read { try CommunityTreeStore().adder(treeID: treeID, connection: $0) }
    }

    static func corrections(_ store: CypressStore) async throws -> [OutboxStore.Record] {
        try await store.queue.read { try OutboxStore().allItems(connection: $0) }
            .filter { $0.item.kind == .locationCorrection }
    }

    static func profileCoordinate(_ api: LocalAPI, _ id: UUID) async throws -> Coordinate {
        try await api.treeProfile(id: id).tree.coordinate
    }

    // MARK: - 1. The add

    /// Red-proof: pass `.nobody` as `adder:` in `LocalAPI.addTree` — red on the adder, with
    /// "the add recorded nobody".
    @Test("adding a tree records its adder and the root of its location chain")
    func addingATreeRecordsItsAdderAndRoot() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID, userID: Self.userID)
        let key = UUID()
        let tree = try await Self.add(api, clientUUID: key)

        let adder = try await Self.adder(store, tree.id)
        #expect(adder == .user(Self.userID), "the add recorded \(String(describing: adder)), not the account")

        let chain = try await Self.chain(store, tree.id)
        #expect(chain.count == 1, "a new tree has \(chain.count) positions, not its root alone")
        let root = try #require(chain.first)
        #expect(root.id == tree.id, "the root's id is not the tree's")
        #expect(root.isRoot && root.isCurrent)
        #expect(root.clientUUID == key, "the root is not keyed on the add")
        #expect(root.coordinate == Self.offshore)
        #expect(root.placement == tree.placement)
        #expect(root.owner == .user(Self.userID))
    }

    // MARK: - 2. The adder moves the pin

    /// The whole happy path, and every place the move has to land.
    ///
    /// Red-proofs, each read by its message: drop `communityTrees.move` from `correctLocation` and
    /// this goes red on "the profile still shows the old position"; drop `locations.supersede` and
    /// the insert is refused by the one-head index (a `SQLiteError`, the test fails on the throw);
    /// drop `queueAppliedMutation` and it goes red on "queued 0 corrections".
    @Test("the adder moves the pin: the chain gains a head, the tree follows, and the move is queued")
    func theAdderMovesThePin() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let tree = try await Self.add(api)
        let destination = ProximityDedupeTests.diagonal(from: Self.offshore, meters: 30)

        let moved = try await api.correctLocation(
            treeID: tree.id, to: destination, placement: .contributorPlaced, locationAccuracyM: 4.5
        )
        #expect(moved.id == tree.id)
        #expect(moved.coordinate == destination, "the returned tree is not where it was moved to")
        #expect(moved.placement == .contributorPlaced)

        let shown = try await Self.profileCoordinate(api, tree.id)
        #expect(shown == destination, "the profile still shows the old position: \(shown)")
        let near = try await api.treesNear(destination, radiusM: 2, limit: 5)
        #expect(near.map(\.tree.id) == [tree.id], "the shortlist does not find the tree where it now is")

        let chain = try await Self.chain(store, tree.id)
        #expect(chain.count == 2, "the chain holds \(chain.count) positions after one move")
        let root = try #require(chain.first), head = try #require(chain.last)
        #expect(root.isRoot && root.coordinate == Self.offshore, "the root moved; history was overwritten")
        #expect(root.supersededBy == head.id, "the root is not stamped with its successor")
        #expect(head.isCurrent && !head.isRoot)
        #expect(head.id != tree.id, "the correction took the tree's id, which the service refuses")
        #expect(head.coordinate == destination)
        #expect(head.placement == .contributorPlaced)
        #expect(head.locationAccuracyM == 4.5)
        #expect(head.owner == .device(Self.deviceID))

        let queued = try await Self.corrections(store)
        #expect(queued.count == 1, "the move queued \(queued.count) corrections")
        let record = try #require(queued.first)
        #expect(record.locallyApplied, "the correction was queued unapplied; a drain would apply it twice")
        guard case let .locationCorrection(correction) = try OutboxPayload.decode(
            kind: record.item.kind, from: record.item.payload
        ) else {
            Issue.record("the queued row did not decode as a location correction")
            return
        }
        // The two ids the wire carries, and which row each names.
        #expect(correction.id == head.id, "the payload's id is not the chain row's")
        #expect(correction.clientUUID == record.item.clientUUID, "the payload's key is not the row's")
        #expect(correction.clientUUID == head.clientUUID, "the chain row is not keyed on the act")
        #expect(correction.id != correction.clientUUID)
        #expect(correction.treeID == tree.id)
        #expect(correction.coordinate == destination)
        #expect(correction.placement == .contributorPlaced)
        #expect(correction.locationAccuracyM == 4.5)
        #expect(correction.attribution.deviceID == Self.deviceID)
        #expect(correction.attribution.userID == nil)
    }

    /// Red-proof: make `correctLocation` skip the `isOwned(by:)` guard — red here on "a tree nobody
    /// added was moved".
    @Test("a tree whose adder is nobody cannot be moved by anybody")
    func nobodysTreeCannotBeMoved() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        // Written the way every pre-v23 tree reads: through the store, with no adder.
        let tree = Tree(source: .community, coordinate: Self.offshore)
        try await store.queue.write { connection in
            try CommunityTreeStore().insert(tree, clientUUID: UUID(), connection: connection)
        }
        let adder = try await Self.adder(store, tree.id)
        #expect(adder == .nobody, "fixture: the tree has an adder, \(String(describing: adder))")
        let root = try #require(try await Self.chain(store, tree.id).first)
        #expect(root.owner == .nobody, "fixture: the root has a mover")

        await #expect(throws: APIError.forbidden, "a tree nobody added was moved") {
            _ = try await api.correctLocation(
                treeID: tree.id,
                to: ProximityDedupeTests.diagonal(from: Self.offshore, meters: 30),
                placement: .gps,
                locationAccuracyM: nil
            )
        }
        #expect(try await Self.corrections(store).isEmpty)
        #expect(try await Self.chain(store, tree.id).count == 1)
    }

    @Test("somebody else's tree cannot be moved, and the refusal changes nothing")
    func somebodyElsesTreeCannotBeMoved() async throws {
        let store = try await CypressStore.inMemory()
        let adder = LocalAPI(store: store, deviceID: Self.deviceID)
        let stranger = LocalAPI(store: store, deviceID: Self.otherDeviceID)
        let tree = try await Self.add(adder)

        await #expect(throws: APIError.forbidden) {
            _ = try await stranger.correctLocation(
                treeID: tree.id,
                to: ProximityDedupeTests.diagonal(from: Self.offshore, meters: 30),
                placement: .gps,
                locationAccuracyM: nil
            )
        }
        #expect(try await Self.corrections(store).isEmpty)
        #expect(try await Self.chain(store, tree.id).count == 1)
        #expect(try await Self.profileCoordinate(adder, tree.id) == Self.offshore)
    }

    /// The service's rule after `POST /devices/claim` (`TestAClaimedDevicesOwnCredentialNoLongerActsOnItsTrees`):
    /// the phone signed out is a stranger to the account's trees. And the claim is what makes the
    /// signed-out add the account's.
    ///
    /// Red-proof: remove `community_trees` from `claimDevice`'s adoption loop — red on "the claim did
    /// not adopt the tree" and on the account's move being refused.
    @Test("a claim adopts the tree and its chain, and the signed-out phone cannot move it afterwards")
    func aClaimAdoptsTheTree() async throws {
        let store = try await CypressStore.inMemory()
        let signedOut = LocalAPI(store: store, deviceID: Self.deviceID)
        let tree = try await Self.add(signedOut)
        #expect(try await Self.adder(store, tree.id) == .device(Self.deviceID), "fixture: the add was not the device's")

        // A species claim this installation made on it, signed out (chip 71).
        let claim = SpeciesAssertion(
            treeID: tree.id, speciesID: UUID(), source: .community, owner: .device(Self.deviceID)
        )
        try await store.queue.write { try SpeciesAssertionStore().insert(claim, connection: $0) }

        let account = LocalAPI(store: store, deviceID: Self.deviceID)
        try await account.claimDevice(deviceUUID: Self.deviceID, userID: Self.userID)

        let claims = try await store.queue.read {
            try SpeciesAssertionStore().chain(treeID: tree.id, connection: $0)
        }
        #expect(claims.first?.owner == .user(Self.userID), "the claim did not adopt the species claim: \(claims.map(\.owner))")

        let adopted = try await Self.adder(store, tree.id)
        #expect(adopted == .user(Self.userID), "the claim did not adopt the tree: \(String(describing: adopted))")
        let root = try #require(try await Self.chain(store, tree.id).first)
        #expect(root.owner == .user(Self.userID), "the claim did not adopt the root position")

        // A fresh signed-out handle on the same installation: the stranger the service now sees.
        let afterwards = LocalAPI(store: store, deviceID: Self.deviceID)
        await #expect(throws: APIError.forbidden, "the signed-out phone moved its account's tree") {
            _ = try await afterwards.correctLocation(
                treeID: tree.id,
                to: ProximityDedupeTests.diagonal(from: Self.offshore, meters: 30),
                placement: .gps,
                locationAccuracyM: nil
            )
        }
        // And the account can.
        let moved = try await account.correctLocation(
            treeID: tree.id,
            to: ProximityDedupeTests.diagonal(from: Self.offshore, meters: 30),
            placement: .gps,
            locationAccuracyM: nil
        )
        #expect(moved.coordinate != Self.offshore)
        let queued = try #require(try await Self.corrections(store).first)
        guard case let .locationCorrection(correction) = try OutboxPayload.decode(
            kind: queued.item.kind, from: queued.item.payload
        ) else {
            Issue.record("the queued row did not decode as a location correction")
            return
        }
        #expect(correction.attribution.userID == Self.userID)
    }

    @Test("a cached tree is forbidden, an unknown id is not found, and a withdrawn tree is not found")
    func theOtherRefusals() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let destination = ProximityDedupeTests.diagonal(from: Self.offshore, meters: 300)

        // Somebody else's published tree, as the service sent it.
        let cached = Tree(source: .community, coordinate: Self.offshore)
        let page = try await store.queue.write { connection in
            try CommunityTreeCacheStore().apply(
                tile: "t", trees: [cached], withdrawnTreeIDs: [], nextCursor: "c",
                at: Date(), connection: connection
            )
        }
        #expect(page.stored == 1, "fixture: the cached tree was not stored")
        await #expect(throws: APIError.forbidden, "somebody else's cached tree was moved") {
            _ = try await api.correctLocation(
                treeID: cached.id, to: destination, placement: .gps, locationAccuracyM: nil
            )
        }

        await #expect(throws: APIError.notFound) {
            _ = try await api.correctLocation(
                treeID: UUID(), to: destination, placement: .gps, locationAccuracyM: nil
            )
        }

        let withdrawn = try await Self.add(api, at: ProximityDedupeTests.diagonal(from: Self.offshore, meters: -300))
        _ = try await store.queue.write { connection in
            try CommunityTreeStore().withdraw(treeID: withdrawn.id, at: Date(), connection: connection)
        }
        await #expect(throws: APIError.notFound, "a withdrawn tree was moved") {
            _ = try await api.correctLocation(
                treeID: withdrawn.id, to: destination, placement: .gps, locationAccuracyM: nil
            )
        }
        #expect(try await Self.corrections(store).isEmpty)
    }

    /// Red-proof: `-90.0...90.0` widened to `-91.0...91.0` goes red on the 91° case only; the NaN
    /// case goes red if `!(accuracy >= 0)` is rewritten as `accuracy < 0`.
    @Test("a position off the map or an accuracy that is not a distance is refused")
    func invalidPositionsAreRefused() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let tree = try await Self.add(api)
        let near = ProximityDedupeTests.diagonal(from: Self.offshore, meters: 30)

        for (coordinate, accuracy) in [
            (Coordinate(latitude: 91, longitude: near.longitude), nil),
            (Coordinate(latitude: near.latitude, longitude: -181), nil),
            (near, -1.0),
            (near, Double.nan)
        ] as [(Coordinate, Double?)] {
            await #expect(throws: APIError.validationFailed, "\(coordinate) ± \(String(describing: accuracy)) was accepted") {
                _ = try await api.correctLocation(
                    treeID: tree.id, to: coordinate, placement: .gps, locationAccuracyM: accuracy
                )
            }
        }
        #expect(try await Self.corrections(store).isEmpty)
    }

    // MARK: - 3. The dedupe

    /// Red-proof: remove `.filter { $0.tree.id != treeID }` from `correctLocation` — red on the first
    /// move, with a `ProximityConflict` naming the tree itself.
    @Test("a move within 10 m of another tree is a conflict, cached trees included, and a tree is not its own neighbor")
    func theMoveRunsTheDedupe() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let tree = try await Self.add(api)
        let neighbor = try await Self.add(api, at: ProximityDedupeTests.diagonal(from: Self.offshore, meters: 60))
        let cachedSpot = ProximityDedupeTests.diagonal(from: Self.offshore, meters: -60)
        let cached = Tree(source: .community, coordinate: cachedSpot)
        _ = try await store.queue.write { connection in
            try CommunityTreeCacheStore().apply(
                tile: "t", trees: [cached], withdrawnTreeIDs: [], nextCursor: "c",
                at: Date(), connection: connection
            )
        }

        // Three meters from where it stands: inside 10 m of nothing but itself.
        let nudged = try await api.correctLocation(
            treeID: tree.id,
            to: ProximityDedupeTests.diagonal(from: Self.offshore, meters: 3),
            placement: .contributorPlaced,
            locationAccuracyM: nil
        )
        #expect(nudged.coordinate != Self.offshore)

        for (target, expected) in [
            (ProximityDedupeTests.diagonal(from: neighbor.coordinate, meters: 5), neighbor.id),
            (ProximityDedupeTests.diagonal(from: cachedSpot, meters: 5), cached.id)
        ] {
            do {
                _ = try await api.correctLocation(
                    treeID: tree.id, to: target, placement: .contributorPlaced, locationAccuracyM: nil
                )
                Issue.record("a move 5 m from \(expected) was accepted")
            } catch let conflict as ProximityConflict {
                #expect(conflict.candidates.map(\.tree.id) == [expected], "\(conflict.candidates.map(\.tree.id))")
            }
        }
        #expect(try await Self.corrections(store).count == 1, "a refused move was queued")
        #expect(try await Self.chain(store, tree.id).count == 2)
    }

    // MARK: - The transaction

    /// **The control is load-bearing**, for `CommunityOutboxKindTests.aFailedEnqueueRollsTheMutationBack`'s
    /// reason: the same move runs first with the queue healthy and is asserted to land.
    @Test("an enqueue that fails rolls the move back with it")
    func aFailedEnqueueRollsTheMoveBack() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let control = try await Self.add(api)
        let subject = try await Self.add(api, at: ProximityDedupeTests.diagonal(from: Self.offshore, meters: 200))

        let controlTarget = ProximityDedupeTests.diagonal(from: control.coordinate, meters: 30)
        _ = try await api.correctLocation(
            treeID: control.id, to: controlTarget, placement: .gps, locationAccuracyM: nil
        )
        #expect(try await Self.chain(store, control.id).count == 2, "fixture: the healthy move did not land")

        let refusal = "the queue refused this location correction"
        try await store.queue.write { connection in
            try connection.execute("""
                CREATE TRIGGER cypress_test_refuse_outbox BEFORE INSERT ON outbox
                BEGIN SELECT RAISE(ABORT, '\(refusal)'); END;
                """)
        }

        var thrown: (any Error)?
        do {
            _ = try await api.correctLocation(
                treeID: subject.id,
                to: ProximityDedupeTests.diagonal(from: subject.coordinate, meters: 30),
                placement: .gps,
                locationAccuracyM: nil
            )
        } catch {
            thrown = error
        }
        let sqlite = try #require(thrown as? SQLiteError, "the move did not fail at the enqueue: \(String(describing: thrown))")
        #expect(sqlite.message.contains(refusal), "something else refused: \(sqlite.message)")

        let chain = try await Self.chain(store, subject.id)
        #expect(chain.count == 1, "\(chain.count) positions survived an enqueue that failed")
        #expect(chain.first?.isCurrent == true, "the root was left stamped by a move that rolled back")
        #expect(try await Self.profileCoordinate(api, subject.id) == subject.coordinate)
    }
}
