import Foundation
import Testing
import UIKit
@testable import Cypress

/// The community add, from the screen that now performs it (ERRATA E127).
///
/// `ProximityDedupeTests` already drives `LocalAPI.addTree` directly and proves the 10 m circle and
/// its diagonal. This suite is about the half that did not exist: the *caller*. `addTree` shipped
/// complete, and nothing in the app ever called it — screen 02's "None of these? Add this tree" was
/// drawn at full opacity and wired to dismiss the flow.
///
/// So the assertions here are of the form "the screen and the boundary agree": the CTA is refused
/// for exactly the reasons `addTree` would throw. Since the owner's ruling of 2026-11-14 a tree
/// within 10 m of another is one of neither: the screen lists the trees nearby under a note
/// (`VisitAddTreeModel.nearby`, read through `treesNear`) and adds the tree anyway.
@Suite("Community add")
struct CommunityAddTests {

    private static let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-00000000AD01")!
    private static var attribution: Attribution { .anonymous(deviceID: deviceID) }
    private static let spot = Coordinate(latitude: 37.7761, longitude: -122.4464)

    /// A staged photo file, which is what `addTree` requires and what `VisitPhotoStaging` writes on
    /// the shipping path. A real file on disk, because "a photo that cannot be written is not a
    /// photo" is the rule the model keeps and a fictional path would not exercise it.
    ///
    /// Two bare JPEG markers used to do, because staging only wrote the bytes down. It rewrites the
    /// container to drop the metadata now (E148) and refuses bytes that are not one — that refusal is
    /// the behavior E148 exists for — so the fixture is the same real photograph the model is given.
    @MainActor
    private static func stagedPhoto() throws -> String {
        try VisitPhotoStaging.write(try jpeg(), for: UUID(), shotType: .fullTree)
    }

    @MainActor
    private static func model(
        api: any CypressAPI,
        fix: VisitLocationProvider.Fix
    ) -> VisitAddTreeModel {
        VisitAddTreeModel(
            api: api,
            location: VisitLocationProvider(pinnedFix: fix),
            attribution: attribution
        )
    }

    // MARK: - The two gates, which are the boundary's own

    @MainActor
    @Test("with no fix there is nothing to add, and the screen says which of the two is missing")
    func aFixIsRequired() async throws {
        let api = LocalAPI(store: try await CypressStore.inMemory(), deviceID: Self.deviceID)

        let subject = Self.model(api: api, fix: .pending)
        #expect(!subject.canAdd)
        #expect(subject.blockingReason == VisitAddTreeCopy.noLocationPending)

        // Refused location is a different sentence, because "waiting" would be a lie and "turn it on
        // in Settings" is only actionable in one of the two states.
        let refused = Self.model(api: api, fix: .denied)
        #expect(refused.blockingReason == VisitAddTreeCopy.noLocationDenied)
    }

    @MainActor
    @Test("with a fix and no photo the CTA is still refused, for the reason the API would refuse it")
    func aPhotoIsRequired() async throws {
        let api = LocalAPI(store: try await CypressStore.inMemory(), deviceID: Self.deviceID)

        let subject = Self.model(api: api, fix: .located(Self.spot, accuracyM: 6))
        #expect(!subject.canAdd)
        #expect(subject.blockingReason == VisitAddTreeCopy.noPhoto)

        // And the boundary agrees: this is `addTree`'s own first line.
        await #expect(throws: APIError.validationFailed) {
            _ = try await api.addTree(
                TreeDraft(coordinate: Self.spot, photoLocalPath: "", attribution: Self.attribution)
            )
        }
    }

    @MainActor
    @Test("a photo and a fix is the whole of it")
    func bothGatesMetOpensTheCTA() async throws {
        let store = try await CypressStore.inMemory()
        let subject = Self.model(
            api: LocalAPI(store: store, deviceID: Self.deviceID),
            fix: .located(Self.spot, accuracyM: 6)
        )
        subject.useLibraryImage(try Self.jpeg())

        #expect(subject.hasPhoto)
        #expect(subject.blockingReason == nil)
        #expect(subject.canAdd)
    }

    // MARK: - The add itself

    @MainActor
    @Test("the tree the screen adds is a community tree at the reader's own fix")
    func addWritesACommunityTreeWhereTheReaderIs() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let subject = Self.model(api: api, fix: .located(Self.spot, accuracyM: 6))
        subject.useLibraryImage(try Self.jpeg())

        let id = try #require(await subject.add(), "the add returned no tree")

        let profile = try await api.treeProfile(id: id)
        #expect(profile.tree.source == .community)
        #expect(profile.tree.verificationState == .unverified)
        #expect(profile.tree.coordinate.distance(to: Self.spot) < 0.5)
        // BUILD-PLAN §6: the photo is not optional, and it arrives on the record with the tree.
        #expect(!profile.photos.items.isEmpty, "the tree was added without the photo that justified it")
        // No species is claimed. Inventing one would be fabricated botany (BUILD-PLAN §15), and the
        // record's own `community-added, unverified` provenance is the honest reading of it.
        #expect(profile.tree.speciesCurrentID == nil)
    }

    // MARK: - The trees already on record nearby: a note, then still add

    /// **The owner's answer of 2026-11-14, on the path that ships: a note, then still add.**
    ///
    /// Driven through `VisitAddTreeModel`, not through `addTree`, because that is the difference
    /// between "the API allows it" and "the person adding a tree is told and is not stopped". The
    /// note is read before the tap, the CTA is active under it, and one tap adds the tree.
    ///
    /// Red-proofs: make `refreshNearby` leave `nearby` empty — red on "the note names no tree".
    /// Make `canAdd` require `nearby.isEmpty` — red on "the note disabled the button".
    @MainActor
    @Test("with a tree 4 m away the note lists it before the tap, the button stays active, and one tap adds")
    func theNoteShowsAndTheAddStillHappens() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)

        let first = try await api.addTree(
            TreeDraft(coordinate: Self.spot, photoLocalPath: try Self.stagedPhoto(), attribution: Self.attribution)
        )

        // Four meters on the diagonal — well inside the circle, and inside the box too, so this
        // passes for the right reason rather than because of E35's square.
        let closeBy = ProximityDedupeTests.diagonal(from: Self.spot, meters: 4)
        let subject = Self.model(api: api, fix: .located(closeBy, accuracyM: 6))
        subject.useLibraryImage(try Self.jpeg())

        // Before the tap: the view reads the note when the pin's position is first known.
        #expect(subject.nearby.isEmpty, "the note was filled before anything read it")
        await subject.refreshNearby()
        #expect(subject.nearby.map(\.tree.id) == [first.id], "the note names no tree, or the wrong ones")
        #expect(
            subject.nearby.allSatisfy { $0.distanceM <= TreeDraft.proximityDedupeRadiusM },
            "the note lists a tree outside its own 10 m"
        )
        #expect(subject.canAdd, "the note disabled the button")

        let id = try #require(await subject.add(), "a tree 4 m from another was not added")
        #expect(id != first.id)
        let profile = try await api.treeProfile(id: id)
        #expect(profile.tree.coordinate.distance(to: closeBy) < 0.5)
        if case let .failed(message) = subject.phase { Issue.record("the add reported: \(message)") }
    }

    /// The note follows the pin: a pin the reader places away from the tree on record clears it,
    /// and the answer for an old position never lands on a new one.
    ///
    /// Red-proof: make the view's trigger, `refreshNearby`, read the fix instead of `coordinate` —
    /// red on "the note did not follow the placed pin".
    @MainActor
    @Test("the note is read again for a placed pin, and clears when the pin leaves the circle")
    func theNoteFollowsThePin() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        _ = try await api.addTree(
            TreeDraft(coordinate: Self.spot, photoLocalPath: try Self.stagedPhoto(), attribution: Self.attribution)
        )

        let closeBy = ProximityDedupeTests.diagonal(from: Self.spot, meters: 4)
        let subject = Self.model(api: api, fix: .located(closeBy, accuracyM: 6))
        await subject.refreshNearby()
        #expect(subject.nearby.count == 1)

        subject.beginPlacingPin()
        subject.confirmPin(VisitPinAdjust.offset(closeBy, northM: 30, eastM: 0))
        await subject.refreshNearby()
        #expect(subject.nearby.isEmpty, "the note did not follow the placed pin")
    }

    /// The owner's words of 2026-11-14, exactly, with the number taken from the radius searched.
    @Test("the note's words are the owner's, and the refusal's sentences are gone")
    func theNoteWords() {
        #expect(VisitAddTreeCopy.nearbyLabel == "ALREADY ON RECORD")
        #expect(
            VisitAddTreeCopy.nearbyBody
                == "Something is already on record within 10 m of here. Add this tree only if it is a different one."
        )
        #expect(VisitAddTreeCopy.nearbyBody.contains("\(Int(TreeDraft.proximityDedupeRadiusM)) m"))
        #expect(!VisitAddTreeCopy.nearbyBody.contains("Nothing was added"))
        #expect(!VisitAddTreeCopy.nearbyBody.contains("open it"))
    }

    @MainActor
    @Test("a tree 12 m away draws no note and adds")
    func twelveMetersAddsThroughTheScreen() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        _ = try await api.addTree(
            TreeDraft(coordinate: Self.spot, photoLocalPath: try Self.stagedPhoto(), attribution: Self.attribution)
        )

        let subject = Self.model(
            api: api,
            fix: .located(ProximityDedupeTests.diagonal(from: Self.spot, meters: 12), accuracyM: 6)
        )
        subject.useLibraryImage(try Self.jpeg())

        await subject.refreshNearby()
        #expect(subject.nearby.isEmpty, "a tree 12 m away was listed under the 10 m note (E35)")
        let id = await subject.add()
        #expect(id != nil, "an honest contribution 12 m away was refused (E35)")
        // Nothing was reported to the reader. The phase stays `.adding` on purpose — see
        // `VisitAddTreeModel.add`.
        if case let .failed(message) = subject.phase { Issue.record("the add reported: \(message)") }
    }

    // MARK: - Show at 10 m, hide past 15 m (the owner's decision of 2026-11-15)

    /// The note comes up at 10 m and a tree it lists stays listed out to 15 m, so a fix drifting
    /// across 10 m does not flip it. Driven with pins placed by hand, which take the same rule.
    ///
    /// Red-proofs: make `listed(_:keeping:)` keep only rows within 10 m — red on "a listed tree at
    /// 12 m left the note". Set `TreeDraft.proximityNoteKeepRadiusM` to 20 — red on "a listed tree
    /// 15.1 m away is still listed".
    @MainActor
    @Test("the note shows at 9.9 m, keeps a listed tree at 12 m, and drops it past 15 m")
    func theNoteHoldsOutToFifteenMeters() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let tree = try await api.addTree(
            TreeDraft(coordinate: Self.spot, photoLocalPath: try Self.stagedPhoto(), attribution: Self.attribution)
        )

        let subject = Self.model(
            api: api, fix: .located(VisitPinAdjust.offset(Self.spot, northM: 9.9, eastM: 0), accuracyM: 6)
        )
        await subject.refreshNearby()
        #expect(subject.nearby.map(\.tree.id) == [tree.id], "a tree 9.9 m away did not bring the note up")

        try await Self.placePin(subject, northOf: Self.spot, meters: 12)
        #expect(subject.nearby.map(\.tree.id) == [tree.id], "a listed tree at 12 m left the note")
        let shown = try #require(subject.nearby.first?.distanceM)
        #expect(abs(shown - 12) < 0.5, "the row shows \(shown) m, not where the tree is now")

        try await Self.placePin(subject, northOf: Self.spot, meters: 15.1)
        #expect(subject.nearby.isEmpty, "a listed tree 15.1 m away is still listed")
    }

    /// A tree first seen between 10 and 15 m does not join the note, even while the note is up for
    /// another tree; it joins once it is within 10 m.
    ///
    /// Red-proof: make `listed(_:keeping:)` keep every row within 15 m — red on "a tree first seen
    /// at 12.1 m joined the note".
    @MainActor
    @Test("a tree first seen at 12 m does not join the note, and joins once it is within 10 m")
    func aNewTreeJoinsOnlyWithinTenMeters() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let near = try await api.addTree(
            TreeDraft(coordinate: Self.spot, photoLocalPath: try Self.stagedPhoto(), attribution: Self.attribution)
        )
        let farther = try await api.addTree(
            TreeDraft(
                coordinate: VisitPinAdjust.offset(Self.spot, northM: 22, eastM: 0),
                photoLocalPath: try Self.stagedPhoto(),
                attribution: Self.attribution
            )
        )

        // 9.9 m from `near` and 12.1 m from `farther`.
        let subject = Self.model(
            api: api, fix: .located(VisitPinAdjust.offset(Self.spot, northM: 9.9, eastM: 0), accuracyM: 6)
        )
        await subject.refreshNearby()
        #expect(subject.nearby.map(\.tree.id) == [near.id], "a tree first seen at 12.1 m joined the note")

        // 12.5 m from `near` (kept) and 9.5 m from `farther` (joins).
        try await Self.placePin(subject, northOf: Self.spot, meters: 12.5)
        #expect(Set(subject.nearby.map(\.tree.id)) == [near.id, farther.id], "the note did not keep `near` at 12.5 m and also take `farther` at 9.5 m")

        // 15.1 m from `near` (dropped) and 6.9 m from `farther`.
        try await Self.placePin(subject, northOf: Self.spot, meters: 15.1)
        #expect(subject.nearby.map(\.tree.id) == [farther.id])

        // 16 m from `farther`: nothing is left, so the note goes.
        try await Self.placePin(subject, northOf: Self.spot, meters: 38)
        #expect(subject.nearby.isEmpty, "the note stayed up with no tree left in it")
    }

    /// The pure rule, at its edges, with no geometry in the way.
    @Test("the listing rule at its edges: 10 m joins, 15 m keeps, past 15 m drops")
    func theListingRuleAtItsEdges() throws {
        let a = Self.row(distanceM: 10)
        let b = Self.row(distanceM: 10.1)
        let c = Self.row(distanceM: 15)
        let d = Self.row(distanceM: 15.1)

        #expect(VisitAddTreeModel.listed([a, b], keeping: []).map(\.id) == [a.id])
        #expect(VisitAddTreeModel.listed([c, d], keeping: [c, d]).map(\.id) == [c.id])
        #expect(VisitAddTreeModel.listed([], keeping: [a, c]).isEmpty, "an empty read kept the old rows")
    }

    // MARK: - The two guards in refreshNearby

    /// A read for an old position that answers after the pin moved must not overwrite the list for
    /// the new position.
    ///
    /// Red-proof: delete `guard coordinate == asked, phase != .adding else { return }` — red on "the
    /// old position's answer replaced the new one".
    @MainActor
    @Test("a slow read for the old pin position does not overwrite the list for the new one")
    func aStaleReadIsDropped() async throws {
        let held = HeldReads()
        let old = Self.spot
        let subject = Self.model(api: HeldAPI(held: held), fix: .located(old, accuracyM: 6))

        let first = Task { await subject.refreshNearby() }
        try await held.waitForReads(1)

        subject.beginPlacingPin()
        subject.confirmPin(VisitPinAdjust.offset(old, northM: 30, eastM: 0))
        let second = Task { await subject.refreshNearby() }
        try await held.waitForReads(2)

        let forNew = Self.row(distanceM: 3)
        held.answer(1, with: [forNew])
        await second.value
        #expect(subject.nearby.map(\.id) == [forNew.id])

        held.answer(0, with: [Self.row(distanceM: 4)])
        await first.value
        #expect(subject.nearby.map(\.id) == [forNew.id], "the old position's answer replaced the new one")
    }

    /// A read that answers after `add()` has begun must not change the note: the screen is leaving.
    ///
    /// Red-proof: delete the same guard — red on "the note changed after the add began".
    @MainActor
    @Test("a read that answers after the add began does not change the note")
    func aReadDuringTheAddIsDropped() async throws {
        let held = HeldReads()
        let subject = Self.model(api: HeldAPI(held: held), fix: .located(Self.spot, accuracyM: 6))
        subject.useLibraryImage(try Self.jpeg())

        let read = Task { await subject.refreshNearby() }
        try await held.waitForReads(1)

        let adding = Task { await subject.add() }
        try await held.waitForAdd()
        #expect(subject.phase == .adding)

        held.answer(0, with: [Self.row(distanceM: 4)])
        await read.value
        #expect(subject.nearby.isEmpty, "the note changed after the add began")

        held.failAdd()
        _ = await adding.value
    }

    /// One failed read must not take down a note that is showing (second review, 2026-11-15).
    ///
    /// Red-proof: turn a thrown read back into `[]` — red on "a failed read took the note down".
    @MainActor
    @Test("a failed read keeps the note that is showing")
    func aFailedReadKeepsTheNote() async throws {
        let held = HeldReads()
        let subject = Self.model(api: HeldAPI(held: held), fix: .located(Self.spot, accuracyM: 6))

        let first = Task { await subject.refreshNearby() }
        try await held.waitForReads(1)
        let shown = Self.row(distanceM: 4)
        held.answer(0, with: [shown])
        await first.value
        #expect(subject.nearby.map(\.id) == [shown.id])

        let second = Task { await subject.refreshNearby() }
        try await held.waitForReads(2)
        held.fail(1)
        await second.value
        #expect(subject.nearby.map(\.id) == [shown.id], "a failed read took the note down")
    }

    /// Two reads at the same position: the older one answering last must not replace the newer
    /// one. This is the read a listed tree's profile closing makes, racing a read from before it
    /// opened.
    ///
    /// Red-proof: drop `read == nearbyReads` from the guard — red on "an older read replaced a newer
    /// one at the same position".
    @MainActor
    @Test("an older read at the same position does not replace a newer one")
    func anOlderReadAtTheSamePositionIsDropped() async throws {
        let held = HeldReads()
        let subject = Self.model(api: HeldAPI(held: held), fix: .located(Self.spot, accuracyM: 6))

        let older = Task { await subject.refreshNearby() }
        try await held.waitForReads(1)
        let newer = Task { await subject.refreshNearby() }
        try await held.waitForReads(2)

        let fromNewer = Self.row(distanceM: 3)
        held.answer(1, with: [fromNewer])
        await newer.value
        #expect(subject.nearby.map(\.id) == [fromNewer.id])

        held.answer(0, with: [Self.row(distanceM: 4)])
        await older.value
        #expect(subject.nearby.map(\.id) == [fromNewer.id], "an older read replaced a newer one at the same position")
    }

    /// A listed tree's profile over the screen: nothing starts the camera while it is up, and
    /// closing it reads the note again, for a tree the reader moved from that profile, then starts
    /// the camera again. A simulator has no capture device, so the camera's start shows as
    /// `.unavailable` and "not started" as `.idle`; a running session stopping is phone-only.
    ///
    /// Red-proofs: drop the guard in `load()` — red on "the camera was started under the profile".
    /// Drop `refreshNearby()` from `closeListedTree()` — red on "the row still says 4 m".
    @MainActor
    @Test("while a listed tree is open over the screen nothing starts the camera, and closing it reads the note again")
    func closingAListedTreeReadsTheNoteAgain() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let tree = try await api.addTree(
            TreeDraft(coordinate: Self.spot, photoLocalPath: try Self.stagedPhoto(), attribution: Self.attribution)
        )
        let subject = Self.model(
            api: api, fix: .located(VisitPinAdjust.offset(Self.spot, northM: 4, eastM: 0), accuracyM: 6)
        )
        await subject.refreshNearby()
        #expect(subject.nearby.map { $0.distanceM.rounded() } == [4])

        subject.openListedTree()
        #expect(subject.isShowingListedTree)
        await subject.load()
        #expect(subject.camera.availability == .idle, "the camera was started under the profile")

        // The reader moves the tree 15 m north from its profile.
        _ = try await api.correctLocation(
            treeID: tree.id,
            to: VisitPinAdjust.offset(Self.spot, northM: 15, eastM: 0),
            placement: .contributorPlaced,
            locationAccuracyM: nil
        )
        await subject.closeListedTree()
        #expect(!subject.isShowingListedTree)
        #expect(subject.nearby.map { $0.distanceM.rounded() } == [11], "the row still says 4 m")
        #expect(subject.camera.availability != .idle, "closing the profile did not start the camera again")
    }

    // MARK: - Fixtures

    /// A row under the note, at a given distance, for the rule tests and the held reads.
    private static func row(distanceM: Double) -> NearbyTree {
        NearbyTree(
            tree: Tree(
                id: UUID(),
                source: .community,
                coordinate: spot,
                status: .alive,
                createdAt: Date(timeIntervalSince1970: 0),
                updatedAt: Date(timeIntervalSince1970: 0)
            ),
            distanceM: distanceM,
            speciesScientificName: nil,
            speciesCommonName: nil,
            tell: nil
        )
    }

    /// Places the pin `meters` north of `origin` and reads the note for it, the way the view does
    /// when the pin's position changes.
    @MainActor
    private static func placePin(
        _ subject: VisitAddTreeModel, northOf origin: Coordinate, meters: Double
    ) async throws {
        subject.beginPlacingPin()
        let pin = VisitPinAdjust.offset(origin, northM: meters, eastM: 0)
        subject.confirmPin(pin)
        try #require(subject.coordinate == pin, "the pin at \(meters) m was not placed")
        await subject.refreshNearby()
    }

    /// Reads and adds that wait until the test answers them. A lock, because the double's methods
    /// are nonisolated and run off the main actor.
    private final class HeldReads: @unchecked Sendable {
        private let lock = NSLock()
        private var reads: [CheckedContinuation<[NearbyTree], Error>] = []
        private var add: CheckedContinuation<Void, Error>?

        func hold(_ continuation: CheckedContinuation<[NearbyTree], Error>) {
            lock.withLock { reads.append(continuation) }
        }

        func holdAdd(_ continuation: CheckedContinuation<Void, Error>) {
            lock.withLock { add = continuation }
        }

        func answer(_ index: Int, with rows: [NearbyTree]) {
            let continuation = lock.withLock { reads[index] }
            continuation.resume(returning: rows)
        }

        func fail(_ index: Int) {
            let continuation = lock.withLock { reads[index] }
            continuation.resume(throwing: APIError.serverError)
        }

        func failAdd() {
            let continuation = lock.withLock { add }
            continuation?.resume(throwing: APIError.forbidden)
        }

        /// Bounded: two seconds, then the test fails instead of hanging.
        func waitForReads(_ count: Int) async throws {
            for _ in 0..<400 {
                if lock.withLock({ reads.count }) >= count { return }
                try await Task.sleep(for: .milliseconds(5))
            }
            Issue.record("only \(lock.withLock { reads.count }) reads arrived, not \(count)")
        }

        func waitForAdd() async throws {
            for _ in 0..<400 {
                if lock.withLock({ add != nil }) { return }
                try await Task.sleep(for: .milliseconds(5))
            }
            Issue.record("the add never reached the API")
        }
    }

    /// `treesNear` and `addTree` wait for `HeldReads`; nothing else is read.
    private struct HeldAPI: CypressAPI {
        let held: HeldReads

        func treesNear(_ c: Coordinate, radiusM: Double, limit: Int) async throws -> [NearbyTree] {
            try await withCheckedThrowingContinuation { held.hold($0) }
        }

        func addTree(_ draft: TreeDraft) async throws -> Tree {
            try await withCheckedThrowingContinuation { held.holdAdd($0) }
            throw APIError.forbidden
        }

        func mapContent(in viewport: MapViewport) async throws -> MapContent { .pins([]) }
        func treeProfile(id: UUID) async throws -> TreeProfile { throw APIError.notFound }
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

    /// A real 1×1 JPEG. Two bytes of a header are not enough: the model decodes the frame with
    /// `UIImage(data:)` before it accepts it, exactly as screen 04 does, and a fixture that skipped
    /// that would not be exercising the path that ships.
    @MainActor
    private static func jpeg() throws -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        let image = renderer.image { context in
            UIColor.darkGray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return try #require(image.jpegData(compressionQuality: 1))
    }
}
