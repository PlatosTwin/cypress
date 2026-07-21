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

    public func visits(treeID: UUID, limit: Int = 50, connection: SQLiteConnection) throws -> [Visit] {
        let statement = try connection.cachedStatement("""
            SELECT * FROM visits
             WHERE tree_uuid = :tree COLLATE NOCASE AND deleted_at IS NULL
             ORDER BY captured_at DESC LIMIT :limit
            """)
        _ = try statement.bind([":tree": treeID.uuidString, ":limit": limit])
        return try statement.fetchAll(Self.decodeVisit)
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

    public func careEvents(treeID: UUID, limit: Int = 50, connection: SQLiteConnection) throws -> [CareEvent] {
        let statement = try connection.cachedStatement("""
            SELECT * FROM care_events
             WHERE tree_uuid = :tree COLLATE NOCASE AND deleted_at IS NULL
             ORDER BY captured_at DESC LIMIT :limit
            """)
        _ = try statement.bind([":tree": treeID.uuidString, ":limit": limit])
        return try statement.fetchAll(Self.decodeCareEvent)
    }

    // MARK: - Favorites (tombstone toggles)

    /// Applies a favourite toggle.
    ///
    /// One row per (user, tree) whose `deleted_at` carries the current state, so an un-favourite is
    /// a tombstone rather than a hard delete and syncs as an event (BUILD-PLAN §4). A `DELETE`
    /// against this table raises, by trigger.
    ///
    /// Idempotency here is on `client_uuid`, not on the pair: the same toggle replayed twice must
    /// not flip the state back. The `WHERE client_uuid <> :client` guard is what makes the replay a
    /// no-op.
    @discardableResult
    public func applyFavoriteToggle(
        userID: UUID,
        treeID: UUID,
        clientUUID: UUID,
        isFavorite: Bool,
        at date: Date,
        connection: SQLiteConnection
    ) throws -> WriteOutcome {
        let statement = try connection.cachedStatement("""
            INSERT INTO favorites (id, user_id, tree_uuid, client_uuid, created_at, updated_at, deleted_at)
            VALUES (:id, :user, :tree, :client, :now, :now, :deleted)
            ON CONFLICT(user_id, tree_uuid) DO UPDATE
               SET deleted_at = excluded.deleted_at,
                   updated_at = excluded.updated_at,
                   client_uuid = excluded.client_uuid
             WHERE favorites.client_uuid <> excluded.client_uuid
            """)
        _ = try statement.bind([
            ":id": UUID(),
            ":user": userID,
            ":tree": treeID,
            ":client": clientUUID,
            ":now": date,
            ":deleted": isFavorite ? nil : date
        ])
        return try run(statement, on: connection)
    }

    public func isFavorite(userID: UUID, treeID: UUID, connection: SQLiteConnection) throws -> Bool {
        let statement = try connection.cachedStatement("""
            SELECT deleted_at IS NULL AS active FROM favorites
             WHERE user_id = :user COLLATE NOCASE AND tree_uuid = :tree COLLATE NOCASE
            """)
        _ = try statement.bind([":user": userID.uuidString, ":tree": treeID.uuidString])
        return try statement.fetchOne { try $0.bool("active") } ?? false
    }

    // MARK: - Photos

    @discardableResult
    public func insert(_ photo: Photo, localPath: String?, connection: SQLiteConnection) throws -> WriteOutcome {
        let statement = try connection.cachedStatement("""
            INSERT INTO photos
                (id, tree_uuid, visit_id, storage_key, local_path, shot_type, moderation_state,
                 blur_applied, width, height, captured_at, public_lat, public_lon,
                 created_at, updated_at, deleted_at)
            VALUES
                (:id, :tree, :visit, :key, :path, :shot, :moderation,
                 :blur, :width, :height, :captured, :lat, :lon,
                 :created, :updated, :deleted)
            ON CONFLICT(id) DO NOTHING
            """)
        _ = try statement.bind([
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

    public func photos(treeID: UUID, limit: Int = 30, connection: SQLiteConnection) throws -> [Photo] {
        let statement = try connection.cachedStatement("""
            SELECT * FROM photos
             WHERE tree_uuid = :tree COLLATE NOCASE AND deleted_at IS NULL
             ORDER BY captured_at DESC LIMIT :limit
            """)
        _ = try statement.bind([":tree": treeID.uuidString, ":limit": limit])
        return try statement.fetchAll(Self.decodePhoto)
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
    public func communityNotes(treeID: UUID, at date: Date, connection: SQLiteConnection) throws -> [CommunityNote] {
        let statement = try connection.cachedStatement("""
            SELECT * FROM community_notes
             WHERE tree_uuid = :tree COLLATE NOCASE AND deleted_at IS NULL AND stale_at > :now
             ORDER BY created_at DESC
            """)
        _ = try statement.bind([":tree": treeID.uuidString, ":now": date])
        return try statement.fetchAll(Self.decodeCommunityNote)
    }

    @discardableResult
    public func insert(_ reminder: PrivateReminder, connection: SQLiteConnection) throws -> WriteOutcome {
        let statement = try connection.cachedStatement("""
            INSERT INTO private_reminders
                (id, user_id, tree_uuid, category, note, photo_id, created_at, updated_at, deleted_at)
            VALUES (:id, :user, :tree, :category, :note, :photo, :created, :updated, :deleted)
            ON CONFLICT(id) DO NOTHING
            """)
        _ = try statement.bind([
            ":id": reminder.id,
            ":user": reminder.userID,
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

    /// `GET /me/grove` — favourited and visited trees. Carries no counts (D1).
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
                     GROUP BY tree_uuid
                    UNION ALL
                    SELECT tree_uuid, NULL AS last_visited, 1 AS is_favorite
                      FROM favorites
                     WHERE deleted_at IS NULL AND :user IS NOT NULL AND user_id = :user COLLATE NOCASE
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

    /// `GET /me/journal`. One stream over the four contribution kinds, newest first.
    ///
    /// The cursor is the `captured_at` of the last row returned, which is stable under insertion —
    /// contributions are append-only and are never back-dated past a page boundary.
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
                       user_id, device_id, deleted_at FROM visits
                UNION ALL
                SELECT id, 'observation', tree_uuid, captured_at,
                       COALESCE(status, '') || CASE WHEN vitality IS NULL THEN ''
                                                    ELSE ' · vitality ' || vitality END,
                       user_id, device_id, deleted_at FROM observations
                UNION ALL
                SELECT id, 'measurement', tree_uuid, captured_at,
                       kind || ' ' || value || ' ' || unit_entered || ', ' || method,
                       user_id, device_id, deleted_at FROM measurements
                UNION ALL
                SELECT id, 'careEvent', tree_uuid, captured_at, actions,
                       user_id, device_id, deleted_at FROM care_events
            )
            WHERE deleted_at IS NULL
              AND (device_id = :device COLLATE NOCASE
                   OR (:user IS NOT NULL AND user_id = :user COLLATE NOCASE))
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
    public func claimDevice(deviceUUID: UUID, userID: UUID, at date: Date, connection: SQLiteConnection) throws {
        for table in ["visits", "observations", "measurements", "care_events"] {
            let statement = try connection.cachedStatement("""
                UPDATE \(table) SET user_id = :user, updated_at = :now
                 WHERE device_id = :device COLLATE NOCASE AND user_id IS NULL
                """)
            _ = try statement.bind([":user": userID, ":now": date, ":device": deviceUUID.uuidString])
            try statement.run()
            _ = try statement.reset()
        }

        let device = try connection.cachedStatement("""
            INSERT INTO device (id, device_uuid, user_id, created_at, updated_at)
            VALUES (:id, :uuid, :user, :now, :now)
            ON CONFLICT(device_uuid) DO UPDATE SET user_id = excluded.user_id, updated_at = excluded.updated_at
            """)
        _ = try device.bind([":id": UUID(), ":uuid": deviceUUID, ":user": userID, ":now": date])
        try device.run()
        _ = try device.reset()
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
