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

    /// `GET /species?query=` — autocomplete over both names.
    ///
    /// BUILD-PLAN §6 specifies a trigram index on both names, which Postgres has and SQLite does
    /// not. The on-device equivalent is a **prefix** range scan against the two B-tree indexes the
    /// seed already carries, unioned:
    ///
    /// ```
    /// SEARCH s USING INTEGER PRIMARY KEY (rowid=?)
    /// LIST SUBQUERY 2
    ///   COMPOUND QUERY
    ///     LEFT-MOST SUBQUERY
    ///       SCAN species USING COVERING INDEX idx_species_scientific_name
    ///     UNION USING TEMP B-TREE
    ///       SCAN species USING COVERING INDEX idx_species_common_name
    /// USE TEMP B-TREE FOR ORDER BY
    /// ```
    ///
    /// The upper bound of each range is the query with `U+FFFF` appended: every string starting
    /// with the query sorts below it.
    ///
    /// **Note what the plan actually says: `SCAN … USING COVERING INDEX`, not a range `SEARCH`.**
    /// `COLLATE NOCASE` on the comparison does not match the `BINARY` collation the seed's indexes
    /// were built with, so SQLite cannot turn the range into a seek and walks the index instead. It
    /// is still a *covering* walk — the `species` table itself is never touched — over 569 rows, and
    /// it measures 0.1 ms. Dropping `COLLATE NOCASE` would restore the seek and break "quercus"
    /// matching "Quercus", which is the whole point of an autocomplete field. Rebuilding the seed's
    /// two name indexes `COLLATE NOCASE` would give both, and belongs in `Tools/build_seed.py`
    /// rather than in a client-side workaround; at 569 rows it buys nothing measurable today.
    ///
    /// **The gap versus §6.** Trigram matching finds "oak" inside "Coast Live Oak"; a prefix scan
    /// does not. Closing it needs an FTS5 index the seed does not carry, and building one on device
    /// over 569 rows at first launch is cheap — but the seed is read-only and the index belongs
    /// beside the data, so this is the ingest pipeline's to add, not the client's to fake.
    /// Recorded here rather than silently approximated.
    public func search(query: String, limit: Int, connection: SQLiteConnection) throws -> [Species] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let upperBound = trimmed + "\u{FFFF}"

        let sql = """
        SELECT \(Self.projection(identityColumn: schema.speciesIdentityColumn))
          FROM \(seed).species s
         WHERE s.id IN (
                 SELECT id FROM \(seed).species
                  WHERE scientific_name >= :q COLLATE NOCASE AND scientific_name < :qHi COLLATE NOCASE
                 UNION
                 SELECT id FROM \(seed).species
                  WHERE common_name >= :q COLLATE NOCASE AND common_name < :qHi COLLATE NOCASE
               )
           AND s.deleted_at IS NULL
         ORDER BY s.curated DESC, s.scientific_name
         LIMIT :limit
        """

        let statement = try connection.cachedStatement(sql)
        _ = try statement.bind([":q": trimmed, ":qHi": upperBound, ":limit": limit])
        return try statement.fetchAll { try Self.decodeIfPresent($0) }.compactMap { $0 }
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

    /// How many trees of this species the city inventory holds — screen 07 §5's `In San Francisco`
    /// card.
    ///
    /// ```
    /// SEARCH s USING COVERING INDEX sqlite_autoindex_species_1 (uuid=?)
    /// SEARCH t USING COVERING INDEX idx_trees_species_current (species_current=?)
    /// ```
    ///
    /// A `COUNT(*)` over the whole inventory, which is what makes the number printable at all: the
    /// card says "in San Francisco", so anything short of the whole city is the wrong number
    /// wearing the right label (ERRATA E38). It is not a count of user actions and D1 does not
    /// reach it — it counts trees the city planted, most of them before the app existed.
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

    /// The same count restricted to one neighbourhood — 07 §5's `Near you` card.
    ///
    /// Takes the neighbourhood `resolveNeighborhood(near:)` found rather than a coordinate, so the
    /// two decisions stay separable: which area you are in, and how many of these grow in it.
    public func neighborhoodTreeCount(
        speciesID: UUID,
        neighborhoodID: Int,
        connection: SQLiteConnection
    ) throws -> Int {
        let sql = """
        SELECT count(*) AS species_tree_count
          FROM \(seed).trees t
          JOIN \(seed).species s ON s.id = t.species_current
         WHERE s.\(schema.speciesIdentityColumn) = :uuid COLLATE NOCASE
           AND t.neighborhood_id = :neighborhood
           AND t.deleted_at IS NULL
        """
        let statement = try connection.cachedStatement(sql)
        _ = try statement.bind([":uuid": speciesID.uuidString, ":neighborhood": neighborhoodID])
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
