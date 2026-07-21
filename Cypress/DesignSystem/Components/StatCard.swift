//
//  StatCard.swift
//  Cypress — DesignSystem/Components
//
//  C11 · `StatCard` — SCREENS.md §2. The 2-up stat grid on 03, 14, 19 and D2, and the large
//  count cards on 07.
//
//  A card whose value is a measurement takes a `Quantity` and renders it through `MeasuredValue`,
//  so the method badge rides along automatically (D7). The plain-string initializer exists for the
//  values that are not measurements — `SF #114-88`, `Sidewalk cut`, `1898`.
//

import SwiftUI

struct StatCard: View {

    /// `padding:9px 12px`, value mono 14.5 — or 07's `padding:10px 13px`, value mono 17.
    enum Size {
        case standard
        case large

        var paddingV: CGFloat {
            switch self {
            case .standard: return CypressSpacing.Component.statPaddingV
            case .large: return CypressSpacing.Component.statPaddingVLarge
            }
        }

        var paddingH: CGFloat {
            switch self {
            case .standard: return CypressSpacing.Component.statPaddingH
            case .large: return CypressSpacing.Component.statPaddingHLarge
            }
        }

        var valueFont: Font {
            switch self {
            case .standard: return CypressFont.monoStat
            case .large: return CypressFont.monoStatBig
            }
        }
    }

    /// What sits under the label.
    enum Value {
        /// A measurement. Always rendered with its method badge (D7).
        case quantity(Quantity)
        /// A city-record measurement — a range or a single number the city published, never
        /// measured by a person. Carries the `city record` badge.
        case cityRecord(String)
        /// A value that is not a measurement: `SF #114-88`, `1898`, `1,204`. Mono, no badge.
        case text(String)
        /// 14's `Watch for` row — **13px/700 sans, not mono**, per §2.
        case prose(String)
    }

    let label: String
    let value: Value
    var size: Size = .standard

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).cypressMicroLabel10()
            valueView
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, size.paddingV)
        .padding(.horizontal, size.paddingH)
        .background {
            RoundedRectangle(cornerRadius: CypressRadius.control, style: .continuous)
                .fill(CypressColor.surfaceCard)
        }
        .cypressBorder(CypressColor.borderCool, radius: CypressRadius.control)
    }

    @ViewBuilder
    private var valueView: some View {
        switch value {
        case let .quantity(quantity):
            MeasuredValue(quantity: quantity, font: size.valueFont)
        case let .cityRecord(text):
            HStack(spacing: 6) {
                Text(text)
                    .font(size.valueFont)
                    .foregroundStyle(CypressColor.textInk)
                MethodBadge(.cityRecord)
            }
        case let .text(text):
            Text(text)
                .font(size.valueFont)
                .foregroundStyle(CypressColor.textInk)
        case let .prose(text):
            Text(text)
                .font(CypressFont.body13Bold)
                .foregroundStyle(CypressColor.textInk)
                .padding(.top, 1)
        }
    }
}

/// C11's `grid-template-columns:1fr 1fr; gap:8px`.
struct StatGrid<Content: View>: View {
    @ViewBuilder var content: Content

    private let columns = [
        GridItem(.flexible(), spacing: CypressSpacing.Component.statGridGap),
        GridItem(.flexible(), spacing: CypressSpacing.Component.statGridGap),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: CypressSpacing.Component.statGridGap) {
            content
        }
    }
}
