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
/// 4. the display name is the one active nickname, else the **seed** species' common name, else
///    empty. The second fallback is `TreeQueries`-only on purpose: `displayNameIfPresent` returns
///    nil for a community tree with no nickname even though that row may carry a self-asserted
///    species, because a self-assertion is not a name the app puts on a tree (D15).
///
/// Every name below is checked **against `displayNameIfPresent` itself**, which is untouched by
/// this round and still the per-tree implementation, so the claim is a comparison rather than a
/// restatement of what the new code does.
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

        // …and every one of them against the per-tree implementation itself, which this round did
        // not touch. A rule restated is a rule that can be restated wrong; this is the comparison.
        for entry in grove {
            let perTree = (try await api.displayNameIfPresent(for: entry.treeID)) ?? ""
            #expect(
                entry.displayName == perTree,
                "\(entry.treeID): batched '\(entry.displayName)' against per-tree '\(perTree)'"
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
