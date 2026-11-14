import Foundation
import Testing
@testable import Cypress

/// **Move pin is not offered on a tree the service never received** (ROADMAP 107).
///
/// A tree added before the sync path existed (R77) was never queued. Migration v23 gives it this
/// installation's owner as its adder, so the adder test alone offered Move pin, and the service
/// answered the move with a terminal `not_found`. The rule: offer the move only when the tree's
/// `add_tree` row is still in the outbox, or the tree was added on or after
/// `CommunityTreeStore.firstQueuedAddsAt`. One test per branch.
@Suite("Community trees · Move pin is offered only for a tree the service may hold")
struct MovePinOfferTests {

    private typealias Fixture = LocationCorrectionTests

    /// Adds a tree as `LocalAPI` would at `moment`, and returns the API and the tree.
    private static func addTree(at moment: Date) async throws -> (CypressStore, LocalAPI, Tree) {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Fixture.deviceID, now: { moment })
        let tree = try await Fixture.add(api)
        return (store, api, tree)
    }

    /// Deletes the tree's `add_tree` row, as `pruneCompleted` does a day after it is `done`.
    private static func pruneAddRow(_ store: CypressStore) async throws {
        try await store.queue.write { connection in
            try connection.execute("DELETE FROM outbox WHERE kind = 'add_tree'")
        }
    }

    private static let beforeQueuing = CommunityTreeStore.firstQueuedAddsAt.addingTimeInterval(-30 * 24 * 60 * 60)

    /// Branch 1: the add row is still queued, so the tree was queued whatever its date says.
    ///
    /// Red-proof: drop the `addRowQueued ||` arm of `CommunityTreeStore.mayHaveReachedService` —
    /// red on "a tree whose add row is still queued is not offered Move pin".
    @Test("a tree whose add row is still in the outbox is offered Move pin, even with an old date")
    func aQueuedAddIsOffered() async throws {
        let (store, api, tree) = try await Self.addTree(at: Self.beforeQueuing)
        let queued = try await store.queue.read { try OutboxStore().allItems(connection: $0) }
        #expect(queued.contains { $0.item.kind == .addTree }, "fixture: the add was not queued")

        let profile = try await api.treeProfile(id: tree.id)
        #expect(profile.canMovePin, "a tree whose add row is still queued is not offered Move pin")
    }

    /// Branch 2: added on the first queuing build's date, add row pruned. The service has it.
    ///
    /// Red-proof: make the date arm `createdAt > firstQueuedAddsAt` — red on "a tree added on the
    /// first day adds were queued is not offered Move pin" (the boundary is "on or after").
    @Test("a tree added on or after the first queuing build is offered Move pin with no add row")
    func aTreeAddedAfterQueuingIsOffered() async throws {
        let (store, api, tree) = try await Self.addTree(at: CommunityTreeStore.firstQueuedAddsAt)
        try await Self.pruneAddRow(store)

        let profile = try await api.treeProfile(id: tree.id)
        #expect(profile.canMovePin, "a tree added on the first day adds were queued is not offered Move pin")
    }

    /// Branch 3: added before any build queued adds, and no add row. This is the R77 tree.
    ///
    /// Red on today's code: the adder test alone offers the move, and the test goes red on
    /// "a tree the service never received is offered Move pin".
    @Test("a tree added before adds were queued, with no add row, is not offered Move pin")
    func anUnqueuedOldTreeIsNotOffered() async throws {
        let (store, api, tree) = try await Self.addTree(at: Self.beforeQueuing)
        try await Self.pruneAddRow(store)

        let adder = try await Fixture.adder(store, tree.id)
        #expect(adder == .device(Fixture.deviceID), "fixture: the reader is not the adder: \(String(describing: adder))")
        let profile = try await api.treeProfile(id: tree.id)
        #expect(!profile.canMovePin, "a tree the service never received is offered Move pin")
    }
}
