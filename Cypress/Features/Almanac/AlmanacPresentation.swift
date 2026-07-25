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
//    zero, not a placeholder, not a greyed-out card. This file is where that happens, and it is
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
        /// `CypressColor.compositionSwatches`, so the feature holds no colour of its own.
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
    /// how many basins are empty, tapping through to the nearest.
    struct VacantBlock: Equatable {
        /// `Where a tree could go` — the micro-label, ROADMAP §1's own phrase for these rows.
        let label: String
        /// `1,474 empty planting sites`.
        let title: String
        /// Inherits `SitePresentation`'s line and may not cross it: the city mapped them, nothing is
        /// growing, and Cypress does not plant.
        let subtitle: String
        /// The nearest of them — a `Route.site`. The row is inert when this is nil, which only
        /// happens if the block should not have drawn at all.
        let nearestID: UUID?
    }

    /// §4's amber card.
    struct Coverage: Equatable {
        /// `9 young trees with no visits since planting`.
        let title: String
        /// The two-sentence body. The second sentence is present only when it is true.
        let body: String
        /// `Walk the nine`.
        let ctaTitle: String
        /// Where the CTA goes: the nearest of them. Screen 14's own footnote calls itself "the
        /// almanac's 'walk the nine' list, one tree at a time", so one tree is the destination.
        let firstTreeID: UUID
    }

    /// The trailing pill on C1 — the neighbourhood's name, or nil when there is no area.
    let neighborhoodName: String?
    let seasonRows: [SeasonRow]
    let composition: Composition?
    let coverage: Coverage?
    let vacantSites: VacantBlock?

    /// §5, always drawn. It is the sentence that makes the screen honest whatever else is on it,
    /// and on a device with no location it is the only thing on it.
    var footnote: String { AlmanacCopy.footnote }

    /// Whether anything at all sits between the header and the footnote.
    ///
    /// **NOT SPECIFIED.** SCREENS.md 12 draws one state, the full one. What an almanac with nothing
    /// in it looks like is not drawn anywhere, and it is the state most devices are in: no seeded
    /// tree carries an observation or a photo, so the bloom row has nothing behind it, and a device
    /// with no location fix has no neighbourhood at all. What was built is the restrained reading —
    /// each block derives from data and a block with no data behind it is absent (§5.6) — leaving
    /// the screen's own chrome. See ERRATA.
    var isEmpty: Bool { seasonRows.isEmpty && composition == nil && coverage == nil && vacantSites == nil }

    // MARK: - Derivation

    init(almanac: Almanac, now: Date = .now, calendar: Calendar = .current, locale: Locale = .current) {
        guard let area = almanac.neighborhood else {
            self.neighborhoodName = nil
            self.seasonRows = []
            self.composition = nil
            self.coverage = nil
            self.vacantSites = nil
            return
        }

        self.neighborhoodName = area.name
        self.seasonRows = Self.seasonRows(area, now: now, calendar: calendar, locale: locale)
        self.composition = Self.composition(area.composition, locale: locale)
        self.coverage = Self.coverage(area.coverage, locale: locale)
        self.vacantSites = Self.vacantSites(area.vacantSites, locale: locale)
    }

    // MARK: - §2 This season

    /// The three C10 rows, in SCREENS.md's order, each present only if its subject is.
    ///
    /// A9 names the floors this block answers to: "bloom sightings need 1". The other two are city
    /// data and their floor is the same one: one elder, one newly planted tree. Below that there is
    /// nothing to notice, and the almanac's whole job is noticing.
    private static func seasonRows(
        _ area: AlmanacNeighborhood,
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
                    treeID: bloom.treeID
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
                    treeID: elder.treeID
                )
            )
        }

        if let planted = area.newestNeighbors, planted.treeCount > 0 {
            rows.append(
                SeasonRow(
                    kind: .newestNeighbors,
                    accent: .newGrowth,
                    title: AlmanacCopy.newestTitle,
                    subtitle: AlmanacCopy.newestSubtitle(
                        treeCount: planted.treeCount,
                        leadingSpecies: planted.leadingSpecies,
                        locale: locale
                    ),
                    treeID: nil
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
    private static func composition(_ composition: NeighborhoodComposition?, locale: Locale) -> Composition? {
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
        // Only when there is a remainder to name. A neighbourhood whose whole inventory is three
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
    private static func coverage(_ coverage: CoverageGap?, locale: Locale) -> Coverage? {
        guard let coverage,
              let count = coverage.trees.totalCount,
              count > 0,
              let nearest = coverage.trees.items.first
        else { return nil }

        // §4's second sentence is a claim about walking distance, so it is checked rather than
        // asserted: it renders only when every tree on the list really is inside the radius.
        let farthest = coverage.trees.items.map(\.distanceM).max() ?? 0
        let allWithinWalk = farthest <= AlmanacMetrics.walkRadiusM

        return Coverage(
            title: AlmanacCopy.coverageTitle(count: count, locale: locale),
            body: AlmanacCopy.coverageBody(count: count, allWithinWalk: allWithinWalk, locale: locale),
            ctaTitle: AlmanacCopy.coverageCTA(count: count, locale: locale),
            firstTreeID: nearest.id
        )
    }

    /// §-new: `Where a tree could go` (RULINGS R10). A count and a destination, or nothing.
    ///
    /// Absent when the neighbourhood holds no sites — which E115 measured as nowhere in the city, but
    /// §5.6 is a rule about the general case — and absent when there is nowhere to send the tap, so
    /// the row is never a statement the reader cannot act on.
    private static func vacantSites(_ sites: VacantSites?, locale: Locale) -> VacantBlock? {
        guard let sites, sites.count > 0, let nearestID = sites.nearestID else { return nil }
        return VacantBlock(
            label: AlmanacCopy.vacantLabel,
            title: AlmanacCopy.vacantTitle(count: sites.count, locale: locale),
            subtitle: AlmanacCopy.vacantSubtitle,
            nearestID: nearestID
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

    /// §5, verbatim. Centred, `text.faintAlt`.
    static let footnote = "No ranks, no counters. The almanac notices trees, not scores."

    /// §2's micro-label.
    static let seasonLabel = "This season"

    /// §2's three drawn titles, verbatim.
    static let bloomTitle = "First bloom of the year"
    static let elderTitle = "The elder"
    static let newestTitle = "Newest neighbors"

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

    static let locationPromptTitle = "See your neighbourhood"
    static let locationPromptSubtitle = "Turn on location and the almanac fills with the trees around you."

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

    // MARK: §2 row 3 — newest neighbours

    /// `23 trees planted this spring, mostly ginkgo and tea tree`.
    ///
    /// **The `mostly` clause needs two trees to be true of.** One tree is not "mostly" anything, so
    /// at a count of one the sentence stops after the season. Two names at most, because the mock
    /// draws two and a list of nine species is not a characterisation. **NOT SPECIFIED** — §2 gives
    /// one instance of this string and no rule; see ERRATA.
    ///
    /// **The names are the record's, capitalisation and all.** The mock writes `mostly ginkgo and
    /// tea tree` in lower case, mid-sentence, which is right for those two words and wrong for the
    /// seed: its common names are title case and include proper nouns and initialisms, so
    /// lower-casing turns `NZ tea tree` into `nz tea tree` and `New Zealand Xmas Tree` into a
    /// sentence about a place that is not capitalised. Deciding which words inside a name may be
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

    /// `The first two summers decide whether a street tree makes it. All nine are within a
    /// 15-minute walk.`
    ///
    /// The first sentence is a fact about street trees and is always true. The second is a claim
    /// about where the reader is standing, so it is only written when it has been checked — see
    /// `AlmanacPresentation.coverage`. A sentence that is drawn whether or not it is true is not
    /// copy, it is decoration.
    static func coverageBody(count: Int, allWithinWalk: Bool, locale: Locale) -> String {
        let opening = "The first two summers decide whether a street tree makes it."
        guard allWithinWalk else { return opening }
        let subject = count == 1 ? "It is" : "All \(spelledOut(count, locale: locale)) are"
        return "\(opening) \(subject) within a 15-minute walk."
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
/// carries no loose values, while every colour, font and radius stays a `DesignSystem` token
/// (ARCHITECTURE §6).
enum AlmanacMetrics {
    /// §3 draws three named species above the remainder.
    static let compositionNamedRows = 3

    /// How far §4's `within a 15-minute walk` reaches.
    ///
    /// 15 minutes at 4.8 km/h — the walking speed transport planning uses for a "15-minute
    /// neighbourhood" — is 1,200 m. **NOT SPECIFIED**: the mock states the claim and no source
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
    static let coverageBodyTop: CGFloat = 4
    static let coverageBodyBottom: CGFloat = 12

    /// §5: footnote `padding:16px 18px 36px`, `margin-top:auto`.
    static let footnoteTop: CGFloat = 16
    static let footnoteBottom: CGFloat = CypressSpacing.bottomFootnote
}
