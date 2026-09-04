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

        /// The read currently parked inside `grove()`, if one is.
        private var gate: CheckedContinuation<Void, Never>?
        /// Whether the *next* read parks rather than answering.
        private var holdNext = false
        /// Somebody waiting to be told that a read has parked.
        private var parked: CheckedContinuation<Void, Never>?

        /// **Holds the next read open**, which is the whole instrument for the interleaving tests
        /// below. Without a read that can be left in flight, `loadMoreTrees` and
        /// `refreshTreesPageOne` can only be driven one after the other — and the defect review
        /// found lives precisely in the case where one resumes inside the other.
        func holdNextRead() { lock.withLock { holdNext = true } }

        /// Suspends until a read is parked, so a test can act while one is genuinely in flight
        /// rather than sleeping and hoping.
        func awaitParkedRead() async {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let alreadyParked: Bool = lock.withLock {
                    if gate != nil { return true }
                    parked = continuation
                    return false
                }
                if alreadyParked { continuation.resume() }
            }
        }

        func releaseHeldRead() {
            let held: CheckedContinuation<Void, Never>? = lock.withLock {
                let held = gate
                gate = nil
                return held
            }
            held?.resume()
        }

        func grove() async throws -> [GroveEntry] {
            let shouldHold: Bool = lock.withLock {
                reads += 1
                let hold = holdNext
                holdNext = false
                return hold
            }
            if shouldHold {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    let waiter: CheckedContinuation<Void, Never>? = lock.withLock {
                        gate = continuation
                        let waiter = parked
                        parked = nil
                        return waiter
                    }
                    waiter?.resume()
                }
            }
            let (entries, failing) = lock.withLock { (self.entries, self.failing) }
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

    /// The grove is **two full pages and a short one**, deliberately: a grove of exactly three
    /// pages ends on a full page, which carries a cursor and offers `Show more` once more —
    /// correct, and `LocalAPI.grovePage(cursor:limit:)`'s stated rule, but not the state this test is
    /// about.
    @Test("the first read is one page, and the rest is behind Show more")
    @MainActor
    func theFirstReadIsOnePage() async {
        let total = GroveLimits.pageSize * 2 + 7
        let api = WholeGroveAPI(Self.grove(total, visitedThrough: GroveLimits.pageSize))
        let model = GroveModel(api: api, tab: .trees)

        await model.loadTreesIfNeeded()
        guard case let .list(first) = model.treesDrawing else {
            Issue.record("the first read drew \(model.treesDrawing)")
            return
        }
        #expect(
            first.rows.count == GroveLimits.pageSize,
            "the first read drew \(first.rows.count) of \(total) trees, not one page"
        )
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
        #expect(third.rows.count == total, "the last page drew \(third.rows.count) of \(total)")
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

    /// …and the same page offers the **control** without the **sentence**. "There are more trees
    /// than these" needs a "these"; the button is still the right thing to press, because pressing
    /// it fetches the next page.
    @Test("an empty page that stopped early offers Show more without the sentence")
    func anEmptyPageWithACursorDrawsTheControlWithoutTheNote() {
        let empty = GroveTreesPresentation(entries: [], hasMore: true)
        #expect(empty.hasMore, "the control's own condition went away with the sentence")
        #expect(
            empty.moreNote == nil,
            "the list said there are more trees “than these” over no rows at all"
        )
        // The ordinary case still says it, or the guard above is just deleting the sentence.
        #expect(GroveTreesPresentation(entries: Self.grove(3), hasMore: true).moreNote != nil)
        #expect(GroveTreesPresentation(entries: Self.grove(3), hasMore: false).moreNote == nil)
    }

    // MARK: - Two reads in flight at once

    /// **A `Show more` that lands while the re-entry refresh is in flight must keep the page it
    /// revealed**, and before this round it did not.
    ///
    /// The input is two ordinary taps, in the order a reader produces them: press `Show more`, and
    /// while that read is running switch the pill (or leave the tab and come back). `GroveView`'s
    /// `.task(id:)` calls `loadTreesIfNeeded`, whose `.loaded` arm is `refreshTreesPageOne` — so a
    /// refresh is now running inside the `Show more`.
    ///
    /// `loadMoreTrees` guards only `isLoadingMoreTrees` and `refreshTreesPageOne` guards only
    /// `isRefreshingTrees`, so neither excludes the other. The refresh used to capture `held`
    /// **before** its `await` and write that snapshot back when it resumed, discarding the appended
    /// page. The fix is to read the phase *after* the await; this test is the order that proves it,
    /// and `theReverseInterleavingLosesNothing` is the other order.
    @Test("a Show more that lands while the re-entry refresh is in flight keeps the revealed page")
    @MainActor
    func aShowMoreInsideARefreshKeepsItsPage() async {
        let api = WholeGroveAPI(Self.grove(GroveLimits.pageSize * 3))
        let model = GroveModel(api: api, tab: .trees)
        await model.loadTreesIfNeeded()

        // The revisit's refresh starts and parks mid-read.
        api.holdNextRead()
        let revisit = Task { @MainActor in await model.loadTreesIfNeeded() }
        await api.awaitParkedRead()

        // The reader presses `Show more` while it is parked. This read is not held, so it lands
        // first — which is exactly the interleaving that used to lose the page.
        await model.loadMoreTrees()
        guard case let .loaded(revealed, _) = model.treesPhase else {
            Issue.record("Show more did not land at all: \(model.treesPhase)")
            return
        }
        #expect(
            revealed.count == GroveLimits.pageSize * 2,
            "the fixture never revealed a second page, so the race below is untested"
        )

        api.releaseHeldRead()
        await revisit.value

        guard case let .loaded(after, cursor) = model.treesPhase else {
            Issue.record("the refresh lost the list entirely: \(model.treesPhase)")
            return
        }
        #expect(
            after.count == GroveLimits.pageSize * 2,
            """
            the refresh resumed and wrote \(after.count) rows over the \
            \(GroveLimits.pageSize * 2) the reader had revealed: it reconciled against the \
            snapshot it took before its await, so the page pressed during the read was thrown away
            """
        )
        #expect(after.count == Set(after.map(\.treeID)).count, "the reconciliation drew a tree twice")
        #expect(cursor != nil, "page three became unreachable")
    }

    /// **The other order: the refresh lands first and the `Show more` resumes into it.**
    ///
    /// This one never lost rows — it discarded the refresh instead, which is benign — but it is
    /// where the symmetric fix in `loadMoreTrees` has to be right: appending a page fetched from a
    /// cursor the list no longer ends at would either repeat rows or leave a hole between the
    /// fresh page's tail and the old cursor. The assertion is therefore not a count but the shape:
    /// whatever is drawn is a **gapless prefix of the grove, in order, with nothing twice**.
    @Test("a refresh that lands while Show more is in flight leaves a gapless list")
    @MainActor
    func theReverseInterleavingLosesNothing() async {
        let whole = Self.grove(GroveLimits.pageSize * 3)
        let api = WholeGroveAPI(whole)
        let model = GroveModel(api: api, tab: .trees)
        await model.loadTreesIfNeeded()

        api.holdNextRead()
        let showMore = Task { @MainActor in await model.loadMoreTrees() }
        await api.awaitParkedRead()

        // The revisit's refresh runs to completion inside the parked `Show more`.
        await model.loadTreesIfNeeded()

        api.releaseHeldRead()
        await showMore.value

        guard case let .loaded(after, _) = model.treesPhase else {
            Issue.record("the interleaving lost the list: \(model.treesPhase)")
            return
        }
        #expect(after.count == Set(after.map(\.treeID)).count, "a tree was drawn twice")
        #expect(
            after.map(\.treeID) == whole.prefix(after.count).map(\.treeID),
            """
            the drawn list is not the grove's own prefix — the two reads were spliced at \
            different places and left a hole
            """
        )
        #expect(after.count >= GroveLimits.pageSize, "the list shrank below the page it started at")
    }

    // MARK: - The account's half beyond the drawn window

    /// **An account-only tree that sorts beyond the drawn window has to stay reachable.**
    ///
    /// `refreshTrees` (`RoutedAPI.refreshedGrove`) is the only read that returns the account's rows
    /// as well as the phone's; `grovePage` returns the phone's alone. `startTreesRefresh` used to
    /// cut the merged answer to the window and drop the rest, which put such a row in no page the
    /// reader could reach — not drawn, and not in any `Show more` — until some later refresh
    /// happened to widen the window past it. The comment on that method claimed "nothing is shown
    /// twice and nothing is skipped", which was true only of a row arriving *inside* the window.
    @Test("an account-only tree beyond the window is reachable by Show more")
    @MainActor
    func anAccountOnlyRowBeyondTheWindowIsReachable() async {
        let local = Self.grove(150)
        // Sorts between local rows 59 and 60, so it lands at merged index 60 — outside the first
        // window of 50, and in no page `grovePage` can produce, because this phone has never
        // heard of it.
        let accountOnly = GroveEntry(
            treeID: UUID(uuidString: "0EAAAAAA-0000-4000-8000-000000000060")!,
            displayName: "A tree from the other phone",
            coordinate: Coordinate(latitude: 37.77, longitude: -122.44),
            lastVisitedAt: Self.start.addingTimeInterval(-60 * 59.5),
            isFavorite: true,
            record: GroveRecord.none
        )
        let merged = (local + [accountOnly]).sorted { $0.orderKey > $1.orderKey }
        // The fixture only means something if the row really is past the first window.
        #expect(
            merged.firstIndex { $0.treeID == accountOnly.treeID } == 60,
            "the fixture put the account's tree inside the window, where the defect is not"
        )

        let api = WholeGroveAPI(local)
        let model = GroveModel(api: api, tab: .trees, refreshTrees: { merged })

        await model.loadTreesIfNeeded()
        await model.treesRefresh?.value

        guard case let .loaded(drawn, _) = model.treesPhase else {
            Issue.record("the first read did not land: \(model.treesPhase)")
            return
        }
        // Not drawn yet is correct: the window is one page, and this row is past it.
        #expect(drawn.count == GroveLimits.pageSize)
        #expect(!drawn.contains { $0.treeID == accountOnly.treeID })

        await model.loadMoreTrees()

        guard case let .loaded(after, _) = model.treesPhase else {
            Issue.record("Show more lost the list: \(model.treesPhase)")
            return
        }
        #expect(
            after.contains { $0.treeID == accountOnly.treeID },
            """
            the account's tree at merged position 60 is in no page the reader can reach: \
            `Show more` returned \(after.count) rows from the phone's own read, which does not \
            contain it, and the merged answer that did was thrown away
            """
        )
        #expect(after.count == Set(after.map(\.treeID)).count, "a tree was drawn twice")
        #expect(
            after.map(\.treeID) == merged.prefix(after.count).map(\.treeID),
            "the second page is not the merged grove's next slice, in order"
        )
    }
}

// MARK: - A read that can be held open

/// A grove read that suspends until a test answers it, so the in-flight phase can be observed.
///
/// `AlmanacLateFixTests.Held` exists for the same reason and says it at length: an `async` function
/// with no `await` in its body is not guaranteed to yield, so a double that simply returns can
/// never show a caller what the model looks like *during* a read.
/// **The handshake is two continuations and not a polling loop**, which is a correction rather than
/// a style: the first draft spun on `Task.yield()` until a flag flipped, and that passed on its
/// first run and failed on the next — the whole suite is `@MainActor` and runs in parallel, so how
/// many yields it takes for one main-actor task to reach a suspension depends on what the other
/// tests happen to be doing. A test that is a race with the scheduler reports the scheduler.
final class SuspendingGroveAPI: CypressAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<[GroveEntry], Error>?
    private var askedSignal: CheckedContinuation<Void, Never>?
    private var answer: [GroveEntry]?
    private var asked = false

    /// Returns once the model has entered `grove()` and suspended there.
    func waitUntilAsked() async {
        await withCheckedContinuation { (signal: CheckedContinuation<Void, Never>) in
            let alreadyAsked: Bool = lock.withLock {
                if asked { return true }
                askedSignal = signal
                return false
            }
            if alreadyAsked { signal.resume() }
        }
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
            let (ready, signal): ([GroveEntry]?, CheckedContinuation<Void, Never>?) = lock.withLock {
                asked = true
                let signal = askedSignal
                askedSignal = nil
                if let answer { return (answer, signal) }
                self.continuation = continuation
                return (nil, signal)
            }
            // Signalled *after* this call has committed to suspending, so a test that wakes on it
            // is looking at a model whose read is genuinely in flight.
            signal?.resume()
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
