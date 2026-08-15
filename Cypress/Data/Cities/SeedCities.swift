import Foundation
import SQLite3

/// Which cities a seed or city file holds, and at what record date — read out of the file itself.
///
/// **The app could not previously answer this about its own bundle.** `CityLibrary` reads
/// `Application Support/Cypress/cities/`, which is the record of what was *downloaded*; the
/// bundled seed is installed in every sense a reader cares about and in none the directory layout
/// can express, so the Cities screen offered an 81 MB download of a city whose trees were on the
/// map at that moment. This type is the missing read.
///
/// Nothing here is invented (DECISIONS constraint 15). Every value is authored data lifted out of
/// a file:
///
/// - **which cities** — `id_spaces.id`;
/// - **the name** — `dim_city.display_name` joined through `id_spaces.city_id` (s16), falling back
///   to `id_spaces.short_name` (s15) and then to nothing at all. Never composed from the id;
/// - **the record date** — `Tools/publish_cities.py`'s own `content_rev_for` rule, applied to a
///   different file. The publisher pairs `seed_meta.inventory_<tag>_id_space` with
///   `inventory_<tag>_snapshot_on` and takes the newest; so does `contentRev(forIDSpace:seedMeta:)`
///   below. Run against the shipped bundle it yields `2026-07-31` for both spaces, which is exactly
///   the `r2026-07-31` in both published version strings.
///
/// **Deliberately not read: anything that would need the file's bytes hashed.** R60 makes a
/// version string's `build_id` the first 8 hex of the source seed's sha256, so a bundled city
/// cannot state its own published version without hashing 108 MB at launch. The comparison is
/// `content_rev` alone (a date, which orders) and the row says only what that supports.
public enum SeedCities {

    /// One city inside a seed or city file.
    public struct City: Equatable, Sendable {
        /// `id_spaces.id` — `sf`, `us-ca-sj`. The same key the manifest and the library use.
        public let id: String
        /// The city's own name as the file states it, or nil when the file is too old to carry one.
        public let displayName: String?
        /// The newest snapshot date among this city's inventories, by the publisher's rule.
        public let contentRev: String?

        public init(id: String, displayName: String?, contentRev: String?) {
            self.id = id
            self.displayName = displayName
            self.contentRev = contentRev
        }
    }

    /// The cities in the app's bundled seed, or `[]` when there is no bundle to read (a unit-test
    /// bundle without the ~103 MB resource, which is a legitimate configuration here).
    ///
    /// Reads the file rather than remembering an answer: the bundle is swapped by a build, and a
    /// constant listing its cities is a comment that would go stale exactly when it mattered.
    public static func inBundle(_ bundle: Bundle = .main) -> [City] {
        guard let url = SeedDatabase.urlInBundle(bundle) else { return [] }
        return read(fileAt: url)
    }

    /// The cities in one seed or city file. Never throws: a file that cannot be opened, or that
    /// predates `id_spaces` entirely, holds no cities this type can name, and the caller's honest
    /// rendering of that is the same as for a file that is not there.
    public static func read(fileAt url: URL) -> [City] {
        guard let connection = try? SQLiteConnection(
            path: SeedDatabase.readOnlyURI(for: url),
            flags: SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOMUTEX
        ) else { return [] }
        return (try? read(from: connection)) ?? []
    }

    /// The same read against an already-open connection, against `main`.
    static func read(from connection: SQLiteConnection) throws -> [City] {
        guard try connection.tableExists("id_spaces") else { return [] }

        let idSpaceColumns = try connection.columnNames(ofTable: "id_spaces")
        // The same chain `TreeQueries.treeSQL()` documents, for the same reason: ask the file what
        // it carries rather than trust a version integer stamped somewhere else. A v16 file has
        // `dim_city` and no `short_name`; a v15 file has `short_name` and no `dim_city`; a v14 file
        // has neither and gets no name at all rather than a prettier one this layer made up.
        let hasDimCity = try connection.tableExists("dim_city") && idSpaceColumns.contains("city_id")
        let hasShortName = idSpaceColumns.contains("short_name")

        let nameExpression: String
        switch (hasDimCity, hasShortName) {
        case (true, true): nameExpression = "COALESCE(dc.display_name, isp.short_name)"
        case (true, false): nameExpression = "dc.display_name"
        case (false, true): nameExpression = "isp.short_name"
        case (false, false): nameExpression = "NULL"
        }
        let join = hasDimCity ? "LEFT JOIN dim_city dc ON dc.id = isp.city_id" : ""

        let statement = try connection.prepare("""
            SELECT isp.id AS id, \(nameExpression) AS display_name
              FROM id_spaces isp
              \(join)
             ORDER BY isp.id
            """)
        defer { statement.finalize() }
        let named = try statement.fetchAll {
            (id: try $0.string("id"), displayName: try $0.stringIfPresent("display_name"))
        }

        let meta = try seedMeta(from: connection)
        return named.map {
            City(
                id: $0.id,
                displayName: $0.displayName,
                contentRev: contentRev(forIDSpace: $0.id, seedMeta: meta)
            )
        }
    }

    /// `seed_meta` as a dictionary, or empty when the file predates the build receipt.
    private static func seedMeta(from connection: SQLiteConnection) throws -> [String: String] {
        guard try connection.tableExists("seed_meta") else { return [:] }
        let statement = try connection.prepare("SELECT key, value FROM seed_meta")
        defer { statement.finalize() }
        let pairs = try statement.fetchAll {
            (key: try $0.string("key"), value: try $0.stringIfPresent("value") ?? "")
        }
        return Dictionary(pairs.map { ($0.key, $0.value) }, uniquingKeysWith: { _, later in later })
    }

    /// `Tools/publish_cities.py`'s `content_rev_for`, transliterated: the newest snapshot date among
    /// the inventories that declare themselves part of `space`.
    ///
    /// **Paired by tag, never by a fixed tag list** — the publisher's own comment says why, and the
    /// bundle's receipt proves it: `sf` is carried by two inventories (`sf_city` at 2026-07-31 and
    /// `sf_datasf` at 2026-07-20) and `us-ca-sj` by one. Hard-coding the tags would silently drop a
    /// city the next ingest adds.
    ///
    /// The rule lives in two files now, which is a real cost. It is paid rather than avoided
    /// because the alternative — a new `seed_meta` key, or a manifest field the bundle could read —
    /// is a schema change in a version space, and Stage 0's defining property is that it makes none.
    /// `BundledCityTests.bundledSeedNamesItsCities` is what keeps the two honest:
    /// it reads the shipped bundle and asserts the answer against the published `content_rev`.
    static func contentRev(forIDSpace space: String, seedMeta: [String: String]) -> String? {
        let prefix = "inventory_"
        let suffix = "_id_space"
        var dates: [String] = []
        for (key, value) in seedMeta
        where key.hasPrefix(prefix) && key.hasSuffix(suffix) && value == space {
            let tag = String(key.dropFirst(prefix.count).dropLast(suffix.count))
            if let snapshot = seedMeta["\(prefix)\(tag)_snapshot_on"], !snapshot.isEmpty {
                dates.append(snapshot)
            }
        }
        return dates.max()
    }
}
