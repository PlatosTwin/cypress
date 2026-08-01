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

    // MARK: - The opened well (task #147)
    //
    // Owner report, 2026-07-31: "the care log has a space for photo/note but neither can be
    // added." Diagnosis: the drawn-but-inert class — E25 recorded the well with no editor behind
    // it while `CareLogDraft`, the writer and the schema (`care_events.note`, the photo path)
    // could all carry both the whole time. These tests prove the two fields now reach the record.

    @Test("the note typed behind the well reaches the care event, trimmed")
    @MainActor
    func theNoteRoundTrips() async throws {
        let store = try await CypressStore.inMemory()
        let photoDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cypress-t147-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: photoDirectory) }
        let api = LocalAPI(store: store, deviceID: Self.deviceID, photoDirectory: photoDirectory)
        let outbox = OutboxQueue(queue: store.queue, transport: APIOutboxTransport(api: api))
        let tree = try await Self.addTree(api: api)

        let model = CareLogModel(
            treeID: tree.id,
            api: api,
            outbox: outbox,
            attribution: .anonymous(deviceID: Self.deviceID)
        )
        model.toggle(.watered)
        model.isEditingExtras = true
        model.note = "  Basin was bone dry  "
        await model.save()

        // The fact is read back off the store, not off the draft: a round trip, not an echo.
        let events = try await api.treeProfile(id: tree.id).careEvents.items
        #expect(events.count == 1)
        #expect(events.first?.note == "Basin was bone dry")
        #expect(events.first?.actions == [.watered])
    }

    @Test("the photo picked behind the well rides the outbox and lands on the tree")
    @MainActor
    func thePhotoRoundTrips() async throws {
        let store = try await CypressStore.inMemory()
        let photoDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cypress-t147-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: photoDirectory) }
        let api = LocalAPI(store: store, deviceID: Self.deviceID, photoDirectory: photoDirectory)
        let outbox = OutboxQueue(queue: store.queue, transport: APIOutboxTransport(api: api))
        let tree = try await Self.addTree(api: api)

        let model = CareLogModel(
            treeID: tree.id,
            api: api,
            outbox: outbox,
            attribution: .anonymous(deviceID: Self.deviceID)
        )
        model.toggle(.mulched)
        model.attachPhoto(try VisitCameraSessionTests.jpeg(width: 220, height: 160))
        #expect(model.hasPhoto)
        await model.save()

        // The photograph is a row on the tree, uploaded — a storage key, a real file — and it is
        // `.other` with no visit id, which is what distinguishes it from the community-add's own
        // full-tree photo on this same tree.
        let photos = try await api.treeProfile(id: tree.id).photos.items
            .filter { $0.shotType == .other }
        #expect(photos.count == 1, "the care photo did not land: \(photos.count) rows")
        let photo = try #require(photos.first)
        #expect(photo.visitID == nil)
        let key = try #require(photo.storageKey, "the care photo was never uploaded")
        let url = photoDirectory.appendingPathComponent((key as NSString).lastPathComponent)
        #expect(FileManager.default.fileExists(atPath: url.path), "the stored file is missing")
        let size = try #require(PhotoBinary.pixelSize(atPath: url.path))
        #expect(size.width == 220 && size.height == 160)
    }

    @Test("a re-pick replaces the photo, and removing it is a real removal")
    @MainActor
    func thePhotoIsReplaceableAndRemovable() async throws {
        let store = try await CypressStore.inMemory()
        let queue = OutboxQueue(queue: store.queue, transport: OutboxTestSupport.ScriptedTransport())
        let model = CareLogModel(
            treeID: Self.treeID,
            api: VisitPreviewAPI(),
            outbox: queue,
            attribution: .anonymous(deviceID: Self.deviceID)
        )

        model.attachPhoto(try VisitCameraSessionTests.jpeg(width: 60, height: 60))
        let firstPath = try #require(model.draft.photos.first?.path)
        model.attachPhoto(try VisitCameraSessionTests.jpeg(width: 90, height: 90))
        defer { try? FileManager.default.removeItem(atPath: firstPath) }

        // One photograph, one staged file: the sheet's id names the path, so a second pick
        // overwrites rather than accumulating staged bytes nobody references.
        #expect(model.draft.photos.count == 1)
        #expect(model.draft.photos.first?.path == firstPath)
        let size = try #require(PhotoBinary.pixelSize(atPath: firstPath))
        #expect(size.width == 90 && size.height == 90, "the re-pick did not replace the file")

        model.removePhoto()
        #expect(!model.hasPhoto)
        #expect(model.draft.photos.isEmpty)
    }

    @Test("the strings behind the well keep the sheet's own rules")
    func openedWellCopy() {
        // The same sweeps the closed sheet's copy passes (ARCHITECTURE §5.4, D1), over the strings
        // the opened well adds — the failure mode R30 records is a word no test was watching.
        let everything = [
            CareLogCopy.optionalWellHint, CareLogCopy.notePrompt,
            CareLogCopy.addPhoto, CareLogCopy.photoAttached, CareLogCopy.removePhoto,
        ].joined(separator: " ").lowercased()
        for forbidden in ["sent to the city", "routed to", "reported to", "notified"] {
            #expect(everything.contains(forbidden) == false)
        }
        for forbidden in ["streak", "points", "rank", "badge", "total"] {
            #expect(everything.contains(forbidden) == false)
        }
        // One vocabulary for "a sentence you may leave": the prompt is screen 04's, verbatim, read
        // off nothing here because 04's is a literal in its view — this pin is the agreement.
        #expect(CareLogCopy.notePrompt == "Anything worth remembering?")
    }

    // MARK: - Fixtures for the round trips

    /// A community tree for the record to hang off — `requireTree` refuses a care event for a tree
    /// that does not exist, and the in-memory store attaches no seed.
    @MainActor
    private static func addTree(api: LocalAPI) async throws -> Tree {
        try await api.addTree(
            TreeDraft(
                coordinate: Coordinate(latitude: 37.7601, longitude: -122.4271),
                photoLocalPath: try VisitPhotoStaging.write(
                    try VisitCameraSessionTests.jpeg(width: 32, height: 32),
                    for: UUID(),
                    shotType: .fullTree
                ),
                attribution: .anonymous(deviceID: Self.deviceID)
            )
        )
    }
}
