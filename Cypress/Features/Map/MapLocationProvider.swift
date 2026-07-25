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
        /// A fix, with how much to trust it. The GPS dot draws and the tree card carries a distance.
        ///
        /// The accuracy rides along even though nothing on the map reads it, because a fix that
        /// arrives without one cannot be recovered later. D6 excludes readings worse than 15m from
        /// growth charting and treats a missing accuracy as unusable, so a provider that drops the
        /// number silently empties every chart built on top of it — a failure that would present as
        /// a charting bug and be hunted in the wrong file entirely.
        case located(Coordinate, accuracyM: Double)
        /// The user said no, or a profile/parental restriction said no for them (BUILD-PLAN §9).
        case denied
        /// Location Services are off device-wide. Same drawing as `denied`, different copy.
        case servicesOff

        /// Both of the states screen 01 has to keep working through.
        var isRefused: Bool { self == .denied || self == .servicesOff }

        var coordinate: Coordinate? {
            if case let .located(coordinate, _) = self { return coordinate }
            return nil
        }

        var accuracyM: Double? {
            if case let .located(_, accuracy) = self { return accuracy }
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
        delegate.onLocation = { [weak self] coordinate, accuracyM in
            self?.availability = .located(coordinate, accuracyM: accuracyM)
            #if DEBUG
            MapFrameProbe.shared.noteLocationPublish()
            #endif
        }
        self.delegate = delegate
        manager.delegate = delegate
        // A street tree is a doorstep-scale target; anything coarser than `best` cannot tell two
        // trees on the same block apart, which is what screen 02 needs from the same fix.
        manager.desiredAccuracy = kCLLocationAccuracyBest
        // Every fix writes `availability`, and `availability` is read by screen 01's basemap — so a
        // walk re-runs the map's whole `MapContent` builder every 5 m. Coarsening this was looked at
        // as part of ERRATA E130's performance work and **declined twice over**: the pin layer is now
        // a few hundred annotations rather than 1,300 and re-running the builder over an array that
        // has not changed costs nothing SwiftUI cannot diff away, and the thing being traded is the
        // freshness of the one fix screen 02 identifies a tree from, where 5 m is the difference
        // between two trees on the same block. If the invalidation ever does cost something, the fix
        // is to move the dot out of the pin layer, not to make the fix worse.
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
        var onLocation: (@MainActor (Coordinate, Double) -> Void)?

        func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
            let status = manager.authorizationStatus
            MainActor.assumeIsolated { onAuthorizationChange?(status) }
        }

        func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
            guard let last = locations.last else { return }
            let coordinate = Coordinate(last.coordinate)
            // A negative horizontalAccuracy means CoreLocation could not work one out. Substituting
            // the pessimistic constant rather than nil is the rule VisitLocationProvider already
            // follows, and one rule in the codebase beats two: at 25m it sits the wrong side of
            // D6's 15m gate, so an unknown fix is excluded from charting by arithmetic instead of
            // by a special case someone has to remember.
            let accuracy = last.horizontalAccuracy
            let effective = accuracy >= 0 ? accuracy : VisitShortlist.assumedAccuracyM
            MainActor.assumeIsolated { onLocation?(coordinate, effective) }
        }

        func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
            // A failed fix is not a refusal — it is "map without location" until the next one
            // arrives, which is the state the map already draws. Nothing to do.
        }
    }
}
