import Foundation
import SQLite3

/// `SQLITE_TRANSIENT`, which the C header defines as `((sqlite3_destructor_type)-1)` and which the
/// Swift importer therefore cannot see.
///
/// **This constant is load-bearing.** `sqlite3_bind_text`/`_blob` default to `SQLITE_STATIC`, which
/// promises sqlite that the bytes outlive the statement. A Swift `String` passed through
/// `withCString` does *not*: the buffer dies at the end of the closure, and the resulting
/// use-after-free reads as garbage rows or a crash minutes later in an unrelated query. Every text
/// and blob bind in this file passes `SQLITE_TRANSIENT` so sqlite copies immediately.
let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

// MARK: - Timestamps

/// ISO-8601 UTC strings, the storage format the seed contract uses for every timestamp
/// (`Fixtures/seed/schema.sql` header). The app's own tables use the same format so that a value
/// read from `seed.trees.created_at` and one read from `main.visits.created_at` sort together.
public enum SQLiteTimestamp {
    /// Writes `2026-07-21T18:51:49.123Z`. Fractional seconds are kept because two contributions in
    /// the same second are ordinary in the field, and the outbox's FIFO tie-break should not depend
    /// on them being distinguishable.
    public static func string(from date: Date) -> String {
        writer.string(from: date)
    }

    /// Reads both the fractional and non-fractional spellings, and both `Z` and `+00:00` zones —
    /// the seed generator emits `+00:00` without fractional seconds, the app emits `Z` with.
    public static func date(from string: String) -> Date? {
        if let date = fractionalReader.date(from: string) { return date }
        return plainReader.date(from: string)
    }

    private static let writer: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static let fractionalReader: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plainReader: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

// MARK: - Binding

/// A Swift value that can be bound to a `?`/`:name` parameter.
///
/// Conformances are deliberately explicit rather than derived from `Codable`: the set of things
/// this layer stores is small and fixed, and an accidental `Encodable` conformance turning a struct
/// into a JSON blob column is exactly the kind of silent schema drift the seed contract test exists
/// to catch.
public protocol SQLiteBindable {
    func bind(to statement: OpaquePointer, at index: Int32) -> Int32
}

extension Int: SQLiteBindable {
    public func bind(to statement: OpaquePointer, at index: Int32) -> Int32 {
        sqlite3_bind_int64(statement, index, Int64(self))
    }
}

extension Int32: SQLiteBindable {
    public func bind(to statement: OpaquePointer, at index: Int32) -> Int32 {
        sqlite3_bind_int(statement, index, self)
    }
}

extension Int64: SQLiteBindable {
    public func bind(to statement: OpaquePointer, at index: Int32) -> Int32 {
        sqlite3_bind_int64(statement, index, self)
    }
}

extension Double: SQLiteBindable {
    public func bind(to statement: OpaquePointer, at index: Int32) -> Int32 {
        sqlite3_bind_double(statement, index, self)
    }
}

extension Bool: SQLiteBindable {
    /// "Booleans are 0/1 INTEGERs" (seed contract header).
    public func bind(to statement: OpaquePointer, at index: Int32) -> Int32 {
        sqlite3_bind_int(statement, index, self ? 1 : 0)
    }
}

extension String: SQLiteBindable {
    public func bind(to statement: OpaquePointer, at index: Int32) -> Int32 {
        // -1 lets sqlite measure the NUL-terminated buffer; SQLITE_TRANSIENT makes it copy before
        // `self`'s storage goes away. See the note on SQLITE_TRANSIENT above.
        sqlite3_bind_text(statement, index, self, -1, SQLITE_TRANSIENT)
    }
}

extension Data: SQLiteBindable {
    public func bind(to statement: OpaquePointer, at index: Int32) -> Int32 {
        if isEmpty {
            return sqlite3_bind_zeroblob(statement, index, 0)
        }
        return withUnsafeBytes { buffer in
            sqlite3_bind_blob(statement, index, buffer.baseAddress, Int32(buffer.count), SQLITE_TRANSIENT)
        }
    }
}

extension UUID: SQLiteBindable {
    /// Stored as the uppercase canonical string `Foundation` produces, matching the seed's
    /// `trees.uuid` / `species.uuid` spelling after case-insensitive comparison. `LocalAPI`
    /// normalizes on read, so a lowercase seed value and an uppercase app value still join.
    public func bind(to statement: OpaquePointer, at index: Int32) -> Int32 {
        uuidString.bind(to: statement, at: index)
    }
}

extension Date: SQLiteBindable {
    public func bind(to statement: OpaquePointer, at index: Int32) -> Int32 {
        SQLiteTimestamp.string(from: self).bind(to: statement, at: index)
    }
}

extension URL: SQLiteBindable {
    public func bind(to statement: OpaquePointer, at index: Int32) -> Int32 {
        absoluteString.bind(to: statement, at: index)
    }
}

// MARK: - Row decoding

/// Why a row could not be turned into a domain value.
///
/// These are all schema-contract failures rather than user errors: a missing column means the seed
/// or a migration moved under the code, and the seed contract test (ARCHITECTURE §7) exists to fail
/// loudly on exactly this.
public enum SQLiteDecodingError: Error, CustomStringConvertible, Equatable {
    case missingColumn(String)
    case unexpectedNull(String)
    case malformedValue(column: String, expected: String, found: String)

    public var description: String {
        switch self {
        case let .missingColumn(name):
            return "no column named '\(name)' in the result set"
        case let .unexpectedNull(name):
            return "column '\(name)' was NULL where a value is required"
        case let .malformedValue(column, expected, found):
            return "column '\(column)' held '\(found)', which is not a \(expected)"
        }
    }
}

/// One row of a result set, addressed by column name.
///
/// A `SQLiteRow` borrows the statement it was produced from and is only valid until the next
/// `step()`. It is a struct with no stored copy of the row for that reason: copying 195,309 rows
/// into dictionaries to read three columns is the single easiest way to make the map feel slow.
public struct SQLiteRow {
    private let statement: OpaquePointer
    private let indexByName: [String: Int32]

    init(statement: OpaquePointer, indexByName: [String: Int32]) {
        self.statement = statement
        self.indexByName = indexByName
    }

    private func index(of column: String) throws -> Int32 {
        guard let index = indexByName[column] else { throw SQLiteDecodingError.missingColumn(column) }
        return index
    }

    public func isNull(_ column: String) throws -> Bool {
        sqlite3_column_type(statement, try index(of: column)) == SQLITE_NULL
    }

    // MARK: Optional readers

    public func intIfPresent(_ column: String) throws -> Int? {
        let i = try index(of: column)
        guard sqlite3_column_type(statement, i) != SQLITE_NULL else { return nil }
        return Int(sqlite3_column_int64(statement, i))
    }

    public func int64IfPresent(_ column: String) throws -> Int64? {
        let i = try index(of: column)
        guard sqlite3_column_type(statement, i) != SQLITE_NULL else { return nil }
        return sqlite3_column_int64(statement, i)
    }

    public func doubleIfPresent(_ column: String) throws -> Double? {
        let i = try index(of: column)
        guard sqlite3_column_type(statement, i) != SQLITE_NULL else { return nil }
        return sqlite3_column_double(statement, i)
    }

    public func stringIfPresent(_ column: String) throws -> String? {
        let i = try index(of: column)
        guard sqlite3_column_type(statement, i) != SQLITE_NULL,
              let raw = sqlite3_column_text(statement, i) else { return nil }
        return String(cString: raw)
    }

    public func boolIfPresent(_ column: String) throws -> Bool? {
        try intIfPresent(column).map { $0 != 0 }
    }

    public func dataIfPresent(_ column: String) throws -> Data? {
        let i = try index(of: column)
        guard sqlite3_column_type(statement, i) != SQLITE_NULL else { return nil }
        let byteCount = Int(sqlite3_column_bytes(statement, i))
        guard byteCount > 0, let pointer = sqlite3_column_blob(statement, i) else { return Data() }
        return Data(bytes: pointer, count: byteCount)
    }

    public func uuidIfPresent(_ column: String) throws -> UUID? {
        guard let text = try stringIfPresent(column) else { return nil }
        guard let uuid = UUID(uuidString: text) else {
            throw SQLiteDecodingError.malformedValue(column: column, expected: "UUID", found: text)
        }
        return uuid
    }

    public func dateIfPresent(_ column: String) throws -> Date? {
        guard let text = try stringIfPresent(column) else { return nil }
        guard let date = SQLiteTimestamp.date(from: text) else {
            throw SQLiteDecodingError.malformedValue(column: column, expected: "ISO-8601 timestamp", found: text)
        }
        return date
    }

    /// Decodes a `RawRepresentable` enum from its stored raw value. Unknown raw values throw rather
    /// than defaulting: enum raw values are "written out verbatim, because they are the stored
    /// values" (`Core/Models/CoreEntity.swift`), so an unrecognized one is a contract break.
    public func enumIfPresent<T: RawRepresentable>(_ column: String, _ type: T.Type) throws -> T?
    where T.RawValue == String {
        guard let text = try stringIfPresent(column) else { return nil }
        guard let value = T(rawValue: text) else {
            throw SQLiteDecodingError.malformedValue(column: column, expected: "\(T.self)", found: text)
        }
        return value
    }

    public func enumIfPresent<T: RawRepresentable>(_ column: String, _ type: T.Type) throws -> T?
    where T.RawValue == Int {
        guard let number = try intIfPresent(column) else { return nil }
        guard let value = T(rawValue: number) else {
            throw SQLiteDecodingError.malformedValue(column: column, expected: "\(T.self)", found: "\(number)")
        }
        return value
    }

    // MARK: Required readers

    public func int(_ column: String) throws -> Int {
        guard let value = try intIfPresent(column) else { throw SQLiteDecodingError.unexpectedNull(column) }
        return value
    }

    public func int64(_ column: String) throws -> Int64 {
        guard let value = try int64IfPresent(column) else { throw SQLiteDecodingError.unexpectedNull(column) }
        return value
    }

    public func double(_ column: String) throws -> Double {
        guard let value = try doubleIfPresent(column) else { throw SQLiteDecodingError.unexpectedNull(column) }
        return value
    }

    public func string(_ column: String) throws -> String {
        guard let value = try stringIfPresent(column) else { throw SQLiteDecodingError.unexpectedNull(column) }
        return value
    }

    public func bool(_ column: String) throws -> Bool {
        guard let value = try boolIfPresent(column) else { throw SQLiteDecodingError.unexpectedNull(column) }
        return value
    }

    public func data(_ column: String) throws -> Data {
        guard let value = try dataIfPresent(column) else { throw SQLiteDecodingError.unexpectedNull(column) }
        return value
    }

    public func uuid(_ column: String) throws -> UUID {
        guard let value = try uuidIfPresent(column) else { throw SQLiteDecodingError.unexpectedNull(column) }
        return value
    }

    public func date(_ column: String) throws -> Date {
        guard let value = try dateIfPresent(column) else { throw SQLiteDecodingError.unexpectedNull(column) }
        return value
    }

    public func value<T: RawRepresentable>(_ column: String, _ type: T.Type) throws -> T
    where T.RawValue == String {
        guard let value = try enumIfPresent(column, type) else { throw SQLiteDecodingError.unexpectedNull(column) }
        return value
    }
}
