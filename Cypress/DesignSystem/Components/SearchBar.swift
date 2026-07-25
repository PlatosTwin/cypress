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
//  **NOT SPECIFIED** (§5 gap 7): the search results screen behind it. `MapSearch` is where the
//  surface that was designed instead is reasoned out.
//
//  ── The placeholder no longer promises street or neighborhood, and that is deliberate ────────────
//  §2 draws `Species, street, or neighborhood…` and this component said it verbatim for as long as
//  the bar did nothing at all — a promise costs nothing while the field is inert. It is not inert
//  any more: it narrows the map to a species (ERRATA E131), and it cannot do the other two.
//
//  Neither is a small gap to close. A street search wants `trees.address`, which carries no index —
//  every keystroke would be a scan of 195,309 rows on the map's critical path, which is the one
//  thing `TreeQueries` forbids outright. A neighbourhood search wants the boundary geometry the seed
//  does not ship; `TreeProfile.neighborhoodName` exists precisely because a neighbourhood has no
//  identity in this database beyond a name hanging off a tree. Both are `Tools/build_seed.py`'s work
//  before they can be the client's, exactly as `SpeciesQueries` already rules for the substring
//  matching an FTS5 index would take.
//
//  So the words match what happens. A bar that offers three kinds of search and answers one is the
//  defect this whole change exists to remove, not a nicety to leave for later — and it is worse than
//  a bar that offers one, because a reader who types a street and sees the map empty out has been
//  told, wrongly, that their street has no trees.
//

import SwiftUI

struct SearchBar: View {
    @Binding var text: String
    /// §2 draws `Species, street, or neighborhood…`; this is the half of it that works. See the file
    /// comment for why the other two are not a matter of writing more code here.
    var placeholder: String = "Search a species…"

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
