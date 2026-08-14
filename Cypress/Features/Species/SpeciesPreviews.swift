//
//  SpeciesPreviews.swift
//  Cypress — Features/Species
//
//  Previews for screen 07 and the three species states it has to tell apart, which SCREENS.md draws
//  as one:
//
//  1. a **curated** species — hero, family and habit chips, the recognize-it card, the population
//     cards and the nearby list, which is the page the mock draws;
//  2. an **uncurated** species with a known habit — 529 of the 569 seeded species. Hero, two chips,
//     counts. No recognize-it card, because nobody authored one;
//  3. a species with **unknown leaf retention** — 59 of the 569. Everything the uncurated page has,
//     minus the habit chip, which is the whole phenology surface (D5, ERRATA E9).
//
//  Nothing here is a fabricated species: each fixture carries only fields the seed genuinely has
//  for that kind of row.
//

#if DEBUG
import SwiftUI

// MARK: - Doubles

/// Answers `speciesGuide` from a fixture and refuses everything else. Previews only.
struct SpeciesPreviewAPI: CypressAPI {

    var guide: SpeciesGuide
    /// Set to make the read fail, for the state SCREENS.md does not draw.
    var fails = false

    func speciesGuide(id: UUID, near coordinate: Coordinate?) async throws -> SpeciesGuide {
        if fails { throw APIError.notFound }
        return guide
    }

    func species(id: UUID) async throws -> Species {
        if fails { throw APIError.notFound }
        return guide.species
    }

    func mapContent(in viewport: MapViewport) async throws -> MapContent { .pins([]) }
    func treesNear(_ coordinate: Coordinate, radiusM: Double, limit: Int) async throws -> [NearbyTree] { [] }
    func treeProfile(id: UUID) async throws -> TreeProfile { throw APIError.notFound }
    func addTree(_ draft: TreeDraft) async throws -> Tree { throw APIError.forbidden }
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

enum SpeciesPreviewFixtures {

    /// July, so a species with a spring care note does *not* draw its callout and the one that has
    /// a July window does.
    static let july = Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 21))!
    /// April, inside Jacaranda's authored March–May window — the one restricted care note in the
    /// shipped seed.
    static let april = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 8))!

    // MARK: Species

    /// The curated flagship, with its seeded `id_tips` verbatim from `Fixtures/species/curated.yaml`.
    ///
    /// The scientific name is `Cupressus macrocarpa`, which is what the seed carries and what GBIF
    /// resolved; SCREENS.md 07 writes `Hesperocyparis macrocarpa`. See ERRATA (E43).
    static let montereyCypress = try! Species(
        id: UUID(uuidString: "F909A9EE-939C-5933-8220-66BB56D0C923")!,
        scientificName: "Cupressus macrocarpa",
        commonName: "Monterey Cypress",
        family: "Cupressaceae",
        leafRetention: .evergreen,
        idTips: [
            IDTip(icon: "leaf", text: "Foliage is blunt scales pressed tight to the twig, not needles, and smells lemony when crushed."),
            IDTip(icon: "bark", text: "Dark grey to red-brown bark, fibrous and rough with irregular furrows."),
            IDTip(icon: "cone", text: "Round to elliptical cones an inch or so long that take two seasons to ripen.")
        ],
        curated: true
    )

    /// The one seeded species with a care note whose window is *not* the whole year, so it is the
    /// only one that can produce 07 §4's `In <month>:` callout at all.
    static let jacaranda = try! Species(
        id: UUID(uuidString: "24D6772A-B8BD-5A70-B823-239398828E1E")!,
        scientificName: "Jacaranda mimosifolia",
        commonName: "Jacaranda",
        family: "Bignoniaceae",
        leafRetention: .semiDeciduous,
        idTips: [
            IDTip(icon: "flower", text: "Trumpet-shaped violet-blue flowers in dense clusters, dropping a carpet under the tree."),
            IDTip(icon: "leaf", text: "Twice-divided fern-like leaves, opposite along the twig.")
        ],
        seasonal: SeasonalCalendar(bloomMonths: [5, 6]),
        careNotes: [
            CareNote(
                monthRange: MonthRange(start: 1, end: 12)!,
                text: "An uneven performer here. Prefers heat, wind protection and good drainage."
            ),
            CareNote(monthRange: MonthRange(start: 3, end: 5)!, text: "Expect leaf drop in spring.")
        ],
        curated: true
    )

    /// One of the 529 the content pipeline never reached: a habit, a family, and nothing authored.
    static let brushCherry = try! Species(
        id: UUID(uuidString: "3B0A1C55-0000-4000-8000-000000000701")!,
        scientificName: "Syzygium paniculatum",
        commonName: "Brush Cherry",
        family: "Myrtaceae",
        leafRetention: .evergreen
    )

    /// One of the 59 nobody sourced a habit for. **No phenology surface at all** — the page draws
    /// its family chip and stops (ERRATA E9). Every field here is exactly what the seed row holds.
    static let maple = try! Species(
        id: UUID(uuidString: "3B0A1C55-0000-4000-8000-000000000702")!,
        scientificName: "Acer spp",
        commonName: "Maple",
        family: "Sapindaceae",
        leafRetention: nil
    )

    // MARK: Population

    static let sunsetTrees = Series(complete: [
        NearbySpeciesTree(
            treeID: UUID(uuidString: "3B0A1C55-0000-4000-8000-0000000007A1")!,
            title: "1450 Great Highway",
            distanceM: 220,
            photoCount: 214,
            vitality: .thriving
        ),
        NearbySpeciesTree(
            treeID: UUID(uuidString: "3B0A1C55-0000-4000-8000-0000000007A2")!,
            title: "2401 Sunset Blvd",
            distanceM: 400,
            photoCount: 12,
            vitality: .good
        )
    ])

    /// What a fresh install actually holds: inventoried trees nobody has photographed or checked in
    /// on, so the rows carry a title and a distance and no sub-line.
    static let untouchedTrees = Series(complete: [
        NearbySpeciesTree(
            treeID: UUID(uuidString: "3B0A1C55-0000-4000-8000-0000000007B1")!,
            title: "1450 Great Highway",
            distanceM: 220,
            photoCount: 0,
            vitality: nil
        )
    ])

    @MainActor
    static func view(
        species: Species,
        cityTreeCount: Int? = 1_923,
        nearYou: SpeciesNeighborhoodCount? = SpeciesNeighborhoodCount(area: .named("Sunset/Parkside"), count: 61),
        nearby: Series<NearbySpeciesTree> = sunsetTrees,
        now: Date = july,
        fails: Bool = false
    ) -> SpeciesView {
        SpeciesView(
            speciesID: species.id,
            api: SpeciesPreviewAPI(
                guide: SpeciesGuide(
                    species: species,
                    cityTreeCount: cityTreeCount,
                    nearYou: nearYou,
                    nearby: nearby
                ),
                fails: fails
            ),
            now: { now }
        )
    }
}

// MARK: - Previews

/// The page SCREENS.md 07 draws, as far as the record supports it.
#Preview("07 · curated species") {
    NavigationStack { SpeciesPreviewFixtures.view(species: SpeciesPreviewFixtures.montereyCypress) }
        .environment(AppRouter())
}

/// The one seeded species that can produce 07 §4's seasonal callout, in the month its authored
/// window covers.
#Preview("07 · this month’s note") {
    NavigationStack {
        SpeciesPreviewFixtures.view(
            species: SpeciesPreviewFixtures.jacaranda,
            now: SpeciesPreviewFixtures.april
        )
    }
    .environment(AppRouter())
}

/// The same species in July, outside its window: no callout, and no invented one.
#Preview("07 · out of its window") {
    NavigationStack { SpeciesPreviewFixtures.view(species: SpeciesPreviewFixtures.jacaranda) }
        .environment(AppRouter())
}

/// 529 of 569. Name, family, habit, counts — no recognize-it card, because nothing was authored.
#Preview("07 · uncurated species") {
    NavigationStack { SpeciesPreviewFixtures.view(species: SpeciesPreviewFixtures.brushCherry) }
        .environment(AppRouter())
}

/// 59 of 569. The same page **minus the habit chip**: no phenology surface at all (D5, ERRATA E9).
#Preview("07 · unknown leaf retention") {
    NavigationStack { SpeciesPreviewFixtures.view(species: SpeciesPreviewFixtures.maple) }
        .environment(AppRouter())
}

/// No fix: no `Near you` card and no nearby list, because neither has a subject.
#Preview("07 · no location") {
    NavigationStack {
        SpeciesPreviewFixtures.view(
            species: SpeciesPreviewFixtures.montereyCypress,
            nearYou: nil,
            nearby: .empty
        )
    }
    .environment(AppRouter())
}

/// A fresh install: real trees, nothing contributed to them yet, so the rows carry no sub-line.
#Preview("07 · nothing contributed yet") {
    NavigationStack {
        SpeciesPreviewFixtures.view(
            species: SpeciesPreviewFixtures.montereyCypress,
            nearby: SpeciesPreviewFixtures.untouchedTrees
        )
    }
    .environment(AppRouter())
}

/// **NOT SPECIFIED** by SCREENS.md 07 — dark has no row for this screen (ERRATA E8). What the
/// tokens resolve to is what this shows; nothing here was designed.
#Preview("07 · dark, unspecified") {
    NavigationStack { SpeciesPreviewFixtures.view(species: SpeciesPreviewFixtures.montereyCypress) }
        .environment(AppRouter())
        .preferredColorScheme(.dark)
}

/// **NOT SPECIFIED.** The read failed and the page says only that.
#Preview("07 · read failed") {
    NavigationStack {
        SpeciesPreviewFixtures.view(species: SpeciesPreviewFixtures.montereyCypress, fails: true)
    }
    .environment(AppRouter())
}
#endif
