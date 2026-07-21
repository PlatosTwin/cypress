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

    var body: some View {
        HStack(spacing: CypressSpacing.Component.headerSpacing) {
            if let onBack {
                Button(action: onBack) { BackCircle() }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
            }
            Text(title)
                .font(CypressFont.screenTitle)
                .foregroundStyle(CypressColor.textInk)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            trailing
        }
        .padding(.top, CypressSpacing.headerPaddingTop)
        .padding(.horizontal, CypressSpacing.headerPaddingHorizontal)
        .padding(.bottom, bottomInset.value)
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
                style == .amber ? CypressColor.amberPillBorder : CypressColor.borderCool
            )
            .fixedSize()
    }
}
