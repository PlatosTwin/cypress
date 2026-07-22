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
            // Below the inner arc rather than inside it: at 24pt the two touch otherwise and the
            // mark reads as a wi-fi glyph with a thick arc rather than as arcs over a dot.
            Circle()
                .fill(tint)
                .frame(width: Self.side * 0.14, height: Self.side * 0.14)
                .offset(y: Self.side * 0.30)
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

/// Two concentric arcs opening upward over a dot — the AirDrop mark's shape, drawn in a 24×24 box.
private struct ShareAirDropArcs: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let centre = CGPoint(x: rect.minX + 12 * s, y: rect.minY + 17.5 * s)
        var path = Path()
        for radius in [6.0, 10.5] {
            path.addArc(
                center: centre,
                radius: radius * s,
                startAngle: .degrees(215),
                endAngle: .degrees(325),
                clockwise: false
            )
        }
        return path
    }
}

/// Two rounded link halves overlapping at the centre, drawn in a 24×24 box.
private struct ShareChainLink: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        var path = Path()
        // Upper-right half: a capsule end that stops at the middle bar.
        path.move(to: CGPoint(x: 13 * s, y: 8 * s))
        path.addLine(to: CGPoint(x: 15.5 * s, y: 5.5 * s))
        path.addArc(
            center: CGPoint(x: 18 * s, y: 8 * s),
            radius: 3.54 * s,
            startAngle: .degrees(225),
            endAngle: .degrees(-45),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: 16 * s, y: 11 * s))
        // Lower-left half, the same shape rotated a half turn.
        path.move(to: CGPoint(x: 11 * s, y: 16 * s))
        path.addLine(to: CGPoint(x: 8.5 * s, y: 18.5 * s))
        path.addArc(
            center: CGPoint(x: 6 * s, y: 16 * s),
            radius: 3.54 * s,
            startAngle: .degrees(45),
            endAngle: .degrees(135),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: 8 * s, y: 13 * s))
        // The bar that joins them.
        path.move(to: CGPoint(x: 9.5 * s, y: 14.5 * s))
        path.addLine(to: CGPoint(x: 14.5 * s, y: 9.5 * s))
        return path.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}
