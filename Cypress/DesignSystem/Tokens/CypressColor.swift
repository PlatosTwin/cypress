//
//  CypressColor.swift
//  Cypress — DesignSystem/Tokens
//
//  Source of truth: docs/distilled/SCREENS.md §1.1 (brand palette), §1.2 (full color table).
//  Enforces docs/ARCHITECTURE.md §6: "Never write a raw hex ... inside a feature."
//
//  Naming: the doc's token names are transliterated to camelCase, dots removed, so any
//  property here can be traced straight back to a row in the table:
//      surface.screen  -> CypressColor.surfaceScreen
//      dark.accent.mint -> CypressColor.Dark.accentMint
//
//  Light and dark are ONE token. Every property below is a dynamic `Color` built from
//  `Color(UIColor { traits in ... })` so it resolves off the trait collection rather than
//  the SwiftUI environment — that means it is also correct inside `UIViewRepresentable`
//  (MapKit overlays, camera previews) where `@Environment(\.colorScheme)` is not available.
//
//  Every token declares where its dark value came from, and the constructor is the declaration:
//
//      dynamic(light:dark:)   the pair is transcribed from SCREENS.md — SPECIFIED.
//      derived(light:dark:)   the dark value was computed from the documented pairs — DERIVED.
//      overruled(light:dark:) the value was transcribed and is changed anyway — RULINGS R1.
//      escalated(_:)          the transform was run and rejected; still light-only, reason inline.
//      lightOnly(_:)          the token has no second appearance by definition (see below).
//
//  `derived` and `escalated` are both listed in `reviewTokens`, which TokenGallery renders as
//  its first two sections, so design review of ERRATA E8 is one screen rather than an audit of
//  the whole palette. Promoting a derived token to specified is one line: `derived` -> `dynamic`.
//  `DerivedTokenTests` fails if the registry and the live tokens disagree.
//
//  `lightOnly` is now reserved for tokens that genuinely have no second appearance: colour that
//  rides on imagery, colour on a screen that is dark regardless of the system setting (04),
//  the spec document's own page chrome, W1 web-only surfaces, and the six brand hues (whose
//  scheme-dependent roles are carried by the paired role tokens further down).
//
//  Screen 04 (camera) and D1–D3 are dark regardless of the system setting. Those views use
//  `CypressColor.Dark.*`, which is the flat, non-resolving dark palette.
//
//  How the derived values were obtained is documented in ERRATA E8. In one paragraph: the 55
//  documented pairs were analysed in OKLCh, which separates the three things a designer actually
//  moves — lightness, chroma, hue. Lightness is repositioned per *role* (a border does not
//  invert like a background); chroma is kept where there is chroma to keep and floored at
//  ~0.025 where there is not, because the dark palette is green-tinted black rather than grey
//  (D2's own caption says so); hue is preserved above C≈0.06 and pulled to the house green
//  ~150° below C≈0.02. The transform is a function of role AND value, never of value alone:
//  `#FFFFFF` has three documented dark counterparts and `#77836F` has two.
//

import SwiftUI
import UIKit

// MARK: - Hex helpers (internal to the design system)

extension UIColor {
    /// `#colorLiteral`-free hex initializer. `0xRRGGBB`, sRGB.
    /// Internal on purpose: features must go through `CypressColor`, never through a raw hex.
    convenience init(cypressHex hex: UInt32, alpha: CGFloat = 1) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255
        let g = CGFloat((hex >> 8) & 0xFF) / 255
        let b = CGFloat(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: alpha)
    }
}

extension Color {
    /// `#colorLiteral`-free hex initializer. `0xRRGGBB`, sRGB.
    /// Internal on purpose — see `UIColor.init(cypressHex:alpha:)`.
    init(cypressHex hex: UInt32, alpha: Double = 1) {
        self.init(uiColor: UIColor(cypressHex: hex, alpha: alpha))
    }
}

// MARK: - CypressColor

enum CypressColor {

    // MARK: Scheme resolution

    /// Pairs a light hex with its documented dark counterpart into a single trait-resolving token.
    static func dynamic(
        light: UInt32,
        dark: UInt32,
        lightAlpha: Double = 1,
        darkAlpha: Double = 1
    ) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(cypressHex: dark, alpha: darkAlpha)
                : UIColor(cypressHex: light, alpha: lightAlpha)
        })
    }

    /// A token with no second appearance by definition — it rides on imagery, it lives on a
    /// screen that is dark regardless of the system setting, it belongs to the spec document or
    /// to W1, or it is a raw brand hue whose scheme-dependent roles are carried by the paired
    /// role tokens. Resolves to the same value in both schemes deliberately.
    static func lightOnly(_ hex: UInt32, alpha: Double = 1) -> Color {
        Color(cypressHex: hex, alpha: alpha)
    }

    /// A pair whose dark half was **derived** from the documented pairs, not transcribed
    /// (ERRATA E8, ROADMAP §3). Identical in behaviour to `dynamic` — the difference is the
    /// claim being made, and that claim is what `reviewTokens` collects for design review.
    ///
    /// When a designer corrects one of these, change `derived` to `dynamic` and drop its line
    /// from `reviewTokens`. The test enforces that the two stay in step.
    static func derived(
        light: UInt32,
        dark: UInt32,
        lightAlpha: Double = 1,
        darkAlpha: Double = 1
    ) -> Color {
        dynamic(light: light, dark: dark, lightAlpha: lightAlpha, darkAlpha: darkAlpha)
    }

    /// A token the transform was run on and **rejected** — it stays light-only, and the reason
    /// is on the line above it. Behaves exactly like `lightOnly`; the difference, again, is the
    /// claim. These are the tokens a designer must answer rather than merely check.
    static func escalated(_ hex: UInt32, alpha: Double = 1) -> Color {
        Color(cypressHex: hex, alpha: alpha)
    }

    /// A value that was **transcribed from SCREENS.md and is changed anyway**, under the written
    /// delegation recorded in `docs/RULINGS.md`. Behaviourally identical to `dynamic`; the claim
    /// is the difference, and it is the strongest claim in this file.
    ///
    /// E8 drew the line between a *transcribed* value, which may not be changed, and a *derived*
    /// one, which may be corrected. R1 adds the third case: a hex the designer wrote, replaced
    /// because it fails WCAG AA and the alternative was editing 61 call sites to route around it.
    /// Every one of these carries `RULINGS R1` and its measured before/after in the comment above
    /// it, so a designer can find every place their intent was substituted for and reverse it in
    /// one pass. There are five, they are listed in `overruledTokens`, and there should never be
    /// a sixth without another ruling.
    ///
    /// The retint itself is `Tools/retint_ramp.py` — lightness moves in OKLCh, chroma and hue are
    /// held, and each half is measured on every ground it is drawn on rather than assumed from
    /// the other half. Run it to reproduce any number below.
    static func overruled(
        light: UInt32,
        dark: UInt32,
        lightAlpha: Double = 1,
        darkAlpha: Double = 1
    ) -> Color {
        dynamic(light: light, dark: dark, lightAlpha: lightAlpha, darkAlpha: darkAlpha)
    }

    // MARK: - §1.1 Brand palette ("Palette · from the tree itself")
    //
    // Six named brand hues. SCREENS.md gives no dark counterpart for the hues themselves, and
    // none is derived for them: a brand hue has no single dark answer. D1 proves it — the same
    // `#2F6B4F` becomes `#6FAE8C` as a pin, `#8EC3A5` as a selection, and stays `#2F6B4F` as the
    // "You" avatar fill. The scheme-dependent roles are carried by the paired role tokens
    // (`ctaFill`, `pinFill`, `selectionFill`, `accentAmber`), which is where a caller belongs.

    /// Cypress Deep `#1D4634` — primary buttons, active nav, cluster badges, dark header.
    static let cypressDeep = lightOnly(0x1D4634)
    /// Swatch text color that rides on Cypress Deep — `#DFE8D6`.
    static let onCypressDeep = lightOnly(0xDFE8D6)

    /// Canopy `#2F6B4F` — links, selection borders, pins, selected chips.
    static let canopy = lightOnly(0x2F6B4F)
    /// Swatch text color that rides on Canopy — `#E8F0E4`.
    static let onCanopy = lightOnly(0xE8F0E4)

    /// New Growth `#4E8F6A` — secondary accents, avatars, dark-mode CTA fill on 04.
    static let newGrowth = lightOnly(0x4E8F6A)
    /// Swatch text color that rides on New Growth — `#10281C`.
    static let onNewGrowth = lightOnly(0x10281C)

    /// Bark `#7A4F33` — third-series charts, avatar accent.
    static let bark = lightOnly(0x7A4F33)
    /// Swatch text color that rides on Bark — `#F2E6DA`.
    static let onBark = lightOnly(0xF2E6DA)

    /// Fog `#F5F6EF` — mobile screen background. Same value as `surface.screen`.
    static let fog = dynamic(light: 0xF5F6EF, dark: 0x0E1712)
    /// Swatch text color that rides on Fog — `#3C4A3E`. Same value as `text.body`.
    static let onFog = dynamic(light: 0x3C4A3E, dark: 0xAEBBAB)

    /// Signal Amber `#B4711F` — reserved solely for "this tree needs something".
    /// Dark counterpart is `dark.accent.amber`.
    static let signalAmber = dynamic(light: 0xB4711F, dark: 0xD99A4E)

    // MARK: - §1.2 Surfaces

    /// `page.parchment` `#EBE8DC` — `body` background of the spec page itself (not app UI).
    static let pageParchment = lightOnly(0xEBE8DC)

    /// `surface.screen` `#F5F6EF` ↔ `dark.bg.screen` `#0E1712` — mobile screen background.
    static let surfaceScreen = dynamic(light: 0xF5F6EF, dark: 0x0E1712)

    /// `surface.card` `#FFFFFF` ↔ `dark.surface.card` `#18251D` — cards, stat cards, list rows.
    static let surfaceCard = dynamic(light: 0xFFFFFF, dark: 0x18251D)

    /// `surface.sheet` `#FDFDF8` ↔ **derived** `#18251D` — bottom sheets (09, 10, 15).
    ///
    /// The headline glare in ERRATA E8: a near-white sheet over a dimmed dark screen. Snapped to
    /// `dark.surface.card`, which is where the documented transform puts every raised plane —
    /// `surface.card`, the hero back circle, the search bar and the glass filter chip all land on
    /// `#18251D` from four different light values. A sheet is a raised plane.
    static let surfaceSheet = derived(light: 0xFDFDF8, dark: 0x18251D)

    /// `surface.warmPanel` `#F7F5EC` — spec-page palette/type panels (not app UI).
    static let surfaceWarmPanel = lightOnly(0xF7F5EC)

    /// `surface.web` `#FBFBF5` — W1 web header + fact column. W1 is out of scope for iOS.
    static let surfaceWeb = lightOnly(0xFBFBF5)

    /// `surface.mapPaper` `#E9E5D4` ↔ `dark.bg.map` `#141E16` — map canvas ground (01, 15).
    static let surfaceMapPaper = dynamic(light: 0xE9E5D4, dark: 0x141E16)

    /// `surface.mapGrid` `#F7F4E6` ↔ `dark.map.grid` `#1C2A1F` — map street grid stripes.
    static let surfaceMapGrid = dynamic(light: 0xF7F4E6, dark: 0x1C2A1F)

    /// `surface.mapStreetBand` `#FAF7EC` ↔ `dark.map.street` `#232F24` — named street bands on 01.
    static let surfaceMapStreetBand = dynamic(light: 0xFAF7EC, dark: 0x232F24)

    /// `surface.routeMap` `#E4E9D3` ↔ **derived** `#141E16` — mini route map on 18.
    ///
    /// 18's map is the same object as 01's at a smaller size, so it takes 01's dark ground
    /// (`dark.bg.map`) rather than a transformed value. Same for its grid and its border below.
    static let surfaceRouteMap = derived(light: 0xE4E9D3, dark: 0x141E16)
    /// `surface.routeMap` border `#DBE0CB` ↔ **derived** `dark.border.alt` `#2B3A2C` (D1's map border).
    static let borderRouteMap = derived(light: 0xDBE0CB, dark: 0x2B3A2C)
    /// `surface.routeMap` grid `#F4F1E2` ↔ **derived** `dark.map.grid` `#1C2A1F`.
    static let surfaceRouteMapGrid = derived(light: 0xF4F1E2, dark: 0x1C2A1F)

    /// `surface.emptyThumb` `#FAFBF4` ↔ **derived** `dark.surface.card` `#18251D` — cold-start
    /// empty photo well (14).
    ///
    /// **Corrected derivation** (RULINGS R1a, ERRATA E108), from `dark.surface.thumb` `#1F2E22`.
    /// Not an overrule and it needs none: E8's own rule is that a transcribed value may not be
    /// changed and a *derived* one may be corrected, and only the assignment was ever derived here.
    ///
    /// The original read this as a recess inside a card, which is what `dark.surface.thumb` is for
    /// — D2 puts the activity thumb base there. But 14's well is not inside a card; it is a dashed
    /// well sitting directly on the screen, and its light value `#FAFBF4` is a card-level plane,
    /// paler than `surface.screen` rather than darker. `surfaceShareCard` `#FAF8EF` is the same
    /// light value to within a step and E8 derived *it* onto `dark.surface.card` on exactly that
    /// reading. The thumb rung is lighter than the card rung, so the old value made this the one
    /// ground in the app where the R1 caption ramp still failed: `text.faint` on it read 2.67
    /// before R1, 4.16 after, and **4.64** here. `text.muted` goes 5.44 → 6.06 with it.
    static let surfaceEmptyThumb = derived(light: 0xFAFBF4, dark: 0x18251D)

    /// `surface.skeleton` `#E3E8D9` ↔ **derived** `#27352B` — skeleton blocks behind sheets (09, 10).
    ///
    /// The strongest derivation in the set: `#E3E8D9` is the *same light hex* as `border.cool`,
    /// whose dark counterpart `#27352B` is documented. The role differs (a fill, not a hairline),
    /// so it is derived rather than transcribed, but the number is the designer's own.
    static let surfaceSkeleton = derived(light: 0xE3E8D9, dark: 0x27352B)

    // MARK: - §1.2 Borders and hairlines

    /// `border.cool` `#E3E8D9` ↔ `dark.border` `#27352B` — default card / chip / row border.
    static let borderCool = dynamic(light: 0xE3E8D9, dark: 0x27352B)

    /// `border.warm` `#DDD9C9` — spec-page panel border (not app UI).
    static let borderWarm = lightOnly(0xDDD9C9)

    /// `border.hairline` `#D8D4C4` — spec-page header/footer rule (not app UI).
    static let borderHairline = lightOnly(0xD8D4C4)

    /// `border.dashed` `#C9D1BC` ↔ **derived** `#353F34` — optional-field dashed wells (05, 06, 09).
    ///
    /// ERRATA E8 names this one: light-only, it was the brightest element on the dark check-in
    /// screen — a hairline outshining the mint CTA. D3 could not settle it, because D3 drops the
    /// optional well entirely. Derived from the border rule fitted on the three documented border
    /// pairs (`border.cool`, the park inset ring, the street-band ring), which reproduces all
    /// three to within 0.005 in OKLab. It lands one step above `dark.border`, which is exactly
    /// where it sits relative to `border.cool` in light.
    static let borderDashed = derived(light: 0xC9D1BC, dark: 0x353F34)

    /// `border.dashedStrong` `#C4CEB4` ↔ **derived** `#364133` — empty photo well (14), `2px dashed`.
    /// Same border rule; keeps its one-step lead over `border.dashed`.
    static let borderDashedStrong = derived(light: 0xC4CEB4, dark: 0x364133)

    /// `border.sheetGrabber` `#DDE2D2` ↔ **derived** `dark.border.alt` `#2B3A2C` — 40×5 grabber pill.
    /// The border rule lands within 0.014 of the documented `#2B3A2C`, so the documented hex is
    /// used rather than a minted one.
    static let borderSheetGrabber = derived(light: 0xDDE2D2, dark: 0x2B3A2C)

    /// `border.web.row` `#E9ECDE` — W1 fact-row separators. W1 is out of scope for iOS.
    static let borderWebRow = lightOnly(0xE9ECDE)

    /// `border.calloutGreen` `#DFE6CD` ↔ `#27352B` — green callout border.
    ///
    /// §1.2 gives no dark counterpart; D2's delta list does, in prose: "Recognize-it callout:
    /// fill `#1A241A`, border `1px #27352B`". Same miss as `text.faintAlt` (E27) and the taped
    /// badge (E8) — a dark value stated in a screen's prose and absent from the table.
    static let borderCalloutGreen = dynamic(light: 0xDFE6CD, dark: 0x27352B)

    /// `border.calloutGradient` `#D9E3C8` — "In July" / "New species!" gradient callout border.
    ///
    /// **Escalated.** It bounds `calloutGradient`, which has no dark counterpart anywhere in
    /// SCREENS.md and is not derivable — a two-stop gradient is a drawing, not a value. Darkening
    /// the border while the fill it bounds stays light would be worse than leaving both alone.
    /// Moves the day the gradient does.
    static let borderCalloutGradient = escalated(0xD9E3C8)

    /// `border.amberSoft` `#EBD3A8` ↔ **derived** `dark.accent.amber` `#D99A4E` — amber pill borders.
    ///
    /// The dark palette contains exactly two ambers: `#D99A4E` for the mark and `#2E271A` for the
    /// ground it sits on. D1 maps the amber pin onto the first and D2 maps the `est.` badge onto
    /// both, so every amber in the dark is one of the two. The border rule was run here and
    /// rejected: fitted on neutral hairlines it extrapolates a chromatic amber to `#44361A`, a
    /// brown 0.40 away in OKLab from the only amber the dark palette has — see ERRATA E8.
    ///
    /// The cost of the collapse, and the question it hands back: light has three amber border
    /// weights (`soft` / `strong` / `mid`) and dark now has one, so the amber pill, the selected
    /// amber chip and the 311 panel no longer differ by border weight after dark.
    static let borderAmberSoft = derived(light: 0xEBD3A8, dark: 0xD99A4E)

    /// `border.amberMid` `#D9A05B` ↔ **derived** `dark.accent.amber` `#D99A4E` — attention card
    /// border (`1.5px`). This one barely moves: `#D9A05B` is 0.016 from `#D99A4E` in OKLab, so
    /// the light attention border was already sitting on the dark amber.
    static let borderAmberMid = derived(light: 0xD9A05B, dark: 0xD99A4E)

    /// `border.amberStrong` `#E0B070` ↔ **derived** `dark.accent.amber` `#D99A4E` — 311 hazard
    /// panel border (`1.5px`). See `borderAmberSoft`.
    static let borderAmberStrong = derived(light: 0xE0B070, dark: 0xD99A4E)

    /// `border.memorial` `#C4C8B8` ↔ **derived** `#39423A` — memorial banner border (`1.5px`).
    /// Border rule; keeps its one step above the banner fill.
    static let borderMemorial = derived(light: 0xC4C8B8, dark: 0x39423A)

    /// `border.account` `#D8DECB` ↔ **derived** `dark.border.alt` `#2B3A2C` — account sheet
    /// secondary buttons (`1.5px`). Border rule, within 0.012 of the documented hex.
    static let borderAccount = derived(light: 0xD8DECB, dark: 0x2B3A2C)

    /// `border.shareCard` `#E0DDC9` ↔ **derived** `dark.border.alt` `#2B3A2C` — share preview card.
    /// Border rule, within 0.011 of the documented hex.
    static let borderShareCard = derived(light: 0xE0DDC9, dark: 0x2B3A2C)

    /// `border.pinRing` `rgba(29,70,52,.14)` ↔ `#2B3A2C` — gradient thumbnail hairline.
    ///
    /// §1.2 gives no dark counterpart; D1's delta table does: "Card thumb … border `#2B3A2C`".
    /// The dark value is opaque, exactly as `searchBorder` and `tabBarTopBorder` already are.
    static let borderPinRing = dynamic(light: 0x1D4634, dark: 0x2B3A2C, lightAlpha: 0.14)

    /// `border.glass` `rgba(29,70,52,.10)` ↔ `#2B3A2C` — search bar edge.
    /// D1: "Search bar … `rgba(24,37,29,.94)`, border `#2B3A2C`".
    static let borderGlassSearch = dynamic(light: 0x1D4634, dark: 0x2B3A2C, lightAlpha: 0.10)
    /// `border.glass` `rgba(29,70,52,.12)` ↔ `#2B3A2C` — filter chip edge.
    /// D1: "Filter chip off … `rgba(24,37,29,.92)`, border `#2B3A2C`".
    static let borderGlassChip = dynamic(light: 0x1D4634, dark: 0x2B3A2C, lightAlpha: 0.12)
    /// `border.glass` `rgba(29,70,52,.08)` ↔ `#26332A` — bottom bar top edge.
    /// D1: "Tab bar … `rgba(16,24,18,.95)`, top border `#26332A`".
    static let borderGlassBottomBar = dynamic(light: 0x1D4634, dark: 0x26332A, lightAlpha: 0.08)

    // MARK: - §1.2 Text

    /// `text.ink` `#1C2A21` ↔ `dark.text.primary` `#E4EBE2` — primary text, headings.
    static let textInk = dynamic(light: 0x1C2A21, dark: 0xE4EBE2)

    /// `text.body` `#3C4A3E` ↔ `dark.text.secondary` `#AEBBAB` — secondary body, unselected chips.
    static let textBody = dynamic(light: 0x3C4A3E, dark: 0xAEBBAB)

    /// `text.muted` — **overruled** to `#535F4C`, from §1.2's `#66735F`. Dark keeps the documented
    /// `dark.text.muted` `#94A496`. Captions, Latin names, sublabels.
    ///
    /// **RULINGS R1** (ERRATA E108). This is the rung above `text.faint`, and it moves because
    /// `text.faint` moves: at §1.2's value it read 4.62:1 on the screen, which is 0.12 above the
    /// AA floor a retinted `text.faint` now sits on, and two rungs 0.12 apart are one rung with
    /// two names. R1 puts it at 6.0 so the ramp reads 4.5 / 6.0 / 8 / 14.
    ///
    /// Measured: **4.62 → 6.21** on the screen and **5.02 → 6.75** on a card, in light. The dark
    /// half is not touched — `#94A496` already reads 6.97 on the dark screen and 6.06 on a dark
    /// card, so it clears R1's 6.0 without an overrule, and three derived badge labels point at
    /// `dark.text.muted` by name. An overrule is spent where it is needed and nowhere else.
    static let textMuted = overruled(light: 0x535F4C, dark: 0x94A496)

    /// `text.faint` — **overruled** to `#697260` ↔ `#7E8F80`, from §1.2's `#8B9482` ↔ `#5F6F61`.
    /// Micro-labels, timestamps, mono meta.
    ///
    /// **RULINGS R1** (ERRATA E108). The finding E106 reported and did not fix: this token is 61
    /// call sites across 24 files — every mono micro-label, every timestamp, every meta line —
    /// and it failed AA in *both* appearances. R1 rules that the token moves rather than the call
    /// sites, so that the failure becomes unrepresentable instead of merely absent.
    ///
    /// Measured, on the two surfaces it is drawn on, in both appearances:
    ///
    ///     light   screen 2.90 → 4.62    card 3.16 → 5.03
    ///     dark    screen 3.42 → 5.33    card 2.98 → 4.64
    ///
    /// The dark half is measured, not inferred from the light one. E106's sharpest observation is
    /// that this token on a card was *worse* after dark (2.98) than in light (3.16) — the one
    /// place E8's transform moved a ratio the wrong way — and the two appearances do not even
    /// share a binding surface: the screen is the hard ground in light, the card in dark.
    static let textFaint = overruled(light: 0x697260, dark: 0x7E8F80)

    /// `text.faintAlt` — **overruled** to `#5D6855` ↔ `#7E8F80`, from §1.2's `#77836F` ↔ `#5F6F61`.
    /// Footnote lines under screens.
    ///
    /// §1.2 gives no dark counterpart, but D3's delta list does, in prose: "Footnote `#5F6F61`" —
    /// the same `dark.text.faint` value `textFaint` already carries. Transcribed as light-only
    /// originally, which is the same miss as the taped badge below. See ERRATA (E27).
    ///
    /// **RULINGS R1** (ERRATA E108). Measured **3.67 → 5.40** on the screen and 3.99 → 5.87 on a
    /// card in light; the dark half follows `textFaint` to `#7E8F80` and reads 5.33 / 4.64, so the
    /// two remain one colour after dark exactly as D3 wrote them.
    ///
    /// Its light value is not solved against the 4.5 floor. Solved that way it lands 0.03 from
    /// `textFaint` — R1's own objection to E106's fix, reappearing one rung lower — so instead it
    /// keeps the fraction of the faint→muted lightness interval §1.2 gave it (0.52, near enough
    /// the midpoint), reapplied to the two retinted ends. The three-rung spacing the designer drew
    /// survives the move.
    static let textFaintAlt = overruled(light: 0x5D6855, dark: 0x7E8F80)

    /// `text.onDark` `#FFFFFF` — on Cypress Deep / Canopy fills.
    ///
    /// **Escalated.** `#FFFFFF` is the clearest counterexample to a value-only transform: it has
    /// three documented dark counterparts — `#0E1712` under `ctaLabel`, `#18251D` under
    /// `surfaceCard`, `#DFE8D6` under `tabAvatarLetter` — 0.73 apart in OKLab. Which one applies
    /// depends on whether the fill beneath moves, and this token's three call sites disagree:
    /// the cluster count rides on `ctaFill` (D1 documents `#0E1712` for it), the phenology chip
    /// rides on `selectionFill` (for which `onSelectionFill` already exists), and the avatar
    /// letter rides on a fill D1 documents as unchanged. The fix is at those call sites, not
    /// here, so no dark value is put on the token.
    static let textOnDark = escalated(0xFFFFFF)

    /// `text.onPhoto` `#EAF2E6` (03) — text over a hero gradient.
    /// The onPhoto family is scheme-independent by definition: it rides on imagery.
    static let textOnPhoto = lightOnly(0xEAF2E6)
    /// `text.onPhoto` `#F0F5EC` (07).
    static let textOnPhotoSpecies = lightOnly(0xF0F5EC)
    /// `text.onPhoto` `#EFF1EA` (19, memorial).
    static let textOnPhotoMemorial = lightOnly(0xEFF1EA)
    /// `text.onPhoto` `#EFF5EA` (W1). W1 is out of scope for iOS; kept for completeness.
    static let textOnPhotoWeb = lightOnly(0xEFF5EA)

    /// `text.mapLabel` street `#98A388` ↔ `dark.map.label` street `#5C6B57`.
    static let textMapLabelStreet = dynamic(light: 0x98A388, dark: 0x5C6B57)
    /// `text.mapLabel` park `#7A9C64` ↔ `dark.map.label` park `#557A50`.
    static let textMapLabelPark = dynamic(light: 0x7A9C64, dark: 0x557A50)
    /// `text.mapLabel` ocean `#5F8C84` ↔ `dark.map.label` ocean `#4E7A74`.
    static let textMapLabelOcean = dynamic(light: 0x5F8C84, dark: 0x4E7A74)

    // MARK: - §1.2 Semantic / status

    /// Thriving badge fill — light `#E2EFE2` ↔ dark `#1F3A2C` (01, 03, D1, D2).
    static let thrivingBadgeFill = dynamic(light: 0xE2EFE2, dark: 0x1F3A2C)
    /// Thriving badge text — light `#28623F` ↔ dark `#8EC3A5`.
    static let thrivingBadgeText = dynamic(light: 0x28623F, dark: 0x8EC3A5)

    /// `taped` method badge fill `#E2EFE2` ↔ `#1F3A2C` (03, 11, W1).
    ///
    /// SCREENS.md D2 states it outright: "both method badges keep their meaning in the dark …
    /// `taped` → `#8EC3A5` on `#1F3A2C`" — the same pair as the thriving badge. Transcribed as
    /// light-only originally; two agents independently hit it rendering screen D2.
    static let tapedBadgeFill = dynamic(light: 0xE2EFE2, dark: 0x1F3A2C)
    /// `taped` method badge text `#28623F` ↔ `#8EC3A5`. Same D2 sentence.
    static let tapedBadgeText = dynamic(light: 0x28623F, dark: 0x8EC3A5)

    /// `est.` / `estimated` badge fill `#F1EAD8` ↔ `dark.accent.amberBg` `#2E271A`.
    static let estimatedBadgeFill = dynamic(light: 0xF1EAD8, dark: 0x2E271A)
    /// `est.` / `estimated` badge text — **overruled** to `#836324` in light, from §1.2's
    /// `#8A6A2A`. Dark keeps `dark.accent.amber` `#D99A4E`.
    ///
    /// **RULINGS R1** (ERRATA E108). It missed AA by a third of a point — **4.19 → 4.64** on
    /// `estimatedBadgeFill`, against a 4.5 floor — and it is the pair with meaning hanging off it:
    /// D7 makes "estimated" the whole difference between a reading and a guess, and this is the
    /// half of the pair that was harder to read. Its partner `taped` reads 6.08. The dark half is
    /// 6.11 on the derived amber ground and is not touched.
    static let estimatedBadgeText = overruled(light: 0x836324, dark: 0xD99A4E)

    /// `city record` badge fill `#EAF0E2` ↔ **derived** `#1F3A2C` (14).
    ///
    /// A green badge on a green badge fill, which the palette has already answered twice: the
    /// thriving badge and the `taped` badge both go `#E2EFE2`/`#28623F` → `#1F3A2C`/`#8EC3A5`.
    /// `#EAF0E2`/`#41522F` is the same badge one shade apart, so it takes the same dark pair
    /// rather than a transformed one.
    static let cityRecordBadgeFill = derived(light: 0xEAF0E2, dark: 0x1F3A2C)
    /// `city record` badge text `#41522F` ↔ **derived** `dark.accent.mint` `#8EC3A5`.
    static let cityRecordBadgeText = derived(light: 0x41522F, dark: 0x8EC3A5)

    /// `PLANTED 2024` badge fill `#EAF0E2` ↔ **derived** `#1F3A2C` (14). See `cityRecordBadgeFill`.
    static let plantedBadgeFill = derived(light: 0xEAF0E2, dark: 0x1F3A2C)
    /// `PLANTED 2024` badge text `#41522F` ↔ **derived** `dark.accent.mint` `#8EC3A5`.
    static let plantedBadgeText = derived(light: 0x41522F, dark: 0x8EC3A5)

    /// `REMOVED` badge fill `#E4E6DC` ↔ **derived** `dark.border` `#27352B` (19).
    ///
    /// The tinted-fill rule fitted on the two documented badge fills: a badge fill in the dark is
    /// its own family's hue held at L≈0.30 with the chroma of a green-tinted black. `REMOVED` has
    /// no family hue, so it takes the house green and lands on `#27352B`, within 0.013 of the fit.
    static let removedBadgeFill = derived(light: 0xE4E6DC, dark: 0x27352B)
    /// `REMOVED` badge text `#5C6555` ↔ **derived** `dark.text.muted` `#94A496`.
    /// A muted grey label: the documented dark ladder has a rung for exactly that.
    static let removedBadgeText = derived(light: 0x5C6555, dark: 0x94A496)

    /// Green callout fill `#EFF3E3` ↔ `dark.surface.callout` `#1A241A` (03, 14, 16, 19; D2).
    static let calloutGreenFill = dynamic(light: 0xEFF3E3, dark: 0x1A241A)
    /// Green callout border `#DFE6CD` ↔ `#27352B`. Same value as `border.calloutGreen`, and the
    /// same D2 sentence gives its dark counterpart.
    static let calloutGreenBorder = dynamic(light: 0xDFE6CD, dark: 0x27352B)
    /// Green callout text `#41522F` ↔ `#B9C7B2`.
    ///
    /// §1.2's semantic table gives no dark counterpart; D2 does, in prose: the recognize-it
    /// callout's "body `#B9C7B2`". `calloutGreenBody` in the §2 block below already carries that
    /// pair; this §1.2 token was left light-only and is the same miss.
    static let calloutGreenText = dynamic(light: 0x41522F, dark: 0xB9C7B2)

    /// Gradient callout border `#D9E3C8` (07, 08). See `calloutGradient` for the fill.
    /// **Escalated** with the gradient it bounds — see `borderCalloutGradient`.
    static let calloutGradientBorder = escalated(0xD9E3C8)
    /// Gradient callout text `#1C2A21` — the `text.ink` token, so it carries ink's dark pair.
    static let calloutGradientText = textInk

    // The amber family. SCREENS.md gives it no dark row at all, and the dark palette answers it
    // with two values and no more: `dark.accent.amber` `#D99A4E` is the mark, `dark.accent.amberBg`
    // `#2E271A` is the ground under it. D1 sends the amber pin to the first; D2 sends the `est.`
    // badge to both. Every amber fill below therefore derives to `#2E271A` and every amber mark to
    // `#D99A4E`, which mints no hex. What that loses is recorded on `borderAmberSoft`.

    /// Amber pill / banner fill `#F8EFDF` ↔ **derived** `dark.accent.amberBg` `#2E271A` (02, 06, 17).
    static let amberPillFill = derived(light: 0xF8EFDF, dark: 0x2E271A)
    /// Amber pill / banner border `#EBD3A8` ↔ **derived** `dark.accent.amber` `#D99A4E`.
    static let amberPillBorder = derived(light: 0xEBD3A8, dark: 0xD99A4E)
    /// Amber pill / banner text `#8A5A17` ↔ **derived** `dark.accent.amber` `#D99A4E`.
    /// 6.1:1 on the derived fill, against 5.2:1 in light.
    static let amberPillText = derived(light: 0x8A5A17, dark: 0xD99A4E)

    /// Amber selected chip fill `#F8EFDF` ↔ **derived** `#2E271A` (06).
    static let amberChipSelectedFill = derived(light: 0xF8EFDF, dark: 0x2E271A)
    /// Amber selected chip border `#D9A05B` ↔ **derived** `#D99A4E` (`1.5px`).
    static let amberChipSelectedBorder = derived(light: 0xD9A05B, dark: 0xD99A4E)
    /// Amber selected chip text `#8A5A17` ↔ **derived** `#D99A4E`.
    static let amberChipSelectedText = derived(light: 0x8A5A17, dark: 0xD99A4E)

    /// Amber attention card fill `#FFFFFF` (12, 17) — the `surface.card` token.
    static let amberAttentionCardFill = surfaceCard
    /// Amber attention card border — **overruled** to `#B8803A` in light, from §1.2's `#D9A05B`.
    /// Dark keeps the derived `#D99A4E` (`1.5px`).
    ///
    /// **RULINGS R1** (ERRATA E108). C24 is `surface.card` on `surface.screen` at 1.09:1, so this
    /// 1.5 pt border is the only thing saying the card is different — which is exactly the case
    /// WCAG 1.4.11 is written for, and the one place in the palette where a border genuinely is
    /// required to identify a component. It read 2.30 against the card it bounds and 2.12 against
    /// the page behind it, against a 3.0 floor.
    ///
    /// Measured **2.30 → 3.39** on the card and **2.12 → 3.12** on the screen. Both grounds on
    /// purpose: a boundary is adjacent to a surface on each side, and the page is the harder of
    /// the two. Dark is 6.57 / 7.55 and is not touched.
    ///
    /// This is the one place the three light amber border weights come apart. `borderAmberMid`
    /// and `amberChipSelectedBorder` are the same `#D9A05B` and stay there: a selected chip is
    /// identified by its fill and its label, not by its edge, so 1.4.11 does not bind on them.
    static let amberAttentionCardBorder = overruled(light: 0xB8803A, dark: 0xD99A4E)

    /// 311 hazard panel fill `#F8EFDF` ↔ **derived** `#2E271A` (06).
    static let hazardPanelFill = derived(light: 0xF8EFDF, dark: 0x2E271A)
    /// 311 hazard panel border `#E0B070` ↔ **derived** `#D99A4E` (`1.5px`).
    static let hazardPanelBorder = derived(light: 0xE0B070, dark: 0xD99A4E)
    /// 311 hazard panel body text `#6B5122` ↔ **derived** `#BDA680`.
    ///
    /// The one amber that is not a mark: it is body copy inside the panel, and the documented
    /// analogue is D2's green callout, whose body goes `#41522F` → `#B9C7B2` — lightened and
    /// desaturated, not moved onto the accent. Same text rule, run at the amber hue. 6.3:1 on
    /// the derived fill, against 6.5:1 in light.
    static let hazardPanelText = derived(light: 0x6B5122, dark: 0xBDA680)
    /// 311 hazard panel phone glyph `#FDF3E3` ↔ **derived** `dark.bg.screen` `#0E1712`, on the
    /// 54×54 Signal Amber circle (06 §4).
    ///
    /// §1.2 has no row for this: the hex reaches SCREENS.md only as Signal Amber's *swatch text
    /// color* in §1.1, which is where 06 borrows it from. Recorded in ERRATA (E20). The circle it
    /// rides on is `signalAmber`, which does have a documented dark value, so the glyph follows
    /// `ctaLabel`'s documented pattern and inverts to the ground: a near-white glyph on `#D99A4E`
    /// is 2.2:1 and unreadable, the ground is 7.6:1.
    static let hazardPanelGlyph = derived(light: 0xFDF3E3, dark: 0x0E1712)

    /// 311 CTA button fill `#A35F12` ↔ **derived** `dark.accent.amber` `#D99A4E` (06).
    /// The accent rule puts it at `#DC9657`, 0.016 from the documented amber, so the documented
    /// hex is used.
    static let hazardCTAFill = derived(light: 0xA35F12, dark: 0xD99A4E)
    /// 311 CTA button label `#FFFFFF` ↔ **derived** `dark.bg.screen` `#0E1712`.
    /// Its fill inverts, so the label inverts with it — `ctaLabel` and `onSelectionFill` are the
    /// documented instances of the same move. 7.6:1, against 5.0:1 in light.
    static let hazardCTAText = derived(light: 0xFFFFFF, dark: 0x0E1712)

    /// Memorial banner fill `#EDEEE6` ↔ **derived** `dark.border` `#27352B` (19).
    /// Tinted-fill rule at the house green; lands within 0.017 of the documented hex.
    static let memorialBannerFill = derived(light: 0xEDEEE6, dark: 0x27352B)
    /// Memorial banner border `#C4C8B8` ↔ **derived** `#39423A` (`1.5px`).
    /// Same value as `border.memorial`, same border rule.
    static let memorialBannerBorder = derived(light: 0xC4C8B8, dark: 0x39423A)
    /// Memorial banner text `#4A5344` ↔ **derived** `dark.text.secondary` `#AEBBAB`.
    static let memorialBannerText = derived(light: 0x4A5344, dark: 0xAEBBAB)

    /// GPS dot fill `#3577C9` ↔ `dark.accent.gps` `#6FA8E8` (01, 02).
    static let gpsDot = dynamic(light: 0x3577C9, dark: 0x6FA8E8)
    /// GPS dot halo `rgba(53,119,201,.18)` ↔ `rgba(111,168,232,.16)` — an 8pt outer ring.
    static let gpsDotHalo = dynamic(
        light: 0x3577C9, dark: 0x6FA8E8, lightAlpha: 0.18, darkAlpha: 0.16
    )
    /// GPS dot / map pin ring — light `3px solid #fff` ↔ `dark.pin.ring` `#0E1712`
    /// ("pins ring against ground, not white").
    static let pinRingStroke = dynamic(light: 0xFFFFFF, dark: 0x0E1712)

    // MARK: - Role pairs
    //
    // SCREENS.md gives the light role in §1.1 and the dark role in the §1.2 dark table, using the
    // same words ("primary CTA fill", "pins", "amber"). These three tokens join them so a CTA does
    // not need a `colorScheme` check at the call site. The underlying hues remain available
    // individually above and in `Dark`.

    /// Primary CTA fill — Cypress Deep `#1D4634` ("primary buttons") ↔ `dark.accent.mint` `#8EC3A5`
    /// ("primary CTA fill, selection, active tab").
    static let ctaFill = dynamic(light: 0x1D4634, dark: 0x8EC3A5)
    /// Label riding on `ctaFill` — `text.onDark` `#FFFFFF` ↔ `dark.bg.screen` `#0E1712`,
    /// because the dark CTA is a light mint fill.
    static let ctaLabel = dynamic(light: 0xFFFFFF, dark: 0x0E1712)
    /// Account sheet primary fill `#1C2A21` ↔ **derived** `#E4EBE2` — 15's `Continue with Apple`.
    ///
    /// Screen 15 is the one primary button in the app that is not `ctaFill`: SCREENS.md 15 §3 gives
    /// it `#1C2A21`, which is `text.ink`'s light value used as a fill, not Cypress Deep. Ink's
    /// documented dark counterpart is `#E4EBE2`, so the fill inverts — which is exactly what it has
    /// to do to remain a fill at all, since `#1C2A21` against the dark sheet (`#18251D`) is 1.1:1
    /// and would vanish.
    static let accountPrimaryFill = derived(light: 0x1C2A21, dark: 0xE4EBE2)

    /// Label riding on `accountPrimaryFill` — `#FFFFFF` ↔ **derived** `dark.bg.screen` `#0E1712`.
    ///
    /// `ctaLabel`'s documented move, for the same reason: the fill inverts, so the label inverts
    /// with it and lands on the ground colour. `#FFFFFF` has three documented dark counterparts
    /// (see `textOnDark`); this is the one that applies when the fill beneath goes light.
    static let accountPrimaryLabel = derived(light: 0xFFFFFF, dark: 0x0E1712)

    /// Map pin fill — Canopy `#2F6B4F` ("pins") ↔ `dark.accent.pin` `#6FAE8C` ("map pins").
    static let pinFill = dynamic(light: 0x2F6B4F, dark: 0x6FAE8C)
    /// Attention accent — Signal Amber `#B4711F` ↔ `dark.accent.amber` `#D99A4E`.
    static let accentAmber = dynamic(light: 0xB4711F, dark: 0xD99A4E)

    // MARK: - §1.2 Foliage strip greens (fixed 3-step ramp)

    /// Foliage density step. Used identically on every foliage strip.
    enum FoliageLevel: Int, CaseIterable, Identifiable {
        case densest
        case mid
        case sparsest

        var id: Int { rawValue }

        /// Row label as it appears in SCREENS.md §1.2.
        var name: String {
            switch self {
            case .densest: return "Densest"
            case .mid: return "Mid"
            case .sparsest: return "Sparsest"
            }
        }

        var color: Color { CypressColor.foliage(self) }
    }

    /// Densest `#5D9159` ↔ `#3E6B44`.
    static let foliageDensest = dynamic(light: 0x5D9159, dark: 0x3E6B44)
    /// Mid `#8FB573` ↔ `#587D50`.
    static let foliageMid = dynamic(light: 0x8FB573, dark: 0x587D50)
    /// Sparsest `#BCD3A8` ↔ `#6E8A5F`.
    static let foliageSparsest = dynamic(light: 0xBCD3A8, dark: 0x6E8A5F)

    static func foliage(_ level: FoliageLevel) -> Color {
        switch level {
        case .densest: return foliageDensest
        case .mid: return foliageMid
        case .sparsest: return foliageSparsest
        }
    }

    // MARK: - CSS gradient angles

    /// Converts a CSS `linear-gradient(<deg>, …)` angle to SwiftUI unit points.
    ///
    /// CSS measures the angle clockwise from "to top", so the gradient-line direction in screen
    /// coordinates (x right, y down) is `(sin θ, −cos θ)`. For a square box the gradient line's
    /// length is `|W·sin θ| + |H·cos θ|`, i.e. `|dx| + |dy|` on the unit square, and the two stops
    /// sit at `center ± length/2 · direction`. The result can fall outside 0…1 — that is correct
    /// and `UnitPoint` accepts it.
    ///
    /// Verified against the CSS definition: 90° → (0,0.5)→(1,0.5) "to right"; 180° → (0.5,0)→(0.5,1)
    /// "to bottom"; 45° → (0,1)→(1,0) "to top right"; 140° → (0.047,−0.040)→(0.953,1.040), i.e.
    /// down-and-to-the-right, which is what every vitality swatch shows.
    static func cssGradientPoints(_ degrees: Double) -> (start: UnitPoint, end: UnitPoint) {
        let radians = degrees * .pi / 180
        let dx = sin(radians)
        let dy = -cos(radians)
        let length = abs(dx) + abs(dy)
        let hx = dx * length / 2
        let hy = dy * length / 2
        return (
            UnitPoint(x: 0.5 - hx, y: 0.5 - hy),
            UnitPoint(x: 0.5 + hx, y: 0.5 + hy)
        )
    }

    /// Unit points for `linear-gradient(140deg, …)` — every vitality swatch.
    static let gradient140 = cssGradientPoints(140)
    /// Unit points for `linear-gradient(120deg, …)` — the gradient callout.
    static let gradient120 = cssGradientPoints(120)
    /// Unit points for `linear-gradient(90deg, …)` — `dark.map.ocean`.
    static let gradient90 = cssGradientPoints(90)

    static func linearGradient(_ degrees: Double, _ colors: [Color]) -> LinearGradient {
        let points = cssGradientPoints(degrees)
        return LinearGradient(colors: colors, startPoint: points.start, endPoint: points.end)
    }

    // MARK: - §1.2 Vitality reference-swatch gradients (05 light / D3 dark)

    /// The anchored 5-class vitality scale (ARCHITECTURE §2, Core/Rubric) as a color ramp.
    /// Every swatch is a `linear-gradient(140deg, …)`.
    enum Vitality: Int, CaseIterable, Identifiable {
        case severeDecline = 1
        case poor = 2
        case fair = 3
        case good = 4
        case thriving = 5

        var id: Int { rawValue }

        /// Label verbatim from SCREENS.md §1.2 ("1 · Severe decline", …).
        var name: String {
            switch self {
            case .severeDecline: return "Severe decline"
            case .poor: return "Poor"
            case .fair: return "Fair"
            case .good: return "Good"
            case .thriving: return "Thriving"
            }
        }

        /// Light stops, as written in the doc.
        var lightStops: (UInt32, UInt32) {
            switch self {
            case .severeDecline: return (0xC0A37C, 0x8A6A4A)
            case .poor: return (0xC9B06A, 0xA3813F)
            case .fair: return (0xB3BD7A, 0x8A9A55)
            case .good: return (0x7FAE72, 0x5D9159)
            case .thriving: return (0x57925E, 0x2C6B45)
            }
        }

        /// Dark stops, as written in the doc.
        var darkStops: (UInt32, UInt32) {
            switch self {
            case .severeDecline: return (0x8A7355, 0x5E4832)
            case .poor: return (0x8F7C48, 0x6E572B)
            case .fair: return (0x7E8752, 0x5C6838)
            case .good: return (0x5B8250, 0x3E6B44)
            case .thriving: return (0x3F7048, 0x245239)
            }
        }

        /// Scheme-resolving gradient — the stops themselves are dynamic colors, so a single
        /// `LinearGradient` value is correct in both light and dark.
        var gradient: LinearGradient {
            CypressColor.linearGradient(140, [
                CypressColor.dynamic(light: lightStops.0, dark: darkStops.0),
                CypressColor.dynamic(light: lightStops.1, dark: darkStops.1),
            ])
        }

        /// Forced-dark gradient, for D3 and any view that pins the dark palette.
        var darkGradient: LinearGradient {
            CypressColor.linearGradient(140, [
                Color(cypressHex: darkStops.0),
                Color(cypressHex: darkStops.1),
            ])
        }
    }

    /// Convenience: the vitality gradient for a 1…5 class, clamped.
    static func vitalityGradient(_ level: Int) -> LinearGradient {
        (Vitality(rawValue: min(max(level, 1), 5)) ?? .fair).gradient
    }

    // MARK: - Named gradients

    /// Gradient callout `linear-gradient(120deg,#EAF2E6,#F6F2DF)` (07, 08).
    ///
    /// **Escalated.** Two stops and an angle are a drawing, not a value: the transform can move
    /// each stop but cannot say whether a pale two-hue wash even survives on a dark ground, and
    /// D1–D3 never draw one. Its border and its ink are pinned light with it, so 07 and 08 keep
    /// a coherent callout in both schemes until a designer draws the dark one.
    static let calloutGradient = linearGradient(120, [
        Color(cypressHex: 0xEAF2E6),
        Color(cypressHex: 0xF6F2DF),
    ])

    // MARK: - Forced-dark palette (screens 04, D1–D3)
    //
    // Flat, non-resolving. Use ONLY on surfaces that are dark regardless of the system setting.
    // Everywhere else, use the paired tokens above.

    enum Dark {
        /// `dark.bg.map` `#141E16` — D1 map ground.
        static let bgMap = Color(cypressHex: 0x141E16)
        /// `dark.bg.screen` `#0E1712` — D2, D3.
        static let bgScreen = Color(cypressHex: 0x0E1712)
        /// `dark.bg.camera` `#10160F` — 04 shell.
        static let bgCamera = Color(cypressHex: 0x10160F)
        /// `dark.bg.camera` tray `#151D15` — 04 camera tray.
        static let bgCameraTray = Color(cypressHex: 0x151D15)

        /// `dark.surface.card` `#18251D` — D1 tree card, D2/D3 cards.
        static let surfaceCard = Color(cypressHex: 0x18251D)
        /// `dark.surface.cardAlt` `#1B241B` — 04 note field & unselected chips.
        static let surfaceCardAlt = Color(cypressHex: 0x1B241B)
        /// `dark.surface.callout` `#1A241A` — D2 recognize-it note.
        static let surfaceCallout = Color(cypressHex: 0x1A241A)
        /// `dark.surface.thumb` `#1F2E22` — D2 activity thumb base.
        static let surfaceThumb = Color(cypressHex: 0x1F2E22)

        /// `dark.border` `#27352B` — D2/D3 card border.
        static let border = Color(cypressHex: 0x27352B)
        /// `dark.border.alt` `#2B3A2C` — D1 borders.
        static let borderAlt = Color(cypressHex: 0x2B3A2C)
        /// `dark.border.camera` `#2A362B` — 04.
        static let borderCamera = Color(cypressHex: 0x2A362B)

        /// `dark.text.primary` `#E4EBE2`.
        static let textPrimary = Color(cypressHex: 0xE4EBE2)
        /// `dark.text.strong` `#D6E0CE` — bolded row text. No light counterpart is documented.
        static let textStrong = Color(cypressHex: 0xD6E0CE)
        /// `dark.text.secondary` `#AEBBAB` — unselected chip labels.
        static let textSecondary = Color(cypressHex: 0xAEBBAB)
        /// `dark.text.muted` `#94A496` — sublabels. Unchanged by R1a: 04's offline line reads
        /// 6.57 on the tray, 6.09 on the note field and 7.00 on the shell, so it already clears
        /// the 6.0 R1 holds the rung above faint to, and a value that clears its floor is not
        /// overruled.
        static let textMuted = Color(cypressHex: 0x94A496)
        /// `dark.text.faint` — **overruled** to `#7E8F80`, from SCREENS.md's `dark.text.faint`
        /// `#5F6F61`. Micro-labels, the note-field prompt, inactive tabs.
        ///
        /// **RULINGS R1a** (ERRATA E108). Screen 04 is dark whether or not the phone is, so this
        /// is the half of the caption ramp that R1 could not reach: it retinted the resolving
        /// token and left the forced-dark palette transcribed, which made the same micro-label
        /// legible when the phone was in dark mode and illegible when the *screen* was dark. R1's
        /// argument was that the ramp is not one badge but every micro-label in the app, and that
        /// argument fails on its own terms if this value stays.
        ///
        /// Measured on the grounds 04 draws it on: the note-field prompt **2.99 → 4.66**, the
        /// tray **3.23 → 5.03**, the shell **3.44 → 5.36**.
        ///
        /// The value is `textFaint`'s retinted dark half exactly, so it mints nothing and the two
        /// halves of the ramp are one colour again. One ground is deliberately excluded from the
        /// solve: the disabled `Log visit` label rides this token on `surfaceThumb` and reads
        /// 4.16, because WCAG 1.4.3 exempts text that is part of an inactive component and
        /// solving against it would make a disabled control read exactly as strongly as an
        /// enabled one. Same call `ctaDisabledLabel` gets.
        static let textFaint = Color(cypressHex: 0x7E8F80)

        /// `dark.accent.mint` `#8EC3A5` — primary CTA fill, selection, active tab.
        static let accentMint = Color(cypressHex: 0x8EC3A5)
        /// `dark.accent.pin` `#6FAE8C` — map pins.
        static let accentPin = Color(cypressHex: 0x6FAE8C)
        /// `dark.accent.amber` `#D99A4E` — amber pin, `est.` badge text.
        static let accentAmber = Color(cypressHex: 0xD99A4E)
        /// `dark.accent.amberBg` `#2E271A` — `est.` badge fill.
        static let accentAmberBg = Color(cypressHex: 0x2E271A)
        /// `dark.accent.gps` `#6FA8E8`.
        static let accentGPS = Color(cypressHex: 0x6FA8E8)
        /// `dark.accent.gps` halo `rgba(111,168,232,.16)` — an 8pt outer ring.
        static let accentGPSHalo = Color(cypressHex: 0x6FA8E8, alpha: 0.16)

        /// `dark.map.grid` `#1C2A1F`.
        static let mapGrid = Color(cypressHex: 0x1C2A1F)
        /// `dark.map.ocean` `linear-gradient(90deg,#14282B,#183034)`.
        static let mapOcean = CypressColor.linearGradient(90, [
            Color(cypressHex: 0x14282B),
            Color(cypressHex: 0x183034),
        ])
        /// `dark.map.beach` `#2B3226`.
        static let mapBeach = Color(cypressHex: 0x2B3226)
        /// `dark.map.park` `#1B3123`.
        static let mapPark = Color(cypressHex: 0x1B3123)
        /// `dark.map.park` inset ring `#274531`.
        static let mapParkRing = Color(cypressHex: 0x274531)
        /// `dark.map.street` `#232F24`.
        static let mapStreet = Color(cypressHex: 0x232F24)
        /// `dark.map.street` ring `#2B3A2C`.
        static let mapStreetRing = Color(cypressHex: 0x2B3A2C)
        /// `dark.map.label` street `#5C6B57`.
        static let mapLabelStreet = Color(cypressHex: 0x5C6B57)
        /// `dark.map.label` park `#557A50`.
        static let mapLabelPark = Color(cypressHex: 0x557A50)
        /// `dark.map.label` ocean `#4E7A74`.
        static let mapLabelOcean = Color(cypressHex: 0x4E7A74)
        /// `dark.pin.ring` `#0E1712` (3px) — pins ring against ground, not white.
        static let pinRing = Color(cypressHex: 0x0E1712)

        /// Thriving badge (dark) fill `#1F3A2C` — D1, D2.
        static let thrivingBadgeFill = Color(cypressHex: 0x1F3A2C)
        /// Thriving badge (dark) text `#8EC3A5` — D1, D2.
        static let thrivingBadgeText = Color(cypressHex: 0x8EC3A5)

        /// Foliage ramp, dark column.
        static let foliageDensest = Color(cypressHex: 0x3E6B44)
        static let foliageMid = Color(cypressHex: 0x587D50)
        static let foliageSparsest = Color(cypressHex: 0x6E8A5F)

        static func foliage(_ level: FoliageLevel) -> Color {
            switch level {
            case .densest: return foliageDensest
            case .mid: return foliageMid
            case .sparsest: return foliageSparsest
            }
        }
    }
}

// MARK: - §2 component tokens
//
// Values that appear in SCREENS.md §2 (the C1–C30 catalogue) but not in the §1 token tables.
// They are transcribed here rather than inlined in `Components/`, so the "no raw hex in a
// component" rule holds. Same conventions as above: `dynamic` where §2 or the D1–D3 delta tables
// give a dark counterpart, `lightOnly` + TODO where they do not.

extension CypressColor {

    // MARK: C2 · HeroPhotoHeader

    /// Hero back button fill — `rgba(255,255,255,.92)` ↔ D2 `rgba(24,37,29,.92)`.
    static let heroBackFill = dynamic(
        light: 0xFFFFFF, dark: 0x18251D, lightAlpha: 0.92, darkAlpha: 0.92
    )

    /// Hero meta pill fill (03, 07) — `rgba(16,32,22,.45)`. Rides on imagery, so it is
    /// scheme-independent; the dark screen uses `heroMetaPillFillDark` instead.
    static let heroMetaPillFill = lightOnly(0x102016, alpha: 0.45)
    /// Hero meta pill fill (19, memorial) — `rgba(30,34,28,.45)`.
    static let heroMetaPillFillMemorial = lightOnly(0x1E221C, alpha: 0.45)
    /// Hero meta pill fill (D2) — `rgba(8,14,10,.55)`.
    static let heroMetaPillFillDark = lightOnly(0x080E0A, alpha: 0.55)
    /// Hero meta pill text (D2) — `#CFE0D2`.
    static let textOnPhotoDark = lightOnly(0xCFE0D2)

    // MARK: C4 · Chip

    /// Filter chip, idle (01) — `rgba(255,255,255,.92)` ↔ D1 `rgba(24,37,29,.92)`.
    static let chipGlassFill = dynamic(
        light: 0xFFFFFF, dark: 0x18251D, lightAlpha: 0.92, darkAlpha: 0.92
    )

    /// Selection fill shared by the segmented control, structure flags, care toggles and
    /// phenology chips — Canopy `#2F6B4F` ↔ `dark.accent.mint` `#8EC3A5`.
    /// Distinct from `ctaFill`, which is Cypress Deep in light.
    static let selectionFill = dynamic(light: 0x2F6B4F, dark: 0x8EC3A5)
    /// Label riding on `selectionFill` — `#FFFFFF` ↔ `#0E1712`.
    static let onSelectionFill = dynamic(light: 0xFFFFFF, dark: 0x0E1712)

    /// Shot-type chip, on (04) — `rgba(233,240,226,.94)`. Screen 04 is dark always.
    static let shotTypeOnFill = lightOnly(0xE9F0E2, alpha: 0.94)
    /// Shot-type chip, on (04) label — `#22301F`.
    static let shotTypeOnText = lightOnly(0x22301F)
    /// Shot-type chip, off (04) — `rgba(6,10,7,.55)`.
    static let shotTypeOffFill = lightOnly(0x060A07, alpha: 0.55)
    /// Shot-type chip, off (04) label — `#CFDAC6`.
    static let shotTypeOffText = lightOnly(0xCFDAC6)

    // MARK: C6 · PrimaryButton, 04 variant

    /// 04 CTA fill — New Growth `#4E8F6A`.
    static let ctaCameraFill = newGrowth
    /// 04 CTA label — `#0E1A12`.
    static let ctaCameraLabel = lightOnly(0x0E1A12)

    /// Disabled CTA fill `#E9ECDE` ↔ **derived** `dark.surface.card` `#18251D`.
    ///
    /// SCREENS.md §5 gap 2 lists the disabled button state as unspecified, and `Buttons.swift` says
    /// so. It is specified elsewhere: PROTOTYPE-FLOW §1.4 gives `careBtnStyle` as
    /// `disabled → background:#E9ECDE;color:#8B9482` for screen 09's `Done`, which §1.3's `logCare`
    /// guard ("no-op if no care chip is on") is the behaviour behind. So the value is the
    /// prototype's, not an invention — it is transcribed here rather than left to the one screen
    /// that needs it.
    ///
    /// The dark half is derived on the same rule `speciesTileLockedFill` takes, whose light hex is
    /// the identical `#E9ECDE`: a card-level plane lands on `dark.surface.card`.
    static let ctaDisabledFill = derived(light: 0xE9ECDE, dark: 0x18251D)
    /// Disabled CTA label — the prototype's `#8B9482`, which is `text.faint`, so it follows that
    /// token's RULINGS R1 retint to `#697260` ↔ `#7E8F80` and now reads 4.19 on the disabled fill
    /// in light and 4.64 in dark, against 2.66 / 2.98 before. It is still the one text pair in the
    /// app deliberately left under 4.5 in light: WCAG 1.4.3 exempts "text that is part of an
    /// inactive user interface component", and a disabled `Done` that reads as enabled is the
    /// worse defect. It moved because the token moved, not because this pair was being fixed.
    static let ctaDisabledLabel = textFaint

    // MARK: 10 · Share sheet

    /// Share preview card fill `#FAF8EF` ↔ **derived** `dark.surface.card` `#18251D`.
    ///
    /// SCREENS.md 10 §3 gives it as a warm plane sitting on the `#FDFDF8` sheet. Dark takes the rung
    /// every raised plane in the documented pairs lands on, which is the same one `surfaceSheet`
    /// takes — so after dark the card is told apart from the sheet by `borderShareCard` alone. 10
    /// has no dark row in SCREENS.md, so this is derived and unreviewed; see ERRATA (E55).
    static let surfaceShareCard = derived(light: 0xFAF8EF, dark: 0x18251D)

    /// Share destination icon well `#EAF0E2` ↔ **derived** `dark.surface.thumb` `#1F2E22`.
    /// A 52pt circular recess inside the sheet, which is what `dark.surface.thumb` is for.
    static let shareTargetWellFill = derived(light: 0xEAF0E2, dark: 0x1F2E22)
    /// Share destination icon well border `#DDE2D2` ↔ **derived** `dark.border.alt` `#2B3A2C`,
    /// on the same border rule `borderSheetGrabber` takes from the identical light hex.
    static let shareTargetWellBorder = derived(light: 0xDDE2D2, dark: 0x2B3A2C)

    // MARK: C10 · IconTextRow tile accents (12, 13)

    /// One `radial-gradient(circle at 45% 42%, <accent> 0%, transparent 55%)` over a pale base.
    /// The five pairs drawn on 12 and 13, in source order.
    enum TileAccent: String, CaseIterable, Identifiable {
        /// `#D77A8A` over `#F6E8E4` — "First bloom of the year" (12).
        case bloom
        /// `#4E8F6A` over `#E7EFE2` — "The elder" (12).
        case elder
        /// `#8FB573` over `#EDF2E0` — "Newest neighbors" (12), "Spring flush noted" (13).
        case newGrowth
        /// `#7FA8C4` over `#E8EEF2` — "Watered through the dry weeks" (13).
        case water
        /// `#C9B44A` over `#F4F0DE` — "Seven years on record" (13).
        case record
        /// The empty planting basin — screen 12's `Where a tree could go` row (RULINGS R10).
        ///
        /// **Composed from tokens the vacant-site family already owns, so no hue enters the palette**
        /// (R7's discipline). Its ground is `surfaceEmptyThumb`, the empty photo well's fill, and its
        /// mark is `borderDashedStrong`, the dashed ring R7 gave the map pin and the site screen and
        /// the well all speak. Reusing `elder` or `newGrowth` would paint a hole in the pavement in a
        /// living tree's colour, which is the exact category error R7 removed from the map (E119).
        case vacantSite

        var id: String { rawValue }

        /// **Escalated.** The accent is the 0% stop of a radial that has faded out by 55%, so its
        /// perceived lightness is set by the base beneath it rather than by its own value — and
        /// the accent rule is a lightness anchor. Run anyway, it moves three of the five by less
        /// than one RGB step and sends `elder` to within 0.031 of `dark.accent.pin`, which is a
        /// reserved meaning (map pins). The five are a set and want deciding as one.
        var accent: Color {
            switch self {
            case .bloom: return CypressColor.escalated(0xD77A8A)
            case .elder: return CypressColor.escalated(0x4E8F6A)
            case .newGrowth: return CypressColor.escalated(0x8FB573)
            case .water: return CypressColor.escalated(0x7FA8C4)
            case .record: return CypressColor.escalated(0xC9B44A)
            // Not a life hue: the dashed-ring token, muted, the same mark a vacant site draws
            // everywhere else. Nothing new (R10, E121).
            case .vacantSite: return CypressColor.borderDashedStrong
            }
        }

        /// **Derived.** Five pale tinted surfaces, which is the one thing the documented pairs do
        /// say something about: a tinted fill in the dark is its family's hue held at L≈0.30 with
        /// the chroma of a tinted black (fitted on the thriving and `est.` badge fills). Each base
        /// keeps its own accent's hue, so the five tiles stay told apart by hue after dark, which
        /// is how they are told apart before it.
        var base: Color {
            switch self {
            case .bloom: return CypressColor.derived(light: 0xF6E8E4, dark: 0x38292B)
            case .elder: return CypressColor.derived(light: 0xE7EFE2, dark: 0x27352B)
            case .newGrowth: return CypressColor.derived(light: 0xEDF2E0, dark: 0x1F2E22)
            case .water: return CypressColor.derived(light: 0xE8EEF2, dark: 0x282F34)
            case .record: return CypressColor.derived(light: 0xF4F0DE, dark: 0x322E1A)
            case .vacantSite: return CypressColor.surfaceEmptyThumb
            }
        }
    }

    // MARK: Screen 12 §3 · composition card
    //
    // The species-mix card has no C-number: SCREENS.md §2's catalogue does not carry it and screen
    // 12 §3 describes it inline. Its colours live here anyway, because a feature may not write a
    // hex (ARCHITECTURE §6) and because two of the four swatches are values the palette did not
    // already carry.

    /// Screen 12 §3's four swatches, in the drawn order: `#1D4634`, `#4E8F6A`, `#7A4F33`, `#C2CAB4`.
    ///
    /// **Escalated as a set, for the reason the C23 series palette is.** Three of the four are brand
    /// hues, which §1.1 says have no single dark answer, and the fourth is the neutral that means
    /// "everyone else". A series palette is chosen for separation between its members rather than
    /// per colour, so deriving them one at a time is the one operation guaranteed to break the thing
    /// they are for — `chartSeriesPrimary`'s note records the same transform collapsing Canopy and
    /// New Growth to 0.011 apart in dark. The four want deciding together, by a designer, with the
    /// track colour below in front of them.
    static let compositionSwatches: [Color] = [
        escalated(0x1D4634),
        escalated(0x4E8F6A),
        escalated(0x7A4F33),
        compositionOther
    ]

    /// The `Everyone else` swatch — `#C2CAB4`. Also the colour its own share of the track is drawn
    /// in. **Escalated** with the other three.
    static let compositionOther = escalated(0xC2CAB4)

    /// The unfilled part of a composition track — `#EDEFE3`.
    ///
    /// **Derived** onto `dark.border` `#27352B`, which is where `chartGridline` (`#EAEDDF`) already
    /// goes. The two are the same kind of thing — a faint neutral rule on a white card — and their
    /// light values are three RGB steps apart, so the two landing on one dark value is the rule
    /// agreeing with itself rather than a second guess.
    static let compositionTrack = derived(light: 0xEDEFE3, dark: 0x27352B)

    // MARK: C14 · Callout

    /// Green callout body — `#41522F` ↔ D2 `#B9C7B2`. The §1.2 `calloutGreenText` token is
    /// light-only; D2 gives the dark counterpart in its delta list, so §2 pairs them here.
    static let calloutGreenBody = dynamic(light: 0x41522F, dark: 0xB9C7B2)
    /// Green callout lead-in — `#41522F` ↔ D2 `#D6E0CE`. In light the weight alone separates the
    /// lead-in from the body; in dark it also lifts in colour.
    static let calloutGreenLeadIn = dynamic(light: 0x41522F, dark: 0xD6E0CE)

    /// Gradient callout ink — the literal `#1C2A21` of §1.2's `text.ink`, deliberately **not** the
    /// paired `textInk` token. The gradient fill (`#EAF2E6 → #F6F2DF`) has no dark counterpart in
    /// SCREENS.md, so it stays light in both schemes — and text on it must stay dark with it.
    /// **Escalated** with the gradient; it moves the day the gradient does.
    static let calloutGradientInk = escalated(0x1C2A21)

    // MARK: C16 · BottomTabBar

    /// Tab bar background — `rgba(250,250,244,.95)` ↔ D1 `rgba(16,24,18,.95)`.
    static let tabBarFill = dynamic(
        light: 0xFAFAF4, dark: 0x101812, lightAlpha: 0.95, darkAlpha: 0.95
    )
    /// Tab bar top hairline — `rgba(29,70,52,.08)` ↔ D1 `#26332A`.
    static let tabBarTopBorder = dynamic(
        light: 0x1D4634, dark: 0x26332A, lightAlpha: 0.08, darkAlpha: 1
    )
    /// Active tab tint — `#1D4634` ↔ `#8EC3A5`. (Inactive is `textFaint`, which since RULINGS R1
    /// pairs `#697260` ↔ `#7E8F80` — the inactive tab label darkened with the rest of the ramp.)
    static let tabActive = dynamic(light: 0x1D4634, dark: 0x8EC3A5)
    /// "You" avatar letter — `#FFFFFF` ↔ D1 `#DFE8D6`.
    static let tabAvatarLetter = dynamic(light: 0xFFFFFF, dark: 0xDFE8D6)

    // MARK: C17 · BottomSheet

    /// Sheet scrim (09, 10) — `rgba(14,24,17,.44)`.
    static let sheetScrim = lightOnly(0x0E1811, alpha: 0.44)
    /// Sheet scrim (15) — `rgba(14,24,17,.3)`.
    static let sheetScrimSoft = lightOnly(0x0E1811, alpha: 0.30)

    // MARK: C18 · MapCanvas

    /// Ocean band start — `#A9CDC7` ↔ `dark.map.ocean` `#14282B`.
    static let mapOceanStart = dynamic(light: 0xA9CDC7, dark: 0x14282B)
    /// Ocean band end — `#BCD8D0` ↔ `#183034`.
    static let mapOceanEnd = dynamic(light: 0xBCD8D0, dark: 0x183034)
    /// Beach strip — `#EADFB4` ↔ `dark.map.beach` `#2B3226`.
    static let mapBeach = dynamic(light: 0xEADFB4, dark: 0x2B3226)
    /// Park block — `#CDE0BC` ↔ `dark.map.park` `#1B3123`.
    static let mapPark = dynamic(light: 0xCDE0BC, dark: 0x1B3123)
    /// Park inset ring (`1.5px`) — `#BCD3A6` ↔ `#274531`.
    static let mapParkRing = dynamic(light: 0xBCD3A6, dark: 0x274531)
    /// Named street band ring (`0 0 0 1px`) — `#E4DEC8` ↔ `dark.map.street` ring `#2B3A2C`.
    static let mapStreetBandRing = dynamic(light: 0xE4DEC8, dark: 0x2B3A2C)

    // MARK: C19 · MapPin

    /// Community-layer pin fill — `#EDF1E3` ↔ D1 `#1B241B`.
    static let pinCommunityFill = dynamic(light: 0xEDF1E3, dark: 0x1B241B)
    /// Removed / memorial pin fill — `#C4C8B8`.
    ///
    /// **Escalated**, and the reason is in the document rather than in the arithmetic: D1 draws
    /// every other pin in the dark and ends with "**`48TH AVE` and the removed/gray pin are
    /// omitted**". The one dark screen that could have answered this declined to. A muted pin
    /// also pulls the transform two ways — the accent rule lifts it to L≈0.73, where it competes
    /// with the live pins it is supposed to recede behind, and the text rule drops it to L≈0.41,
    /// where it stops reading against `dark.bg.map` at all.
    static let pinRemovedFill = escalated(0xC4C8B8)
    /// Removed pin's centred 8×2 bar — `#7A8272`. **Escalated** with the pin it sits in.
    static let pinRemovedBar = escalated(0x7A8272)
    /// Route "done" pin (18) — `#AEBFA1`. **Escalated**: the same muted-pin family, same problem.
    static let pinRouteDone = escalated(0xAEBFA1)

    // MARK: C20 · SearchBar

    /// Search bar fill — `rgba(255,255,255,.94)` ↔ D1 `rgba(24,37,29,.94)`.
    static let searchFill = dynamic(
        light: 0xFFFFFF, dark: 0x18251D, lightAlpha: 0.94, darkAlpha: 0.94
    )
    /// Search bar border — `rgba(29,70,52,.1)` ↔ D1 `#2B3A2C`.
    static let searchBorder = dynamic(
        light: 0x1D4634, dark: 0x2B3A2C, lightAlpha: 0.10, darkAlpha: 1
    )
    /// Search glyph + placeholder — **overruled** to `#6C7764` in light, from §1.2's `#77836F`.
    /// Dark keeps D1's `#94A496`.
    ///
    /// **RULINGS R1a** (ERRATA E108). This is C20's placeholder, which is text, on screen 01,
    /// which is the default screen. It wore `text.faintAlt`'s light hex by coincidence rather than
    /// by alias, so R1 retired that value everywhere except here and left this the only thing in
    /// the app still wearing it. E106's sweep never reached the search bar.
    ///
    /// Measured **3.93 → 4.63**, on the ground it actually sits on: the search fill is
    /// `rgba(255,255,255,.94)`, so the placeholder sits on that fill composited over the map paper
    /// (`#FEFDFC`) and not on the token. That costs 0.06 against measuring the token opaque —
    /// small, and the same class of mistake as measuring a caption on the wrong surface. After
    /// dark the composite rounds back onto `#18251D` and `#94A496` reads 6.06, so the dark half
    /// clears without an overrule and does not get one.
    static let searchGlyph = overruled(light: 0x6C7764, dark: 0x94A496)

    // MARK: C23 · ChartCard

    /// Gridlines and empty bars — `#EAEDDF` ↔ **derived** `dark.border` `#27352B`.
    /// A gridline is a hairline; border rule, within 0.014 of the documented hex.
    static let chartGridline = derived(light: 0xEAEDDF, dark: 0x27352B)

    // The three chart series are **escalated as a set**, which is the only way they make sense.
    // The accent rule reproduces every documented accent to within 0.043 in OKLab, and it is
    // still wrong here: it anchors lightness, so Canopy and New Growth — 0.117 apart in light —
    // land 0.011 apart in dark and C23's three series become two. A series palette is chosen for
    // separation, not per colour, and the dark palette has no third green to separate them with.
    // Left light, which is a stated contrast failure rather than a hidden one: Canopy on
    // `dark.surface.card` is 2.5:1 and Bark is 2.3:1.

    /// Series 1 (photos, DBH, height) — Canopy. **Escalated** with the other two.
    static let chartSeriesPrimary = escalated(0x2F6B4F)
    /// Series 2 (check-ins) — New Growth. **Escalated** with the other two.
    static let chartSeriesSecondary = escalated(0x4E8F6A)
    /// Series 3 (care) — Bark. **Escalated** with the other two.
    static let chartSeriesTertiary = escalated(0x7A4F33)

    // MARK: 13 §4 · "Same week, other years" photo strip

    /// The year chip on a strip photo — `rgba(255,255,255,.85)` (SCREENS.md 13 §4).
    ///
    /// **Light-only by definition, not by omission.** It is a scrim punched into a photograph so a
    /// date can be read off it, which is the case `lightOnly` names ("colour that rides on
    /// imagery"); `heroMetaPillFill` is the same idea from the other end of the value scale. A
    /// photograph does not get darker because the phone did, so neither does the plate on it.
    static let photoStripChipFill = lightOnly(0xFFFFFF, alpha: 0.85)

    // MARK: C26 · AvatarStack

    /// Avatar ring — `2px solid #fff` ↔ **derived** `dark.surface.card` `#18251D`.
    ///
    /// The ring is white because the card behind it is white — it is a gap punched in the stack,
    /// not a colour. `pinRingStroke` is the documented instance of the same idea and goes
    /// `#FFFFFF` → `#0E1712`, the ground *it* sits on; an avatar stack sits on a card.
    static let avatarRing = derived(light: 0xFFFFFF, dark: 0x18251D)
    /// Avatar fills in the drawn order: `#2F6B4F`, `#7A4F33`, `#4E8F6A`, `#66735F`.
    ///
    /// Unchanged after dark, and that is documented rather than assumed: D1's delta table gives
    /// the "You" avatar as `#2F6B4F on #fff` → `#2F6B4F on #DFE8D6` — the letter moves, the fill
    /// does not. It is also the evidence that a brand hue has no single dark answer, since the
    /// same `#2F6B4F` becomes `#6FAE8C` two rows above it.
    static let avatarFills: [Color] = [canopy, bark, newGrowth, lightOnly(0x66735F)]

    // MARK: C27 · ProgressRing

    /// Ring track — `#E0E6D8` ↔ **derived** `dark.border` `#27352B`.
    /// The unfilled part of a ring is a hairline at ring width; border rule, within 0.011.
    static let progressRingTrack = derived(light: 0xE0E6D8, dark: 0x27352B)
    /// Inner disc — `#F5F6EF`, the `surface.screen` value.
    static let progressRingInner = surfaceScreen

    // MARK: C25 · Toggle

    /// Toggle knob — `#FFFFFF`.
    ///
    /// **Escalated.** The knob rides on two tracks that move in opposite directions after dark:
    /// the on-track is `selectionFill`, which inverts to mint, and the off-track is `border.cool`,
    /// which inverts to `#27352B`. `ctaLabel`'s documented move (white → the ground) reads on the
    /// mint and vanishes on the hairline; keeping it white does the reverse. No mocked screen
    /// draws a toggle in the dark — 17 has no dark counterpart — so both states are a guess.
    static let toggleKnob = escalated(0xFFFFFF)
    /// Toggle off track. **NOT SPECIFIED** in SCREENS.md (§5 gap 4); `border.cool` is used so the
    /// off state reads as the same inactive hairline every other idle control uses.
    static let toggleOffTrack = borderCool

    // MARK: C29 · SpeciesTile

    /// Locked tile fill — `#E9ECDE` ↔ **derived** `dark.surface.card` `#18251D`.
    /// A locked tile is a card-level plane in a grid of photo tiles.
    static let speciesTileLockedFill = derived(light: 0xE9ECDE, dark: 0x18251D)
    /// Locked tile `?` glyph — **overruled** to `#7F8974` ↔ `#647062` (RULINGS R8, ERRATA E120).
    ///
    /// It stays a deliberately quiet mark: 2.1:1 on the derived fill against 1.8:1 in light. Both
    /// fail WCAG and the glyph is decorative in both — the tile's meaning is carried by its label,
    /// not by the `?`. Flagged in ERRATA E8 rather than fixed here, because raising it is a design
    /// change to a mocked screen and not a dark-mode question.
    ///
    /// E8 recorded this pair failing 1.4.11 at 1.84:1 light and 2.12:1 dark, and exempted it because
    /// "the `?` is decorative, the tile's meaning is in its label". **That justification was wrong,
    /// and checking it is what reopened this.** `SpeciesTile`'s locked case draws the `?` and nothing
    /// else — the label it refers to is `accessibilityLabel`, which returns "Species not yet learned"
    /// to VoiceOver and is invisible to a sighted reader. So the glyph is not decoration beside a
    /// caption; it is the entire visible content of the tile, and the only thing distinguishing a
    /// locked tile from an empty plane.
    ///
    /// Both halves move by **lightness only**, holding chroma and hue in OKLCh — R1's method, so the
    /// glyph stays the same grey-green it always was. Light darkens to 3.06:1, dark lightens to
    /// 3.05:1. Nothing else in C10 moves, and the tile fill is untouched.
    static let speciesTileLockedGlyph = overruled(light: 0x7F8974, dark: 0x647062)
    /// Species tile label shadow — `0 1px 3px rgba(10,22,15,.5)`.
    static let speciesTileLabelShadow = lightOnly(0x0A160F, alpha: 0.5)

    // MARK: C13/C9 · misc

    /// Framing-corner brackets on 04 — `rgba(255,255,255,.55)`.
    static let cameraFramingCorner = lightOnly(0xFFFFFF, alpha: 0.55)

    /// The trailing disclosure chevron on a tappable card — `#B4BCA9` ↔ D1 card chevron `#4A5A4C`.
    ///
    /// §1.2 has no row for it; SCREENS.md gives the pair inline, in 01 §14 and in D1's delta table.
    /// Named for what it is for rather than for its hex, because it is the whole "this row opens
    /// something" family and not one card's decoration. It is a shade lighter than `text.faint` in
    /// both schemes on purpose: a chevron is an affordance, not a piece of text.
    static let chevronDisclosure = dynamic(light: 0xB4BCA9, dark: 0x4A5A4C)
}

// MARK: - The E8 review sheet
//
// Everything a designer has to rule on, and nothing else. `TokenGallery` renders this list as its
// first two sections, so reviewing ERRATA E8 costs one screen rather than an audit of 137 values.
//
// This list and the tokens above are two statements of the same fact, and `DerivedTokenTests`
// fails if they drift: it resolves every token below in both trait collections and compares.

/// One row of the review sheet: a token whose dark value was derived, or one where the transform
/// was run and rejected.
struct CypressReviewToken: Identifiable {

    enum Kind {
        /// The dark value was computed from the documented pairs. Check it.
        case derived
        /// The transform was run and rejected; the token is still light-only. Answer it.
        case escalated
        /// The value was transcribed and changed anyway, under RULINGS R1. Reverse it or keep it.
        case overruled
    }

    let name: String
    let kind: Kind
    /// The documented light value.
    let light: UInt32
    /// The derived dark value, or `nil` where the token was escalated.
    let dark: UInt32?
    /// Where the value came from, or why there is none — one line, for the gallery.
    let basis: String
    /// The live token, so the gallery renders the real thing and the test can compare against it.
    let color: Color
    /// Set only for `calloutGradient`, which is a drawing rather than a value.
    var gradient: LinearGradient?

    var id: String { name }

    init(
        _ name: String,
        _ kind: Kind,
        light: UInt32,
        dark: UInt32? = nil,
        basis: String,
        color: Color,
        gradient: LinearGradient? = nil
    ) {
        self.name = name
        self.kind = kind
        self.light = light
        self.dark = dark
        self.basis = basis
        self.color = color
        self.gradient = gradient
    }
}

extension CypressColor {

    /// The derived tokens, the five overruled ones, and the escalated ones. See ERRATA E8 for the
    /// transform and E108 for the overrule.
    static let reviewTokens: [CypressReviewToken] = derivedTokens + overruledTokens + escalatedTokens

    // MARK: Derived — check these

    static let derivedTokens: [CypressReviewToken] = [
        // Surfaces. The dark surface ladder is quantised: four different light surfaces land on
        // `#18251D` in the documented pairs, so these snap to a rung rather than mint a value.
        .init("surfaceSheet", .derived, light: 0xFDFDF8, dark: 0x18251D,
              basis: "raised plane → dark.surface.card", color: surfaceSheet),
        .init("surfaceEmptyThumb", .derived, light: 0xFAFBF4, dark: 0x18251D,
              basis: "corrected (R1a): a well on the screen is a card-level plane → dark.surface.card, was dark.surface.thumb #1F2E22",
              color: surfaceEmptyThumb),
        .init("surfaceSkeleton", .derived, light: 0xE3E8D9, dark: 0x27352B,
              basis: "same light hex as border.cool, whose dark is documented", color: surfaceSkeleton),
        .init("surfaceRouteMap", .derived, light: 0xE4E9D3, dark: 0x141E16,
              basis: "18's map is 01's map → dark.bg.map", color: surfaceRouteMap),
        .init("surfaceRouteMapGrid", .derived, light: 0xF4F1E2, dark: 0x1C2A1F,
              basis: "→ dark.map.grid", color: surfaceRouteMapGrid),
        .init("borderRouteMap", .derived, light: 0xDBE0CB, dark: 0x2B3A2C,
              basis: "→ dark.border.alt, D1's map border", color: borderRouteMap),
        .init("speciesTileLockedFill", .derived, light: 0xE9ECDE, dark: 0x18251D,
              basis: "card-level plane → dark.surface.card", color: speciesTileLockedFill),
        .init("ctaDisabledFill", .derived, light: 0xE9ECDE, dark: 0x18251D,
              basis: "PROTOTYPE-FLOW §1.4 careBtnStyle; same light hex as speciesTileLockedFill",
              color: ctaDisabledFill),
        .init("surfaceShareCard", .derived, light: 0xFAF8EF, dark: 0x18251D,
              basis: "raised plane on the sheet → dark.surface.card", color: surfaceShareCard),
        .init("shareTargetWellFill", .derived, light: 0xEAF0E2, dark: 0x1F2E22,
              basis: "circular recess in the sheet → dark.surface.thumb", color: shareTargetWellFill),
        .init("shareTargetWellBorder", .derived, light: 0xDDE2D2, dark: 0x2B3A2C,
              basis: "border rule → dark.border.alt; same light hex as borderSheetGrabber",
              color: shareTargetWellBorder),
        .init("avatarRing", .derived, light: 0xFFFFFF, dark: 0x18251D,
              basis: "the ring is the card behind it; cf. pinRingStroke", color: avatarRing),

        // Borders. L' = 0.816 − 0.543·L, fitted on the three documented border pairs, which it
        // reproduces to within 0.005 in OKLab.
        .init("borderDashed", .derived, light: 0xC9D1BC, dark: 0x353F34,
              basis: "border rule; E8's brightest-thing-on-D3", color: borderDashed),
        .init("borderDashedStrong", .derived, light: 0xC4CEB4, dark: 0x364133,
              basis: "border rule, one step above border.dashed", color: borderDashedStrong),
        .init("borderSheetGrabber", .derived, light: 0xDDE2D2, dark: 0x2B3A2C,
              basis: "border rule → dark.border.alt (ΔE 0.014)", color: borderSheetGrabber),
        .init("borderAccount", .derived, light: 0xD8DECB, dark: 0x2B3A2C,
              basis: "border rule → dark.border.alt (ΔE 0.012)", color: borderAccount),
        .init("accountPrimaryFill", .derived, light: 0x1C2A21, dark: 0xE4EBE2,
              basis: "ink as a fill → text.ink's documented dark; it inverts or it vanishes",
              color: accountPrimaryFill),
        .init("accountPrimaryLabel", .derived, light: 0xFFFFFF, dark: 0x0E1712,
              basis: "ctaLabel's move: the fill inverts, the label follows to the ground",
              color: accountPrimaryLabel),
        .init("borderShareCard", .derived, light: 0xE0DDC9, dark: 0x2B3A2C,
              basis: "border rule → dark.border.alt (ΔE 0.011)", color: borderShareCard),
        .init("borderMemorial", .derived, light: 0xC4C8B8, dark: 0x39423A,
              basis: "border rule, one step above the banner fill", color: borderMemorial),
        .init("chartGridline", .derived, light: 0xEAEDDF, dark: 0x27352B,
              basis: "border rule → dark.border (ΔE 0.014)", color: chartGridline),
        .init("progressRingTrack", .derived, light: 0xE0E6D8, dark: 0x27352B,
              basis: "border rule → dark.border (ΔE 0.011)", color: progressRingTrack),

        // The amber family. Two documented ambers and no more; see `borderAmberSoft`.
        .init("amberPillFill", .derived, light: 0xF8EFDF, dark: 0x2E271A,
              basis: "amber ground → dark.accent.amberBg", color: amberPillFill),
        .init("amberPillBorder", .derived, light: 0xEBD3A8, dark: 0xD99A4E,
              basis: "amber mark → dark.accent.amber; loses a weight", color: amberPillBorder),
        .init("amberPillText", .derived, light: 0x8A5A17, dark: 0xD99A4E,
              basis: "amber mark → dark.accent.amber; 6.1:1", color: amberPillText),
        .init("amberChipSelectedFill", .derived, light: 0xF8EFDF, dark: 0x2E271A,
              basis: "amber ground → dark.accent.amberBg", color: amberChipSelectedFill),
        .init("amberChipSelectedBorder", .derived, light: 0xD9A05B, dark: 0xD99A4E,
              basis: "already the dark amber (ΔE 0.016)", color: amberChipSelectedBorder),
        .init("amberChipSelectedText", .derived, light: 0x8A5A17, dark: 0xD99A4E,
              basis: "amber mark → dark.accent.amber", color: amberChipSelectedText),
        .init("borderAmberSoft", .derived, light: 0xEBD3A8, dark: 0xD99A4E,
              basis: "amber mark; three light weights collapse to one", color: borderAmberSoft),
        .init("borderAmberMid", .derived, light: 0xD9A05B, dark: 0xD99A4E,
              basis: "already the dark amber (ΔE 0.016)", color: borderAmberMid),
        .init("borderAmberStrong", .derived, light: 0xE0B070, dark: 0xD99A4E,
              basis: "amber mark → dark.accent.amber", color: borderAmberStrong),
        .init("hazardPanelFill", .derived, light: 0xF8EFDF, dark: 0x2E271A,
              basis: "amber ground → dark.accent.amberBg", color: hazardPanelFill),
        .init("hazardPanelBorder", .derived, light: 0xE0B070, dark: 0xD99A4E,
              basis: "amber mark → dark.accent.amber", color: hazardPanelBorder),
        .init("hazardPanelText", .derived, light: 0x6B5122, dark: 0xBDA680,
              basis: "text rule at the amber hue, as D2's callout body; 6.3:1", color: hazardPanelText),
        .init("hazardPanelGlyph", .derived, light: 0xFDF3E3, dark: 0x0E1712,
              basis: "inverts with its circle; 2.2:1 → 7.6:1", color: hazardPanelGlyph),
        .init("hazardCTAFill", .derived, light: 0xA35F12, dark: 0xD99A4E,
              basis: "accent rule → dark.accent.amber (ΔE 0.016)", color: hazardCTAFill),
        .init("hazardCTAText", .derived, light: 0xFFFFFF, dark: 0x0E1712,
              basis: "its fill inverts, so it inverts; cf. ctaLabel", color: hazardCTAText),

        // Badges.
        .init("cityRecordBadgeFill", .derived, light: 0xEAF0E2, dark: 0x1F3A2C,
              basis: "the thriving/taped badge pair, one shade apart", color: cityRecordBadgeFill),
        .init("cityRecordBadgeText", .derived, light: 0x41522F, dark: 0x8EC3A5,
              basis: "the thriving/taped badge pair; 6.2:1", color: cityRecordBadgeText),
        .init("plantedBadgeFill", .derived, light: 0xEAF0E2, dark: 0x1F3A2C,
              basis: "the thriving/taped badge pair", color: plantedBadgeFill),
        .init("plantedBadgeText", .derived, light: 0x41522F, dark: 0x8EC3A5,
              basis: "the thriving/taped badge pair; 6.2:1", color: plantedBadgeText),
        .init("removedBadgeFill", .derived, light: 0xE4E6DC, dark: 0x27352B,
              basis: "tinted-fill rule, house green → dark.border", color: removedBadgeFill),
        .init("removedBadgeText", .derived, light: 0x5C6555, dark: 0x94A496,
              basis: "muted label → dark.text.muted; 4.9:1", color: removedBadgeText),

        // Memorial (19).
        .init("memorialBannerFill", .derived, light: 0xEDEEE6, dark: 0x27352B,
              basis: "tinted-fill rule → dark.border (ΔE 0.017)", color: memorialBannerFill),
        .init("memorialBannerBorder", .derived, light: 0xC4C8B8, dark: 0x39423A,
              basis: "border rule; same as border.memorial", color: memorialBannerBorder),
        .init("memorialBannerText", .derived, light: 0x4A5344, dark: 0xAEBBAB,
              basis: "→ dark.text.secondary; 6.4:1", color: memorialBannerText),

        .init("speciesTileLockedGlyph", .overruled, light: 0x7F8974, dark: 0x647062,
              basis: "R8: lightness-only to 3.06:1 / 3.05:1 — it is the tile's only visible content",
              color: speciesTileLockedGlyph),

        // C10 tile bases (12, 13) — each keeps its own accent's hue so the five stay told apart.
        .init("TileAccent.bloom.base", .derived, light: 0xF6E8E4, dark: 0x38292B,
              basis: "tinted-fill rule at the bloom hue", color: TileAccent.bloom.base),
        .init("TileAccent.elder.base", .derived, light: 0xE7EFE2, dark: 0x27352B,
              basis: "tinted-fill rule at the elder hue", color: TileAccent.elder.base),
        .init("TileAccent.newGrowth.base", .derived, light: 0xEDF2E0, dark: 0x1F2E22,
              basis: "tinted-fill rule at the new-growth hue", color: TileAccent.newGrowth.base),
        .init("TileAccent.vacantSite.base", .derived, light: 0xFAFBF4, dark: 0x18251D,
              basis: "R10: surfaceEmptyThumb — no new hue, the empty-well ground",
              color: TileAccent.vacantSite.base),
        .init("TileAccent.water.base", .derived, light: 0xE8EEF2, dark: 0x282F34,
              basis: "tinted-fill rule at the water hue", color: TileAccent.water.base),
        .init("TileAccent.record.base", .derived, light: 0xF4F0DE, dark: 0x322E1A,
              basis: "tinted-fill rule at the record hue", color: TileAccent.record.base),

        // Screen 12 §3's composition track.
        .init("compositionTrack", .derived, light: 0xEDEFE3, dark: 0x27352B,
              basis: "the same faint neutral rule chartGridline is; border rule → dark.border",
              color: compositionTrack),
    ]

    // MARK: Overruled — reverse these or keep them

    /// The five values RULINGS R1 changed after they had been transcribed from SCREENS.md. Every
    /// other row in this sheet is a value the document never gave; these five are values it gave
    /// and that were replaced anyway, so they are the only rows where a designer is being told
    /// their own hex was substituted for rather than filled in. `light` is the shipped value; the
    /// hex the designer wrote is in the basis line, so review is a two-column read.
    ///
    /// Reversing one is one line here and one line on the token. What comes back with it is the
    /// AA failure in ERRATA E106, so the reversal wants an answer to that in the same pass.
    static let overruledTokens: [CypressReviewToken] = [
        .init("textFaint", .overruled, light: 0x697260, dark: 0x7E8F80,
              basis: "R1 · was #8B9482 ↔ #5F6F61; 2.90/3.16 light and 3.42/2.98 dark → 4.62/5.03 and 5.33/4.64",
              color: textFaint),
        .init("textFaintAlt", .overruled, light: 0x5D6855, dark: 0x7E8F80,
              basis: "R1 · was #77836F ↔ #5F6F61; 3.67 → 5.40 on the screen, keeping its place between faint and muted",
              color: textFaintAlt),
        .init("textMuted", .overruled, light: 0x535F4C, dark: 0x94A496,
              basis: "R1 · was #66735F in light; 4.62 → 6.21, so the rung above faint is visibly above it. Dark is untouched.",
              color: textMuted),
        .init("estimatedBadgeText", .overruled, light: 0x836324, dark: 0xD99A4E,
              basis: "R1 · was #8A6A2A in light; 4.19 → 4.64 on its fill. D7 meaning. Dark is untouched.",
              color: estimatedBadgeText),
        .init("amberAttentionCardBorder", .overruled, light: 0xB8803A, dark: 0xD99A4E,
              basis: "R1 · was #D9A05B in light; 2.30 → 3.39 on the card and 2.12 → 3.12 on the page. Dark is the derived amber, untouched.",
              color: amberAttentionCardBorder),
        .init("searchGlyph", .overruled, light: 0x6C7764, dark: 0x94A496,
              basis: "R1a · was #77836F in light; 3.93 → 4.63 on the search fill composited over the map paper. Dark is D1's #94A496 at 6.06, untouched.",
              color: searchGlyph),
        // One value and no pair: screen 04 is dark whether or not the phone is.
        .init("Dark.textFaint", .overruled, light: 0x7E8F80,
              basis: "R1a · was #5F6F61; 2.99 → 4.66 on 04's note field, 3.23 → 5.03 on the tray, 3.44 → 5.36 on the shell. Now textFaint's dark half exactly.",
              color: Dark.textFaint),
    ]

    // MARK: Escalated — answer these

    static let escalatedTokens: [CypressReviewToken] = [
        .init("calloutGradient", .escalated, light: 0xEAF2E6,
              basis: "a two-stop wash is a drawing, not a value; D1–D3 never draw one",
              color: lightOnly(0xEAF2E6), gradient: calloutGradient),
        .init("borderCalloutGradient", .escalated, light: 0xD9E3C8,
              basis: "bounds a fill that stays light", color: borderCalloutGradient),
        .init("calloutGradientBorder", .escalated, light: 0xD9E3C8,
              basis: "bounds a fill that stays light", color: calloutGradientBorder),
        .init("calloutGradientInk", .escalated, light: 0x1C2A21,
              basis: "rides on a fill that stays light", color: calloutGradientInk),
        .init("textOnDark", .escalated, light: 0xFFFFFF,
              basis: "#FFFFFF has three documented darks; the call sites disagree", color: textOnDark),
        .init("pinRemovedFill", .escalated, light: 0xC4C8B8,
              basis: "D1 draws every pin but this one, and says so", color: pinRemovedFill),
        .init("compositionSwatch1", .escalated, light: 0x1D4634,
              basis: "12 §3's four swatches are a series; separation is between them, not per colour",
              color: compositionSwatches[0]),
        .init("compositionSwatch2", .escalated, light: 0x4E8F6A,
              basis: "12 §3's four swatches are a series", color: compositionSwatches[1]),
        .init("compositionSwatch3", .escalated, light: 0x7A4F33,
              basis: "12 §3's four swatches are a series", color: compositionSwatches[2]),
        .init("compositionOther", .escalated, light: 0xC2CAB4,
              basis: "the neutral member of that series; 'everyone else' has no other value",
              color: compositionOther),
        .init("pinRemovedBar", .escalated, light: 0x7A8272,
              basis: "with the pin it sits in", color: pinRemovedBar),
        .init("pinRouteDone", .escalated, light: 0xAEBFA1,
              basis: "same muted-pin family", color: pinRouteDone),
        .init("toggleKnob", .escalated, light: 0xFFFFFF,
              basis: "two tracks, opposite answers; 17 has no dark mock", color: toggleKnob),
        .init("chartSeriesPrimary", .escalated, light: 0x2F6B4F,
              basis: "series separation collapses 0.117 → 0.011; 2.5:1 on a dark card",
              color: chartSeriesPrimary),
        .init("chartSeriesSecondary", .escalated, light: 0x4E8F6A,
              basis: "chosen as a set with series 1 and 3", color: chartSeriesSecondary),
        .init("chartSeriesTertiary", .escalated, light: 0x7A4F33,
              basis: "chosen as a set; 2.3:1 on a dark card", color: chartSeriesTertiary),
        .init("TileAccent.bloom.accent", .escalated, light: 0xD77A8A,
              basis: "0% stop of a radial that fades by 55%", color: TileAccent.bloom.accent),
        .init("TileAccent.elder.accent", .escalated, light: 0x4E8F6A,
              basis: "the rule lands it 0.031 from dark.accent.pin, a reserved meaning",
              color: TileAccent.elder.accent),
        .init("TileAccent.newGrowth.accent", .escalated, light: 0x8FB573,
              basis: "the rule moves it by less than one RGB step", color: TileAccent.newGrowth.accent),
        .init("TileAccent.water.accent", .escalated, light: 0x7FA8C4,
              basis: "the rule moves it by less than one RGB step", color: TileAccent.water.accent),
        .init("TileAccent.record.accent", .escalated, light: 0xC9B44A,
              basis: "the five tile accents want deciding as one set", color: TileAccent.record.accent),
    ]
}
