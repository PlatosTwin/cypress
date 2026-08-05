//
//  AlmanacLocationTransitionTests.swift
//  CypressTests
//
//  ERRATA E123's residual (#223): "granting location while standing on the almanac does not
//  reactively reload it" — recorded as a known limitation, then half-fixed by E155, which made the
//  almanac reload on *any* changed coordinate rather than specifically on a grant. That over-shoots:
//  `MapLocationProvider` rewrites `availability` on every published fix, five meters of walking apart
//  (`MapLocationProvider.publishDistanceM`), and a screen 12 that reloaded on each of those would
//  re-read the whole almanac once per five meters — the "per tick" churn this round's ticket forbids.
//
//  ── Two suites, for the two things that could each be right and the other wrong ────────────
//  1. `AlmanacModel.isFixAvailabilityTransition` is pure and `static`, tested at its boundary the way
//     `MapLocationProvider.isWorthPublishing` already is in `MapLocationChurnTests` — a rule that is
//     right and never called is exactly the failure this file also has to rule out.
//  2. `AlmanacModel.observeLocation()` is the wiring, tested by driving a **real**
//     `MapLocationProvider` through its real `CLLocationManagerDelegate` — `RecordingManager` is
//     `MapLocationChurnTests`' own double, copied rather than imported because it is private there.
//     A predicate that is correct and not wired up is the specific defect `MapLocationChurnTests`'
//     own doc comment names, and it is exactly the shape of bug this file is guarding against too.
//

import CoreLocation
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Cypress

@MainActor
@Suite("Screen 12 reloads on the fix it gains, not on the fix it already has (ERRATA E123 residual, #223)")
struct AlmanacLocationTransitionTests {

    // MARK: - Fixtures

    static let fix = Coordinate(latitude: 37.7530, longitude: -122.4850)
    /// ~7 m north of `fix` — inside `MapLocationProvider.publishDistanceM`'s republish threshold,
    /// so CoreLocation genuinely republishes it, and still well inside the same neighborhood: a real
    /// drift, not a different fix in any sense but coordinates.
    static let fixAfterDrift = Coordinate(latitude: 37.753_063, longitude: -122.4850)

    // MARK: - Doubles

    /// `almanac(near:)`'s contract only, and every read counted — `AlmanacLateFixTests.FixSensitive`
    /// in shape, kept separate because that one is private to its own suite.
    private final class ReadCountingAPI: CypressAPI, @unchecked Sendable {
        private(set) var reads: [Coordinate?] = []

        func almanac(near coordinate: Coordinate?) async throws -> Almanac {
            reads.append(coordinate)
            return .empty
        }

        func mapContent(in viewport: MapViewport) async throws -> MapContent { .pins([]) }
        func treesNear(_ c: Coordinate, radiusM: Double, limit: Int) async throws -> [NearbyTree] { [] }
        func treeProfile(id: UUID) async throws -> TreeProfile { throw APIError.notFound }
        func addTree(_ draft: TreeDraft) async throws -> Tree { throw APIError.forbidden }
        func species(id: UUID) async throws -> Species { throw APIError.notFound }
        func searchSpecies(query: String, limit: Int) async throws -> [Species] { [] }
        func sync(_ items: [OutboxItem]) async throws -> [SyncResult] { [] }
        func beginPhotoUpload(_ r: PhotoUploadRequest) async throws -> PhotoUploadTicket {
            throw APIError.forbidden
        }
        func uploadPhoto(at localPath: String, ticket: PhotoUploadTicket) async throws {}
        func grove() async throws -> [GroveEntry] { [] }
        func journal(cursor: String?, limit: Int) async throws -> Page<JournalEntry> { Page(items: []) }
        func claimDevice(deviceUUID: UUID, userID: UUID) async throws {}
        func logHazardRedirect(_ event: HazardRedirectEvent) async throws {}
        func exportLatest(_ format: ExportFormat) async throws -> Data { Data() }
    }

    /// `ReadCountingAPI`, with one difference that matters only for the mount-race test below: a
    /// real suspension inside `almanac(near:)`, via `Task.yield()`.
    ///
    /// **Why `ReadCountingAPI` itself cannot expose the race `mountingWithALiveProviderDoesNotDoubleRead`
    /// is about.** Its `almanac(near:)` has no `await` in its body, and calling an `async` function
    /// that never itself suspends does not guarantee a scheduler yield — Swift can and does run it to
    /// completion in the same executor turn as its caller. `AlmanacModel.update(coordinate:)`'s two
    /// racing callers (the view's own `.task(id:)` and `AlmanacModel.observeLocation()`) therefore
    /// never actually interleave against `ReadCountingAPI`: the first caller's whole call chain —
    /// guard, assignment, read, `phase = .loaded(...)` — completes before the second caller gets a
    /// turn, so by the time it checks its own guard, `phase` is no longer `.loading` and the second
    /// call is correctly refused regardless of whether `AlmanacView`'s gate exists. Measured directly:
    /// the first attempt at this test used `ReadCountingAPI` and stayed green with the gate deleted.
    /// `Task.yield()` opens the window a real database read already has — `AlmanacLateFixTests.Held`
    /// exists for the identical reason, one call away from a `CypressAPI` read never being able to
    /// show an ordering defect at all.
    private final class SuspendingReadCountingAPI: CypressAPI, @unchecked Sendable {
        private(set) var reads: [Coordinate?] = []

        func almanac(near coordinate: Coordinate?) async throws -> Almanac {
            reads.append(coordinate)
            await Task.yield()
            return .empty
        }

        func mapContent(in viewport: MapViewport) async throws -> MapContent { .pins([]) }
        func treesNear(_ c: Coordinate, radiusM: Double, limit: Int) async throws -> [NearbyTree] { [] }
        func treeProfile(id: UUID) async throws -> TreeProfile { throw APIError.notFound }
        func addTree(_ draft: TreeDraft) async throws -> Tree { throw APIError.forbidden }
        func species(id: UUID) async throws -> Species { throw APIError.notFound }
        func searchSpecies(query: String, limit: Int) async throws -> [Species] { [] }
        func sync(_ items: [OutboxItem]) async throws -> [SyncResult] { [] }
        func beginPhotoUpload(_ r: PhotoUploadRequest) async throws -> PhotoUploadTicket {
            throw APIError.forbidden
        }
        func uploadPhoto(at localPath: String, ticket: PhotoUploadTicket) async throws {}
        func grove() async throws -> [GroveEntry] { [] }
        func journal(cursor: String?, limit: Int) async throws -> Page<JournalEntry> { Page(items: []) }
        func claimDevice(deviceUUID: UUID, userID: UUID) async throws {}
        func logHazardRedirect(_ event: HazardRedirectEvent) async throws {}
        func exportLatest(_ format: ExportFormat) async throws -> Data { Data() }
    }

    /// `MapLocationChurnTests.RecordingManager`, copied: a `CLLocationManager` that answers
    /// "allowed" (or whatever the test stubs) without opening a real session, so the *real*
    /// `MapLocationProvider` delegate path can be driven deterministically.
    private final class RecordingManager: CLLocationManager {
        var stubbedAuthorization: CLAuthorizationStatus = .authorizedWhenInUse
        override var authorizationStatus: CLAuthorizationStatus { stubbedAuthorization }
        override func startUpdatingLocation() {}
        override func stopUpdatingLocation() {}
        override func requestWhenInUseAuthorization() {}
    }

    private static func location(_ latitude: Double, _ longitude: Double, accuracy: Double = 5) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: 0,
            horizontalAccuracy: accuracy,
            verticalAccuracy: 1,
            timestamp: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    /// Pushes a fix through the **real** delegate the provider installed — the only path the app
    /// itself ever uses to learn about one.
    private static func deliver(_ latitude: Double, _ longitude: Double, to manager: CLLocationManager) {
        manager.delegate?.locationManager?(manager, didUpdateLocations: [Self.location(latitude, longitude)])
    }

    /// Polls `condition` instead of guessing a sleep, and gives up after `timeout` rather than
    /// hanging the suite — the same shape `AlmanacLateFixTests.promptSurvivesUntilContentArrives`
    /// gives its own latch-based wait, adapted here because the thing being waited on is a poll loop
    /// rather than a single suspended read.
    private static func waitUntil(
        timeout: Duration = .seconds(3),
        _ condition: () -> Bool
    ) async {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    // MARK: - The predicate, at its boundary (mirrors MapLocationProvider.isWorthPublishing's tests)

    @Test("gaining a fix where there was none is a reload transition")
    func gainingAFixIsATransition() {
        let noFixStates: [MapLocationProvider.Availability] = [.notAsked, .waitingForFix, .denied, .servicesOff]
        for previous in noFixStates {
            #expect(
                AlmanacModel.isFixAvailabilityTransition(from: previous, to: .located(Self.fix, accuracyM: 5)),
                "\(previous) → located did not count as gaining a fix"
            )
        }
    }

    @Test("losing a fix is also a transition — the prompt has to be able to come back (E126's invariant)")
    func losingAFixIsATransition() {
        let noFixStates: [MapLocationProvider.Availability] = [.notAsked, .waitingForFix, .denied, .servicesOff]
        for next in noFixStates {
            #expect(
                AlmanacModel.isFixAvailabilityTransition(from: .located(Self.fix, accuracyM: 5), to: next),
                "located → \(next) did not count as losing a fix"
            )
        }
    }

    /// **The case this whole entry is about.** Two different `.located` payloads — a real,
    /// republish-worthy 7 m walk — are not a boundary crossing: the reader had a fix before and has
    /// one now, and re-reading the almanac for it is the exact "per tick" churn ruled out above.
    @Test("moving within an existing fix is not a transition")
    func driftWithinAFixIsNotATransition() {
        #expect(!AlmanacModel.isFixAvailabilityTransition(
            from: .located(Self.fix, accuracyM: 5),
            to: .located(Self.fixAfterDrift, accuracyM: 5)
        ))
    }

    @Test("an accuracy-only change, with no movement, is not a transition either")
    func accuracyOnlyChangeIsNotATransition() {
        #expect(!AlmanacModel.isFixAvailabilityTransition(
            from: .located(Self.fix, accuracyM: 5),
            to: .located(Self.fix, accuracyM: 30)
        ))
    }

    @Test("no change at all is never a transition")
    func noChangeIsNotATransition() {
        let states: [MapLocationProvider.Availability] = [
            .notAsked, .waitingForFix, .denied, .servicesOff, .located(Self.fix, accuracyM: 5)
        ]
        for state in states {
            #expect(!AlmanacModel.isFixAvailabilityTransition(from: state, to: state))
        }
    }

    // MARK: - The wiring: observeLocation() actually reloads on the transition, and only on it

    /// The reproduction E123 named and left as-is, and E155 only partly closed: stand on the
    /// almanac before CoreLocation has answered, then grant. Driven through the real
    /// `MapLocationProvider`/`CLLocationManagerDelegate` path, not by calling `update(coordinate:)`
    /// directly — a model that reloads when told to and a model that reloads because it noticed the
    /// grant are different claims, and only the second is what this ticket is about.
    @Test("A grant while the almanac is open reloads it")
    func grantWhileOpenReloads() async {
        let manager = RecordingManager()
        manager.stubbedAuthorization = .notDetermined
        let provider = MapLocationProvider(manager: manager)
        provider.start()

        let api = ReadCountingAPI()
        let model = AlmanacModel(
            api: api,
            coordinate: nil,
            location: provider,
            locationPollInterval: .milliseconds(5)
        )
        let observer = Task { await model.observeLocation() }
        defer { observer.cancel() }

        // The mount-time read: nobody has answered the sheet yet, so this is `nil` — the same
        // picture a cold launch draws.
        await Self.waitUntil { api.reads.count >= 1 }
        #expect(api.reads == [nil])
        #expect(model.needsLocation)

        // The grant, exactly as CoreLocation reports one: the authorization callback first, a fix a
        // moment later.
        manager.stubbedAuthorization = .authorizedWhenInUse
        manager.delegate?.locationManagerDidChangeAuthorization?(manager)
        Self.deliver(37.7530, -122.4850, to: manager)

        await Self.waitUntil { api.reads.count >= 2 }
        #expect(api.reads == [nil, Self.fix], "the grant was not read at all")
        #expect(model.needsLocation == false, "the prompt would still be over the content")
    }

    /// The other half of the same claim: once fixed, walking must not re-read the almanac.
    ///
    /// The provider already has a fix *before* the model is built — the ordinary case, reached by
    /// opening the almanac after the map screen already has one — so the only read this test permits
    /// is the mount-time one, and everything after the drift has to be silence.
    @Test("Coordinate drift within an existing fix does not reload")
    func driftDoesNotReload() async {
        let manager = RecordingManager()
        manager.stubbedAuthorization = .authorizedWhenInUse
        let provider = MapLocationProvider(manager: manager)
        provider.start()
        Self.deliver(37.7530, -122.4850, to: manager)
        #expect(provider.availability.coordinate == Self.fix, "the fixture did not actually fix")

        let api = ReadCountingAPI()
        let model = AlmanacModel(
            api: api,
            coordinate: nil,
            location: provider,
            locationPollInterval: .milliseconds(5)
        )
        let observer = Task { await model.observeLocation() }
        defer { observer.cancel() }

        await Self.waitUntil { api.reads.count >= 1 }
        #expect(api.reads == [Self.fix], "the mount-time read did not see the fix already there")

        // A real walk, ~7 m — `MapLocationProvider` genuinely republishes this (verified below),
        // so a bug that reloads on any republished coordinate would pass every check above and only
        // fail here.
        Self.deliver(37.753_063, -122.4850, to: manager)
        #expect(
            provider.availability.coordinate == Self.fixAfterDrift,
            "the fixture's drift fix was not far enough to republish, so this test proves nothing"
        )

        // No event to wait *for* here — the claim is silence, so the loop is given many ticks to
        // prove it rather than one, the same reasoning `AlmanacLateFixTests.render`'s bounded
        // polling gives for why a fixed pass count beats a single guessed sleep.
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(api.reads == [Self.fix], "coordinate drift inside an existing fix re-read the almanac")
    }

    // MARK: - The view's own gate: two mount-time triggers must not race (adversarial review, PR #17)

    /// Mounts `AlmanacView` with a live `location:` supplied, so **both** reload paths are active
    /// from the first frame: the view's own `.task(id: coordinate)` (which always fires once at
    /// mount, whatever `id` starts at — see `AlmanacView.body`'s comment) and
    /// `AlmanacModel.observeLocation()` (which performs its own, separate mount-time read). Neither
    /// of this file's other tests can see a race between the two: the pure-predicate tests never
    /// touch a view, and `grantWhileOpenReloads`/`driftDoesNotReload` build `AlmanacModel` directly,
    /// so `AlmanacView`'s `.task(id: coordinate)` never runs at all in them.
    ///
    /// `AlmanacLateFixTests.LateFixHost` is the shape this borrows — `UIHostingController` in a
    /// visible off-screen window, because `.task` never runs on a view that is never part of an
    /// active hierarchy.
    private struct MountHost: View {
        let api: any CypressAPI
        let location: MapLocationProvider

        var body: some View {
            AlmanacView(api: api, coordinate: location.availability.coordinate, location: location)
        }
    }

    /// **What `AlmanacView.swift:114`'s `guard location == nil else { return }` is for.** Both of
    /// `AlmanacModel.update(coordinate:)`'s callers race while `phase` is still `.loading` — the one
    /// window in which its own `newValue != coordinate` guard cannot help, because `phase ==
    /// .loading` is the *other* half of that guard's `||` and is true for both callers at once. Post-
    /// mount transitions do not have this problem (`grantWhileOpenReloads` above proves a real grant
    /// reads exactly once), which is exactly why deleting this one gate does not fail either of this
    /// file's other tests — only a mount with a live provider can see it.
    @Test("Mounting with a live provider does not double-read at mount")
    func mountingWithALiveProviderDoesNotDoubleRead() async {
        let manager = RecordingManager()
        manager.stubbedAuthorization = .notDetermined
        let provider = MapLocationProvider(manager: manager)
        provider.start()

        let api = SuspendingReadCountingAPI()
        let host = UIHostingController(rootView: MountHost(api: api, location: provider))
        let window = UIWindow(frame: CGRect(x: -2_000, y: 0, width: 393, height: 852))
        window.rootViewController = host
        window.isHidden = false
        window.layoutIfNeeded()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        // Both of `AlmanacView`'s `.task` modifiers start at mount and race there — give them many
        // short passes rather than one guessed sleep, the same reasoning `driftDoesNotReload`'s own
        // tail gives for proving a silence instead of timing one.
        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(
            api.reads == [nil],
            "the mount-time read fired more than once — AlmanacView's own gate on the old .task(id:) path did not hold"
        )
    }
}
