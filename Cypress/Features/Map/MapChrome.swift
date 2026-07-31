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

/// `All / In bloom / Needs care`, single-select, `All` default (SCREENS.md 01 §12).
struct MapFilterChips: View {
    @Binding var filter: MapModel.Filter

    var body: some View {
        HStack(spacing: MapLayout.chipGap) {
            ForEach(MapModel.Filter.allCases) { candidate in
                Chip(
                    candidate.label,
                    style: candidate == filter ? .filterSelected : .filterIdle
                ) {
                    filter = candidate
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Filter trees")
    }
}

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
/// **3 · The remainder is inside the container.** E38's sentence is a row of this list rather than a
/// caption under it, so the reader who hears the rows hears what they are a page of in the same
/// sweep, and so it scrolls with them rather than being the one thing that never moves.
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
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(listing.rows.enumerated()), id: \.element.id) { index, species in
                        if index > 0 { rule }
                        row(species)
                    }
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
            }
            // The list is as tall as it wants to be until it is not allowed to be, which is what
            // `.frame(maxHeight:)` on a `ScrollView` means: no scrolling at all at the drawn size.
            .frame(maxHeight: availableHeight * Self.share)
            // `.fixedSize` in the vertical only, so a short list does not inherit the cap as a
            // *height*. Without it a two-row dropdown is a two-row card in half a screen of white.
            .fixedSize(horizontal: false, vertical: true)
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
    /// gradient is derived from the name rather than photographed and would add four colours over the
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
/// standing "there is no dot on this map" and the recentre control's "that press could not move
/// anything" (`MapRecentreCopy`) — and those are different sentences about the same permission. The
/// words live in the `*Copy` enums where they can be asserted without rendering a view.
struct MapLocationNotice: View {
    let title: String
    let message: String
    /// `nil` for a state Settings cannot fix — waiting for a first fix, say, where a Settings button
    /// would be advice to change something that is already correct.
    var onOpenSettings: (() -> Void)?

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
            if let onOpenSettings {
                Button(action: onOpenSettings) {
                    Text("Settings")
                        .font(CypressFont.body13Bold)
                        .foregroundStyle(CypressColor.ctaLabel)
                        .padding(.vertical, CypressSpacing.Component.chipPaddingVFilter)
                        .padding(.horizontal, CypressSpacing.Component.chipPaddingHFilter)
                        .background { Capsule().fill(CypressColor.ctaFill) }
                }
                .buttonStyle(.plain)
                .cypressHitArea()
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
    /// The `The map still works` opening is load-bearing: `MapRecentreUITests` reads it as the
    /// black-box witness that this simulator has location denied.
    static func message(_ showing: MapOpening.Showing) -> String {
        "The map still works—it just cannot show where you are, or work out which tree you are "
            + "standing in front of. " + MapOpeningCopy.showing(showing)
    }
}

// MARK: - Recentre

/// The control that puts the camera back on the GPS dot. **NOT SPECIFIED** — the argument for
/// building it, for building it ourselves rather than using `MapUserLocationButton`, and for what a
/// press does about the zoom, is all in `MapRecentre`.
///
/// It sits directly above the FAB in the bottom-right block, which is the one part of screen 01 whose
/// position this screen owns — and owning the position is half the reason the system control could
/// not be used (ERRATA E110's arithmetic).
///
/// A 44pt circle, which is `CypressSpacing.minTapTarget` exactly: the control has no label to widen
/// it, so the drawn shape is the hit target rather than something smaller with padding around it.
struct MapRecentreButton: View {
    let engagement: MapRecentre.Engagement
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(engagement == .centred ? CypressColor.ctaFill : CypressColor.surfaceCard)
                MapLocateGlyph(tint: tint, struckThrough: engagement == .unavailable)
            }
            .frame(width: CypressSpacing.minTapTarget, height: CypressSpacing.minTapTarget)
            .overlay {
                // Only the unengaged circle carries an edge. Filled, it is the CTA green against the
                // map and the ring would be a line drawn on top of its own colour.
                if engagement != .centred {
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
        .accessibilityLabel(MapRecentreCopy.label)
        .accessibilityValue(MapRecentreCopy.value(engagement))
        .accessibilityHint(MapRecentreCopy.hint(engagement) ?? "")
    }

    private var tint: Color {
        switch engagement {
        case .centred: return CypressColor.ctaLabel
        // `askable` and `searching` draw exactly as `away` did when all three were one case (#100).
        // The words told the reader apart; the picture never claimed to, and a control that changed
        // colour while CoreLocation thought about it would be flicker with no information in it.
        case .away, .askable, .searching: return CypressColor.ctaFill
        // Struck through *and* muted. Either alone reads as a disabled control, which this is not —
        // it is a control that answers with words instead of with the camera.
        case .unavailable: return CypressColor.textMuted
        }
    }
}

/// The crosshair. Drawn rather than borrowed from SF Symbols, for the reason `LeafGlyph` exists: the
/// app has two `Image(systemName:)` calls in it and both are inside a photo picker, so a system glyph
/// on the map's own chrome would be the one place the drawing came from somewhere else.
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
