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

    var presentation: JournalPresentation? {
        guard case let .loaded(entries, cursor) = phase else { return nil }
        return JournalPresentation(entries: entries, nextCursor: cursor, now: now())
    }

    var hasFailed: Bool { phase == .failed }

    /// The first page.
    ///
    /// Idempotent on a successful read, so the `.task` that fires on every reappearance of a segment
    /// does not throw away pages the reader has already asked for. A screen that reset itself every
    /// time you switched away and back would make `Show earlier` un-doable by accident.
    func load() async {
        if case .loaded = phase { return }
        await read()
    }

    /// Re-runs the first read after a failure. The read writes nothing, so a retry is free — the
    /// same reason `GroveModel.retry` can offer one (ERRATA E126).
    func retry() async {
        phase = .loading
        await read()
    }

    private func read() async {
        do {
            let page = try await api.journal(cursor: nil, limit: JournalLimits.pageSize)
            phase = .loaded(entries: page.items, nextCursor: page.nextCursor)
            hasFailedOlder = false
        } catch {
            phase = .failed
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
            phase = .loaded(entries: entries + page.items, nextCursor: page.nextCursor)
            hasFailedOlder = false
        } catch {
            // The rows already read stay on screen. Only the note changes — see the file comment.
            hasFailedOlder = true
        }
    }
}
