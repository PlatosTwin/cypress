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

    /// Where the trees read is. The same three states for the same reason, over a different endpoint.
    enum TreesPhase: Equatable {
        case idle
        case loaded([GroveEntry])
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
        guard case let .loaded(entries) = treesPhase else { return nil }
        return GroveTreesPresentation(entries: entries)
    }

    var treesHaveFailed: Bool { treesPhase == .failed }

    /// Reads the grove the first time the pill is asked for, and not again.
    ///
    /// **Lazy**, because a reader who opens My Grove and stays on `Species` should not pay for a
    /// query they never looked at. **Once**, because the `.task` that drives this fires on every
    /// reappearance of the view it is attached to, so a reader switching pills back and forth would
    /// otherwise re-run the read on every switch. "Once" has to be a property of the model rather
    /// than of the view, which is what makes it testable.
    ///
    /// **A pill already loaded repaints and refreshes rather than doing nothing** — `load()`'s
    /// `.loaded` arm exactly, for the same ruling and with the same argument for the local re-read.
    /// What the guard still buys is that the pill never returns to a blank column: the phase does not
    /// pass back through `.idle`, so the rows on screen stay on screen while the fresh read runs.
    func loadTreesIfNeeded() async {
        switch treesPhase {
        case .idle:
            do {
                treesPhase = .loaded(try await api.grove())
            } catch {
                treesPhase = .failed
                return
            }
            startTreesRefresh()
        case .loaded:
            if let fresh = try? await api.grove() { treesPhase = .loaded(fresh) }
            startTreesRefresh()
        case .failed:
            break
        }
    }

    func retryTrees() async {
        treesPhase = .idle
        await loadTreesIfNeeded()
    }

    /// `startSpeciesRefresh()`, over the Trees pill. Its whole argument applies unchanged.
    private func startTreesRefresh() {
        guard let refreshTrees else { return }
        treesRefresh?.cancel()
        treesRefresh = Task { [weak self] in
            let merged = await refreshTrees()
            guard !Task.isCancelled, let self, let merged, case .loaded = self.treesPhase else { return }
            self.treesPhase = .loaded(merged)
        }
    }
}
