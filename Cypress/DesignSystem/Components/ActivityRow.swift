//
//  ActivityRow.swift
//  Cypress — DesignSystem/Components
//
//  C9 · `ActivityRow` — SCREENS.md §2. The tree's timeline rows on 03, 19 and D2.
//
//  The row is ~60pt tall, comfortably above the tap minimum; the 38pt leading thumb is *inside*
//  the row's target, so it needs no separate expansion.
//

import SwiftUI

struct ActivityRow: View {

    /// The leading-thumb kinds §2 documents, and the community tree mark.
    enum Leading {
        /// A photo placeholder — any C22 recipe.
        case photo(CypressGradientRecipe)
        /// Care — `#E2EFE2` tile with a 12pt Canopy leaf glyph (D2: `#1F3A2C` + `#8EC3A5`).
        case care
        /// The city-sync row on 19 — `#EDEEE6` with mono 10pt `SYNC` in `#5C6555`.
        case sync
        /// 19's check-in row uses a vitality reference swatch as its thumb.
        case vitality(Vitality)
        /// A community tree's history row: the map's community pin, drawn small on its pale fill
        /// (`CommunityTreeTile`; the app owner's decision of 2026-11-15).
        case communityTree
    }

    let leading: Leading
    /// The bold lead-in, e.g. `Visit`.
    let label: String
    /// Everything after it, verbatim including its separator: ` · “Fog dripping off the crown”`.
    let detail: String
    /// Trailing mono timestamp, e.g. `Oct 12`.
    let timestamp: String
    var action: (() -> Void)?

    var body: some View {
        if let action {
            Button(action: action) { row }
                .buttonStyle(.plain)
        } else {
            row
        }
    }

    private var row: some View {
        HStack(spacing: CypressSpacing.Component.activitySpacing) {
            thumb
            cypressLeadInText(
                label,
                detail,
                leadInFont: CypressFont.body135Bold,
                restFont: CypressFont.body135,
                leadInColor: CypressColor.textInk,
                restColor: CypressColor.textBody
            )
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: CypressSpacing.gapDense)

            Text(timestamp)
                .font(CypressFont.mono11)
                .foregroundStyle(CypressColor.textFaint)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.vertical, CypressSpacing.Component.activityPaddingV)
        .padding(.horizontal, CypressSpacing.Component.activityPaddingH)
        .background {
            RoundedRectangle(cornerRadius: CypressRadius.cardSm, style: .continuous)
                .fill(CypressColor.surfaceCard)
        }
        .cypressBorder(CypressColor.borderCool, radius: CypressRadius.cardSm)
        .cypressCardShadow()
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var thumb: some View {
        let side = CypressSpacing.Component.activityThumb
        Group {
            switch leading {
            case let .photo(recipe):
                CypressGradientField(recipe)
            case .care:
                CypressColor.thrivingBadgeFill
                    .overlay {
                        LeafGlyph(size: CypressSpacing.Component.activityLeaf, tint: CypressColor.selectionFill)
                    }
            case .sync:
                CypressColor.memorialBannerFill
                    .overlay {
                        Text("SYNC")
                            .font(CypressFont.mono10SemiBold)
                            .foregroundStyle(CypressColor.removedBadgeText)
                    }
            case let .vitality(vitality):
                (CypressColor.Vitality(rawValue: vitality.rawValue) ?? .fair).gradient
            case .communityTree:
                CommunityTreeTile()
            }
        }
        .frame(width: side, height: side)
        .cypressCornerRadius(CypressRadius.thumbSmAlt)
        .accessibilityHidden(true)
    }
}
