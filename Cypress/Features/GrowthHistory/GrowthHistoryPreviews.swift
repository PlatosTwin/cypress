//
//  GrowthHistoryPreviews.swift
//  Cypress — Features/GrowthHistory
//
//  Previews for screen 11, including the two states most trees are actually in — a sparse chart and
//  no chart at all — because they are the ones SCREENS.md does not draw and the ones the shipped
//  seed produces.
//

#if DEBUG
import SwiftUI

// MARK: - Doubles

/// Answers the profile read with one measurement series and refuses everything else. Previews only.
struct GrowthHistoryPreviewAPI: CypressAPI {

    var profile: TreeProfile = GrowthHistoryPreviewFixtures.drawnProfile()
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
    func grove() async throws -> [GroveEntry] { [] }
    func journal(cursor: String?, limit: Int) async throws -> Page<JournalEntry> { Page(items: []) }
    func claimDevice(deviceUUID: UUID, userID: UUID) async throws {}
    func logHazardRedirect(_ event: HazardRedirectEvent) async throws {}
    func exportLatest(_ format: ExportFormat) async throws -> Data { Data() }
}

enum GrowthHistoryPreviewFixtures {

    static let treeID = UUID(uuidString: "9F3A0000-0000-4000-8000-000000000011")!
    static let deviceID = UUID(uuidString: "9F3A0000-0000-4000-8000-0000000000DE")!

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

    static func date(_ year: Int, _ month: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: 12))!
    }

    /// A chartable reading: a good fix, which D6 requires before a point may be plotted.
    static func dbh(
        _ year: Int,
        _ month: Int,
        _ centimeters: Double,
        _ method: MeasurementMethod,
        accuracyM: Double = 6
    ) -> TreeMeasurement {
        TreeMeasurement.dbh(
            treeID: treeID,
            attribution: .anonymous(deviceID: deviceID),
            capturedAt: date(year, month),
            gpsAccuracyM: accuracyM,
            quantity: Quantity(value: centimeters, unit: .centimeters, method: method)
        )
    }

    static func height(
        _ year: Int,
        _ month: Int,
        _ meters: Double,
        _ method: MeasurementMethod,
        accuracyM: Double = 6
    ) -> TreeMeasurement {
        TreeMeasurement.height(
            treeID: treeID,
            attribution: .anonymous(deviceID: deviceID),
            capturedAt: date(year, month),
            gpsAccuracyM: accuracyM,
            quantity: Quantity(value: meters, unit: .meters, method: method)
        )
    }

    static func profile(_ measurements: [TreeMeasurement]) -> TreeProfile {
        TreeProfile(
            tree: tree,
            activeName: TreeName(treeID: treeID, name: "Grandmother Cypress", givenBy: nil),
            species: montereyCypress,
            measurements: measurements
        )
    }

    /// SCREENS.md 11's own series: DBH 47→64 cm since 2019, hollow at the first and third readings;
    /// height 14→18 m since 2020 with one taped reading among the estimates.
    static func drawnProfile() -> TreeProfile {
        profile([
            dbh(2019, 6, 47, .estimate),
            dbh(2020, 9, 51, .tape),
            dbh(2021, 7, 54, .estimate),
            dbh(2022, 8, 56, .tape),
            dbh(2023, 8, 60, .tape),
            dbh(2024, 6, 62, .tape),
            dbh(2025, 10, 64, .tape),
            height(2020, 5, 14, .estimate),
            height(2021, 6, 15, .estimate),
            height(2022, 7, 15.5, .tape),
            height(2023, 8, 16, .estimate),
            height(2024, 7, 17, .estimate),
            height(2025, 9, 18, .estimate),
        ])
    }

    /// **The state most trees are in.** Two readings, four years apart, both estimates. Two dots and
    /// one short line, which is what two estimates four years apart look like.
    static func sparseProfile() -> TreeProfile {
        profile([
            dbh(2021, 4, 58, .estimate),
            dbh(2025, 10, 64, .estimate),
        ])
    }

    /// One reading. There is a dot and no line, because a line between one point and nothing is a
    /// trend that was never measured.
    static func singlePointProfile() -> TreeProfile {
        profile([dbh(2025, 10, 64, .tape)])
    }

    /// **D6, visible.** Three readings taken in an urban canyon at 22–48 m accuracy, and one with no
    /// fix recorded at all. None may be charted; all four stay in the log, because the record is the
    /// record.
    static func ineligibleProfile() -> TreeProfile {
        profile([
            dbh(2023, 8, 60, .tape, accuracyM: 22),
            dbh(2024, 6, 62, .tape, accuracyM: 48),
            dbh(2025, 10, 64, .tape, accuracyM: 31),
            TreeMeasurement.dbh(
                treeID: treeID,
                attribution: .anonymous(deviceID: deviceID),
                capturedAt: date(2022, 5),
                gpsAccuracyM: nil,
                quantity: Quantity(value: 57, unit: .centimeters, method: .estimate)
            ),
        ])
    }

    /// **The state every tree in the shipped seed is in.** The seed carries no measurements table,
    /// and screen 16 is the only thing that can create one.
    static func emptyProfile() -> TreeProfile { profile([]) }
}

// MARK: - Previews

/// The state SCREENS.md 11 draws: two cards, both series on the DBH chart, the legend, the log.
#Preview("11 · growth history") {
    NavigationStack {
        GrowthHistoryView(
            treeID: GrowthHistoryPreviewFixtures.treeID,
            api: GrowthHistoryPreviewAPI()
        )
    }
    .environment(AppRouter())
}

/// **Sparse.** Two estimates, four years apart. Correct output, not a gap to fill.
#Preview("11 · sparse — two readings") {
    NavigationStack {
        GrowthHistoryView(
            treeID: GrowthHistoryPreviewFixtures.treeID,
            api: GrowthHistoryPreviewAPI(profile: GrowthHistoryPreviewFixtures.sparseProfile())
        )
    }
    .environment(AppRouter())
}

/// One reading: a dot, a value, one axis year, and no line.
#Preview("11 · one reading") {
    NavigationStack {
        GrowthHistoryView(
            treeID: GrowthHistoryPreviewFixtures.treeID,
            api: GrowthHistoryPreviewAPI(profile: GrowthHistoryPreviewFixtures.singlePointProfile())
        )
    }
    .environment(AppRouter())
}

/// **D6.** Four readings the record keeps and no chart may plot. The log is full and there is no
/// card above it. **NOT SPECIFIED** by SCREENS.md; see ERRATA (E63).
#Preview("11 · readings, none chartable") {
    NavigationStack {
        GrowthHistoryView(
            treeID: GrowthHistoryPreviewFixtures.treeID,
            api: GrowthHistoryPreviewAPI(profile: GrowthHistoryPreviewFixtures.ineligibleProfile())
        )
    }
    .environment(AppRouter())
}

/// **Empty.** Every tree in the shipped inventory, on launch day. **NOT SPECIFIED** by SCREENS.md;
/// see ERRATA (E63).
#Preview("11 · empty") {
    NavigationStack {
        GrowthHistoryView(
            treeID: GrowthHistoryPreviewFixtures.treeID,
            api: GrowthHistoryPreviewAPI(profile: GrowthHistoryPreviewFixtures.emptyProfile())
        )
    }
    .environment(AppRouter())
}

/// Dark. SCREENS.md gives 11 no dark row, so this is evidence of what the token layer resolves the
/// screen to rather than a design. See ERRATA (E61).
#Preview("11 · dark") {
    NavigationStack {
        GrowthHistoryView(
            treeID: GrowthHistoryPreviewFixtures.treeID,
            api: GrowthHistoryPreviewAPI()
        )
    }
    .environment(AppRouter())
    .preferredColorScheme(.dark)
}
#endif
