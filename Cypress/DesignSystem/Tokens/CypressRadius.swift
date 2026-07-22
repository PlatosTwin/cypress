//
//  CypressRadius.swift
//  Cypress — DesignSystem/Tokens
//
//  Source of truth: docs/distilled/SCREENS.md §1.4 (radii), §1.7 (device frame).
//  Straight transcription — every value below is a cell in that table.
//

import SwiftUI

enum CypressRadius {

    /// `radius.pill` `999px` — chips, filter chips, search bar, FAB, status pills.
    static let pill: CGFloat = 999

    /// `radius.sheet` `26px 26px 0 0` — bottom sheets (09, 10, 15). **Top corners only.**
    /// Use `CypressSheetShape` or `.cypressSheetCorners()`; a plain `cornerRadius` is wrong here.
    static let sheet: CGFloat = 26

    /// `radius.device` `48px` — iOS frame screen corner (from `ios-frame.jsx`).
    /// SCREENS.md §1.7: "Do not ship the frames." Kept for the token gallery and for any
    /// screenshot/share-card rendering that reproduces the device corner.
    static let device: CGFloat = 48

    /// `radius.card.lg` `18px` — 01 tree card, 02 candidate cards, 10 share preview,
    /// 14 photo well, 18 route map.
    static let cardLg: CGFloat = 18

    /// `radius.card.md` `16px` — 07 recognize card, 11/13 chart cards, 09/10 skeleton hero.
    static let cardMd: CGFloat = 16

    /// `radius.card.sm` `14px` — primary buttons, activity rows, list rows, callouts, stat panels.
    static let cardSm: CGFloat = 14

    /// `radius.control` `12px` — segmented controls, stat cards, secondary action buttons,
    /// dashed wells.
    static let control: CGFloat = 12

    /// `radius.thumb.lg` `16px` — 02 top candidate thumb (76pt), 10 share thumb (72pt).
    static let thumbLg: CGFloat = 16

    /// `radius.thumb.md` `14px` — 01 card thumb (58pt), 02 row thumb (60pt), 08 species tiles.
    static let thumbMd: CGFloat = 14

    /// `radius.thumb.sm` `11px` — 07, 44pt thumb.
    static let thumbSm: CGFloat = 11
    /// `radius.thumb.sm` `10px` — activity 38pt, almanac 34pt.
    static let thumbSmAlt: CGFloat = 10
    /// `radius.thumb.sm` `8px` — W1 26pt, 12 grabber.
    static let thumbXs: CGFloat = 8

    /// `radius.badge` `6px` — `THRIVING`, `REMOVED`, `PLANTED 2024`.
    static let badge: CGFloat = 6

    /// `radius.methodBadge` `4px` — `taped` / `est.` inline badges.
    static let methodBadge: CGFloat = 4

    /// `radius.foliageCell` `5px` — season-strip cells.
    static let foliageCell: CGFloat = 5

    /// `radius.web.button` `12px` — W1 buttons. W1 is out of scope for iOS (ARCHITECTURE §8);
    /// transcribed for completeness only.
    static let webButton: CGFloat = 12
    /// `radius.web.button` `10px` — W1 "Sign in". Out of scope; see above.
    static let webSignIn: CGFloat = 10

    /// `radius.leafGlyph` — `border-radius: 50% 0` + `rotate(45deg)`.
    /// The CSS two-value shorthand rounds the top-left and bottom-right corners to 50% and leaves
    /// the other two square; rotating 45° turns that square into the leaf-diamond mark.
    /// See `CypressLeafGlyph`.
    static func leafGlyph(size: CGFloat) -> CGFloat { size / 2 }
}

// MARK: - Shapes

/// `radius.sheet` — `26px 26px 0 0`. Top corners only; the bottom runs off-screen.
struct CypressSheetShape: Shape {
    var radius: CGFloat = CypressRadius.sheet

    func path(in rect: CGRect) -> Path {
        UnevenRoundedRectangle(
            topLeadingRadius: radius,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: radius,
            style: .continuous
        )
        .path(in: rect)
    }
}

/// `radius.leafGlyph` — the leaf-diamond mark: a square with two opposite corners fully rounded,
/// rotated 45°. Draw it in a square frame; the rotation is applied inside the shape.
struct CypressLeafGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let square = CGRect(
            x: rect.midX - side / 2,
            y: rect.midY - side / 2,
            width: side,
            height: side
        )
        let leaf = UnevenRoundedRectangle(
            topLeadingRadius: side / 2,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: side / 2,
            topTrailingRadius: 0,
            style: .circular
        )
        return leaf
            .rotation(.degrees(45))
            .path(in: square)
    }
}

extension View {
    /// Clips to `radius.sheet` — 26pt top corners, square bottom. Bottom sheets (09, 10, 15).
    func cypressSheetCorners(radius: CGFloat = CypressRadius.sheet) -> some View {
        clipShape(CypressSheetShape(radius: radius))
    }

    /// Clips to a Cypress radius with the continuous (squircle) curve used throughout the mocks.
    func cypressCornerRadius(_ radius: CGFloat) -> some View {
        clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

// MARK: - §2 component radii

extension CypressRadius {

    /// C3 share-card foliage cell — `3px` (10).
    static let foliageCellShare: CGFloat = 3

    /// C29 grove tab pill — `11px` (08). Same number as `thumbSm`, different role.
    static let grovePill: CGFloat = 11

    /// C5 vitality reference swatch — `7px` (05).
    static let vitalitySwatch: CGFloat = 7

    /// C23 bar-chart corner radii. §2 gives three, keyed to bar height:
    /// `2` at h=4, `2.5` at h≥8, `3` at h=34.
    static let chartBarXs: CGFloat = 2
    static let chartBarSm: CGFloat = 2.5
    static let chartBarLg: CGFloat = 3

    /// C23 legend swatch — `3px` (13); C10-adjacent composition swatch — `3.5px` (12).
    static let legendSwatch: CGFloat = 3
    static let compositionSwatch: CGFloat = 3.5
    /// 12 §3's share track — `5px` on a 9pt bar, i.e. a capsule.
    static let compositionTrack: CGFloat = 5

    /// C17 grabber — `3px` on a 40×5 pill (i.e. a capsule).
    static let sheetGrabber: CGFloat = 3

    /// C18 park block — `14px`. Same number as `cardSm`, different role.
    static let mapPark: CGFloat = 14

    /// 04 framing-corner bracket — `8px` on the outer corner only.
    static let framingCorner: CGFloat = 8

    /// C13 photo-strip chip (13) — `6px`. Same number as `badge`, different role.
    static let photoChip: CGFloat = 6

    /// C19 removed-pin bar — `radius:1px` on the 8×2 crossbar.
    static let pinRemovedBar: CGFloat = 1

    /// C17 skeleton bars — `8px` on the 24pt bar (`thumbXs`) and `7px` on the 14pt one.
    static let skeletonBarSmall: CGFloat = 7
}
