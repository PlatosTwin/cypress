//
//  CypressShadow.swift
//  Cypress — DesignSystem/Tokens
//
//  Source of truth: docs/distilled/SCREENS.md §1.5 (shadows).
//
//  ── CSS → SwiftUI conversion ──────────────────────────────────────────────────────────────
//  CSS writes `box-shadow: <x> <y> <blur> <color>`. SwiftUI writes
//  `.shadow(color:radius:x:y:)`, where `radius` is a Gaussian sigma-ish value roughly HALF the
//  CSS blur. So `0 6px 20px rgba(...)` becomes `y: 6, radius: 10, x: 0`. That halving is applied
//  to every token below, consistently, with no per-token eyeballing.
//
//  ── Dark mode ─────────────────────────────────────────────────────────────────────────────
//  SCREENS.md §1.5: "Dark-mode cards (D2, D3) carry **no** shadow — they are separated by
//  `#27352B` borders only." `.cypressCardShadow()` encodes exactly that: `shadow.rest` in light,
//  nothing in dark. The doc's `shadow.dark.*` row lists five dark-mode elevations for the
//  elements that *do* keep a shadow (pins, FABs, sheets); those are `Dark.*` below.
//

import SwiftUI

/// One row of SCREENS.md §1.5, already converted to SwiftUI units.
struct CypressShadowStyle: Equatable {
    let color: Color
    /// SwiftUI blur radius — CSS blur ÷ 2.
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat

    /// Builds a token from the CSS values exactly as they appear in the doc.
    /// - Parameters:
    ///   - hex: the `rgba()` color as `0xRRGGBB`.
    ///   - opacity: the `rgba()` alpha.
    ///   - blur: the CSS blur radius in px. Halved for SwiftUI.
    ///   - offsetY: the CSS y offset in px. Passed through unchanged.
    ///   - offsetX: the CSS x offset in px. Every Cypress shadow uses 0.
    init(hex: UInt32, opacity: Double, blur: CGFloat, offsetY: CGFloat, offsetX: CGFloat = 0) {
        self.color = Color(cypressHex: hex, alpha: opacity)
        self.radius = blur / 2
        self.x = offsetX
        self.y = offsetY
    }
}

enum CypressShadow {

    // rgba(25,40,28)  = #19281C     rgba(47,107,79) = #2F6B4F (Canopy)
    // rgba(20,50,30)  = #14321E     rgba(20,40,26)  = #14281A
    // rgba(10,20,14)  = #0A140E     rgba(16,32,22)  = #102016
    // rgba(180,113,31)= #B4711F (Signal Amber)      rgba(163,95,18) = #A35F12

    /// `shadow.rest` `0 1px 3px rgba(25,40,28,.05)` — resting card / list row.
    static let rest = CypressShadowStyle(hex: 0x19281C, opacity: 0.05, blur: 3, offsetY: 1)

    /// `shadow.restSoft` `0 1px 4px rgba(25,40,28,.08)` — circular back button.
    static let restSoft = CypressShadowStyle(hex: 0x19281C, opacity: 0.08, blur: 4, offsetY: 1)

    /// `shadow.selected` `0 6px 20px rgba(47,107,79,.16)` — selected candidate card (02).
    static let selected = CypressShadowStyle(hex: 0x2F6B4F, opacity: 0.16, blur: 20, offsetY: 6)

    /// `shadow.selectedSm` `0 4px 12px rgba(47,107,79,.16)` — selected vitality row (05).
    static let selectedSm = CypressShadowStyle(hex: 0x2F6B4F, opacity: 0.16, blur: 12, offsetY: 4)

    /// `shadow.primary` `0 4px 14px rgba(20,50,30,.28)` — primary CTA button.
    static let primary = CypressShadowStyle(hex: 0x14321E, opacity: 0.28, blur: 14, offsetY: 4)

    /// `shadow.fab` `0 8px 24px rgba(20,50,30,.4)` — 01 floating "What tree is this?".
    static let fab = CypressShadowStyle(hex: 0x14321E, opacity: 0.40, blur: 24, offsetY: 8)

    /// `shadow.chipActive` `0 2px 8px rgba(20,50,30,.25)` — selected filter chip (01).
    static let chipActive = CypressShadowStyle(hex: 0x14321E, opacity: 0.25, blur: 8, offsetY: 2)

    /// `shadow.searchBar` `0 4px 16px rgba(20,40,26,.1)` — 01 search bar.
    static let searchBar = CypressShadowStyle(hex: 0x14281A, opacity: 0.10, blur: 16, offsetY: 4)

    /// `shadow.bottomCard` `0 10px 30px rgba(20,40,26,.16)` — 01 bottom tree card.
    static let bottomCard = CypressShadowStyle(hex: 0x14281A, opacity: 0.16, blur: 30, offsetY: 10)

    /// `shadow.sheet` `0 -12px 40px rgba(10,20,14,.32)` — bottom sheets. Note the negative y.
    static let sheet = CypressShadowStyle(hex: 0x0A140E, opacity: 0.32, blur: 40, offsetY: -12)

    /// `shadow.shareCard` `0 3px 12px rgba(25,40,28,.09)` — 10 preview card.
    static let shareCard = CypressShadowStyle(hex: 0x19281C, opacity: 0.09, blur: 12, offsetY: 3)

    /// `shadow.amberCard` `0 3px 12px rgba(180,113,31,.1)` — 12, 17 attention cards.
    static let amberCard = CypressShadowStyle(hex: 0xB4711F, opacity: 0.10, blur: 12, offsetY: 3)

    /// `shadow.hazard` `0 4px 14px rgba(163,95,18,.3)` — 06 "Call 311 now".
    static let hazard = CypressShadowStyle(hex: 0xA35F12, opacity: 0.30, blur: 14, offsetY: 4)

    /// `shadow.pin` `0 2px 6px rgba(20,40,26,.35)` — map pins.
    static let pin = CypressShadowStyle(hex: 0x14281A, opacity: 0.35, blur: 6, offsetY: 2)

    /// `shadow.pinMuted` `0 2px 6px rgba(20,40,26,.2)` — removed pin.
    static let pinMuted = CypressShadowStyle(hex: 0x14281A, opacity: 0.20, blur: 6, offsetY: 2)
    /// `shadow.pinMuted` `0 2px 6px rgba(20,40,26,.25)` — dashed community pin.
    static let pinMutedStrong = CypressShadowStyle(hex: 0x14281A, opacity: 0.25, blur: 6, offsetY: 2)

    /// `shadow.cluster` `0 2px 8px rgba(20,40,26,.35)` — cluster count badges.
    static let cluster = CypressShadowStyle(hex: 0x14281A, opacity: 0.35, blur: 8, offsetY: 2)

    /// `shadow.heroButton` `0 2px 8px rgba(16,32,22,.25)` — back button over a hero photo.
    static let heroButton = CypressShadowStyle(hex: 0x102016, opacity: 0.25, blur: 8, offsetY: 2)

    /// `shadow.toggleKnob` `0 1px 3px rgba(0,0,0,.2)` — 17 switch knob.
    static let toggleKnob = CypressShadowStyle(hex: 0x000000, opacity: 0.20, blur: 3, offsetY: 1)

    /// C29 species-tile label — `text-shadow: 0 1px 3px rgba(10,22,15,.5)`.
    static let speciesTileLabel = CypressShadowStyle(hex: 0x0A160F, opacity: 0.50, blur: 3, offsetY: 1)

    /// `shadow.dark.*` — the five dark-mode elevations. Cards do not use these (see file header);
    /// pins, FABs, hero buttons and sheets do.
    enum Dark {
        /// `0 2px 6px rgba(0,0,0,.5)` — dark map pin.
        static let sm = CypressShadowStyle(hex: 0x000000, opacity: 0.50, blur: 6, offsetY: 2)
        /// `0 2px 8px rgba(0,0,0,.5)` — dark cluster badge / hero button.
        static let md = CypressShadowStyle(hex: 0x000000, opacity: 0.50, blur: 8, offsetY: 2)
        /// `0 4px 16px rgba(0,0,0,.4)` — dark primary CTA.
        static let lg = CypressShadowStyle(hex: 0x000000, opacity: 0.40, blur: 16, offsetY: 4)
        /// `0 10px 30px rgba(0,0,0,.45)` — dark bottom card.
        static let xl = CypressShadowStyle(hex: 0x000000, opacity: 0.45, blur: 30, offsetY: 10)
        /// `0 8px 24px rgba(0,0,0,.5)` — dark FAB.
        static let fab = CypressShadowStyle(hex: 0x000000, opacity: 0.50, blur: 24, offsetY: 8)
    }
}

// MARK: - Modifiers

extension View {
    /// Applies a §1.5 shadow token. Pass `nil` to apply none (keeps call sites branch-free).
    @ViewBuilder
    func cypressShadow(_ style: CypressShadowStyle?) -> some View {
        if let style {
            shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
        } else {
            self
        }
    }

    /// Applies a light-scheme token and its dark-scheme counterpart, resolving off the environment.
    func cypressShadow(
        light: CypressShadowStyle?,
        dark: CypressShadowStyle?
    ) -> some View {
        modifier(CypressSchemeShadow(light: light, dark: dark))
    }

    /// The card elevation rule from SCREENS.md §1.5: `shadow.rest` in light, **no shadow** in
    /// dark, where cards are separated by `dark.border` alone.
    func cypressCardShadow() -> some View {
        modifier(CypressSchemeShadow(light: CypressShadow.rest, dark: nil))
    }
}

private struct CypressSchemeShadow: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let light: CypressShadowStyle?
    let dark: CypressShadowStyle?

    func body(content: Content) -> some View {
        content.cypressShadow(colorScheme == .dark ? dark : light)
    }
}
