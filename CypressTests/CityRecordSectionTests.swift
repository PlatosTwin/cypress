import Foundation
import Testing
@testable import Cypress

/// **What the city has on file** — screen 03/14 §9b, the section that reads `CityRecord` out
/// onto the tree's landing page (ERRATA E145, and ERRATA E181 for the four surfaces that stopped
/// saying San Francisco about San Jose).
///
/// ── Why so much of this runs against the whole seed ───────────────────────────────────────────
/// `CityRecordPresentation` makes exactly three kinds of decision — what to show, how to say it, and
/// what to refuse — and all three are stated in doc comments as counts over 195,309 rows. A count in
/// a comment rots the moment the rule or the export moves, and this section's counts are the whole
/// argument for its design: `plantType` is suppressed because 194,991 rows say `Tree`, `plotSize` is
/// re-spelled because 588 values are written three ways, `permitNotes` is refused because 52,114 of
/// 52,580 are a key into a system this app cannot query. So the refusals are re-derived from every
/// row rather than asserted on a handful — `everyPlotSizeInTheSeedIsShownOrRefusedOnPurpose` is the
/// one to read first.
///
/// The unit cases are not redundant with the sweeps: a sweep's totals can stay right while two
/// classes swap.
@Suite("City record section")
struct CityRecordSectionTests {

    private static func store() async throws -> CypressStore {
        let seedURL = try #require(SeedContractTests.seedURL, "no seed database; set CYPRESS_SEED_PATH")
        return try await CypressStore.inMemory(seedURL: seedURL)
    }

    private static func presentation(_ profile: TreeProfile) -> TreeProfilePresentation {
        TreeProfilePresentation(profile: profile, now: TreeProfileSeedFixtures.date(2026, 7, 25))
    }

    private static func cityTree(_ record: CityRecord) -> Tree {
        Tree(
            externalRef: "1",
            source: .cityImport,
            coordinate: Coordinate(latitude: 37.77, longitude: -122.42),
            verificationState: .cityRecord,
            cityRecord: record
        )
    }

    // MARK: - `plotSize`: three notations in, one out, and everything else refused

    @Test("the city's three plot notations are re-spelled one way, with the city's own digits", arguments: [
        ("Width 3ft", "3 ft wide"),
        ("Width 10ft", "10 ft wide"),
        // The city typed it both ways; E143 rules the seed keeps the case and readers fold it.
        ("3x3", "3 × 3"),
        ("3X3", "3 × 3"),
        ("10x10", "10 × 10"),
        ("11x3", "11 × 3"),
        // Six rows carry a decimal. It stays exactly as written — nothing acquires a leading zero
        // it did not have, because the digits are the city's.
        (".5x1", ".5 × 1"),
        ("  4x6  ", "4 × 6"),
    ])
    func plotNotationsAreRespelled(raw: String, expected: String) {
        #expect(
            CityRecordPresentation.plotSizeText(raw) == expected,
            "\(raw) rendered as \(CityRecordPresentation.plotSizeText(raw) ?? "nothing")"
        )
    }

    /// The three refusals, each of which is a decision rather than a parser limitation.
    @Test("a string that is not a size draws no card at all", arguments: [
        // 17,254 rows. A basin zero feet wide is not a measurement of a basin.
        "Width 0ft", "0x0", "0X4",
        // 2,726 rows. Sixty of what, across what?
        "60", "20", "5",
        // 560 rows of plot codes and typing errors from inside a Public Works workflow.
        "M6", "M", "TR", "TR20", "POT", "CUT", "Plaza", "Park", "G", "aaa", "?",
        "On campus", "within landscaping plot", "strip",
        "3xe", "2x", "3X", "tx5", "5xt", "ex3", "CENTER8",
        // Neither notation, despite starting like one.
        "Width 4x5", "Width 4", "Width", "", "   ",
        // Shapes `Double(_:)` accepts and the column never contains.
        "1e3x2", "infxinf", "+3x3",
    ])
    func aStringThatIsNotASizeIsRefused(raw: String) {
        #expect(
            CityRecordPresentation.plotSizeText(raw) == nil,
            "\(raw) rendered as \(CityRecordPresentation.plotSizeText(raw) ?? "nothing")"
        )
    }

    /// **Every one of the 588 distinct `plot_size` values in the seed, classified.**
    ///
    /// The counts in `plotSizeText`'s doc comment are re-derived here from all 195,309 rows, so the
    /// day the weekly export introduces a fourth notation this fails with the number of trees it
    /// affects rather than quietly dropping them. The two totals are what the design rests on: 86% of
    /// populated rows render, and the 14% that do not are the three documented classes and nothing
    /// else.
    ///
    /// **`--source city` publishes no `PlotSize` at all**, so all three numbers are zero there and
    /// the notation triage has nothing to run against. That is asserted rather than skipped, and it
    /// is checked against the source's own column list so an emptied column is still a failure —
    /// but it does mean the *behaviour* here is exercised by the `--source datasf` corpus and by the
    /// unit cases above, not by the shipped seed.
    @Test("every plot size in the seed is either shown or refused on purpose")
    func everyPlotSizeInTheSeedIsShownOrRefusedOnPurpose() async throws {
        let store = try await Self.store()
        let corpus = try await SeedCorpus.current(store)

        let values: [(String, Int)] = try await store.queue.read { connection in
            let statement = try connection.cachedStatement("""
                SELECT plot_size AS value, count(*) AS n
                  FROM \(SeedDatabase.schemaName).trees
                 WHERE plot_size IS NOT NULL
                 GROUP BY plot_size
                """)
            return try statement.fetchAll { (try $0.string("value"), try $0.int("n")) }
        }

        #expect(
            values.count == corpus.distinctPlotSizes,
            "the seed holds \(values.count) distinct plot sizes, expected \(corpus.distinctPlotSizes) under --source \(corpus.source)"
        )
        if values.isEmpty {
            #expect(
                !corpus.publishes("PlotSize"),
                "the seed holds no plot sizes while \(corpus.source) publishes PlotSize"
            )
        }

        var shown = 0
        var refused = 0
        for (value, count) in values {
            if CityRecordPresentation.plotSizeText(value) == nil { refused += count } else { shown += count }
        }

        #expect(
            shown + refused == corpus.cityColumnRows["plot_size"],
            "the populated rows do not add up: \(shown + refused)"
        )
        #expect(shown == corpus.plotSizesShown, "\(shown) rows render a plot size, expected \(corpus.plotSizesShown)")
        #expect(refused == corpus.plotSizesRefused, "\(refused) rows refuse to render one, expected \(corpus.plotSizesRefused)")
    }

    // MARK: - `plantType`: the column that only speaks when it disagrees with the screen

    @Test("the city calling this a tree adds nothing, and is not drawn", arguments: ["Tree", "tree", "TREE"])
    func aRecordThatSaysTreeDrawsNoCard(raw: String) {
        let presentation = CityRecordPresentation(CityRecord(plantType: raw))
        #expect(presentation.listedAsText == nil)
        #expect(presentation.facts.isEmpty)
    }

    /// The 318 rows where the inventory says a record on the tree map is not a tree — the only
    /// reason the column is carried at all.
    @Test("the city calling this something other than a tree leads the section")
    func aRecordThatSaysLandscapingLeadsTheSection() {
        let presentation = CityRecordPresentation(
            CityRecord(legalStatus: "DPW Maintained", caretaker: "Private", plantType: "Landscaping", plotSize: "3X3")
        )
        #expect(presentation.listedAsText == "Landscaping")
        #expect(presentation.facts.first?.label == CityRecordCopy.plantTypeLabel)
        #expect(presentation.facts.first?.value == "Landscaping")
    }

    // MARK: - `caretaker` / `careAssistant`: codes expanded, everything else untouched

    @Test("a code a reader outside City Hall cannot expand is expanded", arguments: [
        ("FUF", "Friends of the Urban Forest"),
        ("DPW", "SF Public Works"),
        ("SFUSD", "SF Unified School District"),
        ("Rec/Park", "SF Recreation and Parks"),
        ("Private", "A private party"),
    ])
    func codesAreExpanded(raw: String, expected: String) {
        #expect(CityRecordPresentation.agencyName(raw) == expected)
    }

    /// The property that keeps this safe against the weekly refresh: a value this file has never
    /// heard of renders as itself, not as a blank and not as a crash. `CAN` is in the seed today and
    /// is deliberately absent from the glossary — guessing is how a glossary starts lying.
    @Test("an agency the glossary has never heard of passes through verbatim", arguments: [
        "Port", "Mission Verde", "Cleary Bros. Landscape", "CAN", "Owner Water",
        "Department Of Something Renamed Next Month",
    ])
    func unknownAgenciesPassThrough(raw: String) {
        #expect(CityRecordPresentation.agencyName(raw) == raw)
    }

    @Test("an empty caretaker is an absence, not a card with nothing after it")
    func anEmptyAgencyIsAnAbsence() {
        #expect(CityRecordPresentation.agencyName("") == nil)
        #expect(CityRecordPresentation.agencyName("   ") == nil)
    }

    /// The `FUF` state, end to end: 22,879 trees say it and it is the one value in these two columns
    /// worth telling somebody about.
    @Test("a Friends of the Urban Forest tree says so in words")
    func aFUFTreeSaysSoInWords() throws {
        let presentation = Self.presentation(TreeProfileSeedFixtures.fullCityRecord)
        let facts = try #require(presentation.cityRecord?.facts)
        let assistant = try #require(facts.first { $0.id == "careAssistant" })
        #expect(assistant.label == CityRecordCopy.careAssistantLabel)
        #expect(assistant.value == "Friends of the Urban Forest")
    }

    // MARK: - `permitNotes` is refused, and stays refused

    /// 52,114 permit references into a system this app cannot query, and 466 staff working notes
    /// carrying a clerk's initials, a misspelling and an accusation about a neighbour's planting.
    /// Neither is drawn, and this asserts it over the section that would have to draw it.
    @Test("a permit note never reaches the screen, whichever of its two shapes it is in", arguments: [
        "Permit Number 771729",
        "Permit No. 49239",
        "50109",
        "I believe these were planted in 2010 by FUF. C.Buck",
        "Resulted descion 9/7/16 -DE",
        "privately planted on dpw street; unpermitted",
        "Landmark Tree in backyard",
    ])
    func aPermitNoteNeverReachesTheScreen(note: String) {
        let presentation = CityRecordPresentation(
            CityRecord(legalStatus: "DPW Maintained", caretaker: "DPW", plantType: "Tree", permitNotes: note)
        )
        let rendered = presentation.facts.map(\.value) + presentation.facts.map(\.label)
        #expect(rendered.contains(note) == false, "the permit note was drawn")
        #expect(presentation.facts.contains { $0.id == "permitNotes" } == false)
    }

    /// A record whose *only* populated column is the refused one draws no section, rather than a
    /// header over an empty grid.
    @Test("a record carrying nothing but a permit note draws no section")
    func aRecordOfOnlyAPermitNoteDrawsNoSection() {
        let record = CityRecord(permitNotes: "Permit Number 771729")
        #expect(record.isEmpty == false, "the record is not empty; the section is")
        #expect(CityRecordPresentation(record).isEmpty)

        var tree = Self.cityTree(record)
        tree.plantedYear = nil
        let presentation = Self.presentation(TreeProfile(tree: tree))
        #expect(presentation.cityRecord == nil)
        #expect(presentation.showsCityRecordSection == false)
        #expect(presentation.cityRecordNotes.isEmpty)

        // The section's second arm: a record with no drawable card still opens it once the seed can
        // say where the record came from and when. That is the whole content of the section on the
        // shipped seed, where `PlantType` is the only column the city publishes and it draws no card.
        let dated = Self.presentation(
            TreeProfile(
                tree: tree,
                inventorySource: InventorySource(
                    id: "sf_city",
                    name: "SF Public Works street tree inventory",
                    url: "https://example.invalid",
                    snapshotDate: InventorySource.date(fromISODay: "2026-07-26")
                )
            )
        )
        #expect(dated.cityRecord == nil, "still no cards")
        #expect(dated.showsCityRecordSection)
        #expect(dated.cityRecordNotes.last == "From the SF Public Works street tree inventory, July 26, 2026.")
    }

    // MARK: - Pruning: answered on screen, once, about the dataset

    /// The general note is on every tree that draws the section, because it is a statement about the
    /// inventory rather than about the tree — and it never becomes an `Unknown` field, because a
    /// field would be a claim that the value exists and Cypress has not got it.
    @Test("every San Francisco city record says on screen that the inventory holds no pruning dates")
    func thePruningAnswerIsOnScreen() throws {
        let pruning = try #require(CityRecordPresentation.pruningNote(idSpace: "sf"))
        for profile in [
            TreeProfileSeedFixtures.fullCityRecord,
            TreeProfileSeedFixtures.bareCityRecord,
            TreeProfileSeedFixtures.listedAsLandscaping,
            TreeProfileSeedFixtures.populated,
            TreeProfileSeedFixtures.coldStart,
        ] {
            var sanFrancisco = profile
            sanFrancisco.tree.idSpace = "sf"
            let presentation = Self.presentation(sanFrancisco)
            #expect(presentation.cityRecordNotes.last == pruning)
            // No field, no blank, no placeholder anywhere in the grid.
            let labels = presentation.cityRecord?.facts.map(\.label) ?? []
            #expect(labels.contains { $0.lowercased().contains("prun") } == false)
            #expect(labels.contains { $0.lowercased().contains("unknown") } == false)
        }
    }

    /// The 254 trees where "pruning" is a real fact about *this* tree. The status renders verbatim as
    /// a card — it is the city's word — and a sentence under the grid says what it means, because
    /// `Prune Opt Out` is exactly the string a reader looking for pruning history will read as
    /// pruning history.
    @Test("an opt-out tree says what its standing arrangement is, and that it carries no date", arguments: [
        ("Prune Opt Out", CityRecordCopy.pruneOptOutNote),
        ("Street Tree Maintenance Opt Out", CityRecordCopy.maintenanceOptOutNote),
    ])
    func anOptOutTreeExplainsItself(status: String, expected: String) {
        let tree = Self.cityTree(CityRecord(legalStatus: status, caretaker: "Private", plantType: "Tree"))
        let presentation = Self.presentation(TreeProfile(tree: tree))

        #expect(presentation.cityRecordNotes.first == expected)
        #expect(presentation.cityRecordNotes.count == 2, "the general pruning note follows it")
        #expect(expected.contains("no date on the record"), "the sentence must refuse to read as a date")
        // The city's own string still shows, unedited, on the card.
        #expect(presentation.cityRecord?.facts.contains { $0.value == status } == true)
    }

    @Test("a tree with no opt-out carries only the note about the dataset")
    func anOrdinaryTreeCarriesOnlyTheGeneralNote() throws {
        let presentation = Self.presentation(TreeProfileSeedFixtures.fullCityRecord)
        #expect(presentation.cityRecordNotes == [try #require(CityRecordPresentation.pruningNote(idSpace: nil))])
    }

    /// The two opt-out statuses are the only ones that get a sentence — asserted over the seed's
    /// whole legal-status vocabulary, so a status added by a future export cannot silently acquire or
    /// lose one.
    @Test("exactly two of the city's legal statuses carry a standing-arrangement sentence")
    func onlyTheTwoOptOutsCarryASentence() async throws {
        let store = try await Self.store()
        let corpus = try await SeedCorpus.current(store)
        let statuses: [String] = try await store.queue.read { connection in
            let statement = try connection.cachedStatement("""
                SELECT DISTINCT legal_status AS value FROM \(SeedDatabase.schemaName).trees
                 WHERE legal_status IS NOT NULL
                """)
            return try statement.fetchAll { try $0.string("value") }
        }

        let withSentence = statuses.filter {
            CityRecordPresentation(CityRecord(legalStatus: $0)).maintenanceOptOutNote() != nil
        }
        // No `qLegalStatus` in the source means no statuses to filter, so the expected set is empty
        // and the *reason* is the absent column rather than a rule that stopped firing. The rule
        // itself is covered by the unit cases in this suite, which do not read the seed.
        let expected: Set<String> = corpus.publishes("qLegalStatus")
            ? [CityRecordCopy.pruneOptOutStatus, CityRecordCopy.maintenanceOptOutStatus]
            : []
        #expect(
            Set(withSentence) == expected,
            "statuses carrying a sentence: \(withSentence.sorted()) under --source \(corpus.source)"
        )
    }

    // MARK: - The section itself

    /// The floor: the two columns that are always populated, and nothing else. Two cards, no blanks.
    @Test("a record with only the always-populated columns draws two cards and no placeholders")
    func theFloorOfTheSectionIsTwoCards() {
        let presentation = Self.presentation(TreeProfileSeedFixtures.bareCityRecord)
        let facts = presentation.cityRecord?.facts ?? []
        #expect(facts.map(\.id) == ["legalStatus", "caretaker"])
        #expect(facts.map(\.value) == ["Undocumented", "A private party"])
        #expect(facts.contains { $0.value.isEmpty } == false)
    }

    /// **A community tree has no city record and draws no city section**, and nothing stands in for
    /// it. The subtitle already reads `community-added, unverified`.
    @Test("a community-added tree draws no city section and no empty state for one")
    func aCommunityTreeDrawsNoCitySection() {
        let presentation = Self.presentation(TreeProfileSeedFixtures.communityAdded)
        #expect(presentation.profile.tree.cityRecord == nil)
        #expect(presentation.cityRecord == nil)
        #expect(presentation.cityRecordNotes.isEmpty)
        #expect(presentation.subtitle.contains(presentation.provenance))
        // The section is gone; the land-context line is not, because a contributor stated it.
        #expect(presentation.showsCityDetails)
    }

    /// The caretaker card is labelled for care, not for ownership. This is the 84% trap E143 exists
    /// to avoid, and the label is the only thing standing between the reader and making the same
    /// inference by hand.
    @Test("the caretaker card never says owner, on the row where that would be most wrong")
    func theCaretakerCardIsLabelledForCare() {
        // 112,955 seed rows are exactly this: DPW-maintained right-of-way, private caretaker.
        let tree = Self.cityTree(CityRecord(legalStatus: "DPW Maintained", caretaker: "Private", plantType: "Tree"))
        let presentation = Self.presentation(TreeProfile(tree: tree))

        let caretaker = presentation.cityRecord?.facts.first { $0.id == "caretaker" }
        #expect(caretaker?.label == "Cared for by")
        #expect(caretaker?.label.lowercased().contains("owner") == false)
        // And the sentence above the section answers the question the card would otherwise invite.
        #expect(presentation.landContextNote == TreeProfileCopy.landContextInferred("on a street"))
    }

    // MARK: - Where it stands, and who says so

    /// The two ways of knowing produce two different sentences, and each names its own speaker.
    /// `KnownLandContext` exists so a screen cannot show an inference with an observation's
    /// confidence; this is the screen holding up its end.
    @Test("an inference cites itself and an observation states itself")
    func theTwoWaysOfKnowingReadDifferently() throws {
        let city = Self.presentation(TreeProfile(tree: TreeProfileSeedFixtures.flameTree))
        let community = Self.presentation(TreeProfileSeedFixtures.communityAdded)

        let inferred = try #require(city.landContextNote)
        let stated = try #require(community.landContextNote)

        #expect(inferred == "Cypress reads the city's record as a tree on a street.")
        #expect(stated == "A contributor said this tree stands in a city park.")
        #expect(inferred != stated)
        // Neither sentence may be mistaken for the other's kind of claim. The stated arm may well
        // contain the word "city" — `in a city park` is one of the four places — so what it must not
        // contain is the *attribution*.
        #expect(inferred.contains("contributor") == false)
        #expect(stated.contains("the city's record") == false)
        #expect(inferred.contains("the city's record"))
    }

    @Test("all four land contexts have a phrase, and no two are the same", arguments: LandContext.allCases)
    func everyLandContextHasItsOwnPhrase(context: LandContext) {
        let phrase = TreeProfileCopy.landContextPlace(context)
        #expect(phrase.isEmpty == false)
        let others = LandContext.allCases
            .filter { $0 != context }
            .map(TreeProfileCopy.landContextPlace)
        #expect(others.contains(phrase) == false)
    }

    /// A community tree whose contributor did not answer says nothing about where it stands, rather
    /// than guessing `street` — E143's argument for `land_context` being nullable with no default,
    /// carried through to the screen.
    @Test("an unanswered community tree draws no land-context line")
    func anUnansweredCommunityTreeSaysNothing() {
        var tree = TreeProfileSeedFixtures.communityTree
        tree.statedLandContext = nil
        let presentation = Self.presentation(TreeProfile(tree: tree))
        #expect(presentation.landContextNote == nil)
        #expect(presentation.showsCityDetails == false)
    }

    // MARK: - Against the seed, end to end

    /// The section derived from a real row read through the real store, rather than from a fixture:
    /// `TreeQueries` selects the six columns, `decodeCityRecord` assembles them and this reads them
    /// out. Any link in that chain could break without a fixture noticing.
    ///
    /// The row it picks depends on the source, because the chain can only be followed through
    /// columns the source publishes. Under `--source datasf` that is the rich row it always used —
    /// an FUF-assisted tree with a width-notation plot size. Under `--source city` the only one of
    /// the six the layer carries is `PlantType`, so the section it produces has **no cards at all**,
    /// and what it must still carry is the two sentences: the block-grain pruning note, and the
    /// provenance line naming the inventory and the day it was read. Those are the section's whole
    /// content under this source and are the thing worth asserting reaches the screen.
    @Test("a real seed row produces a real section")
    func aRealSeedRowProducesARealSection() async throws {
        let store = try await Self.store()
        let corpus = try await SeedCorpus.current(store)
        let queries = TreeQueries(
            schema: try #require(store.seed),
            seedHasSoftDeletedTrees: store.seedHasSoftDeletedTrees
        )
        let rich = corpus.publishes("qCareAssistant") && corpus.publishes("PlotSize")
        let predicate = rich
            ? "care_assistant = 'FUF' AND plot_size LIKE 'Width %ft' AND plot_size <> 'Width 0ft'"
            : "plant_type IS NOT NULL"

        let tree = try await store.queue.read { connection -> Tree in
            let statement = try connection.cachedStatement("""
                SELECT uuid FROM \(SeedDatabase.schemaName).trees
                 WHERE \(predicate)
                 LIMIT 1
                """)
            let uuid = try #require(try statement.fetchOne { try $0.uuid("uuid") })
            return try #require(try queries.tree(id: uuid, connection: connection)?.tree)
        }

        let presentation = Self.presentation(
            TreeProfile(tree: tree, inventorySource: store.seedProvenance)
        )
        // Not `#require`: under a source that publishes only `PlantType` there are no cards, so
        // `cityRecord` is nil by design and the section is its notes. See `showsCityRecordSection`.
        let facts = presentation.cityRecord?.facts ?? []
        #expect(presentation.showsCityRecordSection)

        if rich {
            #expect(facts.contains { $0.value == "Friends of the Urban Forest" })
            #expect(facts.contains { $0.id == "plotSize" && $0.value.hasSuffix(" ft wide") })
            #expect(presentation.landContextNote != nil)
        } else {
            // `plantType == "Tree"` draws no card by design (`listedAsText`), so a source that
            // publishes only that column produces a section made entirely of its notes.
            #expect(facts.isEmpty, "expected no cards from PlantType alone, got \(facts.map(\.id))")
            #expect(presentation.landContextNote == nil)
        }
        #expect(facts.contains { $0.id == "permitNotes" } == false)
        #expect(
            presentation.cityRecordNotes
                .contains(try #require(CityRecordPresentation.pruningNote(idSpace: tree.idSpace)))
        )

        // The provenance line, end to end: `seed_meta` → `CypressStore.seedProvenance` →
        // `TreeProfile` → the section's last sentence. This is the fix for the defect that made
        // "is our data stale?" unanswerable, and it is only real if it survives the whole chain.
        let provenance = try #require(
            presentation.inventoryProvenanceNote,
            "the section says nothing about where these facts came from or when"
        )
        #expect(provenance.contains(try #require(store.seedProvenance).name))
        #expect(presentation.cityRecordNotes.last == provenance)
    }

    /// **A vacant planting site credits the inventory that actually listed it.**
    ///
    /// The shipped seed is built from both of San Francisco's street-tree inventories. The living
    /// trees are SF Public Works' operational layer; the empty basins are the DataSF export's rows,
    /// because that layer has no vacant-site category at all and has therefore never held one of
    /// these records. `CypressStore.seedProvenance` is a property of the *file* and names the city
    /// for all 145,837 rows, so a screen that reads it puts the city's name and the city's snapshot
    /// date over 12,260 records the city has never seen.
    ///
    /// This follows the fix end to end on real rows: `trees.inventory_source` → `TreeQueries` →
    /// `LocalAPI.provenance(of:in:)` → `SitePresentation.provenanceNote`. **Both halves matter.**
    /// The site asserts the export's name; the tree beside it asserts the city's, which is the
    /// control — without it a resolver that returned the same answer for everything would pass the
    /// first assertion and the whole point would be lost.
    ///
    /// Skipped on a seed built from one inventory (`--source datasf`), where the file-wide answer is
    /// the right answer for every row and there is no second name to distinguish.
    @Test("a vacant site names its own inventory, not the file's")
    func aVacantSiteNamesItsOwnInventory() async throws {
        let store = try await Self.store()
        let schema = try #require(store.seed)
        guard schema.hasInventorySource, store.seedInventories.count > 1 else { return }

        let queries = TreeQueries(
            schema: schema,
            seedHasSoftDeletedTrees: store.seedHasSoftDeletedTrees
        )
        let picked = try await store.queue.read { connection -> (TreeQueries.TreeRecord, TreeQueries.TreeRecord) in
            func row(_ predicate: String) throws -> TreeQueries.TreeRecord {
                let statement = try connection.cachedStatement("""
                    SELECT uuid FROM \(SeedDatabase.schemaName).trees
                     WHERE \(predicate) LIMIT 1
                    """)
                let uuid = try #require(try statement.fetchOne { try $0.uuid("uuid") })
                return try #require(try queries.tree(id: uuid, connection: connection))
            }
            return (
                try row("status = 'vacant_site' AND inventory_source = 'sf_datasf'"),
                try row("status = 'alive' AND inventory_source = 'sf_city'")
            )
        }

        let site = picked.0
        let tree = picked.1
        #expect(site.inventorySourceID == "sf_datasf")
        #expect(tree.inventorySourceID == "sf_city")

        let siteSource = try #require(LocalAPI.provenance(of: site, in: store))
        let treeSource = try #require(LocalAPI.provenance(of: tree, in: store))
        #expect(siteSource.id == "sf_datasf")
        #expect(treeSource.id == "sf_city")
        #expect(siteSource.name != treeSource.name, "two inventories, one name")

        let note = try #require(
            SitePresentation(profile: TreeProfile(tree: site.tree, inventorySource: siteSource)).provenanceNote,
            "the site screen says nothing about where its record came from"
        )
        #expect(note.contains(siteSource.name))
        #expect(
            note.contains(treeSource.name) == false,
            "the site credits the inventory that has never listed it: \(note)"
        )
    }
}
