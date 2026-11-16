import Foundation
import Testing
@testable import Cypress

/// A withdrawal queued before a keep-records account deletion reaches the service while the
/// account still owns the tree (ROADMAP 192).
///
/// The keep-records door makes the account's published trees anonymous on the service, and the
/// service lets nobody withdraw an anonymous tree (`withdrawCommunityTree` answers
/// `ErrNotTheAdder`, `forbidden`). `Service` below plays that rule: after `DELETE /me` under the
/// keep-records door it refuses every `tree_withdrawal` with `forbidden`.
///
/// The sentences, one test each:
/// 1. The reviewer's steps: the withdrawal is sent before `DELETE /me`, and the tree stays withdrawn.
/// 2. Offline at the deletion: nothing is deleted anywhere, the withdrawal stays queued, and a
///    later try sends both in order. The same when the service is up but does not take the
///    withdrawal yet: the deletion stops before `DELETE /me`.
/// 3. A `conflict` answer to the withdrawal during the deletion: the tree comes back with the
///    owner's sentence, and the deletion goes ahead.
/// 4. The erasing door is unchanged: no send first, and its restore still runs.
/// 5. A deletion with nothing queued asks the service exactly what it asked before.
/// 6. A drain already running when the deletion starts is waited for, not raced.
@Suite("Community trees · a withdrawal is sent before a keep-records deletion")
struct WithdrawBeforeAccountDeletionTests {

    private typealias Fixture = LocationCorrectionTests
    private typealias Withdrawal = TreeWithdrawalTests

    /// The service, both halves: the outbox's send sink (`POST /sync`) and the transport
    /// `RemoteAPI` sends `DELETE /me` through. It records every request in the order it arrived.
    final class Service: OutboxSendSink, AuthorizedTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var events: [String] = []
        private var offline = false
        /// `POST /sync` answers `server_error` while every other route works.
        private var syncDown = false
        private var deletedKeepingRecords = false
        private var withdrawalAnswer: APIError?
        private var anonymizedOnDeletion: [UUID] = []
        private var holding = false
        private var held: CheckedContinuation<Void, Never>?

        var log: [String] { locked { events } }
        var isHolding: Bool { locked { held != nil } }

        func setOffline(_ value: Bool) { locked { offline = value } }
        func setSyncDown(_ value: Bool) { locked { syncDown = value } }
        func answerWithdrawals(with error: APIError?) { locked { withdrawalAnswer = error } }
        func keepAnonymized(_ ids: [UUID]) { locked { anonymizedOnDeletion = ids } }
        func clearLog() { locked { events = [] } }
        /// The next `POST /sync` waits until `release()`.
        func holdNextSync() { locked { holding = true } }
        func release() {
            let waiter: CheckedContinuation<Void, Never>? = locked {
                defer { held = nil }
                return held
            }
            waiter?.resume()
        }

        private func locked<T>(_ body: () throws -> T) rethrows -> T {
            lock.lock(); defer { lock.unlock() }
            return try body()
        }

        private func takeHold() -> Bool {
            locked {
                defer { holding = false }
                return holding
            }
        }

        private func park(_ continuation: CheckedContinuation<Void, Never>) {
            locked { held = continuation }
        }

        // MARK: OutboxSendSink

        func sync(_ items: [OutboxItem]) async throws -> [SyncResult] {
            if takeHold() {
                await withCheckedContinuation { park($0) }
            }
            return try locked { () throws -> [SyncResult] in
                if offline {
                    events.append(contentsOf: items.map { "(offline) sync \($0.kind.rawValue)" })
                    throw URLError(.notConnectedToInternet)
                }
                events.append(contentsOf: items.map { "sync \($0.kind.rawValue)" })
                if syncDown { throw APIError.serverError }
                return items.map { item in
                    guard item.kind == .treeWithdrawal else {
                        return SyncResult(clientUUID: item.clientUUID, status: .applied)
                    }
                    // The service's rule: nobody withdraws an anonymous tree.
                    if deletedKeepingRecords {
                        return SyncResult(clientUUID: item.clientUUID, status: .failed, error: .forbidden)
                    }
                    if let withdrawalAnswer {
                        return SyncResult(clientUUID: item.clientUUID, status: .failed, error: withdrawalAnswer)
                    }
                    return SyncResult(clientUUID: item.clientUUID, status: .applied)
                }
            }
        }

        func uploadPhoto(_ photo: OutboxStore.PhotoRow, for item: OutboxItem) async throws {}

        // MARK: AuthorizedTransport

        func send(_ request: URLRequest) async throws -> Data {
            let method = request.httpMethod ?? "GET"
            let path = (request.url?.path ?? "").replacingOccurrences(of: "/api/v1", with: "")
            let choice = (request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? "")
                .contains("eraseEverything") ? "eraseEverything" : "leaveRecords"
            return try locked { () throws -> Data in
                if offline {
                    events.append("(offline) \(method) \(path)")
                    throw URLError(.notConnectedToInternet)
                }
                events.append("\(method) \(path)")
                guard method == "DELETE", path == "/me" else { throw APIError.notFound }
                if choice == "leaveRecords" { deletedKeepingRecords = true }
                let kept = anonymizedOnDeletion.map { "\"\($0.uuidString.lowercased())\"" }.joined(separator: ",")
                return Data("""
                    {"deleted":true,"choice":"\(choice)","contributions":0,"photos":0,"tombstones":0,
                     "community_trees":{"deleted":[],"anonymized":[\(kept)]}}
                    """.utf8)
            }
        }
    }

    /// One signed-in phone: its store, clock, local half, outbox and router, wired as
    /// `DataLayer.boot` wires them.
    struct Phone {
        let store: CypressStore
        let clock: TreeWithdrawalTests.Clock
        let local: LocalAPI
        let outbox: OutboxQueue
        let router: RoutedAPI
        let service: Service

        init() async throws {
            store = try await CypressStore.inMemory()
            let clock = TreeWithdrawalTests.Clock()
            self.clock = clock
            local = LocalAPI(store: store, deviceID: Fixture.deviceID, userID: Fixture.userID, now: { clock.now })
            service = Service()
            let queue = store.queue
            let remote = RemoteAPI(
                baseURL: URL(string: "https://service.invalid/api/v1")!,
                transport: service,
                session: .shared,
                pendingOutboxKeys: {
                    try await queue.read { try OutboxStore().unsentClientUUIDs(connection: $0) }
                }
            )
            let outbox = OutboxQueue(
                queue: store.queue, apply: APIOutboxTransport(api: local), send: service, now: { clock.now }
            )
            self.outbox = outbox
            router = RoutedAPI(
                local: local,
                remote: remote,
                signedInUserID: { Fixture.userID },
                sendQueueBeforeDeletion: { userID in try await outbox.sendBeforeAccountDeletion(userID: userID) }
            )
        }

        /// The account adds a tree and the add reaches the service; the account then withdraws it
        /// with no connection, and the drain's send fails. The withdrawal is left pending, in
        /// backoff, and the tree is hidden on this phone.
        func addThenWithdrawOffline() async throws -> Tree {
            let tree = try await Fixture.add(local)
            _ = try await outbox.drain()
            #expect(service.log == ["sync add_tree"], "fixture: the add did not reach the service: \(service.log)")
            service.keepAnonymized([tree.id])
            clock.advance(by: 60)

            service.setOffline(true)
            try await local.withdrawTree(treeID: tree.id)
            _ = try await outbox.drain()
            service.setOffline(false)

            let row = try #require(try await Withdrawal.withdrawals(store).first)
            #expect(row.item.state == .pending && !row.remoteSent,
                    "fixture: the offline withdrawal is \(row.item.state), sent \(row.remoteSent)")
            #expect(try await Withdrawal.deletedAt(store, tree.id) != nil, "fixture: the tree is not hidden")
            service.clearLog()
            return tree
        }
    }

    // MARK: - 1. The reviewer's steps

    /// Red-proof: remove the send-first block from `RoutedAPI.deleteAccount` — red on "the
    /// withdrawal was not sent before DELETE /me", and after the next drain on "the tree came back".
    @Test("the reviewer's steps: the withdrawal goes before DELETE /me, and the tree stays withdrawn")
    func theReviewersSteps() async throws {
        let phone = try await Phone()
        let tree = try await phone.addThenWithdrawOffline()

        try await phone.router.deleteAccount(.leaveRecords)

        #expect(phone.service.log == ["sync tree_withdrawal", "DELETE /me"],
                "the withdrawal was not sent before DELETE /me: \(phone.service.log)")

        // Whatever the queue does next, the tree stays withdrawn and the row stays settled.
        phone.clock.advance(by: 6 * 60 * 60)
        _ = try await phone.outbox.drain()
        let row = try #require(try await Withdrawal.withdrawals(phone.store).first)
        #expect(row.item.state == .done, "the withdrawal row is \(row.item.state): \(row.item.lastError ?? "no reason")")
        #expect(try await Withdrawal.deletedAt(phone.store, tree.id) != nil, "the tree came back")
        #expect(try await phone.local.mapContent(in: Withdrawal.box(around: tree.coordinate)).markerCount == 0,
                "the withdrawn tree is on the map")
        // The deletion itself happened: the tree is nobody's on this phone, as on the service.
        #expect(try await Fixture.adder(phone.store, tree.id) == .nobody)
    }

    // MARK: - 2. Offline at the deletion

    /// Red-proof: remove the send-first block from `RoutedAPI.deleteAccount` — red on "the
    /// deletion did not try the withdrawal first, or asked to delete": the log is
    /// `["(offline) DELETE /me"]`.
    @Test("offline at the deletion: nothing is deleted, the withdrawal stays queued, and a later try sends both in order")
    func offlineAtTheDeletion() async throws {
        let phone = try await Phone()
        let tree = try await phone.addThenWithdrawOffline()

        phone.service.setOffline(true)
        await #expect(throws: RoutedAPI.WithdrawalNotSentBeforeDeletion(unsent: 1)) {
            try await phone.router.deleteAccount(.leaveRecords)
        }
        #expect(phone.service.log == ["(offline) sync tree_withdrawal"],
                "the deletion did not try the withdrawal first, or asked to delete: \(phone.service.log)")
        phone.service.clearLog()
        let row = try #require(try await Withdrawal.withdrawals(phone.store).first)
        #expect(row.item.state == .pending && !row.remoteSent, "the withdrawal is \(row.item.state)")
        #expect(try await Withdrawal.deletedAt(phone.store, tree.id) != nil, "the tree came back")
        #expect(try await Fixture.adder(phone.store, tree.id) == .user(Fixture.userID),
                "the phone deleted the account although the service was never asked")

        // The person tries again with a connection, still inside the backoff.
        phone.service.setOffline(false)
        try await phone.router.deleteAccount(.leaveRecords)
        #expect(phone.service.log == ["sync tree_withdrawal", "DELETE /me"], "\(phone.service.log)")
        #expect(try await Withdrawal.deletedAt(phone.store, tree.id) != nil, "the tree came back")
    }

    /// The service is up but will not take the withdrawal yet (`server_error`), while `DELETE /me`
    /// would work. This is the case the unsent count is for: without it the account would go and
    /// the withdrawal would then be refused for good.
    ///
    /// Red-proof: make `RoutedAPI.deleteAccount` ignore the unsent count — red on "the deletion
    /// went ahead with the withdrawal unsent".
    @Test("a withdrawal the service does not take yet stops the deletion before DELETE /me")
    func aWithdrawalNotTakenYetStopsTheDeletion() async throws {
        let phone = try await Phone()
        let tree = try await phone.addThenWithdrawOffline()

        phone.service.setSyncDown(true)
        await #expect(throws: RoutedAPI.WithdrawalNotSentBeforeDeletion(unsent: 1),
                      "the deletion went ahead with the withdrawal unsent") {
            try await phone.router.deleteAccount(.leaveRecords)
        }
        #expect(phone.service.log == ["sync tree_withdrawal"], "\(phone.service.log)")
        let row = try #require(try await Withdrawal.withdrawals(phone.store).first)
        #expect(row.item.state == .pending && !row.remoteSent, "the withdrawal is \(row.item.state)")
        #expect(try await Withdrawal.deletedAt(phone.store, tree.id) != nil, "the tree came back")
        #expect(try await Fixture.adder(phone.store, tree.id) == .user(Fixture.userID),
                "the phone deleted the account")
    }

    // MARK: - 3. Conflict

    /// Somebody else built on the tree: the service keeps it, the tree comes back with the owner's
    /// sentence, and the deletion goes ahead, because nothing is left to send.
    @Test("a conflict during the deletion brings the tree back with the owner's sentence, and the deletion goes ahead")
    func aConflictDuringTheDeletion() async throws {
        let phone = try await Phone()
        let tree = try await phone.addThenWithdrawOffline()
        phone.service.answerWithdrawals(with: .conflict)

        try await phone.router.deleteAccount(.leaveRecords)

        #expect(phone.service.log == ["sync tree_withdrawal", "DELETE /me"], "\(phone.service.log)")
        let row = try #require(try await Withdrawal.withdrawals(phone.store).first)
        #expect(row.item.state == .failed)
        #expect(row.item.lastError == "Other people have added to this tree, so it stays on the map.",
                "the row reads \(row.item.lastError ?? "nothing")")
        #expect(try await Withdrawal.deletedAt(phone.store, tree.id) == nil, "the refused tree stays hidden")
        #expect(try await Fixture.adder(phone.store, tree.id) == .nobody, "the deletion did not run")
    }

    // MARK: - 4. The erasing door

    /// Red-proof: drop `choice == .leaveRecords` from the send-first condition — red on "the erasing
    /// door sent the queue first".
    @Test("the erasing door sends nothing first, and still puts back the tree of an unsent withdrawal")
    func theErasingDoorIsUnchanged() async throws {
        let phone = try await Phone()
        let tree = try await phone.addThenWithdrawOffline()

        try await phone.router.deleteAccount(.eraseEverything)

        #expect(phone.service.log == ["DELETE /me"], "the erasing door sent the queue first: \(phone.service.log)")
        #expect(try await Withdrawal.withdrawals(phone.store).isEmpty, "the erasing door kept a queued withdrawal")
        #expect(try await Withdrawal.deletedAt(phone.store, tree.id) == nil,
                "the erasing door left the kept tree hidden")
    }

    // MARK: - 5. Nothing queued

    @Test("a deletion with nothing queued asks the service only DELETE /me, under either door",
          arguments: AccountDeletionChoice.allCases)
    func nothingQueued(choice: AccountDeletionChoice) async throws {
        let phone = try await Phone()
        _ = try await Fixture.add(phone.local)
        _ = try await phone.outbox.drain()
        phone.service.clearLog()

        try await phone.router.deleteAccount(choice)

        #expect(phone.service.log == ["DELETE /me"], "\(phone.service.log)")
    }

    // MARK: - 6. A drain already running

    /// The deletion starts while a drain holds the withdrawal `uploading`. It must wait for that
    /// drain, not race it.
    ///
    /// Red-proof: remove `await waitUntilIdle()` from `sendBeforeAccountDeletion` — the two passes
    /// race: the log reads `["sync tree_withdrawal", "DELETE /me", "sync tree_withdrawal"]`, the
    /// held drain's late send is refused, and the test is red on "the tree came back" and "the
    /// withdrawal row is .failed".
    @Test("a drain already running is waited for, and the withdrawal still goes first")
    func aRunningDrainIsWaitedFor() async throws {
        let phone = try await Phone()
        let tree = try await phone.addThenWithdrawOffline()
        phone.clock.advance(by: 60) // out of the backoff, so the drain takes the withdrawal

        phone.service.holdNextSync()
        let outbox = phone.outbox
        let drain = Task { try await outbox.drain() }
        for _ in 0..<500 where !phone.service.isHolding {
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        #expect(phone.service.isHolding, "fixture: the drain never reached the service")

        let router = phone.router
        let deletion = Task { try await router.deleteAccount(.leaveRecords) }
        // Give the deletion time to reach the queue while the drain is held.
        try await Task.sleep(nanoseconds: 50_000_000)
        phone.service.release()

        _ = try await drain.value
        _ = try await deletion.value

        #expect(phone.service.log == ["sync tree_withdrawal", "DELETE /me"], "\(phone.service.log)")
        #expect(try await Withdrawal.deletedAt(phone.store, tree.id) != nil, "the tree came back")
        let row = try #require(try await Withdrawal.withdrawals(phone.store).first)
        #expect(row.item.state == .done, "the withdrawal row is \(row.item.state)")
    }
}
