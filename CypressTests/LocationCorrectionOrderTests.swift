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

    /// A failed add holds nothing. It will not be sent again unless the volunteer retries it, so a
    /// move held behind it would stay pending forever with no reason shown (review of #209's
    /// merge with F35).
    ///
    /// Fails if the hold matched any add that is not `done`: the move is held behind the failed
    /// add, and the test goes red on "a move was held behind a failed add".
    @Test("a failed add releases its tree's move")
    func aFailedAddHoldsNothing() async throws {
        let store = try await CypressStore.inMemory()
        let clock = Clock()
        let api = LocalAPI(store: store, deviceID: Fixture.deviceID, now: { clock.now })

        let tree = try await Fixture.add(api)
        _ = try await api.correctLocation(
            treeID: tree.id,
            to: VisitPinAdjust.offset(tree.coordinate, northM: 10, eastM: 0),
            placement: .contributorPlaced,
            locationAccuracyM: nil
        )
        let heldWhilePending = try await store.queue.read {
            try OutboxStore().dueItems(now: clock.now, limit: 50, connection: $0)
        }
        #expect(
            !heldWhilePending.contains { $0.item.kind == .locationCorrection },
            "control: the move was not held while its add was pending"
        )

        // The add gives up, as the 48 h cap or a terminal refusal would leave it.
        try await store.queue.write {
            try $0.execute("UPDATE outbox SET state = 'failed' WHERE kind = 'add_tree'")
        }
        let due = try await store.queue.read {
            try OutboxStore().dueItems(now: clock.now, limit: 50, connection: $0)
        }
        #expect(
            due.contains { $0.item.kind == .locationCorrection },
            "a move was held behind a failed add"
        )
    }

    /// A drain asked for while another runs still sends a move its pass released (review of #209's
    /// merge with F35).
    ///
    /// The running drain's first pass sends one tree. While it sends, a second tree and its move
    /// are saved, and their drain is folded into the running one. The drain-again pass sends the
    /// second tree's add, which releases the move. Fails if the drain-again pass makes no extra
    /// pass: the move waits for some later drain, and the test goes red on "the released move was
    /// not sent by the drain that released it".
    @Test("a drain asked for mid-drain sends the move its pass released")
    func aDrainAskedForMidDrainReleasesMoves() async throws {
        let store = try await CypressStore.inMemory()
        let clock = Clock()
        let api = LocalAPI(store: store, deviceID: Fixture.deviceID, now: { clock.now })
        let service = MidDrainService()
        let queue = OutboxQueue(
            queue: store.queue, apply: APIOutboxTransport(api: api), send: service, now: { clock.now }
        )

        let first = try await Fixture.add(api)
        let secondSpot = VisitPinAdjust.offset(first.coordinate, northM: 100, eastM: 0)
        await service.onFirstSync {
            let second = try await Fixture.add(api, at: secondSpot)
            _ = try await api.correctLocation(
                treeID: second.id,
                to: VisitPinAdjust.offset(second.coordinate, northM: 10, eastM: 0),
                placement: .contributorPlaced,
                locationAccuracyM: nil
            )
            // The running drain is busy, so this one is folded into it.
            _ = try await queue.drain()
        }

        _ = try await queue.drain()
        let offered = await service.offered
        #expect(
            offered == [.addTree, .addTree, .locationCorrection],
            "the released move was not sent by the drain that released it: \(offered)"
        )
        #expect(await service.hookRan, "fixture: nothing was saved while the first drain ran")
    }

    /// Accepts everything, and runs a hook once, during its first `sync`.
    private actor MidDrainService: OutboxSendSink {
        private(set) var offered: [OutboxItem.Kind] = []
        private(set) var hookRan = false
        private var hook: (@Sendable () async throws -> Void)?

        func onFirstSync(_ hook: @escaping @Sendable () async throws -> Void) { self.hook = hook }

        func sync(_ items: [OutboxItem]) async throws -> [SyncResult] {
            offered.append(contentsOf: items.map(\.kind))
            if let hook {
                self.hook = nil
                try await hook()
                hookRan = true
            }
            return items.map { SyncResult(clientUUID: $0.clientUUID, status: .applied) }
        }

        func uploadPhoto(_ photo: OutboxStore.PhotoRow, for item: OutboxItem) async throws {}
    }
}
