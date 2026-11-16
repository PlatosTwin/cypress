//
//  AddTreeNoteTests.swift
//  CypressTests
//
//  Round C3, the note under the Add this tree button and the two empty-place texts.
//
//  The owner's rulings of 2026-11-15:
//  - The note under the button says who can see the tree, by the account's sharing state. Signed
//    out and not sharing say "Only you can see it", because the phone does send such a tree to the
//    service, which keeps it private. When the phone does not know, the note stays as it was.
//  - At the accessibility text sizes the note moves into the scrolling form; only the button stays
//    pinned ("move into the scroll").
//  - The map's "No trees on record here" card and the empty "What tree is this?" list name both
//    kinds of tree the app draws: the city inventory and the trees people have added.
//
//  The words are the owner's, so the tests hold them exactly. The tests also hold the facts the
//  words claim: the state is read each time the screen appears, and an added tree, this phone's or
//  someone else's, keeps both empty texts away.
//

#if DEBUG
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Cypress

@Suite("C3 · the note under Add this tree, and the two empty places", .timeLimit(.minutes(5)))
struct AddTreeNoteTests {

    private static let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-0000000C3B01")!
    private static let userID = UUID(uuidString: "D0000000-0000-4000-8000-0000000C3B02")!
    /// Inside `CommunityRefresherTests.tile`, where no seed is attached, so nothing but the trees
    /// these tests put there is on record.
    private static let spot = CommunityRefresherTests.spot

    // MARK: - The note, by sharing state

    /// Red-proof: swap the `.signedOut` and `.notSharing` arms of `VisitAddTreeCopy.footnote(for:)`
    /// — red on both of those two expectations.
    @Test("each sharing state has the owner's sentence")
    func eachStateHasItsSentence() {
        #expect(
            VisitAddTreeCopy.footnote(for: .sharing)
                == "Recorded as community-added and unverified. Everyone using Cypress can see it once it is sent."
        )
        #expect(
            VisitAddTreeCopy.footnote(for: .signedOut)
                == "Recorded as community-added and unverified. Only you can see it. "
                + "Everyone using Cypress can see it after you sign in."
        )
        #expect(
            VisitAddTreeCopy.footnote(for: .notSharing)
                == "Recorded as community-added and unverified. Only you can see it. "
                + "Everyone using Cypress can see it after you agree to share your tree records."
        )
        // The owner, 2026-11-15: "Keep today's note" when the phone holds no answer.
        #expect(
            VisitAddTreeCopy.footnote(for: .unknown)
                == "Recorded as community-added and unverified, on this phone."
        )
    }

    /// The ruling on private property: the note does not mention it, whatever the state. The land
    /// row above the button already says it when the reader chose it.
    @Test("no sharing state's note mentions private property")
    func theNoteDoesNotMentionPrivateProperty() {
        for sharing in [ContributionSharing.sharing, .signedOut, .notSharing, .unknown] {
            let note = VisitAddTreeCopy.footnote(for: sharing).lowercased()
            #expect(!note.contains("private"), "the \(sharing) note mentions private property: \(note)")
            #expect(!note.contains("property"), "the \(sharing) note mentions private property: \(note)")
        }
    }

    // MARK: - The state is read when the screen appears

    /// The reader opens the add screen signed out, leaves, signs in and agrees to share, and opens
    /// it again. The second appearance must say what the account is now. `load()` is what the
    /// screen's `.task` runs on each appearance, and the reader is the composition root's own
    /// (`ContributionSharing.reader(local:)`) over a real `LocalAPI`.
    ///
    /// Red-proof: take `await refreshSharing()` out of `VisitAddTreeModel.load()` — red on "the
    /// first appearance read no state" (the note is nil, so the screen draws none).
    @MainActor
    @Test("a sign-in between two appearances changes the note")
    func theStateIsReadOnEachAppearance() async throws {
        let api = LocalAPI(store: try await CypressStore.inMemory(), deviceID: Self.deviceID)
        let reader = ContributionSharing.reader(local: api)

        let first = Self.model(api: api, reader: reader)
        #expect(first.sharing == nil, "the note has a state before the screen appeared")
        await first.load()
        first.stop()
        #expect(first.sharing == .signedOut, "the first appearance read no state, or the wrong one")

        try await api.linkAccount(
            deviceUUID: Self.deviceID, userID: Self.userID, provider: "apple", acceptsLicense: true
        )

        // The flow builds a new screen each time it reaches the add step; `load()` runs again.
        let second = Self.model(api: api, reader: reader)
        await second.load()
        second.stop()
        #expect(second.sharing == .sharing, "the second appearance did not see the sign-in")

        // And the same screen reads again too: `closeListedTree` calls `load()` when a listed
        // tree's profile closes, which is the one way back to this screen without rebuilding it.
        try await api.signOut()
        await second.load()
        second.stop()
        #expect(second.sharing == .signedOut, "a later appearance of the same screen kept the old state")
    }

    /// A signed-in account that declined is `.notSharing`, through the same read.
    @MainActor
    @Test("a signed-in account that declined reads as not sharing")
    func aDeclinedAccountIsNotSharing() async throws {
        let api = LocalAPI(store: try await CypressStore.inMemory(), deviceID: Self.deviceID)
        try await api.linkAccount(
            deviceUUID: Self.deviceID, userID: Self.userID, provider: "apple", acceptsLicense: false
        )
        let subject = Self.model(api: api, reader: ContributionSharing.reader(local: api))
        await subject.load()
        subject.stop()
        #expect(subject.sharing == .notSharing)
    }

    // MARK: - Where the note sits

    /// The ruling "move into the scroll": the note is pinned under the button below the
    /// accessibility sizes, and is the last row of the scrolling form at them. The decision is a
    /// function of the one fact it reads, like the other AX5 rules (`AX5ReflowTests`); the UI test
    /// `AddTreeNearbyUITests.testTheNoteMovesIntoTheFormAtTheLargestTextSize` checks the running
    /// screen.
    ///
    /// Red-proof: return `.footer` for both in `VisitAddTreeLayout.footnotePlace` — red on the
    /// accessibility sizes.
    @Test("the note is pinned below the accessibility sizes and in the form at them")
    func theNoteMovesIntoTheScrollAtAccessibilitySizes() {
        for size in DynamicTypeSize.allCases {
            let place = VisitAddTreeLayout.footnotePlace(isAccessibilitySize: size.isAccessibilitySize)
            #expect(
                place == (size.isAccessibilitySize ? .scroll : .footer),
                "at \(size) the note is in the \(place)"
            )
        }
    }

    // MARK: - The two empty places

    /// The map card's two bodies, exactly: the owner's new one where the phone asked for added
    /// trees, and the body that shipped before round C3 where it did not (the owner's answer of
    /// 2026-11-15, "Show the old text there"). `MapEmptyInventoryTests` holds the facts each must
    /// carry and the AX5 budget.
    @Test("the map card's two bodies are the owner's words, and each shows where it should")
    func theMapCardNamesBothKinds() {
        #expect(
            MapInventoryCopy.neitherHasATree
                == "Cypress draws a city street-tree inventory and trees people have added. "
                + "Neither has a tree here."
        )
        #expect(
            MapInventoryCopy.notOnTheCityInventory
                == "Cypress draws a city street-tree inventory, and this ground is not on it. "
                + "Trees may stand here without being listed."
        )
        #expect(MapInventoryCopy.message(communityAsked: true) == MapInventoryCopy.neitherHasATree)
        #expect(MapInventoryCopy.message(communityAsked: false) == MapInventoryCopy.notOnTheCityInventory)
        #expect(MapInventoryCopy.title == "No trees on record here")
    }

    // MARK: - Has this phone asked for added trees here?

    /// A tile the service answered with no trees is asked: `apply` writes the tile's row with
    /// every page, empty or not. Before the fetch it is not asked.
    ///
    /// Red-proof: in `CommunityTreeCacheStore.hasAsked`, return `fetched > paths.count` — red on
    /// "a tile served with no trees does not count as asked".
    @Test("a tile fetched with no trees counts as asked")
    func anEmptyFetchedTileIsAsked() async throws {
        let store = try await CypressStore.inMemory()
        let service = ScriptedTileService()
        await service.enqueue(CommunityRefresherTests.tile, .success(CommunityRefresherTests.page([], cursor: "c1")))
        let box = CommunityRefresherTests.box
        #expect(try await Self.asked(box, store) == false, "a tile never fetched counts as asked")

        _ = await CommunityRefresherTests.make(store, service).refresh(covering: box)

        #expect(try await Self.asked(box, store), "a tile served with no trees does not count as asked")
    }

    /// A failed fetch writes nothing, so the ground stays not asked.
    ///
    /// Red-proof: in `CommunityTreeCacheStore.hasAsked`, `return true` after the tile guard — red
    /// on "a failed fetch counts as asked".
    @Test("a failed fetch leaves the ground not asked")
    func aFailedFetchIsNotAsked() async throws {
        let store = try await CypressStore.inMemory()
        // Nothing enqueued: `ScriptedTileService` throws `notConnectedToInternet`.
        let outcome = await CommunityRefresherTests.make(store, ScriptedTileService())
            .refresh(covering: CommunityRefresherTests.box)
        #expect(outcome.ending == .stoppedOnError)
        #expect(
            try await Self.asked(CommunityRefresherTests.box, store) == false,
            "a failed fetch counts as asked"
        )
    }

    /// Every covering tile must have been fetched: one of two is not enough.
    ///
    /// Red-proof: in `CommunityTreeCacheStore.hasAsked`, return `fetched > 0` — red on "one of two
    /// tiles fetched counts as asked".
    @Test("a viewport with one covering tile never fetched is not asked")
    func everyCoveringTileMustBeFetched() async throws {
        let store = try await CypressStore.inMemory()
        let tiles = try #require(CommunityTile.covering(Self.twoTiles, limit: 16))
        #expect(tiles.count == 2, "the fixture box covers \(tiles.count) tiles, not 2")
        try await Self.fetched([tiles[0]], store)
        #expect(try await Self.asked(Self.twoTiles, store) == false, "one of two tiles fetched counts as asked")
        try await Self.fetched([tiles[1]], store)
        #expect(try await Self.asked(Self.twoTiles, store), "both tiles fetched does not count as asked")
    }

    /// More than `Policy.maxTiles` tiles is a map the refresher never asks about, so it is not
    /// asked, even with a row for every tile.
    ///
    /// Red-proof: in `CommunityTreeCacheStore.hasAsked`, cover with `limit: .max` — red on "a
    /// viewport of more than 16 tiles counts as asked".
    @Test("a viewport of more than 16 tiles is not asked, whatever the cache holds")
    func tooManyTilesIsNotAsked() async throws {
        let store = try await CypressStore.inMemory()
        let tiles = try #require(CommunityTile.covering(Self.manyTiles, limit: 10_000))
        #expect(tiles.count > CommunityTileRefresher.Policy().maxTiles, "the fixture covers only \(tiles.count) tiles")
        try await Self.fetched(tiles, store)
        #expect(
            try await Self.asked(Self.manyTiles, store) == false,
            "a viewport of more than 16 tiles counts as asked"
        )
        // The control: the same rows answer true with a limit that admits them all.
        let allowed = try await store.queue.read { connection in
            try CommunityTreeCacheStore().hasAsked(
                covering: Self.manyTiles, maxTiles: tiles.count, connection: connection
            )
        }
        #expect(allowed, "with a limit that admits every tile, the fetched rows do not count")
    }

    // MARK: - The map card picks its body

    /// The map, over ground with nothing on it, after a refresh that fetched every tile in view
    /// and found no trees: the card is owed, and it says the new body. The refresh changes no pin,
    /// so no second map read happens; the model must read the answer again when the refresh ends.
    ///
    /// Red-proof: take out the `!changed` branch in `MapModel.startCommunityRefresh` that reads the
    /// answer again — red on "the card kept the first body after every tile was fetched".
    @MainActor
    @Test("every tile fetched and nothing in view: the card says neither has a tree")
    func aFetchedEmptyViewportGetsTheNewBody() async throws {
        let store = try await CypressStore.inMemory()
        let service = ScriptedTileService()
        await service.enqueue(CommunityRefresherTests.tile, .success(CommunityRefresherTests.page([], cursor: "c1")))
        let model = Self.map(store, service: service)

        await Self.settle(model)

        #expect(model.inventoryIsEmptyHere, "the card is not owed over an empty viewport")
        #expect(
            model.inventoryNoticeMessage == MapInventoryCopy.neitherHasATree,
            "the card kept the first body after every tile was fetched: \(model.inventoryNoticeMessage)"
        )
    }

    /// The same ground, but the fetch fails: the card keeps the first body.
    @MainActor
    @Test("a failed fetch: the card keeps the first body")
    func aFailedFetchKeepsTheFirstBody() async throws {
        let store = try await CypressStore.inMemory()
        let model = Self.map(store, service: ScriptedTileService())

        await Self.settle(model)

        #expect(model.inventoryIsEmptyHere)
        #expect(
            model.inventoryNoticeMessage == MapInventoryCopy.notOnTheCityInventory,
            "a failed fetch drew the new body: \(model.inventoryNoticeMessage)"
        )
    }

    /// The remote gate shut: no refresher at all, the composition root's reader over the cache.
    /// Nothing was ever fetched, so the card says the first body.
    ///
    /// Red-proof: make `CommunityTreeCacheStore.askedReader` answer `true` — red on "with the gate
    /// shut the card drew the new body".
    @MainActor
    @Test("the remote gate shut: the card says the first body")
    func aShutGateKeepsTheFirstBody() async throws {
        let store = try await CypressStore.inMemory()
        let model = Self.map(store, service: nil)

        await Self.settle(model)

        #expect(model.inventoryIsEmptyHere)
        #expect(
            model.inventoryNoticeMessage == MapInventoryCopy.notOnTheCityInventory,
            "with the gate shut the card drew the new body: \(model.inventoryNoticeMessage)"
        )
    }

    /// Zoomed out past the refresher's limit: the card says the first body.
    @MainActor
    @Test("a viewport of more than 16 tiles: the card says the first body")
    func aWideViewportKeepsTheFirstBody() async throws {
        let store = try await CypressStore.inMemory()
        let tiles = try #require(CommunityTile.covering(Self.manyTiles, limit: 10_000))
        try await Self.fetched(tiles, store)
        let model = MapModel(
            api: LocalAPI(store: store, deviceID: Self.deviceID),
            communityAsked: CommunityTreeCacheStore.askedReader(queue: store.queue)
        )
        model.cameraDidChange(bounds: Self.manyTiles, zoom: 12)
        await TestWait.settle(model) { model.inventoryIsEmptyHere }

        #expect(model.inventoryIsEmptyHere)
        #expect(
            model.inventoryNoticeMessage == MapInventoryCopy.notOnTheCityInventory,
            "a zoomed-out map drew the new body: \(model.inventoryNoticeMessage)"
        )
    }

    /// The owner's sentence, with the number taken from the radius the list is read at.
    ///
    /// Red-proof: write `50` in place of `\(Int(VisitShortlist.searchRadiusM))` in
    /// `VisitIdentifyCopy.emptyMessage` — red on "the sentence does not state the list's radius".
    @Test("the empty list names both kinds and states its own radius")
    func theEmptyListNamesBothKinds() {
        let radius = Int(VisitShortlist.searchRadiusM)
        #expect(
            VisitIdentifyCopy.emptyMessage.contains("within \(radius) m of you"),
            "the sentence does not state the list's radius (\(radius) m): \(VisitIdentifyCopy.emptyMessage)"
        )
        // The owner approved the words at today's radius. If the radius changes, this fails, and
        // the owner sees the new number before a reader does.
        #expect(radius == 60, "the list's radius is \(radius) m; the owner approved the sentence at 60 m")
        #expect(
            VisitIdentifyCopy.emptyMessage
                == "No city tree and no added tree is within 60 m of you. "
                + "If there is a tree in front of you, it is not on the map yet."
        )
        #expect(VisitIdentifyCopy.emptyTitle == MapInventoryCopy.title)
    }

    /// **The two texts say "neither has a tree here", so an added tree must keep both away.** The
    /// map card fires on `MapContent.markerCount == 0`, and the list is empty when `treesNear`
    /// returns nothing. This puts one tree on ground with no city inventory, first this phone's
    /// own and then someone else's from the cache, and checks that both reads see it.
    ///
    /// Red-proof: return `Array(fromSeed.prefix(limit))` without the community half in
    /// `LocalAPI.treesNear` — red on "the list is empty with a tree … within 60 m". (Not this
    /// round's file; the proof is that this test would catch it.)
    @MainActor
    @Test("an added tree, this phone's or someone else's, keeps both empty texts away")
    func anAddedTreeKeepsBothEmptyTextsAway() async throws {
        for whose in ["this phone's", "someone else's"] {
            let store = try await CypressStore.inMemory()
            let api = LocalAPI(store: store, deviceID: Self.deviceID)
            let box = BoundingBox(around: Self.spot, radiusM: 100)

            // Nothing on record yet: both texts are owed.
            #expect(try await api.mapContent(in: MapViewport(bounds: box, zoom: 18)).markerCount == 0)
            #expect(try await Self.shortlist(api).state == .empty)

            if whose == "this phone's" {
                _ = try await api.addTree(
                    TreeDraft(
                        coordinate: Self.spot,
                        photoLocalPath: try VisitPhotoStaging.write(
                            Self.jpeg(), for: UUID(), shotType: .fullTree
                        ),
                        attribution: .anonymous(deviceID: Self.deviceID)
                    )
                )
            } else {
                try await CommunityRefresherTests.cache(
                    UUID(), at: Self.spot, tile: CommunityRefresherTests.tile.path, store
                )
            }

            let markers = try await api.mapContent(in: MapViewport(bounds: box, zoom: 18)).markerCount
            #expect(
                !MapInventoryNotice.isOwed(
                    hasSettled: true, isNarrowed: false, readFailed: false, markerCount: markers
                ),
                "the map card is owed over \(whose) added tree"
            )
            #expect(
                try await Self.shortlist(api).state != .empty,
                "the list is empty with a tree (\(whose)) within \(Int(VisitShortlist.searchRadiusM)) m"
            )
        }
    }

    // MARK: - Pictures, for a person to look at

    /// The add screen with each of the four notes at the drawn size, the add screen at AX5 (at a
    /// phone's height, where the button is pinned and the note is further down the form, and tall,
    /// where the note shows as the form's last row), the map card at both sizes, and the empty list.
    /// Runs only when `CYPRESS_SHOT_DIR` is set (`Tools/run_tests.sh`'s header has the one
    /// spelling that sets it); it judges each capture with `ShotBlankGuard` and asserts nothing
    /// about the layout.
    @MainActor
    @Test(
        "photographs of the four notes, AX5, the map card and the empty list",
        .enabled(if: ScreenSweepShots.shotDirectory != nil)
    )
    func photographs() async {
        let states: [(String, ContributionSharing)] = [
            ("sharing", .sharing), ("signed-out", .signedOut),
            ("not-sharing", .notSharing), ("unknown", .unknown),
        ]
        for (name, sharing) in states {
            #expect(await ScreenSweepShots.capture("c3b-add-\(name)", size: .large, scheme: .light) {
                VisitPreviewFixtures.addTree(sharing: sharing)
            } != nil)
        }
        #expect(await ScreenSweepShots.capture("c3b-add-ax5", size: .accessibility5, scheme: .light) {
            VisitPreviewFixtures.addTree()
        } != nil)
        #expect(await ScreenSweepShots.capture(
            "c3b-add-ax5-tall", size: .accessibility5, scheme: .light,
            viewportHeight: ScreenSweepShots.tallestViewport
        ) {
            VisitPreviewFixtures.addTree()
        } != nil)
        let bodies = [
            ("new", MapInventoryCopy.neitherHasATree), ("old", MapInventoryCopy.notOnTheCityInventory),
        ]
        for (body, message) in bodies {
            for (suffix, size) in [("default", DynamicTypeSize.large), ("ax5", .accessibility5)] {
                #expect(await ScreenSweepShots.capture(
                    "c3b-map-card-\(body)-\(suffix)", size: size, scheme: .light
                ) {
                    VStack {
                        Spacer()
                        MapLocationNotice(title: MapInventoryCopy.title, message: message)
                    }
                } != nil)
            }
        }
        #expect(await ScreenSweepShots.capture(
            "c3b-identify-empty", size: .large, scheme: .light, settleFloor: RenderSettle.legacyBudget
        ) {
            VisitPreviewFixtures.identify(rows: [])
        } != nil)

        // The number `MapEmptyInventoryTests.theNoticeFitsTheSlotAtAX5` compares, printed for the
        // branch report: the card at AX5 on the narrowest phone, and the budget it must stay under.
        let width = AX5ReflowTests.phoneWidth
        let newCard = await AX5ReflowTests.ax5Size(
            of: MapLocationNotice(title: MapInventoryCopy.title, message: MapInventoryCopy.neitherHasATree),
            width: width
        )
        let oldCard = await AX5ReflowTests.ax5Size(
            of: MapLocationNotice(
                title: MapInventoryCopy.title, message: MapInventoryCopy.notOnTheCityInventory
            ),
            width: width
        )
        let searching = await AX5ReflowTests.ax5Size(
            of: MapLocationNotice(
                title: MapOpeningCopy.searchingTitle,
                message: MapOpeningCopy.searchingMessage(.whereYouLeftOff)
            ),
            width: width
        )
        let notAsked = await AX5ReflowTests.ax5Size(
            of: MapLocationNotice(
                title: MapOpeningCopy.notAskedTitle,
                message: MapOpeningCopy.notAskedMessage(.theCityFallback)
            ),
            width: width
        )
        print(
            "C3B-AX5: new body \(newCard.height) pt, old body \(oldCard.height) pt at \(width) pt; "
                + "budget \(max(searching.height, notAsked.height)) pt"
        )
    }

    // MARK: - Helpers

    /// Two zoom-14 tiles side by side (x 2616 and 2617, the border at longitude -122.4976), inside
    /// `CommunityRefresherTests.tile`'s row.
    private static let twoTiles = BoundingBox(
        minLatitude: 37.7600, maxLatitude: 37.7610, minLongitude: -122.4990, maxLongitude: -122.4960
    )
    /// About 30 zoom-14 tiles: more than `Policy.maxTiles`.
    private static let manyTiles = BoundingBox(
        minLatitude: 37.7000, maxLatitude: 37.8000, minLongitude: -122.5200, maxLongitude: -122.4000
    )

    private static func asked(_ box: BoundingBox, _ store: CypressStore) async throws -> Bool {
        try await store.queue.read { connection in
            try CommunityTreeCacheStore().hasAsked(covering: box, connection: connection)
        }
    }

    /// Each tile answered with no trees, as `apply` records it.
    private static func fetched(_ tiles: [CommunityTile], _ store: CypressStore) async throws {
        try await store.queue.write { connection in
            for tile in tiles {
                try CommunityTreeCacheStore().apply(
                    tile: tile.path, trees: [], withdrawnTreeIDs: [], nextCursor: "c-\(tile.path)",
                    at: Date(), connection: connection
                )
            }
        }
    }

    /// The map over `CommunityRefresherTests.box`, which no seed covers, wired the way the
    /// composition root wires it: a refresher over `service`, or none for a shut gate, and the
    /// cache's own answer to "asked".
    @MainActor
    private static func map(_ store: CypressStore, service: ScriptedTileService?) -> MapModel {
        let refresher = service.map { CommunityRefresherTests.make(store, $0) }
        let model = MapModel(
            api: LocalAPI(store: store, deviceID: deviceID),
            refreshCommunity: refresher.map { refresher in
                { bounds in await refresher.refresh(covering: bounds).changedCache }
            },
            communityAsked: CommunityTreeCacheStore.askedReader(queue: store.queue)
        )
        model.cameraDidChange(bounds: CommunityRefresherTests.box, zoom: 18)
        return model
    }

    /// The read, then the refresh behind it and anything that started, all finished.
    @MainActor
    private static func settle(_ model: MapModel) async {
        await TestWait.settle(model) { model.inventoryIsEmptyHere }
        await model.communityRefresh?.value
        for task in model.outstandingTasks { await task.value }
    }

    @MainActor
    private static func model(api: LocalAPI, reader: @escaping ContributionSharingReader) -> VisitAddTreeModel {
        VisitAddTreeModel(
            api: api,
            location: VisitLocationProvider(pinnedFix: .located(spot, accuracyM: 5)),
            attribution: .anonymous(deviceID: deviceID),
            readSharing: reader
        )
    }

    /// The list screen 02 draws for a reader standing at `spot`, read the way `VisitIdentifyModel`
    /// reads it.
    private static func shortlist(_ api: LocalAPI) async throws -> VisitShortlist {
        let rows = try await api.treesNear(
            spot, radiusM: VisitShortlist.searchRadiusM, limit: VisitShortlist.maximumCandidates
        )
        return VisitShortlist.rank(rows, accuracyM: 5)
    }

    /// A real JPEG, because staging rewrites the container and refuses bytes that are not one.
    @MainActor
    private static func jpeg() throws -> Data {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { context in
            UIColor.darkGray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return try #require(image.jpegData(compressionQuality: 1))
    }
}
#endif
