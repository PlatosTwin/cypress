import Foundation
import Testing
@testable import Cypress

/// "Anonymized means anonymous, permanently" — the project owner's ruling on #74, made checkable
/// (RULINGS, "the owner's own decisions", 2026-07-26; ERRATA — see
/// E157).
///
/// The defect this suite exists for is a collision between two correct designs. D9 says a
/// contribution with `user_id IS NULL` and this phone's `device_id` is the phone's own unclaimed
/// work, and `claimDevice` moves it onto the account that signs in. `leaveRecords` produces rows in
/// exactly that shape — the account comes off, the installation id stays, because it is `NOT NULL`
/// and was there before the account existed. So records a person deliberately unlinked from
/// themselves were relinked to whoever signed in next on the same phone.
///
/// `AppSchema` v13 marks them, and the marks have to hold in five places for the promise to be
/// worth anything. The sentences below, in the order they can go wrong:
///
/// 1. **the claim skips them** — all four contribution kinds, not the one that is easiest to test;
/// 2. **the device's own work is still claimed** — the tombstone distinguishes *anonymized by a
///    deletion* from *never had an account*, and if it did not, the fix would have broken D9;
/// 3. **the queue cannot smuggle one back** — a contribution written before the deletion and
///    applied after it is born unattributed, and is the one case a tombstone written as a column on
///    the four tables would have missed while looking finished;
/// 4. **nothing on screen shows them** — the journal, the grove, and the count screen 15 states;
/// 5. **the copy says what it costs**, because the accepted price of a permanent tombstone falls on
///    the person themselves as much as on a stranger.
@Suite("A deletion's anonymized records stay nobody's")
struct DeletionTombstoneTests {

    // MARK: - Fixtures

    private static let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-0000000000E1")!
    private static let firstUser = UUID(uuidString: "0E000000-0000-4000-8000-0000000000E2")!
    private static let nextUser = UUID(uuidString: "0E000000-0000-4000-8000-0000000000E3")!
    private static let moment = Date(timeIntervalSince1970: 1_800_000_000)

    private static let contributionTables = ["visits", "observations", "measurements", "care_events"]

    private static func signedIn() async throws -> (store: CypressStore, api: LocalAPI) {
        let store = try await CypressStore.inMemory()
        return (store, LocalAPI(store: store, deviceID: deviceID, userID: firstUser, now: { moment }))
    }

    /// There is no seed in these tests, so the tree is a community add — which `LocalAPI.requireTree`
    /// accepts and an invented UUID does not.
    private static func makeTree(api: LocalAPI, at longitude: Double = -122.44) async throws -> Tree {
        try await api.addTree(
            TreeDraft(
                coordinate: Coordinate(latitude: 37.77, longitude: longitude),
                photoLocalPath: "/tmp/cypress-tombstone-test.jpg",
                attribution: Attribution.anonymous(deviceID: deviceID)
            )
        )
    }

    /// One of each of the four append-only kinds, written straight into the tables.
    private static func writeContributions(
        treeID: UUID,
        attribution: Attribution,
        in store: CypressStore
    ) async throws {
        try await store.queue.write { connection in
            let contributions = ContributionStore()
            try contributions.insert(
                Visit(treeID: treeID, attribution: attribution, note: "leafing out", capturedAt: moment),
                connection: connection
            )
            try contributions.insert(
                TreeObservation(treeID: treeID, attribution: attribution, capturedAt: moment, vitality: .good),
                connection: connection
            )
            try contributions.insert(
                TreeMeasurement.dbh(
                    treeID: treeID,
                    attribution: attribution,
                    capturedAt: moment,
                    quantity: Quantity(value: 31, unit: .centimeters, method: .tape)
                ),
                connection: connection
            )
            try contributions.insert(
                CareEvent(treeID: treeID, attribution: attribution, capturedAt: moment, actions: [.watered]),
                connection: connection
            )
        }
    }

    /// Owners read straight out of SQL, so the assertion is about the rows rather than about a
    /// decoder's opinion of them.
    private static func owners(_ table: String, in store: CypressStore) async throws -> [String?] {
        try await store.queue.read { connection in
            let statement = try connection.prepare("SELECT user_id AS owner FROM \(table) ORDER BY id")
            defer { statement.finalize() }
            return try statement.fetchAll { try $0.stringIfPresent("owner") }
        }
    }

    private static func scalar(_ sql: String, in store: CypressStore) async throws -> Int {
        try await store.queue.read { connection -> Int in
            let statement = try connection.prepare(sql)
            defer { statement.finalize() }
            return try statement.fetchOne { try $0.int("n") } ?? -1
        }
    }

    // MARK: - 1. The claim skips them

    @Test("a record the leaving door anonymized is not adopted by the next account on the phone")
    func theNextAccountDoesNotInheritAnonymizedRecords() async throws {
        let (store, api) = try await Self.signedIn()
        let tree = try await Self.makeTree(api: api)
        try await Self.writeContributions(
            treeID: tree.id,
            attribution: Attribution(userID: Self.firstUser, deviceID: Self.deviceID),
            in: store
        )

        let outcome = try await api.deleteAccount(.leaveRecords)
        #expect(outcome.anonymizedContributions == 4, "fixture: all four kinds were anonymized")

        // Every one of them still carries the installation id, which is the state that made this a
        // defect: `device_id` is NOT NULL and is deliberately not cleared, because clearing it would
        // also unmake the legitimate D9 row the next test is about.
        for table in Self.contributionTables {
            let stillOnThisPhone = try await Self.scalar(
                "SELECT COUNT(*) AS n FROM \(table) WHERE device_id = '\(Self.deviceID.uuidString)'",
                in: store
            )
            #expect(stillOnThisPhone == 1, "\(table): the fix must not work by clearing device_id")
        }

        // Somebody else signs in on the same phone.
        try await api.claimDevice(deviceUUID: Self.deviceID, userID: Self.nextUser)

        for table in Self.contributionTables {
            #expect(
                try await Self.owners(table, in: store) == [nil],
                "\(table) was re-adopted onto the next account signed in on this phone"
            )
        }
    }

    @Test("the tombstone names every table the leaving door anonymizes")
    func everyAnonymizedTableIsTombstoned() async throws {
        let (store, api) = try await Self.signedIn()
        let tree = try await Self.makeTree(api: api)
        try await Self.writeContributions(
            treeID: tree.id,
            attribution: Attribution(userID: Self.firstUser, deviceID: Self.deviceID),
            in: store
        )

        try await api.deleteAccount(.leaveRecords)

        // Four rows, one per kind — a tombstone on three of four is worse than none, because it
        // makes the guarantee look kept.
        #expect(try await Self.scalar(
            "SELECT COUNT(*) AS n FROM anonymized_contributions", in: store
        ) == 4)

        for table in Self.contributionTables {
            let marked = try await Self.scalar(
                """
                SELECT COUNT(*) AS n FROM \(table) t
                 WHERE EXISTS (SELECT 1 FROM anonymized_contributions a
                                WHERE a.client_uuid = t.client_uuid)
                """,
                in: store
            )
            #expect(marked == 1, "\(table)'s anonymized row carries no tombstone")
        }
    }

    // MARK: - 2. The D9 case the fix must not break

    @Test("a device's own unattributed work is still claimed at sign-in")
    func theDevicesOwnWorkIsStillClaimable() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID, now: { Self.moment })
        let tree = try await Self.makeTree(api: api)

        // Never signed in, never deleted: D9's ordinary contributor, whose rows look identical to an
        // anonymized one in every column. The tombstone is the only thing that tells them apart, and
        // this is the test that fails if the fix had cleared `device_id` instead.
        try await Self.writeContributions(
            treeID: tree.id,
            attribution: Attribution.anonymous(deviceID: Self.deviceID),
            in: store
        )

        try await api.claimDevice(deviceUUID: Self.deviceID, userID: Self.nextUser)

        for table in Self.contributionTables {
            #expect(
                try await Self.owners(table, in: store) == [Self.nextUser.uuidString],
                "\(table): D9's own case stopped working"
            )
        }
    }

    @Test("work done on the phone after a deletion belongs to whoever signs in next")
    func workDoneAfterTheDeletionIsStillClaimable() async throws {
        let (store, api) = try await Self.signedIn()
        let tree = try await Self.makeTree(api: api)
        try await Self.writeContributions(
            treeID: tree.id,
            attribution: Attribution(userID: Self.firstUser, deviceID: Self.deviceID),
            in: store
        )
        try await api.deleteAccount(.leaveRecords)

        // The phone keeps being used. This visit is nobody's yet and has never been anybody's, so it
        // is exactly what a claim is for — the tombstone must be about the rows named by one
        // deletion and not about the device from that day on.
        let later = Visit(
            treeID: tree.id,
            attribution: Attribution.anonymous(deviceID: Self.deviceID),
            note: "after the deletion",
            capturedAt: Self.moment.addingTimeInterval(3600)
        )
        try await store.queue.write { connection in
            try ContributionStore().insert(later, connection: connection)
        }

        try await api.claimDevice(deviceUUID: Self.deviceID, userID: Self.nextUser)

        let adopted = try await Self.scalar(
            """
            SELECT COUNT(*) AS n FROM visits
             WHERE client_uuid = '\(later.clientUUID.uuidString)'
               AND user_id = '\(Self.nextUser.uuidString)'
            """,
            in: store
        )
        #expect(adopted == 1, "a visit made after the deletion was not claimed")

        // And the deleted person's visit beside it still is not.
        #expect(try await Self.scalar(
            "SELECT COUNT(*) AS n FROM visits WHERE user_id IS NULL", in: store
        ) == 1)
    }

    // MARK: - 3. The queue, which is where a column-shaped tombstone would have failed

    /// A visit queued before the deletion does not exist as a row when the deletion runs: the outbox
    /// holds it, `forgetAccount` strips the account out of its payload, and `apply` inserts it for
    /// the first time afterwards. So there is nothing to mark at deletion time and nothing marking it
    /// at insert time — it is born in precisely the shape `claimDevice` adopts.
    ///
    /// The tombstone is keyed on `client_uuid` so that it can be written for a row that does not
    /// exist yet and be waiting when the drain finally stores it.
    @Test("a contribution queued before the deletion and drained after it is not adopted either")
    func aQueuedContributionCannotSmuggleItselfOntoTheNextAccount() async throws {
        let (store, api) = try await Self.signedIn()
        let outbox = OutboxQueue(queue: store.queue, transport: APIOutboxTransport(api: api))
        let tree = try await Self.makeTree(api: api)

        let queued = Visit(
            treeID: tree.id,
            attribution: Attribution(userID: Self.firstUser, deviceID: Self.deviceID),
            note: "queued in a dead zone",
            capturedAt: Self.moment
        )
        _ = try await outbox.enqueue(.visit(queued))

        // Nothing has landed yet — this is the state that makes the case real rather than academic.
        #expect(try await Self.scalar("SELECT COUNT(*) AS n FROM visits", in: store) == 0)

        let outcome = try await api.deleteAccount(.leaveRecords)
        #expect(outcome.anonymizedOutboxItems == 1, "fixture: the queued visit was anonymized in place")

        // The phone finds wifi.
        _ = try await outbox.drain()
        #expect(try await Self.scalar("SELECT COUNT(*) AS n FROM visits", in: store) == 1)
        #expect(try await Self.owners("visits", in: store) == [nil], "it must land unattributed")

        try await api.claimDevice(deviceUUID: Self.deviceID, userID: Self.nextUser)
        #expect(
            try await Self.owners("visits", in: store) == [nil],
            "the tail of the deleted person's queue arrived on the next account"
        )
    }

    // MARK: - 4. Nothing on screen shows them

    @Test("the anonymized records are gone from every device-scoped surface")
    func noDeviceScopedSurfaceShowsThem() async throws {
        let (store, api) = try await Self.signedIn()
        let tree = try await Self.makeTree(api: api)
        try await Self.writeContributions(
            treeID: tree.id,
            attribution: Attribution(userID: Self.firstUser, deviceID: Self.deviceID),
            in: store
        )

        #expect(try await api.journal(cursor: nil, limit: 20).items.count == 4, "fixture: the journal has them")

        // Zero, and not because the count is broken: `deviceContributions` counts rows that are
        // *still unattributed*, and these belong to an account. That is what makes the number after
        // the deletion interesting — nulling `user_id` is exactly what would move these four rows
        // into this count, as the phone's to hand to the next person who signs in.
        #expect(try await api.deviceContributions() == .none, "fixture: they are the account's, not the device's")

        try await api.deleteAccount(.leaveRecords)

        // Screen 15's number and the claim have to be one rule read twice: a count that now said
        // four would offer to keep records the claim then declines to move.
        #expect(try await api.deviceContributions() == .none)

        // The journal and the grove are what the next person actually looks at.
        #expect(try await api.journal(cursor: nil, limit: 20).items.isEmpty)
        #expect(try await api.grove().isEmpty)

        // And the records are still on the tree, unattributed, which is the whole point of the door.
        for table in Self.contributionTables {
            #expect(try await Self.scalar("SELECT COUNT(*) AS n FROM \(table)", in: store) == 1)
        }
        #expect(try await api.treeProfile(id: tree.id).visits.items.count == 1)
    }

    // MARK: - 5. The copy, which is what turned this into a defect

    @Test("the leaving door states the price of a permanent tombstone")
    func theCopySaysWhatItCosts() {
        let stays = AccountDeletionCopy.leaveRecordsBody

        // The promise, unchanged.
        #expect(stays.contains("nothing left on them saying they were yours"))

        // And the consequence the owner weighed and accepted, said in the same breath rather than
        // left to be discovered by signing in again to an empty journal. This sentence is the reason
        // #74 was a defect rather than a quirk: the promise was on screen before it was kept.
        #expect(stays.contains("this phone"))
        #expect(stays.contains("do not come back to you"))

        // House style: no spaces around em dashes (ARCHITECTURE §5.7).
        #expect(!stays.contains(" — "))
    }
}
