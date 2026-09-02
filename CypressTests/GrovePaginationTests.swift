//
//  GrovePaginationTests.swift
//  CypressTests
//
//  **A page boundary is a place a row can disappear**, and this project has already lost rows to
//  one: the journal's cursor carried a bare `captured_at`, every contribution sharing a timestamp
//  with the last row of a page was asked for with a strict `<`, and the rest of that run was
//  returned on no page at all (`JournalPaginationTieTests`, `AppSchema` v19). Screen 08's grove has
//  the same hazard twice over — trees visited in the same instant, and the entire run of trees
//  nobody has visited, which share one `last_visited` of NULL — so it gets the same total order and
//  the same proof.
//
//  The proof is a comparison and not a description: every page size below concatenates its pages
//  and holds the result against `LocalAPI.grove()`, the unbounded read, element for element.
//

import Foundation
import Testing
@testable import Cypress

@Suite("My Grove · the pages are the grove, cut")
struct GrovePaginationTests {

    private static let deviceID = UUID(uuidString: "9E00B47C-0000-4000-8000-0000000002F0")!

    /// A tree no inventory holds. `grove()` drops its row, which is what makes the id count and the
    /// entry count differ — see `theCursorIsDecidedByIdsAndNotByEntries`.
    private static let phantom = UUID(uuidString: "F0000000-0000-4000-8000-0000000002F0")!

    /// The instant the tie block shares. A fixed date so a failure names the same rows twice.
    private static let tieInstant = Date(timeIntervalSince1970: 1_780_000_000)

    // MARK: - The fixture

    /// A grove with all three shapes a boundary can land inside.
    ///
    /// - `visited`: trees with distinct visit times, newest first;
    /// - `tied`: **six** trees sharing one `captured_at`, sitting where a page of 7, of 3 and of 1
    ///   all cut inside them;
    /// - `favoritedOnly`: twelve trees with no visit at all, which share a `last_visited` of NULL
    ///   and are therefore one enormous tie of their own;
    /// - one visit to `phantom`, which resolves nowhere.
    private static func seededGrove() async throws -> (api: LocalAPI, store: CypressStore) {
        let url = try #require(InventoryContractTests.seedURL, "no seed database; set CYPRESS_SEED_PATH")
        let store = try await CypressStore.inMemory(seedURL: url)
        let api = LocalAPI(store: store, deviceID: deviceID)

        let candidates = try await api.treesNear(
            Coordinate(latitude: 37.7694, longitude: -122.4862), radiusM: 1_200, limit: 200
        )
        try #require(
            candidates.count >= 52,
            "the seed gave \(candidates.count) trees near the fixture center; the grove needs 52"
        )
        let ids = candidates.prefix(52).map(\.tree.id)
        let visited = Array(ids[0..<34])
        let tied = Array(ids[34..<40])
        let favoritedOnly = Array(ids[40..<52])

        let attribution = await api.attribution
        try await store.queue.write { connection in
            let contributions = ContributionStore()
            for (offset, tree) in visited.enumerated() {
                try contributions.insert(
                    Visit(
                        treeID: tree,
                        attribution: attribution,
                        capturedAt: Self.tieInstant.addingTimeInterval(Double(60 * (offset + 1)))
                    ),
                    connection: connection
                )
            }
            for tree in tied {
                try contributions.insert(
                    Visit(treeID: tree, attribution: attribution, capturedAt: Self.tieInstant),
                    connection: connection
                )
            }
            try contributions.insert(
                Visit(treeID: Self.phantom, attribution: attribution, capturedAt: Self.tieInstant),
                connection: connection
            )
            for tree in favoritedOnly {
                try contributions.applyFavoriteToggle(
                    owner: .device(Self.deviceID),
                    treeID: tree,
                    clientUUID: UUID(),
                    isFavorite: true,
                    at: Self.tieInstant,
                    connection: connection
                )
            }
        }
        return (api, store)
    }

    /// Every page, walked to the end, concatenated. The walk is bounded so a cursor that never
    /// retires fails as a test rather than as a hang.
    private static func allPages(
        _ api: LocalAPI, size: Int
    ) async throws -> (entries: [GroveEntry], pages: Int) {
        var entries: [GroveEntry] = []
        var cursor: String?
        var pages = 0
        while pages < 200 {
            let page = try await api.grove(cursor: cursor, limit: size)
            pages += 1
            entries += page.items
            guard let next = page.nextCursor else { return (entries, pages) }
            cursor = next
        }
        Issue.record("the cursor never retired after 200 pages of \(size)")
        return (entries, pages)
    }

    // MARK: - The instrument, calibrated before it is believed

    /// **The Swift order key says what the query says.**
    ///
    /// `GroveOrderKey` is a mirror of `ContributionStore.groveOrderSQL`, and `GroveModel` and
    /// `RoutedAPI.refreshedGrove` both decide page boundaries with it. A mirror that has drifted
    /// puts a boundary in a different place from the query that produced it, which shows a row
    /// twice or not at all — and it would drift silently, because both orders look plausible.
    ///
    /// So this is the calibration for every test below: sort the unbounded read's own answer by the
    /// Swift key and require it to be the answer already in hand.
    @Test("the Swift order key agrees with the query, element for element")
    func theSwiftOrderKeyAgreesWithTheQuery() async throws {
        let (api, _) = try await Self.seededGrove()
        let grove = try await api.grove()

        try #require(grove.count == 52, "the fixture produced \(grove.count) entries, not 52")
        try #require(
            grove.filter { $0.lastVisitedAt == nil }.count == 12,
            "the fixture has no run of never-visited trees, so the NULL half of the order is untested"
        )

        // **Reversed before it is re-sorted, and the test was vacuous without it.** The first
        // draft sorted `grove` itself — already in the query's order — and Swift's sort leaves an
        // ordered array alone, so a comparator that had *forgotten* the tie-break entirely came
        // back with the right answer and the suite stayed green. Measured: deleting `left.tree <
        // right.tree` from `GroveOrderKey` passed all seven tests in this file. Reversing first
        // means every tie has to be put back deliberately.
        let resorted = Array(grove.reversed()).sorted { $0.orderKey > $1.orderKey }
        let queryOrder = grove.map(\.treeID)
        let keyOrder = resorted.map(\.treeID)
        let firstDisagreement: String = keyOrder.indices
            .first { keyOrder[$0] != queryOrder[$0] }
            .map(String.init) ?? "none"
        #expect(
            keyOrder == queryOrder,
            """
            `GroveOrderKey` and `ContributionStore.groveOrderSQL` disagree about the order of this \
            grove; first disagreement at index \(firstDisagreement). Every cursor in this file is \
            derived from one of the two and handed to the other
            """
        )
    }

    // MARK: - The gate

    /// **Concatenating the pages is the grove**, at four page sizes, one of which cuts inside the
    /// tie and one of which cuts inside the never-visited run.
    @Test(
        "pages concatenate to the unpaginated read",
        arguments: [1, 3, 7, 50]
    )
    func pagesConcatenateToTheWholeGrove(size: Int) async throws {
        let (api, _) = try await Self.seededGrove()
        let whole = try await api.grove()
        try #require(whole.count == 52, "the fixture produced \(whole.count) entries, not 52")

        let (paged, pages) = try await Self.allPages(api, size: size)

        try #require(
            pages > 1,
            "a page size of \(size) read the whole grove in one page; nothing was paginated"
        )
        #expect(
            paged.map(\.treeID) == whole.map(\.treeID),
            """
            \(pages) pages of \(size) returned \(paged.count) trees against the unbounded read's \
            \(whole.count). Dropped: \
            \(Set(whole.map(\.treeID)).subtracting(paged.map(\.treeID)).count). Repeated: \
            \(paged.count - Set(paged.map(\.treeID)).count)
            """
        )
        #expect(
            paged.count == Set(paged.map(\.treeID)).count,
            "a tree was returned on two pages of \(size)"
        )
    }

    /// The tie on its own, named, because a size that cuts inside it is the whole reason the order
    /// carries the tree's uuid. Six trees share one instant and a page of 37 ids ends among them.
    @Test("a page boundary inside a run of trees visited in one instant loses none of them")
    func aTieStraddlingAPageBoundaryLosesNothing() async throws {
        let (api, _) = try await Self.seededGrove()
        let whole = try await api.grove()
        let tied = whole.filter { $0.lastVisitedAt == Self.tieInstant }
        try #require(tied.count == 6, "the fixture's tie is \(tied.count) trees, not 6")

        let first = try await api.grove(cursor: nil, limit: 37)
        // The boundary has to fall *inside* the tie, or this test is about an ordinary page. It is
        // asserted as a range rather than an exact count because which of the seven tied ids fall
        // before the cut is decided by their uuids, which are the seed's and not this file's.
        let onPageOne = first.items.filter { $0.lastVisitedAt == Self.tieInstant }.count
        try #require(
            (1..<6).contains(onPageOne),
            """
            a page of 37 ended with \(onPageOne) of the 6 tied trees on it, so the boundary is not \
            inside the tie and this test is not testing the boundary
            """
        )
        let cursor = try #require(first.nextCursor)
        let second = try await api.grove(cursor: cursor, limit: 37)

        let across = (first.items + second.items).filter { $0.lastVisitedAt == Self.tieInstant }
        #expect(
            Set(across.map(\.treeID)) == Set(tied.map(\.treeID)),
            "\(across.count) of the 6 tied trees survived the boundary"
        )
        #expect(across.count == 6, "a tied tree was drawn twice: \(across.count) rows for 6 trees")
    }

    /// **A page that read a full set of ids carries a cursor even when some of them produced no
    /// entry**, which is the rule `LocalAPI.grove(cursor:limit:)` states and the reason the cursor
    /// is decided by `rows` rather than by `entries`. Deciding on the entries would stop the list
    /// at the first tree the inventories do not hold.
    @Test("an unresolvable row shortens a page without ending the list")
    func theCursorIsDecidedByIdsAndNotByEntries() async throws {
        let (api, _) = try await Self.seededGrove()

        // The phantom's visit shares the tie instant, so it sits inside the tie block — rows 35
        // through 41 of the ordering. A page of 41 ids therefore contains it.
        let page = try await api.grove(cursor: nil, limit: 41)
        #expect(
            page.items.count == 40,
            """
            a page of 41 ids returned \(page.items.count) entries; the fixture's one unresolvable \
            visit should have cost exactly one
            """
        )
        #expect(
            page.nextCursor != nil,
            "a short page ended the list — the cursor is being decided by entries, not by ids"
        )

        let (paged, _) = try await Self.allPages(api, size: 41)
        let whole = try await api.grove()
        #expect(paged.map(\.treeID) == whole.map(\.treeID))
    }

    /// The cursor's wire form, both halves, including the one the journal's cannot have: a tree
    /// with no visit, whose first half is empty.
    @Test("the cursor round-trips, with and without a visit behind it")
    func theCursorRoundTrips() throws {
        let tree = UUID()
        let dated = ContributionStore.GroveCursor(lastVisitedAt: Self.tieInstant, treeID: tree)
        let undated = ContributionStore.GroveCursor(lastVisitedAt: nil, treeID: tree)

        #expect(ContributionStore.GroveCursor(string: dated.string) == dated)
        #expect(
            ContributionStore.GroveCursor(string: undated.string) == undated,
            """
            a cursor for a tree nobody has visited did not survive its own wire form: \
            \(undated.string). Everything past the first never-visited tree would be unreachable
            """
        )
        #expect(ContributionStore.GroveCursor(string: "not a cursor") == nil)
    }

    /// **The protocol default pages too**, which is worth its own assertion because every preview
    /// and most doubles reach it and because it is the thing the census gate exists to keep off
    /// `LocalAPI`: it is *correct* and it builds the whole grove to answer a page.
    ///
    /// It is checked against the real read rather than against itself: the same grove, walked
    /// through the default, has to come back as the same sequence `LocalAPI`'s own pages produce.
    @Test("the protocol default cuts the same pages the bounded query does")
    func theProtocolDefaultCutsTheSamePages() async throws {
        let (api, _) = try await Self.seededGrove()
        let whole = try await api.grove()
        let paging = WholeGroveDouble(whole)

        var entries: [GroveEntry] = []
        var cursor: String?
        for _ in 0..<40 {
            let page = try await paging.grove(cursor: cursor, limit: 7)
            entries += page.items
            guard let next = page.nextCursor else { break }
            cursor = next
        }
        #expect(
            entries.map(\.treeID) == whole.map(\.treeID),
            "the default returned \(entries.count) of \(whole.count) trees"
        )
    }

    /// The paged read and the unbounded read answer the same *content*, not merely the same ids —
    /// the names, the tallies and the favorite bits come from one projection body and this is what
    /// says so.
    @Test("a paged entry is the entry the unbounded read built")
    func aPagedEntryIsTheUnpaginatedEntry() async throws {
        let (api, _) = try await Self.seededGrove()
        let whole = try await api.grove()
        let (paged, _) = try await Self.allPages(api, size: 9)

        try #require(paged.count == whole.count)
        #expect(paged == whole, "the projection differs between the paged and unbounded reads")
    }
}

/// A grove that answers whole, so `grove(cursor:limit:)` reaches the protocol default. Every other
/// requirement is a stub: this exists to exercise one extension member.
private struct WholeGroveDouble: CypressAPI {
    let entries: [GroveEntry]

    init(_ entries: [GroveEntry]) { self.entries = entries }

    func grove() async throws -> [GroveEntry] { entries }

    func mapContent(in viewport: MapViewport) async throws -> MapContent { .pins([]) }
    func treesNear(_ c: Coordinate, radiusM: Double, limit: Int) async throws -> [NearbyTree] { [] }
    func treeProfile(id: UUID) async throws -> TreeProfile { throw APIError.notFound }
    func addTree(_ draft: TreeDraft) async throws -> Tree { throw APIError.forbidden }
    func species(id: UUID) async throws -> Species { throw APIError.notFound }
    func searchSpecies(query: String, limit: Int) async throws -> [Species] { [] }
    func sync(_ items: [OutboxItem]) async throws -> [SyncResult] { [] }
    func beginPhotoUpload(_ r: PhotoUploadRequest) async throws -> PhotoUploadTicket {
        throw APIError.forbidden
    }
    func uploadPhoto(at localPath: String, ticket: PhotoUploadTicket) async throws {}
    func journal(cursor: String?, limit: Int) async throws -> Page<JournalEntry> { Page(items: []) }
    func claimDevice(deviceUUID: UUID, userID: UUID) async throws {}
    func deleteAccount(_ choice: AccountDeletionChoice) async throws -> AccountDeletion.Outcome {
        throw APIError.unauthorized
    }
    func logHazardRedirect(_ event: HazardRedirectEvent) async throws {}
    func exportLatest(_ format: ExportFormat) async throws -> Data { Data() }
}
