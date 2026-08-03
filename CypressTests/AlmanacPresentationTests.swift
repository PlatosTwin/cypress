import Foundation
import Testing
@testable import Cypress

/// **Screen 12 is the screen ARCHITECTURE §5.6 was written for**, and the rule it states —
/// "aggregate surfaces below their cold-start threshold do not render at all" — is the one thing
/// about this screen that can break without anybody noticing.
///
/// It breaks quietly because the failure looks like working software. A card reading
/// `0 young trees with no visits since planting` under the heading `Where eyes are needed`, or
/// `First bloom of the year · 0 neighbors saw it`, renders, lays out, and is wrong in a way no
/// crash reports and no screenshot review catches on a screen whose whole subject is what is and is
/// not there. So the assertions below are mostly negative: not "the number is right" but "there is
/// no number".
///
/// Three documents set the floors and all three are exercised here:
/// - **A9**: "bloom sightings need 1, species mix always renders from city data, coverage panel
///   always renders".
/// - **A8**: a headcount of people is shown only at three or more.
/// - **ERRATA E38**: a page's size is not a total, so an incomplete read prints no count at all.
@Suite("Almanac · below-threshold aggregates render nothing")
struct AlmanacPresentationTests {

    // MARK: - Fixtures

    private static let now = Date(timeIntervalSince1970: 1_784_505_600) // 2026-07-20
    private static let january = Date(timeIntervalSince1970: 1_768_953_600) // 2026-01-21
    /// UTC, so a window boundary is the same boundary on every machine that runs this. The windows
    /// themselves take the *reader's* calendar in the app — "this spring" is the reader's spring —
    /// which is exactly why the test has to pin one.
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private static let locale = Locale(identifier: "en_US_POSIX")

    private static func id(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "12000000-0000-4000-8000-%012d", index))!
    }

    private static func present(_ area: AlmanacNeighborhood?) -> AlmanacPresentation {
        AlmanacPresentation(
            almanac: Almanac(neighborhood: area),
            now: now,
            calendar: calendar,
            locale: locale
        )
    }

    private static let elder = ElderTree(
        treeID: id(2),
        activeName: nil,
        speciesCommonName: "Blackwood Acacia",
        address: "1783 41st Ave",
        plantedYear: 1956
    )

    private static let composition = NeighborhoodComposition(
        distinctSpeciesCount: 215,
        treeCount: 11_026,
        leading: [
            SpeciesShare(speciesID: id(10), name: "New Zealand Xmas Tree", treeCount: 1_561),
            SpeciesShare(speciesID: id(11), name: "Hybrid Strawberry Tree", treeCount: 827),
            SpeciesShare(speciesID: id(12), name: "Monterey Cypress", treeCount: 816),
            SpeciesShare(speciesID: id(13), name: "Monterey Pine", treeCount: 698)
        ]
    )

    private static func bloom(observers: Int) -> BloomFirst {
        BloomFirst(
            treeID: id(1),
            speciesCommonName: "Red flowering gum",
            address: "1240 44th Ave",
            firstSeenAt: january,
            observerCount: observers
        )
    }

    /// A city-inventory pin, spread along one street (ERRATA E129). `.cityImport` / `.cityRecord`
    /// because every row of the shipped seed is — asserted over all 195,309 in
    /// `PinSetDestinationTests`.
    static func pin(_ index: Int, status: TreeStatus = .alive) -> TreePin {
        TreePin(
            id: id(index),
            coordinate: Coordinate(
                latitude: 37.7530 + Double(index % 40) * 0.000_35,
                longitude: -122.4850 + Double(index % 40) * 0.000_20
            ),
            status: status,
            source: .cityImport,
            verificationState: .cityRecord,
            speciesID: nil
        )
    }

    private static func coverage(_ count: Int, farthestM: Double, isComplete: Bool = true) -> CoverageGap {
        let trees = (0..<count).map { index -> CoverageTree in
            let step = count <= 1 ? farthestM : Double(index) / Double(count - 1) * farthestM
            return CoverageTree(pin: pin(100 + index), distanceM: step)
        }
        return CoverageGap(trees: Series(items: trees, isComplete: isComplete))
    }

    /// Every string the screen would put in front of a reader, so a sweep can assert on all of them
    /// at once. If a block is added to the view without being added here the sweep silently stops
    /// covering it, which is why the view draws nothing that is not on the presentation.
    private static func renderedStrings(_ presentation: AlmanacPresentation) -> [String] {
        var strings: [String] = [presentation.footnote]
        if let name = presentation.neighborhoodName { strings.append(name) }
        // R29's qualifier under the header, present only for a fallback area.
        if let note = presentation.areaNote { strings.append(note) }
        // E182's two sentences, drawn in place of every block when the read resolved no area at all.
        if !presentation.hasArea {
            strings.append(AlmanacCopy.outOfRangeTitle)
            strings.append(AlmanacCopy.outOfRangeBody)
        }
        // §2's note, which draws with the rows it describes (task #177).
        if let note = presentation.seasonNote { strings.append(note) }
        for row in presentation.seasonRows {
            strings.append(row.title)
            strings.append(row.subtitle)
        }
        if let composition = presentation.composition {
            strings.append(composition.label)
            for row in composition.rows {
                strings.append(row.name)
                strings.append(row.value)
            }
        }
        if let coverage = presentation.coverage {
            strings.append(coverage.title)
            strings.append(coverage.body)
            strings.append(coverage.ctaTitle)
        }
        return strings
    }

    /// A standalone `0` or a spelled `zero` anywhere in a rendered string.
    ///
    /// Word-bounded so `2026` and `10%` do not trip it: the failure this catches is a *quantity* of
    /// nothing being printed, not the digit existing.
    private static func containsAZero(_ strings: [String]) -> Bool {
        strings.contains { string in
            string.range(of: #"(?<![\d.,%])0(?![\d.,%])"#, options: .regularExpression) != nil
                || string.range(of: #"\bzero\b"#, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    // MARK: - No area at all

    @Test("no area means no almanac, not an empty one")
    func noNeighborhoodRendersNoBlocks() {
        let presentation = Self.present(nil)

        #expect(presentation.neighborhoodName == nil)
        #expect(presentation.hasArea == false)
        #expect(presentation.areaNote == nil)
        #expect(presentation.seasonRows.isEmpty)
        #expect(presentation.composition == nil)
        #expect(presentation.coverage == nil)
        #expect(presentation.isEmpty)

        // The header pill has no name in it, which is the point: a header naming an area we could
        // not determine would be the screen's first lie (A4, ERRATA E44).
        //
        // **It used to be the footnote alone**, and that was the defect ERRATA E182 is about: a
        // finished read that resolved nothing drew the same picture as a read still in flight. The
        // two sentences beside the footnote are what a reader standing outside the record now gets.
        #expect(
            Self.renderedStrings(presentation)
                == [AlmanacCopy.footnote, AlmanacCopy.outOfRangeTitle, AlmanacCopy.outOfRangeBody]
        )
    }

    // MARK: - The whole sweep

    /// The one that matters: a neighbourhood with nothing behind any of its aggregates prints no
    /// number anywhere, and no card frames an absence.
    @Test("every aggregate below its floor is absent, and nothing prints a zero")
    func belowThresholdEverywhere() {
        let presentation = Self.present(
            AlmanacNeighborhood(
                area: .named("Sunset/Parkside"),
                firstBloom: nil,                                      // A9: needs 1 sighting
                elder: nil,                                           // no recorded planting date
                newestNeighbors: RecentPlanting(treeCount: 0, leadingSpecies: []),
                composition: NeighborhoodComposition(
                    distinctSpeciesCount: 0, treeCount: 0, leading: []
                ),
                coverage: Self.coverage(0, farthestM: 0)
            )
        )

        #expect(presentation.seasonRows.isEmpty, "a season row drew with nothing behind it")
        #expect(presentation.composition == nil, "the composition card drew with no trees in it")
        #expect(presentation.coverage == nil, "the coverage card drew with nothing to attend to")
        #expect(presentation.isEmpty)

        let strings = Self.renderedStrings(presentation)
        #expect(!Self.containsAZero(strings), "a zero reached the screen: \(strings)")
        // The neighbourhood is known, so its name is still the header's — that is a fact, not an
        // aggregate, and §5.6 does not reach it.
        #expect(strings == [AlmanacCopy.footnote, "Sunset/Parkside"])
    }

    // MARK: - A9 · bloom sightings need 1

    @Test("no flowering visit means no bloom row at all")
    func noBloomSightingRendersNoRow() {
        let presentation = Self.present(
            AlmanacNeighborhood(area: .named("Sunset/Parkside"), firstBloom: nil, elder: Self.elder)
        )
        #expect(!presentation.seasonRows.contains { $0.kind == .bloom })
        #expect(presentation.seasonRows.map(\.kind) == [.elder])
        #expect(AlmanacThresholds.minimumBloomSightings == 1)
    }

    @Test("one sighting is a first bloom")
    func oneSightingRendersTheRow() {
        let presentation = Self.present(
            AlmanacNeighborhood(area: .named("Sunset/Parkside"), firstBloom: Self.bloom(observers: 1))
        )
        let row = presentation.seasonRows.first { $0.kind == .bloom }
        #expect(row?.title == "First bloom of the year")
    }

    // MARK: - A8 · a headcount needs 3

    @Test("below three observers the sighting is reported and the headcount is not")
    func headcountBelowA8IsDropped() {
        for observers in 0...2 {
            let presentation = Self.present(
                AlmanacNeighborhood(area: .named("Sunset/Parkside"), firstBloom: Self.bloom(observers: observers))
            )
            let subtitle = presentation.seasonRows.first { $0.kind == .bloom }?.subtitle ?? ""
            #expect(
                !subtitle.contains("saw it"),
                "\(observers) observers produced a headcount clause: \(subtitle)"
            )
            // And the row is still there — A9 floors the sighting at one, A8 floors the headcount at
            // three, and they are different claims about the same event.
            #expect(subtitle.contains("Red flowering gum"))
            #expect(!Self.containsAZero([subtitle]), "a zero reached the bloom row: \(subtitle)")
        }
    }

    @Test("at three observers the headcount is spelled out, as the mock spells it")
    func headcountAtA8Renders() {
        let presentation = Self.present(
            AlmanacNeighborhood(area: .named("Sunset/Parkside"), firstBloom: Self.bloom(observers: 3))
        )
        let subtitle = presentation.seasonRows.first { $0.kind == .bloom }?.subtitle ?? ""
        #expect(subtitle.contains("three neighbors saw it"), "\(subtitle)")
        // SCREENS.md's own separator and street form.
        #expect(subtitle.hasPrefix("Red flowering gum on 44th Ave · "), "\(subtitle)")
        #expect(AlmanacThresholds.minimumObservers == 3)
    }

    // MARK: - §2 · the elder and the newest neighbours

    @Test("the elder says what the record says, not what the tree is")
    func elderCitesTheRecord() {
        let presentation = Self.present(
            AlmanacNeighborhood(area: .named("Sunset/Parkside"), elder: Self.elder)
        )
        let row = presentation.seasonRows.first { $0.kind == .elder }
        #expect(row?.subtitle == "Blackwood Acacia · in the city record since 1956")
        // A year is an identifier, never a grouped quantity.
        #expect(row?.subtitle.contains("1,956") == false)
    }

    @Test("a named tree is named, an unnamed one falls back and nothing is invented")
    func elderNameFallsBack() {
        let named = AlmanacCopy.elderSubtitle(
            name: "Grandmother Cypress", species: "Monterey Cypress", street: "41st Ave", plantedYear: 1898
        )
        #expect(named == "Grandmother Cypress · in the city record since 1898")

        let street = AlmanacCopy.elderSubtitle(name: nil, species: nil, street: "41st Ave", plantedYear: 1956)
        #expect(street == "The tree on 41st Ave · in the city record since 1956")

        // No name, no species, no address: the sentence stands alone rather than acquiring a subject.
        let bare = AlmanacCopy.elderSubtitle(name: nil, species: nil, street: nil, plantedYear: 1956)
        #expect(bare == "in the city record since 1956")
    }

    /// #176: a season row draws that tree's own photograph instead of the accent tile when the
    /// payload carries one. The presentation's whole job here is passthrough — `LocalAPI` chooses
    /// the id (`PhotoHeroTests` and `HeroPhotoIDsTests` cover the choosing) — so what this asserts
    /// is that the id survives the trip from `ElderTree`/`BloomFirst` to `SeasonRow` and that the
    /// group-only `newestNeighbors` row, which names no tree, never carries one.
    @Test("a season row carries the tree's own hero photo id through, and only when it names a tree")
    func seasonRowsCarryTheHeroPhotoID() {
        let photoID = UUID(uuidString: "12000000-0000-4000-8000-00000000F001")!
        let elderWithPhoto = ElderTree(
            treeID: Self.elder.treeID,
            activeName: Self.elder.activeName,
            speciesCommonName: Self.elder.speciesCommonName,
            address: Self.elder.address,
            plantedYear: Self.elder.plantedYear,
            heroPhotoID: photoID
        )
        let presentation = Self.present(
            AlmanacNeighborhood(
                area: .named("Sunset/Parkside"),
                firstBloom: Self.bloom(observers: 1),
                elder: elderWithPhoto,
                newestNeighbors: RecentPlanting(treeCount: 4, leadingSpecies: ["Ginkgo"])
            )
        )

        let elderRow = presentation.seasonRows.first { $0.kind == .elder }
        #expect(elderRow?.heroPhotoID == photoID, "the elder's own photo id did not survive the derivation")

        // `bloom(observers:)` above never sets one — this is the "no live photograph" arm.
        let bloomRow = presentation.seasonRows.first { $0.kind == .bloom }
        #expect(bloomRow?.heroPhotoID == nil)

        // A group, not a tree: it must never inherit a photo id from either row beside it.
        let plantedRow = presentation.seasonRows.first { $0.kind == .newestNeighbors }
        #expect(plantedRow?.heroPhotoID == nil, "a row that names a group drew a specific tree's photo")
    }

    @Test("nothing planted this spring means no row, not a row saying none")
    func noRecentPlantingRendersNoRow() {
        for planting in [nil, RecentPlanting(treeCount: 0, leadingSpecies: ["Ginkgo"])] {
            let presentation = Self.present(
                AlmanacNeighborhood(area: .named("Sunset/Parkside"), newestNeighbors: planting)
            )
            #expect(!presentation.seasonRows.contains { $0.kind == .newestNeighbors })
        }
    }

    @Test("`mostly` needs more than one tree to be true of")
    func recentPlantingMostlyClause() {
        let one = AlmanacCopy.newestSubtitle(treeCount: 1, leadingSpecies: ["Ginkgo"], locale: Self.locale)
        #expect(one == "1 tree planted this spring")

        let many = AlmanacCopy.newestSubtitle(
            treeCount: 23, leadingSpecies: ["Ginkgo", "NZ tea tree", "Monterey Pine"], locale: Self.locale
        )
        // The seed's own capitalisation, kept: lower-casing a name to fit the mock's sentence turns
        // `NZ tea tree` into `nz tea tree`.
        #expect(many == "23 trees planted this spring, mostly Ginkgo and NZ tea tree")
    }

    // MARK: - A9 · the species mix

    @Test("the species mix renders from city data, and its remainder is the honest one")
    func compositionRendersAndRemainderIsExact() {
        let presentation = Self.present(
            AlmanacNeighborhood(area: .named("Sunset/Parkside"), composition: Self.composition)
        )
        let composition = presentation.composition
        #expect(composition?.label == "Who lives here · 215 species")
        #expect(composition?.rows.count == 4)
        #expect(composition?.rows.last?.isRemainder == true)
        #expect(composition?.rows.last?.name == "Everyone else")

        // 1,561 + 827 + 816 of 11,026 is 29.05%, so the remainder is 70.95% → 71%, computed from
        // the unrounded shares rather than from `100 - 14 - 8 - 7`.
        #expect(composition?.rows.map(\.value) == ["14%", "8%", "7%", "71%"])

        // Every swatch index addresses a real swatch, so the view never has to clamp.
        for row in composition?.rows ?? [] {
            #expect(CypressColor.compositionSwatches.indices.contains(row.swatchIndex))
        }
    }

    @Test("an empty inventory renders no composition card")
    func emptyCompositionRendersNothing() {
        for composition in [
            nil,
            NeighborhoodComposition(distinctSpeciesCount: 0, treeCount: 0, leading: []),
            NeighborhoodComposition(distinctSpeciesCount: 1, treeCount: 0, leading: [])
        ] {
            let presentation = Self.present(
                AlmanacNeighborhood(area: .named("Sunset/Parkside"), composition: composition)
            )
            #expect(presentation.composition == nil)
        }
    }

    @Test("a neighbourhood with no remainder draws no `Everyone else` at 0%")
    func noRemainderRowWhenNothingRemains() {
        let whole = NeighborhoodComposition(
            distinctSpeciesCount: 2,
            treeCount: 10,
            leading: [
                SpeciesShare(speciesID: Self.id(10), name: "Ginkgo", treeCount: 6),
                SpeciesShare(speciesID: Self.id(11), name: "Monterey Cypress", treeCount: 4)
            ]
        )
        let presentation = Self.present(
            AlmanacNeighborhood(area: .named("Sunset/Parkside"), composition: whole)
        )
        #expect(presentation.composition?.rows.count == 2)
        #expect(presentation.composition?.rows.contains { $0.isRemainder } == false)
        #expect(!Self.containsAZero(Self.renderedStrings(presentation)))
    }

    @Test("a species too rare to round to a point reads `<1%`, never `0%`")
    func vanishinglyRareSpeciesNeverReadsZero() {
        #expect(AlmanacCopy.percent(0.0004, locale: Self.locale) == "<1%")
        #expect(AlmanacCopy.percent(0.14, locale: Self.locale) == "14%")
    }

    // MARK: - §4 · where eyes are needed

    @Test("no young unvisited trees means no card, not a card saying none")
    func emptyCoverageRendersNothing() {
        for gap in [nil, Self.coverage(0, farthestM: 0)] {
            let presentation = Self.present(
                AlmanacNeighborhood(area: .named("Sunset/Parkside"), coverage: gap)
            )
            #expect(presentation.coverage == nil)
            #expect(!Self.containsAZero(Self.renderedStrings(presentation)))
        }
        #expect(AlmanacThresholds.minimumCoverageTrees == 1)
    }

    /// ERRATA E38, on the one card that is nothing but a number.
    @Test("a coverage read that came back a page prints no count")
    func pagedCoverageRendersNothing() {
        let presentation = Self.present(
            AlmanacNeighborhood(
                area: .named("Sunset/Parkside"),
                coverage: Self.coverage(200, farthestM: 500, isComplete: false)
            )
        )
        #expect(presentation.coverage == nil, "a page's size was printed as a total")
    }

    @Test("the walking sentence is written only when it is true")
    func walkClauseIsCheckedNotAsserted() {
        let close = Self.present(
            AlmanacNeighborhood(area: .named("Sunset/Parkside"), coverage: Self.coverage(9, farthestM: 900))
        )
        #expect(close.coverage?.title == "9 young trees with no visits since planting")
        #expect(close.coverage?.body.contains("All nine are within a 15-minute walk.") == true)
        #expect(close.coverage?.ctaTitle == "Walk the nine")

        let spread = Self.present(
            AlmanacNeighborhood(area: .named("Sunset/Parkside"), coverage: Self.coverage(17, farthestM: 4_100))
        )
        #expect(spread.coverage?.body == "The first two summers decide whether a street tree makes it.")
        #expect(spread.coverage?.ctaTitle == "Walk the seventeen")
    }

    @Test("one tree does not read `walk the one`")
    func singleCoverageTreeReadsAsOne() {
        let presentation = Self.present(
            AlmanacNeighborhood(area: .named("Sunset/Parkside"), coverage: Self.coverage(1, farthestM: 100))
        )
        #expect(presentation.coverage?.title == "1 young tree with no visit since planting")
        #expect(presentation.coverage?.ctaTitle == "Walk to it")
        #expect(presentation.coverage?.body.contains("It is within a 15-minute walk.") == true)
    }

    /// **This test used to assert the defect** (ERRATA E129). It read
    /// `#expect(presentation.coverage?.firstTreeID == near.id)` — the CTA opens the nearest of them —
    /// and it passed, on a card whose button says `Walk the nine`. A test can pin the wrong answer
    /// just as precisely as the right one, and this is what that looks like.
    ///
    /// What it checks now is the group, and that the group is still ordered nearest first, because the
    /// destination's own sentence ("The 20 nearest are on this map.") is a claim about that ordering.
    @Test("the CTA hands over every tree it counted, nearest first")
    func coverageCTACarriesTheGroupNearestFirst() {
        let far = CoverageTree(pin: Self.pin(200), distanceM: 900)
        let near = CoverageTree(pin: Self.pin(201), distanceM: 40)
        let presentation = Self.present(
            AlmanacNeighborhood(
                area: .named("Sunset/Parkside"),
                coverage: CoverageGap(trees: Series(complete: [near, far]))
            )
        )
        #expect(presentation.coverage?.group.pins.map(\.id) == [near.id, far.id])
        #expect(presentation.coverage?.group.count == 2)
        #expect(presentation.coverage?.group.isComplete == true)
    }

    // MARK: - Windows

    @Test("there is no `this spring` before spring")
    func springWindowIsAbsentBeforeMarch() {
        // 2026-01-21: the row cannot draw, because the drawn copy has a word for one season only.
        #expect(AlmanacWindow.currentSpring(now: Self.january, calendar: Self.calendar) == nil)

        let spring = AlmanacWindow.currentSpring(now: Self.now, calendar: Self.calendar)
        #expect(spring?.from == "2026-03-01")
        #expect(spring?.to == "2026-05-31")
    }

    @Test("young is two years, measured from the reader's clock")
    func youngWindow() {
        #expect(AlmanacWindow.youngSince(now: Self.now, calendar: Self.calendar) == "2024-07-20")
        #expect(AlmanacWindow.youngTreeYears == 2)
    }

    @Test("the year the first bloom is measured against starts on 1 January")
    func bloomYearWindow() {
        let start = AlmanacWindow.yearStart(now: Self.now, calendar: Self.calendar)
        let parts = Self.calendar.dateComponents([.year, .month, .day], from: start)
        #expect(parts.year == 2026 && parts.month == 1 && parts.day == 1)
    }

    // MARK: - Addresses

    @Test("a house number is dropped and a street number is not")
    func streetStripping() {
        #expect(AlmanacCopy.street(from: "1240 44th Ave") == "44th Ave")
        #expect(AlmanacCopy.street(from: "1783 41st Ave") == "41st Ave")
        #expect(AlmanacCopy.street(from: "Noriega St") == "Noriega St")
        #expect(AlmanacCopy.street(from: nil) == nil)
        #expect(AlmanacCopy.street(from: "   ") == nil)
    }

    // MARK: - D1

    /// The footnote is the specification of this screen, so it is pinned verbatim: if the almanac
    /// ever acquires a rank or a counter, this sentence becomes a lie before any test fails.
    @Test("the footnote says what the screen is, verbatim")
    func footnoteIsVerbatim() {
        #expect(AlmanacCopy.footnote == "No ranks, no counters. The almanac notices trees, not scores.")
    }

    /// No surface on this screen counts what anybody did. The bloom row's headcount counts *people*,
    /// which A8 permits; nothing counts occasions.
    @Test("no rendered string counts a contribution")
    func nothingCountsContributions() {
        let presentation = Self.present(
            AlmanacNeighborhood(
                area: .named("Sunset/Parkside"),
                firstBloom: Self.bloom(observers: 6),
                elder: Self.elder,
                newestNeighbors: RecentPlanting(treeCount: 23, leadingSpecies: ["Ginkgo"]),
                composition: Self.composition,
                coverage: Self.coverage(9, farthestM: 900)
            )
        )
        let forbidden = ["visits by", "photos", "check-ins", "contributions", "streak", "rank", "leaderboard"]
        // The footnote is exempt because it is the promise rather than a breach of it: "No ranks,
        // no counters" is the only place on this screen those words are allowed to appear.
        for string in Self.renderedStrings(presentation) where string != AlmanacCopy.footnote {
            for word in forbidden {
                #expect(
                    !string.lowercased().contains(word),
                    "screen 12 printed '\(word)' in: \(string)"
                )
            }
        }
        // The one permitted headcount, and it is of people rather than of what they did.
        #expect(presentation.seasonRows.first { $0.kind == .bloom }?.subtitle.contains("six neighbors saw it") == true)
    }

    // MARK: - §2's note · what the heading is actually over (task #177)

    /// The note is `areaNote`'s job on the same screen — saying which promise a heading is making —
    /// so it obeys the same rule the whole file is about: it draws with the rows it describes and
    /// is absent when they are. A note under a heading that drew nothing would be the
    /// heading-over-nothing defect with an extra sentence attached.
    @Test("the season note draws exactly when the rows it describes do")
    func theSeasonNoteDrawsOnlyWithItsRows() {
        #expect(Self.present(nil).seasonNote == nil)
        #expect(Self.present(AlmanacNeighborhood(area: .named("Sunset/Parkside"))).seasonNote == nil)

        let drawn = Self.present(AlmanacNeighborhood(area: .named("Sunset/Parkside"), elder: Self.elder))
        #expect(!drawn.seasonRows.isEmpty)
        #expect(drawn.seasonNote != nil, "§2 drew a heading and rows with no account of what selects them")
    }

    /// **The defect #177 is about.** `This season` is over three rows on three different clocks, and
    /// the elder's clock is no clock at all — `ORDER BY planted_on LIMIT 1`, no window, the same
    /// tree in January as in July. So a note that appears beside the elder alone must not borrow a
    /// seasonal window from the rows that did not draw.
    ///
    /// Asserted as *absence of the other rows' windows* rather than against a fixed sentence, so
    /// rewording the clause cannot break it and quietly restoring a blanket "this season" claim
    /// cannot satisfy it.
    @Test("with only the elder, the note claims no seasonal window")
    func theElderAloneIsNotDescribedAsSeasonal() throws {
        let presentation = Self.present(
            AlmanacNeighborhood(area: .named("Sunset/Parkside"), elder: Self.elder)
        )
        #expect(presentation.seasonRows.map(\.kind) == [.elder])
        let note = try #require(presentation.seasonNote)

        for month in Self.springMonthNames() {
            #expect(!note.contains(month), "the elder's note borrowed the planting window: \(note)")
        }
        #expect(!note.lowercased().contains("bloom"), "the note describes a row that did not draw: \(note)")
        #expect(
            note.lowercased().contains("any season"),
            "the note does not say the elder is unaffected by the season: \(note)"
        )
    }

    /// Each drawn row gets its own account, and the note says the windows differ rather than
    /// implying one. The three subjects are asserted present; nothing here pins a sentence.
    @Test("with all three rows, the note accounts for each and states that they differ")
    func theNoteAccountsForEveryDrawnRow() throws {
        let presentation = Self.present(
            AlmanacNeighborhood(
                area: .named("Sunset/Parkside"),
                firstBloom: Self.bloom(observers: 6),
                elder: Self.elder,
                newestNeighbors: RecentPlanting(treeCount: 23, leadingSpecies: ["Ginkgo"])
            )
        )
        #expect(presentation.seasonRows.count == 3)
        let note = try #require(presentation.seasonNote)

        #expect(note.lowercased().contains("bloom"), "the bloom row is undescribed: \(note)")
        #expect(note.lowercased().contains("elder"), "the elder row is undescribed: \(note)")
        #expect(note.lowercased().contains("newest neighbors"), "the planting row is undescribed: \(note)")
        #expect(
            note.lowercased().contains("own window"),
            "the note reads as one window over three clocks: \(note)"
        )
    }

    /// The planting clause names the months the read is actually scoped to, taken from
    /// `AlmanacWindow.springMonths` rather than written out — so moving the window moves the
    /// sentence and the two cannot drift apart.
    @Test("the planting clause names the window the read uses")
    func thePlantingClauseTracksTheWindowConstant() throws {
        let presentation = Self.present(
            AlmanacNeighborhood(
                area: .named("Sunset/Parkside"),
                newestNeighbors: RecentPlanting(treeCount: 23, leadingSpecies: ["Ginkgo"])
            )
        )
        let note = try #require(presentation.seasonNote)
        let months = Self.springMonthNames()
        #expect(months.count == 2)
        for month in months {
            #expect(note.contains(month), "the note does not name \(month), which the read bounds on: \(note)")
        }
    }

    /// The first and last month of the window the planting read is bounded by, in the suite's
    /// pinned calendar **and its pinned locale**.
    ///
    /// The locale is applied here for the reason the note applies it: month symbols come from the
    /// calendar's locale, and this suite's calendar is built by identifier and carries none. Read
    /// off the bare calendar these were `M03` and `M05`, and the assertions below would have been
    /// pinning the fallback rather than the month names a reader sees.
    private static func springMonthNames() -> [String] {
        var calendar = calendar
        calendar.locale = locale
        let names = calendar.standaloneMonthSymbols
        return [names[AlmanacWindow.springMonths.lowerBound - 1], names[AlmanacWindow.springMonths.upperBound - 1]]
    }
}
