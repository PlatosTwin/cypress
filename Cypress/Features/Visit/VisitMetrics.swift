//
//  VisitMetrics.swift
//  Cypress — Features/Visit
//
//  The geometry and the handful of colours that SCREENS.md states for screens 02, 04 and 18 but
//  that `CypressSpacing.Component` / `CypressColor` do not carry, because they are used on exactly
//  one screen and the token files transcribe §1 and §2 (the catalogue), not §3 (the screens).
//
//  ARCHITECTURE §6's rule is "a literal in `Features/` is a bug" — the point of the rule is that a
//  value has one home and a spec change has one place to land. That is what this file is: every
//  number below is quoted from its SCREENS.md line, and no view in this folder contains an
//  unexplained constant. Anything the design system *does* carry is used from there
//  (`CypressColor.cameraFramingCorner`, `CypressRadius.framingCorner`, `CypressGradient.camera*`,
//  `CypressSpacing.Component.*`) and is deliberately not re-declared here.
//

import SwiftUI

enum VisitMetrics {

    // MARK: - 02 · What tree is this?

    enum Identify {
        /// Status chips row — `padding:8px 18px 14px`, `gap:8px`.
        static let statusRowTop: CGFloat = 8
        static let statusRowBottom: CGFloat = 14
        static let statusRowGap: CGFloat = 8

        /// Candidate card — `padding:14px`, `gap:14px`.
        static let cardPadding: CGFloat = 14
        static let cardSpacing: CGFloat = 14
        /// Selected card border `2px solid #2F6B4F`; idle `1px solid #E3E8D9`.
        static let selectedBorderWidth: CGFloat = 2
        /// Name `margin-top:1px` under the eyebrow; tell `margin-top:6px` (top) / `3px` (rows).
        static let nameTop: CGFloat = 1
        static let tellTopSelected: CGFloat = 6
        static let tellTopIdle: CGFloat = 3
        /// Text column gap inside a card. Not stated; the drawn rhythm is a 2pt lead between the
        /// name and the Latin line, which is what a zero-spacing VStack plus the two documented
        /// margins above produces.
        static let cardTextSpacing: CGFloat = 2

        /// Footer CTA — `padding:14px 16px 40px`.
        static let footerTop: CGFloat = 14

        /// The D6 confirmation bar is **NOT SPECIFIED** in SCREENS.md; D6 mandates the step. It is
        /// built from documented pieces only — C6 at its standard size over the same 16pt gutter,
        /// with the card list's own 10pt gap above it.
        static let confirmBarTop = CypressSpacing.gapCandidates
    }

    // MARK: - The community add (ERRATA E127)

    enum AddTree {
        /// **Not a spec value** — the screen has no mock (see `VisitAddTreeView`). Screen 14 §2's
        /// well is 170pt, which is a caption's height; this one holds a viewfinder and then the
        /// photograph taken through it, so it is the 4:3 frame that photograph will be, at the
        /// gutter's width on the drawn 393pt frame.
        static let wellHeight: CGFloat = 268
    }

    // MARK: - Moving the pin

    /// The two numbers `VisitPinAdjustView` owns that no component and no rule already names. The
    /// *rules* — the 75 m radius, the 5 m nudge — are in `VisitPinAdjust`, because they are the
    /// screen's argument rather than its geometry and the model enforces them without drawing
    /// anything.
    enum PinAdjust {
        /// How much of the city the map opens on, in metres across, when the pin screen appears.
        ///
        /// **Not a spec value** — the screen has no mock. 200 m rather than `MapLayout
        /// .defaultSpanMetres`' 120: the pin may travel 75 m in any direction, which is a 150 m
        /// circle, and a reader who cannot see the whole area the pin is allowed into has to zoom out
        /// before they can aim. The 50 m of margin on top is what keeps the boundary off the bezel.
        static let openingSpanM: Double = 200

        /// The pin's opacity once it is past the limit.
        ///
        /// Faded rather than recoloured: Signal Amber means "this tree needs something" (§1.1) and a
        /// pin that is merely too far from the reader is not that. 0.4 is far enough down to read as
        /// "this is not live" at a glance without the pin disappearing off a busy basemap — the reader
        /// still has to be able to find it to bring it back.
        static let beyondLimitOpacity: Double = 0.4

        /// Below this many metres, the camera has not moved.
        ///
        /// `onMapCameraChange(.continuous)` fires on layout, on the settling frames of a
        /// programmatic move, and on every frame of a pan, and only the last of those means the
        /// reader is aiming. 10 cm is far under one point at any zoom this screen opens at, so it
        /// separates a pan from a redraw without needing to know which is which.
        static let stillnessM: Double = 0.1
    }

    // MARK: - 04 · Visit (dark camera)

    enum Camera {
        /// Guidance pill — `top:70px`, `padding:8px 16px`, blur 6.
        static let guidancePillTop: CGFloat = 70
        static let guidancePillPaddingV: CGFloat = 8
        static let guidancePillPaddingH: CGFloat = 16
        static let guidancePillBlur: CGFloat = 6

        /// Framing corners — four 32×32 L-brackets, `3px`, at `top:118px` / `bottom:120px`,
        /// inset 26px from each edge.
        static let framingCornerSide: CGFloat = 32
        static let framingCornerStroke: CGFloat = 3
        static let framingCornerTop: CGFloat = 118
        static let framingCornerBottom: CGFloat = 120
        static let framingCornerInset: CGFloat = 26

        /// Shot-type chips — `bottom:150px`, `gap:8px`.
        static let shotTypeBottom: CGFloat = 150
        static let shotTypeGap: CGFloat = 8

        /// The tick on a framing this session has already photographed (ERRATA E150). **NOT SPECIFIED**
        /// — SCREENS 04 draws the three chips with no captured state, because when it was drawn a visit
        /// held one photograph and the chips were three labels for it. Sized off screen 05's check
        /// circle, which is the app's existing "this one is chosen" mark, at the smaller end because it
        /// sits on the corner of a chip rather than in a row of its own.
        static let capturedMark: CGFloat = 16
        static let capturedMarkGlyph: CGFloat = 8
        static let capturedMarkStroke: CGFloat = 2
        /// Half the mark, so it straddles the chip's corner rather than being clipped by it.
        static let capturedMarkInset: CGFloat = 5

        /// Shutter — 68×68 circle at `bottom:34px`, `box-shadow:0 0 0 6px rgba(255,255,255,.35)`
        /// (a solid ring, not a blur).
        static let shutterDiameter: CGFloat = 68
        static let shutterBottom: CGFloat = 34
        static let shutterRingWidth: CGFloat = 6

        /// The gap between the chip row and the shutter, **derived** so that the chips land on
        /// `shotTypeBottom` when the shutter block is at its specified size and nothing else is in it.
        ///
        /// The two used to be independent bottom-anchored overlays at `bottom:150` and `bottom:34`,
        /// which is fine at the size the mock was drawn at and is a collision at every larger one: the
        /// camera-denied fallback sentence lives in the shutter block (BUILD-PLAN §9 requires that
        /// state), it grows to two and three lines as the type ramp climbs, and it grew straight up
        /// through the chip row. Seen at AX1 on a simulator, where the camera is always unavailable, so
        /// the fallback sentence is always there. One stack cannot overlap itself: the chips get pushed
        /// up instead, and at the specified sizes they do not move at all.
        ///
        /// **The ring is deliberately not in this sum.** `VisitShutterButton` draws it as an `.overlay`
        /// on a 68 pt frame, and an overlay does not enlarge what it is over — so the shutter block's
        /// *layout* height is 68 and the ring hangs 6 pt outside it in both directions. Subtracting it
        /// would move the chips 12 pt off the mock in the one state the mock actually draws.
        static var shotTypeGapAboveShutter: CGFloat {
            shotTypeBottom - shutterBottom - shutterDiameter
        }

        /// Ghost caption — `bottom:44px; left:34px`, `max-width:80px`, `line-height:1.4`.
        static let ghostCaptionBottom: CGFloat = 44
        static let ghostCaptionLeading: CGFloat = 34
        static let ghostCaptionMaxWidth: CGFloat = 80
        static let ghostCaptionLineSpacing: CGFloat = 4.2

        /// "the last full-tree photo at **30 % opacity**" — the one number the whole screen exists
        /// for (PRODUCT §5 M4, SCREENS 04).
        static let ghostOpacity: Double = 0.30

        /// Tray — `padding:16px 16px 40px`, `VStack(spacing:11)`.
        static let trayPadding: CGFloat = 16
        static let trayBottom: CGFloat = 40
        static let traySpacing: CGFloat = 11

        /// Note field — `padding:12px 14px`, radius 12.
        static let notePaddingV: CGFloat = 12
        static let notePaddingH: CGFloat = 14
        /// Two lines of 14.5pt copy plus the padding above — the field is drawn one line tall and
        /// grows; this is its resting height so the tray does not jump on first keystroke.
        static let noteMinHeight: CGFloat = 46

        /// Phenology chip row `gap:8px`; offline line `gap:8px` with an 8×8 dot.
        static let chipGap: CGFloat = 8
        static let offlineDot: CGFloat = 8

        /// Close button — **NOT SPECIFIED** as a size in §3; the prototype puts a ✕ top-left. It is
        /// drawn at the C1 back-circle size so it is already at the 44pt tap minimum.
        static let closeButton = CypressSpacing.Component.backCircle
        static let closeGlyph: CGFloat = 15
        static let closeStroke: CGFloat = 2.2
        static let closeTop: CGFloat = 12
        static let closeLeading: CGFloat = 12
    }

    // MARK: - 18 · Next tree

    enum Saved {
        /// Success block — `padding:22px 0 6px`; 66×66 circle; check 28×22 at stroke 4.
        static let successTop: CGFloat = 22
        static let successBottom: CGFloat = 6
        static let successCircle: CGFloat = 66
        static let successCheckWidth: CGFloat = 28
        static let successCheckHeight: CGFloat = 22
        static let successCheckStroke: CGFloat = 4
        /// Title `margin-top:10px`, subtitle `margin-top:2px`.
        static let successTitleTop: CGFloat = 10
        static let successSubtitleTop: CGFloat = 2

        /// Mini route map — `margin:14px 16px`, height 190, radius 18.
        static let routeMapTop: CGFloat = 14
        static let routeMapHeight: CGFloat = 190
        /// Grid — `transparent 0 52px, #F4F1E2 52px 57px` and its 58/63 sibling.
        static let routeGridStepX: CGFloat = 57
        static let routeGridLineX: CGFloat = 5
        static let routeGridStepY: CGFloat = 63
        static let routeGridLineY: CGFloat = 5
        /// Water band on the right — `width:8%`, `opacity:.75`.
        static let routeWaterFraction: CGFloat = 0.08
        static let routeWaterOpacity: Double = 0.75
        /// Corner label — `right:16px; bottom:10px`.
        static let routeLabelTrailing: CGFloat = 16
        static let routeLabelBottom: CGFloat = 10

        /// Secondary CTA `padding:10px 16px 0`; footnote `padding:16px 24px 36px`.
        static let secondaryTop: CGFloat = 10
        static let footnoteTop: CGFloat = 16
        static let footnoteHorizontal: CGFloat = 24
        static let footnoteLineSpacing: CGFloat = 6.5
    }
}

// MARK: - Screen-local colours

/// The three fills SCREENS.md states inside screen 04's body and screen 18's route map that §1/§2
/// do not tokenise. Same convention as `CypressColor`: hex quoted from the spec line, one home.
///
/// Everything else on these screens resolves from `CypressColor` — including the whole forced-dark
/// palette (`CypressColor.Dark.*`) and `cameraFramingCorner`.
enum VisitColor {
    /// 04 guidance pill fill — `rgba(6,10,7,.62)`. `shotTypeOffFill` is the same hex at `.55`; the
    /// pill is the darker of the two and the spec states both, so both exist.
    static let guidancePillFill = Color(cypressHex: 0x060A07, alpha: 0.62)
    /// 04 guidance pill text — `#DFE8D8`.
    static let guidancePillText = Color(cypressHex: 0xDFE8D8)
    /// 04 ghost caption — `rgba(228,235,226,.75)`.
    static let ghostCaption = Color(cypressHex: 0xE4EBE2, alpha: 0.75)
    /// 04 shutter ring — `rgba(255,255,255,.35)`.
    static let shutterRing = Color(cypressHex: 0xFFFFFF, alpha: 0.35)
    /// 04 shutter fill — `#fff`.
    static let shutterFill = Color(cypressHex: 0xFFFFFF)
    /// 18 route map water band — `#B5CFD2`.
    static let routeWater = Color(cypressHex: 0xB5CFD2)
    /// 04 close button fill — **NOT SPECIFIED**; the C2 hero back button's dark counterpart
    /// (`rgba(24,37,29,.92)`) is the nearest documented control on a photographic surface.
    static let cameraCloseFill = Color(cypressHex: 0x18251D, alpha: 0.92)
}
