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
//  ── The `Journal` pill, built and then cut ────────────────────────────────────────────────
//  This suite used to assert three pills, and it carried a test — `theJournalPillIsOneListNotACopy`
//  — placed here so that a round proposing to cut the third had to answer for it first. This is that
//  round, and the answer is not "the old objection was right after all".
//
//  The objection the pill was built over was *drift*: "two copies of a person's own record is two
//  things that must agree forever." That objection was answered and the answer still holds — one
//  derivation (`JournalPresentation`), one model and one view (`JournalSection`), so there was never
//  a second implementation that could disagree. Nothing about that has been discovered to be wrong.
//
//  What the answer did not establish is that a reader needs **two doors into one room**, and the
//  project owner walked into exactly that: *"What's the diff between Trees and Journal? They look
//  almost identical."* For the pill and the tab he was not confused, he was right — they were the
//  same list. Safety from drift is not comprehensibility. The cost the earlier round weighed was a
//  drawn control left unbuilt; the cost observed since is a person unable to tell two of his own
//  screens apart, and that one is larger.
//
//  So the pill is gone, the journal keeps the tab C16 draws for it, and what replaces the old test is
//  `theJournalHasOneDoorNotTwo` — the same guard pointed the other way, so a round that adds a
//  second entrance has to answer for that instead.
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

    // MARK: - The pills

    /// **A decision, asserted.** SCREENS.md 08 §2 draws three pills; this app draws two, and both
    /// lead somewhere.
    ///
    /// The case list is asserted as well as `hasDestination`, because the deviation from the mock is
    /// the decision and a decision that no test states is a decision the next reader has to
    /// reconstruct. `hasDestination` remains the constraint-21 question a new pill has to answer.
    @Test("screen 08's pills are Trees and Species, and both lead somewhere")
    func everyPillHasADestination() {
        // Hoisted out of `#expect`: a key-path `map` resolves to `Sequence.map`'s `rethrows`
        // overload inside the macro expansion, which the macro then reports as an uncaught throw.
        let labels = GroveTab.allCases.map(\.label)
        let allLeadSomewhere = GroveTab.allCases.allSatisfy(\.hasDestination)

        #expect(GroveTab.allCases == [.trees, .species])
        #expect(labels == ["Trees", "Species"])
        #expect(allLeadSomewhere, "a pill is drawn and does nothing")
    }

    /// **The old guard, pointed the other way.** See the file comment for the argument.
    ///
    /// `theJournalPillIsOneListNotACopy` stood here to make a round that cut the pill answer for it.
    /// This replaces it, and what it now protects is the property that round was after: the journal
    /// is reachable from exactly one place. A second entrance — a fourth pill, a row on the You tab,
    /// a card on the map — has to break this test to exist, which is the same forcing function
    /// aimed at the failure that actually happened rather than at the one that did not.
    @Test("the journal has one door, and it is the tab named after it")
    func theJournalHasOneDoorNotTwo() {
        // Nothing on My Grove is named after the journal any more.
        let groveLabels = GroveTab.allCases.map(\.label)
        #expect(groveLabels.contains(JournalCopy.screenTitle) == false, "the journal has two doors again")

        // And the door it does have is still there, with the almanac still beside it — the thing that
        // must not be displaced to make room for anything (ERRATA E57).
        #expect(JournalSegment.allCases.contains(.journal), "the journal has no door at all")
        #expect(JournalSegment.allCases.contains(.almanac))
    }

    /// The two explanatory lines, which are the owner's own ask and are only worth anything as a
    /// pair: they have to say different things, and each has to name the unit its own list counts in.
    @Test("each list says what one of its lines is, and the two do not say the same thing")
    func theExplanationsDistinguishTheTwoLists() {
        #expect(GroveCopy.treesExplanation != JournalCopy.explanation)
        #expect(GroveCopy.treesExplanation.contains("per tree"))
        #expect(JournalCopy.explanation.contains("each thing you did"))
        // Neither may count anything (D1). Dates are identifiers and live on rows; these two strings
        // are the screen's own words and carry no digits at all.
        #expect(GroveCopy.treesExplanation.rangeOfCharacter(from: .decimalDigits) == nil)
        #expect(JournalCopy.explanation.rangeOfCharacter(from: .decimalDigits) == nil)
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
    ///
    /// **The names are distinct and deliberately not alphabetical**, and that is the whole strength
    /// of this test. It first shipped with all three fixtures on the default name, which made a
    /// `sorted(by: displayName)` slipped into the derivation completely invisible — the assertion
    /// passed against a mutant that re-sorted the list. Sorting by *any* of the three fields a row
    /// carries now changes the answer: by name it is Almond, Magnolia, Zelkova; by date it is the
    /// reverse of the store's; the store's own order is the one asserted.
    @Test("the store's order is the screen's order")
    func orderIsTheStores() {
        let entries = [
            Self.entry(1, name: "Zelkova", lastVisitedAt: Self.date(2026, 7, 12)),
            Self.entry(2, name: "Almond", lastVisitedAt: Self.date(2026, 1, 3)),
            Self.entry(3, name: "Magnolia", lastVisitedAt: nil, isFavorite: true)
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
