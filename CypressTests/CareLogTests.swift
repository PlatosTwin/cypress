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

    // MARK: - The photo and note fields (task #147, redesigned under task #168)
    //
    // #147 wired the drawn-but-inert well (E25/E185) behind a reveal tap; the owner's next walk
    // (task #168) flattened the reveal and made photos plural, with the in-app camera as a
    // second source. These tests prove the fields reach the record — several photographs now.

    @Test("the note reaches the care event, trimmed")
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
        model.note = "  Basin was bone dry  "
        await model.save()

        // The fact is read back off the store, not off the draft: a round trip, not an echo.
        let events = try await api.treeProfile(id: tree.id).careEvents.items
        #expect(events.count == 1)
        #expect(events.first?.note == "Basin was bone dry")
        #expect(events.first?.actions == [.watered])
    }

    @Test("two attached photos ride the outbox and land on the tree as two rows")
    @MainActor
    func thePhotosRoundTrip() async throws {
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
        model.attachPhoto(try VisitCameraSessionTests.jpeg(width: 120, height: 80))
        #expect(model.hasPhoto)
        await model.save()

        // Each photograph is its own row on the tree, uploaded — a storage key, a real file —
        // and `.other` with no visit id, which is what distinguishes them from the
        // community-add's own full-tree photo on this same tree.
        let photos = try await api.treeProfile(id: tree.id).photos.items
            .filter { $0.shotType == .other }
        #expect(photos.count == 2, "the care photos did not land: \(photos.count) rows")
        var widths: Set<Int> = []
        for photo in photos {
            #expect(photo.visitID == nil)
            let key = try #require(photo.storageKey, "a care photo was never uploaded")
            let url = photoDirectory.appendingPathComponent((key as NSString).lastPathComponent)
            #expect(FileManager.default.fileExists(atPath: url.path), "the stored file is missing")
            let size = try #require(PhotoBinary.pixelSize(atPath: url.path))
            widths.insert(size.width)
        }
        // Two distinct binaries, not the second overwriting the first (the pre-#168 staging bug
        // a shared path would reintroduce silently).
        #expect(widths == [220, 120])
    }

    @Test("photos accumulate, and removing one removes only that one")
    @MainActor
    func photosAccumulateAndRemoveIndividually() async throws {
        let store = try await CypressStore.inMemory()
        let queue = OutboxQueue(queue: store.queue, transport: OutboxTestSupport.ScriptedTransport())
        let model = CareLogModel(
            treeID: Self.treeID,
            api: VisitPreviewAPI(),
            outbox: queue,
            attribution: .anonymous(deviceID: Self.deviceID)
        )

        model.attachPhoto(try VisitCameraSessionTests.jpeg(width: 60, height: 60))
        model.attachPhoto(try VisitCameraSessionTests.jpeg(width: 90, height: 90))
        defer {
            for path in [model.draft.photos.first?.path, model.draft.photos.last?.path] {
                if let path { try? FileManager.default.removeItem(atPath: path) }
            }
        }

        // "Take one (or multiple)" — two attachments are two staged files on two paths. A shared
        // path would let the drain take siblings out of the outbox row.
        #expect(model.draft.photos.count == 2)
        let paths = model.draft.photos.map(\.path)
        #expect(Set(paths).count == 2, "two photos share a staged path")
        let firstSize = try #require(PhotoBinary.pixelSize(atPath: paths[0]))
        #expect(firstSize.width == 60, "the second attachment overwrote the first")

        // Removal is per photograph and reversible in the only direction that matters: the other
        // attachment stays.
        model.removePhoto(at: 0)
        #expect(model.draft.photos.count == 1)
        #expect(model.draft.photos.first?.path == paths[1])
        model.removePhoto(at: 0)
        #expect(!model.hasPhoto)
    }

    @Test("the strings behind the extras keep the sheet's own rules")
    func openedWellCopy() {
        // The same sweeps the closed sheet's copy passes (ARCHITECTURE §5.4, D1), over the strings
        // the extras block adds — the failure mode R30 records is a word no test was watching.
        let everything = [
            CareLogCopy.notePrompt, ContributionExtrasCopy.takePhoto,
            ContributionExtrasCopy.addFromLibrary, ContributionCameraCopy.doneCTA,
            ContributionCameraCopy.captureFailed,
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
