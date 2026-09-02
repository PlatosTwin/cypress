//
//  GroveTreesPagingTests.swift
//  CypressTests
//
//  Screen 08's `Trees` pill, paged — the model's half.
//
//  Two owner rulings of 2026-09-02 are what this file is about, and they are separate claims:
//
//  1. the pill pages, the way `Journal > Yours` does, and paging state survives a tab flip and the
//     background re-read that a revisit runs behind it;
//  2. **no phase of this pill draws nothing.** The blank column was a deliberate omission at 26 ms
//     on a forty-tree grove and a three-and-a-half-second hole at a thousand; the ruling is that it
//     is a defect at any duration.
//
//  The second one is not a value assertion, so it is not asserted as one: `GroveDrawnLoadingShot`
//  renders the column and reads the pixels back. See it for why.
//

import Foundation
import Testing
@testable import Cypress

@Suite("My Grove · the Trees pill pages, and always draws something")
struct GroveTreesPagingTests {

    // MARK: - Doubles

    /// A grove that answers whole, so the pages come from the protocol default — the same
    /// implementation every preview and every other double gets. Reads are counted, and the whole
    /// list can be changed between reads, which is what a contribution logged elsewhere is.
    private final class WholeGroveAPI: CypressAPI, @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [GroveEntry]
        private var failing = false
        private(set) var reads = 0

        init(_ entries: [GroveEntry]) { self.entries = entries }

        func set(_ entries: [GroveEntry]) {
            lock.withLock { self.entries = entries }
        }

        func failNextReads(_ failing: Bool) {
            lock.withLock { self.failing = failing }
        }

        func grove() async throws -> [GroveEntry] {
            let (entries, failing) = lock.withLock {
                reads += 1
                return (self.entries, self.failing)
            }
            if failing { throw APIError.serverError }
            return entries
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
        func journal(cursor: String?, limit: Int) async throws -> Page<JournalEntry> { Page(items: []) }
        func claimDevice(deviceUUID: UUID, userID: UUID) async throws {}
        func deleteAccount(_ choice: AccountDeletionChoice) async throws -> AccountDeletion.Outcome {
            throw APIError.unauthorized
        }
        func logHazardRedirect(_ event: HazardRedirectEvent) async throws {}
        func exportLatest(_ format: ExportFormat) async throws -> Data { Data() }
    }

    // MARK: - Fixtures

    static let start = Date(timeIntervalSince1970: 1_780_000_000)

    /// `count` trees, newest first, with ids that ascend so the order is the one the store's would
    /// be. `visitedThrough` decides how many carry a visit; the rest are favorites nobody has
    /// visited, which is the run that shares a `last_visited` of NULL.
    static func grove(_ count: Int, visitedThrough: Int? = nil) -> [GroveEntry] {
        let visited = visitedThrough ?? count
        return (0..<count).map { index in
            GroveEntry(
                treeID: UUID(uuidString: String(format: "0E000000-0000-4000-8000-%012d", index))!,
                displayName: "Tree \(index)",
                coordinate: Coordinate(latitude: 37.77, longitude: -122.44),
                lastVisitedAt: index < visited
                    ? start.addingTimeInterval(Double(-60 * index))
                    : nil,
                isFavorite: true,
                record: GroveRecord.none
            )
        }
        .sorted { $0.orderKey > $1.orderKey }
    }

    // MARK: - Ruling 2: no phase draws nothing

    /// **Every phase this pill can be in arrives at something drawable**, which is a fact about the
    /// type: `TreesDrawing` has no case that means "nothing", and `GroveView` switches over it with
    /// no `default`. The blank column existed because the view had three `if`s and the model had a
    /// fourth state.
    @Test("the phase before an answer draws the loading treatment, not a blank column")
    @MainActor
    func everyPhaseDrawsSomething() async {
        let model = GroveModel(api: WholeGroveAPI(Self.grove(3)), tab: .trees)

        #expect(
            model.treesDrawing == .loading,
            "a pill nobody has opened yet draws \(model.treesDrawing) — `.idle` used to draw nothing"
        )

        await model.loadTreesIfNeeded()
        guard case let .list(painted) = model.treesDrawing else {
            Issue.record("a loaded pill draws \(model.treesDrawing)")
            return
        }
        #expect(painted.rows.count == 3)

        let failed = GroveModel(api: GrovePreviewAPI(treesFail: true), tab: .trees)
        await failed.loadTreesIfNeeded()
        #expect(failed.treesDrawing == .failed)
    }

    /// The in-flight case, which is the one the reader actually sat in front of for three and a
    /// half seconds. `.idle` is what a pill nobody has opened is in; `.loading` is what it is in
    /// while the read runs, and both have to draw.
    @Test("the phase while the first read is in flight also draws")
    @MainActor
    func theReadInFlightDraws() async {
        let api = SuspendingGroveAPI()
        let model = GroveModel(api: api, tab: .trees)

        let load = Task { await model.loadTreesIfNeeded() }
        await api.waitUntilAsked()

        #expect(
            model.treesPhase == .loading,
            "the phase during the read is \(model.treesPhase), not `.loading`"
        )
        #expect(model.treesDrawing == .loading, "the column drew \(model.treesDrawing) mid-read")

        api.answer([])
        await load.value
    }

    // MARK: - Ruling 1: it pages

    @Test("the first read is one page, and the rest is behind Show more")
    @MainActor
    func theFirstReadIsOnePage() async {
        let api = WholeGroveAPI(Self.grove(GroveLimits.pageSize * 3, visitedThrough: GroveLimits.pageSize))
        let model = GroveModel(api: api, tab: .trees)

        await model.loadTreesIfNeeded()
        guard case let .list(first) = model.treesDrawing else {
            Issue.record("the first read drew \(model.treesDrawing)")
            return
        }
        #expect(first.rows.count == GroveLimits.pageSize)
        #expect(first.moreNote != nil, "a grove three pages long offered no way to see page two")

        await model.loadMoreTrees()
        guard case let .list(second) = model.treesDrawing else {
            Issue.record("Show more drew \(model.treesDrawing)")
            return
        }
        #expect(second.rows.count == GroveLimits.pageSize * 2)
        #expect(
            second.rows.map(\.treeID).count == Set(second.rows.map(\.treeID)).count,
            "Show more drew a tree the first page had already drawn"
        )

        await model.loadMoreTrees()
        guard case let .list(third) = model.treesDrawing else {
            Issue.record("the last page drew \(model.treesDrawing)")
            return
        }
        #expect(third.rows.count == GroveLimits.pageSize * 3)
        #expect(third.moreNote == nil, "the end of the grove still offered `Show more`")
    }

    /// **The pages a reader revealed survive a tab flip**, which is the whole reason the model is
    /// hoisted above `RootView.tabRoot`'s switch (#144). A revisit repaints and re-reads page one
    /// *behind* what is already there — `JournalModel.refresh()`'s arm — rather than resetting to
    /// one page.
    @Test("a revisit keeps the pages that were revealed")
    @MainActor
    func aRevisitKeepsRevealedPages() async {
        let api = WholeGroveAPI(Self.grove(GroveLimits.pageSize * 3))
        let model = GroveModel(api: api, tab: .trees)

        await model.loadTreesIfNeeded()
        await model.loadMoreTrees()
        guard case let .loaded(revealed, _) = model.treesPhase else {
            Issue.record("the fixture never revealed two pages: \(model.treesPhase)")
            return
        }
        #expect(revealed.count == GroveLimits.pageSize * 2, "the fixture revealed one page, not two")

        // The tab flip. `GroveView` is destroyed and rebuilt on the same model, so `.task` calls
        // this again on a phase that is already `.loaded`.
        await model.loadTreesIfNeeded()

        guard case let .loaded(after, cursor) = model.treesPhase else {
            Issue.record("the revisit lost the list: \(model.treesPhase)")
            return
        }
        #expect(
            after.map(\.treeID) == revealed.map(\.treeID),
            """
            the revisit left \(after.count) trees of the \(revealed.count) the reader had \
            revealed — `Show more` became un-doable by looking away
            """
        )
        #expect(cursor != nil, "the revisit threw away the cursor, so page three is unreachable")
    }

    /// **…and a tree that entered the grove between visits appears, without costing the pages.**
    /// This is the half that a `guard case .loaded { return }` would pass while being wrong: the
    /// pill would keep its pages and freeze at its first read for the life of the process.
    @Test("a tree favorited elsewhere appears on the revisit, above the pages already revealed")
    @MainActor
    func aNewTreeAppearsWithoutLosingPages() async {
        let api = WholeGroveAPI(Self.grove(GroveLimits.pageSize * 3))
        let model = GroveModel(api: api, tab: .trees)
        await model.loadTreesIfNeeded()
        await model.loadMoreTrees()

        // A visit logged from a tree profile between the two glances: a new tree, newest of all.
        let newcomer = GroveEntry(
            treeID: UUID(uuidString: "0EFFFFFF-0000-4000-8000-000000000001")!,
            displayName: "The Corner Oak",
            coordinate: Coordinate(latitude: 37.77, longitude: -122.44),
            lastVisitedAt: Self.start.addingTimeInterval(60),
            isFavorite: true,
            record: GroveRecord.none
        )
        api.set(([newcomer] + Self.grove(GroveLimits.pageSize * 3)).sorted { $0.orderKey > $1.orderKey })

        await model.loadTreesIfNeeded()

        guard case let .loaded(after, _) = model.treesPhase else {
            Issue.record("the revisit lost the list: \(model.treesPhase)")
            return
        }
        #expect(after.first?.treeID == newcomer.treeID, "the newcomer is not at the top of the list")
        #expect(
            after.count == GroveLimits.pageSize * 2 + 1,
            """
            the revisit holds \(after.count) trees, not the two pages plus the newcomer. Losing \
            rows here is the reconciliation dropping pages; gaining them is it repeating rows
            """
        )
        #expect(
            after.count == Set(after.map(\.treeID)).count,
            "the reconciliation drew a tree twice"
        )
    }

    /// **A tree that left the grove goes**, which is the case a naive "fresh plus everything held"
    /// merge gets wrong: it would put a favorite back that the reader had just withdrawn.
    @Test("a tree withdrawn from inside page one does not survive the revisit")
    @MainActor
    func aWithdrawnTreeDoesNotComeBack() async {
        var whole = Self.grove(GroveLimits.pageSize * 3)
        let api = WholeGroveAPI(whole)
        let model = GroveModel(api: api, tab: .trees)
        await model.loadTreesIfNeeded()
        await model.loadMoreTrees()

        let withdrawn = whole[2]
        whole.remove(at: 2)
        api.set(whole)

        await model.loadTreesIfNeeded()
        guard case let .loaded(after, _) = model.treesPhase else {
            Issue.record("the revisit lost the list: \(model.treesPhase)")
            return
        }
        #expect(
            !after.contains { $0.treeID == withdrawn.treeID },
            "a tree the reader unfavorited was put back by the refresh"
        )
    }

    /// **A `Show more` that fails keeps every row on screen** and says so on its own line.
    /// `hasFailed` is the first read's flag and this must not touch it — `JournalModel`'s
    /// two-failures rule, which exists because taking the column down would throw away rows that
    /// were read successfully.
    @Test("a failed Show more keeps the rows and does not take the column down")
    @MainActor
    func aFailedShowMoreKeepsTheRows() async {
        let api = WholeGroveAPI(Self.grove(GroveLimits.pageSize * 3))
        let model = GroveModel(api: api, tab: .trees)
        await model.loadTreesIfNeeded()

        api.failNextReads(true)
        await model.loadMoreTrees()

        #expect(model.hasFailedMoreTrees, "the failure was not reported anywhere")
        #expect(model.treesHaveFailed == false, "a failed page took down the whole column")
        guard case let .list(painted) = model.treesDrawing else {
            Issue.record("a failed page left the column drawing \(model.treesDrawing)")
            return
        }
        #expect(painted.rows.count == GroveLimits.pageSize, "the rows already read left the screen")
        #expect(painted.moreNote != nil, "the control that would retry the page is gone")

        api.failNextReads(false)
        await model.loadMoreTrees()
        #expect(model.hasFailedMoreTrees == false, "the note stayed up after a page that worked")
    }

    /// A first page that came back empty **with a cursor** is not a cold start, and the cold-start
    /// sentence is the one place getting E38 wrong tells somebody their grove is gone.
    @Test("an empty page that stopped early does not claim the grove is empty")
    func anEmptyPageWithACursorIsNotAColdStart() {
        #expect(GroveTreesPresentation(entries: [], hasMore: false).emptyState != nil)
        #expect(
            GroveTreesPresentation(entries: [], hasMore: true).emptyState == nil,
            "a read that stopped early told the reader they have no trees"
        )
    }
}

// MARK: - A read that can be held open

/// A grove read that suspends until a test answers it, so the in-flight phase can be observed.
///
/// `AlmanacLateFixTests.Held` exists for the same reason and says it at length: an `async` function
/// with no `await` in its body is not guaranteed to yield, so a double that simply returns can
/// never show a caller what the model looks like *during* a read.
final class SuspendingGroveAPI: CypressAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<[GroveEntry], Error>?
    private var answer: [GroveEntry]?
    private var asked = false

    func waitUntilAsked() async {
        for _ in 0..<2_000 {
            if lock.withLock({ asked }) { return }
            await Task.yield()
        }
        Issue.record("the model never asked for the grove")
    }

    func answer(_ entries: [GroveEntry]) {
        let waiting: CheckedContinuation<[GroveEntry], Error>? = lock.withLock {
            let waiting = continuation
            continuation = nil
            answer = entries
            return waiting
        }
        waiting?.resume(returning: entries)
    }

    func grove() async throws -> [GroveEntry] {
        try await withCheckedThrowingContinuation { continuation in
            let ready: [GroveEntry]? = lock.withLock {
                asked = true
                if let answer { return answer }
                self.continuation = continuation
                return nil
            }
            if let ready { continuation.resume(returning: ready) }
        }
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
    func journal(cursor: String?, limit: Int) async throws -> Page<JournalEntry> { Page(items: []) }
    func claimDevice(deviceUUID: UUID, userID: UUID) async throws {}
    func deleteAccount(_ choice: AccountDeletionChoice) async throws -> AccountDeletion.Outcome {
        throw APIError.unauthorized
    }
    func logHazardRedirect(_ event: HazardRedirectEvent) async throws {}
    func exportLatest(_ format: ExportFormat) async throws -> Data { Data() }
}
