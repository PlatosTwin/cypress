//
//  TreeProfilePresentation.swift
//  Cypress — Features/TreeProfile
//
//  Everything screens 03 (tree profile) and 14 (cold-start profile) render, derived from one
//  `TreeProfile` payload. Pure value code: no SwiftUI state, no I/O, no formatting decisions left
//  to the view.
//
//  ── The two screens are one screen ────────────────────────────────────────────────────────
//  SCREENS.md 14 lists its own deltas — "no hero, no foliage strip, no regulars row, no activity
//  feed, no quad-action row, badge is `PLANTED <year>`" — as "differences from 03 to encode as a
//  **variant**". So `isCold` is a property of the payload, not a second screen: a tree with no
//  photos and no visits renders the cold variant. Per D8 that is every tree in the shipped seed,
//  because the city inventory carries no community content at all.
//
//  ── Rules enforced here rather than in the view ───────────────────────────────────────────
//  - **D7**: the city's DBH is a *bucket*, never a point measurement. It becomes
//    `StatCard.Value.cityRecord`, which carries the `city record` badge and is not a `Quantity`,
//    so nothing downstream can render it as something a person taped.
//  - **D1**: no counts of user actions, no ranks, no streaks. See `caretakerHeadline`.
//  - **A8**: the caretakers line renders only at ≥3 distinct caretakers.
//  - **A3**: "best photo" is the most recent approved `full_tree` photo, resolution breaking ties.
//  - **A5**: the season strip is the most recent photo per calendar month across all years.
//  - **BUILD-PLAN §15**: no invented botany. Absent species content produces an absent section.
//

import Foundation

struct TreeProfilePresentation {

    /// One row of the activity feed (C9).
    struct ActivityItem: Identifiable {
        enum Kind { case visit, care }

        let id: UUID
        let kind: Kind
        /// The bold lead-in: `Visit` / `Care`.
        let label: String
        /// Everything after it, verbatim including its separator.
        let detail: String
        /// Trailing mono timestamp, e.g. `Oct 12`.
        let timestamp: String
    }

    /// One card of the stat grid (C11).
    struct StatItem: Identifiable {
        let id: String
        let label: String
        let value: StatCard.Value
        /// Measurement cards open the growth history (screen 11); the rest are inert.
        let opensGrowthHistory: Bool

        init(id: String, label: String, value: StatCard.Value, opensGrowthHistory: Bool = false) {
            self.id = id
            self.label = label
            self.value = value
            self.opensGrowthHistory = opensGrowthHistory
        }
    }

    /// The regulars row's data (A8). `count` is a count of *people who know the tree*, never of
    /// anybody's contributions (D1).
    struct Caretakers {
        let count: Int
        /// Initials for `AvatarStack`. Empty until the API carries caretaker identities — see
        /// `TreeProfileModel.caretakerInitials`.
        let initials: [String]
    }

    let profile: TreeProfile
    private let now: Date
    private let calendar: Calendar
    private let injectedCaretakerInitials: [String]

    init(
        profile: TreeProfile,
        now: Date = Date(),
        calendar: Calendar = .current,
        caretakerInitials: [String] = []
    ) {
        self.profile = profile
        self.now = now
        self.calendar = calendar
        self.injectedCaretakerInitials = caretakerInitials
    }

    private var tree: Tree { profile.tree }
    private var species: Species? { profile.species }

    // MARK: - Which variant

    /// Screen 14 rather than screen 03: nobody has photographed or visited this tree.
    ///
    /// Photos *and* visits, not photos alone: a visit whose photo is still in the outbox has
    /// already made the tree somebody's, and the cold-start copy ("be the first…") would be a lie.
    var isCold: Bool { visiblePhotos.isEmpty && visibleVisits.isEmpty }

    /// A planting site the city lists with no tree standing in it — 12,518 rows of the seed.
    ///
    /// **Not drawn in SCREENS.md.** ARCHITECTURE §5.8 says an unmocked state is a question for
    /// design rather than a screen to invent, so nothing new is drawn for it: it renders as the
    /// cold variant with the two elements that would be false removed. `No photos of this tree
    /// yet` and `Be the first to photograph this tree` both assert a tree, and there is not one.
    /// What is left is the city's own record of the site, which is all anybody knows about it.
    var isVacantSite: Bool { tree.status == .vacantSite }

    // MARK: - Identity

    /// The H1. A given name wins (D15); the species common name is the fallback display
    /// everywhere; the street address is what is left for a site the city lists with no species.
    var title: String {
        if let name = profile.activeName, name.isDisplayable { return name.name }
        if let common = species?.commonName, !common.isEmpty { return common }
        if let address = tree.address, !address.isEmpty { return address }
        return TreeProfilePresentation.fallbackTitle
    }

    static let fallbackTitle = "Tree"

    /// The italic serif line under the name, `·`-joined.
    ///
    /// SCREENS.md draws two versions of this line — `Monterey Cypress · Hesperocyparis macrocarpa`
    /// on 03, where the H1 is a given name, and `Lophostemon confertus · SF city inventory` on 14,
    /// where the H1 is already the common name. Both fall out of the same rule: name the tree with
    /// every fact the H1 has not already used, then state where the record came from.
    ///
    /// The provenance element is **required on both** (BUILD-PLAN §5: no UI-only provenance), which
    /// is the one place this line runs longer than the 03 mock.
    var subtitle: String {
        var parts: [String] = []
        if let species {
            if species.commonName != title, !species.commonName.isEmpty {
                parts.append(species.commonName)
            }
            if species.scientificName != title {
                parts.append(species.scientificName)
            }
        }
        parts.append(provenance)
        return parts.joined(separator: " · ")
    }

    /// "SF city inventory" vs "community-added, unverified" — the two labels SCREENS.md ships.
    var provenance: String {
        switch tree.source {
        case .cityImport: return "SF city inventory"
        case .community: return "community-added, unverified"
        }
    }

    /// `THRIVING` / `PLANTED 2024` / `REMOVED`, or none. The mapping is the component's (C13); a
    /// fourth badge is never invented here.
    var badge: StatusBadge.Kind? {
        StatusBadge.kind(
            status: tree.status,
            vitality: profile.latestObservation?.vitality,
            plantedYear: tree.plantedYear
        )
    }

    // MARK: - Hero (03) and empty well (14)

    /// `214 photos · since 2019`.
    var heroMetaPill: String? {
        guard !visiblePhotos.isEmpty else { return nil }
        let count = visiblePhotos.count
        let noun = count == 1 ? "photo" : "photos"
        guard let earliest = visiblePhotos.map(\.capturedAt).min() else { return nil }
        let year = calendar.component(.year, from: earliest)
        return "\(count) \(noun) · since \(year)"
    }

    /// `Best photo · Oct 2025` — A3. Dropped in dark (D2); that is the view's call.
    var heroEyebrow: String? {
        guard let best = bestPhoto else { return nil }
        return "Best photo · " + TreeProfilePresentation.monthYear.string(from: best.capturedAt)
    }

    /// A3: most recent approved `full_tree` photo, ties broken by resolution.
    var bestPhoto: Photo? {
        visiblePhotos
            .filter(\.isBestPhotoCandidate)
            .max { left, right in
                if left.capturedAt != right.capturedAt { return left.capturedAt < right.capturedAt }
                return left.resolution < right.resolution
            }
    }

    /// 14's dashed well copy, verbatim.
    static let emptyPhotoWellText = "No photos of this tree yet"

    // MARK: - Season strip (A5)

    /// SCREENS.md 14 drops the strip; every other state keeps it, including a tree that has been
    /// visited but not yet photographed — that strip renders empty rather than disappearing.
    var showsFoliageStrip: Bool { !isCold }

    /// Twelve months, January first (A5: "the most recent photo per calendar month across all
    /// years, so a strip fills over time").
    ///
    /// The cell is a placeholder for that month's photograph (SCREENS.md §2 preamble), so the strip
    /// encodes photo *coverage*, not a canopy density nobody measured: a month with a photo takes
    /// the densest ramp step, a month without takes the sparsest. D5 is still handed to the
    /// component — `FoliageStrip` clamps an evergreen away from the leaf-off treatment itself.
    var foliageDensities: [FoliageStrip.Density] {
        let covered = photographedMonths
        return (1...12).map { covered.contains($0) ? .full : .thin }
    }

    /// The calendar months (1–12) that carry at least one visible photo.
    var photographedMonths: Set<Int> {
        Set(visiblePhotos.map { calendar.component(.month, from: $0.capturedAt) })
    }

    /// `nil` for a site with no species on the record and for a species whose habit no source
    /// states (ERRATA E9). `FoliageStrip` treats both the same way it treats an evergreen: no cell
    /// may take the leaf-off treatment, because that would be a claim about a canopy nobody sourced.
    var leafRetention: LeafRetention? { species?.leafRetention }

    /// `FoliageStrip` labels every cell as a canopy state; on a coverage strip that would be a
    /// claim about foliage nobody made. The view replaces the per-cell labels with this.
    var foliageStripAccessibilityLabel: String {
        let months = photographedMonths.sorted().map { TreeProfilePresentation.monthNames[$0 - 1] }
        guard !months.isEmpty else {
            return "Season strip. No month has a photo yet."
        }
        return "Season strip. Photographed in " + months.joined(separator: ", ") + "."
    }

    // MARK: - How to recognize it

    /// The C14 green callout's body, or `nil`.
    ///
    /// **BUILD-PLAN §15 / DECISIONS §3.15**: the curated species pipeline (BUILD-PLAN §8) has run
    /// for the top 40 species, so `species.id_tips` is `[]` for the other 529 of the seed's 569.
    /// There is no empty-state copy for this callout in SCREENS.md, and ARCHITECTURE §5.8 says an
    /// unmocked state is a question for design rather than a string to invent — so the section is
    /// simply absent, and no placeholder botany is written in its place.
    var recognitionTip: IDTip? { species?.idTips.first }

    static let recognitionLeadIn = "How to recognize it:"

    // MARK: - Primary action

    /// Verbatim from 03 and 14.
    var ctaTitle: String {
        isCold ? "Be the first to photograph this tree" : "Visit · say hello with a photo"
    }

    // MARK: - Regulars row (A8, D1)

    /// A8: "distinct users with 2 or more care_events or observations on the tree in 24 months;
    /// shown only when 3 or more".
    ///
    /// `TreeProfile` carries the full care-event series and only the *latest* observation, so the
    /// observation half of A8 can only ever contribute one person. That is a payload limit, not a
    /// rule bent: the count is computed from what the record actually proves and never padded.
    var caretakers: Caretakers? {
        var eventsPerUser: [UUID: Int] = [:]
        for event in profile.careEvents where event.deletedAt == nil {
            guard let userID = event.userID, isWithinCaretakerWindow(event.capturedAt) else { continue }
            eventsPerUser[userID, default: 0] += 1
        }
        var qualifying = Set(eventsPerUser.filter { $0.value >= TreeProfilePresentation.caretakerMinimumContributions }.keys)

        if let observation = profile.latestObservation,
           let userID = observation.userID,
           isWithinCaretakerWindow(observation.capturedAt),
           (eventsPerUser[userID] ?? 0) + 1 >= TreeProfilePresentation.caretakerMinimumContributions {
            qualifying.insert(userID)
        }

        guard qualifying.count >= TreeProfilePresentation.caretakerThreshold else { return nil }
        return Caretakers(count: qualifying.count, initials: injectedCaretakerInitials)
    }

    /// `Six people know this tree` — identity phrasing, spelled out exactly as SCREENS.md draws it.
    /// It counts people, never contributions (D1).
    var caretakerHeadline: String? {
        guard let caretakers else { return nil }
        let spelled = TreeProfilePresentation.spellOut.string(from: NSNumber(value: caretakers.count))
            ?? String(caretakers.count)
        return spelled.prefix(1).uppercased() + spelled.dropFirst() + " people know this tree"
    }

    /// A8's "2 or more care_events or observations in 24 months".
    static let caretakerMinimumContributions = 2
    /// A8's cold-start threshold. Below it the row does not render at all (DECISIONS constraint 1).
    static let caretakerThreshold = 3
    static let caretakerWindowMonths = 24

    private func isWithinCaretakerWindow(_ date: Date) -> Bool {
        guard let cutoff = calendar.date(
            byAdding: .month,
            value: -TreeProfilePresentation.caretakerWindowMonths,
            to: now
        ) else { return true }
        return date >= cutoff
    }

    // MARK: - Activity feed

    /// Visits and care events, most recent first.
    var activity: [ActivityItem] {
        var items: [ActivityItem] = visibleVisits.map { visit in
            ActivityItem(
                id: visit.id,
                kind: .visit,
                label: "Visit",
                // The separator and the curly quotes are the mock's, carried verbatim.
                detail: visit.note.map { " · “\($0)”" } ?? "",
                timestamp: TreeProfilePresentation.dayStamp.string(from: visit.capturedAt)
            )
        }
        items += profile.careEvents.filter { $0.deletedAt == nil }.map { event in
            ActivityItem(
                id: event.id,
                kind: .care,
                label: "Care",
                detail: event.actions.isEmpty
                    ? ""
                    : " · " + event.actions.map(TreeProfilePresentation.careActionLabel).joined(separator: ", "),
                timestamp: TreeProfilePresentation.dayStamp.string(from: event.capturedAt)
            )
        }
        return Array(
            items
                .sorted { left, right in sortDate(of: left) > sortDate(of: right) }
                .prefix(TreeProfilePresentation.activityLimit)
        )
    }

    /// SCREENS.md draws two rows on 03 but does not say what bounds the feed. Four is a "recent
    /// history" window that keeps the screen near its drawn height; it is a **judgment call**, not
    /// a spec value.
    static let activityLimit = 4

    private func sortDate(of item: ActivityItem) -> Date {
        if item.kind == .visit {
            return visibleVisits.first { $0.id == item.id }?.capturedAt ?? .distantPast
        }
        return profile.careEvents.first { $0.id == item.id }?.capturedAt ?? .distantPast
    }

    /// `watered, mulched` — the BUILD-PLAN §4 vocabulary in prose.
    static func careActionLabel(_ action: CareAction) -> String {
        switch action {
        case .watered: return "watered"
        case .mulched: return "mulched"
        case .weeded: return "weeded"
        case .litterCleared: return "litter cleared"
        case .staked: return "staked"
        }
    }

    // MARK: - Stat grid (D7)

    /// The cards, in the order SCREENS.md draws them across 03 and 14: measurements first, then the
    /// city's own facts. A card whose fact the record does not carry is absent rather than blank.
    var stats: [StatItem] {
        var items: [StatItem] = []

        if let height = latestMeasurement(.height) {
            items.append(
                StatItem(
                    id: "height",
                    label: "Height",
                    value: .quantity(height.quantity),
                    opensGrowthHistory: true
                )
            )
        }

        if let dbh = latestMeasurement(.dbh) {
            items.append(
                StatItem(id: "dbh", label: "DBH", value: .quantity(dbh.quantity), opensGrowthHistory: true)
            )
        } else if let cityDBH = cityDBHRangeText {
            // D7, the whole point of this row: the city publishes a 5 cm *bucket*, not a number
            // anybody taped. `.cityRecord` is not a `Quantity`, carries the `city record` badge,
            // and cannot be mistaken downstream for a measurement.
            items.append(StatItem(id: "dbh", label: "DBH", value: .cityRecord(cityDBH)))
        }

        // The planted year is either the badge or a card, never both — 03 badges `THRIVING` and
        // cards `Planted 1898`; 14 badges `PLANTED 2024` and drops the card.
        if let plantedYear = tree.plantedYear, !badgeCarriesPlantedYear {
            items.append(StatItem(id: "planted", label: "Planted", value: .text(String(plantedYear))))
        }

        // `Site` is a 14 card, not an 03 one: SCREENS.md draws it only where the city record is
        // all there is to show. Its value is the DataSF `qSiteInfo` string verbatim — an open
        // vocabulary kept as free text (BUILD-PLAN §7), so `Sidewalk: Curb side : Cutout` is
        // printed as the city wrote it rather than folded into a tidier phrase nobody published.
        if isCold, let siteType = tree.siteType, !siteType.isEmpty {
            items.append(StatItem(id: "site", label: "Site", value: .text(siteType)))
        }

        if let record = cityRecordText {
            items.append(StatItem(id: "cityRecord", label: "City record", value: .text(record)))
        }

        if let watchFor = watchForText {
            items.append(StatItem(id: "watchFor", label: "Watch for", value: .prose(watchFor)))
        }

        return items
    }

    private var badgeCarriesPlantedYear: Bool {
        if case .planted = badge { return true }
        return false
    }

    /// `65–70 cm`. An en dash and no spaces, matching the copy rules (ARCHITECTURE §5.7).
    ///
    /// `IntRange`'s upper bound is exclusive, mirroring the Postgres `[)` the seed was built from;
    /// the city publishes these as 5 cm buckets, and the bucket is what is shown.
    var cityDBHRangeText: String? {
        guard let range = tree.dbhCityCmRange else { return nil }
        if range.upperBound - range.lowerBound <= 1 { return "\(range.lowerBound) cm" }
        return "\(range.lowerBound)–\(range.upperBound) cm"
    }

    /// `SF #13284` — the DataSF `TreeID`, which is the citable city record (BUILD-PLAN §7).
    var cityRecordText: String? {
        guard tree.source == .cityImport, let ref = tree.externalRef, !ref.isEmpty else { return nil }
        return "SF #\(ref)"
    }

    /// 14's `Watch for` card. Authored species care content only — 20 of the curated 40 carry any
    /// (BUILD-PLAN §8), and a species with none simply has no card.
    var watchForText: String? {
        let month = calendar.component(.month, from: now)
        return species?.careNotes.first { $0.monthRange.contains(month) }?.text
    }

    private func latestMeasurement(_ kind: MeasurementKind) -> TreeMeasurement? {
        profile.measurements
            .filter { $0.kind == kind && $0.deletedAt == nil }
            .max { $0.capturedAt < $1.capturedAt }
    }

    // MARK: - Cold-start footnote

    /// 14's footnote, verbatim — minus its first sentence when that sentence would be false.
    ///
    /// The drawn copy reads `A young tree nobody has visited. This is the almanac’s “walk the nine”
    /// list, one tree at a time.` The second sentence is true of every cold profile. The first is a
    /// claim about *this* tree, and D8 puts this variant in front of every tree in the city
    /// inventory, including 1890s cypresses. So the age claim renders only where the city record
    /// supports it, and nothing is reworded to cover the gap.
    ///
    /// **Judgment call, not in the spec:** `recentPlantingWindowYears`. SCREENS.md says nothing
    /// about what makes a tree "young"; ten years is a street-tree establishment horizon and is
    /// named here so it can be argued with in one place.
    var coldStartFootnote: String {
        guard isCold else { return "" }
        let almanac = "This is the almanac’s “walk the nine” list, one tree at a time."
        guard isRecentPlanting else { return almanac }
        return "A young tree nobody has visited. " + almanac
    }

    static let recentPlantingWindowYears = 10

    private var isRecentPlanting: Bool {
        guard let plantedYear = tree.plantedYear else { return false }
        let thisYear = calendar.component(.year, from: now)
        return thisYear - plantedYear <= TreeProfilePresentation.recentPlantingWindowYears
    }

    // MARK: - Filtered series

    /// Only approved photos reach a public surface (BUILD-PLAN §10, A3).
    var visiblePhotos: [Photo] {
        profile.photos.filter { $0.deletedAt == nil && $0.moderationState.isPubliclyVisible }
    }

    var visibleVisits: [Visit] {
        profile.visits.filter { $0.deletedAt == nil }
    }

    // MARK: - Formatters

    private static func fixedFormat(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.setLocalizedDateFormatFromTemplate(format)
        return formatter
    }

    /// `Oct 2025`.
    static let monthYear = fixedFormat("MMMyyyy")
    /// `Oct 12`.
    static let dayStamp = fixedFormat("MMMd")

    static let spellOut: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        return formatter
    }()

    static let monthNames = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
    ]
}
