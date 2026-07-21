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
            await rejects("outbox row marked done with photos pending", """
                INSERT INTO outbox (id, kind, client_uuid, payload, photo_paths, state, json_synced,
                    window_started_at, created_at, updated_at)
                VALUES ('\(UUID().uuidString)','visit','\(UUID().uuidString)','{}',
                    '[{"path":"/tmp/a.jpg","shotType":"trunk"}]','done',1,
                    '\(now)','\(now)','\(now)')
                """)

            // Favourites are tombstoned, never hard-deleted.
            try await store.queue.write { connection in
                try ContributionStore().applyFavoriteToggle(
                    userID: OutboxTestSupport.userID,
                    treeID: UUID(uuidString: tree)!,
                    clientUUID: UUID(),
                    isFavorite: true,
                    at: Date(),
                    connection: connection
                )
            }
            await rejects("hard delete of a favorite", "DELETE FROM favorites")

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
        let queue = OutboxQueue(queue: store.queue, transport: transport, now: clock.closure)
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
            let queue = OutboxQueue(queue: store.queue, transport: transport, now: clock.closure)

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
            expect(record?.jsonSynced == true, "wifi-only: the JSON item did not sync on a metered connection", into: &failures)
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
            let queue = OutboxQueue(queue: store.queue, transport: transport, now: clock.closure)
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
    /// labelled every binary `full_tree`. `photos.shot_type` is append-only and drives both the
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
                    transport: OutboxTestSupport.ScriptedTransport()
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
            let queue = OutboxQueue(queue: store.queue, transport: transport)

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
            let queue = OutboxQueue(queue: store.queue, transport: transport)
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

            var rows = try outboxStore.allItems(connection: connection)
            expect(rows.count == 1, "upgrade: \(rows.count) rows survived the migration, expected 1", into: &failures)
            expect(
                rows.first?.item.photos.map(\.path) == ["/tmp/old-a.jpg", "/tmp/old-b.jpg"],
                "upgrade: the pending binaries were lost: \(String(describing: rows.first?.item.photos))",
                into: &failures
            )
            expect(
                rows.first?.item.photos.allSatisfy { $0.shotType == .other } == true,
                "upgrade: an old row was labelled \(String(describing: rows.first?.item.photos.map(\.shotType)))",
                into: &failures
            )
            expect(
                rows.first?.item.clientUUID == UUID(uuidString: clientUUID),
                "upgrade: the migration moved the idempotency key",
                into: &failures
            )

            // Replaying the migration must not re-wrap what it already wrapped.
            let stored = try storedPhotoPathsJSON(connection: connection)
            try AppSchema.migrations.first(where: { $0.version == 2 })?.migrate(connection)
            let afterReplay = try storedPhotoPathsJSON(connection: connection)
            expect(
                stored == afterReplay,
                "upgrade: replaying the migration changed the column: \(stored) then \(afterReplay)",
                into: &failures
            )

            // And a bare-path row that somehow reaches a migrated database still decodes rather than
            // dropping a contributor's pending visit.
            try connection.execute("""
                INSERT INTO outbox (id, kind, client_uuid, payload, photo_paths, state, json_synced,
                    window_started_at, created_at, updated_at)
                VALUES ('\(UUID().uuidString)','visit','\(UUID().uuidString)','{}',
                    '["/tmp/stray.jpg"]','pending',0,'\(now)','\(now)','\(now)')
                """)
            rows = try outboxStore.allItems(connection: connection)
            expect(rows.count == 2, "upgrade: a bare-path row failed to decode and vanished", into: &failures)
            expect(
                rows.last?.item.photos == [OutboxPhoto(path: "/tmp/stray.jpg", shotType: .other)],
                "upgrade: a bare-path row decoded as \(String(describing: rows.last?.item.photos))",
                into: &failures
            )
        }

        return failures
    }

    /// The `outbox.photo_paths` column exactly as SQLite holds it, for the migration's replay check.
    private static func storedPhotoPathsJSON(connection: SQLiteConnection) throws -> String {
        let statement = try connection.prepare("SELECT group_concat(photo_paths) AS j FROM outbox")
        defer { statement.finalize() }
        return try statement.fetchOne { try $0.stringIfPresent("j") ?? "" } ?? ""
    }

    // MARK: - Gate 2: the seed contract

    /// **The seed database's schema and row invariants are pinned; a diff fails the test.**
    ///
    /// Also pins the query plans, because a plan that silently degrades to `SCAN trees` is a
    /// 195,309-row table scan on the map's critical path — a contract break that a correctness-only
    /// test would pass.
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

        // --- The seed is attached read-only. `mode=ro&immutable=1` makes that a property of the
        // connection rather than a promise in a comment: no DAO bug can corrupt the city inventory,
        // and no `-wal`/`-shm` sidecar is attempted next to a file inside a read-only app bundle.
        do {
            try await store.queue.withConnection { connection in
                try connection.execute("UPDATE \(SeedDatabase.schemaName).trees SET status = 'removed' WHERE 1 = 0")
            }
            failures.append("seed contract: the attached seed accepted a write; it is not read-only")
        } catch {
            // expected
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

        // Every tree joins to exactly one rectangle.
        let orphanedTrees = try await count("""
            SELECT COUNT(*) AS n FROM \(SeedDatabase.schemaName).trees t
             WHERE NOT EXISTS (SELECT 1 FROM \(SeedDatabase.schemaName).trees_rtree r WHERE r.id = t.\(schema.rtreeJoinColumn))
            """)
        expect(orphanedTrees == 0, "seed contract: \(orphanedTrees) trees have no R*Tree rectangle", into: &failures)

        // Identity is present, unique, and parses as a UUID.
        let badUUIDs = try await count("""
            SELECT COUNT(*) AS n FROM \(SeedDatabase.schemaName).trees
             WHERE uuid IS NULL OR LENGTH(uuid) <> 36
            """)
        expect(badUUIDs == 0, "seed contract: \(badUUIDs) trees have a malformed uuid", into: &failures)

        // Coordinates are inside the declared SF bbox.
        let outOfBounds = try await count("""
            SELECT COUNT(*) AS n FROM \(SeedDatabase.schemaName).trees
             WHERE lat NOT BETWEEN 37.69 AND 37.85 OR lon NOT BETWEEN -122.54 AND -122.33
            """)
        expect(outOfBounds == 0, "seed contract: \(outOfBounds) trees are outside the SF bbox", into: &failures)

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

        // Species assertions point at real rows.
        let danglingAssertions = try await count("""
            SELECT COUNT(*) AS n FROM \(SeedDatabase.schemaName).species_assertions a
             WHERE NOT EXISTS (SELECT 1 FROM \(SeedDatabase.schemaName).trees t WHERE t.id = a.tree_id)
                OR NOT EXISTS (SELECT 1 FROM \(SeedDatabase.schemaName).species s WHERE s.id = a.species_id)
            """)
        expect(danglingAssertions == 0, "seed contract: \(danglingAssertions) species assertions dangle", into: &failures)

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
                    "viewport clusters",
                    """
                    SELECT CAST((t.lat + 90.0) / 0.002 AS INTEGER) cy, COUNT(*) n
                      FROM \(SeedDatabase.schemaName).trees t
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
                  JOIN \(SeedDatabase.schemaName).trees t ON t.\(schema.rtreeJoinColumn) = r.id
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
            let centre = Coordinate(latitude: 37.7761, longitude: -122.4464)
            let nearby = try queries.nearest(to: centre, radiusM: 120, limit: 8, connection: connection)
            expect(!nearby.isEmpty, "nearest-N: nothing found near a known-dense corner of SF", into: &failures)
            expect(nearby.count <= 8, "nearest-N: returned \(nearby.count) rows for limit 8", into: &failures)
            let distances = nearby.map(\.distanceM)
            expect(distances == distances.sorted(), "nearest-N: results are not ordered by distance", into: &failures)
            expect(
                zip(nearby, distances).allSatisfy { abs(centre.distance(to: $0.0.tree.coordinate) - $0.1) < 0.001 },
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
            expect(record?.neighborhoodName?.isEmpty == false, "profile: no neighbourhood name", into: &failures)
        } else {
            failures.append("profile: no seeded tree carries a species")
        }

        let speciesQueries = SpeciesQueries(schema: schema)
        let matches = try await store.queue.read { connection in
            try speciesQueries.search(query: "Quercus", limit: 25, connection: connection)
        }
        expect(!matches.isEmpty, "species search: 'Quercus' matched nothing in a 569-species seed", into: &failures)
        expect(
            matches.allSatisfy { $0.scientificName.lowercased().hasPrefix("quercus") || $0.commonName.lowercased().hasPrefix("quercus") },
            "species search: a match starts with neither name",
            into: &failures
        )

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
        let unrecognised = try await count("""
            SELECT COUNT(*) AS n FROM \(SeedDatabase.schemaName).species
             WHERE leaf_retention IS NOT NULL
               AND leaf_retention NOT IN ('evergreen','deciduous','semi_deciduous')
            """)
        expect(
            unrecognised == 0,
            "seed contract: \(unrecognised) species carry a leaf_retention outside the enum",
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
        // inherit a real species' phenology, autumn colour or field guide.
        let nonTaxonWithSpecies = try await count("""
            SELECT COUNT(*) AS n FROM \(SeedDatabase.schemaName).species_map
             WHERE is_non_taxon = 1 AND species_id IS NOT NULL
            """)
        expect(
            nonTaxonWithSpecies == 0,
            "seed contract: \(nonTaxonWithSpecies) qSpecies strings that name no taxon still map to a species",
            into: &failures
        )

        return failures
    }
}
