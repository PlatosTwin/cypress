//
//  AlmanacGeographyTests.swift
//  CypressTests
//
//  **What the almanac is about, once the record holds more than one city** — RULINGS R29,
//  ERRATA E182.
//
//  ── Three claims, and the third is the one that could not be tested any other way ──────────
//
//  1. **San Francisco did not move.** The whole safety argument for R29's hybrid is that a polygon
//     is still preferred wherever the record holds one, so every threshold, every count and every
//     denominator on screen 12 is unchanged for the city the numbers were measured in. Asserted by
//     reading Sunset/Parkside through the new scope and comparing against `SeedCorpus`' pinned
//     figures — the same numbers `AlmanacVacantSiteTests` and RULINGS R5 stand on.
//  2. **San Jose has an almanac.** Downtown resolves no polygon (there is no San Jose layer in the
//     seed and R29 declines to add one) and now resolves a radius instead, with a species mix, a
//     coverage ask and a vacant-site count behind it. Before this pass `LocalAPI.almanac` returned
//     `.empty` for every coordinate in the city.
//  3. **A finished read that resolved nothing no longer looks like a read still in flight.** This is
//     E182 and it is a *picture* claim, for E126's reason: every value-level assertion about it
//     passes on the broken app. `AlmanacPresentation(almanac: .empty)` was always correct; what was
//     wrong is that the view had no arm for it, so the screen it drew was byte-identical to the
//     loading one. The render half below is the only half that fails on the old code.
//
//  The render harness is `FailedReadTests`', which is `ScreenSweepShots.capture`'s, for the reasons
//  given there: a `.task` suspended on the cooperative executor is waited for rather than spun.
//

import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Cypress

@Suite("Almanac · geography")
struct AlmanacGeographyTests {

    // MARK: - Harness

    static var seedURL: URL? {
        if let path = ProcessInfo.processInfo.environment["CYPRESS_SEED_PATH"] {
            return URL(fileURLWithPath: path)
        }
        return SeedDatabase.urlInBundle(Bundle(for: BundleToken.self)) ?? SeedDatabase.urlInBundle()
    }

    private final class BundleToken {}

    private static let seed = SeedDatabase.schemaName

    private static func store() async throws -> CypressStore {
        let url = try #require(seedURL, "no seed database; set CYPRESS_SEED_PATH")
        return try await CypressStore.inMemory(seedURL: url)
    }

    private static func scalar(_ sql: String, on store: CypressStore) async throws -> Int {
        try await store.queue.read { connection in
            let statement = try connection.prepare(sql)
            defer { statement.finalize() }
            return try statement.fetchOne { try $0.int("n") } ?? -1
        }
    }

    /// Downtown San Jose — South First Street, the block E176 photographed the map at.
    static let downtownSanJose = Coordinate(latitude: 37.3352, longitude: -121.8895)

    /// Sunset/Parkside, the fix every other almanac suite uses.
    static let outerSunset = Coordinate(latitude: 37.7533, longitude: -122.4934)

    /// Nowhere the record reaches: downtown Sacramento, 120 km from the nearest seeded tree.
    static let sacramento = Coordinate(latitude: 38.5816, longitude: -121.4944)

    static let now = Date(timeIntervalSince1970: 1_784_505_600) // 2026-07-20

    /// Fixed, so the almanac's own date windows — "this spring", "young" — do not move under the
    /// suite. `deviceID` is required and unused: nothing on screen 12 is scoped to a contributor.
    private static let deviceID = UUID(uuidString: "E1820000-0000-4000-8000-000000000029")!

    private static func api(_ store: CypressStore) -> LocalAPI {
        LocalAPI(store: store, deviceID: deviceID, now: { now })
    }

    // MARK: - 1 · San Francisco did not move

    /// The scope change is a change of *how the area is named*, not of what is in it.
    ///
    /// Every read in `AlmanacQueries` had its `WHERE t.neighborhood_id = :neighborhood` replaced by
    /// `\(scope.predicate("t"))`, and for a `.neighborhood` scope that renders the identical string.
    /// This asserts the identity in the numbers rather than in the SQL text, against the corpus
    /// figures R5 fixed and E115 measured — because a denominator that quietly moves is exactly the
    /// failure R5 exists to prevent, and it would move silently.
    @Test("a named neighborhood reads exactly what it read before the scope existed")
    func namedAreaIsUnchanged() async throws {
        let store = try await Self.store()
        let corpus = try await SeedCorpus.current(store)
        let schema = try #require(store.seed)
        let queries = AlmanacQueries(schema: schema)
        let id = try await Self.scalar(
            "SELECT id AS n FROM \(Self.seed).neighborhoods WHERE name = 'Sunset/Parkside'",
            on: store
        )
        let scope = AlmanacScope.neighborhood(id: id, name: "Sunset/Parkside")

        let mix = try await store.queue.read { try queries.speciesMix(scope: scope, connection: $0) }
        #expect(mix.count == corpus.sunsetSpeciesInMix, "R5's species count moved")
        #expect(
            mix.reduce(0) { $0 + $1.treeCount } == corpus.sunsetTreesWithSpecies,
            "R5's denominator moved"
        )

        let sites = try await store.queue.read {
            try queries.vacantSites(
                scope: scope,
                near: Self.outerSunset,
                limit: AlmanacLimits.vacantSiteRowLimit,
                connection: $0
            )
        }
        #expect(sites.count == corpus.sunsetVacantSites, "E115's site count moved")

        // And the area names itself the way it always did: the seed's own string, verbatim.
        #expect(scope.area == .named("Sunset/Parkside"))
        #expect(AlmanacCopy.areaPill(scope.area, locale: Self.locale) == "Sunset/Parkside")
    }

    static let locale = Locale(identifier: "en_US")

    /// Screen 12, end to end, in the city it was designed for.
    @Test("an almanac read in San Francisco still resolves a named neighborhood")
    func sanFranciscoResolvesAPolygon() async throws {
        let store = try await Self.store()
        let almanac = try await Self.api(store).almanac(near: Self.outerSunset)
        let area = try #require(almanac.neighborhood, "San Francisco resolved no area")

        #expect(area.name != nil, "a San Francisco fix must resolve a named polygon, not the fallback")
        if case .radius = area.area {
            Issue.record("San Francisco fell back to a radius, which R29 reserves for cities with no boundaries on file")
        }
    }

    // MARK: - 2 · San Jose has an almanac

    /// The hole E176 recorded and declined to fix, asserted from the other side.
    ///
    /// The precondition is checked first and it is not decoration: if a San Jose neighborhood layer
    /// ever does land in the seed, this test would otherwise go on passing while measuring the
    /// polygon path, and the fallback would be untested by a suite that claims to test it.
    @Test("downtown San Jose has no polygon, and gets a radius almanac instead")
    func sanJoseResolvesTheFallback() async throws {
        let store = try await Self.store()
        let schema = try #require(store.seed)

        // The precondition: San Jose rows carry no neighborhood, so no polygon can resolve here.
        let assigned = try await Self.scalar(
            """
            SELECT COUNT(*) AS n FROM \(Self.seed).trees
             WHERE id_space = 'us-ca-sj' AND neighborhood_id IS NOT NULL
            """,
            on: store
        )
        #expect(assigned == 0, "San Jose now carries polygons; this suite is measuring the wrong path")

        let polygon = try await store.queue.read { connection in
            try SpeciesQueries(schema: schema).resolveNeighborhood(
                near: Self.downtownSanJose,
                connection: connection
            )
        }
        #expect(polygon == nil, "a polygon resolved in San Jose")

        // And the almanac a reader standing there actually gets.
        let almanac = try await Self.api(store).almanac(near: Self.downtownSanJose)
        let area = try #require(almanac.neighborhood, "San Jose still has no almanac at all")
        #expect(area.area == .radius(meters: AlmanacLimits.fallbackRadiusM))
        #expect(area.name == nil, "a distance is not a name")

        // Four of the five blocks have something behind them. The bloom row does not, and cannot on
        // a fresh install: it needs a contribution and no seeded tree carries one (A9).
        let composition = try #require(area.composition, "San Jose has no species mix")
        #expect(composition.distinctSpeciesCount > 1)
        #expect(composition.treeCount > 1_000, "the fallback area is implausibly small")
        #expect(area.vacantSites != nil, "San Jose has no vacant-site block")
        #expect(area.elder != nil, "San Jose has no elder")
        #expect(area.firstBloom == nil, "nothing in the seed can produce a bloom sighting")
    }

    /// D1's one directed ask, working in the second city.
    ///
    /// This is the sentence in the ticket that makes the geography question worth answering at all:
    /// the coverage panel is "the surface D1 makes the app's only directed ask", and in San Jose it
    /// was empty because the area behind it did not exist.
    @Test("the coverage ask reaches San Jose, and its walking claim is true by construction")
    func sanJoseHasACoverageAsk() async throws {
        let store = try await Self.store()
        let almanac = try await Self.api(store).almanac(near: Self.downtownSanJose)
        let area = try #require(almanac.neighborhood)
        let coverage = try #require(area.coverage, "no coverage gap in San Jose")

        #expect(coverage.trees.items.isEmpty == false)
        #expect(coverage.trees.totalCount != nil, "an incomplete read prints no number (E38)")

        // R29 set the fallback radius to `AlmanacMetrics.walkRadiusM` precisely so this holds. It is
        // asserted rather than assumed, because the two constants are deliberately separate and a
        // future divergence should show up here rather than as a withheld sentence nobody notices.
        let farthest = coverage.trees.items.map(\.distanceM).max() ?? 0
        #expect(
            farthest <= AlmanacMetrics.walkRadiusM,
            "a tree in the fallback area is outside §4's walking claim; the two radii have diverged"
        )

        let presentation = AlmanacPresentation(almanac: almanac, now: Self.now, locale: Self.locale)
        let card = try #require(presentation.coverage)
        #expect(card.body.contains("15-minute walk"), "the walking sentence was withheld")
    }

    /// The fallback names itself as a distance and says so in a sentence, not only in a pill.
    @Test("the fallback area is presented as a distance and explained")
    func fallbackSaysWhatItIs() async throws {
        let store = try await Self.store()
        let almanac = try await Self.api(store).almanac(near: Self.downtownSanJose)
        let presentation = AlmanacPresentation(almanac: almanac, now: Self.now, locale: Self.locale)

        #expect(presentation.hasArea)
        #expect(presentation.neighborhoodName == "Within a 15-minute walk")
        let note = try #require(presentation.areaNote, "the fallback drew no explanation")
        #expect(note.contains("boundaries"))
        // D16(b): an honest empty-ish state says what *would* change it, or it reads as a dead end.
        #expect(note.contains("join the record"))

        // American spellings, at the owner's instruction. Checked over every string this screen can
        // put in front of a reader in this state, not only the ones written today.
        for string in [presentation.neighborhoodName, note, AlmanacCopy.locationPromptTitle].compactMap({ $0 }) {
            for british in ["neighbourhood", "colour", "centre", "metres"] {
                #expect(
                    string.lowercased().contains(british) == false,
                    "\(string) carries the British spelling '\(british)'"
                )
            }
        }
    }

    // MARK: - 3 · Nowhere the record reaches (ERRATA E182)

    @Test("a fix outside every inventory resolves no area at all")
    func outsideTheRecordResolvesNothing() async throws {
        let store = try await Self.store()
        let almanac = try await Self.api(store).almanac(near: Self.sacramento)

        // Not a radius over an empty circle: an area with no record in it is not an area. The
        // fallback is only taken where `holdsAnyRecord` says the inventory covers the ground.
        #expect(almanac.neighborhood == nil)

        let presentation = AlmanacPresentation(almanac: almanac, now: Self.now, locale: Self.locale)
        #expect(presentation.hasArea == false)
        #expect(presentation.neighborhoodName == nil, "a header pill would name an area we do not have")
    }

    /// The copy says what the almanac is made of and what would fill it, and claims nothing about a
    /// read that did not fail.
    @Test("the out-of-range sentence borrows no word from the failed read")
    func outOfRangeCopyIsItsOwnStatement() {
        #expect(AlmanacCopy.outOfRangeTitle.hasSuffix("."))
        #expect(AlmanacCopy.outOfRangeBody.hasSuffix("."))
        #expect(AlmanacCopy.outOfRangeTitle != AlmanacCopy.loadFailed)
        // It must not read as a failure: nothing went wrong, the record simply stops here.
        for forbidden in ["could not", "failed", "error", "try again"] {
            let sentence = (AlmanacCopy.outOfRangeTitle + " " + AlmanacCopy.outOfRangeBody).lowercased()
            #expect(sentence.contains(forbidden) == false, "the out-of-range copy reads as a failure")
        }
        // D16(b) again: it says what would change the answer.
        #expect(AlmanacCopy.outOfRangeBody.contains("as more cities join the record"))
    }

    /// **The half that can only pass on the fixed app.**
    ///
    /// Screen 12 after a read that finished and resolved no area, against screen 12 while the read is
    /// still in flight. These were byte-identical — header, footnote, an empty column between them,
    /// in both — which is E182's defect stated as an assertion, and is E126's defect surviving on a
    /// state E126 did not have a cause for. Deleting the `outOfRange` arm from `AlmanacScreen` makes
    /// this go red and leaves every value assertion above it green.
    ///
    /// The control render proves the harness is byte-stable first: an inequality assertion measures
    /// nothing unless the same screen rendered twice is equal (ARCHITECTURE §7).
    ///
    /// Both sides are compared as a `Bool` before `#expect` sees them. `#expect(a != b)` on two
    /// large `Data` values hangs while it tries to describe the difference rather than reporting it.
    @MainActor
    @Test("an almanac that resolved no area does not look like one that is still loading")
    func outOfRangeDrawsSomethingLoadingDoesNot() async throws {
        let loading = try #require(await Self.render { Self.almanac(payload: nil) })
        let loadingAgain = try #require(await Self.render { Self.almanac(payload: nil) })
        let outOfRange = try #require(await Self.render { Self.almanac(payload: .empty) })

        let stable = loading == loadingAgain
        #expect(stable, "the renderer is not stable, so the comparison below is void")

        let differs = outOfRange != loading
        let message: Comment = "an almanac that finished and found no inventory draws the loading screen (E182): \(outOfRange.count) bytes against \(loading.count)"
        #expect(differs, message)
    }

    // MARK: - Render harness

    /// Screen 12 with a payload, or — for `nil` — with a read that never returns, which is the
    /// loading state without a `Task.sleep` racing the capture.
    @MainActor
    private static func almanac(payload: Almanac?) -> some View {
        NavigationStack {
            AlmanacView(
                api: NeverAnswers(payload: payload),
                coordinate: outerSunset,
                now: { now },
                onBack: {}
            )
        }
        .environment(AppRouter())
    }

    /// A read that answers with `payload`, or never answers at all.
    ///
    /// `nil` suspends forever rather than sleeping: the eight 120 ms passes the harness makes would
    /// otherwise be racing a timer, and a loading screen that had quietly finished loading is the
    /// one thing this comparison must not accidentally capture.
    private struct NeverAnswers: CypressAPI {
        let payload: Almanac?

        func almanac(near coordinate: Coordinate?) async throws -> Almanac {
            guard let payload else {
                await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in }
                return .empty
            }
            return payload
        }

        func mapContent(in viewport: MapViewport) async throws -> MapContent { .pins([]) }
        func treesNear(_ c: Coordinate, radiusM: Double, limit: Int) async throws -> [NearbyTree] { [] }
        func treeProfile(id: UUID) async throws -> TreeProfile { throw APIError.notFound }
        func addTree(_ draft: TreeDraft) async throws -> Tree { throw APIError.forbidden }
        func species(id: UUID) async throws -> Species { throw APIError.notFound }
        func searchSpecies(query: String, limit: Int) async throws -> [Species] { [] }
        func sync(_ items: [OutboxItem]) async throws -> [SyncResult] { [] }
        func beginPhotoUpload(_ r: PhotoUploadRequest) async throws -> PhotoUploadTicket {
            throw APIError.forbidden
        }
        func uploadPhoto(at localPath: String, ticket: PhotoUploadTicket) async throws {}
        func grove() async throws -> [GroveEntry] { [] }
        func journal(cursor: String?, limit: Int) async throws -> Page<JournalEntry> { Page(items: []) }
        func claimDevice(deviceUUID: UUID, userID: UUID) async throws {}
        func logHazardRedirect(_ event: HazardRedirectEvent) async throws {}
        func exportLatest(_ format: ExportFormat) async throws -> Data { Data() }
    }

    private static let width: CGFloat = 393
    private static let height: CGFloat = 852

    @MainActor
    private static func render(@ViewBuilder _ content: () -> some View) async -> Data? {
        let host = UIHostingController(
            rootView: AnyView(
                content()
                    .frame(width: width, height: height)
                    .background(CypressColor.surfaceScreen)
            )
        )
        host.overrideUserInterfaceStyle = .light
        let frame = CGRect(x: 0, y: 0, width: width, height: height)
        host.view.frame = frame

        let window = UIWindow(frame: CGRect(x: -2_000, y: 0, width: width, height: height))
        window.overrideUserInterfaceStyle = .light
        window.rootViewController = host
        window.isHidden = false
        window.layoutIfNeeded()

        for _ in 0..<8 {
            try? await Task.sleep(for: .milliseconds(120))
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
        }

        let image = UIGraphicsImageRenderer(bounds: frame).image { _ in
            host.view.drawHierarchy(in: frame, afterScreenUpdates: true)
        }
        window.isHidden = true
        window.rootViewController = nil
        return image.pngData()
    }
}
