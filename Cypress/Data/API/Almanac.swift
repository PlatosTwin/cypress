import Foundation

/// The payload behind screen 12 — the neighborhood almanac.
///
/// **This is the screen D1 exists for.** The leaderboard was killed because "every ranked metric is
/// farmable in under 30 seconds", and the almanac is what replaced it: it "notices trees instead of
/// scoring people" (PRODUCT §3). The shape of this type is where that promise is kept or lost, so
/// three rules are structural here rather than editorial:
///
/// - **No count of anybody's actions reaches this payload** (D1, ARCHITECTURE §5.1). The numbers on
///   it count *trees* — trees the city planted, trees of one species, trees nobody has been to yet —
///   with one exception, `BloomFirst.observerCount`, which counts distinct *people* and is the count
///   A8 explicitly sanctions, under A8's own floor of three. There is no ordering of contributors
///   anywhere and no query that could produce one.
/// - **An aggregate with no data behind it is absent, not zero** (ARCHITECTURE §5.6, A9). Every
///   field below except the neighborhood's name is optional, and each `nil` means "there is nothing
///   to say", which is what a fresh install has to say about almost all of them.
/// - **Nothing here identifies a contributor** (D11, DECISIONS §3.11). The bloom sighting carries a
///   tree, a date and a headcount; it does not carry who, and no method on `CypressAPI` can turn it
///   into who.
///
/// One consequence of the local-first build worth stating out loud: the two contribution-derived
/// surfaces (the bloom sighting and the coverage gap) are computed over the contributions this
/// installation holds, which today is the ones it made itself, because no sync brings anybody
/// else's down. The almanac is therefore honest but small until there is a server, and it says so
/// by rendering nothing rather than by apologizing.
public struct Almanac: Hashable, Sendable {

    /// The area the almanac is about, or `nil` when there is no area to be about.
    ///
    /// A4 fixes the *unit* — an SF Analysis Neighborhood — and its stated mechanism does not exist
    /// (ERRATA E44). Screen 12 resolves the unit through the nearest inventoried tree, the same seam
    /// screen 07 uses, and without a location fix there is no answer: no neighborhood, no elder, no
    /// species mix, no coverage list. "We could not tell where you are" and "nothing is happening
    /// here" are different facts and only one of them is ever true.
    public let neighborhood: AlmanacNeighborhood?

    public init(neighborhood: AlmanacNeighborhood?) {
        self.neighborhood = neighborhood
    }

    /// No area, and therefore no almanac.
    public static var empty: Almanac { Almanac(neighborhood: nil) }
}

// MARK: - The area

/// **What the almanac is about** — RULINGS R29, ERRATA E182.
///
/// A4 fixed the unit as an SF Analysis Neighborhood. D16 made the destination a merged national
/// inventory, and the seed already holds two cities, only one of which publishes polygons we carry.
/// R29's answer is a named area where the record holds one and a stated distance where it does not,
/// and this type is that answer: the two cases are different promises and the screen says which one
/// it is making rather than calling both "your area".
public enum AlmanacArea: Hashable, Sendable {

    /// A polygon the seed carries, named by the city that drew it.
    ///
    /// The name is the seed's own, verbatim (A4, ERRATA E2). Never prettified: SF's official set has
    /// no "Outer Sunset" — the mock's pill names a place the dataset the product committed to does
    /// not carry (ERRATA E47).
    case named(String)

    /// Everything within this many meters of the reader, because no boundary in the record covers
    /// where they are standing.
    case radius(meters: Double)
}

// MARK: - The neighborhood

/// One area, and everything screen 12 says about it.
public struct AlmanacNeighborhood: Hashable, Sendable {

    /// The area this almanac is about (R29).
    public let area: AlmanacArea

    /// The area's name, when it has one. `nil` for a radius, and that `nil` is load-bearing:
    /// `PinSet.neighborhoodName` documents that "an area we could not name must not be named", and
    /// a distance is not a name.
    public var name: String? {
        guard case let .named(name) = area else { return nil }
        return name
    }

    /// SCREENS.md 12 §2 row 1 — the year's first recorded flowering in this neighborhood.
    /// `nil` below A9's floor of one sighting.
    public let firstBloom: BloomFirst?

    /// §2 row 2 — the oldest planting date the city record holds here.
    public let elder: ElderTree?

    /// §2 row 3 — what was planted in the current spring.
    public let newestNeighbors: RecentPlanting?

    /// §3 — the species mix. A9: "species mix always renders from city data".
    public let composition: NeighborhoodComposition?

    /// §4 — the coverage gap, the only directed ask in the app (D1).
    public let coverage: CoverageGap?

    /// The vacant planting sites (RULINGS R10). A statement, not an ask — see `VacantSites`. `nil`
    /// only where the neighborhood holds none, which E115 measured as nowhere in the city.
    public let vacantSites: VacantSites?

    /// Whether this almanac is about the area the reader's fix resolves, or one they chose.
    ///
    /// **What it decides is which blocks are honest, not which are interesting.** §4 — the coverage
    /// gap, the app's one directed ask (D1) — asks the reader to go and look at particular trees,
    /// and its second sentence is a claim about how far away they are from *the reader*
    /// (`AlmanacMetrics.walkRadiusM`). Neither survives being asked about a neighborhood across
    /// town, so `LocalAPI` withholds the block for `.picked` rather than printing an ask nobody can
    /// answer. Everything else here is a fact about the place and is unchanged.
    public let resolution: AreaResolution

    public init(
        area: AlmanacArea,
        firstBloom: BloomFirst? = nil,
        elder: ElderTree? = nil,
        newestNeighbors: RecentPlanting? = nil,
        composition: NeighborhoodComposition? = nil,
        coverage: CoverageGap? = nil,
        vacantSites: VacantSites? = nil,
        resolution: AreaResolution = .fromFix
    ) {
        self.area = area
        self.firstBloom = firstBloom
        self.elder = elder
        self.newestNeighbors = newestNeighbors
        self.composition = composition
        self.coverage = coverage
        self.vacantSites = vacantSites
        self.resolution = resolution
    }
}

/// Screen 12's `Where a tree could go` block (RULINGS R10, ERRATA E121).
///
/// **A statement, deliberately not the §4 ask.** E115 drew the line: the coverage gap (§4) is "the
/// only directed ask in the app" and its subject is a tree somebody can go and observe. A vacant site
/// takes no visit, no observation, no measurement and no care event — the app's whole vocabulary has
/// nothing true to say about a hole — so an ask pointed at one would be a `Walk to it` that ends at
/// bare pavement, the same defect as "sent to the city". This block only says how many there are and
/// offers to show the nearest, which is the one honest sentence available.
public struct VacantSites: Hashable, Sendable {
    /// How many planting sites in the neighborhood have no tree in them. Counts city records, not
    /// user actions, so it carries no A8 floor (ARCHITECTURE §5.1).
    public let count: Int

    /// The nearest of them, nearest first, capped at `AlmanacLimits.vacantSiteRowLimit`
    /// (ERRATA E129).
    ///
    /// It was a single `nearestID` until E129, because the block's only affordance opened one basin.
    /// That is the defect E129 fixed on both of screen 12's counted rows at once: a row that says
    /// `1,474 empty planting sites` and opens one of them has not answered the question it raised.
    ///
    /// **Deliberately not a `Series`, unlike `CoverageGap.trees`.** `Series` exists to stop a page's
    /// size being read as a total (ERRATA E38), and it proves completeness by reading one row more
    /// than the caller wanted. Here `count` is a `COUNT(*)` over the same predicate these rows came
    /// from, so completeness is `nearest.count >= count` — a comparison against a number the data
    /// already stands behind, which is a stronger proof than the extra row and needs no type to hold
    /// it. Sunset/Parkside holds 1,474 of these, so this array is almost always a page, and
    /// `PinSet.isComplete` is what keeps the destination from calling it the whole set.
    public let nearest: [TreePin]

    public init(count: Int, nearest: [TreePin]) {
        self.count = count
        self.nearest = nearest
    }
}

// MARK: - This season

/// The first flowering anybody recorded in this neighborhood this calendar year.
///
/// SCREENS.md 12 §2: `Red flowering gum on 44th Ave · Jan 22, three neighbors saw it`.
///
/// The subject is a tree and an event, never a person. `observerCount` is the one headcount on this
/// screen and it is A8's, not a new idea: "distinct users with 2 or more care_events or observations
/// on the tree in 24 months; shown only when 3 or more". The floor lives in
/// `AlmanacThresholds.minimumObservers` and is applied in the presentation, so the payload stays a
/// statement of what the record holds and the screen stays the place that decides what may be said.
public struct BloomFirst: Hashable, Sendable {
    public let treeID: UUID
    /// The species' common name, or `nil` — 312 seeded trees carry no species at all because the
    /// city's label names no taxon (ERRATA E14), and 11 species carry no common name. Neither gets
    /// a name invented for it (BUILD-PLAN §15).
    public let speciesCommonName: String?
    /// The street address the city holds. The house number is dropped before this reaches the
    /// screen; see `AlmanacCopy.street(from:)`.
    public let address: String?
    /// When the earliest flowering visit of the year was captured.
    public let firstSeenAt: Date
    /// Distinct contributors who recorded a flowering visit on this tree this year.
    public let observerCount: Int
    /// This tree's own photograph, chosen by `PhotoHero` — the same rule the profile hero and the
    /// personal lists use (#176). `nil` on `RemoteAPI`, where nothing computes it yet, and for any
    /// tree this device has never itself photographed: the almanac is neighborhood-wide, and a
    /// tree nobody on this device photographed truthfully has no photograph to show here.
    public let heroPhotoID: UUID?

    public init(
        treeID: UUID,
        speciesCommonName: String?,
        address: String?,
        firstSeenAt: Date,
        observerCount: Int,
        heroPhotoID: UUID? = nil
    ) {
        self.treeID = treeID
        self.speciesCommonName = speciesCommonName
        self.address = address
        self.firstSeenAt = firstSeenAt
        self.observerCount = observerCount
        self.heroPhotoID = heroPhotoID
    }
}

/// The oldest planting date the city record holds inside the neighborhood.
///
/// SCREENS.md 12 §2: `Grandmother Cypress · in the city record since 1898`.
///
/// **"In the city record since" is the precise claim and the only one available.** DataSF fills
/// `PlantDate` for 70,067 of 195,309 trees, so this is the oldest tree *with a recorded planting
/// date*, which is not the same as the oldest tree. The drawn copy happens to say exactly that, and
/// it is kept for exactly that reason.
public struct ElderTree: Hashable, Sendable {
    public let treeID: UUID
    /// The tree's active name, when it has been named (D15). Screen 12's mock elder has one; almost
    /// no real tree does.
    public let activeName: String?
    public let speciesCommonName: String?
    public let address: String?
    public let plantedYear: Int
    /// This tree's own photograph, chosen by `PhotoHero` (#176). See `BloomFirst.heroPhotoID` for
    /// why it is `nil` far more often here than on a personal surface.
    public let heroPhotoID: UUID?

    public init(
        treeID: UUID,
        activeName: String?,
        speciesCommonName: String?,
        address: String?,
        plantedYear: Int,
        heroPhotoID: UUID? = nil
    ) {
        self.treeID = treeID
        self.activeName = activeName
        self.speciesCommonName = speciesCommonName
        self.address = address
        self.plantedYear = plantedYear
        self.heroPhotoID = heroPhotoID
    }
}

/// What the city planted in this neighborhood in the current spring.
///
/// SCREENS.md 12 §2: `23 trees planted this spring, mostly ginkgo and tea tree`.
public struct RecentPlanting: Hashable, Sendable {
    public let treeCount: Int
    /// The most common species among them, most common first. Empty when every one of those trees
    /// carries no species.
    public let leadingSpecies: [String]

    /// The trees themselves, nearest first, capped at `AlmanacLimits.recentPlantingRowLimit`
    /// (ERRATA **E182**, the owner's own report: *"Clicking on newest neighbors on neighborhood
    /// almanac should show them on the map."*).
    ///
    /// This row was the last counted row on screen 12 that named a group and could not say where it
    /// was — the identical defect E129 fixed on the coverage gap and the vacant sites, and E144 on a
    /// single record. It is fixed the identical way, with the same type and the same destination,
    /// because a third route onto the map would be a third chance to answer *where* differently.
    ///
    /// `treeCount` stays the total over the whole window and these are a page of it, exactly as
    /// `VacantSites` splits the two. In the shipped seed the page is never a page — the busiest
    /// neighborhood holds five spring plantings — but the cap is real and `PinSet.isComplete`
    /// compares against the total rather than trusting that.
    public let nearest: [TreePin]

    public init(treeCount: Int, leadingSpecies: [String], nearest: [TreePin] = []) {
        self.treeCount = treeCount
        self.leadingSpecies = leadingSpecies
        self.nearest = nearest
    }
}

// MARK: - Who lives here

/// The neighborhood's species mix, from the city inventory alone.
///
/// A9: "species mix always renders from city data" — which is why this is the one block on the
/// screen that a fresh install still draws in full.
///
/// Community-added trees are excluded for the same reason `GroveNeighborhood.species` excludes them:
/// a self-asserted species on an unverified tree would let a contributor move the mix by adding a
/// tree (DECISIONS §3.16, D12).
public struct NeighborhoodComposition: Hashable, Sendable {
    /// The header's own number — `Who lives here · 64 species`.
    public let distinctSpeciesCount: Int
    /// Every city-inventory tree here that carries a species. The denominator of every share below.
    public let treeCount: Int
    /// The most common species, most common first. SCREENS.md 12 §3 draws three and an
    /// "Everyone else" remainder; how many are drawn is the presentation's business.
    public let leading: [SpeciesShare]

    public init(distinctSpeciesCount: Int, treeCount: Int, leading: [SpeciesShare]) {
        self.distinctSpeciesCount = distinctSpeciesCount
        self.treeCount = treeCount
        self.leading = leading
    }
}

/// One row of the composition card: a species and how many of it stand here.
///
/// A count of trees, not of anything anybody did.
public struct SpeciesShare: Hashable, Sendable, Identifiable {
    public var id: UUID { speciesID }
    public let speciesID: UUID
    /// The species' own common name, falling back to the scientific name for the 11 seeded species
    /// that have none — exactly as `SpeciesQueries` does (ERRATA E51).
    public let name: String
    public let treeCount: Int

    public init(speciesID: UUID, name: String, treeCount: Int) {
        self.speciesID = speciesID
        self.name = name
        self.treeCount = treeCount
    }
}

// MARK: - Where eyes are needed

/// The young trees in this neighborhood that nobody has visited since they were planted.
///
/// SCREENS.md 12 §4, and the only directed ask in the app (D1): "coverage gaps are the only directed
/// incentive (chasing coverage produces exactly the data you want)".
///
/// Note which way round the query runs. This is not "trees you have not visited" — it asks whether
/// *anyone* has, which is the question the card's copy asks and the one a server will answer with
/// everybody's contributions in hand. That it currently resolves to this device's own contributions
/// is a property of there being no sync, not of the question.
public struct CoverageGap: Hashable, Sendable {

    /// The trees, nearest first.
    ///
    /// A `Series` because the card prints its size — `9 young trees with no visits since planting` —
    /// and a page's size read as a total is the bug `Series` exists to make unwritable (ERRATA E38).
    /// An incomplete read prints no number, and this card is nothing but a number.
    public let trees: Series<CoverageTree>

    public init(trees: Series<CoverageTree>) {
        self.trees = trees
    }
}

/// One tree on the coverage list, and how far the reader is from it.
public struct CoverageTree: Hashable, Sendable, Identifiable {
    public var id: UUID { pin.id }

    /// The tree, as the thing a map can draw (ERRATA E129).
    ///
    /// It was a bare `id` until E129, and the coordinate was being read and thrown away:
    /// `AlmanacQueries.youngTreesWithoutVisits` has always selected `lat`/`lon`, because the card's
    /// second sentence is a claim about walking distance and `LocalAPI` needed the coordinate to
    /// check it. So §4 knew where all nine trees were and could only send the reader to one of them.
    ///
    /// A `TreePin` rather than a `Coordinate`, so the pin the destination draws is the pin screen 01
    /// would draw for the same record — `MapPinKind` decides that from `status`, `source` and
    /// `verificationState`, and a group whose members carried only a coordinate would have to have
    /// those three invented for it.
    public let pin: TreePin

    /// Great-circle meters from the fix the almanac was resolved against. Present because §4's body
    /// makes a claim about walking distance, and a claim gets checked rather than printed.
    public let distanceM: Double

    public init(pin: TreePin, distanceM: Double) {
        self.pin = pin
        self.distanceM = distanceM
    }
}

// MARK: - Limits

public enum AlmanacLimits {
    /// How many coverage-gap trees are read.
    ///
    /// A cap rather than an unbounded read, because a neighborhood with a large planting program
    /// and no contributions would otherwise pull every one of them into memory to print one number.
    /// It is set well clear of the real distribution — the busiest neighborhood in the seed holds
    /// 21 young trees — so that in practice the read is whole and the card can print its count.
    /// When it does trip, the count disappears rather than shrinking (ERRATA E38).
    public static let coverageRowLimit = 200

    /// How many vacant planting sites the `Where a tree could go` row carries to its map
    /// (ERRATA E129).
    ///
    /// **This one really is a page, and the destination says so**, which is the whole of E38 applied
    /// to a group that cannot be shown whole: E115 measured every neighborhood in the city at
    /// between 4 and 1,474 sites, so a map of all of them is not available at any zoom a person can
    /// read. The count on screen stays the `COUNT(*)`; the map shows this many and the sentence over
    /// it says how many that is.
    ///
    /// **NOT SPECIFIED** — no source names a number here — so it is chosen against two things that
    /// are measured. The busiest neighborhood in the seed holds 21 coverage-gap trees (see
    /// `coverageRowLimit`), so 20 puts the two maps at the same density and neither is a density this
    /// app has not already reasoned about. And the 20 nearest basins to a fix inside Sunset/Parkside
    /// span 197 m × 212 m — about two blocks, close to screen 01's own opening view of 120 m, which
    /// `MapLayout.defaultSpanMeters` picked as the scale at which 18 pt pins stop fusing (ERRATA
    /// E12). A larger cap buys pins the camera would have to pull back to hold, and pulling back is
    /// exactly what E12 measured as the point where the pin layer starts lying about how many
    /// records there are.
    public static let vacantSiteRowLimit = 20

    /// How many of this spring's plantings the `Newest neighbors` row carries to its map
    /// (ERRATA E182).
    ///
    /// The same number as `vacantSiteRowLimit`, for the same measured reason and stated once more
    /// rather than shared: 20 pins is about the density `MapLayout.defaultSpanMeters` was chosen for,
    /// and above it E12's finding is that the pin layer starts lying about how many records there
    /// are. It is a much looser cap here — the busiest neighborhood in the shipped seed holds five
    /// spring plantings — which is why it is a cap and not a page size anybody has to think about.
    public static let recentPlantingRowLimit = 20

    /// The radius of the fallback area, when no polygon in the record covers the reader
    /// (RULINGS **R29**).
    ///
    /// **1,200 m, which is `AlmanacMetrics.walkRadiusM`, and the coincidence is the choice.** Two
    /// things had to be true of this number and one number satisfies both:
    ///
    /// - **It has to be a neighborhood-sized area, or the screen's thresholds change meaning.** SF's
    ///   41 Analysis Neighborhoods span 0.015–0.045 degrees of latitude; a 1,200 m radius is 0.0216,
    ///   which sits inside that range rather than beside it. Measured on the shipped seed, the circle
    ///   around downtown San Jose holds 6,963 records and 167 species — between Outer Richmond
    ///   (6,216) and Noe Valley (6,361). A smaller area would cross the cold-start floors less often
    ///   and quietly empty panels that were populating (DECISIONS §2.6).
    /// - **§4's second sentence has to stay honest.** The coverage card says "All nine are within a
    ///   15-minute walk" only when it has checked, against `AlmanacMetrics.walkRadiusM`. Setting the
    ///   fallback to the same distance makes that check pass by construction inside the fallback,
    ///   which is the sentence being *true* rather than the check being skipped.
    ///
    /// The two constants are deliberately not one. If they ever diverge, the fallback area may hold
    /// a tree §4 declines to call walkable, which costs a true sentence rather than printing a false
    /// one — the safe direction, and the direction `walkRadiusM`'s own note already picks.
    public static let fallbackRadiusM: Double = 1_200
}

// MARK: - Default

public extension CypressAPI {
    /// An implementation with no city inventory behind it has no neighborhood, and therefore no
    /// almanac.
    ///
    /// The same shape as `groveSpecies()`'s default and for the same reason: it is a true statement
    /// about such an implementation rather than a placeholder, and it means a preview double or a
    /// second client does not have to invent a neighborhood to compile. `LocalAPI` overrides it
    /// with the real read; `RemoteAPI` overrides it to throw, because a server that does not exist
    /// has no answer at all, which is a different thing from an empty one.
    func almanac(near coordinate: Coordinate?, in area: AreaSelection) async throws -> Almanac { .empty }
}

// MARK: - Windows

/// The date windows the almanac's reads are scoped to.
///
/// Pure arithmetic over a clock and a calendar, kept out of both the SQL and the view so the two
/// questions the sources leave open — what "this spring" is, and how long a tree counts as young —
/// are answered in one readable place and can be tested without a database.
public enum AlmanacWindow {

    /// **"This spring" is March, April and May.**
    ///
    /// SCREENS.md 12 §2 writes `planted this spring` and nothing in the sources defines a season
    /// boundary. The meteorological quarters are the convention phenology uses and the one that
    /// needs no equinox table; the astronomical alternative would move the edge by about three
    /// weeks and change nothing else. Recorded in ERRATA rather than chosen silently.
    public static let springMonths = 3...5

    /// **A tree counts as young for two years after planting. This is a product threshold and it is
    /// not sourced.**
    ///
    /// This comment used to justify the number with §4's own body copy — "The first two summers
    /// decide whether a street tree makes it" — and the copy audit of 2026-08-23 struck that
    /// sentence (owner ruling) precisely because the app cannot source an arboricultural claim
    /// (DECISIONS constraint 15). A justification that was not good enough to print is not good
    /// enough to reason from, so it is gone from here as well, and nothing has been put in its
    /// place. Nothing sources it: SCREENS.md 12 §4 draws `9 young trees with no visits since
    /// planting` without defining young, DECISIONS D1 says "young trees unvisited since planting"
    /// and stops, and no ERRATA entry records this window the way the entry above records
    /// `springMonths`. Checked, rather than assumed, before this comment was rewritten.
    ///
    /// **The number and its behavior are unchanged, deliberately.** Moving it would change which
    /// trees screen 12 asks people to walk to, which is a product decision and not a comment's to
    /// make. All that changed is that the comment stopped claiming a basis it does not have.
    public static let youngTreeYears = 2

    /// The current calendar year's start, for "First bloom **of the year**".
    public static func yearStart(now: Date, calendar: Calendar) -> Date {
        calendar.date(from: calendar.dateComponents([.year], from: now)) ?? now
    }

    /// The current year's spring, as the inclusive `YYYY-MM-DD` bounds the seed's `planted_on`
    /// column is compared against.
    ///
    /// `nil` before March, because in January there is no "this spring" yet and the drawn copy has
    /// no word for any other season. The row simply does not draw until spring has begun — which is
    /// a second sense in which a seasonal row is seasonal, and is recorded in ERRATA.
    public static func currentSpring(now: Date, calendar: Calendar) -> (from: String, to: String)? {
        let parts = calendar.dateComponents([.year, .month], from: now)
        guard let year = parts.year, let month = parts.month, month >= springMonths.lowerBound else {
            return nil
        }
        return (
            from: String(format: "%04d-%02d-01", year, springMonths.lowerBound),
            to: String(format: "%04d-%02d-31", year, springMonths.upperBound)
        )
    }

    /// The earliest planting date that still counts as young, as a `YYYY-MM-DD` bound.
    public static func youngSince(now: Date, calendar: Calendar) -> String {
        let cutoff = calendar.date(byAdding: .year, value: -youngTreeYears, to: now) ?? now
        let parts = calendar.dateComponents([.year, .month, .day], from: cutoff)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 1, parts.day ?? 1)
    }
}
