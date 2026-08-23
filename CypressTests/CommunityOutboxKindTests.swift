import Foundation
import Testing
@testable import Cypress

/// Spec §3.4's nine mutations, which reached a contributor's phone and nothing else.
///
/// `addTree`, `claimSpecies`, `correctSpecies`, `flagWrongSpecies`, `flagNeverExisted`,
/// `setPhotoVote`, `deletePhoto`, `logHazardRedirect` and the two review dismissals were routed
/// straight to `local` because "they have no queue behind them at all". Since #158's wiring round
/// wired a send sink, that is a signed-in contributor's work landing on their phone and on no
/// account, with every layer reporting success.
///
/// This suite is the five sentences the fix has to make true:
///
/// 1. `outbox.kind` admits the ten values, and the migration that widened it **queued nothing**;
/// 2. every one of the ten mutations writes exactly one row, and writes it as locally applied;
/// 3. a mutation that is refused writes no row — the two are one transaction;
/// 4. a drain **sends** such a row and never re-applies it;
/// 5. every payload survives the round trip the queue puts it through, `nil` votes included.
@Suite("Community outbox kinds")
struct CommunityOutboxKindTests {

    private static let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-00000000C001")!
    private static let otherDeviceID = UUID(uuidString: "D0000000-0000-4000-8000-00000000C002")!

    private static var attribution: Attribution { .anonymous(deviceID: deviceID) }

    /// West of Ocean Beach: the seed is the city's *street*-tree inventory, so nothing is inside the
    /// 10 m dedupe radius and the only trees a test contends with are its own
    /// (`SpeciesCorrectionTests.offshore`'s argument).
    private static let offshore = Coordinate(latitude: 37.7600, longitude: -122.5400)

    /// A store with the city file attached, because `claimSpecies` checks the catalog first and an
    /// invented uuid is refused by design.
    private static func seededStore() async throws -> CypressStore {
        let seedURL = try #require(SeedContractTests.seedURL, "no seed database; set CYPRESS_SEED_PATH")
        return try await CypressStore.inMemory(seedURL: seedURL)
    }

    /// A community tree with a photograph, which is what §3.4's other mutations act on.
    ///
    /// Written through `addTree` rather than into the table, because a tree inserted behind the API
    /// would not exercise the writer this suite is about — and because `LocalAPI.requireTree`
    /// refuses an invented UUID.
    private static func makeTree(
        api: LocalAPI,
        path: String,
        at coordinate: Coordinate = offshore
    ) async throws -> Tree {
        FileManager.default.createFile(atPath: path, contents: Data([0xFF, 0xD8, 0xFF, 0xD9]))
        return try await api.addTree(
            TreeDraft(
                coordinate: coordinate,
                photoLocalPath: path,
                attribution: attribution
            )
        )
    }

    /// What the trigger below raises, read back by the test that proves the rollback.
    ///
    /// One constant rather than the same sentence twice: a guard that asserts a message nothing
    /// produces is green for the wrong reason, and the two literals drifting apart is the ordinary
    /// way that happens.
    static let enqueueRefusalMessage = "the queue refused this row"

    /// Makes every `INSERT INTO outbox` fail, and nothing else.
    ///
    /// A trigger rather than dropping the table: the table stays readable, so a mutation that
    /// touches the queue for any *other* reason still behaves normally
    /// (`LocalAPI.deletePhoto` calls `OutboxStore.discardStagedPhoto`), and the failure lands on
    /// exactly the statement under test with a message that says so.
    private static func refuseEveryEnqueue(in store: CypressStore) async throws {
        try await store.queue.write { connection in
            try connection.execute("""
                CREATE TRIGGER cypress_test_refuse_outbox BEFORE INSERT ON outbox
                BEGIN SELECT RAISE(ABORT, '\(enqueueRefusalMessage)'); END;
                """)
        }
    }

    private static func scalar(_ sql: String, in store: CypressStore) async throws -> Int {
        try await store.queue.read { connection -> Int in
            let statement = try connection.prepare(sql)
            defer { statement.finalize() }
            return try statement.fetchOne { try $0.int("n") } ?? -1
        }
    }

    private static func rows(_ store: CypressStore) async throws -> [OutboxStore.Record] {
        try await store.queue.read { connection in
            try OutboxStore().allItems(connection: connection)
        }
    }

    private static func rows(_ store: CypressStore, ofKind kind: OutboxItem.Kind) async throws -> [OutboxStore.Record] {
        try await rows(store).filter { $0.item.kind == kind }
    }

    // MARK: - 1. The vocabulary, and what the migration did not do

    /// The `CHECK` admits every kind the app can build, tested through `Kind.allCases` rather than a
    /// hand-written list.
    ///
    /// A list here would pass on the day an eleventh case is added to the enum and forgotten in the
    /// migration — which is precisely the failure this test exists to catch, since the symptom is a
    /// mutation that succeeds locally and cannot be queued.
    @Test("every kind the app can build is one the outbox can store")
    func theStoredVocabularyCoversEveryKind() async throws {
        let store = try await CypressStore.inMemory()
        for kind in OutboxItem.Kind.allCases {
            let item = OutboxItem(
                kind: kind,
                clientUUID: UUID(),
                payload: Data("{}".utf8),
                createdAt: Date(),
                updatedAt: Date()
            )
            try await store.queue.write { connection in
                try OutboxStore().enqueue(item, connection: connection)
            }
        }
        let stored = try await Self.rows(store)
        let missing = Set(OutboxItem.Kind.allCases).subtracting(stored.map(\.item.kind))
        #expect(missing.isEmpty, "the outbox refused kinds the app can build: \(missing.map(\.rawValue))")
    }

    /// **The ruling, measured.** The migration widens a vocabulary; it must not sweep a single row
    /// that already exists into the queue.
    ///
    /// The setup is a real pre-v17 phone: a community tree somebody added, a review flag they
    /// raised, a vote they cast, a hazard redirect they were shown — all applied locally, none of
    /// them queued, because until this round there was no kind to queue them under. Plus one
    /// ordinary visit in the queue, so "the outbox is empty afterwards" cannot pass by the rebuild
    /// having dropped everything.
    ///
    /// The owner's phone carries local test data of exactly this shape, and a backfill would publish
    /// all of it the first time a build with a send sink drained.
    @Test("the migration widens the vocabulary and enqueues nothing that was already applied")
    func theMigrationDoesNotSweepPreExistingWorkIntoTheQueue() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try connection.configureForWriting()
        _ = try SchemaMigrator.migrate(AppSchema.migrations.filter { $0.version <= 16 }, on: connection)

        let moment = SQLiteTimestamp.string(from: Date(timeIntervalSince1970: 1_800_000_000))
        let tree = UUID(), photo = UUID(), visitRow = UUID(), visitKey = UUID()

        try connection.execute("""
            INSERT INTO community_trees (id, client_uuid, source, lat, lon, status,
                verification_state, placement, created_at, updated_at)
            VALUES ('\(tree.uuidString)','\(UUID().uuidString)','community',37.77,-122.44,'alive',
                'unverified','gps','\(moment)','\(moment)');

            INSERT INTO photos (id, tree_uuid, shot_type, captured_at, created_at, updated_at)
            VALUES ('\(photo.uuidString)','\(tree.uuidString)','full_tree','\(moment)','\(moment)','\(moment)');

            INSERT INTO review_flags (id, tree_uuid, kind, status, created_at, updated_at)
            VALUES ('\(UUID().uuidString)','\(tree.uuidString)','wrong_species','open','\(moment)','\(moment)');

            INSERT INTO photo_votes (id, photo_id, tree_uuid, device_id, vote, created_at, updated_at)
            VALUES ('\(UUID().uuidString)','\(photo.uuidString)','\(tree.uuidString)',
                '\(Self.deviceID.uuidString)',1,'\(moment)','\(moment)');

            INSERT INTO hazard_redirects (id, tree_uuid, category, shown_at)
            VALUES ('\(UUID().uuidString)','\(tree.uuidString)','hanging_or_broken_limb','\(moment)');

            INSERT INTO outbox (id, kind, client_uuid, payload, photo_paths, state, fail_count,
                local_applied, remote_sent, window_started_at, created_at, updated_at)
            VALUES ('\(visitRow.uuidString)','visit','\(visitKey.uuidString)','{}','[]','pending',0,
                0,0,'\(moment)','\(moment)','\(moment)');
            """)

        // Every step above 16, not literally `[17]`: this test is about a v16 database reaching the
        // current schema, and it must not fail the day an unrelated migration is added.
        let expected = AppSchema.migrations.map(\.version).filter { $0 > 16 }
        let applied = try SchemaMigrator.migrate(AppSchema.migrations, on: connection)
        #expect(applied == expected, "migrating a v16 database applied \(applied), expected \(expected)")

        let queued = try OutboxStore().allItems(connection: connection)
        let kinds = queued.map(\.item.kind.rawValue)
        #expect(queued.map(\.item.clientUUID) == [visitKey],
                "the migration queued \(queued.count) rows (\(kinds)); only the already-queued visit may be there")

        // And the widening actually happened — otherwise "nothing was enqueued" is true for the
        // uninteresting reason that the migration did nothing at all.
        try connection.execute("""
            INSERT INTO outbox (id, kind, client_uuid, payload, state, fail_count,
                local_applied, remote_sent, window_started_at, created_at, updated_at)
            VALUES ('\(UUID().uuidString)','add_tree','\(UUID().uuidString)','{}','pending',0,
                1,0,'\(moment)','\(moment)','\(moment)');
            """)
    }

    // MARK: - 2. Every mutation writes a row, and writes it applied

    @Test("adding a tree queues the addition, keyed on the tree this device minted")
    func addingATreeQueuesIt() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let tree = try await Self.makeTree(api: api, path: NSTemporaryDirectory() + "cypress-s34-add.jpg")

        let queued = try await Self.rows(store, ofKind: .addTree)
        #expect(queued.count == 1, "adding a tree queued \(queued.count) rows")
        let record = try #require(queued.first)
        #expect(record.locallyApplied, "the row was queued unapplied; a drain would apply it twice")
        #expect(!record.remoteSent)
        guard case let .addTree(addition) = try OutboxPayload.decode(
            kind: record.item.kind, from: record.item.payload
        ) else {
            Issue.record("the payload did not decode as an addition")
            return
        }
        #expect(addition.treeID == tree.id, "the queued row names a tree nothing else on this device does")
        #expect(addition.coordinate.latitude == Self.offshore.latitude)
        #expect(addition.attribution.deviceID == Self.deviceID)
    }

    @Test("naming, correcting, reporting and dismissing a species each queue their own kind")
    func theSpeciesSeamQueuesItsFourActs() async throws {
        let store = try await Self.seededStore()
        let api = LocalAPI(store: store, deviceID: Self.deviceID, role: .moderator)
        let tree = try await Self.makeTree(api: api, path: NSTemporaryDirectory() + "cypress-s34-species.jpg")
        let (first, second) = try await Self.twoSpecies(api)

        _ = try await api.claimSpecies(treeID: tree.id, speciesID: first)
        #expect(try await Self.rows(store, ofKind: .speciesClaim).count == 1)

        _ = try await api.correctSpecies(treeID: tree.id, speciesID: second)
        #expect(try await Self.rows(store, ofKind: .speciesCorrection).count == 1)

        // A report by somebody who is not the namer, so the "is it yours" guard lets it through.
        let stranger = LocalAPI(store: store, deviceID: Self.otherDeviceID)
        try await stranger.flagWrongSpecies(treeID: tree.id)
        let reports = try await Self.rows(store, ofKind: .wrongSpeciesReport)
        #expect(reports.count == 1)
        let report = try #require(reports.first)
        guard case let .wrongSpeciesReport(raised) = try OutboxPayload.decode(
            kind: report.item.kind, from: report.item.payload
        ) else {
            Issue.record("the payload did not decode as a report")
            return
        }
        #expect(raised.treeID == tree.id)
        #expect(raised.kind == .wrongSpecies)
        #expect(raised.attribution.deviceID == Self.otherDeviceID)

        try await api.dismissSpeciesReview(flagID: raised.flagID)
        let dismissals = try await Self.rows(store, ofKind: .speciesReviewDismissal)
        #expect(dismissals.count == 1, "a dismissal queued \(dismissals.count) rows")
        guard case let .speciesReviewDismissal(dismissal) = try OutboxPayload.decode(
            kind: try #require(dismissals.first).item.kind,
            from: try #require(dismissals.first).item.payload
        ) else {
            Issue.record("the payload did not decode as a dismissal")
            return
        }
        #expect(dismissal.flagID == raised.flagID, "the dismissal names a flag nothing raised")
        #expect(dismissal.treeID == tree.id, "a queued item with no tree cannot be sent")
    }

    @Test("reporting and dismissing a record defect each queue their own kind")
    func theRecordSeamQueuesItsTwoActs() async throws {
        let store = try await Self.seededStore()
        let api = LocalAPI(store: store, deviceID: Self.deviceID, role: .moderator)
        let tree = try await Self.makeTree(api: api, path: NSTemporaryDirectory() + "cypress-s34-record.jpg")

        try await api.flagNeverExisted(treeID: tree.id)
        let reports = try await Self.rows(store, ofKind: .neverExistedReport)
        #expect(reports.count == 1)
        guard case let .neverExistedReport(raised) = try OutboxPayload.decode(
            kind: try #require(reports.first).item.kind,
            from: try #require(reports.first).item.payload
        ) else {
            Issue.record("the payload did not decode as a report")
            return
        }
        #expect(raised.kind == .neverExisted)

        try await api.dismissRecordReview(flagID: raised.flagID)
        #expect(try await Self.rows(store, ofKind: .recordReviewDismissal).count == 1)
    }

    @Test("a photo vote queues the vote it cast, and taking it back queues the withdrawal")
    func aPhotoVoteQueuesTheStateItSet() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let tree = try await Self.makeTree(api: api, path: NSTemporaryDirectory() + "cypress-s34-vote.jpg")
        let photo = try #require(try await api.treeProfile(id: tree.id).photos.items.first?.id)

        try await api.setPhotoVote(photoID: photo, vote: .up)
        try await api.setPhotoVote(photoID: photo, vote: nil)

        let votes = try await Self.rows(store, ofKind: .photoVote)
        #expect(votes.count == 2, "two decisions queued \(votes.count) rows")
        let decoded: [PhotoVote?] = try votes.map { record in
            guard case let .photoVote(cast) = try OutboxPayload.decode(
                kind: record.item.kind, from: record.item.payload
            ) else { return nil }
            return cast.vote
        }
        #expect(decoded == [.up, nil], "the withdrawal did not travel as a decision: \(decoded)")

        // The tree the vote is about, resolved from the photograph. Without it the item names no
        // tree and `POST /sync` refuses it.
        guard case let .photoVote(cast) = try OutboxPayload.decode(
            kind: try #require(votes.first).item.kind, from: try #require(votes.first).item.payload
        ) else {
            Issue.record("the payload did not decode as a vote")
            return
        }
        #expect(cast.treeID == tree.id)
        #expect(cast.photoID == photo)
    }

    @Test("withdrawing a photograph queues the withdrawal")
    func deletingAPhotoQueuesTheWithdrawal() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let tree = try await Self.makeTree(api: api, path: NSTemporaryDirectory() + "cypress-s34-delete.jpg")
        let photo = try #require(try await api.treeProfile(id: tree.id).photos.items.first?.id)

        let deletion = try await api.deletePhoto(id: photo)
        #expect(deletion.photoID == photo, "PR #94's report changed shape")

        let queued = try await Self.rows(store, ofKind: .photoWithdrawal)
        #expect(queued.count == 1, "withdrawing a photograph queued \(queued.count) rows")
        let record = try #require(queued.first)
        #expect(record.locallyApplied)
        guard case let .photoWithdrawal(withdrawal) = try OutboxPayload.decode(
            kind: record.item.kind, from: record.item.payload
        ) else {
            Issue.record("the payload did not decode as a withdrawal")
            return
        }
        #expect(withdrawal.photoID == photo)
        #expect(withdrawal.treeID == tree.id)
    }

    @Test("a hazard redirect queues the moment the sheet was shown, not the moment it was logged")
    func aHazardRedirectQueuesItsOwnTime() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let tree = try await Self.makeTree(api: api, path: NSTemporaryDirectory() + "cypress-s34-hazard.jpg")
        let shown = Date(timeIntervalSince1970: 1_700_000_000)

        try await api.logHazardRedirect(
            HazardRedirectEvent(treeID: tree.id, category: .hangingOrBrokenLimb, shownAt: shown)
        )

        let queued = try await Self.rows(store, ofKind: .hazardRedirect)
        #expect(queued.count == 1)
        let record = try #require(queued.first)
        let payload = try OutboxPayload.decode(kind: record.item.kind, from: record.item.payload)
        #expect(payload.occurredAt == shown, "the report was dated the log call rather than the sheet")
        #expect(payload.treeID == tree.id)
        // The row's own clock is not the mutation's: `createdAt` starts the 48 h window, and dating
        // it 2023 would open a queue row that had already expired.
        #expect(record.item.createdAt > shown, "the queue row inherited the mutation's clock")
    }

    // MARK: - 3. A refused mutation queues nothing

    /// The mutation and its row are one transaction, so a refusal leaves neither.
    ///
    /// **What this proves and what it does not.** The refusal it exercises is
    /// `PhotoOwner.permitsRemoval(by:takenOnDevice:)`, which throws before the transaction opens —
    /// so what is measured is that nothing is queued ahead of the gates. PR #94's second gate, the
    /// owner predicate inside the tombstone `UPDATE` (`ContributionStore.removalPredicate`), is not
    /// reachable from here without racing two deletions; the row is queued after that `UPDATE` has
    /// matched, and `LocalAPI.deletePhoto` states the ordering at the line that does it.
    @Test("a refused deletion queues nothing")
    func aRefusedMutationQueuesNothing() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let tree = try await Self.makeTree(api: api, path: NSTemporaryDirectory() + "cypress-s34-refused.jpg")
        let photo = try #require(try await api.treeProfile(id: tree.id).photos.items.first?.id)

        let stranger = LocalAPI(store: store, deviceID: Self.otherDeviceID)
        await #expect(throws: APIError.forbidden) {
            _ = try await stranger.deletePhoto(id: photo)
        }

        #expect(
            try await Self.rows(store, ofKind: .photoWithdrawal).isEmpty,
            "a refused deletion queued a withdrawal, which would send a deletion the gate refused"
        )
    }

    @Test("a species claim refused for want of a catalog entry queues nothing")
    func aRefusedClaimQueuesNothing() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let tree = try await Self.makeTree(api: api, path: NSTemporaryDirectory() + "cypress-s34-noclaim.jpg")

        await #expect(throws: (any Error).self) {
            _ = try await api.claimSpecies(treeID: tree.id, speciesID: UUID())
        }
        #expect(try await Self.rows(store, ofKind: .speciesClaim).isEmpty)
    }

    // MARK: - 4. A drain sends such a row and never re-applies it

    /// The tally is the point, for the reason `OutboxApplySendSplitTests` gives: `LocalAPI` dedupes
    /// on the unique `client_uuid` index, so "it was not applied twice" is not provable by counting
    /// rows. Counting what each **sink was offered** is the question that separates them.
    private actor CountingApply: OutboxTransport {
        private let inner: any OutboxTransport
        private(set) var offered: [UUID] = []

        init(_ inner: any OutboxTransport) { self.inner = inner }

        func sync(_ items: [OutboxItem]) async throws -> [SyncResult] {
            offered.append(contentsOf: items.map(\.clientUUID))
            return try await inner.sync(items)
        }

        @discardableResult
        func uploadPhoto(_ photo: OutboxPhoto, for item: OutboxItem) async throws -> AppliedPhoto {
            try await inner.uploadPhoto(photo, for: item)
        }
    }

    private actor CountingSend: OutboxSendSink {
        private(set) var offered: [UUID] = []
        private(set) var photosOffered: [UUID] = []

        func sync(_ items: [OutboxItem]) async throws -> [SyncResult] {
            offered.append(contentsOf: items.map(\.clientUUID))
            return items.map { SyncResult(clientUUID: $0.clientUUID, status: .applied) }
        }

        func uploadPhoto(_ photo: OutboxStore.PhotoRow, for item: OutboxItem) async throws {
            photosOffered.append(photo.id)
        }
    }

    @Test("a drain sends a §3.4 row and never offers it to the apply sink")
    func aDrainSendsWithoutReapplying() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let apply = CountingApply(APIOutboxTransport(api: api))
        let send = CountingSend()
        let queue = OutboxQueue(queue: store.queue, apply: apply, send: send)

        let tree = try await Self.makeTree(api: api, path: NSTemporaryDirectory() + "cypress-s34-drain.jpg")
        let queued = try #require(try await Self.rows(store, ofKind: .addTree).first)

        let report = try await queue.drain()
        #expect(report.sent == 1, "\(report.sent) rows were sent")

        let applied = await apply.offered
        #expect(
            !applied.contains(queued.item.clientUUID),
            "the addition was offered to the apply sink; applying it again is a second tree"
        )
        let sent = await send.offered
        #expect(sent == [queued.item.clientUUID], "the addition was not sent: \(sent)")

        let settled = try #require(try await Self.rows(store, ofKind: .addTree).first)
        #expect(settled.remoteSent, "the row settled without being marked sent")
        #expect(settled.item.state == .done)
        // And the tree is still one tree.
        #expect(try await api.treesNear(tree.coordinate, radiusM: 25, limit: 10).count == 1)
    }

    /// The unreachable arm, exercised. `LocalAPI.apply` refuses §3.4's kinds, and an arm nothing
    /// tests is an arm the next change will reach.
    @Test("the apply sink refuses a §3.4 row rather than performing the mutation a second time")
    func theApplySinkRefusesTheseKinds() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let tree = try await Self.makeTree(api: api, path: NSTemporaryDirectory() + "cypress-s34-refuse.jpg")

        let item = try OutboxPayload.hazardRedirect(
            HazardRedirectReport(
                clientUUID: UUID(),
                event: HazardRedirectEvent(treeID: tree.id, category: .hangingOrBrokenLimb),
                attribution: Self.attribution
            )
        ).makeItem()

        let results = try await api.sync([item])
        #expect(results.count == 1)
        let verdict = try #require(results.first)
        #expect(verdict.status == .failed, "the apply sink performed a §3.4 mutation a second time")
        #expect(
            verdict.error == .validationFailed,
            "a retryable code would burn 48 h on an answer that will not change; got \(String(describing: verdict.error))"
        )
    }

    // MARK: - 3b. The other direction: an enqueue that fails takes the mutation with it

    /// **The direction the design claim is actually about, which nothing else here could see.**
    ///
    /// `aRefusedMutationQueuesNothing` and `aRefusedClaimQueuesNothing` prove *mutation refused ⇒ no
    /// row*. The header on `LocalAPI.queueAppliedMutation` claims the converse — that the row and
    /// the mutation are one write, so a failure to queue rolls the mutation back. That is true by
    /// construction today (`DatabaseQueue.write` is `connection.transaction`, which rolls back on any
    /// throw), and **a change that destroyed it would leave this suite green**: moving a
    /// `queueAppliedMutation` call into a second transaction is observationally identical in every
    /// happy path. This project's dominant defect is a guard that stays green while the defect is
    /// present, and that is exactly this shape.
    ///
    /// **The control is load-bearing.** Without it, "no flag was written" passes for the wrong
    /// reason the day `flagWrongSpecies` starts refusing for a domain reason — a missing head, an
    /// already-open report — and the test would certify a rollback that never happened. So the same
    /// mutation runs first with the queue healthy and is asserted to write its flag, and the thrown
    /// error is checked to be the trigger's, not the boundary's.
    @Test("an enqueue that fails rolls the mutation back with it")
    func aFailedEnqueueRollsTheMutationBack() async throws {
        let store = try await Self.seededStore()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let (species, _) = try await Self.twoSpecies(api)

        // ── The control: the identical mutation, with the queue working. ──────────────────────
        let control = try await Self.makeTree(
            api: api, path: NSTemporaryDirectory() + "cypress-s34-atomic-control.jpg"
        )
        _ = try await api.claimSpecies(treeID: control.id, speciesID: species)
        let stranger = LocalAPI(store: store, deviceID: Self.otherDeviceID)
        try await stranger.flagWrongSpecies(treeID: control.id)
        let controlFlags = try await Self.scalar(
            "SELECT COUNT(*) AS n FROM review_flags WHERE tree_uuid = '\(control.id.uuidString)'",
            in: store
        )
        // Without this the assertion below passes the day `flagWrongSpecies` starts refusing for a
        // domain reason, certifying a rollback that never happened.
        #expect(controlFlags == 1, "fixture: with the queue healthy the mutation wrote \(controlFlags) flags")

        // A second tree, far enough away that its own 10 m dedupe does not refuse it.
        let subject = try await Self.makeTree(
            api: api,
            path: NSTemporaryDirectory() + "cypress-s34-atomic-subject.jpg",
            at: Coordinate(latitude: Self.offshore.latitude + 0.01, longitude: Self.offshore.longitude)
        )
        _ = try await api.claimSpecies(treeID: subject.id, speciesID: species)

        // ── Now the queue refuses everything. ─────────────────────────────────────────────────
        try await Self.refuseEveryEnqueue(in: store)

        var thrown: (any Error)?
        do {
            try await stranger.flagWrongSpecies(treeID: subject.id)
        } catch {
            thrown = error
        }
        let failure = try #require(thrown, "the mutation succeeded although its queue row could not be written")
        let sqlite = try #require(
            failure as? SQLiteError,
            "the refusal came from the boundary, not the enqueue, so it proves nothing: \(failure)"
        )
        // **The type alone does not identify the thrower.** `SQLiteError` is what every statement in
        // this path raises, so a constraint this fixture did not install — or a later refusal
        // somewhere else in `flagWrongSpecies` — satisfies `is SQLiteError` perfectly while proving
        // nothing about the enqueue. The trigger names itself, so the assertion reads that name
        // (PR #103 review).
        #expect(
            sqlite.message.contains(Self.enqueueRefusalMessage),
            """
            the enqueue was not what refused: expected sqlite3 to report \
            "\(Self.enqueueRefusalMessage)", the message this test's own trigger raises, and got \
            "\(sqlite.message)". A rollback proved against somebody else's failure is not a proof.
            """
        )

        let survivingFlags = try await Self.scalar(
            "SELECT COUNT(*) AS n FROM review_flags WHERE tree_uuid = '\(subject.id.uuidString)'",
            in: store
        )
        #expect(survivingFlags == 0,
                "\(survivingFlags) flags survived an enqueue that failed; the row and the mutation are two writes")

        // The same, on a second mutation shape and a second table — the hazard log, which has no
        // boundary refusal of its own and so can only fail at the enqueue.
        do {
            try await api.logHazardRedirect(
                HazardRedirectEvent(treeID: subject.id, category: .hangingOrBrokenLimb)
            )
            Issue.record("the hazard redirect was logged although its queue row could not be written")
        } catch {
            #expect(error is SQLiteError, "the hazard log failed for some other reason: \(error)")
        }
        let survivingLines = try await Self.scalar("SELECT COUNT(*) AS n FROM hazard_redirects", in: store)
        #expect(survivingLines == 0,
                "\(survivingLines) hazard log lines survived an enqueue that failed")
    }

    /// A clear against a photograph this owner never voted on queues nothing.
    ///
    /// Withdrawing a vote that was never cast is not an act, and a `photo_vote` contribution saying
    /// it happened is a record of something nobody did. Harmless while nothing counts these and not
    /// harmless once something does — which is the wrong moment to find out.
    @Test("clearing a vote nobody cast queues nothing, and clearing a real one queues the withdrawal")
    func aNoOpVoteClearQueuesNothing() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let tree = try await Self.makeTree(api: api, path: NSTemporaryDirectory() + "cypress-s34-noop.jpg")
        let photo = try #require(try await api.treeProfile(id: tree.id).photos.items.first?.id)

        try await api.setPhotoVote(photoID: photo, vote: nil)
        #expect(
            try await Self.rows(store, ofKind: .photoVote).isEmpty,
            "a clear against a photograph nobody voted on queued a withdrawal of a vote that never existed"
        )

        // The control, and it is what stops the guard above passing by clearing never queueing at
        // all: a clear that really does remove a vote is still an act, and still queues.
        try await api.setPhotoVote(photoID: photo, vote: .up)
        try await api.setPhotoVote(photoID: photo, vote: nil)
        let votes = try await Self.rows(store, ofKind: .photoVote)
        #expect(votes.count == 2, "a real vote and its withdrawal queued \(votes.count) rows")
        let decoded: [PhotoVote?] = try votes.map { record in
            guard case let .photoVote(cast) = try OutboxPayload.decode(
                kind: record.item.kind, from: record.item.payload
            ) else { return nil }
            return cast.vote
        }
        #expect(decoded == [.up, nil], "the withdrawal of a real vote did not travel: \(decoded)")
    }

    // MARK: - 4b. Account deletion reaches these rows

    /// **The under-deletion this round had to close.** `OutboxStore.forgetAccount` named six kinds
    /// and one payload shape — a top-level `$.userID`. §3.4's ten carry the `Attribution` as an
    /// object, so `$.userID` matches nothing on them: a signed-in contributor's queued species
    /// correction, photo withdrawal or hazard redirect would have survived their own account
    /// deletion still naming the account, and drained to the service afterwards.
    ///
    /// RULINGS R3's stated failure mode is deleting differently from what was asked, and this is the
    /// quiet half of it: every layer reports success while the rows go untouched.
    @Test("deleting an account anonymizes its queued §3.4 rows rather than leaving them naming it")
    func deletionReachesTheNewKinds() async throws {
        let userID = UUID(uuidString: "0E000000-0000-4000-8000-00000000C0A1")!
        let store = try await Self.seededStore()
        let api = LocalAPI(store: store, deviceID: Self.deviceID, userID: userID)
        let tree = try await Self.makeTree(api: api, path: NSTemporaryDirectory() + "cypress-s34-deleted.jpg")

        let queued = try #require(try await Self.rows(store, ofKind: .addTree).first)
        guard case let .addTree(before) = try OutboxPayload.decode(
            kind: queued.item.kind, from: queued.item.payload
        ) else {
            Issue.record("the payload did not decode as an addition")
            return
        }
        #expect(before.attribution.userID == userID, "fixture: the row does not name the account")

        let outcome = try await api.deleteAccount(.leaveRecords)
        let anonymized = outcome.anonymizedOutboxItems
        #expect(anonymized >= 1, "the deletion anonymized \(anonymized) queued rows, expected the addition among them")

        let after = try #require(try await Self.rows(store, ofKind: .addTree).first)
        guard case let .addTree(stripped) = try OutboxPayload.decode(
            kind: after.item.kind, from: after.item.payload
        ) else {
            Issue.record("the anonymized payload no longer decodes")
            return
        }
        #expect(stripped.attribution.userID == nil, "the queued addition still names the deleted account")
        #expect(stripped.attribution.deviceID == Self.deviceID, "the installation id must not be cleared")
        #expect(stripped.treeID == tree.id, "anonymizing rewrote something other than the owner")

        // And the tombstone was written for the key, so an item that drains after the deletion comes
        // back `duplicate` rather than resurrecting the account.
        let marked = try await store.queue.read { connection -> Int in
            let statement = try connection.prepare("""
                SELECT COUNT(*) AS n FROM anonymized_contributions WHERE client_uuid = :key COLLATE NOCASE
                """)
            defer { statement.finalize() }
            _ = try statement.bind([":key": after.item.clientUUID.uuidString])
            return try statement.fetchOne { try $0.int("n") } ?? 0
        }
        #expect(marked == 1, "the queued addition's key was not tombstoned")
    }

    // MARK: - 5. The round trip

    @Test("every §3.4 payload survives the round trip the queue puts it through")
    func everyPayloadRoundTrips() throws {
        let tree = UUID(), photo = UUID(), flag = UUID(), species = UUID()
        let moment = Date(timeIntervalSince1970: 1_700_000_000)
        let who = Self.attribution

        let payloads: [OutboxPayload] = [
            .addTree(TreeAddition(
                clientUUID: UUID(), treeID: tree, attribution: who,
                coordinate: Coordinate(latitude: 37.77, longitude: -122.44),
                address: "1 Alameda", placement: .contributorPlaced,
                speciesID: species, landContext: .cityPark, occurredAt: moment
            )),
            .speciesClaim(SpeciesStatement(
                clientUUID: UUID(), treeID: tree, speciesID: species,
                attribution: who, occurredAt: moment
            )),
            .speciesCorrection(SpeciesStatement(
                clientUUID: UUID(), treeID: tree, speciesID: species,
                attribution: who, occurredAt: moment
            )),
            .wrongSpeciesReport(ReviewReport(
                clientUUID: UUID(), flagID: flag, treeID: tree, kind: .wrongSpecies,
                attribution: who, occurredAt: moment
            )),
            .neverExistedReport(ReviewReport(
                clientUUID: UUID(), flagID: flag, treeID: tree, kind: .neverExisted,
                attribution: who, occurredAt: moment
            )),
            .speciesReviewDismissal(ReviewDismissal(
                clientUUID: UUID(), flagID: flag, treeID: tree, attribution: who, occurredAt: moment
            )),
            .recordReviewDismissal(ReviewDismissal(
                clientUUID: UUID(), flagID: flag, treeID: tree, attribution: who, occurredAt: moment
            )),
            .photoVote(PhotoVoteCast(
                clientUUID: UUID(), photoID: photo, treeID: tree, vote: .down,
                attribution: who, occurredAt: moment
            )),
            .photoVote(PhotoVoteCast(
                clientUUID: UUID(), photoID: photo, treeID: tree, vote: nil,
                attribution: who, occurredAt: moment
            )),
            .photoWithdrawal(PhotoWithdrawal(
                clientUUID: UUID(), photoID: photo, treeID: tree, attribution: who, occurredAt: moment
            )),
            .hazardRedirect(HazardRedirectReport(
                clientUUID: UUID(),
                event: HazardRedirectEvent(treeID: tree, category: .hangingOrBrokenLimb, shownAt: moment),
                attribution: who
            ))
        ]

        for payload in payloads {
            let restored = try OutboxPayload.decode(kind: payload.kind, from: payload.encoded())
            #expect(restored == payload, "\(payload.kind.rawValue) did not survive the round trip")
            #expect(restored.treeID == tree)
            #expect(restored.occurredAt == moment)
            #expect(restored.ownerDeviceID == Self.deviceID)
            #expect(restored.ownerUserID == nil)
            #expect(restored.isAppliedBeforeItIsQueued)
        }
    }

    /// A withdrawn vote is `null` on the wire and not an absent key.
    ///
    /// The synthesized encoder writes `encodeIfPresent`, which drops the key on exactly the value
    /// that carries a decision. `POST /sync`'s `is_favorite` is the same trap already sprung once:
    /// as a plain `bool`, an item that omitted the field recorded `false` and answered `applied`, so
    /// "the heart went off, the client was told it worked, and nothing anywhere errored."
    @Test("a withdrawn vote travels as an explicit null, never as an absent key")
    func aWithdrawnVoteIsWrittenOut() throws {
        let payload = OutboxPayload.photoVote(PhotoVoteCast(
            clientUUID: UUID(), photoID: UUID(), treeID: UUID(), vote: nil,
            attribution: Self.attribution, occurredAt: Date()
        ))
        let json = try #require(
            try JSONSerialization.jsonObject(with: payload.encoded()) as? [String: Any]
        )
        #expect(json.keys.contains("vote"), "the key was dropped; a reader cannot tell 'cleared' from 'unsaid'")
        #expect(json["vote"] is NSNull, "the key is present and is not null: \(String(describing: json["vote"]))")
    }

    // MARK: - Helpers

    /// Two species ids the catalog will actually resolve, since `claimSpecies` checks the catalog
    /// first and an invented uuid is refused.
    private static func twoSpecies(_ api: LocalAPI) async throws -> (UUID, UUID) {
        let plane = try #require(await api.searchSpecies(query: "Platanus", limit: 5).first,
                                 "the catalog answered no Platanus")
        let oak = try #require(
            await api.searchSpecies(query: "Quercus", limit: 5).first { $0.id != plane.id },
            "the catalog answered no second species"
        )
        return (plane.id, oak.id)
    }
}
