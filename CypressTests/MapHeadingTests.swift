//
//  MapHeadingTests.swift
//  Cypress — CypressTests
//
//  Task #155 — the direction cone on the reader's dot.
//
//  ── Read this before trusting a green run of this file ────────────────────────────────────────
//  **No simulator can produce a heading.** `simctl` sets a location; it has no magnetometer to set,
//  and `CLLocationManager.headingAvailable()` answers `false` on every one of them. So this file
//  cannot and does not claim the cone points where the reader is facing — that is device-only truth
//  and only the owner's phone can settle it.
//
//  What it does claim is everything a machine can actually check: the arithmetic (the short way
//  round a circle, the map's own rotation subtracted off, the churn gate), the fallback to a bare
//  dot when the magnetometer cannot be trusted, and — through the **real** delegate the provider
//  installed, the way `MapLocationChurnTests` insists — that the wiring between the two is
//  connected. A rule that is right and never called is the failure this project keeps paying for.
//

import CoreLocation
import Foundation
import MapKit
import Testing
import UIKit
@testable import Cypress

@MainActor
@Suite("The heading cone on the reader's dot")
struct MapHeadingTests {

    // MARK: - The arithmetic

    @Test("an angle from anywhere lands in one turn")
    func normalizationWraps() {
        #expect(MapHeading.normalized(0) == 0)
        #expect(MapHeading.normalized(359.9) == 359.9)
        #expect(MapHeading.normalized(360) == 0)
        #expect(MapHeading.normalized(361) == 1)
        #expect(MapHeading.normalized(-1) == 359)
        #expect(MapHeading.normalized(-361) == 359)
        #expect(MapHeading.normalized(720 + 45) == 45)
    }

    /// **The one that decides whether the cone turns or spins.** A reader facing north crosses 0°
    /// on every other reading, and plain subtraction calls 359° → 1° a 358° turn — a full backwards
    /// sweep of the cone, visible from across the street, every time they wobble.
    @Test("the way round is the short way, across north as well as anywhere else")
    func shortestDeltaTakesTheShortWay() {
        #expect(MapHeading.shortestDelta(from: 359, to: 1) == 2)
        #expect(MapHeading.shortestDelta(from: 1, to: 359) == -2)
        #expect(MapHeading.shortestDelta(from: 10, to: 40) == 30)
        #expect(MapHeading.shortestDelta(from: 40, to: 10) == -30)
        #expect(MapHeading.shortestDelta(from: 90, to: 90) == 0)
        // The half-turn itself is ambiguous by definition; it is taken forwards, and it is a turn
        // of 180 either way round — never 180 one way and −180 the next, which would jitter.
        #expect(MapHeading.shortestDelta(from: 0, to: 180) == 180)
        #expect(MapHeading.shortestDelta(from: 180, to: 0) == 180)
        for from in stride(from: 0.0, to: 360.0, by: 7) {
            for to in stride(from: 0.0, to: 360.0, by: 11) {
                let delta = MapHeading.shortestDelta(from: from, to: to)
                #expect(
                    abs(delta) <= 180,
                    "\(from)° → \(to)° was reported as \(delta)°, which is the long way round"
                )
                #expect(
                    MapHeading.normalized(from + delta) == MapHeading.normalized(to),
                    "\(from)° turned by \(delta)° does not arrive at \(to)°"
                )
            }
        }
    }

    /// The basemap leaves `isRotateEnabled` on and an `MKAnnotationView` stays square to the screen,
    /// so the cone has to be drawn at the heading **minus the camera's own**. Without this the cone
    /// is right only while the map happens to be north-up.
    @Test("a rotated map turns the cone the other way")
    func theCameraRotationIsSubtracted() {
        #expect(MapHeading.screenAngleDegrees(heading: 90, cameraHeading: 0) == 90)
        // The reader has twisted the map 90° clockwise; north is now to the left of the screen, so
        // a reader facing east is facing straight up it.
        #expect(MapHeading.screenAngleDegrees(heading: 90, cameraHeading: 90) == 0)
        #expect(MapHeading.screenAngleDegrees(heading: 0, cameraHeading: 90) == 270)
        #expect(MapHeading.screenAngleDegrees(heading: 10, cameraHeading: 350) == 20)
    }

    // MARK: - What is not drawn

    /// **The decision this feature turns on.** `headingAccuracy` goes negative when CoreLocation
    /// cannot trust the magnetometer — a car door, a laptop, a speaker magnet — and a cone pointing
    /// confidently the wrong way is worse than no cone in an app whose premise is standing in front
    /// of one specific tree.
    @Test("an untrustworthy reading draws no direction at all")
    func invalidAccuracyIsNoHeading() {
        #expect(MapHeading.usable(trueHeading: 90, accuracyDegrees: -1) == nil)
        #expect(MapHeading.usable(trueHeading: 90, accuracyDegrees: -0.0001) == nil)
        #expect(MapHeading.usable(trueHeading: 90, accuracyDegrees: 0) == 90)
        #expect(MapHeading.usable(trueHeading: 90, accuracyDegrees: 40) == 90)
    }

    /// True north or nothing. `trueHeading` is negative until CoreLocation has a fix to work the
    /// declination out from, and the basemap is drawn against true north — a magnetic fallback in
    /// San Francisco would be a cone quietly 13° off, which is the confident wrong answer the rule
    /// above refuses.
    @Test("a heading with no true north behind it is not drawn")
    func magneticOnlyIsNoHeading() {
        #expect(MapHeading.usable(trueHeading: -1, accuracyDegrees: 5) == nil)
        #expect(MapHeading.usable(trueHeading: 0, accuracyDegrees: 5) == 0)
        #expect(MapHeading.usable(trueHeading: .nan, accuracyDegrees: 5) == nil)
        #expect(MapHeading.usable(trueHeading: 359.5, accuracyDegrees: 5) == 359.5)
    }

    // MARK: - The churn gate

    /// `headingDegrees` is `@Observable` and screen 01 reads it, so a write re-runs that screen's
    /// view tree — the E139 class, arriving down a second channel. A magnetometer reports far faster
    /// than a person turns.
    @Test("a heading that has barely moved is not worth publishing")
    func smallTurnsAreDropped() {
        #expect(MapHeading.isWorthPublishing(90, over: nil), "the first heading always publishes")
        #expect(!MapHeading.isWorthPublishing(92, over: 90))
        #expect(MapHeading.isWorthPublishing(95, over: 90), "the gate is inclusive at its own number")
        #expect(MapHeading.isWorthPublishing(140, over: 90))
    }

    /// And the gate is wrap-aware, which matters most exactly where a reader stands most: a
    /// north–south street. A naive comparison would call 359° → 1° a 358° turn and publish every
    /// reading — the churn this gate exists to stop, at the one bearing it would never help.
    @Test("the gate measures a turn across north as a small turn")
    func theGateWrapsToo() {
        #expect(!MapHeading.isWorthPublishing(1, over: 359))
        #expect(!MapHeading.isWorthPublishing(359, over: 1))
        #expect(MapHeading.isWorthPublishing(6, over: 359))
    }

    /// CoreLocation is asked for the same gate the provider enforces. Both, because this project has
    /// measured `distanceFilter` being ignored on a device (`MapLocationProvider.publishDistanceM`),
    /// and whether `headingFilter` keeps its promise better is not something a simulator can say.
    @Test("the gate and the filter CoreLocation is given are the same number")
    func theFilterMatchesTheGate() {
        let manager = HeadingManager()
        _ = MapLocationProvider(manager: manager)
        #expect(manager.headingFilter == MapHeading.publishDegrees)
        #expect(MapHeading.publishDegrees == 5)
    }

    // MARK: - The wiring, through the real delegate

    /// A `CLLocationManager` that answers "allowed", claims a magnetometer, and counts heading
    /// sessions instead of opening one. Modelled on `MapLocationChurnTests.RecordingManager` — the
    /// thing under test is what the provider *does to a manager*.
    private class HeadingManager: CLLocationManager {
        var headingStarts = 0
        var headingStops = 0

        override class func headingAvailable() -> Bool { true }
        override var authorizationStatus: CLAuthorizationStatus { .authorizedWhenInUse }
        override func startUpdatingLocation() {}
        override func stopUpdatingLocation() {}
        override func startUpdatingHeading() { headingStarts += 1 }
        override func stopUpdatingHeading() { headingStops += 1 }
        override func requestWhenInUseAuthorization() {}
    }

    /// The same manager on a device with no magnetometer — which is every simulator this suite runs
    /// on. A subclass rather than a flag on the one above, so no two tests share a mutable answer.
    private final class MagnetometerlessManager: HeadingManager {
        override class func headingAvailable() -> Bool { false }
    }

    /// `CLHeading` has no public initializer and its properties are read-only, so the readings the
    /// delegate is given are a subclass answering the three numbers the app reads. This is what lets
    /// the tests below go through `MapLocationProvider`'s **own** delegate rather than around it.
    private final class Reading: CLHeading {
        private let trueValue: CLLocationDirection
        private let accuracyValue: CLLocationDirection

        init(trueHeading: CLLocationDirection, accuracy: CLLocationDirection) {
            self.trueValue = trueHeading
            self.accuracyValue = accuracy
            super.init()
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override var trueHeading: CLLocationDirection { trueValue }
        override var magneticHeading: CLLocationDirection { trueValue }
        override var headingAccuracy: CLLocationDirection { accuracyValue }
    }

    private static func deliver(
        trueHeading: CLLocationDirection,
        accuracy: CLLocationDirection,
        to manager: CLLocationManager
    ) {
        manager.delegate?.locationManager?(
            manager,
            didUpdateHeading: Reading(trueHeading: trueHeading, accuracy: accuracy)
        )
    }

    /// The owner installed TestFlight build 7 and reported no direction pointer on the dot;
    /// `startUpdatingHeading` appeared nowhere in the app. This is the sentence that stops it
    /// appearing nowhere again.
    @Test("asking for a heading is what opens the magnetometer, and only that")
    func startHeadingOpensTheSession() {
        let manager = HeadingManager()
        let provider = MapLocationProvider(manager: manager)
        #expect(manager.headingStarts == 0, "constructing a provider must open nothing")
        provider.start()
        #expect(manager.headingStarts == 0, "the fix and the magnetometer start separately")
        provider.startHeading()
        #expect(manager.headingStarts == 1)
    }

    /// A device with no magnetometer — which is every simulator this suite runs on — is asked for
    /// nothing.
    @Test("a device with no magnetometer is not asked for a heading")
    func noMagnetometerNoSession() {
        let manager = MagnetometerlessManager()
        let provider = MapLocationProvider(manager: manager)
        provider.startHeading()
        #expect(manager.headingStarts == 0)
    }

    /// The end-to-end path: a reading through the provider's own delegate reaches the value the map
    /// draws from. Asserted where it is read back, never at the call site.
    @Test("a trustworthy reading reaches the value the map draws")
    func aReadingReachesTheProvider() {
        let manager = HeadingManager()
        let provider = MapLocationProvider(manager: manager)
        provider.start()
        provider.startHeading()
        #expect(provider.headingDegrees == nil, "nothing is known before the first reading")

        Self.deliver(trueHeading: 137.5, accuracy: 12, to: manager)
        #expect(
            provider.headingDegrees == 137.5,
            """
            A heading delivered through the provider's own delegate did not reach headingDegrees. \
            The rule can be perfect; if nothing calls it the dot stays bare, which is exactly what \
            the owner reported from build 7.
            """
        )
    }

    /// The fallback, all the way through: a reading that goes bad takes the cone off, immediately,
    /// without waiting for a five-degree turn that a reader standing at a car door will never make.
    @Test("a reading that goes bad takes the direction off the dot at once")
    func abadReadingClearsTheHeading() {
        let manager = HeadingManager()
        let provider = MapLocationProvider(manager: manager)
        provider.start()
        provider.startHeading()

        Self.deliver(trueHeading: 137.5, accuracy: 12, to: manager)
        #expect(provider.headingDegrees == 137.5)
        Self.deliver(trueHeading: 138, accuracy: -1, to: manager)
        #expect(
            provider.headingDegrees == nil,
            "an untrusted magnetometer left the last good bearing on the dot, pointing at nothing"
        )
    }

    @Test("a two-degree turn does not rewrite the provider's heading")
    func churnIsGatedOnTheProviderToo() {
        let manager = HeadingManager()
        let provider = MapLocationProvider(manager: manager)
        provider.start()
        provider.startHeading()

        Self.deliver(trueHeading: 90, accuracy: 10, to: manager)
        Self.deliver(trueHeading: 92, accuracy: 10, to: manager)
        #expect(provider.headingDegrees == 90, "every write re-runs screen 01's view tree")
        Self.deliver(trueHeading: 96, accuracy: 10, to: manager)
        #expect(provider.headingDegrees == 96)
    }

    /// Stopping forgets. A cone left pointing wherever the reader last stood is the confident wrong
    /// answer the whole fallback exists to refuse.
    @Test("stopping the magnetometer forgets the bearing as well as the sensor")
    func stoppingForgetsTheBearing() {
        let manager = HeadingManager()
        let provider = MapLocationProvider(manager: manager)
        provider.start()
        provider.startHeading()
        Self.deliver(trueHeading: 200, accuracy: 8, to: manager)
        #expect(provider.headingDegrees == 200)

        provider.stopHeading()
        #expect(manager.headingStops == 1)
        #expect(provider.headingDegrees == nil)
    }

    // MARK: - The mark on the glass

    private func userDotView(heading: Double?) -> MapMarkerView {
        let dot = UserDotAnnotation(
            coordinate: CLLocationCoordinate2D(latitude: 37.77, longitude: -122.42),
            headingDegrees: heading
        )
        let view = MapMarkerView(annotation: dot, reuseIdentifier: MapMarkerView.reuseIdentifier)
        view.bounds = CGRect(x: 0, y: 0, width: 18, height: 18)
        view.apply(annotation: dot, isDark: false)
        return view
    }

    /// The rotation runs on the render server, where no screenshot can catch which way it went
    /// round, so the accumulated angle is the assertion. It is unwrapped on purpose: 350 → 10 must
    /// come out as 370, a two-degree turn forwards, not as 10 — a 340° spin backwards through south.
    @Test("the cone turns the short way, and keeps turning the same way past north")
    func theConeTakesTheShortWay() {
        let view = userDotView(heading: 350)
        view.setHeading(350, animated: false)
        #expect(view.headingRotationDegrees == 350)

        view.setHeading(10, animated: true)
        #expect(
            view.headingRotationDegrees == 370,
            """
            The cone was turned to \(view.headingRotationDegrees ?? .nan)° instead of 370°. \
            Anything else is the cone sweeping the long way round the compass every time the \
            reader crosses north.
            """
        )
        view.setHeading(350, animated: true)
        #expect(view.headingRotationDegrees == 350)
    }

    /// No heading, no cone — on the view as well as in the arithmetic. This is the bare dot the app
    /// shipped before #155, which is what an untrusted magnetometer degrades back to.
    @Test("no heading leaves the dot bare")
    func noHeadingNoCone() {
        let view = userDotView(heading: nil)
        view.setHeading(nil, animated: false)
        #expect(view.headingRotationDegrees == nil)

        view.setHeading(120, animated: false)
        #expect(view.headingRotationDegrees == 120)
        view.setHeading(nil, animated: false)
        #expect(
            view.headingRotationDegrees == nil,
            "the cone survived a heading going away, which is a direction pointer pointing at nothing"
        )
    }

    /// A recycled marker takes the cone off on its way to a tree. `MKAnnotationView`s are reused
    /// across annotation types here, and a direction pointer on a tree pin is not a mark this app has.
    @Test("a recycled marker carries no cone to the next annotation")
    func recyclingClearsTheCone() {
        let view = userDotView(heading: 45)
        view.setHeading(45, animated: false)
        #expect(view.headingRotationDegrees == 45)
        view.prepareForReuse()
        #expect(view.headingRotationDegrees == nil)
    }

    /// **Heading stays out of what VoiceOver says.** #100 made this label about *where you are*; a
    /// bearing that changed every time the reader turned their wrist would talk over everything else
    /// on the screen and serve nobody. The cone is visual-only, and this is the assertion that keeps
    /// the spoken channel as it was.
    @Test("the dot still says where you are, and says nothing about which way you face")
    func headingIsNotSpoken() {
        let view = userDotView(heading: 137)
        view.setHeading(137, animated: false)
        #expect(view.accessibilityLabel == MapPin.Kind.gps.accessibilityLabel)
        #expect(view.accessibilityLabel == "Your location")
    }
}
