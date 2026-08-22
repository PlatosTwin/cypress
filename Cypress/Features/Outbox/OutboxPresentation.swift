//
//  OutboxPresentation.swift
//  Cypress — Features/Outbox
//
//  Screen 17 · Outbox. SCREENS.md lines 1241–1280.
//
//  "Unsent field work gets a real screen, not a toast." Everything below turns one `OutboxSnapshot`
//  into what that screen draws, and every judgment in it is about whether a sentence is true.
//
//  ── 1. The footnote is the contract ───────────────────────────────────────────────────────
//  §6: "Nothing here disappears silently. An item that cannot sync says so, says why, and waits for
//  you." `OutboxFailureReason` already writes the "says why" line for every failure path, so this
//  file never authors one — it decides which rows carry theirs and how a terminal row is told from a
//  transient one.
//
//  ── 2. Terminal is not transient ─────────────────────────────────────────────────────────
//  BUILD-PLAN §4's schedule is "30 s, 2 m, 10 m, 1 h, then hourly; cap 48 h then state failed with a
//  visible retry button (screen 17)". `OutboxItem.State.failed` is that terminal state and is the
//  only one `OutboxItemSnapshot.showsRetryAffordance` admits — a row that has failed four times and
//  is still inside the window is `pending` and still reads `waiting`, because it is still trying.
//  The terminal row is the amber C24 card, and it is the only row with a control on it.
//
//  ── 3. Never "sent to the city" ──────────────────────────────────────────────────────────
//  ARCHITECTURE §5.4. Nothing in `OutboxCopy` says an authority was told anything: `synced` here
//  means the row reached this app's own API, and the strings say "sent" of the item and never of a
//  recipient.
//
//  ── 4. Counts ───────────────────────────────────────────────────────────────────────────
//  `OutboxStore.allItems` has no `LIMIT`, so this screen's counts are counts of the whole queue and
//  not of a page (ERRATA E38). The ones that would be zero are absent instead (ARCHITECTURE §5.6).
//
//  No SwiftUI in this file.
//

import Foundation

struct OutboxPresentation {

    /// The word in a row's trailing corner. Both are drawn by §2, and there is no third.
    ///
    /// **A third case, `stopped`, stood here until the owner's ruling 3 of 2026-08-14.** It was
    /// ERRATA E83's answer to `failed` meaning two things — the 48 h cap ran out, or the service
    /// refused with a code that will not change — and it drew the second as its own amber word with
    /// no control. The ruling folds that state back into this one: SCREENS.md 17's "States drawn"
    /// line names `waiting`, `retry` and `synced`, and a fourth drawn state is not the owner's
    /// design. What tells the two apart is the row's own sentence and nothing else, which is why
    /// the control is *not* withheld from a refused row either — withholding it would put the
    /// distinction back on the row's furniture, which is the thing the ruling removed.
    enum RowState: String {
        /// Still trying, whether or not it has failed before.
        case waiting
        /// Terminal: the 48 h cap ran out, or the service refused it outright. §2's amber state.
        case retry
    }

    /// What the 38pt leading tile holds.
    enum Tile: Equatable {
        /// C21's leaf, the app's only bespoke mark.
        case leaf
        /// §2's third row draws the reading itself in mono inside the tile.
        case value(String)
    }

    /// One queued row.
    struct Row: Identifiable, Equatable {
        let id: UUID
        /// `Visit · Grandmother Cypress`.
        let title: String
        /// `2 photos` / `vitality 3, thinning` / `DBH` — what the queued mutation says, or nil when
        /// it says nothing beyond its kind.
        let detail: String?
        /// The measured value, when the row is a measurement. Rendered by `MeasuredValue`, which
        /// cannot print a number without its C12 badge (D7). It follows `detail` and precedes the
        /// time, which is the order §2 draws: `DBH 31 cm, tape · upload failed twice`.
        let quantity: Quantity?
        /// `11:42 am` — or `Aug 19` once this list spans days (`OutboxCopy.stamp`) — carrying §2's
        /// `·` separator when something precedes it on the line.
        let timeText: String
        /// `OutboxFailureReason`'s sentence, or nil when there is nothing to explain.
        let reason: String?
        let state: RowState
        let tile: Tile
        /// Terminal rows take C24's amber card. A row inside its retry window does not, however many
        /// times it has failed.
        var isTerminal: Bool { state != .waiting }
        /// Every terminal row gets the control (BUILD-PLAN §4 attaches it to `failed`, and the
        /// owner's ruling 3 of 2026-08-14 keeps a refused row in that same failed row).
        var showsRetryButton: Bool { state == .retry }
    }

    /// One dimmed receipt in §4's `Synced earlier today`.
    struct SyncedRow: Identifiable, Equatable {
        let id: UUID
        /// `Visit · Ginkgo on Noriega`.
        let title: String
        /// `✓ 9:56 am`, or `✓ Aug 19` once this section spans days (`OutboxCopy.stamp`).
        let timeText: String
    }

    let snapshot: OutboxSnapshot
    private let now: Date
    private let calendar: Calendar
    private let locale: Locale

    init(
        snapshot: OutboxSnapshot,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current
    ) {
        self.snapshot = snapshot
        self.now = now
        self.calendar = calendar
        self.locale = locale
    }

    // MARK: - §1 Header pill

    /// `3 waiting`, or nil.
    ///
    /// **The mock's second clause is dropped.** §1 draws `3 waiting · offline`, and nothing in this
    /// app knows whether it is offline: there is no reachability monitor, and a failure sentence
    /// reading "No connection." is a record of the last attempt rather than a statement about now.
    /// Printing `offline` beside a live connection would be the same class of untrue label as
    /// "sent to the city" (ARCHITECTURE §5.4). See ERRATA.
    ///
    /// Absent at zero, because `0 waiting` is the zero ARCHITECTURE §5.6 does not draw.
    var headerPill: String? {
        guard snapshot.waitingCount > 0 else { return nil }
        return OutboxCopy.waitingPill(count: snapshot.waitingCount)
    }

    // MARK: - §2 The queue

    /// Everything not yet sent, oldest first, exactly as the store returns it.
    ///
    /// FIFO is the order the queue drains in, so it is the order the screen shows: a row above
    /// another row will be attempted before it.
    var queue: [Row] {
        let items = snapshot.items.filter { $0.state != .done }
        // Asked once for the whole list, not once per row: it is a property of the *list* (see
        // `OutboxCopy.stamp`), and a per-row call would walk every row for every row.
        let spansDays = OutboxCopy.spansMoreThanOneDay(items.map(\.createdAt), calendar: calendar)
        return items.map { row(for: $0, spansDays: spansDays) }
    }

    private func row(for item: OutboxItemSnapshot, spansDays: Bool) -> Row {
        let detail = OutboxCopy.detail(for: item)
        let quantity = measurementQuantity(item)
        let time = OutboxCopy.stamp(
            item.createdAt,
            spansDays: spansDays,
            now: now,
            calendar: calendar,
            locale: locale
        )
        return Row(
            id: item.id,
            title: OutboxCopy.title(kind: item.kind, treeName: item.treeName),
            detail: detail,
            quantity: quantity,
            // A row whose mutation says nothing beyond its kind carries the time alone, rather than
            // a separator with nothing on the other side of it.
            timeText: detail == nil && quantity == nil ? time : OutboxCopy.metaSeparator + time,
            reason: reason(for: item),
            state: state(for: item),
            tile: tile(for: item)
        )
    }

    /// The "says why" line, or nil.
    ///
    /// **Waiting for wi-fi is not a failure**, and it is the one sentence this screen says twice.
    /// `OutboxQueue.drain` writes it into `lastError` because that column is the only place a
    /// rescheduled row can carry a note, but the row already says `3 photos` and `waiting`, and the
    /// same sentence belongs under the toggle that is causing it (`awaitingWifiSentence`). Printing
    /// it in both places on a queue of one is the screen telling somebody the same thing twice.
    private func reason(for item: OutboxItemSnapshot) -> String? {
        guard let reason = item.reason else { return nil }
        return reason == OutboxFailureReason.awaitingWifi(photoCount: item.photoCount) ? nil : reason
    }

    /// `waiting` / `retry`.
    ///
    /// `OutboxRetryPolicy.nextState` still produces `failed` for two different reasons — the 48 h
    /// cap ran out, or the API returned a code that is not retryable — and this screen no longer
    /// draws them apart. That is the owner's ruling 3 of 2026-08-14, overruling ERRATA E83's
    /// `stopped`: the two terminal reasons share the failed row, and the only thing that separates
    /// them is the sentence `OutboxFailureReason.describe` wrote into `lastError`
    /// (`refusedTerminally` against `expired`). `errorCode` is still carried on the snapshot and is
    /// still what the sentence was chosen by; it is simply not read here any more.
    private func state(for item: OutboxItemSnapshot) -> RowState {
        item.state == .failed ? .retry : .waiting
    }

    private func tile(for item: OutboxItemSnapshot) -> Tile {
        guard let quantity = measurementQuantity(item) else { return .leaf }
        return .value(MeasuredValue.number(quantity.value))
    }

    private func measurementQuantity(_ item: OutboxItemSnapshot) -> Quantity? {
        guard case let .measurement(measurement)? = item.payload else { return nil }
        return measurement.quantity
    }

    /// Nothing is queued. **NOT SPECIFIED**, and named as a required decision by SCREENS.md §5
    /// gap 5 ("empty states for: outbox with nothing queued"). It is also the state a contributor
    /// sees almost every time they open this screen.
    var isQueueEmpty: Bool { queue.isEmpty }

    // MARK: - §3 The wi-fi row

    /// `The note is saved. 2 photos are waiting for wi-fi.`, or nil.
    ///
    /// Every clause of that sentence is a condition on the count behind it: the JSON really was
    /// accepted, binaries really are still on the device, the row is still alive rather than given
    /// up on, and the toggle really is what is holding them (ERRATA E32). The number is
    /// `awaitingWifiPhotoCount` and not `awaitingWifiCount` because the sentence says *photos* and
    /// the latter counts items.
    var awaitingWifiSentence: String? {
        guard snapshot.awaitingWifiCount > 0 else { return nil }
        return OutboxFailureReason.awaitingWifi(photoCount: snapshot.awaitingWifiPhotoCount)
    }

    // MARK: - §4 Synced earlier today

    /// The receipts, newest first.
    ///
    /// `OutboxQueue.completedRetention` is 24 h and `pruneCompleted` sweeps past it, so this section
    /// can never become a week — **but 24 h of retention spans two calendar days for most of the
    /// day**, and this line used to argue from the first fact that the section "is exactly what its
    /// heading claims". It is not: the two-day case is precisely the one that flips the stamps to
    /// dates, and it is common rather than exotic (PR #102 review). The heading asks the same
    /// question and answers it the same way — see `syncedHeading`.
    private var syncedItems: [OutboxItemSnapshot] {
        snapshot.items
            .filter { $0.state == .done }
            // Newest receipt first, as §4 lists them — and by when each one *went*, which is not the
            // FIFO order the queue drained in once a retry has reordered anything.
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// This section's own span, and not the queue's. They are two lists under two headings, and the
    /// question `stamp` answers — "can a reader tell these rows apart by their stamps" — is asked of
    /// the rows a reader is looking at. See `OutboxCopy.stamp`.
    private var syncedSpansDays: Bool {
        OutboxCopy.spansMoreThanOneDay(syncedItems.map(\.updatedAt), calendar: calendar)
    }

    /// §4's heading, for the list actually under it.
    ///
    /// One `spansDays` answer drives the heading and every stamp beneath it, so the screen cannot
    /// say `Synced earlier today` over a row stamped `Jan 14` — which it could, and which is what
    /// the original report was half about. See `OutboxCopy.syncedLabel(spansDays:)`.
    var syncedHeading: String {
        OutboxCopy.syncedLabel(spansDays: syncedSpansDays)
    }

    var syncedRows: [SyncedRow] {
        let items = syncedItems
        let spansDays = syncedSpansDays
        return items.map { item in
            SyncedRow(
                id: item.id,
                title: OutboxCopy.title(kind: item.kind, treeName: item.treeName),
                // `updatedAt`, not `capturedAt`: the receipt stamps when it went, and an item
                // that waited out a dead zone went at a different hour than it was taken.
                timeText: OutboxCopy.syncedStamp(
                    item.updatedAt,
                    spansDays: spansDays,
                    now: now,
                    calendar: calendar,
                    locale: locale
                )
            )
        }
    }

    // MARK: - §5 Summary line

    /// `today · 14 synced · 0 lost`, or nil.
    ///
    /// **The mock's window is not the one the app keeps.** §5 draws `this week · 14 synced · 0
    /// lost`, and a `done` row is swept after `OutboxQueue.completedRetention`, which is one day. A
    /// week's figure is not a number this app has, so the line says the window it can actually
    /// answer for. `0 lost` is computed rather than asserted, which is why it is worth printing.
    /// Absent when nothing has gone today, because `0 synced` is a zero (ARCHITECTURE §5.6).
    ///
    /// §5's trailing `full history` link is **not rendered**: there is no history screen and no
    /// route to one, and printing a control that goes nowhere is the same small broken promise
    /// ERRATA E64 removed from screen 11.
    var summaryLine: String? {
        guard snapshot.syncedRecentlyCount > 0 else { return nil }
        return OutboxCopy.summary(sent: snapshot.syncedRecentlyCount, lost: snapshot.lostCount)
    }

    // MARK: - The whole screen

    /// Nothing queued and nothing sent today. The wi-fi row still draws: it is a preference, and a
    /// preference is true whether or not anything is waiting on it.
    var isEmpty: Bool { snapshot.items.isEmpty }
}

// MARK: - Copy

/// Screen 17's strings, verbatim from SCREENS.md 17 unless a clause is deliberately dropped and says
/// so. Nothing here claims an authority was notified (ARCHITECTURE §5.4), and no sentence uses a
/// spaced em dash (§5.7).
enum OutboxCopy {

    /// §1's header title.
    static let screenTitle = "Outbox"

    /// §1's amber pill, minus its `offline` clause. See `OutboxPresentation.headerPill`.
    static func waitingPill(count: Int) -> String { "\(count) waiting" }

    /// §2's row titles — `Visit · Grandmother Cypress`.
    ///
    /// The tree falls back to `TreeProfilePresentation.fallbackTitle`, the same word every other
    /// surface uses for a tree with no name in hand, rather than to a blank half-title.
    static func title(kind: OutboxItem.Kind, treeName: String?) -> String {
        "\(kindLabel(kind)) · \(treeName ?? TreeProfilePresentation.fallbackTitle)"
    }

    /// §2 names four of the six kinds it was written against. `Favorite` and `Reminder` are **NOT
    /// SPECIFIED** — no mocked row carries either — and are the plain nouns the rest of the app
    /// already uses for them.
    ///
    /// A private reminder deliberately names no hazard category here. D4 keeps hazards off every
    /// surface but the owner's own record, and a queue is a list, not that record.
    ///
    /// **Spec §3.4's ten are unspecified in the same way and are handled the same way**, which is
    /// the precedent above rather than a new decision: each is the noun the screen that captured it
    /// already uses (`TreeProfileCopy.correctSpeciesAction`, `reportSpeciesAction`,
    /// `reportNeverExistedAction`), shortened to a label. Nothing here invents a civic or botanical
    /// fact, and the hazard row names no category for the reason the reminder row does not.
    static func kindLabel(_ kind: OutboxItem.Kind) -> String {
        switch kind {
        case .visit: return "Visit"
        case .observation: return "Check-in"
        case .measurement: return "Measurement"
        case .careEvent: return "Care"
        case .favoriteToggle: return "Favorite"
        case .privateReminder: return "Reminder"
        case .addTree: return "New tree"
        case .speciesClaim: return "Species"
        case .speciesCorrection: return "Species correction"
        case .wrongSpeciesReport: return "Species report"
        case .neverExistedReport: return "Record report"
        case .speciesReviewDismissal: return "Species review"
        case .recordReviewDismissal: return "Record review"
        case .photoVote: return "Photo vote"
        case .photoWithdrawal: return "Photo removed"
        case .hazardRedirect: return "Hazard redirect"
        }
    }

    /// What the queued mutation says, in the vocabulary the screen that captured it used.
    ///
    /// §2's sub-line is `2 photos · 11:42 am`, `vitality 3, thinning · 11:18 am`,
    /// `DBH 31 cm, tape · …`. The mock's third row spells its method into the string; here the
    /// method is drawn as its C12 badge instead, because that is how every other surface in the app
    /// renders a number and its method together (D7, `MeasuredValue`).
    static func detail(for item: OutboxItemSnapshot) -> String? {
        switch item.payload {
        case let .visit(visit):
            var parts: [String] = []
            if item.photoCount > 0 { parts.append(photoCount(item.photoCount)) }
            if visit.note?.isEmpty == false { parts.append("a note") }
            return parts.isEmpty ? nil : parts.joined(separator: ", ")

        case let .observation(observation):
            var parts: [String] = []
            if let vitality = observation.vitality { parts.append("vitality \(vitality.rawValue)") }
            if let density = observation.foliage?.density {
                parts.append(FoliageDensityLabel.text(for: density).lowercased())
            }
            parts.append(contentsOf: observation.structureFlags.map {
                StructureFlagLabel.text(for: $0).lowercased()
            })
            return parts.isEmpty ? nil : parts.joined(separator: ", ")

        case let .measurement(measurement):
            // The value itself is drawn by `MeasuredValue`, which cannot print a number without its
            // badge; this is only the label in front of it.
            return kindLabel(measurement.kind)

        case let .careEvent(event):
            let actions = event.actions.map { CareActionLabel.text(for: $0).lowercased() }
            return actions.isEmpty ? nil : actions.joined(separator: ", ")

        case let .favoriteToggle(toggle):
            return toggle.isFavorite ? "favorited" : "no longer a favorite"

        case .privateReminder:
            return "private to you"

        // ── §3.4's ten carry no sub-line, and that is a refusal rather than a gap ─────────────
        //
        // §2 specifies a sub-line for three kinds and the row reads `<Kind> · <Tree> · <time>`
        // without one. Every clause that could go here would be invented: a species name the mock
        // never asked for, a reason a dismissal does not record, a thumb direction, a hazard
        // category D4 keeps off every surface but the owner's own record. DECISIONS constraint 21
        // makes that a stop-and-ask, and the kind label already says what the person did.
        case .addTree, .speciesClaim, .speciesCorrection, .wrongSpeciesReport, .neverExistedReport,
             .speciesReviewDismissal, .recordReviewDismissal, .photoVote, .photoWithdrawal,
             .hazardRedirect:
            return nil

        case nil:
            return nil
        }
    }

    /// `DBH` / `Height`, matching screen 11's own labels for the two kinds.
    static func kindLabel(_ kind: MeasurementKind) -> String {
        switch kind {
        case .dbh: return "DBH"
        case .height: return "Height"
        }
    }

    static func photoCount(_ count: Int) -> String {
        count == 1 ? "1 photo" : "\(count) photos"
    }

    /// §2's ` · ` between the sub-line's clauses. A middle dot, never an em dash (ARCHITECTURE §5.7).
    /// It carries its own spaces because the clauses either side of it are separate views — one of
    /// them is a `MeasuredValue` — and a layout gap is not a separator.
    static let metaSeparator = " · "

    /// §3's two lines, verbatim.
    static let wifiTitle = "Sync photos on wifi only"
    static let wifiSubtitle = "Notes and numbers sync on any connection"

    /// §4's micro-label, verbatim — **for the list it is true of.**
    static let syncedLabel = "Synced earlier today"

    /// The same label for a synced list that reaches back past today.
    ///
    /// **NOT SPECIFIED**, and the implementation's choice — recorded in `docs/RULINGS.md` once
    /// the orchestrator splices this branch's pending entry under its real number at merge.
    /// The owner ruled the *stamps*, in response to a report that the stamps and this heading
    /// disagreed; fixing only the stamps left the screen able to draw `Synced earlier today` over a
    /// row stamped `Jan 14`, which is the same contradiction from the other side (PR #102 review).
    ///
    /// It says less rather than saying something new: `Recently synced` makes no claim about a day,
    /// which is the only thing wrong with the other string here. That is the move §5's summary line
    /// already made when it replaced the mock's `this week` with `today` — a heading may only name a
    /// window the app can actually answer for.
    static let syncedSpanningLabel = "Recently synced"

    /// Which of the two the section's own list has earned. Asked with the same `spansDays` the
    /// stamps in it are asked with, so the heading and the rows under it cannot disagree — which is
    /// the whole point, and was the defect.
    static func syncedLabel(spansDays: Bool) -> String {
        spansDays ? syncedSpanningLabel : syncedLabel
    }

    /// §4's trailing stamp — `✓ 9:56 am`, or `✓ Aug 19` on a list that spans days. See `stamp`.
    static func syncedStamp(
        _ date: Date,
        spansDays: Bool,
        now: Date,
        calendar: Calendar,
        locale: Locale
    ) -> String {
        "✓ " + stamp(date, spansDays: spansDays, now: now, calendar: calendar, locale: locale)
    }

    /// §5's summary, with the mock's own words and its own window replaced by the one the store
    /// keeps. See `OutboxPresentation.summaryLine`.
    static func summary(sent: Int, lost: Int) -> String {
        "today · \(sent) synced · \(lost) lost"
    }

    /// §6's footnote, verbatim.
    static let footnote =
        "Nothing here disappears silently. An item that cannot sync says so, says why, and waits for you."

    /// **NOT SPECIFIED**, and named as a required decision by SCREENS.md §5 gap 5. Written in the
    /// shape every other empty state in this app uses: state the fact, draw nothing else. The
    /// footnote above it is the rest of the answer.
    static let emptyState = "Nothing is waiting to send."

    /// The retry control's label, from §2's drawn state word.
    static let retryAction = "Retry"

    /// What a row's trailing stamp says: `11:42 am`, or `Aug 19` once the list it is in spans more
    /// than one day.
    ///
    /// ── **The report, and the rule** ──────────────────────────────────────────────────────────
    ///
    /// Reported from the field: the synced receipts read `1:49 pm` on a list whose rows were taken
    /// on different days, so two stamps an hour apart on the screen were a day apart in fact, and
    /// nothing drawn said so. **The owner ruled it on 2026-08-21 (RULINGS R80, item 3)**: show the
    /// date instead of the time once the list spans more than one day, otherwise the time. This
    /// function is that rule, and `spansDays` is the question its caller has already answered about
    /// the whole list.
    ///
    /// It is a property of the *list* and not of the row, which is what makes it right. A per-row
    /// "is this today" test would print `Aug 19` beside `1:49 pm` and leave the reader comparing two
    /// kinds of thing; one answer for one list means every stamp in it is the same kind of fact and
    /// they can be read against each other. `OutboxPresentation` asks it once per section, over that
    /// section's own dates.
    ///
    /// ── **Why the year appears and usually does not** ─────────────────────────────────────────
    ///
    /// `Aug 19` is unambiguous inside a list that cannot reach back a year, and the synced section
    /// cannot: `OutboxQueue.completedRetention` sweeps it at 24 h. The **queue** has no such sweep —
    /// a terminally failed row waits for a tap and waits as long as it takes — so a queue really can
    /// hold two rows whose `Aug 19`s are twelve months apart. A stamp carries its year when it is
    /// not in `now`'s year, which costs nothing in the ordinary case and stops the one case where
    /// the rule would replace an ambiguity with a different ambiguity.
    static func stamp(
        _ date: Date,
        spansDays: Bool,
        now: Date,
        calendar: Calendar,
        locale: Locale
    ) -> String {
        guard spansDays else { return timeStamp(date, calendar: calendar, locale: locale) }
        return dateStamp(date, now: now, calendar: calendar, locale: locale)
    }

    /// Whether these dates fall on more than one calendar day, in the reader's own calendar and
    /// time zone. An empty list and a one-row list both span one day and take the time.
    ///
    /// The set is of `startOfDay`, not of a day-of-year number: two dates eleven months apart can
    /// share a day-of-month, and a `dateComponents` difference of "1 day" is a duration rather than
    /// a boundary crossing — 11 pm and 1 am are two hours apart and two days.
    static func spansMoreThanOneDay(_ dates: [Date], calendar: Calendar) -> Bool {
        guard let first = dates.first else { return false }
        let day = calendar.startOfDay(for: first)
        return dates.contains { calendar.startOfDay(for: $0) != day }
    }

    /// `11:42 am`. Lower case, as §2 writes it.
    static func timeStamp(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("jmm")
        return formatter.string(from: date).lowercased(with: locale)
    }

    /// `Aug 19`, or `Aug 19, 2025` outside `now`'s year. See `stamp` for both halves of that.
    ///
    /// **Not lower-cased**, unlike `timeStamp` beside it. That call exists because §2 draws `11:42
    /// am` rather than `11:42 AM` — it is fixing the *meridiem*, which is the only thing in a time
    /// that a formatter capitalizes against the mock. A month is a proper noun in English and
    /// `aug 19` is a misspelling, not a house style.
    static func dateStamp(_ date: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        formatter.setLocalizedDateFormatFromTemplate(sameYear ? "MMMd" : "yMMMd")
        return formatter.string(from: date)
    }
}

// MARK: - Screen metrics

/// The geometry SCREENS.md 17 gives this screen that the design system does not already name.
enum OutboxMetrics {
    /// §2: `padding:12px 16px 0`, `VStack(spacing:8)`.
    static let queueTop: CGFloat = 12
    static let queueGap: CGFloat = CypressSpacing.gapRows
    /// §2: rows are `padding:13px 14px`, `gap:12px`, leading tile 38×38 radius 10.
    static let rowPaddingV: CGFloat = 13
    static let rowPaddingH: CGFloat = 14
    static let rowSpacing: CGFloat = 12
    static let tile: CGFloat = CypressSpacing.Component.thumb38
    /// §2: `sub margin-top:1px`.
    static let rowTextGap: CGFloat = 1
    /// §3: `margin:10px 16px 0`, `padding:13px 15px`, `gap:12px`.
    static let wifiTop: CGFloat = 10
    static let wifiPaddingV: CGFloat = 13
    static let wifiPaddingH: CGFloat = 15
    /// §4: `VStack(spacing:7)` at `opacity:.65`, rows `padding:10px 13px`.
    static let syncedGap: CGFloat = CypressSpacing.gapDense
    static let syncedOpacity: Double = 0.65
    static let syncedRowPaddingV: CGFloat = 10
    static let syncedRowPaddingH: CGFloat = 13
    /// §5: `margin-top:9px`.
    static let summaryTop: CGFloat = 9
    /// §6: `padding:16px 24px 36px`.
    static let footnoteTop: CGFloat = 16
    static let footnoteGutter: CGFloat = 24
}
