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
    /// Screen 01, narrowed to this contributor's trees (tester report F23). Resolved by the
    /// composition root like every other destination — this folder constructs no other feature's
    /// view and holds no `MapFilter` (ARCHITECTURE §2, §3). Nil in the previews and in the value
    /// tests, where the link is drawn as a plain row of text with nowhere to go.
    var onSeeAllOnMap: (() -> Void)?

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
                    // Above the rows, not under them. This list is paginated, so its bottom is
                    // wherever `Show earlier` has stopped rather than the end of anything; a link
                    // that says `all` would be sitting at the end of a page and reading as the end
                    // of the record. Under the tab's explanation line is also where the sentence is
                    // answering a question the reader already has.
                    if presentation.offersMapLink, let onSeeAllOnMap { mapLink(onSeeAllOnMap) }
                    rows(presentation)
                    olderBlock(presentation)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, JournalMetrics.listTop)
        .padding(.horizontal, CypressSpacing.gutter)
    }

    // MARK: - The way onto the map (tester report F23)

    /// `See them all on the map` — screen 01, narrowed to `Yours`.
    ///
    /// **A text link built from tokens, because C1–C30 has no link in it** and this is the shape the
    /// app already uses where the catalog has no entry: screen 03's `See the whole year`
    /// (`TreeProfileView.activityLink`), down to the font, the color and the hit area. Reading as
    /// the same control at the same volume is the point — a reader who has met one has met this.
    ///
    /// **Drawn only when there is somewhere to go**, in both senses: `offersMapLink` is the list
    /// having rows, and the closure being non-nil is the host having wired a destination. A control
    /// that looks pressable and does nothing is worse than a label — `GroveTabRow` says so, and it
    /// is why this takes the closure as an argument rather than checking it inside.
    private func mapLink(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(JournalCopy.seeAllOnMap)
                .font(CypressFont.body13Bold)
                .foregroundStyle(CypressColor.ctaFill)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cypressHitArea()
        .padding(.bottom, CypressSpacing.gapRows)
    }

    // MARK: - The rows, under their days

    /// **The date leads.** Each day is a `micro.label` rule across the column — the treatment
    /// SCREENS.md §1.3 assigns to "section headers inside screens", and the one screens 03, 07, 13
    /// and 17 already use — with that day's acts under it.
    ///
    /// This is the structural half of telling a chronology from a collection. My Grove's list has no
    /// headers and no dates at all; this one is organized by nothing else. A reader who has just come
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
    /// list: nothing here apologizes for rows that do not exist, and nothing states or implies how
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
/// a state nobody can photograph). This is the piece the host mounts, and it is the reason the host
/// does not have to know that a journal is paginated.
///
/// **It is handed its model rather than owning one, and that is the whole of the segment-switch
/// fix.** This used to declare `@State private var model` and build it in its own initializer.
/// SwiftUI ties `@State` to the identity of the view that declares it, and this view sits inside
/// `JournalTabView`'s `switch` on the segment, so a glance at Neighborhood destroyed the model:
/// every page past the first was thrown away, and `JournalModel.load()`'s idempotence guard — which
/// is correct — met a fresh `.loading` and re-read from scratch. The model now lives on
/// `JournalTabView`, above that `switch`, and this view observes it.
struct JournalSection: View {

    let model: JournalModel

    var onOpenTree: ((UUID) -> Void)?
    var onSeeAllOnMap: (() -> Void)?

    var body: some View {
        JournalListView(
            presentation: model.presentation,
            hasFailed: model.hasFailed,
            hasFailedOlder: model.hasFailedOlder,
            isLoadingOlder: model.isLoadingOlder,
            onOpenTree: onOpenTree,
            onRetry: { Task { await model.retry() } },
            onShowOlder: { Task { await model.loadOlder() } },
            onSeeAllOnMap: onSeeAllOnMap
        )
        // `load()` is idempotent on a successful read, and the model outlives this view (see the
        // type comment), so switching away from this segment and back re-runs this `.task` against
        // a model that is already `.loaded` — the pages the reader asked for are still there and
        // nothing is re-read.
        .task { await model.load() }
    }
}
