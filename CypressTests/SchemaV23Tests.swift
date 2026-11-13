import Foundation
import Testing
@testable import Cypress

/// **What migration v23 does to a database that already has community trees and a queue in it.**
///
/// v23 gives a community tree an adder (`community_trees.user_id` / `device_id`), gives its pin a
/// chain (`tree_locations`, with a root backfilled for every tree already here), adds the cache of
/// other people's trees and its per-tile cursors, and widens `outbox.kind` to admit
/// `location_correction` and the reserved `tree_withdrawal` — a table rebuild, the seventh (v4, v15,
/// v17, v18, v21, v22, v23), with v21's parking of `outbox_photos` because the drop cascades.
///
/// `DataGates.sqliteStore` runs the ladder on an empty database; this is the part that needs rows:
///
/// 1. a v22 database reaches 23 by exactly one step, and 23 is the newest;
/// 2. the staged binaries survive the rebuild, and the counter still counts them;
/// 3. every tree already here gets an adder and a root — this installation's own owner, the account
///    when one is signed in and the device otherwise, because `addTree` is the only writer the
///    table has ever had (owner's ruling of 2026-11-12) — and the root is the tree's own id,
///    uppercase whatever the row held, at the tree's position; the owner can move the pin, and a
///    queued item of every kind survives the outbox rebuild;
/// 4. the vocabulary widened, both values, and still refuses a value it does not know;
/// 5. the schema's own rules hold: one head per chain, at most one adder, and a cached copy of a
///    tree this phone added cannot be stored.
///
/// **When v24 lands**, filter this suite's ladder to `<= 23` the way `SchemaV22Tests.ladder` is
/// filtered, and move the `currentVersion` expectation below into v24's own file.
@Suite("AppSchema · v23")
struct SchemaV23Tests {

    private static let moment = Date(timeIntervalSince1970: 1_796_000_000)
    private static var version: Int32 { 23 }

    /// A pre-v23 tree, stored with a **lowercase** id — the spelling a JSON round trip produces —
    /// so the backfill's `upper()` is measured rather than assumed.
    private static let legacyTree = UUID(uuidString: "5A000000-0000-4000-8000-0000000C2301")!
    private static let legacyKey = UUID(uuidString: "5A000000-0000-4000-8000-0000000C2302")!
    private static let queuedItem = UUID(uuidString: "5A000000-0000-4000-8000-0000000C2303")!
    private static let binary = UUID(uuidString: "5A000000-0000-4000-8000-0000000C2304")!
    /// This installation, as `app_state.device_uuid` names it, and an account signed in on it.
    private static let device = UUID(uuidString: "5A000000-0000-4000-8000-0000000C2305")!
    private static let account = UUID(uuidString: "5A000000-0000-4000-8000-0000000C2306")!

    /// Every kind a v22 queue admits (v22's CHECK, copied into v23's), one pending item each.
    private static let v22Kinds = [
        "visit", "observation", "measurement", "care_event", "favorite_toggle", "private_reminder",
        "add_tree", "species_claim", "species_correction", "wrong_species_report",
        "never_existed_report", "species_review_dismissal", "record_review_dismissal", "photo_vote",
        "photo_withdrawal", "hazard_redirect", "measurement_withdrawal", "data_dispute",
        "data_dispute_withdrawal",
    ]

    /// A v22 database holding one community tree and one queued visit with one staged binary,
    /// written **as rows** for `SchemaV21Tests.v20Database`'s reason. `deviceUUID` and
    /// `signedInAs` are the installation's identity in `app_state`, which is what the adder
    /// backfill reads; `everyKind` adds one more pending item of every kind a v22 queue admits.
    private static func v22Database(
        deviceUUID: UUID? = device,
        signedInAs userID: UUID? = nil,
        everyKind: Bool = false
    ) async throws -> CypressStore {
        let store = try await CypressStore.inMemory(
            migrations: AppSchema.migrations.filter { $0.version <= 22 }
        )
        let stamp = SQLiteTimestamp.string(from: moment)
        try await store.queue.write { connection in
            let opened = try connection.userVersion
            #expect(opened == 22, "the fixture opened at user_version \(opened), not 22")
            #expect(
                !(try connection.columnNames(ofTable: "community_trees").contains("user_id")),
                "a v22 database already had the adder column"
            )
            try connection.execute("""
                INSERT INTO community_trees
                    (id, client_uuid, lat, lon, placement, created_at, updated_at)
                VALUES ('\(legacyTree.uuidString.lowercased())', '\(legacyKey.uuidString)',
                        37.7601, -122.5401, 'contributor_placed', '\(stamp)', '\(stamp)');
                INSERT INTO outbox
                    (seq, id, kind, client_uuid, payload, photo_paths, photos_outstanding,
                     state, fail_count, local_applied, remote_sent, window_started_at,
                     created_at, updated_at)
                VALUES (10, '\(queuedItem.uuidString)', 'visit', '\(UUID().uuidString)',
                        '{"note":"queued"}', '[]', 0, 'pending', 0, 1, 0, '\(stamp)',
                        '\(stamp)', '\(stamp)');
                INSERT INTO outbox_photos
                    (id, outbox_id, path, shot_type, state, sendable, fail_count, created_at, updated_at)
                VALUES ('\(binary.uuidString)', '\(queuedItem.uuidString)', '/staged/one.jpg',
                        'full_tree', 'pending', 1, 0, '\(stamp)', '\(stamp)');
                """)
            if let deviceUUID {
                try connection.execute("""
                    INSERT INTO app_state (key, value) VALUES ('device_uuid', '\(deviceUUID.uuidString)');
                    """)
            }
            if let userID {
                try connection.execute("""
                    INSERT INTO app_state (key, value) VALUES ('current_user_id', '\(userID.uuidString)');
                    """)
            }
            if everyKind {
                for (offset, kind) in v22Kinds.enumerated() {
                    try connection.execute("""
                        INSERT INTO outbox
                            (seq, id, kind, client_uuid, payload, photo_paths, photos_outstanding,
                             state, fail_count, local_applied, remote_sent, window_started_at,
                             created_at, updated_at)
                        VALUES (\(100 + offset), '\(kindItem(offset).uuidString)', '\(kind)',
                                '\(UUID().uuidString)', '{"kind":"\(kind)"}', '[]', 0, 'pending', 0,
                                1, 0, '\(stamp)', '\(stamp)', '\(stamp)');
                        """)
                }
            }
        }
        return store
    }

    /// The queue key of `v22Kinds[offset]`'s item.
    private static func kindItem(_ offset: Int) -> UUID {
        UUID(uuidString: String(format: "5A000000-0000-4000-8000-0000000C24%02d", offset))!
    }

    private static func scalar(_ sql: String, _ connection: SQLiteConnection) throws -> String? {
        let statement = try connection.prepare(sql)
        defer { statement.finalize() }
        return try statement.fetchOne { try $0.stringIfPresent("v") } ?? nil
    }

    // MARK: - 1. The ladder

    @Test("a v22 database with trees and a queue is carried to 23 by exactly one migration")
    func aV22DatabaseRunsOnlyV23() async throws {
        let store = try await Self.v22Database()
        let applied = try await store.queue.write { connection in
            try SchemaMigrator.migrate(AppSchema.migrations, on: connection)
        }
        #expect(
            applied == [Self.version],
            """
            a v22 database applied \(applied) rather than [\(Self.version)]. If this is a longer \
            list, another migration was added without this fixture being moved forward — filter the \
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

    // MARK: - 2. The binaries

    /// Red-proof: delete the parking block from `applyV23` — red on "the rebuild lost the staged
    /// binary" (the drop cascades `outbox_photos`).
    @Test("the staged binary survives the rebuild, and the counter still counts it")
    func theStagedBinarySurvives() async throws {
        let store = try await Self.v22Database()
        let before = try await store.queue.read { connection in
            try Self.scalar("SELECT CAST(photos_outstanding AS TEXT) AS v FROM outbox", connection)
        }
        #expect(before == "1", "fixture: the counter reads \(before ?? "nil") before the migration")

        _ = try await store.queue.write { try SchemaMigrator.migrate(AppSchema.migrations, on: $0) }

        let (path, owner, counter) = try await store.queue.read { connection in
            (
                try Self.scalar("SELECT path AS v FROM outbox_photos", connection),
                try Self.scalar("SELECT outbox_id AS v FROM outbox_photos", connection),
                try Self.scalar("SELECT CAST(photos_outstanding AS TEXT) AS v FROM outbox", connection)
            )
        }
        #expect(path == "/staged/one.jpg", "the rebuild lost the staged binary")
        #expect(owner == Self.queuedItem.uuidString, "the binary is on another item now")
        #expect(counter == "1", "the counter reads \(counter ?? "nil") after the rebuild")
    }

    // MARK: - 3. The roots

    /// Red-proofs, each read by its message: drop `upper()` from the backfill's id — red on the
    /// root's id, which keeps the lowercase spelling and no longer equals `tree.id` under the BINARY
    /// head index; delete the two `UPDATE community_trees` statements from `applyV23` — red on
    /// "the migration gave a pre-v23 tree nobody", and on the root's owner.
    @Test("every tree already here gets this device as its adder and a root: its own id, uppercase, at its position")
    func everyTreeGetsARoot() async throws {
        let store = try await Self.v22Database()
        _ = try await store.queue.write { try SchemaMigrator.migrate(AppSchema.migrations, on: $0) }

        let chain = try await store.queue.read {
            try TreeLocationStore().chain(treeID: Self.legacyTree, connection: $0)
        }
        #expect(chain.count == 1, "the backfill wrote \(chain.count) positions for one tree")
        let root = try #require(chain.first)
        #expect(root.id == Self.legacyTree && root.isRoot)
        #expect(root.clientUUID == Self.legacyKey, "the root is not keyed on the add")
        #expect(root.coordinate == Coordinate(latitude: 37.7601, longitude: -122.5401))
        #expect(root.placement == .contributorPlaced)
        #expect(root.owner == .device(Self.device), "the root's owner is \(root.owner), not this device")
        #expect(root.occurredAt == Self.moment && root.isCurrent)

        let stored = try await store.queue.read { connection in
            try Self.scalar("SELECT id AS v FROM tree_locations", connection)
        }
        #expect(stored == Self.legacyTree.uuidString, "the root's id is spelled \(stored ?? "nil")")

        let adder = try await store.queue.read {
            try CommunityTreeStore().adder(treeID: Self.legacyTree, connection: $0)
        }
        #expect(adder != .nobody, "the migration gave a pre-v23 tree nobody")
        #expect(adder == .device(Self.device), "the adder is \(String(describing: adder)), not this device")
    }

    /// The account arm: a phone signed in when it migrates names the account, as `addTree`'s
    /// `ContributionOwner(attribution)` does. Red-proof: swap the two `UPDATE`s' keys in `applyV23`
    /// — red on "the adder is .device(…), not the account".
    @Test("a phone signed in when it migrates gives its trees to the account, as addTree would")
    func aSignedInPhoneGivesItsTreesToTheAccount() async throws {
        let store = try await Self.v22Database(signedInAs: Self.account)
        _ = try await store.queue.write { try SchemaMigrator.migrate(AppSchema.migrations, on: $0) }
        let adder = try await store.queue.read {
            try CommunityTreeStore().adder(treeID: Self.legacyTree, connection: $0)
        }
        #expect(adder == .user(Self.account), "the adder is \(String(describing: adder)), not the account")
        let root = try #require(try await store.queue.read {
            try TreeLocationStore().chain(treeID: Self.legacyTree, connection: $0)
        }.first)
        #expect(root.owner == .user(Self.account), "the root's owner is \(root.owner), not the account")
    }

    /// v12's third case: a database with no identity at all has never run `addTree`, so there is
    /// nobody to name, and the CHECK admits nobody.
    @Test("a database with no installation identity leaves the tree nobody's")
    func noIdentityLeavesNobody() async throws {
        let store = try await Self.v22Database(deviceUUID: nil)
        _ = try await store.queue.write { try SchemaMigrator.migrate(AppSchema.migrations, on: $0) }
        let adder = try await store.queue.read {
            try CommunityTreeStore().adder(treeID: Self.legacyTree, connection: $0)
        }
        #expect(adder == .nobody, "the adder is \(String(describing: adder)) with no identity to give")
    }

    /// The point of the backfill, end to end: after the migration the tree's owner moves its pin,
    /// and every item that was waiting in the v22 queue, of every kind, is still waiting, unchanged.
    ///
    /// Red-proofs: delete the two `UPDATE community_trees` statements — red on the move, which
    /// throws `forbidden`; drop one kind (say `photo_vote`) from v23's CHECK — the migration's
    /// `INSERT … SELECT` fails, and the test fails on that throw.
    @Test("after v23 the owner moves a pre-v23 tree's pin, and a queued item of every kind survives")
    func theOwnerMovesAPreV23TreeAndTheQueueSurvives() async throws {
        let store = try await Self.v22Database(everyKind: true)
        _ = try await store.queue.write { try SchemaMigrator.migrate(AppSchema.migrations, on: $0) }

        let survivors = try await store.queue.read { connection -> [String: String] in
            let statement = try connection.prepare(
                "SELECT id, kind || '|' || payload || '|' || state || '|' || seq AS v FROM outbox"
            )
            defer { statement.finalize() }
            let pairs = try statement.fetchAll { (try $0.string("id"), try $0.string("v")) }
            return Dictionary(uniqueKeysWithValues: pairs)
        }
        #expect(survivors.count == Self.v22Kinds.count + 1, "the rebuild kept \(survivors.count) items")
        for (offset, kind) in Self.v22Kinds.enumerated() {
            let row = survivors[Self.kindItem(offset).uuidString]
            #expect(
                row == "\(kind)|{\"kind\":\"\(kind)\"}|pending|\(100 + offset)",
                "the queued \(kind) item came out of the rebuild as \(row ?? "nothing")"
            )
        }

        let api = LocalAPI(store: store, deviceID: Self.device)
        let destination = Coordinate(latitude: 37.7604, longitude: -122.5401)
        let moved = try await api.correctLocation(
            treeID: Self.legacyTree, to: destination, placement: .contributorPlaced, locationAccuracyM: nil
        )
        #expect(moved.coordinate == destination, "the pre-v23 tree did not move: \(moved.coordinate)")
        let queued = try await store.queue.read { try OutboxStore().allItems(connection: $0) }
            .filter { $0.item.kind == .locationCorrection }
        #expect(queued.count == 1, "the move queued \(queued.count) corrections")
    }

    // MARK: - 4. The vocabulary

    @Test("the queue admits location_correction and the reserved tree_withdrawal, and nothing else new")
    func theVocabularyWidened() async throws {
        let store = try await Self.v22Database()
        _ = try await store.queue.write { try SchemaMigrator.migrate(AppSchema.migrations, on: $0) }
        let stamp = SQLiteTimestamp.string(from: Self.moment)

        func enqueue(_ kind: String) async -> (any Error)? {
            do {
                try await store.queue.write { connection in
                    try connection.execute("""
                        INSERT INTO outbox (id, kind, client_uuid, payload, photo_paths, state,
                                            local_applied, window_started_at, created_at, updated_at)
                        VALUES ('\(UUID().uuidString)', '\(kind)', '\(UUID().uuidString)', '{}', '[]',
                                'pending', 1, '\(stamp)', '\(stamp)', '\(stamp)');
                        """)
                }
                return nil
            } catch {
                return error
            }
        }
        // The control first: a value the CHECK has never admitted is refused, so the two
        // acceptances below are the CHECK's answer rather than the absence of one.
        #expect(await enqueue("location_move") != nil, "the queue admitted a kind nobody declared")
        for kind in ["location_correction", "tree_withdrawal"] {
            let error = await enqueue(kind)
            #expect(error == nil, "the queue refused \(kind): \(String(describing: error))")
        }
    }

    // MARK: - 5. The schema's own rules

    @Test("a chain has one head, a tree has at most one adder, and a cached copy of a tree added here is ignored")
    func theSchemaKeepsItsRules() async throws {
        let store = try await Self.v22Database()
        _ = try await store.queue.write { try SchemaMigrator.migrate(AppSchema.migrations, on: $0) }
        let stamp = SQLiteTimestamp.string(from: Self.moment)

        // A second head for the legacy tree.
        await #expect(throws: SQLiteError.self, "a second head was stored beside the root") {
            try await store.queue.write { connection in
                try connection.execute("""
                    INSERT INTO tree_locations
                        (id, tree_id, client_uuid, lat, lon, placement, occurred_at, created_at, updated_at)
                    VALUES ('\(UUID().uuidString)', '\(Self.legacyTree.uuidString)', '\(UUID().uuidString)',
                            37.76, -122.54, 'gps', '\(stamp)', '\(stamp)', '\(stamp)');
                    """)
            }
        }

        // Both owners on one tree.
        await #expect(throws: SQLiteError.self, "a tree was stored with two adders") {
            try await store.queue.write { connection in
                try connection.execute("""
                    UPDATE community_trees SET user_id = '\(UUID().uuidString)', device_id = '\(UUID().uuidString)'
                    """)
            }
        }

        // The phone's own row wins at the door, in the service's lowercase.
        try await store.queue.write { connection in
            try connection.execute("""
                INSERT INTO community_tree_cache
                    (id, lat, lon, placement, status, verification_state, created_at, updated_at,
                     tile, fetched_at)
                VALUES ('\(Self.legacyTree.uuidString.lowercased())', 1, 1, 'gps', 'alive',
                        'unverified', '\(stamp)', '\(stamp)', 't', '\(stamp)');
                """)
        }
        let cached = try await store.queue.read { connection in
            try Self.scalar("SELECT CAST(COUNT(*) AS TEXT) AS v FROM community_tree_cache", connection)
        }
        #expect(cached == "0", "a cached copy of a tree this phone added was stored")
    }
}
