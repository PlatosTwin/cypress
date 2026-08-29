import Foundation

/// **What the reader may choose to read stats about, and what a choice resolves to.**
///
/// The two segments of the Journal that carry aggregates — screen 12's almanac and the `City`
/// segment — used to have exactly one area each, resolved from the nearest inventoried tree. This
/// file is the other half: the list of areas the live inventories can actually answer for, and the
/// resolution of one the reader picked.
///
/// ── One denominator, not two ──────────────────────────────────────────────────────────────────
/// Every count below is the count the screen it feeds already prints. `neighborhoods()` counts what
/// `AlmanacQueries.speciesMix(scope:)` sums to for the same area — the inner `JOIN` on
/// `species_current`, `deleted_at IS NULL`, and `Self.standing`, all three copied and none
/// paraphrased. `cities()` counts what `CityQueries.speciesMix(idSpace:)` sums to. A picker row that
/// said `12,014 trees` over a card that then said `11,026` would be two answers to one question,
/// and the reader has no way to tell which is the real one. See ERRATA E115 for why widening the
/// join by one clause moves the number by 52 and breaks RULINGS R5's 215 at the same time.
///
/// ── Why a city has a name here and `CityQueries` says it has none ─────────────────────────────
/// `CityQueries`'s header states that "nothing in this file, and nothing built on it, prints a
/// city's proper name", because `id_spaces` carried no display name and `inventories.name` names
/// the *inventory* rather than the city. **That was true when it was written and stopped being true
/// at seed schema 16** (task #237), which added `dim_city` — slug, display name, state, county —
/// with `id_spaces.city_id` pointing into it. `SeedCities` and `CityDownloadsPresentation` already
/// read it, and the Cities screen has printed `San Francisco` and `San Jose` from it since s16.
/// So this file joins through it, and reads a name rather than composing one, which is the thing
/// R28 and R48 actually closed the door on.
///
/// **A file with no `dim_city` offers no cities at all.** `SeedSchema.hasDimCity` gates the read,
/// and the fallback is an empty list rather than a name built out of the id space's key — the
/// picker simply does not appear. Naming a city `us-ca-sj` would be exactly the guess this whole
/// area is written to avoid.
public struct AreaQueries {

    private let schema: SeedSchema
    private let seed = SeedDatabase.schemaName

    public init(schema: SeedSchema) {
        self.schema = schema
    }

    /// A tree these lists are willing to count: one the city believes is standing.
    ///
    /// `AlmanacQueries.standing` and `CityQueries.standing`, a third time and for the third time as
    /// its own copy — see either of their comments. The single line that keeps a vacant planting
    /// site out of a count has to be visible in the file that does the counting.
    private static let standing = "t.status IN ('alive','declining')"

    // MARK: - The neighborhood list

    /// Every neighborhood any live inventory carries that holds at least one standing, identified
    /// tree, most trees first.
    ///
    /// ```
    /// SCAN t
    /// SEARCH s USING INTEGER PRIMARY KEY (rowid=?)
    /// SEARCH n USING INTEGER PRIMARY KEY (rowid=?)
    /// ```
    ///
    /// **A neighborhood with no countable tree is not offered.** Picking it would open a screen
    /// whose every block is absent — the state screen 12 draws when the record does not reach you —
    /// under a name that promises otherwise. Grouping by `t.neighborhood_id` rather than listing
    /// `neighborhoods` and joining outward is what makes that automatic: a polygon no tree points at
    /// produces no row.
    ///
    /// Ordered by count and then by name, so the list is stable across two runs over one seed and
    /// the largest neighborhoods — the ones a reader is most likely to want — are not buried under
    /// an alphabet.
    public func neighborhoods(connection: SQLiteConnection) throws -> [NeighborhoodChoice] {
        let statement = try connection.cachedStatement("""
            SELECT n.id AS neighborhood_id,
                   n.name AS neighborhood_name,
                   COUNT(*) AS tree_count
              FROM \(seed).trees t
              JOIN \(seed).species s ON s.id = t.species_current
              JOIN \(seed).neighborhoods n ON n.id = t.neighborhood_id
             WHERE t.deleted_at IS NULL
               AND \(Self.standing)
             GROUP BY n.id
             ORDER BY tree_count DESC, neighborhood_name
            """)
        return try statement.fetchAll { row in
            NeighborhoodChoice(
                id: try row.int("neighborhood_id"),
                name: try row.string("neighborhood_name"),
                treeCount: try row.int("tree_count")
            )
        }
    }

    /// One neighborhood by its id: the name to print and a center to order distances from.
    ///
    /// `nil` when no live inventory carries that id — which is a state a reader reaches without
    /// doing anything wrong, by picking a neighborhood inside a downloaded pack and then removing
    /// the pack. The caller falls back to `.here` rather than drawing a named screen with nothing
    /// under it.
    ///
    /// **The center is the midpoint of the polygon's own stored bounding box**, not the reader's
    /// position and not a centroid computed from `geom_geojson`. It is a fact the seed already
    /// carries (`min_lat`/`max_lat`/`min_lon`/`max_lon`, written at ingest), it needs no geometry
    /// pass at read time, and it is the *same* point for everybody looking at that neighborhood —
    /// which is the property the ordering it feeds has to have. A "nearest planting site" ordered
    /// from the reader would answer, for a neighborhood across town, with a list sorted by which
    /// edge of it faces the reader.
    public func neighborhood(
        id: Int,
        connection: SQLiteConnection
    ) throws -> (name: String, center: Coordinate)? {
        let statement = try connection.cachedStatement("""
            SELECT n.name AS neighborhood_name,
                   n.min_lat AS min_lat, n.max_lat AS max_lat,
                   n.min_lon AS min_lon, n.max_lon AS max_lon
              FROM \(seed).neighborhoods n
             WHERE n.id = :id
            """)
        _ = try statement.bind([":id": id])
        return try statement.fetchOne { row in
            (
                name: try row.string("neighborhood_name"),
                center: Coordinate(
                    latitude: (try row.double("min_lat") + (try row.double("max_lat"))) / 2,
                    longitude: (try row.double("min_lon") + (try row.double("max_lon"))) / 2
                )
            )
        }
    }

    // MARK: - The city list

    /// Every city any live inventory carries, most trees first, named from `dim_city`.
    ///
    /// Empty — and therefore no city picker at all — when the attached record has no `id_space`
    /// column or no `dim_city` table. See the type's header: a city without a name on file is not
    /// offered under an invented one.
    public func cities(connection: SQLiteConnection) throws -> [CityChoice] {
        guard schema.hasIdSpace, schema.hasDimCity else { return [] }
        let statement = try connection.cachedStatement("""
            SELECT t.id_space AS id_space,
                   dc.display_name AS city_name,
                   COUNT(*) AS tree_count
              FROM \(seed).trees t
              JOIN \(seed).species s ON s.id = t.species_current
              JOIN \(seed).id_spaces isp ON isp.id = t.id_space
              JOIN \(seed).dim_city dc ON dc.id = isp.city_id
             WHERE t.deleted_at IS NULL
               AND \(Self.standing)
             GROUP BY t.id_space
             ORDER BY tree_count DESC, city_name
            """)
        return try statement.fetchAll { row in
            CityChoice(
                id: try row.string("id_space"),
                name: try row.string("city_name"),
                treeCount: try row.int("tree_count")
            )
        }
    }

    /// The display name of one id space, or `nil` when no live inventory carries it — the removed-
    /// pack case `neighborhood(id:)` documents, one level up.
    public func city(idSpace: String, connection: SQLiteConnection) throws -> String? {
        guard schema.hasIdSpace, schema.hasDimCity else { return nil }
        let statement = try connection.cachedStatement("""
            SELECT dc.display_name AS city_name
              FROM \(seed).id_spaces isp
              JOIN \(seed).dim_city dc ON dc.id = isp.city_id
             WHERE isp.id = :idSpace
            """)
        _ = try statement.bind([":idSpace": idSpace])
        return try statement.fetchOne { try $0.string("city_name") }
    }
}
