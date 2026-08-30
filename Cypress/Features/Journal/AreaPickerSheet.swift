//
//  AreaPickerSheet.swift
//  Cypress — Features/Journal
//
//  **Pick a neighborhood, or pick a city.** The owner's 2026-08-28 backlog item ("In journal view,
//  add ability to select a different neighborhood and get the stats for that neighborhood (and ditto
//  for City)"), and the designated fix for tester report F17.
//
//  ── NOT SPECIFIED, and what that means here ───────────────────────────────────────────────────
//  SCREENS.md carries no mock for a picker on any screen, so this is written under DECISIONS
//  constraint 21's delegated-authority pattern — the same footing the City segment itself stands on
//  (`CityView`'s own header) and the same footing R43 §3's affordance table was produced on. The
//  mechanism and the copy are proposals for the owner's ratification; the alternatives that were
//  weighed are recorded in the pull request rather than lost.
//
//  ── Why nothing new is drawn ──────────────────────────────────────────────────────────────────
//  ARCHITECTURE §5 rule 8 sends an unspecified screen to the nearest specified thing, and every
//  piece of this already exists:
//
//  - **C17 `BottomSheet(style: .standard)`** is the app's card-over-scrim, with the drag-to-dismiss
//    band and the scrim tap R42 settled. Screens 09, 10 and 15 present through it.
//  - **C1 `ScreenHeader`** titles it, as it titles the sheets.
//  - **C4 `Chip`, `.filterSelected` / `.filterIdle`, in a `CypressChipFlow`** is the app's existing
//    "choose one of these" control — it is screen 01's map filter row, verbatim, and it already
//    carries the `.isSelected` accessibility trait that makes the current choice audible. A list of
//    rows with a checkmark beside one would be a second selection idiom for the same job, and the
//    checkmark would have to be drawn as a shape because there are no SF Symbols here (R57).
//
//  So this file contributes a layout and two sentences, and no component.
//
//  ── The counts are in the order, not on the chips ─────────────────────────────────────────────
//  `NeighborhoodChoice.treeCount` and `CityChoice.treeCount` order both lists, largest first, and
//  are deliberately not printed on the chips: a capsule reading `Sunset/Parkside · 11,026` is a
//  number nobody asked for at the moment of choosing, and 41 of them is a wall. The ordering is
//  where the count does its work, and each sheet's subtitle closes with `Largest first.` so the
//  order is stated rather than left to be inferred from a list of names.
//

import SwiftUI

/// The sheet both Journal stats segments raise. One view for both because they are one control with
/// two lists — a second copy would be two chances for the two segments to disagree about what
/// picking means.
struct AreaPickerSheet: View {

    /// One thing the reader may pick, flattened out of whichever list this sheet was handed.
    ///
    /// A `String` id rather than the choice types' own, because a neighborhood's id is an `Int` and
    /// a city's is a `String`, and the row that means "where I am" has neither. The sheet does not
    /// need to know which kind it is holding; the caller resolves the tap back into its own
    /// selection type.
    struct Option: Identifiable, Hashable {
        let id: String
        let label: String
    }

    let title: String
    /// The sentence under the title. Says what picking does, in the reader's terms.
    let subtitle: String
    /// `AreaPickerCopy.here` first, then the record's own areas, largest first.
    let options: [Option]
    /// Which option is drawn as chosen. `nil` never happens in practice — `.here` is always in the
    /// list — and is drawn as nothing selected rather than as a guess.
    let selectedID: String?

    let onSelect: (Option) -> Void
    let onClose: () -> Void

    var body: some View {
        BottomSheet(style: .standard, onScrimTap: onClose) {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(title: title)

                Text(subtitle)
                    .font(CypressFont.body125)
                    .foregroundStyle(CypressColor.textMuted)
                    .lineSpacing(CypressFont.LineSpacing.body125)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, CypressSpacing.labelSectionTop)
                    .padding(.horizontal, CypressSpacing.gutter)

                CypressChipFlow(spacing: CypressSpacing.gapDense) {
                    ForEach(options) { option in
                        Chip(
                            option.label,
                            style: option.id == selectedID ? .filterSelected : .filterIdle,
                            action: { onSelect(option) }
                        )
                    }
                }
                .padding(.top, CypressSpacing.labelSectionTop)
                .padding(.horizontal, CypressSpacing.gutter)
                .padding(.bottom, CypressSpacing.bottomFootnote)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Copy

/// Every sentence the picker and the two provenance lines print.
///
/// **NOT SPECIFIED.** Written under DECISIONS constraint 21 and put to the owner in the pull
/// request; see this file's header.
enum AreaPickerCopy {

    /// The option that means "resolve it from my location", and the label the header pill takes when
    /// that is what is showing and there is nothing to name.
    ///
    /// Not `Automatic` and not `Current location`: the reader is being asked which *place* they want
    /// stats for, and the answer this row gives is a place — the one they are in. `Where I am` says
    /// that in the reader's own terms and stays true whether the app can currently name it or not.
    static let here = "Where I am"

    /// The id `AreaPickerSheet.Option` carries for `.here`. An id and not a label, so a translated
    /// or reworded `here` cannot silently stop matching the selection.
    static let hereID = "here"

    static let neighborhoodTitle = "Neighborhood"
    static let cityTitle = "City"

    /// What picking does, said once, at the top of each sheet.
    static let neighborhoodSubtitle = "Read the almanac for any neighborhood the inventories on this "
        + "phone cover. Largest first."
    static let citySubtitle = "Read the city record for any city the inventories on this phone cover. "
        + "Largest first."

    // MARK: The provenance line — the half of F17 that is not the picker

    /// Under the header, whenever the area on screen was resolved from the reader's own fix.
    ///
    /// **This sentence is the actual answer to F17.** The report asks "why does this page seem to
    /// *default* to showing stats for Castro/market?" — and until now the screen said nothing at
    /// all: it printed a neighborhood name in the header as bare fact, with no account of where the
    /// name came from and no way to disagree with it. A reader who could see this line would have
    /// known in one glance both what had happened and what to do about it.
    ///
    /// It names the mechanism (the nearest tree on file) rather than the outcome, because the
    /// mechanism is the part that explains a surprising name.
    static let resolvedFromFix = "Chosen from the tree nearest you in the city record."

    /// Under the header, whenever the reader picked the area themselves. Says what is being looked
    /// at and, by saying it, that it is not where they are standing.
    ///
    /// **Two of them, because the two segments leave out different things and a shared sentence
    /// would be wrong on one of them.** The almanac withholds §4, which is an ask to go and walk to
    /// particular trees; the City segment withholds card 1, which is a comparison against the
    /// reader's own streets. Naming "your own walk" on the City segment would describe a section
    /// that is not there and has never been there — the small dishonesty this whole round is about,
    /// reintroduced in the sentence that fixes it. Caught by looking at the screen, not by a test.
    static let resolvedByChoice = "You're reading a place you're not in, so the section asking you "
        + "to go and look is left out."
    static let resolvedByChoiceCity = "You're reading a city you're not in, so the comparison with "
        + "your own streets is left out."

    /// The affordance itself.
    static let change = "Change"

    // MARK: The fix that cannot name a place (ERRATA — the F17 mechanism)

    /// The state a reader lands in with location granted, a fix in hand, and the fix too coarse to
    /// place them — `AlmanacLimits.fixCanResolveAnArea(accuracyM:)`. In practice: **Precise
    /// Location turned off**, which is a setting, not a fault, and the copy treats it as one.
    ///
    /// It does not name the setting. The app cannot tell an approximate authorization from a poor
    /// fix in a parking garage, and naming the wrong cause is how a true screen becomes a
    /// misleading one. It says what it knows — the fix is too rough to place you — and offers the
    /// door that is actually open, which is the picker.
    static let coarseFixTitle = "Your location is too rough to place you."
    static let coarseFixBody = "The stats here are about one neighborhood at a time, and this "
        + "phone's fix covers too much ground to say which one you're in. Pick an area and it will "
        + "fill in."
    static let coarseFixCityBody = "The stats here are about one city at a time, and this phone's "
        + "fix covers too much ground to say which one you're in. Pick a city and it will fill in."

    /// The button on that state, and on the two out-of-range states, where the picker is the only
    /// thing the reader can still do.
    static let pickAnArea = "Pick an area"
    static let pickACity = "Pick a city"
}
