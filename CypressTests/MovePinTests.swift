import Foundation
import Testing
@testable import Cypress

/// The owner's Move pin control of 2026-11-12, below the screen: what the profile offers, and what
/// one Save does.
///
/// 1. **The profile offers Move pin only to the tree's adder** (`TreeProfile.canMovePin`): yes for
///    a tree this reader added, no for another installation's tree, no for a cached tree from the
///    service, and no for a pre-v23-style tree whose adder is nobody.
/// 2. **Save moves the tree everywhere it is read** (the profile, the shortlist, the map) and queues
///    one `location_correction`, placed by hand.
/// 3. **A refusal is said, not swallowed**: a spot within 10 m of another tree keeps the pin where it
///    was, writes nothing and queues nothing, and the screen says why.
///
/// `LocationCorrectionTests` covers the verb itself; this covers the control built on it.
@MainActor
@Suite("Community trees · Move pin")
struct MovePinTests {

    private typealias Fixture = LocationCorrectionTests

    // MARK: - 1. Who is offered the control

    /// Red-proof: make `LocalAPI.treeProfile` pass `canMovePin: addedHere` (dropping the adder
    /// test) — red on "another installation's tree offers Move pin".
    @Test("the profile offers Move pin for a tree the reader added, and for nobody else's")
    func onlyTheAdderIsOffered() async throws {
        let store = try await CypressStore.inMemory()
        let mine = LocalAPI(store: store, deviceID: Fixture.deviceID)
        let tree = try await Fixture.add(mine)

        let ownProfile = try await mine.treeProfile(id: tree.id)
        #expect(ownProfile.canMovePin, "the adder's own profile does not offer Move pin")
        #expect(TreeProfilePresentation(profile: ownProfile).offersMovePin)

        let somebodyElse = LocalAPI(store: store, deviceID: Fixture.otherDeviceID)
        let theirView = try await somebodyElse.treeProfile(id: tree.id)
        #expect(!theirView.canMovePin, "another installation's tree offers Move pin")

        // An adder of nobody: what an account deletion leaves, and what the first draft of v23 gave
        // every pre-v23 tree.
        try await store.queue.write { connection in
            try connection.execute("UPDATE community_trees SET user_id = NULL, device_id = NULL")
        }
        let anonymized = try await mine.treeProfile(id: tree.id)
        #expect(!anonymized.canMovePin, "a tree whose adder is nobody offers Move pin")
    }

    @Test("a cached tree from the service offers no Move pin")
    func aCachedTreeIsNotOffered() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Fixture.deviceID)
        let cached = UUID()
        let stamp = SQLiteTimestamp.string(from: Date())
        try await store.queue.write { connection in
            try connection.execute("""
                INSERT INTO community_tree_cache
                    (id, lat, lon, placement, status, verification_state, created_at, updated_at,
                     tile, fetched_at)
                VALUES ('\(cached.uuidString.lowercased())', 37.7601, -122.5401, 'gps', 'alive',
                        'unverified', '\(stamp)', '\(stamp)', 't', '\(stamp)');
                """)
        }
        let profile = try await api.treeProfile(id: cached)
        #expect(profile.tree.id == cached, "fixture: the cached tree did not load")
        #expect(!profile.canMovePin, "somebody else's cached tree offers Move pin")
    }

    // MARK: - 2. Save

    /// Red-proofs, each read by its message: make `MovePinModel.save` skip the `correctLocation`
    /// call (set `didSave` alone) — red on "the profile still shows the old position"; make
    /// `LocalAPI.correctLocation` skip `queueAppliedMutation` — red on "queued 0 corrections".
    @Test("Save moves the tree on the profile, the shortlist and the map, and queues one correction")
    func saveMovesTheTreeAndQueuesTheCorrection() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Fixture.deviceID)
        let tree = try await Fixture.add(api)

        let model = MovePinModel(treeID: tree.id, original: tree.coordinate, api: api)
        #expect(!model.canSave, "Save is offered before the pin moved")
        model.pin = VisitPinAdjust.offset(tree.coordinate, northM: 10, eastM: 0)
        #expect(model.presentation.placement == "10 m north of where it was.")
        #expect(model.canSave)
        let destination = model.pin

        await model.save()
        #expect(model.failure == nil, "the save was refused: \(model.failure ?? "")")
        #expect(model.didSave)

        let profile = try await api.treeProfile(id: tree.id)
        #expect(profile.tree.coordinate == destination, "the profile still shows the old position: \(profile.tree.coordinate)")
        #expect(profile.tree.placement == .contributorPlaced, "a hand-placed move is recorded as \(profile.tree.placement)")
        #expect(profile.canMovePin, "the adder lost the control after one move")

        let near = try await api.treesNear(destination, radiusM: 2, limit: 5)
        #expect(near.map(\.tree.id) == [tree.id], "the shortlist does not find the tree where it now is")

        let viewport = MapViewport(
            bounds: BoundingBox(around: destination, radiusM: 3), zoom: 18, pinLimit: 50
        )
        guard case let .pins(answer) = try await api.mapContent(in: viewport) else {
            Issue.record("a 6 m viewport answered with clusters")
            return
        }
        #expect(answer.items.map(\.id).contains(tree.id), "the map does not draw the tree where it now is")
        #expect(answer.items.first { $0.id == tree.id }?.coordinate == destination)

        let queued = try await Fixture.corrections(store)
        #expect(queued.count == 1, "the move queued \(queued.count) corrections")
        let record = try #require(queued.first)
        guard case let .locationCorrection(correction) = try OutboxPayload.decode(
            kind: record.item.kind, from: record.item.payload
        ) else {
            Issue.record("the queued item is not a location correction")
            return
        }
        #expect(correction.treeID == tree.id)
        #expect(correction.coordinate == destination)
        #expect(correction.placement == .contributorPlaced)
        #expect(correction.locationAccuracyM == nil, "a hand-placed pin claims an accuracy")
    }

    // MARK: - 3. A refusal

    /// Red-proof: make `MovePinModel.save` ignore a `ProximityConflict` (catch it and set
    /// `didSave`) — red on "a refused move closed the screen".
    @Test("a spot within 10 m of another tree is refused out loud, and nothing moves")
    func aSpotTooCloseIsRefused() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Fixture.deviceID)
        let tree = try await Fixture.add(api)
        let neighborSpot = VisitPinAdjust.offset(tree.coordinate, northM: 30, eastM: 0)
        _ = try await Fixture.add(api, at: neighborSpot)

        let model = MovePinModel(treeID: tree.id, original: tree.coordinate, api: api)
        model.pin = VisitPinAdjust.offset(neighborSpot, northM: -4, eastM: 0)
        await model.save()

        #expect(!model.didSave, "a refused move closed the screen")
        #expect(model.failure == MovePinCopy.tooClose, "the refusal said: \(model.failure ?? "nothing")")
        let profile = try await api.treeProfile(id: tree.id)
        #expect(profile.tree.coordinate == tree.coordinate, "a refused move moved the tree")
        #expect(try await Fixture.corrections(store).isEmpty, "a refused move was queued")
    }
}
