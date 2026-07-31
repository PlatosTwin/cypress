//
//  MapSuggestions.swift
//  Cypress — Features/Map
//
//  The list of species that drops under C20 as you type, and the one sentence that stops it lying
//  about how much of the catalogue it is showing you.
//
//  ── NOT SPECIFIED, and this is the third thing that has not been ────────────────────────────────
//  SCREENS.md 01 lists the search bar (C20) at `top:68px` and says of its behaviour only that
//  "search opens species/street/neighborhood search" (:664). Three lines later, under
//  **States/variants**, it says "**NOT SPECIFIED:** search results" (:667). §2's C20 draws a pill
//  with one leading magnifier and a placeholder and nothing else; §5's gap list carries the same
//  hole. So there is no drawn suggestion list at any text size, and DECISIONS constraint 21 says
//  stop rather than invent one. `docs/rulings-pending/search-suggestions.md` **R25** is that stop,
//  answered under the standing delegation, and this file is the machinery it decided on.
//
//  Two rulings already stand on this same control and neither is disturbed:
//    · **R16** (task #110) gave C20 the ✕ and the `Done`. Nothing here touches either. The ✕ still
//      clears and *keeps* focus, because clearing starts the next query; choosing a suggestion is
//      the opposite act and ends one, which is why it does the opposite thing with the keyboard.
//    · **E165** (task #108) made the catalogue match a word anywhere in either name with a rank.
//      No matching is written here. This list is a *rendering* of `CypressAPI.searchSpecies`, the
//      same call and the same page the map narrows itself with — one read, two surfaces, so the
//      list can never offer a species the map is not narrowed to.
//
//  ── The one way this ticket was most likely to go wrong (ERRATA E38) ─────────────────────────────
//  E165 made the 100-species cap **routine**: `a` prefix-matched 97 species before that change and
//  *contains* in 555 after it. A dropdown is a small surface — it shows a handful of rows — so it is
//  a page of a page, and a page's size is not a total. Six rows of five hundred and fifty-five
//  matches, drawn with nothing saying so, is precisely the defect E38 exists to name: a truncated
//  head presented as the whole answer.
//
//  So the remainder is modelled rather than described. `Remainder` has three cases and the third one
//  is the whole point: the catalogue's own answer was itself a page, so the app **does not know** the
//  total and may not print one. It claims the weaker of the two available sentences — "at least" —
//  for the same reason `MapSearch.Narrowed.isTruncated` does: saying "the first 100 of at least 100"
//  is true when exactly 100 matched, and the reverse is not.
//
//  No SwiftUI in this file. `MapSuggestionList` in `MapChrome` draws it.
//

import Foundation

/// What drops under the search bar for the query currently in it.
enum MapSuggestions: Equatable {

    /// Nothing to offer, and no sentence owed about it. Three different situations produce this and
    /// they are deliberately one case, because the *list* has the same job in all three — be absent:
    ///
    ///   · nothing has been typed;
    ///   · a suggestion was chosen, so the field already holds the answer the list would offer;
    ///   · the query matched nothing at all.
    ///
    /// The last of those is the one worth defending, because E126 requires a surface with nothing on
    /// it to say why. **It does say why — once, thirty points below, where it already said it.**
    /// `MapSearchCopy.status` has printed `No species matches “sycamore”` since E134, in a line that
    /// is on screen for exactly this state and no other. A no-match row in the list as well would put
    /// two spellings of one sentence on one screen, and the reader would have to work out whether
    /// they were being told two things. See R25.
    case off

    /// Rows to offer, and what is behind them.
    case listing(Listing)

    /// A page of the catalogue's ranking, and what the app knows about the rest of it.
    struct Listing: Equatable {
        /// The rows drawn, in the catalogue's own ranking — head matches above word matches above
        /// matches inside a word (E165). At most `MapSuggestions.rowLimit` of them.
        let rows: [Species]
        /// Everything the list is not showing.
        let remainder: Remainder

        init(rows: [Species], remainder: Remainder) {
            self.rows = rows
            self.remainder = remainder
        }
    }

    /// The matches this list is **not** drawing — E38, as a type rather than as a comment.
    ///
    /// The distinction between the last two cases is not pedantry and it is not cheap to recover
    /// later: `searchSpecies` returns a page, and a full page is the only evidence it gives that
    /// there were more. A caller that flattened `atLeast` into `exactly` would print a total the app
    /// has never counted.
    enum Remainder: Equatable {
        /// Every match the catalogue returned is on screen, and the catalogue's answer was not
        /// itself a page. This is the only state in which the list is the whole answer.
        case none
        /// Exactly this many more matched, all of them counted by the catalogue.
        case exactly(Int)
        /// At least this many more matched. The catalogue returned a full page
        /// (`MapSearch.speciesLimit`), so the true number is unknown and unknowable from here.
        case atLeast(Int)
    }

    /// How many species the dropdown offers before it starts counting instead.
    ///
    /// Not `MapSearch.speciesLimit`'s 100, which is the right number for *narrowing a map* — every
    /// extra species there is another pin the reader might be hunting and nothing is read in a list.
    /// Not `SpeciesPickModel.resultLimit`'s 25 either, which is the right number for a screen whose
    /// whole job is the list and which can scroll for as long as it likes.
    ///
    /// This list floats over the map that is answering the question, so every row it adds hides some
    /// of the answer.
    ///
    /// **Measured rather than estimated, and the estimate was wrong.** This said "about a third of
    /// the display" until it was drawn on an iPhone 16e: a two-line row is about 79 pt, so six of them
    /// come to roughly 480 pt and the height cap in `MapSuggestionList` bites first. Five and a bit
    /// rows are drawn and the part-row at the cut is what says the list scrolls, which is a better
    /// dropdown than six exactly. The number stays at six because the *cap*, not the count, governs
    /// how much of the map is hidden. See R25.
    static let rowLimit = 6

    /// Resolves what the catalogue returned into what the list should draw.
    ///
    /// `matches` is expected to be the answer to `searchSpecies(query:limit:)` at
    /// `MapSearch.speciesLimit` — the same array `MapSearch.init(query:matches:)` is handed, so the
    /// list and the map are two readings of one read and cannot disagree.
    init(matches: [Species]) {
        guard !matches.isEmpty else {
            self = .off
            return
        }
        let rows = Array(matches.prefix(MapSuggestions.rowLimit))
        let hidden = matches.count - rows.count
        // A full page from the catalogue means there may be more behind it, and there is no second
        // query in this app that could count them without reading the whole table on the typing
        // path. So the count stops being a total and starts being a floor. (E38.)
        let wasItselfAPage = matches.count >= MapSearch.speciesLimit
        let remainder: Remainder
        if wasItselfAPage {
            remainder = .atLeast(hidden)
        } else if hidden > 0 {
            remainder = .exactly(hidden)
        } else {
            remainder = .none
        }
        self = .listing(Listing(rows: rows, remainder: remainder))
    }

    /// The rows, or none. For the view and for tests that do not care which case they are in.
    var rows: [Species] {
        switch self {
        case .off: return []
        case let .listing(listing): return listing.rows
        }
    }
}

// MARK: - The words

/// Every string the dropdown draws (ARCHITECTURE §5.7: a string somebody reads is a decision).
enum MapSuggestionCopy {

    /// What a species is called, common name first when it has one.
    ///
    /// D15's rule — "the species common name is the fallback display everywhere" — and the other way
    /// round here, exactly as `MapSearch.init` already does it: a species with no common name still
    /// has a scientific one, and 59 of the seeded 569 are in that position.
    static func name(_ species: Species) -> String {
        species.commonName.isEmpty ? species.scientificName : species.commonName
    }

    /// The second line, which is empty for a species whose only name is already on the first.
    static func latin(_ species: Species) -> String? {
        species.commonName.isEmpty ? nil : species.scientificName
    }

    /// One row, as a single utterance.
    ///
    /// A VoiceOver reader arriving at a suggestion under a field they are typing into needs to hear
    /// what it *is* before they hear what it does, and the two names are the whole of what it is. The
    /// comma is what makes iOS pause between them rather than running `Monterey CypressHesperocyparis`
    /// together — the same combining `SpeciesPickView`'s row relies on.
    static func rowLabel(_ species: Species) -> String {
        guard let latin = latin(species) else { return name(species) }
        return "\(name(species)), \(latin)"
    }

    /// The container, so a reader navigating by element rather than by swipe is told how many rows
    /// dropped under the field they are still typing in — the failure a suggestion list under a text
    /// field classically produces, where the rows exist and nobody is told they arrived.
    ///
    /// It counts the rows *drawn*, never the matches, because that is what is under the finger. What
    /// the drawn rows are a page **of** is `remainder`'s sentence, and it is inside this container so
    /// the same reader hears it in the same sweep.
    static func listLabel(_ rows: Int) -> String {
        rows == 1 ? "1 species suggestion" : "\(rows) species suggestions"
    }

    /// **E38's sentence.** What the list is not showing, and what to do about it.
    ///
    /// `nil` for `.none`, and that silence is the only case in which it is honest: the list is the
    /// whole answer, so a line saying how much of the answer it is would be the app announcing that
    /// it had finished.
    ///
    /// The two counted forms are different sentences rather than one sentence with a different
    /// number, because "of 21" and "of at least 100" are different claims and the second one is the
    /// only thing the app can say when the catalogue itself answered with a page. Both name the way
    /// out — a suggestion list that says "there are more" and not "here is how to see them" has told
    /// the reader they are stuck.
    static func remainder(_ remainder: MapSuggestions.Remainder, shown: Int) -> String? {
        switch remainder {
        case .none:
            return nil
        case let .exactly(more):
            return "Showing \(shown) of \(shown + more) matching species. Keep typing to narrow it."
        case let .atLeast(more):
            return "Showing \(shown) of at least \(shown + more) matching species. "
                + "Keep typing to narrow it."
        }
    }
}
