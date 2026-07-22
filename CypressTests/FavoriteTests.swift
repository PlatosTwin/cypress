import Foundation
import Testing
@testable import Cypress

/// The heart on screen 03's quad row, on a device that has no account (ERRATA E89).
///
/// E23 proved this shape once for private reminders and this suite proves the same sentences for
/// favourites, plus the two it has that a reminder does not:
///
/// 1. a favourite saves with no user present, and is owned by the device;
/// 2. the migration that made that possible did not drop the rows already stored;
/// 3. `claimDevice` moves device-owned favourites onto the account, and claiming twice changes
///    nothing — no duplicate, no orphan, and nobody else's favourite moved;
/// 4. **the uniqueness pair survived becoming an ownership pair**: one owner may hold a tree once,
///    two owners may each hold it, and a sign-in where both had already favourited the same tree
///    merges rather than aborting the claim;
/// 5. **the tombstone and the replay guard still work**, which they must, because a favourite is the
///    one contribution the model allows to be taken back.
@Suite("Favourites")
struct FavoriteTests {

    // MARK: - Fixtures

    private static let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-0000000000B1")!
    private static let userID = UUID(uuidString: "0E000000-0000-4000-8000-0000000000B2")!
    private static let strangerID = UUID(uuidString: "0E000000-0000-4000-8000-0000000000B3")!

    /// A tree to favourite. There is no seed in these tests, so it is a community add — which
    /// `LocalAPI.requireTree` accepts and an invented UUID does not.
    private static func makeTree(api: LocalAPI, at longitude: Double = -122.44) async throws -> Tree {
        try await api.addTree(
            TreeDraft(
                coordinate: Coordinate(latitude: 37.77, longitude: longitude),
                photoLocalPath: "/tmp/cypress-favorite-test.jpg",
                attribution: Attribution.anonymous(deviceID: deviceID)
            )
        )
    }

    /// One favourite row, read straight from SQL. The store has no "read a favourite" API — it
    /// answers `isFavorite` for one owner and one tree — and these assertions are about the row's
    /// owner, timestamp and client uuid, which is more than the boolean carries.
    private struct Row: Equatable {
        var userID: UUID?
        var deviceID: UUID?
        var treeID: UUID
        var clientUUID: UUID
        var isActive: Bool
        var updatedAt: String
    }

    private static func rows(in store: CypressStore) async throws -> [Row] {
        try await store.queue.read { connection in
            let statement = try connection.prepare("SELECT * FROM favorites ORDER BY tree_uuid")
            defer { statement.finalize() }
            return try statement.fetchAll { row in
                Row(
                    userID: try row.uuidIfPresent("user_id"),
                    deviceID: try row.uuidIfPresent("device_id"),
                    treeID: try row.uuid("tree_uuid"),
                    clientUUID: try row.uuid("client_uuid"),
                    isActive: try row.dateIfPresent("deleted_at") == nil,
                    updatedAt: try row.string("updated_at")
                )
            }
        }
    }

    /// The row count the "exactly one owner" CHECK is supposed to make impossible.
    private static func ownerlessCount(in store: CypressStore) async throws -> Int {
        try await store.queue.read { connection in
            let statement = try connection.prepare(
                "SELECT COUNT(*) AS n FROM favorites WHERE user_id IS NULL AND device_id IS NULL"
            )
            defer { statement.finalize() }
            return try statement.fetchOne { try $0.int("n") } ?? -1
        }
    }

    /// Applies a toggle the way a drained outbox item does, without going through the queue.
    private static func toggle(
        _ store: CypressStore,
        owner: FavoriteOwner,
        treeID: UUID,
        isFavorite: Bool,
        clientUUID: UUID,
        at date: Date
    ) async throws {
        try await store.queue.write { connection in
            try ContributionStore().applyFavoriteToggle(
                owner: owner,
                treeID: treeID,
                clientUUID: clientUUID,
                isFavorite: isFavorite,
                at: date,
                connection: connection
            )
        }
    }

    // MARK: - 1. It saves with no user

    @Test("a favourite saves with no user present, owned by the device")
    func savesWithoutAnAccount() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let outbox = OutboxQueue(queue: store.queue, transport: APIOutboxTransport(api: api))
        let tree = try await Self.makeTree(api: api)

        let attribution = await api.attribution
        #expect(attribution.isAnonymous, "the fixture is only meaningful on a device with no account")

        let receipt = try await FavoriteOutboxWriter.save(
            treeID: tree.id,
            isFavorite: true,
            attribution: attribution,
            outbox: outbox
        )

        // The outbox carried it, keyed on the client uuid the composition root minted.
        #expect(receipt.item.kind == .favoriteToggle)
        #expect(receipt.item.clientUUID == receipt.toggle.clientUUID)
        #expect(receipt.toggle.owner == .device(Self.deviceID))

        let stored = try await Self.rows(in: store)
        #expect(stored.count == 1)
        #expect(stored.first?.deviceID == Self.deviceID)
        #expect(stored.first?.userID == nil)
        #expect(stored.first?.treeID == tree.id)
        #expect(stored.first?.isActive == true)
        #expect(try await Self.ownerlessCount(in: store) == 0)

        // The row was applied, not abandoned.
        let records = try await outbox.records()
        #expect(records.count == 1)
        #expect(records.first?.item.state == .done)

        // And the two reads that a device-owned favourite has to reach: the grove, which used to
        // read favourites only when a user was present, and screen 15's holdings.
        let grove = try await api.grove()
        #expect(grove.map(\.treeID) == [tree.id])
        #expect(grove.first?.isFavorite == true)
        #expect(try await api.deviceContributions().favorites == 1)
    }

    @Test("two taps on one heart save one favourite")
    func doubleTapIsOneFavorite() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let outbox = OutboxQueue(queue: store.queue, transport: APIOutboxTransport(api: api))
        let tree = try await Self.makeTree(api: api)

        // One key, two taps — which is what `RootView` does by keeping the client uuid it minted for
        // this tree, the way screen 06 keeps `PrivateReminderDraft.reminderID`.
        let clientUUID = UUID()
        for _ in 0..<2 {
            _ = try await FavoriteOutboxWriter.save(
                treeID: tree.id,
                isFavorite: true,
                attribution: await api.attribution,
                outbox: outbox,
                clientUUID: clientUUID
            )
        }

        #expect(try await Self.rows(in: store).count == 1)
        #expect(try await outbox.records().count == 1)
    }

    @Test("a favourite of a tree that does not exist is not stored")
    func unknownTreeIsRejected() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let toggle = FavoriteToggle(owner: .device(Self.deviceID), treeID: UUID(), isFavorite: true)
        let item = try OutboxPayload.favoriteToggle(toggle).makeItem()

        let results = try await api.sync([item])
        #expect(results.first?.status == .failed)
        #expect(results.first?.error == .notFound)
        #expect(try await Self.rows(in: store).isEmpty)
    }

    // MARK: - 2. The migration keeps what was already there

    @Test("migrating a v4 database preserves the favourites already in it")
    func migrationPreservesExistingRows() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try connection.configureForWriting()
        _ = try SchemaMigrator.migrate(AppSchema.migrations.filter { $0.version <= 4 }, on: connection)

        // Two favourites written by a build where `user_id` was NOT NULL: one live, one already
        // tombstoned, because the tombstone is the state a rebuild is most likely to flatten.
        let liveTree = UUID()
        let offTree = UUID()
        let liveClient = UUID()
        let now = SQLiteTimestamp.string(from: Date(timeIntervalSince1970: 1_800_000_000))
        try connection.execute("""
            INSERT INTO favorites (id, user_id, tree_uuid, client_uuid, created_at, updated_at, deleted_at)
            VALUES ('\(UUID().uuidString)','\(Self.userID.uuidString)','\(liveTree.uuidString)',
                    '\(liveClient.uuidString)','\(now)','\(now)', NULL),
                   ('\(UUID().uuidString)','\(Self.userID.uuidString)','\(offTree.uuidString)',
                    '\(UUID().uuidString)','\(now)','\(now)','\(now)');
            """)

        let applied = try SchemaMigrator.migrate(AppSchema.migrations, on: connection)
        #expect(applied == [5])

        let store = ContributionStore()
        #expect(try store.isFavorite(owner: .user(Self.userID), treeID: liveTree, connection: connection))
        #expect(try !store.isFavorite(owner: .user(Self.userID), treeID: offTree, connection: connection))

        // Both rows are still there — the tombstone is a row, not an absence — and both are owned by
        // the account and by nothing else.
        let survivors = try Self.rawRows(connection: connection)
        #expect(survivors.count == 2)
        #expect(survivors.allSatisfy { $0.userID == Self.userID && $0.deviceID == nil })
        #expect(survivors.first { $0.treeID == liveTree }?.clientUUID == liveClient)

        // The new shape is in force: a device-owned favourite is now storable…
        try store.applyFavoriteToggle(
            owner: .device(Self.deviceID),
            treeID: liveTree,
            clientUUID: UUID(),
            isFavorite: true,
            at: Date(timeIntervalSince1970: 1_800_000_100),
            connection: connection
        )
        #expect(try Self.rawRows(connection: connection).count == 3)
        // …and an ownerless one is not.
        #expect(throws: (any Error).self) {
            try connection.execute("""
                INSERT INTO favorites (id, tree_uuid, client_uuid, created_at, updated_at)
                VALUES ('\(UUID().uuidString)','\(liveTree.uuidString)','\(UUID().uuidString)','\(now)','\(now)')
                """)
        }

        // Replaying the migration must be a no-op, not a second rebuild.
        let before = try Self.schemaFingerprint(connection: connection)
        try AppSchema.migrations.first { $0.version == 5 }?.migrate(connection)
        #expect(try Self.schemaFingerprint(connection: connection) == before)
        #expect(try Self.rawRows(connection: connection).count == 3)
    }

    private static func rawRows(connection: SQLiteConnection) throws -> [Row] {
        let statement = try connection.prepare("SELECT * FROM favorites ORDER BY tree_uuid")
        defer { statement.finalize() }
        return try statement.fetchAll { row in
            Row(
                userID: try row.uuidIfPresent("user_id"),
                deviceID: try row.uuidIfPresent("device_id"),
                treeID: try row.uuid("tree_uuid"),
                clientUUID: try row.uuid("client_uuid"),
                isActive: try row.dateIfPresent("deleted_at") == nil,
                updatedAt: try row.string("updated_at")
            )
        }
    }

    /// The table's stored DDL plus its indexes and its trigger — everything a replay could rebuild.
    private static func schemaFingerprint(connection: SQLiteConnection) throws -> String {
        let statement = try connection.prepare("""
            SELECT group_concat(sql, '|') AS ddl FROM sqlite_master
             WHERE tbl_name = 'favorites' ORDER BY name
            """)
        defer { statement.finalize() }
        return try statement.fetchOne { try $0.stringIfPresent("ddl") ?? "" } ?? ""
    }

    // MARK: - 3. Adoption

    @Test("claimDevice adopts device-owned favourites, and claiming twice changes nothing")
    func claimDeviceAdoptsIdempotently() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let outbox = OutboxQueue(queue: store.queue, transport: APIOutboxTransport(api: api))
        let first = try await Self.makeTree(api: api)
        let second = try await Self.makeTree(api: api, at: -122.40)
        let strangers = try await Self.makeTree(api: api, at: -122.36)

        for tree in [first, second] {
            _ = try await FavoriteOutboxWriter.save(
                treeID: tree.id,
                isFavorite: true,
                attribution: await api.attribution,
                outbox: outbox
            )
        }
        // One that already belongs to somebody else, which no claim may touch.
        try await Self.toggle(
            store, owner: .user(Self.strangerID), treeID: strangers.id,
            isFavorite: true, clientUUID: UUID(), at: Date(timeIntervalSince1970: 1_800_000_000)
        )

        try await api.claimDevice(deviceUUID: Self.deviceID, userID: Self.userID)

        var stored = try await Self.rows(in: store)
        #expect(stored.count == 3)
        let mine = stored.filter { $0.userID == Self.userID }
        #expect(Set(mine.map(\.treeID)) == [first.id, second.id])
        // The device link is gone, not kept beside the account: strictly less data after sign-in.
        #expect(stored.allSatisfy { $0.deviceID == nil })
        #expect(try await Self.ownerlessCount(in: store) == 0)
        // Nobody else's row moved.
        #expect(stored.filter { $0.userID == Self.strangerID }.map(\.treeID) == [strangers.id])

        // Claiming again: same rows, same owners, nothing duplicated and nothing orphaned.
        let before = stored
        try await api.claimDevice(deviceUUID: Self.deviceID, userID: Self.userID)
        stored = try await Self.rows(in: store)
        #expect(stored == before)

        // And the device is holding nothing any more, which is screen 15's promise.
        #expect(try await api.deviceContributions().favorites == 0)

        // A favourite made after sign-in is the account's from the start, and a later claim by a
        // different account does not take it.
        await api.setUserID(Self.userID)
        let third = try await Self.makeTree(api: api, at: -122.32)
        _ = try await FavoriteOutboxWriter.save(
            treeID: third.id,
            isFavorite: true,
            attribution: await api.attribution,
            outbox: outbox
        )
        try await api.claimDevice(deviceUUID: Self.deviceID, userID: Self.strangerID)
        let after = try await Self.rows(in: store)
        #expect(after.filter { $0.userID == Self.userID }.count == 3)
        #expect(after.first { $0.treeID == third.id }?.userID == Self.userID)
    }

    // MARK: - 4. The collision the reminder never had

    @Test("a device and the account it claims may both hold one tree, and the later word wins")
    func signInMergesACollision() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let shared = try await Self.makeTree(api: api)
        let deviceOnly = try await Self.makeTree(api: api, at: -122.40)
        let accountOnly = try await Self.makeTree(api: api, at: -122.36)

        let january = Date(timeIntervalSince1970: 1_800_000_000)
        let june = january.addingTimeInterval(60 * 60 * 24 * 150)

        // The account favourited this tree in January, from somewhere else…
        let accountToggle = UUID()
        try await Self.toggle(
            store, owner: .user(Self.userID), treeID: shared.id,
            isFavorite: true, clientUUID: accountToggle, at: january
        )
        // …and this device favourited the same tree in June, before signing in. Both rows exist:
        // that is the state the ownership pair has to allow.
        let deviceToggle = UUID()
        try await Self.toggle(
            store, owner: .device(Self.deviceID), treeID: shared.id,
            isFavorite: true, clientUUID: deviceToggle, at: june
        )
        try await Self.toggle(
            store, owner: .device(Self.deviceID), treeID: deviceOnly.id,
            isFavorite: true, clientUUID: UUID(), at: june
        )
        try await Self.toggle(
            store, owner: .user(Self.userID), treeID: accountOnly.id,
            isFavorite: true, clientUUID: UUID(), at: january
        )
        #expect(try await Self.rows(in: store).filter { $0.treeID == shared.id }.count == 2)

        // The claim must not throw, and must not leave two rows for one tree.
        try await api.claimDevice(deviceUUID: Self.deviceID, userID: Self.userID)

        let stored = try await Self.rows(in: store)
        #expect(stored.count == 3, "one row per tree after the merge")
        #expect(stored.allSatisfy { $0.userID == Self.userID && $0.deviceID == nil })
        let merged = try #require(stored.first { $0.treeID == shared.id })
        #expect(merged.isActive)
        // The device's June statement is the later one, so it is the one the surviving row carries —
        // state, timestamp and the client uuid that identifies the toggle event.
        #expect(merged.clientUUID == deviceToggle)
        #expect(merged.updatedAt == SQLiteTimestamp.string(from: june))
        #expect(try await Self.ownerlessCount(in: store) == 0)

        // Re-running the claim changes nothing, including the merged row.
        try await api.claimDevice(deviceUUID: Self.deviceID, userID: Self.userID)
        #expect(try await Self.rows(in: store) == stored)
    }

    @Test("when the account's word is the later one, the merge keeps it")
    func signInKeepsTheAccountsLaterWord() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let tree = try await Self.makeTree(api: api)

        let january = Date(timeIntervalSince1970: 1_800_000_000)
        let june = january.addingTimeInterval(60 * 60 * 24 * 150)

        // The device favourited it in January; the account took the heart off in June.
        try await Self.toggle(
            store, owner: .device(Self.deviceID), treeID: tree.id,
            isFavorite: true, clientUUID: UUID(), at: january
        )
        let accountToggle = UUID()
        try await Self.toggle(
            store, owner: .user(Self.userID), treeID: tree.id,
            isFavorite: false, clientUUID: accountToggle, at: june
        )

        try await api.claimDevice(deviceUUID: Self.deviceID, userID: Self.userID)

        let stored = try await Self.rows(in: store)
        #expect(stored.count == 1)
        #expect(stored.first?.userID == Self.userID)
        #expect(stored.first?.isActive == false, "the later un-favourite is what the person meant")
        #expect(stored.first?.clientUUID == accountToggle)
    }

    @Test("one owner cannot hold a tree twice; two owners can each hold it")
    func uniquenessIsPerOwner() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let tree = try await Self.makeTree(api: api)
        let moment = Date(timeIntervalSince1970: 1_800_000_000)

        try await Self.toggle(
            store, owner: .device(Self.deviceID), treeID: tree.id,
            isFavorite: true, clientUUID: UUID(), at: moment
        )
        try await Self.toggle(
            store, owner: .user(Self.userID), treeID: tree.id,
            isFavorite: true, clientUUID: UUID(), at: moment
        )
        #expect(try await Self.rows(in: store).count == 2)

        // A second toggle by the same owner updates the one row rather than adding another. The
        // device arm is the one a single three-column UNIQUE would have failed to enforce, because
        // SQL compares NULLs as distinct.
        try await Self.toggle(
            store, owner: .device(Self.deviceID), treeID: tree.id,
            isFavorite: false, clientUUID: UUID(), at: moment.addingTimeInterval(60)
        )
        let stored = try await Self.rows(in: store)
        #expect(stored.count == 2)
        #expect(stored.first { $0.deviceID == Self.deviceID }?.isActive == false)
        #expect(stored.first { $0.userID == Self.userID }?.isActive == true)
    }

    // MARK: - 5. The tombstone and the replay guard

    @Test("an un-favourite is a tombstone, and a replayed toggle does not flip it back")
    func tombstoneAndReplayGuardSurvive() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let tree = try await Self.makeTree(api: api)
        let moment = Date(timeIntervalSince1970: 1_800_000_000)

        let on = UUID()
        try await Self.toggle(
            store, owner: .device(Self.deviceID), treeID: tree.id,
            isFavorite: true, clientUUID: on, at: moment
        )
        // The same event again, which is what a re-sent outbox item is: no flip, no second row.
        try await Self.toggle(
            store, owner: .device(Self.deviceID), treeID: tree.id,
            isFavorite: false, clientUUID: on, at: moment.addingTimeInterval(10)
        )
        var stored = try await Self.rows(in: store)
        #expect(stored.count == 1)
        #expect(stored.first?.isActive == true, "a replay of the same client uuid flipped the state")
        #expect(stored.first?.updatedAt == SQLiteTimestamp.string(from: moment))

        // A real un-favourite is a different event, and it tombstones rather than deleting.
        let off = UUID()
        try await Self.toggle(
            store, owner: .device(Self.deviceID), treeID: tree.id,
            isFavorite: false, clientUUID: off, at: moment.addingTimeInterval(20)
        )
        stored = try await Self.rows(in: store)
        #expect(stored.count == 1, "the un-favourite removed the row instead of tombstoning it")
        #expect(stored.first?.isActive == false)
        #expect(try await api.deviceContributions().favorites == 0)
        // The grove drops it, because the grove lists what you hold.
        #expect(try await api.grove().isEmpty)
    }

    // MARK: - What a memorial may be

    /// **A memorial and a vacant site can be favourited, and that is deliberate.**
    ///
    /// `TreeStatus.acceptsNewContributions` gates the visit, the photo, the check-in and the measure
    /// sheet, and its reason is stated on the property: those are all observations of a tree that has
    /// to exist. A favourite observes nothing. It writes to the person's grove, not to the tree's
    /// record — which is exactly why it is the one non-append-only row in the model (DECISIONS §3.7)
    /// and why D1 had to kill the version of it that was a public vote.
    ///
    /// The deciding argument is the second assertion below: gating the write would make the toggle
    /// one-way for anyone whose favourite tree is later removed. They could no longer take the heart
    /// off a record they can still see. A rule that turns a reversible thing into an irreversible one
    /// is worse than the state it was trying to prevent.
    ///
    /// Almost nothing offers it, and nothing here changes what does: screen 03 draws the quad row
    /// only on the warm variant, so a vacant site never shows it, and the map sends a removed pin to
    /// screen 19 (E95). A photographed removed tree reached from the almanac still draws the row —
    /// E95's own open residual — and the heart is the one cell in it that costs nothing there.
    @Test("a removed tree can be favourited, and un-favourited afterwards")
    func aMemorialMayBeFavorited() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let outbox = OutboxQueue(queue: store.queue, transport: APIOutboxTransport(api: api))
        let tree = try await Self.makeTree(api: api)

        // Favourited while it was standing.
        let clientUUID = UUID()
        _ = try await FavoriteOutboxWriter.save(
            treeID: tree.id,
            isFavorite: true,
            attribution: await api.attribution,
            outbox: outbox,
            clientUUID: clientUUID
        )

        // The city's next sync removes it, and the profile becomes a memorial (DECISIONS §3.17).
        try await store.queue.write { connection in
            try connection.execute(
                "UPDATE community_trees SET status = 'removed' WHERE id = '\(tree.id.uuidString)'"
            )
        }
        #expect(try await api.treeProfile(id: tree.id).tree.status.acceptsNewContributions == false)

        // The heart still comes off, which is the whole argument.
        _ = try await FavoriteOutboxWriter.save(
            treeID: tree.id,
            isFavorite: false,
            attribution: await api.attribution,
            outbox: outbox
        )
        let stored = try await Self.rows(in: store)
        #expect(stored.count == 1)
        #expect(stored.first?.isActive == false)
    }

    // MARK: - The shapes that must stay unrepresentable

    @Test("a favourite's owner round-trips through the outbox payload as exactly one owner")
    func ownerEncodesAsOneKey() throws {
        for owner in [FavoriteOwner.user(Self.userID), .device(Self.deviceID)] {
            let toggle = FavoriteToggle(owner: owner, treeID: UUID(), isFavorite: true)
            let data = try OutboxPayload.favoriteToggle(toggle).encoded()
            let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            let ownerKeys = try #require(json["owner"] as? [String: Any]).keys
            #expect(ownerKeys.count == 1, "an owner encoded as \(ownerKeys)")

            let decoded = try OutboxPayload.decode(kind: .favoriteToggle, from: data)
            guard case let .favoriteToggle(round) = decoded else {
                Issue.record("a favourite payload decoded as \(decoded)")
                return
            }
            #expect(round.owner == owner)
            #expect(round.clientUUID == toggle.clientUUID)
        }
    }

    @Test("an ownerless favourite payload does not decode into an ownerless favourite")
    func ownerlessPayloadIsRefused() throws {
        let toggle = FavoriteToggle(owner: .device(Self.deviceID), treeID: UUID(), isFavorite: true)
        let encoded = try OutboxPayload.favoriteToggle(toggle).encoded()
        var json = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(try OutboxPayload.decode(kind: .favoriteToggle, from: encoded).treeID == toggle.treeID)

        json["owner"] = [String: Any]()
        let ownerless = try JSONSerialization.data(withJSONObject: json)
        #expect(throws: (any Error).self) {
            _ = try OutboxPayload.decode(kind: .favoriteToggle, from: ownerless)
        }
    }

    @Test("the favourite owner follows D9: the account when there is one, the device otherwise")
    func ownerFollowsAttribution() {
        #expect(FavoriteOwner(Attribution.anonymous(deviceID: Self.deviceID)) == .device(Self.deviceID))
        #expect(FavoriteOwner(Attribution(userID: Self.userID, deviceID: Self.deviceID)) == .user(Self.userID))
        #expect(FavoriteOwner.device(Self.deviceID).adopted(by: Self.userID) == .user(Self.userID))
        // Adoption never re-homes an account's favourite onto another account.
        #expect(FavoriteOwner.user(Self.userID).adopted(by: Self.strangerID) == .user(Self.userID))
    }
}
