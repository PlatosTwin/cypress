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
    /// The tree this row is about, when it should draw that tree's own photograph rather than the
    /// accent tile (#176). `nil` — every call site that does not pass one — draws exactly the
    /// accent gradient this component has always drawn; a row with a real tree's id but no live
    /// photograph draws the same gradient too, because `PhotoImage` falls back to its placeholder.
    /// The rule for which photograph a row with several may choose is `PhotoHero`, applied once in
    /// `ContributionStore.heroPhotoIDs` rather than here — this component only draws the id it is
    /// given.
    var photoID: UUID?
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
                // **Absent, not empty.** A row whose second line has nothing true to say hands over
                // "" — a journal entry with no note, a grove row whose record could not be proved
                // (ERRATA E38) — and `Text("")` is not nothing: it reserves a line's height and
                // leaves the title floating above a gap. The rule this app already keeps for clauses
                // (a journal row's missing note, screen 11's pills) is that an absent fact is left
                // out rather than filled in; this is the same rule one level up.
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(CypressFont.body125)
                        .foregroundStyle(CypressColor.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
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

    /// `radial-gradient(circle at 45% 42%, <accent> 0%, transparent 55%)` over a pale base — drawn
    /// on its own when there is no photograph, and reused as `PhotoImage`'s placeholder when there
    /// is one so a tree whose bytes have not loaded yet, or have none, still draws this row's own
    /// accent rather than a photograph-shaped hole.
    private var tile: some View {
        Group {
            // ⚠️ CAMERA RIG (design/14-proposals) — E119/E122's open question, drawn so it can be
            // photographed. Neither arm adds a hue: both are `surfaceEmptyThumb` under
            // `borderDashedStrong`, the two tokens the vacant-site family already owns.
            if accent == .vacantSite, DesignProposalVariant.vacantTile != .shipped {
                vacantSiteTile
            } else if let photoID {
                PhotoImage(photoID: photoID, placeholder: Self.placeholderRecipe(accent))
            } else {
                CypressGradientField(Self.placeholderRecipe(accent))
            }
        }
        .frame(
            width: CypressSpacing.Component.iconRowTile,
            height: CypressSpacing.Component.iconRowTile
        )
        .cypressCornerRadius(CypressRadius.thumbSmAlt)
        .accessibilityHidden(true)
    }

    /// 12a · the empty photo well at 34 pt — `surfaceEmptyThumb` under a dashed
    /// `borderDashedStrong` edge, which is what 14's well, the site screen and `LocationPrompt`
    /// already draw. 12b · the map pin's hollow ring (E119), centered on the same ground.
    @ViewBuilder
    private var vacantSiteTile: some View {
        switch DesignProposalVariant.vacantTile {
        case .dashedWell:
            RoundedRectangle(cornerRadius: CypressRadius.thumbSmAlt, style: .continuous)
                .fill(CypressColor.surfaceEmptyThumb)
                .overlay {
                    RoundedRectangle(cornerRadius: CypressRadius.thumbSmAlt, style: .continuous)
                        .strokeBorder(
                            CypressColor.borderDashedStrong,
                            style: StrokeStyle(
                                lineWidth: CypressSpacing.Component.hairlineStrong,
                                dash: [3, 2.5]
                            )
                        )
                }
        case .hollowRing:
            RoundedRectangle(cornerRadius: CypressRadius.thumbSmAlt, style: .continuous)
                .fill(CypressColor.surfaceEmptyThumb)
                .overlay {
                    Circle()
                        .strokeBorder(
                            CypressColor.borderDashedStrong,
                            lineWidth: CypressSpacing.Component.outlineWidth
                        )
                        .padding(CypressSpacing.Component.hairlineStrong * 3)
                }
        case .shipped:
            EmptyView()
        }
    }

    private static func placeholderRecipe(_ accent: CypressColor.TileAccent) -> CypressGradientRecipe {
        CypressGradientRecipe(
            base: LinearGradient(
                colors: [accent.base, accent.base],
                startPoint: .top,
                endPoint: .bottom
            ),
            radials: [CypressRadialStop(0.45, 0.42, accent.accent, 0.55)]
        )
    }
}
