//
//  TreeProfilePreviews.swift
//  Cypress — Features/TreeProfile
//
//  Previews for screens 03, 14 and D2.
//
//  ── Real trees ────────────────────────────────────────────────────────────────────────────
//  Every id below is a **real row of the bundled seed** (`Fixtures/seed/cypress-seed.sqlite`), and
//  every city fact beside it — address, planted year, DBH bucket, site type, DataSF `TreeID`,
//  species — is that row's own value, read out of the seed rather than made up:
//
//    sqlite3 Fixtures/seed/cypress-seed.sqlite \
//      "SELECT t.uuid, t.address, t.planted_year, t.dbh_city_cm_min, t.dbh_city_cm_max,
//              t.site_type, t.external_ref, s.scientific_name
//         FROM trees t LEFT JOIN species s ON s.id = t.species_current
//        WHERE t.uuid = '…';"
//
//  What is *not* real is the community content on the 03 preview: the given name, the photos, the
//  visits, the care events, the check-in and the two measurements. The seed carries none of that
//  for any tree — that is the entire point of screen 14 and of D8 — so a populated profile can only
//  be reached by standing community content up beside a real city row. It lives behind `#if DEBUG`
//  so none of it can ship.
//

#if DEBUG
import SwiftUI

// MARK: - A `CypressAPI` that answers one profile

/// Serves one prepared `TreeProfile` and refuses everything else. Previews only.
struct TreeProfilePreviewAPI: CypressAPI {
    let profile: TreeProfile
    /// Whether this device already holds the tree as a favorite — the on-state of C8's first cell
    /// (RULINGS R2). Read through `grove()`, which is where `TreeProfileModel` asks.
    var isFavorite = false

    func treeProfile(id: UUID) async throws -> TreeProfile {
        guard id == profile.tree.id else { throw APIError.notFound }
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
    func grove() async throws -> [GroveEntry] {
        guard isFavorite else { return [] }
        return [
            GroveEntry(
                treeID: profile.tree.id,
                displayName: profile.activeName?.name ?? "",
                coordinate: profile.tree.coordinate,
                lastVisitedAt: nil,
                isFavorite: true
            ),
        ]
    }
    func journal(cursor: String?, limit: Int) async throws -> Page<JournalEntry> { Page(items: []) }
    func claimDevice(deviceUUID: UUID, userID: UUID) async throws {}
    func deleteAccount(_ choice: AccountDeletionChoice) async throws -> AccountDeletion.Outcome {
        throw APIError.unauthorized
    }
    func logHazardRedirect(_ event: HazardRedirectEvent) async throws {}
    func exportLatest(_ format: ExportFormat) async throws -> Data { Data() }
}

// MARK: - Seed rows

enum TreeProfileSeedFixtures {

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
        return calendar
    }

    static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date()
    }

    // MARK: Trees, verbatim from the seed

    /// `2576 Lombard St`, Marina — Monterey Cypress, planted 1993, city DBH bucket 65–70 cm,
    /// DataSF TreeID 13284.
    static let montereyCypressID = UUID(uuidString: "eac6cce9-68bf-53c6-aa3c-44d26deb868d")!
    static let montereyCypressSpeciesID = UUID(uuidString: "f909a9ee-939c-5933-8220-66bb56d0c923")!

    /// `688 Geary St`, Tenderloin — Brisbane Box, planted 2024, city DBH bucket 5–10 cm,
    /// DataSF TreeID 272149. The seed's own version of the tree screen 14 was drawn from.
    static let brisbaneBoxID = UUID(uuidString: "69442c4f-dcdd-5d6f-85c9-8f3644daa6a3")!
    static let brisbaneBoxSpeciesID = UUID(uuidString: "ea4f4595-b255-56a6-bfe9-b57d41267457")!

    /// `666 Rhode Island St` — a vacant planting site the city still lists. No species, no year,
    /// no DBH: the record is a site, not a tree.
    static let vacantSiteID = UUID(uuidString: "aa72e15a-f8b2-5711-9735-95338a27104f")!

    static let montereyCypress = Tree(
        id: montereyCypressID,
        externalRef: "13284",
        source: .cityImport,
        coordinate: Coordinate(latitude: 37.799005143246, longitude: -122.443869066799),
        address: "2576 Lombard St",
        siteType: "Sidewalk: Curb side : Cutout",
        status: .alive,
        speciesCurrentID: montereyCypressSpeciesID,
        plantedYear: 1993,
        dbhCityCmRange: IntRange(lowerBound: 65, upperBound: 70),
        verificationState: .cityRecord,
        // The row's own six columns (ERRATA E143), read out of the seed like everything else here.
        cityRecord: CityRecord(
            legalStatus: "DPW Maintained",
            caretaker: "DPW",
            plantType: "Tree",
            plotSize: "3X3"
        ),
        createdAt: date(2026, 7, 21),
        updatedAt: date(2026, 7, 21)
    )

    static let brisbaneBox = Tree(
        id: brisbaneBoxID,
        externalRef: "272149",
        source: .cityImport,
        coordinate: Coordinate(latitude: 37.7867697180908, longitude: -122.414619131107),
        address: "688 Geary St",
        siteType: "Sidewalk: Curb side : Cutout",
        status: .alive,
        speciesCurrentID: brisbaneBoxSpeciesID,
        plantedYear: 2024,
        dbhCityCmRange: IntRange(lowerBound: 5, upperBound: 10),
        verificationState: .cityRecord,
        cityRecord: CityRecord(
            legalStatus: "Undocumented",
            caretaker: "Private",
            plantType: "Tree",
            plotSize: "3x3"
        ),
        createdAt: date(2026, 7, 21),
        updatedAt: date(2026, 7, 21)
    )

    static let vacantSite = Tree(
        id: vacantSiteID,
        externalRef: "271641",
        source: .cityImport,
        coordinate: Coordinate(latitude: 37.7613772513055, longitude: -122.402313864692),
        address: "666 Rhode Island St",
        siteType: "Sidewalk: Property side : Cutout",
        status: .vacantSite,
        verificationState: .cityRecord,
        cityRecord: CityRecord(
            legalStatus: "Permitted Site",
            caretaker: "Private",
            plantType: "Landscaping",
            plotSize: "11x3"
        ),
        createdAt: date(2026, 7, 21),
        updatedAt: date(2026, 7, 21)
    )

    // MARK: The five city-record states (ERRATA E145)
    //
    // Five rows, chosen so that between them every branch of `CityRecordPresentation` is on a
    // screen somebody can look at. Each is a real seed row and every city column below is that
    // row's own value:
    //
    //   sqlite3 Fixtures/seed/cypress-seed.sqlite \
    //     "SELECT uuid, legal_status, caretaker, care_assistant, plant_type, plot_size, permit_notes
    //        FROM trees WHERE uuid = '…';"
    //
    // The sixth state — a community tree with no city record at all — cannot be a seed row by
    // definition, and is `communityTree` below.

    /// `3260 Virgil St`, Bernal — every one of the six columns populated, and the tree is one of the
    /// 22,879 whose `care_assistant` is `FUF`. DataSF TreeID 221277.
    static let flameTreeID = UUID(uuidString: "14fd0840-1c30-5300-8050-6680cd4ef199")!
    static let flameTreeSpeciesID = UUID(uuidString: "0DE5A9EE-0000-4000-8000-000000000059")!

    static let flameTree = Tree(
        id: flameTreeID,
        externalRef: "221277",
        source: .cityImport,
        coordinate: Coordinate(latitude: 37.7492776968184, longitude: -122.415327896468),
        address: "3260 Virgil St",
        siteType: "Sidewalk: Curb side : Cutout",
        status: .alive,
        speciesCurrentID: flameTreeSpeciesID,
        plantedYear: 2014,
        dbhCityCmRange: IntRange(lowerBound: 5, upperBound: 10),
        verificationState: .cityRecord,
        cityRecord: CityRecord(
            legalStatus: "DPW Maintained",
            caretaker: "Private",
            careAssistant: "FUF",
            plantType: "Tree",
            plotSize: "Width 3ft",
            // Populated, and deliberately never drawn — see `permitNotesIsNotShown`. The fixture
            // carries it so that a screenshot of this tree is evidence the column is refused rather
            // than evidence the fixture forgot it.
            permitNotes: "Permit Number 771729"
        ),
        createdAt: date(2026, 7, 21),
        updatedAt: date(2026, 7, 21)
    )

    /// `2868 Bush St` — only the two columns that are always populated, and nothing else. No
    /// assistant, no plot size, no permit note, and the city has no planted year or DBH for it
    /// either. This is the floor of the section: two cards. DataSF TreeID 273314.
    static let bareRecordID = UUID(uuidString: "7f9eda5e-9d08-5ca6-8de7-6373df660f38")!
    static let bareRecordSpeciesID = UUID(uuidString: "0DE5A9EE-0000-4000-8000-00000000000F")!

    static let bareRecordTree = Tree(
        id: bareRecordID,
        externalRef: "273314",
        source: .cityImport,
        coordinate: Coordinate(latitude: 37.7857196995974, longitude: -122.444538242866),
        address: "2868 Bush St",
        siteType: "Sidewalk: Curb side : Cutout",
        status: .alive,
        speciesCurrentID: bareRecordSpeciesID,
        verificationState: .cityRecord,
        cityRecord: CityRecord(legalStatus: "Undocumented", caretaker: "Private", plantType: "Tree"),
        createdAt: date(2026, 7, 21),
        updatedAt: date(2026, 7, 21)
    )

    /// `338 Ortega St`, Sunset — one of the 196 rows whose legal status is `Prune Opt Out`, which is
    /// the closest the entire dataset comes to the pruning question #68 asked. DataSF TreeID 211090.
    static let pruneOptOutID = UUID(uuidString: "361dde0d-b08b-5f43-b9e2-db2326c2aef5")!
    static let montereyPineSpeciesID = UUID(uuidString: "0DE5A9EE-0000-4000-8000-000000000015")!

    static let pruneOptOutTree = Tree(
        id: pruneOptOutID,
        externalRef: "211090",
        source: .cityImport,
        coordinate: Coordinate(latitude: 37.7528471437891, longitude: -122.467346689111),
        address: "338 Ortega St",
        siteType: "Sidewalk: Curb side : Cutout",
        status: .alive,
        speciesCurrentID: montereyPineSpeciesID,
        dbhCityCmRange: IntRange(lowerBound: 55, upperBound: 60),
        verificationState: .cityRecord,
        cityRecord: CityRecord(
            legalStatus: "Prune Opt Out",
            caretaker: "Private",
            plantType: "Tree",
            plotSize: "Width 4ft"
        ),
        createdAt: date(2026, 7, 21),
        updatedAt: date(2026, 7, 21)
    )

    /// `2241 Bryant St` — one of the 318 rows where the city's own `plant_type` says the record on
    /// the tree map is **not** a tree. DataSF TreeID 2313.
    static let landscapingID = UUID(uuidString: "5af6a042-498c-501f-a5fb-5e3c55294b18")!
    static let oleanderSpeciesID = UUID(uuidString: "0DE5A9EE-0000-4000-8000-00000000004C")!

    static let landscapingTree = Tree(
        id: landscapingID,
        externalRef: "2313",
        source: .cityImport,
        coordinate: Coordinate(latitude: 37.7584968269853, longitude: -122.409553821766),
        address: "2241 Bryant St",
        siteType: "Sidewalk: Curb side : Cutout",
        status: .alive,
        speciesCurrentID: oleanderSpeciesID,
        plantedYear: 2000,
        dbhCityCmRange: IntRange(lowerBound: 5, upperBound: 10),
        verificationState: .cityRecord,
        cityRecord: CityRecord(
            legalStatus: "DPW Maintained",
            caretaker: "Private",
            plantType: "Landscaping",
            plotSize: "3X3"
        ),
        createdAt: date(2026, 7, 21),
        updatedAt: date(2026, 7, 21)
    )

    /// A tree somebody added, out past Ocean Beach where the city's inventory has nothing.
    ///
    /// **No `cityRecord`, and that is the state being shown**: the section does not draw, no empty
    /// state replaces it, and the only line about where it stands is the contributor's own. The
    /// coordinate is `DebugDeepLink`'s `unclaimedSpot`, for the same reason that one is where it is.
    static let communityTreeID = UUID(uuidString: "0DE5A9EE-0000-4000-8000-0000000000C0")!

    static let communityTree = Tree(
        id: communityTreeID,
        source: .community,
        coordinate: Coordinate(latitude: 37.7618, longitude: -122.5300),
        address: "Great Highway",
        status: .alive,
        speciesCurrentID: montereyCypressSpeciesID,
        placement: .contributorPlaced,
        statedLandContext: .cityPark,
        createdAt: date(2026, 7, 21),
        updatedAt: date(2026, 7, 21)
    )

    // MARK: Species, verbatim from the seed
    //
    // Both of these are in the curated 40 (BUILD-PLAN §8), so they carry a sourced family, habit
    // and id_tips; the values are copied from the seed rather than written here. `seasonal` is
    // empty for both because no source gives either a bloom or fruit calendar.
    //
    // The species-less case — where `leafRetention` is `nil` and the profile must derive no
    // phenology at all (ERRATA E9) — is the `vacant` preview below.

    static let montereyCypressSpecies = try! Species(
        id: montereyCypressSpeciesID,
        scientificName: "Cupressus macrocarpa",
        commonName: "Monterey Cypress",
        family: "Cupressaceae",
        leafRetention: .evergreen,
        curated: true,
        createdAt: date(2026, 7, 21),
        updatedAt: date(2026, 7, 21)
    )

    static let brisbaneBoxSpecies = try! Species(
        id: brisbaneBoxSpeciesID,
        scientificName: "Lophostemon confertus",
        commonName: "Brisbane Box",
        family: "Myrtaceae",
        leafRetention: .evergreen,
        curated: true,
        createdAt: date(2026, 7, 21),
        updatedAt: date(2026, 7, 21)
    )

    /// The species on the four city-record fixtures, verbatim from `seed.species`.
    static let flameTreeSpecies = try! Species(
        id: flameTreeSpeciesID,
        scientificName: "Brachychiton acerifolius",
        commonName: "Australian Flame Tree",
        family: "Malvaceae",
        leafRetention: .semiDeciduous,
        createdAt: date(2026, 7, 21),
        updatedAt: date(2026, 7, 21)
    )

    static let greenGemSpecies = try! Species(
        id: bareRecordSpeciesID,
        scientificName: "Ficus microcarpa nitida 'Green Gem'",
        commonName: "Indian Laurel Fig Tree 'Green Gem'",
        family: "Moraceae",
        leafRetention: .evergreen,
        curated: true,
        createdAt: date(2026, 7, 21),
        updatedAt: date(2026, 7, 21)
    )

    static let montereyPineSpecies = try! Species(
        id: montereyPineSpeciesID,
        scientificName: "Pinus radiata",
        commonName: "Monterey Pine",
        family: "Pinaceae",
        leafRetention: .evergreen,
        curated: true,
        createdAt: date(2026, 7, 21),
        updatedAt: date(2026, 7, 21)
    )

    static let oleanderSpecies = try! Species(
        id: oleanderSpeciesID,
        scientificName: "Nerium oleander",
        commonName: "Oleander",
        family: "Apocynaceae",
        leafRetention: .evergreen,
        createdAt: date(2026, 7, 21),
        updatedAt: date(2026, 7, 21)
    )

    // MARK: Community content — preview-only, not in the seed

    private static let device = UUID(uuidString: "00000000-0000-4000-8000-0000000000D0")!
    private static let caretakerN = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    private static let caretakerM = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
    private static let caretakerJ = UUID(uuidString: "00000000-0000-4000-8000-000000000003")!

    /// The months that carry photographs. Three months are left empty on purpose, so the season
    /// strip shows what A5 actually encodes: coverage that fills in over time.
    private static let photographedMonths = [1, 2, 3, 6, 7, 9, 10, 11, 12]

    /// 214 full-tree photos from 2019 to 2025 — the hero's `214 photos · since 2019`. The most
    /// recent lands in October 2025, so "best photo" (A3) resolves to `Oct 2025`.
    ///
    /// `.pending`, deliberately: that is the only moderation state anything in the app can produce,
    /// and a preview that quietly set `.approved` was the reason this screen looked fine in Xcode
    /// while showing no photograph at all on a device (ERRATA E37).
    static let photos: [Photo] = {
        var dates: [Date] = []
        for year in 2019...2025 {
            for month in photographedMonths {
                for day in [5, 12, 19, 26] {
                    let captured = date(year, month, day)
                    if captured <= date(2025, 10, 20) { dates.append(captured) }
                }
            }
        }
        return dates.sorted().suffix(214).map { captured in
            Photo(
                treeID: montereyCypressID,
                shotType: .fullTree,
                moderationState: .pending,
                width: 3024,
                height: 4032,
                capturedAt: captured
            )
        }
    }()

    static let visits: [Visit] = [
        Visit(
            treeID: montereyCypressID,
            attribution: Attribution(userID: caretakerN, deviceID: device),
            note: "Fog dripping off the crown",
            capturedAt: date(2025, 10, 12)
        ),
        Visit(
            treeID: montereyCypressID,
            attribution: Attribution(userID: caretakerM, deviceID: device),
            note: "Cones all over the sidewalk",
            capturedAt: date(2025, 8, 30)
        ),
    ]

    /// Three caretakers with two care events each — A8's threshold, exactly met.
    static let careEvents: [CareEvent] = [
        CareEvent(
            treeID: montereyCypressID,
            attribution: Attribution(userID: caretakerN, deviceID: device),
            capturedAt: date(2025, 9, 28),
            actions: [.watered, .mulched]
        ),
        CareEvent(
            treeID: montereyCypressID,
            attribution: Attribution(userID: caretakerN, deviceID: device),
            capturedAt: date(2025, 5, 4),
            actions: [.watered]
        ),
        CareEvent(
            treeID: montereyCypressID,
            attribution: Attribution(userID: caretakerM, deviceID: device),
            capturedAt: date(2025, 7, 19),
            actions: [.weeded]
        ),
        CareEvent(
            treeID: montereyCypressID,
            attribution: Attribution(userID: caretakerM, deviceID: device),
            capturedAt: date(2025, 3, 2),
            actions: [.litterCleared]
        ),
        CareEvent(
            treeID: montereyCypressID,
            attribution: Attribution(userID: caretakerJ, deviceID: device),
            capturedAt: date(2025, 6, 11),
            actions: [.watered]
        ),
        CareEvent(
            treeID: montereyCypressID,
            attribution: Attribution(userID: caretakerJ, deviceID: device),
            capturedAt: date(2024, 11, 23),
            actions: [.watered, .weeded]
        ),
    ]

    /// The two numbers of 03's stat grid, each with its method (D7): an estimated height and a
    /// taped DBH. They are never the same series and never lose their badge.
    static let measurements: [TreeMeasurement] = [
        .height(
            treeID: montereyCypressID,
            attribution: Attribution(userID: caretakerN, deviceID: device),
            capturedAt: date(2025, 10, 12),
            gpsAccuracyM: 6,
            quantity: Quantity(value: 18, unit: .meters, method: .estimate)
        ),
        .dbh(
            treeID: montereyCypressID,
            attribution: Attribution(userID: caretakerN, deviceID: device),
            capturedAt: date(2025, 10, 12),
            gpsAccuracyM: 6,
            quantity: Quantity(value: 64, unit: .centimeters, method: .tape)
        ),
    ]

    // MARK: Profiles

    /// Screen 03 — a real city row with community content standing beside it.
    static let populated = TreeProfile(
        tree: montereyCypress,
        activeName: TreeName(
            treeID: montereyCypressID,
            name: "Grandmother Cypress",
            givenBy: caretakerN,
            createdAt: date(2024, 4, 2),
            updatedAt: date(2024, 4, 2)
        ),
        species: montereyCypressSpecies,
        neighborhoodName: "Marina",
        latestObservation: TreeObservation(
            treeID: montereyCypressID,
            attribution: Attribution(userID: caretakerN, deviceID: device),
            capturedAt: date(2025, 10, 12),
            status: .alive,
            vitality: .thriving
        ),
        // Series, not arrays, and complete ones: this is the whole of what the fixture holds, so
        // the hero's `214 photos · since 2019` is a real count of a real series rather than a page
        // of one presented as a total (ERRATA E38).
        photos: Series(complete: photos),
        measurements: measurements,
        visits: Series(complete: visits),
        careEvents: Series(complete: careEvents),
        // The preview device took every one of these, which is why they render at all while their
        // moderation state is `.pending` (ERRATA E37).
        ownPhotoIDs: Set(photos.map(\.id))
    )

    /// Screen 14 — the same shape of record every seeded tree actually has: city facts, nothing
    /// else.
    static let coldStart = TreeProfile(
        tree: brisbaneBox,
        species: brisbaneBoxSpecies,
        neighborhoodName: "Tenderloin"
    )

    /// Screen 14 on a site the city lists with no tree in it. Not drawn in SCREENS.md; rendered as
    /// the cold variant with the record's own facts and nothing invented.
    static let vacant = TreeProfile(
        tree: vacantSite,
        neighborhoodName: "Potrero Hill"
    )

    // ── The five §9b states (ERRATA E145) ────────────────────────────────────────────────────

    /// All six columns, `FUF` among them, and a permit note that is not drawn.
    static let fullCityRecord = TreeProfile(
        tree: flameTree,
        species: flameTreeSpecies,
        neighborhoodName: "Bernal Heights"
    )

    /// Only the two columns that are always populated: two cards and nothing else.
    static let bareCityRecord = TreeProfile(
        tree: bareRecordTree,
        species: greenGemSpecies,
        neighborhoodName: "Lower Pacific Heights"
    )

    /// One of the 196 `Prune Opt Out` rows — the pruning question's only real answer.
    static let pruneOptOut = TreeProfile(
        tree: pruneOptOutTree,
        species: montereyPineSpecies,
        neighborhoodName: "Outer Sunset"
    )

    /// One of the 318 rows the city does not list as a tree.
    static let listedAsLandscaping = TreeProfile(
        tree: landscapingTree,
        species: oleanderSpecies,
        neighborhoodName: "Mission"
    )

    /// A community tree: no city section at all, and the only land-context line on the screen is
    /// the one a contributor stated.
    static let communityAdded = TreeProfile(
        tree: communityTree,
        species: montereyCypressSpecies,
        neighborhoodName: "Outer Sunset"
    )
}

// MARK: - Previews

@MainActor
func treeProfilePreview(
    _ profile: TreeProfile,
    caretakerInitials: [String] = [],
    isFavorite: Bool = false,
    scheme: ColorScheme = .light
) -> some View {
    TreeProfileView(
        treeID: profile.tree.id,
        api: TreeProfilePreviewAPI(profile: profile, isFavorite: isFavorite),
        caretakerInitials: caretakerInitials
    )
    .environment(AppRouter())
    .preferredColorScheme(scheme)
}

#Preview("03 · Tree profile") {
    treeProfilePreview(TreeProfileSeedFixtures.populated, caretakerInitials: ["N", "M", "J"])
}

#Preview("14 · Cold start") {
    treeProfilePreview(TreeProfileSeedFixtures.coldStart)
}

/// C8's first cell in its selected state (RULINGS R2). The same profile as the 03 preview above,
/// on a device that already holds this tree — which is a read of `grove()`, not a flag on the view.
#Preview("03 · Tree profile, favorited") {
    treeProfilePreview(
        TreeProfileSeedFixtures.populated,
        caretakerInitials: ["N", "M", "J"],
        isFavorite: true
    )
}

/// The vacant planting site no longer renders here at all: it leaves for `Route.site` before
/// anything is derived (ERRATA E113). This preview shows what that looks like from inside the
/// profile — a spinner and a routing call — and the screen itself is previewed in `SitePreviews`.
/// The fixture stays because it is the one thing that proves the redirect fires under a preview's
/// router as well as under the app's.
#Preview("14 · Vacant site → redirects to the site screen") {
    treeProfilePreview(TreeProfileSeedFixtures.vacant)
}

// ── §9b · What the city has on file (ERRATA E145, E181) ──────────────────────────────────────

#Preview("9b · Every city column, FUF among them") {
    treeProfilePreview(TreeProfileSeedFixtures.fullCityRecord)
}

#Preview("9b · Only the always-populated columns") {
    treeProfilePreview(TreeProfileSeedFixtures.bareCityRecord)
}

#Preview("9b · Prune Opt Out — the pruning question's only answer") {
    treeProfilePreview(TreeProfileSeedFixtures.pruneOptOut)
}

#Preview("9b · The city does not list this as a tree") {
    treeProfilePreview(TreeProfileSeedFixtures.listedAsLandscaping)
}

#Preview("9b · Community-added — no city record to show") {
    treeProfilePreview(TreeProfileSeedFixtures.communityAdded)
}

#Preview("9b · Every city column, dark") {
    treeProfilePreview(TreeProfileSeedFixtures.fullCityRecord, scheme: .dark)
}

#Preview("D2 · Tree profile, dark") {
    treeProfilePreview(TreeProfileSeedFixtures.populated, caretakerInitials: ["N", "M", "J"], scheme: .dark)
}
#endif
