//
//  MapSearch.swift
//  Cypress — Features/Map
//
//  What C20's search bar resolved to, and the words screen 01 says about it.
//
//  ── NOT SPECIFIED, and what was specified ────────────────────────────────────────────────────────
//  SCREENS.md 01 states the intent — "search opens species/street/neighborhood search" (:664) — and
//  then, three lines later, "NOT SPECIFIED: search results" (:667). PROTOTYPE-FLOW.md:105 lists the
//  bar as inert, which is what shipped: C20 was a `@Binding` to a `String` nothing read, and
//  `grep -rn searchText` returned exactly two lines, the declaration and the binding.
//
//  So the *result surface* is designed here, under ARCHITECTURE §8 rule 8, and this file is the
//  reasoning. Two decisions are worth stating outright because neither is in the spec:
//
//  1. **There is no results screen.** The map is the result. A list of species behind a sheet would
//     be a second surface to design, would cover the map the answer is drawn on, and is not what was
//     asked for — the ask was that typing a name "brought up all and only those trees", which is a
//     narrowing of the map in place. It also keeps C20 a real `TextField` in the accessibility tree,
//     which `CypressUITests/AccessibilityTreeTests` and `DeepLinkVoiceOverTests` both require.
//  2. **Species only, and the placeholder now says so.** See `SearchBar` for that argument.
//
//  ── Why the states are shaped like this ──────────────────────────────────────────────────────────
//  Every one of them exists because "nothing drawn" would otherwise be the answer to a different
//  question each time, and the reader cannot tell those apart from an empty map:
//
//      typed nothing              → the map is not narrowed at all
//      typed a word nothing knows → the catalogue has no such species; the map is showing you none
//      typed a real species       → and there are none of them *in this viewport*, which is not the
//                                   same statement and deserves different words
//      typed a real species       → and there are more here than the map can draw as pins
//
//  The last one is ERRATA E38's rule applied to the map: a truncated set must not be presented as a
//  complete one. `PinAnswer` carries how many matched so this can say so.
//

import Foundation

/// What the search bar resolved to, and what the map may honestly claim about it.
enum MapSearch: Equatable {

    /// Nothing typed. The map is the whole neighbourhood.
    case off

    /// A query the species catalogue has no prefix match for.
    ///
    /// Carries the query so the message can quote it back — "No species called *sycamore*" is a
    /// different sentence from "no results", and the difference is that the first one tells the
    /// reader the app understood them and the catalogue simply does not have it.
    case noMatch(query: String)

    /// A query that resolved to at least one species.
    case narrowed(Narrowed)

    /// A resolved search, and how much of it the current viewport is showing.
    struct Narrowed: Equatable {
        /// Every species the prefix matched. More than one is common and correct: `Prunus` is a
        /// genus, and narrowing to all of it is what the reader asked for.
        let speciesIDs: Set<UUID>
        /// For the message. The first few names, in the order the catalogue ranked them.
        let names: [String]
        /// Pins actually drawn, once an answer has arrived. `nil` before the first fetch settles.
        var drawn: Int?
        /// Trees that matched inside the viewport, which is `drawn` unless the grid thinned them.
        var matched: Int?

        /// Whether the map is showing a spatial sample rather than every match.
        var isSample: Bool {
            guard let drawn, let matched else { return false }
            return matched > drawn
        }
    }

    /// How many species one query may narrow to.
    ///
    /// `Page.maximumLimit` is 100 and `LocalAPI.searchSpecies` already clamps to it. Kept here as
    /// well so the number the map asks for is visible at the place that asks for it.
    static let speciesLimit = 100

    /// How many names the status line will read out before it starts counting instead.
    static let namesShown = 2

    /// Resolves a settled query against what the catalogue returned.
    init(query: String, matches: [Species]) {
        guard !matches.isEmpty else {
            self = .noMatch(query: query)
            return
        }
        self = .narrowed(Narrowed(
            speciesIDs: Set(matches.map(\.id)),
            // "the species common name is the fallback display everywhere" (D15) — and the other way
            // round here, because a species with no common name still has a scientific one.
            names: matches.map { $0.commonName.isEmpty ? $0.scientificName : $0.commonName }
        ))
    }

    /// The same search, told what the map just drew.
    ///
    /// A clustered viewport reports no counts: its badges already carry them, and "showing 151 of
    /// 1,458" is a sentence about pins. `MapContent.pinCount` counts the trees a clustered answer
    /// stands for, which is the honest number for the badges and the wrong one for this line.
    func reporting(_ content: MapContent, budget: Int) -> MapSearch {
        guard case var .narrowed(narrowed) = self else { return self }
        switch content {
        case let .pins(answer):
            narrowed.drawn = answer.items.count
            narrowed.matched = answer.treesRepresented
        case .clusters:
            narrowed.drawn = nil
            narrowed.matched = nil
        }
        return .narrowed(narrowed)
    }

    /// Whether the map is narrowed to anything at all.
    var isActive: Bool { self != .off }
}

// MARK: - The words

/// Screen 01's search status line.
///
/// Kept out of the view for the same reason every other `*Presentation` in this app is: the sentence
/// a state produces is a decision, it is worth a test, and a test should not have to render a
/// `View` to read it.
enum MapSearchCopy {

    /// The line drawn under the search bar, or `nil` when there is nothing to say.
    ///
    /// Nothing is said for an un-narrowed map, and nothing is said for a narrowed one that is
    /// showing every match it found — in that case the map itself is the answer and a banner
    /// repeating it is clutter over the thing the reader is trying to look at.
    static func status(for search: MapSearch) -> String? {
        switch search {
        case .off:
            return nil

        case let .noMatch(query):
            return "No species matches “\(query)”"

        case let .narrowed(narrowed):
            let subject = subject(narrowed.names)
            guard let drawn = narrowed.drawn, let matched = narrowed.matched else {
                // A clustered viewport, or the first frame before an answer landed. The badges are
                // already narrowed and already carry counts, so this only has to name the subject.
                return "Showing \(subject)"
            }
            if matched == 0 {
                // The species exists; there are none of it here. Naming the viewport is the whole
                // point — it tells the reader to move the map rather than to doubt the spelling.
                return "No \(subject) in view"
            }
            if matched > drawn {
                // ERRATA E38: a sample must say it is one, and say how much of one.
                return "Showing \(drawn) of \(matched) \(subject) here"
            }
            return nil
        }
    }

    /// What to call the thing being searched for.
    ///
    /// One species is its name. Two are both named, because a prefix that matches exactly two is
    /// usually a real ambiguity the reader wants to see. Beyond that the names stop being useful and
    /// the count is the honest summary — nobody reads seven species names off a map.
    static func subject(_ names: [String]) -> String {
        switch names.count {
        case 0: return "trees"
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return "\(names.count) species"
        }
    }
}
