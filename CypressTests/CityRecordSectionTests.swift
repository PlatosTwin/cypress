import Foundation
import Testing
@testable import Cypress

/// **What San Francisco has on file** — screen 03/14 §9b, the section that reads `CityRecord` out
/// onto the tree's landing page (ERRATA E145).
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
    @Test("every plot size in the seed is either shown or refused on purpose")
    func everyPlotSizeInTheSeedIsShownOrRefusedOnPurpose() async throws {
        let store = try await Self.store()

        let values: [(String, Int)] = try await store.queue.read { connection in
            let statement = try connection.cachedStatement("""
                SELECT plot_size AS value, count(*) AS n
                  FROM \(SeedDatabase.schemaName).trees
                 WHERE plot_size IS NOT NULL
                 GROUP BY plot_size
                """)
            return try statement.fetchAll { (try $0.string("value"), try $0.int("n")) }
        }

        #expect(values.count == 588, "the seed holds \(values.count) distinct plot sizes, expected 588")

        var shown = 0
        var refused = 0
        for (value, count) in values {
            if CityRecordPresentation.plotSizeText(value) == nil { refused += count } else { shown += count }
        }

        #expect(shown + refused == 146_951, "the populated rows do not add up: \(shown + refused)")
        #expect(shown == 126_411, "\(shown) rows render a plot size, expected 126,411")
        #expect(refused == 20_540, "\(refused) rows refuse to render one, expected 20,540")
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
    }

    // MARK: - Pruning: answered on screen, once, about the dataset

    /// The general note is on every tree that draws the section, because it is a statement about the
    /// inventory rather than about the tree — and it never becomes an `Unknown` field, because a
    /// field would be a claim that the value exists and Cypress has not got it.
    @Test("every city record says on screen that the inventory holds no pruning dates")
    func thePruningAnswerIsOnScreen() {
        for profile in [
            TreeProfileSeedFixtures.fullCityRecord,
            TreeProfileSeedFixtures.bareCityRecord,
            TreeProfileSeedFixtures.listedAsLandscaping,
            TreeProfileSeedFixtures.populated,
            TreeProfileSeedFixtures.coldStart,
        ] {
            let presentation = Self.presentation(profile)
            #expect(presentation.cityRecordNotes.last == CityRecordPresentation.pruningNote)
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
    func anOrdinaryTreeCarriesOnlyTheGeneralNote() {
        let presentation = Self.presentation(TreeProfileSeedFixtures.fullCityRecord)
        #expect(presentation.cityRecordNotes == [CityRecordPresentation.pruningNote])
    }

    /// The two opt-out statuses are the only ones that get a sentence — asserted over the seed's
    /// whole legal-status vocabulary, so a status added by a future export cannot silently acquire or
    /// lose one.
    @Test("exactly two of the city's legal statuses carry a standing-arrangement sentence")
    func onlyTheTwoOptOutsCarryASentence() async throws {
        let store = try await Self.store()
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
        #expect(
            Set(withSentence) == [CityRecordCopy.pruneOptOutStatus, CityRecordCopy.maintenanceOptOutStatus],
            "statuses carrying a sentence: \(withSentence.sorted())"
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
    @Test("a real seed row produces a real section")
    func aRealSeedRowProducesARealSection() async throws {
        let store = try await Self.store()
        let queries = TreeQueries(
            schema: try #require(store.seed),
            seedHasSoftDeletedTrees: store.seedHasSoftDeletedTrees
        )

        let tree = try await store.queue.read { connection -> Tree in
            let statement = try connection.cachedStatement("""
                SELECT uuid FROM \(SeedDatabase.schemaName).trees
                 WHERE care_assistant = 'FUF' AND plot_size LIKE 'Width %ft' AND plot_size <> 'Width 0ft'
                 LIMIT 1
                """)
            let uuid = try #require(try statement.fetchOne { try $0.uuid("uuid") })
            return try #require(try queries.tree(id: uuid, connection: connection)?.tree)
        }

        let presentation = Self.presentation(TreeProfile(tree: tree))
        let facts = try #require(presentation.cityRecord?.facts)

        #expect(facts.contains { $0.value == "Friends of the Urban Forest" })
        #expect(facts.contains { $0.id == "plotSize" && $0.value.hasSuffix(" ft wide") })
        #expect(facts.contains { $0.id == "permitNotes" } == false)
        #expect(presentation.cityRecordNotes.contains(CityRecordPresentation.pruningNote))
        #expect(presentation.landContextNote != nil)
    }
}
