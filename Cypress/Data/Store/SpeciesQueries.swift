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
