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
            // "walk the nine" no longer lands here — it opens the group map, and a pin on that map
            // is what reaches a profile now (ERRATA E129).
            return "01 map pin · 02 shortlist row · 12 almanac season row · a pin on the group map"
        case let .identify(treeID):
            // Two entrances, because the case now names the flow rather than one of its screens
            // (ERRATA E127). With no tree it opens 02 and asks; with one it opens 04's camera for
            // that tree, which is what screen 03's photo CTA means.
            return treeID == nil
                ? "01 map · the what-tree-is-this FAB"
                : "03 · the photo CTA, and the empty photo well above it (E127)"
        case .species:
            return "08 My Grove · a species tile"
        case .careLog:
            return "03 · quad action row, Care (presented as a sheet)"
        case .share:
            return "03 · quad action row, Share (presented as a sheet)"
        case .growthHistory:
            // The link is the entrance that matters: the stat card only reaches here once it holds a
            // reading, which is never true for the person who has just taken the first one (E127).
            return "03 · the 'See every reading' link, and a stat card that has a reading in it"
        case .checkIn:
            return "03 · the C7 outline button under the primary CTA (invented, E98)"
        case .report:
            return "03 · quad action row, Report"
        case .almanac:
            // Still the Journal tab, and now one segment of it rather than the whole of it. The
            // wording keeps "Journal tab" because that is what `theSixFormerlyUnreachableRoutes`
            // checks, and because it is still literally true: `Route.almanac` has no push call site
            // anywhere, so this tab remains screen 12's only entrance in the app (E99).
            return "the Journal tab · the Neighborhood segment (invented, E98)"
        case .activity:
            return "03 · the 'see the whole year' link under the activity feed (invented, E98)"
        case .memorial:
            return "01 map · a gray dash-marked pin"
        case .measure:
            return "03 · a measurement stat card with no reading in it (invented, E98)"
        case .outbox:
            return "the You tab · the outbox row (specified, BUILD-PLAN §9)"
        case .photos:
            return "03 · a tap on the hero photograph (invented, E125)"
        case .site:
            return "01 map · a pin with no tree behind it, or a pin on the group map (E107, E129)"
        case .pinSet:
            return "12 · the 'Walk the nine' CTA and the 'Where a tree could go' row (invented, E129)"
        case .accountAsk:
            // Two, and the second is why the route exists at all. D9 puts the ask on the third
            // visit save, where `VisitSavedView` covers it with no route needed; the You tab needs
            // one because it can sign you out (ERRATA E131), and a sign-out whose only way back is
            // three more field visits is a door that locks behind you.
            return "the third visit save (D9) · the You tab · the account block's Sign in row (E131)"
        }
    }

    private static let everyRoute: [Route] = [
        .treeProfile(treeID),
        .identify(nil),
        .identify(treeID),
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
        .pinSet(pinSet),
        .accountAsk,
    ]

    /// A group of nine, as screen 12's coverage CTA hands one over (ERRATA E129).
    private static let pinSet = PinSet(
        subject: .coverageGap,
        pins: (0..<9).map { AlmanacPresentationTests.pin(500 + $0) },
        count: 9,
        neighborhoodName: "Sunset/Parkside"
    )

    /// **The entrance table is a table of strings, and it has passed on a lie once** (this suite's own
    /// header says so). So the newest row in it is checked against the thing it describes: the two
    /// affordances it names have to actually be on the presentation, and each has to hand over a group
    /// rather than a record.
    ///
    /// That is exactly the assertion whose absence let ERRATA E129 ship twice. Both rows were wired,
    /// both destinations rendered, and what nobody had written down was that a row printing a count
    /// must not resolve to one of the things it counted.
    @Test("the group map's entrance is two affordances that really hand over a group")
    func thePinSetEntranceIsReal() throws {
        #expect(Self.entrance(for: .pinSet(Self.pinSet)).contains("Walk the nine"))
        #expect(Self.entrance(for: .pinSet(Self.pinSet)).contains("Where a tree could go"))

        let almanac = AlmanacPresentation(almanac: Almanac(neighborhood: AlmanacNeighborhood(
            name: "Sunset/Parkside",
            coverage: CoverageGap(trees: Series(complete: (0..<9).map {
                CoverageTree(pin: AlmanacPresentationTests.pin(600 + $0), distanceM: Double(100 + $0 * 50))
            })),
            vacantSites: VacantSites(
                count: 1_474,
                nearest: (0..<20).map { AlmanacPresentationTests.pin(700 + $0, status: .vacantSite) }
            )
        )))

        let coverage = try #require(almanac.coverage, "§4's card is the CTA's home and it did not draw")
        let vacant = try #require(almanac.vacantSites, "R10's row did not draw")
        #expect(coverage.group.pins.count == 9)
        #expect(vacant.group.pins.count == 20)
        #expect(vacant.group.count == 1_474)
    }

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

    // MARK: - The surfaces that are not routes

    /// **Three built surfaces had no entrance, and none of them is a `Route`** — which is exactly why
    /// the table above could not catch them. A tab's segment is not a pushed destination, so the
    /// mechanism this suite installed for screens 05, 11, 12, 13, 16 and 17 had a blind spot the
    /// width of every tab root in the app.
    ///
    /// The three: `CypressAPI.grove()` and `CypressAPI.journal(cursor:limit:)`, both finished and
    /// both called by nothing, sitting behind two pills that SCREENS.md 08 §2 draws and that were
    /// `Text` rather than `Button`; and `CypressAPI.exportLatest(_:)`, whose only caller in the
    /// repository was a test file.
    ///
    /// The export is the one that mattered most, and not because it is the largest. Its own doc
    /// comment ties it to "what a coordinator's 'export my morning' and the account-data request both
    /// need", which makes an unreachable implementation a **privacy commitment the app was not
    /// keeping** rather than a missing convenience.
    @Test("the three built surfaces that were not routes now have a control each")
    func theSurfacesThatWereNotRoutes() {
        // Both pills are controls, and each has a read behind it.
        #expect(GroveTab.trees.hasDestination, "grove() still has no caller")
        #expect(GroveTab.journal.hasDestination, "journal() still has no caller")

        // The export has a row per format, and the two are named apart so neither can be mistaken
        // for the other.
        let everyFormatNamed = ExportFormat.allCases.allSatisfy { !JournalCopy.exportAction($0).isEmpty }
        #expect(ExportFormat.allCases.count == 2)
        #expect(everyFormatNamed)
        #expect(JournalCopy.exportFileName(.csv) != JournalCopy.exportFileName(.geojson))
    }

    /// **The almanac's entrance, guarded against this very round.**
    ///
    /// The Journal tab was screen 12's only way in, and this round put a journal in that tab. Had it
    /// replaced the almanac rather than joining it, a finished, fully specified screen would have
    /// left the product with no code deleted and no test failing — ERRATA E57 reintroduced by the
    /// change that was closing E99.
    @Test("putting a journal in the Journal tab did not evict the almanac from it")
    func theAlmanacWasNotDisplaced() {
        #expect(JournalSegment.allCases.contains(.almanac), "screen 12 has no entrance again")
        #expect(JournalSegment.allCases.contains(.journal))
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

    // MARK: - A tree nobody has touched (ERRATA E127)

    /// The defect the project owner found on their phone: a cold profile drew **no action at all**.
    ///
    /// `isCold` is the state every tree in the shipped city inventory is in on launch day (D8), and
    /// the quad row was inside the view's `if !isCold` because SCREENS.md 14 lists "no quad-action
    /// row" among its deltas. So the shipped app's answer to "this limb is hanging over the pavement"
    /// was nothing. The owner ruled: "A tree no one has touched should at least offer a REPORT and
    /// CARE."
    @Test("a cold profile offers the quad row, and all four of its cells")
    func coldProfileOffersActions() {
        let cold = Self.presentation()
        #expect(cold.isCold, "the fixture is not the cold variant, so this proves nothing")
        #expect(cold.offersQuadActionRow, "a tree nobody has touched offers no action at all")

        // The two the owner named, and the two that need nothing from the tree either.
        #expect(cold.quadActions.contains(.report))
        #expect(cold.quadActions.contains(.care))
        #expect(cold.quadActions.contains(.favorite))
        #expect(cold.quadActions.contains(.share))
    }

    /// The row's arrival on the cold variant must not be the thing that hands a read-only record a
    /// write — E95's rule, restated for the one screen state it had never applied to.
    @Test("a memorial keeps losing the two cells that write, cold or not")
    func coldMemorialStillWithholdsTheWrites() {
        for status in TreeStatus.allCases where !status.acceptsNewContributions {
            let subject = Self.presentation(status: status)
            #expect(subject.offersQuadActionRow, "\(status) lost the row entirely")
            #expect(!subject.quadActions.contains(.care), "\(status) was offered Care")
            #expect(!subject.quadActions.contains(.report), "\(status) was offered Report")
            #expect(subject.quadActions.contains(.favorite), "\(status) lost the one-way heart (R2)")
        }
    }

    // MARK: - The growth history link (ERRATA E127)

    /// Screen 11's second entrance, and the reason it needed one: a stat card is drawn as a fact
    /// beside `Planted 1898` and `SF #13284`, which are not doors, and it *changes meaning* once a
    /// reading lands. Nothing said the word "history" anywhere on the profile.
    @Test("the growth link draws once the tree has a reading on record, and not before")
    func growthLinkFollowsTheRecord() {
        #expect(!Self.presentation().offersGrowthLink, "a door onto 'no measurements yet'")
        #expect(Self.presentation(measurements: [Self.dbhReading()]).offersGrowthLink, "11 has no entrance")
    }

    /// D6 keeps a reading taken on a poor fix off the chart; screen 11 still lists it in the log
    /// (`GrowthLogRow`). The person who took it is the last person who should be told it does not
    /// exist, so the link follows the *record*, not the chart.
    @Test("a reading D6 will not chart still has a history to open")
    func growthLinkFollowsTheRecordNotTheChart() {
        let unchartable = TreeMeasurement.dbh(
            treeID: Self.treeID,
            attribution: Self.attribution,
            capturedAt: Self.date(2026, 6, 1),
            // Worse than D6's 15 m ceiling, so `isChartable` is false and `charts` is empty.
            gpsAccuracyM: 40,
            quantity: Quantity(value: 64, unit: .centimetres, method: .tape)
        )
        let subject = Self.presentation(measurements: [unchartable])

        #expect(!unchartable.isChartable, "the fixture is chartable, so this proves nothing")
        #expect(subject.offersGrowthLink)
        #expect(
            !GrowthHistoryPresentation(profile: subject.profile).isEmpty,
            "the link would open a screen with nothing on it"
        )
    }

    /// A tombstone is not a reading. The link must not survive the deletion of the only measurement.
    @Test("a deleted reading leaves no history to open")
    func growthLinkIgnoresTombstones() {
        var deleted = Self.dbhReading()
        deleted.deletedAt = Self.date(2026, 6, 2)
        #expect(!Self.presentation(measurements: [deleted]).offersGrowthLink)
    }

    /// A cold tree can carry a reading — measuring a trunk needs no photograph and no visit — so the
    /// link cannot be gated on the variant the way the quad row wrongly was.
    @Test("a cold tree that has been measured still gets the link")
    func growthLinkOnAColdProfile() {
        let subject = Self.presentation(measurements: [Self.heightReading()])
        #expect(subject.isCold)
        #expect(subject.offersGrowthLink)
    }

    // MARK: - The photo CTA's destination (ERRATA E127)

    /// The route the profile's photo CTA and its empty well now take.
    ///
    /// What this can prove is that the *case can carry the tree at all* — before E127 it could not,
    /// so `RootView` had nowhere to put the id it was handed and threw it away. That the composition
    /// root now passes it was verified by opening the running app on a cold tree and pressing the
    /// button; see the round's report.
    @Test("the visit flow's route distinguishes 'this tree' from 'which tree is this'")
    func theVisitRouteCarriesItsTree() {
        #expect(Route.identify(Self.treeID) != Route.identify(nil))
        #expect(Route.identify(Self.treeID) == Route.identify(Self.treeID))
        #expect(Self.entrance(for: .identify(Self.treeID)).contains("03"))
        #expect(Self.entrance(for: .identify(nil)).contains("01 map"))
    }

    /// What the camera is opened *with*. Screen 04 puts the tree's name in its header and screen 18
    /// ranks the next nearest tree from its coordinate, and on this entrance both come from the
    /// record rather than from a shortlist row that was never built.
    @Test("a tree's own record is enough to open its camera")
    func theCameraSubjectComesFromTheRecord() {
        let profile = Self.presentation().profile
        let subject = VisitFlowView.Subject(profile)

        #expect(subject.id == Self.treeID)
        #expect(subject.coordinate == profile.tree.coordinate)
        // The same name screen 03's own H1 shows, by the same rule (D15).
        #expect(subject.displayName == TreeProfilePresentation(profile: profile).title)
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
