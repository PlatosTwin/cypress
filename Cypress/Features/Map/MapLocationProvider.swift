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
            self?.publish(coordinate: coordinate, accuracyM: accuracyM)
        }
        self.delegate = delegate
        manager.delegate = delegate
        // A street tree is a doorstep-scale target; anything coarser than `best` cannot tell two
        // trees on the same block apart, which is what screen 02 needs from the same fix.
        manager.desiredAccuracy = kCLLocationAccuracyBest
        // **Unchanged, and it is the accuracy of the fix that is being protected here, not its rate.**
        // A street tree is a doorstep-scale target and 5 m is the difference between two trees on the
        // same block, which is what screen 02 identifies one from and what D6 charts growth against.
        // The previous round considered coarsening both of these as a performance measure and
        // declined; that decision stands, and the note it left behind — "if the invalidation ever
        // does cost something, the fix is to move the dot out of the pin layer, not to make the fix
        // worse" — is what `publish(coordinate:accuracyM:)` below and the basemap's own annotation
        // diffing now do instead.
        //
        // What that note got wrong is the premise underneath it: re-running the builder over an
        // unchanged array does *not* cost nothing. Measured, walking, at the opening camera with 167
        // markers on screen and no finger on the glass: **1.3–1.9 fps, worst frame 850 ms**, with the
        // whole of it main-thread time spent rebuilding an annotation layer that had not changed.
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

    // MARK: - Publishing a fix

    /// How far the reader has to have actually moved before `availability` is rewritten.
    ///
    /// **This is `distanceFilter`'s own promise, kept.** `manager.distanceFilter = 5` says "do not
    /// tell me until I have moved five metres", and on a device driving a simulated route it is
    /// simply not honoured: measured at a walking 4 m/s, CoreLocation delivered **24 to 42 fixes a
    /// second**, one every fifteen centimetres. Every one of them wrote `availability`; every write
    /// re-ran screen 01's whole basemap body; and the map sat at under 2 fps with nobody touching it.
    /// A static `simctl location` fires the delegate once and never again, which is exactly why two
    /// rounds of simulator measurement never saw this.
    ///
    /// Five metres rather than some smaller number that would also have fixed the frame rate,
    /// because five metres is a *decision this file already made* and the point is to make it true
    /// rather than to make a new one. Nothing downstream can tell the difference: the fix that
    /// arrives is the same fix, at the same `kCLLocationAccuracyBest`, and the reader's dot on a
    /// 120 m-wide camera moves about sixteen points between publishes.
    static let publishDistanceM: Double = 5

    /// And how much the *accuracy* has to change on its own to be worth a publish, when the reader
    /// has not moved.
    ///
    /// The coordinate is not the only thing on `availability` that matters. `RootView` hands
    /// `accuracyM` to every check-in, measurement and visit it records, and D6 excludes a reading
    /// worse than 15 m from growth charting — so a provider that froze the accuracy at whatever the
    /// first fix happened to say would be feeding that gate a stale number. One metre is finer than
    /// any decision made anywhere on top of it and far coarser than the jitter.
    static let publishAccuracyM: Double = 1

    /// Whether a fix says anything the last published one did not.
    ///
    /// Pure and `static` so the rule can be tested at its boundaries without a `CLLocationManager`,
    /// which cannot be made to produce a fix on demand. The end-to-end path — a delegate callback
    /// reaching `availability` or not — is tested separately by driving `manager.delegate` directly,
    /// because a predicate that is right and not called is the defect this whole entry is about.
    static func isWorthPublishing(
        coordinate: Coordinate,
        accuracyM: Double,
        over previous: Availability
    ) -> Bool {
        guard case let .located(last, lastAccuracy) = previous else { return true }
        return last.distance(to: coordinate) >= publishDistanceM
            || abs(lastAccuracy - accuracyM) >= publishAccuracyM
    }

    /// The one place `availability` is written from a fix.
    private func publish(coordinate: Coordinate, accuracyM: Double) {
        guard Self.isWorthPublishing(
            coordinate: coordinate,
            accuracyM: accuracyM,
            over: availability
        ) else { return }
        availability = .located(coordinate, accuracyM: accuracyM)
        #if DEBUG
        MapFrameProbe.shared.noteLocationPublish()
        #endif
    }

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
