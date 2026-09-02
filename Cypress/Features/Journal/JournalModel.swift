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
    /// **Three environment inputs are therefore sampled when the phase changes, not when the view
    /// draws.** An earlier draft of this paragraph named one, and PR #143's review counted:
    ///
    /// - **`now`** decides only whether `JournalCopy.day` prints the year, so freezing it means a
    ///   screen left open across midnight on December 31st relabels on its next read instead of on
    ///   its next redraw. That is the better of the two — a list should not silently relabel itself
    ///   under a reader — and the year boundary really is all `now` reaches.
    /// - **`locale`** decides the header's whole format.
    /// - **`calendar`** decides the format *and* the grouping: `JournalPresentation.init` folds
    ///   rows into days with `calendar.startOfDay(for:)`, so a time-zone change can restack which
    ///   rows sit under which header, not merely how the header reads.
    ///
    /// The last two are not opinions the model may hold about the reader's settings, and this
    /// change made them worse before it made them better: they used to be re-read on every body
    /// pass, and a model that now outlives a segment switch would have held stale ones for as long
    /// as it lived. So they are **re-sampled on the system's own notifications** — see
    /// `environmentObservers`. A Region, Calendar, first-weekday or time-zone change re-derives in
    /// place; a language change restarts the app and needs nothing here.
    ///
    /// That is also what makes `JournalDayFormatters`' retirement reachable at all. The cache is
    /// only consulted *during* a derivation, so before this a zone change retired nothing, because
    /// nothing re-derived — the mechanism was correct and, one level up, unreachable.
    ///
    /// Set by `setPhase` alone, which is the one writer of `phase` — see it for why the pair moves
    /// together rather than through a `didSet`.
    private(set) var presentation: JournalPresentation?

    /// Whether the last `Show earlier` failed. Cleared by the next successful one.
    private(set) var hasFailedOlder = false

    /// Whether a page read is in flight, so the control cannot be pressed twice into two reads of
    /// the same cursor — which would append the same rows twice.
    private(set) var isLoadingOlder = false

    /// Whether the background refresh on re-entry is in flight. Nothing on screen changes while it
    /// is — that is the point of it — but it must not overlap itself.
    private(set) var isRefreshing = false

    private let api: any CypressAPI
    private let now: @Sendable () -> Date
    /// The two environment inputs the derivation reads besides `now`, as closures for the same
    /// reason `now` is one: a test cannot change `Calendar.current`, and the paragraph on
    /// `presentation` is a claim about what happens when they change.
    private let calendar: @Sendable () -> Calendar
    private let locale: @Sendable () -> Locale

    /// Keeps the notification registrations alive for exactly as long as this model.
    ///
    /// A separate object rather than tokens on `self` so that unregistering is `deinit`'s job on a
    /// type with no isolation: this model is `@MainActor`, and touching main-actor state from its
    /// own `deinit` is the kind of thing that compiles today and is an error in the next language
    /// mode. The bag has no isolation and nothing to get wrong.
    private let environmentObservers: NotificationBag

    init(
        api: any CypressAPI,
        now: @escaping @Sendable () -> Date = { Date() },
        calendar: @escaping @Sendable () -> Calendar = { .current },
        locale: @escaping @Sendable () -> Locale = { .current }
    ) {
        self.api = api
        self.now = now
        self.calendar = calendar
        self.locale = locale
        self.environmentObservers = NotificationBag()

        // Re-derive, in place, when the reader changes something the derivation read. `setPhase`
        // is already the one writer, so this is a re-call with the phase it already has: the rows
        // are untouched and only the labels and the day fold are rebuilt. No read, no network, no
        // page lost.
        //
        // `.NSSystemTimeZoneDidChange` covers travelling and the Settings toggle; the locale
        // notification covers Region, Calendar and first-weekday. A **language** change relaunches
        // the app, so it needs nothing here.
        for name in [NSLocale.currentLocaleDidChangeNotification, .NSSystemTimeZoneDidChange] {
            environmentObservers.add(
                NotificationCenter.default.addObserver(
                    forName: name, object: nil, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.setPhase(self.phase)
                    }
                }
            )
        }
    }

    var hasFailed: Bool { phase == .failed }

    /// The one writer of `phase`, so `presentation` cannot fall behind it.
    ///
    /// A `didSet` on `phase` would read more directly and is not used: `phase` is a stored property
    /// of an `@Observable` type, and the macro rewrites those into accessors over a backing store.
    /// A single explicit setter keeps the pairing legible in the source rather than depending on
    /// what the macro does with an observer.
    ///
    /// **Called with the phase it already has to re-derive**, which is what the environment
    /// notifications do. Assigning `phase` to itself is not a no-op here: the derivation below is
    /// what re-samples `now`, `calendar` and `locale`.
    private func setPhase(_ newPhase: Phase) {
        phase = newPhase
        guard case let .loaded(entries, cursor) = newPhase else {
            presentation = nil
            return
        }
        presentation = JournalPresentation(
            entries: entries,
            nextCursor: cursor,
            now: now(),
            calendar: calendar(),
            locale: locale()
        )
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
    ///
    /// **And it does not simply return, which is the owner's other half.** The ruling is that a
    /// revisit paints what was there *and* refreshes behind it. Returning early gave the first and
    /// took away the second — PR #143's review pointed out that before the lifetime fix, flipping
    /// segments was at least an accidental refresh, and afterwards nothing re-read at all short of
    /// leaving the tab. So a re-entry on `.loaded` repaints instantly (nothing is cleared, nothing
    /// becomes `.loading`) and runs `refresh()` behind it.
    func load() async {
        if case .loaded = phase {
            await refresh()
            return
        }
        await read()
    }

    /// **Re-reads page one behind a list that never stops showing what it had.**
    ///
    /// This is `GroveModel.load()`'s arm — re-read, keep the old value visible until the new one
    /// arrives, never pass through `.loading` — with the one difference a paginated list forces:
    /// page one is not the whole answer, so the fresh page has to be *reconciled* with the deeper
    /// pages `Show earlier` fetched rather than replacing them.
    ///
    /// ── The reconciliation, and why it is sound ──────────────────────────────────────────────
    /// `ContributionStore.journal` orders by `captured_at DESC` and contributions are append-only
    /// and never back-dated across a page boundary — the property the cursor already depends on.
    /// So a fresh page one is the newest N rows, and everything the model holds beyond it is
    /// strictly older. Three cases, and the third is the one a naive merge gets wrong:
    ///
    /// 1. **New rows arrived.** They are at the head of the fresh page. Held rows the fresh page
    ///    does not contain are older than its last row, and are kept in place after it. The reader
    ///    sees the new contributions appear above a list that is otherwise untouched.
    /// 2. **The fresh page reached the end** (`nextCursor == nil`). Then the fresh page *is* the
    ///    whole journal, and anything held beyond it no longer exists. Held rows are dropped.
    /// 3. **A row inside the fresh window was deleted.** It is held, absent from the fresh page,
    ///    and *newer* than the fresh page's last row. Keeping it would resurrect a deleted
    ///    contribution, so the `capturedAt <= oldest` test drops exactly those. This is why the
    ///    merge is not simply "fresh + everything held it does not have".
    ///
    /// **The comparison is `<=` and not `<`, and as of `AppSchema` v19 that is load-bearing rather
    /// than a boundary curiosity.** Two contributions can share a `captured_at`. A held row tying
    /// with the fresh page's last row is ambiguous — it could be a row that belongs *after* page
    /// one in the ordering (case 1, keep it) or a deletion (case 3, drop it) — and the two
    /// directions cost different things: dropping loses a contribution the reader is looking at,
    /// which is what the owner's ruling forbids, while keeping leaves one stale row until the tab
    /// is next re-entered from scratch. So a tie is kept.
    ///
    /// **This paragraph used to end on a sentence that is now false, and this round's own change is
    /// what falsified it.** It said the tie was "already invisible to paging itself: the cursor
    /// asks for `captured_at < :cursor`, so page two never contained a row tying with page one's
    /// last." That was true, and it was true because of a defect: those rows were absent from page
    /// two because they were being dropped from the journal altogether
    /// (`JournalPaginationTieTests`, and this round's errata entry). v19's cursor carries
    /// `(captured_at, id)`, so page two now holds exactly the tie-mates page one did not fit.
    ///
    /// The reconciliation is unchanged by that and is still correct — but its weakest justification
    /// has become its strongest. A held row tying with `oldest` is now, in the ordinary case, a
    /// genuine page-two row rather than a transient, so a strict `<` here would drop real rows on
    /// every background refresh: the same defect a third time.
    /// `JournalModelLifetimeTests.aRefreshKeepsATieMateThatLivesOnPageTwo` is what makes that a
    /// test rather than this sentence.
    ///
    /// The cursor follows the same logic: if held rows survive, the list still runs down to the old
    /// tail and the old cursor is still the right place to ask from; if none do, the list is exactly
    /// the fresh page and so is its cursor.
    ///
    /// ── What a failure does ──────────────────────────────────────────────────────────────────
    /// Nothing. A background refresh the reader did not ask for must not take down a screen that is
    /// already showing them their journal, and it must not raise `hasFailedOlder` either — that
    /// flag is `Show earlier`'s, and this is not that. The list stays exactly as it was, which is
    /// the same reasoning the file comment gives for keeping the two failure kinds apart.
    private func refresh() async {
        guard case let .loaded(held, heldCursor) = phase, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        guard let fresh = try? await api.journal(cursor: nil, limit: JournalLimits.pageSize) else {
            return
        }

        guard let oldest = fresh.items.last?.capturedAt, fresh.nextCursor != nil else {
            // Case 2: the fresh page reached the end of the journal, so it is the whole of it.
            // Also the empty case — every contribution deleted — which is the same statement.
            setPhase(.loaded(entries: fresh.items, nextCursor: fresh.nextCursor))
            return
        }

        let freshIDs = Set(fresh.items.map(\.id))
        let kept = held.filter { !freshIDs.contains($0.id) && $0.capturedAt <= oldest }
        setPhase(.loaded(
            entries: fresh.items + kept,
            nextCursor: kept.isEmpty ? fresh.nextCursor : heldCursor
        ))
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

/// Holds `NotificationCenter` registrations and removes them when it is released.
///
/// One job, and it is a lifetime job: an observer registered with the block-based API outlives its
/// owner unless somebody removes it, and the natural place to remove it — the owner's `deinit` — is
/// a place a `@MainActor` type cannot safely touch its own stored properties from. This type has no
/// isolation, so its `deinit` is ordinary code, and a `let` of it on the owner ties the two
/// lifetimes together with nothing to remember.
final class NotificationBag {
    private var tokens: [any NSObjectProtocol] = []

    func add(_ token: any NSObjectProtocol) {
        tokens.append(token)
    }

    deinit {
        tokens.forEach(NotificationCenter.default.removeObserver)
    }
}
