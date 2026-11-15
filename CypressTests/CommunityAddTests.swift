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

    // MARK: - Fixtures

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
