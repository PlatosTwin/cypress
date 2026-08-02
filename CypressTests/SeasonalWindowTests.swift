import Foundation
import Testing
@testable import Cypress

/// `MonthRange.spanning(_:)` and `Species.leafOnMonths` — the phenological window, and the year
/// wrap that used to be lost in it.
///
/// `SeasonalCalendar` sorts its month arrays, which is right for a set and fatal for anything that
/// reads a start off `first` or an end off `last`: a fall authored as November, December, January
/// sorts to `[1, 11, 12]` and ends in December. `Vitality.isRatingPermitted` then hides the vitality
/// rows in January, a month the authored calendar says the tree is still in leaf, with no override
/// available to a rater standing in front of it (ERRATA E33).
///
/// No longer latent: the current seed carries seasonal data on 511 of 569 species (E189), so these
/// windows run against real calendars. The sentence that used to stand here — "every `seasonal` in
/// the shipped seed is empty" — was true of an earlier seed and aged into a false comment (E189
/// records the correction).
@Suite("Seasonal windows")
struct SeasonalWindowTests {

    // MARK: - The window, recovered from membership

    @Test("a contiguous run gives its own start and end")
    func plainRun() throws {
        let range = try #require(MonthRange.spanning([3, 4, 5]))
        #expect(range.start == 3)
        #expect(range.end == 5)
    }

    /// The property the whole fix rests on: the answer does not depend on how the author spelled
    /// the array, because a month array carries membership and nothing else.
    @Test("every spelling of November through January gives the same window", arguments: [
        [11, 12, 1], [1, 11, 12], [12, 1, 11], [1, 12, 11]
    ])
    func wrapIsOrderIndependent(months: [Int]) throws {
        let range = try #require(MonthRange.spanning(months))
        #expect(range.start == 11)
        #expect(range.end == 1)
        #expect(range.months == [11, 12, 1])
    }

    @Test("a single month is a window of one")
    func singleMonth() throws {
        let range = try #require(MonthRange.spanning([1]))
        #expect(range.start == 1)
        #expect(range.end == 1)
    }

    @Test("all twelve months is the whole year")
    func wholeYear() throws {
        let range = try #require(MonthRange.spanning(Array(1...12)))
        #expect(range.months == Set(1...12))
    }

    @Test("a set with a gap describes no single window")
    func gapHasNoWindow() {
        #expect(MonthRange.spanning([3, 7]) == nil)
        #expect(MonthRange.spanning([1, 2, 6, 7]) == nil)
    }

    @Test("no months is no window")
    func emptyHasNoWindow() {
        #expect(MonthRange.spanning([Int]()) == nil)
    }

    // MARK: - What it buys `leafOnMonths`

    private static func deciduous(
        newGrowth: [Int],
        fallColor: [Int]
    ) throws -> Species {
        try Species(
            scientificName: "Testus deciduus",
            commonName: "Test deciduous",
            leafRetention: .deciduous,
            seasonal: SeasonalCalendar(fallColorMonths: fallColor, newGrowthMonths: newGrowth),
            curated: true
        )
    }

    /// The regression itself. Before the fix this window ended in December and January was leaf-off.
    @Test("a fall colour that wraps the year keeps its January")
    func leafOnWrapsTheYear() throws {
        let species = try Self.deciduous(newGrowth: [3, 4], fallColor: [11, 12, 1])
        let months = try #require(species.leafOnMonths)

        #expect(months == [3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 1])
        #expect(months.contains(1))
        #expect(!months.contains(2))
    }

    /// And the consequence that made it worth fixing: the vitality UI is the thing that disappears.
    @Test("vitality stays rateable in the wrapped month, and only there")
    func ratingFollowsTheWrappedWindow() throws {
        let species = try Self.deciduous(newGrowth: [3, 4], fallColor: [11, 12, 1])

        #expect(Vitality.isRatingPermitted(for: species, month: 1))
        #expect(Vitality.suppression(for: species, month: 1) == .none)
        #expect(!Vitality.isRatingPermitted(for: species, month: 2))
        #expect(Vitality.suppression(for: species, month: 2) == .leafOffSeason)
    }

    /// The ordinary non-wrapping case did not regress.
    @Test("a northern-hemisphere calendar that does not wrap is unchanged")
    func nonWrappingCalendar() throws {
        let species = try Self.deciduous(newGrowth: [4, 5], fallColor: [10, 11])
        #expect(species.leafOnMonths == Set(4...11))
    }

    /// The authored order of the source array reaches nothing, at either end.
    @Test("neither end of the window depends on how the arrays were written")
    func authoringOrderIsIrrelevant() throws {
        let asWritten = try Self.deciduous(newGrowth: [4, 3], fallColor: [1, 12, 11])
        let sorted = try Self.deciduous(newGrowth: [3, 4], fallColor: [11, 12, 1])
        #expect(asWritten.leafOnMonths == sorted.leafOnMonths)
    }

    @Test("an absent season falls back to April through October")
    func fallbackWhenUnauthored() throws {
        let noFall = try Self.deciduous(newGrowth: [3, 4], fallColor: [])
        #expect(noFall.leafOnMonths == Species.defaultDeciduousLeafOnMonths)

        let noGrowth = try Self.deciduous(newGrowth: [], fallColor: [10, 11])
        #expect(noGrowth.leafOnMonths == Species.defaultDeciduousLeafOnMonths)
    }

    /// A season with a gap states no window, so the documented default applies rather than a window
    /// invented across the gap.
    @Test("a gapped season falls back rather than spanning the gap")
    func gappedSeasonFallsBack() throws {
        let species = try Self.deciduous(newGrowth: [3, 4], fallColor: [7, 11])
        #expect(species.leafOnMonths == Species.defaultDeciduousLeafOnMonths)
    }

    /// The two habits that never consult the calendar, and the one that has no window to state
    /// (ERRATA E9).
    @Test("habit still decides before the calendar does")
    func habitFirst() throws {
        let evergreen = try Species(
            scientificName: "Hesperocyparis macrocarpa",
            commonName: "Monterey cypress",
            leafRetention: .evergreen,
            seasonal: SeasonalCalendar(newGrowthMonths: [3, 4]),
            curated: true
        )
        #expect(evergreen.leafOnMonths == Set(1...12))

        let unknown = try Species(
            scientificName: "Ignotum arbor",
            commonName: "Unsourced",
            leafRetention: nil,
            seasonal: SeasonalCalendar(fallColorMonths: [11, 12, 1], newGrowthMonths: [3, 4])
        )
        #expect(unknown.leafOnMonths == nil)
    }
}
