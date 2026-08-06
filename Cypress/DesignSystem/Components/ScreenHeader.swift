//
//  ScreenHeader.swift
//  Cypress — DesignSystem/Components
//
//  C1 · `ScreenHeader` — SCREENS.md §2.
//  Back circle + serif title + optional trailing pill. Used by 02, 05, 06, 11, 12, 13, 14, 16, 17, D3.
//

import SwiftUI

struct ScreenHeader<Trailing: View>: View {

    /// `padding: 10px 18px 4px`; 02 uses `10px 18px 6px`.
    enum BottomInset {
        case standard
        case wide

        var value: CGFloat {
            switch self {
            case .standard: return CypressSpacing.headerPaddingBottom
            case .wide: return CypressSpacing.headerPaddingBottom02
            }
        }
    }

    let title: String
    var bottomInset: BottomInset = .standard
    var onBack: (() -> Void)?
    @ViewBuilder var trailing: Trailing

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // ══════════════════════════════════════════════════════════════════════════════════════
        // One row at the drawn sizes, two once the title cannot share one.
        //
        // This was the worst Dynamic Type failure in the app and it is worth describing, because
        // the symptom looks nothing like the cause. §2 C1 is `[back circle] [title] [pill]` on one
        // line, and `HeaderPill` ends in `.fixedSize()` so the pill always takes its intrinsic
        // width. At AX5 on a 393 pt phone the circle takes 44, the pill's "under a minute" takes
        // ~300, and the 22 pt serif title is left with about 60 pt — into which it wraps *one
        // letter per line*. Screen 05 rendered as a vertical column spelling C-h-e-c-k-–-i down
        // the whole viewport with the card pushed off the bottom.
        //
        // Two lines rather than a truncated pill or a scaled title: the pill is real information
        // on every screen that has one (`under a minute` on 05, `Outer Sunset` on 12, the tree's
        // name on 11 and 13, `3 waiting · offline` on 17) and the title is what the screen is. At
        // a size where both cannot fit across, the honest layout is one under the other.
        // ══════════════════════════════════════════════════════════════════════════════════════
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: CypressSpacing.Component.headerSpacing) {
                    HStack(spacing: CypressSpacing.Component.headerSpacing) {
                        backButton
                        titleText
                        Spacer(minLength: 0)
                    }
                    trailing
                }
            } else {
                HStack(spacing: CypressSpacing.Component.headerSpacing) {
                    backButton
                    titleText
                    Spacer(minLength: 0)
                    trailing
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, CypressSpacing.headerPaddingTop)
        .padding(.horizontal, CypressSpacing.headerPaddingHorizontal)
        .padding(.bottom, bottomInset.value)
    }

    @ViewBuilder
    private var backButton: some View {
        if let onBack {
            Button(action: onBack) { BackCircle() }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
        }
    }

    private var titleText: some View {
        Text(title)
            .font(CypressFont.screenTitle)
            .foregroundStyle(CypressColor.textInk)
            .fixedSize(horizontal: false, vertical: true)
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(title: String, bottomInset: BottomInset = .standard, onBack: (() -> Void)? = nil) {
        self.init(title: title, bottomInset: bottomInset, onBack: onBack) { EmptyView() }
    }
}

extension ScreenHeader where Trailing == HeaderPill {
    /// The common case: a plain trailing pill, e.g. `under a minute` (05) or `Outer Sunset` (12).
    init(
        title: String,
        trailingPill: String,
        pillStyle: HeaderPill.Style = .neutral,
        bottomInset: BottomInset = .standard,
        onBack: (() -> Void)? = nil
    ) {
        self.init(title: title, bottomInset: bottomInset, onBack: onBack) {
            HeaderPill(trailingPill, style: pillStyle)
        }
    }
}

// MARK: - Pieces

/// 44×44 circle, `1px` border, `shadow.restSoft`. Already at the 44pt minimum, so no hit-area
/// expansion is needed. Dark (D3): `#18251D` fill, `#27352B` border, `#AEBBAB` chevron, no shadow.
struct BackCircle: View {
    var body: some View {
        Circle()
            .fill(CypressColor.surfaceCard)
            .overlay { Circle().strokeBorder(CypressColor.borderCool, lineWidth: 1) }
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
            .cypressShadow(light: CypressShadow.restSoft, dark: nil)
            .contentShape(Circle())
            .accessibilityHidden(true)
    }
}

/// C1's optional trailing pill. `neutral` is the documented default; `amber` is 17's
/// `3 waiting · offline`.
struct HeaderPill: View {
    enum Style {
        case neutral
        case amber
    }

    let text: String
    var style: Style = .neutral

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(_ text: String, style: Style = .neutral) {
        self.text = text
        self.style = style
    }

    var body: some View {
        Text(text)
            .font(style == .amber ? CypressFont.body12Bold : CypressFont.body12)
            .foregroundStyle(
                style == .amber ? CypressColor.amberPillText : CypressColor.textMuted
            )
            .padding(.vertical, CypressSpacing.Component.headerPillPaddingV)
            .padding(.horizontal, CypressSpacing.Component.headerPillPaddingH)
            .background {
                Capsule().fill(
                    style == .amber ? CypressColor.amberPillFill : CypressColor.surfaceCard
                )
            }
            .cypressPillBorder(
                style == .amber ? (DesignProposalVariant.amberPillBorder ?? CypressColor.amberPillBorder) : CypressColor.borderCool
            )
            // Intrinsic width while the pill shares a row with the title, so it never compresses to
            // an ellipsis beside it. Once C1 has moved it onto its own line there is no competition
            // and a long pill may wrap — `3 waiting · offline` at AX5 needs two lines and has one.
            .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: true)
    }
}
