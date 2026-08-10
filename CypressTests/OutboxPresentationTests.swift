import Foundation
import Testing
@testable import Cypress

/// Screen 17, derived — and specifically the two things it exists to make visible: an item that has
/// given up, and the sentence the wi-fi toggle is currently making true.
///
/// The 48 h cap is driven through a real `OutboxQueue` on a movable clock rather than asserted
/// against a hand-built row, because the state that matters is the one the drain actually produces.
@Suite("Outbox screen")
struct OutboxPresentationTests {

    private static let deviceID = UUID(uuidString: "9F3A0000-0000-4000-8000-0000000000DE")!
    private static let treeID = UUID(uuidString: "9F3A0000-0000-4000-8000-000000000017")!
    private static let treeNames = [treeID: "The Tea Tree at 46th"]

    private static func makeQueue(
        script: OutboxTestSupport.Script
    ) async throws -> (OutboxQueue, OutboxTestSupport.Clock) {
        let clock = OutboxTestSupport.Clock()
        let store = try await CypressStore.inMemory()
        let transport = OutboxTestSupport.ScriptedTransport(script: script)
        return (OutboxQueue(queue: store.queue, apply: transport, now: clock.closure), clock)
    }

    private static func enqueueMeasurement(on queue: OutboxQueue, at moment: Date) async throws {
        _ = try await queue.enqueue(
            .measurement(TreeMeasurement.dbh(
                treeID: treeID,
                attribution: .anonymous(deviceID: deviceID),
                capturedAt: moment,
                gpsAccuracyM: 7,
                quantity: Quantity(value: 31, unit: .centimeters, method: .tape),
                createdAt: moment,
                updatedAt: moment
            ))
        )
    }

    private static func enqueueVisitWithPhotos(
        on queue: OutboxQueue,
        at moment: Date,
        photos: Int,
        suffix: String
    ) async throws {
        _ = try await queue.enqueue(
            .visit(Visit(
                treeID: treeID,
                attribution: .anonymous(deviceID: deviceID),
                gpsAccuracyM: 5,
                capturedAt: moment
            )),
            photos: (0..<photos).map {
                OutboxPhoto(path: "/tmp/cypress-outbox-\(suffix)-\($0).jpg", shotType: .fullTree)
            }
        )
    }

    private static func presentation(_ snapshot: OutboxSnapshot, now: Date) -> OutboxPresentation {
        OutboxPresentation(snapshot: snapshot, now: now)
    }

    // MARK: - The 48 h terminal state

    @Test("an item that runs out the 48 h window renders as terminal, not as still trying")
    func expiredRendersAsTerminal() async throws {
        let (queue, clock) = try await Self.makeQueue(script: .allFail(.serverError))
        try await Self.enqueueMeasurement(on: queue, at: clock.now)

        // A retryable failure inside the window: still trying, and the screen says `waiting`.
        _ = try await queue.drain()
        let stillTrying = Self.presentation(
            try await queue.snapshot(treeNames: Self.treeNames, syncPhotosOnWifiOnly: true),
            now: clock.now
        )
        let live = try #require(stillTrying.queue.first)
        #expect(live.state == .waiting)
        #expect(live.isTerminal == false)
        #expect(live.showsRetryButton == false)
        #expect(stillTrying.headerPill == "1 waiting")

        // Past the cap. BUILD-PLAN §4: "cap 48 h then state failed with a visible retry button".
        clock.advance(by: OutboxRetryPolicy.cap + 1)
        _ = try await queue.drain()

        let snapshot = try await queue.snapshot(treeNames: Self.treeNames, syncPhotosOnWifiOnly: true)
        #expect(snapshot.failedCount == 1)
        #expect(snapshot.waitingCount == 0)
        #expect(snapshot.lostCount == 0)

        let presentation = Self.presentation(snapshot, now: clock.now)
        let row = try #require(presentation.queue.first)
        #expect(row.state == .retry)
        #expect(row.isTerminal, "an expired item must not draw as a live one")
        #expect(row.showsRetryButton)
        // It says so and says why (§6's footnote is the contract).
        #expect(row.reason == OutboxFailureReason.expired)
        #expect(row.reason?.contains("48 hours") == true)
        // And the header stops claiming anything is waiting, because nothing is.
        #expect(presentation.headerPill == nil)
        // The row still names what is in it, with its method badge (D7).
        #expect(row.title == "Measurement · The Tea Tree at 46th")
        #expect(row.quantity?.method == .tape)
        #expect(row.tile == .value("31"))
    }

    @Test("retrying an expired item puts it back to waiting, and restarts its window")
    func retryRevivesAnExpiredItem() async throws {
        let (queue, clock) = try await Self.makeQueue(script: .allFail(.serverError))
        try await Self.enqueueMeasurement(on: queue, at: clock.now)
        _ = try await queue.drain()
        clock.advance(by: OutboxRetryPolicy.cap + 1)
        _ = try await queue.drain()

        let expired = try #require(
            Self.presentation(
                try await queue.snapshot(treeNames: Self.treeNames, syncPhotosOnWifiOnly: true),
                now: clock.now
            ).queue.first
        )
        #expect(expired.showsRetryButton)

        #expect(try await queue.retry(id: expired.id))
        let revived = try #require(
            Self.presentation(
                try await queue.snapshot(treeNames: Self.treeNames, syncPhotosOnWifiOnly: true),
                now: clock.now
            ).queue.first
        )
        #expect(revived.state == .waiting)
        #expect(revived.isTerminal == false)
    }

    @Test("a terminal failure the API will never accept is not offered a retry")
    func nonRetryableIsStoppedRatherThanRetryable() async throws {
        let (queue, clock) = try await Self.makeQueue(script: .allFail(.validationFailed))
        try await Self.enqueueMeasurement(on: queue, at: clock.now)
        _ = try await queue.drain()

        let presentation = Self.presentation(
            try await queue.snapshot(treeNames: Self.treeNames, syncPhotosOnWifiOnly: true),
            now: clock.now
        )
        let row = try #require(presentation.queue.first)
        // Terminal, amber, and honest about the fact that a tap will not change it.
        #expect(row.state == .stopped)
        #expect(row.isTerminal)
        #expect(row.showsRetryButton == false)
        #expect(row.reason?.contains("will not go through on its own") == true)
    }

    // MARK: - The wi-fi sentence, clause by clause

    @Test("the sentence appears only when every clause of it is true")
    func awaitingWifiClauses() async throws {
        let (queue, clock) = try await Self.makeQueue(script: .allSucceed)
        try await Self.enqueueVisitWithPhotos(on: queue, at: clock.now, photos: 2, suffix: "a")

        // Clause 1, the note is saved: not yet. It has never been drained.
        var snapshot = try await queue.snapshot(syncPhotosOnWifiOnly: true)
        #expect(Self.presentation(snapshot, now: clock.now).awaitingWifiSentence == nil)

        // Now it has: JSON accepted, binaries held back.
        _ = try await queue.drain(photoUploadsAllowed: false)
        snapshot = try await queue.snapshot(syncPhotosOnWifiOnly: true)
        #expect(
            Self.presentation(snapshot, now: clock.now).awaitingWifiSentence
                == "The note is saved. 2 photos are waiting for wi-fi."
        )

        // Clause 4, the toggle is what is holding them: with it off, nothing is.
        let toggledOff = try await queue.snapshot(syncPhotosOnWifiOnly: false)
        #expect(Self.presentation(toggledOff, now: clock.now).awaitingWifiSentence == nil)

        // Clause 2, the binaries are still on the device: once they go, the sentence goes.
        _ = try await queue.drain(photoUploadsAllowed: true)
        snapshot = try await queue.snapshot(syncPhotosOnWifiOnly: true)
        #expect(Self.presentation(snapshot, now: clock.now).awaitingWifiSentence == nil)
        #expect(snapshot.awaitingWifiPhotoCount == 0)
    }

    @Test("the sentence counts photos, not items")
    func theSentenceCountsPhotos() async throws {
        // Two items, two binaries each. `awaitingWifiCount` is 2 and the sentence must say 4:
        // "photos" is one of the clauses ERRATA E32 requires to be true.
        let (queue, clock) = try await Self.makeQueue(script: .allSucceed)
        try await Self.enqueueVisitWithPhotos(on: queue, at: clock.now, photos: 2, suffix: "b")
        try await Self.enqueueVisitWithPhotos(on: queue, at: clock.now.addingTimeInterval(60), photos: 2, suffix: "c")

        _ = try await queue.drain(photoUploadsAllowed: false)

        let snapshot = try await queue.snapshot(syncPhotosOnWifiOnly: true)
        #expect(snapshot.awaitingWifiCount == 2)
        #expect(snapshot.awaitingWifiPhotoCount == 4)
        #expect(
            Self.presentation(snapshot, now: clock.now).awaitingWifiSentence
                == "The note is saved. 4 photos are waiting for wi-fi."
        )
    }

    @Test("clause 3: an item that gave up is asking for a tap, not for a connection")
    func terminalItemsAreNotAwaitingWifi() async throws {
        let (queue, clock) = try await Self.makeQueue(script: .allFail(.validationFailed))
        try await Self.enqueueVisitWithPhotos(on: queue, at: clock.now, photos: 2, suffix: "d")
        _ = try await queue.drain(photoUploadsAllowed: false)

        let snapshot = try await queue.snapshot(syncPhotosOnWifiOnly: true)
        let presentation = Self.presentation(snapshot, now: clock.now)
        #expect(snapshot.failedCount == 1)
        #expect(snapshot.awaitingWifiCount == 0)
        #expect(presentation.awaitingWifiSentence == nil)
        #expect(presentation.queue.first?.isTerminal == true)
    }

    @Test("one photo is one photo")
    func singularPhoto() async throws {
        let (queue, clock) = try await Self.makeQueue(script: .allSucceed)
        try await Self.enqueueVisitWithPhotos(on: queue, at: clock.now, photos: 1, suffix: "e")
        _ = try await queue.drain(photoUploadsAllowed: false)

        #expect(
            Self.presentation(
                try await queue.snapshot(syncPhotosOnWifiOnly: true),
                now: clock.now
            ).awaitingWifiSentence == "The note is saved. One photo is waiting for wi-fi."
        )
    }

    // MARK: - The empty queue

    @Test("an empty outbox draws its own sentence and no zeroes")
    func emptyQueue() {
        let presentation = Self.presentation(
            OutboxSnapshot(records: [], treeNames: [:], now: Date(), syncPhotosOnWifiOnly: true),
            now: Date()
        )
        #expect(presentation.isEmpty)
        #expect(presentation.isQueueEmpty)
        #expect(presentation.queue.isEmpty)
        #expect(presentation.syncedRows.isEmpty)
        // ARCHITECTURE §5.6: a surface below its threshold does not render at all — not a zero.
        #expect(presentation.headerPill == nil)
        #expect(presentation.summaryLine == nil)
        #expect(presentation.awaitingWifiSentence == nil)
        #expect(OutboxCopy.emptyState.isEmpty == false)
    }

    @Test("a synced item leaves the queue, becomes a receipt, and is counted once")
    func syncedItemsBecomeReceipts() async throws {
        let (queue, clock) = try await Self.makeQueue(script: .allSucceed)
        try await Self.enqueueMeasurement(on: queue, at: clock.now)
        clock.advance(by: 60)
        _ = try await queue.drain()

        let snapshot = try await queue.snapshot(treeNames: Self.treeNames, syncPhotosOnWifiOnly: true)
        let presentation = Self.presentation(snapshot, now: clock.now)
        #expect(presentation.queue.isEmpty)
        #expect(presentation.isQueueEmpty)
        #expect(presentation.syncedRows.count == 1)
        #expect(presentation.syncedRows.first?.title == "Measurement · The Tea Tree at 46th")
        #expect(presentation.syncedRows.first?.timeText.hasPrefix("✓ ") == true)
        #expect(presentation.summaryLine == "today · 1 synced · 0 lost")
        #expect(presentation.headerPill == nil)
    }

    // MARK: - What a row says

    @Test("a row with no name for its tree falls back rather than drawing half a title")
    func unnamedTree() async throws {
        let (queue, clock) = try await Self.makeQueue(script: .allSucceed)
        try await Self.enqueueMeasurement(on: queue, at: clock.now)

        let presentation = Self.presentation(
            try await queue.snapshot(syncPhotosOnWifiOnly: true),
            now: clock.now
        )
        #expect(presentation.queue.first?.title == "Measurement · \(TreeProfilePresentation.fallbackTitle)")
    }

    @Test("every outbox kind has a row title, including the two SCREENS.md does not draw")
    func everyKindHasALabel() {
        for kind in OutboxItem.Kind.allCases {
            #expect(OutboxCopy.kindLabel(kind).isEmpty == false)
        }
        #expect(OutboxCopy.kindLabel(.visit) == "Visit")
        #expect(OutboxCopy.kindLabel(.observation) == "Check-in")
        #expect(OutboxCopy.kindLabel(.measurement) == "Measurement")
        #expect(OutboxCopy.kindLabel(.careEvent) == "Care")
    }

    @Test("a queued check-in says what it holds, and a private reminder does not name a hazard")
    func rowDetails() {
        func item(_ payload: OutboxPayload, photos: Int = 0) -> OutboxItemSnapshot {
            OutboxItemSnapshot(
                id: UUID(),
                kind: payload.kind,
                state: .pending,
                failCount: 0,
                reason: nil,
                errorCode: nil,
                treeID: Self.treeID,
                treeName: "Judah Street Gum",
                payload: payload,
                photoCount: photos,
                createdAt: Date(),
                updatedAt: Date(),
                nextAttemptAt: nil
            )
        }

        let checkIn = item(.observation(TreeObservation(
            treeID: Self.treeID,
            attribution: .anonymous(deviceID: Self.deviceID),
            capturedAt: Date(),
            status: .alive,
            vitality: .fair,
            foliage: FoliageAssessment(density: .thinning)
        )))
        #expect(OutboxCopy.detail(for: checkIn) == "vitality 3, thinning")

        let visit = item(.visit(Visit(
            treeID: Self.treeID,
            attribution: .anonymous(deviceID: Self.deviceID),
            capturedAt: Date()
        )), photos: 2)
        #expect(OutboxCopy.detail(for: visit) == "2 photos")

        // D4: a hazard never reaches a surface that is not the owner's own record. A queue is a
        // list, so the category is not printed on it.
        let reminder = item(.privateReminder(PrivateReminder(
            owner: .device(Self.deviceID),
            treeID: Self.treeID,
            category: .hangingOrBrokenLimb
        )))
        let detail = OutboxCopy.detail(for: reminder)
        #expect(detail?.isEmpty == false)
        #expect(detail?.lowercased().contains("limb") == false)
    }

    // MARK: - Copy

    @Test("nothing on screen 17 says an authority was told anything")
    func copyRules() {
        let everything = [
            OutboxCopy.screenTitle, OutboxCopy.wifiTitle, OutboxCopy.wifiSubtitle,
            OutboxCopy.syncedLabel, OutboxCopy.footnote, OutboxCopy.emptyState,
            OutboxCopy.summary(sent: 14, lost: 0), OutboxCopy.waitingPill(count: 3),
            OutboxFailureReason.expired, OutboxFailureReason.awaitingWifi(photoCount: 2)
        ].joined(separator: " ")

        // ARCHITECTURE §5.4.
        #expect(everything.lowercased().contains("the city") == false)
        #expect(everything.lowercased().contains("routed to") == false)
        // ARCHITECTURE §5.7.
        #expect(everything.contains(" — ") == false)
        // §6's footnote is the screen's contract and is kept verbatim.
        #expect(
            OutboxCopy.footnote
                == "Nothing here disappears silently. An item that cannot sync says so, says why, and waits for you."
        )
    }

    @Test("every failure sentence this screen can show is a sentence")
    func everyReasonSaysWhy() {
        for error in APIError.allCases {
            for state in [OutboxItem.State.pending, .failed] {
                let sentence = OutboxFailureReason.describe(error: error, failCount: 3, state: state)
                #expect(sentence.isEmpty == false)
                #expect(sentence.contains(" — ") == false)
            }
        }
    }
}
