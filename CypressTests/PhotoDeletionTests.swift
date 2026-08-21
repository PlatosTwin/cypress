import Foundation
import Testing
@testable import Cypress

/// Deleting one photograph you took — task #78, ERRATA **E147**.
///
/// **The assertion that matters is on the disk.** A deletion test that only checked the call
/// returned without throwing would pass against a delete that deletes nothing, and a deletion test
/// that only checked the row would pass against one that leaves the JPEG in the container — which is
/// precisely the failure E136 refused to ship for account deletion. So every path here asserts the
/// bytes as well as the rows.
///
/// The sentences this suite has to make true:
///
/// 1. **the bytes go and the row stops being readable** — under both storage shapes, the staged one
///    and the uploaded one;
/// 2. **only your own** — a stranger's photograph and an anonymized one are both refused, and the
///    refusal is a thrown error rather than a silent no-op;
/// 3. **the hero is left in a defined state** — deleting the photograph a tree leads with promotes
///    the next by the same rule, and deleting the last one returns the tree to its cold profile;
/// 4. **votes do not outlive the photograph they judged**, whoever cast them;
/// 5. **the last photograph of a community-added tree is deletable, and says so** — BUILD-PLAN §6's
///    "requires photo" is a rule about making a record, not a cage around it;
/// 6. **a queued upload cannot resurrect it**;
/// 7. **it works through `any CypressAPI`** — E125's witness-table trap, which a test holding a
///    `LocalAPI` cannot see.
@Suite("Photo deletion")
struct PhotoDeletionTests {

    private static let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-00000000B001")!
    private static let userID = UUID(uuidString: "0E000000-0000-4000-8000-00000000B002")!
    private static let strangerID = UUID(uuidString: "0E000000-0000-4000-8000-00000000B003")!
    /// The installation a stranger's photograph would have come from (`AppSchema` v16). Not this
    /// one, which is the whole of what makes such a row a stranger's.
    private static let strangersDeviceID = UUID(uuidString: "D0000000-0000-4000-8000-00000000B004")!
    private static let moment = Date(timeIntervalSince1970: 1_800_000_000)

    private static func photoDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cypress-photo-delete-\(UUID().uuidString)", isDirectory: true)
    }

    private static func signedIn(
        userID: UUID? = PhotoDeletionTests.userID
    ) async throws -> (store: CypressStore, api: LocalAPI, photos: URL) {
        let store = try await CypressStore.inMemory()
        let directory = photoDirectory()
        return (
            store,
            LocalAPI(
                store: store, deviceID: deviceID, userID: userID,
                photoDirectory: directory, now: { moment }
            ),
            directory
        )
    }

    /// A community tree with one photograph whose bytes are really on the disk, staged where
    /// `addTree` leaves them (`local_path`, never uploaded).
    private static func treeWithAStagedPhotograph(
        _ api: LocalAPI,
        at longitude: Double = -122.44
    ) async throws -> (tree: Tree, photoID: UUID, file: URL, store: CypressStore) {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("cypress-staged-\(UUID().uuidString).jpg")
        try Data("a photograph of a tree".utf8).write(to: file, options: .atomic)
        let tree = try await api.addTree(
            TreeDraft(
                coordinate: Coordinate(latitude: 37.77, longitude: longitude),
                photoLocalPath: file.path,
                attribution: Attribution(userID: nil, deviceID: deviceID)
            )
        )
        let profile = try await api.treeProfile(id: tree.id)
        let photo = try #require(profile.photos.items.first, "the add wrote no photograph")
        return (tree, photo.id, file, try await CypressStore.inMemory())
    }

    private static func rowCount(_ sql: String, in store: CypressStore) async throws -> Int {
        try await store.queue.read { connection -> Int in
            let statement = try connection.prepare(sql)
            defer { statement.finalize() }
            return try statement.fetchOne { try $0.int("n") } ?? -1
        }
    }

    // MARK: - The bytes

    /// The whole feature in one test, and the only assertion in it that could not have been faked:
    /// **the file is gone from the disk**.
    @Test("deleting a photograph removes the row, the reads and the bytes")
    func deletingAPhotographRemovesEverything() async throws {
        let (store, api, _) = try await Self.signedIn()
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("cypress-staged-\(UUID().uuidString).jpg")
        try Data("a photograph of a tree".utf8).write(to: file, options: .atomic)
        let tree = try await api.addTree(
            TreeDraft(
                coordinate: Coordinate(latitude: 37.77, longitude: -122.44),
                photoLocalPath: file.path,
                attribution: Attribution(userID: nil, deviceID: Self.deviceID)
            )
        )
        let photo = try #require(try await api.treeProfile(id: tree.id).photos.items.first).id
        #expect(FileManager.default.fileExists(atPath: file.path), "fixture: no bytes on disk")

        let outcome = try await api.deletePhoto(id: photo)

        #expect(outcome.photoID == photo)
        #expect(outcome.treeID == tree.id)
        #expect(outcome.removedFiles == 1, "the call succeeded and removed no file")

        // The disk.
        #expect(
            !FileManager.default.fileExists(atPath: file.path),
            "the row went and the JPEG stayed — the failure the whole ordering exists to prevent"
        )
        // The reads, all of them.
        #expect(try await api.treeProfile(id: tree.id).photos.items.isEmpty)
        await #expect(throws: APIError.self) { try await api.photoData(id: photo) }
        // The row survives as a tombstone — `private_reminders.photo_id` references it, and the
        // tree's record keeps saying a photograph was here — stripped of everything that could find
        // a picture again.
        #expect(try await Self.rowCount(
            "SELECT COUNT(*) AS n FROM photos WHERE id = '\(photo.uuidString)'", in: store
        ) == 1, "the row was hard-deleted, taking any reminder that referenced it")
        #expect(try await Self.rowCount(
            """
            SELECT COUNT(*) AS n FROM photos
             WHERE id = '\(photo.uuidString)' AND deleted_at IS NOT NULL
               AND storage_key IS NULL AND local_path IS NULL
               AND width IS NULL AND height IS NULL
               AND public_lat IS NULL AND public_lon IS NULL
            """,
            in: store
        ) == 1, "the tombstone still knows where the picture was")
    }

    /// The other shape a photograph's bytes take: uploaded, so `storage_key` names a file inside the
    /// app's own photo directory and `local_path` is NULL. A delete that only knew about staged
    /// files would leave every settled photograph on the disk.
    @Test("deleting an uploaded photograph removes the file from the photo directory")
    func deletingAnUploadedPhotographRemovesTheStoredFile() async throws {
        let (_, api, directory) = try await Self.signedIn()
        let staged = FileManager.default.temporaryDirectory
            .appendingPathComponent("cypress-staged-\(UUID().uuidString).jpg")
        try Data("a photograph of a tree".utf8).write(to: staged, options: .atomic)
        let tree = try await api.addTree(
            TreeDraft(
                coordinate: Coordinate(latitude: 37.77, longitude: -122.44),
                photoLocalPath: staged.path,
                attribution: Attribution(userID: nil, deviceID: Self.deviceID)
            )
        )

        // A second photograph, taken through the upload path so its bytes settle in the container.
        let second = FileManager.default.temporaryDirectory
            .appendingPathComponent("cypress-staged-\(UUID().uuidString).jpg")
        try Data("the trunk, close up".utf8).write(to: second, options: .atomic)
        let ticket = try await api.beginPhotoUpload(
            PhotoUploadRequest(
                treeID: tree.id, shotType: .trunk, localPath: second.path, capturedAt: Self.moment
            )
        )
        try await api.uploadPhoto(at: second.path, ticket: ticket)
        let stored = directory.appendingPathComponent("\(ticket.photoID.uuidString).jpg")
        #expect(FileManager.default.fileExists(atPath: stored.path), "fixture: the upload stored nothing")

        let outcome = try await api.deletePhoto(id: ticket.photoID)
        #expect(outcome.removedFiles == 1)
        #expect(
            !FileManager.default.fileExists(atPath: stored.path),
            "an uploaded photograph's bytes stayed in the container"
        )
        // …and the tree's other photograph is untouched, which a predicate that widened by one
        // clause would have taken with it.
        #expect(try await api.treeProfile(id: tree.id).photos.items.count == 1)
        #expect(FileManager.default.fileExists(atPath: staged.path))
    }

    // MARK: - Only your own

    @Test("a photograph that is not yours cannot be deleted")
    func astrangersPhotographIsRefused() async throws {
        let (store, api, _) = try await Self.signedIn()
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("cypress-staged-\(UUID().uuidString).jpg")
        try Data("somebody else's photograph".utf8).write(to: file, options: .atomic)
        let tree = try await api.addTree(
            TreeDraft(
                coordinate: Coordinate(latitude: 37.77, longitude: -122.44),
                photoLocalPath: file.path,
                attribution: Attribution(userID: nil, deviceID: Self.deviceID)
            )
        )
        let photo = try #require(try await api.treeProfile(id: tree.id).photos.items.first).id
        // **`taken_on_device` moves with the owner, and it has to** (`AppSchema` v16). This fixture
        // makes a stranger's photograph by writing one here and then rewriting the owner, and since
        // v16 that is no longer enough: the row would still say this installation took it, which is
        // true — and is exactly the case the v16 gate admits, a photograph this phone wrote that an
        // account has since adopted. A photograph that is genuinely somebody else's arrived from
        // somebody else's installation, so the fixture says that too. Without this line the test
        // asserts the opposite of its own name.
        try await store.queue.write { connection in
            try connection.execute("""
                UPDATE photos SET user_id = '\(Self.strangerID.uuidString)', device_id = NULL,
                                  taken_on_device = '\(Self.strangersDeviceID.uuidString)'
                 WHERE id = '\(photo.uuidString)'
                """)
        }

        await #expect(throws: APIError.forbidden) { _ = try await api.deletePhoto(id: photo) }
        #expect(FileManager.default.fileExists(atPath: file.path), "a refused delete removed the bytes")
        #expect(try await api.treeProfile(id: tree.id).photos.items.count == 1)
    }

    /// A photograph whose contributor deleted their account through the door that leaves the work in
    /// place. It belongs to nobody, and nobody includes whoever is holding the phone now.
    ///
    /// **The fixture nulls the owners and deliberately leaves `taken_on_device` set** — a row shape
    /// neither shipping path produces any more, since both `AccountDeletion.anonymizeContributions`
    /// and `LocalAPI.debugAnonymizePhoto` clear provenance in the same statement that clears the
    /// name. That is not an oversight to be tidied away: it is the only place in the suite where the
    /// *shipping delete path* meets a row that belongs to nobody and still claims this installation,
    /// which is exactly the row `PhotoOwner.permitsRemoval` refuses on its first line before it ever
    /// reads provenance (`AppSchema` v16). Correcting the fixture to match the leaving door would
    /// delete that coverage silently, so the assertion below states the constraint instead.
    @Test("an anonymized photograph cannot be deleted by the next person on this phone")
    func anAnonymizedPhotographIsRefused() async throws {
        let (store, api, _) = try await Self.signedIn()
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("cypress-staged-\(UUID().uuidString).jpg")
        try Data("a photograph left behind".utf8).write(to: file, options: .atomic)
        let tree = try await api.addTree(
            TreeDraft(
                coordinate: Coordinate(latitude: 37.77, longitude: -122.44),
                photoLocalPath: file.path,
                attribution: Attribution(userID: nil, deviceID: Self.deviceID)
            )
        )
        let photo = try #require(try await api.treeProfile(id: tree.id).photos.items.first).id
        try await store.queue.write { connection in
            try connection.execute("""
                UPDATE photos SET user_id = NULL, device_id = NULL WHERE id = '\(photo.uuidString)'
                """)
        }
        // The row is ownerless *and* still says this phone took it — see the header. If this ever
        // fails, the fixture has been aligned with the leaving door and the `.nobody`-first
        // ordering has lost its only shipping-path test.
        let provenance = try await store.queue.read { connection in
            try ContributionStore().photoForDeletion(id: photo, connection: connection)?.takenOnDevice
        }
        #expect(provenance == Self.deviceID, "the fixture no longer claims this installation")

        await #expect(throws: APIError.forbidden) { _ = try await api.deletePhoto(id: photo) }
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test("deleting a photograph that is not there is not found")
    func aMissingPhotographIsNotFound() async throws {
        let (_, api, _) = try await Self.signedIn()
        await #expect(throws: APIError.notFound) { _ = try await api.deletePhoto(id: UUID()) }
    }

    // MARK: - The hero

    /// Photo hero voting (task #47) picks the hero by rule rather than storing an id, so a deleted
    /// hero cannot dangle — but "cannot dangle" is a claim about the rule, and the rule is fed by
    /// `photos` and `photoTallies`, both of which this change touches.
    @Test("deleting the hero promotes the next photograph by the same rule")
    func deletingTheHeroPromotesTheNext() async throws {
        let (store, api, _) = try await Self.signedIn()
        let first = FileManager.default.temporaryDirectory
            .appendingPathComponent("cypress-staged-\(UUID().uuidString).jpg")
        try Data("the first".utf8).write(to: first, options: .atomic)
        let tree = try await api.addTree(
            TreeDraft(
                coordinate: Coordinate(latitude: 37.77, longitude: -122.44),
                photoLocalPath: first.path,
                attribution: Attribution(userID: nil, deviceID: Self.deviceID)
            )
        )
        let older = try #require(try await api.treeProfile(id: tree.id).photos.items.first).id

        let second = FileManager.default.temporaryDirectory
            .appendingPathComponent("cypress-staged-\(UUID().uuidString).jpg")
        try Data("the second".utf8).write(to: second, options: .atomic)
        let ticket = try await api.beginPhotoUpload(
            PhotoUploadRequest(
                treeID: tree.id, shotType: .fullTree, localPath: second.path,
                capturedAt: Self.moment.addingTimeInterval(3_600)
            )
        )
        // A thumb up makes it the hero outright — A3's "manual pin overrides".
        try await api.setPhotoVote(photoID: ticket.photoID, vote: .up)

        func hero() async throws -> UUID? {
            let profile = try await api.treeProfile(id: tree.id)
            return PhotoHero.choose(from: profile.photos.items, tallies: profile.photoTallies)?.id
        }
        #expect(try await hero() == ticket.photoID, "fixture: the up-voted photograph is not the hero")

        _ = try await api.deletePhoto(id: ticket.photoID)

        #expect(try await hero() == older, "deleting the hero did not promote the surviving photograph")
        // The vote went with it, so the tombstone cannot win an election it is not in.
        #expect(try await Self.rowCount("SELECT COUNT(*) AS n FROM photo_votes", in: store) == 0)

        // And deleting the last one leaves the tree in the state it had before anybody photographed
        // it: no hero, no photographs, and the profile still readable.
        _ = try await api.deletePhoto(id: older)
        #expect(try await hero() == nil)
        #expect(try await api.treeProfile(id: tree.id).photos.items.isEmpty)
    }

    /// Everybody's votes, not only the deleter's: they were judgments about a thing that no longer
    /// exists, which is `AccountDeletion`'s argument for the same deletion under the erasing door.
    @Test("every vote on a deleted photograph goes, including a stranger's")
    func votesDoNotOutliveThePhotograph() async throws {
        let (store, api, _) = try await Self.signedIn()
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("cypress-staged-\(UUID().uuidString).jpg")
        try Data("a photograph".utf8).write(to: file, options: .atomic)
        let tree = try await api.addTree(
            TreeDraft(
                coordinate: Coordinate(latitude: 37.77, longitude: -122.44),
                photoLocalPath: file.path,
                attribution: Attribution(userID: nil, deviceID: Self.deviceID)
            )
        )
        let photo = try #require(try await api.treeProfile(id: tree.id).photos.items.first).id

        try await api.setPhotoVote(photoID: photo, vote: .up)
        try await store.queue.write { connection in
            try ContributionStore().setPhotoVote(
                photoID: photo, owner: .user(Self.strangerID), vote: .down,
                at: Self.moment, connection: connection
            )
            // And one whose owner is already gone — the state `AppSchema` v9 exists to allow. A
            // delete keyed on an owner arm would strand it.
            try connection.execute("""
                INSERT INTO photo_votes (id, photo_id, tree_uuid, vote, created_at, updated_at)
                VALUES ('\(UUID().uuidString)','\(photo.uuidString)','\(tree.id.uuidString)',1,
                        '\(SQLiteTimestamp.string(from: Self.moment))',
                        '\(SQLiteTimestamp.string(from: Self.moment))')
                """)
        }
        #expect(try await Self.rowCount("SELECT COUNT(*) AS n FROM photo_votes", in: store) == 3)

        let outcome = try await api.deletePhoto(id: photo)
        #expect(outcome.deletedVotes == 3)
        #expect(try await Self.rowCount("SELECT COUNT(*) AS n FROM photo_votes", in: store) == 0)
    }

    // MARK: - The last photograph of a community add

    /// BUILD-PLAN §6: "Community add: requires photo". Deleting the only photograph of a tree that
    /// exists because of it is a real conflict, settled in favor of the person: allowed, named in
    /// the copy before the tap, and reported by the call.
    @Test("the last photograph of an added tree can be deleted, and the tree stays")
    func theLastPhotographOfACommunityAddIsDeletable() async throws {
        let (_, api, _) = try await Self.signedIn()
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("cypress-staged-\(UUID().uuidString).jpg")
        try Data("the evidence".utf8).write(to: file, options: .atomic)
        let tree = try await api.addTree(
            TreeDraft(
                coordinate: Coordinate(latitude: 37.77, longitude: -122.44),
                photoLocalPath: file.path,
                attribution: Attribution(userID: nil, deviceID: Self.deviceID)
            )
        )
        let photo = try #require(try await api.treeProfile(id: tree.id).photos.items.first).id

        let outcome = try await api.deletePhoto(id: photo)

        #expect(
            outcome.leftACommunityTreeWithoutAPhotograph,
            "the one case the confirmation has extra words for was not reported"
        )
        #expect(!FileManager.default.fileExists(atPath: file.path))
        // The tree stays on the map, and stays exactly as unverified as it was. Deleting it would
        // remove a real tree other people may have visited; "everything I contributed" has never
        // meant the forest.
        let profile = try await api.treeProfile(id: tree.id)
        #expect(profile.tree.id == tree.id)
        #expect(profile.tree.verificationState == .unverified)
        #expect(profile.photos.items.isEmpty)
    }

    /// The same call on a tree with two photographs must not claim it. The flag is the trigger for a
    /// sentence shown to a person, so a flag that was always true would be copy nobody could trust.
    @Test("deleting one of several photographs does not claim it was the last")
    func deletingOneOfSeveralIsNotTheLast() async throws {
        let (_, api, _) = try await Self.signedIn()
        let first = FileManager.default.temporaryDirectory
            .appendingPathComponent("cypress-staged-\(UUID().uuidString).jpg")
        try Data("one".utf8).write(to: first, options: .atomic)
        let tree = try await api.addTree(
            TreeDraft(
                coordinate: Coordinate(latitude: 37.77, longitude: -122.44),
                photoLocalPath: first.path,
                attribution: Attribution(userID: nil, deviceID: Self.deviceID)
            )
        )
        let second = FileManager.default.temporaryDirectory
            .appendingPathComponent("cypress-staged-\(UUID().uuidString).jpg")
        try Data("two".utf8).write(to: second, options: .atomic)
        let ticket = try await api.beginPhotoUpload(
            PhotoUploadRequest(
                treeID: tree.id, shotType: .trunk, localPath: second.path, capturedAt: Self.moment
            )
        )

        let outcome = try await api.deletePhoto(id: ticket.photoID)
        #expect(!outcome.leftACommunityTreeWithoutAPhotograph)
    }

    // MARK: - The queue

    /// A photograph deleted between the shutter and the drain. Remove the file and the row and leave
    /// the queue alone, and the next drain finds a staged path and retries a photograph that was
    /// supposed to be gone — on a real backend, one it may already have uploaded.
    @Test("a queued upload stops carrying a photograph that has been deleted")
    func aQueuedUploadIsDisarmed() async throws {
        let (store, api, _) = try await Self.signedIn()
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("cypress-staged-\(UUID().uuidString).jpg")
        try Data("a photograph mid-flight".utf8).write(to: file, options: .atomic)
        let tree = try await api.addTree(
            TreeDraft(
                coordinate: Coordinate(latitude: 37.77, longitude: -122.44),
                photoLocalPath: file.path,
                attribution: Attribution(userID: nil, deviceID: Self.deviceID)
            )
        )
        let photo = try #require(try await api.treeProfile(id: tree.id).photos.items.first).id

        // The visit this photograph would have ridden to the server on, still queued.
        let visit = Visit(
            treeID: tree.id,
            attribution: Attribution(userID: Self.userID, deviceID: Self.deviceID),
            capturedAt: Self.moment
        )
        try await store.queue.write { connection in
            let item = try OutboxPayload.visit(visit).makeItem(
                photos: [OutboxPhoto(path: file.path, shotType: .fullTree)]
            )
            try OutboxStore().enqueue(item, connection: connection)
        }
        #expect(try await Self.rowCount(
            "SELECT COUNT(*) AS n FROM outbox WHERE json_array_length(photo_paths) = 1", in: store
        ) == 1, "fixture: nothing queued")

        let outcome = try await api.deletePhoto(id: photo)

        #expect(outcome.dequeuedBinaries == 1, "the queue kept a path to a deleted photograph")
        #expect(try await Self.rowCount(
            "SELECT COUNT(*) AS n FROM outbox WHERE kind = 'visit' AND json_array_length(photo_paths) = 0",
            in: store
        ) == 1)
        // The visit itself is still queued: the person deleted a picture, not the record of having
        // stood in front of the tree. Narrowed to the visit because the deletion queues a
        // `photo_withdrawal` of its own now, and the tree an `add_tree` — both are real rows and
        // neither is what this test is asking about.
        #expect(try await Self.rowCount("SELECT COUNT(*) AS n FROM outbox WHERE kind = 'visit'", in: store) == 1)
    }

    // MARK: - The boundary

    /// **ERRATA E125's trap, checked rather than trusted.** An extension-only member has no
    /// witness-table entry and dispatches statically, so `LocalAPI`'s implementation would be
    /// unreachable the moment the value is erased — which it is on every screen in the app. Every
    /// other test in this file holds a `LocalAPI` and would pass against exactly that bug.
    @Test("deletePhoto reaches the implementation through any CypressAPI")
    func theProtocolDispatchesDynamically() async throws {
        let (_, concrete, _) = try await Self.signedIn()
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("cypress-staged-\(UUID().uuidString).jpg")
        try Data("erased to the protocol".utf8).write(to: file, options: .atomic)
        let tree = try await concrete.addTree(
            TreeDraft(
                coordinate: Coordinate(latitude: 37.77, longitude: -122.44),
                photoLocalPath: file.path,
                attribution: Attribution(userID: nil, deviceID: Self.deviceID)
            )
        )
        let photo = try #require(try await concrete.treeProfile(id: tree.id).photos.items.first).id

        let erased: any CypressAPI = concrete
        let outcome = try await erased.deletePhoto(id: photo)

        #expect(outcome.removedFiles == 1, "the extension's default answered instead of LocalAPI")
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    // MARK: - The tombstone and the erasing door

    /// A tombstone is still the person's row. "Erase everything I contributed" reaches the sentence
    /// "a photograph was here and was withdrawn" as well as the photographs themselves.
    @Test("erasing an account takes the tombstones of photographs it already deleted")
    func theErasingDoorTakesTombstonesToo() async throws {
        let (store, api, _) = try await Self.signedIn()
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("cypress-staged-\(UUID().uuidString).jpg")
        try Data("deleted, then erased".utf8).write(to: file, options: .atomic)
        let tree = try await api.addTree(
            TreeDraft(
                coordinate: Coordinate(latitude: 37.77, longitude: -122.44),
                photoLocalPath: file.path,
                attribution: Attribution(userID: nil, deviceID: Self.deviceID)
            )
        )
        let photo = try #require(try await api.treeProfile(id: tree.id).photos.items.first).id
        _ = try await api.deletePhoto(id: photo)
        #expect(try await Self.rowCount("SELECT COUNT(*) AS n FROM photos", in: store) == 1)

        try await api.deleteAccount(.eraseEverything)
        #expect(try await Self.rowCount("SELECT COUNT(*) AS n FROM photos", in: store) == 0)
    }
}
