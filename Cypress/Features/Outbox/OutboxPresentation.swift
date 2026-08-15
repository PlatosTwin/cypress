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
        /// `11:42 am`, carrying §2's `·` separator when something precedes it on the line.
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
        /// `✓ 9:56 am`.
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
        snapshot.items
            .filter { $0.state != .done }
            .map(row(for:))
    }

    private func row(for item: OutboxItemSnapshot) -> Row {
        let detail = OutboxCopy.detail(for: item)
        let quantity = measurementQuantity(item)
        let time = OutboxCopy.timeStamp(item.createdAt, calendar: calendar, locale: locale)
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
    /// is exactly what its heading claims and cannot quietly become a week.
    var syncedRows: [SyncedRow] {
        snapshot.items
            .filter { $0.state == .done }
            // Newest receipt first, as §4 lists them — and by when each one *went*, which is not the
            // FIFO order the queue drained in once a retry has reordered anything.
            .sorted { $0.updatedAt > $1.updatedAt }
            .map { item in
                SyncedRow(
                    id: item.id,
                    title: OutboxCopy.title(kind: item.kind, treeName: item.treeName),
                    // `updatedAt`, not `capturedAt`: the receipt stamps when it went, and an item
                    // that waited out a dead zone went at a different hour than it was taken.
                    timeText: OutboxCopy.syncedStamp(item.updatedAt, calendar: calendar, locale: locale)
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

    /// §2 names four of the six kinds. `Favorite` and `Reminder` are **NOT SPECIFIED** — no mocked
    /// row carries either — and are the plain nouns the rest of the app already uses for them.
    ///
    /// A private reminder deliberately names no hazard category here. D4 keeps hazards off every
    /// surface but the owner's own record, and a queue is a list, not that record.
    static func kindLabel(_ kind: OutboxItem.Kind) -> String {
        switch kind {
        case .visit: return "Visit"
        case .observation: return "Check-in"
        case .measurement: return "Measurement"
        case .careEvent: return "Care"
        case .favoriteToggle: return "Favorite"
        case .privateReminder: return "Reminder"
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

    /// §4's micro-label, verbatim.
    static let syncedLabel = "Synced earlier today"

    /// §4's trailing stamp — `✓ 9:56 am`.
    static func syncedStamp(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        "✓ " + timeStamp(date, calendar: calendar, locale: locale)
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

    /// `11:42 am`. Lower case, as §2 writes it.
    static func timeStamp(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("jmm")
        return formatter.string(from: date).lowercased(with: locale)
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
