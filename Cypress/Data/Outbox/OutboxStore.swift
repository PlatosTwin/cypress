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
        /// The mutation is committed to this device's own tables. The row is not `done` until the
        /// photos have gone too.
        ///
        /// This is what the column called `json_synced` always meant — `AppSchema` v15 renamed it
        /// and put `remoteSent` beside it, because the drain was doing two jobs under one name
        /// (ERRATA E261 §2, RULINGS R72 §1).
        public let locallyApplied: Bool
        /// The mutation has been accepted by a server. False until a drain with a send sink wired
        /// carries it across — and `DataLayer.boot` wires one, since #158's wiring round.
        public let remoteSent: Bool
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
        try enqueue(item, locallyApplied: false, connection: connection)
    }

    /// Enqueues a mutation this device has **already committed**, from inside the transaction that
    /// committed it (spec §3.4's nine).
    ///
    /// ── Why these rows are born `local_applied = 1` ────────────────────────────────────────────
    ///
    /// For the six original kinds the drain *is* the local commit: nothing has touched this device's
    /// tables when the row is written, `OutboxQueue`'s apply sink runs `LocalAPI.sync`, and that
    /// call is what puts the visit on the tree (ERRATA E261 §2). §3.4's nine are the other shape.
    /// `LocalAPI.addTree` runs a proximity dedupe, strips a photograph's metadata, mints a tree and
    /// returns it; `deletePhoto` tombstones a row behind two ownership gates and then removes files;
    /// `correctSpecies` supersedes an assertion chain. Each is performed **first**, because the
    /// caller needs the answer, and each writes its queue row inside its own transaction — so either
    /// both happened or neither did, and there is no window in which the mutation is committed and
    /// the row that would send it is not.
    ///
    /// Marking them applied is a statement of fact rather than an optimization: the mutation is on
    /// this device by the time the row exists. `OutboxQueue.drain` already skips the apply half for
    /// such a row (`live.filter { !$0.locallyApplied }`), so what is left is the send, which is the
    /// half that was missing. Leaving them at 0 would offer them to the apply sink, and applying one
    /// a second time is a second correction, a second flag, a second withdrawal —
    /// `LocalAPI.apply(_:)` refuses them outright for that reason.
    ///
    /// **This is not a backfill and must never become one.** It writes one row for one mutation at
    /// the moment that mutation happens. Nothing sweeps rows that already exist into the queue; see
    /// `AppSchema` v17.
    ///
    /// **The `Bool` says whether a row was written, and every caller today discards it, on an
    /// invariant worth stating rather than assuming**: the `ON CONFLICT(client_uuid) DO NOTHING`
    /// arm cannot fire for these ten. Nine mint a fresh `UUID()` at the call site, and `addTree`
    /// reuses `TreeDraft.clientUUID`, which `community_trees.client_uuid TEXT NOT NULL UNIQUE` has
    /// already refused in the same transaction if it is a repeat. A future kind that keys on
    /// something a caller can hand in twice inherits a silent drop instead — so it reads this
    /// result, or it does not use this method.
    @discardableResult
    public func enqueueLocallyApplied(_ item: OutboxItem, connection: SQLiteConnection) throws -> Bool {
        try enqueue(item, locallyApplied: true, connection: connection)
    }

    @discardableResult
    private func enqueue(
        _ item: OutboxItem,
        locallyApplied: Bool,
        connection: SQLiteConnection
    ) throws -> Bool {
        let statement = try connection.cachedStatement("""
            INSERT INTO outbox
                (id, kind, client_uuid, payload, state, fail_count,
                 last_error, last_error_code, local_applied, remote_sent, window_started_at,
                 next_attempt_at, created_at, updated_at)
            VALUES
                (:id, :kind, :client, :payload, :state, :failCount,
                 :lastError, :lastErrorCode, :localApplied, 0, :created,
                 NULL, :created, :updated)
            ON CONFLICT(client_uuid) DO NOTHING
            """)
        _ = try statement.bind([
            ":localApplied": locallyApplied ? 1 : 0,
            ":id": item.id,
            ":kind": item.kind.rawValue,
            ":client": item.clientUUID,
            ":payload": String(data: item.payload, encoding: .utf8) ?? "{}",
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
        // **Only when the row is new.** The `DO NOTHING` arm means this `client_uuid` was already
        // queued, and staging its binaries a second time would give one mutation two copies of every
        // photograph — the duplicate the whole per-photo model exists to make impossible.
        if inserted {
            // `sendable: true` — these are binaries staged now, which is exactly what RULINGS R77
            // permits to travel. v18's migrated rows are the ones marked 0, by that migration.
            try stagePhotos(item.photos, for: item.id, sendable: true, at: item.createdAt, connection: connection)
        }
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

    /// Records that the apply sink committed the mutation to this device (`applied` or `duplicate`
    /// — both are successes).
    public func markLocallyApplied(_ id: UUID, at date: Date, connection: SQLiteConnection) throws {
        let statement = try connection.cachedStatement("""
            UPDATE outbox
               SET local_applied = 1, last_error = NULL, last_error_code = NULL, updated_at = :now
             WHERE id = :id
            """)
        _ = try statement.bind([":now": date, ":id": id])
        try statement.run()
        _ = try statement.reset()
    }

    /// Records that a server accepted the mutation (`applied` or `duplicate` — the server dedupes on
    /// `client_uuid` exactly as the local unique index does, so both are successes on this side too).
    ///
    /// The `WHERE` carries `local_applied = 1` rather than trusting the caller, which is the same
    /// defense `markDoneIfComplete` takes: the table's own CHECK would reject the write, and an
    /// `UPDATE` that matches nothing is a better failure than a transaction that aborts a whole
    /// drain. Apply is first and unconditional (RULINGS R72 §1); nothing may be sent that this
    /// device has not already committed.
    public func markRemotelySent(_ id: UUID, at date: Date, connection: SQLiteConnection) throws {
        let statement = try connection.cachedStatement("""
            UPDATE outbox
               SET remote_sent = 1, last_error = NULL, last_error_code = NULL, updated_at = :now
             WHERE id = :id AND local_applied = 1
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
            DELETE FROM outbox_photos WHERE outbox_id = :id AND path = :path
            """)
        _ = try statement.bind([":path": path, ":id": id])
        try statement.run()
        _ = try statement.reset()
        try touch(id, at: date, connection: connection)
    }

    /// Bumps an item's `updated_at` without changing anything else, for the changes that now happen
    /// in `outbox_photos` and would otherwise leave the item looking untouched on screen 17.
    private func touch(_ id: UUID, at date: Date, connection: SQLiteConnection) throws {
        let statement = try connection.cachedStatement(
            "UPDATE outbox SET updated_at = :now WHERE id = :id"
        )
        _ = try statement.bind([":now": date, ":id": id])
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
    /// ── It matches on the photograph's **id** as well as its staged path, and the id is the arm
    /// that matters ────────────────────────────────────────────────────────────────────────────
    ///
    /// Keying on `path` alone was correct while a binary was only ever staged. It stopped being
    /// correct when `AppSchema` v18 gave a binary a second half of its life: `markPhotoApplied`
    /// sets `path = NULL` once the apply has moved the bytes into the container, so from that
    /// moment nothing in this table can be found by path at all.
    ///
    /// **What that cost, measured in #116's review rather than reasoned about.** A photograph
    /// withdrawn after its apply left its `outbox_photos` row behind forever. `sendablePhotos`
    /// refused it (correctly — it is tombstoned), so phase B3 skipped the item entirely and never
    /// even recorded a reason; `photos_outstanding` stayed at 1, so `markDoneIfComplete` never
    /// matched; and the item sat in `uploading` across five consecutive drains still displaying
    /// "One photo hasn't gone through yet" — a sentence promising a photograph in flight, about one
    /// the contributor had deleted. The retry button could not clear it either, because `retry`
    /// requires `failed` and this row was never failed. It was reachable in two ordinary steps: one
    /// send fails for want of signal, then the person deletes the picture.
    ///
    /// So the match is `photo_id = :photo OR path = :path`, and the two arms are the binary's two
    /// lives. `:path` is still needed on its own: before the apply there is no `photo_id` to match.
    ///
    /// - Returns: how many queued rows were carrying it.
    @discardableResult
    public func discardPhoto(
        id photoID: UUID,
        stagedPath path: String?,
        at date: Date,
        connection: SQLiteConnection
    ) throws -> Int {
        // The items that were carrying it, read before the delete because after it there is nothing
        // left to name them. The return value is a count of *rows carrying the binary*, which is
        // what the caller reports, and it stays that even though the delete is now on another table.
        let owners = try connection.cachedStatement("""
            SELECT DISTINCT outbox_id FROM outbox_photos
             WHERE photo_id = :photo COLLATE NOCASE
                OR (:path IS NOT NULL AND path = :path)
            """)
        _ = try owners.bind([":photo": photoID, ":path": path])
        let ids = try owners.fetchAll { try $0.uuid("outbox_id") }
        _ = try owners.reset()

        let statement = try connection.cachedStatement("""
            DELETE FROM outbox_photos
             WHERE photo_id = :photo COLLATE NOCASE
                OR (:path IS NOT NULL AND path = :path)
            """)
        _ = try statement.bind([":photo": photoID, ":path": path])
        try statement.run()
        _ = try statement.reset()

        for id in ids { try touch(id, at: date, connection: connection) }
        return ids.count
    }

    /// The `client_uuid`s this device is still holding for a server, for `DELETE /me`.
    ///
    /// `me.go` tombstones these "even though this service has never seen them", so that an item
    /// queued on Tuesday against an account deleted on Wednesday cannot resurrect it on Thursday.
    /// `RemoteAPI.pendingOutboxKeys` is the seam that asks for them and it **refuses** rather than
    /// sending `[]`, because an empty array is the claim that nothing is queued and RULINGS R3's
    /// stated failure mode is deleting differently from what was asked. This is the statement that
    /// answers it honestly.
    ///
    /// ── Which rows count as still queued, which is not "every row" ─────────────────────────────
    ///
    /// `remote_sent = 0` — a row a server has accepted needs no tombstone, it needs the ordinary
    /// deletion — **and** `state <> 'done'`. The second predicate is the one worth reading twice: a
    /// `done` row with `remote_sent = 0` is every outbox row on every build shipped so far, and it
    /// will never be attempted again (`dueItems` only returns `pending`), so it cannot arrive after
    /// the deletion and does not need a mark to stop it. `failed` rows *are* included: the retry
    /// button restarts them, so they can still arrive.
    public func unsentClientUUIDs(connection: SQLiteConnection) throws -> [UUID] {
        let statement = try connection.cachedStatement("""
            SELECT client_uuid FROM outbox
             WHERE remote_sent = 0 AND state <> 'done'
             ORDER BY seq
            """)
        return try statement.fetchAll { try $0.uuid("client_uuid") }
    }

    /// Settles an item whose sinks and photos have all taken it.
    ///
    /// The `WHERE` mirrors the table's own CHECK, so a bug that called this early would fail the
    /// update rather than write a `done` row that had not actually been applied.
    ///
    /// - Parameter requiringRemoteSend: whether a send sink is wired. It is a parameter and not a
    ///   column predicate because whether a send is owed is a fact about the composition root, not
    ///   about the row: `AppSchema` v15's `done` CHECK deliberately does not name `remote_sent`,
    ///   since every row on every shipped build is locally applied and has never been sent anywhere.
    ///   With no sink wired this is `false` and the statement is the one that shipped, with v15's
    ///   rename applied to the column it reads.
    ///
    ///   **It has no default, deliberately.** The unsafe answer is `false`, and this parameter is
    ///   the entire guard against a row that was never sent settling `done` — after which it is
    ///   never due again, so it is never sent. A defaulted `false` would let a future caller forget
    ///   it and compile; requiring it makes forgetting it a compile error. Same argument as
    ///   `OutboxSendSink` carrying no `uploadPhoto`, and ERRATA E125 is what both are paying for.
    ///
    /// - Returns: whether the row actually settled. The `UPDATE` is conditional, so a caller that
    ///   counts settlements has to count what it matched rather than the fact that it ran.
    @discardableResult
    public func markDoneIfComplete(
        _ id: UUID,
        requiringRemoteSend: Bool,
        at date: Date,
        connection: SQLiteConnection
    ) throws -> Bool {
        let sent = requiringRemoteSend ? " AND remote_sent = 1" : ""
        // **`last_error` is cleared here, and that is not tidiness.** A settled row kept whatever
        // sentence its last failure wrote — "The note is sent. One photo hasn't gone through yet."
        // on an item where the photograph subsequently *did* go. Screen 17 does not draw a sentence
        // on a synced receipt, so it was invisible; it stopped being invisible the moment anything
        // read `lastError` off a `done` row, and a stale sentence is worse than none because it
        // reads as current. Noted in #116's r3 review as cosmetic and fixed here rather than left
        // in a PR description that stops existing at merge.
        let statement = try connection.cachedStatement("""
            UPDATE outbox
               SET state = 'done', next_attempt_at = NULL,
                   last_error = NULL, last_error_code = NULL, updated_at = :now
             WHERE id = :id AND local_applied = 1 AND photos_outstanding = 0\(sent)
            """)
        _ = try statement.bind([":now": date, ":id": id])
        try statement.run()
        let settled = connection.changes > 0
        _ = try statement.reset()
        return settled
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
    /// which is exactly the "silently stuck" behavior the outbox screen exists to prevent.
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
    /// Nothing disappears silently — screen 17's rule, no longer printed on it (copy audit,
    /// 2026-08-23) and no less binding — and that has to survive a crash: an item stuck in
    /// `uploading` would never be picked up again by the due-items query.
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
        return try attachStagedPhotos(to: statement.fetchAll(Self.decode), connection: connection)
    }

    /// Everything, newest activity first. Screen 17 renders this whole list.
    public func allItems(connection: SQLiteConnection) throws -> [Record] {
        let statement = try connection.cachedStatement("SELECT * FROM outbox ORDER BY seq")
        return try attachStagedPhotos(to: statement.fetchAll(Self.decode), connection: connection)
    }

    public func item(id: UUID, connection: SQLiteConnection) throws -> Record? {
        let statement = try connection.cachedStatement("SELECT * FROM outbox WHERE id = :id")
        _ = try statement.bind(id, forName: ":id")
        guard let record = try statement.fetchOne(Self.decode) else { return nil }
        return try attachStagedPhotos(to: [record], connection: connection).first
    }

    /// Fills in each record's **staged** binaries — the ones an apply still owes.
    ///
    /// `OutboxItem.photos` has always meant "binaries this row has not committed yet", and it still
    /// does; what changed in `AppSchema` v18 is where they live. Only `state = 'pending'` rows are
    /// attached: an `applied` binary has been ingested into the app container, its staged file is
    /// gone, and offering it to the apply sink again would write the photograph twice — which is
    /// the defect ERRATA **E264** says a second sink cannot be built around. The send half reads
    /// `sendablePhotos(for:)` instead, which is the other state.
    ///
    /// One statement per record rather than one `IN` over all of them: a drain batch is 20 rows and
    /// the index on `outbox_id` makes each lookup a seek, so the loop costs less than building the
    /// list, and it keeps the ordering of `photos` per item obvious.
    private func attachStagedPhotos(to records: [Record], connection: SQLiteConnection) throws -> [Record] {
        guard !records.isEmpty else { return records }
        let statement = try connection.cachedStatement("""
            SELECT id, path, shot_type FROM outbox_photos
             WHERE outbox_id = :item AND state = 'pending'
             ORDER BY rowid
            """)
        return try records.map { record in
            _ = try statement.reset()
            _ = try statement.bind(record.id, forName: ":item")
            let photos = try statement.fetchAll { row in
                OutboxPhoto(
                    id: try row.uuid("id"),
                    path: try row.string("path"),
                    shotType: try row.value("shot_type", ShotType.self)
                )
            }
            var item = record.item
            item.photos = photos
            return Record(
                sequence: record.sequence,
                item: item,
                locallyApplied: record.locallyApplied,
                remoteSent: record.remoteSent,
                windowStartedAt: record.windowStartedAt,
                nextAttemptAt: record.nextAttemptAt
            )
        }
    }

    /// One binary's durable row, which is what a per-photo state machine needs and
    /// `OutboxPhoto` deliberately is not.
    ///
    /// `OutboxPhoto` is the *staged descriptor* a feature hands to `enqueue` — a file and a framing.
    /// This is the row that outlives it: it keeps its identity after the file is consumed, it names
    /// the local `photos` row the apply wrote, and it says whether a send is owed. Keeping the two
    /// apart is why `Core` still compiles with no notion of a send (ARCHITECTURE §2).
    public struct PhotoRow: Sendable, Equatable {
        public var id: UUID
        public var outboxID: UUID
        /// NULL once the apply has consumed the staged file.
        public var path: String?
        public var shotType: ShotType
        /// The local `photos.id` the apply minted. The source a send reads.
        public var photoID: UUID?
        /// `photos.local_path` — where the apply put the binary inside the app container.
        ///
        /// This is the answer to the first of the three things ERRATA **E264** says a send needs and
        /// did not have: "a source the remote can still read after ingest". `path` above is the
        /// staged file and is gone by then; this one is the copy that outlived it.
        public var containerPath: String?
        public var isApplied: Bool
        /// RULINGS **R77**: false for every binary `AppSchema` v18 migrated, which stays on device.
        public var isSendable: Bool
        public var failCount: Int
    }

    /// The binaries whose local commit is done and whose send is still owed.
    ///
    /// `sendable = 1` is R77 in the `WHERE`: a binary staged before the send path existed is
    /// applied, deleted, and never offered here. `photo_id IS NOT NULL` is redundant against the
    /// table's own CHECK and is written anyway, because this is the statement whose result is handed
    /// to a network call and the alternative to a redundant predicate is a force-unwrap.
    /// **`sendable = 1` here is the second of two R77 gates, and it is not redundant.** The first is
    /// `settleAppliedPhoto`, which deletes a local-only binary the moment it is applied, so in the
    /// ordinary flow no `sendable = 0` row ever reaches this statement. Measured, when red-proving:
    /// removing *this* predicate alone changes nothing, because the delete has already run — and
    /// removing the delete alone leaves the binary unsent, because this predicate catches it. Each
    /// covers the other's failure, which is why both stay: R77 is a ruling about photographs
    /// leaving the device, and one guard for it is one edit away from none.
    ///
    /// **The `NOT EXISTS` is a gate, not tidiness.** A photograph the contributor deleted between
    /// the apply and the send has a tombstoned `photos` row, and sending it anyway would publish a
    /// picture somebody had already taken back — ERRATA **E147**'s harm, arriving through the one
    /// door that opens *after* the deletion gate has run.
    ///
    /// Written as `NOT EXISTS (… deleted_at IS NOT NULL)` rather than as a join requiring a live
    /// row, because those differ on the case that matters: a binary whose `photos` row is missing
    /// entirely is not a withdrawn photograph, it is a queue whose apply sink is not `LocalAPI` —
    /// which is every test double, and refusing those would make this path untestable except
    /// end-to-end. Absent means "nothing says it was withdrawn"; present-and-tombstoned means it
    /// was.
    public func sendablePhotos(for id: UUID, connection: SQLiteConnection) throws -> [PhotoRow] {
        let statement = try connection.cachedStatement("""
            SELECT * FROM outbox_photos
             WHERE outbox_id = :item AND state = 'applied' AND sendable = 1
               AND photo_id IS NOT NULL AND container_path IS NOT NULL
               AND NOT EXISTS (
                     SELECT 1 FROM photos
                      WHERE photos.id = outbox_photos.photo_id AND photos.deleted_at IS NOT NULL
                   )
             ORDER BY rowid
            """)
        _ = try statement.bind(id, forName: ":item")
        return try statement.fetchAll(Self.decodePhotoRow)
    }

    /// Drops the queue rows of binaries whose photograph has been withdrawn.
    ///
    /// **The drain's own half of the F1 repair, and the half that does not depend on which door the
    /// deletion came through.** `LocalAPI.deletePhoto` calls `discardPhoto`, which is the direct
    /// route; this is what makes the queue converge anyway when a row is tombstoned by any other
    /// means — an operator takedown reaching this device, a future sync-down, a repair script.
    /// Without it the drain's correct refusal to send a withdrawn photograph (`sendablePhotos`)
    /// becomes a permanent wedge: the row is never sendable and never removed, so the item's
    /// `photos_outstanding` never reaches zero and it can never settle.
    ///
    /// Only `applied` rows, and only against a tombstone. A `pending` row still has a staged file
    /// and is the apply's business, and a photograph that simply has no `photos` row yet is not a
    /// withdrawn one — the same distinction `sendablePhotos` draws, written the same way so the two
    /// cannot disagree about what "withdrawn" means.
    ///
    /// - Returns: how many rows were dropped.
    @discardableResult
    public func discardWithdrawnPhotos(for id: UUID, at date: Date, connection: SQLiteConnection) throws -> Int {
        let statement = try connection.cachedStatement("""
            DELETE FROM outbox_photos
             WHERE outbox_id = :item AND state = 'applied'
               AND EXISTS (
                     SELECT 1 FROM photos
                      WHERE photos.id = outbox_photos.photo_id AND photos.deleted_at IS NOT NULL
                   )
            """)
        _ = try statement.bind(id, forName: ":item")
        try statement.run()
        let dropped = connection.changes
        _ = try statement.reset()
        if dropped > 0 { try touch(id, at: date, connection: connection) }
        return dropped
    }

    /// The binaries an item still owes something for, whatever that something is. Used to decide
    /// whether a row can settle when its send half is done.
    public func outstandingPhotoCount(for id: UUID, connection: SQLiteConnection) throws -> Int {
        let statement = try connection.cachedStatement(
            "SELECT COUNT(*) AS n FROM outbox_photos WHERE outbox_id = :item"
        )
        _ = try statement.bind(id, forName: ":item")
        return try statement.fetchOne { try $0.int("n") } ?? 0
    }

    static func decodePhotoRow(_ row: SQLiteRow) throws -> PhotoRow {
        PhotoRow(
            id: try row.uuid("id"),
            outboxID: try row.uuid("outbox_id"),
            path: try row.stringIfPresent("path"),
            shotType: try row.value("shot_type", ShotType.self),
            photoID: try row.uuidIfPresent("photo_id"),
            containerPath: try row.stringIfPresent("container_path"),
            isApplied: (try row.string("state")) == "applied",
            isSendable: try row.bool("sendable"),
            failCount: try row.int("fail_count")
        )
    }

    /// Writes one row per staged binary, at the moment its mutation is queued.
    func stagePhotos(
        _ photos: [OutboxPhoto],
        for id: UUID,
        sendable: Bool,
        at date: Date,
        connection: SQLiteConnection
    ) throws {
        guard !photos.isEmpty else { return }
        let statement = try connection.cachedStatement("""
            INSERT INTO outbox_photos
                (id, outbox_id, path, shot_type, photo_id, state, sendable,
                 fail_count, created_at, updated_at)
            VALUES
                (:id, :item, :path, :shot, NULL, 'pending', :sendable, 0, :now, :now)
            ON CONFLICT(id) DO NOTHING
            """)
        for photo in photos {
            _ = try statement.reset()
            _ = try statement.bind([
                ":id": photo.id,
                ":item": id,
                ":path": photo.path,
                ":shot": photo.shotType.rawValue,
                ":sendable": sendable ? 1 : 0,
                ":now": date
            ])
            try statement.run()
        }
        _ = try statement.reset()
    }

    /// Records that the apply sink has committed this binary locally.
    ///
    /// The staged path is cleared in the same statement that sets `photo_id`, because after this the
    /// file is gone: `LocalAPI.uploadPhoto` moves it into the app container. Leaving the path behind
    /// would leave a column naming a file that is not there, which is the shape of the defect E264
    /// describes rather than a record of anything.
    public func markPhotoApplied(
        id: UUID,
        photoID: UUID,
        containerPath: String,
        at date: Date,
        connection: SQLiteConnection
    ) throws {
        let statement = try connection.cachedStatement("""
            UPDATE outbox_photos
               SET state = 'applied', photo_id = :photo, container_path = :container,
                   path = NULL, updated_at = :now
             WHERE id = :id AND state = 'pending'
            """)
        _ = try statement.bind([":id": id, ":photo": photoID, ":container": containerPath, ":now": date])
        try statement.run()
        _ = try statement.reset()
    }

    /// Settles one binary's *apply*, and decides in one place whether anything is still owed for it.
    ///
    /// Three cases, and the third is the one that would otherwise be a stranded row:
    ///
    ///   - **No send sink wired.** The local commit was everything. The row goes, which is the
    ///     behavior every shipped build has, and it is what keeps `photos_outstanding = 0` — and
    ///     therefore `done` — reachable on a phone with no server.
    ///   - **Send sink, sendable binary.** Marked `applied`; the send half will complete it.
    ///   - **Send sink, `sendable = 0` binary.** Also goes, immediately. These are the binaries
    ///     `AppSchema` v18 migrated, which RULINGS **R77** keeps on the device permanently: nothing
    ///     will ever send one, so leaving it `applied` would leave its item's `photos_outstanding`
    ///     above zero for the life of the install and the mutation could never settle. A contributor
    ///     would see one visit stuck on screen 17 forever, for a rule they cannot see and did not
    ///     choose.
    ///
    /// The `sendable = 0` arm is a predicate rather than a Swift branch because the flag lives in
    /// the row, not in the caller — the drain does not know which binaries predate the send path and
    /// has no business learning.
    public func settleAppliedPhoto(
        id: UUID,
        photoID: UUID,
        containerPath: String,
        sendSinkWired: Bool,
        at date: Date,
        connection: SQLiteConnection
    ) throws {
        guard sendSinkWired else {
            // Touch first: after the delete the row is gone and there is nothing left to resolve the
            // owning item from.
            try touchItem(forPhoto: id, at: date, connection: connection)
            try completePhoto(id: id, connection: connection)
            return
        }
        try markPhotoApplied(
            id: id, photoID: photoID, containerPath: containerPath, at: date, connection: connection
        )
        let localOnly = try connection.cachedStatement(
            "DELETE FROM outbox_photos WHERE id = :id AND sendable = 0"
        )
        _ = try localOnly.bind(id, forName: ":id")
        try localOnly.run()
        _ = try localOnly.reset()
    }

    /// Bumps the item that owns one binary, by the binary's id.
    ///
    /// Read before the caller's delete would make it unfindable, so this takes the photo id and
    /// resolves the owner itself only while the row still exists; callers that already deleted the
    /// row pass the item id to `touch` instead.
    private func touchItem(forPhoto id: UUID, at date: Date, connection: SQLiteConnection) throws {
        let statement = try connection.cachedStatement(
            "UPDATE outbox SET updated_at = :now WHERE id = (SELECT outbox_id FROM outbox_photos WHERE id = :id)"
        )
        _ = try statement.bind([":now": date, ":id": id])
        try statement.run()
        _ = try statement.reset()
    }

    /// Removes a binary's row once nothing more is owed for it.
    ///
    /// Deletion rather than a third `state`, so that "outstanding" stays countable: the trigger pair
    /// v18 installs decrements `outbox.photos_outstanding` here, and that column is what the `done`
    /// CHECK reads. A `sent` state left in the table would have to be excluded from the count by
    /// every future reader, which is the convention v1's comment refuses.
    public func completePhoto(id: UUID, connection: SQLiteConnection) throws {
        let statement = try connection.cachedStatement("DELETE FROM outbox_photos WHERE id = :id")
        _ = try statement.bind(id, forName: ":id")
        try statement.run()
        _ = try statement.reset()
    }

    /// Records a failed send attempt against one binary.
    public func recordPhotoFailure(
        id: UUID,
        failCount: Int,
        reason: String,
        code: APIError?,
        at date: Date,
        connection: SQLiteConnection
    ) throws {
        let statement = try connection.cachedStatement("""
            UPDATE outbox_photos
               SET fail_count = :count, last_error = :reason, last_error_code = :code, updated_at = :now
             WHERE id = :id
            """)
        _ = try statement.bind([
            ":id": id, ":count": failCount, ":reason": reason,
            ":code": code?.rawValue, ":now": date
        ])
        try statement.run()
        _ = try statement.reset()
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
    /// 1. **A queued favorite or private reminder is discarded.** It is a mutation whose only
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
    /// E157). A stripped payload lands as a row with
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
    /// leaving the receipt would leave the account's id on the device. A `done` favorite's receipt
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

        // The append-only contribution kinds, in **two families with two payload shapes**.
        //
        // The four original ones flatten `Attribution` into top-level `userID` + `deviceID`
        // (`Visit`, `TreeObservation`, `TreeMeasurement`, `CareEvent`). Spec §3.4's ten carry the
        // `Attribution` as an object, so the account is at `$.attribution.userID`
        // (`CommunityMutations.swift`).
        //
        // **Both families have to be named or a deletion under-deletes**, and the failure is R3's
        // stated one: a signed-in contributor's queued species correction, photo withdrawal or
        // hazard redirect would keep naming the account through the deletion and then drain to the
        // service afterwards. A single `$.userID` predicate matches none of them — the key is not
        // there — so the rows would be silently untouched, which is the shape of under-deletion that
        // reads as success at every layer.
        let contributions = """
            (kind IN ('visit','observation','measurement','care_event')
             OR kind IN ('add_tree','species_claim','species_correction',
                         'wrong_species_report','never_existed_report',
                         'species_review_dismissal','record_review_dismissal',
                         'photo_vote','photo_withdrawal','hazard_redirect'))
            """
        // Either shape. `json_extract` answers NULL for a path a payload does not have, so exactly
        // one half of this can match any given row and neither can match a device-owned one.
        let mine = """
            (json_extract(payload, '$.userID') = :user COLLATE NOCASE
             OR json_extract(payload, '$.attribution.userID') = :user COLLATE NOCASE)
            """

        // One statement or the other, chosen by the door, over exactly the same set of rows — so
        // there is no arrangement of the two in which a queued contribution is both anonymized and
        // discarded, and none in which it is neither.

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

            // Both keys, in one statement, because a row has one of them and `json_remove` is a
            // no-op on a path that is not there. Naming only the one a kind "should" have would put
            // the mapping from kind to payload shape in a second place, and the two would drift.
            let anonymize = try connection.cachedStatement("""
                UPDATE outbox
                   SET payload = json_remove(json_remove(payload, '$.userID'), '$.attribution.userID'),
                       updated_at = :now
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
            // Empty here, filled by `attachStagedPhotos`. Since `AppSchema` v18 the binaries are
            // rows in `outbox_photos` rather than a JSON column on this one, so they cannot be
            // decoded from `row` — every query returning a `Record` runs them through that step.
            photos: [],
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
            locallyApplied: try row.bool("local_applied"),
            remoteSent: try row.bool("remote_sent"),
            windowStartedAt: try row.date("window_started_at"),
            nextAttemptAt: try row.dateIfPresent("next_attempt_at")
        )
    }
}
