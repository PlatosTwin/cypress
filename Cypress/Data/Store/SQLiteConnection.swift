import Foundation
import SQLite3

/// A single sqlite3 database handle.
///
/// Not thread-safe by itself and deliberately so: exactly one `DatabaseQueue` actor owns each
/// connection and serializes access to it (ARCHITECTURE §3, "`Data` types are actors or are called
/// from a background context explicitly"). Sharing one of these across threads is the bug this
/// design is meant to make impossible to write by accident.
public final class SQLiteConnection {
    let handle: OpaquePointer
    private var statementCache: [String: SQLiteStatement] = [:]
    private var savepointDepth = 0

    /// Where the handle points. `":memory:"` for the test connections.
    public let path: String

    // MARK: - Lifecycle

    /// Opens a database.
    ///
    /// `SQLITE_OPEN_URI` is always set so callers can pass `file:…?mode=ro&immutable=1`, which is
    /// how the read-only bundled seed is attached (see `SeedDatabase`). `SQLITE_OPEN_NOMUTEX`
    /// selects multi-thread mode: no internal mutex, because the actor above is already the mutex
    /// and paying for a second one on every step of a 195,309-row scan is measurable.
    public init(
        path: String,
        flags: Int32 = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_URI | SQLITE_OPEN_NOMUTEX
    ) throws {
        var handle: OpaquePointer?
        let code = sqlite3_open_v2(path, &handle, flags, nil)
        guard code == SQLITE_OK, let opened = handle else {
            // sqlite3_open_v2 may hand back a usable handle even on failure; it must still be
            // closed, and its errmsg is the informative one.
            let error = SQLiteError.fromConnection(handle, code: code)
            if let handle { sqlite3_close_v2(handle) }
            throw error
        }
        self.handle = opened
        self.path = path

        // Extended result codes make SQLITE_CONSTRAINT_UNIQUE distinguishable from every other
        // constraint failure, which the outbox's idempotent insert depends on.
        sqlite3_extended_result_codes(opened, 1)
        // A five-second busy timeout rather than an immediate SQLITE_BUSY: the only contention in
        // this app is the outbox drain against a foreground read, and both are short.
        sqlite3_busy_timeout(opened, 5_000)
    }

    deinit {
        // Drop cached statements first so close_v2 does not have to zombie the connection.
        statementCache.values.forEach { $0.finalize() }
        statementCache.removeAll()
        sqlite3_close_v2(handle)
    }

    // MARK: - Pragmas and configuration

    /// Applies the pragmas every writable Cypress database uses.
    ///
    /// - WAL: a reader (the map) and the writer (the outbox drain) never block each other.
    /// - `foreign_keys = ON`: SQLite defaults this **off** per connection, so the FK declarations in
    ///   the migrations are inert without it.
    /// - `synchronous = NORMAL`: the documented safe pairing with WAL on a device whose power loss
    ///   story is the OS, not the app.
    public func configureForWriting() throws {
        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA foreign_keys = ON")
        try execute("PRAGMA synchronous = NORMAL")
        try execute("PRAGMA temp_store = MEMORY")
    }

    /// `PRAGMA user_version`, the migration counter (ARCHITECTURE §2 / BUILD-PLAN §4).
    public var userVersion: Int32 {
        get throws {
            let statement = try prepare("PRAGMA user_version")
            defer { statement.finalize() }
            guard try statement.step() else { return 0 }
            return Int32(try statement.row.int("user_version"))
        }
    }

    /// `PRAGMA user_version = n`. Not parameterizable in SQLite, hence the interpolation; the value
    /// is an `Int32` from the migration list, never user input.
    public func setUserVersion(_ version: Int32) throws {
        try execute("PRAGMA user_version = \(version)")
    }

    // MARK: - Statements

    /// Prepares a fresh statement. The caller owns it and should `finalize()` or let it deallocate.
    public func prepare(_ sql: String) throws -> SQLiteStatement {
        var handle: OpaquePointer?
        let code = sqlite3_prepare_v2(self.handle, sql, -1, &handle, nil)
        guard code == SQLITE_OK, let prepared = handle else {
            let error = SQLiteError.fromConnection(self.handle, code: code, sql: sql)
            if let handle { sqlite3_finalize(handle) }
            throw error
        }
        return SQLiteStatement(connection: self, handle: prepared, sql: sql)
    }

    /// Prepares once and reuses. The returned statement is reset and its bindings cleared.
    ///
    /// The map re-runs the same viewport query on every pan; re-preparing it each time is pure
    /// parser and planner overhead against a 195,309-row table.
    public func cachedStatement(_ sql: String) throws -> SQLiteStatement {
        if let cached = statementCache[sql] {
            return try cached.reset()
        }
        let statement = try prepare(sql)
        statementCache[sql] = statement
        return statement
    }

    /// Drops the statement cache. Required before `DETACH`, because a cached statement referencing
    /// an attached schema keeps that schema locked.
    public func clearStatementCache() {
        statementCache.values.forEach { $0.finalize() }
        statementCache.removeAll()
    }

    /// Runs one or more statements that return no rows.
    ///
    /// Uses `sqlite3_exec` so a migration can be written as a single multi-statement string;
    /// `sqlite3_prepare_v2` would only compile the first statement and silently ignore the rest,
    /// which is a very quiet way to ship half a schema.
    public func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let code = sqlite3_exec(handle, sql, nil, nil, &errorMessage)
        if let errorMessage { sqlite3_free(errorMessage) }
        guard code == SQLITE_OK else {
            throw SQLiteError.fromConnection(handle, code: code, sql: sql)
        }
    }

    /// Rows changed by the most recent statement.
    public var changes: Int { Int(sqlite3_changes(handle)) }

    /// `sqlite3_last_insert_rowid`.
    public var lastInsertRowID: Int64 { sqlite3_last_insert_rowid(handle) }

    // MARK: - Transactions

    /// Runs `body` inside a transaction, committing on return and rolling back on any throw.
    ///
    /// Nesting is handled with `SAVEPOINT`, so a DAO that wants atomicity does not have to know
    /// whether its caller already opened a transaction. `BEGIN IMMEDIATE` at the outermost level
    /// takes the write lock up front rather than discovering the conflict at COMMIT time.
    public func transaction<T>(_ body: () throws -> T) throws -> T {
        let name = "cypress_sp_\(savepointDepth)"
        if savepointDepth == 0 {
            try execute("BEGIN IMMEDIATE TRANSACTION")
        } else {
            try execute("SAVEPOINT \(name)")
        }
        savepointDepth += 1

        do {
            let result = try body()
            savepointDepth -= 1
            if savepointDepth == 0 {
                try execute("COMMIT TRANSACTION")
            } else {
                try execute("RELEASE SAVEPOINT \(name)")
            }
            return result
        } catch {
            savepointDepth -= 1
            if savepointDepth == 0 {
                // A failed ROLLBACK leaves the connection in an unusable state, but the original
                // error is the one the caller needs; swallowing the rollback failure here would
                // hide it behind a less informative one.
                try? execute("ROLLBACK TRANSACTION")
            } else {
                try? execute("ROLLBACK TO SAVEPOINT \(name)")
                try? execute("RELEASE SAVEPOINT \(name)")
            }
            throw error
        }
    }

    // MARK: - Attaching

    /// `ATTACH DATABASE`. `uri` is passed as a bound parameter, never interpolated.
    public func attach(uri: String, as schemaName: String) throws {
        let statement = try prepare("ATTACH DATABASE :uri AS \(Self.validatedSchemaName(schemaName))")
        defer { statement.finalize() }
        _ = try statement.bind(uri, forName: ":uri")
        try statement.run()
    }

    public func detach(_ schemaName: String) throws {
        clearStatementCache()
        try execute("DETACH DATABASE \(Self.validatedSchemaName(schemaName))")
    }

    /// The schema names currently attached, e.g. `["main", "seed", "temp"]`.
    public func attachedSchemas() throws -> [String] {
        let statement = try prepare("PRAGMA database_list")
        defer { statement.finalize() }
        return try statement.fetchAll { try $0.string("name") }
    }

    /// A schema name is a SQL identifier and cannot be bound, so it is validated instead of trusted.
    /// Only the two names this app uses can ever reach here, but the check keeps that true.
    private static func validatedSchemaName(_ name: String) -> String {
        precondition(
            name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" } && !name.isEmpty,
            "schema name '\(name)' is not a bare identifier"
        )
        return name
    }

    // MARK: - Introspection

    /// Column names of a table, in declaration order. Empty when the table does not exist.
    public func columnNames(ofTable table: String, in schema: String = "main") throws -> [String] {
        let statement = try prepare("SELECT name FROM pragma_table_info(:table, :schema)")
        defer { statement.finalize() }
        _ = try statement.bind([":table": table, ":schema": schema])
        return try statement.fetchAll { try $0.string("name") }
    }

    /// Whether a table (or view, or virtual table) exists in a schema.
    public func tableExists(_ table: String, in schema: String = "main") throws -> Bool {
        let statement = try prepare(
            "SELECT 1 FROM \(Self.validatedSchemaName(schema)).sqlite_master WHERE type IN ('table','view') AND name = :name"
        )
        defer { statement.finalize() }
        _ = try statement.bind(table, forName: ":name")
        return try statement.fetchOne { _ in true } ?? false
    }

    /// `EXPLAIN QUERY PLAN`, one line per step, as the planner prints it.
    ///
    /// Used by the seed contract test to pin that the viewport, nearest-N, profile, and species
    /// queries still resolve through their indexes: a plan that degrades to `SCAN trees` is a
    /// 195,309-row table scan on the map's critical path and must fail CI, not the field.
    public func queryPlan(for sql: String) throws -> [String] {
        let statement = try prepare("EXPLAIN QUERY PLAN \(sql)")
        defer { statement.finalize() }
        return try statement.fetchAll { try $0.string("detail") }
    }
}
