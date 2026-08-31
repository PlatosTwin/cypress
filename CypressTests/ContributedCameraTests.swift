import Foundation
import Testing
@testable import Cypress

/// **The camera `See them all on the map` opens screen 01 on.**
///
/// The owner, trying build 63: the link "should center the map on where the trees are; right now it
/// just takes you to the map, and if you're nowhere near a city it shows blank. It should be
/// centered on the city where you have the most trees." ERRATA E287 recorded the old behavior as a
/// deferral — "the link keeps the remembered viewport, so trees in the set can be off screen" — and
/// this suite is what replaces it.
///
/// ── Two halves, because there are two ways to get this wrong ─────────────────────────────────
/// The **policy** half is pure: given the reader's trees, which one city and what box. It needs no
/// database and every case below is reachable by writing three structs, including the ones a seed
/// cannot produce (a tie, a tree in no city at all).
///
/// The **read** half needs the real seed, for `SeeAllOnMapTests`' reason: every tree a reader can
/// reach is a seed row, and a test that never opens the seed cannot tell a query that works from
/// one that only works on the rows this app wrote. It is also the only place the two cities are
/// real — the bundled inventory is fused across `sf` and `us-ca-sj` under one attached schema, with
/// membership carried by `trees.id_space` and no `city_id` column (`CityQueries`' header).
@Suite("See them all on the map · the camera")
struct ContributedCameraTests {

    private static let deviceID = UUID(uuidString: "CA3E0000-0000-4000-8000-0000000000C1")!

    private static func attribution() -> Attribution {
        Attribution(userID: nil, deviceID: deviceID)
    }

    private static func store() async throws -> CypressStore {
        let seedURL = try #require(SeedContractTests.seedURL, "no seed database; set CYPRESS_SEED_PATH")
        return try await CypressStore.inMemory(seedURL: seedURL)
    }

    /// Real tree uuids from one city of the fused bundle, with their coordinates.
    ///
    /// Ordered by `id` rather than by distance to anything, so the rows are the same on every run
    /// and this fixture cannot drift the way `DebugDeepLink`'s nearest-N slots can (PR #130 review,
    /// F5).
    private static func seedTrees(
        idSpace: String, limit: Int, store: CypressStore
    ) async throws -> [(id: UUID, coordinate: Coordinate)] {
        try await store.queue.read { connection in
            let statement = try connection.cachedStatement("""
            SELECT uuid AS tree_uuid, lat AS lat, lon AS lon
              FROM \(SeedDatabase.schemaName).trees
             WHERE deleted_at IS NULL AND status = 'alive' AND id_space = :space
             ORDER BY id LIMIT :limit
            """)
            _ = try statement.bind([":space": idSpace, ":limit": limit] as [String: SQLiteBindable?])
            return try statement.fetchAll { row in
                (
                    id: try row.uuid("tree_uuid"),
                    coordinate: Coordinate(
                        latitude: try row.double("lat"), longitude: try row.double("lon")
                    )
                )
            }
        }
    }

    private static func place(
        _ idSpace: String?, _ latitude: Double, _ longitude: Double, at moment: Date? = nil
    ) -> ContributedPlace {
        ContributedPlace(
            treeID: UUID(),
            idSpace: idSpace,
            coordinate: Coordinate(latitude: latitude, longitude: longitude),
            contributedAt: moment
        )
    }

    /// The box's width across its own middle, in meters — what "how far out is this camera" means
    /// in the unit `MapLayout.defaultSpanMeters` is written in.
    private static func widthM(_ box: BoundingBox) -> Double {
        let middle = (box.minLatitude + box.maxLatitude) / 2
        return Coordinate(latitude: middle, longitude: box.minLongitude)
            .distance(to: Coordinate(latitude: middle, longitude: box.maxLongitude))
    }

    // MARK: - 1 · The policy

    /// **The ruling itself.** Three trees in one city, two in another sixty kilometers away: the
    /// camera holds the three and does not stretch to reach the two.
    ///
    /// The second assertion is the one that would catch a fit over the whole set — a box holding
    /// both cities contains every coordinate, so a test that only asked "does it hold my trees"
    /// would pass against the defect this exists to prevent.
    @Test("the camera opens on the city holding the most of the reader's trees")
    func theCameraLandsOnTheCityWithTheMostTrees() throws {
        let many = [
            Self.place("sf", 37.7590, -122.4260),
            Self.place("sf", 37.7610, -122.4230),
            Self.place("sf", 37.7600, -122.4200)
        ]
        let few = [
            Self.place("us-ca-sj", 37.3290, -121.8789),
            Self.place("us-ca-sj", 37.3300, -121.8800)
        ]

        let frame = try #require(ContributedCamera.frame(for: many + few))

        for winner in many {
            #expect(
                frame.contains(winner.coordinate),
                "a tree in the winning city is off screen when the map opens"
            )
        }
        for loser in few {
            #expect(
                !frame.contains(loser.coordinate),
                """
                the camera stretched to reach a second city. The box that holds two cities is the \
                state they are in, at which no pin is a pin — narrowing to one city is the whole \
                of what makes "centered on where the trees are" producible.
                """
            )
        }
    }

    /// **A tie is broken by the most recent contribution** — this round's proposal rather than
    /// the owner's ruling, which stopped at "the city where you have the most trees". The
    /// alternative weighed and not taken was inventory size, largest first, which is
    /// `InventoryUnion.openingCenter`'s rule for the opening camera; `ContributedCamera.winner`
    /// carries the argument.
    ///
    /// Both cities hold two trees, so the count says nothing; the only thing that separates them is
    /// that the reader was in the second one yesterday and in the first one a year ago.
    @Test("two cities holding the same number are separated by where the reader was last")
    func aTieGoesToTheCityContributedToMostRecently() throws {
        let old = Date(timeIntervalSince1970: 1_700_000_000)
        let recent = old.addingTimeInterval(60 * 60 * 24 * 365)
        let stale = [
            Self.place("sf", 37.7590, -122.4260, at: old),
            Self.place("sf", 37.7610, -122.4230, at: old)
        ]
        let fresh = [
            Self.place("us-ca-sj", 37.3290, -121.8789, at: recent),
            Self.place("us-ca-sj", 37.3300, -121.8800, at: old)
        ]

        #expect(
            ContributedCamera.winner(among: stale + fresh) == .city("us-ca-sj"),
            "a tie on count did not go to the city the reader contributed to most recently"
        )
        // Reversed, so this cannot be passing on argument order.
        #expect(ContributedCamera.winner(among: fresh + stale) == .city("us-ca-sj"))
    }

    /// **A tie with nothing to separate it goes to the first group by key** — the rule, stated.
    ///
    /// `sf` sorts before `us-ca-sj`, both hold two of the reader's trees, and neither carries a
    /// date, so key 3 is the only thing deciding this.
    ///
    /// **What this test cannot do is prove key 3 is what decided it**, and two versions of it have
    /// now failed to. The first held the answer from one call and required 200 shuffles to agree
    /// with it — green against a build with key 3 deleted. The second wrote the expected winner
    /// down and was still green against that build, because with key 3 gone the answer comes out of
    /// `Dictionary` iteration order, which is a function of the **process hash seed** and not of
    /// the row order: the reviewer measured green, green, and a coin flip across three processes
    /// (PR #135 review, F2). No amount of permuting `places` can reach past a dictionary. That is
    /// `theRankingDoesNotDependOnTheOrderItIsHandedIn` below, which asks `best` directly.
    @Test("a tie with nothing to separate it opens on the first city by key")
    func aTieWithNothingToSeparateItGoesToTheFirstKey() throws {
        let places = [
            Self.place("sf", 37.7590, -122.4260),
            Self.place("sf", 37.7610, -122.4230),
            Self.place("us-ca-sj", 37.3290, -121.8789),
            Self.place("us-ca-sj", 37.3300, -121.8800)
        ]
        #expect(
            ContributedCamera.winner(among: places) == .city("sf"),
            "a tie on count and on date did not go to the first city by key"
        )
    }

    /// **The ranking's one guarantee: the order it is handed in does not reach the answer.**
    ///
    /// This is the guard `aTieWithNothingToSeparateItGoesToTheFirstKey` above could not be, and the
    /// reason it works is that it asks `ContributedCamera.best` — which takes an **array** — rather
    /// than `winner`, which builds a dictionary first. A dictionary's order is the process's, not
    /// the test's; an array's is the test's, so "permute the input" is a thing that can actually be
    /// done here.
    ///
    /// **It goes red the moment key 3 is deleted**, deterministically and in both directions:
    /// without a total order `max(by:)` keeps whichever tied standing it met first, so `[sf, sj]`
    /// answers `sf` and `[sj, sf]` answers `us-ca-sj`. One of the two `#expect`s below is then
    /// wrong on every process. That is the whole of F2's repair on the test side; the code side was
    /// to delete the redundant pre-sort, so key 3 is now the only thing holding this up.
    ///
    /// Both permutations are written out rather than shuffled: there are two, and a loop over a
    /// randomizer would make a deterministic property into a probabilistic one for no gain.
    @Test("the ranking does not depend on the order it is handed in")
    func theRankingDoesNotDependOnTheOrderItIsHandedIn() throws {
        let sanFrancisco = ContributedCamera.Standing(group: .city("sf"), count: 2, latest: nil)
        let sanJose = ContributedCamera.Standing(group: .city("us-ca-sj"), count: 2, latest: nil)

        #expect(
            ContributedCamera.best(among: [sanFrancisco, sanJose]) == .city("sf"),
            "a tie on count and date did not go to the first group by key"
        )
        #expect(
            ContributedCamera.best(among: [sanJose, sanFrancisco]) == .city("sf"),
            """
            reversing the two tied groups changed the winner, so the ranking is not a total order \
            and which city the link opens depends on the order the rows arrived in — which is the \
            process's hash seed, not the reader's trees.
            """
        )
    }

    /// **A group of one gets a camera with a street on it.**
    ///
    /// ERRATA E12 measured 120 m as the scale where San Francisco's street trees stop fusing into a
    /// mat, and `MapLayout.defaultSpanMeters` is that number; a fit with no floor would open on one
    /// pin and nothing else. The tolerance is a percent, because the box is built by
    /// `BoundingBox(around:radiusM:)` in degrees and read back in meters.
    @Test("one tree opens at the screen's own opening scale, not tighter")
    func oneTreeGetsAReadableCamera() throws {
        let frame = try #require(ContributedCamera.frame(for: [Self.place("sf", 37.7590, -122.4260)]))
        let width = Self.widthM(frame)
        #expect(
            width >= MapLayout.defaultSpanMeters * 0.99,
            """
            a single tree opened at \(Int(width)) m across, inside \
            \(Int(MapLayout.defaultSpanMeters)) m — a camera with one pin and no street to place it \
            against (ERRATA E12).
            """
        )
    }

    /// **A tree the app cannot place in a city is its own group, never pooled with another.**
    ///
    /// Reachable: a community-added tree standing further from the nearest inventoried row than
    /// `AlmanacLimits.fallbackRadiusM` resolves no `id_space`. Pooling two of those is the failure
    /// this whole type exists to prevent, one level down — the box holding a tree in Nevada and a
    /// tree in Oregon is most of the western United States.
    @Test("two trees the app can place in no city do not become one city")
    func aTreeWithNoCityIsItsOwnGroup() throws {
        let frame = try #require(
            ContributedCamera.frame(for: [
                Self.place(nil, 39.5000, -116.0000),
                Self.place(nil, 44.0000, -120.5000)
            ])
        )
        #expect(
            Self.widthM(frame) < MapLayout.defaultSpanMeters * 2,
            """
            the camera opened \(Int(Self.widthM(frame))) m across over two trees in no city, so \
            they were pooled into one group and fitted together.
            """
        )
    }

    /// **Nothing to show aims nothing**, which is the honest answer and is what the link already
    /// did. A reader whose every contributed tree is in a city pack they have since removed keeps
    /// their journal rows and has no pin the map can draw (ERRATA E287); there is no camera that
    /// shows them their trees, so this round proposes none.
    ///
    /// **It does not follow that the screen holds still, and the first version of this comment said
    /// it did** (PR #135 review, F3). `MapHomeView.fitCameraToYours()` answers a nil frame by
    /// ending its suppression and asking `centerOnUserIfNeeded()` again, which may fly the map to
    /// the reader. What is asserted here is what the ruling ratified — that the **fit** stays
    /// silent rather than inventing a plausible box — not that the map does not move.
    @Test("no places at all aims no camera")
    func nothingToShowAimsNoCamera() {
        #expect(ContributedCamera.frame(for: []) == nil)
    }

    // MARK: - 2 · The read

    /// **End to end over the real, fused seed.** Three contributions in San Francisco and one in
    /// San Jose — sixty-eight kilometers apart, in one attached inventory, told apart only by
    /// `trees.id_space` — and the camera opens on San Francisco.
    ///
    /// This is the assertion the pure one above cannot make: that `id_space` is read off the row
    /// the reader contributed to, rather than guessed from a coordinate (R28, R48).
    @Test("the camera follows the contributions to the city that holds most of them")
    func theCameraFollowsTheContributionsAcrossCities() async throws {
        let store = try await Self.store()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let sanFrancisco = try await Self.seedTrees(idSpace: "sf", limit: 3, store: store)
        let sanJose = try await Self.seedTrees(idSpace: "us-ca-sj", limit: 1, store: store)
        #expect(sanFrancisco.count == 3 && sanJose.count == 1, "the seed did not supply both cities")

        try await store.queue.write { connection in
            for tree in sanFrancisco + sanJose {
                _ = try ContributionStore().insert(
                    Visit(treeID: tree.id, attribution: Self.attribution(), capturedAt: Date()),
                    connection: connection
                )
            }
        }

        let places = try await api.contributedPlaces()
        #expect(
            Set(places.map(\.treeID)) == Set((sanFrancisco + sanJose).map(\.id)),
            "the read lost or invented a tree: \(places.count) places for four contributions"
        )

        let frame = try #require(ContributedCamera.frame(for: places))
        for tree in sanFrancisco {
            #expect(
                frame.contains(tree.coordinate),
                "a San Francisco tree the reader contributed to is off screen when the map opens"
            )
        }
        #expect(
            !frame.contains(sanJose[0].coordinate),
            "the camera stretched from San Francisco to San Jose to hold one tree"
        )
    }

    /// **A tree the inventory no longer holds cannot win the vote** — which is the whole of the
    /// removed-pack fallback, and it needed no code.
    ///
    /// `LocalAPI.contributedPlaces` resolves geometry through `TreeQueries.places(ids:)`, and an id
    /// the union does not answer for is simply absent. So a reader with four contributions in a
    /// city whose pack they have removed and one in a city they still have installed gets a camera
    /// on the second city rather than no camera and rather than the wrong one.
    ///
    /// The removed pack is stood in for by contributions on ids the seed does not carry, written
    /// straight through `ContributionStore` — which is exactly the state E287 describes: the rows
    /// survive, the inventory does not.
    @Test("contributions the installed inventory cannot place do not decide the camera")
    func aCityWithNoInstalledInventoryCannotWinTheVote() async throws {
        let store = try await Self.store()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let installed = try await Self.seedTrees(idSpace: "sf", limit: 1, store: store)
        let uninstalled = (0..<4).map { _ in UUID() }

        try await store.queue.write { connection in
            for treeID in uninstalled + installed.map(\.id) {
                _ = try ContributionStore().insert(
                    Visit(treeID: treeID, attribution: Self.attribution(), capturedAt: Date()),
                    connection: connection
                )
            }
        }

        let yours = try await api.mapMembership(.yours)
        #expect(yours.count == 5, "the journal-side set lost a row it should have kept")

        let places = try await api.contributedPlaces()
        #expect(
            Set(places.map(\.treeID)) == Set(installed.map(\.id)),
            "the camera counted \(places.count) trees, including some the map cannot draw"
        )
        let frame = try #require(ContributedCamera.frame(for: places))
        #expect(frame.contains(installed[0].coordinate))
    }

    /// **A tree the reader added counts, and its city is resolved rather than assumed.**
    ///
    /// `community_trees` carries no `id_space` — the column belongs to the inventory files — so a
    /// community tree standing among San Francisco's street trees has to be placed by asking the
    /// nearest inventoried row which city it is in (`CityQueries.resolveIDSpace`). Without that it
    /// would be its own group, and a reader whose contributions are three added trees on one block
    /// would get a camera on one of them.
    @Test("a tree the reader added is placed in the city it stands in")
    func aCommunityTreeIsPlacedByItsNeighbors() async throws {
        let store = try await Self.store()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let neighbor = try await Self.seedTrees(idSpace: "sf", limit: 1, store: store)[0]
        let added = Tree(source: .community, coordinate: neighbor.coordinate)

        try await store.queue.write { connection in
            _ = try CommunityTreeStore().insert(added, clientUUID: UUID(), connection: connection)
        }

        let places = try await api.contributedPlaces()
        let mine = try #require(
            places.first { $0.treeID == added.id },
            "a tree this device added is not among the places the camera counts"
        )
        #expect(
            mine.idSpace == "sf",
            """
            an added tree standing on top of a San Francisco street tree resolved \
            \(mine.idSpace ?? "no city"), so it would be its own group and the camera would open \
            on it alone whatever else the reader has.
            """
        )
    }
}
