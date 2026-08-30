import Foundation

/// The two acceptance gates from ARCHITECTURE §7, written framework-free.
///
/// Each gate returns a list of failure descriptions — empty means it passed. That shape exists so
/// the *same code* runs from two places without drifting:
///
/// 1. the Swift Testing suites in this folder, once a test target is configured;
/// 2. a plain executable harness, which is how these were run for real before that target existed.
///
/// A gate that only ever ran inside a test target nobody has wired up would be a gate in name only.
public enum DataGates {

    /// A failure, with enough context to act on without a debugger.
    public static func expect(_ condition: Bool, _ message: @autoclosure () -> String, into failures: inout [String]) {
        if !condition { failures.append(message()) }
    }

    // MARK: - Gate 0: the sqlite3 wrapper

    /// Not one of the two acceptance gates, but everything they assert runs through this code, so
    /// it is checked first: parameter binding lifetime, transaction rollback, migration
    /// idempotency, and the schema invariants that BUILD-PLAN §13 asks to be enforced rather than
    /// documented.
    public static func sqliteStore() async throws -> [String] {
        var failures: [String] = []

        // --- Binding lifetime. With SQLITE_STATIC instead of SQLITE_TRANSIENT this loop reads back
        // freed memory: the Swift String backing each bind is gone by the time sqlite copies it.
        // 500 rows is enough for the allocator to reuse the freed buffers.
        do {
            let queue = try DatabaseQueue.inMemory()
            try await queue.write { connection in
                try connection.execute("CREATE TABLE t (i INTEGER, s TEXT, b BLOB)")
                let statement = try connection.cachedStatement("INSERT INTO t (i, s, b) VALUES (:i, :s, :b)")
                for index in 0..<500 {
                    _ = try statement.reset()
                    // Built and destroyed inside this iteration on purpose.
                    let text = "row-\(index)-" + String(repeating: "x", count: 64)
                    _ = try statement.bind([":i": index, ":s": text, ":b": Data(text.utf8)])
                    try statement.run()
                }
                _ = try statement.reset()
            }
            let mismatches = try await queue.read { connection -> Int in
                let statement = try connection.prepare("SELECT i, s, b FROM t ORDER BY i")
                defer { statement.finalize() }
                return try statement.fetchAll { row -> Int in
                    let index = try row.int("i")
                    let expected = "row-\(index)-" + String(repeating: "x", count: 64)
                    let textMatches = try row.string("s") == expected
                    let blobMatches = try row.data("b") == Data(expected.utf8)
                    return (textMatches && blobMatches) ? 0 : 1
                }.reduce(0, +)
            }
            expect(mismatches == 0, "SQLITE_TRANSIENT: \(mismatches)/500 bound values came back wrong", into: &failures)
        }

        // --- Transactions roll back, including nested savepoints.
        do {
            let queue = try DatabaseQueue.inMemory()
            try await queue.write { connection in
                try connection.execute("CREATE TABLE t (i INTEGER PRIMARY KEY)")
                try connection.execute("INSERT INTO t VALUES (1)")
            }
            struct Boom: Error {}
            do {
                try await queue.write { connection in
                    try connection.execute("INSERT INTO t VALUES (2)")
                    try connection.transaction {
                        try connection.execute("INSERT INTO t VALUES (3)")
                    }
                    throw Boom()
                }
                failures.append("transaction: a throwing write did not propagate its error")
            } catch is Boom {
                // expected
            }
            let count = try await queue.read { connection -> Int in
                let statement = try connection.prepare("SELECT COUNT(*) AS n FROM t")
                defer { statement.finalize() }
                return try statement.fetchOne { try $0.int("n") } ?? -1
            }
            expect(count == 1, "transaction: rollback left \(count) rows, expected 1", into: &failures)
        }

        // --- Migrations are ordered, idempotent, and recorded in PRAGMA user_version.
        do {
            let connection = try SQLiteConnection(path: ":memory:")
            let first = try SchemaMigrator.migrate(AppSchema.migrations, on: connection)
            let second = try SchemaMigrator.migrate(AppSchema.migrations, on: connection)
            let version = try connection.userVersion
            expect(
                first == AppSchema.migrations.map(\.version),
                "migrations: first run applied \(first), expected \(AppSchema.migrations.map(\.version))",
                into: &failures
            )
            expect(second.isEmpty, "migrations: second run re-applied \(second)", into: &failures)
            expect(
                version == AppSchema.currentVersion,
                "migrations: user_version is \(version), expected \(AppSchema.currentVersion)",
                into: &failures
            )

            // Re-running the DDL itself must also be a no-op — a run interrupted between the DDL
            // and the version bump has to replay cleanly.
            try connection.setUserVersion(0)
            _ = try SchemaMigrator.migrate(AppSchema.migrations, on: connection)

            // A database from the future is refused rather than half-understood.
            try connection.setUserVersion(999)
            do {
                _ = try SchemaMigrator.migrate(AppSchema.migrations, on: connection)
                failures.append("migrations: a database ahead of this build was accepted")
            } catch is MigrationError {
                // expected
            }
        }

        // --- Schema invariants (BUILD-PLAN §13), enforced by the engine.
        do {
            let store = try await CypressStore.inMemory()

            func rejects(_ label: String, _ sql: String) async {
                do {
                    try await store.queue.write { connection in try connection.execute(sql) }
                    failures.append("invariant not enforced: \(label)")
                } catch {
                    // expected
                }
            }

            let now = SQLiteTimestamp.string(from: Date())
            let tree = UUID().uuidString
            let device = UUID().uuidString

            // D7: a quantity without its method, or without its unit, cannot be stored.
            await rejects("measurement without method", """
                INSERT INTO measurements (id, tree_uuid, device_id, client_uuid, captured_at, kind,
                    value, unit_entered, si_value, method, measurement_height_m, created_at, updated_at)
                VALUES ('\(UUID().uuidString)','\(tree)','\(device)','\(UUID().uuidString)','\(now)',
                    'dbh', 31, 'cm', 0.31, NULL, 1.4, '\(now)', '\(now)')
                """)
            await rejects("measurement with an unknown unit", """
                INSERT INTO measurements (id, tree_uuid, device_id, client_uuid, captured_at, kind,
                    value, unit_entered, si_value, method, measurement_height_m, created_at, updated_at)
                VALUES ('\(UUID().uuidString)','\(tree)','\(device)','\(UUID().uuidString)','\(now)',
                    'dbh', 31, 'furlong', 0.31, 'tape', 1.4, '\(now)', '\(now)')
                """)
            // measurement_height_m accompanies DBH and only DBH.
            await rejects("height carrying a measurement height", """
                INSERT INTO measurements (id, tree_uuid, device_id, client_uuid, captured_at, kind,
                    value, unit_entered, si_value, method, measurement_height_m, created_at, updated_at)
                VALUES ('\(UUID().uuidString)','\(tree)','\(device)','\(UUID().uuidString)','\(now)',
                    'height', 8, 'm', 8, 'laser', 1.4, '\(now)', '\(now)')
                """)
            await rejects("dbh without a measurement height", """
                INSERT INTO measurements (id, tree_uuid, device_id, client_uuid, captured_at, kind,
                    value, unit_entered, si_value, method, measurement_height_m, created_at, updated_at)
                VALUES ('\(UUID().uuidString)','\(tree)','\(device)','\(UUID().uuidString)','\(now)',
                    'dbh', 31, 'cm', 0.31, 'tape', NULL, '\(now)', '\(now)')
                """)
            // D4: a hazard category cannot become a public community note.
            for hazard in HazardCategory.allCases {
                await rejects("hazard category '\(hazard.rawValue)' stored as a community note", """
                    INSERT INTO community_notes (id, tree_uuid, user_id, category, stale_at, created_at, updated_at)
                    VALUES ('\(UUID().uuidString)','\(tree)','\(UUID().uuidString)','\(hazard.rawValue)',
                        '\(now)','\(now)','\(now)')
                    """)
            }
            // A private reminder always has exactly one owner (ERRATA E23). Never none…
            await rejects("private reminder with no owner", """
                INSERT INTO private_reminders (id, tree_uuid, category, created_at, updated_at)
                VALUES ('\(UUID().uuidString)','\(tree)','hanging_or_broken_limb','\(now)','\(now)')
                """)
            // …and never two, which is what would make "whose reminder is this" a precedence rule.
            await rejects("private reminder owned by both a user and a device", """
                INSERT INTO private_reminders (id, user_id, device_id, tree_uuid, category, created_at, updated_at)
                VALUES ('\(UUID().uuidString)','\(UUID().uuidString)','\(device)','\(tree)',
                    'hanging_or_broken_limb','\(now)','\(now)')
                """)
            // The CHECK has to reject those two and accept a device-owned reminder — a constraint
            // that rejects everything would pass both assertions above and break screen 06.
            do {
                try await store.queue.write { connection in
                    try connection.execute("""
                        INSERT INTO private_reminders (id, device_id, tree_uuid, category, created_at, updated_at)
                        VALUES ('\(UUID().uuidString)','\(device)','\(tree)',
                            'hanging_or_broken_limb','\(now)','\(now)')
                        """)
                }
            } catch {
                failures.append("a device-owned private reminder was rejected: \(error)")
            }

            // …and the inverse: a private reminder can only hold a hazard category.
            for category in CommunityNote.Category.allCases {
                await rejects("community-note category '\(category.rawValue)' stored as a private reminder", """
                    INSERT INTO private_reminders (id, user_id, tree_uuid, category, created_at, updated_at)
                    VALUES ('\(UUID().uuidString)','\(UUID().uuidString)','\(tree)','\(category.rawValue)',
                        '\(now)','\(now)')
                    """)
            }
            // Vitality is the anchored 1–5 scale, not a free number.
            await rejects("vitality outside 1...5", """
                INSERT INTO observations (id, tree_uuid, device_id, client_uuid, captured_at, vitality,
                    verification_state, created_at, updated_at)
                VALUES ('\(UUID().uuidString)','\(tree)','\(device)','\(UUID().uuidString)','\(now)', 6,
                    'unverified','\(now)','\(now)')
                """)
            // An outbox row cannot claim `done` while a photo binary is still on device.
            //
            // Against `photos_outstanding` since `AppSchema` v18, where the binaries became rows in
            // `outbox_photos` and this counter — kept by that migration's two triggers — is what a
            // CHECK can read; SQLite CHECKs cannot hold a subquery. The invariant is v1's and is
            // unchanged: zero loss is a schema rule, not a convention.
            // A binary cannot be moved between items: the counter both triggers maintain has no
            // third arm, so a reassignment would leave one item able to settle with work
            // outstanding and another unable to settle at all (`AppSchema` v18).
            await rejects("outbox_photos row reassigned to another item", """
                INSERT INTO outbox (id, kind, client_uuid, payload, state, local_applied,
                    window_started_at, created_at, updated_at)
                VALUES ('11111111-1111-4111-8111-111111111111','visit',
                    '\(UUID().uuidString)','{}','pending',1,'\(now)','\(now)','\(now)');
                INSERT INTO outbox (id, kind, client_uuid, payload, state, local_applied,
                    window_started_at, created_at, updated_at)
                VALUES ('22222222-2222-4222-8222-222222222222','visit',
                    '\(UUID().uuidString)','{}','pending',1,'\(now)','\(now)','\(now)');
                INSERT INTO outbox_photos (id, outbox_id, path, shot_type, state, sendable,
                    created_at, updated_at)
                VALUES ('33333333-3333-4333-8333-333333333333',
                    '11111111-1111-4111-8111-111111111111','/tmp/move.jpg','full_tree','pending',1,
                    '\(now)','\(now)');
                UPDATE outbox_photos SET outbox_id = '22222222-2222-4222-8222-222222222222'
                 WHERE id = '33333333-3333-4333-8333-333333333333';
                """)

            await rejects("outbox row marked done with photos pending", """
                INSERT INTO outbox (id, kind, client_uuid, payload, photos_outstanding, state,
                    local_applied, window_started_at, created_at, updated_at)
                VALUES ('\(UUID().uuidString)','visit','\(UUID().uuidString)','{}',1,'done',1,
                    '\(now)','\(now)','\(now)')
                """)

            // A favorite always has exactly one owner too (ERRATA E89), by the same CHECK and for
            // the same reasons as a private reminder. Never none…
            await rejects("favorite with no owner", """
                INSERT INTO favorites (id, tree_uuid, client_uuid, created_at, updated_at)
                VALUES ('\(UUID().uuidString)','\(tree)','\(UUID().uuidString)','\(now)','\(now)')
                """)
            // …and never two, which is what would make "whose favorite is this" a precedence rule.
            await rejects("favorite owned by both a user and a device", """
                INSERT INTO favorites (id, user_id, device_id, tree_uuid, client_uuid, created_at, updated_at)
                VALUES ('\(UUID().uuidString)','\(UUID().uuidString)','\(device)','\(tree)',
                    '\(UUID().uuidString)','\(now)','\(now)')
                """)

            // Favorites are tombstoned, never hard-deleted.
            try await store.queue.write { connection in
                try ContributionStore().applyFavoriteToggle(
                    owner: .user(OutboxTestSupport.userID),
                    treeID: UUID(uuidString: tree)!,
                    clientUUID: UUID(),
                    isFavorite: true,
                    at: Date(),
                    connection: connection
                )
            }
            await rejects("hard delete of a favorite", "DELETE FROM favorites")

            // The uniqueness pair moved from (user, tree) to (owner, tree). One owner may not hold a
            // tree twice — and the device arm has to be checked separately, because a single
            // three-column UNIQUE would have enforced nothing for it (NULLs compare distinct).
            let deviceOwned = UUID()
            try await store.queue.write { connection in
                try ContributionStore().applyFavoriteToggle(
                    owner: .device(deviceOwned),
                    treeID: UUID(uuidString: tree)!,
                    clientUUID: UUID(),
                    isFavorite: true,
                    at: Date(),
                    connection: connection
                )
            }
            await rejects("a second row for one account and one tree", """
                INSERT INTO favorites (id, user_id, tree_uuid, client_uuid, created_at, updated_at)
                VALUES ('\(UUID().uuidString)','\(OutboxTestSupport.userID.uuidString)','\(tree)',
                    '\(UUID().uuidString)','\(now)','\(now)')
                """)
            await rejects("a second row for one device and one tree", """
                INSERT INTO favorites (id, device_id, tree_uuid, client_uuid, created_at, updated_at)
                VALUES ('\(UUID().uuidString)','\(deviceOwned.uuidString)','\(tree)',
                    '\(UUID().uuidString)','\(now)','\(now)')
                """)
            // …while two different owners holding the same tree is the state adoption has to merge,
            // so it must be storable. The two writes above already made it; this is the assertion.
            let bothOwners = try await store.queue.read { connection -> Int in
                let statement = try connection.prepare(
                    "SELECT COUNT(*) AS n FROM favorites WHERE tree_uuid = '\(tree)'"
                )
                defer { statement.finalize() }
                return try statement.fetchOne { try $0.int("n") } ?? -1
            }
            expect(
                bothOwners == 2,
                "uniqueness: a device and an account cannot both favorite one tree (\(bothOwners) rows)",
                into: &failures
            )

            // The trigger's adoption exception is exactly one row wide. A device-owned favorite
            // with no account row beside it is still undeletable — otherwise the exception would be
            // a hole rather than a merge (see `AppSchema` v5).
            let lonely = UUID()
            try await store.queue.write { connection in
                try ContributionStore().applyFavoriteToggle(
                    owner: .device(deviceOwned),
                    treeID: lonely,
                    clientUUID: UUID(),
                    isFavorite: true,
                    at: Date(),
                    connection: connection
                )
            }
            await rejects(
                "hard delete of a device-owned favorite nobody is adopting",
                "DELETE FROM favorites WHERE tree_uuid = '\(lonely.uuidString)'"
            )

            // The trigger's *second* exception (v6, RULINGS R3): an account's own favorites are
            // deleted with the account. It is keyed on a sentinel that exists only inside a deletion
            // transaction, so with nobody being deleted a user-owned favorite is exactly as
            // undeletable as it was under v5.
            //
            // This is the assertion that catches the natural, wrong spelling of the WHEN clause.
            // `OLD.user_id = (SELECT value FROM app_state WHERE key = …)` is NULL when the sentinel
            // is absent, `NOT (0 OR NULL)` is NULL, and a NULL WHEN does not fire — so that form
            // permits every hard delete of a user-owned favorite on every database where nobody is
            // being deleted at all.
            let erasedAccount = UUID()
            let keptTree = UUID()
            try await store.queue.write { connection in
                try ContributionStore().applyFavoriteToggle(
                    owner: .user(erasedAccount),
                    treeID: keptTree,
                    clientUUID: UUID(),
                    isFavorite: true,
                    at: Date(),
                    connection: connection
                )
            }
            await rejects(
                "hard delete of a user-owned favorite with no erasure in progress",
                "DELETE FROM favorites WHERE user_id = '\(erasedAccount.uuidString)'"
            )
            // A sentinel naming a different account does not open it either — the exception is one
            // account wide, not "somebody is being deleted somewhere".
            await rejects("hard delete of a favorite belonging to an account other than the one being erased", """
                INSERT INTO app_state (key, value)
                VALUES ('\(AccountDeletion.erasureSentinelKey)','\(UUID().uuidString)')
                ON CONFLICT(key) DO UPDATE SET value = excluded.value;
                DELETE FROM favorites WHERE user_id = '\(erasedAccount.uuidString)';
                """)
            // …and it does open, or R3 is unimplementable: a trigger that refused everything would
            // pass both assertions above and neither would notice.
            do {
                try await store.queue.write { connection in
                    try AccountDeletion().delete(
                        userID: erasedAccount, choice: .default, at: Date(), connection: connection
                    )
                }
            } catch {
                failures.append("R3: an account's own favorite could not be deleted with the account: \(error)")
            }
            let erasedRows = try await store.queue.read { connection -> Int in
                let statement = try connection.prepare("""
                    SELECT COUNT(*) AS n FROM favorites WHERE user_id = '\(erasedAccount.uuidString)'
                    """)
                defer { statement.finalize() }
                return try statement.fetchOne { try $0.int("n") } ?? -1
            }
            expect(erasedRows == 0, "R3: \(erasedRows) favorites survived their account", into: &failures)
            // The permission slip is torn up by the same transaction that wrote it. A sentinel left
            // on disk would be a standing hole in the trigger for exactly one account id.
            let sentinelSurvived = try await store.queue.read { connection -> Bool in
                let statement = try connection.prepare("""
                    SELECT COUNT(*) AS n FROM app_state WHERE key = '\(AccountDeletion.erasureSentinelKey)'
                    """)
                defer { statement.finalize() }
                return (try statement.fetchOne { try $0.int("n") } ?? 0) > 0
            }
            expect(!sentinelSurvived, "R3: the erasure sentinel outlived the deletion transaction", into: &failures)

            // D15: one active name per tree.
            let named = UUID()
            try await store.queue.write { connection in
                try ContributionStore().insert(
                    TreeName(treeID: named, name: "Grandmother Cypress", givenBy: OutboxTestSupport.userID),
                    connection: connection
                )
            }
            do {
                try await store.queue.write { connection in
                    try ContributionStore().insert(
                        TreeName(treeID: named, name: "Second name", givenBy: OutboxTestSupport.userID),
                        connection: connection
                    )
                }
                failures.append("invariant not enforced: a tree accepted two active names (D15)")
            } catch {
                // expected
            }
        }

        return failures
    }

    // MARK: - Gate 1: outbox chaos

    /// **Twenty queued mutations through scripted failures.**
    ///
    /// ARCHITECTURE §7 / BUILD-PLAN §13: "20 queued mutations across scripted failures; assert zero
    /// loss, zero duplicates on `clientUUID`, correct per-item terminal states", plus — added here
    /// because BUILD-PLAN §4 states the schedule precisely and a wrong backoff is invisible until
    /// it is in the field — that the backoff matches 30 s, 2 m, 10 m, 1 h, then hourly, with a 48 h
    /// cap and a terminal `failed` after it.
    public static func outboxChaos() async throws -> [String] {
        var failures: [String] = []

        let clock = OutboxTestSupport.Clock()
        let store = try await CypressStore.inMemory()
        let transport = OutboxTestSupport.ScriptedTransport(script: .connectionDropped)
        let queue = OutboxQueue(queue: store.queue, apply: transport, now: clock.closure)
        let outboxStore = OutboxStore()

        // Ten trees, so contributions spread across them the way a morning's work does.
        let treeIDs = (0..<10).map { _ in UUID() }
        let mutations = OutboxTestSupport.twentyMutations(treeIDs: treeIDs, capturedAt: clock.now)

        // --- Enqueue, twice. The second pass must be a complete no-op: enqueuing is idempotent on
        // clientUUID, which is what protects against a double tap or a re-run view model.
        for (payload, photos) in mutations {
            _ = try await queue.enqueue(payload, photos: photos)
        }
        for (payload, photos) in mutations {
            _ = try await queue.enqueue(payload, photos: photos)
        }

        var records = try await queue.records()
        expect(records.count == 20, "enqueue: \(records.count) rows after 40 enqueues of 20 mutations", into: &failures)
        expect(
            Set(records.map(\.item.clientUUID)).count == 20,
            "enqueue: duplicate clientUUIDs in the outbox",
            into: &failures
        )

        // --- Pass 1: the connection drops mid-batch. Everything must survive, counted once.
        var report = try await queue.drain()
        expect(report.attempted == 20, "pass 1: attempted \(report.attempted), expected 20", into: &failures)
        expect(report.synced == 0, "pass 1: \(report.synced) items claimed success on a dropped connection", into: &failures)

        records = try await queue.records()
        expect(records.count == 20, "pass 1: lost rows, \(records.count) remain", into: &failures)
        expect(
            records.allSatisfy { $0.item.state == .pending && $0.item.failCount == 1 },
            "pass 1: not every item is pending with failCount 1",
            into: &failures
        )
        // Backoff step 1: 30 s.
        for record in records {
            let delay = record.nextAttemptAt.map { $0.timeIntervalSince(clock.now) } ?? -1
            expect(
                abs(delay - 30) < 0.001,
                "backoff after 1 failure: \(delay) s, expected 30",
                into: &failures
            )
        }

        // Nothing is due yet: draining early must not burn an attempt.
        report = try await queue.drain()
        expect(report.attempted == 0, "backoff: an item was attempted before its next_attempt_at", into: &failures)

        // --- Pass 2, at +30 s: the server is up but unhappy. rate_limited is retryable.
        clock.advance(by: 30)
        await transport.setScript(.allFail(.rateLimited))
        report = try await queue.drain()
        records = try await queue.records()
        expect(report.attempted == 20, "pass 2: attempted \(report.attempted)", into: &failures)
        expect(
            records.allSatisfy { $0.item.state == .pending && $0.item.failCount == 2 },
            "pass 2: rate_limited did not keep every item alive at failCount 2",
            into: &failures
        )
        for record in records {
            let delay = record.nextAttemptAt.map { $0.timeIntervalSince(clock.now) } ?? -1
            expect(abs(delay - 120) < 0.001, "backoff after 2 failures: \(delay) s, expected 120", into: &failures)
        }

        // --- Pass 3, at +2 m: half succeed. The other half take their third failure.
        clock.advance(by: 120)
        let failingHalf = Set(records.prefix(10).map(\.item.clientUUID))
        await transport.setScript(.theseFail(failingHalf, .serverError))
        report = try await queue.drain()
        records = try await queue.records()

        let succeeded = records.filter { $0.item.state == .done }
        expect(succeeded.count == 10, "pass 3: \(succeeded.count) items settled done, expected 10", into: &failures)
        for record in records where failingHalf.contains(record.item.clientUUID) {
            expect(
                record.item.state == .pending && record.item.failCount == 3,
                "pass 3: failing item is \(record.item.state)/failCount \(record.item.failCount)",
                into: &failures
            )
            let delay = record.nextAttemptAt.map { $0.timeIntervalSince(clock.now) } ?? -1
            expect(abs(delay - 600) < 0.001, "backoff after 3 failures: \(delay) s, expected 600", into: &failures)
        }

        // --- Pass 4, at +10 m: two items fail non-retryably. Those go terminal at once rather than
        // spending 48 h on an answer that will not change (BUILD-PLAN §6, APIError.retryable).
        clock.advance(by: 600)
        let permanentlyBad = Set(failingHalf.prefix(2))
        await transport.setScript(.theseFail(permanentlyBad, .validationFailed))
        report = try await queue.drain()
        records = try await queue.records()

        for record in records where permanentlyBad.contains(record.item.clientUUID) {
            expect(
                record.item.state == .failed,
                "non-retryable: item is \(record.item.state), expected failed",
                into: &failures
            )
            expect(
                record.item.lastErrorCode == .validationFailed,
                "non-retryable: lastErrorCode is \(String(describing: record.item.lastErrorCode))",
                into: &failures
            )
            expect(
                record.item.lastError?.isEmpty == false,
                "non-retryable: item has no human-readable reason (screen 17 says why)",
                into: &failures
            )
        }

        // --- Zero loss and zero duplicates.
        records = try await queue.records()
        expect(records.count == 20, "zero loss: \(records.count) rows remain of 20", into: &failures)
        expect(
            Set(records.map(\.item.clientUUID)).count == 20,
            "zero duplicates: outbox holds repeated clientUUIDs",
            into: &failures
        )

        let applied = await transport.applied
        let appliedResponses = await transport.appliedResponses
        let offers = await transport.offers
        expect(applied.count == 18, "zero duplicates: \(applied.count) distinct items applied, expected 18", into: &failures)
        expect(
            appliedResponses.count == appliedResponses.count,
            "zero duplicates: an item was applied more than once",
            into: &failures
        )
        expect(
            Set(appliedResponses).count == appliedResponses.count,
            "zero duplicates: \(appliedResponses.count) applies for \(Set(appliedResponses).count) distinct items",
            into: &failures
        )
        expect(
            offers.values.contains { $0 > 1 },
            "the scenario never re-sent an item, so dedupe was not actually exercised",
            into: &failures
        )

        // --- The visible retry affordance restarts the 48 h window; without that reset the button
        // would do nothing and the item would be silently stuck.
        guard let terminal = records.first(where: { $0.item.state == .failed }) else {
            failures.append("retry: no terminal item to retry")
            return failures
        }
        let didRetry = try await queue.retry(id: terminal.id)
        expect(didRetry, "retry: the retry button did not move a failed item", into: &failures)
        if let after = try await queue.records().first(where: { $0.id == terminal.id }) {
            expect(after.item.state == .pending, "retry: item is \(after.item.state), expected pending", into: &failures)
            expect(after.item.failCount == 0, "retry: failCount is \(after.item.failCount), expected 0", into: &failures)
            expect(
                abs(after.windowStartedAt.timeIntervalSince(clock.now)) < 1,
                "retry: the 48 h window was not restarted",
                into: &failures
            )
        }

        // --- The 48 h cap. An item still failing after the window is terminal, whatever the code.
        clock.advance(by: OutboxRetryPolicy.cap + 1)
        await transport.setScript(.allFail(.serverError))
        _ = try await queue.drain()
        records = try await queue.records()
        for record in records where record.item.state != .done {
            expect(
                record.item.state == .failed,
                "48 h cap: item is \(record.item.state) after the window, expected failed",
                into: &failures
            )
            expect(
                record.item.lastError == OutboxFailureReason.expired
                    || record.item.lastErrorCode?.retryable == false,
                "48 h cap: item does not say why it gave up",
                into: &failures
            )
        }

        // --- The backoff schedule itself, read straight off `Core`'s policy. Verifying the table
        // separately from the drain means a wrong constant fails here rather than in the field.
        let expectedSchedule: [(Int, TimeInterval)] = [
            (1, 30), (2, 120), (3, 600), (4, 3_600),
            (5, 3_600), (6, 3_600), (48, 3_600)
        ]
        for (failCount, expected) in expectedSchedule {
            let actual = OutboxRetryPolicy.delay(afterFailures: failCount)
            expect(
                actual == expected,
                "schedule: delay after \(failCount) failures is \(actual) s, expected \(expected)",
                into: &failures
            )
        }
        expect(
            OutboxRetryPolicy.delay(afterFailures: 0) == 0,
            "schedule: a never-failed item should not wait",
            into: &failures
        )
        expect(
            OutboxRetryPolicy.cap == 48 * 3_600,
            "schedule: the cap is \(OutboxRetryPolicy.cap) s, expected 48 h",
            into: &failures
        )

        // --- Wifi-only applies to photo binaries only.
        do {
            let clock = OutboxTestSupport.Clock()
            let store = try await CypressStore.inMemory()
            let transport = OutboxTestSupport.ScriptedTransport(script: .allSucceed)
            let queue = OutboxQueue(queue: store.queue, apply: transport, now: clock.closure)

            let treeID = UUID()
            let visit = Visit(
                treeID: treeID,
                attribution: OutboxTestSupport.attribution,
                note: "with a photo",
                gpsAccuracyM: 5,
                capturedAt: clock.now
            )
            _ = try await queue.enqueue(
                .visit(visit),
                photos: [OutboxPhoto(path: "/tmp/cypress-photo.jpg", shotType: .leaf)]
            )

            // Metered connection: the JSON goes, the binary waits.
            _ = try await queue.drain(photoUploadsAllowed: false)
            var record = try await queue.records().first
            expect(record?.locallyApplied == true, "wifi-only: the JSON item did not sync on a metered connection", into: &failures)
            expect(record?.item.state == .pending, "wifi-only: item is \(String(describing: record?.item.state))", into: &failures)
            expect(record?.item.photos.count == 1, "wifi-only: the photo was uploaded anyway", into: &failures)
            expect(record?.item.failCount == 0, "wifi-only: waiting for wi-fi counted as a failure", into: &failures)
            let uploadsBefore = await transport.uploadedPhotoPaths.count
            expect(uploadsBefore == 0, "wifi-only: \(uploadsBefore) binaries uploaded on a metered connection", into: &failures)

            // Wi-fi arrives.
            _ = try await queue.drain(photoUploadsAllowed: true)
            record = try await queue.records().first
            expect(record?.item.state == .done, "wifi-only: item did not settle once wi-fi arrived", into: &failures)
            let uploadsAfter = await transport.uploadedPhotoPaths.count
            expect(uploadsAfter == 1, "wifi-only: \(uploadsAfter) binaries uploaded on wi-fi, expected 1", into: &failures)

            // The JSON was accepted exactly once across both passes, despite two drains.
            let appliedTwice = await transport.appliedResponses
            expect(
                Set(appliedTwice).count == appliedTwice.count,
                "wifi-only: the JSON item was applied twice",
                into: &failures
            )
        }

        // --- Crash recovery: a row left `uploading` must be picked up again, not stranded.
        do {
            let clock = OutboxTestSupport.Clock()
            let store = try await CypressStore.inMemory()
            let transport = OutboxTestSupport.ScriptedTransport(script: .allSucceed)
            let queue = OutboxQueue(queue: store.queue, apply: transport, now: clock.closure)
            let item = try await queue.enqueue(
                .visit(Visit(treeID: UUID(), attribution: OutboxTestSupport.attribution, capturedAt: clock.now))
            )
            try await store.queue.write { connection in
                try outboxStore.markUploading([item.id], at: clock.now, connection: connection)
            }
            _ = try await queue.drain()
            let after = try await queue.records().first
            expect(
                after?.item.state == .done,
                "crash recovery: an interrupted `uploading` row was not recovered (state \(String(describing: after?.item.state)))",
                into: &failures
            )
        }

        return failures
    }

    // MARK: - Gate 1b: a photo's shot type survives the outbox

    /// **The framing chip the contributor tapped is what the upload records.**
    ///
    /// The outbox used to carry paths alone, so `APIOutboxTransport` had nothing to send and
    /// labeled every binary `full_tree`. `photos.shot_type` is append-only and drives both the
    /// ghost overlay's reference shot and A3's best photo, so a wrong label is permanent and
    /// visible. This gate follows one non-full-tree photo the whole way: enqueue, close the
    /// database, reopen it, drain, and check what the transport was handed.
    ///
    /// It also covers the upgrade case, which is the one that can lose work rather than mislabel
    /// it: rows written by the previous build are already on disk in the bare-path shape.
    public static func outboxPhotoShotTypes() async throws -> [String] {
        var failures: [String] = []
        let outboxStore = OutboxStore()

        // --- A leaf close-up, across a close and reopen of a real file, and out to the transport.
        do {
            let directory = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("cypress-shot-type-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let databaseURL = directory.appendingPathComponent("cypress.sqlite")

            let photo = OutboxPhoto(path: directory.appendingPathComponent("leaf.jpg").path, shotType: .leaf)
            let visit = Visit(
                treeID: UUID(),
                attribution: OutboxTestSupport.attribution,
                note: "Leaf close-up",
                capturedAt: Date(timeIntervalSince1970: 1_800_000_000)
            )

            // Session one: enqueue and stop, the way a save in a basement ends.
            do {
                let store = try await CypressStore.open(databaseURL: databaseURL, seedURL: nil)
                let queue = OutboxQueue(
                    queue: store.queue,
                    apply: OutboxTestSupport.ScriptedTransport()
                )
                _ = try await queue.enqueue(.visit(visit), photos: [photo])
                // Idempotency is keyed on clientUUID and must not have moved with the payload shape.
                _ = try await queue.enqueue(.visit(visit), photos: [photo])
                let records = try await queue.records()
                expect(records.count == 1, "shot type: a second enqueue made \(records.count) rows", into: &failures)
            }

            // Session two: a different process would see exactly this.
            let store = try await CypressStore.open(databaseURL: databaseURL, seedURL: nil)
            let transport = OutboxTestSupport.ScriptedTransport()
            let queue = OutboxQueue(queue: store.queue, apply: transport)

            guard let reopened = try await queue.records().first else {
                failures.append("shot type: the queued row did not survive a reopen")
                return failures
            }
            expect(
                reopened.item.photos == [photo],
                "shot type: the row came back as \(reopened.item.photos), expected \(photo)",
                into: &failures
            )
            expect(
                reopened.item.clientUUID == visit.clientUUID,
                "shot type: the idempotency key did not survive the reopen",
                into: &failures
            )

            _ = try await queue.drain()
            let offered = await transport.uploadedPhotos
            expect(
                offered == [photo],
                "shot type: the transport was handed \(offered), expected \(photo)",
                into: &failures
            )
            expect(
                offered.first?.shotType != .fullTree,
                "shot type: a leaf close-up was uploaded as a full-tree shot",
                into: &failures
            )
            let settled = try await queue.records().first
            expect(settled?.item.state == .done, "shot type: the row did not settle after its photo went", into: &failures)
            expect(settled?.item.photos.isEmpty == true, "shot type: the uploaded binary was not removed", into: &failures)
        }

        // --- Two binaries on one row: removing the uploaded one must not flatten the survivor.
        do {
            let store = try await CypressStore.inMemory()
            let transport = OutboxTestSupport.ScriptedTransport()
            let queue = OutboxQueue(queue: store.queue, apply: transport)
            let trunk = OutboxPhoto(path: "/tmp/cypress-trunk.jpg", shotType: .trunk)
            let leaf = OutboxPhoto(path: "/tmp/cypress-leaf.jpg", shotType: .leaf)
            let item = try await queue.enqueue(
                .visit(Visit(treeID: UUID(), attribution: OutboxTestSupport.attribution, capturedAt: Date())),
                photos: [trunk, leaf]
            )
            try await store.queue.write { connection in
                try outboxStore.removePhoto(atPath: trunk.path, from: item.id, at: Date(), connection: connection)
            }
            let remaining = try await queue.records().first?.item.photos
            expect(
                remaining == [leaf],
                "shot type: after one upload the row holds \(String(describing: remaining)), expected \(leaf)",
                into: &failures
            )
        }

        // --- The upgrade. A row written by the previous build, in a v1 database, then migrated.
        do {
            let connection = try SQLiteConnection(path: ":memory:")
            _ = try SchemaMigrator.migrate(AppSchema.migrations.filter { $0.version <= 1 }, on: connection)

            let now = SQLiteTimestamp.string(from: Date(timeIntervalSince1970: 1_800_000_000))
            let clientUUID = UUID().uuidString
            try connection.execute("""
                INSERT INTO outbox (id, kind, client_uuid, payload, photo_paths, state, json_synced,
                    window_started_at, created_at, updated_at)
                VALUES ('\(UUID().uuidString)','visit','\(clientUUID)','{}',
                    '["/tmp/old-a.jpg","/tmp/old-b.jpg"]','pending',0,'\(now)','\(now)','\(now)')
                """)

            // Every step above v1, not literally `[2]`: this gate is about the shot-type rewrite
            // surviving an upgrade, and it must not fail the day an unrelated migration is added.
            let expected = AppSchema.migrations.map(\.version).filter { $0 > 1 }
            let applied = try SchemaMigrator.migrate(AppSchema.migrations, on: connection)
            expect(
                applied == expected,
                "upgrade: migrating a v1 database applied \(applied), expected \(expected)",
                into: &failures
            )

            let rows = try outboxStore.allItems(connection: connection)
            expect(rows.count == 1, "upgrade: \(rows.count) rows survived the migration, expected 1", into: &failures)
            expect(
                rows.first?.item.photos.map(\.path) == ["/tmp/old-a.jpg", "/tmp/old-b.jpg"],
                "upgrade: the pending binaries were lost: \(String(describing: rows.first?.item.photos))",
                into: &failures
            )
            expect(
                rows.first?.item.photos.allSatisfy { $0.shotType == .other } == true,
                "upgrade: an old row was labeled \(String(describing: rows.first?.item.photos.map(\.shotType)))",
                into: &failures
            )
            expect(
                rows.first?.item.clientUUID == UUID(uuidString: clientUUID),
                "upgrade: the migration moved the idempotency key",
                into: &failures
            )

            // Replaying the migration must not move the binaries a second time.
            //
            // **This replays v18 rather than v2, because v2 can no longer run here.** v2 rewrote
            // `outbox.photo_paths`, and v18 dropped that column when it turned each binary into a
            // row; replaying v2 against a fully migrated database is not a weaker version of this
            // check, it is a statement error. What the check is actually for — a migration that
            // runs twice must not duplicate what it moved — is now v18's to answer, and its guard
            // is the `outbox_photos` table already existing.
            let stored = try stagedBinariesFingerprint(connection: connection)
            try AppSchema.migrations.first(where: { $0.version == 18 })?.migrate(connection)
            let afterReplay = try stagedBinariesFingerprint(connection: connection)
            expect(
                stored == afterReplay,
                "upgrade: replaying the migration changed the staged binaries: \(stored) then \(afterReplay)",
                into: &failures
            )

            // RULINGS **R77**: a binary the migration carried over was staged by a build with no
            // send path, so it stays on this device permanently. Every row v18 writes is
            // `sendable = 0`, and this is the assertion that says so — without it the migration
            // would be a silent retroactive upload of pre-existing photographs, which is the one
            // thing R77 names and forbids.
            let sendable = try connection.prepare(
                "SELECT COUNT(*) AS n FROM outbox_photos WHERE sendable = 1"
            )
            defer { sendable.finalize() }
            let sendableCount = try sendable.fetchOne { try $0.int("n") } ?? -1
            expect(
                sendableCount == 0,
                "upgrade: \(sendableCount) migrated binaries were marked sendable; R77 keeps them on device",
                into: &failures
            )
        }

        return failures
    }

    /// Every staged binary as one string, ordered, for the migration's replay check.
    ///
    /// Replaced `storedPhotoPathsJSON` when `AppSchema` v18 moved the binaries out of
    /// `outbox.photo_paths` and into rows. `ORDER BY` is not decoration: without it two runs could
    /// return the same rows in different orders and the check would fail on nothing.
    private static func stagedBinariesFingerprint(connection: SQLiteConnection) throws -> String {
        let statement = try connection.prepare("""
            SELECT group_concat(line, '|') AS j FROM (
                SELECT outbox_id || ':' || COALESCE(path, '-') || ':' || shot_type || ':' || sendable AS line
                  FROM outbox_photos ORDER BY outbox_id, path
            )
            """)
        defer { statement.finalize() }
        return try statement.fetchOne { try $0.stringIfPresent("j") ?? "" } ?? ""
    }

    // MARK: - Gate 2: the seed contract

    /// **The seed database's schema and row invariants are pinned; a diff fails the test.**
    ///
    /// Also pins the query plans, because a plan that silently degrades to `SCAN trees` is a
    /// 195,309-row table scan on the map's critical path — a contract break that a correctness-only
    /// test would pass.
    /// Every attached inventory holding a `trees.uuid` that is not its own lower case, by pack id.
    ///
    /// **The property three joins now depend on for their plan.** `trees.uuid` is `NOT NULL
    /// UNIQUE`, so its index is BINARY; the app stores Foundation's uppercase canonical string in
    /// `main`; and the only comparison that both matches and seeks is `t.uuid = lower(<the app's
    /// value>)`. That is sound exactly while every file stores uuids lower case —
    /// `GroveQueries.treeJoin` and `TreeQueries.identityMatch` carry the argument, and this is where
    /// it stops being an assumption. A file that broke it would not be slow, it would be **empty**:
    /// the join matches nothing, the Grove shows no species and no trees, and the tree profile
    /// cannot be opened. That is a failure the gate has to catch before a reader does.
    ///
    /// **Per file, and it has to be** — for the reason `MapQueryPlanTests.armsWithoutStatistics`
    /// gives about statistics, plus one of its own: a downloaded pack's rows reach these joins
    /// exactly as the bundle's do, and a bundled arm that is shadowed for an id space does not even
    /// present its rows through `temp.trees`. Asked of the arm, the question is about the published
    /// file, which is what the property belongs to.
    ///
    /// `EXISTS` rather than `COUNT(*)`: the answer is a bit, and on a healthy file SQLite stops at
    /// the first row that satisfies nothing rather than walking a million.
    public static func armsWithUppercaseUUIDs(_ store: CypressStore) async throws -> [String] {
        let arms = store.inventory?.arms ?? []
        return try await store.queue.read { connection in
            try arms.compactMap { arm -> String? in
                let column = arm.schema.treeIdentityColumn
                let statement = try connection.cachedStatement("""
                SELECT EXISTS(
                    SELECT 1 FROM \(arm.schemaName).trees
                     WHERE \(column) <> lower(\(column))
                ) AS present
                """)
                return (try statement.fetchOne { try $0.bool("present") } ?? false) ? arm.id : nil
            }
        }
    }

    public static func seedContract(seedURL: URL) async throws -> [String] {
        var failures: [String] = []

        let store = try await CypressStore.inMemory(seedURL: seedURL)
        guard let schema = store.seed else {
            return ["seed contract: no seed attached at \(seedURL.path)"]
        }

        // --- Identity model. Two shapes are recognized and the current one is the INTEGER-PK model.
        expect(
            schema.usesIntegerPrimaryKeys,
            "seed contract: identity columns are \(schema.treeIdentityColumn)/\(schema.speciesIdentityColumn), expected the uuid model",
            into: &failures
        )
        expect(
            schema.rtreeJoinColumn == "id" || schema.rtreeJoinColumn == "rt_id",
            "seed contract: unrecognized rtree join column '\(schema.rtreeJoinColumn)'",
            into: &failures
        )

        // --- Every inventory file is attached read-only. `mode=ro&immutable=1` makes that a
        // property of the connection rather than a promise in a comment: no DAO bug can corrupt a
        // city inventory, and no `-wal`/`-shm` sidecar is attempted next to a file inside a
        // read-only app bundle.
        //
        // **Written against each arm rather than against `temp.trees`, and that is the whole
        // point.** The union presents the inventory as a view, and SQLite refuses a write to a view
        // whatever the files behind it permit — `cannot modify trees because it is a view`. Aimed
        // at the view, this gate would stay green with every arm opened read-write, which is the
        // failure it exists to catch. So it is aimed at the files.
        expect(
            !(store.inventory?.arms ?? []).isEmpty,
            "seed contract: no inventory is attached, so the read-only check tested nothing",
            into: &failures
        )
        for arm in store.inventory?.arms ?? [] {
            do {
                try await store.queue.withConnection { connection in
                    try connection.execute(
                        "UPDATE \(arm.schemaName).trees SET status = 'removed' WHERE 1 = 0"
                    )
                }
                failures.append(
                    "seed contract: inventory '\(arm.id)' accepted a write; it is not read-only"
                )
            } catch {
                // expected
            }
        }

        // --- Tables, columns, and the build receipt.
        try await store.queue.read { connection in
            for table in ["trees", "species", "neighborhoods", "trees_rtree", "species_assertions", "seed_meta"] {
                expect(
                    try connection.tableExists(table, in: SeedDatabase.schemaName),
                    "seed contract: missing table seed.\(table)",
                    into: &failures
                )
            }

            let treeColumns = Set(try connection.columnNames(ofTable: "trees", in: SeedDatabase.schemaName))
            let requiredTreeColumns: Set<String> = [
                "id", "uuid", "external_ref", "source", "lat", "lon", "address", "site_type",
                "neighborhood_id", "status", "species_current", "planted_year",
                "dbh_city_cm_min", "dbh_city_cm_max", "site_lineage", "verification_state",
                "created_at", "updated_at", "deleted_at"
            ]
            let missing = requiredTreeColumns.subtracting(treeColumns)
            expect(missing.isEmpty, "seed contract: seed.trees is missing \(missing.sorted())", into: &failures)

            let speciesColumns = Set(try connection.columnNames(ofTable: "species", in: SeedDatabase.schemaName))
            let requiredSpeciesColumns: Set<String> = [
                "id", "uuid", "scientific_name", "common_name", "family", "leaf_retention",
                "id_tips", "seasonal", "care_notes", "curated", "created_at", "updated_at", "deleted_at"
            ]
            let missingSpecies = requiredSpeciesColumns.subtracting(speciesColumns)
            expect(missingSpecies.isEmpty, "seed contract: seed.species is missing \(missingSpecies.sorted())", into: &failures)
        }

        // --- Row invariants, checked against the generator's own receipt so a rebuild that changes
        // the corpus updates both halves together or fails.
        let meta = try await store.queue.read { connection -> [String: String] in
            let statement = try connection.prepare("SELECT key, value FROM \(SeedDatabase.schemaName).seed_meta")
            defer { statement.finalize() }
            let rows = try statement.fetchAll { (try $0.string("key"), try $0.string("value")) }
            return Dictionary(uniqueKeysWithValues: rows)
        }

        func count(_ sql: String) async throws -> Int {
            try await store.queue.read { connection -> Int in
                let statement = try connection.prepare(sql)
                defer { statement.finalize() }
                return try statement.fetchOne { try $0.int("n") } ?? -1
            }
        }

        let treeCount = try await count("SELECT COUNT(*) AS n FROM \(SeedDatabase.schemaName).trees")
        let speciesCount = try await count("SELECT COUNT(*) AS n FROM \(SeedDatabase.schemaName).species")
        let rtreeCount = try await count("SELECT COUNT(*) AS n FROM \(SeedDatabase.schemaName).trees_rtree")

        expect(
            String(treeCount) == meta["rows_kept"],
            "seed contract: \(treeCount) trees but seed_meta.rows_kept is \(meta["rows_kept"] ?? "absent")",
            into: &failures
        )
        expect(
            String(speciesCount) == meta["species_count"],
            "seed contract: \(speciesCount) species but seed_meta.species_count is \(meta["species_count"] ?? "absent")",
            into: &failures
        )
        expect(
            rtreeCount == treeCount,
            "seed contract: the R*Tree holds \(rtreeCount) rectangles for \(treeCount) trees",
            into: &failures
        )
        expect(
            meta["schema_contract"] == "Fixtures/seed/schema.sql",
            "seed contract: the receipt does not name the schema contract file",
            into: &failures
        )

        // Every tree joins to exactly one rectangle — **asked of each inventory FILE, arm by arm.**
        //
        // Written against `temp.trees` this is quadratic and does not finish: the union's
        // `trees_rtree` is a view over the arms' virtual tables, so `NOT EXISTS (… r.id = t.id)`
        // has no index to seek and scans the whole rtree view once per tree row. Against the
        // shipped seed that is 198,625² page reads, which presents as a 99 %-CPU hang in the unit
        // suite rather than as a slow test. Aimed at the arm, each `r.id` lookup is the rtree's own
        // integer primary key again.
        //
        // It is also the more honest question: the invariant belongs to a published file, and a
        // file that satisfies it does not stop satisfying it because another one was attached.
        for arm in store.inventory?.arms ?? [] {
            let orphaned = try await count("""
                SELECT COUNT(*) AS n FROM \(arm.schemaName).trees t
                 WHERE NOT EXISTS (
                     SELECT 1 FROM \(arm.schemaName).trees_rtree r
                      WHERE r.id = t.\(arm.schema.rtreeJoinColumn)
                 )
                """)
            expect(
                orphaned == 0,
                "seed contract: \(orphaned) trees in '\(arm.id)' have no R*Tree rectangle",
                into: &failures
            )
        }

        // Identity is present, unique, and parses as a UUID.
        let badUUIDs = try await count("""
            SELECT COUNT(*) AS n FROM \(SeedDatabase.schemaName).trees
             WHERE uuid IS NULL OR LENGTH(uuid) <> 36
            """)
        expect(badUUIDs == 0, "seed contract: \(badUUIDs) trees have a malformed uuid", into: &failures)

        // …and is stored in **lower case**, which is a query-plan contract and not a spelling
        // preference. See `armsWithUppercaseUUIDs`.
        let shouty = try await armsWithUppercaseUUIDs(store)
        expect(
            shouty.isEmpty,
            """
            seed contract: \(shouty) store trees.uuid in something other than lower case, so \
            GroveQueries' and TreeQueries' `lower()` joins would match none of their rows — an \
            empty Grove and an unreachable tree profile, not a slow one
            """,
            into: &failures
        )

        // Coordinates are inside their own city's declared bbox.
        //
        // **The box belongs to the id space, not to the file.** This used to be San Francisco's box
        // applied to every row, which was right while every row was San Francisco's and became a
        // hard failure for all 52,788 San Jose rows the moment a second city landed — one of them
        // being San Jose's own `SJ_BBOX` in `Tools/build_seed.py`, where `accepts()` already
        // enforces it. A gate that rejected the correct outcome is a gate that would have been
        // "fixed" by widening it to hold both cities, which is how a bbox check stops catching
        // state-plane leakage and null island at all.
        //
        // **New York arrived, and this table is the conscious act the check above demands.** The
        // `unboxed` assertion below is not a formality: when the s17 seed landed it reported all
        // 898,643 New York rows as unchecked, which is the gate working. What it is NOT is evidence
        // of a data gap — the rows carry good coordinates, `Tools/build_seed.py` already holds
        // `NYC_BBOX` and `accepts()` already rejected against it at ingest (`dropped_out_of_bbox`
        // is 0), and the seed carries no per-region box for this to have read instead: `dim_region`
        // has no bbox column, and the manifest's per-borough boxes are computed at publish time.
        // The three boxes below are `Tools/build_seed.py`'s `BBOX_BY_ID_SPACE` verbatim, which is
        // where SF's and San Jose's came from too; copying the seed's own observed min/max instead
        // would make this check compare the data against itself and stop catching anything.
        let boxes: [(space: String, minLat: Double, maxLat: Double, minLon: Double, maxLon: Double)] = [
            ("sf", 37.69, 37.85, -122.54, -122.33),
            ("us-ca-sj", 37.10, 37.50, -122.10, -121.65),
            ("us-ny-nyc", 40.45, 40.95, -74.30, -73.65)
        ]
        if schema.hasIdSpace {
            for box in boxes {
                let outOfBounds = try await count("""
                    SELECT COUNT(*) AS n FROM \(SeedDatabase.schemaName).trees
                     WHERE id_space = '\(box.space)'
                       AND (lat NOT BETWEEN \(box.minLat) AND \(box.maxLat)
                            OR lon NOT BETWEEN \(box.minLon) AND \(box.maxLon))
                    """)
                expect(
                    outOfBounds == 0,
                    "seed contract: \(outOfBounds) trees in id space '\(box.space)' are outside its bbox",
                    into: &failures
                )
            }
            // And no row is in a space this gate has no box for, so a third city cannot arrive
            // unchecked by being unrecognized.
            let unboxed = try await count("""
                SELECT COUNT(*) AS n FROM \(SeedDatabase.schemaName).trees
                 WHERE id_space NOT IN (\(boxes.map { "'\($0.space)'" }.joined(separator: ",")))
                """)
            expect(unboxed == 0, "seed contract: \(unboxed) trees are in an id space with no bounding box to check", into: &failures)
        } else {
            let outOfBounds = try await count("""
                SELECT COUNT(*) AS n FROM \(SeedDatabase.schemaName).trees
                 WHERE lat NOT BETWEEN 37.69 AND 37.85 OR lon NOT BETWEEN -122.54 AND -122.33
                """)
            expect(outOfBounds == 0, "seed contract: \(outOfBounds) trees are outside the SF bbox", into: &failures)
        }

        // Enumerated columns hold only vocabulary values.
        let badStatus = try await count("""
            SELECT COUNT(*) AS n FROM \(SeedDatabase.schemaName).trees
             WHERE status NOT IN ('alive','declining','dead_reported','removed','vacant_site')
            """)
        expect(badStatus == 0, "seed contract: \(badStatus) trees have a status outside the vocabulary", into: &failures)

        let badVerification = try await count("""
            SELECT COUNT(*) AS n FROM \(SeedDatabase.schemaName).trees
             WHERE verification_state NOT IN ('unverified','org_verified','city_record')
            """)
        expect(badVerification == 0, "seed contract: \(badVerification) trees have an unknown verification_state", into: &failures)

        // The DBH bucket is a range or nothing; never half a range.
        let halfRanges = try await count("""
            SELECT COUNT(*) AS n FROM \(SeedDatabase.schemaName).trees
             WHERE (dbh_city_cm_min IS NULL) <> (dbh_city_cm_max IS NULL)
            """)
        expect(halfRanges == 0, "seed contract: \(halfRanges) trees carry half a DBH range", into: &failures)

        // D5 / BUILD-PLAN §13: no evergreen species carrying fall_color_months.
        let evergreensWithFallColor = try await count("""
            SELECT COUNT(*) AS n FROM \(SeedDatabase.schemaName).species
             WHERE leaf_retention = 'evergreen'
               AND json_array_length(COALESCE(json_extract(seasonal, '$.fall_color_months'), '[]')) > 0
            """)
        expect(
            evergreensWithFallColor == 0,
            "seed contract: \(evergreensWithFallColor) evergreen species carry fall_color_months (D5)",
            into: &failures
        )

        // Species assertions point at real rows — **arm by arm, for the reason the R*Tree check
        // above gives at length**: through the union's views neither `t.id` nor `s.id` has an
        // index to seek, so each of the 173,538 assertions would scan 198,625 trees. Against the
        // files it is two integer-primary-key lookups per row, which is what it always was.
        for arm in store.inventory?.arms ?? [] {
            let dangling = try await count("""
                SELECT COUNT(*) AS n FROM \(arm.schemaName).species_assertions a
                 WHERE NOT EXISTS (
                     SELECT 1 FROM \(arm.schemaName).trees t WHERE t.id = a.tree_id
                 )
                    OR NOT EXISTS (
                     SELECT 1 FROM \(arm.schemaName).species s WHERE s.id = a.species_id
                 )
                """)
            expect(
                dangling == 0,
                "seed contract: \(dangling) species assertions dangle in '\(arm.id)'",
                into: &failures
            )
        }

        // --- Query plans. Every hot query must resolve through an index.
        let queries = TreeQueries(schema: schema, seedHasSoftDeletedTrees: store.seedHasSoftDeletedTrees)
        let bounds = BoundingBox(minLatitude: 37.770, maxLatitude: 37.775, minLongitude: -122.450, maxLongitude: -122.440)

        try await store.queue.read { connection in
            let plans: [(String, String, String)] = [
                (
                    "viewport pins",
                    """
                    SELECT t.uuid, t.lat, t.lon FROM \(SeedDatabase.schemaName).trees t
                     WHERE t.lat BETWEEN 37.77 AND 37.775 AND t.lon BETWEEN -122.45 AND -122.44
                       AND t.deleted_at IS NULL LIMIT 2000
                    """,
                    "idx_trees_lat_lon"
                ),
                (
                    // **`trees_geo`, because that is the relation a clustered viewport reads.**
                    // The union's full `trees` carries `species_current` and a neighborhood id,
                    // and a compound view's width is paid per row — SQLite materializes it as a
                    // co-routine and does not prune columns the outer query never asks for — so
                    // the covering index is lost the moment this reads the wide view.
                    // `TreeQueries.geometrySource` is where the app makes the same choice, and
                    // `MapQueryPlanTests` explains the SQL it actually emits rather than this
                    // paraphrase of it (ERRATA E130).
                    "viewport clusters",
                    """
                    SELECT CAST((t.lat + 90.0) / 0.002 AS INTEGER) cy, COUNT(*) n
                      FROM \(SeedDatabase.schemaName).trees_geo t
                     WHERE t.lat BETWEEN 37.69 AND 37.85 AND t.lon BETWEEN -122.54 AND -122.33
                     GROUP BY cy
                    """,
                    "COVERING INDEX idx_trees_lat_lon"
                ),
                (
                    "tree profile",
                    "SELECT t.id FROM \(SeedDatabase.schemaName).trees t WHERE t.uuid = 'x'",
                    "sqlite_autoindex_trees_1"
                ),
                (
                    "species by uuid",
                    "SELECT s.id FROM \(SeedDatabase.schemaName).species s WHERE s.uuid = 'x'",
                    "sqlite_autoindex_species_1"
                ),
                (
                    "species by scientific name prefix",
                    "SELECT id FROM \(SeedDatabase.schemaName).species WHERE scientific_name >= 'Q' AND scientific_name < 'R'",
                    "idx_species_scientific_name"
                ),
                (
                    "species by common name prefix",
                    "SELECT id FROM \(SeedDatabase.schemaName).species WHERE common_name >= 'Q' AND common_name < 'R'",
                    "idx_species_common_name"
                )
            ]

            for (label, sql, expectedIndex) in plans {
                let steps = try connection.queryPlan(for: sql)
                let plan = steps.joined(separator: " | ")
                expect(
                    plan.contains(expectedIndex),
                    "query plan (\(label)) does not use \(expectedIndex): \(plan)",
                    into: &failures
                )
                // A `SCAN` step is only acceptable when it walks an index that answers the query
                // outright. A bare `SCAN trees` is 195,309 rows on the map's critical path.
                let tableScans = steps.filter {
                    $0.contains("SCAN") && !$0.contains("COVERING INDEX") && !$0.contains("VIRTUAL TABLE")
                }
                expect(
                    tableScans.isEmpty,
                    "query plan (\(label)) degraded to a table scan: \(tableScans.joined(separator: " | "))",
                    into: &failures
                )
            }
        }

        // --- The R*Tree is a conservative pre-filter, and the exact re-check is what makes it
        // correct. Both strategies must return the same set.
        try await store.queue.read { connection in
            let viewport = MapViewport(bounds: bounds, zoom: 17)
            let viaIndex = try queries.pins(in: viewport, strategy: .coveringIndex, connection: connection)
            let viaRTree = try queries.pins(in: viewport, strategy: .rtreePrefilter, connection: connection)
            expect(
                Set(viaIndex.map(\.id)) == Set(viaRTree.map(\.id)),
                "spatial strategies disagree: \(viaIndex.count) via the covering index, \(viaRTree.count) via the R*Tree",
                into: &failures
            )
            expect(!viaIndex.isEmpty, "spatial strategies: the test viewport returned nothing", into: &failures)

            // …and the drift is real, not theoretical: without the re-check the R*Tree returns
            // strictly more rows, because it stores float32 and rounds outward.
            let unchecked = try connection.prepare("""
                SELECT COUNT(*) AS n
                  FROM \(SeedDatabase.schemaName).trees_rtree r
                  JOIN \(SeedDatabase.schemaName).trees t
                    ON t.inv = r.inv AND t.local_id = r.id
                 WHERE r.max_lat >= :minLat AND r.min_lat <= :maxLat
                   AND r.max_lon >= :minLon AND r.min_lon <= :maxLon
                   AND t.deleted_at IS NULL
                """)
            defer { unchecked.finalize() }
            _ = try unchecked.bind([
                ":minLat": bounds.minLatitude, ":maxLat": bounds.maxLatitude,
                ":minLon": bounds.minLongitude, ":maxLon": bounds.maxLongitude
            ])
            let uncheckedCount = try unchecked.fetchOne { try $0.int("n") } ?? -1
            expect(
                uncheckedCount >= viaRTree.count,
                "R*Tree pre-filter returned fewer rows (\(uncheckedCount)) than the exact answer (\(viaRTree.count)); it is supposed to be conservative",
                into: &failures
            )
        }

        // --- A1: clusters at zoom ≤ 15, individual pins at zoom ≥ 16.
        try await store.queue.read { connection in
            let clustered = try queries.mapContent(in: MapViewport(bounds: bounds, zoom: 15), connection: connection)
            let pinned = try queries.mapContent(in: MapViewport(bounds: bounds, zoom: 16), connection: connection)
            if case .pins = clustered { failures.append("A1: zoom 15 returned individual pins") }
            if case .clusters = pinned { failures.append("A1: zoom 16 returned clusters") }
            expect(clustered.pinCount == pinned.pinCount, "A1: the two zooms disagree on how many trees are in view", into: &failures)
        }

        // --- Nearest-N is ordered by true distance and stays inside the radius.
        try await store.queue.read { connection in
            let center = Coordinate(latitude: 37.7761, longitude: -122.4464)
            let nearby = try queries.nearest(to: center, radiusM: 120, limit: 8, connection: connection)
            expect(!nearby.isEmpty, "nearest-N: nothing found near a known-dense corner of SF", into: &failures)
            expect(nearby.count <= 8, "nearest-N: returned \(nearby.count) rows for limit 8", into: &failures)
            let distances = nearby.map(\.distanceM)
            expect(distances == distances.sorted(), "nearest-N: results are not ordered by distance", into: &failures)
            expect(
                zip(nearby, distances).allSatisfy { abs(center.distance(to: $0.0.tree.coordinate) - $0.1) < 0.001 },
                "nearest-N: the reported distance is not the great-circle distance",
                into: &failures
            )
        }

        // --- Profile and species lookup round-trip through the domain types.
        let sampleUUID = try await store.queue.read { connection -> UUID? in
            let statement = try connection.prepare(
                "SELECT uuid FROM \(SeedDatabase.schemaName).trees WHERE species_current IS NOT NULL LIMIT 1"
            )
            defer { statement.finalize() }
            return try statement.fetchOne { try $0.uuid("uuid") }
        }
        if let sampleUUID {
            let record = try await store.queue.read { connection in
                try queries.tree(id: sampleUUID, connection: connection)
            }
            expect(record != nil, "profile: seed.trees.uuid \(sampleUUID) did not resolve", into: &failures)
            expect(record?.tree.id == sampleUUID, "profile: resolved the wrong tree", into: &failures)
            expect(record?.tree.source == .cityImport, "profile: seeded tree is not a city import", into: &failures)
            expect(record?.species != nil, "profile: a tree with species_current resolved no species", into: &failures)
            expect(record?.neighborhoodName?.isEmpty == false, "profile: no neighborhood name", into: &failures)
        } else {
            failures.append("profile: no seeded tree carries a species")
        }

        let speciesQueries = SpeciesQueries(schema: schema)
        let matches = try await store.queue.read { connection in
            try speciesQueries.search(query: "Quercus", limit: 25, connection: connection)
        }
        expect(!matches.isEmpty, "species search: 'Quercus' matched nothing in a 569-species seed", into: &failures)
        expect(
            matches.allSatisfy {
                $0.scientificName.lowercased().contains("quercus") || $0.commonName.lowercased().contains("quercus")
            },
            "species search: a match contains the query in neither name",
            into: &failures
        )
        // `contains`, not `hasPrefix`: the search matches a word anywhere in either name, so "oak"
        // reaches `Coast Live Oak` (task #108). The rank that keeps a head match above an interior
        // one is asserted in `SpeciesSearchTests`, which can name the expected order; this gate is
        // only here to catch a search that returns something unrelated at all.

        // --- The species content pipeline (BUILD-PLAN §8) has run, and its coverage is pinned to
        // the build receipt rather than to a literal, so a content rebuild updates both halves at
        // once. `unknown` is not a shortfall to be closed: those species have no authoritative
        // source for their habit and the app renders no phenology for them (ERRATA E9).
        let withLeafRetention = try await count("""
            SELECT COUNT(*) AS n FROM \(SeedDatabase.schemaName).species WHERE leaf_retention IS NOT NULL
            """)
        let curated = try await count("SELECT COUNT(*) AS n FROM \(SeedDatabase.schemaName).species WHERE curated = 1")
        expect(
            String(withLeafRetention) == meta["species_with_leaf_retention"],
            "seed contract: \(withLeafRetention) species carry leaf_retention but seed_meta says \(meta["species_with_leaf_retention"] ?? "absent")",
            into: &failures
        )
        expect(
            String(curated) == meta["species_curated"],
            "seed contract: \(curated) curated species but seed_meta says \(meta["species_curated"] ?? "absent")",
            into: &failures
        )

        // --- Every value in the column is one the enum knows, so nothing decodes to `nil` by
        // accident. `SpeciesQueries.leafRetention` maps an unknown string to `nil`, which would
        // silently look exactly like the honest unknown state.
        let unrecognized = try await count("""
            SELECT COUNT(*) AS n FROM \(SeedDatabase.schemaName).species
             WHERE leaf_retention IS NOT NULL
               AND leaf_retention NOT IN ('evergreen','deciduous','semi_deciduous')
            """)
        expect(
            unrecognized == 0,
            "seed contract: \(unrecognized) species carry a leaf_retention outside the enum",
            into: &failures
        )

        // --- D5 in the shipped file, not just in the CHECK that wrote it (DECISIONS §3.14). The
        // `IS 'evergreen'` form is null-safe, so an unknown habit is untouched by this rule.
        let d5Violations = try await count("""
            SELECT COUNT(*) AS n FROM \(SeedDatabase.schemaName).species
             WHERE leaf_retention IS 'evergreen'
               AND json_array_length(COALESCE(json_extract(seasonal, '$.fall_color_months'), '[]')) > 0
            """)
        expect(
            d5Violations == 0,
            "seed contract: \(d5Violations) evergreen species carry fall_color_months (D5)",
            into: &failures
        )

        // --- A tree whose city record names no taxon carries no species at all, so it cannot
        // inherit a real species' phenology, autumn color or field guide.
        let nonTaxonWithSpecies = try await count("""
            SELECT COUNT(*) AS n FROM \(SeedDatabase.schemaName).species_map
             WHERE is_non_taxon = 1 AND species_id IS NOT NULL
            """)
        expect(
            nonTaxonWithSpecies == 0,
            "seed contract: \(nonTaxonWithSpecies) qSpecies strings that name no taxon still map to a species",
            into: &failures
        )

        // --- #95: no column the app matches on holds two spellings of one value.
        //
        // `plant_type` held 'Tree' 194,988 times and 'tree' 3 times (TreeIDs 253212, 253634, 96598),
        // so every `WHERE plant_type = 'Tree'` in the product silently dropped three rows and every
        // reader had to remember to case-fold. `Tools/build_seed.py` now folds these columns at
        // ingest; this is the assertion that makes a future source change fail here rather than hide.
        //
        // The column list is read from the seed's own receipt rather than written out here, so the
        // generator and the gate cannot drift: adding a column to `NORMALISED_SEED_COLUMNS` extends
        // this check by rebuilding, and removing one from the normalizer without removing it from
        // the receipt fails immediately.
        //
        // **Deliberately not every column.** `address` (2,277 case-variant groups), `plot_size` (61)
        // and `permit_notes` (2) are free text that is shown as the city wrote it and never compared
        // against a literal, and one of `McAllister St` / `MCALLISTER ST` is a real spelling of that
        // street. Folding those would be editing the city's record; folding a closed vocabulary is
        // repairing a filter. The line between them is "does any code compare this to a string".
        let treeColumnNames = try await store.queue.read { connection in
            Set(try connection.columnNames(ofTable: "trees", in: SeedDatabase.schemaName))
        }
        // The key is British because the *published seed file* spells it that way: it is written by
        // `Tools/build_seed.py` and is already shipped, so it is not this repo's to correct (#140,
        // and the allowlist in `BritishSpellingGuardTests`). Named once and interpolated wherever it
        // is spoken about, so there is one British spelling here rather than one per sentence.
        let normalizedColumnsKey = "case_normalised_columns"
        let normalizedColumns = (meta[normalizedColumnsKey] ?? "")
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        expect(
            !normalizedColumns.isEmpty,
            "seed contract: seed_meta.\(normalizedColumnsKey) is absent, so #95's assertion would "
                + "silently check nothing",
            into: &failures
        )
        for column in normalizedColumns {
            guard treeColumnNames.contains(column) else {
                failures.append("seed contract: seed_meta names '\(column)' as case-normalized but "
                    + "seed.trees has no such column")
                continue
            }
            let collisions = try await count("""
                SELECT COUNT(*) AS n FROM (
                    SELECT 1 FROM (
                        SELECT DISTINCT \(column) AS v FROM \(SeedDatabase.schemaName).trees
                         WHERE \(column) IS NOT NULL
                    )
                    GROUP BY LOWER(TRIM(v)) HAVING COUNT(*) > 1
                )
                """)
            expect(
                collisions == 0,
                "seed contract (#95): trees.\(column) holds \(collisions) value(s) spelled two ways, "
                    + "so a `WHERE \(column) = '…'` in the app drops rows it should match",
                into: &failures
            )
        }

        // --- Provenance. The seed says which of San Francisco's two street-tree inventories it is,
        // and what day that inventory was read.
        //
        // This is the assertion that keeps "is our data stale?" answerable. It was not answerable
        // before #91: the bundle carried 195,309 rows and not one byte saying where they came from
        // or when, so the question could only be settled by re-downloading the source and diffing.
        // A seed that ships without a dated source is the defect, not an untidiness.
        expect(
            InventorySource(seedMeta: meta) != nil,
            "seed contract: the build receipt names no inventory (seed_meta.trees_source), so "
                + "nothing in the app can say where its records came from",
            into: &failures
        )
        if let provenance = InventorySource(seedMeta: meta) {
            expect(
                provenance.snapshotDate != nil,
                "seed contract: seed_meta.trees_snapshot_on is "
                    + "'\(meta["trees_snapshot_on"] ?? "absent")', which is not an ISO calendar day. "
                    + "A snapshot with no date is what made staleness unanswerable last time.",
                into: &failures
            )
            expect(
                !provenance.name.isEmpty && !provenance.url.isEmpty,
                "seed contract: the inventory is named '\(provenance.name)' at '\(provenance.url)'; "
                    + "the tree page prints the name and the receipt keeps the url",
                into: &failures
            )
            // Every row the source offered is accounted for: shipped, or dropped for a reason the
            // receipt names. A seed that lost 40,000 rows to a parse bug and said nothing would
            // otherwise pass every assertion above this one, because they all compare the file
            // against its own receipt and the receipt would have been written by the same bug.
            //
            // **Two passes under `--source city`, and both are counted.** The row set is the city
            // layer's, but that layer publishes no vacant-site category at all, so the seed's empty
            // planting sites are a second read of the DataSF export. Its rows are read, shipped and
            // skipped on exactly the same terms, and a `city` seed whose second pass silently
            // stopped carrying sites would otherwise balance its books without them.
            //
            // **A third pass once a second city is in the file**, on the same terms. San Jose's
            // whole 345,023-record corpus is read and validated; what does not ship is the part
            // outside `SJ_SHIP_WINDOW`, and that count is a *product* decision rather than a data
            // defect — which is why it is named `sj_rows_outside_ship_window` and not folded in
            // with the drops. It still has to appear on this side of the arithmetic, or the books
            // balance only by not mentioning 292,248 rows.
            //
            // Those two figures read 344,879 and 292,091 until the s17 publish re-read the San Jose
            // layer on 2026-08-22. Measured on seed `ac7b1ccc`: `sj_rows_read` 345,023 and
            // `sj_rows_outside_ship_window` 292,248, whose difference is 52,775 — exactly the
            // `us-ca-sj` rows the file holds. A comment stating a count is a claim, and this one had
            // gone stale inside the very block whose job is to check counts.
            //
            // **A fourth pass once New York is in the file**, and adding it here is the same
            // conscious act the bbox table above demands. Left out, this gate reported the s17 seed
            // as reading 492,490 rows and accounting for 1,391,133 — a shortfall of exactly
            // 898,643, which is New York's whole contribution. That is the gate working: it is
            // written so a city cannot arrive unaccounted for, and the arithmetic balances to the
            // row again the moment its pass is named. New York drops nothing — `nyc_rows_read` and
            // `nyc_rows_shipped` are both 898,643 — so it adds a term on this side only.
            let spineRead = meta["source_rows"].flatMap(Int.init) ?? -1
            let read = spineRead
                + (meta["export_vacant_rows_read"].flatMap(Int.init) ?? 0)
                + (meta["sj_rows_read"].flatMap(Int.init) ?? 0)
                + (meta["nyc_rows_read"].flatMap(Int.init) ?? 0)
            let dropped = [
                "dropped_no_coords", "dropped_out_of_bbox", "dropped_dupe_treeid",
                // Read, validated, and deliberately not shipped. See above.
                "sj_rows_outside_ship_window",
                // A site the city's layer lists as a living tree — the one case where the two
                // inventories genuinely contradict each other, and the city wins.
                "export_vacant_sites_excluded_city_lists_tree",
                // A site the city's layer also holds, already shipped by the first pass.
                "export_vacant_sites_already_city_listed"
            ]
                .compactMap { meta[$0].flatMap(Int.init) }
                .reduce(0, +)
            expect(
                read == treeCount + dropped,
                "seed contract: the receipt read \(read) source rows and accounts for "
                    + "\(treeCount) shipped + \(dropped) dropped = \(treeCount + dropped)",
                into: &failures
            )
            // …and the count it read is the count the source said it had. This is the only
            // assertion in this gate that reaches past the build receipt to something the *city*
            // asserted, which is what makes a truncated extract fail rather than pass consistently.
            // The spine's own count, not the two passes together: the number the city's server
            // reported is a claim about the city's layer, and the export's vacant sites are not in
            // it.
            if let claimed = meta["trees_source_feature_count"].flatMap(Int.init) {
                expect(
                    spineRead == claimed,
                    "seed contract: the source reported \(claimed) records and the build read "
                        + "\(spineRead); the extract is incomplete",
                    into: &failures
                )
            }
        }

        // --- Per-row provenance. Every row names an inventory, and every inventory it names is one
        // the receipt can describe.
        //
        // **This is the gate that keeps the provenance sentence from being fiction.** The shipped
        // seed is built from two inventories — the city's operational layer for the trees, the
        // DataSF export for the vacant planting sites the layer has no category for — and the app
        // prints one of their names, with one of their snapshot dates, under a record. A row whose
        // `inventory_source` the receipt cannot name would draw either nothing or, if anybody ever
        // made the resolution lenient, the *other* inventory's name over a record it never held.
        if schema.hasInventorySource {
            let named = CypressStore.inventories(in: meta)
            let sources = try await store.queue.read { connection -> [String] in
                let statement = try connection.prepare(
                    "SELECT DISTINCT inventory_source AS v FROM \(SeedDatabase.schemaName).trees"
                )
                defer { statement.finalize() }
                return try statement.fetchAll { try $0.string("v") }
            }
            for source in sources.sorted() {
                expect(
                    named[source] != nil,
                    "seed contract: trees.inventory_source holds '\(source)', which the build "
                        + "receipt does not describe (no inventory_\(source)_name), so no row from "
                        + "it can say where it came from",
                    into: &failures
                )
                expect(
                    named[source]?.snapshotDate != nil,
                    "seed contract: inventory '\(source)' carries no readable snapshot date, so "
                        + "every row from it draws no provenance line at all",
                    into: &failures
                )
            }
        }

        return failures
    }
}
