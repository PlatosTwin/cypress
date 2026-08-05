import Foundation
import Testing
@testable import Cypress

/// **The half of ERRATA E165 that was still open**: a typo missed, and so did a name the catalog
/// spells differently.
///
/// E165 fixed prefix-matching by matching a substring, and said plainly what that still was not —
/// "it does not tolerate a typo and it does not match across word order … that remains
/// `Tools/build_seed.py`'s to add rather than the client's to fake at launch". `seed.species_trigrams`
/// is that addition, and this suite is what holds it to the two cases E165 named.
///
/// ── Why these tests name real rows of the shipped seed ───────────────────────────────────────
/// The same reason `SpeciesSearchTests` does: the defect was that the query disagreed with the
/// *catalog* about what a typed word refers to, and a fixture built for the test cannot disagree
/// with itself. `Liquidambar` and `Sweet Gum` are not illustrations here, they are the evidence.
///
/// The one thing asserted against a built fixture instead is the **fallback**, because the fact
/// under test is the absence of a table and the shipped seed has it. Those two tests build the same
/// two-species file twice, differing only in whether `species_trigrams` exists, so the flag is the
/// only variable.
@Suite("Species search — trigram similarity (E165)")
struct SpeciesTrigramTests {

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

    // MARK: - The two misses E165 named

    /// **A typo.** `liquidamber` for `Liquidambar` — an `e` for the `a`, the commonest misspelling
    /// of the genus and one that the substring match cannot reach by construction, because the
    /// typed string is not a substring of any name in the catalog.
    ///
    /// All four Liquidambars share 9 of the query's 12 trigrams (0.75), which is what carries them
    /// over the 0.6 bar.
    @Test("a misspelled genus still finds the species (E165: “a typo misses”)")
    func aTypoStillFindsTheSpecies() async throws {
        let matches = try await Self.search("liquidamber")
        let found = Set(matches.map(\.scientificName))

        #expect(
            found.contains("Liquidambar styraciflua"),
            "“liquidamber” did not reach Liquidambar styraciflua; it found \(found.sorted())"
        )
        #expect(
            found.contains("Liquidambar orientalis"),
            "“liquidamber” reached only some of the genus: \(found.sorted())"
        )
    }

    /// **An alternate spelling.** The catalog spells the same tree three ways — `American Sweet
    /// Gum`, `Chinese Sweet Gum`, and `Roundleaf sweetgum` — so a reader typing the closed-up form
    /// used to find exactly the one row that happened to share their spelling, and none of the
    /// others. That is E165's "a name the catalog spells differently", and it is a real property of
    /// this seed rather than a hypothetical.
    @Test("a closed-up spelling reaches the species the catalog spells open (E165)")
    func anAlternateSpellingStillFindsTheSpecies() async throws {
        let matches = try await Self.search("sweetgum")
        let found = Set(matches.map(\.scientificName))

        // The row whose spelling matches literally — the only one the substring match ever found.
        #expect(found.contains("Liquidambar styraciflua 'Rotundiloba'"))
        // The rows it could not reach, which are the point.
        #expect(
            found.contains("Liquidambar styraciflua"),
            "“sweetgum” missed American Sweet Gum, which is the whole case: \(found.sorted())"
        )
        #expect(
            found.contains("Liquidambar formosana"),
            "“sweetgum” missed Chinese Sweet Gum: \(found.sorted())"
        )
    }

    /// Two typos, one in each word, and the answer is still the tree the owner was asking about in
    /// the report that opened E165.
    ///
    /// This is the case that needs the trigram to straddle the space: `y c` is a trigram of
    /// `Monterey Cypress` and of `monteray cypres` alike, and it is shared *because* the words are
    /// adjacent. A per-word index would not have it.
    @Test("a query misspelled in both words still reaches Monterey Cypress")
    func twoTyposStillReachTheTree() async throws {
        let matches = try await Self.search("monteray cypres")
        #expect(
            Self.names(matches).contains("Monterey Cypress"),
            "“monteray cypres” found \(Self.names(matches))"
        )
    }

    // MARK: - What must not move

    /// **The control, and the reason the bar is 0.6 rather than 0.5.**
    ///
    /// "cypress" already had a correct and complete answer, and `SpeciesSearchTests` pins its exact
    /// head — genus first, the curated Monterey Cypress second. The similarity pass must therefore
    /// add *nothing* to it. Measured at 0.5 it adds `Empress Tree`, `Cupressus arizonica` and
    /// `Cupressus species`; at 0.6 it adds nothing, which is what this asserts.
    @Test("a query the substring match already answered gains nothing, and keeps its ranking")
    func anAnsweredQueryIsUntouched() async throws {
        let matches = try await Self.search("cypress")
        let names = Self.names(matches)

        #expect(names.first == "Cypress species", "the genus stopped heading the list: \(names)")
        #expect(names[1] == "Monterey Cypress", "the curated Cypress stopped being second: \(names)")
        // Every name returned carries the typed word. Nothing arrived by similarity alone.
        for name in names {
            #expect(
                name.lowercased().contains("cypress"),
                "the similarity pass admitted “\(name)”, which does not contain the query: \(names)"
            )
        }
    }

    /// An exact scientific name returns that species at the head, not buried under near misses.
    @Test("an exact name still ranks first")
    func anExactNameRanksFirst() async throws {
        let matches = try await Self.search("Liquidambar styraciflua")
        let first = try #require(matches.first, "an exact scientific name found nothing")
        #expect(
            first.scientificName == "Liquidambar styraciflua",
            "an exact name did not rank first; got \(first.scientificName)"
        )
    }

    /// The similarity pass never runs for a query this short, so `oak` — whose complete ranking
    /// `SpeciesSearchTests` pins down to which species is *last* — cannot be reordered by anything
    /// the catalog gains. Asserted as the fact it is, over the real seed.
    @Test("a query under four characters is answered by the substring match alone")
    func aShortQueryDoesNotReachTheSimilarityPass() async throws {
        let matches = try await Self.search("oak")
        for species in matches {
            let carriesIt = species.commonName.lowercased().contains("oak")
                || species.scientificName.lowercased().contains("oak")
            #expect(
                carriesIt,
                """
                “oak” returned \(species.commonName), which does not contain it — the similarity \
                pass ran on a three-character query
                """
            )
        }
    }

    // MARK: - The fallback, on a file that has no index

    /// **A city file published at seed schema 14 has no `species_trigrams`, and must still search.**
    ///
    /// R37.3 makes this an ordinary session rather than an edge case: the bundled seed and a
    /// downloaded city are two different generations at the same time, so the app can be reading an
    /// s15 bundle and an s14 San Jose at once. The read layer asks the file what it carries
    /// (`SeedSchema.hasSpeciesTrigrams`) rather than trusting a version integer.
    ///
    /// What the older file must do is *degrade*, not fail: the substring match E165 shipped, with
    /// no error and no empty result where it used to answer.
    @Test("a seed with no trigram index still searches, by substring, without error")
    func aLegacySeedFallsBackToSubstring() async throws {
        let url = try Self.miniSeed(withTrigrams: false)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = try await CypressStore.inMemory(seedURL: url)
        let schema = try #require(store.seed)
        #expect(!schema.hasSpeciesTrigrams, "the fixture was built with the index after all")

        let queries = SpeciesQueries(schema: schema)
        let (substringHit, typo) = try await store.queue.read { connection in
            (
                try queries.search(query: "Liquidambar", limit: 100, connection: connection),
                try queries.search(query: "liquidamber", limit: 100, connection: connection)
            )
        }

        // The behaviour E165 shipped, intact.
        #expect(
            substringHit.map(\.scientificName) == ["Liquidambar styraciflua"],
            "the substring match stopped working on a legacy seed: \(substringHit.map(\.scientificName))"
        )
        // And the typo finds nothing — which is the old behaviour, correctly, rather than a crash.
        #expect(typo.isEmpty, "a seed with no index somehow answered a typo: \(typo.map(\.scientificName))")
    }

    /// The same two species, the same query, the same code — and the index is the only difference.
    ///
    /// Paired with the test above this is what proves `hasSpeciesTrigrams` is the switch: if the
    /// typo were being answered by something else, this pair could not disagree.
    @Test("the same fixture with the index answers the typo the legacy one cannot")
    func theIndexIsTheOnlyDifference() async throws {
        let url = try Self.miniSeed(withTrigrams: true)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = try await CypressStore.inMemory(seedURL: url)
        let schema = try #require(store.seed)
        #expect(schema.hasSpeciesTrigrams, "the fixture was built without the index")

        let queries = SpeciesQueries(schema: schema)
        let typo = try await store.queue.read { connection in
            try queries.search(query: "liquidamber", limit: 100, connection: connection)
        }
        #expect(
            typo.map(\.scientificName) == ["Liquidambar styraciflua"],
            "the indexed fixture did not answer the typo: \(typo.map(\.scientificName))"
        )
    }

    // MARK: - The scheme itself

    /// **`Tools/build_seed.py` writes the index and this file reads it, so the two trigram
    /// implementations have to agree character for character.**
    ///
    /// A drift between them does not throw and does not fail a build — a trigram spelled slightly
    /// differently on the query side simply never joins, and the search quietly stops tolerating
    /// typos while every other test stays green. So the expectations below are the *Python*
    /// function's output, generated from `species_trigrams()` in `Tools/build_seed.py` and pasted
    /// here, rather than anything this file computed for itself.
    @Test("the Swift trigrams are the ones Tools/build_seed.py wrote into the seed")
    func theSwiftAndPythonTrigramsAgree() {
        #expect(SpeciesQueries.trigrams("Oak") == ["  o", " oa", "ak ", "oak"])

        #expect(SpeciesQueries.trigrams("Monterey Cypress") == [
            "  m", " cy", " mo", "cyp", "ere", "ess", "ey ", "mon", "nte", "ont",
            "pre", "res", "rey", "ss ", "ter", "y c", "ypr"
        ])

        // An apostrophe and a cultivar name: punctuation becomes a space, and the run collapses.
        #expect(SpeciesQueries.trigrams("Liquidambar styraciflua 'Rotundiloba'") == [
            "  l", " li", " ro", " st", "a r", "aci", "amb", "ar ", "ba ", "bar",
            "cif", "dam", "dil", "flu", "ida", "ifl", "ilo", "iqu", "liq", "lob",
            "lua", "mba", "ndi", "oba", "otu", "qui", "r s", "rac", "rot", "sty",
            "tun", "tyr", "ua ", "uid", "und", "yra"
        ])

        // A hyphen is a word boundary, as it is for E165's rank bands.
        #expect(SpeciesQueries.trigrams("Purple-Leaf Plum") == [
            "  p", " le", " pl", " pu", "af ", "e l", "eaf", "f p", "le ", "lea",
            "lum", "ple", "plu", "pur", "rpl", "um ", "urp"
        ])

        // Non-ASCII folds to a space on both sides rather than being case-folded by either, because
        // Swift's `lowercased()` and Python's `.lower()` do not agree in the corners.
        #expect(SpeciesQueries.trigrams("Érable") == ["  r", " ra", "abl", "ble", "le ", "rab"])

        // Nothing to index is an empty set, not a set of padding.
        #expect(SpeciesQueries.trigrams("   ").isEmpty)
        #expect(SpeciesQueries.trigrams("").isEmpty)
    }

    // MARK: - Fixture

    /// A minimal seed carrying two species, with or without the trigram index.
    ///
    /// Two species and not one: `Liquidambar styraciflua` is the answer and `Platanus racemosa`
    /// is there so that "found the right row" is distinguishable from "returned everything".
    private static func miniSeed(withTrigrams: Bool) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("e165-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("cypress-seed.sqlite")

        let connection = try SQLiteConnection(path: url.path)
        try connection.execute("""
            CREATE TABLE trees (
                id INTEGER PRIMARY KEY, uuid TEXT NOT NULL UNIQUE, lat REAL, lon REAL,
                status TEXT, deleted_at TEXT
            );
            CREATE TABLE species (
                id INTEGER PRIMARY KEY, uuid TEXT NOT NULL UNIQUE,
                scientific_name TEXT NOT NULL, common_name TEXT, family TEXT,
                leaf_retention TEXT, id_tips TEXT NOT NULL DEFAULT '[]',
                seasonal TEXT NOT NULL DEFAULT '{}', care_notes TEXT NOT NULL DEFAULT '[]',
                curated INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT
            );
            CREATE TABLE neighborhoods (id INTEGER PRIMARY KEY);
            CREATE TABLE trees_rtree (id INTEGER PRIMARY KEY);
            INSERT INTO species (id, uuid, scientific_name, common_name, created_at, updated_at)
            VALUES (1, '\(UUID().uuidString)', 'Liquidambar styraciflua', 'American Sweet Gum',
                    '2026-01-01T00:00:00+00:00', '2026-01-01T00:00:00+00:00'),
                   (2, '\(UUID().uuidString)', 'Platanus racemosa', 'California Sycamore',
                    '2026-01-01T00:00:00+00:00', '2026-01-01T00:00:00+00:00');
            """)

        if withTrigrams {
            // The same DDL `Tools/build_seed.py` writes, and the same trigram scheme, applied to
            // the two rows above.
            try connection.execute("""
                CREATE TABLE species_trigrams (
                    trigram TEXT NOT NULL,
                    species_id INTEGER NOT NULL REFERENCES species(id),
                    PRIMARY KEY (trigram, species_id)
                ) WITHOUT ROWID;
                """)
            for (id, name, common) in [
                (1, "Liquidambar styraciflua", "American Sweet Gum"),
                (2, "Platanus racemosa", "California Sycamore")
            ] {
                for gram in SpeciesQueries.trigrams(name).union(SpeciesQueries.trigrams(common)) {
                    let escaped = gram.replacingOccurrences(of: "'", with: "''")
                    try connection.execute(
                        "INSERT OR IGNORE INTO species_trigrams VALUES ('\(escaped)', \(id))"
                    )
                }
            }
        }
        return url
    }
}
