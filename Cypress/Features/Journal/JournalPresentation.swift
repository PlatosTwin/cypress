//
//  JournalPresentation.swift
//  Cypress — Features/Journal
//
//  **NOT SPECIFIED.** ERRATA E99, closed here.
//
//  ── What this screen is, and what it is allowed to be ─────────────────────────────────────────
//  `docs/ARCHITECTURE.md` rule 8: a screen or state in neither SCREENS.md nor BUILD-PLAN §9 is not
//  specified, must say so, and must follow the nearest specified thing rather than invent. The
//  journal is the strongest case of that rule in the app. BUILD-PLAN §9 M2 asks for an "empty
//  journal" and SCREENS.md draws no journal at all — no layout, no row, no empty state, no copy —
//  which is why E99 recorded it OPEN rather than guessing, and why `CypressAPI.journal(cursor:
//  limit:)` has returned a finished `Page<JournalEntry>` to nobody since the protocol was written.
//
//  So the nearest specified thing is asked for by name. A journal row says **a thing that happened,
//  on a day, to a tree** — which is precisely the sentence C10 (`IconTextRow`) already says in the
//  two places SCREENS.md draws it: screen 12's `This season` rows and screen 13's `Moments`. The row
//  is therefore C10, at C10's geometry, and the accent on each row is **screen 13's own assignment
//  for that kind of contribution** (`newGrowth` for an observation, `record` for a measurement,
//  `water` for care) rather than a second palette invented here. A person who has read screen 13
//  has already learnt this vocabulary; a journal that recoloured it would be teaching a second one
//  for the same facts.
//
//  Three decisions are mine and are argued where they are made:
//  - the list is **the store's order, not re-sorted** (`rows`);
//  - what it may say about its own extent is **derived from the cursor and from nothing else**
//    (`hasOlder`, `olderNote`, and, most importantly, `emptyState`);
//  - a visit takes the `elder` accent, the family's plain green, because it is the plainest of the
//    four and `bloom` is spoken for by a specific seasonal event on screen 12.
//
//  ── ERRATA E38, which is the whole reason this file is careful ────────────────────────────────
//  **A page of results must not be presented as a complete series.** `journal(cursor:limit:)` is a
//  cursor read: it returns rows and, when the page came back full, a cursor. It cannot know a total,
//  and there is no second call that could tell it one. So nothing here prints a count, a total, an
//  "N entries" header, or a fraction — not because counting is hard but because every number this
//  screen could print would be a number about a page wearing the clothes of a series. E38 is the
//  entry about `30 photos · since 2024` drawn over a tree with 214 photographs going back to 2019,
//  and this project has shipped that defect twice.
//
//  What the cursor *can* prove is the opposite, and it proves it exactly: a cursor came back means
//  there are older rows; no cursor means this read reached the end. Both sentences here are derived
//  from that one fact, and the second of them is load-bearing in a way that is easy to miss —
//  **`emptyState` is gated on the cursor rather than on `rows.isEmpty`.** "You have not recorded
//  anything yet" is a claim about a person's whole history, and a read that stopped early is not
//  entitled to make it.
//
//  ── D1 / ARCHITECTURE §5.1, which applies here with unusual force ─────────────────────────────
//  A time-ordered list of your own contributions is, as E99 put it, one design decision away from a
//  streak. `JournalEntry` carries no counts by construction and nothing is derived here that would
//  reintroduce one: no tally, no run of consecutive days, no "most active month", no comparison to
//  anybody. The dates on the rows are each record's own timestamp — an identifier for when a thing
//  happened, not a quantity of anything — and they are the only digits this screen draws.
//
//  No SwiftUI in this file, so every rule above is testable without a renderer
//  (`CypressTests/JournalPresentationTests.swift`).
//

import Foundation

// MARK: - Segments

/// The two things the `Journal` tab of C16 can show.
///
/// **Why there are two, and why the almanac is one of them.** E99 recorded that the Journal tab
/// hosts screen 12 and not the journal, and called the name of the tab promising something it does
/// not contain "the honest cost" of not inventing a screen. This file removes that cost — but the
/// almanac cannot simply be displaced to make room, because **the Journal tab is the almanac's only
/// entrance in the entire app**. `Route.almanac` exists, is resolved in `RootView`, and has no
/// `push` call site anywhere; `RootView`'s own comment on that arm says so. A journal that took the
/// tab for itself would have silently deleted screen 12 from the app while every test still passed,
/// which is precisely the class of defect ERRATA E57 was written about in the first place.
///
/// So both live here, and the reader picks. See `JournalTabView` for why the control is C5.
enum JournalSegment: String, CaseIterable, Identifiable {
    case journal
    case almanac

    var id: String { rawValue }

    var label: String {
        switch self {
        case .journal: return JournalCopy.journalSegment
        case .almanac: return JournalCopy.almanacSegment
        }
    }
}

// MARK: - Limits

enum JournalLimits {
    /// How many rows one read asks for.
    ///
    /// **NOT SPECIFIED.** `Page.maximumLimit` is 100 and that is a ceiling, not a page size: asking
    /// for the maximum on first paint means the screen waits on a hundred name lookups to draw the
    /// six rows a phone can show. Twenty-five is roughly three screenfuls at the drawn row height,
    /// which is enough that the first `Show older` is a deliberate act rather than something a
    /// reader trips over on their way down the first page.
    static let pageSize = 25
}

// MARK: - Presentation

/// Everything the journal list draws, derived from the rows read so far and the cursor that came
/// back with them.
struct JournalPresentation: Equatable {

    /// One C10 row.
    struct Row: Equatable, Identifiable {
        let id: UUID
        /// `Visited Grandmother Cypress` — **the act first, then the tree it was done to.**
        ///
        /// It used to be the tree's name alone, which is what My Grove's rows are titled, which is
        /// how two lists of different things came to look like one. A journal row is a sentence
        /// about something that happened; leading with the verb is what makes it read as one.
        let title: String
        /// The contributor's own note, or empty when the record carries none.
        ///
        /// The date left this line and became the section header above the row (`Day`), because a
        /// date repeated on every row is a date nobody reads, and a date over a group of rows is
        /// the structure of a chronology.
        let subtitle: String
        /// Screen 13's accent for this kind of contribution.
        let accent: CypressColor.TileAccent
        /// Where the row goes. Every row has one, which is the point of `everyRowHasADestination`.
        let treeID: UUID
        /// The photograph this row draws instead of the accent tile, when this tree has one
        /// (#176). See `JournalEntry.heroPhotoID` for the rule.
        let heroPhotoID: UUID?
    }

    /// One day's worth of rows, under the day.
    ///
    /// **Grouped by consecutive run, never by key.** `ContributionStore.journal` orders by
    /// `captured_at DESC`, so every row of one day is already contiguous; folding runs preserves that
    /// order exactly, while a `Dictionary(grouping:)` would impose an ordering of its own and
    /// `Show earlier` would start inserting rows into the middle of a list somebody is reading. It
    /// also means a page boundary that falls inside a day merges into the section already on screen
    /// rather than drawing the same date twice.
    struct Day: Equatable, Identifiable {
        /// The first row's id: stable, and unique without assuming two days never format alike.
        var id: UUID { rows[0].id }
        /// `Jul 12`, or `Jul 12, 2025` outside this year. Drawn uppercase by `.cypressMicroLabel()`.
        let header: String
        let rows: [Row]
    }

    /// Every row read so far, in the store's order. Kept flat as well as grouped, because the
    /// questions the suite asks about ordering and destinations are questions about the sequence.
    let rows: [Row]

    /// The same rows, under their days — what the list actually draws.
    let days: [Day]

    /// Whether the read came back with a cursor — the one fact this screen has about its own extent.
    let hasOlder: Bool

    /// The sentence under the list when there are older rows (E38). Nil when the read reached the
    /// end, because the end of a list needs no explaining.
    var olderNote: String? { hasOlder ? JournalCopy.olderNote : nil }

    /// The cold-start sentence — and it is **only** drawn when the read proved it had everything.
    ///
    /// A read that stopped early has rows it did not fetch, so it cannot say a person has recorded
    /// nothing; that is E38 pointed at the emptiest possible page, and it is the one place where
    /// getting E38 wrong tells somebody their own records are gone rather than merely miscounting
    /// them.
    var emptyState: String? {
        rows.isEmpty && !hasOlder ? JournalCopy.emptyState : nil
    }

    init(
        entries: [JournalEntry],
        nextCursor: String?,
        now: Date = .now,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) {
        // **The store's order, unchanged.** `ContributionStore.journal` orders by `captured_at DESC`
        // and the cursor is the last row's timestamp, so the query's order is the order the paging
        // is built on. A derivation that re-sorted would be a second ordering, and the first time the
        // two disagreed `Show older` would insert rows into the middle of a list somebody was
        // reading.
        self.rows = entries.map { entry in
            Row(
                id: entry.id,
                title: JournalCopy.rowTitle(
                    kind: entry.kind,
                    treeName: entry.treeDisplayName.isEmpty
                        ? TreeProfilePresentation.fallbackTitle
                        : entry.treeDisplayName
                ),
                subtitle: entry.summary.trimmingCharacters(in: .whitespacesAndNewlines),
                accent: JournalCopy.accent(for: entry.kind),
                treeID: entry.treeID,
                heroPhotoID: entry.heroPhotoID
            )
        }
        self.hasOlder = nextCursor != nil

        // Runs, not keys — see `Day`. The header is computed from the entry rather than re-parsed
        // out of a row, so the string on screen and the day the fold is made on come from one date.
        var days: [Day] = []
        var currentRows: [Row] = []
        var currentHeader = ""
        var currentDay: Date?
        for (index, entry) in entries.enumerated() {
            let startOfDay = calendar.startOfDay(for: entry.capturedAt)
            if startOfDay != currentDay {
                if !currentRows.isEmpty {
                    days.append(Day(header: currentHeader, rows: currentRows))
                    currentRows = []
                }
                currentHeader = JournalCopy.day(
                    entry.capturedAt, now: now, calendar: calendar, locale: locale
                )
                currentDay = startOfDay
            }
            currentRows.append(self.rows[index])
        }
        if !currentRows.isEmpty {
            days.append(Day(header: currentHeader, rows: currentRows))
        }
        self.days = days
    }
}

// MARK: - Copy

/// **Every string here is NOT SPECIFIED.** Each states a fact and stops (ARCHITECTURE §5.7),
/// sentence case, no spaces around em dashes.
///
/// The suite over this enum checks every one of them for a decimal digit, which is the bluntest
/// possible reading of D1 and catches a count, a total, a rank and a streak in one assertion.
enum JournalCopy {

    static let screenTitle = "Journal"

    /// C5's two labels. `Your journal` rather than `Journal` because the tab is already called
    /// Journal and a segment repeating its parent's name says nothing; the possessive is also the
    /// distinction that matters between the two halves — one is your record, the other is the
    /// neighbourhood's.
    static let journalSegment = "Yours"
    static let almanacSegment = "Neighborhood"

    /// The line above the list, saying what the list is.
    ///
    /// The other half of `GroveCopy.treesExplanation`, and the two are only worth anything as a pair:
    /// **one line per tree** over there, **one line for each time** here. Same length, same shape,
    /// opposite content — which is what makes the difference legible to somebody who has just come
    /// from the other screen, which is the exact reader this round is for.
    ///
    /// "Newest first" rather than "in order": the ordering is the one thing a chronology has that a
    /// collection does not, and it is worth one word.
    static let explanation =
        "One line for each thing you did, newest first, under the day it happened."

    /// The footnote, which is screen 08's own, verbatim.
    ///
    /// Borrowed rather than written because it is *already* the specification of every personal
    /// surface in this app, and this is the one most able to break it. It is the sentence that makes
    /// a list of your own contributions read as a record rather than a scoreboard.
    static let footnote = GroveCopy.footnote

    // MARK: The end of a page (ERRATA E38)

    /// Under the last row when a cursor came back.
    ///
    /// It says there are older entries and does not say how many, because how many is the one thing
    /// a cursor read cannot know. "Earlier" rather than "more" is deliberate: the list is ordered by
    /// time, so what is behind the cursor is a *direction*, not a remainder.
    static let olderNote = "There are earlier entries than these."
    static let olderAction = "Show earlier"
    /// A `Show earlier` that failed. The rows already on screen stay; only this line is new, which is
    /// why it is its own sentence rather than a reuse of `loadFailed`.
    static let olderFailed = "Earlier entries could not be read just now."

    // MARK: Empty and failed (ERRATA E126)

    /// A journal with nothing in it, which is what every device shows on day one.
    ///
    /// It says what the list is *for*, so that the emptiness reads as "nothing yet" rather than
    /// "nothing found" — the same job `PrivateReminderCopy.emptyState` does. It names the acts in
    /// the words the buttons that perform them use (`Check in`, `Care`), so a reader can tell what
    /// would put a row here.
    static let emptyState =
        "Nothing recorded yet. Checking in on a tree, caring for one, or measuring one writes a "
        + "line here, and it stays on this phone."

    /// **A read that failed, said as a failure** — never as an empty journal.
    ///
    /// This is ERRATA E126 on the third screen of that shape. Grove and Journal both used to draw
    /// their cold-start state over a failed read, which is indistinguishable from "you have nothing"
    /// and means the opposite. The wording is deliberately the one screen 08 already uses, so a
    /// reader meeting a second failure meets a screen they know how to leave.
    static let loadFailed = "Your journal could not be loaded."
    static let loadRetry = "Try again"

    // MARK: The export (ERRATA E39's method, given an entrance)

    static let exportLabel = "Take your record with you"
    /// What the file contains, in one line. It names the disclaimer that travels inside it rather
    /// than paraphrasing it, because the file says it too and the two must not drift.
    static let exportBody =
        "A copy of everything you have recorded on this phone, carrying "
        + StructureFlag.disclaimer + "."

    /// The row's title, per format.
    static func exportAction(_ format: ExportFormat) -> String {
        switch format {
        case .csv: return "Export as a spreadsheet"
        case .geojson: return "Export as map data"
        }
    }

    /// The row's second line — what each format is actually for, so the choice is not a guess about
    /// file extensions.
    static func exportTitle(_ format: ExportFormat) -> String {
        switch format {
        case .csv: return "One row per entry, for a spreadsheet"
        case .geojson: return "Points on a map, for mapping software"
        }
    }

    /// What lands in the share sheet.
    static func exportFileName(_ format: ExportFormat) -> String {
        switch format {
        case .csv: return "cypress-journal.csv"
        case .geojson: return "cypress-journal.geojson"
        }
    }

    // MARK: Rows

    /// Screen 13's accent for each kind of contribution.
    ///
    /// Three of the four are 13's own assignments, so the same contribution is the same colour on
    /// both screens. The fourth — a visit — takes `elder`, the family's plain green: it is the
    /// plainest of the four acts, and `bloom` is spoken for by "First bloom of the year" on screen
    /// 12, where it means a specific seasonal event rather than a person having been somewhere.
    ///
    /// `vacantSite` is unreachable here and must stay so: RULINGS R7 reserves it for a basin with no
    /// tree in it (ERRATA E119), and every row in this list is about a tree somebody visited.
    static func accent(for kind: JournalEntry.Kind) -> CypressColor.TileAccent {
        switch kind {
        case .visit: return .elder
        case .observation: return .newGrowth
        case .measurement: return .record
        case .careEvent: return .water
        }
    }

    /// `Visited`, `Observed`, `Measured`, `Cared for`.
    ///
    /// Past tense throughout, because every row is a thing that has already happened. The words are
    /// the acts as the app's own controls name them — screen 05 is a check-in, screen 09 is `Care`,
    /// screen 16 is a measurement — rather than the schema's table names.
    static func verb(for kind: JournalEntry.Kind) -> String {
        switch kind {
        case .visit: return "Visited"
        case .observation: return "Observed"
        case .measurement: return "Measured"
        case .careEvent: return "Cared for"
        }
    }

    /// `Visited Grandmother Cypress` — the row's title, verb first.
    ///
    /// ── Why the verb leads ────────────────────────────────────────────────────────────────
    /// The title used to be the tree's name alone, which is exactly what a row on My Grove's `Trees`
    /// pill is titled. Two lists of different things, drawn with one grammar, are one list as far as
    /// a reader is concerned — the project owner read them as one. A journal row is a sentence about
    /// something that happened, and putting the act at the front is what makes the column scan as a
    /// stream of acts rather than as a list of trees with details under them.
    ///
    /// The old row put the verb in the *subtitle*, in grey, at 12.5 pt, after which came a date and
    /// then the note. Nothing about that ordering said the verb was the subject.
    ///
    /// The tree's name is still here, because a journal entry with no tree in it is not a journal
    /// entry this app can have — every row opens a profile — and it is still what its own page calls
    /// it, fallback included.
    static func rowTitle(kind: JournalEntry.Kind, treeName: String) -> String {
        "\(verb(for: kind)) \(treeName)"
    }

    /// `Jul 12` inside this year, `Jul 12, 2025` outside it. **A section header now, not a clause.**
    ///
    /// It is the one element of a journal row the grove has no equivalent of, so it is the element
    /// that carries the difference: it leads, it is drawn as a rule across the column
    /// (`.cypressMicroLabel()`, the app's own section-header treatment), and it is written once for
    /// however many things happened that day rather than repeated on each of them.
    ///
    /// Still used by nothing else. `GroveCopy.treeSubtitle` used to call this so the two personal
    /// lists could not date the same record differently; it no longer prints a date at all, which
    /// settles that question more firmly than sharing a formatter did.
    ///
    /// **A journal spans years and the almanac's `shortDate` does not.** `AlmanacCopy.shortDate`
    /// drops the year on the stated grounds that "first bloom of the year" is about a day inside the
    /// current one. That reasoning does not transfer: this list is every contribution a person has
    /// ever made, and two different Julys drawn under the same label is the same day appearing
    /// twice. The year is added exactly when it is needed and never otherwise, so the common case
    /// keeps the app's shorter form.
    ///
    /// A year is an identifier, not a quantity, so it takes no grouping separator — the rule
    /// `AlmanacCopy.year` already states.
    static func day(_ date: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        formatter.setLocalizedDateFormatFromTemplate(sameYear ? "MMMd" : "MMMdyyyy")
        return formatter.string(from: date)
    }
}

// MARK: - Screen metrics

/// The geometry this list owns. **Not spec values** — nothing draws this screen — so each follows
/// the nearest thing that is drawn, named here so the view body carries no loose numbers
/// (ARCHITECTURE §6).
enum JournalMetrics {
    /// Between rows: C10's own gap on screens 12 and 13.
    static let rowGap: CGFloat = CypressSpacing.gapRows
    /// Above the first row and below the last, matching the section rhythm every other list uses.
    static let listTop: CGFloat = CypressSpacing.labelSectionTop
    /// Between one day and the next — larger than the gap between rows *within* a day, because that
    /// difference is what makes the grouping visible without a divider.
    static let dayGap: CGFloat = CypressSpacing.labelSectionTop
    /// The header sits a hair inside the cards, on the text's own left edge rather than the card's,
    /// which is where every other `micro.label` in the app sits relative to what it labels.
    static let dayHeaderInset: CGFloat = CypressSpacing.Component.iconRowPaddingH
}
