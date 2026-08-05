import Foundation

/// Reads and writes over the app's own tables — everything the device produces.
///
/// Every insert of a `SyncableMutation` is idempotent on `client_uuid`: `ON CONFLICT DO NOTHING`
/// plus a `changes` check, so a replayed outbox item reports `.duplicate` rather than creating a
/// second row. This is the same guarantee the server gives (BUILD-PLAN §6, "Server dedupes on
/// client_uuid") and it is what makes the outbox chaos test's "zero duplicates" assertion hold
/// while the API is local.
public struct ContributionStore {
    public init() {}

    /// Whether a write created a row or found one already there.
    public enum WriteOutcome: Sendable, Equatable {
        case inserted
        case duplicate

        public var syncStatus: SyncResult.Status { self == .inserted ? .applied : .duplicate }
    }

    // MARK: - Visits

    @discardableResult
    public func insert(_ visit: Visit, connection: SQLiteConnection) throws -> WriteOutcome {
        let statement = try connection.cachedStatement("""
            INSERT INTO visits
                (id, tree_uuid, user_id, device_id, client_uuid, note, phenology_tags,
                 gps_accuracy_m, captured_at, created_at, updated_at, deleted_at)
            VALUES
                (:id, :tree, :user, :device, :client, :note, :tags,
                 :accuracy, :captured, :created, :updated, :deleted)
            ON CONFLICT(client_uuid) DO NOTHING
            """)
        _ = try statement.bind([
            ":id": visit.id,
            ":tree": visit.treeID,
            ":user": visit.userID,
            ":device": visit.deviceID,
            ":client": visit.clientUUID,
            ":note": visit.note,
            ":tags": JSONColumn.encode(visit.phenologyTags.map(\.rawValue)),
            ":accuracy": visit.gpsAccuracyM,
            ":captured": visit.capturedAt,
            ":created": visit.createdAt,
            ":updated": visit.updatedAt,
            ":deleted": visit.deletedAt
        ])
        return try run(statement, on: connection)
    }

    /// This tree's visits, newest first. `limit: nil` reads the series whole.
    public func visits(treeID: UUID, limit: Int? = nil, connection: SQLiteConnection) throws -> Series<Visit> {
        let statement = try connection.cachedStatement("""
            SELECT * FROM visits
             WHERE tree_uuid = :tree COLLATE NOCASE AND deleted_at IS NULL
             ORDER BY captured_at DESC LIMIT :limit
            """)
        _ = try statement.bind([":tree": treeID.uuidString, ":limit": Self.rowsToRead(for: limit)])
        return Self.series(try statement.fetchAll(Self.decodeVisit), limit: limit)
    }

    // MARK: - Observations

    @discardableResult
    public func insert(_ observation: TreeObservation, connection: SQLiteConnection) throws -> WriteOutcome {
        let statement = try connection.cachedStatement("""
            INSERT INTO observations
                (id, tree_uuid, user_id, device_id, client_uuid, captured_at, gps_accuracy_m,
                 status, vitality, foliage, structure_flags, note, verification_state,
                 created_at, updated_at, deleted_at)
            VALUES
                (:id, :tree, :user, :device, :client, :captured, :accuracy,
                 :status, :vitality, :foliage, :flags, :note, :verification,
                 :created, :updated, :deleted)
            ON CONFLICT(client_uuid) DO NOTHING
            """)
        _ = try statement.bind([
            ":id": observation.id,
            ":tree": observation.treeID,
            ":user": observation.userID,
            ":device": observation.deviceID,
            ":client": observation.clientUUID,
            ":captured": observation.capturedAt,
            ":accuracy": observation.gpsAccuracyM,
            ":status": observation.status?.rawValue,
            ":vitality": observation.vitality?.rawValue,
            ":foliage": observation.foliage.flatMap(JSONColumn.encode),
            ":flags": JSONColumn.encode(observation.structureFlags.map(\.rawValue)),
            ":note": observation.note,
            ":verification": observation.verificationState.rawValue,
            ":created": observation.createdAt,
            ":updated": observation.updatedAt,
            ":deleted": observation.deletedAt
        ])
        return try run(statement, on: connection)
    }

    /// This tree's check-ins, newest first. `limit: nil` reads the series whole.
    ///
    /// Screen 13 draws a twelve-month bar row from this and shares one vertical scale across it and
    /// two others (D2), so a page here does not just understate one row — it understates the scale
    /// and draws the other two rows too tall. `Series` is what carries that fact to the caller.
    public func observations(
        treeID: UUID,
        limit: Int? = nil,
        connection: SQLiteConnection
    ) throws -> Series<TreeObservation> {
        let statement = try connection.cachedStatement("""
            SELECT * FROM observations
             WHERE tree_uuid = :tree COLLATE NOCASE AND deleted_at IS NULL
             ORDER BY captured_at DESC LIMIT :limit
            """)
        _ = try statement.bind([":tree": treeID.uuidString, ":limit": Self.rowsToRead(for: limit)])
        return Self.series(try statement.fetchAll(Self.decodeObservation), limit: limit)
    }

    public func latestObservation(treeID: UUID, connection: SQLiteConnection) throws -> TreeObservation? {
        let statement = try connection.cachedStatement("""
            SELECT * FROM observations
             WHERE tree_uuid = :tree COLLATE NOCASE AND deleted_at IS NULL
             ORDER BY captured_at DESC LIMIT 1
            """)
        _ = try statement.bind(treeID.uuidString, forName: ":tree")
        return try statement.fetchOne(Self.decodeObservation)
    }

    // MARK: - Measurements

    @discardableResult
    public func insert(_ measurement: TreeMeasurement, connection: SQLiteConnection) throws -> WriteOutcome {
        let statement = try connection.cachedStatement("""
            INSERT INTO measurements
                (id, tree_uuid, user_id, device_id, client_uuid, captured_at, gps_accuracy_m,
                 kind, value, unit_entered, si_value, method, measurement_height_m,
                 verification_state, created_at, updated_at, deleted_at)
            VALUES
                (:id, :tree, :user, :device, :client, :captured, :accuracy,
                 :kind, :value, :unit, :si, :method, :height,
                 :verification, :created, :updated, :deleted)
            ON CONFLICT(client_uuid) DO NOTHING
            """)
        _ = try statement.bind([
            ":id": measurement.id,
            ":tree": measurement.treeID,
            ":user": measurement.userID,
            ":device": measurement.deviceID,
            ":client": measurement.clientUUID,
            ":captured": measurement.capturedAt,
            ":accuracy": measurement.gpsAccuracyM,
            ":kind": measurement.kind.rawValue,
            ":value": measurement.quantity.value,
            ":unit": measurement.quantity.unitEntered.rawValue,
            ":si": measurement.quantity.siValue,
            ":method": measurement.quantity.method.rawValue,
            ":height": measurement.measurementHeightM,
            ":verification": measurement.verificationState.rawValue,
            ":created": measurement.createdAt,
            ":updated": measurement.updatedAt,
            ":deleted": measurement.deletedAt
        ])
        return try run(statement, on: connection)
    }

    /// The whole measurement series, oldest first — there is no `LIMIT` here and there must not be
    /// one added: D7's two never-connected chart series are drawn from all of it. If this ever has
    /// to page, it returns a `Series` like `photos` and `visits` do, so the caller keeps knowing.
    public func measurements(treeID: UUID, connection: SQLiteConnection) throws -> [TreeMeasurement] {
        let statement = try connection.cachedStatement("""
            SELECT * FROM measurements
             WHERE tree_uuid = :tree COLLATE NOCASE AND deleted_at IS NULL
             ORDER BY captured_at
            """)
        _ = try statement.bind(treeID.uuidString, forName: ":tree")
        return try statement.fetchAll(Self.decodeMeasurement)
    }

    // MARK: - Care events

    @discardableResult
    public func insert(_ event: CareEvent, connection: SQLiteConnection) throws -> WriteOutcome {
        let statement = try connection.cachedStatement("""
            INSERT INTO care_events
                (id, tree_uuid, user_id, device_id, client_uuid, captured_at, gps_accuracy_m,
                 actions, note, photo_id, created_at, updated_at, deleted_at)
            VALUES
                (:id, :tree, :user, :device, :client, :captured, :accuracy,
                 :actions, :note, :photo, :created, :updated, :deleted)
            ON CONFLICT(client_uuid) DO NOTHING
            """)
        _ = try statement.bind([
            ":id": event.id,
            ":tree": event.treeID,
            ":user": event.userID,
            ":device": event.deviceID,
            ":client": event.clientUUID,
            ":captured": event.capturedAt,
            ":accuracy": event.gpsAccuracyM,
            ":actions": JSONColumn.encode(event.actions.map(\.rawValue)),
            ":note": event.note,
            ":photo": event.photoID,
            ":created": event.createdAt,
            ":updated": event.updatedAt,
            ":deleted": event.deletedAt
        ])
        return try run(statement, on: connection)
    }

    /// This tree's care events, newest first. `limit: nil` reads the series whole.
    ///
    /// A8 counts "distinct users with 2 or more care_events or observations in 24 months" and
    /// renders at 3 or more. Counted over the 50 most recent rows that is not A8's number, it is
    /// A8's number restricted to a page — and it is printed at the contributor as a sentence about
    /// how many people know the tree.
    public func careEvents(treeID: UUID, limit: Int? = nil, connection: SQLiteConnection) throws -> Series<CareEvent> {
        let statement = try connection.cachedStatement("""
            SELECT * FROM care_events
             WHERE tree_uuid = :tree COLLATE NOCASE AND deleted_at IS NULL
             ORDER BY captured_at DESC LIMIT :limit
            """)
        _ = try statement.bind([":tree": treeID.uuidString, ":limit": Self.rowsToRead(for: limit)])
        return Self.series(try statement.fetchAll(Self.decodeCareEvent), limit: limit)
    }

    // MARK: - Favorites (tombstone toggles)

    /// Applies a favorite toggle.
    ///
    /// One row per (owner, tree) whose `deleted_at` carries the current state, so an un-favorite is
    /// a tombstone rather than a hard delete and syncs as an event (BUILD-PLAN §4). A `DELETE`
    /// against this table raises, by trigger, everywhere except the adoption case `claimDevice`
    /// documents.
    ///
    /// Idempotency here is on `client_uuid`, not on the pair: the same toggle replayed twice must
    /// not flip the state back. The `WHERE client_uuid <> :client` guard is what makes the replay a
    /// no-op.
    ///
    /// Two statements rather than one because uniqueness is two partial indexes, and an upsert names
    /// exactly one conflict target (`AppSchema` v5). Which one applies is not a guess — the owner is
    /// known at the call site, which is what exclusive ownership buys.
    @discardableResult
    public func applyFavoriteToggle(
        owner: FavoriteOwner,
        treeID: UUID,
        clientUUID: UUID,
        isFavorite: Bool,
        at date: Date,
        connection: SQLiteConnection
    ) throws -> WriteOutcome {
        // `Core` does not know column names (ARCHITECTURE §2's import discipline), so the mapping
        // from owner to column lives here, as a switch that a third case would break loudly.
        let ownerColumn: String
        switch owner {
        case .user: ownerColumn = "user_id"
        case .device: ownerColumn = "device_id"
        }
        let statement = try connection.cachedStatement(Self.favoriteUpsert(ownerColumn: ownerColumn))
        _ = try statement.bind([
            ":id": UUID(),
            ":user": owner.userID,
            ":device": owner.deviceID,
            ":tree": treeID,
            ":client": clientUUID,
            ":now": date,
            ":deleted": isFavorite ? nil : date
        ])
        return try run(statement, on: connection)
    }

    /// The upsert, written once and pointed at whichever partial index the owner lives under. The
    /// column name is one of two literals from `FavoriteOwner`, never a caller's string.
    private static func favoriteUpsert(ownerColumn: String) -> String {
        """
        INSERT INTO favorites
            (id, user_id, device_id, tree_uuid, client_uuid, created_at, updated_at, deleted_at)
        VALUES (:id, :user, :device, :tree, :client, :now, :now, :deleted)
        ON CONFLICT(\(ownerColumn), tree_uuid) WHERE \(ownerColumn) IS NOT NULL DO UPDATE
           SET deleted_at = excluded.deleted_at,
               updated_at = excluded.updated_at,
               client_uuid = excluded.client_uuid
         WHERE favorites.client_uuid <> excluded.client_uuid
        """
    }

    /// Whether this owner currently holds this tree.
    ///
    /// One owner, stated by the caller — there is no "is anybody's favorite" query and no way to
    /// ask for another owner's, because a favorite is a private bookmark and D1 killed the version
    /// of it that was a public vote. A signed-in contributor who has not claimed this device still
    /// wrote its device-owned rows, so a caller that wants both asks twice.
    public func isFavorite(owner: FavoriteOwner, treeID: UUID, connection: SQLiteConnection) throws -> Bool {
        let statement = try connection.cachedStatement("""
            SELECT deleted_at IS NULL AS active FROM favorites
             WHERE ((:user IS NOT NULL AND user_id = :user COLLATE NOCASE)
                    OR (:device IS NOT NULL AND device_id = :device COLLATE NOCASE))
               AND tree_uuid = :tree COLLATE NOCASE
            """)
        _ = try statement.bind([
            ":user": owner.userID?.uuidString,
            ":device": owner.deviceID?.uuidString,
            ":tree": treeID.uuidString
        ])
        return try statement.fetchOne { try $0.bool("active") } ?? false
    }

    // MARK: - Photos

    /// Writes a photograph, with the owner the column has carried since `AppSchema` v12.
    ///
    /// `owner` is a parameter rather than a property of `Photo` for `localPath`'s reason: the model
    /// is BUILD-PLAN §4's photo and these two are the app database's answer to questions §4 left to
    /// `visit_id`. It is not defaulted, and that is the point — ERRATA E136's hole was a write path
    /// that quietly recorded no owner, and a default here would be a way to write that row again by
    /// forgetting an argument rather than by typing one.
    @discardableResult
    public func insert(
        _ photo: Photo,
        localPath: String?,
        owner: PhotoOwner,
        connection: SQLiteConnection
    ) throws -> WriteOutcome {
        let statement = try connection.cachedStatement("""
            INSERT INTO photos
                (id, tree_uuid, visit_id, storage_key, local_path, shot_type, moderation_state,
                 blur_applied, width, height, captured_at, public_lat, public_lon,
                 created_at, updated_at, deleted_at, user_id, device_id)
            VALUES
                (:id, :tree, :visit, :key, :path, :shot, :moderation,
                 :blur, :width, :height, :captured, :lat, :lon,
                 :created, :updated, :deleted, :user, :device)
            ON CONFLICT(id) DO NOTHING
            """)
        _ = try statement.bind([
            ":user": owner.userID,
            ":device": owner.deviceID,
            ":id": photo.id,
            ":tree": photo.treeID,
            ":visit": photo.visitID,
            ":key": photo.storageKey,
            ":path": localPath,
            ":shot": photo.shotType.rawValue,
            ":moderation": photo.moderationState.rawValue,
            ":blur": photo.blurApplied,
            ":width": photo.width,
            ":height": photo.height,
            ":captured": photo.capturedAt,
            ":lat": photo.publicCoordinate?.latitude,
            ":lon": photo.publicCoordinate?.longitude,
            ":created": photo.createdAt,
            ":updated": photo.updatedAt,
            ":deleted": photo.deletedAt
        ])
        return try run(statement, on: connection)
    }

    public func markPhotoUploaded(id: UUID, storageKey: String, at date: Date, connection: SQLiteConnection) throws {
        let statement = try connection.cachedStatement("""
            UPDATE photos SET storage_key = :key, local_path = NULL, updated_at = :now WHERE id = :id
            """)
        _ = try statement.bind([":key": storageKey, ":now": date, ":id": id])
        try statement.run()
        _ = try statement.reset()
    }

    /// This tree's photo timeline, newest first. `limit: nil` reads the series whole.
    ///
    /// The default used to be 30 and the profile called it with no limit at all, so the hero's
    /// `214 photos · since 2019` was in fact the size and the earliest date *of page one*, and A5's
    /// season strip was computed over the same 30 — a well-photographed tree stopped filling its
    /// strip and could lose months it had shown the year before (ERRATA E38). Hence `Series`: a
    /// page can no longer be counted as if it were the series.
    public func photos(treeID: UUID, limit: Int? = nil, connection: SQLiteConnection) throws -> Series<Photo> {
        let statement = try connection.cachedStatement("""
            SELECT * FROM photos
             WHERE tree_uuid = :tree COLLATE NOCASE AND deleted_at IS NULL
             ORDER BY captured_at DESC LIMIT :limit
            """)
        _ = try statement.bind([":tree": treeID.uuidString, ":limit": Self.rowsToRead(for: limit)])
        return Self.series(try statement.fetchAll(Self.decodePhoto), limit: limit)
    }

    // MARK: - Hero photographs, batched (#176)

    /// One photograph id per tree, chosen by `PhotoHero.choose` — the same rule the profile hero
    /// draws by (ERRATA E125) — for every tree that has at least one live photograph on this
    /// device. This is the rule for "which photograph a thumbnail shows" everywhere but the
    /// profile hero itself, and it is this one function rather than logic repeated at each call
    /// site, so `PhotoHeroIDsTests` can assert it once.
    ///
    /// **One statement, not one per tree and not one per row.** `groveRecords` above answers "what
    /// did this person do, by tree" with a single query scoped to the contributor rather than one
    /// query per tree in the grove; this answers "which photograph, by tree" the same way. It can
    /// be scoped to the contributor alone rather than to a caller-supplied set of tree ids because
    /// `main.photos` holds only what this device wrote (`TreeProfile.ownPhotoIDs`'s comment says
    /// so, and constructs its own set the identical way — every live row) — there is no per-tree
    /// visibility check to make the way the profile makes one for a mixed own/public set, because
    /// every row here already passes it. A personal photo library is small; this is the same order
    /// of magnitude `groveRecords` already reads unscoped.
    ///
    /// What is expensive is decoding a photograph's **bytes**, and this statement never touches
    /// them: it reads the same columns `photos(treeID:)` reads, and hands the chosen id to
    /// `PhotoImage`, which loads and caches pixels through `PhotoImageStore` exactly as the hero
    /// already does (#46). A tree absent from the returned dictionary has no live photograph; the
    /// caller passes that absence straight to `PhotoImage(photoID:)`, which draws its placeholder.
    public func heroPhotoIDs(connection: SQLiteConnection) throws -> [UUID: UUID] {
        let photoStatement = try connection.cachedStatement("""
            SELECT * FROM photos WHERE deleted_at IS NULL
            """)
        let photos = try photoStatement.fetchAll(Self.decodePhoto)
        guard !photos.isEmpty else { return [:] }

        let talliesStatement = try connection.cachedStatement("""
            SELECT photo_id, SUM(vote) AS score FROM photo_votes GROUP BY photo_id
            """)
        let tallyPairs = try talliesStatement.fetchAll { row -> (UUID, Int)? in
            guard let id = try row.uuidIfPresent("photo_id") else { return nil }
            return (id, try row.int("score"))
        }
        let tallies = Dictionary(uniqueKeysWithValues: tallyPairs.compactMap { $0 })
            .mapValues { PhotoTally(score: $0) }

        let byTree = Dictionary(grouping: photos, by: \.treeID)
        return byTree.compactMapValues { PhotoHero.choose(from: $0, tallies: tallies) }.mapValues(\.id)
    }

    /// Where a photo's bytes are on this device, if they are anywhere yet.
    ///
    /// Two columns, because a photograph is in one of two places for a while: `local_path` from the
    /// moment of capture until the outbox drains it, `storage_key` — a filename inside `LocalAPI`'s
    /// own photo directory — from then on. `markPhotoUploaded` sets the second and clears the first
    /// in one statement, so exactly one of them is non-null on a settled row.
    ///
    /// A screen that only read `storage_key` would show nothing for the seconds or minutes between
    /// the shutter and the drain — which is precisely when somebody is looking at the tree they just
    /// photographed. Hence both.
    public func photoBinaryLocation(
        id: UUID,
        connection: SQLiteConnection
    ) throws -> (storageKey: String?, localPath: String?)? {
        let statement = try connection.cachedStatement("""
            SELECT storage_key, local_path FROM photos
             WHERE id = :id COLLATE NOCASE AND deleted_at IS NULL
            """)
        _ = try statement.bind([":id": id.uuidString])
        return try statement.fetchOne { row in
            (storageKey: try row.stringIfPresent("storage_key"),
             localPath: try row.stringIfPresent("local_path"))
        }
    }

    // MARK: - Deleting one photograph (AppSchema v12)

    /// One photograph, as a deletion needs to see it: who owns it, which tree it is on, and where
    /// its bytes are.
    ///
    /// Returned as a whole rather than as four reads because the caller has to hold all four at once
    /// — it checks the owner, removes the files, and only then writes — and two reads of a table
    /// that a third statement is about to change is how a delete ends up removing one photograph's
    /// row and another photograph's file.
    public struct PhotoForDeletion: Sendable, Equatable {
        public let id: UUID
        public let treeID: UUID
        public let owner: PhotoOwner
        public let storageKey: String?
        public let localPath: String?
    }

    /// The photograph a delete is about, or nil when there is no live row with that id.
    public func photoForDeletion(id: UUID, connection: SQLiteConnection) throws -> PhotoForDeletion? {
        let statement = try connection.cachedStatement("""
            SELECT tree_uuid, user_id, device_id, storage_key, local_path FROM photos
             WHERE id = :id COLLATE NOCASE AND deleted_at IS NULL
            """)
        _ = try statement.bind([":id": id.uuidString])
        defer { _ = try? statement.reset() }
        return try statement.fetchOne { row in
            let owner: PhotoOwner
            if let userID = try row.uuidIfPresent("user_id") {
                owner = .user(userID)
            } else if let deviceID = try row.uuidIfPresent("device_id") {
                owner = .device(deviceID)
            } else {
                owner = .nobody
            }
            return PhotoForDeletion(
                id: id,
                treeID: try row.uuid("tree_uuid"),
                owner: owner,
                storageKey: try row.stringIfPresent("storage_key"),
                localPath: try row.stringIfPresent("local_path")
            )
        }
    }

    /// Which of this tree's photographs this installation may delete.
    ///
    /// **Not the same set as `TreeProfile.ownPhotoIDs`, and the difference is the point.** That set
    /// answers "may this device show this photograph to the person holding it", and its answer is
    /// every row in `main.photos`, because nothing syncs anybody else's down and moderation does not
    /// stand between a contributor and their own picture (ERRATA E37). This set answers "may this
    /// person take this photograph back", and an anonymized photograph — one whose contributor
    /// deleted their account through the door that leaves the work in place — is in the first set
    /// and not in this one. Seeing and unmaking are two questions; conflating them would hand a
    /// stranger's withdrawn record to whoever holds the phone next.
    public func deletablePhotoIDs(
        treeID: UUID,
        attribution: Attribution,
        connection: SQLiteConnection
    ) throws -> Set<UUID> {
        let statement = try connection.cachedStatement("""
            SELECT id FROM photos
             WHERE tree_uuid = :tree COLLATE NOCASE AND deleted_at IS NULL
               AND ((:user IS NOT NULL AND user_id = :user COLLATE NOCASE)
                    OR device_id = :device COLLATE NOCASE)
            """)
        _ = try statement.bind([
            ":tree": treeID.uuidString,
            ":user": attribution.userID?.uuidString,
            ":device": attribution.deviceID.uuidString
        ])
        defer { _ = try? statement.reset() }
        return Set(try statement.fetchAll { try $0.uuidIfPresent("id") }.compactMap { $0 })
    }

    /// Which of this tree's photographs have no owner left (task #131).
    ///
    /// **Both columns null**, which is the row `AccountDeletion.anonymizeContributions` leaves: the
    /// leaving door nulls `user_id`, and `photos` carries at most one owner, so a photograph
    /// contributed while signed in has no `device_id` to fall back to. A row still holding a
    /// `device_id` is this phone's unclaimed work and is deletable; a row still holding a `user_id`
    /// is somebody's. Neither is nobody's.
    ///
    /// **Not the complement of `deletablePhotoIDs`.** That set is asked with an attribution and
    /// answers a question about the person holding the phone; this one takes none and answers a
    /// question about the record. They coincide on this device today and would stop coinciding the
    /// moment a row arrived that belonged to somebody else — see `TreeProfile.anonymizedPhotoIDs`
    /// for why a screen that speaks about ownership must read the columns rather than subtract the
    /// permissions.
    public func anonymizedPhotoIDs(
        treeID: UUID,
        connection: SQLiteConnection
    ) throws -> Set<UUID> {
        let statement = try connection.cachedStatement("""
            SELECT id FROM photos
             WHERE tree_uuid = :tree COLLATE NOCASE AND deleted_at IS NULL
               AND user_id IS NULL AND device_id IS NULL
            """)
        _ = try statement.bind([":tree": treeID.uuidString])
        defer { _ = try? statement.reset() }
        return Set(try statement.fetchAll { try $0.uuidIfPresent("id") }.compactMap { $0 })
    }

    /// What one photograph's deletion changed, in rows.
    public struct PhotoDeletionCounts: Sendable, Equatable {
        /// 1 when the row was tombstoned, 0 when the owner predicate matched nothing.
        public var photos: Int = 0
        /// Every vote on it, whoever cast it.
        public var votes: Int = 0
        /// Queued mutations that were still carrying this photograph's staged binary.
        public var stagedBinaries: Int = 0
    }

    /// Tombstones one photograph and strips the row of everything that could find its bytes again.
    ///
    /// **Soft, and stripped, which is not the same as soft alone.** `deleted_at` is the house verb
    /// (BUILD-PLAN §4: "every table that users touch gets soft delete") and it is load-bearing here
    /// for two reasons the erasing door does not have: `private_reminders.photo_id` and
    /// `community_notes.photo_id` both reference `photos(id)`, so a hard delete would take a
    /// *private reminder* — a record only its owner can read — down with a photograph, and the
    /// surviving tombstone is what lets a community-added tree's record still say a photograph was
    /// here and was withdrawn (see `LocalAPI.deletePhoto`).
    ///
    /// A tombstone on its own would be a lie, though, because the reason somebody deletes one
    /// photograph is usually what is *in* it. So the row loses `storage_key`, `local_path`, `width`,
    /// `height` and its fuzzed coordinate in the same statement that sets `deleted_at`; the caller
    /// removes the bytes from disk before this runs. What is left is a photograph's id, its tree,
    /// its shot type, when it was taken and whose it was — the same facts the visit beside it
    /// already carries, and none of them a picture.
    ///
    /// **The owner predicate is in the statement, not only in the caller's guard.** A check made in
    /// Swift and an UPDATE that would have matched anyway are one refactor apart from a delete that
    /// reaches somebody else's photograph.
    ///
    /// **Votes are deleted outright** — every vote on it, not only the owner's. They were judgments
    /// about a photograph that no longer exists, which is exactly `AccountDeletion`'s argument for
    /// the same deletion under the erasing door. Leaving them would also leave a tombstone holding a
    /// tally, and `PhotoHero` reads tallies.
    public func deletePhoto(
        id: UUID,
        attribution: Attribution,
        at date: Date,
        connection: SQLiteConnection
    ) throws -> PhotoDeletionCounts {
        var counts = PhotoDeletionCounts()
        let owned: [String: SQLiteBindable?] = [
            ":id": id.uuidString,
            ":user": attribution.userID?.uuidString,
            ":device": attribution.deviceID.uuidString
        ]

        let votes = try connection.cachedStatement("""
            DELETE FROM photo_votes WHERE photo_id = :id COLLATE NOCASE
              AND EXISTS (SELECT 1 FROM photos p
                           WHERE p.id = :id COLLATE NOCASE AND p.deleted_at IS NULL
                             AND ((:user IS NOT NULL AND p.user_id = :user COLLATE NOCASE)
                                  OR p.device_id = :device COLLATE NOCASE))
            """)
        _ = try votes.bind(owned)
        try votes.run()
        counts.votes = connection.changes
        _ = try votes.reset()

        let photo = try connection.cachedStatement("""
            UPDATE photos
               SET deleted_at = :now, updated_at = :now,
                   storage_key = NULL, local_path = NULL,
                   width = NULL, height = NULL,
                   public_lat = NULL, public_lon = NULL
             WHERE id = :id COLLATE NOCASE AND deleted_at IS NULL
               AND ((:user IS NOT NULL AND user_id = :user COLLATE NOCASE)
                    OR device_id = :device COLLATE NOCASE)
            """)
        var ownedAndNow = owned
        ownedAndNow[":now"] = date
        _ = try photo.bind(ownedAndNow)
        try photo.run()
        counts.photos = connection.changes
        _ = try photo.reset()

        return counts
    }

    // MARK: - Photo votes (AppSchema v8)

    /// Casts or changes one owner's vote on one photograph.
    ///
    /// `tree_uuid` is copied from the photo's own row inside the statement rather than taken as an
    /// argument, so a vote can never be filed against a tree the photograph does not belong to. A
    /// photo that does not exist inserts nothing — the `SELECT` yields no row — which is the right
    /// answer to voting on something that is not there.
    ///
    /// Two statements' worth of conflict targets in one, the way `applyFavoriteToggle` does it: the
    /// owner column is one of two literals chosen by a `switch` here, never a caller's string.
    @discardableResult
    public func setPhotoVote(
        photoID: UUID,
        owner: FavoriteOwner,
        vote: PhotoVote,
        at date: Date,
        connection: SQLiteConnection
    ) throws -> WriteOutcome {
        let ownerColumn: String
        switch owner {
        case .user: ownerColumn = "user_id"
        case .device: ownerColumn = "device_id"
        }
        let statement = try connection.cachedStatement("""
            INSERT INTO photo_votes (id, photo_id, tree_uuid, user_id, device_id, vote, created_at, updated_at)
            SELECT :id, p.id, p.tree_uuid, :user, :device, :vote, :now, :now
              FROM photos p
             WHERE p.id = :photo COLLATE NOCASE AND p.deleted_at IS NULL
            ON CONFLICT(\(ownerColumn), photo_id) WHERE \(ownerColumn) IS NOT NULL DO UPDATE
               SET vote = excluded.vote, updated_at = excluded.updated_at
            """)
        _ = try statement.bind([
            ":id": UUID(),
            ":photo": photoID.uuidString,
            ":user": owner.userID,
            ":device": owner.deviceID,
            ":vote": vote.rawValue,
            ":now": date
        ])
        return try run(statement, on: connection)
    }

    /// Takes a vote back. No tombstone: an un-vote is the absence of a judgment, and a missing row
    /// and a zero score are the same fact (`AppSchema` v8).
    public func clearPhotoVote(photoID: UUID, owner: FavoriteOwner, connection: SQLiteConnection) throws {
        let statement = try connection.cachedStatement("""
            DELETE FROM photo_votes
             WHERE photo_id = :photo COLLATE NOCASE
               AND ((:user IS NOT NULL AND user_id = :user COLLATE NOCASE)
                    OR (:device IS NOT NULL AND device_id = :device COLLATE NOCASE))
            """)
        _ = try statement.bind([
            ":photo": photoID.uuidString,
            ":user": owner.userID?.uuidString,
            ":device": owner.deviceID?.uuidString
        ])
        try statement.run()
        _ = try statement.reset()
    }

    /// Every photograph of this tree that anybody has voted on, with the total and this owner's own.
    ///
    /// The sum is over all voters and the `own` column is one voter's, in one pass, because the hero
    /// and the control that changes it are read at the same moment by the same screen and must not
    /// be able to disagree about which photograph is which.
    public func photoTallies(
        treeID: UUID,
        owner: FavoriteOwner,
        connection: SQLiteConnection
    ) throws -> [UUID: PhotoTally] {
        let statement = try connection.cachedStatement("""
            SELECT photo_id,
                   SUM(vote) AS score,
                   SUM(CASE WHEN (:user IS NOT NULL AND user_id = :user COLLATE NOCASE)
                              OR (:device IS NOT NULL AND device_id = :device COLLATE NOCASE)
                            THEN vote ELSE 0 END) AS own
              FROM photo_votes
             WHERE tree_uuid = :tree COLLATE NOCASE
             GROUP BY photo_id
            """)
        _ = try statement.bind([
            ":tree": treeID.uuidString,
            ":user": owner.userID?.uuidString,
            ":device": owner.deviceID?.uuidString
        ])
        let rows = try statement.fetchAll { row -> (UUID, PhotoTally)? in
            guard let id = try row.uuidIfPresent("photo_id") else { return nil }
            return (id, PhotoTally(
                score: try row.int("score"),
                ownVote: PhotoVote(rawValue: try row.int("own"))
            ))
        }
        return Dictionary(uniqueKeysWithValues: rows.compactMap { $0 })
    }

    /// Erases one account's votes (RULINGS R3). Nothing here needs the deletion sentinel `favorites`
    /// needs, because no trigger guards this table.
    public func deletePhotoVotes(userID: UUID, connection: SQLiteConnection) throws {
        let statement = try connection.cachedStatement("""
            DELETE FROM photo_votes WHERE user_id = :user COLLATE NOCASE
            """)
        _ = try statement.bind([":user": userID.uuidString])
        try statement.run()
        _ = try statement.reset()
    }

    // MARK: - Notes, reminders, flags, names

    @discardableResult
    public func insert(_ note: CommunityNote, connection: SQLiteConnection) throws -> WriteOutcome {
        let statement = try connection.cachedStatement("""
            INSERT INTO community_notes
                (id, tree_uuid, user_id, category, note, photo_id, stale_at, created_at, updated_at, deleted_at)
            VALUES (:id, :tree, :user, :category, :note, :photo, :stale, :created, :updated, :deleted)
            ON CONFLICT(id) DO NOTHING
            """)
        _ = try statement.bind([
            ":id": note.id,
            ":tree": note.treeID,
            ":user": note.userID,
            ":category": note.category.rawValue,
            ":note": note.note,
            ":photo": note.photoID,
            ":stale": note.staleAt,
            ":created": note.createdAt,
            ":updated": note.updatedAt,
            ":deleted": note.deletedAt
        ])
        return try run(statement, on: connection)
    }

    /// Public notes for a tree, excluding stale ones. Hazard categories cannot appear because they
    /// cannot be stored (D4, `AppSchema`'s CHECK).
    ///
    /// No `LIMIT`, and the same rule as `measurements` if that ever changes: the live notes on a
    /// tree are all of them, not the first page of them.
    public func communityNotes(treeID: UUID, at date: Date, connection: SQLiteConnection) throws -> [CommunityNote] {
        let statement = try connection.cachedStatement("""
            SELECT * FROM community_notes
             WHERE tree_uuid = :tree COLLATE NOCASE AND deleted_at IS NULL AND stale_at > :now
             ORDER BY created_at DESC
            """)
        _ = try statement.bind([":tree": treeID.uuidString, ":now": date])
        return try statement.fetchAll(Self.decodeCommunityNote)
    }

    /// D4's private reminder.
    ///
    /// Idempotent on `id`, which is also the mutation's `clientUUID` in the outbox (see
    /// `PrivateReminder`): a replayed reminder reports `.duplicate` and no second row exists, the
    /// same guarantee the other contribution tables get from their `client_uuid` column.
    ///
    /// The owner binds to exactly one of the two columns, and the schema's CHECK rejects any other
    /// combination — so a reminder cannot be stored ownerless even by a hand-written INSERT.
    @discardableResult
    public func insert(_ reminder: PrivateReminder, connection: SQLiteConnection) throws -> WriteOutcome {
        let statement = try connection.cachedStatement("""
            INSERT INTO private_reminders
                (id, user_id, device_id, tree_uuid, category, note, photo_id,
                 created_at, updated_at, deleted_at)
            VALUES (:id, :user, :device, :tree, :category, :note, :photo, :created, :updated, :deleted)
            ON CONFLICT(id) DO NOTHING
            """)
        _ = try statement.bind([
            ":id": reminder.id,
            ":user": reminder.owner.userID,
            ":device": reminder.owner.deviceID,
            ":tree": reminder.treeID,
            ":category": reminder.category.rawValue,
            ":note": reminder.note,
            ":photo": reminder.photoID,
            ":created": reminder.createdAt,
            ":updated": reminder.updatedAt,
            ":deleted": reminder.deletedAt
        ])
        return try run(statement, on: connection)
    }

    /// The reminders one contributor can see: their account's, plus this device's own.
    ///
    /// Both halves are needed at once because ownership moves at sign-in and nothing forces a claim
    /// to have happened — a signed-in contributor who has never claimed this device still wrote the
    /// device-owned rows in front of them. There is no "everyone's reminders" query and no way to
    /// ask for another owner's: a caller states who it is, and privacy is the shape of the API
    /// rather than a filter someone can forget (D4, DECISIONS §3.11).
    public func privateReminders(
        userID: UUID?,
        deviceID: UUID?,
        limit: Int = 50,
        connection: SQLiteConnection
    ) throws -> [PrivateReminder] {
        let statement = try connection.cachedStatement("""
            SELECT * FROM private_reminders
             WHERE deleted_at IS NULL
               AND ((:user IS NOT NULL AND user_id = :user COLLATE NOCASE)
                    OR (:device IS NOT NULL AND device_id = :device COLLATE NOCASE))
             ORDER BY created_at DESC LIMIT :limit
            """)
        _ = try statement.bind([
            ":user": userID?.uuidString,
            ":device": deviceID?.uuidString,
            ":limit": limit
        ])
        return try statement.fetchAll(Self.decodePrivateReminder)
    }

    @discardableResult
    public func insert(_ flag: ReviewFlag, connection: SQLiteConnection) throws -> WriteOutcome {
        let statement = try connection.cachedStatement("""
            INSERT INTO review_flags (id, tree_uuid, kind, raised_by, status, created_at, updated_at, deleted_at)
            VALUES (:id, :tree, :kind, :by, :status, :created, :updated, :deleted)
            ON CONFLICT(id) DO NOTHING
            """)
        _ = try statement.bind([
            ":id": flag.id,
            ":tree": flag.treeID,
            ":kind": flag.kind.rawValue,
            ":by": flag.raisedBy,
            ":status": flag.status.rawValue,
            ":created": flag.createdAt,
            ":updated": flag.updatedAt,
            ":deleted": flag.deletedAt
        ])
        return try run(statement, on: connection)
    }

    // MARK: - Moderation (ERRATA E124-B)

    /// The open flags a lead has to act on, newest first, across every kind asked for.
    ///
    /// **Plural since ERRATA E170.** It used to take one `kind`, on the reasoning that "the removal
    /// queue and (a future) dead-tree queue are separate lists" — and the future queue was never
    /// built, so the one caller passed `.appearsRemoved` and every `appears_dead` flag screen 05
    /// raised was invisible to the only surface that could close it. One list, and the row says which
    /// kind it is; see `ReviewFlag.Kind.confirmedStatus`.
    ///
    /// Scoped to `status = 'open'` because a confirmed or dismissed flag is done. The index
    /// `(tree_uuid, status)` is not the one that serves this, so it is a small scan over a table that
    /// holds one row per raised concern, not per tree.
    ///
    /// An empty `kinds` returns nothing rather than everything: "no kinds" is not "all kinds", and a
    /// query that widened when its filter emptied is how a queue starts showing rows nobody can act
    /// on. The placeholders are generated from the count, so the SQL text is one of a handful and
    /// `cachedStatement` still caches it.
    public func openReviewFlags(kinds: [ReviewFlag.Kind], connection: SQLiteConnection) throws -> [ReviewFlag] {
        guard !kinds.isEmpty else { return [] }
        let names = (0..<kinds.count).map { ":kind\($0)" }
        let statement = try connection.cachedStatement("""
            SELECT * FROM review_flags
             WHERE kind IN (\(names.joined(separator: ", "))) AND status = 'open' AND deleted_at IS NULL
             ORDER BY created_at DESC
            """)
        var bindings: [String: SQLiteBindable?] = [:]
        for (name, kind) in zip(names, kinds) { bindings[name] = kind.rawValue }
        _ = try statement.bind(bindings)
        return try statement.fetchAll(Self.decodeReviewFlag)
    }

    /// One flag by id, for the confirm path that has to read a flag's tree before it acts on it.
    public func reviewFlag(id: UUID, connection: SQLiteConnection) throws -> ReviewFlag? {
        let statement = try connection.cachedStatement("SELECT * FROM review_flags WHERE id = :id")
        _ = try statement.bind([":id": id.uuidString])
        return try statement.fetchOne(Self.decodeReviewFlag)
    }

    /// Move an open flag to `confirmed`. Guarded on `status = 'open'` so a second confirmation (two
    /// leads, or a double tap) changes nothing and reports `.duplicate` — the confirmation is a
    /// transition, not a toggle, and the row records who has already made it.
    @discardableResult
    public func confirmReviewFlag(id: UUID, at date: Date, connection: SQLiteConnection) throws -> WriteOutcome {
        let statement = try connection.cachedStatement("""
            UPDATE review_flags SET status = 'confirmed', updated_at = :now
             WHERE id = :id AND status = 'open' AND deleted_at IS NULL
            """)
        _ = try statement.bind([":id": id.uuidString, ":now": date])
        return try run(statement, on: connection)
    }

    /// Move an open flag to `dismissed` — a lead saying the report is wrong (ERRATA E170).
    ///
    /// `ReviewFlag.Status.dismissed` has existed since the model was written and nothing wrote it,
    /// so a lead who disagreed with a report could only leave it open forever. Guarded on
    /// `status = 'open'` for the same reason `confirmReviewFlag` is: it is a transition, not a
    /// toggle, and a dismiss arriving after a confirm must change nothing.
    @discardableResult
    public func dismissReviewFlag(id: UUID, at date: Date, connection: SQLiteConnection) throws -> WriteOutcome {
        let statement = try connection.cachedStatement("""
            UPDATE review_flags SET status = 'dismissed', updated_at = :now
             WHERE id = :id AND status = 'open' AND deleted_at IS NULL
            """)
        _ = try statement.bind([":id": id.uuidString, ":now": date])
        return try run(statement, on: connection)
    }

    /// Record — or replace — a device-side status override for a tree (see `AppSchema.v7`). One row
    /// per tree: `INSERT … ON CONFLICT(tree_uuid) DO UPDATE`, because a tree has one current status.
    public func setStatusOverride(
        treeID: UUID,
        status: TreeStatus,
        setBy: UUID?,
        at date: Date,
        connection: SQLiteConnection
    ) throws {
        let statement = try connection.cachedStatement("""
            INSERT INTO tree_status_overrides (tree_uuid, status, set_by, created_at)
            VALUES (:tree, :status, :by, :created)
            ON CONFLICT(tree_uuid) DO UPDATE SET
                status = excluded.status, set_by = excluded.set_by, created_at = excluded.created_at
            """)
        _ = try statement.bind([
            ":tree": treeID.uuidString,
            ":status": status.rawValue,
            ":by": setBy?.uuidString,
            ":created": date
        ])
        _ = try run(statement, on: connection)
    }

    /// Every override this device holds, as a lookup `LocalAPI` layers over a tree's inventory status
    /// (`mapContent`, `treeProfile`). Small by construction — one row per locally-moderated tree — so
    /// it is read whole rather than joined into each seed query across the ATTACH boundary.
    public func statusOverrides(connection: SQLiteConnection) throws -> [UUID: TreeStatus] {
        let statement = try connection.cachedStatement("SELECT tree_uuid, status FROM tree_status_overrides")
        let rows = try statement.fetchAll { row -> (UUID, TreeStatus) in
            (try row.uuid("tree_uuid"), try row.value("status", TreeStatus.self))
        }
        return Dictionary(rows, uniquingKeysWith: { _, latest in latest })
    }

    /// Empties the table `statusOverrides` reads (ERRATA E217 "Still open"). Whole-table, with no
    /// predicate, because the harness that calls this wants the device back to holding none — the
    /// same reason `debugClearPhotos` in `LocalAPI` takes a tree rather than a photograph.
    public func clearStatusOverrides(connection: SQLiteConnection) throws {
        let statement = try connection.cachedStatement("DELETE FROM tree_status_overrides")
        try statement.run()
        _ = try statement.reset()
    }

    // MARK: - The map's membership sets (#116, RULINGS R23)

    /// Every tree this reader has contributed to — screen 01's `Yours` chip.
    ///
    /// The four contribution tables unioned, exactly as `GroveQueries.ownContributions` unions them
    /// and for the same reason: "standing in front of a tree with the camera, rating it, taping it
    /// and watering it are all having been there". `DISTINCT` because a tree visited four times is
    /// one tree on a map, and because **nothing here may produce a count** — D1, and
    /// ARCHITECTURE §5.1's "if you find yourself writing `visitCount` into a user-visible string,
    /// stop". This returns a set of ids; there is no `COUNT(*)` in it and no caller could get one.
    ///
    /// Community-added trees are unioned in as well. A tree you added is not in any of the four
    /// contribution tables — it is the row in `community_trees` — and it is the most emphatically
    /// yours there is, so a `Yours` map that omitted it would be wrong in the one case the reader
    /// would notice first.
    ///
    /// **That arm carries no owner clause, because the table carries no owner columns**, and this is
    /// correct rather than a hole: `community_trees` has neither `user_id` nor `device_id`, and it
    /// does not need them, because there is no sync that brings anybody else's rows down — every row
    /// in `main.community_trees` is one this installation wrote. `CommunityTreeStore` relies on the
    /// same fact, and `TreeProfile.ownPhotoIDs` states it in the same words: "`main.photos` holds
    /// what this device wrote and nothing else". If a `RemoteAPI` ever lands rows from elsewhere,
    /// this arm needs an owner clause on the same day the columns arrive — and the schema change is
    /// where that will be noticed, because this query will not compile against a table it has to
    /// filter and cannot.
    ///
    /// Privacy is the shape of the query (D11): the caller states who it is, both owners are read
    /// because a row saved before sign-in and a row saved after are both this person's
    /// (`grove()` makes the same argument), and there is no form of this SQL that returns anybody
    /// else's rows.
    public func contributedTreeIDs(
        userID: UUID?,
        deviceID: UUID,
        connection: SQLiteConnection
    ) throws -> Set<UUID> {
        let owner = """
             WHERE deleted_at IS NULL
               AND (device_id = :device COLLATE NOCASE
                    OR (:user IS NOT NULL AND user_id = :user COLLATE NOCASE))
            """
        let statement = try connection.cachedStatement("""
            SELECT DISTINCT tree_uuid FROM (
                SELECT tree_uuid FROM visits \(owner)
                UNION ALL
                SELECT tree_uuid FROM observations \(owner)
                UNION ALL
                SELECT tree_uuid FROM measurements \(owner)
                UNION ALL
                SELECT tree_uuid FROM care_events \(owner)
                UNION ALL
                SELECT id AS tree_uuid FROM community_trees WHERE deleted_at IS NULL
            )
            """)
        let bindings: [String: SQLiteBindable?] = [":device": deviceID, ":user": userID]
        _ = try statement.bind(bindings)
        return Set(try statement.fetchAll { try $0.uuid("tree_uuid") })
    }

    /// Every tree this reader is still holding a favorite on — screen 01's `Favorites` chip.
    ///
    /// `deleted_at IS NULL` is the whole of it and it matters more here than anywhere else on this
    /// type: a favorite is a toggle with a tombstone (BUILD-PLAN §4), so an un-favorited tree
    /// keeps its row and would come back as a favorite from any query that forgot the clause.
    /// `DeviceContributions.favorites` makes the same call in the same words.
    public func favoriteTreeIDs(
        userID: UUID?,
        deviceID: UUID,
        connection: SQLiteConnection
    ) throws -> Set<UUID> {
        let statement = try connection.cachedStatement("""
            SELECT DISTINCT tree_uuid FROM favorites
             WHERE deleted_at IS NULL
               AND (device_id = :device COLLATE NOCASE
                    OR (:user IS NOT NULL AND user_id = :user COLLATE NOCASE))
            """)
        let bindings: [String: SQLiteBindable?] = [":device": deviceID, ":user": userID]
        _ = try statement.bind(bindings)
        return Set(try statement.fetchAll { try $0.uuid("tree_uuid") })
    }

    /// `favoriteTreeIDs` narrowed to one tree — screen 03's heart, re-read after a write (#167).
    ///
    /// The same predicate as `favoriteTreeIDs` above, on purpose: both ownership arms, because a
    /// favorite saved before sign-in is the device's until a claim moves it (E89), and
    /// `deleted_at IS NULL` because an un-favorite is a tombstone, not an absence.
    public func holdsFavorite(
        userID: UUID?,
        deviceID: UUID,
        treeID: UUID,
        connection: SQLiteConnection
    ) throws -> Bool {
        let statement = try connection.cachedStatement("""
            SELECT 1 AS held FROM favorites
             WHERE deleted_at IS NULL
               AND tree_uuid = :tree COLLATE NOCASE
               AND (device_id = :device COLLATE NOCASE
                    OR (:user IS NOT NULL AND user_id = :user COLLATE NOCASE))
             LIMIT 1
            """)
        let bindings: [String: SQLiteBindable?] = [
            ":tree": treeID.uuidString, ":device": deviceID, ":user": userID
        ]
        _ = try statement.bind(bindings)
        return try statement.fetchOne { _ in true } ?? false
    }

    /// First namer wins (D15). The partial unique index on `(tree_uuid) WHERE status = 'active'`
    /// makes a second active name a constraint violation rather than a race.
    @discardableResult
    public func insert(_ name: TreeName, connection: SQLiteConnection) throws -> WriteOutcome {
        let statement = try connection.cachedStatement("""
            INSERT INTO tree_names (id, tree_uuid, name, given_by, status, created_at, updated_at, deleted_at)
            VALUES (:id, :tree, :name, :by, :status, :created, :updated, :deleted)
            ON CONFLICT(id) DO NOTHING
            """)
        _ = try statement.bind([
            ":id": name.id,
            ":tree": name.treeID,
            ":name": name.name,
            ":by": name.givenBy,
            ":status": name.status.rawValue,
            ":created": name.createdAt,
            ":updated": name.updatedAt,
            ":deleted": name.deletedAt
        ])
        return try run(statement, on: connection)
    }

    public func activeName(treeID: UUID, connection: SQLiteConnection) throws -> TreeName? {
        let statement = try connection.cachedStatement("""
            SELECT * FROM tree_names
             WHERE tree_uuid = :tree COLLATE NOCASE AND status = 'active' AND deleted_at IS NULL
             LIMIT 1
            """)
        _ = try statement.bind(treeID.uuidString, forName: ":tree")
        return try statement.fetchOne(Self.decodeTreeName)
    }

    /// `POST /reports/hazard-redirect`. Analytics only, no public record (D4).
    public func log(_ event: HazardRedirectEvent, connection: SQLiteConnection) throws {
        let statement = try connection.cachedStatement("""
            INSERT INTO hazard_redirects (id, tree_uuid, category, shown_at)
            VALUES (:id, :tree, :category, :shown)
            """)
        _ = try statement.bind([
            ":id": UUID(),
            ":tree": event.treeID,
            ":category": event.category.rawValue,
            ":shown": event.shownAt
        ])
        try statement.run()
        _ = try statement.reset()
    }

    // MARK: - Personal surfaces

    /// `GET /me/grove` — favorited and visited trees. Carries no counts (D1).
    public func groveTreeIDs(userID: UUID?, deviceID: UUID, connection: SQLiteConnection) throws -> [(treeID: UUID, lastVisitedAt: Date?, isFavorite: Bool)] {
        let statement = try connection.cachedStatement("""
            SELECT tree_uuid,
                   MAX(last_visited) AS last_visited,
                   MAX(is_favorite)  AS is_favorite
              FROM (
                    SELECT tree_uuid, MAX(captured_at) AS last_visited, 0 AS is_favorite
                      FROM visits
                     WHERE deleted_at IS NULL
                       AND (device_id = :device COLLATE NOCASE
                            OR (:user IS NOT NULL AND user_id = :user COLLATE NOCASE))
                       -- A visit an account deletion anonymized is nobody's, including this
                       -- phone's, so it does not put a tree in the next person's grove
                       -- (`AppSchema` v13). The favorites arm below needs no such clause: a
                       -- favorite is deleted with its account under both doors.
                       AND \(Self.notAnonymized("visits"))
                     GROUP BY tree_uuid
                    UNION ALL
                    -- Both owners, for the reason the visits arm above reads both: a favorite saved
                    -- before sign-in is the device's until a claim moves it, and nothing forces a
                    -- claim to have happened (E89, and the same argument as `privateReminders`).
                    -- Reading only the user's arm is what made the heart's absence invisible.
                    SELECT tree_uuid, NULL AS last_visited, 1 AS is_favorite
                      FROM favorites
                     WHERE deleted_at IS NULL
                       AND (device_id = :device COLLATE NOCASE
                            OR (:user IS NOT NULL AND user_id = :user COLLATE NOCASE))
                   )
             GROUP BY tree_uuid
             ORDER BY last_visited DESC NULLS LAST
            """)
        _ = try statement.bind([":device": deviceID.uuidString, ":user": userID?.uuidString])
        return try statement.fetchAll { row in
            (
                treeID: try row.uuid("tree_uuid"),
                lastVisitedAt: try row.dateIfPresent("last_visited"),
                isFavorite: try row.boolIfPresent("is_favorite") ?? false
            )
        }
    }

    /// What this contributor has done to each tree in their grove, by kind.
    ///
    /// **`COUNT(*)` rather than a page's size**, so these are totals and may be rendered as such —
    /// the engine answers the whole predicate, the same argument `deviceContributions` makes and the
    /// distinction ERRATA E38 exists for. There is no limit on this statement and there must not be:
    /// a limited read here would produce a plausible small number, and a plausible small number about
    /// a person's own history is E38's exact failure.
    ///
    /// **Why counting here is not what `GroveQueries`' header forbids.** That file says "nothing here
    /// counts contributions", on D1's grounds, and it is still true of that file: it feeds the species
    /// ring, whose numerator is a count of *species*, and a `COUNT(*)` of contributions there would be
    /// a tally of a person's activity with nothing else it could be. This is a different question with
    /// a different subject — what one relationship with one tree consists of, never summed, never
    /// ordered on, never compared. `GroveRecord` argues that at length, and it is the type that has to
    /// hold the line, not this comment.
    ///
    /// Privacy is the shape of the query, as in `groveTreeIDs` above: the caller states who it is and
    /// there is no form of this SQL that returns somebody else's rows (D11). Tombstones are excluded,
    /// because a deleted contribution is not something a person did that still stands.
    ///
    /// Trees with no contributions at all — a favorite nobody has visited — are simply absent from
    /// the result; the caller reads a missing key as `GroveRecord.none`, which is what it is.
    public func groveRecords(
        userID: UUID?,
        deviceID: UUID,
        connection: SQLiteConnection
    ) throws -> [UUID: GroveRecord] {
        let statement = try connection.cachedStatement("""
            SELECT tree_uuid, kind, COUNT(*) AS n FROM (
                SELECT tree_uuid, 'visit' AS kind, user_id, device_id, client_uuid, deleted_at FROM visits
                UNION ALL
                SELECT tree_uuid, 'observation', user_id, device_id, client_uuid, deleted_at FROM observations
                UNION ALL
                SELECT tree_uuid, 'measurement', user_id, device_id, client_uuid, deleted_at FROM measurements
                UNION ALL
                SELECT tree_uuid, 'care_event', user_id, device_id, client_uuid, deleted_at FROM care_events
            ) record
             WHERE deleted_at IS NULL
               AND (device_id = :device COLLATE NOCASE
                    OR (:user IS NOT NULL AND user_id = :user COLLATE NOCASE))
               -- `journal`'s clause, for the same reason (`AppSchema` v13).
               AND \(Self.notAnonymized("record"))
             GROUP BY tree_uuid, kind
            """)
        _ = try statement.bind([":device": deviceID.uuidString, ":user": userID?.uuidString])

        var visits: [UUID: Int] = [:]
        var checkIns: [UUID: Int] = [:]
        var measurements: [UUID: Int] = [:]
        var careEvents: [UUID: Int] = [:]
        _ = try statement.fetchAll { row -> Void in
            let tree = try row.uuid("tree_uuid")
            let count = try row.int("n")
            switch try row.string("kind") {
            case "visit": visits[tree] = count
            case "observation": checkIns[tree] = count
            case "measurement": measurements[tree] = count
            default: careEvents[tree] = count
            }
        }

        let trees = Set(visits.keys)
            .union(checkIns.keys)
            .union(measurements.keys)
            .union(careEvents.keys)
        return Dictionary(uniqueKeysWithValues: trees.map { tree in
            (
                tree,
                GroveRecord(
                    visits: visits[tree] ?? 0,
                    checkIns: checkIns[tree] ?? 0,
                    measurements: measurements[tree] ?? 0,
                    careEvents: careEvents[tree] ?? 0
                )
            )
        })
    }

    /// `GET /me/journal`. One stream over the four contribution kinds, newest first.
    ///
    /// The cursor is the `captured_at` of the last row returned, which is stable under insertion —
    /// contributions are append-only and are never back-dated past a page boundary.
    ///
    /// **The device arm reads "this phone's own unclaimed work", and a record an account deletion
    /// anonymized is not that** (`AppSchema` v13). Without the tombstone clause, the person who signs
    /// in on a handed-down phone opens their journal and reads a stranger's visits — the rows kept
    /// their `device_id`, which is the whole of what the device arm asks for. The user arm cannot
    /// reach them either way, because an anonymized row has no `user_id`; the clause is written once
    /// at the top rather than inside the device arm for that reason.
    public func journal(
        userID: UUID?,
        deviceID: UUID,
        before cursor: Date?,
        limit: Int,
        connection: SQLiteConnection
    ) throws -> [(id: UUID, kind: JournalEntry.Kind, treeID: UUID, capturedAt: Date, summary: String)] {
        let statement = try connection.cachedStatement("""
            SELECT id, kind, tree_uuid, captured_at, summary FROM (
                SELECT id, 'visit' AS kind, tree_uuid, captured_at, COALESCE(note, '') AS summary,
                       user_id, device_id, client_uuid, deleted_at FROM visits
                UNION ALL
                SELECT id, 'observation', tree_uuid, captured_at,
                       COALESCE(status, '') || CASE WHEN vitality IS NULL THEN ''
                                                    ELSE ' · vitality ' || vitality END,
                       user_id, device_id, client_uuid, deleted_at FROM observations
                UNION ALL
                SELECT id, 'measurement', tree_uuid, captured_at,
                       kind || ' ' || value || ' ' || unit_entered || ', ' || method,
                       user_id, device_id, client_uuid, deleted_at FROM measurements
                UNION ALL
                SELECT id, 'careEvent', tree_uuid, captured_at, actions,
                       user_id, device_id, client_uuid, deleted_at FROM care_events
            ) entry
            WHERE deleted_at IS NULL
              AND (device_id = :device COLLATE NOCASE
                   OR (:user IS NOT NULL AND user_id = :user COLLATE NOCASE))
              AND \(Self.notAnonymized("entry"))
              AND (:cursor IS NULL OR captured_at < :cursor)
            ORDER BY captured_at DESC
            LIMIT :limit
            """)
        _ = try statement.bind([
            ":device": deviceID.uuidString,
            ":user": userID?.uuidString,
            ":cursor": cursor.map(SQLiteTimestamp.string(from:)),
            ":limit": limit
        ])
        return try statement.fetchAll { row in
            (
                id: try row.uuid("id"),
                kind: try row.value("kind", JournalEntry.Kind.self),
                treeID: try row.uuid("tree_uuid"),
                capturedAt: try row.date("captured_at"),
                summary: try row.stringIfPresent("summary") ?? ""
            )
        }
    }

    /// `POST /devices/claim` — attributes this device's anonymous contributions to a user (D9).
    ///
    /// Every contribution table is updated in one transaction: three visits made before sign-in
    /// must all arrive attributed, or none should (BUILD-PLAN §12, M2 acceptance).
    ///
    /// Idempotent, in the only way that matters here: every statement is an UPDATE whose WHERE
    /// clause stops matching once it has run. Nothing inserts, so nothing can duplicate; nothing
    /// deletes, so nothing can be orphaned. A second claim by the same user matches zero rows, and a
    /// claim by a *different* user leaves already-attributed rows alone rather than stealing them —
    /// the `user_id IS NULL` guard is what makes both true.
    ///
    /// **What it will not adopt, ever: a record a deletion anonymized** (`AppSchema` v13, ERRATA —
    /// see E157). `user_id IS NULL AND device_id = :device`
    /// used to be the whole definition of *this device's unclaimed work*, and it was one state too
    /// broad. `leaveRecords` nulls `user_id` and — correctly — leaves `device_id`, so a record its
    /// author deliberately unlinked from themselves matched this predicate exactly and was adopted
    /// by the **next** account signed in on the phone. On a shared or handed-down device that is a
    /// re-identification of somebody who asked not to be identifiable.
    ///
    /// `Self.notAnonymized` is the difference between *anonymized by a deletion* and *never had an
    /// account*, which are two states this predicate could not previously tell apart. Both halves
    /// still matter: the second is D9's own case — an unsigned-in contributor keeping their own work
    /// on their own phone — and it is precisely why the fix is not "clear `device_id` as well".
    public func claimDevice(deviceUUID: UUID, userID: UUID, at date: Date, connection: SQLiteConnection) throws {
        for table in ["visits", "observations", "measurements", "care_events"] {
            let statement = try connection.cachedStatement("""
                UPDATE \(table) SET user_id = :user, updated_at = :now
                 WHERE device_id = :device COLLATE NOCASE AND user_id IS NULL
                   AND \(Self.notAnonymized(table))
                """)
            _ = try statement.bind([":user": userID, ":now": date, ":device": deviceUUID.uuidString])
            try statement.run()
            _ = try statement.reset()
        }

        // D4's reminder, adopted by the same mechanism (ERRATA E23). It is not in the loop above
        // because ownership here is exclusive: the account gains the row and the device link is
        // dropped in the same statement, so the "exactly one owner" CHECK holds at every instant and
        // the reminder carries strictly less about the device afterwards than before. A reminder
        // written *after* sign-in already has `user_id` and is not matched.
        let reminders = try connection.cachedStatement("""
            UPDATE private_reminders SET user_id = :user, device_id = NULL, updated_at = :now
             WHERE device_id = :device COLLATE NOCASE AND user_id IS NULL
            """)
        _ = try reminders.bind([":user": userID, ":now": date, ":device": deviceUUID.uuidString])
        try reminders.run()
        _ = try reminders.reset()

        // The photograph, adopted on the reminder's terms rather than the visit's (`AppSchema` v12,
        // ERRATA E136). It is not in the loop above because `photos` carries at most one owner: the
        // account gains the row and the device link is dropped in the same statement, so a
        // photograph never says both whose account it is and which phone it was taken on. The
        // `user_id IS NULL` guard also leaves an *anonymized* photograph alone — a row whose owner
        // deleted their account through the leaving door has no `device_id` either, so it matches
        // nothing here and cannot be adopted by the next person to sign in on this phone.
        let photos = try connection.cachedStatement("""
            UPDATE photos SET user_id = :user, device_id = NULL, updated_at = :now
             WHERE device_id = :device COLLATE NOCASE AND user_id IS NULL
            """)
        _ = try photos.bind([":user": userID, ":now": date, ":device": deviceUUID.uuidString])
        try photos.run()
        _ = try photos.reset()

        try claimFavorites(deviceUUID: deviceUUID, userID: userID, at: date, connection: connection)
        try claimPhotoVotes(deviceUUID: deviceUUID, userID: userID, at: date, connection: connection)

        let device = try connection.cachedStatement("""
            INSERT INTO device (id, device_uuid, user_id, created_at, updated_at)
            VALUES (:id, :uuid, :user, :now, :now)
            ON CONFLICT(device_uuid) DO UPDATE SET user_id = excluded.user_id, updated_at = excluded.updated_at
            """)
        _ = try device.bind([":id": UUID(), ":uuid": deviceUUID, ":user": userID, ":now": date])
        try device.run()
        _ = try device.reset()
    }

    /// The favorites half of `POST /devices/claim`, which is the half with a collision in it
    /// (ERRATA E89).
    ///
    /// A reminder's adoption is one UPDATE because two reminders are never the same record. Two
    /// favorites can be: the device favorited a tree that the account it is now claiming had
    /// *already* favorited from somewhere else. Both rows then say one thing — "this tree is mine" —
    /// and after the claim only one owner exists, so one row has to carry both histories. Left
    /// alone, the plain UPDATE would hit `idx_favorites_user_tree` and abort the whole claim, which
    /// would mean sign-in fails for the contributor whose grove overlaps most.
    ///
    /// Three statements, in this order, each an UPDATE or a narrowly-predicated DELETE whose WHERE
    /// stops matching once it has run:
    ///
    /// 1. **The later statement wins.** Where both owners hold a tree and the device's row is the
    ///    more recent, its state, its `client_uuid` and its timestamp move onto the account's row.
    ///    A favorite is a toggle event with a tombstone (BUILD-PLAN §4 and §6), and a toggle
    ///    resolves by time: whichever the person said last is what they meant. Timestamps compare as
    ///    strings because `SQLiteTimestamp` writes fixed-width UTC ISO-8601 — lexicographic order is
    ///    chronological order.
    /// 2. **The superseded device row goes.** It is the one row the tombstone trigger permits
    ///    deleting, and only because its event has just been folded onto the surviving row for the
    ///    same tree, in this transaction — which is the loss the trigger exists to prevent. Keeping
    ///    it instead would leave the account and the device each holding a row for one tree, which
    ///    is the permanent device↔account link exclusive ownership exists to avoid.
    ///    The device row is the one dropped rather than the account's because the account's may have
    ///    an identity beyond this phone; the device's has never left it.
    /// 3. **Everything else moves**, exactly as a reminder does: `user_id` set, `device_id` cleared,
    ///    with a `user_id IS NULL` guard so a claim by a different account cannot steal an
    ///    already-attributed row.
    ///
    /// Nothing is inserted, so nothing can duplicate; the only delete is the merge above, so nothing
    /// is orphaned. A second claim matches nothing at all.
    private func claimFavorites(
        deviceUUID: UUID,
        userID: UUID,
        at date: Date,
        connection: SQLiteConnection
    ) throws {
        // 1 — the device's later word overwrites the account's earlier one.
        let merge = try connection.cachedStatement("""
            UPDATE favorites
               SET deleted_at  = (SELECT d.deleted_at FROM favorites d
                                   WHERE d.tree_uuid = favorites.tree_uuid
                                     AND d.user_id IS NULL AND d.device_id = :device COLLATE NOCASE),
                   client_uuid = (SELECT d.client_uuid FROM favorites d
                                   WHERE d.tree_uuid = favorites.tree_uuid
                                     AND d.user_id IS NULL AND d.device_id = :device COLLATE NOCASE),
                   updated_at  = (SELECT d.updated_at FROM favorites d
                                   WHERE d.tree_uuid = favorites.tree_uuid
                                     AND d.user_id IS NULL AND d.device_id = :device COLLATE NOCASE)
             WHERE favorites.user_id = :user COLLATE NOCASE
               AND EXISTS (SELECT 1 FROM favorites d
                            WHERE d.tree_uuid = favorites.tree_uuid
                              AND d.user_id IS NULL AND d.device_id = :device COLLATE NOCASE
                              AND d.updated_at > favorites.updated_at)
            """)
        _ = try merge.bind([":user": userID, ":device": deviceUUID.uuidString])
        try merge.run()
        _ = try merge.reset()

        // 2 — the folded-away row, which is the trigger's one permitted delete.
        let drop = try connection.cachedStatement("""
            DELETE FROM favorites
             WHERE user_id IS NULL AND device_id = :device COLLATE NOCASE
               AND EXISTS (SELECT 1 FROM favorites mine
                            WHERE mine.tree_uuid = favorites.tree_uuid
                              AND mine.user_id = :user COLLATE NOCASE)
            """)
        _ = try drop.bind([":user": userID, ":device": deviceUUID.uuidString])
        try drop.run()
        _ = try drop.reset()

        // 3 — and the ones with nothing to collide with simply move.
        let adopt = try connection.cachedStatement("""
            UPDATE favorites SET user_id = :user, device_id = NULL, updated_at = :now
             WHERE device_id = :device COLLATE NOCASE AND user_id IS NULL
            """)
        _ = try adopt.bind([":user": userID, ":now": date, ":device": deviceUUID.uuidString])
        try adopt.run()
        _ = try adopt.reset()
    }

    /// `claimFavorites`' shape, one table over and two statements shorter (`AppSchema` v8).
    ///
    /// A vote can collide the same way a favorite can — the same photograph voted from the device
    /// before sign-in and from the account after — and it resolves the same way: whichever the
    /// person said last is what they meant. What it does not need is the tombstone dance. There is
    /// no trigger on `photo_votes`, so the superseded row is simply deleted rather than being
    /// deleted under an exception; and there is nothing to merge beyond the vote itself, because a
    /// vote is one integer with no state behind it.
    private func claimPhotoVotes(
        deviceUUID: UUID,
        userID: UUID,
        at date: Date,
        connection: SQLiteConnection
    ) throws {
        // 1 — the device's later word overwrites the account's earlier one.
        let merge = try connection.cachedStatement("""
            UPDATE photo_votes
               SET vote       = (SELECT d.vote FROM photo_votes d
                                  WHERE d.photo_id = photo_votes.photo_id
                                    AND d.user_id IS NULL AND d.device_id = :device COLLATE NOCASE),
                   updated_at = (SELECT d.updated_at FROM photo_votes d
                                  WHERE d.photo_id = photo_votes.photo_id
                                    AND d.user_id IS NULL AND d.device_id = :device COLLATE NOCASE)
             WHERE photo_votes.user_id = :user COLLATE NOCASE
               AND EXISTS (SELECT 1 FROM photo_votes d
                            WHERE d.photo_id = photo_votes.photo_id
                              AND d.user_id IS NULL AND d.device_id = :device COLLATE NOCASE
                              AND d.updated_at > photo_votes.updated_at)
            """)
        _ = try merge.bind([":user": userID, ":device": deviceUUID.uuidString])
        try merge.run()
        _ = try merge.reset()

        // 2 — the superseded device row goes.
        let drop = try connection.cachedStatement("""
            DELETE FROM photo_votes
             WHERE user_id IS NULL AND device_id = :device COLLATE NOCASE
               AND EXISTS (SELECT 1 FROM photo_votes mine
                            WHERE mine.photo_id = photo_votes.photo_id
                              AND mine.user_id = :user COLLATE NOCASE)
            """)
        _ = try drop.bind([":user": userID, ":device": deviceUUID.uuidString])
        try drop.run()
        _ = try drop.reset()

        // 3 — and the rest move.
        let adopt = try connection.cachedStatement("""
            UPDATE photo_votes SET user_id = :user, device_id = NULL, updated_at = :now
             WHERE device_id = :device COLLATE NOCASE AND user_id IS NULL
            """)
        _ = try adopt.bind([":user": userID, ":now": date, ":device": deviceUUID.uuidString])
        try adopt.run()
        _ = try adopt.reset()
    }

    /// The account this device has already been claimed by, if any — the `device` row `claimDevice`
    /// wrote.
    ///
    /// It exists because a claim is a fact with a lifetime, not an event. `claimDevice` sweeps the
    /// rows that are in the tables *at the moment it runs*, and the outbox means a mutation can be
    /// written before sign-in and applied after it: queued offline on Tuesday, signed in on
    /// Wednesday, drained on Thursday. That row arrives carrying the anonymous attribution it was
    /// built with, lands with `user_id IS NULL`, and the sweep that would have adopted it has
    /// already been and gone — so the contributor signs in, is told their work is kept, and the last
    /// items in the queue quietly stay the device's for ever.
    ///
    /// `LocalAPI.sync` reads this after a batch and re-runs the claim when it is non-nil, which is
    /// idempotent by the same argument as above. The device row is the durable half of the claim,
    /// which is what makes this answerable at all.
    public func claimedUser(forDevice deviceUUID: UUID, connection: SQLiteConnection) throws -> UUID? {
        let statement = try connection.cachedStatement("""
            SELECT user_id FROM device WHERE device_uuid = :uuid COLLATE NOCASE
            """)
        _ = try statement.bind([":uuid": deviceUUID.uuidString])
        return try statement.fetchOne { try $0.uuidIfPresent("user_id") } ?? nil
    }

    // MARK: - What the device is holding (D9, screen 15)

    /// The five record kinds `claimDevice` moves, counted for this device while they are still
    /// unattributed.
    ///
    /// `COUNT(*)` rather than a page's size: this is the whole predicate answered by the engine, so
    /// it is a total and may be rendered as one (contrast `Series.totalCount`, and ERRATA E38 for
    /// what happens when a page is read as a total).
    ///
    /// Tombstoned rows are excluded — `deleted_at IS NULL` — because the sentence this feeds is
    /// about what a person would keep, and a deleted row is not something they have.
    ///
    /// So is a record an account deletion anonymized (`AppSchema` v13). This number is the promise
    /// screen 15 makes and `claimDevice` keeps, and the two have to be counted by the same
    /// predicate: leave the tombstone out here and the screen offers to keep three visits that the
    /// claim then declines to move — a broken promise made *by the count*, on the one surface where
    /// a person could notice. `deviceContributions` and `claimDevice` are one rule read twice.
    public func deviceContributions(
        deviceUUID: UUID,
        connection: SQLiteConnection
    ) throws -> DeviceContributions {
        func count(_ table: String, canBeAnonymized: Bool = false) throws -> Int {
            // The four append-only kinds carry a `client_uuid` and survive a deletion unattributed,
            // so they are the four that can hold a v13 tombstone. `private_reminders` has no
            // `client_uuid` at all and `favorites` is deleted with its account under both doors, so
            // neither can — and asking would be a SQL error on the first of them.
            let tombstone = canBeAnonymized ? "AND \(Self.notAnonymized(table))" : ""
            let statement = try connection.cachedStatement("""
                SELECT COUNT(*) AS n FROM \(table)
                 WHERE device_id = :device COLLATE NOCASE
                   AND user_id IS NULL
                   AND deleted_at IS NULL
                   \(tombstone)
                """)
            _ = try statement.bind([":device": deviceUUID.uuidString])
            defer { _ = try? statement.reset() }
            return try statement.fetchOne { try $0.int("n") } ?? 0
        }

        return DeviceContributions(
            visits: try count("visits", canBeAnonymized: true),
            checkIns: try count("observations", canBeAnonymized: true),
            measurements: try count("measurements", canBeAnonymized: true),
            careEvents: try count("care_events", canBeAnonymized: true),
            // Exclusive ownership (E23): a device-owned reminder has `user_id IS NULL` and a
            // `device_id`, so the same predicate reads it correctly.
            privateReminders: try count("private_reminders"),
            // And a favorite, on the same terms, since v5 (E89). `deleted_at IS NULL` matters more
            // here than anywhere else on this type: a favorite that was turned off is a tombstone,
            // and a tombstone is not something a person would say they have.
            favorites: try count("favorites")
        )
    }

    // MARK: - Paging

    // MARK: - The tombstone (AppSchema v13)

    /// "This record is still somebody's to claim" — the clause that keeps a contribution anonymized
    /// by an account deletion out of every device-scoped predicate in this file.
    ///
    /// **Why it is a constant and not five hand-written subqueries.** The guarantee is only worth
    /// what its least careful reader honors. `user_id IS NULL AND device_id = :device` appears in
    /// `claimDevice`, in `deviceContributions`, in `journal`, in `groveTreeIDs` and in
    /// `groveRecords`, and it means the same thing in all five: *the work of the phone in your hand*.
    /// A tombstone applied to the claim alone would stop the rows being adopted and go on showing
    /// them, so the next person to sign in would read a stranger's visits in their own journal and be
    /// offered a count of records the claim then refuses to move — the promise visibly broken in the
    /// one place a person can see it. One clause, named once, is what makes "all five" checkable.
    ///
    /// It reads `client_uuid` rather than `id` because that is the key a contribution has before it
    /// is stored as well as after: the tombstone for a queued mutation is written from its payload
    /// while it is still in the outbox (`OutboxStore.forgetAccount`), and is waiting when the drain
    /// finally inserts the row.
    ///
    /// `NOT EXISTS` over a one-column primary key, so the plan is a point lookup per candidate row on
    /// a table that holds tens of rows at most, against tables that hold tens to hundreds.
    ///
    /// **The qualifier is required and is not a style choice.** Written
    /// `WHERE t.client_uuid = client_uuid`, SQLite resolves the bare name in the *inner* scope first
    /// and the condition becomes `t.client_uuid = t.client_uuid` — true for every row of a non-empty
    /// table, so `NOT EXISTS` is false for every candidate and the claim silently adopts nothing at
    /// all. A guarantee that fails closed on a name-resolution rule is not one, so the caller names
    /// the table it is filtering.
    static func notAnonymized(_ qualifier: String) -> String {
        """
        NOT EXISTS (SELECT 1 FROM anonymized_contributions tomb
                     WHERE tomb.client_uuid = \(qualifier).client_uuid)
        """
    }

    /// How many rows to ask SQLite for, given what the caller wants.
    ///
    /// One more than the caller asked for, so the answer to "was that all of them?" comes from the
    /// database rather than from a guess: a page that comes back short is provably the whole series.
    /// A negative `LIMIT` is SQLite's documented "no upper bound", which is what `nil` means here.
    static func rowsToRead(for limit: Int?) -> Int {
        guard let limit else { return -1 }
        return max(limit, 0) + 1
    }

    /// Trims the extra row back off and records what its presence proved.
    static func series<Element>(_ rows: [Element], limit: Int?) -> Series<Element> {
        guard let limit else { return Series(complete: rows) }
        let wanted = max(limit, 0)
        return Series(items: Array(rows.prefix(wanted)), isComplete: rows.count <= wanted)
    }

    // MARK: - Helpers

    private func run(_ statement: SQLiteStatement, on connection: SQLiteConnection) throws -> WriteOutcome {
        try statement.run()
        let changed = connection.changes
        _ = try statement.reset()
        return changed > 0 ? .inserted : .duplicate
    }

    // MARK: - Decoding

    static func decodeVisit(_ row: SQLiteRow) throws -> Visit {
        Visit(
            id: try row.uuid("id"),
            treeID: try row.uuid("tree_uuid"),
            attribution: Attribution(userID: try row.uuidIfPresent("user_id"), deviceID: try row.uuid("device_id")),
            clientUUID: try row.uuid("client_uuid"),
            note: try row.stringIfPresent("note"),
            phenologyTags: JSONColumn.decodeRawValues(PhenologyTag.self, try row.stringIfPresent("phenology_tags")),
            gpsAccuracyM: try row.doubleIfPresent("gps_accuracy_m"),
            capturedAt: try row.date("captured_at"),
            createdAt: try row.date("created_at"),
            updatedAt: try row.date("updated_at"),
            deletedAt: try row.dateIfPresent("deleted_at")
        )
    }

    static func decodeObservation(_ row: SQLiteRow) throws -> TreeObservation {
        TreeObservation(
            id: try row.uuid("id"),
            treeID: try row.uuid("tree_uuid"),
            attribution: Attribution(userID: try row.uuidIfPresent("user_id"), deviceID: try row.uuid("device_id")),
            clientUUID: try row.uuid("client_uuid"),
            capturedAt: try row.date("captured_at"),
            gpsAccuracyM: try row.doubleIfPresent("gps_accuracy_m"),
            status: try row.enumIfPresent("status", ObservationStatus.self),
            vitality: try row.enumIfPresent("vitality", Vitality.self),
            foliage: JSONColumn.decode(FoliageAssessment.self, try row.stringIfPresent("foliage")),
            structureFlags: JSONColumn.decodeRawValues(StructureFlag.self, try row.stringIfPresent("structure_flags")),
            note: try row.stringIfPresent("note"),
            verificationState: try row.value("verification_state", VerificationState.self),
            createdAt: try row.date("created_at"),
            updatedAt: try row.date("updated_at"),
            deletedAt: try row.dateIfPresent("deleted_at")
        )
    }

    static func decodeMeasurement(_ row: SQLiteRow) throws -> TreeMeasurement {
        let attribution = Attribution(
            userID: try row.uuidIfPresent("user_id"),
            deviceID: try row.uuid("device_id")
        )
        // `Quantity` has no initializer that omits `method` (D7), so a row that somehow lost its
        // method cannot be reconstructed — which is the point. The CHECK constraint makes such a
        // row unstorable in the first place.
        let quantity = Quantity(
            value: try row.double("value"),
            unit: try row.value("unit_entered", LengthUnit.self),
            method: try row.value("method", MeasurementMethod.self)
        )
        let common = (
            id: try row.uuid("id"),
            treeID: try row.uuid("tree_uuid"),
            clientUUID: try row.uuid("client_uuid"),
            capturedAt: try row.date("captured_at"),
            accuracy: try row.doubleIfPresent("gps_accuracy_m"),
            verification: try row.value("verification_state", VerificationState.self),
            createdAt: try row.date("created_at"),
            updatedAt: try row.date("updated_at"),
            deletedAt: try row.dateIfPresent("deleted_at")
        )

        switch try row.value("kind", MeasurementKind.self) {
        case .dbh:
            return TreeMeasurement.dbh(
                id: common.id, treeID: common.treeID, attribution: attribution,
                clientUUID: common.clientUUID, capturedAt: common.capturedAt,
                gpsAccuracyM: common.accuracy, quantity: quantity,
                measurementHeightM: try row.doubleIfPresent("measurement_height_m")
                    ?? TreeMeasurement.defaultDBHMeasurementHeightM,
                verificationState: common.verification,
                createdAt: common.createdAt, updatedAt: common.updatedAt, deletedAt: common.deletedAt
            )
        case .height:
            return TreeMeasurement.height(
                id: common.id, treeID: common.treeID, attribution: attribution,
                clientUUID: common.clientUUID, capturedAt: common.capturedAt,
                gpsAccuracyM: common.accuracy, quantity: quantity,
                verificationState: common.verification,
                createdAt: common.createdAt, updatedAt: common.updatedAt, deletedAt: common.deletedAt
            )
        }
    }

    static func decodeCareEvent(_ row: SQLiteRow) throws -> CareEvent {
        CareEvent(
            id: try row.uuid("id"),
            treeID: try row.uuid("tree_uuid"),
            attribution: Attribution(userID: try row.uuidIfPresent("user_id"), deviceID: try row.uuid("device_id")),
            clientUUID: try row.uuid("client_uuid"),
            capturedAt: try row.date("captured_at"),
            gpsAccuracyM: try row.doubleIfPresent("gps_accuracy_m"),
            actions: JSONColumn.decodeRawValues(CareAction.self, try row.stringIfPresent("actions")),
            note: try row.stringIfPresent("note"),
            photoID: try row.uuidIfPresent("photo_id"),
            createdAt: try row.date("created_at"),
            updatedAt: try row.date("updated_at"),
            deletedAt: try row.dateIfPresent("deleted_at")
        )
    }

    static func decodePhoto(_ row: SQLiteRow) throws -> Photo {
        let latitude = try row.doubleIfPresent("public_lat")
        let longitude = try row.doubleIfPresent("public_lon")
        return Photo(
            id: try row.uuid("id"),
            treeID: try row.uuid("tree_uuid"),
            visitID: try row.uuidIfPresent("visit_id"),
            storageKey: try row.stringIfPresent("storage_key"),
            shotType: try row.value("shot_type", ShotType.self),
            moderationState: try row.value("moderation_state", ModerationState.self),
            blurApplied: try row.bool("blur_applied"),
            width: try row.intIfPresent("width"),
            height: try row.intIfPresent("height"),
            capturedAt: try row.date("captured_at"),
            publicCoordinate: (latitude != nil && longitude != nil)
                ? Coordinate(latitude: latitude!, longitude: longitude!) : nil,
            createdAt: try row.date("created_at"),
            updatedAt: try row.date("updated_at"),
            deletedAt: try row.dateIfPresent("deleted_at")
        )
    }

    static func decodeCommunityNote(_ row: SQLiteRow) throws -> CommunityNote {
        CommunityNote(
            id: try row.uuid("id"),
            treeID: try row.uuid("tree_uuid"),
            userID: try row.uuid("user_id"),
            category: try row.value("category", CommunityNote.Category.self),
            note: try row.stringIfPresent("note"),
            photoID: try row.uuidIfPresent("photo_id"),
            createdAt: try row.date("created_at"),
            staleAt: try row.date("stale_at"),
            updatedAt: try row.date("updated_at"),
            deletedAt: try row.dateIfPresent("deleted_at")
        )
    }

    static func decodePrivateReminder(_ row: SQLiteRow) throws -> PrivateReminder {
        // No `?? .device(...)` fallback and no default owner. The schema's CHECK makes an ownerless
        // row unstorable, so a row that has neither is corruption, and inventing an owner for it
        // would attribute someone's private record to a party that never wrote it.
        let owner: ReminderOwner
        if let userID = try row.uuidIfPresent("user_id") {
            owner = .user(userID)
        } else if let deviceID = try row.uuidIfPresent("device_id") {
            owner = .device(deviceID)
        } else {
            throw APIError.validationFailed
        }
        return PrivateReminder(
            id: try row.uuid("id"),
            owner: owner,
            treeID: try row.uuid("tree_uuid"),
            category: try row.value("category", HazardCategory.self),
            note: try row.stringIfPresent("note"),
            photoID: try row.uuidIfPresent("photo_id"),
            createdAt: try row.date("created_at"),
            updatedAt: try row.date("updated_at"),
            deletedAt: try row.dateIfPresent("deleted_at")
        )
    }

    static func decodeTreeName(_ row: SQLiteRow) throws -> TreeName {
        TreeName(
            id: try row.uuid("id"),
            treeID: try row.uuid("tree_uuid"),
            name: try row.string("name"),
            givenBy: try row.uuidIfPresent("given_by"),
            status: try row.value("status", TreeName.Status.self),
            createdAt: try row.date("created_at"),
            updatedAt: try row.date("updated_at"),
            deletedAt: try row.dateIfPresent("deleted_at")
        )
    }

    static func decodeReviewFlag(_ row: SQLiteRow) throws -> ReviewFlag {
        ReviewFlag(
            id: try row.uuid("id"),
            treeID: try row.uuid("tree_uuid"),
            kind: try row.value("kind", ReviewFlag.Kind.self),
            raisedBy: try row.uuidIfPresent("raised_by"),
            status: try row.value("status", ReviewFlag.Status.self),
            createdAt: try row.date("created_at"),
            updatedAt: try row.date("updated_at"),
            deletedAt: try row.dateIfPresent("deleted_at")
        )
    }
}

/// JSON-in-TEXT columns. `Core` stays serialization-agnostic; the codecs live here (see the
/// coding-key note in `Core/Models/CoreEntity.swift`).
public enum JSONColumn {
    public static func encode<T: Encodable>(_ value: T) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func decode<T: Decodable>(_ type: T.Type, _ json: String?) -> T? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// A JSON array of enum raw values. Unknown members are dropped: a client one version behind
    /// should render the tags it understands, not fail the whole row.
    public static func decodeRawValues<T: RawRepresentable>(_ type: T.Type, _ json: String?) -> [T]
    where T.RawValue == String {
        guard let raw = decode([String].self, json) else { return [] }
        return raw.compactMap(T.init(rawValue:))
    }
}
