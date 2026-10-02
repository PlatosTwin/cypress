import Foundation
import Testing
@testable import Cypress

/// The community layer read as one set — the trees this phone added and other people's from the
/// service — with one tree per id, and the cache that holds the second half (`AppSchema` v23).
///
/// The one-id rule is the whole of it: a tree this phone added and the same tree served back by a
/// tile are one tree, and the service spells its ids in lowercase where this phone spells them in
/// uppercase. So every case below that can be written with a lowercase cached id is.
@Suite("Community trees · the merged layer and its cache")
struct CommunityLayerTests {

    private typealias Fixture = LocationCorrectionTests

    private static func cacheRowCount(_ store: CypressStore) async throws -> Int {
        try await store.queue.read { connection in
            let statement = try connection.prepare("SELECT COUNT(*) AS n FROM community_tree_cache")
            defer { statement.finalize() }
            return try statement.fetchOne { try $0.int("n") } ?? -1
        }
    }

    /// A cached row written as the service would spell it: lowercase id.
    private static func cacheLowercase(
        _ id: UUID,
        at coordinate: Coordinate,
        _ store: CypressStore
    ) async throws {
        let stamp = SQLiteTimestamp.string(from: Date())
        try await store.queue.write { connection in
            try connection.execute("""
                INSERT INTO community_tree_cache
                    (id, lat, lon, placement, status, verification_state, created_at, updated_at,
                     tile, fetched_at)
                VALUES ('\(id.uuidString.lowercased())', \(coordinate.latitude), \(coordinate.longitude),
                        'gps', 'alive', 'unverified', '\(stamp)', '\(stamp)', 't', '\(stamp)');
                """)
        }
    }

    // MARK: - The schema keeps the double out

    /// Red-proof: drop `COLLATE NOCASE` from `community_tree_cache_yields_to_the_added_row`'s
    /// `WHEN` — red on the lowercase insert, "a cached copy of a tree this phone added was stored".
    @Test("a cached copy of a tree this phone added is never stored, however its id is spelled")
    func theCacheYieldsToTheAddedRow() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Fixture.deviceID)
        let tree = try await Fixture.add(api)

        try await Self.cacheLowercase(tree.id, at: Fixture.offshore, store)
        #expect(try await Self.cacheRowCount(store) == 0, "a cached copy of a tree this phone added was stored")

        let page = try await store.queue.write { connection in
            try CommunityTreeCacheStore().apply(
                tile: "t", trees: [tree], withdrawnTreeIDs: [], nextCursor: "c",
                at: Date(), connection: connection
            )
        }
        #expect(page.stored == 0, "the page reported storing the phone's own tree")
        #expect(try await Self.cacheRowCount(store) == 0)
    }

    /// Red-proof: drop the `community_trees_evict_their_cached_copy` trigger's `COLLATE NOCASE` —
    /// red on "the cached copy outlived the add".
    @Test("adding a tree evicts a cached copy of it that arrived first")
    func anAddEvictsTheCachedCopy() async throws {
        let store = try await CypressStore.inMemory()
        let id = UUID()
        try await Self.cacheLowercase(id, at: Fixture.offshore, store)
        #expect(try await Self.cacheRowCount(store) == 1, "fixture: the cached row was not stored")

        try await store.queue.write { connection in
            try CommunityTreeStore().insert(
                Tree(id: id, source: .community, coordinate: Fixture.offshore),
                clientUUID: UUID(), connection: connection
            )
        }
        #expect(try await Self.cacheRowCount(store) == 0, "the cached copy outlived the add")
    }

    // MARK: - The readers keep it out too

    /// The triggers are dropped here on purpose, so the two tables really do hold one tree twice —
    /// the state the readers must survive on their own, whatever wrote it.
    ///
    /// Red-proof: remove `AND \(notAddedHere)` from `CommunityLayer.inBoundsSQL` — red on the
    /// shortlist ("2 rows for one tree") and on the dedupe candidate count.
    @Test("a tree held twice is read once, and the phone's own row wins")
    func theReadersKeepTheDoubleOut() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Fixture.deviceID)
        let tree = try await Fixture.add(api)
        try await store.queue.write { connection in
            try connection.execute("DROP TRIGGER community_tree_cache_yields_to_the_added_row")
        }
        // Two meters off, so a reader that returned the cached copy is visibly wrong.
        let elsewhere = ProximityDedupeTests.diagonal(from: Fixture.offshore, meters: 2)
        try await Self.cacheLowercase(tree.id, at: elsewhere, store)
        #expect(try await Self.cacheRowCount(store) == 1, "fixture: the double was not written")

        let near = try await api.treesNear(Fixture.offshore, radiusM: 10, limit: 10)
        #expect(near.count == 1, "\(near.count) rows for one tree: \(near.map(\.tree.coordinate))")
        #expect(near.first?.tree.coordinate == Fixture.offshore, "the cached copy won the merge")

        let row = try await store.queue.read {
            try CommunityLayer().row(id: tree.id, connection: $0)
        }
        #expect(row?.isAddedHere == true, "the profile read the cached copy")
        #expect(row?.tree.coordinate == Fixture.offshore)

        let set = try await store.queue.read {
            try CommunityLayer().trees(ids: [tree.id], connection: $0)
        }
        #expect(set.count == 1 && set[tree.id]?.coordinate == Fixture.offshore, "\(set)")
    }

    // MARK: - Other people's trees

    @Test("somebody else's tree is on the shortlist and the profile, with no species or record controls")
    func othersTreesAreReadable() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Fixture.deviceID)
        let theirs = Tree(source: .community, coordinate: Fixture.offshore, speciesCurrentID: UUID())
        _ = try await store.queue.write { connection in
            try CommunityTreeCacheStore().apply(
                tile: "t", trees: [theirs], withdrawnTreeIDs: [], nextCursor: "c",
                at: Date(), connection: connection
            )
        }

        let near = try await api.treesNear(Fixture.offshore, radiusM: 5, limit: 5)
        #expect(near.map(\.tree.id) == [theirs.id], "the shortlist does not see the cached tree")

        let profile = try await api.treeProfile(id: theirs.id)
        #expect(profile.tree.id == theirs.id)
        #expect(profile.tree.source == .community)
        // "Others' trees: no species/report/dispute controls this round."
        #expect(profile.speciesCorrection == .unavailable, "\(profile.speciesCorrection)")
        #expect(profile.recordDefect == .unavailable, "\(profile.recordDefect)")

        // And the add dedupe sees it: a tree 5 m from somebody else's is a duplicate.
        do {
            _ = try await Fixture.add(api, at: ProximityDedupeTests.diagonal(from: Fixture.offshore, meters: 5))
            Issue.record("a tree 5 m from somebody else's published tree was added")
        } catch let conflict as ProximityConflict {
            #expect(conflict.candidates.map(\.tree.id) == [theirs.id])
        }
    }

    /// A tree this phone withdrew is not brought back by the service's copy of it.
    @Test("a withdrawn tree this phone added stays withdrawn whatever the cache is sent")
    func aWithdrawnTreeStaysWithdrawn() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Fixture.deviceID)
        let tree = try await Fixture.add(api)
        _ = try await store.queue.write { connection in
            try CommunityTreeStore().withdraw(treeID: tree.id, at: Date(), connection: connection)
        }
        let page = try await store.queue.write { connection in
            try CommunityTreeCacheStore().apply(
                tile: "t", trees: [tree], withdrawnTreeIDs: [], nextCursor: "c",
                at: Date(), connection: connection
            )
        }
        #expect(page.stored == 0)
        let near = try await api.treesNear(Fixture.offshore, radiusM: 5, limit: 5)
        #expect(near.isEmpty, "a withdrawn tree came back through the cache")
        // The profile treats a withdrawn tree as no tree at all (task #125), so the proof that the
        // phone's own row still wins is the layer's read, which does not filter a withdrawal.
        let row = try await store.queue.read { try CommunityLayer().row(id: tree.id, connection: $0) }
        #expect(row?.isAddedHere == true && row?.tree.deletedAt != nil, "\(String(describing: row))")
    }

    // MARK: - The cache store's own contract

    /// `server/testdata/README.md`'s rules, one page at a time.
    ///
    /// Red-proofs: scope `remove(ids:)` to the page's tile — red on "a removal reported by another
    /// tile left the tree standing"; make `dropTile` delete only the cursor — red on the tree count.
    @Test("a page lands whole, a removal reaches the whole cache, and a dropped tile takes its trees with it")
    func theCacheStoreKeepsItsContract() async throws {
        let store = try await CypressStore.inMemory()
        let a = Tree(source: .community, coordinate: Fixture.offshore)
        let b = Tree(
            source: .community,
            coordinate: ProximityDedupeTests.diagonal(from: Fixture.offshore, meters: 50)
        )
        let city = Tree(source: .cityImport, coordinate: Fixture.offshore)

        let first = try await store.queue.write { connection in
            try CommunityTreeCacheStore().apply(
                tile: "t1", trees: [a, b, city], withdrawnTreeIDs: [], nextCursor: "c1",
                at: Date(), connection: connection
            )
        }
        #expect(first.stored == 2, "a city row was cached, or a community one was not: \(first)")

        // A removal reported by a different tile, plus an id the cache never held.
        let second = try await store.queue.write { connection in
            try CommunityTreeCacheStore().apply(
                tile: "t2", trees: [], withdrawnTreeIDs: [a.id, UUID()], nextCursor: "c2",
                at: Date(), connection: connection
            )
        }
        #expect(second.removed == 1, "a removal reported by another tile left the tree standing: \(second)")

        let cursors = try await store.queue.read { connection in
            (
                try CommunityTreeCacheStore().cursor(tile: "t1", connection: connection),
                try CommunityTreeCacheStore().cursor(tile: "t2", connection: connection),
                try CommunityTreeCacheStore().cursor(tile: "never", connection: connection)
            )
        }
        #expect(cursors.0 == "c1" && cursors.1 == "c2" && cursors.2 == nil, "\(cursors)")

        let dropped = try await store.queue.write { connection in
            try CommunityTreeCacheStore().dropTile("t1", connection: connection)
        }
        #expect(dropped == 1, "the dropped tile took \(dropped) trees with it")
        #expect(try await Self.cacheRowCount(store) == 0)
        let afterDrop = try await store.queue.read { connection in
            (
                try CommunityTreeCacheStore().cursor(tile: "t1", connection: connection),
                try CommunityTreeCacheStore().cursor(tile: "t2", connection: connection)
            )
        }
        #expect(afterDrop.0 == nil, "a dropped tile kept its cursor")
        #expect(afterDrop.1 == "c2", "dropping one tile touched another's cursor")
    }
}
