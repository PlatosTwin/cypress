import Foundation
import Testing
@testable import Cypress

/// Screen 09, derived — plus the one thing about it that touches the record.
///
/// A care log is thirty seconds long and append-only, so the failure that matters is a chip that was
/// on when the sheet opened: it writes a watering nobody did, and the contributor has to notice a
/// default and undo it inside those thirty seconds.
@Suite("Care log")
struct CareLogTests {

    private static let treeID = UUID(uuidString: "9F3A0000-0000-4000-8000-000000000C09")!
    private static let deviceID = UUID(uuidString: "9F3A0000-0000-4000-8000-0000000000DE")!

    private static func presentation(_ draft: CareLogDraft, name: String? = "Grandmother Cypress")
        -> CareLogPresentation {
        CareLogPresentation(treeDisplayName: name, draft: draft)
    }

    // MARK: - The sheet opens empty

    @Test("a fresh draft has nothing toggled and cannot be saved")
    func opensEmpty() {
        let draft = CareLogDraft()
        #expect(draft.actions.isEmpty)
        #expect(draft.isEmpty)
        #expect(Self.presentation(draft).canSave == false)
        #expect(Self.presentation(draft).chips.allSatisfy { $0.isOn == false })
    }

    @Test("one toggle is enough to save, and turning it off again is not")
    func theSaveGuard() {
        // PROTOTYPE-FLOW §1.3 `logCare`: "Guard: no-op if no care chip is on."
        #expect(Self.presentation(CareLogDraft(actions: [.watered])).canSave)
        #expect(Self.presentation(CareLogDraft(actions: [.watered, .mulched])).canSave)
        #expect(Self.presentation(CareLogDraft(actions: [])).canSave == false)
    }

    // MARK: - The chips

    @Test("the sheet offers the four actions SCREENS.md 09 draws, in its order")
    func drawnChips() {
        #expect(CareLogCopy.drawnActions == [.watered, .mulched, .weeded, .litterCleared])
        #expect(
            Self.presentation(CareLogDraft()).chips.map { CareActionLabel.text(for: $0.action) }
                == ["Watered", "Mulched", "Weeded basin", "Litter cleared"]
        )
        // `staked` stays in the stored vocabulary and off this screen — narrowing `CareAction` to
        // fit one mock would narrow BUILD-PLAN §4's column. See ERRATA (E58).
        #expect(CareAction.allCases.contains(.staked))
        #expect(CareLogCopy.drawnActions.contains(.staked) == false)
    }

    @Test("the record keeps declaration order, not tap order")
    func orderedActionsAreStable() {
        let draft = CareLogDraft(actions: [.litterCleared, .watered, .weeded])
        #expect(draft.orderedActions == [.watered, .weeded, .litterCleared])
    }

    // MARK: - The title

    @Test("the title carries the tree's name, and drops the separator when there is none")
    func title() {
        #expect(Self.presentation(CareLogDraft()).title == "Care log · Grandmother Cypress")
        #expect(Self.presentation(CareLogDraft(), name: nil).title == "Care log")
        #expect(Self.presentation(CareLogDraft(), name: "").title == "Care log")
    }

    // MARK: - Copy

    @Test("the footnote keeps SCREENS.md's wording and its em dash rule")
    func footnote() {
        #expect(CareLogCopy.footnote == "This joins the tree’s care history—separate from health observations.")
        // ARCHITECTURE §5.7: no spaces around em dashes.
        #expect(CareLogCopy.footnote.contains(" — ") == false)
        #expect(CareLogCopy.footnote.contains("—"))
        // ARCHITECTURE §5.4: nothing on this sheet says an authority was told anything.
        let everything = [CareLogCopy.subtitle, CareLogCopy.footnote, CareLogCopy.optionalWell, CareLogCopy.doneCTA]
            .joined(separator: " ")
            .lowercased()
        for forbidden in ["sent to the city", "routed to", "reported to", "notified"] {
            #expect(everything.contains(forbidden) == false)
        }
        // D1: no count of anything a person did.
        for forbidden in ["streak", "points", "rank", "badge", "times", "total"] {
            #expect(everything.contains(forbidden) == false)
        }
    }

    // MARK: - What reaches the record

    @Test("a saved care log is a care event carrying exactly what was toggled")
    func enqueueWritesACareEvent() async throws {
        let store = try await CypressStore.inMemory()
        let queue = OutboxQueue(queue: store.queue, transport: OutboxTestSupport.ScriptedTransport())
        let captured = Date(timeIntervalSince1970: 1_800_000_000)

        let (event, item) = try await CareLogOutboxWriter.enqueue(
            CareLogDraft(actions: [.litterCleared, .watered]),
            treeID: Self.treeID,
            attribution: .anonymous(deviceID: Self.deviceID),
            outbox: queue,
            gpsAccuracyM: 8,
            now: captured
        )

        #expect(event.treeID == Self.treeID)
        #expect(event.actions == [.watered, .litterCleared])
        #expect(event.capturedAt == captured)
        #expect(event.note == nil)
        #expect(event.userID == nil)
        #expect(event.deviceID == Self.deviceID)

        // It is a care event, not an observation: "Care performed and conditions observed stay
        // separate records" (SCREENS.md 09 caption, V-M3). Two tables, two outbox kinds.
        #expect(item.kind == .careEvent)
        #expect(item.clientUUID == event.clientUUID)

        // Durable before anything is attempted (ARCHITECTURE §4).
        let queued = try await store.queue.read { try OutboxStore().allItems(connection: $0) }
        #expect(queued.map(\.item.clientUUID) == [event.clientUUID])
        #expect(queued.map(\.item.kind) == [.careEvent])
    }

    @Test("a blank note is stored as NULL rather than as whitespace")
    func blankNoteIsNull() async throws {
        let store = try await CypressStore.inMemory()
        let queue = OutboxQueue(queue: store.queue, transport: OutboxTestSupport.ScriptedTransport())

        var draft = CareLogDraft(actions: [.mulched])
        draft.note = "   \n "
        let (event, _) = try await CareLogOutboxWriter.enqueue(
            draft,
            treeID: Self.treeID,
            attribution: .anonymous(deviceID: Self.deviceID),
            outbox: queue
        )
        #expect(event.note == nil)
    }
}
