import Foundation
import Testing
@testable import Cypress

/// Screen 08, derived.
///
/// The two things this suite exists to stop are the two that regress silently, because both leave a
/// screen that still looks designed:
///
/// - **An aggregate below its cold-start threshold rendering anyway** (ARCHITECTURE §5.6, A9). A
///   ring reading `0 of 215` under the caption "you can recognize in the Sunset/Parkside" is a
///   sentence about nothing, drawn at full fidelity.
/// - **A count taken off an incomplete read** (ERRATA E38). Here the error flatters: a short
///   denominator makes the ring fuller than it is, and nobody files a bug about a number that is
///   too kind.
@Suite("Grove presentation")
struct GrovePresentationTests {

    // MARK: - Fixtures

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
        return calendar
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date()
    }

    private static let now = date(2026, 7, 21)

    private static func speciesID(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "08000000-0000-4000-8000-%012d", index))!
    }

    private static func known(
        _ index: Int,
        scientific: String = "Cupressus macrocarpa",
        common: String = "Monterey Cypress",
        metOn met: Date = date(2024, 5, 1),
        address: String? = "1450 Noriega St"
    ) -> KnownSpecies {
        KnownSpecies(
            speciesID: speciesID(index),
            scientificName: scientific,
            commonName: common,
            firstMetAt: met,
            firstMetAddress: address
        )
    }

    /// `count` species in the neighbourhood, the first `known.count` of which are the known ones.
    private static func neighborhood(
        totalling count: Int,
        complete: Bool = true,
        name: String = "Sunset/Parkside"
    ) -> GroveNeighborhood {
        GroveNeighborhood(
            area: .named(name),
            species: Series(items: (1...count).map(speciesID), isComplete: complete)
        )
    }

    private static func presentation(
        known: [KnownSpecies],
        knownIsComplete: Bool = true,
        neighborhood: GroveNeighborhood?,
        now: Date = now
    ) -> GrovePresentation {
        GrovePresentation(
            grove: GroveSpecies(
                neighborhood: neighborhood,
                known: Series(items: known, isComplete: knownIsComplete)
            ),
            now: now,
            calendar: calendar
        )
    }

    // MARK: - The ring, when it is honest

    @Test("The ring reads species recognised over species the city records nearby")
    func ringCountsSpeciesNotActions() throws {
        let subject = Self.presentation(
            known: (1...12).map { Self.known($0) },
            neighborhood: Self.neighborhood(totalling: 40)
        )
        let progress = try #require(subject.progress)

        // SCREENS.md 08 §3, verbatim shape: `12 of 40 species` / `you can recognize in the …`.
        #expect(progress.headline == "12 of 40 species")
        #expect(progress.caption == "you can recognize in the Sunset/Parkside")
        #expect(progress.ringLabel == "30%")
        #expect(abs(progress.fraction - 0.3) < 0.0001)
    }

    @Test("A species known but not growing nearby raises no numerator")
    func numeratorIsTheIntersection() throws {
        // Twelve known, but four of them are not in the neighbourhood's forty at all.
        let known = (1...8).map { Self.known($0) } + (41...44).map { Self.known($0) }
        let subject = Self.presentation(known: known, neighborhood: Self.neighborhood(totalling: 40))
        let progress = try #require(subject.progress)

        #expect(progress.headline == "8 of 40 species")
        // …and the grid still shows all twelve: the grid is what you know, the ring is what grows
        // where you walk.
        #expect(subject.tiles.filter(\.isKnown).count == 12)
    }

    @Test("The ring never rounds itself up to full")
    func ringLabelRoundsDown() throws {
        let subject = Self.presentation(
            known: (1...39).map { Self.known($0) },
            neighborhood: Self.neighborhood(totalling: 40)
        )
        #expect(try #require(subject.progress).ringLabel == "97%")
    }

    // MARK: - Below the cold-start threshold, nothing renders

    @Test("A device that has contributed nothing renders no ring, no callout and no grid")
    func emptyGroveRendersNothing() {
        let subject = Self.presentation(known: [], neighborhood: nil)

        #expect(subject.progress == nil)
        #expect(subject.celebration == nil)
        #expect(subject.tiles.isEmpty)
        #expect(subject.isEmpty)
        // The one thing that always renders. It is the whole empty state.
        #expect(subject.footnote == "Quiet collecting. There are no streaks and no leaderboards.")
    }

    @Test("Zero recognised species renders no ring rather than a ring at zero")
    func zeroRecognizedIsBelowThreshold() {
        // A contributor whose only species does not grow in their own neighbourhood: the
        // neighbourhood is known, the denominator is known, and the numerator is 0.
        let subject = Self.presentation(
            known: [Self.known(99)],
            neighborhood: Self.neighborhood(totalling: 40)
        )

        #expect(subject.progress == nil)
        // Not the empty grove, though — the species they do know is still theirs.
        #expect(subject.tiles.contains { $0.isKnown })
    }

    @Test("One recognised species is the threshold, and it renders")
    func oneRecognizedSpeciesRenders() throws {
        let subject = Self.presentation(
            known: [Self.known(1)],
            neighborhood: Self.neighborhood(totalling: 40)
        )
        #expect(try #require(subject.progress).headline == "1 of 40 species")
    }

    @Test("A neighbourhood the city has no species for renders no ring")
    func emptyNeighborhoodRendersNothing() {
        let subject = Self.presentation(
            known: [Self.known(1)],
            neighborhood: GroveNeighborhood(area: .named("Treasure Island"), species: .empty)
        )
        #expect(subject.progress == nil)
    }

    // MARK: - Counts off an incomplete read do not render

    @Test("A page of known species prints no fraction")
    func pagedNumeratorPrintsNothing() {
        let subject = Self.presentation(
            known: (1...12).map { Self.known($0) },
            knownIsComplete: false,
            neighborhood: Self.neighborhood(totalling: 40)
        )

        #expect(subject.progress == nil)
        // The rows themselves are still true — every one of them is a species this contributor met
        // — so the grid draws. It is the *count* that the page cannot support.
        #expect(subject.tiles.filter(\.isKnown).count == 12)
    }

    @Test("A page of the neighbourhood's species prints no fraction")
    func pagedDenominatorPrintsNothing() {
        let subject = Self.presentation(
            known: (1...12).map { Self.known($0) },
            neighborhood: Self.neighborhood(totalling: 40, complete: false)
        )
        #expect(subject.progress == nil)
    }

    @Test("Filtering the known series to the neighbourhood cannot launder a page into a total")
    func intersectionKeepsIncompleteness() {
        // The guarantee `Series.filter` gives, exercised through the screen that depends on it: a
        // page filtered by a visibility rule is still a page.
        let page = Series(items: (1...12).map { Self.known($0) }, isComplete: false)
        let neighborhoodIDs = Set((1...40).map(Self.speciesID))
        let intersection = page.filter { neighborhoodIDs.contains($0.speciesID) }

        #expect(intersection.items.count == 12)
        #expect(intersection.totalCount == nil)
    }

    // MARK: - The grid

    @Test("Tiles read oldest first, in the order the collection was built")
    func tilesAreOldestFirst() {
        let subject = Self.presentation(
            known: [
                Self.known(3, common: "Brisbane Box", metOn: Self.date(2026, 1, 4)),
                Self.known(1, common: "Monterey Cypress", metOn: Self.date(2024, 3, 9)),
                Self.known(2, common: "Ginkgo", metOn: Self.date(2025, 6, 2))
            ],
            neighborhood: Self.neighborhood(totalling: 40)
        )
        #expect(subject.tiles.compactMap(\.knownLabel) == ["Monterey Cypress", "Ginkgo", "Brisbane Box"])
    }

    @Test("Locked tiles square off the last row and never out-run what is left to meet")
    func lockedTilesPadTheRow() {
        // Seven known in a 3-column grid leaves two cells in the last row, and the neighbourhood has
        // thirty-three species left, so both are drawn — the mock's nine cells exactly.
        let padded = Self.presentation(
            known: (1...7).map { Self.known($0) },
            neighborhood: Self.neighborhood(totalling: 40)
        )
        #expect(padded.tiles.count == 9)
        #expect(padded.tiles.filter(\.isLocked).count == 2)

        // Forty known of forty-one leaves one species to meet, and forty tiles leave two cells in
        // the last row. One locked tile is drawn where the row wants two: the padding never claims
        // there is more left than there is.
        let almostComplete = Self.presentation(
            known: (1...40).map { Self.known($0) },
            neighborhood: Self.neighborhood(totalling: 41)
        )
        #expect(almostComplete.tiles.filter(\.isLocked).count == 1)

        // A full row needs no padding at all.
        let full = Self.presentation(
            known: (1...9).map { Self.known($0) },
            neighborhood: Self.neighborhood(totalling: 40)
        )
        #expect(full.tiles.filter(\.isLocked).isEmpty)
    }

    @Test("A page is never padded — the last row of a page is not the last row of the series")
    func pagesAreNotPadded() {
        let subject = Self.presentation(
            known: (1...7).map { Self.known($0) },
            knownIsComplete: false,
            neighborhood: Self.neighborhood(totalling: 40)
        )
        #expect(subject.tiles.count == 7)
        #expect(subject.tiles.filter(\.isLocked).isEmpty)
    }

    // MARK: - The celebration

    @Test("A find from yesterday is celebrated, in the mock's own words")
    func celebrationUsesTheDrawnCopy() throws {
        let subject = Self.presentation(
            known: [
                Self.known(1, metOn: Self.date(2024, 5, 1)),
                Self.known(
                    2,
                    scientific: "Pittosporum undulatum",
                    common: "Victorian Box",
                    metOn: Self.date(2026, 7, 20),
                    address: "1450 Noriega St"
                )
            ],
            neighborhood: Self.neighborhood(totalling: 40)
        )
        let celebration = try #require(subject.celebration)

        #expect(celebration.leadIn == "New species!")
        #expect(celebration.body == " First Victorian Box, spotted yesterday on Noriega St.")
    }

    @Test("A find older than yesterday is not celebrated")
    func celebrationHasAWindow() {
        let subject = Self.presentation(
            known: [Self.known(1, metOn: Self.date(2026, 7, 18))],
            neighborhood: Self.neighborhood(totalling: 40)
        )
        #expect(subject.celebration == nil)
    }

    @Test("A tree with no recorded address loses the clause rather than gaining a location")
    func celebrationDropsTheStreetItDoesNotHave() throws {
        let subject = Self.presentation(
            known: [
                Self.known(
                    1,
                    scientific: "Metrosideros excelsa",
                    common: "Pōhutukawa",
                    metOn: Self.date(2026, 7, 21),
                    address: nil
                )
            ],
            neighborhood: Self.neighborhood(totalling: 40)
        )
        #expect(try #require(subject.celebration).body == " First Pōhutukawa, spotted today.")
    }

    // MARK: - No count of anybody's actions reaches the screen

    @Test("Nothing the screen renders is a count of contributions")
    func nothingCountsContributions() throws {
        // One species, met on twenty separate occasions — which the payload cannot even express,
        // and that is the point: `KnownSpecies` carries no such number and neither does anything
        // derived from it. The rendered strings are checked so that a future field could not leak
        // into one (D1, ARCHITECTURE §5.1).
        let subject = Self.presentation(
            known: [Self.known(1, metOn: Self.date(2026, 7, 21))],
            neighborhood: Self.neighborhood(totalling: 40)
        )
        let progress = try #require(subject.progress)
        // Every string the screen *derives*. The footnote is excluded because it is the fixed
        // disclaimer and says the word "streaks" on purpose — it is asserted separately, verbatim,
        // in `emptyGroveRendersNothing`.
        let derived = [progress.headline, progress.caption, try #require(subject.celebration).body]

        for line in derived {
            #expect(!line.lowercased().contains("visit"))
            #expect(!line.lowercased().contains("photo"))
            #expect(!line.lowercased().contains("streak"))
            #expect(!line.lowercased().contains("care"))
        }
    }

    // MARK: - Tile artwork

    @Test("Artwork is stable and genus-led, and never invents a likeness")
    func artworkIsStable() {
        let ginkgo = Self.known(1, scientific: "Ginkgo biloba", common: "Ginkgo")
        #expect(SpeciesTileArtwork.art(for: ginkgo) == .ginkgo)

        let cypress = Self.known(2, scientific: "Hesperocyparis macrocarpa", common: "Monterey Cypress")
        #expect(SpeciesTileArtwork.art(for: cypress) == .montereyCypress)

        // A species with no authored artwork gets the same tile every time it is asked for.
        let unknown = Self.known(3, scientific: "Lagunaria patersonii", common: "Primrose Tree")
        #expect(SpeciesTileArtwork.art(for: unknown) == SpeciesTileArtwork.art(for: unknown))
    }
}

// MARK: - Tile helpers

private extension GrovePresentation.Tile {
    var isKnown: Bool {
        if case .known = self { return true }
        return false
    }

    var isLocked: Bool {
        if case .locked = self { return true }
        return false
    }

    var knownLabel: String? {
        if case let .known(_, label, _) = self { return label }
        return nil
    }
}
