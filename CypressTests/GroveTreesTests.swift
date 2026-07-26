//
//  GroveTreesTests.swift
//  CypressTests
//
//  Screen 08's `Trees` pill, and the `Journal` pill that is no longer beside it.
//
//  ── Where this started ────────────────────────────────────────────────────────────────────
//  SCREENS.md 08 §2 draws three pills, and for most of the app's life only `Species` had a screen:
//  `Trees` and `Journal` were `Text` rather than `Button`, on the sound grounds that a control which
//  looks pressable and does nothing is worse than a label. Both destinations turned out to be built
//  and merely unreachable, so both became controls — and then one of them turned out to be a second
//  door onto a room the app already had.
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

@Suite("My Grove · the Trees pill, and the Journal pill that was cut")
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
        isFavorite: Bool = false,
        record: GroveRecord? = GroveRecord(visits: 1)
    ) -> GroveEntry {
        GroveEntry(
            treeID: UUID(uuidString: String(format: "08100000-0000-4000-8000-%012d", index))!,
            displayName: name,
            coordinate: Coordinate(latitude: 37.7601, longitude: -122.5089),
            lastVisitedAt: lastVisitedAt,
            isFavorite: isFavorite,
            record: record
        )
    }

    static func presentation(_ entries: [GroveEntry]) -> GroveTreesPresentation {
        GroveTreesPresentation(entries: entries)
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

    /// **The line that used to be a date.** It read `Favorite · last visit Jul 12`, which is the
    /// grammar the Journal also uses, which is why the two screens were indistinguishable.
    ///
    /// What it says now is the shape of the relationship: which acts, how many of each, and none of
    /// the kinds that are zero — because a stated zero is a sentence about what somebody has not
    /// done, and this screen has no opinion about that.
    @Test("a row says what the relationship with the tree consists of")
    func subtitleDescribesTheRelationship() {
        let rows = Self.presentation([
            Self.entry(1, isFavorite: true, record: GroveRecord(visits: 4, measurements: 1)),
            Self.entry(2, isFavorite: false, record: GroveRecord(visits: 1)),
            Self.entry(3, isFavorite: true, record: GroveRecord.none),
            Self.entry(4, isFavorite: false, record: GroveRecord(checkIns: 2, careEvents: 1))
        ]).rows

        #expect(rows[0].subtitle == "Favorite · 4 visits · 1 measurement")
        #expect(rows[1].subtitle == "1 visit")
        #expect(rows[2].subtitle == "Favorite")
        #expect(rows[3].subtitle == "2 check-ins · 1 care log")
    }

    /// **No date on this screen, at all.** The old clause is what made a set of trees read as a
    /// chronology; recency now lives in the ordering and nowhere else.
    ///
    /// Asserted against a month name rather than against the old literal, so that reinstating the
    /// clause in *any* format fails here.
    @Test("nothing a grove row draws is a date")
    func noDatesOnTheTreesPill() {
        let rows = Self.presentation([
            Self.entry(1, lastVisitedAt: Self.date(2026, 7, 12), isFavorite: true),
            Self.entry(2, lastVisitedAt: Self.date(2024, 3, 4), record: GroveRecord(visits: 2))
        ]).rows

        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        for row in rows {
            for month in months {
                #expect(
                    row.subtitle.contains(month) == false,
                    "\(row.subtitle) dates a tree, which is the journal's job"
                )
            }
            #expect(row.subtitle.contains("2024") == false)
        }
    }

    /// The word is `QuadActionRow.Action.favorite.label`'s, not a second spelling of it: the list
    /// describes what the button did, and a list that renamed the act would be describing a
    /// different one.
    @Test("the grove calls a favourite what the button that made it is called")
    func favoriteMatchesTheControl() {
        let row = Self.presentation([Self.entry(1, lastVisitedAt: nil, isFavorite: true, record: GroveRecord.none)]).rows[0]
        #expect(row.subtitle == QuadActionRow.Action.favorite.label)
    }

    // MARK: - The tally, held to D1 and E38

    /// **The assertion that separates a description from a score.** `GroveRecord` claims the tally is
    /// never compared and never ordered on; this is the claim, executed.
    ///
    /// The fixture is built so that a `sorted(by: record)` slipped into the derivation — in either
    /// direction — changes the answer: the tree with the most against it is in the middle, the one
    /// with the least is at the top, and the store's own order is none of those. A list that ranked
    /// a person's trees by how much they had done to them is a leaderboard with one player.
    @Test("the tally does not sort the list, and the store's order still does")
    func theTallyDoesNotSortTheList() {
        let entries = [
            Self.entry(1, name: "Zelkova", record: GroveRecord(visits: 1)),
            Self.entry(2, name: "Almond", record: GroveRecord(visits: 40, careEvents: 12)),
            Self.entry(3, name: "Magnolia", record: GroveRecord(visits: 7))
        ]
        let drawn = Self.presentation(entries).rows.map(\.treeID)
        #expect(drawn == entries.map(\.treeID), "the grove is ordered by how much you have done")
    }

    /// **No total, anywhere.** A per-tree description becomes a score the moment something adds it
    /// up, so the type carries no sum and the derivation produces no row that is about the grove
    /// rather than about a tree.
    ///
    /// Checked two ways, because either alone is weak: no row's text may contain the sum of the
    /// grove, and the number of rows is the number of trees rather than the number of acts.
    @Test("nothing sums the tally across the grove")
    func theTallyIsNeverATotal() {
        let entries = [
            Self.entry(1, record: GroveRecord(visits: 3)),
            Self.entry(2, record: GroveRecord(visits: 4)),
            Self.entry(3, record: GroveRecord(visits: 5))
        ]
        let presentation = Self.presentation(entries)
        #expect(presentation.rows.count == 3, "the grove drew a row per act rather than per tree")
        for row in presentation.rows {
            #expect(row.subtitle.contains("12") == false, "a grove-wide total reached a row")
        }
        // And the type itself offers no sum to print. `GroveRecord.isEmpty` answers the only
        // whole-record question the drawing asks, and it answers it without producing a number.
        #expect(GroveRecord(visits: 3, checkIns: 1).isEmpty == false)
        #expect(GroveRecord.none.isEmpty)
    }

    /// **ERRATA E38, at the row level.** An implementation that could not prove it counted everything
    /// hands back `nil`, and nil must draw nothing — not `0 visits`, which is a claim about a
    /// person's history that an unproven read is not entitled to make.
    ///
    /// The favourite clause survives, because it comes from a different fact that *was* proved.
    @Test("a record that could not be proved prints no tally, and does not print a zero")
    func anUnprovenRecordSaysNothing() {
        let unproven = Self.presentation([
            Self.entry(1, isFavorite: false, record: nil),
            Self.entry(2, isFavorite: true, record: nil)
        ]).rows

        #expect(unproven[0].subtitle == "", "an unproven read printed a tally")
        #expect(unproven[0].subtitle.contains("0") == false)
        #expect(unproven[1].subtitle == "Favorite")

        // And the proved-empty case is a different answer from the unproved one: a favourite with a
        // read behind it saying "nothing yet" draws the same line here, but the two arrive by
        // different routes and `.none` is the one that means zero.
        let proved = Self.presentation([Self.entry(3, isFavorite: false, record: GroveRecord.none)]).rows
        #expect(proved[0].subtitle == "")
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

    /// D1 on the strings this screen owns. The rows carry a tally now, argued at length in
    /// `GroveRecord` and held by the three tests above; **the screen's own sentences still carry no
    /// number at all**, which is the part of the blunt digit check that survives and should.
    ///
    /// A number in one of these would be a number about the grove rather than about a tree, and that
    /// is the line the tally must not cross.
    @Test("no sentence the Trees pill owns contains a number")
    func noCountsInTheTreesCopy() {
        let owned = [
            GroveCopy.treesEmptyState,
            GroveCopy.treesLoadFailed,
            GroveCopy.treesExplanation,
            GroveCopy.footnote
        ]
        for string in owned {
            #expect(
                string.rangeOfCharacter(from: .decimalDigits) == nil,
                "\(string) counts something on the screen whose footnote forbids it"
            )
        }
    }

    @Test("an empty grove of trees says so, and a full one does not")
    func emptyState() {
        #expect(Self.presentation([]).emptyState != nil)
        #expect(Self.presentation([Self.entry(1)]).emptyState == nil)
    }

    // MARK: - The tally, over a real database

    /// **Everything above this point is a double.** The clauses, the ordering, the nil case — all of
    /// it is asserted against `GroveEntry`s the test wrote, which proves the derivation and says
    /// nothing about where the numbers come from. The numbers come from SQL that unions four tables,
    /// filters on two owners and a tombstone column, and groups twice; that is the part with somewhere
    /// to hide a mistake, and it is the part `GrovePreviewAPI` cannot exercise.
    ///
    /// So this goes through `LocalAPI` against an actual store with actual contributions in it, the
    /// way `JournalPresentationTests.exportPayloadIsReal` does for the export.
    ///
    /// The fixture is built to fail four specific ways:
    /// - **three kinds against one tree**, so a `GROUP BY` that lost the kind column would collapse
    ///   them into one clause;
    /// - **two trees**, so a query missing its per-tree grouping would give both the same figures;
    /// - **a tombstoned visit**, which `deleted_at IS NULL` must exclude — a deleted contribution is
    ///   not something a person did that still stands;
    /// - **a tree with no contributions at all**, which must come back `.none` and draw nothing,
    ///   rather than being dropped from the grove or arriving as nil.
    @Test("the tally is what the database holds, counted by kind and by tree")
    @MainActor
    func theTallyComesFromTheStore() async throws {
        let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-0000000000C1")!
        let attribution = Attribution.anonymous(deviceID: deviceID)
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: deviceID)

        func addTree(_ latitude: Double) async throws -> UUID {
            try await api.addTree(
                TreeDraft(
                    coordinate: Coordinate(latitude: latitude, longitude: -122.4464),
                    photoLocalPath: "/tmp/cypress-grove-record-\(latitude).jpg",
                    attribution: attribution
                )
            ).id
        }

        // Far enough apart to clear the 10 m any-species proximity dedupe.
        let cypress = try await addTree(37.7761)
        let ginkgo = try await addTree(37.7801)

        try await store.queue.write { connection in
            let contributions = ContributionStore()
            for index in 0..<3 {
                try contributions.insert(
                    Visit(
                        treeID: cypress,
                        attribution: attribution,
                        capturedAt: Self.date(2026, 7, 10 + index)
                    ),
                    connection: connection
                )
            }
            try contributions.insert(
                CareEvent(
                    treeID: cypress,
                    attribution: attribution,
                    capturedAt: Self.date(2026, 7, 12),
                    actions: [.watered]
                ),
                connection: connection
            )
            // A visit that was taken back. It is a row in the table and it must not be counted.
            try contributions.insert(
                Visit(
                    treeID: cypress,
                    attribution: attribution,
                    capturedAt: Self.date(2026, 6, 1),
                    deletedAt: Self.date(2026, 6, 2)
                ),
                connection: connection
            )
            try contributions.insert(
                Visit(treeID: ginkgo, attribution: attribution, capturedAt: Self.date(2026, 7, 1)),
                connection: connection
            )
        }

        let grove = try await api.grove()
        let records = Dictionary(uniqueKeysWithValues: grove.map { ($0.treeID, $0.record) })

        #expect(records[cypress] == GroveRecord(visits: 3, careEvents: 1), "\(String(describing: records[cypress] ?? nil))")
        #expect(records[ginkgo] == GroveRecord(visits: 1))

        // And the sentence a reader sees, from the real read rather than from a fixture.
        let rows = GroveTreesPresentation(entries: grove).rows
        let cypressRow = try #require(rows.first { $0.treeID == cypress })
        #expect(cypressRow.subtitle == "3 visits · 1 care log")
    }

    /// A tree in the grove that has never been contributed to — a favourite, the second arm of
    /// `groveTreeIDs` — has **no key** in the records map, and that absence must read as `.none`
    /// rather than as nil. Nil means "this read could not answer"; this read answered.
    @Test("a favourite nobody has visited has a record, and it is empty")
    @MainActor
    func aFavouriteWithNoContributionsIsEmptyNotUnknown() async throws {
        let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-0000000000C2")!
        let attribution = Attribution.anonymous(deviceID: deviceID)
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: deviceID)

        let tree = try await api.addTree(
            TreeDraft(
                coordinate: Coordinate(latitude: 37.7841, longitude: -122.4464),
                photoLocalPath: "/tmp/cypress-grove-record-favourite.jpg",
                attribution: attribution
            )
        ).id
        try await store.queue.write { connection in
            try ContributionStore().applyFavoriteToggle(
                owner: FavoriteOwner(attribution),
                treeID: tree,
                clientUUID: UUID(),
                isFavorite: true,
                at: Self.date(2026, 7, 12),
                connection: connection
            )
        }

        let entry = try #require(try await api.grove().first { $0.treeID == tree })
        #expect(entry.record == GroveRecord.none, "an answered read came back as unknown")
        #expect(entry.record?.isEmpty == true)
        #expect(GroveTreesPresentation(entries: [entry]).rows[0].subtitle == "Favorite")
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
