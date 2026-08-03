import Foundation
import Testing
@testable import Cypress

/// D9's promise, which screen 15 is the sentence for: "everything you have already done comes with
/// you." `POST /devices/claim` is the mechanism (BUILD-PLAN §6), and this suite is what makes the
/// promise checkable.
///
/// Four things, in the order they can go wrong:
///
/// 1. every kind of record a device can write while anonymous arrives on the account;
/// 2. the count screen 15 states is the count of exactly those records, and it goes to nothing once
///    they are claimed;
/// 3. **a mutation that was queued before sign-in and applied after it comes with you too** — the
///    gap the outbox opens between writing a contribution and applying it, which `claimDevice`'s
///    one-shot sweep could not close on its own;
/// 4. claiming twice, or by somebody else, moves nothing it should not.
@Suite("Signing in keeps what the device made")
struct DeviceClaimTests {

    private static let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-0000000000B1")!
    private static let userID = UUID(uuidString: "0E000000-0000-4000-8000-0000000000B2")!
    private static let strangerID = UUID(uuidString: "0E000000-0000-4000-8000-0000000000B3")!

    /// There is no seed in these tests, so the tree is a community add — which `LocalAPI.requireTree`
    /// accepts and an invented UUID does not.
    private static func makeTree(api: LocalAPI, at longitude: Double = -122.44) async throws -> Tree {
        try await api.addTree(
            TreeDraft(
                coordinate: Coordinate(latitude: 37.77, longitude: longitude),
                photoLocalPath: "/tmp/cypress-claim-test.jpg",
                attribution: Attribution.anonymous(deviceID: deviceID)
            )
        )
    }

    /// One of each of the four contribution kinds plus D4's reminder, as an anonymous device writes
    /// them: through the outbox first, then drained (ARCHITECTURE §4).
    private static func contributeEverything(
        api: LocalAPI,
        outbox: OutboxQueue,
        treeID: UUID
    ) async throws {
        let attribution = Attribution.anonymous(deviceID: deviceID)
        let moment = Date(timeIntervalSince1970: 1_780_000_000)

        _ = try await outbox.enqueue(
            .visit(Visit(treeID: treeID, attribution: attribution, note: "hello", capturedAt: moment))
        )
        _ = try await outbox.enqueue(
            .observation(TreeObservation(
                treeID: treeID,
                attribution: attribution,
                capturedAt: moment,
                vitality: .good
            ))
        )
        _ = try await outbox.enqueue(
            .measurement(TreeMeasurement.dbh(
                treeID: treeID,
                attribution: attribution,
                capturedAt: moment,
                quantity: Quantity(value: 31, unit: .centimeters, method: .tape)
            ))
        )
        _ = try await outbox.enqueue(
            .careEvent(CareEvent(
                treeID: treeID,
                attribution: attribution,
                capturedAt: moment,
                actions: [.watered]
            ))
        )
        _ = try await outbox.enqueue(
            .privateReminder(PrivateReminder(
                owner: ReminderOwner(attribution),
                treeID: treeID,
                category: .hangingOrBrokenLimb
            ))
        )
        _ = try await outbox.drain()
    }

    /// Who owns each of the five kinds, read straight out of SQL so the assertion is about the rows
    /// rather than about a decoder's opinion of them.
    private static func owners(
        in store: CypressStore,
        table: String,
        ownerColumn: String = "user_id"
    ) async throws -> [String?] {
        try await store.queue.read { connection in
            let statement = try connection.prepare("SELECT \(ownerColumn) AS owner FROM \(table)")
            defer { statement.finalize() }
            return try statement.fetchAll { try $0.stringIfPresent("owner") }
        }
    }

    // MARK: - 1. Everything comes with you

    @Test("every kind of anonymous contribution arrives on the account")
    func claimMovesEveryKind() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let outbox = OutboxQueue(queue: store.queue, transport: APIOutboxTransport(api: api))
        let tree = try await Self.makeTree(api: api)
        try await Self.contributeEverything(api: api, outbox: outbox, treeID: tree.id)

        // Before: five rows, nobody's.
        for table in ["visits", "observations", "measurements", "care_events", "private_reminders"] {
            let owners = try await Self.owners(in: store, table: table)
            #expect(owners == [nil], "\(table) should hold one unattributed row before the claim")
        }

        try await api.claimDevice(deviceUUID: Self.deviceID, userID: Self.userID)

        // After: the same five rows, now the account's. Nothing was inserted and nothing deleted —
        // contributions are append-only (DECISIONS §3.7), so a claim that "worked" by rewriting the
        // history would be the worse failure.
        for table in ["visits", "observations", "measurements", "care_events", "private_reminders"] {
            let owners = try await Self.owners(in: store, table: table)
            #expect(owners.count == 1, "\(table) gained or lost a row during the claim")
            #expect(owners.first ?? nil == Self.userID.uuidString, "\(table) was not adopted")
        }

        // E23's exclusive ownership: the reminder gains the account and loses the device link in the
        // same statement, so it is never both and never neither.
        let reminderDevices = try await Self.owners(in: store, table: "private_reminders", ownerColumn: "device_id")
        #expect(reminderDevices == [nil])
    }

    /// The photo that came with the visit. Photos carry no owner of their own — they hang off the
    /// visit — so "what survives sign-in" has to be checked at the join rather than at the column.
    @Test("a photo survives because its visit does")
    func photosFollowTheirVisit() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let tree = try await Self.makeTree(api: api)

        // `addTree` requires a photo, so the tree already has one on it.
        let before = try await api.treeProfile(id: tree.id).photos.items.count
        #expect(before == 1)

        try await api.claimDevice(deviceUUID: Self.deviceID, userID: Self.userID)

        let after = try await api.treeProfile(id: tree.id).photos.items.count
        #expect(after == before, "the claim must not touch photographs")
    }

    // MARK: - 2. The number screen 15 says

    @Test("the count screen 15 states is what the claim would move, and it empties when it does")
    func deviceContributionsMatchTheClaim() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let outbox = OutboxQueue(queue: store.queue, transport: APIOutboxTransport(api: api))
        let tree = try await Self.makeTree(api: api)

        #expect(try await api.deviceContributions() == .none)

        try await Self.contributeEverything(api: api, outbox: outbox, treeID: tree.id)

        let held = try await api.deviceContributions()
        #expect(held.visits == 1)
        #expect(held.checkIns == 1)
        #expect(held.measurements == 1)
        #expect(held.careEvents == 1)
        #expect(held.privateReminders == 1)
        #expect(held.total == 5)

        try await api.claimDevice(deviceUUID: Self.deviceID, userID: Self.userID)

        // Nothing left on the phone that an account would rescue — which is the honest thing for the
        // headline to say once it has already happened.
        #expect(try await api.deviceContributions() == .none)
    }

    // MARK: - 3. The gap the outbox opens

    /// Queued on Tuesday in a dead zone, signed in on Wednesday, drained on Thursday.
    ///
    /// This is the case a one-shot sweep cannot catch: `claimDevice` updates the rows that exist when
    /// it runs, and this row does not exist yet. Its payload carries the anonymous attribution it was
    /// built with and is never rewritten — the outbox promises to send what it was given — so without
    /// the re-claim after a batch, the contributor is told their work came with them and the tail of
    /// their queue silently stays the device's.
    @Test("a contribution queued before sign-in and applied after it still arrives on the account")
    func queuedBeforeSignInAppliedAfter() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let outbox = OutboxQueue(queue: store.queue, transport: APIOutboxTransport(api: api))
        let tree = try await Self.makeTree(api: api)

        // Tuesday: written, not sent.
        let attribution = Attribution.anonymous(deviceID: Self.deviceID)
        _ = try await outbox.enqueue(
            .visit(Visit(
                treeID: tree.id,
                attribution: attribution,
                note: "queued in a dead zone",
                capturedAt: Date(timeIntervalSince1970: 1_780_000_000)
            ))
        )

        // Wednesday: the account arrives, and there is nothing in the tables yet to adopt.
        try await api.claimDevice(deviceUUID: Self.deviceID, userID: Self.userID)
        #expect(try await Self.owners(in: store, table: "visits").isEmpty)

        // Thursday.
        _ = try await outbox.drain()

        let owners = try await Self.owners(in: store, table: "visits")
        #expect(owners.count == 1)
        #expect(
            owners.first ?? nil == Self.userID.uuidString,
            "a visit queued before sign-in was applied afterwards and stayed the device's"
        )
    }

    @Test("the same is true of a reminder, whose ownership is exclusive")
    func queuedReminderIsAdoptedAfterTheClaim() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let outbox = OutboxQueue(queue: store.queue, transport: APIOutboxTransport(api: api))
        let tree = try await Self.makeTree(api: api)

        _ = try await outbox.enqueue(
            .privateReminder(PrivateReminder(
                owner: ReminderOwner(Attribution.anonymous(deviceID: Self.deviceID)),
                treeID: tree.id,
                category: .uprooted
            ))
        )
        try await api.claimDevice(deviceUUID: Self.deviceID, userID: Self.userID)
        _ = try await outbox.drain()

        let users = try await Self.owners(in: store, table: "private_reminders")
        let devices = try await Self.owners(in: store, table: "private_reminders", ownerColumn: "device_id")
        #expect(users == [Self.userID.uuidString])
        #expect(devices == [nil], "exactly one owner, at every instant (ERRATA E23)")
    }

    // MARK: - 4. Claiming twice, and claiming somebody else's

    @Test("a second claim moves nothing, and a stranger's claim moves nothing of the account's")
    func claimingIsIdempotentAndDoesNotSteal() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let outbox = OutboxQueue(queue: store.queue, transport: APIOutboxTransport(api: api))
        let tree = try await Self.makeTree(api: api)
        try await Self.contributeEverything(api: api, outbox: outbox, treeID: tree.id)

        try await api.claimDevice(deviceUUID: Self.deviceID, userID: Self.userID)
        try await api.claimDevice(deviceUUID: Self.deviceID, userID: Self.userID)
        try await api.claimDevice(deviceUUID: Self.deviceID, userID: Self.strangerID)

        // The rows stay with whoever claimed them first: `user_id IS NULL` is the guard that makes
        // the second and third calls no-ops on already-attributed rows.
        for table in ["visits", "observations", "measurements", "care_events", "private_reminders"] {
            let owners = try await Self.owners(in: store, table: table)
            #expect(owners.count == 1, "\(table) duplicated across repeated claims")
            #expect(owners.first ?? nil == Self.userID.uuidString, "\(table) was stolen by a second account")
        }
    }
}
