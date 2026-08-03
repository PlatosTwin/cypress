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
        /// `DEAD` — a tree a lead has confirmed dead (ERRATA E170).
        ///
        /// **Not a second way of saying `removed`.** A `dead_reported` tree is still standing over a
        /// pavement: it keeps its profile, its REPORT and CARE buttons and its pin
        /// (`TreeStatus.deadReported.acceptsNewContributions`). The badge exists because that profile
        /// otherwise says nothing at all about a status somebody confirmed — it looked exactly like a
        /// live tree with no check-ins.
        case deadReported

        var text: String {
            switch self {
            case .thriving: return "Thriving"
            case let .planted(year): return "Planted \(year)"
            case .removed: return "Removed"
            case .deadReported: return "Dead"
            }
        }

        var foreground: Color {
            switch self {
            case .thriving: return CypressColor.thrivingBadgeText
            case .planted: return CypressColor.plantedBadgeText
            // The removed pair, deliberately: the catalog has no fifth badge color, and inventing
            // one is a design decision this errata has no standing to make (the argument E107 made
            // about the vacant-site pin, which waited for RULINGS R7). Gray says "not a living tree
            // here", which is true of both — and the two badges never say the same word.
            case .removed, .deadReported: return CypressColor.removedBadgeText
            }
        }

        var background: Color {
            switch self {
            case .thriving: return CypressColor.thrivingBadgeFill
            case .planted: return CypressColor.plantedBadgeFill
            case .removed, .deadReported: return CypressColor.removedBadgeFill
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
    ///
    /// Status outranks vitality in both directions, and `deadReported` is why that ordering had to be
    /// written down rather than left to `isMemorial` (ERRATA E170). A tree can carry a confirmed-dead
    /// status *and* a stale `.thriving` rating from a check-in made before it died — the observation
    /// is not wrong, it is old — and the badge must be the status.
    static func kind(
        status: TreeStatus,
        vitality: Vitality?,
        plantedYear: Int?
    ) -> Kind? {
        if status.isMemorial { return .removed }
        if status == .deadReported { return .deadReported }
        if vitality == .thriving { return .thriving }
        if vitality == nil, let plantedYear { return .planted(year: plantedYear) }
        return nil
    }
}
