//
//  OutboxView.swift
//  Cypress — Features/Outbox
//
//  Screen 17 · Outbox. SCREENS.md lines 1241–1280.
//
//  A pushed screen with its own C1 header and back circle, like 11, 12, 13 and 16.
//
//  Composed from C1 (header + amber trailing pill), C24 (the terminal row's amber card), C25 (the
//  wi-fi toggle), C21 (the leading tile's leaf) and C12 (a queued measurement's method badge). The
//  row card and the dimmed receipt have no C-number — §2 and §4 describe both inline — so they are
//  built here from tokens, as 13's photo strip was.
//
//  ── The model is `OutboxViewState`, and there is not a second one ─────────────────────────
//  ARCHITECTURE §3 asks for one `@Observable` model per feature folder. This feature's model already
//  existed before the screen did, in `Data/Outbox`, because the queue's own view state is what the
//  drain notifies and what the wi-fi preference is persisted through. Wrapping it in a second
//  observable object here would give the screen two places to hold the same toggle, and the toggle
//  is the one piece of state that must not drift: `awaitingWifiCount` is a statement about it
//  (ERRATA E32). So the view owns `OutboxViewState` directly via `@State`, and this file adds only
//  the derivation (`OutboxPresentation`) and the drawing.
//
//  Not a raw hex or a raw font size in the file (ARCHITECTURE §6).
//

import SwiftUI

struct OutboxView: View {

    @State private var state: OutboxViewState
    @Environment(AppRouter.self) private var router: AppRouter?

    private let now: () -> Date
    private let calendar: Calendar

    /// - Parameter state: built by the composition root (`DataLayer.makeOutboxViewState`), which is
    ///   where the queue, the preference store and the name resolver are already wired together.
    ///   The feature does not assemble its own services (ARCHITECTURE §3).
    init(
        state: @autoclosure () -> OutboxViewState,
        now: @escaping () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        _state = State(wrappedValue: state())
        self.now = now
        self.calendar = calendar
    }

    var body: some View {
        @Bindable var state = state

        OutboxScreen(
            presentation: OutboxPresentation(
                snapshot: state.snapshot,
                now: now(),
                calendar: calendar
            ),
            syncPhotosOnWifiOnly: $state.syncPhotosOnWifiOnly,
            refreshError: state.refreshError,
            onBack: { router?.pop() },
            onRetry: { id in Task { await self.state.retry(id: id) } }
        )
        .task {
            await state.start()
        }
    }
}

// MARK: - The screen itself

/// Screen 17's layout, given a finished derivation.
///
/// Split from `OutboxView` for the reason `ActivityScreen` is split from `ActivityView`: this
/// screen's states — an empty queue, a failed item, an expired one — arrive from an `async` read,
/// and a view that only has content after one renders as the loading state in a detached window.
/// With the split, any state can be handed straight in and looked at.
struct OutboxScreen: View {

    let presentation: OutboxPresentation
    @Binding var syncPhotosOnWifiOnly: Bool
    var refreshError: String?
    var onBack: (() -> Void)?
    var onRetry: ((UUID) -> Void)?

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    if let refreshError { readFailure(refreshError) }

                    if presentation.isQueueEmpty {
                        emptyQueue
                    } else {
                        queue
                    }

                    wifiRow
                    if let sentence = presentation.awaitingWifiSentence { awaitingWifi(sentence) }
                    syncedSection
                    if let summary = presentation.summaryLine { summaryLine(summary) }

                    // §6 carries no `margin-top:auto`, unlike 16's CTA, so the footnote follows the
                    // content rather than being pinned to the bottom of the frame. On an empty queue
                    // that keeps the screen's one promise next to its one sentence.
                    footnote
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: proxy.size.height, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CypressColor.surfaceScreen)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - §1 Header (C1)

    /// `title: Outbox`, trailing amber pill `3 waiting`. No pill when nothing is waiting.
    @ViewBuilder
    private var header: some View {
        if let pill = presentation.headerPill {
            ScreenHeader(
                title: OutboxCopy.screenTitle,
                trailingPill: pill,
                pillStyle: .amber,
                onBack: onBack
            )
        } else {
            ScreenHeader(title: OutboxCopy.screenTitle, onBack: onBack)
        }
    }

    // MARK: - §2 The queue

    private var queue: some View {
        VStack(spacing: OutboxMetrics.queueGap) {
            ForEach(presentation.queue) { row in
                OutboxQueueRow(row: row, onRetry: { onRetry?(row.id) })
            }
        }
        .padding(.top, OutboxMetrics.queueTop)
        .padding(.horizontal, CypressSpacing.gutter)
    }

    /// SCREENS.md §5 gap 5's `outbox with nothing queued`, and the state a contributor sees almost
    /// every time. See `OutboxCopy.emptyState`.
    private var emptyQueue: some View {
        Text(OutboxCopy.emptyState)
            .cypressBody135(color: CypressColor.textMuted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, CypressSpacing.labelSectionTop)
            .padding(.horizontal, CypressSpacing.gutterLabel)
    }

    // MARK: - §3 The wi-fi setting (C25)

    private var wifiRow: some View {
        HStack(spacing: OutboxMetrics.rowSpacing) {
            VStack(alignment: .leading, spacing: OutboxMetrics.rowTextGap) {
                Text(OutboxCopy.wifiTitle)
                    .font(CypressFont.body135Bold)
                    .foregroundStyle(CypressColor.textInk)
                Text(OutboxCopy.wifiSubtitle)
                    .font(CypressFont.body115)
                    .foregroundStyle(CypressColor.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            // Flipping this refreshes the snapshot, because `awaitingWifiCount` is a statement about
            // the toggle as much as about the rows (`OutboxViewState.syncPhotosOnWifiOnly`, E32).
            CypressToggle(isOn: $syncPhotosOnWifiOnly, accessibilityLabel: OutboxCopy.wifiTitle)
        }
        .padding(.vertical, OutboxMetrics.wifiPaddingV)
        .padding(.horizontal, OutboxMetrics.wifiPaddingH)
        .background {
            RoundedRectangle(cornerRadius: CypressRadius.cardSm, style: .continuous)
                .fill(CypressColor.surfaceCard)
        }
        .cypressBorder(CypressColor.borderCool, radius: CypressRadius.cardSm)
        .padding(.top, OutboxMetrics.wifiTop)
        .padding(.horizontal, CypressSpacing.gutter)
    }

    /// `The note is saved. 2 photos are waiting for wi-fi.` — the sentence the toggle above is
    /// currently making true.
    private func awaitingWifi(_ sentence: String) -> some View {
        Text(sentence)
            .cypressBody135(color: CypressColor.textMuted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, CypressSpacing.gapVitality)
            .padding(.horizontal, CypressSpacing.gutterLabel)
    }

    // MARK: - §4 Synced earlier today

    @ViewBuilder
    private var syncedSection: some View {
        let rows = presentation.syncedRows
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text(OutboxCopy.syncedLabel)
                    .cypressMicroLabel()
                    .padding(.bottom, CypressSpacing.gapVitality)

                VStack(spacing: OutboxMetrics.syncedGap) {
                    ForEach(rows) { row in
                        OutboxSyncedRow(row: row)
                    }
                }
                .opacity(OutboxMetrics.syncedOpacity)
            }
            .padding(.top, CypressSpacing.labelSectionTop)
            .padding(.horizontal, CypressSpacing.gutter)
        }
    }

    // MARK: - §5 Summary

    private func summaryLine(_ text: String) -> some View {
        Text(text)
            .font(CypressFont.mono11)
            .foregroundStyle(CypressColor.textFaint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, OutboxMetrics.summaryTop)
            .padding(.horizontal, CypressSpacing.gutter)
    }

    // MARK: - §6 Footnote

    private var footnote: some View {
        Text(OutboxCopy.footnote)
            .cypressBody135(color: CypressColor.textFaintAlt)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, OutboxMetrics.footnoteTop)
            .padding(.bottom, CypressSpacing.bottomFootnote)
            .padding(.horizontal, OutboxMetrics.footnoteGutter)
    }

    // MARK: - The state SCREENS.md does not draw

    /// Failing to *read* the outbox is a different problem from failing to *send* it, and this
    /// screen is the last place to conflate them (`OutboxViewState.refreshError`).
    private func readFailure(_ text: String) -> some View {
        Text(text)
            .cypressBody135(color: CypressColor.amberChipSelectedText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, CypressSpacing.labelSectionTop)
            .padding(.horizontal, CypressSpacing.gutterLabel)
    }
}

// MARK: - §2's row

/// One queued item.
///
/// A terminal row is a C24 attention card and a live one is a plain card, which is the whole of
/// "must not look like a transient one": the border, the tile and the state word all change
/// together, and only the terminal row carries a control.
struct OutboxQueueRow: View {

    let row: OutboxPresentation.Row
    var onRetry: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if row.isTerminal {
            AttentionCard(size: .compact) { content }
        } else {
            content
                .padding(.vertical, OutboxMetrics.rowPaddingV)
                .padding(.horizontal, OutboxMetrics.rowPaddingH)
                .background {
                    RoundedRectangle(cornerRadius: CypressRadius.cardSm, style: .continuous)
                        .fill(CypressColor.surfaceCard)
                }
                .cypressBorder(CypressColor.borderCool, radius: CypressRadius.cardSm)
        }
    }

    private var content: some View {
        // §2 draws the row as `[tile] [title / detail / reason] [state]`, three columns. That holds
        // while the middle column has room. At AX5 the state word takes most of the width on its
        // own — `waiting` in mono is wider than the phone's text column — and the title is left
        // wrapping two or three characters at a time down a 180 pt gutter.
        //
        // So above the accessibility sizes the state moves under the row it describes rather than
        // beside it. It is still the last thing in reading order, which is what §2's placement was
        // saying.
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: OutboxMetrics.rowTextGap) {
                    HStack(alignment: .top, spacing: OutboxMetrics.rowSpacing) {
                        tile
                        textColumn
                        Spacer(minLength: 0)
                    }
                    stateCorner
                }
            } else {
                HStack(alignment: .top, spacing: OutboxMetrics.rowSpacing) {
                    tile
                    textColumn
                    Spacer(minLength: 0)
                    stateCorner
                }
            }
        }
    }

    private var textColumn: some View {
        VStack(alignment: .leading, spacing: OutboxMetrics.rowTextGap) {
            Text(row.title)
                .font(CypressFont.body14)
                .foregroundStyle(CypressColor.textInk)
                .fixedSize(horizontal: false, vertical: true)

            // `DBH` · `31 cm` + `taped` · `11:03 am`, in §2's order. A queued number carries its
            // method here exactly as it does on 03 and 11 (D7).
            //
            // Three text pieces across a row that is already inset by a 38 pt tile and a state
            // word. At AX5 they were interleaving into each other — `2 phot / os, a / note`
            // running down the left with `11:42 am` overprinting it — because an `HStack` with
            // no wrapping and no spacer divides whatever is left between them. Stacked, each
            // piece keeps its own line. The `MeasuredValue` stays intact either way, which is
            // the part D7 cares about.
            detailLine

            // "says so, says why, and waits for you" (§6). The sentence is
            // `OutboxFailureReason`'s; this file never writes one.
            if let reason = row.reason {
                Text(reason)
                    .font(CypressFont.body12)
                    .foregroundStyle(
                        row.isTerminal ? CypressColor.amberChipSelectedText : CypressColor.textFaint
                    )
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var detailLine: some View {
        let detail = Group {
            if let detail = row.detail {
                Text(detail)
                    .font(CypressFont.body12)
                    .foregroundStyle(CypressColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let quantity = row.quantity {
                MeasuredValue(quantity: quantity, font: CypressFont.mono12)
            }
            Text(row.timeText)
                .font(CypressFont.body12)
                .foregroundStyle(CypressColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: OutboxMetrics.rowTextGap) { detail }
        } else {
            HStack(spacing: CypressSpacing.gapVitality) { detail }
        }
    }

    /// §2: leading tile 38×38, radius 10. The measurement row draws its reading in mono inside the
    /// tile, as the mock does; every other kind takes C21's leaf, which is the only mark the
    /// catalog carries. §2's camera and ring glyphs are not in C1–C30 and are not invented here.
    private var tile: some View {
        RoundedRectangle(cornerRadius: CypressRadius.thumbSmAlt, style: .continuous)
            .fill(row.isTerminal ? CypressColor.amberPillFill : CypressColor.cityRecordBadgeFill)
            .frame(width: OutboxMetrics.tile, height: OutboxMetrics.tile)
            .overlay {
                switch row.tile {
                case .leaf:
                    LeafGlyph(
                        size: OutboxMetrics.tile / 2,
                        tint: row.isTerminal ? CypressColor.amberPillText : CypressColor.canopy
                    )
                case let .value(text):
                    Text(text)
                        .font(CypressFont.mono12SemiBold)
                        .foregroundStyle(
                            row.isTerminal ? CypressColor.amberPillText : CypressColor.tapedBadgeText
                        )
                        // The reading inside a 38 pt tile is a mark, not a sentence, and the tile
                        // is sized by §2 rather than by its contents. `minimumScaleFactor` alone
                        // was not enough: without a line limit the text wraps to two lines inside
                        // 38 pt *before* it ever tries to scale, and two lines do not fit either.
                        // The row's own detail line carries the same value in full, unclamped, so
                        // nothing is lost by holding this one to the tile.
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, CypressSpacing.Component.hairlineStrong)
                }
            }
            .accessibilityHidden(true)
    }

    /// §2's trailing state word. `retry` is the drawn one and is a control (BUILD-PLAN §4: "cap 48 h
    /// then state failed with a visible retry button"); `stopped` is not, because retrying a
    /// non-retryable code promises an outcome the taxonomy says will not change.
    /// The state word is one short mono token — `waiting`, `stopped`, `retry` — and it belongs at
    /// the end of the row, not wrapped down the side of it. At AX5 `waiting` broke to `waiti / ng`
    /// in the corner while the title wrapped underneath it, so it is held to one line: it is a
    /// status token in the row's furniture, and the row's own reason sentence below says the same
    /// thing in prose when there is more to say.
    @ViewBuilder
    private var stateCorner: some View {
        stateWord.lineLimit(1).fixedSize()
    }

    /// **The amber the two terminal words are drawn in, and why it is not Signal Amber.**
    ///
    /// `retry` and `stopped` are mono **11 pt bold** on `surface.card`. 11 pt bold is not WCAG
    /// "large text" — that exemption starts at 14 pt bold — so the pair takes the 4.5 floor, and
    /// `accentAmber` `#B4711F` reads **3.95:1** there (3.63 on the screen). Nothing was watching:
    /// `ContrastTests` pins `accentAmber` as a *map pin* against map paper, where the 3.0 non-text
    /// floor is the right one.
    ///
    /// The closure is a call site rather than a token. `accentAmber` is Signal Amber, a brand hue
    /// with a reserved meaning (§1.1) that also draws the amber map pin; retinting it to clear a
    /// text floor would move a mark on a screen nobody asked about. `amberChipSelectedText`
    /// `#8A5A17` is **5.91:1** on the card and is already what the reason line directly beneath
    /// this word uses, so the two terminal lines now read as one voice. Dark is unchanged — both
    /// tokens resolve to `#D99A4E` there, at 6.57:1.
    private var terminalStateWordColor: Color { CypressColor.amberChipSelectedText }

    @ViewBuilder
    private var stateWord: some View {
        switch row.state {
        case .waiting:
            Text(row.state.rawValue)
                .font(CypressFont.mono11SemiBold)
                .foregroundStyle(CypressColor.textFaint)
        case .stopped:
            Text(row.state.rawValue)
                .font(CypressFont.mono11Bold)
                .foregroundStyle(terminalStateWordColor)
        case .retry:
            Button { onRetry?() } label: {
                Text(row.state.rawValue)
                    .font(CypressFont.mono11Bold)
                    .foregroundStyle(terminalStateWordColor)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .cypressHitArea()
            .accessibilityLabel(OutboxCopy.retryAction)
        }
    }
}

// MARK: - §4's receipt

/// One dimmed `Synced earlier today` row: bold title, trailing mono check and time.
struct OutboxSyncedRow: View {

    let row: OutboxPresentation.SyncedRow

    var body: some View {
        HStack(spacing: OutboxMetrics.rowSpacing) {
            Text(row.title)
                .font(CypressFont.body13Bold)
                .foregroundStyle(CypressColor.textInk)
            Spacer(minLength: 0)
            Text(row.timeText)
                .font(CypressFont.mono11SemiBold)
                .foregroundStyle(CypressColor.tapedBadgeText)
        }
        .padding(.vertical, OutboxMetrics.syncedRowPaddingV)
        .padding(.horizontal, OutboxMetrics.syncedRowPaddingH)
        .background {
            RoundedRectangle(cornerRadius: CypressRadius.control, style: .continuous)
                .fill(CypressColor.surfaceCard)
        }
        .cypressBorder(CypressColor.borderCool, radius: CypressRadius.control)
    }
}
