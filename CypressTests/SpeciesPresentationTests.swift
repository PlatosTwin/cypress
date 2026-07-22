import Foundation
import Testing
@testable import Cypress

/// Screen 07, derived.
///
/// The screen's whole job is to render sourced content and render *nothing* where knowledge is
/// absent, so these tests are mostly assertions that something does not appear. The one most likely
/// to regress is the first: `leafRetention` is optional, every phenology surface hangs off it, and
/// the fix for "the chip row looks lopsided" is one `?? .deciduous` away (D5, ERRATA E9,
/// ARCHITECTURE §5.5).
@Suite("Species page presentation")
struct SpeciesPresentationTests {

    // MARK: - Fixtures

    private static let curatedID = UUID(uuidString: "F909A9EE-939C-5933-8220-66BB56D0C923")!
    private static let unsourcedID = UUID(uuidString: "3B0A1C55-0000-4000-8000-000000000702")!

    /// The seeded Monterey Cypress: curated, evergreen, three authored `id_tips`, no seasonal
    /// calendar and no care notes — exactly the row `Fixtures/species/curated.yaml` produces.
    private static func curated() throws -> Species {
        try Species(
            id: curatedID,
            scientificName: "Cupressus macrocarpa",
            commonName: "Monterey Cypress",
            family: "Cupressaceae",
            leafRetention: .evergreen,
            idTips: [
                IDTip(icon: "leaf", text: "Foliage is blunt scales pressed tight to the twig, not needles, and smells lemony when crushed."),
                IDTip(icon: "bark", text: "Dark grey to red-brown bark, fibrous and rough with irregular furrows."),
                IDTip(icon: "cone", text: "Round to elliptical cones an inch or so long that take two seasons to ripen.")
            ],
            curated: true
        )
    }

    /// One of the 59 seeded species with no sourced habit. `Acer spp` is a real one.
    private static func unsourcedHabit() throws -> Species {
        try Species(
            id: unsourcedID,
            scientificName: "Acer spp",
            commonName: "Maple",
            family: "Sapindaceae",
            leafRetention: nil
        )
    }

    /// One of the 529 with a habit and nothing authored.
    private static func uncurated() throws -> Species {
        try Species(
            scientificName: "Syzygium paniculatum",
            commonName: "Brush Cherry",
            family: "Myrtaceae",
            leafRetention: .evergreen
        )
    }

    private static func presentation(
        _ species: Species,
        month: Int = 7,
        cityTreeCount: Int? = 1_923,
        nearYou: SpeciesNeighborhoodCount? = nil,
        nearby: Series<NearbySpeciesTree> = .empty
    ) -> SpeciesPresentation {
        SpeciesPresentation(
            guide: SpeciesGuide(
                species: species,
                cityTreeCount: cityTreeCount,
                nearYou: nearYou,
                nearby: nearby
            ),
            month: month
        )
    }

    // MARK: - Unknown leaf retention renders no phenology surface

    @Test("a species with no sourced habit gets no phenology chip, and nothing stands in for one")
    func unknownHabitDrawsNoPhenology() throws {
        let page = Self.presentation(try Self.unsourcedHabit())

        #expect(page.showsPhenology == false)
        #expect(page.taxonomyChips.contains { $0.kind == .habit } == false)
        // Not a neutral chip, not a grey one, nothing: the family is the only chip left.
        #expect(page.taxonomyChips.map(\.kind) == [.family])
        #expect(page.taxonomyChips.map(\.label) == ["Sapindaceae"])
    }

    @Test("the habit chip cannot be constructed from an absent habit at all")
    func habitChipIsUnconstructibleWithoutAHabit() {
        // The type-level half of the same rule. There is no other initializer for `.habit`, so a
        // future caller cannot route around the presentation and draw one anyway.
        #expect(SpeciesTaxonomyChip.habit(nil) == nil)
        #expect(SpeciesTaxonomyChip.habit(.evergreen)?.label == "Evergreen")
        #expect(SpeciesTaxonomyChip.habit(.deciduous)?.label == "Deciduous")
        #expect(SpeciesTaxonomyChip.habit(.semiDeciduous)?.label == "Semi-deciduous")
    }

    @Test("an unsourced habit carries no phenology vocabulary either, in any month")
    func unknownHabitHasNoTagsAndNoLeafOnWindow() throws {
        let species = try Self.unsourcedHabit()
        // The Core half of E9, asserted here because screen 07's chip is the visible end of it.
        #expect(species.availablePhenologyTags.isEmpty)
        #expect(species.leafOnMonths == nil)
        for month in 1...12 {
            #expect(Self.presentation(species, month: month).showsPhenology == false)
        }
    }

    @Test("an unsourced habit still gets its name, its family and its population")
    func unknownHabitKeepsEverythingThatIsSourced() throws {
        let page = Self.presentation(
            try Self.unsourcedHabit(),
            nearYou: SpeciesNeighborhoodCount(neighborhoodName: "Sunset/Parkside", count: 61)
        )
        // Absence of a habit suppresses the phenology surface, not the page.
        #expect(page.commonName == "Maple")
        #expect(page.scientificName == "Acer spp")
        #expect(page.showsCountCards)
        #expect(page.nearYouCountText == "61")
    }

    // MARK: - A curated species renders its sourced content

    @Test("a curated species renders its authored id_tips, verbatim and in order")
    func curatedRendersItsSourcedContent() throws {
        let species = try Self.curated()
        let page = Self.presentation(species)

        #expect(page.showsRecognizeCard)
        #expect(page.idTipRows.count == 3)
        #expect(page.idTipRows.map(\.tip.text) == species.idTips.map(\.text))
        // The three glyph tints SCREENS.md 07 §3 draws, in the order it draws them.
        #expect(page.idTipRows.map(\.tint) == [.canopy, .newGrowth, .bark])

        #expect(page.showsPhenology)
        #expect(page.taxonomyChips.map(\.label) == ["Cupressaceae", "Evergreen"])
        #expect(page.commonName == "Monterey Cypress")
        #expect(page.scientificName == "Cupressus macrocarpa")
    }

    @Test("an evergreen carries no fall colour to render, at the type level")
    func evergreenCannotCarryFallColor() throws {
        let species = try Self.curated()
        #expect(species.leafRetention?.canShowFallColor == false)
        #expect(species.availablePhenologyTags.contains(.fallColor) == false)
        #expect(species.availablePhenologyTags.contains(.bare) == false)
        // D5 is enforced in `Species.init`, in the database CHECK and in the seed builder. This
        // asserts the throw exists rather than adding a fourth enforcement point.
        #expect(throws: SpeciesValidationError.self) {
            _ = try Species(
                scientificName: "Cupressus macrocarpa",
                commonName: "Monterey Cypress",
                leafRetention: .evergreen,
                seasonal: SeasonalCalendar(fallColorMonths: [11])
            )
        }
    }

    @Test("an uncurated species draws no recognize-it card rather than an empty one")
    func uncuratedDrawsNoCard() throws {
        let page = Self.presentation(try Self.uncurated())
        #expect(page.idTipRows.isEmpty)
        #expect(page.showsRecognizeCard == false)
        // It keeps everything that *is* sourced: family and habit.
        #expect(page.taxonomyChips.map(\.label) == ["Myrtaceae", "Evergreen"])
    }

    // MARK: - The seasonal callout

    @Test("a year-round care note is never presented as a note about this month")
    func yearRoundCareNoteDrawsNothing() throws {
        let species = try Species(
            scientificName: "Jacaranda mimosifolia",
            commonName: "Jacaranda",
            leafRetention: .semiDeciduous,
            careNotes: [
                CareNote(
                    monthRange: MonthRange(start: 1, end: 12)!,
                    text: "An uneven performer here. Prefers heat, wind protection and good drainage."
                )
            ]
        )
        // `curated.yaml`: "{start: 1, end: 12} means the source attaches no month restriction."
        for month in 1...12 {
            #expect(Self.presentation(species, month: month).seasonalNote == nil)
        }
    }

    @Test("a restricted care note draws in its own months and in no others")
    func restrictedCareNoteDrawsOnlyInItsWindow() throws {
        let species = try Species(
            scientificName: "Jacaranda mimosifolia",
            commonName: "Jacaranda",
            leafRetention: .semiDeciduous,
            careNotes: [
                CareNote(monthRange: MonthRange(start: 1, end: 12)!, text: "Year round."),
                CareNote(monthRange: MonthRange(start: 3, end: 5)!, text: "Expect leaf drop in spring.")
            ]
        )
        for month in 3...5 {
            #expect(Self.presentation(species, month: month).seasonalNote?.text == "Expect leaf drop in spring.")
        }
        for month in [1, 2, 6, 7, 8, 9, 10, 11, 12] {
            #expect(Self.presentation(species, month: month).seasonalNote == nil)
        }
    }

    @Test("a seasonal calendar alone never produces a sentence")
    func seasonalCalendarIsNotASourceForCopy() throws {
        // Ginkgo colours in November per the seeded calendar, and nobody wrote what to look for.
        let ginkgo = try Species(
            scientificName: "Ginkgo biloba",
            commonName: "Maidenhair Tree",
            leafRetention: .deciduous,
            seasonal: SeasonalCalendar(fallColorMonths: [11, 12])
        )
        #expect(Self.presentation(ginkgo, month: 11).seasonalNote == nil)
    }

    // MARK: - Counts are totals, never pages

    @Test("a count that was not taken renders nothing, which is not the same as zero")
    func absentCountIsNotZero() throws {
        let species = try Self.curated()
        #expect(Self.presentation(species, cityTreeCount: nil).cityTreeCountText == nil)
        #expect(Self.presentation(species, cityTreeCount: 0).cityTreeCountText == "0")
        #expect(Self.presentation(species, cityTreeCount: nil, nearYou: nil).showsCountCards == false)
    }

    @Test("a nearby row prints a photo count only when the whole series was read")
    func photoCountComesFromATotal() {
        // The E38 shape: `Series.totalCount` is nil for a page, and the sub-line drops the count
        // rather than printing the page's size.
        let page = Series(items: [Photo](), isComplete: false)
        #expect(page.totalCount == nil)
        #expect(SpeciesCopy.nearbySubtitle(photoCount: page.totalCount, vitality: .thriving) == "thriving")
        #expect(SpeciesCopy.nearbySubtitle(photoCount: 214, vitality: .thriving) == "214 photos · thriving")
        #expect(SpeciesCopy.nearbySubtitle(photoCount: 1, vitality: nil) == "1 photo")
        // A tree nobody has touched has no sub-line at all.
        #expect(SpeciesCopy.nearbySubtitle(photoCount: 0, vitality: nil) == nil)
    }

    @Test("without a fix there is no near-you card and no nearby list")
    func noFixMeansNoPopulationSurfaces() throws {
        let page = Self.presentation(try Self.curated(), nearYou: nil, nearby: .empty)
        #expect(page.nearYouCountText == nil)
        #expect(page.showsNearby == false)
        // The city count does not depend on where you are, so it stays.
        #expect(page.cityTreeCountText == "1,923")
    }
}
