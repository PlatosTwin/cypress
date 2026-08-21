import Foundation
import Testing
@testable import Cypress

/// Screen 17's trailing stamps, and the owner's ruling of 2026-08-21 about when they stop being
/// clock times.
///
/// ── **The report** ────────────────────────────────────────────────────────────────────────────
/// From TestFlight: the synced receipts read `1:49 pm` on a list whose rows had gone on different
/// days. Two stamps that looked an hour apart were a day apart, and nothing drawn said so — the
/// section's own heading (`Synced earlier today`) said the opposite.
///
/// ── **The ruling, and how it is asserted here** ───────────────────────────────────────────────
/// Show the date instead of the time once the list spans more than one day; otherwise the time.
///
/// The load-bearing test is `twoRowsADayApartStopSharingOneStamp`, and it is written to be
/// independent of what the date *says*. Two rows enqueued at the same clock time on consecutive
/// days produced two **identical** stamps under the old code — that is the defect, exactly — and
/// produce two different ones under the rule. A test that pinned the string `Aug 19` would be
/// asserting `DateFormatter`'s phrasing and the reader's locale; this asserts the property the
/// reader actually lost, which is that a stamp told one row from another.
@Suite("Outbox stamps say the date once a list spans days")
struct OutboxStampTests {

    private static let deviceID = UUID(uuidString: "9F3A0000-0000-4000-8000-0000000000DE")!
    private static let treeID = UUID(uuidString: "9F3A0000-0000-4000-8000-000000000017")!
    private static let treeNames = [treeID: "The Tea Tree at 46th"]

    /// One fixed calendar for every case here. A stamp is a statement in the reader's own time zone
    /// and `Calendar.current` is the CI machine's, which is a different answer on a different agent.
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    private static let locale = Locale(identifier: "en_US")

    /// 2027-01-14 13:49:00 Pacific — an ordinary afternoon, chosen only so that a day's step lands
    /// nowhere near a midnight or a daylight-saving boundary.
    private static var anchor: Date {
        calendar.date(from: DateComponents(year: 2027, month: 1, day: 14, hour: 13, minute: 49))!
    }

    private static let day: TimeInterval = 24 * 60 * 60

    // MARK: - The span, which is a property of the list

    @Test("a list of one day, however many rows, spans one day")
    func oneDayDoesNotSpan() {
        let calendar = Self.calendar
        let noon = Self.anchor
        #expect(OutboxCopy.spansMoreThanOneDay([], calendar: calendar) == false)
        #expect(OutboxCopy.spansMoreThanOneDay([noon], calendar: calendar) == false)
        #expect(
            OutboxCopy.spansMoreThanOneDay(
                [noon, noon.addingTimeInterval(-6 * 60 * 60), noon.addingTimeInterval(3 * 60 * 60)],
                calendar: calendar
            ) == false,
            "three moments inside one calendar day are one day"
        )
    }

    /// The case a duration test gets wrong: two hours apart, and two days.
    @Test("two moments either side of midnight span two days, however close they are")
    func midnightSplitsTheList() {
        let calendar = Self.calendar
        let elevenPM = calendar.date(
            from: DateComponents(year: 2027, month: 1, day: 14, hour: 23, minute: 0)
        )!
        let oneAM = calendar.date(
            from: DateComponents(year: 2027, month: 1, day: 15, hour: 1, minute: 0)
        )!
        #expect(oneAM.timeIntervalSince(elevenPM) == 2 * 60 * 60)
        #expect(OutboxCopy.spansMoreThanOneDay([elevenPM, oneAM], calendar: calendar))
    }

    // MARK: - The stamp itself

    @Test("a stamp is a clock time on a one-day list and a date on a longer one")
    func theRuleSwitchesTheStamp() {
        let calendar = Self.calendar
        let moment = Self.anchor

        let time = OutboxCopy.stamp(
            moment, spansDays: false, now: moment, calendar: calendar, locale: Self.locale
        )
        let date = OutboxCopy.stamp(
            moment, spansDays: true, now: moment, calendar: calendar, locale: Self.locale
        )

        #expect(time == OutboxCopy.timeStamp(moment, calendar: calendar, locale: Self.locale))
        #expect(
            date == OutboxCopy.dateStamp(moment, now: moment, calendar: calendar, locale: Self.locale)
        )
        #expect(time != date, "the two branches must not produce the same string")
        // The clock time is the thing being replaced, so it must be gone rather than joined.
        #expect(date.contains(":") == false, "a date stamp carries no clock: \(date)")
    }

    /// The queue has no retention sweep, so `Aug 19` in it can be two different years. The synced
    /// section cannot — it is swept at 24 h — which is why this is not always on.
    @Test("a date outside this year carries its year, and one inside it does not")
    func theYearAppearsOnlyWhenItHasTo() {
        let calendar = Self.calendar
        let now = Self.anchor
        // `anchor` is the 14th of January, so a month back is a *different year* — which is what
        // this fixture got wrong on its first run, and the reason both dates below are checked
        // against the calendar rather than assumed from a day count.
        let sameYear = now.addingTimeInterval(-5 * Self.day)
        let lastYear = now.addingTimeInterval(-400 * Self.day)
        #expect(
            calendar.component(.year, from: sameYear) == calendar.component(.year, from: now),
            "the fixture's 'same year' date is not in the same year"
        )
        #expect(
            calendar.component(.year, from: lastYear) != calendar.component(.year, from: now),
            "the fixture's 'other year' date is in the same year"
        )

        let thisYearStamp = OutboxCopy.dateStamp(
            sameYear, now: now, calendar: calendar, locale: Self.locale
        )
        let lastYearStamp = OutboxCopy.dateStamp(
            lastYear, now: now, calendar: calendar, locale: Self.locale
        )

        let year = String(calendar.component(.year, from: sameYear))
        let previous = String(calendar.component(.year, from: lastYear))
        #expect(thisYearStamp.contains(year) == false, "\(thisYearStamp) names a year it need not")
        #expect(lastYearStamp.contains(previous), "\(lastYearStamp) does not say which year it is")
    }

    // MARK: - The two drawn sections

    /// **The defect, as the reader met it.** Same clock time, consecutive days: one stamp each, and
    /// under the old code they were the same string.
    @Test("two rows a day apart stop sharing one stamp")
    func twoRowsADayApartStopSharingOneStamp() async throws {
        let clock = OutboxTestSupport.Clock(Self.anchor)
        let store = try await CypressStore.inMemory()
        let queue = OutboxQueue(
            queue: store.queue,
            apply: OutboxTestSupport.ScriptedTransport(script: .allFail(.serverError)),
            now: clock.closure
        )

        try await Self.enqueueVisit(on: queue, at: clock.now)
        clock.advance(by: Self.day)
        try await Self.enqueueVisit(on: queue, at: clock.now)

        let rows = Self.presentation(
            try await queue.snapshot(treeNames: Self.treeNames, syncPhotosOnWifiOnly: true),
            now: clock.now
        ).queue
        #expect(rows.count == 2, "the queue lost a row before the stamps could be compared")

        let first = try #require(rows.first)
        let second = try #require(rows.last)
        #expect(
            first.timeText != second.timeText,
            """
            two rows enqueued a day apart carry the same stamp — \(first.timeText) — so the screen \
            is drawing a clock time on a list that spans days. That is the build-37 report.
            """
        )
        // And it is a date rather than a time, which is the ruling's other half.
        #expect(
            first.timeText.contains(":") == false,
            "the stamp is still a clock time: \(first.timeText)"
        )
    }

    /// The control, and the half of the ruling that is easiest to lose: within one day the screen
    /// still says the hour, which is what a volunteer draining a queue on a pavement is reading.
    @Test("a one-day queue still stamps the hour")
    func aOneDayQueueKeepsItsClock() async throws {
        let clock = OutboxTestSupport.Clock(Self.anchor)
        let store = try await CypressStore.inMemory()
        let queue = OutboxQueue(
            queue: store.queue,
            apply: OutboxTestSupport.ScriptedTransport(script: .allFail(.serverError)),
            now: clock.closure
        )

        try await Self.enqueueVisit(on: queue, at: clock.now)
        clock.advance(by: 90 * 60)
        try await Self.enqueueVisit(on: queue, at: clock.now)

        let rows = Self.presentation(
            try await queue.snapshot(treeNames: Self.treeNames, syncPhotosOnWifiOnly: true),
            now: clock.now
        ).queue
        let first = try #require(rows.first)
        #expect(
            first.timeText.contains(":"),
            "a queue inside one day must still say the hour, and this says \(first.timeText)"
        )
    }

    /// **The section the report was about.** `Synced earlier today` is drawn from `updatedAt`, and
    /// its rows are stamped by the same rule.
    @Test("synced receipts a day apart stop sharing one stamp")
    func syncedReceiptsADayApartStopSharingOneStamp() async throws {
        let clock = OutboxTestSupport.Clock(Self.anchor)
        let store = try await CypressStore.inMemory()
        let queue = OutboxQueue(
            queue: store.queue,
            apply: OutboxTestSupport.ScriptedTransport(script: .allSucceed),
            now: clock.closure
        )

        try await Self.enqueueVisit(on: queue, at: clock.now)
        _ = try await queue.drain()
        clock.advance(by: Self.day)
        try await Self.enqueueVisit(on: queue, at: clock.now)
        _ = try await queue.drain()

        let receipts = Self.presentation(
            try await queue.snapshot(treeNames: Self.treeNames, syncPhotosOnWifiOnly: true),
            now: clock.now
        ).syncedRows
        #expect(receipts.count == 2, "both items must have gone for this to be a two-day list")

        let newest = try #require(receipts.first)
        let oldest = try #require(receipts.last)
        #expect(
            newest.timeText != oldest.timeText,
            """
            two receipts a day apart carry the same stamp — \(newest.timeText) — which is the \
            reported defect: `1:49 pm` on a list that spans days.
            """
        )
        // §4's check mark survives the change; it is the stamp inside it that moved.
        #expect(newest.timeText.hasPrefix("✓ "))
    }

    // MARK: - Support

    private static func enqueueVisit(on queue: OutboxQueue, at moment: Date) async throws {
        _ = try await queue.enqueue(
            .visit(Visit(
                treeID: treeID,
                attribution: .anonymous(deviceID: deviceID),
                gpsAccuracyM: 5,
                capturedAt: moment
            ))
        )
    }

    private static func presentation(_ snapshot: OutboxSnapshot, now: Date) -> OutboxPresentation {
        OutboxPresentation(snapshot: snapshot, now: now, calendar: calendar, locale: locale)
    }
}
