//
//  AvatarStack.swift
//  Cypress — DesignSystem/Components
//
//  C26 · `AvatarStack` — SCREENS.md §2. The regulars row on 03: `N`, `M`, `J`, `+3`.
//
//  ── A product rule this component must not break ──────────────────────────────────────────
//  D1 / ARCHITECTURE §5.1: no public counts of user *actions*. "Six people know this tree" is a
//  count of people, not of contributions, and it is the copy the spec ships — so the overflow
//  bubble carries `+3` and nothing else. This component takes initials, never counts of visits,
//  photos or care events.
//

import SwiftUI

struct AvatarStack: View {
    /// Initials in drawn order. Each takes the next fill from `CypressColor.avatarFills`.
    let initials: [String]
    /// The trailing overflow bubble, e.g. `+3`. Optional.
    var overflow: String?

    var body: some View {
        HStack(spacing: -CypressSpacing.Component.avatarOverlap) {
            ForEach(Array(initials.enumerated()), id: \.offset) { index, initial in
                bubble(initial, fill: fill(at: index))
            }
            if let overflow {
                bubble(overflow, fill: fill(at: initials.count))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Regulars")
    }

    private func fill(at index: Int) -> Color {
        let fills = CypressColor.avatarFills
        return fills[index % fills.count]
    }

    private func bubble(_ text: String, fill: Color) -> some View {
        Circle()
            .fill(fill)
            .overlay {
                Circle().strokeBorder(
                    CypressColor.avatarRing,
                    lineWidth: CypressSpacing.Component.avatarRingWidth
                )
            }
            .overlay {
                Text(text)
                    .font(CypressFont.body10ExtraBold)
                    .foregroundStyle(CypressColor.textOnDark)
            }
            .frame(
                width: CypressSpacing.Component.avatar,
                height: CypressSpacing.Component.avatar
            )
    }
}
