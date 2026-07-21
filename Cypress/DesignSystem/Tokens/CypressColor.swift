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
//  Where SCREENS.md documents no dark counterpart for a token, the light value is used in
//  both schemes and the line is marked `// TODO: no dark value specified in SCREENS.md`.
//  No dark value is invented here.
//
//  Screen 04 (camera) and D1–D3 are dark regardless of the system setting. Those views use
//  `CypressColor.Dark.*`, which is the flat, non-resolving dark palette.
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

    /// A token SCREENS.md §1 gives for light only. Resolves to the same value in both schemes
    /// deliberately; see the file header. Every call site carries the TODO marker.
    static func lightOnly(_ hex: UInt32, alpha: Double = 1) -> Color {
        Color(cypressHex: hex, alpha: alpha)
    }

    // MARK: - §1.1 Brand palette ("Palette · from the tree itself")
    //
    // Six named brand hues. SCREENS.md gives no dark counterpart for the hues themselves;
    // dark screens re-derive their accents from the `dark.accent.*` rows (see `rolePairs` below).

    /// Cypress Deep `#1D4634` — primary buttons, active nav, cluster badges, dark header.
    // TODO: no dark value specified in SCREENS.md
    static let cypressDeep = lightOnly(0x1D4634)
    /// Swatch text color that rides on Cypress Deep — `#DFE8D6`.
    static let onCypressDeep = lightOnly(0xDFE8D6)

    /// Canopy `#2F6B4F` — links, selection borders, pins, selected chips.
    // TODO: no dark value specified in SCREENS.md
    static let canopy = lightOnly(0x2F6B4F)
    /// Swatch text color that rides on Canopy — `#E8F0E4`.
    static let onCanopy = lightOnly(0xE8F0E4)

    /// New Growth `#4E8F6A` — secondary accents, avatars, dark-mode CTA fill on 04.
    // TODO: no dark value specified in SCREENS.md
    static let newGrowth = lightOnly(0x4E8F6A)
    /// Swatch text color that rides on New Growth — `#10281C`.
    static let onNewGrowth = lightOnly(0x10281C)

    /// Bark `#7A4F33` — third-series charts, avatar accent.
    // TODO: no dark value specified in SCREENS.md
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
    // TODO: no dark value specified in SCREENS.md
    static let pageParchment = lightOnly(0xEBE8DC)

    /// `surface.screen` `#F5F6EF` ↔ `dark.bg.screen` `#0E1712` — mobile screen background.
    static let surfaceScreen = dynamic(light: 0xF5F6EF, dark: 0x0E1712)

    /// `surface.card` `#FFFFFF` ↔ `dark.surface.card` `#18251D` — cards, stat cards, list rows.
    static let surfaceCard = dynamic(light: 0xFFFFFF, dark: 0x18251D)

    /// `surface.sheet` `#FDFDF8` — bottom sheets (09, 10, 15).
    // TODO: no dark value specified in SCREENS.md
    static let surfaceSheet = lightOnly(0xFDFDF8)

    /// `surface.warmPanel` `#F7F5EC` — spec-page palette/type panels (not app UI).
    // TODO: no dark value specified in SCREENS.md
    static let surfaceWarmPanel = lightOnly(0xF7F5EC)

    /// `surface.web` `#FBFBF5` — W1 web header + fact column. W1 is out of scope for iOS.
    // TODO: no dark value specified in SCREENS.md
    static let surfaceWeb = lightOnly(0xFBFBF5)

    /// `surface.mapPaper` `#E9E5D4` ↔ `dark.bg.map` `#141E16` — map canvas ground (01, 15).
    static let surfaceMapPaper = dynamic(light: 0xE9E5D4, dark: 0x141E16)

    /// `surface.mapGrid` `#F7F4E6` ↔ `dark.map.grid` `#1C2A1F` — map street grid stripes.
    static let surfaceMapGrid = dynamic(light: 0xF7F4E6, dark: 0x1C2A1F)

    /// `surface.mapStreetBand` `#FAF7EC` ↔ `dark.map.street` `#232F24` — named street bands on 01.
    static let surfaceMapStreetBand = dynamic(light: 0xFAF7EC, dark: 0x232F24)

    /// `surface.routeMap` `#E4E9D3` — mini route map on 18.
    // TODO: no dark value specified in SCREENS.md
    static let surfaceRouteMap = lightOnly(0xE4E9D3)
    /// `surface.routeMap` border `#DBE0CB`.
    // TODO: no dark value specified in SCREENS.md
    static let borderRouteMap = lightOnly(0xDBE0CB)
    /// `surface.routeMap` grid `#F4F1E2`.
    // TODO: no dark value specified in SCREENS.md
    static let surfaceRouteMapGrid = lightOnly(0xF4F1E2)

    /// `surface.emptyThumb` `#FAFBF4` — cold-start empty photo well (14).
    // TODO: no dark value specified in SCREENS.md
    static let surfaceEmptyThumb = lightOnly(0xFAFBF4)

    /// `surface.skeleton` `#E3E8D9` — skeleton blocks behind sheets (09, 10).
    // TODO: no dark value specified in SCREENS.md
    static let surfaceSkeleton = lightOnly(0xE3E8D9)

    // MARK: - §1.2 Borders and hairlines

    /// `border.cool` `#E3E8D9` ↔ `dark.border` `#27352B` — default card / chip / row border.
    static let borderCool = dynamic(light: 0xE3E8D9, dark: 0x27352B)

    /// `border.warm` `#DDD9C9` — spec-page panel border (not app UI).
    // TODO: no dark value specified in SCREENS.md
    static let borderWarm = lightOnly(0xDDD9C9)

    /// `border.hairline` `#D8D4C4` — spec-page header/footer rule (not app UI).
    // TODO: no dark value specified in SCREENS.md
    static let borderHairline = lightOnly(0xD8D4C4)

    /// `border.dashed` `#C9D1BC` — optional-field dashed wells (05, 06, 09).
    // TODO: no dark value specified in SCREENS.md
    static let borderDashed = lightOnly(0xC9D1BC)

    /// `border.dashedStrong` `#C4CEB4` — empty photo well (14), `2px dashed`.
    // TODO: no dark value specified in SCREENS.md
    static let borderDashedStrong = lightOnly(0xC4CEB4)

    /// `border.sheetGrabber` `#DDE2D2` — 40×5 sheet grabber pill.
    // TODO: no dark value specified in SCREENS.md
    static let borderSheetGrabber = lightOnly(0xDDE2D2)

    /// `border.web.row` `#E9ECDE` — W1 fact-row separators. W1 is out of scope for iOS.
    // TODO: no dark value specified in SCREENS.md
    static let borderWebRow = lightOnly(0xE9ECDE)

    /// `border.calloutGreen` `#DFE6CD` — green callout border.
    // TODO: no dark value specified in SCREENS.md
    static let borderCalloutGreen = lightOnly(0xDFE6CD)

    /// `border.calloutGradient` `#D9E3C8` — "In July" / "New species!" gradient callout border.
    // TODO: no dark value specified in SCREENS.md
    static let borderCalloutGradient = lightOnly(0xD9E3C8)

    /// `border.amberSoft` `#EBD3A8` — amber pill borders.
    // TODO: no dark value specified in SCREENS.md
    static let borderAmberSoft = lightOnly(0xEBD3A8)

    /// `border.amberMid` `#D9A05B` — attention card border (`1.5px`).
    // TODO: no dark value specified in SCREENS.md
    static let borderAmberMid = lightOnly(0xD9A05B)

    /// `border.amberStrong` `#E0B070` — 311 hazard panel border (`1.5px`).
    // TODO: no dark value specified in SCREENS.md
    static let borderAmberStrong = lightOnly(0xE0B070)

    /// `border.memorial` `#C4C8B8` — memorial banner border (`1.5px`).
    // TODO: no dark value specified in SCREENS.md
    static let borderMemorial = lightOnly(0xC4C8B8)

    /// `border.account` `#D8DECB` — account sheet secondary buttons (`1.5px`).
    // TODO: no dark value specified in SCREENS.md
    static let borderAccount = lightOnly(0xD8DECB)

    /// `border.shareCard` `#E0DDC9` — share preview card.
    // TODO: no dark value specified in SCREENS.md
    static let borderShareCard = lightOnly(0xE0DDC9)

    /// `border.pinRing` `rgba(29,70,52,.14)` — gradient thumbnail hairline. (29,70,52) is Cypress Deep.
    // TODO: no dark value specified in SCREENS.md
    static let borderPinRing = lightOnly(0x1D4634, alpha: 0.14)

    /// `border.glass` `rgba(29,70,52,.10)` — search bar edge.
    // TODO: no dark value specified in SCREENS.md
    static let borderGlassSearch = lightOnly(0x1D4634, alpha: 0.10)
    /// `border.glass` `rgba(29,70,52,.12)` — filter chip edge.
    // TODO: no dark value specified in SCREENS.md
    static let borderGlassChip = lightOnly(0x1D4634, alpha: 0.12)
    /// `border.glass` `rgba(29,70,52,.08)` — bottom bar top edge.
    // TODO: no dark value specified in SCREENS.md
    static let borderGlassBottomBar = lightOnly(0x1D4634, alpha: 0.08)

    // MARK: - §1.2 Text

    /// `text.ink` `#1C2A21` ↔ `dark.text.primary` `#E4EBE2` — primary text, headings.
    static let textInk = dynamic(light: 0x1C2A21, dark: 0xE4EBE2)

    /// `text.body` `#3C4A3E` ↔ `dark.text.secondary` `#AEBBAB` — secondary body, unselected chips.
    static let textBody = dynamic(light: 0x3C4A3E, dark: 0xAEBBAB)

    /// `text.muted` `#66735F` ↔ `dark.text.muted` `#94A496` — captions, Latin names, sublabels.
    static let textMuted = dynamic(light: 0x66735F, dark: 0x94A496)

    /// `text.faint` `#8B9482` ↔ `dark.text.faint` `#5F6F61` — micro-labels, timestamps, mono meta.
    static let textFaint = dynamic(light: 0x8B9482, dark: 0x5F6F61)

    /// `text.faintAlt` `#77836F` ↔ `#5F6F61` — footnote lines under screens.
    ///
    /// §1.2 gives no dark counterpart, but D3's delta list does, in prose: "Footnote `#5F6F61`" —
    /// the same `dark.text.faint` value `textFaint` already carries. Transcribed as light-only
    /// originally, which is the same miss as the taped badge below. See ERRATA (E27).
    static let textFaintAlt = dynamic(light: 0x77836F, dark: 0x5F6F61)

    /// `text.onDark` `#FFFFFF` — on Cypress Deep / Canopy fills.
    /// Identical in both schemes by definition: it rides on a dark fill, not on the page.
    static let textOnDark = lightOnly(0xFFFFFF)

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

    /// `taped` method badge fill `#E2EFE2` (03, 11, W1).
    // TODO: no dark value specified in SCREENS.md
    /// SCREENS.md D2 states it outright: "both method badges keep their meaning in the dark …
    /// `taped` → `#8EC3A5` on `#1F3A2C`" — the same pair as the thriving badge. Transcribed as
    /// light-only originally; two agents independently hit it rendering screen D2.
    static let tapedBadgeFill = dynamic(light: 0xE2EFE2, dark: 0x1F3A2C)
    /// `taped` method badge text `#28623F`.
    // TODO: no dark value specified in SCREENS.md
    static let tapedBadgeText = dynamic(light: 0x28623F, dark: 0x8EC3A5)

    /// `est.` / `estimated` badge fill `#F1EAD8` ↔ `dark.accent.amberBg` `#2E271A`.
    static let estimatedBadgeFill = dynamic(light: 0xF1EAD8, dark: 0x2E271A)
    /// `est.` / `estimated` badge text `#8A6A2A` ↔ `dark.accent.amber` `#D99A4E`.
    static let estimatedBadgeText = dynamic(light: 0x8A6A2A, dark: 0xD99A4E)

    /// `city record` badge fill `#EAF0E2` (14).
    // TODO: no dark value specified in SCREENS.md
    static let cityRecordBadgeFill = lightOnly(0xEAF0E2)
    /// `city record` badge text `#41522F`.
    // TODO: no dark value specified in SCREENS.md
    static let cityRecordBadgeText = lightOnly(0x41522F)

    /// `PLANTED 2024` badge fill `#EAF0E2` (14).
    // TODO: no dark value specified in SCREENS.md
    static let plantedBadgeFill = lightOnly(0xEAF0E2)
    /// `PLANTED 2024` badge text `#41522F`.
    // TODO: no dark value specified in SCREENS.md
    static let plantedBadgeText = lightOnly(0x41522F)

    /// `REMOVED` badge fill `#E4E6DC` (19).
    // TODO: no dark value specified in SCREENS.md
    static let removedBadgeFill = lightOnly(0xE4E6DC)
    /// `REMOVED` badge text `#5C6555`.
    // TODO: no dark value specified in SCREENS.md
    static let removedBadgeText = lightOnly(0x5C6555)

    /// Green callout fill `#EFF3E3` ↔ `dark.surface.callout` `#1A241A` (03, 14, 16, 19; D2).
    static let calloutGreenFill = dynamic(light: 0xEFF3E3, dark: 0x1A241A)
    /// Green callout border `#DFE6CD`. Same value as `border.calloutGreen`.
    // TODO: no dark value specified in SCREENS.md
    static let calloutGreenBorder = lightOnly(0xDFE6CD)
    /// Green callout text `#41522F`.
    // TODO: no dark value specified in SCREENS.md
    static let calloutGreenText = lightOnly(0x41522F)

    /// Gradient callout border `#D9E3C8` (07, 08). See `calloutGradient` for the fill.
    // TODO: no dark value specified in SCREENS.md
    static let calloutGradientBorder = lightOnly(0xD9E3C8)
    /// Gradient callout text `#1C2A21` — the `text.ink` token, so it carries ink's dark pair.
    static let calloutGradientText = textInk

    /// Amber pill / banner fill `#F8EFDF` (02, 06, 17).
    // TODO: no dark value specified in SCREENS.md
    static let amberPillFill = lightOnly(0xF8EFDF)
    /// Amber pill / banner border `#EBD3A8`.
    // TODO: no dark value specified in SCREENS.md
    static let amberPillBorder = lightOnly(0xEBD3A8)
    /// Amber pill / banner text `#8A5A17`.
    // TODO: no dark value specified in SCREENS.md
    static let amberPillText = lightOnly(0x8A5A17)

    /// Amber selected chip fill `#F8EFDF` (06).
    // TODO: no dark value specified in SCREENS.md
    static let amberChipSelectedFill = lightOnly(0xF8EFDF)
    /// Amber selected chip border `#D9A05B` (`1.5px`).
    // TODO: no dark value specified in SCREENS.md
    static let amberChipSelectedBorder = lightOnly(0xD9A05B)
    /// Amber selected chip text `#8A5A17`.
    // TODO: no dark value specified in SCREENS.md
    static let amberChipSelectedText = lightOnly(0x8A5A17)

    /// Amber attention card fill `#FFFFFF` (12, 17) — the `surface.card` token.
    static let amberAttentionCardFill = surfaceCard
    /// Amber attention card border `#D9A05B` (`1.5px`).
    // TODO: no dark value specified in SCREENS.md
    static let amberAttentionCardBorder = lightOnly(0xD9A05B)

    /// 311 hazard panel fill `#F8EFDF` (06).
    // TODO: no dark value specified in SCREENS.md
    static let hazardPanelFill = lightOnly(0xF8EFDF)
    /// 311 hazard panel border `#E0B070` (`1.5px`).
    // TODO: no dark value specified in SCREENS.md
    static let hazardPanelBorder = lightOnly(0xE0B070)
    /// 311 hazard panel body text `#6B5122`.
    // TODO: no dark value specified in SCREENS.md
    static let hazardPanelText = lightOnly(0x6B5122)
    /// 311 hazard panel phone glyph `#FDF3E3`, on the 54×54 Signal Amber circle (06 §4).
    ///
    /// §1.2 has no row for this: the hex reaches SCREENS.md only as Signal Amber's *swatch text
    /// color* in §1.1, which is where 06 borrows it from. Recorded in ERRATA (E20).
    // TODO: no dark value specified in SCREENS.md
    static let hazardPanelGlyph = lightOnly(0xFDF3E3)

    /// 311 CTA button fill `#A35F12` (06).
    // TODO: no dark value specified in SCREENS.md
    static let hazardCTAFill = lightOnly(0xA35F12)
    /// 311 CTA button label `#FFFFFF`.
    static let hazardCTAText = lightOnly(0xFFFFFF)

    /// Memorial banner fill `#EDEEE6` (19).
    // TODO: no dark value specified in SCREENS.md
    static let memorialBannerFill = lightOnly(0xEDEEE6)
    /// Memorial banner border `#C4C8B8` (`1.5px`).
    // TODO: no dark value specified in SCREENS.md
    static let memorialBannerBorder = lightOnly(0xC4C8B8)
    /// Memorial banner text `#4A5344`.
    // TODO: no dark value specified in SCREENS.md
    static let memorialBannerText = lightOnly(0x4A5344)

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
    // TODO: no dark value specified in SCREENS.md
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
        /// `dark.text.muted` `#94A496` — sublabels.
        static let textMuted = Color(cypressHex: 0x94A496)
        /// `dark.text.faint` `#5F6F61` — micro-labels, inactive tabs.
        static let textFaint = Color(cypressHex: 0x5F6F61)

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

        var id: String { rawValue }

        var accent: Color {
            switch self {
            case .bloom: return CypressColor.lightOnly(0xD77A8A)
            case .elder: return CypressColor.lightOnly(0x4E8F6A)
            case .newGrowth: return CypressColor.lightOnly(0x8FB573)
            case .water: return CypressColor.lightOnly(0x7FA8C4)
            case .record: return CypressColor.lightOnly(0xC9B44A)
            }
        }

        // TODO: no dark values specified in SCREENS.md for the C10 tiles.
        var base: Color {
            switch self {
            case .bloom: return CypressColor.lightOnly(0xF6E8E4)
            case .elder: return CypressColor.lightOnly(0xE7EFE2)
            case .newGrowth: return CypressColor.lightOnly(0xEDF2E0)
            case .water: return CypressColor.lightOnly(0xE8EEF2)
            case .record: return CypressColor.lightOnly(0xF4F0DE)
            }
        }
    }

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
    static let calloutGradientInk = lightOnly(0x1C2A21)

    // MARK: C16 · BottomTabBar

    /// Tab bar background — `rgba(250,250,244,.95)` ↔ D1 `rgba(16,24,18,.95)`.
    static let tabBarFill = dynamic(
        light: 0xFAFAF4, dark: 0x101812, lightAlpha: 0.95, darkAlpha: 0.95
    )
    /// Tab bar top hairline — `rgba(29,70,52,.08)` ↔ D1 `#26332A`.
    static let tabBarTopBorder = dynamic(
        light: 0x1D4634, dark: 0x26332A, lightAlpha: 0.08, darkAlpha: 1
    )
    /// Active tab tint — `#1D4634` ↔ `#8EC3A5`. (Inactive is `textFaint`, which already pairs
    /// `#8B9482` ↔ `#5F6F61`.)
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
    // TODO: no dark value specified in SCREENS.md (D1 omits the removed pin entirely).
    static let pinRemovedFill = lightOnly(0xC4C8B8)
    /// Removed pin's centred 8×2 bar — `#7A8272`.
    // TODO: no dark value specified in SCREENS.md
    static let pinRemovedBar = lightOnly(0x7A8272)
    /// Route "done" pin (18) — `#AEBFA1`.
    // TODO: no dark value specified in SCREENS.md
    static let pinRouteDone = lightOnly(0xAEBFA1)

    // MARK: C20 · SearchBar

    /// Search bar fill — `rgba(255,255,255,.94)` ↔ D1 `rgba(24,37,29,.94)`.
    static let searchFill = dynamic(
        light: 0xFFFFFF, dark: 0x18251D, lightAlpha: 0.94, darkAlpha: 0.94
    )
    /// Search bar border — `rgba(29,70,52,.1)` ↔ D1 `#2B3A2C`.
    static let searchBorder = dynamic(
        light: 0x1D4634, dark: 0x2B3A2C, lightAlpha: 0.10, darkAlpha: 1
    )
    /// Search glyph + placeholder — `#77836F` ↔ D1 `#94A496`.
    static let searchGlyph = dynamic(light: 0x77836F, dark: 0x94A496)

    // MARK: C23 · ChartCard

    /// Gridlines and empty bars — `#EAEDDF`.
    // TODO: no dark value specified in SCREENS.md
    static let chartGridline = lightOnly(0xEAEDDF)
    /// Series 1 (photos, DBH, height) — Canopy.
    static let chartSeriesPrimary = canopy
    /// Series 2 (check-ins) — New Growth.
    static let chartSeriesSecondary = newGrowth
    /// Series 3 (care) — Bark.
    static let chartSeriesTertiary = bark

    // MARK: C26 · AvatarStack

    /// Avatar ring — `2px solid #fff`.
    // TODO: no dark value specified in SCREENS.md
    static let avatarRing = lightOnly(0xFFFFFF)
    /// Avatar fills in the drawn order: `#2F6B4F`, `#7A4F33`, `#4E8F6A`, `#66735F`.
    static let avatarFills: [Color] = [canopy, bark, newGrowth, lightOnly(0x66735F)]

    // MARK: C27 · ProgressRing

    /// Ring track — `#E0E6D8`.
    // TODO: no dark value specified in SCREENS.md
    static let progressRingTrack = lightOnly(0xE0E6D8)
    /// Inner disc — `#F5F6EF`, the `surface.screen` value.
    static let progressRingInner = surfaceScreen

    // MARK: C25 · Toggle

    /// Toggle knob — `#FFFFFF`.
    static let toggleKnob = lightOnly(0xFFFFFF)
    /// Toggle off track. **NOT SPECIFIED** in SCREENS.md (§5 gap 4); `border.cool` is used so the
    /// off state reads as the same inactive hairline every other idle control uses.
    static let toggleOffTrack = borderCool

    // MARK: C29 · SpeciesTile

    /// Locked tile fill — `#E9ECDE`.
    // TODO: no dark value specified in SCREENS.md
    static let speciesTileLockedFill = lightOnly(0xE9ECDE)
    /// Locked tile `?` glyph — `#A8B29C`.
    // TODO: no dark value specified in SCREENS.md
    static let speciesTileLockedGlyph = lightOnly(0xA8B29C)
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
