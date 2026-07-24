//
//  AlmanacPreviews.swift
//  Cypress — Features/Almanac
//
//  Previews for screen 12, including the states SCREENS.md does not draw. Two of those matter more
//  here than the drawn one:
//
//  - **the fresh install**, where no seeded tree has a visit or a photo, so the bloom row has
//    nothing behind it and the coverage list is every young tree in the neighbourhood;
//  - **no location fix**, where there is no neighbourhood and therefore no almanac at all.
//
//  Both are what a real device shows, and neither is in the mock set. They are previewed rather
//  than described so that what was chosen for them is visible (ARCHITECTURE §5.6, ERRATA).
//

#if DEBUG
import SwiftUI

// MARK: - Double

/// Hands back a fixed almanac and refuses everything else. Previews only.
struct AlmanacPreviewAPI: CypressAPI {
    var payload: Almanac = .empty

    func almanac(near coordinate: Coordinate?) async throws -> Almanac { payload }

    func mapContent(in viewport: MapViewport) async throws -> MapContent { .pins([]) }
    func treesNear(_ coordinate: Coordinate, radiusM: Double, limit: Int) async throws -> [NearbyTree] { [] }
    func treeProfile(id: UUID) async throws -> TreeProfile { throw APIError.notFound }
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

// MARK: - Fixtures

/// The numbers here are the seed's own for `Sunset/Parkside`, not the mock's, wherever the two
/// disagree — the point of a preview is to show what the screen will actually say.
///
/// | | SCREENS.md 12 | the seed |
/// |---|---|---|
/// | pill | `Outer Sunset` | `Sunset/Parkside` — SF's polygon set has no Outer Sunset (E47) |
/// | elder | `since 1898` | `since 1956`, the oldest recorded planting in the neighbourhood |
/// | species | `64 species` | `215 species` |
/// | shares | 18 / 11 / 9 / 62 | 14 / 8 / 7 / 71 — SF's street-tree tail is very long |
/// | coverage | `9 young trees` | `17`, the young trees the city planted here since 2024 |
private enum AlmanacFixtures {

    /// A summer afternoon, so `AlmanacWindow.currentSpring` has a spring behind it to look at.
    static let now = Date(timeIntervalSince1970: 1_784_505_600) // 2026-07-20, 00:00 UTC

    private static func id(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "12000000-0000-4000-8000-%012d", index))!
    }

    static let bloom = BloomFirst(
        treeID: id(1),
        speciesCommonName: "Red flowering gum",
        address: "1240 44th Ave",
        firstSeenAt: Date(timeIntervalSince1970: 1_768_953_600), // 2026-01-21
        observerCount: 3
    )

    /// The same sighting with one observer. A8's floor drops the headcount clause and keeps the row.
    static let bloomAlone = BloomFirst(
        treeID: id(1),
        speciesCommonName: "Red flowering gum",
        address: "1240 44th Ave",
        firstSeenAt: Date(timeIntervalSince1970: 1_768_953_600),
        observerCount: 1
    )

    static let elder = ElderTree(
        treeID: id(2),
        activeName: nil,
        speciesCommonName: "Blackwood Acacia",
        address: "1783 41st Ave",
        plantedYear: 1956
    )

    static let composition = NeighborhoodComposition(
        distinctSpeciesCount: 215,
        treeCount: 11_026,
        leading: [
            SpeciesShare(speciesID: id(10), name: "New Zealand Xmas Tree", treeCount: 1_561),
            SpeciesShare(speciesID: id(11), name: "Hybrid Strawberry Tree", treeCount: 827),
            SpeciesShare(speciesID: id(12), name: "Monterey Cypress", treeCount: 816),
            SpeciesShare(speciesID: id(13), name: "Monterey Pine", treeCount: 698)
        ]
    )

    static func coverage(_ count: Int, farthestM: Double) -> CoverageGap {
        CoverageGap(
            trees: Series(
                complete: (0..<count).map {
                    CoverageTree(
                        id: id(100 + $0),
                        distanceM: count <= 1 ? farthestM : Double($0) / Double(count - 1) * farthestM
                    )
                }
            )
        )
    }

    /// Every block present — the state SCREENS.md draws, with the seed's numbers in it.
    static let full = Almanac(
        neighborhood: AlmanacNeighborhood(
            name: "Sunset/Parkside",
            firstBloom: bloom,
            elder: elder,
            newestNeighbors: RecentPlanting(treeCount: 23, leadingSpecies: ["Ginkgo", "NZ tea tree"]),
            composition: composition,
            coverage: coverage(9, farthestM: 900),
            vacantSites: VacantSites(count: 1_474, nearestID: UUID())
        )
    )

    /// **The fresh install.** No seeded tree carries a visit or a photo, so: no bloom (A9's floor of
    /// one sighting is not met), and nothing was planted in this neighbourhood this spring. The
    /// elder and the mix are city data and draw in full. The coverage card counts every young tree
    /// here, because nobody has visited any of them — and they are spread across the whole
    /// neighbourhood, so §4's walking sentence is withheld.
    static let freshInstall = Almanac(
        neighborhood: AlmanacNeighborhood(
            name: "Sunset/Parkside",
            firstBloom: nil,
            elder: elder,
            newestNeighbors: nil,
            composition: composition,
            coverage: coverage(17, farthestM: 4_100),
            // The block draws on a fresh install: it counts city records, not contributions (R10).
            vacantSites: VacantSites(count: 1_474, nearestID: UUID())
        )
    )

    /// One sighting rather than three: the row draws, the headcount does not (A8).
    static let singleObserver = Almanac(
        neighborhood: AlmanacNeighborhood(
            name: "Sunset/Parkside",
            firstBloom: bloomAlone,
            elder: elder,
            newestNeighbors: nil,
            composition: composition,
            coverage: coverage(17, farthestM: 4_100)
        )
    )

    /// No location fix, so no area. Header, footnote, nothing else.
    static let noArea = Almanac.empty
}

// MARK: - Previews

/// The drawn state: three season rows, the composition card, the amber coverage card.
#Preview("12 · almanac") {
    NavigationStack {
        AlmanacView(
            api: AlmanacPreviewAPI(payload: AlmanacFixtures.full),
            coordinate: Coordinate(latitude: 37.7533, longitude: -122.4934),
            now: { AlmanacFixtures.now },
            onBack: {},
            onOpenTree: { _ in },
            onWalk: { _ in }
        )
    }
}

/// **NOT SPECIFIED**, and the state every new device is in. Two of the five blocks are gone because
/// nothing has been contributed yet, and neither leaves a zero behind.
#Preview("12 · fresh install") {
    NavigationStack {
        AlmanacView(
            api: AlmanacPreviewAPI(payload: AlmanacFixtures.freshInstall),
            coordinate: Coordinate(latitude: 37.7533, longitude: -122.4934),
            now: { AlmanacFixtures.now },
            onBack: {},
            onWalk: { _ in }
        )
    }
}

/// A8's floor, visible: one person saw the bloom, so the sighting is reported and the headcount is
/// not.
#Preview("12 · one observer (A8)") {
    NavigationStack {
        AlmanacView(
            api: AlmanacPreviewAPI(payload: AlmanacFixtures.singleObserver),
            coordinate: Coordinate(latitude: 37.7533, longitude: -122.4934),
            now: { AlmanacFixtures.now },
            onBack: {},
            onWalk: { _ in }
        )
    }
}

/// No fix, no area, no almanac. "We could not tell where you are" is not the same fact as "nothing
/// is happening here", and this is what the first of the two looks like.
#Preview("12 · no location") {
    NavigationStack {
        AlmanacView(
            api: AlmanacPreviewAPI(payload: AlmanacFixtures.noArea),
            coordinate: nil,
            now: { AlmanacFixtures.now },
            onBack: {}
        )
    }
}

/// Dark. 12 has no specified dark screen (D1–D3 and 04 are the only ones, ERRATA E8), so this
/// preview is evidence of what the token layer resolves it to rather than a design.
#Preview("12 · dark") {
    NavigationStack {
        AlmanacView(
            api: AlmanacPreviewAPI(payload: AlmanacFixtures.full),
            coordinate: Coordinate(latitude: 37.7533, longitude: -122.4934),
            now: { AlmanacFixtures.now },
            onBack: {},
            onWalk: { _ in }
        )
    }
    .preferredColorScheme(.dark)
}
#endif
