//
//  JournalModel.swift
//  Cypress — Features/Journal
//
//  The journal list's one `@Observable` model (ARCHITECTURE §3). It talks to `CypressAPI` and to
//  nothing else (§4).
//
//  ── Two failures, kept apart ──────────────────────────────────────────────────────────────────
//  This screen can fail twice and the two mean different things. A **first** read that fails leaves
//  the reader with no journal at all, and must say so rather than draw the cold-start state (ERRATA
//  E126). A **`Show earlier`** that fails leaves the reader with everything they already had; taking
//  the whole screen down for it would throw away rows that were read successfully in order to report
//  that some others were not. So there are two flags, and `hasFailed` is never set by the second
//  kind — see `loadOlder`.
//

import Foundation
import Observation

@MainActor
@Observable
final class JournalModel {

    /// Where the first read is.
    ///
    /// A failed read is its own case rather than an empty journal, for the reason `GroveModel.Phase`
    /// gives: the two look identical on screen and mean opposite things.
    enum Phase: Equatable {
        case loading
        case loaded(entries: [JournalEntry], nextCursor: String?)
        case failed
    }

    private(set) var phase: Phase = .loading

    /// Everything the list draws, derived **once per phase change** rather than once per body pass.
    ///
    /// This was a computed property. SwiftUI evaluates a body many times for one visible change —
    /// a scroll, an appearance, an observation firing anywhere in the subtree — and each evaluation
    /// rebuilt the whole derivation: every row's title, the day fold, and a `DateFormatter` per day
    /// group inside `JournalCopy.day`. A full page is up to `JournalLimits.pageSize` groups, so the
    /// cost was paid up to twenty-five times over on every redraw of a screen whose content had not
    /// changed.
    ///
    /// **`now` is therefore sampled when the phase changes, not when the view draws**, and that is
    /// a real difference rather than an implementation detail: `JournalCopy.day` prints the year on
    /// a date outside the current one, so a screen left open across midnight on December 31st would
    /// have started printing years the moment it next redrew and now does so on its next read. The
    /// list not silently relabelling itself under a reader is the better of the two, and the year
    /// boundary is the only input `now` has.
    ///
    /// Set by `setPhase` alone, which is the one writer of `phase` — see it for why the pair moves
    /// together rather than through a `didSet`.
    private(set) var presentation: JournalPresentation?

    /// Whether the last `Show earlier` failed. Cleared by the next successful one.
    private(set) var hasFailedOlder = false

    /// Whether a page read is in flight, so the control cannot be pressed twice into two reads of
    /// the same cursor — which would append the same rows twice.
    private(set) var isLoadingOlder = false

    private let api: any CypressAPI
    private let now: @Sendable () -> Date

    init(api: any CypressAPI, now: @escaping @Sendable () -> Date = { Date() }) {
        self.api = api
        self.now = now
    }

    var hasFailed: Bool { phase == .failed }

    /// The one writer of `phase`, so `presentation` cannot fall behind it.
    ///
    /// A `didSet` on `phase` would read more directly and is not used: `phase` is a stored property
    /// of an `@Observable` type, and the macro rewrites those into accessors over a backing store.
    /// A single explicit setter keeps the pairing legible in the source rather than depending on
    /// what the macro does with an observer.
    private func setPhase(_ newPhase: Phase) {
        phase = newPhase
        guard case let .loaded(entries, cursor) = newPhase else {
            presentation = nil
            return
        }
        presentation = JournalPresentation(entries: entries, nextCursor: cursor, now: now())
    }

    /// The first page.
    ///
    /// **Idempotent on a successful read**, so the `.task` that fires on every reappearance does not
    /// throw away pages the reader has already asked for — a screen that reset itself every time you
    /// looked away would make `Show earlier` un-doable by accident.
    ///
    /// **That guard is only worth anything while the model outlives the view**, and this is where a
    /// comment on this method was wrong for two rounds: the guard was here, it was correct, and the
    /// model it guarded was `@State` on `JournalSection`, which sat inside `JournalTabView`'s
    /// `switch` on the segment. Glancing at Neighborhood and back destroyed the model, the next
    /// `.task` met a fresh `.loading`, and every page after the first was gone. The claim was a
    /// property of the model that the view structure did not give it.
    ///
    /// So the ownership is now stated as the thing it is: `JournalTabView` holds the model *above*
    /// its segment `switch`, which makes this guard true across Yours ↔ Neighborhood ↔ City.
    /// `JournalModelOwnershipGuardTests` reads the two files rather than trusting this paragraph.
    ///
    /// **Across the bottom tabs it is true exactly as far as whoever holds `JournalTabView` makes it
    /// true.** `RootView.tabRoot` is a `switch` on `router.tab`, so leaving the Journal tab destroys
    /// the tab view and this model with it. That is one level up and outside this file; nothing here
    /// claims otherwise.
    func load() async {
        if case .loaded = phase { return }
        await read()
    }

    /// Re-runs the first read after a failure. The read writes nothing, so a retry is free — the
    /// same reason `GroveModel.retry` can offer one (ERRATA E126).
    func retry() async {
        setPhase(.loading)
        await read()
    }

    private func read() async {
        do {
            let page = try await api.journal(cursor: nil, limit: JournalLimits.pageSize)
            setPhase(.loaded(entries: page.items, nextCursor: page.nextCursor))
            hasFailedOlder = false
        } catch {
            setPhase(.failed)
        }
    }

    /// The next page, appended.
    ///
    /// **Guarded on the cursor, not on the row count.** Without the guard this would re-read page one
    /// — `journal(cursor: nil, …)` is a valid call that always returns the newest rows — and draw
    /// every one of them a second time. The guard is also what makes the button's absence and the
    /// read's refusal the same condition: `hasOlder` is `nextCursor != nil` and so is this.
    func loadOlder() async {
        guard case let .loaded(entries, cursor) = phase, let cursor, !isLoadingOlder else { return }
        isLoadingOlder = true
        defer { isLoadingOlder = false }
        do {
            let page = try await api.journal(cursor: cursor, limit: JournalLimits.pageSize)
            setPhase(.loaded(entries: entries + page.items, nextCursor: page.nextCursor))
            hasFailedOlder = false
        } catch {
            // The rows already read stay on screen. Only the note changes — see the file comment.
            hasFailedOlder = true
        }
    }
}
