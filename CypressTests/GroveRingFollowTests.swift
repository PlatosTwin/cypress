//
//  GroveRingFollowTests.swift
//  CypressTests
//
//  **ROADMAP 114, F38's follow-ups.** PR #207 made the My Grove ring read the reader's location,
//  and left three defects in that read:
//
//  1. It read the fix once, when the tab opened, and did not follow the reader while it stayed open.
//  2. It did not check how old the fix was, so a fix CoreLocation replayed from its cache was
//     captioned as where the reader is now.
//  3. Two reads that overlapped could finish out of order, and the older one could win.
//
//  No test here waits on a clock. The fix's age comes from an injected clock on the provider, and
//  the overlapping reads are held open by a gate that the test releases in the order it chooses.
//

import CoreLocation
import Foundation
import Observation
import Testing
@testable import Cypress

// MARK: - The fixture, outside the suite

/// The fixture's places, clock and groves.
///
/// **Outside the suite because the suite is `@MainActor`**, for `GroveFirstClock`'s reason: the
/// fakes answer from a nonisolated context and `GroveModel(now:)` takes a `@Sendable` closure, so
/// reading main-actor statics from either is a warning, and the test target holds a zero-warning line.
enum GroveFollowFixture {
    static let now = Date(timeIntervalSince1970: 1_784_505_600) // 2026-07-20

    /// Two places a kilometer apart, far more than `GroveModel.ringFollowDistanceM`.
    static let placeA = Coordinate(latitude: 37.7600, longitude: -122.4900)
    static let placeB = Coordinate(latitude: 37.7600, longitude: -122.4786)
    /// About 150 m north of A: one and a half blocks, just past `GroveModel.ringFollowDistanceM`.
    static let placeC = Coordinate(latitude: 37.76135, longitude: -122.4900)

    /// A grove whose ring is named for the place it was read at, so the phase says which read won.
    static func grove(named name: String) -> GroveSpecies {
        GroveSpecies(
            neighborhood: GroveNeighborhood(area: .named(name), species: .empty, basis: .whereYouAre),
            known: .empty
        )
    }

    static func name(of coordinate: Coordinate?) -> String {
        guard let coordinate else { return "most-visited" }
        if coordinate == placeA { return "A" }
        if coordinate == placeB { return "B" }
        if coordinate == placeC { return "C" }
        return "elsewhere"
    }
}

@MainActor
@Suite("Grove ring · follows the reader, refuses a stale fix, keeps the newest read (ROADMAP 114)")
struct GroveRingFollowTests {

    typealias F = GroveFollowFixture
    static let now = F.now
    static let placeA = F.placeA
    static let placeB = F.placeB
    static let placeC = F.placeC
    static func grove(named name: String) -> GroveSpecies { F.grove(named: name) }
    static func name(of coordinate: Coordinate?) -> String { F.name(of: coordinate) }

    /// A fix that arrived the moment it was taken.
    static func current(_ coordinate: Coordinate) -> GroveModel.RingFix {
        GroveModel.RingFix(
            availability: .located(coordinate, accuracyM: 8),
            timing: MapLocationProvider.FixTiming(capturedAt: now, receivedAt: now)
        )
    }

    /// The fix the model reads, changed by the test as the reader moves.
    final class FixBox {
        var fix: GroveModel.RingFix
        init(_ fix: GroveModel.RingFix) { self.fix = fix }
    }

    /// Answers every species read at once, with a ring named for the place asked, and records the
    /// places asked.
    final class ByPlaceAPI: CypressAPI, @unchecked Sendable {
        private let lock = NSLock()
        private var askedStorage: [Coordinate?] = []
        var asked: [Coordinate?] { lock.withLock { askedStorage } }

        func groveSpecies(near coordinate: Coordinate?) async throws -> GroveSpecies {
            lock.withLock { askedStorage.append(coordinate) }
            return GroveFollowFixture.grove(named: GroveFollowFixture.name(of: coordinate))
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
        func deleteAccount(_ choice: AccountDeletionChoice) async throws -> AccountDeletion.Outcome {
            throw APIError.unauthorized
        }
        func logHazardRedirect(_ event: HazardRedirectEvent) async throws {}
        func exportLatest(_ format: ExportFormat) async throws -> Data { Data() }
    }

    /// Holds every species read open until the test answers it.
    ///
    /// **A handshake, not a yield loop**, for the reason the comment on `SuspendingGroveAPI`
    /// (`GroveTreesPagingTests`) records: how many yields a main-actor task needs to reach its
    /// suspension depends on what the parallel suite is doing. `untilWaiting(_:)` suspends on a
    /// continuation that `wait(at:)` resumes once the count is reached, after the read has committed
    /// to suspending. Each test awaits it only for reads it has already seen start (`load()` called,
    /// or `followRead` set), so every wait has a read that will end it.
    @MainActor
    final class Gate {
        private var pending: [(Coordinate?, CheckedContinuation<GroveSpecies, Error>)] = []
        private var waiter: (count: Int, continuation: CheckedContinuation<Void, Never>)?

        var waiting: Int { pending.count }

        func wait(at coordinate: Coordinate?) async throws -> GroveSpecies {
            try await withCheckedThrowingContinuation { continuation in
                pending.append((coordinate, continuation))
                if let waiter, pending.count >= waiter.count {
                    self.waiter = nil
                    waiter.continuation.resume()
                }
            }
        }

        /// Returns once `count` reads are suspended here.
        func untilWaiting(_ count: Int) async {
            if pending.count >= count { return }
            await withCheckedContinuation { continuation in
                waiter = (count, continuation)
            }
        }

        private func take(at coordinate: Coordinate?) -> CheckedContinuation<GroveSpecies, Error>? {
            guard let index = pending.firstIndex(where: { $0.0 == coordinate }) else {
                Issue.record("no read is waiting at \(GroveFollowFixture.name(of: coordinate))")
                return nil
            }
            return pending.remove(at: index).1
        }

        func release(at coordinate: Coordinate?) {
            take(at: coordinate)?.resume(
                returning: GroveFollowFixture.grove(named: GroveFollowFixture.name(of: coordinate))
            )
        }

        func fail(at coordinate: Coordinate?) {
            take(at: coordinate)?.resume(throwing: APIError.serverError)
        }
    }

    final class GatedAPI: CypressAPI, @unchecked Sendable {
        let gate: Gate
        init(gate: Gate) { self.gate = gate }

        func groveSpecies(near coordinate: Coordinate?) async throws -> GroveSpecies {
            try await gate.wait(at: coordinate)
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
        func deleteAccount(_ choice: AccountDeletionChoice) async throws -> AccountDeletion.Outcome {
            throw APIError.unauthorized
        }
        func logHazardRedirect(_ event: HazardRedirectEvent) async throws {}
        func exportLatest(_ format: ExportFormat) async throws -> Data { Data() }
    }

    // MARK: - 1. The ring follows the reader while the tab is open

    @Test("a second fix a block and a half away, arriving while the tab is open, moves the ring there")
    func theRingFollowsASecondFix() async {
        let api = ByPlaceAPI()
        let box = FixBox(Self.current(Self.placeA))
        let model = GroveModel(api: api, now: { GroveFollowFixture.now }, currentFix: { box.fix })

        await model.load()
        model.screenDidAppear()
        #expect(model.phase == .loaded(Self.grove(named: "A")))

        // A walk of 20 m is inside `ringFollowDistanceM`: the ring is not read again for it.
        box.fix = Self.current(
            Coordinate(latitude: Self.placeA.latitude + 0.00018, longitude: Self.placeA.longitude)
        )
        model.followLocation()
        await model.followRead?.value

        // A walk of about 150 m, a block and a half, while the tab stays open.
        box.fix = Self.current(Self.placeC)
        model.followLocation()
        await model.followRead?.value

        #expect(
            model.phase == .loaded(Self.grove(named: "C")),
            "the reader walked 150 m while the tab was open and the ring still says \(model.phase)"
        )
        #expect(api.asked.map(Self.name(of:)) == ["A", "C"])
    }

    @Test("a fix that moves while a pushed screen covers My Grove is read on return, not before")
    func noFollowingWhileCovered() async {
        let api = ByPlaceAPI()
        let box = FixBox(Self.current(Self.placeA))
        let model = GroveModel(api: api, now: { GroveFollowFixture.now }, currentFix: { box.fix })
        await model.load()
        model.screenDidAppear()

        // A species page is pushed over My Grove, then the reader walks a kilometer.
        model.screenDidDisappear()
        box.fix = Self.current(Self.placeB)
        model.followLocation()
        await model.followRead?.value
        #expect(
            api.asked.map(Self.name(of:)) == ["A"],
            "the ring was read behind a screen that covers it: \(api.asked.map(Self.name(of:)))"
        )

        // Back on My Grove: the view's `.task` runs `load()` again, which reads where the reader is.
        model.screenDidAppear()
        await model.load()
        #expect(api.asked.map(Self.name(of:)) == ["A", "B"])
        #expect(model.phase == .loaded(Self.grove(named: "B")))
    }

    @Test("the follow rule: a block or more, or a fix gained or lost, reads again")
    func theFollowRule() {
        let a = Self.placeA
        let nearby = Coordinate(latitude: a.latitude + 0.00018, longitude: a.longitude) // about 20 m
        let aBlock = Coordinate(latitude: a.latitude + 0.0009, longitude: a.longitude)  // about 100 m
        #expect(GroveModel.ringHasMoved(from: a, to: aBlock))
        #expect(GroveModel.ringHasMoved(from: nil, to: a))
        #expect(GroveModel.ringHasMoved(from: a, to: nil))
        #expect(GroveModel.ringHasMoved(from: a, to: nearby) == false)
        #expect(GroveModel.ringHasMoved(from: nil, to: nil) == false)
    }

    // MARK: - 2. A fix older than the limit is not used

    @Test("a fix CoreLocation replayed from an hour ago is not where the reader is")
    func aStaleFixIsNotUsed() async throws {
        // The fix goes through the real provider's real delegate, with the provider's clock pinned,
        // so the age is the one the app would compute.
        let manager = CLLocationManager()
        let provider = MapLocationProvider(manager: manager, now: { GroveFollowFixture.now })
        let hourOld = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: Self.placeA.latitude, longitude: Self.placeA.longitude),
            altitude: 0,
            horizontalAccuracy: 8,
            verticalAccuracy: 1,
            timestamp: Self.now.addingTimeInterval(-3_600)
        )
        manager.delegate?.locationManager?(manager, didUpdateLocations: [hourOld])
        #expect(provider.availability.coordinate == Self.placeA)
        let timing = try #require(provider.fixTiming, "the provider kept no timing for the fix")
        #expect(timing.ageOnArrival == 3_600)

        let api = ByPlaceAPI()
        let model = GroveModel(
            api: api,
            now: { GroveFollowFixture.now },
            currentFix: { .init(availability: provider.availability, timing: provider.fixTiming) }
        )
        await model.load()

        #expect(
            api.asked.map(Self.name(of:)) == ["most-visited"],
            "an hour-old fix was used to place the ring"
        )
        #expect(model.phase == .loaded(Self.grove(named: "most-visited")))
    }

    /// Records that an observation fired. The `onChange` of `withObservationTracking` is `@Sendable`.
    final class Fired: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        var didFire: Bool { lock.withLock { value } }
        func fire() { lock.withLock { value = true } }
    }

    @Test("a replayed place confirmed by a fresh fix the provider does not republish becomes usable")
    func aReplayedPlaceTurnsFresh() throws {
        let manager = CLLocationManager()
        let provider = MapLocationProvider(manager: manager, now: { GroveFollowFixture.now })
        func deliver(_ coordinate: Coordinate, takenSecondsAgo age: TimeInterval) {
            let location = CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude),
                altitude: 0,
                horizontalAccuracy: 8,
                verticalAccuracy: 1,
                timestamp: GroveFollowFixture.now.addingTimeInterval(-age)
            )
            manager.delegate?.locationManager?(manager, didUpdateLocations: [location])
        }
        func ring() -> Coordinate? {
            GroveModel.ringCoordinate(.init(availability: provider.availability, timing: provider.fixTiming))
        }

        // CoreLocation replays an hour-old fix at A: the ring cannot use it.
        // (`aStaleFixIsNotUsed` covers the ring refusing it; this test is about the turn to fresh.)
        deliver(Self.placeA, takenSecondsAgo: 3_600)
        #expect(provider.fixIsReplayed)

        // A fresh fix 2 m away with the same accuracy: `isWorthPublishing` drops it, so
        // `availability` stays as it was, and only `fixIsReplayed` can tell the view.
        let fired = Fired()
        withObservationTracking { _ = provider.fixIsReplayed } onChange: { fired.fire() }
        deliver(Coordinate(latitude: Self.placeA.latitude + 0.000018, longitude: Self.placeA.longitude),
                takenSecondsAgo: 0)

        #expect(provider.availability.coordinate == Self.placeA, "the fresh fix was republished; this measures the wrong path")
        #expect(fired.didFire, "nothing observable changed when the replayed place turned fresh")
        #expect(provider.fixIsReplayed == false)
        #expect(ring() == Self.placeA, "a reader standing where the fix says still gets the most-visited ring")
    }

    @Test("the age is the age on arrival: a fix taken long ago that arrived at once is still used")
    func ageIsMeasuredOnArrival() {
        let longAgo = Self.now.addingTimeInterval(-3_600)
        let stillStanding = GroveModel.RingFix(
            availability: .located(Self.placeA, accuracyM: 8),
            timing: MapLocationProvider.FixTiming(capturedAt: longAgo, receivedAt: longAgo)
        )
        #expect(GroveModel.ringCoordinate(stillStanding) == Self.placeA)

        let atTheLimit = GroveModel.RingFix(
            availability: .located(Self.placeA, accuracyM: 8),
            timing: MapLocationProvider.FixTiming(
                capturedAt: Self.now.addingTimeInterval(-GroveModel.ringFixMaxAgeOnArrival),
                receivedAt: Self.now
            )
        )
        #expect(GroveModel.ringCoordinate(atTheLimit) == Self.placeA)
    }

    @Test("a pinned provider (CYPRESS_LOCATION, R58) gives a fix the ring uses")
    func aPinnedFixIsCurrent() {
        let pinned = MapLocationProvider(pinnedAvailability: .located(Self.placeA, accuracyM: 8))
        let fix = GroveModel.RingFix(availability: pinned.availability, timing: pinned.fixTiming)
        #expect(GroveModel.ringCoordinate(fix) == Self.placeA)
    }

    // MARK: - 3. The newest read wins

    @Test("two overlapping reads resolved in reverse order: the newer read's ring stands")
    func theNewestReadWins() async throws {
        let gate = Gate()
        let box = FixBox(Self.current(Self.placeA))
        let model = GroveModel(api: GatedAPI(gate: gate), now: { GroveFollowFixture.now }, currentFix: { box.fix })

        model.screenDidAppear()

        // The first read, at A, is held open.
        let first = Task { await model.load() }
        await gate.untilWaiting(1)

        // The reader moves to B while it is still open, and a second read starts.
        box.fix = Self.current(Self.placeB)
        model.followLocation()
        let second = try #require(model.followRead, "the second read never started; the test cannot overlap them")
        await gate.untilWaiting(2)

        // The newer read finishes first, then the older one.
        gate.release(at: Self.placeB)
        await second.value
        gate.release(at: Self.placeA)
        await first.value

        #expect(
            model.phase == .loaded(Self.grove(named: "B")),
            "the older read finished last and its ring replaced the newer one: \(model.phase)"
        )
    }

    @Test("a newer read that fails under an older one does not pin the older place on screen")
    func aFailedNewerReadIsReadAgain() async throws {
        let gate = Gate()
        let box = FixBox(Self.current(Self.placeA))
        let model = GroveModel(api: GatedAPI(gate: gate), now: { GroveFollowFixture.now }, currentFix: { box.fix })
        model.screenDidAppear()

        let first = Task { await model.load() }
        await gate.untilWaiting(1)
        box.fix = Self.current(Self.placeB)
        model.followLocation()
        let failing = try #require(model.followRead, "the read at B never started")
        await gate.untilWaiting(2)

        // The read at B fails; the read at A then paints A.
        gate.fail(at: Self.placeB)
        await failing.value
        gate.release(at: Self.placeA)
        await first.value
        #expect(model.phase == .loaded(Self.grove(named: "A")))

        // The reader is still at B. The next trigger has to read B again.
        model.followLocation()
        let retry = try #require(
            model.followRead.flatMap { $0 == failing ? nil : $0 },
            "the screen shows A, the reader is at B, and the next trigger read nothing"
        )
        await gate.untilWaiting(1)
        gate.release(at: Self.placeB)
        await retry.value
        #expect(model.phase == .loaded(Self.grove(named: "B")))
    }
}
