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
//  any more: it narrows the map to a species (ERRATA E134), and it cannot do the other two.
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
//  ── The clear control and the way out of the keyboard (task #110, ruling R15) ────────────────────
//  Two owner reports about this one control: "it's possible to get stuck in the search bar — cursor
//  active and no way to exit out of keyboard", and "I want a little x in far right of bar to clear
//  contents". Both were true of the component as drawn. It was a `TextField` and a glyph in an
//  `HStack` with no clear button, no `submitLabel`, no `FocusState` and no dismissal of any kind,
//  and on screen 01 there is nothing behind it to tap that would put the keyboard away: the map is
//  an `MKMapView`, and covering it with a tap-catcher to dismiss on tap would take the pan and the
//  pinch with it.
//
//  SCREENS.md §2 draws C20 with one glyph and screen 01 lists nothing else in the bar, so neither
//  affordance is specified and DECISIONS constraint 21 applies. `docs/RULINGS.md` R15 records what
//  was chosen and why; the short form is that there are now **two** ways out, because the one that
//  costs no pixels is also the one nobody finds:
//
//    · the return key says `Search` and dismisses (`submitLabel` + `onSubmit`). It was already a key
//      on the keyboard doing nothing at all, which is the worst of both.
//    · a `Done` above the keyboard, for the reader who does not think of the return key. It lives on
//      the keyboard rather than on screen 01, so nothing the mock positions moves.
//
//  The ✕ is drawn where the owner asked for it — hard against the trailing edge, on the bar's own
//  18 pt inset — while its *hit area* is the 44 pt ARCHITECTURE §6 requires, grown leftwards and
//  outwards from the visual rather than around it. It is an overlay so that growing it cannot change
//  the bar's height; the `HStack` reserves the width so the text never runs underneath it.
//

import SwiftUI

struct SearchBar: View {
    @Binding var text: String
    /// §2 draws `Species, street, or neighborhood…`; this is the half of it that works. See the file
    /// comment for why the other two are not a matter of writing more code here.
    var placeholder: String = "Search a species…"

    /// Owned here rather than passed in: every caller wants the same behaviour from it, and a
    /// `FocusState` binding threaded through two screens would be two chances to forget it.
    @FocusState private var isFocused: Bool

    /// Whether the clear control is drawn. One expression, read by the overlay and by the spacer
    /// that reserves its width, so the two can never disagree about whether it is there — a control
    /// in the accessibility tree with nothing under the finger is the failure task #100 is open on.
    private var showsClear: Bool { !text.isEmpty }

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
            .focused($isFocused)
            // The key was always there; now it does something. `.search` is what it is for, and the
            // word on it is the one iOS draws for that role in the reader's own language.
            .submitLabel(.search)
            .onSubmit { isFocused = false }
            .accessibilityLabel(SearchBarCopy.field)

            if showsClear {
                // Width only — the ✕ itself is an overlay, so that its 44 pt hit area cannot grow
                // the bar past the ~45 pt §2 draws.
                Color.clear
                    .frame(
                        width: CypressSpacing.Component.searchIcon,
                        height: CypressSpacing.Component.searchIcon
                    )
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, CypressSpacing.Component.searchPaddingV)
        .padding(.horizontal, CypressSpacing.Component.searchPaddingH)
        .background { Capsule().fill(CypressColor.searchFill) }
        .cypressPillBorder(CypressColor.searchBorder)
        .cypressShadow(light: CypressShadow.searchBar, dark: CypressShadow.Dark.lg)
        .overlay(alignment: .trailing) {
            if showsClear { clearButton }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(SearchBarCopy.done) { isFocused = false }
                    .font(CypressFont.body145)
            }
        }
    }

    /// The ✕, at the trailing edge, with a 44 pt target behind it.
    ///
    /// The trailing padding is the bar's own inset less half the difference between the target and
    /// the glyph, so the *glyph* lands exactly where a trailing glyph belongs — 18 pt in — while the
    /// target it sits in the middle of extends inwards over the gap beside the text.
    private var clearButton: some View {
        Button {
            text = ""
            // The field keeps focus: clearing is the start of the next query far more often than it
            // is the end of searching, and a reader who wanted the keyboard gone has `Done` and the
            // return key. Dismissing here would make the ✕ do two things and neither predictably.
        } label: {
            CypressClearGlyph()
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
                .cypressTapTarget()
        }
        .buttonStyle(.plain)
        .padding(
            .trailing,
            CypressSpacing.Component.searchPaddingH
                - (CypressSpacing.minTapTarget - CypressSpacing.Component.searchIcon) / 2
        )
        .accessibilityLabel(SearchBarCopy.clear)
    }
}

/// C20's words. Here rather than inline for ARCHITECTURE §5.7's reason: a string somebody reads is a
/// decision, and a decision should be findable.
enum SearchBarCopy {
    /// The field's own label. Pinned by `MapSearchUITests`, which asserts it, and by the VoiceOver
    /// ordering tests that walk screen 01 — do not rename it without them.
    static let field = "Search"
    /// The ✕. Says what it does to what, not what it looks like: "Clear" alone, read out in a list of
    /// map controls, does not say clear *what*.
    static let clear = "Clear search"
    /// The way out of the keyboard, for a reader who does not reach for the return key.
    static let done = "Done"
}
