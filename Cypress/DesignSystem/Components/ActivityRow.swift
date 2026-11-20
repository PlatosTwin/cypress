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

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Whether the timestamp moves under the row instead of sitting beside the label.
    ///
    /// §2 draws `[thumb] [label] [timestamp]` in one line. At the accessibility sizes the timestamp
    /// holds its one mono line at its full width, and the label was left a column narrower than
    /// one of its own words: "Specie / s", "drippi / ng", "watere / d". So above the accessibility
    /// threshold the timestamp goes under the row it dates, as screen 17's outbox row moves its
    /// state word. It is still the last thing in reading order. A value, so a test can read it.
    static func stacksTimestamp(isAccessibilitySize: Bool) -> Bool {
        isAccessibilitySize
    }

    private var row: some View {
        Group {
            if Self.stacksTimestamp(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize) {
                VStack(alignment: .leading, spacing: CypressSpacing.gapDense) {
                    HStack(spacing: CypressSpacing.Component.activitySpacing) {
                        thumb
                        labelText
                        Spacer(minLength: 0)
                    }
                    timestampText
                }
            } else {
                HStack(spacing: CypressSpacing.Component.activitySpacing) {
                    thumb
                    labelText

                    Spacer(minLength: CypressSpacing.gapDense)

                    timestampText
                }
            }
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

    private var labelText: some View {
        cypressLeadInText(
            label,
            detail,
            leadInFont: CypressFont.body135Bold,
            restFont: CypressFont.body135,
            leadInColor: CypressColor.textInk,
            restColor: CypressColor.textBody
        )
        .fixedSize(horizontal: false, vertical: true)
    }

    private var timestampText: some View {
        Text(timestamp)
            .font(CypressFont.mono11)
            .foregroundStyle(CypressColor.textFaint)
            .lineLimit(1)
            .fixedSize()
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
                        // The word is a mark inside a tile §2 sizes at 38 pt, like the leaf
                        // beside it, and the tile does not grow with the text. Without a line
                        // limit and a scale floor it scaled past the tile at the accessibility
                        // sizes and drew as "…". This is the outbox tile's treatment of its
                        // reading (screen 17), with a floor low enough for four mono letters at
                        // AX5: 0.4 still drew "SY…" there. At the drawn size the word fits and
                        // nothing scales.
                        Text("SYNC")
                            .font(CypressFont.mono10SemiBold)
                            .foregroundStyle(CypressColor.removedBadgeText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.3)
                            .padding(.horizontal, CypressSpacing.Component.hairlineStrong)
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
