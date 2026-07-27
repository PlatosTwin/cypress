import Foundation

/// Which of San Francisco's street-tree inventories the shipped seed was built from, and **when it
/// was taken**.
///
/// ── Why this type exists ──────────────────────────────────────────────────────────────────
/// The seed is a ~63 MB file inside the app bundle. Nothing in the app could previously say where
/// its contents came from or how old they were, and that is precisely what made "is our data
/// stale?" unanswerable the last time it was asked: the file could have been a day old or a year
/// old and no screen, no log line and no reader of the database could tell the difference. A
/// snapshot with no date is not a small omission — it is the omission that turns every later
/// disagreement with the city's own map into an argument nobody can settle.
///
/// So the date travels with the data, from `seed_meta.trees_snapshot_on`, which
/// `Tools/build_seed.py` writes from the extraction's own record rather than from a clock at build
/// time. Rebuilding the same seed in 2030 still reports 2026.
///
/// ── The two inventories ───────────────────────────────────────────────────────────────────
/// San Francisco publishes its street trees twice and the two do not agree:
///
/// - **`city`** — SF Public Works' own operational layer, the one its public map at
///   <https://bsm.sfdpw.org/urbanforestry/> draws. 133,577 records, every one of them a tree.
/// - **`datasf`** — the open-data export `tkzw-k3nq`. 195,309 records, nine more columns, and
///   ~65,000 rows the city's own map does not show. What shipped before #91, still buildable with
///   `Tools/build_seed.py --source datasf`.
///
/// Both are the city's; neither is a superset of the other. `name` is the phrase the app puts on
/// screen and it names the *inventory*, never "San Francisco" alone — the distinction between the
/// two lists is the whole reason this type exists.
///
/// **The shipped seed holds rows from both**, which is why `init(id:seedMeta:)` exists beside
/// `init(seedMeta:)`. The city's layer decides which *trees* exist; it has no vacant-site category
/// at all, so the 12,260 empty planting sites are the export's rows and say so. A row's own source
/// is `trees.inventory_source`, and the seed-wide value is only the right answer for a seed built
/// from one inventory.
public struct InventorySource: Hashable, Sendable {

    /// The identifier `Tools/build_seed.py` was invoked with — `city` or `datasf`. Not shown to
    /// anyone; it exists so a log, a test or a support answer can name the build exactly.
    public let id: String

    /// The inventory's name, as the app says it: `SF Public Works street tree inventory`.
    public let name: String

    /// Where the records were read from. A service or dataset URL, for the record rather than for
    /// tapping — nothing in the app links to it.
    public let url: String

    /// **The day the records were taken from the city.** Not the build date, not today.
    ///
    /// Optional because a seed built before this key existed simply does not carry one, and an
    /// absent date must read as absent rather than as some plausible substitute. Every surface that
    /// draws provenance renders nothing at all when this is nil: a date the app made up would be
    /// worse than the silence it replaced.
    public let snapshotDate: Date?

    public init(id: String, name: String, url: String, snapshotDate: Date?) {
        self.id = id
        self.name = name
        self.url = url
        self.snapshotDate = snapshotDate
    }

    /// Builds from the seed's own build receipt (`seed_meta`), or `nil` when the receipt predates
    /// these keys.
    ///
    /// A receipt naming a source but carrying no date still produces a value, with `snapshotDate`
    /// nil. That is deliberate: half an answer is still an answer, and the missing half is visible
    /// as missing rather than papered over.
    public init?(seedMeta: [String: String]) {
        guard let id = seedMeta["trees_source"], !id.isEmpty else { return nil }
        self.id = id
        self.name = seedMeta["trees_source_name"] ?? id
        self.url = seedMeta["trees_source_url"] ?? ""
        self.snapshotDate = (seedMeta["trees_snapshot_on"]).flatMap(Self.date(fromISODay:))
    }

    /// **The inventory a single row came from**, by the identifier `trees.inventory_source` stores.
    ///
    /// The seed is no longer one inventory's file. Its living trees are SF Public Works' operational
    /// layer, and its 12,260 vacant planting sites are the DataSF export's, because the layer
    /// publishes no vacant-site category and so has nothing to say about them. Two inventories in
    /// one file means the seed-wide answer above is the wrong answer for some of its rows, and a
    /// provenance line is a claim about **this record** — putting the city's name and the city's
    /// snapshot date over a row the city has never listed is exactly the kind of quiet falsehood
    /// this type was added to end.
    ///
    /// Resolved from the `inventory_<id>_*` keys the build writes for every inventory the file
    /// actually holds rows from. A seed built before those keys existed falls back to the
    /// `trees_source_*` keys, which are right for it because every row in it came from one place.
    /// Nil when the receipt names neither, for the same reason the initializer above is failable:
    /// an unknown provenance must read as unknown.
    public init?(id: String, seedMeta: [String: String]) {
        guard !id.isEmpty else { return nil }
        if let name = seedMeta["inventory_\(id)_name"], !name.isEmpty {
            self.init(
                id: id,
                name: name,
                url: seedMeta["inventory_\(id)_url"] ?? "",
                snapshotDate: (seedMeta["inventory_\(id)_snapshot_on"]).flatMap(Self.date(fromISODay:))
            )
            return
        }
        guard seedMeta["trees_source"] == id else { return nil }
        self.init(seedMeta: seedMeta)
    }

    /// `2026-07-26` → a `Date` at UTC midnight. Nil for anything else, including an empty string.
    ///
    /// Deliberately strict and deliberately not `ISO8601DateFormatter`: the receipt writes a bare
    /// calendar day, and a parser that accepted a full timestamp would let a build with the wrong
    /// grain through unnoticed.
    static func date(fromISODay day: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: day)
    }
}
