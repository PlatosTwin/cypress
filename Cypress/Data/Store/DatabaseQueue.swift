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
        #if DEBUG
        census?.recordRead()
        #endif
        return try body(connection)
    }

    /// Reads several statements that must agree with each other, inside one deferred transaction.
    public func readConsistently<T>(_ body: (SQLiteConnection) throws -> T) throws -> T {
        #if DEBUG
        census?.recordRead()
        #endif
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
        #if DEBUG
        census?.recordRead()
        #endif
        return try body(connection)
    }

    #if DEBUG
    private var census: StatementCensus?

    /// Point this queue and its connection at a census, or at nil to stop.
    ///
    /// **Per-queue, deliberately, and not a global.** Swift Testing runs tests in parallel, and a
    /// process-wide recorder would have every suite writing into one bucket — a gate that reads
    /// like a measurement and is a race. Each test builds its own `CypressStore`, so a census
    /// installed here can only ever see the statements that test caused.
    ///
    /// `DEBUG` only: in a shipping build the property, both call sites and `SQLiteConnection`'s
    /// own do not exist. See `StatementCensus` for what the counts mean and what they cannot see.
    public func installCensus(_ census: StatementCensus?) {
        self.census = census
        connection.census = census
    }
    #endif
}

#if DEBUG
/// **What a database operation actually did**, in round-trips and in statement texts.
///
/// This exists because two of this pull request's central claims had no instrument. PR #143's
/// review demonstrated both by experiment on a fully green suite:
///
/// 1. appending `" -- drift"` to the statement `ContributionStore.journal` runs left
///    `JournalQueryPlanTests` explaining a string the app no longer executes, and nothing went
///    red — the gate referenced a *property*, which does not make that property the thing the app
///    runs;
/// 2. putting the per-tree N+1 loop back into `LocalAPI.journal()` — the defect the whole change
///    exists to remove — left the suite green, because every other gate compares *answers*, and
///    the loop and the batch answer identically by construction.
///
/// Both are the same missing question: not "what does this statement say" but "which statements
/// ran, and how many times". A census answers it from the inside — `SQLiteConnection` records
/// every prepare request, `DatabaseQueue` records every hop onto its own actor — so a gate written
/// against it is bound to executed text rather than to a string a test happens to name.
///
/// **What it cannot see**, stated so nothing is claimed for it that it does not do:
/// `SQLiteConnection.execute`, which runs through `sqlite3_exec` and never prepares a statement.
/// Migrations and `ATTACH` go that way; no read path in the app does.
public final class StatementCensus: @unchecked Sendable {

    private let lock = NSLock()
    private var preparedSQL: [String] = []
    private var reads = 0

    public init() {}

    /// Every statement text prepared while this census was installed, in order, **with repeats** —
    /// the repeats are the entire point, since an N+1 is one statement run many times.
    public var statements: [String] {
        lock.lock(); defer { lock.unlock() }
        return preparedSQL
    }

    /// How many times a caller hopped onto the queue: `read`, `readConsistently` or
    /// `withConnection`. Writes are not counted — a read path that writes is a different defect
    /// from the one this measures, and counting both would blur the number.
    public var readCount: Int {
        lock.lock(); defer { lock.unlock() }
        return reads
    }

    public func reset() {
        lock.lock(); defer { lock.unlock() }
        preparedSQL.removeAll()
        reads = 0
    }

    func record(_ sql: String) {
        lock.lock(); defer { lock.unlock() }
        preparedSQL.append(sql)
    }

    func recordRead() {
        lock.lock(); defer { lock.unlock() }
        reads += 1
    }
}
#endif
