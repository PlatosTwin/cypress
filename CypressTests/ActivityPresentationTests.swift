import Foundation
import Testing
@testable import Cypress

/// **Screen 13 is the screen most likely to become a leaderboard**, and the three ways that happens
/// are all silent — the software renders, lays out, and is wrong.
///
/// 1. **A below-threshold aggregate draws a zero.** ARCHITECTURE §5.6: "aggregate surfaces below
///    their cold-start threshold do not render at all." A8 floors the headcount at three; §5.6
///    floors an empty year at nothing. E54 settled the same argument at zero on screen 12 in §5.6's
///    favor, and the same reasoning applies here.
/// 2. **A page's size is printed as a total.** ERRATA E38. On this screen a page is worse than a
///    wrong total: D2 makes the three rows share one vertical scale, so a page understates the
///    ceiling and the two rows it did not come from get drawn too tall.
/// 3. **Attribution comes off the stored preference instead of D11's effective one.** D11 forces
///    anonymous attribution for under-18 accounts regardless of the toggle, and
///    `User.isPublicAttributionEffective` is the only predicate allowed to answer it.
///
/// The assertions below are mostly negative — not "the number is right" but "there is no number".
@Suite("Activity · a tree's year, counted honestly")
struct ActivityPresentationTests {

    // MARK: - Fixtures

    /// UTC, so a month boundary is the same boundary on every machine that runs this.
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private static let locale = Locale(identifier: "en_US_POSIX")
    private static let now = calendar.date(from: DateComponents(year: 2026, month: 6, day: 18))!

    private static let treeID = UUID(uuidString: "13000000-0000-4000-8000-000000000001")!
    private static let deviceID = UUID(uuidString: "13000000-0000-4000-8000-0000000000DE")!

    private static func person(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "13000000-0000-4000-8000-%012d", 100 + index))!
    }

    private static let tree = Tree(
        id: treeID,
        externalRef: "114-88",
        source: .cityImport,
        coordinate: Coordinate(latitude: 37.76, longitude: -122.50),
        address: "Great Highway at Judah",
        verificationState: .cityRecord
    )

    private static func date(_ year: Int, _ month: Int, _ day: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private static func photo(_ year: Int, _ month: Int, _ day: Int = 12) -> Photo {
        Photo(treeID: treeID, shotType: .fullTree, capturedAt: date(year, month, day))
    }

    private static func visit(
        _ year: Int,
        _ month: Int,
        _ day: Int = 12,
        tags: [PhenologyTag] = [],
        userID: UUID? = nil
    ) -> Visit {
        Visit(
            treeID: treeID,
            attribution: Attribution(userID: userID, deviceID: deviceID),
            phenologyTags: tags,
            capturedAt: date(year, month, day)
        )
    }

    private static func observation(_ year: Int, _ month: Int, _ day: Int = 12, userID: UUID? = nil) -> TreeObservation {
        TreeObservation(
            treeID: treeID,
            attribution: Attribution(userID: userID, deviceID: deviceID),
            capturedAt: date(year, month, day),
            status: .alive
        )
    }

    private static func care(
        _ year: Int,
        _ month: Int,
        _ day: Int = 12,
        actions: [CareAction] = [.watered],
        userID: UUID? = nil
    ) -> CareEvent {
        CareEvent(
            treeID: treeID,
            attribution: Attribution(userID: userID, deviceID: deviceID),
            capturedAt: date(year, month, day),
            actions: actions
        )
    }

    private static func profile(
        photos: [Photo] = [],
        visits: [Visit] = [],
        observations: [TreeObservation] = [],
        careEvents: [CareEvent] = [],
        complete: Bool = true
    ) -> TreeProfile {
        TreeProfile(
            tree: tree,
            latestObservation: observations.max { $0.capturedAt < $1.capturedAt },
            observations: Series(items: observations, isComplete: complete),
            photos: Series(items: photos, isComplete: complete),
            visits: Series(items: visits, isComplete: complete),
            careEvents: Series(items: careEvents, isComplete: complete),
            ownPhotoIDs: Set(photos.map(\.id))
        )
    }

    private static func present(_ profile: TreeProfile) -> ActivityPresentation {
        ActivityPresentation(profile: profile, now: now, calendar: calendar, locale: locale)
    }

    /// Two care events and two check-ins each for `count` distinct people, all inside A8's
    /// twenty-four-month window — the threshold, met exactly.
    private static func caretakerProfile(people count: Int, photos: [Photo] = []) -> TreeProfile {
        var events: [CareEvent] = []
        var checkIns: [TreeObservation] = []
        for index in 0..<count {
            events.append(care(2026, 1 + index, actions: [.mulched], userID: person(index)))
            checkIns.append(observation(2026, 2 + index, userID: person(index)))
        }
        return profile(photos: photos, observations: checkIns, careEvents: events)
    }

    // MARK: - §5.6 · nothing below the floor

    // The footnote was a fifth thing this test named, until the copy audit of 2026-08-23 removed
    // it from the screen entirely; `glance == nil` covered it then and covers nothing now, because
    // there is no longer a footnote to be absent.
    @Test("an empty record renders no chart, no moments and no strip")
    func emptyRecordRendersNothing() {
        let subject = Self.present(Self.profile())
        #expect(subject.glance == nil)
        #expect(subject.moments.isEmpty)
        #expect(subject.sameWeek.isEmpty)
        #expect(subject.isEmpty)
    }

    /// The zero §5.6 forbids, in the form this screen would produce it: thirty-six empty bars under
    /// `This year at a glance`, on a tree whose only records are from other years.
    @Test("a year with nothing in it draws no card rather than an empty one")
    func emptyYearDrawsNoCard() {
        let subject = Self.present(
            Self.profile(
                photos: [Self.photo(2019, 3), Self.photo(2021, 5)],
                careEvents: [Self.care(2020, 7)]
            )
        )
        #expect(subject.glance == nil)
        // The record still supports the years-on-record moment, which is a different claim.
        #expect(subject.moments.map(\.kind) == [.onRecord])
    }

    /// A8's floor, applied to the two sentences on this screen that count people.
    @Test("a caretakers headcount below three is not rendered, and at three it is")
    func caretakerHeadcountHoldsItsFloor() {
        let firstPhoto = Self.photo(2019, 3, 14)

        for people in 0...2 {
            let subject = Self.present(Self.caretakerProfile(people: people, photos: [firstPhoto]))
            let moment = subject.moments.first { $0.kind == .onRecord }
            #expect(moment != nil, "the years-on-record row itself does not depend on the headcount")
            #expect(
                moment?.subtitle == "First photo Mar 2019",
                """
                at \(people) caretakers the row printed \(moment?.subtitle ?? "nothing"). A8 shows a \
                headcount only at three or more, and below it the clause is dropped rather than \
                rendered smaller.
                """
            )
        }

        let atThreshold = Self.present(Self.caretakerProfile(people: 3, photos: [firstPhoto]))
        #expect(
            atThreshold.moments.first { $0.kind == .onRecord }?.subtitle
                == "First photo Mar 2019 · three people know this tree"
        )
    }

    /// **The two season rows are gone and cannot come back by accident** (copy audit, 2026-08-23).
    ///
    /// This replaces `springFlushVisitorCountHoldsItsFloor` and
    /// `dryWeeksNeedsMoreThanOneMonth`, which guarded the *inside* of two rows the owner has since
    /// killed: `Spring flush noted` and `Watered through the dry weeks`. Deleting them and stopping
    /// there would leave the removal unguarded, and the rows are easy to reinstate — their builders
    /// read ordinary timeline data that is all still there.
    ///
    /// So this is the same fixtures, asserting the opposite: a tree carrying exactly what used to
    /// produce both rows produces neither. It asserts a fact about the screen (what §3 draws for
    /// this record), not a phrasing, so it survives any rewording of the row that remains.
    @Test("a leaf-out visit and a summer of watering no longer caption themselves as a season")
    func theSeasonRowsAreGone() {
        // Three contributors on one April day, all tagging leaf-out: row 1's strongest case, over
        // A8's floor, which is what used to make it print the visitor clause.
        let flush = Self.present(
            Self.profile(
                visits: (0..<3).map { index in
                    Self.visit(2026, 4, 3, tags: [.leafOut], userID: Self.person(index))
                }
            )
        )
        #expect(flush.moments.isEmpty, "a leaf-out visit still produces a moment: \(flush.moments)")

        // Waterings across three of the dry months: row 2's case, well past its two-month floor.
        let watered = Self.present(
            Self.profile(careEvents: [Self.care(2026, 6, 3), Self.care(2026, 7, 9), Self.care(2026, 8, 2)])
        )
        #expect(watered.moments.isEmpty, "watering still produces a moment: \(watered.moments)")

        // The control, and the reason the two assertions above are not vacuous: §3 still draws the
        // row that says what it counts, from a fixture that differs only in what it carries.
        let onRecord = Self.present(Self.profile(photos: [Self.photo(2025, 11)]))
        #expect(onRecord.moments.count == 1)
        #expect(onRecord.moments.first?.kind == .onRecord)
    }

    /// A tree first photographed this year is on record for zero years.
    @Test("zero years on record is not a row")
    func zeroYearsOnRecordIsNotARow() {
        let thisYear = Self.present(Self.profile(photos: [Self.photo(2026, 1)]))
        #expect(thisYear.moments.contains { $0.kind == .onRecord } == false)

        let lastYear = Self.present(Self.profile(photos: [Self.photo(2025, 11)]))
        #expect(lastYear.moments.first { $0.kind == .onRecord }?.title == "One year on record")
    }

    /// `Same week, other years` with no other year in it is a heading that is false.
    @Test("the strip needs a prior year before it draws at all")
    func stripNeedsAPriorYear() {
        let onlyThisWeek = Self.present(Self.profile(photos: [Self.photo(2026, 6, 18)]))
        #expect(onlyThisWeek.sameWeek.isEmpty)

        let withPrior = Self.present(
            Self.profile(photos: [Self.photo(2026, 6, 18), Self.photo(2024, 6, 19), Self.photo(2025, 6, 17)])
        )
        #expect(withPrior.sameWeek.map(\.label) == ["2024", "2025", "this week"])
        #expect(withPrior.sameWeek.map(\.isCurrentWeek) == [false, false, true])
    }

    // MARK: - ERRATA E38 · a page is never a total, and never a scale

    @Test("a paged read prints no total, draws no chart and states no span")
    func aPagedReadPrintsNothing() {
        let rows = Self.profile(
            photos: [Self.photo(2019, 3, 14), Self.photo(2026, 6, 18), Self.photo(2024, 6, 19)],
            visits: [Self.visit(2026, 4, 3, tags: [.leafOut])],
            observations: [Self.observation(2026, 5)],
            careEvents: [Self.care(2026, 6, 3), Self.care(2026, 7, 9), Self.care(2026, 8, 2)]
        )
        let whole = Self.present(rows)
        #expect(whole.glance != nil)
        #expect(whole.moments.isEmpty == false)
        #expect(whole.sameWeek.isEmpty == false)

        // The identical rows, read as a page. Nothing about them changed except what the read can
        // prove, and that is enough to withdraw every claim on the screen.
        let paged = Self.present(
            Self.profile(
                photos: rows.photos.items,
                visits: rows.visits.items,
                observations: rows.observations.items,
                careEvents: rows.careEvents.items,
                complete: false
            )
        )
        #expect(paged.glance == nil)
        #expect(paged.moments.isEmpty)
        #expect(paged.sameWeek.isEmpty)
        #expect(paged.isEmpty)
    }

    /// D2's shared scale is set by the tallest month across all three rows, so a page in *one* of
    /// them is enough to take the whole card down. This pins the direction of the dependency: the
    /// card is not a per-row decision.
    @Test("one paged series takes the whole card, because the scale is shared")
    func onePagedSeriesTakesTheWholeCard() {
        let subject = ActivityPresentation(
            profile: TreeProfile(
                tree: Self.tree,
                observations: Series(complete: [Self.observation(2026, 5)]),
                // Only the photo series is a page.
                photos: Series(items: [Self.photo(2026, 6)], isComplete: false),
                visits: .empty,
                careEvents: Series(complete: [Self.care(2026, 6)])
            ),
            now: Self.now,
            calendar: Self.calendar,
            locale: Self.locale
        )
        #expect(subject.glance == nil)
    }

    // MARK: - D1 / BUILD-PLAN §4 · which counts may be printed

    /// BUILD-PLAN §4, `care_events`: "Never publicly counted or ranked (D1)". BUILD-PLAN outranks
    /// SCREENS.md (ARCHITECTURE §1), so the drawn `9` is not drawn — while D2's chart itself stays,
    /// because a shape is not a tally.
    @Test("the care series draws its bars and prints no total")
    func careSeriesPrintsNoTotal() {
        let subject = Self.present(
            Self.profile(
                photos: [Self.photo(2026, 6), Self.photo(2026, 6, 20)],
                observations: [Self.observation(2026, 5)],
                careEvents: [Self.care(2026, 6, 3), Self.care(2026, 7, 9)]
            )
        )
        let rows = try! #require(subject.glance).rows
        #expect(rows.map(\.kind) == [.photos, .checkIns, .care])
        #expect(rows[0].total == "2")
        #expect(rows[1].total == "1")
        #expect(rows[2].total == nil, "the care row printed a total, which BUILD-PLAN §4 forbids")
        // The bars are still there: two months with care in them, ten without.
        #expect(rows[2].emptyMonths.count == 10)
        #expect(rows[2].counts.reduce(0, +) == 2)
    }

    /// **BUILD-PLAN §4: care events are "never publicly counted or ranked (D1)".**
    ///
    /// This test used to hold that rule through §5's footnote, which named the month that set the
    /// chart's ceiling and was written to fall silent when that month's ceiling was a care count.
    /// The copy audit of 2026-08-23 removed the footnote from the screen (owner ruling), and with
    /// it the only sentence that could have leaked the number in prose.
    ///
    /// The rule outlived the sentence, so the test does: the tallest bar on the card belongs to the
    /// care row here, and the number behind it must appear nowhere the screen draws — not as the
    /// row's total, and not inside any other string. Asserted over everything the card produces
    /// rather than over one field, because that is how the footnote leaked it in the first place.
    @Test("a care month at the ceiling publishes its count nowhere on the screen")
    func aCareCeilingPublishesNoCount() throws {
        let careCeiling = Self.present(
            Self.profile(
                photos: [Self.photo(2026, 6)],
                careEvents: [Self.care(2026, 7, 2), Self.care(2026, 7, 9), Self.care(2026, 7, 19)]
            )
        )
        let glance = try #require(careCeiling.glance, "the card is absent, so nothing below is tested")

        // The care row really is the tallest — otherwise this fixture proves nothing about a
        // ceiling that a care month set.
        let care = try #require(glance.rows.first { $0.kind == .care })
        #expect(care.counts.max() == 3)
        #expect(glance.rows.allSatisfy { ($0.counts.max() ?? 0) <= 3 })
        #expect(care.total == nil, "the care row printed a total, which BUILD-PLAN §4 forbids")

        var drawn = glance.rows.flatMap { [$0.name, $0.total ?? ""] }
        drawn.append(glance.year)
        drawn += careCeiling.moments.flatMap { [$0.title, $0.subtitle] }
        drawn += careCeiling.sameWeek.map(\.label)

        for string in drawn {
            #expect(
                !string.contains("3"),
                "the care count reached a drawn string: \(string)"
            )
        }
    }

    /// **The whole of D2 on this screen**: one height rule for all three rows. A count of n draws
    /// the same bar whichever series it is in, and the peak is the only thing that reaches the top.
    @Test("one scale across all three rows, and an empty month keeps the stub")
    func oneScaleAcrossAllThreeRows() {
        let subject = Self.present(
            Self.profile(
                // June: four photos — the peak. February: one.
                photos: [Self.photo(2026, 6, 1), Self.photo(2026, 6, 2), Self.photo(2026, 6, 3), Self.photo(2026, 6, 4)],
                // February: one check-in, the same count as February's photos.
                observations: [Self.observation(2026, 2)],
                careEvents: [Self.care(2026, 2)]
            )
        )
        let rows = try! #require(subject.glance).rows
        #expect(rows[0].heights[5] == ActivityMetrics.barMaximum, "the peak month must reach the ceiling")
        #expect(
            rows[1].heights[1] == rows[2].heights[1],
            "one check-in and one care event are the same amount and must draw the same bar"
        )
        #expect(rows[0].heights[0] == ActivityMetrics.barMinimum)
        #expect(rows[0].emptyMonths.contains(0))
        #expect(rows[0].emptyMonths.contains(5) == false)
        // A month with something in it is never shorter than an empty one, at any peak.
        for row in rows {
            for month in 0..<12 where !row.emptyMonths.contains(month) {
                #expect(row.heights[month] > ActivityMetrics.barMinimum)
            }
        }
    }

    /// Nothing on this screen names anybody. The strongest form of D11 compliance available is that
    /// there is no attribution call site here at all, and this pins it: the only person-shaped thing
    /// the presentation produces is a spelled-out headcount.
    @Test("no name, initial or identifier reaches any string on this screen")
    func nothingOnScreenNamesAnybody() {
        let named = UUID(uuidString: "13000000-0000-4000-8000-0000000000AA")!
        let subject = Self.present(
            Self.profile(
                photos: [Self.photo(2019, 3, 14)],
                visits: [Self.visit(2026, 4, 3, tags: [.leafOut], userID: named)],
                observations: [Self.observation(2026, 5, userID: named)],
                careEvents: [Self.care(2026, 6, 3, userID: named), Self.care(2026, 7, 9, userID: named)]
            )
        )

        var strings = subject.moments.flatMap { [$0.title, $0.subtitle] }
        strings.append(subject.treeDisplayName)
        if let glance = subject.glance {
            strings.append(glance.year)
            strings += glance.rows.flatMap { [$0.name, $0.total ?? ""] }
        }
        strings += subject.sameWeek.map(\.label)

        for string in strings {
            #expect(string.contains(named.uuidString) == false)
            #expect(string.lowercased().contains("visitor") ? string.contains("visitors caught") : true)
        }
    }
}

// MARK: - D11's effective check

/// **D11: attribution is never read off the stored preference.** `User.publicAttribution` is a
/// toggle a minor can switch on; `User.isPublicAttributionEffective` is the only predicate that may
/// answer whether a name may be shown, and it refuses for an under-18 account whatever the toggle
/// says.
///
/// Screen 13 has no attribution call site — it renders no name, initial or avatar — so the way this
/// screen honors D11 is by having nothing for the predicate to gate. That makes the risk *forward*
/// rather than present: the day somebody adds an avatar row to this screen, the raw preference is
/// the field autocomplete offers. So the predicate itself is pinned here alongside the screen, the
/// way `SharePresentationTests` pins it alongside screen 10.
@Suite("Activity · attribution goes through D11's effective check")
struct ActivityAttributionTests {

    private static func user(_ bucket: BirthYearBucket, publicAttribution: Bool) -> User {
        User(
            email: "a@b.c",
            displayName: "N",
            birthYearBucket: bucket,
            publicAttribution: publicAttribution
        )
    }

    @Test("an under-18 account is anonymous however the stored preference is set")
    func minorsAreAnonymousRegardlessOfThePreference() {
        let minorOptedIn = Self.user(.under18, publicAttribution: true)
        #expect(minorOptedIn.publicAttribution, "the stored preference is what a minor could set")
        #expect(
            minorOptedIn.isPublicAttributionEffective == false,
            "D11 forces anonymous attribution for under-18 accounts regardless of the preference"
        )

        #expect(Self.user(.over18, publicAttribution: true).isPublicAttributionEffective)
        #expect(Self.user(.over18, publicAttribution: false).isPublicAttributionEffective == false)
        #expect(Self.user(.unknown, publicAttribution: true).isPublicAttributionEffective)
        // The default: opt-in, so an account that never answered shows no name (DECISIONS §3.11).
        #expect(User(email: "a@b.c", displayName: "N").isPublicAttributionEffective == false)
    }

    /// The C26 question, answered as a test rather than as a comment: with no account system there
    /// is no user id on any contribution (D9), so A8's distinct-user count is zero on every tree in
    /// the shipped app and the caretakers surface never renders — on 03 or on 13.
    @Test("anonymous device contributions produce no caretakers surface at all")
    func anonymousContributionsProduceNoCaretakers() {
        let deviceID = UUID()
        let treeID = UUID()
        let tree = Tree(
            id: treeID,
            source: .cityImport,
            coordinate: Coordinate(latitude: 37.76, longitude: -122.50),
            verificationState: .cityRecord
        )
        // Twelve care events and twelve check-ins, all from this device, none carrying a user id —
        // which is what every contribution the shipped app writes looks like.
        let events = (0..<12).map { index in
            CareEvent(
                treeID: treeID,
                attribution: .anonymous(deviceID: deviceID),
                capturedAt: Date().addingTimeInterval(-Double(index) * 86_400),
                actions: [.watered]
            )
        }
        let checkIns = (0..<12).map { index in
            TreeObservation(
                treeID: treeID,
                attribution: .anonymous(deviceID: deviceID),
                capturedAt: Date().addingTimeInterval(-Double(index) * 86_400),
                status: .alive
            )
        }
        let profile = TreeProfile(
            tree: tree,
            observations: Series(complete: checkIns),
            careEvents: Series(complete: events)
        )

        let base = TreeProfilePresentation(profile: profile)
        #expect(base.caretakers == nil)
        #expect(base.caretakerHeadline == nil)

        let activity = ActivityPresentation(profile: profile)
        #expect(
            activity.moments.contains { $0.subtitle.contains("know this tree") } == false,
            "a headcount appeared on a tree whose every contribution is anonymous"
        )
    }
}
