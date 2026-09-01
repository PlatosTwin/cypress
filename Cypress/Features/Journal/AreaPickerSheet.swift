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
//  - **C17 `BottomSheet(style: .standard)`, presented the way the app's other three sheets are** —
//    from the composition root, through `RootView`'s single `.fullScreenCover(isPresented:)`, keyed
//    on `AppRouter.sheet`. The first version of this file was a `ZStack` layer inside the tab's own
//    content, which looked identical and was not modal: the PR #132 review tapped the C5 segmented
//    control *through* the scrim and the sheet vanished with no dismissal, and the scrim stopped
//    short of the segmented control and the tab bar. Through the cover this sheet is **exactly as
//    modal as 09, 10 and 15** — the finding was that it was unlike every other `BottomSheet` in the
//    app, and parity is the fix. Measured: with it up, the controls at both ends of the screen
//    report `isHittable == false`. That is the property `RootView`'s comment is protecting when it
//    insists on one cover for all of them.
//
//    **No accessibility claim is made beyond that parity, deliberately.** Driving screen 15's
//    ratified cover as a control shows the background still enumerated in the accessibility
//    hierarchy behind it too, so the cover buys this sheet the same modality the app's other
//    sheets have and not a stronger one. XCUITest's element tree is not VoiceOver's rotor.
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

    // MARK: - The options, and the selection they map back to

    /// `AreaPickerCopy.here` first, then the record's own neighborhoods in the order the read
    /// returned them (largest first — `AreaQueries.neighborhoods`).
    ///
    /// **`here` is always offered, including while it is the one showing.** A picker that hid the way
    /// back would strand a reader who picked a neighborhood by mistake, and the chip's selected state
    /// is what says which one is live.
    ///
    /// **A name two cities share is qualified, and only then** (PR #132 review, F4).
    /// `InventoryUnionSQL.createCanonicalCatalogs` deliberately does not merge neighborhoods across
    /// arms — "two cities may each have a `Downtown`, and merging those would put San Jose's trees in
    /// a San Francisco neighborhood" — so the union can and one day will hand this list two rows with
    /// one label. Unqualified they are two identical chips with nothing to choose between; qualified
    /// unconditionally, all 41 of San Francisco's would carry a city nobody is choosing between. So
    /// the qualifier is applied per colliding name and to nothing else, in the app's own
    /// middle-dot idiom (`Who lives here · 127 species`, `Red flowering gum on 44th Ave · Jan 22`).
    ///
    /// Today's bundle cannot reach it — 41 distinct San Francisco names, and San Jose carries no
    /// polygons at all — so this is written against the configuration D1 exists to enable rather than
    /// against a defect on screen.
    static func options(_ choices: [NeighborhoodChoice]) -> [Option] {
        var seen: [String: Int] = [:]
        for choice in choices { seen[choice.name, default: 0] += 1 }
        return [Option(id: AreaPickerCopy.hereID, label: AreaPickerCopy.here)]
            + choices.map { choice in
                let shared = seen[choice.name, default: 0] > 1
                let label = shared && !(choice.cityName ?? "").isEmpty
                    ? AreaPickerCopy.qualified(choice.name, city: choice.cityName ?? "")
                    : choice.name
                return Option(id: String(choice.id), label: label)
            }
    }

    /// The cities, largest first. No collision rule: `dim_city.display_name` is the city's own civic
    /// name and two live inventories naming one city is what R84 decision 4 forbids outright — a
    /// downloaded copy of a bundled city is an update to it, never a peer.
    static func options(_ choices: [CityChoice]) -> [Option] {
        [Option(id: AreaPickerCopy.hereID, label: AreaPickerCopy.here)]
            + choices.map { Option(id: $0.id, label: $0.name) }
    }

    static func optionID(_ selection: AreaSelection) -> String {
        switch selection {
        case .here: return AreaPickerCopy.hereID
        case let .neighborhood(id): return String(id)
        }
    }

    static func optionID(_ selection: CitySelection) -> String {
        switch selection {
        case .here: return AreaPickerCopy.hereID
        case let .city(idSpace): return idSpace
        }
    }

    /// The inverse. An id that is not `here` and not an integer cannot be produced by `options(_:)`
    /// above, and resolves to `.here` rather than to a crash or a neighborhood 0.
    static func areaSelection(for option: Option) -> AreaSelection {
        guard option.id != AreaPickerCopy.hereID, let id = Int(option.id) else { return .here }
        return .neighborhood(id: id)
    }

    /// The inverse for cities. **An id space literally equal to `AreaPickerCopy.hereID` would be
    /// shadowed** — `id_spaces.id` is `sf`, `us-ca-sj`, `us-ny-nyc`, and a space named `here` would
    /// resolve to the reader's own city instead of itself. A collision worth naming rather than one
    /// worth engineering around: the vocabulary is `<country>-<state>-<city>` by convention
    /// (`dim_city.slug`'s own note), the two exceptions are frozen, and the failure would be visible
    /// on screen rather than silent in a count.
    static func citySelection(for option: Option) -> CitySelection {
        option.id == AreaPickerCopy.hereID ? .here : .city(idSpace: option.id)
    }

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

    /// `Downtown · San Jose` — a neighborhood name two live inventories share, qualified by the city
    /// that drew the polygon (PR #132 review, F4). The middle dot is the app's own compound-label
    /// separator (`AlmanacCopy.compositionLabel`, `AlmanacCopy.bloomSubtitle`,
    /// `CityCopy.recordSince`'s row), so this introduces a rule and not a punctuation mark.
    ///
    /// **Applied only to a name that actually collides** — see `AreaPickerSheet.options(_:)`.
    static func qualified(_ name: String, city: String) -> String { "\(name) · \(city)" }

    static let neighborhoodTitle = "Neighborhood"
    static let cityTitle = "City"

    /// What picking does, said once, at the top of each sheet.
    static let neighborhoodSubtitle = "Read the almanac for any neighborhood the inventories on this "
        + "phone cover. Largest first."
    static let citySubtitle = "Read the city record for any city the inventories on this phone cover. "
        + "Largest first."

    // MARK: The provenance line — the half of F17 that is not the picker

    /// Under the header, whenever the area on screen was resolved from the reader's own fix **and a
    /// nearest tree is what did the resolving**.
    ///
    /// **It is not the only `.fromFix` mechanism, and shipping it as if it were was PR #132's
    /// blocking review finding.** `AlmanacScope` has two cases and R29 is the ruling that they are
    /// different promises: a polygon the seed carries, resolved through the nearest inventoried tree
    /// (`SpeciesQueries.resolveNeighborhood`), and — where no polygon covers the reader — a 1,200 m
    /// circle drawn around them, which no tree chose. Printed over the second, this sentence is
    /// false, and it is false directly above `AlmanacCopy.areaNote` saying no boundary exists and the
    /// almanac was drawn around you instead. **All 52,788 San Jose rows carry
    /// `neighborhood_id IS NULL`**, so that was not an edge: it was every reader in the bundle's
    /// second city, permanently. See `resolvedFromFixRadius` for the sentence that state gets.
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

    /// Under the header for R29's radius fallback — the other `.fromFix` mechanism, and the one that
    /// has no tree in it (PR #132 review, F1).
    ///
    /// **It states what actually happened and nothing more.** The reader's own fix is the center of
    /// the circle (`AlmanacScope.radius(center:meters:)` is handed the coordinate), and that is the
    /// whole of this area's provenance. Why it is a circle rather than a place is `areaNote`'s
    /// sentence, immediately below, and repeating it here would be the same fact twice — the
    /// "not pure data porn" restraint the City segment's brief asks for, applied to copy.
    ///
    /// Deliberately not `nil`. D3's rule is that the default accounts for itself *always*; a blank
    /// where the account should be is how the screen got into F17 in the first place.
    static let resolvedFromFixRadius = "Centered on where you are."

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

    /// The affordance itself, which is now the header pill rather than a control of its own.
    ///
    /// **There is no `change` label any more.** It was a boxed `SecondaryOutlineButton` reading
    /// `Change`, stacked under the provenance sentence on both segments, and the owner's ruling
    /// retired it: the place name in the header is the control. See `HeaderPillButton` for what
    /// replaced it and the picker-header ruling, pending, for why.
    ///
    /// What survives is these two — the hint VoiceOver reads after the pill's name and its button
    /// trait. They name the list that opens, because the pill's label has already named the place:
    /// `Sunset/Parkside, button, Opens the list of neighborhoods on this phone.`
    ///
    /// "on this phone" is the honest scope and it is the sheet's own (`neighborhoodSubtitle`,
    /// `citySubtitle` both say it): the list is what the inventories currently on the device cover,
    /// not every neighborhood there is.
    static let changeAreaHint = "Opens the list of neighborhoods on this phone."
    static let changeCityHint = "Opens the list of cities on this phone."

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
