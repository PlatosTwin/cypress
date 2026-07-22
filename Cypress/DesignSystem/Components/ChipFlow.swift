//
//  ChipFlow.swift
//  Cypress — DesignSystem/Components
//
//  The `flex-wrap` that SCREENS.md declares on every chip row it draws — 06 §2–3 (`gap:7px`) and
//  09 §4 (`gap:9px`).
//
//  SwiftUI has no wrapping stack, and the alternative — pre-splitting the chips into fixed rows —
//  would bake in a line break that the spec expresses as a flow property and that Dynamic Type
//  invalidates at AX1 (ARCHITECTURE §6). One gap value, applied on both axes, as CSS `gap` does.
//
//  It lives here rather than in a feature folder because two screens draw it and ARCHITECTURE §2
//  says a feature folder owns its own views: the second screen to need a wrapping chip row must not
//  reach into the first one's folder for it.
//

import SwiftUI

struct CypressChipFlow: Layout {

    let spacing: CGFloat

    init(spacing: CGFloat) {
        self.spacing = spacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let rows = rows(subviews: subviews, maxWidth: proposal.width ?? .infinity)
        let height = rows.reduce(0) { $0 + $1.height }
            + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        var y = bounds.minY
        for row in rows(subviews: subviews, maxWidth: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let candidate = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if !current.indices.isEmpty, candidate > maxWidth {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
