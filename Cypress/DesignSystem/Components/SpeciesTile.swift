//
//  SpeciesTile.swift
//  Cypress — DesignSystem/Components
//
//  C29 · `SpeciesTile` — SCREENS.md §2. The 3-up grid on 08, "Species you know".
//
//  A tile is a square in a 3-column grid — on any iPhone that is well over 44pt, so the whole tile
//  is the target and no expansion is needed.
//

import SwiftUI

struct SpeciesTile: View {

    enum Content {
        /// A species the user can recognize. Art comes from `CypressGradient.SpeciesTileArt`.
        case known(CypressGradient.SpeciesTileArt)
        /// A species not yet learned — `#E9ECDE` with a centered `?`.
        case locked
    }

    let content: Content
    /// The name written on the tile, when it is not the artwork's own.
    ///
    /// SCREENS.md 08 §5 draws seven tiles whose label and whose gradient are the same species, so
    /// `SpeciesTileArt.label` was doing both jobs. The seed carries 569 species and §2 authors art
    /// for seven, so on any real grove the two come apart: the art is chosen by genus or by a stable
    /// hash (`SpeciesTileArtwork`) while the name has to be the species' own. Left unset the tile
    /// printed the *artwork's* name — a Maidenhair Tree drawn with the Ginkgo gradient was labeled
    /// `Ginkgo`, and a species with no genus match was labeled with whatever the hash landed on.
    /// That is fabricated botany on screen (BUILD-PLAN §15). See ERRATA E51.
    var label: String?
    var action: (() -> Void)?

    var body: some View {
        if let action {
            Button(action: action) { tile }
                .buttonStyle(.plain)
        } else {
            tile
        }
    }

    private var tile: some View {
        background
            .aspectRatio(1, contentMode: .fit)
            .overlay(alignment: .bottomLeading) { labelOverlay }
            .cypressCornerRadius(CypressRadius.thumbMd)
            .contentShape(Rectangle())
            .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var background: some View {
        switch content {
        case let .known(art):
            CypressGradientField(art.recipe)
        case .locked:
            CypressColor.speciesTileLockedFill
        }
    }

    @ViewBuilder
    private var labelOverlay: some View {
        switch content {
        case let .known(art):
            Text(label ?? art.label)
                .font(CypressFont.body11Bold)
                .foregroundStyle(CypressColor.textOnDark)
                .lineSpacing(0)
                .cypressShadow(CypressShadow.speciesTileLabel)
                .padding(CypressSpacing.Component.speciesTilePadding)
        case .locked:
            Text("?")
                .font(CypressFont.body20SemiBold)
                .foregroundStyle(CypressColor.speciesTileLockedGlyph)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var accessibilityLabel: String {
        switch content {
        case let .known(art): return label ?? art.label
        case .locked: return "Species not yet learned"
        }
    }
}

/// 08's `grid-template-columns:repeat(3,1fr); gap:9px`.
struct SpeciesGrid<Content: View>: View {
    @ViewBuilder var content: Content

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: CypressSpacing.Component.speciesTileGap),
        count: 3
    )

    var body: some View {
        LazyVGrid(columns: columns, spacing: CypressSpacing.Component.speciesTileGap) {
            content
        }
    }
}
