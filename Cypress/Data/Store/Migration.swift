import Foundation

/// One ordered, checked-in schema step.
///
/// Migrations are identified by an integer `version` recorded in `PRAGMA user_version`. They are
/// written to be idempotent (`CREATE TABLE IF NOT EXISTS`, `CREATE INDEX IF NOT EXISTS`) so that a
/// run interrupted between the DDL and the version bump — power loss, a crash, a test harness
/// killed mid-run — replays cleanly instead of failing on "table already exists".
public struct Migration {
    public let version: Int32
    public let name: String
    public let migrate: (SQLiteConnection) throws -> Void

    public init(version: Int32, name: String, sql: String) {
        self.version = version
        self.name = name
        self.migrate = { connection in try connection.execute(sql) }
    }

    public init(version: Int32, name: String, migrate: @escaping (SQLiteConnection) throws -> Void) {
        self.version = version
        self.name = name
        self.migrate = migrate
    }
}

public enum MigrationError: Error, CustomStringConvertible {
    case duplicateVersion(Int32)
    case nonPositiveVersion(Int32)
    /// The database is newer than this build of the app knows about. Refusing is the only safe
    /// answer: running an old app's queries against a newer schema silently returns wrong rows.
    case databaseIsAhead(databaseVersion: Int32, highestKnown: Int32)

    public var description: String {
        switch self {
        case let .duplicateVersion(version):
            return "two migrations claim version \(version)"
        case let .nonPositiveVersion(version):
            return "migration version \(version) must be >= 1; 0 means 'unmigrated'"
        case let .databaseIsAhead(databaseVersion, highestKnown):
            return "database is at user_version \(databaseVersion) but this build knows only up to \(highestKnown)"
        }
    }
}

/// Runs the ordered migration list against a connection using `PRAGMA user_version`.
public enum SchemaMigrator {
    /// Applies every migration whose version exceeds the database's `user_version`, in order.
    ///
    /// Each migration and its version bump commit together, so `user_version` can never claim a
    /// step that did not land. Returns the versions actually applied.
    @discardableResult
    public static func migrate(_ migrations: [Migration], on connection: SQLiteConnection) throws -> [Int32] {
        let ordered = migrations.sorted { $0.version < $1.version }

        var seen = Set<Int32>()
        for migration in ordered {
            guard migration.version >= 1 else { throw MigrationError.nonPositiveVersion(migration.version) }
            guard seen.insert(migration.version).inserted else {
                throw MigrationError.duplicateVersion(migration.version)
            }
        }

        let current = try connection.userVersion
        if let highest = ordered.last?.version, current > highest {
            throw MigrationError.databaseIsAhead(databaseVersion: current, highestKnown: highest)
        }

        var applied: [Int32] = []
        for migration in ordered where migration.version > current {
            try connection.transaction {
                try migration.migrate(connection)
                try connection.setUserVersion(migration.version)
            }
            applied.append(migration.version)
        }
        return applied
    }
}
