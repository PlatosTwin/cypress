//
//  Callout.swift
//  Cypress — DesignSystem/Components
//
//  C14 · `Callout` and C15 · `OptionalWell` — SCREENS.md §2.
//
//  Four callout styles: green (recognize-it / lineage), gradient (seasonal / celebration),
//  memorial, and the dashed disclosure on 06. Each leads with a bold lead-in followed by prose,
//  so both are passed separately and the component owns the typography of each.
//

import SwiftUI

struct Callout: View {

    enum Style: String, CaseIterable, Identifiable {
        /// `#EFF3E3` / `1px #DFE6CD` / `#41522F` — 03, 14, 19 lineage. Dark (D2): `#1A241A` /
        /// `1px #27352B`, body `#B9C7B2`, lead-in `#D6E0CE`.
        case green
        /// `linear-gradient(120deg,#EAF2E6,#F6F2DF)` / `1px #D9E3C8` — 07 "In July", 08 "New species!".
        case gradient
        /// `#EDEEE6` / `1.5px #C4C8B8` / `#4A5344` — 19's removal banner.
        case memorial
        /// `1px dashed #C9D1BC` / `#66735F`, 12.5px — 06's hazard disclosure.
        case dashed

        var id: String { rawValue }

        var radius: CGFloat {
            switch self {
            case .green, .dashed: return CypressRadius.control
            case .gradient, .memorial: return CypressRadius.cardSm
            }
        }

        var paddingV: CGFloat {
            switch self {
            case .green: return CypressSpacing.Component.calloutPaddingV
            case .gradient: return CypressSpacing.Component.calloutPaddingVGradient
            case .memorial, .dashed: return CypressSpacing.Component.calloutPaddingVLarge
            }
        }

        var paddingH: CGFloat {
            switch self {
            case .green: return CypressSpacing.Component.calloutPaddingH
            case .gradient, .memorial, .dashed: return CypressSpacing.Component.calloutPaddingHGradient
            }
        }

        var font: Font {
            self == .dashed ? CypressFont.body125 : CypressFont.body135
        }

        var leadInFont: Font {
            self == .dashed ? CypressFont.body125Bold : CypressFont.body135Bold
        }

        var text: Color {
            switch self {
            case .green: return CypressColor.calloutGreenBody
            // The gradient fill has no dark counterpart, so its ink must not flip either.
            case .gradient: return CypressColor.calloutGradientInk
            case .memorial: return CypressColor.memorialBannerText
            case .dashed: return CypressColor.textMuted
            }
        }

        var borderWidth: CGFloat {
            self == .memorial
                ? CypressSpacing.Component.hairlineStrong
                : CypressSpacing.Component.hairline
        }

        var border: Color {
            switch self {
            case .green: return CypressColor.calloutGreenBorder
            case .gradient: return CypressColor.calloutGradientBorder
            case .memorial: return CypressColor.memorialBannerBorder
            case .dashed: return CypressColor.borderDashed
            }
        }
    }

    let style: Style
    /// The bold lead-in, e.g. `How to recognize it:`. Optional — 19's lineage callout has one,
    /// a plain paragraph does not.
    var leadIn: String?
    /// The rest, verbatim including its leading space.
    let text: String
    /// 19's green callout uses `radius:14px` and `padding:13px 15px` instead of the 03 values.
    var largePadding: Bool = false

    init(_ text: String, style: Style, leadIn: String? = nil, largePadding: Bool = false) {
        self.text = text
        self.style = style
        self.leadIn = leadIn
        self.largePadding = largePadding
    }

    var body: some View {
        content
            .lineSpacing(CypressFont.LineSpacing.body135)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(
                .vertical,
                largePadding ? CypressSpacing.Component.calloutPaddingVLarge : style.paddingV
            )
            .padding(
                .horizontal,
                largePadding ? CypressSpacing.Component.calloutPaddingHLarge : style.paddingH
            )
            .background { background }
            .overlay {
                if style != .dashed {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(style.border, lineWidth: style.borderWidth)
                }
            }
            .modifier(DashedIfNeeded(style: style, radius: radius))
    }

    private var radius: CGFloat {
        largePadding ? CypressRadius.cardSm : style.radius
    }

    private var content: Text {
        if let leadIn {
            return cypressLeadInText(
                leadIn,
                text,
                leadInFont: style.leadInFont,
                restFont: style.font,
                leadInColor: leadInColor,
                restColor: style.text
            )
        }
        return Text(text).font(style.font).foregroundColor(style.text)
    }

    /// D2 lifts the lead-in to `#D6E0CE` against the `#B9C7B2` body; in light both are the same
    /// colour and only the weight separates them.
    private var leadInColor: Color {
        style == .green ? CypressColor.calloutGreenLeadIn : style.text
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .green:
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(CypressColor.calloutGreenFill)
        case .gradient:
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(CypressColor.calloutGradient)
        case .memorial:
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(CypressColor.memorialBannerFill)
        case .dashed:
            Color.clear
        }
    }
}

private struct DashedIfNeeded: ViewModifier {
    let style: Callout.Style
    let radius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if style == .dashed {
            content.cypressDashedBorder(CypressColor.borderDashed, radius: radius)
        } else {
            content
        }
    }
}

// MARK: - C15 · OptionalWell

/// C15 · `OptionalWell` — the dashed "you may skip this" placeholder on 05 and 09.
/// Copy seen: `Add photos · notes (optional)` (05), `Photo or note (optional)` (09).
struct OptionalWell: View {

    enum Size {
        /// 05 — `padding:12px 14px`.
        case standard
        /// 09 — `padding:13px 15px`.
        case large

        var paddingV: CGFloat {
            switch self {
            case .standard: return CypressSpacing.Component.wellPaddingV
            case .large: return CypressSpacing.Component.calloutPaddingVLarge
            }
        }

        var paddingH: CGFloat {
            switch self {
            case .standard: return CypressSpacing.Component.wellPaddingH
            case .large: return CypressSpacing.Component.calloutPaddingHLarge
            }
        }
    }

    let text: String
    var size: Size = .standard
    var action: (() -> Void)?

    init(_ text: String, size: Size = .standard, action: (() -> Void)? = nil) {
        self.text = text
        self.size = size
        self.action = action
    }

    var body: some View {
        if let action {
            Button(action: action) { well }
                .buttonStyle(.plain)
        } else {
            well
        }
    }

    private var well: some View {
        Text(text)
            .font(CypressFont.body135)
            .foregroundStyle(CypressColor.textFaint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, size.paddingV)
            .padding(.horizontal, size.paddingH)
            .cypressDashedBorder()
            .contentShape(Rectangle())
    }
}
