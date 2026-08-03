//
//  GrovePreviews.swift
//  Cypress — Features/Grove
//
//  Previews for screen 08, including the states SCREENS.md does not draw — the empty grove
//  (BUILD-PLAN §9 M2 requires it and no mock covers it) and the read that came back a page — so
//  that what was chosen for them is visible rather than described.
//

#if DEBUG
import SwiftUI

// MARK: - Double

/// Counts `grove()` reads, so a test can assert the `Trees` pill's read is lazy and runs once.
final class GroveReadCounter: @unchecked Sendable {
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

/// Hands back a fixed grove and refuses everything else. Previews only.
///
/// **Two reads and two ways to fail**, because screen 08 has two pills with data behind them and
/// they are two endpoints. A double with one `fails` flag could not express the case that matters
/// most — one read failing while the other succeeds — which is the case `GroveModel` keeps two
/// phases for.
struct GrovePreviewAPI: CypressAPI {
    var grove: GroveSpecies = .empty
    /// Makes the species read fail, which is the only way to see screen 08's failure arm without a
    /// broken device (ERRATA E126).
    var fails = false

    /// The `Trees` pill's rows.
    var trees: [GroveEntry] = []
    /// Makes the trees read fail, independently of the species one.
    var treesFail = false
    var groveReads: GroveReadCounter?

    func groveSpecies() async throws -> GroveSpecies {
        if fails { throw APIError.serverError }
        return grove
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
    func grove() async throws -> [GroveEntry] {
        groveReads?.record()
        if treesFail { throw APIError.serverError }
        return trees
    }
    func journal(cursor: String?, limit: Int) async throws -> Page<JournalEntry> { Page(items: []) }
    func claimDevice(deviceUUID: UUID, userID: UUID) async throws {}
    func logHazardRedirect(_ event: HazardRedirectEvent) async throws {}
    func exportLatest(_ format: ExportFormat) async throws -> Data { Data() }
}

// MARK: - Fixtures

/// The seven species SCREENS.md 08 §5 names, with the scientific names the seed carries for them,
/// so `SpeciesTileArtwork` resolves each by genus exactly as it will in the app.
///
/// **The mock does not add up, and this is where it shows.** §3's ring reads `12 of 40 species`
/// while §5's grid draws seven known tiles and two locked. Seven is what is drawn, so seven is what
/// this fixture holds; the ring below therefore reads `7 of 40`. See ERRATA E47.
private enum GroveFixtures {

    static let now = Date(timeIntervalSince1970: 1_753_142_400) // 2025-07-22, 00:00 UTC

    private static func species(
        _ index: Int,
        _ scientific: String,
        _ common: String,
        daysAgo: Int,
        address: String?
    ) -> KnownSpecies {
        KnownSpecies(
            speciesID: UUID(uuidString: String(format: "08000000-0000-4000-8000-%012d", index))!,
            scientificName: scientific,
            commonName: common,
            firstMetAt: now.addingTimeInterval(TimeInterval(-daysAgo * 86_400)),
            firstMetAddress: address
        )
    }

    /// Oldest first, matching the order the grid draws them in.
    static let known: [KnownSpecies] = [
        species(1, "Cupressus macrocarpa", "Monterey Cypress", daysAgo: 400, address: "1200 Great Highway"),
        species(2, "Ginkgo biloba", "Ginkgo", daysAgo: 300, address: "2100 Noriega St"),
        species(3, "Platanus × hispanica", "London Plane", daysAgo: 210, address: "800 Judah St"),
        species(4, "Pittosporum undulatum", "Victorian Box", daysAgo: 1, address: "1450 Noriega St"),
        species(5, "Corymbia ficifolia", "Red Flowering Gum", daysAgo: 120, address: "3300 Taraval St"),
        species(6, "Metrosideros excelsa", "Pōhutukawa", daysAgo: 90, address: nil),
        species(7, "Lophostemon confertus", "Brisbane Box", daysAgo: 40, address: "2500 Vicente St")
    ]

    /// Forty species in the neighborhood — §3's denominator. The first seven are the ones known,
    /// so the intersection is the whole known set.
    static let neighborhoodSpeciesIDs: [UUID] =
        known.map(\.speciesID)
        + (8...40).map { UUID(uuidString: String(format: "08000000-0000-4000-8000-%012d", $0))! }

    static func neighborhood(complete: Bool = true) -> GroveNeighborhood {
        GroveNeighborhood(
            area: .named("Sunset/Parkside"),
            species: Series(items: neighborhoodSpeciesIDs, isComplete: complete)
        )
    }

    static let populated = GroveSpecies(
        neighborhood: neighborhood(),
        known: Series(complete: known)
    )

    /// The same rows, read as a page. Every count disappears; the grid stays, unpadded.
    static let paged = GroveSpecies(
        neighborhood: neighborhood(complete: false),
        known: Series(items: known, isComplete: false)
    )

    /// A device that has contributed nothing. There is no neighborhood to infer and nothing to
    /// count, so the screen is its title, its tabs and its footnote.
    static let empty = GroveSpecies.empty
}

// MARK: - Previews

/// The drawn state: ring, celebration callout, and the 3-up grid with its locked tiles.
#Preview("08 · species you know") {
    NavigationStack {
        GroveView(
            api: GrovePreviewAPI(grove: GroveFixtures.populated),
            now: { GroveFixtures.now },
            onOpenSpecies: { _ in }
        )
    }
    .environment(AppRouter())
}

/// **NOT SPECIFIED** by SCREENS.md; required by BUILD-PLAN §9 M2. The state most devices are in on
/// day one.
#Preview("08 · empty grove") {
    NavigationStack {
        GroveView(api: GrovePreviewAPI(grove: GroveFixtures.empty), now: { GroveFixtures.now })
    }
    .environment(AppRouter())
}

/// The honesty case: the same species, read as a page. No ring, no fraction, no locked padding —
/// only the tiles, which are true whether or not there are more of them (ERRATA E38).
#Preview("08 · read came back a page") {
    NavigationStack {
        GroveView(
            api: GrovePreviewAPI(grove: GroveFixtures.paged),
            now: { GroveFixtures.now },
            onOpenSpecies: { _ in }
        )
    }
    .environment(AppRouter())
}

/// The read that failed. Next to `08 · empty grove` above, which is the picture this used to draw
/// (ERRATA E126) — the two are meant to be looked at together, because the whole point is that they
/// are no longer the same one.
#Preview("08 · read failed") {
    NavigationStack {
        GroveView(api: GrovePreviewAPI(fails: true), now: { GroveFixtures.now })
    }
    .environment(AppRouter())
}

/// Dark. 08 has no specified dark screen (D1–D3 are the only ones), so this preview is the
/// evidence for what the token layer resolves it to rather than a design. See ERRATA E50.
#Preview("08 · dark") {
    NavigationStack {
        GroveView(
            api: GrovePreviewAPI(grove: GroveFixtures.populated),
            now: { GroveFixtures.now },
            onOpenSpecies: { _ in }
        )
    }
    .environment(AppRouter())
    .preferredColorScheme(.dark)
}
#endif
