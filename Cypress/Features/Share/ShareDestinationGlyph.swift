//
//  ShareDestinationGlyph.swift
//  Cypress — Features/Share
//
//  The four 24×24 marks in screen 10 §4's icon wells.
//
//  SCREENS.md gives them by description rather than by path — "`Messages` (speech bubble),
//  `Instagram` (rounded square + circle + dot), `AirDrop` (arcs + dot), `Copy link` (chain link)" —
//  and fixes only what they are drawn with: `24×24 SVG stroke/fill #3C4A3E width 1.8`. Everything
//  else about their geometry is **NOT SPECIFIED**, so these are drawn to that description at that
//  stroke and nothing further is claimed for them.
//
//  Local to this folder rather than in `DesignSystem/Components`: no other screen in SCREENS.md
//  uses them, and C1–C30 is a closed catalogue. Same arrangement as 14's camera glyph.
//
//  No SF Symbols. The design system is explicit that every icon in the app is hand-drawn and there
//  is no icon font (SCREENS.md §2 C16), and the Apple glyphs would put three vendors' marks on one
//  row of a screen that draws its own.
//

import SwiftUI

struct ShareDestinationGlyph: View {

    let destination: ShareDestination

    /// `24×24`, `width 1.8` — 10 §4.
    static let side: CGFloat = 24
    static let stroke: CGFloat = 1.8

    var body: some View {
        Group {
            switch destination {
            case .messages: messages
            case .instagram: instagram
            case .airDrop: airDrop
            case .copyLink: copyLink
            }
        }
        .frame(width: Self.side, height: Self.side)
        .accessibilityHidden(true)
    }

    private var strokeStyle: StrokeStyle {
        StrokeStyle(lineWidth: Self.stroke, lineCap: .round, lineJoin: .round)
    }

    private var tint: Color { CypressColor.textBody }

    // MARK: The four marks

    private var messages: some View {
        ShareSpeechBubble().stroke(tint, style: strokeStyle)
    }

    private var instagram: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Self.side * 0.28, style: .continuous)
                .strokeBorder(tint, lineWidth: Self.stroke)
                .frame(width: Self.side * 0.79, height: Self.side * 0.79)
            Circle()
                .strokeBorder(tint, lineWidth: Self.stroke)
                .frame(width: Self.side * 0.36, height: Self.side * 0.36)
            Circle()
                .fill(tint)
                .frame(width: Self.side * 0.085, height: Self.side * 0.085)
                .offset(x: Self.side * 0.21, y: -Self.side * 0.21)
        }
    }

    private var airDrop: some View {
        ZStack {
            ShareAirDropArcs().stroke(tint, style: strokeStyle)
            // **At the arcs' own centre of curvature**, which is the thing that makes two arcs and a
            // dot read as one mark rather than as three marks sharing a box.
            //
            // This used to be pushed `0.30 · side` *below* the arcs, on the stated reasoning that at
            // 24pt a centred dot touches the inner arc. It does not, and never did: the inner arc's
            // nearest point to that centre is `radius − stroke/2 = 5.1pt` away and the dot's own
            // radius is under 2. What actually touched was the **chord** `ShareAirDropArcs` was
            // drawing between its two arcs — see that shape — which crossed the box 4.4pt above the
            // centre and merged with the inner arc into a blob. The dot was moved to escape a
            // defect that was somewhere else, and the mark ended up with a detached full stop under
            // it. See docs/errata-pending/share-glyphs-and-readings.md.
            Circle()
                .fill(tint)
                .frame(width: Self.side * 0.16, height: Self.side * 0.16)
                .offset(y: Self.side * ShareAirDropArcs.centreOffsetFraction)
        }
    }

    private var copyLink: some View {
        ShareChainLink().stroke(tint, style: strokeStyle)
    }
}

// MARK: - Shapes

/// A rounded speech bubble with a tail at the lower left, drawn in a 24×24 box.
private struct ShareSpeechBubble: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        var path = Path()
        let body = CGRect(x: 3 * s, y: 4 * s, width: 18 * s, height: 13 * s)
        path.addRoundedRect(
            in: body,
            cornerSize: CGSize(width: 5 * s, height: 5 * s),
            style: .continuous
        )
        // The tail: a short flick down from the bubble's lower-left corner.
        path.move(to: CGPoint(x: 8.5 * s, y: 17 * s))
        path.addLine(to: CGPoint(x: 7 * s, y: 21 * s))
        path.addLine(to: CGPoint(x: 12 * s, y: 17 * s))
        return path.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

/// Two concentric arcs over a dot — the AirDrop mark's shape, drawn in a 24×24 box.
///
/// SCREENS.md 10 §4 names this one `AirDrop` (arcs + dot), so a dot is what it has. Apple's own
/// AirDrop mark puts an upward triangle under the arcs; substituting one here would be changing a
/// transcribed description rather than drawing it, which is the design's call and not this file's.
private struct ShareAirDropArcs: Shape {

    /// The centre of curvature both arcs share, in the 24×24 box. The dot goes here too.
    static let centre = CGPoint(x: 12.0, y: 16.5)
    static let radii: [CGFloat] = [6, 10]
    /// A 120° fan, wide enough that the inner arc reads as an arc and not as a dash.
    static let sweep = (start: 210.0, end: 330.0)

    /// `centre` as an offset from the middle of the box, in units of the box's side — what a
    /// `.offset(y:)` on a centred `Circle` needs to land the dot on `centre`.
    static let centreOffsetFraction: CGFloat = (centre.y - 12) / 24

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let centre = CGPoint(
            x: rect.minX + Self.centre.x * s,
            y: rect.minY + Self.centre.y * s
        )
        let startRadians = CGFloat(Angle.degrees(Self.sweep.start).radians)
        var path = Path()
        for radius in Self.radii {
            // **`move(to:)` first, and this is the whole of the defect this shape had.** `addArc`
            // appends to the current subpath, so the second call joined the first arc's end to the
            // second arc's start with a straight line — a chord clean across the mark, which at
            // 1.8pt merged with the inner arc and drew a filled-looking blob. Two arcs are two
            // subpaths.
            path.move(
                to: CGPoint(
                    x: centre.x + radius * s * cos(startRadians),
                    y: centre.y + radius * s * sin(startRadians)
                )
            )
            path.addArc(
                center: centre,
                radius: radius * s,
                startAngle: .degrees(Self.sweep.start),
                endAngle: .degrees(Self.sweep.end),
                clockwise: false
            )
        }
        return path
    }
}

/// Two rounded link halves overlapping at the centre, drawn in a 24×24 box.
///
/// ── The construction, because the numbers below are not arbitrary ──────────────────────────
/// Both halves are the same capsule end — a **half turn** of a `3.54pt` cap plus two straight arms
/// of the same length — sitting on the box's leading diagonal, one rotated 180° about the centre
/// `(12, 12)`. The cap centres are `(18, 8)` and `(6, 16)`, each `3.54pt` off the diagonal on
/// opposite sides, so the two halves read as two rings hooked through each other rather than as one
/// ring cut in half. The bar runs *on* the diagonal, between the two inner arms, and joins them.
///
/// ── What was wrong (ERRATA — see docs/errata-pending/share-glyphs-and-readings.md) ─────────
/// Each cap swept **90° instead of 180°**, so it stopped at the top of its circle instead of at the
/// far side of it, and the arm that followed was then drawn from that wrong point back across the
/// mark. The result was two lopsided hooks with a stroke cutting through each, which at 24pt reads
/// as a paintbrush. The arms' own endpoints were right all along; only the sweep and the point the
/// second arm started from were not.
private struct ShareChainLink: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        var path = Path()
        // Upper-right half: an arm in, a half turn, an arm back out.
        path.move(to: CGPoint(x: 13 * s, y: 8 * s))
        path.addLine(to: CGPoint(x: 15.5 * s, y: 5.5 * s))
        path.addArc(
            center: CGPoint(x: 18 * s, y: 8 * s),
            radius: 3.54 * s,
            startAngle: .degrees(225),
            endAngle: .degrees(45),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: 18 * s, y: 13 * s))
        // Lower-left half, the same shape rotated a half turn about (12, 12).
        path.move(to: CGPoint(x: 11 * s, y: 16 * s))
        path.addLine(to: CGPoint(x: 8.5 * s, y: 18.5 * s))
        path.addArc(
            center: CGPoint(x: 6 * s, y: 16 * s),
            radius: 3.54 * s,
            startAngle: .degrees(45),
            endAngle: .degrees(225),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: 6 * s, y: 11 * s))
        // The bar that joins them, on the diagonal between the two inner arms.
        path.move(to: CGPoint(x: 9.5 * s, y: 14.5 * s))
        path.addLine(to: CGPoint(x: 14.5 * s, y: 9.5 * s))
        return path.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}
