//
//  MapGeography.swift
//  Cypress — Features/Map
//
//  The adapters between `Core`'s CoreLocation-free geometry and MapKit's. `Core` imports
//  Foundation only (ARCHITECTURE §2), so every `Coordinate` ⇄ `CLLocationCoordinate2D` and
//  `MKCoordinateRegion` ⇄ `BoundingBox` conversion lives here rather than in the domain.
//

import CoreLocation
import Foundation
import MapKit

extension Coordinate {
    var clLocationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

extension BoundingBox {
    init(_ region: MKCoordinateRegion) {
        self.init(
            minLatitude: region.center.latitude - region.span.latitudeDelta / 2,
            maxLatitude: region.center.latitude + region.span.latitudeDelta / 2,
            minLongitude: region.center.longitude - region.span.longitudeDelta / 2,
            maxLongitude: region.center.longitude + region.span.longitudeDelta / 2
        )
    }

    /// Whether this box already covers `other` entirely. The map uses it to answer "is there
    /// anything off-screen I have not fetched yet?" without touching the database.
    ///
    /// (The inverse conversion — box to region — is on `MKCoordinateRegion` below.)
    func contains(_ other: BoundingBox) -> Bool {
        minLatitude <= other.minLatitude && maxLatitude >= other.maxLatitude
            && minLongitude <= other.minLongitude && maxLongitude >= other.maxLongitude
    }

    /// Grows the box by `fraction` of its own size on each axis, so a fetch covers a little more
    /// than the screen and a small pan does not immediately blank the map.
    func expanded(by fraction: Double) -> BoundingBox {
        let latitudePad = (maxLatitude - minLatitude) * fraction
        let longitudePad = (maxLongitude - minLongitude) * fraction
        return BoundingBox(
            minLatitude: minLatitude - latitudePad,
            maxLatitude: maxLatitude + latitudePad,
            minLongitude: minLongitude - longitudePad,
            maxLongitude: maxLongitude + longitudePad
        )
    }
}

extension MKCoordinateRegion {

    /// A fitted box, as MapKit's own camera type.
    ///
    /// **This lived in `PinSetMapView` and its own comment said why**: `MapGeography` converted a
    /// region into a box, which was the only direction screen 01 needed, and adding the inverse to
    /// a shared file for one screen's single use would have been surface bought for nothing. That
    /// stopped being true when screen 01 gained a fitted camera of its own (the Journal's `See them
    /// all on the map` link) — there are two callers now, on two screens, and the conversion is the
    /// same arithmetic in both.
    init(_ box: BoundingBox) {
        self.init(
            center: CLLocationCoordinate2D(
                latitude: (box.minLatitude + box.maxLatitude) / 2,
                longitude: (box.minLongitude + box.maxLongitude) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: box.maxLatitude - box.minLatitude,
                longitudeDelta: box.maxLongitude - box.minLongitude
            )
        )
    }
}

// MARK: - Zoom

/// Web-mercator zoom, the number A1 is expressed in.
///
/// MapKit's SwiftUI camera reports a span, not a zoom, so the number has to be recovered:
/// at zoom `z` the whole world is `256 · 2^z` points wide, so a view `w` points wide showing
/// `Δlon` degrees satisfies `256 · 2^z · (Δlon / 360) = w`.
///
/// A1 (BUILD-PLAN §11) turns on clustering at ≤ 15 and individual pins at ≥ 16, and
/// `MapViewport.shouldCluster` is the only place that comparison is made — this function only has
/// to hand it an honest integer.
enum MapZoom {
    static let tileSize: Double = 256
    /// Below this the whole world is on screen; above it MapKit stops zooming in.
    static let range: ClosedRange<Int> = 1...21

    static func level(longitudeDelta: Double, viewWidth: Double) -> Int {
        guard longitudeDelta > 0, viewWidth > 0 else { return range.upperBound }
        let zoom = log2(360 * viewWidth / (tileSize * longitudeDelta))
        guard zoom.isFinite else { return range.upperBound }
        return min(max(Int(zoom.rounded(.down)), range.lowerBound), range.upperBound)
    }

    /// The inverse, for driving the camera to a chosen zoom (tapping a cluster).
    static func longitudeDelta(zoom: Int, viewWidth: Double) -> Double {
        360 * viewWidth / (tileSize * pow(2, Double(zoom)))
    }
}

// MARK: - Bearing

/// The `NE` in the tree card's `6 m NE`. Eight points, initial great-circle bearing.
enum CompassPoint {
    static let names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

    static func from(_ origin: Coordinate, to destination: Coordinate) -> String {
        let lat1 = origin.latitude * .pi / 180
        let lat2 = destination.latitude * .pi / 180
        let deltaLongitude = (destination.longitude - origin.longitude) * .pi / 180
        let y = sin(deltaLongitude) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLongitude)
        let degrees = (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        let index = Int((degrees / 45).rounded()) % names.count
        return names[index]
    }
}
