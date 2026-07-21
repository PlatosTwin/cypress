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

/// Accepts the redirect log and refuses everything else. Previews only.
struct ReportPreviewAPI: CypressAPI {
    func logHazardRedirect(_ event: HazardRedirectEvent) async throws {}

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
    func exportLatest(_ format: ExportFormat) async throws -> Data { Data() }
}

/// A dialer that answers without touching the system, so a preview never tries to place a call.
struct ReportPreviewDialer: TelephoneDialing {
    var isAvailable: Bool = true
    func canPlaceCall(to url: URL) async -> Bool { isAvailable }
    func placeCall(to url: URL) async -> Bool { isAvailable }
}

// MARK: - Previews

/// `Great Highway at Judah` — the tree SCREENS.md uses throughout. Any id does here: screen 06
/// reads nothing about the tree, which is itself the point (a hazard report carries the tree id and
/// a category, and no tree content).
private let previewTreeID = UUID(uuidString: "9F3A0000-0000-4000-8000-000000000001")!

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
