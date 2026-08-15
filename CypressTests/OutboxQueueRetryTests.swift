//
//  OutboxQueueRetryTests.swift
//  CypressTests
//
//  **What screen 17's retry control does, frame by frame** — PR #88's review, finding F1.
//
//  The owner's ruling 3 of 2026-08-14 put the whole stopped-versus-will-retry distinction into the
//  row's own sentence, and kept the retry control on a terminally refused row. The round that
//  implemented it wrote a test for the drawing and none for the control, and the control erased the
//  sentence: `OutboxStore.retry` NULLs `last_error` and `last_error_code`, and until the fix nothing
//  drained afterwards, so the row read `waiting` with no sentence for an unbounded stretch.
//
//  ── Why this is a separate file from `OutboxPresentationTests` ──────────────────────────────────
//  Because the defect is the seam between them. `OutboxPresentationTests` reads a snapshot; every
//  assertion in it is about a row at one instant, and each of those instants was correct.
//  The tests here take the snapshot **repeatedly across an interaction**, which is the only shape
//  that can see a state the screen passes through. A guard that reads one frame of a sequence is
//  green with the defect present — this project's dominant family, reached from a direction its own
//  note does not name.
//
//  These drive `OutboxViewState`, not `OutboxQueue`, deliberately: `queue.retry(id:)` is *supposed*
//  to clear the row, and the view state is where the tap lands and where the repair is.
//

import Foundation
import Testing
@testable import Cypress

@Suite("Screen 17's retry control, across the tap (PR #88 F1)")
@MainActor
struct OutboxQueueRetryTests {

    private static let deviceID = UUID(uuidString: "9F3A0000-0000-4000-8000-0000000000DE")!
    private static let treeID = UUID(uuidString: "9F3A0000-0000-4000-8000-000000000017")!

    /// A queue whose transport can be swapped mid-test, so a retry can meet a different answer from
    /// the one that made the row terminal.
    private static func makeViewState(
        script: OutboxTestSupport.Script
    ) async throws -> (OutboxViewState, OutboxQueue, OutboxTestSupport.Clock) {
        let clock = OutboxTestSupport.Clock()
        let store = try await CypressStore.inMemory()
        let queue = OutboxQueue(
            queue: store.queue,
            apply: OutboxTestSupport.ScriptedTransport(script: script),
            now: clock.closure
        )
        return (OutboxViewState(queue: queue), queue, clock)
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

    private static func row(_ state: OutboxViewState) -> OutboxPresentation.Row? {
        OutboxPresentation(snapshot: state.snapshot).queue.first
    }

    /// **The sequence the reviewer measured, asserted at the frame that was wrong.**
    ///
    /// The middle assertion is the whole test. Before the fix this row reported
    /// `state=waiting isTerminal=false showsRetryButton=false reason=nil`, and stayed there — the
    /// item that could not sync had stopped saying so and stopped saying why (screen 17 §6), while
    /// the header counted it among the things still trying.
    @Test("a tap on a refused row never draws it as waiting with nothing to say")
    func aTapNeverDrawsARefusedRowAsSilentlyWaiting() async throws {
        let (state, queue, clock) = try await Self.makeViewState(script: .allFail(.forbidden))
        try await Self.enqueueMeasurement(on: queue, at: clock.now)
        _ = try await queue.drain()
        await state.refresh()

        let before = try #require(Self.row(state))
        #expect(before.state == .retry)
        #expect(before.isTerminal)
        #expect(before.showsRetryButton)
        #expect(before.reason == OutboxFailureReason.refusedTerminally)

        await state.retry(id: before.id)
        await state.refresh()

        let after = try #require(Self.row(state))
        #expect(
            after.state == .retry,
            """
            after the tap the row draws `\(after.state.rawValue)` with reason \
            \(after.reason ?? "nil"). The service refused this item and nothing has changed its \
            mind; SCREENS.md 17's `waiting` is the word for an item that is still trying, and \
            §6 promises an item that cannot sync says so and says why.
            """
        )
        #expect(after.isTerminal)
        #expect(after.showsRetryButton)
        #expect(
            after.reason == OutboxFailureReason.refusedTerminally,
            "the tap erased the sentence the owner's ruling 3 made the sole carrier of the distinction"
        )
        // And the header pill does not count it among the things still on their way.
        #expect(state.snapshot.waitingCount == 0)
        #expect(state.snapshot.failedCount == 1)
    }

    /// The control's own calibration: the same tap on the same code, with the service now accepting.
    ///
    /// Without this, the assertions above would pass on a build where `retry` did nothing at all —
    /// the row would still read `retry` with its sentence, for the wrong reason. This is the arm
    /// that proves the tap is a real retry rather than a no-op.
    @Test("the same tap really does retry: a refusal that has lifted sends the item")
    func theSameTapReallyRetries() async throws {
        let clock = OutboxTestSupport.Clock()
        let store = try await CypressStore.inMemory()
        let transport = OutboxTestSupport.ScriptedTransport(script: .allFail(.forbidden))
        let queue = OutboxQueue(queue: store.queue, apply: transport, now: clock.closure)
        let state = OutboxViewState(queue: queue)

        try await Self.enqueueMeasurement(on: queue, at: clock.now)
        _ = try await queue.drain()
        await state.refresh()
        let before = try #require(Self.row(state))
        #expect(before.isTerminal)

        await transport.setScript(.allSucceed)
        await state.retry(id: before.id)
        await state.refresh()

        let remaining = Self.row(state)
        #expect(
            remaining == nil,
            "the item is still in the queue after a retry the service accepted: \(String(describing: remaining))"
        )
        #expect(state.snapshot.syncedRecentlyCount == 1)
    }

    /// `retryAll` takes the same path and needs the same guarantee: two refused rows, one tap, and
    /// neither of them is left drawing `waiting` with nothing to say.
    @Test("retry-all leaves no row waiting in silence either")
    func retryAllLeavesNoRowWaitingInSilence() async throws {
        let (state, queue, clock) = try await Self.makeViewState(script: .allFail(.validationFailed))
        try await Self.enqueueMeasurement(on: queue, at: clock.now)
        _ = try await queue.enqueue(
            .visit(Visit(
                treeID: Self.treeID,
                attribution: .anonymous(deviceID: Self.deviceID),
                gpsAccuracyM: 5,
                capturedAt: clock.now
            ))
        )
        _ = try await queue.drain()
        await state.refresh()

        let rows = OutboxPresentation(snapshot: state.snapshot).queue
        #expect(rows.count == 2)
        let allTerminal = rows.allSatisfy { $0.isTerminal }
        #expect(allTerminal)

        await state.retryAll()
        await state.refresh()

        let after = OutboxPresentation(snapshot: state.snapshot).queue
        #expect(after.count == 2)
        for row in after {
            #expect(row.state == .retry, "row \(row.title) draws \(row.state.rawValue) after retry-all")
            #expect(row.reason == OutboxFailureReason.refusedTerminally)
        }
        #expect(state.snapshot.waitingCount == 0)
    }

    /// **The `moderation_rejected` row keeps its own sentence across the tap too** (F2's ruling and
    /// F1's fix, composed). This is the pair the owner split; if a retry re-derived the sentence
    /// from anything other than the code the service answered with, this is where it would show.
    @Test("a moderated row still says it was reviewed after a retry tap")
    func aModeratedRowKeepsItsOwnSentenceAcrossARetry() async throws {
        let (state, queue, clock) = try await Self.makeViewState(script: .allFail(.moderationRejected))
        try await Self.enqueueMeasurement(on: queue, at: clock.now)
        _ = try await queue.drain()
        await state.refresh()

        let before = try #require(Self.row(state))
        #expect(before.reason == OutboxFailureReason.moderationDeclined)

        await state.retry(id: before.id)
        await state.refresh()

        let after = try #require(Self.row(state))
        #expect(after.state == .retry)
        #expect(
            after.reason == OutboxFailureReason.moderationDeclined,
            "after a retry the moderated row reads \(after.reason ?? "nil"), not the sentence the owner ruled for it"
        )
        #expect(after.reason != OutboxFailureReason.refusedTerminally)
    }
}
