import Foundation
import Testing
@testable import Cypress

/// **All and only.** The owner asked that typing a tree name bring up all and only those trees, and
/// a map with fewer pins on it proves nothing about *which* pins — so every claim here is checked
/// against a second, independent read of the seed rather than against the map's own arithmetic.
///
/// The read-back is deliberately written as raw SQL that shares no code with `TreeQueries`: it names
/// the species by uuid, joins it itself, and takes the bounding box literally. If the map's predicate
/// and the map's grid ever disagree with what is actually in the box, these fail.
///
/// ── Why the grid is the whole difficulty ─────────────────────────────────────────────────────────
/// `TreeQueries.pins` grids the viewport into 44 pt cells and returns one tree per occupied cell once
/// the un-thinned answer would overrun `pinLimit` (ERRATA E130). Filter *after* that and both halves
/// of the ask break at once: the cell's winner is whichever tree holds `MIN(rowid)`, which need not be
/// a match, and six matches sharing a cell come back as at most one. The fix is that the predicate
/// goes into the cell query too — so the count that decides whether to thin is the count of matches —
/// and `narrowedViewportIsExactlyTheSeed` is the assertion that it worked.
@Suite("Map species search")
struct MapSearchTests {

    private static let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-0000000000E1")!

    /// `Platanus x hispanica`, 11,851 trees citywide — the densest species in the seed and therefore
    /// the hardest case for "all", because it is the one most able to overrun the pin budget.
    private static let londonPlane = UUID(uuidString: "7d22dcda-354d-5f7d-9be0-3739ea8c6688")!
    /// `Lophostemon confertus`, 10,215 citywide. Used as the tree that must *not* come back.
    private static let brisbaneBox = UUID(uuidString: "ea4f4595-b255-56a6-bfe9-b57d41267457")!

    /// A block of the Mission dense enough in London Planes to be worth asking about, and small
    /// enough that the matches fit inside the budget — which is the case the ask is really about.
    private static let bounds = BoundingBox(
        minLatitude: 37.7835, maxLatitude: 37.7862,
        minLongitude: -122.4232, maxLongitude: -122.4198
    )

    private static func store() async throws -> CypressStore {
        let seedURL = try #require(SeedContractTests.seedURL, "no seed database; set CYPRESS_SEED_PATH")
        return try await CypressStore.inMemory(seedURL: seedURL)
    }

    /// The independent answer: every undeleted tree in the box whose species is `speciesUUID`,
    /// straight out of the seed, sharing nothing with the code under test.
    private static func seedTruth(
        in bounds: BoundingBox,
        speciesUUID: UUID,
        store: CypressStore
    ) async throws -> Set<UUID> {
        try await store.queue.read { connection in
            let statement = try connection.cachedStatement("""
            SELECT t.uuid AS tree_uuid
              FROM \(SeedDatabase.schemaName).trees t
              JOIN \(SeedDatabase.schemaName).species s ON s.id = t.species_current
             WHERE t.lat BETWEEN :minLat AND :maxLat
               AND t.lon BETWEEN :minLon AND :maxLon
               AND t.deleted_at IS NULL
               AND s.uuid = :species COLLATE NOCASE
            """)
            _ = try statement.bind([
                ":minLat": bounds.minLatitude, ":maxLat": bounds.maxLatitude,
                ":minLon": bounds.minLongitude, ":maxLon": bounds.maxLongitude,
                ":species": speciesUUID.uuidString
            ])
            return Set(try statement.fetchAll { try $0.uuid("tree_uuid") })
        }
    }

    private static func pins(_ content: MapContent) throws -> PinAnswer {
        guard case let .pins(answer) = content else {
            Issue.record("the viewport clustered when it should have drawn pins")
            return PinAnswer([])
        }
        return answer
    }

    // MARK: - The bar

    /// **The read-back.** The set the map drew equals the set the seed says is there — not the same
    /// count, the same trees.
    @Test("a narrowed viewport draws exactly the trees the seed holds for that species")
    func narrowedViewportIsExactlyTheSeed() async throws {
        let store = try await Self.store()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)

        let viewport = MapViewport(
            bounds: Self.bounds,
            zoom: 16,
            pinLimit: MapModel.pinLimit,
            markerCellPoints: MapModel.markerCellPoints,
            speciesIDs: [Self.londonPlane]
        )
        let answer = try Self.pins(try await api.mapContent(in: viewport))
        let truth = try await Self.seedTruth(in: Self.bounds, speciesUUID: Self.londonPlane, store: store)

        try #require(!truth.isEmpty, "the fixture box holds no London Planes at all")
        try #require(
            truth.count <= MapModel.pinLimit,
            "the fixture box holds \(truth.count) matches, over the \(MapModel.pinLimit) budget; see theOverBudgetCase"
        )

        let drawn = Set(answer.items.map(\.id))
        // ALL: nothing the seed holds is missing.
        #expect(
            drawn == truth,
            "the map drew \(drawn.count) of the seed's \(truth.count): \(truth.subtracting(drawn).count) missing, \(drawn.subtracting(truth).count) unexpected"
        )
        // …and it says so, rather than leaving the reader to guess.
        #expect(!answer.isSample, "a complete answer reported itself as a sample")
    }

    /// **ONLY**, stated as its own assertion rather than inferred from set equality above: every pin
    /// carries the species asked for. This is the half the grid breaks when the predicate is applied
    /// downstream of it, because a cell's winner need not be a match.
    @Test("every pin a narrowed viewport draws is of the species asked for")
    func narrowedViewportDrawsNothingElse() async throws {
        let store = try await Self.store()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)

        let viewport = MapViewport(
            bounds: Self.bounds,
            zoom: 16,
            pinLimit: MapModel.pinLimit,
            markerCellPoints: MapModel.markerCellPoints,
            speciesIDs: [Self.londonPlane]
        )
        let answer = try Self.pins(try await api.mapContent(in: viewport))
        try #require(!answer.items.isEmpty, "the fixture box drew nothing")

        let wrong = answer.items.filter { $0.speciesID != Self.londonPlane }
        #expect(
            wrong.isEmpty,
            "\(wrong.count) of \(answer.items.count) pins were not London Planes; the narrowing ran after the grid, not inside it"
        )
    }

    /// Narrowing really does narrow, so the tests above are not passing merely because the fixture
    /// box happens to hold one species.
    ///
    /// ── The comparison is against *trees*, not against pins drawn, and that is not pedantry ───────
    /// The obvious assertion — a narrowed map draws fewer pins than an un-narrowed one — is **false**,
    /// and measurably so on this very box: un-narrowed it draws 21, narrowed it draws 157. That is
    /// the grid working correctly rather than a defect. Un-narrowed the box holds well over the 400
    /// budget, so it thins to one pin per 44 pt cell and 21 cells are occupied; narrowed, the 157
    /// matches are inside the budget, so nothing is thinned and every one of them is drawn.
    ///
    /// Which is worth stating plainly, because it is the reverse of what everyone expects: **a search
    /// can put more pins on the map than there were before it.** It is the honest outcome — the map
    /// was previously showing a sample of a crowded neighbourhood and is now showing all of one
    /// species in it — but an assertion written on the intuition would have failed, and "fixing" the
    /// implementation until it passed would have meant thinning matches for no reason.
    @Test("narrowing narrows the trees answered for, whatever it does to the pins drawn")
    func narrowingActuallyNarrows() async throws {
        let store = try await Self.store()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)

        // A budget nothing can reach, so both answers are un-thinned and the counts are trees rather
        // than cells.
        func answer(_ speciesIDs: Set<UUID>?) async throws -> PinAnswer {
            try Self.pins(try await api.mapContent(in: MapViewport(
                bounds: Self.bounds,
                zoom: 16,
                pinLimit: 100_000,
                speciesIDs: speciesIDs
            )))
        }

        let everything = try await answer(nil)
        let narrowed = try await answer([Self.londonPlane])

        #expect(!narrowed.items.isEmpty)
        #expect(
            narrowed.items.count < everything.items.count,
            "narrowing to one species answered for \(narrowed.items.count) trees, the same as the whole box's \(everything.items.count)"
        )
        // The box genuinely holds other species, which is what makes the exclusion meaningful.
        let others = everything.items.filter { $0.speciesID != Self.londonPlane }
        #expect(!others.isEmpty, "the fixture box holds only London Planes; it cannot show that anything was excluded")
        #expect(narrowed.items.allSatisfy { $0.speciesID == Self.londonPlane })
    }

    // MARK: - Where it cannot show all of them, it says so

    /// **The honest-sample case (ERRATA E38).** The densest zoom-16 screenful of the city holds 1,458
    /// London Planes, which is three and a half times the pin budget. The map cannot draw them all as
    /// individually tappable pins and must not pretend it did: `only` still holds absolutely, `all`
    /// does not, and `PinAnswer` carries the number that lets screen 01 say which.
    @Test("a viewport with more matches than the budget reports itself a sample, and still draws only matches")
    func theOverBudgetCase() async throws {
        let store = try await Self.store()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)

        // The densest London Plane screenful in the seed, at the zoom the complaint was about.
        let dense = BoundingBox(
            minLatitude: 37.776923, maxLatitude: 37.795257,
            minLongitude: -122.430502, maxLongitude: -122.419798
        )
        let viewport = MapViewport(
            bounds: dense,
            zoom: 16,
            pinLimit: MapModel.pinLimit,
            markerCellPoints: MapModel.markerCellPoints,
            speciesIDs: [Self.londonPlane]
        )
        let answer = try Self.pins(try await api.mapContent(in: viewport))
        let truth = try await Self.seedTruth(in: dense, speciesUUID: Self.londonPlane, store: store)

        try #require(
            truth.count > MapModel.pinLimit,
            "the fixture box holds only \(truth.count) matches, inside the budget — it cannot exercise thinning"
        )

        // It knows how many there were, exactly, and it is the seed's own number.
        #expect(
            answer.matchesInView == truth.count,
            "the answer reported \(String(describing: answer.matchesInView)) matches; the seed holds \(truth.count)"
        )
        #expect(answer.isSample, "a thinned answer did not report itself as one")
        #expect(answer.items.count < truth.count, "nothing was actually thinned")

        // ONLY still holds — every drawn pin is a real match, and one the seed agrees is in the box.
        #expect(answer.items.allSatisfy { $0.speciesID == Self.londonPlane })
        #expect(Set(answer.items.map(\.id)).isSubset(of: truth), "the grid drew a tree the seed does not hold here")

        // And the reader is told, in words, rather than shown 151 pins and left to assume.
        let search = MapSearch.narrowed(.init(
            speciesIDs: [Self.londonPlane], names: ["Sycamore: London Plane"],
            drawn: answer.items.count, matched: answer.matchesInView
        ))
        let status = try #require(MapSearchCopy.status(for: search))
        #expect(status.contains("\(answer.items.count) of \(truth.count)"), "the status line was “\(status)”")
    }

    // MARK: - The empty answers, which are two different answers

    /// A query the catalogue has never heard of. The map narrows to nothing — correctly — and the
    /// difference between that and a broken map is the sentence.
    @Test("a query matching no species empties the map and says why")
    func aQueryNothingMatches() async throws {
        let store = try await Self.store()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)

        // An empty species set is what `MapModel` sends for a query the catalogue did not match.
        let viewport = MapViewport(
            bounds: Self.bounds,
            zoom: 16,
            pinLimit: MapModel.pinLimit,
            markerCellPoints: MapModel.markerCellPoints,
            speciesIDs: []
        )
        let answer = try Self.pins(try await api.mapContent(in: viewport))
        #expect(answer.items.isEmpty)
        #expect(!answer.isSample, "an empty answer claimed to be a truncated one")

        #expect(MapSearchCopy.status(for: .noMatch(query: "sycamore")) == "No species matches “sycamore”")
    }

    /// A real species with none of it in this viewport — a different statement from the one above,
    /// and the one that should send the reader panning rather than doubting their spelling.
    @Test("a real species with none in view says so, and does not say the species is unknown")
    func aSpeciesWithNoneInView() async throws {
        let store = try await Self.store()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)

        // A block of the bay: real coordinates, no trees of any species.
        let water = BoundingBox(
            minLatitude: 37.8300, maxLatitude: 37.8330,
            minLongitude: -122.3800, maxLongitude: -122.3760
        )
        let answer = try Self.pins(try await api.mapContent(in: MapViewport(
            bounds: water,
            zoom: 16,
            pinLimit: MapModel.pinLimit,
            markerCellPoints: MapModel.markerCellPoints,
            speciesIDs: [Self.londonPlane]
        )))
        #expect(answer.items.isEmpty)

        let search = MapSearch.narrowed(.init(
            speciesIDs: [Self.londonPlane], names: ["Sycamore: London Plane"], drawn: 0, matched: 0
        ))
        #expect(MapSearchCopy.status(for: search) == "No Sycamore: London Plane in view")
    }

    // MARK: - The other layer

    /// The community layer is a separate table merged in Swift, so the narrowing has to reach it
    /// too. It draws *dashed* — "the community found you these" — which makes an unfiltered
    /// community tree the most convincing possible way to break "only".
    @Test("a community tree of another species is not drawn on a narrowed map")
    func communityTreesAreNarrowedToo() async throws {
        let store = try await Self.store()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let centre = Coordinate(
            latitude: (Self.bounds.minLatitude + Self.bounds.maxLatitude) / 2,
            longitude: (Self.bounds.minLongitude + Self.bounds.maxLongitude) / 2
        )

        let match = Tree(source: .community, coordinate: centre, speciesCurrentID: Self.londonPlane)
        let other = Tree(
            source: .community,
            coordinate: Coordinate(latitude: centre.latitude + 0.0001, longitude: centre.longitude),
            speciesCurrentID: Self.brisbaneBox
        )
        let unidentified = Tree(
            source: .community,
            coordinate: Coordinate(latitude: centre.latitude + 0.0002, longitude: centre.longitude)
        )
        for tree in [match, other, unidentified] {
            try await store.queue.write { connection in
                try CommunityTreeStore().insert(tree, clientUUID: UUID(), connection: connection)
            }
        }

        let answer = try Self.pins(try await api.mapContent(in: MapViewport(
            bounds: Self.bounds,
            zoom: 16,
            pinLimit: MapModel.pinLimit,
            markerCellPoints: MapModel.markerCellPoints,
            speciesIDs: [Self.londonPlane]
        )))
        let drawn = Set(answer.items.map(\.id))
        #expect(drawn.contains(match.id), "the contributor's own matching tree was dropped from a search that matches it")
        #expect(!drawn.contains(other.id), "a Brisbane Box was drawn on a search for London Planes")
        #expect(
            !drawn.contains(unidentified.id),
            "a community tree with no species was drawn on a species search — it cannot match anything"
        )
    }

    // MARK: - Clustered zooms

    /// A1's regime rule is untouched by searching: a zoomed-out narrowed viewport still clusters, and
    /// the badges count the species asked for rather than every tree underneath them. See
    /// `TreeQueries.clusters` for why that is affordable — the planner answers a narrowed cluster
    /// query from the species index, at 21 ms against the un-narrowed 104.
    @Test("a narrowed viewport still clusters, and its badges count only the species")
    func clustersAreNarrowedNotReshaped() async throws {
        let store = try await Self.store()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let city = BoundingBox(
            minLatitude: 37.74, maxLatitude: 37.80,
            minLongitude: -122.46, maxLongitude: -122.40
        )

        func content(_ speciesIDs: Set<UUID>?) async throws -> MapContent {
            try await api.mapContent(in: MapViewport(bounds: city, zoom: 13, speciesIDs: speciesIDs))
        }

        let everything = try await content(nil)
        let narrowed = try await content([Self.londonPlane])

        guard case .clusters = narrowed else {
            Issue.record("a narrowed viewport at zoom 13 stopped clustering; A1 says it must not")
            return
        }
        #expect(
            narrowed.pinCount < everything.pinCount,
            "the narrowed badges count \(narrowed.pinCount) trees, the same as the un-narrowed \(everything.pinCount)"
        )
        #expect(narrowed.pinCount > 0, "the whole city holds no London Planes, which cannot be right")

        // And the badge total is the seed's own count for the species in that box.
        let truth = try await Self.seedTruth(in: city, speciesUUID: Self.londonPlane, store: store)
        #expect(
            narrowed.pinCount == truth.count,
            "the badges add to \(narrowed.pinCount); the seed holds \(truth.count) London Planes in the box"
        )
    }

    // MARK: - The typing path

    /// End to end through the thing the owner actually touches: text into `MapModel.searchText`,
    /// pins out of `MapModel.pins`. Everything above tests the query; this tests that the search bar
    /// is wired to it at all, which is the defect being fixed — `searchText` had two references in
    /// the whole repository, its declaration and its binding, and nothing read either.
    @MainActor
    @Test("typing a species name into the model narrows the map to it")
    func typingNarrowsTheMap() async throws {
        let store = try await Self.store()
        let model = MapModel(api: LocalAPI(store: store, deviceID: Self.deviceID))

        model.cameraDidChange(bounds: Self.bounds, zoom: 16)
        try await Self.waitUntil { !model.pins.isEmpty }
        let before = model.pins.count
        try #require(before > 0, "the map drew nothing before the search")

        // The scientific name, prefix-matched — `Platanus x hispanica` is the London Plane.
        model.searchText = "Platanus"
        try await Self.waitUntil { model.search.isActive && model.pins.count != before }

        guard case let .narrowed(narrowed) = model.search else {
            Issue.record("typing a real species left the model at \(model.search)")
            return
        }
        #expect(narrowed.speciesIDs.contains(Self.londonPlane))
        #expect(!model.pins.isEmpty, "the map emptied out on a species that is in the box")
        #expect(
            model.pins.allSatisfy { $0.speciesID != nil && narrowed.speciesIDs.contains($0.speciesID!) },
            "the map drew a tree the search did not match"
        )

        // Clearing the field puts the whole neighbourhood back.
        model.searchText = ""
        try await Self.waitUntil { model.search == .off && model.pins.count == before }
        #expect(model.search == .off)
        #expect(model.pins.count == before, "clearing the search did not restore the map")
    }

    /// **The owner's own query, through the model he types into.**
    ///
    /// `SpeciesSearchTests` proves the catalogue answers "cypress" with six species; this proves the
    /// map's search state carries all six, which is the claim the owner's report was actually about.
    /// It ran against the previous prefix scan and would have found one.
    @MainActor
    @Test("typing cypress narrows the map to every Cypress, not to the one called Cypress")
    func typingCypressNarrowsToAllOfThem() async throws {
        let store = try await Self.store()
        let model = MapModel(api: LocalAPI(store: store, deviceID: Self.deviceID))

        model.cameraDidChange(bounds: Self.bounds, zoom: 16)
        model.searchText = "cypress"
        try await Self.waitUntil { model.search.isActive }

        guard case let .narrowed(narrowed) = model.search else {
            Issue.record("“cypress” left the model at \(model.search)")
            return
        }
        #expect(
            narrowed.speciesIDs.count >= 6,
            "“cypress” narrowed to \(narrowed.speciesIDs.count) species: \(narrowed.names)"
        )
        #expect(narrowed.names.contains("Monterey Cypress"), "the map's search missed Monterey Cypress: \(narrowed.names)")
        #expect(narrowed.names.first == "Cypress species", "the genus was not ranked first: \(narrowed.names)")
        #expect(!narrowed.isTruncated, "six species is not a page")
    }

    /// A word the catalogue has never heard of narrows the map to nothing, and says so.
    @MainActor
    @Test("typing a word no species matches empties the map and reports it")
    func typingSomethingUnknown() async throws {
        let store = try await Self.store()
        let model = MapModel(api: LocalAPI(store: store, deviceID: Self.deviceID))

        model.cameraDidChange(bounds: Self.bounds, zoom: 16)
        try await Self.waitUntil { !model.pins.isEmpty }
        try #require(!model.pins.isEmpty)

        model.searchText = "zzzznotatree"
        try await Self.waitUntil { model.search.isActive && model.pins.isEmpty }

        #expect(model.search == .noMatch(query: "zzzznotatree"))
        #expect(model.pins.isEmpty, "a search matching no species still drew trees")
        #expect(MapSearchCopy.status(for: model.search) == "No species matches “zzzznotatree”")
    }

    /// Waits for the model to settle on a state, rather than for a fixed span.
    ///
    /// A fixed sleep is the wrong tool twice over here: too short and it fails on a cold page cache —
    /// the first read against the attached 95 MB seed takes seconds in CI — and too long and every
    /// one of these tests pays for the worst case. Polling asserts *what* the model settles on and
    /// never how fast, which is the only thing worth pinning: the debounces are tuned for a thumb,
    /// not for a test, and a test that pinned them would fail every time they were retuned.
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
    }

    // MARK: - The words

    @Test("the status line distinguishes the four things an empty map can mean")
    func theStatusLineSaysWhichEmptyItIs() {
        #expect(MapSearchCopy.status(for: .off) == nil)
        #expect(MapSearchCopy.status(for: .noMatch(query: "qqq")) == "No species matches “qqq”")

        // Resolved but not yet answered: name the subject, claim no counts.
        let pending = MapSearch.narrowed(.init(speciesIDs: [Self.londonPlane], names: ["Ginkgo"]))
        #expect(MapSearchCopy.status(for: pending) == "Showing Ginkgo")

        // Answered completely: say nothing. The map is the answer.
        let complete = MapSearch.narrowed(.init(
            speciesIDs: [Self.londonPlane], names: ["Ginkgo"], drawn: 12, matched: 12
        ))
        #expect(MapSearchCopy.status(for: complete) == nil)

        let none = MapSearch.narrowed(.init(
            speciesIDs: [Self.londonPlane], names: ["Ginkgo"], drawn: 0, matched: 0
        ))
        #expect(MapSearchCopy.status(for: none) == "No Ginkgo in view")

        let sampled = MapSearch.narrowed(.init(
            speciesIDs: [Self.londonPlane], names: ["Ginkgo"], drawn: 151, matched: 1_458
        ))
        #expect(MapSearchCopy.status(for: sampled) == "Showing 151 of 1458 Ginkgo here")
    }

    /// **E38, one level up from the pins.** The counts above are about trees; this one is about
    /// species, and it became reachable when task #108 stopped the catalogue matching prefixes only.
    /// "a" prefix-matches 97 of the seed's 577 species and *contains* in 555, so a single keystroke
    /// on the way to a real word now overruns the 100 the map asks for. Every sentence the status
    /// line can produce has to say so, because in every one of them the map is complete with respect
    /// to a species set the reader was never told was a page.
    @Test("a species set that was itself a page never reads as the whole match")
    func aTruncatedSpeciesSetSaysSo() {
        let names = (0..<MapSearch.speciesLimit).map { "Species \($0)" }
        func truncated(drawn: Int? = nil, matched: Int? = nil) -> MapSearch {
            .narrowed(.init(
                speciesIDs: Set(names.map { _ in UUID() }),
                names: names,
                isTruncated: true,
                drawn: drawn,
                matched: matched
            ))
        }

        // Before an answer lands, and on a clustered viewport.
        #expect(MapSearchCopy.status(for: truncated()) == "Showing the first 100 matching species")
        // A complete answer, which for an untruncated search says nothing at all.
        #expect(
            MapSearchCopy.status(for: truncated(drawn: 12, matched: 12))
                == "Showing every tree of the first 100 matching species"
        )
        // A thinned answer keeps its own numbers and adds the species page to them.
        #expect(
            MapSearchCopy.status(for: truncated(drawn: 151, matched: 1_458))
                == "Showing 151 of 1458 trees here, from the first 100 matching species"
        )
        // Nothing in view. "No the first 100 matching species in view" is why this is not the
        // untruncated sentence with a substitution.
        #expect(
            MapSearchCopy.status(for: truncated(drawn: 0, matched: 0))
                == "None of the first 100 matching species are in view"
        )
    }

    /// The flag is set from the one signal the catalogue gives — a full page — and only from it. A
    /// search that came back under the limit is complete, and must go on saying nothing when the map
    /// has drawn all of it.
    @Test("a search under the limit is not reported as a page")
    func anUnderfullSearchIsNotTruncated() throws {
        func species(_ n: Int) throws -> [Species] {
            try (0..<n).map { i in
                try Species(
                    scientificName: "Genus species\(i)",
                    commonName: "Common \(i)",
                    leafRetention: nil
                )
            }
        }

        guard case let .narrowed(few) = try MapSearch(query: "x", matches: species(3)) else {
            Issue.record("three matches did not resolve to a narrowed search")
            return
        }
        #expect(!few.isTruncated)

        guard case let .narrowed(full) = try MapSearch(query: "a", matches: species(MapSearch.speciesLimit)) else {
            Issue.record("a full page did not resolve to a narrowed search")
            return
        }
        #expect(full.isTruncated, "a full page of species did not report itself as one")
    }

    @Test("the subject names one or two species and counts the rest")
    func theSubjectStaysReadable() {
        #expect(MapSearchCopy.subject([]) == "trees")
        #expect(MapSearchCopy.subject(["Ginkgo"]) == "Ginkgo")
        #expect(MapSearchCopy.subject(["Ginkgo", "Cherry Plum"]) == "Ginkgo and Cherry Plum")
        #expect(MapSearchCopy.subject(["A", "B", "C"]) == "3 species")
    }

    /// `PinAnswer` may not describe a complete answer as a sample, whatever it is handed — the whole
    /// value of `matchesInView == nil` is that a reader can treat it as a guarantee.
    @Test("an answer that dropped nothing is never a sample")
    func aCompleteAnswerIsNeverASample() {
        let pin = TreePin(
            id: UUID(), coordinate: Coordinate(latitude: 37.77, longitude: -122.42),
            status: .alive, source: .cityImport, verificationState: .unverified, speciesID: nil
        )
        #expect(!PinAnswer([pin], matchesInView: 1).isSample)
        #expect(!PinAnswer([pin], matchesInView: 0).isSample)
        #expect(PinAnswer([pin], matchesInView: 9).isSample)
        #expect(PinAnswer([pin]).treesRepresented == 1)
        #expect(PinAnswer([pin], matchesInView: 9).treesRepresented == 9)
    }
}
