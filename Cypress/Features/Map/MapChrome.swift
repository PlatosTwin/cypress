//
//  MapChrome.swift
//  Cypress — Features/Map
//
//  The parts of screen 01 that float over the map in screen space: the filter chip row, the
//  "What tree is this?" FAB, and the two location states BUILD-PLAN §9 requires.
//
//  Everything here composes §2 components or draws from tokens. No hexes, no font sizes.
//

import SwiftUI

// MARK: - Filter chips

/// Screen 01's filter row (#116, RULINGS R23, restructured by **R23.1**, by task #145, and again
/// by the owner's directives in tasks #165 and #166).
///
/// `Yours · In bloom · Needs care · More filters`, plus a `Clear filters` chip that appears only
/// when something is on. SCREENS.md 01 §12 drew `All / In bloom / Needs care`, single-select; the
/// owner asked for four narrowings and they are not alternatives to each other, so the row became
/// a conjunction and `All` became the row with nothing selected. `MapFilter`'s header is the full
/// argument, including why there is no species chip — the legend is the species control.
///
/// **What R23.1 changed, and what #145 changed after it.** R23.1 moved `Favorites` behind the
/// expandable control; #145 is the owner's follow-up directive cutting the visible row to `Yours ·
/// In bloom · Needs care` and sending `Year` behind the same control, beside `Favorites`. The
/// conjunction, the absent `All`, the single `Clear filters`, the legend-as-species-filter and the
/// result line are all untouched — see `MapExtraFilter` for the drawer's contents and
/// `docs/RULINGS.md` R23.1 for the hazard a hidden narrowing carries, which `Year` now shares:
/// R23.1's three channels (fill, count, spoken names) cover it through the same
/// `MapFilter.activeExtras` expression, so a decade set behind a shut control is still announced.
///
/// **Every chip is an ordinary tappable pill, always** (task #165, overriding R31's presentation
/// clause). R31 drew a condition chip that could not match as a disabled control carrying its
/// reason as a sentence on its own surface; the owner saw the box standing where the `Needs care`
/// pill should be and struck the presentation — no message box ever stands in for a filter. A
/// chip whose filter matches zero trees narrows the map to an empty map, and the empty map is the
/// whole answer; the way out is the `Clear filters` chip, which is on screen whenever anything is
/// set.
///
/// **The row is one horizontally scrolling line, never a second one** (task #166, overriding the
/// wrap this row shipped with). It borrowed `FlowRow` from the legend on the argument that a
/// horizontal scroller over a map competes with the pan underneath it; the owner's directive is
/// "one row for filters, that's it", and the directive wins. The scroll gesture is only ambiguous
/// where the row draws, which is one line of chips at the top of the chrome — a drag that starts
/// on a chip scrolls the row, a pan that starts on the map still pans the map.
struct MapFilterChips: View {
    @Binding var filter: MapModel.Filter

    /// Whether the expandable control is open.
    ///
    /// **View state, not filter state, and the distinction is the whole of R23.1's hazard.** What is
    /// narrowing the map lives in `filter`; whether the reader can currently *see* one of those
    /// narrowings lives here. Closing the control must not clear anything — a disclosure that
    /// discarded what was set inside it would be a control that undoes your instruction when you tidy
    /// the screen — which is exactly why the collapsed chip has to say that something is still on.
    @State private var isExpanded = false

    var body: some View {
        // A stack rather than more entries in the flow: the drawer is a block under the row, not a
        // wide chip in it. In the flow and never an overlay, for R25's reason one control over — an
        // overlay would leave whatever it covered reachable by an assistive technology and invisible
        // to everyone else.
        VStack(alignment: .leading, spacing: MapLayout.chipGap) {
            // One line, scrolled, never wrapped (#166). The indicator is off because a scroll bar
            // under a row of pills reads as a second piece of chrome; the cut-off chip at the
            // trailing edge is what says there is more.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: MapLayout.chipGap) {
                    // The owner's visible three, in the owner's order (#145). `Yours` is the
                    // membership half that stayed; `Favorites` and `Year` are behind `moreChip`.
                    chip(
                        MapFilterCopy.membershipLabel(.yours),
                        isOn: filter.membership == .yours
                    ) {
                        // Tapping the chip that is on turns it off. Every chip in this row is a
                        // toggle, because a conjunction with no way to remove one term is a
                        // conjunction that can only be escaped through `Clear`.
                        filter.membership = filter.membership == .yours ? nil : .yours
                    }

                    // Always live pills (#165). A condition that matches nothing draws the empty
                    // map, which is the whole answer.
                    ForEach(MapFilter.Condition.allCases) { condition in
                        chip(condition.label, isOn: filter.condition == condition) {
                            filter.condition = filter.condition == condition ? nil : condition
                        }
                    }

                    moreChip

                    if filter.isActive {
                        chip(MapFilterCopy.clearLabel, isOn: false) { filter = .all }
                    }
                }
            }
            // The named container is the scroller itself, not the stack around it. It was the
            // outer VStack's, and moving the chips into a `ScrollView` silently removed the
            // labeled group from the accessibility tree XCUITest reads — `otherElements["Filter
            // trees"]` matched nothing, measured on the assigned simulator, not reasoned about.
            // On the scroller, the group survives, and it is also the truer boundary: the row is
            // the group; the drawer below is its own named group (`moreLabel`).
            .accessibilityElement(children: .contain)
            .accessibilityLabel(MapFilterCopy.rowLabel)

            // Open, the drawer's chips are real elements after the row. Shut, they are **not in the
            // tree at all** — the `if` is the point. A drawer built as a hidden overlay, or as chips
            // behind `.opacity(0)`, would leave a filter a sighted reader cannot see and a VoiceOver
            // reader can still swipe onto and press, which is the failure
            // `DeepLinkVoiceOverTests.testAModalIsolatesTheScreenBehindIt` exists for.
            if isExpanded { drawer }
        }
    }

    /// The expandable control itself (R23.1).
    ///
    /// It is a `Chip` like the rest of the row rather than a new kind of object, because it *is* a
    /// filter control — the one that holds the filters there is no room for. Three channels say the
    /// same thing about what is hidden inside it, and they are three because they reach different
    /// readers: the selected fill (sighted, glanceable), the count in the label (sighted, exact, and
    /// survives a reader who cannot tell the two fills apart), and the spoken value, which is the
    /// only one that names what is on.
    private var moreChip: some View {
        let active = filter.activeExtras
        return Chip(
            MapFilterCopy.moreChipLabel(active: active.count),
            style: active.isEmpty ? .filterIdle : .filterSelected
        ) {
            isExpanded.toggle()
        }
        .accessibilityLabel(MapFilterCopy.moreLabel)
        .accessibilityValue(
            MapFilterCopy.moreValue(
                isExpanded: isExpanded,
                // `label(in:)`, so a hidden narrowing that carries a value speaks it — a listener
                // hears `Collapsed, on: Year: 2010s`, not a dimension with no answer (R23.1 §2).
                activeNames: active.map { $0.label(in: filter) }
            )
        )
        .accessibilityHint(MapFilterCopy.moreHint)
    }

    /// What is behind the control: `MapExtraFilter.allCases`, and nothing written out by hand —
    /// the `ForEach` is over the cases, and the switch below only says which *control* draws each
    /// one, because `year` is a value chosen from a menu and `favorites` is a toggle (#145).
    ///
    /// It takes the search bar's own capsule fill rather than a new surface, for `MapFilterStatus`'s
    /// reason — it is another block of chrome in the same strip, and screen 01 has enough kinds of
    /// object floating on it. It wraps (`FlowRow`) where the row above it no longer does (#166):
    /// the owner's one-line directive was about the *row*, this is the opened box under it, and at
    /// AX5 a single chip is most of the width of the phone.
    private var drawer: some View {
        FlowRow(spacing: MapLayout.chipGap, lineSpacing: MapLayout.chipGap) {
            ForEach(MapExtraFilter.allCases) { extra in
                switch extra {
                case .favorites:
                    chip(extra.label(in: filter), isOn: extra.isOn(filter)) {
                        MapExtraFilter.toggleFavorites(in: &filter)
                    }
                case .year:
                    yearChip
                case .siteKind:
                    siteKindChip
                }
            }
        }
        .padding(.vertical, CypressSpacing.Component.chipPaddingVFilter)
        .padding(.horizontal, CypressSpacing.Component.chipPaddingHFilter)
        .background {
            RoundedRectangle(cornerRadius: CypressRadius.cardSm, style: .continuous)
                .fill(CypressColor.searchFill)
        }
        .cypressBorder(CypressColor.searchBorder, radius: CypressRadius.cardSm)
        // A container, not a combine: the chips inside must stay separately reachable, and the
        // group's own name is what tells a reader navigating by element that they have arrived
        // inside the control they just opened rather than somewhere else in the chrome.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(MapFilterCopy.moreLabel)
    }

    /// The one chip that carries a value rather than a state. **In the drawer since #145** — the
    /// owner cut the visible row to `Yours · In bloom · Needs care`, so the decade lives behind
    /// `More filters` beside `Favorites`, and R23.1's three channels are what keep a decade set
    /// behind a shut control from narrowing the map invisibly.
    ///
    /// A `Menu` rather than a sixth and seventh chip per decade: five decades plus `Any year` is
    /// five more capsules over a map. The menu is the system's own,
    /// which means it is already a ≥44 pt target list, already Dynamic Type correct, and already
    /// dismissible by the gesture readers expect — none of which a hand-drawn popover over MapKit
    /// would be. It draws no SF Symbol: the label carries the chosen decade in words
    /// (`MapYearFilterCopy.label`), so there is no chevron to source and nothing added to the five
    /// call sites ticket #130 already owes.
    private var yearChip: some View {
        Menu {
            Button(MapYearFilterCopy.anyLabel) { filter.decade = nil }
            ForEach(MapFilter.Decade.allCases) { decade in
                Button(decade.label) { filter.decade = decade }
            }
        } label: {
            // No `action:`, so `Chip` renders the bare pill and the `Menu` around it owns the press.
            // A `Chip` with its own action inside a `Menu` label would be a button inside a button.
            Chip(
                MapYearFilterCopy.label(filter.decade),
                style: filter.decade == nil ? .filterIdle : .filterSelected
            )
        }
        .cypressHitArea()
        .accessibilityLabel(MapYearFilterCopy.label)
        .accessibilityValue(filter.decade?.label ?? MapYearFilterCopy.anyLabel)
    }

    /// **Tree or empty planting site** (task #179). A `Menu`, built exactly like `yearChip` above,
    /// for exactly its reasons: this is a *value* chosen from a short list, not a toggle, so the
    /// system's own platter gives it a ≥44 pt target list, Dynamic Type and the expected dismiss
    /// gesture for free, and it draws no SF Symbol because the label carries the chosen value in
    /// words (#130 gains no sixth call site).
    ///
    /// Two options and an `Any`, rather than a pair of toggle chips: the two arms are exclusive by
    /// construction — every row is one or the other (`MapSiteKind.of`) — so two toggles would offer
    /// a both-on state meaning "every tree" and a both-off state meaning the same thing, which is
    /// the un-narrowed map wearing two controls. `MapFilter.membership` had this exact shape and
    /// R23 §1 settled it the same way.
    private var siteKindChip: some View {
        Menu {
            Button(MapSiteKindFilterCopy.anyLabel) { filter.siteKind = nil }
            ForEach(MapSiteKind.allCases) { kind in
                Button(MapSiteKindFilterCopy.optionLabel(kind)) { filter.siteKind = kind }
            }
        } label: {
            Chip(
                MapSiteKindFilterCopy.label(filter.siteKind),
                style: filter.siteKind == nil ? .filterIdle : .filterSelected
            )
        }
        .cypressHitArea()
        .accessibilityLabel(MapSiteKindFilterCopy.label)
        .accessibilityValue(
            filter.siteKind.map(MapSiteKindFilterCopy.optionLabel) ?? MapSiteKindFilterCopy.anyLabel
        )
    }

    private func chip(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Chip(title, style: isOn ? .filterSelected : .filterIdle, action: action)
            // The fill and the weight say "on" and neither reaches a listener, so the state travels
            // as a value the way `MapRecenterButton`'s engagement does.
            .accessibilityValue(MapFilterCopy.chipValue(isOn: isOn))
    }
}

// MARK: - The filter's status line, which no longer exists (RULINGS R41, task #180)

// `MapFilterStatus` stood here. It drew two lines in a capsule over the map whenever a filter was
// on: the result count (`31 trees` / `1,458 trees—showing 151`) and, under a chosen decade, the
// year control's caveat (`About 4 in 5 trees have no recorded planting date—…`). **Both are gone,
// and the view with them.**
//
// R41 is categorical and it is the owner's own instruction: "No messages should appear alongside
// filters ever. for any reason. ever again." Its test is "does text appear because a filter did
// something?" — and both lines did, exactly. The ruling names *a count* in the same breath as a
// notice and a card, and it answers the obvious objection in advance: counts have three sanctioned
// channels (R23.1 — chip fill, count **on the chip**, spoken names), and "on the chip is the chip's
// voice, not a companion message". A capsule on the glass is not one of the three.
//
// **Why the count went too, when the owner only named the caveat.** R41 exists because this is the
// third filter-adjacent message to be ruled out and the first two came back "under a different
// mechanism"; the ruling says in terms that it is categorical so no mechanism can shelter one. The
// count sat in the same view, in the same capsule, in the same position, appearing for the same
// cause. Removing the sentence and keeping its neighbor would be exactly the survival R41 was
// written to stop. See `ERRATA E205` for the whole argument and for the
// one thing this costs.
//
// E38 is not weakened by this. E38 forbids *presenting a page as a total*; it is a constraint on a
// number that is shown, and there is now no number. `MapModel.pinLimit` and the 44 pt grid still
// thin the drawn pins, and the map still draws a sample — it simply no longer says a wrong thing
// about it, because it says nothing.

// MARK: - Search suggestions

/// The species that drop under C20 as you type (task #109, ruling **R25**).
///
/// **NOT SPECIFIED** — SCREENS.md 01:667 lists "search results" among the surfaces it does not draw,
/// and §2's C20 is a pill with one glyph in it. `MapSuggestions` is where the design is argued; this
/// file only draws it.
///
/// ── Three properties of this view are load-bearing, and each one is a way it could have gone wrong ─
///
/// **1 · It is in the flow, not an overlay.** The obvious dropdown floats over the chips below it,
/// and it would have been wrong twice: an overlay leaves the chips underneath *hittable* by an
/// assistive technology while a sighted reader cannot see them — the covered-but-reachable failure
/// `DeepLinkVoiceOverTests.testAModalIsolatesTheScreenBehindIt` exists for — and it puts the rows
/// somewhere other than immediately after the field in the element tree, which is where a VoiceOver
/// reader looks for them. In the flow, the chips move down and stay real, and the swipe order is
/// field → suggestions → chips, which is the order the words are in.
///
/// **2 · It is bounded and it scrolls.** Six rows of two serif lines is about a third of the display
/// at the drawn size and rather more than the whole of it at AX5, where each row is a wrapped
/// paragraph. So the list takes at most `share` of the height it was given and scrolls inside that,
/// which is R14's answer on screen 04 and R22's on the add screen, applied a third time. **The cap is
/// a `ScrollView` and not `.clipped()`**, deliberately: `.clipped()` has clipped drawing without
/// clipping touches on this project before, leaving a control that reports `isHittable` and answers
/// nobody.
///
/// **3 · The remainder sentence is inside the card and outside the scroll, and that arrangement was
/// arrived at by looking rather than by thinking.** It began as the last row of the scrolling list,
/// on the reasoning that a reader who hears the rows should hear what they are a page of in the same
/// sweep. Typed into the running app, `a` drew six rows, filled the cap exactly, and left
/// `Showing 6 of at least 100 matching species` **below the fold** — E38's own defect, reproduced one
/// level down by the change that was written to prevent it. It is now pinned under the scroll: still
/// inside the accessibility container, so the sweep is unchanged, and never scrollable away, because
/// the one sentence that says the list is a page cannot be a thing you have to scroll to find.
struct MapSuggestionList: View {

    let suggestions: MapSuggestions
    /// The height this list may take a share of — the chrome's own, measured by the caller.
    let availableHeight: CGFloat
    let onChoose: (Species) -> Void

    /// How much of the screen a dropdown may take before it stops being a hint about the map and
    /// starts being a screen in front of it.
    ///
    /// Half, which at the drawn size is more than six rows need (so nothing scrolls and nothing is
    /// hidden) and at AX5 is about three (so the rest scrolls). Chosen against the running app at
    /// both sizes, per R25 — a share large enough that the list is not a peephole, small enough that
    /// the FAB and the tree card are never underneath it.
    static let share: CGFloat = 0.5

    var body: some View {
        if case let .listing(listing) = suggestions, !listing.rows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(listing.rows.enumerated()), id: \.element.id) { index, species in
                            if index > 0 { rule }
                            row(species)
                        }
                    }
                }
                // The rows are as tall as they want to be until they are not allowed to be, which is
                // what `.frame(maxHeight:)` on a `ScrollView` means. Whatever it cuts off is reachable
                // by scrolling, and the part-row at the cut is what says so.
                .frame(maxHeight: availableHeight * Self.share)
                // `.fixedSize` in the vertical only, so a short list does not inherit the cap as a
                // *height*. Without it a two-row dropdown is two rows in half a screen of white.
                .fixedSize(horizontal: false, vertical: true)

                if let sentence = MapSuggestionCopy.remainder(
                    listing.remainder, shown: listing.rows.count
                ) {
                    rule
                    Text(sentence)
                        .font(CypressFont.body13)
                        .foregroundStyle(CypressColor.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, CypressSpacing.gutterBottomCard)
                        .padding(.vertical, CypressSpacing.gutterBottomCard)
                }
            }
            .background {
                RoundedRectangle(cornerRadius: CypressRadius.cardLg, style: .continuous)
                    .fill(CypressColor.surfaceCard)
            }
            .cypressBorder(CypressColor.borderCool, radius: CypressRadius.cardLg)
            .cypressShadow(light: CypressShadow.bottomCard, dark: CypressShadow.Dark.xl)
            // A container rather than a combine: the rows must stay separately reachable, and the
            // container's own label is what tells a reader navigating by element that a list arrived
            // under the field they are typing in.
            .accessibilityElement(children: .contain)
            .accessibilityLabel(MapSuggestionCopy.listLabel(listing.rows.count))
        }
    }

    /// One species. The same pairing `SpeciesPickView` draws and `SpeciesTile` draws — common name in
    /// the serif list face, scientific name in the italic serif under it — so that a species looks
    /// like a species everywhere in this app rather than looking like a search result here.
    ///
    /// **Nothing else is on the row, and that is a decision** (R25): no thumbnail, because C22's
    /// gradient is derived from the name rather than photographed and would add four colors over the
    /// map for no information; and no count of trees, because a per-species count is a read of a
    /// 195,309-row table on the typing path, and a count of what is *in view* is not the same number
    /// as a count of what is in the city — which is E38 again, one row further down.
    private func row(_ species: Species) -> some View {
        Button {
            onChoose(species)
        } label: {
            VStack(alignment: .leading, spacing: CypressSpacing.gapVitality) {
                Text(MapSuggestionCopy.name(species))
                    .font(CypressFont.listNameSerif)
                    .foregroundStyle(CypressColor.textInk)
                    .multilineTextAlignment(.leading)
                if let latin = MapSuggestionCopy.latin(species) {
                    Text(latin)
                        .font(CypressFont.latinName135)
                        .foregroundStyle(CypressColor.textMuted)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, CypressSpacing.gutterBottomCard)
            .padding(.vertical, CypressSpacing.gutterBottomCard)
            // The row is the target, not the words in it. Two lines of 17.5 and 13.5 with this
            // padding clear 44 pt on their own, and `contentShape` is what makes the gap beside a
            // short name part of the same press.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(MapSuggestionCopy.rowLabel(species))
        .accessibilityAddTraits(.isButton)
    }

    private var rule: some View {
        Rectangle()
            .fill(CypressColor.borderCool)
            .frame(height: CypressSpacing.Component.hairline)
            .accessibilityHidden(true)
    }
}

// MARK: - Search status

/// What the map is showing for the query in C20, when that needs saying.
///
/// **NOT SPECIFIED** — SCREENS.md 01:667 lists "search results" among its unspecified surfaces. The
/// argument for a line here rather than a results screen is in `MapSearch`; this is only the drawing
/// of it, and it is deliberately the smallest thing that can carry the sentence.
///
/// It takes the search bar's own capsule and fill so it reads as part of the bar rather than as a
/// new kind of object floating on the map, and it sits *below* the filter chips so that the order of
/// the chrome C20 → chips is untouched — `CypressUITests/AccessibilityTreeTests` and
/// `DeepLinkVoiceOverTests` both walk that order and both require the search field to stay a real
/// `TextField` in its existing place.
///
/// Nothing is drawn when there is nothing to say, which includes the ordinary success case: a map
/// showing every match it found does not need a banner over it announcing that it did.
struct MapSearchStatus: View {
    let search: MapSearch

    var body: some View {
        if let message = MapSearchCopy.status(for: search) {
            Text(message)
                .font(CypressFont.body13)
                .foregroundStyle(CypressColor.textMuted)
                .padding(.vertical, CypressSpacing.Component.chipPaddingVFilter)
                .padding(.horizontal, CypressSpacing.Component.chipPaddingHFilter)
                .background { Capsule().fill(CypressColor.searchFill) }
                .cypressPillBorder(CypressColor.searchBorder)
                // One element, one sentence. The map behind it has just changed shape, and a reader
                // on VoiceOver gets no other signal that it did.
                .accessibilityElement(children: .combine)
                .accessibilityLabel(message)
        }
    }
}

// MARK: - FAB

/// SCREENS.md 01 §13. `HStack(spacing:9)`, `ctaFill`, pill, `padding:15px 20px`, `shadow.fab`,
/// with the 14pt leaf glyph leading the label.
///
/// The glyph inverts with the scheme: `#8EC3A5` on the deep green FAB in light, `#1D4634` on the
/// mint FAB in dark (D1). Those are the *other* scheme's `ctaFill`, which is why the tokens read
/// crossed over.
struct IdentifyFAB: View {
    var action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    /// Verbatim from SCREENS.md 01.
    private static let label = "What tree is this?"

    var body: some View {
        Button(action: action) {
            HStack(spacing: MapLayout.fabSpacing) {
                LeafGlyph(.fab, tint: glyphTint)
                Text(Self.label)
                    // D1 raises the FAB label to weight 800 in dark and leaves the size alone. §1.3
                    // had no 15.5/800 row, so the ramp grew one (`body155ExtraBold`) rather than
                    // this rounding to 16/800 and changing the size D1 did not ask to change.
                    .font(colorScheme == .dark ? CypressFont.body155ExtraBold : CypressFont.body155)
                    .foregroundStyle(CypressColor.ctaLabel)
            }
            .padding(.vertical, MapLayout.fabPaddingV)
            .padding(.horizontal, MapLayout.fabPaddingH)
            .background { Capsule().fill(CypressColor.ctaFill) }
            .cypressShadow(light: CypressShadow.fab, dark: CypressShadow.Dark.fab)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.label)
    }

    private var glyphTint: Color {
        colorScheme == .dark ? CypressColor.cypressDeep : CypressColor.Dark.accentMint
    }
}

// MARK: - Location states

/// The two states BUILD-PLAN §9 asks for by name — "location permission ask with purpose copy and
/// denied state; map without location".
///
/// **NOT SPECIFIED** in SCREENS.md: 01 lists "empty/no-GPS state" among its unspecified states, so
/// nothing new is drawn for it. Instead it takes the bottom card's slot and the bottom card's
/// surface, which are both already documented, and says the honest thing.
///
/// "map without location" needs no view at all: no GPS dot draws, the map opens on the city instead
/// of on the user, and the tree card omits its distance clause. That absence *is* the state.
///
/// **It draws the sentence it is handed rather than deriving one.** It started out switching on
/// `Availability` itself, which was right while it answered one question; it now answers two — the
/// standing "there is no dot on this map" and the recenter control's "that press could not move
/// anything" (`MapRecenterCopy`) — and those are different sentences about the same permission. The
/// words live in the `*Copy` enums where they can be asserted without rendering a view.
struct MapLocationNotice: View {
    let title: String
    let message: String
    /// `nil` for a state Settings cannot fix — waiting for a first fix, say, where a Settings button
    /// would be advice to change something that is already correct.
    var onOpenSettings: (() -> Void)?

    /// The trailing button's words, when it is not the Settings one.
    ///
    /// **The button was hard-coded to `Settings` and is not any more** (#116). ERRATA E126 requires
    /// a filtered empty map to offer a way *out*, and the way out is `Clear filters` — a different
    /// sentence on the same control, on the same card, in the same slot. Generalizing the label was
    /// the whole change; both existing call sites pass neither and get `Settings`, so nothing that
    /// already used this moved.
    var actionLabel: String = "Settings"
    /// The trailing button's press, when it is not `onOpenSettings`.
    var onAction: (() -> Void)?

    /// One trailing button, whichever of the two filled it.
    private var action: (label: String, run: () -> Void)? {
        if let onAction { return (actionLabel, onAction) }
        if let onOpenSettings { return ("Settings", onOpenSettings) }
        return nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: MapLayout.cardSpacing) {
            VStack(alignment: .leading, spacing: MapLayout.cardMetaTop) {
                Text(title)
                    .font(CypressFont.body145Bold)
                    .foregroundStyle(CypressColor.textInk)
                Text(message)
                    .font(CypressFont.body13)
                    .foregroundStyle(CypressColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if let action {
                Button(action: action.run) {
                    Text(action.label)
                        .font(CypressFont.body13Bold)
                        .foregroundStyle(CypressColor.ctaLabel)
                        .padding(.vertical, CypressSpacing.Component.chipPaddingVFilter)
                        .padding(.horizontal, CypressSpacing.Component.chipPaddingHFilter)
                        .background { Capsule().fill(CypressColor.ctaFill) }
                }
                .buttonStyle(.plain)
                .cypressHitArea()
                .fixedSize()
            }
        }
        .padding(.vertical, MapLayout.cardPaddingV)
        .padding(.horizontal, MapLayout.cardPaddingH)
        .background {
            RoundedRectangle(cornerRadius: CypressRadius.cardLg, style: .continuous)
                .fill(CypressColor.surfaceCard)
        }
        .cypressBorder(CypressColor.borderPinRing, radius: CypressRadius.cardLg)
        .cypressShadow(light: CypressShadow.bottomCard, dark: nil)
    }
}

/// The standing notice's words — what the map says about having no dot on it, unprompted.
enum MapLocationCopy {
    /// No spaces around em dashes (ARCHITECTURE §5.7).
    static func title(_ availability: MapLocationProvider.Availability) -> String {
        availability == .servicesOff ? "Location Services are off" : "Location is off"
    }

    /// **Now it also names the place the reader is looking at instead** (#115, ERRATA E126).
    ///
    /// The first clause was already honest about the absence. It said nothing about the *presence* of
    /// a particular stretch of San Francisco, which is the half of the screen the reader can actually
    /// see — and once the map opens on a remembered camera rather than always on the same park, which
    /// stretch it is became a fact worth stating rather than a constant nobody could be told about.
    ///
    /// The `The map still works` opening is load-bearing: `MapRecenterUITests` reads it as the
    /// black-box witness that this simulator has location denied.
    static func message(_ showing: MapOpening.Showing) -> String {
        "The map still works—it just cannot show where you are, or work out which tree you are "
            + "standing in front of. " + MapOpeningCopy.showing(showing)
    }
}

// MARK: - Recenter

/// The control that puts the camera back on the GPS dot. **NOT SPECIFIED** — the argument for
/// building it, for building it ourselves rather than using `MapUserLocationButton`, and for what a
/// press does about the zoom, is all in `MapRecenter`.
///
/// It sits directly above the FAB in the bottom-right block, which is the one part of screen 01 whose
/// position this screen owns — and owning the position is half the reason the system control could
/// not be used (ERRATA E110's arithmetic).
///
/// A 44pt circle, which is `CypressSpacing.minTapTarget` exactly: the control has no label to widen
/// it, so the drawn shape is the hit target rather than something smaller with padding around it.
struct MapRecenterButton: View {
    let engagement: MapRecenter.Engagement
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(engagement == .centered ? CypressColor.ctaFill : CypressColor.surfaceCard)
                MapLocateGlyph(tint: tint, struckThrough: engagement == .unavailable)
            }
            .frame(width: CypressSpacing.minTapTarget, height: CypressSpacing.minTapTarget)
            .overlay {
                // Only the unengaged circle carries an edge. Filled, it is the CTA green against the
                // map and the ring would be a line drawn on top of its own color.
                if engagement != .centered {
                    Circle().strokeBorder(
                        CypressColor.borderPinRing,
                        lineWidth: CypressSpacing.Component.hairline
                    )
                }
            }
            // The FAB's shadow, because this floats off the same map at the same height and a
            // control that sat flat next to it would read as part of the basemap.
            .cypressShadow(light: CypressShadow.fab, dark: CypressShadow.Dark.fab)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(MapRecenterCopy.label)
        .accessibilityValue(MapRecenterCopy.value(engagement))
        .accessibilityHint(MapRecenterCopy.hint(engagement) ?? "")
    }

    private var tint: Color {
        switch engagement {
        case .centered: return CypressColor.ctaLabel
        // `askable` and `searching` draw exactly as `away` did when all three were one case (#100).
        // The words told the reader apart; the picture never claimed to, and a control that changed
        // color while CoreLocation thought about it would be flicker with no information in it.
        case .away, .askable, .searching: return CypressColor.ctaFill
        // Struck through *and* muted. Either alone reads as a disabled control, which this is not —
        // it is a control that answers with words instead of with the camera.
        case .unavailable: return CypressColor.textMuted
        }
    }
}

/// The crosshair. Drawn rather than borrowed from SF Symbols, for the reason `LeafGlyph` exists:
/// every mark in this app is drawn here, so a system glyph on the map's own chrome would be the
/// one place the drawing came from somewhere else.
///
/// This comment used to say the app had "two `Image(systemName:)` calls, both inside a photo
/// picker". It had five, in three files, and not one of them was in a picker. Ticket #130 drew
/// those five and put the count under a test — `DrawnGlyphGuardTests` — rather than in a sentence,
/// because a sentence cannot go red. The policy itself is stated in `ShareDestinationGlyph`.
///
/// A ring, a dot, and four ticks on the axes — the mark every map in the world uses for this, which
/// is the entire argument for it. It is `accessibilityHidden`; the button around it does the talking.
struct MapLocateGlyph: View {
    let tint: Color
    var struckThrough: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(tint, lineWidth: MapLayout.locateStroke)
                .frame(width: MapLayout.locateRing, height: MapLayout.locateRing)
            Circle()
                .fill(tint)
                .frame(width: MapLayout.locateDot, height: MapLayout.locateDot)
            ForEach(0..<4, id: \.self) { quarter in
                Capsule()
                    .fill(tint)
                    .frame(width: MapLayout.locateStroke, height: MapLayout.locateTick)
                    .offset(y: -(MapLayout.locateRing + MapLayout.locateTick) / 2 - MapLayout.locateTickGap)
                    .rotationEffect(.degrees(Double(quarter) * 90))
            }
            if struckThrough {
                Capsule()
                    .fill(tint)
                    .frame(width: MapLayout.locateStroke, height: MapLayout.locateSlash)
                    .rotationEffect(.degrees(45))
            }
        }
        .accessibilityHidden(true)
    }
}
