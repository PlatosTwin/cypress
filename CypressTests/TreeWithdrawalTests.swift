import Foundation
import Testing
@testable import Cypress

/// The adder withdraws a community tree for everyone (the owner's decision 8, and the owner's
/// answers of 2026-11-16).
///
/// The sentences the change has to make true, one group of tests each:
///
/// 1. **The adder withdraws**: the tree's `deleted_at` is set and one `tree_withdrawal` is queued,
///    in one write, at one instant.
/// 2. **Every other caller is refused, and queues nothing**, with the answer the service would give.
/// 3. **The reads**: the tree leaves the map, the shortlist, the profile, the Journal, My Grove and
///    the Yours map; the adder's own rows stay saved; a tile page cannot bring it back.
/// 4. **The service's answer settles it**: a `conflict` brings the tree back and the Outbox row says
///    why; a retry the service accepts takes it off again.
/// 5. **The offer**: the control is drawn only for the adder's live tree, and the reason line only
///    on a fact the phone holds.
@Suite("Community trees · withdrawing a tree you added")
struct TreeWithdrawalTests {

    private typealias Fixture = LocationCorrectionTests

    static let otherUserID = UUID(uuidString: "0E000000-0000-4000-8000-0000000C1099")!

    /// A clock the test moves.
    final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var value = Date(timeIntervalSince1970: 1_797_000_000)
        var now: Date { lock.withLock { value } }
        func advance(by seconds: TimeInterval) { lock.withLock { value.addTimeInterval(seconds) } }
    }

    /// The service: answers each `tree_withdrawal` with the next scripted answer (and `applied`
    /// once the script is spent), and every other kind with `applied`.
    actor Service: OutboxSendSink {
        private var withdrawalAnswers: [APIError?]
        private(set) var offered: [OutboxItem.Kind] = []

        init(withdrawalAnswers: [APIError?]) { self.withdrawalAnswers = withdrawalAnswers }

        func sync(_ items: [OutboxItem]) async throws -> [SyncResult] {
            offered.append(contentsOf: items.map(\.kind))
            return items.map { item in
                guard item.kind == .treeWithdrawal, !withdrawalAnswers.isEmpty,
                      let refusal = withdrawalAnswers.removeFirst()
                else { return SyncResult(clientUUID: item.clientUUID, status: .applied) }
                return SyncResult(clientUUID: item.clientUUID, status: .failed, error: refusal)
            }
        }

        func uploadPhoto(_ photo: OutboxStore.PhotoRow, for item: OutboxItem) async throws {}
    }

    static func withdrawals(_ store: CypressStore) async throws -> [OutboxStore.Record] {
        try await store.queue.read { try OutboxStore().allItems(connection: $0) }
            .filter { $0.item.kind == .treeWithdrawal }
    }

    /// `community_trees.deleted_at`, read straight from SQL: the question is whether it was written.
    static func deletedAt(_ store: CypressStore, _ id: UUID) async throws -> String? {
        try await store.queue.read { connection -> String? in
            let statement = try connection.prepare(
                "SELECT deleted_at FROM community_trees WHERE id = :id COLLATE NOCASE"
            )
            defer { statement.finalize() }
            _ = try statement.bind(id.uuidString, forName: ":id")
            return try statement.fetchOne { try $0.stringIfPresent("deleted_at") } ?? nil
        }
    }

    static func visit(
        _ store: CypressStore,
        on treeID: UUID,
        by attribution: Attribution,
        at moment: Date = Date(timeIntervalSince1970: 1_796_000_000)
    ) async throws -> Visit {
        let visit = Visit(treeID: treeID, attribution: attribution, capturedAt: moment)
        try await store.queue.write { try ContributionStore().insert(visit, connection: $0) }
        return visit
    }

    static func box(around coordinate: Coordinate) -> MapViewport {
        MapViewport(bounds: BoundingBox(around: coordinate, radiusM: 100), zoom: 18)
    }

    static func journal(_ api: LocalAPI) async throws -> [JournalEntry] {
        try await api.journal(cursor: nil, limit: 100).items
    }

    // MARK: - 1. The adder withdraws

    /// Red-proof: remove `queueAppliedMutation` from `LocalAPI.withdrawTree` — red on "queued 0
    /// withdrawals".
    @Test("the adder withdraws: the tree is tombstoned and one withdrawal is queued, at one instant")
    func theAdderWithdraws() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Fixture.deviceID, userID: Fixture.userID)
        let tree = try await Fixture.add(api)

        try await api.withdrawTree(treeID: tree.id)

        let tombstone = try await Self.deletedAt(store, tree.id)
        #expect(tombstone != nil, "the tree was not tombstoned")
        let queued = try await Self.withdrawals(store)
        #expect(queued.count == 1, "queued \(queued.count) withdrawals")
        let record = try #require(queued.first)
        #expect(record.locallyApplied, "the withdrawal was queued unapplied; a drain would apply it")
        guard case let .treeWithdrawal(withdrawal) = try OutboxPayload.decode(
            kind: record.item.kind, from: record.item.payload
        ) else {
            Issue.record("the queued row did not decode as a tree withdrawal")
            return
        }
        #expect(withdrawal.treeID == tree.id)
        #expect(withdrawal.clientUUID == record.item.clientUUID, "the payload's key is not the row's")
        #expect(withdrawal.attribution.userID == Fixture.userID)
        #expect(withdrawal.attribution.deviceID == Fixture.deviceID)
        // The tombstone and the row's `created_at` are one instant: the refusal path relies on it.
        #expect(
            tombstone == SQLiteTimestamp.string(from: record.item.createdAt),
            "the tombstone \(tombstone ?? "nil") is not the queue row's instant"
        )
        await #expect(throws: APIError.notFound, "the profile still opens a withdrawn tree") {
            _ = try await api.treeProfile(id: tree.id)
        }
    }

    // MARK: - 2. Refusals

    /// Each case must queue nothing. Red-proofs: drop the `isOwned(by:)` guard — red on the
    /// stranger, the signed-out phone and nobody's tree; drop the `deletedAt` guard — red on the
    /// second withdrawal ("an already withdrawn tree was withdrawn again", with a second row).
    @Test("everyone but the adder is refused, an already withdrawn or unknown tree is not found, and nothing is queued")
    func theRefusals() async throws {
        let store = try await CypressStore.inMemory()
        let adder = LocalAPI(store: store, deviceID: Fixture.deviceID)

        // Somebody else on this phone's store: another installation.
        let mine = try await Fixture.add(adder)
        let stranger = LocalAPI(store: store, deviceID: Fixture.otherDeviceID)
        await #expect(throws: APIError.forbidden, "a stranger withdrew the tree") {
            try await stranger.withdrawTree(treeID: mine.id)
        }

        // A tree whose adder is nobody (an anonymized tree).
        let nobodys = Tree(source: .community, coordinate: ProximityDedupeTests.diagonal(from: Fixture.offshore, meters: 300))
        try await store.queue.write { connection in
            try CommunityTreeStore().insert(nobodys, clientUUID: UUID(), connection: connection)
        }
        await #expect(throws: APIError.forbidden, "a tree nobody added was withdrawn") {
            try await adder.withdrawTree(treeID: nobodys.id)
        }

        // Somebody else's published tree, from the cache.
        let cached = Tree(source: .community, coordinate: ProximityDedupeTests.diagonal(from: Fixture.offshore, meters: 600))
        _ = try await store.queue.write { connection in
            try CommunityTreeCacheStore().apply(
                tile: "t", trees: [cached], withdrawnTreeIDs: [], nextCursor: "c",
                at: Date(), connection: connection
            )
        }
        await #expect(throws: APIError.forbidden, "somebody else's cached tree was withdrawn") {
            try await adder.withdrawTree(treeID: cached.id)
        }

        // An unknown id.
        await #expect(throws: APIError.notFound) { try await adder.withdrawTree(treeID: UUID()) }

        #expect(try await Self.withdrawals(store).isEmpty, "a refusal queued a withdrawal")

        // Already withdrawn: the first one is the adder's, the second is refused.
        try await adder.withdrawTree(treeID: mine.id)
        await #expect(throws: APIError.notFound, "an already withdrawn tree was withdrawn again") {
            try await adder.withdrawTree(treeID: mine.id)
        }
        #expect(try await Self.withdrawals(store).count == 1, "a second withdrawal was queued")
    }

    /// The S1 rule (`TreeWithdrawal.swift`): after a claim the account owns the tree, and the
    /// service treats the signed-out phone as a stranger to it.
    @Test("a signed-out phone cannot withdraw a tree its account added, and sees no control for it")
    func aSignedOutPhoneCannotWithdrawItsAccountsTree() async throws {
        let store = try await CypressStore.inMemory()
        let signedOut = LocalAPI(store: store, deviceID: Fixture.deviceID)
        let tree = try await Fixture.add(signedOut)
        let account = LocalAPI(store: store, deviceID: Fixture.deviceID)
        try await account.claimDevice(deviceUUID: Fixture.deviceID, userID: Fixture.userID)

        let afterwards = LocalAPI(store: store, deviceID: Fixture.deviceID)
        #expect(try await afterwards.treeProfile(id: tree.id).treeWithdrawal == .unavailable,
                "the signed-out phone is offered a withdrawal the service would refuse")
        await #expect(throws: APIError.forbidden, "the signed-out phone withdrew its account's tree") {
            try await afterwards.withdrawTree(treeID: tree.id)
        }
        #expect(try await Self.withdrawals(store).isEmpty)

        // And the account can.
        #expect(try await account.treeProfile(id: tree.id).treeWithdrawal == .available)
        try await account.withdrawTree(treeID: tree.id)
        #expect(try await Self.withdrawals(store).count == 1)
    }

    /// A city tree is real and not this person's to withdraw.
    @Test("a city tree is forbidden, and queues nothing")
    func aCityTreeIsForbidden() async throws {
        let seedURL = try #require(SeedContractTests.seedURL, "no seed database; set CYPRESS_SEED_PATH")
        let store = try await CypressStore.inMemory(seedURL: seedURL)
        let api = LocalAPI(store: store, deviceID: Fixture.deviceID)
        let cityTreeID = try await store.queue.read { connection -> UUID? in
            let statement = try connection.prepare(
                "SELECT uuid FROM \(SeedDatabase.schemaName).trees WHERE deleted_at IS NULL LIMIT 1"
            )
            defer { statement.finalize() }
            return try statement.fetchOne { try $0.uuidIfPresent("uuid") } ?? nil
        }
        let target = try #require(cityTreeID, "the seed has no trees")
        await #expect(throws: APIError.forbidden, "a city tree was withdrawn") {
            try await api.withdrawTree(treeID: target)
        }
        #expect(try await Self.withdrawals(store).isEmpty)
        #expect(try await api.treeProfile(id: target).treeWithdrawal == .unavailable)
    }

    // MARK: - 3. The reads

    /// Red-proofs, each read by its message:
    /// - drop `notOnAWithdrawnTree` from the Journal's four arms — red on "the Journal still lists";
    /// - drop the `isWithdrawnCommunityTree` skip in `groveEntries` — red on "My Grove still lists";
    /// - drop it from `contributedRowsSQL` — red on "the Yours map still holds".
    @Test("a withdrawn tree leaves the map, the shortlist, the Journal, My Grove and Yours, and the adder's rows stay")
    func theReadsDropAWithdrawnTree() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Fixture.deviceID)
        let tree = try await Fixture.add(api)
        let kept = try await Fixture.add(api, at: ProximityDedupeTests.diagonal(from: Fixture.offshore, meters: 400))
        let own = try await Self.visit(store, on: tree.id, by: .anonymous(deviceID: Fixture.deviceID))
        _ = try await Self.visit(store, on: kept.id, by: .anonymous(deviceID: Fixture.deviceID))

        // The fixture, before: every read lists both trees.
        #expect(try await api.mapContent(in: Self.box(around: tree.coordinate)).markerCount == 1)
        #expect(Set(try await Self.journal(api).map(\.treeID)) == [tree.id, kept.id], "fixture: the Journal")
        #expect(Set(try await api.grove().map(\.treeID)) == [tree.id, kept.id], "fixture: My Grove")
        #expect(try await api.mapMembership(.yours) == [tree.id, kept.id], "fixture: Yours")

        try await api.withdrawTree(treeID: tree.id)

        #expect(try await api.mapContent(in: Self.box(around: tree.coordinate)).markerCount == 0,
                "the map still draws the withdrawn tree")
        let near = try await api.treesNear(tree.coordinate, radiusM: 20, limit: 5)
        #expect(!near.map(\.tree.id).contains(tree.id), "the shortlist still offers the withdrawn tree")
        let journal = try await Self.journal(api).map(\.treeID)
        #expect(!journal.contains(tree.id), "the Journal still lists the withdrawn tree: \(journal)")
        #expect(journal.contains(kept.id), "the Journal lost the other tree")
        let grove = try await api.grove().map(\.treeID)
        #expect(!grove.contains(tree.id), "My Grove still lists the withdrawn tree")
        #expect(grove.contains(kept.id), "My Grove lost the other tree")
        let yours = try await api.mapMembership(.yours)
        #expect(yours == [kept.id], "the Yours map still holds the withdrawn tree: \(yours)")

        // The adder's own row stays saved.
        let saved = try await store.queue.read { connection -> Int in
            let statement = try connection.prepare(
                "SELECT COUNT(*) AS n FROM visits WHERE id = :id AND deleted_at IS NULL"
            )
            defer { statement.finalize() }
            _ = try statement.bind(own.id.uuidString, forName: ":id")
            return try statement.fetchOne { try $0.int("n") } ?? 0
        }
        #expect(saved == 1, "the adder's own visit was not kept")
    }

    /// The service's grove still lists a tree the person contributed to after it is withdrawn, so
    /// the router's read must drop it too. Red-proof: drop the skip in `groveCityFileRows` — red on
    /// "the service's grove row came back named".
    @Test("a withdrawn tree the service's grove still names is dropped as a rule, not as a lost row")
    func theServicesGroveRowIsDropped() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Fixture.deviceID)
        let tree = try await Fixture.add(api)
        try await store.queue.write { connection in
            try ContributionStore().insert(
                TreeName(treeID: tree.id, name: "Grandmother Cypress", givenBy: nil), connection: connection
            )
        }
        #expect(await api.groveCityFileRows(for: [tree.id]).named[tree.id] != nil, "fixture: the row is not named")

        try await api.withdrawTree(treeID: tree.id)

        let rows = await api.groveCityFileRows(for: [tree.id])
        #expect(rows.named[tree.id] == nil, "the service's grove row came back named")
        #expect(rows.unnamed.contains(tree.id), "the row was dropped as lost, which marks the read degraded")
    }

    /// The phone's own row wins over the cache, withdrawn or not (`CommunityLayer`), so a tile that
    /// still carries the tree cannot bring it back. Red-proof: make `CommunityLayer` prefer the
    /// cache row — red on "a tile page brought the withdrawn tree back".
    @Test("a tile page that still carries the tree does not bring it back")
    func aTilePageDoesNotBringItBack() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Fixture.deviceID)
        let tree = try await Fixture.add(api)
        try await api.withdrawTree(treeID: tree.id)

        let copy = Tree(id: tree.id, source: .community, coordinate: tree.coordinate)
        _ = try await store.queue.write { connection in
            try CommunityTreeCacheStore().apply(
                tile: "t", trees: [copy], withdrawnTreeIDs: [], nextCursor: "c",
                at: Date(), connection: connection
            )
        }
        #expect(try await api.mapContent(in: Self.box(around: tree.coordinate)).markerCount == 0,
                "a tile page brought the withdrawn tree back")
        await #expect(throws: APIError.notFound) { _ = try await api.treeProfile(id: tree.id) }
    }

    // MARK: - 4. The service's answer

    /// **The refusal path.** The service refuses with `conflict`; the tree comes back on this
    /// phone, the row is `failed` with the owner's sentence, and the profile now draws the reason
    /// line. The person retries; the service accepts; the tree goes again.
    ///
    /// Red-proofs, each read by its message:
    /// - remove the restore from `OutboxQueue.settle` — red on "the tree stays hidden after the
    ///   service refused";
    /// - remove the `treeStaysOnTheMap` branch in `recordFailure` — red on the row's reason, which
    ///   reads "This couldn't be sent.";
    /// - remove `withdrawAgain` from the send settlement — red on "the accepted retry left the tree
    ///   on the map".
    @Test("a refused withdrawal brings the tree back with the owner's reason, and an accepted retry takes it off again")
    func aRefusalBringsTheTreeBack() async throws {
        let store = try await CypressStore.inMemory()
        let clock = Clock()
        let api = LocalAPI(store: store, deviceID: Fixture.deviceID, now: { clock.now })
        let service = Service(withdrawalAnswers: [.conflict])
        let queue = OutboxQueue(
            queue: store.queue, apply: APIOutboxTransport(api: api), send: service, now: { clock.now }
        )
        let tree = try await Fixture.add(api)
        _ = try await queue.drain() // the add reaches the service
        clock.advance(by: 60)

        try await api.withdrawTree(treeID: tree.id)
        #expect(try await api.mapContent(in: Self.box(around: tree.coordinate)).markerCount == 0,
                "fixture: the tree did not leave the map")

        clock.advance(by: 60)
        _ = try await queue.drain()
        #expect(await service.offered.contains(.treeWithdrawal), "fixture: the withdrawal was never sent")

        #expect(try await Self.deletedAt(store, tree.id) == nil, "the tree stays hidden after the service refused")
        #expect(try await api.mapContent(in: Self.box(around: tree.coordinate)).markerCount == 1,
                "the refused tree is not back on the map")
        let row = try #require(try await Self.withdrawals(store).first)
        #expect(row.item.state == .failed)
        #expect(row.item.lastError == "Other people have added to this tree, so it stays on the map.",
                "the row reads \(row.item.lastError ?? "nothing")")

        // Screen 17 draws the sentence.
        let snapshot = try await queue.snapshot(treeNames: [tree.id: "Grandmother Cypress"], syncPhotosOnWifiOnly: true)
        let drawn = try #require(OutboxPresentation(snapshot: snapshot, now: clock.now).queue.first {
            $0.id == row.item.id
        })
        #expect(drawn.title == "Tree withdrawn · Grandmother Cypress")
        #expect(drawn.detail == nil)
        #expect(drawn.reason == "Other people have added to this tree, so it stays on the map.")
        #expect(drawn.showsRetryButton)

        // The phone now knows: the profile draws the reason line, not the control.
        #expect(try await api.treeProfile(id: tree.id).treeWithdrawal == .othersHaveAddedToIt)

        // The person retries, and this time the service takes it.
        try await queue.retry(id: row.item.id)
        clock.advance(by: 60)
        _ = try await queue.drain()
        let settled = try #require(try await Self.withdrawals(store).first)
        #expect(settled.item.state == .done, "the retried withdrawal is \(settled.item.state)")
        #expect(try await Self.deletedAt(store, tree.id) != nil, "the accepted retry left the tree on the map")
        await #expect(throws: APIError.notFound) { _ = try await api.treeProfile(id: tree.id) }
    }

    /// Every terminal failure leaves the tree on the service, so every one brings it back, and only
    /// `conflict` reads the owner's sentence. A retryable failure brings nothing back.
    @Test("a forbidden withdrawal also brings the tree back, with the shared sentence; a retryable one does not")
    func otherAnswers() async throws {
        let store = try await CypressStore.inMemory()
        let clock = Clock()
        let api = LocalAPI(store: store, deviceID: Fixture.deviceID, now: { clock.now })
        let service = Service(withdrawalAnswers: [.serverError, .forbidden])
        let queue = OutboxQueue(
            queue: store.queue, apply: APIOutboxTransport(api: api), send: service, now: { clock.now }
        )
        let tree = try await Fixture.add(api)
        _ = try await queue.drain()
        try await api.withdrawTree(treeID: tree.id)

        clock.advance(by: 60)
        _ = try await queue.drain()
        #expect(try await Self.deletedAt(store, tree.id) != nil, "a retryable failure brought the tree back")
        #expect(try #require(try await Self.withdrawals(store).first).item.state == .pending)

        clock.advance(by: 6 * 60 * 60)
        _ = try await queue.drain()
        let row = try #require(try await Self.withdrawals(store).first)
        #expect(row.item.state == .failed, "fixture: the forbidden answer did not fail the row: \(row.item.state)")
        #expect(try await Self.deletedAt(store, tree.id) == nil, "a forbidden withdrawal left the tree hidden")
        #expect(row.item.lastError == "This couldn't be sent.")
        // A refusal for another reason says nothing about other people's work.
        #expect(try await api.treeProfile(id: tree.id).treeWithdrawal == .available)
    }

    // MARK: - 5. The offer

    @Test("the control is offered on the adder's live tree only")
    func theControlIsOfferedToTheAdderOnly() async throws {
        let store = try await CypressStore.inMemory()
        let adder = LocalAPI(store: store, deviceID: Fixture.deviceID)
        let stranger = LocalAPI(store: store, deviceID: Fixture.otherDeviceID)
        let tree = try await Fixture.add(adder)

        #expect(try await adder.treeProfile(id: tree.id).treeWithdrawal == .available)
        #expect(try await stranger.treeProfile(id: tree.id).treeWithdrawal == .unavailable,
                "somebody who did not add the tree is offered its withdrawal")
    }

    /// **Q8 from the phone's own tables.** Only a row by another account that has left the phone
    /// counts. Red-proofs: drop `met.user_id IS NOT NULL` — red on "this device's own signed-out
    /// visit"; drop the `owed` clause — red on "a visit still in the queue".
    @Test("the reason line is drawn for another account's sent visit, and never on a guess")
    func theReasonLineNeedsAFact() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Fixture.deviceID, userID: Fixture.userID)
        let tree = try await Fixture.add(api)

        // This device's own visit, signed out: a sign-in claims those, so it is not somebody else's.
        _ = try await Self.visit(store, on: tree.id, by: .anonymous(deviceID: Fixture.deviceID))
        #expect(try await api.treeProfile(id: tree.id).treeWithdrawal == .available,
                "this device's own signed-out visit drew the reason line")

        // Another account's visit, still in the queue: the service has not seen it yet.
        let queued = try await Self.visit(
            store, on: tree.id, by: Attribution(userID: Self.otherUserID, deviceID: Fixture.deviceID)
        )
        let item = try OutboxPayload.visit(queued).makeItem()
        _ = try await store.queue.write { try OutboxStore().enqueue(item, connection: $0) }
        #expect(try await api.treeProfile(id: tree.id).treeWithdrawal == .available,
                "a visit still in the queue drew the reason line")

        // The same visit once it has reached the service.
        try await store.queue.write { connection in
            try connection.execute("UPDATE outbox SET remote_sent = 1, state = 'done'")
        }
        #expect(try await api.treeProfile(id: tree.id).treeWithdrawal == .othersHaveAddedToIt,
                "another account's sent visit did not draw the reason line")
    }

    /// **Q8 from the service's read.** Red-proof: return `local` from `RoutedAPI.withdrawalOffer`
    /// unchanged — red on "a stranger's photograph did not draw the reason line".
    @Test("a photograph the service served as somebody else's draws the reason line, and the reader's own does not")
    func theServicesPhotographNarrowsTheOffer() {
        let tree = UUID()
        let at = Date(timeIntervalSince1970: 1_790_000_000)
        let own = Photo(treeID: tree, shotType: .fullTree, moderationState: .approved, capturedAt: at)
        let theirs = Photo(treeID: tree, shotType: .leaf, moderationState: .approved, capturedAt: at)

        func delta(_ photos: [Photo]) -> RemoteAPI.TreeCommunityDelta {
            RemoteAPI.TreeCommunityDelta(
                treeID: tree, photos: photos, ownPhotoIDs: [own.id], deletablePhotoIDs: [own.id],
                clientUUIDs: [own.id: UUID()]
            )
        }

        #expect(RoutedAPI.withdrawalOffer(.available, community: delta([own])) == .available,
                "the reader's own photograph drew the reason line")
        #expect(RoutedAPI.withdrawalOffer(.available, community: delta([own, theirs])) == .othersHaveAddedToIt,
                "a stranger's photograph did not draw the reason line")
        #expect(RoutedAPI.withdrawalOffer(.unavailable, community: delta([own, theirs])) == .unavailable,
                "a reader who did not add the tree was given the reason line")
    }

    /// The alert's two messages follow the profile's own "only you can see" rule.
    @Test("the alert says 'only you' exactly when the profile says only the reader can see the tree")
    func theAlertMessageFollowsTheOnlyYouRule() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Fixture.deviceID)
        let tree = try await Fixture.add(api)
        let profile = try await api.treeProfile(id: tree.id)

        let signedOut = TreeProfilePresentation(profile: profile)
        #expect(signedOut.onlyYouCanSeeNote != nil, "fixture: a signed-out adder is not told only they can see it")
        #expect(signedOut.withdrawTreeMessage
                == "Only you can see this tree. It comes off the map. This cannot be undone.")

        let shared = TreeProfile(
            tree: profile.tree, treeWithdrawal: .available, addedByYou: true,
            readerSharing: .sharing, isPublished: true
        )
        #expect(TreeProfilePresentation(profile: shared).withdrawTreeMessage
                == "Everyone using Cypress stops seeing this tree once this is sent. If someone else has visited or photographed it, it stays. This cannot be undone.")
        #expect(TreeProfilePresentation(profile: shared).treeWithdrawal == .available)
    }
}
