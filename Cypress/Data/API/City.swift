import Foundation

/// The payload behind the Journal tab's `City` segment.
///
/// **Same three rules `Almanac.swift` states for screen 12, applied at city scale:**
/// - No count of anybody's actions reaches this payload (D1, ARCHITECTURE §5.1). Every number counts
///   trees, never visits, observations or care events.
/// - An aggregate with no data behind it is absent, not zero (ARCHITECTURE §5.6, A9).
/// - Nothing here identifies a contributor (D11, DECISIONS §3.11).
///
/// **What this file adds that `Almanac.swift` did not need: nowhere does it, or anything built on
/// it, carry a city's proper name.** The bundled inventory is fused across `sf` and `us-ca-sj` with
/// no display-name column for the city itself — `id_spaces.id` is the bare key and
/// `inventories.name` is an inventory's published name, not a city's. Composing "San Francisco" or
/// "San Jose" from either would be the same guess RULINGS R28 and R51 already closed for a single
/// tree's own screen, and `CityManifest.displayName` — the one place this app *does* carry a civic
/// name entered by hand — is fetched from a network manifest and does not exist for the reader who
/// has never opened Cities or has no connection, which every other read on this payload does not
/// require. So `CityQueries.resolveIDSpace` resolves *which* city (a fact off a row, for scoping
/// queries) and nothing downstream of it ever turns that key into a name.
public struct CityAlmanac: Hashable, Sendable {

    /// What the resolved city has to say, or `nil` when no city resolved at all.
    ///
    /// Distinct from a `Snapshot` whose fields are all empty: that is a real city with nothing to
    /// report today; `nil` is "the inventory does not reach where the reader is standing", the same
    /// distinction `Almanac.neighborhood` draws and for the same reason (ERRATA E182).
    public let snapshot: Snapshot?

    public init(snapshot: Snapshot? = nil) {
        self.snapshot = snapshot
    }

    /// No city resolved, and therefore nothing to show.
    public static var empty: CityAlmanac { CityAlmanac(snapshot: nil) }

    /// One resolved city's findings.
    public struct Snapshot: Hashable, Sendable {

        /// The species mix around the reader — card 1's local half, and the input `Composition`
        /// reads at `AlmanacScope`'s own thresholds.
        ///
        /// Resolved exactly as the almanac resolves its own area (RULINGS R29): a named neighborhood
        /// where the seed carries one, a stated radius where it does not. Reusing that resolution
        /// rather than a fresh one is what lets card 1 ask "is this species markedly more common
        /// *here* than citywide" about the same "here" the almanac already means.
        public let localComposition: NeighborhoodComposition?

        /// The whole `idSpace`'s species mix — card 1's citywide half and all of card 2.
        ///
        /// **Never a `COUNT(*)` with no `id_space` predicate.** `CityQueries.speciesMix(idSpace:)` is
        /// the whole of that guarantee; this field is simply its result.
        public let cityComposition: NeighborhoodComposition?

        /// The oldest standing trees in this city whose planting the city recorded, oldest first —
        /// card 3.
        ///
        /// **One row more than the card draws.** `CityQueries.oldestOnFile` is handed
        /// `CityLimits.oldestRowLimit + 1`, so `CityPresentation` can tell whether the row just past
        /// its own cutoff shares the last drawn row's year — the fact that decides whether the card
        /// may say "the five oldest" outright or has to say something truer.
        public let oldest: [ElderTree]

        public init(
            localComposition: NeighborhoodComposition? = nil,
            cityComposition: NeighborhoodComposition? = nil,
            oldest: [ElderTree] = []
        ) {
            self.localComposition = localComposition
            self.cityComposition = cityComposition
            self.oldest = oldest
        }
    }
}

// MARK: - Limits

public enum CityLimits {
    /// How many of the oldest-on-file rows card 3 draws.
    public static let oldestRowLimit = 5

    /// The minimum number of trees the local scope must hold before card 1 will compare it to the
    /// city at all.
    ///
    /// **NOT SPECIFIED** — chosen rather than measured, the same footing `AlmanacMetrics.walkRadiusM`
    /// stands on. A comparison built from a handful of nearby trees can put any one species at 100%
    /// of a sample of two; this is the floor below which "markedly more common near you" is a
    /// statement about sample size rather than about the street. It is deliberately far under a real
    /// neighborhood's count (the smallest in the shipped seed carries thousands) so that it is the
    /// almanac's own cold-start rule — a resolved area with a real mix — that governs in practice,
    /// and this floor only bites for a reader standing at the ragged, sparsely-inventoried edge of the
    /// record.
    public static let minimumLocalTreesForContrast = 20

    /// The minimum number of a species' own trees nearby before its divergence is spoken.
    ///
    /// **NOT SPECIFIED.** One tree of a rare species near the reader can be 100% of a five-tree
    /// sample; this keeps card 1 from turning a single planting into a claim about the street. Below
    /// `AlmanacThresholds.minimumObservers` (3, A8's own floor for a headcount) deliberately, because
    /// this counts trees rather than people and a tree count of three is a real, checkable fact in a
    /// way three distinct visitors is a privacy floor.
    public static let minimumLocalSpeciesCount = 3

    /// How many percentage points a local share must lead the city's before card 1 calls it "markedly
    /// more common".
    ///
    /// **NOT SPECIFIED.** Five points is enough that the sentence survives rounding noise between two
    /// independently-rounded percentages (`AlmanacCopy.percent` rounds each to the nearest point) and
    /// small enough to still catch the kind of block-scale planting pattern — one species along one
    /// street — that is card 1's whole reason to exist.
    public static let minimumDivergencePoints = 5.0

    /// How many divergent species card 1 names.
    ///
    /// SCREENS.md draws no mock for this card (it does not exist there) — the owner's brief asks for
    /// "two or three", and three is `AlmanacMetrics.compositionNamedRows`'s own number: the same cap
    /// the composition card already uses for "the most common", applied here to "the most different".
    public static let maximumDivergentSpecies = 3
}

// MARK: - Default

public extension CypressAPI {
    /// An implementation with no city inventory behind it resolves no city, and therefore has no
    /// findings — the same shape `almanac(near:)`'s default takes, and for the same reason: this is a
    /// true statement about such an implementation rather than a placeholder.
    func city(near coordinate: Coordinate?) async throws -> CityAlmanac { .empty }
}
