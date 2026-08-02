//
//  ShareDestinationGlyph.swift
//  Cypress — Features/Share
//
//  The three 24×24 marks in screen 10 §4's icon wells.
//
//  SCREENS.md drew four by description — "`Messages` (speech bubble), `Instagram` (rounded square
//  + circle + dot), `AirDrop` (arcs + dot), `Copy link` (chain link)" — and fixed only what they
//  are drawn with: `24×24 SVG stroke/fill #3C4A3E width 1.8`. The row is now three (ticket #146,
//  RULINGS R39): Instagram and AirDrop are gone, and `Share…`
//  (tray + up arrow, the platform's own idiom for "hand this off") is new, drawn to the same
//  stroke. Everything else about the geometry is **NOT SPECIFIED**, so nothing further is claimed
//  for it.
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
            case .copyLink: copyLink
            case .system: system
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

    private var copyLink: some View {
        ShareChainLink().stroke(tint, style: strokeStyle)
    }

    private var system: some View {
        ShareTrayArrow().stroke(tint, style: strokeStyle)
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

/// A tray with an arrow rising out of it — the `Share…` mark, drawn in a 24×24 box.
///
/// Three subpaths: the tray (an open-topped rectangle), the arrow's shaft, and its head. The
/// tray has no top edge — the shaft descends 3pt past the rim into that opening, which is what
/// makes the two read as one hand-off rather than as an arrow floating over a box.
private struct ShareTrayArrow: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        var path = Path()
        // The tray: down the left wall, across the floor, up the right wall.
        path.move(to: CGPoint(x: 5 * s, y: 11 * s))
        path.addLine(to: CGPoint(x: 5 * s, y: 20 * s))
        path.addLine(to: CGPoint(x: 19 * s, y: 20 * s))
        path.addLine(to: CGPoint(x: 19 * s, y: 11 * s))
        // The shaft, from the tray's mouth up and out of the box's middle.
        path.move(to: CGPoint(x: 12 * s, y: 14 * s))
        path.addLine(to: CGPoint(x: 12 * s, y: 3.5 * s))
        // The head.
        path.move(to: CGPoint(x: 8.5 * s, y: 7 * s))
        path.addLine(to: CGPoint(x: 12 * s, y: 3.5 * s))
        path.addLine(to: CGPoint(x: 15.5 * s, y: 7 * s))
        return path.offsetBy(dx: rect.minX, dy: rect.minY)
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
/// ── What was wrong (ERRATA E163) ─────────
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
