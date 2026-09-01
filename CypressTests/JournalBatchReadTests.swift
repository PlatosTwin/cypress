import Foundation
import Testing
@testable import Cypress

/// **`LocalAPI.journal()` reads a page's names and thumbnails in four statements, and answers
/// exactly what the per-tree loop answered.**
///
/// This is `GroveBatchReadTests` pointed at the other personal list, and it exists because the
/// defect that file was written for was never removed from here. `journal()` resolved its names
/// through `displayNames(for:)`, which was a serial `for` over the page's distinct trees — one
/// `store.queue.read` round-trip apiece, each falling through on a nickname miss to
/// `TreeQueries.tree(id:)`, the wide four-join projection `LocalAPI`'s own header calls the app's
/// most expensive single-row query. On the tab's **default** segment, on first paint and again on
/// every `Show earlier`.
///
/// Batching a read is where semantics get lost quietly. Two rules are kept here and both are only
/// visible on a row that is not the common case:
///
/// 1. the display name is the tree's one active nickname, else the **seed** species' common name,
///    else nothing — and the second fallback is `TreeQueries`-only, so a community tree with no
///    nickname is nameless even when its row carries a self-asserted species (D15);
/// 2. the nickname match is case-insensitive on `tree_uuid`, which is what `activeNamesSQL`'s
///    `COLLATE NOCASE` is for and what a `lower()` "optimization" would silently change.
///
/// Every name below is checked **against `displayNameIfPresent` itself** — untouched by this round
/// and still the per-tree implementation — so the claim is a comparison rather than a restatement
/// of what the new code does.
///
/// The thumbnails move from the unscoped `ContributionStore.heroPhotoIDs()` to the scoped
/// `heroPhotoIDs(treeIDs:attribution:)` (ERRATA E204), and the two do not answer identically in
/// every possible state. `theScopedHeroReadIsTheSameAnswerForThisDevicesOwnPhotographs` and
/// `aStrangersUnmoderatedPhotographIsNotAJournalThumbnail` are the two halves of that: the same
/// answer for every row this path can have today, and E215's rule where it differs.
@Suite("Journal · the batched read answers what the loop answered")
struct JournalBatchReadTests {

    private static let deviceID = UUID(uuidString: "9E00B47C-0000-4000-8000-000000000251")!

    /// A tree that is in nobody's inventory. Constant so a failure names the same row twice.
    private static let phantom = UUID(uuidString: "F0000000-0000-4000-8000-0000000000FE")!

    private static let moment = Date(timeIntervalSince1970: 1_780_000_000)

    /// An in-memory database needs a real directory for photo binaries — `PhotoHeroTests`
    /// `photoDirectory()`'s reason, in one line: `photoDirectory` is derived from
    /// `store.databaseURL`, which for `:memory:` resolves to the root of a read-only volume.
    private static func photoDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cypress-journal-photos-\(UUID().uuidString)", isDirectory: true)
    }

    private static func openSeeded() async throws -> (api: LocalAPI, store: CypressStore) {
        let url = try #require(InventoryContractTests.seedURL, "no seed database; set CYPRESS_SEED_PATH")
        let store = try await CypressStore.inMemory(seedURL: url)
        return (LocalAPI(store: store, deviceID: deviceID, photoDirectory: photoDirectory()), store)
    }

    /// Puts a row in the journal the way a walk does — a visit, which is one of the four kinds
    /// `ContributionStore.journal` unions.
    @discardableResult
    private static func visit(
        _ treeID: UUID,
        at capturedAt: Date = moment,
        api: LocalAPI,
        store: CypressStore
    ) async throws -> UUID {
        let attribution = await api.attribution
        let record = Visit(treeID: treeID, attribution: attribution, capturedAt: capturedAt)
        try await store.queue.write { connection in
            try ContributionStore().insert(record, connection: connection)
        }
        return record.id
    }

    private static func name(_ treeID: UUID, _ nickname: String, store: CypressStore) async throws {
        try await store.queue.write { connection in
            _ = try ContributionStore().insert(
                TreeName(treeID: treeID, name: nickname, givenBy: nil), connection: connection
            )
        }
    }

    // MARK: - The name rule, on one page carrying a case of each

    @Test("a page of seed trees, community trees and one unresolvable id names them exactly as the loop did")
    func theBatchedNameReadKeepsEveryRule() async throws {
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

        // Two trees this device added. `addTree` is the community arm — the one the seed projection
        // cannot resolve and the one rule 1's second half is about.
        let attribution = await api.attribution
        let communityNamed = try await api.addTree(
            TreeDraft(
                coordinate: Coordinate(latitude: 37.7695, longitude: -122.4863),
                photoLocalPath: "/tmp/cypress-journal-batch-a.jpg",
                attribution: attribution
            )
        ).id
        let communityBare = try await api.addTree(
            TreeDraft(
                coordinate: Coordinate(latitude: 37.7696, longitude: -122.4864),
                photoLocalPath: "/tmp/cypress-journal-batch-b.jpg",
                attribution: attribution
            )
        ).id

        try await Self.name(named.tree.id, "The Corner Elder", store: store)
        try await Self.name(communityNamed, "The Sapling", store: store)

        let trees = [named.tree.id, unnamed.tree.id, communityNamed, communityBare, Self.phantom]
        // Distinct capture times so the page's order is a fact rather than a tie-break, and two
        // visits to one tree so the "one lookup per distinct tree" claim is exercised rather than
        // trivially true.
        for (offset, id) in trees.enumerated() {
            try await Self.visit(id, at: Self.moment.addingTimeInterval(Double(offset) * 60), api: api, store: store)
        }
        try await Self.visit(named.tree.id, at: Self.moment.addingTimeInterval(600), api: api, store: store)

        let page = try await api.journal(cursor: nil, limit: JournalLimits.pageSize)
        let byTree = Dictionary(grouping: page.items, by: \.treeID)

        // Every tree that was visited has rows — including the phantom. A journal row is a record of
        // something the contributor did, and it is not conditional on the tree resolving anywhere;
        // that is the one place this list differs from the grove, where an unresolvable id is
        // dropped because a grove entry needs a coordinate.
        #expect(
            byTree[Self.phantom]?.count == 1,
            """
            a visit to a tree neither the inventory nor this device holds lost its journal row; \
            the page holds \(page.items.count) rows across \(byTree.count) trees
            """
        )
        #expect(byTree[named.tree.id]?.count == 2, "the two visits to one tree did not both survive")

        // Rule 1, stated four ways.
        #expect(
            byTree[named.tree.id]?.allSatisfy { $0.treeDisplayName == "The Corner Elder" } == true,
            "the nickname lost to the species common name"
        )
        #expect(
            byTree[unnamed.tree.id]?.first?.treeDisplayName == unnamed.speciesCommonName,
            "a seed tree with no nickname did not fall back to its species' common name"
        )
        #expect(byTree[communityNamed]?.first?.treeDisplayName == "The Sapling")
        #expect(
            byTree[communityBare]?.first?.treeDisplayName == "",
            """
            a community tree with no nickname got the name '\
            \(byTree[communityBare]?.first?.treeDisplayName ?? "<absent>")'; \
            `displayNameIfPresent` answers nil for it, which the caller spells as empty
            """
        )
        #expect(byTree[Self.phantom]?.first?.treeDisplayName == "")

        // …and every one of them against the per-tree implementation itself, which this round did
        // not touch. A rule restated is a rule that can be restated wrong; this is the comparison.
        for entry in page.items {
            let perTree = (try await api.displayNameIfPresent(for: entry.treeID)) ?? ""
            #expect(
                entry.treeDisplayName == perTree,
                "\(entry.treeID): batched '\(entry.treeDisplayName)' against per-tree '\(perTree)'"
            )
        }
    }

    /// **Rule 2: the nickname join is case-insensitive, and stays so.**
    ///
    /// `UUID`'s own `SQLiteBindable` writes Foundation's upper-case canonical string, so every row
    /// this app writes today is upper case and an exact match would pass. This plants a **lower**-case
    /// `tree_names.tree_uuid` — the one thing `activeNamesSQL`'s `COLLATE NOCASE` is there for — so
    /// that replacing the collation with an exact match, or with a one-sided `lower()`, is caught
    /// rather than looking like a free optimization.
    ///
    /// The row is written with a raw `INSERT` for `PhotoHeroTests.insertStrangersPhoto`'s reason:
    /// no write path this app ships can produce it, and the fixture has to reach past the write path
    /// to state the property the read depends on.
    @Test("a nickname stored with a lower-case tree uuid still names its journal rows")
    func theNicknameJoinIsCaseInsensitive() async throws {
        let (api, store) = try await Self.openSeeded()
        let tree = try await api.addTree(
            TreeDraft(
                coordinate: Coordinate(latitude: 37.7697, longitude: -122.4865),
                photoLocalPath: "/tmp/cypress-journal-case.jpg",
                attribution: await api.attribution
            )
        ).id
        try await Self.visit(tree, api: api, store: store)

        let stamp = SQLiteTimestamp.string(from: Self.moment)
        try await store.queue.write { connection in
            try connection.execute("""
                INSERT INTO tree_names (id, tree_uuid, name, status, created_at, updated_at)
                VALUES ('\(UUID().uuidString)', '\(tree.uuidString.lowercased())', 'The Quiet One',
                        'active', '\(stamp)', '\(stamp)')
                """)
        }

        let page = try await api.journal(cursor: nil, limit: JournalLimits.pageSize)
        #expect(
            page.items.first(where: { $0.treeID == tree })?.treeDisplayName == "The Quiet One",
            """
            a nickname whose tree_uuid is stored lower case did not reach the page. The batched \
            read's predicate is no longer case-insensitive, which changes which rows match — see \
            `ContributionStore.activeNamesSQL`
            """
        )
        // And the per-tree implementation agrees, which is what makes this a property of the rule
        // rather than of one statement.
        #expect(try await api.displayNameIfPresent(for: tree) == "The Quiet One")
    }

    /// **One unresolvable tree does not cost the others their names**, which is the difference
    /// between a batch and a batch that throws.
    ///
    /// The loop wrapped each id in `try?`; one read now answers for the whole set. The state that
    /// used to be per-row recoverable — an id no inventory holds — is the ordinary case and does not
    /// throw, so the page names everything it can. `LocalAPI.displayNames(for:)` states what does
    /// change.
    @Test("a page whose tree is in no inventory still names the others")
    func aPageWhoseTreeIsInNoInventoryStillNamesTheOthers() async throws {
        let (api, store) = try await Self.openSeeded()
        let candidates = try await api.treesNear(
            Coordinate(latitude: 37.7694, longitude: -122.4862), radiusM: 900, limit: 200
        )
        let real = try #require(
            candidates.first(where: { $0.speciesCommonName != nil }),
            "no seed tree near the opening center carries a species with a common name"
        )
        try await Self.visit(Self.phantom, at: Self.moment, api: api, store: store)
        try await Self.visit(real.tree.id, at: Self.moment.addingTimeInterval(60), api: api, store: store)

        let page = try await api.journal(cursor: nil, limit: JournalLimits.pageSize)
        #expect(
            page.items.first(where: { $0.treeID == real.tree.id })?.treeDisplayName
                == real.speciesCommonName,
            "an id in no inventory took the whole page's names down with it"
        )
    }

    /// **`displayNames(for:)` itself**, which `OutboxViewState` calls and which now shares one
    /// implementation with the page.
    @Test("displayNames answers the set exactly as displayNameIfPresent answers each id")
    func theSetFormAgreesWithThePerIDForm() async throws {
        let (api, store) = try await Self.openSeeded()
        let candidates = try await api.treesNear(
            Coordinate(latitude: 37.7694, longitude: -122.4862), radiusM: 900, limit: 200
        )
        let seedTree = try #require(candidates.first(where: { $0.speciesCommonName != nil })?.tree.id)
        let community = try await api.addTree(
            TreeDraft(
                coordinate: Coordinate(latitude: 37.7698, longitude: -122.4866),
                photoLocalPath: "/tmp/cypress-journal-set.jpg",
                attribution: await api.attribution
            )
        ).id
        try await Self.name(community, "The Set Form", store: store)

        let ids = [seedTree, community, Self.phantom]
        let batched = await api.displayNames(for: ids)
        for id in ids {
            let perID = try await api.displayNameIfPresent(for: id)
            let expected = (perID?.isEmpty == false) ? perID : nil
            #expect(
                batched[id] == expected,
                "\(id): the set form said \(batched[id] ?? "<absent>"), the per-id form \(expected ?? "<absent>")"
            )
        }
        #expect(batched[Self.phantom] == nil, "an id with no name must be absent, not present and empty")
    }

    /// **An empty page asks for nothing.** `json_each('[]')` is legal but `IN ()` is not, and a
    /// set-shaped read that forgets the empty case fails on the one state every install starts in.
    @Test("a device with no contributions has an empty journal and reads nothing to find out")
    func anEmptyJournalIsEmpty() async throws {
        let (api, _) = try await Self.openSeeded()
        let page = try await api.journal(cursor: nil, limit: JournalLimits.pageSize)
        #expect(page.items.isEmpty)
        #expect(page.nextCursor == nil)
        #expect(await api.displayNames(for: []).isEmpty)
    }

    // MARK: - The thumbnails: scoped where they were unscoped (ERRATA E204)

    /// **The same answer, for every photograph this path can have today.**
    ///
    /// `main.photos` holds what this device wrote, so every candidate a journal page has is
    /// `is_own`, and `TreeProfile.isPhotoVisible` judges an own photograph by
    /// `Photo.isVisibleToItsContributor` — `deletedAt == nil`, which is the unscoped read's entire
    /// filter. Asserted as an equality against the unscoped read rather than as a restatement of
    /// that paragraph, over a tree carrying three photographs and a vote, so the chosen id is a
    /// choice rather than the only row.
    @Test("the scoped hero read is the same answer for this device's own photographs")
    func theScopedHeroReadIsTheSameAnswerForThisDevicesOwnPhotographs() async throws {
        let (api, store) = try await Self.openSeeded()
        let tree = try await api.addTree(
            TreeDraft(
                coordinate: Coordinate(latitude: 37.7699, longitude: -122.4867),
                photoLocalPath: "/tmp/cypress-journal-hero.jpg",
                attribution: await api.attribution
            )
        ).id
        let ids = try await api.debugSeedPhotos(treeID: tree, count: 3)
        try await api.setPhotoVote(photoID: ids[2], vote: .up)
        try await Self.visit(tree, api: api, store: store)

        let unscoped = try await store.queue.read { connection in
            try ContributionStore().heroPhotoIDs(connection: connection)
        }
        try #require(
            unscoped[tree] == ids[2],
            "the fixture did not produce a chosen hero, so an equality against it proves nothing"
        )

        let page = try await api.journal(cursor: nil, limit: JournalLimits.pageSize)
        #expect(
            page.items.first(where: { $0.treeID == tree })?.heroPhotoID == unscoped[tree],
            "the scoped read the page now runs disagreed with the unscoped read it replaced"
        )
    }

    /// **And the one state where they differ, which is E215's rule and not a regression.**
    ///
    /// A photograph belonging to somebody this device has never met cannot arrive through any write
    /// path the app ships — E215 calls it latent, not live — so the row is planted with a raw
    /// `INSERT`, `PhotoHeroTests.insertStrangersPhoto`'s idiom. The unscoped read filters
    /// `deleted_at IS NULL` and nothing else, so it would hand this row to the journal as a
    /// thumbnail the day anything syncs one down. The scoped read judges it by
    /// `TreeProfile.isPhotoVisible` and withholds it.
    ///
    /// Both halves are asserted: the unscoped read really does return it (otherwise this test would
    /// pass on a fixture that proves nothing), and the page does not.
    @Test("a stranger's unmoderated photograph is not a journal thumbnail")
    func aStrangersUnmoderatedPhotographIsNotAJournalThumbnail() async throws {
        let (api, store) = try await Self.openSeeded()
        let tree = try await api.addTree(
            TreeDraft(
                coordinate: Coordinate(latitude: 37.7700, longitude: -122.4868),
                photoLocalPath: "/tmp/cypress-journal-stranger.jpg",
                attribution: await api.attribution
            )
        ).id
        // `addTree`'s own photograph is cleared, so the stranger's row is the only candidate and the
        // question is about that row alone.
        _ = try await api.debugSeedPhotos(treeID: tree, count: 0)
        try await Self.visit(tree, api: api, store: store)

        let stranger = UUID()
        let strangerOwner = UUID(uuidString: "57A4DE00-0000-4000-8000-00000000E215")!
        let stamp = SQLiteTimestamp.string(from: Self.moment)
        try await store.queue.write { connection in
            try connection.execute("""
                INSERT INTO photos
                    (id, tree_uuid, shot_type, moderation_state, captured_at, created_at, updated_at, user_id)
                VALUES ('\(stranger.uuidString)', '\(tree.uuidString)', 'full_tree', 'pending',
                        '\(stamp)', '\(stamp)', '\(stamp)', '\(strangerOwner.uuidString)')
                """)
        }

        let unscoped = try await store.queue.read { connection in
            try ContributionStore().heroPhotoIDs(connection: connection)
        }
        try #require(
            unscoped[tree] == stranger,
            """
            the unscoped read did not return the stranger's row, so this fixture cannot show that \
            the scoped read is what withholds it
            """
        )

        let page = try await api.journal(cursor: nil, limit: JournalLimits.pageSize)
        #expect(
            page.items.first(where: { $0.treeID == tree })?.heroPhotoID == nil,
            "a stranger's unmoderated photograph reached the journal — the case ERRATA E215 names"
        )
    }
}
