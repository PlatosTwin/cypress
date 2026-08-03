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
//  thing `TreeQueries` forbids outright. A neighborhood search wants the boundary geometry the seed
//  does not ship; `TreeProfile.neighborhoodName` exists precisely because a neighborhood has no
//  identity in this database beyond a name hanging off a tree. Both are `Tools/build_seed.py`'s work
//  before they can be the client's, exactly as `SpeciesQueries` already rules for the substring
//  matching an FTS5 index would take.
//
//  So the words match what happens. A bar that offers three kinds of search and answers one is the
//  defect this whole change exists to remove, not a nicety to leave for later — and it is worse than
//  a bar that offers one, because a reader who types a street and sees the map empty out has been
//  told, wrongly, that their street has no trees.
//
//  ── The clear control and the way out of the keyboard (task #110, ruling R16) ────────────────────
//  Two owner reports about this one control: "it's possible to get stuck in the search bar — cursor
//  active and no way to exit out of keyboard", and "I want a little x in far right of bar to clear
//  contents".
//
//  **The second is literally true; the first is not, and the difference is worth stating because it
//  changes what the fix is.** The bar had no clear control at all. It was *not* a keyboard trap:
//  measured on the simulator against this component exactly as it shipped — no `FocusState`, no
//  `submitLabel`, no `onSubmit` — pressing return already resigned focus, because that is SwiftUI's
//  default for a single-line `TextField` and always was. So there was a way out. What there was not
//  was a way out anybody could *see*: the key is labeled `return`, which reads as "insert a
//  newline" rather than "I am finished", and nothing else on screen 01 dismisses the keyboard —
//  tapping the map does not, because an `MKMapView` does not resign anyone's first responder, and
//  covering it with a tap-catcher that would takes the pan and the pinch with it. Meanwhile the
//  keyboard covers the FAB, the bottom card and the tab bar. A person who has not been taught to
//  reach for `return` is, for every practical purpose, stuck — which is the report.
//
//  SCREENS.md §2 draws C20 with one glyph and screen 01 lists nothing else in the bar, so neither
//  affordance is specified and DECISIONS constraint 21 applies. `docs/RULINGS.md` R16 records what
//  was chosen and why. What is added here is therefore **visibility**, not capability:
//
//    · `submitLabel(.search)` relabels the key that already worked, from `return` to `Search`, so it
//      reads as an exit instead of as a newline.
//    · a `Done` above the keyboard, which is the affordance the report was asking for. It lives on
//      the keyboard rather than on screen 01, so nothing the mock positions moves.
//
//  There is deliberately **no** `onSubmit` resigning focus. It was written, and then removed once the
//  measurement above showed it changed nothing: a line that appears to cause the behavior it merely
//  coincides with is how a comment ends up ratifying a defect on this project.
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

    /// A caller's own focus, for the one caller that has to *read* it.
    ///
    /// R16 owned the `FocusState` here on the grounds that "every caller wants the same behavior
    /// from it, and a binding threaded through two screens would be two chances to forget it". That
    /// stays true and stays the default — this is `nil` at three of the four call sites and they are
    /// unchanged. What changed is that screen 01 now drops a list of species under this bar (task
    /// #109, R25), and a dropdown has to disappear when the field it belongs to is no longer being
    /// typed into. Whether that has happened is a fact only the field knows, so the field can now be
    /// asked. `Done` and the return key keep working through whichever binding is in play.
    var focus: FocusState<Bool>.Binding?

    /// The focus when no caller supplied one, so the default behavior needs no caller at all.
    @FocusState private var ownFocus: Bool

    private var isFocused: FocusState<Bool>.Binding { focus ?? $ownFocus }

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
            .focused(isFocused)
            // The key already dismissed the keyboard (see the file comment — it was measured, not
            // assumed). This changes what it *says*: `Search` rather than `return`, which is the
            // difference between a key that reads as an exit and one that reads as a newline. iOS
            // draws the word for that role in the reader's own language.
            .submitLabel(.search)
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
                Button(SearchBarCopy.done) { isFocused.wrappedValue = false }
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
