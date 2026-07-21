import Foundation

/// Serializes every access to one `SQLiteConnection`.
///
/// ARCHITECTURE §3: "All I/O is `async`. Anything touching the database or the outbox is `await`ed.
/// UI types are `@MainActor`; `Data` types are actors." This is the actor. The connection handle is
/// private to it and never escapes, so there is no supported way for two tasks to step the same
/// statement concurrently.
public actor DatabaseQueue {
    private let connection: SQLiteConnection

    public init(connection: SQLiteConnection) {
        self.connection = connection
    }

    /// Opens a read-write database at `url`, creating it and its parent directory if needed, and
    /// applies the standard pragmas.
    public init(url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let connection = try SQLiteConnection(path: url.path)
        try connection.configureForWriting()
        self.connection = connection
    }

    /// An in-memory database, for tests and previews.
    public static func inMemory() throws -> DatabaseQueue {
        let connection = try SQLiteConnection(path: ":memory:")
        try connection.execute("PRAGMA foreign_keys = ON")
        return DatabaseQueue(connection: connection)
    }

    /// Reads. No transaction is opened: a single statement in WAL mode already sees a consistent
    /// snapshot, and wrapping every viewport query in `BEGIN`/`COMMIT` is measurable overhead on a
    /// query that runs on every map pan.
    public func read<T>(_ body: (SQLiteConnection) throws -> T) throws -> T {
        try body(connection)
    }

    /// Reads several statements that must agree with each other, inside one deferred transaction.
    public func readConsistently<T>(_ body: (SQLiteConnection) throws -> T) throws -> T {
        try connection.execute("BEGIN DEFERRED TRANSACTION")
        do {
            let result = try body(connection)
            try connection.execute("COMMIT TRANSACTION")
            return result
        } catch {
            try? connection.execute("ROLLBACK TRANSACTION")
            throw error
        }
    }

    /// Writes, inside a transaction that rolls back on any throw.
    @discardableResult
    public func write<T>(_ body: (SQLiteConnection) throws -> T) throws -> T {
        try connection.transaction { try body(connection) }
    }

    /// Escape hatch for callers that manage their own transaction boundaries — the migration
    /// runner, and `ATTACH`, which cannot run inside a transaction.
    public func withConnection<T>(_ body: (SQLiteConnection) throws -> T) throws -> T {
        try body(connection)
    }
}
