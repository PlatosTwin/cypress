//
//  AttentionCard.swift
//  Cypress — DesignSystem/Components
//
//  C24 · `AttentionCard` — SCREENS.md §2. The amber card on 12 ("9 young trees with no visits since
//  planting") and the failed outbox row on 17.
//
//  Signal Amber is reserved: §1.1 says it is used "solely for 'this tree needs something'". The
//  card's own micro-label therefore takes `accentAmber` instead of `text.faint` — that color swap
//  is the whole point of the component, so it is exposed as `AttentionCard.sectionLabel`.
//

import SwiftUI

struct AttentionCard<Content: View>: View {

    enum Size {
        /// 12 — radius 16, `padding:14px 16px`.
        case standard
        /// 17 — radius 14, `padding:13px 14px`.
        case compact

        var radius: CGFloat {
            switch self {
            case .standard: return CypressRadius.cardMd
            case .compact: return CypressRadius.cardSm
            }
        }

        var paddingV: CGFloat {
            switch self {
            case .standard: return CypressSpacing.Component.attentionPaddingV
            case .compact: return CypressSpacing.Component.attentionPaddingVCompact
            }
        }

        var paddingH: CGFloat {
            switch self {
            case .standard: return CypressSpacing.Component.attentionPaddingH
            case .compact: return CypressSpacing.Component.attentionPaddingHCompact
            }
        }
    }

    var size: Size = .standard
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, size.paddingV)
            .padding(.horizontal, size.paddingH)
            .background {
                RoundedRectangle(cornerRadius: size.radius, style: .continuous)
                    .fill(CypressColor.amberAttentionCardFill)
            }
            .cypressBorder(
                CypressColor.amberAttentionCardBorder,
                radius: size.radius,
                width: CypressSpacing.Component.hairlineStrong
            )
            .cypressShadow(light: CypressShadow.amberCard, dark: nil)
    }

    /// The section micro-label that introduces an attention card — amber, not faint.
    /// e.g. `Where eyes are needed` (12).
    static func sectionLabel(_ text: String) -> some View {
        Text(text).cypressMicroLabel(color: CypressColor.accentAmber)
    }
}
