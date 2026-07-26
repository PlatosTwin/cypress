//
//  GroveTreesPresentation.swift
//  Cypress — Features/Grove
//
//  Screen 08's `Trees` pill: **a set of nouns.**
//
//  ── What this list is, next to the one it was mistaken for ────────────────────────────────────
//  A row here is *one tree you have a relationship with*. A row in the Journal is *one thing you
//  did*. A tree you visited twenty times is one row here and twenty rows there, and that is not a
//  detail — it is the entire difference between the two surfaces, and the reason both exist.
//
//  They looked identical anyway, and the project owner said so. Both drew a tree's name in bold over
//  a grey line ending in a date, which is one grammar for two meanings. Two things were changed to
//  fix it structurally rather than with words:
//
//  - **the date is gone from the row.** Recency lives in the ordering (`last_visited DESC NULLS
//    LAST`, the store's, unchanged), which is where a stable collection should keep it. Nothing on
//    this screen is a chronology any more.
//  - **the row carries the shape of the relationship instead** — `Favorite · 4 visits · 1
//    measurement`. This is the one fact the journal cannot state without printing twenty rows, and
//    it is what makes "one row per tree, forever" visible.
//
//  ── What this list is allowed to say ──────────────────────────────────────────────────────────
//  **NOT SPECIFIED**: SCREENS.md 08 draws the pill and not the panel behind it, so there is no
//  layout, no row and no copy. The nearest specified thing is the screen it sits on, and screen 08's
//  own footnote is the specification: "Quiet collecting. There are no streaks and no leaderboards."
//
//  The tally is the one thing here that had to be argued against that footnote rather than derived
//  from it, and the argument is in `GroveRecord`, beside the type that carries it: never public,
//  never compared, never a reward, never summed across the grove, and never the thing the list is
//  ordered by. What is drawn is a description of one relationship with one tree, which is a
//  different object from a total. `GroveTreesTests.theTallyDoesNotSortTheList` and
//  `theTallyIsNeverATotal` are where that stops being a claim.
//
//  No SwiftUI in this file (`CypressTests/GroveTreesTests.swift`).
//

import Foundation

/// Everything the `Trees` pill draws, derived from one `grove()` read.
struct GroveTreesPresentation: Equatable {

    /// One C10 row — the same component the journal list and screens 12 and 13 use, because it is
    /// the same sentence: a thing, with a line about it, that opens somewhere.
    struct Row: Equatable, Identifiable {
        var id: UUID { treeID }
        let treeID: UUID
        let title: String
        let subtitle: String
    }

    let rows: [Row]

    /// The cold-start sentence, or nil when there is a grove to draw.
    ///
    /// Unlike the journal's, this one needs no cursor guard: `grove()` returns an array rather than a
    /// `Page` and there is no read behind it that could have stopped early, so an empty result really
    /// is an empty grove. The distinction that *does* have to be kept is the other one — an empty
    /// grove against a read that failed — and that is `GroveModel`'s job, not this type's.
    var emptyState: String? { rows.isEmpty ? GroveCopy.treesEmptyState : nil }

    /// No clock, and it is worth saying why one is not taken: **nothing this list draws is a date**.
    /// The parameters this used to carry (`now`, `calendar`, `locale`) existed to format `last visit
    /// Jul 12`, and that clause is gone — see `GroveCopy.treeSubtitle`.
    init(entries: [GroveEntry]) {
        // **The store's order, unchanged.** `groveTreeIDs` orders by `last_visited DESC NULLS LAST`,
        // which puts the tree you saw most recently at the top and the ones you have only favourited
        // at the bottom. Re-sorting here would be a second ordering, and two orderings is two
        // chances to disagree — the one in SQL is the one the index is built for.
        //
        // It is also the *only* place recency is now expressed, and the only ordering this list may
        // have: sorting by the tally would turn a description into a ranking (D1, `GroveRecord`).
        self.rows = entries.map { entry in
            Row(
                treeID: entry.treeID,
                title: entry.displayName.isEmpty
                    ? TreeProfilePresentation.fallbackTitle
                    : entry.displayName,
                subtitle: GroveCopy.treeSubtitle(
                    isFavorite: entry.isFavorite,
                    record: entry.record
                )
            )
        }
    }
}

// MARK: - Copy

/// The `Trees` pill's strings. **Every one is NOT SPECIFIED** — see the file comment.
extension GroveCopy {

    /// The line above the list, saying what the list is.
    ///
    /// **The project owner asked for this in those words** — *"some small explanatory note of what's
    /// on each page"* — after mistaking this pill for the Journal tab. Its opposite number is
    /// `JournalCopy.explanation`, and the pair is written to be read against each other: this one says
    /// *one line per tree*, that one says *one line per thing you did*. That is the whole difference
    /// between the two surfaces, stated in the place where a reader is deciding which one they are on.
    ///
    /// The model for the tone is `JournalCopy.emptyState`, which does its whole job in one breath.
    /// Two clauses: what a row is, and what governs how many there are. No adjectives, no invitation.
    static let treesExplanation =
        "One line per tree, however many times you have been back."

    /// A grove with no trees in it, which is what every device shows on day one.
    ///
    /// It names the two acts that would put a tree here, in the words of the controls that perform
    /// them: `Favorite` is screen 03's quad-row cell, and a visit is what the camera flow saves. So
    /// the emptiness reads as "nothing yet" rather than "nothing found", and a reader can tell what
    /// would change it.
    static let treesEmptyState =
        "No trees here yet. Favoriting a tree or saving a visit to one puts it in your grove."

    /// **A read that failed, said as a failure** (ERRATA E126). Not "no trees here yet": that is a
    /// sentence about the person's grove, and saying it over a database that could not be read tells
    /// somebody their trees are gone. Same shape as `GroveCopy.loadFailed` one pill over, because it
    /// is the same event.
    static let treesLoadFailed = "Your trees could not be loaded."

    /// `Favorite · 4 visits · 1 measurement`, `3 visits`, `Favorite`.
    ///
    /// ── What this line is, and what it stopped being ──────────────────────────────────────
    /// It used to read `Favorite · last visit Jul 12`, and that sentence is why the project owner
    /// could not tell this screen from the Journal: both lists drew a tree's name in bold over a grey
    /// line ending in a date. Two lists with one grammar are one list as far as a reader is concerned.
    ///
    /// **There is no date here now, and that is the point.** A grove is a set of nouns — which trees
    /// are mine, where do I go back to — and a journal is a stream of verbs. Recency has not been
    /// thrown away; it moved from the text into the *ordering*, which is `last_visited DESC NULLS
    /// LAST` and was always the store's. The most recently seen tree is at the top, where it was
    /// before, and it no longer has to say so in words the journal also uses.
    ///
    /// What takes the date's place is the one fact the journal cannot show without twenty rows: how
    /// much of a relationship this is. See `GroveRecord` for why a per-tree, per-kind, never-summed,
    /// never-sorted-on tally is a description rather than a score, and for the three D1 clauses it
    /// has to satisfy.
    ///
    /// ── The clauses, and their order ──────────────────────────────────────────────────────
    /// The favourite clause leads, because it is a thing you *chose* rather than a thing you
    /// accumulated, and it uses `QuadActionRow.Action.favorite.label` rather than a second spelling
    /// of the word: this list describes what a button did, and a list that renamed the act would be
    /// describing a different one. RULINGS R2 fixed that label as "the same string in every state".
    ///
    /// Then the kinds, in the order the acts sit in the app rather than by size — **by size would be
    /// a ranking**, and a ranking inside the row is the first step to a ranking between rows.
    ///
    /// A `nil` record contributes nothing at all, not `0 visits`: see `GroveEntry.record`.
    static func treeSubtitle(isFavorite: Bool, record: GroveRecord?) -> String {
        var parts: [String] = []
        if isFavorite { parts.append(QuadActionRow.Action.favorite.label) }
        if let record {
            parts.append(contentsOf: kindClauses(record))
        }
        // Empty when there is nothing true to say — a row with a name and no second line, which C10
        // draws without the gap. Reachable through `groveTreeIDs` only for a visited tree whose
        // implementation returned no record.
        return parts.joined(separator: " · ")
    }

    /// `4 visits`, `1 check-in`, `2 measurements`, `1 care log` — omitting every kind that is zero.
    ///
    /// Zeroes are left out rather than printed, for the reason every other absent clause in this app
    /// is left out (`JournalCopy.subtitle`'s summary, screen 11's pills): a stated zero is a sentence
    /// about what somebody has not done, and this screen does not have opinions about that.
    ///
    /// The nouns are the acts as the app's own controls name them — screen 05 is a check-in, screen
    /// 09 is a care log, screen 16 a measurement — rather than the schema's table names, matching
    /// `JournalCopy.verb` one screen over.
    private static func kindClauses(_ record: GroveRecord) -> [String] {
        [
            clause(record.visits, "visit", "visits"),
            clause(record.checkIns, "check-in", "check-ins"),
            clause(record.measurements, "measurement", "measurements"),
            clause(record.careEvents, "care log", "care logs")
        ].compactMap { $0 }
    }

    private static func clause(_ count: Int, _ singular: String, _ plural: String) -> String? {
        guard count > 0 else { return nil }
        return "\(count) \(count == 1 ? singular : plural)"
    }
}
