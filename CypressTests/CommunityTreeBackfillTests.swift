//
//  CommunityTreeBackfillTests.swift
//  CypressTests
//
//  ROADMAP 139, the phone piece: the community trees the service never received are sent once,
//  with everything on them; every tree sends its add photo; a refused add is sent again once; and
//  the add carries the phone's local added day. `CommunityTreeBackfill`'s header states the rules.
//
//  Every test builds its own phone: an in-memory store, a `LocalAPI` over a photo directory of its
//  own, and a clock it moves. An *old* tree is made the way an old build left one: added through
//  `addTree` on a date before any build queued adds, then its add row and its once-record removed,
//  because no build of that time wrote either.
//

import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Cypress

@Suite("Community trees · the one-time send of trees the service never received (ROADMAP 139)")
struct CommunityTreeBackfillTests {

    static let deviceID = LocationCorrectionTests.deviceID
    static let accountA = LocationCorrectionTests.userID
    static let accountB = UUID(uuidString: "0E000000-0000-4000-8000-0000000C1394")!

    /// Thirty days before any build queued an add, so also before any build could send a photograph.
    static let old = CommunityTreeStore.firstQueuedAddsAt.addingTimeInterval(-30 * 24 * 60 * 60)
    /// Thirty days after builds started queuing adds: a tree the service has.
    static let later = CommunityTreeStore.firstQueuedAddsAt.addingTimeInterval(30 * 24 * 60 * 60)
    /// The day the update runs.
    static let today = Date(timeIntervalSince1970: 1_794_000_000)

    struct Boom: Error {}

    final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Date
        private var spots = 0
        init(_ start: Date) { value = start }
        var now: Date { lock.withLock { value } }
        func set(_ date: Date) { lock.withLock { value = date } }
        /// A fresh spot about 110 m north of the last one. This branch's `addTree` still refuses a
        /// tree within 10 m of another (ROADMAP 140's phone half removes that), so each tree in a
        /// test stands on its own spot.
        func nextSpot() -> Coordinate {
            lock.withLock {
                spots += 1
                return Coordinate(
                    latitude: LocationCorrectionTests.offshore.latitude + Double(spots) * 0.001,
                    longitude: LocationCorrectionTests.offshore.longitude
                )
            }
        }
    }

    struct Phone {
        let store: CypressStore
        let api: LocalAPI
        let clock: Clock
        let folder: URL
        var photos: URL { folder.appendingPathComponent("Photos", isDirectory: true) }

        var signedOut: CommunityTreeBackfill.Identity { .init(userID: nil, deviceID: deviceID) }
        func signedIn(_ user: UUID) -> CommunityTreeBackfill.Identity { .init(userID: user, deviceID: deviceID) }

        func backfill(timeZone: TimeZone = .current) -> CommunityTreeBackfill {
            CommunityTreeBackfill(
                photoDirectory: photos, applicationSupport: folder,
                now: { [clock] in clock.now }, timeZone: { timeZone }
            )
        }

        @discardableResult
        func run(
            _ identity: CommunityTreeBackfill.Identity,
            timeZone: TimeZone = .current
        ) async throws -> CommunityTreeBackfill.Report {
            clock.set(today)
            return try await backfill(timeZone: timeZone).run(identity: identity, queue: store.queue)
        }

        func outbox() async throws -> [OutboxStore.Record] {
            try await store.queue.read { try OutboxStore().allItems(connection: $0) }
        }

        func sendable(_ item: UUID) async throws -> [OutboxStore.PhotoRow] {
            try await store.queue.read { try OutboxStore().sendablePhotos(for: item, connection: $0) }
        }

        func isQueuedOnce(_ tree: UUID) async throws -> Bool {
            try await store.queue.read { try CommunityTreeBackfill.isQueued(treeID: tree, connection: $0) }
        }

        func write(_ body: @escaping (SQLiteConnection) throws -> Void) async throws {
            try await store.queue.write { try body($0) }
        }
    }

    // MARK: - Fixtures

    static func phone(userID: UUID? = nil) async throws -> Phone {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cypress-139-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent("Photos"), withIntermediateDirectories: true
        )
        let store = try await CypressStore.inMemory()
        let clock = Clock(old)
        let api = LocalAPI(
            store: store, deviceID: deviceID, userID: userID,
            photoDirectory: folder.appendingPathComponent("Photos", isDirectory: true),
            applicationSupportDirectory: folder,
            now: { clock.now }
        )
        return Phone(store: store, api: api, clock: clock, folder: folder)
    }

    /// A real JPEG at a fresh path in the phone's folder. `cameraJPEG` carries a GPS fix, a capture
    /// time, camera identity and an orientation tag.
    static func jpeg(in folder: URL, withMetadata: Bool = false) throws -> String {
        let data = withMetadata
            ? try PhotoMetadataTests.cameraJPEG()
            : try PhotoMetadataTests.cameraJPEG(withLocation: false, orientation: nil)
        let path = folder.appendingPathComponent("capture-\(UUID().uuidString).jpg").path
        try data.write(to: URL(fileURLWithPath: path))
        if !withMetadata { try PhotoBinary.stripMetadataInPlace(atPath: path) }
        return path
    }

    /// Adds a tree at `moment` through `addTree`, then removes what this build writes and an older
    /// build did not: the add row (with the add photo staged on it) and the once-record.
    static func addTree(
        on phone: Phone,
        at moment: Date,
        asOldBuild: Bool = true
    ) async throws -> (tree: Tree, clientUUID: UUID) {
        phone.clock.set(moment)
        let clientUUID = UUID()
        let tree = try await phone.api.addTree(TreeDraft(
            clientUUID: clientUUID,
            coordinate: phone.clock.nextSpot(),
            photoLocalPath: try jpeg(in: phone.folder),
            attribution: .anonymous(deviceID: deviceID)
        ))
        if asOldBuild {
            try await phone.write { connection in
                let addRow = try connection.cachedStatement("""
                    DELETE FROM outbox WHERE kind = 'add_tree'
                       AND upper(json_extract(payload, '$.treeID')) = upper(:id)
                    """)
                _ = try addRow.bind(tree.id.uuidString, forName: ":id")
                try addRow.run()
                _ = try addRow.reset()
                let key = try connection.cachedStatement("DELETE FROM app_state WHERE key = :key")
                _ = try key.bind(CommunityTreeStore.queuedOnceKey(treeID: tree.id), forName: ":key")
                try key.run()
                _ = try key.reset()
            }
        }
        return (tree, clientUUID)
    }

    struct Rows {
        let visitWithPhoto: Visit
        let otherVisit: Visit
        let checkIn: TreeObservation
        let measurement: TreeMeasurement
        let withdrawnMeasurement: TreeMeasurement
        let care: CareEvent
        let visitPhotoID: UUID
    }

    /// Two visits (one with a photograph taken before any build could send one), a check-in, a live
    /// and a withdrawn measurement, and a care event, all at `moment`, owned by `owner`.
    static func addRows(
        on phone: Phone, tree: UUID, owner: Attribution, at moment: Date
    ) async throws -> Rows {
        let visit = Visit(treeID: tree, attribution: owner, capturedAt: moment, createdAt: moment, updatedAt: moment)
        let other = Visit(
            treeID: tree, attribution: owner, capturedAt: moment.addingTimeInterval(60),
            createdAt: moment, updatedAt: moment
        )
        let checkIn = TreeObservation(treeID: tree, attribution: owner, capturedAt: moment, createdAt: moment, updatedAt: moment)
        let measurement = TreeMeasurement.dbh(
            treeID: tree, attribution: owner, capturedAt: moment,
            quantity: Quantity(value: 30, unit: .centimeters, method: .tape),
            createdAt: moment, updatedAt: moment
        )
        let withdrawn = TreeMeasurement.dbh(
            treeID: tree, attribution: owner, capturedAt: moment,
            quantity: Quantity(value: 31, unit: .centimeters, method: .tape),
            createdAt: moment, updatedAt: moment, deletedAt: moment
        )
        let care = CareEvent(
            treeID: tree, attribution: owner, capturedAt: moment, actions: [.watered],
            createdAt: moment, updatedAt: moment
        )
        let photo = Photo(
            treeID: tree, visitID: visit.id, storageKey: "\(UUID().uuidString).jpg", shotType: .leaf,
            capturedAt: moment, createdAt: moment, updatedAt: moment
        )
        let bytes = try Data(contentsOf: URL(fileURLWithPath: try jpeg(in: phone.folder)))
        try bytes.write(to: phone.photos.appendingPathComponent(photo.storageKey!))
        try await phone.write { connection in
            let contributions = ContributionStore()
            _ = try contributions.insert(visit, connection: connection)
            _ = try contributions.insert(other, connection: connection)
            _ = try contributions.insert(checkIn, connection: connection)
            _ = try contributions.insert(measurement, connection: connection)
            _ = try contributions.insert(withdrawn, connection: connection)
            _ = try contributions.insert(care, connection: connection)
            _ = try contributions.insert(
                photo, localPath: nil, owner: PhotoOwner(owner), takenOnDevice: deviceID, connection: connection
            )
        }
        return Rows(
            visitWithPhoto: visit, otherVisit: other, checkIn: checkIn, measurement: measurement,
            withdrawnMeasurement: withdrawn, care: care, visitPhotoID: photo.id
        )
    }

    static func addition(_ record: OutboxStore.Record) throws -> TreeAddition {
        guard case let .addTree(addition) = try OutboxPayload.decode(kind: .addTree, from: record.item.payload)
        else { throw Boom() }
        return addition
    }

    static func addPhotoID(_ phone: Phone, _ tree: UUID) async throws -> UUID? {
        try await phone.store.queue.read { connection in
            let statement = try connection.cachedStatement("""
                SELECT id FROM photos WHERE tree_uuid = :tree COLLATE NOCASE AND visit_id IS NULL
                   AND storage_key IS NULL
                """)
            _ = try statement.bind(tree.uuidString, forName: ":tree")
            defer { _ = try? statement.reset() }
            return try statement.fetchOne { try $0.uuid("id") }
        }
    }

    // MARK: - 1. An old tree goes once, with everything on it

    /// Red-proof: drop the `queueRows` call in `CommunityTreeBackfill.queueTree` — red on the kinds.
    @Test("an old tree is queued once, the add first, with its rows and its unsent photographs")
    func anOldTreeIsQueuedOnceWithEverythingOnIt() async throws {
        let phone = try await Self.phone()
        let (tree, clientUUID) = try await Self.addTree(on: phone, at: Self.old)
        let rows = try await Self.addRows(on: phone, tree: tree.id, owner: .anonymous(deviceID: Self.deviceID), at: Self.old)
        // A visit on a city tree, recorded before syncing existed. R77 still holds for it.
        let cityVisit = Visit(treeID: UUID(), attribution: .anonymous(deviceID: Self.deviceID), capturedAt: Self.old)
        try await phone.write { _ = try ContributionStore().insert(cityVisit, connection: $0) }
        #expect(try await phone.outbox().isEmpty, "fixture: an old build's tree has nothing queued")

        let report = try await phone.run(phone.signedOut)

        let queued = try await phone.outbox()
        #expect(queued.first?.item.kind == .addTree, "the add is not first: \(queued.map(\.item.kind))")
        let kinds = queued.map(\.item.kind.rawValue).sorted()
        #expect(kinds == ["add_tree", "care_event", "measurement", "observation", "visit", "visit"],
                "queued \(kinds)")
        let allApplied = queued.allSatisfy { $0.locallyApplied }
        #expect(allApplied, "a backfilled row would be applied a second time")
        let keys = Set(queued.map(\.item.clientUUID))
        #expect(keys.isSuperset(of: [
            clientUUID, rows.visitWithPhoto.clientUUID, rows.otherVisit.clientUUID,
            rows.checkIn.clientUUID, rows.measurement.clientUUID, rows.care.clientUUID
        ]), "a row is not queued under its own client_uuid")
        #expect(!keys.contains(rows.withdrawnMeasurement.clientUUID), "a withdrawn measurement was queued")
        #expect(!keys.contains(cityVisit.clientUUID), "a city tree's old visit was queued (R77)")

        let add = try #require(queued.first)
        let addition = try Self.addition(add)
        #expect(addition.occurredAt == Self.old, "the add is dated \(addition.occurredAt), not the day it was added")
        #expect(addition.addedOn == TreeAddition.addedDay(of: Self.old, in: .current))
        #expect(addition.treeID == tree.id && addition.attribution.deviceID == Self.deviceID)

        let addPhoto = try #require(try await Self.addPhotoID(phone, tree.id))
        let onAdd = try await phone.sendable(add.id)
        #expect(onAdd.map(\.id) == [addPhoto], "the add photo is not staged on the add, keyed by its id")
        #expect(onAdd.first?.capturedAt == Self.old, "the add photo is not dated by its own capture")
        let visitRow = try #require(queued.first { $0.item.clientUUID == rows.visitWithPhoto.clientUUID })
        #expect(try await phone.sendable(visitRow.id).map(\.id) == [rows.visitPhotoID],
                "the visit's old photograph is not staged on its visit")
        #expect(report.trees == 1 && report.adds == 1 && report.rows == 5 && report.photos == 2, "\(report)")
        #expect(try await phone.isQueuedOnce(tree.id))

        // Once: a second run queues nothing.
        let again = try await phone.run(phone.signedOut)
        #expect(again == CommunityTreeBackfill.Report(), "a second run did something: \(again)")
        #expect(try await phone.outbox().count == queued.count)

        // And still nothing once every row is sent and pruned.
        try await phone.write { connection in
            try connection.execute("DELETE FROM outbox_photos")
            try connection.execute("UPDATE outbox SET state = 'done', remote_sent = 1")
            _ = try OutboxStore().pruneCompleted(olderThan: 0, now: Self.today.addingTimeInterval(1), connection: connection)
        }
        #expect(try await phone.outbox().isEmpty, "fixture: the rows were not pruned")
        #expect(try await phone.run(phone.signedOut) == CommunityTreeBackfill.Report())
        #expect(try await phone.outbox().isEmpty, "a pruned tree was queued again")
    }

    // MARK: - 2. A stop in the middle of a tree

    /// Red-proof: write the key before the rows, outside the tree's transaction (in `run`) — red on
    /// "the next run queued".
    @Test("a run stopped after the add row leaves nothing, and the next run sends the tree once")
    func aStopMidTreeFinishesOnTheNextRun() async throws {
        let phone = try await Self.phone()
        let (tree, _) = try await Self.addTree(on: phone, at: Self.old)
        _ = try await Self.addRows(on: phone, tree: tree.id, owner: .anonymous(deviceID: Self.deviceID), at: Self.old)

        var interrupted = phone.backfill()
        interrupted.afterAddRow = { throw Boom() }
        phone.clock.set(Self.today)
        await #expect(throws: Boom.self) {
            try await interrupted.run(identity: phone.signedOut, queue: phone.store.queue)
        }
        #expect(try await phone.outbox().isEmpty, "a stopped tree left rows behind")
        #expect(try await !phone.isQueuedOnce(tree.id), "a stopped tree was recorded as queued")

        try await phone.run(phone.signedOut)
        let queued = try await phone.outbox()
        #expect(queued.count == 6, "the next run queued \(queued.count) rows, want the add and five")
        #expect(Set(queued.map(\.item.clientUUID)).count == queued.count, "a row was queued twice")
        try await phone.run(phone.signedOut)
        #expect(try await phone.outbox().count == 6)
    }

    // MARK: - 3. Trees the service has

    /// Red-proof: make the date arm of the plan `everything: true` for every tree — red on "rows of
    /// a tree the service has were queued".
    @Test("a tree the service already has sends only its add photo, and only once")
    func aTreeTheServiceHasSendsOnlyItsAddPhoto() async throws {
        let phone = try await Self.phone()
        // Added by an older build after adds were queued: its add went, and was pruned.
        let (tree, clientUUID) = try await Self.addTree(on: phone, at: Self.later)
        _ = try await Self.addRows(on: phone, tree: tree.id, owner: .anonymous(deviceID: Self.deviceID), at: Self.later)

        try await phone.run(phone.signedOut)
        let queued = try await phone.outbox()
        #expect(queued.map(\.item.kind) == [.addTree], "rows of a tree the service has were queued: \(queued.map(\.item.kind))")
        #expect(queued.first?.item.clientUUID == clientUUID, "the carrier is not the tree's own add, which the service answers duplicate")
        let addPhoto = try #require(try await Self.addPhotoID(phone, tree.id))
        #expect(try await phone.sendable(try #require(queued.first).id).map(\.id) == [addPhoto])
        #expect(try await phone.run(phone.signedOut) == CommunityTreeBackfill.Report())

        // A tree this build added: its add photo is already on its add row, and the key says so.
        let (fresh, _) = try await Self.addTree(on: phone, at: Self.later, asOldBuild: false)
        try await phone.write { connection in
            try connection.execute("DELETE FROM outbox")
        }
        #expect(try await phone.isQueuedOnce(fresh.id))
        #expect(try await phone.run(phone.signedOut) == CommunityTreeBackfill.Report())
        #expect(try await phone.outbox().isEmpty, "a tree this build added was queued again")

        // An older build's tree whose add photo was withdrawn: nothing to carry, so nothing queued.
        let (bare, _) = try await Self.addTree(on: phone, at: Self.later)
        let barePhoto = try #require(try await Self.addPhotoID(phone, bare.id))
        try await phone.write { connection in
            let statement = try connection.cachedStatement("UPDATE photos SET deleted_at = '2026-10-01T00:00:00Z' WHERE id = :id")
            _ = try statement.bind(barePhoto, forName: ":id")
            try statement.run()
            _ = try statement.reset()
        }
        try await phone.run(phone.signedOut)
        #expect(try await phone.outbox().isEmpty, "a tree with no photograph to send was queued")
        #expect(try await phone.isQueuedOnce(bare.id))
    }

    @Test("a tree whose add row is done is left until the row is pruned")
    func aDoneAddRowIsLeftAlone() async throws {
        let phone = try await Self.phone()
        let (tree, _) = try await Self.addTree(on: phone, at: Self.later, asOldBuild: false)
        try await phone.write { connection in
            try connection.execute("DELETE FROM outbox_photos")
            try connection.execute("UPDATE outbox SET state = 'done', remote_sent = 1")
            try connection.execute(
                "DELETE FROM app_state WHERE key LIKE '\(CommunityTreeStore.queuedOnceKeyPrefix)%'"
            )
        }
        #expect(try await phone.run(phone.signedOut) == CommunityTreeBackfill.Report())
        #expect(try await !phone.isQueuedOnce(tree.id))
    }

    // MARK: - 4. The added day

    /// Red-proof: read `addedOn` from `moment` (the run's clock) instead of the tree's
    /// `created_at` — red on the day ("2026-11-…") and on `occurred_at`.
    @Test("an add made at 23:30 Pacific is sent with that day and its own instant")
    func theAddedDayIsTheLocalDayOfTheAdd() async throws {
        let phone = try await Self.phone()
        // 23:30 on 2026-07-31 in San Francisco is 06:30 UTC on 2026-08-01, before adds were queued.
        let evening = try #require(ISO8601DateFormatter().date(from: "2026-08-01T06:30:00Z"))
        let (tree, _) = try await Self.addTree(on: phone, at: evening)
        let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))

        try await phone.run(phone.signedOut, timeZone: losAngeles)
        let add = try #require(try await phone.outbox().first { $0.item.kind == .addTree })
        let addition = try Self.addition(add)
        #expect(addition.addedOn == "2026-07-31", "addedOn is \(addition.addedOn ?? "nil")")
        #expect(addition.occurredAt == evening)
        let body = try RemoteAPI.syncItemBody(for: add.item)
        #expect(body.occurredAt == evening, "occurred_at is the run's time, not the add's")
        #expect(addition.treeID == tree.id)
    }

    // MARK: - 5. Adds refused under the 10 m rule

    /// Red-proof: drop `.failed where row.code == .conflict` so a refused add is left alone — red on
    /// "the refused add was not retried".
    @Test("an add refused under the 10 m rule is sent again once, and never twice")
    func aRefusedAddIsRetriedOnce() async throws {
        let phone = try await Self.phone()
        let (tree, _) = try await Self.addTree(on: phone, at: Self.later, asOldBuild: false)
        _ = try await Self.addRows(on: phone, tree: tree.id, owner: .anonymous(deviceID: Self.deviceID), at: Self.later)
        // As an older build left it: no add photo staged, no added day, no key, and refused.
        try await phone.write { connection in
            try connection.execute("DELETE FROM outbox_photos")
            try connection.execute("""
                UPDATE outbox SET state = 'failed', fail_count = 1, last_error_code = 'conflict',
                       last_error = 'This couldn''t be sent.',
                       payload = json_remove(payload, '$.addedOn')
                 WHERE kind = 'add_tree'
                """)
            try connection.execute(
                "DELETE FROM app_state WHERE key LIKE '\(CommunityTreeStore.queuedOnceKeyPrefix)%'"
            )
        }
        // A second tree refused for another reason, which would be refused again.
        let (other, _) = try await Self.addTree(on: phone, at: Self.later, asOldBuild: false)
        try await phone.write { connection in
            let statement = try connection.cachedStatement("""
                UPDATE outbox SET state = 'failed', last_error_code = 'validation_failed'
                 WHERE kind = 'add_tree' AND upper(json_extract(payload, '$.treeID')) = upper(:id)
                """)
            _ = try statement.bind(other.id.uuidString, forName: ":id")
            try statement.run()
            _ = try statement.reset()
            try connection.execute(
                "DELETE FROM app_state WHERE key LIKE '\(CommunityTreeStore.queuedOnceKeyPrefix)%'"
            )
        }

        try await phone.run(phone.signedOut)
        let queued = try await phone.outbox()
        let adds = queued.filter { $0.item.kind == .addTree }
        let retried = try #require(adds.first { (try? Self.addition($0).treeID) == tree.id })
        #expect(retried.item.state == .pending, "the refused add was not retried: \(retried.item.state)")
        #expect(retried.item.failCount == 0 && retried.item.lastErrorCode == nil)
        #expect(try Self.addition(retried).addedOn == TreeAddition.addedDay(of: Self.later, in: .current),
                "the retried add carries no added day")
        let addPhoto = try #require(try await Self.addPhotoID(phone, tree.id))
        #expect(try await phone.sendable(retried.id).map(\.id) == [addPhoto], "the retry carries no add photo")
        #expect(queued.filter { $0.item.kind == .visit }.count == 2, "the refused tree's rows were not sent with it")
        let untouched = try #require(adds.first { (try? Self.addition($0).treeID) == other.id })
        #expect(untouched.item.state == .failed, "an add refused for another reason was retried")
        #expect(try await !phone.isQueuedOnce(other.id))

        // Refused again: it stays failed. Once means once.
        try await phone.write { connection in
            let statement = try connection.cachedStatement(
                "UPDATE outbox SET state = 'failed', last_error_code = 'conflict' WHERE id = :id"
            )
            _ = try statement.bind(retried.id, forName: ":id")
            try statement.run()
            _ = try statement.reset()
        }
        let second = try await phone.run(phone.signedOut)
        #expect(second.adds == 0, "a refused add was retried a second time")
        let after = try await phone.outbox().first { $0.id == retried.id }
        #expect(after?.item.state == .failed)
    }

    // MARK: - 6. What leaves the phone

    /// Red-proof: remove the strip from `APIOutboxSendSink.uploadPhoto` — red on the GPS line.
    @Test("an old add photo is sent with no location or time in it, upright, dated by its own capture")
    func theSentBytesCarryNoLocationOrTime() async throws {
        let phone = try await Self.phone()
        let (tree, _) = try await Self.addTree(on: phone, at: Self.old)
        // A build before ERRATA E148's fix kept the camera's file as it was.
        let addPhoto = try #require(try await Self.addPhotoID(phone, tree.id))
        let stored = try await phone.store.queue.read { connection -> String in
            let statement = try connection.cachedStatement("SELECT local_path FROM photos WHERE id = :id")
            _ = try statement.bind(addPhoto, forName: ":id")
            defer { _ = try? statement.reset() }
            return try #require(try statement.fetchOne { try $0.string("local_path") })
        }
        try PhotoMetadataTests.cameraJPEG().write(to: URL(fileURLWithPath: stored))
        #expect(PhotoBinary.carriesIdentifyingMetadata(atPath: stored), "fixture: the file is already clean")

        try await phone.run(phone.signedOut)
        let add = try #require(try await phone.outbox().first { $0.item.kind == .addTree })
        let row = try #require(try await phone.sendable(add.id).first)

        let serviceID = UUID()
        let destination = URL(string: "https://storage.invalid/photos/\(serviceID.uuidString).jpg?sig=139")!
        StubStorageProtocol.park(destination, status: 200)
        let transport = ScriptedTransport()
        transport.answer("POST /photos/begin", with: """
            {"photo_id":"\(serviceID.uuidString)","presigned_put_url":"\(destination.absoluteString)",
             "moderation_state":"approved","approval_reason":"auto_approved_launch"}
            """)
        transport.answer("POST /photos/\(serviceID.uuidString)/received", with: #"{"received":true}"#)
        let sink = APIOutboxSendSink(
            remote: RemoteAPITests.api(transport, session: StubStorageProtocol.session()),
            applicationSupportDirectory: phone.folder
        )
        try await sink.uploadPhoto(row, for: add.item)

        let put = try #require(StubStorageProtocol.requests(to: destination).first { $0.method == "PUT" })
        let sent = try #require(put.body)
        let file = phone.folder.appendingPathComponent("sent.jpg")
        try sent.write(to: file)
        let properties = try #require(
            CGImageSourceCreateWithURL(file as CFURL, nil)
                .flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }
        )
        #expect(properties[kCGImagePropertyGPSDictionary] == nil, "the sent file still says where it was taken")
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        #expect(exif[kCGImagePropertyExifDateTimeOriginal] == nil && tiff[kCGImagePropertyTIFFDateTime] == nil,
                "the sent file still says when it was taken")
        #expect(!PhotoBinary.carriesIdentifyingMetadata(atPath: file.path))
        #expect(properties[kCGImagePropertyOrientation] as? Int == 6, "the sent file lost which way up it goes")

        let begin = try #require(transport.call("POST /photos/begin")?.body)
        let json = try #require(try JSONSerialization.jsonObject(with: begin) as? [String: Any])
        let capturedAt = try #require((json["captured_at"] as? String).flatMap(ISO8601DateFormatter().date(from:)))
        #expect(capturedAt == Self.old, "the begin dates the photograph \(capturedAt), not by its capture")
        #expect((json["client_uuid"] as? String)?.uppercased() == addPhoto.uuidString.uppercased(),
                "the begin is not keyed by the photograph's own id")
    }

    /// Red-proof: drop `where photo.created < Self.photoSendPathExisted` — red on the later photo.
    @Test("a photograph the service may already have is not sent again")
    func aPhotographThatMayHaveBeenSentIsNotSentAgain() async throws {
        let phone = try await Self.phone()
        let (tree, _) = try await Self.addTree(on: phone, at: Self.old)
        let rows = try await Self.addRows(on: phone, tree: tree.id, owner: .anonymous(deviceID: Self.deviceID), at: Self.old)

        // Taken once a build could send photographs, and sent (no queue row is left), on a visit
        // of the old tree. And one the service refused for good.
        func photo(at moment: Date) async throws -> UUID {
            let photo = Photo(
                treeID: tree.id, visitID: rows.otherVisit.id, storageKey: "\(UUID().uuidString).jpg",
                shotType: .trunk, capturedAt: moment, createdAt: moment, updatedAt: moment
            )
            let bytes = try Data(contentsOf: URL(fileURLWithPath: try Self.jpeg(in: phone.folder)))
            try bytes.write(to: phone.photos.appendingPathComponent(photo.storageKey!))
            try await phone.write { connection in
                _ = try ContributionStore().insert(
                    photo, localPath: nil, owner: .device(Self.deviceID), takenOnDevice: Self.deviceID,
                    connection: connection
                )
            }
            return photo.id
        }
        let sentLater = try await photo(at: CommunityTreeBackfill.photoSendPathExisted.addingTimeInterval(60))
        let refused = try await photo(at: Self.old)
        try await phone.write { connection in
            let statement = try connection.cachedStatement("INSERT INTO app_state (key, value) VALUES (:key, 'not_found')")
            _ = try statement.bind(OutboxStore.refusedPhotoKeyPrefix + refused.uuidString, forName: ":key")
            try statement.run()
            _ = try statement.reset()
        }

        try await phone.run(phone.signedOut)
        let visit = try #require(try await phone.outbox().first { $0.item.clientUUID == rows.otherVisit.clientUUID })
        let staged = try await phone.sendable(visit.id).map(\.id)
        #expect(!staged.contains(sentLater), "a photograph a build may have sent was staged again")
        #expect(!staged.contains(refused), "a photograph the service refused for good was staged again")
        #expect(staged.isEmpty, "staged \(staged)")
    }

    // MARK: - 7. Who may be sent for

    /// Red-proof: make `Identity.maySend` answer true for any account — red on "signed out".
    @Test("an account's old tree waits while the phone is signed out, and goes when that account signs in")
    func anAccountsTreeWaitsForItsAccount() async throws {
        let phone = try await Self.phone(userID: Self.accountA)
        let (tree, _) = try await Self.addTree(on: phone, at: Self.old)
        _ = try await Self.addRows(
            on: phone, tree: tree.id, owner: Attribution(userID: Self.accountA, deviceID: Self.deviceID), at: Self.old
        )

        let signedOut = try await phone.run(phone.signedOut)
        #expect(try await phone.outbox().isEmpty, "an account's tree was queued while signed out")
        #expect(signedOut.treesWaiting == 1)
        #expect(try await !phone.isQueuedOnce(tree.id))

        #expect(try await phone.run(phone.signedIn(Self.accountB)).trees == 0)
        #expect(try await phone.outbox().isEmpty, "an account's tree was queued under another account")

        let signedIn = try await phone.run(phone.signedIn(Self.accountA))
        #expect(signedIn.trees == 1 && signedIn.rows == 5, "\(signedIn)")
        let add = try #require(try await phone.outbox().first { $0.item.kind == .addTree })
        #expect(try Self.addition(add).attribution.userID == Self.accountA)
    }

    @Test("a tree with no adder is never sent, and a row of another owner is left behind")
    func anonymizedTreesAndOtherOwnersRowsStay() async throws {
        let phone = try await Self.phone()
        let (anonymized, _) = try await Self.addTree(on: phone, at: Self.old)
        try await phone.write { connection in
            try connection.execute("UPDATE community_trees SET user_id = NULL, device_id = NULL")
        }
        try await phone.run(phone.signedOut)
        #expect(try await phone.outbox().isEmpty, "a tree with no adder was queued")
        #expect(try await !phone.isQueuedOnce(anonymized.id))

        let (tree, _) = try await Self.addTree(on: phone, at: Self.old)
        let rows = try await Self.addRows(
            on: phone, tree: tree.id, owner: Attribution(userID: Self.accountB, deviceID: Self.deviceID), at: Self.old
        )
        let report = try await phone.run(phone.signedOut)
        let keys = Set(try await phone.outbox().map(\.item.clientUUID))
        #expect(!keys.contains(rows.visitWithPhoto.clientUUID), "another account's visit was queued")
        #expect(report.rows == 0 && report.rowsSkipped == 5, "\(report)")
    }

    // MARK: - 8. Rows already queued

    /// Red-proof: stage the visit's photographs whether or not its row was written — red on the
    /// photo count.
    @Test("a visit already in the queue is not queued twice, and its photographs are not staged twice")
    func aVisitAlreadyQueuedIsNotDoubled() async throws {
        let phone = try await Self.phone()
        let (tree, _) = try await Self.addTree(on: phone, at: Self.old)
        let rows = try await Self.addRows(on: phone, tree: tree.id, owner: .anonymous(deviceID: Self.deviceID), at: Self.old)
        let pending = try OutboxPayload.visit(rows.visitWithPhoto).makeItem(createdAt: Self.today)
        try await phone.write { _ = try OutboxStore().enqueueLocallyApplied(pending, connection: $0) }

        try await phone.run(phone.signedOut)
        let queued = try await phone.outbox()
        #expect(queued.filter { $0.item.clientUUID == rows.visitWithPhoto.clientUUID }.count == 1)
        let staged = try await phone.store.queue.read { connection -> Int in
            let statement = try connection.cachedStatement(
                "SELECT COUNT(*) AS n FROM outbox_photos WHERE photo_id = :id COLLATE NOCASE"
            )
            _ = try statement.bind(rows.visitPhotoID, forName: ":id")
            defer { _ = try? statement.reset() }
            return try statement.fetchOne { try $0.int("n") } ?? 0
        }
        #expect(staged == 0, "a photograph was staged on a row this run did not write")
    }

    // MARK: - 9. Move pin, and the deletion doors

    /// Red-proof: drop `if queuedOnce { return true }` — red on "after its add row is pruned".
    @Test("an old tree is offered Move pin once it is queued, and still after its add row is pruned")
    func movePinFollowsTheOneTimeSend() async throws {
        let phone = try await Self.phone()
        let (tree, _) = try await Self.addTree(on: phone, at: Self.old)
        #expect(try await !phone.api.treeProfile(id: tree.id).canMovePin, "fixture: an unsent old tree is offered Move pin")

        try await phone.run(phone.signedOut)
        #expect(try await phone.api.treeProfile(id: tree.id).canMovePin, "a queued old tree is not offered Move pin")

        try await phone.write { connection in
            try connection.execute("DELETE FROM outbox WHERE kind = 'add_tree'")
        }
        #expect(try await phone.api.treeProfile(id: tree.id).canMovePin,
                "an old tree is not offered Move pin after its add row is pruned")
    }

    /// Red-proof: remove the key cleanup from `AccountDeletion.forgetCommunityTrees` — red on the key.
    @Test("erasing an account removes the once-records of the trees it erased")
    func theErasingDoorRemovesTheKeysOfErasedTrees() async throws {
        let phone = try await Self.phone(userID: Self.accountA)
        let (tree, _) = try await Self.addTree(on: phone, at: Self.later, asOldBuild: false)
        #expect(try await phone.isQueuedOnce(tree.id), "fixture: the add wrote no key")

        _ = try await phone.api.deleteAccount(.eraseEverything)
        let remaining = try await phone.store.queue.read { connection -> Int in
            let statement = try connection.cachedStatement(
                "SELECT COUNT(*) AS n FROM community_trees WHERE id = :id COLLATE NOCASE"
            )
            _ = try statement.bind(tree.id.uuidString, forName: ":id")
            defer { _ = try? statement.reset() }
            return try statement.fetchOne { try $0.int("n") } ?? 0
        }
        #expect(remaining == 0, "fixture: the erasing door kept the tree")
        #expect(try await !phone.isQueuedOnce(tree.id), "the erased tree's key outlived it")
    }

    // MARK: - 10. Every new tree sends its add photo

    /// Red-proof: pass `addPhoto: nil` from `LocalAPI.addTree` — red on the staged photo.
    @Test("a new tree is queued with its add photo, its added day and its key, and settles with no sink")
    func aNewTreeSendsItsAddPhoto() async throws {
        let phone = try await Self.phone()
        let (tree, _) = try await Self.addTree(on: phone, at: Self.later, asOldBuild: false)
        let add = try #require(try await phone.outbox().first { $0.item.kind == .addTree })
        let addPhoto = try #require(try await Self.addPhotoID(phone, tree.id))
        #expect(try await phone.sendable(add.id).map(\.id) == [addPhoto], "the add photo is not on the add")
        #expect(try Self.addition(add).addedOn == TreeAddition.addedDay(of: Self.later, in: .current))
        #expect(try await phone.isQueuedOnce(tree.id))

        // No send sink (the UI suite's wiring): the binary is owed nothing, and the add settles.
        let queue = OutboxQueue(
            queue: phone.store.queue, apply: APIOutboxTransport(api: phone.api),
            now: { [clock = phone.clock] in clock.now }
        )
        try await queue.drain()
        let settled = try #require(try await phone.outbox().first { $0.id == add.id })
        #expect(settled.item.state == .done, "the add is \(settled.item.state) with no sink wired")
    }

    // MARK: - 11. Only with the send sink wired

    /// Red-proof: run the backfill in `DataLayer.boot` whatever `access.allowsNetwork` says — red on
    /// "with the gate shut".
    @Test("the launch sends old trees only when the send sink is wired")
    func theLaunchRunsOnlyWithTheSendSink() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cypress-139-boot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("cypress.sqlite")

        func boot(_ access: RemoteAccess) async throws -> DataLayer {
            try await DataLayer.boot(
                databaseURL: url, seedURL: nil,
                baseURL: URL(string: "https://cypress-sync.invalid/api/v1")!,
                transport: access.allowsNetwork ? ScriptedTransport() : nil,
                remoteAccess: access,
                credentials: InMemoryCredentialStore(),
                storageSession: StubStorageProtocol.session()
            )
        }

        let first = try await boot(.disabled)
        let tree = try await first.local.addTree(TreeDraft(
            coordinate: LocationCorrectionTests.offshore,
            photoLocalPath: try Self.jpeg(in: directory),
            attribution: .anonymous(deviceID: first.deviceID)
        ))
        try await first.store.queue.write { connection in
            try connection.execute("DELETE FROM outbox")
            try connection.execute(
                "DELETE FROM app_state WHERE key LIKE '\(CommunityTreeStore.queuedOnceKeyPrefix)%'"
            )
            let statement = try connection.cachedStatement("UPDATE community_trees SET created_at = :old")
            _ = try statement.bind(Self.old, forName: ":old")
            try statement.run()
            _ = try statement.reset()
        }

        let shut = try await boot(.disabled)
        let afterShut = try await shut.store.queue.read { try OutboxStore().allItems(connection: $0) }
        #expect(afterShut.isEmpty, "with the gate shut the launch queued \(afterShut.count) rows")
        #expect(try await shut.store.queue.read { try !CommunityTreeBackfill.isQueued(treeID: tree.id, connection: $0) })

        let live = try await boot(.live)
        let afterLive = try await live.store.queue.read { try OutboxStore().allItems(connection: $0) }
        #expect(afterLive.map(\.item.kind) == [.addTree], "with the sink wired the launch queued \(afterLive.map(\.item.kind))")
        #expect(try await live.store.queue.read { try CommunityTreeBackfill.isQueued(treeID: tree.id, connection: $0) })
    }
}
