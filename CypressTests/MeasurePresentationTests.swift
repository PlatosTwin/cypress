import Foundation
import Testing
@testable import Cypress

/// Screen 16, derived.
///
/// The measure sheet is the one gate every number in the record passes through (D7), so the tests
/// that matter are about what the screen will and will not claim: that a keypad cannot produce a
/// method-less quantity, that the previous value is only compared against when there is one, that a
/// verdict is written only when the record supports it, and that a fix D6 will not chart says so
/// before the save rather than after it.
@Suite("Measure sheet")
struct MeasurePresentationTests {

    private static let treeID = UUID(uuidString: "9F3A0000-0000-4000-8000-000000000016")!
    private static let deviceID = UUID(uuidString: "9F3A0000-0000-4000-8000-0000000000DE")!

    private static let now = Calendar.current.date(from: DateComponents(year: 2025, month: 6, day: 18))!

    private static func draft(kind: MeasurementKind = .dbh, entry: String) -> MeasureDraft {
        var draft = MeasureDraft()
        draft.select(kind: kind)
        draft.entry = entry
        return draft
    }

    private static func previous(
        _ value: Double,
        unit: LengthUnit = .centimeters,
        method: MeasurementMethod = .tape,
        at capturedAt: Date = Calendar.current.date(from: DateComponents(year: 2024, month: 6, day: 14))!
    ) -> TreeMeasurement {
        TreeMeasurement.dbh(
            treeID: treeID,
            attribution: .anonymous(deviceID: deviceID),
            capturedAt: capturedAt,
            gpsAccuracyM: 7,
            quantity: Quantity(value: value, unit: unit, method: method)
        )
    }

    private static func presentation(
        _ draft: MeasureDraft,
        previous: TreeMeasurement? = nil,
        gpsAccuracyM: Double? = 8
    ) -> MeasurePresentation {
        MeasurePresentation(
            draft: draft,
            treeDisplayName: "Grandmother Cypress",
            previous: previous,
            gpsAccuracyM: gpsAccuracyM,
            now: now
        )
    }

    // MARK: - D7 at the type level

    @Test("a draft with no entry has no quantity, and therefore nothing to save")
    func emptyDraftHasNoQuantity() {
        let draft = MeasureDraft()
        #expect(draft.value == nil)
        #expect(draft.quantity == nil)
        #expect(draft.canSave == false)
        // A typed zero is not a reading of zero either.
        #expect(Self.draft(entry: "0").quantity == nil)
    }

    @Test("every quantity this screen can build carries a method")
    func everyQuantityCarriesItsMethod() {
        for method in MeasurementMethod.allCases {
            var draft = Self.draft(entry: "64")
            draft.method = method
            let quantity = draft.quantity
            #expect(quantity?.method == method)
            // D7: the two chart series, and there is no third.
            #expect(quantity?.series == method.series)
        }
    }

    @Test("the entered unit and the SI value are both stored, and agree")
    func unitsAreCaptured() {
        var draft = Self.draft(entry: "64")
        draft.unit = .centimeters
        #expect(draft.quantity?.unitEntered == .centimeters)
        #expect(draft.quantity?.siValue == 0.64)

        draft.unit = .inches
        #expect(draft.quantity?.siValue == 64 * 0.0254)
    }

    // MARK: - The keypad

    @Test("the keypad is SCREENS.md 16 §5's twelve keys, in its order")
    func keypadLayout() {
        #expect(MeasureKey.pad.count == 12)
        #expect(MeasureKey.pad.map(\.label) == ["1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", "⌫"])
    }

    @Test("typing, deleting and the one decimal point")
    func typing() {
        var draft = MeasureDraft()
        for key in [MeasureKey.digit("6"), .digit("4")] { draft.apply(key) }
        #expect(draft.entry == "64")

        draft.apply(.decimalPoint)
        draft.apply(.digit("5"))
        #expect(draft.entry == "64.5")

        // A second point is refused rather than producing an unparseable entry.
        draft.apply(.decimalPoint)
        #expect(draft.entry == "64.5")
        #expect(draft.value == 64.5)

        draft.apply(.backspace)
        #expect(draft.entry == "64.")
        for _ in 0..<10 { draft.apply(.backspace) }
        #expect(draft.entry.isEmpty)
        // Deleting past the start is a no-op, not a crash.
        draft.apply(.backspace)
        #expect(draft.entry.isEmpty)
    }

    @Test("a leading decimal point becomes a leading zero, and a leading zero is not kept")
    func leadingZero() {
        var draft = MeasureDraft()
        draft.apply(.decimalPoint)
        #expect(draft.entry == "0.")
        draft.apply(.digit("8"))
        #expect(draft.value == 0.8)

        var other = MeasureDraft()
        other.apply(.digit("0"))
        other.apply(.digit("6"))
        #expect(other.entry == "6")
    }

    @Test("a stuck key cannot fill the readout")
    func entryIsCapped() {
        var draft = MeasureDraft()
        for _ in 0..<40 { draft.apply(.digit("9")) }
        #expect(draft.entry.count == MeasureMetrics.maxEntryLength)
    }

    // MARK: - Units

    /// **F26, as the owner ruled it on 2026-08-31.** The digits survive the flip, and the screen
    /// says what they now mean.
    ///
    /// The old behavior — clearing — was defended against `64 cm` silently becoming `64 in`, a 2.5×
    /// error "with nothing on screen to catch it". Both halves of the replacement are asserted here
    /// in one test *because they are one ruling*: keeping the digits without the annotation is the
    /// error that argument describes, so a test that checked only the digits would go green on
    /// exactly the outcome the clear existed to prevent.
    @Test("switching the unit keeps the digits and annotates what they now mean")
    func switchingUnitsKeepsTheEntryAndSaysTheMeaningMoved() {
        var draft = Self.draft(entry: "64")
        #expect(draft.unit == .centimeters)

        draft.switchUnit()
        #expect(draft.unit == .inches)
        // 5 stays 5: the digits are not converted, which is what keeps `Quantity.value` honest.
        #expect(draft.entry == "64")
        #expect(draft.quantity?.value == 64)
        #expect(draft.quantity?.unitEntered == .inches)
        // And the something-on-screen that makes keeping them safe.
        #expect(draft.unitDigitsWereTypedIn == .centimeters)
        #expect(
            Self.presentation(draft).unitFlipNotice
                == "Typed in centimeters, now read as inches."
        )
    }

    /// Flipping back returns the digits to the unit they were typed in, so there is nothing left to
    /// annotate. Without this the notice would stand over a number it no longer describes — the same
    /// class of stale sentence the annotation exists to prevent, pointing the other way.
    @Test("flipping back to the unit the digits were typed in withdraws the annotation")
    func flippingBackWithdrawsTheAnnotation() {
        var draft = Self.draft(entry: "64")
        draft.switchUnit()
        #expect(draft.unitDigitsWereTypedIn == .centimeters)

        draft.switchUnit()
        #expect(draft.unit == .centimeters)
        #expect(draft.entry == "64")
        #expect(draft.unitDigitsWereTypedIn == nil)
        #expect(Self.presentation(draft).unitFlipNotice == nil)
    }

    /// A flip with an empty pad has no digits to be wrong about, so it annotates nothing.
    @Test("switching the unit on an empty pad annotates nothing")
    func switchingOnAnEmptyPadSaysNothing() {
        var draft = Self.draft(entry: "")
        draft.switchUnit()
        #expect(draft.unit == .inches)
        #expect(draft.unitDigitsWereTypedIn == nil)
        #expect(Self.presentation(draft).unitFlipNotice == nil)
    }

    /// **The gap PR #139's review found: nothing held the two places that empty the pad.**
    ///
    /// `clearEntry` exists so that emptying the entry and forgetting the annotation are one action,
    /// and two callers use it — `MeasureModel.save` and `select(kind:)`. Reverting *both* to a bare
    /// `entry = ""` left the whole suite green, because every test above drives `switchUnit` and the
    /// keypad and none of them saved or changed kind afterwards. The state that escaped is a stale
    /// amber sentence about centimeters standing over an empty pad.
    ///
    /// This is the kind-change path, which is pure. The save path is the test below it.
    @Test("changing the measurement kind takes the unit annotation with the digits")
    func changingKindWithdrawsTheAnnotation() {
        var draft = Self.draft(entry: "64")
        draft.switchUnit()
        #expect(draft.unitDigitsWereTypedIn == .centimeters, "the annotation is not set, so this test cannot see it being cleared")

        draft.select(kind: .height)
        #expect(draft.entry.isEmpty)
        #expect(draft.unitDigitsWereTypedIn == nil)
        #expect(Self.presentation(draft).unitFlipNotice == nil)
    }

    /// The save path, end to end through a real outbox — the reviewer's actual reproduction.
    ///
    /// A save empties the pad, so the annotation has to go with it: the reading that was filed is
    /// gone from the screen, and a sentence describing its units is then describing nothing. The
    /// assertion is on the presentation's notice rather than only on the flag, because the notice is
    /// what a person would have been looking at.
    @Test("saving a reading takes the unit annotation with the digits it filed")
    func savingWithdrawsTheAnnotation() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let tree = try await api.addTree(
            TreeDraft(
                coordinate: Coordinate(latitude: 37.7848, longitude: -122.4215),
                photoLocalPath: "/tmp/cypress-f26-save-clears.jpg",
                attribution: .anonymous(deviceID: Self.deviceID)
            )
        )
        var opening = MeasureDraft()
        opening.entry = "64"
        opening.switchUnit()
        #expect(opening.unitDigitsWereTypedIn == .centimeters, "the annotation is not set, so this test cannot see it being cleared")

        let model = await MeasureModel(
            treeID: tree.id,
            api: api,
            outbox: OutboxQueue(queue: store.queue, apply: APIOutboxTransport(api: api)),
            attribution: .anonymous(deviceID: Self.deviceID),
            gpsAccuracyM: { 8 },
            initialDraft: opening,
            now: { Self.now }
        )
        await model.save()

        let draft = await model.draft
        #expect(draft.entry.isEmpty, "the save did not empty the pad, so this proves nothing about the annotation")
        #expect(draft.unitDigitsWereTypedIn == nil)
        #expect(
            Self.presentation(draft).unitFlipNotice == nil,
            "the reading was filed and the pad is empty, and the screen is still saying those digits were typed in centimeters"
        )
    }

    /// Emptying the pad discards the number the annotation was about, so the annotation goes too —
    /// and a partial edit does not, because the digits left behind were still typed under the old
    /// unit.
    @Test("the annotation outlives a partial backspace and dies with the last digit")
    func backspacingToEmptyWithdrawsTheAnnotation() {
        var draft = Self.draft(entry: "64")
        draft.switchUnit()

        draft.apply(.backspace)
        #expect(draft.entry == "6")
        #expect(draft.unitDigitsWereTypedIn == .centimeters)

        draft.apply(.backspace)
        #expect(draft.entry.isEmpty)
        #expect(draft.unitDigitsWereTypedIn == nil)
    }

    @Test("each kind opens in its own unit, and changing kind resets the entry")
    func kindOwnsItsUnit() {
        var draft = MeasureDraft()
        #expect(draft.kind == .dbh)
        #expect(draft.unit == .centimeters)

        draft.entry = "64"
        draft.select(kind: .height)
        #expect(draft.unit == .meters)
        #expect(draft.entry.isEmpty)

        draft.switchUnit()
        #expect(draft.unit == .feet)
    }

    @Test("the switch link names the unit it will switch to")
    func switchLabel() {
        #expect(Self.presentation(Self.draft(entry: "64")).unitSwitchLabel == "switch to inches")
        var inches = Self.draft(entry: "")
        inches.unit = .inches
        #expect(Self.presentation(inches).unitSwitchLabel == "switch to centimeters")
        #expect(Self.presentation(Self.draft(kind: .height, entry: "")).unitSwitchLabel == "switch to feet")
    }

    // MARK: - §3's sanity pill

    @Test("no previous reading means no pill at all")
    func noPreviousNoPill() {
        // Every tree in the shipped app: the seed carries no measurements, and this screen is the
        // only thing that writes one. A pill reading `Last recorded —` is a surface with nothing
        // behind it (ARCHITECTURE §5.6).
        #expect(Self.presentation(Self.draft(entry: "64")).sanity == nil)
    }

    @Test("the pill states the previous reading in its own unit and carries its method")
    func pillStatesThePreviousReading() throws {
        let sanity = try #require(Self.presentation(Self.draft(entry: ""), previous: Self.previous(62)).sanity)
        #expect(sanity.previousText == "Last recorded 62 cm, Jun 2024")
        // D7: the number and how it was obtained travel together.
        #expect(sanity.previousQuantity.method == .tape)
        // No entry yet, so nothing to compare against.
        #expect(sanity.verdict == nil)
    }

    @Test("the mock's own verdict is written for the mock's own numbers")
    func drawnVerdict() throws {
        let sanity = try #require(
            Self.presentation(Self.draft(entry: "64"), previous: Self.previous(62)).sanity
        )
        #expect(sanity.verdict == "+2 cm in a year sounds right")
    }

    @Test("a verdict needs enough time to have passed for a rate to mean anything")
    func verdictNeedsASpan() throws {
        let lastWeek = Calendar.current.date(byAdding: .day, value: -7, to: Self.now)!
        let sanity = try #require(
            Self.presentation(
                Self.draft(entry: "64"),
                previous: Self.previous(62, at: lastWeek)
            ).sanity
        )
        #expect(sanity.verdict == nil)
    }

    @Test("an implausibly fast year gets no verdict, and no alarm either")
    func fastGrowthGetsNoVerdict() throws {
        let sanity = try #require(
            Self.presentation(Self.draft(entry: "95"), previous: Self.previous(62)).sanity
        )
        #expect(sanity.verdict == nil)
        // 95 cm is a real street tree, so the range warning stays quiet too.
        #expect(Self.presentation(Self.draft(entry: "95"), previous: Self.previous(62)).anomaly == nil)
    }

    // MARK: - The "sure about that?" of §7

    @Test("a shrinking trunk is asked about, and is still saveable")
    func shrinkingTrunk() throws {
        let presentation = Self.presentation(Self.draft(entry: "58"), previous: Self.previous(62))
        let anomaly = try #require(presentation.anomaly)
        #expect(anomaly.hasPrefix("Sure about that?"))
        // DECISIONS §2.5: submission is never blocked for lack of rigor. The sentence asks; the CTA
        // stays live.
        #expect(presentation.canSave)
    }

    @Test("a reading outside the plausible range warns and never rejects")
    func outOfRangeWarns() throws {
        // 900 cm of trunk diameter is a slipped keypad, not a street tree.
        let presentation = Self.presentation(Self.draft(entry: "900"))
        #expect(presentation.anomaly == MeasureCopy.anomalyOutOfRange)
        #expect(presentation.canSave)
        #expect(Quantity(value: 900, unit: .centimeters, method: .tape)
            .isPlausible(within: MeasurementKind.dbh.plausibleSIRange) == false)
    }

    @Test("an ordinary reading raises nothing")
    func noAnomaly() {
        #expect(Self.presentation(Self.draft(entry: "64"), previous: Self.previous(62)).anomaly == nil)
        #expect(Self.presentation(Self.draft(entry: "64")).anomaly == nil)
    }

    // MARK: - D6's notice

    @Test("a good fix says nothing about charting")
    func goodFixIsQuiet() {
        let presentation = Self.presentation(Self.draft(entry: "64"), gpsAccuracyM: 8)
        #expect(presentation.chartEligibility == .eligible)
        #expect(presentation.chartNotice == nil)
    }

    @Test("D6's gate is inclusive at 15 m and the screen changes its mind one tenth past it")
    func gateBoundary() {
        #expect(Self.presentation(Self.draft(entry: "64"), gpsAccuracyM: 15).chartEligibility == .eligible)
        #expect(
            Self.presentation(Self.draft(entry: "64"), gpsAccuracyM: 15.1).chartEligibility
                == .tooImprecise(accuracyM: 15.1)
        )
    }

    @Test("a fix too poor to chart says so, with the number in it")
    func poorFixSaysSo() throws {
        let presentation = Self.presentation(Self.draft(entry: "64"), gpsAccuracyM: 40)
        #expect(presentation.chartEligibility == .tooImprecise(accuracyM: 40))
        let notice = try #require(presentation.chartNotice)
        #expect(notice.contains("40 m"))
        #expect(notice.contains("saved"))
        // The contribution is still worth recording; only the chart is in question (screen 11's
        // `GrowthLogRow`, ERRATA E63).
        #expect(presentation.canSave)
    }

    @Test("no fix at all is its own sentence, and is not treated as a good one")
    func noFixSaysSo() throws {
        let presentation = Self.presentation(Self.draft(entry: "64"), gpsAccuracyM: nil)
        #expect(presentation.chartEligibility == .noFix)
        #expect(try #require(presentation.chartNotice) == MeasureCopy.chartNoticeNoFix)
        #expect(presentation.canSave)
    }

    @Test("the substitute for an unmeasurable fix is excluded by arithmetic, on a measurement too")
    func assumedAccuracyIsNotChartable() {
        // The same pin `LocationAccuracyTests` puts on a visit, applied to the type screen 16 writes.
        let measurement = TreeMeasurement.dbh(
            treeID: Self.treeID,
            attribution: .anonymous(deviceID: Self.deviceID),
            capturedAt: Self.now,
            gpsAccuracyM: VisitShortlist.assumedAccuracyM,
            quantity: Quantity(value: 64, unit: .centimeters, method: .tape)
        )
        #expect(measurement.isChartable == false)
        #expect(
            Self.presentation(Self.draft(entry: "64"), gpsAccuracyM: VisitShortlist.assumedAccuracyM)
                .chartEligibility == .tooImprecise(accuracyM: VisitShortlist.assumedAccuracyM)
        )
    }

    // MARK: - Copy

    /// **§7's footnote is gone and its one fact is not.**
    ///
    /// The copy audit of 2026-08-23 took the footnote slot off this screen with the rest of the
    /// app's (owner ruling). The `1.4 m` survived by the single exception that ruling made (R9) —
    /// the convention is what makes two readings of one trunk comparable — and moved up into §2,
    /// under the control that selects DBH.
    ///
    /// The arm is the footnote's own and is the half worth keeping under test:
    /// `TreeMeasurement.height` carries no `measurementHeightM` at all, by construction, so the
    /// sentence must never appear over a height reading.
    @Test("the DBH convention is stated for a trunk and never over a height")
    func dbhHelp() {
        let dbh = Self.presentation(Self.draft(entry: "64")).dbhHelp
        #expect(dbh == MeasureCopy.dbhHelp)
        #expect(dbh?.contains("1.4 m") == true, "the DBH help lost the convention it exists to state")

        let height = Self.presentation(Self.draft(kind: .height, entry: "18")).dbhHelp
        #expect(height == nil, "a height reading was told where DBH is measured: \(height ?? "")")
    }

    @Test("no copy on this screen claims an authority was told anything, or spaces an em dash")
    func copyRules() {
        let everything = [
            MeasureCopy.screenTitle, MeasureCopy.kindLabel, MeasureCopy.methodLabel,
            MeasureCopy.saveCTA, MeasureCopy.dbhHelp,
            MeasureCopy.anomalyShrunkTrunk, MeasureCopy.anomalyShrunk, MeasureCopy.anomalyOutOfRange,
            MeasureCopy.chartNoticeNoFix, MeasureCopy.chartNoticeTooImprecise(accuracyM: 40),
            MeasureCopy.saveFailed
        ].joined(separator: " ")

        // ARCHITECTURE §5.4.
        #expect(everything.lowercased().contains("the city") == false)
        #expect(everything.lowercased().contains("reported") == false)
        // ARCHITECTURE §5.7.
        #expect(everything.contains(" — ") == false)
        // D1: no count of anything a person did.
        for forbidden in ["streak", "points", "rank", "badge"] {
            #expect(everything.lowercased().contains(forbidden) == false)
        }
    }

    @Test("the readout draws the entry, and a placeholder that is not a reading")
    func readout() {
        #expect(Self.presentation(Self.draft(entry: "")).readout == MeasureCopy.readoutPlaceholder)
        #expect(Self.presentation(Self.draft(entry: "")).hasEntry == false)
        #expect(Self.presentation(Self.draft(entry: "64")).readout == "64")
        #expect(Self.presentation(Self.draft(entry: "64")).hasEntry)
        #expect(Self.presentation(Self.draft(entry: "64")).unitSuffix == " cm")
    }
}
