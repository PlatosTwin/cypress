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
/// ── What changed, and what deliberately did not ────────────────────────────────────────────
///
/// **The caption ramp was retinted under RULINGS R1** (ERRATA E108). Five values that E106 found
/// failing and reported rather than fixed are now fixed in the token: `text.faint`, `text.faintAlt`
/// and `text.muted` moved in both halves or one, the `est.` badge label moved, and C24's border
/// moved. Their new ratios are pinned in `retinted` below, to ±0.05, in the same direction as the
/// known failures were: a number that gets worse fails, and a number that quietly gets *better*
/// fails too, because either means a token changed without a ruling behind it.
///
/// **R1a then extended it to three grounds this sweep had never measured**, which is why they were
/// missing from the ruling: `searchGlyph` on C20's translucent fill, `CypressColor.Dark.textFaint`
/// on screen 04 — dark by design in both appearances, and therefore not reached by a retint of the
/// resolving token — and 14's empty photo well, closed by correcting a *derived* surface rather
/// than by overruling anything. The lesson is the suite's own: a pair that is never measured is a
/// pair that never fails.
///
/// **It does not re-tint an escalated token.** `CypressColor.escalated(_:)` means the derivation
/// was run and rejected, and E8 lists the failures it produced on purpose: the three C23 chart
/// series read at 2.3–2.5:1 on a dark card, and `speciesTileLockedGlyph` fails in both. Those are
/// *stated* failures with a design question behind them, and quietly nudging a hex to clear a
/// threshold would convert a question into a wrong answer. R1 leaves all three where they are and
/// says why: they are drawn decisions — a glyph and a data encoding — and not a text ramp. They
/// are asserted here as known and listed, so the number moving is a test failure either way.
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

    /// A translucent fill composited over what is behind it, as a `Color` that resolves in both
    /// appearances.
    ///
    /// `hex(_:_:)` above drops alpha, which is right for every opaque token and wrong for exactly
    /// one measured pair: C20's search fill is `rgba(255,255,255,.94)` over the map, so the
    /// placeholder that sits on it sits on the composite. Measuring the token instead would be the
    /// same class of mistake as measuring a caption on the wrong surface — small here (0.06) and
    /// only small by luck.
    static func flatten(_ fill: Color, over ground: Color) -> Color {
        Color(uiColor: UIColor { traits in
            var fr: CGFloat = 0, fg: CGFloat = 0, fb: CGFloat = 0, fa: CGFloat = 0
            var gr: CGFloat = 0, gg: CGFloat = 0, gb: CGFloat = 0, ga: CGFloat = 0
            UIColor(fill).resolvedColor(with: traits).getRed(&fr, green: &fg, blue: &fb, alpha: &fa)
            UIColor(ground).resolvedColor(with: traits).getRed(&gr, green: &gg, blue: &gb, alpha: &ga)
            return UIColor(
                red: fa * fr + (1 - fa) * gr,
                green: fa * fg + (1 - fa) * gg,
                blue: fa * fb + (1 - fa) * gb,
                alpha: 1
            )
        })
    }

    /// C20's search fill as it is actually drawn on 01 — 94% opaque over the map paper.
    static let searchFillOverMap = flatten(CypressColor.searchFill, over: CypressColor.surfaceMapPaper)

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
        Pair(what: "`est.` badge text on its fill (C12, 03/11/W1)",
             foreground: CypressColor.estimatedBadgeText, background: CypressColor.estimatedBadgeFill, floor: 4.5),
        // Non-text: borders and the phone glyph are marks, so WCAG 1.4.11's 3:1 applies.
        Pair(what: "311 phone glyph on Signal Amber (06)",
             foreground: CypressColor.hazardPanelGlyph, background: CypressColor.signalAmber, floor: 3.0),
        Pair(what: "amber pin on the map paper (01)",
             foreground: CypressColor.accentAmber, background: CypressColor.surfaceMapPaper, floor: 3.0),
        // C24 is `surface.card` on `surface.screen` at 1.09:1, so its border is the only thing
        // identifying the card — the one place in this palette where 1.4.11 genuinely binds, and
        // therefore measured against the surface on *each* side of it rather than one of them.
        Pair(what: "C24 attention card border on the card it identifies (12, 17)",
             foreground: CypressColor.amberAttentionCardBorder, background: CypressColor.surfaceCard, floor: 3.0),
        Pair(what: "C24 attention card border against the page behind it (12, 17)",
             foreground: CypressColor.amberAttentionCardBorder, background: CypressColor.surfaceScreen, floor: 3.0),
    ]

    @Test("the amber family clears AA in light")
    func amberInLight() { assertAll(Self.amber, Self.light, "light") }

    @Test("the amber family clears AA in dark")
    func amberInDark() { assertAll(Self.amber, Self.dark, "dark") }

    // MARK: - The four species slots, on every ground screen 01 draws

    /// **The grounds a map pin actually sits on, which is not one colour.**
    ///
    /// `body` above measures the city pin and the amber pin against `surface.map.paper` and stops
    /// there, and that is the easiest of the seven: the paper is the lightest thing on the map in
    /// light and the darkest in dark, so a mark measured only against it is measured against its best
    /// case. A pin over Golden Gate Park, over a street band, over the ocean or on the beach is on
    /// something else entirely — and 01's own pins spend most of their time on the street band,
    /// because that is where street trees are.
    ///
    /// So the four species slots (task #80) are measured against all seven, in both appearances:
    /// 56 pairs. The floor is WCAG 1.4.11's 3:1 — a pin is a non-text mark — and the binding grounds
    /// turned out to be the **water** in light and the **park inset ring** in dark, with the park
    /// block next in both. Neither is a ground anybody would have thought to check, and the paper —
    /// the only one the suite measured a pin against before — is the easiest of the seven.
    ///
    /// These are the app's own map tokens rather than MapKit's tiles, which is a stand-in and is
    /// stated as one: the real ground is a MapKit basemap under `MapLayout.washOpacityLight`/`Dark`.
    /// The tokens are the palette that basemap was tuned toward, they span the same range from paper
    /// to park to water, and the honest other half of this check is looking at a screenshot — which
    /// this task did, on a booted simulator, in both appearances.
    static let mapGrounds: [(name: String, color: Color)] = [
        ("map paper", CypressColor.surfaceMapPaper),
        ("map grid", CypressColor.surfaceMapGrid),
        ("street band", CypressColor.surfaceMapStreetBand),
        ("park block", CypressColor.mapPark),
        ("park inset ring", CypressColor.mapParkRing),
        ("ocean", CypressColor.mapOceanStart),
        ("beach", CypressColor.mapBeach),
    ]

    /// The four slots, plus the two marks that are drawn *on* them: the 3 pt ring that separates a pin
    /// from the ground, and the glyph inside it that carries the grouping without hue (RULINGS R8).
    static let speciesSlots: [(name: String, fill: Color)] = [
        ("slot A · plum", CypressColor.pinSpeciesA),
        ("slot B · lagoon", CypressColor.pinSpeciesB),
        ("slot C · iris", CypressColor.pinSpeciesC),
        ("slot D · cherry", CypressColor.pinSpeciesD),
    ]

    static let speciesOnTheMap: [Pair] = speciesSlots.flatMap { slot in
        mapGrounds.map { ground in
            Pair(
                what: "01 · \(slot.name) pin on the \(ground.name)",
                foreground: slot.fill,
                background: ground.color,
                floor: 3.0
            )
        }
    }

    /// The ring and the glyph both ride on the fill, so they are one pair each: `pinRingStroke` is
    /// white in light and `#0E1712` in dark, and `MapSpeciesGlyph` is drawn in the same token.
    static let speciesMarksOnTheirFills: [Pair] = speciesSlots.map { slot in
        Pair(
            what: "01 · the ring and glyph on the \(slot.name) pin",
            foreground: CypressColor.pinRingStroke,
            background: slot.fill,
            floor: 3.0
        )
    }

    @Test("every species pin clears AA on every map ground, in light")
    func speciesPinsInLight() {
        assertAll(Self.speciesOnTheMap + Self.speciesMarksOnTheirFills, Self.light, "light")
    }

    @Test("every species pin clears AA on every map ground, after dark")
    func speciesPinsInDark() {
        assertAll(Self.speciesOnTheMap + Self.speciesMarksOnTheirFills, Self.dark, "dark")
    }

    /// **The residual class must not be one of the four**, because Canopy green means "a street tree
    /// whose species is not being asserted" and the four slots mean "this species". A palette that
    /// drifted a slot toward the house green would turn the residual into a fifth group and make the
    /// encoding's one claim — same colour, same species — false.
    ///
    /// **Measured in OKLab ΔE, not in WCAG contrast**, and the distinction is the point. WCAG
    /// contrast is a luminance ratio, so two colours of the same lightness and opposite hue read as
    /// 1.0:1 — it is the right tool for "can I see this mark against that ground" and the wrong one
    /// for "can I tell these two marks apart". Every separation claim the palette makes is a ΔE, and
    /// the floor is 0.09: four and a half times the ~0.02 just-noticeable difference, and just under
    /// the 0.099 the palette search actually achieved. See the note above `CypressColor.pinSpeciesA`.
    @Test("no species slot can be read as the plain city pin, the amber pin, a badge or the GPS dot")
    func slotsStayOutOfTheReservedFills() {
        let reserved: [(String, Color)] = [
            ("the plain city pin (the residual class)", CypressColor.pinFill),
            ("the amber pin (\"this tree needs something\")", CypressColor.accentAmber),
            ("a cluster badge", CypressColor.ctaFill),
            ("the reader's own GPS dot", CypressColor.gpsDot),
            ("a memorial's grey", CypressColor.pinRemovedFill),
        ]
        for (appearance, traits) in [("light", Self.light), ("dark", Self.dark)] {
            for slot in Self.speciesSlots {
                for (what, colour) in reserved {
                    let separation = Self.deltaE(slot.fill, colour, traits)
                    #expect(
                        separation >= 0.09,
                        """
                        \(slot.name) is ΔE \(String(format: "%.3f", separation)) from \(what) in \
                        \(appearance). A species colour that can be taken for one of the map's \
                        existing fills lets a reader read a wrong answer off the map, which is the one \
                        thing the species palette search was constrained to prevent.
                        """
                    )
                }
            }
        }
    }

    /// …and the four are that far apart from **each other**, which is the claim "same colour, same
    /// species" rests on. A pair below the floor would mean two species a reader merges.
    @Test("the four species slots are pairwise distinguishable in both appearances")
    func slotsAreDistinguishableFromEachOther() {
        for (appearance, traits) in [("light", Self.light), ("dark", Self.dark)] {
            for (first, second) in Self.pairs(Self.speciesSlots) {
                let separation = Self.deltaE(first.fill, second.fill, traits)
                #expect(
                    separation >= 0.09,
                    """
                    \(first.name) and \(second.name) are ΔE \(String(format: "%.3f", separation)) apart \
                    in \(appearance). Two slots a reader cannot tell apart are one colour with two \
                    meanings, and the map would be asserting that two species are the same tree.
                    """
                )
            }
        }
    }

    private static func pairs<T>(_ items: [T]) -> [(T, T)] {
        items.indices.dropLast().flatMap { i in
            items.indices.dropFirst(i + 1).map { (items[i], items[$0]) }
        }
    }

    /// Euclidean distance in OKLab — the space ERRATA E8's derivation and the species palette search both
    /// work in. Written out here for the same reason `contrast` is: the design system carries no
    /// colour maths at runtime and does not need any.
    static func deltaE(_ a: Color, _ b: Color, _ traits: UITraitCollection) -> Double {
        func oklab(_ color: Color) -> (Double, Double, Double) {
            var r: CGFloat = 0, g: CGFloat = 0, bl: CGFloat = 0, alpha: CGFloat = 0
            UIColor(color).resolvedColor(with: traits).getRed(&r, green: &g, blue: &bl, alpha: &alpha)
            func linear(_ c: CGFloat) -> Double {
                let v = Double(c)
                return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            let (lr, lg, lb) = (linear(r), linear(g), linear(bl))
            let l = cbrt(0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb)
            let m = cbrt(0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb)
            let s = cbrt(0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb)
            return (
                0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
            )
        }
        let (l1, a1, b1) = oklab(a)
        let (l2, a2, b2) = oklab(b)
        return ((l1 - l2) * (l1 - l2) + (a1 - a2) * (a1 - a2) + (b1 - b2) * (b1 - b2)).squareRoot()
    }

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

    // MARK: - The text ramp, every rung against every ground

    /// **Every rung of the ramp on every surface it sits on, in both appearances.**
    ///
    /// Before RULINGS R1 this section could not exist: the bottom two rungs failed, so the suite
    /// asserted the one rung that cleared and listed the rest as known failures. R1 retinted them,
    /// and the assertion that replaces the listing is the strongest form of the same statement —
    /// *no* rung of the ramp is unreadable on *any* of the three grounds the app draws text on.
    ///
    /// `text.faint` is the 9–11 pt end: mono micro-labels, timestamps, month letters. Small text
    /// has no large-text exemption, so it takes the 4.5 floor like any other sentence, and it is
    /// still the row most likely to fail because it is chosen to recede.
    ///
    /// Three grounds and not two. R1 names the screen and the card, and the sheet is the third
    /// plane the app puts text on (09, 10, 15) — a rung that clears on the two named surfaces and
    /// fails on the sheet would be a ramp that fails, so it is measured here too.
    static let ramp: [Pair] = rungs.flatMap { rung in
        grounds.map { ground in
            Pair(
                what: "\(rung.name) on the \(ground.name)",
                foreground: rung.color,
                background: ground.color,
                floor: 4.5
            )
        }
    }

    /// The four rungs of the ramp, darkest last. The order is the assertion in `rampIsMonotonic`.
    static let rungs: [(name: String, color: Color)] = [
        ("text.faint", CypressColor.textFaint),
        ("text.muted", CypressColor.textMuted),
        ("text.body", CypressColor.textBody),
        ("text.ink", CypressColor.textInk),
    ]

    /// The three surfaces the app sets text on.
    static let grounds: [(name: String, color: Color)] = [
        ("screen", CypressColor.surfaceScreen),
        ("card", CypressColor.surfaceCard),
        ("sheet", CypressColor.surfaceSheet),
    ]

    @Test("every rung of the text ramp clears AA in light")
    func rampInLight() { assertAll(Self.ramp, Self.light, "light") }

    @Test("every rung of the text ramp clears AA in dark")
    func rampInDark() { assertAll(Self.ramp, Self.dark, "dark") }

    /// The grounds that are not one of the three surfaces, and that R1 was written without —
    /// E106's sweep did not reach any of them, so RULINGS R1a closed them one at a time.
    ///
    /// Screen 04 is the reason this section exists. It is dark whether or not the phone is, and it
    /// draws its micro-labels in `CypressColor.Dark.*`, the flat forced-dark palette. R1 retinted
    /// the resolving token and left that palette transcribed, which made the same label legible
    /// when the phone was in dark mode and illegible when the *screen* was dark — R1's own
    /// argument, that the ramp is every micro-label in the app rather than one badge, failing on
    /// its own terms. Both appearances are asserted because a flat token that starts resolving is
    /// itself a defect worth catching.
    static let offSurface: [Pair] = [
        Pair(what: "C20 search placeholder on the fill it is drawn on (01)",
             foreground: CypressColor.searchGlyph, background: searchFillOverMap, floor: 4.5),
        Pair(what: "text.faint in 14's empty photo well",
             foreground: CypressColor.textFaint, background: CypressColor.surfaceEmptyThumb, floor: 4.5),
        Pair(what: "text.muted in 14's empty photo well",
             foreground: CypressColor.textMuted, background: CypressColor.surfaceEmptyThumb, floor: 4.5),
        Pair(what: "04 · Dark.textFaint note-field prompt on Dark.surfaceCardAlt",
             foreground: CypressColor.Dark.textFaint, background: CypressColor.Dark.surfaceCardAlt, floor: 4.5),
        Pair(what: "04 · Dark.textFaint on the camera tray",
             foreground: CypressColor.Dark.textFaint, background: CypressColor.Dark.bgCameraTray, floor: 4.5),
        Pair(what: "04 · Dark.textFaint on the camera shell",
             foreground: CypressColor.Dark.textFaint, background: CypressColor.Dark.bgCamera, floor: 4.5),
        Pair(what: "04 · Dark.textMuted offline line on the camera tray",
             foreground: CypressColor.Dark.textMuted, background: CypressColor.Dark.bgCameraTray, floor: 4.5),
    ]

    @Test("the grounds R1 was written without clear AA in light")
    func offSurfaceInLight() { assertAll(Self.offSurface, Self.light, "light") }

    @Test("the grounds R1 was written without clear AA in dark")
    func offSurfaceInDark() { assertAll(Self.offSurface, Self.dark, "dark") }

    /// `text.faintAlt` is not a rung — it is a second footnote colour that sits between `faint`
    /// and `muted` — but it is text on the same grounds and takes the same floor.
    @Test("text.faintAlt clears AA on every ground, in both appearances")
    func faintAltClearsAA() {
        for (appearance, traits) in [("light", Self.light), ("dark", Self.dark)] {
            for ground in Self.grounds {
                let ratio = Self.contrast(
                    Self.hex(CypressColor.textFaintAlt, traits),
                    Self.hex(ground.color, traits)
                )
                #expect(
                    ratio >= 4.5,
                    "text.faintAlt is \(String(format: "%.2f", ratio)):1 on the \(appearance) \(ground.name)"
                )
            }
        }
    }

    /// **The ramp is a ramp.** Four rungs that each clear 4.5 are not yet a ramp — four rungs at
    /// 4.6, 4.7, 4.8 and 4.9 would pass every assertion above and be one colour with four names.
    /// So the ordering is pinned as well as the floors: contrast strictly increases from `faint`
    /// to `ink` on every ground in both appearances, which is what makes it impossible for a
    /// future edit to collapse two rungs into each other quietly. R1 re-spaced the ramp precisely
    /// because lifting `faint` to exactly 4.5 would have left it 0.12 from `muted`.
    @Test("the ramp is monotonic — faint < muted < body < ink, on every ground")
    func rampIsMonotonic() {
        for (appearance, traits) in [("light", Self.light), ("dark", Self.dark)] {
            for ground in Self.grounds {
                let measured = Self.rungs.map { rung in
                    (rung.name, Self.contrast(Self.hex(rung.color, traits), Self.hex(ground.color, traits)))
                }
                for (lower, upper) in zip(measured, measured.dropFirst()) {
                    #expect(
                        lower.1 < upper.1,
                        """
                        \(lower.0) is \(String(format: "%.2f", lower.1)):1 and \(upper.0) is \
                        \(String(format: "%.2f", upper.1)):1 on the \(appearance) \(ground.name). \
                        The rung above must read as above: two adjacent rungs at the same contrast \
                        are one colour with two names, which is what RULINGS R1 re-spaced the ramp \
                        to prevent.
                        """
                    )
                }
            }
        }
        // …and `faintAlt` keeps the place between the two bottom rungs that §1.2 gave it. Not
        // strict at both ends: D3 documents one dark faint, so `faint` and `faintAlt` are the same
        // colour after dark and were before R1 too.
        for (appearance, traits) in [("light", Self.light), ("dark", Self.dark)] {
            for ground in Self.grounds {
                let value = { (color: Color) in
                    Self.contrast(Self.hex(color, traits), Self.hex(ground.color, traits))
                }
                let (faint, alt, muted) = (
                    value(CypressColor.textFaint), value(CypressColor.textFaintAlt), value(CypressColor.textMuted)
                )
                #expect(
                    faint <= alt && alt < muted,
                    """
                    text.faintAlt is \(String(format: "%.2f", alt)):1 on the \(appearance) \
                    \(ground.name), outside faint \(String(format: "%.2f", faint)) … muted \
                    \(String(format: "%.2f", muted)). The footnote colour sits between the two \
                    bottom rungs; a footnote that reads as a caption or as a micro-label is a rung \
                    the ramp does not have.
                    """
                )
            }
        }
    }

    /// R1's re-spacing, as its own assertion: `text.muted` is not merely above the floor, it is at
    /// 6.0 — a rung visibly above a `text.faint` that now sits at 4.5. Separated from the
    /// monotonicity check because the two fail for different reasons and want different messages:
    /// this one fails when someone lifts `faint` without lifting what is above it.
    @Test("text.muted is a rung above faint, not a hair above it")
    func mutedIsARungAbove() {
        for (appearance, traits) in [("light", Self.light), ("dark", Self.dark)] {
            for ground in Self.grounds {
                let ratio = Self.contrast(
                    Self.hex(CypressColor.textMuted, traits),
                    Self.hex(ground.color, traits)
                )
                #expect(
                    ratio >= 6.0,
                    """
                    text.muted is \(String(format: "%.2f", ratio)):1 on the \(appearance) \
                    \(ground.name); RULINGS R1 puts it at 6.0 so the ramp reads 4.5 / 6.0 / 8 / 14.
                    """
                )
            }
        }
    }

    // MARK: - The retint, measured and pinned

    /// **What RULINGS R1 moved, held to the value it now measures at.**
    ///
    /// E106 found these failing and reported them rather than fixing them, on the rule that a hex
    /// transcribed from SCREENS.md §1.2 may not be changed — changing it overrules the designer,
    /// and ARCHITECTURE §5.8 says an unanswered question is a question for design rather than a
    /// value to pick. R1 is that answer, made under a written delegation, and it changes five of
    /// them. `CypressColor.overruled(light:dark:)` carries the claim; `Tools/retint_ramp.py`
    /// reproduces the arithmetic; `CypressColor.overruledTokens` puts them in front of a designer
    /// in one screen.
    ///
    /// They are pinned exactly as the failures below are, and for the same reason: **a number that
    /// gets better without a ruling is as much a defect as one that gets worse.** The ±0.05 is not
    /// a tolerance on the retint, it is the mechanism that makes an unannounced token change loud
    /// in either direction. Both before and after are recorded on every row so the diff that
    /// changes one has to say what it is undoing.
    struct Pin {
        let what: String
        let foreground: Color
        let background: Color
        /// The ratio now, in each appearance, to ±0.05.
        let light: Double
        let dark: Double
        /// What it read before R1, and why it moved — or, for a known failure, why it did not.
        let because: String
    }

    static let retinted: [Pin] = [
        Pin(
            what: "C23 series 1 (Canopy) on a dark card",
            foreground: CypressColor.chartSeriesPrimary, background: CypressColor.surfaceCard,
            light: 6.29, dark: 3.05,
            because: "R8/E122: dark lifted lightness-only #2F6B4F→#3C785B; no dash — 13's series are "
                + "text-labelled strips, already distinct without hue"
        ),
        Pin(
            what: "C23 series 3 (Bark) on a dark card",
            foreground: CypressColor.chartSeriesTertiary, background: CypressColor.surfaceCard,
            light: 7.01, dark: 3.06,
            because: "R8/E122: dark lifted lightness-only #7A4F33→#8F6346"
        ),
        Pin(
            what: "C10 species-tile locked glyph on its fill",
            foreground: CypressColor.speciesTileLockedGlyph, background: CypressColor.speciesTileLockedFill,
            light: 3.06, dark: 3.05,
            because: "R8: was 1.84 / 2.12; #A8B29C ↔ #4C584B → #7F8974 ↔ #647062 — E8 called the `?` "
                + "decorative, but it is the locked tile's only visible content"
        ),
        Pin(
            what: "text.faint micro-label on the screen",
            foreground: CypressColor.textFaint, background: CypressColor.surfaceScreen,
            light: 4.62, dark: 5.33,
            because: "R1: was 2.90 light / 3.42 dark; #8B9482 ↔ #5F6F61 → #697260 ↔ #7E8F80"
        ),
        Pin(
            what: "text.faint micro-label on a card",
            foreground: CypressColor.textFaint, background: CypressColor.surfaceCard,
            light: 5.03, dark: 4.64,
            because: "R1: was 3.16 light / 2.98 dark — the card was the ground E8's transform moved the wrong way"
        ),
        Pin(
            what: "text.faintAlt footnote on the screen",
            foreground: CypressColor.textFaintAlt, background: CypressColor.surfaceScreen,
            light: 5.40, dark: 5.33,
            because: "R1: was 3.67 light / 3.42 dark; placed between faint and muted rather than on the floor"
        ),
        Pin(
            what: "text.faintAlt footnote on a card",
            foreground: CypressColor.textFaintAlt, background: CypressColor.surfaceCard,
            light: 5.87, dark: 4.64,
            because: "R1: was 3.99 light / 2.98 dark"
        ),
        Pin(
            what: "text.muted caption on the screen",
            foreground: CypressColor.textMuted, background: CypressColor.surfaceScreen,
            light: 6.21, dark: 6.97,
            because: "R1: was 4.62 light; the dark half already cleared 6.0 and was not overruled"
        ),
        Pin(
            what: "text.muted caption on a card",
            foreground: CypressColor.textMuted, background: CypressColor.surfaceCard,
            light: 6.75, dark: 6.06,
            because: "R1: was 5.02 light; dark is the documented #94A496, untouched"
        ),
        Pin(
            what: "estimated badge text on its fill (C12, 03/11/W1)",
            foreground: CypressColor.estimatedBadgeText, background: CypressColor.estimatedBadgeFill,
            light: 4.64, dark: 6.11,
            because: "R1: was 4.19 light — a third of a point, with D7's meaning hanging off it"
        ),
        Pin(
            what: "C24 attention card border on the card it identifies (12, 17)",
            foreground: CypressColor.amberAttentionCardBorder, background: CypressColor.surfaceCard,
            light: 3.39, dark: 6.57,
            because: "R1: was 2.30 light; the border is the only thing distinguishing this card"
        ),
        Pin(
            what: "C24 attention card border against the page behind it (12, 17)",
            foreground: CypressColor.amberAttentionCardBorder, background: CypressColor.surfaceScreen,
            light: 3.12, dark: 7.55,
            because: "R1: was 2.12 light; a boundary is adjacent to a surface on each side of it"
        ),
        // R1a · the three grounds R1 was written without, because E106's sweep did not reach them.
        Pin(
            what: "C20 search placeholder on the fill it is drawn on (01)",
            foreground: CypressColor.searchGlyph, background: searchFillOverMap,
            light: 4.63, dark: 6.06,
            because: "R1a: was 3.93 light; it wore text.faintAlt's retired hex by coincidence, on the default screen"
        ),
        Pin(
            what: "04 · Dark.textFaint note-field prompt on Dark.surfaceCardAlt",
            foreground: CypressColor.Dark.textFaint, background: CypressColor.Dark.surfaceCardAlt,
            light: 4.66, dark: 4.66,
            because: "R1a: was 2.99; the forced-dark half of the ramp, one value in both appearances because 04 is dark by design"
        ),
        Pin(
            what: "04 · Dark.textFaint on the camera tray",
            foreground: CypressColor.Dark.textFaint, background: CypressColor.Dark.bgCameraTray,
            light: 5.03, dark: 5.03,
            because: "R1a: was 3.23"
        ),
        Pin(
            what: "text.faint in 14's empty photo well",
            foreground: CypressColor.textFaint, background: CypressColor.surfaceEmptyThumb,
            light: 4.83, dark: 4.64,
            because: "R1a: was 3.03 / 2.67, and 4.16 after R1 alone; closed by correcting surfaceEmptyThumb's derived dark to dark.surface.card, which needed no overrule"
        ),
        Pin(
            what: "text.muted in 14's empty photo well",
            foreground: CypressColor.textMuted, background: CypressColor.surfaceEmptyThumb,
            light: 6.49, dark: 6.06,
            because: "R1a: the same correction; 5.44 → 6.06 after dark, so the rung above faint clears 6.0 here too"
        ),
        // The two rungs R1 did not move, pinned with the rest so that "does not move" is a fact
        // the suite checks rather than a sentence in a ruling.
        Pin(
            what: "text.body on a card",
            foreground: CypressColor.textBody, background: CypressColor.surfaceCard,
            light: 9.37, dark: 7.94,
            because: "R1: does not move"
        ),
        Pin(
            what: "text.ink on a card",
            foreground: CypressColor.textInk, background: CypressColor.surfaceCard,
            light: 14.97, dark: 13.08,
            because: "R1: does not move"
        ),
    ]

    @Test("every ratio RULINGS R1 moved is still exactly where it was left")
    func retintedRatiosHaveNotMoved() { assertPinned(Self.retinted, "R1 retint") }

    // MARK: - The failures left in place, measured and pinned

    /// **Every AA failure this suite still finds, with its ratio, held to the value it was
    /// measured at.**
    ///
    /// R1 fixed five and left these deliberately, and the reason differs per group. The pinning is
    /// the same as above: the number getting worse fails here, and the number quietly getting
    /// *better* — somebody nudging a hex to clear a threshold without an ERRATA entry — fails here
    /// too.
    ///
    /// The three groups, and why each is a different question:
    ///
    /// 1. **The borders carry no contrast in light, as a house style rather than as a defect.**
    ///    `border.cool`, the default card edge on every screen, is 1.15:1 against the page. WCAG
    ///    1.4.11 only asks for 3:1 where a boundary is *required* to identify a component, and for
    ///    almost all of these it is not — a card is identified by the type in it. The 311 panel
    ///    has its own fill and its own amber body copy; the border is not what identifies it. The
    ///    one place a border *was* required is C24, and that one is fixed above.
    /// 2. **C23 and C10 both left this list** and are in `retinted`. R8 deferred C23 on a
    ///    measurement — the lightness move costs 38% of series 1's separation from series 2 — but
    ///    E122 found the premise wrong: `ActivityView` draws the three series as *text-labelled,
    ///    spatially separate strips* (`ChartSeriesLegend` names each, plus a VoiceOver label), so
    ///    they were never "separated by hue alone" and the pre-authorised dash solves a problem that
    ///    does not exist. C23 is therefore a plain lightness-only fix like C10, and both now pass at
    ///    3:1. C10's own story: E8 exempted the `?` as decorative — "the tile's meaning is in its
    ///    label" — and that was wrong, because `SpeciesTile`'s locked case draws the `?` and nothing
    ///    else and the label meant is `accessibilityLabel`, invisible to a sighted reader (E120).
    ///
    /// The empty photo well on 14 was a third group here and is not any more. It was the one text
    /// pair the R1 retint left failing, at 4.16 after dark, and it was not fixable in the token:
    /// lifting `text.faint` far enough to clear that ground would have put it 0.042 from
    /// `text.muted` in OKLCh lightness, inside the 0.075 step of the documented dark ladder, which
    /// is the rung collapse R1 re-spaced the ramp to prevent. R1a closed it from the other side
    /// instead — `surfaceEmptyThumb`'s dark value was *derived*, and E8's own rule is that a
    /// derived value may be corrected — so it needed no overrule at all. It is in `retinted`.
    typealias KnownFailure = Pin

    static let knownFailures: [KnownFailure] = [
        // 1 · The borders.
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
    ]

    @Test("every known contrast failure is still exactly the failure that was reported")
    func knownFailuresHaveNotMoved() { assertPinned(Self.knownFailures, "known failure") }

    // MARK: - The two pairs that are under 4.5 on purpose

    /// **Disabled controls, which WCAG 1.4.3 exempts** — "text or images of text that are part of
    /// an inactive user interface component" have no contrast requirement. Both of these ride on
    /// `text.faint` or its forced-dark twin, so both moved when R1 and R1a moved those tokens, and
    /// both are still under 4.5 on purpose.
    ///
    /// They are not in `offSurface` because asserting a floor on them would be asserting the wrong
    /// thing, and they are not in `knownFailures` because they are not failures. They are pinned,
    /// two-sided, for the reason everything here is pinned: the number moving in *either*
    /// direction means a token changed. RULINGS R1a declined to solve for either ground, on the
    /// ground that a disabled control which reads exactly as strongly as an enabled one is a
    /// different defect from an unreadable one — and it is the defect that this app, whose primary
    /// CTA is gated on having taken a photo, would actually ship.
    static let exemptByInactivity: [Pin] = [
        Pin(
            what: "09 · the disabled `Done` label on its fill (ctaDisabledLabel)",
            foreground: CypressColor.ctaDisabledLabel, background: CypressColor.ctaDisabledFill,
            light: 4.19, dark: 4.64,
            because: "1.4.3 exempts inactive components; it was 2.63 / 2.98 and moved because text.faint moved"
        ),
        Pin(
            what: "04 · the disabled `Log visit` label on Dark.surfaceThumb",
            foreground: CypressColor.Dark.textFaint, background: CypressColor.Dark.surfaceThumb,
            light: 4.16, dark: 4.16,
            because: "1.4.3 exempts inactive components; R1a left this ground out of the solve deliberately"
        ),
    ]

    @Test("the two deliberately-exempt pairs are where R1a left them")
    func exemptPairsHaveNotMoved() { assertPinned(Self.exemptByInactivity, "1.4.3-exempt pair") }

    // MARK: -

    /// One pinned ratio, both appearances, ±0.05 in **both** directions. The two-sided bound is
    /// the whole design of this suite: a `>= 4.5` assertion would let a token drift upward without
    /// anyone noticing, and an unannounced token change is the thing being caught, not an
    /// unreadable one. Do not loosen this and do not replace a pin with a floor.
    private func assertPinned(_ pins: [Pin], _ kind: String) {
        for pin in pins {
            let light = Self.contrast(Self.hex(pin.foreground, Self.light), Self.hex(pin.background, Self.light))
            let dark = Self.contrast(Self.hex(pin.foreground, Self.dark), Self.hex(pin.background, Self.dark))
            #expect(
                abs(light - pin.light) < 0.05,
                """
                \(pin.what) is \(String(format: "%.2f", light)):1 in light; this \(kind) was \
                recorded at \(pin.light):1. \(pin.because). If the value is being changed on \
                purpose, the ERRATA entry comes first.
                """
            )
            #expect(
                abs(dark - pin.dark) < 0.05,
                """
                \(pin.what) is \(String(format: "%.2f", dark)):1 after dark; this \(kind) was \
                recorded at \(pin.dark):1. \(pin.because).
                """
            )
        }
    }

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
