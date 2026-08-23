//
//  ActivityPresentation.swift
//  Cypress — Features/Activity
//
//  Screen 13 · Tree activity. SCREENS.md lines 1095–1133.
//
//  "One tree's year in three small multiples… Below that, the year appears as a list of moments
//  instead of totals." This is the screen D2 was written about, and it is the screen most likely to
//  drift into a scoreboard, so almost every decision below is a rule from a document rather than a
//  layout choice.
//
//  ── 1. Nobody is named, anywhere ──────────────────────────────────────────────────────────
//  D11 / DECISIONS §3.11: contribution feeds are private by default; a public timeline says
//  "a visitor" unless `public_attribution` is opted into, and always for under-18 accounts. This
//  screen therefore renders **no name, no initial and no avatar** — there is no `User` on the
//  payload for `isPublicAttributionEffective` to be asked about, and the only honest thing a face
//  could say here is nothing. The two places SCREENS.md counts people (`four visitors caught the
//  bright new tips`, `six people know this tree`) are headcounts with no identity attached, and both
//  go through A8's floor of three. See `ActivityCopy` and ERRATA.
//
//  ── 2. Counts are counts of a tree, and the care count is not printed at all ───────────────
//  D1 kills counts of *user* actions; D2 keeps this screen's three counted small multiples. The two
//  are reconciled the way `TreeProfilePresentation.heroMetaPill` already reconciles them: a number
//  here describes one tree's record and is attributable to nobody, which is not the farmable,
//  per-person tally D1 was written against.
//
//  The one exception is stated in the top document rather than inferred. BUILD-PLAN §4 says of
//  `care_events`: "Never publicly counted or ranked (D1)", and BUILD-PLAN outranks SCREENS.md
//  (ARCHITECTURE §1). So the Care row draws its twelve bars — D2 keeps the chart, and the caption's
//  whole subject is the *rhythm* of care against the photo spike — and its legend prints no total.
//  Same for the moments list: `five care visits kept it going` becomes `Jun–Aug`. Recorded in ERRATA.
//
//  ── 3. A page is never a total, and here it is never a scale either ───────────────────────
//  ERRATA E38. Every count on this screen reads `Series.totalCount` or `Series.isComplete` first.
//  The chart card is stricter than a count needs to be: D2 makes the three rows share one vertical
//  scale, and that scale is the tallest bar across all thirty-six months, so a page in *any* of the
//  three understates the ceiling and draws the other two rows too tall. The card therefore needs all
//  three series whole or it does not render.
//
//  No SwiftUI in this file, so all of the above is testable without a renderer
//  (`CypressTests/ActivityPresentationTests.swift`).
//

import Foundation

// MARK: - The three series

/// Which small multiple a row is. Named rather than colored: a feature holds no color of its own
/// (ARCHITECTURE §6), so the view maps this to `CypressColor.chartSeries*`.
enum ActivitySeriesKind: String, CaseIterable, Identifiable {
    case photos
    case checkIns
    case care

    var id: String { rawValue }

    /// SCREENS.md 13 §2's legend names, verbatim.
    var name: String {
        switch self {
        case .photos: return "Photos"
        case .checkIns: return "Check-ins"
        case .care: return "Care"
        }
    }

    /// Whether the legend may print this series' total for the year.
    ///
    /// **BUILD-PLAN §4, `care_events`: "Never publicly counted or ranked (D1)".** It is the only one
    /// of the three the data model singles out, and BUILD-PLAN sits above SCREENS.md in the
    /// precedence order (ARCHITECTURE §1), so the drawn `9` is not drawn. The bars stay: D2 keeps
    /// the chart, and a shape is not a tally.
    var mayPrintTotal: Bool { self != .care }

    /// The noun the footnote's ceiling sentence uses — `June’s 12 photos set the ceiling.`
    func countedNoun(_ count: Int) -> String {
        switch self {
        case .photos: return count == 1 ? "photo" : "photos"
        case .checkIns: return count == 1 ? "check-in" : "check-ins"
        case .care: return count == 1 ? "care visit" : "care visits"
        }
    }
}

/// Where a strip cell's placeholder artwork comes from. Same reasoning as `ActivitySeriesKind`:
/// the recipes are `CypressGradient`'s, and the presentation only says which.
enum ActivityStripArt: String {
    case priorEarlier
    case priorRecent
    case currentWeek
}

// MARK: - Presentation

struct ActivityPresentation {

    /// One legend line plus its twelve bars (C23's bar variant).
    struct SeriesRow: Identifiable {
        let kind: ActivitySeriesKind
        /// `Photos`.
        let name: String
        /// `41`, or nil when the series may not print one. See `ActivitySeriesKind.mayPrintTotal`.
        let total: String?
        /// Twelve bar heights in the source's 0…34 scale, January first.
        let heights: [CGFloat]
        /// The zero-based month indices drawn in `chartGridline` because nothing happened in them.
        let emptyMonths: Set<Int>
        /// The raw monthly counts, January first. Not rendered as text; the accessibility label
        /// reads them, because twelve unlabeled rectangles are nothing to a screen reader.
        let counts: [Int]

        var id: String { kind.rawValue }
    }

    /// §2's whole card, which exists only when all three series are whole and something happened.
    struct Glance {
        /// The mono range in the card header — `2026`.
        let year: String
        let rows: [SeriesRow]
        /// §5's footnote. Its second sentence is present only when it can be written truthfully.
        let footnote: String
    }

    /// One C10 row of §3's `Moments`.
    ///
    /// `Kind` carried `springFlush` and `dryWeeks` until the copy audit of 2026-08-23 removed both
    /// rows (owner ruling); see `moments` for what they were and why the builders are gone rather
    /// than dark.
    struct Moment: Identifiable {
        enum Kind: String { case onRecord }

        let kind: Kind
        let accent: CypressColor.TileAccent
        let title: String
        let subtitle: String

        var id: String { kind.rawValue }
    }

    /// One tile of §4's three-up strip.
    struct StripCell: Identifiable {
        let id: UUID
        /// `2024`, or `this week` for the current year's tile.
        let label: String
        /// The current-year tile takes the 2pt Canopy border and the inverted chip (§4).
        let isCurrentWeek: Bool
        let art: ActivityStripArt
    }

    let profile: TreeProfile
    private let now: Date
    private let calendar: Calendar
    private let locale: Locale
    private let base: TreeProfilePresentation

    init(profile: TreeProfile, now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) {
        self.profile = profile
        self.now = now
        self.calendar = calendar
        self.locale = locale
        self.base = TreeProfilePresentation(profile: profile, now: now, calendar: calendar)
    }

    /// C1's trailing pill — the tree, named the way every other surface names it.
    var treeDisplayName: String { base.title }

    // MARK: - §2 This year at a glance

    /// The chart card, or nil.
    ///
    /// Two reasons it is nil, and both are the same rule seen from different sides:
    ///
    /// - **A page cannot found a shared scale.** D2 puts one vertical scale across all three rows,
    ///   set by the tallest month anywhere in them. A page understates that ceiling, so the two rows
    ///   it did not come from get drawn too tall and the card's one claim — "a tall bar means the
    ///   same amount everywhere" — becomes false without anything on screen saying so (ERRATA E38).
    /// - **Nothing happened.** Thirty-six empty bars under `This year at a glance` is an aggregate
    ///   surface with nothing behind it, which ARCHITECTURE §5.6 says does not render at all. E54
    ///   settled the same argument at zero on screen 12 in §5.6's favor.
    var glance: Glance? {
        let series = monthlySeries
        guard let series else { return nil }

        let peak = series.flatMap(\.counts).max() ?? 0
        guard peak > 0 else { return nil }

        let rows = series.map { entry in
            SeriesRow(
                kind: entry.kind,
                name: entry.kind.name,
                total: entry.kind.mayPrintTotal
                    ? ActivityCopy.grouped(entry.counts.reduce(0, +), locale: locale)
                    : nil,
                heights: entry.counts.map { ActivityMetrics.barHeight(count: $0, peak: peak) },
                emptyMonths: Set(entry.counts.indices.filter { entry.counts[$0] == 0 }),
                counts: entry.counts
            )
        }

        return Glance(
            year: String(calendar.component(.year, from: now)),
            rows: rows,
            footnote: ActivityCopy.footnote(ceiling: ceiling(in: series, peak: peak))
        )
    }

    /// The three series bucketed into the twelve months of the current year, or nil when any of them
    /// is a page.
    private var monthlySeries: [(kind: ActivitySeriesKind, counts: [Int])]? {
        let photos = base.visiblePhotos
        let checkIns = base.visibleObservations
        let care = base.visibleCareEvents
        guard photos.isComplete, checkIns.isComplete, care.isComplete else { return nil }

        return [
            (.photos, monthCounts(photos.items.map(\.capturedAt))),
            (.checkIns, monthCounts(checkIns.items.map(\.capturedAt))),
            (.care, monthCounts(care.items.map(\.capturedAt))),
        ]
    }

    /// Twelve counts, January first, over the current calendar year only.
    private func monthCounts(_ dates: [Date]) -> [Int] {
        let year = calendar.component(.year, from: now)
        var counts = [Int](repeating: 0, count: 12)
        for date in dates where calendar.component(.year, from: date) == year {
            let month = calendar.component(.month, from: date)
            guard (1...12).contains(month) else { continue }
            counts[month - 1] += 1
        }
        return counts
    }

    /// Which month set the ceiling, for §5's second sentence — or nil when naming it would print a
    /// number this screen withholds.
    ///
    /// Scanning in `ActivitySeriesKind` order and then by month makes the tie deterministic and puts
    /// the earliest month of the first series in front, which is the mock's own reading (`June’s 12
    /// photos`). A ceiling set by the Care row names no month at all: the sentence's whole content
    /// is a care count, and BUILD-PLAN §4 does not publish one.
    private func ceiling(
        in series: [(kind: ActivitySeriesKind, counts: [Int])],
        peak: Int
    ) -> (month: String, count: Int, kind: ActivitySeriesKind)? {
        for entry in series {
            guard entry.kind.mayPrintTotal else { continue }
            guard let index = entry.counts.firstIndex(of: peak) else { continue }
            return (ActivityCopy.monthName(index + 1, calendar: calendar, locale: locale), peak, entry.kind)
        }
        return nil
    }

    // MARK: - §3 Moments

    /// The C10 rows, in SCREENS.md's order, each present only when the record proves it.
    ///
    /// **There is one of them now, and there were three.** The copy audit of 2026-08-23 killed rows
    /// 1 and 2 by owner ruling. Their titles — `Spring flush noted` and `Watered through the dry
    /// weeks` — asserted a seasonal narrative nothing in the app detects: the rows keyed off a
    /// `leaf_out` tag and a count of waterings in named months, and then captioned that arithmetic
    /// as a season. `Seven years on record` survives because it says what it counts.
    ///
    /// The row builders went with the titles rather than being left dark, so there is no dormant
    /// code path waiting to draw a killed string.
    var moments: [Moment] {
        [yearsOnRecord].compactMap { $0 }
    }

    // Rows 1 and 2 — `Spring flush noted` and `Watered through the dry weeks`, with their
    // subtitles `Apr 3 · four visitors caught the bright new tips` and `Jun–Aug` — were removed by
    // the copy audit of 2026-08-23 (owner ruling). SCREENS.md 13 §3's first two table rows are
    // struck to match.
    //
    // **The builders are deleted rather than left unreferenced**, because a dark builder is how a
    // killed string comes back: the next reader finds `springFlush` intact, assumes the row was
    // dropped by accident, and reinstates it. What they did is on the record here instead. Row 1
    // fired on a visit tagged `leaf_out` in the current year and counted distinct contributors
    // against A8's floor; row 2 fired on waterings falling in two or more of
    // `ActivityMetrics.dryMonths` and printed the span, its own doc comment noting that
    // SCREENS.md's `· five care visits kept it going` was already dropped as a public count
    // BUILD-PLAN §4 forbids. Neither detection is lost — the visits and care events they read are
    // still on the timeline and still in the three charts above; what is gone is the screen calling
    // them a season.
    //
    // `ActivityMetrics.dryMonths` and `minimumDryMonths` went with row 2. `PhenologyTag.leafOut` is
    // untouched: it is stored vocabulary and the check-in screen still writes it.

    /// `Seven years on record` · `First photo Mar 2019 · six people know this tree`.
    ///
    /// Both halves of the subtitle are claims about the whole photo series — the earliest photograph
    /// and the span it opens — so a page produces no row (ERRATA E38: a page of thirty read as
    /// `since 2024` on a tree photographed since 2019).
    ///
    /// A tree first photographed this year is on record for zero years, and `Zero years on record`
    /// is the zero ARCHITECTURE §5.6 forbids, so the row needs a full year behind it.
    private var yearsOnRecord: Moment? {
        let photos = base.visiblePhotos
        guard photos.isComplete, let earliest = photos.items.map(\.capturedAt).min() else { return nil }

        let years = calendar.component(.year, from: now) - calendar.component(.year, from: earliest)
        guard years >= ActivityMetrics.minimumYearsOnRecord else { return nil }

        return Moment(
            kind: .onRecord,
            accent: .record,
            title: ActivityCopy.onRecordTitle(years: years, locale: locale),
            subtitle: ActivityCopy.onRecordSubtitle(
                firstPhotoAt: earliest,
                caretakers: base.caretakers?.count ?? 0,
                calendar: calendar,
                locale: locale
            )
        )
    }

    // MARK: - §4 Same week, other years

    /// Up to three tiles: this calendar week in earlier years, and this week.
    ///
    /// **The heading is the constraint.** `Same week, other years` is false with no other year in it,
    /// so a strip that would hold only the current week's photograph does not render — a bordered
    /// tile labeled `this week` beside nothing is a comparison with nothing to compare against.
    ///
    /// The tiles are gradient placeholders because every image in this app is (SCREENS.md §2
    /// preamble, C22). A placeholder still stands for a photograph that exists: a tile is drawn only
    /// where a photograph was actually taken in that week of that year, never to fill the row out.
    var sameWeek: [StripCell] {
        let photos = base.visiblePhotos
        // Which years hold a photograph from this week is a statement about the whole series.
        guard photos.isComplete else { return [] }

        let week = calendar.component(.weekOfYear, from: now)
        let thisYear = calendar.component(.year, from: now)

        var newestPerYear: [Int: Photo] = [:]
        for photo in photos.items where calendar.component(.weekOfYear, from: photo.capturedAt) == week {
            let year = calendar.component(.yearForWeekOfYear, from: photo.capturedAt)
            if let held = newestPerYear[year], held.capturedAt >= photo.capturedAt { continue }
            newestPerYear[year] = photo
        }

        let years = newestPerYear.keys.sorted().suffix(ActivityMetrics.stripCells)
        guard years.contains(where: { $0 < thisYear }) else { return [] }

        var priorIndex = 0
        return years.compactMap { year -> StripCell? in
            guard let photo = newestPerYear[year] else { return nil }
            if year == thisYear {
                return StripCell(
                    id: photo.id,
                    label: ActivityCopy.thisWeekChip,
                    isCurrentWeek: true,
                    art: .currentWeek
                )
            }
            let art: ActivityStripArt = priorIndex == 0 ? .priorEarlier : .priorRecent
            priorIndex += 1
            return StripCell(id: photo.id, label: String(year), isCurrentWeek: false, art: art)
        }
    }

    // MARK: - The empty screen

    /// Nothing on this tree's record has anything to say about a year.
    ///
    /// **This is the state every tree in the shipped app is in.** The seed carries `trees`,
    /// `species`, `neighborhoods`, `species_assertions`, `species_map`, `seed_meta` and the R*Tree —
    /// no visits, no observations, no care events and no photos — so on launch day every tree's
    /// activity screen is this one. SCREENS.md 13 draws only the full state; see ERRATA.
    var isEmpty: Bool { glance == nil && moments.isEmpty && sameWeek.isEmpty }
}

// MARK: - Copy

/// Screen 13's strings, verbatim from SCREENS.md 13 including its typographic characters, except
/// where a clause is deliberately left out and says so.
///
/// Every sentence with a number in it is assembled from parts rather than templated whole, so a
/// clause that is not true — or that may not be printed — can be dropped instead of softened.
enum ActivityCopy {

    /// §1's header title.
    static let screenTitle = "Activity"

    /// §2's card title.
    static let glanceTitle = "This year at a glance"

    /// §3's micro-label.
    static let momentsLabel = "Moments"

    /// §4's micro-label and its current-week chip.
    static let sameWeekLabel = "Same week, other years"
    static let thisWeekChip = "this week"

    // MARK: §3's titles

    // Rows 1 and 2 — `Spring flush noted` and `Watered through the dry weeks` — were removed by the
    // copy audit of 2026-08-23 (owner ruling: they caption arithmetic as a season). SCREENS.md 13
    // §3's first two table rows are struck to match.

    /// §3 row 3 — `Seven years on record`. The mock spells its number out and so does this.
    static func onRecordTitle(years: Int, locale: Locale) -> String {
        let spelled = spelledOut(years, locale: locale)
        let noun = years == 1 ? "year" : "years"
        return spelled.prefix(1).uppercased() + spelled.dropFirst() + " \(noun) on record"
    }

    // MARK: §3's subtitles

    // Both subtitles went with their rows in the copy audit of 2026-08-23: row 1's
    // `Apr 3 · four visitors caught the bright new tips`, and row 2's `monthRange(from:to:…)`, which
    // rendered `Jun–Aug`.
    //
    // `monthRange` is deleted rather than kept as a utility because it had exactly one caller — the
    // dry-weeks row — and `Species.CareNote.monthRange` is a different symbol that a grep for
    // "monthRange" will find nine times over. Checked by callers, not by name.

    /// `First photo Mar 2019 · six people know this tree`.
    ///
    /// The second clause is A8's, floored at three, and it is a count of *people who know the tree*
    /// rather than of anything anybody did (D1). Lower case mid-sentence, as the mock writes it;
    /// `TreeProfilePresentation.caretakerHeadline` is the same sentence standing alone on 03 and is
    /// capitalized there for that reason.
    static func onRecordSubtitle(
        firstPhotoAt: Date,
        caretakers: Int,
        calendar: Calendar,
        locale: Locale
    ) -> String {
        let first = "First photo " + monthYear(firstPhotoAt, calendar: calendar, locale: locale)
        guard caretakers >= TreeProfilePresentation.caretakerThreshold else { return first }
        return "\(first) · \(spelledOut(caretakers, locale: locale)) people know this tree"
    }

    // MARK: §5's footnote

    /// `One scale across all three charts, so a tall bar means the same amount everywhere. June’s 12
    /// photos set the ceiling.`
    ///
    /// The first sentence is a fact about the chart above it and is always true, because the shared
    /// scale is how `glance` is built. The second names the month that set the ceiling and is only
    /// written when there is a month to name and a number this screen publishes — a ceiling set by
    /// the Care row leaves the first sentence standing alone (BUILD-PLAN §4).
    static func footnote(ceiling: (month: String, count: Int, kind: ActivitySeriesKind)?) -> String {
        let opening = "One scale across all three charts, so a tall bar means the same amount everywhere."
        guard let ceiling else { return opening }
        return "\(opening) \(ceiling.month)’s \(ceiling.count) \(ceiling.kind.countedNoun(ceiling.count)) set the ceiling."
    }

    // MARK: The state SCREENS.md does not draw

    /// **NOT SPECIFIED.** SCREENS.md 13 draws one state, the full one, and this is the state every
    /// tree in the shipped app is actually in. Written in the shape `GrowthHistoryCopy.emptyState`
    /// and `TreeProfilePresentation.coldStartFootnote` already use — state a fact, drop the rest of
    /// the screen, invent nothing (DECISIONS constraint 21). See ERRATA.
    static let emptyState = "Nothing has been recorded on this tree yet."

    /// **NOT SPECIFIED**, same reasoning as 11's. SCREENS.md 13 draws no failure state.
    static let notFound = "No record for this tree."
    static let loadFailed = "This tree's activity could not be loaded."
    static let retry = "Try again"

    // MARK: Numbers and dates

    /// `three`, `six`, `seven`. The formatter spells rather than a table of my own words, so a reader
    /// in another language gets their own — the same reason `AlmanacCopy.spelledOut` exists.
    static func spelledOut(_ value: Int, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        formatter.locale = locale
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    /// `41`, `1,204`. Grouping is the formatter's.
    static func grouped(_ value: Int, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    /// `Apr 3` and `Mar 2019`.
    ///
    /// Built against the *caller's* calendar rather than taken from
    /// `TreeProfilePresentation.dayStamp`, which is a shared static and therefore carries the system
    /// time zone. Every date on this screen is derived from a window the caller decided — "this
    /// year", "this week", "the dry months" — and formatting the result in a different zone than the
    /// one the window was cut in puts a photograph in a month the chart above it does not have a bar
    /// for. `AlmanacCopy.shortDate` takes its calendar for the same reason.
    static func dayStamp(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        formatter(template: "MMMd", calendar: calendar, locale: locale).string(from: date)
    }

    static func monthYear(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        formatter(template: "MMMyyyy", calendar: calendar, locale: locale).string(from: date)
    }

    private static func formatter(template: String, calendar: Calendar, locale: Locale) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }

    /// `June` — the footnote writes the month out.
    static func monthName(_ month: Int, calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        let symbols = formatter.standaloneMonthSymbols ?? TreeProfilePresentation.monthNames
        guard (1...symbols.count).contains(month) else { return "" }
        return symbols[month - 1]
    }

    /// `Jun` — the moments list abbreviates it.
    static func shortMonthName(_ month: Int, calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        let symbols = formatter.shortStandaloneMonthSymbols ?? []
        guard (1...symbols.count).contains(month) else {
            return monthName(month, calendar: calendar, locale: locale)
        }
        return symbols[month - 1]
    }
}

// MARK: - Screen metrics

/// The geometry and the thresholds SCREENS.md 13 gives this screen that the design system does not
/// already name. Kept together so the view body carries no loose numbers and so every judgment call
/// on this screen can be argued with in one place.
enum ActivityMetrics {

    // MARK: The shared scale (D2)

    /// The shortest bar the mock draws — the stub an empty month keeps so the axis stays readable.
    /// §2's Care row: "starred bars drawn in `#EAEDDF` (no care that month)", all at height 4.
    static let barMinimum: CGFloat = 4
    /// The tallest bar the mock draws: June's photo spike, which sets the ceiling for all three rows.
    static let barMaximum: CGFloat = 34

    /// One height rule for all three rows, which is the whole of D2 on this screen.
    ///
    /// A month with nothing in it keeps the stub and is told from a month with one thing in it by
    /// color, which is how the mock tells them apart — its Care row has bars of height 4 in both
    /// treatments. A month with something in it is never shorter than the stub, so "nothing here"
    /// and "one thing here" cannot swap places at any peak.
    static func barHeight(count: Int, peak: Int) -> CGFloat {
        guard count > 0, peak > 0 else { return barMinimum }
        let span = barMaximum - barMinimum
        return barMinimum + span * CGFloat(count) / CGFloat(peak)
    }

    // MARK: Thresholds

    // §3 row 2's window (`dryMonths`, Jun–Aug) and its two-month floor (`minimumDryMonths`) went
    // with the row in the copy audit of 2026-08-23. Both were **NOT SPECIFIED** guesses standing
    // behind a sentence about a season, which is the thing the ruling removed.

    /// A tree first photographed this year is on record for zero years, and §5.6 does not draw a
    /// zero.
    static let minimumYearsOnRecord = 1

    /// §4 draws three tiles.
    static let stripCells = 3

    // MARK: Margins

    /// C23: `margin:10px 16px 0`.
    static let chartTop: CGFloat = 10
    /// §2: each legend line sits above its bar row; `VStack` gap between the three groups.
    static let legendGap: CGFloat = 6
    static let seriesGap: CGFloat = 8
    /// §3: `VStack(spacing:7)` under the micro-label, as 12's season block.
    static let momentGap: CGFloat = CypressSpacing.gapDense
    /// §4: `gap:8px`, each tile `flex:1`, height 88, radius 12.
    static let stripGap: CGFloat = CypressSpacing.gapRows
    static let stripHeight: CGFloat = 88
    /// §4's chip: `padding:2px 7px`, radius 6, inset 8 from the tile's bottom-left corner.
    static let stripChipPaddingV: CGFloat = 2
    static let stripChipPaddingH: CGFloat = 7
    static let stripChipInset: CGFloat = 8
    /// §4's current-week tile: `border:2px solid #2F6B4F`.
    static let stripCurrentBorder: CGFloat = 2
    /// §5: `padding:16px 24px 36px`.
    static let footnoteTop: CGFloat = 16
    static let footnotePaddingH: CGFloat = 24
}
