import Foundation
import SQLite3

/// Extended result codes the Swift `SQLite3` module does not re-export.
///
/// The C header builds them with `#define SQLITE_CONSTRAINT_UNIQUE (SQLITE_CONSTRAINT | (8<<8))`,
/// which the importer drops. They are spelled out the same way here rather than as bare literals so
/// the derivation stays checkable against `sqlite3.h`.
enum SQLiteExtendedCode {
    static let constraintUnique = SQLITE_CONSTRAINT | (8 << 8)      // 2067
    static let constraintPrimaryKey = SQLITE_CONSTRAINT | (6 << 8)  // 1555
    static let constraintTrigger = SQLITE_CONSTRAINT | (7 << 8)     // 1811
    static let constraintCheck = SQLITE_CONSTRAINT | (1 << 8)       // 275
}

/// A failure from the sqlite3 C API, carrying both the primary and the extended result code.
///
/// Every call into libsqlite3 in this layer is checked against its documented success codes rather
/// than against "the ones we usually see": `SQLITE_MISUSE`, `SQLITE_CORRUPT`, and the extended
/// `SQLITE_IOERR_*` family all arrive through the same door and all mean the caller must stop.
public struct SQLiteError: Error, CustomStringConvertible, Equatable {
    /// Whatever `sqlite3_errcode` returned. Extended result codes are enabled on every connection
    /// here, so this is usually an *extended* code despite the name. Classify on `primaryCode`.
    public let code: Int32
    /// Extended result code, e.g. `SQLITE_CONSTRAINT_UNIQUE` (2067). Equal to `code` when the
    /// connection has no extended code to offer.
    public let extendedCode: Int32
    /// `sqlite3_errmsg`, or a synthesized description when no connection was available.
    public let message: String
    /// The statement being prepared or run, when the failure has one. Truncated for log hygiene.
    public let sql: String?

    public init(code: Int32, extendedCode: Int32, message: String, sql: String? = nil) {
        self.code = code
        self.extendedCode = extendedCode
        self.message = message
        self.sql = sql
    }

    /// Builds an error from a live connection so `sqlite3_errmsg` and the extended code are read
    /// before any subsequent call can overwrite them.
    static func fromConnection(_ handle: OpaquePointer?, code: Int32, sql: String? = nil) -> SQLiteError {
        let message: String
        if let handle, let raw = sqlite3_errmsg(handle) {
            message = String(cString: raw)
        } else if let raw = sqlite3_errstr(code) {
            message = String(cString: raw)
        } else {
            message = "sqlite3 error \(code)"
        }
        let extended = handle.map { sqlite3_extended_errcode($0) } ?? code
        return SQLiteError(code: code, extendedCode: extended, message: message, sql: sql?.truncatedForLog())
    }

    /// For failures that happen before a connection exists (`sqlite3_open_v2` returning without a
    /// handle, a path that will not encode).
    static func detached(code: Int32, message: String, sql: String? = nil) -> SQLiteError {
        SQLiteError(code: code, extendedCode: code, message: message, sql: sql?.truncatedForLog())
    }

    public var description: String {
        var text = "SQLiteError(\(code)/\(extendedCode)): \(message)"
        if let sql { text += " — while running: \(sql)" }
        return text
    }

    // MARK: - Classification

    /// The primary result code, whatever `code` happens to hold.
    ///
    /// `code` comes from `sqlite3_errcode`, and this layer enables extended result codes on every
    /// connection — so `sqlite3_errcode` returns *extended* codes too, and `code` is 1555
    /// (`SQLITE_CONSTRAINT_PRIMARYKEY`) where the doc comment above promises 19
    /// (`SQLITE_CONSTRAINT`). Comparing `code` to a primary constant therefore never matched.
    ///
    /// Masking is sqlite's own documented relationship between the two: the low byte of an
    /// extended code is its primary code, and a code with no extended form is unchanged by the
    /// mask. Classify on this, never on `code`.
    public var primaryCode: Int32 { code & 0xFF }

    /// A uniqueness violation. The outbox relies on this to make `clientUUID` insertion idempotent
    /// rather than racy (BUILD-PLAN §4).
    public var isUniqueConstraintViolation: Bool {
        extendedCode == SQLiteExtendedCode.constraintUnique
            || extendedCode == SQLiteExtendedCode.constraintPrimaryKey
    }

    /// Any CHECK / NOT NULL / FK / trigger-RAISE violation. These are schema-invariant failures
    /// (BUILD-PLAN §13) and are never retryable — the same row will fail the same way forever.
    public var isConstraintViolation: Bool { primaryCode == SQLITE_CONSTRAINT }

    /// Transient contention. Retryable.
    public var isBusy: Bool { primaryCode == SQLITE_BUSY || primaryCode == SQLITE_LOCKED }

    /// Mapping into the BUILD-PLAN §6 taxonomy so a storage failure reaching the API boundary
    /// arrives as one of the eight codes the UI knows how to render (ARCHITECTURE §4).
    public var asAPIError: APIError {
        if isConstraintViolation { return .validationFailed }
        return .serverError
    }
}

private extension String {
    func truncatedForLog(limit: Int = 400) -> String {
        count <= limit ? self : String(prefix(limit)) + "…"
    }
}
