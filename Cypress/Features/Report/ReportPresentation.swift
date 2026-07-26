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

/// The derivation the view renders. A value, recomputed from the selection on every change.
struct ReportPresentation: Equatable {

    let selection: ReportSelection

    init(selection: ReportSelection) {
        self.selection = selection
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
    /// **This gate knows nothing about the tree, and task #69 will make that matter.** The branch
    /// turns on the chip alone — `ReportModel` holds a `treeID` and never reads the tree — so every
    /// tree in the app gets the same "Call 311 now". 311 is the city's line for *city* trees, and
    /// once a contributor can mark a tree as standing on private property, this screen will route
    /// them to a number that will not take the report. Nothing can reach that state today, because
    /// nothing writes `community_trees.land_context` until #69 ships a picker; the data and the
    /// column exist as of AppSchema v11 and `Tree.landContext` already answers the question for both
    /// city and community rows. Whether the panel changes its copy, offers a different destination,
    /// or says plainly that the city does not handle this tree is a product decision and belongs
    /// with #69. Recorded in ERRATA (E142).
    var showsHazardBranch: Bool { selection.hazard != nil }
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

    static let callCTA = "Call 311 now"
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
