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
        unit: LengthUnit = .centimetres,
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
        draft.unit = .centimetres
        #expect(draft.quantity?.unitEntered == .centimetres)
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

    @Test("switching the unit clears the entry rather than relabelling it")
    func switchingUnitsClearsTheEntry() {
        var draft = Self.draft(entry: "64")
        #expect(draft.unit == .centimetres)

        draft.switchUnit()
        // The dangerous outcome is `64 in` written where 64 cm was measured — a 2.5× error on an
        // append-only record with nothing on screen to catch it.
        #expect(draft.unit == .inches)
        #expect(draft.entry.isEmpty)
        #expect(draft.quantity == nil)

        draft.switchUnit()
        #expect(draft.unit == .centimetres)
    }

    @Test("each kind opens in its own unit, and changing kind resets the entry")
    func kindOwnsItsUnit() {
        var draft = MeasureDraft()
        #expect(draft.kind == .dbh)
        #expect(draft.unit == .centimetres)

        draft.entry = "64"
        draft.select(kind: .height)
        #expect(draft.unit == .metres)
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
        #expect(Quantity(value: 900, unit: .centimetres, method: .tape)
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
            quantity: Quantity(value: 64, unit: .centimetres, method: .tape)
        )
        #expect(measurement.isChartable == false)
        #expect(
            Self.presentation(Self.draft(entry: "64"), gpsAccuracyM: VisitShortlist.assumedAccuracyM)
                .chartEligibility == .tooImprecise(accuracyM: VisitShortlist.assumedAccuracyM)
        )
    }

    // MARK: - Copy

    @Test("the footnote drops its DBH sentence over a height")
    func footnote() {
        let dbh = Self.presentation(Self.draft(entry: "64")).footnote
        #expect(dbh.hasPrefix("Taken at 1.4 m, tape in one hand."))
        #expect(dbh.contains("“sure about that?”"))

        // `TreeMeasurement.height` carries no `measurementHeightM` at all, by construction.
        let height = Self.presentation(Self.draft(kind: .height, entry: "18")).footnote
        #expect(height == MeasureCopy.footnoteAnomaly)
        #expect(height.contains("1.4 m") == false)
    }

    @Test("no copy on this screen claims an authority was told anything, or spaces an em dash")
    func copyRules() {
        let everything = [
            MeasureCopy.screenTitle, MeasureCopy.kindLabel, MeasureCopy.methodLabel,
            MeasureCopy.saveCTA, MeasureCopy.footnoteDBH, MeasureCopy.footnoteAnomaly,
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
