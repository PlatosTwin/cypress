import Foundation

/// The reads behind the Journal tab's `City` segment.
///
/// **Follows `AlmanacQueries`'s conventions exactly, and for the same reason: nothing in this file
/// counts a contribution.** Every count is over trees — trees of a species, trees whose planting the
/// city wrote down — never over visits, observations or care events.
///
/// ── The constraint this file exists to answer ──────────────────────────────────────────────────
/// The bundled inventory is **fused across two cities** (`sf` and `us-ca-sj`) under one attached
/// schema, with no `city_id` column — city membership is `trees.id_space`. `AlmanacQueries` never had
/// to reckon with this because every one of its reads is scoped to a neighborhood polygon or a radius
/// around the reader, and a neighborhood or a 1,200 m circle cannot itself span two cities that are
/// forty miles apart. A citywide read has no such shelter: `COUNT(*)` with no `id_space` predicate is
/// R48's defect exactly — a card that spans both cities under one city's name, or here, under no name
/// but still the wrong population. **So every query below either takes an `idSpace` and predicates on
/// it, or resolves one before it reads anything else.**
///
/// `resolveIDSpace(near:)` is that resolution: the `id_space` of the nearest inventoried tree, which
/// is a fact read off a row rather than a guess about which city a coordinate falls in. It is the
/// same shape as `SpeciesQueries.resolveNeighborhood(near:)` and is bounded by the same radius
/// `AlmanacQueries` already uses to decide whether the record reaches a reader at all
/// (`AlmanacLimits.fallbackRadiusM`, RULINGS R29) — a coordinate with no inventory within that
/// distance resolves no city, and the caller renders the almanac's own out-of-range state rather than
/// naming one.
///
/// **Nothing in this file, and nothing built on it, prints a city's proper name.** `id_spaces` carries
/// no display name for the city itself — `id` is `sf` / `us-ca-sj`, and `inventories.name` is the
/// *inventory's* published name ("City of San Jose Street Tree inventory"), the same string
/// `CityRecordCopy.provenanceNote` already uses per tree. Composing a city's name from that string, or
/// from the `id_space` key, is exactly the guess R28 and R48 closed the door on.
public struct CityQueries {
    private let schema: SeedSchema
    private let seed = SeedDatabase.schemaName

    public init(schema: SeedSchema) {
        self.schema = schema
    }

    /// A tree this file is willing to talk about: one the city believes is standing.
    ///
    /// Identical to `AlmanacQueries.standing` and kept as its own copy rather than a shared import
    /// for the reason that constant's own comment gives: it is the single line that keeps a vacant
    /// planting site out of every read below, and a file whose whole subject is "which trees may this
    /// screen count" is the file where that line has to be visible on its own, not reached through
    /// another type. 24,200 seed rows are `vacant_site`, and 9,237 of those carry a `planted_year` —
    /// the date of a tree that stood there and is gone — so a query that dropped this predicate would
    /// count some of them as trees.
    private static let standing = "t.status IN ('alive','declining')"

    // MARK: - Which city

    /// The `id_space` of the nearest inventoried tree within `radiusM`, or `nil` when no tree in the
    /// attached inventory is that close.
    ///
    /// **A fact read off a row, not an inference about a coordinate.** The alternative — deciding
    /// which city a `Coordinate` is "in" from its own latitude and longitude — would need a boundary
    /// dataset this app does not carry for every city it might one day hold (D16), and would be
    /// exactly the kind of guess R28 and R51 both closed the door on for a single tree's own screen.
    /// Asking the nearest row instead needs nothing beyond what is already attached, and degrades
    /// honestly: nothing near enough resolves to nothing, never to a plausible-looking wrong city.
    ///
    /// `radiusM` defaults to `AlmanacLimits.fallbackRadiusM` — the same distance `AlmanacScope`'s
    /// fallback uses to decide whether the almanac's record reaches a reader at all. Reusing it here
    /// means a coordinate that resolves a local scope for card 1 and a coordinate that resolves a city
    /// for cards 2 and 3 are answering the same question, over the same ground, and cannot disagree.
    ///
    /// `deleted_at IS NULL` is the only filter — not `Self.standing` — because a vacant planting site
    /// is still a real row in this city's inventory and still says which city the reader is standing
    /// in; excluding it would make sparse, mostly-vacant blocks resolve no city at all.
    public func resolveIDSpace(
        near coordinate: Coordinate,
        radiusM: Double,
        connection: SQLiteConnection
    ) throws -> String? {
        guard schema.hasIdSpace else { return nil }
        let bounds = BoundingBox(around: coordinate, radiusM: radiusM)
        // Longitude degrees are shorter than latitude degrees by cos(lat); squaring the ratio makes
        // the two terms comparable, exactly as `TreeQueries.nearest` does it.
        let longitudeWeight = pow(cos(coordinate.latitude * .pi / 180), 2)

        let statement = try connection.cachedStatement("""
            SELECT t.id_space AS id_space
              FROM \(seed).trees t
             WHERE t.lat BETWEEN :minLat AND :maxLat
               AND t.lon BETWEEN :minLon AND :maxLon
               AND t.deleted_at IS NULL
             ORDER BY (t.lat - :lat) * (t.lat - :lat)
                    + (t.lon - :lon) * (t.lon - :lon) * :lonWeight
             LIMIT 1
            """)
        _ = try statement.bind([
            ":minLat": bounds.minLatitude,
            ":maxLat": bounds.maxLatitude,
            ":minLon": bounds.minLongitude,
            ":maxLon": bounds.maxLongitude,
            ":lat": coordinate.latitude,
            ":lon": coordinate.longitude,
            ":lonWeight": longitudeWeight
        ])
        return try statement.fetchOne { try $0.string("id_space") }
    }

    // MARK: - Who lives here, citywide

    /// Every species the city inventory records across the whole `idSpace`, most common first.
    ///
    /// **`AlmanacQueries.speciesMix(scope:)`'s query, word for word, with one `WHERE` clause traded
    /// for another.** Every other predicate — the inner `JOIN` that excludes both vacant sites and
    /// the 312 seed-wide rows whose city label names no taxon, `deleted_at IS NULL`, `Self.standing`
    /// — is copied rather than referenced so this file makes no promise about staying in step with a
    /// query written for a different scope; the two are free to diverge if the neighborhood read ever
    /// needs something this one does not. See `AlmanacQueries.speciesMix` for why the inner `JOIN`
    /// is what excludes a vacant site (`species_current` is `NULL` on every one of them) rather than
    /// `Self.standing`, and why it is read whole rather than `LIMIT 3`: the composition card prints
    /// the header's species count and an "Everyone else" remainder, and a page would make the
    /// remainder wrong in the flattering direction (the same reasoning, unchanged).
    public func speciesMix(idSpace: String, connection: SQLiteConnection) throws -> [SpeciesShare] {
        let statement = try connection.cachedStatement("""
            SELECT s.\(schema.speciesIdentityColumn) AS species_uuid,
                   COALESCE(s.common_name, s.scientific_name) AS species_name,
                   COUNT(*) AS tree_count
              FROM \(seed).trees t
              JOIN \(seed).species s ON s.id = t.species_current
             WHERE t.id_space = :citySpace
               AND t.deleted_at IS NULL
               AND \(Self.standing)
             GROUP BY s.id
             ORDER BY tree_count DESC, species_name
            """)
        _ = try statement.bind([":citySpace": idSpace])
        return try statement.fetchAll { row in
            SpeciesShare(
                speciesID: try row.uuid("species_uuid"),
                name: try row.string("species_name"),
                treeCount: try row.int("tree_count")
            )
        }
    }

    // MARK: - The oldest on file

    /// The `limit` oldest standing trees in `idSpace` whose planting the city recorded, oldest first.
    ///
    /// **Three exclusions, each closing one way this list could mislead.**
    /// - `\(Self.standing)` excludes vacant planting sites — 9,237 of the seed's 24,200 carry a
    ///   `planted_year`, the date of a tree that stood there and is gone, and a list of "the oldest on
    ///   file" containing an empty hole in the ground is exactly the defect `TreeQueries.Narrowing`'s
    ///   own comment records having shipped once already. It also excludes `dead` and `removed`
    ///   trees, for the reason `AlmanacQueries.elder` does: this list is offered as places a reader
    ///   could go and look, the same as every other tree this screen counts.
    /// - `t.id_space = :citySpace` is R48's rule applied here: without it the list is not "this
    ///   city's oldest", it is whichever of the fused bundle's two cities happens to have older
    ///   paperwork, presented as one city's record.
    /// - `s.scientific_name NOT LIKE ':: %'` (or no species at all) excludes the seven seed-wide rows
    ///   whose species the ingest could not read (RULINGS R47, R54). A tree with no species keeps its
    ///   place — `CityCopy` falls back to its street, the same chain `AlmanacCopy.elderSubtitle`
    ///   already uses — but a stub species would put a raw ingest artifact like `9662` in front of the
    ///   reader as if it were this tree's name, on a list five times more exposed than the almanac's
    ///   single elder row — so the row is skipped and the next non-stub tree takes its place, rather
    ///   than being named by its position without a species.
    ///
    /// **`limit` is deliberately handed one higher than the card draws, by the caller.** This file
    /// does not decide how many rows are "the oldest" — that is whether the `limit + 1`th row ties the
    /// `limit`th one's year, which `CityPresentation` decides once it has both rows in hand, exactly
    /// the way `AlmanacPresentation` already treats `Series` reads it did not itself size.
    public func oldestOnFile(
        idSpace: String,
        limit: Int,
        connection: SQLiteConnection
    ) throws -> [(treeID: UUID, speciesCommonName: String?, address: String?, plantedYear: Int)] {
        let statement = try connection.cachedStatement("""
            SELECT t.\(schema.treeIdentityColumn) AS tree_uuid,
                   t.address AS address,
                   t.planted_year AS planted_year,
                   COALESCE(s.common_name, s.scientific_name) AS species_name
              FROM \(seed).trees t
              LEFT JOIN \(seed).species s ON s.id = t.species_current
             WHERE t.id_space = :citySpace
               AND t.planted_on IS NOT NULL
               AND t.deleted_at IS NULL
               AND \(Self.standing)
               AND (s.id IS NULL OR s.scientific_name NOT LIKE ':: %')
             ORDER BY t.planted_on
             LIMIT :limit
            """)
        _ = try statement.bind([
            ":citySpace": idSpace,
            ":limit": limit
        ] as [String: SQLiteBindable?])
        return try statement.fetchAll { row in
            (
                treeID: try row.uuid("tree_uuid"),
                speciesCommonName: try row.stringIfPresent("species_name"),
                address: try row.stringIfPresent("address"),
                plantedYear: try row.int("planted_year")
            )
        }
    }
}
