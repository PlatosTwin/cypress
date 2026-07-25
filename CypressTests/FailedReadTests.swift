//
//  FailedReadTests.swift
//  CypressTests
//
//  The two tab roots whose single read can fail with nothing else on the screen to say so — My Grove
//  (08) and the Journal, which draws the almanac (12). ERRATA E126.
//
//  ── What this suite is guarding, and why the obvious test does not guard it ───────────────
//  Both models already distinguished a failed read from an empty one, and both views drew the two
//  identically: `presentation` is nil for `.loading` and for `.failed` alike, and a single
//  `if let presentation` with no else left the column blank. A blank column is *also* what an empty
//  grove and a quiet neighbourhood look like — those are legitimate, common states with legitimate,
//  designed layouts — so the failure was invisible by construction.
//
//  A test that asserts `model.hasFailed == true` would have passed on the broken app: the property
//  was correct the whole time and had no readers. A test that asserts the copy string exists would
//  have passed too. What can only pass on the fixed app is a comparison of the two *pictures*: the
//  screen after a read that failed against the screen after a read that succeeded and returned
//  nothing. Those were the same image, and the whole of E126 is that they no longer are.
//
//  So this suite has two halves, and they are not interchangeable:
//
//  1. **the model half**, which pins the states apart as values — cheap, exact, and blind to whether
//     anything draws them;
//  2. **the render half**, which puts each screen through a real `UIHostingController` in a real
//     off-screen window and compares the pixels. It fails, loudly, the moment the failure arm is
//     removed from either view — which is how it was checked.
//
//  The renderer is `DynamicTypeScreenshotTests`' and `ScreenSweepShots`', for the reasons given
//  there: a run-loop spin does not drain the cooperative executor a `.task` is suspended on, so a
//  screen that loads asynchronously has to be waited for rather than laid out.
//

#if DEBUG
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Cypress

@MainActor
@Suite("Failed reads · My Grove and the Journal")
struct FailedReadTests {

    // MARK: - Fixtures

    /// Fixed, because both screens format dates off it and a clock reading is not the subject here.
    static let now = Date(timeIntervalSince1970: 1_784_505_600) // 2026-07-20

    /// A real fix, so the almanac is not showing E123's location prompt instead of its content. The
    /// prompt takes the same slot, and a screen showing it would be answering a different question.
    static let coordinate = Coordinate(latitude: 37.7533, longitude: -122.4934)

    /// One read that fails and then answers, so a retry can be judged by the only thing that makes
    /// it a retry: the second attempt getting a different result from the first.
    private final class Attempts: @unchecked Sendable {
        var grove = 0
        var almanac = 0
    }

    /// Both screens' reads, each failing exactly once. Every access is from a `@MainActor` model, so
    /// the counter is only ever touched on one thread; `@unchecked` records that rather than assumes
    /// it, the same way `FavoriteToggleTests.Favourites` does.
    private struct FailsOnce: CypressAPI {
        let attempts: Attempts

        func groveSpecies() async throws -> GroveSpecies {
            attempts.grove += 1
            if attempts.grove == 1 { throw APIError.serverError }
            return .empty
        }

        func almanac(near coordinate: Coordinate?) async throws -> Almanac {
            attempts.almanac += 1
            if attempts.almanac == 1 { throw APIError.serverError }
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

    // MARK: - The models, as values

    @Test("A grove that could not be read is not an empty grove")
    func groveFailureIsItsOwnState() async {
        let failed = GroveModel(api: GrovePreviewAPI(fails: true), now: { Self.now })
        await failed.load()
        #expect(failed.hasFailed)
        #expect(failed.presentation == nil)

        // The read the failure is mistakeable for: it finished, and there is nothing in it.
        let empty = GroveModel(api: GrovePreviewAPI(grove: .empty), now: { Self.now })
        await empty.load()
        #expect(empty.hasFailed == false)
        #expect(empty.presentation != nil)
    }

    @Test("An almanac that could not be read is not a quiet neighbourhood")
    func almanacFailureIsItsOwnState() async {
        let failed = AlmanacModel(
            api: AlmanacPreviewAPI(fails: true),
            coordinate: Self.coordinate,
            now: { Self.now }
        )
        await failed.load()
        #expect(failed.hasFailed)
        #expect(failed.presentation == nil)

        let empty = AlmanacModel(
            api: AlmanacPreviewAPI(payload: .empty),
            coordinate: Self.coordinate,
            now: { Self.now }
        )
        await empty.load()
        #expect(empty.hasFailed == false)
        #expect(empty.presentation != nil)
    }

    @Test("Try again re-runs the grove read and clears the failure")
    func groveRetryRecovers() async {
        let attempts = Attempts()
        let model = GroveModel(api: FailsOnce(attempts: attempts), now: { Self.now })

        await model.load()
        #expect(model.hasFailed)

        await model.retry()
        #expect(attempts.grove == 2)
        #expect(model.hasFailed == false)
        #expect(model.presentation != nil)
    }

    @Test("Try again re-runs the almanac read and clears the failure")
    func almanacRetryRecovers() async {
        let attempts = Attempts()
        let model = AlmanacModel(
            api: FailsOnce(attempts: attempts),
            coordinate: Self.coordinate,
            now: { Self.now }
        )

        await model.load()
        #expect(model.hasFailed)

        await model.retry()
        #expect(attempts.almanac == 2)
        #expect(model.hasFailed == false)
        #expect(model.presentation != nil)
    }

    // MARK: - The copy the arm renders

    @Test("The failure sentence says the read failed and claims nothing about the subject")
    func failureCopyStatesOneFact() {
        for sentence in [GroveCopy.loadFailed, AlmanacCopy.loadFailed] {
            #expect(sentence.hasSuffix("."))
            // A9 and §5.6 govern what a *finished* read may say about an empty subject. A failed
            // read has not earned any of those sentences, so it borrows none of their words.
            for forbidden in ["yet", "nothing", "empty", "quiet"] {
                #expect(
                    sentence.lowercased().contains(forbidden) == false,
                    "\(sentence) reads as a statement about the subject, not about the read"
                )
            }
        }
        #expect(GroveCopy.loadRetry == "Try again")
        #expect(AlmanacCopy.loadRetry == "Try again")
    }

    // MARK: - The screens, as pixels

    /// Screen 08 after a failed read against screen 08 after a read that came back empty.
    ///
    /// These two were byte-identical before E126, which is the defect stated as an assertion. The
    /// control below it is not decoration: an inequality assertion measures nothing unless the same
    /// screen rendered twice is equal, and this harness has to be shown to be that stable before its
    /// disagreement means anything (ARCHITECTURE §7's rule about controls that do not fire).
    @Test("Screen 08 draws something after a failed read that it does not draw for an empty grove")
    func groveFailureDraws() async throws {
        let failed = try #require(await Self.render { Self.grove(fails: true) })
        let empty = try #require(await Self.render { Self.grove(fails: false) })
        let emptyAgain = try #require(await Self.render { Self.grove(fails: false) })

        #expect(empty == emptyAgain, "the renderer is not stable, so the comparison below is void")
        #expect(failed != empty, "a failed grove read draws the empty grove, which is E126's defect")
    }

    /// The same comparison for screen 12, driven end to end through `AlmanacView` rather than by
    /// handing `AlmanacScreen` a flag — the wiring between the model's `hasFailed` and the arm is
    /// half of what broke, and a test that sets the flag itself would not have noticed.
    ///
    /// One control render, in the test above, covers both: it is the harness that is being proved
    /// stable, not the screen. Each capture is seconds of real work on a loaded machine, and a
    /// second copy of the same proof buys nothing.
    @Test("Screen 12 draws something after a failed read that it does not draw for an empty almanac")
    func almanacFailureDraws() async throws {
        let failed = try #require(await Self.render { Self.almanac(fails: true) })
        let empty = try #require(await Self.render { Self.almanac(fails: false) })

        #expect(failed != empty, "a failed almanac read draws the empty almanac, which is E126's defect")
    }

    // MARK: - Harness

    private static func grove(fails: Bool) -> some View {
        NavigationStack {
            GroveView(api: GrovePreviewAPI(grove: .empty, fails: fails), now: { now })
        }
        .environment(AppRouter())
    }

    private static func almanac(fails: Bool) -> some View {
        NavigationStack {
            AlmanacView(
                api: AlmanacPreviewAPI(payload: .empty, fails: fails),
                coordinate: coordinate,
                now: { now },
                onBack: {}
            )
        }
        .environment(AppRouter())
    }

    private static let width: CGFloat = 393
    private static let height: CGFloat = 852

    /// The PNG bytes of one screen, rendered the way the app renders it.
    ///
    /// `UIHostingController` in a visible off-screen window, and eight short sleeps rather than a
    /// run-loop spin, both for `ScreenSweepShots.capture`'s reasons — the `.task` that performs the
    /// read is suspended on the cooperative executor, and a window that was never made key lays out
    /// nothing.
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
