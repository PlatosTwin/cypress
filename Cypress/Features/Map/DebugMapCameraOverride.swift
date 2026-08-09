//
//  DebugMapCameraOverride.swift
//  Cypress — Features/Map
//
//  A launch-time way to say where screen 01's camera opens, for the UI test target and nothing else.
//
//  ── Why this exists ───────────────────────────────────────────────────────────────────────
//  `MapOpeningCamera`'s header makes the product case for remembering a camera: "a place the reader
//  has actually been beats a stranger's park". Nothing here disputes it. What it costs the test
//  suite is that **screen 01 opens somewhere the last run chose**, and several tests that are not
//  about the map at all read the map anyway:
//
//  - screens 09, 10 and 18 are presented *over* the map tab root, so screen 01's annotations stay
//    in the accessibility tree behind them. `DeepLinkHarness.assertEveryControlIsLabeled` walks
//    `app.buttons` — every button in the app — and one annotation the remembered camera happened to
//    place where XCUITest can compute no activation point makes `isHittable` **raise**. That is
//    `DeepLinkVoiceOverTests.testPinAdjust`, and `DeepLinkSweepTests.testNothingIsAnnouncedTwice`
//    on CI run 31300530216;
//  - `MapSpeciesLegend` "draws nothing when it has colored none", so whether the legend is in the
//    tree at all is a fact about how many trees the opening camera has in view.
//    `IdentifyFABReachabilityTests.testTheTopChromeStaysClearOfTheBottomChromeAtAX5WithLocation
//    Denied` failed on CI runs 31291434427, 31294993494 and 31300530216 waiting 30 s for a legend
//    that was never going to be drawn.
//
//  `Tools/run_tests.sh` normalizes the camera before the suite starts (task #71), and that is a
//  different guarantee from this one: it makes every *run* start from the same camera, and cannot
//  say anything about the camera the twentieth launch inside that run inherits from the nineteenth.
//  The errata entry for #71 names this file as the repair it deliberately did not make.
//
//  ── What it deliberately is not ───────────────────────────────────────────────────────────
//  **Not a setting, and not reachable from the app.** Read from the process environment for
//  `DebugLocationOverride.environmentKey`'s reasons — a thing only whoever launched the process can
//  write. The whole file is `#if DEBUG`, as is every line that consults it.
//
//  **Not a way to make an empty map look full.** It moves the camera; it does not put trees under
//  it. A caller that pins a coordinate the seed has no rows near gets an empty map, honestly.
//
//  **Not a replacement for the harness preflight.** This pins the app's *opening* camera. Whether
//  the device is otherwise fit to run a UI suite — another `xcodebuild` live against it, a stale
//  `active-city` marker — is still `Tools/run_tests.sh`'s question and is not asked here.
//
//  ── The one thing it must never do quietly ────────────────────────────────────────────────
//  Fail. A typo in `CYPRESS_MAP_CAMERA` must not fall through to the remembered camera and let a
//  test pass while reading a screen drawn somewhere else — that is `DebugDeepLink.Failure`'s lesson
//  and `DebugLocationOverride`'s, and the same answer is used: an unparseable value becomes a banner
//  drawn on top of the app, in words.
//

#if DEBUG
import CoreLocation
import Foundation
import MapKit

/// The test-only way to pin screen 01's opening camera. `#if DEBUG`; see the file comment.
enum DebugMapCameraOverride {

    /// Read from the environment, for `DebugLocationOverride.environmentKey`'s reasons.
    static let environmentKey = "CYPRESS_MAP_CAMERA"

    /// What the launching process asked for.
    ///
    /// `.invalid` rather than `nil` for an unrecognized value, for `DebugLocationOverride.Request`'s
    /// reason: a seam that quietly did nothing would leave a test reading a screen drawn over
    /// whatever camera the last launch left, which is the state this file exists to remove.
    enum Request: Equatable {
        case pinned(MapCameraMemory.Snapshot)
        case invalid(raw: String, reason: String)
    }

    /// What the launching process asked for, if anything.
    static func requested(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Request? {
        guard let raw = environment[environmentKey]?
            .trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        return parse(raw)
    }

    /// The grammar, in one place so it can be tested without a process.
    ///
    ///     CYPRESS_MAP_CAMERA=37.78485,-122.4215       at `MapLayout.defaultSpanMeters`
    ///     CYPRESS_MAP_CAMERA=37.78485,-122.4215,300   300 m across
    ///
    /// **The span is in meters, not degrees, because `MapLayout` is.** A caller writing a camera by
    /// hand would otherwise have to convert, and a longitude span in degrees is a different distance
    /// at every latitude — the exact confusion `MapLayout.region(around:meters:)` exists to spare
    /// the rest of the app.
    static func parse(_ raw: String) -> Request {
        let parts = raw.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2 || parts.count == 3 else {
            return .invalid(raw: raw, reason: "expected lat,lon[,spanMeters]")
        }
        guard let latitude = Double(parts[0]), let longitude = Double(parts[1]) else {
            return .invalid(raw: raw, reason: "latitude and longitude must be numbers")
        }
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            return .invalid(raw: raw, reason: "latitude must be within ±90 and longitude within ±180")
        }
        var meters = MapLayout.defaultSpanMeters
        if parts.count == 3 {
            guard let stated = Double(parts[2]), stated > 0 else {
                return .invalid(raw: raw, reason: "the span must be a positive number of meters")
            }
            meters = stated
        }
        let region = MapLayout.region(
            around: Coordinate(latitude: latitude, longitude: longitude), meters: meters
        )
        let snapshot = MapCameraMemory.Snapshot(
            center: Coordinate(latitude: latitude, longitude: longitude),
            latitudeSpan: region.span.latitudeDelta,
            longitudeSpan: region.span.longitudeDelta
        )
        // **Refused rather than clamped, and checked against the app's own rule rather than a second
        // copy of it.** `MapCameraMemory` drops a camera that fails this on the way in and falls back
        // to the city; a pinned camera that did the same would be a seam that silently did not pin,
        // which is the whole failure mode this file's header is about. A span of 10° or more is the
        // reachable case — `maximumSpanDegrees` — and it is reachable from a plausible typo.
        guard MapCameraMemory.isWorthRemembering(snapshot) else {
            return .invalid(
                raw: raw,
                reason: "\(Int(meters)) m at that latitude is not a camera the app would remember "
                    + "(spans must be positive and under \(Int(MapCameraMemory.maximumSpanDegrees))°)"
            )
        }
        return .pinned(snapshot)
    }

    /// The camera the composition root should pin, and the banner to draw if the request was junk.
    ///
    /// Returns `nil` for the snapshot when nothing was asked for, which is every ordinary launch.
    static func resolve(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> (snapshot: MapCameraMemory.Snapshot?, failure: String?) {
        switch requested(environment) {
        case nil:
            return (nil, nil)
        case let .pinned(snapshot):
            return (snapshot, nil)
        case let .invalid(raw, reason):
            return (nil, "MAP CAMERA OVERRIDE FAILED · \(raw) · \(reason)")
        }
    }
}

/// Coordinates a UI test can open the map on without landing somewhere the inventory does not cover.
///
/// One entry, and it is deliberately the **same string** `DebugLocationFixtures.westernAddition`
/// holds — 780 trees inside the ±250 m box `Tools/run_tests.sh count_camera_trees` uses, measured
/// against `Cypress/Resources/cypress-seed.sqlite` on 2026-08-03 and recorded there.
/// `DebugMapCameraOverrideTests` asserts the two agree, so this is a second name for one measured
/// coordinate rather than a second coordinate.
///
/// **`MapLayout.defaultCenter` is not offered here**, and that is the point of having a list at all:
/// the app's own default is Mission Dolores Park, whose 120 × 261 m opening view contains no
/// inventoried tree — `defaultSpanMeters`' own doc comment says so, and `Tools/run_tests.sh` stamps
/// `viewport-trees=0` for it on every run. It is the right place for the app to open and the wrong
/// place for a test that needs a pin, a species color or a legend to be on screen.
enum DebugMapCameraFixtures {
    /// Western Addition — dense street inventory, and the fix `AlmanacGroupTapTests` has named since
    /// E153.
    static let westernAddition = "37.78485,-122.4215"
}
#endif
