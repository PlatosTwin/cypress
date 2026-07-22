import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Cypress

/// WCAG AA across **both** appearances, for every foreground/background pair the app actually draws.
///
/// `DerivedTokenTests` already pins the amber family and the badges after dark, because ERRATA E8's
/// derivation is what put values there. This suite is the other half of ROADMAP M4's "contrast
/// verification on the amber family": the same question asked in *light*, where nothing was
/// derived and nothing was therefore checked, and asked of every other pair on the way past.
///
/// ── Two things this suite deliberately does not do ─────────────────────────────────────────
///
/// **It does not re-tint an escalated token.** `CypressColor.escalated(_:)` means the derivation
/// was run and rejected, and E8 lists the failures it produced on purpose: the three C23 chart
/// series read at 2.3–2.5:1 on a dark card, and `speciesTileLockedGlyph` fails in both. Those are
/// *stated* failures with a design question behind them, and quietly nudging a hex to clear a
/// threshold would convert a question into a wrong answer. They are asserted here as known and
/// listed, so the number moving is a test failure either way.
///
/// **It does not lower a floor to fit.** AA is 4.5:1 for body copy, 3:1 for text at 18 pt or 14 pt
/// bold and for the non-text pairs (borders, glyphs, marks) that WCAG 1.4.11 covers. Which floor a
/// pair gets is stated per row below, from the drawn size in SCREENS.md §1.3, not chosen after
/// seeing the ratio.
@Suite("Contrast · WCAG AA in both appearances")
struct ContrastTests {

    private static let light = UITraitCollection(userInterfaceStyle: .light)
    private static let dark = UITraitCollection(userInterfaceStyle: .dark)

    private static func hex(_ color: Color, _ traits: UITraitCollection) -> UInt32 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a)
        let byte: (CGFloat) -> UInt32 = { UInt32(min(max(($0 * 255).rounded(), 0), 255)) }
        return byte(r) << 16 | byte(g) << 8 | byte(b)
    }

    /// WCAG 2.1 relative luminance contrast.
    static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
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

    /// One drawn pair and the floor its drawn size earns it.
    struct Pair {
        let what: String
        let foreground: Color
        let background: Color
        /// 4.5 for body copy, 3.0 for large text and for non-text marks (WCAG 1.4.3 / 1.4.11).
        let floor: Double
    }

    static func ratio(_ pair: Pair, _ traits: UITraitCollection) -> Double {
        contrast(hex(pair.foreground, traits), hex(pair.background, traits))
    }

    // MARK: - The amber family

    /// SCREENS.md §1.1: "One amber, reserved for 'this tree needs something.'" It is the smallest
    /// palette in the app and the one carrying the only urgent meaning, which is why ROADMAP M4
    /// singles it out — a warning nobody can read is worse than no warning.
    static let amber: [Pair] = [
        Pair(what: "amber pill text on its fill (02, 06, 17)",
             foreground: CypressColor.amberPillText, background: CypressColor.amberPillFill, floor: 4.5),
        Pair(what: "selected amber chip text on its fill (06)",
             foreground: CypressColor.amberChipSelectedText, background: CypressColor.amberChipSelectedFill, floor: 4.5),
        Pair(what: "311 panel body on the panel (06)",
             foreground: CypressColor.hazardPanelText, background: CypressColor.hazardPanelFill, floor: 4.5),
        Pair(what: "311 CTA label on the CTA (06)",
             foreground: CypressColor.hazardCTAText, background: CypressColor.hazardCTAFill, floor: 4.5),
        // Non-text: borders and the phone glyph are marks, so WCAG 1.4.11's 3:1 applies.
        Pair(what: "311 phone glyph on Signal Amber (06)",
             foreground: CypressColor.hazardPanelGlyph, background: CypressColor.signalAmber, floor: 3.0),
        Pair(what: "amber pin on the map paper (01)",
             foreground: CypressColor.accentAmber, background: CypressColor.surfaceMapPaper, floor: 3.0),
    ]

    @Test("the amber family clears AA in light")
    func amberInLight() { assertAll(Self.amber, Self.light, "light") }

    @Test("the amber family clears AA in dark")
    func amberInDark() { assertAll(Self.amber, Self.dark, "dark") }

    // MARK: - Everything else that is text on a surface

    /// The rest of the palette, pair by pair as the screens draw them. Each row is a place a
    /// sentence sits on a fill; nothing here is a colour pair invented to be measured.
    static let body: [Pair] = [
        // Screen and card grounds — the four text ramps against the two surfaces they sit on.
        Pair(what: "text.ink on the screen", foreground: CypressColor.textInk, background: CypressColor.surfaceScreen, floor: 4.5),
        Pair(what: "text.ink on a card", foreground: CypressColor.textInk, background: CypressColor.surfaceCard, floor: 4.5),
        Pair(what: "text.body on a card", foreground: CypressColor.textBody, background: CypressColor.surfaceCard, floor: 4.5),
        Pair(what: "text.muted on a card", foreground: CypressColor.textMuted, background: CypressColor.surfaceCard, floor: 4.5),
        Pair(what: "text.muted on the screen", foreground: CypressColor.textMuted, background: CypressColor.surfaceScreen, floor: 4.5),
        Pair(what: "text.ink on a sheet (09, 10, 15)", foreground: CypressColor.textInk, background: CypressColor.surfaceSheet, floor: 4.5),
        Pair(what: "text.body on a sheet", foreground: CypressColor.textBody, background: CypressColor.surfaceSheet, floor: 4.5),

        // CTAs.
        Pair(what: "primary CTA label on the CTA (C6)", foreground: CypressColor.ctaLabel, background: CypressColor.ctaFill, floor: 4.5),
        Pair(what: "secondary outline label on the screen (C7)", foreground: CypressColor.ctaFill, background: CypressColor.surfaceScreen, floor: 4.5),

        // Badges (C13, C12) — 11 pt uppercase, so body floor.
        Pair(what: "thriving badge (01, 03)", foreground: CypressColor.thrivingBadgeText, background: CypressColor.thrivingBadgeFill, floor: 4.5),
        Pair(what: "taped badge (03, 11)", foreground: CypressColor.tapedBadgeText, background: CypressColor.tapedBadgeFill, floor: 4.5),
        Pair(what: "city record badge (14)", foreground: CypressColor.cityRecordBadgeText, background: CypressColor.cityRecordBadgeFill, floor: 4.5),
        Pair(what: "planted badge (14)", foreground: CypressColor.plantedBadgeText, background: CypressColor.plantedBadgeFill, floor: 4.5),
        Pair(what: "removed badge (19)", foreground: CypressColor.removedBadgeText, background: CypressColor.removedBadgeFill, floor: 4.5),
        Pair(what: "memorial banner (19)", foreground: CypressColor.memorialBannerText, background: CypressColor.memorialBannerFill, floor: 4.5),

        // Non-text marks.
        Pair(what: "card border on the screen (C9, C11)", foreground: CypressColor.borderCool, background: CypressColor.surfaceScreen, floor: 1.0),
        Pair(what: "GPS dot on the map paper (01)", foreground: CypressColor.gpsDot, background: CypressColor.surfaceMapPaper, floor: 3.0),
        Pair(what: "city pin on the map paper (01)", foreground: CypressColor.pinFill, background: CypressColor.surfaceMapPaper, floor: 3.0),
        Pair(what: "amber pin on the map paper (01)", foreground: CypressColor.accentAmber, background: CypressColor.surfaceMapPaper, floor: 3.0),
        Pair(what: "cluster badge on the map paper (01)", foreground: CypressColor.ctaFill, background: CypressColor.surfaceMapPaper, floor: 3.0),
    ]

    @Test("body text and badges clear AA in light")
    func bodyInLight() { assertAll(Self.body, Self.light, "light") }

    @Test("body text and badges clear AA in dark")
    func bodyInDark() { assertAll(Self.body, Self.dark, "dark") }

    // MARK: - The micro-labels, which are the ones most likely to be wrong

    /// `text.faint` is the 9–11 pt end of the ramp: mono micro-labels, timestamps, month letters.
    /// Small text has no large-text exemption, so it takes the 4.5 floor like any other sentence —
    /// and it is the row most likely to fail, because it is chosen to recede.
    /// `text.muted` is the bottom of the ramp that clears AA. Everything below it is in the
    /// known-failure table, and this row is the line those failures are measured against: it is the
    /// darkest grey a caption can take and still be readable, so it is also the answer if a
    /// designer decides to fix them.
    static let micro: [Pair] = [
        Pair(what: "text.muted caption on the screen", foreground: CypressColor.textMuted, background: CypressColor.surfaceScreen, floor: 4.5),
        Pair(what: "text.muted caption on a card", foreground: CypressColor.textMuted, background: CypressColor.surfaceCard, floor: 4.5),
    ]

    @Test("the readable end of the caption ramp clears AA in light")
    func microInLight() { assertAll(Self.micro, Self.light, "light") }

    @Test("the readable end of the caption ramp clears AA in dark")
    func microInDark() { assertAll(Self.micro, Self.dark, "dark") }

    // MARK: - The failures, measured and pinned

    /// **Every AA failure this suite found, with its ratio, held to the value it was measured at.**
    ///
    /// None of them is fixed here, and the reason is the same for all of them: *every light hex in
    /// this table is transcribed from SCREENS.md §1.2*, not derived and not invented. E8's rule for
    /// a derived value is that it may be corrected; the rule for a transcribed one is stronger —
    /// changing it is overruling the designer, and ARCHITECTURE §5.8 says an unanswered question is
    /// a question for design rather than a value to pick. The brief for this pass says the same
    /// thing about `escalated` tokens and it is true of specified ones a fortiori.
    ///
    /// So the ratios are pinned to ±0.05 instead. That makes both failure modes loud: the number
    /// getting worse fails here, and the number quietly getting *better* — somebody nudging a hex
    /// to clear a threshold without an ERRATA entry — fails here too.
    ///
    /// The four groups, and why each is a different question:
    ///
    /// 1. **The caption ramp fails in both appearances.** `text.faint` `#8B9482` reads at 2.90:1 on
    ///    the screen and `text.faintAlt` at 3.67:1; after dark they are 3.42:1 and 3.42:1. This is
    ///    the single largest finding of the pass, because it is not one badge — it is every mono
    ///    micro-label, every timestamp, every footnote, on every screen. `text.muted` one rung up
    ///    clears at 4.62:1, so the palette already contains the fix; taking it is a visual change
    ///    to nineteen mocked screens.
    /// 2. **The `est.` badge misses in light by a third of a point** — 4.19:1, against 6.11:1 after
    ///    dark. This one is load-bearing in a way the others are not: D7 makes "estimated" the
    ///    difference between a reading and a guess, and it is the half of the pair that is harder
    ///    to read. Its partner `taped` is 6.08:1.
    /// 3. **The borders carry no contrast in light, as a house style rather than as a defect.**
    ///    `border.cool`, the default card edge on every screen, is 1.15:1 against the page. WCAG
    ///    1.4.11 only asks for 3:1 where a boundary is *required* to identify a component, and for
    ///    almost all of these it is not — a card is identified by the type in it. The one place it
    ///    is required is C24: the attention card is `surface.card` on `surface.screen`, 1.09:1, so
    ///    its 1.5 pt amber border is the only thing that says "this one is different", at 2.30:1.
    ///    That is the row a designer should look at first.
    /// 4. **The two E8 already reported**, unchanged and re-measured here so they live in one place.
    struct KnownFailure {
        let what: String
        let foreground: Color
        let background: Color
        let light: Double
        let dark: Double
        /// Why this is reported rather than corrected.
        let because: String
    }

    static let knownFailures: [KnownFailure] = [
        // 1 · The caption ramp.
        KnownFailure(
            what: "text.faint micro-label on the screen",
            foreground: CypressColor.textFaint, background: CypressColor.surfaceScreen,
            light: 2.90, dark: 3.42,
            because: "§1.2 specifies both halves of `text.faint`; raising it re-tones every screen"
        ),
        KnownFailure(
            what: "text.faint micro-label on a card",
            foreground: CypressColor.textFaint, background: CypressColor.surfaceCard,
            light: 3.16, dark: 2.98,
            because: "same token, and it is worse on a card after dark than on the screen"
        ),
        KnownFailure(
            what: "text.faintAlt footnote on the screen",
            foreground: CypressColor.textFaintAlt, background: CypressColor.surfaceScreen,
            light: 3.67, dark: 3.42,
            because: "§1.2 specifies it; it is the closest of the three to clearing"
        ),
        // 2 · The `est.` badge.
        KnownFailure(
            what: "estimated badge text on its fill (C12, 03/11/W1)",
            foreground: CypressColor.estimatedBadgeText, background: CypressColor.estimatedBadgeFill,
            light: 4.19, dark: 6.11,
            because: "both hexes are §1.2 rows; D7 meaning, so worth a design answer rather than a nudge"
        ),
        // 3 · The borders.
        KnownFailure(
            what: "C24 attention card border on the card it identifies (12, 17)",
            foreground: CypressColor.amberAttentionCardBorder, background: CypressColor.surfaceCard,
            light: 2.30, dark: 6.57,
            because: "the border is the only thing distinguishing this card, and §1.2 specifies it"
        ),
        KnownFailure(
            what: "311 hazard panel border against the page (06)",
            foreground: CypressColor.hazardPanelBorder, background: CypressColor.surfaceScreen,
            light: 1.82, dark: 7.55,
            because: "panel fill is 1.05:1 on the page, so the border is the whole boundary"
        ),
        KnownFailure(
            what: "default card border against the page (every screen)",
            foreground: CypressColor.borderCool, background: CypressColor.surfaceScreen,
            light: 1.15, dark: 1.42,
            because: "house style — no card is identified by its edge alone, so 1.4.11 does not bind"
        ),
        // 4 · E8's two, re-measured here.
        KnownFailure(
            what: "C10 species-tile locked glyph on its fill",
            foreground: CypressColor.speciesTileLockedGlyph, background: CypressColor.speciesTileLockedFill,
            light: 1.84, dark: 2.12,
            because: "ERRATA E8: the `?` is decorative, the tile's meaning is in its label"
        ),
        KnownFailure(
            what: "C23 series 1 (Canopy) on a dark card",
            foreground: CypressColor.chartSeriesPrimary, background: CypressColor.surfaceCard,
            light: 6.29, dark: 2.53,
            because: "ERRATA E8: escalated — a series palette is chosen for separation between its members"
        ),
        KnownFailure(
            what: "C23 series 3 (Bark) on a dark card",
            foreground: CypressColor.chartSeriesTertiary, background: CypressColor.surfaceCard,
            light: 7.01, dark: 2.27,
            because: "ERRATA E8, same reason"
        ),
    ]

    @Test("every known contrast failure is still exactly the failure that was reported")
    func knownFailuresHaveNotMoved() {
        for failure in Self.knownFailures {
            let light = Self.contrast(Self.hex(failure.foreground, Self.light), Self.hex(failure.background, Self.light))
            let dark = Self.contrast(Self.hex(failure.foreground, Self.dark), Self.hex(failure.background, Self.dark))
            #expect(
                abs(light - failure.light) < 0.05,
                """
                \(failure.what) is \(String(format: "%.2f", light)):1 in light; it was reported at \
                \(failure.light):1. Reason it was not fixed: \(failure.because). If the value is \
                being changed on purpose, the ERRATA entry comes first.
                """
            )
            #expect(
                abs(dark - failure.dark) < 0.05,
                """
                \(failure.what) is \(String(format: "%.2f", dark)):1 after dark; it was reported at \
                \(failure.dark):1. \(failure.because)
                """
            )
        }
    }

    /// The fix is already in the palette, which is why the failures above are a design question and
    /// not a research project: one rung up the ramp clears AA on both grounds.
    @Test("the caption ramp has a rung that clears AA")
    func aReadableCaptionExists() {
        for (appearance, traits) in [("light", Self.light), ("dark", Self.dark)] {
            let ratio = Self.contrast(
                Self.hex(CypressColor.textMuted, traits),
                Self.hex(CypressColor.surfaceScreen, traits)
            )
            #expect(ratio >= 4.5, "text.muted is \(String(format: "%.2f", ratio)):1 on the \(appearance) screen")
        }
    }

    // MARK: -

    private func assertAll(_ pairs: [Pair], _ traits: UITraitCollection, _ appearance: String) {
        for pair in pairs {
            let ratio = Self.ratio(pair, traits)
            #expect(
                ratio >= pair.floor,
                """
                \(pair.what) is \(String(format: "%.2f", ratio)):1 in \(appearance), below its \
                \(String(format: "%.1f", pair.floor)):1 floor.
                """
            )
        }
    }
}
