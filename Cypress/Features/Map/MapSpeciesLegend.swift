//
//  MapSpeciesLegend.swift
//  Cypress — Features/Map
//
//  ── Why there is a legend at all, when the encoding does not need one ─────────────────────────
//  The coloring answers "which of these are the same tree?" on its own: matching hue and matching
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
//  slots (`minimumPinsForASlot`), and the map is showing no colors in either case. It also draws
//  nothing for a slot whose species name has not arrived — a chip with a swatch and no word is a
//  legend entry that explains nothing.
//

import SwiftUI

/// The four colored species, named — **and, since #116, the map's species filter.**
///
/// ── Why the legend is the filter ─────────────────────────────────────────────────────────────
/// The owner asked for a species narrowing, and attached two constraints to it: the filter and the
/// legend "must agree with each other", and they "must not fight for the same screen space" — the
/// legend having covered the map once already. A separate species chip would have been a second
/// control naming the same four species in the same strip of chrome, which is both of those problems
/// at once, and the agreement would have been something to maintain rather than something true.
///
/// One control cannot disagree with itself and costs no space it was not already costing. Tapping an
/// entry narrows the map to that species; tapping it again clears. A species outside the four is
/// reached the way it always was, by typing it into C20 — `MapModel.speciesIDs` intersects the two,
/// so neither control silently undoes the other.
///
/// The selected entry keeps its swatch and takes the filter row's selected fill, so "this is the one
/// the map is narrowed to" is said in the same visual language the chips beside it use.
struct MapSpeciesLegend: View {

    let palette: MapSpeciesPalette
    /// The species the map is narrowed to, or nil. A binding rather than a callback because the
    /// legend renders the selection as well as setting it.
    @Binding var selection: UUID?

    /// **The entries this view actually draws**, which is not the same as `palette.entries` — a slot
    /// whose species name has not arrived yet draws nothing (see this file's header).
    ///
    /// `static`, because `MapHomeView` has to reserve room for exactly the chips that will be drawn
    /// and there must be one definition of which those are (task #258). A second copy of this filter
    /// in the reservation would be a rule the two could disagree about, and the disagreement would
    /// show up as the legend covering the identify FAB — the defect the reservation exists for.
    static func named(in palette: MapSpeciesPalette) -> [MapSpeciesPalette.Entry] {
        palette.entries.filter { $0.name?.isEmpty == false }
    }

    private var named: [MapSpeciesPalette.Entry] { Self.named(in: palette) }

    /// **The ceiling this legend may grow to before it scrolls rather than pushing the chrome below
    /// it off the screen** (task #258). `nil` for every caller that is not screen 01 — the same
    /// bargain `MapLocationNotice.maxHeight` makes with the same slot's other occupant.
    ///
    /// `MapLayout.legendMaxHeight` gives the legend everything it asks for wherever the screen has
    /// the room, and returns `nil` there so this branch is not taken at all — at every ordinary
    /// content size, on every supported phone, the rendering is byte-for-byte the wrapped `FlowRow`
    /// it has always been. It binds at AX5 with a full four-species palette on the phones at or
    /// below 402 pt, where the search bar, the chip row, four wrapped legend chips,
    /// `MapLocationNotice`'s own floor, the recenter control and the FAB together want more than the
    /// glass has. Something has to yield there, and it must not be the FAB — that control is screen
    /// 01's only entrance to the visit flow, and the legend covering it is the whole of #258.
    /// `AX5ReflowTests.theLegendCeilingBindsWhereTheArithmeticSaysItDoes` carries the boundary.
    ///
    /// The legend is what yields, for the reason RULINGS R53 §6 gave when it made the same call for
    /// the notice: scrolled content is reachable and covered content is not. Every chip stays
    /// pressable, which matters twice over here because the legend is also the species filter
    /// (#116).
    ///
    /// **A clipped legend has to look clipped** (task #72). `MapLayout.quantizedLegendCeiling`
    /// moves the number below off the edge of whichever chip it would otherwise land on, so this
    /// view always ends part-way down a chip — a quarter of one showing at the least, and a quarter
    /// of one hidden at the least. Without it the arithmetic landed, on the phones where it binds,
    /// on a tidy stack of whole chips with nothing under them: a fourth filter the reader has no
    /// way to know is there is a fourth filter the reader does not have.
    var maxHeight: CGFloat?

    /// **The trailing strip this legend must not draw into**, in points — 0 for every caller that
    /// does not put a control there.
    ///
    /// Screen 01 passes `MapLayout.compassColumnReserved`, because MapKit's compass takes the map's
    /// top-**trailing** ornament slot and the legend's band is what hangs below the chip row on the
    /// same side. The compass is drawn by MapKit *under* this chrome, so a chip that reaches the
    /// trailing edge does not merely crowd the compass — it covers it and takes its taps, which is
    /// PR #102's blocking finding: a tap aimed at "put me back to north" applied a species filter
    /// instead.
    ///
    /// **A trailing reserve rather than a vertical one, and that is the whole reason this is
    /// affordable.** Every vertical slot on this screen is already spoken for — `MapLayout`'s own
    /// arithmetic leaves exactly `chipRowTop` between the two reserved blocks at every screen,
    /// inset, palette size and type size the app supports, so there is nowhere to put a 44 pt
    /// control without taking those points off the legend's ceiling or the notice's floor. Width
    /// costs nothing: `MapLayout.legendNaturalHeight` already bounds the legend at *one chip per
    /// line*, so a narrower column can push the drawn legend toward that bound but never past it,
    /// and every reservation built on it is unchanged. Guarded by
    /// `AX5ReflowTests.theLegendNeverDrawsIntoTheCompassColumn`.
    var trailingReserve: CGFloat = 0

    var body: some View {
        if !named.isEmpty {
            if let maxHeight {
                ScrollView {
                    chips
                }
                .frame(maxHeight: maxHeight)
                // Vertical only, and load-bearing for "unchanged where there is room": without it a
                // legend well under its ceiling sits in a tall, mostly empty scroll well instead of
                // hugging its own rows. `MapLocationNotice` and `MapSuggestionList` carry it for
                // exactly this reason.
                .fixedSize(horizontal: false, vertical: true)
                // **The labeled group is the scroller, not the rows inside it** (task #258). An
                // element's frame is what an assistive technology draws its cursor around and what
                // XCUITest measures, and the rows inside a clamped `ScrollView` extend past the
                // window that clips them: on an iPhone 16e at AX5 the visible legend ends at y 417
                // and the `FlowRow` inside it reports a bottom edge of 477.67 — 48 pt of element
                // over controls it does not draw on. Labeling the outer view reports the rectangle
                // the reader can actually see and touch. Found by this ticket's own geometric
                // guard, which went red on a screen that was, in a screenshot, correct.
                .accessibilityElement(children: .contain)
                .accessibilityLabel(MapSpeciesLegendCopy.rowLabel)
            } else {
                chips
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(MapSpeciesLegendCopy.rowLabel)
            }
        }
    }

    private var chips: some View {
        // Wraps rather than scrolls *horizontally*. Four common names can be long ("Brisbane Box",
        // "New Zealand Christmas Tree") and a horizontal scroller on top of a map is a gesture
        // competing with the pan underneath it — the one interaction screen 01 cannot afford to
        // make ambiguous. The vertical ceiling above is a different question and a different axis:
        // it competes with nothing, because the rows it would scroll are rows the reader could not
        // otherwise see at all.
        FlowRow(spacing: MapLayout.chipGap, lineSpacing: MapLayout.chipGap) {
            ForEach(named) { entry in
                Button {
                    selection = selection == entry.speciesID ? nil : entry.speciesID
                } label: {
                    chip(entry)
                }
                .buttonStyle(.plain)
                .cypressHitArea()
            }
        }
        // The compass's column, kept clear by narrowing the row rather than by moving anything.
        // See `trailingReserve`.
        .padding(.trailing, trailingReserve)
    }

    private func chip(_ entry: MapSpeciesPalette.Entry) -> some View {
        let isSelected = selection == entry.speciesID
        return HStack(spacing: CypressSpacing.Component.chipSpeciesSwatchGap) {
            swatch(entry.slot)
            Text(entry.name ?? "")
                .font(CypressFont.body12SemiBold)
                .foregroundStyle(isSelected ? CypressColor.ctaLabel : CypressColor.textBody)
                .lineLimit(1)
        }
        .padding(.vertical, CypressSpacing.Component.chipPaddingVFilter)
        .padding(.horizontal, CypressSpacing.Component.chipPaddingHFilter)
        .background { Capsule().fill(isSelected ? CypressColor.ctaFill : CypressColor.searchFill) }
        .cypressPillBorder(isSelected ? CypressColor.ctaFill : CypressColor.searchBorder)
        // One stop per species, and it says the mark as well as the color. A reader who cannot see
        // either still gets the pairing from the pins, which speak the same name
        // (`MapPinKind.accessibilityLabel(for:palette:)`) — this is the key to that, not a substitute
        // for it.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(MapSpeciesLegendCopy.chipLabel(name: entry.name ?? "", slot: entry.slot))
        // It is a filter now, so it has a state, and the state is not visible to a listener.
        .accessibilityValue(MapFilterCopy.chipValue(isOn: isSelected))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
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
    static let rowLabel = "Species shown in color on this map"

    /// "London Plane, plum pins marked dot". The color is named as well as the mark, because a
    /// reader with partial color vision may be able to use one and not the other.
    static func chipLabel(name: String, slot: MapSpeciesSlot) -> String {
        "\(name), \(colorName(slot)) pins marked \(slot.glyphName)"
    }

    /// Plain words for the four hues. They are *descriptions*, not token names: a listener has no
    /// use for "slot B".
    static func colorName(_ slot: MapSpeciesSlot) -> String {
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
/// AX5 and would not fit on one line at default size either for the longest names in the catalog.
///
/// SwiftUI has no wrapping stack before iOS 16's `Layout`, which this uses: measuring subviews and
/// placing them is a dozen lines here, against a `ScrollView` that would fight the map's pan or a
/// `LazyVGrid` that would give four differently-sized chips four equal columns.
struct FlowRow: Layout {

    var spacing: CGFloat
    var lineSpacing: CGFloat

    /// **What a subview is allowed to measure, given the column it has to live in** (PR #102).
    ///
    /// Every measurement here was `sizeThatFits(.unspecified)` — the subview's *ideal* size, asked
    /// for with no constraint — and the ideal was then both wrapped against and placed at. For a
    /// chip narrower than the row those are the same number. For one wider than the row they are
    /// not, and the row placed it at its ideal anyway: measured on an iPhone 16 Pro Max at AX5, a
    /// `Sycamore, London Plane` chip drew **446 pt wide inside a 408 pt column on a 440 pt screen**,
    /// off the trailing edge of the phone. `lines(_:within:)` could not wrap out of it either —
    /// a single subview is never moved to a line of its own, so the overflow had nothing to break
    /// against.
    ///
    /// Clamping the *proposal* is what fixes it rather than clipping the result: the chip's label is
    /// `.lineLimit(1)`, so a narrower proposal truncates the name and leaves the height alone. That
    /// last part is load-bearing — `MapLayout.legendChipHeightAX5` is a bound on a one-line chip,
    /// and a fix that let a name wrap instead would have broken every reservation built on it.
    private func measure(_ subview: Subviews.Element, within width: CGFloat) -> CGSize {
        let ideal = subview.sizeThatFits(.unspecified)
        guard width.isFinite, ideal.width > width else { return ideal }
        return subview.sizeThatFits(ProposedViewSize(width: width, height: ideal.height))
    }

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
                let size = measure(subviews[index], within: bounds.width)
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
            let size = measure(subviews[index], within: width)
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
