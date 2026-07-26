//
//  ReportPresentation.swift
//  Cypress — Features/Report
//
//  Screen 06 · Report an issue. SCREENS.md lines 843–873.
//
//  The whole screen exists to keep two things apart: a safety hazard, which goes to the city by
//  telephone, and a neighborly note, which stays in Cypress. D4 is the rule — "the public
//  community-note option disappears for hazard categories" — and `Core` already enforces it at the
//  type level: `HazardCategory` and `CommunityNote.Category` have disjoint raw values and no
//  conversion between them (see Core/Models/Hazard.swift). Nothing in this folder converts one to
//  the other, and nothing here can produce a public record from a hazard.
//
//  No SwiftUI in this file. Everything the view draws is decided here, so the split can be reasoned
//  about — and tested — without a renderer.
//

import Foundation

// MARK: - Selection

/// What the contributor has picked.
///
/// The caption calls hazards and neighborly notes "separate pickers", but they are not two
/// independent selections. D4 removes the public note option for hazard categories, so a state that
/// carries both at once must not be representable — one enum with three cases is that guarantee.
/// There is no assignment anywhere that leaves a hazard and a note selected together.
enum ReportSelection: Hashable {
    /// Nothing picked. **NOT SPECIFIED** by SCREENS.md 06 — see `ReportPresentation.showsHazardBranch`.
    case nothing
    case hazard(HazardCategory)
    /// **NOT SPECIFIED** by SCREENS.md 06 as a drawn state; see the same note.
    case note(CommunityNote.Category)

    var hazard: HazardCategory? {
        if case let .hazard(category) = self { return category }
        return nil
    }

    var note: CommunityNote.Category? {
        if case let .note(category) = self { return category }
        return nil
    }
}

// MARK: - Presentation

/// Where a hazard on *this* tree can actually go.
///
/// ── The hole E143 left open, and the measurement that shaped how it is closed ────────────────
/// Until now every tree got the same `Call 311 now`, because the branch was gated on the chip and
/// `ReportModel` never read the tree. 311 is San Francisco's front door for city-owned anything — a
/// sidewalk tree, a Rec/Park tree and an SFUSD yard tree all reach a crew through it, by queues the
/// caller never sees — so the split is not four-way, it is `LandContext.isPublicLand`, one bit.
///
/// ── Only an observation may redirect a safety call. An inference may only inform ─────────────
/// This is the whole rule, and it is `KnownLandContext` earning the reason E143 built it: *a screen
/// cannot show an inference with the confidence of an observation*. Screen 06 is the most
/// consequential screen in the app, so it is the last place that principle may be relaxed.
///
/// The seed says why in numbers. 11,856 city rows infer `.privateProperty`, and **11,153 of them —
/// 94% — come from `caretaker == 'Private'` with no jurisdiction on file**: 8,126 whose
/// `legal_status` reads `Undocumented`, 2,964 `Significant Tree`, 48 `Landmark tree`, 15 blank. Only
/// **703** come from San Francisco actually recording `Private` or `Property Tree` as the legal
/// status. E143 measured that leading on `caretaker` mislabels ~152,000 street trees and built the
/// mapping so jurisdiction leads — but for these 11,153 rows there is no jurisdiction to lead, and
/// the caretaker decides alone. On the *Street* Tree List, "no legal status on file and a private
/// party waters it" describes a great many ordinary street trees whose neighbour holds the hose.
///
/// So the harms are not symmetric and the design follows the asymmetry:
///
/// - Suppressing the call on a misread street tree means somebody with a hanging limb over a
///   pavement was told by an app that the city will not help. That is a safety harm.
/// - Showing the call on a genuinely private tree means a wasted call and a 311 operator saying
///   "not ours". That is a friction harm.
///
/// **Nothing is ever removed.** `Call 311` is reachable in all three cases; the only thing that
/// changes is how loudly the screen recommends it. Shipping the picker therefore cannot make a
/// safety report harder for any tree in the app.
enum HazardHandoff: Equatable {

    /// Screen 06 exactly as it has always drawn. Every public context, and — importantly — every
    /// tree whose context is unknown, which is every row written before AppSchema v11 and every
    /// contributor who declined the question. Unknown is not private; it is unasked.
    case city

    /// The same panel and the same `Call 311 now`, plus one line saying what the city's own record
    /// reads as. The inference is shown and not acted on.
    case cityWithInferredPrivateLand

    /// A contributor stood at the tree and said it is on private land. The panel says the city is
    /// not the party that fixes it, and the call is demoted from the amber CTA to a plain control —
    /// demoted, not deleted, because a contributor can be wrong too and the harm of being wrong runs
    /// one way.
    case notCityMaintained
}

/// The derivation the view renders. A value, recomputed from the selection on every change.
struct ReportPresentation: Equatable {

    let selection: ReportSelection

    /// What the record says about the ground under this tree, and who said it.
    ///
    /// `nil` is the honest majority and the safe default: an unasked community row, a city row whose
    /// `legal_status` and `caretaker` both say nothing, and — deliberately — a tree whose read
    /// failed. `ReportModel.load` swallows the error, so a screen that could not reach the database
    /// falls back to *today's behaviour* rather than to a suppressed call. The failure mode of the
    /// new code is the old code.
    let landContext: KnownLandContext?

    /// The default keeps every existing call site — the previews, the sweep shots, the tests that
    /// are about the picker and not about the tree — meaning what they already meant, because `nil`
    /// is genuinely "nobody asked" and that is genuinely unchanged behaviour.
    init(selection: ReportSelection, landContext: KnownLandContext? = nil) {
        self.selection = selection
        self.landContext = landContext
    }

    /// The hazard picker's chips, in the order `HazardCategory` declares them.
    ///
    /// Driven by the enum rather than by the three chips SCREENS.md 06 draws, because a chip that
    /// does not correspond to a storable category would produce a redirect log and a private
    /// reminder carrying the wrong hazard. The mock's chip set and the category vocabulary do not
    /// agree; document precedence puts data with BUILD-PLAN/PRODUCT over the drawing (ARCHITECTURE
    /// §1, top of file). Recorded in ERRATA (E21).
    var hazardCategories: [HazardCategory] { HazardCategory.allCases }

    /// The neighborly picker's chips. These *do* match the mock one for one.
    var noteCategories: [CommunityNote.Category] { CommunityNote.Category.allCases }

    var selectedHazard: HazardCategory? { selection.hazard }
    var selectedNote: CommunityNote.Category? { selection.note }

    /// SCREENS.md 06 §States, verbatim: "the 311 panel appears because a hazard chip is selected."
    ///
    /// The panel, the private-reminder button and the dashed disclosure are one branch, not three
    /// independent blocks: the disclosure's own sentences are about the call ("until you call"), and
    /// a private reminder's category *is* a `HazardCategory`, so neither can exist without a hazard.
    /// With a neighborly chip selected, or nothing selected, the branch is absent and the screen is
    /// its header plus the two pickers. Both of those states are **NOT SPECIFIED** by SCREENS.md;
    /// this is the restrained reading of what is specified, not an invented state (DECISIONS
    /// constraint 21). Recorded in ERRATA (E22).
    ///
    /// **Whether the branch draws is still the chip alone, and that did not change** when the screen
    /// learned about the tree (E146). A hazard is a hazard on any ground: a split trunk over a
    /// private drive is worth a private reminder and worth a neighbour knowing, and a branch that
    /// vanished for a private tree would delete the reminder button along with the call. What the
    /// branch *says* is `hazardHandoff`'s question, and it is a different one.
    ///
    /// E143 flagged the hole this closed: the gate knew nothing about the tree, `ReportModel` held a
    /// `treeID` and never read it, so every tree got the same `Call 311 now` and 311 is the city's
    /// line for *city* trees. Nothing could reach that state until #69 shipped a picker; it can now.
    var showsHazardBranch: Bool { selection.hazard != nil }

    /// Which of the three handoffs this tree gets. See `HazardHandoff` for the whole argument and
    /// the numbers behind it.
    var hazardHandoff: HazardHandoff {
        guard let landContext, !landContext.context.isPublicLand else { return .city }
        switch landContext.source {
        case .statedByContributor: return .notCityMaintained
        case .inferredFromCityRecord: return .cityWithInferredPrivateLand
        }
    }

    /// The panel's body paragraph. Its title never changes: `This may be a public-safety hazard` is
    /// an assessment of the *tree*, and who owns the ground under it does not make a hanging limb
    /// less dangerous. Only the destination changes, and the destination is what the body is about.
    var hazardPanelBody: String {
        switch hazardHandoff {
        case .city, .cityWithInferredPrivateLand:
            return ReportCopy.hazardPanelBody
        case .notCityMaintained:
            return ReportCopy.notCityMaintainedBody
        }
    }

    /// Whether the amber `Call 311 now` button draws. False only where the panel has just said the
    /// city is not the party that fixes this — `showsDemotedCall` puts the same call back as a plain
    /// control on that branch, so the number is never unreachable.
    var showsCallCTA: Bool { hazardHandoff != .notCityMaintained }

    /// The plain-text `Call 311 anyway`, on the one branch that does not lead with the button.
    var showsDemotedCall: Bool { hazardHandoff == .notCityMaintained }

    /// One line under the CTA saying what San Francisco's record reads as, on a tree the *city's*
    /// row puts on private land.
    ///
    /// It is a sentence and not a redirect on purpose: 94% of the rows that reach this state were
    /// decided by the `caretaker` column alone (`HazardHandoff`), which is the column E143 measured
    /// as the one that mislabels street trees. The screen says what it read and leaves the call
    /// where it was.
    ///
    /// **The city's caretaker string is deliberately not named here, and the seed is why.** Naming
    /// the party the city record gives was the obvious alternative — `caretaker` is populated on
    /// 100% of city rows — and it collapses on precisely the branch it would serve: of the 11,856
    /// rows that infer `.privateProperty`, **11,715 (98.8%) have `caretaker = 'Private'`**. A panel
    /// reading "the city says the caretaker is Private" names nobody, tells the reader nothing they
    /// cannot see from the sentence above it, and dresses a non-answer as a lead. `care_assistant`
    /// is worse: it is populated on 112 of the 703 rows with a private jurisdiction, and 80 of those
    /// say `FUF` — the volunteers who *planted* it, who are not a hazard line.
    var cityRecordPrivateNote: String? {
        hazardHandoff == .cityWithInferredPrivateLand ? ReportCopy.inferredPrivateLandNote : nil
    }
}

// MARK: - Copy

/// Screen 06's strings, verbatim from SCREENS.md including its typographic characters — `·`
/// (U+00B7), `’` (U+2019), `“ ”` (U+201C/U+201D).
enum ReportCopy {

    static let screenTitle = "Report an issue"

    static let hazardSectionLabel = "Safety hazard · for the city’s crew"
    static let noteSectionLabel = "Neighborly note · stays in Cypress"

    static let hazardPanelTitle = "This may be a public-safety hazard"

    /// Verbatim. The first sentence names the hanging-limb case because that is the chip SCREENS.md
    /// draws selected; no per-category variant is written here, because none is specified and
    /// inventing copy for the other three would be inventing a state (DECISIONS constraint 21).
    /// Recorded in ERRATA (E21).
    static let hazardPanelBody = """
        A hanging or broken limb over a path needs the city’s crew, not an app queue. \
        Cypress does not dispatch emergency work.
        """

    /// **NOT SPECIFIED** (ERRATA E146). SCREENS.md 06 draws one panel body, for a screen that had no
    /// way to know whose tree it was on. This is the body for a tree a contributor has said stands on
    /// private land.
    ///
    /// Three sentences, and each one is doing a job the others cannot:
    ///
    /// 1. The first is `hazardPanelBody`'s own closing sentence, kept verbatim. Cypress dispatching
    ///    nothing is true on every ground and the reader should not have to notice it changed.
    /// 2. The second says what 311 is *for* before it says this tree is not it. A reader told only
    ///    "not 311" learns a refusal; a reader told what the line covers learns the rule and can
    ///    apply it themselves next time.
    /// 3. The third states what Cypress cannot do. It would be easy to leave that out and let the
    ///    silence imply somebody is handling it. Nobody is: this app has no owner contact for any
    ///    parcel in San Francisco, and it has no business implying otherwise (DECISIONS constraint 3).
    ///
    /// It does not name the contributor's answer back at them ("you said private property") — the
    /// tree page one screen back already says it in a sentence that names its speaker
    /// (`TreeProfilePresentation.landContextNote`), and a panel that argued with the reader about
    /// their own answer would be picking a fight it cannot win.
    static let notCityMaintainedBody = """
        Cypress does not dispatch emergency work. 311 is the city’s line for the trees the city \
        maintains, and this one is recorded as standing on private property — so the city is not \
        the party that fixes it, and Cypress has no way to reach whoever is.
        """

    /// **NOT SPECIFIED** (ERRATA E146). One line under the amber CTA on a tree the city's own record
    /// reads as private, where the call is unchanged. See `cityRecordPrivateNote` for why this
    /// informs rather than redirects, and why no caretaker is named.
    ///
    /// `reads` and `may not`, not `is` and `will not`: this is Cypress's reading of two columns in a
    /// municipal export and the sentence says so in its own grammar rather than in a footnote.
    static let inferredPrivateLandNote = """
        The city’s own record reads as private land here, so 311 may not be the line for this one.
        """

    static let callCTA = "Call 311 now"

    /// **NOT SPECIFIED** (ERRATA E146). The same number, on the branch that does not lead with it.
    ///
    /// `anyway` is the whole word. It concedes that the screen has just recommended against it and
    /// keeps the choice with the person standing in front of the tree — who can see the limb, and
    /// whose answer about the ground may simply have been wrong. A screen that removed the number
    /// would be making a safety decision on behalf of somebody with better information than it has.
    static let callAnyway = "Call 311 anyway"

    static let saveReminder = "Save a private reminder for yourself"

    /// **NOT SPECIFIED.** SCREENS.md 06 §5 draws the button and nothing after it, so what a
    /// successful save looks like is not in the mock. This is the screen's own sentence — the
    /// disclosure below already says "Your reminder stays yours alone" — rather than new copy, which
    /// is the least invented answer available (DECISIONS constraint 21). It states what happened and
    /// stops: the reminder is on this device's own record, and the city still has not been notified,
    /// which the dashed disclosure directly beneath keeps saying (ARCHITECTURE §5.4). Recorded in
    /// ERRATA (E23).
    static let reminderSaved = "Saved. Your reminder stays yours alone."
    /// **NOT SPECIFIED**, same note. The reminder is not on disk, so nothing may suggest it is.
    static let reminderFailed = "Not saved. Tap to try again."

    /// The dashed disclosure (C14 dashed), split at its bold run. Each part carries its own spacing
    /// exactly as SCREENS.md writes it.
    static let disclosureOpening = """
        Hazards never become public notes: a “hanging limb” pin the city never saw would be a \
        liability record, not a warning. Your reminder stays yours alone, and
        """
    static let disclosureEmphasis = "the city has not been notified"
    static let disclosureContinuation = """
         until you call. “Routed to the city” appears only with a real 311 ticket (Phase 2).
        """

    /// The city's number. `tel:` rather than `telprompt:` — the latter is undocumented API.
    static let telephoneNumber = "311"
    static let telephoneURL = URL(string: "tel://311")

    /// **NOT SPECIFIED.** SCREENS.md draws no failure state for the call, and a device that cannot
    /// dial is not a state the mock anticipates. A system alert changes nothing about the drawn
    /// screen, which is the least this can be while still answering the tap. The wording repeats
    /// the sanctioned honest state and never implies the city heard anything
    /// (DECISIONS constraint 3). Recorded in ERRATA (E23).
    static let callUnavailableTitle = "This device can’t place calls"
    static let callUnavailableMessage = """
        Dial 311 from a phone. The city has not been notified.
        """
    static let callUnavailableDismiss = "OK"
}

// MARK: - Category labels

/// Display copy for the `HazardCategory` vocabulary.
///
/// The four categories are PRODUCT §5 M7's, and these are its own words shortened to chip length:
/// "hanging or broken limb over a path, uprooted, struck by vehicle, blocking a signal or
/// sightline". SCREENS.md 06 draws `Hanging limb` · `Split trunk` · `Blocking path` — one label that
/// matches, one that names a hazard no category can hold, and one that renames a different one. See
/// ERRATA (E21). Sentence case, per ARCHITECTURE §5.7.
enum HazardCategoryLabel {
    static func text(for category: HazardCategory) -> String {
        switch category {
        case .hangingOrBrokenLimb: return "Hanging limb"
        case .uprooted: return "Uprooted"
        case .struckByVehicle: return "Struck by vehicle"
        case .blockingSignalOrSightline: return "Blocking a sightline"
        }
    }
}

/// Display copy for the neighborly categories — verbatim from the chips SCREENS.md 06 draws.
enum CommunityNoteCategoryLabel {
    static func text(for category: CommunityNote.Category) -> String {
        switch category {
        case .needsWater: return "Needs water"
        case .pest: return "Pest suspected"
        case .vandalism: return "Vandalism"
        }
    }
}

// MARK: - Screen metrics

/// The margins SCREENS.md gives screen 06 that `CypressSpacing` does not already name.
///
/// Same arrangement as `TreeProfileMetrics`: screen-specific geometry is named once here so the
/// view body carries no loose numbers, while every colour and font stays a `DesignSystem` token
/// (ARCHITECTURE §6).
enum ReportMetrics {
    /// Gap between a section's micro-label and its chips. **NOT SPECIFIED** — SCREENS.md 06 gives
    /// the section's outer `padding` and the chips' `gap:7px` but no gap under the label. The chip
    /// gap is reused so the block has one rhythm rather than a second invented number.
    static let labelToChips: CGFloat = CypressSpacing.gapDense

    /// 06 §4: 311 panel `margin:18px 16px 0`.
    static let panelTop: CGFloat = 18
    /// 06 §4: `padding:26px 20px`.
    static let panelPaddingV: CGFloat = 26
    static let panelPaddingH: CGFloat = 20
    /// 06 §4: `radius 20px`. §1.4 names no 20 — see ERRATA (E20).
    static let panelRadius: CGFloat = 20
    /// 06 §4: the 54×54 circle, `margin:0 auto 12px`, holding a 22×22 phone glyph.
    static let panelCircle: CGFloat = 54
    static let panelGlyph: CGFloat = 22
    static let panelCircleBottom: CGFloat = 12
    /// 06 §4: title `margin-bottom:5px`, body `margin-bottom:16px`.
    static let panelTitleBottom: CGFloat = 5
    static let panelBodyBottom: CGFloat = 16
    /// Gap between the CTA and the line under it that says what the city's record reads as.
    /// **NOT SPECIFIED** — the line itself is not in the mock (ERRATA E146). `reminderNoteTop`'s own
    /// value, because it is the same relationship one block down: a control, and a sentence about it.
    static let panelNoteTop: CGFloat = CypressSpacing.gapDense

    /// 06 §5: secondary button block `padding:10px 16px 0`.
    static let secondaryTop: CGFloat = 10
    /// Gap between the reminder button and the line that answers a tap on it. **NOT SPECIFIED** —
    /// the state itself is not in the mock. The chip gap is reused rather than a new number invented.
    static let reminderNoteTop: CGFloat = CypressSpacing.gapDense
    /// 06 §6: dashed disclosure `margin:14px 16px 0`.
    static let disclosureTop: CGFloat = 14
    /// Bottom inset before the home indicator. §1.6 gives 36 for a screen that ends in a line of
    /// small print, which is what 06 does.
    static let bottomInset: CGFloat = 36
}
