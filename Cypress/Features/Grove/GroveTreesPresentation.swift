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
//  a gray line ending in a date, which is one grammar for two meanings. Two things were changed to
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
//  layout, no row and no copy. The nearest specified thing was the screen it sits on: screen 08
//  carried the footnote "Quiet collecting. There are no streaks and no leaderboards.", and that
//  sentence is what this list was written against. The copy audit of 2026-08-23 removed the
//  footnote (owner ruling) and SCREENS.md 08 §6 is struck to match, so the sentence is no longer
//  drawn anywhere — but the rule it stated is DECISIONS D1's, which is where it came from and where
//  it still stands. Nothing below was derived from the footnote's presence on the screen.
//
//  The tally is the one thing here that had to be argued against that rule rather than derived
//  from it, and the argument is in `GroveRecord`, beside the type that carries it: never public,
//  never compared, never a reward, never summed across the grove, and never the thing the list is
//  ordered by. What is drawn is a description of one relationship with one tree, which is a
//  different object from a total. `GroveTreesTests.theTallyDoesNotSortTheList` and
//  `theTallyIsNeverATotal` are where that stops being a claim.
//
//  No SwiftUI in this file (`CypressTests/GroveTreesTests.swift`).
//

import Foundation

// MARK: - Limits

enum GroveLimits {
    /// How many trees one read asks for.
    ///
    /// **NOT SPECIFIED**, and chosen the way `JournalLimits.pageSize` was: by what a phone can
    /// draw, not by what the store can answer. `Page.maximumLimit` is 100 and that is a ceiling.
    ///
    /// **Fifty, measured on the running screen at the size the defect was found at.** A grove row
    /// is `IconTextRow` at about 100 pt drawn, so an iPhone 16 Pro shows between seven and eight of
    /// them; fifty is six or seven screenfuls, which is enough that the first `Show more` is a
    /// deliberate act rather than something a reader trips over on the way down the first page —
    /// `JournalLimits`' own rule, at this list's row height rather than the journal's. Twenty-five
    /// was tried first and rejected for the opposite failure: three screenfuls on a grove of a
    /// thousand puts the control in front of somebody twenty times.
    ///
    /// The upper bound is the one this round exists for. At 1,027 trees the whole list took 3.47 s
    /// of blank column to build; the numbers are in
    /// `docs/whats-new/perf-grove-trees-paging.md`, measured with timestamped screenshot bursts
    /// before and after on the same device.
    static let pageSize = 50
}

// MARK: - Presentation

/// Everything the `Trees` pill draws, derived from one `grove(cursor:limit:)` read.
struct GroveTreesPresentation: Equatable {

    /// One C10 row — the same component the journal list and screens 12 and 13 use, because it is
    /// the same sentence: a thing, with a line about it, that opens somewhere.
    struct Row: Equatable, Identifiable {
        var id: UUID { treeID }
        let treeID: UUID
        let title: String
        let subtitle: String
        /// The photograph this row draws instead of the accent tile, when this tree has one
        /// (#176). See `GroveEntry.heroPhotoID` for the rule.
        let heroPhotoID: UUID?
    }

    let rows: [Row]

    /// Whether the read came back with a cursor — the one fact this screen has about its own extent.
    let hasMore: Bool

    /// The sentence under the list when there are more trees, and nil when the read reached the end.
    /// `JournalPresentation.olderNote`'s shape exactly; see `GroveCopy.moreNote` for the one word
    /// that differs and why.
    var moreNote: String? { hasMore ? GroveCopy.moreNote : nil }

    /// The cold-start sentence, or nil when there is a grove to draw.
    ///
    /// **`!hasMore` is new and it is `JournalPresentation.emptyState`'s guard, arriving with the
    /// cursor.** The paragraph this replaces said the guard was unnecessary because "`grove()`
    /// returns an array rather than a `Page` and there is no read behind it that could have stopped
    /// early". That is no longer true of this list, and the guard is what keeps a first page that
    /// came back empty *with* a cursor from telling somebody their grove is empty — E38 pointed at
    /// the emptiest possible page. The other distinction, an empty grove against a read that
    /// failed, is still `GroveModel`'s job and not this type's.
    var emptyState: String? { rows.isEmpty && !hasMore ? GroveCopy.treesEmptyState : nil }

    /// No clock, and it is worth saying why one is not taken: **nothing this list draws is a date**.
    /// The parameters this used to carry (`now`, `calendar`, `locale`) existed to format `last visit
    /// Jul 12`, and that clause is gone — see `GroveCopy.treeSubtitle`.
    init(entries: [GroveEntry], hasMore: Bool = false) {
        self.hasMore = hasMore
        // **The store's order, unchanged.** `groveTreeIDs` orders by `last_visited DESC NULLS LAST`,
        // which puts the tree you saw most recently at the top and the ones you have only favorited
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
                ),
                heroPhotoID: entry.heroPhotoID
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

    // MARK: The end of a page

    /// Under the last row when a cursor came back, and the control that fetches the next page.
    ///
    /// **The owner ruled the affordance in on 2026-09-02** — page this list the way `Journal >
    /// Yours` is paged, reusing that list's own vocabulary and tokens and inventing no new one. So
    /// the control is `SecondaryOutlineButton(style: .compact)` under a `body12` muted line, which
    /// is `JournalListView.olderBlock` down to the modifier, and these three strings are
    /// `JournalCopy.olderNote` / `olderAction` / `olderFailed` with one word changed.
    ///
    /// **The word is `more` and not `earlier`, and the change is the point rather than a
    /// paraphrase.** `JournalCopy.olderNote`'s own comment gives the rule it is following:
    /// "'Earlier' rather than 'more' is deliberate: the list is ordered by time, so what is behind
    /// the cursor is a *direction*, not a remainder." Applying that rule to this list gives the
    /// opposite word. A grove is a set of nouns, not a chronology — this file's first paragraph is
    /// about nothing else — and its tail is the trees nobody has visited, which are not *earlier*
    /// than anything. What is behind the cursor here really is a remainder. Copying the journal's
    /// sentence verbatim would have been reusing its words while contradicting its reason, on the
    /// one screen the owner has already had to tell us reads too much like the journal.
    ///
    /// It does not say how many, for `olderNote`'s reason: how many is the one thing a cursor read
    /// cannot know (ERRATA E38).
    static let moreNote = "There are more trees than these."
    static let moreAction = "Show more"
    /// A `Show more` that failed. The rows already on screen stay; only this line is new.
    static let moreFailed = "More trees could not be read just now."

    /// **A read that failed, said as a failure** (ERRATA E126). Not "no trees here yet": that is a
    /// sentence about the person's grove, and saying it over a database that could not be read tells
    /// somebody their trees are gone. Same shape as `GroveCopy.loadFailed` one pill over, because it
    /// is the same event.
    static let treesLoadFailed = "Your trees could not be loaded."

    /// `Favorite · 4 visits · 1 measurement`, `3 visits`, `Favorite`.
    ///
    /// ── What this line is, and what it stopped being ──────────────────────────────────────
    /// It used to read `Favorite · last visit Jul 12`, and that sentence is why the project owner
    /// could not tell this screen from the Journal: both lists drew a tree's name in bold over a gray
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
    /// never-sorted-on tally is a description rather than a score, and for the five D1 clauses it has
    /// to satisfy.
    ///
    /// ── The clauses, and their order ──────────────────────────────────────────────────────
    /// The favorite clause leads, because it is a thing you *chose* rather than a thing you
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
    /// is left out (a journal row's missing note, screen 11's pills): a stated zero is a sentence
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
