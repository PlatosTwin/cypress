//
//  QuadActionRow.swift
//  Cypress — DesignSystem/Components
//
//  C8 · `QuadActionRow` — SCREENS.md §2. The quiet row under the profile CTA (03, D2).
//
//  **NOT SPECIFIED** (§2 C8, §5 gap 3): icons for the four actions. The spec shows text only, and
//  no icon is invented here.
//
//  Tap targets: a cell is ~31pt tall as drawn (`padding:9px 2px` + a 12pt label). The cell keeps
//  that size; `.cypressHitArea()` gives it 44pt.
//

import SwiftUI

struct QuadActionRow: View {

    /// The four actions, labels verbatim from screen 03.
    enum Action: String, CaseIterable, Identifiable {
        case favorite
        case care
        case share
        case report

        var id: String { rawValue }

        var label: String {
            switch self {
            case .favorite: return "Favorite"
            case .care: return "Care"
            case .share: return "Share"
            case .report: return "Report"
            }
        }
    }

    var actions: [Action] = Action.allCases
    var onTap: (Action) -> Void

    var body: some View {
        HStack(spacing: CypressSpacing.Component.quadSpacing) {
            ForEach(actions) { action in
                Button {
                    onTap(action)
                } label: {
                    Text(action.label)
                        .font(CypressFont.body12SemiBold)
                        .foregroundStyle(CypressColor.textBody)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, CypressSpacing.Component.quadCellPaddingV)
                        .padding(.horizontal, CypressSpacing.Component.quadCellPaddingH)
                        .background {
                            RoundedRectangle(cornerRadius: CypressRadius.control, style: .continuous)
                                .fill(CypressColor.surfaceCard)
                        }
                        .cypressBorder(CypressColor.borderCool, radius: CypressRadius.control)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .cypressHitArea()
            }
        }
        .padding(.vertical, CypressSpacing.Component.quadRowPaddingV)
        .padding(.horizontal, CypressSpacing.gutter)
    }
}
