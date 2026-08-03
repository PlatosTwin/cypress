//
//  SpeciesPickModel.swift
//  Cypress — Features/Species
//
//  Choosing one species out of 569, for a contributor who is stating what they think a tree is.
//
//  ── NOT SPECIFIED ────────────────────────────────────────────────────────────────────────────────
//  SCREENS.md has no species *picker*. It has a species search — screen 01's C20 bar — and that one
//  resolves to a narrowed map rather than to a chosen row (`MapSearch`, which argues at length why
//  there is no results screen behind it). This is the other shape of the same question, and the
//  difference is what the answer is for: on the map the reader is *filtering*, and the map is the
//  result; here the reader is *naming*, and a naming needs exactly one row to come back with.
//
//  ── What is reused, and what is deliberately not ─────────────────────────────────────────────────
//  Reused, whole:
//    · `CypressAPI.searchSpecies(query:limit:)` — the same protocol requirement `MapModel` calls,
//      backed by `SpeciesQueries.search`'s covering substring scan over both the scientific and
//      the common name. No second search was written, and no second query was written either.
//    · `SearchBar` (C20) — the same field, with its own placeholder, because a species field that
//      looked different from the app's other species field would be a second vocabulary for one act.
//    · `MapModel.searchDidChange`'s shape: cancel, debounce, refuse to debounce a *clear*. Copied as
//      a shape rather than shared as code, because the two differ in what they do with the answer and
//      sharing the four lines would mean sharing a type that has to know about both.
//
//  Not reused: `MapSearch` itself. Its states are claims about a map — "no *sycamore* in view",
//  "showing 30 of 214 here" — and every one of them is about a viewport this screen does not have.
//  A picker that borrowed them would be answering questions nobody asked it.
//
//  ── The limit is 25, not `MapSearch.speciesLimit`'s 100 ─────────────────────────────────────────
//  100 is the right number for narrowing a map, where every extra species is another pin the reader
//  might be looking for and nothing is read in a list. It is the wrong number for a list somebody has
//  to read: past a couple of dozen rows the answer to "which of these is it" is not more rows, it is
//  a better query. See `resultLimit`.
//
//  ── The matching gap is stated, not hidden ──────────────────────────────────────────────────────
//  `SpeciesQueries.search` matches a word **anywhere** in either name and ranks head matches above
//  interior ones (task #108), so "oak" does find "Coast Live Oak". What it still is not is the
//  trigram matching BUILD-PLAN §6 specifies, which needs an FTS5 index the seed does not carry: a
//  typo misses, and so does a name the catalogue spells another way. So `.noMatch` says the
//  catalogue has nothing *matching* what was typed rather than claiming no such tree exists. A
//  picker that said "no such species" over a spelling miss would be telling the contributor their
//  tree is not real, which is the opposite of this screen's job.
//
//  No SwiftUI in this file.
//

import Foundation
import Observation

/// What the catalogue said about what has been typed.
enum SpeciesPickState: Equatable {
    /// Nothing typed yet, or the field was cleared. The list is empty and that is not a failure.
    case idle
    /// A query is in flight or waiting out the debounce. Distinct from `.noMatch` on purpose: the
    /// frame between a keystroke and an answer must not read as "there is no such tree".
    case searching
    /// At least one match, in the catalogue's own ranking.
    case matched([Species])
    /// The catalogue has nothing matching this. Carries the query so the sentence can quote it.
    case noMatch(query: String)
}

@MainActor
@Observable
final class SpeciesPickModel {

    private let api: any CypressAPI

    var query: String = "" {
        didSet { guard query != oldValue else { return }; queryDidChange() }
    }

    private(set) var state: SpeciesPickState = .idle

    private var searchTask: Task<Void, Never>?

    init(api: any CypressAPI) {
        self.api = api
    }

    /// How many rows one query may offer. See the file header for why this is not the map's 100.
    static let resultLimit = 25

    /// The same debounce the map's bar uses. A 577-row species catalogue answers in 0.1 ms, so this
    /// is not about the database — it is about not redrawing a list under somebody's thumb while they
    /// are still typing the word.
    static let searchDebounce = Duration.milliseconds(180)

    private func queryDidChange() {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        // Clearing the field is not a search, and it must not wait out the debounce — the same rule
        // `MapModel` keeps, for the same reason: the reader has asked for the list to stop, now.
        guard !trimmed.isEmpty else {
            searchTask = nil
            state = .idle
            return
        }

        state = .searching
        searchTask = Task { [weak self, api] in
            try? await Task.sleep(for: Self.searchDebounce)
            if Task.isCancelled { return }
            let matches = (try? await api.searchSpecies(query: trimmed, limit: Self.resultLimit)) ?? []
            guard let self, !Task.isCancelled else { return }
            self.state = matches.isEmpty ? .noMatch(query: trimmed) : .matched(matches)
        }
    }

    /// Resolves a query without the debounce, for a caller that already knows the reader has stopped
    /// typing — and for tests, which should not have to sleep to assert on a state machine.
    func searchNow() async {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { state = .idle; return }
        state = .searching
        let matches = (try? await api.searchSpecies(query: trimmed, limit: Self.resultLimit)) ?? []
        state = matches.isEmpty ? .noMatch(query: trimmed) : .matched(matches)
    }
}

// MARK: - The words

/// Every string the picker renders, in one place to be argued with (ARCHITECTURE §5.7).
enum SpeciesPickCopy {

    static let title = "Which species?"

    /// C20's placeholder, narrowed to this screen's one job. Screen 01's bar says "Search a species…"
    /// because it is offering to filter; this one is asking a question, so it says what to type.
    static let placeholder = "Type a species name…"

    /// The line under the field before anything is typed.
    ///
    /// It names the contributor as the source in advance, so that nobody chooses a row believing the
    /// app is about to confirm it. The promise the screen makes here is the same one the record keeps
    /// and the same one the profile prints, which is the whole point.
    static let prompt =
        "Whatever you pick is recorded as your claim, not as a confirmed identification."

    /// The out. Named for the state it produces rather than for the act of leaving, because leaving
    /// without choosing *is* an answer: nobody has said what this tree is.
    static let skip = "I'm not sure"

    static let searching = "Looking…"

    /// A miss, quoting the query back.
    ///
    /// It said *starts with* for as long as the search was a prefix scan. Task #108 made the search
    /// match a word anywhere in either name, and this sentence had to move with it: telling somebody
    /// to "try the first word of either name" when the search no longer cares which word it is sends
    /// them to retype a query that already worked. It still stops short of "no such species" — the
    /// match is a substring one, not a trigram one, so a typo or a name the catalogue spells
    /// differently still misses, and a picker that called that miss non-existence would be telling a
    /// contributor their tree is not real.
    static func noMatch(query: String) -> String {
        "Nothing in the catalog matches “\(query)”. Try part of either name, or check the spelling."
    }

    /// A chosen row, restated where the choice was made. Common name first when there is one, by
    /// D15's rule that the common name is the fallback display everywhere.
    static func chosen(_ species: Species) -> String {
        species.commonName.isEmpty ? species.scientificName : species.commonName
    }
}
