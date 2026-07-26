import Foundation
import Testing
@testable import Cypress

/// `photos` learns whose it is — `AppSchema` v12, closing the hole ERRATA **E136** pinned and
/// ERRATA **E147** records.
///
/// The sentences this suite has to make true:
///
/// 1. **every write path records an owner** — the visit's photograph and, the one that was missing,
///    the photograph `addTree` writes for a tree somebody adds;
/// 2. **the engine carries the rule**, not the DAO: a photograph owned twice is refused by SQLite
///    against a hand-written `INSERT`, and a photograph owned by *nobody* is accepted, because that
///    is the state the anonymizing door leaves behind and v8's `photo_votes` CHECK is the standing
///    lesson about forbidding it;
/// 3. **an upgrade attributes what was already on the disk** — a v11 database's photographs come out
///    the other side owned, including the visitless ones that had nothing to be derived from;
/// 4. **sign-in adopts them**, as it adopts a reminder, and cannot steal an already-attributed one
///    or resurrect an anonymized one.
@Suite("Photo ownership")
struct PhotoOwnershipTests {

    private static let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-00000000A001")!
    private static let userID = UUID(uuidString: "0E000000-0000-4000-8000-00000000A002")!
    private static let strangerID = UUID(uuidString: "0E000000-0000-4000-8000-00000000A003")!
    private static let moment = Date(timeIntervalSince1970: 1_800_000_000)

    /// A photo directory of its own per API, because an in-memory store's database URL resolves to
    /// the root and `beginPhotoUpload` would try to create `/Photos`.
    private static func api(store: CypressStore, userID: UUID?) -> LocalAPI {
        LocalAPI(
            store: store,
            deviceID: deviceID,
            userID: userID,
            photoDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("cypress-ownership-\(UUID().uuidString)", isDirectory: true),
            now: { moment }
        )
    }

    private static func owner(of photoID: UUID, in store: CypressStore) async throws -> PhotoOwner {
        try await store.queue.read { connection in
            try #require(
                try ContributionStore().photoForDeletion(id: photoID, connection: connection),
                "no live photograph \(photoID)"
            ).owner
        }
    }

    private static func addATree(_ api: LocalAPI, at longitude: Double = -122.44) async throws -> Tree {
        try await api.addTree(
            TreeDraft(
                coordinate: Coordinate(latitude: 37.77, longitude: longitude),
                photoLocalPath: "/tmp/cypress-ownership-\(UUID().uuidString).jpg",
                attribution: Attribution(userID: nil, deviceID: deviceID)
            )
        )
    }

    private static func photoID(ofTree treeID: UUID, in store: CypressStore) async throws -> UUID {
        try await store.queue.read { connection in
            try #require(
                try ContributionStore().photos(treeID: treeID, connection: connection).items.first,
                "the tree has no photograph"
            ).id
        }
    }

    // MARK: - The write paths

    /// The exact row E136 named. Before v12 this photograph had no owner anywhere in the schema:
    /// `visit_id` is NULL because a community add has no visit, and `community_trees` records no
    /// author. The assertion is that it now names the account that added the tree.
    @Test("the photograph on a tree you add is owned by whoever added the tree")
    func addTreeRecordsThePhotographsOwner() async throws {
        let store = try await CypressStore.inMemory()
        let signedIn = Self.api(store: store, userID: Self.userID)
        let tree = try await Self.addATree(signedIn)
        let photo = try await Self.photoID(ofTree: tree.id, in: store)

        #expect(try await Self.owner(of: photo, in: store) == .user(Self.userID))
        // And it really is the visitless row, so this test cannot pass by accident against a
        // photograph that had a visit to inherit from.
        let visitless = try await store.queue.read { connection -> Int in
            let statement = try connection.prepare(
                "SELECT COUNT(*) AS n FROM photos WHERE visit_id IS NULL AND user_id IS NOT NULL"
            )
            defer { statement.finalize() }
            return try statement.fetchOne { try $0.int("n") } ?? -1
        }
        #expect(visitless == 1)
    }

    /// The same write before there is an account: the device owns it, and the device is what
    /// `claimDevice` later moves.
    @Test("a tree added before sign-in leaves its photograph owned by the device")
    func addTreeBeforeSignInRecordsTheDevice() async throws {
        let store = try await CypressStore.inMemory()
        let anonymous = Self.api(store: store, userID: nil)
        let tree = try await Self.addATree(anonymous)
        let photo = try await Self.photoID(ofTree: tree.id, in: store)

        #expect(try await Self.owner(of: photo, in: store) == .device(Self.deviceID))
    }

    /// The ordinary path — the photograph of a visit — which had a derivable owner before v12 and
    /// now states it on its own row.
    @Test("a photograph staged for upload is owned by whoever staged it")
    func beginPhotoUploadRecordsTheOwner() async throws {
        let store = try await CypressStore.inMemory()
        let signedIn = Self.api(store: store, userID: Self.userID)
        let tree = try await Self.addATree(signedIn)

        let ticket = try await signedIn.beginPhotoUpload(
            PhotoUploadRequest(
                treeID: tree.id,
                visitID: nil,
                shotType: .trunk,
                localPath: "/tmp/cypress-staged-\(UUID().uuidString).jpg",
                capturedAt: Self.moment
            )
        )
        #expect(try await Self.owner(of: ticket.photoID, in: store) == .user(Self.userID))
    }

    // MARK: - The engine holds the rule

    /// The CHECK is the invariant, so it binds a hand-written `INSERT` in a debugger and not only
    /// the DAO — this file's standing promise about every other closed rule in the schema.
    @Test("the engine refuses a photograph owned twice")
    func aDoublyOwnedPhotographIsRefused() async throws {
        let store = try await CypressStore.inMemory()
        let stamp = SQLiteTimestamp.string(from: Self.moment)
        await #expect(throws: SQLiteError.self) {
            try await store.queue.write { connection in
                try connection.execute("""
                    INSERT INTO photos
                        (id, tree_uuid, shot_type, captured_at, created_at, updated_at,
                         user_id, device_id)
                    VALUES ('\(UUID().uuidString)','\(UUID().uuidString)','full_tree',
                            '\(stamp)','\(stamp)','\(stamp)',
                            '\(Self.userID.uuidString)','\(Self.deviceID.uuidString)')
                    """)
            }
        }
    }

    /// **The half of the CHECK that is deliberately absent**, and the reason v12 is not a copy of
    /// v5. An ownerless photograph has to be storable, because it is what the leaving door of an
    /// account deletion produces. `photo_votes` v8 forbade exactly this state and v9 had to be
    /// written to take it back; this test is that lesson pinned rather than repeated.
    @Test("the engine accepts a photograph owned by nobody")
    func anOwnerlessPhotographIsAccepted() async throws {
        let store = try await CypressStore.inMemory()
        let stamp = SQLiteTimestamp.string(from: Self.moment)
        let id = UUID()
        try await store.queue.write { connection in
            try connection.execute("""
                INSERT INTO photos
                    (id, tree_uuid, shot_type, captured_at, created_at, updated_at)
                VALUES ('\(id.uuidString)','\(UUID().uuidString)','full_tree',
                        '\(stamp)','\(stamp)','\(stamp)')
                """)
        }
        #expect(try await Self.owner(of: id, in: store) == .nobody)
    }

    // MARK: - The upgrade

    /// A database written by the previous build. This is the path that can lose somebody's data and
    /// the one a fresh install never runs.
    ///
    /// Three rows, because the backfill has three different jobs: a photograph on a signed-in
    /// person's visit, a photograph on an anonymous device's visit, and the visitless one that has
    /// nothing at all to derive from and is the whole reason E136 exists.
    @Test("photographs written before the column come out of the upgrade owned")
    func theUpgradeAttributesExistingPhotographs() async throws {
        let connection = try SQLiteConnection(path: ":memory:")
        _ = try SchemaMigrator.migrate(AppSchema.migrations.filter { $0.version <= 11 }, on: connection)
        #expect(
            !(try connection.columnNames(ofTable: "photos").contains("user_id")),
            "a v11 database already had the column"
        )

        let stamp = SQLiteTimestamp.string(from: Self.moment)
        let attributedVisit = UUID(), anonymousVisit = UUID()
        let onAnAccountsVisit = UUID(), onADevicesVisit = UUID(), withNoVisit = UUID()
        let tree = UUID()

        try connection.execute("""
            INSERT INTO app_state (key, value) VALUES
                ('device_uuid','\(Self.deviceID.uuidString)'),
                ('current_user_id','\(Self.userID.uuidString)');

            INSERT INTO visits (id, tree_uuid, user_id, device_id, client_uuid,
                                captured_at, created_at, updated_at)
            VALUES ('\(attributedVisit.uuidString)','\(tree.uuidString)',
                    '\(Self.userID.uuidString)','\(Self.deviceID.uuidString)','\(UUID().uuidString)',
                    '\(stamp)','\(stamp)','\(stamp)'),
                   ('\(anonymousVisit.uuidString)','\(tree.uuidString)',
                    NULL,'\(Self.deviceID.uuidString)','\(UUID().uuidString)',
                    '\(stamp)','\(stamp)','\(stamp)');

            INSERT INTO photos (id, tree_uuid, visit_id, shot_type, captured_at, created_at, updated_at)
            VALUES ('\(onAnAccountsVisit.uuidString)','\(tree.uuidString)','\(attributedVisit.uuidString)',
                    'full_tree','\(stamp)','\(stamp)','\(stamp)'),
                   ('\(onADevicesVisit.uuidString)','\(tree.uuidString)','\(anonymousVisit.uuidString)',
                    'trunk','\(stamp)','\(stamp)','\(stamp)'),
                   ('\(withNoVisit.uuidString)','\(tree.uuidString)',NULL,
                    'full_tree','\(stamp)','\(stamp)','\(stamp)');
            """)

        // Every step above 11 rather than literally `[12]`, so this gate does not fail the day an
        // unrelated migration is added.
        let expected = AppSchema.migrations.map(\.version).filter { $0 > 11 }
        let applied = try SchemaMigrator.migrate(AppSchema.migrations, on: connection)
        #expect(applied == expected, "migrating a v11 database applied \(applied), expected \(expected)")
        #expect(try connection.userVersion == AppSchema.currentVersion)

        let store = ContributionStore()
        func owner(_ id: UUID) throws -> PhotoOwner {
            try #require(try store.photoForDeletion(id: id, connection: connection)).owner
        }
        #expect(try owner(onAnAccountsVisit) == .user(Self.userID), "a visit's photograph lost its account")
        #expect(try owner(onADevicesVisit) == .device(Self.deviceID), "an anonymous visit's photograph")
        // The row E136 was written about. Nothing in the schema could have said whose it was; the
        // backfill knows it anyway, because `main.photos` holds only what this installation wrote.
        #expect(try owner(withNoVisit) == .user(Self.userID), "the visitless photograph stayed unowned")

        // Replaying the step is a no-op rather than "duplicate column name" — a run interrupted
        // between the DDL and the version bump replays.
        try AppSchema.migrations.first(where: { $0.version == 12 })?.migrate(connection)
        #expect(try owner(withNoVisit) == .user(Self.userID), "the replay disturbed the backfill")

        // And the CHECK the upgraded database gained is the CHECK a fresh one has.
        #expect(throws: SQLiteError.self) {
            try connection.execute("""
                UPDATE photos SET device_id = '\(Self.deviceID.uuidString)'
                 WHERE id = '\(onAnAccountsVisit.uuidString)'
                """)
        }
    }

    /// The same upgrade on a phone that has never been signed in: there is no account to attribute
    /// to and the device is the honest answer.
    @Test("an upgrade with no account attributes the visitless photograph to the device")
    func theUpgradeFallsBackToTheDevice() async throws {
        let connection = try SQLiteConnection(path: ":memory:")
        _ = try SchemaMigrator.migrate(AppSchema.migrations.filter { $0.version <= 11 }, on: connection)
        let stamp = SQLiteTimestamp.string(from: Self.moment)
        let id = UUID()
        try connection.execute("""
            INSERT INTO app_state (key, value) VALUES ('device_uuid','\(Self.deviceID.uuidString)');
            INSERT INTO photos (id, tree_uuid, visit_id, shot_type, captured_at, created_at, updated_at)
            VALUES ('\(id.uuidString)','\(UUID().uuidString)',NULL,'full_tree',
                    '\(stamp)','\(stamp)','\(stamp)');
            """)
        _ = try SchemaMigrator.migrate(AppSchema.migrations, on: connection)

        let owner = try #require(try ContributionStore().photoForDeletion(id: id, connection: connection)).owner
        #expect(owner == .device(Self.deviceID))
    }

    // MARK: - Adoption at sign-in

    /// D9's promise — "everything you have already done survives signing in" — now true of a
    /// photograph, on the reminder's terms: the account gains it and the device link is dropped, so
    /// the row says strictly less about the phone afterwards than before.
    @Test("signing in adopts the device's photographs and does not steal anybody else's")
    func claimDeviceAdoptsPhotographs() async throws {
        let store = try await CypressStore.inMemory()
        let anonymous = Self.api(store: store, userID: nil)
        let tree = try await Self.addATree(anonymous)
        let mine = try await Self.photoID(ofTree: tree.id, in: store)

        // A stranger's photograph on the same phone, already attributed, plus one that an account
        // deletion left owned by nobody. Neither may move.
        let stamp = SQLiteTimestamp.string(from: Self.moment)
        let theirs = UUID(), anonymized = UUID()
        try await store.queue.write { connection in
            try connection.execute("""
                INSERT INTO photos (id, tree_uuid, shot_type, captured_at, created_at, updated_at, user_id)
                VALUES ('\(theirs.uuidString)','\(tree.id.uuidString)','trunk',
                        '\(stamp)','\(stamp)','\(stamp)','\(Self.strangerID.uuidString)');
                INSERT INTO photos (id, tree_uuid, shot_type, captured_at, created_at, updated_at)
                VALUES ('\(anonymized.uuidString)','\(tree.id.uuidString)','leaf',
                        '\(stamp)','\(stamp)','\(stamp)');
                """)
        }

        try await anonymous.claimDevice(deviceUUID: Self.deviceID, userID: Self.userID)

        #expect(try await Self.owner(of: mine, in: store) == .user(Self.userID))
        #expect(try await Self.owner(of: theirs, in: store) == .user(Self.strangerID), "a claim stole a row")
        #expect(
            try await Self.owner(of: anonymized, in: store) == .nobody,
            "a claim re-attributed a photograph somebody had asked to be unlinked from"
        )

        // Claiming twice moves nothing, and a *different* account claiming afterwards moves nothing
        // either — the `user_id IS NULL` guard, which is what makes both true.
        try await anonymous.claimDevice(deviceUUID: Self.deviceID, userID: Self.strangerID)
        #expect(try await Self.owner(of: mine, in: store) == .user(Self.userID))
    }

    // MARK: - Seeing versus unmaking

    /// The two sets on `TreeProfile` are different questions and this is the row they disagree on.
    /// A photograph anonymized by an account deletion is still shown on this device — it is on the
    /// tree, which is what that door promised — and is nobody's to take back.
    @Test("an anonymized photograph is still shown and is no longer deletable")
    func seeingAndUnmakingAreDifferentSets() async throws {
        let store = try await CypressStore.inMemory()
        let signedIn = Self.api(store: store, userID: Self.userID)
        let tree = try await Self.addATree(signedIn)
        let photo = try await Self.photoID(ofTree: tree.id, in: store)

        var profile = try await signedIn.treeProfile(id: tree.id)
        #expect(profile.ownPhotoIDs.contains(photo))
        #expect(profile.deletablePhotoIDs.contains(photo))

        try await store.queue.write { connection in
            try connection.execute("UPDATE photos SET user_id = NULL WHERE id = '\(photo.uuidString)'")
        }

        profile = try await signedIn.treeProfile(id: tree.id)
        #expect(profile.ownPhotoIDs.contains(photo), "the contributor's own screen stopped showing it")
        #expect(!profile.deletablePhotoIDs.contains(photo), "an ownerless photograph offered a delete")
    }
}
