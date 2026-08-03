//
//  AlmanacPreviews.swift
//  Cypress — Features/Almanac
//
//  Previews for screen 12, including the states SCREENS.md does not draw. Two of those matter more
//  here than the drawn one:
//
//  - **the fresh install**, where no seeded tree has a visit or a photo, so the bloom row has
//    nothing behind it and the coverage list is every young tree in the neighborhood;
//  - **no location fix**, where there is no neighborhood and therefore no almanac at all.
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
    /// Makes the one read fail, which is the only way to see screen 12's failure arm without a
    /// broken device (ERRATA E126).
    var fails = false

    func almanac(near coordinate: Coordinate?) async throws -> Almanac {
        if fails { throw APIError.serverError }
        return payload
    }

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
    func grove() async throws -> [GroveEntry] { [] }
    func journal(cursor: String?, limit: Int) async throws -> Page<JournalEntry> { Page(items: []) }
    func claimDevice(deviceUUID: UUID, userID: UUID) async throws {}
    func logHazardRedirect(_ event: HazardRedirectEvent) async throws {}
    func exportLatest(_ format: ExportFormat) async throws -> Data { Data() }
}

// MARK: - Fixtures

/// The numbers here are the seed's own for `Sunset/Parkside`, not the mock's, wherever the two
/// disagree — the point of a preview is to show what the screen will actually say.
///
/// | | SCREENS.md 12 | the seed |
/// |---|---|---|
/// | pill | `Outer Sunset` | `Sunset/Parkside` — SF's polygon set has no Outer Sunset (E47) |
/// | elder | `since 1898` | `since 1956`, the oldest recorded planting in the neighborhood |
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

    /// A fix inside Sunset/Parkside, so the previewed groups sit where the previewed almanac says
    /// they are.
    static let here = Coordinate(latitude: 37.7530, longitude: -122.4850)

    /// A city-inventory pin `index` records along a street from `here` (ERRATA E129).
    ///
    /// `.cityImport` / `.cityRecord` because that is what every row of the shipped seed is — measured,
    /// not assumed: `PinSetDestinationTests` asserts it over all 195,309 of them.
    static func pin(_ index: Int, status: TreeStatus = .alive) -> TreePin {
        TreePin(
            id: id(100 + index),
            coordinate: Coordinate(
                latitude: here.latitude + Double(index) * 0.000_35,
                longitude: here.longitude + Double(index) * 0.000_20
            ),
            status: status,
            source: .cityImport,
            verificationState: .cityRecord,
            speciesID: nil
        )
    }

    static func coverage(_ count: Int, farthestM: Double) -> CoverageGap {
        CoverageGap(
            trees: Series(
                complete: (0..<count).map {
                    CoverageTree(
                        pin: pin($0),
                        distanceM: count <= 1 ? farthestM : Double($0) / Double(count - 1) * farthestM
                    )
                }
            )
        )
    }

    /// The block as a real device draws it: 1,474 basins in the neighborhood, the nearest 20 of them
    /// carried to the map (ERRATA E129, E38).
    static func vacantSites(count: Int = 1_474) -> VacantSites {
        VacantSites(
            count: count,
            nearest: (0..<min(count, AlmanacLimits.vacantSiteRowLimit)).map {
                pin(200 + $0, status: .vacantSite)
            }
        )
    }

    /// Every block present — the state SCREENS.md draws, with the seed's numbers in it.
    static let full = Almanac(
        neighborhood: AlmanacNeighborhood(
            area: .named("Sunset/Parkside"),
            firstBloom: bloom,
            elder: elder,
            newestNeighbors: RecentPlanting(
                treeCount: 23,
                leadingSpecies: ["Ginkgo", "NZ tea tree"],
                // The pins the row hands its map (ERRATA E182). Fewer than the count, so the
                // preview also exercises `PinSet.isComplete` being false and the destination
                // saying which page it is holding.
                nearest: (0..<12).map { pin(400 + $0) }
            ),
            composition: composition,
            coverage: coverage(9, farthestM: 900),
            vacantSites: vacantSites()
        )
    )

    /// **The fresh install.** No seeded tree carries a visit or a photo, so: no bloom (A9's floor of
    /// one sighting is not met), and nothing was planted in this neighborhood this spring. The
    /// elder and the mix are city data and draw in full. The coverage card counts every young tree
    /// here, because nobody has visited any of them — and they are spread across the whole
    /// neighborhood, so §4's walking sentence is withheld.
    static let freshInstall = Almanac(
        neighborhood: AlmanacNeighborhood(
            area: .named("Sunset/Parkside"),
            firstBloom: nil,
            elder: elder,
            newestNeighbors: nil,
            composition: composition,
            coverage: coverage(17, farthestM: 4_100),
            // The block draws on a fresh install: it counts city records, not contributions (R10).
            vacantSites: vacantSites()
        )
    )

    /// One sighting rather than three: the row draws, the headcount does not (A8).
    static let singleObserver = Almanac(
        neighborhood: AlmanacNeighborhood(
            area: .named("Sunset/Parkside"),
            firstBloom: bloomAlone,
            elder: elder,
            newestNeighbors: nil,
            composition: composition,
            coverage: coverage(17, farthestM: 4_100)
        )
    )

    /// No location fix, so no area. Header, footnote, nothing else.
    static let noArea = Almanac.empty

    /// **The fallback area** (RULINGS R29): a reader in a city the record holds trees for and
    /// boundaries for. The pill is a distance, and the sentence under the header says so.
    static let radiusArea = Almanac(
        neighborhood: AlmanacNeighborhood(
            area: .radius(meters: AlmanacLimits.fallbackRadiusM),
            firstBloom: nil,
            elder: elder,
            newestNeighbors: RecentPlanting(
                treeCount: 5,
                leadingSpecies: ["Ornamental Pear"],
                nearest: (0..<5).map { pin(500 + $0) }
            ),
            composition: composition,
            coverage: coverage(4, farthestM: 700),
            vacantSites: vacantSites(count: 1_000)
        )
    )
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
            onShowGroup: { _ in }
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
            onShowGroup: { _ in }
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
            onShowGroup: { _ in }
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

/// The read that failed. To be looked at beside `12 · no location` above: that one is the screen
/// saying it does not know where you are, this one is the screen saying it could not ask at all, and
/// until E126 both drew a header and a footnote with nothing in between.
#Preview("12 · read failed") {
    NavigationStack {
        AlmanacView(
            api: AlmanacPreviewAPI(fails: true),
            coordinate: Coordinate(latitude: 37.7533, longitude: -122.4934),
            now: { AlmanacFixtures.now },
            onBack: {}
        )
    }
}

/// **The fallback area** (RULINGS R29). Beside `12 · almanac` above: the same five blocks, and a
/// pill that is a distance rather than a place, with the sentence that keeps the two from being
/// mistaken for each other.
#Preview("12 · a distance, not a place") {
    NavigationStack {
        AlmanacView(
            api: AlmanacPreviewAPI(payload: AlmanacFixtures.radiusArea),
            coordinate: Coordinate(latitude: 37.3352, longitude: -121.8895),
            now: { AlmanacFixtures.now },
            onBack: {},
            onOpenTree: { _ in },
            onShowGroup: { _ in }
        )
    }
}

/// **Outside every inventory in the record** (ERRATA E182). To be looked at beside
/// `12 · read failed`: that one is the screen saying it could not ask, this one is the screen saying
/// it asked and the answer is that the record stops before here. Until E182 this drew the loading
/// screen, byte for byte.
#Preview("12 · no inventory here") {
    NavigationStack {
        AlmanacView(
            api: AlmanacPreviewAPI(payload: AlmanacFixtures.noArea),
            coordinate: Coordinate(latitude: 38.5816, longitude: -121.4944),
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
            onShowGroup: { _ in }
        )
    }
    .preferredColorScheme(.dark)
}
#endif
