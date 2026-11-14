import Foundation
import Testing
@testable import Cypress

/// **Every row whose effect on the service needs its tree waits for that tree's add, and the wait
/// does not count toward its 48 h window** (ROADMAP 115 and 116).
///
/// #209 held a pin move behind its tree's `add_tree`. A species claim or correction that arrives
/// before its tree is recorded by the service and never applied to the tree
/// (`store.materializeSpecies`), so those two wait too (`OutboxItem.Kind.waitsForItsTreeAdd`).
/// And a held row is never in a pass, so nothing banked its wait: an add in backoff for 47 h
/// released its row with about 1 h of its window left (`OutboxStore.creditHeldBehindAdd`).
@Suite("Outbox · rows about a tree wait for its add, and the wait is not counted")
struct TreeAddHoldTests {

    private typealias Fixture = LocationCorrectionTests

    /// A clock the test moves.
    private final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var value = Date(timeIntervalSince1970: 1_796_000_000)
        var now: Date { lock.withLock { value } }
        func advance(by seconds: TimeInterval) { lock.withLock { value.addTimeInterval(seconds) } }
    }

    /// The service: refuses adds with a retryable error until told to accept them, can refuse one
    /// other kind once with a retryable error, and records the order it was offered every item.
    private actor Service: OutboxSendSink {
        private(set) var offered: [OutboxItem.Kind] = []
        private var acceptsAdds = false
        private var failOnce: OutboxItem.Kind?

        func acceptAdds() { acceptsAdds = true }
        func failNext(_ kind: OutboxItem.Kind) { failOnce = kind }

        func sync(_ items: [OutboxItem]) async throws -> [SyncResult] {
            offered.append(contentsOf: items.map(\.kind))
            return items.map { item in
                if item.kind == .addTree && !acceptsAdds {
                    return SyncResult(clientUUID: item.clientUUID, status: .failed, error: .serverError)
                }
                if item.kind == failOnce {
                    failOnce = nil
                    return SyncResult(clientUUID: item.clientUUID, status: .failed, error: .serverError)
                }
                return SyncResult(clientUUID: item.clientUUID, status: .applied)
            }
        }

        func uploadPhoto(_ photo: OutboxStore.PhotoRow, for item: OutboxItem) async throws {}
    }

    /// Queues one row of `kind` about `tree`, the way `LocalAPI` queues it: born applied.
    private static func queue(
        _ kind: OutboxItem.Kind,
        about tree: Tree,
        api: LocalAPI,
        store: CypressStore,
        at moment: Date
    ) async throws {
        let statement = SpeciesStatement(
            clientUUID: UUID(), treeID: tree.id, speciesID: UUID(),
            attribution: .anonymous(deviceID: Fixture.deviceID), occurredAt: moment
        )
        let payload: OutboxPayload
        switch kind {
        case .locationCorrection:
            _ = try await api.correctLocation(
                treeID: tree.id,
                to: VisitPinAdjust.offset(tree.coordinate, northM: 10, eastM: 0),
                placement: .contributorPlaced,
                locationAccuracyM: nil
            )
            return
        case .speciesClaim: payload = .speciesClaim(statement)
        case .speciesCorrection: payload = .speciesCorrection(statement)
        default:
            Issue.record("this test does not queue \(kind)")
            return
        }
        let item = try payload.makeItem(createdAt: moment)
        try await store.queue.write { try OutboxStore().enqueueLocallyApplied(item, connection: $0) }
    }

    private static func row(_ kind: OutboxItem.Kind, _ store: CypressStore) async throws -> OutboxStore.Record {
        try #require(
            try await store.queue.read { try OutboxStore().allItems(connection: $0) }
                .first { $0.item.kind == kind }
        )
    }

    /// The kinds that now wait. `locationCorrection` is #209's; the other two are new.
    static let heldKinds: [OutboxItem.Kind] = [.speciesClaim, .speciesCorrection, .locationCorrection]

    /// ROADMAP 115. Red on today's code for the two species kinds: the first drain offers
    /// `[addTree, speciesClaim]`, and the test goes red on "a species claim was offered while its
    /// tree's add had not reached the service".
    @Test("a row about a tree is not sent while the tree's add is unsent, and is sent right after it",
          arguments: heldKinds)
    func aRowWaitsForItsTree(_ kind: OutboxItem.Kind) async throws {
        let store = try await CypressStore.inMemory()
        let clock = Clock()
        let api = LocalAPI(store: store, deviceID: Fixture.deviceID, now: { clock.now })
        let service = Service()
        let queue = OutboxQueue(
            queue: store.queue, apply: APIOutboxTransport(api: api), send: service, now: { clock.now }
        )

        let tree = try await Fixture.add(api)
        try await Self.queue(kind, about: tree, api: api, store: store, at: clock.now)

        _ = try await queue.drain()
        clock.advance(by: 60)
        _ = try await queue.drain()
        let whileUnsent = await service.offered
        #expect(whileUnsent.contains(.addTree), "fixture: the add was never offered")
        #expect(
            !whileUnsent.contains(kind),
            "a \(kind.rawValue) was offered while its tree's add had not reached the service: \(whileUnsent)"
        )

        await service.acceptAdds()
        clock.advance(by: 2 * 60 * 60)
        _ = try await queue.drain()
        let afterwards = Array(await service.offered.dropFirst(whileUnsent.count))
        #expect(
            afterwards == [.addTree, kind],
            "the \(kind.rawValue) was not sent in the drain that sent its tree, after it: \(afterwards)"
        )
        #expect(try await Self.row(kind, store).item.state == .done)
    }

    /// ROADMAP 116. The add is in backoff for 47 h, then sends. The released row's window starts
    /// at the release, so a transient failure and two more hours do not expire it.
    ///
    /// Red on today's code, differently per argument:
    /// - `locationCorrection` is held but nothing banks the held time. The window still starts at
    ///   the save, red on "the window starts 0.0 h after the save, not 47 h"; then at 49 h the row
    ///   expires, red on "the row expired: failed, Tried for 48 hours…".
    /// - `speciesClaim` and `speciesCorrection` are not held on today's code, so the first drain
    ///   sends them and they are `done` before the 47 h drain. Red on "fixture: the released row
    ///   was not tried: done" and on "the window starts 0.0 h after the save, not 47 h"; the last
    ///   check passes, because the row is already `done`. Those two go red through the missing
    ///   hold (ROADMAP 115). The credit itself (116) is proven for them only with the hold in
    ///   place and the credit broken.
    @Test("a row held 47 h behind its add has its full 48 h window after release",
          arguments: heldKinds)
    func heldTimeIsNotCounted(_ kind: OutboxItem.Kind) async throws {
        let store = try await CypressStore.inMemory()
        let clock = Clock()
        let api = LocalAPI(store: store, deviceID: Fixture.deviceID, now: { clock.now })
        let service = Service()
        let queue = OutboxQueue(
            queue: store.queue, apply: APIOutboxTransport(api: api), send: service, now: { clock.now }
        )
        let saved = clock.now

        let tree = try await Fixture.add(api)
        try await Self.queue(kind, about: tree, api: api, store: store, at: saved)
        _ = try await queue.drain()

        // 47 h later the service takes the add, and refuses the released row once.
        clock.advance(by: 47 * 60 * 60)
        await service.acceptAdds()
        await service.failNext(kind)
        _ = try await queue.drain()
        let released = try await Self.row(kind, store)
        #expect(released.item.failCount == 1, "fixture: the released row was not tried: \(released.item.state)")
        let hours = released.windowStartedAt.timeIntervalSince(saved) / 3600
        #expect(
            released.windowStartedAt == saved.addingTimeInterval(47 * 60 * 60),
            "the window starts \(hours) h after the save, not 47 h"
        )

        // Two hours on, 49 h after the save: the row still has its window and goes.
        clock.advance(by: 2 * 60 * 60)
        _ = try await queue.drain()
        let settled = try await Self.row(kind, store)
        #expect(
            settled.item.state == .done,
            "the row expired: \(settled.item.state), \(settled.item.lastError ?? "no reason")"
        )
    }

    /// The hold credits only a held row: a row not about an unsent tree keeps its window.
    ///
    /// Red-proof: make `creditHeldBehindAdd` select every pending row — red on "a row that was not
    /// held was credited" (the count). The window line stays green under that break, because
    /// `creditHold` checks the hold again for each row and moves no window for a row that is not
    /// held.
    @Test("a row that is not held keeps the window it was saved with")
    func anUnheldRowKeepsItsWindow() async throws {
        let store = try await CypressStore.inMemory()
        let clock = Clock()
        let api = LocalAPI(store: store, deviceID: Fixture.deviceID, now: { clock.now })
        let saved = clock.now
        let tree = try await Fixture.add(api)
        try await Self.queue(.speciesClaim, about: tree, api: api, store: store, at: saved)
        // The add has reached the service, so nothing holds the claim.
        try await store.queue.write { try $0.execute("UPDATE outbox SET remote_sent = 1 WHERE kind = 'add_tree'") }

        clock.advance(by: 5 * 60 * 60)
        let credited = try await store.queue.write {
            try OutboxStore().creditHeldBehindAdd(at: clock.now, connection: $0)
        }
        #expect(credited == 0, "a row that was not held was credited")
        let claim = try await Self.row(.speciesClaim, store)
        #expect(claim.windowStartedAt == saved, "a row that was never held had its window moved")
    }
}
