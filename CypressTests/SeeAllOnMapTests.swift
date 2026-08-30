import Foundation
import Testing
@testable import Cypress

/// **`See them all on the map`** — the link the Journal tab's `Yours` segment draws, and the route
/// it takes (tester report F23).
///
/// The report is one sentence: *"let's add a link that says See them all on the map. When clicked it
/// takes you back to the map and shows only yours"*. Three separate things have to be true for that
/// sentence to be honest, and each is a different kind of failure:
///
/// 1. **The route arrives narrowed.** `AppRouter` had `goToMap()` and no way to say what the map
///    should show, so the destination existed and the argument did not.
/// 2. **The narrowing is escapable.** A map that opens filtered with no visible cause is ERRATA
///    E126's defect. The chip's own selected state and `Clear filters` are what answer it, and the
///    assertion here is that the value this route carries is one `MapFilter.isActive` reports —
///    which is the single condition `MapFilterChips` puts the way out on screen for.
/// 3. **`them` and `only yours` are the same set.** This is the one that decided *where the link
///    goes*, and it is the reason it is not on screen 08 — see `theMapsYoursIsNotTheGrovesList`.
///
/// The store-backed tests run against the real seed for `FavoriteRoundTripTests`' reason: every tree
/// a reader can reach is a seed row, and a test that never opens the seed cannot tell a query that
/// works from one that only works on the records this app added.
@Suite("Tester report F23 · See them all on the map")
struct SeeAllOnMapTests {

    private static let deviceID = UUID(uuidString: "F2300000-0000-4000-8000-0000000000F1")!

    private static func store() async throws -> CypressStore {
        let seedURL = try #require(SeedContractTests.seedURL, "no seed database; set CYPRESS_SEED_PATH")
        return try await CypressStore.inMemory(seedURL: seedURL)
    }

    /// Real tree uuids out of the seed, so nothing here contributes to an id that does not exist.
    private static func seedTrees(limit: Int, store: CypressStore) async throws -> [UUID] {
        try await store.queue.read { connection in
            let statement = try connection.cachedStatement("""
            SELECT uuid AS tree_uuid FROM \(SeedDatabase.schemaName).trees
             WHERE deleted_at IS NULL AND status = 'alive'
             ORDER BY id LIMIT :limit
            """)
            _ = try statement.bind([":limit": limit])
            return try statement.fetchAll { try $0.uuid("tree_uuid") }
        }
    }

    private static func attribution() -> Attribution {
        Attribution(userID: nil, deviceID: deviceID)
    }

    // MARK: - 1 · The route

    /// The link's destination, as `RootView` forms it.
    ///
    /// Everything `goToMap()` already guaranteed (ERRATA E151) still has to hold — a narrowed map
    /// behind a pushed screen or under a cover is the same invisible destination an unnarrowed one
    /// would be.
    @Test("the link lands on the map with the narrowing armed")
    @MainActor
    func theRouteArrivesNarrowed() {
        let router = AppRouter()
        router.tab = .journal
        router.push(.treeProfile(UUID()))
        router.present(.identify(nil))

        router.goToMap(showing: MapFilter(membership: .yours))

        #expect(router.tab == .map)
        #expect(router.path.isEmpty, "the map arrived behind \(router.path.count) pushed screens")
        #expect(router.sheet == nil, "a cover is still up over the map")
        #expect(router.pendingMapFilter == MapFilter(membership: .yours))
    }

    /// **The arming is a one-shot.** A filter that stayed here would re-narrow the map on every later
    /// return to the tab, so a reader who had cleared the chips would find them back with nothing on
    /// screen saying why.
    @Test("the narrowing is cleared by the screen that reads it")
    @MainActor
    func theArmingIsSpentOnce() {
        let router = AppRouter()
        router.goToMap(showing: MapFilter(membership: .yours))

        #expect(router.takePendingMapFilter() == MapFilter(membership: .yours))
        #expect(router.takePendingMapFilter() == nil, "the second reader got the same narrowing again")
        #expect(router.pendingMapFilter == nil)
    }

    /// Arriving at the map any *other* way must not pick up a narrowing somebody armed and abandoned.
    @Test("a plain tab switch disarms a narrowing nobody used")
    @MainActor
    func aPlainTabSwitchDisarms() {
        let router = AppRouter()
        router.goToMap(showing: MapFilter(membership: .yours))

        router.goToTab(.grove)

        #expect(router.pendingMapFilter == nil, "a narrowing survived a tab switch that did not want it")
    }

    /// `goToMap()` is unchanged: the visit flow's "Back to the map" (E151) still means the plain map.
    @Test("the way back from a visit arms nothing")
    @MainActor
    func theVisitFlowsWayBackIsUnnarrowed() {
        let router = AppRouter()
        router.goToMap()

        #expect(router.pendingMapFilter == nil, "finishing a visit narrowed the map")
        #expect(router.tab == .map)
    }

    // MARK: - 2 · The way out of it

    /// **A map that opens narrowed must say so and must be escapable.**
    ///
    /// `MapFilterChips` draws the `Clear filters` chip under exactly one condition —
    /// `MapFilter.isActive` — and draws `Yours` in its selected state under exactly one other, so
    /// this asserts the value the route carries satisfies both. A narrowing that arrived without
    /// them is E126's screen showing something other than what was asked for, with no way back.
    @Test("the narrowing this route carries is one the chip row draws and can clear")
    func theArrivedFilterIsVisibleAndClearable() {
        let arrived = MapFilter(membership: .yours)

        #expect(arrived.isActive, "the row would draw no Clear filters chip over this map")
        #expect(arrived.membership == .yours, "the Yours chip would not read as selected")

        // The chip is a toggle, and the row's one way out clears every dimension at once.
        #expect(MapFilter.all.isActive == false)
    }

    // MARK: - 3 · `them` and `only yours` are the same trees

    /// **The link cannot hide a row the reader was just looking at.**
    ///
    /// The journal is read from `visits`, `observations`, `measurements` and `care_events`
    /// (`ContributionStore.journal`); screen 01's `Yours` is read from those same four plus
    /// `community_trees` (`contributedTreeIDs`). So the map is a superset of what this list names,
    /// and `See them all` cannot drop anything — which is the entire argument for putting the link
    /// on this screen. One row of each kind, because a proof over one table would pass for a query
    /// that had lost the other three.
    @Test("every tree the journal names is under the map's Yours")
    func theMapCannotHideARowTheJournalDrew() async throws {
        let store = try await Self.store()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let trees = try await Self.seedTrees(limit: 4, store: store)
        let moment = Date()

        try await store.queue.write { connection in
            let contributions = ContributionStore()
            _ = try contributions.insert(
                Visit(treeID: trees[0], attribution: Self.attribution(), capturedAt: moment),
                connection: connection
            )
            _ = try contributions.insert(
                TreeObservation(
                    treeID: trees[1], attribution: Self.attribution(), capturedAt: moment
                ),
                connection: connection
            )
            _ = try contributions.insert(
                TreeMeasurement.dbh(
                    treeID: trees[2],
                    attribution: Self.attribution(),
                    capturedAt: moment,
                    quantity: Quantity(value: 30, unit: .centimeters, method: .tape)
                ),
                connection: connection
            )
            _ = try contributions.insert(
                CareEvent(
                    treeID: trees[3],
                    attribution: Self.attribution(),
                    capturedAt: moment,
                    actions: [.watered]
                ),
                connection: connection
            )
        }

        let drawn = Set(try await api.journal(cursor: nil, limit: 50).items.map(\.treeID))
        #expect(drawn.count == 4, "the journal drew \(drawn.count) trees, not the four just written")

        let yours = try await api.mapMembership(.yours)
        let hidden = drawn.subtracting(yours)
        #expect(
            hidden.isEmpty,
            "\(hidden.count) trees the journal drew are not on the map the link opens: \(hidden)"
        )
    }

    /// **Why the link is not on screen 08's `Trees` pill**, which is the other list a reader could
    /// say `them` about.
    ///
    /// The grove is `groveTreeIDs` — visits **and favorites** — and `Yours` has no favorites arm at
    /// all, because a bookmark is not a contribution (RULINGS R23, `MapMembership`). A tree somebody
    /// only hearted is therefore in the grove and not on the map, so the same sentence on that
    /// screen would drop rows the reader could still see.
    ///
    /// This is a **fact about the two queries as they stand**, asserted so that it is a decision
    /// somebody has to revisit rather than one that quietly rots: if the two sets are ever
    /// reconciled, this test fails and the placement is open again.
    @Test("a favorited tree is in the grove and is not under the map's Yours")
    func theMapsYoursIsNotTheGrovesList() async throws {
        let store = try await Self.store()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let hearted = try await Self.seedTrees(limit: 1, store: store)[0]

        try await store.queue.write { connection in
            _ = try ContributionStore().applyFavoriteToggle(
                owner: .device(Self.deviceID),
                treeID: hearted,
                clientUUID: UUID(),
                isFavorite: true,
                at: Date(),
                connection: connection
            )
        }

        let grove = Set(try await api.grove().map(\.treeID))
        #expect(grove.contains(hearted), "a favorited tree did not reach the grove's Trees pill")

        let yours = try await api.mapMembership(.yours)
        #expect(
            !yours.contains(hearted),
            """
            a favorite now reaches the map's Yours. The two sets have been reconciled, which \
            removes the reason `See them all on the map` is not on screen 08 — reopen the placement.
            """
        )
    }

    // MARK: - 4 · Where the link draws

    /// **Only over a list**, which is `TreeProfilePresentation.offersActivityLink`'s rule: a link
    /// drawn over an empty journal is a door onto an empty map, and screen 01 deliberately says
    /// nothing at all to explain one (RULINGS R41).
    @Test("the link is offered over a journal with rows and withheld over one without")
    func theLinkIsOnlyOfferedOverAList() {
        let moment = Date()
        let populated = JournalPresentation(
            entries: [
                JournalEntry(
                    id: UUID(),
                    kind: .observation,
                    treeID: UUID(),
                    treeDisplayName: "London Plane",
                    capturedAt: moment,
                    summary: "alive"
                )
            ],
            nextCursor: nil,
            now: moment
        )
        #expect(populated.offersMapLink, "a journal with a row offered no way onto the map")

        let empty = JournalPresentation(entries: [], nextCursor: nil, now: moment)
        #expect(!empty.offersMapLink, "an empty journal offered a link onto an empty map")
    }

    /// The tester's own words, kept verbatim, and carrying no number (D1 — the same check
    /// `JournalPresentationTests.noCountsAnywhere` makes over the rest of this type).
    @Test("the link says what the report asked it to say")
    func theCopyIsTheReports() {
        #expect(JournalCopy.seeAllOnMap == "See them all on the map")
    }
}
