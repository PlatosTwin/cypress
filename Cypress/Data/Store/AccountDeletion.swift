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
        /// Tree names (D15), review flags, data disputes (v22) and status overrides that carried the
        /// account as their author.
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
        /// Tree names, review flags and data disputes deleted outright — a dispute's two child
        /// tables cascade with it (v22). Status overrides are not counted here; a moderation
        /// decision is anonymized under both doors (see `delete`).
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

        // --- the community trees the account added (`AppSchema` v23)
        //
        // **These two break the one-group-is-zero shape on purpose**, because the owner's decision
        // 6 of 2026-09-28 does: under `eraseEverything` a tree somebody else has built on stays,
        // anonymized, and one nobody has is deleted — so one erasure can do both. `forgetCommunityTrees`
        // carries the rule.

        /// Community trees the account added that stay, with no adder. Every one under
        /// `leaveRecords`; under `eraseEverything`, the ones another identity has built on.
        public var anonymizedCommunityTrees: Int = 0
        /// Community trees the account added that are gone, with every position their pin held.
        /// Zero under `leaveRecords` on this phone — see `forgetCommunityTrees` for the one case the
        /// service deletes that the phone cannot see.
        public var deletedCommunityTrees: Int = 0
        /// Pin positions the account set that stay on their tree with no mover, under either door.
        /// A position on a tree the erasing door deleted is not counted here: it went with its tree.
        public var anonymizedTreeLocations: Int = 0

        public init() {}
    }

    // MARK: - The bytes

    /// Every file the account's photographs occupy, for the erasing door.
    ///
    /// **A photograph says whose it is** since `AppSchema` v12, and this read is the reason the
    /// column exists. Before it, the only tie between a photograph and a person was `visit_id` and
    /// from there `visits.user_id` — which meant `LocalAPI.addTree`'s photograph, written with no
    /// visit for a tree whose row then recorded no author, was attributable to nobody and reachable by
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
        // A join onto `outbox_photos` since `AppSchema` v18, where the binaries stopped being
        // elements of a JSON column and became rows. `path IS NOT NULL` is not a tidiness filter: an
        // *applied* binary has no staged file left — the apply moved it into the app container,
        // where it is named by `photos.local_path` and has therefore already been collected by the
        // statement above. A NULL here means "counted", not "missing".
        let staged = try connection.cachedStatement("""
            SELECT outbox_photos.path AS path
              FROM outbox
              JOIN outbox_photos ON outbox_photos.outbox_id = outbox.id
             WHERE json_extract(outbox.payload, '$.userID') = :user COLLATE NOCASE
               AND outbox_photos.path IS NOT NULL
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

            // After the contributions, and the order is the rule: under the erasing door "has
            // anybody else built on this tree" is asked of what is left once the account's own
            // visits and photographs are gone — the service's order too (`deleteAccountTrees`).
            try forgetCommunityTrees(
                userID: userID, choice: choice, at: date, into: &outcome, on: connection
            )

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

        // A data dispute is the same shape as a review flag and is anonymized on the same argument
        // (`AppSchema` v22, `RULINGS R79`). It was missed when the table was added, which is what
        // `ROADMAP`'s entry about enumerating the user-bearing tables is for: a hand-kept list
        // cannot fail loudly, and this one did not.
        //
        // **What `raised_by IS NULL` then means, said out loud rather than inherited, because the
        // table's own NULL cannot say it.** A NULL in `raised_by` is also D9's ordinary case — a
        // dispute raised on this phone before it had an account — so the column alone cannot tell an
        // un-named row from an unsigned-in one. `review_flags` never had to: a flag has no
        // author-only verb. This table does, and the answer to "whose is it now" is **nobody's**.
        //
        // That is not this half's ruling to make. `server/internal/store/disputes.go`'s
        // `disputeIsThisIdentitys` counts a dispute as the caller's on a `user_id` or a `device_id`
        // match against its own `contributions` row, and `AccountDeletionChoice.leaveRecords` clears
        // both of those there; a comparison against two NULLs then falls out of its `FILTER` — "a
        // record owned by nobody is not withdrawable by anybody", measured there by
        // `TestAnAnonymizedDisputeIsWithdrawableByNobody`. **This door clears one**, because this
        // table has one: `tree_data_disputes` carries `raised_by` and no device column at all
        // (`AppSchema` v22), which is why the fact that the row is nobody's has to be read off the
        // tombstone rather than off a second NULL. The service cannot adopt the other answer even in
        // principle, because `ClaimDevice` has already folded the row's `device_id` into its
        // `user_id` and there is no installation identity left to match. A phone that offered the
        // withdrawal anyway would apply it locally, queue a `data_dispute_withdrawal` and be
        // answered `forbidden` — a dispute shown as withdrawn while the service goes on holding it,
        // which is the shape ERRATA **E280** records for `photo_withdrawal`, reached here through a
        // third verb.
        //
        // So the tombstone goes down first, exactly as it does for the four tables above and for the
        // reason `MeasurementForWithdrawal.isAnonymized` gives: the fact cannot be read off the
        // owner column, the `client_uuid` is the key the row already carries, and the `UPDATE` below
        // is what stops the predicate matching. `TreeDataDispute.isAuthored(by:)` refuses on it, and
        // `DataDisputeStore`'s `WHERE` clauses carry the same refusal so the two gates cannot differ.
        try run(
            """
            INSERT OR IGNORE INTO anonymized_contributions (client_uuid, anonymized_at)
            SELECT client_uuid, :now FROM tree_data_disputes WHERE raised_by = :user COLLATE NOCASE
            """,
            userAndNow, on: connection
        )
        outcome.anonymizedAttributions += try run(
            """
            UPDATE tree_data_disputes SET raised_by = NULL, updated_at = :now
             WHERE raised_by = :user COLLATE NOCASE
            """,
            userAndNow, on: connection
        )

        // A species statement is the same shape as a tree name, and is anonymized on the same
        // argument: the chain is the tree's record, the author was a person. `ROADMAP` chip 79
        // measured the gap (`AccountDeletionCoverageTests`, #186) and this closes it.
        //
        // **No tombstone, and the question chip 79 left open is answered by the schema.**
        // `species_assertions` carries at most one owner (v14's CHECK), so a row the account owned
        // has `device_id IS NULL`, and nulling `user_id` leaves a row owned by nobody — which
        // `claimDevice` cannot adopt (it matches on `device_id`) and `SpeciesAssertion
        // .isSupersedable(by:)` refuses to everybody (R45 arm 3). v13's tombstone exists for the
        // four tables whose `device_id` is NOT NULL and survives; this one has nothing left to
        // mistake for this phone's unclaimed work.
        outcome.anonymizedAttributions += try run(
            """
            UPDATE species_assertions SET user_id = NULL, updated_at = :now
             WHERE user_id = :user COLLATE NOCASE
            """,
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
        // visit to join through and whose row recorded no author until v23 — is finally inside the door that
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

        // The refusal keys of photographs that are now gone (`OutboxStore.recordRefusedPhoto`). Each
        // names one photograph by id, in `app_state` rather than a column, so neither the statement
        // above nor `AccountDeletionCoverage` reaches it. It goes with its photograph. A key whose
        // photograph was already gone by some other road goes too: nothing reads it, and erasing is
        // the door that promises no residue. A key whose photograph survives — another owner's, or
        // this device's unclaimed work — stays, because it is still true.
        try run(
            """
            DELETE FROM app_state
             WHERE substr(key, 1, length(:prefix)) = :prefix
               AND substr(key, length(:prefix) + 1) NOT IN (SELECT upper(id) FROM photos)
            """,
            [":prefix": OutboxStore.refusedPhotoKeyPrefix], on: connection
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
        // The dispute goes whole, children and all: `tree_dispute_issues` and
        // `tree_dispute_suggestions` are `ON DELETE CASCADE` against this parent (`AppSchema` v22),
        // so the checked issues and the suggested values go with it in the same statement. They are
        // the account's own words about a record — "erase everything I contributed" reaches them —
        // and a child row surviving its parent is not reachable while foreign keys are ON, which
        // `SQLiteConnection` and `DatabaseQueue` both set.
        outcome.deletedAttributions += try run(
            "DELETE FROM tree_data_disputes WHERE raised_by = :user COLLATE NOCASE", user, on: connection
        )

        outcome.deletedAttributions += try eraseSpeciesAssertions(userID: userID, on: connection)
    }

    /// The account's species statements, gone, with each chain they sat in spliced shut (`ROADMAP`
    /// chip 79).
    ///
    /// **Why a splice and not a `DELETE`.** `superseded_by` is a deferred foreign key into the same
    /// table, so deleting a statement that an older one's `superseded_by` names fails at `COMMIT` —
    /// the whole erasure rolls back, which is loud and correct and not the door the person asked
    /// for. So every pointer at a deleted row is moved to the first surviving row after it, or to
    /// NULL where nothing survives after it, which makes that older row the head again: the tree's
    /// species goes back to what it was before the account spoke. A run of consecutive statements by
    /// the account is followed to its end, which is why the successor is resolved in Swift rather
    /// than one step at a time in SQL.
    ///
    /// **The deletes go first**, and the order is the one-head index's: it is not deferrable, so
    /// making an older row the head while the deleted head still stands would be two heads for one
    /// tree mid-statement. With the head deleted first, the dangling pointer is only a deferred
    /// foreign key, which the splice has repaired by `COMMIT`.
    ///
    /// `community_trees.species_current` is the chain head's read cache (v14), so it is resynced for
    /// every tree whose chain changed: to the new head's species, or to NULL where the account's
    /// statements were the whole chain. A tree this phone added and the account named, with no
    /// other statement, ends unnamed — "erase everything I contributed" includes the name.
    private func eraseSpeciesAssertions(userID: UUID, on connection: SQLiteConnection) throws -> Int {
        let doomedStatement = try connection.cachedStatement("""
            SELECT id, tree_uuid, superseded_by FROM species_assertions
             WHERE user_id = :user COLLATE NOCASE
            """)
        _ = try doomedStatement.bind([":user": userID.uuidString])
        let doomed = try doomedStatement.fetchAll { row in
            (
                id: try row.string("id"),
                tree: try row.string("tree_uuid"),
                successor: try row.stringIfPresent("superseded_by")
            )
        }
        _ = try doomedStatement.reset()
        guard !doomed.isEmpty else { return 0 }

        let successorOf = Dictionary(
            doomed.map { ($0.id.uppercased(), $0.successor) }, uniquingKeysWith: { first, _ in first }
        )
        // The first surviving row after `id`, or nil for none. Bounded by the doomed set's size, so
        // a cycle — which the schema's CHECK and the head index together make unstorable — could
        // not spin here either.
        func survivor(after id: String) -> String? {
            var next = successorOf[id.uppercased()] ?? nil
            var steps = 0
            while let candidate = next, successorOf[candidate.uppercased()] != nil, steps <= doomed.count {
                next = successorOf[candidate.uppercased()] ?? nil
                steps += 1
            }
            return next
        }

        var deleted = 0
        for row in doomed {
            deleted += try run(
                "DELETE FROM species_assertions WHERE id = :id", [":id": row.id], on: connection
            )
        }
        for row in doomed {
            try run(
                """
                UPDATE species_assertions SET superseded_by = :survivor
                 WHERE superseded_by = :id COLLATE NOCASE
                """,
                [":survivor": survivor(after: row.id), ":id": row.id], on: connection
            )
        }
        for tree in Set(doomed.map { $0.tree.uppercased() }) {
            try run(
                """
                UPDATE community_trees
                   SET species_current = (
                       SELECT species_uuid FROM species_assertions
                        WHERE tree_uuid = :tree COLLATE NOCASE AND superseded_by IS NULL
                        LIMIT 1
                   )
                 WHERE id = :tree COLLATE NOCASE
                """,
                [":tree": tree], on: connection
            )
        }
        return deleted
    }

    // MARK: - The community trees the account added

    /// The owner's decisions 6 and 12 of 2026-09-28, over the trees this phone added and their pin
    /// chains (`AppSchema` v23), mirroring the service's `deleteAccountTrees`.
    ///
    /// - **`leaveRecords`**: every tree the account added stays, with no adder. Nobody may move it
    ///   afterwards — `ContributionOwner.nobody` is nobody's (`LocationCorrection.swift`) — and
    ///   `claimDevice` cannot adopt it, because the account-owned row has no `device_id` (at most
    ///   one owner, v23's CHECK).
    /// - **`eraseEverything`**: a tree another identity has built on stays, anonymized; one nobody
    ///   has is deleted with every position its pin held. "Built on" is the orchestrator's ruling on
    ///   decision 6, as the service reads it: another identity's live visit, check-in, measurement
    ///   or care event, or live photograph, on the tree — anonymized rows included, and favorites,
    ///   votes, names, species statements and reports not. This runs after `eraseContributions`, so
    ///   what remains on the tree is other people's.
    /// - **Either door**: every pin position the account set on a tree that stays loses its mover —
    ///   the service takes the account's name off every chain row too. The positions stay, because
    ///   they are where the tree is.
    ///
    /// **What the phone cannot do, stated rather than implied.** Decision 12 deletes an
    /// *unpublished* tree under both doors, including `leaveRecords`. Publication is the service's
    /// fact — it depends on the license the account held when the tree went live (decisions 7 and
    /// 10) — and this round's phone does not hold it, so the leaving door anonymizes every tree here
    /// and the service deletes the unpublished ones. The phone keeps a pin the service has dropped
    /// until the round that syncs the layer down can tell it otherwise; the pending erratum for this
    /// round records the gap.
    ///
    /// Nothing references `community_trees(id)` by foreign key: visits and photographs name a tree
    /// by `tree_uuid`, which may be a city row. A visit by somebody else on a deleted tree cannot
    /// exist here, because such a tree was not built on; the account's own went in
    /// `eraseContributions`.
    private func forgetCommunityTrees(
        userID: UUID,
        choice: AccountDeletionChoice,
        at date: Date,
        into outcome: inout Outcome,
        on connection: SQLiteConnection
    ) throws {
        let userAndNow: [String: SQLiteBindable?] = [":user": userID.uuidString, ":now": date]

        if choice == .eraseEverything {
            // The trees nobody else has built on. A `LEFT JOIN`-free `NOT EXISTS` per table, each
            // seeking its `idx_<table>_tree` index.
            let unbuilt = Self.builtOnTables.map { table in
                """
                NOT EXISTS (SELECT 1 FROM \(table) x
                             WHERE x.tree_uuid = community_trees.id COLLATE NOCASE
                               AND x.deleted_at IS NULL)
                """
            }.joined(separator: "\n   AND ")
            let doomed = try connection.cachedStatement("""
                SELECT id FROM community_trees
                 WHERE user_id = :user COLLATE NOCASE
                   AND \(unbuilt)
                """)
            _ = try doomed.bind([":user": userID.uuidString])
            let ids = try doomed.fetchAll { try $0.string("id") }
            _ = try doomed.reset()

            for id in ids {
                // The chain first: its rows name the tree, not the other way round, and a deleted
                // tree's positions are not the forest's to keep.
                try run(
                    "DELETE FROM tree_locations WHERE tree_id = :tree COLLATE NOCASE",
                    [":tree": id], on: connection
                )
                outcome.deletedCommunityTrees += try run(
                    "DELETE FROM community_trees WHERE id = :tree", [":tree": id], on: connection
                )
            }
        }

        outcome.anonymizedCommunityTrees += try run(
            """
            UPDATE community_trees SET user_id = NULL, updated_at = :now
             WHERE user_id = :user COLLATE NOCASE
            """,
            userAndNow, on: connection
        )
        outcome.anonymizedTreeLocations += try run(
            """
            UPDATE tree_locations SET user_id = NULL, updated_at = :now
             WHERE user_id = :user COLLATE NOCASE
            """,
            userAndNow, on: connection
        )
    }

    /// The tables whose live rows mean somebody has met a tree (decision 6, as the orchestrator
    /// ruled it: `MetSpeciesKinds`' four, plus photographs).
    static let builtOnTables = ["visits", "observations", "measurements", "care_events", "photos"]

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
