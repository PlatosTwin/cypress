//
//  AreaSelection.swift
//  Cypress — Data/API
//
//  **Which area the Journal's two stats segments are about, when it is not the one the reader is
//  standing in.**
//
//  ── The defect this exists to answer ───────────────────────────────────────────────────────────
//  Both segments used to have exactly one answer to "which area": the nearest inventoried tree's.
//  `SpeciesQueries.resolveNeighborhood(near:)` for the almanac, `CityQueries.resolveIDSpace(near:)`
//  for the city. A reader had no say in it and the screen never said where the answer came from, so
//  a fix that was not where the reader was produced a neighborhood name presented as simple fact
//  (tester report F17: "I am nowhere near Castro/upper market … Why does this page seem to default
//  to showing stats for Castro/market?").
//
//  R84 D4 kept the nearest-tree scoping deliberately and left the question open — "whether the
//  Journal's `City` segment and the almanac should now be able to speak about more than the city the
//  reader is standing in is a separate question, and this ruling does not open it". The owner opened
//  it on 2026-08-28. This type is the opening.
//
//  ── Why two enums and not one ──────────────────────────────────────────────────────────────────
//  The two segments select different things out of different tables — a neighborhood is a polygon
//  keyed by `trees.neighborhood_id`, a city is an `id_space` — and they select them independently:
//  a reader may read the almanac for a neighborhood in one city while the City segment still shows
//  the city they are in. One enum with both cases would make that state unrepresentable-looking
//  while remaining perfectly representable, which is worse than two.
//

import Foundation

// MARK: - What the reader picked

/// Which neighborhood the almanac (screen 12) is about.
///
/// `.here` is the shipping behavior, unchanged and still the default: resolve through the nearest
/// inventoried tree. It is deliberately **not** spelled as `neighborhood(id:) ?? nearest` — a `nil`
/// selection and a chosen area are different states and the screen says different things about
/// them, which is the distinction `AlmanacModel.Phase` already keeps for a different pair.
public enum AreaSelection: Hashable, Sendable {

    /// Resolve from the reader's own fix, as the screen always has.
    case here

    /// A neighborhood the reader chose, keyed as `trees.neighborhood_id` keys it.
    ///
    /// The id and not the name: the name is the seed's and comes back on the payload
    /// (`AlmanacArea.named`), so there is one string and the header cannot disagree with the read.
    case neighborhood(id: Int)

    /// Whether this selection is the reader's own surroundings.
    public var isHere: Bool { self == .here }
}

/// Which city the Journal's `City` segment is about. `.here` is the shipping behavior.
public enum CitySelection: Hashable, Sendable {

    /// Resolve from the reader's own fix, as the segment always has.
    case here

    /// A city the reader chose, keyed by `trees.id_space` — the same key every citywide read in
    /// `CityQueries` already predicates on, so nothing about how a count is computed changes.
    case city(idSpace: String)

    public var isHere: Bool { self == .here }
}

// MARK: - How the payload got its area

/// Whether the area a payload describes was resolved from the reader's fix or chosen by the reader.
///
/// **Carried on the payload rather than remembered by the view**, for `AlmanacModel
/// .displayedCoordinate`'s reason: the selection the model holds and the area the screen is
/// currently drawing are one read apart, and a screen that took the provenance from the selection
/// would label the old area with the new area's provenance for exactly that long.
public enum AreaResolution: Hashable, Sendable {

    /// The nearest inventoried tree to the reader's own fix decided it.
    case fromFix

    /// The reader chose it. Every block that is a fact about *the reader* rather than about the
    /// place is withheld in this state — see `LocalAPI.almanac(near:in:)`.
    case picked
}

// MARK: - What there is to pick from

/// One neighborhood the reader may choose, with the size of the record behind it.
///
/// `treeCount` is the standing-tree count the almanac's own composition card would print for this
/// area — not a second, differently-derived number. It is on the row because a list of 41 names is
/// a list of 41 identical-looking things, and the count is the one fact that distinguishes them
/// without inventing anything (DECISIONS constraint 15).
public struct NeighborhoodChoice: Identifiable, Hashable, Sendable {
    public let id: Int
    public let name: String
    public let treeCount: Int

    public init(id: Int, name: String, treeCount: Int) {
        self.id = id
        self.name = name
        self.treeCount = treeCount
    }
}

/// One city the reader may choose.
///
/// `id` is `trees.id_space`. `name` is `dim_city.display_name` joined through `id_spaces.city_id`
/// — the seed's own civic name, never composed from the id space's key and never from
/// `inventories.name`, which names the *inventory* ("City of San Jose Street Tree inventory") and
/// not the city. `CityQueries`'s header says no city name exists; that stopped being true at seed
/// schema 16, and this is the row that reads it.
public struct CityChoice: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let treeCount: Int

    public init(id: String, name: String, treeCount: Int) {
        self.id = id
        self.name = name
        self.treeCount = treeCount
    }
}

/// Everything the two pickers can offer, read together.
///
/// **The live inventories only** — the bundled seed plus every downloaded pack currently in the
/// union (R84 decision 1), which is exactly the set the map draws and the set the Cities screen
/// lists as installed. A city whose pack is not on the phone has no rows to aggregate, so offering
/// it would be offering a screen that could only say nothing.
public struct AreaChoices: Hashable, Sendable {

    /// Every neighborhood any live inventory carries, most trees first.
    public let neighborhoods: [NeighborhoodChoice]

    /// Every city any live inventory carries, most trees first.
    public let cities: [CityChoice]

    public init(neighborhoods: [NeighborhoodChoice] = [], cities: [CityChoice] = []) {
        self.neighborhoods = neighborhoods
        self.cities = cities
    }

    /// What an implementation with no inventory behind it truthfully has.
    public static let none = AreaChoices()

    /// Whether either picker has anything to offer. A segment with nothing to pick from draws no
    /// affordance at all — a button that opens an empty list is worse than no button, the judgment
    /// `GroveTabRow` already made about its two inert pills.
    public var isEmpty: Bool { neighborhoods.isEmpty && cities.isEmpty }
}

// MARK: - Default

public extension CypressAPI {
    /// An implementation with no inventory behind it has nothing to offer either picker — the same
    /// shape `almanac(near:in:)`'s and `city(near:in:)`'s defaults take, and a true statement about
    /// such an implementation rather than a placeholder.
    func areaChoices() async throws -> AreaChoices { .none }
}
