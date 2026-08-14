import Foundation
import Testing
@testable import Cypress

/// **A vacant site cannot be shown as a tree profile** — whichever entrance was used (ERRATA E113).
///
/// E107 gave the site its own screen and routed the map card to it, and named what it left behind in
/// its own last paragraph: every other entrance — the almanac's rows, the visit flow's open-tree
/// callback, a stale link — still landed a vacant site on `TreeProfileView`, which is screen 14
/// asserting a tree that is not there: an empty photo well captioned `No photos of this tree yet`
/// over `Be the first to photograph this tree`.
///
/// The shape of the fix is the thing these tests are really holding. A redirect at one more call
/// site would pass a test written against that call site and leave the next one broken, which is
/// what happened the first time. So the question is asked once, of the record, in the one place
/// every entrance converges — after the read, before anything is derived — and it is asked as an
/// exhaustive switch, so a sixth `TreeStatus` is a compile error rather than a silent profile.
///
/// The second half of the suite is the case that must *not* redirect, and it is not a caveat: a
/// removed tree keeps its profile, because screen 19 has nothing to press and RULINGS R2 needs the
/// heart to stay reachable on a tree somebody favorited before it was felled.
@MainActor
@Suite("The vacant site never opens the tree profile (E113)")
struct VacantSiteRedirectTests {

    // MARK: - Fixtures

    private static let treeID = UUID(uuidString: "5E000000-0000-4000-8000-0000000004B1")!
    private static let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-0000000004B2")!

    private static func tree(status: TreeStatus) -> Tree {
        Tree(
            id: treeID,
            externalRef: "201-33",
            source: .cityImport,
            coordinate: Coordinate(latitude: 37.7601, longitude: -122.4014),
            address: "666 Rhode Island St",
            siteType: "Sidewalk: Curb side : Cutout",
            status: status,
            verificationState: .cityRecord,
            createdAt: Date(timeIntervalSince1970: 1_784_505_600),
            updatedAt: Date(timeIntervalSince1970: 1_784_505_600)
        )
    }

    /// A *photographed* record, so that if the redirect ever stopped firing the screen would draw
    /// the warm variant — the loudest possible failure, and the one E89 flagged as latent.
    private static func profile(status: TreeStatus) -> TreeProfile {
        TreeProfile(
            tree: tree(status: status),
            visits: Series(complete: [
                Visit(
                    treeID: treeID,
                    attribution: Attribution.anonymous(deviceID: deviceID),
                    capturedAt: Date(timeIntervalSince1970: 1_784_419_200)
                ),
            ])
        )
    }

    private struct Records: CypressAPI {
        var profile: TreeProfile

        func treeProfile(id: UUID) async throws -> TreeProfile {
            guard id == profile.tree.id else { throw APIError.notFound }
            return profile
        }

        func mapContent(in viewport: MapViewport) async throws -> MapContent { .pins([]) }
        func treesNear(_ c: Coordinate, radiusM: Double, limit: Int) async throws -> [NearbyTree] { [] }
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

    private static func model(_ status: TreeStatus) -> TreeProfileModel {
        TreeProfileModel(treeID: treeID, api: Records(profile: profile(status: status)))
    }

    private static func phaseRoute(_ model: TreeProfileModel) -> Route? {
        if case let .elsewhere(route) = model.phase { return route }
        return nil
    }

    // MARK: - 1. The record leaves before it is derived

    @Test("a vacant site never becomes a tree profile")
    func aVacantSiteLeaves() async {
        let model = Self.model(.vacantSite)
        await model.load()

        #expect(Self.phaseRoute(model) == .site(Self.treeID))
        // Not "a profile with the false parts removed" — no profile at all. `presentation` is what
        // the view draws from, and there is nothing for it to draw.
        #expect(model.presentation == nil, "a vacant site was derived as a tree profile")
    }

    @Test("every status that is a tree is still the tree profile")
    func aTreeIsStillATree() async {
        for status in [TreeStatus.alive, .declining, .deadReported] {
            let model = Self.model(status)
            await model.load()
            #expect(model.presentation != nil, "\(status) stopped opening the profile")
            #expect(Self.phaseRoute(model) == nil)
        }
    }

    /// The gate itself, over the whole vocabulary. `TreeStatus` is `CaseIterable`, so this loop
    /// grows on its own the day a status is added — and `TreeProfileDestination`'s switch will not
    /// compile until somebody has answered for it.
    @Test("the destination is decided for every status there is")
    func everyStatusHasAnAnswer() {
        var answers: [TreeStatus: TreeProfileDestination] = [:]
        for status in TreeStatus.allCases {
            answers[status] = TreeProfileDestination(record: Self.tree(status: status))
        }
        #expect(answers[.vacantSite] == .elsewhere(.site(Self.treeID)))
        #expect(answers[.alive] == .profile)
        #expect(answers[.declining] == .profile)
        #expect(answers[.deadReported] == .profile)
        #expect(answers[.removed] == .profile)
        #expect(answers.count == TreeStatus.allCases.count)
    }

    // MARK: - 2. Where the redirect leaves the reader

    @Test("the site replaces the profile on the stack rather than stacking on top of it")
    func theRedirectReplacesInPlace() {
        let router = AppRouter()
        // The almanac's season row — an entrance that is not the map, which is the whole of E113.
        router.push(.almanac)
        router.push(.treeProfile(Self.treeID))

        router.replace(.treeProfile(Self.treeID), with: .site(Self.treeID))

        #expect(router.path == [.almanac, .site(Self.treeID)])
        // Back goes to the entrance, not to the profile that should not have opened.
        router.pop()
        #expect(router.path == [.almanac])
    }

    @Test("a profile that is no longer on the stack still reaches the site")
    func theRedirectSurvivesAMovedStack() {
        let router = AppRouter()
        router.push(.species(Self.treeID))

        // The load returned after the reader had already gone somewhere else. Replacing "the top"
        // would have thrown away screen 07; this pushes instead, which is the same destination by a
        // longer road rather than a silent no-op.
        router.replace(.treeProfile(Self.treeID), with: .site(Self.treeID))
        #expect(router.path == [.species(Self.treeID), .site(Self.treeID)])
    }

    // MARK: - 3. The case that must not redirect

    /// A removed tree keeps the profile **on purpose**, and this test is the reason written down.
    ///
    /// Screen 19 is drawn with deliberately nothing to press. So a redirect from the profile to the
    /// memorial would take the last surface in the app that can take a favorite off a felled tree —
    /// which is E89's deciding argument for not gating the heart in the first place, arriving by a
    /// different road. R2 restates it: the gate that refuses the heart also refuses removing it.
    @Test("a removed tree keeps its profile, and keeps the heart on it")
    func aMemorialKeepsItsProfile() async throws {
        let model = Self.model(.removed)
        await model.load()

        #expect(Self.phaseRoute(model) == nil, "the memorial redirect took away the only way to un-favorite")
        let presentation = try #require(model.presentation)
        #expect(presentation.quadActions.contains(.favorite))
        // And it offers no write of any kind (E95, E112).
        #expect(!presentation.acceptsContributions)
        #expect(!presentation.quadActions.contains(.care))
        #expect(!presentation.quadActions.contains(.report))
    }

    /// A site cannot be favorited from anywhere, before or after this change, and that is worth
    /// pinning so the redirect is not read as having taken something away.
    ///
    /// The quad row is drawn only on the warm variant and a vacant site is always cold — no photos,
    /// no visits, because nothing can contribute either to it — so the heart was never on a site's
    /// screen. E107 declined to put one on the site screen for its own reason: the only control it
    /// could hang on is C7, which has no selected appearance, which is the defect R2 just closed on
    /// C8.
    @Test("no surface offered a favorite on a vacant site, so the redirect takes nothing away")
    func aSiteNeverHadTheHeart() {
        let site = TreeProfilePresentation(
            profile: TreeProfile(tree: Self.tree(status: .vacantSite))
        )
        #expect(site.isCold, "a vacant site drew the warm variant, which is where the quad row is")
        #expect(!site.acceptsContributions)
    }
}
