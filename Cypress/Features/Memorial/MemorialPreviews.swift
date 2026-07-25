//
//  MemorialPreviews.swift
//  Cypress — Features/Memorial
//
//  Previews for screen 19.
//
//  **Every one of these is a fixture, and that is a finding rather than a convenience.** The shipped
//  seed contains 182,791 `alive` trees and 12,518 `vacant_site` rows and **no removed tree at all**,
//  so screen 01's gray dash-marked memorial pins have nothing behind them on any device today and
//  this screen is unreachable from real data. Recorded in ERRATA.
//
//  The drawn state and the same screen with the removal date withheld are both previewed, because
//  the second is what the app actually renders: BUILD-PLAN §4 has no `removed_at` column, so every
//  sentence that needs the date is currently the shorter one.
//

#if DEBUG
import SwiftUI

// MARK: - Double

/// Hands back one profile and refuses everything else. Previews only.
struct MemorialPreviewAPI: CypressAPI {
    var profile: TreeProfile

    func treeProfile(id: UUID) async throws -> TreeProfile { profile }

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

// MARK: - Fixtures

/// SCREENS.md 19's own tree, assembled from real record types.
///
/// Judah Street Gum is not in the seed and neither is any other removed tree, so this is the mock's
/// tree built by hand — which is also the only way to see the drawn state at all.
enum MemorialFixtures {

    static let now = Date(timeIntervalSince1970: 1_784_505_600) // 2026-07-20

    static func id(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "19000000-0000-4000-8000-%012d", index))!
    }

    static func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        return formatter.date(from: iso) ?? now
    }

    static let treeID = id(1)
    static let speciesID = id(2)

    static let species = try! Species(
        id: speciesID,
        scientificName: "Corymbia ficifolia",
        commonName: "Red Flowering Gum",
        family: "Myrtaceae",
        leafRetention: .evergreen
    )

    static let tree = Tree(
        id: treeID,
        externalRef: "088-21",
        source: .cityImport,
        coordinate: Coordinate(latitude: 37.7605, longitude: -122.4931),
        address: "1450 Judah St",
        siteType: "Sidewalk: Curb side : Cutout",
        status: .removed,
        speciesCurrentID: speciesID,
        plantedYear: 2003,
        verificationState: .cityRecord
    )

    static let name = TreeName(
        id: id(3),
        treeID: treeID,
        name: "Judah Street Gum",
        givenBy: nil
    )

    /// 86 photographs across the tree's recorded life, so the hero pill has a whole series behind
    /// it. Their contents do not matter here; their dates and their count do.
    static let photos: [Photo] = (0..<86).map { index in
        Photo(
            id: id(1_000 + index),
            treeID: treeID,
            shotType: .fullTree,
            capturedAt: date(String(format: "%04d-%02d-15", 2019 + index / 12, index % 12 + 1))
        )
    }

    static let visit = Visit(
        id: id(20),
        treeID: treeID,
        attribution: Attribution(userID: id(90), deviceID: id(99)),
        note: "The reddest bloom on the block, every January",
        capturedAt: date("2026-01-18")
    )

    /// The check-in the mock draws: vitality 2, and made by an org steward, which is the column that
    /// earns the `a steward confirmed the decline` clause.
    static let observation = TreeObservation(
        id: id(30),
        treeID: treeID,
        attribution: Attribution(userID: id(91), deviceID: id(99)),
        capturedAt: date("2026-03-04"),
        vitality: .poor,
        verificationState: .orgVerified
    )

    /// Three people with two contributions each — A8's floor exactly, so `six people came to know
    /// it` becomes `three` and the clause renders at all.
    static let careEvents: [CareEvent] = (0..<3).flatMap { person in
        (0..<2).map { visit in
            CareEvent(
                id: id(40 + person * 10 + visit),
                treeID: treeID,
                attribution: Attribution(userID: id(90 + person), deviceID: id(99)),
                capturedAt: date("2025-0\(visit + 5)-12"),
                actions: [.watered]
            )
        }
    }

    static var profile: TreeProfile {
        TreeProfile(
            tree: tree,
            activeName: name,
            species: species,
            neighborhoodName: "Sunset/Parkside",
            latestObservation: observation,
            observations: Series(complete: [observation]),
            photos: Series(complete: photos),
            visits: Series(complete: [visit]),
            careEvents: Series(complete: careEvents),
            ownPhotoIDs: Set(photos.map(\.id))
        )
    }

    /// A removed tree nobody photographed or visited — the common case once the weekly diff starts
    /// marking rows removed, since a tree with *no* community activity is exactly the one BUILD-PLAN
    /// §7 removes without opening a flag.
    static var bare: TreeProfile {
        TreeProfile(tree: tree, activeName: nil, species: species, neighborhoodName: "Sunset/Parkside")
    }

    /// The photo timeline as a *page* rather than a series — the hero pill's two claims are about
    /// the whole of it, so it renders nothing (ERRATA E38).
    static var paged: TreeProfile {
        TreeProfile(
            tree: tree,
            activeName: name,
            species: species,
            latestObservation: observation,
            observations: Series(items: [observation], isComplete: false),
            photos: Series(items: Array(photos.prefix(30)), isComplete: false),
            visits: Series(complete: [visit]),
            careEvents: Series(items: careEvents, isComplete: false),
            ownPhotoIDs: Set(photos.map(\.id))
        )
    }

    /// What SCREENS.md draws, which needs a removal date the schema has no column for.
    static let removedInMay = MemorialFacts(removedAt: date("2026-05-11"))
}

// MARK: - Previews

/// **What the app renders today.** No `removed_at` column exists, so the banner loses its date, the
/// identity line loses its `2003–2026`, the `On record` card goes with it, and the city-record row
/// at the foot of the timeline has no moment to sit at. Everything else is the drawn screen.
#Preview("19 · memorial (as built)") {
    MemorialScreen(
        presentation: MemorialPresentation(
            profile: MemorialFixtures.profile,
            now: MemorialFixtures.now
        ),
        onBack: {}
    )
}

/// The drawn state, with the removal date supplied by hand — what the screen looks like the day a
/// column or a confirmed review flag can answer for it.
#Preview("19 · memorial (with a removal date)") {
    MemorialScreen(
        presentation: MemorialPresentation(
            profile: MemorialFixtures.profile,
            facts: MemorialFixtures.removedInMay,
            now: MemorialFixtures.now
        ),
        onBack: {}
    )
}

/// A removed tree nobody photographed. Hero pill and eyebrow gone, timeline gone, stat grid down to
/// the city's own reference — and the banner, which is the one thing this screen always has to say.
#Preview("19 · nothing was recorded") {
    MemorialScreen(
        presentation: MemorialPresentation(
            profile: MemorialFixtures.bare,
            facts: MemorialFixtures.removedInMay,
            now: MemorialFixtures.now
        ),
        onBack: {}
    )
}

/// The photo series read as a page. `86 photos · 2019–2026` cannot be said about thirty rows, so it
/// is not said, and `three people came to know it` goes with the partial care series.
#Preview("19 · a page, not a series") {
    MemorialScreen(
        presentation: MemorialPresentation(
            profile: MemorialFixtures.paged,
            facts: MemorialFixtures.removedInMay,
            now: MemorialFixtures.now
        ),
        onBack: {}
    )
}

/// The whole feature against a double, so the read and the `isMemorial` gate run rather than being
/// staged.
#Preview("19 · live") {
    MemorialView(
        treeID: MemorialFixtures.treeID,
        api: MemorialPreviewAPI(profile: MemorialFixtures.profile),
        now: { MemorialFixtures.now },
        onBack: {}
    )
}

/// The gate itself: the same screen opened on a tree that is not removed.
#Preview("19 · not a memorial") {
    MemorialView(
        treeID: MemorialFixtures.treeID,
        api: MemorialPreviewAPI(
            profile: TreeProfile(
                tree: Tree(
                    id: MemorialFixtures.treeID,
                    source: .cityImport,
                    coordinate: Coordinate(latitude: 37.76, longitude: -122.49),
                    status: .alive
                )
            )
        ),
        now: { MemorialFixtures.now },
        onBack: {}
    )
}

/// Dark. 19 has no specified dark screen (ERRATA E8), so this is evidence of what the token layer
/// resolves the desaturated hero and the memorial banner to rather than a design.
#Preview("19 · dark") {
    MemorialScreen(
        presentation: MemorialPresentation(
            profile: MemorialFixtures.profile,
            facts: MemorialFixtures.removedInMay,
            now: MemorialFixtures.now
        ),
        onBack: {}
    )
    .preferredColorScheme(.dark)
}
#endif
