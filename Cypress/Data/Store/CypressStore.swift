import Foundation

/// The app's storage, opened once and handed to `LocalAPI`.
///
/// Owns the writable database in Application Support, the read-only seed attached beside it, and
/// the facts about the seed that the query layer needs but should not re-derive per query.
public final class CypressStore: Sendable {
    /// Serializes every statement (ARCHITECTURE §3).
    public let queue: DatabaseQueue
    /// The shape the attached seed turned out to have. `nil` when no seed is attached — a state
    /// only tests and the "no inventory shipped yet" case reach.
    public let seed: SeedSchema?
    /// Whether `seed.trees` contains any soft-deleted row.
    ///
    /// Measured once at open (~18 ms against 195,309 rows) because the answer changes only when the
    /// bundle changes, and because it decides between two viewport queries that differ by 4× in
    /// wall-clock. See `TreeQueries` for why.
    public let seedHasSoftDeletedTrees: Bool
    /// Where `main` lives, for diagnostics and for the "delete my data" path.
    public let databaseURL: URL

    private init(queue: DatabaseQueue, seed: SeedSchema?, seedHasSoftDeletedTrees: Bool, databaseURL: URL) {
        self.queue = queue
        self.seed = seed
        self.seedHasSoftDeletedTrees = seedHasSoftDeletedTrees
        self.databaseURL = databaseURL
    }

    // MARK: - Opening

    /// The app's writable database.
    ///
    /// Application Support rather than Documents: this is app-managed state the user never sees as
    /// a file, and Documents is surfaced by file-sharing. It is backed up, which is correct — the
    /// outbox holds field work that has not synced anywhere yet, and BUILD-PLAN's whole posture is
    /// that field work is too expensive to lose.
    public static func defaultDatabaseURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base
            .appendingPathComponent("Cypress", isDirectory: true)
            .appendingPathComponent("cypress.sqlite", isDirectory: false)
    }

    /// Opens the store: writable database, migrations, seed attached read-only.
    ///
    /// A missing seed is not fatal. The outbox, the profile of a community-added tree, and every
    /// write path work without it; only the city inventory is absent. That keeps a build whose
    /// 92 MB resource has not landed yet from failing to launch.
    public static func open(
        databaseURL: URL? = nil,
        seedURL: URL? = SeedDatabase.urlInBundle(),
        migrations: [Migration] = AppSchema.migrations
    ) async throws -> CypressStore {
        let url = try databaseURL ?? defaultDatabaseURL()
        let queue = try DatabaseQueue(url: url)

        let (schema, hasSoftDeletes) = try await queue.withConnection { connection -> (SeedSchema?, Bool) in
            try SchemaMigrator.migrate(migrations, on: connection)

            guard let seedURL else { return (nil, false) }
            let schema = try SeedDatabase.attach(seedURL, to: connection)

            let statement = try connection.prepare(
                "SELECT EXISTS(SELECT 1 FROM \(SeedDatabase.schemaName).trees WHERE deleted_at IS NOT NULL) AS present"
            )
            defer { statement.finalize() }
            let present = try statement.fetchOne { try $0.bool("present") } ?? false
            return (schema, present)
        }

        return CypressStore(
            queue: queue,
            seed: schema,
            seedHasSoftDeletedTrees: hasSoftDeletes,
            databaseURL: url
        )
    }

    /// An in-memory store with the app schema migrated and, optionally, a seed attached. For tests
    /// and previews.
    public static func inMemory(
        seedURL: URL? = nil,
        migrations: [Migration] = AppSchema.migrations
    ) async throws -> CypressStore {
        let queue = try DatabaseQueue.inMemory()
        let (schema, hasSoftDeletes) = try await queue.withConnection { connection -> (SeedSchema?, Bool) in
            try SchemaMigrator.migrate(migrations, on: connection)
            guard let seedURL else { return (nil, false) }
            let schema = try SeedDatabase.attach(seedURL, to: connection)
            let statement = try connection.prepare(
                "SELECT EXISTS(SELECT 1 FROM \(SeedDatabase.schemaName).trees WHERE deleted_at IS NOT NULL) AS present"
            )
            defer { statement.finalize() }
            let present = try statement.fetchOne { try $0.bool("present") } ?? false
            return (schema, present)
        }
        return CypressStore(
            queue: queue,
            seed: schema,
            seedHasSoftDeletedTrees: hasSoftDeletes,
            databaseURL: URL(fileURLWithPath: ":memory:")
        )
    }

    // MARK: - App state

    /// Reads a value from the `app_state` key/value table.
    public func appState(_ key: AppStateKey) async throws -> String? {
        try await queue.read { connection in
            let statement = try connection.cachedStatement("SELECT value FROM app_state WHERE key = :key")
            _ = try statement.bind(key.rawValue, forName: ":key")
            return try statement.fetchOne { try $0.string("value") }
        }
    }

    public func setAppState(_ key: AppStateKey, to value: String) async throws {
        try await queue.write { connection in
            let statement = try connection.cachedStatement("""
                INSERT INTO app_state (key, value) VALUES (:key, :value)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value
                """)
            _ = try statement.bind([":key": key.rawValue, ":value": value])
            try statement.run()
            _ = try statement.reset()
        }
    }
}

/// The keys `app_state` recognizes. An enum rather than free strings so a typo is a compile error
/// and the set of persisted settings is enumerable.
public enum AppStateKey: String, CaseIterable, Sendable {
    /// Screen 17's toggle. "Sync photos on wifi only"; notes and numbers sync on any connection.
    case syncPhotosOnWifiOnly = "sync_photos_on_wifi_only"
    /// This installation's device UUID (D9).
    case deviceUUID = "device_uuid"
    /// The signed-in user, when there is one. Contributions made before sign-in stay attributed to
    /// the device until `POST /devices/claim` migrates them.
    case currentUserID = "current_user_id"
    /// The signed-in account's role (`UserRole`), for the local moderation route (ERRATA E124-B).
    /// Absent means `member`. There is no `users` table on device (ERRATA E86), so a role — like the
    /// user id itself — is carried in `app_state` rather than on a user row.
    case currentUserRole = "current_user_role"
}
