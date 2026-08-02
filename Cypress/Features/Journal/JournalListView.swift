//
//  JournalListView.swift
//  Cypress — Features/Journal
//
//  The contributions journal, drawn. **NOT SPECIFIED** — the argument for what it is allowed to be
//  is in `JournalPresentation`, which is also where E38 and D1 are enforced.
//
//  ── One list, one door ────────────────────────────────────────────────────────────────────────
//  This view is mounted **once**, as the `Yours` segment of the `Journal` tab.
//
//  It was mounted twice — there and behind screen 08's `Journal` pill — and the argument for that was
//  that the two could not drift, there being one derivation, one model and one view behind both. The
//  argument was sound and the conclusion did not follow. Two doors into one room cannot disagree with
//  each other and can still leave a reader working out why he is being shown the same list twice,
//  which is what happened. The pill is gone; see `GroveTab` for the whole of it.
//
//  What that leaves is a list that has to look like what it is, next to `GroveTreesPresentation`,
//  which is a list of a different thing: **this is a stream of verbs and that is a set of nouns.**
//  The day sections and the verb-first titles below are that distinction, drawn.
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

    // MARK: - The rows, under their days

    /// **The date leads.** Each day is a `micro.label` rule across the column — the treatment
    /// SCREENS.md §1.3 assigns to "section headers inside screens", and the one screens 03, 07, 13
    /// and 17 already use — with that day's acts under it.
    ///
    /// This is the structural half of telling a chronology from a collection. My Grove's list has no
    /// headers and no dates at all; this one is organised by nothing else. A reader who has just come
    /// from the other screen can see which he is on before reading a word of either.
    ///
    /// `.cypressMicroLabel()` carries `.cypressTypographicFurniture()`, which clamps at AX1 — so the
    /// headers stay rules rather than becoming large cramped uppercase that outruns the phone, which
    /// is the failure that modifier exists for. The rows above and below scale the whole way.
    private func rows(_ presentation: JournalPresentation) -> some View {
        VStack(alignment: .leading, spacing: JournalMetrics.dayGap) {
            ForEach(presentation.days) { day in
                VStack(alignment: .leading, spacing: JournalMetrics.rowGap) {
                    Text(day.header)
                        .cypressMicroLabel()
                        .padding(.horizontal, JournalMetrics.dayHeaderInset)

                    ForEach(day.rows) { row in
                        IconTextRow(
                            accent: row.accent,
                            title: row.title,
                            subtitle: row.subtitle,
                            photoID: row.heroPhotoID,
                            // Every row is about a tree, so every row has somewhere to go. Nil only
                            // when the host supplies no destination, in which case C10 draws a card
                            // rather than a button.
                            action: onOpenTree.map { open in { open(row.treeID) } }
                        )
                    }
                }
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
