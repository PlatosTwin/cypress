//
//  MapLocationProvider.swift
//  Cypress — Features/Map
//
//  When-in-use location for screen 01. The purpose string is already in `Info.plist`
//  (`NSLocationWhenInUseUsageDescription`); this type only decides *when* the sheet is asked for
//  and what the map does with each answer.
//
//  BUILD-PLAN §9 lists three of the four states as required work, not as a happy path:
//  the ask, the **denied** state, and **map without location**. They are modeled here as
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

    /// Which way the reader is facing, in degrees clockwise from **true** north, or `nil` for
    /// "nobody knows" (task #155).
    ///
    /// Separate from `availability` rather than a sixth case or a payload on `.located`, because the
    /// two answer different questions and change at different rates. `availability` is what the app
    /// records against a check-in, a measurement and a visit; a bearing is not part of any of those,
    /// and folding it in would rewrite the fix — and everything watching it — every time the reader
    /// turned on the spot. `nil` is a state the map draws (the bare dot), not an error.
    private(set) var headingDegrees: Double?

    private let manager: CLLocationManager
    private var delegate: Delegate?

    /// Whether anybody has actually asked this provider for fixes.
    ///
    /// **It exists because `init` used to start a GPS session on its own**, through
    /// `apply(authorization:)`, and a SwiftUI `@State` default expression is re-evaluated on every
    /// initialization of the view that declares it — so screen 01 was constructing a fresh
    /// `CLLocationManager` and starting it around fifty times a second (measured: 336 instances in
    /// seven seconds). `RootView`'s own comment says of its provider "it is never `start()`ed here,
    /// and that is deliberate", and that sentence has been false since it was written: on a device
    /// where permission was already granted, construction started updating immediately.
    ///
    /// Now construction configures and answers questions; `start()` is the only thing that opens a
    /// session. A provider nobody asked is inert, which is what makes a stray one harmless.
    private var hasStarted = false

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
        delegate.onHeading = { [weak self] heading in
            self?.publish(heading: heading)
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
        // CoreLocation's own version of the gate `publish(heading:)` keeps below. Asked for as well
        // as enforced, for the reason the comment above records about `distanceFilter`: a filter
        // this app has measured being ignored is a filter it cannot rely on alone.
        manager.headingFilter = MapHeading.publishDegrees
        apply(authorization: manager.authorizationStatus)
    }

    #if DEBUG
    /// A provider pinned to one availability, which never talks to CoreLocation (task #121).
    ///
    /// `VisitLocationProvider(pinnedFix:)` is the same seam for the same reason one screen over, and
    /// this is deliberately shaped like it: no delegate is attached, so nothing CoreLocation has to
    /// say can arrive; `start()` and `stop()` are no-ops, so nothing here can raise a permission
    /// sheet or move a fix out from under a test. `#if DEBUG`, so it does not exist in a shipping
    /// build — see `.measurements/` for how E117 proved the same of `DebugDeepLink`.
    ///
    /// **`authorization` is derived rather than asked for**, because the two are not independent:
    /// `.denied` with an `authorizedWhenInUse` status is not a state iOS can be in, and a seam that
    /// let a test construct one would be a seam for testing states the app will never see.
    ///
    /// The `CLLocationManager` is still constructed and still configured, because the alternative is
    /// making `manager` optional and adding a `nil` branch to every use of it on the shipping path —
    /// a change to production code to serve a test double, which is the wrong direction. It has no
    /// delegate and is never started, so it does nothing.
    init(pinnedAvailability: Availability) {
        self.manager = CLLocationManager()
        self.availability = pinnedAvailability
        switch pinnedAvailability {
        case .notAsked:                     self.authorization = .notDetermined
        case .denied:                       self.authorization = .denied
        case .servicesOff:                  self.authorization = .restricted
        case .waitingForFix, .located:      self.authorization = .authorizedWhenInUse
        }
        self.isPinned = true
    }
    #endif

    /// Whether this provider is a pinned double. Always `false` in a shipping build.
    private var isPinned = false

    /// Called once when the map appears. Only `notDetermined` produces a system sheet; every other
    /// status is already an answer and must not be re-asked (iOS silently no-ops, and pretending
    /// otherwise would put a dead button in the denied state).
    func start() {
        // A pinned provider (task #121) is the whole answer already; asking CoreLocation anything
        // here would raise the system sheet the pin exists to make unnecessary.
        if isPinned { return }
        hasStarted = true
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
        if isPinned { return }
        hasStarted = false
        manager.stopUpdatingLocation()
        stopHeading()
    }

    // MARK: - The magnetometer (task #155)

    /// **Started and stopped separately from the fix, and that asymmetry is the answer to the
    /// question the ticket asks.**
    ///
    /// The GPS session is deliberately never stopped when screen 01 goes away: one provider is
    /// shared with screens 09, 12, 16 and the whole visit flow, and stopping it on the map's way to
    /// a tree profile would take the accuracy out from under the record being written there
    /// (`MapHomeView`'s own note says so). The heading has no such reader. Exactly one surface in
    /// this app draws a cone, so the magnetometer can be scoped to the screen that draws it without
    /// anybody else noticing, and a sensor nobody is reading is a sensor that should be off.
    ///
    /// That is a scope argument, not a measurement: **the power cost of `startUpdatingHeading` has
    /// not been measured here and cannot be**, because no simulator has a magnetometer to spin up.
    /// The gate is cheap, reversible and costs nothing if the cost turns out to be nil.
    ///
    /// `headingAvailable()` is asked because a device without a magnetometer answers no — and every
    /// simulator answers no, which is why nothing in this file can be seen working on one.
    func startHeading() {
        if isPinned { return }
        guard CLLocationManager.headingAvailable() else { return }
        manager.startUpdatingHeading()
    }

    /// Stops the magnetometer **and forgets the last heading**, which is the point rather than
    /// tidiness: a cone left pointing wherever the reader last stood is the confident wrong answer
    /// that `MapHeading.usable` refuses one line at a time.
    func stopHeading() {
        if isPinned { return }
        manager.stopUpdatingHeading()
        headingDegrees = nil
    }

    /// The only route out of `denied`: iOS never re-presents the sheet, so the honest affordance is
    /// Settings. The view owns the copy; this owns the URL.
    var settingsURL: URL? { URL(string: UIApplication.openSettingsURLString) }

    // MARK: - Publishing a fix

    /// How far the reader has to have actually moved before `availability` is rewritten.
    ///
    /// **This is `distanceFilter`'s own promise, kept.** `manager.distanceFilter = 5` says "do not
    /// tell me until I have moved five meters", and on a device driving a simulated route it is
    /// simply not honored: measured at a walking 4 m/s, CoreLocation delivered **24 to 42 fixes a
    /// second**, one every fifteen centimeters. Every one of them wrote `availability`; every write
    /// re-ran screen 01's whole basemap body; and the map sat at under 2 fps with nobody touching it.
    /// A static `simctl location` fires the delegate once and never again, which is exactly why two
    /// rounds of simulator measurement never saw this.
    ///
    /// Five meters rather than some smaller number that would also have fixed the frame rate,
    /// because five meters is a *decision this file already made* and the point is to make it true
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
    /// first fix happened to say would be feeding that gate a stale number. One meter is finer than
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

    /// The one place `headingDegrees` is written.
    ///
    /// A heading that has *become* unusable is published immediately — that is the fallback to the
    /// bare dot and it must not wait for a five-degree turn that a stationary reader will never
    /// make. A heading that has merely moved a little is dropped, for the churn reason
    /// `MapHeading.publishDegrees` records.
    private func publish(heading: Double?) {
        guard let heading else {
            headingDegrees = nil
            return
        }
        guard MapHeading.isWorthPublishing(heading, over: headingDegrees) else { return }
        headingDegrees = heading
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
            // Only if somebody asked. This is the authorization *callback* as well as the
            // constructor's own call, and answering "you are allowed" with "then I shall start"
            // is right in the first case and is the fifty-sessions-a-second defect in the second.
            if hasStarted { manager.startUpdatingLocation() }
        @unknown default:
            availability = .notAsked
        }
    }

    /// `CLLocationManagerDelegate` has to be an `NSObject`, and `@Observable` has to not be one.
    /// Keeping the delegate separate is cheaper than fighting either constraint.
    private final class Delegate: NSObject, CLLocationManagerDelegate {
        var onAuthorizationChange: (@MainActor (CLAuthorizationStatus) -> Void)?
        var onLocation: (@MainActor (Coordinate, Double) -> Void)?
        /// A heading, or `nil` for one that cannot be trusted. See `MapHeading.usable`.
        var onHeading: (@MainActor (Double?) -> Void)?

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

        func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
            let usable = MapHeading.usable(
                trueHeading: newHeading.trueHeading,
                accuracyDegrees: newHeading.headingAccuracy
            )
            MainActor.assumeIsolated { onHeading?(usable) }
        }

        /// **No figure-of-eight.** Answering `true` here lets iOS put its own full-screen
        /// calibration HUD over whatever the app is showing, uninvited, whenever it decides the
        /// magnetometer needs work — on a screen whose job is to show the reader a tree in front of
        /// them. This app's answer to a heading it cannot trust is to stop drawing one
        /// (`MapHeading.usable`), which needs nothing from the reader and interrupts nothing.
        func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
            false
        }

        func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
            // A failed fix is not a refusal — it is "map without location" until the next one
            // arrives, which is the state the map already draws. Nothing to do.
        }
    }
}
