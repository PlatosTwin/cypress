import Foundation
import Testing
@testable import Cypress

/// A photograph remembers which installation took it — `AppSchema` v16, against the project owner's
/// report of 2026-08-15: photographs taken before photo deletion existed could not be deleted.
///
/// The diagnosis is short. `PhotoOwner.device` is compared against a value that lives in the same
/// file as the photographs and cannot stop matching, `.nobody` is refused on purpose, and `.user`
/// matches only while this installation is signed in as exactly that account. `claimDevice` moves a photograph onto an
/// account and clears `device_id`; E270 made an account minted in the local-account era impossible
/// to sign into again. Between them, a person's own photographs on their own phone became
/// undeletable, with no control drawn and — unlike an anonymized row — no sentence saying why.
///
/// The sentences this suite has to make true:
///
/// 1. **signing out does not take your photographs with it**, and neither does signing in as
///    somebody else afterwards — the reported defect, driven through the shipping calls;
/// 2. **the upgrade repairs what is already stranded**, because the phones this was reported from
///    already hold those rows;
/// 3. **it repairs nothing R3 refused** — an anonymized photograph gains no provenance in the
///    migration, loses it at the leaving door, and stays undeletable by everybody for ever;
/// 4. **provenance is not ownership** — it is not a third way to own a photograph, and a
///    photograph that is genuinely somebody else's is still refused.
@Suite("Photo provenance")
struct PhotoProvenanceTests {

    private static let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-0000000E0001")!
    private static let otherDeviceID = UUID(uuidString: "D0000000-0000-4000-8000-0000000E0002")!
    private static let userID = UUID(uuidString: "0E000000-0000-4000-8000-0000000E0003")!
    private static let secondUserID = UUID(uuidString: "0E000000-0000-4000-8000-0000000E0004")!
    private static let strangerID = UUID(uuidString: "0E000000-0000-4000-8000-0000000E0005")!
    private static let moment = Date(timeIntervalSince1970: 1_800_000_000)

    private static func api(_ store: CypressStore, userID: UUID? = nil) -> LocalAPI {
        LocalAPI(
            store: store,
            deviceID: deviceID,
            userID: userID,
            photoDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("cypress-provenance-\(UUID().uuidString)", isDirectory: true),
            now: { moment }
        )
    }

    /// A community tree with one photograph whose bytes are really on the disk, staged where
    /// `addTree` leaves them. The bytes matter here for the same reason they matter in
    /// `PhotoDeletionTests`: a deletion test that asserts only rows passes against a delete that
    /// leaves the picture in the container.
    private static func treeWithAPhotograph(
        _ api: LocalAPI,
        at longitude: Double = -122.44
    ) async throws -> (treeID: UUID, photoID: UUID, file: URL) {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("cypress-provenance-\(UUID().uuidString).jpg")
        try Data("a photograph of a tree".utf8).write(to: file, options: .atomic)
        let tree = try await api.addTree(
            TreeDraft(
                coordinate: Coordinate(latitude: 37.77, longitude: longitude),
                photoLocalPath: file.path,
                attribution: await api.attribution
            )
        )
        let profile = try await api.treeProfile(id: tree.id)
        let photo = try #require(profile.photos.items.first, "the add wrote no photograph")
        return (tree.id, photo.id, file)
    }

    private static func deletableIDs(
        treeID: UUID, in store: CypressStore, for api: LocalAPI
    ) async throws -> Set<UUID> {
        let who = await api.attribution
        return try await store.queue.read { connection in
            try ContributionStore().deletablePhotoIDs(treeID: treeID, attribution: who, connection: connection)
        }
    }

    private static func provenance(of photoID: UUID, in store: CypressStore) async throws -> UUID? {
        try await store.queue.read { connection in
            try ContributionStore().photoForDeletion(id: photoID, connection: connection)?.takenOnDevice
        }
    }

    // MARK: - The reported defect

    /// **The report, as an assertion.** Take a photograph, sign in — which moves it onto the account
    /// and clears `device_id` — then sign out. Before v16 the trash was no longer drawn and the call
    /// threw `forbidden`: the person's own photograph, on their own phone, with nothing on screen
    /// saying why.
    @Test("signing out does not take your photographs with it")
    func aPhotographSurvivesSigningOut() async throws {
        let store = try await CypressStore.inMemory()
        let api = Self.api(store)
        let (treeID, photoID, file) = try await Self.treeWithAPhotograph(api)

        try await api.claimDevice(deviceUUID: Self.deviceID, userID: Self.userID)
        try await api.signOut()

        #expect(
            try await Self.deletableIDs(treeID: treeID, in: store, for: api).contains(photoID),
            "the delete control was not drawn on a photograph this phone took"
        )
        let deletion = try await api.deletePhoto(id: photoID)
        #expect(deletion.photoID == photoID)
        #expect(deletion.removedFiles == 1, "the row went and the picture stayed on the disk")
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(try await api.treeProfile(id: treeID).photos.items.isEmpty)
    }

    /// The other half of the same defect, and the half no sign-in can undo: after E270 the id comes
    /// from the service, so a phone whose account was minted locally signs in as somebody else and
    /// `claimDevice` — which only takes rows where `user_id IS NULL` — walks straight past its own
    /// earlier work.
    @Test("a photograph survives a second account signing in on the same phone")
    func aPhotographSurvivesADifferentAccount() async throws {
        let store = try await CypressStore.inMemory()
        let api = Self.api(store)
        let (treeID, photoID, _) = try await Self.treeWithAPhotograph(api)

        try await api.claimDevice(deviceUUID: Self.deviceID, userID: Self.userID)
        try await api.signOut()
        try await api.claimDevice(deviceUUID: Self.deviceID, userID: Self.secondUserID)

        #expect(
            try await Self.deletableIDs(treeID: treeID, in: store, for: api).contains(photoID),
            "the photograph was left with the account that no sign-in can produce again"
        )
        _ = try await api.deletePhoto(id: photoID)
        #expect(try await api.treeProfile(id: treeID).photos.items.isEmpty)
    }

    /// Adoption must not touch the column. If `claimDevice` cleared it the way it clears `device_id`,
    /// every test above would pass on the write path and fail on the phones this was reported from.
    @Test("signing in leaves the provenance where it is")
    func claimDeviceDoesNotClearProvenance() async throws {
        let store = try await CypressStore.inMemory()
        let api = Self.api(store)
        let (_, photoID, _) = try await Self.treeWithAPhotograph(api)

        try await api.claimDevice(deviceUUID: Self.deviceID, userID: Self.userID)

        let subject = try await store.queue.read { connection in
            try ContributionStore().photoForDeletion(id: photoID, connection: connection)
        }
        #expect(try #require(subject).owner == .user(Self.userID), "the account did not adopt it")
        #expect(try #require(subject).takenOnDevice == Self.deviceID, "adoption erased the provenance")
    }

    // MARK: - The upgrade

    /// A v15 database holding the two rows the upgrade has to tell apart, migrated the rest of the
    /// way: one photograph stranded under an account (`user_id` set, `device_id` cleared — the row
    /// `claimDevice` leaves and the shape the report came from), and one anonymized by the leaving
    /// door. These are written as rows rather than driven through the shipping calls on purpose:
    /// the write path is v16's and would record provenance itself, which is the thing the migration
    /// tests must not be handed for free.
    private static func upgradedFromV15() async throws -> (
        store: CypressStore, treeID: UUID, stranded: UUID, anonymized: UUID
    ) {
        let store = try await CypressStore.inMemory(
            migrations: AppSchema.migrations.filter { $0.version <= 15 }
        )
        let stamp = SQLiteTimestamp.string(from: moment)
        let tree = UUID(), stranded = UUID(), anonymized = UUID()
        try await store.queue.write { connection in
            #expect(
                !(try connection.columnNames(ofTable: "photos").contains("taken_on_device")),
                "a v15 database already had the column"
            )
            try connection.execute("""
                INSERT INTO app_state (key, value) VALUES ('device_uuid','\(deviceID.uuidString)');
                INSERT INTO photos (id, tree_uuid, shot_type, captured_at, created_at, updated_at,
                                    user_id, device_id)
                VALUES ('\(stranded.uuidString)','\(tree.uuidString)','full_tree',
                        '\(stamp)','\(stamp)','\(stamp)','\(userID.uuidString)',NULL),
                       ('\(anonymized.uuidString)','\(tree.uuidString)','trunk',
                        '\(stamp)','\(stamp)','\(stamp)',NULL,NULL);
                """)
            let applied = try SchemaMigrator.migrate(AppSchema.migrations, on: connection)
            #expect(applied == AppSchema.migrations.map(\.version).filter { $0 > 15 })
        }
        return (store, tree, stranded, anonymized)
    }

    /// **The phones this was reported from already hold the stranded rows**, so a column that is only
    /// written going forward fixes nobody. A v15 database whose photograph belongs to an account
    /// this installation is not signed in as comes out of the upgrade deletable.
    @Test("the upgrade repairs a photograph stranded under an account that is gone")
    func theUpgradeRepairsAStrandedPhotograph() async throws {
        let (store, tree, stranded, anonymized) = try await Self.upgradedFromV15()

        // Signed out, which is the state the report came from.
        let api = Self.api(store)
        #expect(try await Self.provenance(of: stranded, in: store) == Self.deviceID)
        #expect(
            try await Self.deletableIDs(treeID: tree, in: store, for: api).contains(stranded),
            "the upgrade left the reported photograph exactly as undeletable as it was"
        )
        _ = try await api.deletePhoto(id: stranded)

        // And R3's row was not repaired with it — see the next test for what that means on the way in.
        #expect(try await Self.provenance(of: anonymized, in: store) == nil)
        await #expect(throws: APIError.forbidden) { _ = try await api.deletePhoto(id: anonymized) }
    }

    /// **The upgrade's third cell: signed in as a different account than the one the rows are
    /// stranded under.** The write-path half of this is `aPhotographSurvivesADifferentAccount`; this
    /// is the same person's phone before they update the app, which is where the report actually
    /// came from — a row left under a local-era account, and an Apple account signed in since. The
    /// third arm does not consult `:user` at all, so what is being asserted is that it does not have
    /// to: provenance names the machine, and the machine is the same one.
    @Test("the upgrade repairs a stranded photograph for a different account signed in now")
    func theUpgradeRepairsAStrandedPhotographForADifferentAccount() async throws {
        let (store, tree, stranded, _) = try await Self.upgradedFromV15()
        let api = Self.api(store, userID: Self.secondUserID)

        #expect(await api.attribution.userID == Self.secondUserID, "the fixture signed in as the wrong account")
        #expect(
            try await Self.provenance(of: stranded, in: store) == Self.deviceID,
            "the upgrade did not record which installation wrote the row"
        )
        #expect(
            try await Self.deletableIDs(treeID: tree, in: store, for: api).contains(stranded),
            "an account that is not the row's owner was refused a photograph this phone took"
        )
        _ = try await api.deletePhoto(id: stranded)
        #expect(
            !(try await Self.deletableIDs(treeID: tree, in: store, for: api).contains(stranded)),
            "the delete reported success and left the photograph"
        )
    }

    /// **What a replay of v16 must do, which is not nothing.** The step's guard covers the `ALTER`
    /// alone — `ADD COLUMN` has no `IF NOT EXISTS` — while the backfill `UPDATE` runs every time and
    /// is idempotent by construction. So this exercises the `WHERE`, not the guard: provenance is
    /// taken off the stranded row first, and the replay has to put it back (proving the backfill
    /// ran) while leaving R3's ownerless row NULL (proving the `WHERE` still skips it). Gating the
    /// `UPDATE` on the column being absent makes the first expectation red; broadening the `WHERE`
    /// makes the second.
    @Test("replaying the step re-runs the backfill and still refuses R3's row")
    func replayingTheStepRunsTheBackfillAndSkipsTheAnonymizedRow() async throws {
        let (store, _, stranded, anonymized) = try await Self.upgradedFromV15()

        try await store.queue.write { connection in
            try connection.execute(
                "UPDATE photos SET taken_on_device = NULL WHERE id = '\(stranded.uuidString)'"
            )
            // Rather than "duplicate column name", which is the whole reason the `ALTER` is guarded.
            try AppSchema.migrations.first(where: { $0.version == 16 })?.migrate(connection)
        }

        #expect(
            try await Self.provenance(of: stranded, in: store) == Self.deviceID,
            "the replay ran nothing, so a database with the column and no backfill stays stranded"
        )
        #expect(
            try await Self.provenance(of: anonymized, in: store) == nil,
            "the replay backfilled a row the leaving door emptied"
        )
    }

    // MARK: - What the repair must not reach

    /// **R3 and E157, which this column had every opportunity to repeal quietly.** The leaving door
    /// promises that a deleted account's photographs stay on their trees and belong to nobody — "and
    /// nobody, including whoever signs in on this phone next, can delete it". Provenance is on every
    /// row that door touches, so it comes off in the same statement.
    @Test("the leaving door takes the provenance off with the name")
    func theLeavingDoorClearsProvenance() async throws {
        let store = try await CypressStore.inMemory()
        let api = Self.api(store, userID: Self.userID)
        let (treeID, photoID, file) = try await Self.treeWithAPhotograph(api)

        _ = try await api.deleteAccount(.leaveRecords)

        #expect(try await Self.provenance(of: photoID, in: store) == nil, "the door left the phone's claim on it")
        #expect(
            try await Self.deletableIDs(treeID: treeID, in: store, for: api).isEmpty,
            "an anonymized photograph offered a delete control"
        )
        await #expect(throws: APIError.forbidden) { _ = try await api.deletePhoto(id: photoID) }
        #expect(FileManager.default.fileExists(atPath: file.path), "the refusal removed the bytes anyway")

        // The screen's own sentence still applies to it (task #131), which is the difference between
        // this state and the one the report was about.
        #expect(try await api.treeProfile(id: treeID).anonymizedPhotoIDs.contains(photoID))
    }

    /// **Both refusals, asserted separately, because each is the other's belt.** The leaving door
    /// clears provenance, so this row should not exist; the Swift rule refuses `.nobody` before it
    /// reads provenance and the statement leads with the same clause, so a row that does exist —
    /// written by an older tombstone, or by a future writer that forgets — is refused twice.
    /// Removing either half turns one of these two expectations red on its own.
    @Test("an ownerless photograph is refused even when the row still claims this installation")
    func anOwnerlessRowIsRefusedWhateverTheProvenanceSays() async throws {
        let who = Attribution(userID: nil, deviceID: Self.deviceID)
        #expect(
            !PhotoOwner.nobody.permitsRemoval(by: who, takenOnDevice: Self.deviceID),
            "the rule read provenance on a row that belongs to nobody"
        )

        let store = try await CypressStore.inMemory()
        let api = Self.api(store)
        let (treeID, _, _) = try await Self.treeWithAPhotograph(api)
        let orphan = Photo(
            treeID: treeID, shotType: .leaf,
            capturedAt: Self.moment, createdAt: Self.moment, updatedAt: Self.moment
        )
        try await store.queue.write { connection in
            try ContributionStore().insert(
                orphan, localPath: nil, owner: .nobody,
                takenOnDevice: Self.deviceID, connection: connection
            )
        }
        #expect(
            !(try await Self.deletableIDs(treeID: treeID, in: store, for: api).contains(orphan.id)),
            "the statement offered a control on a photograph that belongs to nobody"
        )
    }

    /// Provenance is not a third way to own a photograph. A row that says both that somebody else
    /// took it and that somebody else owns it is refused, which is the property that has to hold on
    /// the day anything syncs a photograph down.
    @Test("a photograph taken on another installation is not this one's to remove")
    func aStrangersPhotographIsStillRefused() async throws {
        let store = try await CypressStore.inMemory()
        let api = Self.api(store)
        let (treeID, mine, _) = try await Self.treeWithAPhotograph(api)

        let theirs = Photo(
            treeID: treeID, shotType: .trunk,
            capturedAt: Self.moment, createdAt: Self.moment, updatedAt: Self.moment
        )
        try await store.queue.write { connection in
            try ContributionStore().insert(
                theirs, localPath: nil, owner: .user(Self.strangerID),
                takenOnDevice: Self.otherDeviceID, connection: connection
            )
        }

        let deletable = try await Self.deletableIDs(treeID: treeID, in: store, for: api)
        #expect(deletable.contains(mine))
        #expect(!deletable.contains(theirs.id), "a stranger's photograph offered a delete control")
        await #expect(throws: APIError.forbidden) { _ = try await api.deletePhoto(id: theirs.id) }
    }

    /// The write path records it, on the device rather than on the owner — the case where the two
    /// disagree is the whole reason the column exists.
    @Test("a photograph taken while signed in still records the phone that took it")
    func theWritePathRecordsTheInstallation() async throws {
        let store = try await CypressStore.inMemory()
        let api = Self.api(store, userID: Self.userID)
        let (_, photoID, _) = try await Self.treeWithAPhotograph(api)

        let subject = try await store.queue.read { connection in
            try ContributionStore().photoForDeletion(id: photoID, connection: connection)
        }
        #expect(try #require(subject).owner == .user(Self.userID))
        #expect(try #require(subject).takenOnDevice == Self.deviceID)
    }
}
