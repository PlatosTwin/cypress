//
//  PhenologyObservedStatesTests.swift
//  Cypress — CypressTests
//
//  Field report #151, 2026-07-31: SF tree 222615 — Cassia leptophylla, in full flower — offered no
//  phenology option at all during a visit. The owner was looking at a flowering tree and the app
//  refused the word "flowering".
//
//  The gate was `VisitPhenologyVocabulary.tags(for:)`'s curated check: the seed row is mapped
//  (is_stub = 0), carries a sourced habit (semi_deciduous), and is `curated = 0` like 529 of the
//  seed's 569 species — so the chip row was offered "for the curated 40 and nobody else".
//
//  The ruling this file pins (docs/rulings-pending/observed-states-not-gated.md): a phenology tag
//  is the OBSERVER's report of what is in front of them, not the app's claim about the species.
//  DECISIONS constraint 15 forbids the app asserting botany it does not have; a contributor's own
//  observation is the opposite of that — it is the community data D16 says the product exists to
//  collect. So the observed-state options are always available at check-in; species data may order
//  or hint, but never gates availability. The one exclusion that stands is D5's: a species KNOWN
//  to be evergreen is never asked about fall color or bare, because that is a sourced fact making
//  the tag a contradiction rather than an observation.
//

import Foundation
import SwiftUI
import Testing
@testable import Cypress

@Suite("Observed states are not gated by what the app knows (#151)")
struct PhenologyObservedStatesTests {

    /// Seed row 209, mirrored exactly: `sf/222615`'s species as `SpeciesQueries` decodes it —
    /// mapped, uncurated, `semi_deciduous`, and a seasonal calendar of four empty arrays, which is
    /// `SeasonalCalendar.empty` by value.
    static func goldMedallion() throws -> Species {
        try Species(
            scientificName: "Cassia leptophylla",
            commonName: "Gold Medallion Tree",
            family: "Fabaceae",
            leafRetention: .semiDeciduous,
            seasonal: .empty,
            curated: false
        )
    }

    // MARK: - The report, as the property that was violated

    @Test("an uncurated species with an empty calendar offers the full observed-state list")
    func emptyCalendarOffersTheWholeList() throws {
        let tags = VisitPhenologyVocabulary.tags(for: try Self.goldMedallion())
        #expect(
            tags == VisitPhenologyVocabulary.order,
            "a flowering gold medallion tree was offered \(tags) — the observer must be able to say what they see"
        )
    }

    @Test("the write path keeps every tag the observer of an uncurated species picked")
    func writePathKeepsUncuratedTags() throws {
        let species = try Self.goldMedallion()
        #expect(PhenologyTag.validated([.flowering], for: species) == [.flowering])
        #expect(
            PhenologyTag.validated(PhenologyTag.allCases, for: species) == PhenologyTag.allCases,
            "no tag an observer can pick for this species may be silently dropped at save"
        )
    }

    /// The exact record behind the report, through the real read path: the seed's `sf/222615`
    /// resolves to a species, and that species offers the full vocabulary. This is the test that
    /// re-fails if the seed's mapping for this row ever degrades to a stub or the gate returns.
    @Test("seed tree sf/222615 — the reported record — offers the full list through the real read")
    func tree222615OffersTheList() async throws {
        let seedURL = try #require(SeedContractTests.seedURL, "no seed database; set CYPRESS_SEED_PATH")
        let store = try await CypressStore.inMemory(seedURL: seedURL)
        let api = LocalAPI(store: store, deviceID: UUID())

        // The row's stable uuid, verified against the seed on 2026-07-31:
        // id 100569 · sf/222615 · 34 Carl St · species_current 209 (Cassia leptophylla, curated 0).
        let treeID = try #require(UUID(uuidString: "f9312e71-d5c2-5f42-9dc6-9c7bdcd838cb"))
        let profile = try await api.treeProfile(id: treeID)

        let species = try #require(profile.species, "sf/222615 lost its species mapping")
        #expect(species.scientificName == "Cassia leptophylla")
        #expect(species.curated == false, "if this row is curated now, this test guards nothing — move it")
        #expect(species.leafRetention == .semiDeciduous)
        #expect(species.seasonal == .empty)

        let tags = VisitPhenologyVocabulary.tags(for: species)
        #expect(
            tags == VisitPhenologyVocabulary.order,
            "the owner of #151 would still meet an empty option list: \(tags)"
        )
    }

    // MARK: - The ruling's edges

    @Test("a species with no sourced habit still lets the observer report what they see")
    func unknownHabitOffersTheWholeList() throws {
        let species = try Species(
            scientificName: "Ficus laurel",
            commonName: "Laurel Fig",
            leafRetention: nil,
            curated: true
        )
        // The chip row: everything. Excluding fall color would assert "this is an evergreen",
        // which is exactly the unsourced claim E9 forbids the app to make.
        #expect(VisitPhenologyVocabulary.tags(for: species) == VisitPhenologyVocabulary.order)
        // And the write path agrees with the row it drew.
        #expect(PhenologyTag.validated(PhenologyTag.allCases, for: species) == PhenologyTag.allCases)
    }

    // MARK: - What must not regress

    /// D5 survives the ruling: it is a sourced fact, not a guess, and it is the only gate left.
    @Test("a known evergreen is still never asked about fall color or bare")
    func evergreenExclusionStands() throws {
        let species = try Species(
            scientificName: "Hesperocyparis macrocarpa",
            commonName: "Monterey Cypress",
            leafRetention: .evergreen,
            curated: true
        )
        let tags = VisitPhenologyVocabulary.tags(for: species)
        #expect(!tags.contains(.fallColor))
        #expect(!tags.contains(.bare))
        #expect(tags == VisitPhenologyVocabulary.order.filter { $0 != .fallColor && $0 != .bare })
        #expect(PhenologyTag.validated([.fallColor, .fullLeaf], for: species) == [.fullLeaf])
    }

    /// A curated species with a full authored calendar — the known-calendar ordering the fix must
    /// not disturb: the row still reads in `VisitPhenologyVocabulary.order`'s seasonal order.
    @Test("a curated species with a known calendar keeps its seasonal order")
    func knownCalendarKeepsItsOrder() throws {
        let londonPlane = try Species(
            scientificName: "Platanus × acerifolia",
            commonName: "London Plane",
            leafRetention: .deciduous,
            seasonal: SeasonalCalendar(
                bloomMonths: [4, 5],
                fallColorMonths: [10, 11],
                fruitMonths: [9, 10],
                newGrowthMonths: [3, 4]
            ),
            curated: true
        )
        let tags = VisitPhenologyVocabulary.tags(for: londonPlane)
        #expect(tags == [.leafOut, .fullLeaf, .flowering, .fruiting, .fallColor, .bare])
        #expect(tags == VisitPhenologyVocabulary.order)
    }

    /// The gate the ruling leaves standing, deliberately: a tree with no species record at all
    /// still draws no chip row. Whether that gate should also fall is proposed, not done, in
    /// docs/rulings-pending/observed-states-not-gated.md.
    @Test("no species record still means no chip row — the one gate left untouched")
    func nilSpeciesStillOffersNothing() {
        #expect(VisitPhenologyVocabulary.tags(for: nil).isEmpty)
    }

    /// `VisitGates.phenologyVocabulary()` had no caller anywhere in the repository — a gate that
    /// has never run is not a gate, by this project's own line. Wired in here, where its subject
    /// now lives.
    @Test("the framework-free phenology gate runs, and agrees")
    func visitGateRunsAndPasses() async throws {
        let failures = try await VisitGates.phenologyVocabulary()
        #expect(failures.isEmpty, "\(failures.count) gate failures:\n\(failures.joined(separator: "\n"))")
    }
}

// MARK: - Photographed

/// Screen 04's tray, photographed in the states #151 changed — the uncurated Cassia that had no
/// row at all — and the states that must not have moved: the curated London Plane's full row and
/// the no-species tray, which still draws none.
@MainActor
@Suite("Observed-state chips · photographed (#151)")
struct PhenologyObservedStatesShots {

    /// The tray over a given species record, through the same preview double the camera's own
    /// fixtures use. The simulator has no camera, so the viewfinder is the designed placeholder;
    /// the subject here is the tray below it.
    private static func camera(species: Species?, displayName: String) -> VisitCameraView {
        VisitCameraView(
            treeID: VisitPreviewFixtures.cypress.id,
            treeDisplayName: displayName,
            gpsAccuracyM: { 9 },
            api: VisitPreviewAPI(
                profile: TreeProfile(tree: VisitPreviewFixtures.cypress, species: species)
            ),
            outbox: VisitPreviewFixtures.outbox(),
            attribution: VisitPreviewFixtures.attribution,
            onSaved: { _ in },
            onClose: {}
        )
    }

    @Test("the tray for sf/222615's species, a curated control, and the no-species state")
    func photograph() async throws {
        print("SHOT DIR \(ScreenSweepShots.outputDirectory.path)")

        // The report: an uncurated species, empty calendar. Before #151 this tray had no chip row.
        let cassia = try PhenologyObservedStatesTests.goldMedallion()
        #expect(await ScreenSweepShots.pair("n151-1-camera-cassia-222615") {
            Self.camera(species: cassia, displayName: "Gold Medallion Tree")
        })

        // The control: a curated deciduous species with a full calendar — the row it always had,
        // in the order it always had it.
        let plane = try Species(
            scientificName: "Platanus × acerifolia",
            commonName: "London Plane",
            leafRetention: .deciduous,
            seasonal: SeasonalCalendar(
                bloomMonths: [4, 5], fallColorMonths: [10, 11],
                fruitMonths: [9, 10], newGrowthMonths: [3, 4]
            ),
            curated: true
        )
        #expect(await ScreenSweepShots.pair("n151-2-camera-london-plane") {
            Self.camera(species: plane, displayName: "London Plane")
        })

        // The gate left standing: no species record, no row.
        #expect(await ScreenSweepShots.pair("n151-3-camera-no-species") {
            Self.camera(species: nil, displayName: "Tree")
        })
    }
}
