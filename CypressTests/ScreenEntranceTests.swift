import Foundation
import Testing
@testable import Cypress

/// **Every screen has a way in.**
///
/// Six built screens had none: 05 (ERRATA E24), 11 (E63), 12 (E57), 13 (E66), 16 (E74) and 17
/// (E75). Every route was wired, every destination was tested, and no affordance anywhere in the
/// app pushed any of them — which is a failure no per-screen test could see, because each screen
/// was correct on its own. These tests are about the joins.
///
/// What they can and cannot prove: a presentation exposing an affordance is not the same as a
/// finger reaching it, so these assertions were taken together with a walk through the simulator
/// (documented in the round's report). What they *do* hold is the shape of the mistake — a route
/// with nothing pointing at it, and a read-only record handed a write.
@Suite("Screen entrances")
struct ScreenEntranceTests {

    // MARK: - Fixtures

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
        return calendar
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date()
    }

    private static let now = date(2026, 7, 21)
    private static let treeID = UUID(uuidString: "7E000000-0000-4000-8000-00000000EE01")!
    private static let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-00000000EE02")!
    private static var attribution: Attribution { Attribution(userID: nil, deviceID: deviceID) }

    private static func tree(
        status: TreeStatus,
        cityDBH: IntRange? = IntRange(lowerBound: 30, upperBound: 35)
    ) -> Tree {
        Tree(
            id: treeID,
            externalRef: "13284",
            source: .cityImport,
            coordinate: Coordinate(latitude: 37.799, longitude: -122.443),
            address: "2576 Lombard St",
            status: status,
            plantedYear: 1993,
            dbhCityCmRange: cityDBH,
            verificationState: .cityRecord
        )
    }

    private static func presentation(
        status: TreeStatus = .alive,
        cityDBH: IntRange? = IntRange(lowerBound: 30, upperBound: 35),
        measurements: [TreeMeasurement] = [],
        visits: Series<Visit> = .empty
    ) -> TreeProfilePresentation {
        TreeProfilePresentation(
            profile: TreeProfile(
                tree: tree(status: status, cityDBH: cityDBH),
                measurements: measurements,
                visits: visits
            ),
            now: now,
            calendar: calendar
        )
    }

    private static func dbhReading() -> TreeMeasurement {
        TreeMeasurement.dbh(
            treeID: treeID,
            attribution: attribution,
            capturedAt: date(2026, 6, 1),
            gpsAccuracyM: 6,
            quantity: Quantity(value: 64, unit: .centimetres, method: .tape)
        )
    }

    private static func heightReading() -> TreeMeasurement {
        TreeMeasurement.height(
            treeID: treeID,
            attribution: attribution,
            capturedAt: date(2026, 6, 1),
            gpsAccuracyM: 6,
            quantity: Quantity(value: 18, unit: .metres, method: .estimate)
        )
    }

    private static func visit(_ note: String) -> Series<Visit> {
        Series(complete: [
            Visit(
                treeID: treeID,
                attribution: attribution,
                note: note,
                capturedAt: date(2026, 7, 12)
            ),
        ])
    }

    private static func stat(_ id: String, in presentation: TreeProfilePresentation)
        -> TreeProfilePresentation.StatItem? {
        presentation.stats.first { $0.id == id }
    }

    private static func isPlaceholder(_ value: StatCard.Value) -> Bool {
        if case .placeholder = value { return true }
        return false
    }

    private static func isQuantity(_ value: StatCard.Value) -> Bool {
        if case .quantity = value { return true }
        return false
    }

    private static func isCityRecord(_ value: StatCard.Value) -> Bool {
        if case .cityRecord = value { return true }
        return false
    }

    // MARK: - Every route has an entrance

    /// The switch below is exhaustive over `Route`, so a new screen cannot be added to the app's
    /// inventory without somebody writing down where a person taps to reach it. That is the check
    /// this round existed to install: six routes sat in that enum, resolved and tested, with the
    /// answer to this question missing for all six.
    private static func entrance(for route: Route) -> String {
        switch route {
        case .treeProfile:
            return "01 map pin · 02 shortlist row · 12 almanac season row and 'walk the nine'"
        case .identify:
            return "01 map · the what-tree-is-this FAB"
        case .species:
            return "08 My Grove · a species tile"
        case .careLog:
            return "03 · quad action row, Care (presented as a sheet)"
        case .share:
            return "03 · quad action row, Share (presented as a sheet)"
        case .growthHistory:
            return "03 · a measurement stat card that has a reading in it"
        case .checkIn:
            return "03 · the C7 outline button under the primary CTA (invented, E98)"
        case .report:
            return "03 · quad action row, Report"
        case .almanac:
            return "the Journal tab renders screen 12 as its root (invented, E98)"
        case .activity:
            return "03 · the 'see the whole year' link under the activity feed (invented, E98)"
        case .memorial:
            return "01 map · a gray dash-marked pin"
        case .measure:
            return "03 · a measurement stat card with no reading in it (invented, E98)"
        case .outbox:
            return "the You tab · the outbox row (specified, BUILD-PLAN §9)"
        case .site:
            return "01 map · a pin with no tree behind it (invented, E107)"
        }
    }

    private static let everyRoute: [Route] = [
        .treeProfile(treeID),
        .identify,
        .species(treeID),
        .careLog(treeID),
        .share(treeID),
        .growthHistory(treeID),
        .checkIn(treeID),
        .report(treeID),
        .almanac,
        .activity(treeID),
        .memorial(treeID),
        .measure(treeID),
        .outbox,
        .site(treeID),
    ]

    @Test("every route names a real affordance, not a plan for one")
    func everyRouteHasANamedEntrance() {
        for route in Self.everyRoute {
            let entrance = Self.entrance(for: route)
            #expect(!entrance.isEmpty, "\(route) has no entrance")
            #expect(
                !entrance.lowercased().contains("not built"),
                "\(route) is reachable only in principle"
            )
        }
    }

    @Test("the six routes that had no entrance now have one on a screen a person can be standing on")
    func theSixFormerlyUnreachableRoutes() {
        // 05, 11, 13 and 16 are reached from screen 03, so the presentation that draws 03 has to
        // actually offer them. This is the assertion, not the table above.
        let live = Self.presentation(measurements: [Self.dbhReading()], visits: Self.visit("Fog on the crown"))
        #expect(live.offersCheckIn, "05 has no entrance")
        #expect(live.offersActivityLink, "13 has no entrance")
        #expect(
            live.stats.contains { $0.destination == .growthHistory },
            "11 has no entrance"
        )
        #expect(
            live.stats.contains { $0.destination == .measure },
            "16 has no entrance"
        )

        // 12 and 17 are tab roots and a tab is not a `Route`, so what is checkable here is that the
        // bar can select them at all. The screens behind them were walked in the simulator.
        #expect(Self.entrance(for: .almanac).contains("Journal tab"))
        #expect(Self.entrance(for: .outbox).contains("You tab"))
    }

    // MARK: - The stat card's two destinations

    @Test("a stat card with a reading opens the growth history")
    func filledMeasurementCardOpensGrowthHistory() {
        let subject = Self.presentation(measurements: [Self.dbhReading(), Self.heightReading()])

        let dbh = Self.stat("dbh", in: subject)
        let height = Self.stat("height", in: subject)

        #expect(dbh?.destination == .growthHistory)
        #expect(height?.destination == .growthHistory)
        #expect(Self.isQuantity(dbh?.value ?? .text("")), "a reading renders as its quantity")
        #expect(Self.isQuantity(height?.value ?? .text("")))
    }

    @Test("a stat card with no reading opens the measure sheet")
    func emptyMeasurementCardOpensMeasure() {
        // A city tree: the city's DBH bucket fills the DBH card, so the Height slot is the door.
        let subject = Self.presentation()

        let height = Self.stat("height", in: subject)
        #expect(height?.destination == .measure)
        #expect(Self.isPlaceholder(height?.value ?? .text("")))
        #expect(height?.label == "Height")

        // D7 and E63: the city's 5 cm bucket is a fact, not a door. It opens neither screen.
        let dbh = Self.stat("dbh", in: subject)
        #expect(Self.isCityRecord(dbh?.value ?? .text("")))
        #expect(dbh?.destination == nil, "the city's bucket became tappable")
    }

    @Test("with no city bucket either, both measurement slots stand open")
    func bothSlotsOpenWithoutACityRecord() {
        let subject = Self.presentation(cityDBH: nil)

        #expect(Self.stat("height", in: subject)?.destination == .measure)
        #expect(Self.stat("dbh", in: subject)?.destination == .measure)
    }

    @Test("one kind measured, the other not: the card each gets is the card its record earns")
    func mixedMeasurementState() {
        let subject = Self.presentation(cityDBH: nil, measurements: [Self.heightReading()])

        #expect(Self.stat("height", in: subject)?.destination == .growthHistory)
        #expect(Self.stat("dbh", in: subject)?.destination == .measure)
    }

    // MARK: - A read-only record gains no write

    /// `TreeStatus.acceptsNewContributions` is false for a memorial and a vacant site, and the whole
    /// point of ERRATA E95 is that a new affordance must not be the thing that quietly gives one of
    /// them a write. Both entrances added to screen 03 that *write* — the check-in and the measure
    /// slot — are gated on it, and this is the test that says so for every non-contributing status
    /// at once.
    @Test("a memorial and a vacant site are offered no check-in and no measurement slot")
    func readOnlyRecordsGainNoWriteAffordance() {
        for status in TreeStatus.allCases where !status.acceptsNewContributions {
            let subject = Self.presentation(status: status)

            #expect(!subject.acceptsContributions, "\(status) should take no contribution")
            #expect(!subject.offersCheckIn, "\(status) was offered a check-in")
            #expect(
                !subject.stats.contains { $0.destination == .measure },
                "\(status) was offered a measurement slot"
            )
            #expect(
                !subject.stats.contains { Self.isPlaceholder($0.value) },
                "\(status) drew an invitation to fill a slot it cannot have filled"
            )
        }
    }

    /// The other half of that rule, which is easy to get wrong in the safe direction: a read is not
    /// a write. A removed tree that was measured while it stood still has a growth history, and
    /// nothing about reading it contributes anything.
    @Test("a removed tree keeps the history of the readings it earned while standing")
    func readOnlyRecordsKeepTheirReads() {
        let subject = Self.presentation(status: .removed, measurements: [Self.dbhReading()])

        #expect(!subject.acceptsContributions)
        #expect(Self.stat("dbh", in: subject)?.destination == .growthHistory)
    }

    @Test("every status that does take contributions is offered both")
    func contributingStatusesAreOfferedTheEntrances() {
        for status in TreeStatus.allCases where status.acceptsNewContributions {
            let subject = Self.presentation(status: status, cityDBH: nil)

            #expect(subject.offersCheckIn, "\(status) lost its check-in")
            #expect(
                subject.stats.contains { $0.destination == .measure },
                "\(status) lost its measurement slot"
            )
        }
    }

    // MARK: - The activity link

    @Test("the activity link draws only where there is a year to see")
    func activityLinkFollowsTheFeed() {
        // E67: no tree in the shipped seed carries any activity, and screen 13's state on all of
        // them is a header and one line. A link onto that is a door onto an empty room.
        #expect(!Self.presentation().offersActivityLink)
        #expect(Self.presentation(visits: Self.visit("Fog on the crown")).offersActivityLink)
    }

    // MARK: - The bar the two new tab roots hang on

    @MainActor
    @Test("C16's four labels and the router's four tabs are the same four, both ways")
    func tabTranslationRoundTrips() {
        let router = AppRouter()
        let selection = router.bottomTabSelection

        for tab in BottomTabBar.Tab.allCases {
            selection.wrappedValue = tab
            #expect(selection.wrappedValue == tab, "\(tab) did not survive the round trip")
        }

        // And the two that used to render `NotBuiltYetView` are reachable from the bar.
        selection.wrappedValue = .journal
        #expect(router.tab == .journal)
        selection.wrappedValue = .you
        #expect(router.tab == .you)
    }
}
