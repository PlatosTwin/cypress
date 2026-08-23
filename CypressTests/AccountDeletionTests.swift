import Foundation
import Testing
@testable import Cypress

/// Account deletion, in the two-part sense RULINGS **R3** settles: contributions are anonymized and
/// the rows only that account could ever read are deleted (ERRATA E23 and E89 each left this OPEN,
/// and E109 records how it closed).
///
/// The sentences this suite has to make true, each of them a thing that was either impossible before
/// the change or is easy to get quietly wrong:
///
/// 1. **a contribution survives with its owner nulled** — every one of the four kinds, plus the two
///    nullable attributions (`tree_names.given_by`, `review_flags.raised_by`), and the tree keeps it;
/// 2. **a private reminder and a favorite do not survive** — including a favorite *tombstone*,
///    which the v5 trigger would have refused to delete and which is exactly as unreadable as a live
///    row once its owner is gone;
/// 3. **somebody else's rows are untouched** — the device's own, and a stranger account's;
/// 4. **the two halves are one transaction** — a failure after the anonymization has already run
///    leaves the database exactly as it was, because a half-deleted person cannot tell and cannot
///    retry;
/// 5. **the queue cannot resurrect what was deleted** — a favorite toggle queued before the
///    deletion does not re-create the favorite when it drains afterwards, and a queued visit lands
///    anonymous rather than re-attributed;
/// 6. **the hole in the tombstone trigger is one account wide and closes behind itself.**
@Suite("Account deletion")
struct AccountDeletionTests {

    // MARK: - Fixtures

    private static let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-0000000000C1")!
    private static let userID = UUID(uuidString: "0E000000-0000-4000-8000-0000000000C2")!
    private static let strangerID = UUID(uuidString: "0E000000-0000-4000-8000-0000000000C3")!
    private static let moment = Date(timeIntervalSince1970: 1_800_000_000)

    /// A store and a signed-in `LocalAPI` over it.
    private static func signedIn() async throws -> (store: CypressStore, api: LocalAPI) {
        let store = try await CypressStore.inMemory()
        return (store, LocalAPI(store: store, deviceID: deviceID, userID: userID, now: { moment }))
    }

    /// A tree to hang contributions on. There is no seed in these tests, so it is a community add —
    /// which `LocalAPI.requireTree` accepts and an invented UUID does not.
    private static func makeTree(
        api: LocalAPI,
        in store: CypressStore,
        at longitude: Double = -122.44
    ) async throws -> Tree {
        let tree = try await api.addTree(
            TreeDraft(
                coordinate: Coordinate(latitude: 37.77, longitude: longitude),
                photoLocalPath: "/tmp/cypress-deletion-test.jpg",
                attribution: Attribution.anonymous(deviceID: deviceID)
            )
        )
        // `addTree` is one of spec §3.4's nine and now queues an `add_tree` row of its own,
        // in the transaction that adds the tree. This suite is not about that row, and every
        // queue count below would otherwise be counting the fixture. See
        // `OutboxTestSupport.discardFixtureRows`.
        try await OutboxTestSupport.discardFixtureRows(in: store)
        return tree
    }

    private static func scalar(_ sql: String, in store: CypressStore) async throws -> Int {
        try await store.queue.read { connection -> Int in
            let statement = try connection.prepare(sql)
            defer { statement.finalize() }
            return try statement.fetchOne { try $0.int("n") } ?? -1
        }
    }

    /// Rows of one contribution table that still name a user.
    private static func attributed(_ table: String, to user: UUID, in store: CypressStore) async throws -> Int {
        try await scalar(
            "SELECT COUNT(*) AS n FROM \(table) WHERE user_id = '\(user.uuidString)'",
            in: store
        )
    }

    /// One of each of the four append-only contribution kinds, all attributed to `attribution`.
    @discardableResult
    private static func writeContributions(
        treeID: UUID,
        attribution: Attribution,
        in store: CypressStore
    ) async throws -> Visit {
        let visit = Visit(treeID: treeID, attribution: attribution, note: "leafing out", capturedAt: moment)
        try await store.queue.write { connection in
            let contributions = ContributionStore()
            try contributions.insert(visit, connection: connection)
            try contributions.insert(
                TreeObservation(treeID: treeID, attribution: attribution, capturedAt: moment, vitality: .good),
                connection: connection
            )
            try contributions.insert(
                TreeMeasurement.dbh(
                    treeID: treeID,
                    attribution: attribution,
                    capturedAt: moment,
                    quantity: Quantity(value: 31, unit: .centimeters, method: .tape)
                ),
                connection: connection
            )
            try contributions.insert(
                CareEvent(treeID: treeID, attribution: attribution, capturedAt: moment, actions: [.watered]),
                connection: connection
            )
        }
        return visit
    }

    // MARK: - 1. What the forest keeps

    @Test("a contribution survives deletion with its owner nulled")
    func contributionsSurviveAnonymized() async throws {
        let (store, api) = try await Self.signedIn()
        let tree = try await Self.makeTree(api: api, in: store)
        let attribution = Attribution(userID: Self.userID, deviceID: Self.deviceID)
        let visit = try await Self.writeContributions(treeID: tree.id, attribution: attribution, in: store)

        // The two nullable attributions on the public-record tables. `given_by` is nullable exactly
        // so a tree's name can outlive its namer (D15).
        try await store.queue.write { connection in
            try ContributionStore().insert(
                TreeName(treeID: tree.id, name: "Grandmother Cypress", givenBy: Self.userID),
                connection: connection
            )
            try ContributionStore().insert(
                ReviewFlag(treeID: tree.id, kind: .appearsDead, raisedBy: Self.userID, createdAt: Self.moment, updatedAt: Self.moment),
                connection: connection
            )
        }

        for table in ["visits", "observations", "measurements", "care_events"] {
            #expect(try await Self.attributed(table, to: Self.userID, in: store) == 1, "fixture: \(table)")
        }

        let outcome = try await api.deleteAccount(.leaveRecords)
        #expect(outcome.anonymizedContributions == 4)
        #expect(outcome.anonymizedAttributions == 2)

        // Still there, and still on the tree — this is the half §3.12 has always required.
        for table in ["visits", "observations", "measurements", "care_events"] {
            #expect(try await Self.attributed(table, to: Self.userID, in: store) == 0, "\(table) still names the account")
            let total = try await Self.scalar("SELECT COUNT(*) AS n FROM \(table)", in: store)
            #expect(total == 1, "\(table) lost its row instead of losing its owner")
        }
        #expect(try await Self.scalar(
            "SELECT COUNT(*) AS n FROM tree_names WHERE given_by IS NULL", in: store
        ) == 1)
        #expect(try await Self.scalar(
            "SELECT COUNT(*) AS n FROM review_flags WHERE raised_by IS NULL", in: store
        ) == 1)

        // The device id is left alone. It is D9's anonymous installation handle, which these rows
        // carried before there was an account and would carry if there had never been one; the
        // "device link" §3.12 severs is the `device` row, asserted below.
        let profile = try await api.treeProfile(id: tree.id)
        #expect(profile.visits.items.map(\.id) == [visit.id])
        #expect(profile.visits.items.first?.userID == nil)
        #expect(profile.visits.items.first?.deviceID == Self.deviceID)
        #expect(profile.visits.items.first?.note == "leafing out")
    }

    @Test("the device link is severed and the signed-in state goes with it")
    func theDeviceLinkIsSevered() async throws {
        let (store, api) = try await Self.signedIn()
        try await api.claimDevice(deviceUUID: Self.deviceID, userID: Self.userID)
        #expect(try await store.appState(.currentUserID) == Self.userID.uuidString)

        try await api.deleteAccount(.leaveRecords)

        let claimed = try await store.queue.read { connection in
            try ContributionStore().claimedUser(forDevice: Self.deviceID, connection: connection)
        }
        #expect(claimed == nil, "the device is still linked to the deleted account")
        #expect(try await store.appState(.currentUserID) == nil)
        #expect(await api.userID == nil)

        // And a second deletion is refused rather than silently succeeding, because there is no
        // longer an account to delete.
        await #expect(throws: APIError.unauthorized) { try await api.deleteAccount(.leaveRecords) }
    }

    // MARK: - 2. What only one person could ever see

    @Test("a private reminder and a favorite do not survive their account")
    func exclusivelyOwnedRowsAreDeleted() async throws {
        let (store, api) = try await Self.signedIn()
        let tree = try await Self.makeTree(api: api, in: store)
        let other = try await Self.makeTree(api: api, in: store, at: -122.46)

        try await store.queue.write { connection in
            let contributions = ContributionStore()
            try contributions.insert(
                PrivateReminder(owner: .user(Self.userID), treeID: tree.id, category: .hangingOrBrokenLimb),
                connection: connection
            )
            try contributions.applyFavoriteToggle(
                owner: .user(Self.userID), treeID: tree.id, clientUUID: UUID(),
                isFavorite: true, at: Self.moment, connection: connection
            )
            // The device's own rows, written before there was an account and never moved onto it.
            // Deleting these would delete a stranger's records on the strength of a shared phone.
            try contributions.insert(
                PrivateReminder(owner: .device(Self.deviceID), treeID: other.id, category: .uprooted),
                connection: connection
            )
            try contributions.applyFavoriteToggle(
                owner: .device(Self.deviceID), treeID: other.id, clientUUID: UUID(),
                isFavorite: true, at: Self.moment, connection: connection
            )
            // And a second account's, which shares neither.
            try contributions.applyFavoriteToggle(
                owner: .user(Self.strangerID), treeID: tree.id, clientUUID: UUID(),
                isFavorite: true, at: Self.moment, connection: connection
            )
        }

        let outcome = try await api.deleteAccount(.leaveRecords)
        #expect(outcome.deletedPrivateReminders == 1)
        #expect(outcome.deletedFavorites == 1)

        // Gone — not tombstoned, not re-homed onto the device, not left ownerless.
        #expect(try await Self.scalar(
            "SELECT COUNT(*) AS n FROM private_reminders WHERE user_id = '\(Self.userID.uuidString)'", in: store
        ) == 0)
        #expect(try await Self.scalar(
            "SELECT COUNT(*) AS n FROM favorites WHERE user_id = '\(Self.userID.uuidString)'", in: store
        ) == 0)
        #expect(try await Self.scalar(
            "SELECT COUNT(*) AS n FROM favorites WHERE user_id IS NULL AND device_id IS NULL", in: store
        ) == 0)
        #expect(try await Self.scalar(
            "SELECT COUNT(*) AS n FROM favorites WHERE device_id = '\(Self.deviceID.uuidString)' AND tree_uuid = '\(tree.id.uuidString)'",
            in: store
        ) == 0, "the account's favorite was re-homed onto the device rather than deleted")

        // Everyone else's are exactly where they were.
        let deviceReminders = try await store.queue.read { connection in
            try ContributionStore().privateReminders(userID: nil, deviceID: Self.deviceID, connection: connection)
        }
        #expect(deviceReminders.count == 1)
        #expect(deviceReminders.first?.treeID == other.id)
        #expect(try await store.queue.read { connection in
            try ContributionStore().isFavorite(owner: .device(Self.deviceID), treeID: other.id, connection: connection)
        })
        #expect(try await store.queue.read { connection in
            try ContributionStore().isFavorite(owner: .user(Self.strangerID), treeID: tree.id, connection: connection)
        })
    }

    @Test("a favorite tombstone goes with the account too")
    func tombstonesAreDeleted() async throws {
        let (store, api) = try await Self.signedIn()
        let tree = try await Self.makeTree(api: api, in: store)

        // On, then off: one row whose `deleted_at` is set. E89 keeps this row rather than deleting
        // it so that sync can carry the un-favorite event — and there is no such sync for an
        // account that no longer exists.
        try await store.queue.write { connection in
            let contributions = ContributionStore()
            try contributions.applyFavoriteToggle(
                owner: .user(Self.userID), treeID: tree.id, clientUUID: UUID(),
                isFavorite: true, at: Self.moment, connection: connection
            )
            try contributions.applyFavoriteToggle(
                owner: .user(Self.userID), treeID: tree.id, clientUUID: UUID(),
                isFavorite: false, at: Self.moment.addingTimeInterval(60), connection: connection
            )
        }
        #expect(try await Self.scalar(
            "SELECT COUNT(*) AS n FROM favorites WHERE deleted_at IS NOT NULL", in: store
        ) == 1, "fixture: the un-favorite should have tombstoned rather than deleted")

        let outcome = try await api.deleteAccount(.leaveRecords)
        #expect(outcome.deletedFavorites == 1)
        #expect(outcome.deletedFavoriteTombstones == 1)
        #expect(try await Self.scalar("SELECT COUNT(*) AS n FROM favorites", in: store) == 0)
    }

    // MARK: - 3. One transaction

    @Test("a failure part-way through leaves nothing anonymized")
    func theDeletionIsOneTransaction() async throws {
        let (store, api) = try await Self.signedIn()
        let tree = try await Self.makeTree(api: api, in: store)
        let attribution = Attribution(userID: Self.userID, deviceID: Self.deviceID)
        try await Self.writeContributions(treeID: tree.id, attribution: attribution, in: store)
        try await store.queue.write { connection in
            let contributions = ContributionStore()
            try contributions.insert(
                PrivateReminder(owner: .user(Self.userID), treeID: tree.id, category: .uprooted),
                connection: connection
            )
            try contributions.applyFavoriteToggle(
                owner: .user(Self.userID), treeID: tree.id, clientUUID: UUID(),
                isFavorite: true, at: Self.moment, connection: connection
            )
        }

        // A real failure, injected from outside the deletion path rather than through a seam in it:
        // reminders are deleted *after* the contributions have been anonymized, so this aborts the
        // transaction at exactly the point where a non-atomic implementation would already have
        // committed half a deletion.
        try await store.queue.write { connection in
            try connection.execute("""
                CREATE TRIGGER deletion_atomicity_probe BEFORE DELETE ON private_reminders
                BEGIN SELECT RAISE(ABORT, 'probe'); END;
                """)
        }

        await #expect(throws: (any Error).self) { try await api.deleteAccount(.leaveRecords) }

        // Nothing moved. Not the contributions — a person who saw an error and tried again must not
        // find their work already anonymized and the deletion reporting success over rows that are
        // still there.
        for table in ["visits", "observations", "measurements", "care_events"] {
            #expect(try await Self.attributed(table, to: Self.userID, in: store) == 1, "\(table) was anonymized by a failed deletion")
        }
        #expect(try await Self.scalar(
            "SELECT COUNT(*) AS n FROM favorites WHERE user_id = '\(Self.userID.uuidString)'", in: store
        ) == 1)
        #expect(try await Self.scalar(
            "SELECT COUNT(*) AS n FROM private_reminders WHERE user_id = '\(Self.userID.uuidString)'", in: store
        ) == 1)
        // Including the trigger's permission slip, which a rollback has to take with it — otherwise
        // a failed deletion leaves a standing hole in the tombstone rule.
        #expect(try await Self.scalar(
            "SELECT COUNT(*) AS n FROM app_state WHERE key = '\(AccountDeletion.erasureSentinelKey)'", in: store
        ) == 0)

        // …and the account is still signed in, because nothing was deleted.
        #expect(await api.userID == Self.userID)

        // With the probe gone the same call succeeds, which is what "retryable" has to mean here.
        try await store.queue.write { connection in
            try connection.execute("DROP TRIGGER deletion_atomicity_probe")
        }
        let outcome = try await api.deleteAccount(.leaveRecords)
        #expect(outcome.anonymizedContributions == 4)
        #expect(outcome.deletedPrivateReminders == 1)
        #expect(outcome.deletedFavorites == 1)
    }

    // MARK: - 4. The queue

    @Test("queued reminders and favorites are discarded, queued contributions are anonymized")
    func theOutboxIsTakenWithTheAccount() async throws {
        let (store, api) = try await Self.signedIn()
        let tree = try await Self.makeTree(api: api, in: store)
        let attribution = Attribution(userID: Self.userID, deviceID: Self.deviceID)

        let queuedVisit = Visit(treeID: tree.id, attribution: attribution, capturedAt: Self.moment)
        let queuedToggle = FavoriteToggle(
            owner: .user(Self.userID), treeID: tree.id, isFavorite: true, occurredAt: Self.moment
        )
        let queuedReminder = PrivateReminder(
            owner: .user(Self.userID), treeID: tree.id, category: .struckByVehicle
        )
        // A device-owned toggle in the same queue, which must not be swept up with the account's.
        let deviceToggle = FavoriteToggle(
            owner: .device(Self.deviceID), treeID: tree.id, isFavorite: true, occurredAt: Self.moment
        )

        try await store.queue.write { connection in
            let outbox = OutboxStore()
            try outbox.enqueue(OutboxPayload.visit(queuedVisit).makeItem(), connection: connection)
            try outbox.enqueue(OutboxPayload.favoriteToggle(queuedToggle).makeItem(), connection: connection)
            try outbox.enqueue(OutboxPayload.privateReminder(queuedReminder).makeItem(), connection: connection)
            try outbox.enqueue(OutboxPayload.favoriteToggle(deviceToggle).makeItem(), connection: connection)
        }

        let outcome = try await api.deleteAccount(.leaveRecords)
        #expect(outcome.discardedOutboxItems == 2)
        #expect(outcome.anonymizedOutboxItems == 1)

        let records = try await store.queue.read { connection in
            try OutboxStore().allItems(connection: connection)
        }
        #expect(records.count == 2, "the account's exclusively-owned mutations are still queued")
        #expect(Set(records.map(\.item.kind)) == [.visit, .favoriteToggle])

        // The surviving visit carries no account any more: its payload is byte-identical to one
        // written before sign-in. Leaving it alone would re-attribute the row on drain, silently
        // undoing the anonymization for exactly the contributions that were in flight.
        let visitRecord = try #require(records.first { $0.item.kind == .visit })
        let payload = try OutboxPayload.decode(kind: .visit, from: visitRecord.item.payload)
        guard case let .visit(decoded) = payload else { throw APIError.validationFailed }
        #expect(decoded.userID == nil)
        #expect(decoded.deviceID == Self.deviceID)
        #expect(decoded.clientUUID == queuedVisit.clientUUID, "the idempotency key must not move")

        // Draining now must not resurrect the favorite the deletion removed.
        let results = try await api.sync(records.map(\.item))
        #expect(results.allSatisfy { $0.status != .failed })
        #expect(try await Self.attributed("visits", to: Self.userID, in: store) == 0)
        #expect(try await Self.scalar("SELECT COUNT(*) AS n FROM visits", in: store) == 1)
        #expect(try await Self.scalar(
            "SELECT COUNT(*) AS n FROM favorites WHERE user_id = '\(Self.userID.uuidString)'", in: store
        ) == 0, "a queued toggle re-created the deleted account's favorite")
        // The device's own toggle applied, exactly as it would have without a deletion.
        #expect(try await store.queue.read { connection in
            try ContributionStore().isFavorite(owner: .device(Self.deviceID), treeID: tree.id, connection: connection)
        })
    }

    // MARK: - 5. The hole in the trigger is one account wide

    @Test("with no erasure in progress a user-owned favorite still cannot be hard-deleted")
    func theTriggerStillRefusesEverythingElse() async throws {
        let (store, api) = try await Self.signedIn()
        let tree = try await Self.makeTree(api: api, in: store)
        try await store.queue.write { connection in
            try ContributionStore().applyFavoriteToggle(
                owner: .user(Self.userID), treeID: tree.id, clientUUID: UUID(),
                isFavorite: true, at: Self.moment, connection: connection
            )
        }

        // The `WHEN` clause has to be written with EXISTS rather than a comparison against the
        // sentinel's value: with no sentinel row the comparison is NULL, `NOT (0 OR NULL)` is NULL,
        // and a NULL `WHEN` does not fire — which would leave every user-owned favorite hard
        // deletable on every database where nobody is being deleted.
        await #expect(throws: (any Error).self) {
            try await store.queue.write { connection in
                try connection.execute("DELETE FROM favorites")
            }
        }
        #expect(try await Self.scalar("SELECT COUNT(*) AS n FROM favorites", in: store) == 1)

        // And after a real deletion the sentinel is gone, so the rule is back in force for everyone
        // else — asserted with a second account's row, since the first account's is now deleted.
        try await store.queue.write { connection in
            try ContributionStore().applyFavoriteToggle(
                owner: .user(Self.strangerID), treeID: tree.id, clientUUID: UUID(),
                isFavorite: true, at: Self.moment, connection: connection
            )
        }
        try await api.deleteAccount(.leaveRecords)
        #expect(try await Self.scalar(
            "SELECT COUNT(*) AS n FROM app_state WHERE key = '\(AccountDeletion.erasureSentinelKey)'", in: store
        ) == 0)
        await #expect(throws: (any Error).self) {
            try await store.queue.write { connection in
                try connection.execute("DELETE FROM favorites")
            }
        }
        #expect(try await Self.scalar("SELECT COUNT(*) AS n FROM favorites", in: store) == 1)
    }

    @Test("the sentinel key the code writes is the one the trigger reads")
    func theSentinelKeyMatchesTheTrigger() async throws {
        let store = try await CypressStore.inMemory()
        let triggerSQL = try await store.queue.read { connection -> String in
            let statement = try connection.prepare("""
                SELECT sql FROM sqlite_master WHERE type = 'trigger' AND name = 'favorites_are_tombstoned'
                """)
            defer { statement.finalize() }
            return try statement.fetchOne { try $0.stringIfPresent("sql") ?? "" } ?? ""
        }
        // The migration spells the key out as frozen text (a migration must not interpolate a Swift
        // constant a later rename could change), so this is what keeps the two spellings honest.
        #expect(triggerSQL.contains("'\(AccountDeletion.erasureSentinelKey)'"))
        #expect(triggerSQL.contains("EXISTS (SELECT 1 FROM app_state"))
    }

    // MARK: - 6. The migration keeps what was already there

    @Test("migrating a v5 database keeps its rows and replays as a no-op")
    func migrationPreservesExistingRows() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try connection.configureForWriting()
        _ = try SchemaMigrator.migrate(AppSchema.migrations.filter { $0.version <= 5 }, on: connection)

        let liveTree = UUID()
        let offTree = UUID()
        let now = SQLiteTimestamp.string(from: Self.moment)
        try connection.execute("""
            INSERT INTO favorites (id, user_id, tree_uuid, client_uuid, created_at, updated_at, deleted_at)
            VALUES ('\(UUID().uuidString)','\(Self.userID.uuidString)','\(liveTree.uuidString)',
                    '\(UUID().uuidString)','\(now)','\(now)', NULL),
                   ('\(UUID().uuidString)','\(Self.userID.uuidString)','\(offTree.uuidString)',
                    '\(UUID().uuidString)','\(now)','\(now)','\(now)');
            """)

        let expected = AppSchema.migrations.map(\.version).filter { $0 > 5 }
        let applied = try SchemaMigrator.migrate(AppSchema.migrations, on: connection)
        #expect(applied == expected)

        let store = ContributionStore()
        #expect(try store.isFavorite(owner: .user(Self.userID), treeID: liveTree, connection: connection))
        #expect(try !store.isFavorite(owner: .user(Self.userID), treeID: offTree, connection: connection))

        // A run interrupted between the DDL and the version bump has to replay cleanly, and this one
        // is DROP-then-CREATE rather than a table rebuild, so replaying it is the whole guard.
        try connection.setUserVersion(5)
        _ = try SchemaMigrator.migrate(AppSchema.migrations, on: connection)
        #expect(try connection.userVersion == AppSchema.currentVersion)

        // Both rows are still there, and both are still deletable only under an erasure.
        let outcome = try AccountDeletion().delete(
            userID: Self.userID, choice: .leaveRecords, at: Self.moment, connection: connection
        )
        #expect(outcome.deletedFavorites == 2)
        #expect(outcome.deletedFavoriteTombstones == 1)
    }

    // MARK: - 7. The copy, which R3 makes load-bearing

    @Test("each door states its own behavior and the shared clause escapes neither")
    func theCopyStatesBothDoors() {
        // R3's rule was one sentence because there was one behavior. There are now two, and the
        // half that is true either way is hoisted out of both rather than printed inside each — see
        // `AccountDeletionCopy` for the argument. What R3 actually defends against is a person
        // reading the reassuring half and missing the rest, and that is what these pin.
        let stays = AccountDeletionCopy.leaveRecordsBody
        let goes = AccountDeletionCopy.eraseEverythingBody
        let either = AccountDeletionCopy.personalRecords

        #expect(stays.contains("stay on the trees"))
        #expect(stays.contains("photo votes"), "the door that keeps votes must say it keeps votes")
        #expect(stays.contains("Nobody can tell"), "NULL rather than a sentinel is a promise, so it is made")

        #expect(goes.contains("photo vote"))
        #expect(goes.contains("photographs are removed from this phone"))
        #expect(goes.contains("different one"), "the hero consequence must be told rather than discovered")

        #expect(either.hasPrefix("Either way"))
        #expect(either.contains("reminders"))
        #expect(either.contains("favorites"))

        // House style: no spaces around em dashes (ARCHITECTURE §5.7).
        for line in [stays, goes, either, AccountDeletionCopy.queuedWork] {
            #expect(!line.contains(" — "))
        }
        #expect(AccountDeletionCopy.irreversible == "This cannot be undone.")

        // The last tap names its door. Nothing else stops the destructive one being reached by
        // momentum, so this stands in for the whole interaction design.
        let safeLabel = AccountDeletionCopy.confirmAction(for: .leaveRecords)
        let eraseLabel = AccountDeletionCopy.confirmAction(for: .eraseEverything)
        #expect(safeLabel != eraseLabel)
        #expect(eraseLabel.lowercased().contains("erase"))
        #expect(!safeLabel.lowercased().contains("erase"))
        #expect(AccountDeletionChoice.default == .leaveRecords)
        #expect(AccountDeletionChoice.allCases.first == .leaveRecords)
    }

    // MARK: - 8. The two doors

    /// A photo directory of this suite's own, so a test can look at the bytes on disk rather than at
    /// a row that claims something about them.
    private static func photoDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cypress-deletion-\(UUID().uuidString)", isDirectory: true)
    }

    private static func signedIn(photoDirectory: URL) async throws -> (store: CypressStore, api: LocalAPI) {
        let store = try await CypressStore.inMemory()
        return (
            store,
            LocalAPI(
                store: store, deviceID: deviceID, userID: userID,
                photoDirectory: photoDirectory, now: { moment }
            )
        )
    }

    /// A photograph taken on one of the account's visits, uploaded through the shipping path so its
    /// bytes land in the app's photo directory exactly as a real one's would.
    ///
    /// It goes through `beginPhotoUpload`/`uploadPhoto` rather than an INSERT because the thing
    /// under test is whether the deletion can *find* the file, and a hand-written row could agree
    /// with a hand-written filename while the real pair disagreed.
    private static func photograph(
        api: LocalAPI,
        treeID: UUID,
        visitID: UUID
    ) async throws -> (id: UUID, url: URL) {
        let staged = FileManager.default.temporaryDirectory
            .appendingPathComponent("cypress-staged-\(UUID().uuidString).jpg")
        try Data("not really a jpeg, and that is fine: nothing decodes it here".utf8)
            .write(to: staged, options: .atomic)

        let ticket = try await api.beginPhotoUpload(
            PhotoUploadRequest(
                treeID: treeID, visitID: visitID, shotType: .fullTree,
                localPath: staged.path, capturedAt: moment, width: 12, height: 16
            )
        )
        try await api.uploadPhoto(at: staged.path, ticket: ticket)
        return (ticket.photoID, ticket.destination)
    }

    /// One account holding one of everything the ruling names.
    private static func everything(
        api: LocalAPI,
        store: CypressStore
    ) async throws -> (tree: Tree, visit: Visit, photo: (id: UUID, url: URL)) {
        let tree = try await makeTree(api: api, in: store)
        let attribution = Attribution(userID: userID, deviceID: deviceID)
        let visit = try await writeContributions(treeID: tree.id, attribution: attribution, in: store)
        let photo = try await photograph(api: api, treeID: tree.id, visitID: visit.id)

        try await store.queue.write { connection in
            let contributions = ContributionStore()
            try contributions.setPhotoVote(
                photoID: photo.id, owner: .user(userID), vote: .up, at: moment, connection: connection
            )
            try contributions.insert(
                PrivateReminder(owner: .user(userID), treeID: tree.id, category: .uprooted),
                connection: connection
            )
            try contributions.applyFavoriteToggle(
                owner: .user(userID), treeID: tree.id, clientUUID: UUID(),
                isFavorite: true, at: moment, connection: connection
            )
            try contributions.insert(
                TreeName(treeID: tree.id, name: "Grandmother Cypress", givenBy: userID),
                connection: connection
            )
        }
        return (tree, visit, photo)
    }

    @Test("the default door leaves the photo bytes and the vote, with the attribution gone")
    func theDefaultDoorLeavesTheContributions() async throws {
        let (store, api) = try await Self.signedIn(photoDirectory: Self.photoDirectory())
        let fixture = try await Self.everything(api: api, store: store)
        #expect(FileManager.default.fileExists(atPath: fixture.photo.url.path), "fixture: no bytes on disk")

        let outcome = try await api.deleteAccount(.leaveRecords)
        #expect(outcome.choice == .leaveRecords)
        #expect(outcome.anonymizedContributions == 4)
        #expect(outcome.anonymizedPhotoVotes == 1)
        // Both photographs lose their owner: the visit's, and the one `addTree` wrote, which before
        // v12 had no owner to lose (E136, E147).
        #expect(outcome.anonymizedPhotos == 2)
        #expect(outcome.deletedPhotos == 0)
        #expect(outcome.deletedContributions == 0)
        #expect(outcome.deletedPhotoVotes == 0)

        // The bytes, read from the container rather than from a column that claims something about
        // them.
        #expect(
            FileManager.default.fileExists(atPath: fixture.photo.url.path),
            "the default door deleted a photograph's bytes"
        )
        // Two rows: the visit photograph above and the one `addTree` wrote for the tree itself.
        // Both stay, which is what this door promises.
        #expect(try await Self.scalar("SELECT COUNT(*) AS n FROM photos", in: store) == 2)

        // The vote survives and still counts, which is what "leaves them in place" has to mean for a
        // record whose whole purpose is to be aggregated.
        #expect(try await Self.scalar("SELECT COUNT(*) AS n FROM photo_votes", in: store) == 1)
        #expect(try await Self.scalar(
            "SELECT COUNT(*) AS n FROM photo_votes WHERE user_id IS NULL AND device_id IS NULL", in: store
        ) == 1, "the vote kept an owner, or was deleted")

        let tallies = try await store.queue.read { connection in
            try ContributionStore().photoTallies(
                treeID: fixture.tree.id, owner: .device(Self.deviceID), connection: connection
            )
        }
        #expect(tallies[fixture.photo.id]?.score == 1, "hero selection changed on the door that changes nothing")
        #expect(tallies[fixture.photo.id]?.ownVote == nil, "an ownerless vote lit up somebody else's thumb")

        // …and nothing anywhere still names the account.
        for table in ["visits", "observations", "measurements", "care_events"] {
            #expect(try await Self.attributed(table, to: Self.userID, in: store) == 0, "\(table)")
        }
        #expect(try await Self.scalar(
            "SELECT COUNT(*) AS n FROM tree_names WHERE given_by IS NULL", in: store
        ) == 1)
        #expect(try await Self.scalar(
            "SELECT COUNT(*) AS n FROM photos p JOIN visits v ON v.id = p.visit_id WHERE v.user_id IS NOT NULL",
            in: store
        ) == 0)
        // And the photograph's own column, which is where the name actually was after v12. Both
        // rows are owned by nobody now — not re-homed onto the device, which would hand one
        // person's photographs to whoever signs in on this phone next.
        #expect(try await Self.scalar(
            "SELECT COUNT(*) AS n FROM photos WHERE user_id IS NULL AND device_id IS NULL", in: store
        ) == 2, "a photograph kept an owner through the door that takes the name off")
    }

    @Test("the destructive door removes the rows and the files")
    func theDestructiveDoorRemovesRowsAndBytes() async throws {
        let (store, api) = try await Self.signedIn(photoDirectory: Self.photoDirectory())
        let fixture = try await Self.everything(api: api, store: store)

        // A stranger's vote on the account's photograph. It is not this person's to withdraw and it
        // goes anyway, because the photograph it is about is going — the one cost of this door that
        // falls on somebody else, asserted rather than left as a comment.
        try await store.queue.write { connection in
            try ContributionStore().setPhotoVote(
                photoID: fixture.photo.id, owner: .user(Self.strangerID), vote: .up,
                at: Self.moment, connection: connection
            )
        }
        #expect(try await Self.scalar("SELECT COUNT(*) AS n FROM photo_votes", in: store) == 2)

        let outcome = try await api.deleteAccount(.eraseEverything)
        #expect(outcome.choice == .eraseEverything)
        #expect(outcome.deletedContributions == 4)
        // Two, and the second one is the entire point of `AppSchema` v12. One is the visit's
        // photograph, which this door has always reached. The other is the one `addTree` wrote for
        // the tree the account added — no `visit_id`, on a `community_trees` row that records no
        // author — which ERRATA E136 pinned as reachable by neither door and which now carries the
        // account's id in its own column (E147).
        #expect(outcome.deletedPhotos == 2)
        #expect(outcome.deletedPhotoVotes == 2)
        #expect(outcome.deletedAttributions == 1)
        #expect(outcome.anonymizedContributions == 0)
        #expect(outcome.anonymizedPhotoVotes == 0)

        // The file, which an assertion on rows alone would never notice.
        #expect(
            !FileManager.default.fileExists(atPath: fixture.photo.url.path),
            "the JPEG survived an erasure and is now unreachable by any query"
        )
        for table in ["photo_votes", "visits", "observations", "measurements", "care_events", "tree_names"] {
            #expect(try await Self.scalar("SELECT COUNT(*) AS n FROM \(table)", in: store) == 0, "\(table)")
        }
        // The photograph the *visit* carried is gone, and so is the one `addTree` wrote — see
        // `theAddedTreesPhotographIsReachableByBothDoors`, which used to assert the opposite.
        #expect(try await Self.scalar(
            "SELECT COUNT(*) AS n FROM photos WHERE id = '\(fixture.photo.id.uuidString)'", in: store
        ) == 0)
        // The tree is still there. "Everything I have added" is the person's rows, not the forest.
        #expect(try await api.treeProfile(id: fixture.tree.id).tree.id == fixture.tree.id)
    }

    /// **The hole ERRATA E136 pinned, closed and pinned from the other side.**
    ///
    /// This test used to assert the opposite, and its own note said why: `LocalAPI.addTree` writes a
    /// photograph with no `visit_id`, `community_trees` records no author, and neither door could
    /// tell that photograph from somebody else's. It existed "so that the gap is a failing assertion
    /// the day somebody adds that column and forgets this path, rather than a silence". The column
    /// arrived as `AppSchema` v12 and this path was not forgotten; the assertion is now the sentence
    /// the copy always claimed.
    ///
    /// Both doors, both halves — the row *and* the bytes, because a row-only assertion would pass
    /// against an erasure that left the JPEG in the container, which is the exact failure the whole
    /// arrangement exists to prevent.
    @Test("the photograph on a tree you added is reachable by both doors")
    func theAddedTreesPhotographIsReachableByBothDoors() async throws {
        for choice in AccountDeletionChoice.allCases {
            let (store, api) = try await Self.signedIn(photoDirectory: Self.photoDirectory())
            // A real file at the staged path, so "the bytes went" is a fact about the disk rather
            // than about a column that claims something about it.
            let staged = FileManager.default.temporaryDirectory
                .appendingPathComponent("cypress-added-\(UUID().uuidString).jpg")
            try Data("the tree I added".utf8).write(to: staged, options: .atomic)
            let tree = try await api.addTree(
                TreeDraft(
                    coordinate: Coordinate(latitude: 37.77, longitude: -122.44),
                    photoLocalPath: staged.path,
                    attribution: Attribution(userID: Self.userID, deviceID: Self.deviceID)
                )
            )

        // `addTree` is one of spec §3.4's nine and now queues an `add_tree` row of its own,
        // in the transaction that adds the tree. This suite is not about that row, and every
        // queue count below would otherwise be counting the fixture. See
        // `OutboxTestSupport.discardFixtureRows`.
            try await OutboxTestSupport.discardFixtureRows(in: store)

            #expect(try await Self.scalar(
                "SELECT COUNT(*) AS n FROM photos WHERE visit_id IS NULL", in: store
            ) == 1, "fixture: \(choice)")
            #expect(try await Self.scalar(
                """
                SELECT COUNT(*) AS n FROM photos
                 WHERE visit_id IS NULL AND user_id = '\(Self.userID.uuidString)'
                """,
                in: store
            ) == 1, "fixture: \(choice): the visitless photograph was written with no owner")

            try await api.deleteAccount(choice)

            let rows = try await Self.scalar(
                "SELECT COUNT(*) AS n FROM photos WHERE tree_uuid = '\(tree.id.uuidString)'", in: store
            )
            let onDisk = FileManager.default.fileExists(atPath: staged.path)
            switch choice {
            case .eraseEverything:
                #expect(rows == 0, "erase everything left the photograph of a tree the account added")
                #expect(!onDisk, "erase everything left the added tree's JPEG on disk — E136's hole")
            case .leaveRecords:
                #expect(rows == 1, "the leaving door deleted a photograph it promised to leave")
                #expect(onDisk, "the leaving door removed bytes it promised to leave")
                #expect(try await Self.scalar(
                    """
                    SELECT COUNT(*) AS n FROM photos
                     WHERE tree_uuid = '\(tree.id.uuidString)'
                       AND user_id IS NULL AND device_id IS NULL
                    """,
                    in: store
                ) == 1, "the leaving door left the account's name on the photograph")
            }
            // Under both doors the tree itself stays: "everything I have added" is the person's
            // rows, not the forest.
            #expect(try await api.treeProfile(id: tree.id).tree.id == tree.id, "\(choice)")
            try? FileManager.default.removeItem(at: staged)
        }
    }

    @Test("the destructive door does not touch the device's own rows or a stranger's")
    func theDestructiveDoorIsScopedToTheAccount() async throws {
        let (store, api) = try await Self.signedIn(photoDirectory: Self.photoDirectory())
        let mine = try await Self.makeTree(api: api, in: store)
        let theirs = try await Self.makeTree(api: api, in: store, at: -122.46)

        try await Self.writeContributions(
            treeID: mine.id, attribution: Attribution(userID: Self.userID, deviceID: Self.deviceID), in: store
        )
        // The device's own work, written before there was an account and never moved onto it, plus a
        // second account's. Neither identity is being deleted and neither can consent here.
        try await Self.writeContributions(
            treeID: theirs.id, attribution: Attribution.anonymous(deviceID: Self.deviceID), in: store
        )
        try await Self.writeContributions(
            treeID: theirs.id, attribution: Attribution(userID: Self.strangerID, deviceID: Self.deviceID), in: store
        )
        try await store.queue.write { connection in
            try ContributionStore().insert(
                PrivateReminder(owner: .device(Self.deviceID), treeID: theirs.id, category: .uprooted),
                connection: connection
            )
        }

        try await api.deleteAccount(.eraseEverything)

        for table in ["visits", "observations", "measurements", "care_events"] {
            #expect(try await Self.scalar("SELECT COUNT(*) AS n FROM \(table)", in: store) == 2, "\(table)")
            #expect(try await Self.attributed(table, to: Self.strangerID, in: store) == 1, "\(table): a stranger's row went")
        }
        let deviceReminders = try await store.queue.read { connection in
            try ContributionStore().privateReminders(userID: nil, deviceID: Self.deviceID, connection: connection)
        }
        #expect(deviceReminders.count == 1, "the device's own reminder went with somebody else's account")
    }

    @Test("the destructive door discards queued contributions instead of landing them anonymously")
    func theDestructiveDoorEmptiesTheQueue() async throws {
        let (store, api) = try await Self.signedIn(photoDirectory: Self.photoDirectory())
        let tree = try await Self.makeTree(api: api, in: store)
        let attribution = Attribution(userID: Self.userID, deviceID: Self.deviceID)

        // A queued visit with a staged JPEG, which is the state a phone is in on a bus: the
        // photograph is on disk with no `photos` row at all, so a deletion that only looked at
        // `photos` would leave the most recent picture the person took.
        let staged = FileManager.default.temporaryDirectory
            .appendingPathComponent("cypress-queued-\(UUID().uuidString).jpg")
        try Data("queued bytes".utf8).write(to: staged, options: .atomic)

        let queued = Visit(treeID: tree.id, attribution: attribution, capturedAt: Self.moment)
        try await store.queue.write { connection in
            let item = try OutboxPayload.visit(queued).makeItem(
                photos: [OutboxPhoto(path: staged.path, shotType: .fullTree)]
            )
            try OutboxStore().enqueue(item, connection: connection)
        }
        #expect(FileManager.default.fileExists(atPath: staged.path), "fixture: nothing staged")

        let outcome = try await api.deleteAccount(.eraseEverything)
        #expect(outcome.anonymizedOutboxItems == 0, "a contribution the person erased was kept to land later")
        #expect(outcome.discardedOutboxItems == 1)
        #expect(try await store.queue.read { connection in
            try OutboxStore().allItems(connection: connection).count
        } == 0)
        #expect(
            !FileManager.default.fileExists(atPath: staged.path),
            "the staged JPEG of an erased visit is still on disk"
        )
    }

    @Test("a deleted account is unrecoverable through either door")
    func neitherDoorLeavesTheAccountResumable() async throws {
        for choice in AccountDeletionChoice.allCases {
            let (store, api) = try await Self.signedIn(photoDirectory: Self.photoDirectory())
            try await api.claimDevice(deviceUUID: Self.deviceID, userID: Self.userID)

            try await api.deleteAccount(choice)

            #expect(await api.userID == nil, "\(choice)")
            #expect(try await store.appState(.currentUserID) == nil, "\(choice)")
            #expect(try await api.resumableUserID() == nil, "\(choice): the account was left resumable")
            await #expect(throws: APIError.unauthorized) { try await api.deleteAccount(choice) }
        }
    }

    // MARK: - 9. v9, which is what lets a vote outlive its voter

    @Test("v9 accepts an ownerless vote and v8 did not")
    func theVoteCheckWasRelaxedRatherThanRemoved() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try connection.configureForWriting()

        // v8's shape, on a database that stops there. That CHECK is why R3 deleted votes rather than
        // anonymizing them, so it is worth proving it really did refuse.
        _ = try SchemaMigrator.migrate(AppSchema.migrations.filter { $0.version <= 8 }, on: connection)
        let tree = UUID(), photo = UUID(), voter = UUID()
        let stamp = SQLiteTimestamp.string(from: Self.moment)
        try connection.execute("""
            INSERT INTO photos (id, tree_uuid, shot_type, captured_at, created_at, updated_at)
            VALUES ('\(photo.uuidString)','\(tree.uuidString)','full_tree','\(stamp)','\(stamp)','\(stamp)');
            INSERT INTO photo_votes (id, photo_id, tree_uuid, user_id, device_id, vote, created_at, updated_at)
            VALUES ('\(UUID().uuidString)','\(photo.uuidString)','\(tree.uuidString)',
                    '\(voter.uuidString)', NULL, 1, '\(stamp)','\(stamp)');
            """)
        #expect(throws: (any Error).self) {
            try connection.execute("UPDATE photo_votes SET user_id = NULL")
        }

        // Migrating forward keeps the row and lifts exactly that refusal.
        let applied = try SchemaMigrator.migrate(AppSchema.migrations, on: connection)
        #expect(applied == AppSchema.migrations.map(\.version).filter { $0 > 8 })
        #expect(try connection.userVersion == AppSchema.currentVersion)
        try connection.execute("UPDATE photo_votes SET user_id = NULL")

        // Relaxed, not removed: owned twice is still refused, which is the half of v8's rule that
        // was about integrity rather than about deletion.
        #expect(throws: (any Error).self) {
            try connection.execute("""
                UPDATE photo_votes SET user_id = '\(voter.uuidString)', device_id = '\(UUID().uuidString)'
                """)
        }

        // A replay from an interrupted run lands on the same table rather than rebuilding it twice.
        try connection.setUserVersion(8)
        _ = try SchemaMigrator.migrate(AppSchema.migrations, on: connection)
        let survivors = try connection.prepare("SELECT COUNT(*) AS n FROM photo_votes")
        defer { survivors.finalize() }
        #expect(try survivors.fetchOne { try $0.int("n") } == 1, "the rebuild lost the votes it copied")
    }

    // MARK: - 8. Through the router, against a real store (ERRATA E272)

    /// Everything above proves what the *local* half does. These two prove **whether it runs at
    /// all**, over the same tables, because the owner's ruling of 2026-08-23 put `DELETE /me` in
    /// front of it: a deletion that cannot reach the service deletes nothing here.
    ///
    /// `RoutedAPITests` pins the ordering against a double. This pins the rows, because "nothing was
    /// deleted" is a claim about rows and a double cannot be wrong about them in the way a store can.

    /// A router over the real signed-in `LocalAPI`, with a scripted service in front of it.
    private static func routed(api: LocalAPI, transport: ScriptedTransport) -> RoutedAPI {
        let remote = RemoteAPI(
            baseURL: URL(string: "https://service.invalid/api/v1")!,
            transport: transport,
            session: .shared,
            pendingOutboxKeys: { [] }
        )
        return RoutedAPI(local: api, remote: remote, signedInUserID: { userID })
    }

    @Test("a service that refuses leaves every row where it was")
    func aRefusedDeletionLeavesTheRowsAlone() async throws {
        let (store, api) = try await Self.signedIn()
        let tree = try await Self.makeTree(api: api, in: store)
        let attribution = Attribution(userID: Self.userID, deviceID: Self.deviceID)
        try await Self.writeContributions(treeID: tree.id, attribution: attribution, in: store)
        try await store.queue.write { connection in
            try ContributionStore().insert(
                PrivateReminder(owner: .user(Self.userID), treeID: tree.id, category: .uprooted),
                connection: connection
            )
        }
        // `claimDevice` is what writes `app_state.currentUserID`, so without it the signed-in
        // assertion below would read nil before the deletion as well as after and pass on a
        // deletion that had emptied everything.
        try await api.claimDevice(deviceUUID: Self.deviceID, userID: Self.userID)
        #expect(try await store.appState(.currentUserID) == Self.userID.uuidString, "fixture")

        let transport = ScriptedTransport()
        transport.answer("DELETE /me", throwing: APIError.serverError)

        await #expect(throws: APIError.serverError) {
            _ = try await Self.routed(api: api, transport: transport).deleteAccount(.eraseEverything)
        }

        // Every table the erasing door would have emptied still holds its row, still attributed.
        for table in ["visits", "observations", "measurements", "care_events"] {
            #expect(
                try await Self.attributed(table, to: Self.userID, in: store) == 1,
                "\(table) was deleted after the service refused the deletion"
            )
        }
        #expect(try await Self.scalar(
            "SELECT COUNT(*) AS n FROM private_reminders WHERE user_id = '\(Self.userID.uuidString)'", in: store
        ) == 1, "the reminders went with a deletion that never happened")

        // And the account is still signed in, so the sheet has something to retry against.
        #expect(
            try await store.appState(.currentUserID) == Self.userID.uuidString,
            "the deletion signed the person out of an account it did not delete"
        )
    }

    @Test("a service that accepts is followed by the whole local deletion")
    func anAcceptedDeletionRunsTheLocalHalf() async throws {
        let (store, api) = try await Self.signedIn()
        let tree = try await Self.makeTree(api: api, in: store)
        let attribution = Attribution(userID: Self.userID, deviceID: Self.deviceID)
        try await Self.writeContributions(treeID: tree.id, attribution: attribution, in: store)
        // As above: the signed-out assertion at the end is only worth making about a device that
        // was signed in to begin with.
        try await api.claimDevice(deviceUUID: Self.deviceID, userID: Self.userID)
        #expect(try await store.appState(.currentUserID) == Self.userID.uuidString, "fixture")

        let transport = ScriptedTransport()
        transport.answer(
            "DELETE /me",
            with: #"{"deleted":true,"choice":"leave_records","contributions":4,"photos":0,"tombstones":0}"#
        )

        let outcome = try await Self.routed(api: api, transport: transport).deleteAccount(.leaveRecords)

        #expect(transport.call("DELETE /me") != nil, "the service was not asked")
        #expect(outcome.choice == .leaveRecords)

        // R3's local behavior, unchanged by the wire now in front of it: the rows stay, nulled.
        for table in ["visits", "observations", "measurements", "care_events"] {
            #expect(
                try await Self.attributed(table, to: Self.userID, in: store) == 0,
                "\(table) still names the deleted account"
            )
            #expect(
                try await Self.scalar("SELECT COUNT(*) AS n FROM \(table)", in: store) == 1,
                "\(table)'s row was destroyed by the door that keeps it"
            )
        }
        #expect(try await store.appState(.currentUserID) == nil, "the account survived its own deletion")
    }
}
