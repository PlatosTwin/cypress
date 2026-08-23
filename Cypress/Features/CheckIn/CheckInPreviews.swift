//
//  CheckInPreviews.swift
//  Cypress — Features/CheckIn
//
//  Previews for screen 05 and its dark twin D3, plus the leaf-off state BUILD-PLAN §9 lists as a
//  required build and SCREENS.md does not draw — so what was chosen for it is visible rather than
//  described.
//

#if DEBUG
import SwiftUI

// MARK: - Doubles

/// Answers the profile read with a species and refuses everything else. Previews only.
struct CheckInPreviewAPI: CypressAPI {

    /// What `GET /trees/{id}` hands back. Only `species` is read by this screen.
    var speciesRecord: Species?

    func treeProfile(id: UUID) async throws -> TreeProfile {
        TreeProfile(tree: CheckInPreviewFixtures.tree(id: id), species: speciesRecord)
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
struct CheckInPreviewTransport: OutboxTransport {
    func sync(_ items: [OutboxItem]) async throws -> [SyncResult] { [] }
    func uploadPhoto(_ photo: OutboxPhoto, for item: OutboxItem) async throws -> UUID { UUID() }
}

enum CheckInPreviewFixtures {

    static let treeID = UUID(uuidString: "9F3A0000-0000-4000-8000-000000000005")!
    static let deviceID = UUID(uuidString: "9F3A0000-0000-4000-8000-0000000000DE")!

    static func tree(id: UUID) -> Tree {
        Tree(
            source: .cityImport,
            coordinate: Coordinate(latitude: 37.7601, longitude: -122.5054),
            verificationState: .cityRecord
        )
    }

    /// An evergreen: ratable in every month (PRODUCT §3).
    static let montereyCypress = try! Species(
        scientificName: "Hesperocyparis macrocarpa",
        commonName: "Monterey Cypress",
        family: "Cupressaceae",
        leafRetention: .evergreen,
        curated: true
    )

    /// A deciduous species on the default April–October leaf-on window, so a December preview lands
    /// in the suppressed state.
    static let ginkgo = try! Species(
        scientificName: "Ginkgo biloba",
        commonName: "Ginkgo",
        family: "Ginkgoaceae",
        leafRetention: .deciduous,
        curated: true
    )

    /// D3's caption: "The screen a volunteer uses at 7 am in December."
    static let december = Calendar.current.date(
        from: DateComponents(year: 2026, month: 12, day: 3, hour: 7)
    )!
    /// A month every species is in leaf.
    static let july = Calendar.current.date(
        from: DateComponents(year: 2026, month: 7, day: 3, hour: 9)
    )!

    /// The one fixed state the design export draws (SCREENS.md §"Ground rules": every selected chip
    /// is drawn in a single state).
    static let drawnState = CheckInDraft(
        status: .alive,
        vitality: .good,
        foliageDensity: .thinning,
        structureFlags: [.brokenLimb]
    )

    static func outbox() -> OutboxQueue {
        // In-memory and unmigrated: the previews draw the card, they do not save from it.
        OutboxQueue(queue: try! DatabaseQueue.inMemory(), apply: CheckInPreviewTransport())
    }

    @MainActor
    static func view(
        species: Species? = montereyCypress,
        now: Date = july,
        draft: CheckInDraft = CheckInDraft()
    ) -> CheckInView {
        CheckInView(
            treeID: treeID,
            api: CheckInPreviewAPI(speciesRecord: species),
            outbox: outbox(),
            attribution: .anonymous(deviceID: deviceID),
            species: species,
            initialDraft: draft,
            now: { now }
        )
    }
}

// MARK: - Previews

/// The state SCREENS.md 05 draws: `Alive`, vitality `4 · Good`, foliage `Thinning`,
/// `Broken limb` flagged.
#Preview("05 · light check-in") {
    NavigationStack {
        CheckInPreviewFixtures.view(draft: CheckInPreviewFixtures.drawnState)
    }
    .environment(AppRouter())
}

/// D3 — the same card at 7 am in December, on the dark palette.
#Preview("D3 · check-in, dark") {
    NavigationStack {
        CheckInPreviewFixtures.view(
            now: CheckInPreviewFixtures.december,
            draft: CheckInPreviewFixtures.drawnState
        )
    }
    .environment(AppRouter())
    .preferredColorScheme(.dark)
}

/// How the screen actually opens: only `Alive`, which is the one field with a default.
#Preview("05 · nothing filled in") {
    NavigationStack {
        CheckInPreviewFixtures.view()
    }
    .environment(AppRouter())
}

/// **NOT SPECIFIED** by SCREENS.md; required by BUILD-PLAN §9 M2. A deciduous tree in December:
/// the vitality section says why it is empty, and every other field still works.
#Preview("05 · vitality suppressed, leaf-off") {
    NavigationStack {
        CheckInPreviewFixtures.view(
            species: CheckInPreviewFixtures.ginkgo,
            now: CheckInPreviewFixtures.december
        )
    }
    .environment(AppRouter())
}
#endif
