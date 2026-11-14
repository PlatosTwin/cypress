import Foundation
import Testing
@testable import Cypress

/// Screen 17's header pill and its `· offline` clause (ROADMAP 110, ERRATA E81 and E???).
///
/// E81 dropped the mock's `3 waiting · offline` to `3 waiting` because nothing in the app knew
/// whether it was offline. `NetworkPathSource` now says whether any path is satisfied, and the pill
/// draws the clause only from that reading. Each test drives the real chain: a real `OutboxQueue`
/// with waiting rows, a real `OutboxViewState` following a fake path, and the presentation the
/// screen draws from both.
@MainActor
@Suite("Outbox pill offline clause")
struct OutboxOfflinePillTests {

    private struct Rig {
        let state: OutboxViewState
        let path: OutboxTestSupport.ManualNetworkPath
        let follower: Task<Void, Never>

        /// What `OutboxView` hands `OutboxScreen`'s header.
        var pill: String? {
            OutboxPresentation(snapshot: state.snapshot, isOffline: state.isOffline).headerPill
        }
    }

    /// A queue with `waiting` rows that are still trying (a retryable failure inside the 48 h
    /// window), and a view state that follows `path` the way the open screen does.
    private static func rig(
        waiting: Int,
        unmetered: Bool,
        connected: Bool?
    ) async throws -> Rig {
        let clock = OutboxTestSupport.Clock()
        let store = try await CypressStore.inMemory()
        let transport = OutboxTestSupport.ScriptedTransport(script: .allFail(.serverError))
        let queue = OutboxQueue(queue: store.queue, apply: transport, now: clock.closure)
        for _ in 0..<waiting {
            _ = try await queue.enqueue(
                .measurement(TreeMeasurement.dbh(
                    treeID: UUID(),
                    attribution: OutboxTestSupport.attribution,
                    capturedAt: clock.now,
                    gpsAccuracyM: 7,
                    quantity: Quantity(value: 31, unit: .centimeters, method: .tape),
                    createdAt: clock.now,
                    updatedAt: clock.now
                ))
            )
        }
        _ = try await queue.drain()

        let path = OutboxTestSupport.ManualNetworkPath(unmetered: unmetered, connected: connected)
        let state = OutboxViewState(queue: queue, store: store, networkPath: path)
        await state.refresh()
        let follower = Task { await state.followConnection() }
        return Rig(state: state, path: path, follower: follower)
    }

    /// Waits, boundedly, for the follower to catch up with a reading.
    private static func settle(_ condition: () -> Bool) async {
        for _ in 0..<300 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("waiting rows and no satisfied path draw the mock's pill: `1 waiting · offline`")
    func offlineDrawsTheClause() async throws {
        let rig = try await Self.rig(waiting: 1, unmetered: false, connected: false)
        defer { rig.follower.cancel() }
        #expect(rig.state.snapshot.waitingCount == 1)

        await Self.settle { rig.state.isOffline }
        #expect(rig.state.isOffline)
        #expect(rig.pill == "1 waiting · offline")
    }

    /// The second argument is a phone on cellular. The wi-fi toggle holds its photographs back, and
    /// the phone is still connected, so it is not offline.
    @Test(
        "a satisfied path draws `N waiting` with no clause, on wi-fi or on cellular",
        arguments: [true, false]
    )
    func connectedDrawsNoClause(unmetered: Bool) async throws {
        let rig = try await Self.rig(waiting: 2, unmetered: unmetered, connected: true)
        defer { rig.follower.cancel() }

        // Prove the follower is live before reading the answer, so the answer is not only the
        // initial `false`: a change to offline is heard, and the change back is heard too.
        rig.path.set(connected: false)
        await Self.settle { rig.state.isOffline }
        #expect(rig.state.isOffline)
        rig.path.set(connected: true)
        await Self.settle { !rig.state.isOffline }

        #expect(rig.pill == "2 waiting")
    }

    @Test("before the first reading the pill says `N waiting`, and offline only once a reading says so")
    func noReadingNeverClaimsOffline() async throws {
        let rig = try await Self.rig(waiting: 1, unmetered: false, connected: nil)
        defer { rig.follower.cancel() }
        #expect(rig.path.connectedNow() == nil)

        for _ in 0..<20 { await Task.yield() }
        #expect(rig.pill == "1 waiting")

        // The first reading arrives, and it is what turns the clause on.
        rig.path.set(connected: false)
        await Self.settle { rig.state.isOffline }
        #expect(rig.pill == "1 waiting · offline")
    }

    @Test("zero waiting draws no pill, offline or not")
    func zeroWaitingDrawsNoPill() async throws {
        let rig = try await Self.rig(waiting: 0, unmetered: false, connected: false)
        defer { rig.follower.cancel() }

        await Self.settle { rig.state.isOffline }
        #expect(rig.state.isOffline, "the reading arrived, so this is the offline case")
        #expect(rig.state.snapshot.waitingCount == 0)
        #expect(rig.pill == nil)
    }

    @Test("the clause follows the path while the screen is open")
    func pathChangeUpdatesThePill() async throws {
        let rig = try await Self.rig(waiting: 3, unmetered: true, connected: true)
        defer { rig.follower.cancel() }
        await Self.settle { rig.pill != nil }
        #expect(rig.pill == "3 waiting")

        rig.path.set(connected: false)
        await Self.settle { rig.pill == "3 waiting · offline" }
        #expect(rig.pill == "3 waiting · offline")

        rig.path.set(connected: true)
        await Self.settle { rig.pill == "3 waiting" }
        #expect(rig.pill == "3 waiting")
    }

    @Test("a pinned path with no connection reads as not connected and not unmetered")
    func pinnedOfflinePath() async {
        let offline = PinnedNetworkPath(unmetered: true, connected: false)
        #expect(offline.connectedNow() == false)
        #expect(await offline.isUnmetered() == false)
        #expect(PinnedNetworkPath(unmetered: false).connectedNow() == true)
    }

    #if DEBUG
    @Test("CYPRESS_NETWORK_PATH=offline pins a path with no connection")
    func debugOverrideOffline() async throws {
        let pinned = try #require(
            DebugNetworkPathOverride.requested(["CYPRESS_NETWORK_PATH": "offline"])
        )
        #expect(pinned.connectedNow() == false)
        #expect(await pinned.isUnmetered() == false)
    }
    #endif
}
