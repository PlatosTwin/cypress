//
//  JournalListView.swift
//  Cypress — Features/Journal
//
//  The contributions journal, drawn. **NOT SPECIFIED** — the argument for what it is allowed to be
//  is in `JournalPresentation`, which is also where E38 and D1 are enforced.
//
//  ── One list, two doors ───────────────────────────────────────────────────────────────────────
//  This view is mounted twice: as the `Yours` segment of the `Journal` tab, and behind screen 08's
//  `Journal` pill. Both are places the design itself names — C16's bar draws a `Journal` tab and
//  SCREENS.md 08 §2 draws a `Journal` pill — and a person who taps either is asking the same
//  question about the same records.
//
//  An earlier round proposed cutting the pill instead, on the grounds that "two surfaces showing one
//  record have to agree forever, and the first time they did not, one of them would be lying to
//  somebody about what they had done." That objection is correct and it is answered here
//  structurally rather than by discipline: there is one derivation, one model and one view, so the
//  two mount points cannot come to disagree — there is no second implementation to drift. Cutting a
//  drawn control would have been the larger invention of the two.
//
//  No chrome of its own: no header, no tab bar, no scroll view. Each host already owns those, and a
//  list that brought its own would nest a scroll view inside one. It draws a column and stops.
//
//  Not a raw hex or a raw font size in the file (ARCHITECTURE §6).
//

import SwiftUI

struct JournalListView: View {

    let presentation: JournalPresentation?
    /// Whether the *first* read failed, as opposed to returning nothing (ERRATA E126). The two are
    /// different sentences and were once the same blank column.
    var hasFailed = false
    /// Whether the last `Show earlier` failed. Independent of `hasFailed`; see `JournalModel`.
    var hasFailedOlder = false
    var isLoadingOlder = false

    var onOpenTree: ((UUID) -> Void)?
    var onRetry: (() -> Void)?
    var onShowOlder: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if hasFailed {
                failure
            } else if let presentation {
                if let empty = presentation.emptyState {
                    // The same card the grove's empty pill draws, so the app has one shape for "a
                    // sentence where a list would be" rather than one per screen.
                    GroveNote(empty)
                } else {
                    rows(presentation)
                    olderBlock(presentation)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, JournalMetrics.listTop)
        .padding(.horizontal, CypressSpacing.gutter)
    }

    // MARK: - The rows

    private func rows(_ presentation: JournalPresentation) -> some View {
        VStack(spacing: JournalMetrics.rowGap) {
            ForEach(presentation.rows) { row in
                IconTextRow(
                    accent: row.accent,
                    title: row.title,
                    subtitle: row.subtitle,
                    // Every row is about a tree, so every row has somewhere to go. Nil only when the
                    // host supplies no destination, in which case C10 draws a card rather than a
                    // button — a control that looked pressable and did nothing is the thing this
                    // whole round is about.
                    action: onOpenTree.map { open in { open(row.treeID) } }
                )
            }
        }
    }

    // MARK: - The end of the page (ERRATA E38)

    /// The sentence about there being older entries, and the control that fetches them.
    ///
    /// Both are absent when the read reached the end, which is the honest drawing of a finished
    /// list: nothing here apologises for rows that do not exist, and nothing states or implies how
    /// many there are.
    @ViewBuilder
    private func olderBlock(_ presentation: JournalPresentation) -> some View {
        if let older = presentation.olderNote {
            VStack(alignment: .leading, spacing: CypressSpacing.gapRows) {
                Text(older)
                    .font(CypressFont.body12)
                    .foregroundStyle(CypressColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)

                // A failed `Show earlier` keeps every row already on screen and adds one line. The
                // control stays, because the thing to do about it is press it again.
                if hasFailedOlder {
                    Text(JournalCopy.olderFailed)
                        .font(CypressFont.body12)
                        .foregroundStyle(CypressColor.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let onShowOlder {
                    SecondaryOutlineButton(JournalCopy.olderAction, style: .compact) {
                        onShowOlder()
                    }
                    .fixedSize()
                    .disabled(isLoadingOlder)
                }
            }
            .padding(.top, JournalMetrics.listTop)
        }
    }

    // MARK: - Failure

    /// The shape screen 08's failure arm uses — one sentence, then a retry that re-runs the load —
    /// rather than a new one, so a reader meeting a second failure meets a screen they already know
    /// how to leave (ERRATA E126).
    private var failure: some View {
        VStack(alignment: .leading, spacing: CypressSpacing.gapRows) {
            Text(JournalCopy.loadFailed)
                .cypressBody135()
                .fixedSize(horizontal: false, vertical: true)

            if let onRetry {
                SecondaryOutlineButton(JournalCopy.loadRetry, style: .compact) { onRetry() }
                    .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

}

// MARK: - The list, with a model behind it

/// `JournalListView` plus the read that fills it.
///
/// Split from the list itself so that every state of the list can be drawn — and photographed — from
/// a value alone, with no API in sight (ERRATA E126's lesson: a state the screen cannot be *given* is
/// a state nobody can photograph). This is the piece the two hosts mount, and it is the reason
/// neither of them has to know that a journal is paginated.
struct JournalSection: View {

    @State private var model: JournalModel

    private let onOpenTree: ((UUID) -> Void)?

    init(api: any CypressAPI, now: @escaping @Sendable () -> Date = { Date() }, onOpenTree: ((UUID) -> Void)? = nil) {
        _model = State(wrappedValue: JournalModel(api: api, now: now))
        self.onOpenTree = onOpenTree
    }

    var body: some View {
        JournalListView(
            presentation: model.presentation,
            hasFailed: model.hasFailed,
            hasFailedOlder: model.hasFailedOlder,
            isLoadingOlder: model.isLoadingOlder,
            onOpenTree: onOpenTree,
            onRetry: { Task { await model.retry() } },
            onShowOlder: { Task { await model.loadOlder() } }
        )
        // `load()` is idempotent on a successful read, so switching away from this segment and back
        // does not throw away pages the reader has already asked for.
        .task { await model.load() }
    }
}
