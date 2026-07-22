import Foundation
import Testing
@testable import Cypress

/// The path ERRATA E65 was written about, end to end.
///
/// E65: "The day screen 16 lands it changes everything on screen 11 — every measurement the measure
/// sheet writes would arrive with a nil accuracy, `isEligibleForGrowthCharting` would refuse all of
/// them, and the growth charts would be permanently empty on a tree somebody had just measured. The
/// failure would look exactly like the designed empty state."
///
/// So these tests walk a reading the whole way: the sheet, the outbox, the drain, the SQLite row,
/// the profile payload and finally screen 11's derivation, asserting the accuracy survives every one
/// of those hops — and that a reading D6 will not chart is still on the record afterwards.
@Suite("Measurement accuracy, end to end")
struct MeasurementAccuracyTests {

    private static let deviceID = UUID(uuidString: "9F3A0000-0000-4000-8000-0000000000AC")!
    private static let captured = Date(timeIntervalSince1970: 1_800_000_000)

    private struct Bench {
        let store: CypressStore
        let api: LocalAPI
        let outbox: OutboxQueue
        let tree: Tree
    }

    /// A store with one real tree in it, and an outbox pointed at the same API the app points it at.
    private static func bench() async throws -> Bench {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: deviceID)
        let tree = try await api.addTree(
            TreeDraft(
                coordinate: Coordinate(latitude: 37.7601, longitude: -122.5054),
                photoLocalPath: "/tmp/cypress-measure-test.jpg",
                attribution: .anonymous(deviceID: deviceID)
            )
        )
        let outbox = OutboxQueue(queue: store.queue, transport: APIOutboxTransport(api: api))
        return Bench(store: store, api: api, outbox: outbox, tree: tree)
    }

    private static func draft(_ entry: String, kind: MeasurementKind = .dbh, method: MeasurementMethod = .tape)
        -> MeasureDraft {
        var draft = MeasureDraft()
        draft.select(kind: kind)
        draft.method = method
        draft.entry = entry
        return draft
    }

    // MARK: - The fix reaches the record

    @Test("a measurement saved on a good fix carries that accuracy all the way to the chart")
    func accuracyReachesTheChart() async throws {
        let bench = try await Self.bench()

        let receipt = try await MeasureOutboxWriter.save(
            Self.draft("64"),
            treeID: bench.tree.id,
            attribution: .anonymous(deviceID: Self.deviceID),
            outbox: bench.outbox,
            // The number `MapLocationProvider.Availability.accuracyM` now carries (E65).
            gpsAccuracyM: 7,
            now: Self.captured
        )

        // 1 · the mutation the sheet built.
        #expect(receipt.measurement.gpsAccuracyM == 7)
        #expect(receipt.measurement.quantity.method == .tape)
        #expect(receipt.measurement.measurementHeightM == TreeMeasurement.defaultDBHMeasurementHeightM)
        #expect(receipt.item.kind == .measurement)
        #expect(receipt.item.clientUUID == receipt.measurement.clientUUID)

        // 2 · the drain applied it, so the row is in SQLite rather than only in the queue.
        #expect(receipt.syncedImmediately)

        // 3 · what came back out of `GET /trees/{id}`.
        let profile = try await bench.api.treeProfile(id: bench.tree.id)
        let stored = try #require(profile.measurements.first)
        #expect(profile.measurements.count == 1)
        #expect(stored.gpsAccuracyM == 7)
        #expect(stored.quantity.value == 64)
        #expect(stored.quantity.unitEntered == .centimetres)
        #expect(stored.quantity.siValue == 0.64)
        #expect(stored.quantity.method == .tape)
        #expect(stored.isChartable)

        // 4 · screen 11 draws it. This is the assertion E65 exists for: a nil anywhere above and
        // this chart is nil, with nothing on screen able to say why.
        let growth = GrowthHistoryPresentation(profile: profile)
        let chart = try #require(growth.chart(for: .dbh))
        #expect(chart.points.count == 1)
        #expect(chart.points.first?.quantity.method == .tape)
        #expect(growth.isEmpty == false)
        #expect(growth.hasRecordButNoChart == false)
    }

    @Test("the accuracy survives the outbox on its own, before any drain")
    func accuracySurvivesTheQueuedPayload() async throws {
        let bench = try await Self.bench()

        let (measurement, item) = try await MeasureOutboxWriter.enqueue(
            Self.draft("31"),
            treeID: bench.tree.id,
            attribution: .anonymous(deviceID: Self.deviceID),
            outbox: bench.outbox,
            gpsAccuracyM: 9.5,
            now: Self.captured
        )
        #expect(measurement.gpsAccuracyM == 9.5)

        // The queued JSON is what a relaunch reads back, so the accuracy has to round-trip through
        // it. `Quantity` re-derives `siValue` on decode; `gpsAccuracyM` has no such safety net.
        let decoded = try OutboxPayload.decode(kind: .measurement, from: item.payload)
        guard case let .measurement(fromQueue) = decoded else {
            Issue.record("the queued payload did not decode as a measurement")
            return
        }
        #expect(fromQueue.gpsAccuracyM == 9.5)
        #expect(fromQueue.quantity.method == .tape)
        #expect(fromQueue.quantity.siValue == 0.31)
        #expect(fromQueue.isChartable)
    }

    // MARK: - A reading too imprecise to chart is still a reading

    @Test("a reading taken on a poor fix is recorded, and is kept off the chart")
    func poorFixIsRecordedButNotCharted() async throws {
        let bench = try await Self.bench()

        // The screen said so before it was written.
        let sheet = MeasurePresentation(
            draft: Self.draft("64"),
            previous: nil,
            gpsAccuracyM: 40,
            now: Self.captured
        )
        #expect(sheet.chartEligibility == .tooImprecise(accuracyM: 40))
        #expect(sheet.chartNotice != nil)
        #expect(sheet.canSave, "a poor fix must not stop somebody recording what they measured")

        let receipt = try await MeasureOutboxWriter.save(
            Self.draft("64"),
            treeID: bench.tree.id,
            attribution: .anonymous(deviceID: Self.deviceID),
            outbox: bench.outbox,
            gpsAccuracyM: 40,
            now: Self.captured
        )
        #expect(receipt.measurement.gpsAccuracyM == 40)
        #expect(receipt.measurement.isChartable == false)

        let profile = try await bench.api.treeProfile(id: bench.tree.id)
        let stored = try #require(profile.measurements.first)
        // On the record, in full, with the fix that produced it.
        #expect(stored.gpsAccuracyM == 40)
        #expect(stored.deletedAt == nil)
        #expect(stored.isEligibleForGrowthCharting == false)

        // Screen 11: no chart, and the log still shows it. "Hiding somebody's own contribution
        // because the GPS was poor when they made it would be worse than showing it"
        // (`GrowthLogRow`).
        let growth = GrowthHistoryPresentation(profile: profile)
        #expect(growth.charts.isEmpty)
        #expect(growth.logRows.count == 1)
        #expect(growth.isEmpty == false)
        #expect(growth.hasRecordButNoChart)

        // And screen 03's stat card still names the reading with its method badge (D7).
        let stats = TreeProfilePresentation(profile: profile).stats
        #expect(stats.contains { $0.id == "dbh" })
    }

    @Test("a reading with no fix at all is recorded and not charted")
    func noFixIsRecordedButNotCharted() async throws {
        let bench = try await Self.bench()

        let receipt = try await MeasureOutboxWriter.save(
            Self.draft("18", kind: .height, method: .estimate),
            treeID: bench.tree.id,
            attribution: .anonymous(deviceID: Self.deviceID),
            outbox: bench.outbox,
            gpsAccuracyM: nil,
            now: Self.captured
        )
        #expect(receipt.measurement.gpsAccuracyM == nil)
        // "Unknown accuracy is treated as unusable rather than assumed good" (`CoreEntity`, D6).
        #expect(receipt.measurement.isChartable == false)
        // A height carries no measurement height, by construction (BUILD-PLAN §4).
        #expect(receipt.measurement.measurementHeightM == nil)

        let profile = try await bench.api.treeProfile(id: bench.tree.id)
        let stored = try #require(profile.measurements.first)
        #expect(stored.gpsAccuracyM == nil)
        #expect(stored.kind == .height)
        #expect(stored.quantity.method == .estimate)
        #expect(stored.series == .estimated)

        let growth = GrowthHistoryPresentation(profile: profile)
        #expect(growth.charts.isEmpty)
        #expect(growth.logRows.count == 1)
        #expect(growth.hasRecordButNoChart)
    }

    @Test("two readings on the same tree keep their own accuracies and their own series")
    func twoReadingsDoNotBorrowEachOthersFix() async throws {
        let bench = try await Self.bench()

        _ = try await MeasureOutboxWriter.save(
            Self.draft("62"),
            treeID: bench.tree.id,
            attribution: .anonymous(deviceID: Self.deviceID),
            outbox: bench.outbox,
            gpsAccuracyM: 6,
            now: Self.captured
        )
        _ = try await MeasureOutboxWriter.save(
            Self.draft("64", method: .estimate),
            treeID: bench.tree.id,
            attribution: .anonymous(deviceID: Self.deviceID),
            outbox: bench.outbox,
            gpsAccuracyM: 32,
            now: Self.captured.addingTimeInterval(365 * 24 * 60 * 60)
        )

        let profile = try await bench.api.treeProfile(id: bench.tree.id)
        #expect(profile.measurements.count == 2)
        #expect(Set(profile.measurements.compactMap(\.gpsAccuracyM)) == [6, 32])

        // D6 admits one of the two. D7 keeps the estimate out of the measured series regardless, so
        // the split is a pair and never a join.
        let split = profile.measurements.splitBySeries(kind: .dbh)
        #expect(split.measured.count == 1)
        #expect(split.estimated.isEmpty)
        #expect(GrowthHistoryPresentation(profile: profile).logRows.count == 2)
    }

    // MARK: - The sheet cannot write a method-less number

    @Test("an empty draft is refused at the boundary as well as at the button")
    func emptyDraftIsRefusedAtTheBoundary() async throws {
        let bench = try await Self.bench()
        await #expect(throws: APIError.validationFailed) {
            _ = try await MeasureOutboxWriter.enqueue(
                MeasureDraft(),
                treeID: bench.tree.id,
                attribution: .anonymous(deviceID: Self.deviceID),
                outbox: bench.outbox,
                gpsAccuracyM: 7,
                now: Self.captured
            )
        }
        let queued = try await bench.outbox.records()
        #expect(queued.isEmpty)
    }
}
