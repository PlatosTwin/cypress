import Foundation
import Testing
@testable import Cypress

/// **What migration v21 does to a database that already has a queue in it.**
///
/// v21 widens `outbox.kind` to admit `measurement_withdrawal`, and SQLite cannot widen a `CHECK` in
/// place, so it is a table rebuild — the fifth this table has had (v4, v15, v17, v18, v21).
///
/// `DataGates.sqliteStore` runs the whole ladder on an **empty** in-memory database and picks up a
/// new version for free: it asserts the versions applied, that a second run applies none, that
/// `user_version` matches `currentVersion`, that a replay from 0 is clean, and that a database from
/// the future is refused. Every one of those passes on this migration written badly, because every
/// one of them runs against a database with no rows.
///
/// This file is the part that only shows up with rows in it, and one of the four tests below is the
/// reason the migration is shaped the way it is:
///
/// 1. a v20 database with a queue in it reaches 21 by running exactly one step;
/// 2. **the staged binaries survive the rebuild** — see below;
/// 3. the queue itself is carried across column for column, `seq` order included;
/// 4. the vocabulary really widened, and the migration enqueued nothing while widening it.
///
/// ── Why (2) is the whole point ─────────────────────────────────────────────────────────────────
///
/// `outbox_photos.outbox_id` is `ON DELETE CASCADE` against `outbox`, and this migration **drops**
/// `outbox`. Under `PRAGMA foreign_keys = ON` — which `DatabaseQueue` sets on every connection —
/// the implicit `DELETE FROM` inside `DROP TABLE` performs that cascade, so a rebuild written the
/// obvious way deletes every queued photograph in the app. Worse, the implicit delete fires no
/// triggers, so `outbox.photos_outstanding` is copied across *unchanged* and every item goes on
/// owing binaries that no longer exist — a queue that can never settle `done`, with no error
/// anywhere. Both halves were measured on SQLite 3.51 before the migration was written, and v18's
/// header records the same hazard from the round that first met it.
///
/// So v21 parks the binaries in a table with no foreign key, empties the child, rebuilds, puts them
/// back, and recomputes the counter. `theStagedBinariesSurviveTheRebuild` is what makes that
/// structure load-bearing rather than decorative.
///
/// ── Calibration ────────────────────────────────────────────────────────────────────────────────
///
/// Measured, by deleting the parking block from `applyV21` and running this suite:
/// `theStagedBinariesSurviveTheRebuild` fails with **3 issues** — the binaries are gone
/// (`after.map(\\.0) == before.map(\\.0) → false`), and both items that were carrying one come out
/// of the rebuild still owing it (`(outstanding → 2) == (live[id] ?? 0 → 0)`, and the same at 1).
/// The other four tests stay green under that revert, and correctly so: they are about the version
/// ladder, the queue rows, the vocabulary and the scaffolding, none of which the cascade touches.
/// `theQueueSurvivesTheRebuild` is the negative control that the cascade *only* reaches the child
/// table.
///
/// **The counter half of that measurement is why it is asked against `outbox_photos` rather than
/// against the fixture.** Written the obvious way — comparing the counter to how many binaries the
/// fixture staged — it stayed green under this exact revert and reported two issues where there
/// were three: the rebuild copies `photos_outstanding` *before* the drop cascades the children
/// away, so the number is correct and the rows behind it are gone. A guard green while its defect
/// is present, found by running the red-proof rather than by reading the test.
@Suite("AppSchema · v21")
struct SchemaV21Tests {

    private static let moment = Date(timeIntervalSince1970: 1_790_000_000)

    /// The version this file is about, read from the code rather than written down twice.
    private static var version: Int32 { 21 }

    /// The ladder this suite runs, which stops at v21.
    ///
    /// **Filtered since v22 landed**, which is what this file's own header told the next author to
    /// do: "when v22 lands, this test filters its ladder to `<= 21` and the `currentVersion`
    /// expectation moves to v22's file". Unfiltered, every test here would run v22's rebuild on top
    /// of v21's and then assert v21's shape against a table v22 replaced — a suite about the wrong
    /// migration, still green for a while, which is the failure the instruction existed to prevent.
    private static var ladder: [Migration] { AppSchema.migrations.filter { $0.version <= version } }

    // MARK: - The fixture

    /// One queued item as it sits in a v20 database, and the binaries it still owes.
    ///
    /// **Every column the rebuild has to carry gets a distinguishable value**, which is a repair
    /// rather than thoroughness for its own sake. Written with three of them uniformly NULL or zero
    /// — no `uploading` row, no `next_attempt_at`, nothing `remote_sent` — the fixture could not
    /// tell a copied column from a defaulted one, so an `INSERT … SELECT` that dropped any of the
    /// three would have left `theQueueSurvivesTheRebuild` green.
    private struct QueuedItem {
        let id: UUID
        let clientUUID: UUID
        let kind: String
        let state: String
        let failCount: Int
        let lastError: String?
        let lastErrorCode: String?
        /// Set on the one row the drain has scheduled a retry for; NULL elsewhere, as in a real queue.
        let nextAttemptAt: Date?
        let remoteSent: Int
        /// Distinct per row, so a payload swapped between two rows is visible.
        let payload: String
        /// v2's column, dead since v18 and still copied — so still checked.
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
                // The *current* shape, `[{path, shotType}]`, not v1's bare string. A v20 database
                // cannot hold the bare form — v2 rewrote it eight versions ago — and a fixture that
                // carried one made `replayingTheLadderChangesNothing` red for v2's reason rather
                // than v21's: the replay re-runs v2, which rewrites the element, so the queue
                // genuinely changes. Measured, and it is the fixture that was wrong.
                photoPaths: #"[{"path":"/staged/a.jpg","shotType":"other"}]"#,
                binaries: [UUID(), UUID()]
            ),
            // A failed species correction carrying error text, an error code and a retry count, so
            // "the queue came across" is a claim about more than ids.
            QueuedItem(
                id: UUID(), clientUUID: UUID(), kind: "species_correction", state: "failed",
                failCount: 3, lastError: "the service said no", lastErrorCode: "validation_failed",
                nextAttemptAt: nil, remoteSent: 0, payload: #"{"note":"the correction"}"#,
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
            // The fourth state, which the fixture had no row in, and the only one carrying a
            // scheduled retry: a row the drain has picked up, with a `next_attempt_at` behind it.
            QueuedItem(
                id: UUID(), clientUUID: UUID(), kind: "measurement", state: "uploading",
                failCount: 2, lastError: "the service was busy", lastErrorCode: "rate_limited",
                nextAttemptAt: moment.addingTimeInterval(900), remoteSent: 0,
                payload: #"{"note":"the one in flight"}"#, photoPaths: "[]", binaries: []
            )
        ]
    }

    /// A v20 database holding that queue, written **as rows** rather than through `OutboxStore`.
    ///
    /// `PhotoProvenanceTests.upgradedFromV15`'s reason: the shipping write path is not what an
    /// already-installed database was filled by, and handing a migration rows in the exact shape the
    /// current code produces tests the migration against its own author's assumptions. It matters
    /// more than usual here, because `OutboxStore.stagePhoto` would maintain `photos_outstanding`
    /// through the same triggers the migration has to survive.
    private static func v20Database(_ items: [QueuedItem]) async throws -> CypressStore {
        let store = try await CypressStore.inMemory(
            migrations: AppSchema.migrations.filter { $0.version <= 20 }
        )
        let stamp = SQLiteTimestamp.string(from: moment)

        try await store.queue.write { connection in
            let opened = try connection.userVersion
            #expect(opened == 20, "the fixture opened at user_version \(opened), not 20")
            #expect(
                !(try Self.outboxDDL(connection).contains("measurement_withdrawal")),
                "a v20 database already admitted the kind this migration adds"
            )

            // **`seq` is sparse — 10, 20, 30, 40 — and that is what makes it testable.** A real
            // queue's sequence has gaps in it (settled rows are removed) and, more to the point,
            // `1, 2, 3, 4` is exactly what an `INSERT … SELECT` that *forgot* to carry `seq` would
            // produce from AUTOINCREMENT. Written contiguously, `theQueueSurvivesTheRebuild` was
            // green under that revert.
            for (index, item) in items.enumerated() {
                let error = item.lastError.map { "'\($0)'" } ?? "NULL"
                let code = item.lastErrorCode.map { "'\($0)'" } ?? "NULL"
                let nextAttempt = item.nextAttemptAt
                    .map { "'\(SQLiteTimestamp.string(from: $0))'" } ?? "NULL"
                // The timestamps differ per row as well, and by a day rather than a second: three
                // columns holding one identical string cannot show a copy that put `created_at`
                // into `updated_at`, or either into `window_started_at`.
                let created = SQLiteTimestamp.string(from: moment.addingTimeInterval(Double(index) * 86_400))
                let updated = SQLiteTimestamp.string(from: moment.addingTimeInterval(Double(index) * 86_400 + 60))
                let window = SQLiteTimestamp.string(from: moment.addingTimeInterval(Double(index) * 86_400 + 120))
                // `local_applied = 1` on every row, because `done` requires it and the settled item
                // above is one — as does `remote_sent = 1`. The two sinks are v15's and v21 does not
                // touch them.
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
                    // `photos_outstanding` — which is exactly how a real queue reaches this state.
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

    private static func outboxDDL(_ connection: SQLiteConnection) throws -> String {
        let statement = try connection.prepare(
            "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'outbox'"
        )
        defer { statement.finalize() }
        return try statement.fetchOne { try $0.stringIfPresent("sql") ?? "" } ?? ""
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

    /// One `outbox` row, every column of it, as text.
    ///
    /// Text because the comparison is "is this the same value", not "is this the same type": a
    /// `CAST(… AS TEXT)` projection reads a column whose affinity it does not need to know, which is
    /// what lets the reader below follow `pragma_table_info` instead of a hand-written list.
    private struct QueueRow: Equatable {
        let values: [String: String?]

        subscript(column: String) -> String? { values[column] ?? nil }
        var seq: String { self["seq"] ?? "" }
        var id: String { self["id"] ?? "" }
        var kind: String { self["kind"] ?? "" }
        var photosOutstanding: Int { Int(self["photos_outstanding"] ?? "") ?? -1 }
    }

    /// The queue in `seq` order, **every column of it**, projected from the table's own column list.
    ///
    /// **Not a hand-written `SELECT`.** This read named 7 of the 17 columns, while the test it feeds
    /// says "column for column" and the failure it guards against is a column dropped from the
    /// rebuild's `INSERT … SELECT` — so an edit that lost `next_attempt_at` or `remote_sent` would
    /// have left it green. Reading `columnNames(ofTable:)` makes the projection follow the schema,
    /// and it keeps following it: the day v22 adds a column and forgets to carry it, this fails
    /// without anybody having remembered to widen a list here.
    private static func queue(_ store: CypressStore) async throws -> [QueueRow] {
        try await store.queue.read { connection in
            let columns = try connection.columnNames(ofTable: "outbox")
            #expect(
                columns.count >= 17,
                """
                `outbox` reports \(columns.count) columns (\(columns)); v21's table has 17, so this \
                projection is reading a table that is not the one this suite is about
                """
            )
            let projection = columns.map { "CAST(\($0) AS TEXT) AS \($0)" }.joined(separator: ", ")
            let statement = try connection.prepare("SELECT \(projection) FROM outbox ORDER BY seq")
            defer { statement.finalize() }
            return try statement.fetchAll { row in
                var values: [String: String?] = [:]
                for column in columns {
                    // `updateValue` rather than the subscript: assigning a `String?` through
                    // `values[column]` is one implicit promotion away from removing the key
                    // instead of storing a NULL, and a missing key would compare equal to a
                    // missing key on the other side.
                    values.updateValue(try row.stringIfPresent(column), forKey: column)
                }
                return QueueRow(values: values)
            }
        }
    }

    // MARK: - 1. The ladder

    /// **v21 runs, alone, on a database that already holds a queue.**
    ///
    /// This file **used** to be the newest version's and carried the claim `SchemaV19Tests` handed
    /// to `SchemaV20Tests` and `SchemaV20Tests` handed here: that `AppSchema.currentVersion` is what
    /// it is written about. v22 landed, so it did what its own instruction said — the ladder is
    /// filtered to `<= 21` (`Self.ladder`) and the `currentVersion` expectation now lives in
    /// `SchemaV22Tests`. The same instruction is repeated there for whoever writes v23.
    @Test("a v20 database with a queue in it is carried to 21 by exactly one migration")
    func aV20DatabaseRunsOnlyV21() async throws {
        let store = try await Self.v20Database(Self.fixture())

        let applied = try await store.queue.write { connection in
            try SchemaMigrator.migrate(Self.ladder, on: connection)
        }
        #expect(
            applied == [Self.version],
            """
            a v20 database applied \(applied) rather than [\(Self.version)]. If this is a longer \
            list, another migration was added without this fixture being moved forward — filter \
            the ladder to `<= \(Self.version)` here and move the `currentVersion` claim below into \
            the new version's own file; if it is empty, v21 is not in `AppSchema.migrations`
            """
        )

        let version = try await store.queue.read { try $0.userVersion }
        #expect(
            version == Self.version,
            """
            a v20 database run up this suite's ladder reports user_version \(version), not \
            \(Self.version)
            """
        )
        // **The `currentVersion` claim is not here any more.** It moved to `SchemaV22Tests` the day
        // v22 landed, which is what this file's header instructed: the newest version's own file is
        // where "this is the newest version" belongs, and asserting it here against a ladder that
        // deliberately stops at 21 would be asserting something this suite has arranged to be false.
    }

    // MARK: - 2. The binaries

    /// **Every staged binary is still there afterwards, on the item it belonged to, at the path it
    /// was staged at — and the counter says so.**
    ///
    /// The test the whole shape of this migration exists to pass. See this suite's header for what
    /// the obvious rebuild does instead, and why nothing else in the suite can see it.
    @Test("the staged binaries survive the rebuild, and the counter still counts them")
    func theStagedBinariesSurviveTheRebuild() async throws {
        let items = Self.fixture()
        let store = try await Self.v20Database(items)
        let before = try await Self.binaries(store)
        #expect(before.count == 3, "the fixture staged \(before.count) binaries, not 3")

        _ = try await store.queue.write { connection in
            try SchemaMigrator.migrate(Self.ladder, on: connection)
        }

        let after = try await Self.binaries(store)
        #expect(
            after.map(\.0) == before.map(\.0) && after.map(\.1) == before.map(\.1)
                && after.map(\.2) == before.map(\.2),
            """
            the rebuild lost or altered staged binaries: \(before.count) before, \(after.count) \
            after. Each is a contributor's photograph waiting to be sent, and `DROP TABLE outbox` \
            cascades them away unless they are parked first
            """
        )

        // The counter, which is the second half of the same defect and the quieter one: a cascade
        // fires no triggers, so an unparked rebuild leaves every item claiming binaries that are
        // gone and unable ever to reach `done`.
        //
        // **Asked against the child table, not against the fixture**, and the difference is the
        // whole assertion. Comparing the counter to what the fixture staged passes under exactly
        // the defect this is for: the rebuild copies `photos_outstanding` *before* the drop
        // cascades the children away, so the number is the right one and the rows behind it are
        // gone. It was written that way first and stayed green while the binaries were being
        // destroyed two lines above — this project's dominant defect shape, met once more.
        let counters = try await Self.queue(store).map { ($0.id, $0.photosOutstanding) }
        let live = try await Self.binaries(store).reduce(into: [String: Int]()) { counts, binary in
            counts[binary.1, default: 0] += 1
        }
        let staged = Dictionary(
            uniqueKeysWithValues: items.map { ($0.id.uuidString, $0.binaries.count) }
        )
        for (id, outstanding) in counters {
            #expect(
                outstanding == live[id] ?? 0,
                """
                item \(id) came out of the rebuild owing \(outstanding) binaries with \
                \(live[id] ?? 0) actually in `outbox_photos`. An item can never reach `done` \
                while it owes a binary that does not exist
                """
            )
            #expect(
                outstanding == staged[id],
                "item \(id) owes \(outstanding) binaries, and the fixture staged \(staged[id] ?? -1)"
            )
        }
    }

    // MARK: - 3. The queue

    /// **The queue came across column for column, in `seq` order — all seventeen of them.**
    ///
    /// The negative control for the test above: the cascade reaches the child table and nothing
    /// else, so this stays green under the revert that turns that one red. It is here for the
    /// rebuild's *own* failure modes — a column dropped from the `INSERT … SELECT`, a `seq` not
    /// carried (which would renumber the FIFO order the drain reads), error text or a retry count
    /// left behind.
    ///
    /// **It used to compare 7 columns of 17 while saying "column for column".** `client_uuid`,
    /// `payload`, `photo_paths`, `last_error_code`, `local_applied`, `remote_sent`,
    /// `window_started_at`, `next_attempt_at`, `created_at` and `updated_at` went unread, and three
    /// of those were uniformly NULL or zero in the fixture besides — so a rebuild that dropped
    /// `next_attempt_at` or `remote_sent` would lose no row, renumber no `seq`, and leave this
    /// green. The fixture now holds a row in every state with a distinguishable value in every
    /// column, and the projection follows `pragma_table_info` rather than a list somebody has to
    /// remember to widen.
    @Test("the queue itself is carried across unchanged, every column and seq order included")
    func theQueueSurvivesTheRebuild() async throws {
        let store = try await Self.v20Database(Self.fixture())
        let columnsBefore = try await store.queue.read { try $0.columnNames(ofTable: "outbox") }
        let before = try await Self.queue(store)

        _ = try await store.queue.write { connection in
            try SchemaMigrator.migrate(Self.ladder, on: connection)
        }

        let columnsAfter = try await store.queue.read { try $0.columnNames(ofTable: "outbox") }
        #expect(
            columnsAfter == columnsBefore,
            """
            the rebuilt table's columns are \(columnsAfter) where v20's were \(columnsBefore). v21 \
            widens a CHECK and must add, drop and reorder nothing
            """
        )

        let after = try await Self.queue(store)
        #expect(
            after.map(\.seq) == before.map(\.seq),
            "seq changed: \(before.map(\.seq)) → \(after.map(\.seq))"
        )
        #expect(after.map(\.id) == before.map(\.id), "the rows changed identity or order")

        // Every column of every row, named individually, because "the rows differ" is not a finding
        // somebody can act on and this is the assertion that catches a dropped column.
        var lost: [String] = []
        for (old, new) in zip(before, after) where old != new {
            for column in columnsBefore where old[column] != new[column] {
                lost.append(
                    "seq \(old.seq) · \(column): \(old[column] ?? "NULL") → \(new[column] ?? "NULL")"
                )
            }
        }
        #expect(
            lost.isEmpty,
            """
            the rebuild did not carry every column across: \(lost.joined(separator: "; ")). Each \
            one is a fact about a contributor's queued mutation, silently defaulted by an \
            `INSERT … SELECT` that did not name it
            """
        )
        #expect(after == before, "the queue changed in a way the per-column report above did not name")
    }

    // MARK: - 4. The vocabulary

    /// **The widening happened, and the migration queued nothing while doing it.**
    ///
    /// Two halves that have to be asserted together. "Nothing was enqueued" is trivially true of a
    /// migration that did nothing at all, so the row inserted at the end is what makes the first
    /// half non-vacuous — the same pairing `CommunityOutboxKindTests
    /// .theMigrationDoesNotSweepPreExistingWorkIntoTheQueue` makes for v17.
    ///
    /// **The tombstoned reading in the fixture is the sweep this must not perform.** No shipping
    /// build before v21 could tombstone a measurement, so it is written as a row — a device that
    /// somehow holds a withdrawn reading must not have it published the first time a drain runs.
    /// v17's ruling, restated on this table.
    @Test("the vocabulary widens and the migration enqueues nothing")
    func theVocabularyWidensAndNothingIsSwept() async throws {
        let items = Self.fixture()
        let store = try await Self.v20Database(items)
        let stamp = SQLiteTimestamp.string(from: Self.moment)
        let tree = UUID(), reading = UUID()

        try await store.queue.write { connection in
            try connection.execute("""
                INSERT INTO measurements
                    (id, tree_uuid, device_id, client_uuid, captured_at, kind, value,
                     unit_entered, si_value, method, measurement_height_m,
                     created_at, updated_at, deleted_at)
                VALUES ('\(reading.uuidString)','\(tree.uuidString)','\(UUID().uuidString)',
                        '\(UUID().uuidString)','\(stamp)','dbh',31,'cm',0.31,'tape',1.4,
                        '\(stamp)','\(stamp)','\(stamp)');
                """)
        }

        _ = try await store.queue.write { connection in
            try SchemaMigrator.migrate(Self.ladder, on: connection)
        }

        let queued = try await Self.queue(store)
        #expect(
            queued.map(\.id) == items.map(\.id.uuidString),
            """
            the migration left \(queued.count) rows in the queue (\(queued.map(\.kind))); only the \
            \(items.count) that were already there may be present. A withdrawn reading on somebody's \
            phone must not be published by an upgrade
            """
        )

        // And the widening actually happened — otherwise the sentence above is true for the
        // uninteresting reason that nothing changed.
        try await store.queue.write { connection in
            try connection.execute("""
                INSERT INTO outbox
                    (id, kind, client_uuid, payload, state, fail_count, local_applied,
                     remote_sent, window_started_at, created_at, updated_at)
                VALUES ('\(UUID().uuidString)','measurement_withdrawal','\(UUID().uuidString)',
                        '{}','pending',0,1,0,'\(stamp)','\(stamp)','\(stamp)');
                """)
        }
        let ddl = try await store.queue.read { try Self.outboxDDL($0) }
        #expect(ddl.contains("measurement_withdrawal"), "the rebuilt CHECK does not name the new kind")
    }

    // MARK: - 5. Replay

    /// **The migration leaves nothing of its own behind, and a replay of the whole ladder against a
    /// migrated database changes nothing.**
    ///
    /// Two claims, and they are not equally strong — said plainly, because a red-proof that cannot
    /// be produced is a test that proves nothing:
    ///
    /// · **The parking table must not survive.** `outbox_photos_parked_v21` is scaffolding, and a
    ///   `CREATE TABLE` with no `IF NOT EXISTS` behind it: left in place, the next replay that
    ///   reaches this step dies on "table already exists", on somebody's phone, unattended.
    ///   Deleting the final `DROP TABLE` from `applyV21` turns this assertion red.
    ///
    /// · **The replay is a no-change assertion, and the guard is not what makes it true.** Measured:
    ///   with `applyV21`'s idempotence guard removed, a replay parks, empties, rebuilds and refills
    ///   a second time and every value below is identical afterwards, because `seq` is copied
    ///   explicitly. So this half cannot go red on a missing guard and does not claim to. What it
    ///   does catch is a replay that *errors* — the case above — or one that renumbers the FIFO
    ///   order the drain reads. The guard's own case is `DataGates.sqliteStore`'s replay from zero.
    @Test("the migration leaves no scaffolding, and a replay changes nothing")
    func replayingTheLadderChangesNothing() async throws {
        let store = try await Self.v20Database(Self.fixture())
        _ = try await store.queue.write { connection in
            try SchemaMigrator.migrate(Self.ladder, on: connection)
        }
        let queueAfterFirst = try await Self.queue(store)
        let binariesAfterFirst = try await Self.binaries(store)

        let leftovers = try await store.queue.read { connection -> [String] in
            let statement = try connection.prepare("""
                SELECT name FROM sqlite_master
                 WHERE type = 'table' AND name LIKE '%parked%'
                """)
            defer { statement.finalize() }
            return try statement.fetchAll { try $0.string("name") }
        }
        #expect(
            leftovers.isEmpty,
            """
            the migration left \(leftovers) behind. The parking table has no `IF NOT EXISTS`, so a \
            replay that reaches this step dies on "table already exists"
            """
        )

        try await store.queue.write { connection in
            try connection.setUserVersion(0)
            _ = try SchemaMigrator.migrate(Self.ladder, on: connection)
        }

        let replayedQueue = try await Self.queue(store)
        #expect(replayedQueue.map(\.seq) == queueAfterFirst.map(\.seq), "a replay renumbered `seq`")
        #expect(replayedQueue == queueAfterFirst, "a replay changed the queue")
        let replayedBinaries = try await Self.binaries(store)
        #expect(
            replayedBinaries.map(\.0) == binariesAfterFirst.map(\.0),
            "a replay lost \(binariesAfterFirst.count - replayedBinaries.count) staged binaries"
        )
    }
}
