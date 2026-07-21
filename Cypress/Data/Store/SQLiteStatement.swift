import Foundation
import SQLite3

/// A prepared statement.
///
/// Lifetime rules this type enforces so callers cannot get them wrong:
/// - the statement is finalized exactly once, in `deinit` or in an explicit `finalize()`;
/// - the owning `SQLiteConnection` is retained, so a statement can never outlive its database
///   handle (which is `SQLITE_MISUSE`, and on some builds a crash rather than an error code);
/// - `reset()` also clears bindings, so a cached statement never carries a stale parameter into its
///   next execution.
public final class SQLiteStatement {
    private let connection: SQLiteConnection
    private let handle: OpaquePointer
    private let indexByName: [String: Int32]
    private var isFinalized = false

    /// The SQL this statement was prepared from, for error messages.
    public let sql: String

    init(connection: SQLiteConnection, handle: OpaquePointer, sql: String) {
        self.connection = connection
        self.handle = handle
        self.sql = sql

        var names: [String: Int32] = [:]
        let columnCount = sqlite3_column_count(handle)
        names.reserveCapacity(Int(columnCount))
        for index in 0..<columnCount {
            if let raw = sqlite3_column_name(handle, index) {
                names[String(cString: raw)] = index
            }
        }
        self.indexByName = names
    }

    deinit {
        if !isFinalized { sqlite3_finalize(handle) }
    }

    /// Finalizes early. Safe to call more than once.
    public func finalize() {
        guard !isFinalized else { return }
        isFinalized = true
        sqlite3_finalize(handle)
    }

    // MARK: - Binding

    /// Binds by 1-based positional index.
    @discardableResult
    public func bind(_ value: SQLiteBindable?, at index: Int32) throws -> SQLiteStatement {
        let code: Int32
        if let value {
            code = value.bind(to: handle, at: index)
        } else {
            code = sqlite3_bind_null(handle, index)
        }
        guard code == SQLITE_OK else {
            throw SQLiteError.fromConnection(connection.handle, code: code, sql: sql)
        }
        return self
    }

    /// Binds by `:name`. An unknown name is a programming error and throws rather than silently
    /// binding nothing, which would leave the parameter NULL and quietly change the query's meaning.
    @discardableResult
    public func bind(_ value: SQLiteBindable?, forName name: String) throws -> SQLiteStatement {
        let index = sqlite3_bind_parameter_index(handle, name)
        guard index > 0 else {
            throw SQLiteError.detached(
                code: SQLITE_MISUSE,
                message: "no bound parameter named '\(name)'",
                sql: sql
            )
        }
        return try bind(value, at: index)
    }

    @discardableResult
    public func bind(_ parameters: [String: SQLiteBindable?]) throws -> SQLiteStatement {
        for (name, value) in parameters {
            _ = try bind(value, forName: name)
        }
        return self
    }

    @discardableResult
    public func bind(_ parameters: [SQLiteBindable?]) throws -> SQLiteStatement {
        for (offset, value) in parameters.enumerated() {
            _ = try bind(value, at: Int32(offset + 1))
        }
        return self
    }

    // MARK: - Execution

    /// Advances one row. Returns `true` for `SQLITE_ROW`, `false` for `SQLITE_DONE`, and throws on
    /// anything else — including `SQLITE_BUSY`, which callers must see rather than treat as "no
    /// more rows".
    @discardableResult
    public func step() throws -> Bool {
        let code = sqlite3_step(handle)
        switch code {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        default: throw SQLiteError.fromConnection(connection.handle, code: code, sql: sql)
        }
    }

    /// Resets for reuse and clears every binding.
    @discardableResult
    public func reset() throws -> SQLiteStatement {
        // sqlite3_reset returns the error from the *previous* execution; that error has already
        // been surfaced by step(), so only a genuine reset failure is interesting here. Clearing
        // bindings cannot fail.
        _ = sqlite3_reset(handle)
        sqlite3_clear_bindings(handle)
        return self
    }

    /// The current row. Only valid until the next `step()`.
    public var row: SQLiteRow { SQLiteRow(statement: handle, indexByName: indexByName) }

    /// Runs a statement that returns no rows.
    public func run() throws {
        while try step() {}
    }

    /// Maps every row through `decode`. The statement is reset afterwards so it can be cached.
    public func fetchAll<T>(_ decode: (SQLiteRow) throws -> T) throws -> [T] {
        var results: [T] = []
        defer { _ = try? reset() }
        while try step() {
            results.append(try decode(row))
        }
        return results
    }

    /// Maps the first row, if any.
    public func fetchOne<T>(_ decode: (SQLiteRow) throws -> T) throws -> T? {
        defer { _ = try? reset() }
        guard try step() else { return nil }
        return try decode(row)
    }
}
