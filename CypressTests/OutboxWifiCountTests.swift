import Foundation
import Testing
@testable import Cypress

/// `OutboxSnapshot.awaitingWifiCount` — the number behind screen 17's "The note is saved. N photos
/// are waiting for wi-fi."
///
/// The predicate this suite pins used to be `state != .done && !photos.isEmpty`, which asserted
/// neither half of the sentence. Screen 17's whole job is that an item "says so, says why, and
/// waits for you", and the two cases below — a visit that has not been drained at all, and one that
/// failed validation while carrying a photo — are the two ways that count told somebody the note
/// had gone when it had not (ERRATA E32).
@Suite("Outbox awaiting-wifi count")
struct OutboxWifiCountTests {

    private static func makeQueue(
        script: OutboxTestSupport.Script
    ) async throws -> (OutboxQueue, OutboxTestSupport.Clock) {
        let clock = OutboxTestSupport.Clock()
        let store = try await CypressStore.inMemory()
        let transport = OutboxTestSupport.ScriptedTransport(script: script)
        return (OutboxQueue(queue: store.queue, apply: transport, now: clock.closure), clock)
    }

    private static func enqueueVisitWithPhoto(on queue: OutboxQueue, at moment: Date) async throws {
        let visit = Visit(
            treeID: UUID(),
            attribution: OutboxTestSupport.attribution,
            note: "with a photo",
            gpsAccuracyM: 5,
            capturedAt: moment
        )
        _ = try await queue.enqueue(
            .visit(visit),
            photos: [OutboxPhoto(path: "/tmp/cypress-wifi-count.jpg", shotType: .leaf)]
        )
    }

    /// The bug's first face: nothing has been sent yet, so nothing is waiting on wi-fi. The item is
    /// waiting on its first drain, and `waitingCount` is where it belongs.
    @Test("a photo-carrying visit that has never been drained is not awaiting wi-fi")
    func neverDrained() async throws {
        let (queue, clock) = try await Self.makeQueue(script: .allSucceed)
        try await Self.enqueueVisitWithPhoto(on: queue, at: clock.now)

        let snapshot = try await queue.snapshot(syncPhotosOnWifiOnly: true)
        #expect(snapshot.awaitingWifiCount == 0)
        #expect(snapshot.waitingCount == 1)
    }

    /// The state the sentence actually describes: the JSON was accepted, the binary was held back.
    @Test("a drained item whose binary was held back is awaiting wi-fi")
    func heldBackOnMeteredConnection() async throws {
        let (queue, clock) = try await Self.makeQueue(script: .allSucceed)
        try await Self.enqueueVisitWithPhoto(on: queue, at: clock.now)

        _ = try await queue.drain(photoUploadsAllowed: false)

        let snapshot = try await queue.snapshot(syncPhotosOnWifiOnly: true)
        #expect(snapshot.awaitingWifiCount == 1)
        let item = try #require(snapshot.items.first)
        #expect(item.state == .pending)
        #expect(item.photoCount == 1)
    }

    /// With the toggle off, no photo is behind it. Same rows, different answer, and the count has to
    /// be able to say so — this is the assertion that makes the toggle a real input rather than an
    /// unused argument.
    @Test("the same held-back item is not awaiting wi-fi once the toggle is off")
    func toggleOffCountsNothing() async throws {
        let (queue, clock) = try await Self.makeQueue(script: .allSucceed)
        try await Self.enqueueVisitWithPhoto(on: queue, at: clock.now)

        _ = try await queue.drain(photoUploadsAllowed: false)

        let snapshot = try await queue.snapshot(syncPhotosOnWifiOnly: false)
        #expect(snapshot.awaitingWifiCount == 0)
    }

    /// The bug's second face. `validation_failed` is not retryable, so the row is terminal and
    /// screen 17 draws it as an amber card asking for a tap. It happens to carry a photo, which was
    /// the whole of the old predicate.
    @Test("an item that failed validation while carrying a photo is not awaiting wi-fi")
    func terminalFailureWithPhoto() async throws {
        let (queue, clock) = try await Self.makeQueue(script: .allFail(.validationFailed))
        try await Self.enqueueVisitWithPhoto(on: queue, at: clock.now)

        _ = try await queue.drain(photoUploadsAllowed: true)

        let snapshot = try await queue.snapshot(syncPhotosOnWifiOnly: true)
        #expect(snapshot.awaitingWifiCount == 0)
        #expect(snapshot.failedCount == 1)
        let item = try #require(snapshot.items.first)
        #expect(item.errorCode == .validationFailed)
        #expect(item.photoCount == 1)
    }

    /// And once the binary has gone, the count empties.
    @Test("the count clears when wi-fi arrives and the binary goes")
    func clearsOnceUploaded() async throws {
        let (queue, clock) = try await Self.makeQueue(script: .allSucceed)
        try await Self.enqueueVisitWithPhoto(on: queue, at: clock.now)

        _ = try await queue.drain(photoUploadsAllowed: false)
        _ = try await queue.drain(photoUploadsAllowed: true)

        let snapshot = try await queue.snapshot(syncPhotosOnWifiOnly: true)
        #expect(snapshot.awaitingWifiCount == 0)
        #expect(snapshot.items.first?.state == .done)
    }
}
