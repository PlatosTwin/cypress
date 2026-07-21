//
//  MapLocationProvider.swift
//  Cypress — Features/Map
//
//  When-in-use location for screen 01. The purpose string is already in `Info.plist`
//  (`NSLocationWhenInUseUsageDescription`); this type only decides *when* the sheet is asked for
//  and what the map does with each answer.
//
//  BUILD-PLAN §9 lists three of the four states as required work, not as a happy path:
//  the ask, the **denied** state, and **map without location**. They are modelled here as
//  `Availability` so the view switches on one value rather than on a pile of booleans.
//

import CoreLocation
import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class MapLocationProvider {

    /// What the map can do about the user right now.
    enum Availability: Equatable {
        /// The sheet has not been shown yet. The map draws without a GPS dot until it is answered.
        case notAsked
        /// Asked, awaiting the first fix. Still "map without location" as far as drawing goes.
        case waitingForFix
        /// A fix. The GPS dot draws and the tree card can carry a distance.
        case located(Coordinate)
        /// The user said no, or a profile/parental restriction said no for them (BUILD-PLAN §9).
        case denied
        /// Location Services are off device-wide. Same drawing as `denied`, different copy.
        case servicesOff

        /// Both of the states screen 01 has to keep working through.
        var isRefused: Bool { self == .denied || self == .servicesOff }

        var coordinate: Coordinate? {
            if case let .located(coordinate) = self { return coordinate }
            return nil
        }
    }

    private(set) var availability: Availability = .notAsked
    private(set) var authorization: CLAuthorizationStatus

    private let manager: CLLocationManager
    private var delegate: Delegate?

    init(manager: CLLocationManager = CLLocationManager()) {
        self.manager = manager
        self.authorization = manager.authorizationStatus
        let delegate = Delegate()
        delegate.onAuthorizationChange = { [weak self] status in
            self?.apply(authorization: status)
        }
        delegate.onLocation = { [weak self] coordinate in
            self?.availability = .located(coordinate)
        }
        self.delegate = delegate
        manager.delegate = delegate
        // A street tree is a doorstep-scale target; anything coarser than `best` cannot tell two
        // trees on the same block apart, which is what screen 02 needs from the same fix.
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        apply(authorization: manager.authorizationStatus)
    }

    /// Called once when the map appears. Only `notDetermined` produces a system sheet; every other
    /// status is already an answer and must not be re-asked (iOS silently no-ops, and pretending
    /// otherwise would put a dead button in the denied state).
    func start() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    /// The only route out of `denied`: iOS never re-presents the sheet, so the honest affordance is
    /// Settings. The view owns the copy; this owns the URL.
    var settingsURL: URL? { URL(string: UIApplication.openSettingsURLString) }

    private func apply(authorization status: CLAuthorizationStatus) {
        authorization = status
        switch status {
        case .notDetermined:
            availability = .notAsked
        case .restricted, .denied:
            // `denied` covers both "you said no" and "Location Services are off device-wide";
            // `CLLocationManager.locationServicesEnabled()` is the only way to tell them apart and
            // it blocks the main thread, so the distinction is drawn from `restricted` instead —
            // which is the profile/parental case and reads the same to the user.
            availability = status == .restricted ? .servicesOff : .denied
        case .authorizedAlways, .authorizedWhenInUse:
            if availability.coordinate == nil { availability = .waitingForFix }
            manager.startUpdatingLocation()
        @unknown default:
            availability = .notAsked
        }
    }

    /// `CLLocationManagerDelegate` has to be an `NSObject`, and `@Observable` has to not be one.
    /// Keeping the delegate separate is cheaper than fighting either constraint.
    private final class Delegate: NSObject, CLLocationManagerDelegate {
        var onAuthorizationChange: (@MainActor (CLAuthorizationStatus) -> Void)?
        var onLocation: (@MainActor (Coordinate) -> Void)?

        func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
            let status = manager.authorizationStatus
            MainActor.assumeIsolated { onAuthorizationChange?(status) }
        }

        func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
            guard let last = locations.last else { return }
            let coordinate = Coordinate(last.coordinate)
            MainActor.assumeIsolated { onLocation?(coordinate) }
        }

        func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
            // A failed fix is not a refusal — it is "map without location" until the next one
            // arrives, which is the state the map already draws. Nothing to do.
        }
    }
}
