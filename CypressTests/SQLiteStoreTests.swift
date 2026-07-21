import Foundation
import Testing
@testable import Cypress

/// The sqlite3 wrapper, the migration runner, and the schema invariants BUILD-PLAN §13 asks to be
/// enforced by the engine rather than by convention.
@Suite("SQLite store")
struct SQLiteStoreTests {

    @Test("binding lifetime, transactions, migrations, and schema invariants")
    func storeGate() async throws {
        let failures = try await DataGates.sqliteStore()
        #expect(failures.isEmpty, "\(failures.count) gate failures:\n\(failures.joined(separator: "\n"))")
    }

    @Test("every checked return code surfaces as a SQLiteError, not as silence")
    func errorsSurface() async throws {
        let queue = try await DatabaseQueue.inMemory()
        await #expect(throws: SQLiteError.self) {
            try await queue.read { connection in
                _ = try connection.prepare("SELECT * FROM a_table_that_does_not_exist")
            }
        }
        await #expect(throws: SQLiteError.self) {
            try await queue.read { connection in
                try connection.execute("this is not sql")
            }
        }
    }

    @Test("a unique violation is distinguishable from every other constraint failure")
    func uniqueViolationIsDistinguishable() async throws {
        let queue = try await DatabaseQueue.inMemory()
        try await queue.write { connection in
            try connection.execute("CREATE TABLE t (id TEXT PRIMARY KEY, n INTEGER CHECK (n > 0))")
            try connection.execute("INSERT INTO t VALUES ('a', 1)")
        }
        do {
            try await queue.write { connection in try connection.execute("INSERT INTO t VALUES ('a', 1)") }
            Issue.record("a duplicate primary key was accepted")
        } catch let error as SQLiteError {
            #expect(error.isConstraintViolation)
            #expect(error.isUniqueConstraintViolation)
            #expect(error.asAPIError == .validationFailed)
        }
        do {
            try await queue.write { connection in try connection.execute("INSERT INTO t VALUES ('b', 0)") }
            Issue.record("a CHECK violation was accepted")
        } catch let error as SQLiteError {
            #expect(error.isConstraintViolation)
            #expect(!error.isUniqueConstraintViolation)
        }
    }

    @Test("timestamps round-trip through both spellings the seed and the app emit")
    func timestampRoundTrip() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000.25)
        let text = SQLiteTimestamp.string(from: date)
        let parsed = try #require(SQLiteTimestamp.date(from: text))
        #expect(abs(parsed.timeIntervalSince(date)) < 0.002)
        // The generator writes `+00:00` with no fractional seconds.
        #expect(SQLiteTimestamp.date(from: "2026-07-21T18:51:49+00:00") != nil)
        #expect(SQLiteTimestamp.date(from: "2026-07-21T18:51:49Z") != nil)
        #expect(SQLiteTimestamp.date(from: "not a date") == nil)
    }

    @Test("a measurement round-trips with its method and unit intact (D7)")
    func measurementRoundTrip() async throws {
        let store = try await CypressStore.inMemory()
        let contributions = ContributionStore()
        let treeID = UUID()
        let measurement = TreeMeasurement.dbh(
            treeID: treeID,
            attribution: OutboxTestSupport.attribution,
            capturedAt: Date(),
            gpsAccuracyM: 4,
            quantity: Quantity(value: 12.5, unit: .inches, method: .caliper)
        )
        try await store.queue.write { connection in
            try contributions.insert(measurement, connection: connection)
        }
        let read = try await store.queue.read { connection in
            try contributions.measurements(treeID: treeID, connection: connection)
        }
        let stored = try #require(read.first)
        #expect(stored.quantity.method == .caliper)
        #expect(stored.quantity.unitEntered == .inches)
        #expect(abs(stored.quantity.value - 12.5) < 0.000_001)
        #expect(abs(stored.quantity.siValue - 12.5 * 0.0254) < 0.000_001)
        #expect(stored.measurementHeightM == TreeMeasurement.defaultDBHMeasurementHeightM)
        #expect(stored.series == .measured)
    }

    @Test("a favorite toggles through a tombstone and never through a delete")
    func favoritesAreTombstoned() async throws {
        let store = try await CypressStore.inMemory()
        let contributions = ContributionStore()
        let treeID = UUID()
        let userID = OutboxTestSupport.userID

        try await store.queue.write { connection in
            try contributions.applyFavoriteToggle(
                userID: userID, treeID: treeID, clientUUID: UUID(),
                isFavorite: true, at: Date(), connection: connection
            )
        }
        #expect(try await store.queue.read { try contributions.isFavorite(userID: userID, treeID: treeID, connection: $0) })

        try await store.queue.write { connection in
            try contributions.applyFavoriteToggle(
                userID: userID, treeID: treeID, clientUUID: UUID(),
                isFavorite: false, at: Date(), connection: connection
            )
        }
        #expect(try await !store.queue.read { try contributions.isFavorite(userID: userID, treeID: treeID, connection: $0) })

        // The row survives as a tombstone, which is what sync needs.
        let rowCount = try await store.queue.read { connection -> Int in
            let statement = try connection.prepare("SELECT COUNT(*) AS n FROM favorites")
            defer { statement.finalize() }
            return try statement.fetchOne { try $0.int("n") } ?? 0
        }
        #expect(rowCount == 1)
    }

    @Test("an observation reporting a removal opens a review flag rather than mutating the tree")
    func removalOpensAReviewFlag() async throws {
        for status in ObservationStatus.allCases {
            let observation = TreeObservation(
                treeID: UUID(),
                attribution: OutboxTestSupport.attribution,
                capturedAt: Date(),
                status: status
            )
            #expect((observation.raisesReviewFlagKind != nil) == status.opensReviewFlag)
        }
    }

    @Test("the seed and the app database are separate files")
    func attachKeepsTheTwoApart() async throws {
        let store = try await CypressStore.inMemory()
        let schemas = try await store.queue.read { try $0.attachedSchemas() }
        #expect(schemas.contains("main"))
        // No seed in this fixture, so nothing is attached under that name.
        #expect(!schemas.contains(SeedDatabase.schemaName))
    }
}
