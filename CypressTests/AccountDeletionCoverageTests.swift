import Foundation
import Testing
@testable import Cypress

/// Account deletion reaches every table that names a person or an installation — derived from the
/// live migrated schema, not from a list somebody remembered to update.
///
/// The failure this exists for has happened three times, and each time silently: twice the outbox
/// kind list in `OutboxStore.forgetAccount`, and once a whole table, `tree_data_disputes`
/// (`AppSchema` v22), which neither door could see until PR #165's review measured a dispute
/// surviving `.leaveRecords` that nobody could withdraw. A hand-kept list of table names cannot fail
/// loudly: a name it lacks matches nothing. `AccountDeletion.OwnedTable` is the classification;
/// this suite is what makes it complete.
///
/// Three layers, each closing a hole the one before leaves open:
///
/// 1. **The vocabulary.** Every column name in the writable schema is known either to name a person
///    or installation (`identitySpellings`) or not to (`ordinarySpellings`). Without this, the
///    derivation below could only look for spellings it already knows, and a column called
///    `reported_by` would be invisible to it — the dispute table's failure again, one level up.
/// 2. **The classification.** The tables and columns the schema says carry an identity are exactly
///    `OwnedTable.allCases` and their `identityColumns`, in both directions.
/// 3. **The behavior.** Under each door, a row owned by the deleting account ends as
///    `OwnedTable.fate(under:)` says, and a stranger's row in the same table is unchanged, column for
///    column. A classified table that no door actually reaches is caught here, not above.
///
/// Each layer is calibrated against a specimen whose answer is known (the "instrument" tests), so a
/// green cannot mean the instrument looked at nothing.
@Suite("Account deletion reaches every owner-bearing table")
struct AccountDeletionCoverageTests {

    typealias OwnedTable = AccountDeletion.OwnedTable

    // MARK: - The vocabulary

    /// Column names that name a person (an account) or an installation (D9's device handle).
    ///
    /// Every spelling the schema actually uses, read out of it: `user_id` and `device_id` on the
    /// contribution tables, `raised_by` (`review_flags`, `tree_data_disputes`), `given_by`
    /// (`tree_names`), `set_by` (`tree_status_overrides`), `taken_on_device` (`photos`, v16) and the
    /// `device` table's own `device_uuid`.
    static let identitySpellings: Set<String> = [
        "user_id", "device_id", "device_uuid", "raised_by", "given_by", "set_by", "taken_on_device"
    ]

    /// Every other column name in the writable schema. A new name has to be put here or above, and
    /// that is the point: it is the moment somebody decides whether the new column names a person.
    static let ordinarySpellings: Set<String> = [
        "actions", "address", "anonymized_at", "blur_applied", "captured_at", "category",
        "client_uuid", "confidence", "container_path", "created_at", "dbh_city_cm_max",
        "dbh_city_cm_min", "deleted_at", "dispute_id", "external_ref", "fail_count", "field",
        "foliage", "gps_accuracy_m", "height", "id", "key", "kind", "land_context", "last_error",
        "last_error_code", "lat", "local_applied", "local_path", "lon", "measurement_height_m",
        "method", "moderation_state", "name", "next_attempt_at", "note", "notes", "outbox_id", "path",
        "payload", "phenology_tags", "photo_id", "photo_paths", "photos_outstanding", "placement",
        "planted_year", "public_lat", "public_lon", "remote_sent", "sendable", "seq", "shot_type",
        "shown_at", "si_value", "site_lineage", "site_type", "source", "species_current",
        "species_uuid", "stale_at", "state", "status", "storage_key", "structure_flags",
        "superseded_by", "tree_id", "tree_source", "tree_uuid", "unit_entered", "updated_at", "value",
        "verification_state", "vote", "visit_id", "vitality", "width", "window_started_at",
        "withdrawn_at"
    ]

    /// Ordinary names that are shaped like identity ones, each with the reason it is not. A second
    /// check on the list above: a name that reads as "who" cannot be filed as ordinary by reflex.
    static let identityShapedButOrdinary: [String: String] = [
        "superseded_by": "names the species assertion that replaced this one, not a person"
    ]

    /// Whether a column name reads like it names somebody. Deliberately broad; the exceptions above
    /// are where a false positive is answered.
    static func looksLikeIdentity(_ name: String) -> Bool {
        let words: Set<String> = [
            "user", "users", "device", "owner", "author", "account", "person", "people", "member",
            "creator", "actor", "installation", "reporter", "editor", "moderator", "voter", "namer",
            "by", "who", "uid"
        ]
        return name.lowercased().split(separator: "_").contains { words.contains(String($0)) }
    }

    // MARK: - Reading the schema

    /// Table name to its column names, for every table in `main` that is not SQLite's own.
    struct Schema: Sendable {
        var columns: [String: [String]]

        var allColumnNames: Set<String> { Set(columns.values.joined()) }

        /// Tables with at least one identity-spelled column, and which.
        var identityColumns: [String: Set<String>] {
            columns.compactMapValues { names in
                let identity = Set(names).intersection(AccountDeletionCoverageTests.identitySpellings)
                return identity.isEmpty ? nil : identity
            }
        }
    }

    /// A fresh database, migrated by `AppSchema`, then — for the instrument tests only — altered by
    /// a specimen whose effect on the guard is known in advance.
    static func migratedSchema(specimen: String? = nil) async throws -> Schema {
        let queue = try DatabaseQueue.inMemory()
        return try await queue.withConnection { connection in
            try SchemaMigrator.migrate(AppSchema.migrations, on: connection)
            if let specimen { try connection.execute(specimen) }
            return try readSchema(connection)
        }
    }

    static func readSchema(_ connection: SQLiteConnection) throws -> Schema {
        let statement = try connection.prepare("""
            SELECT m.name AS table_name, p.name AS column_name
              FROM main.sqlite_master AS m, pragma_table_info(m.name) AS p
             WHERE m.type = 'table' AND m.name NOT LIKE 'sqlite\\_%' ESCAPE '\\'
             ORDER BY m.name, p.cid
            """)
        defer { statement.finalize() }
        var columns: [String: [String]] = [:]
        for pair in try statement.fetchAll({ (try $0.string("table_name"), try $0.string("column_name")) }) {
            columns[pair.0, default: []].append(pair.1)
        }
        return Schema(columns: columns)
    }

    // MARK: - The two checks, as values

    enum VocabularyFailure: Equatable, CustomStringConvertible {
        case unknownSpelling(table: String, column: String)
        case noLongerInSchema(String)
        case filedTwice(String)
        case identityShapedFiledAsOrdinary(String)

        var description: String {
            switch self {
            case let .unknownSpelling(table, column):
                return """
                    \(table).\(column) is a column name this guard has never seen. Decide whether it \
                    names a person or an installation. If it does, add it to `identitySpellings` — \
                    and its table will then need a case in `AccountDeletion.OwnedTable`. If it does \
                    not, add it to `ordinarySpellings`.
                    """
            case let .noLongerInSchema(name):
                return "'\(name)' is in the vocabulary but no column in the writable schema is called that; remove it"
            case let .filedTwice(name):
                return "'\(name)' is filed as both an identity spelling and an ordinary one"
            case let .identityShapedFiledAsOrdinary(name):
                return """
                    '\(name)' reads like it names a person or installation and is filed as ordinary. \
                    Either it is an identity spelling, or it belongs in `identityShapedButOrdinary` \
                    with the reason it is not
                    """
            }
        }
    }

    static func vocabularyFailures(_ schema: Schema) -> [VocabularyFailure] {
        var failures: [VocabularyFailure] = []
        let known = identitySpellings.union(ordinarySpellings)
        for table in schema.columns.keys.sorted() {
            for column in schema.columns[table, default: []] where !known.contains(column) {
                failures.append(.unknownSpelling(table: table, column: column))
            }
        }
        let present = schema.allColumnNames
        failures += known.subtracting(present).sorted().map(VocabularyFailure.noLongerInSchema)
        failures += identitySpellings.intersection(ordinarySpellings).sorted().map(VocabularyFailure.filedTwice)
        failures += ordinarySpellings
            .filter { looksLikeIdentity($0) && identityShapedButOrdinary[$0] == nil }
            .sorted()
            .map(VocabularyFailure.identityShapedFiledAsOrdinary)
        return failures
    }

    enum CoverageFailure: Equatable, CustomStringConvertible {
        case unclassified(table: String, columns: Set<String>)
        case classifiedButNotOwnerBearing(table: String)
        case columnsDisagree(table: String, schema: Set<String>, declared: Set<String>)

        var description: String {
            switch self {
            case let .unclassified(table, columns):
                return """
                    \(table) has \(columns.sorted()) and no case in `AccountDeletion.OwnedTable`, so \
                    nothing says what either deletion door does to it. This is the omission \
                    `tree_data_disputes` shipped with in AppSchema v22. Add a case, answer \
                    `fate(under:)`, and make both doors do what it says
                    """
            case let .classifiedButNotOwnerBearing(table):
                return "`OwnedTable` has a case for \(table), which the writable schema does not have as an owner-bearing table"
            case let .columnsDisagree(table, schema, declared):
                return """
                    \(table): the schema's identity columns are \(schema.sorted()) and \
                    `OwnedTable.identityColumns` declares \(declared.sorted()). A column that names a \
                    person was added or removed without the classification following it
                    """
            }
        }
    }

    static func coverageFailures(_ schema: Schema) -> [CoverageFailure] {
        let derived = schema.identityColumns
        let declared = Dictionary(uniqueKeysWithValues: OwnedTable.allCases.map { ($0.tableName, $0.identityColumns) })
        var failures: [CoverageFailure] = []
        for table in Set(derived.keys).union(declared.keys).sorted() {
            switch (derived[table], declared[table]) {
            case let (found?, nil):
                failures.append(.unclassified(table: table, columns: found))
            case (nil, _?):
                failures.append(.classifiedButNotOwnerBearing(table: table))
            case let (found?, said?) where found != said:
                failures.append(.columnsDisagree(table: table, schema: found, declared: said))
            default:
                break
            }
        }
        return failures
    }

    // MARK: - 1 and 2. The live schema

    @Test("every column name in the writable schema is known to name a person, or known not to")
    func everyColumnNameIsFiled() async throws {
        let schema = try await Self.migratedSchema()
        // Calibration: the reader read something, and read the column the dispute fix was about.
        #expect(schema.columns["tree_data_disputes"]?.contains("raised_by") == true, "\(schema.columns.keys.sorted())")
        #expect(schema.allColumnNames.count > Self.identitySpellings.count)

        let failures = Self.vocabularyFailures(schema)
        #expect(failures.isEmpty, "\(failures.map(\.description).joined(separator: "\n\n"))")
    }

    @Test("the owner-bearing tables in the schema are exactly the classified ones")
    func theOwnerBearingTablesAreClassified() async throws {
        let schema = try await Self.migratedSchema()
        let derived = schema.identityColumns
        // Calibration with known answers: a table from v1 and the table the dispute fix was about.
        #expect(derived["review_flags"] == ["raised_by"], "\(derived)")
        #expect(derived["tree_data_disputes"] == ["raised_by"], "\(derived)")
        #expect(derived["visits"] == ["user_id", "device_id"], "\(derived)")

        let failures = Self.coverageFailures(schema)
        #expect(failures.isEmpty, "\(failures.map(\.description).joined(separator: "\n\n"))")

        // Every declared account column is a real column of its table.
        for table in OwnedTable.allCases {
            #expect(
                schema.columns[table.tableName]?.contains(table.accountColumn) == true,
                "\(table.tableName) has no column \(table.accountColumn)"
            )
        }
    }

    // MARK: - The instrument, against specimens whose answer is known

    @Test("the instrument names an owner-bearing table nobody classified")
    func theInstrumentSeesAnUnclassifiedTable() async throws {
        let schema = try await Self.migratedSchema(
            specimen: "CREATE TABLE specimen_ledger (id TEXT PRIMARY KEY, user_id TEXT)"
        )
        #expect(Self.coverageFailures(schema) == [.unclassified(table: "specimen_ledger", columns: ["user_id"])])
        #expect(Self.vocabularyFailures(schema).isEmpty)
    }

    @Test("the instrument names a column spelling it has never seen")
    func theInstrumentSeesANewSpelling() async throws {
        let schema = try await Self.migratedSchema(
            specimen: "ALTER TABLE review_flags ADD COLUMN reported_by TEXT"
        )
        #expect(Self.vocabularyFailures(schema) == [.unknownSpelling(table: "review_flags", column: "reported_by")])
        // The derivation alone cannot see it — which is the whole reason the vocabulary exists.
        #expect(Self.coverageFailures(schema).isEmpty)
    }

    @Test("the instrument names an identity column added to a table it already classifies")
    func theInstrumentSeesANewIdentityColumn() async throws {
        let schema = try await Self.migratedSchema(
            specimen: "ALTER TABLE tree_data_disputes ADD COLUMN device_id TEXT"
        )
        #expect(Self.coverageFailures(schema) == [
            .columnsDisagree(table: "tree_data_disputes", schema: ["raised_by", "device_id"], declared: ["raised_by"])
        ])
    }

    @Test("the identity-shaped check catches a person-naming column filed as ordinary")
    func theShapeCheckCatchesAMisfiling() {
        #expect(Self.looksLikeIdentity("reported_by"))
        #expect(Self.looksLikeIdentity("owner_id"))
        #expect(Self.looksLikeIdentity("taken_on_device"))
        #expect(!Self.looksLikeIdentity("moderation_state"))
        #expect(!Self.looksLikeIdentity("tree_uuid"))
    }

    // MARK: - 3. What each door does

    private static let userID = UUID(uuidString: "0E000000-0000-4000-8000-00000000A0C1")!
    private static let strangerID = UUID(uuidString: "0E000000-0000-4000-8000-00000000A0C2")!
    private static let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-00000000A0C3")!
    private static let moment = Date(timeIntervalSince1970: 1_800_000_000)
    private static let stamp = "2026-09-01T12:00:00.000Z"

    /// The values of one row of `table`, owned by `account`. The exhaustive `switch` is the third
    /// place a new case has to be answered: a table cannot be classified without being seedable.
    private static func row(for table: OwnedTable, account: UUID) -> [String: String?] {
        let who = account.uuidString
        let device = deviceID.uuidString
        let tree = UUID().uuidString
        let fresh = { UUID().uuidString }
        let times: [String: String?] = ["created_at": stamp, "updated_at": stamp]
        let timed: ([String: String?]) -> [String: String?] = { $0.merging(times) { mine, _ in mine } }
        switch table {
        case .device:
            return timed(["id": fresh(), "device_uuid": fresh(), "user_id": who])
        case .visits:
            return timed(["id": fresh(), "tree_uuid": tree, "user_id": who, "device_id": device,
                    "client_uuid": fresh(), "captured_at": stamp])
        case .observations:
            return timed(["id": fresh(), "tree_uuid": tree, "user_id": who, "device_id": device,
                    "client_uuid": fresh(), "captured_at": stamp])
        case .measurements:
            return timed(["id": fresh(), "tree_uuid": tree, "user_id": who, "device_id": device,
                    "client_uuid": fresh(), "captured_at": stamp, "kind": "height", "value": "12",
                    "unit_entered": "m", "si_value": "12", "method": "tape"])
        case .careEvents:
            return timed(["id": fresh(), "tree_uuid": tree, "user_id": who, "device_id": device,
                    "client_uuid": fresh(), "captured_at": stamp, "actions": "[\"watered\"]"])
        case .photos:
            return timed(["id": fresh(), "tree_uuid": tree, "shot_type": "other", "captured_at": stamp,
                    "user_id": who])
        case .photoVotes:
            // The parent photograph is inserted by `seed` and belongs to the device — neither to the
            // account nor to the stranger — so the erasing door's "every vote on the account's
            // photographs" arm cannot be what removes the account's vote.
            return timed(["id": fresh(), "tree_uuid": tree, "user_id": who, "vote": "1"])
        case .favorites:
            return timed(["id": fresh(), "user_id": who, "tree_uuid": tree, "client_uuid": fresh()])
        case .privateReminders:
            return timed(["id": fresh(), "user_id": who, "tree_uuid": tree, "category": "uprooted"])
        case .communityNotes:
            return timed(["id": fresh(), "tree_uuid": tree, "user_id": who, "category": "pest", "stale_at": stamp])
        case .reviewFlags:
            return timed(["id": fresh(), "tree_uuid": tree, "kind": "appears_dead", "raised_by": who])
        case .treeNames:
            return timed(["id": fresh(), "tree_uuid": tree, "name": "Specimen", "given_by": who])
        case .treeStatusOverrides:
            // No `updated_at` on this table (v7).
            let override: [String: String?] = ["tree_uuid": tree, "status": "removed", "set_by": who, "created_at": stamp]
            return override
        case .treeDataDisputes:
            return timed(["id": fresh(), "client_uuid": fresh(), "tree_id": tree, "tree_source": "community",
                    "raised_by": who])
        case .speciesAssertions:
            return timed(["id": fresh(), "tree_uuid": tree, "source": "community", "user_id": who])
        }
    }

    private static func insert(_ table: String, _ values: [String: String?], on connection: SQLiteConnection) throws {
        let columns = values.keys.sorted()
        let statement = try connection.prepare("""
            INSERT INTO \(table) (\(columns.joined(separator: ", ")))
            VALUES (\(columns.map { ":\($0)" }.joined(separator: ", ")))
            """)
        defer { statement.finalize() }
        var bindings: [String: SQLiteBindable?] = [:]
        for column in columns { bindings.updateValue(values[column] ?? nil, forKey: ":\(column)") }
        _ = try statement.bind(bindings)
        try statement.run()
    }

    /// Inserts one row of `table` owned by `account` and returns its primary key.
    private static func seed(_ table: OwnedTable, account: UUID, on connection: SQLiteConnection) throws -> String {
        var values = row(for: table, account: account)
        if table == .photoVotes {
            let photo = UUID().uuidString
            try insert("photos", [
                "id": photo, "tree_uuid": values["tree_uuid"] ?? nil, "shot_type": "other",
                "captured_at": stamp, "device_id": deviceID.uuidString, "created_at": stamp, "updated_at": stamp
            ], on: connection)
            values["photo_id"] = photo
        }
        try insert(table.tableName, values, on: connection)
        let key = try primaryKey(of: table.tableName, on: connection)
        return (values[key] ?? nil) ?? ""
    }

    private static func primaryKey(of table: String, on connection: SQLiteConnection) throws -> String {
        let statement = try connection.prepare("SELECT name FROM pragma_table_info(:table) WHERE pk = 1")
        defer { statement.finalize() }
        _ = try statement.bind([":table": table])
        return try statement.fetchOne { try $0.string("name") } ?? ""
    }

    /// Every column of one row, quoted, so a comparison sees any change at all — including one to a
    /// column nobody thought to look at. Nil when the row does not exist.
    private static func snapshot(_ table: String, key: String, on connection: SQLiteConnection) throws -> String? {
        let pk = try primaryKey(of: table, on: connection)
        let columns = try connection.columnNames(ofTable: table)
        let statement = try connection.prepare("""
            SELECT \(columns.map { "quote(\($0))" }.joined(separator: " || '|' || ")) AS r
              FROM \(table) WHERE \(pk) = :key
            """)
        defer { statement.finalize() }
        _ = try statement.bind([":key": key])
        return try statement.fetchOne { try $0.string("r") }
    }

    /// The account column of one row: `.some(nil)` when the row exists with it NULL, `nil` when the
    /// row does not exist.
    private static func owner(of table: OwnedTable, key: String, on connection: SQLiteConnection) throws -> String?? {
        let pk = try primaryKey(of: table.tableName, on: connection)
        let statement = try connection.prepare(
            "SELECT \(table.accountColumn) AS owner FROM \(table.tableName) WHERE \(pk) = :key"
        )
        defer { statement.finalize() }
        _ = try statement.bind([":key": key])
        return try statement.fetchOne { try $0.stringIfPresent("owner") }
    }

    struct Observed: Sendable {
        var table: OwnedTable
        var ownedBefore: String??
        var ownedAfter: String??
        var strangerOwnerBefore: String??
        var strangerBefore: String?
        var strangerAfter: String?
    }

    @Test(
        "each door does to every owner-bearing table what its classification says, and nothing to a stranger's rows",
        arguments: AccountDeletionChoice.allCases
    )
    func eachDoorKeepsItsClassification(choice: AccountDeletionChoice) async throws {
        let queue = try DatabaseQueue.inMemory()
        let (observed, outcome) = try await queue.withConnection { connection -> ([Observed], AccountDeletion.Outcome) in
            try SchemaMigrator.migrate(AppSchema.migrations, on: connection)

            var seeded: [(table: OwnedTable, owned: String, stranger: String)] = []
            for table in OwnedTable.allCases {
                seeded.append((
                    table,
                    try Self.seed(table, account: Self.userID, on: connection),
                    try Self.seed(table, account: Self.strangerID, on: connection)
                ))
            }
            var observed = try seeded.map { entry in
                Observed(
                    table: entry.table,
                    ownedBefore: try Self.owner(of: entry.table, key: entry.owned, on: connection),
                    ownedAfter: nil,
                    strangerOwnerBefore: try Self.owner(of: entry.table, key: entry.stranger, on: connection),
                    strangerBefore: try Self.snapshot(entry.table.tableName, key: entry.stranger, on: connection),
                    strangerAfter: nil
                )
            }

            let outcome = try AccountDeletion().delete(
                userID: Self.userID, choice: choice, at: Self.moment, connection: connection
            )

            for (index, entry) in seeded.enumerated() {
                observed[index].ownedAfter = try Self.owner(of: entry.table, key: entry.owned, on: connection)
                observed[index].strangerAfter = try Self.snapshot(entry.table.tableName, key: entry.stranger, on: connection)
            }
            return (observed, outcome)
        }

        // Calibration: the harness looked at every classified table, each seed landed where the
        // classification says the account is named, and the door reported doing something.
        #expect(observed.count == OwnedTable.allCases.count)
        #expect(observed.count > 0)
        for row in observed {
            let table = row.table.tableName
            #expect(row.ownedBefore == .some(Self.userID.uuidString), "fixture: \(table)'s owned row does not name the account")
            #expect(row.strangerOwnerBefore == .some(Self.strangerID.uuidString), "fixture: \(table)'s stranger row")
            #expect(row.strangerBefore != nil, "fixture: \(table)'s stranger row was not written")
        }
        // A known-good table, stated on its own: `review_flags` has been reached by both doors since
        // before the doors were two. If this fails the harness is broken, not the classification.
        let flags = try #require(observed.first { $0.table == .reviewFlags })
        switch choice {
        case .leaveRecords:
            #expect(flags.ownedAfter == .some(nil), "calibration: review_flags was not anonymized")
            #expect(outcome.anonymizedAttributions > 0 && outcome.anonymizedContributions > 0, "\(outcome)")
        case .eraseEverything:
            #expect(flags.ownedAfter == nil, "calibration: review_flags was not erased")
            #expect(outcome.deletedAttributions > 0 && outcome.deletedContributions > 0, "\(outcome)")
        }

        for row in observed {
            let table = row.table.tableName
            let fate = row.table.fate(under: choice)
            #expect(
                row.strangerAfter == row.strangerBefore,
                "\(choice): a stranger's \(table) row changed — before \(row.strangerBefore ?? "nil"), after \(row.strangerAfter ?? "nil")"
            )
            switch fate {
            case .anonymized:
                #expect(
                    row.ownedAfter == .some(nil),
                    "\(choice): \(table) is classified anonymized, and its row \(Self.describe(row.ownedAfter))"
                )
            case .deleted:
                #expect(
                    row.ownedAfter == nil,
                    "\(choice): \(table) is classified deleted, and its row \(Self.describe(row.ownedAfter))"
                )
            case .leftAttributed, .notReached:
                #expect(
                    row.ownedAfter == .some(Self.userID.uuidString),
                    """
                    \(choice): \(table) is classified \(fate), and its row \(Self.describe(row.ownedAfter)). \
                    If a door now reaches this table, change its arm in `OwnedTable.fate(under:)`
                    """
                )
            }
        }
    }

    private static func describe(_ owner: String??) -> String {
        switch owner {
        case .none: return "is gone"
        case .some(.none): return "survives with the account column NULL"
        case let .some(.some(value)): return "survives still naming \(value)"
        }
    }
}
