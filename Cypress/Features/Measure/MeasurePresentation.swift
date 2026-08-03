//
//  MeasurePresentation.swift
//  Cypress — Features/Measure
//
//  Screen 16 · Measure. SCREENS.md lines 1212–1237.
//
//  "The single gate every number in the record passes through." D7 is this screen, so almost
//  everything below is a rule from a document rather than a layout choice.
//
//  ── 1. A number cannot leave here without its method ──────────────────────────────────────
//  Not enforced by a validation pass; enforced by construction. `Quantity` has exactly one
//  initializer and it requires a `MeasurementMethod`, so `MeasureDraft` cannot hold a half-built
//  quantity at all: it holds an entry string and a method, and `quantity` is nil until both are
//  answerable. `TreeMeasurement`'s two factories are the only way to a measurement, which is what
//  keeps `measurementHeightM` attached to DBH and absent from height (D7, DECISIONS §3.5).
//
//  ── 2. The GPS fix is part of the reading ─────────────────────────────────────────────────
//  D6 stores per-contribution GPS accuracy and excludes readings worse than 15 m from growth
//  charting; `FieldCaptured.isEligibleForGrowthCharting` also excludes a fix that was never
//  recorded, because "unknown accuracy is treated as unusable rather than assumed good". The fix
//  arrives from the composition root (`MapLocationProvider.Availability.accuracyM`, ERRATA E65) and
//  goes onto the measurement unchanged. **The screen says so before the save**, because a reading
//  that will never appear on screen 11 and does not say so is indistinguishable from a charting bug
//  — which is exactly the failure E65 was recorded to prevent. The contribution is still recorded:
//  screen 11's log already settled that hiding somebody's contribution for a weak fix is worse than
//  showing it (`GrowthLogRow`).
//
//  ── 3. Nothing here blocks a save ────────────────────────────────────────────────────────
//  DECISIONS §2.5 and §3.5: range validation warns on entry and "submission is otherwise never
//  blocked for lack of rigor". So an implausible value and a shrinking trunk each produce a visible
//  sentence and a live CTA, never a gate.
//
//  No SwiftUI in this file, so all of the above is testable without a renderer.
//

import Foundation

// MARK: - The draft

/// What the contributor has entered. Everything is local: this screen is usable the instant it
/// appears and nothing on it waits for a read (the same rule `CareLogDraft` follows).
struct MeasureDraft: Equatable {

    /// 16 §2's two-segment control. `Trunk · DBH` is the drawn selection.
    var kind: MeasurementKind = .dbh
    /// 16 §4's three-segment control, `Method · required`. `Tape` is the drawn selection, and there
    /// is no "unset" case: a `Quantity` cannot exist without a method, so neither can this control.
    var method: MeasurementMethod = .tape
    /// The unit the keypad is entering in. Defaults per kind; changed by 16 §3's `switch to …` link.
    var unit: LengthUnit = MeasureMetrics.defaultUnit(for: .dbh)
    /// The digits as typed, in `unit`. Never converted (see `switchUnit`).
    var entry: String = ""

    /// A draft opened on a given measurement, with the unit that measurement is entered in.
    ///
    /// The pair is the point. `kind` and `unit` are two stored properties that must agree, and the
    /// memberwise initialiser will happily let a caller set one and not the other — a height draft
    /// in centimetres, which is exactly the silent error `select(kind:)` exists to prevent once the
    /// screen is open. This is that rule applied to the moment the screen *opens* (RULINGS R15).
    init(kind: MeasurementKind = .dbh) {
        self.kind = kind
        self.unit = MeasureMetrics.defaultUnit(for: kind)
    }

    /// The number, or nil while there is nothing to read.
    ///
    /// A bare `0` is not a measurement of anything, so it does not parse into one. This is not the
    /// "never block submission" rule being bent: that rule is about *precision* — an estimate is as
    /// welcome as a tape — and a zero names no reading at all, the same distinction
    /// `CareLogModel.save` draws about an empty care event.
    var value: Double? {
        guard let parsed = Double(entry), parsed > 0 else { return nil }
        return parsed
    }

    /// The measurement, whole, or nil. There is no path to a `Quantity` without a method (D7).
    var quantity: Quantity? {
        guard let value else { return nil }
        return Quantity(value: value, unit: unit, method: method)
    }

    var canSave: Bool { quantity != nil }

    // MARK: Keypad

    /// 16 §5's twelve keys, applied.
    mutating func apply(_ key: MeasureKey) {
        switch key {
        case let .digit(digit):
            guard entry.count < MeasureMetrics.maxEntryLength else { return }
            // A leading zero followed by digits ("064") is a typo, not a number.
            if entry == "0" { entry = String(digit) } else { entry.append(digit) }
        case .decimalPoint:
            guard !entry.contains(MeasureMetrics.decimalSeparator),
                  entry.count < MeasureMetrics.maxEntryLength
            else { return }
            entry = entry.isEmpty ? "0" + MeasureMetrics.decimalSeparator : entry + MeasureMetrics.decimalSeparator
        case .backspace:
            guard !entry.isEmpty else { return }
            entry.removeLast()
        }
    }

    // MARK: Kind and unit

    /// Changing what is being measured changes the unit under the keypad, and a number entered
    /// against the old question is not an answer to the new one.
    mutating func select(kind newKind: MeasurementKind) {
        guard newKind != kind else { return }
        kind = newKind
        unit = MeasureMetrics.defaultUnit(for: newKind)
        entry = ""
    }

    /// 16 §3's `switch to inches`.
    ///
    /// **The entry is cleared rather than converted.** `Quantity.value` is "the number as the human
    /// typed it, in `unitEntered`. Never silently converted for display" — and converting it on
    /// entry would make that field a lie in the other direction. Keeping the digits and swapping the
    /// label is worse still: `64 cm` would silently become `64 in`, a 2.5× error written to an
    /// append-only record with nothing on screen to catch it. Retyping four digits is the cheap
    /// half of that trade. **NOT SPECIFIED** by SCREENS.md; see ERRATA.
    mutating func switchUnit() {
        unit = MeasureMetrics.alternateUnit(for: kind, from: unit)
        entry = ""
    }
}

/// One key of 16 §5's `1 2 3 4 5 6 7 8 9 . 0 ⌫` pad.
enum MeasureKey: Hashable, Identifiable {
    case digit(Character)
    case decimalPoint
    case backspace

    var id: String { label }

    /// The glyph on the key, verbatim from §5.
    var label: String {
        switch self {
        case let .digit(digit): return String(digit)
        case .decimalPoint: return MeasureMetrics.decimalSeparator
        case .backspace: return "⌫"
        }
    }

    /// Twelve keys, in the drawn order.
    static let pad: [MeasureKey] =
        (1...9).map { .digit(Character(String($0))) } + [.decimalPoint, .digit("0"), .backspace]

    var accessibilityLabel: String {
        switch self {
        case let .digit(digit): return String(digit)
        case .decimalPoint: return "Decimal point"
        case .backspace: return "Delete"
        }
    }
}

// MARK: - Presentation

struct MeasurePresentation {

    /// What D6 will do with this reading once it is saved.
    ///
    /// Three cases, because "no fix" and "a poor fix" are different facts about the world even
    /// though `isEligibleForGrowthCharting` treats them the same. The screen says which.
    enum ChartEligibility: Equatable {
        case eligible
        /// A real fix, outside D6's 15 m limit.
        case tooImprecise(accuracyM: Double)
        /// No fix at all. Nil accuracy is unusable, not assumed good (`CoreEntity`).
        case noFix
    }

    /// 16 §3's sanity pill, and the anomaly line under it.
    struct Sanity: Equatable {
        /// `Last recorded 62 cm, Jun 2024` — always the previous reading in **its own** entered
        /// unit, never converted (D7, `Quantity`).
        let previousText: String
        /// The previous quantity, so the pill can carry its C12 method badge. Every number on this
        /// screen carries how it was obtained.
        let previousQuantity: Quantity
        /// ` · +2 cm in a year sounds right`, or nil when there is no verdict the record supports.
        let verdict: String?
    }

    let draft: MeasureDraft
    /// The tree's display name, once the profile read lands. Nil before that and nil forever if the
    /// read failed — the header simply carries no pill, as 11's and 13's do.
    let treeDisplayName: String?
    /// The most recent non-deleted reading of the drafted kind, or nil.
    let previous: TreeMeasurement?
    /// The accuracy of the fix this reading would be stamped with (D6).
    let gpsAccuracyM: Double?
    private let now: Date
    private let calendar: Calendar
    private let locale: Locale

    init(
        draft: MeasureDraft,
        treeDisplayName: String? = nil,
        previous: TreeMeasurement? = nil,
        gpsAccuracyM: Double? = nil,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current
    ) {
        self.draft = draft
        self.treeDisplayName = treeDisplayName
        self.previous = previous
        self.gpsAccuracyM = gpsAccuracyM
        self.now = now
        self.calendar = calendar
        self.locale = locale
    }

    // MARK: §3 Readout

    /// The digits as typed. Empty until a key is pressed; the view draws that placeholder dimmed so
    /// "nothing entered" and "somebody typed a zero" cannot look the same.
    var readout: String { draft.entry.isEmpty ? MeasureCopy.readoutPlaceholder : draft.entry }

    var hasEntry: Bool { !draft.entry.isEmpty }

    /// ` cm` — the leading space is in the source.
    var unitSuffix: String { MeasureCopy.unitSuffix(draft.unit) }

    /// `switch to inches`.
    var unitSwitchLabel: String {
        MeasureCopy.switchTo(MeasureMetrics.alternateUnit(for: draft.kind, from: draft.unit))
    }

    var canSave: Bool { draft.canSave }

    // MARK: §3 The sanity pill

    /// "the previous value sits under the readout as a sanity check" (16's caption).
    ///
    /// Absent when there is no previous reading of this kind, which is every tree in the shipped
    /// app: the seed carries no `measurements` table at all, and this screen is the only thing that
    /// can write one. A pill reading `Last recorded —` is a surface with nothing behind it
    /// (ARCHITECTURE §5.6).
    ///
    /// **The city's DBH is deliberately not used as the anchor.** `tree.dbhCityCmRange` is a 5 cm
    /// bucket, not a reading — "seed data is a range, never a point" — and subtracting an entered
    /// number from a bucket manufactures a delta nobody measured (D7). See ERRATA.
    var sanity: Sanity? {
        guard let previous else { return nil }
        return Sanity(
            previousText: MeasureCopy.lastRecorded(
                previous,
                calendar: calendar,
                locale: locale
            ),
            previousQuantity: previous.quantity,
            verdict: verdict(against: previous)
        )
    }

    /// `+2 cm in a year sounds right`, or nil.
    ///
    /// The mock states this sentence once, for one plausible year of growth, and it is the only
    /// verdict written. Three things have to be true before it is: the reading has to have gone
    /// **up**, enough time has to have passed for a rate to mean anything (a fortnight's growth is
    /// noise), and the annualised change has to sit inside `MeasureMetrics.maxAnnualGrowthM`. When
    /// any of those fails the pill states the previous reading and stops, and `anomaly` below is
    /// what speaks instead. Same shape as `ActivityCopy.springFlushSubtitle`: a clause that cannot
    /// be verified is dropped rather than softened.
    private func verdict(against previous: TreeMeasurement) -> String? {
        guard let quantity = draft.quantity else { return nil }
        let deltaSI = quantity.siValue - previous.quantity.siValue
        guard deltaSI > 0 else { return nil }

        let months = elapsedMonths(since: previous.capturedAt)
        guard let span = MeasureCopy.spanPhrase(months: months, locale: locale) else { return nil }
        guard annualisedGrowthSI(deltaSI, months: months) <= MeasureMetrics.maxAnnualGrowthM(for: draft.kind)
        else { return nil }

        // Rounded to a tenth before it is formatted. Both values reached SI through a multiply, so
        // 64 cm minus 62 cm is 2.0000000000000018 metres-worth of centimetres and `MeasuredValue
        // .number` — which decides "whole number" by exact equality — would print `+2.0 cm` for a
        // difference the contributor entered as two whole centimetres.
        let delta = ((deltaSI / draft.unit.metresPerUnit) * 10).rounded() / 10
        return MeasureCopy.verdict(delta: delta, unit: draft.unit, span: span)
    }

    /// The "sure about that?" of 16's footnote, or nil.
    ///
    /// SCREENS.md §5 gap 10 lists this as described in copy only, with no drawing. It is built as a
    /// **line above the CTA rather than a dialog that gates the save**, because a gate would
    /// contradict the rule that submission is never blocked for lack of rigor (DECISIONS §2.5,
    /// §3.5) — and because the anomaly is a question for the person holding the tape, not a
    /// judgement the app is entitled to make. See ERRATA.
    var anomaly: String? {
        guard let quantity = draft.quantity else { return nil }
        if !quantity.isPlausible(within: draft.kind.plausibleSIRange) {
            return MeasureCopy.anomalyOutOfRange
        }
        if let previous, quantity.siValue < previous.quantity.siValue {
            return draft.kind == .dbh ? MeasureCopy.anomalyShrunkTrunk : MeasureCopy.anomalyShrunk
        }
        return nil
    }

    // MARK: D6

    /// What will happen to this reading on screen 11, decided before it is written.
    var chartEligibility: ChartEligibility {
        guard let gpsAccuracyM else { return .noFix }
        return gpsAccuracyM <= GPSAccuracy.growthChartingLimitM
            ? .eligible
            : .tooImprecise(accuracyM: gpsAccuracyM)
    }

    /// The sentence under the CTA, or nil when the fix is good enough to say nothing.
    var chartNotice: String? {
        switch chartEligibility {
        case .eligible: return nil
        case .noFix: return MeasureCopy.chartNoticeNoFix
        case let .tooImprecise(accuracy): return MeasureCopy.chartNoticeTooImprecise(accuracyM: accuracy)
        }
    }

    // MARK: §7 Footnote

    /// 16 §7, verbatim, minus its first sentence when that sentence is not about this reading.
    ///
    /// `Taken at 1.4 m` is the DBH convention (BUILD-PLAN §4 `measurement_height_m … for dbh`), and
    /// `TreeMeasurement.height` carries no measurement height at all, by construction. Printing it
    /// over a height reading would describe a column that row does not have. The second sentence
    /// stands on both, because `anomaly` above is what it describes.
    var footnote: String {
        draft.kind == .dbh
            ? MeasureCopy.footnoteDBH + " " + MeasureCopy.footnoteAnomaly
            : MeasureCopy.footnoteAnomaly
    }

    // MARK: Helpers

    private func elapsedMonths(since date: Date) -> Int {
        calendar.dateComponents([.month], from: date, to: now).month ?? 0
    }

    private func annualisedGrowthSI(_ deltaSI: Double, months: Int) -> Double {
        guard months > 0 else { return .infinity }
        return deltaSI * 12 / Double(months)
    }
}

// MARK: - Copy

/// Screen 16's strings, verbatim from SCREENS.md 16 including its typographic characters, except
/// where a clause is deliberately dropped and says so.
enum MeasureCopy {

    /// §1's header title.
    static let screenTitle = "Measure"

    /// §2's micro-label and its two segments, verbatim.
    static let kindLabel = "What are you measuring?"
    static func kindSegment(_ kind: MeasurementKind) -> String {
        switch kind {
        case .dbh: return "Trunk · DBH"
        case .height: return "Height"
        }
    }

    /// §4's micro-label, verbatim. The word `required` is the type system's, not a hint.
    static let methodLabel = "Method · required"

    /// §3's readout placeholder. **NOT SPECIFIED**: the mock draws `64` and no empty state. A dimmed
    /// `0` beside the live unit keeps the readout's shape without asserting a reading of zero; the
    /// CTA is disabled until a key is pressed. See ERRATA.
    static let readoutPlaceholder = "0"

    /// ` cm` — the leading space is in the source (§3).
    static func unitSuffix(_ unit: LengthUnit) -> String { " " + unit.rawValue }

    /// §3's `switch to inches`.
    static func switchTo(_ unit: LengthUnit) -> String { "switch to " + unitName(unit) }

    /// The spelled-out unit the switch link names. **NOT SPECIFIED** beyond `inches`; the other
    /// three follow from the pairs in `MeasureMetrics.alternateUnit`.
    static func unitName(_ unit: LengthUnit) -> String {
        switch unit {
        case .millimetres: return "millimeters"
        case .centimetres: return "centimeters"
        case .metres: return "meters"
        case .inches: return "inches"
        case .feet: return "feet"
        }
    }

    /// §6's CTA, verbatim.
    static let saveCTA = "Save measurement"

    // MARK: §3's sanity pill

    /// `Last recorded 62 cm, Jun 2024`.
    ///
    /// The value is printed in the unit it was entered in, never converted (`Quantity`), and its
    /// method badge rides beside the pill rather than inside this string — a number and its method
    /// are one thing on this screen (D7, `MeasuredValue`).
    static func lastRecorded(_ measurement: TreeMeasurement, calendar: Calendar, locale: Locale) -> String {
        let value = MeasuredValue.formatted(measurement.quantity)
        return "Last recorded \(value), \(monthYear(measurement.capturedAt, calendar: calendar, locale: locale))"
    }

    /// `+2 cm in a year sounds right`.
    static func verdict(delta: Double, unit: LengthUnit, span: String) -> String {
        "+\(MeasuredValue.number(delta)) \(unit.rawValue) \(span) sounds right"
    }

    /// `in a year` / `in 8 months` / `in 3 years`, or nil when too little time has passed for a
    /// rate to mean anything.
    static func spanPhrase(months: Int, locale: Locale) -> String? {
        switch months {
        case ..<MeasureMetrics.minimumVerdictMonths: return nil
        case MeasureMetrics.minimumVerdictMonths..<11: return "in \(months) months"
        case 11...17: return "in a year"
        default: return "in \(spelledOut(months / 12, locale: locale)) years"
        }
    }

    // MARK: The "sure about that?" states (§5 gap 10)

    /// **NOT SPECIFIED.** A trunk that shrank is the case 16's footnote names out loud. The sentence
    /// asks and then gets out of the way: submission is never blocked (DECISIONS §2.5).
    static let anomalyShrunkTrunk = "Sure about that? That is smaller than the last reading. Save it anyway if that is what the tape says."
    /// The same question for a height, which shrinks for reasons a trunk does not (a lost limb).
    static let anomalyShrunk = "Sure about that? That is smaller than the last reading. Save it anyway if that is what you measured."
    /// **NOT SPECIFIED**, and the other half of DECISIONS §3.6's "range validation on entry".
    /// `TreeMeasurement.isPlausible` documents itself as "warn the user, never reject", so this
    /// warns and the CTA stays live.
    static let anomalyOutOfRange = "Sure about that? Readings this size are usually a slipped keypad. Save it anyway if that is what you measured."

    // MARK: D6's notice

    /// **NOT SPECIFIED.** D6 excludes this reading from growth charting and nothing in SCREENS.md 16
    /// says so. Screen 11 already settled the principle in the contributor's favour — the reading is
    /// recorded, it is only the chart it stays off (`GrowthLogRow`, ERRATA E63) — and saying which
    /// is what stops an empty chart from looking like the charting bug E65 describes.
    static func chartNoticeTooImprecise(accuracyM: Double) -> String {
        "This fix is good to about \(Int(accuracyM.rounded())) m, so the reading is saved but stays off the growth chart."
    }

    /// The same fact with no number to give. "Unknown accuracy is treated as unusable rather than
    /// assumed good" (`CoreEntity`, D6).
    static let chartNoticeNoFix = "Without a location fix the reading is saved but stays off the growth chart."

    // MARK: §7's footnote

    /// §7's first sentence, verbatim. DBH only; a height carries no measurement height at all.
    static let footnoteDBH = "Taken at 1.4 m, tape in one hand."
    /// §7's second sentence, verbatim, including its typographic quotes. It describes `anomaly`.
    static let footnoteAnomaly = "A shrinking trunk gets a “sure about that?” before it saves."

    // MARK: Failure

    /// **NOT SPECIFIED** by SCREENS.md 16, in the shape `CareLogCopy.saveFailed` already uses: the
    /// only failure a contributor can act on is a failed *enqueue*, and it says only what is true.
    static let saveFailed = "That did not save. Try once more."

    // MARK: Numbers and dates

    /// `Jun 2024`, formatted against the caller's calendar for the reason `ActivityCopy` gives.
    static func monthYear(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("MMMyyyy")
        return formatter.string(from: date)
    }

    static func spelledOut(_ value: Int, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        formatter.locale = locale
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}

// MARK: - Screen metrics

/// The geometry and the thresholds SCREENS.md 16 gives this screen that the design system does not
/// already name. Kept together so the view body carries no loose numbers and so every judgment call
/// on this screen can be argued with in one place.
enum MeasureMetrics {

    // MARK: Entry

    /// Six characters is `123.45`, well past any street tree in either unit, and short enough that a
    /// stuck key cannot fill the readout.
    static let maxEntryLength = 6
    /// The keypad's `.`. Not localised: it is a glyph on a drawn key, and `Double(_:)` parses this
    /// one. A locale-aware keypad is a decision nobody has taken.
    static let decimalSeparator = "."

    // MARK: Units

    /// What the keypad opens in. Centimetres for a trunk and metres for a height are the units the
    /// mock draws and the units `MeasuredValue` prints everywhere else in the app.
    static func defaultUnit(for kind: MeasurementKind) -> LengthUnit {
        switch kind {
        case .dbh: return .centimetres
        case .height: return .metres
        }
    }

    /// The other end of §3's `switch to …`. **NOT SPECIFIED** for height: the mock draws only the
    /// trunk's `cm ⇄ in`, and `m ⇄ ft` is the same pair one size up. See ERRATA.
    static func alternateUnit(for kind: MeasurementKind, from unit: LengthUnit) -> LengthUnit {
        switch kind {
        case .dbh: return unit == .centimetres ? .inches : .centimetres
        case .height: return unit == .metres ? .feet : .metres
        }
    }

    // MARK: Verdict thresholds

    /// Below this, a rate is noise: two readings a fortnight apart say nothing about growth.
    static let minimumVerdictMonths = 2

    /// The ceiling on annualised change that `+2 cm in a year sounds right` will still be written
    /// over. **Judgment call, NOT SPECIFIED.** Deliberately generous — SF street trees put on
    /// roughly 0.5–2 cm of diameter a year, so 10 cm is far outside anything ordinary while staying
    /// well clear of calling an unusual but real year a mistake. Above it the pill simply prints no
    /// verdict; nothing is blocked and no alarm is raised.
    static func maxAnnualGrowthM(for kind: MeasurementKind) -> Double {
        switch kind {
        case .dbh: return 0.10
        case .height: return 2.0
        }
    }

    // MARK: Margins

    /// §2: the first label block sits under the header, as 05's does.
    static let firstSectionTop: CGFloat = 10
    /// Gap between a micro-label and the control under it.
    static let labelBottom: CGFloat = 6
    /// §3: `padding:18px 0 2px` around the readout.
    static let readoutTop: CGFloat = 18
    static let readoutBottom: CGFloat = 2
    /// §3: `margin-top:2px` under the readout, `margin-top:10px` above the sanity pill.
    static let unitSwitchTop: CGFloat = 2
    static let sanityTop: CGFloat = 10
    /// §5: `gap:8px; padding:16px 18px 0`.
    static let keypadTop: CGFloat = 16
    static let keypadGutter: CGFloat = 18
    static let keypadGap: CGFloat = CypressSpacing.gapRows
    /// §5: each key is `padding:14px 0`.
    static let keyPaddingV: CGFloat = 14
    /// §6: `margin-top:auto; padding:14px 18px 8px`.
    static let ctaTop: CGFloat = 14
    static let ctaGutter: CGFloat = 18
    static let ctaBottom: CGFloat = 8
    /// §7: `padding:0 24px 36px`.
    static let footnoteGutter: CGFloat = 24
}
