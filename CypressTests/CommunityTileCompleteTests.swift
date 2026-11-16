//
//  CommunityTileCompleteTests.swift
//  CypressTests
//
//  ROADMAP 156: a community tile counts as asked only after a pass reached its last page at least
//  once. The mark is an `app_state` row (`CommunityTreeCacheStore.completeKey(tile:)`) that the
//  refresher writes in the same transaction as the page whose `has_more` is false. The refresher's
//  helpers (`CommunityRefresherTests`, `ScriptedTileService`, `TestClock`) are defined in
//  `CommunitySyncDownTests`.
//

import Foundation
import Testing
@testable import Cypress

@Suite("Community sync down · a tile is asked only when fetched to its last page")
struct CommunityTileCompleteTests {

    private static let tile = CommunityRefresherTests.tile
    private static let box = CommunityRefresherTests.box

    private static func asked(_ store: CypressStore) async throws -> Bool {
        try await store.queue.read { connection in
            try CommunityTreeCacheStore().hasAsked(covering: Self.box, connection: connection)
        }
    }

    /// Whether the tile's complete mark is in `app_state`, read as a row, apart from `hasAsked`.
    private static func marked(_ store: CypressStore) async throws -> Bool {
        try await store.queue.read { connection in
            let statement = try connection.prepare("SELECT 1 AS present FROM app_state WHERE key = :key")
            defer { statement.finalize() }
            _ = try statement.bind(CommunityTreeCacheStore.completeKey(tile: Self.tile.path), forName: ":key")
            return try statement.fetchOne { _ in true } ?? false
        }
    }

    private static func page(_ cursor: String, hasMore: Bool) -> CommunityTilePage {
        CommunityRefresherTests.page([CommunityRefresherTests.tree()], cursor: cursor, hasMore: hasMore)
    }

    /// A pass of two pages, both served: the tile is complete.
    private static func completePass(_ refresher: CommunityTileRefresher, _ service: ScriptedTileService) async {
        await service.enqueue(Self.tile, .success(Self.page("p1", hasMore: true)))
        await service.enqueue(Self.tile, .success(Self.page("p2", hasMore: false)))
        _ = await refresher.refresh(covering: Self.box)
    }

    // MARK: - The first pass

    /// The reviewer's probe: page one of two applied, page two fails. The row is written, the tile
    /// is not complete, so the ground is not asked.
    ///
    /// Red-proof: in `CommunityTreeCacheStore.hasAsked`, drop the `AND EXISTS (... app_state ...)`
    /// clause — red on "a tile that failed after page one of two counts as asked".
    @Test("a fetch that fails after page one of two is not asked")
    func aFailureAfterPageOneIsNotAsked() async throws {
        let store = try await CypressStore.inMemory()
        let service = ScriptedTileService()
        await service.enqueue(Self.tile, .success(Self.page("p1", hasMore: true)))
        // Nothing more enqueued: the second request throws `notConnectedToInternet`.

        let outcome = await CommunityRefresherTests.make(store, service).refresh(covering: Self.box)

        #expect(outcome.ending == .stoppedOnError)
        #expect(outcome.stored == 1, "page one was not applied: \(outcome)")
        #expect(try await CommunityRefresherTests.cursor(Self.tile, store) == "p1", "page one's cursor was not stored")
        #expect(try await Self.asked(store) == false, "a tile that failed after page one of two counts as asked")
    }

    /// A pass that stops at its page limit with `has_more` still true is not asked; the next pass,
    /// from the stored cursor, reaches the last page, and then it is.
    ///
    /// Red-proof: in `CommunityTileRefresher.refresh(_:into:)`, write the mark with every page
    /// (drop the `!page.hasMore` check) — red on "a pass stopped at its page limit counts as asked".
    @Test("a pass stopped at its page limit is not asked until a later pass reaches the end")
    func thePageLimitIsNotAsked() async throws {
        let store = try await CypressStore.inMemory()
        let service = ScriptedTileService()
        let clock = TestClock()
        let refresher = CommunityRefresherTests.make(store, service, clock: clock, policy: .init(maxPagesPerTile: 2))
        await service.enqueue(Self.tile, .success(Self.page("p1", hasMore: true)))
        await service.enqueue(Self.tile, .success(Self.page("p2", hasMore: true)))
        await service.enqueue(Self.tile, .success(Self.page("p3", hasMore: false)))

        let first = await refresher.refresh(covering: Self.box)

        #expect(first.ending == .finished)
        #expect(first.tilesRefreshed == [Self.tile.path], "the pass did not count the tile as refreshed: \(first)")
        #expect(await service.calls.count == 2, "the pass did not stop at its page limit")
        #expect(try await Self.asked(store) == false, "a pass stopped at its page limit counts as asked")

        clock.advance(121)
        _ = await refresher.refresh(covering: Self.box)

        #expect(await service.calls.last?.cursor == "p2", "the next pass did not continue from the stored cursor")
        #expect(try await Self.asked(store), "a pass that reached the last page does not count as asked")
    }

    /// Two pages, both served: asked, and the mark is the row that says so.
    ///
    /// Red-proof: in `CommunityTileRefresher.refresh(_:into:)`, remove the `markComplete` call —
    /// red on "a pass that reached the last page does not count as asked".
    @Test("a pass that reaches the last page is asked")
    func aCompletePassIsAsked() async throws {
        let store = try await CypressStore.inMemory()
        let service = ScriptedTileService()
        #expect(try await Self.asked(store) == false, "a tile never fetched counts as asked")

        await Self.completePass(CommunityRefresherTests.make(store, service), service)

        #expect(try await Self.marked(store), "the last page wrote no complete mark")
        #expect(try await Self.asked(store), "a pass that reached the last page does not count as asked")
    }

    // MARK: - A delta after a complete pass

    /// A tile complete once stays asked while a later delta fails, on its first page or after one
    /// applied page, and when a delta stops at the page limit: the phone holds every tree the tile
    /// had as of the cursor that completed it.
    ///
    /// Red-proof: in `CommunityTreeCacheStore.apply`, delete the tile's complete mark — red on "a
    /// delta that failed after one page un-marked a complete tile".
    @Test("a delta that fails or stops part way does not un-mark a complete tile")
    func aFailedDeltaKeepsTheMark() async throws {
        let store = try await CypressStore.inMemory()
        let service = ScriptedTileService()
        let clock = TestClock()
        let refresher = CommunityRefresherTests.make(store, service, clock: clock, policy: .init(maxPagesPerTile: 2))
        await Self.completePass(refresher, service)
        #expect(try await Self.asked(store), "the complete pass did not count as asked")

        // A delta that fails on its first request.
        clock.advance(121)
        let offline = await refresher.refresh(covering: Self.box)
        #expect(offline.ending == .stoppedOnError)
        #expect(try await Self.asked(store), "a delta that failed on its first page un-marked a complete tile")

        // A delta that applies one page, then fails.
        await service.enqueue(Self.tile, .success(Self.page("d1", hasMore: true)))
        clock.advance(121)
        let broken = await refresher.refresh(covering: Self.box)
        #expect(broken.ending == .stoppedOnError)
        #expect(try await CommunityRefresherTests.cursor(Self.tile, store) == "d1", "the delta's page was not applied")
        #expect(try await Self.asked(store), "a delta that failed after one page un-marked a complete tile")

        // A delta that stops at the page limit.
        await service.enqueue(Self.tile, .success(Self.page("d2", hasMore: true)))
        await service.enqueue(Self.tile, .success(Self.page("d3", hasMore: true)))
        clock.advance(121)
        let limited = await refresher.refresh(covering: Self.box)
        #expect(limited.ending == .finished)
        #expect(try await CommunityRefresherTests.cursor(Self.tile, store) == "d3")
        #expect(try await Self.asked(store), "a delta stopped at its page limit un-marked a complete tile")
    }

    // MARK: - The paths that reset a tile

    /// `dropTile` is the one writer that deletes a tile's row, and the mark goes with it.
    ///
    /// Red-proof: in `CommunityTreeCacheStore.dropTile`, skip the `app_state` delete — red on "the
    /// complete mark outlived the dropped tile".
    @Test("dropping a tile drops its complete mark")
    func dropTileDropsTheMark() async throws {
        let store = try await CypressStore.inMemory()
        let service = ScriptedTileService()
        await Self.completePass(CommunityRefresherTests.make(store, service), service)
        #expect(try await Self.marked(store))

        try await store.queue.write { connection in
            _ = try CommunityTreeCacheStore().dropTile(Self.tile.path, connection: connection)
        }

        #expect(try await Self.marked(store) == false, "the complete mark outlived the dropped tile")
        #expect(try await Self.asked(store) == false)
    }

    /// A refused cursor drops the tile, and the snapshot that follows counts as asked only when it
    /// reaches its own last page.
    ///
    /// Red-proof: in `CommunityTreeCacheStore.dropTile`, skip the `app_state` delete — red on "a
    /// snapshot that failed after a refused cursor counts as asked".
    @Test("after a refused cursor, a snapshot that fails part way is not asked")
    func aRefusedCursorResetsTheMark() async throws {
        let store = try await CypressStore.inMemory()
        let service = ScriptedTileService()
        let clock = TestClock()
        let refresher = CommunityRefresherTests.make(store, service, clock: clock)
        await Self.completePass(refresher, service)

        await service.enqueue(Self.tile, .failure(APIError.validationFailed))
        await service.enqueue(Self.tile, .success(Self.page("s1", hasMore: true)))
        clock.advance(121)
        let outcome = await refresher.refresh(covering: Self.box)

        #expect(outcome.ending == .stoppedOnError)
        #expect(await service.calls.suffix(3).map(\.cursor) == ["p2", nil, "s1"])
        #expect(try await Self.asked(store) == false, "a snapshot that failed after a refused cursor counts as asked")

        await service.enqueue(Self.tile, .success(Self.page("s2", hasMore: false)))
        clock.advance(121)
        _ = await refresher.refresh(covering: Self.box)
        #expect(try await Self.asked(store), "the snapshot that reached its last page does not count as asked")
    }

    /// Sign-out and both account deletion doors leave the tile cache alone: the trees in it are
    /// other people's, and no account owns a tile. They must leave the row and the mark together,
    /// so a complete tile stays asked through each.
    ///
    /// Red-proof: in `LocalAPI.signOut`, delete the tile's row from `community_tree_cache_tiles` —
    /// red on "sign-out split a tile's row from its mark".
    @Test("sign-out and account deletion keep a tile's row and mark together", arguments: ["signOut", "leaveRecords", "eraseEverything"])
    func accountChangesKeepRowAndMarkTogether(_ door: String) async throws {
        let store = try await CypressStore.inMemory()
        let service = ScriptedTileService()
        await Self.completePass(CommunityRefresherTests.make(store, service), service)
        let api = LocalAPI(
            store: store,
            deviceID: UUID(uuidString: "D0000000-0000-4000-8000-0000000C1560")!,
            userID: UUID(uuidString: "A0000000-0000-4000-8000-0000000C1560")!
        )

        switch door {
        case "signOut": try await api.signOut()
        case "leaveRecords": _ = try await api.deleteAccount(.leaveRecords)
        default: _ = try await api.deleteAccount(.eraseEverything)
        }

        let hasRow = try await CommunityRefresherTests.cursor(Self.tile, store) != nil
        let hasMark = try await Self.marked(store)
        #expect(hasRow == hasMark, "\(door) split a tile's row from its mark: row \(hasRow), mark \(hasMark)")
        #expect(try await Self.asked(store) == (hasRow && hasMark))
    }

    /// Every statement in the app that deletes a tile's row lives in a file that also clears the
    /// complete mark, so a new reset path cannot leave a mark standing over a tile that is gone.
    ///
    /// Red-proof: add `"DELETE FROM community_tree_cache_tiles"` to a string in `LocalAPI.signOut`
    /// — red on "deletes tile rows without clearing the complete mark".
    @Test("every deletion of tile rows sits beside the complete mark's deletion")
    func everyTileDeletionClearsTheMark() throws {
        let root = AppSourceLiterals.repositoryRoot()
        let files = AppSourceLiterals.sourceFiles(root: root)
        #expect(files.count > 100, "the source walk found only \(files.count) files under \(root.path)")
        let deletion = try Regex("DELETE\\s+FROM\\s+(main\\.)?community_tree_cache_tiles\\b")
        var deleters: [String] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            guard text.contains(deletion) else { continue }
            deleters.append(file.lastPathComponent)
            #expect(
                text.contains("completeKey(tile:"),
                "\(file.lastPathComponent) deletes tile rows without clearing the complete mark"
            )
        }
        // The calibration: the one deleter there is today is found.
        #expect(deleters == ["CommunityTreeCacheStore.swift"], "tile rows are deleted in \(deleters)")
    }
}
