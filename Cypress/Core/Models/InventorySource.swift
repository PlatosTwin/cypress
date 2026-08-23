import Foundation

/// Which street-tree inventory a seed row came from, and **when it was taken**.
///
/// ── Why this type exists ──────────────────────────────────────────────────────────────────
/// The seed is a large file inside the app bundle. Nothing in the app could previously say where
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
/// ── The inventories, and their identifiers ────────────────────────────────────────────────
/// **The vocabulary is `trees.inventory_source`, and it is a foreign key into the seed's own
/// `inventories` table — read it there, never from this comment.** The shipped seed registers
/// three, across two cities:
///
/// - **`sf_city`** — SF Public Works' own operational layer, the one its public map at
///   <https://bsm.sfdpw.org/urbanforestry/> draws. Every record in it is a tree.
/// - **`sf_datasf`** — San Francisco's open-data export `tkzw-k3nq`: more columns, and tens of
///   thousands of rows the city's own map does not show. What shipped alone before #91.
/// - **`sj_street_tree`** — the City of San José Street Tree inventory (#129, ERRATA E176).
///
/// The two San Francisco lists are both the city's, and neither is a superset of the other. `name`
/// is the phrase the app puts on screen and it names the *inventory*, never a city alone — that
/// distinction is the whole reason this type exists, and it got sharper rather than softer when a
/// second city landed (RULINGS R28).
///
/// **These identifiers were renamed by the v14 seed pass**, from a bare `city` / `datasf` that
/// could not survive a second city's `city`. A comment or a test naming the bare forms as the
/// current column values is describing a file that no longer ships; `InventoryContractTests`
/// documents the rename and `SeedCorpus.current(_:)` still accepts both so a pre-v14 seed resolves.
///
/// **The shipped seed holds rows from all three**, which is why `init(id:seedMeta:)` exists beside
/// `init(seedMeta:)`. San Francisco's city layer decides which SF *trees* exist; it has no
/// vacant-site category at all, so the empty planting sites among the SF rows are the export's and
/// say so. A row's own source is `trees.inventory_source`, and the seed-wide value is only the
/// right answer for a seed built from one inventory — which, under **D16**, is the case that is
/// going away rather than the norm.
public struct InventorySource: Hashable, Sendable {

    /// An `inventories.id` — `sf_city`, `sf_datasf`, `sj_street_tree` on the seed that ships, and
    /// whatever the `inventories` table holds on one that does not. Not shown to anyone; it exists
    /// so a log, a test or a support answer can name the build exactly.
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
    ///
    /// **A name that is present and empty is not a name, and this initializer used to accept one.**
    /// Its per-inventory sibling below has always guarded `!name.isEmpty`; this one did not, so a
    /// receipt carrying `trees_source_name` as `""` produced a value whose `name` was `""` — and
    /// `name` is documented as "the phrase the app puts on screen", read by every surface that draws
    /// provenance. The visible results were `Recorded dead in the .` on the tree profile's dead
    /// notice, and `From the , 26 July 2026.` on the city-record provenance line; the subtitle's
    /// `?? unnamedCityInventory` never fired, because the value was not nil, only unsayable.
    ///
    /// Nil is the right answer rather than falling back to `id`: `id` is documented "Not shown to
    /// anyone", and every caller of this type already has a correct path for an inventory it cannot
    /// name — the subtitle and the dead notice say `city inventory`, and the provenance line renders
    /// nothing at all, which is the same discipline `snapshotDate` keeps for an absent date. Narrow
    /// by construction: an *absent* key still yields `id`, which is non-empty by the guard above, so
    /// this can only fire on a receipt that wrote the key empty.
    public init?(seedMeta: [String: String]) {
        guard let id = seedMeta["trees_source"], !id.isEmpty else { return nil }
        let name = seedMeta["trees_source_name"] ?? id
        guard !name.isEmpty else { return nil }
        self.id = id
        self.name = name
        self.url = seedMeta["trees_source_url"] ?? ""
        self.snapshotDate = (seedMeta["trees_snapshot_on"]).flatMap(Self.date(fromISODay:))
    }

    /// **The inventory a single row came from**, by the identifier `trees.inventory_source` stores.
    ///
    /// The seed is no longer one inventory's file. Its San Francisco trees are SF Public Works'
    /// operational layer, the SF vacant planting sites among them are the DataSF export's because
    /// that layer publishes no vacant-site category, and since #129 the rest is San José's. Several
    /// inventories in one file means the seed-wide answer above is wrong for some of its rows, and a
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
