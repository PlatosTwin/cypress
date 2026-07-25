import Foundation

/// `DELETE /me`, over the app's own tables (RULINGS **R3**, closing the question ERRATA E23 and E89
/// each left OPEN).
///
/// **The conflict.** DECISIONS §3.12 says account deletion *anonymizes* attributed rows — "user_id
/// nulled, device link severed" — rather than deleting them. Two tables now hold rows owned
/// exclusively by one party or the other, `private_reminders` (E23) and `favorites` (E89), under
/// `CHECK ((user_id IS NULL) <> (device_id IS NULL))`. Such a row cannot satisfy both halves of that
/// sentence: null its `user_id` and it is owned by nobody, which the engine refuses; re-home it onto
/// the device and one person's private records become whoever picks the phone up next. Something had
/// to give, and no document said which.
///
/// **The ruling, which this type implements.** §3.12 anonymizes *contributions*, and the word is
/// doing real work. A photograph, a measurement, a check-in have value to the forest independent of
/// who made them — that is the entire argument for keeping them, and it is why the record outlives
/// the account. A private reminder and a favourite have no such value. Nobody but their owner can
/// read them, and after anonymization nobody at all can: an ownerless favourite is a row that no
/// query returns and no person can remove. Keeping it is not privacy-preserving, it is litter that
/// happens to be unreachable.
///
/// So: **anonymize what the forest keeps, delete what only one person could ever see.** This is not
/// an exception to §3.12; it is what §3.12 means by *contribution*, made explicit.
///
/// **Both halves commit or neither does.** Everything below runs inside one transaction, because a
/// deletion that anonymized and then failed before deleting would leave a person half-deleted with
/// no way to tell and no way to retry — the second attempt would find nothing left to anonymize and
/// would report success over a database that still holds their reminders. `DatabaseQueue.write`
/// already opens that transaction; `delete(userID:at:connection:)` therefore takes a connection and
/// does not open one of its own, so a caller that wants deletion and some other write to be one
/// atomic act still gets one.
///
/// **What is *not* here.** There is no `users` table in `AppSchema` — the app stores a signed-in
/// user's id and nothing else about them (`AppStateKey.currentUserID`) — so "removes the profile"
/// (BUILD-PLAN §10) is one key, cleared below. When a server exists it deletes the profile row; the
/// local half stays exactly this.
public struct AccountDeletion {
    public init() {}

    /// The `app_state` key whose presence tells the tombstone trigger that an erasure is in progress,
    /// and whose *value* names the one account it is in progress for (`AppSchema` v6).
    ///
    /// Set and cleared inside the deletion transaction, so it cannot outlive it — a crash rolls it
    /// back along with everything else. It is deliberately not an `AppStateKey`: that enum is the
    /// enumerable set of *persisted settings*, and this is a value that must never be found on disk.
    ///
    /// The v6 trigger spells the same string out in frozen migration text. `AccountDeletionTests`
    /// pins that the two still agree.
    public static let erasureSentinelKey = "account_deletion_user_id"

    /// What a deletion did, in rows. Returned rather than logged because every number here is a
    /// claim the confirmation copy makes to a person, and a claim that nothing checks is a claim
    /// that quietly stops being true.
    public struct Outcome: Sendable, Equatable {
        /// Visits, check-ins, measurements and care events whose `user_id` was nulled. They stay on
        /// their trees.
        public var anonymizedContributions: Int = 0
        /// Tree names (D15) and review flags that carried the account as their author.
        public var anonymizedAttributions: Int = 0
        /// Reminders deleted (E23's rows), tombstoned ones included.
        public var deletedPrivateReminders: Int = 0
        /// Favourites deleted (E89's rows), of which `deletedFavoriteTombstones` were already turned
        /// off. Both are exclusively owned; see `delete` for why a tombstone goes too.
        public var deletedFavorites: Int = 0
        public var deletedFavoriteTombstones: Int = 0
        /// Photo votes deleted (`AppSchema` v8).
        ///
        /// A vote *is* a contribution in §3.12's sense — the hero it picks is what everybody sees —
        /// so anonymizing rather than deleting would be the rule. It is not writable: `photo_votes`
        /// carries the same exactly-one-owner CHECK `favorites` does, and a row with its `user_id`
        /// nulled is owned by nobody. Nor is a vote separable from its voter the way a measurement
        /// is separable from whoever took it: "one vote per owner per photo" is the whole of its
        /// integrity, and an ownerless vote is a ballot that can never be recounted, changed or
        /// withdrawn. So it goes with the account, on R3's reasoning about `favorites`.
        public var deletedPhotoVotes: Int = 0
        /// Queued mutations discarded because applying them would re-create a deleted row.
        public var discardedOutboxItems: Int = 0
        /// Queued mutations kept, with the account stripped out of their payload.
        public var anonymizedOutboxItems: Int = 0
        /// Public notes this path could not anonymize, because `community_notes.user_id` is
        /// `NOT NULL` (v1) and no migration has yet made it nullable. Nothing in the app writes a
        /// community note, so this is zero on every database the app can produce — and it is
        /// returned rather than ignored so that the day something does write one, the hole is a
        /// number somebody can see rather than a silence. See ERRATA E109.
        public var communityNotesLeftAttributed: Int = 0

        public init() {}
    }

    /// Deletes an account, in the two-part sense above.
    ///
    /// The order is not arbitrary. Anonymization runs first, so that if any later statement throws,
    /// the rollback restores rows that were about to be kept anyway — and so that the atomicity of
    /// the two halves is exercised by the failure mode that actually matters (a delete refused after
    /// the anonymization has already run).
    ///
    /// **The tombstones go too, and E89's reason for them does not survive here.** A favourite
    /// un-favourites through `deleted_at` rather than a `DELETE` because a stray delete loses the
    /// un-favourite *event*, so the row comes back on the next sync from another device. There is no
    /// such next sync: the account those other devices would sync as no longer exists, and this
    /// transaction removes the account's queued toggles in the same breath. A tombstone is also
    /// exactly as exclusively owned as a live row and exactly as unreadable — it is a sentence about
    /// a person ("this account stopped keeping this tree") that no query can return and no person can
    /// remove. So it is deleted on the same argument as the row it is a tombstone for.
    ///
    /// **What happens to the device's own rows: nothing.** A device-owned reminder or favourite was
    /// written before there was an account and was never the account's; `claimDevice` moves such a
    /// row *onto* an account, and nothing has moved these. Deleting them would delete a stranger's
    /// records — the next person to use this phone, or the same person's pre-sign-in work — on the
    /// strength of a shared installation id. They are left where they are.
    @discardableResult
    public func delete(userID: UUID, at date: Date, connection: SQLiteConnection) throws -> Outcome {
        try connection.transaction {
            var outcome = Outcome()

            // The trigger's permission slip, narrowed to this one account and opened only for the
            // length of this transaction (`AppSchema` v6).
            try run(
                """
                INSERT INTO app_state (key, value) VALUES (:key, :user)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value
                """,
                [":key": Self.erasureSentinelKey, ":user": userID.uuidString],
                on: connection
            )

            // --- What the forest keeps. §3.12, unchanged: the row stays on its tree and stops
            // saying who put it there. `device_id` is NOT NULL on all four and is left alone — it is
            // D9's anonymous installation handle, which these rows carried before there was an
            // account and would carry if there had never been one. The "device link" §3.12 severs is
            // the `device.user_id` row below, which is the only place this installation is tied to
            // this person.
            for table in ["visits", "observations", "measurements", "care_events"] {
                outcome.anonymizedContributions += try run(
                    "UPDATE \(table) SET user_id = NULL, updated_at = :now WHERE user_id = :user COLLATE NOCASE",
                    [":now": date, ":user": userID.uuidString],
                    on: connection
                )
            }

            // A tree's name is the most durable public contribution in the model — first namer wins
            // and the name outlives everything (D15) — and `given_by` is nullable precisely so it can
            // outlive its namer. A review flag is the same shape: the flag is the forest's, the
            // raiser was a person.
            outcome.anonymizedAttributions += try run(
                "UPDATE tree_names SET given_by = NULL, updated_at = :now WHERE given_by = :user COLLATE NOCASE",
                [":now": date, ":user": userID.uuidString],
                on: connection
            )
            outcome.anonymizedAttributions += try run(
                "UPDATE review_flags SET raised_by = NULL, updated_at = :now WHERE raised_by = :user COLLATE NOCASE",
                [":now": date, ":user": userID.uuidString],
                on: connection
            )

            // The one contribution table that cannot be anonymized. Reported, not silently skipped.
            outcome.communityNotesLeftAttributed = try count(
                "SELECT COUNT(*) AS n FROM community_notes WHERE user_id = :user COLLATE NOCASE",
                [":user": userID.uuidString],
                on: connection
            )

            // --- What only one person could ever see. R3.
            outcome.deletedPrivateReminders = try run(
                "DELETE FROM private_reminders WHERE user_id = :user COLLATE NOCASE",
                [":user": userID.uuidString],
                on: connection
            )

            outcome.deletedFavoriteTombstones = try count(
                """
                SELECT COUNT(*) AS n FROM favorites
                 WHERE user_id = :user COLLATE NOCASE AND deleted_at IS NOT NULL
                """,
                [":user": userID.uuidString],
                on: connection
            )
            outcome.deletedFavorites = try run(
                "DELETE FROM favorites WHERE user_id = :user COLLATE NOCASE",
                [":user": userID.uuidString],
                on: connection
            )

            // No sentinel needed: `photo_votes` has no tombstone trigger to satisfy (`AppSchema` v8).
            outcome.deletedPhotoVotes = try run(
                "DELETE FROM photo_votes WHERE user_id = :user COLLATE NOCASE",
                [":user": userID.uuidString],
                on: connection
            )

            // --- The queue, which is the half a deletion path is most likely to forget.
            let outbox = try OutboxStore().forgetAccount(userID: userID, at: date, connection: connection)
            outcome.discardedOutboxItems = outbox.discarded
            outcome.anonymizedOutboxItems = outbox.anonymized

            // --- The device link §3.12 severs, and the signed-in state that named the account.
            try run(
                "UPDATE device SET user_id = NULL, updated_at = :now WHERE user_id = :user COLLATE NOCASE",
                [":now": date, ":user": userID.uuidString],
                on: connection
            )
            try run(
                "DELETE FROM app_state WHERE key = :key AND value = :user COLLATE NOCASE",
                [":key": AppStateKey.currentUserID.rawValue, ":user": userID.uuidString],
                on: connection
            )

            // The permission slip is torn up. Inside the transaction, so a rollback tears it up too
            // and a commit leaves nothing behind that would let a later stray DELETE through.
            try run(
                "DELETE FROM app_state WHERE key = :key",
                [":key": Self.erasureSentinelKey],
                on: connection
            )

            return outcome
        }
    }

    // MARK: - Helpers

    @discardableResult
    private func run(_ sql: String, _ bindings: [String: SQLiteBindable?], on connection: SQLiteConnection) throws -> Int {
        let statement = try connection.cachedStatement(sql)
        _ = try statement.bind(bindings)
        try statement.run()
        let changed = connection.changes
        _ = try statement.reset()
        return changed
    }

    private func count(_ sql: String, _ bindings: [String: SQLiteBindable?], on connection: SQLiteConnection) throws -> Int {
        let statement = try connection.cachedStatement(sql)
        _ = try statement.bind(bindings)
        defer { _ = try? statement.reset() }
        return try statement.fetchOne { try $0.int("n") } ?? 0
    }
}
