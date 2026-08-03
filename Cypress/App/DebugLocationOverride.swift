//
//  DebugLocationOverride.swift
//  Cypress — App
//
//  A launch-time way to say where the phone is, for the UI test target and nothing else
//  (task #121; the ruling is `docs/rulings-pending/location-state-launch-seam.md`).
//
//  ── Why this exists ───────────────────────────────────────────────────────────────────────
//  Two UI tests used to decide at runtime whether they were going to run at all, by *detecting*
//  the simulator's ambient location state and throwing `XCTSkip` when it was not the one they
//  needed. `MapRecenterUITests` skipped whenever location was not denied — which is every
//  simulator anybody has ever handed it — so the entire permission-denied refusal path went
//  unexercised in every ordinary run. `AlmanacGroupTapTests` skipped whenever there was no fix.
//
//  Both skips were honestly documented and honestly reasoned: a skip says "not checked here",
//  which is true, where a failure would say "broken", which is not. The problem was never
//  dishonesty at the site. It is that a skipped test is invisible in the line this project
//  judges a run by — `Test run with N tests passed` counts a test that declined to run exactly
//  the same as one that ran and passed — so a suite could go green with the refusal path never
//  once exercised and nobody reading the number would know.
//
//  The cure for a test that detects state is to let it *drive* the state. That is this file.
//  With `CYPRESS_LOCATION` set, the app's one shared `MapLocationProvider` is a pinned double
//  that reports exactly the availability the launching process named, and both tests become
//  unconditional.
//
//  ── What it deliberately is not ───────────────────────────────────────────────────────────
//  **Not a setting, and not reachable from the app.** Like `DebugDeepLink`, it is read from the
//  process environment — a thing only whoever launched the process can write — rather than from
//  `launchArguments` (which `NSUserDefaults` also consumes, so a test seam would be writing to
//  the reader's preferences) and rather than from any UI. The whole file is `#if DEBUG`, and so
//  is its one call site in `RootView`.
//
//  **Not a replacement for `xcrun simctl privacy … revoke location`.** Pinning changes what the
//  *app* believes; it does not change what CoreLocation would say. That distinction matters and
//  is stated in the ruling: this seam proves the app's behavior in each state, not CoreLocation's
//  behavior in producing it. A test that needs the real system permission sheet — the Springboard
//  alert — still needs the real device state, and `AlmanacGroupTapTests` still taps that alert
//  through when it appears.
//
//  **Not a way to make an empty map look full.** A pinned coordinate moves the map to it, which
//  means it also gets written into `map.lastCamera` on the way out, which E216's preflight then
//  reads on the next run. Every coordinate this file offers as a default is one the seed has
//  hundreds of trees around, and `LocationFixtures` below records the counts and how they were
//  measured.
//
//  ── The one thing it must never do quietly ────────────────────────────────────────────────
//  Fail. A typo in `CYPRESS_LOCATION` must not fall back to the real provider and let a test pass
//  while asserting the wrong state — that is `DebugDeepLink.Failure`'s lesson, and the same answer
//  is used: an unparseable value becomes a banner drawn on top of the app, in words.
//

#if DEBUG
import CoreLocation
import Foundation

/// The test-only way to pin the app's idea of where the phone is. `#if DEBUG`; see the file comment.
enum DebugLocationOverride {

    /// Read from the environment, for `DebugDeepLink.environmentKey`'s reasons.
    static let environmentKey = "CYPRESS_LOCATION"

    /// What the launching process asked for.
    ///
    /// `.invalid` rather than `nil` for an unrecognized value, for exactly the reason
    /// `DebugDeepLink.requested()` distinguishes a typo from an absence: a seam that quietly did
    /// nothing would leave a test asserting the denied refusal path against a simulator that has a
    /// perfectly good fix, and the test would fail somewhere else entirely — or worse, pass.
    enum Request: Equatable {
        case pinned(MapLocationProvider.Availability)
        case invalid(raw: String, reason: String)
    }

    /// The accuracy a pinned fix reports, in meters.
    ///
    /// **Eight, and the number is a decision rather than a placeholder.** D6 excludes a reading
    /// worse than 15 m from growth charting and treats a missing accuracy as unusable, so a pinned
    /// fix that reported a pessimistic number would silently empty every chart built on top of it —
    /// the app would be in a state no reader is ever in, and a test standing on it would be
    /// measuring the exclusion rather than the screen. Eight metres is a plausible street-canyon
    /// fix, comfortably inside D6's gate, and coarser than anything that would make a shortlist
    /// ranking degenerate.
    ///
    /// A caller that wants to sit on the wrong side of D6 on purpose says so: `lat,lon,accuracy`.
    static let defaultAccuracyM: Double = 8

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
    /// Four named states, plus a coordinate. The named states are spelled exactly as
    /// `MapLocationProvider.Availability`'s own cases, so there is one vocabulary rather than two:
    /// a reader who knows what `waitingForFix` means in the app knows what to type here.
    ///
    ///     CYPRESS_LOCATION=denied                       the reader said no
    ///     CYPRESS_LOCATION=servicesOff                  Location Services off device-wide
    ///     CYPRESS_LOCATION=notAsked                     the sheet has not been shown
    ///     CYPRESS_LOCATION=waitingForFix                allowed, no fix yet
    ///     CYPRESS_LOCATION=37.78485,-122.4215           a fix, at `defaultAccuracyM`
    ///     CYPRESS_LOCATION=37.78485,-122.4215,25        a fix, at a stated accuracy
    static func parse(_ raw: String) -> Request {
        switch raw {
        case "denied":        return .pinned(.denied)
        case "servicesOff":   return .pinned(.servicesOff)
        case "notAsked":      return .pinned(.notAsked)
        case "waitingForFix": return .pinned(.waitingForFix)
        default: break
        }

        let parts = raw.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2 || parts.count == 3 else {
            return .invalid(
                raw: raw,
                reason: "expected denied | servicesOff | notAsked | waitingForFix | lat,lon[,accuracyM]"
            )
        }
        guard let latitude = Double(parts[0]), let longitude = Double(parts[1]) else {
            return .invalid(raw: raw, reason: "latitude and longitude must be numbers")
        }
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            return .invalid(raw: raw, reason: "latitude must be within ±90 and longitude within ±180")
        }
        var accuracy = defaultAccuracyM
        if parts.count == 3 {
            guard let stated = Double(parts[2]), stated > 0 else {
                return .invalid(raw: raw, reason: "accuracy must be a positive number of meters")
            }
            accuracy = stated
        }
        return .pinned(
            .located(Coordinate(latitude: latitude, longitude: longitude), accuracyM: accuracy)
        )
    }

    /// The provider the composition root should use, and the banner to draw if the request was junk.
    ///
    /// Returns `nil` for the provider when nothing was asked for, which is every ordinary launch.
    static func resolve(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> (provider: MapLocationProvider?, failure: String?) {
        switch requested(environment) {
        case nil:
            return (nil, nil)
        case let .pinned(availability):
            return (MapLocationProvider(pinnedAvailability: availability), nil)
        case let .invalid(raw, reason):
            return (nil, "LOCATION OVERRIDE FAILED · \(raw) · \(reason)")
        }
    }
}

/// Coordinates a UI test can pin without moving the map somewhere the inventory does not cover.
///
/// **The counts below were measured, not remembered** — E216 is the record of what it costs to put
/// a simulator's fix on a block SF's *street* tree inventory has no rows for: two UI tests fail
/// naming the map, and they look exactly like a defect in whatever you just changed. A pinned fix
/// has the same reach as a `simctl location`, because screen 01 flies to it and `MapCameraMemory`
/// writes it out on the way to the background, where the next run's preflight reads it back.
///
/// Measured against `Cypress/Resources/cypress-seed.sqlite` on 2026-08-03, over the same ±250 m box
/// `Tools/run_tests.sh count_camera_trees` uses, so these numbers and that guard's threshold are the
/// same question asked the same way:
///
///     37.78485, -122.4215   Western Addition    780 trees
///     37.7596,  -122.4269   the map's own default center, Mission Dolores    553 trees
enum DebugLocationFixtures {
    /// Western Addition — the fix `AlmanacGroupTapTests`' own comments have named since E153, and
    /// the neighborhood those tests' counted rows were written against.
    static let westernAddition = "37.78485,-122.4215"
    /// `MapLayout.defaultCenter`, which is also E216's repair coordinate.
    static let missionDolores = "37.7596,-122.4269"
}
#endif
