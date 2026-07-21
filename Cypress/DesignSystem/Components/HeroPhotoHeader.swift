//
//  HeroPhotoHeader.swift
//  Cypress — DesignSystem/Components
//
//  C2 · `HeroPhotoHeader` — SCREENS.md §2. Screens 03, 07, 19 and D2.
//
//  The gradient stack is a *placeholder for photography* (§2 preamble). `background:` takes any
//  view, so swapping in a real image later is a one-line change at the call site; the scrim, back
//  button, eyebrow and meta pill stay put.
//

import SwiftUI

struct HeroPhotoHeader<Background: View, BottomLeading: View>: View {

    /// The four drawn heroes. Height, gradient and scrim travel together because §2 pairs them.
    enum Style: String, CaseIterable, Identifiable {
        /// 03 tree profile — 224pt.
        case profile
        /// 07 species page — 190pt.
        case species
        /// 19 memorial — 200pt, desaturated.
        case memorial
        /// D2 tree profile, dark — 224pt.
        case profileDark

        var id: String { rawValue }

        var height: CGFloat {
            switch self {
            case .profile, .profileDark: return CypressSpacing.Component.heroHeightProfile
            case .species: return CypressSpacing.Component.heroHeightSpecies
            case .memorial: return CypressSpacing.Component.heroHeightMemorial
            }
        }

        var recipe: CypressGradientRecipe {
            switch self {
            case .profile: return CypressGradient.heroProfile
            case .species: return CypressGradient.heroSpecies
            case .memorial: return CypressGradient.heroMemorial
            case .profileDark: return CypressGradient.heroProfileDark
            }
        }

        var scrim: LinearGradient {
            switch self {
            case .profile: return CypressGradient.Scrim.profile
            case .species: return CypressGradient.Scrim.species
            case .memorial: return CypressGradient.Scrim.memorial
            case .profileDark: return CypressGradient.Scrim.dark
            }
        }

        var pillFill: Color {
            switch self {
            case .profile, .species: return CypressColor.heroMetaPillFill
            case .memorial: return CypressColor.heroMetaPillFillMemorial
            case .profileDark: return CypressColor.heroMetaPillFillDark
            }
        }

        var onPhoto: Color {
            switch self {
            case .profile: return CypressColor.textOnPhoto
            case .species: return CypressColor.textOnPhotoSpecies
            case .memorial: return CypressColor.textOnPhotoMemorial
            case .profileDark: return CypressColor.textOnPhotoDark
            }
        }

        /// D2 gives the back circle a `1px #2B3A2C` edge; the light heroes have none.
        var backBorder: Color? {
            self == .profileDark ? CypressColor.Dark.borderAlt : nil
        }
    }

    let style: Style
    /// Bottom-right pill, e.g. `214 photos · since 2019`.
    var metaPill: String?
    /// Bottom-left eyebrow, e.g. `Best photo · Oct 2025`. D2 drops it.
    var eyebrow: String?
    var onBack: (() -> Void)?
    /// Replaces the gradient placeholder with real photography.
    @ViewBuilder var background: Background
    /// 07 puts a name block here instead of a plain eyebrow.
    @ViewBuilder var bottomLeading: BottomLeading

    var body: some View {
        background
            .frame(height: style.height)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay { style.scrim }
            .overlay(alignment: .topLeading) { backButton }
            .overlay(alignment: .bottomLeading) { bottomLeadingContent }
            .overlay(alignment: .bottomTrailing) { pill }
    }

    @ViewBuilder
    private var backButton: some View {
        if let onBack {
            Button(action: onBack) {
                Circle()
                    .fill(CypressColor.heroBackFill)
                    .overlay {
                        if let border = style.backBorder {
                            Circle().strokeBorder(border, lineWidth: 1)
                        }
                    }
                    .overlay {
                        CypressChevron()
                            .stroke(
                                CypressColor.textBody,
                                style: StrokeStyle(
                                    lineWidth: CypressSpacing.Component.chevronStroke,
                                    lineCap: .round,
                                    lineJoin: .round
                                )
                            )
                            .frame(
                                width: CypressSpacing.Component.chevronWidth,
                                height: CypressSpacing.Component.chevronHeight
                            )
                    }
                    .frame(
                        width: CypressSpacing.Component.backCircle,
                        height: CypressSpacing.Component.backCircle
                    )
                    .cypressShadow(CypressShadow.heroButton)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            .padding(.leading, CypressSpacing.Component.heroBackLeading)
            .padding(.top, CypressSpacing.Component.heroBackTop)
        }
    }

    @ViewBuilder
    private var bottomLeadingContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            bottomLeading
            if let eyebrow {
                Text(eyebrow).cypressHeroEyebrow(color: style.onPhoto)
            }
        }
        .padding(.leading, CypressSpacing.Component.heroEyebrowLeading)
        .padding(.bottom, CypressSpacing.Component.heroBottomInset)
    }

    @ViewBuilder
    private var pill: some View {
        if let metaPill {
            Text(metaPill)
                .font(CypressFont.mono105)
                .foregroundStyle(style.onPhoto)
                .padding(.vertical, CypressSpacing.Component.heroPillPaddingV)
                .padding(.horizontal, CypressSpacing.Component.heroPillPaddingH)
                .background { Capsule().fill(style.pillFill) }
                .padding(.trailing, CypressSpacing.Component.heroPillTrailing)
                .padding(.bottom, CypressSpacing.Component.heroBottomInset)
        }
    }
}

// MARK: - Convenience initialisers

extension HeroPhotoHeader where Background == CypressGradientField, BottomLeading == EmptyView {
    /// The placeholder hero: §2's gradient stack, no custom bottom-left block.
    init(
        style: Style,
        metaPill: String? = nil,
        eyebrow: String? = nil,
        onBack: (() -> Void)? = nil
    ) {
        self.init(
            style: style,
            metaPill: metaPill,
            eyebrow: eyebrow,
            onBack: onBack,
            background: { CypressGradientField(style.recipe) },
            bottomLeading: { EmptyView() }
        )
    }
}

extension HeroPhotoHeader where Background == CypressGradientField {
    /// The placeholder hero with a custom bottom-left block — 07's name/latin stack.
    init(
        style: Style,
        metaPill: String? = nil,
        eyebrow: String? = nil,
        onBack: (() -> Void)? = nil,
        @ViewBuilder bottomLeading: () -> BottomLeading
    ) {
        self.init(
            style: style,
            metaPill: metaPill,
            eyebrow: eyebrow,
            onBack: onBack,
            background: { CypressGradientField(style.recipe) },
            bottomLeading: bottomLeading
        )
    }
}
