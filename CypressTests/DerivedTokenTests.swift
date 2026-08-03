import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Cypress

/// What the ERRATA E8 derivation is allowed to be wrong about, and what it is not.
///
/// The derived dark values are a considered guess and a designer may overturn any of them. What
/// must not happen is the quieter failure: a token that reads as answered and is not. Three ways
/// that happens, and the three things pinned here.
///
/// 1. **A token is left light-only by accident.** The E8 gap was 59 tokens with no dark value and
///    a `// TODO` comment, which is invisible at runtime — the app simply glared. Every token that
///    claims to be derived is checked here to actually resolve to two different colors.
/// 2. **The review sheet drifts from the tokens.** `CypressColor.reviewTokens` is what TokenGallery
///    shows a designer, and it restates hexes that also live on the tokens. If someone promotes a
///    derived token to specified and forgets the registry line, review shows the old value. Every
///    entry is resolved against the live token here, in both appearances.
/// 3. **A derived color is unreadable.** The amber family is the palette most likely to fail on a
///    dark surface, so its contrast floor is pinned rather than eyeballed.
@Suite("Derived dark-mode tokens (ERRATA E8)")
struct DerivedTokenTests {

    // MARK: - Resolving

    private static let light = UITraitCollection(userInterfaceStyle: .light)
    private static let dark = UITraitCollection(userInterfaceStyle: .dark)

    /// The token's sRGB value under one appearance, as `0xRRGGBB`.
    private static func hex(_ color: Color, _ traits: UITraitCollection) -> UInt32 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a)
        let byte: (CGFloat) -> UInt32 = { UInt32((($0 * 255).rounded()).clamped(to: 0...255)) }
        return byte(r) << 16 | byte(g) << 8 | byte(b)
    }

    /// WCAG 2.1 relative luminance contrast. Written out because the design system has no color
    /// maths of its own and does not need any at runtime — only the test asks this question.
    private static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        func luminance(_ hex: UInt32) -> Double {
            let channels = [(hex >> 16) & 0xFF, (hex >> 8) & 0xFF, hex & 0xFF].map { channel -> Double in
                let value = Double(channel) / 255
                return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
        }
        let (high, low) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
        return (high + 0.05) / (low + 0.05)
    }

    // MARK: - The registry is the tokens

    @Test("every review-sheet row resolves to the pair it prints")
    func registryMatchesTheLiveTokens() {
        for token in CypressColor.reviewTokens {
            #expect(
                Self.hex(token.color, Self.light) == token.light,
                """
                \(token.name): the review sheet prints #\(String(format: "%06X", token.light)) for \
                light, the token resolves to #\(String(format: "%06X", Self.hex(token.color, Self.light))). \
                CypressColor.reviewTokens and the token itself have drifted apart, and TokenGallery \
                is showing a designer the wrong swatch.
                """
            )
            let expectedDark = token.dark ?? token.light
            #expect(
                Self.hex(token.color, Self.dark) == expectedDark,
                """
                \(token.name): the review sheet prints #\(String(format: "%06X", expectedDark)) for \
                dark, the token resolves to #\(String(format: "%06X", Self.hex(token.color, Self.dark))).
                """
            )
        }
    }

    @Test("a derived token actually carries a dark value")
    func derivedTokensResolveDifferently() {
        for token in CypressColor.derivedTokens {
            #expect(
                Self.hex(token.color, Self.light) != Self.hex(token.color, Self.dark),
                """
                \(token.name) is listed as derived but resolves to the same color in both \
                appearances. That is the E8 failure exactly: a token that reads as answered and \
                still glares after dark.
                """
            )
        }
    }

    @Test("an escalated token is honestly still light-only")
    func escalatedTokensDoNotResolve() {
        for token in CypressColor.escalatedTokens {
            #expect(token.dark == nil, "\(token.name) is listed as escalated but carries a dark value")
            #expect(
                Self.hex(token.color, Self.light) == Self.hex(token.color, Self.dark),
                "\(token.name) is listed as escalated but resolves differently after dark"
            )
        }
    }

    @Test("the review sheet lists each token once")
    func registryHasNoDuplicates() {
        let names = CypressColor.reviewTokens.map(\.name)
        #expect(Set(names).count == names.count, "duplicate rows in CypressColor.reviewTokens")
    }

    // MARK: - The amber family after dark

    /// ROADMAP M4 names this one: "contrast verification on the amber family, which is the palette
    /// most likely to fail". The floors are WCAG AA — 4.5:1 for body copy, 3:1 for the border and
    /// the glyph, which are non-text.
    @Test("derived amber text clears WCAG AA on its derived fill")
    func amberContrastAfterDark() {
        let pairs: [(String, Color, Color, Double)] = [
            ("amber pill text on its fill",
             CypressColor.amberPillText, CypressColor.amberPillFill, 4.5),
            ("selected amber chip text on its fill",
             CypressColor.amberChipSelectedText, CypressColor.amberChipSelectedFill, 4.5),
            ("311 panel body on the panel",
             CypressColor.hazardPanelText, CypressColor.hazardPanelFill, 4.5),
            ("311 CTA label on the CTA",
             CypressColor.hazardCTAText, CypressColor.hazardCTAFill, 4.5),
            ("311 phone glyph on the Signal Amber circle",
             CypressColor.hazardPanelGlyph, CypressColor.signalAmber, 3.0),
            ("amber pill border on the pill",
             CypressColor.amberPillBorder, CypressColor.amberPillFill, 3.0),
            ("attention card border on the card",
             CypressColor.amberAttentionCardBorder, CypressColor.surfaceCard, 3.0),
        ]

        for (what, foreground, background, floor) in pairs {
            let ratio = Self.contrast(
                Self.hex(foreground, Self.dark),
                Self.hex(background, Self.dark)
            )
            #expect(
                ratio >= floor,
                "\(what) is \(String(format: "%.2f", ratio)):1 after dark, below the \(floor):1 floor"
            )
        }
    }

    /// The badge families derive onto the documented thriving/`taped` pair, so they inherit its
    /// legibility. Pinned because a badge that derives onto the wrong fill fails silently: the
    /// label is two words and nobody reads it closely enough to notice.
    @Test("derived badge text clears WCAG AA on its derived fill")
    func badgeContrastAfterDark() {
        let pairs: [(String, Color, Color)] = [
            ("city record", CypressColor.cityRecordBadgeText, CypressColor.cityRecordBadgeFill),
            ("planted", CypressColor.plantedBadgeText, CypressColor.plantedBadgeFill),
            ("removed", CypressColor.removedBadgeText, CypressColor.removedBadgeFill),
            ("memorial banner", CypressColor.memorialBannerText, CypressColor.memorialBannerFill),
        ]

        for (what, foreground, background) in pairs {
            let ratio = Self.contrast(
                Self.hex(foreground, Self.dark),
                Self.hex(background, Self.dark)
            )
            #expect(
                ratio >= 4.5,
                "the \(what) badge is \(String(format: "%.2f", ratio)):1 after dark"
            )
        }
    }

    // MARK: - The one that started it

    /// ERRATA E8's own sentence: "`border.dashed` is the brightest element on the dark check-in
    /// screen". D3 could not settle it — it drops the optional well entirely — so the value is
    /// derived, and this is the assertion that it stays quiet: a hairline must not out-shine the
    /// mint CTA that D3 makes the brightest thing on the screen.
    @Test("the dashed well no longer out-shines D3's CTA")
    func dashedBorderIsQuietAfterDark() {
        let ground = Self.hex(CypressColor.surfaceScreen, Self.dark)
        let dashed = Self.contrast(Self.hex(CypressColor.borderDashed, Self.dark), ground)
        let cta = Self.contrast(Self.hex(CypressColor.ctaFill, Self.dark), ground)
        #expect(
            dashed < cta,
            """
            border.dashed reads at \(String(format: "%.2f", dashed)):1 against the dark ground and \
            the CTA at \(String(format: "%.2f", cta)):1 — the dashed well is the loudest thing on \
            the check-in screen again.
            """
        )
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
