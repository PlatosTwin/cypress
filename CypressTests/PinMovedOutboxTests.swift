import Foundation
import Testing
@testable import Cypress

/// Screen 17's row for a pin move, in the owner's words of 2026-11-14.
///
/// The owner chose "Pin moved", as in `Pin moved · Grandmother Cypress`, with no second line, and
/// chose that a refused move reads the sentence every other kind reads: "This couldn't be sent."
///
/// Both are driven through a real `OutboxQueue` and `OutboxPresentation`, because the row a person
/// sees is what the drain wrote and what the presentation drew, not a constant read in isolation.
@Suite("Outbox: a pin move")
struct PinMovedOutboxTests {

    private static let deviceID = UUID(uuidString: "C3C00000-0000-4000-8000-0000000000DE")!
    private static let treeID = UUID(uuidString: "C3C00000-0000-4000-8000-000000000017")!
    private static let treeNames = [treeID: "Grandmother Cypress"]

    private static func makeQueue(
        script: OutboxTestSupport.Script
    ) async throws -> (OutboxQueue, OutboxTestSupport.Clock) {
        let clock = OutboxTestSupport.Clock()
        let store = try await CypressStore.inMemory()
        let transport = OutboxTestSupport.ScriptedTransport(script: script)
        return (OutboxQueue(queue: store.queue, apply: transport, now: clock.closure), clock)
    }

    private static func enqueueMove(on queue: OutboxQueue, at moment: Date) async throws {
        _ = try await queue.enqueue(
            .locationCorrection(TreeLocationCorrection(
                id: UUID(),
                clientUUID: UUID(),
                treeID: treeID,
                coordinate: Coordinate(latitude: 37.7600, longitude: -122.5400),
                placement: .contributorPlaced,
                locationAccuracyM: 6,
                attribution: .anonymous(deviceID: deviceID),
                occurredAt: moment
            ))
        )
    }

    @Test("a queued pin move reads \"Pin moved · <name>\" and has no second line")
    func theRowReadsPinMoved() async throws {
        let (queue, clock) = try await Self.makeQueue(script: .allFail(.serverError))
        try await Self.enqueueMove(on: queue, at: clock.now)

        let snapshot = try await queue.snapshot(treeNames: Self.treeNames, syncPhotosOnWifiOnly: true)
        let row = try #require(OutboxPresentation(snapshot: snapshot, now: clock.now).queue.first)

        #expect(row.title == "Pin moved · Grandmother Cypress")
        #expect(row.detail == nil)
        #expect(row.quantity == nil)
        // With no second clause, the time carries no separator in front of it.
        #expect(row.timeText.hasPrefix(OutboxCopy.metaSeparator) == false)
    }

    /// The app owner's words of 2026-11-16: a pin move on a tree with no name reads `Pin moved`
    /// alone, not "Pin moved · Tree". A named tree keeps its name, and every other kind keeps the
    /// fallback. Red-proof: drop the `.locationCorrection` early return from `OutboxCopy.title` — red
    /// on "an unnamed tree's pin move reads Pin moved · Tree".
    @Test("a pin move on a tree with no name reads \"Pin moved\" alone; a named tree and other kinds are unchanged")
    func anUnnamedTreesPinMoveReadsPinMovedAlone() {
        let unnamed = OutboxCopy.title(kind: .locationCorrection, treeName: nil)
        #expect(unnamed == "Pin moved", "an unnamed tree's pin move reads \(unnamed)")
        #expect(OutboxCopy.title(kind: .locationCorrection, treeName: "London plane")
                == "Pin moved · London plane")
        #expect(OutboxCopy.title(kind: .visit, treeName: nil)
                == "Visit · \(TreeProfilePresentation.fallbackTitle)")
    }

    /// The same rule through the screen: a queued pin move whose tree has no resolved name.
    @Test("a queued pin move on a tree with no name reads \"Pin moved\" on screen 17")
    func aQueuedUnnamedPinMoveReadsPinMoved() async throws {
        let (queue, clock) = try await Self.makeQueue(script: .allFail(.serverError))
        try await Self.enqueueMove(on: queue, at: clock.now)

        let snapshot = try await queue.snapshot(treeNames: [:], syncPhotosOnWifiOnly: true)
        let row = try #require(OutboxPresentation(snapshot: snapshot, now: clock.now).queue.first)
        #expect(row.title == "Pin moved", "the row reads \(row.title)")
    }

    /// The service answers a move by somebody who is not the adder with `forbidden`, and a move on
    /// a tree it does not know or has hidden with `not_found`. Both are terminal, and the owner
    /// chose the shared sentence for both rather than a move-specific one.
    @Test(
        "a refused pin move reads the sentence every other kind reads",
        arguments: [APIError.forbidden, APIError.notFound]
    )
    func aRefusedMoveReadsTheSharedSentence(code: APIError) async throws {
        let (queue, clock) = try await Self.makeQueue(script: .allFail(code))
        try await Self.enqueueMove(on: queue, at: clock.now)
        _ = try await queue.drain()

        let snapshot = try await queue.snapshot(treeNames: Self.treeNames, syncPhotosOnWifiOnly: true)
        let row = try #require(OutboxPresentation(snapshot: snapshot, now: clock.now).queue.first)

        #expect(row.title == "Pin moved · Grandmother Cypress")
        #expect(row.state == .retry)
        #expect(row.reason == "This couldn't be sent.")
    }
}
