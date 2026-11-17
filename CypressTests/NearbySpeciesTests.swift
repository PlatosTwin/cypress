#if DEBUG
import Foundation
import Testing
@testable import Cypress

/// **An added tree's nearby record carries the species its profile title shows** (the owner's
/// answer of 2026-11-16, "Yes, show the species", ROADMAP chip 205).
///
/// Three lists read `LocalAPI.treesNear` and show species only: the "What tree is this?" shortlist
/// (`VisitCandidate.displayName`), the Add this tree "ALREADY ON RECORD" note
/// (`VisitAddTreeCopy.candidateName`), and a site's neighbor line (`SiteCopy.neighborTitle`).
/// Before this change `treesNear` gave every added tree no species, so all three read
/// "Unidentified tree" (the site line: "Unidentified") even when the profile named a species.
///
/// Every tree here stands at sea, west of Ocean Beach, where the street inventory has no rows, so
/// each list holds community trees only.
@Suite("Nearby lists · an added tree reads the species its profile shows")
struct NearbySpeciesTests {

    private static let spot = OthersTreeControlsTests.spot
    private static let radiusM: Double = 60

    private static func open() async throws -> (api: LocalAPI, store: CypressStore) {
        let store = try await OthersTreeControlsTests.seededStore()
        return (LocalAPI(store: store, deviceID: OthersTreeControlsTests.readerDevice), store)
    }

    /// A point `meters` north of the spot, so each tree in a fixture has its own place.
    private static func north(_ meters: Double) -> Coordinate {
        Coordinate(latitude: spot.latitude + meters / 111_320, longitude: spot.longitude)
    }

    private static func near(_ api: LocalAPI) async throws -> [UUID: NearbyTree] {
        let rows = try await api.treesNear(spot, radiusM: radiusM, limit: 50)
        return Dictionary(rows.map { ($0.tree.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private static func name(_ treeID: UUID, _ given: String, store: CypressStore) async throws {
        try await store.queue.write { connection in
            _ = try ContributionStore().insert(
                TreeName(treeID: treeID, name: given, givenBy: nil), connection: connection
            )
        }
    }

    /// The three list titles for one record.
    private static func titles(_ nearby: NearbyTree) -> [String] {
        [
            VisitCandidate(nearby: nearby).displayName,
            VisitAddTreeCopy.candidateName(nearby),
            SiteCopy.neighborTitle(nearby)
        ]
    }

    // MARK: - The record

    /// Red-proof: in `LocalAPI.treesNear`, set `speciesCommonName` to nil for added rows — red on
    /// "this phone's tree with a species carried common name nil".
    @Test("this phone's tree with a species carries both names; one with none carries neither")
    func ownTrees() async throws {
        let (api, _) = try await Self.open()
        let plane = try await OthersTreeControlsTests.plane(api)
        let withSpecies = try await OthersTreeControlsTests.add(
            api, device: OthersTreeControlsTests.readerDevice, at: Self.north(5), species: plane.id
        ).id
        let bare = try await OthersTreeControlsTests.add(
            api, device: OthersTreeControlsTests.readerDevice, at: Self.north(10)
        ).id

        let rows = try await Self.near(api)
        let named = try #require(rows[withSpecies], "the tree with a species is not in the list")
        #expect(
            named.speciesCommonName == plane.commonName,
            "this phone's tree with a species carried common name \(String(describing: named.speciesCommonName))"
        )
        #expect(named.speciesScientificName == plane.scientificName)
        #expect(Self.titles(named) == [plane.commonName, plane.commonName, plane.commonName])

        let none = try #require(rows[bare], "the bare tree is not in the list")
        #expect(none.speciesCommonName == nil && none.speciesScientificName == nil)
        #expect(
            Self.titles(none) == ["Unidentified tree", "Unidentified tree", SiteCopy.unidentified],
            "a tree with no species read \(Self.titles(none))"
        )
    }

    /// Red-proof: in `LocalAPI.treesNear`, give cached rows no species (`isAddedHere ? … : nil`) —
    /// red on "somebody else's tree with a species carried …".
    @Test("somebody else's cached tree carries the species the cache holds")
    func cachedTree() async throws {
        let (api, _) = try await Self.open()
        let plane = try await OthersTreeControlsTests.plane(api)
        let cached = try await OthersTreeControlsTests.cached(api, species: plane.id, at: Self.north(5))

        let row = try #require(try await Self.near(api)[cached], "the cached tree is not in the list")
        #expect(
            row.speciesCommonName == plane.commonName,
            "somebody else's tree with a species carried \(String(describing: row.speciesCommonName))"
        )
        #expect(row.speciesScientificName == plane.scientificName)
    }

    /// **A cached tree the reader named reads the reader's species while the naming is in force**,
    /// as its profile does, although the cache still holds none.
    ///
    /// Red-proof: in `LocalAPI.treesNear`, read `row.tree.speciesCurrentID` instead of
    /// `communityShownSpecies` — red on "the cached tree the reader named carried …".
    @Test("a cached tree the reader named carries the reader's species, as its profile does")
    func cachedTreeTheReaderNamed() async throws {
        let (api, _) = try await Self.open()
        try await OthersTreeControlsTests.signIn(api)
        let plane = try await OthersTreeControlsTests.plane(api)
        let cached = try await OthersTreeControlsTests.cached(api, species: nil, at: Self.north(5))
        _ = try await api.claimSpecies(treeID: cached, speciesID: plane.id)

        let profile = try await api.treeProfile(id: cached)
        #expect(profile.species?.id == plane.id, "calibration: the profile does not show the reader's naming")

        let row = try #require(try await Self.near(api)[cached], "the cached tree is not in the list")
        #expect(
            row.speciesCommonName == plane.commonName,
            "the cached tree the reader named carried \(String(describing: row.speciesCommonName))"
        )
    }

    /// **A given name is never a list title.** These lists show species only; the owner's answer
    /// does not change that.
    @Test("a given name is not used: the species stays the title, and a bare tree stays unidentified")
    func givenNamesAreNotUsed() async throws {
        let (api, store) = try await Self.open()
        let plane = try await OthersTreeControlsTests.plane(api)
        let withSpecies = try await OthersTreeControlsTests.add(
            api, device: OthersTreeControlsTests.readerDevice, at: Self.north(5), species: plane.id
        ).id
        let bare = try await OthersTreeControlsTests.add(
            api, device: OthersTreeControlsTests.readerDevice, at: Self.north(10)
        ).id
        try await Self.name(withSpecies, "Grandmother Plane", store: store)
        try await Self.name(bare, "The Stranger", store: store)
        #expect(
            try await api.displayNameIfPresent(for: bare) == "The Stranger",
            "calibration: the given name is not in force"
        )

        let rows = try await Self.near(api)
        let named = try #require(rows[withSpecies])
        let none = try #require(rows[bare])
        #expect(Self.titles(named) == [plane.commonName, plane.commonName, plane.commonName], "\(Self.titles(named))")
        #expect(
            Self.titles(none) == ["Unidentified tree", "Unidentified tree", SiteCopy.unidentified],
            "a given name reached a species-only list: \(Self.titles(none))"
        )
    }

    // MARK: - The distinguisher

    /// **The shortlist's "Tell them apart" banner does not use an added tree's species.** The owner's
    /// answer of 2026-11-16 put that species in the card's title; the banner keeps to inventory data
    /// (`VisitDistinguisher`'s header), so any pair that includes an added tree gets the banner it
    /// got before the title changed: the answer for the same pair with the added tree's species
    /// taken away. Two city trees of different species are still told apart by species.
    ///
    /// Red-proof: remove the `source != .community` guard in `VisitDistinguisher`'s `.species`
    /// case — red on "an added tree's species reached the banner".
    @Test("the banner reads as before for a pair with an added tree, and by species for two city trees")
    func theDistinguisher() async throws {
        let (api, _) = try await Self.open()
        let plane = try await OthersTreeControlsTests.plane(api)
        let oak = try await OthersTreeControlsTests.oak(api, besides: plane)
        let device = OthersTreeControlsTests.readerDevice

        // Two city trees with different species, on a street in the Inner Sunset. Neither may carry
        // a curated tell (some seed species do), because a tell is the banner's first step and
        // would answer before the species step this test is about.
        let street = Coordinate(latitude: 37.7600, longitude: -122.4750)
        let city = try await api.treesNear(street, radiusM: 80, limit: 200)
            .filter { $0.tree.source != .community && $0.speciesScientificName != nil && $0.tell == nil }
        let cityA = try #require(
            city.first { $0.speciesScientificName != plane.scientificName },
            "no city tree with a species near the street"
        )
        let cityB = try #require(
            city.first { $0.speciesScientificName != nil && $0.speciesScientificName != cityA.speciesScientificName },
            "no second city species near the street"
        )

        // Added trees: a plane on the city tree's spot, an oak, and one with no species.
        let planeOnStreet = try await OthersTreeControlsTests.add(
            api, device: device, at: cityA.tree.coordinate, species: plane.id
        ).id
        let planeA = try await OthersTreeControlsTests.add(api, device: device, at: Self.north(4), species: plane.id).id
        let oakTree = try await OthersTreeControlsTests.cached(api, species: oak.id, at: Self.north(12))
        let bare = try await OthersTreeControlsTests.add(api, device: device, at: Self.north(16)).id

        var rows = try await Self.near(api)
        for row in try await api.treesNear(street, radiusM: 80, limit: 200) { rows[row.tree.id] = row }
        func candidate(_ id: UUID) throws -> VisitCandidate { VisitCandidate(nearby: try #require(rows[id])) }

        /// The record as `treesNear` gave it on main: an added tree carried no species.
        func onMain(_ candidate: VisitCandidate) -> VisitCandidate {
            guard candidate.tree.source == .community else { return candidate }
            return VisitCandidate(nearby: NearbyTree(
                tree: candidate.tree, distanceM: candidate.distanceM,
                speciesScientificName: nil, speciesCommonName: nil, tell: candidate.tell
            ))
        }
        func banner(_ a: VisitCandidate, _ b: VisitCandidate) -> String {
            guard let traits = VisitDistinguisher.traits(a, b) else { return VisitDistinguisher.indistinguishableCopy }
            return "\(traits.first.dimension): \(traits.first.value) / \(traits.second.value)"
        }

        // Calibration: the added trees really carry a species now, so the guard is what is tested.
        #expect(try candidate(planeA).nearby.speciesScientificName == plane.scientificName)
        #expect(try candidate(planeOnStreet).nearby.speciesScientificName == plane.scientificName)

        let pairs: [(String, VisitCandidate, VisitCandidate)] = [
            ("an added plane beside a city tree", try candidate(planeOnStreet), try candidate(cityA.tree.id)),
            ("two added trees of different species", try candidate(planeA), try candidate(oakTree)),
            ("an added tree with a species beside one without", try candidate(planeA), try candidate(bare))
        ]
        for (label, a, b) in pairs {
            let now = banner(a, b)
            #expect(
                now == banner(onMain(a), onMain(b)),
                "an added tree's species reached the banner for \(label): '\(now)'"
            )
            #expect(!now.hasPrefix(VisitDistinguisher.Dimension.species.label), "\(label): '\(now)'")
        }

        let cities = try #require(VisitDistinguisher.traits(VisitCandidate(nearby: cityA), VisitCandidate(nearby: cityB)))
        #expect(
            cities.first.dimension == VisitDistinguisher.Dimension.species.label,
            "two city trees of different species were told apart by '\(cities.first.dimension)'"
        )
        #expect(cities.first.isRedundantWithCard, "the species trait is the card's own title")
    }

    // MARK: - The list and the profile agree

    /// **For every added tree in range, the three list titles name the species the profile names**,
    /// and a tree whose profile has no species reads as unidentified in all three. Over this phone's
    /// own trees, a cached tree, and a cached tree the reader named, so the overlay is in the set.
    ///
    /// Red-proof: in `LocalAPI.communityShownSpecies`, skip the `treesWithAClaim` loop — red on "the
    /// lists say … and the profile says Sycamore, London Plane".
    @Test("each list's species and the profile's species are the same for the same tree")
    func theListsAndTheProfileAgree() async throws {
        let (api, _) = try await Self.open()
        try await OthersTreeControlsTests.signIn(api)
        let plane = try await OthersTreeControlsTests.plane(api)
        let oak = try await OthersTreeControlsTests.oak(api, besides: plane)
        let device = OthersTreeControlsTests.readerDevice
        var ids: [UUID] = []
        ids.append(try await OthersTreeControlsTests.add(api, device: device, at: Self.north(4), species: plane.id).id)
        ids.append(try await OthersTreeControlsTests.add(api, device: device, at: Self.north(8)).id)
        ids.append(try await OthersTreeControlsTests.cached(api, species: oak.id, at: Self.north(12)))
        ids.append(try await OthersTreeControlsTests.cached(api, species: nil, at: Self.north(16)))
        let claimed = try await OthersTreeControlsTests.cached(api, species: nil, at: Self.north(20))
        _ = try await api.claimSpecies(treeID: claimed, speciesID: plane.id)
        ids.append(claimed)

        let rows = try await Self.near(api)
        var withSpecies = 0
        for id in ids {
            let row = try #require(rows[id], "tree \(id) is not in the list")
            let profile = try await api.treeProfile(id: id)
            let expected = profile.species.map { [$0.commonName, $0.commonName, $0.commonName] }
                ?? ["Unidentified tree", "Unidentified tree", SiteCopy.unidentified]
            if profile.species != nil { withSpecies += 1 }
            #expect(
                Self.titles(row) == expected,
                """
                the lists say \(Self.titles(row)) and the profile says \
                \(profile.species?.commonName ?? "no species") for tree \(id)
                """
            )
        }
        // Calibration: the fixture holds trees with and without a species.
        #expect(withSpecies == 3, "the fixture has \(withSpecies) trees with a species, not 3")
    }
}

/// **What `treesNear` runs, counted from inside the database** (`StatementCensus`).
///
/// Before the owner's answer of 2026-11-16, two statements in two queue reads, whatever the list
/// held: the seed's nearest trees and the community layer's box. Now up to two more, once per call,
/// only when a community tree is in range: the claim check when one is somebody else's cached tree,
/// and the species' names when one has a species. A cached tree the reader named or corrected adds
/// `localSpeciesAnswers`' statements for that tree only.
@Suite("Nearby lists · what treesNear runs")
struct NearbyStatementCensusTests {

    /// A street in the Inner Sunset with city trees on it, so the city read has rows to return.
    private static let center = Coordinate(latitude: 37.7600, longitude: -122.4750)

    private static func open() async throws -> (api: LocalAPI, store: CypressStore) {
        let store = try await OthersTreeControlsTests.seededStore()
        return (LocalAPI(store: store, deviceID: OthersTreeControlsTests.readerDevice), store)
    }

    private static func point(_ index: Int) -> Coordinate {
        Coordinate(
            latitude: center.latitude + Double(index % 10) * 0.00003,
            longitude: center.longitude + Double(index / 10) * 0.00003
        )
    }

    private static func census(
        _ store: CypressStore,
        _ read: () async throws -> [NearbyTree]
    ) async throws -> (rows: [NearbyTree], census: StatementCensus) {
        let census = StatementCensus()
        await store.queue.installCensus(census)
        let rows = try await read()
        await store.queue.installCensus(nil)
        return (rows, census)
    }

    private static func histogram(_ statements: [String]) -> String {
        Dictionary(grouping: statements, by: { $0 })
            .map { entry -> String in
                let head = entry.key.components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .first(where: { !$0.isEmpty }) ?? "<empty>"
                return "\(entry.value.count)× \(head) […\(entry.key.count) chars]"
            }
            .sorted()
            .joined(separator: "; ")
    }

    /// Red-proof: in `LocalAPI.treesNear`, resolve each added tree's species with its own
    /// `names(ids: [species])` call — red on the count for fifty added trees.
    @Test("city trees only: two statements; fifty added and two cached trees with species: four")
    func theCountIsFixedPerCall() async throws {
        let (api, store) = try await Self.open()
        let schema = try #require(store.seed, "the store opened without a seed attached")
        let names = SpeciesQueries(schema: schema).commonNamesSQL()

        let cityOnly = try await Self.census(store) {
            try await api.treesNear(Self.center, radiusM: 60, limit: 500)
        }
        try #require(!cityOnly.rows.isEmpty, "no city tree near the center; the fixture is vacuous")
        #expect(cityOnly.census.readCount == 2, "city trees only made \(cityOnly.census.readCount) hops")
        #expect(
            cityOnly.census.statements.count == 2,
            "city trees only ran \(cityOnly.census.statements.count) statements: \(Self.histogram(cityOnly.census.statements))"
        )
        #expect(cityOnly.census.statements.contains(CommunityLayer.inBoundsSQL))

        let plane = try await OthersTreeControlsTests.plane(api)
        let oak = try await OthersTreeControlsTests.oak(api, besides: plane)
        var added: [UUID] = []
        for index in 0..<50 {
            added.append(try await OthersTreeControlsTests.add(
                api, device: OthersTreeControlsTests.readerDevice, at: Self.point(index),
                species: index.isMultiple(of: 2) ? plane.id : oak.id
            ).id)
        }
        let cached = [
            try await OthersTreeControlsTests.cached(api, species: plane.id, at: Self.point(51)),
            try await OthersTreeControlsTests.cached(api, species: oak.id, at: Self.point(52))
        ]

        let mixed = try await Self.census(store) {
            try await api.treesNear(Self.center, radiusM: 60, limit: 500)
        }
        // The scientific name, which every species has; the oak the catalog answers may have no
        // common name.
        let carried = mixed.rows.filter { (added + cached).contains($0.tree.id) && $0.speciesScientificName != nil }
        try #require(carried.count == 52, "the list carried a species for \(carried.count) of the 52 added trees")
        #expect(mixed.census.readCount == 2, "the list made \(mixed.census.readCount) hops")
        #expect(
            mixed.census.statements.count == 4,
            "the list ran \(mixed.census.statements.count) statements, not 4: \(Self.histogram(mixed.census.statements))"
        )
        #expect(
            Set([CommunityLayer.inBoundsSQL, SpeciesAssertionStore.treesWithAClaimSQL, names])
                .isSubset(of: Set(mixed.census.statements)),
            "the list did not run the claim check and the names: \(Self.histogram(mixed.census.statements))"
        )
    }

    /// **The per-tree step, measured.** Each cached tree the reader named runs `localSpeciesAnswers`
    /// for that tree, the cost the row names already pay (`LocalAPI.resolvedDisplayNames`). Pinned
    /// so a change to that cost is seen here.
    @Test("each cached tree the reader named adds the overlay's statements for that tree only")
    func theOverlayCostsPerClaimedTree() async throws {
        let (api, store) = try await Self.open()
        try await OthersTreeControlsTests.signIn(api)
        let plane = try await OthersTreeControlsTests.plane(api)
        var claimed: [UUID] = []
        for index in 0..<2 {
            let id = try await OthersTreeControlsTests.cached(api, species: nil, at: Self.point(index))
            _ = try await api.claimSpecies(treeID: id, speciesID: plane.id)
            claimed.append(id)
        }
        let one = try await Self.census(store) {
            try await api.treesNear(Self.point(0), radiusM: 1, limit: 200)
        }
        try #require(
            one.rows.filter { claimed.contains($0.tree.id) }.count == 1,
            "the 1 m read held \(one.rows.filter { claimed.contains($0.tree.id) }.count) claimed trees, not 1"
        )
        let both = try await Self.census(store) {
            try await api.treesNear(Self.center, radiusM: 60, limit: 500)
        }
        try #require(
            both.rows.filter { claimed.contains($0.tree.id) && $0.speciesCommonName == plane.commonName }.count == 2,
            "the list did not carry the reader's species on both claimed trees"
        )
        let perTree = both.census.statements.count - one.census.statements.count
        #expect(both.census.readCount == 2 && one.census.readCount == 2)
        #expect(
            one.census.statements.count == 7 && perTree == 3,
            """
            one claimed tree ran \(one.census.statements.count) statements (\(Self.histogram(one.census.statements))); \
            two ran \(both.census.statements.count), so \(perTree) per claimed tree
            """
        )
    }
}
#endif
