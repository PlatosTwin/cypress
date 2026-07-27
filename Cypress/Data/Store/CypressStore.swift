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
    /// Which city inventory the attached seed was built from, and when it was taken.
    ///
    /// Read once at open from `seed_meta`, for the same reason as `seedHasSoftDeletedTrees`: it is
    /// one row of a table that cannot change while the bundle does not, and re-reading it per tree
    /// page would be 133,577 identical queries a day. `nil` when no seed is attached, or when the
    /// attached seed predates the receipt keys — see `InventorySource`.
    public let seedProvenance: InventorySource?
    /// **Every inventory the attached seed holds rows from**, keyed by the identifier
    /// `trees.inventory_source` stores.
    ///
    /// The shipped seed is built from two: SF Public Works' operational layer decides which trees
    /// exist, and the DataSF export supplies the vacant planting sites, which the layer has no
    /// category for. `seedProvenance` above is the file's *primary* inventory and is the wrong
    /// answer for 12,260 of its rows, so a per-row provenance line resolves through here instead.
    ///
    /// Read once at open with the rest of the receipt. Empty for a seed built before the
    /// `inventory_<id>_*` keys existed, in which case `seedProvenance` is the only answer there is
    /// and it is the right one, because such a seed came from one inventory.
    public let seedInventories: [String: InventorySource]
    /// Where `main` lives, for diagnostics and for the "delete my data" path.
    public let databaseURL: URL

    private init(
        queue: DatabaseQueue,
        seed: SeedSchema?,
        seedHasSoftDeletedTrees: Bool,
        seedMeta: [String: String],
        databaseURL: URL
    ) {
        self.queue = queue
        self.seed = seed
        self.seedHasSoftDeletedTrees = seedHasSoftDeletedTrees
        self.seedProvenance = InventorySource(seedMeta: seedMeta)
        self.seedInventories = Self.inventories(in: seedMeta)
        self.databaseURL = databaseURL
    }

    /// The attached seed's build receipt, as a dictionary. Empty when the table is absent, which is
    /// how a seed built before `seed_meta` existed reads — an absent receipt is not an error.
    static func readSeedMeta(connection: SQLiteConnection) -> [String: String] {
        guard let statement = try? connection.prepare(
            "SELECT key, value FROM \(SeedDatabase.schemaName).seed_meta"
        ) else { return [:] }
        defer { statement.finalize() }
        guard let rows = try? statement.fetchAll({ (try $0.string("key"), try $0.string("value")) })
        else { return [:] }
        return Dictionary(rows, uniquingKeysWith: { first, _ in first })
    }

    /// Every `inventory_<id>_name` key in the receipt, resolved. Plus the file's primary inventory,
    /// so a seed that predates those keys still answers for its own rows.
    ///
    /// Key-driven rather than a fixed list of two: the identifiers belong to `Tools/build_seed.py`,
    /// and a build that one day sources a third thing should not need this file edited to be able
    /// to name it.
    static func inventories(in seedMeta: [String: String]) -> [String: InventorySource] {
        var found: [String: InventorySource] = [:]
        for key in seedMeta.keys where key.hasPrefix("inventory_") && key.hasSuffix("_name") {
            let id = String(key.dropFirst("inventory_".count).dropLast("_name".count))
            if let source = InventorySource(id: id, seedMeta: seedMeta) { found[id] = source }
        }
        if let primary = InventorySource(seedMeta: seedMeta), found[primary.id] == nil {
            found[primary.id] = primary
        }
        return found
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

        let (schema, hasSoftDeletes, seedMeta) = try await queue.withConnection {
            connection -> (SeedSchema?, Bool, [String: String]) in
            try SchemaMigrator.migrate(migrations, on: connection)

            guard let seedURL else { return (nil, false, [:]) }
            let schema = try SeedDatabase.attach(seedURL, to: connection)

            let statement = try connection.prepare(
                "SELECT EXISTS(SELECT 1 FROM \(SeedDatabase.schemaName).trees WHERE deleted_at IS NOT NULL) AS present"
            )
            defer { statement.finalize() }
            let present = try statement.fetchOne { try $0.bool("present") } ?? false
            return (schema, present, readSeedMeta(connection: connection))
        }

        return CypressStore(
            queue: queue,
            seed: schema,
            seedHasSoftDeletedTrees: hasSoftDeletes,
            seedMeta: seedMeta,
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
        let (schema, hasSoftDeletes, seedMeta) = try await queue.withConnection {
            connection -> (SeedSchema?, Bool, [String: String]) in
            try SchemaMigrator.migrate(migrations, on: connection)
            guard let seedURL else { return (nil, false, [:]) }
            let schema = try SeedDatabase.attach(seedURL, to: connection)
            let statement = try connection.prepare(
                "SELECT EXISTS(SELECT 1 FROM \(SeedDatabase.schemaName).trees WHERE deleted_at IS NOT NULL) AS present"
            )
            defer { statement.finalize() }
            let present = try statement.fetchOne { try $0.bool("present") } ?? false
            return (schema, present, readSeedMeta(connection: connection))
        }
        return CypressStore(
            queue: queue,
            seed: schema,
            seedHasSoftDeletedTrees: hasSoftDeletes,
            seedMeta: seedMeta,
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

    /// Removes a key entirely, rather than writing an empty string over it (ERRATA **E131**).
    ///
    /// The distinction is the whole reason this exists. `appState(_:)` returns `String?`, and every
    /// caller reads absence as "no answer" — no account, no role, no recorded consent. A cleared key
    /// written as `""` is present and parses to nothing, so a `UUID(uuidString:)` or a
    /// `UserRole(rawValue:)` of it is nil by accident rather than by record, and the next person to
    /// read the table cannot tell a setting somebody turned off from one nobody ever set.
    /// `AccountDeletion` already deletes rows for this reason; sign-out needs the same verb.
    public func clearAppState(_ key: AppStateKey) async throws {
        try await queue.write { connection in
            let statement = try connection.cachedStatement("DELETE FROM app_state WHERE key = :key")
            _ = try statement.bind(key.rawValue, forName: ":key")
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

    /// The account this device was signed in as before somebody signed out (ERRATA **E131**).
    ///
    /// **Why signing out has to remember anything at all.** A local account has no credential: there
    /// is no server, no magic link and nothing to prove you are the same person on the way back in,
    /// so `accountLink` mints a fresh `UUID` when it finds no account. Sign-out that forgot the id
    /// would therefore be irreversible in the one way that matters — every reminder, favourite and
    /// photo vote written under the old id stays in the tables, readable by no query
    /// (`privateReminders` asks for the *current* user or this device) and removable by no deletion,
    /// because `deleteAccount` can only delete the account it is signed in as. That is precisely the
    /// "litter that happens to be unreachable" RULINGS R3 refuses to create, arrived at by a
    /// different road.
    ///
    /// So the id is kept here and `accountLink` resumes it. Signing out stops the app acting as you;
    /// it does not silently strand your records. `deleteAccount` clears this key along with the rest,
    /// so a deleted account is never resumable.
    case signedOutUserID = "signed_out_user_id"

    /// Which of screen 15's three routes was tapped, and the license consent that travelled with it
    /// (ERRATA **E131**). `AccountAskProvider`'s raw value and `User.licenseVersion`'s shape
    /// respectively; see `AccountLinkRecord` for why absence is meaningful in both.
    case accountProvider = "account_provider"
    case accountLicenseVersion = "account_license_version"
}
