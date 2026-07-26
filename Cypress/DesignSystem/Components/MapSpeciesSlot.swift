//
//  MapSpeciesSlot.swift
//  Cypress — DesignSystem/Components
//
//  ══════════════════════════════════════════════════════════════════════════════════════════
//  FOUR SLOTS, NOT 569 COLOURS
//  ══════════════════════════════════════════════════════════════════════════════════════════
//  "Add ability to color different species differently so it's easy to tell which trees are same on
//  a local zoom" (task #80). The seed holds **569 species**, so the first thing this cannot be is a
//  species-to-colour function: 569 hues is a colour wheel, and a reader asked to distinguish the
//  fortieth of them from the forty-first is being asked to do something eyes do not do.
//
//  ── What the reader actually asks, and what the map therefore encodes ────────────────────────
//  The question is *"which of these are the same tree?"* — a question about **matching**, not about
//  naming. Matching needs colours that are unique among the ones on screen right now; it does not
//  need a colour that means *Platanus* forever. So this is a **slot**, and `MapSpeciesPalette`
//  hands the four slots out to the four most common species in the current viewport.
//
//  Measured against the shipped seed, over ten neighbourhoods at the zooms a reader browses at
//  (the pins as `TreeQueries` actually thins them, one per 44 pt cell):
//
//      zoom 19 · 0–75 pins per screen · 6–31 distinct species · top 4 cover 32–90 % of the pins
//      zoom 18 · 14–133 pins         · 10–53 species          · top 4 cover 29–76 %
//      zoom 17 · 93–222 pins         · 27–64 species          · top 4 cover 27–64 %
//
//  There is no zoom at which a screenful of San Francisco street trees is four species. So the
//  encoding has to say something honest about the rest, and what it says is **nothing**: a tree
//  outside the four keeps `MapPin.Kind.cityTree` exactly as it is drawn today — Canopy green, no
//  glyph — and Canopy green is deliberately **not** one of the four slot colours. Green is the
//  residual class, and it carries no species claim at all. Two green pins are not being asserted to
//  be the same tree; they are being asserted to be street trees, which is what green has always
//  meant on this map.
//
//  ── The second channel, which is not optional ────────────────────────────────────────────────
//  RULINGS R8 settled this for C23 and the sentence generalises: "a chart that distinguishes its
//  lines only by hue is unreadable to a colour-blind reader at *any* contrast ratio, so the
//  redundant encoding is owed regardless". A map is a data encoding on the same terms. **Each slot
//  therefore carries a glyph as well as a hue**, drawn in the ring colour inside the pin, and the
//  four glyphs are chosen to differ in silhouette rather than in detail: a dot, a triangle, a
//  cross, a standing bar. A reader who sees no hue at all still sees four different marks, and the
//  legend chip (`MapSpeciesLegend`) shows the same mark beside the name.
//
//  This is not R6's forbidden move. R6 refused a glyph that *replaced a word* on screen 17's queue
//  rows. Nothing on a 18 pt map pin is a word — the pin has never had one — and the word still
//  exists in the two places a word belongs: the legend chip names the species, and
//  `MapPinKind.accessibilityLabel(for:)` speaks it.
//
//  ── What the glyphs are not allowed to be ────────────────────────────────────────────────────
//  The standing bar is **vertical**, and that is a decision rather than a preference: a memorial
//  (`MapPin.Kind.removed`) is a grey 16 pt pin with a *horizontal* bar across it. Two bars at right
//  angles on two different colours at two different sizes cannot be read for each other; two
//  parallel ones could.
//
//  No slot uses a hollow inner ring, because a hollow pin is a vacant planting site (R7), and none
//  uses a check, because a check is screen 18's visited route pin.
//

import SwiftUI

/// One of the four colour slots a viewport can hand out. **Ordinal, not semantic** — slot `a` does
/// not mean any particular species, it means "the most common species on this screen".
///
/// `CaseIterable` in rank order: `MapSpeciesPalette` fills them in this order, so slot `a` is always
/// the busiest species in view and slot `d` the fourth. The lightness of the four fills descends in
/// the same order in light and ascends in dark, so the ranking is faintly visible as weight too —
/// which is a third channel for free and costs nothing if a reader never notices it.
enum MapSpeciesSlot: String, CaseIterable, Hashable, Identifiable, Sendable {
    case a
    case b
    case c
    case d

    var id: String { rawValue }

    /// The pin fill. See `CypressColor.pinSpeciesA` for where the values come from and what every
    /// one of them was measured against.
    var fill: Color {
        switch self {
        case .a: return CypressColor.pinSpeciesA
        case .b: return CypressColor.pinSpeciesB
        case .c: return CypressColor.pinSpeciesC
        case .d: return CypressColor.pinSpeciesD
        }
    }

    /// The redundant mark. Four silhouettes, not four decorations.
    enum Glyph: Hashable, Sendable {
        case dot
        case triangle
        case cross
        case bar
    }

    var glyph: Glyph {
        switch self {
        case .a: return .dot
        case .b: return .triangle
        case .c: return .cross
        case .d: return .bar
        }
    }

    /// What the mark is called, for the one place a reader may need it said: VoiceOver on a legend
    /// chip, where "plum, dot" is how a colour-blind or blind reader ties the chip to the pins.
    var glyphName: String {
        switch self {
        case .a: return "dot"
        case .b: return "triangle"
        case .c: return "cross"
        case .d: return "bar"
        }
    }
}

// MARK: - The mark itself

/// The glyph inside a species-coloured pin, and the same glyph inside its legend chip.
///
/// It is one view used in both places on purpose: a legend whose swatch is drawn by different code
/// from the pin it stands for is a legend that can quietly stop matching the map.
///
/// **Everything is a fraction of `diameter`.** The pin draws it at `pinStandard` and the legend chip
/// at `chipSpeciesSwatch`, and a mark tuned in absolute points for the pin would be a smear on the
/// smaller one. `CypressSpacing.Component.pinSpeciesGlyphRatio` and its siblings are the fractions.
struct MapSpeciesGlyph: View {

    let glyph: MapSpeciesSlot.Glyph
    let diameter: CGFloat
    let tint: Color

    init(_ glyph: MapSpeciesSlot.Glyph, diameter: CGFloat, tint: Color = CypressColor.pinRingStroke) {
        self.glyph = glyph
        self.diameter = diameter
        self.tint = tint
    }

    private var extent: CGFloat { diameter * CypressSpacing.Component.pinSpeciesGlyphRatio }
    private var stroke: CGFloat { diameter * CypressSpacing.Component.pinSpeciesGlyphStrokeRatio }

    var body: some View {
        Group {
            switch glyph {
            case .dot:
                Circle()
                    .fill(tint)
                    .frame(width: extent * CypressSpacing.Component.pinSpeciesDotRatio,
                           height: extent * CypressSpacing.Component.pinSpeciesDotRatio)
            case .triangle:
                CypressTriangle()
                    .fill(tint)
                    .frame(width: extent, height: extent * CypressSpacing.Component.pinSpeciesTriangleRatio)
            case .cross:
                ZStack {
                    Capsule().fill(tint).frame(width: extent, height: stroke)
                    Capsule().fill(tint).frame(width: stroke, height: extent)
                }
            case .bar:
                // Vertical. A memorial's bar is horizontal — see this file's header.
                Capsule()
                    .fill(tint)
                    .frame(width: stroke, height: extent)
            }
        }
        // The mark is redundant with the fill by construction, so it must never become a second
        // VoiceOver stop on a pin that already announces its species in words.
        .accessibilityHidden(true)
    }
}

/// An upward triangle inscribed in its frame. There is no SF Symbol here on purpose: the pin is
/// rasterised through `ImageRenderer` at 18 pt and a symbol's own optical padding would land the
/// mark off-centre inside the dot.
struct CypressTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
