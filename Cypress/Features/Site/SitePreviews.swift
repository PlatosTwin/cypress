//
//  SitePreviews.swift
//  Cypress — Features/Site
//
//  Previews for the vacant planting site (ERRATA E107).
//
//  Unlike screen 19, this one is reachable from real data on every device: 12,518 rows of the
//  shipped seed are vacant sites, against zero removed trees. The fixture below is one of them —
//  the same record `TreeProfilePreviews` uses for the degraded profile this screen replaces — so
//  what these previews draw is what the app draws.
//

#if DEBUG
import SwiftUI

// MARK: - Double

/// Hands back one profile and one nearby list, and refuses everything else. Previews only.
struct SitePreviewAPI: CypressAPI {
    var profile: TreeProfile
    var nearby: [NearbyTree] = []

    func treeProfile(id: UUID) async throws -> TreeProfile { profile }
    func treesNear(_ coordinate: Coordinate, radiusM: Double, limit: Int) async throws -> [NearbyTree] {
        nearby
    }

    func mapContent(in viewport: MapViewport) async throws -> MapContent { .pins([]) }
    func addTree(_ draft: TreeDraft) async throws -> Tree { throw APIError.forbidden }
    func species(id: UUID) async throws -> Species { throw APIError.notFound }
    func searchSpecies(query: String, limit: Int) async throws -> [Species] { [] }
    func sync(_ items: [OutboxItem]) async throws -> [SyncResult] { [] }
    func beginPhotoUpload(_ request: PhotoUploadRequest) async throws -> PhotoUploadTicket {
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

// MARK: - Fixtures

enum SiteFixtures {

    static func id(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "5E000000-0000-4000-8000-%012d", index))!
    }

    static let siteID = id(1)

    /// A vacant site as the seed holds one: an address, a `qSiteInfo` string, a city reference, and
    /// no species, no planted year and no DBH bucket.
    static let site = Tree(
        id: siteID,
        externalRef: "201-33",
        source: .cityImport,
        coordinate: Coordinate(latitude: 37.7601, longitude: -122.4014),
        address: "666 Rhode Island St",
        siteType: "Sidewalk: Curb side : Cutout",
        status: .vacantSite,
        verificationState: .cityRecord
    )

    static var profile: TreeProfile {
        TreeProfile(tree: site, neighborhoodName: "Potrero Hill")
    }

    /// A site the city listed with no address and no site vocabulary — the sparse end of the seed,
    /// where the screen is the header, one sentence and the city's reference number.
    static var bare: TreeProfile {
        TreeProfile(
            tree: Tree(
                id: siteID,
                source: .cityImport,
                coordinate: site.coordinate,
                status: .vacantSite,
                verificationState: .cityRecord
            )
        )
    }

    static let neighborSpecies = try! Species(
        id: id(2),
        scientificName: "Platanus × acerifolia",
        commonName: "London Plane",
        family: "Platanaceae",
        leafRetention: .deciduous
    )

    /// The nearest standing tree, 24 m away, with a vacant site nearer than it — which is the case
    /// the model's filter exists for, since 6.4% of the inventory is a site and sites cluster.
    static var nearby: [NearbyTree] {
        [
            NearbyTree(
                tree: Tree(
                    id: id(10),
                    source: .cityImport,
                    coordinate: Coordinate(latitude: 37.7602, longitude: -122.4014),
                    status: .vacantSite
                ),
                distanceM: 11,
                speciesScientificName: nil,
                speciesCommonName: nil,
                tell: nil
            ),
            NearbyTree(
                tree: Tree(
                    id: id(11),
                    source: .cityImport,
                    coordinate: Coordinate(latitude: 37.7603, longitude: -122.4014),
                    status: .alive
                ),
                distanceM: 24,
                speciesScientificName: neighborSpecies.scientificName,
                speciesCommonName: neighborSpecies.commonName,
                tell: nil
            )
        ]
    }
}

// MARK: - Previews

/// The screen as the app draws it: the address, the sentence, the city's three facts, and the
/// nearest tree that is actually standing.
#Preview("site · a vacant planting site") {
    SiteScreen(
        presentation: SitePresentation(
            profile: SiteFixtures.profile,
            nearest: SiteFixtures.nearby.last
        ),
        onBack: {},
        onOpenTree: { _ in }
    )
}

/// Nothing standing within 150 m. The row is absent rather than reworded, which is the same answer
/// every other surface gives to a fact it does not hold.
#Preview("site · nothing standing nearby") {
    SiteScreen(presentation: SitePresentation(profile: SiteFixtures.profile), onBack: {})
}

/// The sparse end of the seed: no address, so the H1 falls back to the noun and the italic line
/// carries provenance alone.
#Preview("site · no address, no site vocabulary") {
    SiteScreen(presentation: SitePresentation(profile: SiteFixtures.bare), onBack: {})
}

/// The whole feature against a double, so both reads and the `vacant_site` gate run rather than
/// being staged.
#Preview("site · live") {
    SiteView(
        treeID: SiteFixtures.siteID,
        api: SitePreviewAPI(profile: SiteFixtures.profile, nearby: SiteFixtures.nearby),
        onBack: {},
        onOpenTree: { _ in }
    )
}

/// The gate itself: the same screen opened on a record with a tree standing on it.
#Preview("site · there is a tree here") {
    SiteView(
        treeID: SiteFixtures.siteID,
        api: SitePreviewAPI(
            profile: TreeProfile(
                tree: Tree(
                    id: SiteFixtures.siteID,
                    source: .cityImport,
                    coordinate: SiteFixtures.site.coordinate,
                    status: .alive
                )
            )
        ),
        onBack: {}
    )
}

/// Dark. Nothing here has a documented dark row (ERRATA E8), so this is evidence of what the token
/// layer resolves the dashed callout and the C10 tile to rather than a design.
#Preview("site · dark") {
    SiteScreen(
        presentation: SitePresentation(
            profile: SiteFixtures.profile,
            nearest: SiteFixtures.nearby.last
        ),
        onBack: {},
        onOpenTree: { _ in }
    )
    .preferredColorScheme(.dark)
}
#endif
