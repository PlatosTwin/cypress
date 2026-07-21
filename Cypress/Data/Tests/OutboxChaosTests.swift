#if canImport(Testing)
import Foundation
import Testing

/// **Acceptance gate (ARCHITECTURE §7).** 20 queued mutations across scripted failures; zero loss,
/// zero duplicates on `clientUUID`, correct per-item terminal states, and a backoff schedule that
/// matches BUILD-PLAN §4 exactly.
///
/// The scenario itself lives in `DataGates.outboxChaos()` so that it can also be run from a plain
/// executable — which is how it was verified before a test target existed. See `DataGates`.
///
/// > No test target is configured for this project yet. These suites compile into the app target as
/// > nothing (`canImport(Testing)` is false there) and are ready to be added to one.
@Suite("Outbox chaos")
struct OutboxChaosTests {

    @Test("20 mutations survive scripted failures with zero loss and zero duplicates")
    func chaos() async throws {
        let failures = try await DataGates.outboxChaos()
        #expect(failures.isEmpty, "\(failures.count) gate failures:\n" + failures.joined(separator: "\n"))
    }

    @Test("the backoff schedule is 30 s, 2 m, 10 m, 1 h, then hourly")
    func backoffSchedule() {
        #expect(OutboxRetryPolicy.delay(afterFailures: 0) == 0)
        #expect(OutboxRetryPolicy.delay(afterFailures: 1) == 30)
        #expect(OutboxRetryPolicy.delay(afterFailures: 2) == 120)
        #expect(OutboxRetryPolicy.delay(afterFailures: 3) == 600)
        #expect(OutboxRetryPolicy.delay(afterFailures: 4) == 3_600)
        for failCount in 5...100 {
            #expect(OutboxRetryPolicy.delay(afterFailures: failCount) == 3_600)
        }
        #expect(OutboxRetryPolicy.cap == 48 * 60 * 60)
    }

    @Test("a non-retryable code fails immediately rather than spending 48 hours", arguments: APIError.allCases)
    func nonRetryableFailsFast(error: APIError) {
        let item = OutboxItem(kind: .visit, clientUUID: UUID(), payload: Data("{}".utf8))
        let state = OutboxRetryPolicy.nextState(for: item, error: error, now: item.createdAt)
        #expect(state == (error.retryable ? .pending : .failed))
    }

    @Test("every failure produces a sentence the outbox screen can show")
    func everyFailureSaysWhy() {
        for error in APIError.allCases {
            let sentence = OutboxFailureReason.describe(error: error, failCount: 1, state: .pending)
            #expect(!sentence.isEmpty)
            // ARCHITECTURE §5.7: no spaces around em dashes. Easiest kept by not using one.
            #expect(!sentence.contains(" — "))
        }
        #expect(!OutboxFailureReason.sentence(for: URLError(.notConnectedToInternet)).isEmpty)
        #expect(!OutboxFailureReason.expired.isEmpty)
    }

    @Test("enqueue is idempotent on clientUUID")
    func enqueueIsIdempotent() async throws {
        let store = try await CypressStore.inMemory()
        let transport = OutboxTestSupport.ScriptedTransport()
        let queue = OutboxQueue(queue: store.queue, transport: transport)

        let visit = Visit(treeID: UUID(), attribution: OutboxTestSupport.attribution, capturedAt: Date())
        let first = try await queue.enqueue(.visit(visit))
        let second = try await queue.enqueue(.visit(visit))

        let records = try await queue.records()
        #expect(records.count == 1)
        #expect(first.clientUUID == second.clientUUID)
    }

    @Test("the wifi-only toggle gates photo binaries and nothing else")
    func wifiOnlyGatesBinariesOnly() async throws {
        let store = try await CypressStore.inMemory()
        let transport = OutboxTestSupport.ScriptedTransport()
        let queue = OutboxQueue(queue: store.queue, transport: transport)

        let visit = Visit(treeID: UUID(), attribution: OutboxTestSupport.attribution, capturedAt: Date())
        _ = try await queue.enqueue(.visit(visit), photoPaths: ["/tmp/a.jpg", "/tmp/b.jpg"])

        _ = try await queue.drain(photoUploadsAllowed: false)
        var record = try #require(try await queue.records().first)
        #expect(record.jsonSynced)
        #expect(record.item.state == .pending)
        #expect(record.item.photoPaths.count == 2)
        #expect(await transport.uploadedPhotoPaths.isEmpty)

        _ = try await queue.drain(photoUploadsAllowed: true)
        record = try #require(try await queue.records().first)
        #expect(record.item.state == .done)
        #expect(record.item.photoPaths.isEmpty)
        #expect(await transport.uploadedPhotoPaths.count == 2)
    }

    @Test("screen 17's snapshot reports state, fail count, and a reason per item")
    func snapshotFeedsScreen17() async throws {
        let clock = OutboxTestSupport.Clock()
        let store = try await CypressStore.inMemory()
        let transport = OutboxTestSupport.ScriptedTransport(script: .allFail(.validationFailed))
        let queue = OutboxQueue(queue: store.queue, transport: transport, now: clock.closure)

        let treeID = UUID()
        _ = try await queue.enqueue(
            .visit(Visit(treeID: treeID, attribution: OutboxTestSupport.attribution, capturedAt: clock.now))
        )
        _ = try await queue.drain()

        let snapshot = try await queue.snapshot(treeNames: [treeID: "Grandmother Cypress"])
        let item = try #require(snapshot.items.first)
        #expect(item.state == .failed)
        #expect(item.failCount == 1)
        #expect(item.reason?.isEmpty == false)
        #expect(item.errorCode == .validationFailed)
        #expect(item.treeName == "Grandmother Cypress")
        #expect(item.showsRetryAffordance)
        #expect(snapshot.failedCount == 1)
        #expect(snapshot.lostCount == 0)
    }
}
#endif
