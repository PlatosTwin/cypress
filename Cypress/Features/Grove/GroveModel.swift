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

    init(api: any CypressAPI, now: @escaping @Sendable () -> Date = { Date() }, tab: GroveTab = .species) {
        self.api = api
        self.now = now
        self.tab = tab
    }

    /// The derivation the species grid draws, or nil while loading or after a failure.
    var presentation: GrovePresentation? {
        guard case let .loaded(grove) = phase else { return nil }
        return GrovePresentation(grove: grove, now: now())
    }

    var hasFailed: Bool { phase == .failed }

    func load() async {
        do {
            phase = .loaded(try await api.groveSpecies())
        } catch {
            phase = .failed
        }
    }

    /// Re-reads after a failure. The load writes nothing, so a retry is free — the same reason
    /// `ShareModel.retry` and `SpeciesModel.retry` can offer one (ERRATA E126).
    func retry() async {
        phase = .loading
        await load()
    }

    // MARK: - The Trees pill

    var treesPresentation: GroveTreesPresentation? {
        guard case let .loaded(entries) = treesPhase else { return nil }
        return GroveTreesPresentation(entries: entries, now: now())
    }

    var treesHaveFailed: Bool { treesPhase == .failed }

    /// Reads the grove the first time the pill is asked for, and not again.
    ///
    /// **Lazy**, because a reader who opens My Grove and stays on `Species` should not pay for a
    /// query they never looked at. **Once**, because the `.task` that drives this fires on every
    /// reappearance of the view it is attached to, so a reader switching pills back and forth would
    /// otherwise re-run the read on every switch. "Once" has to be a property of the model rather
    /// than of the view, which is what makes it testable.
    func loadTreesIfNeeded() async {
        guard case .idle = treesPhase else { return }
        await readTrees()
    }

    func retryTrees() async {
        treesPhase = .idle
        await readTrees()
    }

    private func readTrees() async {
        do {
            treesPhase = .loaded(try await api.grove())
        } catch {
            treesPhase = .failed
        }
    }
}
