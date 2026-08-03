import Foundation
import Testing
@testable import Cypress

/// The launch seam that lets a UI test **drive** the app's location state instead of detecting it
/// (task #121; ruling `docs/rulings-pending/location-state-launch-seam.md`).
///
/// The grammar is what these assert. The wiring — that a pinned provider actually reaches screen 01
/// and screen 12 — cannot be asserted in-process and is not attempted here: it is
/// `MapRecenterUITests.testPressingItWithLocationDeniedExplainsRatherThanDoingNothing` and
/// `AlmanacGroupTapTests`, which are exactly the two tests this seam exists to make unconditional.
///
/// **The invalid cases carry the weight.** A seam that quietly fell back to the real provider on a
/// typo would let a test assert the denied refusal path against a simulator with a good fix, and it
/// would fail somewhere else entirely — or pass. That is `DebugDeepLink.Failure`'s lesson, and every
/// rejection below is a state this seam must refuse rather than round off.
@Suite("Debug location override (#121)")
struct DebugLocationOverrideTests {

    private func pinned(_ raw: String) -> MapLocationProvider.Availability? {
        if case let .pinned(availability) = DebugLocationOverride.parse(raw) { return availability }
        return nil
    }

    private func invalidReason(_ raw: String) -> String? {
        if case let .invalid(_, reason) = DebugLocationOverride.parse(raw) { return reason }
        return nil
    }

    // MARK: - The named states

    /// Spelled exactly as `Availability`'s own cases, so there is one vocabulary rather than two.
    @Test("each named state parses to its own availability")
    func namedStates() {
        #expect(pinned("denied") == .denied)
        #expect(pinned("servicesOff") == .servicesOff)
        #expect(pinned("notAsked") == .notAsked)
        #expect(pinned("waitingForFix") == .waitingForFix)
    }

    /// `denied` and `servicesOff` are both refusals and are *different* refusals — `MapLocationCopy
    /// .title` says "Location Services are off" for one and "Location is off" for the other. A seam
    /// that collapsed them would make the second sentence untestable.
    @Test("the two refusals stay distinct")
    func refusalsAreDistinct() {
        #expect(pinned("denied") != pinned("servicesOff"))
        #expect(pinned("denied")?.isRefused == true)
        #expect(pinned("servicesOff")?.isRefused == true)
    }

    // MARK: - A coordinate

    @Test("lat,lon pins a fix at the default accuracy")
    func coordinateWithDefaultAccuracy() {
        let parsed = pinned("37.78485,-122.4215")
        #expect(parsed?.coordinate?.latitude == 37.78485)
        #expect(parsed?.coordinate?.longitude == -122.4215)
        #expect(parsed?.accuracyM == DebugLocationOverride.defaultAccuracyM)
    }

    /// The default has to sit the *usable* side of D6's 15 m gate, or every chart built on a pinned
    /// fix would be empty for a reason no reader ever encounters. See the constant's own comment.
    @Test("the default accuracy is inside D6's 15 m gate")
    func defaultAccuracyIsUsable() {
        #expect(DebugLocationOverride.defaultAccuracyM < 15)
        #expect(DebugLocationOverride.defaultAccuracyM > 0)
    }

    @Test("a third field states the accuracy, including a deliberately unusable one")
    func coordinateWithStatedAccuracy() {
        #expect(pinned("37.78485,-122.4215,25")?.accuracyM == 25)
        #expect(pinned("37.78485,-122.4215,2.5")?.accuracyM == 2.5)
    }

    @Test("surrounding whitespace is not a syntax error")
    func whitespaceTolerated() {
        #expect(pinned(" 37.78485 , -122.4215 ")?.coordinate?.latitude == 37.78485)
    }

    // MARK: - Refusals

    @Test("a misspelled state name is refused rather than ignored")
    func misspelledStateIsRefused() {
        #expect(invalidReason("Denied") != nil)
        #expect(invalidReason("deneid") != nil)
        #expect(invalidReason("servicesoff") != nil)
    }

    @Test("a coordinate that is not two or three numbers is refused")
    func malformedCoordinateIsRefused() {
        #expect(invalidReason("37.78485") != nil)
        #expect(invalidReason("37.78485,-122.4215,8,9") != nil)
        #expect(invalidReason("37.78485,west") != nil)
        #expect(invalidReason(",") != nil)
    }

    /// Out-of-range is its own refusal rather than a clamp: a caller who typed the longitude into the
    /// latitude field wants to be told, not quietly moved to the pole.
    @Test("a coordinate off the globe is refused, not clamped")
    func outOfRangeIsRefused() {
        #expect(invalidReason("91,-122.4215") != nil)
        #expect(invalidReason("37.78485,-181") != nil)
        #expect(pinned("-90,180") != nil)
    }

    @Test("a non-positive accuracy is refused")
    func nonPositiveAccuracyIsRefused() {
        #expect(invalidReason("37.78485,-122.4215,0") != nil)
        #expect(invalidReason("37.78485,-122.4215,-5") != nil)
    }

    // MARK: - The environment

    @Test("an unset or empty key asks for nothing")
    func absentKeyIsNoRequest() {
        #expect(DebugLocationOverride.requested([:]) == nil)
        #expect(DebugLocationOverride.requested([DebugLocationOverride.environmentKey: ""]) == nil)
        #expect(DebugLocationOverride.requested([DebugLocationOverride.environmentKey: "   "]) == nil)
    }

    /// The composition root asks one question and gets both halves of the answer, so an ordinary
    /// launch cannot accidentally take the pinned path and a junk one cannot accidentally take the
    /// real one.
    @MainActor
    @Test("resolve hands back a provider, a banner, or neither — never both")
    func resolveIsExclusive() {
        let ordinary = DebugLocationOverride.resolve([:])
        #expect(ordinary.provider == nil)
        #expect(ordinary.failure == nil)

        let junk = DebugLocationOverride.resolve([DebugLocationOverride.environmentKey: "nowhere"])
        #expect(junk.provider == nil)
        #expect(junk.failure?.hasPrefix("LOCATION OVERRIDE FAILED · nowhere · ") == true)
    }

    /// The two coordinates this project offers by name are the ones E216 makes it expensive to get
    /// wrong: a pinned fix moves screen 01's camera, and that camera is written out and read back by
    /// the next run's preflight. Both parse, and both are inside San Francisco's bounding box — the
    /// tree counts behind them are recorded on `DebugLocationFixtures` and re-measured there.
    @Test("the named fixtures parse and land in San Francisco")
    func fixturesAreUsable() {
        for raw in [DebugLocationFixtures.westernAddition, DebugLocationFixtures.missionDolores] {
            guard let coordinate = pinned(raw)?.coordinate else {
                Issue.record("\(raw) did not parse as a fix")
                continue
            }
            #expect(coordinate.latitude > 37.70 && coordinate.latitude < 37.83)
            #expect(coordinate.longitude > -122.52 && coordinate.longitude < -122.35)
        }
    }

    // MARK: - The provider it builds

    /// A pinned provider reports what it was handed and **cannot be moved off it**. `start()` is the
    /// call that raises the system sheet and opens a GPS session; on a pinned provider it must do
    /// neither, or a test that asked for `denied` would get a permission alert over the screen it is
    /// reading and a real fix a moment later.
    @MainActor
    @Test("a pinned provider reports its state and start() cannot move it")
    func pinnedProviderIsInert() {
        for availability in [
            MapLocationProvider.Availability.denied,
            .servicesOff,
            .notAsked,
            .waitingForFix,
            .located(Coordinate(latitude: 37.78485, longitude: -122.4215), accuracyM: 8),
        ] {
            let provider = MapLocationProvider(pinnedAvailability: availability)
            #expect(provider.availability == availability)
            provider.start()
            #expect(provider.availability == availability, "start() moved a pinned provider")
            provider.stop()
            #expect(provider.availability == availability, "stop() moved a pinned provider")
        }
    }

    /// `authorization` is derived from the availability rather than taken separately, because the
    /// pairs the app can actually be in are not free: a `.denied` availability with an
    /// `authorizedWhenInUse` status is a state iOS never produces, and a seam that could construct
    /// one would be a seam for testing states the app will never see.
    @MainActor
    @Test("a pinned provider's authorization agrees with its availability")
    func pinnedAuthorizationAgrees() {
        #expect(MapLocationProvider(pinnedAvailability: .denied).authorization == .denied)
        #expect(MapLocationProvider(pinnedAvailability: .servicesOff).authorization == .restricted)
        #expect(MapLocationProvider(pinnedAvailability: .notAsked).authorization == .notDetermined)
        #expect(
            MapLocationProvider(pinnedAvailability: .waitingForFix).authorization == .authorizedWhenInUse
        )
        let fix = MapLocationProvider.Availability.located(
            Coordinate(latitude: 37.78485, longitude: -122.4215), accuracyM: 8
        )
        #expect(MapLocationProvider(pinnedAvailability: fix).authorization == .authorizedWhenInUse)
    }
}
