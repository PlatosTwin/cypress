import Foundation

/// **What the almanac is about, as a `WHERE` clause** — RULINGS R29, ERRATA E182.
///
/// Every read in `AlmanacQueries` used to take a `neighborhoodID: Int` and say
/// `t.neighborhood_id = :neighborhood`. That is San Francisco's 41 Analysis Neighborhoods and
/// nothing else, so with a second city in the seed all 52,788 San Jose rows carry
/// `neighborhood_id IS NULL` and are invisible to screen 12 and to the coverage panel — the app's
/// only directed ask (D1). E176 recorded the hole and declined to make the product decision; R29
/// makes it.
///
/// **R29 in one sentence: a named polygon where the merged record holds one, a stated radius where
/// it does not.** The two cases below are that ruling, and they are deliberately not
/// interchangeable:
///
/// - `.neighborhood` is a *place*. Its boundary is the city's, it has a name a reader recognizes,
///   and — the property a radius cannot have — it is the **same area for everybody standing in
///   it**, so "the elder" and "nine young trees" are statements about a place rather than about
///   where one person happens to be.
/// - `.radius` is a *distance*, and the screen says so rather than dressing it as a place
///   (`AlmanacCopy.radiusPill`). It needs no per-city asset, which is what makes it the right
///   default under D16: the destination is every municipal inventory in the country merged into one
///   format, and a geography that requires a polygon set per city makes a city's trees invisible
///   until somebody sources one.
///
/// Under D16 the compounding cost is not even the main objection to polygons-everywhere. It is that
/// the *unit* would differ city by city — San Francisco publishes 41 statistical Analysis
/// Neighborhoods, San Jose publishes council districts that are redrawn every ten years, most cities
/// publish nothing — and presenting all of them under one word would reintroduce at the polygon
/// level exactly the seam D16's normalized format removes at the tree level.
///
/// The bindings are prefixed `:area…` so a scope can be dropped into a query that already binds
/// `:lat`, `:lon` or `:limit` of its own without colliding — `vacantSites` does exactly that.
public enum AlmanacScope: Hashable, Sendable {

    /// A polygon the seed carries, keyed by `trees.neighborhood_id`.
    case neighborhood(id: Int, name: String)

    /// Everything within `meters` of the reader.
    ///
    /// The predicate is a bounding box (which uses `idx_trees_lat_lon`) narrowed by the same
    /// squared-distance test `TreeQueries.nearest` and `SpeciesQueries.resolveNeighborhood` use:
    /// no `sqrt`, no per-row trigonometry, and monotonically identical to true distance at this
    /// size. The box alone would make the area a *square*, and a square whose corners reach 1.41×
    /// the stated distance is a different claim from the one the pill makes.
    case radius(center: Coordinate, meters: Double)

    /// How the area describes itself to the screen.
    public var area: AlmanacArea {
        switch self {
        case let .neighborhood(_, name): .named(name)
        case let .radius(_, meters): .radius(meters: meters)
        }
    }

    /// The `WHERE` fragment, for a `seed.trees` row aliased `alias`.
    func predicate(_ alias: String) -> String {
        switch self {
        case .neighborhood:
            return "\(alias).neighborhood_id = :areaNeighborhood"
        case .radius:
            return """
            \(alias).lat BETWEEN :areaMinLat AND :areaMaxLat
                           AND \(alias).lon BETWEEN :areaMinLon AND :areaMaxLon
                           AND ((\(alias).lat - :areaLat) * (\(alias).lat - :areaLat)
                                + (\(alias).lon - :areaLon) * (\(alias).lon - :areaLon) * :areaLonWeight)
                               <= :areaRadiusSquared
            """
        }
    }

    /// Exactly the parameters `predicate(_:)` names, and no others: `bind(_:forName:)` throws on a
    /// name the statement does not carry, which is what keeps these two in step.
    var bindings: [String: SQLiteBindable?] {
        switch self {
        case let .neighborhood(id, _):
            return [":areaNeighborhood": id]
        case let .radius(center, meters):
            let box = BoundingBox(around: center, radiusM: meters)
            // Degrees of latitude, so the comparison happens in the same units the columns are in.
            let radiusDegrees = meters / Self.metersPerDegreeLatitude
            return [
                ":areaMinLat": box.minLatitude,
                ":areaMaxLat": box.maxLatitude,
                ":areaMinLon": box.minLongitude,
                ":areaMaxLon": box.maxLongitude,
                ":areaLat": center.latitude,
                ":areaLon": center.longitude,
                ":areaLonWeight": pow(cos(center.latitude * .pi / 180), 2),
                ":areaRadiusSquared": radiusDegrees * radiusDegrees
            ]
        }
    }

    /// `BoundingBox(around:radiusM:)`'s own constant, repeated here because the squared-distance
    /// bound has to be expressed in the same degrees the box is.
    private static let metersPerDegreeLatitude = 111_320.0
}
