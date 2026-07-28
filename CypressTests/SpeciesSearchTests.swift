import Foundation
import Testing
@testable import Cypress

/// **Typing "cypress" finds the Cypresses** — the defect of task #108, asserted against the seed
/// rather than against a fixture.
///
/// The bar matched a *prefix* of `scientific_name` or `common_name`, so "cypress" matched exactly one
/// of 577 species — `Cypress species / Cupressus spp` — and missed Monterey, Italian, Leyland, Hinoki
/// and Montezuma Cypress, every one of which carries the word in second position. The owner read the
/// three pins that one species had in his viewport as three species, which is the other half of why
/// this looked like a counting bug rather than a matching one.
///
/// Every expectation below names real rows of the shipped seed. That is deliberate: a fixture built
/// for the test could not have caught the original defect, because the original defect was that the
/// query disagreed with the catalogue about what the word "cypress" refers to.
@Suite("Species search")
struct SpeciesSearchTests {

    private static func store() async throws -> CypressStore {
        let seedURL = try #require(SeedContractTests.seedURL, "no seed database; set CYPRESS_SEED_PATH")
        return try await CypressStore.inMemory(seedURL: seedURL)
    }

    private static func search(_ query: String, limit: Int = 100) async throws -> [Species] {
        let store = try await store()
        let schema = try #require(store.seed, "the store opened without a seed attached")
        let queries = SpeciesQueries(schema: schema)
        return try await store.queue.read { connection in
            try queries.search(query: query, limit: limit, connection: connection)
        }
    }

    private static func names(_ species: [Species]) -> [String] {
        species.map(\.commonName)
    }

    // MARK: - The defect

    /// The owner's sentence, as an assertion: "should bring up all Monterey cypress not just cypress
    /// spp". All six of the seed's Cypresses, named.
    @Test("typing cypress finds every Cypress in the catalogue, not just the one called Cypress")
    func cypressFindsEveryCypress() async throws {
        let matches = try await Self.search("cypress")
        let found = Set(Self.names(matches))

        for expected in [
            "Cypress species",      // Cupressus spp — the only one the prefix scan found
            "Monterey Cypress",     // Cupressus macrocarpa
            "Italian Cypress",      // Cupressus sempervirens
            "Leyland Cypress",      // Cupressocyparis leylandii
            "Hinoki cypress",       // Chamaecyparis obtusa — lowercase, so case-insensitively too
            "Montezuma Cypress"     // Taxodium mucronatum — a different genus entirely
        ] {
            #expect(found.contains(expected), "“cypress” did not find \(expected); it found \(found.sorted())")
        }
    }

    /// The rank, in the order the map's status line reads the names out in.
    ///
    /// `Cypress species` is the genus and the only name that *starts* with the word, so it heads the
    /// list; `Monterey Cypress` is the one curated Cypress, so it heads the band below it. Anything
    /// else would put a species nobody asked for above the two the reader most likely meant.
    @Test("a head match outranks a word match, and curation breaks the tie inside a band")
    func cypressIsRankedGenusFirst() async throws {
        let matches = try await Self.search("cypress")
        try #require(matches.count >= 2, "only \(matches.count) Cypresses came back")
        #expect(matches[0].commonName == "Cypress species", "the genus was not first: \(Self.names(matches))")
        #expect(matches[1].commonName == "Monterey Cypress", "the curated Cypress was not second: \(Self.names(matches))")
    }

    /// The case `SpeciesQueries` named as the gap for as long as the scan was a prefix one — "oak"
    /// inside "Coast Live Oak" — plus the interior match that makes the third rank band worth having.
    ///
    /// `Silkoak species` contains the letters *inside* a word. It is a real match and it is drawn,
    /// but it must not outrank a tree somebody searching for "oak" is plausibly looking for.
    @Test("oak reaches Coast Live Oak, and a match inside a word sinks below every word match")
    func oakReachesTheOaksAndRanksSilkoakLast() async throws {
        let matches = try await Self.search("oak")
        let names = Self.names(matches)

        #expect(names.contains("Coast Live Oak"), "“oak” missed Coast Live Oak: \(names)")
        #expect(names.first == "Oak", "the genus Quercus spp was not first: \(names)")

        let silkoak = try #require(names.firstIndex(of: "Silkoak species"), "“oak” missed Silkoak species: \(names)")
        let liveOak = try #require(names.firstIndex(of: "Coast Live Oak"))
        #expect(silkoak > liveOak, "an inside-a-word match outranked a word match: \(names)")
        #expect(silkoak == names.count - 1, "Silkoak species was not last of \(names.count): \(names)")
    }

    /// A word after a hyphen is a word. `Drooping She-Oak` would otherwise sink to the interior band
    /// alongside `Silkoak`, which is a different kind of match: somebody typing "oak" means that one.
    @Test("a hyphen starts a word for ranking, as a space does")
    func aHyphenIsAWordBoundary() async throws {
        let matches = try await Self.search("oak")
        let names = Self.names(matches)
        let sheOak = try #require(
            names.firstIndex(where: { $0.contains("She-Oak") }),
            "“oak” missed Drooping She-Oak: \(names)"
        )
        let silkoak = try #require(names.firstIndex(of: "Silkoak species"))
        #expect(sheOak < silkoak, "a hyphen-started word ranked no better than a match inside a word: \(names)")
    }

    /// Case is ignored on both sides, which is the whole point of an autocomplete field and was true
    /// of the range scan's `COLLATE NOCASE` before it. `LIKE`'s default ASCII case folding is the
    /// same fold, so this is a property being *kept*, not a new one.
    @Test("matching ignores case in the query and in the catalogue")
    func matchingIsCaseInsensitive() async throws {
        let lower = try await Self.search("cypress")
        let upper = try await Self.search("CYPRESS")
        let mixed = try await Self.search("CyPrEsS")
        #expect(Set(lower.map(\.id)) == Set(upper.map(\.id)))
        #expect(Set(lower.map(\.id)) == Set(mixed.map(\.id)))
        // `Hinoki cypress` is stored lowercase; finding it at all proves the catalogue side folds.
        #expect(Self.names(upper).contains("Hinoki cypress"))
    }

    // MARK: - What the reader may type

    /// `%` and `_` are `LIKE`'s wildcards, and a query is user input.
    ///
    /// Unescaped, a lone `%` matches every name in the catalogue: the map would narrow to the first
    /// 100 species for a keystroke that means nothing, and `_` would silently match any character
    /// inside a cultivar name typed with one. Escaped, both are ordinary characters — and no species
    /// name contains either, so both queries correctly find nothing.
    @Test("LIKE's own wildcards are matched literally, not honoured")
    func wildcardsInTheQueryAreEscaped() async throws {
        let percent = try await Self.search("%")
        let underscore = try await Self.search("_")
        let inWord = try await Self.search("cypre%s")
        // The escape character itself, which must escape before the wildcards do.
        let backslash = try await Self.search("\\")

        #expect(percent.isEmpty, "a bare % matched \(percent.count) species; the query is not escaped")
        #expect(underscore.isEmpty, "a bare _ matched \(underscore.count) species; the query is not escaped")
        #expect(inWord.isEmpty, "% acted as a wildcard inside a word, matching \(Self.names(inWord))")
        #expect(backslash.isEmpty)
    }

    @Test("the escaper escapes the wildcards and its own escape character")
    func theEscaperIsCorrect() {
        #expect(SpeciesQueries.escapedForLike("oak") == "oak")
        #expect(SpeciesQueries.escapedForLike("100%") == "100\\%")
        #expect(SpeciesQueries.escapedForLike("a_b") == "a\\_b")
        #expect(SpeciesQueries.escapedForLike("\\") == "\\\\")
        #expect(SpeciesQueries.escapedForLike("\\%") == "\\\\\\%")
    }

    @Test("whitespace-only and empty queries search for nothing rather than for everything")
    func anEmptyQueryMatchesNothing() async throws {
        let empty = try await Self.search("")
        let spaces = try await Self.search("   ")
        let newlines = try await Self.search("\n\t")
        #expect(empty.isEmpty)
        #expect(spaces.isEmpty)
        #expect(newlines.isEmpty)
    }

    @Test("the limit is honoured, and it is a page of the ranking rather than of the table")
    func theLimitTakesTheTopOfTheRanking() async throws {
        let all = try await Self.search("oak", limit: 100)
        let three = try await Self.search("oak", limit: 3)
        try #require(all.count > 3, "“oak” matched only \(all.count) species; it cannot exercise the limit")
        #expect(three.count == 3)
        #expect(three.map(\.id) == Array(all.map(\.id).prefix(3)), "the limit did not take the head of the ranking")
    }

    // MARK: - The cost model

    /// **The gate on the thing that would have made this a worse bug than the one it fixes.**
    ///
    /// A leading `%` normally forfeits an index. It forfeits nothing here, because the range scan it
    /// replaced was already walking both indexes end to end — `COLLATE NOCASE` does not match the
    /// `BINARY` collation the seed's name indexes were built with, so SQLite could never turn the
    /// range into a seek. What is load-bearing is that both branches of the union still ask for
    /// nothing but `id` and one name, so both stay *covering*: the 577-row `species` table, with its
    /// four JSON columns, is touched only for rows that matched.
    ///
    /// This is the same rule `MapQueryPlanTests.groupingQueriesAreCovering` states for the map, over
    /// the statement `SpeciesQueries` actually runs. Add a column to either branch and it fails.
    @Test("the species search walks both name indexes and never scans the species table")
    func searchStaysOnItsCoveringIndexes() async throws {
        let store = try await Self.store()
        let schema = try #require(store.seed, "the store opened without a seed attached")
        let queries = SpeciesQueries(schema: schema)

        try await store.queue.read { connection in
            let steps = try connection.queryPlan(for: queries.searchSQL())
            let plan = steps.joined(separator: " | ")

            #expect(
                plan.contains("COVERING INDEX idx_species_scientific_name"),
                "the scientific-name branch stopped being covered: \(plan)"
            )
            #expect(
                plan.contains("COVERING INDEX idx_species_common_name"),
                "the common-name branch stopped being covered: \(plan)"
            )
            let tableScans = steps.filter { $0.contains("SCAN") && $0.contains("species") && !$0.contains("COVERING INDEX") }
            #expect(
                tableScans.isEmpty,
                "the species search degraded to a table scan: \(tableScans.joined(separator: " | "))"
            )
        }
    }
}
