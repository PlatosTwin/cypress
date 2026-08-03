import Foundation
import Testing
@testable import Cypress

/// Screen 01's filter interface (#116, RULINGS R23, ERRATA E175).
///
/// ── What these tests are actually guarding ───────────────────────────────────────────────────
/// The narrowing itself is the easy half and `MapSearchTests` already proves the hard part of it —
/// that a predicate reaching the pin query but not the marker grid breaks "all and only". What is
/// left here is a filter's ability to make a *silent wrong claim*, which is the kind of defect this
/// project has shipped before:
///
/// - **E175** — most of the seed carries no planting date, so a year filter is judging a small
///   minority of rows and silently setting the rest aside. The share is asserted against the seed
///   by `plantingDateCoverageIsWhatTheDecadeBucketsWereBuiltFor`, because it moved once already
///   when San Jose landed (E176) and the control's whole shape is built on it.
/// - **Task #178** — a vacant planting site's `planted_year` belongs to a tree that is gone, so a
///   year narrowing that returns one asserts a planting on an empty basin. E107 refused the same
///   claim on the site screen.
/// - **Task #179** — the two arms of the site filter must partition the map, or one of them is
///   quietly answering for the other.
///
/// **Three former entries are gone, and all three for the same reason.** E38 (`31 trees` must not
/// be the size of a page) and D1 (no count of the reader's own actions) both constrained the result
/// line; E126 constrained an empty-state card. Task #165 struck the card, and **RULINGS R41 struck
/// every remaining message beside a filter** (task #180) — the caveat sentence and the result count
/// with it. A filter's entire voice is its chip. What survives of those entries is
/// `membershipLabelCarriesNoNumber`, which guards the chips themselves.
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

    /// A box around the whole of San Francisco, which is where the seed's rows are dense enough for
    /// a narrowing to have something to return at pin zoom.
    private static let cityBounds = BoundingBox(
        minLatitude: 37.69, maxLatitude: 37.85,
        minLongitude: -122.54, maxLongitude: -122.33
    )

    /// The `trees.status` of each drawn pin, read straight out of the seed.
    ///
    /// **Deliberately a second, independent read.** The tests for tasks #178 and #179 are about
    /// whether the filter returned the right *rows*, and asking the same query layer to confirm its
    /// own answer would pass for a predicate that was consistently wrong. This joins the drawn ids
    /// back to the seed by uuid instead.
    private static func statuses(of drawn: [UUID], in store: CypressStore) async throws -> [String] {
        guard !drawn.isEmpty else { return [] }
        let json = "[\(drawn.map { "\"\($0.uuidString.lowercased())\"" }.joined(separator: ","))]"
        return try await store.queue.read { connection in
            let statement = try connection.cachedStatement("""
            SELECT status FROM \(SeedDatabase.schemaName).trees
             WHERE uuid COLLATE NOCASE IN (SELECT value FROM json_each(:uuids))
            """)
            _ = try statement.bind([":uuids": json])
            return try statement.fetchAll { try $0.string("status") }
        }
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
    /// with no favorites taps `Favorites` and is shown the entire city as though all of it were
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

    // MARK: - 2. Favorites

    /// **A favorite is held; an un-favorite is not.**
    ///
    /// The tombstone is the whole test. A favorite toggle keeps its row and sets `deleted_at`
    /// (BUILD-PLAN §4), so a query that forgot the clause would report every tree the reader had
    /// *ever* hearted as one they still hold.
    @Test("Favorites excludes a tree whose favorite was turned back off")
    func favoritesExcludesTombstones() async throws {
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

        let favorites = try await api.mapMembership(.favorites)
        #expect(favorites == [kept], "expected only the tree still hearted, got \(favorites)")
        #expect(!favorites.contains(dropped), "an un-favorited tree came back as a favorite")
    }

    /// A favorite is not a contribution, and a contribution is not a favorite. The owner asked for
    /// two chips because they are two questions; if either set answered the other, one chip would be
    /// dead weight and the reader would be told something false about the trees it drew.
    @Test("Yours and Favorites are different sets")
    func yoursAndFavoritesDisagree() async throws {
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
        let favorites = try await api.mapMembership(.favorites)
        #expect(yours == [visited], "Yours answered \(yours)")
        #expect(favorites == [hearted], "Favorites answered \(favorites)")
    }

    // MARK: - 3. Year (ERRATA E175)

    /// **The seed measurements the year control is designed around, pinned so they cannot rot.**
    ///
    /// This test used to be `plantingDateCoverageMatchesTheCopy`, and it asserted that the seed's
    /// undated share still rounded to the "4 in 5" in `MapYearFilterCopy.setAside`. **RULINGS R41
    /// removed that sentence** (task #180), so the copy it checked against no longer exists.
    ///
    /// It is repurposed rather than deleted because the *number* was never really about the
    /// sentence: it is why this control buckets by decade instead of by year, why R23 recorded the
    /// per-viewport count as a trade rather than an oversight, and — since task #178 — why a year
    /// narrowing has to exclude vacant sites. A re-ingest that moved any of these should make
    /// somebody re-read that design, which is what a failing build is for. `Tools/build_seed.py`
    /// rebuilds this file from a live city export, so none of it is under this repo's control.
    ///
    /// Every number here was measured against the shipped seed, not carried in from a document.
    /// Several documents still quote the San-Francisco-only figures (145,837 rows, 12,518 vacant
    /// sites, 6.4 %); see `ERRATA E206`.
    @Test("the seed still looks like the inventory the year and site filters were designed against")
    func plantingDateCoverageIsWhatTheDecadeBucketsWereBuiltFor() async throws {
        let store = try await Self.store()
        let counts = try await store.queue.read { connection -> (Int, Int, Int, Int) in
            let statement = try connection.cachedStatement("""
            SELECT COUNT(*) AS total,
                   SUM(planted_year IS NOT NULL) AS dated,
                   SUM(status = 'vacant_site') AS vacant,
                   SUM(status = 'vacant_site' AND planted_year IS NOT NULL) AS datedVacant
              FROM \(SeedDatabase.schemaName).trees
             WHERE deleted_at IS NULL
            """)
            return try statement.fetchOne {
                (try $0.int("total"), try $0.int("dated"),
                 try $0.int("vacant"), try $0.int("datedVacant"))
            }!
        }
        let (total, dated, vacant, datedVacant) = counts
        try #require(total > 0, "the seed holds no trees at all")

        // 1 · Most rows carry no planting date, which is why the control is bucketed by decade and
        // why its blind spot was worth a sentence until R41 ruled the sentence out.
        let undatedShare = Double(total - dated) / Double(total)
        #expect(
            undatedShare > 0.75 && undatedShare < 0.85,
            "planting-date coverage moved: \(undatedShare) of \(total) rows are undated. The year filter's decade buckets were sized against roughly four in five being unjudgeable (E175, E176); re-read MapFilter.swift's header before repinning this."
        )

        // 2 · Vacant sites are a large enough share of the map to be worth their own filter (#179),
        // which is the premise ROADMAP §1 and RULINGS R7 argue from.
        let vacantShare = Double(vacant) / Double(total)
        #expect(
            vacantShare > 0.08 && vacantShare < 0.18,
            "vacant planting sites are now \(vacantShare) of \(total) rows. #179 exists because they are a large minority of the map; if this moved a lot, that argument moved."
        )

        // 3 · **The premise of task #178**: a lot of vacant sites carry a planting date, so the
        // year filter had a large wrong answer to give and the exclusion is not theoretical. If
        // this ever reaches zero the #178 predicate is untested by the seed, and
        // `aYearNarrowingReturnsNoEmptyPlantingSites` below would pass without proving anything.
        #expect(
            datedVacant > 1_000,
            "only \(datedVacant) vacant sites carry a planting year. Task #178's exclusion is measured against there being many; below this the test that guards it stops being evidence."
        )
    }

    /// **A year narrowing never returns a tree with no planting date.**
    ///
    /// This is the honest half of E175 — the predicate does what it says. The dishonest half was a
    /// surface that let the silence read as an answer; that surface is gone entirely (RULINGS R41,
    /// task #180) rather than corrected, so this predicate is now the whole of the guarantee.
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

    /// **A year narrowing never returns an empty planting site** (task #178).
    ///
    /// `yearFilterAlwaysSaysWhatItSetAside` stood here and asserted the wording of the caveat
    /// sentence R41 has since removed. What replaces it is the defect that sentence was papering
    /// over: 9,237 of the seed's 24,200 vacant sites carry a `planted_year` — the date of a tree
    /// that stood here and is gone — so `2010s` used to draw empty basins as trees planted in the
    /// 2010s. E107 refused exactly this claim one layer up, keeping `PLANTED <year>` off the site
    /// screen because it "would assert a planting on an empty basin".
    ///
    /// Read back from the seed by status rather than by asking the filter what it thinks it did.
    @Test("a year-narrowed viewport returns no empty planting sites")
    func aYearNarrowingReturnsNoEmptyPlantingSites() async throws {
        let store = try await Self.store()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let decade = MapFilter.Decade.twentyTens
        let viewport = MapViewport(
            bounds: Self.cityBounds,
            zoom: 16,
            pinLimit: MapModel.pinLimit,
            markerCellPoints: MapModel.markerCellPoints,
            plantedYears: decade.years
        )
        let answer = try Self.pins(try await api.mapContent(in: viewport))
        try #require(!answer.items.isEmpty, "the 2010s narrowing drew nothing at all over the city")

        let statuses = try await Self.statuses(of: answer.items.map(\.id), in: store)
        #expect(
            statuses.count == answer.items.count,
            "the read-back found \(statuses.count) of \(answer.items.count) drawn pins"
        )
        let vacant = statuses.filter { $0 == TreeStatus.vacantSite.rawValue }
        #expect(
            vacant.isEmpty,
            "\(vacant.count) empty planting sites were drawn under a year filter. A vacant site's planted_year is the date of a tree that is gone; returning it asserts a planting on an empty basin (task #178, E107)."
        )
    }

    // MARK: - 3b. Tree or empty planting site (task #179)

    /// **Each arm of the site filter returns only its own rows, and the two partition the map.**
    ///
    /// Asserted as facts about `trees.status` read back from the seed, never against a count this
    /// branch happened to measure: the seed is rebuilt from a live export and a pinned total would
    /// be a re-ingest away from a false red.
    @Test("the site filter's two arms return only their own rows", arguments: MapSiteKind.allCases)
    func siteKindNarrowingReturnsOnlyThatKind(_ kind: MapSiteKind) async throws {
        let store = try await Self.store()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let viewport = MapViewport(
            bounds: Self.cityBounds,
            zoom: 16,
            pinLimit: MapModel.pinLimit,
            markerCellPoints: MapModel.markerCellPoints,
            siteKind: kind
        )
        let answer = try Self.pins(try await api.mapContent(in: viewport))
        try #require(!answer.items.isEmpty, "\(kind) drew nothing at all over the city")

        let statuses = try await Self.statuses(of: answer.items.map(\.id), in: store)
        let wrong = statuses.compactMap(TreeStatus.init(rawValue:)).filter { MapSiteKind.of($0) != kind }
        #expect(
            wrong.isEmpty,
            "\(wrong.count) rows of the wrong kind were drawn under \(kind): \(Set(wrong.map(\.rawValue)))"
        )
    }

    /// **The empty-site arm actually finds the thing the app exists to point at.**
    ///
    /// Separate from the partition test above because it asserts something that test cannot: that
    /// the arm is non-empty *and* that it is finding vacant sites specifically. A predicate
    /// inverted by a typo would still partition correctly.
    @Test("the empty-site arm draws vacant sites and nothing else")
    func emptySiteArmDrawsVacantSites() async throws {
        let store = try await Self.store()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let viewport = MapViewport(
            bounds: Self.cityBounds,
            zoom: 16,
            pinLimit: MapModel.pinLimit,
            markerCellPoints: MapModel.markerCellPoints,
            siteKind: .emptySite
        )
        let answer = try Self.pins(try await api.mapContent(in: viewport))
        let statuses = try await Self.statuses(of: answer.items.map(\.id), in: store)
        try #require(!statuses.isEmpty, "the empty-site filter drew nothing over the whole city")
        #expect(
            statuses.allSatisfy { $0 == TreeStatus.vacantSite.rawValue },
            "the empty-site arm drew something other than a vacant site: \(Set(statuses))"
        )
    }

    /// **Year and site are ANDed, like every other pair of dimensions** (RULINGS R23 §1).
    ///
    /// `Empty planting site` + a decade is a contradiction after #178 — the year arm excludes
    /// vacant sites — and the honest answer is an empty map, not a silently dropped term. This
    /// pins that the conjunction is real rather than one dimension quietly winning. An empty map
    /// with no explanation is exactly what R41 and the task #165 correction to R31 call for.
    @Test("an empty-site narrowing and a decade together return nothing, rather than one winning")
    func emptySiteAndADecadeContradict() async throws {
        let store = try await Self.store()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let viewport = MapViewport(
            bounds: Self.cityBounds,
            zoom: 16,
            pinLimit: MapModel.pinLimit,
            markerCellPoints: MapModel.markerCellPoints,
            plantedYears: MapFilter.Decade.twentyTens.years,
            siteKind: .emptySite
        )
        let answer = try Self.pins(try await api.mapContent(in: viewport))
        #expect(
            answer.items.isEmpty,
            "\(answer.items.count) pins were drawn for “empty planting site, planted in the 2010s”, which after #178 is a contradiction — so one of the two terms was dropped."
        )
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

    // MARK: - 4. The result line, which no longer exists (RULINGS R41, task #180)

    // Two tests stood here: `resultLineReportsMatchesNotThePage` (E38 — a thinned answer must
    // report how many matched, not how many were drawn) and `resultLineIsNotAPersonalTotal` (D1 —
    // the number is about the map, never about the reader). Both asserted over
    // `MapFilterCopy.result`, and R41 removed the line, the formatter and the view that drew them.
    //
    // They are gone rather than rewritten because neither has a subject any more, and there is no
    // honest way to keep a test whose only remaining claim is "the string nobody builds would have
    // been fine". What they were protecting is not lost: E38's hazard is a constraint on a number
    // that is *shown*, and the map now shows none. `membershipLabelCarriesNoNumber` below survives
    // untouched, because the chip labels it guards are still on screen — and under R41 the chip is
    // the only voice a filter has, so that guard matters more than it did.
    //
    // The structural replacement is in `CypressUITests/MapFilterAccessibilityTests`:
    // `testNoTextAccompaniesAFilter` turns each narrowing on against the running app and fails if
    // any text appears beside the chips. That is the test R41 asks for by name, and it is a UI test
    // because "nothing is drawn on the map" is not a claim a unit test can make.

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
    // is labeled, because the `Clear filters` chip is the only exit left.
    @Test("the way out of any filter is a labeled control")
    func clearFiltersIsStillLabeled() {
        #expect(!MapFilterCopy.clearLabel.isEmpty)
    }

    // MARK: - 6. The filter value itself

    /// The filters compose. The owner's four are independent questions, and a row that dropped one
    /// when the reader asked another would be the single-select behavior the design replaced.
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
            case .siteKind: filter.siteKind = .emptySite
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
