//
//  SharePreviews.swift
//  Cypress — Features/Share
//
//  Previews for screen 10, including the one that matters most: the same tree with photographs on
//  its timeline that this device took and nobody has approved. The card is identical, because a
//  public surface takes the public predicate. See `SharePresentation`'s header.
//

#if DEBUG
import SwiftUI

// MARK: - Doubles

/// Answers the profile read with one tree and refuses everything else. Previews only.
struct SharePreviewAPI: CypressAPI {

    var profile: TreeProfile = SharePreviewFixtures.profile()
    var fails = false

    func treeProfile(id: UUID) async throws -> TreeProfile {
        if fails { throw APIError.notFound }
        return profile
    }

    func mapContent(in viewport: MapViewport) async throws -> MapContent { .pins([]) }
    func treesNear(_ coordinate: Coordinate, radiusM: Double, limit: Int) async throws -> [NearbyTree] { [] }
    func addTree(_ draft: TreeDraft) async throws -> Tree { throw APIError.forbidden }
    func species(id: UUID) async throws -> Species { throw APIError.notFound }
    func searchSpecies(query: String, limit: Int) async throws -> [Species] { [] }
    func sync(_ items: [OutboxItem]) async throws -> [SyncResult] { [] }
    func beginPhotoUpload(_ request: PhotoUploadRequest) async throws -> PhotoUploadTicket {
        throw APIError.forbidden
    }
    func uploadPhoto(at localPath: String, ticket: PhotoUploadTicket) async throws {}
    func outboxStatus() async throws -> [SyncResult] { [] }
    func grove() async throws -> [GroveEntry] { [] }
    func journal(cursor: String?, limit: Int) async throws -> Page<JournalEntry> { Page(items: []) }
    func claimDevice(deviceUUID: UUID, userID: UUID) async throws {}
    func logHazardRedirect(_ event: HazardRedirectEvent) async throws {}
    func savePrivateReminder(_ reminder: PrivateReminder) async throws -> SyncResult.Status {
        throw APIError.forbidden
    }
    func exportLatest(_ format: ExportFormat) async throws -> Data { Data() }
}

enum SharePreviewFixtures {

    static let treeID = UUID(uuidString: "9F3A0000-0000-4000-8000-000000000010")!

    static let tree = Tree(
        id: treeID,
        externalRef: "13284",
        source: .cityImport,
        coordinate: Coordinate(latitude: 37.7601, longitude: -122.5054),
        address: "Great Highway at Judah",
        verificationState: .cityRecord
    )

    static let montereyCypress = try! Species(
        scientificName: "Hesperocyparis macrocarpa",
        commonName: "Monterey Cypress",
        family: "Cupressaceae",
        leafRetention: .evergreen,
        curated: true
    )

    static func photo(month: Int, moderation: ModerationState) -> Photo {
        Photo(
            treeID: treeID,
            shotType: .fullTree,
            moderationState: moderation,
            capturedAt: Calendar.current.date(
                from: DateComponents(year: 2025, month: month, day: 12)
            )!
        )
    }

    static func profile(
        name: String? = "Grandmother Cypress",
        photos: [Photo] = [],
        ownPhotoIDs: Set<UUID> = []
    ) -> TreeProfile {
        TreeProfile(
            tree: tree,
            activeName: name.map { TreeName(treeID: treeID, name: $0, givenBy: nil) },
            species: montereyCypress,
            neighborhoodName: "Sunset/Parkside",
            photos: Series(complete: photos),
            ownPhotoIDs: ownPhotoIDs
        )
    }

    /// Nine months of photographs this device took. Every one is `.pending`, because nothing in the
    /// app can approve anything, so **none of them reaches the card** — the strip stays thin and the
    /// thumbnail stays a gradient.
    static func deviceLocalPhotos() -> (photos: [Photo], ids: Set<UUID>) {
        let photos = [1, 2, 3, 5, 6, 7, 9, 10, 11].map { photo(month: $0, moderation: .pending) }
        return (photos, Set(photos.map(\.id)))
    }

    /// The counterfactual: the same photographs, moderated. This is what the card becomes the day a
    /// moderation service exists, and it is here so the difference is visible rather than argued.
    static func approvedPhotos() -> [Photo] {
        [1, 2, 3, 5, 6, 7, 9, 10, 11].map { photo(month: $0, moderation: .approved) }
    }
}

// MARK: - Previews

/// The state SCREENS.md 10 draws.
#Preview("10 · share") {
    ShareView(treeID: SharePreviewFixtures.treeID, api: SharePreviewAPI())
}

/// **The predicate, made visible.** Nine of this device's own photographs are on the timeline and
/// the card is byte-identical to the one above: a share card is a public surface and takes
/// `isPubliclyVisible`, which no photo in the shipping app satisfies (ERRATA E37, E59).
#Preview("10 · nine pending photos — card unchanged") {
    let local = SharePreviewFixtures.deviceLocalPhotos()
    return ShareView(
        treeID: SharePreviewFixtures.treeID,
        api: SharePreviewAPI(
            profile: SharePreviewFixtures.profile(photos: local.photos, ownPhotoIDs: local.ids)
        )
    )
}

/// The counterfactual: the same nine, approved. The season strip fills for those months. Nothing in
/// the app can produce this state today; it exists so the moderation gate is visibly a gate.
#Preview("10 · if moderation existed") {
    ShareView(
        treeID: SharePreviewFixtures.treeID,
        api: SharePreviewAPI(
            profile: SharePreviewFixtures.profile(photos: SharePreviewFixtures.approvedPhotos())
        )
    )
}

/// A tree with no given name: the card falls back to the species common name, as every other
/// surface in the app does.
#Preview("10 · unnamed tree") {
    ShareView(
        treeID: SharePreviewFixtures.treeID,
        api: SharePreviewAPI(profile: SharePreviewFixtures.profile(name: nil))
    )
}

/// **NOT SPECIFIED.** The read failed, so there is no name and no link to put in front of anybody.
#Preview("10 · read failed") {
    ShareView(treeID: SharePreviewFixtures.treeID, api: SharePreviewAPI(fails: true))
}

/// Dark. SCREENS.md gives 10 no dark row, so this is evidence of what the token layer resolves the
/// sheet to rather than a design. See ERRATA (E61).
#Preview("10 · dark") {
    ShareView(treeID: SharePreviewFixtures.treeID, api: SharePreviewAPI())
        .preferredColorScheme(.dark)
}
#endif
