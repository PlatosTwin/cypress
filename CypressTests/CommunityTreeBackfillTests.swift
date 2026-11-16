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
    /// A day after the first build that could reach the service's sign-in, and still before any
    /// build queued adds: an old tree, whose account ids can be real ones.
    static let afterSignIn = CommunityTreeBackfill.serviceSignInExisted.addingTimeInterval(24 * 60 * 60)
    /// An account this phone made itself in the local-account era (builds 6 to 33).
    static let phoneMade = UUID(uuidString: "0E000000-0000-4000-8000-00000000AA33")!
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

    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        /// 1 on the first call, 2 on the second, and so on.
        func next() -> Int { lock.withLock { count += 1; return count } }
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
        let stopped = try await interrupted.run(identity: phone.signedOut, queue: phone.store.queue)
        #expect(stopped.treesFailed == 1 && stopped.trees == 0, "\(stopped)")
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
        // A real account: its tree and rows date from after the service's sign-in existed.
        let phone = try await Self.phone(userID: Self.accountA)
        let (tree, _) = try await Self.addTree(on: phone, at: Self.afterSignIn)
        _ = try await Self.addRows(
            on: phone, tree: tree.id, owner: Attribution(userID: Self.accountA, deviceID: Self.deviceID), at: Self.afterSignIn
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

    // MARK: - 12. A deleted account's anonymized work

    /// Red-proof: drop the `notAnonymized` clause from `CommunityTreeBackfill.live` — red on the
    /// anonymized visit queued under account B.
    @Test("a deleted account's anonymized rows on an old tree are not sent under the account signed in now")
    func anonymizedRowsAreNeverSent() async throws {
        let phone = try await Self.phone(userID: Self.accountB)
        let (tree, _) = try await Self.addTree(on: phone, at: Self.old)
        try await phone.write { connection in
            let statement = try connection.cachedStatement(
                "UPDATE community_trees SET user_id = :user, device_id = NULL"
            )
            _ = try statement.bind(Self.accountB.uuidString, forName: ":user")
            try statement.run()
            _ = try statement.reset()
        }
        let rows = try await Self.addRows(
            on: phone, tree: tree.id,
            owner: Attribution(userID: Self.accountA, deviceID: Self.deviceID), at: Self.old
        )
        try await phone.write { connection in
            _ = try AccountDeletion().delete(
                userID: Self.accountA, choice: .leaveRecords,
                at: Self.old.addingTimeInterval(3600), connection: connection
            )
        }
        let owners = try await phone.store.queue.read { connection -> (user: UUID?, device: UUID?, tombstoned: Bool) in
            let statement = try connection.cachedStatement("""
                SELECT user_id, device_id,
                       EXISTS (SELECT 1 FROM anonymized_contributions t
                                WHERE t.client_uuid = visits.client_uuid) AS tombstoned
                  FROM visits WHERE id = :id
                """)
            _ = try statement.bind(rows.visitWithPhoto.id, forName: ":id")
            defer { _ = try? statement.reset() }
            return try #require(try statement.fetchOne { row in
                (try row.uuidIfPresent("user_id"), try row.uuidIfPresent("device_id"), try row.bool("tombstoned"))
            })
        }
        #expect(owners.user == nil && owners.device == Self.deviceID && owners.tombstoned,
                "fixture: the leaving door did not leave the visit as this device's, tombstoned")

        let report = try await phone.run(phone.signedIn(Self.accountB))
        let queued = try await phone.outbox()
        let keys = Set(queued.map(\.item.clientUUID))
        for (name, key) in [
            ("visit", rows.visitWithPhoto.clientUUID), ("second visit", rows.otherVisit.clientUUID),
            ("check-in", rows.checkIn.clientUUID), ("measurement", rows.measurement.clientUUID),
            ("care event", rows.care.clientUUID)
        ] {
            #expect(!keys.contains(key), "a deleted account's anonymized \(name) was queued under account B")
        }
        #expect(queued.map(\.item.kind) == [.addTree], "queued \(queued.map(\.item.kind))")
        let stagedVisitPhoto = try await phone.store.queue.read { connection -> Bool in
            let statement = try connection.cachedStatement(
                "SELECT 1 AS p FROM outbox_photos WHERE photo_id = :id COLLATE NOCASE"
            )
            _ = try statement.bind(rows.visitPhotoID, forName: ":id")
            defer { _ = try? statement.reset() }
            return try statement.fetchOne { _ in true } ?? false
        }
        #expect(!stagedVisitPhoto, "a deleted account's anonymized photograph was staged")
        #expect(report.trees == 1, "\(report)")
    }

    /// Red-proof: make `Identity.maySend` answer true when both owners are nil — red on the tree and
    /// on its add photo.
    @Test("an old tree and its add photo whose adder deleted the account are never sent")
    func anAnonymizedTreeAndItsAddPhotoStay() async throws {
        let phone = try await Self.phone(userID: Self.accountA)
        let (tree, _) = try await Self.addTree(on: phone, at: Self.old)
        let addPhoto = try #require(try await Self.addPhotoID(phone, tree.id))
        try await phone.write { connection in
            // As `addTree` would have left it, signed in as A: the tree and its photograph are A's.
            let tree = try connection.cachedStatement("UPDATE community_trees SET user_id = :user, device_id = NULL")
            _ = try tree.bind(Self.accountA.uuidString, forName: ":user")
            try tree.run()
            _ = try tree.reset()
            let photo = try connection.cachedStatement("UPDATE photos SET user_id = :user, device_id = NULL")
            _ = try photo.bind(Self.accountA.uuidString, forName: ":user")
            try photo.run()
            _ = try photo.reset()
            _ = try AccountDeletion().delete(
                userID: Self.accountA, choice: .leaveRecords,
                at: Self.old.addingTimeInterval(3600), connection: connection
            )
        }
        let owners = try await phone.store.queue.read { connection -> [String?] in
            let statement = try connection.cachedStatement("""
                SELECT (SELECT coalesce(user_id, device_id) FROM community_trees) AS tree,
                       (SELECT coalesce(user_id, device_id) FROM photos WHERE id = :photo) AS photo
                """)
            _ = try statement.bind(addPhoto, forName: ":photo")
            defer { _ = try? statement.reset() }
            return try #require(try statement.fetchOne { [try $0.stringIfPresent("tree"), try $0.stringIfPresent("photo")] })
        }
        #expect(owners == [nil, nil], "fixture: the leaving door left an owner on the tree or its photo: \(owners)")

        for identity in [phone.signedOut, phone.signedIn(Self.accountB)] {
            let report = try await phone.run(identity)
            #expect(try await phone.outbox().isEmpty, "an anonymized tree was queued: \(report)")
        }
        #expect(try await !phone.isQueuedOnce(tree.id))
    }

    // MARK: - 13. One tree that fails

    /// Red-proof: take the `do`/`catch` out of `run` — red on the second tree.
    @Test("a tree that fails on every run does not hold back the trees after it, and is tried again")
    func oneFailingTreeDoesNotStopTheOthers() async throws {
        let phone = try await Self.phone()
        let (first, _) = try await Self.addTree(on: phone, at: Self.old)
        let (second, _) = try await Self.addTree(on: phone, at: Self.old.addingTimeInterval(60))
        // Fails only on the first tree. Trees go oldest first, so the first run's first call is the
        // first tree, its second call the second tree, and the second run's only call the first tree.
        let calls = Counter()
        var failing = phone.backfill()
        failing.afterAddRow = {
            if calls.next() != 2 { throw Boom() }
        }
        phone.clock.set(Self.today)
        for _ in 0..<2 {
            let report = try await failing.run(identity: phone.signedOut, queue: phone.store.queue)
            #expect(report.treesFailed <= 1, "\(report)")
        }
        #expect(try await !phone.isQueuedOnce(first.id), "the failing tree was recorded as queued")
        #expect(try await phone.isQueuedOnce(second.id), "the tree after a failing one was never reached")
        let queuedFor = Set(try await phone.outbox().compactMap { try? Self.addition($0).treeID })
        #expect(queuedFor == [second.id], "queued adds for \(queuedFor)")

        // Once it stops failing, the next run sends it.
        try await phone.run(phone.signedOut)
        #expect(try await phone.isQueuedOnce(first.id), "the failed tree was not tried again")
    }

    // MARK: - 14. The added day on an older build's queued add

    /// Red-proof: drop the `addAddedDayIfMissing` call from the `.stageOn` arm — red on the day.
    @Test("an older build's pending add of 23:30 Pacific gets that day before it is sent")
    func aPendingAddGetsItsAddedDay() async throws {
        let phone = try await Self.phone()
        let evening = try #require(ISO8601DateFormatter().date(from: "2026-10-15T06:30:00Z"))
        let (tree, _) = try await Self.addTree(on: phone, at: evening, asOldBuild: false)
        try await phone.write { connection in
            try connection.execute("DELETE FROM outbox_photos")
            try connection.execute("UPDATE outbox SET payload = json_remove(payload, '$.addedOn') WHERE kind = 'add_tree'")
            try connection.execute(
                "DELETE FROM app_state WHERE key LIKE '\(CommunityTreeStore.queuedOnceKeyPrefix)%'"
            )
        }
        let before = try #require(try await phone.outbox().first)
        #expect(try Self.addition(before).addedOn == nil && before.item.state == .pending, "fixture")

        let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
        try await phone.run(phone.signedOut, timeZone: losAngeles)
        let after = try #require(try await phone.outbox().first { $0.id == before.id })
        let addition = try Self.addition(after)
        #expect(addition.addedOn == "2026-10-14", "the pending add's day is \(addition.addedOn ?? "nil")")
        #expect(addition.occurredAt == evening && addition.treeID == tree.id)
        #expect(after.item.state == .pending)
    }

    // MARK: - 15. Photographs that are not JPEGs

    /// Whether this Mac is a virtual machine (`kern.hv_vmm_present`; a simulator process reads its
    /// host's value). The value is printed once, so a CI log shows what the runner answered.
    ///
    /// **Why the HEIC cases need it.** These tests make their HEIC with `CGImageDestinationFinalize`.
    /// CI run 43806821528 (2026-11-16 UTC) was the first to run them on a GitHub runner, which is a
    /// virtual machine with three worker threads. The unit suite stopped a few lines after the three
    /// HEIC-writing cases started: no test finished in 33 minutes and the job was cancelled at its
    /// time limit. The same tree passes on a physical Mac in about 100 s. The log does not name the
    /// call that blocked; three threads and three HEIC writers is the evidence, and a HEIC write
    /// that never returns on a machine with no hardware HEVC encoder is the likely cause. So on a
    /// virtual machine no test here writes a HEIC. The PNG case still runs there, and it takes the
    /// same path through the code under test (a file that is not a JPEG is sent as a JPEG copy).
    /// What CI then does not cover is reading a HEIC; that is covered on a physical Mac only
    /// (ROADMAP 161).
    static let onAVirtualMachine: Bool = {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let read = sysctlbyname("kern.hv_vmm_present", &value, &size, nil, 0)
        print("CYPRESS-TEST: kern.hv_vmm_present read=\(read) value=\(value)")
        return read == 0 && value == 1
    }()

    /// The picked-photo types the two parameterized tests run: HEIC and PNG on a physical Mac, PNG
    /// alone on a virtual machine.
    static var pickedTypes: [UTType] { onAVirtualMachine ? [.png] : [.heic, .png] }

    /// A real HEIC or PNG, 400 × 300, with a GPS fix, a capture time and orientation 6 (the way an
    /// iPhone stores a portrait photograph).
    static func image(_ type: UTType, at url: URL) throws -> URL {
        let jpeg = try PhotoMetadataTests.cameraJPEG()
        let source = try #require(CGImageSourceCreateWithData(jpeg as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let destination = try #require(
            CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil),
            "this simulator cannot write \(type.identifier)"
        )
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination), "fixture: \(type.identifier) not written")
        return url
    }

    /// Fact-finding for the library path: a HEIC goes through the ingest that `VisitAddTreeModel`
    /// uses (`PhotoBinary.write`) and comes out a HEIC, which is not a JPEG.
    @Test(
        "a HEIC through the ingest stays a HEIC, so it is not a JPEG",
        .enabled(
            if: !CommunityTreeBackfillTests.onAVirtualMachine,
            "writing a HEIC stalls on a virtual machine (CI run 43806821528)"
        )
    )
    func aHEICStaysAHEICThroughTheIngest() throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cypress-139-heic-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let heic = try Self.image(.heic, at: folder.appendingPathComponent("pick.heic"))
        let staged = folder.appendingPathComponent("staged")
        try PhotoBinary.write(try Data(contentsOf: heic), strippingMetadataTo: staged)
        let type = CGImageSourceCreateWithURL(staged as CFURL, nil).flatMap(CGImageSourceGetType) as String?
        #expect(type == UTType.heic.identifier, "the ingest wrote \(type ?? "nil")")
        #expect(!PhotoBinary.isJPEG(atPath: staged.path))
    }

    /// Red-proof: make `sendableFile` require a JPEG again — red on "not staged"; and drop the JPEG
    /// copy from `APIOutboxSendSink.uploadPhoto` — red on the sent type.
    @Test(
        "an add photo picked as HEIC or PNG is staged and sent as a clean, upright JPEG",
        arguments: CommunityTreeBackfillTests.pickedTypes
    )
    func aLibraryAddPhotoIsSentAsAJPEG(_ type: UTType) async throws {
        let phone = try await Self.phone()
        let (tree, _) = try await Self.addTree(on: phone, at: Self.old)
        let addPhoto = try #require(try await Self.addPhotoID(phone, tree.id))
        let stored = try await phone.store.queue.read { connection -> String in
            let statement = try connection.cachedStatement("SELECT local_path FROM photos WHERE id = :id")
            _ = try statement.bind(addPhoto, forName: ":id")
            defer { _ = try? statement.reset() }
            return try #require(try statement.fetchOne { try $0.string("local_path") })
        }
        let original = URL(fileURLWithPath: stored)
        try FileManager.default.removeItem(at: original)
        _ = try Self.image(type, at: original)
        let originalBytes = try Data(contentsOf: original)
        #expect(!PhotoBinary.isJPEG(atPath: stored), "fixture: the add photo is a JPEG")

        try await phone.run(phone.signedOut)
        let add = try #require(try await phone.outbox().first { $0.item.kind == .addTree })
        let row = try #require(try await phone.sendable(add.id).first, "the \(type.identifier) add photo was not staged")

        let serviceID = UUID()
        let destination = URL(string: "https://storage.invalid/photos/\(serviceID.uuidString).jpg?sig=139\(type.preferredFilenameExtension ?? "")")!
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
        let sent = phone.folder.appendingPathComponent("sent-\(UUID().uuidString)")
        try #require(put.body).write(to: sent)
        #expect(PhotoBinary.isJPEG(atPath: sent.path), "the \(type.identifier) add photo was sent as it is, not as a JPEG")
        #expect(!PhotoBinary.carriesIdentifyingMetadata(atPath: sent.path), "the sent file still says where or when")
        let properties = try #require(
            CGImageSourceCreateWithURL(sent as CFURL, nil)
                .flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }
        )
        #expect(properties[kCGImagePropertyOrientation] as? Int == 6, "the sent file lost which way up it goes")
        #expect(PhotoBinary.pixelSize(atPath: sent.path).map { [$0.width, $0.height] } == [400, 300])
        #expect(try Data(contentsOf: original) == originalBytes, "the person's own file was changed")
    }

    /// Red-proof: make `sendableFile` require a JPEG again — red on "not staged on the add".
    @Test(
        "a new tree whose photo was picked as HEIC or PNG queues it on its add",
        arguments: CommunityTreeBackfillTests.pickedTypes
    )
    func aNewTreeWithALibraryPhotoQueuesIt(_ type: UTType) async throws {
        let phone = try await Self.phone()
        phone.clock.set(Self.later)
        let picked = try Self.image(type, at: phone.folder.appendingPathComponent("pick-\(UUID().uuidString)"))
        // What `VisitAddTreeModel.apply` does with the picker's bytes.
        let staged = phone.folder.appendingPathComponent("staged-\(UUID().uuidString)")
        try PhotoBinary.write(try Data(contentsOf: picked), strippingMetadataTo: staged)
        #expect(!PhotoBinary.isJPEG(atPath: staged.path), "fixture: the ingest made a JPEG")

        let tree = try await phone.api.addTree(TreeDraft(
            coordinate: phone.clock.nextSpot(),
            photoLocalPath: staged.path,
            attribution: .anonymous(deviceID: Self.deviceID)
        ))
        let add = try #require(try await phone.outbox().first { $0.item.kind == .addTree })
        let addPhoto = try #require(try await Self.addPhotoID(phone, tree.id), "the add stored no photograph")
        #expect(try await phone.sendable(add.id).map(\.id) == [addPhoto],
                "the \(type.identifier) add photo was not staged on the add")
    }

    /// Red-proof: drop the `sendableFile` check on the add photo in `queueTree` — red on the staged
    /// photograph.
    @Test("an old tree whose add photo file is gone is queued without it")
    func aMissingAddPhotoIsNotStaged() async throws {
        let phone = try await Self.phone()
        let (tree, _) = try await Self.addTree(on: phone, at: Self.old)
        let stored = try await phone.store.queue.read { connection -> String in
            let statement = try connection.cachedStatement(
                "SELECT local_path FROM photos WHERE tree_uuid = :tree COLLATE NOCASE AND visit_id IS NULL"
            )
            _ = try statement.bind(tree.id.uuidString, forName: ":tree")
            defer { _ = try? statement.reset() }
            return try #require(try statement.fetchOne { try $0.string("local_path") })
        }
        try FileManager.default.removeItem(atPath: stored)

        let report = try await phone.run(phone.signedOut)
        let add = try #require(try await phone.outbox().first { $0.item.kind == .addTree })
        #expect(try await phone.sendable(add.id).isEmpty, "a missing add photo was staged")
        #expect(report.trees == 1 && report.photos == 0, "\(report)")
    }

    // MARK: - 16. The strip replaces the file in one step

    /// Red-proof: remove the destination before the rename in `PhotoBinary.install` — red on "the
    /// original is gone".
    @Test("a strip that fails at the swap leaves the original photograph in place")
    func aFailedSwapKeepsTheOriginal() throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cypress-139-swap-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("photo.jpg")
        let original = try PhotoMetadataTests.cameraJPEG()
        try original.write(to: file)

        #expect(throws: Boom.self) {
            try PhotoBinary.stripMetadataInPlace(atPath: file.path, rename: { _, _ in throw Boom() })
        }
        #expect(FileManager.default.fileExists(atPath: file.path), "the original is gone after a failed swap")
        #expect(try Data(contentsOf: file) == original, "the original changed after a failed swap")
        let left = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(left == ["photo.jpg"], "the failed strip left \(left)")

        // And with the real swap: cleaned, upright, one file.
        try PhotoBinary.stripMetadataInPlace(atPath: file.path)
        #expect(!PhotoBinary.carriesIdentifyingMetadata(atPath: file.path))
        let orientation = CGImageSourceCreateWithURL(file as CFURL, nil)
            .flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }?[kCGImagePropertyOrientation]
        #expect(orientation as? Int == 6)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["photo.jpg"])
    }

    // MARK: - 17. A phone-made account's work (the owner's ruling of 2026-11-15)

    /// The owner of one row, read back from its table.
    static func owner(_ phone: Phone, _ table: String, _ id: UUID) async throws -> UUID? {
        try await phone.store.queue.read { connection in
            let statement = try connection.cachedStatement("SELECT user_id FROM \(table) WHERE id = :id COLLATE NOCASE")
            _ = try statement.bind(id.uuidString, forName: ":id")
            defer { _ = try? statement.reset() }
            return try statement.fetchOne { try $0.uuidIfPresent("user_id") } ?? nil
        }
    }

    /// The five rows `addRows` writes that a run sends, by client key.
    static func sentKeys(_ rows: Rows) -> Set<UUID> {
        [rows.visitWithPhoto.clientUUID, rows.otherVisit.clientUUID, rows.checkIn.clientUUID,
         rows.measurement.clientUUID, rows.care.clientUUID]
    }

    /// Red-proof: skip the `adopt` call in `queueTree` **and** return before the second pass in
    /// `run` — red on the five rows. Either one alone still sends them: the second pass picks up
    /// what the first did not move. (`mayAdopt` answering false does not turn this test red: the
    /// tree here is the device's, and `adopt` does not ask `mayAdopt`.)
    @Test("a phone-made account's rows and photograph on an old tree go out once, under the account signed in now")
    func aPhoneMadeAccountsWorkGoesUnderTheSignedInAccount() async throws {
        let phone = try await Self.phone(userID: Self.accountB)
        let (tree, _) = try await Self.addTree(on: phone, at: Self.old)
        let made = Attribution(userID: Self.phoneMade, deviceID: Self.deviceID)
        let rows = try await Self.addRows(on: phone, tree: tree.id, owner: made, at: Self.old)
        // The same account's visit on a city tree: R77 still holds for it.
        let cityVisit = Visit(treeID: UUID(), attribution: made, capturedAt: Self.old, createdAt: Self.old, updatedAt: Self.old)
        try await phone.write { _ = try ContributionStore().insert(cityVisit, connection: $0) }

        let report = try await phone.run(phone.signedIn(Self.accountB))
        let queued = try await phone.outbox()
        let keys = Set(queued.map(\.item.clientUUID))
        #expect(keys.isSuperset(of: Self.sentKeys(rows)), "a phone-made account's row was not queued: \(report)")
        #expect(!keys.contains(cityVisit.clientUUID), "a city tree's row was queued (R77)")
        #expect(try await Self.owner(phone, "visits", cityVisit.id) == Self.phoneMade, "a city tree's row changed owner")
        for record in queued where record.item.kind != .addTree {
            let body = try RemoteAPI.syncItemBody(for: record.item)
            #expect(body.userID == Self.accountB, "\(record.item.kind) is sent as \(String(describing: body.userID))")
        }
        let visitRow = try #require(queued.first { $0.item.clientUUID == rows.visitWithPhoto.clientUUID })
        #expect(try await phone.sendable(visitRow.id).map(\.id) == [rows.visitPhotoID], "the photograph is not on its visit")
        #expect(try await Self.owner(phone, "visits", rows.visitWithPhoto.id) == Self.accountB, "the visit is not B's on the phone")
        #expect(try await Self.owner(phone, "photos", rows.visitPhotoID) == Self.accountB, "the photograph is not B's on the phone")
        #expect(try await Self.owner(phone, "care_events", rows.care.id) == Self.accountB)
        #expect(try await Self.owner(phone, "measurements", rows.withdrawnMeasurement.id) == Self.phoneMade,
                "a withdrawn row changed owner")

        let again = try await phone.run(phone.signedIn(Self.accountB))
        #expect(again == CommunityTreeBackfill.Report(), "a second run did something: \(again)")
        #expect(try await phone.outbox().count == queued.count)
    }

    /// Red-proof: return before the second pass in `run` (`sentTreesWithPhoneMadeWork`) — red on
    /// "after sign-in".
    @Test("a phone-made account's rows stay on a signed-out phone and go once after sign-in, on a tree already sent")
    func aPhoneMadeAccountsWorkWaitsForASignIn() async throws {
        let phone = try await Self.phone()
        let (tree, _) = try await Self.addTree(on: phone, at: Self.old)
        let rows = try await Self.addRows(
            on: phone, tree: tree.id, owner: Attribution(userID: Self.phoneMade, deviceID: Self.deviceID), at: Self.old
        )

        let signedOut = try await phone.run(phone.signedOut)
        let first = try await phone.outbox()
        #expect(first.map(\.item.kind) == [.addTree], "a signed-out phone sent \(first.map(\.item.kind))")
        #expect(signedOut.rowsSkipped == 5 && signedOut.adopted == 0, "\(signedOut)")
        #expect(try await phone.isQueuedOnce(tree.id), "fixture: the tree did not go")
        #expect(try await Self.owner(phone, "visits", rows.visitWithPhoto.id) == Self.phoneMade)

        let signedIn = try await phone.run(phone.signedIn(Self.accountA))
        let queued = try await phone.outbox()
        let keys = Set(queued.map(\.item.clientUUID))
        #expect(keys.isSuperset(of: Self.sentKeys(rows)), "the rows did not go after sign-in: \(signedIn)")
        #expect(queued.filter { $0.item.kind == .addTree }.count == 1, "the tree's add was queued again")
        let visitRow = try #require(queued.first { $0.item.clientUUID == rows.visitWithPhoto.clientUUID })
        #expect(try await phone.sendable(visitRow.id).map(\.id) == [rows.visitPhotoID], "the photograph did not go with its visit")
        #expect(signedIn.adopted == 6 && signedIn.rows == 5 && signedIn.photos == 1, "\(signedIn)")

        let again = try await phone.run(phone.signedIn(Self.accountA))
        #expect(again == CommunityTreeBackfill.Report(), "a second run did something: \(again)")
        #expect(try await phone.outbox().count == queued.count)
    }

    /// Red-proof: drop `AND julianday(created_at) < julianday(:cutoff)` from the visits arm of
    /// `phoneMadeAccounts` — red on account A's visit.
    @Test("a real account's rows, made after the service's sign-in existed, are not sent under another account")
    func aRealAccountsWorkIsNotAdopted() async throws {
        let phone = try await Self.phone(userID: Self.accountB)
        let (tree, _) = try await Self.addTree(on: phone, at: Self.old)
        let made = try await Self.addRows(
            on: phone, tree: tree.id, owner: Attribution(userID: Self.phoneMade, deviceID: Self.deviceID), at: Self.old
        )
        // Account A signed in on this phone after sign-in existed and visited the same tree.
        let real = Visit(
            treeID: tree.id, attribution: Attribution(userID: Self.accountA, deviceID: Self.deviceID),
            capturedAt: Self.afterSignIn, createdAt: Self.afterSignIn, updatedAt: Self.afterSignIn
        )
        try await phone.write { _ = try ContributionStore().insert(real, connection: $0) }

        try await phone.run(phone.signedIn(Self.accountB))
        let keys = Set(try await phone.outbox().map(\.item.clientUUID))
        #expect(keys.isSuperset(of: Self.sentKeys(made)), "fixture: the phone-made rows did not go")
        #expect(!keys.contains(real.clientUUID), "account A's visit was sent under account B")
        #expect(try await Self.owner(phone, "visits", real.id) == Self.accountA, "account A's visit changed owner")
    }

    /// Red-proof: make `Identity.mayAdopt` answer false — red on "the tree did not go". The
    /// signed-out half has two guards (`run` fills `phoneMade` only for a signed-in identity, and
    /// `mayAdopt` refuses one with no account).
    @Test("a phone-made account's own old tree goes under the signed-in account, never while signed out")
    func aPhoneMadeAccountsTreeGoesUnderTheSignedInAccount() async throws {
        let phone = try await Self.phone()
        let (tree, _) = try await Self.addTree(on: phone, at: Self.old)
        try await phone.write { connection in
            let statement = try connection.cachedStatement(
                "UPDATE community_trees SET user_id = :user, device_id = NULL"
            )
            _ = try statement.bind(Self.phoneMade.uuidString, forName: ":user")
            try statement.run()
            _ = try statement.reset()
            let photo = try connection.cachedStatement("UPDATE photos SET user_id = :user, device_id = NULL")
            _ = try photo.bind(Self.phoneMade.uuidString, forName: ":user")
            try photo.run()
            _ = try photo.reset()
        }
        let signedOut = try await phone.run(phone.signedOut)
        #expect(try await phone.outbox().isEmpty, "a phone-made account's tree went on a signed-out phone")
        #expect(signedOut.treesWaiting == 1, "\(signedOut)")

        try await phone.run(phone.signedIn(Self.accountA))
        let add = try #require(try await phone.outbox().first { $0.item.kind == .addTree }, "the tree did not go")
        #expect(try Self.addition(add).attribution.userID == Self.accountA, "the add is not sent as the signed-in account")
        #expect(try await Self.owner(phone, "community_trees", tree.id) == Self.accountA)
        let addPhoto = try #require(try await Self.addPhotoID(phone, tree.id))
        #expect(try await phone.sendable(add.id).map(\.id) == [addPhoto], "the add photo did not go")
    }

    /// Red-proof: widen `ownedByPhoneMade` to `(user_id IS NULL OR …)` — red on "an anonymized visit
    /// was given an owner": the widened match gives the NULL-owner visit the signed-in account. No
    /// constraint stops that for a visit. Only a row with a single owner column pair (a photograph,
    /// a tree) refuses it through its at-most-one-owner CHECK, when it already has a device owner.
    @Test("an anonymized row stays unsent when a phone-made account's work goes")
    func anAnonymizedRowStaysWhenPhoneMadeWorkGoes() async throws {
        let phone = try await Self.phone(userID: Self.accountB)
        let (tree, _) = try await Self.addTree(on: phone, at: Self.old)
        let made = try await Self.addRows(
            on: phone, tree: tree.id, owner: Attribution(userID: Self.phoneMade, deviceID: Self.deviceID), at: Self.old
        )
        let gone = try await Self.addRows(
            on: phone, tree: tree.id, owner: Attribution(userID: Self.accountA, deviceID: Self.deviceID), at: Self.afterSignIn
        )
        try await phone.write { connection in
            _ = try AccountDeletion().delete(
                userID: Self.accountA, choice: .leaveRecords, at: Self.afterSignIn.addingTimeInterval(3600), connection: connection
            )
        }
        try await phone.run(phone.signedIn(Self.accountB))
        let keys = Set(try await phone.outbox().map(\.item.clientUUID))
        #expect(keys.isSuperset(of: Self.sentKeys(made)), "fixture: the phone-made rows did not go")
        #expect(keys.isDisjoint(with: Self.sentKeys(gone)), "an anonymized row was sent")
        #expect(try await Self.owner(phone, "visits", gone.visitWithPhoto.id) == nil, "an anonymized visit was given an owner")
    }

    /// Red-proof: move only live photographs in `adopt` (put `AND deleted_at IS NULL` back for
    /// photos) — red on the erasing door, which cannot delete a visit that still has the old
    /// account's withdrawn photograph on it (a foreign key).
    @Test("deleting the signed-in account takes the adopted rows with it, by either door")
    func theDeletionDoorsTreatAdoptedRowsAsTheAccounts() async throws {
        for choice in [AccountDeletionChoice.eraseEverything, .leaveRecords] {
            let phone = try await Self.phone(userID: Self.accountB)
            let (tree, _) = try await Self.addTree(on: phone, at: Self.old)
            let made = Attribution(userID: Self.phoneMade, deviceID: Self.deviceID)
            let rows = try await Self.addRows(on: phone, tree: tree.id, owner: made, at: Self.old)
            // A photograph the old account withdrew, on the same visit.
            let withdrawn = Photo(
                treeID: tree.id, visitID: rows.visitWithPhoto.id, storageKey: "\(UUID().uuidString).jpg",
                shotType: .trunk, capturedAt: Self.old, createdAt: Self.old, updatedAt: Self.old
            )
            try await phone.write { connection in
                _ = try ContributionStore().insert(
                    withdrawn, localPath: nil, owner: PhotoOwner(made), takenOnDevice: Self.deviceID, connection: connection
                )
                let statement = try connection.cachedStatement("UPDATE photos SET deleted_at = :at WHERE id = :id")
                _ = try statement.bind([":at": Self.old, ":id": withdrawn.id])
                try statement.run()
                _ = try statement.reset()
            }
            try await phone.run(phone.signedIn(Self.accountB))
            #expect(try await Self.owner(phone, "visits", rows.visitWithPhoto.id) == Self.accountB, "fixture")
            let staged = try await phone.store.queue.read { connection -> Bool in
                let statement = try connection.cachedStatement("SELECT 1 AS p FROM outbox_photos WHERE photo_id = :id COLLATE NOCASE")
                _ = try statement.bind(withdrawn.id, forName: ":id")
                defer { _ = try? statement.reset() }
                return try statement.fetchOne { _ in true } ?? false
            }
            #expect(!staged, "a withdrawn photograph was staged")

            _ = try await phone.api.deleteAccount(choice)
            let state = try await phone.store.queue.read { connection -> (live: Int, tombstoned: Bool, photoOwner: String?) in
                let statement = try connection.cachedStatement("""
                    SELECT (SELECT COUNT(*) FROM visits WHERE id = :visit AND deleted_at IS NULL) AS live,
                           EXISTS (SELECT 1 FROM anonymized_contributions WHERE client_uuid = :client) AS tombstoned,
                           (SELECT coalesce(user_id, device_id) FROM photos WHERE id = :photo) AS photo_owner
                    """)
                _ = try statement.bind([
                    ":visit": rows.visitWithPhoto.id, ":client": rows.visitWithPhoto.clientUUID,
                    ":photo": rows.visitPhotoID
                ])
                defer { _ = try? statement.reset() }
                return try #require(try statement.fetchOne { row in
                    (try row.int("live"), try row.bool("tombstoned"), try row.stringIfPresent("photo_owner"))
                })
            }
            switch choice {
            case .eraseEverything:
                #expect(state.live == 0, "erasing the account kept its adopted visit")
            case .leaveRecords:
                #expect(state.live == 1 && state.tombstoned, "leaving the records did not un-name the adopted visit")
                #expect(state.photoOwner == nil, "leaving the records left an owner on the adopted photograph")
                #expect(try await Self.owner(phone, "visits", rows.visitWithPhoto.id) == nil)
            }
        }
    }

    // MARK: - 18. Real accounts on old rows are not phone-made

    /// Red-proof: drop `AND julianday(updated_at) < julianday(:cutoff)` from both arms of
    /// `phoneMadeAccounts` — red on account A's work adopted under B.
    @Test("a real account that claimed this device's old work is not phone-made, and its tree waits for it")
    func aClaimedRealAccountIsNotPhoneMade() async throws {
        // Signed-out work before real sign-in existed.
        let phone = try await Self.phone()
        let (tree, _) = try await Self.addTree(on: phone, at: Self.old)
        let rows = try await Self.addRows(on: phone, tree: tree.id, owner: .anonymous(deviceID: Self.deviceID), at: Self.old)
        // Real account A signs in later, on a build with no backfill: the claim gives A the tree,
        // the rows and the photographs, keeping their `created_at`.
        phone.clock.set(Self.later)
        try await phone.api.claimDevice(deviceUUID: Self.deviceID, userID: Self.accountA)
        #expect(try await Self.owner(phone, "community_trees", tree.id) == Self.accountA, "fixture: the claim did not give A the tree")
        #expect(try await Self.owner(phone, "visits", rows.visitWithPhoto.id) == Self.accountA, "fixture")
        // A signs out, and B signs in on the same phone.
        try await phone.api.claimDevice(deviceUUID: Self.deviceID, userID: Self.accountB)

        let asB = try await phone.run(phone.signedIn(Self.accountB))
        #expect(asB.adopted == 0, "account A's work was moved to B: \(asB)")
        #expect(try await phone.outbox().isEmpty, "account A's work was queued under B")
        #expect(asB.treesWaiting == 1, "A's tree does not wait for A: \(asB)")
        #expect(try await Self.owner(phone, "visits", rows.visitWithPhoto.id) == Self.accountA, "A's visit changed owner")
        #expect(try await Self.owner(phone, "community_trees", tree.id) == Self.accountA, "A's tree changed owner")

        // A signs in again: the tree and its rows go under A.
        let asA = try await phone.run(phone.signedIn(Self.accountA))
        #expect(asA.trees == 1 && asA.rows == 5 && asA.adopted == 0, "\(asA)")
        let add = try #require(try await phone.outbox().first { $0.item.kind == .addTree })
        #expect(try Self.addition(add).attribution.userID == Self.accountA)
    }

    /// Red-proof: put the `community_trees` arm back into `phoneMadeAccounts` — red on A's tree
    /// adopted under B.
    @Test("a real account that migration v23 wrote onto an old tree is not phone-made")
    func aMigrationStampedRealAccountIsNotPhoneMade() async throws {
        let phone = try await Self.phone()
        let (tree, _) = try await Self.addTree(on: phone, at: Self.old)
        // What v23 writes when real account A is signed in and the old tree has no add row: A as the
        // adder, with the tree's old timestamps left as they were.
        try await phone.write { connection in
            let statement = try connection.cachedStatement(
                "UPDATE community_trees SET user_id = :user, device_id = NULL"
            )
            _ = try statement.bind(Self.accountA.uuidString, forName: ":user")
            try statement.run()
            _ = try statement.reset()
        }
        phone.clock.set(Self.later)
        try await phone.api.claimDevice(deviceUUID: Self.deviceID, userID: Self.accountB)

        let asB = try await phone.run(phone.signedIn(Self.accountB))
        #expect(asB.adopted == 0, "A's v23-stamped tree was moved to B: \(asB)")
        #expect(try await phone.outbox().isEmpty, "A's tree was queued under B")
        #expect(asB.treesWaiting == 1, "\(asB)")
        #expect(try await Self.owner(phone, "community_trees", tree.id) == Self.accountA)
    }

    /// Red-proof: drop `AND julianday(updated_at) < julianday(:cutoff)` from both arms — red on the
    /// edited rows adopted. The stated cost of the `updated_at` test.
    @Test("a phone-made account whose rows were all edited after real sign-in existed is not found, and its work waits")
    func aPhoneMadeAccountEditedLaterWaits() async throws {
        let phone = try await Self.phone(userID: Self.accountB)
        let (tree, _) = try await Self.addTree(on: phone, at: Self.old)
        let rows = try await Self.addRows(
            on: phone, tree: tree.id, owner: Attribution(userID: Self.phoneMade, deviceID: Self.deviceID), at: Self.old
        )
        try await phone.write { connection in
            for table in ["visits", "observations", "measurements", "care_events", "photos"] {
                let statement = try connection.cachedStatement(
                    "UPDATE \(table) SET updated_at = :later WHERE user_id = :user COLLATE NOCASE"
                )
                _ = try statement.bind([":later": Self.afterSignIn, ":user": Self.phoneMade.uuidString])
                try statement.run()
                _ = try statement.reset()
            }
        }

        let report = try await phone.run(phone.signedIn(Self.accountB))
        let keys = Set(try await phone.outbox().map(\.item.clientUUID))
        #expect(report.adopted == 0, "an account with no row last written before real sign-in was adopted: \(report)")
        #expect(keys.isDisjoint(with: Self.sentKeys(rows)), "the edited rows were sent")
        #expect(report.trees == 1 && report.rowsSkipped == 5, "the tree did not go with its rows waiting: \(report)")
        #expect(try await Self.owner(phone, "visits", rows.visitWithPhoto.id) == Self.phoneMade)
    }
}
