import Foundation
import Testing
@testable import Cypress

/// Screen 01's filter interface (#116, RULINGS R23, ERRATA E175).
///
/// ── What these tests are actually guarding ───────────────────────────────────────────────────
/// The narrowing itself is the easy half and `MapSearchTests` already proves the hard part of it —
/// that a predicate reaching the pin query but not the marker grid breaks "all and only". What is
/// new here is that three of the four filters can produce a *wrong number* or a *silent omission*,
/// and both are the kind of defect this project has shipped before:
///
/// - **E38** — `31 trees` must not be the size of a page. The grid thins; the count must be of what
///   matched, not of what survived.
/// - **E175** — 80.78 % of the seed carries no planting date, so a year filter that says nothing
///   about them is asserting they were planted outside every decade the reader can pick. The figure
///   was 73.97 % when this was written and San Jose moved it the same day (E176); the number lives in
///   `MapYearFilterCopy` and is asserted against the seed for exactly that reason.
/// - **D1** — none of the above may become a count of the reader's own actions.
///
/// E126 used to be the fourth entry — an emptied map said why, on a card. Task #165 struck that
/// presentation on the owner's instruction: no message box stands in for an empty filter, and the
/// `Clear filters` chip in the row is the way out.
///
/// Every assertion that could be satisfied by a stub is checked against a second, independent read
/// of the store rather than against the code under test.
@Suite("Map filters")
struct MapFilterTests {

    private static let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-0000000000F1")!
    private static let otherDeviceID = UUID(uuidString: "D0000000-0000-4000-8000-0000000000F2")!

    private static func store() async throws -> CypressStore {
        let seedURL = try #require(SeedContractTests.seedURL, "no seed database; set CYPRESS_SEED_PATH")
        return try await CypressStore.inMemory(seedURL: seedURL)
    }

    /// Some real tree uuids out of the seed, so nothing here narrows to an id that does not exist.
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

    private static func coordinate(of tree: UUID, store: CypressStore) async throws -> Coordinate {
        try await store.queue.read { connection in
            let statement = try connection.cachedStatement("""
            SELECT lat, lon FROM \(SeedDatabase.schemaName).trees
             WHERE uuid = :uuid COLLATE NOCASE
            """)
            _ = try statement.bind([":uuid": tree.uuidString])
            return try statement.fetchOne {
                Coordinate(latitude: try $0.double("lat"), longitude: try $0.double("lon"))
            }!
        }
    }

    private static func pins(_ content: MapContent) throws -> PinAnswer {
        guard case let .pins(answer) = content else {
            Issue.record("the viewport clustered when it should have drawn pins")
            return PinAnswer([])
        }
        return answer
    }

    // MARK: - 1. Yours

    /// **The `Yours` set is the trees this device contributed to, and only those.**
    ///
    /// A visit is written for one tree from this device and one from another, and the set must hold
    /// exactly the first. The second is the assertion that matters: D11 says privacy is the shape of
    /// the query, and a `Yours` chip that showed somebody else's trees would be the loudest possible
    /// violation of it.
    @Test("Yours holds the trees this device contributed to, and no one else's")
    func yoursIsThisDevicesContributions() async throws {
        let store = try await Self.store()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let trees = try await Self.seedTrees(limit: 3, store: store)
        let mine = trees[0]
        let theirs = trees[1]

        try await store.queue.write { connection in
            let contributions = ContributionStore()
            _ = try contributions.insert(
                Visit(
                    treeID: mine,
                    attribution: Attribution(userID: nil, deviceID: Self.deviceID),
                    capturedAt: Date()
                ),
                connection: connection
            )
            _ = try contributions.insert(
                Visit(
                    treeID: theirs,
                    attribution: Attribution(userID: nil, deviceID: Self.otherDeviceID),
                    capturedAt: Date()
                ),
                connection: connection
            )
        }

        let yours = try await api.mapMembership(.yours)
        #expect(yours == [mine], "expected exactly the tree this device visited, got \(yours)")
        #expect(!yours.contains(theirs), "another device's visit leaked into Yours")
    }

    /// **A membership narrowing draws exactly its set — no more, and nothing thinned away.**
    ///
    /// The box is the whole city, so an un-narrowed viewport here would draw thousands of pins and
    /// the grid would thin them. The narrowed one must come back with the one tree and must report
    /// itself complete: `PinAnswer.matchesInView == nil` is the guarantee E38 rests on.
    @Test("a Yours viewport draws exactly the contributed trees, un-thinned")
    func yoursViewportDrawsExactlyTheSet() async throws {
        let store = try await Self.store()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let trees = try await Self.seedTrees(limit: 2, store: store)
        let mine = trees[0]

        try await store.queue.write { connection in
            _ = try ContributionStore().insert(
                Visit(
                    treeID: mine,
                    attribution: Attribution(userID: nil, deviceID: Self.deviceID),
                    capturedAt: Date()
                ),
                connection: connection
            )
        }

        let city = BoundingBox(
            minLatitude: 37.69, maxLatitude: 37.85,
            minLongitude: -122.54, maxLongitude: -122.33
        )
        let viewport = MapViewport(
            bounds: city,
            zoom: 16,
            pinLimit: MapModel.pinLimit,
            treeIDs: try await api.mapMembership(.yours)
        )
        let answer = try Self.pins(try await api.mapContent(in: viewport))

        #expect(Set(answer.items.map(\.id)) == [mine], "drew \(answer.items.count) pins, expected 1")
        #expect(!answer.isSample, "a set of one reported itself as a thinned sample")
    }

    /// **An empty membership set narrows the map to nothing — it does not widen it to everything.**
    ///
    /// This is the failure mode that would be invisible in use and catastrophic in meaning: a reader
    /// with no favourites taps `Favourites` and is shown the entire city as though all of it were
    /// theirs. `nil` means "not narrowed"; `[]` means "narrowed to nothing", and the two must not
    /// collapse anywhere between `MapModel` and the SQL.
    @Test("an empty membership set empties the map rather than showing every tree")
    func emptyMembershipEmptiesTheMap() async throws {
        let store = try await Self.store()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)

        let city = BoundingBox(
            minLatitude: 37.69, maxLatitude: 37.85,
            minLongitude: -122.54, maxLongitude: -122.33
        )
        let viewport = MapViewport(bounds: city, zoom: 16, pinLimit: MapModel.pinLimit, treeIDs: [])
        let answer = try Self.pins(try await api.mapContent(in: viewport))

        #expect(answer.items.isEmpty, "an empty membership set drew \(answer.items.count) pins")
    }

    // MARK: - 2. Favourites

    /// **A favourite is held; an un-favourite is not.**
    ///
    /// The tombstone is the whole test. A favourite toggle keeps its row and sets `deleted_at`
    /// (BUILD-PLAN §4), so a query that forgot the clause would report every tree the reader had
    /// *ever* hearted as one they still hold.
    @Test("Favourites excludes a tree whose favourite was turned back off")
    func favouritesExcludesTombstones() async throws {
        let store = try await Self.store()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let trees = try await Self.seedTrees(limit: 3, store: store)
        let kept = trees[0]
        let dropped = trees[1]
        let owner = FavoriteOwner.device(Self.deviceID)

        try await store.queue.write { connection in
            let contributions = ContributionStore()
            _ = try contributions.applyFavoriteToggle(
                owner: owner, treeID: kept, clientUUID: UUID(),
                isFavorite: true, at: Date(), connection: connection
            )
            _ = try contributions.applyFavoriteToggle(
                owner: owner, treeID: dropped, clientUUID: UUID(),
                isFavorite: true, at: Date(), connection: connection
            )
            _ = try contributions.applyFavoriteToggle(
                owner: owner, treeID: dropped, clientUUID: UUID(),
                isFavorite: false, at: Date().addingTimeInterval(60), connection: connection
            )
        }

        let favourites = try await api.mapMembership(.favorites)
        #expect(favourites == [kept], "expected only the tree still hearted, got \(favourites)")
        #expect(!favourites.contains(dropped), "an un-favourited tree came back as a favourite")
    }

    /// A favourite is not a contribution, and a contribution is not a favourite. The owner asked for
    /// two chips because they are two questions; if either set answered the other, one chip would be
    /// dead weight and the reader would be told something false about the trees it drew.
    @Test("Yours and Favourites are different sets")
    func yoursAndFavouritesDisagree() async throws {
        let store = try await Self.store()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let trees = try await Self.seedTrees(limit: 3, store: store)
        let visited = trees[0]
        let hearted = trees[1]

        try await store.queue.write { connection in
            let contributions = ContributionStore()
            _ = try contributions.insert(
                Visit(
                    treeID: visited,
                    attribution: Attribution(userID: nil, deviceID: Self.deviceID),
                    capturedAt: Date()
                ),
                connection: connection
            )
            _ = try contributions.applyFavoriteToggle(
                owner: .device(Self.deviceID), treeID: hearted, clientUUID: UUID(),
                isFavorite: true, at: Date(), connection: connection
            )
        }

        let yours = try await api.mapMembership(.yours)
        let favourites = try await api.mapMembership(.favorites)
        #expect(yours == [visited], "Yours answered \(yours)")
        #expect(favourites == [hearted], "Favourites answered \(favourites)")
    }

    // MARK: - 3. Year (ERRATA E175)

    /// **The measurement the year control is designed around, pinned so it cannot rot.**
    ///
    /// `MapYearFilterCopy.setAside` says "about 4 in 5". That sentence is only honest while the seed
    /// actually looks like this, and the seed is rebuilt by `Tools/build_seed.py` from a live city
    /// export — so a re-ingest could move coverage without anybody touching this feature. This test
    /// is what makes that a failing build rather than a lie on screen.
    @Test("the seed's planting-date coverage still matches what the year filter's copy claims")
    func plantingDateCoverageMatchesTheCopy() async throws {
        let store = try await Self.store()
        let (total, dated) = try await store.queue.read { connection -> (Int, Int) in
            let statement = try connection.cachedStatement("""
            SELECT COUNT(*) AS total, SUM(planted_year IS NOT NULL) AS dated
              FROM \(SeedDatabase.schemaName).trees
             WHERE deleted_at IS NULL
            """)
            return try statement.fetchOne {
                (try $0.int("total"), try $0.int("dated"))
            }!
        }

        try #require(total > 0, "the seed holds no trees at all")
        let undatedShare = Double(total - dated) / Double(total)

        // The constant the copy is derived from, and the rounding the copy performs. Both are
        // asserted: the first catches a drift the sentence would hide, the second catches a drift
        // large enough to make "4 in 5" the wrong words.
        //
        // This pair has already caught a real one. Written against a San-Francisco-only seed it read
        // 0.7397 and "3 in 4"; San Jose landed hours later and turned the merge red, because San Jose
        // publishes a planting date for 222 of 52,788 rows. See E175 and E176 — the point of pinning
        // the number to the seed rather than to the day it was measured.
        #expect(
            abs(undatedShare - MapYearFilterCopy.undatedShareOfSeed) < 0.01,
            "planting-date coverage moved: \(undatedShare) undated, copy is written for \(MapYearFilterCopy.undatedShareOfSeed)"
        )
        #expect(
            undatedShare > 0.75 && undatedShare < 0.85,
            "\"about 4 in 5\" is no longer true of the seed: \(undatedShare) of rows are undated"
        )
    }

    /// **A year narrowing never returns a tree with no planting date.**
    ///
    /// This is the honest half of E175 — the predicate does what it says. The dishonest half is a
    /// surface that lets the silence read as an answer, which `yearFilterAlwaysSaysWhatItSetAside`
    /// below is about.
    @Test("a year-narrowed viewport returns no tree without a planting date")
    func yearNarrowingExcludesUndatedTrees() async throws {
        let store = try await Self.store()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let city = BoundingBox(
            minLatitude: 37.69, maxLatitude: 37.85,
            minLongitude: -122.54, maxLongitude: -122.33
        )
        let decade = MapFilter.Decade.twentyTens
        let viewport = MapViewport(
            bounds: city,
            zoom: 16,
            pinLimit: MapModel.pinLimit,
            markerCellPoints: MapModel.markerCellPoints,
            plantedYears: decade.years
        )
        let answer = try Self.pins(try await api.mapContent(in: viewport))
        try #require(!answer.items.isEmpty, "the 2010s narrowing drew nothing at all over the city")

        // The read-back, independent of `TreeQueries`: every drawn pin's planting year, straight out
        // of the seed. Any nil, or any year outside the decade, is the defect.
        let drawn = answer.items.map(\.id)
        let json = "[\(drawn.map { "\"\($0.uuidString.lowercased())\"" }.joined(separator: ","))]"
        let years: [Int?] = try await store.queue.read { connection in
            let statement = try connection.cachedStatement("""
            SELECT planted_year FROM \(SeedDatabase.schemaName).trees
             WHERE uuid COLLATE NOCASE IN (SELECT value FROM json_each(:uuids))
            """)
            _ = try statement.bind([":uuids": json])
            return try statement.fetchAll { try $0.intIfPresent("planted_year") }
        }

        #expect(years.count == drawn.count, "the read-back found \(years.count) of \(drawn.count) drawn pins")
        let undated = years.filter { $0 == nil }
        #expect(undated.isEmpty, "\(undated.count) trees with no planting date were drawn under a year filter")
        let outside = years.compactMap { $0 }.filter { !decade.years.contains($0) }
        #expect(outside.isEmpty, "\(outside.count) trees outside the 2010s were drawn: \(outside.prefix(5))")
    }

    /// **The year control never runs silently.** The screen renders `MapYearFilterCopy.setAside`
    /// whenever a decade is chosen, and the sentence has to name the thing the filter cannot judge.
    /// A caveat that did not mention planting dates would satisfy a `!isEmpty` check and tell the
    /// reader nothing.
    @Test("the year filter's caveat names the rows it cannot judge")
    func yearFilterAlwaysSaysWhatItSetAside() {
        let sentence = MapYearFilterCopy.setAside
        #expect(sentence.lowercased().contains("planting date"), "the caveat does not mention planting dates: \(sentence)")
        #expect(sentence.lowercased().contains("no recorded"), "the caveat does not say the date is missing: \(sentence)")
        // ARCHITECTURE §5.7 — no spaces around em dashes.
        #expect(!sentence.contains(" — "), "spaced em dash in \(sentence)")
    }

    /// Every decade is reachable and none of them overlap, so a tree cannot be in two buckets and no
    /// year between the seed's 1955 and 2026 falls out of all of them.
    @Test("the decade buckets tile the seed's whole planting range without overlapping")
    func decadesTileTheRange() {
        let all = MapFilter.Decade.allCases
        for year in 1955...2026 {
            let matching = all.filter { $0.years.contains(year) }
            #expect(matching.count == 1, "\(year) falls in \(matching.count) buckets, not 1")
        }
    }

    // MARK: - 4. The result line (D1 and ERRATA E38)

    /// **E38: a page is not a total.** When the grid thinned the answer, the line must report how
    /// many matched *and* say that fewer are drawn. Reporting the drawn count alone is the defect.
    @Test("the result line reports matches, not the size of the thinned page")
    func resultLineReportsMatchesNotThePage() {
        let thinned = MapFilterCopy.result(drawn: 151, matched: 1_458)
        #expect(thinned.contains("1458") || thinned.contains("1,458"), "the match count is missing from \(thinned)")
        #expect(thinned.contains("151"), "the drawn count is missing from \(thinned)")
        #expect(thinned != "151 trees", "a thinned answer was reported as a total")

        // A complete answer says one number, because there is only one.
        #expect(MapFilterCopy.result(drawn: 31, matched: nil) == "31 trees")
        #expect(MapFilterCopy.result(drawn: 1, matched: nil) == "1 tree")
    }

    /// **D1: the number is about the map, never about the person.**
    ///
    /// The owner's brief draws the line precisely — "a neutral count as a *filter result* ('31
    /// trees') is fine — a count that reads as a personal total is not". So the sentence may not
    /// address the reader or claim possession, in any of the shapes that would turn it into a score.
    @Test("the result line never states a count as the reader's own total")
    func resultLineIsNotAPersonalTotal() {
        let forbidden = ["your", "you have", "you've", "yours", "visited", "contributed", "total"]
        for drawn in [0, 1, 31, 1_458] {
            for matched in [nil, 9_999] as [Int?] {
                let line = MapFilterCopy.result(drawn: drawn, matched: matched).lowercased()
                for word in forbidden {
                    #expect(!line.contains(word), "\"\(word)\" appeared in the result line: \(line)")
                }
            }
        }
    }

    /// The chip that names the set is allowed to say `Yours`; the *count* beside it is not allowed
    /// to attach itself to that word. This pins the separation the previous test relies on — the
    /// label and the number are different strings and neither is built from the other.
    @Test("the membership chip label carries no number")
    func membershipLabelCarriesNoNumber() {
        for kind in MapMembership.allCases {
            let label = MapFilterCopy.membershipLabel(kind)
            let hasDigit = label.rangeOfCharacter(from: .decimalDigits) != nil
            #expect(!hasDigit, "a digit appeared in the chip label: \(label)")
        }
    }

    // MARK: - 5. The empty state there deliberately is none of (task #165)

    // Section 5 used to pin E126's empty-notice copy — `emptyTitle`, `emptyMessage`, the E184
    // heart-word hunt. The owner struck the presentation those sentences existed for ("we should
    // NEVER display a message box in place of an empty filter … if nothing matches, fine"), the
    // copy is deleted, and a filter that matches nothing renders the empty map itself. What
    // survives of the section is the one fact that is still load-bearing: the way out exists and
    // is labelled, because the `Clear filters` chip is the only exit left.
    @Test("the way out of any filter is a labelled control")
    func clearFiltersIsStillLabelled() {
        #expect(!MapFilterCopy.clearLabel.isEmpty)
    }

    // MARK: - 6. The filter value itself

    /// The filters compose. The owner's four are independent questions, and a row that dropped one
    /// when the reader asked another would be the single-select behaviour the design replaced.
    @Test("the four dimensions combine rather than replacing each other")
    func dimensionsCompose() {
        var filter = MapFilter()
        #expect(!filter.isActive)
        #expect(!filter.narrowsTheQuery)

        filter.membership = .yours
        filter.decade = .twentyTens
        filter.speciesID = UUID()
        filter.condition = .needsCare

        #expect(filter.membership == .yours, "setting a decade cleared the membership")
        #expect(filter.decade == .twentyTens, "setting a species cleared the decade")
        #expect(filter.isActive)
        #expect(filter.narrowsTheQuery)

        // The condition is the one dimension that does *not* reach the query, because neither
        // "needs care" nor "in bloom" is a column the seed's map statements select on.
        #expect(MapFilter.needsCare.isActive)
        #expect(!MapFilter.needsCare.narrowsTheQuery)
    }

    /// A membership viewport suspends A1's clustering, and only a membership viewport does. The
    /// deviation is argued on `MapViewport.shouldCluster`; this pins how narrow it is.
    @Test("only a membership narrowing suspends clustering")
    func onlyMembershipSuspendsClustering() {
        let city = BoundingBox(
            minLatitude: 37.69, maxLatitude: 37.85,
            minLongitude: -122.54, maxLongitude: -122.33
        )
        #expect(MapViewport(bounds: city, zoom: 12).shouldCluster)
        #expect(MapViewport(bounds: city, zoom: 12, plantedYears: 2010...2019).shouldCluster,
                "a year narrowing suspended clustering; it can still match 37,962 trees")
        #expect(MapViewport(bounds: city, zoom: 12, speciesIDs: [UUID()]).shouldCluster,
                "a species narrowing suspended clustering")
        #expect(!MapViewport(bounds: city, zoom: 12, treeIDs: [UUID()]).shouldCluster,
                "a membership narrowing still clustered a set bounded by what one person tapped")
    }

    // MARK: - 7. The expandable control (RULINGS R23.1)

    /// **A narrowing set behind a shut control must be visible in the row's drawn label.**
    ///
    /// R23.1 §2's hazard: a filter nobody can see is a map thinned by a cause nobody can find, which
    /// is ERRATA E126's defect wearing a new hat. Three channels answer it and `CypressUITests`
    /// reaches two of them — the selected trait and the spoken value. It cannot reach this one,
    /// because the chip overrides its accessibility label back to `More filters` so the count is not
    /// read out ahead of the value that names what is on. So the *drawn* string is pinned here.
    @Test("the collapsed control's drawn label counts what is set inside it")
    func moreChipLabelCountsWhatIsHidden() {
        #expect(MapFilterCopy.moreChipLabel(active: 0) == MapFilterCopy.moreLabel,
                "an empty control decorates its label with something")
        let one = MapFilterCopy.moreChipLabel(active: 1)
        #expect(one != MapFilterCopy.moreLabel,
                "a filter is set behind the control and the chip draws “\(one)”, the same words as an empty one, so nothing on screen says the map has been narrowed")
        #expect(one.contains("1"), "the label does not say how many: \(one)")
        #expect(MapFilterCopy.moreChipLabel(active: 2).contains("2"))
    }

    /// **And a listener gets the state and the names, which is the channel the label cannot carry.**
    ///
    /// Two facts in one value on purpose (R23.1 §2). A disclosure that does not say whether it is open
    /// leaves a listener pressing it to find out; a shut one that named no contents would leave the
    /// hazard fixed for sighted readers only.
    @Test("the control announces whether it is open and what is on inside it")
    func moreValueSaysStateAndContents() {
        let shutEmpty = MapFilterCopy.moreValue(isExpanded: false, activeNames: [])
        let openEmpty = MapFilterCopy.moreValue(isExpanded: true, activeNames: [])
        #expect(shutEmpty != openEmpty, "open and shut announce the same thing: \(shutEmpty)")

        let favoritesOn = MapFilter(membership: .favorites)
        let names = favoritesOn.activeExtras.map { $0.label(in: favoritesOn) }
        let shutOn = MapFilterCopy.moreValue(isExpanded: false, activeNames: names)
        #expect(shutOn != shutEmpty,
                "a shut control with a filter on announces “\(shutOn)”, the same as an empty one: the map is narrowed by a cause nothing on screen names")
        #expect(shutOn.contains(MapExtraFilter.favorites.label(in: favoritesOn)),
                "the shut control does not name what is on: \(shutOn)")
        // The names, not a count: a spoken string has no width, which is the whole reason the label
        // and the value divide the work the way they do.
        #expect(!shutOn.contains("1"), "the spoken value counts where it should name: \(shutOn)")
    }

    /// **A hidden narrowing that carries a value speaks the value, not just the dimension** (#145).
    ///
    /// `Year` is set from a menu inside a control that may be shut by the time anyone listens. The
    /// shut control's spoken names are built from `label(in:)`, so a listener has to get the decade
    /// — the dimension alone would tell them the map is narrowed by year and leave them opening the
    /// drawer to learn to what.
    @Test("the year narrowing names its decade through the shut control")
    func yearSpeaksItsDecadeWhileHidden() {
        var filter = MapFilter.all
        let resting = MapExtraFilter.year.label(in: filter)
        filter.decade = .twentyTens

        let chosen = MapExtraFilter.year.label(in: filter)
        #expect(chosen != resting,
                "a chosen decade and no decade produce the same name: “\(chosen)”")
        #expect(chosen.contains(MapFilter.Decade.twentyTens.label),
                "the hidden year narrowing is named “\(chosen)”, which does not say which decade is on")

        let names = filter.activeExtras.map { $0.label(in: filter) }
        let spoken = MapFilterCopy.moreValue(isExpanded: false, activeNames: names)
        #expect(spoken.contains(MapFilter.Decade.twentyTens.label),
                "the shut control announces “\(spoken)” while the map is narrowed to the 2010s")
    }

    /// **The drawer is an extension point, and `activeExtras` is the one expression its three
    /// channels read.**
    ///
    /// The owner asked for "favorites (and any others we add later)"; `year` is the later one
    /// (#145), and it is also the case that proved the drawer's contents are not all toggles — a
    /// decade is a value, so each case is turned on below the way its own control does it, and the
    /// claims that stay uniform (reports itself, activates the filter, clears with the rest) are
    /// asserted over `allCases`.
    @Test("every hidden narrowing reports itself and clears with the rest")
    func extraFiltersAreDrivenByTheirOwnCases() {
        #expect(!MapExtraFilter.allCases.isEmpty)
        for extra in MapExtraFilter.allCases {
            var filter = MapFilter.all
            #expect(!extra.isOn(filter), "\(extra) reads as on over an unfiltered map")
            #expect(filter.activeExtras.isEmpty)

            switch extra {
            case .favorites: MapExtraFilter.toggleFavorites(in: &filter)
            case .year: filter.decade = .twentyTens
            }
            #expect(extra.isOn(filter), "\(extra) did not come on")
            #expect(filter.isActive,
                    "\(extra) is on and the filter is not active, so no “Clear filters” would draw and the only way out would be to remember it is there (R23.1 §3)")
            #expect(filter.activeExtras.map(\.id) == [extra.id],
                    "\(extra) is on and activeExtras reports \(filter.activeExtras.map(\.id))")
            #expect(!extra.label(in: filter).isEmpty, "\(extra) has no words")

            // …and the one clear-everything control reaches it. This is R23.1 §3: if the way out of
            // a hidden filter were also hidden, a reader would have to know the filter existed to
            // find the control that removes it.
            filter = .all
            #expect(!extra.isOn(filter), "clearing every filter left \(extra) on")
        }
    }

    /// `Favorites` is still a toggle, and the membership swap still crosses the two surfaces
    /// (R23 §1, R23.1): turning it on inside the drawer turns `Yours` off in the row above.
    @Test("favorites toggles, and turning it on takes Yours off")
    func favoritesToggleStillSwapsMembership() {
        var filter = MapFilter(membership: .yours)
        MapExtraFilter.toggleFavorites(in: &filter)
        #expect(filter.membership == .favorites, "the swap did not cross the two surfaces")
        MapExtraFilter.toggleFavorites(in: &filter)
        #expect(filter.membership == nil, "favorites could not be turned off again")
    }

    /// The row is the owner's four, in the owner's order: "yours, in bloom, needs care, and year".
    ///
    /// `MapFilterChips` draws `Condition.allCases` and does not re-sort it, so the declaration order
    /// *is* the drawn order — which makes it worth one assertion rather than a comment.
    @Test("the two condition chips are drawn in the owner's order")
    func conditionOrderIsTheOwnersOrder() {
        #expect(MapFilter.Condition.allCases.map(\.label) == ["In bloom", "Needs care"],
                "the row draws \(MapFilter.Condition.allCases.map(\.label))")
    }

    /// American spelling, on the owner's instruction (R23.1). They named this word.
    @Test("the membership vocabulary is spelled the American way")
    func membershipIsSpelledAmerican() {
        let label = MapFilterCopy.membershipLabel(.favorites)
        #expect(label == "Favorites", "the chip says \(label)")
    }
}
