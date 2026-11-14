import Foundation
import Network
import Testing
@testable import Cypress

/// Screen 17's header pill and its `· offline` clause (ROADMAP 110).
///
/// ERRATA E81 dropped the mock's `3 waiting · offline` to `3 waiting` because nothing in the app
/// knew whether it was offline. `NetworkPathSource` now says whether the phone has any path, and the
/// pill draws the clause only from that reading. Most tests drive the real chain: a real
/// `OutboxQueue` with waiting rows, a real `OutboxViewState` following a fake path, and the
/// presentation the screen draws from both.
///
/// Not covered here: the two lines in `OutboxView` that pass `isOffline` and start
/// `followConnection()`. The UI suite has no way to put a waiting row in the outbox.
@MainActor
@Suite("Outbox pill offline clause")
struct OutboxOfflinePillTests {

    @MainActor
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
        // The follower subscribes and reads the current value with no suspension between, so once
        // its listener exists it has also taken the first reading.
        await settle { path.connectedListenerCount == 1 }
        return Rig(state: state, path: path, follower: follower)
    }

    /// Lets the follower run, with no clock. The follower runs on the main actor and the fake path
    /// hands each reading to its stream at once, so a fixed number of yields is enough; a count, not
    /// a wall clock, bounds the wait.
    private static func settle(_ condition: () -> Bool) async {
        for _ in 0..<1_000 {
            if condition() { return }
            await Task.yield()
        }
    }

    @Test("only an unsatisfied path is offline; requiresConnection may still connect")
    func statusMapping() {
        #expect(SystemNetworkPath.isConnected(NWPath.Status.unsatisfied) == false)
        #expect(SystemNetworkPath.isConnected(NWPath.Status.satisfied) == true)
        #expect(SystemNetworkPath.isConnected(NWPath.Status.requiresConnection) == true)
    }

    @Test("waiting rows and no path at all draw the mock's pill: `1 waiting · offline`")
    func offlineDrawsTheClause() async throws {
        let rig = try await Self.rig(waiting: 1, unmetered: false, connected: false)
        defer { rig.follower.cancel() }
        #expect(rig.state.snapshot.waitingCount == 1)

        #expect(rig.state.isOffline)
        #expect(rig.pill == "1 waiting · offline")
    }

    /// The second argument is a phone on cellular. The wi-fi toggle holds its photographs back, and
    /// the phone is still connected, so it is not offline.
    @Test(
        "a connected path draws `N waiting` with no clause, on wi-fi or on cellular",
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
        // The follower ran: it subscribed, and so it has read the missing reading too.
        #expect(rig.path.connectedListenerCount == 1)

        #expect(rig.state.isOffline == false)
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

        #expect(rig.state.isOffline, "the reading arrived, so this is the offline case")
        #expect(rig.state.snapshot.waitingCount == 0)
        #expect(rig.pill == nil)
    }

    @Test("the clause follows the path while the screen is open")
    func pathChangeUpdatesThePill() async throws {
        let rig = try await Self.rig(waiting: 3, unmetered: true, connected: true)
        defer { rig.follower.cancel() }
        #expect(rig.pill == "3 waiting")

        rig.path.set(connected: false)
        await Self.settle { rig.state.isOffline }
        #expect(rig.state.isOffline)
        #expect(rig.pill == "3 waiting · offline")

        rig.path.set(connected: true)
        await Self.settle { rig.pill == "3 waiting" }
        #expect(rig.pill == "3 waiting")
    }

    @Test("DataLayer.boot hands its network path to screen 17's view state")
    func bootWiresThePathToTheScreen() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cypress-110-boot-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Removed after the layer is released, so the database is not unlinked under an open
        // handle (the hazard `DataLayerWiringTests.databaseURL()` describes).
        defer { try? FileManager.default.removeItem(at: directory) }
        try await Self.checkBootWiring(directory: directory)
    }

    /// The layer lives only inside this call, so it is gone before the caller removes its folder.
    private static func checkBootWiring(directory: URL) async throws {
        let path = OutboxTestSupport.ManualNetworkPath(unmetered: false, connected: false)
        let data = try await DataLayer.boot(
            databaseURL: directory.appendingPathComponent("cypress.sqlite"),
            seedURL: nil,
            credentials: InMemoryCredentialStore(),
            networkPath: path
        )
        let state = data.makeOutboxViewState()
        let follower = Task { await state.followConnection() }
        defer { follower.cancel() }
        await settle { state.isOffline }
        #expect(state.isOffline, "the shipped screen was not given the layer's network path")
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
