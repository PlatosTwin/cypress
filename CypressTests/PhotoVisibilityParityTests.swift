//
//  PhotoVisibilityParityTests.swift
//  CypressTests
//
//  ERRATA E215 — the hero pill (screen 03/14) and the photo browser (screen 20) filtered the same
//  `TreeProfile.photos` series by two different rules. They agreed only because `LocalAPI` fills
//  `ownPhotoIDs` with every row it returns, since nothing syncs anybody else's photographs down yet.
//  The moment a read returns a row this installation did not write, `TreePhotosModel.load()`'s old
//  filter — `isVisibleToItsContributor` alone — showed it, unmoderated, on a stranger's own screen,
//  while the hero correctly kept it off (`TreeProfile.isVisibleOnDevice`, gated on `isPubliclyVisible`
//  for a photo that is not this device's own).
//
//  The repair moved the one predicate onto `TreeProfile` (`isVisibleOnDevice` / `visiblePhotos`, in
//  `Cypress/Data/API/CypressAPI.swift`) and made both features read it. This suite pins two things:
//
//  1. **the two surfaces agree**, over a payload that mixes own and not-own, pending and approved,
//     rows — a comparison that would have failed on the pre-fix `TreePhotosModel`;
//  2. **the specific defect named in E215** — a stranger's unmoderated (`.pending`) photograph must
//     not reach the browser, even though it is visible to *its own* contributor.
//

import Foundation
import Testing
@testable import Cypress

@MainActor
@Suite("Photo visibility parity — hero and browser, one rule (ERRATA E215)")
struct PhotoVisibilityParityTests {

    private static let treeID = UUID(uuidString: "E2150000-0000-4000-8000-000000000001")!
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private static let tree = Tree(
        id: treeID,
        source: .community,
        coordinate: Coordinate(latitude: 37.77, longitude: -122.44),
        status: .alive
    )

    /// One tree, three photographs that only disagree once moderation and ownership stop coinciding
    /// — which is exactly the day E215 says the two rules can finally answer differently:
    ///
    /// - `ownPending`: this device's own, not yet moderated. Visible on this device either way.
    /// - `strangersPending`: somebody else's, not yet moderated. The row E215 is about — visible to
    ///   *its* contributor, and to nobody else's screen.
    /// - `strangersApproved`: somebody else's, and moderation has actually cleared it. Visible
    ///   everywhere, own screen included.
    private static let ownPending = Photo(
        id: UUID(uuidString: "E2150000-0000-4000-8000-0000000000A1")!,
        treeID: treeID, shotType: .fullTree, moderationState: .pending, capturedAt: now
    )
    private static let strangersPending = Photo(
        id: UUID(uuidString: "E2150000-0000-4000-8000-0000000000A2")!,
        treeID: treeID, shotType: .trunk, moderationState: .pending, capturedAt: now
    )
    private static let strangersApproved = Photo(
        id: UUID(uuidString: "E2150000-0000-4000-8000-0000000000A3")!,
        treeID: treeID, shotType: .leaf, moderationState: .approved, capturedAt: now
    )

    /// A profile only a sync could produce today (BUILD-PLAN has no such read yet) — `ownPhotoIDs`
    /// names one of the three rows, the other two are somebody else's. `LocalAPI` can never build
    /// this payload, which is exactly why the defect was latent rather than live (ERRATA E215).
    private static var profile: TreeProfile {
        TreeProfile(
            tree: tree,
            photos: Series(complete: [ownPending, strangersPending, strangersApproved]),
            ownPhotoIDs: [ownPending.id]
        )
    }

    /// Answers `treeProfile(id:)` with the fixed payload above and throws on everything else this
    /// suite does not exercise — the same shape as `FailedReadTests.FailsOnce`.
    ///
    /// Holds its own copy of the payload rather than reaching back into the (`@MainActor`) suite for
    /// `profile`: the protocol's methods are `nonisolated`, and a stub that read a main-actor static
    /// from a nonisolated context would not compile.
    private struct StubAPI: CypressAPI {
        let profile: TreeProfile

        func mapContent(in viewport: MapViewport) async throws -> MapContent { .pins([]) }
        func treesNear(_ c: Coordinate, radiusM: Double, limit: Int) async throws -> [NearbyTree] { [] }
        func treeProfile(id: UUID) async throws -> TreeProfile { profile }
        func addTree(_ draft: TreeDraft) async throws -> Tree { throw APIError.forbidden }
        func species(id: UUID) async throws -> Species { throw APIError.notFound }
        func searchSpecies(query: String, limit: Int) async throws -> [Species] { [] }
        func almanac(near coordinate: Coordinate?) async throws -> Almanac { .empty }
        func sync(_ items: [OutboxItem]) async throws -> [SyncResult] { [] }
        func beginPhotoUpload(_ r: PhotoUploadRequest) async throws -> PhotoUploadTicket {
            throw APIError.forbidden
        }
        func uploadPhoto(at localPath: String, ticket: PhotoUploadTicket) async throws {}
        func grove() async throws -> [GroveEntry] { [] }
        func groveSpecies() async throws -> GroveSpecies { .empty }
        func journal(cursor: String?, limit: Int) async throws -> Page<JournalEntry> { Page(items: []) }
        func claimDevice(deviceUUID: UUID, userID: UUID) async throws {}
        func deleteAccount(_ choice: AccountDeletionChoice) async throws -> AccountDeletion.Outcome {
            throw APIError.unauthorized
        }
        func logHazardRedirect(_ event: HazardRedirectEvent) async throws {}
        func exportLatest(_ format: ExportFormat) async throws -> Data { Data() }
    }

    // MARK: - The two surfaces, compared

    /// The assertion E215 asks for: whatever the hero (`TreeProfilePresentation.visiblePhotos`)
    /// admits, the browser (`TreePhotosModel.load()`) admits, and nothing else — over one payload,
    /// read once, by both.
    @Test("the hero and the browser agree on exactly the same set of photographs")
    func heroAndBrowserAgree() async {
        let hero = TreeProfilePresentation(profile: Self.profile, now: Self.now)
        let model = TreePhotosModel(treeID: Self.treeID, api: StubAPI(profile: Self.profile))
        await model.load()

        let heroIDs = Set(hero.visiblePhotos.items.map(\.id))
        let browserIDs = Set(model.photos.map(\.id))

        #expect(!heroIDs.isEmpty, "fixture: the hero saw nothing, so agreement would be vacuous")
        #expect(
            browserIDs == heroIDs,
            "screen 20 (\(browserIDs)) and the hero (\(heroIDs)) disagreed on the tree's own photo set"
        )
    }

    // MARK: - The named defect

    @Test("this device's own pending photo reaches the browser")
    func ownPendingReachesTheBrowser() async {
        let model = TreePhotosModel(treeID: Self.treeID, api: StubAPI(profile: Self.profile))
        await model.load()
        #expect(model.photos.map(\.id).contains(Self.ownPending.id))
    }

    @Test("a stranger's approved photo reaches the browser")
    func strangersApprovedReachesTheBrowser() async {
        let model = TreePhotosModel(treeID: Self.treeID, api: StubAPI(profile: Self.profile))
        await model.load()
        #expect(model.photos.map(\.id).contains(Self.strangersApproved.id))
    }

    /// The exact sentence E215 is filed about: "the day anything syncs … the browser shows a
    /// stranger's unmoderated photograph." This is that day, simulated, and the row must not be here.
    @Test("a stranger's unmoderated photo does not reach the browser, even though it reaches its own contributor's device")
    func strangersPendingPhotoStaysOffTheBrowser() async {
        // It really is visible somewhere — to the row's own contributor, elsewhere on this same
        // payload — so this is a claim about *this* screen, not a claim that the row is dead weight.
        #expect(
            Self.strangersPending.isVisibleToItsContributor,
            "fixture: the row would not test anything if its own contributor could not see it either"
        )
        #expect(
            !Self.strangersPending.isPubliclyVisible,
            "fixture: the row must still be unmoderated, or this is not the case E215 names"
        )

        let model = TreePhotosModel(treeID: Self.treeID, api: StubAPI(profile: Self.profile))
        await model.load()

        #expect(
            !model.photos.map(\.id).contains(Self.strangersPending.id),
            "screen 20 showed a stranger's unmoderated photograph — the exact failure ERRATA E215 names"
        )
    }
}
