//
//  IconTextRow.swift
//  Cypress — DesignSystem/Components
//
//  C10 · `IconTextRow` — SCREENS.md §2. 12 "This season" ×3 and 13 "Moments" ×3.
//  Card, **no shadow**, `align-items:flex-start`, 34pt accent tile.
//

import SwiftUI

struct IconTextRow: View {
    let accent: CypressColor.TileAccent
    let title: String
    let subtitle: String
    var action: (() -> Void)?

    var body: some View {
        if let action {
            Button(action: action) { row }.buttonStyle(.plain)
        } else {
            row
        }
    }

    private var row: some View {
        HStack(alignment: .top, spacing: CypressSpacing.Component.iconRowSpacing) {
            tile
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(CypressFont.body14)
                    .foregroundStyle(CypressColor.textInk)
                Text(subtitle)
                    .font(CypressFont.body125)
                    .foregroundStyle(CypressColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, CypressSpacing.Component.iconRowPaddingV)
        .padding(.horizontal, CypressSpacing.Component.iconRowPaddingH)
        .background {
            RoundedRectangle(cornerRadius: CypressRadius.cardSm, style: .continuous)
                .fill(CypressColor.surfaceCard)
        }
        .cypressBorder(CypressColor.borderCool, radius: CypressRadius.cardSm)
        .contentShape(Rectangle())
    }

    /// `radial-gradient(circle at 45% 42%, <accent> 0%, transparent 55%)` over a pale base.
    private var tile: some View {
        CypressGradientField(
            CypressGradientRecipe(
                base: LinearGradient(
                    colors: [accent.base, accent.base],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                radials: [CypressRadialStop(0.45, 0.42, accent.accent, 0.55)]
            )
        )
        .frame(
            width: CypressSpacing.Component.iconRowTile,
            height: CypressSpacing.Component.iconRowTile
        )
        .cypressCornerRadius(CypressRadius.thumbSmAlt)
        .accessibilityHidden(true)
    }
}
