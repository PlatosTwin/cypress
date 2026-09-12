import Foundation
import Testing
@testable import Cypress

/// **What migration v22 does to a database that already has a queue and staged binaries in it.**
///
/// v22 adds `tree_data_disputes` and its two `ON DELETE CASCADE` children, and widens `outbox.kind`
/// to admit `data_dispute` and `data_dispute_withdrawal`. SQLite cannot widen a `CHECK` in place, so
/// the second half is a table rebuild — the sixth this table has had (v4, v15, v17, v18, v21, v22).
///
/// `DataGates.sqliteStore` runs the whole ladder on an **empty** in-memory database and picks up a
/// new version for free: the versions applied, that a second run applies none, that `user_version`
/// matches `currentVersion`, that a replay from 0 is clean, that a database from the future is
/// refused. Every one of those passes on this migration written badly, because every one of them
/// runs against a database with no rows.
///
/// This file is the part that only shows up with rows in it:
///
/// 1. a v21 database with a queue in it reaches 22 by running exactly one step, and 22 is the newest;
/// 2. **the staged binaries survive the rebuild** — `SchemaV21Tests`' whole reason, restated here
///    because this migration performs the same drop and would lose them the same way;
/// 3. the queue is carried across column for column, `seq` order included;
/// 4. the vocabulary really widened, both values, and nothing was swept into the queue while it did;
/// 5. the three new tables are there, and the `field` and `kind` CHECKs admit exactly the fixed
///    vocabularies and refuse anything else;
/// 6. **the cascade this schema's comment warns about is real on this SQLite** — the paragraph in
///    `applyV22` about a future rebuild of `tree_data_disputes` is measured rather than believed.
///
/// ── Calibration ────────────────────────────────────────────────────────────────────────────────
///
/// Every red-proof this suite was checked against is recorded in the PR that added it, with the
/// failure message it produced. The one worth naming here is (2): with `applyV22`'s parking block
/// deleted, `theStagedBinariesSurviveTheRebuild` goes red on the binaries being gone **and** on the
/// counter, and it is asked against `outbox_photos` rather than against the fixture for the reason
/// `SchemaV21Tests` measured — the rebuild copies `photos_outstanding` *before* the drop cascades
/// the children away, so a fixture comparison agrees with a database whose counter and contents
/// disagree. Both comparisons are kept, in opposite directions, exactly as that suite argues.
@Suite("AppSchema · v22")
struct SchemaV22Tests {

    private static let moment = Date(timeIntervalSince1970: 1_795_000_000)

    /// The version this file is about, read from the code rather than written down twice.
    private static var version: Int32 { 22 }

    // MARK: - The fixture

    /// One queued item as it sits in a v21 database, and the binaries it still owes.
    ///
    /// `SchemaV21Tests.QueuedItem`'s shape and its reasoning: every column the rebuild has to carry
    /// gets a distinguishable value, because a fixture with three columns uniformly NULL cannot tell
    /// a copied column from a defaulted one.
    private struct QueuedItem {
        let id: UUID
        let clientUUID: UUID
        let kind: String
        let state: String
        let failCount: Int
        let lastError: String?
        let lastErrorCode: String?
        let nextAttemptAt: Date?
        let remoteSent: Int
        let payload: String
        let photoPaths: String
        let binaries: [UUID]
    }

    private static func fixture() -> [QueuedItem] {
        [
            // A visit with two photographs still staged: the row the cascade destroys.
            QueuedItem(
                id: UUID(), clientUUID: UUID(), kind: "visit", state: "pending",
                failCount: 0, lastError: nil, lastErrorCode: nil, nextAttemptAt: nil,
                remoteSent: 0, payload: #"{"note":"the visit"}"#,
                photoPaths: #"[{"path":"/staged/a.jpg","shotType":"other"}]"#,
                binaries: [UUID(), UUID()]
            ),
            // v21's own kind, in a v21 database — so this fixture could not have been written
            // against v20 by accident, and the copy is proved to carry the newest vocabulary too.
            QueuedItem(
                id: UUID(), clientUUID: UUID(), kind: "measurement_withdrawal", state: "failed",
                failCount: 3, lastError: "the service said no", lastErrorCode: "validation_failed",
                nextAttemptAt: nil, remoteSent: 0, payload: #"{"note":"the withdrawal"}"#,
                photoPaths: "[]", binaries: []
            ),
            // A settled item, and the only row that is `remote_sent`. `done` is only legal with
            // nothing outstanding, which is v1's invariant and the one a mis-copied counter breaks.
            QueuedItem(
                id: UUID(), clientUUID: UUID(), kind: "photo_withdrawal", state: "done",
                failCount: 0, lastError: nil, lastErrorCode: nil, nextAttemptAt: nil,
                remoteSent: 1, payload: #"{"note":"the settled one"}"#, photoPaths: "[]",
                binaries: []
            ),
            // One binary on its own item, so the counter is not uniformly 0 or 2.
            QueuedItem(
                id: UUID(), clientUUID: UUID(), kind: "observation", state: "pending",
                failCount: 1, lastError: nil, lastErrorCode: nil, nextAttemptAt: nil,
                remoteSent: 0, payload: #"{"note":"the observation"}"#, photoPaths: "[]",
                binaries: [UUID()]
            ),
            // The fourth state, and the only row carrying a scheduled retry.
            QueuedItem(
                id: UUID(), clientUUID: UUID(), kind: "measurement", state: "uploading",
                failCount: 2, lastError: "the service was busy", lastErrorCode: "rate_limited",
                nextAttemptAt: moment.addingTimeInterval(900), remoteSent: 0,
                payload: #"{"note":"the one in flight"}"#, photoPaths: "[]", binaries: []
            )
        ]
    }

    /// A v21 database holding that queue, written **as rows** rather than through `OutboxStore`.
    ///
    /// `SchemaV21Tests.v20Database`'s reason: the shipping write path is not what an
    /// already-installed database was filled by, and it would maintain `photos_outstanding` through
    /// the very triggers the migration has to survive.
    private static func v21Database(_ items: [QueuedItem]) async throws -> CypressStore {
        let store = try await CypressStore.inMemory(
            migrations: AppSchema.migrations.filter { $0.version <= 21 }
        )
        let stamp = SQLiteTimestamp.string(from: moment)

        try await store.queue.write { connection in
            let opened = try connection.userVersion
            #expect(opened == 21, "the fixture opened at user_version \(opened), not 21")
            #expect(
                !(try Self.outboxDDL(connection).contains("data_dispute")),
                "a v21 database already admitted the kinds this migration adds"
            )
            #expect(
                try Self.tableExists("tree_data_disputes", connection) == false,
                "a v21 database already had the table this migration creates"
            )

            // Sparse `seq` — 10, 20, 30, 40, 50 — for `SchemaV21Tests`' measured reason: `1, 2, 3,
            // 4` is exactly what an `INSERT … SELECT` that forgot to carry `seq` would produce from
            // AUTOINCREMENT, so a contiguous fixture leaves that revert green.
            for (index, item) in items.enumerated() {
                let error = item.lastError.map { "'\($0)'" } ?? "NULL"
                let code = item.lastErrorCode.map { "'\($0)'" } ?? "NULL"
                let nextAttempt = item.nextAttemptAt
                    .map { "'\(SQLiteTimestamp.string(from: $0))'" } ?? "NULL"
                // Three timestamps a day apart per row, so a copy that put `created_at` into
                // `updated_at` is visible.
                let created = SQLiteTimestamp.string(from: moment.addingTimeInterval(Double(index) * 86_400))
                let updated = SQLiteTimestamp.string(from: moment.addingTimeInterval(Double(index) * 86_400 + 60))
                let window = SQLiteTimestamp.string(from: moment.addingTimeInterval(Double(index) * 86_400 + 120))
                try connection.execute("""
                    INSERT INTO outbox
                        (seq, id, kind, client_uuid, payload, photo_paths, photos_outstanding,
                         state, fail_count, last_error, last_error_code, local_applied, remote_sent,
                         window_started_at, next_attempt_at, created_at, updated_at)
                    VALUES (\((index + 1) * 10),'\(item.id.uuidString)','\(item.kind)',
                            '\(item.clientUUID.uuidString)','\(item.payload)','\(item.photoPaths)',0,
                            '\(item.state)',\(item.failCount),\(error),\(code),1,\(item.remoteSent),
                            '\(window)',\(nextAttempt),'\(created)','\(updated)');
                    """)
                for binary in item.binaries {
                    // Inserted through the table, so v18's `counted_in` trigger sets
                    // `photos_outstanding` — which is how a real queue reaches this state.
                    try connection.execute("""
                        INSERT INTO outbox_photos
                            (id, outbox_id, path, shot_type, state, sendable,
                             fail_count, created_at, updated_at)
                        VALUES ('\(binary.uuidString)','\(item.id.uuidString)',
                                '/staged/\(binary.uuidString).jpg','full_tree','pending',1,
                                0,'\(stamp)','\(stamp)');
                        """)
                }
            }
        }
        return store
    }

    // MARK: - Readers

    private static func outboxDDL(_ connection: SQLiteConnection) throws -> String {
        let statement = try connection.prepare(
            "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'outbox'"
        )
        defer { statement.finalize() }
        return try statement.fetchOne { try $0.stringIfPresent("sql") ?? "" } ?? ""
    }

    private static func tableExists(_ name: String, _ connection: SQLiteConnection) throws -> Bool {
        let statement = try connection.prepare(
            "SELECT COUNT(*) AS n FROM sqlite_master WHERE type = 'table' AND name = :name"
        )
        defer { statement.finalize() }
        _ = try statement.bind([":name": name])
        return (try statement.fetchOne { try $0.int("n") } ?? 0) > 0
    }

    /// Every staged binary, as `(id, outbox_id, path)` — the three facts that make it the same
    /// binary rather than merely the same number of rows.
    private static func binaries(_ store: CypressStore) async throws -> [(String, String, String)] {
        try await store.queue.read { connection in
            let statement = try connection.prepare(
                "SELECT id, outbox_id, path FROM outbox_photos ORDER BY id"
            )
            defer { statement.finalize() }
            return try statement.fetchAll {
                (try $0.string("id"), try $0.string("outbox_id"), try $0.string("path"))
            }
        }
    }

    private struct QueueRow: Equatable {
        let values: [String: String?]
        subscript(column: String) -> String? { values[column] ?? nil }
        var id: String { self["id"] ?? "" }
        var photosOutstanding: Int { Int(self["photos_outstanding"] ?? "") ?? -1 }
    }

    /// The queue in `seq` order, **every column of it**, projected from the table's own column list.
    ///
    /// Not a hand-written `SELECT`, for `SchemaV21Tests`' reason: the failure this guards against is
    /// a column dropped from the rebuild's `INSERT … SELECT`, and a projection naming 7 of 17
    /// columns is green through exactly that.
    private static func queue(_ store: CypressStore) async throws -> [QueueRow] {
        try await store.queue.read { connection in
            let columns = try connection.columnNames(ofTable: "outbox")
            #expect(
                columns.count >= 17,
                """
                `outbox` reports \(columns.count) columns (\(columns)); v22's table has 17, so this \
                projection is reading a table that is not the one this suite is about
                """
            )
            let projection = columns.map { "CAST(\($0) AS TEXT) AS \($0)" }.joined(separator: ", ")
            let statement = try connection.prepare("SELECT \(projection) FROM outbox ORDER BY seq")
            defer { statement.finalize() }
            return try statement.fetchAll { row in
                var values: [String: String?] = [:]
                for column in columns {
                    values.updateValue(try row.stringIfPresent(column), forKey: column)
                }
                return QueueRow(values: values)
            }
        }
    }

    // MARK: - 1. The ladder

    /// **v22 runs, alone, on a database that already holds a queue.**
    ///
    /// This file is the newest version's, so it carries the claim `SchemaV21Tests` handed on: that
    /// `AppSchema.currentVersion` is what this file is written about. **When v23 lands, filter this
    /// suite's ladder to `<= 22` the way `SchemaV21Tests.ladder` is filtered, and move the
    /// `currentVersion` expectation below into v23's own file.**
    @Test("a v21 database with a queue in it is carried to 22 by exactly one migration")
    func aV21DatabaseRunsOnlyV22() async throws {
        let store = try await Self.v21Database(Self.fixture())

        let applied = try await store.queue.write { connection in
            try SchemaMigrator.migrate(AppSchema.migrations, on: connection)
        }
        #expect(
            applied == [Self.version],
            """
            a v21 database applied \(applied) rather than [\(Self.version)]. If this is a longer \
            list, another migration was added without this fixture being moved forward — filter the \
            ladder to `<= \(Self.version)` here and move the `currentVersion` claim below into the \
            new version's own file; if it is empty, v22 is not in `AppSchema.migrations`
            """
        )

        let version = try await store.queue.read { try $0.userVersion }
        #expect(version == AppSchema.currentVersion, "user_version is \(version)")
        #expect(
            AppSchema.currentVersion == Self.version,
            """
            `AppSchema.currentVersion` is \(AppSchema.currentVersion) and this file is written \
            about \(Self.version). One of the two moved without the other — the fixture above still \
            opens at 21 and no longer proves what it says it proves
            """
        )
    }

    // MARK: - 2. The binaries

    /// **Every staged binary is still there afterwards, on the item it belonged to, at the path it
    /// was staged at — and the counter says so.**
    ///
    /// The test the parking block in `applyV22` exists to pass. `outbox_photos.outbox_id` cascades
    /// from `outbox` and this migration drops `outbox`; without the parking, every queued photograph
    /// in the app is deleted and `photos_outstanding` is copied across unchanged, leaving a queue
    /// that can never settle `done` with no error anywhere.
    ///
    /// **Two comparisons, in opposite directions, and neither may be dropped for the other.** The
    /// counter against `outbox_photos` catches a counter left too *high* by a cascade that fired no
    /// triggers; the counter against what the fixture staged catches one recomputed too *low*
    /// against children that are already gone. `SchemaV21Tests`' header measured both halves.
    @Test("the staged binaries survive the rebuild, and the counter still counts them")
    func theStagedBinariesSurviveTheRebuild() async throws {
        let items = Self.fixture()
        let store = try await Self.v21Database(items)
        let before = try await Self.binaries(store)
        #expect(before.count == 3, "the fixture staged \(before.count) binaries, not 3")

        _ = try await store.queue.write { connection in
            try SchemaMigrator.migrate(AppSchema.migrations, on: connection)
        }

        let after = try await Self.binaries(store)
        #expect(
            after.map(\.0) == before.map(\.0),
            "the staged binaries did not come through the rebuild: \(before.count) before, \(after.count) after"
        )
        #expect(after.map(\.1) == before.map(\.1), "a binary came back attached to a different item")
        #expect(after.map(\.2) == before.map(\.2), "a binary came back pointing at a different path")

        let live = Dictionary(grouping: after, by: \.1).mapValues(\.count)
        let staged = Dictionary(uniqueKeysWithValues: items.map { ($0.id.uuidString, $0.binaries.count) })
        for row in try await Self.queue(store) {
            #expect(
                row.photosOutstanding == (live[row.id] ?? 0),
                "\(row.id): (outstanding → \(row.photosOutstanding)) == (live → \(live[row.id] ?? 0))"
            )
            #expect(
                row.photosOutstanding == (staged[row.id] ?? 0),
                "\(row.id): (outstanding → \(row.photosOutstanding)) == (staged → \(staged[row.id] ?? 0))"
            )
        }
    }

    // MARK: - 3. The queue

    /// The queue itself is carried across column for column, in `seq` order.
    ///
    /// The negative control for the test above: it says the cascade reaches the child table and
    /// nothing else.
    @Test("the queue survives the rebuild, column for column and in order")
    func theQueueSurvivesTheRebuild() async throws {
        let store = try await Self.v21Database(Self.fixture())
        let before = try await Self.queue(store)
        #expect(before.count == 5, "the fixture queued \(before.count) rows, not 5")

        _ = try await store.queue.write { connection in
            try SchemaMigrator.migrate(AppSchema.migrations, on: connection)
        }

        let after = try await Self.queue(store)
        // `photos_outstanding` is recomputed by step 5 and is asserted by the test above; every
        // other column has to be identical. Compared per row so a failure names the column.
        for (old, new) in zip(before, after) {
            for column in old.values.keys where column != "photos_outstanding" {
                #expect(
                    old[column] == new[column],
                    "\(column) changed across the rebuild: \(old[column] ?? "nil") → \(new[column] ?? "nil")"
                )
            }
        }
        #expect(after.count == before.count, "the rebuild changed the number of queued rows")
        #expect(after.map(\.id) == before.map(\.id), "the rebuild changed the queue's order")
    }

    // MARK: - 4. The vocabulary

    /// **Both new kinds are storable afterwards, and neither was before.**
    ///
    /// Two directions, because "the migration widened the vocabulary" is only interesting beside
    /// evidence that it was narrower first — otherwise it passes on a migration that did nothing.
    @Test("the vocabulary admits both dispute kinds afterwards and neither before")
    func theVocabularyWidensBothWays() async throws {
        let store = try await Self.v21Database([])

        for kind in ["data_dispute", "data_dispute_withdrawal"] {
            let refused: Bool = try await store.queue.write { connection in
                do {
                    try Self.insertOutboxRow(kind: kind, connection: connection)
                    return false
                } catch {
                    return true
                }
            }
            #expect(refused, "a v21 outbox already accepted '\(kind)'")
        }

        _ = try await store.queue.write { connection in
            try SchemaMigrator.migrate(AppSchema.migrations, on: connection)
        }

        for kind in ["data_dispute", "data_dispute_withdrawal"] {
            try await store.queue.write { connection in
                try Self.insertOutboxRow(kind: kind, connection: connection)
            }
        }
        let stored = try await Self.queue(store).map { $0["kind"] ?? "" }
        #expect(
            Set(stored) == ["data_dispute", "data_dispute_withdrawal"],
            "the outbox holds \(stored) after accepting both kinds"
        )

        // And the vocabulary is still closed. A rebuild that dropped the CHECK altogether would pass
        // every expectation above.
        let accepted: Bool = try await store.queue.write { connection in
            do {
                try Self.insertOutboxRow(kind: "not_a_kind", connection: connection)
                return true
            } catch {
                return false
            }
        }
        #expect(!accepted, "the rebuilt outbox accepts any string; the CHECK did not come across")
    }

    /// The migration widens a vocabulary; it must not sweep anything into the queue while doing it.
    ///
    /// v17's ruling, and there is nothing a sweep could even find here — no build before v22 could
    /// record a dispute. The control is a queued row that *was* there, so "the outbox is empty
    /// afterwards" cannot pass by the rebuild having dropped everything.
    @Test("the migration enqueues nothing")
    func theMigrationEnqueuesNothing() async throws {
        let items = Self.fixture()
        let store = try await Self.v21Database(items)

        _ = try await store.queue.write { connection in
            try SchemaMigrator.migrate(AppSchema.migrations, on: connection)
        }

        let queued = try await Self.queue(store)
        #expect(
            queued.map(\.id).sorted() == items.map(\.id.uuidString).sorted(),
            "the migration changed which rows are queued: \(queued.map(\.id))"
        )
    }

    // MARK: - 5. The three new tables

    /// The dispute tables exist, and both `CHECK` vocabularies are exactly the fixed ones.
    ///
    /// **Driven from the enums**, so a seventh `SuggestedField` or a fourth `IssueKind` added in
    /// Swift and forgotten in the migration fails here rather than at a contributor's first tap.
    /// The refusal control is what stops it passing on a table with no CHECK at all.
    @Test("the dispute tables admit exactly the vocabularies the enums declare")
    func theDisputeTablesCarryTheirVocabularies() async throws {
        let store = try await Self.v21Database([])
        _ = try await store.queue.write { connection in
            try SchemaMigrator.migrate(AppSchema.migrations, on: connection)
        }

        for table in ["tree_data_disputes", "tree_dispute_issues", "tree_dispute_suggestions"] {
            let exists = try await store.queue.read { try Self.tableExists(table, $0) }
            #expect(exists, "\(table) is not in the database after v22")
        }

        let parent = UUID()
        try await store.queue.write { connection in
            let stamp = SQLiteTimestamp.string(from: Self.moment)
            try connection.execute("""
                INSERT INTO tree_data_disputes
                    (id, client_uuid, tree_id, tree_source, created_at, updated_at)
                VALUES ('\(parent.uuidString)','\(UUID().uuidString)','\(UUID().uuidString)',
                        'city_import','\(stamp)','\(stamp)');
                """)
        }

        for kind in TreeDataDispute.IssueKind.allCases {
            let stored: Bool = try await store.queue.write { connection in
                do {
                    try connection.execute("""
                        INSERT INTO tree_dispute_issues (dispute_id, kind)
                        VALUES ('\(parent.uuidString)','\(kind.rawValue)');
                        """)
                    return true
                } catch { return false }
            }
            #expect(stored, "tree_dispute_issues refused '\(kind.rawValue)', which the enum declares")
        }
        for field in TreeDataDispute.SuggestedField.allCases {
            let stored: Bool = try await store.queue.write { connection in
                do {
                    try connection.execute("""
                        INSERT INTO tree_dispute_suggestions (dispute_id, field, value)
                        VALUES ('\(parent.uuidString)','\(field.rawValue)','x');
                        """)
                    return true
                } catch { return false }
            }
            #expect(stored, "tree_dispute_suggestions refused '\(field.rawValue)', which the enum declares")
        }

        // The controls: both CHECKs still close, and `tree_source` is the two `TreeSource` raw
        // values rather than any string.
        let refusals: [(String, String)] = [
            ("tree_dispute_issues (dispute_id, kind) VALUES ('\(parent.uuidString)','wrong_everything')",
             "tree_dispute_issues.kind"),
            ("tree_dispute_suggestions (dispute_id, field, value) VALUES ('\(parent.uuidString)','dbh_cm','1')",
             "tree_dispute_suggestions.field")
        ]
        for (statement, name) in refusals {
            let accepted: Bool = try await store.queue.write { connection in
                do {
                    try connection.execute("INSERT INTO \(statement);")
                    return true
                } catch { return false }
            }
            #expect(!accepted, "\(name) accepts values outside its vocabulary; the CHECK is not there")
        }

        let badSource: Bool = try await store.queue.write { connection in
            let stamp = SQLiteTimestamp.string(from: Self.moment)
            do {
                try connection.execute("""
                    INSERT INTO tree_data_disputes
                        (id, client_uuid, tree_id, tree_source, created_at, updated_at)
                    VALUES ('\(UUID().uuidString)','\(UUID().uuidString)','\(UUID().uuidString)',
                            'city','\(stamp)','\(stamp)');
                    """)
                return true
            } catch { return false }
        }
        #expect(
            !badSource,
            """
            tree_data_disputes accepted tree_source 'city', which is not a `TreeSource` raw value. \
            The column holds `city_import`/`community` — the same two strings `seed.trees.source` \
            and `community_trees.source` hold — and a third spelling is how two copies of a \
            vocabulary start to differ
            """
        )
    }

    // MARK: - 6. The hazard the migration's comment names

    /// **The cascade `applyV22` warns a future rebuilder about is real on this SQLite.**
    ///
    /// The comment beside the two `ON DELETE CASCADE` children says that dropping the parent during
    /// a rebuild deletes every checked issue and every suggested value, and that
    /// `PRAGMA defer_foreign_keys = ON` does not save it because it defers the *check* and a cascade
    /// is an *action*. A confident comment is where bugs have survived in this project, so it is
    /// measured here rather than believed — against this build's own SQLite, on this schema's own
    /// tables, inside a transaction, with `foreign_keys` on as `DatabaseQueue` sets it.
    ///
    /// It is a test about SQLite's behavior on purpose. What it protects is a *sentence*, and the
    /// sentence is the only thing standing between the next author of a `tree_data_disputes` rebuild
    /// and silently deleting the contents of two tables.
    @Test("dropping the dispute parent cascades its children away, and deferring does not stop it")
    func theCascadeIsRealOnThisSQLite() async throws {
        let store = try await Self.v21Database([])
        _ = try await store.queue.write { connection in
            try SchemaMigrator.migrate(AppSchema.migrations, on: connection)
        }

        let parent = UUID()
        try await store.queue.write { connection in
            let stamp = SQLiteTimestamp.string(from: Self.moment)
            try connection.execute("""
                INSERT INTO tree_data_disputes
                    (id, client_uuid, tree_id, tree_source, created_at, updated_at)
                VALUES ('\(parent.uuidString)','\(UUID().uuidString)','\(UUID().uuidString)',
                        'city_import','\(stamp)','\(stamp)');
                INSERT INTO tree_dispute_issues (dispute_id, kind)
                VALUES ('\(parent.uuidString)','wrong_species');
                INSERT INTO tree_dispute_suggestions (dispute_id, field, value)
                VALUES ('\(parent.uuidString)','species_id','\(UUID().uuidString)');
                """)
        }

        // The control first: `PRAGMA foreign_keys` is on, so the cascade below is a live rule and
        // not an inert clause. Without this, "the children went" would also be what a table with no
        // foreign keys at all looks like.
        let enforced = try await store.queue.read { connection -> Int in
            let statement = try connection.prepare("PRAGMA foreign_keys")
            defer { statement.finalize() }
            return try statement.fetchOne { try $0.int("foreign_keys") } ?? 0
        }
        #expect(enforced == 1, "foreign keys are off on this connection; the measurement below is vacuous")

        let (issues, suggestions) = try await store.queue.write { connection -> (Int, Int) in
            // The tempting escape, set inside the transaction the migrator opens — which is the only
            // reason it is a candidate at all, `PRAGMA foreign_keys` being a documented no-op there.
            try connection.execute("PRAGMA defer_foreign_keys = ON;")
            try connection.execute("""
                CREATE TABLE tree_data_disputes_rebuilt AS SELECT * FROM tree_data_disputes;
                DROP TABLE tree_data_disputes;
                """)
            let issueRows = try connection.prepare("SELECT COUNT(*) AS n FROM tree_dispute_issues")
            defer { issueRows.finalize() }
            let suggestionRows = try connection.prepare("SELECT COUNT(*) AS n FROM tree_dispute_suggestions")
            defer { suggestionRows.finalize() }
            return (
                try issueRows.fetchOne { try $0.int("n") } ?? -1,
                try suggestionRows.fetchOne { try $0.int("n") } ?? -1
            )
        }

        #expect(
            issues == 0 && suggestions == 0,
            """
            dropping `tree_data_disputes` left \(issues) issue(s) and \(suggestions) suggestion(s) \
            standing. If SQLite has stopped cascading here, `AppSchema.applyV22`'s comment about \
            what a future rebuild must do is now wrong and has to be rewritten rather than trusted
            """
        )
    }

    // MARK: - Helpers

    private static func insertOutboxRow(kind: String, connection: SQLiteConnection) throws {
        let stamp = SQLiteTimestamp.string(from: moment)
        try connection.execute("""
            INSERT INTO outbox (id, kind, client_uuid, payload, photo_paths, state, fail_count,
                local_applied, remote_sent, window_started_at, created_at, updated_at)
            VALUES ('\(UUID().uuidString)','\(kind)','\(UUID().uuidString)','{}','[]','pending',0,
                1,0,'\(stamp)','\(stamp)','\(stamp)');
            """)
    }
}
