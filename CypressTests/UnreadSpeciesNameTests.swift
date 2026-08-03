import Foundation
import Testing
@testable import Cypress

/// **The seven trees that quoted the parser at a reader** — task #185, ruled in
/// `RULINGS R54`.
///
/// DataSF publishes species in one column as `Scientific name :: Common name`. On five rows of the
/// shipped seed the scientific half is empty, and `Tools/inventory_adapters.py`'s `parse_qspecies`
/// classifies those `stub` and stores **the whole raw string** in `scientific_name` — `:: Magnolia`,
/// `:: 9662`. `RULINGS R47` took them out of the suggestion list and out of the species picker on
/// E126's principle, and recorded in the same breath what that fix could not reach: a filter over
/// `SpeciesQueries.searchSQL()` cannot omit a tree's own species from its own page. So seven trees
/// went on drawing `:: Magnolia` in the slot labelled by position as the Latin name, and this is the
/// suite for the copy that replaced it.
///
/// **These read the shipped seed rather than a fixture**, for `SeedStubNamingTests`' reason: a
/// `Species` written for a test cannot catch a disagreement between the screens and the catalogue,
/// and the whole subject here is a value the catalogue produced.
@Suite("Unread species names")
struct UnreadSpeciesNameTests {

    // MARK: - Reading the catalogue

    private static func store() async throws -> CypressStore {
        let seedURL = try #require(SeedContractTests.seedURL, "no seed database; set CYPRESS_SEED_PATH")
        return try await CypressStore.inMemory(seedURL: seedURL)
    }

    /// Every species whose scientific name the ingest never read, decoded by the app's **own**
    /// decoder — `SpeciesQueries.species(id:)`, the read screen 07 runs — rather than by SQL written
    /// here. What the screens are handed is what is asserted.
    private static func unreadSpecies() async throws -> [Species] {
        let store = try await store()
        let schema = try #require(store.seed, "the store opened without a seed attached")
        let queries = SpeciesQueries(schema: schema)
        return try await store.queue.read { connection in
            let sql = """
            SELECT \(schema.speciesIdentityColumn) AS species_uuid
              FROM \(SeedDatabase.schemaName).species
             WHERE scientific_name LIKE ':: %'
             ORDER BY id
            """
            let ids = try connection.prepare(sql).fetchAll { try $0.uuidIfPresent("species_uuid") }
            return try ids.compactMap { id -> Species? in
                guard let id else { return nil }
                return try queries.species(id: id, connection: connection)
            }
        }
    }

    /// How many standing records each unread name covers, and how many there are in total.
    private static func treeCounts() async throws -> (perSpecies: [String: Int], total: Int) {
        let store = try await store()
        return try await store.queue.read { connection in
            let sql = """
            SELECT s.scientific_name AS name, count(*) AS n
              FROM \(SeedDatabase.schemaName).trees t
              JOIN \(SeedDatabase.schemaName).species s ON s.id = t.species_current
             WHERE s.scientific_name LIKE ':: %'
               AND t.deleted_at IS NULL
             GROUP BY s.scientific_name
            """
            let rows = try connection.prepare(sql).fetchAll { row in
                (name: try row.stringIfPresent("name") ?? "", n: try row.intIfPresent("n") ?? 0)
            }
            return (
                Dictionary(uniqueKeysWithValues: rows.map { ($0.name, $0.n) }),
                rows.reduce(0) { $0 + $1.n }
            )
        }
    }

    // MARK: - Fixtures for the two screens

    private static let treeID = UUID(uuidString: "7E000000-0000-4000-8000-000001850001")!

    private static func tree(address: String? = "3555 20th St") -> Tree {
        Tree(
            id: treeID,
            externalRef: "236625",
            source: .cityImport,
            coordinate: Coordinate(latitude: 37.758645, longitude: -122.424929),
            address: address,
            status: .alive,
            verificationState: .cityRecord
        )
    }

    private static func profile(species: Species?) -> TreeProfile {
        TreeProfile(tree: tree(), species: species)
    }

    private static func treePage(_ species: Species?) -> TreeProfilePresentation {
        TreeProfilePresentation(profile: profile(species: species))
    }

    private static func speciesPage(_ species: Species, cityTreeCount: Int? = 3) -> SpeciesPresentation {
        SpeciesPresentation(
            guide: SpeciesGuide(species: species, cityTreeCount: cityTreeCount, nearYou: nil, nearby: .empty),
            month: 7
        )
    }

    // MARK: - The precondition

    /// **Asserts presence.** Every number in the ruling is re-measured here, so a rebuild that
    /// changes the corpus fails a test rather than quietly leaving the copy addressed to nobody.
    ///
    /// The counts are the ones stated in `RULINGS R54`; the shape
    /// assertion is the one the copy depends on and is not in R47: on every one of these rows the
    /// *common* half parsed and is the city's own word, which is what there is to quote.
    @Test("the catalogue still carries names the ingest could not read, each with a city wording")
    func theCatalogueStillCarriesUnreadNames() async throws {
        let species = try await Self.unreadSpecies()
        let counts = try await Self.treeCounts()

        #expect(species.count == 5, "the seed carries \(species.count) unread names, not 5")
        #expect(counts.total == 7, "the unread names stand over \(counts.total) trees, not 7")
        #expect(
            Set(species.map(\.scientificName)) == Set([
                ":: Magnolia", ":: 9662", ":: Chitalpatashkentensis",
                ":: Magnolia Little Gem", ":: Podocarpus Gracilor"
            ]),
            "the unread names are not the five the ruling was written about: \(species.map(\.scientificName))"
        )
        #expect(counts.perSpecies[":: Magnolia"] == 3, "':: Magnolia' no longer stands over three trees")

        for row in species {
            #expect(row.scientificNameIsUnread, "\(row.scientificName) was selected by a marker it does not carry")
            #expect(
                row.cityWordingForUnreadName != nil,
                "\(row.scientificName) has no city wording to quote, so neither sentence can be written"
            )
        }
    }

    // MARK: - The ruling, as assertions

    /// **The defect, stated over the real rows.** Every string either screen would draw is checked
    /// for the marker, including the two sentences written to replace it.
    ///
    /// Asserts a fact — no drawn string contains the raw source string's separator — rather than the
    /// phrasing of either sentence, so rewording the copy leaves this test standing.
    @Test("no string either screen draws carries the ingest's marker")
    func neitherScreenDrawsTheMarker() async throws {
        let species = try await Self.unreadSpecies()
        try #require(!species.isEmpty, "no unread species to render")

        for row in species {
            let marker = Species.unreadScientificNameMarker
            let tree = Self.treePage(row)
            let page = Self.speciesPage(row)

            let drawn: [String] = [
                tree.title,
                tree.subtitle,
                tree.unreadSpeciesNote ?? "",
                page.commonName,
                page.scientificName ?? "",
                page.unreadNameNote ?? ""
            ]
            for text in drawn {
                #expect(
                    !text.contains(marker),
                    "“\(text)” carries the ingest's marker on a screen a reader can open"
                )
            }
        }
    }

    /// **The Latin line is gone from both screens, and something says why.**
    ///
    /// The pair matters more than either half: R47's argument against rendering these honestly is
    /// that a `:: ` prefix is unreadable in the field a reader uses to decide whether this is the
    /// tree they meant, and E126's is that an uninterpretable state is worse than one not drawn. A
    /// silently missing line satisfies neither, so absence and account are asserted together.
    @Test("the unread name is withheld and accounted for on both screens")
    func bothScreensWithholdAndAccount() async throws {
        let species = try await Self.unreadSpecies()

        for row in species {
            let wording = try #require(row.cityWordingForUnreadName)
            let page = Self.speciesPage(row)
            #expect(page.scientificName == nil, "07 still draws a Latin line for \(row.scientificName)")
            let speciesNote = try #require(page.unreadNameNote, "07 drops the Latin line and says nothing")
            #expect(speciesNote.contains(wording), "07's sentence does not quote the city's wording")

            let tree = Self.treePage(row)
            let treeNote = try #require(tree.unreadSpeciesNote, "03 says nothing about the missing name")
            #expect(treeNote.contains(wording), "03's sentence does not quote the city's wording")
            #expect(
                !tree.subtitle.contains(row.scientificName),
                "03's subtitle still prints the unread name: \(tree.subtitle)"
            )
        }
    }

    /// **The map card and the "what tree is this?" shortlist withhold it too**, and neither gets a
    /// sentence — both are `·`-joined preview lines that already drop any clause they have no fact
    /// for, and both open a profile that carries the whole account.
    @Test("the map card and the shortlist drop the unread name without standing anything in for it")
    func previewSurfacesDropTheClause() async throws {
        let species = try await Self.unreadSpecies()

        for row in species {
            let subject = MapCardSubject(
                pin: TreePin(
                    id: Self.treeID,
                    coordinate: Self.tree().coordinate,
                    status: .alive,
                    source: .cityImport,
                    verificationState: .cityRecord,
                    speciesID: row.id
                ),
                profile: Self.profile(species: row)
            )
            #expect(
                subject.scientificName == nil,
                "the map card still prints \(row.scientificName) under a pin"
            )

            let candidate = VisitCandidate(
                nearby: NearbyTree(
                    tree: Self.tree(),
                    distanceM: 6,
                    speciesScientificName: row.scientificName,
                    speciesCommonName: row.commonName,
                    tell: nil
                )
            )
            #expect(
                candidate.latinName == nil,
                "the shortlist still prints \(row.scientificName) beside the city's own word for it"
            )
        }
    }

    // MARK: - The two states this must not disturb

    /// A species the ingest **did** read keeps its Latin line and gets no sentence. Without this the
    /// suite above passes on a build that simply never draws a scientific name.
    @Test("a species with a read name keeps its Latin line and gets no sentence")
    func aReadNameIsUntouched() throws {
        let species = try Species(
            scientificName: "Cupressus macrocarpa",
            commonName: "Monterey Cypress",
            family: "Cupressaceae",
            leafRetention: .evergreen
        )
        let page = Self.speciesPage(species)
        #expect(page.scientificName == "Cupressus macrocarpa")
        #expect(page.unreadNameNote == nil)

        let tree = Self.treePage(species)
        #expect(tree.subtitle.contains("Cupressus macrocarpa"))
        #expect(tree.unreadSpeciesNote == nil)
    }

    /// A record with **no species at all** is a different state and keeps its own rendering. There
    /// is no wording to quote and no line that went missing, so the sentence would be describing an
    /// absence the screen never claimed to fill.
    @Test("a tree with no species says nothing about an unread name")
    func noSpeciesIsNotAnUnreadName() {
        let tree = Self.treePage(nil)
        #expect(tree.unreadSpeciesNote == nil)
        #expect(tree.title == "3555 20th St", "the no-species title rule moved")
    }
}
