//
//  SearchBar.swift
//  Cypress — DesignSystem/Components
//
//  C20 · `SearchBar` — SCREENS.md §2. The glass bar floating over the map (01, D1).
//
//  ~45pt tall as drawn (`padding:12px 18px` + a 14.5pt field), so it clears the tap minimum on its
//  own. The bar is positioned by its caller; §2's `top:68px; left:16px; right:16px` is an
//  absolute position on the map screen, not a property of the component.
//
//  **NOT SPECIFIED** (§5 gap 7): the search results screen behind it.
//

import SwiftUI

struct SearchBar: View {
    @Binding var text: String
    /// Verbatim from §2: `Species, street, or neighborhood…`
    var placeholder: String = "Species, street, or neighborhood…"

    var body: some View {
        HStack(spacing: CypressSpacing.Component.searchSpacing) {
            CypressSearchGlyph()
                .stroke(
                    CypressColor.searchGlyph,
                    style: StrokeStyle(
                        lineWidth: CypressSpacing.Component.searchIconStroke,
                        lineCap: .round
                    )
                )
                .frame(
                    width: CypressSpacing.Component.searchIcon,
                    height: CypressSpacing.Component.searchIcon
                )
                .accessibilityHidden(true)

            TextField(
                "",
                text: $text,
                prompt: Text(placeholder).foregroundColor(CypressColor.searchGlyph)
            )
            .font(CypressFont.body145)
            .foregroundStyle(CypressColor.textInk)
            .textFieldStyle(.plain)
            .accessibilityLabel("Search")
        }
        .padding(.vertical, CypressSpacing.Component.searchPaddingV)
        .padding(.horizontal, CypressSpacing.Component.searchPaddingH)
        .background { Capsule().fill(CypressColor.searchFill) }
        .cypressPillBorder(CypressColor.searchBorder)
        .cypressShadow(light: CypressShadow.searchBar, dark: CypressShadow.Dark.lg)
    }
}
