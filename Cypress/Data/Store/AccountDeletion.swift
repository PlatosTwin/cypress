import Foundation

/// `DELETE /me`, over the app's own tables (RULINGS **R3**, closing the question ERRATA E23 and E89
/// each left OPEN; extended to two doors by the project owner's ruling — see `AccountDeletionChoice`).
///
/// **The conflict R3 settled.** DECISIONS §3.12 says account deletion *anonymizes* attributed rows —
/// "user_id nulled, device link severed" — rather than deleting them. Two tables hold rows owned
/// exclusively by one party or the other, `private_reminders` (E23) and `favorites` (E89), under
/// `CHECK ((user_id IS NULL) <> (device_id IS NULL))`. Such a row cannot satisfy both halves of that
/// sentence: null its `user_id` and it is owned by nobody, which the engine refuses; re-home it onto
/// the device and one person's private records become whoever picks the phone up next. R3 ruled that
/// §3.12 anonymizes *contributions*, and that a reminder nobody but its owner can read is not one.
/// **Anonymize what the forest keeps, delete what only one person could ever see.**
///
/// **What the two doors changed, and what they did not.** R3's rule is now R3's *default*. The
/// argument for it is unchanged and it is the door most people should take; what changed is that a
/// person who means "I want what I put here gone" is no longer told no. `AccountDeletionChoice`
/// argues the whole of it, including why anonymous means NULL rather than a stand-in id, and why
/// reminders and favorites are outside the choice rather than inside it. This type implements it.
///
/// **Both halves commit or neither does.** Everything below runs inside one transaction, because a
/// deletion that anonymized and then failed before deleting would leave a person half-deleted with
/// no way to tell and no way to retry — the second attempt would find nothing left to anonymize and
/// would report success over a database that still holds their reminders. `DatabaseQueue.write`
/// already opens that transaction; `delete(userID:choice:at:connection:)` therefore takes a
/// connection and does not open one of its own, so a caller that wants deletion and some other write
/// to be one atomic act still gets one.
///
/// **The bytes are not here, and cannot be.** Photographs are files in the container keyed by
/// storage key, and a `FileManager` call inside a SQLite transaction is not part of that
/// transaction. `photoBytes(userID:connection:)` is a *read* that names the files the erasing door
/// has to remove, and `LocalAPI.deleteAccount` removes them **before** it opens the write. See that
/// method for why files-first is the correct order for an erasure specifically, and
/// `LocalAPI.debugClearPhotos` for the general form of the trap.
///
/// **What is *not* here.** There is no `users` table in `AppSchema` — the app stores a signed-in
/// user's id and nothing else about them (`AppStateKey.currentUserID`) — so "removes the profile"
/// (BUILD-PLAN §10) is one key, cleared by the caller. When a server exists it deletes the profile
/// row; the local half stays exactly this.
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

    /// The files one account's photographs occupy, named so a caller can remove them.
    ///
    /// Two lists because there are two ways a photograph's bytes exist on this device and a
    /// deletion that took only one of them would leave the other. `storageKeys` are the confirmed
    /// uploads — names inside the app's photo directory, which only `LocalAPI` knows the location of,
    /// so they are returned as names and resolved there. `absolutePaths` are the ones still on their
    /// way: a `photos.local_path` whose upload has not been confirmed, and the staged JPEGs of visits
    /// still sitting in the outbox, both of which were written as full paths by the code that staged
    /// them.
    public struct PhotoBytes: Sendable, Equatable {
        public var storageKeys: [String] = []
        public var absolutePaths: [String] = []

        public var isEmpty: Bool { storageKeys.isEmpty && absolutePaths.isEmpty }

        public init() {}
    }

    /// What a deletion did, in rows. Returned rather than logged because every number here is a
    /// claim the confirmation copy makes to a person, and a claim that nothing checks is a claim
    /// that quietly stops being true.
    ///
    /// The `anonymized*` fields are `leaveRecords`' and the `deleted*` contribution fields are
    /// `eraseEverything`'s; on any one deletion one group is zero. That is a deliberate shape — a
    /// single `affectedContributions` count would make a test that meant to assert the erasing door
    /// pass just as happily against the anonymizing one, which is exactly the class of green test
    /// this project has been bitten by.
    public struct Outcome: Sendable, Equatable {
        /// Which door this outcome is the result of.
        public var choice: AccountDeletionChoice = .leaveRecords

        // --- leaveRecords

        /// Visits, check-ins, measurements and care events whose `user_id` was nulled. They stay on
        /// their trees.
        public var anonymizedContributions: Int = 0
        /// Tree names (D15), review flags and status overrides that carried the account as their
        /// author.
        public var anonymizedAttributions: Int = 0
        /// Photo votes whose owner was nulled and which still count toward their photograph's hero
        /// (`AppSchema` v9).
        public var anonymizedPhotoVotes: Int = 0
        /// Photographs whose owner was nulled (`AppSchema` v12, ERRATA E147). They stay on their
        /// trees with their bytes intact and belong to nobody afterwards — which also means nobody
        /// can delete them, including the next account signed in on this phone.
        ///
        /// Zero before v12, and not because nothing happened: there was no column to null, so a
        /// photograph was un-named by proxy when its visit was, and `addTree`'s photograph was never
        /// named at all.
        public var anonymizedPhotos: Int = 0
        /// Public notes the anonymizing door could not anonymize, because `community_notes.user_id`
        /// is `NOT NULL` (v1) and no migration has made it nullable. Nothing in the app writes a
        /// community note, so this is zero on every database the app can produce — and it is
        /// returned rather than ignored so that the day something does write one, the hole is a
        /// number somebody can see rather than a silence. See ERRATA E109. The erasing door has no
        /// such hole: a row that cannot be anonymized can still be deleted.
        public var communityNotesLeftAttributed: Int = 0

        // --- eraseEverything

        /// Visits, check-ins, measurements and care events deleted outright.
        public var deletedContributions: Int = 0
        /// Tree names and review flags deleted outright. Status overrides are not counted here; a
        /// moderation decision is anonymized under both doors (see `delete`).
        public var deletedAttributions: Int = 0
        /// Photograph rows deleted. Their bytes are removed by the caller, before this runs.
        public var deletedPhotos: Int = 0
        /// Community notes deleted, which is the E109 hole closed from the other side.
        public var deletedCommunityNotes: Int = 0

        // --- both doors

        /// Reminders deleted (E23's rows), tombstoned ones included.
        public var deletedPrivateReminders: Int = 0
        /// Favorites deleted (E89's rows), of which `deletedFavoriteTombstones` were already turned
        /// off. Both are exclusively owned; see `delete` for why a tombstone goes too.
        public var deletedFavorites: Int = 0
        public var deletedFavoriteTombstones: Int = 0
        /// Photo votes deleted.
        ///
        /// Under `eraseEverything` this is the account's own votes **plus** everybody else's votes on
        /// the account's photographs, which the foreign key from `photo_votes.photo_id` requires to
        /// go first. That second group is a real cost of the erasing door and is stated here rather
        /// than discovered: erasing your photograph erases the judgments other people made about it,
        /// because those judgments were about a thing that no longer exists.
        ///
        /// Under `leaveRecords` it is zero — the votes are anonymized instead, and counted in
        /// `anonymizedPhotoVotes`.
        public var deletedPhotoVotes: Int = 0
        /// Queued mutations discarded because applying them would re-create a deleted row, or —
        /// under `eraseEverything` — because the contribution they carry is one the person asked not
        /// to have land at all.
        public var discardedOutboxItems: Int = 0
        /// Queued mutations kept, with the account stripped out of their payload. Zero under
        /// `eraseEverything`, which keeps none of them.
        public var anonymizedOutboxItems: Int = 0

        public init() {}
    }

    // MARK: - The bytes

    /// Every file the account's photographs occupy, for the erasing door.
    ///
    /// **A photograph says whose it is** since `AppSchema` v12, and this read is the reason the
    /// column exists. Before it, the only tie between a photograph and a person was `visit_id` and
    /// from there `visits.user_id` — which meant `LocalAPI.addTree`'s photograph, written with no
    /// visit for a tree whose row records no author, was attributable to nobody and reachable by
    /// neither door. "Erase everything I contributed" left that JPEG on the disk. ERRATA E136
    /// recorded it as a broken promise; ERRATA E147 is the column that closes it, and this predicate
    /// is now `photos.user_id` rather than a join through the visits.
    ///
    /// Two things that did not change with it:
    ///
    /// 1. This read still **must run before the rows are touched**, and the ordering is still
    ///    enforced by construction: it is a read on a separate connection, taken by
    ///    `LocalAPI.deleteAccount` before it opens the write at all.
    /// 2. It is scoped to the account and not to the device. A device-owned photograph was taken
    ///    before there was an account and was never this account's; `claimDevice` is what moves one
    ///    onto an account, and nothing has moved these. The erasing door is emphatically not an
    ///    exception, for the reason `delete` gives about every other device-owned row.
    ///
    /// **What the anonymizing door now does, which is also new.** It used to name `photos` not once,
    /// and that was correct when nulling the visit's `user_id` removed the only link there was. It
    /// is not correct now: a photograph carries the name itself, so the door that promises to take
    /// the name off has to take it off here too. See `anonymizeContributions`.
    public func photoBytes(userID: UUID, connection: SQLiteConnection) throws -> PhotoBytes {
        var bytes = PhotoBytes()

        let photos = try connection.cachedStatement("""
            SELECT storage_key, local_path FROM photos WHERE user_id = :user COLLATE NOCASE
            """)
        _ = try photos.bind([":user": userID.uuidString])
        for row in try photos.fetchAll({ row in
            (key: try row.stringIfPresent("storage_key"), path: try row.stringIfPresent("local_path"))
        }) {
            if let key = row.key { bytes.storageKeys.append(key) }
            if let path = row.path { bytes.absolutePaths.append(path) }
        }
        _ = try photos.reset()

        // The queue's own staged JPEGs. A visit that has not synced has its photograph on disk and
        // no `photos` row at all, so the query above cannot see it, and a deletion that missed it
        // would leave the one photograph the person took most recently.
        //
        // `json_each` over `photo_paths`, tolerating both shapes the column has held: v2 rewrote the
        // bare-string rows into objects, and `OutboxPhoto` still decodes the old form, so this reads
        // it too rather than trusting that the migration reached every row.
        let staged = try connection.cachedStatement("""
            SELECT COALESCE(json_extract(element.value, '$.path'),
                            CASE WHEN json_type(element.value) = 'text' THEN element.value END) AS path
              FROM outbox, json_each(outbox.photo_paths) AS element
             WHERE json_extract(outbox.payload, '$.userID') = :user COLLATE NOCASE
            """)
        _ = try staged.bind([":user": userID.uuidString])
        bytes.absolutePaths += try staged.fetchAll { try $0.stringIfPresent("path") }.compactMap { $0 }
        _ = try staged.reset()

        return bytes
    }

    // MARK: - The rows

    /// Deletes an account, through the door the person chose.
    ///
    /// **The tombstones go too, and E89's reason for them does not survive here.** A favorite
    /// un-favorites through `deleted_at` rather than a `DELETE` because a stray delete loses the
    /// un-favorite *event*, so the row comes back on the next sync from another device. There is no
    /// such next sync: the account those other devices would sync as no longer exists, and this
    /// transaction removes the account's queued toggles in the same breath. A tombstone is also
    /// exactly as exclusively owned as a live row and exactly as unreadable — it is a sentence about
    /// a person ("this account stopped keeping this tree") that no query can return and no person can
    /// remove. So it is deleted on the same argument as the row it is a tombstone for, under both
    /// doors.
    ///
    /// **What happens to the device's own rows: nothing, under either door.** A device-owned reminder
    /// or favorite was written before there was an account and was never the account's; `claimDevice`
    /// moves such a row *onto* an account, and nothing has moved these. Deleting them would delete a
    /// stranger's records — the next person to use this phone, or the same person's pre-sign-in work —
    /// on the strength of a shared installation id. The erasing door is emphatically not an exception:
    /// "everything I have added" is scoped to the account that is being deleted, and a device's
    /// anonymous rows were added by an identity that is not being deleted and cannot consent here.
    ///
    /// **A moderation decision is anonymized under both doors.** `tree_status_overrides.set_by` names
    /// the lead who confirmed a tree's status, and that confirmation is not a personal contribution
    /// the way a measurement is — it was made in a role, about a public object, and other people's
    /// screens depend on it. Deleting it would revert a tree to a status a moderator had already
    /// looked at and rejected, which is a change to the forest's record rather than a removal of the
    /// person's. The column is nullable, so both doors take the name off and leave the decision. This
    /// was residue before the two doors existed: the id stayed in that column after a deletion, and
    /// nothing noticed.
    @discardableResult
    public func delete(
        userID: UUID,
        choice: AccountDeletionChoice,
        at date: Date,
        connection: SQLiteConnection
    ) throws -> Outcome {
        try connection.transaction {
            var outcome = Outcome()
            outcome.choice = choice
            let user: [String: SQLiteBindable?] = [":user": userID.uuidString]
            let userAndNow: [String: SQLiteBindable?] = [":user": userID.uuidString, ":now": date]

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

            // --- The queue, which is the half a deletion path is most likely to forget. It goes
            // first under both doors: a queued mutation that drains after the rows are gone would
            // re-create them, and the window in which that can happen should be zero rather than
            // small.
            let outbox = try OutboxStore().forgetAccount(
                userID: userID, choice: choice, at: date, connection: connection
            )
            outcome.discardedOutboxItems = outbox.discarded
            outcome.anonymizedOutboxItems = outbox.anonymized

            // --- What only one person could ever see. R3, under both doors, and not part of the
            // choice — see `AccountDeletionChoice` for why offering to keep an unreadable row would
            // be a decorative control rather than an option.
            //
            // Reminders go before photographs because `private_reminders.photo_id` references
            // `photos(id)` and foreign keys are ON (`SQLiteConnection`). The whole of the erasing
            // door's ordering below is that constraint, made explicit.
            outcome.deletedPrivateReminders = try run(
                "DELETE FROM private_reminders WHERE user_id = :user COLLATE NOCASE", user, on: connection
            )

            outcome.deletedFavoriteTombstones = try count(
                """
                SELECT COUNT(*) AS n FROM favorites
                 WHERE user_id = :user COLLATE NOCASE AND deleted_at IS NOT NULL
                """,
                user, on: connection
            )
            outcome.deletedFavorites = try run(
                "DELETE FROM favorites WHERE user_id = :user COLLATE NOCASE", user, on: connection
            )

            switch choice {
            case .leaveRecords:
                try anonymizeContributions(userID: userID, at: date, into: &outcome, on: connection)
            case .eraseEverything:
                try eraseContributions(userID: userID, into: &outcome, on: connection)
            }

            // A moderation decision keeps its effect and loses its author, whichever door was taken.
            outcome.anonymizedAttributions += try run(
                "UPDATE tree_status_overrides SET set_by = NULL WHERE set_by = :user COLLATE NOCASE",
                user, on: connection
            )

            // --- The device link §3.12 severs, and the signed-in state that named the account.
            try run(
                "UPDATE device SET user_id = NULL, updated_at = :now WHERE user_id = :user COLLATE NOCASE",
                userAndNow, on: connection
            )
            try run(
                "DELETE FROM app_state WHERE key = :key AND value = :user COLLATE NOCASE",
                [":key": AppStateKey.currentUserID.rawValue, ":user": userID.uuidString],
                on: connection
            )

            // The permission slip is torn up. Inside the transaction, so a rollback tears it up too
            // and a commit leaves nothing behind that would let a later stray DELETE through.
            try run(
                "DELETE FROM app_state WHERE key = :key", [":key": Self.erasureSentinelKey], on: connection
            )

            return outcome
        }
    }

    // MARK: - The default door

    /// §3.12, unchanged: the row stays on its tree and stops saying who put it there.
    ///
    /// `device_id` is NOT NULL on the four contribution tables and is left alone — it is D9's
    /// anonymous installation handle, which these rows carried before there was an account and would
    /// carry if there had never been one. The "device link" §3.12 severs is the `device.user_id` row,
    /// which is the only place this installation is tied to this person.
    ///
    /// **And leaving it alone is exactly what a tombstone had to be added for** (`AppSchema` v13,
    /// ERRATA E157). A row with `user_id IS NULL` and a
    /// `device_id` is, to every other query in this app, *this device's unclaimed work*:
    /// `claimDevice` adopts it onto the next account signed in on the phone, and the journal, the
    /// grove and screen 15's count all show it as the current holder's. So the four `INSERT`s below
    /// record each row's `client_uuid` in `anonymized_contributions`, which those queries read as
    /// *nobody's*. The accepted cost is stated in RULINGS and is not softened anywhere: the person
    /// who deletes their account and signs back in on their own phone does not get their own work
    /// back. `AccountDeletionCopy.leaveRecordsBody` says so on screen.
    ///
    /// Photographs **are** named here, since `AppSchema` v12 gave them an owner (ERRATA E147). This
    /// paragraph used to say the opposite and used to be right: with no owner column, nulling the
    /// visit's `user_id` un-named every photograph taken on it, and naming `photos` would have been
    /// an empty statement. A photograph carries the name itself now, so the door whose whole promise
    /// is that the work stays and the name comes off has to take it off here as well — otherwise the
    /// picture would go on saying whose it was after the visit under it had stopped.
    ///
    /// It becomes a `PhotoOwner.nobody` photograph, which v12's CHECK permits deliberately and v9's
    /// `photo_votes` CHECK had to be relaxed to permit: the bytes stay, the tree keeps its picture,
    /// nothing says whose it was, and nobody — including whoever signs in on this phone next — can
    /// delete it. `device_id` is *not* set instead, which is the difference between this and the
    /// four tables above: they carry D9's installation handle in a NOT NULL column and always did,
    /// whereas re-homing a photograph onto the device would hand one person's picture to the next
    /// person holding the phone, and `claimDevice` would then attribute it to them.
    private func anonymizeContributions(
        userID: UUID,
        at date: Date,
        into outcome: inout Outcome,
        on connection: SQLiteConnection
    ) throws {
        let userAndNow: [String: SQLiteBindable?] = [":user": userID.uuidString, ":now": date]

        for table in ["visits", "observations", "measurements", "care_events"] {
            // The tombstone goes down **before** the owner comes off, and the order is not a
            // preference: the predicate that names these rows is `user_id = :user`, and the UPDATE
            // below is what stops it matching. Written first, it reads the set the person is asking
            // to be unlinked from; written second it would read nothing at all and the whole
            // guarantee would be a table of zero rows.
            try run(
                """
                INSERT OR IGNORE INTO anonymized_contributions (client_uuid, anonymized_at)
                SELECT client_uuid, :now FROM \(table) WHERE user_id = :user COLLATE NOCASE
                """,
                userAndNow, on: connection
            )

            outcome.anonymizedContributions += try run(
                "UPDATE \(table) SET user_id = NULL, updated_at = :now WHERE user_id = :user COLLATE NOCASE",
                userAndNow, on: connection
            )
        }

        // The photograph loses its owner and keeps its place. Its own field, mirroring
        // `deletedPhotos` on the other door, for the reason `Outcome` gives about not letting one
        // number stand for two different acts.
        //
        // **`taken_on_device` comes off in the same statement** (`AppSchema` v16). That column is
        // provenance rather than ownership and the deletion gate reads it, so leaving it would make
        // this door's promise last exactly as long as the phone: the next person holding it would
        // find the deleted account's photographs deletable again, which is the outcome the
        // paragraph above spends its length refusing. The Swift rule refuses `.nobody` before it
        // looks at provenance and the SQL leads with the same clause; this is what makes both of
        // those true of the row rather than only of the code.
        outcome.anonymizedPhotos = try run(
            """
            UPDATE photos SET user_id = NULL, taken_on_device = NULL, updated_at = :now
             WHERE user_id = :user COLLATE NOCASE
            """,
            userAndNow, on: connection
        )

        // A tree's name is the most durable public contribution in the model — first namer wins
        // and the name outlives everything (D15) — and `given_by` is nullable precisely so it can
        // outlive its namer. A review flag is the same shape: the flag is the forest's, the
        // raiser was a person.
        outcome.anonymizedAttributions += try run(
            "UPDATE tree_names SET given_by = NULL, updated_at = :now WHERE given_by = :user COLLATE NOCASE",
            userAndNow, on: connection
        )
        outcome.anonymizedAttributions += try run(
            "UPDATE review_flags SET raised_by = NULL, updated_at = :now WHERE raised_by = :user COLLATE NOCASE",
            userAndNow, on: connection
        )

        // The vote survives its voter (`AppSchema` v9), which is the concrete thing the owner asked
        // for when they said "up votes" among the things the default door leaves in place. Until v9
        // this was a `DELETE`, not because anybody had ruled that a vote should die with its voter —
        // v8 argues at length that a vote *is* a contribution — but because the exactly-one-owner
        // CHECK made an anonymous vote unstorable. It is storable now, and it still counts: hero
        // selection across the whole app is unchanged by a deletion through this door.
        outcome.anonymizedPhotoVotes = try run(
            "UPDATE photo_votes SET user_id = NULL, updated_at = :now WHERE user_id = :user COLLATE NOCASE",
            userAndNow, on: connection
        )

        // The one contribution table this door cannot anonymize. Reported, not silently skipped.
        outcome.communityNotesLeftAttributed = try count(
            "SELECT COUNT(*) AS n FROM community_notes WHERE user_id = :user COLLATE NOCASE",
            [":user": userID.uuidString], on: connection
        )
    }

    // MARK: - The destructive door

    /// Everything the account added, gone.
    ///
    /// **The order is the foreign-key graph read backwards, and it is not adjustable.** Foreign keys
    /// are ON, so a child row must go before its parent, and there are two chains: `care_events`,
    /// `private_reminders` and `community_notes` all reference `photos(id)`, and `photos` references
    /// `visits(id)`. So notes and care events go, then every vote touching one of these photographs,
    /// then the photographs, then the visits. Reminders have already gone in `delete`.
    ///
    /// **Whose votes go.** Two sets, and only one of them is the person's. Their own votes on
    /// anybody's photographs are theirs to withdraw. Everybody *else's* votes on the person's
    /// photographs are not, and go anyway, because the photograph they are votes about is going and
    /// a vote on a row that does not exist cannot be stored. `Outcome.deletedPhotoVotes` counts both
    /// together and says so.
    ///
    /// **Community notes are deleted rather than left**, which closes ERRATA E109 from the side it
    /// can be closed from. `community_notes.user_id` is NOT NULL so the row cannot be anonymized;
    /// it can be deleted, and a person who asked for everything to go should not keep the one record
    /// kind whose column happens to be strict.
    private func eraseContributions(
        userID: UUID,
        into outcome: inout Outcome,
        on connection: SQLiteConnection
    ) throws {
        let user: [String: SQLiteBindable?] = [":user": userID.uuidString]

        outcome.deletedCommunityNotes = try run(
            "DELETE FROM community_notes WHERE user_id = :user COLLATE NOCASE", user, on: connection
        )
        outcome.deletedContributions += try run(
            "DELETE FROM care_events WHERE user_id = :user COLLATE NOCASE", user, on: connection
        )

        outcome.deletedPhotoVotes = try run(
            """
            DELETE FROM photo_votes
             WHERE user_id = :user COLLATE NOCASE
                OR photo_id IN (SELECT id FROM photos WHERE user_id = :user COLLATE NOCASE)
            """,
            user, on: connection
        )

        // The rows whose bytes the caller has already removed from disk. See
        // `LocalAPI.deleteAccount` for why that order and not this one.
        //
        // `photos.user_id` since v12, where this used to join through `visits`. The account's
        // photographs are now one predicate, so the tree a person *added* — whose photograph has no
        // visit to join through and whose row records no author — is finally inside the door that
        // promised to erase it (ERRATA E136, E147).
        //
        // Tombstones go too. A photograph the person deleted one at a time keeps a stripped row so
        // the tree's record can say a picture was here and was withdrawn (`ContributionStore
        // .deletePhoto`); "erase everything I contributed" reaches that sentence as well, and the
        // row is theirs to take. `deleted_at` is not in the predicate for exactly that reason.
        outcome.deletedPhotos = try run(
            "DELETE FROM photos WHERE user_id = :user COLLATE NOCASE",
            user, on: connection
        )

        for table in ["visits", "observations", "measurements"] {
            outcome.deletedContributions += try run(
                "DELETE FROM \(table) WHERE user_id = :user COLLATE NOCASE", user, on: connection
            )
        }

        outcome.deletedAttributions += try run(
            "DELETE FROM tree_names WHERE given_by = :user COLLATE NOCASE", user, on: connection
        )
        outcome.deletedAttributions += try run(
            "DELETE FROM review_flags WHERE raised_by = :user COLLATE NOCASE", user, on: connection
        )
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
