import Foundation
import Testing
@testable import Cypress

/// **What migration v24 does to a database that already has pin positions in it.**
///
/// v24 adds `tree_locations.set_on_device`, the installation that set each position (the owner's
/// decision of 2026-11-16, ROADMAP chip 152), and fills it for the rows already here. The sentences
/// this suite makes true:
///
/// 1. a v23 database reaches 24 by exactly one step, and 24 is the newest;
/// 2. the fill names this installation on a row this installation owns and on a row an account
///    owns, and on no other: not an anonymized row (neither owner), and not a row a different
///    installation owns;
/// 3. the fill changes no row's owner;
/// 4. a replay changes nothing, on a database that already has the column;
/// 5. a stored device id that is not a UUID fills nothing, so every chain still decodes.
///
/// **When v25 lands**, filter this suite's ladder test to `<= 24` the way `SchemaV23Tests.ladder`
/// is filtered, and move the `currentVersion` expectation below into v25's own file.
@Suite("AppSchema · v24")
struct SchemaV24Tests {

    private static var version: Int32 { 24 }
    private static let stamp = "2026-11-16T12:00:00.000Z"

    /// This installation, as `app_state.device_uuid` names it.
    private static let device = UUID(uuidString: "5A000000-0000-4000-8000-0000000C2401")!
    private static let account = UUID(uuidString: "5A000000-0000-4000-8000-0000000C2402")!
    private static let otherDevice = UUID(uuidString: "5A000000-0000-4000-8000-0000000C2403")!

    /// One position per case, each on its own tree so each is its tree's only head.
    private static let ownedByThisDevice = UUID(uuidString: "5A000000-0000-4000-8000-0000000C2411")!
    private static let ownedByAccount = UUID(uuidString: "5A000000-0000-4000-8000-0000000C2412")!
    private static let anonymized = UUID(uuidString: "5A000000-0000-4000-8000-0000000C2413")!
    private static let ownedByOtherDevice = UUID(uuidString: "5A000000-0000-4000-8000-0000000C2414")!

    /// A v23 database holding the four positions, written as rows. The device-owned row stores this
    /// installation's id in **lowercase**, the spelling a JSON round trip produces, so the fill's
    /// `COLLATE NOCASE` is measured rather than assumed.
    ///
    /// `deviceValue` is what `app_state.device_uuid` holds, as text, so a corrupted value can be
    /// stored; nil stores no row.
    private static func v23Database(deviceValue: String? = device.uuidString) async throws -> CypressStore {
        let store = try await CypressStore.inMemory(
            migrations: AppSchema.migrations.filter { $0.version <= 23 }
        )
        try await store.queue.write { connection in
            let opened = try connection.userVersion
            #expect(opened == 23, "the fixture opened at user_version \(opened), not 23")
            #expect(
                !(try connection.columnNames(ofTable: "tree_locations").contains("set_on_device")),
                "a v23 database already had the provenance column"
            )
            let rows: [(UUID, String, String)] = [
                (ownedByThisDevice, "NULL", "'\(device.uuidString.lowercased())'"),
                (ownedByAccount, "'\(account.uuidString)'", "NULL"),
                (anonymized, "NULL", "NULL"),
                (ownedByOtherDevice, "NULL", "'\(otherDevice.uuidString)'")
            ]
            for (id, user, deviceColumn) in rows {
                try connection.execute("""
                    INSERT INTO tree_locations
                        (id, tree_id, client_uuid, lat, lon, placement, user_id, device_id,
                         occurred_at, created_at, updated_at)
                    VALUES ('\(id.uuidString)', '\(UUID().uuidString)', '\(UUID().uuidString)',
                            37.76, -122.54, 'gps', \(user), \(deviceColumn),
                            '\(stamp)', '\(stamp)', '\(stamp)');
                    """)
            }
            if let deviceValue {
                try connection.execute("""
                    INSERT INTO app_state (key, value) VALUES ('device_uuid', '\(deviceValue)');
                    """)
            }
        }
        return store
    }

    /// `set_on_device` of one row: `.some(nil)` when it is NULL.
    private static func provenance(_ id: UUID, _ connection: SQLiteConnection) throws -> String?? {
        let statement = try connection.prepare(
            "SELECT set_on_device AS v FROM tree_locations WHERE id = :id"
        )
        defer { statement.finalize() }
        _ = try statement.bind([":id": id])
        return try statement.fetchOne { try $0.stringIfPresent("v") }
    }

    /// Every row's owner columns, in id order, so a change to any one of them shows.
    private static func owners(_ connection: SQLiteConnection) throws -> [String] {
        let statement = try connection.prepare("""
            SELECT id || '|' || quote(user_id) || '|' || quote(device_id) AS v
              FROM tree_locations ORDER BY id
            """)
        defer { statement.finalize() }
        return try statement.fetchAll { try $0.string("v") }
    }

    private static var v24: Migration {
        AppSchema.migrations.first { $0.version == version }!
    }

    // MARK: - 1. The ladder

    @Test("a v23 database with positions is carried to 24 by exactly one migration")
    func aV23DatabaseRunsOnlyV24() async throws {
        let store = try await Self.v23Database()
        let applied = try await store.queue.write { connection in
            try SchemaMigrator.migrate(AppSchema.migrations, on: connection)
        }
        #expect(
            applied == [Self.version],
            """
            a v23 database applied \(applied) rather than [\(Self.version)]. If this is a longer \
            list, another migration was added without this fixture being moved forward: filter the \
            ladder to `<= \(Self.version)` here and move the `currentVersion` claim below into the \
            new version's own file
            """
        )
        let version = try await store.queue.read { try $0.userVersion }
        #expect(version == AppSchema.currentVersion, "user_version is \(version)")
        #expect(
            AppSchema.currentVersion == Self.version,
            "`AppSchema.currentVersion` is \(AppSchema.currentVersion) and this file is written about \(Self.version)"
        )
    }

    // MARK: - 2. The fill

    /// Red-proofs, each read by its message: delete the `UPDATE` from `applyV24` — red on the two
    /// owned rows, which read NULL; drop its `NOT (user_id IS NULL AND device_id IS NULL)` clause —
    /// red on the anonymized row, which reads this phone; drop its `device_id` clause — red on the
    /// other installation's row.
    @Test("the fill names this phone on its own rows and the account's, and not on an anonymized or another phone's row")
    func theFillNamesOnlyRowsThisPhoneCanVouchFor() async throws {
        let store = try await Self.v23Database()
        _ = try await store.queue.write { try SchemaMigrator.migrate(AppSchema.migrations, on: $0) }

        try await store.queue.read { connection in
            let mine = Self.device.uuidString
            let own = try Self.provenance(Self.ownedByThisDevice, connection)
            #expect(own == .some(mine), "this device's own row reads \(String(describing: own)), not this phone")
            let account = try Self.provenance(Self.ownedByAccount, connection)
            #expect(account == .some(mine), "the account's row reads \(String(describing: account)), not this phone")
            let nobodys = try Self.provenance(Self.anonymized, connection)
            #expect(nobodys == .some(nil), "the anonymized row reads \(String(describing: nobodys)); it must stay nobody's")
            let theirs = try Self.provenance(Self.ownedByOtherDevice, connection)
            #expect(theirs == .some(nil), "another installation's row reads \(String(describing: theirs))")
        }

        // Through the store as well: the column decodes as the model's provenance and not as its
        // owner.
        let decoded = try await store.queue.read {
            try TreeLocationStore().chain(treeID: try Self.treeID(of: Self.ownedByAccount, $0), connection: $0)
        }
        let row = try #require(decoded.first)
        #expect(row.setOnDevice == Self.device)
        #expect(row.owner == .user(Self.account), "provenance changed the decoded owner to \(row.owner)")
    }

    /// The fresh-install case: no `device_uuid`, so nothing is named.
    @Test("with no device id stored, the fill names nobody")
    func noDeviceIDNamesNobody() async throws {
        let store = try await Self.v23Database(deviceValue: nil)
        _ = try await store.queue.write { try SchemaMigrator.migrate(AppSchema.migrations, on: $0) }
        try await store.queue.read { connection in
            for id in [Self.ownedByThisDevice, Self.ownedByAccount, Self.anonymized, Self.ownedByOtherDevice] {
                let value = try Self.provenance(id, connection)
                #expect(value == .some(nil), "\(id) reads \(String(describing: value)) with no device id stored")
            }
        }
    }

    /// A stored id that is not a UUID: empty, short, and 36 characters of the wrong kind (which a
    /// length check alone would let through).
    static let malformedDeviceValues = ["", "not-a-uuid", "ZZZZZZZZ-ZZZZ-ZZZZ-ZZZZ-ZZZZZZZZZZZZ"]

    /// The fill must never write a value the decoder refuses: `TreeLocationStore.decode` reads the
    /// column through `uuidIfPresent`, and `correctLocation` reads the chain's head before every
    /// move, so one bad value would make that tree's pin unmovable.
    ///
    /// Then a later launch with a good id (`DataLayer` mints one over a value it cannot parse).
    /// The old rows were not filled, so the account's old move is in the Journal while the account
    /// is signed in (by `user_id`) and not after sign-out. That is the known limit the header of
    /// `applyV24` states.
    ///
    /// Red-proof: remove the `GLOB` guard from `applyV24`'s fill — red on the value written and on
    /// the chain that no longer decodes.
    @Test("a stored id that is not a UUID fills nothing, and the chain still decodes", arguments: malformedDeviceValues)
    func aMalformedDeviceIDFillsNothing(value: String) async throws {
        let store = try await Self.v23Database(deviceValue: value)
        _ = try await store.queue.write { try SchemaMigrator.migrate(AppSchema.migrations, on: $0) }

        try await store.queue.read { connection in
            for id in [Self.ownedByThisDevice, Self.ownedByAccount, Self.anonymized, Self.ownedByOtherDevice] {
                let written = try Self.provenance(id, connection)
                #expect(written == .some(nil), "with device_uuid '\(value)' the row \(id) reads \(String(describing: written))")
            }
        }
        let tree = try await store.queue.read { try Self.treeID(of: Self.ownedByAccount, $0) }
        let chain: [TreeLocation]
        do {
            chain = try await store.queue.read { try TreeLocationStore().chain(treeID: tree, connection: $0) }
        } catch {
            Issue.record("with device_uuid '\(value)' the chain no longer decodes: \(error)")
            return
        }
        #expect(chain.count == 1 && chain.first?.setOnDevice == nil)

        // A later launch, with the good id `DataLayer` mints over the bad one.
        let newDevice = UUID()
        try await store.queue.write { connection in
            try connection.execute("UPDATE app_state SET value = '\(newDevice.uuidString)' WHERE key = 'device_uuid'")
        }
        let signedOut = LocalAPI(store: store, deviceID: newDevice)
        let signedIn = LocalAPI(store: store, deviceID: newDevice, userID: Self.account)
        let movesSignedOut = try await signedOut.journal(cursor: nil, limit: 25).items.filter { $0.kind == .pinMoved }
        let movesSignedIn = try await signedIn.journal(cursor: nil, limit: 25).items.filter { $0.kind == .pinMoved }
        #expect(movesSignedIn.map(\.id) == [Self.ownedByAccount], "signed in, the account's old move reads \(movesSignedIn.map(\.id))")
        #expect(movesSignedOut.isEmpty, "the known limit changed: signed out, old moves read \(movesSignedOut.map(\.id))")
    }

    // MARK: - 3. Owners

    /// Red-proof: make the fill also write `device_id = NULL` — red on the owners that changed.
    @Test("the migration changes no row's owner")
    func noOwnerChanges() async throws {
        let store = try await Self.v23Database()
        let before = try await store.queue.read { try Self.owners($0) }
        #expect(before.count == 4, "fixture: \(before)")
        _ = try await store.queue.write { try SchemaMigrator.migrate(AppSchema.migrations, on: $0) }
        let after = try await store.queue.read { try Self.owners($0) }
        #expect(after == before, "the owners changed: before \(before), after \(after)")
    }

    // MARK: - 4. Replay

    /// Red-proof: remove the column guard from `applyV24` — red on "duplicate column name". Remove
    /// `set_on_device IS NULL` from the fill — red on the row whose provenance was overwritten.
    @Test("a replay on a database that has the column changes nothing, and keeps a value already there")
    func aReplayChangesNothing() async throws {
        let store = try await Self.v23Database()
        _ = try await store.queue.write { try SchemaMigrator.migrate(AppSchema.migrations, on: $0) }

        // A position another installation set while an account owned it: the writer recorded it,
        // and a replay must not take it for this phone's.
        try await store.queue.write { connection in
            try connection.execute("""
                UPDATE tree_locations SET set_on_device = '\(Self.otherDevice.uuidString)'
                 WHERE id = '\(Self.ownedByAccount.uuidString)'
                """)
        }
        let snapshot = { (connection: SQLiteConnection) throws -> [String] in
            let statement = try connection.prepare("""
                SELECT id || '|' || quote(user_id) || '|' || quote(device_id) || '|' || quote(set_on_device) AS v
                  FROM tree_locations ORDER BY id
                """)
            defer { statement.finalize() }
            return try statement.fetchAll { try $0.string("v") }
        }
        let before = try await store.queue.read(snapshot)
        try await store.queue.write { connection in try Self.v24.migrate(connection) }
        let after = try await store.queue.read(snapshot)
        #expect(after == before, "a replay changed rows: before \(before), after \(after)")
    }

    private static func treeID(of id: UUID, _ connection: SQLiteConnection) throws -> UUID {
        let statement = try connection.prepare("SELECT tree_id FROM tree_locations WHERE id = :id")
        defer { statement.finalize() }
        _ = try statement.bind([":id": id])
        return try statement.fetchOne { try $0.uuid("tree_id") }!
    }
}
