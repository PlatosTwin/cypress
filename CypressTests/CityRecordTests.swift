import Foundation
import Testing
@testable import Cypress

/// The city's own record, and the land context read out of it.
///
/// Six DataSF columns now land on `seed.trees`, and `LandContext.inferred(from:)` reads two of them
/// to answer "what ground does this tree stand on" — the question task #69 asks a contributor and
/// this half answers for the 195,309 trees the city already knows about.
///
/// ── Why the distribution is asserted against the whole seed ───────────────────────────────────
/// The mapping's doc comment carries a table of four numbers, and a table in a comment is a claim
/// that rots the moment either the rule or the seed moves. `bucketsMatchTheDocumentedDistribution`
/// re-derives all four from all 195,309 rows, so the day somebody adds a legal status to the rule or
/// rebuilds from a fresher export, the comment fails rather than lying. The individual cases below
/// are not redundant with it: a total can stay right while two buckets swap.
@Suite("City record")
struct CityRecordTests {

    private static func store() async throws -> CypressStore {
        let seedURL = try #require(SeedContractTests.seedURL, "no seed database; set CYPRESS_SEED_PATH")
        return try await CypressStore.inMemory(seedURL: seedURL)
    }

    // MARK: - The columns are there and are populated

    /// The populations measured against the source at ingest, pinned so that a rebuild which quietly
    /// stops writing one of the six fails here rather than on somebody's tree page.
    ///
    /// Exact counts rather than "greater than zero", because the failure this guards is a column that
    /// still exists and has gone half empty — a `.strip()` that starts eating values, a CSV whose
    /// header drifts. A column that emptied completely is the easy case; these numbers catch the
    /// other one.
    @Test("the seed carries all six city columns, populated as measured at ingest")
    func theSixColumnsArePopulated() async throws {
        let store = try await Self.store()
        let expected: [(String, Int)] = [
            ("legal_status", 195_252),
            ("caretaker", 195_309),
            ("care_assistant", 25_199),
            ("plant_type", 195_309),
            ("plot_size", 146_951),
            ("permit_notes", 52_580)
        ]

        try await store.queue.read { connection in
            for (column, count) in expected {
                let statement = try connection.cachedStatement(
                    "SELECT count(\(column)) AS n FROM \(SeedDatabase.schemaName).trees"
                )
                let actual = try statement.fetchOne { try $0.int("n") } ?? -1
                #expect(actual == count, "\(column) holds \(actual) values, expected \(count)")
            }
        }
    }

    /// The columns reach a decoded `Tree`, not just the file. `treeColumns` selects them and
    /// `TreeQueries.decodeCityRecord` assembles them; either could be dropped without the file
    /// changing at all.
    @Test("a city tree's record reaches the profile payload")
    func theRecordReachesTheProfile() async throws {
        let store = try await Self.store()
        let queries = TreeQueries(
            schema: try #require(store.seed),
            seedHasSoftDeletedTrees: store.seedHasSoftDeletedTrees
        )

        let record = try await store.queue.read { connection -> CityRecord? in
            let statement = try connection.cachedStatement("""
                SELECT uuid FROM \(SeedDatabase.schemaName).trees
                 WHERE legal_status IS NOT NULL AND caretaker IS NOT NULL
                   AND care_assistant IS NOT NULL AND plot_size IS NOT NULL
                   AND permit_notes IS NOT NULL AND plant_type IS NOT NULL
                 LIMIT 1
                """)
            let uuid = try #require(try statement.fetchOne { try $0.uuid("uuid") })
            return try queries.tree(id: uuid, connection: connection)?.tree.cityRecord
        }

        let unwrapped = try #require(record, "a row with all six columns set decoded to no city record")
        #expect(unwrapped.isEmpty == false)
        #expect(unwrapped.legalStatus != nil)
        #expect(unwrapped.caretaker != nil)
        #expect(unwrapped.careAssistant != nil)
        #expect(unwrapped.plantType != nil)
        #expect(unwrapped.plotSize != nil)
        #expect(unwrapped.permitNotes != nil)
    }

    // MARK: - There is no pruning data, and saying so is the answer

    /// **The project owner asked for "next pruning / last pruning" and the answer is that this
    /// dataset cannot give it at any grain.**
    ///
    /// Recorded as a test rather than only as a comment so that the day DataSF adds such a column and
    /// somebody ingests it, this fails and the owner's question gets reopened deliberately. The two
    /// `legal_status` values that mention pruning are opt-outs from the city's maintenance programme
    /// — a standing policy, not an event — and this asserts they are the only mention, so nothing
    /// downstream can mistake one for a date.
    @Test("no column in the seed records a pruning event, and the two that say 'prune' are opt-outs")
    func thereIsNoPruningData() async throws {
        let store = try await Self.store()

        try await store.queue.read { connection in
            let columns = try connection.columnNames(ofTable: "trees", in: SeedDatabase.schemaName)
            let pruning = columns.filter { $0.lowercased().contains("prun") }
            #expect(
                pruning.isEmpty,
                """
                seed.trees now has \(pruning) — if DataSF has started publishing pruning data, \
                task #68's "next pruning / last pruning" is answerable and should be reopened
                """
            )

            let statement = try connection.cachedStatement("""
                SELECT DISTINCT legal_status AS value FROM \(SeedDatabase.schemaName).trees
                 WHERE legal_status LIKE '%rune%' ORDER BY legal_status
                """)
            let values = try statement.fetchAll { try $0.stringIfPresent("value") }.compactMap { $0 }
            #expect(values == ["Prune Opt Out", "Street Tree Maintenance Opt Out"].filter { $0.contains("rune") })
        }
    }

    // MARK: - The mapping

    /// **The trap this whole mapping exists to avoid.**
    ///
    /// `qCaretaker` is `"Private"` on 163,955 of 195,309 rows, and DataSF's own description of the
    /// field ends "Owner of Tree" — so reading it as a location is both easy and wrong. 112,955 of
    /// those rows also say `"DPW Maintained"`: a street tree in the sidewalk whose adjacent owner
    /// waters it. A mapping that led on the caretaker would file roughly 150,000 street trees under
    /// private property while looking perfectly sensible.
    @Test("a DPW-maintained tree with a private caretaker is a street tree, not private property")
    func jurisdictionBeatsCare() {
        let record = CityRecord(legalStatus: "DPW Maintained", caretaker: "Private")
        #expect(LandContext.inferred(from: record) == .street)
    }

    @Test("legal status decides wherever it names a jurisdiction", arguments: [
        ("DPW Maintained", LandContext.street),
        ("Permitted Site", .street),
        ("Section 806 (d)", .street),
        ("Planning Code 138.1 required", .street),
        ("Section 143", .street),
        ("Prune Opt Out", .street),
        ("Street Tree Maintenance Opt Out", .street),
        ("Private", .privateProperty),
        ("Property Tree", .privateProperty)
    ])
    func legalStatusDecides(status: String, expected: LandContext) {
        // The caretaker is set to the value that would give the opposite answer if it were consulted.
        let contrary = expected == .street ? "Private" : "DPW"
        #expect(LandContext.inferred(from: CityRecord(legalStatus: status, caretaker: contrary)) == expected)
    }

    /// Where the legal status names a protective designation rather than a place — SF's Public Works
    /// Code attaches both of these on either side of the property line — or says nothing at all, the
    /// caretaker is the only signal left and answers for those rows only.
    @Test("caretaker answers only where the legal status is silent about location", arguments: [
        ("Significant Tree", "Rec/Park", LandContext.cityPark),
        ("Significant Tree", "Private", .privateProperty),
        ("Landmark tree", "SFUSD", .otherPublic),
        ("Undocumented", "Port", .otherPublic),
        ("Undocumented", "Private", .privateProperty),
        ("", "Rec/Park", .cityPark)
    ])
    func caretakerFillsIn(status: String, caretaker: String, expected: LandContext) {
        #expect(LandContext.inferred(from: CityRecord(legalStatus: status, caretaker: caretaker)) == expected)
    }

    /// A record that says neither resolves to nothing rather than to a plausible bucket. The current
    /// export contains no such row, but it is refreshed weekly and the return type is optional
    /// precisely so a silent record can stay silent.
    @Test("a record that says neither resolves to no context at all")
    func silenceStaysSilent() {
        #expect(LandContext.inferred(from: CityRecord()) == nil)
        #expect(LandContext.inferred(from: CityRecord(legalStatus: "Undocumented", caretaker: "")) == nil)
    }

    /// **The four numbers in `LandContext.inferred(from:)`'s doc table, re-derived from every row.**
    ///
    /// This is the assertion #69 will actually lean on: it says the mapping covers the whole
    /// inventory and says how much lands in each bucket, so a picker built on three buckets knows
    /// exactly what it is leaving out.
    @Test("the mapping covers all 195,309 rows in the documented proportions")
    func bucketsMatchTheDocumentedDistribution() async throws {
        let store = try await Self.store()

        var counts: [LandContext?: Int] = [:]
        try await store.queue.read { connection in
            let statement = try connection.cachedStatement("""
                SELECT legal_status AS legal_status, caretaker AS caretaker, count(*) AS n
                  FROM \(SeedDatabase.schemaName).trees
                 GROUP BY legal_status, caretaker
                """)
            for row in try statement.fetchAll({ row -> (CityRecord, Int) in
                (
                    CityRecord(
                        legalStatus: try row.stringIfPresent("legal_status"),
                        caretaker: try row.stringIfPresent("caretaker")
                    ),
                    try row.int("n")
                )
            }) {
                counts[LandContext.inferred(from: row.0), default: 0] += row.1
            }
        }

        #expect(counts[.street] == 182_320)
        #expect(counts[.privateProperty] == 11_856)
        #expect(counts[.otherPublic] == 956)
        #expect(counts[.cityPark] == 177)
        #expect(counts[LandContext?.none] == nil, "some row resolved to no context; the mapping used to cover every row")
        #expect(counts.values.reduce(0, +) == 195_309)
    }

    // MARK: - Stated beats inferred, and says so

    /// A contributor was standing there; the mapping was reading two strings in a municipal export.
    /// Nothing may show the second with the confidence of the first, which is why the answer carries
    /// its own provenance rather than leaving a screen to remember to ask.
    @Test("a contributor's own answer wins over the reading of the city's record, and names itself")
    func statedWinsAndIsLabelled() {
        let city = CityRecord(legalStatus: "DPW Maintained", caretaker: "Private")

        let inferred = try? #require(Tree(source: .cityImport, coordinate: .init(latitude: 37.77, longitude: -122.42), cityRecord: city).landContext)
        #expect(inferred?.context == .street)
        #expect(inferred?.source == .inferredFromCityRecord)

        let stated = Tree(
            source: .community,
            coordinate: .init(latitude: 37.77, longitude: -122.42),
            cityRecord: city,
            statedLandContext: .cityPark
        ).landContext
        #expect(stated?.context == .cityPark)
        #expect(stated?.source == .statedByContributor)
    }

    /// A community tree whose contributor did not answer has no context at all — it has no city
    /// record to fall back on, and nothing may invent one.
    @Test("an unanswered community tree has no land context")
    func unansweredIsAbsent() {
        let tree = Tree(source: .community, coordinate: .init(latitude: 37.77, longitude: -122.42))
        #expect(tree.landContext == nil)
    }

    // MARK: - AppSchema v11

    /// The vocabulary is a CHECK, so it holds against a hand-written `INSERT` the way this schema's
    /// other closed vocabularies do — and unlike the six seed columns, which hold San Francisco's
    /// vocabulary rather than Cypress's and are deliberately unconstrained.
    @Test("the engine refuses a land context outside the four")
    func theVocabularyIsEnforcedByTheEngine() async throws {
        let store = try await CypressStore.inMemory()
        for bad in ["Street", "park", "", "city-park"] {
            await #expect(throws: SQLiteError.self, "the engine accepted \(bad)") {
                try await store.queue.write { connection in
                    try connection.execute("""
                        INSERT INTO community_trees
                            (id, client_uuid, source, lat, lon, status, verification_state,
                             land_context, created_at, updated_at)
                        VALUES ('\(UUID().uuidString)', '\(UUID().uuidString)', 'community',
                                37.77, -122.42, 'alive', 'unverified',
                                '\(bad)', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
                        """)
                }
            }
        }
    }

    /// NULL is a value here and means "not stated". Unlike v10's `placement` there is no column
    /// default, on purpose: no tree written before v11 was ever asked, so any default would be
    /// Cypress answering for a contributor.
    @Test("the column accepts all four and NULL, and defaults to nothing")
    func nullIsTheUnansweredState() async throws {
        let store = try await CypressStore.inMemory()

        for context in LandContext.allCases {
            let id = UUID()
            try await store.queue.write { connection in
                try CommunityTreeStore().insert(
                    Tree(
                        id: id,
                        source: .community,
                        coordinate: .init(latitude: 37.77, longitude: -122.42),
                        statedLandContext: context
                    ),
                    clientUUID: UUID(),
                    connection: connection
                )
            }
            #expect(try await Self.storedContext(of: id, in: store) == context.rawValue)
        }

        let unanswered = UUID()
        try await store.queue.write { connection in
            try CommunityTreeStore().insert(
                Tree(id: unanswered, source: .community, coordinate: .init(latitude: 37.77, longitude: -122.42)),
                clientUUID: UUID(),
                connection: connection
            )
        }
        #expect(try await Self.storedContext(of: unanswered, in: store) == nil)
    }

    /// The whole write path — `TreeDraft` through `LocalAPI.addTree` through `CommunityTreeStore` —
    /// and then read back out of the column with SQL rather than off the model that was just handed
    /// in. Any of those layers could drop the answer and leave a `Tree` that says the right thing
    /// about a row that says nothing.
    @Test("a contributor's answer travels from the draft to the column and back")
    func theDraftReachesTheColumn() async throws {
        let store = try await CypressStore.inMemory()
        let deviceID = UUID()
        let api = LocalAPI(store: store, deviceID: deviceID)

        let tree = try await api.addTree(
            TreeDraft(
                coordinate: .init(latitude: 37.7599, longitude: -122.4148),
                photoLocalPath: "/tmp/does-not-need-to-exist.jpg",
                attribution: .anonymous(deviceID: deviceID),
                landContext: .privateProperty
            )
        )

        #expect(try await Self.storedContext(of: tree.id, in: store) == "private_property")
        let readBack = try await api.treeProfile(id: tree.id).tree
        #expect(readBack.statedLandContext == .privateProperty)
        #expect(readBack.landContext?.context == .privateProperty)
        #expect(readBack.landContext?.source == .statedByContributor)
        #expect(readBack.cityRecord == nil, "a community tree is not in the city's inventory")
    }

    /// The stored string, exactly as SQLite holds it — not `Tree.statedLandContext`, which is a
    /// decode of it.
    private static func storedContext(of id: UUID, in store: CypressStore) async throws -> String? {
        try await store.queue.read { connection -> String? in
            let statement = try connection.prepare(
                "SELECT land_context FROM community_trees WHERE id = :id COLLATE NOCASE"
            )
            defer { statement.finalize() }
            _ = try statement.bind(id.uuidString, forName: ":id")
            return try statement.fetchOne { try $0.stringIfPresent("land_context") } ?? nil
        }
    }
}
