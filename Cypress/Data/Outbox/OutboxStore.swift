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
            ":photos": JSONColumn.encode(item.photoPaths) ?? "[]",
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
    public func removePhotoPath(_ path: String, from id: UUID, at date: Date, connection: SQLiteConnection) throws {
        let statement = try connection.cachedStatement("""
            UPDATE outbox
               SET photo_paths = (
                     SELECT COALESCE(json_group_array(value), json('[]'))
                       FROM json_each(outbox.photo_paths)
                      WHERE value <> :path
                   ),
                   updated_at = :now
             WHERE id = :id
            """)
        _ = try statement.bind([":path": path, ":now": date, ":id": id])
        try statement.run()
        _ = try statement.reset()
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
            photoPaths: JSONColumn.decode([String].self, try row.stringIfPresent("photo_paths")) ?? [],
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
