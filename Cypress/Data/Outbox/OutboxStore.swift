import Foundation

/// SQL over the `outbox` table.
///
/// Split from `OutboxQueue` so the queue holds the policy and this holds the statements: the chaos
/// test drives the policy over an in-memory database and needs the two separable.
public struct OutboxStore {
    public init() {}

    /// An outbox row plus the two columns that are implementation, not domain: the FIFO sequence
    /// and the state of the photo phase.
    public struct Record: Sendable, Identifiable {
        public var id: UUID { item.id }
        public let sequence: Int64
        public let item: OutboxItem
        /// The JSON half has been accepted. The row is not `done` until the photos have gone too.
        public let jsonSynced: Bool
        /// Start of the 48 h cap window. Equal to `createdAt` until the user taps retry.
        public let windowStartedAt: Date
        public let nextAttemptAt: Date?
    }

    // MARK: - Writing

    /// Enqueues, idempotently on `clientUUID`.
    ///
    /// "Every mutation is idempotent on a client-generated `clientUUID`, written to the outbox
    /// *first*, and only then attempted against the API" (ARCHITECTURE §4). Enqueuing the same
    /// mutation twice — a double tap, a view model re-run — must not produce two rows, which is why
    /// this is `ON CONFLICT DO NOTHING` on the unique `client_uuid` rather than a plain INSERT.
    @discardableResult
    public func enqueue(_ item: OutboxItem, connection: SQLiteConnection) throws -> Bool {
        let statement = try connection.cachedStatement("""
            INSERT INTO outbox
                (id, kind, client_uuid, payload, photo_paths, state, fail_count,
                 last_error, last_error_code, json_synced, window_started_at,
                 next_attempt_at, created_at, updated_at)
            VALUES
                (:id, :kind, :client, :payload, :photos, :state, :failCount,
                 :lastError, :lastErrorCode, 0, :created,
                 NULL, :created, :updated)
            ON CONFLICT(client_uuid) DO NOTHING
            """)
        _ = try statement.bind([
            ":id": item.id,
            ":kind": item.kind.rawValue,
            ":client": item.clientUUID,
            ":payload": String(data: item.payload, encoding: .utf8) ?? "{}",
            ":photos": JSONColumn.encode(item.photos) ?? "[]",
            ":state": item.state.rawValue,
            ":failCount": item.failCount,
            ":lastError": item.lastError,
            ":lastErrorCode": item.lastErrorCode?.rawValue,
            ":created": item.createdAt,
            ":updated": item.updatedAt
        ])
        try statement.run()
        let inserted = connection.changes > 0
        _ = try statement.reset()
        return inserted
    }

    /// Moves a set of rows to `uploading` so a second drain cannot pick them up.
    public func markUploading(_ ids: [UUID], at date: Date, connection: SQLiteConnection) throws {
        guard !ids.isEmpty else { return }
        let statement = try connection.cachedStatement("""
            UPDATE outbox SET state = 'uploading', updated_at = :now WHERE id = :id AND state = 'pending'
            """)
        for id in ids {
            _ = try statement.reset()
            _ = try statement.bind([":now": date, ":id": id])
            try statement.run()
        }
        _ = try statement.reset()
    }

    /// Records that the JSON half was accepted (`applied` or `duplicate` — both are successes).
    public func markJSONSynced(_ id: UUID, at date: Date, connection: SQLiteConnection) throws {
        let statement = try connection.cachedStatement("""
            UPDATE outbox
               SET json_synced = 1, last_error = NULL, last_error_code = NULL, updated_at = :now
             WHERE id = :id
            """)
        _ = try statement.bind([":now": date, ":id": id])
        try statement.run()
        _ = try statement.reset()
    }

    /// Removes an uploaded binary from the item's pending list.
    ///
    /// Keyed on the path rather than the whole object: the path is what the upload consumed, and a
    /// row cannot stage the same file twice — `VisitPhotoStaging` names the file after the visit.
    /// `json(value)` re-inserts each survivor as an object instead of a quoted string, which is the
    /// difference between rewriting the list and destroying it. Every element is an object by the
    /// time this runs; `AppSchema` v2 converts the rows that were not.
    public func removePhoto(atPath path: String, from id: UUID, at date: Date, connection: SQLiteConnection) throws {
        let statement = try connection.cachedStatement("""
            UPDATE outbox
               SET photo_paths = (
                     SELECT COALESCE(json_group_array(json(value)), json('[]'))
                       FROM json_each(outbox.photo_paths)
                      WHERE json_extract(value, '$.path') <> :path
                   ),
                   updated_at = :now
             WHERE id = :id
            """)
        _ = try statement.bind([":path": path, ":now": date, ":id": id])
        try statement.run()
        _ = try statement.reset()
    }

    /// Takes a staged binary out of every queued mutation still carrying it, because the person who
    /// took it has deleted it (ERRATA E147).
    ///
    /// `removePhoto(atPath:from:)` above is the drain's version and names the row it just uploaded
    /// for. This one does not know the row — a deletion starts from a `photos` id — and it must not
    /// miss one, because the window this closes is a photograph deleted between the shutter and the
    /// drain: remove the file and the row and leave the queue alone, and the next drain finds a
    /// staged path, fails to read it, and retries a photograph that was supposed to be gone. Worse
    /// on a real backend, where it would have already been uploaded.
    ///
    /// The mutation the binary rode on is left in the queue. A visit is not a photograph: the person
    /// asked to delete the picture, not the record of having stood in front of the tree.
    ///
    /// - Returns: how many queued rows were carrying it.
    @discardableResult
    public func discardStagedPhoto(atPath path: String, at date: Date, connection: SQLiteConnection) throws -> Int {
        let statement = try connection.cachedStatement("""
            UPDATE outbox
               SET photo_paths = (
                     SELECT COALESCE(json_group_array(json(value)), json('[]'))
                       FROM json_each(outbox.photo_paths)
                      WHERE json_extract(value, '$.path') <> :path
                   ),
                   updated_at = :now
             WHERE EXISTS (
                     SELECT 1 FROM json_each(outbox.photo_paths)
                      WHERE json_extract(value, '$.path') = :path
                   )
            """)
        _ = try statement.bind([":path": path, ":now": date])
        try statement.run()
        let changed = connection.changes
        _ = try statement.reset()
        return changed
    }

    /// Settles an item whose JSON and photos have both gone.
    ///
    /// The `WHERE` mirrors the table's own CHECK, so a bug that called this early would fail the
    /// update rather than write a `done` row that had not actually been sent.
    public func markDoneIfComplete(_ id: UUID, at date: Date, connection: SQLiteConnection) throws {
        let statement = try connection.cachedStatement("""
            UPDATE outbox
               SET state = 'done', next_attempt_at = NULL, updated_at = :now
             WHERE id = :id AND json_synced = 1 AND json_array_length(photo_paths) = 0
            """)
        _ = try statement.bind([":now": date, ":id": id])
        try statement.run()
        _ = try statement.reset()
    }

    /// Records a failed attempt: the new state, the incremented count, the reason, and when to try
    /// again.
    public func recordFailure(
        _ id: UUID,
        state: OutboxItem.State,
        failCount: Int,
        reason: String,
        code: APIError?,
        nextAttemptAt: Date?,
        at date: Date,
        connection: SQLiteConnection
    ) throws {
        let statement = try connection.cachedStatement("""
            UPDATE outbox
               SET state = :state, fail_count = :failCount, last_error = :reason,
                   last_error_code = :code, next_attempt_at = :next, updated_at = :now
             WHERE id = :id
            """)
        _ = try statement.bind([
            ":state": state.rawValue,
            ":failCount": failCount,
            ":reason": reason,
            ":code": code?.rawValue,
            ":next": nextAttemptAt,
            ":now": date,
            ":id": id
        ])
        try statement.run()
        _ = try statement.reset()
    }

    /// Puts an item back to `pending` without counting an attempt.
    ///
    /// Used when nothing was tried — the photo phase deferred for wi-fi — so the backoff does not
    /// advance for a decision the user made on purpose.
    public func reschedule(_ id: UUID, reason: String?, at date: Date, connection: SQLiteConnection) throws {
        let statement = try connection.cachedStatement("""
            UPDATE outbox
               SET state = 'pending', last_error = :reason, next_attempt_at = NULL, updated_at = :now
             WHERE id = :id
            """)
        _ = try statement.bind([":reason": reason, ":now": date, ":id": id])
        try statement.run()
        _ = try statement.reset()
    }

    /// The visible retry affordance from screen 17.
    ///
    /// Restarts the 48 h cap window and clears the fail count. Without the window reset the item
    /// would move straight back to `failed` on its next attempt, and the button would do nothing —
    /// which is exactly the "silently stuck" behaviour the outbox screen exists to prevent.
    @discardableResult
    public func retry(_ id: UUID, at date: Date, connection: SQLiteConnection) throws -> Bool {
        let statement = try connection.cachedStatement("""
            UPDATE outbox
               SET state = 'pending', fail_count = 0, last_error = NULL, last_error_code = NULL,
                   window_started_at = :now, next_attempt_at = NULL, updated_at = :now
             WHERE id = :id AND state = 'failed'
            """)
        _ = try statement.bind([":now": date, ":id": id])
        try statement.run()
        let changed = connection.changes > 0
        _ = try statement.reset()
        return changed
    }

    @discardableResult
    public func retryAllFailed(at date: Date, connection: SQLiteConnection) throws -> Int {
        let statement = try connection.cachedStatement("""
            UPDATE outbox
               SET state = 'pending', fail_count = 0, last_error = NULL, last_error_code = NULL,
                   window_started_at = :now, next_attempt_at = NULL, updated_at = :now
             WHERE state = 'failed'
            """)
        _ = try statement.bind(date, forName: ":now")
        try statement.run()
        let changed = connection.changes
        _ = try statement.reset()
        return changed
    }

    /// Recovers rows left `uploading` by a process that died mid-drain.
    ///
    /// Nothing disappears silently (screen 17's footnote), and that has to survive a crash: an item
    /// stuck in `uploading` would never be picked up again by the due-items query.
    @discardableResult
    public func recoverInterrupted(at date: Date, connection: SQLiteConnection) throws -> Int {
        let statement = try connection.cachedStatement("""
            UPDATE outbox SET state = 'pending', updated_at = :now WHERE state = 'uploading'
            """)
        _ = try statement.bind(date, forName: ":now")
        try statement.run()
        let changed = connection.changes
        _ = try statement.reset()
        return changed
    }

    // MARK: - Reading

    /// Items due for an attempt, oldest first.
    ///
    /// **FIFO, among items that are due.** Strict FIFO would let one item in backoff block every
    /// item behind it for up to an hour, which loses nothing but delays everything; contributions
    /// are independent and the server dedupes on `client_uuid`, so ordering only has to be stable,
    /// not total. `ORDER BY seq` gives that.
    public func dueItems(now: Date, limit: Int, connection: SQLiteConnection) throws -> [Record] {
        let statement = try connection.cachedStatement("""
            SELECT * FROM outbox
             WHERE state = 'pending'
               AND (next_attempt_at IS NULL OR next_attempt_at <= :now)
             ORDER BY seq
             LIMIT :limit
            """)
        _ = try statement.bind([":now": now, ":limit": limit])
        return try statement.fetchAll(Self.decode)
    }

    /// Everything, newest activity first. Screen 17 renders this whole list.
    public func allItems(connection: SQLiteConnection) throws -> [Record] {
        let statement = try connection.cachedStatement("SELECT * FROM outbox ORDER BY seq")
        return try statement.fetchAll(Self.decode)
    }

    public func item(id: UUID, connection: SQLiteConnection) throws -> Record? {
        let statement = try connection.cachedStatement("SELECT * FROM outbox WHERE id = :id")
        _ = try statement.bind(id, forName: ":id")
        return try statement.fetchOne(Self.decode)
    }

    /// Drops rows that have been `done` for longer than `age`.
    ///
    /// Screen 17 shows "Synced earlier today", so `done` rows are not deleted on completion — they
    /// are the receipt. They are swept later.
    @discardableResult
    public func pruneCompleted(olderThan age: TimeInterval, now: Date, connection: SQLiteConnection) throws -> Int {
        let statement = try connection.cachedStatement("""
            DELETE FROM outbox WHERE state = 'done' AND updated_at < :cutoff
            """)
        _ = try statement.bind(now.addingTimeInterval(-age), forName: ":cutoff")
        try statement.run()
        let changed = connection.changes
        _ = try statement.reset()
        return changed
    }

    /// Takes a deleted account out of the queue (RULINGS R3, and the half a deletion path is most
    /// likely to forget).
    ///
    /// A mutation lives in the outbox between being written and being applied, and that gap can
    /// straddle anything — `LocalAPI.adoptRowsWrittenAfterTheClaim` documents the same gap in the
    /// other direction, where a row queued before sign-in lands after it. Straddling a *deletion* is
    /// worse than straddling a claim: an item that drains afterwards re-creates, under the name of an
    /// account that no longer exists, exactly what the deletion just removed.
    ///
    /// The two kinds of row get the two answers R3 gives, for the same reasons:
    ///
    /// 1. **A queued favourite or private reminder is discarded.** It is a mutation whose only
    ///    possible destination is a row that no longer exists and may not be re-created: an
    ///    ownerless one fails the `CHECK`, and a device-owned one is the re-homing R3 refused. There
    ///    is nothing left for it to mean, so the row goes rather than failing forever in the queue
    ///    where screen 17 would keep reporting it.
    /// 2. **A queued contribution stays, with the account stripped out of its payload.** The
    ///    contribution itself survives deletion — that is §3.12 — but it must arrive anonymous, and
    ///    an untouched payload would re-attribute it on drain, silently undoing the anonymization for
    ///    exactly the rows that were in flight. `json_remove` leaves the payload byte-identical to
    ///    one written before sign-in, because `JSONEncoder` omits a nil `userID` rather than writing
    ///    a null; the mutation's `client_uuid`, its photos, its retry state and its place in the FIFO
    ///    are untouched.
    ///
    /// **And rule 2 is why the tombstone is keyed on `client_uuid`** (`AppSchema` v13, ERRATA — see
    /// `docs/errata-pending/deletion-tombstone.md`). A stripped payload lands as a row with
    /// `user_id IS NULL` and a `device_id`, which is D9's description of *this device's unclaimed
    /// work* — so `claimDevice` adopts it onto the next account signed in on the phone, and the
    /// person who asked to be unlinked is relinked by the tail of their own queue. The row cannot be
    /// marked when it is stored, because at deletion time it does not exist and after the drain the
    /// deletion is long over. It can be marked *now*, by the key it will be stored under: the
    /// `client_uuid` is in the payload, it is the same value the eventual row carries, and the
    /// tombstone is simply waiting for it. This is the case a tombstone written as a column on the
    /// four tables would have missed while looking complete.
    ///
    /// **Every state, not just the pending ones.** A `done` row is screen 17's receipt, and its
    /// payload is a second copy of the attribution sitting on disk — anonymizing the table and
    /// leaving the receipt would leave the account's id on the device. A `done` favourite's receipt
    /// is worse still: it describes, by name, a tree this person kept, which is precisely the record
    /// R3 says nobody but they could read.
    ///
    /// **`eraseEverything` collapses the two cases into one.** Rule 2 above exists because the
    /// contribution survives deletion; through the destructive door it does not, so a queued one has
    /// nothing left to arrive as. It is discarded with the rest, and `anonymized` comes back zero.
    /// Leaving it to land anonymously would be the loudest possible version of the failure the whole
    /// queue clause guards against: a person who chose "erase everything" watching a check-in appear
    /// on a tree the next time the phone found wifi.
    ///
    /// Both statements are `UPDATE`/`DELETE` whose `WHERE` stops matching once they have run, so a
    /// second call over the same account changes nothing.
    @discardableResult
    public func forgetAccount(
        userID: UUID,
        choice: AccountDeletionChoice,
        at date: Date,
        connection: SQLiteConnection
    ) throws -> (discarded: Int, anonymized: Int) {
        // The two exclusively-owned kinds. Their payload carries a `ReminderOwner`/`FavoriteOwner`,
        // encoded as a single-key object — `{"user": …}` or `{"device": …}` — so `$.owner.user`
        // matches an account-owned mutation and cannot match a device-owned one.
        let discard = try connection.cachedStatement("""
            DELETE FROM outbox
             WHERE kind IN ('favorite_toggle','private_reminder')
               AND json_extract(payload, '$.owner.user') = :user COLLATE NOCASE
            """)
        _ = try discard.bind([":user": userID.uuidString])
        try discard.run()
        let discarded = connection.changes
        _ = try discard.reset()

        // The four append-only contribution kinds. `userID` is a top-level key on each of their
        // payloads (`Visit`, `TreeObservation`, `TreeMeasurement`, `CareEvent` all flatten
        // `Attribution` into `userID` + `deviceID`).
        //
        // One statement or the other, chosen by the door, over exactly the same set of rows — so
        // there is no arrangement of the two in which a queued contribution is both anonymized and
        // discarded, and none in which it is neither.
        let contributions = "kind IN ('visit','observation','measurement','care_event')"
        let mine = "json_extract(payload, '$.userID') = :user COLLATE NOCASE"

        switch choice {
        case .leaveRecords:
            // The tombstone for a row that does not exist yet, written before the payload stops
            // naming the account — the same ordering `AccountDeletion.anonymizeContributions` keeps,
            // and for the same reason: `\(mine)` is the predicate, and the statement below is what
            // stops it matching.
            let tombstone = try connection.cachedStatement("""
                INSERT OR IGNORE INTO anonymized_contributions (client_uuid, anonymized_at)
                SELECT json_extract(payload, '$.clientUUID'), :now
                  FROM outbox
                 WHERE \(contributions) AND \(mine)
                   AND json_extract(payload, '$.clientUUID') IS NOT NULL
                """)
            _ = try tombstone.bind([":now": date, ":user": userID.uuidString])
            try tombstone.run()
            _ = try tombstone.reset()

            let anonymize = try connection.cachedStatement("""
                UPDATE outbox
                   SET payload = json_remove(payload, '$.userID'), updated_at = :now
                 WHERE \(contributions) AND \(mine)
                """)
            _ = try anonymize.bind([":now": date, ":user": userID.uuidString])
            try anonymize.run()
            let anonymized = connection.changes
            _ = try anonymize.reset()
            return (discarded: discarded, anonymized: anonymized)

        case .eraseEverything:
            // The staged JPEGs these rows point at are removed by `LocalAPI.deleteAccount` before
            // this transaction opens; `AccountDeletion.photoBytes` reads them from this same
            // `photo_paths` column, which is why that read has to happen first.
            let erase = try connection.cachedStatement("""
                DELETE FROM outbox WHERE \(contributions) AND \(mine)
                """)
            _ = try erase.bind([":user": userID.uuidString])
            try erase.run()
            let erased = connection.changes
            _ = try erase.reset()
            return (discarded: discarded + erased, anonymized: 0)
        }
    }

    public func counts(connection: SQLiteConnection) throws -> [OutboxItem.State: Int] {
        let statement = try connection.cachedStatement("SELECT state, COUNT(*) AS n FROM outbox GROUP BY state")
        let rows = try statement.fetchAll { row in
            (state: try row.value("state", OutboxItem.State.self), count: try row.int("n"))
        }
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.state, $0.count) })
    }

    // MARK: - Decoding

    static func decode(_ row: SQLiteRow) throws -> Record {
        let item = OutboxItem(
            id: try row.uuid("id"),
            kind: try row.value("kind", OutboxItem.Kind.self),
            clientUUID: try row.uuid("client_uuid"),
            payload: Data((try row.string("payload")).utf8),
            // `OutboxPhoto` decodes the pre-shot-type bare-string form too, so a row that somehow
            // escaped the v2 migration still yields its binaries instead of an empty list.
            photos: JSONColumn.decode([OutboxPhoto].self, try row.stringIfPresent("photo_paths")) ?? [],
            state: try row.value("state", OutboxItem.State.self),
            failCount: try row.int("fail_count"),
            lastError: try row.stringIfPresent("last_error"),
            lastErrorCode: try row.enumIfPresent("last_error_code", APIError.self),
            createdAt: try row.date("created_at"),
            updatedAt: try row.date("updated_at")
        )
        return Record(
            sequence: try row.int64("seq"),
            item: item,
            jsonSynced: try row.bool("json_synced"),
            windowStartedAt: try row.date("window_started_at"),
            nextAttemptAt: try row.dateIfPresent("next_attempt_at")
        )
    }
}
