//
//  MapSpeciesLegend.swift
//  Cypress — Features/Map
//
//  ── Why there is a legend at all, when the encoding does not need one ─────────────────────────
//  The colouring answers "which of these are the same tree?" on its own: matching hue and matching
//  glyph mean matching species, and that is readable off the glass with nothing to consult. The
//  legend answers the *next* question, which is the one the owner is actually walking around with —
//  "same as each other, yes, but same as **what**?" A map that groups without naming turns a street
//  into an abstract pattern.
//
//  ── Why it is four chips and not a panel ─────────────────────────────────────────────────────
//  **NOT SPECIFIED** — SCREENS.md 01 draws a search bar, three filter chips and a FAB, and no
//  legend. So this is built under ARCHITECTURE §5 rule 8 as the smallest surface that can carry the
//  four names, and it borrows every token it uses: the swatch is `MapPin` itself, the chip is C20's
//  capsule and fill, the row is the filter row's gap.
//
//  It sits **below** `MapSearchStatus`, at the bottom of the same absolutely positioned block, for
//  the reason that line sits below the chips: `CypressUITests/AccessibilityTreeTests` and
//  `DeepLinkVoiceOverTests` both walk the order C20 → chips, and nothing may be inserted above the
//  search field.
//
//  ── When it draws nothing ────────────────────────────────────────────────────────────────────
//  Whenever `MapSpeciesPalette` is empty, which is a real and common state rather than an edge case:
//  a clustered viewport has no pins to rank, a viewport whose species are all singletons earns no
//  slots (`minimumPinsForASlot`), and the map is showing no colours in either case. It also draws
//  nothing for a slot whose species name has not arrived — a chip with a swatch and no word is a
//  legend entry that explains nothing.
//

import SwiftUI

/// The four coloured species, named. One chip each, in rank order.
struct MapSpeciesLegend: View {

    let palette: MapSpeciesPalette

    private var named: [MapSpeciesPalette.Entry] {
        palette.entries.filter { $0.name?.isEmpty == false }
    }

    var body: some View {
        if !named.isEmpty {
            // Wraps rather than scrolls. Four common names can be long ("Brisbane Box", "New Zealand
            // Christmas Tree") and a horizontal scroller on top of a map is a gesture competing with
            // the pan underneath it — the one interaction screen 01 cannot afford to make ambiguous.
            FlowRow(spacing: MapLayout.chipGap, lineSpacing: MapLayout.chipGap) {
                ForEach(named) { entry in
                    chip(entry)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(MapSpeciesLegendCopy.rowLabel)
        }
    }

    private func chip(_ entry: MapSpeciesPalette.Entry) -> some View {
        HStack(spacing: CypressSpacing.Component.chipSpeciesSwatchGap) {
            swatch(entry.slot)
            Text(entry.name ?? "")
                .font(CypressFont.body12SemiBold)
                .foregroundStyle(CypressColor.textBody)
                .lineLimit(1)
        }
        .padding(.vertical, CypressSpacing.Component.chipPaddingVFilter)
        .padding(.horizontal, CypressSpacing.Component.chipPaddingHFilter)
        .background { Capsule().fill(CypressColor.searchFill) }
        .cypressPillBorder(CypressColor.searchBorder)
        // One stop per species, and it says the mark as well as the colour. A reader who cannot see
        // either still gets the pairing from the pins, which speak the same name
        // (`MapPinKind.accessibilityLabel(for:palette:)`) — this is the key to that, not a substitute
        // for it.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(MapSpeciesLegendCopy.chipLabel(name: entry.name ?? "", slot: entry.slot))
    }

    /// The pin, at the chip's size.
    ///
    /// It is not literally a `MapPin`: C19's pins are drawn at fixed diameters and an 18 pt dot beside
    /// a 12 pt name is a bullet the size of the line. What *is* shared is the part that could drift —
    /// `MapSpeciesGlyph`, the same view the pin puts inside itself, given the smaller diameter — plus
    /// the fill and the ring tokens. The geometry is a scale of the pin's own 1:6 ring ratio, so a key
    /// and the thing it keys cannot come apart in the only way that would matter.
    private func swatch(_ slot: MapSpeciesSlot) -> some View {
        Circle()
            .fill(slot.fill)
            .overlay {
                MapSpeciesGlyph(
                    slot.glyph,
                    diameter: CypressSpacing.Component.chipSpeciesSwatch
                )
            }
            .overlay {
                Circle().strokeBorder(
                    CypressColor.pinRingStroke,
                    lineWidth: CypressSpacing.Component.chipSpeciesSwatchRing
                )
            }
            .frame(
                width: CypressSpacing.Component.chipSpeciesSwatch,
                height: CypressSpacing.Component.chipSpeciesSwatch
            )
    }
}

// MARK: - Copy

enum MapSpeciesLegendCopy {
    static let rowLabel = "Species shown in colour on this map"

    /// "London Plane, plum pins marked dot". The colour is named as well as the mark, because a
    /// reader with partial colour vision may be able to use one and not the other.
    static func chipLabel(name: String, slot: MapSpeciesSlot) -> String {
        "\(name), \(colourName(slot)) pins marked \(slot.glyphName)"
    }

    /// Plain words for the four hues. They are *descriptions*, not token names: a listener has no
    /// use for "slot B".
    static func colourName(_ slot: MapSpeciesSlot) -> String {
        switch slot {
        case .a: return "plum"
        case .b: return "lagoon"
        case .c: return "iris"
        case .d: return "cherry"
        }
    }
}

// MARK: - Layout

/// A row that wraps. Four chips of unpredictable width in a 361 pt column do not fit on one line at
/// AX5 and would not fit on one line at default size either for the longest names in the catalogue.
///
/// SwiftUI has no wrapping stack before iOS 16's `Layout`, which this uses: measuring subviews and
/// placing them is a dozen lines here, against a `ScrollView` that would fight the map's pan or a
/// `LazyVGrid` that would give four differently-sized chips four equal columns.
struct FlowRow: Layout {

    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = lines(subviews, within: width)
        let height = rows.reduce(into: CGFloat.zero) { total, row in
            total += row.height + (total > 0 ? lineSpacing : 0)
        }
        let widest = rows.map(\.width).max() ?? 0
        return CGSize(width: min(widest, width), height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var y = bounds.minY
        for row in lines(subviews, within: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Line {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func lines(_ subviews: Subviews, within width: CGFloat) -> [Line] {
        var rows: [Line] = []
        var current = Line()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let next = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if !current.indices.isEmpty, next > width {
                rows.append(current)
                current = Line()
            }
            current.indices.append(index)
            current.width = current.indices.count == 1 ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
