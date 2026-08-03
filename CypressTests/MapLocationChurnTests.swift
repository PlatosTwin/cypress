import CoreLocation
import Foundation
import Testing
@testable import Cypress

/// **The map's location provider, and the two ways it used to set the screen on fire.**
///
/// Screen 01 was reported slow on a real iPhone after a round of work that measured it fast on a
/// simulator. The gap was location: every simulator measurement this project has ever taken was
/// made with permission *declined* or with a single static `simctl location`, and a static fix
/// fires `didUpdateLocations` once and never again. With a route running, two defects showed up
/// that no static run could have.
///
/// Both are wiring defects, so both are asserted the way `AccountSurfaceTests` insists on — **where
/// the value is read back, through the real delegate, not at the call site.** A predicate that is
/// correct and never called is exactly the failure being tested for: `MapHomeView` had a perfectly
/// good shared provider available to it and built its own anyway.
@MainActor
@Suite("Screen 01's location churn")
struct MapLocationChurnTests {

    /// A `CLLocationManager` that answers "allowed" and counts sessions instead of opening one.
    ///
    /// Subclassing rather than protocol-ing the provider: `MapLocationProvider` already takes a
    /// manager for exactly this reason, and the thing under test is what it *does to a manager*.
    private final class RecordingManager: CLLocationManager {
        var startCount = 0
        var stopCount = 0
        var stubbedAuthorization: CLAuthorizationStatus = .authorizedWhenInUse

        override var authorizationStatus: CLAuthorizationStatus { stubbedAuthorization }
        override func startUpdatingLocation() { startCount += 1 }
        override func stopUpdatingLocation() { stopCount += 1 }
        override func requestWhenInUseAuthorization() {}
    }

    private static func fix(_ latitude: Double, _ longitude: Double, accuracy: Double = 5) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: 0,
            horizontalAccuracy: accuracy,
            verticalAccuracy: 1,
            timestamp: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    /// Pushes a fix through the **real** delegate the provider installed, which is the only path
    /// the app itself uses.
    private static func deliver(_ location: CLLocation, to manager: CLLocationManager) {
        manager.delegate?.locationManager?(manager, didUpdateLocations: [location])
    }

    // MARK: - Construction must not open a GPS session

    /// **The one that cost the most.** `MapHomeView` declared
    /// `@State private var location = MapLocationProvider()`, and a SwiftUI `@State` default
    /// expression is re-evaluated on every initialization of the view struct — `RootView.body`
    /// initializes this one on every pass. Construction called `startUpdatingLocation()` by way of
    /// `apply(authorization:)`, so the app stood up and threw away roughly fifty `CLLocationManager`
    /// sessions a second: 336 provider instances in seven measured seconds, each delivering a cached
    /// fix on its way out.
    ///
    /// The provider is shared from the composition root now, so no stray one should exist at all.
    /// This is the belt to that braces: even if one is built by accident, it is inert.
    @Test("constructing a provider opens no location session")
    func constructionIsInert() {
        let manager = RecordingManager()
        _ = MapLocationProvider(manager: manager)
        #expect(
            manager.startCount == 0,
            """
            Constructing a MapLocationProvider started \(manager.startCount) location session(s). \
            A SwiftUI @State default expression runs on every initialization of its view, so a \
            provider that opens a session in init opens one per body pass of whatever declares it.
            """
        )
    }

    @Test("start() is what opens the session, once asked")
    func startOpensTheSession() {
        let manager = RecordingManager()
        let provider = MapLocationProvider(manager: manager)
        provider.start()
        #expect(manager.startCount == 1)
    }

    /// The authorization callback is the *other* caller of the same private path, and it is the one
    /// that must still work: the map calls `start()` while the status is `notDetermined`, the sheet
    /// is answered later, and the grant has to open the session that `start()` could not.
    @Test("a grant that arrives after start() still opens the session")
    func aLateGrantStillStarts() {
        let manager = RecordingManager()
        manager.stubbedAuthorization = .notDetermined
        let provider = MapLocationProvider(manager: manager)
        provider.start()
        #expect(manager.startCount == 0, "notDetermined asks for the sheet; it does not start")

        manager.stubbedAuthorization = .authorizedWhenInUse
        manager.delegate?.locationManagerDidChangeAuthorization?(manager)
        #expect(manager.startCount == 1)
    }

    /// And a grant that arrives when nobody asked must not. This is the half that makes the
    /// inertness above hold on a device where permission was granted in a previous session.
    @Test("a grant arriving at a provider nobody started opens nothing")
    func anUnaskedGrantStartsNothing() {
        let manager = RecordingManager()
        manager.stubbedAuthorization = .notDetermined
        let provider = MapLocationProvider(manager: manager)
        _ = provider

        manager.stubbedAuthorization = .authorizedWhenInUse
        manager.delegate?.locationManagerDidChangeAuthorization?(manager)
        #expect(manager.startCount == 0)
    }

    // MARK: - A fix that says nothing must not be republished

    /// `availability` is `@Observable` and screen 01's whole view tree reads it, so a write is a
    /// rebuild. `distanceFilter = 5` is supposed to mean the delegate is not called until the
    /// reader has moved five meters, and on a simulated route it is simply not honored — measured
    /// at a walking 4 m/s, **24 to 42 fixes a second**, one every fifteen centimeters.
    ///
    /// Asserted through `availability` rather than through the predicate, so a rule that is right
    /// and not wired up fails here.
    @Test("a fix from where you already are does not rewrite availability")
    func aStationaryFixIsNotRepublished() {
        let manager = RecordingManager()
        let provider = MapLocationProvider(manager: manager)
        provider.start()

        Self.deliver(Self.fix(37.778_75, -122.424_66), to: manager)
        let first = provider.availability
        #expect(first.coordinate != nil, "the first fix always publishes")

        // Roughly a meter and a half north — well inside the five the manager was told to filter at.
        Self.deliver(Self.fix(37.778_763, -122.424_66), to: manager)
        #expect(
            provider.availability == first,
            """
            A fix 1.4 m from the last published one rewrote availability. Every write re-runs \
            screen 01's view tree, and CoreLocation delivers these dozens of times a second.
            """
        )
    }

    @Test("a fix five meters away is published")
    func realMovementIsPublished() {
        let manager = RecordingManager()
        let provider = MapLocationProvider(manager: manager)
        provider.start()

        Self.deliver(Self.fix(37.778_75, -122.424_66), to: manager)
        let first = provider.availability
        // ~6.7 m north.
        Self.deliver(Self.fix(37.778_81, -122.424_66), to: manager)
        #expect(provider.availability != first)
        #expect(provider.availability.coordinate?.latitude == 37.778_81)
    }

    /// The accuracy is not decoration. `RootView` hands `availability.accuracyM` to every check-in,
    /// measurement and visit it records, and D6 excludes a reading worse than 15 m from growth
    /// charting — so a provider that froze the accuracy while the reader stood still would be
    /// feeding that gate a stale number.
    @Test("standing still but with a changed accuracy still publishes")
    func anAccuracyChangeAlonePublishes() {
        let manager = RecordingManager()
        let provider = MapLocationProvider(manager: manager)
        provider.start()

        Self.deliver(Self.fix(37.778_75, -122.424_66, accuracy: 5), to: manager)
        #expect(provider.availability.accuracyM == 5)

        Self.deliver(Self.fix(37.778_75, -122.424_66, accuracy: 22), to: manager)
        #expect(
            provider.availability.accuracyM == 22,
            "a fix that got much worse while the reader stood still never reached the record"
        )
    }

    /// The threshold is `distanceFilter`'s own number, kept rather than invented — the point was to
    /// make a decision this file had already taken actually true, not to take a new one. If anybody
    /// ever raises it as a performance measure, this is the sentence they have to argue with.
    @Test("the publish threshold is the distance filter's own promise, not a coarser one")
    func thresholdMatchesTheDistanceFilter() {
        #expect(MapLocationProvider.publishDistanceM == 5)
        #expect(MapLocationProvider.publishAccuracyM == 1)
    }

    /// Boundary behavior of the rule itself, stated once where it can be read.
    @Test("the rule publishes anything when there is no previous fix")
    func thereIsAlwaysAFirstFix() {
        for previous: MapLocationProvider.Availability in [.notAsked, .waitingForFix, .denied, .servicesOff] {
            #expect(MapLocationProvider.isWorthPublishing(
                coordinate: Coordinate(latitude: 37.77, longitude: -122.42),
                accuracyM: 5,
                over: previous
            ))
        }
    }
}
