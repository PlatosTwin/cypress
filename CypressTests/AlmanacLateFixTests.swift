//
//  AlmanacLateFixTests.swift
//  CypressTests
//
//  Screen 12 opened before CoreLocation has answered. ERRATA — see docs/errata-pending/almanac-blank.md.
//
//  ── The defect these tests are the assertion form of ──────────────────────────────────────
//  `AlmanacView` built its model in a `@State` initialiser, which runs exactly once, so the almanac
//  was derived from whatever coordinate existed in the first frame and from no other — `nil`, on a
//  cold launch, because the composition root's provider has not published anything yet. The read
//  returned `.empty` by contract and stayed. Meanwhile `showsLocationPrompt` was a plain `let`
//  recomputed on every pass the parent made, so a second later, when the fix did arrive, the prompt
//  was *withdrawn* — from a screen that had nothing to put in its place. Header, footnote, eleven
//  hundred points of nothing, permanently.
//
//  ── Why the obvious test would have passed on the broken app ──────────────────────────────
//  Every value involved was individually correct. `almanac(near: nil)` is `.empty` and is supposed
//  to be; `coordinate == nil` was false and was supposed to be; the read did not fail, so `hasFailed`
//  was correctly false. A test that loads the model once and checks any of those passes either way.
//  What is only true on the fixed app is a statement about a *sequence*: that the second coordinate
//  is read at all, and that the sentence explaining an empty screen is never removed before the
//  content that replaces it exists. Both tests below are about the order of things, not the values.
//
//  The second one needs the read held open to say anything, because the window it is about is
//  exactly the duration of one database read. `Held` is that: an API that parks inside
//  `almanac(near:)` until the test lets it go, so the half-way state can be looked at instead of
//  raced against.
//

#if DEBUG
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Cypress

@MainActor
@Suite("Screen 12 · the fix that arrives after the screen does")
struct AlmanacLateFixTests {

    // MARK: - Fixtures

    static let now = Date(timeIntervalSince1970: 1_784_505_600) // 2026-07-20

    /// A fix inside Sunset/Parkside.
    static let fix = Coordinate(latitude: 37.7530, longitude: -122.4850)
    /// A different one, for the read-supersedes-read case.
    static let otherFix = Coordinate(latitude: 37.7845, longitude: -122.4215)

    private static func id(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "12000000-0000-4000-8000-%012d", index))!
    }

    /// Enough of a neighbourhood to be unmistakably *not* the empty one: a name for the header pill
    /// and a composition card under it. The numbers are not the subject and are not asserted on.
    static let neighbourhood = Almanac(
        neighborhood: AlmanacNeighborhood(
            name: "Sunset/Parkside",
            composition: NeighborhoodComposition(
                distinctSpeciesCount: 215,
                treeCount: 11_026,
                leading: [
                    SpeciesShare(speciesID: id(10), name: "New Zealand Xmas Tree", treeCount: 1_561),
                    SpeciesShare(speciesID: id(11), name: "Monterey Cypress", treeCount: 816)
                ]
            )
        )
    )

    // MARK: - Doubles

    /// `LocalAPI.almanac(near:)`'s contract, and only that: without a coordinate there is no area and
    /// the payload is empty.
    ///
    /// The preview double answers the same almanac whatever it is handed, which is right for drawing
    /// a screen and useless here — a model that never re-read would still look correct against it.
    /// Every read is counted, because "did it read a second time" is half of what is being asked.
    private final class FixSensitive: CypressAPI, @unchecked Sendable {
        let payload: Almanac
        /// Touched only from `AlmanacModel`, which is `@MainActor`, so this is single-threaded in
        /// fact; `@unchecked` records that rather than assumes it, as `FailedReadTests.Attempts` does.
        private(set) var reads: [Coordinate?] = []

        init(payload: Almanac) { self.payload = payload }

        func almanac(near coordinate: Coordinate?) async throws -> Almanac {
            reads.append(coordinate)
            return coordinate == nil ? .empty : payload
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

    /// A one-shot rendezvous: `arrive()` suspends until somebody calls `release()`, and everybody who
    /// arrives after the release passes straight through.
    ///
    /// Two of them make the read observable from outside while it is in flight — one signalling that
    /// the read has begun, one holding it there. Sleeping for a guessed interval instead would make
    /// the test's subject a timing assumption rather than the ordering it is about.
    private actor Latch {
        private var isOpen = false
        private var waiting: [CheckedContinuation<Void, Never>] = []

        func arrive() async {
            if isOpen { return }
            await withCheckedContinuation { waiting.append($0) }
        }

        func release() {
            isOpen = true
            for continuation in waiting { continuation.resume() }
            waiting = []
        }
    }

    /// `FixSensitive`, with the **first** read for a real coordinate parked until the test lets it
    /// finish. Only the first: a second fix arriving while the first read is held has to be able to
    /// complete, or the case it stages deadlocks instead of describing anything.
    private final class Held: CypressAPI, @unchecked Sendable {
        let payload: Almanac
        let began = Latch()
        let mayFinish = Latch()
        private var reads = 0

        init(payload: Almanac) { self.payload = payload }

        func almanac(near coordinate: Coordinate?) async throws -> Almanac {
            guard coordinate != nil else { return .empty }
            reads += 1
            let isTheHeldOne = reads == 1
            await began.release()
            if isTheHeldOne { await mayFinish.arrive() }
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

    // MARK: - The model reads the fix that turns up after it was built

    @Test("An almanac built without a fix re-reads when the fix arrives")
    func lateFixIsRead() async {
        let api = FixSensitive(payload: Self.neighbourhood)
        let model = AlmanacModel(api: api, coordinate: nil, now: { Self.now })

        // Mount, exactly as `AlmanacView`'s `.task(id:)` does it: the first call carries the same
        // coordinate the model was constructed with.
        await model.update(coordinate: nil)
        #expect(model.presentation?.neighborhoodName == nil, "a nil fix has no neighbourhood to name")
        #expect(model.needsLocation, "and the screen has to say why it is empty")

        // CoreLocation answers.
        await model.update(coordinate: Self.fix)

        #expect(api.reads == [nil, Self.fix], "the second coordinate was never read")
        #expect(model.presentation?.neighborhoodName == "Sunset/Parkside")
        #expect(model.needsLocation == false, "the prompt would still be over the content")
    }

    @Test("The same coordinate arriving again does not re-read")
    func unchangedFixIsNotReRead() async {
        let api = FixSensitive(payload: Self.neighbourhood)
        let model = AlmanacModel(api: api, coordinate: Self.fix, now: { Self.now })

        await model.update(coordinate: Self.fix)
        await model.update(coordinate: Self.fix)

        #expect(api.reads == [Self.fix], "every published fix would re-read the whole almanac")
    }

    // MARK: - The invariant: an empty screen always says why

    /// The window this test is about is one database read wide, and it is the whole defect.
    ///
    /// E123 computed the prompt from the coordinate the *parent* was holding. The moment the fix
    /// arrives that condition goes false, and it goes false one read before there is a neighbourhood
    /// to draw. So there was an interval — brief on paper, permanent in practice, because the read
    /// that would end it was never started — in which screen 12 had nothing on it and nothing to say
    /// about that. E126's invariant is that this interval must not exist.
    ///
    /// **The time limit is not boilerplate.** This test waits on the read *beginning*, so an app that
    /// has stopped re-reading altogether does not fail it — it never wakes it up. Measured: with the
    /// re-read deliberately removed, this sat on its latch and took the whole run with it, and a suite
    /// that hangs on a broken app reports nothing at all. Three minutes rather than Swift Testing's
    /// minimum of one, because one minute is reachable by *load* — this machine has run these tests at
    /// a load average of 300 with three agents on it, and a limit that a busy machine can trip is a
    /// flake wearing a failure's clothes.
    @Test(
        "The location prompt is not withdrawn until the neighbourhood is there to replace it",
        .timeLimit(.minutes(3))
    )
    func promptSurvivesUntilContentArrives() async {
        let api = Held(payload: Self.neighbourhood)
        let model = AlmanacModel(api: api, coordinate: nil, now: { Self.now })

        await model.update(coordinate: nil)
        #expect(model.needsLocation)

        let arrival = Task { await model.update(coordinate: Self.fix) }
        await api.began.arrive()

        // Mid-read. The model has the new fix, the screen still has the old empty almanac — and the
        // sentence explaining it is still standing.
        #expect(model.coordinate == Self.fix, "the model did not take the new fix")
        #expect(model.presentation?.neighborhoodName == nil, "the read has not answered yet")
        #expect(model.needsLocation, "the prompt left before the neighbourhood arrived — E126's blank")
        #expect(model.hasFailed == false, "nothing failed; the wrong sentence would be worse than none")

        await api.mayFinish.release()
        await arrival.value

        #expect(model.presentation?.neighborhoodName == "Sunset/Parkside")
        #expect(model.needsLocation == false)
    }

    /// Two fixes in quick succession — a real possibility on a phone that is still settling.
    ///
    /// The stale answer must not land on top of the fresh one, and `displayedCoordinate` must end up
    /// naming the picture that is actually on screen; otherwise the prompt's condition is being
    /// computed from a read the reader is not looking at.
    @Test("A superseded read does not overwrite the fix that replaced it", .timeLimit(.minutes(3)))
    func supersededReadIsDropped() async {
        let api = Held(payload: Self.neighbourhood)
        let model = AlmanacModel(api: api, coordinate: nil, now: { Self.now })

        let first = Task { await model.update(coordinate: Self.fix) }
        await api.began.arrive()

        // A second fix lands while the first read is still parked. `Held` lets this one through
        // immediately, because its latch is already released.
        await model.update(coordinate: Self.otherFix)
        #expect(model.needsLocation == false)

        await api.mayFinish.release()
        await first.value

        #expect(model.coordinate == Self.otherFix)
        #expect(model.displayedCoordinate == Self.otherFix, "the stale read claimed the screen")
    }

    // MARK: - The screen, as pixels

    /// A host whose coordinate starts `nil` and becomes a fix after the first frame — which is what
    /// the composition root does on a cold launch, in the only form a unit test can stage it.
    ///
    /// Both arms of the comparison go through this same view so the two hierarchies are structurally
    /// identical and the pixels are comparable at all; only `late` differs.
    private struct LateFixHost: View {
        let api: any CypressAPI
        let late: Bool
        @State private var coordinate: Coordinate?
        /// Held rather than constructed in `body`, which runs again on every pass: a fresh router
        /// per pass is a fresh identity per pass, and the late arm has passes the early one does not.
        @State private var router = AppRouter()

        init(api: any CypressAPI, late: Bool) {
            self.api = api
            self.late = late
            _coordinate = State(wrappedValue: late ? nil : AlmanacLateFixTests.fix)
        }

        var body: some View {
            NavigationStack {
                AlmanacView(
                    api: api,
                    coordinate: coordinate,
                    now: { AlmanacLateFixTests.now },
                    onBack: {}
                )
            }
            .environment(router)
            // Runs after the first render pass, so `AlmanacView` really does mount with `nil` and
            // really does start its own read from it. No sleep: the transition is caused, not timed.
            .task { if late { coordinate = AlmanacLateFixTests.fix } }
        }
    }

    /// The end-to-end statement, and the one that would have caught this without knowing where it was.
    ///
    /// Driven through `AlmanacView` rather than by handing `AlmanacScreen` a flag, for the reason
    /// E126 gives about its own render test: the wiring between the model and the screen is half of
    /// what was broken, and a test that sets the flag itself would not have noticed.
    ///
    /// The assertion is **equality**, which is unusual and deliberate. A fix that arrives late must
    /// leave the reader looking at the same screen as a fix that was there all along; anything else
    /// — the blank, the prompt still standing, a half-drawn column — is a different picture. The
    /// control render below it proves the harness is byte-stable first, without which an equality
    /// assertion is just as void as an inequality one (ARCHITECTURE §7).
    /// **The comparison is reduced to a `Bool` before `#expect` sees it, and it has to be.** Handing
    /// `#expect` two `Data` values and letting it compare them is how this test spent its first life:
    /// on a *failing* comparison Swift Testing builds a Myers diff of the two collections to describe
    /// the mismatch, and a Myers diff of two hundred-kilobyte PNGs does not finish. Sampled on the
    /// broken app: one hundred per cent of a core and three gigabytes resident, inside
    /// `_myers(from:to:using:)`, with no failure ever reported. `FailedReadTests` never met this
    /// because its picture assertions are *inequalities*, which pass and so never ask for a
    /// description. An equality on large `Data` is a test that cannot fail — the exact defect this
    /// project keeps finding — and the fix is to compare outside the macro and assert on the answer.
    @Test("Screen 12 ends up looking the same whether the fix was there at mount or arrived after")
    func lateFixDrawsTheSameScreen() async throws {
        let early = try #require(await Self.render(late: false))
        let earlyAgain = try #require(await Self.render(late: false))
        let late = try #require(await Self.render(late: true))

        let rendererIsStable = early == earlyAgain
        let lateMatchesEarly = late == early

        #expect(rendererIsStable, "the renderer is not stable, so the comparison below is void")
        #expect(
            lateMatchesEarly,
            "a late fix draws a different screen from one present at mount, which is this defect"
        )
    }

    // MARK: - Harness

    private static let width: CGFloat = 393
    private static let height: CGFloat = 852

    /// `FailedReadTests.render`'s harness verbatim in shape, for its reasons: a `UIHostingController`
    /// in a visible off-screen window, and short sleeps rather than a run-loop spin, because the
    /// `.task` that performs the read is suspended on the cooperative executor and a window that was
    /// never made key lays out nothing.
    ///
    /// Twelve passes rather than eight: this screen performs *two* reads in the late arm, and the
    /// second does not begin until the first has finished and the coordinate has propagated.
    private static func render(late: Bool) async -> Data? {
        let host = UIHostingController(
            rootView: AnyView(
                LateFixHost(api: FixSensitive(payload: neighbourhood), late: late)
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

        for _ in 0..<12 {
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
