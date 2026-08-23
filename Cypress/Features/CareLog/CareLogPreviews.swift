//
//  CareLogPreviews.swift
//  Cypress — Features/CareLog
//
//  Previews for screen 09, including the state it actually opens in — nothing toggled, `Done`
//  disabled — which SCREENS.md does not draw and which every contributor sees first.
//

#if DEBUG
import SwiftUI

// MARK: - Doubles

/// Answers the profile read with one named tree and refuses everything else. Previews only.
struct CareLogPreviewAPI: CypressAPI {

    var displayName: String? = "Grandmother Cypress"

    func treeProfile(id: UUID) async throws -> TreeProfile {
        TreeProfile(
            tree: CareLogPreviewFixtures.tree,
            activeName: displayName.map { TreeName(treeID: id, name: $0, givenBy: nil) },
            species: CareLogPreviewFixtures.montereyCypress
        )
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
    func deleteAccount(_ choice: AccountDeletionChoice) async throws -> AccountDeletion.Outcome {
        throw APIError.unauthorized
    }
    func logHazardRedirect(_ event: HazardRedirectEvent) async throws {}
    func exportLatest(_ format: ExportFormat) async throws -> Data { Data() }
}

/// A transport that accepts nothing, so a preview never writes anywhere real.
struct CareLogPreviewTransport: OutboxTransport {
    func sync(_ items: [OutboxItem]) async throws -> [SyncResult] { [] }
    func uploadPhoto(_ photo: OutboxPhoto, for item: OutboxItem) async throws -> UUID { UUID() }
}

enum CareLogPreviewFixtures {

    static let treeID = UUID(uuidString: "9F3A0000-0000-4000-8000-000000000009")!
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

    /// The state SCREENS.md 09 §4 draws: `Watered ✓` and `Mulched ✓` on, the other two off.
    static let drawnState = CareLogDraft(actions: [.watered, .mulched])

    static func outbox() -> OutboxQueue {
        // In-memory and unmigrated: the previews draw the sheet, they do not save from it.
        OutboxQueue(queue: try! DatabaseQueue.inMemory(), apply: CareLogPreviewTransport())
    }

    @MainActor
    static func view(
        displayName: String? = "Grandmother Cypress",
        draft: CareLogDraft = CareLogDraft()
    ) -> CareLogView {
        CareLogView(
            treeID: treeID,
            api: CareLogPreviewAPI(displayName: displayName),
            outbox: outbox(),
            attribution: .anonymous(deviceID: deviceID),
            initialDraft: draft
        )
    }
}

// MARK: - Previews

/// The state SCREENS.md 09 draws.
#Preview("09 · care log") {
    CareLogPreviewFixtures.view(draft: CareLogPreviewFixtures.drawnState)
}

/// How the sheet actually opens. Nothing is pre-toggled — a default chip would record care nobody
/// did — so `Done` carries PROTOTYPE-FLOW §1.4's disabled fill until something is tapped.
#Preview("09 · nothing toggled") {
    CareLogPreviewFixtures.view()
}

/// A tree with no given name and no species common name to fall back on: the title is the lead
/// alone rather than a middle dot with nothing after it.
#Preview("09 · unnamed tree") {
    CareLogPreviewFixtures.view(displayName: nil, draft: CareLogPreviewFixtures.drawnState)
}

/// Dark. SCREENS.md gives 09 no dark row (D1–D3 are the only ones), so this preview is evidence of
/// what the token layer resolves the sheet to rather than a design. See ERRATA (E8, E61).
#Preview("09 · dark") {
    CareLogPreviewFixtures.view(draft: CareLogPreviewFixtures.drawnState)
        .preferredColorScheme(.dark)
}
#endif
