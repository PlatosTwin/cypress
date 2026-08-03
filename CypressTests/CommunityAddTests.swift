import Foundation
import Testing
import UIKit
@testable import Cypress

/// The community add, from the screen that now performs it (ERRATA E127).
///
/// `ProximityDedupeTests` already drives `LocalAPI.addTree` directly and proves the 10 m rule and its
/// diagonal. This suite is about the half that did not exist: the *caller*. `addTree` shipped
/// complete, with the dedupe in it, and nothing in the app ever called it — screen 02's "None of
/// these? Add this tree" was drawn at full opacity and wired to dismiss the flow.
///
/// So the assertions here are all of the form "the screen and the boundary agree": the CTA is refused
/// for exactly the reasons `addTree` would throw, and the dedupe that `addTree` performs is the one
/// the screen reports. Nothing here re-implements a rule in order to test it — in particular the
/// screen never pre-checks the 10 m circle, because a client-side copy of that rule is a copy that
/// can disagree with the refusal.
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

    // MARK: - BUILD-PLAN §9 M2 · the duplicate-proximity warning

    /// **The one the brief asked to have confirmed: the 10 m dedupe runs on the path that ships.**
    ///
    /// Driven through `VisitAddTreeModel`, not through `addTree`, because that is the difference
    /// between "the rule exists" and "the rule is in front of the person adding a tree". The
    /// candidates the screen shows are the API's own, so the warning cannot disagree with the refusal.
    @MainActor
    @Test("a second tree 4 m away is refused, and the screen shows the tree that refused it")
    func theDedupeRunsOnTheShippingPath() async throws {
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

        let id = await subject.add()
        #expect(id == nil, "a tree was added 4 m from an existing one")

        guard case let .duplicate(candidates) = subject.phase else {
            Issue.record("the screen is in \(subject.phase) rather than showing the duplicate warning")
            return
        }
        #expect(candidates.contains { $0.tree.id == first.id }, "the warning names no tree")
        #expect(
            candidates.allSatisfy { $0.distanceM <= TreeDraft.proximityDedupeRadiusM },
            "the warning lists a tree the rule did not refuse for"
        )
        // The sentence states the rule it just applied, and takes the number from the rule.
        #expect(VisitAddTreeCopy.duplicateBody.contains("\(Int(TreeDraft.proximityDedupeRadiusM)) m"))
    }

    @MainActor
    @Test("a tree 12 m away is not a duplicate on this path either")
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

        let id = await subject.add()
        #expect(id != nil, "an honest contribution 12 m away was refused (E35)")
        // Nothing was reported to the reader: no duplicate warning and no failure. The phase stays
        // `.adding` on purpose — see `VisitAddTreeModel.add`.
        if case .duplicate = subject.phase { Issue.record("12 m was reported as a duplicate") }
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
