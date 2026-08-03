import Foundation
import Testing
@testable import Cypress

/// **A row a reader cannot interpret is worse than a row that is not there** (the principle ERRATA
/// E126 states for a screen, applied to a list row) — task #103, ruled in
/// `RULINGS R47`.
///
/// A species the ingest could not read keeps the raw source string as its scientific name, so the
/// name still carries DataSF's `::` separator with an empty scientific half. Those rows reached the
/// map's suggestion list, where `:: Magnolia` rendered under a heading that says "scientific name",
/// beside the real `Magnolia` — one plant, two rows, and one of them addressed to the parser rather
/// than to the reader.
///
/// These assert against the shipped seed on purpose, for the reason `SpeciesSearchTests` gives: a
/// fixture written for the test cannot catch a disagreement between the query and the catalogue.
@Suite("Seed stub naming")
struct SeedStubNamingTests {

    private static func store() async throws -> CypressStore {
        let seedURL = try #require(SeedContractTests.seedURL, "no seed database; set CYPRESS_SEED_PATH")
        return try await CypressStore.inMemory(seedURL: seedURL)
    }

    /// Every species whose scientific name still carries the ingest's unread marker, from the seed.
    private static func unreadableNames() async throws -> [(id: Int, name: String, common: String?)] {
        let store = try await store()
        return try await store.queue.read { connection in
            let sql = """
            SELECT id, scientific_name, common_name
              FROM \(SeedDatabase.schemaName).species
             WHERE scientific_name LIKE ':: %'
             ORDER BY id
            """
            return try connection.prepare(sql).fetchAll { row in
                (
                    id: try row.intIfPresent("id") ?? -1,
                    name: try row.stringIfPresent("scientific_name") ?? "",
                    common: try row.stringIfPresent("common_name")
                )
            }
        }
    }

    private static func search(_ query: String, limit: Int = 100) async throws -> [Species] {
        let store = try await store()
        let schema = try #require(store.seed, "the store opened without a seed attached")
        let queries = SpeciesQueries(schema: schema)
        return try await store.queue.read { connection in
            try queries.search(query: query, limit: limit, connection: connection)
        }
    }

    // MARK: - The precondition, so the two tests below are about something

    /// **Asserts presence.** If the corpus ever stops carrying an unreadable name, the filter and the
    /// tests under it are guarding nothing, and this says so out loud rather than passing quietly.
    ///
    /// Seven trees stand under these five names as of the #103 rebuild; `Tools/build_seed.py`'s swap
    /// removed the other fifty-eight by reading the name the city actually wrote.
    @Test("the catalogue still carries species the ingest could not read")
    func theCatalogueStillCarriesUnreadableNames() async throws {
        let unreadable = try await Self.unreadableNames()
        #expect(!unreadable.isEmpty, "no species carries the ':: ' marker; this suite guards nothing")
        for row in unreadable {
            #expect(row.name.hasPrefix(":: "), "row \(row.id) was selected by a marker it does not carry")
        }
    }

    // MARK: - The cheap predicate is the exact one

    /// **What makes the `LIKE` in `SpeciesQueries.searchSQL()` honest rather than a guess.**
    ///
    /// The query filters on the *shape* of the name because `species_map` carries no index on
    /// `species_id` and the exact question costs a scan there (see the note beside `stubNameMarker`).
    /// This proves the shape and the fact select the same rows in the seed as built, so the cheap
    /// predicate is not quietly narrower than the thing it stands for.
    @Test("the name marker and species_map.is_stub select the same species")
    func theMarkerAndTheProvenanceFlagAgree() async throws {
        let store = try await Self.store()
        let (marked, onlyStub) = try await store.queue.read { connection -> ([Int], [Int]) in
            let seed = SeedDatabase.schemaName
            let markedSQL = """
            SELECT id FROM \(seed).species WHERE scientific_name LIKE ':: %' ORDER BY id
            """
            let onlyStubSQL = """
            SELECT s.id
              FROM \(seed).species s
             WHERE NOT EXISTS (
                       SELECT 1 FROM \(seed).species_map m
                        WHERE m.species_id = s.id AND m.is_stub = 0
                   )
             ORDER BY s.id
            """
            let decode: (SQLiteRow) throws -> Int = { try $0.intIfPresent("id") ?? -1 }
            return (
                try connection.prepare(markedSQL).fetchAll(decode),
                try connection.prepare(onlyStubSQL).fetchAll(decode)
            )
        }
        #expect(
            marked == onlyStub,
            "the ':: ' marker and species_map.is_stub disagree — marked \(marked), stub-only \(onlyStub)"
        )
    }

    // MARK: - The ruling, as an assertion

    /// **The defect, stated as a search.** Each unreadable species is looked up by the very text it
    /// would be found under; the list must come back without it.
    ///
    /// Asserts a fact about the rows, not the phrasing of a row: no result carries the marker.
    @Test("the suggestion list offers no species the ingest could not read")
    func theListOffersNoUnreadableName() async throws {
        let unreadable = try await Self.unreadableNames()
        try #require(!unreadable.isEmpty, "no unreadable species to search for")

        for row in unreadable {
            let term = (row.common?.isEmpty == false ? row.common! : String(row.name.dropFirst(3)))
            let matches = try await Self.search(term)
            let offered = matches.filter { $0.scientificName.hasPrefix(":: ") }
            #expect(
                offered.isEmpty,
                "searching “\(term)” offered \(offered.map(\.scientificName)) — a name addressed to the parser"
            )
        }
    }

    /// **The builder half of #103, from the app's side.** `Arbutus 'Marina'` stood in the catalogue
    /// twice: once properly, as `Hybrid Strawberry Tree`, and once as the stub `:: Arbutus 'Marina'`
    /// minted from a city row whose botanical field was empty. The swap in
    /// `Tools/inventory_adapters.py` merged the second into the first.
    ///
    /// **What this deliberately does not assert.** Not that the plant has one row — it has three
    /// (`Arbutus 'Marina'`, `Arbutus marina`, and `Arbutus ‘Marina’` with typographic quotes), and it
    /// had them before #103 and still does. Collapsing those is a synonymy the sources do not state,
    /// which is the judgment `QSPECIES_NAME_CORRECTIONS` refuses to make; it is recorded in
    /// `ERRATA E208` rather than fixed here. What #103 removed is the
    /// row that was not a name at all, and that is what is asserted.
    /// **This asks the catalogue, not the search, and the difference is the whole point.** Written
    /// first against `search("Marina")`, it passed with the builder's swap reverted and the stub back
    /// in the seed — because the filter ruled on above hides the row from the search, so the
    /// assertion was guarded by the fix it was not testing. A test cannot red-proof the ingest
    /// through a query that exists to hide the ingest's mistakes.
    @Test("the ingest mints no stub beside Arbutus 'Marina', and the real row keeps its name")
    func arbutusMarinaKeptItsName() async throws {
        let store = try await Self.store()
        let (shadows, real) = try await store.queue.read { connection -> ([String], [String]) in
            let seed = SeedDatabase.schemaName
            let name: (SQLiteRow) throws -> String = { try $0.stringIfPresent("scientific_name") ?? "" }
            let common: (SQLiteRow) throws -> String = { try $0.stringIfPresent("common_name") ?? "" }
            let shadowSQL = """
            SELECT scientific_name FROM \(seed).species
             WHERE scientific_name LIKE ':: %Arbutus%' ORDER BY scientific_name
            """
            let realSQL = """
            SELECT common_name FROM \(seed).species WHERE scientific_name = 'Arbutus ''Marina'''
            """
            return (
                try connection.prepare(shadowSQL).fetchAll(name),
                try connection.prepare(realSQL).fetchAll(common)
            )
        }
        #expect(shadows.isEmpty, "the ingest still mints a stub beside Arbutus 'Marina': \(shadows)")
        #expect(
            real == ["Hybrid Strawberry Tree"],
            "the row the stub merged into is not the one the catalogue had: \(real)"
        )
    }
}
