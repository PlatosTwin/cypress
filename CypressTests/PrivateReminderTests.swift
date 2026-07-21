import Foundation
import Testing
@testable import Cypress

/// D4's private reminder, on a device that has no account (ERRATA E23).
///
/// The four sentences this suite has to make true, because each of them is a thing E23 said could
/// not happen or a thing the fix could quietly get wrong:
///
/// 1. a reminder saves with no user present, and is owned by the device;
/// 2. it is still there after the process dies and the store is reopened;
/// 3. the migration that made that possible did not drop the rows that were already stored;
/// 4. `claimDevice` moves device-owned reminders onto the account, and claiming twice changes
///    nothing — no duplicate, no orphan, and nobody else's reminder moved.
@Suite("Private reminders")
struct PrivateReminderTests {

    // MARK: - Fixtures

    private static let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-0000000000A1")!
    private static let userID = UUID(uuidString: "0E000000-0000-4000-8000-0000000000A2")!
    private static let strangerID = UUID(uuidString: "0E000000-0000-4000-8000-0000000000A3")!

    /// A tree to attach reminders to. There is no seed in these tests, so it is a community add —
    /// which `LocalAPI.requireTree` accepts and an invented UUID does not.
    private static func makeTree(api: LocalAPI, at longitude: Double = -122.44) async throws -> Tree {
        try await api.addTree(
            TreeDraft(
                coordinate: Coordinate(latitude: 37.77, longitude: longitude),
                photoLocalPath: "/tmp/cypress-reminder-test.jpg",
                attribution: Attribution.anonymous(deviceID: deviceID)
            )
        )
    }

    private static func reminders(
        in store: CypressStore,
        userID: UUID? = nil,
        deviceID: UUID? = nil
    ) async throws -> [PrivateReminder] {
        try await store.queue.read { connection in
            try ContributionStore().privateReminders(userID: userID, deviceID: deviceID, connection: connection)
        }
    }

    /// The row count the "exactly one owner" CHECK is supposed to make impossible. Read straight
    /// from SQL rather than through the decoder, because the decoder would refuse such a row and the
    /// question here is whether the row exists at all.
    private static func ownerlessCount(in store: CypressStore) async throws -> Int {
        try await store.queue.read { connection in
            let statement = try connection.prepare(
                "SELECT COUNT(*) AS n FROM private_reminders WHERE user_id IS NULL AND device_id IS NULL"
            )
            defer { statement.finalize() }
            return try statement.fetchOne { try $0.int("n") } ?? -1
        }
    }

    // MARK: - 1. It saves with no user

    @Test("a reminder saves with no user present, owned by the device")
    func savesWithoutAnAccount() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let outbox = OutboxQueue(queue: store.queue, transport: APIOutboxTransport(api: api))
        let tree = try await Self.makeTree(api: api)

        // Exactly what screen 06 hands the composition root.
        let draft = PrivateReminderDraft(treeID: tree.id, category: .hangingOrBrokenLimb)
        let attribution = await api.attribution
        #expect(attribution.isAnonymous, "the fixture is only meaningful on a device with no account")

        let receipt = try await ReminderOutboxWriter.save(draft, attribution: attribution, outbox: outbox)

        // The outbox carried it, keyed on the id the screen minted.
        #expect(receipt.item.kind == .privateReminder)
        #expect(receipt.item.clientUUID == draft.reminderID)

        let stored = try await Self.reminders(in: store, deviceID: Self.deviceID)
        #expect(stored.count == 1)
        #expect(stored.first?.owner == .device(Self.deviceID))
        #expect(stored.first?.owner.userID == nil)
        #expect(stored.first?.category == .hangingOrBrokenLimb)
        #expect(stored.first?.treeID == tree.id)
        #expect(try await Self.ownerlessCount(in: store) == 0)

        // And the queue is empty of unfinished work: the row was applied, not abandoned.
        let records = try await outbox.records()
        #expect(records.count == 1)
        #expect(records.first?.item.state == .done)
    }

    @Test("saving the same selection twice stores one reminder")
    func doubleTapIsOneReminder() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let outbox = OutboxQueue(queue: store.queue, transport: APIOutboxTransport(api: api))
        let tree = try await Self.makeTree(api: api)

        // One draft, two taps — the id is minted per selection, which is what makes the second tap a
        // replay rather than a second reminder.
        let draft = PrivateReminderDraft(treeID: tree.id, category: .uprooted)
        let attribution = await api.attribution
        _ = try await ReminderOutboxWriter.save(draft, attribution: attribution, outbox: outbox)
        _ = try await ReminderOutboxWriter.save(draft, attribution: attribution, outbox: outbox)

        #expect(try await Self.reminders(in: store, deviceID: Self.deviceID).count == 1)
        #expect(try await outbox.records().count == 1)
    }

    @Test("a reminder about a tree that does not exist is not stored")
    func unknownTreeIsRejected() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let reminder = PrivateReminder(
            owner: .device(Self.deviceID),
            treeID: UUID(),
            category: .struckByVehicle
        )
        await #expect(throws: APIError.notFound) {
            _ = try await api.savePrivateReminder(reminder)
        }
        #expect(try await Self.reminders(in: store, deviceID: Self.deviceID).isEmpty)
    }

    // MARK: - 2. It survives relaunch

    @Test("a reminder survives the process dying, drained or not")
    func survivesRelaunch() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cypress-reminder-relaunch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("cypress.sqlite")

        // ── Launch one: save one reminder through the drain, and queue a second that never gets to
        //    drain — the basement case the outbox exists for.
        let saved: UUID
        let queued: UUID
        let treeID: UUID
        do {
            let store = try await CypressStore.open(databaseURL: databaseURL, seedURL: nil)
            let api = LocalAPI(store: store, deviceID: Self.deviceID)
            let outbox = OutboxQueue(queue: store.queue, transport: APIOutboxTransport(api: api))
            let tree = try await Self.makeTree(api: api)
            treeID = tree.id

            let first = PrivateReminderDraft(treeID: tree.id, category: .hangingOrBrokenLimb)
            _ = try await ReminderOutboxWriter.save(first, attribution: await api.attribution, outbox: outbox)
            saved = first.reminderID

            let second = PrivateReminder(
                owner: .device(Self.deviceID),
                treeID: tree.id,
                category: .blockingSignalOrSightline
            )
            _ = try await outbox.enqueue(.privateReminder(second))
            queued = second.id
        }

        // ── Launch two: the same file, a fresh store, the same device id. Scoped so the connection
        //    is closed before the directory goes, which is what a relaunch means anyway.
        do {
            let store = try await CypressStore.open(databaseURL: databaseURL, seedURL: nil)
            let api = LocalAPI(store: store, deviceID: Self.deviceID)
            let outbox = OutboxQueue(queue: store.queue, transport: APIOutboxTransport(api: api))

            let afterRelaunch = try await api.privateReminders()
            #expect(afterRelaunch.map(\.id) == [saved], "the applied reminder did not survive relaunch")
            #expect(afterRelaunch.first?.owner == .device(Self.deviceID))
            #expect(afterRelaunch.first?.treeID == treeID)

            // The undrained one is still queued, still owned by the device, and still decodes.
            let pending = try await outbox.records().filter { $0.item.state == .pending }
            #expect(pending.count == 1)
            let payload = try #require(pending.first.map {
                try OutboxPayload.decode(kind: $0.item.kind, from: $0.item.payload)
            })
            guard case let .privateReminder(decoded) = payload else {
                Issue.record("the surviving payload did not decode as a private reminder")
                return
            }
            #expect(decoded.id == queued)
            #expect(decoded.owner == .device(Self.deviceID))

            // And it drains after the relaunch, exactly like any other queued mutation.
            let report = try await outbox.drain()
            #expect(report.synced == 1)
            #expect(try await api.privateReminders().count == 2)
            #expect(try await Self.ownerlessCount(in: store) == 0)
        }
    }

    // MARK: - 3. The migration keeps what was already there

    @Test("migrating a v2 database preserves the reminders and the outbox rows already in it")
    func migrationPreservesExistingRows() async throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try connection.configureForWriting()
        _ = try SchemaMigrator.migrate(AppSchema.migrations.filter { $0.version <= 2 }, on: connection)

        // A reminder written by a build where `user_id` was NOT NULL, and a queued visit beside it —
        // v4 rebuilds the outbox, so a contributor's pending work has to come across untouched.
        let legacy = UUID()
        let treeID = UUID()
        let queuedID = UUID()
        let clientUUID = UUID()
        let now = SQLiteTimestamp.string(from: Date(timeIntervalSince1970: 1_800_000_000))
        try connection.execute("""
            INSERT INTO private_reminders (id, user_id, tree_uuid, category, note, created_at, updated_at)
            VALUES ('\(legacy.uuidString)','\(Self.userID.uuidString)','\(treeID.uuidString)',
                'uprooted','the one by the corner','\(now)','\(now)');

            INSERT INTO outbox (id, kind, client_uuid, payload, photo_paths, state, fail_count,
                last_error, json_synced, window_started_at, created_at, updated_at)
            VALUES ('\(queuedID.uuidString)','visit','\(clientUUID.uuidString)','{}',
                '[{"path":"/tmp/pending.jpg","shotType":"trunk"}]','failed',3,'no signal',0,
                '\(now)','\(now)','\(now)');
            """)

        let applied = try SchemaMigrator.migrate(AppSchema.migrations, on: connection)
        #expect(applied == [3, 4])

        // The reminder survived, still owned by its account and by nothing else.
        let rows = try ContributionStore().privateReminders(
            userID: Self.userID, deviceID: nil, connection: connection
        )
        #expect(rows.count == 1)
        #expect(rows.first?.id == legacy)
        #expect(rows.first?.owner == .user(Self.userID))
        #expect(rows.first?.category == .uprooted)
        #expect(rows.first?.note == "the one by the corner")

        // The pending visit came across with its retry accounting intact.
        let queue = try OutboxStore().allItems(connection: connection)
        #expect(queue.count == 1)
        #expect(queue.first?.item.id == queuedID)
        #expect(queue.first?.item.clientUUID == clientUUID)
        #expect(queue.first?.item.state == .failed)
        #expect(queue.first?.item.failCount == 3)
        #expect(queue.first?.item.lastError == "no signal")
        #expect(queue.first?.item.photos == [OutboxPhoto(path: "/tmp/pending.jpg", shotType: .trunk)])

        // The new vocabulary is storable and the old one still is.
        try connection.execute("""
            INSERT INTO outbox (id, kind, client_uuid, payload, photo_paths, state, json_synced,
                window_started_at, created_at, updated_at)
            VALUES ('\(UUID().uuidString)','private_reminder','\(UUID().uuidString)','{}','[]','pending',0,
                '\(now)','\(now)','\(now)')
            """)
        #expect(try OutboxStore().allItems(connection: connection).count == 2)

        // Replaying either migration must be a no-op, not a second rebuild.
        let before = try Self.schemaFingerprint(connection: connection)
        try AppSchema.migrations.first { $0.version == 3 }?.migrate(connection)
        try AppSchema.migrations.first { $0.version == 4 }?.migrate(connection)
        #expect(try Self.schemaFingerprint(connection: connection) == before)
        #expect(try ContributionStore().privateReminders(userID: Self.userID, deviceID: nil, connection: connection).count == 1)
        #expect(try OutboxStore().allItems(connection: connection).count == 2)
    }

    /// Every table's stored DDL plus the two row counts a replay could damage.
    private static func schemaFingerprint(connection: SQLiteConnection) throws -> String {
        let statement = try connection.prepare("""
            SELECT group_concat(sql, '|') AS ddl FROM sqlite_master
             WHERE type = 'table' AND name IN ('private_reminders','outbox')
            """)
        defer { statement.finalize() }
        return try statement.fetchOne { try $0.stringIfPresent("ddl") ?? "" } ?? ""
    }

    // MARK: - 4. Adoption

    @Test("claimDevice adopts device-owned reminders, and claiming twice changes nothing")
    func claimDeviceAdoptsIdempotently() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let outbox = OutboxQueue(queue: store.queue, transport: APIOutboxTransport(api: api))
        let tree = try await Self.makeTree(api: api)
        let other = try await Self.makeTree(api: api, at: -122.40)

        // Two reminders written before sign-in…
        for category in [HazardCategory.hangingOrBrokenLimb, .uprooted] {
            _ = try await ReminderOutboxWriter.save(
                PrivateReminderDraft(treeID: tree.id, category: category),
                attribution: await api.attribution,
                outbox: outbox
            )
        }
        // …and one that already belongs to somebody else, which no claim may touch.
        let stranger = PrivateReminder(owner: .user(Self.strangerID), treeID: other.id, category: .uprooted)
        _ = try await api.savePrivateReminder(stranger)

        #expect(try await Self.reminders(in: store, deviceID: Self.deviceID).count == 2)

        try await api.claimDevice(deviceUUID: Self.deviceID, userID: Self.userID)

        let adopted = try await Self.reminders(in: store, userID: Self.userID)
        #expect(adopted.count == 2, "both pre-sign-in reminders should have arrived on the account")
        #expect(adopted.allSatisfy { $0.owner == .user(Self.userID) })
        // The device link is gone, not kept beside the account: strictly less data after sign-in.
        #expect(try await Self.reminders(in: store, deviceID: Self.deviceID).isEmpty)
        #expect(try await Self.ownerlessCount(in: store) == 0)
        // Nobody else's record moved.
        let strangers = try await Self.reminders(in: store, userID: Self.strangerID)
        #expect(strangers.map(\.id) == [stranger.id])

        // Claiming again: same rows, same owners, nothing duplicated and nothing orphaned.
        let idsAfterFirstClaim = Set(adopted.map(\.id))
        try await api.claimDevice(deviceUUID: Self.deviceID, userID: Self.userID)
        let afterSecondClaim = try await Self.reminders(in: store, userID: Self.userID)
        #expect(Set(afterSecondClaim.map(\.id)) == idsAfterFirstClaim)
        #expect(afterSecondClaim.count == 2)
        #expect(try await Self.ownerlessCount(in: store) == 0)
        #expect(try await Self.reminders(in: store, userID: Self.strangerID).count == 1)

        // A reminder written after sign-in is the account's from the start, and a later claim by a
        // different account does not take it.
        let afterSignIn = PrivateReminderDraft(treeID: tree.id, category: .struckByVehicle)
        _ = try await ReminderOutboxWriter.save(
            afterSignIn, attribution: await api.attribution, outbox: outbox
        )
        try await api.claimDevice(deviceUUID: Self.deviceID, userID: Self.strangerID)
        let mine = try await Self.reminders(in: store, userID: Self.userID)
        #expect(mine.count == 3)
        #expect(mine.contains { $0.id == afterSignIn.reminderID })
    }

    // MARK: - The shapes that must stay unrepresentable

    @Test("a reminder's owner round-trips through the outbox payload as exactly one owner")
    func ownerEncodesAsOneKey() throws {
        for owner in [ReminderOwner.user(Self.userID), .device(Self.deviceID)] {
            let reminder = PrivateReminder(owner: owner, treeID: UUID(), category: .uprooted)
            let data = try OutboxPayload.privateReminder(reminder).encoded()
            let json = try #require(
                try JSONSerialization.jsonObject(with: data) as? [String: Any]
            )
            let ownerKeys = try #require(json["owner"] as? [String: Any]).keys
            #expect(ownerKeys.count == 1, "an owner encoded as \(ownerKeys)")

            let decoded = try OutboxPayload.decode(kind: .privateReminder, from: data)
            guard case let .privateReminder(round) = decoded else {
                Issue.record("a private reminder payload decoded as \(decoded)")
                return
            }
            #expect(round.owner == owner)
            #expect(round.id == reminder.id)
        }
    }

    @Test("an ownerless reminder payload does not decode into an ownerless reminder")
    func ownerlessPayloadIsRefused() throws {
        // Built by stripping the owner out of a payload that is known to decode, so this asserts the
        // owner is what fails rather than some unrelated key drifting.
        let reminder = PrivateReminder(owner: .device(Self.deviceID), treeID: UUID(), category: .uprooted)
        let encoded = try OutboxPayload.privateReminder(reminder).encoded()
        var json = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(try OutboxPayload.decode(kind: .privateReminder, from: encoded).treeID == reminder.treeID)

        json["owner"] = [String: Any]()
        let ownerless = try JSONSerialization.data(withJSONObject: json)
        #expect(throws: (any Error).self) {
            _ = try OutboxPayload.decode(kind: .privateReminder, from: ownerless)
        }
    }

    @Test("the reminder owner follows D9: the account when there is one, the device otherwise")
    func ownerFollowsAttribution() {
        #expect(ReminderOwner(Attribution.anonymous(deviceID: Self.deviceID)) == .device(Self.deviceID))
        #expect(ReminderOwner(Attribution(userID: Self.userID, deviceID: Self.deviceID)) == .user(Self.userID))
        #expect(ReminderOwner.device(Self.deviceID).adopted(by: Self.userID) == .user(Self.userID))
        // Adoption never re-homes an account's reminder onto another account.
        #expect(ReminderOwner.user(Self.userID).adopted(by: Self.strangerID) == .user(Self.userID))
    }
}
