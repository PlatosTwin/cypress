//
//  AlmanacPresentation.swift
//  Cypress — Features/Almanac
//
//  Screen 12 · Neighborhood almanac. SCREENS.md lines 1053–1091.
//
//  This screen is the one D1 was written to produce. The leaderboard was killed because ranked
//  counts are farmable, and the almanac is the replacement: it "notices trees instead of scoring
//  people" (PRODUCT §3). Everything below is decided by two rules and one absence.
//
//  - **ARCHITECTURE §5.6 / A9 — an aggregate below its threshold does not render at all.** Not a
//    zero, not a placeholder, not a grayed-out card. This file is where that happens, and it is
//    almost the whole file: every block on the screen is an optional and every optional is nil for
//    a reason it can state. The screen a fresh install draws is the proof, not the exception.
//  - **ARCHITECTURE §5.1 / D1 — no counts of user actions, no ranks, no leaderboards.** The numbers
//    here count trees. The one number that counts people is A8's, and it is floored at three.
//  - **The absence: nobody's name appears anywhere**, because the payload carries none (D11,
//    DECISIONS §3.11). The almanac cannot become a way to see what one person did, because it
//    cannot see one person at all.
//
//  No SwiftUI in this file, so all of the above is testable without a renderer
//  (`CypressTests/AlmanacPresentationTests.swift`).
//

import Foundation

// MARK: - Presentation

/// Everything screen 12 renders, derived from one `Almanac` payload.
struct AlmanacPresentation: Equatable {

    /// One C10 row of §2's "This season" block.
    struct SeasonRow: Equatable, Identifiable {
        enum Kind: String { case bloom, elder, newestNeighbors }

        let kind: Kind
        let accent: CypressColor.TileAccent
        /// §2's drawn titles, verbatim.
        let title: String
        let subtitle: String
        /// The tree this row is about, when it is about one. The elder and the first bloom are both
        /// a specific tree; "newest neighbors" is a group and has none.
        let treeID: UUID?

        /// The group this row is about, when it is about a group (ERRATA **E182**).
        ///
        /// Exactly one of `treeID` and `group` is ever set, because a row either names one record or
        /// counts several and those take different destinations — a profile and a map. `Newest
        /// neighbors` is the only row of the second kind in §2, and until the owner reported it as
        /// going nowhere it was the only counted row on the whole screen with no destination at all.
        let group: PinSet?

        /// The photograph this row draws instead of the accent tile, when the tree it names has
        /// one on this device (#176). Always `nil` for `newestNeighbors`, which names a group
        /// rather than a tree.
        let heroPhotoID: UUID?

        var id: String { kind.rawValue }
    }

    /// One row of §3's composition card.
    struct CompositionRow: Equatable, Identifiable {
        let id: String
        let name: String
        /// 0…1, the width of the filled part of the track.
        let share: Double
        /// `18%`, mono.
        let value: String
        /// Which of §3's four swatches this row draws — an index into
        /// `CypressColor.compositionSwatches`, so the feature holds no color of its own.
        let swatchIndex: Int
        /// The `Everyone else` row draws its name in `text.muted` rather than in ink (§3).
        let isRemainder: Bool
    }

    /// §3's whole block, which only exists when there is a mix to state.
    struct Composition: Equatable {
        /// `Who lives here · 64 species`.
        let label: String
        let rows: [CompositionRow]
    }

    /// Screen 12's `Where a tree could go` block (RULINGS R10). One C10 row, a plain statement of
    /// how many basins are empty, tapping through to a map of the nearest of them.
    struct VacantBlock: Equatable {
        /// `Where a tree could go` — the micro-label, ROADMAP §1's own phrase for these rows.
        let label: String
        /// `1,474 empty planting sites`.
        let title: String
        /// Inherits `SitePresentation`'s line and may not cross it: the city mapped them, nothing is
        /// growing, and Cypress does not plant.
        let subtitle: String
        /// The group the row is counting, for a screen that shows them together (ERRATA E129).
        ///
        /// It was a single `nearestID` — a `Route.site` — and that is the defect. A row that says
        /// `1,474 empty planting sites` and opens one basin has answered a question nobody asked;
        /// the question a count of places raises is *where*.
        let group: PinSet
    }

    /// §4's amber card.
    struct Coverage: Equatable {
        /// `9 young trees with no visits since planting`.
        let title: String
        /// `All nine are within a 15-minute walk.` — present only when it is true, nil otherwise.
        ///
        /// This was a two-sentence body until the copy audit of 2026-08-23, whose owner ruling
        /// killed the opening sentence ("The first two summers decide whether a street tree makes
        /// it.") as an unattributed arboricultural claim. What is left is the checked half, and the
        /// checked half is sometimes absent — hence the optional.
        let body: String?
        /// `Walk the nine`.
        let ctaTitle: String

        /// Where the CTA goes: **all nine of them, on a map** (ERRATA E129).
        ///
        /// It used to be `firstTreeID`, one tree, and the justification was screen 14's own footnote
        /// calling itself "the almanac's 'walk the nine' list, one tree at a time". What that
        /// footnote could not do is stand in for a destination: the button says `Walk the nine`, and
        /// a walk is a route between places, so a screen showing one place was never it. The
        /// footnote itself was removed by the copy audit of 2026-08-23 (owner ruling), so this is
        /// now the whole account of why the CTA goes where it goes.
        let group: PinSet
    }

    /// The trailing pill on C1 — the area's name for a polygon, the stated distance for the
    /// fallback, and nil when there is no area at all (RULINGS **R29**).
    ///
    /// The two are different promises and the pill says which one is being made: `Sunset/Parkside`
    /// is a place, `Within a 15-minute walk` is a measurement. Nothing here ever invents a place
    /// name for an area the record does not name.
    let neighborhoodName: String?

    /// Whether the read resolved an area at all (ERRATA **E182**).
    ///
    /// Distinct from `isEmpty`, which is about a resolved area with nothing to say, and distinct
    /// from `presentation == nil`, which is a read still in flight or one that failed. Screen 12
    /// has four ways of having nothing on it and they mean four different things; this is the one
    /// that means "the inventory does not reach where you are standing".
    let hasArea: Bool

    /// The line that explains the fallback area, or nil for a named one (RULINGS **R29**).
    ///
    /// **NOT SPECIFIED** — SCREENS.md 12 draws one area and gives it a name. A pill on its own is
    /// too quiet to carry this: a reader who has only ever seen `Sunset/Parkside` there has no way
    /// to know that `Within a 15-minute walk` is a different kind of thing rather than an oddly
    /// named neighborhood. The sentence says what changed and, by naming what is missing, what would
    /// change it back.
    let areaNote: String?

    let seasonRows: [SeasonRow]

    /// The line under §2's micro-label saying what determines the rows below it (task #177).
    ///
    /// **NOT SPECIFIED** — SCREENS.md 12 §2 draws the heading and the rows and nothing between
    /// them. `AlmanacCopy.seasonNote` has what it says and why `This season` is not a filter, so
    /// R41 does not reach it. `nil` exactly when `seasonRows` is empty, because the block does not
    /// draw at all then and a note explaining three absent rows is the heading-over-nothing defect
    /// that `AlmanacView.seasonBlock` already guards against.
    let seasonNote: String?

    let composition: Composition?
    let coverage: Coverage?
    let vacantSites: VacantBlock?

    // §5's footnote was removed by the copy audit of 2026-08-23; see `AlmanacCopy`. On a device
    // with no location it was the only thing on the screen; the location prompt now is.

    /// Whether anything at all sits below the header.
    ///
    /// **NOT SPECIFIED.** SCREENS.md 12 draws one state, the full one. What an almanac with nothing
    /// in it looks like is not drawn anywhere, and it is the state most devices are in: no seeded
    /// tree carries an observation or a photo, so the bloom row has nothing behind it, and a device
    /// with no location fix has no neighborhood at all. What was built is the restrained reading —
    /// each block derives from data and a block with no data behind it is absent (§5.6) — leaving
    /// the screen's own chrome. See ERRATA.
    var isEmpty: Bool { seasonRows.isEmpty && composition == nil && coverage == nil && vacantSites == nil }

    // MARK: - Derivation

    init(almanac: Almanac, now: Date = .now, calendar: Calendar = .current, locale: Locale = .current) {
        guard let area = almanac.neighborhood else {
            self.hasArea = false
            self.neighborhoodName = nil
            self.areaNote = nil
            self.seasonRows = []
            self.seasonNote = nil
            self.composition = nil
            self.coverage = nil
            self.vacantSites = nil
            return
        }

        // The one string every block hands its destination for the header pill. For a polygon it is
        // the city's own name; for the fallback it is the distance, because `PinSet` documents that
        // an area we could not name must not be named and a measurement is not a name (R29).
        let pill = AlmanacCopy.areaPill(area.area, locale: locale)
        self.hasArea = true
        self.neighborhoodName = pill
        self.areaNote = AlmanacCopy.areaNote(area.area, locale: locale)
        let rows = Self.seasonRows(area, in: pill, now: now, calendar: calendar, locale: locale)
        self.seasonRows = rows
        self.seasonNote = AlmanacCopy.seasonNote(kinds: rows.map(\.kind), calendar: calendar, locale: locale)
        self.composition = Self.composition(area.composition, locale: locale)
        self.coverage = Self.coverage(area.coverage, in: pill, locale: locale)
        self.vacantSites = Self.vacantSites(area.vacantSites, in: pill, locale: locale)
    }

    // MARK: - §2 This season

    /// The three C10 rows, in SCREENS.md's order, each present only if its subject is.
    ///
    /// A9 names the floors this block answers to: "bloom sightings need 1". The other two are city
    /// data and their floor is the same one: one elder, one newly planted tree. Below that there is
    /// nothing to notice, and the almanac's whole job is noticing.
    private static func seasonRows(
        _ area: AlmanacNeighborhood,
        in areaName: String,
        now: Date,
        calendar: Calendar,
        locale: Locale
    ) -> [SeasonRow] {
        var rows: [SeasonRow] = []

        if let bloom = area.firstBloom {
            rows.append(
                SeasonRow(
                    kind: .bloom,
                    accent: .bloom,
                    title: AlmanacCopy.bloomTitle,
                    subtitle: AlmanacCopy.bloomSubtitle(
                        species: bloom.speciesCommonName,
                        street: AlmanacCopy.street(from: bloom.address),
                        seenAt: bloom.firstSeenAt,
                        observers: bloom.observerCount,
                        calendar: calendar,
                        locale: locale
                    ),
                    treeID: bloom.treeID,
                    group: nil,
                    heroPhotoID: bloom.heroPhotoID
                )
            )
        }

        if let elder = area.elder {
            rows.append(
                SeasonRow(
                    kind: .elder,
                    accent: .elder,
                    title: AlmanacCopy.elderTitle,
                    subtitle: AlmanacCopy.elderSubtitle(
                        name: elder.activeName,
                        species: elder.speciesCommonName,
                        street: AlmanacCopy.street(from: elder.address),
                        plantedYear: elder.plantedYear
                    ),
                    treeID: elder.treeID,
                    group: nil,
                    heroPhotoID: elder.heroPhotoID
                )
            )
        }

        if let planted = area.newestNeighbors, planted.treeCount > 0 {
            let sentence = AlmanacCopy.newestSubtitle(
                treeCount: planted.treeCount,
                leadingSpecies: planted.leadingSpecies,
                locale: locale
            )
            rows.append(
                SeasonRow(
                    kind: .newestNeighbors,
                    accent: .newGrowth,
                    title: AlmanacCopy.newestTitle,
                    subtitle: sentence,
                    treeID: nil,
                    // The row counts trees, so it goes where the other two counted rows go
                    // (ERRATA E182, the owner's report). Absent rather than inert when the read
                    // returned no pins: a row that looks pressable and answers nothing is the
                    // defect being fixed, not a smaller version of it.
                    group: planted.nearest.isEmpty ? nil : PinSet(
                        subject: .newestNeighbors(sentence: sentence),
                        pins: planted.nearest,
                        count: planted.treeCount,
                        neighborhoodName: areaName
                    ),
                    heroPhotoID: nil
                )
            )
        }

        return rows
    }

    // MARK: - §3 Who lives here

    /// The composition card: the three most common species, then everyone else.
    ///
    /// **The remainder is what makes the read have to be whole.** `Everyone else` is one minus the
    /// three shares above it, so a card built from a partial read would put the missing trees into
    /// the named species and overstate them. `NeighborhoodComposition` is only ever built from a
    /// complete `speciesMix`, and this is the reason.
    ///
    /// Percentages are rounded for display and the remainder is computed from the *unrounded*
    /// shares, so the four numbers on screen can be off by a point from summing to 100 but no
    /// species is ever credited with a tree it does not have. Displaying a remainder that had been
    /// derived from rounded values would be the opposite trade.
    ///
    /// **Not `private`.** `CityPresentation` reuses this verbatim for card 2 of the City segment —
    /// same remainder discipline, same input shape (`NeighborhoodComposition`), scoped to a whole
    /// `id_space` instead of a neighborhood. Two composition cards computing "everyone else"
    /// differently is exactly the drift this sharing avoids.
    static func composition(_ composition: NeighborhoodComposition?, locale: Locale) -> Composition? {
        guard let composition, composition.treeCount > 0, !composition.leading.isEmpty else { return nil }

        let total = Double(composition.treeCount)
        let named = composition.leading.prefix(AlmanacMetrics.compositionNamedRows)
        var rows = named.enumerated().map { index, species in
            CompositionRow(
                id: species.speciesID.uuidString,
                name: species.name,
                share: Double(species.treeCount) / total,
                value: AlmanacCopy.percent(Double(species.treeCount) / total, locale: locale),
                swatchIndex: index,
                isRemainder: false
            )
        }

        let namedShare = named.reduce(0.0) { $0 + Double($1.treeCount) / total }
        let remainder = max(1 - namedShare, 0)
        // Only when there is a remainder to name. A neighborhood whose whole inventory is three
        // species has no "everyone else", and drawing a 0% row would be the zero §5.6 forbids.
        if composition.leading.count > named.count {
            rows.append(
                CompositionRow(
                    id: "everyone-else",
                    name: AlmanacCopy.everyoneElse,
                    share: remainder,
                    value: AlmanacCopy.percent(remainder, locale: locale),
                    swatchIndex: CypressColor.compositionSwatches.count - 1,
                    isRemainder: true
                )
            )
        }

        return Composition(
            label: AlmanacCopy.compositionLabel(speciesCount: composition.distinctSpeciesCount, locale: locale),
            rows: rows
        )
    }

    // MARK: - §4 Where eyes are needed

    /// The amber card, and the app's only directed ask (D1).
    ///
    /// A9 says the coverage panel "always renders", and two cases still remove it, both of which are
    /// A9 and §5.6 agreeing rather than disagreeing:
    ///
    /// - **The read came back a page.** The card is a number and a page's size is not a total
    ///   (ERRATA E38). A card that says "200 young trees" when the true figure is unknown is worse
    ///   than no card.
    /// - **There are none.** `0 young trees with no visits since planting` under the heading
    ///   `Where eyes are needed` is precisely the zero §5.6 forbids, and the card's job — sending
    ///   somebody to walk somewhere — has nowhere to send them. Recorded in ERRATA, because A9's
    ///   sentence and §5.6 read differently at exactly this value.
    private static func coverage(_ coverage: CoverageGap?, in area: String, locale: Locale) -> Coverage? {
        guard let coverage,
              let count = coverage.trees.totalCount,
              count > 0,
              !coverage.trees.items.isEmpty
        else { return nil }

        // §4's second sentence is a claim about walking distance, so it is checked rather than
        // asserted: it renders only when every tree on the list really is inside the radius.
        let farthest = coverage.trees.items.map(\.distanceM).max() ?? 0
        let allWithinWalk = farthest <= AlmanacMetrics.walkRadiusM

        return Coverage(
            title: AlmanacCopy.coverageTitle(count: count, locale: locale),
            body: AlmanacCopy.coverageBody(count: count, allWithinWalk: allWithinWalk, locale: locale),
            ctaTitle: AlmanacCopy.coverageCTA(count: count, locale: locale),
            // Every tree the card counted, and `count` is `Series.totalCount` — nil unless the read
            // was whole, which is why this card draws at all. So the map holds the same nine the
            // title names, and `PinSet.isComplete` is true here by the same proof (ERRATA E38).
            group: PinSet(
                subject: .coverageGap,
                pins: coverage.trees.items.map(\.pin),
                count: count,
                neighborhoodName: area
            )
        )
    }

    /// §-new: `Where a tree could go` (RULINGS R10). A count and a destination, or nothing.
    ///
    /// Absent when the neighborhood holds no sites — which E115 measured as nowhere in the city, but
    /// §5.6 is a rule about the general case — and absent when there is nowhere to send the tap, so
    /// the row is never a statement the reader cannot act on.
    private static func vacantSites(_ sites: VacantSites?, in area: String, locale: Locale) -> VacantBlock? {
        guard let sites, sites.count > 0, !sites.nearest.isEmpty else { return nil }
        return VacantBlock(
            label: AlmanacCopy.vacantLabel,
            title: AlmanacCopy.vacantTitle(count: sites.count, locale: locale),
            subtitle: AlmanacCopy.vacantSubtitle,
            // The count is the neighborhood's; the pins are the nearest page of it. The two are
            // different numbers on purpose and the destination prints both, because a map of 1,474
            // basins is not available at any zoom a person can read (ERRATA E38, E129).
            group: PinSet(
                subject: .vacantSites,
                pins: sites.nearest,
                count: sites.count,
                neighborhoodName: area
            )
        )
    }
}

// MARK: - Thresholds

/// The cold-start floors screen 12 holds (ARCHITECTURE §5.6, A8, A9).
///
/// Named rather than inlined because "which number does this surface need before it may speak" is
/// the single thing this screen is about, and a threshold buried in an `if` is a threshold nobody
/// reviews.
enum AlmanacThresholds {

    /// **A8, applied to §2's `three neighbors saw it` clause.** "Distinct users with 2 or more
    /// care_events or observations on the tree in 24 months; shown only when 3 or more" — the floor
    /// that stops a headcount on a public surface from being a headcount of one identifiable person.
    /// Below it the clause is dropped and the rest of the row still draws, because A9 floors the
    /// *sighting* at one and the *headcount* is a separate claim.
    static let minimumObservers = 3

    /// **A9, verbatim: "bloom sightings need 1".** One sighting is a first bloom; none is not a
    /// smaller first bloom. Enforced by `Almanac.firstBloom` being nil when no visit carries
    /// `flowering`, so there is no code path that could render a zero here.
    static let minimumBloomSightings = 1

    /// §4's card is a count, and a count of none is nothing to attend to.
    static let minimumCoverageTrees = 1
}

// MARK: - Copy

/// Screen 12's strings, verbatim from SCREENS.md including its typographic characters.
///
/// Every sentence with a number in it is assembled rather than templated wholesale, so that the
/// parts which are not true can be left out instead of being written in a smaller font.
enum AlmanacCopy {

    /// §1's title.
    static let screenTitle = "Almanac"

    // §5's footnote — `No ranks, no counters. The almanac notices trees, not scores.` — was removed
    // by the copy audit of 2026-08-23 (owner ruling: the footnote slot is a demo-era artifact and
    // comes out of every screen that had one). SCREENS.md 12 §5 is struck to match. Do not restore
    // it from the mock; the mock is the thing that was ruled against.

    /// §2's micro-label.
    static let seasonLabel = "This season"

    /// §2's three drawn titles, verbatim.
    static let bloomTitle = "First bloom of the year"
    static let elderTitle = "The elder"
    static let newestTitle = "Newest neighbors"

    // MARK: §2's note — what actually determines what is under this heading (task #177)

    /// The line under `This season`, assembled from the rows that actually drew.
    ///
    /// **NOT SPECIFIED**; the decision is
    /// `RULINGS R49`, which also records why R41 does not reach
    /// this. R41 forbids any message accompanying a **filter**, categorically. `This season` is a
    /// static micro-label over a content block: there is no chip, no selection, no state, and
    /// nothing here appears *because a filter did something* — R41's own test. E205 confirms the
    /// scope by showing what R41 did reach, which was chrome on the map beside the chip row.
    ///
    /// ── What the heading is actually over, which is three different clocks ────────────────────
    /// Read from the code rather than from the heading:
    /// - **first bloom** — `captured_at >= AlmanacWindow.yearStart`, so it is year-to-date, not
    ///   this season, and in December it is still March's sighting. Its own title says
    ///   `of the year`, so it is the one row whose drawn copy already admits its clock.
    /// - **the elder** — `ORDER BY planted_on LIMIT 1` with **no window at all**. It is the same
    ///   tree in January and in July, every year. Nothing about it is seasonal.
    /// - **newest neighbors** — `planted_on BETWEEN` `AlmanacWindow.currentSpring`, a fixed
    ///   March–May window of the current year that keeps drawing, still saying `planted this
    ///   spring`, until the year ends.
    ///
    /// So none of the three is scoped to the current season, and the honest sentence says so
    /// rather than dressing the heading up. The months are read from `AlmanacWindow.springMonths`
    /// and the reader's own calendar, so the sentence cannot drift from the window it describes.
    ///
    /// Assembled from the drawn rows, never templated whole — this enum's own rule, so a clause
    /// about a row that is not on screen is never written.
    static func seasonNote(
        kinds: [AlmanacPresentation.SeasonRow.Kind],
        calendar: Calendar,
        locale: Locale
    ) -> String? {
        guard !kinds.isEmpty else { return nil }

        let clauses: [String] = kinds.map { kind in
            switch kind {
            case .bloom:
                return "the first bloom is this year's earliest"
            case .elder:
                return "the elder is the oldest on file in any season"
            case .newestNeighbors:
                return "the newest neighbors were planted \(springSpan(calendar: calendar, locale: locale))"
            }
        }

        // One row makes no claim about differing windows; it just states its own.
        guard clauses.count > 1 else { return sentence(clauses[0]) }

        let joined = clauses.dropLast().joined(separator: ", ") + ", and " + clauses[clauses.count - 1]
        return "Each row keeps its own window: \(joined)."
    }

    /// `March to May`, from the constant the read is actually scoped to.
    ///
    /// **The locale is applied to the calendar rather than taken from it**, which the red-proof for
    /// this note caught: `Calendar.standaloneMonthSymbols` reads the *calendar's* own locale, and a
    /// calendar constructed as `Calendar(identifier: .gregorian)` carries none, so the months came
    /// out as `M03 to M05`. Every other sentence in this enum already takes the reader's locale as
    /// its own parameter; this one now does too, instead of hoping the two agree.
    private static func springSpan(calendar: Calendar, locale: Locale) -> String {
        var calendar = calendar
        calendar.locale = locale
        let names = calendar.standaloneMonthSymbols
        let first = AlmanacWindow.springMonths.lowerBound
        let last = AlmanacWindow.springMonths.upperBound
        guard (1...names.count).contains(first), (1...names.count).contains(last) else {
            return "in spring"
        }
        return "\(names[first - 1]) to \(names[last - 1])"
    }

    /// Capitalizes a clause written to sit mid-sentence and closes it.
    private static func sentence(_ clause: String) -> String {
        guard let first = clause.first else { return clause }
        return first.uppercased() + clause.dropFirst() + "."
    }

    /// §3's fourth row, verbatim.
    static let everyoneElse = "Everyone else"

    /// §4's micro-label, verbatim. Drawn in amber, which is the whole point of C24.
    static let coverageLabel = "Where eyes are needed"

    // MARK: Where a tree could go (R10, ERRATA E121)

    /// The block's micro-label — ROADMAP §1's own phrase for these rows, chosen over anything with
    /// `needed` or `gap` in it because this is a statement, not the §4 ask.
    static let vacantLabel = "Where a tree could go"

    /// `1,474 empty planting sites`. Counts city records, so no A8 floor and no `at least` hedge.
    static func vacantTitle(count: Int, locale: Locale) -> String {
        count == 1
            ? "1 empty planting site"
            : "\(grouped(count, locale: locale)) empty planting sites"
    }

    /// Inherits `SitePresentation`'s two-part line — the city holds the record, nothing is growing —
    /// and stops exactly where the site screen does. It does not say `yet`, does not ask anyone to
    /// plant, and does not imply anyone has been told (ARCHITECTURE §5.4). Cypress keeps the record
    /// of what is planted; it does not plant.
    static let vacantSubtitle = "The city has mapped them. Nothing is growing there."

    // MARK: Turn on location (R11 residual, E123)

    /// American spelling, at the owner's explicit instruction. The screen's own name in SCREENS.md
    /// has always been `Neighborhood almanac`; this string was the one place on it that disagreed.
    /// The codebase-wide sweep is somebody else's ticket and is deliberately not started here.
    static let locationPromptTitle = "See your neighborhood"
    static let locationPromptSubtitle = "Turn on location and the almanac fills with the trees around you."

    // MARK: The area this almanac is about (RULINGS R29)

    /// C1's trailing pill, and the string every block hands its destination.
    ///
    /// **A name for a polygon, a distance for the fallback, and never a name invented for a
    /// distance.** The whole of R29 is that "the Mission" and "everything within a 15-minute walk"
    /// are different promises; a pill reading `Your area` would make the smaller promise while
    /// looking like the larger one, which is the failure this copy exists to avoid.
    ///
    /// The fallback reads as a walk rather than as meters because the screen already has a unit for
    /// this distance — §4's body says "within a 15-minute walk" of the same 1,200 m — and a reader
    /// who is being told how far the almanac reaches is better served by the time it takes to cross
    /// it than by a number they have to convert.
    static func areaPill(_ area: AlmanacArea, locale: Locale) -> String {
        switch area {
        case let .named(name): return name
        case .radius: return "Within a 15-minute walk"
        }
    }

    /// The sentence under the header that explains a fallback area, or nil for a named one.
    ///
    /// **NOT SPECIFIED**; see `AlmanacPresentation.areaNote`. Three things had to be in it and
    /// nothing else: that this almanac is drawn around the reader rather than around a place, why,
    /// and — D16(b)'s rule, that an honest empty state must say what *would* happen rather than only
    /// what does not — what would give it a place back. It never names the city. The app does not
    /// know which city a coordinate is in; it knows only that no boundary in the record contains it,
    /// and saying more than that would be the screen guessing.
    static func areaNote(_ area: AlmanacArea, locale: Locale) -> String? {
        guard case .radius = area else { return nil }
        return "No neighborhood boundaries are on file for where you are, so this almanac is drawn "
            + "around you instead. It will name a neighborhood once this city's boundaries join the record."
    }

    // MARK: Nowhere the record reaches (ERRATA E182)

    /// The screen a reader gets when the fix is good, the read finished, and the merged inventory
    /// simply does not cover where they are standing.
    ///
    /// This is the state San Jose was in before R29 and that everywhere outside two cities is still
    /// in, and until now it drew **nothing**: header, footnote, and an empty column between them —
    /// pixel for pixel the screen a reader sees while the read is still in flight. That is E126's
    /// defect on a different cause, on the screen E126 itself calls the last place to conflate
    /// states, and it is the half of this ticket that had to land whatever was decided about
    /// geography.
    ///
    /// The copy is D16's shape, not an apology. It says what the almanac is made of, that the record
    /// does not reach here, and what would change that — because a dead end that explains itself is
    /// still a dead end unless it says which way the door opens.
    static let outOfRangeTitle = "No inventory reaches here yet."
    static let outOfRangeBody = "The almanac is built from city tree inventories, and none of the "
        + "ones on this phone covers where you are. It fills in as more cities join the record."

    // MARK: The read that did not arrive (ERRATA E126)

    /// **NOT SPECIFIED** by SCREENS.md 12, which draws no error state.
    ///
    /// It says the almanac could not be read, and says nothing at all about the neighborhood —
    /// which is the distinction `AlmanacModel.Phase` exists to keep, and the one this screen can
    /// least afford to lose, its whole subject being what is and is not out there. A screen that
    /// draws its five blocks away and leaves a footnote is reporting a quiet neighborhood; that
    /// report has to be earned by a read that finished.
    static let loadFailed = "This almanac could not be loaded."
    static let loadRetry = "Try again"

    // MARK: §2 row 1 — the first bloom

    /// `Red flowering gum on 44th Ave · Jan 22, three neighbors saw it`.
    ///
    /// Four clauses, three of which can be missing, and each is simply left out when it is:
    /// - the **species**, for the 312 trees whose city label names no taxon (ERRATA E14);
    /// - the **street**, when the city recorded no address;
    /// - the **headcount**, below A8's floor of three — the sighting is still a first bloom, it just
    ///   stops saying how many people were there. That is A8 doing its job rather than a degraded
    ///   string: at one or two, naming the number on a surface that also names the tree and the day
    ///   comes close to naming the person (D11).
    ///
    /// The date is the only clause that is always present, because the sighting is the date.
    static func bloomSubtitle(
        species: String?,
        street: String?,
        seenAt: Date,
        observers: Int,
        calendar: Calendar,
        locale: Locale
    ) -> String {
        var head = species ?? ""
        if let street {
            head += head.isEmpty ? "On \(street)" : " on \(street)"
        }

        var tail = shortDate(seenAt, calendar: calendar, locale: locale)
        if observers >= AlmanacThresholds.minimumObservers {
            let people = spelledOut(observers, locale: locale)
            tail += ", \(people) neighbors saw it"
        }

        return head.isEmpty ? tail : "\(head) · \(tail)"
    }

    // MARK: §2 row 2 — the elder

    /// `Grandmother Cypress · in the city record since 1898`.
    ///
    /// **"In the city record since" is load-bearing and is kept word for word.** DataSF fills
    /// `PlantDate` on 70,067 of 195,309 rows, so this is the oldest tree whose planting the city
    /// wrote down — not the oldest tree. The mock's phrasing happens to say precisely that, which is
    /// the only reason a year the record only partly knows can go on screen at all.
    ///
    /// The name is the tree's own if it has been named (D15), then its species' common name, then
    /// the street. Nothing is invented for a tree that has none of the three: it reads as the
    /// sentence alone.
    static func elderSubtitle(name: String?, species: String?, street: String?, plantedYear: Int) -> String {
        let record = "in the city record since \(year(plantedYear))"
        guard let subject = name ?? species ?? street.map({ "The tree on \($0)" }) else { return record }
        return "\(subject) · \(record)"
    }

    // MARK: §2 row 3 — newest neighbors

    /// `23 trees planted this spring, mostly ginkgo and tea tree`.
    ///
    /// **The `mostly` clause needs two trees to be true of.** One tree is not "mostly" anything, so
    /// at a count of one the sentence stops after the season. Two names at most, because the mock
    /// draws two and a list of nine species is not a characterization. **NOT SPECIFIED** — §2 gives
    /// one instance of this string and no rule; see ERRATA.
    ///
    /// **The names are the record's, capitalization and all.** The mock writes `mostly ginkgo and
    /// tea tree` in lower case, mid-sentence, which is right for those two words and wrong for the
    /// seed: its common names are title case and include proper nouns and initialisms, so
    /// lower-casing turns `NZ tea tree` into `nz tea tree` and `New Zealand Xmas Tree` into a
    /// sentence about a place that is not capitalized. Deciding which words inside a name may be
    /// lowered is deciding what kind of word each one is, and getting that wrong renames a species
    /// (the same reasoning that keeps `AlmanacCopy.street(from:)` from stripping a street type).
    static func newestSubtitle(treeCount: Int, leadingSpecies: [String], locale: Locale) -> String {
        let trees = treeCount == 1 ? "1 tree" : "\(grouped(treeCount, locale: locale)) trees"
        var sentence = "\(trees) planted this spring"

        let named = leadingSpecies.prefix(2)
        if treeCount > 1, !named.isEmpty {
            sentence += ", mostly \(named.joined(separator: " and "))"
        }
        return sentence
    }

    // MARK: §3 — who lives here

    /// `Who lives here · 64 species`.
    static func compositionLabel(speciesCount: Int, locale: Locale) -> String {
        "Who lives here · \(grouped(speciesCount, locale: locale)) species"
    }

    /// `18%`. Rounded to the nearest point; a species that is present but rounds to nothing reads
    /// `<1%` rather than `0%`, because it is not absent and the row is drawn.
    static func percent(_ share: Double, locale: Locale) -> String {
        let points = (share * 100).rounded()
        if points < 1, share > 0 { return "<1%" }
        return "\(Int(points))%"
    }

    // MARK: §4 — where eyes are needed

    /// `9 young trees with no visits since planting`.
    static func coverageTitle(count: Int, locale: Locale) -> String {
        let trees = count == 1 ? "1 young tree" : "\(grouped(count, locale: locale)) young trees"
        return "\(trees) with no \(count == 1 ? "visit" : "visits") since planting"
    }

    /// `All nine are within a 15-minute walk.` — or nothing at all.
    ///
    /// **The opening sentence is gone, and this returns nil where it used to stand alone.** SCREENS
    /// 12 §4 wrote the body as two sentences, the first being `The first two summers decide whether
    /// a street tree makes it.` That is an arboricultural claim the app cannot source, which
    /// DECISIONS constraint 15 forbids inventing; the copy audit of 2026-08-23 killed it by owner
    /// ruling and struck the line from SCREENS.md.
    ///
    /// What remains is a claim about where the reader is standing, so it is only written when it has
    /// been checked — see `AlmanacPresentation.coverage`. A sentence that is drawn whether or not it
    /// is true is not copy, it is decoration. When it has not been checked the card now draws its
    /// title and its button and no body, rather than falling back to a sentence about summers.
    static func coverageBody(count: Int, allWithinWalk: Bool, locale: Locale) -> String? {
        guard allWithinWalk else { return nil }
        let subject = count == 1 ? "It is" : "All \(spelledOut(count, locale: locale)) are"
        return "\(subject) within a 15-minute walk."
    }

    /// `Walk the nine`. One tree reads `Walk to it`, because "walk the one" is not a sentence.
    static func coverageCTA(count: Int, locale: Locale) -> String {
        count == 1 ? "Walk to it" : "Walk the \(spelledOut(count, locale: locale))"
    }

    // MARK: - Numbers and dates

    /// `three`, `nine`, `seventeen`.
    ///
    /// The mock spells its people counts and its walk counts out (`three neighbors saw it`, `All
    /// nine`, `Walk the nine`), as SCREENS.md 13 does ("six people know this tree", "four
    /// visitors"). The formatter does the spelling rather than a table of my own words, so a reader
    /// in another language gets their own and nobody's number ends up in a list I stopped writing
    /// at ten.
    static func spelledOut(_ value: Int, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        formatter.locale = locale
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    /// `1,204`. Grouping is the formatter's, so a reader in a locale that groups differently sees
    /// their own separator.
    static func grouped(_ value: Int, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    /// `Jan 22`. A day inside the current year, which is what "first bloom of the year" is about, so
    /// the year is not repeated. Prose dates elsewhere read "Summer 2026" (ARCHITECTURE §5.7); this
    /// is the mock's own shorter form for a specific day.
    static func shortDate(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter.string(from: date)
    }

    /// `1898`. A year is an identifier, not a quantity, so it never takes a grouping separator.
    static func year(_ value: Int) -> String { String(value) }

    /// `1450 Noriega St` → `Noriega St`.
    ///
    /// The same rule `GroveCopy.street(from:)` applies, for the same two reasons: the mock writes
    /// `on 44th Ave` without a house number, and stripping a street *type* means deciding which
    /// trailing words are types, which renames a street when you get it wrong. Dropping the leading
    /// number is unambiguous, and it is the part that would otherwise put a specific doorway into a
    /// sentence read by anybody standing nearby (DECISIONS §3.11's principle).
    ///
    /// A leading number is only dropped when something remains: `44th Ave` keeps its `44th`, because
    /// that token is the street's name rather than a house number.
    static func street(from address: String?) -> String? {
        guard let address else { return nil }
        let trimmed = address.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        var parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
        if parts.count > 1, parts[0].allSatisfy(\.isNumber) {
            parts.removeFirst()
        }
        let street = parts.joined(separator: " ")
        return street.isEmpty ? nil : street
    }
}

// MARK: - Screen metrics

/// The geometry SCREENS.md gives screen 12 that `CypressSpacing` does not already name.
///
/// Same arrangement as `GroveMetrics`: screen-specific numbers are named once here so the view body
/// carries no loose values, while every color, font and radius stays a `DesignSystem` token
/// (ARCHITECTURE §6).
enum AlmanacMetrics {
    /// §3 draws three named species above the remainder.
    static let compositionNamedRows = 3

    /// How far §4's `within a 15-minute walk` reaches.
    ///
    /// 15 minutes at 4.8 km/h — the walking speed transport planning uses for a "15-minute
    /// neighborhood" — is 1,200 m. **NOT SPECIFIED**: the mock states the claim and no source
    /// states the distance behind it, so the number is named here and recorded in ERRATA rather than
    /// buried in a comparison. It is used to *withhold* a sentence, never to select trees, so
    /// getting it slightly wrong costs a true sentence rather than producing a false one.
    static let walkRadiusM: Double = 1_200

    /// §2: `VStack(spacing:7)` under the micro-label.
    static let seasonRowGap: CGFloat = CypressSpacing.gapDense

    /// §3: card `padding:14px 16px`, `VStack(spacing:9)`.
    static let compositionPaddingV: CGFloat = 14
    static let compositionPaddingH: CGFloat = CypressSpacing.gutter
    static let compositionRowGap: CGFloat = 9
    /// §3: 11×11 swatch, 9pt track.
    static let compositionSwatch: CGFloat = 11
    static let compositionTrackHeight: CGFloat = 9
    /// **NOT SPECIFIED** — §3 gives the row its parts and no gap between them. 8 is `gapRows`, the
    /// spacing every other in-card row rhythm in the app uses.
    static let compositionRowSpacing: CGFloat = CypressSpacing.gapRows

    /// §4: title, then body `margin:4px 0 12px`, then the CTA.
    ///
    /// `coverageBodyBottom` is also the gap the CTA takes when there is no body to sit under — see
    /// `AlmanacView.coverageBlock`, and `AlmanacCopy.coverageBody` for when that happens.
    static let coverageBodyTop: CGFloat = 4
    static let coverageBodyBottom: CGFloat = 12

    // §5's footnote metrics (`padding:16px 18px 36px`, `margin-top:auto`) went with the footnote
    // itself in the copy audit of 2026-08-23. `CityView` drew its own footnote with them and no
    // longer draws one either.
}
