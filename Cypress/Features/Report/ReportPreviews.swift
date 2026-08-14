//
//  ReportPreviews.swift
//  Cypress — Features/Report
//
//  Previews for screen 06, including the two states SCREENS.md marks NOT SPECIFIED so that what was
//  chosen for them is visible rather than described.
//

#if DEBUG
import SwiftUI

// MARK: - Doubles

/// Accepts the redirect log, answers `treeProfile` with whatever tree the preview wants the screen
/// to be about, and refuses everything else. Previews only.
struct ReportPreviewAPI: CypressAPI {
    /// The tree screen 06 will read for its land context (ERRATA E146). `nil` throws `.notFound`,
    /// which is what every preview of this screen did before there was anything to read — and is
    /// still the state that draws the panel SCREENS.md mocks.
    var tree: Tree?

    func logHazardRedirect(_ event: HazardRedirectEvent) async throws {}
    func mapContent(in viewport: MapViewport) async throws -> MapContent { .pins([]) }
    func treesNear(_ coordinate: Coordinate, radiusM: Double, limit: Int) async throws -> [NearbyTree] { [] }
    func treeProfile(id: UUID) async throws -> TreeProfile {
        guard let tree else { throw APIError.notFound }
        return TreeProfile(tree: tree)
    }
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
    func exportLatest(_ format: ExportFormat) async throws -> Data { Data() }
}

/// A dialer that answers without touching the system, so a preview never tries to place a call.
struct ReportPreviewDialer: TelephoneDialing {
    var isAvailable: Bool = true
    func canPlaceCall(to url: URL) async -> Bool { isAvailable }
    func placeCall(to url: URL) async -> Bool { isAvailable }
}

// MARK: - Previews

/// `Great Highway at Judah` — the tree SCREENS.md uses throughout.
///
/// The screen used to read nothing about the tree and the old note here said so approvingly. That
/// was the defect: a hazard report carries a tree id and a category and no tree content, so a tree
/// on private land got the city's telephone number (E143's flag, closed in E146). It now reads one
/// field, and the three previews below stand up the three answers.
private let previewTreeID = UUID(uuidString: "9F3A0000-0000-4000-8000-000000000001")!

private let previewCoordinate = Coordinate(latitude: 37.7601, longitude: -122.5094)

/// A community tree whose contributor tapped `Private property` — an observation, so the panel
/// changes.
private let previewStatedPrivateTree = Tree(
    id: previewTreeID,
    source: .community,
    coordinate: previewCoordinate,
    statedLandContext: .privateProperty
)

/// A city row Cypress *reads* as private land. `Undocumented` with a private caretaker is the
/// commonest shape of it — 8,126 seed rows — and is exactly the weak arm that keeps the 311 CTA.
private let previewInferredPrivateTree = Tree(
    id: previewTreeID,
    source: .cityImport,
    coordinate: previewCoordinate,
    cityRecord: CityRecord(legalStatus: "Undocumented", caretaker: "Private")
)

/// The state SCREENS.md draws: a hazard chip on, and the 311 branch below it.
#Preview("06 · hazard selected") {
    NavigationStack {
        ReportView(
            treeID: previewTreeID,
            api: ReportPreviewAPI(),
            dialer: ReportPreviewDialer(),
            initialSelection: .hazard(.hangingOrBrokenLimb)
        )
    }
    .environment(AppRouter())
}

/// **NOT SPECIFIED** by SCREENS.md 06, and how the screen opens: the header and the two pickers.
#Preview("06 · nothing selected") {
    NavigationStack {
        ReportView(
            treeID: previewTreeID,
            api: ReportPreviewAPI(),
            dialer: ReportPreviewDialer()
        )
    }
    .environment(AppRouter())
}

/// **NOT SPECIFIED** by SCREENS.md 06: a neighborly chip on and no 311 branch, because there is no
/// hazard to call about.
#Preview("06 · neighborly selected") {
    NavigationStack {
        ReportView(
            treeID: previewTreeID,
            api: ReportPreviewAPI(),
            dialer: ReportPreviewDialer(),
            initialSelection: .note(.needsWater)
        )
    }
    .environment(AppRouter())
}

/// **NOT SPECIFIED** (ERRATA E146). The contributor said this tree stands on private property, so
/// the panel says the city is not the party that fixes it and `Call 311 now` becomes
/// `Call 311 anyway`. Demoted, not deleted.
#Preview("06 · hazard · contributor says private") {
    NavigationStack {
        ReportView(
            treeID: previewTreeID,
            api: ReportPreviewAPI(tree: previewStatedPrivateTree),
            dialer: ReportPreviewDialer(),
            initialSelection: .hazard(.hangingOrBrokenLimb)
        )
    }
    .environment(AppRouter())
}

/// **NOT SPECIFIED** (ERRATA E146). The *city's* record reads as private land. The panel and the
/// amber CTA are untouched; one line under the button says what was read. An inference informs and
/// does not redirect.
#Preview("06 · hazard · city record reads private") {
    NavigationStack {
        ReportView(
            treeID: previewTreeID,
            api: ReportPreviewAPI(tree: previewInferredPrivateTree),
            dialer: ReportPreviewDialer(),
            initialSelection: .hazard(.hangingOrBrokenLimb)
        )
    }
    .environment(AppRouter())
}

/// The device that cannot dial — the alert, over the drawn screen unchanged.
#Preview("06 · call unavailable") {
    NavigationStack {
        ReportView(
            treeID: previewTreeID,
            api: ReportPreviewAPI(),
            dialer: ReportPreviewDialer(isAvailable: false),
            initialSelection: .hazard(.hangingOrBrokenLimb)
        )
    }
    .environment(AppRouter())
}
#endif
