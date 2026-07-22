import Foundation
import Testing
@testable import Cypress

/// `GET /export/latest` and the paging underneath it.
///
/// The export took page one of a cursor-paginated journal and threw the cursor away, so an export
/// stopped at 100 rows with nothing in the file saying it had (ERRATA E39). Its own doc comment
/// names the account-data request as a use case: an incomplete subject-access export, presented as
/// complete, is the kind of wrong that only shows up when somebody needs it to be right.
@Suite("Journal export")
struct JournalExportTests {

    private static let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-0000000000A9")!
    private static let start = Date(timeIntervalSince1970: 1_700_000_000)

    /// More than two pages of the 100-row maximum, so a single-page export is unmistakably short.
    private static let visitCount = 250

    private static func makeStore() async throws -> (CypressStore, LocalAPI, Tree) {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: deviceID)
        let tree = try await api.addTree(
            TreeDraft(
                coordinate: Coordinate(latitude: 37.7761, longitude: -122.4464),
                photoLocalPath: "/tmp/cypress-export-test.jpg",
                attribution: Attribution.anonymous(deviceID: deviceID)
            )
        )
        let contributions = ContributionStore()
        try await store.queue.write { connection in
            for index in 0..<visitCount {
                // Distinct capture times: the cursor is a timestamp, and rows sharing one at a page
                // boundary are a separate, still-open defect (ERRATA E39).
                let visit = Visit(
                    treeID: tree.id,
                    attribution: Attribution.anonymous(deviceID: deviceID),
                    note: "visit \(index)",
                    capturedAt: start.addingTimeInterval(Double(index) * 60)
                )
                try contributions.insert(visit, connection: connection)
            }
        }
        return (store, api, tree)
    }

    @Test("the CSV export carries every contribution, not the first page of them")
    func csvExportIsComplete() async throws {
        let (_, api, _) = try await Self.makeStore()

        let data = try await api.exportLatest(.csv)
        let text = try #require(String(data: data, encoding: .utf8))
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)

        // Two header lines: the structure-flag disclaimer and the column row (D12).
        #expect(lines.count == Self.visitCount + 2, "the export holds \(lines.count - 2) rows of \(Self.visitCount)")
        #expect(lines[0].hasPrefix("#"))
        #expect(lines[1] == "kind,tree_id,captured_at,summary,verification_state")
        #expect(text.contains("visit 0"), "the oldest contribution is missing — the export stopped early")
        #expect(text.contains("visit \(Self.visitCount - 1)"))
        // D12: every citizen row carries its machine-readable marker.
        #expect(lines.dropFirst(2).allSatisfy { $0.hasSuffix(VerificationState.unverified.rawValue) })
    }

    @Test("the GeoJSON export carries every contribution too")
    func geoJSONExportIsComplete() async throws {
        let (_, api, _) = try await Self.makeStore()

        let data = try await api.exportLatest(.geojson)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let features = try #require(root["features"] as? [[String: Any]])
        #expect(features.count == Self.visitCount)
        #expect(root["note"] as? String == StructureFlag.disclaimer)
    }

    @Test("the journal is still paginated, and its pages still end")
    func journalStillPages() async throws {
        let (_, api, _) = try await Self.makeStore()

        var seen: Set<UUID> = []
        var pages = 0
        var cursor: String?
        repeat {
            let page = try await api.journal(cursor: cursor, limit: Page<JournalEntry>.maximumLimit)
            pages += 1
            for entry in page.items { seen.insert(entry.id) }
            cursor = page.nextCursor
        } while cursor != nil

        #expect(pages == 3, "250 rows at 100 a page is three pages, was \(pages)")
        #expect(seen.count == Self.visitCount)
    }

    // MARK: - The store's own page-versus-series answer

    @Test("a limited read says it is a page; an unlimited one says it is the series")
    func storeReportsCompleteness() async throws {
        let (store, _, tree) = try await Self.makeStore()
        let contributions = ContributionStore()

        let whole = try await store.queue.read { connection in
            try contributions.visits(treeID: tree.id, connection: connection)
        }
        #expect(whole.isComplete)
        #expect(whole.totalCount == Self.visitCount)

        let page = try await store.queue.read { connection in
            try contributions.visits(treeID: tree.id, limit: 50, connection: connection)
        }
        #expect(!page.isComplete)
        #expect(page.totalCount == nil)
        #expect(page.items.count == 50)

        // A limit larger than the series is not a page: the row that would have proved otherwise
        // was asked for and did not exist.
        let generous = try await store.queue.read { connection in
            try contributions.visits(treeID: tree.id, limit: Self.visitCount + 1, connection: connection)
        }
        #expect(generous.isComplete)
        #expect(generous.totalCount == Self.visitCount)

        // Exactly the series length is the boundary case, and it is still complete.
        let exact = try await store.queue.read { connection in
            try contributions.visits(treeID: tree.id, limit: Self.visitCount, connection: connection)
        }
        #expect(exact.isComplete)
        #expect(exact.totalCount == Self.visitCount)
    }

    @Test("the profile reads its series whole, so the screen can count them")
    func profileSeriesAreComplete() async throws {
        let (_, api, tree) = try await Self.makeStore()
        let profile = try await api.treeProfile(id: tree.id)

        #expect(profile.visits.isComplete)
        #expect(profile.visits.totalCount == Self.visitCount)
        #expect(profile.photos.isComplete)
        #expect(profile.careEvents.isComplete)
        // One photo, from the community add.
        #expect(profile.photos.totalCount == 1)
    }
}
