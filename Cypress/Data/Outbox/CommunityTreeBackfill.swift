//
//  CommunityTreeBackfill.swift
//  Cypress — Data/Outbox
//
//  Sends, once, what this phone holds about its own community trees and never sent (ROADMAP 139).
//
//  ── The rulings this applies ──────────────────────────────────────────────────────────────────
//
//  The owner reversed R77 for community trees on 2026-11-14 ("trees that are community added should
//  make it onto everyone's phone regardless of when they were added") and answered three more
//  questions on 2026-11-15:
//
//  1. A community tree the service never received is sent with everything on it: the tree, its
//     photographs, and every visit, check-in, measurement and care event recorded on it. Rows on a
//     city tree are not covered and stay on the phone (R77).
//  2. It happens automatically, once, after the update.
//  3. A signed-out phone follows the rule a new tree follows.
//  4. "Every tree, new and old": each community tree sends the photograph taken on the Add this
//     tree screen, which no build had ever sent.
//  5. A tree whose add the service refused under the retired 10 m rule is sent again once.
//  6. Each item is an ordinary Outbox row with today's labels. No new wording.
//
//  ── Which trees, and what each one gets ───────────────────────────────────────────────────────
//
//  Only trees in `community_trees` (trees this phone added), live, with an adder, and with no
//  `CommunityTreeStore.queuedOnceKey` yet. The latest `add_tree` row for the tree decides the rest:
//
//  - **No row, added before `CommunityTreeStore.firstQueuedAddsAt`** (an *old* tree): no build ever
//    queued its add. It gets a new add row, its add photo, every live row on it, and every old
//    photograph on it (below).
//  - **No row, added later**: its add went and the row was pruned, so the service holds the tree
//    without its photograph. It gets a new add row, which the service answers `duplicate`, so the
//    add photo has an item to ride on. Nothing else: its rows were queued when they happened.
//  - **A failed row whose code is `conflict`**: the service refused the add. Under every version of
//    the service an `add_tree` was answered `conflict` only by the 10 m rule, now retired, so this is
//    the one refusal that would not be repeated. The row is retried once, and the tree is treated
//    as an old tree for everything on it.
//  - **A pending or uploading row**: queued by an earlier build, not yet sent. Its add photo is
//    staged on it, and it gets the added day it was queued without.
//  - **A done row, or a failed row with another code**: left alone and not marked. A done row is
//    seen again once it is pruned; a failed one is the person's to retry from the Outbox screen.
//
//  ── Which photographs, and why not the others ─────────────────────────────────────────────────
//
//  A photograph may go only if the service cannot already hold it. The service dedupes a begin on
//  its key, and this phone's key for a photograph is `photos.id`. Builds from the first photo send
//  path until report F30's fix keyed a begin by the queue row's id instead, and that row is gone,
//  so a photograph sent then cannot be recognized and sending it again would make a second copy.
//  So exactly two kinds are sent:
//
//  - **the add photo** of each tree (`visit_id`, `storage_key` NULL, `local_path` set): no build
//    staged it for any send, so the service has none;
//  - **a photograph created before `photoSendPathExisted`**, on an old or refused tree: no build
//    could send anything then.
//
//  Either is skipped while a queue row or a refusal record names it, when its file is missing or is
//  not an image, or when its owner is not one this phone can send for now. A file that is not a JPEG
//  (a HEIC or PNG from the library) is sent as a JPEG copy, and location and time data are stripped,
//  both by the send sink, the last point before the bytes go (`APIOutboxSendSink.uploadPhoto`).
//
//  A row the leaving door of an account deletion anonymized is never sent: it keeps this device's
//  `device_id`, so only its tombstone says it is nobody's (`ContributionStore.notAnonymized`). An
//  anonymized tree or photograph has no owner at all, and `Identity.maySend` refuses it.
//
//  ── Who may be sent for ───────────────────────────────────────────────────────────────────────
//
//  A new tree is attributed to whoever is signed in when it is added, and the drain sends it under
//  whoever is signed in when it drains. Signed out, that is this device, and the service keeps the
//  tree unpublished until the device is claimed at sign-in. An old tree on this device's adder
//  follows exactly that. An old tree whose adder is an **account** has no new-tree equivalent: a
//  row naming an account sent under the device credential is refused `forbidden`, for good, and
//  sending it as the device instead would let the next account to sign in on this phone claim it.
//  So such a tree, and any row or photograph owned by an account that is not signed in now, waits:
//  nothing is queued and no key is written, and the next run after that account signs in sends it.
//
//  ── Once, and safe to stop at any point ───────────────────────────────────────────────────────
//
//  One write transaction per tree, with the key written last in it. A failure anywhere in a tree
//  rolls back that tree's rows and its key together, so the next run starts the tree from nothing,
//  and the run goes on to the next tree.
//  A tree whose key is written is never looked at again. Done rows do not last (`pruneCompleted`),
//  which is why the record is an `app_state` key rather than the queue itself.
//
//  It runs only with the send sink wired (`DataLayer.boot`): with no sink a row settles `done`
//  without being sent, and the key would record a send that never happened.
//
//  Foundation only.
//

import Foundation

public struct CommunityTreeBackfill: Sendable {

    /// The first moment any build could send a photograph: 2026-08-23 05:57:21 UTC, the date of
    /// commit `79f983b1` ("the send sink gains a photo method"), the first commit with a photo send
    /// path. `build-55`, the first build tag that contains it, is later (2026-08-23 13:51:40 UTC).
    /// The earlier date is used because a photograph created before it cannot have been sent by any
    /// build, which is the one fact this cutoff has to be sure of.
    public static let photoSendPathExisted = Date(timeIntervalSince1970: 1_787_464_641)

    /// Who the drain will send as: the signed-in account, if any, and this installation.
    public struct Identity: Sendable, Equatable {
        public let userID: UUID?
        public let deviceID: UUID

        public init(userID: UUID?, deviceID: UUID) {
            self.userID = userID
            self.deviceID = deviceID
        }

        /// Whether a row owned by `user`/`device` may be sent under this identity without being
        /// refused, and without being claimed by somebody else.
        func maySend(user: UUID?, device: UUID?) -> Bool {
            if let user { return user == userID }
            guard let device else { return false }
            return device == deviceID
        }
    }

    /// What one run queued and what it left waiting.
    public struct Report: Sendable, Equatable {
        /// Trees whose key this run wrote.
        public var trees = 0
        /// Add rows written or retried.
        public var adds = 0
        /// Visits, check-ins, measurements and care events queued.
        public var rows = 0
        /// Photographs staged.
        public var photos = 0
        /// Trees left for a later run because their adder is not this identity.
        public var treesWaiting = 0
        /// Rows on a queued tree left behind because their owner is not this identity.
        public var rowsSkipped = 0
        /// Photographs left behind: missing file, not an image, or another owner.
        public var photosSkipped = 0
        /// Trees whose transaction threw and rolled back; each is tried again on the next run.
        public var treesFailed = 0

        public init() {}

        mutating func absorb(_ other: Report) {
            trees += other.trees
            adds += other.adds
            rows += other.rows
            photos += other.photos
            treesWaiting += other.treesWaiting
            rowsSkipped += other.rowsSkipped
            photosSkipped += other.photosSkipped
            treesFailed += other.treesFailed
        }
    }

    private let photoDirectory: URL
    private let applicationSupport: URL
    private let now: @Sendable () -> Date
    private let timeZone: @Sendable () -> TimeZone
    /// Runs inside a tree's transaction after its add row is written. Only a test sets it, to stop a
    /// run part of the way through a tree.
    var afterAddRow: (@Sendable () throws -> Void)?

    /// - Parameters:
    ///   - photoDirectory: where applied photographs live (`LocalAPI`'s own, `storage_key` names a
    ///     file in it).
    ///   - applicationSupport: this container's Application Support folder, to re-root a stored
    ///     path an app update made stale (`StoredPhotoPath`).
    public init(
        photoDirectory: URL,
        applicationSupport: URL,
        now: @escaping @Sendable () -> Date = { Date() },
        timeZone: @escaping @Sendable () -> TimeZone = { .current }
    ) {
        self.photoDirectory = photoDirectory
        self.applicationSupport = applicationSupport
        self.now = now
        self.timeZone = timeZone
    }

    // MARK: - The new add, for every tree from this build on

    /// Queues one add and its add photo, and records the tree as queued, in the caller's
    /// transaction. `LocalAPI.addTree` calls this for every new tree, and the backfill for an old one.
    ///
    /// - Parameter addPhoto: the photograph taken on the Add this tree screen, already ingested:
    ///   its `photos.id` and the stored path of its file. Staged only when the file is there.
    /// - Returns: the add row's id, or nil when the add was already queued (nothing written).
    @discardableResult
    static func queueAddition(
        _ addition: TreeAddition,
        addPhoto: (id: UUID, path: String)?,
        applicationSupport: URL,
        at date: Date,
        connection: SQLiteConnection
    ) throws -> UUID? {
        let store = OutboxStore()
        let item = try OutboxPayload.addTree(addition).makeItem(createdAt: date)
        guard try store.enqueueLocallyApplied(item, connection: connection) else { return nil }
        if let addPhoto,
           Self.sendableFile(addPhoto.path, applicationSupport: applicationSupport) {
            try store.stageAppliedPhoto(
                photoID: addPhoto.id, for: item.id, shotType: .fullTree,
                containerPath: addPhoto.path, at: date, connection: connection
            )
        }
        try markQueued(treeID: addition.treeID, at: date, connection: connection)
        return item.id
    }

    // MARK: - The run

    /// One pass over every tree this phone added. Cheap when nothing qualifies: one read of
    /// `community_trees` and one key lookup per tree.
    @discardableResult
    public func run(identity: Identity, queue: DatabaseQueue) async throws -> Report {
        let candidates = try await queue.read { connection in
            try Self.candidateTreeIDs(connection: connection)
        }
        var report = Report()
        for treeID in candidates {
            // One tree's failure is that tree's alone. Its transaction rolls back, so it keeps no
            // row and no key, and the next launch tries it again from nothing. The trees after it
            // still go. There is no limit on how often a tree that always fails is tried: each try
            // is one rolled-back transaction at launch, and giving up would need a second record
            // and would leave the tree behind for good, against the owner's ruling.
            do {
                let tree = try await queue.write { connection -> Report in
                    var tree = Report()
                    try queueTree(treeID, identity: identity, report: &tree, connection: connection)
                    return tree
                }
                report.absorb(tree)
            } catch {
                report.treesFailed += 1
            }
        }
        return report
    }

    /// Live trees this phone added, with an adder, and with no key yet.
    static func candidateTreeIDs(connection: SQLiteConnection) throws -> [UUID] {
        let statement = try connection.cachedStatement("""
            SELECT id FROM community_trees
             WHERE deleted_at IS NULL
               AND (user_id IS NOT NULL OR device_id IS NOT NULL)
               AND NOT EXISTS (
                     SELECT 1 FROM app_state
                      WHERE app_state.key = :prefix || upper(community_trees.id)
                   )
             ORDER BY created_at, id
            """)
        _ = try statement.bind(CommunityTreeStore.queuedOnceKeyPrefix, forName: ":prefix")
        return try statement.fetchAll { try $0.uuid("id") }
    }

    /// What the latest `add_tree` row for one tree says.
    private enum AddRow {
        case none
        case waiting(id: UUID)
        case refused(id: UUID, addition: TreeAddition)
        case leftAlone
    }

    private enum Plan {
        /// A new add row; `everything` also queues the rows and old photographs on the tree.
        case newAdd(everything: Bool)
        case stageOn(UUID)
        case retry(UUID)
    }

    /// One tree, inside one transaction. Throws to roll the whole tree back.
    private func queueTree(
        _ treeID: UUID,
        identity: Identity,
        report: inout Report,
        connection: SQLiteConnection
    ) throws {
        // Read again inside the write: two runs (the launch and a sign-in) must not both queue it.
        guard !(try Self.isQueued(treeID: treeID, connection: connection)) else { return }
        guard let tree = try Self.tree(treeID, connection: connection) else { return }
        guard identity.maySend(user: tree.adderUser, device: tree.adderDevice) else {
            report.treesWaiting += 1
            return
        }

        let plan: Plan
        switch try Self.latestAddRow(treeID: treeID, connection: connection) {
        case .none:
            plan = .newAdd(everything: tree.tree.createdAt < CommunityTreeStore.firstQueuedAddsAt)
        case let .waiting(id):
            plan = .stageOn(id)
        case let .refused(id, addition):
            // The refused row names who it was queued for. It is sent as that, so it is checked
            // as that.
            guard identity.maySend(
                user: addition.attribution.userID, device: addition.attribution.deviceID
            ) else {
                report.treesWaiting += 1
                return
            }
            plan = .retry(id)
        case .leftAlone:
            return
        }

        let moment = now()
        let store = OutboxStore()
        let addPhoto = try Self.addPhoto(treeID: treeID, identity: identity, connection: connection)
        var addRowID: UUID?
        var everything = false

        switch plan {
        case let .newAdd(sendsEverything):
            everything = sendsEverything
            // A tree that already reached the service needs a new add only to carry its photograph.
            // With no photograph to send there is nothing to do, and the key says so.
            if !sendsEverything, addPhoto == nil {
                try Self.markQueued(treeID: treeID, at: moment, connection: connection)
                report.trees += 1
                return
            }
            let addition = TreeAddition(
                clientUUID: tree.clientUUID,
                treeID: treeID,
                attribution: Attribution(
                    userID: tree.adderUser, deviceID: tree.adderDevice ?? identity.deviceID
                ),
                coordinate: tree.tree.coordinate,
                address: tree.tree.address,
                placement: tree.tree.placement,
                speciesID: tree.tree.speciesCurrentID,
                landContext: tree.tree.statedLandContext,
                // The instant of the add, not of this run: the service keeps `addedOn` only when it
                // is within a day of this instant's UTC date (`store.addedDay`).
                occurredAt: tree.tree.createdAt,
                addedOn: TreeAddition.addedDay(of: tree.tree.createdAt, in: timeZone())
            )
            let item = try OutboxPayload.addTree(addition).makeItem(createdAt: moment)
            // A tree with no add row has nothing queued under its key. If a row exists anyway the
            // tree is left for the person rather than guessed at.
            guard try store.enqueueLocallyApplied(item, connection: connection) else { return }
            addRowID = item.id
            report.adds += 1

        case let .stageOn(id):
            // Queued by an earlier build, with no added day: the service would then use the UTC
            // date of the add, a day late for an evening add west of Greenwich.
            try Self.addAddedDayIfMissing(id, timeZone: timeZone(), connection: connection)
            addRowID = id

        case let .retry(id):
            everything = true
            try Self.retryRefusedAdd(id, timeZone: timeZone(), at: moment, connection: connection)
            addRowID = id
            report.adds += 1
        }

        try afterAddRow?()

        if let addRowID, let addPhoto {
            if try store.stageAppliedPhoto(
                photoID: addPhoto.id, for: addRowID, shotType: .fullTree,
                containerPath: addPhoto.path, at: moment, connection: connection
            ) {
                report.photos += 1
            }
        }

        if everything {
            let visitRows = try queueRows(
                on: treeID, identity: identity, at: moment, report: &report, connection: connection
            )
            try stageOldPhotos(
                on: treeID, addRowID: addRowID, visitRows: visitRows, identity: identity,
                at: moment, report: &report, connection: connection
            )
        }

        try Self.markQueued(treeID: treeID, at: moment, connection: connection)
        report.trees += 1
    }

    // MARK: - Rows

    /// Queues every live visit, check-in, measurement and care event on the tree, each under its
    /// own `client_uuid`, so the service answers `duplicate` for any it already holds.
    ///
    /// - Returns: the queue row of each visit this wrote, by visit id, for its photographs.
    private func queueRows(
        on treeID: UUID,
        identity: Identity,
        at moment: Date,
        report: inout Report,
        connection: SQLiteConnection
    ) throws -> [UUID: UUID] {
        let store = OutboxStore()
        var visitRows: [UUID: UUID] = [:]

        func queue(_ payload: OutboxPayload, owner: Attribution) throws -> UUID? {
            guard identity.maySend(user: owner.userID, device: owner.deviceID) else {
                report.rowsSkipped += 1
                return nil
            }
            let item = try payload.makeItem(createdAt: moment)
            // Already queued (a visit made in the last day, say): that row sends it, and its
            // photographs are already on it.
            guard try store.enqueueLocallyApplied(item, connection: connection) else { return nil }
            report.rows += 1
            return item.id
        }

        for visit in try Self.live(
            "visits", treeID: treeID, connection: connection, ContributionStore.decodeVisit
        ) {
            if let id = try queue(.visit(visit), owner: visit.attribution) { visitRows[visit.id] = id }
        }
        for observation in try Self.live(
            "observations", treeID: treeID, connection: connection, ContributionStore.decodeObservation
        ) {
            _ = try queue(.observation(observation), owner: observation.attribution)
        }
        for measurement in try Self.live(
            "measurements", treeID: treeID, connection: connection, ContributionStore.decodeMeasurement
        ) {
            _ = try queue(.measurement(measurement), owner: measurement.attribution)
        }
        for careEvent in try Self.live(
            "care_events", treeID: treeID, connection: connection, ContributionStore.decodeCareEvent
        ) {
            _ = try queue(.careEvent(careEvent), owner: careEvent.attribution)
        }
        return visitRows
    }

    /// Live rows of one contribution table on one tree, oldest first.
    private static func live<T>(
        _ table: String,
        treeID: UUID,
        connection: SQLiteConnection,
        _ decode: (SQLiteRow) throws -> T
    ) throws -> [T] {
        // `table` is one of four literals above, never input.
        // Not anonymized: the leaving door of an account deletion keeps a row's `device_id` and
        // records its `client_uuid` in `anonymized_contributions` (ERRATA E157). Without this
        // clause such a row reads as this device's own work and would be sent under whoever is
        // signed in now, and the service would store it as theirs.
        let statement = try connection.cachedStatement("""
            SELECT * FROM \(table)
             WHERE tree_uuid = :tree COLLATE NOCASE AND deleted_at IS NULL
               AND \(ContributionStore.notAnonymized(table))
             ORDER BY captured_at, id
            """)
        _ = try statement.bind(treeID.uuidString, forName: ":tree")
        return try statement.fetchAll(decode)
    }

    // MARK: - Photographs

    /// The tree's add photo, when it is still owed and this phone may send it.
    private static func addPhoto(
        treeID: UUID, identity: Identity, connection: SQLiteConnection
    ) throws -> (id: UUID, path: String)? {
        let statement = try connection.cachedStatement("""
            SELECT id, local_path, user_id, device_id FROM photos
             WHERE tree_uuid = :tree COLLATE NOCASE
               AND visit_id IS NULL AND storage_key IS NULL AND local_path IS NOT NULL
               AND deleted_at IS NULL
               AND \(notQueuedOrRefused)
             ORDER BY created_at, id
             LIMIT 1
            """)
        _ = try statement.bind([
            ":tree": treeID.uuidString, ":refused": OutboxStore.refusedPhotoKeyPrefix
        ])
        let found = try statement.fetchOne { row in
            (
                id: try row.uuid("id"), path: try row.string("local_path"),
                user: try row.uuidIfPresent("user_id"), device: try row.uuidIfPresent("device_id")
            )
        }
        _ = try statement.reset()
        guard let row = found, identity.maySend(user: row.user, device: row.device) else { return nil }
        return (id: row.id, path: row.path)
    }

    /// Stages each photograph on the tree created before any build could send one, on the row it
    /// belongs to: its visit's, or the add's for a photograph with no visit.
    private func stageOldPhotos(
        on treeID: UUID,
        addRowID: UUID?,
        visitRows: [UUID: UUID],
        identity: Identity,
        at moment: Date,
        report: inout Report,
        connection: SQLiteConnection
    ) throws {
        let statement = try connection.cachedStatement("""
            SELECT id, visit_id, storage_key, shot_type, created_at, user_id, device_id FROM photos
             WHERE tree_uuid = :tree COLLATE NOCASE
               AND storage_key IS NOT NULL
               AND deleted_at IS NULL
               AND \(Self.notQueuedOrRefused)
             ORDER BY created_at, id
            """)
        _ = try statement.bind([
            ":tree": treeID.uuidString, ":refused": OutboxStore.refusedPhotoKeyPrefix
        ])
        let photos = try statement.fetchAll { row in
            (
                id: try row.uuid("id"), visit: try row.uuidIfPresent("visit_id"),
                key: try row.string("storage_key"), shot: try row.value("shot_type", ShotType.self),
                created: try row.date("created_at"),
                user: try row.uuidIfPresent("user_id"), device: try row.uuidIfPresent("device_id")
            )
        }
        _ = try statement.reset()

        let store = OutboxStore()
        // Only photographs no build could have sent. A later one was sent, or is still queued, or
        // was sent keyed by a row id this phone no longer holds (before report F30's fix).
        for photo in photos where photo.created < Self.photoSendPathExisted {
            let carrier = photo.visit.flatMap { visitRows[$0] } ?? (photo.visit == nil ? addRowID : nil)
            // `storage_key` is a file name in the photo directory (`LocalAPI.uploadPhoto` writes
            // `lastPathComponent`); anything else is not followed.
            guard let carrier, !photo.key.contains("/"), photo.key != "..",
                  identity.maySend(user: photo.user, device: photo.device)
            else {
                report.photosSkipped += 1
                continue
            }
            let path = photoDirectory.appendingPathComponent(photo.key).path
            guard Self.sendableFile(path, applicationSupport: applicationSupport) else {
                report.photosSkipped += 1
                continue
            }
            if try store.stageAppliedPhoto(
                photoID: photo.id, for: carrier, shotType: photo.shot,
                containerPath: path, at: moment, connection: connection
            ) {
                report.photos += 1
            }
        }
    }

    /// No queue row names the photograph, and the service did not refuse it for good.
    private static let notQueuedOrRefused = """
        NOT EXISTS (SELECT 1 FROM outbox_photos
                     WHERE outbox_photos.photo_id = photos.id COLLATE NOCASE
                        OR outbox_photos.id = photos.id COLLATE NOCASE)
        AND NOT EXISTS (SELECT 1 FROM app_state
                         WHERE app_state.key = :refused || upper(photos.id))
        """

    /// The stored path names an image ImageIO can read on this device today. A file that is not a
    /// JPEG (a HEIC or PNG picked from the library) is sent as a JPEG copy (`APIOutboxSendSink`).
    static func sendableFile(_ stored: String, applicationSupport: URL) -> Bool {
        let resolved = StoredPhotoPath.resolve(stored, applicationSupport: applicationSupport).path
        return FileManager.default.fileExists(atPath: resolved) && PhotoBinary.isReadableImage(atPath: resolved)
    }

    // MARK: - The tree and its add row

    private struct TreeRow {
        let tree: Tree
        let clientUUID: UUID
        let adderUser: UUID?
        let adderDevice: UUID?
    }

    private static func tree(_ id: UUID, connection: SQLiteConnection) throws -> TreeRow? {
        let statement = try connection.cachedStatement("""
            SELECT * FROM community_trees WHERE id = :id COLLATE NOCASE AND deleted_at IS NULL
            """)
        _ = try statement.bind(id.uuidString, forName: ":id")
        let row = try statement.fetchOne { row in
            TreeRow(
                tree: try CommunityTreeStore.decode(row),
                clientUUID: try row.uuid("client_uuid"),
                adderUser: try row.uuidIfPresent("user_id"),
                adderDevice: try row.uuidIfPresent("device_id")
            )
        }
        _ = try statement.reset()
        return row
    }

    private static func latestAddRow(treeID: UUID, connection: SQLiteConnection) throws -> AddRow {
        let statement = try connection.cachedStatement("""
            SELECT id, state, last_error_code, payload FROM outbox
             WHERE kind = 'add_tree'
               AND upper(json_extract(payload, '$.treeID')) = upper(:id)
             ORDER BY seq DESC
             LIMIT 1
            """)
        _ = try statement.bind(treeID.uuidString, forName: ":id")
        let row = try statement.fetchOne { row in
            (
                id: try row.uuid("id"), state: try row.value("state", OutboxItem.State.self),
                code: try row.enumIfPresent("last_error_code", APIError.self),
                payload: try row.string("payload")
            )
        }
        _ = try statement.reset()
        guard let row else { return .none }
        switch row.state {
        case .pending, .uploading:
            return .waiting(id: row.id)
        case .failed where row.code == .conflict:
            return .refused(id: row.id, addition: try Self.addition(row.payload))
        case .failed, .done:
            return .leftAlone
        }
    }

    /// A stored `add_tree` payload, read the way the drain reads it.
    private static func addition(_ payload: String) throws -> TreeAddition {
        guard case let .addTree(addition) = try OutboxPayload.decode(
            kind: .addTree, from: Data(payload.utf8)
        ) else { throw APIError.validationFailed }
        return addition
    }

    /// Puts a refused add back in the queue, with the added day it was queued without.
    ///
    /// The retry button's reset (`OutboxStore.retry`), and `addedOn` set from the add's own
    /// `occurredAt`, which the payload has kept since it was queued.
    private static func retryRefusedAdd(
        _ id: UUID, timeZone: TimeZone, at moment: Date, connection: SQLiteConnection
    ) throws {
        let store = OutboxStore()
        guard try store.retry(id, at: moment, connection: connection) else { return }
        try addAddedDayIfMissing(id, timeZone: timeZone, connection: connection)
    }

    /// Sets `addedOn` on a queued add that has none, from the add's own `occurredAt`.
    private static func addAddedDayIfMissing(
        _ id: UUID, timeZone: TimeZone, connection: SQLiteConnection
    ) throws {
        let read = try connection.cachedStatement("SELECT payload FROM outbox WHERE id = :id")
        _ = try read.bind(id, forName: ":id")
        let payload = try read.fetchOne { try $0.string("payload") }
        _ = try read.reset()
        guard let payload else { return }
        let addition = try Self.addition(payload)
        guard addition.addedOn == nil else { return }
        let update = try connection.cachedStatement("""
            UPDATE outbox SET payload = json_set(payload, '$.addedOn', :day) WHERE id = :id
            """)
        _ = try update.bind([
            ":day": TreeAddition.addedDay(of: addition.occurredAt, in: timeZone), ":id": id
        ])
        try update.run()
        _ = try update.reset()
    }

    // MARK: - The key

    static func isQueued(treeID: UUID, connection: SQLiteConnection) throws -> Bool {
        let statement = try connection.cachedStatement(
            "SELECT 1 AS present FROM app_state WHERE key = :key"
        )
        _ = try statement.bind(CommunityTreeStore.queuedOnceKey(treeID: treeID), forName: ":key")
        let present = try statement.fetchOne { _ in true } ?? false
        _ = try statement.reset()
        return present
    }

    static func markQueued(treeID: UUID, at moment: Date, connection: SQLiteConnection) throws {
        let statement = try connection.cachedStatement("""
            INSERT INTO app_state (key, value) VALUES (:key, :value)
            ON CONFLICT(key) DO NOTHING
            """)
        _ = try statement.bind([
            ":key": CommunityTreeStore.queuedOnceKey(treeID: treeID),
            ":value": ISO8601DateFormatter().string(from: moment)
        ])
        try statement.run()
        _ = try statement.reset()
    }
}
