import Foundation
import Testing
@testable import Cypress

/// Screen 17's trailing stamps, and the owner's ruling of 2026-08-21 (RULINGS R80, item 3) about
/// when they stop being clock times.
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

    /// **The heading over those receipts stops saying `today` when they are not all from today.**
    ///
    /// The round that fixed the stamps left this half standing (PR #102 review): `syncedLabel` is
    /// literally `Synced earlier today`, and the section it heads can span two calendar days for
    /// most of any given day — 24 h of retention does that. So the shipped screen could draw
    ///
    ///     Synced earlier today
    ///       Visit · …  ✓ Jan 14
    ///       Visit · …  ✓ Jan 15
    ///
    /// which is the app contradicting itself in its own words, and is half of what the original
    /// report was about: this file's own header names the heading as part of the defect and the
    /// round then fixed only the stamps.
    ///
    /// **Asserted as a change, not as a string.** What matters is that the heading is not the same
    /// answer for both lists — pinning `Recently synced` here would make this a copy test, and the
    /// wording is the implementation's rather than the owner's, and is recorded as such in the
    /// entry the orchestrator splices into `docs/RULINGS.md` at merge. The
    /// one literal claim is the narrow one that actually failed: a spanning list's heading must not
    /// be the `today` one.
    @Test("the synced heading stops claiming today once its own list spans days")
    func theSyncedHeadingFollowsItsList() async throws {
        let clock = OutboxTestSupport.Clock(Self.anchor)
        let store = try await CypressStore.inMemory()
        let queue = OutboxQueue(
            queue: store.queue,
            apply: OutboxTestSupport.ScriptedTransport(script: .allSucceed),
            now: clock.closure
        )

        try await Self.enqueueVisit(on: queue, at: clock.now)
        _ = try await queue.drain()

        let sameDay = Self.presentation(
            try await queue.snapshot(treeNames: Self.treeNames, syncPhotosOnWifiOnly: true),
            now: clock.now
        )
        #expect(
            sameDay.syncedHeading == OutboxCopy.syncedLabel,
            """
            a synced list inside one day is headed \"\(sameDay.syncedHeading)\" — §4's own drawn \
            heading is what a list that really is from earlier today must keep. Only the spanning \
            case was supposed to move.
            """
        )

        clock.advance(by: Self.day)
        try await Self.enqueueVisit(on: queue, at: clock.now)
        _ = try await queue.drain()

        let spanning = Self.presentation(
            try await queue.snapshot(treeNames: Self.treeNames, syncPhotosOnWifiOnly: true),
            now: clock.now
        )
        #expect(spanning.syncedRows.count == 2, "both receipts must be present for this to span")
        #expect(
            spanning.syncedHeading != OutboxCopy.syncedLabel,
            """
            a synced list spanning two calendar days is still headed \
            \"\(spanning.syncedHeading)\", over rows stamped \
            \(spanning.syncedRows.map(\.timeText)) — the heading says today and the rows say \
            otherwise, in the app's own words. That disagreement is what the field report was \
            about; fixing the stamps alone moved it rather than closing it.
            """
        )
    }

    /// **The two sections are asked independently**, which is the judgement call in the rule and the
    /// one part of it nothing asserted (PR #102 review).
    ///
    /// `OutboxCopy.stamp`'s doc argues carefully that the span is a property of the *list*, asked
    /// once **per section** over that section's own dates. The tests above assert the rule *inside*
    /// each section and assert the one-day control; none of them would notice a "simplification"
    /// that asked the question once for the whole screen. That refactor is the likely one — it looks
    /// tidier and it is wrong — and its signature is exactly this fixture: a queue that spans days
    /// beside a synced list that does not.
    ///
    /// So: two failed items a day apart still waiting (the queue has no retention sweep, so it
    /// really can), and one receipt that went today. The queue's rows must carry dates and the
    /// synced row must still carry a clock time. One answer for the screen cannot produce both.
    @Test("a spanning queue and a same-day synced list get different answers")
    func theTwoSectionsAreAskedIndependently() async throws {
        let clock = OutboxTestSupport.Clock(Self.anchor)
        let store = try await CypressStore.inMemory()
        let transport = OutboxTestSupport.ScriptedTransport(script: .allSucceed)
        let queue = OutboxQueue(queue: store.queue, apply: transport, now: clock.closure)

        // Two visits a day apart that will never send. `theseFail` names them, so no later drain
        // can quietly apply them and collapse this fixture into one section.
        let older = try await Self.enqueueVisit(on: queue, at: clock.now)
        clock.advance(by: Self.day)
        let newer = try await Self.enqueueVisit(on: queue, at: clock.now)
        await transport.setScript(
            .theseFail([older.clientUUID, newer.clientUUID], .forbidden)
        )

        // And one that sends, on the second day — so the synced list is inside a single day while
        // the queue beside it spans two.
        try await Self.enqueueVisit(on: queue, at: clock.now)
        _ = try await queue.drain()

        let screen = Self.presentation(
            try await queue.snapshot(treeNames: Self.treeNames, syncPhotosOnWifiOnly: true),
            now: clock.now
        )

        let queueRows = screen.queue
        let syncedRows = screen.syncedRows
        #expect(queueRows.count == 2, "the queue must hold both stuck items for this to span days")
        #expect(syncedRows.count == 1, "exactly one receipt must have gone, and on one day")

        for row in queueRows {
            #expect(
                !row.timeText.contains(":"),
                """
                a queue spanning two days stamped a row \"\(row.timeText)\" — a clock time. The \
                queue's own dates span days, so its rows must carry dates whatever the synced list \
                beside them is doing.
                """
            )
        }
        for row in syncedRows {
            #expect(
                row.timeText.contains(":"),
                """
                a synced list inside one day stamped a row \"\(row.timeText)\" — a date. It took \
                the queue's answer instead of its own, which is the whole thing OutboxCopy.stamp's \
                doc says must not happen: the span is asked once per SECTION, over that section's \
                own dates, not once per screen.
                """
            )
        }
    }

    // MARK: - Support

    @discardableResult
    private static func enqueueVisit(on queue: OutboxQueue, at moment: Date) async throws -> OutboxItem {
        try await queue.enqueue(
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
