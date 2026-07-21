//
//  CheckInPresentation.swift
//  Cypress — Features/CheckIn
//
//  Screen 05 · Light check-in. SCREENS.md lines 805–839; dark appearance D3, lines 1427–1449.
//
//  The 90-second structured health observation. Every field is optional except status, which
//  defaults to alive (PRODUCT §5 M6: "Everything can be skipped; only status has a default").
//
//  **The rubric is data.** Not one anchor sentence, class label or class number is written in this
//  folder. `CheckInPresentation.vitalityRows` reads `Vitality.rubric` — order included — and each
//  row's copy comes off `Vitality.label`, `Vitality.anchor` and `Vitality.classNumber` in
//  `Core/Rubric/Vitality.swift`. Which rubric finally ships is the single highest-value unresolved
//  question in the source documents (DECISIONS §2.5 P-C1), so answering it has to be an edit to one
//  Core file and nothing else.
//
//  No SwiftUI in this file. Everything the view draws is decided here, including the seasonal
//  suppression, so the rules can be reasoned about — and tested — without a renderer.
//

import Foundation

// MARK: - Draft

/// What the contributor has filled in so far.
///
/// Every field is optional and stays optional all the way to `TreeObservation` (BUILD-PLAN §4:
/// `observations.status`, `.vitality`, `.foliage` are all nullable). Nothing here is defaulted on
/// the contributor's behalf except `status`, which PRODUCT §5 M6 says defaults to alive.
struct CheckInDraft: Hashable {

    /// `ObservationStatus`, never `TreeStatus`: an observation reports what a person saw and opens a
    /// review flag; only a moderator moves a tree's own status (DECISIONS §3.7).
    var status: ObservationStatus = .alive

    /// The anchored 1–5 class. Nil until a row is tapped, and cleared by
    /// `CheckInOutboxWriter` when the season does not permit the rating (PRODUCT §3).
    var vitality: Vitality?

    /// SCREENS.md 05 §4 draws only the density axis of PRODUCT §5 M6 step 3. Discoloration and
    /// damage have no control on this screen and are therefore never set — inventing two more
    /// segmented rows would be inventing a screen (DECISIONS constraint 21).
    var foliageDensity: FoliageDensity?

    /// Multi-select, per SCREENS.md 05 §5.
    var structureFlags: Set<StructureFlag> = []

    /// 05 §6's optional well covers "photos · notes". The well is drawn; no editor behind it is
    /// specified, so nothing in the view sets these two yet. They are carried here rather than
    /// bolted on later because the writer's shape is what a picker would have to satisfy, and the
    /// outbox already takes both. See ERRATA (E25).
    var note: String?
    var photos: [OutboxPhoto] = []

    var isEmpty: Bool {
        vitality == nil && foliageDensity == nil && structureFlags.isEmpty
            && note == nil && photos.isEmpty
    }

    /// The three foliage axes as `Core` stores them. Nil when nothing was answered, so an untouched
    /// check-in writes SQL NULL rather than an object full of nulls.
    var foliage: FoliageAssessment? {
        guard let foliageDensity else { return nil }
        return FoliageAssessment(density: foliageDensity)
    }

    /// Declaration order, so the chips do not reorder as they are toggled.
    var orderedStructureFlags: [StructureFlag] {
        StructureFlag.allCases.filter { structureFlags.contains($0) }
    }
}

// MARK: - Vitality rows

/// One of the five full-width anchored rows (D3).
///
/// Every string on it is derived from `Core`'s `Vitality`. There is no initializer that takes a
/// title or an anchor, so a view cannot construct a row whose words are its own.
struct VitalityRow: Hashable, Identifiable {

    let vitality: Vitality
    let isSelected: Bool

    var id: Int { vitality.classNumber }

    init(vitality: Vitality, isSelected: Bool) {
        self.vitality = vitality
        self.isSelected = isSelected
    }

    /// `1 · Severe decline` — SCREENS.md 05 §3's title column. The number and the label are Core's;
    /// the middle dot (U+00B7) is the separator SCREENS.md uses throughout.
    var title: String { "\(vitality.classNumber) · \(vitality.label)" }

    /// The anchor sentence, verbatim from `Vitality.anchor`. Always visible, never truncated (D3).
    var anchor: String { vitality.anchor }
}

// MARK: - Presentation

/// The derivation the view renders. A value, recomputed from the draft on every change.
struct CheckInPresentation: Equatable {

    let draft: CheckInDraft
    /// Why the vitality section is not offered, if it is not (PRODUCT §3 seasonality rule).
    let vitalitySuppression: Vitality.Suppression

    /// - Parameters:
    ///   - species: the tree's species, when the profile read has landed. Nil is normal — the screen
    ///     opens before the read finishes and stays usable if it fails, and a nil habit permits the
    ///     rating year-round (ERRATA E9).
    ///   - month: the calendar month the rating would be collected in.
    init(draft: CheckInDraft, species: Species?, month: Int) {
        self.draft = draft
        self.vitalitySuppression = species.map { Vitality.suppression(for: $0, month: month) } ?? .none
    }

    /// The five rows, in `Vitality.rubric`'s order — worst at the top, as screen 05 draws them.
    ///
    /// Driven by the rubric rather than by a literal list, so a sixth class or a reordering is a
    /// Core change and this file does not move.
    var vitalityRows: [VitalityRow] {
        Vitality.rubric.map { VitalityRow(vitality: $0, isSelected: draft.vitality == $0) }
    }

    /// PRODUCT §3: "The app suppresses the vitality UI off-season using species leaf phenology;
    /// structure flags remain available year-round." The structure section below is unaffected, and
    /// so is everything else on the card.
    var showsVitality: Bool { vitalitySuppression == .none }

    var statusOptions: [ObservationStatus] { ObservationStatus.allCases }
    var foliageOptions: [FoliageDensity] { FoliageDensity.allCases }
    var structureOptions: [StructureFlag] { StructureFlag.allCases }

    func isFlagged(_ flag: StructureFlag) -> Bool { draft.structureFlags.contains(flag) }
}

// MARK: - Copy

/// Screen 05's strings, verbatim from SCREENS.md including its typographic characters — `·`
/// (U+00B7 middle dot) and `/` as the spec writes them.
///
/// The rubric's own words are deliberately absent: they live on `Vitality` (see the file header).
enum CheckInCopy {

    static let screenTitle = "Check-in"
    /// C1's trailing pill.
    static let headerPill = "under a minute"

    static let statusLabel = "Status"
    static let vitalityLabel = "Vitality · tap the closest match"
    /// The same micro-label with its instruction clause removed, for the leaf-off state: there is
    /// nothing to tap, and "tap the closest match" above a box explaining that would contradict
    /// itself. A subtraction from the verbatim label rather than a new string. See ERRATA (E28).
    static let vitalityLabelSuppressed = "Vitality"
    static let foliageLabel = "Foliage"
    static let structureLabel = "Structure · flag anything you see"

    /// C15's placeholder copy.
    static let optionalWell = "Add photos · notes (optional)"

    static let saveCTA = "Save check-in"

    /// Load-bearing, and verbatim. It is the sentence that makes a 90-second card honest.
    static let footnote = "Everything here is optional. Skip anything and it still counts."

    /// The leaf-off state, which BUILD-PLAN §9 lists as a required M2 build ("vitality suppressed
    /// leaf-off state for deciduous species") without giving copy for it.
    ///
    /// **NOT SPECIFIED.** Written to say only what PRODUCT §3 states — a deciduous tree out of leaf
    /// cannot be rated on canopy fullness, and the rest of the card still applies — and to say it
    /// without implying anything about this tree's health. Sentence case, no spaces around a dash
    /// because there is no dash (ARCHITECTURE §5.7). Recorded in ERRATA (E28).
    static let vitalitySuppressed = """
        Out of leaf this month, so there is no canopy to rate. Everything else on this card still \
        counts.
        """

    /// The failed-save line. **NOT SPECIFIED** by SCREENS.md 05, which draws no error state.
    /// It never claims a save that did not happen (DECISIONS constraint 3's principle).
    static let saveFailed = "This check-in was not saved. Try again."
    static let saveRetry = "Try again"
}

// MARK: - Vocabulary labels

/// Display copy for `ObservationStatus` — verbatim from the segments SCREENS.md 05 §2 draws.
enum ObservationStatusLabel {
    static func text(for status: ObservationStatus) -> String {
        switch status {
        case .alive: return "Alive"
        case .declining: return "Declining"
        case .appearsDead: return "Appears dead"
        case .appearsRemoved: return "Removed?"
        }
    }
}

/// Display copy for `FoliageDensity` — verbatim from 05 §4.
///
/// `bareInSeason` is drawn as `Bare`: the stored vocabulary carries "in season" because a bare
/// deciduous tree in January is not an observation, and the label is what the contributor reads.
enum FoliageDensityLabel {
    static func text(for density: FoliageDensity) -> String {
        switch density {
        case .full: return "Full"
        case .thinning: return "Thinning"
        case .sparse: return "Sparse"
        case .bareInSeason: return "Bare"
        }
    }
}

/// Display copy for `StructureFlag` — verbatim from the chips 05 §5 draws, in the order it draws
/// them, which is `StructureFlag`'s own declaration order.
enum StructureFlagLabel {
    static func text(for flag: StructureFlag) -> String {
        switch flag {
        case .lean: return "Lean"
        case .brokenLimb: return "Broken limb"
        case .trunkWound: return "Trunk wound"
        case .rootHeave: return "Root heave"
        case .hardwareIssue: return "Stake / tie issue"
        }
    }
}

// MARK: - Screen metrics

/// The geometry SCREENS.md gives screen 05 that `CypressSpacing` does not already name.
///
/// Same arrangement as `ReportMetrics` and `TreeProfileMetrics`: screen-specific numbers are named
/// once here so the view body carries no loose values, while every colour, font and radius stays a
/// `DesignSystem` token (ARCHITECTURE §6).
enum CheckInMetrics {
    /// 05 §2: the first label block sits at `padding:10px 18px 0`, tighter than the `14px` the
    /// repeated sections use, because the header above it already carries its own 4pt bottom.
    static let firstSectionTop: CGFloat = 10
    /// Gap between a micro-label and the control under it — `margin-bottom:6px` on every label
    /// block of 05.
    static let labelToControl: CGFloat = 6

    /// 05 §3: each row is `padding:8px 12px 8px 8px`, `HStack(spacing:11)`.
    static let rowPaddingV: CGFloat = 8
    static let rowPaddingLeading: CGFloat = 8
    static let rowPaddingTrailing: CGFloat = 12
    static let rowSpacing: CGFloat = 11
    /// The reference swatch — 44×30.
    static let swatchWidth: CGFloat = 44
    static let swatchHeight: CGFloat = 30
    /// The selected row's trailing 20×20 check circle.
    static let checkCircle: CGFloat = 20
    /// `border:2px solid` on the selected row, against `1px` on the rest.
    static let rowBorderSelected: CGFloat = 2

    /// 05 §7: the sticky CTA block — `padding:12px 18px 8px`.
    static let ctaTop: CGFloat = 12
    /// 05 §8: the footnote — `padding:0 18px 36px`.
    static let footnoteBottom: CGFloat = 36
}
