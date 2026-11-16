//
//  CommunityHistoryRowsTests.swift
//  CypressTests
//
//  Round C3: a community tree's history in the tree profile's activity list. The owner's answers of
//  2026-11-14 set the rows word for word, the "Mar 20" date, the four-row limit, and the "Added"
//  row from what the phone knows when the history cannot be read. The owner's ruling of 2026-11-15
//  dates "Added" by the day the tree was added on its adder's phone.
//

import Foundation
import Testing
@testable import Cypress

@Suite("Community tree history on the profile")
struct CommunityHistoryRowsTests {

    static let treeID = UUID(uuidString: "C3000000-0000-4000-8000-00000000A001")!
    static let spot = Coordinate(latitude: 37.7600, longitude: -122.5050)

    static func zone(_ identifier: String) throws -> TimeZone {
        try #require(TimeZone(identifier: identifier), "no zone \(identifier) on this runtime")
    }

    static func calendar(_ zone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    static func instant(_ iso: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: iso), "not an instant: \(iso)")
    }

    static func day(_ iso: String) throws -> CalendarDay {
        try #require(CalendarDay(isoDate: iso), "not a day: \(iso)")
    }

    static func event(
        _ kind: CommunityTreeHistory.Kind,
        _ iso: String,
        id: UUID = UUID(),
        from: Coordinate? = nil,
        to: Coordinate? = nil
    ) throws -> CommunityTreeHistory.Event {
        CommunityTreeHistory.Event(id: id, kind: kind, day: try day(iso), fromCoordinate: from, toCoordinate: to)
    }

    static func profile(
        history: CommunityTreeHistory?,
        addedByYou: Bool = false,
        isAddedHere: Bool = false,
        createdAt: Date = Date(timeIntervalSince1970: 1_789_948_800),
        source: TreeSource = .community,
        visits: [Visit] = [],
        care: [CareEvent] = []
    ) -> TreeProfile {
        TreeProfile(
            tree: Tree(id: treeID, source: source, coordinate: spot, createdAt: createdAt, updatedAt: createdAt),
            visits: Series(items: visits, isComplete: true),
            careEvents: Series(items: care, isComplete: true),
            addedByYou: addedByYou,
            communityHistory: history,
            isAddedHere: isAddedHere
        )
    }

    static func history(_ events: [CommunityTreeHistory.Event], complete: Bool = true) -> CommunityTreeHistory {
        CommunityTreeHistory(treeID: treeID, events: events, isComplete: complete)
    }

    static func rows(_ profile: TreeProfile, zone: TimeZone = .current) -> [TreeProfilePresentation.ActivityItem] {
        TreeProfilePresentation(profile: profile, calendar: calendar(zone)).activity
    }

    /// `label + detail`, the way `ActivityRow` reads them out.
    static func spoken(_ rows: [TreeProfilePresentation.ActivityItem]) -> [String] {
        rows.map { $0.label + $0.detail }
    }

    // MARK: - The words

    /// All four events, both readers. Every event the service serves is the adder's, so
    /// `addedByYou` decides the wording of every row together.
    ///
    /// Red-proof: swap the two arms of the `locationCorrected` label in `historyItems` — red on both
    /// readers.
    @Test("the four events read in the owner's words, for other readers and for the adder")
    func theEightStrings() throws {
        let from = Self.spot
        let to = VisitPinAdjust.offset(from, northM: 12, eastM: 0)
        let events = [
            try Self.event(.speciesCorrected, "2026-09-24"),
            try Self.event(.speciesNamed, "2026-09-23"),
            try Self.event(.locationCorrected, "2026-09-22", from: from, to: to),
            try Self.event(.added, "2026-09-21"),
        ]
        let others = Self.spoken(Self.rows(Self.profile(history: Self.history(events))))
        #expect(others == ["Species corrected", "Species named", "Pin moved · 12 m north", "Added"])

        let yours = Self.spoken(Self.rows(Self.profile(history: Self.history(events), addedByYou: true, isAddedHere: true)))
        #expect(yours == [
            "You corrected the species", "You named the species", "You moved the pin · 12 m north", "You added this tree",
        ])
    }

    /// The distance and the direction, from known coordinates.
    ///
    /// Red-proof: swap `origin` and `destination` in `TreeProfileCopy.pinMovedDetail` — red,
    /// reading "south-west".
    @Test("a move reads its whole meters and one of eight directions")
    func northEast() throws {
        let from = Self.spot
        let to = VisitPinAdjust.offset(from, northM: 8.5, eastM: 8.5)
        // Calibration: the move is 12 m, so the row's number is the distance and not a constant.
        #expect(Int(from.distance(to: to).rounded()) == 12)
        #expect(TreeProfileCopy.pinMovedDetail(from: from, to: to) == " · 12 m north-east")
        #expect(TreeProfileCopy.pinMovedDetail(from: to, to: from) == " · 12 m south-west")
        #expect(TreeProfileCopy.pinMovedDetail(from: nil, to: to) == "")
        #expect(TreeProfileCopy.pinMovedDetail(from: from, to: nil) == "")
    }

    /// A move that rounds to 0 m names no direction, the way `VisitShortlist.label` prints a
    /// distance that rounds to 0 m. The owner has not ruled on this; it follows that precedent.
    ///
    /// Red-proof: remove the `meters > 0` guard in `pinMovedDetail` — red, reading a direction.
    @Test("a move that rounds to 0 m reads 0 m and no direction")
    func zeroMeters() throws {
        let from = Self.spot
        let to = VisitPinAdjust.offset(from, northM: 0.3, eastM: 0)
        // Calibration: the move is real but rounds to 0 m.
        #expect(from.distance(to: to) > 0)
        #expect(Int(from.distance(to: to).rounded()) == 0)
        #expect(TreeProfileCopy.pinMovedDetail(from: from, to: to) == " · 0 m")
        #expect(TreeProfileCopy.pinMovedDetail(from: from, to: from) == " · 0 m")
    }

    // MARK: - The date

    /// A history day prints as itself far east and far west of UTC.
    @Test("a history row's day prints as itself at UTC+12 and at UTC−10")
    func theDayIsTheDay() throws {
        let events = [try Self.event(.added, "2026-03-20")]
        for identifier in ["Pacific/Auckland", "Pacific/Honolulu", "UTC"] {
            let rows = Self.rows(Self.profile(history: Self.history(events)), zone: try Self.zone(identifier))
            #expect(rows.map(\.timestamp) == ["Mar 20"], "at \(identifier)")
        }
    }

    /// Somebody else's tree, with no history read: the cache holds the service's day as midnight
    /// UTC, and the "Added" row must print that day, not the day before (west of UTC).
    ///
    /// Red-proof: date the fallback with `readerDay(of:)` for a cached tree as well — red at
    /// Honolulu, reading "Mar 19".
    @Test("another person's tree: the Added row is the service's day in every zone")
    func cachedAddedDay() throws {
        let midnight = try Self.instant("2026-03-20T00:00:00Z")
        for identifier in ["Pacific/Honolulu", "Pacific/Auckland", "America/Los_Angeles"] {
            let rows = Self.rows(Self.profile(history: nil, createdAt: midnight), zone: try Self.zone(identifier))
            #expect(Self.spoken(rows) == ["Added"], "at \(identifier)")
            #expect(rows.map(\.timestamp) == ["Mar 20"], "at \(identifier)")
        }
    }

    /// The reader's own tree on this phone: `createdAt` is the add's instant, and the day is the
    /// reader's own. 20:00 UTC on the 20th is the 21st in Auckland.
    ///
    /// Red-proof: date the fallback with `CalendarDay(utcDayOf:)` for this phone's row too — red,
    /// reading "Mar 20".
    @Test("your own tree: the Added row is the day of the add in your zone")
    func ownAddedDay() throws {
        let evening = try Self.instant("2026-03-20T20:00:00Z")
        let auckland = Self.rows(
            Self.profile(history: nil, addedByYou: true, isAddedHere: true, createdAt: evening),
            zone: try Self.zone("Pacific/Auckland")
        )
        #expect(Self.spoken(auckland) == ["You added this tree"])
        #expect(auckland.map(\.timestamp) == ["Mar 21"])

        let honolulu = Self.rows(
            Self.profile(history: nil, addedByYou: true, isAddedHere: true, createdAt: evening),
            zone: try Self.zone("Pacific/Honolulu")
        )
        #expect(honolulu.map(\.timestamp) == ["Mar 20"])
    }

    // MARK: - The "Added" row from what the phone knows

    /// Nil, empty and capped histories each still draw one "Added" row, for both readers.
    @Test("no history, an empty one, or a capped one still draws the Added row")
    func theFallback() throws {
        let capped = Self.history([try Self.event(.speciesNamed, "2026-09-25")], complete: false)
        let cases: [(String, CommunityTreeHistory?)] = [
            ("nil", nil), ("empty", Self.history([])), ("capped", capped),
        ]
        for (name, history) in cases {
            let others = Self.spoken(Self.rows(Self.profile(history: history)))
            #expect(others.last == "Added", "\(name): \(others)")
            #expect(others.filter { $0 == "Added" }.count == 1, "\(name): \(others)")
            let yours = Self.spoken(Self.rows(Self.profile(history: history, addedByYou: true, isAddedHere: true)))
            #expect(yours.last == "You added this tree", "\(name): \(yours)")
        }
    }

    /// A history that has its `added` event draws no second "Added" row.
    @Test("a history with its own added event draws one Added row")
    func noDoubleAdded() throws {
        let rows = Self.spoken(Self.rows(Self.profile(history: Self.history([try Self.event(.added, "2026-09-21")]))))
        #expect(rows == ["Added"])
    }

    /// A kind this build does not know makes no row; a city tree makes none at all.
    @Test("an unrecognized kind makes no row, and a city tree has no history rows")
    func noRowsWhereNoneBelong() throws {
        let events = [try Self.event(.unrecognized("photo_added"), "2026-09-22"), try Self.event(.added, "2026-09-21")]
        #expect(Self.spoken(Self.rows(Self.profile(history: Self.history(events)))) == ["Added"])
        #expect(Self.rows(Self.profile(history: Self.history(events), source: .cityImport)).isEmpty)
    }

    // MARK: - Mixed with visits and care

    static func visit(_ iso: String) throws -> Visit {
        let at = try instant(iso)
        return Visit(
            treeID: treeID, attribution: .anonymous(deviceID: UUID()), capturedAt: at, createdAt: at, updatedAt: at
        )
    }

    /// Four rows at most, newest day first; on one day a visit sorts above a history row.
    ///
    /// Red-proof: make the `if aHistory != bHistory` line in `activity` return `aHistory` instead
    /// of `!aHistory` — red on the same-day order. Dropping the line does not go red: the lines
    /// below it still happen to put this visit first, because visits come before history rows in
    /// the list the sort starts from.
    @Test("history rows mix with visits by day, a visit above a history row on the same day, four at most")
    func mixedAndLimited() throws {
        let honolulu = try Self.zone("Pacific/Honolulu")
        // 18:00 UTC on Sep 22 is 08:00 on Sep 22 in Honolulu.
        let sameDayVisit = try Self.visit("2026-09-22T18:00:00Z")
        let laterVisit = try Self.visit("2026-09-25T20:00:00Z")
        let events = [
            try Self.event(.speciesCorrected, "2026-09-24"),
            try Self.event(.speciesNamed, "2026-09-22"),
            try Self.event(.locationCorrected, "2026-09-21"),
            try Self.event(.added, "2026-09-20"),
        ]
        let rows = Self.rows(
            Self.profile(history: Self.history(events), visits: [sameDayVisit, laterVisit]),
            zone: honolulu
        )
        #expect(rows.count == TreeProfilePresentation.activityLimit)
        #expect(rows.map(\.kind) == [.visit, .history, .visit, .history])
        #expect(Self.spoken(rows).map { $0.hasPrefix("Visit") ? "Visit" : $0 } == [
            "Visit", "Species corrected", "Visit", "Species named",
        ])
        #expect(rows.map(\.timestamp).last == "Sep 22")
    }

    /// A feed of history rows alone opens no screen 13: that screen charts visits, check-ins and
    /// care, and none of those exist here.
    ///
    /// Red-proof: return `!activity.isEmpty` from `offersActivityLink` — red.
    @Test("a community tree with only history rows offers no See the whole year link")
    func noLinkForHistoryAlone() throws {
        let presentation = TreeProfilePresentation(profile: Self.profile(history: nil))
        #expect(!presentation.activity.isEmpty, "calibration: the Added row is there")
        #expect(!presentation.offersActivityLink)

        let visited = TreeProfilePresentation(profile: Self.profile(history: nil, visits: [try Self.visit("2026-09-22T18:00:00Z")]))
        #expect(visited.offersActivityLink)
    }

    /// A city tree with care and no visit or photo is cold, and screen 14 draws no activity feed
    /// for it. A cold community tree draws one, for its "Added" row.
    ///
    /// Red-proof: return `true` from `drawsActivityFeed` — red on the city tree.
    @Test("a care-only city tree is cold and draws no feed; a cold community tree draws one")
    func careOnlyCityTree() throws {
        let at = try Self.instant("2026-09-22T18:00:00Z")
        let care = CareEvent(
            treeID: Self.treeID, attribution: Attribution(userID: nil, deviceID: UUID()),
            capturedAt: at, actions: [.watered]
        )
        let city = TreeProfilePresentation(profile: Self.profile(history: nil, source: .cityImport, care: [care]))
        // Calibration: the care entry is there and would make a row, and the tree is still cold.
        #expect(city.isCold)
        #expect(city.activity.map(\.kind) == [.care])
        #expect(!city.drawsActivityFeed)

        let community = TreeProfilePresentation(profile: Self.profile(history: nil))
        #expect(community.isCold)
        #expect(community.drawsActivityFeed)

        let visited = TreeProfilePresentation(
            profile: Self.profile(history: nil, source: .cityImport, visits: [try Self.visit("2026-09-22T18:00:00Z")])
        )
        #expect(!visited.isCold)
        #expect(visited.drawsActivityFeed)
    }

    // MARK: - Whose rows are "you"

    /// The reasoning behind "every row is the adder's", checked on the one event the phone can
    /// match: a pin move's event id is the id of the move's row in this phone's `tree_locations`
    /// (`LocalAPI.correctLocation`), and only the adder can write one. So a history holding that
    /// id belongs to a profile whose reader added the tree.
    ///
    /// Red-proof: swap the two arms of the `locationCorrected` label in `historyItems` — red on the
    /// label (the same break turns `theEightStrings` red).
    @Test("a move this phone made is in a history whose rows say You")
    func aMoveFromThisPhoneIsYours() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: LocationCorrectionTests.deviceID)
        let tree = try await LocationCorrectionTests.add(api)
        let moved = VisitPinAdjust.offset(tree.coordinate, northM: 12, eastM: 0)
        _ = try await api.correctLocation(treeID: tree.id, to: moved, placement: .contributorPlaced, locationAccuracyM: nil)
        let chain = try await LocationCorrectionTests.chain(store, tree.id)
        let move = try #require(chain.first { $0.id != tree.id }, "the move wrote no row of its own")

        let local = try await api.treeProfile(id: tree.id)
        #expect(local.addedByYou)
        let served = CommunityTreeHistory(treeID: tree.id, events: [
            CommunityTreeHistory.Event(
                id: move.id, kind: .locationCorrected, day: try Self.day("2026-09-22"),
                fromCoordinate: tree.coordinate, toCoordinate: moved
            ),
        ], isComplete: true)
        let merged = TreeProfile(
            tree: local.tree, addedByYou: local.addedByYou, communityHistory: served, isAddedHere: local.isAddedHere
        )
        let rows = Self.spoken(TreeProfilePresentation(profile: merged).activity)
        #expect(rows.contains("You moved the pin · 12 m north"), "\(rows)")
    }
}
