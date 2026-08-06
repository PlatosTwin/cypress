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
    ///
    /// **A vacant site is not drawn that way, because a vacant site is not a tree.** ROADMAP §1
    /// settles what it is — "a distinct planting-site state, *not* a variant of the tree profile" —
    /// and R7/E119/E123 gave that state a drawn vocabulary everywhere else it appears: the map pin,
    /// 14's empty photo well, the site screen, `LocationPrompt`. The almanac tile was the one member
    /// still wearing the tree's clothes, a radial blob at 45%/42% differing from the five living
    /// tiles only in color. `emptyWell` below is that vocabulary at 34 pt, and nothing else.
    private var tile: some View {
        Group {
            if accent == .vacantSite {
                emptyWell
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

    /// The empty planting basin, drawn exactly as 14's empty photo well, the site screen and
    /// `LocationPrompt` draw it: `surfaceEmptyThumb` under a dashed `borderDashedStrong` edge. Off
    /// the map a dashed frame is what this family already speaks — E119 chose a *solid* ring for the
    /// pin only because on the map dashes mean the community layer (DECISIONS §3.16), and screen 12
    /// has no community layer. No new token and no new hue.
    ///
    /// It also closes a rendering the swap in E122 did not reach: the radial drawing this replaces
    /// read at 1.48:1 on a dark card, which is to say it did not read at all. The dashed frame is
    /// the same 1.48:1 against the tile's own ground and is legible anyway, because a dashed edge on
    /// a plane is a *shape* rather than a wash — the same reason no C10 tile is asked to clear 3:1.
    private var emptyWell: some View {
        RoundedRectangle(cornerRadius: CypressRadius.thumbSmAlt, style: .continuous)
            .fill(CypressColor.surfaceEmptyThumb)
            .cypressDashedBorder(
                CypressColor.borderDashedStrong,
                radius: CypressRadius.thumbSmAlt,
                width: CypressSpacing.Component.outlineWidth
            )
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
