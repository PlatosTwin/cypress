import Foundation

/// Reads over `seed.species` — the field guide and the autocomplete behind `GET /species*`.
public struct SpeciesQueries {
    private let schema: SeedSchema
    private let seed = SeedDatabase.schemaName

    public init(schema: SeedSchema) {
        self.schema = schema
    }

    // MARK: - Lookup

    /// `GET /species/{id}`.
    ///
    /// ```
    /// SEARCH s USING COVERING INDEX sqlite_autoindex_species_1 (uuid=?)
    /// ```
    public func species(id: UUID, connection: SQLiteConnection) throws -> Species? {
        let sql = """
        SELECT \(Self.projection(identityColumn: schema.speciesIdentityColumn))
          FROM \(seed).species s
         WHERE s.\(schema.speciesIdentityColumn) = :uuid COLLATE NOCASE
        """
        let statement = try connection.cachedStatement(sql)
        _ = try statement.bind(id.uuidString, forName: ":uuid")
        return try statement.fetchOne { try Self.decodeIfPresent($0) }.flatMap { $0 }
    }

    /// `GET /species?query=` — autocomplete over both names, matching the word **anywhere** in
    /// either of them.
    ///
    /// BUILD-PLAN §6 specifies a trigram index on both names, which Postgres has and SQLite does
    /// not. The on-device equivalent is a substring match against the two B-tree indexes the seed
    /// already carries, unioned, with a rank computed in the same pass:
    ///
    /// ```
    /// CO-ROUTINE m
    ///   CO-ROUTINE (subquery-2)
    ///     COMPOUND QUERY
    ///       LEFT-MOST SUBQUERY
    ///         SCAN species USING COVERING INDEX idx_species_scientific_name
    ///       UNION ALL
    ///         SCAN species USING COVERING INDEX idx_species_common_name
    ///   SCAN (subquery-2)
    ///   USE TEMP B-TREE FOR GROUP BY
    /// SCAN m
    /// SEARCH s USING INTEGER PRIMARY KEY (rowid=?)
    /// USE TEMP B-TREE FOR ORDER BY
    /// ```
    ///
    /// ── Why `LIKE '%q%'` costs nothing here, which is not the usual answer ───────────────────────
    /// The usual objection to a leading wildcard is that it throws away an index. It does not throw
    /// away anything here, because **this query was never seeking**. The shape it replaces was a
    /// range scan — `name >= :q AND name < :q || U+FFFF` — and its plan said `SCAN … USING COVERING
    /// INDEX`, not a range `SEARCH`: `COLLATE NOCASE` on the comparison does not match the `BINARY`
    /// collation the seed's two name indexes were built with, so SQLite could not turn the range
    /// into a seek and walked the whole index anyway. The plan above is the same walk with a
    /// different predicate on each row.
    ///
    /// Measured against the full seed (`.measurements/species-search-108.txt`): the **SQL** goes
    /// from 0.08–0.25 ms to 0.13–0.83 ms — roughly double, for four `LIKE` evaluations a row where
    /// there were two comparisons, and still under a millisecond at its worst. The **whole read** is
    /// unchanged where the two return the same rows (`quercus` 2.60 → 2.67 ms, `c` 14.95 → 15.31 ms)
    /// because it is dominated by decoding `species`' four JSON columns at ~0.15 ms a row. Where it
    /// costs more it is because the search found more: `oak` goes from 1 species to 21, and 3.3 ms
    /// is the price of the twenty Oaks it should have been finding all along. None of this is on a
    /// frame budget — it runs off the main actor behind `MapModel.searchDebounce`'s 300 ms.
    ///
    /// What is load-bearing is the **shape**, not the predicate: both branches select `id` and one
    /// name, so both stay *covering* — the 577-row `species` table, with its four JSON columns, is
    /// never touched except for the rows that matched. Widening either branch to select anything
    /// else turns a covering walk into a probe per row, which is the rule `MapQueryPlanTests`
    /// gates. `speciesSearchStaysOnItsCoveringIndexes` is that gate for this statement.
    ///
    /// ── The rank, and why it is a rank and not an ordering ───────────────────────────────────────
    /// Matching anywhere makes "cypress" find all six Cypresses in the seed instead of the one
    /// called `Cypress species`, which is the defect. But it also makes "oak" find `Silkoak
    /// species`, where the letters are simply inside a longer word. So the match carries a rank:
    ///
    ///     0  the name *starts* with the query        `Oak`, `Cypress species`
    ///     1  a *word* in the name starts with it     `Coast Live Oak`, `Monterey Cypress`
    ///     2  the letters appear inside a word        `Silkoak species`
    ///
    /// A species matching on both names takes its better rank (`min`). Ties fall through to the
    /// ordering this query always had — curated first, then scientific name — so `Monterey Cypress`,
    /// the one curated Cypress, heads its band. Word starts are recognised after a space or a
    /// hyphen: DataSF's own double-name format is comma-separated (`Sycamore, London Plane`) and
    /// hyphenated common names are everywhere in the seed (`Drooping She-Oak`, `Purple-Leaf Plum`).
    ///
    /// ── What this still is not ──────────────────────────────────────────────────────────────────
    /// It is a substring match, not a trigram one: it does not tolerate a typo and it does not match
    /// across word order. An FTS5 index would, and the seed does not carry one; that remains
    /// `Tools/build_seed.py`'s to add rather than the client's to fake at launch.
    public func search(query: String, limit: Int, connection: SQLiteConnection) throws -> [Species] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let pattern = Self.escapedForLike(trimmed)

        let statement = try connection.cachedStatement(searchSQL())
        _ = try statement.bind([
            ":anywhere": "%\(pattern)%",
            ":head": "\(pattern)%",
            ":afterSpace": "% \(pattern)%",
            ":afterHyphen": "%-\(pattern)%",
            ":limit": limit
        ])
        return try statement.fetchAll { try Self.decodeIfPresent($0) }.compactMap { $0 }
    }

    /// The statement `search(query:limit:connection:)` runs, exposed so a plan gate can explain the
    /// text the app actually executes rather than a paraphrase of it copied into a test.
    ///
    /// That distinction is `MapQueryPlanTests`' whole subject: the gates it replaced explained SQL
    /// hand-copied into `DataGates`, so changing the real query left them explaining the copy.
    func searchSQL() -> String {
        """
        SELECT \(Self.projection(identityColumn: schema.speciesIdentityColumn))
          FROM \(seed).species s
          JOIN (
                 SELECT id, min(match_rank) AS match_rank
                   FROM (
                          SELECT id, \(Self.rankExpression(column: "scientific_name")) AS match_rank
                            FROM \(seed).species
                           WHERE scientific_name LIKE :anywhere ESCAPE '\\'
                          UNION ALL
                          SELECT id, \(Self.rankExpression(column: "common_name")) AS match_rank
                            FROM \(seed).species
                           WHERE common_name LIKE :anywhere ESCAPE '\\'
                        )
                  GROUP BY id
               ) m ON m.id = s.id
         WHERE s.deleted_at IS NULL
           AND s.scientific_name NOT LIKE ':: %'
         ORDER BY m.match_rank, s.curated DESC, s.scientific_name
         LIMIT :limit
        """
    }

    /// Why the second condition is a `LIKE` on a name and not a join to `species_map.is_stub`.
    ///
    /// A species the ingest could not read keeps the raw source string as its scientific name, so its
    /// name still carries DataSF's `::` separator with an empty scientific half — `:: 9662`,
    /// `:: Magnolia`. Those are the rows this list must not offer, and the ruling that says so is
    /// `RULINGS R47`.
    ///
    /// The exact statement of "the ingest could not read this" is `species_map.is_stub`, and the
    /// obvious query asks it directly. It is not asked here for two reasons, both measured rather
    /// than assumed. `species_map` carries no index on `species_id` — its only index is the primary
    /// key on `qspecies_string` — so a correlated `EXISTS` over it is a scan per candidate row, and
    /// `SpeciesSearchTests.searchStaysOnItsCoveringIndexes` fails on the `SCAN species_map` step it
    /// adds. Adding that index would change `Fixtures/seed/schema.sql`, and the per-city files
    /// already published at seed schema 14 would not have it, so the plan would differ between the
    /// bundled seed and a downloaded city — the gate would pass here and the scan would happen there.
    ///
    /// So the cheap predicate runs in the hot query and the exact one is asserted beside the seed:
    /// `SeedStubNamingTests` proves the two select the same rows, which is what makes this `LIKE`
    /// honest rather than a guess about the shape of the data.
    static let stubNameMarker = ":: "

    /// The three-band rank of `search(query:limit:connection:)`, over one name column.
    ///
    /// Written once and interpolated twice so the two branches of the union cannot drift; the
    /// column name is a literal from this file, never anything a caller supplied.
    static func rankExpression(column: String) -> String {
        "CASE WHEN \(column) LIKE :head ESCAPE '\\' THEN \(MatchRank.head) "
            + "WHEN \(column) LIKE :afterSpace ESCAPE '\\' "
            + "OR \(column) LIKE :afterHyphen ESCAPE '\\' THEN \(MatchRank.word) "
            + "ELSE \(MatchRank.interior) END"
    }

    /// The rank bands `search` sorts by. Named so the SQL above and the tests that assert the
    /// resulting order are reading the same numbers.
    enum MatchRank {
        /// The name begins with the query.
        static let head = 0
        /// A word inside the name begins with it.
        static let word = 1
        /// The letters appear inside a word.
        static let interior = 2
    }

    /// Escapes a user-typed query for use inside a `LIKE` pattern with `ESCAPE '\'`.
    ///
    /// Without this, typing `%` matches every species and typing `_` matches any character — a
    /// person searching for a cultivar with an underscore in it would get the whole catalogue back
    /// and no way to tell why. The escape character escapes itself first, or `\%` typed literally
    /// would come out as an unescaped wildcard.
    static func escapedForLike(_ query: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(query.count)
        for character in query {
            if character == "\\" || character == "%" || character == "_" {
                escaped.append("\\")
            }
            escaped.append(character)
        }
        return escaped
    }

    /// The curated field-guide list (BUILD-PLAN §8), for screen 08.
    ///
    /// ```
    /// SEARCH s USING INDEX idx_species_curated (curated=?)
    /// ```
    public func curated(limit: Int, connection: SQLiteConnection) throws -> [Species] {
        let sql = """
        SELECT \(Self.projection(identityColumn: schema.speciesIdentityColumn))
          FROM \(seed).species s
         WHERE s.curated = 1 AND s.deleted_at IS NULL
         ORDER BY s.common_name, s.scientific_name
         LIMIT :limit
        """
        let statement = try connection.cachedStatement(sql)
        _ = try statement.bind(limit, forName: ":limit")
        return try statement.fetchAll { try Self.decodeIfPresent($0) }.compactMap { $0 }
    }

    // MARK: - How common it is nearby (screen 07 §5)

    /// How many trees of this species the attached inventory holds — screen 07 §5's
    /// `In this inventory` card.
    ///
    /// ```
    /// SEARCH s USING COVERING INDEX sqlite_autoindex_species_1 (uuid=?)
    /// SEARCH t USING COVERING INDEX idx_trees_species_current (species_current=?)
    /// ```
    ///
    /// A `COUNT(*)` over the whole inventory, which is what makes the number printable at all:
    /// anything short of the whole attached file is the wrong number wearing the right label
    /// (ERRATA E38). It is not a count of user actions and D1 does not reach it — it counts trees
    /// the city planted, most of them before the app existed.
    ///
    /// **This predicate is not scoped to an id space, and the label no longer claims it is.** The
    /// built-in bundle is fused across `sf` and `us-ca-sj`, so on it this count spans two cities —
    /// Crape Myrtle is 97 + 3,649. The card said `In San Francisco` over that number until
    /// `RULINGS R48`. Adding an id-space predicate
    /// here would be the other candidate fix and the ruling declines it: screen 07 has no row to
    /// take an id space from.
    ///
    /// Vacant planting sites fall out for free: 12,518 of them carry no `species_current` at all
    /// (ERRATA E11), so a species-scoped count never includes a basin with nothing in it.
    public func cityTreeCount(speciesID: UUID, connection: SQLiteConnection) throws -> Int {
        let sql = """
        SELECT count(*) AS species_tree_count
          FROM \(seed).trees t
          JOIN \(seed).species s ON s.id = t.species_current
         WHERE s.\(schema.speciesIdentityColumn) = :uuid COLLATE NOCASE
           AND t.deleted_at IS NULL
        """
        let statement = try connection.cachedStatement(sql)
        _ = try statement.bind(speciesID.uuidString, forName: ":uuid")
        return try statement.fetchOne { try $0.int("species_tree_count") } ?? 0
    }

    /// The same count restricted to one area — 07 §5's `Near you` card.
    ///
    /// Takes the `AlmanacScope` the caller resolved rather than a coordinate, so the two decisions
    /// stay separable: which area you are in, and how many of these grow in it. Until R29 reached
    /// this screen it took a `neighborhoodID: Int` and wrote `t.neighborhood_id = :neighborhood` —
    /// San Francisco's 41 polygons and nothing else, so a San Jose reader's `Near you` card
    /// silently did not draw: the defect family E182 closed for screen 12. For a `.neighborhood`
    /// scope the rendered predicate is the identical string, so San Francisco's count cannot move.
    public func treeCount(
        speciesID: UUID,
        scope: AlmanacScope,
        connection: SQLiteConnection
    ) throws -> Int {
        let sql = """
        SELECT count(*) AS species_tree_count
          FROM \(seed).trees t
          JOIN \(seed).species s ON s.id = t.species_current
         WHERE s.\(schema.speciesIdentityColumn) = :uuid COLLATE NOCASE
           AND \(scope.predicate("t"))
           AND t.deleted_at IS NULL
        """
        let statement = try connection.cachedStatement(sql)
        _ = try statement.bind(scope.bindings.merging(
            [":uuid": speciesID.uuidString] as [String: SQLiteBindable?]
        ) { a, _ in a })
        return try statement.fetchOne { try $0.int("species_tree_count") } ?? 0
    }

    /// Which SF Analysis Neighborhood a coordinate sits in — A4's unit of "your area".
    ///
    /// ```
    /// SEARCH t USING INDEX idx_trees_lat_lon (lat>? AND lat<?)
    /// SEARCH n USING INTEGER PRIMARY KEY (rowid=?)
    /// ```
    ///
    /// **Resolved through the nearest inventoried tree, not through the polygon.** The seed carries
    /// `neighborhoods.geom_geojson`, so a point-in-polygon test is available in principle; what it
    /// would produce is a *second* answer to a question the seed has already answered 195,309 times
    /// — the city assigned every tree to a neighbourhood at ingest, and `trees.neighborhood_id` is
    /// that assignment. A ray-cast of mine that disagreed with it on a boundary block would make
    /// the count card and the map disagree about where you are, for no gain. See ERRATA (E44).
    ///
    /// `nil` when no inventoried tree is within `radiusM` — outside SF, or in the middle of the
    /// bay. Then there is no area, and the `Near you` card does not draw at all.
    public func resolveNeighborhood(
        near coordinate: Coordinate,
        radiusM: Double = 400,
        connection: SQLiteConnection
    ) throws -> (id: Int, name: String)? {
        let bounds = BoundingBox(around: coordinate, radiusM: radiusM)
        // The same squared-distance ordering `TreeQueries.nearest` uses: no sqrt, no trigonometry
        // per row, and monotonically identical to true distance over a box this size.
        let longitudeWeight = pow(cos(coordinate.latitude * .pi / 180), 2)

        let sql = """
        SELECT t.neighborhood_id AS neighborhood_id, n.name AS neighborhood_name
          FROM \(seed).trees t
          JOIN \(seed).neighborhoods n ON n.id = t.neighborhood_id
         WHERE t.lat BETWEEN :minLat AND :maxLat
           AND t.lon BETWEEN :minLon AND :maxLon
           AND t.deleted_at IS NULL
         ORDER BY (t.lat - :lat) * (t.lat - :lat)
                + (t.lon - :lon) * (t.lon - :lon) * :lonWeight
         LIMIT 1
        """
        let statement = try connection.cachedStatement(sql)
        _ = try statement.bind([
            ":minLat": bounds.minLatitude,
            ":maxLat": bounds.maxLatitude,
            ":minLon": bounds.minLongitude,
            ":maxLon": bounds.maxLongitude,
            ":lat": coordinate.latitude,
            ":lon": coordinate.longitude,
            ":lonWeight": longitudeWeight
        ])
        return try statement.fetchOne { row in
            (id: try row.int("neighborhood_id"), name: try row.string("neighborhood_name"))
        }
    }

    // MARK: - Projection and decoding

    /// The `species` projection, aliased so the decoder is shape-independent. Every consumer of
    /// `decodeIfPresent(_:)` selects exactly this.
    static func projection(identityColumn: String) -> String {
        """
        s.\(identityColumn) AS species_uuid,
               s.scientific_name AS species_scientific_name,
               s.common_name AS species_common_name,
               s.family AS species_family,
               s.leaf_retention AS species_leaf_retention,
               s.id_tips AS species_id_tips,
               s.seasonal AS species_seasonal,
               s.care_notes AS species_care_notes,
               s.curated AS species_curated,
               s.created_at AS species_created_at,
               s.updated_at AS species_updated_at
        """
    }

    /// Decodes a `Species` from a row produced by `projection(identityColumn:)`, or `nil` when the
    /// LEFT JOIN found nothing.
    ///
    /// `Species.init` validates (D5) and throws; a throw here is a content bug that must fail the
    /// read loudly rather than resolve to a half-built guide entry (`Core/Models/Species.swift`).
    static func decodeIfPresent(_ row: SQLiteRow) throws -> Species? {
        guard let id = try row.uuidIfPresent("species_uuid") else { return nil }
        let scientificName = try row.string("species_scientific_name")
        let seasonal = decodeSeasonal(try row.stringIfPresent("species_seasonal"))

        return try Species(
            id: id,
            scientificName: scientificName,
            // `common_name` is NULL for 11 of the 569 seeded species. The scientific name is the
            // honest fallback — inventing a common name would be fabricating content (§15).
            commonName: try row.stringIfPresent("species_common_name") ?? scientificName,
            family: try row.stringIfPresent("species_family"),
            leafRetention: leafRetention(stored: try row.stringIfPresent("species_leaf_retention")),
            idTips: decodeJSON([IDTip].self, try row.stringIfPresent("species_id_tips")) ?? [],
            seasonal: seasonal,
            careNotes: decodeCareNotes(try row.stringIfPresent("species_care_notes")),
            curated: try row.boolIfPresent("species_curated") ?? false,
            createdAt: try row.date("species_created_at"),
            updatedAt: try row.date("species_updated_at")
        )
    }

    /// Reads `species.leaf_retention`, which is NULL for 59 of the 569 seeded species.
    ///
    /// The column carries exactly the three strings of `LeafRetention` or SQL NULL, and NULL means
    /// no authoritative source states this species' habit (ERRATA E9, and the seed schema's own
    /// note beside the column). Nothing is resolved, substituted or inferred here: this read layer
    /// used to pick a value for the unauthored rows, and *any* pick is a botanical claim the record
    /// does not carry — `.deciduous` lets a fall-colour chip onto an unclassified tree, `.evergreen`
    /// asserts that 59 species keep their leaves through winter.
    ///
    /// An unrecognised string is also `nil` rather than a throw: the vocabulary is pinned by a
    /// database CHECK, so a value outside it means the seed and this enum have drifted, and losing
    /// a chip is the right failure for that. `Tools/verify_seed.py` check 17b is what catches it.
    static func leafRetention(stored: String?) -> LeafRetention? {
        stored.flatMap(LeafRetention.init(rawValue:))
    }

    // MARK: - JSON columns

    private static func decodeJSON<T: Decodable>(_ type: T.Type, _ json: String?) -> T? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// `species.seasonal` is `{bloom_months, fall_color_months, fruit_months, new_growth_months}`
    /// (BUILD-PLAN §4) — snake_case on the wire, camelCase in `Core`.
    static func decodeSeasonal(_ json: String?) -> SeasonalCalendar {
        guard let json, let data = json.data(using: .utf8) else { return .empty }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return (try? decoder.decode(SeasonalCalendar.self, from: data)) ?? .empty
    }

    /// `species.care_notes` is `[{month_range, text}]`, and `month_range` is itself
    /// `{start, end}` — a `MonthRange` whose failable initializer rejects a month outside 1…12.
    /// Malformed entries are dropped rather than failing the whole guide entry.
    static func decodeCareNotes(_ json: String?) -> [CareNote] {
        guard let json, let data = json.data(using: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return (try? decoder.decode([CareNote].self, from: data)) ?? []
    }
}
