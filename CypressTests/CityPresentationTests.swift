import Foundation
import Testing
@testable import Cypress

/// Presentation-layer tests for the Journal tab's `City` segment — the synthetic-fixture half of the
/// suite; `CityQueriesTests` covers the real-seed half.
///
/// Three things this file exists to prove, each a floor `CityLimits` names and none of them
/// negative-only: every gate below is exercised on both sides, so a test that stopped firing would
/// itself go red rather than pass by no longer covering anything (the standing instruction to prove
/// a test can fail).
/// 1. Card 1 renders only with a real local sample, a real per-species sample, and a real gap — and
///    caps at three, ranked by the gap.
/// 2. Card 3's five oldest carry the non-negotiable hedge, and the card says the truer, weaker thing
///    when a sixth tree ties the fifth's year.
/// 3. Nothing this file's copy prints ever names a city.
@Suite("City segment · presentation")
struct CityPresentationTests {

    // MARK: - Fixtures

    private static let locale = Locale(identifier: "en_US_POSIX")

    private static func id(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "C1700000-0000-4000-8000-%012d", index))!
    }

    private static func composition(_ shares: [(id: Int, count: Int)]) -> NeighborhoodComposition {
        let leading = shares.map { SpeciesShare(speciesID: id($0.id), name: "Species \($0.id)", treeCount: $0.count) }
        return NeighborhoodComposition(
            distinctSpeciesCount: leading.count,
            treeCount: leading.reduce(0) { $0 + $1.treeCount },
            leading: leading
        )
    }

    private static func present(_ snapshot: CityAlmanac.Snapshot?) -> CityPresentation {
        CityPresentation(city: CityAlmanac(snapshot: snapshot), locale: locale)
    }

    private static func elder(
        _ index: Int,
        name: String? = nil,
        species: String? = nil,
        address: String? = nil,
        year: Int
    ) -> ElderTree {
        ElderTree(treeID: id(index), activeName: name, speciesCommonName: species, address: address, plantedYear: year)
    }

    // MARK: - hasCity / isEmpty

    @Test("no resolved city renders nothing, and hasCity says so")
    func noCityRendersNothing() {
        let presentation = Self.present(nil)
        #expect(presentation.hasCity == false)
        #expect(presentation.contrast == nil)
        #expect(presentation.composition == nil)
        #expect(presentation.oldest == nil)
    }

    @Test("a resolved city with nothing to report is empty, not absent")
    func resolvedCityWithNothingIsEmpty() {
        let presentation = Self.present(CityAlmanac.Snapshot())
        #expect(presentation.hasCity == true)
        #expect(presentation.isEmpty == true)
    }

    // MARK: - Card 1 · Your streets, against the city

    /// Below `CityLimits.minimumLocalTreesForContrast` — a huge divergence does not buy its way past
    /// a thin local sample.
    @Test("card 1 renders nothing below the local sample floor")
    func contrastNeedsARealLocalSample() {
        let local = Self.composition([(id: 1, count: 10)]) // 10 < minimumLocalTreesForContrast (20)
        let city = Self.composition([(id: 1, count: 10), (id: 2, count: 990)]) // species 1 is 1% citywide
        let presentation = Self.present(CityAlmanac.Snapshot(localComposition: local, cityComposition: city))
        #expect(presentation.contrast == nil, "a 10-tree local sample produced a card")
    }

    /// A real sample on both sides, and genuinely no gap — every local share equals its city share.
    @Test("card 1 renders nothing with a real sample and no divergence")
    func contrastNeedsARealGap() {
        let local = Self.composition([(id: 1, count: 5), (id: 2, count: 20)]) // 25 trees, 20%/80%
        let city = Self.composition([(id: 1, count: 200), (id: 2, count: 800)]) // 1,000 trees, same split
        let presentation = Self.present(CityAlmanac.Snapshot(localComposition: local, cityComposition: city))
        #expect(presentation.contrast == nil, "an identical local and city split produced a card")
    }

    /// Below `CityLimits.minimumLocalSpeciesCount` — two trees of a rare species can carry a large
    /// percentage gap purely from a thin sample, and this floor is what stops that from speaking.
    @Test("card 1 ignores a divergence built from too few local trees of that species")
    func contrastNeedsARealPerSpeciesSample() {
        let local = Self.composition([(id: 1, count: 2), (id: 2, count: 23)]) // 25 trees; species 1 is 8%
        let city = Self.composition([(id: 1, count: 1), (id: 2, count: 999)]) // species 1 is 0.1% citywide
        let presentation = Self.present(CityAlmanac.Snapshot(localComposition: local, cityComposition: city))
        #expect(presentation.contrast == nil, "a two-tree local sample produced a divergence row")
    }

    /// The positive case, with the owner's own example numbers: a species at 18% locally and 4%
    /// citywide, sentence and all — and three more candidates to prove the ranking and the cap.
    @Test("card 1 names the two or three most divergent species, ranked by the gap, capped at three")
    func contrastRanksAndCaps() throws {
        let local = Self.composition([
            (id: 1, count: 18), (id: 2, count: 17), (id: 3, count: 16), (id: 4, count: 10), (id: 5, count: 39)
        ]) // 100 trees
        let city = Self.composition([
            (id: 1, count: 40), (id: 2, count: 40), (id: 3, count: 40), (id: 4, count: 40), (id: 5, count: 840)
        ]) // 1,000 trees — species 1-4 each 4% citywide, species 5 (filler) 84%
        let presentation = Self.present(CityAlmanac.Snapshot(localComposition: local, cityComposition: city))

        let contrast = try #require(presentation.contrast)
        #expect(contrast.label == "Your streets, against the city")
        #expect(contrast.rows.count == 3, "four species qualified; the cap did not apply")
        // Ranked by the gap: species 1 (14 points) > species 2 (13) > species 3 (12) > species 4
        // (6, dropped by the cap).
        #expect(contrast.rows.map(\.speciesID) == [Self.id(1), Self.id(2), Self.id(3)])
        #expect(
            contrast.rows[0].sentence == "Species 1 is 18% of the trees near you and 4% citywide.",
            "got: \(contrast.rows[0].sentence)"
        )
    }

    // MARK: - Card 3 · The oldest on file

    @Test("card 3 renders nothing when the city has no dated standing tree")
    func oldestNeedsAtLeastOneRow() {
        let presentation = Self.present(CityAlmanac.Snapshot(oldest: []))
        #expect(presentation.oldest == nil)
    }

    @Test("fewer than five dated trees shows all of them, honestly, with no tie caveat")
    func fewerThanFiveShowsWhatExists() throws {
        let trees = (1...3).map { Self.elder($0, year: 1900 + $0) }
        let presentation = Self.present(CityAlmanac.Snapshot(oldest: trees))
        let oldest = try #require(presentation.oldest)
        #expect(oldest.rows.count == 3)
        #expect(!oldest.note.contains("shares the last one's year"))
    }

    @Test("a sixth row sharing the fifth's year softens the card's own claim")
    func tiedBoundarySoftensTheNote() throws {
        var trees = (1...5).map { Self.elder($0, year: 1900 + $0) } // 1901...1905
        trees.append(Self.elder(6, year: 1905)) // ties row 5 (index 4, year 1905)
        let presentation = Self.present(CityAlmanac.Snapshot(oldest: trees))

        let oldest = try #require(presentation.oldest)
        #expect(oldest.rows.count == 5, "the sixth (tied) row was drawn; it should only ever inform the note")
        #expect(
            oldest.note.contains("shares the last one's year"),
            "a tie at the boundary did not soften the card's claim: \(oldest.note)"
        )
    }

    @Test("a sixth row that does not tie the fifth draws five with no caveat")
    func untiedSixthRowDrawsPlainly() throws {
        var trees = (1...5).map { Self.elder($0, year: 1900 + $0) } // 1901...1905
        trees.append(Self.elder(6, year: 1920)) // no tie
        let presentation = Self.present(CityAlmanac.Snapshot(oldest: trees))

        let oldest = try #require(presentation.oldest)
        #expect(oldest.rows.count == 5)
        #expect(!oldest.note.contains("shares the last one's year"))
    }

    /// The hedge, non-negotiable and per row: `AlmanacCopy.elderSubtitle`'s own "in the city record
    /// since", never "planted in".
    @Test("every oldest-on-file row carries the record hedge, never a planting claim")
    func rowsCarryTheHedge() throws {
        let presentation = Self.present(CityAlmanac.Snapshot(oldest: [Self.elder(1, year: 1898)]))
        let row = try #require(presentation.oldest?.rows.first)
        #expect(row.subtitle == "in the city record since 1898")
        #expect(!row.subtitle.localizedCaseInsensitiveContains("planted"))
    }

    /// The subject chain: given name, then species, then street, then the app's own fallback — never
    /// empty, which `IconTextRow` cannot draw as an absence the way it draws an empty subtitle.
    @Test("a row's title falls back from the tree's name to its species to its street to Tree")
    func rowTitleFallsBackInOrder() throws {
        let named = ElderTree(treeID: Self.id(1), activeName: "Grandmother Cypress", speciesCommonName: "Monterey Cypress", address: "10 Elm St", plantedYear: 1900)
        let speciesOnly = ElderTree(treeID: Self.id(2), activeName: nil, speciesCommonName: "Blackwood Acacia", address: "20 Elm St", plantedYear: 1900)
        let streetOnly = ElderTree(treeID: Self.id(3), activeName: nil, speciesCommonName: nil, address: "1240 44th Ave", plantedYear: 1900)
        let bareRecord = ElderTree(treeID: Self.id(4), activeName: nil, speciesCommonName: nil, address: nil, plantedYear: 1900)

        let presentation = Self.present(CityAlmanac.Snapshot(oldest: [named, speciesOnly, streetOnly, bareRecord]))
        let rows = try #require(presentation.oldest?.rows)

        #expect(rows[0].title == "Grandmother Cypress")
        #expect(rows[1].title == "Blackwood Acacia")
        #expect(rows[2].title == "The tree on 44th Ave")
        #expect(rows[3].title == TreeProfilePresentation.fallbackTitle)
    }

    // MARK: - Card 2 · Who lives here (the reused composition math)

    /// A sanity check that the City segment's composition card is `AlmanacPresentation.composition`
    /// itself, not a second implementation — same label format, same remainder discipline.
    @Test("card 2 is the almanac's own composition math, scoped to the city")
    func compositionIsReusedVerbatim() throws {
        // Sorted descending, as `CityQueries.speciesMix`'s own `ORDER BY tree_count DESC` guarantees
        // — `AlmanacPresentation.composition` trusts that order rather than re-sorting it.
        let city = Self.composition([(id: 1, count: 40), (id: 2, count: 30), (id: 3, count: 20), (id: 4, count: 10)])
        let presentation = Self.present(CityAlmanac.Snapshot(cityComposition: city))
        let composition = try #require(presentation.composition)

        #expect(composition.label == "Who lives here · 4 species")
        #expect(composition.rows.count == 4, "three named plus one remainder row")
        #expect(composition.rows.last?.name == "Everyone else")
        #expect(composition.rows.last?.isRemainder == true)
    }

    // MARK: - No city named anywhere

    /// Every static string `CityCopy` owns, plus a representative dynamic one from each card, none of
    /// them naming a city — the file header's own claim, checked rather than assumed. Markers rather
    /// than a fixed string, the same discipline `SecondCityGeographyTests
    /// .theCountCardNamesThePopulationItCounted` uses for R48, so swapping one hardcoded city for
    /// another cannot satisfy this.
    @Test("no City segment copy names a city")
    func noCopyNamesACity() {
        let strings = [
            CityCopy.segmentLabel,
            CityCopy.contrastLabel,
            CityCopy.recordLabel,
            CityCopy.recordNote(tiedAtBoundary: false),
            CityCopy.recordNote(tiedAtBoundary: true),
            CityCopy.outOfRangeTitle,
            CityCopy.outOfRangeBody,
            CityCopy.loadFailed,
            CityCopy.loadRetry,
            CityCopy.locationPromptTitle,
            CityCopy.locationPromptSubtitle,
            CityCopy.footnote,
            CityCopy.recordSince(1898),
            CityCopy.recordSubject(name: nil, species: nil, street: nil),
            CityCopy.contrastSentence(name: "Monterey cypress", localShare: 0.18, cityShare: 0.04, locale: Self.locale)
        ]
        let markers = ["San Francisco", "San Jose", " SF ", "SF ·", "DataSF", "sf,", "us-ca-sj"]
        for string in strings {
            for marker in markers {
                #expect(
                    !string.contains(marker),
                    "\"\(string)\" names a city via the marker \"\(marker)\""
                )
            }
        }
    }
}
