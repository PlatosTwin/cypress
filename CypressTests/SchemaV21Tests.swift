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
/// `theStagedBinariesSurviveTheRebuild` fails with **2 issues** — the binaries are gone, and the
/// counter still claims them. The other three tests stay green under that revert, and correctly so:
/// they are about the version ladder, the queue rows and the vocabulary, none of which the cascade
/// touches. `theQueueSurvivesTheRebuild` is the negative control that the cascade *only* reaches
/// the child table.
@Suite("AppSchema · v21")
struct SchemaV21Tests {

    private static let moment = Date(timeIntervalSince1970: 1_790_000_000)

    /// The version this file is about, read from the code rather than written down twice.
    private static var version: Int32 { 21 }

    // MARK: - The fixture

    /// One queued item as it sits in a v20 database, and the binaries it still owes.
    private struct QueuedItem {
        let id: UUID
        let clientUUID: UUID
        let kind: String
        let state: String
        let failCount: Int
        let lastError: String?
        let binaries: [UUID]
    }

    private static func fixture() -> [QueuedItem] {
        [
            // A visit with two photographs still staged: the row the cascade destroys.
            QueuedItem(
                id: UUID(), clientUUID: UUID(), kind: "visit", state: "pending",
                failCount: 0, lastError: nil, binaries: [UUID(), UUID()]
            ),
            // A failed species correction carrying error text and a retry count, so "the queue came
            // across" is a claim about more than ids.
            QueuedItem(
                id: UUID(), clientUUID: UUID(), kind: "species_correction", state: "failed",
                failCount: 3, lastError: "the service said no", binaries: []
            ),
            // A settled item. `done` is only legal with nothing outstanding, which is v1's invariant
            // and the one a mis-copied counter breaks.
            QueuedItem(
                id: UUID(), clientUUID: UUID(), kind: "photo_withdrawal", state: "done",
                failCount: 0, lastError: nil, binaries: []
            ),
            // One binary on its own item, so the counter is not uniformly 0 or 2.
            QueuedItem(
                id: UUID(), clientUUID: UUID(), kind: "observation", state: "pending",
                failCount: 1, lastError: nil, binaries: [UUID()]
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

            for (index, item) in items.enumerated() {
                let error = item.lastError.map { "'\($0)'" } ?? "NULL"
                // `local_applied = 1` on every row, because `done` requires it and the settled item
                // above is one. The two sinks are v15's and v21 does not touch them.
                try connection.execute("""
                    INSERT INTO outbox
                        (seq, id, kind, client_uuid, payload, photo_paths, photos_outstanding,
                         state, fail_count, last_error, local_applied, remote_sent,
                         window_started_at, created_at, updated_at)
                    VALUES (\(index + 1),'\(item.id.uuidString)','\(item.kind)',
                            '\(item.clientUUID.uuidString)','{}','[]',0,
                            '\(item.state)',\(item.failCount),\(error),1,0,
                            '\(stamp)','\(stamp)','\(stamp)');
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

    /// The queue as comparable values, in `seq` order.
    private static func queue(
        _ store: CypressStore
    ) async throws -> [(Int, String, String, String, Int, String?, Int)] {
        try await store.queue.read { connection in
            let statement = try connection.prepare("""
                SELECT seq, id, kind, state, fail_count, last_error, photos_outstanding
                  FROM outbox ORDER BY seq
                """)
            defer { statement.finalize() }
            return try statement.fetchAll {
                (
                    try $0.int("seq"), try $0.string("id"), try $0.string("kind"),
                    try $0.string("state"), try $0.int("fail_count"),
                    try $0.stringIfPresent("last_error"), try $0.int("photos_outstanding")
                )
            }
        }
    }

    // MARK: - 1. The ladder

    /// **v21 runs, alone, on a database that already holds a queue.**
    ///
    /// This file is the newest version's, so it carries the claim `SchemaV19Tests` handed to
    /// `SchemaV20Tests` and `SchemaV20Tests` now hands here: that `AppSchema.currentVersion` is
    /// what this file is written about. When v22 lands, this test filters its ladder to `<= 21` and
    /// the `currentVersion` expectation moves to v22's file.
    @Test("a v20 database with a queue in it is carried to 21 by exactly one migration")
    func aV20DatabaseRunsOnlyV21() async throws {
        let store = try await Self.v20Database(Self.fixture())

        let applied = try await store.queue.write { connection in
            try SchemaMigrator.migrate(AppSchema.migrations, on: connection)
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
        #expect(version == AppSchema.currentVersion, "user_version is \(version)")
        #expect(
            AppSchema.currentVersion == Self.version,
            """
            `AppSchema.currentVersion` is \(AppSchema.currentVersion) and this file is written \
            about \(Self.version). One of the two moved without the other — the fixture above still \
            opens at 20 and no longer proves what it says it proves
            """
        )
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
            try SchemaMigrator.migrate(AppSchema.migrations, on: connection)
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
        let counters = try await Self.queue(store).map { ($0.1, $0.6) }
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

    /// **The queue came across column for column, in `seq` order.**
    ///
    /// The negative control for the test above: the cascade reaches the child table and nothing
    /// else, so this stays green under the revert that turns that one red. It is here for the
    /// rebuild's *own* failure modes — a column dropped from the `INSERT … SELECT`, a `seq` not
    /// carried (which would renumber the FIFO order the drain reads), error text or a retry count
    /// left behind.
    @Test("the queue itself is carried across unchanged, seq order included")
    func theQueueSurvivesTheRebuild() async throws {
        let store = try await Self.v20Database(Self.fixture())
        let before = try await Self.queue(store)

        _ = try await store.queue.write { connection in
            try SchemaMigrator.migrate(AppSchema.migrations, on: connection)
        }

        let after = try await Self.queue(store)
        #expect(after.map(\.0) == before.map(\.0), "seq changed: \(before.map(\.0)) → \(after.map(\.0))")
        #expect(after.map(\.1) == before.map(\.1), "the rows changed identity or order")
        #expect(after.map(\.2) == before.map(\.2), "a kind was rewritten by the rebuild")
        #expect(after.map(\.3) == before.map(\.3), "a state was rewritten by the rebuild")
        #expect(after.map(\.4) == before.map(\.4), "a retry count was lost")
        #expect(after.map(\.5) == before.map(\.5), "error text was lost")
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
            try SchemaMigrator.migrate(AppSchema.migrations, on: connection)
        }

        let queued = try await Self.queue(store)
        #expect(
            queued.map(\.1) == items.map(\.id.uuidString),
            """
            the migration left \(queued.count) rows in the queue (\(queued.map(\.2))); only the \
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
            try SchemaMigrator.migrate(AppSchema.migrations, on: connection)
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
            _ = try SchemaMigrator.migrate(AppSchema.migrations, on: connection)
        }

        let replayedQueue = try await Self.queue(store)
        #expect(replayedQueue.map(\.0) == queueAfterFirst.map(\.0), "a replay renumbered `seq`")
        #expect(replayedQueue.map(\.1) == queueAfterFirst.map(\.1), "a replay changed the queue")
        let replayedBinaries = try await Self.binaries(store)
        #expect(
            replayedBinaries.map(\.0) == binariesAfterFirst.map(\.0),
            "a replay lost \(binariesAfterFirst.count - replayedBinaries.count) staged binaries"
        )
    }
}
