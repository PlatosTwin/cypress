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
        // ══════════════════════════════════════════════════════════════════════════════════════
        // A stack with nothing in it is not an element.
        //
        // This used to be an unconditional `children: .ignore` plus the word "Regulars", which
        // meant that on a stack with no bubbles — the shipping case, because E71 records that the
        // API carries caretakers as bare UUIDs and there are no initials to draw — VoiceOver
        // stopped on an empty box and said "Regulars". A drawn-nothing that speaks is worse than
        // either: sighted users see no row, listeners are told there is one.
        //
        // The same rule as ARCHITECTURE §5.6 for below-threshold surfaces, applied one level down:
        // if it renders nothing, it announces nothing.
        // ══════════════════════════════════════════════════════════════════════════════════════
        .accessibilityElement(children: .ignore)
        .accessibilityHidden(isEmpty)
        .accessibilityLabel(accessibilityLabel)
    }

    private var isEmpty: Bool { initials.isEmpty && overflow == nil }

    /// What the bubbles are, said as the thing they stand for. `+3` alone is a glyph; "3 more
    /// regulars" is what a sighted reader takes from it.
    var accessibilityLabel: String {
        guard !isEmpty else { return "" }
        var parts: [String] = []
        if !initials.isEmpty { parts.append(initials.joined(separator: ", ")) }
        if let overflow {
            let more = overflow.hasPrefix("+") ? String(overflow.dropFirst()) : overflow
            parts.append(initials.isEmpty ? "\(more) regulars" : "\(more) more")
        }
        return "Regulars: " + parts.joined(separator: ", ")
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
