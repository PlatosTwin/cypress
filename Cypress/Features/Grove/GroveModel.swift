//
//  GroveModel.swift
//  Cypress — Features/Grove
//
//  Screen 08's one `@Observable` model (ARCHITECTURE §3: "One `@Observable` model per feature
//  folder, owned by the feature's root view via `@State`"). It talks to `CypressAPI` and to nothing
//  else — no store, no network (ARCHITECTURE §4).
//
//  ── Two reads, kept apart ─────────────────────────────────────────────────────────────────────
//  The screen's two pills each have data behind them and they are two different endpoints:
//  `groveSpecies()` for the species grid and `grove()` for the list of trees. Each therefore has its
//  own way to fail, and a single `phase` would mean one failing read blanked the other pill — a
//  reader whose species read failed would find an empty-looking Trees list and conclude they had no
//  trees. So there are two phases, and `GroveTreesTests.thePhasesAreIndependent` is the assertion
//  that they stay that way.
//

import Foundation
import Observation

@MainActor
@Observable
final class GroveModel {

    /// Where the species read is.
    ///
    /// A failed read is its own case rather than an empty grove, because the two look identical on
    /// screen and mean opposite things: one says "you have not met a species yet", the other says
    /// "we could not tell". Drawing the cold-start state over a failure would be the same class of
    /// mistake as printing a page's size as a total.
    enum Phase: Equatable {
        case loading
        case loaded(GroveSpecies)
        case failed
    }

    /// Where the trees read is. The same reasons as `Phase`, over a different endpoint, plus two
    /// things that endpoint has and the species read does not: a page and a state for being asked.
    ///
    /// **`.loading` is new and it is a defect fix, not a refactor.** There used to be three cases
    /// and `.idle` covered both "nobody has opened this pill" and "the read is in flight", and
    /// `GroveView` drew nothing for either — a column with a selected pill above it and no content,
    /// no spinner and no skeleton. At forty trees that was one frame and the omission was
    /// deliberate and measured (`docs/whats-new/fix-grove-tab-performance.md`). At a thousand it was
    /// three and a half seconds of a screen that looks broken, photographed. The owner ruled on
    /// 2026-09-02 that the blank is a defect whatever its duration, so the phases are now exhaustive
    /// over things that can be drawn — see `treesDrawing`, which is the property that makes that
    /// exhaustiveness a fact about the type rather than about this paragraph.
    ///
    /// `.loaded` carries the cursor beside the rows for `JournalModel.Phase`'s reason: the rows and
    /// the place they stop are one answer, and a screen that held them apart could offer a
    /// `Show more` that asks from the wrong place.
    enum TreesPhase: Equatable {
        /// Nobody has asked for this pill yet.
        case idle
        /// The first page is in flight.
        case loading
        case loaded(entries: [GroveEntry], nextCursor: String?)
        case failed
    }

    /// What the `Trees` column draws, for every phase there is.
    ///
    /// **The type is the guard.** A `switch` over this in `GroveView` has three arms and no
    /// default, and there is no case here that means "nothing" — so a phase that draws nothing
    /// cannot be reintroduced by leaving an arm out, which is exactly how the blank column existed
    /// for two rounds. `GroveTreesPagingTests` pins that `.idle` and `.loading` both arrive here as
    /// `.loading`, and `GroveDrawnLoadingShot` photographs the column to prove that arm puts pixels
    /// on the glass rather than merely existing.
    enum TreesDrawing: Equatable {
        case loading
        case list(GroveTreesPresentation)
        case failed
    }

    private(set) var phase: Phase = .loading
    private(set) var treesPhase: TreesPhase = .idle

    /// Which pill is showing.
    ///
    /// **It was a `let` fixed at `.species`**, on the grounds that the other pills had nowhere to go.
    /// `Trees` now does — see `GroveTab` — so the screen is a screen with segments rather than one
    /// segment with labels beside it.
    var tab: GroveTab

    private let api: any CypressAPI
    private let now: @Sendable () -> Date

    /// The Species read again, with the account's half merged in — or nil when there is no service
    /// to merge from (`DataLayer.refreshGroveSpecies`, which is where the whole argument lives).
    ///
    /// Nil is the default and nil means *no background task at all*: every preview, every
    /// screenshot fixture and every unit test that builds this model passes nothing and gets the
    /// pure-local model they have always had.
    private let refreshSpecies: (@Sendable () async -> GroveSpecies?)?

    /// The Trees read again, on the same terms.
    private let refreshTrees: (@Sendable () async -> [GroveEntry]?)?

    /// The background refresh currently in flight, or nil.
    ///
    /// **Held so that it can be awaited**, which is the only way a test can assert what the refresh
    /// did without reading a clock: `await model.speciesRefresh?.value` returns when the merge has
    /// been applied, and until then the assertion available is that the *local* answer is already
    /// on screen. `GroveLocalFirstTests` is built on exactly those two facts and no timing at all.
    ///
    /// `@ObservationIgnored` because nothing draws it — a view that observed it would re-render on
    /// the task's creation as well as on the phase change it produces.
    @ObservationIgnored private(set) var speciesRefresh: Task<Void, Never>?
    @ObservationIgnored private(set) var treesRefresh: Task<Void, Never>?

    init(
        api: any CypressAPI,
        now: @escaping @Sendable () -> Date = { Date() },
        tab: GroveTab = .species,
        refreshSpecies: (@Sendable () async -> GroveSpecies?)? = nil,
        refreshTrees: (@Sendable () async -> [GroveEntry]?)? = nil
    ) {
        self.api = api
        self.now = now
        self.tab = tab
        self.refreshSpecies = refreshSpecies
        self.refreshTrees = refreshTrees
    }

    /// The derivation the species grid draws, or nil while loading or after a failure.
    var presentation: GrovePresentation? {
        guard case let .loaded(grove) = phase else { return nil }
        return GrovePresentation(grove: grove, now: now())
    }

    var hasFailed: Bool { phase == .failed }

    /// Reads the species grove once, then keeps it current in the background.
    ///
    /// ── Three arms, because the `.task` that drives this fires on every appearance ──────────────
    ///
    /// The view this is attached to is mounted afresh on **every** switch back to the My Grove tab,
    /// so this method is called again each time. It used to have no guard at all, which meant every
    /// visit re-ran the read — and at the time the read awaited a network round trip, so every visit
    /// paid for one. `loadTreesIfNeeded()` below has had the guard since it was written and states
    /// the reason: "once" has to be a property of the model rather than of the view, which is what
    /// makes it testable.
    ///
    /// - `.loading` — nothing has been read yet. Read the phone, paint it, then refresh behind it.
    /// - `.loaded` — the answer is already on the glass. **Re-read the phone and repaint, then
    ///   refresh behind it.** Nothing passes through `.loading`, so there is no blank and no spinner;
    ///   the reader sees what they saw, updated. That is the owner's ruling of 2026-09-01 made
    ///   literal, and it is the same arm `JournalModel.load()` takes for the same ruling.
    /// - `.failed` — leave it. The retry button is the way back from a failure (ERRATA E126), and a
    ///   `.task` firing again is not somebody asking for one.
    ///
    /// ── The local re-read is not redundant with the refresh, and PR #144's review is why ────────
    ///
    /// The first cut of this arm did **only** `startSpeciesRefresh()`, on the reasoning that the
    /// refresh re-reads the phone before it merges. It does — but only when there *is* a refresh, and
    /// there is none in a build whose remote gate is shut, which is every DEBUG build and the whole
    /// UI suite. So the tab froze at its first read for the life of the process: favorite a tree from
    /// the Map, come back, and the grove still said what it said. The prose claimed a gate-shut build
    /// "behaves exactly as it did" while the suite pinned the opposite.
    ///
    /// Re-reading here fixes that and one more thing besides: a **local** write — a visit logged from
    /// a tree profile, a favorite — now shows on revisit in every build rather than only in one that
    /// can reach the service. At about 6 ms it is not a cost worth arm-wrestling over.
    ///
    /// A re-read that throws leaves the painted grove exactly where it is. A background read the
    /// reader did not ask for must not take down a screen that is already showing them their grove
    /// (R72 ruling 1) — the same reasoning `JournalModel.refresh()` states for its own failure path.
    func load() async {
        switch phase {
        case .loading:
            do {
                phase = .loaded(try await api.groveSpecies())
            } catch {
                phase = .failed
                return
            }
            startSpeciesRefresh()
        case .loaded:
            if let fresh = try? await api.groveSpecies() { phase = .loaded(fresh) }
            startSpeciesRefresh()
        case .failed:
            break
        }
    }

    /// Re-reads after a failure. The load writes nothing, so a retry is free — the same reason
    /// `ShareModel.retry` and `SpeciesModel.retry` can offer one (ERRATA E126).
    func retry() async {
        phase = .loading
        await load()
    }

    /// Merges the account's half in behind the painted screen.
    ///
    /// Nothing here can blank the grove. The refresh answers nil when it could not reach the
    /// service, and a nil leaves the painted phase exactly as it is — "an empty state is a claim,
    /// and this project has already drawn one over a failed read" (R72 ruling 1).
    ///
    /// The guard on `.loaded` before assigning is not ceremony: `retry()` can move the phase back to
    /// `.loading` while a refresh is in flight, and a merge landing after that would paint a grove
    /// over a screen that is deliberately reading again.
    private func startSpeciesRefresh() {
        guard let refreshSpecies else { return }
        speciesRefresh?.cancel()
        speciesRefresh = Task { [weak self] in
            let merged = await refreshSpecies()
            guard !Task.isCancelled, let self, let merged, case .loaded = self.phase else { return }
            self.phase = .loaded(merged)
        }
    }

    // MARK: - The Trees pill

    var treesPresentation: GroveTreesPresentation? {
        guard case let .loaded(entries, nextCursor) = treesPhase else { return nil }
        return GroveTreesPresentation(entries: entries, hasMore: nextCursor != nil)
    }

    /// The one thing the view switches on. See `TreesDrawing`.
    var treesDrawing: TreesDrawing {
        switch treesPhase {
        case .idle, .loading:
            return .loading
        case let .loaded(entries, nextCursor):
            return .list(GroveTreesPresentation(entries: entries, hasMore: nextCursor != nil))
        case .failed:
            return .failed
        }
    }

    var treesHaveFailed: Bool { treesPhase == .failed }

    /// Whether the last `Show more` failed. Cleared by the next successful one, and never set by
    /// the first read — `JournalModel`'s two-flags rule, for its reason: a `Show more` that fails
    /// leaves the reader with everything they already had, and taking the column down for it would
    /// throw away rows that were read successfully in order to report that some others were not.
    private(set) var hasFailedMoreTrees = false

    /// Whether a page read is in flight, so the control cannot be pressed twice into two reads of
    /// the same cursor — which would append the same rows twice.
    private(set) var isLoadingMoreTrees = false

    /// Whether the re-entry refresh is in flight. Nothing on screen changes while it is.
    private(set) var isRefreshingTrees = false

    /// Reads the grove's **first page** the first time the pill is asked for, and not again.
    ///
    /// **Lazy**, because a reader who opens My Grove and stays on `Species` should not pay for a
    /// query they never looked at. **Once**, because the `.task` that drives this fires on every
    /// reappearance of the view it is attached to, so a reader switching pills back and forth would
    /// otherwise re-run the read on every switch. "Once" has to be a property of the model rather
    /// than of the view, which is what makes it testable.
    ///
    /// **A pill already loaded repaints and refreshes rather than doing nothing** — `load()`'s
    /// `.loaded` arm exactly, for the same ruling, and now with the one thing a paginated list adds:
    /// the refresh has to reconcile page one against the pages `Show more` fetched instead of
    /// replacing them. See `refreshTrees()`.
    ///
    /// **`.loading` returns**, which is not the same as `.failed` returning. A `.task(id:)` firing
    /// while the first read is in flight is the view reappearing, not a second request; starting a
    /// second read there would race two answers onto one phase.
    func loadTreesIfNeeded() async {
        switch treesPhase {
        case .idle:
            await readFirstTreesPage()
        case .loading:
            break
        case .loaded:
            await refreshTreesPageOne()
            startTreesRefresh()
        case .failed:
            break
        }
    }

    /// The first page, from nothing. Passes through `.loading` — which draws — and never through a
    /// state that draws nothing.
    private func readFirstTreesPage() async {
        treesPhase = .loading
        do {
            let page = try await api.grove(cursor: nil, limit: GroveLimits.pageSize)
            treesPhase = .loaded(entries: page.items, nextCursor: page.nextCursor)
            hasFailedMoreTrees = false
        } catch {
            treesPhase = .failed
            return
        }
        startTreesRefresh()
    }

    func retryTrees() async {
        treesPhase = .idle
        await loadTreesIfNeeded()
    }

    /// The next page, appended.
    ///
    /// **Guarded on the cursor, not on the row count**, for `JournalModel.loadOlder`'s reason:
    /// without it this would re-read page one — `grove(cursor: nil, …)` is a valid call that always
    /// returns the newest rows — and draw every one of them a second time. The guard is also what
    /// makes the control's absence and the read's refusal the same condition.
    func loadMoreTrees() async {
        guard case let .loaded(entries, cursor) = treesPhase, let cursor, !isLoadingMoreTrees else {
            return
        }
        isLoadingMoreTrees = true
        defer { isLoadingMoreTrees = false }
        do {
            let page = try await api.grove(cursor: cursor, limit: GroveLimits.pageSize)
            treesPhase = .loaded(
                entries: entries + page.items, nextCursor: page.nextCursor
            )
            hasFailedMoreTrees = false
        } catch {
            // The rows already read stay on screen. Only the note changes.
            hasFailedMoreTrees = true
        }
    }

    /// **Re-reads page one behind a list that never stops showing what it had.**
    ///
    /// `JournalModel.refresh()`'s reconciliation, over this list, and the argument transfers whole
    /// because the two lists now share the property it rests on: a **total** order. The grove's is
    /// `ContributionStore.groveOrderSQL` and `GroveOrderKey` is its mirror here.
    ///
    /// Three cases, and the third is the one a naive merge gets wrong:
    ///
    /// 1. **A tree entered the grove, or was visited again and moved up.** It is in the fresh page.
    ///    Held rows the fresh page does not contain sort below its last row and are kept after it.
    /// 2. **The fresh page reached the end** (`nextCursor == nil`). It *is* the whole grove, so
    ///    anything held beyond it no longer exists and is dropped. The empty grove — every favorite
    ///    withdrawn — is the same statement.
    /// 3. **A tree left the grove from inside the fresh window.** It is held, absent from the fresh
    ///    page, and sorts *above* that page's last row. Keeping it would put a tree back in a grove
    ///    the reader took it out of, so the `orderKey <= oldest` test drops exactly those.
    ///
    /// **The `<=` is `<` here and that is worth saying rather than copying.** On the journal the
    /// boundary case is load-bearing: two contributions can share a `captured_at`, so a held row
    /// tying with the fresh page's last row is ambiguous and the tie is kept. Here the key carries
    /// the tree's own uuid, so two *different* trees can never tie — the only entry `<=` admits
    /// that `<` would not is the fresh page's last row itself, which the id filter one line above
    /// has already excluded. It is written `<=` so the two methods read as the same rule; it cannot
    /// change an answer.
    ///
    /// **A failure does nothing.** A background re-read the reader did not ask for must not take
    /// down a column that is already showing them their trees (R72 ruling 1), and it must not raise
    /// `hasFailedMoreTrees` either — that flag is `Show more`'s, and this is not that.
    private func refreshTreesPageOne() async {
        guard case let .loaded(held, heldCursor) = treesPhase, !isRefreshingTrees else { return }
        isRefreshingTrees = true
        defer { isRefreshingTrees = false }

        guard let fresh = try? await api.grove(cursor: nil, limit: GroveLimits.pageSize) else {
            return
        }
        guard let oldest = fresh.items.last?.orderKey, fresh.nextCursor != nil else {
            treesPhase = .loaded(entries: fresh.items, nextCursor: fresh.nextCursor)
            return
        }
        let freshIDs = Set(fresh.items.map(\.treeID))
        let kept = held.filter { !freshIDs.contains($0.treeID) && $0.orderKey <= oldest }
        treesPhase = .loaded(
            entries: fresh.items + kept,
            nextCursor: kept.isEmpty ? fresh.nextCursor : heldCursor
        )
    }

    /// `startSpeciesRefresh()`, over the Trees pill — the account's half, merged in behind the
    /// painted column.
    ///
    /// **What it has to do that the species one does not: stay inside the window the reader
    /// revealed.** `refreshTrees` answers with the *whole* joined grove, because that is what
    /// `RoutedAPI.refreshedGrove` is — one join over one delta. Assigning it whole would undo the
    /// paging on the first background refresh and hand SwiftUI the thousand rows again, so the
    /// merged answer is cut to the window the reader has actually asked for: at least a page, and
    /// as much as they have revealed.
    ///
    /// **The cursor is derived from the merged list and that is sound because both lists carry one
    /// order.** `refreshedGrove` sorts by `GroveOrderKey`, which is the query's order, so the last
    /// kept row names the same position in both. A tree the account has and this phone does not,
    /// arriving inside the window, pushes a local row past the cursor — where the next `Show more`
    /// will read it. Nothing is shown twice and nothing is skipped.
    private func startTreesRefresh() {
        guard let refreshTrees else { return }
        treesRefresh?.cancel()
        treesRefresh = Task { [weak self] in
            let merged = await refreshTrees()
            guard !Task.isCancelled, let self, let merged,
                  case let .loaded(held, _) = self.treesPhase
            else { return }
            let window = max(GroveLimits.pageSize, held.count)
            let kept = Array(merged.prefix(window))
            self.treesPhase = .loaded(
                entries: kept,
                nextCursor: merged.count > window ? kept.last?.groveCursor : nil
            )
        }
    }
}
