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
//      typed a word nothing knows → the catalog has no such species; the map is showing you none
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

    /// Nothing typed. The map is the whole neighborhood.
    case off

    /// A query the species catalog has no match for.
    ///
    /// Carries the query so the message can quote it back — "No species called *sycamore*" is a
    /// different sentence from "no results", and the difference is that the first one tells the
    /// reader the app understood them and the catalog simply does not have it.
    case noMatch(query: String)

    /// A query that resolved to at least one species.
    case narrowed(Narrowed)

    /// A resolved search, and how much of it the current viewport is showing.
    struct Narrowed: Equatable {
        /// Every species the query matched. More than one is common and correct: `Prunus` is a
        /// genus, and narrowing to all of it is what the reader asked for.
        let speciesIDs: Set<UUID>
        /// For the message. The first few names, in the order the catalog ranked them.
        let names: [String]
        /// Whether the catalog had more matches than `speciesLimit` and this is the first page.
        ///
        /// **This is E38 applied one level up from the pins.** The other counts on this struct are
        /// about trees; this one is about species, and it became reachable the moment matching
        /// stopped being prefix-only — "a" prefix-matches 97 species and *contains* in 555, well
        /// over the 100 the map asks for. Without this flag the status line reads "Showing 100
        /// species" for a query that matched five and a half times that, which is a page wearing a
        /// total's clothes.
        let isTruncated: Bool
        /// Pins actually drawn, once an answer has arrived. `nil` before the first fetch settles.
        var drawn: Int?
        /// Trees that matched inside the viewport, which is `drawn` unless the grid thinned them.
        var matched: Int?

        init(
            speciesIDs: Set<UUID>,
            names: [String],
            isTruncated: Bool = false,
            drawn: Int? = nil,
            matched: Int? = nil
        ) {
            self.speciesIDs = speciesIDs
            self.names = names
            self.isTruncated = isTruncated
            self.drawn = drawn
            self.matched = matched
        }

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

    /// Resolves a settled query against what the catalog returned.
    init(query: String, matches: [Species]) {
        guard !matches.isEmpty else {
            self = .noMatch(query: query)
            return
        }
        self = .narrowed(Narrowed(
            speciesIDs: Set(matches.map(\.id)),
            // "the species common name is the fallback display everywhere" (D15) — and the other way
            // round here, because a species with no common name still has a scientific one.
            names: matches.map { $0.commonName.isEmpty ? $0.scientificName : $0.commonName },
            // A full page is the only signal the catalog gives that there were more; it cannot
            // distinguish "exactly 100 matched" from "500 did", so it claims the weaker of the two.
            // Saying "the first 100" of exactly 100 is a true sentence; the reverse is not.
            isTruncated: matches.count >= MapSearch.speciesLimit
        ))
    }

    /// The same search, told what the map just drew.
    ///
    /// A clustered viewport reports no counts: its badges already carry them, and "showing 151 of
    /// 1,458" is a sentence about pins. `MapContent.pinCount` counts the trees a clustered answer
    /// stands for, which is the honest number for the badges and the wrong one for this line.
    func reporting(_ content: MapContent) -> MapSearch {
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
            let subject = subject(narrowed.names, truncated: narrowed.isTruncated)
            let counted = isCounted(narrowed)
            guard let drawn = narrowed.drawn, let matched = narrowed.matched else {
                // A clustered viewport, or the first frame before an answer landed. The badges are
                // already narrowed and already carry counts, so this only has to name the subject.
                return "Showing \(subject)"
            }
            if matched == 0 {
                // The species exists; there are none of it here. Naming the viewport is the whole
                // point — it tells the reader to move the map rather than to doubt the spelling.
                return counted ? "None of \(subject) are in view" : "No \(subject) in view"
            }
            if matched > drawn {
                // ERRATA E38: a sample must say it is one, and say how much of one. A counted
                // subject cannot be the noun those numbers count — "151 of 1458 the 6 matching
                // species" — so the trees are named and the species set follows the comma.
                return counted
                    ? "Showing \(drawn) of \(matched) trees here, from \(subject)"
                    : "Showing \(drawn) of \(matched) \(subject) here"
            }
            // A complete answer normally says nothing: the map is the answer. It cannot stay silent
            // when the *species* set behind it was itself a page, because then the map is complete
            // only with respect to a subset the reader was never told about (E38).
            return narrowed.isTruncated ? "Showing every tree of \(subject)" : nil
        }
    }

    /// Whether `subject` counted the species rather than naming them.
    ///
    /// The sentences above cannot substitute a count everywhere a name goes, and the day the search
    /// stopped matching prefixes only is the day that started showing: typing "cypress" resolves to
    /// six species, and screen 01 drew **"No 6 species in view"** on the simulator. Naming a subject
    /// and counting one are different parts of speech, so they get different sentences.
    ///
    /// A page is always counted, however few names came back with it.
    static func isCounted(_ narrowed: MapSearch.Narrowed) -> Bool {
        narrowed.isTruncated || narrowed.names.count > MapSearch.namesShown
    }

    /// What to call the thing being searched for.
    ///
    /// One species is its name. Two are both named, because a query that matches exactly two is
    /// usually a real ambiguity the reader wants to see. Beyond that the names stop being useful and
    /// the count is the honest summary — nobody reads seven species names off a map.
    ///
    /// The counted forms carry their own article — "**the** 6 matching species" — because every
    /// sentence that takes them needs one, and a phrase that has to be assembled at four call sites
    /// is a phrase that will read wrongly at one of them.
    static func subject(_ names: [String], truncated: Bool = false) -> String {
        // A page says so before it says anything else: the count is of what came back, not of what
        // matched, and "the first N" is the only honest article for it (E38).
        if truncated { return "the first \(names.count) matching species" }
        switch names.count {
        case 0: return "trees"
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return "the \(names.count) matching species"
        }
    }
}
