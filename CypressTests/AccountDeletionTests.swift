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
/// 2. **a private reminder and a favourite do not survive** — including a favourite *tombstone*,
///    which the v5 trigger would have refused to delete and which is exactly as unreadable as a live
///    row once its owner is gone;
/// 3. **somebody else's rows are untouched** — the device's own, and a stranger account's;
/// 4. **the two halves are one transaction** — a failure after the anonymization has already run
///    leaves the database exactly as it was, because a half-deleted person cannot tell and cannot
///    retry;
/// 5. **the queue cannot resurrect what was deleted** — a favourite toggle queued before the
///    deletion does not re-create the favourite when it drains afterwards, and a queued visit lands
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
    private static func makeTree(api: LocalAPI, at longitude: Double = -122.44) async throws -> Tree {
        try await api.addTree(
            TreeDraft(
                coordinate: Coordinate(latitude: 37.77, longitude: longitude),
                photoLocalPath: "/tmp/cypress-deletion-test.jpg",
                attribution: Attribution.anonymous(deviceID: deviceID)
            )
        )
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
                    quantity: Quantity(value: 31, unit: .centimetres, method: .tape)
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
        let tree = try await Self.makeTree(api: api)
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

        let outcome = try await api.deleteAccount()
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

        try await api.deleteAccount()

        let claimed = try await store.queue.read { connection in
            try ContributionStore().claimedUser(forDevice: Self.deviceID, connection: connection)
        }
        #expect(claimed == nil, "the device is still linked to the deleted account")
        #expect(try await store.appState(.currentUserID) == nil)
        #expect(await api.userID == nil)

        // And a second deletion is refused rather than silently succeeding, because there is no
        // longer an account to delete.
        await #expect(throws: APIError.unauthorized) { try await api.deleteAccount() }
    }

    // MARK: - 2. What only one person could ever see

    @Test("a private reminder and a favourite do not survive their account")
    func exclusivelyOwnedRowsAreDeleted() async throws {
        let (store, api) = try await Self.signedIn()
        let tree = try await Self.makeTree(api: api)
        let other = try await Self.makeTree(api: api, at: -122.46)

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

        let outcome = try await api.deleteAccount()
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
        ) == 0, "the account's favourite was re-homed onto the device rather than deleted")

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

    @Test("a favourite tombstone goes with the account too")
    func tombstonesAreDeleted() async throws {
        let (store, api) = try await Self.signedIn()
        let tree = try await Self.makeTree(api: api)

        // On, then off: one row whose `deleted_at` is set. E89 keeps this row rather than deleting
        // it so that sync can carry the un-favourite event — and there is no such sync for an
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
        ) == 1, "fixture: the un-favourite should have tombstoned rather than deleted")

        let outcome = try await api.deleteAccount()
        #expect(outcome.deletedFavorites == 1)
        #expect(outcome.deletedFavoriteTombstones == 1)
        #expect(try await Self.scalar("SELECT COUNT(*) AS n FROM favorites", in: store) == 0)
    }

    // MARK: - 3. One transaction

    @Test("a failure part-way through leaves nothing anonymized")
    func theDeletionIsOneTransaction() async throws {
        let (store, api) = try await Self.signedIn()
        let tree = try await Self.makeTree(api: api)
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

        await #expect(throws: (any Error).self) { try await api.deleteAccount() }

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
        let outcome = try await api.deleteAccount()
        #expect(outcome.anonymizedContributions == 4)
        #expect(outcome.deletedPrivateReminders == 1)
        #expect(outcome.deletedFavorites == 1)
    }

    // MARK: - 4. The queue

    @Test("queued reminders and favourites are discarded, queued contributions are anonymized")
    func theOutboxIsTakenWithTheAccount() async throws {
        let (store, api) = try await Self.signedIn()
        let tree = try await Self.makeTree(api: api)
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

        let outcome = try await api.deleteAccount()
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

        // Draining now must not resurrect the favourite the deletion removed.
        let results = try await api.sync(records.map(\.item))
        #expect(results.allSatisfy { $0.status != .failed })
        #expect(try await Self.attributed("visits", to: Self.userID, in: store) == 0)
        #expect(try await Self.scalar("SELECT COUNT(*) AS n FROM visits", in: store) == 1)
        #expect(try await Self.scalar(
            "SELECT COUNT(*) AS n FROM favorites WHERE user_id = '\(Self.userID.uuidString)'", in: store
        ) == 0, "a queued toggle re-created the deleted account's favourite")
        // The device's own toggle applied, exactly as it would have without a deletion.
        #expect(try await store.queue.read { connection in
            try ContributionStore().isFavorite(owner: .device(Self.deviceID), treeID: tree.id, connection: connection)
        })
    }

    // MARK: - 5. The hole in the trigger is one account wide

    @Test("with no erasure in progress a user-owned favourite still cannot be hard-deleted")
    func theTriggerStillRefusesEverythingElse() async throws {
        let (store, api) = try await Self.signedIn()
        let tree = try await Self.makeTree(api: api)
        try await store.queue.write { connection in
            try ContributionStore().applyFavoriteToggle(
                owner: .user(Self.userID), treeID: tree.id, clientUUID: UUID(),
                isFavorite: true, at: Self.moment, connection: connection
            )
        }

        // The `WHEN` clause has to be written with EXISTS rather than a comparison against the
        // sentinel's value: with no sentinel row the comparison is NULL, `NOT (0 OR NULL)` is NULL,
        // and a NULL `WHEN` does not fire — which would leave every user-owned favourite hard
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
        try await api.deleteAccount()
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
        let outcome = try AccountDeletion().delete(userID: Self.userID, at: Self.moment, connection: connection)
        #expect(outcome.deletedFavorites == 2)
        #expect(outcome.deletedFavoriteTombstones == 1)
    }

    // MARK: - 7. The copy, which R3 makes load-bearing

    @Test("the deletion copy names the reminders and the favourites in the sentence that keeps the observations")
    func theCopyEnumeratesBoth() {
        let sentence = AccountDeletionCopy.whatHappens
        // R3: "A person deleting an account should be told that their reminders and favourites go
        // with it, before it happens, in the same sentence that tells them their observations stay."
        // One sentence — deleting more than someone expected is the failure mode this ruling
        // creates, and copy split into two paragraphs is how the second one stops being read.
        #expect(sentence.contains("reminders"))
        #expect(sentence.contains("favorites"))
        #expect(sentence.contains("stay on the trees"))
        #expect(sentence.filter { $0 == "." }.count == 1, "the two halves must arrive in one sentence")
        // House style: no spaces around em dashes (ARCHITECTURE §5.7).
        #expect(!sentence.contains(" — "))
        #expect(sentence.contains("—"))
        #expect(AccountDeletionCopy.irreversible == "This cannot be undone.")
    }
}
