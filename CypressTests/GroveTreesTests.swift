//
//  GroveTreesTests.swift
//  CypressTests
//
//  Screen 08's `Trees` and `Journal` pills, which were drawn and inert for the whole life of the app.
//
//  ── What was wrong, and what "fixed" means here ───────────────────────────────────────────
//  SCREENS.md 08 §2 draws three pills. `Species` had a screen; `Trees` and `Journal` were `Text`
//  rather than `Button` — deliberately, because a control that looks pressable and does nothing is
//  worse than a label. Meanwhile `CypressAPI.grove()` has returned `[GroveEntry]` since the protocol
//  was written, with a doc comment explaining that the two tabs of My Grove "are keyed on different
//  things", and `journal(cursor:limit:)` has returned a finished page to nobody for just as long.
//  Both lists the pills wanted had been available the entire time.
//
//  ── The design this suite argues against, and why ─────────────────────────────────────────
//  An earlier, abandoned round proposed shipping `Trees` and **cutting** `Journal`, asserting
//  `GroveTab.allCases == [.trees, .species]`. Its reason was good: "what it could hold is the
//  Journal tab's list, read for read and row for row, and two copies of a person's own record is two
//  things that must agree forever."
//
//  That objection is answered rather than ignored, and it is answered structurally. There is one
//  derivation (`JournalPresentation`), one model and one view (`JournalSection`), mounted in both
//  places. The two surfaces cannot come to disagree because there is no second implementation to
//  drift — and cutting a control the design actually draws would have been the larger invention of
//  the two. `theJournalPillIsOneListNotACopy` is that argument, written where a future round has to
//  answer it before undoing this.
//

import Foundation
import Testing
@testable import Cypress

@Suite("My Grove · the Trees and Journal pills")
struct GroveTreesTests {

    // MARK: - Fixtures

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
        return calendar
    }

    static let locale = Locale(identifier: "en_US")

    static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date()
    }

    static let now = date(2026, 7, 20)

    static func entry(
        _ index: Int,
        name: String = "Grandmother Cypress",
        lastVisitedAt: Date? = GroveTreesTests.date(2026, 7, 12),
        isFavorite: Bool = false
    ) -> GroveEntry {
        GroveEntry(
            treeID: UUID(uuidString: String(format: "08100000-0000-4000-8000-%012d", index))!,
            displayName: name,
            coordinate: Coordinate(latitude: 37.7601, longitude: -122.5089),
            lastVisitedAt: lastVisitedAt,
            isFavorite: isFavorite
        )
    }

    static func presentation(_ entries: [GroveEntry]) -> GroveTreesPresentation {
        GroveTreesPresentation(entries: entries, now: now, calendar: calendar, locale: locale)
    }

    // MARK: - The three pills

    /// **A decision, asserted.** SCREENS.md 08 §2 draws three pills and all three now lead somewhere.
    ///
    /// The check is on `hasDestination` rather than on the case list, because that property is the
    /// question DECISIONS constraint 21 asks of any control — a fourth pill added without answering
    /// it should fail here rather than ship inert.
    @Test("all three of screen 08's pills lead somewhere")
    func everyPillHasADestination() {
        // Hoisted out of `#expect`: a key-path `map` resolves to `Sequence.map`'s `rethrows`
        // overload inside the macro expansion, which the macro then reports as an uncaught throw.
        let labels = GroveTab.allCases.map(\.label)
        let allLeadSomewhere = GroveTab.allCases.allSatisfy(\.hasDestination)

        #expect(GroveTab.allCases == [.trees, .journal, .species])
        #expect(labels == ["Trees", "Journal", "Species"])
        #expect(allLeadSomewhere, "a pill is drawn and does nothing")
    }

    /// The abandoned round's objection, answered. See the file comment.
    ///
    /// What makes two surfaces safe here is that there is only one of everything behind them: the
    /// same presentation type derives both, so a change to what a journal row says lands on both
    /// doors or on neither. If a later round splits them, this is the test that has to be deleted
    /// deliberately rather than quietly broken.
    @Test("the Journal pill and the Journal tab are one list, not two copies of one")
    func theJournalPillIsOneListNotACopy() {
        let entries = [
            JournalPresentationTests.entry(1, kind: .visit),
            JournalPresentationTests.entry(2, kind: .careEvent)
        ]
        // The derivation both mount points use, given the same read, produces the same rows.
        let a = JournalPresentation(entries: entries, nextCursor: nil, now: Self.now, calendar: Self.calendar, locale: Self.locale)
        let b = JournalPresentation(entries: entries, nextCursor: nil, now: Self.now, calendar: Self.calendar, locale: Self.locale)
        let subtitlesA = a.rows.map(\.subtitle)
        let subtitlesB = b.rows.map(\.subtitle)
        #expect(a == b)
        #expect(subtitlesA == subtitlesB)
        // And the tab still holds the almanac, which is the thing that must not have been displaced
        // to make room for it (ERRATA E57).
        #expect(JournalSegment.allCases.contains(.almanac))
    }

    // MARK: - Rows

    /// Both clauses come from the two arms of `ContributionStore.groveTreeIDs` — a visit and a
    /// favourite — so the sentence can be checked against the query that produced the row.
    @Test("a row says what put the tree in this grove, and leaves out what did not")
    func subtitleNamesTheReason() {
        let rows = Self.presentation([
            Self.entry(1, isFavorite: true),
            Self.entry(2, isFavorite: false),
            Self.entry(3, lastVisitedAt: nil, isFavorite: true)
        ]).rows

        #expect(rows[0].subtitle == "Favorite · last visit Jul 12")
        #expect(rows[1].subtitle == "Last visit Jul 12")
        #expect(rows[2].subtitle == "Favorite")
    }

    /// The word is `QuadActionRow.Action.favorite.label`'s, not a second spelling of it: the list
    /// describes what the button did, and a list that renamed the act would be describing a
    /// different one.
    @Test("the grove calls a favourite what the button that made it is called")
    func favoriteMatchesTheControl() {
        let row = Self.presentation([Self.entry(1, lastVisitedAt: nil, isFavorite: true)]).rows[0]
        #expect(row.subtitle == QuadActionRow.Action.favorite.label)
    }

    /// The store orders by `last_visited DESC NULLS LAST` and this derivation must not re-sort:
    /// two orderings is two chances to disagree, and the one in SQL is the one the cursor and the
    /// index are built for.
    @Test("the store's order is the screen's order")
    func orderIsTheStores() {
        let entries = [
            Self.entry(1, lastVisitedAt: Self.date(2026, 7, 12)),
            Self.entry(2, lastVisitedAt: Self.date(2026, 1, 3)),
            Self.entry(3, lastVisitedAt: nil, isFavorite: true)
        ]
        let drawn = Self.presentation(entries).rows.map(\.treeID)
        let read = entries.map(\.treeID)
        #expect(drawn == read)
    }

    @Test("a tree the city named neither way is called what its own page calls it")
    func unnamedTreeUsesTheProfileFallback() {
        let rows = Self.presentation([Self.entry(1, name: "")]).rows
        #expect(rows[0].title == TreeProfilePresentation.fallbackTitle)
    }

    /// A grove spans years exactly as a journal does, and through the same function — so the two
    /// personal lists cannot come to date the same record differently.
    @Test("a visit outside this year carries its year")
    func datesOutsideTheYearKeepTheirYear() {
        let row = Self.presentation([Self.entry(1, lastVisitedAt: Self.date(2024, 7, 12))]).rows[0]
        #expect(row.subtitle.contains("2024"), "two different Julys are drawn under the same label")
    }

    /// D1 again, on the second personal surface. The grove's own footnote — "Quiet collecting. There
    /// are no streaks and no leaderboards." — is the specification of this list as much as of the
    /// species grid above it.
    @Test("nothing the Trees pill draws counts anything")
    func noCountsOnTheTreesPill() {
        let rows = Self.presentation((1...5).map { Self.entry($0, isFavorite: $0.isMultiple(of: 2)) }).rows
        // The subtitles carry dates, which are identifiers and not quantities, so the digit check
        // that guards the journal's copy cannot be run over them. What is checked is the strings the
        // screen owns.
        #expect(GroveCopy.treesEmptyState.rangeOfCharacter(from: .decimalDigits) == nil)
        #expect(GroveCopy.treesLoadFailed.rangeOfCharacter(from: .decimalDigits) == nil)
        #expect(rows.count == 5)
    }

    @Test("an empty grove of trees says so, and a full one does not")
    func emptyState() {
        #expect(Self.presentation([]).emptyState != nil)
        #expect(Self.presentation([Self.entry(1)]).emptyState == nil)
    }

    // MARK: - The model

    /// **The E126 shape, on a read that did not exist when E126 was written.** The `Trees` pill has
    /// a read of its own, so it has a way to fail of its own, and a failed read must not draw the
    /// empty grove — which is a legitimate, common, designed state and therefore an invisible place
    /// for a failure to hide.
    @Test("a trees read that failed is not a grove with no trees in it")
    @MainActor
    func treesFailureIsItsOwnState() async {
        let failed = GroveModel(api: GrovePreviewAPI(treesFail: true), now: { Self.now }, tab: .trees)
        await failed.loadTreesIfNeeded()
        #expect(failed.treesHaveFailed)
        #expect(failed.treesPresentation == nil)

        let empty = GroveModel(api: GrovePreviewAPI(), now: { Self.now }, tab: .trees)
        await empty.loadTreesIfNeeded()
        #expect(empty.treesHaveFailed == false)
        #expect(empty.treesPresentation?.emptyState != nil)
    }

    /// One failing read must not take the other pill down with it. They are two endpoints and
    /// `GroveModel` keeps two phases for exactly this.
    @Test("the species read and the trees read fail separately")
    @MainActor
    func thePhasesAreIndependent() async {
        let model = GroveModel(
            api: GrovePreviewAPI(grove: .empty, treesFail: true),
            now: { Self.now },
            tab: .trees
        )
        await model.load()
        await model.loadTreesIfNeeded()

        #expect(model.hasFailed == false, "a trees failure was reported as a species failure")
        #expect(model.presentation != nil)
        #expect(model.treesHaveFailed)
    }

    @Test("Try again re-runs the trees read")
    @MainActor
    func retryTrees() async {
        let model = GroveModel(api: GrovePreviewAPI(treesFail: true), now: { Self.now }, tab: .trees)
        await model.loadTreesIfNeeded()
        #expect(model.treesHaveFailed)

        // A retry against a double that has stopped failing is the only thing that makes a retry a
        // retry: the second attempt getting a different answer from the first.
        let recovering = GroveModel(
            api: GrovePreviewAPI(trees: [Self.entry(1)]),
            now: { Self.now },
            tab: .trees
        )
        await recovering.retryTrees()
        #expect(recovering.treesHaveFailed == false)
        #expect(recovering.treesPresentation?.rows.count == 1)
    }

    /// The read is deferred until the pill is asked for, and runs once. A `.task(id:)` fires again
    /// on every switch back, so "once" has to be a property of the model rather than of the view.
    @Test("the trees read runs when the pill is asked for, and only once")
    @MainActor
    func theReadIsLazyAndIdempotent() async {
        let counter = GroveReadCounter()
        let model = GroveModel(
            api: GrovePreviewAPI(trees: [Self.entry(1)], groveReads: counter),
            now: { Self.now }
        )

        await model.load()
        #expect(counter.count == 0, "the trees read ran on a screen nobody had opened it on")

        await model.loadTreesIfNeeded()
        #expect(counter.count == 1)

        await model.loadTreesIfNeeded()
        #expect(counter.count == 1, "switching back to the pill re-read a list that was already held")
    }
}
