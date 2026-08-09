import Foundation
import Testing
@testable import Cypress

/// The launch seam that lets a UI test **drive** screen 01's opening camera instead of inheriting
/// whichever one the last run left on the device.
///
/// Two things are asserted here and they are different claims. The **grammar** — what parses, what
/// is refused — is `DebugLocationOverrideTests`' shape one file over. The **effect** is
/// `MapCameraMemory`'s, and it matters more: a pinned instance must open on the pin *and write
/// nothing*, because a seam that left its camera in `map.lastCamera` would hand the next run — which
/// pinned nothing — a remembered camera it never chose. Every one of those has a control that pins
/// nothing and must behave exactly as before.
///
/// What cannot be asserted in-process is that a pinned camera reaches MapKit and puts trees on the
/// glass. That is `IdentifyFABReachabilityTests` and the deep-link classes, which are the tests this
/// seam exists to make deterministic.
@Suite("Debug map camera override")
struct DebugMapCameraOverrideTests {

    private func pinned(_ raw: String) -> MapCameraMemory.Snapshot? {
        if case let .pinned(snapshot) = DebugMapCameraOverride.parse(raw) { return snapshot }
        return nil
    }

    private func invalidReason(_ raw: String) -> String? {
        if case let .invalid(_, reason) = DebugMapCameraOverride.parse(raw) { return reason }
        return nil
    }

    // MARK: - The grammar

    @Test("lat,lon opens at the app's own default span")
    func coordinateAtDefaultSpan() {
        let snapshot = pinned("37.78485,-122.4215")
        #expect(snapshot?.center.latitude == 37.78485)
        #expect(snapshot?.center.longitude == -122.4215)

        // The same span the app opens on when it has nothing remembered, taken from `MapLayout`
        // rather than restated: a literal here would be a second number to keep in step with the
        // first, and `MapLayout.defaultSpanMeters`' own doc comment is where the 120 is argued.
        let expected = MapLayout.region(around: Coordinate(latitude: 37.78485, longitude: -122.4215))
        #expect(snapshot?.latitudeSpan == expected.span.latitudeDelta)
        #expect(snapshot?.longitudeSpan == expected.span.longitudeDelta)
    }

    /// The third field is **meters**, not degrees. A degree of longitude is a different distance at
    /// every latitude, which is the conversion `MapLayout.region(around:meters:)` exists to own.
    @Test("a third field widens the camera, in meters")
    func statedSpanIsInMeters() {
        guard let narrow = pinned("37.78485,-122.4215"),
              let wide = pinned("37.78485,-122.4215,1200")
        else {
            Issue.record("a well-formed camera did not parse")
            return
        }
        #expect(wide.latitudeSpan > narrow.latitudeSpan)
        // Ten times the meters is ten times the latitude span, because latitude degrees are a
        // constant distance. Compared with a tolerance rather than by equality: the conversion goes
        // through `MKCoordinateRegion`, and pinning a floating-point identity on Apple's arithmetic
        // would be asserting their implementation rather than this file's.
        #expect(abs(wide.latitudeSpan / narrow.latitudeSpan - 10) < 0.01)
    }

    @Test("surrounding whitespace is not a syntax error")
    func whitespaceTolerated() {
        #expect(pinned(" 37.78485 , -122.4215 ")?.center.latitude == 37.78485)
    }

    // MARK: - Refusals

    @Test("a camera that is not two or three numbers is refused")
    func malformedIsRefused() {
        #expect(invalidReason("37.78485") != nil)
        #expect(invalidReason("37.78485,-122.4215,120,3") != nil)
        #expect(invalidReason("37.78485,west") != nil)
        #expect(invalidReason("westernAddition") != nil)
        #expect(invalidReason(",") != nil)
    }

    /// Out of range is refused rather than clamped, for `DebugLocationOverride`'s reason: a caller
    /// who typed the longitude into the latitude field wants to be told, not quietly moved.
    @Test("a coordinate off the globe is refused, not clamped")
    func outOfRangeIsRefused() {
        #expect(invalidReason("91,-122.4215") != nil)
        #expect(invalidReason("37.78485,-181") != nil)
    }

    /// Nothing here is San Francisco-specific — the grammar is a grammar.
    @Test("a coordinate on the other side of the world parses")
    func farFromHomeParses() {
        #expect(pinned("-33.86,151.21")?.center.latitude == -33.86)
    }

    /// **A pole is on the globe and is still not a camera**, which the seam found rather than
    /// assumed: `-90,180` passes every range check above and is then refused, because converting a
    /// fixed number of meters into a longitude span degenerates as the meridians converge and the
    /// result is wider than `MapCameraMemory.maximumSpanDegrees`. Recorded because the refusal
    /// arrives from the app's own admission rule rather than from this parser's ranges, and a
    /// reader who saw only the ranges would expect it to parse — the first draft of this file did.
    @Test("a camera at the pole is refused by the app's own rule, not by a range check")
    func poleIsRefusedBySpan() {
        let reason = invalidReason("-90,180")
        #expect(reason != nil)
        #expect(
            reason?.contains("latitude must be within") == false,
            """
            the pole was refused by a coordinate range check. That is not what happens — it is \
            refused because the span the meters convert to is one `MapCameraMemory` would throw \
            away — and if the ranges changed to reject it, this test is no longer about anything
            """
        )
    }

    @Test("a non-positive span is refused")
    func nonPositiveSpanIsRefused() {
        #expect(invalidReason("37.78485,-122.4215,0") != nil)
        #expect(invalidReason("37.78485,-122.4215,-120") != nil)
    }

    /// **The refusal that is not about typing but about the app's own rule.** `MapCameraMemory` drops
    /// a camera wider than `maximumSpanDegrees` on the way in and falls back to the city, so a pin
    /// that wide would be a seam that silently did not pin. Reachable from a plausible mistake:
    /// somebody reading the span as degrees and writing 20.
    @Test("a span the app would refuse to remember is refused here too")
    func unrememberableSpanIsRefused() {
        let tooWide = MapCameraMemory.maximumSpanDegrees * 111_000 * 2
        #expect(invalidReason("37.78485,-122.4215,\(Int(tooWide))") != nil)
    }

    /// Everything that parses must survive the app's own admission test, or the pin would be
    /// discarded downstream and the map would open somewhere else while the seam reported success.
    @Test("every camera that parses is one the app would remember")
    func everyPinIsRememberable() {
        for raw in [
            DebugMapCameraFixtures.westernAddition,
            "37.7596,-122.4269",
            "37.78485,-122.4215,1200",
            "-33.86,151.21",
        ] {
            guard let snapshot = pinned(raw) else {
                Issue.record("\(raw) did not parse")
                continue
            }
            #expect(
                MapCameraMemory.isWorthRemembering(snapshot),
                "\(raw) parsed into a camera `MapCameraMemory` would throw away"
            )
        }
    }

    // MARK: - The environment

    @Test("an unset or empty key asks for nothing")
    func absentKeyIsNoRequest() {
        #expect(DebugMapCameraOverride.requested([:]) == nil)
        #expect(DebugMapCameraOverride.requested([DebugMapCameraOverride.environmentKey: ""]) == nil)
        #expect(DebugMapCameraOverride.requested([DebugMapCameraOverride.environmentKey: " "]) == nil)
    }

    @Test("resolve hands back a camera, a banner, or neither — never both")
    func resolveIsExclusive() {
        let ordinary = DebugMapCameraOverride.resolve([:])
        #expect(ordinary.snapshot == nil)
        #expect(ordinary.failure == nil)

        let junk = DebugMapCameraOverride.resolve(
            [DebugMapCameraOverride.environmentKey: "the park"]
        )
        #expect(junk.snapshot == nil)
        #expect(junk.failure?.hasPrefix("MAP CAMERA OVERRIDE FAILED · the park · ") == true)
    }

    /// One measured coordinate under two names, not two coordinates. `DebugLocationFixtures` records
    /// how the 780 trees around it were counted; this is the same string, so the count applies.
    @Test("the camera fixture is the same coordinate the location fixture names")
    func fixturesAgree() {
        #expect(DebugMapCameraFixtures.westernAddition == DebugLocationFixtures.westernAddition)
        #expect(pinned(DebugMapCameraFixtures.westernAddition) != nil)
    }

    // MARK: - What it does to the camera memory

    /// Each test gets its own defaults suite: Swift Testing runs these in parallel, and two of them
    /// sharing `map.lastCamera` would be a flake this file exists to argue against.
    private func scratchDefaults(_ name: String) -> UserDefaults {
        let suite = "MapCameraMemoryTests.\(name)"
        UserDefaults().removePersistentDomain(forName: suite)
        return UserDefaults(suiteName: suite) ?? .standard
    }

    private let onDisk = MapCameraMemory.Snapshot(
        center: Coordinate(latitude: 37.759899, longitude: -122.414803),
        latitudeSpan: 0.001081,
        longitudeSpan: 0.001362
    )

    /// **The control comes first.** Without it the two assertions below could both pass on a
    /// `MapCameraMemory` that had simply stopped reading and writing at all.
    @MainActor
    @Test("with nothing pinned, the camera on disk is still read and still written")
    func unpinnedIsUnchanged() {
        let defaults = scratchDefaults("unpinned")
        defaults.set(MapCameraMemory.encode(onDisk), forKey: MapCameraMemory.defaultsKey)

        let memory = MapCameraMemory(defaults: defaults)
        #expect(memory.remembered == onDisk)

        let moved = MapCameraMemory.Snapshot(
            center: Coordinate(latitude: 37.78485, longitude: -122.4215),
            latitudeSpan: 0.0011, longitudeSpan: 0.0014
        )
        memory.note(moved)
        memory.flush()
        #expect(
            MapCameraMemory.decode(
                defaults.array(forKey: MapCameraMemory.defaultsKey) as? [Double]
            ) == moved,
            "an ordinary launch must still write the camera it was left on — that is #115"
        )
    }

    @MainActor
    @Test("a pinned camera is what the map opens on, whatever is on disk")
    func pinnedCameraWins() {
        let defaults = scratchDefaults("pinnedWins")
        defaults.set(MapCameraMemory.encode(onDisk), forKey: MapCameraMemory.defaultsKey)

        guard let pin = pinned(DebugMapCameraFixtures.westernAddition) else {
            Issue.record("the fixture did not parse")
            return
        }
        let memory = MapCameraMemory(defaults: defaults, pinned: pin)
        #expect(memory.remembered == pin)
        #expect(memory.openingSnapshot == pin)
        #expect(MapOpening.openingRegion(remembered: memory.openingSnapshot).center.latitude == pin.center.latitude)
    }

    /// **The half that fixes the flake.** A run that wrote its pin out would leave the next run — a
    /// run that pinned nothing — opening on a camera it never chose, which is the device-state
    /// inheritance this seam removes rather than relocates.
    @MainActor
    @Test("a pinned camera is never written back to the device")
    func pinnedCameraIsNeverWritten() {
        let defaults = scratchDefaults("pinnedNeverWritten")
        defaults.set(MapCameraMemory.encode(onDisk), forKey: MapCameraMemory.defaultsKey)

        guard let pin = pinned(DebugMapCameraFixtures.westernAddition) else {
            Issue.record("the fixture did not parse")
            return
        }
        let memory = MapCameraMemory(defaults: defaults, pinned: pin)
        memory.note(
            MapCameraMemory.Snapshot(
                center: Coordinate(latitude: 37.80, longitude: -122.40),
                latitudeSpan: 0.002, longitudeSpan: 0.002
            )
        )
        memory.flush()
        #expect(
            MapCameraMemory.decode(
                defaults.array(forKey: MapCameraMemory.defaultsKey) as? [Double]
            ) == onDisk,
            "a pinned run wrote over the device's own remembered camera"
        )
    }

    /// **A pinned launch says what a first launch says.** `MapOpeningCopy.showing` ends the location
    /// notice with one of two sentences, the fallback one is five characters longer, and at AX5 the
    /// notice's height is what `IdentifyFABReachabilityTests` measures the bottom chrome against. A
    /// pinned run reporting "where you last left it" would quietly hand that class the shorter
    /// sentence and the weaker version of its own guard.
    @MainActor
    @Test("a pinned camera is not a camera the reader left")
    func pinnedIsNotRemembered() {
        let defaults = scratchDefaults("pinnedNotRemembered")
        defaults.set(MapCameraMemory.encode(onDisk), forKey: MapCameraMemory.defaultsKey)

        // The control: the same defaults, unpinned, do report a remembered camera.
        #expect(MapCameraMemory(defaults: defaults).hasRememberedCamera)

        guard let pin = pinned(DebugMapCameraFixtures.westernAddition) else {
            Issue.record("the fixture did not parse")
            return
        }
        let memory = MapCameraMemory(defaults: defaults, pinned: pin)
        #expect(memory.hasRememberedCamera == false)
        #expect(
            MapOpening.showing(remembered: memory.hasRememberedCamera) == .theCityFallback,
            "a pinned launch must produce the sentence a fresh install produces"
        )
    }

    /// Pinning is about where the map *opens*. A pan the test itself performs must still be visible
    /// to the screen when it is remade by a tab switch, or this seam would quietly change what
    /// `MapPanTabSwitchUITests` asserts (task #128).
    @MainActor
    @Test("a pinned camera does not freeze the session's own camera")
    func pinnedStillTracksTheSession() {
        guard let pin = pinned(DebugMapCameraFixtures.westernAddition) else {
            Issue.record("the fixture did not parse")
            return
        }
        let memory = MapCameraMemory(defaults: scratchDefaults("pinnedSession"), pinned: pin)
        let panned = MapCameraMemory.Snapshot(
            center: Coordinate(latitude: 37.80, longitude: -122.40),
            latitudeSpan: 0.002, longitudeSpan: 0.002
        )
        memory.note(panned)
        #expect(memory.sessionSnapshot == panned)
        #expect(memory.openingSnapshot == panned)
    }
}
