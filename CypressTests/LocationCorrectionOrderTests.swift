import Foundation
import Testing
@testable import Cypress

/// **A pin move never reaches the service before its tree** (review of #209, F2).
///
/// "Add a tree offline, then fix its pin" queues an `add_tree` and then a `location_correction`
/// for the same tree. The queue sends due items oldest first, but only among items that are due, so
/// an add in backoff used to let the move go first. The service answers a move for a tree it has
/// not received with `not_found`, which is terminal: the move was lost on the service while the
/// phone kept it.
///
/// 1. While the tree's add has not reached the service, the move is not offered to the send sink,
///    in the drain that fails the add and in every drain while the add is in backoff.
/// 2. The drain that finally sends the add sends the move in the same call, after it.
@Suite("Community trees · a move waits for its tree's add")
struct LocationCorrectionOrderTests {

    private typealias Fixture = LocationCorrectionTests

    /// A clock the test moves, so a backoff can be waited out without waiting.
    private final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var value = Date(timeIntervalSince1970: 1_796_000_000)
        var now: Date { lock.withLock { value } }
        func advance(by seconds: TimeInterval) { lock.withLock { value.addTimeInterval(seconds) } }
    }

    /// The service: refuses the add with a retryable error until told to accept, and records the
    /// order in which it was offered every item.
    private actor Service: OutboxSendSink {
        private(set) var offered: [OutboxItem.Kind] = []
        private var acceptsAdds = false

        func acceptAdds() { acceptsAdds = true }

        func sync(_ items: [OutboxItem]) async throws -> [SyncResult] {
            offered.append(contentsOf: items.map(\.kind))
            return items.map { item in
                item.kind == .addTree && !acceptsAdds
                    ? SyncResult(clientUUID: item.clientUUID, status: .failed, error: .serverError)
                    : SyncResult(clientUUID: item.clientUUID, status: .applied)
            }
        }

        func uploadPhoto(_ photo: OutboxStore.PhotoRow, for item: OutboxItem) async throws {}
    }

    /// Fails with the defect present: without the hold in `OutboxStore.dueItems`, the first drain's
    /// batch holds both rows, the service is offered `[addTree, locationCorrection]`, and the test
    /// goes red on "the move was offered while its tree's add had not reached the service". The
    /// second drain, with the add in backoff, offers the move alone, which is the order the
    /// service turns into a terminal `not_found`.
    ///
    /// The second half fails without `drain`'s extra pass: the move is still held when the add's
    /// pass reads its batch, so the call that sends the add sends nothing else, and the test goes
    /// red on "the move was not sent in the drain that sent its tree".
    @Test("a move is held while its tree's add is in backoff, and sent right after the add")
    func aMoveWaitsForItsTree() async throws {
        let store = try await CypressStore.inMemory()
        let clock = Clock()
        let api = LocalAPI(store: store, deviceID: Fixture.deviceID, now: { clock.now })
        let service = Service()
        let queue = OutboxQueue(
            queue: store.queue, apply: APIOutboxTransport(api: api), send: service, now: { clock.now }
        )

        // Offline: the tree and its move are both queued before anything is sent.
        let tree = try await Fixture.add(api)
        _ = try await api.correctLocation(
            treeID: tree.id,
            to: VisitPinAdjust.offset(tree.coordinate, northM: 10, eastM: 0),
            placement: .contributorPlaced,
            locationAccuracyM: nil
        )

        // Back online, and the service refuses the add for now.
        _ = try await queue.drain()
        clock.advance(by: 1)
        _ = try await queue.drain()
        let whileInBackoff = await service.offered
        #expect(whileInBackoff.contains(.addTree), "fixture: the add was never offered")
        #expect(
            !whileInBackoff.contains(.locationCorrection),
            "the move was offered while its tree's add had not reached the service: \(whileInBackoff)"
        )

        // The backoff passes and the service takes the add.
        await service.acceptAdds()
        clock.advance(by: 6 * 60 * 60)
        let report = try await queue.drain()
        let all = await service.offered
        let afterBackoff = Array(all.dropFirst(whileInBackoff.count))
        #expect(
            afterBackoff == [.addTree, .locationCorrection],
            "the move was not sent in the drain that sent its tree, after it: \(afterBackoff)"
        )
        #expect(report.sent == 2, "the drain reports \(report.sent) sent")

        let rows = try await store.queue.read { try OutboxStore().allItems(connection: $0) }
        #expect(rows.allSatisfy { $0.item.state == .done }, "an item is still waiting: \(rows.map(\.item.state))")
    }

    /// The hold is about one tree: another tree's add in backoff does not hold this tree's move.
    ///
    /// Fails if the hold matched any unsent add rather than the move's own tree: the move would be
    /// held, and the test goes red on "a move was held by another tree's add".
    @Test("another tree's add in backoff does not hold this tree's move")
    func anotherTreesAddHoldsNothing() async throws {
        let store = try await CypressStore.inMemory()
        let clock = Clock()
        let api = LocalAPI(store: store, deviceID: Fixture.deviceID, now: { clock.now })
        let service = Service()
        let queue = OutboxQueue(
            queue: store.queue, apply: APIOutboxTransport(api: api), send: service, now: { clock.now }
        )

        // This tree's add reaches the service first.
        let tree = try await Fixture.add(api)
        await service.acceptAdds()
        _ = try await queue.drain()

        // A second tree, 100 m away, whose add the service now refuses; then this tree's move.
        let neighbor = VisitPinAdjust.offset(tree.coordinate, northM: 100, eastM: 0)
        _ = try await Fixture.add(api, at: neighbor)
        _ = try await api.correctLocation(
            treeID: tree.id,
            to: VisitPinAdjust.offset(tree.coordinate, northM: -10, eastM: 0),
            placement: .contributorPlaced,
            locationAccuracyM: nil
        )
        let due = try await store.queue.read {
            try OutboxStore().dueItems(now: clock.now, limit: 50, connection: $0)
        }
        #expect(
            due.contains { $0.item.kind == .locationCorrection },
            "a move was held by another tree's add"
        )
    }
}
