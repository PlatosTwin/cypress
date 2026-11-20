import Foundation
import Testing
@testable import Cypress

/// **`LocalAPI.grove()` reads the whole set in three statements, and answers exactly what the
/// per-tree loop answered.**
///
/// The loop it replaces ran `TreeQueries.tree(id:)` **twice** per tree, over two `store.queue.read`
/// round-trips — once through `treeIfPresent` for the coordinate and once through
/// `displayNameIfPresent` for the name, after that method's cheap `activeName` miss. The same
/// 40-tree grove measured 13.2 s, 16.3 s and 21.7 s across three calibrated runs; the spread is
/// machine load, and what is stable is that the cost was linear in the size of the grove at roughly
/// a third to half a second per tree. `LocalAPI.grove()` says why the range is quoted and not one
/// of the figures.
///
/// Batching a read is where semantics get lost quietly, and this one had four rules to keep, three
/// of which are only visible on a row that is not the common case:
///
/// 1. a tree the **inventory** holds resolves there;
/// 2. a tree only **this device** added resolves against `community_trees` — that is the second arm
///    of the old `treeIfPresent`, and the arm every test that uses `addTree` goes down;
/// 3. a row whose tree resolves to **neither** is not a grove entry at all — the old `guard let …
///    else { continue }`, which is the only way a grove row can be dropped;
/// 4. the display name is the row name rule: the one active nickname, else the seed species'
///    common name, else, for a community tree, the species its profile title shows, else empty
///    (drawn as "Tree"). The community arm is the owner's answer of 2026-11-16, "Yes, use the
///    species"; before it, My Grove never named an added tree by its species.
///
/// Every name below is checked **against `displayNameIfPresent` itself**, the per-tree form the
/// Journal and the Outbox share, so the claim is a comparison rather than a restatement of what the
/// new code does. `aCommunityTreeIsNamedByItsSpeciesInMyGrove` adds the five community shapes
/// (a species; none; a nickname and a species; somebody else's cached tree with a species; a
/// withdrawn tree) and holds My Grove, the Journal and the profile title to one name for each of
/// those community trees. It does not cover a city tree with no species, whose profile title is
/// its street address while My Grove and the Journal read "Tree" (older behavior, outside the
/// owner's answers).
@Suite("My Grove · the batched read answers what the loop answered")
struct GroveBatchReadTests {

    private static let deviceID = UUID(uuidString: "9E00B47C-0000-4000-8000-000000000250")!

    /// A tree that is in nobody's inventory. Constant so a failure names the same row twice.
    private static let phantom = UUID(uuidString: "F0000000-0000-4000-8000-0000000000FF")!

    private static func openSeeded() async throws -> (api: LocalAPI, store: CypressStore) {
        let url = try #require(InventoryContractTests.seedURL, "no seed database; set CYPRESS_SEED_PATH")
        let store = try await CypressStore.inMemory(seedURL: url)
        return (LocalAPI(store: store, deviceID: deviceID), store)
    }

    /// Puts a tree in the grove the way a walk does — a visit, which is what `groveTreeIDs` reads.
    private static func visit(_ treeID: UUID, api: LocalAPI, store: CypressStore) async throws {
        let attribution = await api.attribution
        try await store.queue.write { connection in
            try ContributionStore().insert(
                Visit(treeID: treeID, attribution: attribution, capturedAt: Date()),
                connection: connection
            )
        }
    }

    private static func name(_ treeID: UUID, _ nickname: String, store: CypressStore) async throws {
        try await store.queue.write { connection in
            _ = try ContributionStore().insert(
                TreeName(treeID: treeID, name: nickname, givenBy: nil), connection: connection
            )
        }
    }

    // MARK: - The four rules, on one grove that carries a case of each

    @Test("a grove of seed trees, community trees and one unresolvable id reads exactly as it did")
    func theBatchedReadKeepsEveryRule() async throws {
        let (api, store) = try await Self.openSeeded()

        // Two real standing records out of the shipped inventory, resolved the way `DebugDeepLink`
        // resolves one — nothing here invents a seed tree id.
        let candidates = try await api.treesNear(
            Coordinate(latitude: 37.7694, longitude: -122.4862), radiusM: 900, limit: 200
        )
        let named = try #require(
            candidates.first(where: { $0.speciesCommonName != nil }),
            "no seed tree near the opening center carries a species with a common name"
        )
        let unnamed = try #require(
            candidates.first(where: { $0.speciesCommonName != nil && $0.tree.id != named.tree.id }),
            "the fixture needs two distinct seed trees with a species common name"
        )

        // Two trees this device added. `addTree` is the community arm — the one `treeIfPresent`
        // fell through to and the one a narrower batch would have dropped.
        let attribution = await api.attribution
        let communityNamed = try await api.addTree(
            TreeDraft(
                coordinate: Coordinate(latitude: 37.7695, longitude: -122.4863),
                photoLocalPath: "/tmp/cypress-grove-batch-a.jpg",
                attribution: attribution
            )
        ).id
        let communityBare = try await api.addTree(
            TreeDraft(
                coordinate: Coordinate(latitude: 37.7696, longitude: -122.4864),
                photoLocalPath: "/tmp/cypress-grove-batch-b.jpg",
                attribution: attribution
            )
        ).id

        try await Self.name(named.tree.id, "The Corner Elder", store: store)
        try await Self.name(communityNamed, "The Sapling", store: store)
        for id in [named.tree.id, unnamed.tree.id, communityNamed, communityBare, Self.phantom] {
            try await Self.visit(id, api: api, store: store)
        }

        let grove = try await api.grove()
        let byTree = Dictionary(uniqueKeysWithValues: grove.map { ($0.treeID, $0) })

        // Rule 3 first, because it is the one that decides which rows the rest are about.
        #expect(
            byTree[Self.phantom] == nil,
            "a visit to a tree neither the inventory nor this device holds became a grove entry"
        )
        #expect(
            byTree.count == 4,
            "the grove holds \(byTree.count) of the 4 resolvable trees: \(grove.map(\.treeID))"
        )

        // Rule 1 and 2 — the coordinate came from the right place for each kind of tree.
        #expect(byTree[named.tree.id]?.coordinate == named.tree.coordinate)
        #expect(byTree[unnamed.tree.id]?.coordinate == unnamed.tree.coordinate)
        #expect(
            byTree[communityBare]?.coordinate
                == Coordinate(latitude: 37.7696, longitude: -122.4864),
            "a community tree's coordinate did not survive the batch"
        )

        // Rule 4, stated three ways.
        #expect(byTree[named.tree.id]?.displayName == "The Corner Elder", "the nickname lost")
        #expect(
            byTree[unnamed.tree.id]?.displayName == unnamed.speciesCommonName,
            "a seed tree with no nickname did not fall back to its species' common name"
        )
        #expect(byTree[communityNamed]?.displayName == "The Sapling")
        #expect(
            byTree[communityBare]?.displayName == "",
            """
            a community tree with no nickname got the name '\
            \(byTree[communityBare]?.displayName ?? "<absent>")'; \
            `displayNameIfPresent` answers nil for it, which the caller spells as empty
            """
        )

        // …and every one of them against the per-tree form the Journal and the Outbox use, which
        // applies the same row name rule. A rule restated is a rule that can be restated wrong;
        // this is the comparison.
        for entry in grove {
            let perTree = (try await api.displayNameIfPresent(for: entry.treeID)) ?? ""
            #expect(
                entry.displayName == perTree,
                "\(entry.treeID): batched '\(entry.displayName)' against per-tree '\(perTree)'"
            )
        }
    }

    /// **The owner's answer of 2026-11-16, "Yes, use the species": My Grove names a community tree
    /// as its profile, the Journal and the Outbox do.** `JournalBatchReadTests`' five shapes:
    ///
    /// - an added tree with a species reads that species' common name;
    /// - an added tree with none reads "" (drawn "Tree");
    /// - an added tree with a nickname and a species reads the nickname;
    /// - somebody else's cached tree with a species, which this person visited, reads the species;
    /// - an added tree this phone withdrew leaves My Grove (the owner's earlier answer).
    ///
    /// Then, for every tree in this fixture's grove (all community trees), the title My Grove draws,
    /// the name the Journal resolves and the profile's title must be one string. A city tree with
    /// no species is outside this check: its profile title is its street address. Red-proof: in `LocalAPI.groveEntries`, drop
    /// `?? speciesNames[row.treeID]` from the name — red on "an added tree with a species read ''"
    /// and on "My Grove, the Journal and the profile disagree".
    @Test("My Grove names a community tree by its species, as the Journal and the profile do")
    func aCommunityTreeIsNamedByItsSpeciesInMyGrove() async throws {
        let (api, store) = try await Self.openSeeded()
        let candidates = try await api.treesNear(
            Coordinate(latitude: 37.7694, longitude: -122.4862), radiusM: 900, limit: 200
        )
        let source = try #require(
            candidates.first(where: { $0.speciesCommonName != nil && $0.tree.speciesCurrentID != nil }),
            "no seed tree near the opening center carries a species id and a common name"
        )
        let speciesID = try #require(source.tree.speciesCurrentID)
        let common = try #require(source.speciesCommonName)
        let attribution = await api.attribution

        func add(_ suffix: String, _ latitude: Double, species: UUID?) async throws -> UUID {
            try await api.addTree(
                TreeDraft(
                    coordinate: Coordinate(latitude: latitude, longitude: -122.4870),
                    speciesID: species,
                    photoLocalPath: "/tmp/cypress-grove-species-\(suffix).jpg",
                    attribution: attribution
                )
            ).id
        }
        let withSpecies = try await add("a", 37.7700, species: speciesID)
        let withNone = try await add("b", 37.7701, species: nil)
        let givenAndSpecies = try await add("c", 37.7702, species: speciesID)
        let withdrawn = try await add("d", 37.7703, species: speciesID)
        try await Self.name(givenAndSpecies, "The Named Plane", store: store)

        let cached = UUID(uuidString: "C0000000-0000-4000-8000-0000000002CA")!
        let stamp = SQLiteTimestamp.string(from: Date())
        try await store.queue.write { connection in
            try connection.execute("""
                INSERT INTO community_tree_cache
                    (id, lat, lon, placement, status, verification_state, species_current,
                     created_at, updated_at, tile, fetched_at)
                VALUES ('\(cached.uuidString)', 37.7704, -122.4870, 'gps', 'alive', 'unverified',
                        '\(speciesID.uuidString.lowercased())', '\(stamp)', '\(stamp)', 't', '\(stamp)');
                """)
        }
        for id in [withSpecies, withNone, givenAndSpecies, withdrawn, cached] {
            try await Self.visit(id, api: api, store: store)
        }
        try await api.withdrawTree(treeID: withdrawn)

        let grove = try await api.grove()
        let byTree = Dictionary(uniqueKeysWithValues: grove.map { ($0.treeID, $0) })
        let expected: [(UUID, String, String)] = [
            (withSpecies, common, "an added tree with a species"),
            (withNone, "", "an added tree with no species"),
            (givenAndSpecies, "The Named Plane", "an added tree with a nickname and a species"),
            (cached, common, "somebody else's cached tree with a species")
        ]
        for (id, name, what) in expected {
            #expect(byTree[id]?.displayName == name, "\(what) read '\(byTree[id]?.displayName ?? "<absent>")'")
        }
        #expect(byTree[withdrawn] == nil, "a withdrawn tree is still in My Grove")

        // One name per tree, on three surfaces: the title My Grove draws, the name the Journal and
        // the Outbox resolve (drawn "Tree" when absent), and the profile's title.
        let drawn = GroveTreesPresentation(entries: grove).rows
        let names = await api.displayNames(for: grove.map(\.treeID))
        for row in drawn {
            let journal = names[row.treeID] ?? TreeProfilePresentation.fallbackTitle
            let profile = TreeProfilePresentation(profile: try await api.treeProfile(id: row.treeID)).title
            #expect(
                row.title == journal && journal == profile,
                "My Grove, the Journal and the profile disagree on \(row.treeID): '\(row.title)', '\(journal)', '\(profile)'"
            )
        }
    }

    /// **An empty grove asks for nothing**, which is the guard the three batched statements carry
    /// and not a courtesy: `json_each('[]')` is legal but `IN ()` is not, and a set-shaped read that
    /// forgets the empty case fails on the one state every install starts in.
    @Test("a device with no contributions has an empty grove and reads nothing to find out")
    func anEmptyGroveIsEmpty() async throws {
        let (api, _) = try await Self.openSeeded()
        #expect(try await api.grove().isEmpty)
    }
}
