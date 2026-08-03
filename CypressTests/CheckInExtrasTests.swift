import Foundation
import Testing
@testable import Cypress

/// Screen 05's photo/note slot, wired (task #169; E25's closure).
///
/// The owner's report: "the add photos/notes does nothing." `CheckInDraft` has carried `note` and
/// `photos` since M1 and `CheckInOutboxWriter` has always written both — only the entrance was
/// missing. These tests assert the stored rows, not the UI: the outbox row a save makes durable,
/// and the observation and photo rows the drain lands on the tree.
@Suite("Check-in extras")
struct CheckInExtrasTests {

    private static let treeID = UUID(uuidString: "9F3A0000-0000-4000-8000-000000000C05")!
    private static let deviceID = UUID(uuidString: "9F3A0000-0000-4000-8000-0000000000DE")!

    // MARK: - The outbox row

    @Test("a check-in with a note and two photos is durable as one row carrying all three")
    @MainActor
    func theOutboxRowCarriesNoteAndPhotos() async throws {
        let store = try await CypressStore.inMemory()
        // A transport that accepts nothing: the enqueue is the whole subject, and the row must be
        // durable *before* any drain is attempted (ARCHITECTURE §4).
        let queue = OutboxQueue(queue: store.queue, transport: OutboxTestSupport.ScriptedTransport())

        var draft = CheckInDraft()
        draft.vitality = .fair
        draft.note = "  Leaning since the storm  "
        draft.photos = [
            OutboxPhoto(
                path: try VisitPhotoStaging.write(
                    try VisitCameraSessionTests.jpeg(width: 40, height: 40),
                    for: UUID(),
                    shotType: .other
                ),
                shotType: .other
            ),
            OutboxPhoto(
                path: try VisitPhotoStaging.write(
                    try VisitCameraSessionTests.jpeg(width: 50, height: 50),
                    for: UUID(),
                    shotType: .other
                ),
                shotType: .other
            ),
        ]

        // The returned item is deliberately dropped: this test reads the row back out of the store
        // below, which is the only copy the sync path will ever see.
        let (observation, _) = try await CheckInOutboxWriter.enqueue(
            draft,
            treeID: Self.treeID,
            attribution: .anonymous(deviceID: Self.deviceID),
            outbox: queue
        )

        // The writer's trim, on the record itself.
        #expect(observation.note == "Leaning since the storm")

        // The stored row: one observation, both binaries riding it, each on its own path.
        let queued = try await store.queue.read { try OutboxStore().allItems(connection: $0) }
        #expect(queued.count == 1)
        let record = try #require(queued.first)
        #expect(record.item.kind == .observation)
        #expect(record.item.clientUUID == observation.clientUUID)
        #expect(record.item.photos.map(\.path) == draft.photos.map(\.path))
        #expect(Set(record.item.photos.map(\.path)).count == 2, "two photos share a staged path")
        #expect(record.item.photos.allSatisfy { $0.shotType == .other })
    }

    // MARK: - Through the model, onto the tree

    @Test("the note and photos set on the model land as stored rows on the tree")
    @MainActor
    func noteAndPhotosRoundTripThroughTheModel() async throws {
        let store = try await CypressStore.inMemory()
        let photoDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cypress-t169-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: photoDirectory) }
        let api = LocalAPI(store: store, deviceID: Self.deviceID, photoDirectory: photoDirectory)
        let outbox = OutboxQueue(queue: store.queue, transport: APIOutboxTransport(api: api))
        let tree = try await Self.addTree(api: api)

        let model = CheckInModel(
            treeID: tree.id,
            api: api,
            outbox: outbox,
            attribution: .anonymous(deviceID: Self.deviceID)
        )
        model.select(vitality: .good)
        model.note = "  New growth on the south side  "
        model.attachPhoto(try VisitCameraSessionTests.jpeg(width: 200, height: 150))
        model.attachPhoto(try VisitCameraSessionTests.jpeg(width: 100, height: 75))
        #expect(model.draft.photos.count == 2)
        await model.save()

        // The observation, read back off the store — a round trip, not an echo.
        let profile = try await api.treeProfile(id: tree.id)
        let observations = profile.observations.items
        #expect(observations.count == 1)
        #expect(observations.first?.note == "New growth on the south side")
        #expect(observations.first?.vitality == .good)

        // The photographs: two rows, uploaded, `.other` with no visit id, real files behind them.
        let photos = profile.photos.items.filter { $0.shotType == .other }
        #expect(photos.count == 2, "the check-in photos did not land: \(photos.count) rows")
        var widths: Set<Int> = []
        for photo in photos {
            #expect(photo.visitID == nil)
            let key = try #require(photo.storageKey, "a check-in photo was never uploaded")
            let url = photoDirectory.appendingPathComponent((key as NSString).lastPathComponent)
            #expect(FileManager.default.fileExists(atPath: url.path), "the stored file is missing")
            let size = try #require(PhotoBinary.pixelSize(atPath: url.path))
            widths.insert(size.width)
        }
        #expect(widths == [200, 100], "the second binary overwrote the first")
    }

    @Test("photos accumulate on the model and removal takes only its own")
    @MainActor
    func photosAccumulateAndRemoveIndividually() async throws {
        let store = try await CypressStore.inMemory()
        let queue = OutboxQueue(queue: store.queue, transport: OutboxTestSupport.ScriptedTransport())
        let model = CheckInModel(
            treeID: Self.treeID,
            api: VisitPreviewAPI(),
            outbox: queue,
            attribution: .anonymous(deviceID: Self.deviceID)
        )

        model.attachPhoto(try VisitCameraSessionTests.jpeg(width: 60, height: 60))
        model.attachPhoto(try VisitCameraSessionTests.jpeg(width: 90, height: 90))
        let paths = model.draft.photos.map(\.path)
        defer { for path in paths { try? FileManager.default.removeItem(atPath: path) } }

        // `#require`, so a regression fails this test rather than crashing the suite on the
        // indexing below.
        try #require(paths.count == 2)
        #expect(Set(paths).count == 2, "two photos share a staged path")

        model.removePhoto(at: 0)
        #expect(model.draft.photos.map(\.path) == [paths[1]])
        model.removePhoto(at: 0)
        #expect(model.draft.photos.isEmpty)
    }

    // MARK: - Fixture

    /// A community tree for the record to hang off — `requireTree` refuses an observation for a
    /// tree that does not exist, and the in-memory store attaches no seed.
    @MainActor
    private static func addTree(api: LocalAPI) async throws -> Tree {
        try await api.addTree(
            TreeDraft(
                coordinate: Coordinate(latitude: 37.7605, longitude: -122.4275),
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
