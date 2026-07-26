import Foundation
import Testing
@testable import Cypress

/// The numbers that are properties of **San Francisco's inventory**, not of our code.
///
/// ── Why this exists ───────────────────────────────────────────────────────────────────────
/// A dozen suites pin exact counts against the shipped seed — 12,518 vacant sites, 588 distinct
/// plot sizes, 195,309 rows — and they are right to. Those literals are what catch a `.strip()`
/// that starts eating values or a join that quietly widens; "greater than zero" would catch none of
/// it. But they were written when there was one possible seed, and since #91 there are two:
///
/// - `city`   — SF Public Works' own operational layer, 133,577 records. What ships.
/// - `datasf` — the open-data export `tkzw-k3nq`, 195,309 records. Still buildable with
///              `Tools/build_seed.py --source datasf`, and still required to work, because the
///              owner may default back to it.
///
/// A literal in a test body can only be right about one of them. So the literals move here, keyed
/// by the source the seed's own build receipt names, and each suite asks for the corpus it is
/// actually running against. **Both sets stay pinned to exact numbers** — this is not a loosening.
/// Rebuilding either seed and getting different numbers still fails.
///
/// ── The harder half: controls that cannot fire ────────────────────────────────────────────
/// Some of these suites do not merely count. They assert a *control* — "this neighbourhood does
/// have dated plantings", "a row with all six columns set decodes to a city record" — and the
/// control is what proves the assertion above it measured something. The city's layer publishes
/// nine fewer columns than the export, so under `city` there are no planting dates anywhere, no
/// legal status and no plot sizes, and a control that reads them cannot fire.
///
/// Rewriting those controls to expect zero would be the worst available outcome: the suite would go
/// green while testing nothing, which is precisely the failure ARCHITECTURE §7 records about
/// grepping for a DEBUG symbol without a control string. So `publishes(_:)` answers whether the
/// running corpus can support a given claim, the affected tests say out loud which half they are
/// running, and the *absence* is asserted against `seed_meta.columns_absent_from_source` — a key the
/// generator writes — so a column that goes empty by accident still fails.
struct SeedCorpus: Sendable {

    /// `city` or `datasf`, from `seed_meta.trees_source`.
    let source: String

    /// Columns the source does not publish, from `seed_meta.columns_absent_from_source`. The DataSF
    /// names, because that is the vocabulary the schema comments and BUILD-PLAN §7 use.
    let absentColumns: Set<String>

    // ── Whole-corpus counts ──────────────────────────────────────────────────────────────────
    let trees: Int
    let species: Int
    let vacantSites: Int
    /// Populations of the six city columns #67 added, keyed by seed column name.
    let cityColumnRows: [String: Int]
    /// Distinct `plot_size` strings, and how the presentation splits them.
    let distinctPlotSizes: Int
    let plotSizesShown: Int
    let plotSizesRefused: Int
    /// `LandContext.inferred(from:)` over the whole corpus. `nil` counts rows the mapping cannot
    /// place — which under `city` is every row, because it reads two columns the layer lacks.
    let landContextStreet: Int
    let landContextPrivate: Int
    let landContextOtherPublic: Int
    let landContextCityPark: Int
    let landContextUnplaced: Int
    /// Neighbourhoods that hold trees but no vacant planting site.
    let neighborhoodsWithNoVacantSite: Int

    // ── Sunset/Parkside, the neighbourhood the almanac suites read ───────────────────────────
    let sunsetVacantSites: Int
    /// Standing trees that join a species (the inner join) and that do not (the left join).
    let sunsetTreesWithSpecies: Int
    let sunsetTreesLeftJoined: Int
    let sunsetSpeciesInMix: Int

    // ── The map ─────────────────────────────────────────────────────────────────────────────
    /// The densest screenful `MapDetailTests` measures must exceed this. It is a floor on how much
    /// the budget has to cope with, so it moves with the corpus.
    let densestScreenfulFloor: Int

    /// Whether the running corpus publishes a given DataSF column, and can therefore support a
    /// control that reads it.
    func publishes(_ column: String) -> Bool { !absentColumns.contains(column) }

    /// Reads the corpus for whichever seed is attached.
    static func current(_ store: CypressStore) async throws -> SeedCorpus {
        let meta = try await store.queue.read { connection in
            CypressStore.readSeedMeta(connection: connection)
        }
        let source = meta["trees_source"] ?? "datasf"
        let absent = Set((meta["columns_absent_from_source"] ?? "")
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty })
        switch source {
        case "city": return .city(absentColumns: absent)
        case "datasf": return .dataSF(absentColumns: absent)
        default:
            Issue.record("seed_meta.trees_source is '\(source)', which no corpus is pinned for")
            return .dataSF(absentColumns: absent)
        }
    }

    /// **SF Public Works' own street tree inventory**, extracted 2026-07-26. What ships.
    ///
    /// Five of the six #67 columns are zero and that is the source, not a regression: the layer
    /// publishes `PlantType` and nothing else of that set. `landContextUnplaced == trees` follows —
    /// `LandContext.inferred(from:)` reads `qLegalStatus` and `qCaretaker`, and the layer has
    /// neither, so no row can be placed and the `Stands on` sentence does not draw for anybody.
    static func city(absentColumns: Set<String>) -> SeedCorpus {
        SeedCorpus(
            source: "city",
            absentColumns: absentColumns,
            trees: 133_577,
            species: 577,
            vacantSites: 153,
            cityColumnRows: [
                "legal_status": 0,
                "caretaker": 0,
                "care_assistant": 0,
                "plant_type": 133_577,
                "plot_size": 0,
                "permit_notes": 0
            ],
            distinctPlotSizes: 0,
            plotSizesShown: 0,
            plotSizesRefused: 0,
            landContextStreet: 0,
            landContextPrivate: 0,
            landContextOtherPublic: 0,
            landContextCityPark: 0,
            landContextUnplaced: 133_577,
            neighborhoodsWithNoVacantSite: 17,
            sunsetVacantSites: 7,
            sunsetTreesWithSpecies: 9_504,
            sunsetTreesLeftJoined: 9_512,
            sunsetSpeciesInMix: 201,
            densestScreenfulFloor: 4_000
        )
    }

    /// **The DataSF `tkzw-k3nq` export.** What shipped before #91 and what `--source datasf` still
    /// builds. Every number here is the one its own suite carried as a literal before this type
    /// existed, moved rather than recomputed.
    static func dataSF(absentColumns: Set<String>) -> SeedCorpus {
        SeedCorpus(
            source: "datasf",
            absentColumns: absentColumns,
            trees: 195_309,
            species: 569,
            vacantSites: 12_518,
            cityColumnRows: [
                "legal_status": 195_252,
                "caretaker": 195_309,
                "care_assistant": 25_199,
                "plant_type": 195_309,
                "plot_size": 146_951,
                "permit_notes": 52_580
            ],
            distinctPlotSizes: 588,
            plotSizesShown: 126_411,
            plotSizesRefused: 20_540,
            landContextStreet: 182_320,
            landContextPrivate: 11_856,
            landContextOtherPublic: 956,
            landContextCityPark: 177,
            landContextUnplaced: 0,
            neighborhoodsWithNoVacantSite: 0,
            sunsetVacantSites: 1_474,
            sunsetTreesWithSpecies: 11_026,
            sunsetTreesLeftJoined: 11_078,
            sunsetSpeciesInMix: 215,
            densestScreenfulFloor: 5_000
        )
    }
}
