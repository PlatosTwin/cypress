import Foundation
import Testing
@testable import Cypress

/// The numbers that are properties of **the inventory**, not of our code.
///
/// ── Why this exists ───────────────────────────────────────────────────────────────────────
/// A dozen suites pin exact counts against the seed and they are right to. Those literals are what
/// catch a `.strip()` that starts eating values or a join that quietly widens; "greater than zero"
/// would catch none of it. But they were written when there was one possible seed, and there are
/// now four corpora, named by `seed_meta.trees_source` and by which cities' rows are in the file
/// (`seed_meta.id_spaces_in_file`):
///
/// - `sf_datasf` — the open-data export `tkzw-k3nq`, 195,309 records. What shipped before #91,
///                 still buildable with `Tools/build_seed.py --source datasf`, and still required
///                 to work, because the owner may default back to it.
/// - `sf_city`   — SF Public Works' own operational layer for the trees, 133,577 records, plus the
///                 export's 12,260 vacant planting sites, which that layer has no category for.
///                 145,837 records. What shipped between #91 and #129.
/// - `sf_city` **with `us-ca-sj` in `id_spaces_in_file`** — the same, fused with central San Jose.
///                 198,625 records. What shipped between #129 and the s17 publish.
/// - `sf_city` **with `us-ca-sj` and `us-ny-nyc`** — the same again, fused with all five boroughs of
///                 New York City. 1,097,382 records. **What ships**, and what `Tools/fetch_seed.sh`
///                 resolves from the live manifest.
///
/// **`sf_city` / `sf_datasf` are the v14 vocabulary.** The column values were bare `city` and
/// `datasf` before that pass renamed them (`InventoryContractTests` documents the rename), and
/// `current(_:)` below still accepts both so a seed built before v14 resolves. A comment naming
/// the bare forms as what the column holds is describing a file that no longer ships.
///
/// A literal in a test body can only be right about one corpus. So the literals move here, keyed
/// by the source the seed's own build receipt names, and each suite asks for the corpus it is
/// actually running against. **Every set stays pinned to exact numbers** — this is not a loosening.
/// Rebuilding any of these seeds and getting different numbers still fails.
///
/// ── What none of these numbers is ─────────────────────────────────────────────────────────
/// **A property of this app.** Under D16 the seed is a *merged* inventory on the way to a national
/// one, so every count and every share below is a weighted average over whichever cities happen to
/// be in the file, and it moves whenever one is added. #129 moved all of them at once. That is the
/// argument for pinning them here rather than stating them in prose: a constant plus a test turns
/// the next city into a red build, and a sentence in a comment turns it into a lie nobody reads
/// (ERRATA E175, the worked example; ERRATA E206 for the figures that rotted in prose instead).
///
/// ── The harder half: controls that cannot fire ────────────────────────────────────────────
/// Some of these suites do not merely count. They assert a *control* — "this neighborhood does
/// have dated plantings", "a row with all six columns set decodes to a city record" — and the
/// control is what proves the assertion above it measured something. The city's layer publishes
/// seven fewer columns than the export, and a first build of `--source city` that took only the
/// layer had no planting dates at all: every one of those controls stopped firing, and the suites
/// would have gone green while testing nothing. That is precisely the failure ARCHITECTURE §7
/// records about grepping for a DEBUG symbol with no control string.
///
/// The build's answer was to keep the row set from the city and carry those seven columns across
/// from the export for the records both list, so the controls fire again. `publishes(_:)` remains
/// as the mechanism that would catch it happening for real: it reads
/// `seed_meta.columns_absent_from_source`, so a source that genuinely stops publishing a column
/// makes the affected tests say so instead of quietly asserting nothing.
struct SeedCorpus: Sendable {

    /// `seed_meta.trees_source` verbatim: `sf_city` or `sf_datasf` on any seed built since the v14
    /// pass, bare `city` or `datasf` on one built before it. Both spellings are resolved by
    /// `current(_:)`; this field carries whichever the file actually said.
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
    /// Rows `LandContext.inferred(from:idSpace:)` declines outright because they are in an id space
    /// the mapping was not written for (R24) — as opposed to rows whose record says nothing. Both
    /// land in `landContextUnplaced`, and they are different facts: a change that turned one into
    /// the other would balance a single total without anybody noticing.
    let landContextDeclinedForeignVocabulary: Int
    /// Neighborhoods that hold trees but no vacant planting site.
    let neighborhoodsWithNoVacantSite: Int
    /// Vacant sites in no neighborhood at all, and therefore invisible to every neighborhood
    /// surface in the app. Zero for a San Francisco-only seed; a whole city's worth once a second
    /// city ships without a neighborhood layer of its own (ERRATA E176).
    let vacantSitesWithNoNeighborhood: Int
    /// Rows that are `alive` with no species because their **source said a tree is there and did not
    /// say which** — R18's answer for San Jose's `NAMESCIENTIFIC = 'Unknown'`. Distinct from
    /// `records_not_a_tree`, which is a source saying the thing growing there is not a tree. Neither
    /// of San Francisco's inventories can express the first, so it is zero for both SF corpora.
    let treesOfUnknownSpecies: Int
    /// Vacant sites carrying a planting date — the reason `planted_on` alone cannot decide what the
    /// almanac's season rows and coverage card may show.
    let datedVacantSites: Int
    /// Rows carrying a `planted_year` at all — the figure the whole year control is designed
    /// around (E175), and the one that has rotted in prose more often than any other here.
    ///
    /// **Pinned exactly rather than as a share, and this is the #122 correction.** E206 chose a
    /// loose range for it on the argument that a tight pin measured on one branch would false-red
    /// one city later. The range did its job — it is why `MapFilterTests` still passes — but it
    /// could not catch an arithmetic slip, and one happened: E206 stated **38,185 dated / 160,440
    /// undated**, three shipped comments copied it, and the seed says **38,184 / 160,441**
    /// (37,962 San Francisco + 222 San Jose, E175 + E176's own figures, which sum to 38,184).
    /// Keyed by corpus, an exact pin does not false-red on a new city: a new city is a new corpus
    /// entry, and the red is the reminder to write one.
    ///
    /// `nil` where nobody has measured it. The DataSF export is still buildable and still required
    /// to work, but this repo ships no copy of it, so a number here would be remembered rather
    /// than counted — and the suite falls back to the share for that corpus rather than asserting
    /// a figure whose provenance is a document.
    let datedTrees: Int?

    // ── Sunset/Parkside, the neighborhood the almanac suites read ───────────────────────────
    let sunsetVacantSites: Int
    /// Standing trees that join a species (the inner join) and that do not (the left join).
    let sunsetTreesWithSpecies: Int
    let sunsetTreesLeftJoined: Int
    let sunsetSpeciesInMix: Int

    // ── The map ─────────────────────────────────────────────────────────────────────────────
    /// The densest screenful `MapDetailTests` measures must exceed this. It is a floor on how much
    /// the budget has to cope with, so it moves with the corpus.
    let densestScreenfulFloor: Int

    /// Rows of **this corpus's own tree source** (`inventory_source = seed_meta.trees_source`)
    /// carrying no DBH bucket — the discriminator `InventoryContractTests` uses to prove the
    /// source's `DBH = 0` sentinel was not read as a measurement. Both spellings of that test's
    /// literals lived in the test body until the s17 publish re-read San Francisco's layer and moved
    /// one of them, which is the lesson this type exists for: it is a fact about one snapshot of one
    /// inventory, not about the code.
    let cityRowsWithNoDBHBucket: Int

    /// The share of rows carrying no planting year, and the share that are vacant planting sites.
    ///
    /// **Bands rather than pins, because they are arguments rather than measurements.** The first
    /// sized `MapFilter`'s decade buckets (E175, E176); the second is the premise task #179 argues
    /// from. Both are whole-corpus properties, so both move when a city lands — which is why they
    /// are keyed here now instead of sitting as magic numbers in `MapFilterTests`, where a new city
    /// made them false-red with nothing to say about which corpus they had been true of.
    ///
    /// `nil` where nobody has measured the band for that corpus, on the same rule as `datedTrees`:
    /// the suite skips the assertion rather than checking a figure whose provenance is a document.
    let undatedShareBand: ClosedRange<Double>?
    let vacantShareBand: ClosedRange<Double>?

    /// Whether the running corpus publishes a given DataSF column, and can therefore support a
    /// control that reads it.
    func publishes(_ column: String) -> Bool { !absentColumns.contains(column) }

    /// Reads the corpus for whichever seed is attached.
    static func current(_ store: CypressStore) async throws -> SeedCorpus {
        let meta = try await store.queue.read { connection in
            CypressStore.readSeedMeta(connection: connection)
        }
        // The default is the pre-v14 spelling on purpose: a file old enough to be missing this key
        // is old enough to have been built before the rename.
        let source = meta["trees_source"] ?? "datasf"
        let absent = Set((meta["columns_absent_from_source"] ?? "")
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty })
        // Which corpus a file is depends on TWO facts now, not one: which San Francisco inventory
        // decided its trees, and whether a second city's rows are in it. `id_spaces_in_file` is
        // written by the v14 pass and is absent on every earlier seed, which is exactly right —
        // those files hold one space.
        let spaces = Set((meta["id_spaces_in_file"] ?? "")
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty })
        switch (source, spaces.contains("us-ca-sj"), spaces.contains("us-ny-nyc")) {
        case ("sf_city", false, false), ("city", false, false): return .city(absentColumns: absent)
        case ("sf_city", true, false), ("city", true, false): return .cityWithSanJose(absentColumns: absent)
        case ("sf_city", true, true), ("city", true, true):
            return .cityWithSanJoseAndNewYork(absentColumns: absent)
        case ("sf_datasf", _, _), ("datasf", _, _): return .dataSF(absentColumns: absent)
        default:
            Issue.record("seed_meta.trees_source is '\(source)', which no corpus is pinned for")
            return .dataSF(absentColumns: absent)
        }
    }

    /// **SF Public Works' own street tree inventory for the trees, the DataSF export for the
    /// sites.** San Francisco alone, extracted 2026-07-26. What shipped between #91 and #129, and
    /// what a San-Francisco-only city file still narrows to (R37 §3) — **not what ships**, which is
    /// `cityWithSanJose` below.
    ///
    /// The *tree* row set is the city's: 133,577 records, exactly what its public map draws. The
    /// seven columns its layer does not publish are carried across from the DataSF export for the
    /// 130,070 records both inventories list, so `legal_status`, `plot_size` and the planting dates
    /// are populated on 97% of those rows rather than none. The shortfall is the **3,507 records
    /// only the city has**, which carry NULL there — including TreeID 276198, the tree that
    /// started #91.
    ///
    /// `landContextUnplaced` is therefore 3,506 rather than 0: `LandContext.inferred(from:)` reads
    /// `qLegalStatus` and `qCaretaker`, and those 3,506 have neither, so the `Stands on` sentence
    /// does not draw for them. (3,506 and not 3,507: one of the city-only records does carry a
    /// caretaker, because DataSF holds a row for it that the seed's coordinate rules had dropped.)
    ///
    /// **The 12,260 vacant planting sites are the export's rows, and they are not a compromise.**
    /// The city's layer has no vacant-site category at all — `PlantType` is `Tree` on every one of
    /// its records — so on an empty basin it is not contradicting the export, it has nothing to say.
    /// The one place the two really do disagree is a TreeID the export calls empty and the layer
    /// lists as a planted tree: **128 rows**, and there the city wins, consistently with the rule
    /// that decides the tree row set. A further 130 sites the layer also holds as empty are already
    /// in from the first pass. So `vacantSites` is 12,413: 12,260 from the export and 153 the
    /// city's own `BOTANICAL = 'Potential Site'` yields.
    static func city(absentColumns: Set<String>) -> SeedCorpus {
        SeedCorpus(
            source: "city",
            absentColumns: absentColumns,
            trees: 145_837,
            // 577 before task #103, which merged seven species the ingest had minted twice — once
            // properly and once as a stub named `:: <the city's own string>`. Measured, not
            // predicted: `--source city --sj-extent none` reports 570.
            species: 570,
            vacantSites: 12_413,
            cityColumnRows: [
                "legal_status": 142_282,
                "caretaker": 142_331,
                "care_assistant": 10_595,
                "plant_type": 145_837,
                "plot_size": 115_196,
                "permit_notes": 27_046
            ],
            distinctPlotSizes: 407,
            plotSizesShown: 96_566,
            plotSizesRefused: 18_630,
            landContextStreet: 137_204,
            landContextPrivate: 4_596,
            landContextOtherPublic: 460,
            landContextCityPark: 71,
            landContextUnplaced: 3_506,
            landContextDeclinedForeignVocabulary: 0,
            neighborhoodsWithNoVacantSite: 0,
            vacantSitesWithNoNeighborhood: 0,
            treesOfUnknownSpecies: 0,
            datedVacantSites: 9_237,
            // 37,962 of the 145,837 `sf` rows, counted off the shipped fused file's San
            // Francisco half (E175's own figure, re-counted rather than copied).
            datedTrees: 37_962,
            sunsetVacantSites: 1_436,
            sunsetTreesWithSpecies: 9_504,
            sunsetTreesLeftJoined: 9_512,
            // 201 before task #103. The species that left is `:: lophostemon confertus`, the stub
            // the ingest minted beside `Lophostemon confertus`, which was already in this mix — so
            // the mix lost a name for a plant it still carries, not a plant.
            sunsetSpeciesInMix: 200,
            densestScreenfulFloor: 4_000,
            cityRowsWithNoDBHBucket: 9_019,
            // The `sf` id space's own shares, measured on seed 4f6ebaaa (2026-08-22) at 0.73987 /
            // 0.08503 and on the previous shipped file at 0.73970 / 0.08512 — this corpus is that
            // space alone. NOTE it sits BELOW the 0.75 the fused corpus's band starts at: San
            // Francisco was never the four-in-five, San Jose's 99.6%-undated rows are what carried
            // the fused figure over that line.
            undatedShareBand: 0.70...0.78,
            vacantShareBand: 0.06...0.11
        )
    }

    /// **San Francisco as above, plus central San Jose.** What ships after #129, built with
    /// `--source city --sj-extent downtown`.
    ///
    /// **52,788 San Jose rows on top of San Francisco's 145,837**, out of a 344,879-record corpus
    /// that was read and validated in full. Ingesting and shipping are two decisions (ERRATA E176):
    /// what a phone gets is a contiguous window over central San Jose — downtown, SoFA, Japantown,
    /// Naglee Park, the Alameda, north Willow Glen — **complete inside it**, because a sampled corpus
    /// would put invisible holes between real trees on a real block while looking fine in aggregate.
    ///
    /// **Three numbers here are the same as `city`'s and that is the finding, not an oversight.**
    /// `landContextStreet`, `landContextPrivate`, `landContextOtherPublic` and `landContextCityPark`
    /// do not move, because `LandContext.inferred(from:idSpace:)` refuses to read San Francisco's
    /// `qLegalStatus` vocabulary against San Jose's `OWNEDBY` (R24). So all 52,788 San Jose rows land
    /// in `landContextUnplaced`, which goes 3,506 → 56,294. Before that refusal they resolved —
    /// 48,036 of them to `.privateProperty`, on a layer called *Street Trees*.
    ///
    /// **`sunset*` and `neighborhoodsWithNoVacantSite` do not move either**, for a related reason
    /// worth stating: the seed's `neighborhoods` table is San Francisco's 41 Analysis Neighborhoods
    /// and nothing else, so every San Jose row carries `neighborhood_id IS NULL` and is invisible to
    /// every neighborhood-scoped surface in the app, the almanac included.
    static func cityWithSanJose(absentColumns: Set<String>) -> SeedCorpus {
        SeedCorpus(
            source: "sf_city",
            absentColumns: absentColumns,
            trees: 198_625,
            // 738 before task #103. The same seven merges as the SF-only variant above; San Jose
            // contributes none, because its adapter never packed a name into DataSF's convention.
            species: 731,
            vacantSites: 24_200,
            cityColumnRows: [
                "legal_status": 192_912,
                "caretaker": 195_119,
                "care_assistant": 10_595,
                "plant_type": 197_526,
                "plot_size": 166_746,
                // 78_095 until task #103 rebuilt the seed, and NOT a consequence of that task: the
                // shipped file predates a refresh of `Fixtures/raw/street_tree_list.csv`, in which
                // SF TreeID 234040 now publishes an empty `PermitNotes`. The SF-only variant above
                // reads 27_046 before and after, which is what localizes the drift to the shipped
                // artifact rather than to the ingest. See ERRATA E208.
                "permit_notes": 78_094
            ],
            distinctPlotSizes: 411,
            // UNCHANGED from `city`, and that is a finding. San Jose's SPACEWIDTH is a bare
            // number of feet — `8+`, `3`, `0` — and `CityRecordPresentation.plotSizeText` refuses a
            // bare integer of unstated unit, which is the same rule that refuses San Francisco's
            // `60`. So all 51,550 San Jose plot sizes are carried into the seed and none of them
            // will ever render. Correct under the existing rule; recorded in ERRATA E176 rather
            // than fixed, because deciding that SPACEWIDTH means feet is a decision about a column
            // documented as DataSF's PlotSize.
            plotSizesShown: 96_566,
            plotSizesRefused: 70_180,
            landContextStreet: 137_204,
            landContextPrivate: 4_596,
            landContextOtherPublic: 460,
            landContextCityPark: 71,
            landContextUnplaced: 56_294,
            landContextDeclinedForeignVocabulary: 52_788,
            neighborhoodsWithNoVacantSite: 0,
            vacantSitesWithNoNeighborhood: 11_787,
            treesOfUnknownSpecies: 705,
            datedVacantSites: 9_237,
            // 38,184 = 37,962 (`sf`) + 222 (`us-ca-sj`), which are E175's and E176's own per-city
            // figures. NOT E206's 38,185; see this field's doc comment for the slip.
            datedTrees: 38_184,
            sunsetVacantSites: 1_436,
            sunsetTreesWithSpecies: 9_504,
            sunsetTreesLeftJoined: 9_512,
            // 201 before task #103. The species that left is `:: lophostemon confertus`, the stub
            // the ingest minted beside `Lophostemon confertus`, which was already in this mix — so
            // the mix lost a name for a plant it still carries, not a plant.
            sunsetSpeciesInMix: 200,
            densestScreenfulFloor: 4_000,
            cityRowsWithNoDBHBucket: 9_019,
            // Unchanged from what `MapFilterTests` carried as literals while this was the shipped
            // corpus; measured on that file at 0.80776 undated / 0.12184 vacant.
            undatedShareBand: 0.75...0.85,
            vacantShareBand: 0.08...0.18
        )
    }

    /// **San Francisco and central San Jose as above, plus all five boroughs of New York City.**
    /// What ships after the s17 publish, measured from **seed `4f6ebaaa` on 2026-08-22** — the file
    /// `Tools/fetch_seed.sh` resolves from the live manifest (706,535,424 bytes, sha256
    /// `4f6ebaaad8c94bde…`), which is what CI's `unit` job builds against.
    ///
    /// **Every number below was counted from that file, and each query was calibrated first by
    /// reproducing `cityWithSanJose`'s shipped literal from the previous seed.** None was copied out
    /// of a failure message: a failing expectation prints the reading of the instrument under
    /// suspicion, which is the one number in the room that has not been checked.
    ///
    /// ── What moved, and why it is not all New York ────────────────────────────────────────────
    /// **The s17 publish re-read San Francisco and San Jose too** (`inventory_sf_city_snapshot_on`
    /// and `inventory_sj_street_tree_snapshot_on` are both 2026-08-22, against 2026-07-31 before).
    /// So this is not the previous corpus plus a third city: `sf` went 145,837 → 145,964 and
    /// `us-ca-sj` went 52,788 → 52,775, which is why several counts here are *lower* than
    /// `cityWithSanJose`'s — `plotSizesRefused` 70,180 → 70,153, `landContextStreet` 137,204 →
    /// 137,192, `datedVacantSites` 9,237 → 9,235. A reading that assumed a new city can only add
    /// would have called those three impossible and gone looking for the wrong defect.
    ///
    /// **New York ships no vacant planting sites at all** — 898,643 rows, zero `vacant_site` — which
    /// is why `vacantSites` barely moves while `trees` grows 5.5×, and why `vacantShareBand` drops
    /// from an eighth of the map to a fiftieth. See that field.
    ///
    /// `landContextDeclinedForeignVocabulary` is now 951,418: R24 refuses to read San Francisco's
    /// `qLegalStatus` vocabulary against any other publisher's, so every San Jose **and** every New
    /// York row is declined outright, and 52,775 + 898,643 is exactly that figure.
    static func cityWithSanJoseAndNewYork(absentColumns: Set<String>) -> SeedCorpus {
        SeedCorpus(
            source: "sf_city",
            absentColumns: absentColumns,
            trees: 1_097_382,
            species: 1_198,
            vacantSites: 24_205,
            // All six agree with the seed's own receipt (`seed_meta.city_<column>_rows`), which is
            // an independent witness to the same count rather than a second reading of mine.
            cityColumnRows: [
                "legal_status": 333_962,
                "caretaker": 195_093,
                "care_assistant": 10_595,
                "plant_type": 1_096_267,
                "plot_size": 167_831,
                "permit_notes": 976_706
            ],
            distinctPlotSizes: 660,
            plotSizesShown: 97_678,
            plotSizesRefused: 70_153,
            landContextStreet: 137_192,
            landContextPrivate: 4_596,
            landContextOtherPublic: 459,
            landContextCityPark: 71,
            landContextUnplaced: 955_064,
            landContextDeclinedForeignVocabulary: 951_418,
            neighborhoodsWithNoVacantSite: 0,
            vacantSitesWithNoNeighborhood: 11_793,
            // 4,411 rows are alive with no species; the receipt counts 185 not-a-tree records, and
            // 4,411 − 185 is the trees whose source said a tree is there without saying which.
            treesOfUnknownSpecies: 4_226,
            datedVacantSites: 9_235,
            // Every row carrying a `planted_year`, vacant sites included — the definition the field
            // states and the one that reproduces `cityWithSanJose`'s 38,184 on the previous file.
            datedTrees: 161_914,
            // UNCHANGED, and measured rather than assumed: the seed's `neighborhoods` table is San
            // Francisco's 41 Analysis Neighborhoods, so New York's rows carry a NULL
            // `neighborhood_id` and are invisible to every neighborhood-scoped surface, exactly as
            // San Jose's are.
            sunsetVacantSites: 1_436,
            sunsetTreesWithSpecies: 9_504,
            sunsetTreesLeftJoined: 9_512,
            sunsetSpeciesInMix: 200,
            densestScreenfulFloor: 4_000,
            cityRowsWithNoDBHBucket: 9_177,
            // 0.85245 undated on this file. Still "most rows", and slightly more so than the fused
            // California corpus: New York states a planting year on 123,723 of its 898,643 rows.
            undatedShareBand: 0.82...0.88,
            // 0.02206, against 0.12184 before. **This is a product finding, not a stale number.**
            // Task #179's premise — that vacant planting sites are a large minority of the map —
            // now holds only inside San Francisco (0.08503 of the `sf` space); New York publishes
            // no vacant sites at all, so nationally they are a fiftieth of the map. Pinned here as
            // a band rather than widened in the test, so the figure is attached to the corpus it is
            // true of and the next city has to state its own. Raised for adjudication in the PR
            // that measured it rather than settled here.
            vacantShareBand: 0.015...0.030
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
            landContextDeclinedForeignVocabulary: 0,
            neighborhoodsWithNoVacantSite: 0,
            vacantSitesWithNoNeighborhood: 0,
            treesOfUnknownSpecies: 0,
            datedVacantSites: 9_294,
            // Never measured: this repo ships no DataSF-built seed to count. See the field.
            datedTrees: nil,
            sunsetVacantSites: 1_474,
            sunsetTreesWithSpecies: 11_026,
            sunsetTreesLeftJoined: 11_078,
            sunsetSpeciesInMix: 215,
            densestScreenfulFloor: 5_000,
            cityRowsWithNoDBHBucket: 44_584,
            // Never measured: this repo ships no DataSF-built seed to count, and the band that used
            // to be asserted against this corpus was the fused corpus's. See the fields.
            undatedShareBand: nil,
            vacantShareBand: nil
        )
    }
}
