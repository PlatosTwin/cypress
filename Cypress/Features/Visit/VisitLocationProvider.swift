//
//  VisitLocationProvider.swift
//  Cypress — Features/Visit
//
//  Where the phone thinks it is, and — the part D6 actually cares about — how sure it is.
//
//  ── Naming ────────────────────────────────────────────────────────────────────────────────
//  ARCHITECTURE §3 anticipates one shared `LocationProvider` in the environment from the
//  composition root. That root is not this feature's to write, and the map feature is being built
//  in parallel. This type is deliberately named for the visit flow so the two cannot collide;
//  when the shared service lands, this becomes an adapter or is deleted, and only
//  `VisitIdentifyModel` changes.
//

import CoreLocation
import Foundation
import Observation

@MainActor
@Observable
final class VisitLocationProvider {

    /// The fix, as far as the flow is concerned.
    enum Fix: Equatable {
        /// Nothing yet — permission is being asked for, or the first fix has not arrived.
        case pending
        /// The user refused, or location is off device-wide. Screen 02 has a designed state for
        /// this (BUILD-PLAN §9, "map without location" / the low-GPS shortlist).
        case denied
        case located(Coordinate, accuracyM: Double)

        var coordinate: Coordinate? {
            if case let .located(coordinate, _) = self { return coordinate }
            return nil
        }

        var accuracyM: Double? {
            if case let .located(_, accuracy) = self { return accuracy }
            return nil
        }
    }

    private(set) var fix: Fix = .pending

    private let manager = CLLocationManager()
    private var delegate: Delegate?

    init() {
        let delegate = Delegate { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        self.delegate = delegate
        manager.delegate = delegate
        // Street trees sit 6–10 m apart (D6). Anything coarser than "best" is asking the ranking to
        // fail; anything finer does not exist.
        manager.desiredAccuracy = kCLLocationAccuracyBest
        // A volunteer standing at a kerb moves a metre at a time. Updating on every metre keeps the
        // shortlist honest as they step around the trunk, without a continuous stream.
        manager.distanceFilter = 1
    }

    /// Asks for when-in-use permission if it has not been asked for, then starts updating.
    func start() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            fix = .denied
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        @unknown default:
            fix = .denied
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    private func handle(_ event: Delegate.Event) {
        switch event {
        case let .authorization(status):
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                if case .denied = fix { fix = .pending }
                manager.startUpdatingLocation()
            case .denied, .restricted:
                fix = .denied
            case .notDetermined:
                fix = .pending
            @unknown default:
                fix = .denied
            }

        case let .location(location):
            // A negative accuracy means CoreLocation could not work one out. Treating it as `nil`
            // rather than as a number is what keeps `VisitShortlist` on its pessimistic default
            // instead of unlocking the no-confirmation path on a fix that has no error bar at all.
            let accuracy = location.horizontalAccuracy
            fix = .located(
                Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude),
                accuracyM: accuracy >= 0 ? accuracy : VisitShortlist.assumedAccuracyM
            )

        case .failed:
            // A transient failure is not a refusal. Keep whatever fix we had; if there was none,
            // stay pending — the screen's low-GPS copy already covers "we cannot narrow this down".
            if case .pending = fix { fix = .pending }
        }
    }

    // MARK: - Delegate

    /// CoreLocation still wants an NSObject delegate. Kept separate so the provider itself can be
    /// `@MainActor @Observable` without fighting the callbacks' isolation.
    private final class Delegate: NSObject, CLLocationManagerDelegate {
        enum Event {
            case authorization(CLAuthorizationStatus)
            case location(CLLocation)
            case failed
        }

        private let onEvent: (Event) -> Void

        init(onEvent: @escaping (Event) -> Void) {
            self.onEvent = onEvent
        }

        func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
            onEvent(.authorization(manager.authorizationStatus))
        }

        func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
            guard let latest = locations.last else { return }
            onEvent(.location(latest))
        }

        func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
            onEvent(.failed)
        }
    }
}
