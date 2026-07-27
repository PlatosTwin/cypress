//
//  GPSAccuracyAtSubmitTests.swift
//  CypressTests
//
//  A contribution form opened before CoreLocation has answered.
//  ERRATA — see docs/errata-pending/gps-accuracy-at-submit.md.
//
//  ── The defect these tests are the assertion form of ──────────────────────────────────────
//  Four views carried D6's per-contribution GPS accuracy into a model built in a `@State`
//  initialiser: the care log, the check-in, the measure sheet and the visit camera. `@State` runs
//  its initialiser exactly once for the lifetime of a view's identity, so the number handed in was
//  whichever one the composition root's provider had published in the first frame — and on a cold
//  launch that is `nil`, because the provider is inert until screen 01 asks it to start and
//  CoreLocation then takes its own time.
//
//  A `nil` accuracy is not a missing decoration. `FieldCaptured.isEligibleForGrowthCharting` treats
//  it as unusable rather than assumed good, deliberately (D6, `CoreEntity`), so a measurement taken
//  a minute after a perfectly good fix arrived was excluded from screen 11 for the lifetime of the
//  record. The person did everything right and their reading did not count.
//
//  ── Why the obvious test would have passed on the broken app ──────────────────────────────
//  Every warm-path assertion passes either way. Hand the form an accuracy at construction and it
//  arrives on the record intact — that is what `MeasurementAccuracyTests` already walks end to end,
//  and it was green against this bug for the whole of its life. What is only true on the fixed app
//  is a statement about a *sequence*: that the value is asked for **after** the form was built. So
//  every test below moves the fix between mount and submit, and the assertion is on which of the
//  two the record ends up carrying.
//
//  ── The other direction, which is the worse defect ────────────────────────────────────────
//  Making the accuracy *live* would fix the cold launch and break something quieter: the
//  contribution would end up stamped with the best fix the phone went on to get rather than the one
//  it was actually taken on, which is a false claim about a reading's provenance in an append-only
//  record. `accuracyIsTheOneAtTheTapAndNotTheBestOneAfterIt` is the guard against a later round
//  "simplifying" this into a live read.
//

#if DEBUG
import Foundation
import Testing
import UIKit
@testable import Cypress

@MainActor
@Suite("A contribution carries the fix it was submitted on, not the one at mount")
struct GPSAccuracyAtSubmitTests {

    // MARK: - Fixtures

    private static let deviceID = UUID(uuidString: "6D5A0000-0000-4000-8000-0000000000A6")!
    private static let captured = Date(timeIntervalSince1970: 1_800_000_000)

    /// The composition root's location provider, reduced to the one thing these four forms ask of
    /// it, and mutable so a fix can be made to arrive *while a form is open*.
    ///
    /// `nil` is the cold launch: permission granted, session started, nothing published yet. It is
    /// not "denied" and it is not "no GPS" — it is the second or two before the first fix, which on
    /// a real phone indoors is considerably longer than that.
    private final class Phone: @unchecked Sendable {
        /// What the provider would answer if asked right now.
        var accuracyM: Double?
        /// How many times a form asked. Only used to show that a form asks at all.
        private(set) var asks = 0

        init(accuracyM: Double? = nil) { self.accuracyM = accuracyM }

        func read() -> Double? {
            asks += 1
            return accuracyM
        }
    }

    /// Somewhere to put a receipt that only reaches a callback.
    ///
    /// Touched only from the models, which are all `@MainActor`, so this is single-threaded in
    /// fact; `@unchecked` records that rather than assumes it, as `FailedReadTests.Attempts` does.
    private final class Received<Receipt>: @unchecked Sendable {
        var receipt: Receipt?
    }

    private struct Bench {
        let api: LocalAPI
        let outbox: OutboxQueue
        let tree: Tree
    }

    /// A store with one real tree in it and an outbox that can actually be written to.
    ///
    /// `VisitPreviewFixtures.outbox()` is deliberately unmigrated, so an enqueue over it fails and
    /// every model here would report a save failure rather than a wrong accuracy.
    private static func bench() async throws -> Bench {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: deviceID)
        let tree = try await api.addTree(
            TreeDraft(
                coordinate: Coordinate(latitude: 37.7848, longitude: -122.4215),
                photoLocalPath: "/tmp/cypress-gps-at-submit.jpg",
                attribution: .anonymous(deviceID: deviceID)
            )
        )
        let outbox = OutboxQueue(queue: store.queue, transport: APIOutboxTransport(api: api))
        return Bench(api: api, outbox: outbox, tree: tree)
    }

    private static func measureDraft(_ entry: String) -> MeasureDraft {
        var draft = MeasureDraft()
        draft.entry = entry
        return draft
    }

    // MARK: - 16 · The measure sheet, which is the one D6 actually bites on

    /// The whole bug, in the screen where it costs something.
    ///
    /// Screen 16 is the only writer of the only record screen 11 charts. A reading that arrives with
    /// a `nil` accuracy is excluded, the chart card is absent, and the absence looks exactly like the
    /// designed empty state of a tree nobody has measured (E63) — which is how E37 went unnoticed
    /// for as long as it did.
    @Test("a measurement begun before the first fix is charted on the fix that arrived")
    func measurementTakenAcrossAColdLaunch() async throws {
        let bench = try await Self.bench()
        let phone = Phone()               // cold launch: no fix yet
        let received = Received<MeasureSaveReceipt>()

        // The sheet opens. `@State` builds the model exactly here and never again.
        let model = MeasureModel(
            treeID: bench.tree.id,
            api: bench.api,
            outbox: bench.outbox,
            attribution: .anonymous(deviceID: Self.deviceID),
            gpsAccuracyM: { phone.read() },
            initialDraft: Self.measureDraft("64"),
            now: { Self.captured },
            onSaved: { received.receipt = $0 }
        )

        // The contributor chooses a method and types a number. Somewhere in there, CoreLocation
        // answers — which on the broken app was an event nothing in this screen could observe.
        phone.accuracyM = 8

        await model.save()

        let measurement = try #require(received.receipt?.measurement, "the reading did not save")
        #expect(
            measurement.gpsAccuracyM == 8,
            """
            The reading carried \(String(describing: measurement.gpsAccuracyM))m rather than the 8m \
            fix the phone had when Save was tapped. A snapshot taken at mount is a snapshot of a \
            cold launch.
            """
        )
        #expect(
            measurement.isChartable,
            "the reading was excluded from screen 11 despite having been taken on an 8m fix"
        )
    }

    /// The sentence under the CTA is a *prediction about the next tap*, so it has to be made from
    /// the fix that tap would use. Made once at mount it was true for about a second and then told
    /// somebody holding a phone with a good fix that they had none.
    @Test("the notice under the CTA withdraws itself when the fix arrives")
    func chartNoticeFollowsTheFix() async throws {
        let bench = try await Self.bench()
        let phone = Phone()

        let model = MeasureModel(
            treeID: bench.tree.id,
            api: bench.api,
            outbox: bench.outbox,
            attribution: .anonymous(deviceID: Self.deviceID),
            gpsAccuracyM: { phone.read() },
            initialDraft: Self.measureDraft("64"),
            now: { Self.captured }
        )

        #expect(model.presentation.chartEligibility == .noFix)
        #expect(model.presentation.chartNotice == MeasureCopy.chartNoticeNoFix)

        phone.accuracyM = 8
        #expect(
            model.presentation.chartNotice == nil,
            """
            The screen still says the reading will not be charted, on a phone that has had an 8m fix \
            since before the number was typed.
            """
        )

        // And it comes *back* if the fix degrades, naming the accuracy rather than saying "no fix":
        // "no fix" and "a poor fix" are different facts about the world (`ChartEligibility`).
        phone.accuracyM = 40
        #expect(model.presentation.chartEligibility == .tooImprecise(accuracyM: 40))
    }

    /// The guard against the wrong fix for the right bug.
    ///
    /// Two readings taken in one standing, either side of the fix improving. Each carries its own
    /// moment. A live accuracy — one that tracked the newest value — would have rewritten the first
    /// reading's provenance from a fix it was never taken on.
    @Test("the accuracy is the one at the tap, not the best one after it")
    func accuracyIsTheOneAtTheTapAndNotTheBestOneAfterIt() async throws {
        let bench = try await Self.bench()
        let phone = Phone(accuracyM: 40)   // a real fix, and a poor one: urban canyon
        let received = Received<MeasureSaveReceipt>()

        let model = MeasureModel(
            treeID: bench.tree.id,
            api: bench.api,
            outbox: bench.outbox,
            attribution: .anonymous(deviceID: Self.deviceID),
            gpsAccuracyM: { phone.read() },
            initialDraft: Self.measureDraft("64"),
            now: { Self.captured },
            onSaved: { received.receipt = $0 }
        )

        await model.save()
        let poor = try #require(received.receipt?.measurement)
        #expect(poor.gpsAccuracyM == 40)
        #expect(poor.isChartable == false, "a 40m fix is outside D6's 15m limit and must not chart")

        // The contributor steps out of the canyon and measures the height too.
        phone.accuracyM = 5
        model.select(kind: .height)
        model.press(.digit("1"))
        model.press(.digit("8"))
        await model.save()

        let good = try #require(received.receipt?.measurement)
        #expect(good.gpsAccuracyM == 5)
        #expect(good.isChartable)
        #expect(
            poor.gpsAccuracyM == 40,
            """
            The first reading's accuracy moved with the phone. A contribution is an append-only \
            record of a moment; a later fix is not evidence about an earlier reading.
            """
        )
    }

    // MARK: - 09 · The care log

    @Test("a care event logged before the first fix carries the fix that arrived")
    func careEventTakenAcrossAColdLaunch() async throws {
        let bench = try await Self.bench()
        let phone = Phone()
        let received = Received<CareLogSaveReceipt>()

        let model = CareLogModel(
            treeID: bench.tree.id,
            api: bench.api,
            outbox: bench.outbox,
            attribution: .anonymous(deviceID: Self.deviceID),
            gpsAccuracyM: { phone.read() },
            now: { Self.captured },
            onSaved: { received.receipt = $0 }
        )

        model.toggle(.watered)
        phone.accuracyM = 9
        await model.save()

        let careEvent = try #require(received.receipt?.careEvent, "the care event did not save")
        #expect(careEvent.gpsAccuracyM == 9)
        #expect(phone.asks > 0, "the sheet never asked the provider anything")
    }

    // MARK: - 05 · The check-in

    @Test("a check-in begun before the first fix carries the fix that arrived")
    func checkInTakenAcrossAColdLaunch() async throws {
        let bench = try await Self.bench()
        let phone = Phone()
        let received = Received<CheckInSaveReceipt>()

        let model = CheckInModel(
            treeID: bench.tree.id,
            api: bench.api,
            outbox: bench.outbox,
            attribution: .anonymous(deviceID: Self.deviceID),
            gpsAccuracyM: { phone.read() },
            now: { Self.captured },
            onSaved: { received.receipt = $0 }
        )

        model.select(status: .alive)
        phone.accuracyM = 11
        await model.save()

        let observation = try #require(received.receipt?.observation, "the check-in did not save")
        #expect(observation.gpsAccuracyM == 11)
    }

    // MARK: - 04 · The visit camera, which is the longest a form stays open

    /// The camera is the widest window of the four: a session runs from the viewfinder opening,
    /// through up to three framings, a note and a chip row, to `Log visit`. Nothing else in the app
    /// holds one `@State` model for as long.
    @Test("a visit photographed before the first fix carries the fix that arrived")
    func visitLoggedAcrossAColdLaunch() async throws {
        let bench = try await Self.bench()
        let phone = Phone()

        let model = VisitCameraModel(
            treeID: bench.tree.id,
            treeDisplayName: "Grandmother Cypress",
            gpsAccuracyM: { phone.read() },
            api: bench.api,
            outbox: bench.outbox,
            attribution: .anonymous(deviceID: Self.deviceID)
        )

        // `useLibraryImage` is BUILD-PLAN §9's camera-denied fallback and reaches `apply(imageData:)`,
        // which is exactly what the shutter reaches. `load()` is never called: it would start a
        // capture session.
        model.useLibraryImage(VisitPreviewFixtures.onePixelJPEG())
        defer {
            for path in model.draft.photoPaths {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: path))
            }
        }

        phone.accuracyM = 7
        let receipt = try #require(await model.logVisit(), "the visit did not save")

        #expect(
            receipt.visit.gpsAccuracyM == 7,
            """
            The visit carried \(String(describing: receipt.visit.gpsAccuracyM))m. The camera opened \
            before the first fix, and the fix that existed when the shutter and the button were \
            pressed is the one the visit was made on.
            """
        )
    }

    // MARK: - 11 · What the reader is told afterwards

    /// D6's exclusion is not silent — screen 16 says it before the save and screen 11 says it after —
    /// but until this round screen 11 said the *wrong one of two things*.
    ///
    /// `MeasurePresentation.ChartEligibility` has three cases and not two precisely because "no fix"
    /// and "a fix too poor" are different facts about the world, and 16's own comment says "the
    /// screen says which". 11 said `too weak to attribute them` over readings whose accuracy was
    /// never recorded at all, which describes a bad fix to somebody whose phone had not answered
    /// yet. On the broken app that was not an edge case: it was the whole cold-launch population.
    @Test("screen 11 does not blame a weak fix for a reading that had none")
    func screenElevenNamesTheRightReason() async throws {
        // A bench each: three readings on one tree would be one record, and the question here is
        // what the screen says about three *different* records.
        func profile(with accuracy: Double?) async throws -> TreeProfile {
            let bench = try await Self.bench()
            _ = try await MeasureOutboxWriter.save(
                Self.measureDraft("64"),
                treeID: bench.tree.id,
                attribution: .anonymous(deviceID: Self.deviceID),
                outbox: bench.outbox,
                gpsAccuracyM: accuracy,
                now: Self.captured
            )
            return try await bench.api.treeProfile(id: bench.tree.id)
        }

        let noFix = GrowthHistoryPresentation(profile: try await profile(with: nil))
        #expect(noFix.hasRecordButNoChart, "a nil-accuracy reading is on the log and off the chart")
        #expect(
            noFix.noChartReason == GrowthHistoryCopy.noFixRecordedState,
            """
            Screen 11 told the reader their GPS fix was too weak, about a reading saved before the \
            phone had produced a fix at all.
            """
        )

        // A second reading, this one measured and genuinely too poor. Now "too weak" is true of the
        // record, so it is what the screen says.
        let poorFix = GrowthHistoryPresentation(profile: try await profile(with: 40))
        #expect(poorFix.noChartReason == GrowthHistoryCopy.noChartableState)

        // And a chartable one puts the cards back, so the sentence goes away entirely.
        let charted = GrowthHistoryPresentation(profile: try await profile(with: 8))
        #expect(charted.noChartReason == nil)
        #expect(charted.charts.isEmpty == false)
    }
}
#endif
