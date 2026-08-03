//
//  MeasureEntranceKindTests.swift
//  CypressTests
//
//  **Which measurement screen 16 opens on, and who decided.**
//
//  Reported by the project owner walking the app: "if adding a reading for height the height sub
//  screen should open, not dbh, and vice versa for dbh."
//
//  The join this is about is the one `ScreenEntranceTests` was built for and could not see. That
//  suite asserts every route has an affordance pointing at it; this asserts that an affordance
//  which *names a measurement* hands that measurement on. A card labelled `Height` whose only
//  meaning is that this tree has no height on it, opening a form pre-set to trunk diameter, is a
//  route with a correct entrance and a wrong argument — and `Route.measure` had no argument to be
//  wrong until now.
//
//  **Why the wrong default was not cosmetic.** `MeasurePresentation`'s sanity pill compares a draft
//  against previous readings *of the drafted kind*. Enter from the empty `Height` card on a tree
//  with no readings, type the number off the tape and save without looking at a segmented control
//  further up the screen, and the record gains a trunk diameter of 18 metres with nothing anywhere
//  in the flow positioned to notice.
//

import Foundation
import Testing
@testable import Cypress

@Suite("Screen 16 opens on the measurement its entrance named")
struct MeasureEntranceKindTests {

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
    private static let treeID = UUID(uuidString: "7E000000-0000-4000-8000-0000000016A1")!
    private static let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-0000000016A2")!
    private static var attribution: Attribution { Attribution(userID: nil, deviceID: deviceID) }

    /// A standing tree. `cityDBH` defaults to `nil` so that the DBH slot is an *empty* slot rather
    /// than the city's inert bucket card — the two empty slots side by side are the subject here.
    private static func tree(status: TreeStatus = .alive, cityDBH: IntRange? = nil) -> Tree {
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
        cityDBH: IntRange? = nil,
        measurements: [TreeMeasurement] = []
    ) -> TreeProfilePresentation {
        TreeProfilePresentation(
            profile: TreeProfile(
                tree: tree(status: status, cityDBH: cityDBH),
                measurements: measurements,
                visits: .empty
            ),
            now: now,
            calendar: calendar
        )
    }

    private static func height(_ value: Double) -> TreeMeasurement {
        TreeMeasurement.height(
            treeID: treeID,
            attribution: attribution,
            capturedAt: date(2026, 6, 1),
            gpsAccuracyM: 6,
            quantity: Quantity(value: value, unit: .meters, method: .estimate)
        )
    }

    private static func dbh(_ value: Double) -> TreeMeasurement {
        TreeMeasurement.dbh(
            treeID: treeID,
            attribution: attribution,
            capturedAt: date(2026, 6, 1),
            gpsAccuracyM: 6,
            quantity: Quantity(value: value, unit: .centimeters, method: .tape)
        )
    }

    private static func growth(
        status: TreeStatus = .alive,
        measurements: [TreeMeasurement] = []
    ) -> GrowthHistoryPresentation {
        GrowthHistoryPresentation(
            profile: TreeProfile(tree: tree(status: status), measurements: measurements, visits: .empty),
            calendar: calendar
        )
    }

    private static func destination(_ id: String, in presentation: TreeProfilePresentation)
        -> TreeProfilePresentation.StatDestination? {
        presentation.stats.first { $0.id == id }?.destination
    }

    // MARK: - The defect, in the smallest form that can hold it

    /// **This is the assertion that was red before the fix**, and it is deliberately the weakest one
    /// that could be: it needs to know nothing about `MeasurementKind` at all, only that two cards
    /// labelled with two different measurements cannot be the same door.
    ///
    /// `StatDestination.measure` carried no payload, so both empty slots produced the identical
    /// value and this compared equal. Every stronger assertion in this file needs the enum to have
    /// grown a kind first, so this one is the record of what the code said beforehand.
    @Test("the empty Height card and the empty DBH card are not the same door")
    func theTwoEmptySlotsAreDifferentDoors() {
        let subject = Self.presentation()

        let height = Self.destination("height", in: subject)
        let dbh = Self.destination("dbh", in: subject)

        #expect(height != nil, "the Height slot is not on the profile at all")
        #expect(dbh != nil, "the DBH slot is not on the profile at all")
        #expect(
            height != dbh,
            "the Height card and the DBH card open screen 16 in the same state, so one of them lies"
        )
    }

    // MARK: - Which measurement each door names

    @Test("each empty slot opens screen 16 on its own measurement")
    func eachSlotNamesItsOwnKind() {
        let subject = Self.presentation()

        #expect(Self.destination("height", in: subject) == .measure(.height))
        #expect(Self.destination("dbh", in: subject) == .measure(.dbh))
    }

    /// The mixed state, which is the one the owner described: *"sometimes for DBH too when that's
    /// missing"*. A tree with a height already on it draws a filled Height card that opens the
    /// chart, and an empty DBH slot — and that slot must open DBH.
    @Test("with one kind already measured, the surviving slot still names its own")
    func theSurvivingSlotNamesItsOwnKind() {
        let subject = Self.presentation(measurements: [Self.height(18)])

        #expect(Self.destination("height", in: subject) == .growthHistory)
        #expect(Self.destination("dbh", in: subject) == .measure(.dbh))
    }

    /// A city tree, which is every tree in the shipped seed: the city's 5 cm bucket fills the DBH
    /// card and leaves it inert (D7, E63), so the Height slot is the only door — and it is a height
    /// door. This is the exact combination that used to send somebody entering under the word
    /// `Height` into a form set to trunk diameter.
    @Test("on a city tree the Height slot is the only door, and it is a height door")
    func theCityTreesOneDoorIsAHeightDoor() {
        let subject = Self.presentation(cityDBH: IntRange(lowerBound: 30, upperBound: 35))

        #expect(Self.destination("height", in: subject) == .measure(.height))
        #expect(Self.destination("dbh", in: subject) == nil, "the city's bucket became tappable")
    }

    // MARK: - The last hop, which the first version of these tests could not reach

    /// **The gap this suite shipped with, found by breaking the half it did not cover.**
    ///
    /// Every assertion above stops at `StatDestination`. Between that and the screen there is one
    /// more hop — the view turning a destination into a `Route` — and it was a private instance
    /// method, so nothing could call it. Rewriting that one line as
    /// `case .measure: return .measure(treeID, .dbh)` reinstates the owner's exact bug (tap
    /// `HEIGHT · Add a reading`, get a trunk-diameter sheet in metres) **with the whole suite
    /// green**, which is what happened.
    ///
    /// The remedy is the one `MapHomeView.route(for:)` already uses and
    /// `PinSetDestinationTests` already exercises: make the mapping `static`, hand it the id, and
    /// call it from here. A mapping only the renderer can reach is a mapping nothing checks — and
    /// "which layer owns this decision" being written down in a comment is not the same as the
    /// other layer being made to honour it.
    @Test("the profile's own card-to-route mapping carries the kind through")
    func theViewsMappingCarriesTheKind() {
        let id = Self.treeID

        #expect(TreeProfileView.route(for: .measure(.height), treeID: id) == .measure(id, .height))
        #expect(TreeProfileView.route(for: .measure(.dbh), treeID: id) == .measure(id, .dbh))
        #expect(TreeProfileView.route(for: .growthHistory, treeID: id) == .growthHistory(id))
    }

    /// The same hop for every card the profile actually draws, taken end to end: from the
    /// presentation's stats, through the view's mapping, to the `Route` the router receives. This
    /// is the assertion that would have caught the break in either half on its own.
    @Test("every drawn measurement card routes to its own measurement, end to end")
    func everyDrawnCardRoutesToItsOwnKind() {
        let subject = Self.presentation()
        let id = Self.treeID

        let routes = subject.stats.compactMap { stat in
            stat.destination.map { (stat.id, TreeProfileView.route(for: $0, treeID: id)) }
        }

        #expect(routes.first { $0.0 == "height" }?.1 == .measure(id, .height))
        #expect(routes.first { $0.0 == "dbh" }?.1 == .measure(id, .dbh))
    }

    /// Screen 11's link had the identical shape of gap — a `Route` built inline in a view body,
    /// with a hardcoded `.dbh` nothing could reach. Same remedy, same assertion.
    @Test("screen 11's add-a-reading link routes to the measure sheet")
    func elevensLinkRoutesToTheMeasureSheet() {
        let id = Self.treeID

        #expect(GrowthHistoryView.route(forAddReading: id) == .measure(id, .dbh))
        #expect(
            GrowthHistoryView.route(forAddReading: id)
                == .measure(id, GrowthHistoryPresentation.addReadingKind),
            "the link stopped honouring the kind the presentation names"
        )
    }

    // MARK: - What the screen actually opens on

    /// The presentation naming a kind is only half of it; the screen has to open on that kind. This
    /// is the other end of the same wire, one layer below `MeasureView`'s `init`.
    ///
    /// **The unit travels with the kind**, which is why `MeasureDraft(kind:)` exists: a height draft
    /// opened in centimetres is the same silent error one step further along, and `switchUnit`'s own
    /// comment already records what a wrong unit costs on an append-only record.
    @Test("the model opens on the kind it was handed, in that kind's unit")
    @MainActor
    func theModelOpensOnTheKindItWasHanded() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let outbox = OutboxQueue(queue: store.queue, transport: APIOutboxTransport(api: api))

        for kind in [MeasurementKind.height, .dbh] {
            let model = MeasureModel(
                treeID: Self.treeID,
                api: api,
                outbox: outbox,
                attribution: Self.attribution,
                initialDraft: MeasureDraft(kind: kind)
            )

            #expect(model.presentation.draft.kind == kind)
            #expect(
                model.presentation.draft.unit == MeasureMetrics.defaultUnit(for: kind),
                "\(kind) opened in the wrong unit"
            )
        }
    }

    /// `MeasureDraft()` keeps opening on DBH — SCREENS.md 16 §2's drawn selection — because one
    /// entrance genuinely names no measurement: screen 11's general `Add a reading` link. Pinned so
    /// that a later change to the default is a deliberate one.
    @Test("the default is still 16 §2's drawn selection")
    func theDrawnDefaultIsUnchanged() {
        #expect(MeasureDraft().kind == .dbh)
        #expect(MeasureDraft().unit == MeasureMetrics.defaultUnit(for: .dbh))
    }

    // MARK: - The entrance that survives a fully measured tree (RULINGS R15)

    /// **The hole the owner walked into.** A tree with both measures has no empty slot, so before
    /// R15 it had no door to screen 16 anywhere in the app — and it is the tree with the most growth
    /// left to record.
    @Test("a tree with both measures has no stat-card door to screen 16")
    func aFullyMeasuredTreeHasNoSlotLeft() {
        let subject = Self.presentation(measurements: [Self.height(18), Self.dbh(64)])

        #expect(
            !subject.stats.contains { $0.destination?.isMeasure == true },
            "the premise of R15 has changed: a fully measured tree now has a slot again"
        )
        // …and the way through is 11, which it can reach.
        #expect(subject.offersGrowthLink, "11 is unreachable, so the general entrance is too")
    }

    /// Screen 11's general entrance, which is what closes that hole.
    @Test("screen 11 offers to add a reading, in every state a contribution is allowed in")
    func elevenCarriesTheGeneralEntrance() {
        #expect(Self.growth(measurements: [Self.dbh(64)]).offersAddReading)

        // The empty state too — every tree in the shipped seed is in it, and an empty room with no
        // door out is the state E63 recorded and R11 forbids.
        let empty = Self.growth()
        #expect(empty.isEmpty)
        #expect(empty.offersAddReading, "the emptiest screen in the app has no way to fill itself")
    }

    /// E95's rule, applied to the new control from the other side: a record that takes no
    /// contribution is offered no write. 11 is reachable with a removed tree — a memorial's readings
    /// are still readings — so this gate is not theoretical.
    @Test("a read-only record is offered no reading to add")
    func aReadOnlyRecordIsOfferedNoWrite() {
        for status in TreeStatus.allCases where !status.acceptsNewContributions {
            #expect(
                !Self.growth(status: status).offersAddReading,
                "\(status) was offered a write on screen 11"
            )
        }
    }
}
