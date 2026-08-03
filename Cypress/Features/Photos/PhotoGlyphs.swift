//
//  PhotoGlyphs.swift
//  Cypress — Features/Photos
//
//  The three marks screens 20 and the photo viewer draw: a trash can, a thumb, and a ✕.
//
//  **All three were `Image(systemName:)` until ticket #130.** The app's rule is that every glyph in
//  it is drawn here rather than borrowed — the rule is stated in `ShareDestinationGlyph`, and the
//  ruling that made it true again is `docs/rulings-pending/drawn-glyphs.md`. Read that before adding
//  a mark or reaching for a symbol; `DrawnGlyphGuardTests` is what goes red if anybody does.
//
//  Local to this folder rather than in `DesignSystem/Components`: no screen outside Photos uses
//  them, and C1–C30 is a closed catalog. Same arrangement as `ShareDestinationGlyph` and 14's
//  camera glyph, both of which say so in the same words.
//
//  ── Geometry ────────────────────────────────────────────────────────────────────────────────────
//  Every mark is authored in a **24×24 box** at **stroke 1.8**, which is the stroke every other
//  hand-drawn mark in this app uses, and scaled to whatever frame it is given. The stroke scales
//  with the box (`stroke(for:)`) rather than staying at 1.8 — a 1.8 pt line in a 17 pt frame is the
//  weight of a 2.5 pt line in the 24 pt box these were drawn in, and reads as a different mark.
//
//  **NOT SPECIFIED.** SCREENS.md draws no photo browser and no viewer, so none of these three marks
//  is transcribed from anything; the geometry below is this file's, and nothing further is claimed
//  for it.
//

import SwiftUI

// MARK: - Shared metrics

enum PhotoGlyphMetrics {
    /// The box every mark below is authored in.
    static let box: CGFloat = 24
    /// The stroke, in that box. The app's own line weight for a drawn mark.
    static let strokeInBox: CGFloat = 1.8

    /// The stroke to draw a `side`-wide mark with, so the line keeps its proportion to the mark.
    static func stroke(for side: CGFloat) -> CGFloat {
        strokeInBox * side / box
    }

    static func style(for side: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: stroke(for: side), lineCap: .round, lineJoin: .round)
    }
}

/// Scales a point from the 24×24 authoring box into `rect`.
private func photoGlyphPoint(_ x: CGFloat, _ y: CGFloat, in rect: CGRect) -> CGPoint {
    let s = min(rect.width, rect.height) / PhotoGlyphMetrics.box
    return CGPoint(x: rect.minX + x * s, y: rect.minY + y * s)
}

// MARK: - Trash

/// The delete mark: a lid with a handle above it, a tapered can, and two ribs.
///
/// Four subpaths, each opened with its own `move(to:)`. That is not a style preference — E163 is
/// the errata about two marks in this app that appended a second stroke to a first one's current
/// point and drew a chord across themselves. Every mark in this file is written to be read for that
/// mistake specifically.
struct PhotoTrashGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { photoGlyphPoint(x, y, in: rect) }
        var path = Path()

        // The handle, a bracket standing on the lid.
        path.move(to: p(9.5, 6.5))
        path.addLine(to: p(9.5, 4))
        path.addLine(to: p(14.5, 4))
        path.addLine(to: p(14.5, 6.5))

        // The lid.
        path.move(to: p(4, 6.5))
        path.addLine(to: p(20, 6.5))

        // The can: two walls tapering in, joined by a floor with rounded corners.
        path.move(to: p(6.2, 6.5))
        path.addLine(to: p(7.1, 20.2))
        path.addQuadCurve(to: p(8, 21), control: p(7.15, 21))
        path.addLine(to: p(16, 21))
        path.addQuadCurve(to: p(16.9, 20.2), control: p(16.85, 21))
        path.addLine(to: p(17.8, 6.5))

        // Two ribs, each leaning with the wall nearest it.
        path.move(to: p(10.4, 9.8))
        path.addLine(to: p(10.8, 17.6))
        path.move(to: p(13.6, 9.8))
        path.addLine(to: p(13.2, 17.6))

        return path
    }
}

// MARK: - Thumb

/// The vote mark: a cuff and a closed hand outline with the thumb raised.
///
/// **One shape serves all four states.** A downvote is this mark turned a half turn, and the
/// reader's own vote fills it instead of stroking it. That is the whole reason there is one path
/// here and not four: the two directions cannot drift apart, and the filled state cannot disagree
/// with the outline, because in each case there is only one set of numbers.
///
/// The hand is a **single closed subpath** and the cuff is a second one, disjoint from it. Filling
/// the two together is correct under the nonzero winding rule — they do not overlap, so neither
/// punches a hole in the other.
struct PhotoThumbGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { photoGlyphPoint(x, y, in: rect) }
        let s = min(rect.width, rect.height) / PhotoGlyphMetrics.box
        var path = Path()

        // The cuff. Clear of the palm by 1.2 units in the box, so the two do not merge at 17 pt
        // once the stroke has taken 0.9 off each side of that gap.
        path.addRoundedRect(
            in: CGRect(x: rect.minX + 2 * s, y: rect.minY + 11.4 * s, width: 4.2 * s, height: 9.4 * s),
            cornerSize: CGSize(width: 1.3 * s, height: 1.3 * s),
            style: .continuous
        )

        // The hand: along the bottom, up the knuckles, back along the palm's top to the web, up
        // and over the thumb, and down its near side into the palm's left edge, which `closeSubpath`
        // draws.
        path.move(to: p(9.2, 20.8))
        path.addLine(to: p(18, 20.8))
        path.addCurve(to: p(20.6, 18.2), control1: p(19.5, 20.8), control2: p(20.6, 19.7))
        path.addLine(to: p(20.6, 13.9))
        path.addCurve(to: p(18, 11.3), control1: p(20.6, 12.4), control2: p(19.5, 11.3))
        path.addLine(to: p(13.4, 11.3))
        path.addCurve(to: p(13.8, 6.6), control1: p(13.4, 9.6), control2: p(13.8, 8.4))
        path.addCurve(to: p(11.4, 3.2), control1: p(13.8, 4.6), control2: p(12.8, 3.2))
        path.addCurve(to: p(9.6, 5.8), control1: p(10.2, 3.2), control2: p(9.6, 4.2))
        path.addLine(to: p(9.6, 8.4))
        path.addCurve(to: p(9.2, 11.9), control1: p(9.6, 10), control2: p(9.2, 10.6))
        path.closeSubpath()

        return path
    }
}

/// A thumb in one of its four appearances, at `side` points.
struct PhotoThumbMark: View {
    let appearance: TreePhotosPresentation.ThumbAppearance
    let side: CGFloat
    let tint: Color

    var body: some View {
        Group {
            if appearance.isFilled {
                PhotoThumbGlyph().fill(tint)
            } else {
                PhotoThumbGlyph().stroke(tint, style: PhotoGlyphMetrics.style(for: side))
            }
        }
        .frame(width: side, height: side)
        .rotationEffect(.degrees(appearance.halfTurn ? 180 : 0))
        .accessibilityHidden(true)
    }
}

// MARK: - Close

/// The viewer's ✕.
///
/// The same construction as `VisitCloseGlyph` — two lines corner to corner — and a second copy of
/// it on purpose, because glyphs in this app live beside the screens that use them and neither
/// folder should have to import the other's. Inset inside the 24 box rather than run to its edges,
/// because this one sits in a 40 pt circle and needs the margin the camera's full-bleed ✕ does not.
struct PhotoCloseGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { photoGlyphPoint(x, y, in: rect) }
        var path = Path()
        path.move(to: p(6.2, 6.2))
        path.addLine(to: p(17.8, 17.8))
        path.move(to: p(17.8, 6.2))
        path.addLine(to: p(6.2, 17.8))
        return path
    }
}
