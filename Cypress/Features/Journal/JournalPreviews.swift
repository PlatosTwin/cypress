//
//  JournalPreviews.swift
//  Cypress — Features/Journal
//
//  Previews for the journal list, and the double the suite drives it with.
//
//  Every state here is one SCREENS.md does not draw, because SCREENS.md draws none of them — so
//  these previews are the only picture of what was chosen. The two that matter most are the last
//  two: an empty journal and a journal that could not be read, side by side, because the whole point
//  of ERRATA E126 is that they must not look the same.
//

#if DEBUG
import SwiftUI

// MARK: - Double

/// Counts reads, so a test can assert that a page was *not* fetched.
///
/// A class with a lock rather than an actor: the assertions read it synchronously after an `await`,
/// and an actor would make every one of them a suspension point in a test that is checking whether a
/// suspension happened. Same arrangement as `FavoriteToggleTests.Writes`.
final class JournalReadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func record() {
        lock.lock()
        defer { lock.unlock() }
        value += 1
    }
}

/// Hands back fixed journal pages and refuses everything else.
struct JournalPreviewAPI: CypressAPI {

    /// The first page.
    var page: Page<JournalEntry> = Page(items: [])
    /// What the second read returns, when there is one.
    var older: Page<JournalEntry>?
    /// Makes every read fail — the only way to see the failure arm without a broken device (E126).
    var fails = false
    /// Makes only the *first* read fail, so a retry can be seen to recover.
    var failsOnce = false
    /// Makes only `Show earlier` fail, which must not take the whole screen down.
    var olderFails = false
    var reads: JournalReadCounter?

    var exportBytes = Data()
    var geoJSONBytes = Data()

    func journal(cursor: String?, limit: Int) async throws -> Page<JournalEntry> {
        let attempt = reads?.count ?? 0
        reads?.record()
        if fails { throw APIError.serverError }
        if failsOnce, attempt == 0 { throw APIError.serverError }
        guard cursor != nil else { return page }
        if olderFails { throw APIError.serverError }
        return older ?? Page(items: [])
    }

    func exportLatest(_ format: ExportFormat) async throws -> Data {
        switch format {
        case .csv: return exportBytes
        case .geojson: return geoJSONBytes
        }
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
    func claimDevice(deviceUUID: UUID, userID: UUID) async throws {}
    func deleteAccount(_ choice: AccountDeletionChoice) async throws -> AccountDeletion.Outcome {
        throw APIError.unauthorized
    }
    func logHazardRedirect(_ event: HazardRedirectEvent) async throws {}
}

// MARK: - Fixtures

enum JournalFixtures {

    static let now = Date(timeIntervalSince1970: 1_753_142_400) // 2025-07-22, 00:00 UTC

    static func entry(
        _ index: Int,
        kind: JournalEntry.Kind,
        tree: String,
        daysAgo: Int,
        summary: String
    ) -> JournalEntry {
        JournalEntry(
            id: UUID(uuidString: String(format: "12000000-0000-4000-8000-%012d", index))!,
            kind: kind,
            treeID: UUID(uuidString: String(format: "12000000-0000-4000-8000-%012d", 900 + index))!,
            treeDisplayName: tree,
            capturedAt: now.addingTimeInterval(TimeInterval(-daysAgo * 86_400)),
            summary: summary
        )
    }

    /// One of each kind, so all four accents are visible together.
    static let entries: [JournalEntry] = [
        entry(1, kind: .visit, tree: "Grandmother Cypress", daysAgo: 1, summary: "Fog on the crown"),
        entry(2, kind: .careEvent, tree: "Grandmother Cypress", daysAgo: 3, summary: "watering, weeding"),
        entry(3, kind: .measurement, tree: "Ginkgo on Judah", daysAgo: 12, summary: "31 cm taped"),
        // `Spring flush noted` until the copy audit of 2026-08-23 retired it — see
        // `ActivityPresentation.moments`. A preview fixture is a place retired copy survives.
        entry(4, kind: .observation, tree: "Ginkgo on Judah", daysAgo: 40, summary: "Leaf-out noted"),
        entry(5, kind: .visit, tree: "", daysAgo: 400, summary: "")
    ]
}

// MARK: - Previews

/// The drawn state, with the read having reached the end: no note about earlier entries, because
/// there are none and a finished list needs no explaining.
#Preview("journal · a record") {
    NavigationStack {
        ScrollView {
            JournalListView(
                presentation: JournalPresentation(
                    entries: JournalFixtures.entries,
                    nextCursor: nil,
                    now: JournalFixtures.now
                ),
                onOpenTree: { _ in }
            )
        }
    }
}

/// The same rows read as a page (ERRATA E38). The list gains one sentence and a control, and still
/// prints no number — because there is no number a cursor read is entitled to print.
#Preview("journal · came back a page") {
    NavigationStack {
        ScrollView {
            JournalListView(
                presentation: JournalPresentation(
                    entries: JournalFixtures.entries,
                    nextCursor: "2024-06-01T12:00:00Z",
                    now: JournalFixtures.now
                ),
                onOpenTree: { _ in },
                onShowOlder: {}
            )
        }
    }
}

/// Day one on every device. Drawn only because the read proved it reached the end.
#Preview("journal · nothing recorded") {
    NavigationStack {
        ScrollView {
            JournalListView(
                presentation: JournalPresentation(entries: [], nextCursor: nil, now: JournalFixtures.now)
            )
        }
    }
}

/// The read that failed. Meant to be looked at beside `journal · nothing recorded` above: the whole
/// of ERRATA E126 is that these two are not the same picture.
#Preview("journal · read failed") {
    NavigationStack {
        ScrollView {
            JournalListView(presentation: nil, hasFailed: true, onRetry: {})
        }
    }
}

/// A `Show earlier` that failed. Every row already read stays on screen; one line is added.
#Preview("journal · earlier entries failed") {
    NavigationStack {
        ScrollView {
            JournalListView(
                presentation: JournalPresentation(
                    entries: JournalFixtures.entries,
                    nextCursor: "2024-06-01T12:00:00Z",
                    now: JournalFixtures.now
                ),
                hasFailedOlder: true,
                onOpenTree: { _ in },
                onShowOlder: {}
            )
        }
    }
}

/// The tab, with both segments — the journal it is named for, and the almanac whose only entrance it
/// is (see `JournalTabView`).
#Preview("journal tab · two segments") {
    NavigationStack {
        JournalTabView(
            api: JournalPreviewAPI(page: Page(items: JournalFixtures.entries)),
            coordinate: nil
        )
    }
    .environment(AppRouter())
}

/// The export rows, which had no button anywhere in the app until this round.
#Preview("journal · export rows") {
    ScrollView {
        JournalExportRows(export: JournalExportBytes { _ in Data() })
    }
    .background(CypressColor.surfaceScreen)
}
#endif
