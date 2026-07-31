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

/// Screen 01's filter row (#116, RULINGS R23).
///
/// `Yours · Favourites · Year ▾ · Needs care · In bloom`, plus a `Clear` chip that appears only when
/// something is on. SCREENS.md 01 §12 drew `All / In bloom / Needs care`, single-select; the owner
/// asked for four narrowings in priority order and they are not alternatives to each other, so the
/// row became a conjunction and `All` became the row with nothing selected. `MapFilter`'s header is
/// the full argument, including why there is no species chip — the legend is the species control.
///
/// **It wraps rather than scrolls**, borrowing `FlowRow` from the legend, and for the reason stated
/// there: "a horizontal scroller on top of a map is a gesture competing with the pan underneath it —
/// the one interaction screen 01 cannot afford to make ambiguous". Six chips do not fit one 361 pt
/// line at default size, let alone at AX5.
struct MapFilterChips: View {
    @Binding var filter: MapModel.Filter

    var body: some View {
        FlowRow(spacing: MapLayout.chipGap, lineSpacing: MapLayout.chipGap) {
            ForEach(MapMembership.allCases) { kind in
                chip(
                    MapFilterCopy.membershipLabel(kind),
                    isOn: filter.membership == kind
                ) {
                    // Tapping the chip that is on turns it off. Every chip in this row is a toggle,
                    // because a conjunction with no way to remove one term is a conjunction that
                    // can only be escaped through `Clear`.
                    filter.membership = filter.membership == kind ? nil : kind
                }
            }

            yearChip

            ForEach(MapFilter.Condition.allCases) { condition in
                chip(condition.label, isOn: filter.condition == condition) {
                    filter.condition = filter.condition == condition ? nil : condition
                }
            }

            if filter.isActive {
                chip(MapFilterCopy.clearLabel, isOn: false) { filter = .all }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(MapFilterCopy.rowLabel)
    }

    /// The one chip that carries a value rather than a state.
    ///
    /// A `Menu` rather than a sixth and seventh chip per decade: five decades plus `Any year` is
    /// five more capsules on a row already carrying five, over a map. The menu is the system's own,
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

    private func chip(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Chip(title, style: isOn ? .filterSelected : .filterIdle, action: action)
            // The fill and the weight say "on" and neither reaches a listener, so the state travels
            // as a value the way `MapRecentreButton`'s engagement does.
            .accessibilityValue(MapFilterCopy.chipValue(isOn: isOn))
    }
}

// MARK: - The filter's result and its empty state

/// What the filter says about what it found — the count, the year caveat, or nothing.
///
/// It borrows `MapSearchStatus`'s capsule exactly, because it is the same kind of object in the same
/// strip of chrome: a sentence about how the map has been narrowed. Two lines at most, and it draws
/// nothing at all when no filter is on, so an un-narrowed screen 01 is untouched.
struct MapFilterStatus: View {
    let result: String?
    let showsYearCaveat: Bool

    var body: some View {
        if result != nil || showsYearCaveat {
            VStack(alignment: .leading, spacing: MapLayout.chipGap) {
                if let result {
                    line(result)
                }
                // The sentence that keeps the year control honest about the 74 % of rows it cannot
                // judge (ERRATA E175). It sits *below* the count deliberately: the count is the
                // answer, this is the qualification on it.
                if showsYearCaveat {
                    line(MapYearFilterCopy.setAside)
                }
            }
        }
    }

    private func line(_ message: String) -> some View {
        Text(message)
            .font(CypressFont.body13)
            .foregroundStyle(CypressColor.textMuted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, CypressSpacing.Component.chipPaddingVFilter)
            .padding(.horizontal, CypressSpacing.Component.chipPaddingHFilter)
            .background { Capsule().fill(CypressColor.searchFill) }
            .cypressPillBorder(CypressColor.searchBorder)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(message)
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

    /// The trailing button's words, when it is not the Settings one.
    ///
    /// **The button was hard-coded to `Settings` and is not any more** (#116). ERRATA E126 requires
    /// a filtered empty map to offer a way *out*, and the way out is `Clear filters` — a different
    /// sentence on the same control, on the same card, in the same slot. Generalising the label was
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
