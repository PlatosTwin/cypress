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
///   the `r2026-07-31` in both published version strings. **It can legitimately be nil** — see that
///   method's note on where the transliteration stops;
/// - **the coverage word** — `seed_meta`, by the publisher's `COVERAGE_KEYS` rule
///   (`coverage(forIDSpace:seedMeta:)`).
///
/// **Deliberately not read: anything that would need the file's bytes hashed.** R60 makes a
/// version string's `build_id` the first 8 hex of the source seed's sha256, so a bundled city
/// cannot state its own published version without hashing 108 MB at launch. The comparison is
/// `content_rev` alone (a date, which orders) and the row says only what that supports.
public enum SeedCities {

    /// One city inside a seed or city file.
    ///
    /// **Presence is the `id`; every other field is optional and may legitimately be absent.** A
    /// caller deciding whether the bundle holds a city must ask whether it has a `City` at all,
    /// never whether that city has a date. Those were briefly the same question here, and that is
    /// precisely how the `Download` button came back for a bundled city — see
    /// `CityInstallState.bundled`.
    public struct City: Equatable, Sendable {
        /// `id_spaces.id` — `sf`, `us-ca-sj`. The same key the manifest and the library use.
        public let id: String
        /// The city's own name as the file states it, or nil when the file is too old to carry one.
        public let displayName: String?
        /// The newest snapshot date among this city's inventories, by the publisher's rule, or nil
        /// when the file's own receipt does not support one.
        ///
        /// **In a published city file this is the publisher's own `publish_content_rev`**, which it
        /// writes into `seed_meta` for exactly the pack it just narrowed; the per-inventory rule
        /// below is the fallback, and the only thing the *bundled* seed can answer with. Both
        /// name the same fact — see `contentRev(forIDSpace:seedMeta:idSpaceCount:)`.
        public let contentRev: String?
        /// The shipped extent's word (`downtown`), or nil for full coverage — the same meaning, from
        /// the same `seed_meta` keys, that the manifest's `coverage` field carries.
        public let coverage: String?
        /// `seed_meta.publish_schema_version` — the seed generation the publisher stamped into this
        /// file. Nil in the bundled seed, which `publish_cities.py` never touched.
        ///
        /// Read for one reason: **`content_rev` alone cannot tell a re-publish from a new schema
        /// generation.** A city republished at the same record date under a newer generation is a
        /// genuine update; the same date under the same generation is not. See `CityInstallState`.
        public let publishedSchemaVersion: Int?

        public init(
            id: String,
            displayName: String?,
            contentRev: String?,
            coverage: String? = nil,
            publishedSchemaVersion: Int? = nil
        ) {
            self.id = id
            self.displayName = displayName
            self.contentRev = contentRev
            self.coverage = coverage
            self.publishedSchemaVersion = publishedSchemaVersion
        }
    }

    /// The app bundle's cities, read **once per process**.
    ///
    /// A `static let` rather than a call, because `CityDownloadsModel`'s default argument is
    /// evaluated inside a `ViewBuilder` switch arm (`RootView`'s `case .cityDownloads`), which is
    /// produced on every pass over that switch while `_model = State(wrappedValue:)` keeps only the
    /// first. The read is two small queries against a two-row table and no hitch was measured; it
    /// is cached because the property that consumes it says "once", and an invariant a comment
    /// states is one the code should hold.
    ///
    /// Only `Bundle.main` is cached. `inBundle(_:)` with an explicit bundle re-reads, because a
    /// caller naming a bundle is asking about that file rather than about this process.
    public static let inMainBundle: [City] = inBundle(.main)

    /// The cities in a bundle's seed, or `[]` when there is no bundle to read (a unit-test bundle
    /// without the ~103 MB resource, which is a legitimate configuration here).
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
        let publishedSchemaVersion = meta["publish_schema_version"].flatMap(Int.init)
        return named.map {
            City(
                id: $0.id,
                displayName: $0.displayName,
                contentRev: contentRev(
                    forIDSpace: $0.id, seedMeta: meta, idSpaceCount: named.count
                ),
                coverage: coverage(forIDSpace: $0.id, seedMeta: meta),
                publishedSchemaVersion: publishedSchemaVersion
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
    ///
    /// **Where the transliteration deliberately stops, and what the caller owes it.** The empty
    /// check matches the publisher's `if snap:`, and it is load-bearing: `Tools/build_seed.py`
    /// writes San Jose's date as `sj_meta.get("extracted_on", "")` — an empty-string default with
    /// no `die()` behind it, unlike the San Francisco path — so a bundle really can ship a city
    /// whose date does not derive. The publisher's response to that is to `fail()` the whole
    /// publish; this method's is to return nil, because refusing to answer is not something a read
    /// on a reader's phone can usefully do. **Nil therefore means "no date", never "no city",** and
    /// a caller that reads it as absence re-opens the defect this whole type exists to close.
    ///
    /// **`publish_content_rev` wins when the file is one pack**, and that is not a shortcut around
    /// the rule — it is the publisher's own answer to it. `Tools/publish_cities.py` computes
    /// `content_rev_for(space, …)` for the pack it has just narrowed and writes the result into
    /// `seed_meta.publish_content_rev` (its `additions` block), so the stamped value *is* this rule
    /// applied by the program that owns it, and it is the same string the manifest entry carries.
    /// Reading it back beats re-deriving it, for a reason that cost a tester report: the narrowed
    /// file's surviving `inventory_*_snapshot_on` keys are the **fused** build receipt, not the
    /// pack's, so a borough split can re-derive a date that never described this pack.
    ///
    /// **Guarded on a single id space** (`idSpaceCount == 1`), because the stamped key names one
    /// pack and a file holding two id spaces has no single answer to attribute it to. R37.3 narrows
    /// every published file to one, so the guard is satisfied wherever the key exists; the fused
    /// bundled seed holds two id spaces and carries no `publish_*` key at all, and falls through to
    /// the per-inventory rule below, which is the only thing it can answer with.
    static func contentRev(
        forIDSpace space: String,
        seedMeta: [String: String],
        idSpaceCount: Int = 1
    ) -> String? {
        if idSpaceCount == 1, let stamped = seedMeta["publish_content_rev"], !stamped.isEmpty {
            return stamped
        }
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

    /// `Tools/publish_cities.py`'s `COVERAGE_KEYS` lookup, transliterated: the `seed_meta` key that
    /// states this city's shipped extent, or nil for full coverage.
    ///
    /// **Two keys, in the order R37 plans to retire them.** The standardized `coverage_<id_space>`
    /// is preferred; `legacyCoverageKeys` is the publisher's own per-city shim, which its comment
    /// describes as lasting *"until `build_seed.py` standardizes on `coverage_<id_space>`"*. R37's
    /// trailing clause says the same, and names a third city as the trigger. Preferring the
    /// standardized key means the day `build_seed.py` writes it, this reader is already correct and
    /// the shim below is dead rather than wrong.
    ///
    /// The shim is a hand-entered table duplicated across two languages, which is a cost worth
    /// naming: if a city is added to `COVERAGE_KEYS` and not here, its bundled row silently claims
    /// full coverage. `BundledCityTests.everyPublisherCoverageKeyIsMirrored` is the guard —
    /// it reads the shipped bundle and asserts the answer against the live manifest's own word.
    static func coverage(forIDSpace space: String, seedMeta: [String: String]) -> String? {
        for key in ["coverage_\(space)"] + Array(legacyCoverageKeys[space].map { [$0] } ?? []) {
            if let value = seedMeta[key], !value.isEmpty { return value }
        }
        return nil
    }

    /// `publish_cities.py`'s `COVERAGE_KEYS`, mirrored. Absent id ⇒ full coverage.
    static let legacyCoverageKeys: [String: String] = ["us-ca-sj": "sj_ship_extent"]
}
