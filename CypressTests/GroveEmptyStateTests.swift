//
//  GroveEmptyStateTests.swift
//  CypressTests
//
//  ERRATA E48, closed — the owner approved copy for screen 08's empty grove on 2026-08-05, and
//  `GroveView.speciesTab` now draws it. `GrovePresentationTests` pins
//  the two halves a renderer cannot see: the gate (`GrovePresentation.isEmpty`) and the string
//  (`GroveCopy.emptyGrove`, verbatim). What is left is the one fact only a renderer can decide — that
//  the sentence actually reaches the screen, in the slot E48 describes, above §6's footnote — and
//  that is what this file is for.
//
//  ── Why a pixel comparison, and against what ──────────────────────────────────────────────
//  SwiftUI builds no in-process accessibility tree (`AccessibilityTests.swift`'s own header), so
//  "does this string appear on screen" cannot be answered by walking a tree. `FailedReadTests`
//  answers the adjacent question ("does this screen draw something a sibling state does not") by
//  rendering through a real `UIHostingController` and comparing PNG bytes; this file uses the same
//  harness for a narrower claim.
//
//  **Comparing the empty grove against a populated one is not narrow enough**, and a hand-rebuilt
//  "what the chrome looked like before" is not safe enough — both were tried first. A populated
//  grove already drew a ring and a grid before E48's copy existed and an empty one drew nothing, so
//  that comparison passes whether or not this ticket's sentence is on screen. A second view
//  reconstructing `GroveView.body`'s chrome by hand (title, tab row, footnote, nothing between) came
//  out a measurably different picture from the real screen's own empty rendering *even with the
//  sentence removed* — some structural detail of the real screen's composition was not reproduced —
//  so that comparison was void for the opposite reason: it never agrees with the real screen, so a
//  disagreement proves nothing either.
//
//  **What is used instead is a real `GroveView` that never finishes loading.** `NeverRespondingAPI`
//  suspends `groveSpecies()` forever, so `GroveModel.presentation` stays `nil` and `hasFailed` stays
//  `false` for the whole capture — exactly the state `speciesTab`'s `if let presentation = …` has no
//  branch for, drawn by the same production code the fixed screen runs, with nothing hand-copied.
//  That is the actual picture the empty grove degenerates to if the `isEmpty` branch is ever removed
//  (`if let presentation` becomes reachable and immediately finds nothing to draw, same as if the
//  read had simply not returned yet).
//
//  Watched failing with the `GroveNote(GroveCopy.emptyGrove)` branch deleted from `speciesTab`, then
//  restored — the sentence is E48's whole change, and `theSentenceIsOnScreen` is the test that would
//  have caught it going missing.
//

#if DEBUG
import SwiftUI
import Testing
import UIKit
@testable import Cypress

@MainActor
@Suite("Screen 08's empty-grove sentence, on screen (ERRATA E48)")
struct GroveEmptyStateTests {

    /// `nonisolated` so the `@Sendable () -> Date` `GroveView.init` takes can read it — an
    /// immutable `Date` carries no isolation of its own, and the suite's `@MainActor` is about the
    /// hosting controller in `render(_:)`, not about this constant (`FailedReadTests.now`'s own
    /// reasoning).
    private nonisolated static let now = Date(timeIntervalSince1970: 1_753_142_400) // 2025-07-22, matching GrovePreviews

    // MARK: - The claim only a renderer can decide

    /// The real empty grove against a real `GroveView` that never finished loading — the only
    /// "nothing between the tab row and the footnote" this suite trusts, because it is produced by
    /// the same code the fixed screen runs rather than reconstructed by hand. A control render of
    /// each proves the harness stable before the disagreement between them means anything
    /// (`FailedReadTests.groveFailureDraws`'s own reasoning).
    @Test("The empty-grove sentence draws something an unloaded screen does not")
    func theSentenceIsOnScreen() async throws {
        let sentence = try #require(await Self.render { Self.grove(grove: .empty) })
        let sentenceAgain = try #require(await Self.render { Self.grove(grove: .empty) })
        let unloaded = try #require(await Self.render { Self.groveNeverLoads() })
        let unloadedAgain = try #require(await Self.render { Self.groveNeverLoads() })

        #expect(sentence == sentenceAgain, "the renderer is not stable, so the comparison below is void")
        #expect(unloaded == unloadedAgain, "the renderer is not stable, so the comparison below is void")
        #expect(
            sentence != unloaded,
            """
            the empty grove rendered identically to a screen that never finished loading (title, \
            tab row, footnote, nothing between) — E48's sentence is not reaching the screen
            """
        )
    }

    /// The same comparison, for a grove with one recognized species — `oneKnownSpeciesIsNeverTheEmptyGrove`
    /// pins this at the presentation layer; here it is a picture. A contributor who has met a species
    /// must see the tile that names it, never the sentence that says they have met none.
    @Test("A grove with one known species draws its tile, not the empty-grove sentence")
    func aKnownSpeciesDrawsSomethingElse() async throws {
        let populated = try #require(await Self.render { Self.grove(grove: Self.oneKnown) })
        let empty = try #require(await Self.render { Self.grove(grove: .empty) })
        #expect(
            populated != empty,
            "a grove with a known species rendered the same picture as the empty grove"
        )
    }

    // MARK: - Fixtures

    private static let oneKnown = GroveSpecies(
        neighborhood: nil,
        known: Series(complete: [
            KnownSpecies(
                speciesID: UUID(uuidString: "08000000-0000-4000-8000-000000000001")!,
                scientificName: "Cupressus macrocarpa",
                commonName: "Monterey Cypress",
                firstMetAt: now.addingTimeInterval(-400 * 86_400),
                firstMetAddress: "1200 Great Highway"
            )
        ])
    )

    /// Answers `groveSpecies()` with a suspension that outlives every capture this suite ever takes,
    /// so `GroveModel.presentation` never leaves `nil` and `hasFailed` never leaves `false` — the one
    /// state `speciesTab` has no branch for at all. Cancelled for free when the hosting window comes
    /// down at the end of `render(_:)`, the same way any other screen's in-flight `.task` is.
    private struct NeverRespondingAPI: CypressAPI {
        func groveSpecies() async throws -> GroveSpecies {
            try await Task.sleep(for: .seconds(3_600))
            return .empty
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

    // MARK: - Harness

    private static func grove(grove: GroveSpecies) -> some View {
        NavigationStack {
            GroveView(api: GrovePreviewAPI(grove: grove), now: { now })
        }
        .environment(AppRouter())
    }

    private static func groveNeverLoads() -> some View {
        NavigationStack {
            GroveView(api: NeverRespondingAPI(), now: { now })
        }
        .environment(AppRouter())
    }

    private static let width: CGFloat = 393
    private static let height: CGFloat = 852

    /// `FailedReadTests.render`, unchanged and for its reasons: a real `UIHostingController` in a
    /// real off-screen window, eight short sleeps rather than a run-loop spin (the `.task` that
    /// loads the grove is suspended on the cooperative executor, and a window that was never made
    /// key lays out nothing), then the drawn pixels.
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
#endif
