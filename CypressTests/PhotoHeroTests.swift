//
//  PhotoHeroTests.swift
//  CypressTests
//
//  Photographs, finally, on screens (ERRATA **E125**), in three parts:
//
//  1. **The rule.** `PhotoHero` — A3's heuristic *and* A3's long-dead "a manual pin overrides".
//  2. **The bytes.** `LocalAPI.photoData`, including the window between the shutter and the outbox
//     drain, when a photograph exists only as a staged file.
//  3. **The loop.** Vote on a photograph → the tally changes → the tree leads with a different one.
//     Which is the whole feature: the browser exists to change what screen 03 draws.
//

import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Cypress

@Suite("Photo hero · the rule, the bytes and the vote")
struct PhotoHeroTests {

    private static let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-0000000000C1")!
    private static let moment = Date(timeIntervalSince1970: 1_780_000_000)

    private static func photo(
        _ shotType: ShotType,
        daysAgo: Int,
        resolution: (Int, Int) = (1_000, 1_000)
    ) -> Photo {
        Photo(
            treeID: UUID(),
            shotType: shotType,
            width: resolution.0,
            height: resolution.1,
            capturedAt: moment.addingTimeInterval(TimeInterval(-86_400 * daysAgo))
        )
    }

    // MARK: - 1 · The rule

    @Test("with nobody voting, A3 stands: the most recent full-tree shot")
    func a3IsTheDefault() {
        let newest = Self.photo(.fullTree, daysAgo: 0)
        let older = Self.photo(.fullTree, daysAgo: 10)
        let trunk = Self.photo(.trunk, daysAgo: -5)   // newer than either, and not a candidate
        #expect(PhotoHero.choose(from: [older, newest, trunk])?.id == newest.id)
    }

    @Test("resolution breaks a tie, which is the half that needed width and height recorded")
    func resolutionBreaksTies() {
        let small = Self.photo(.fullTree, daysAgo: 3, resolution: (800, 600))
        let large = Self.photo(.fullTree, daysAgo: 3, resolution: (4_000, 3_000))
        #expect(PhotoHero.choose(from: [small, large])?.id == large.id)
    }

    @Test("a thumbs-up is A3's manual pin: it beats the heuristic, whatever the shot type")
    func anUpVoteOverridesTheHeuristic() {
        let newestFullTree = Self.photo(.fullTree, daysAgo: 0)
        let oldTrunk = Self.photo(.trunk, daysAgo: 400)
        let tallies = [oldTrunk.id: PhotoTally(score: 1, ownVote: .up)]
        #expect(PhotoHero.choose(from: [newestFullTree, oldTrunk], tallies: tallies)?.id == oldTrunk.id)
    }

    @Test("a down-voted photo is never the hero, even when it is the only full-tree shot")
    func aDownVoteExcludes() {
        let rejected = Self.photo(.fullTree, daysAgo: 0)
        let trunk = Self.photo(.trunk, daysAgo: 2)
        let tallies = [rejected.id: PhotoTally(score: -1, ownVote: .down)]
        let chosen = PhotoHero.choose(from: [rejected, trunk], tallies: tallies)
        #expect(chosen?.id == trunk.id, "it should fall through to the only photo left standing")
    }

    @Test("the more up-voted of two pinned photos wins")
    func higherScoreWins() {
        let one = Self.photo(.fullTree, daysAgo: 0)
        let two = Self.photo(.trunk, daysAgo: 30)
        let tallies = [one.id: PhotoTally(score: 1, ownVote: .up), two.id: PhotoTally(score: 3)]
        #expect(PhotoHero.choose(from: [one, two], tallies: tallies)?.id == two.id)
    }

    @Test("a tree photographed only in close-up still leads with something")
    func fallsBackToAnyPhoto() {
        let leaf = Self.photo(.leaf, daysAgo: 1)
        let trunk = Self.photo(.trunk, daysAgo: 9)
        #expect(PhotoHero.choose(from: [trunk, leaf])?.id == leaf.id)
        #expect(PhotoHero.choose(from: []) == nil)
    }

    @Test("every photo down-voted is no hero at all, not the least-bad one")
    func everythingRejectedMeansNoHero() {
        let one = Self.photo(.fullTree, daysAgo: 0)
        let two = Self.photo(.fullTree, daysAgo: 1)
        let tallies = [one.id: PhotoTally(score: -1), two.id: PhotoTally(score: -2)]
        #expect(PhotoHero.choose(from: [one, two], tallies: tallies) == nil)
    }

    // MARK: - 2 · The bytes

    /// An in-memory database needs a real directory for the binaries: `photoDirectory` is derived
    /// from `store.databaseURL`, which for `:memory:` resolves to the root of a read-only volume.
    /// Each test gets its own, so nothing leaks between them.
    private static func photoDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cypress-photos-\(UUID().uuidString)", isDirectory: true)
    }

    private static func harness() async throws -> (LocalAPI, OutboxQueue) {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: deviceID, photoDirectory: Self.photoDirectory())
        return (api, OutboxQueue(queue: store.queue, apply: APIOutboxTransport(api: api)))
    }

    private static func jpeg(width: Int = 40, height: Int = 60) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.3, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    @Test("a photograph's bytes come back through the API, which is the thing that did not exist")
    func photoDataReadsTheBinary() async throws {
        let (api, _) = try await Self.harness()
        let tree = try await api.addTree(TreeDraft(
            coordinate: Coordinate(latitude: 37.77, longitude: -122.44),
            photoLocalPath: "/tmp/cypress-photo-test.jpg",
            attribution: .anonymous(deviceID: Self.deviceID)
        ))
        let ids = try await api.debugSeedPhotos(treeID: tree.id, count: 2)
        #expect(ids.count == 2)

        for id in ids {
            let data = try await api.photoData(id: id)
            #expect(!data.isEmpty)
            // Really an image, not merely bytes: the screens decode this.
            #expect(PhotoImageStore.downsample(data, maximumEdge: 200) != nil)
        }
    }

    @Test("a photo still in the outbox is readable from where it is staged")
    func photoDataFindsAStagedFile() async throws {
        let (api, _) = try await Self.harness()
        let tree = try await api.addTree(TreeDraft(
            coordinate: Coordinate(latitude: 37.77, longitude: -122.44),
            photoLocalPath: "/tmp/cypress-photo-staged-tree.jpg",
            attribution: .anonymous(deviceID: Self.deviceID)
        ))

        // The state between the shutter and the drain: a row with `local_path` set and no
        // `storage_key`. `beginPhotoUpload` writes exactly that.
        let staged = FileManager.default.temporaryDirectory
            .appendingPathComponent("cypress-staged-\(UUID().uuidString).jpg")
        try Self.jpeg().write(to: staged)
        defer { try? FileManager.default.removeItem(at: staged) }

        let ticket = try await api.beginPhotoUpload(PhotoUploadRequest(
            treeID: tree.id,
            shotType: .fullTree,
            localPath: staged.path,
            capturedAt: Self.moment
        ))

        let data = try await api.photoData(id: ticket.photoID)
        #expect(!data.isEmpty, "the tree you just photographed must not be blank until the drain runs")
    }

    /// The test the first version of this feature needed and did not have.
    ///
    /// `photoData` and `setPhotoVote` began as extension-only members of `CypressAPI`. An extension
    /// member is not a requirement, so it dispatches statically — every test in this file held a
    /// concrete `LocalAPI` and reached the real implementation, while every screen holds
    /// `any CypressAPI` and reached the extension's `throw APIError.notFound`. Photographs were
    /// invisible and votes did nothing, on a green suite.
    ///
    /// So this one erases the type first, exactly as `PhotoImageStore` and `TreePhotosModel` do.
    @Test("the API works through the existential every screen actually holds")
    func worksThroughTheProtocol() async throws {
        let (concrete, _) = try await Self.harness()
        let tree = try await concrete.addTree(TreeDraft(
            coordinate: Coordinate(latitude: 37.77, longitude: -122.44),
            photoLocalPath: "/tmp/cypress-photo-existential.jpg",
            attribution: .anonymous(deviceID: Self.deviceID)
        ))
        let id = try await concrete.debugSeedPhotos(treeID: tree.id, count: 1)[0]

        // The erasure is the point. Do not replace this with the concrete type.
        let api: any CypressAPI = concrete

        let data = try await api.photoData(id: id)
        #expect(!data.isEmpty, "dispatched to the extension default instead of LocalAPI")

        try await api.setPhotoVote(photoID: id, vote: .up)
        #expect(try await api.treeProfile(id: tree.id).photoTallies[id]?.ownVote == .up)
    }

    @Test("a photo id nothing knows about is notFound, not an empty image")
    func unknownPhotoIsNotFound() async throws {
        let (api, _) = try await Self.harness()
        await #expect(throws: APIError.notFound) { try await api.photoData(id: UUID()) }
        await #expect(throws: APIError.notFound) { try await api.setPhotoVote(photoID: UUID(), vote: .up) }
    }

    // MARK: - 3 · The loop

    @Test("voting a photo up makes the tree lead with it")
    func aVoteChangesTheHero() async throws {
        let (api, _) = try await Self.harness()
        let tree = try await api.addTree(TreeDraft(
            coordinate: Coordinate(latitude: 37.77, longitude: -122.44),
            photoLocalPath: "/tmp/cypress-photo-vote.jpg",
            attribution: .anonymous(deviceID: Self.deviceID)
        ))
        // Newest first: [0] is a full tree taken today, [2] a leaf close-up from two days ago.
        let ids = try await api.debugSeedPhotos(treeID: tree.id, count: 3)

        let before = try await api.treeProfile(id: tree.id)
        #expect(
            TreeProfilePresentation(profile: before).bestPhoto?.id == ids[0],
            "A3 first: the newest full-tree shot"
        )

        try await api.setPhotoVote(photoID: ids[2], vote: .up)

        let after = try await api.treeProfile(id: tree.id)
        #expect(after.photoTallies[ids[2]] == PhotoTally(score: 1, ownVote: .up))
        #expect(
            TreeProfilePresentation(profile: after).bestPhoto?.id == ids[2],
            "the pin overrides the heuristic"
        )
    }

    @Test("a vote can be changed and taken back")
    func votesToggle() async throws {
        let (api, _) = try await Self.harness()
        let tree = try await api.addTree(TreeDraft(
            coordinate: Coordinate(latitude: 37.77, longitude: -122.44),
            photoLocalPath: "/tmp/cypress-photo-toggle.jpg",
            attribution: .anonymous(deviceID: Self.deviceID)
        ))
        let id = try await api.debugSeedPhotos(treeID: tree.id, count: 1)[0]

        try await api.setPhotoVote(photoID: id, vote: .up)
        #expect(try await api.treeProfile(id: tree.id).photoTallies[id]?.ownVote == .up)

        // Changed, not doubled: one row per owner per photo.
        try await api.setPhotoVote(photoID: id, vote: .down)
        let changed = try await api.treeProfile(id: tree.id).photoTallies[id]
        #expect(changed == PhotoTally(score: -1, ownVote: .down))

        try await api.setPhotoVote(photoID: id, vote: nil)
        #expect(try await api.treeProfile(id: tree.id).photoTallies[id] == nil)
    }

    @Test("a down-voted photo stops being the hero and the next one takes over")
    func aDownVoteHandsTheHeroOver() async throws {
        let (api, _) = try await Self.harness()
        let tree = try await api.addTree(TreeDraft(
            coordinate: Coordinate(latitude: 37.77, longitude: -122.44),
            photoLocalPath: "/tmp/cypress-photo-down.jpg",
            attribution: .anonymous(deviceID: Self.deviceID)
        ))
        let ids = try await api.debugSeedPhotos(treeID: tree.id, count: 3)

        try await api.setPhotoVote(photoID: ids[0], vote: .down)
        let profile = try await api.treeProfile(id: tree.id)
        let hero = TreeProfilePresentation(profile: profile).bestPhoto
        #expect(hero?.id != ids[0])
        #expect(hero != nil, "the tree still has photographs and must still lead with one")
    }

    @Test("a vote cast before signing in is adopted by the account, not counted twice")
    func claimingTheDeviceAdoptsVotes() async throws {
        let (api, _) = try await Self.harness()
        let tree = try await api.addTree(TreeDraft(
            coordinate: Coordinate(latitude: 37.77, longitude: -122.44),
            photoLocalPath: "/tmp/cypress-photo-claim.jpg",
            attribution: .anonymous(deviceID: Self.deviceID)
        ))
        let id = try await api.debugSeedPhotos(treeID: tree.id, count: 1)[0]
        try await api.setPhotoVote(photoID: id, vote: .up)

        try await api.claimDevice(deviceUUID: Self.deviceID, userID: UUID())

        let tally = try await api.treeProfile(id: tree.id).photoTallies[id]
        #expect(tally == PhotoTally(score: 1, ownVote: .up), "one vote, now the account's")
    }

    // MARK: - 4 · Batched, for a list of rows (#176)
    //
    // My Grove's `Trees` pill, the journal and the almanac's season rows each draw several trees at
    // once and must not read the database once per row (ARCHITECTURE, the performance campaigns
    // E130/E139). `ContributionStore.heroPhotoIDs` is the one statement behind all three; these
    // assert it agrees with `PhotoHero` itself rather than duplicating the rule.

    @Test("the batched read agrees with A3's own ordering, per tree")
    func heroPhotoIDsAgreesWithA3() async throws {
        let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-0000000000C3")!
        let attribution = Attribution.anonymous(deviceID: deviceID)
        let store = try await CypressStore.inMemory()
        // A real directory for the binaries `debugSeedPhotos` writes — see `Self.harness()`'s own
        // comment: an in-memory store's `photoDirectory` otherwise resolves to the root of a
        // read-only volume.
        let api = LocalAPI(store: store, deviceID: deviceID, photoDirectory: Self.photoDirectory())

        let tree = try await api.addTree(TreeDraft(
            coordinate: Coordinate(latitude: 37.77, longitude: -122.44),
            photoLocalPath: "/tmp/cypress-hero-ids.jpg",
            attribution: attribution
        )).id
        // `debugSeedPhotos` clears the one photo `addTree` requires and writes three of its own —
        // [0] a full-tree shot taken today, which A3 picks with nobody voting.
        let ids = try await api.debugSeedPhotos(treeID: tree, count: 3)

        let heroPhotoIDs = try await store.queue.read { connection in
            try ContributionStore().heroPhotoIDs(connection: connection)
        }
        #expect(heroPhotoIDs[tree] == ids[0], "the batched read did not agree with A3's own ordering")

        // A tree nothing here has touched is simply absent from the map — a missing key, not a
        // present one holding nil, which `[UUID: UUID]` cannot even express.
        #expect(heroPhotoIDs[UUID()] == nil)
    }

    @Test("a vote changes the batched read's answer exactly as it changes the hero's")
    func heroPhotoIDsRespectsVotes() async throws {
        let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-0000000000C4")!
        let attribution = Attribution.anonymous(deviceID: deviceID)
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: deviceID, photoDirectory: Self.photoDirectory())

        let tree = try await api.addTree(TreeDraft(
            coordinate: Coordinate(latitude: 37.79, longitude: -122.44),
            photoLocalPath: "/tmp/cypress-hero-ids-vote.jpg",
            attribution: attribution
        )).id
        let ids = try await api.debugSeedPhotos(treeID: tree, count: 3)

        try await api.setPhotoVote(photoID: ids[2], vote: .up)

        let heroPhotoIDs = try await store.queue.read { connection in
            try ContributionStore().heroPhotoIDs(connection: connection)
        }
        #expect(
            heroPhotoIDs[tree] == ids[2],
            "the pin overrode the heuristic for the profile hero but not for a list row"
        )
    }

    @Test("two trees do not bleed into each other's answer")
    func heroPhotoIDsIsKeyedPerTree() async throws {
        let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-0000000000C5")!
        let attribution = Attribution.anonymous(deviceID: deviceID)
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: deviceID, photoDirectory: Self.photoDirectory())

        let first = try await api.addTree(TreeDraft(
            coordinate: Coordinate(latitude: 37.80, longitude: -122.44),
            photoLocalPath: "/tmp/cypress-hero-ids-first.jpg",
            attribution: attribution
        )).id
        let second = try await api.addTree(TreeDraft(
            coordinate: Coordinate(latitude: 37.81, longitude: -122.44),
            photoLocalPath: "/tmp/cypress-hero-ids-second.jpg",
            attribution: attribution
        )).id
        let firstIDs = try await api.debugSeedPhotos(treeID: first, count: 2)
        let secondIDs = try await api.debugSeedPhotos(treeID: second, count: 2)

        let heroPhotoIDs = try await store.queue.read { connection in
            try ContributionStore().heroPhotoIDs(connection: connection)
        }
        #expect(heroPhotoIDs[first] == firstIDs[0])
        #expect(heroPhotoIDs[second] == secondIDs[0])
        #expect(heroPhotoIDs[first] != heroPhotoIDs[second])
    }

    // MARK: - 4b · Batched and scoped, for a caller-supplied set of trees (#222, ERRATA E204)
    //
    // Screen 07 §6's `Nearby individuals` cannot use `heroPhotoIDs()` above: its candidates are
    // not "this device's own trees" the way grove/journal/almanac's are, so scanning the whole
    // `main.photos` table to answer a two-or-three-tree question would be paying for the entire
    // photo library on every species page. `heroPhotoIDs(treeIDs:)` is the scoped read named in
    // E204's own follow-up instruction; see `SpeciesGuideNearbyPhotosTests` for the same rule
    // proved through the full `speciesGuide` call path.

    @Test("the scoped batched read agrees with the unscoped one, for the trees it was asked about")
    func heroPhotoIDsScopedToTreesAgreesWithTheUnscopedRead() async throws {
        let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-0000000000C6")!
        let attribution = Attribution.anonymous(deviceID: deviceID)
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: deviceID, photoDirectory: Self.photoDirectory())

        let tree = try await api.addTree(TreeDraft(
            coordinate: Coordinate(latitude: 37.77, longitude: -122.44),
            photoLocalPath: "/tmp/cypress-hero-ids-scoped.jpg",
            attribution: attribution
        )).id
        let ids = try await api.debugSeedPhotos(treeID: tree, count: 3)

        let (scoped, unscoped) = try await store.queue.read { connection in
            (
                try ContributionStore().heroPhotoIDs(treeIDs: [tree], attribution: attribution, connection: connection),
                try ContributionStore().heroPhotoIDs(connection: connection)
            )
        }
        #expect(scoped[tree] == unscoped[tree])
        #expect(scoped[tree] == ids[0], "the scoped read did not agree with A3's own ordering")
    }

    @Test("a tree outside the requested set never appears, even though it has photographs")
    func heroPhotoIDsScopedToTreesExcludesTreesNotAsked() async throws {
        let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-0000000000C7")!
        let attribution = Attribution.anonymous(deviceID: deviceID)
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: deviceID, photoDirectory: Self.photoDirectory())

        let asked = try await api.addTree(TreeDraft(
            coordinate: Coordinate(latitude: 37.80, longitude: -122.44),
            photoLocalPath: "/tmp/cypress-hero-ids-scoped-asked.jpg",
            attribution: attribution
        )).id
        let notAsked = try await api.addTree(TreeDraft(
            coordinate: Coordinate(latitude: 37.81, longitude: -122.44),
            photoLocalPath: "/tmp/cypress-hero-ids-scoped-not-asked.jpg",
            attribution: attribution
        )).id
        let askedIDs = try await api.debugSeedPhotos(treeID: asked, count: 2)
        _ = try await api.debugSeedPhotos(treeID: notAsked, count: 2)

        let scoped = try await store.queue.read { connection in
            try ContributionStore().heroPhotoIDs(treeIDs: [asked], attribution: attribution, connection: connection)
        }
        #expect(scoped[asked] == askedIDs[0])
        #expect(scoped[notAsked] == nil, "a tree the caller never asked about must not appear at all")
        #expect(scoped.count == 1, "the scoped read pulled in more trees than it was asked for")
    }

    @Test("a tree with no live photograph is simply absent — never a present key holding nil")
    func heroPhotoIDsScopedToTreesOmitsAPhotolessTree() async throws {
        let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-0000000000C8")!
        let attribution = Attribution.anonymous(deviceID: deviceID)
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: deviceID, photoDirectory: Self.photoDirectory())

        let photographed = try await api.addTree(TreeDraft(
            coordinate: Coordinate(latitude: 37.82, longitude: -122.44),
            photoLocalPath: "/tmp/cypress-hero-ids-scoped-photographed.jpg",
            attribution: attribution
        )).id
        // A tree id nothing has ever written a photo row for — the honest shape of "a fresh
        // install's every seeded tree", which is what `Nearby individuals` actually asks about.
        let untouched = UUID()

        let scoped = try await store.queue.read { connection in
            try ContributionStore().heroPhotoIDs(treeIDs: [untouched], attribution: attribution, connection: connection)
        }
        #expect(scoped.isEmpty, "a request naming only an untouched tree found a photo from nowhere")
        #expect(scoped[untouched] == nil)

        // And the same fact holds inside a mixed request, so a well-photographed neighbor cannot
        // paper over an empty answer for the tree actually asked about.
        let mixed = try await store.queue.read { connection in
            try ContributionStore().heroPhotoIDs(
                treeIDs: [photographed, untouched], attribution: attribution, connection: connection
            )
        }
        #expect(mixed[untouched] == nil)
        #expect(mixed[photographed] != nil)
    }

    @Test("an empty request answers empty, even when this device's photo library is not")
    func heroPhotoIDsScopedToTreesAnEmptyRequestAnswersEmpty() async throws {
        let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-0000000000C9")!
        let attribution = Attribution.anonymous(deviceID: deviceID)
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: deviceID, photoDirectory: Self.photoDirectory())

        // A tree with real photographs on the device — present so that an empty request falling
        // through to `heroPhotoIDs()`'s unscoped shape would be caught rather than trivially true.
        let tree = try await api.addTree(TreeDraft(
            coordinate: Coordinate(latitude: 37.83, longitude: -122.44),
            photoLocalPath: "/tmp/cypress-hero-ids-scoped-empty-request.jpg",
            attribution: attribution
        )).id
        _ = try await api.debugSeedPhotos(treeID: tree, count: 2)

        let scoped = try await store.queue.read { connection in
            try ContributionStore().heroPhotoIDs(treeIDs: [], attribution: attribution, connection: connection)
        }
        #expect(scoped.isEmpty, "asking about no trees must not answer with every tree's photograph")
    }

    // MARK: - 4c · Visibility, not just existence (ERRATA E215, review of #222/PR #16)
    //
    // The scoped read's candidates are not "this device's own trees" (unlike the unscoped
    // `heroPhotoIDs()` above), so a row it finds may belong to a contributor this device has
    // never met. Caught in adversarial review: the SQL above filtered only `deleted_at IS NULL`
    // — no ownership, no moderation — so the day anything syncs a stranger's photograph down, an
    // unmoderated one could become a nearby hero. `PhotoOwnershipTests`' own idiom is used to seed
    // the "stranger" row: a raw `INSERT` with a `user_id` this test's `attribution` does not hold,
    // since nothing in the shipping write path can produce that row today (E215: "latent, not
    // live") and the fixture has to reach past it the way a synced read someday would.

    private static let strangerID = UUID(uuidString: "57A4DE00-0000-4000-8000-00000000E215")!

    /// Inserts one photograph directly, owned by `Self.strangerID` rather than by the test's own
    /// `attribution` — bypassing `ContributionStore.insert` exactly as `PhotoOwnershipTests`'
    /// "theirs" rows do, because no write path this app ships can attribute a photograph to
    /// somebody else on this device.
    private static func insertStrangersPhoto(
        id: UUID = UUID(),
        treeID: UUID,
        moderationState: ModerationState,
        capturedAt: Date,
        connection: SQLiteConnection
    ) throws {
        let stamp = SQLiteTimestamp.string(from: capturedAt)
        try connection.execute("""
            INSERT INTO photos
                (id, tree_uuid, shot_type, moderation_state, captured_at, created_at, updated_at, user_id)
            VALUES ('\(id.uuidString)', '\(treeID.uuidString)', 'full_tree', '\(moderationState.rawValue)',
                    '\(stamp)', '\(stamp)', '\(stamp)', '\(Self.strangerID.uuidString)')
            """)
    }

    @Test("a stranger's unmoderated photograph must not become a nearby hero")
    func heroPhotoIDsScopedToTreesExcludesAStrangersPendingPhoto() async throws {
        let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-0000000000CA")!
        let attribution = Attribution.anonymous(deviceID: deviceID)
        let store = try await CypressStore.inMemory()
        let tree = UUID()

        try await store.queue.write { connection in
            try Self.insertStrangersPhoto(
                treeID: tree, moderationState: .pending, capturedAt: Self.moment, connection: connection
            )
        }

        let scoped = try await store.queue.read { connection in
            try ContributionStore().heroPhotoIDs(treeIDs: [tree], attribution: attribution, connection: connection)
        }
        #expect(
            scoped[tree] == nil,
            "a stranger's unmoderated photograph reached the nearby section — the exact case ERRATA E215 names"
        )
    }

    @Test("a stranger's approved photograph may become a nearby hero — moderation, not ownership, is the gate")
    func heroPhotoIDsScopedToTreesAdmitsAStrangersApprovedPhoto() async throws {
        let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-0000000000CB")!
        let attribution = Attribution.anonymous(deviceID: deviceID)
        let store = try await CypressStore.inMemory()
        let tree = UUID()
        let approved = UUID()

        try await store.queue.write { connection in
            // The unmoderated row from the previous test would also disqualify this one if the
            // exclusion above were really "exclude every stranger" rather than "exclude an
            // unmoderated stranger" — planting one beside the approved row is what tells the two
            // rules apart, the same arm `PhotoVisibilityParityTests.strangersApprovedReachesTheBrowser`
            // exists to check for the hero and the browser.
            try Self.insertStrangersPhoto(
                treeID: tree, moderationState: .pending, capturedAt: Self.moment.addingTimeInterval(-86_400),
                connection: connection
            )
            try Self.insertStrangersPhoto(
                id: approved, treeID: tree, moderationState: .approved, capturedAt: Self.moment,
                connection: connection
            )
        }

        let scoped = try await store.queue.read { connection in
            try ContributionStore().heroPhotoIDs(treeIDs: [tree], attribution: attribution, connection: connection)
        }
        #expect(
            scoped[tree] == approved,
            "a stranger's approved, more recent photograph should have led — excluding it is 'exclude every stranger', not the moderation rule"
        )
    }

    // MARK: - 5 · The map card (#176)
    //
    // `MapCardSubject` already carries `profile: TreeProfile?` — the same full read the tree
    // profile draws from, `photos` and `photoTallies` included — so the card needs no read of its
    // own. It needs only to ask `PhotoHero` the same question the profile hero asks.

    @Test("the map card draws no photo before its profile has loaded, whatever the pin says")
    func mapCardHasNoHeroBeforeTheProfileLoads() {
        let pin = TreePin(
            id: UUID(),
            coordinate: Coordinate(latitude: 37.77, longitude: -122.44),
            status: .alive,
            source: .cityImport,
            verificationState: .cityRecord,
            speciesID: nil
        )
        let subject = MapCardSubject(pin: pin)
        #expect(subject.profile == nil)
        #expect(subject.heroPhoto == nil, "a card drew a photo before its profile read had landed")
    }

    @Test("once the profile lands, the map card leads with the same photo the tree's own page would")
    func mapCardSharesTheProfileHero() {
        let pin = TreePin(
            id: UUID(),
            coordinate: Coordinate(latitude: 37.77, longitude: -122.44),
            status: .alive,
            source: .cityImport,
            verificationState: .cityRecord,
            speciesID: nil
        )
        let tree = Tree(
            id: pin.id,
            source: .cityImport,
            coordinate: pin.coordinate,
            status: .alive,
            createdAt: Self.moment,
            updatedAt: Self.moment
        )
        let newest = Self.photo(.fullTree, daysAgo: 0)
        let older = Self.photo(.fullTree, daysAgo: 10)
        let profile = TreeProfile(tree: tree, photos: Series(complete: [older, newest]))

        let subject = MapCardSubject(pin: pin, profile: profile)
        #expect(subject.heroPhoto?.id == newest.id, "disagreed with the same rule the profile hero uses")
    }

    @Test("a vacant site's card has no hero, because a site has no tree to have photographed")
    func mapCardVacantSiteHasNoHero() {
        let pin = TreePin(
            id: UUID(),
            coordinate: Coordinate(latitude: 37.77, longitude: -122.44),
            status: .vacantSite,
            source: .cityImport,
            verificationState: .cityRecord,
            speciesID: nil
        )
        let tree = Tree(
            id: pin.id,
            source: .cityImport,
            coordinate: pin.coordinate,
            status: .vacantSite,
            createdAt: Self.moment,
            updatedAt: Self.moment
        )
        let subject = MapCardSubject(pin: pin, profile: TreeProfile(tree: tree))
        #expect(subject.isVacantSite)
        #expect(subject.heroPhoto == nil)
    }
}
