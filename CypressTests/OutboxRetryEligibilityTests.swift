import Foundation
import Testing
@testable import Cypress

/// Which failed Outbox rows a person may retry (the owner's answers of 2026-11-16, "Remove Retry
/// there" and "Row stays, reason only").
///
/// One kind of row loses Retry: a `tree_withdrawal` the service refused with `conflict`. It stays in
/// the Outbox with its reason and no button, and it is what keeps the tree's profile drawing the
/// reason line. The rule is stated once in Swift (`OutboxRetryPolicy.acceptsRetry`) and once in SQL
/// (`OutboxStore.retryable`); this suite holds the screen, the store and the policy to one answer.
@Suite("Outbox · which failed rows may be retried")
struct OutboxRetryEligibilityTests {

    private static let moment = Date(timeIntervalSince1970: 1_797_000_000)

    /// A failed row of `kind`, with `code` as its last failure code, written straight to the store.
    /// The payload is never decoded on these paths.
    @discardableResult
    private static func failedRow(
        _ kind: OutboxItem.Kind,
        code: APIError?,
        store: CypressStore
    ) async throws -> UUID {
        let item = OutboxItem(kind: kind, clientUUID: UUID(), payload: Data("{}".utf8))
        try await store.queue.write { connection in
            let outbox = OutboxStore()
            _ = try outbox.enqueue(item, connection: connection)
            try outbox.recordFailure(
                item.id, state: .failed, failCount: 1, reason: "This couldn't be sent.",
                code: code, nextAttemptAt: nil, at: moment, connection: connection
            )
        }
        return item.id
    }

    private static func record(_ id: UUID, _ store: CypressStore) async throws -> OutboxStore.Record? {
        try await store.queue.read { try OutboxStore().item(id: id, connection: $0) }
    }

    // MARK: - The policy

    /// Red-proof: make `acceptsRetry` return true — red on "a withdrawal refused with conflict is
    /// retryable".
    @Test("only a withdrawal refused with conflict is refused a retry")
    func thePolicy() {
        #expect(!OutboxRetryPolicy.acceptsRetry(kind: .treeWithdrawal, errorCode: .conflict),
                "a withdrawal refused with conflict is retryable")
        #expect(OutboxRetryPolicy.acceptsRetry(kind: .treeWithdrawal, errorCode: .forbidden))
        #expect(OutboxRetryPolicy.acceptsRetry(kind: .treeWithdrawal, errorCode: nil),
                "a withdrawal that ran out its 48 hours lost Retry")
        #expect(OutboxRetryPolicy.acceptsRetry(kind: .visit, errorCode: .conflict),
                "another kind refused with conflict lost Retry")
        #expect(OutboxRetryPolicy.acceptsRetry(kind: .locationCorrection, errorCode: .conflict))
    }

    // MARK: - The store agrees with the policy, for every kind and every code

    /// Red-proof: drop `AND \(Self.retryable)` from `OutboxStore.retry` — red on "the store retried
    /// tree_withdrawal / conflict".
    @Test("the store retries exactly the rows the policy accepts")
    func theStoreAgreesWithThePolicy() async throws {
        let store = try await CypressStore.inMemory()
        let codes: [APIError?] = [nil] + APIError.allCases.map { $0 }
        for kind in OutboxItem.Kind.allCases {
            for code in codes {
                let id = try await Self.failedRow(kind, code: code, store: store)
                let retried = try await store.queue.write {
                    try OutboxStore().retry(id, at: Self.moment, connection: $0)
                }
                let expected = OutboxRetryPolicy.acceptsRetry(kind: kind, errorCode: code)
                #expect(retried == expected,
                        "the store \(retried ? "retried" : "refused") \(kind.rawValue) / \(code?.rawValue ?? "no code")")
            }
        }
    }

    // MARK: - Retry all, with a mix

    /// Red-proof: drop `AND \(Self.retryable)` from `OutboxStore.retryAllFailed` — red on "Retry all
    /// moved 3 rows" and on the refused withdrawal's state.
    @Test("retry all moves every other failed row and leaves the refused withdrawal as it is")
    func retryAllLeavesTheRefusedWithdrawal() async throws {
        let store = try await CypressStore.inMemory()
        let refused = try await Self.failedRow(.treeWithdrawal, code: .conflict, store: store)
        let forbidden = try await Self.failedRow(.treeWithdrawal, code: .forbidden, store: store)
        let visit = try await Self.failedRow(.visit, code: .conflict, store: store)

        let moved = try await store.queue.write {
            try OutboxStore().retryAllFailed(at: Self.moment, connection: $0)
        }
        #expect(moved == 2, "Retry all moved \(moved) rows")

        let kept = try #require(try await Self.record(refused, store))
        #expect(kept.item.state == .failed, "the refused withdrawal is \(kept.item.state)")
        #expect(kept.item.lastErrorCode == .conflict, "the refused withdrawal lost its code")
        #expect(kept.item.lastError == "This couldn't be sent.", "the refused withdrawal lost its reason")
        #expect(try await Self.record(forbidden, store)?.item.state == .pending)
        #expect(try await Self.record(visit, store)?.item.state == .pending)
    }

    // MARK: - The screen

    /// Red-proof: make `Row.showsRetryButton` ignore `acceptsRetry` — red on "the refused
    /// withdrawal draws Retry".
    @Test("the refused withdrawal is still a terminal row with its reason, and draws no Retry")
    func theScreenDrawsNoRetryOnTheRefusedWithdrawal() async throws {
        let store = try await CypressStore.inMemory()
        let refused = try await Self.failedRow(.treeWithdrawal, code: .conflict, store: store)
        let forbidden = try await Self.failedRow(.treeWithdrawal, code: .forbidden, store: store)
        let visit = try await Self.failedRow(.visit, code: .conflict, store: store)

        let records = try await store.queue.read { try OutboxStore().allItems(connection: $0) }
        let snapshot = OutboxSnapshot(
            records: records, treeNames: [:], now: Self.moment, syncPhotosOnWifiOnly: true
        )
        let rows = OutboxPresentation(snapshot: snapshot, now: Self.moment).queue
        func row(_ id: UUID) throws -> OutboxPresentation.Row { try #require(rows.first { $0.id == id }) }

        let kept = try row(refused)
        #expect(kept.reason == "This couldn't be sent.", "the refused withdrawal lost its reason")
        #expect(kept.isTerminal, "the refused withdrawal is no longer a terminal row")
        #expect(!kept.showsRetryButton, "the refused withdrawal draws Retry")
        #expect(snapshot.items.first { $0.id == refused }?.showsRetryAffordance == false,
                "the snapshot offers the refused withdrawal a retry")

        #expect(try row(forbidden).showsRetryButton, "a withdrawal refused as forbidden lost Retry")
        #expect(try row(visit).showsRetryButton, "a visit refused with conflict lost Retry")
    }
}
