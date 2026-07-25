//
//  GroveTreesPresentation.swift
//  Cypress — Features/Grove
//
//  Screen 08's `Trees` pill, which was drawn and inert for the whole life of the app.
//
//  ── What was wrong, and what "built" means here ───────────────────────────────────────────────
//  SCREENS.md 08 §2 draws three pills and only `Species` had anything behind it. `Trees` and
//  `Journal` were `Text` rather than `Button` — deliberately, and the reasoning was sound at the
//  time: a control that looks pressable and does nothing is worse than a label (DECISIONS constraint
//  21). What made that reasoning expire is that both destinations turned out to already exist.
//  `CypressAPI.grove()` has returned `[GroveEntry]` since the protocol was written, and its doc
//  comment on `groveSpecies` explains at length that "the two tabs of My Grove are keyed on
//  different things — one on the contributor's trees, one on the species they have come to know".
//  The list this pill wanted had been one call away the entire time.
//
//  ── What this list is allowed to say ──────────────────────────────────────────────────────────
//  **NOT SPECIFIED**: SCREENS.md 08 draws the pill and not the panel behind it, so there is no
//  layout, no row and no copy. The nearest specified thing is the screen it sits on, and screen 08's
//  own footnote is the specification: "Quiet collecting. There are no streaks and no leaderboards."
//  So the row says which tree, and why it is in this grove, and nothing else — no visit tally, no
//  first-met date, no ordering by how much you have done.
//
//  The subtitle's two clauses are the two arms of the query that produced the row.
//  `ContributionStore.groveTreeIDs` puts a tree in this grove because you visited it or because you
//  favourited it, and the sentence names whichever of those is true. That is a fact about the record
//  rather than a judgement about the person, and it is checkable against the SQL that built it.
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

    init(
        entries: [GroveEntry],
        now: Date = .now,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) {
        // **The store's order, unchanged.** `groveTreeIDs` orders by `last_visited DESC NULLS LAST`,
        // which puts the tree you saw most recently at the top and the ones you have only favourited
        // at the bottom. Re-sorting here would be a second ordering, and two orderings is two
        // chances to disagree — the one in SQL is the one the index is built for.
        self.rows = entries.map { entry in
            Row(
                treeID: entry.treeID,
                title: entry.displayName.isEmpty
                    ? TreeProfilePresentation.fallbackTitle
                    : entry.displayName,
                subtitle: GroveCopy.treeSubtitle(
                    isFavorite: entry.isFavorite,
                    lastVisitedAt: entry.lastVisitedAt,
                    now: now,
                    calendar: calendar,
                    locale: locale
                )
            )
        }
    }
}

// MARK: - Copy

/// The `Trees` pill's strings. **Every one is NOT SPECIFIED** — see the file comment.
extension GroveCopy {

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

    /// `Favorite · last visit Jul 12`, `Last visit Jul 12`, or `Favorite`.
    ///
    /// The favourite clause uses `QuadActionRow.Action.favorite.label` rather than a second spelling
    /// of the word: this list describes what a button did, and a list that renamed the act would be
    /// describing a different one. RULINGS R2 fixed that label as "the same string in every state",
    /// which is exactly the property a list of past acts needs from it.
    ///
    /// The date is a day, not a duration — "last visit Jul 12" rather than "visited 8 days ago". A
    /// duration is a quantity of time since you last did something, which is one rendering away from
    /// a lapsed streak (D1); a date is an identifier for when a thing happened. It is the same
    /// judgement `JournalCopy.day` makes, through the same function, so the two personal lists cannot
    /// come to date the same record differently.
    static func treeSubtitle(
        isFavorite: Bool,
        lastVisitedAt: Date?,
        now: Date,
        calendar: Calendar,
        locale: Locale
    ) -> String {
        let visit = lastVisitedAt.map { date in
            JournalCopy.day(date, now: now, calendar: calendar, locale: locale)
        }
        switch (isFavorite, visit) {
        case let (true, .some(day)):
            return "\(QuadActionRow.Action.favorite.label) · last visit \(day)"
        case let (false, .some(day)):
            return "Last visit \(day)"
        case (true, .none):
            return QuadActionRow.Action.favorite.label
        case (false, .none):
            // Unreachable through `groveTreeIDs`, which returns a row only when one of the two arms
            // matched. Empty rather than invented: a row with nothing true about it should say
            // nothing, not guess.
            return ""
        }
    }
}
