//
//  CypressSpacing.swift
//  Cypress — DesignSystem/Tokens
//
//  Source of truth: docs/distilled/SCREENS.md §1.6 (spacing), §1.7 (device frame).
//
//  The spec-page rhythm in §1.6's last paragraph (page padding `56px 56px 120px`, max width
//  `1560px`, section `margin-top:88px`, the 402pt figure grid) is design-document chrome, not app
//  UI, and is deliberately not transcribed.
//
//  §1.7's device frame is presentation scaffolding — "Do not ship the frames. In SwiftUI use real
//  safe areas." The canvas numbers are kept under `Device` for reference and for anything that
//  reproduces the mock geometry (share cards, the token gallery); layout code uses safe areas.
//

import SwiftUI

enum CypressSpacing {

    // MARK: - Horizontal gutters
    //
    // One rhythm, two variants: 16 inside cards, 18 for blocks headed by an uppercase micro-label.
    // Screens 05, 06, 11, 12, 13, 16, 17 mix both — label blocks get 18, card grids get 16.

    /// `16px` — content that lives inside cards.
    static let gutter: CGFloat = 16
    /// `18px` — content headed by an uppercase micro-label.
    static let gutterLabel: CGFloat = 18
    /// `14px` — 01 bottom tree card (`left:14px;right:14px`).
    static let gutterBottomCard: CGFloat = 14
    /// `20px` — 15 account sheet.
    static let gutterSheet: CGFloat = 20

    // MARK: - Vertical rhythm

    /// Screen header `padding: 10px 18px 4px`.
    static let headerPaddingTop: CGFloat = 10
    /// Screen header trailing/leading inset — same as `gutterLabel`.
    static let headerPaddingHorizontal: CGFloat = 18
    /// Screen header bottom padding `4px`.
    static let headerPaddingBottom: CGFloat = 4
    /// Screen header bottom padding on 02 — `6px`.
    static let headerPaddingBottom02: CGFloat = 6

    /// Repeated label section `padding: 14px 18px 0` — top.
    static let labelSectionTop: CGFloat = 14

    // MARK: - Stack gaps

    /// `gap: 8px` — card stacks / rows.
    static let gapRows: CGFloat = 8
    /// `gap: 7px` — chips and dense rows.
    static let gapDense: CGFloat = 7
    /// `gap: 6px` — vitality rows (05).
    static let gapVitality: CGFloat = 6
    /// `gap: 10px` — 02 candidate list.
    static let gapCandidates: CGFloat = 10
    /// `gap: 9px` — 08 species grid, 09 chips.
    static let gapGrid: CGFloat = 9

    // MARK: - Bottom padding before the home indicator

    /// `30px` — above a bottom bar.
    static let bottomBar: CGFloat = 30
    /// `36px` — above a footnote line.
    static let bottomFootnote: CGFloat = 36
    /// `40px` — 02 CTA.
    static let bottomCTA: CGFloat = 40
    /// `44px` — sheets.
    static let bottomSheet: CGFloat = 44
    /// `8px` — gap under a sticky CTA that sits over a footnote (pairs with `bottomFootnote`).
    static let bottomStickyCTAGap: CGFloat = 8

    // MARK: - Accessibility

    /// Minimum tap target, ARCHITECTURE §6: "Tap targets ≥44 pt. ... where the mock and
    /// accessibility disagree, the target grows and the *visual* stays put via `contentShape`."
    static let minTapTarget: CGFloat = 44

    // MARK: - Device canvas (§1.7) — reference only, do not lay out against these

    enum Device {
        /// Screen canvas width, logical points.
        static let width: CGFloat = 402
        /// Screen canvas height, logical points.
        static let height: CGFloat = 874
        /// Status-bar inset the mocks bake in (`paddingTop: 62`). Use real safe areas instead.
        static let statusBarInset: CGFloat = 62
        /// Frame's own bottom padding (`paddingBottom: 10`).
        static let homeIndicatorInset: CGFloat = 10
        /// Content height when a screen declares `height:812px; padding-top:62px` (812 + 62 = 874).
        static let contentHeight: CGFloat = 812
    }
}

// MARK: - Modifiers

extension View {
    /// The 16pt in-card gutter.
    func cypressGutter() -> some View {
        padding(.horizontal, CypressSpacing.gutter)
    }

    /// The 18pt gutter used by blocks headed by an uppercase micro-label.
    func cypressLabelGutter() -> some View {
        padding(.horizontal, CypressSpacing.gutterLabel)
    }

    /// Grows the hit area to the 44pt minimum without moving the visual (ARCHITECTURE §6).
    func cypressTapTarget(_ size: CGFloat = CypressSpacing.minTapTarget) -> some View {
        frame(minWidth: size, minHeight: size)
            .contentShape(Rectangle())
    }
}

// MARK: - §2 component metrics
//
// The fixed geometry of the C1–C30 catalog: the sizes and paddings SCREENS.md §2 states in px.
// They live here for the same reason the hexes live in `CypressColor` — so a component file
// contains no unexplained number, and so a spec change has one place to land.
//
// **Visual sizes are the mock's, exactly.** Where a visual is below the 44pt minimum tap target,
// the component keeps this size and grows the hit area with `.cypressTapTarget()`; the enlarged
// area is never one of these constants.

extension CypressSpacing {

    enum Component {

        // C1 · ScreenHeader
        /// Back circle — 44×44 (already at the tap minimum).
        static let backCircle: CGFloat = 44
        /// Chevron glyph — 10×16 in a 10×16 viewBox, stroke 2.2.
        static let chevronWidth: CGFloat = 10
        static let chevronHeight: CGFloat = 16
        static let chevronStroke: CGFloat = 2.2
        /// Header `HStack(spacing: 12)`.
        static let headerSpacing: CGFloat = 12
        /// Trailing pill — `padding: 5px 12px`.
        static let headerPillPaddingV: CGFloat = 5
        static let headerPillPaddingH: CGFloat = 12

        // C2 · HeroPhotoHeader
        /// 03 / D2 hero height.
        static let heroHeightProfile: CGFloat = 224
        /// 07 hero height.
        static let heroHeightSpecies: CGFloat = 190
        /// 19 hero height.
        static let heroHeightMemorial: CGFloat = 200
        /// Back button inset — `left:16px; top:66px`.
        static let heroBackLeading: CGFloat = 16
        static let heroBackTop: CGFloat = 66
        /// Meta pill — `padding: 4px 11px`, `right:14px; bottom:12px`.
        static let heroPillPaddingV: CGFloat = 4
        static let heroPillPaddingH: CGFloat = 11
        static let heroPillTrailing: CGFloat = 14
        static let heroBottomInset: CGFloat = 12
        /// Eyebrow inset — `left:16px; bottom:12px`.
        static let heroEyebrowLeading: CGFloat = 16

        // C3 · FoliageStrip
        static let foliageCellHeight: CGFloat = 26
        static let foliageCellGap: CGFloat = 3
        static let foliageMonthGap: CGFloat = 3
        static let foliageMonthTop: CGFloat = 3
        static let foliageEyebrowBottom: CGFloat = 6
        /// Share-card variant — 12 × 11pt squares, `gap:2.5px`.
        static let foliageShareCell: CGFloat = 11
        static let foliageShareGap: CGFloat = 2.5

        // C4 · Chip
        /// Filter / phenology — `7px 15px`.
        static let chipPaddingVFilter: CGFloat = 7
        static let chipPaddingHFilter: CGFloat = 15
        /// Meta / legend / sanity — `6px 13px` (`6px 14px` for shot type and sanity).
        static let chipPaddingVMeta: CGFloat = 6
        static let chipPaddingHMeta: CGFloat = 13
        static let chipPaddingHMetaWide: CGFloat = 14
        /// Structure flag / hazard / dark flag — `11px 16px`.
        static let chipPaddingVFlag: CGFloat = 11
        static let chipPaddingHFlag: CGFloat = 16
        /// Care toggle — `12px 18px`.
        static let chipPaddingVCare: CGFloat = 12
        static let chipPaddingHCare: CGFloat = 18
        /// Legend dot — 10×10 filled, 5×5 hollow with a 2.5 border; `gap:7px`.
        static let chipLegendDot: CGFloat = 10
        static let chipLegendDotHollow: CGFloat = 5
        static let chipLegendDotStroke: CGFloat = 2.5
        static let chipLegendGap: CGFloat = 7
        /// Border widths: 1px everywhere except the amber hazard-on chip at 1.5px.
        static let hairline: CGFloat = 1
        static let hairlineStrong: CGFloat = 1.5

        // C5 · SegmentedControl
        /// `padding:10px 2px` (05) / `11px 2px` (16).
        static let segmentPaddingV: CGFloat = 10
        static let segmentPaddingVLarge: CGFloat = 11
        static let segmentPaddingH: CGFloat = 2

        // C6 / C7 · Buttons
        /// `padding:15px` — the default primary.
        static let buttonPadding: CGFloat = 15
        /// `padding:13px` — 12 "Walk the nine", 06 secondary, W1.
        static let buttonPaddingSmall: CGFloat = 13
        /// `padding:14px` — 02/18 secondary, 15 Apple button.
        static let buttonPaddingMedium: CGFloat = 14
        /// `padding:16px` — 18 "Next nearest…".
        static let buttonPaddingLarge: CGFloat = 16
        /// C7 outline width — `2px`.
        static let outlineWidth: CGFloat = 2

        // C8 · QuadActionRow
        /// `HStack(spacing:8)`, `padding:10px 16px`, each cell `padding:9px 2px`.
        static let quadSpacing: CGFloat = 8
        static let quadRowPaddingV: CGFloat = 10
        static let quadCellPaddingV: CGFloat = 9
        static let quadCellPaddingH: CGFloat = 2

        // C9 · ActivityRow
        /// `padding:11px 13px`, `HStack(spacing:11)`; thumb 38×38.
        static let activityPaddingV: CGFloat = 11
        static let activityPaddingH: CGFloat = 13
        static let activitySpacing: CGFloat = 11
        static let activityThumb: CGFloat = 38
        /// Care leaf glyph inside the thumb — 12×12.
        static let activityLeaf: CGFloat = 12

        // C10 · IconTextRow
        /// `padding:12px 14px`, `HStack(spacing:12)`; tile 34×34.
        static let iconRowPaddingV: CGFloat = 12
        static let iconRowPaddingH: CGFloat = 14
        static let iconRowSpacing: CGFloat = 12
        static let iconRowTile: CGFloat = 34

        // C11 · StatCard
        /// `padding:9px 12px`; large variant `10px 13px`.
        static let statPaddingV: CGFloat = 9
        static let statPaddingH: CGFloat = 12
        static let statPaddingVLarge: CGFloat = 10
        static let statPaddingHLarge: CGFloat = 13
        /// Grid `gap:8px`.
        static let statGridGap: CGFloat = 8

        // C12 · MethodBadge
        /// `padding:1px 5px`; growth-log `1.5px 7px`; web `1.5px 6px`.
        static let methodBadgePaddingV: CGFloat = 1
        static let methodBadgePaddingH: CGFloat = 5
        static let methodBadgePaddingVLog: CGFloat = 1.5
        static let methodBadgePaddingHLog: CGFloat = 7

        // C13 · StatusBadge
        /// `padding:2px 8px` (compact) / `3px 9px` (default).
        static let statusBadgePaddingVCompact: CGFloat = 2
        static let statusBadgePaddingHCompact: CGFloat = 8
        static let statusBadgePaddingV: CGFloat = 3
        static let statusBadgePaddingH: CGFloat = 9

        // C14 · Callout
        /// `padding:11px 14px` (green) / `12px 15px` (gradient) / `13px 15px` (memorial, dashed, 19).
        static let calloutPaddingV: CGFloat = 11
        static let calloutPaddingH: CGFloat = 14
        static let calloutPaddingVGradient: CGFloat = 12
        static let calloutPaddingHGradient: CGFloat = 15
        static let calloutPaddingVLarge: CGFloat = 13
        static let calloutPaddingHLarge: CGFloat = 15

        // C15 · OptionalWell
        /// `padding:12px 14px` (05) / `13px 15px` (09).
        static let wellPaddingV: CGFloat = 12
        static let wellPaddingH: CGFloat = 14

        // C16 · BottomTabBar
        /// `padding:12px 10px 30px`.
        static let tabBarPaddingTop: CGFloat = 12
        static let tabBarPaddingH: CGFloat = 10
        static let tabBarPaddingBottom: CGFloat = 30
        /// Map icon — 22×22, 2px border, 6×6 dot, radius 6, `margin:0 auto 3px`.
        static let tabIconMap: CGFloat = 22
        static let tabIconMapDot: CGFloat = 6
        static let tabIconStroke: CGFloat = 2
        /// My Grove leaf — 16×16, `margin:3px auto 6px`.
        static let tabIconLeaf: CGFloat = 16
        /// Journal book — 18×20, spine 2px at `left:3px`, `margin:1px auto 4px`.
        static let tabIconBookWidth: CGFloat = 18
        static let tabIconBookHeight: CGFloat = 20
        static let tabIconBookSpineInset: CGFloat = 3
        /// You avatar — 20×20, `margin:1px auto 4px`.
        static let tabIconAvatar: CGFloat = 20
        /// Gap between glyph and label, from the icon margins above.
        static let tabIconLabelGap: CGFloat = 4

        // C17 · BottomSheet
        /// `padding:10px 18px 44px` (09, 10) / `22px 20px 44px` (15).
        static let sheetPaddingTop: CGFloat = 10
        static let sheetPaddingH: CGFloat = 18
        static let sheetPaddingTopAccount: CGFloat = 22
        static let sheetPaddingHAccount: CGFloat = 20
        /// Grabber 40×5, `margin:4px auto 14px`.
        static let grabberWidth: CGFloat = 40
        static let grabberHeight: CGFloat = 5
        static let grabberTop: CGFloat = 4
        static let grabberBottom: CGFloat = 14
        /// The full-width band at the top of a `.standard` sheet that drags the sheet down
        /// (ticket #175, RULINGS R42). **NOT SPECIFIED** by the mocks —
        /// they draw the grabber, and a grabber promises a drag; this is the size of the promise
        /// kept. Deep enough to cover the card's top padding plus the grabber row
        /// (10+4+5+14 = 33pt) and the title line under it, so the "bar at the top" the owner
        /// tried to pull is all handle; comfortably past the 44pt minimum touch target.
        static let sheetDragZone: CGFloat = 62

        // C18 · MapCanvas
        /// Street grid — `transparent 0 58px, grid 58px 64px` vertical;
        /// `transparent 0 66px, grid 66px 72px` horizontal.
        static let mapGridStepX: CGFloat = 64
        static let mapGridLineX: CGFloat = 6
        static let mapGridStepY: CGFloat = 72
        static let mapGridLineY: CGFloat = 6
        /// Ocean band — `width:13%`; beach strip — 7pt at `left:13%`.
        static let mapOceanFraction: CGFloat = 0.13
        static let mapBeachWidth: CGFloat = 7
        /// Park block — `left:22%; top:9%; width:74%; height:11%`, inset ring 1.5.
        static let mapParkLeftFraction: CGFloat = 0.22
        static let mapParkTopFraction: CGFloat = 0.09
        static let mapParkWidthFraction: CGFloat = 0.74
        static let mapParkHeightFraction: CGFloat = 0.11
        static let mapParkRingWidth: CGFloat = 1.5
        /// Named street bands — 9pt tall at `top:46%` and `top:72%`.
        static let mapStreetBandHeight: CGFloat = 9

        // C19 · MapPin
        static let pinStandard: CGFloat = 18
        static let pinRemoved: CGFloat = 16
        static let pinRing: CGFloat = 3
        static let pinRingCommunity: CGFloat = 2.5
        static let pinClusterLarge: CGFloat = 32
        static let pinClusterSmall: CGFloat = 30
        static let pinGPSHalo: CGFloat = 8
        static let pinRouteDone: CGFloat = 20
        static let pinRouteActive: CGFloat = 24
        static let pinRouteActiveHalo: CGFloat = 7
        /// Removed pin's centered bar — 8×2, radius 1.
        static let pinRemovedBarWidth: CGFloat = 8
        static let pinRemovedBarHeight: CGFloat = 2

        // C19 · the species slot glyph (task #80)
        //
        // **Fractions of the pin, not points.** The same mark is drawn at 18 pt inside a pin and at
        // `chipSpeciesSwatch` inside a legend chip, and a mark tuned in points for one is a smear on
        // the other. `MapSpeciesGlyph` multiplies these by whatever diameter it is given.
        //
        // 0.40 of an 18 pt pin is 7.2 pt of mark inside the 12 pt the 3 pt ring leaves — the mark
        // fills the dot without touching the ring, which is what keeps the ring reading as a ring.
        static let pinSpeciesGlyphRatio: CGFloat = 0.40
        /// Stroke of the cross and the standing bar — 0.105 of the pin is 1.9 pt at 18, which is the
        /// thinnest line that survives `ImageRenderer` at 3× and still reads as a bar rather than a
        /// hair.
        static let pinSpeciesGlyphStrokeRatio: CGFloat = 0.105
        /// The dot is drawn smaller than the glyph box it shares with the other three, because a
        /// filled circle at the full extent reads as "the pin has a hole in it" rather than as a mark.
        static let pinSpeciesDotRatio: CGFloat = 0.72
        /// An equilateral triangle is shorter than it is wide; 0.88 keeps its optical center on the
        /// pin's center instead of sitting a hair high the way a square-framed one does.
        static let pinSpeciesTriangleRatio: CGFloat = 0.88
        /// The legend chip's swatch — a pin, drawn small enough to sit inside a chip beside a name.
        static let chipSpeciesSwatch: CGFloat = 14
        /// Ring on the legend swatch, to the same 1:6 ratio the 18 pt pin's 3 pt ring keeps.
        static let chipSpeciesSwatchRing: CGFloat = 2.3
        /// Gap between a legend swatch and the name beside it.
        static let chipSpeciesSwatchGap: CGFloat = 5

        // C20 · SearchBar
        /// `padding:12px 18px`, `HStack(spacing:10)`, icon 16×16 stroke 1.8, `top:68px`.
        static let searchPaddingV: CGFloat = 12
        static let searchPaddingH: CGFloat = 18
        static let searchSpacing: CGFloat = 10
        static let searchIcon: CGFloat = 16
        static let searchIconStroke: CGFloat = 1.8
        static let searchTop: CGFloat = 68

        // C21 · LeafGlyph — the four drawn sizes.
        static let leafTabBar: CGFloat = 16
        static let leafFAB: CGFloat = 14
        static let leafCareThumb: CGFloat = 12
        static let leafBullet: CGFloat = 10

        // C23 · ChartCard
        /// `padding:14px 16px 10px` (11) / `14px 16px 8px` (13); header `margin-bottom:8px`.
        static let chartPaddingTop: CGFloat = 14
        static let chartPaddingH: CGFloat = 16
        static let chartPaddingBottom: CGFloat = 10
        static let chartPaddingBottomBars: CGFloat = 8
        static let chartHeaderBottom: CGFloat = 8
        /// Line chart viewBox `0 0 330 100`; gridlines y=28/50/72 from x=10 to x=300.
        static let chartLineViewWidth: CGFloat = 330
        static let chartLineViewHeight: CGFloat = 100
        static let chartGridlineY: [CGFloat] = [28, 50, 72]
        static let chartGridlineX0: CGFloat = 10
        static let chartGridlineX1: CGFloat = 300
        static let chartSeriesStroke: CGFloat = 2.5
        static let chartPointRadius: CGFloat = 5
        /// Bar chart viewBox `0 0 330 36`; 12 bars, width 18, `x = 10 + 26*i`.
        static let chartBarViewWidth: CGFloat = 330
        static let chartBarViewHeight: CGFloat = 36
        static let chartBarWidth: CGFloat = 18
        static let chartBarX0: CGFloat = 10
        static let chartBarStep: CGFloat = 26

        // C24 · AttentionCard
        /// `padding:14px 16px` (12) / `13px 14px` (17); border 1.5px.
        static let attentionPaddingV: CGFloat = 14
        static let attentionPaddingH: CGFloat = 16
        static let attentionPaddingVCompact: CGFloat = 13
        static let attentionPaddingHCompact: CGFloat = 14

        // C25 · Toggle
        /// Track 44×26, knob 20×20 inset 3.
        static let toggleTrackWidth: CGFloat = 44
        static let toggleTrackHeight: CGFloat = 26
        static let toggleKnob: CGFloat = 20
        static let toggleKnobInset: CGFloat = 3

        // C26 · AvatarStack
        /// 24×24 circles, 2px ring, `-8px` overlap.
        static let avatar: CGFloat = 24
        static let avatarRingWidth: CGFloat = 2
        static let avatarOverlap: CGFloat = 8

        // C27 · ProgressRing
        /// 74×74 outer, 54×54 inner disc.
        static let progressRing: CGFloat = 74
        static let progressRingInner: CGFloat = 54

        // C28 · ConfidenceBar
        /// Track 4pt tall, radius 2, `max-width:150px`, `margin-top:7px`.
        static let confidenceHeight: CGFloat = 4
        static let confidenceRadius: CGFloat = 2
        static let confidenceMaxWidth: CGFloat = 150
        static let confidenceTop: CGFloat = 7

        // C29 · SpeciesTile
        /// `padding:9px`, grid `gap:9px`.
        static let speciesTilePadding: CGFloat = 9
        static let speciesTileGap: CGFloat = 9

        // C4 · leading status dot — the 8×8 `#3577C9` dot on 02's `GPS ±9 m` chip.
        static let chipLeadingDot: CGFloat = 8

        // C17 · skeleton behind the 09/10 sheets
        static let skeletonHero: CGFloat = 150
        static let skeletonBarLarge: CGFloat = 24
        static let skeletonBarSmall: CGFloat = 14
        static let skeletonBlock: CGFloat = 52
        static let skeletonBarLargeFraction: CGFloat = 0.64
        static let skeletonBarSmallFraction: CGFloat = 0.44

        // C19 · route-done check — a 10×8 glyph at stroke 2.2.
        static let pinRouteCheckWidth: CGFloat = 10
        static let pinRouteCheckHeight: CGFloat = 8
        static let pinRouteCheckStroke: CGFloat = 2.2

        // C22 · ThumbnailGradient — the drawn thumb sizes.
        static let thumb76: CGFloat = 76
        static let thumb72: CGFloat = 72
        static let thumb60: CGFloat = 60
        static let thumb58: CGFloat = 58
        static let thumb44: CGFloat = 44
        static let thumb38: CGFloat = 38
        static let thumb34: CGFloat = 34
    }
}
