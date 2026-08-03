import Foundation
import Testing
@testable import Cypress

/// **The dropdown under C20, and the one thing it must never do** (task #109, ruling R25).
///
/// `MapSearchTests` proves the map narrows to the right trees. This proves the *list* offers the
/// right species and — the half that is easy to get wrong and impossible to see — that it never
/// presents its own six rows as the whole of what matched.
///
/// ERRATA E38 is the entry: a page's size is not a total. It became the ordinary case here rather
/// than an edge one when task #108 made the catalog match a word anywhere in either name, so the
/// 100-species cap that used to need a genus to reach now falls out of a single letter — `a`
/// prefix-matched 97 species and *contains* in 555. Every assertion about `Remainder` below is that
/// sentence, made into something that can fail.
///
/// The seed-backed tests are last and are the ones that would catch a change in the catalog itself;
/// the value tests above them need no database and pin the arithmetic.
@Suite("Map search suggestions")
struct MapSuggestionTests {

    private static let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-0000000000E2")!

    /// The Mission block `MapSearchTests` uses, so both files talk about the same map.
    private static let bounds = BoundingBox(
        minLatitude: 37.7835, maxLatitude: 37.7862,
        minLongitude: -122.4232, maxLongitude: -122.4198
    )

    private static func store() async throws -> CypressStore {
        let seedURL = try #require(SeedContractTests.seedURL, "no seed database; set CYPRESS_SEED_PATH")
        return try await CypressStore.inMemory(seedURL: seedURL)
    }

    /// A species that is only a name, which is all this file needs of one.
    private static func species(_ common: String, _ latin: String) throws -> Species {
        try Species(scientificName: latin, commonName: common, leafRetention: nil)
    }

    /// `n` distinct species, for counting.
    private static func many(_ n: Int) throws -> [Species] {
        try (0..<n).map { try species("Common \($0)", "Latinus \($0)") }
    }

    // MARK: - What the list is

    @Test("a query the catalog has nothing for offers no rows")
    func noMatchesIsNoList() throws {
        #expect(MapSuggestions(matches: []) == .off)
        #expect(MapSuggestions(matches: []).rows.isEmpty)
    }

    @Test("a handful of matches are all offered, and the list says nothing about a remainder")
    func aShortAnswerIsTheWholeAnswer() throws {
        let suggestions = MapSuggestions(matches: try Self.many(3))
        guard case let .listing(listing) = suggestions else {
            Issue.record("three matches produced \(suggestions)")
            return
        }
        #expect(listing.rows.count == 3)
        #expect(listing.remainder == .none)
        // The only silence this file permits: the list *is* the answer, so there is nothing to add.
        #expect(MapSuggestionCopy.remainder(listing.remainder, shown: 3) == nil)
    }

    @Test("exactly a listful is still the whole answer")
    func exactlyTheRowLimitIsNotAPage() throws {
        let suggestions = MapSuggestions(matches: try Self.many(MapSuggestions.rowLimit))
        guard case let .listing(listing) = suggestions else {
            Issue.record("a full list produced \(suggestions)")
            return
        }
        #expect(listing.rows.count == MapSuggestions.rowLimit)
        #expect(listing.remainder == .none, "a list that showed everything claimed a remainder")
    }

    /// **E38, the countable half.** More matched than fits, but the catalog counted them all, so the
    /// total is a fact and the sentence may print it.
    @Test("more matches than rows are counted, and the count is exact when the catalog counted it")
    func aRemainderTheCatalogCounted() throws {
        let suggestions = MapSuggestions(matches: try Self.many(21))
        guard case let .listing(listing) = suggestions else {
            Issue.record("21 matches produced \(suggestions)")
            return
        }
        #expect(listing.rows.count == MapSuggestions.rowLimit)
        #expect(listing.remainder == .exactly(21 - MapSuggestions.rowLimit))
        #expect(
            MapSuggestionCopy.remainder(listing.remainder, shown: listing.rows.count)
                == "Showing 6 of 21 matching species. Keep typing to narrow it."
        )
    }

    /// **E38, the half this ticket was most likely to get wrong.**
    ///
    /// The catalog's own answer was a page, so the app does not know the total and may not print
    /// one. `atLeast` is the weaker claim and the only true one: "at least 100" is true when exactly
    /// 100 matched *and* when 555 did, which is the property `MapSearch.Narrowed.isTruncated` already
    /// picks for the same reason one level up.
    @Test("a full page from the catalog is reported as a floor, never as a total")
    func aRemainderNobodyCounted() throws {
        let suggestions = MapSuggestions(matches: try Self.many(MapSearch.speciesLimit))
        guard case let .listing(listing) = suggestions else {
            Issue.record("a full page produced \(suggestions)")
            return
        }
        #expect(listing.rows.count == MapSuggestions.rowLimit)
        #expect(listing.remainder == .atLeast(MapSearch.speciesLimit - MapSuggestions.rowLimit))

        let sentence = try #require(
            MapSuggestionCopy.remainder(listing.remainder, shown: listing.rows.count)
        )
        #expect(
            sentence == "Showing 6 of at least 100 matching species. Keep typing to narrow it.",
            "the sentence for a page was “\(sentence)”"
        )
        // Stated twice on purpose. The exact string above is a copy assertion and will be edited by
        // whoever rewrites the copy; this is the *rule*, and it must survive that edit.
        #expect(
            sentence.contains("at least"),
            "a page of the catalog was described without saying it was a page: “\(sentence)”"
        )
    }

    /// The two remainders are different sentences rather than one sentence with a different number,
    /// which is the whole claim: a reader must be able to tell a counted total from a floor.
    @Test("a counted remainder and an uncounted one do not read alike")
    func theTwoRemaindersAreDistinguishable() {
        let counted = MapSuggestionCopy.remainder(.exactly(94), shown: 6)
        let floored = MapSuggestionCopy.remainder(.atLeast(94), shown: 6)
        #expect(counted != floored)
        #expect(counted == "Showing 6 of 100 matching species. Keep typing to narrow it.")
        #expect(floored == "Showing 6 of at least 100 matching species. Keep typing to narrow it.")
    }

    // MARK: - What a row says

    /// D15's rule — the common name is the fallback display everywhere — and the other way round for
    /// the 59 seeded species that have no common name at all (E9). A row that read "Common name, "
    /// with nothing after the comma is what this stops.
    @Test("a row names both names, and a species with only one name says only that one")
    func rowLabels() throws {
        let both = try Self.species("Monterey Cypress", "Hesperocyparis macrocarpa")
        #expect(MapSuggestionCopy.name(both) == "Monterey Cypress")
        #expect(MapSuggestionCopy.latin(both) == "Hesperocyparis macrocarpa")
        #expect(MapSuggestionCopy.rowLabel(both) == "Monterey Cypress, Hesperocyparis macrocarpa")

        let latinOnly = try Species(
            scientificName: "Quercus agrifolia", commonName: "", leafRetention: nil
        )
        #expect(MapSuggestionCopy.name(latinOnly) == "Quercus agrifolia")
        #expect(MapSuggestionCopy.latin(latinOnly) == nil)
        #expect(
            MapSuggestionCopy.rowLabel(latinOnly) == "Quercus agrifolia",
            "a species with no common name announced a dangling comma"
        )
    }

    /// What a VoiceOver reader is told arrived under the field they are still typing into.
    @Test("the list announces how many rows it dropped, and counts one correctly")
    func listLabel() {
        #expect(MapSuggestionCopy.listLabel(1) == "1 species suggestion")
        #expect(MapSuggestionCopy.listLabel(6) == "6 species suggestions")
    }

    // MARK: - The typing path, against the seed

    /// The owner's own query, through the model they type into: `cypress` drops a list, and every row
    /// on it is a species the map is simultaneously narrowed to.
    ///
    /// That last clause is the invariant worth having. The list and the narrowing are two readings of
    /// one `searchSpecies` call; a later refactor that gave the list its own query at its own limit
    /// would let the dropdown offer a species the map is not showing, and nothing else in the suite
    /// would notice.
    @MainActor
    @Test("typing drops a list, and every row on it is a species the map narrowed to")
    func typingDropsAList() async throws {
        let store = try await Self.store()
        let model = MapModel(api: LocalAPI(store: store, deviceID: Self.deviceID))

        model.cameraDidChange(bounds: Self.bounds, zoom: 16)
        model.searchText = "cypress"
        try await Self.waitUntil { !model.suggestions.rows.isEmpty }

        let rows = model.suggestions.rows
        #expect(rows.count >= 2, "“cypress” offered \(rows.count) suggestions")
        #expect(
            rows.contains { $0.commonName == "Monterey Cypress" },
            "the dropdown missed Monterey Cypress: \(rows.map(\.commonName))"
        )
        guard case let .narrowed(narrowed) = model.search else {
            Issue.record("“cypress” left the model at \(model.search)")
            return
        }
        #expect(
            rows.allSatisfy { narrowed.speciesIDs.contains($0.id) },
            "the dropdown offered a species the map is not narrowed to"
        )
    }

    /// A word nothing matches drops no list at all — and the screen is not silent about it, because
    /// `MapSearchCopy.status` is the one sentence for this state and it is already on screen (E126,
    /// R25). Asserted here so that the two halves are pinned together: an empty list is only
    /// acceptable while that line exists.
    @MainActor
    @Test("a word no species matches drops no list, and the status line is what says why")
    func nothingMatchesDropsNothing() async throws {
        let store = try await Self.store()
        let model = MapModel(api: LocalAPI(store: store, deviceID: Self.deviceID))

        model.cameraDidChange(bounds: Self.bounds, zoom: 16)
        model.searchText = "zzzznotatree"
        try await Self.waitUntil { model.search.isActive }

        #expect(model.suggestions == .off)
        #expect(
            MapSearchCopy.status(for: model.search) == "No species matches “zzzznotatree”",
            "the list drew nothing and so did the sentence that was supposed to explain it"
        )
    }

    /// **The cap, reached the way a person reaches it.** One letter, against the real catalog.
    ///
    /// E165 measured this: `a` prefix-matched 97 species and contains-matched 555. So the dropdown's
    /// six rows are six of at least a hundred, and the only defensible thing it can say is so.
    @MainActor
    @Test("one letter against the real catalog is a page, and the list says it is")
    func oneLetterIsAPage() async throws {
        let store = try await Self.store()
        let model = MapModel(api: LocalAPI(store: store, deviceID: Self.deviceID))

        model.cameraDidChange(bounds: Self.bounds, zoom: 16)
        model.searchText = "a"
        try await Self.waitUntil { !model.suggestions.rows.isEmpty }

        guard case let .listing(listing) = model.suggestions else {
            Issue.record("“a” produced \(model.suggestions)")
            return
        }
        #expect(listing.rows.count == MapSuggestions.rowLimit)
        #expect(
            listing.remainder == .atLeast(MapSearch.speciesLimit - MapSuggestions.rowLimit),
            "“a” matched a full page of the catalog and the list called it \(listing.remainder)"
        )
        let sentence = try #require(
            MapSuggestionCopy.remainder(listing.remainder, shown: listing.rows.count)
        )
        #expect(sentence.contains("at least"), "“a” was reported as an exact total: “\(sentence)”")
    }

    /// **Choosing a row narrows to that species, not to what its name matches.**
    ///
    /// This is the ticket's own sentence — "tapping one selects that species rather than leaving the
    /// raw typed string in place" — and it is the assertion a wiring mistake fails. Typing `cypress`
    /// narrows to every Cypress; picking one of them must leave exactly one species behind, and the
    /// field must show what was picked.
    @MainActor
    @Test("choosing a suggestion narrows the map to that one species and puts its name in the field")
    func choosingASuggestionPins() async throws {
        let store = try await Self.store()
        let model = MapModel(api: LocalAPI(store: store, deviceID: Self.deviceID))

        model.cameraDidChange(bounds: Self.bounds, zoom: 16)
        model.searchText = "cypress"
        try await Self.waitUntil { !model.suggestions.rows.isEmpty }

        guard case let .narrowed(before) = model.search else {
            Issue.record("“cypress” left the model at \(model.search)")
            return
        }
        try #require(before.speciesIDs.count > 1, "“cypress” narrowed to one species; nothing to pin")

        let chosen = try #require(
            model.suggestions.rows.first { $0.commonName == "Monterey Cypress" },
            "Monterey Cypress was not on the list to choose"
        )
        model.chooseSuggestion(chosen)

        #expect(model.searchText == "Monterey Cypress", "the field kept the raw query after a choice")
        #expect(model.chosenSpecies?.id == chosen.id)
        #expect(model.suggestions == .off, "the list stayed open over its own answer")
        guard case let .narrowed(after) = model.search else {
            Issue.record("choosing a suggestion left the model at \(model.search)")
            return
        }
        #expect(
            after.speciesIDs == [chosen.id],
            "choosing Monterey Cypress left the map on \(after.speciesIDs.count) species"
        )
        #expect(!after.isTruncated, "one chosen species was reported as a page")

        // …and it stays chosen. A re-resolution of the field's text would arrive after the debounce
        // and could widen the map back out under a reader who has already chosen.
        try await Task.sleep(for: MapModel.searchDebounce * 3)
        guard case let .narrowed(settled) = model.search else {
            Issue.record("the choice decayed to \(model.search)")
            return
        }
        #expect(
            settled.speciesIDs == [chosen.id],
            "the choice was re-resolved from the field's text and widened to \(settled.speciesIDs.count) species"
        )
    }

    /// The other half of pinning: a keystroke takes it back. Deleting a letter from a chosen name
    /// must stop the map claiming the choice, or the field and the map say different things.
    @MainActor
    @Test("typing after choosing releases the choice")
    func typingReleasesTheChoice() async throws {
        let store = try await Self.store()
        let model = MapModel(api: LocalAPI(store: store, deviceID: Self.deviceID))

        model.cameraDidChange(bounds: Self.bounds, zoom: 16)
        model.searchText = "cypress"
        try await Self.waitUntil { !model.suggestions.rows.isEmpty }
        let chosen = try #require(model.suggestions.rows.first)
        model.chooseSuggestion(chosen)
        try #require(model.chosenSpecies != nil)

        model.searchText = "cypre"
        #expect(model.chosenSpecies == nil, "the map is still pinned to a species the field no longer names")
        try await Self.waitUntil { !model.suggestions.rows.isEmpty }
        #expect(!model.suggestions.rows.isEmpty, "typing after a choice never re-opened the list")
    }

    /// Clearing the field takes the list with it, on the frame it is cleared rather than a debounce
    /// later — the same rule `MapModel.searchDidChange` already keeps for the narrowing itself.
    @MainActor
    @Test("clearing the field closes the list immediately")
    func clearingClosesTheList() async throws {
        let store = try await Self.store()
        let model = MapModel(api: LocalAPI(store: store, deviceID: Self.deviceID))

        model.cameraDidChange(bounds: Self.bounds, zoom: 16)
        model.searchText = "cypress"
        try await Self.waitUntil { !model.suggestions.rows.isEmpty }

        model.searchText = ""
        #expect(model.suggestions == .off, "clearing the field left the dropdown open")
        #expect(model.chosenSpecies == nil)
    }

    /// `MapSearchTests`' waiter, for the same reason: the debounces are tuned for a thumb, and a test
    /// that pinned them would fail the day they were retuned.
    @MainActor
    private static func waitUntil(
        _ condition: () -> Bool,
        timeout: Duration = .seconds(20)
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(condition(), "the model never settled within \(timeout)")
    }
}
