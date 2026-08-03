import Foundation

/// `species.leaf_retention` (BUILD-PLAN §4). Drives phenology chips and season strip rendering (D5).
///
/// Every phenology surface derives from this attribute — an evergreen never shows a fall-color
/// chip or an autumn strip color (D5, DECISIONS §3.14).
///
/// **Absence is modeled by `Optional`, never by a case.** 59 of the 569 seeded species have no
/// authoritative source for their habit, and the seed column is NULL for them (ERRATA E9). An
/// `unknown` case here would be a fourth value every `switch` could quietly treat as a fact; an
/// optional forces each call site to say what it does when nobody has established the answer.
public enum LeafRetention: String, Codable, Sendable, Hashable, CaseIterable {
    case evergreen = "evergreen"
    case deciduous = "deciduous"
    case semiDeciduous = "semi_deciduous"

    /// Whether fall color is a possible phenological event for this species at all (D5).
    public var canShowFallColor: Bool {
        switch self {
        case .evergreen: return false
        case .deciduous, .semiDeciduous: return true
        }
    }
}

/// One entry of `species.id_tips jsonb`: `{icon, text}` (BUILD-PLAN §4).
/// Authored content only — no fabricated botany (DECISIONS §3.15).
public struct IDTip: Hashable, Codable, Sendable {
    public let icon: String
    public let text: String

    public init(icon: String, text: String) {
        self.icon = icon
        self.text = text
    }
}

/// A wrapping inclusive month window, e.g. November–February. `1 == January`.
public struct MonthRange: Hashable, Codable, Sendable {
    public let start: Int
    public let end: Int

    public init?(start: Int, end: Int) {
        guard (1...12).contains(start), (1...12).contains(end) else { return nil }
        self.start = start
        self.end = end
    }

    public func contains(_ month: Int) -> Bool {
        guard (1...12).contains(month) else { return false }
        if start <= end { return month >= start && month <= end }
        return month >= start || month <= end // wraps the year boundary
    }

    public var months: Set<Int> {
        Set((1...12).filter(contains))
    }

    /// The one wrapping window a set of months describes, or `nil` when it does not describe
    /// exactly one.
    ///
    /// BUILD-PLAN §4 stores each phenological season as a bare month array — `fall_color_months`
    /// and friends — which carries membership and nothing else. Where a *window* is needed, the
    /// ordered reading has to be recovered from that membership rather than assumed from the order
    /// the array happens to be in: `[11, 12, 1]`, `[1, 11, 12]` and `[12, 1, 11]` are the same
    /// November-through-January season, the curated YAML gives no reason to expect one spelling
    /// over another, and `SeasonalCalendar` sorts them anyway (ERRATA E33).
    ///
    /// A set with a gap in it — two separate bloom flushes, say — describes no single window, and
    /// this returns `nil` rather than inventing one that spans the gap.
    public static func spanning(_ months: some Sequence<Int>) -> MonthRange? {
        let set = Set(months.filter { (1...12).contains($0) })
        guard !set.isEmpty else { return nil }
        // A year-round season has no month that begins it; naming January is the only reading.
        guard set.count < 12 else { return MonthRange(start: 1, end: 12) }
        // The window opens at the month whose predecessor around the circle is absent. Exactly one
        // such month exists when the set is contiguous; two or more mean a gap.
        let openings = set.filter { !set.contains($0 == 1 ? 12 : $0 - 1) }
        guard openings.count == 1, let start = openings.first else { return nil }
        let unwrappedEnd = start + set.count - 1
        return MonthRange(start: start, end: unwrappedEnd > 12 ? unwrappedEnd - 12 : unwrappedEnd)
    }
}

/// One entry of `species.care_notes jsonb`: `{month_range, text}` (BUILD-PLAN §4).
public struct CareNote: Hashable, Codable, Sendable {
    public let monthRange: MonthRange
    public let text: String

    public init(monthRange: MonthRange, text: String) {
        self.monthRange = monthRange
        self.text = text
    }
}

/// `species.seasonal jsonb`: `{bloom_months, fall_color_months, fruit_months, new_growth_months}`
/// (BUILD-PLAN §4). Empty arrays are valid.
public struct SeasonalCalendar: Hashable, Codable, Sendable {
    public let bloomMonths: [Int]
    public let fallColorMonths: [Int]
    public let fruitMonths: [Int]
    public let newGrowthMonths: [Int]

    /// The arrays are sorted on the way in, and that is deliberate: each one is a *set* of months,
    /// so two spellings of the same season should be the same value, and `Hashable` should agree.
    /// Nothing may read a phenological start or end off `first` or `last` here — sorting is exactly
    /// what destroys that reading for a season that wraps the year. `MonthRange.spanning(_:)`
    /// recovers the window from the membership instead, which is order-independent by construction
    /// (ERRATA E33).
    public init(
        bloomMonths: [Int] = [],
        fallColorMonths: [Int] = [],
        fruitMonths: [Int] = [],
        newGrowthMonths: [Int] = []
    ) {
        self.bloomMonths = bloomMonths.sorted()
        self.fallColorMonths = fallColorMonths.sorted()
        self.fruitMonths = fruitMonths.sorted()
        self.newGrowthMonths = newGrowthMonths.sorted()
    }

    public static let empty = SeasonalCalendar()

    var allMonths: [Int] { bloomMonths + fallColorMonths + fruitMonths + newGrowthMonths }
}

/// Why a `Species` could not be constructed. Species records are loaded from the curated YAML by
/// migration and are never hand-edited in production (DECISIONS §3.15), so a throw here is a
/// content bug that must fail the import loudly.
public enum SpeciesValidationError: Error, Hashable, Sendable, CustomStringConvertible {
    /// D5 / DECISIONS §3.14 / BUILD-PLAN §4: "fall_color_months must be empty when
    /// leaf_retention = evergreen". Pinned by a schema invariant test (BUILD-PLAN §13).
    case evergreenWithFallColorMonths(scientificName: String, months: [Int])
    case monthOutOfRange(Int)
    case emptyScientificName

    public var description: String {
        switch self {
        case let .evergreenWithFallColorMonths(name, months):
            return "\(name) is evergreen but carries fall_color_months \(months) (D5)"
        case let .monthOutOfRange(month):
            return "month \(month) is outside 1...12"
        case .emptyScientificName:
            return "scientific_name is required"
        }
    }
}

/// A species field-guide entry (BUILD-PLAN §4 `species`, PRODUCT §3 "Species").
///
/// The curated list is roughly 100 species covering 90 % of SF street trees (BUILD-PLAN §8); the
/// long tail renders name, family, and a generic silhouette, with `curated == false`.
public struct Species: CoreEntity {
    public let id: UUID
    public let scientificName: String
    public let commonName: String
    public let family: String?
    /// Drives every phenology surface (D5). `nil` means no source states this species' habit,
    /// which renders as no phenology surface at all (ERRATA E9).
    public let leafRetention: LeafRetention?
    public let idTips: [IDTip]
    public let seasonal: SeasonalCalendar
    public let careNotes: [CareNote]
    /// True for the authored top list (BUILD-PLAN §8). False for stub rows produced by the ingest
    /// fallback path (BUILD-PLAN §7).
    public let curated: Bool
    public let createdAt: Date
    public let updatedAt: Date

    /// Validating initializer. Throws rather than silently repairing, because the only writer is
    /// the curated-YAML migration and BUILD-PLAN §7 requires ingest to fail loudly.
    ///
    /// An evergreen carrying `fallColorMonths` is rejected here (D5, DECISIONS §3.14). This is the
    /// practical form of "unrepresentable": `LeafRetention` must stay a flat enum because it maps
    /// to a database string column (BUILD-PLAN §4), so the invariant is enforced at construction
    /// and all stored properties are `let`, leaving no post-construction path back into the
    /// invalid state.
    ///
    /// `leafRetention` has no default. A species whose habit nobody has established passes `nil`
    /// deliberately; it must never arrive because a caller left the argument out (ERRATA E9).
    public init(
        id: UUID = UUID(),
        scientificName: String,
        commonName: String,
        family: String? = nil,
        leafRetention: LeafRetention?,
        idTips: [IDTip] = [],
        seasonal: SeasonalCalendar = .empty,
        careNotes: [CareNote] = [],
        curated: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) throws {
        guard !scientificName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SpeciesValidationError.emptyScientificName
        }
        if let bad = seasonal.allMonths.first(where: { !(1...12).contains($0) }) {
            throw SpeciesValidationError.monthOutOfRange(bad)
        }
        // D5 binds only when the habit is known. An unknown species carrying fall-color months is
        // not a contradiction — it is a species somebody sourced a calendar for and a habit for
        // nobody has (ERRATA E9).
        if leafRetention == .evergreen, !seasonal.fallColorMonths.isEmpty {
            throw SpeciesValidationError.evergreenWithFallColorMonths(
                scientificName: scientificName,
                months: seasonal.fallColorMonths
            )
        }
        self.id = id
        self.scientificName = scientificName
        self.commonName = commonName
        self.family = family
        self.leafRetention = leafRetention
        self.idTips = idTips
        self.seasonal = seasonal
        self.careNotes = careNotes
        self.curated = curated
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Property-name keys. The snake_case column and jsonb names of BUILD-PLAN §4 are produced by
    /// the coder's key strategy in `Data`, so no type in `Core` restates them.
    public enum CodingKeys: String, CodingKey {
        case id, scientificName, commonName, family, leafRetention
        case idTips, seasonal, careNotes, curated, createdAt, updatedAt
    }

    /// Decoding runs the same validation, so a corrupt row cannot enter the app through a decoder
    /// either (D5).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: try c.decode(UUID.self, forKey: .id),
            scientificName: try c.decode(String.self, forKey: .scientificName),
            commonName: try c.decode(String.self, forKey: .commonName),
            family: try c.decodeIfPresent(String.self, forKey: .family),
            // Absent and explicitly null both mean unknown; neither is repaired (ERRATA E9).
            leafRetention: try c.decodeIfPresent(LeafRetention.self, forKey: .leafRetention),
            idTips: try c.decodeIfPresent([IDTip].self, forKey: .idTips) ?? [],
            seasonal: try c.decodeIfPresent(SeasonalCalendar.self, forKey: .seasonal) ?? .empty,
            careNotes: try c.decodeIfPresent([CareNote].self, forKey: .careNotes) ?? [],
            curated: try c.decodeIfPresent(Bool.self, forKey: .curated) ?? false,
            createdAt: try c.decode(Date.self, forKey: .createdAt),
            updatedAt: try c.decode(Date.self, forKey: .updatedAt)
        )
    }
}

extension Species {
    /// The phenology states an observer may report against this species.
    ///
    /// **A tag here is the observer's report of what is in front of them, not the app's claim
    /// about the species** (see R35, #151). The
    /// species record — its calendar, its curation, its habit — may order or hint, but it never
    /// gates what a person standing at the tree is allowed to say they see. The one exclusion is
    /// D5's, and it stands because it is a *sourced fact*: a species known to be evergreen is
    /// never asked about fall color or bare, since either tag would contradict the record rather
    /// than inform it (DECISIONS §3.14, and the schema CHECK behind it).
    ///
    /// An **unknown habit therefore yields the full set**, not the empty one it used to (the old
    /// reading of ERRATA E9). Withholding `fallColor` from an unsourced species would itself
    /// assert "this is an evergreen" — precisely the unsourced claim E9 exists to prevent. E9's
    /// real subject — the APP's own phenology surfaces (screen 07's section, the season strip) —
    /// still renders nothing for an unknown habit; that is `SpeciesPresentation.showsPhenology`
    /// and `FoliageStrip.enforcingD5`, not this property.
    public var availablePhenologyTags: Set<PhenologyTag> {
        var tags: Set<PhenologyTag> = [.fullLeaf, .flowering, .fruiting, .leafOut]
        // `!= false`, deliberately: only a *known* evergreen excludes. `nil` is "nobody sourced
        // the habit", and an exclusion needs a fact.
        if leafRetention?.canShowFallColor != false {
            tags.insert(.fallColor)
            tags.insert(.bare)
        }
        return tags
    }

    /// The months this species is in leaf, used by the vitality seasonality rule (PRODUCT §3), or
    /// `nil` when the species' habit is unknown and there is therefore no leaf-on window to state
    /// (ERRATA E9). `nil` is not "no months" — see `Vitality.isRatingPermitted` for what the
    /// distinction buys.
    ///
    /// Evergreen and semi-deciduous species are in leaf year-round. For deciduous species the
    /// window runs from the opening of the new-growth season to the close of the fall-color
    /// season, wrapping the year if needed. When either season is absent — or is not one
    /// contiguous run of months, and so states no season at all — the northern-hemisphere default
    /// April–October applies; that fallback is a derivation, not authored botany, and is the one
    /// seasonality value not stated in the source documents.
    ///
    /// Each season's opening and close come from `MonthRange.spanning(_:)` rather than from the
    /// ends of the stored arrays. Reading `fallColorMonths.last` meant a species authored with a
    /// November-through-January fall put its leaf-on window's close in December, because the
    /// calendar sorts and December is the numeric maximum — and `Vitality.isRatingPermitted` would
    /// then have hidden the vitality rows in a month the authored calendar says the tree is still
    /// in leaf, with nothing a rater standing in front of it could do about that (ERRATA E33).
    public var leafOnMonths: Set<Int>? {
        switch leafRetention {
        case nil:
            return nil
        case .evergreen?, .semiDeciduous?:
            return Set(1...12)
        case .deciduous?:
            guard
                let newGrowth = MonthRange.spanning(seasonal.newGrowthMonths),
                let fallColor = MonthRange.spanning(seasonal.fallColorMonths),
                let window = MonthRange(start: newGrowth.start, end: fallColor.end)
            else {
                return Species.defaultDeciduousLeafOnMonths
            }
            return window.months
        }
    }

    /// April through October. Applies only when a deciduous species has no authored new-growth or
    /// fall-color months. See `leafOnMonths`.
    public static let defaultDeciduousLeafOnMonths: Set<Int> = Set(4...10)
}

// MARK: - The row whose scientific name is not a name

extension Species {

    /// The prefix a scientific name carries when the ingest never read one.
    ///
    /// DataSF publishes one column in the convention `Scientific name :: Common name`. When the
    /// scientific half is empty, `Tools/inventory_adapters.py`'s `parse_qspecies` classifies the row
    /// `stub` and stores **the whole raw string, separator and all**, in `scientific_name` — so the
    /// column holds `:: Magnolia` rather than a binomial. Five such rows ship, standing under seven
    /// trees, measured against `Cypress/Resources/cypress-seed.sqlite`.
    ///
    /// The marker lives in `Core` because it is a fact about a stored value, and both the query
    /// layer and two screens have to agree on it; `SpeciesQueries.stubNameMarker` reads it from
    /// here so the SQL filter and the drawn line cannot drift apart.
    public static let unreadScientificNameMarker = ":: "

    /// True when nobody ever read a scientific name for this row, so `scientificName` holds the
    /// ingest's raw source string instead of a name.
    ///
    /// The ruling that decides what the app does about it is
    /// `RULINGS R54`.
    ///
    /// **The same parse can produce a stub without the marker** — a source string carrying no `::`
    /// at all is also classified `stub`, and its scientific name is that string verbatim, which
    /// carries no prefix to test. None ship (`SeedStubNamingTests.theMarkerAndTheProvenanceFlagAgree`
    /// proves the marker and `species_map.is_stub` select the same rows in the seed as built), and
    /// that test is what will say so if one ever does. This property is deliberately not widened to
    /// guess at those: a rule for "does this string look like a name" is exactly what the ingest
    /// already tried and got wrong.
    public var scientificNameIsUnread: Bool {
        Species.isUnreadScientificName(scientificName)
    }

    /// The same test against a bare string, for the reads that carry a species name without a
    /// `Species` — `NearbyTree.speciesScientificName`, which the shortlist and a vacant site's
    /// neighbor line both draw. A static function rather than a `String` extension: this is a
    /// statement about one column of one table, not about strings.
    public static func isUnreadScientificName(_ name: String) -> Bool {
        name.hasPrefix(Species.unreadScientificNameMarker)
    }

    /// The city's own wording for this row, when the scientific name is not a name.
    ///
    /// **`commonName` is sound on these rows and `scientificName` is not**, which is the asymmetry
    /// the ruling turns on. `parse_qspecies` splits `:: Magnolia` and puts the common half —
    /// `Magnolia`, `Magnolia Little Gem`, `9662` — into `common_name` unaltered. That half is the
    /// city's, verbatim; the scientific half is empty and what stands in `scientific_name` is the
    /// parser's leftovers.
    ///
    /// `nil` when the common half is missing too, which is when `SpeciesQueries.decodeIfPresent`
    /// falls `commonName` back to the scientific name and quoting it would print the marker in a
    /// sentence written to avoid printing the marker.
    public var cityWordingForUnreadName: String? {
        guard scientificNameIsUnread else { return nil }
        let wording = commonName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wording.isEmpty, !wording.hasPrefix(Species.unreadScientificNameMarker) else { return nil }
        return wording
    }
}
