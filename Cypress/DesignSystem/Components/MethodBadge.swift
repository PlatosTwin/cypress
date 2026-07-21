//
//  MethodBadge.swift
//  Cypress — DesignSystem/Components
//
//  C12 · `MethodBadge` — SCREENS.md §2, and decision D7.
//
//  ── Why this takes a `Quantity` ───────────────────────────────────────────────────────────
//  D7 / ARCHITECTURE §5.2: "A quantity without a `method` does not compile." The badge therefore
//  takes `Core.Quantity`, never a string: there is no initializer through which a caller can pass
//  the number `64` and the word `taped` separately, and `MeasuredValue` renders the two together
//  so a bare number cannot reach the screen at all.
//
//  The one non-`Quantity` case is `city record` (14) — a value that came from the city import and
//  was never measured by anyone. It is a separate, explicit case rather than a third method.
//

import SwiftUI

struct MethodBadge: View {

    /// Where the number came from.
    enum Source {
        /// A measured or estimated value. Style and label both derive from `quantity.method`.
        case quantity(Quantity)
        /// `city record` (14) — the DataSF row, not an observation. Never a `Quantity`.
        case cityRecord
    }

    /// `10.5px/600, padding:1px 5px` inline (03, 14) — or the growth-log form on 11,
    /// `11px/600, padding:1.5px 7px`, whose estimate label reads `estimated` rather than `est.`
    enum Size {
        case inline
        case growthLog

        var font: Font {
            switch self {
            case .inline: return CypressFont.body105SemiBold
            case .growthLog: return CypressFont.body11SemiBold
            }
        }

        var paddingV: CGFloat {
            switch self {
            case .inline: return CypressSpacing.Component.methodBadgePaddingV
            case .growthLog: return CypressSpacing.Component.methodBadgePaddingVLog
            }
        }

        var paddingH: CGFloat {
            switch self {
            case .inline: return CypressSpacing.Component.methodBadgePaddingH
            case .growthLog: return CypressSpacing.Component.methodBadgePaddingHLog
            }
        }
    }

    let source: Source
    var size: Size = .inline

    init(_ source: Source, size: Size = .inline) {
        self.source = source
        self.size = size
    }

    /// The common call: badge a quantity.
    init(_ quantity: Quantity, size: Size = .inline) {
        self.init(.quantity(quantity), size: size)
    }

    var body: some View {
        Text(label)
            .font(size.font)
            .foregroundStyle(foreground)
            .padding(.vertical, size.paddingV)
            .padding(.horizontal, size.paddingH)
            .background {
                RoundedRectangle(cornerRadius: CypressRadius.methodBadge, style: .continuous)
                    .fill(background)
            }
            .fixedSize()
            .accessibilityLabel(accessibilityLabel)
    }

    // MARK: Copy

    /// `taped` / `est.` (inline) · `taped` / `estimated` (growth log) · `city record`.
    ///
    /// `caliper` and `laser` are in the `MeasurementMethod` vocabulary but not in SCREENS.md's
    /// badge table. They are measured methods, so they take the `taped` styling and carry their own
    /// word — the badge never claims a caliper reading was taped. **Judgment call:** the copy is
    /// not in the spec.
    var label: String {
        switch source {
        case .cityRecord:
            return "city record"
        case let .quantity(quantity):
            switch quantity.method {
            case .tape: return "taped"
            case .caliper: return "caliper"
            case .laser: return "laser"
            case .estimate: return size == .growthLog ? "estimated" : "est."
            }
        }
    }

    private var series: MeasurementSeries? {
        switch source {
        case .cityRecord: return nil
        case let .quantity(quantity): return quantity.series
        }
    }

    private var foreground: Color {
        switch series {
        case .measured: return CypressColor.tapedBadgeText
        case .estimated: return CypressColor.estimatedBadgeText
        case nil: return CypressColor.cityRecordBadgeText
        }
    }

    private var background: Color {
        switch series {
        case .measured: return CypressColor.tapedBadgeFill
        case .estimated: return CypressColor.estimatedBadgeFill
        case nil: return CypressColor.cityRecordBadgeFill
        }
    }

    private var accessibilityLabel: String {
        switch source {
        case .cityRecord: return "from the city record"
        case let .quantity(quantity):
            switch quantity.method {
            case .tape: return "measured with a tape"
            case .caliper: return "measured with a caliper"
            case .laser: return "measured with a laser"
            case .estimate: return "estimated"
            }
        }
    }
}

// MARK: - The number and its method, together

/// A quantity rendered the only way the product allows: the value in mono, its `MethodBadge`
/// beside it (D7). There is no view in the design system that renders a `Quantity`'s number alone.
struct MeasuredValue: View {
    let quantity: Quantity
    var size: MethodBadge.Size = .inline
    var font: Font = CypressFont.monoStat
    var color: Color = CypressColor.textInk

    var body: some View {
        HStack(spacing: 6) {
            Text(Self.formatted(quantity))
                .font(font)
                .foregroundStyle(color)
            MethodBadge(quantity, size: size)
        }
        .accessibilityElement(children: .combine)
    }

    /// `64 cm` — the value as entered, in the unit it was entered in (never silently converted,
    /// per `Quantity`).
    static func formatted(_ quantity: Quantity) -> String {
        "\(number(quantity.value)) \(quantity.unitEntered.rawValue)"
    }

    /// Whole numbers print bare; anything else keeps one decimal.
    static func number(_ value: Double) -> String {
        value == value.rounded()
            ? String(Int(value.rounded()))
            : String(format: "%.1f", value)
    }
}
