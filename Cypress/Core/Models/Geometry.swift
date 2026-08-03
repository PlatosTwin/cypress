import Foundation

/// A WGS-84 (EPSG:4326) point.
///
/// Deliberately not `CLLocationCoordinate2D`: `Core` imports Foundation only (ARCHITECTURE §2), so
/// the domain layer stays free of CoreLocation and MapKit. Adapters live in `Data`/`Features`.
public struct Coordinate: Hashable, Codable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Great-circle distance in metres. Used for the "what tree is this?" shortlist ordering and
    /// the 10 m add-a-tree proximity dedupe (BUILD-PLAN §6).
    public func distance(to other: Coordinate) -> Double {
        let earthRadiusM = 6_371_008.8
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let dLat = (other.latitude - latitude) * .pi / 180
        let dLon = (other.longitude - longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadiusM * atan2(sqrt(a), sqrt(1 - a))
    }

    /// Public photo locations snap to a universal 25 m grid — everywhere, not only near residential
    /// parcels (A7, BUILD-PLAN §10). Tree pins themselves stay exact; this is only for photos.
    public func snappedToPublicPhotoGrid() -> Coordinate {
        let cell = Coordinate.publicPhotoGridM
        let metersPerDegreeLat = 111_320.0
        let metersPerDegreeLon = metersPerDegreeLat * cos(latitude * .pi / 180)
        let latStep = cell / metersPerDegreeLat
        let lonStep = metersPerDegreeLon > 1 ? cell / metersPerDegreeLon : latStep
        return Coordinate(
            latitude: (latitude / latStep).rounded() * latStep,
            longitude: (longitude / lonStep).rounded() * lonStep
        )
    }

    /// 25 m snap-to-grid for published photo locations (BUILD-PLAN §10).
    public static let publicPhotoGridM: Double = 25
}

/// A closed linear ring of coordinates. First and last point are expected to coincide.
public struct LinearRing: Hashable, Codable, Sendable {
    public var coordinates: [Coordinate]
    public init(coordinates: [Coordinate]) { self.coordinates = coordinates }
}

public struct Polygon: Hashable, Codable, Sendable {
    public var exterior: LinearRing
    public var holes: [LinearRing]

    public init(exterior: LinearRing, holes: [LinearRing] = []) {
        self.exterior = exterior
        self.holes = holes
    }
}

/// `geometry(MultiPolygon)` for neighborhoods (BUILD-PLAN §4).
public struct MultiPolygon: Hashable, Codable, Sendable {
    public var polygons: [Polygon]
    public init(polygons: [Polygon]) { self.polygons = polygons }
}

/// Half-open integer range mirroring Postgres `int4range` (BUILD-PLAN §4, `dbh_city_cm_range`).
///
/// The city seed's DBH is a range, never a point, and must never be rendered as a measured value.
public struct IntRange: Hashable, Codable, Sendable {
    /// Inclusive lower bound.
    public let lowerBound: Int
    /// Exclusive upper bound, matching Postgres `[)` range semantics.
    public let upperBound: Int

    public init?(lowerBound: Int, upperBound: Int) {
        guard upperBound > lowerBound else { return nil }
        self.lowerBound = lowerBound
        self.upperBound = upperBound
    }

    public func contains(_ value: Int) -> Bool {
        value >= lowerBound && value < upperBound
    }
}
