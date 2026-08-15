//
//  AppleMark.swift
//  Cypress — Features/AccountAsk
//
//  The Apple logo on screen 15's `Continue with Apple` button. **The owner ruled it on 2026-08-14**
//  (ruling 6): draw it as a vector shape into the existing drawn control, per Apple's own
//  custom-button guidelines, consistent with the five ex-SF-Symbol glyphs (RULINGS R57,
//  `DrawnGlyphGuardTests`). No SF Symbol, and none of Apple's own button views — neither
//  `ASAuthorizationAppleIDButton` (UIKit) nor `SignInWithAppleButton` (SwiftUI), each of which draws
//  Apple's mark for you and takes the whole control with it. The button's fill and its label do not
//  change.
//
//  **Both spellings are named in this paragraph on purpose.**
//  `AppleMarkTests.theAppConstructsNoSystemAppleButton` scans the app target for each of them and
//  controls each token against a prose mention, so that a scan for a string this repository does not
//  contain cannot pass by matching nothing. This is that anchor. The SwiftUI half of it exists
//  because PR #88's reviewer compiled `SignInWithAppleButton(.continue, …)` into
//  `AccountProviderButton` — the exact control this ruling governs — and every guard stayed green.
//
//  ── 1. Where the geometry came from, since it is not mine ──────────────────────────────────────
//  Apple's Sign in with Apple JS SDK, which the Human Interface Guidelines link to as the way to
//  "view and adjust live previews of web-based buttons and get the code":
//
//      https://appleid.cdn-apple.com/appleauth/static/jsapi/appleid/1/en_US/appleid.auth.js
//
//  It carries the same three logo files Apple Design Resources ships for a button with text, as
//  path data, each in a **44 pt tall** box with Apple's own padding built in:
//
//      | size   | file box | crop      | glyph inside the crop     | glyph height ÷ box |
//      | small  | 24 × 44  | 12 × 44   | 11.825 × 14.532           | 33.0 %             |
//      | medium | 31 × 44  | 17 × 44   | 15.461 × 19.000           | 43.2 %             |
//      | large  | 39 × 44  | 21 × 44   | 19.530 × 24.000           | 54.5 %             |
//
//  `small` is transcribed below — Apple's own default for a button with text, and there is no other
//  provider mark on this sheet to size against (§4 and §5 draw wordmark-free outlined buttons), so
//  the HIG's reason to reach for `medium` or `large` does not arise. The crop is `viewBox="6 0 12
//  44"` of the 24-wide file, which is what Apple's own renderer takes; every control point below is
//  that path translated by −6 in x and otherwise untouched, so `pathBox` is 12 × 44 and the padding
//  in it is Apple's.
//
//  **The padding is why the whole file is transcribed rather than only the apple.** The HIG's rule
//  is "match the height of the logo file to the height of the button", "don't crop the logo file",
//  "don't add vertical padding" — the file's own top and bottom margins are what put the mark on the
//  title's optical center, and they are not equal (13.63 above, 15.83 below). Trimming to the glyph
//  and centering it would have moved the mark down by a point, which is exactly the drift the rule
//  is written to prevent.
//
//  ── 2. What Apple asks that this app does not give it ──────────────────────────────────────────
//  Recorded here rather than only in the errata, because the next person to touch this file is the
//  one who needs it:
//
//  - **"Use only the logo artwork downloaded from Apple Design Resources; never create a custom
//    Apple logo."** Nothing here is drawn by eye — it is Apple's published path, control point for
//    control point — but it is a transcription of that artwork rather than the file itself, and the
//    guideline's literal reading asks for the file. That is the owner's ruling and the trade it
//    makes: an app whose every glyph is a `Shape` in this repo (R57) against a vendor asset. App
//    Review evaluates all custom Sign in with Apple buttons.
//  - **"the title's font size would be 43% of the button's height".** SCREENS.md 15 §3 draws 15 px /
//    700 with `padding:14px`, which puts the label nearer a third of the button's height. The mock
//    is not this round's to move and the ruling says the label does not change, so the mark is sized
//    from the title instead of from the button — see `fileHeight(forTitleSize:)`.
//  - **"The overall color needs to remain black or white."** `accountPrimaryFill` is `#1C2A21` in
//    light — a near-black with a green cast, drawn by the mock — and it inverts to `#E4EBE2` in
//    dark, where the mark inverts with it through `accountPrimaryLabel`. Within the button the mark
//    and the title are always the same color, which is the part of the rule that is about the mark.
//

import SwiftUI

/// Apple's `small` Sign in with Apple logo file, as a `Shape`.
///
/// Scales uniformly and centers inside whatever rect it is given, so a caller cannot stretch the
/// mark by handing it the wrong aspect ratio — `Path` on its own would have.
struct AppleMark: Shape {

    /// The transcribed file's own coordinate space: Apple's 12 × 44 crop.
    static let pathBox = CGSize(width: 12, height: 44)

    /// The file's aspect ratio, for a caller sizing a frame for it.
    static let aspectRatio = pathBox.width / pathBox.height

    /// The logo file's height for a button whose title is drawn at `size`.
    ///
    /// Apple states the proportion twice and in both directions: "the title's font size would be
    /// 43% of the button's height — in other words, the button's height would be 233% of the title's
    /// font size, rounded to the nearest integer", and separately "match the height of the logo file
    /// to the height of the button". Composing the two gives the logo file its height from the title
    /// alone, which is the form this app can honor: screen 15's button is taller than 233% of its
    /// 15 pt label, and its padding is the mock's rather than mine to change.
    ///
    /// Sizing from the title is also the version that survives Dynamic Type. The button's height at
    /// AX5 is set by a label that has wrapped onto three lines; a mark matched to *that* would be
    /// half the height of the sheet.
    static func fileHeight(forTitleSize size: CGFloat) -> CGFloat { size * 2.33 }

    /// Apple's minimum margin between the logo file and the button's leading edge: half the file's
    /// width, taken from `appleid.auth.js`'s own layout (`leftMargin = floor(0.5 * logoWidth)`).
    static func leadingMargin(forFileWidth width: CGFloat) -> CGFloat { width * 0.5 }

    /// Apple's minimum margin between the logo file and the title: seven tenths of the file's width
    /// (`middleMargin = floor(0.7 * logoWidth)`, same source).
    static func titleMargin(forFileWidth width: CGFloat) -> CGFloat { width * 0.7 }

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width / Self.pathBox.width, rect.height / Self.pathBox.height)
        let originX = rect.minX + (rect.width - Self.pathBox.width * scale) / 2
        let originY = rect.minY + (rect.height - Self.pathBox.height * scale) / 2
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: originX + x * scale, y: originY + y * scale)
        }

        var p = Path()
        // The leaf.
        p.move(to: pt(6.233743, 16.98797))
        p.addCurve(to: pt(8.201497, 15.95328), control1: pt(6.889661, 16.98797), control2: pt(7.711868, 16.54453))
        p.addCurve(to: pt(8.968274, 13.92086), control1: pt(8.644934, 15.41746), control2: pt(8.968274, 14.66916))
        p.addCurve(to: pt(8.940559, 13.63447), control1: pt(8.968274, 13.81924), control2: pt(8.959036, 13.71762))
        p.addCurve(to: pt(6.806516, 14.74307), control1: pt(8.210735, 13.66219), control2: pt(7.333098, 14.1241))
        p.addCurve(to: pt(6.012024, 16.71082), control1: pt(6.390793, 15.21422), control2: pt(6.012024, 15.95328))
        p.addCurve(to: pt(6.039739, 16.96949), control1: pt(6.012024, 16.82168), control2: pt(6.030501, 16.93254))
        p.addCurve(to: pt(6.233743, 16.98797), control1: pt(6.08593, 16.97873), control2: pt(6.159837, 16.98797))
        p.closeSubpath()
        // The body.
        p.move(to: pt(3.924172, 28.16629))
        p.addCurve(to: pt(6.335364, 27.5658), control1: pt(4.820286, 28.16629), control2: pt(5.217532, 27.5658))
        p.addCurve(to: pt(8.71884, 28.14781), control1: pt(7.471672, 27.5658), control2: pt(7.721106, 28.14781))
        p.addCurve(to: pt(10.97298, 26.35559), control1: pt(9.698098, 28.14781), control2: pt(10.35402, 27.24246))
        p.addCurve(to: pt(11.97072, 24.29545), control1: pt(11.66585, 25.33938), control2: pt(11.95224, 24.34164))
        p.addCurve(to: pt(10.03068, 21.35768), control1: pt(11.90605, 24.27697), control2: pt(10.03068, 23.5102))
        p.addCurve(to: pt(11.59195, 18.58619), control1: pt(10.03068, 19.49154), control2: pt(11.5088, 18.65086))
        p.addCurve(to: pt(8.71884, 17.14502), control1: pt(10.61269, 17.18197), control2: pt(9.125325, 17.14502))
        p.addCurve(to: pt(6.159837, 17.81018), control1: pt(7.619485, 17.14502), control2: pt(6.723372, 17.81018))
        p.addCurve(to: pt(3.794836, 17.18197), control1: pt(5.55011, 17.81018), control2: pt(4.746379, 17.18197))
        p.addCurve(to: pt(0.1457154, 21.50549), control1: pt(1.984133, 17.18197), control2: pt(0.1457154, 18.67857))
        p.addCurve(to: pt(1.670032, 26.31863), control1: pt(0.1457154, 23.26076), control2: pt(0.8293482, 25.11766))
        p.addCurve(to: pt(3.924172, 28.16629), control1: pt(2.390618, 27.33484), control2: pt(3.018821, 28.16629))
        p.closeSubpath()
        return p
    }
}
