//
//  SegmentedControl.swift
//  Cypress — DesignSystem/Components
//
//  C5 · `SegmentedControl` — SCREENS.md §2. Used by 05 (Status, Foliage), 16 (what are you
//  measuring, method) and D3 (Status).
//
//  Tap targets: a segment is ~33pt tall as drawn (`padding:10px 2px` + 13pt label). The drawn
//  control keeps that height and each segment gets a ≥44pt hit area via `.cypressHitArea()`, so
//  the enlarged targets stack vertically outside the border rather than inflating the control.
//

import SwiftUI

struct SegmentedControl<Option: Hashable>: View {

    /// `padding:10px 2px`, 13px (05) — or `11px 2px`, 14px (16).
    enum Size {
        case standard
        case large

        var paddingV: CGFloat {
            switch self {
            case .standard: return CypressSpacing.Component.segmentPaddingV
            case .large: return CypressSpacing.Component.segmentPaddingVLarge
            }
        }

        func font(selected: Bool, forcedDarkWeight: Bool) -> Font {
            switch (self, selected, forcedDarkWeight) {
            case (.standard, false, _): return CypressFont.body13
            case (.standard, true, false): return CypressFont.body13Bold
            case (.standard, true, true): return CypressFont.body13ExtraBold
            case (.large, false, _): return CypressFont.body14Regular
            case (.large, true, false): return CypressFont.body14
            case (.large, true, true): return CypressFont.body14ExtraBold
            }
        }
    }

    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String
    var size: Size = .standard

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                segment(option, isFirst: index == 0)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: CypressRadius.control, style: .continuous)
                .fill(CypressColor.surfaceCard)
        }
        .cypressCornerRadius(CypressRadius.control)
        .cypressBorder(CypressColor.borderCool, radius: CypressRadius.control)
    }

    private func segment(_ option: Option, isFirst: Bool) -> some View {
        let isSelected = option == selection
        return Button {
            selection = option
        } label: {
            Text(label(option))
                .font(size.font(selected: isSelected, forcedDarkWeight: colorScheme == .dark))
                .foregroundStyle(
                    isSelected ? CypressColor.onSelectionFill : CypressColor.textBody
                )
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, size.paddingV)
                .padding(.horizontal, CypressSpacing.Component.segmentPaddingH)
                .background(isSelected ? CypressColor.selectionFill : Color.clear)
                .overlay(alignment: .leading) {
                    // `border-left:1px solid #E3E8D9` on every segment except the first.
                    if !isFirst {
                        Rectangle()
                            .fill(CypressColor.borderCool)
                            .frame(width: CypressSpacing.Component.hairline)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cypressHitArea()
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Domain-typed conveniences

extension SegmentedControl where Option == TreeStatus {
    /// 05 / D3 `Status`. Copy is verbatim from screen 05: `Alive · Declining · Appears dead ·
    /// Removed?`, mapped onto `TreeStatus` so the control cannot emit a status the model lacks.
    static func status(selection: Binding<TreeStatus>) -> SegmentedControl<TreeStatus> {
        SegmentedControl(
            options: [.alive, .declining, .deadReported, .removed],
            selection: selection,
            label: { status in
                switch status {
                case .alive: return "Alive"
                case .declining: return "Declining"
                case .deadReported: return "Appears dead"
                case .removed: return "Removed?"
                case .vacantSite: return "Vacant site"
                }
            }
        )
    }
}

extension SegmentedControl where Option == MeasurementMethod {
    /// 16 `Method · required`. `Tape · Caliper · Estimate`, verbatim, over the `MeasurementMethod`
    /// vocabulary — a number cannot leave this sheet without one (D7).
    static func method(selection: Binding<MeasurementMethod>) -> SegmentedControl<MeasurementMethod> {
        SegmentedControl(
            options: [.tape, .caliper, .estimate],
            selection: selection,
            label: { method in
                switch method {
                case .tape: return "Tape"
                case .caliper: return "Caliper"
                case .estimate: return "Estimate"
                case .laser: return "Laser"
                }
            },
            size: .large
        )
    }
}
