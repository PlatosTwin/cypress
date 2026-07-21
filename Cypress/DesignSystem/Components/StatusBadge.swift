//
//  StatusBadge.swift
//  Cypress — DesignSystem/Components
//
//  C13 · `StatusBadge` — SCREENS.md §2. `THRIVING` (01, 03, D1, D2), `PLANTED 2024` (14),
//  `REMOVED` (19).
//
//  The three drawn badges are the whole vocabulary. `from(status:vitality:plantedYear:)` maps the
//  domain onto them and returns `nil` when no badge is documented for that combination — the
//  component never invents a fourth badge (ARCHITECTURE §5.8: if a state is not in SCREENS.md,
//  stop and ask).
//

import SwiftUI

struct StatusBadge: View {

    enum Kind: Hashable {
        /// `THRIVING` — a vitality-5 tree.
        case thriving
        /// `PLANTED 2024` — a young city record with no observations yet.
        case planted(year: Int)
        /// `REMOVED` — the memorial state.
        case removed

        var text: String {
            switch self {
            case .thriving: return "Thriving"
            case let .planted(year): return "Planted \(year)"
            case .removed: return "Removed"
            }
        }

        var foreground: Color {
            switch self {
            case .thriving: return CypressColor.thrivingBadgeText
            case .planted: return CypressColor.plantedBadgeText
            case .removed: return CypressColor.removedBadgeText
            }
        }

        var background: Color {
            switch self {
            case .thriving: return CypressColor.thrivingBadgeFill
            case .planted: return CypressColor.plantedBadgeFill
            case .removed: return CypressColor.removedBadgeFill
            }
        }
    }

    /// `padding:2px 8px` on the 01 / D1 card, `3px 9px` everywhere else.
    enum Size {
        case compact
        case standard

        var paddingV: CGFloat {
            switch self {
            case .compact: return CypressSpacing.Component.statusBadgePaddingVCompact
            case .standard: return CypressSpacing.Component.statusBadgePaddingV
            }
        }

        var paddingH: CGFloat {
            switch self {
            case .compact: return CypressSpacing.Component.statusBadgePaddingHCompact
            case .standard: return CypressSpacing.Component.statusBadgePaddingH
            }
        }
    }

    let kind: Kind
    var size: Size = .standard

    init(_ kind: Kind, size: Size = .standard) {
        self.kind = kind
        self.size = size
    }

    var body: some View {
        Text(kind.text)
            .cypressBadge(color: kind.foreground)
            .padding(.vertical, size.paddingV)
            .padding(.horizontal, size.paddingH)
            .background {
                RoundedRectangle(cornerRadius: CypressRadius.badge, style: .continuous)
                    .fill(kind.background)
            }
            .fixedSize()
    }

    /// The domain → badge mapping. `nil` means "SCREENS.md documents no badge for this tree",
    /// which is a legitimate answer: most trees carry none.
    static func kind(
        status: TreeStatus,
        vitality: Vitality?,
        plantedYear: Int?
    ) -> Kind? {
        if status.isMemorial { return .removed }
        if vitality == .thriving { return .thriving }
        if vitality == nil, let plantedYear { return .planted(year: plantedYear) }
        return nil
    }
}
