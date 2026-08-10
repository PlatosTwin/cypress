import Foundation
import Testing
@testable import Cypress

/// The outbox drain does two things, and until `AppSchema` v15 they were one thing with one name.
///
/// `DataLayer` wires the queue's transport to `LocalAPI`, so `sync` was simultaneously the *send*
/// and the *local commit*: a visit reaches its tree because a drain called `LocalAPI.sync` →
/// `apply(_:)` → `contributions.insert`, and there is no other path (ERRATA E261 §2). RULINGS R72
/// §1 orders the two — apply first and unconditional, send retryable and injectable — and this
/// suite is the four sentences that ordering has to make true:
///
/// 1. with no send sink wired, nothing observable changed;
/// 2. a send that fails does not take the local write with it, and does not re-run it;
/// 3. nothing is ever offered to a server that this device has not already committed, and the
///    table itself refuses to record otherwise;
/// 4. a v14 database's queued work comes across as locally applied and not remotely sent, which is
///    what it truthfully is.
@Suite("Outbox apply/send split")
struct OutboxApplySendSplitTests {

    // MARK: - Fixtures

    private static let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-0000000000B1")!

    /// A tree to attach contributions to. No seed here, so it is a community add — which
    /// `LocalAPI.requireTree` accepts and an invented UUID does not.
    private static func makeTree(api: LocalAPI) async throws -> Tree {
        try await api.addTree(
            TreeDraft(
                coordinate: Coordinate(latitude: 37.77, longitude: -122.44),
                photoLocalPath: "/tmp/cypress-outbox-split-test.jpg",
                attribution: Attribution.anonymous(deviceID: deviceID)
            )
        )
    }

    /// The real apply sink with a tally on it.
    ///
    /// The tally is the point. `LocalAPI` dedupes on the unique `client_uuid` index, so "the local
    /// write did not happen twice" is *not* provable by counting rows — the row count would be 1
    /// whether the drain re-applied or not, and the assertion would be green with the defect
    /// present. Counting what the sink was **offered** is the question that separates them.
    private actor CountingApply: OutboxTransport {
        private let inner: any OutboxTransport
        private(set) var offered: [UUID] = []

        init(_ inner: any OutboxTransport) { self.inner = inner }

        func sync(_ items: [OutboxItem]) async throws -> [SyncResult] {
            offered.append(contentsOf: items.map(\.clientUUID))
            return try await inner.sync(items)
        }

        func uploadPhoto(_ photo: OutboxPhoto, for item: OutboxItem) async throws {
            try await inner.uploadPhoto(photo, for: item)
        }
    }

    /// A server that has already seen everything. `duplicate` is a success on this side too.
    private struct AlwaysDuplicateSendSink: OutboxSendSink {
        func sync(_ items: [OutboxItem]) async throws -> [SyncResult] {
            items.map { SyncResult(clientUUID: $0.clientUUID, status: .duplicate) }
        }
    }

    // MARK: - 1. With no send sink, nothing changed

    @Test("with no send sink the drain settles an item exactly as it did before the split")
    func noSendSinkIsTodaysBehavior() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let queue = OutboxQueue(queue: store.queue, apply: APIOutboxTransport(api: api))
        let tree = try await Self.makeTree(api: api)

        _ = try await queue.enqueue(
            .visit(Visit(
                treeID: tree.id,
                attribution: Attribution.anonymous(deviceID: Self.deviceID),
                capturedAt: Date()
            ))
        )
        let report = try await queue.drain()

        let record = try #require(try await queue.records().first)
        #expect(record.item.state == .done, "an item did not settle with no send sink wired")
        #expect(record.locallyApplied, "the drain did not record the local commit")
        #expect(!record.remoteSent, "an item was marked sent with nowhere to send it")
        #expect(report.synced == 1)
        #expect(report.sent == 0, "\(report.sent) items were sent with no send sink wired")

        // And the contribution really is on its tree, which is the thing the split exists to keep.
        let held = try await api.deviceContributions()
        #expect(held.visits == 1, "the visit did not reach the local tables")
    }

    // MARK: - 2. A failed send keeps the local write, and does not repeat it

    @Test("a send that fails leaves the contribution on its tree and is retried alone")
    func aFailedSendKeepsTheContributionOnItsTree() async throws {
        let clock = OutboxTestSupport.Clock()
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let apply = CountingApply(APIOutboxTransport(api: api))
        let send = OutboxTestSupport.ScriptedSendSink(script: .connectionDropped)
        let queue = OutboxQueue(queue: store.queue, apply: apply, send: send, now: clock.closure)
        let tree = try await Self.makeTree(api: api)

        let visit = Visit(
            treeID: tree.id,
            attribution: Attribution.anonymous(deviceID: Self.deviceID),
            capturedAt: clock.now
        )
        _ = try await queue.enqueue(.visit(visit))

        // Pass one: the connection is gone. The apply half still ran.
        var report = try await queue.drain()
        #expect(report.sent == 0)
        #expect(report.failedTemporarily == 1, "a dropped send did not leave the item alive")

        var record = try #require(try await queue.records().first)
        #expect(record.locallyApplied, "the local commit was skipped because the network was down")
        #expect(!record.remoteSent)
        #expect(record.item.state == .pending, "the item is \(record.item.state), expected pending")
        #expect(record.item.failCount == 1)

        var held = try await api.deviceContributions()
        #expect(held.visits == 1, "offline, the visit did not reach its tree")

        // Pass two: the network is back. Only the send half is owed.
        await send.setScript(.allSucceed)
        clock.advance(by: 60)
        report = try await queue.drain()
        #expect(report.sent == 1, "the retry did not send the item")
        #expect(report.synced == 1)

        record = try #require(try await queue.records().first)
        #expect(record.item.state == .done)
        #expect(record.remoteSent)

        // The apply sink was offered this mutation once across both passes. A drain that re-applied
        // would still leave one row — `LocalAPI` dedupes — so the tally is the only witness.
        let offered = await apply.offered
        #expect(
            offered == [visit.clientUUID],
            "the apply sink was offered \(offered.count) items across two drains, expected 1"
        )
        held = try await api.deviceContributions()
        #expect(held.visits == 1, "the retry wrote the visit a second time")
    }

    // MARK: - 3. Nothing is sent that was not applied

    @Test("an item the apply sink refused is never offered to the send sink")
    func nothingReachesTheServerThatThisDeviceDidNotCommit() async throws {
        let store = try await CypressStore.inMemory()
        let apply = OutboxTestSupport.ScriptedTransport(script: .connectionDropped)
        let send = OutboxTestSupport.ScriptedSendSink(script: .allSucceed)
        let queue = OutboxQueue(queue: store.queue, apply: apply, send: send)

        _ = try await queue.enqueue(
            .visit(Visit(
                treeID: UUID(),
                attribution: Attribution.anonymous(deviceID: Self.deviceID),
                capturedAt: Date()
            ))
        )
        let report = try await queue.drain()

        let offered = await send.offered
        #expect(offered.isEmpty, "the send sink was offered \(offered.count) uncommitted items")
        #expect(await send.syncCallCount == 0, "the send sink was called with nothing to send")
        #expect(report.sent == 0)

        let record = try #require(try await queue.records().first)
        #expect(!record.locallyApplied)
        #expect(!record.remoteSent)
        #expect(record.item.state == .pending, "a failed apply lost the item")
    }

    @Test("the table refuses a row that claims to have been sent without being applied")
    func theTableItselfRefusesSendBeforeApply() async throws {
        let store = try await CypressStore.inMemory()
        let apply = OutboxTestSupport.ScriptedTransport(script: .connectionDropped)
        let queue = OutboxQueue(queue: store.queue, apply: apply)

        let item = try await queue.enqueue(
            .visit(Visit(
                treeID: UUID(),
                attribution: Attribution.anonymous(deviceID: Self.deviceID),
                capturedAt: Date()
            ))
        )
        _ = try await queue.drain()   // the connection is down, so the row is unapplied

        // The CHECK, by hand — a debugger, or a future statement that forgot the ordering.
        await #expect(throws: (any Error).self) {
            try await store.queue.write { connection in
                try connection.execute("UPDATE outbox SET remote_sent = 1 WHERE id = '\(item.id.uuidString)'")
            }
        }
        #expect(try await Self.remoteSent(of: item.id, in: store) == 0)

        // `markRemotelySent` declines the same row rather than aborting the transaction around it.
        try await store.queue.write { connection in
            try OutboxStore().markRemotelySent(item.id, at: Date(), connection: connection)
        }
        #expect(
            try await Self.remoteSent(of: item.id, in: store) == 0,
            "markRemotelySent marked an unapplied row"
        )

        // The control: the identical statement succeeds the moment the row *is* applied, which is
        // what proves the rejection above came from the ordering rule and not from something else
        // about the row or the statement.
        try await store.queue.write { connection in
            try OutboxStore().markLocallyApplied(item.id, at: Date(), connection: connection)
            try connection.execute("UPDATE outbox SET remote_sent = 1 WHERE id = '\(item.id.uuidString)'")
        }
        #expect(try await Self.remoteSent(of: item.id, in: store) == 1)
    }

    // MARK: - `duplicate` is a success on both sides

    @Test("a server that says duplicate settles the item, and the binaries still go locally")
    func duplicateIsASuccessOnTheSendSideToo() async throws {
        let store = try await CypressStore.inMemory()
        let apply = OutboxTestSupport.ScriptedTransport(script: .allSucceed)
        let queue = OutboxQueue(queue: store.queue, apply: apply, send: AlwaysDuplicateSendSink())

        _ = try await queue.enqueue(
            .visit(Visit(
                treeID: UUID(),
                attribution: Attribution.anonymous(deviceID: Self.deviceID),
                capturedAt: Date()
            )),
            photos: [OutboxPhoto(path: "/tmp/cypress-split-a.jpg", shotType: .fullTree)]
        )
        let report = try await queue.drain()

        let record = try #require(try await queue.records().first)
        #expect(record.item.state == .done, "a duplicate was treated as a failure")
        #expect(record.remoteSent)
        #expect(report.sent == 1)
        // The binary went through the apply sink, which is the only sink that has one.
        #expect(await apply.uploadedPhotoPaths == ["/tmp/cypress-split-a.jpg"])
        #expect(record.item.photos.isEmpty)
    }

    // MARK: - 2b. The photograph is apply-side too

    @Test("a send that fails still commits the photograph, because the binary is apply-side")
    func aFailedSendDoesNotHoldBackThePhotoLocalCommit() async throws {
        let store = try await CypressStore.inMemory()
        let apply = OutboxTestSupport.ScriptedTransport(script: .allSucceed)
        let send = OutboxTestSupport.ScriptedSendSink(script: .connectionDropped)
        let queue = OutboxQueue(queue: store.queue, apply: apply, send: send)

        let photo = OutboxPhoto(path: "/tmp/cypress-split-offline.jpg", shotType: .fullTree)
        _ = try await queue.enqueue(
            .visit(Visit(
                treeID: UUID(),
                attribution: Attribution.anonymous(deviceID: Self.deviceID),
                capturedAt: Date()
            )),
            photos: [photo]
        )

        _ = try await queue.drain(photoUploadsAllowed: true)

        // `apply.uploadPhoto` is the local commit of the photograph, exactly as `apply.sync` is the
        // local commit of the note. Behind the send gate it never ran offline, and 48 h of that
        // expires the row terminally with the binary still staged and nothing referencing it.
        let uploaded = await apply.uploadedPhotoPaths
        #expect(uploaded == [photo.path], "the binary was not offered to the apply sink offline")

        let record = try #require(try await queue.records().first)
        #expect(record.item.photos.isEmpty, "the staged binary is still queued after being ingested")
        #expect(record.locallyApplied)
        #expect(!record.remoteSent, "the send failed, so nothing may claim it was sent")
        #expect(record.item.state == .pending, "the item is \(record.item.state), expected pending")
    }

    @Test("a binary waiting for wi-fi does not hold back the note's send")
    func aDeferredBinaryDoesNotDelayTheJSON() async throws {
        let store = try await CypressStore.inMemory()
        let apply = OutboxTestSupport.ScriptedTransport(script: .allSucceed)
        let send = OutboxTestSupport.ScriptedSendSink(script: .allSucceed)
        let queue = OutboxQueue(queue: store.queue, apply: apply, send: send)

        let photo = OutboxPhoto(path: "/tmp/cypress-split-metered.jpg", shotType: .leaf)
        _ = try await queue.enqueue(
            .visit(Visit(
                treeID: UUID(),
                attribution: Attribution.anonymous(deviceID: Self.deviceID),
                capturedAt: Date()
            )),
            photos: [photo]
        )

        // Metered. BUILD-PLAN §4 and screen 17: notes and numbers sync on any connection; the
        // toggle gates binaries and nothing else. Moving the photo phase ahead of the send is what
        // could have broken this, so it is asserted rather than assumed.
        let report = try await queue.drain(photoUploadsAllowed: false)
        #expect(report.sent == 1, "a deferred binary stopped the note from being sent")
        #expect(report.awaitingWifi == 1)
        #expect(report.synced == 0, "an item waiting for wi-fi was counted as settled")
        #expect(await apply.uploadedPhotoPaths.isEmpty, "a binary went out on a metered connection")

        var record = try #require(try await queue.records().first)
        #expect(record.remoteSent, "the note was not sent while its photograph waited")
        #expect(record.item.state == .pending)
        #expect(record.item.photos.count == 1)
        #expect(record.item.failCount == 0, "waiting for wi-fi counted as a failure")

        // Wi-fi arrives: only the binary is owed, and the server is not asked twice.
        _ = try await queue.drain(photoUploadsAllowed: true)
        record = try #require(try await queue.records().first)
        #expect(record.item.state == .done)
        #expect(await apply.uploadedPhotoPaths == [photo.path])
        #expect(await send.offered.count == 1, "the note was offered to the server twice")
    }

    @Test("binaries are ingested oldest first, like every other phase of a drain")
    func binariesAreIngestedInFIFOOrder() async throws {
        let store = try await CypressStore.inMemory()
        let apply = OutboxTestSupport.ScriptedTransport(script: .allSucceed)
        let queue = OutboxQueue(queue: store.queue, apply: apply)

        // Three visits, enqueued oldest first, each carrying one binary named for its position.
        // `drain()` promises "attempts every due item, oldest first" and phases B and D keep it;
        // the photo phase is the one doing something irreversible — ingesting consumes the staged
        // file — so it is where the wrong order costs the most and shows the least.
        let paths = (0..<3).map { "/tmp/cypress-split-order-\($0).jpg" }
        for (index, path) in paths.enumerated() {
            _ = try await queue.enqueue(
                .visit(Visit(
                    treeID: UUID(),
                    attribution: Attribution.anonymous(deviceID: Self.deviceID),
                    capturedAt: Date(timeIntervalSince1970: 1_800_000_000 + Double(index) * 60)
                )),
                photos: [OutboxPhoto(path: path, shotType: .fullTree)]
            )
        }

        _ = try await queue.drain(photoUploadsAllowed: true)

        let uploaded = await apply.uploadedPhotoPaths
        #expect(uploaded == paths, "binaries were ingested \(uploaded), expected oldest first")
        #expect(try await queue.records().allSatisfy { $0.item.state == .done })
    }

    // MARK: - The composition root itself

    @Test("the shipping composition root wires no send sink")
    func dataLayerWiresNoSendSink() async throws {
        // Not a double: `DataLayer.boot` is the wiring `CypressApp` runs, and one line of it
        // omitting `send:` is the whole of today's safety (ERRATA E261 §2). A test that builds its
        // own `OutboxQueue` proves the queue and not the wiring, so this one reads the real thing.
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cypress-datalayer-sink-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Deliberately not removed on the way out. `DataLayer` holds the SQLite connection past this
        // function's scope, and unlinking the file under an open handle is what prints
        // `BUG IN CLIENT OF libsqlite3.dylib: … vnode unlinked while in use` — the same family as
        // the `SQLITE_IOERR_VNODE` noise this project has already chased once. The directory is a
        // per-run UUID under `NSTemporaryDirectory()`; the simulator sweeps it.

        let data = try await DataLayer.boot(
            databaseURL: directory.appendingPathComponent("cypress.sqlite"),
            seedURL: nil
        )
        let tree = try await data.api.addTree(
            TreeDraft(
                coordinate: Coordinate(latitude: 37.77, longitude: -122.44),
                photoLocalPath: "/tmp/cypress-datalayer-sink.jpg",
                attribution: Attribution.anonymous(deviceID: data.deviceID)
            )
        )
        _ = try await data.outbox.enqueue(
            .visit(Visit(
                treeID: tree.id,
                attribution: Attribution.anonymous(deviceID: data.deviceID),
                capturedAt: Date()
            ))
        )
        let report = try await data.outbox.drain()

        #expect(
            report.sent == 0,
            "DataLayer wired a send sink: \(report.sent) items reached a server that does not exist yet"
        )
        let record = try #require(try await data.outbox.records().first)
        #expect(record.locallyApplied, "the shipping wiring did not commit the contribution locally")
        #expect(!record.remoteSent)
        #expect(record.item.state == .done, "the shipping wiring did not settle an item")
    }

    // MARK: - 4. The migration

    @Test("migrating a v14 database calls its queued work applied, and not sent")
    func migratingAV14DatabaseKeepsTheQueueAndTellsTheTruthAboutIt() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try connection.configureForWriting()
        _ = try SchemaMigrator.migrate(AppSchema.migrations.filter { $0.version <= 14 }, on: connection)

        let now = SQLiteTimestamp.string(from: Date(timeIntervalSince1970: 1_800_000_000))
        let pending = UUID(), stuck = UUID(), receipt = UUID()
        let pendingClient = UUID(), stuckClient = UUID(), receiptClient = UUID()

        // Three rows a phone really holds: work not yet drained, work that has given up and is
        // waiting for the retry button, and a `done` receipt screen 17 still shows. The receipt is
        // the row that matters most — it is `json_synced = 1` and has never been sent anywhere, so a
        // `done` CHECK naming `remote_sent` would make this migration reject it.
        try connection.execute("""
            INSERT INTO outbox (id, kind, client_uuid, payload, photo_paths, state, fail_count,
                last_error, json_synced, window_started_at, created_at, updated_at)
            VALUES ('\(pending.uuidString)','visit','\(pendingClient.uuidString)','{}',
                '[{"path":"/tmp/queued.jpg","shotType":"trunk"}]','pending',0,NULL,0,
                '\(now)','\(now)','\(now)');

            INSERT INTO outbox (id, kind, client_uuid, payload, photo_paths, state, fail_count,
                last_error, json_synced, window_started_at, created_at, updated_at)
            VALUES ('\(stuck.uuidString)','care_event','\(stuckClient.uuidString)','{}','[]','failed',3,
                'no signal',0,'\(now)','\(now)','\(now)');

            INSERT INTO outbox (id, kind, client_uuid, payload, photo_paths, state, fail_count,
                last_error, json_synced, window_started_at, created_at, updated_at)
            VALUES ('\(receipt.uuidString)','favorite_toggle','\(receiptClient.uuidString)','{}','[]','done',0,
                NULL,1,'\(now)','\(now)','\(now)');
            """)

        // Every step above 14, not literally `[15]`: this test is about a v14 database reaching the
        // current schema with its queue intact, and it must not fail the day an unrelated migration
        // is added — the rule `DataGates.outboxPhotoShotTypes` and E89 both state.
        let expected = AppSchema.migrations.map(\.version).filter { $0 > 14 }
        let applied = try SchemaMigrator.migrate(AppSchema.migrations, on: connection)
        #expect(applied == expected, "migrating a v14 database applied \(applied), expected \(expected)")
        #expect(try connection.userVersion == AppSchema.currentVersion)

        let rows = try OutboxStore().allItems(connection: connection)
        #expect(rows.count == 3, "\(rows.count) rows survived the rebuild, expected 3")
        #expect(rows.map(\.item.id) == [pending, stuck, receipt], "FIFO order did not survive the rebuild")
        #expect(rows.map(\.item.clientUUID) == [pendingClient, stuckClient, receiptClient])
        #expect(rows.map(\.item.state) == [.pending, .failed, .done])
        #expect(rows.map(\.item.failCount) == [0, 3, 0])
        #expect(rows[1].item.lastError == "no signal", "the reason screen 17 shows was dropped")
        #expect(rows[0].item.photos == [OutboxPhoto(path: "/tmp/queued.jpg", shotType: .trunk)])

        // The truth about each row: `json_synced` was only ever the local commit.
        #expect(rows.map(\.locallyApplied) == [false, false, true], "the migration moved the applied flag")
        #expect(
            rows.allSatisfy { !$0.remoteSent },
            "the migration claimed a row had been sent to a server that does not exist"
        )

        // Replaying it must not rebuild the table a second time.
        let before = try Self.outboxDDL(connection: connection)
        try AppSchema.migrations.first { $0.version == 15 }?.migrate(connection)
        #expect(try Self.outboxDDL(connection: connection) == before, "replaying v15 rebuilt the table")
        #expect(try OutboxStore().allItems(connection: connection).count == 3)

        // And the rebuilt table still enqueues, with both flags starting at zero.
        let fresh = OutboxItem(kind: .visit, clientUUID: UUID(), payload: Data("{}".utf8))
        try OutboxStore().enqueue(fresh, connection: connection)
        let stored = try #require(try OutboxStore().item(id: fresh.id, connection: connection))
        #expect(!stored.locallyApplied)
        #expect(!stored.remoteSent)
    }

    @Test("the rebuild carries seq forward with rows, and restarts from 1 on an empty outbox")
    func whatCopyingSeqActuallyBuys() throws {
        // The measurement `applyV15`'s comment cites, kept because the tempting stronger sentence —
        // "copying `seq` re-seeds `sqlite_sequence`, so no id is ever reused" — is false in the
        // ordinary case, and it is inherited verbatim from v4.

        // With rows: the counter comes across, so the next row sorts after the survivors.
        let withRows = try SQLiteConnection(path: ":memory:")
        try withRows.configureForWriting()
        _ = try SchemaMigrator.migrate(AppSchema.migrations.filter { $0.version <= 14 }, on: withRows)
        let now = SQLiteTimestamp.string(from: Date(timeIntervalSince1970: 1_800_000_000))
        try withRows.execute("""
            INSERT INTO outbox (id, kind, client_uuid, payload, photo_paths, state, fail_count,
                json_synced, window_started_at, created_at, updated_at)
            VALUES ('\(UUID().uuidString)','visit','\(UUID().uuidString)','{}','[]','pending',0,0,
                '\(now)','\(now)','\(now)')
            """)
        let seqBefore = try Self.maxSeq(connection: withRows)
        _ = try SchemaMigrator.migrate(AppSchema.migrations, on: withRows)
        #expect(try Self.maxSeq(connection: withRows) == seqBefore, "the rebuild renumbered a live row")

        // Empty — the state of a phone that drained everything and let `pruneCompleted` sweep the
        // receipts. `DROP TABLE` takes the counter, and the next row starts from 1 again. Harmless,
        // because `seq` only orders rows that are live at the same time and identity is `id` and
        // `client_uuid`; recorded because the comment must not claim otherwise.
        let empty = try SQLiteConnection(path: ":memory:")
        try empty.configureForWriting()
        _ = try SchemaMigrator.migrate(AppSchema.migrations.filter { $0.version <= 14 }, on: empty)
        try empty.execute("""
            INSERT INTO outbox (id, kind, client_uuid, payload, photo_paths, state, fail_count,
                json_synced, window_started_at, created_at, updated_at)
            VALUES ('\(UUID().uuidString)','visit','\(UUID().uuidString)','{}','[]','done',0,1,
                '\(now)','\(now)','\(now)')
            """)
        try empty.execute("DELETE FROM outbox")
        _ = try SchemaMigrator.migrate(AppSchema.migrations, on: empty)

        let after = OutboxItem(kind: .visit, clientUUID: UUID(), payload: Data("{}".utf8))
        try OutboxStore().enqueue(after, connection: empty)
        #expect(
            try Self.maxSeq(connection: empty) == 1,
            "the empty-outbox rebuild did not restart the counter, so the comment is now wrong the other way"
        )
    }

    // MARK: - Helpers

    private static func maxSeq(connection: SQLiteConnection) throws -> Int {
        let statement = try connection.prepare("SELECT COALESCE(MAX(seq), 0) AS n FROM outbox")
        defer { statement.finalize() }
        return try statement.fetchOne { try $0.int("n") } ?? -1
    }

    private static func remoteSent(of id: UUID, in store: CypressStore) async throws -> Int {
        try await store.queue.read { connection in
            let statement = try connection.prepare("SELECT remote_sent AS n FROM outbox WHERE id = :id")
            defer { statement.finalize() }
            _ = try statement.bind(id, forName: ":id")
            return try statement.fetchOne { try $0.int("n") } ?? -1
        }
    }

    private static func outboxDDL(connection: SQLiteConnection) throws -> String {
        let statement = try connection.prepare(
            "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'outbox'"
        )
        defer { statement.finalize() }
        return try statement.fetchOne { try $0.stringIfPresent("sql") ?? "" } ?? ""
    }
}
