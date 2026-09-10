import Foundation
import Testing
@testable import Cypress

/// **Taking a reading back** (tester report F27, `AppSchema` v21).
///
/// F27 read "measurements can be neither edited nor deleted". *Edited* needed nothing built and
/// `MeasurementWithdrawalAccess.swift` says why at length: there is no edit verb for any
/// contributed record in this app, by design, and changing a reading is adding a reading. *Deleted*
/// was real — `measurements.deleted_at` has existed since v1, every reader honors it, and nothing
/// anywhere set it.
///
/// This suite is the six sentences the fix has to make true:
///
/// 1. a withdrawal tombstones the reading **and** queues the act, in one transaction;
/// 2. every surface that reads a measurement stops counting it — the log, the charts, the journal,
///    the grove, the profile's stat cards;
/// 3. a reading that is not this person's is refused, and a refused withdrawal queues nothing;
/// 4. the control is drawn on exactly the readings the API would accept;
/// 5. the payload survives the round trip the queue puts it through, and a drain sends it without
///    ever re-applying it;
/// 6. the confirmation's sentence about the chart and the API's answer about it agree.
@Suite("Measurement withdrawal")
struct MeasurementWithdrawalTests {

    private static let deviceID = UUID(uuidString: "F2700000-0000-4000-8000-00000000D001")!
    private static let otherDeviceID = UUID(uuidString: "F2700000-0000-4000-8000-00000000D002")!
    private static let userID = UUID(uuidString: "F2700000-0000-4000-8000-00000000U001")!

    private static var attribution: Attribution { .anonymous(deviceID: deviceID) }

    private static let moment = Date(timeIntervalSince1970: 1_780_000_000)

    /// West of Ocean Beach, `CommunityOutboxKindTests.offshore`'s coordinate and its reason: the
    /// seed is the city's *street*-tree inventory, so nothing is inside the 10 m dedupe radius and
    /// the only trees a test contends with are its own.
    private static let offshore = Coordinate(latitude: 37.7600, longitude: -122.5400)

    private static func seededStore() async throws -> CypressStore {
        let seedURL = try #require(SeedContractTests.seedURL, "no seed database; set CYPRESS_SEED_PATH")
        return try await CypressStore.inMemory(seedURL: seedURL)
    }

    /// A community tree, written through `addTree` because `LocalAPI.requireTree` refuses an
    /// invented UUID and because a tree inserted behind the API is not the tree the app makes.
    private static func makeTree(api: LocalAPI, path: String) async throws -> Tree {
        FileManager.default.createFile(atPath: path, contents: Data([0xFF, 0xD8, 0xFF, 0xD9]))
        return try await api.addTree(
            TreeDraft(coordinate: offshore, photoLocalPath: path, attribution: attribution)
        )
    }

    /// One reading, saved the way screen 16 saves one: through the outbox and the apply sink.
    ///
    /// Not `ContributionStore.insert` directly. A withdrawal is about a reading somebody
    /// contributed, and a fixture that wrote the row behind the API would not carry the attribution
    /// the ownership gate reads — which is the thing most of this suite is about.
    @discardableResult
    private static func record(
        _ measurement: TreeMeasurement,
        with api: LocalAPI
    ) async throws -> TreeMeasurement {
        let results = try await api.sync([try OutboxPayload.measurement(measurement).makeItem()])
        #expect(results.first?.isSuccess == true, "the fixture could not save a reading")
        return measurement
    }

    private static func dbh(
        treeID: UUID,
        _ centimeters: Double,
        at offsetDays: Double,
        attribution: Attribution
    ) -> TreeMeasurement {
        TreeMeasurement.dbh(
            treeID: treeID,
            attribution: attribution,
            capturedAt: moment.addingTimeInterval(offsetDays * 86_400),
            gpsAccuracyM: 6,
            quantity: Quantity(value: centimeters, unit: .centimeters, method: .tape)
        )
    }

    private static func height(
        treeID: UUID,
        _ meters: Double,
        at offsetDays: Double,
        attribution: Attribution
    ) -> TreeMeasurement {
        TreeMeasurement.height(
            treeID: treeID,
            attribution: attribution,
            capturedAt: moment.addingTimeInterval(offsetDays * 86_400),
            gpsAccuracyM: 6,
            quantity: Quantity(value: meters, unit: .meters, method: .tape)
        )
    }

    private static func withdrawals(_ store: CypressStore) async throws -> [MeasurementWithdrawal] {
        try await store.queue.read { connection in
            try OutboxStore().allItems(connection: connection)
                .filter { $0.item.kind == .measurementWithdrawal }
                .compactMap { record -> MeasurementWithdrawal? in
                    guard case let .measurementWithdrawal(payload) =
                        try OutboxPayload.decode(kind: record.item.kind, from: record.item.payload)
                    else { return nil }
                    return payload
                }
        }
    }

    // MARK: - 1. The act

    /// **The reading is tombstoned and the withdrawal is queued, and both or neither.**
    ///
    /// The row is not deleted: `deleted_at` is the house verb, and the tombstone is what every
    /// reader already narrows on. Nothing is stripped from it either, which is where this parts
    /// company with `deletePhoto` — see `ContributionStore.withdrawMeasurement`.
    @Test("withdrawing a reading tombstones the row and queues the act")
    func withdrawingTombstonesAndQueues() async throws {
        let store = try await Self.seededStore()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let tree = try await Self.makeTree(api: api, path: NSTemporaryDirectory() + "cypress-f27-a.jpg")
        let reading = try await Self.record(
            Self.dbh(treeID: tree.id, 31, at: 0, attribution: Self.attribution), with: api
        )

        let outcome = try await api.withdrawMeasurement(id: reading.id)
        #expect(outcome.measurementID == reading.id)
        #expect(outcome.treeID == tree.id)
        #expect(outcome.kind == .dbh)

        // The row survives, tombstoned, with its number intact.
        let stored = try await store.queue.read { connection -> (String?, Double)? in
            let statement = try connection.prepare("""
                SELECT deleted_at, value FROM measurements WHERE id = :id COLLATE NOCASE
                """)
            defer { statement.finalize() }
            _ = try statement.bind([":id": reading.id.uuidString])
            return try statement.fetchOne { (try $0.stringIfPresent("deleted_at"), try $0.double("value")) }
        }
        let row = try #require(stored, "the withdrawal deleted the row instead of tombstoning it")
        #expect(row.0 != nil, "the reading was not tombstoned")
        #expect(row.1 == 31, "the withdrawal stripped the reading's value")

        // And the act is on the queue, naming what it withdrew.
        let queued = try await Self.withdrawals(store)
        #expect(queued.count == 1, "the withdrawal queued \(queued.count) rows, not 1")
        #expect(queued.first?.measurementID == reading.id)
        #expect(queued.first?.treeID == tree.id)
        #expect(queued.first?.kind == .dbh)
        #expect(queued.first?.attribution.deviceID == Self.deviceID)
    }

    /// **Born locally applied**, like every other kind `LocalAPI` writes from inside the transaction
    /// that performed the mutation. A drain owes it the send and nothing else, and the apply sink
    /// refuses it — re-applying one would tombstone a reading that is already withdrawn and queue a
    /// second withdrawal for it.
    @Test("the queued withdrawal is applied before it is queued, and the apply sink refuses it")
    func theRowIsAppliedBeforeItIsQueued() async throws {
        let store = try await Self.seededStore()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let tree = try await Self.makeTree(api: api, path: NSTemporaryDirectory() + "cypress-f27-b.jpg")
        let reading = try await Self.record(
            Self.dbh(treeID: tree.id, 31, at: 0, attribution: Self.attribution), with: api
        )
        _ = try await api.withdrawMeasurement(id: reading.id)

        let record = try #require(
            try await store.queue.read { connection in
                try OutboxStore().allItems(connection: connection)
                    .first { $0.item.kind == .measurementWithdrawal }
            }
        )
        #expect(record.locallyApplied, "the withdrawal was queued as not-yet-applied")
        #expect(!record.remoteSent, "the withdrawal was queued as already sent")

        let payload = try OutboxPayload.decode(kind: .measurementWithdrawal, from: record.item.payload)
        #expect(payload.isAppliedBeforeItIsQueued)

        // Offered to the apply sink it refuses, non-retryably, rather than performing the act twice.
        await #expect(throws: APIError.validationFailed) { _ = try await api.sync([record.item]) }
    }

    // MARK: - 2. Every reader

    /// **A withdrawn reading is gone from every surface that reads a measurement.**
    ///
    /// The one test in this suite that is about the *rest* of the app rather than about the
    /// withdrawal. Each of these narrows on `deleted_at IS NULL` in its own statement or its own
    /// filter, and the list is what "behaves correctly everywhere" means:
    ///
    /// · the profile payload's series, which is what screen 03's stat cards and screen 11 both read;
    /// · screen 11's log rows and its chart cards (`isChartable` is `deletedAt == nil` and more);
    /// · the journal page (`ContributionStore.journal`);
    /// · the grove's per-tree record counts (`groveRecords`);
    /// · the device's own contribution count, which is the promise screen 15 makes.
    ///
    /// Two readings are recorded and one is withdrawn, so every assertion below is `2 → 1` rather
    /// than `1 → 0`: a surface that had simply stopped reading measurements would pass the second
    /// and fails the first.
    @Test("every surface that reads a measurement stops counting a withdrawn one")
    func everyReaderStopsCountingIt() async throws {
        let store = try await Self.seededStore()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let tree = try await Self.makeTree(api: api, path: NSTemporaryDirectory() + "cypress-f27-c.jpg")
        let kept = try await Self.record(
            Self.dbh(treeID: tree.id, 31, at: 0, attribution: Self.attribution), with: api
        )
        let doomed = try await Self.record(
            Self.dbh(treeID: tree.id, 34, at: 365, attribution: Self.attribution), with: api
        )

        func read() async throws -> (
            series: [UUID], logRows: [UUID], chartPoints: [UUID],
            journal: Int, grove: Int, deviceCount: Int
        ) {
            let profile = try await api.treeProfile(id: tree.id)
            let presentation = GrowthHistoryPresentation(profile: profile)
            let journal = try await api.journal(cursor: nil, limit: 50)
            let records = try await store.queue.read { connection in
                try ContributionStore().groveRecords(
                    userID: nil, deviceID: Self.deviceID, connection: connection
                )
            }
            let contributions = try await store.queue.read { connection in
                try ContributionStore().deviceContributions(
                    deviceUUID: Self.deviceID, connection: connection
                )
            }
            return (
                series: profile.measurements.map(\.id),
                logRows: presentation.logRows.map(\.id),
                chartPoints: presentation.charts.flatMap(\.points).map(\.id),
                journal: journal.items.filter { $0.kind == .measurement }.count,
                grove: records[tree.id]?.measurements ?? 0,
                deviceCount: contributions.measurements
            )
        }

        let before = try await read()
        #expect(before.series.count == 2, "the fixture recorded \(before.series.count) readings, not 2")
        #expect(before.logRows.count == 2)
        #expect(before.chartPoints.count == 2)
        #expect(before.journal == 2)
        #expect(before.grove == 2)
        #expect(before.deviceCount == 2)

        _ = try await api.withdrawMeasurement(id: doomed.id)

        let after = try await read()
        #expect(after.series == [kept.id], "the profile payload still carries the withdrawn reading")
        #expect(after.logRows == [kept.id], "screen 11's log still draws the withdrawn reading")
        #expect(after.chartPoints == [kept.id], "the growth chart still plots the withdrawn reading")
        #expect(after.journal == 1, "the journal still lists the withdrawn reading")
        #expect(after.grove == 1, "the grove still counts the withdrawn reading")
        #expect(after.deviceCount == 1, "the account ask still offers to keep the withdrawn reading")
    }

    /// **Withdrawing the last reading of a kind takes its chart card with it**, and the API says so
    /// before anybody has to notice.
    ///
    /// `WithdrawnMeasurement.leftTheKindWithNoReading` and
    /// `GrowthHistoryCopy.withdrawLastOfItsKind` are the same sentence read after and before the
    /// tap, so they are asserted together: the confirmation promises the card goes, and the record
    /// afterwards is a tree with no DBH card and its height card untouched.
    @Test("the last reading of a kind reports itself, and its chart card goes")
    func theLastOfItsKindIsReported() async throws {
        let store = try await Self.seededStore()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let tree = try await Self.makeTree(api: api, path: NSTemporaryDirectory() + "cypress-f27-d.jpg")
        let firstDBH = try await Self.record(
            Self.dbh(treeID: tree.id, 31, at: 0, attribution: Self.attribution), with: api
        )
        let lastDBH = try await Self.record(
            Self.dbh(treeID: tree.id, 34, at: 365, attribution: Self.attribution), with: api
        )
        try await Self.record(
            Self.height(treeID: tree.id, 8, at: 0, attribution: Self.attribution), with: api
        )

        // Two DBH readings on file: neither is the last of its kind, and the confirmation says only
        // its first sentence.
        let both = GrowthHistoryPresentation(profile: try await api.treeProfile(id: tree.id))
        let firstRow = try #require(both.logRows.first { $0.id == firstDBH.id })
        #expect(!firstRow.isLastOfItsKind)
        #expect(
            GrowthHistoryPresentation.withdrawMessage(firstRow) == GrowthHistoryCopy.withdrawMessage,
            "the confirmation warned about a chart that is not going anywhere"
        )

        let firstOutcome = try await api.withdrawMeasurement(id: firstDBH.id)
        #expect(!firstOutcome.leftTheKindWithNoReading, "one of two DBH readings emptied the series")

        // Now the remaining DBH reading is the last of its kind, on both sides of the tap.
        let one = GrowthHistoryPresentation(profile: try await api.treeProfile(id: tree.id))
        let lastRow = try #require(one.logRows.first { $0.id == lastDBH.id })
        #expect(lastRow.isLastOfItsKind)
        #expect(
            GrowthHistoryPresentation.withdrawMessage(lastRow)
                .contains(GrowthHistoryCopy.withdrawLastOfItsKind(.dbh)),
            "the confirmation did not say the chart goes with it"
        )

        let lastOutcome = try await api.withdrawMeasurement(id: lastDBH.id)
        #expect(lastOutcome.leftTheKindWithNoReading, "the last DBH reading did not empty the series")

        let after = GrowthHistoryPresentation(profile: try await api.treeProfile(id: tree.id))
        #expect(after.charts.map(\.kind) == [.height], "the DBH card outlived its last reading")
    }

    // MARK: - 3. Whose reading it is

    /// **Somebody else's reading is refused, and the refusal queues nothing.**
    ///
    /// The gate is checked twice — in Swift before the transaction, and again in the tombstone
    /// `UPDATE`'s own predicate — because a check made in Swift and an `UPDATE` that would have
    /// matched anyway are one refactor apart from a withdrawal that reaches somebody else's row
    /// (`ContributionStore.withdrawalPredicate`).
    @Test("a reading contributed by another installation cannot be withdrawn")
    func anotherInstallationsReadingIsRefused() async throws {
        let store = try await Self.seededStore()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let tree = try await Self.makeTree(api: api, path: NSTemporaryDirectory() + "cypress-f27-e.jpg")
        let theirs = try await Self.record(
            Self.dbh(
                treeID: tree.id, 31, at: 0,
                attribution: .anonymous(deviceID: Self.otherDeviceID)
            ),
            with: api
        )

        await #expect(throws: APIError.forbidden) { _ = try await api.withdrawMeasurement(id: theirs.id) }
        #expect(try await Self.withdrawals(store).isEmpty, "a refused withdrawal queued a row")
        #expect(
            try await api.treeProfile(id: tree.id).measurements.map(\.id) == [theirs.id],
            "the refusal tombstoned the reading anyway"
        )
    }

    /// **A reading nobody owns is refused too**, which is R3 and the leaving door's promise.
    ///
    /// On this table the anonymized case is a `anonymized_contributions` tombstone rather than a
    /// null owner, because `measurements.device_id` is NOT NULL: the door nulls `user_id` and
    /// deliberately leaves the device column, so an unlinked reading is indistinguishable by columns
    /// from D9's ordinary unsigned-in case. Without the tombstone clause, a reading somebody
    /// deliberately unlinked from themselves would be withdrawable by whoever holds the phone next.
    @Test("a reading an account deletion unlinked is nobody's to withdraw")
    func anAnonymizedReadingIsRefused() async throws {
        let store = try await Self.seededStore()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let tree = try await Self.makeTree(api: api, path: NSTemporaryDirectory() + "cypress-f27-f.jpg")
        let reading = try await Self.record(
            Self.dbh(treeID: tree.id, 31, at: 0, attribution: Self.attribution), with: api
        )

        // The leaving door's own shape: a tombstone on the client uuid, and `user_id` nulled. The
        // device column stays, which is exactly what makes this row look like this phone's.
        try await store.queue.write { connection in
            try connection.execute("""
                INSERT INTO anonymized_contributions (client_uuid, anonymized_at)
                VALUES ('\(reading.clientUUID.uuidString)',
                        '\(SQLiteTimestamp.string(from: Self.moment))');
                """)
        }

        await #expect(throws: APIError.forbidden) { _ = try await api.withdrawMeasurement(id: reading.id) }
        #expect(try await Self.withdrawals(store).isEmpty, "a refused withdrawal queued a row")

        // And the control is not drawn on it either, which is the same rule read from the other
        // side: a control offered on a row the API refuses is a control that fails under a thumb.
        let profile = try await api.treeProfile(id: tree.id)
        #expect(!profile.withdrawableMeasurementIDs.contains(reading.id))
        #expect(
            profile.measurements.map(\.id) == [reading.id],
            "the leaving door's promise was broken: the reading is no longer in the record"
        )
    }

    /// **Withdrawing twice is `notFound`, and queues one row rather than two.**
    ///
    /// "There is no live reading with that id" is exactly true of a reading that is already
    /// withdrawn, which is why this is not a case of its own.
    @Test("withdrawing a reading twice is not found, and queues one act")
    func withdrawingTwiceIsRefused() async throws {
        let store = try await Self.seededStore()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let tree = try await Self.makeTree(api: api, path: NSTemporaryDirectory() + "cypress-f27-g.jpg")
        let reading = try await Self.record(
            Self.dbh(treeID: tree.id, 31, at: 0, attribution: Self.attribution), with: api
        )

        _ = try await api.withdrawMeasurement(id: reading.id)
        await #expect(throws: APIError.notFound) { _ = try await api.withdrawMeasurement(id: reading.id) }
        #expect(try await Self.withdrawals(store).count == 1, "the second call queued a second act")
    }

    /// **An account's own reading is still theirs after signing in**, which is the case
    /// `claimDevice` produces and the one that needed no `taken_on_device` arm.
    ///
    /// `AppSchema` v16 gave photo removal a provenance arm because `claimDevice` **clears**
    /// `photos.device_id`; on the four contribution tables it sets `user_id` and leaves the device
    /// column, so a reading adopted by an account is reachable through either arm afterwards. This
    /// test is what makes that difference a measured fact rather than a reading of the source.
    @Test("signing in does not take your readings out of your hands")
    func adoptionKeepsTheReadingWithdrawable() async throws {
        let store = try await Self.seededStore()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let tree = try await Self.makeTree(api: api, path: NSTemporaryDirectory() + "cypress-f27-h.jpg")
        let reading = try await Self.record(
            Self.dbh(treeID: tree.id, 31, at: 0, attribution: Self.attribution), with: api
        )

        try await api.claimDevice(deviceUUID: Self.deviceID, userID: Self.userID)
        try await api.signOut()

        #expect(
            try await api.treeProfile(id: tree.id).withdrawableMeasurementIDs.contains(reading.id),
            "the reading stopped being this phone's when an account adopted it"
        )
        _ = try await api.withdrawMeasurement(id: reading.id)
        #expect(try await api.treeProfile(id: tree.id).measurements.isEmpty)
    }

    // MARK: - 4. The control

    /// **The control is drawn on exactly the readings the API would accept.**
    ///
    /// Two rows on one tree, one this installation's and one another's, so the assertion is about a
    /// *set* rather than about a flag that happens to be true. A control drawn on a row the API
    /// refuses is a control that fails under a thumb; a control missing from a row the API accepts
    /// is F27 unfixed for that row.
    @Test("screen 11 draws the withdraw control on exactly the rows the API accepts")
    func theControlMatchesThePermission() async throws {
        let store = try await Self.seededStore()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let tree = try await Self.makeTree(api: api, path: NSTemporaryDirectory() + "cypress-f27-i.jpg")
        let mine = try await Self.record(
            Self.dbh(treeID: tree.id, 31, at: 0, attribution: Self.attribution), with: api
        )
        let theirs = try await Self.record(
            Self.dbh(
                treeID: tree.id, 34, at: 365,
                attribution: .anonymous(deviceID: Self.otherDeviceID)
            ),
            with: api
        )

        let presentation = GrowthHistoryPresentation(profile: try await api.treeProfile(id: tree.id))
        let withdrawable = Set(presentation.logRows.filter(\.isWithdrawable).map(\.id))
        #expect(
            withdrawable == [mine.id],
            "the control was drawn on \(withdrawable.count) of 2 rows; only this installation's is"
        )
        #expect(presentation.logRows.count == 2, "the other installation's reading left the log")

        // The other half: the API agrees about the row it did not draw a control on.
        await #expect(throws: APIError.forbidden) { _ = try await api.withdrawMeasurement(id: theirs.id) }
    }

    // MARK: - 5. The payload and the queue

    /// **The payload survives the round trip the queue puts it through**, keys, kind and attribution
    /// intact. `CommunityOutboxKindTests.everyPayloadRoundTrips`' assertion for the eleventh kind.
    @Test("the withdrawal payload survives the round trip the queue puts it through")
    func thePayloadRoundTrips() throws {
        let payload = OutboxPayload.measurementWithdrawal(
            MeasurementWithdrawal(
                clientUUID: UUID(),
                measurementID: UUID(),
                treeID: UUID(),
                kind: .height,
                attribution: Self.attribution,
                occurredAt: Self.moment
            )
        )
        let item = try payload.makeItem()
        #expect(item.kind == .measurementWithdrawal)
        #expect(item.clientUUID == payload.clientUUID)

        let decoded = try OutboxPayload.decode(kind: item.kind, from: item.payload)
        #expect(decoded == payload, "the payload did not survive its own encoder")
        #expect(decoded.treeID == payload.treeID)
        #expect(decoded.occurredAt == Self.moment)
        #expect(decoded.ownerDeviceID == Self.deviceID)
        #expect(decoded.ownerUserID == nil)
    }

    /// **The queue row says what it is, in the words screen 17 draws.**
    ///
    /// `Reading withdrawn` is `Photo removed`'s twin, and the sub-line is the one fact the payload
    /// actually carries — the same clause the `.measurement` row prints, rather than a species name
    /// or a value nobody sent.
    @Test("screen 17 labels the withdrawal and names the series it was in")
    func screen17ReadsTheRow() throws {
        #expect(OutboxCopy.kindLabel(OutboxItem.Kind.measurementWithdrawal) == "Reading withdrawn")

        let payload = OutboxPayload.measurementWithdrawal(
            MeasurementWithdrawal(
                clientUUID: UUID(), measurementID: UUID(), treeID: UUID(), kind: .dbh,
                attribution: Self.attribution, occurredAt: Self.moment
            )
        )
        let snapshot = OutboxItemSnapshot(
            id: UUID(),
            kind: payload.kind,
            state: .pending,
            failCount: 0,
            reason: nil,
            errorCode: nil,
            treeID: payload.treeID,
            treeName: "Grandmother Cypress",
            payload: payload,
            photoCount: 0,
            createdAt: Self.moment,
            updatedAt: Self.moment,
            nextAttemptAt: nil
        )
        #expect(OutboxCopy.detail(for: snapshot) == "DBH")
    }

    // MARK: - 6. What the migration did and did not make reachable

    /// **A withdrawal could not have been queued before v21, so there is no pre-migration row to
    /// drain.**
    ///
    /// Asserted rather than assumed, because "a withdrawal queued before the migration still drains
    /// after it" is a real question about this round and the honest answer is that the state is
    /// unreachable: the v20 `CHECK` refuses the kind outright, and no build before this one could
    /// build the payload either. This is the measurement that says so.
    @Test("a v20 database cannot hold a queued withdrawal at all")
    func theStateThisMigrationMakesReachableDidNotExist() async throws {
        let store = try await CypressStore.inMemory(
            migrations: AppSchema.migrations.filter { $0.version <= 20 }
        )
        let stamp = SQLiteTimestamp.string(from: Self.moment)

        var refused = false
        do {
            try await store.queue.write { connection in
                try connection.execute("""
                    INSERT INTO outbox
                        (id, kind, client_uuid, payload, state, fail_count, local_applied,
                         remote_sent, window_started_at, created_at, updated_at)
                    VALUES ('\(UUID().uuidString)','measurement_withdrawal','\(UUID().uuidString)',
                            '{}','pending',0,1,0,'\(stamp)','\(stamp)','\(stamp)');
                    """)
            }
        } catch {
            refused = true
        }
        #expect(
            refused,
            """
            a v20 outbox accepted a `measurement_withdrawal` row, so the CHECK this migration \
            widens was not closed and v21 is not the step it claims to be
            """
        )
    }
}
