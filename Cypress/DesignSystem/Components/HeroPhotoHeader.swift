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

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
        // ══════════════════════════════════════════════════════════════════════════════════════
        // A ZStack, not four `.overlay`s on a fixed-height photo.
        //
        // §2 C2 gives the hero a `height` — 224 pt on 03, 190 on 07, 200 on 19 — and the drawn
        // size is unchanged at the mock's type size. What changed is what happens above it. An
        // overlay does not contribute to its parent's size, so the eyebrow, the 07 name block and
        // the meta pill were laid out inside a box that could not grow for them: at AX sizes the
        // 25 pt serif species name simply drew past the bottom edge and over the strip below it,
        // and the `.clipped()` on the photo did not catch it because the overlays are added after.
        //
        // In a ZStack the content is a real child, so the header is `max(drawn height, what the
        // text needs)`. The photo takes `minHeight` and stretches to match; nothing moves at the
        // sizes the mock was drawn at.
        // ══════════════════════════════════════════════════════════════════════════════════════
        ZStack(alignment: .bottomLeading) {
            background
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                // The photo (today a gradient — SCREENS.md §5 gap 13) and the scrim over it are
                // the ground the text sits on. Neither says anything a listener does not get from
                // the eyebrow, the name block and the pill drawn on top of them.
                .accessibilityHidden(true)
                .overlay { style.scrim.accessibilityHidden(true) }

            // Eyebrow and meta pill sit at opposite ends of one line in the mock. At AX5 the pill
            // alone is wider than the phone, so across becomes down — and the block gets clear of
            // the back circle, which the eyebrow was otherwise growing up into.
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: CypressSpacing.gapDense) {
                        bottomLeadingContent
                        // The pill carries its own trailing inset for the mock's right-aligned
                        // placement; stacked at the leading edge it needs the eyebrow's.
                        pill.padding(.leading, CypressSpacing.Component.heroEyebrowLeading)
                    }
                    .padding(.top, CypressSpacing.Component.heroBackTop + CypressSpacing.Component.backCircle)
                } else {
                    HStack(alignment: .bottom, spacing: CypressSpacing.gapDense) {
                        bottomLeadingContent
                        Spacer(minLength: 0)
                        pill
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: style.height)
        .overlay(alignment: .topLeading) { backButton }
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
                .fixedSize(horizontal: false, vertical: true)
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
