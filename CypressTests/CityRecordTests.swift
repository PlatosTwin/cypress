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
    ///
    /// **The counts move with the source**, so they come from `SeedCorpus` rather than from literals
    /// here. Under `--source city` five of the six are carried across from the DataSF export for the
    /// 130,070 records both inventories list, so they land at ~97% rather than 100%; the shortfall is
    /// the 3,507 records only SF Public Works lists.
    ///
    /// A zero is additionally checked against `seed_meta.columns_absent_from_source`, so a column
    /// that empties by accident under a source that *does* publish it still fails here rather than
    /// turning this test into six comparisons of nothing against nothing.
    @Test("the seed carries all six city columns, populated as measured at ingest")
    func theSixColumnsArePopulated() async throws {
        let store = try await Self.store()
        let corpus = try await SeedCorpus.current(store)
        let dataSFNames = [
            "legal_status": "qLegalStatus", "caretaker": "qCaretaker",
            "care_assistant": "qCareAssistant", "plant_type": "PlantType",
            "plot_size": "PlotSize", "permit_notes": "PermitNotes"
        ]

        try await store.queue.read { connection in
            for (column, count) in corpus.cityColumnRows.sorted(by: { $0.key < $1.key }) {
                let statement = try connection.cachedStatement(
                    "SELECT count(\(column)) AS n FROM \(SeedDatabase.schemaName).trees"
                )
                let actual = try statement.fetchOne { try $0.int("n") } ?? -1
                #expect(
                    actual == count,
                    "\(column) holds \(actual) values, expected \(count) under --source \(corpus.source)"
                )
                if count == 0, let upstream = dataSFNames[column] {
                    #expect(
                        !corpus.publishes(upstream),
                        "\(column) is empty, but \(corpus.source) does publish \(upstream): a lost column, not an absent one"
                    )
                }
            }
        }
    }

    /// The columns reach a decoded `Tree`, not just the file. `treeColumns` selects them and
    /// `TreeQueries.decodeCityRecord` assembles them; either could be dropped without the file
    /// changing at all.
    ///
    /// The row it looks for carries every column the *running source* publishes rather than all six
    /// unconditionally, so a source that drops one fails on the dropped column rather than on an
    /// empty result set. The assertions follow the same rule in both directions.
    @Test("a city tree's record reaches the profile payload")
    func theRecordReachesTheProfile() async throws {
        let store = try await Self.store()
        let corpus = try await SeedCorpus.current(store)
        let queries = TreeQueries(
            schema: try #require(store.seed),
            seedHasSoftDeletedTrees: store.seedHasSoftDeletedTrees
        )

        let published = [
            ("legal_status", "qLegalStatus"), ("caretaker", "qCaretaker"),
            ("care_assistant", "qCareAssistant"), ("plant_type", "PlantType"),
            ("plot_size", "PlotSize"), ("permit_notes", "PermitNotes")
        ].filter { corpus.publishes($0.1) }
        #expect(!published.isEmpty, "no source publishes none of the six; the seed carries no city record at all")
        let predicate = published.map { "\($0.0) IS NOT NULL" }.joined(separator: " AND ")

        let record = try await store.queue.read { connection -> CityRecord? in
            let statement = try connection.cachedStatement("""
                SELECT uuid FROM \(SeedDatabase.schemaName).trees
                 WHERE \(predicate)
                 LIMIT 1
                """)
            let uuid = try #require(try statement.fetchOne { try $0.uuid("uuid") })
            return try queries.tree(id: uuid, connection: connection)?.tree.cityRecord
        }

        let unwrapped = try #require(record, "a row with every published column set decoded to no city record")
        #expect(unwrapped.isEmpty == false)
        #expect((unwrapped.legalStatus != nil) == corpus.publishes("qLegalStatus"))
        #expect((unwrapped.caretaker != nil) == corpus.publishes("qCaretaker"))
        #expect((unwrapped.careAssistant != nil) == corpus.publishes("qCareAssistant"))
        #expect(unwrapped.plantType != nil)
        #expect((unwrapped.plotSize != nil) == corpus.publishes("PlotSize"))
        #expect((unwrapped.permitNotes != nil) == corpus.publishes("PermitNotes"))
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
        let corpus = try await SeedCorpus.current(store)

        try await store.queue.read { connection in
            let columns = try connection.columnNames(ofTable: "trees", in: SeedDatabase.schemaName)
            let pruning = columns.filter { $0.lowercased().contains("prun") }
            // **This assertion became load-bearing with #91.** It used to guard against a column
            // DataSF might one day add. The inventory we ship now carries `Prune_Status` and
            // `Prune_Year` on every record, and `Tools/fetch_city_trees.py` has them cached on disk
            // — so the only thing standing between them and a tree page is a decision not to ingest
            // them, and this is where that decision is written down.
            //
            // They are properties of the **keymap grid**, not the tree: 133,577 records share 106
            // distinct `Prune_Year` values, 5,147 of them the single string `Completed 20210601`.
            // A column named `prune_year` in this table gets rendered under a tree's name sooner or
            // later, and that is E143's mistake with a different column. If this fails, somebody has
            // ingested them and #68 has been reopened by accident rather than on purpose.
            #expect(
                pruning.isEmpty,
                """
                seed.trees now has \(pruning). The city's layer publishes pruning at BLOCK grain \
                (106 distinct values over 133,577 records); nothing here may present it as this \
                tree's pruning date. Reopen #68 deliberately or drop the column.
                """
            )

            let statement = try connection.cachedStatement("""
                SELECT DISTINCT legal_status AS value FROM \(SeedDatabase.schemaName).trees
                 WHERE legal_status LIKE '%rune%' ORDER BY legal_status
                """)
            let values = try statement.fetchAll { try $0.stringIfPresent("value") }.compactMap { $0 }
            // `legal_status` is a DataSF column. Under `--source city` there is none, so there is
            // no status mentioning pruning either — and the reason must be the absent column rather
            // than a vocabulary that quietly changed.
            let expected = corpus.publishes("qLegalStatus")
                ? ["Prune Opt Out", "Street Tree Maintenance Opt Out"].filter { $0.contains("rune") }
                : []
            #expect(values == expected)
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
    @Test("the mapping covers every row of the inventory, in the documented proportions")
    func bucketsMatchTheDocumentedDistribution() async throws {
        let store = try await Self.store()
        let corpus = try await SeedCorpus.current(store)

        // **Grouped by id space as well as by the two columns, because the mapping is now qualified
        // by one (R24).** `legal_status` holds DataSF's `qLegalStatus` for an `sf` row and San Jose's
        // `OWNEDBY` for a `us-ca-sj` one. Reading them as one vocabulary is exactly what this test
        // would have ratified: before the qualifier existed it counted 52,632 rows as
        // `.privateProperty` — 48,036 of them San Jose street trees whose adjacent owner waters them.
        let hasIdSpace = store.seed?.hasIdSpace == true
        var counts: [LandContext?: Int] = [:]
        try await store.queue.read { connection in
            let statement = try connection.cachedStatement("""
                SELECT legal_status AS legal_status, caretaker AS caretaker,
                       \(hasIdSpace ? "id_space" : "'sf'") AS id_space, count(*) AS n
                  FROM \(SeedDatabase.schemaName).trees
                 GROUP BY legal_status, caretaker, id_space
                """)
            for row in try statement.fetchAll({ row -> (CityRecord, String, Int) in
                (
                    CityRecord(
                        legalStatus: try row.stringIfPresent("legal_status"),
                        caretaker: try row.stringIfPresent("caretaker")
                    ),
                    try row.string("id_space"),
                    try row.int("n")
                )
            }) {
                counts[LandContext.inferred(from: row.0, idSpace: row.1), default: 0] += row.2
            }
        }

        #expect((counts[.street] ?? 0) == corpus.landContextStreet)
        #expect((counts[.privateProperty] ?? 0) == corpus.landContextPrivate)
        #expect((counts[.otherPublic] ?? 0) == corpus.landContextOtherPublic)
        #expect((counts[.cityPark] ?? 0) == corpus.landContextCityPark)

        // **Under `--source city` every row is unplaced, and that is the whole cost of the switch
        // for #69.** `LandContext.inferred(from:)` reads `qLegalStatus` and `qCaretaker`; SF Public
        // Works' own layer publishes neither, so no row can be placed and the `Stands on` sentence
        // draws for nobody. The mapping is not broken — it has nothing to read.
        //
        // Pinned as an exact number rather than tolerated, and cross-checked against the source's
        // own column list, so a mapping that started failing on a corpus that *does* carry those
        // columns still fails here.
        #expect(
            (counts[LandContext?.none] ?? 0) == corpus.landContextUnplaced,
            "\(counts[LandContext?.none] ?? 0) rows resolved to no context, expected \(corpus.landContextUnplaced)"
        )
        // An unplaced row must be unplaced for one of exactly TWO reasons, never because the mapping
        // failed on it:
        //
        //   1. the record says neither thing. The 3,506 under `--source city` are records only SF
        //      Public Works lists, so the DataSF export has no row to carry `qLegalStatus` or
        //      `qCaretaker` across from.
        //   2. the row is in an id space this mapping was not written for, and it declined (R24).
        //      52,788 San Jose rows, every one of which the mapping WOULD have placed — 48,036 of
        //      them wrongly, as private property, on a layer called Street Trees.
        //
        // Decomposed rather than totalled, because the two are different facts and a change that
        // turned one into the other would balance a single sum without anybody noticing.
        let saysNeither = try await store.queue.read { connection -> Int in
            let statement = try connection.prepare("""
                SELECT COUNT(*) AS n FROM \(SeedDatabase.schemaName).trees
                 WHERE COALESCE(legal_status, '') = '' AND COALESCE(caretaker, '') = ''
                   \(hasIdSpace ? "AND id_space = 'sf'" : "")
                """)
            defer { statement.finalize() }
            return try statement.fetchOne { try $0.int("n") } ?? -1
        }
        let declined = try await store.queue.read { connection -> Int in
            guard hasIdSpace else { return 0 }
            let statement = try connection.prepare("""
                SELECT COUNT(*) AS n FROM \(SeedDatabase.schemaName).trees WHERE id_space <> 'sf'
                """)
            defer { statement.finalize() }
            return try statement.fetchOne { try $0.int("n") } ?? -1
        }
        #expect(
            declined == corpus.landContextDeclinedForeignVocabulary,
            "\(declined) rows are outside the mapping's id space, expected \(corpus.landContextDeclinedForeignVocabulary)"
        )
        #expect(
            saysNeither + declined == corpus.landContextUnplaced,
            "\(corpus.landContextUnplaced) rows are unplaced but \(saysNeither) say neither thing and \(declined) are in a foreign id space; the mapping failed on the difference"
        )
        #expect(counts.values.reduce(0, +) == corpus.trees)
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
