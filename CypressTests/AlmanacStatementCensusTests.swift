import Foundation
import Testing
@testable import Cypress

/// **What screen 12 actually runs, counted from inside the database.**
///
/// `AlmanacQueryPlanTests` explains the text of nine statements. On its own that proves nothing
/// about the app, and PR #143's review proved it does not by experiment: appending `" -- drift"` to
/// the string a method hands `cachedStatement` left the plan gate explaining a property the app no
/// longer executed, on a fully green suite. Referencing a property from a test makes the *property*
/// exist; it does not make the property be what runs.
///
/// `StatementCensus` closes that. It records every prepare as it happens, so a gate written against
/// it is bound to executed text rather than to a string a test happens to name.
///
/// ── The two halves, and what each one can say ───────────────────────────────────────────────
/// - `eachReadRunsTheTextItsPropertyHolds` puts the census around the nine `AlmanacQueries` methods
///   called directly. It is exact — nine statements, one execution each, and the set is precisely
///   the nine properties — because nothing about it depends on the season or on where the reader is
///   standing. This is the half that catches the drift specimen.
/// - `theAlmanacScreenRunsTheseStatements` puts it around `LocalAPI.almanac(near:in:)`, which is the
///   claim the plan gate's header makes about *screen 12*. It asserts a subset rather than a set,
///   and says which statements it expects and why each one is reached — an almanac read also runs
///   `SpeciesQueries`', `AreaQueries`' and `ContributionStore`' statements, which belong to those
///   files' own gates.
///
/// **This file does not count executions of the screen's read the way `JournalStatementCensusTests`
/// does.** That gate exists because the Journal had an N+1 to remove; the almanac has none to pin —
/// every block below reads once, and a count asserted here would be pinning an absence nobody has
/// measured a defect in. Stated so the omission reads as a decision rather than as an oversight.
@Suite("Almanac · what screen 12 actually runs")
struct AlmanacStatementCensusTests {

    private static let deviceID = UUID(uuidString: "12000000-0000-4000-8000-000000000912")!

    /// The same fix `AlmanacQueryPlanTests` explains the radius arm at — inside Sunset/Parkside, so
    /// `resolveNeighborhood` finds a polygon and the screen takes R29's first arm.
    private static let fix = AlmanacQueryPlanTests.fix

    // MARK: - Every method runs the text its property holds

    @Test("each almanac read prepares exactly the statement its property holds, once")
    func eachReadRunsTheTextItsPropertyHolds() async throws {
        let store = try await AlmanacQueryPlanTests.store()
        let schema = try #require(store.seed, "the store opened without a seed attached")
        let queries = AlmanacQueries(schema: schema)
        let hood = try await AlmanacQueryPlanTests.anyNeighborhood(store)
        try #require(hood.id > 0, "the seed carries no neighborhoods, so this census has no scope")
        let scope = AlmanacScope.neighborhood(id: hood.id, name: hood.name)

        let expected = [
            queries.holdsAnyRecordSQL(scope: scope),
            queries.elderSQL(scope: scope),
            queries.plantingsSQL(scope: scope),
            queries.plantingPinsSQL(scope: scope),
            queries.speciesMixSQL(scope: scope),
            queries.youngTreesWithoutVisitsSQL(scope: scope),
            queries.firstBloomSQL(scope: scope),
            queries.vacantSiteCountSQL(scope: scope),
            queries.vacantSitePinsSQL(scope: scope)
        ]
        #expect(expected.count == Set(expected).count, "two of the nine properties hold the same text")

        let census = StatementCensus()
        await store.queue.installCensus(census)
        let sites: (count: Int, nearest: [TreePin]) = try await store.queue.read { connection in
            _ = try queries.holdsAnyRecord(scope: scope, connection: connection)
            _ = try queries.elder(scope: scope, connection: connection)
            _ = try queries.plantings(scope: scope, from: "2020-03-01", to: "2020-05-31", connection: connection)
            _ = try queries.plantingPins(
                scope: scope, from: "2020-03-01", to: "2020-05-31",
                near: Self.fix, limit: AlmanacLimits.recentPlantingRowLimit, connection: connection
            )
            _ = try queries.speciesMix(scope: scope, connection: connection)
            _ = try queries.youngTreesWithoutVisits(
                scope: scope, plantedOnOrAfter: "2020-01-01",
                limit: AlmanacLimits.coverageRowLimit, connection: connection
            )
            _ = try queries.firstBloom(scope: scope, since: Date(timeIntervalSince1970: 0), connection: connection)
            return try queries.vacantSites(
                scope: scope, near: Self.fix, limit: AlmanacLimits.vacantSiteRowLimit, connection: connection
            )
        }
        await store.queue.installCensus(nil)

        // `vacantSites` is two statements and skips the second when the count is zero, so a
        // neighborhood with no vacant sites would quietly make this census eight rather than nine.
        try #require(
            sites.count > 0,
            """
            '\(hood.name)' holds no vacant planting sites, so `vacantSites` never ran its second \
            statement and this census is counting eight reads, not nine — pick another neighborhood
            """
        )

        let ran = census.statements
        #expect(
            ran.count == expected.count,
            """
            nine almanac reads prepared \(ran.count) statements. More than one apiece is a read \
            that runs a statement per row; fewer is a read that did not run at all: \
            \(Self.histogram(ran))
            """
        )
        #expect(
            Set(ran) == Set(expected),
            """
            an almanac read runs a statement this repository does not explain, or a property holds \
            a text nothing runs. Unexplained: \(Self.label(Set(ran).subtracting(expected))). \
            Explained but not run: \(Self.label(Set(expected).subtracting(ran))). \
            `AlmanacQueryPlanTests` explains these nine texts off the same properties, so a text \
            that drifts from the app is caught here rather than left explained forever
            """
        )
    }

    // MARK: - …and screen 12 is what runs them

    /// **The almanac a reader's fix draws runs the statements the plan gate explains.**
    ///
    /// A subset, and each membership is argued rather than assumed, because which blocks a given
    /// almanac read reaches is a product decision `LocalAPI.almanac(near:in:)` makes:
    ///
    /// - `holdsAnyRecordSQL` is **not** expected. It runs only on R29's radius fallback, and this
    ///   read resolves a polygon — asserted below, so the absence is a fact about the path taken
    ///   rather than about the statement.
    /// - `plantingsSQL` and `plantingPinsSQL` need a spring, and the pins additionally need that
    ///   spring to hold plantings. The year is read out of the seed rather than written down here,
    ///   for `anyNeighborhood`'s reason, and `LocalAPI`'s injectable clock is set to it.
    /// - `youngTreesWithoutVisitsSQL` is read only for `.fromFix`, which is this read.
    /// - `vacantSitePinsSQL` needs a non-zero count, required below.
    @Test("the almanac a fix draws runs the statements this repository explains")
    func theAlmanacScreenRunsTheseStatements() async throws {
        let store = try await AlmanacQueryPlanTests.store()
        let schema = try #require(store.seed, "the store opened without a seed attached")
        let queries = AlmanacQueries(schema: schema)

        // The scope the screen will resolve, resolved here the same way, so the texts below are the
        // texts that read will build.
        let species = SpeciesQueries(schema: schema)
        let polygon = try await store.queue.read { connection in
            try species.resolveNeighborhood(near: Self.fix, connection: connection)
        }
        let found = try #require(polygon, "the fix resolves no neighborhood, so this read takes the radius arm")
        let scope = AlmanacScope.neighborhood(id: found.id, name: found.name)

        // A year whose spring the seed actually holds plantings in, so `plantingPins` is reached.
        let springYear = try await Self.springYearWithPlantings(store, neighborhoodID: found.id)
        let year = try #require(
            springYear,
            "'\(found.name)' records no spring planting in any year, so the newest-neighbors row never draws"
        )
        let calendar = Calendar.current
        let moment = try #require(
            calendar.date(from: DateComponents(year: year, month: 6, day: 15)),
            "could not build a date in \(year)"
        )

        let api = LocalAPI(
            store: store,
            deviceID: Self.deviceID,
            photoDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("almanac-census-\(UUID().uuidString)", isDirectory: true),
            now: { moment }
        )

        let census = StatementCensus()
        await store.queue.installCensus(census)
        let almanac = try await api.almanac(near: Self.fix, in: .here)
        await store.queue.installCensus(nil)

        let hood = try #require(almanac.neighborhood, "the read came back empty, so it ran none of these")
        try #require(
            hood.area == .named(found.name),
            "the read resolved \(hood.area) rather than the polygon this test built its texts for"
        )
        try #require(
            hood.newestNeighbors != nil,
            """
            \(year)'s spring drew no newest-neighbors row for '\(found.name)', so `plantingPins` \
            was never reached and its membership below would be vacuous
            """
        )
        try #require(
            hood.vacantSites != nil,
            "'\(found.name)' drew no vacant-sites block, so `vacantSitePins` was never reached"
        )

        let ran = Set(census.statements)
        let expected: [(String, String)] = [
            ("the elder", queries.elderSQL(scope: scope)),
            ("this spring's plantings", queries.plantingsSQL(scope: scope)),
            ("this spring's plantings, as pins", queries.plantingPinsSQL(scope: scope)),
            ("who lives here", queries.speciesMixSQL(scope: scope)),
            ("the young trees nobody has visited", queries.youngTreesWithoutVisitsSQL(scope: scope)),
            ("the first bloom", queries.firstBloomSQL(scope: scope)),
            ("how many sites are vacant", queries.vacantSiteCountSQL(scope: scope)),
            ("the vacant sites, as pins", queries.vacantSitePinsSQL(scope: scope))
        ]
        for (label, sql) in expected {
            #expect(
                ran.contains(sql),
                """
                screen 12 did not run the statement `AlmanacQueryPlanTests` explains as "\(label)". \
                Either the read stopped reaching that block — the requires above say it did not — \
                or the method no longer runs the text its property holds, which is the drift this \
                census exists to see. What ran: \(Self.label(ran))
                """
            )
        }
    }

    // MARK: - Fixtures

    /// The most recent year in which this neighborhood recorded a planting between March and May.
    ///
    /// Read out of the seed rather than written down, so a rebuilt seed moves the clock this gate
    /// sets rather than silently emptying the row it is about.
    private static func springYearWithPlantings(
        _ store: CypressStore,
        neighborhoodID: Int
    ) async throws -> Int? {
        try await store.queue.read { connection in
            let statement = try connection.prepare("""
                SELECT CAST(substr(t.planted_on, 1, 4) AS INTEGER) AS year
                  FROM \(SeedDatabase.schemaName).trees t
                 WHERE t.neighborhood_id = :hood
                   AND t.planted_on IS NOT NULL
                   AND t.deleted_at IS NULL
                   AND t.status IN ('alive','declining')
                   AND CAST(substr(t.planted_on, 6, 2) AS INTEGER)
                       BETWEEN \(AlmanacWindow.springMonths.lowerBound) AND \(AlmanacWindow.springMonths.upperBound)
                 ORDER BY t.planted_on DESC
                 LIMIT 1
                """)
            defer { statement.finalize() }
            _ = try statement.bind(neighborhoodID, forName: ":hood")
            return try statement.fetchOne { try $0.int("year") }
        }
    }

    // MARK: - Failure text

    private static func histogram(_ statements: [String]) -> String {
        Dictionary(grouping: statements, by: { $0 })
            .map { "\($0.value.count)× \(firstLine(of: $0.key))" }
            .sorted()
            .joined(separator: "; ")
    }

    private static func label(_ statements: Set<String>) -> String {
        statements.isEmpty ? "none" : statements.map(firstLine(of:)).sorted().joined(separator: "; ")
    }

    /// A statement's first non-empty line and its length. `JournalStatementCensusTests.firstLine`
    /// records why the length is not decoration: the drift this catches is often too far into the
    /// text to show in a first line, and without it the two halves of a failure print the same
    /// string and read as a contradiction rather than as a diff.
    private static func firstLine(of sql: String) -> String {
        let head = sql.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty }) ?? "<empty>"
        return "\(head) […\(sql.count) chars]"
    }
}
