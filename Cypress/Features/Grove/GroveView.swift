//
//  GroveView.swift
//  Cypress — Features/Grove
//
//  Screen 08 · Species you know (My Grove · Species tab). SCREENS.md lines 923–957.
//
//  Composed from C27 (ProgressRing), C29 (SpeciesTile / SpeciesGrid), C14 gradient (Callout) and
//  C16 (BottomTabBar, the no-blur variant this screen specifies). The pill row under the title is
//  screen-08-only — SCREENS.md §2 gives it no C-number and its geometry does not match C5, which is
//  one bordered container with dividers rather than separate pills with a gap between them (see
//  ERRATA E46) — so it is built here from tokens.
//
//  **Two pills, where 08 §2 draws three.** The `Journal` pill embedded the Journal tab's own list;
//  see `GroveTab` for the argument for removing it and the errata entry for this round.
//
//  Not a raw hex or a raw font size in the file (ARCHITECTURE §6). The numbers that remain are
//  SCREENS.md 08's own margins, named in `GroveMetrics`.
//

import SwiftUI

struct GroveView: View {

    @State private var model: GroveModel
    @Environment(AppRouter.self) private var router: AppRouter?

    /// Tapping a species tile opens screen 07 — SCREENS.md 08's caption, verbatim: "Tapping a tile
    /// opens the species page." Handed in rather than pushed here so this folder does not construct
    /// another feature's view (ARCHITECTURE §3); the composition root resolves it.
    private let onOpenSpecies: ((UUID) -> Void)?

    /// Where a row on the `Trees` pill goes: the tree it names.
    private let onOpenTree: ((UUID) -> Void)?

    init(
        api: any CypressAPI,
        now: @escaping @Sendable () -> Date = { Date() },
        tab: GroveTab = .species,
        onOpenSpecies: ((UUID) -> Void)? = nil,
        onOpenTree: ((UUID) -> Void)? = nil
    ) {
        _model = State(wrappedValue: GroveModel(api: api, now: now, tab: tab))
        self.onOpenSpecies = onOpenSpecies
        self.onOpenTree = onOpenTree
    }

    /// The shipping entrance: **the model comes from outside and outlives this view.**
    ///
    /// `RootView.tabRoot` is a `switch` on the selected tab, so every switch away from My Grove
    /// destroys this view — and with the initializer above, the `@State` model with it. Every visit
    /// was therefore a cold load, which is what turned the read's cost into a cost the reader paid
    /// again on every return. The owner ruled on 2026-09-01 that a tab keeps its state across
    /// switches; the model is owned by the composition root now, the same way `OutboxViewState` and
    /// `AccountModel` already are, and this initializer is how it reaches the view.
    ///
    /// It stays `@State`, which is correct rather than leftover: `State(wrappedValue:)` seeds this
    /// view's storage on each fresh mount with whatever it is handed, and what it is handed is the
    /// **same instance** every time. The phase is already `.loaded`, so `.task` repaints from it
    /// instantly and refreshes behind it (`GroveModel.load()`).
    init(
        model: GroveModel,
        onOpenSpecies: ((UUID) -> Void)? = nil,
        onOpenTree: ((UUID) -> Void)? = nil
    ) {
        _model = State(wrappedValue: model)
        self.onOpenSpecies = onOpenSpecies
        self.onOpenTree = onOpenTree
    }

    var body: some View {
        @Bindable var model = model

        return VStack(spacing: 0) {
            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        title
                        GroveTabRow(selection: $model.tab)

                        switch model.tab {
                        case .species: speciesTab
                        case .trees: treesTab
                        }

                        // §6's `margin-top:auto` existed to bottom-pin the footnote, and the copy
                        // audit of 2026-08-23 removed the footnote (owner ruling). The spacer goes
                        // with it: nothing is left to push down, and the `minHeight` frame below
                        // already top-aligns the column on an empty grove. The 14pt that closed the
                        // column was the footnote's own bottom padding and is kept as itself.
                    }
                    .padding(.bottom, CypressSpacing.labelSectionTop)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: proxy.size.height, alignment: .top)
                }
                .scrollBounceBehavior(.basedOnSize)
            }

            BottomTabBar(selection: tabBinding, usesBlur: false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CypressColor.surfaceScreen)
        // C16 absorbs the home indicator with its own 30pt bottom padding (§1.6), so the bar runs to
        // the physical edge rather than floating above an inset.
        .ignoresSafeArea(.container, edges: .bottom)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { await model.load() }
        // The trees read is deferred until somebody asks for that pill, and the model makes it run
        // once — `.task(id:)` fires again on every switch back, so the guard cannot live here.
        .task(id: model.tab) {
            guard model.tab == .trees else { return }
            await model.loadTreesIfNeeded()
        }
    }

    // MARK: - The two pills

    /// Screen 08 proper: the ring, the celebration and the grid — or, on a device that has made no
    /// contributions yet, the sentence ERRATA E48 records the closure of.
    @ViewBuilder
    private var speciesTab: some View {
        if let presentation = model.presentation {
            if presentation.isEmpty {
                // ERRATA E48, closed — owner-approved copy, 2026-08-05. The
                // ring, the celebration and the grid are each derived from contributions
                // (`GrovePresentation.isEmpty`), so a device that has made none renders none of
                // them; this is the sentence that fills the column they would otherwise leave
                // silent, and since the copy audit of 2026-08-23 took §6's footnote out of it (see
                // the note on the spacer above) it is the only thing under the tab row. Same card
                // `treesTab` already draws for its own empty state, below.
                GroveNote(GroveCopy.emptyGrove)
                    .padding(.top, CypressSpacing.labelSectionTop)
                    .padding(.horizontal, CypressSpacing.gutter)
            } else {
                progressBlock(presentation)
                celebration(presentation)
                grid(presentation)
            }
        } else if model.hasFailed {
            failure
        }
    }

    /// The trees this contributor has touched. **NOT SPECIFIED** — see `GroveTreesPresentation`.
    ///
    /// The explanatory line above the list is the project owner's own ask — *"some small explanatory
    /// note of what's on each page"* — and it is the thing that says out loud what the drawing now
    /// also says: **one line per tree, however many times you have been.** Its opposite number is on
    /// the Journal tab (`JournalTabView.explanation`), and the two are written to be read against
    /// each other.
    ///
    /// ── There used to be three arms and no arm for the read in flight ───────────────────────────
    /// While `loadTreesIfNeeded()` was running, `model.treesPresentation` was nil and
    /// `treesHaveFailed` was false, so **none** of the arms matched and this column drew nothing.
    /// That was a 13-to-22-second blank until task #250 batched `LocalAPI.grove()`'s per-tree
    /// reads; at 26 ms on a forty-tree grove a loading state was considered and declined, on the
    /// grounds that a spinner visible for two frames reads as a flicker. The measurement was right
    /// and the conclusion did not survive a bigger grove: at 1,027 trees the same column was blank
    /// for 3.47 s, photographed, because the cost had moved from the query to building a thousand
    /// rows. The owner ruled on 2026-09-02 that the blank is a defect at any duration.
    ///
    /// So the `switch` below is over `GroveModel.TreesDrawing`, which is total, and it has no
    /// `default`. There is no longer an arm to leave out.
    @ViewBuilder
    private var treesTab: some View {
        switch model.treesDrawing {
        case .failed:
            treesFailure
        case .loading:
            // The treatment every other screen in this app uses for a read in flight — screens 03,
            // 07, 11, 13, 15 and the launch gate are all a bare `ProgressView()` — rather than a
            // skeleton or a message, which would be a drawing and a sentence that appear in no mock
            // (DECISIONS constraint 21).
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, CypressSpacing.labelSectionTop)
        case let .list(presentation):
            if let empty = presentation.emptyState {
                GroveNote(empty)
                    .padding(.top, CypressSpacing.labelSectionTop)
                    .padding(.horizontal, CypressSpacing.gutter)
            } else {
                VStack(alignment: .leading, spacing: CypressSpacing.gapRows) {
                    Text(GroveCopy.treesExplanation)
                        .font(CypressFont.body12)
                        .foregroundStyle(CypressColor.textMuted)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(presentation.rows) { row in
                        IconTextRow(
                            accent: .elder,
                            title: row.title,
                            subtitle: row.subtitle,
                            photoID: row.heroPhotoID,
                            action: onOpenTree.map { open in { open(row.treeID) } }
                        )
                    }

                    moreBlock(presentation)
                }
                .padding(.top, CypressSpacing.labelSectionTop)
                .padding(.horizontal, CypressSpacing.gutter)
            }
        }
    }

    /// The sentence about there being more trees, and the control that fetches them.
    ///
    /// **`JournalListView.olderBlock`, component for component and token for token** — the owner's
    /// ruling of 2026-09-02 is that this list pages the way that one does and invents no vocabulary
    /// of its own. Both are absent when the read reached the end, which is the honest drawing of a
    /// finished list: nothing here states or implies how many trees there are (D1, ERRATA E38).
    @ViewBuilder
    private func moreBlock(_ presentation: GroveTreesPresentation) -> some View {
        if let more = presentation.moreNote {
            VStack(alignment: .leading, spacing: CypressSpacing.gapRows) {
                Text(more)
                    .font(CypressFont.body12)
                    .foregroundStyle(CypressColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)

                // A failed `Show more` keeps every row already on screen and adds one line. The
                // control stays, because the thing to do about it is press it again.
                if model.hasFailedMoreTrees {
                    Text(GroveCopy.moreFailed)
                        .font(CypressFont.body12)
                        .foregroundStyle(CypressColor.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SecondaryOutlineButton(GroveCopy.moreAction, style: .compact) {
                    Task { await model.loadMoreTrees() }
                }
                .fixedSize()
                .disabled(model.isLoadingMoreTrees)
            }
            .padding(.top, CypressSpacing.labelSectionTop)
        }
    }

    // MARK: - Title

    /// §1: `My Grove` — Serif 26/600, `padding:10px 18px 4px`. No back button: 08 is a tab root.
    private var title: some View {
        Text(GroveCopy.screenTitle)
            .font(CypressFont.screenTitleGrove)
            .foregroundStyle(CypressColor.textInk)
            .padding(.top, GroveMetrics.titleTop)
            .padding(.bottom, GroveMetrics.titleBottom)
            .padding(.horizontal, CypressSpacing.gutterLabel)
    }

    // MARK: - Progress (C27)

    /// §3: `padding:2px 18px 0`, `HStack(spacing:16)` — the ring, then two lines of text.
    ///
    /// Absent entirely when the two reads behind it could not both be proved complete, or when
    /// nothing is recognized yet. See `GrovePresentation.progress` for why each of those is a
    /// removal rather than a zero.
    @ViewBuilder
    private func progressBlock(_ presentation: GrovePresentation) -> some View {
        if let progress = presentation.progress {
            HStack(spacing: GroveMetrics.progressSpacing) {
                ProgressRing(fraction: progress.fraction, label: progress.ringLabel)

                VStack(alignment: .leading, spacing: GroveMetrics.progressLineGap) {
                    Text(progress.headline)
                        .font(CypressFont.cardTitleSerif)
                        .foregroundStyle(CypressColor.textInk)
                    Text(progress.caption)
                        .font(CypressFont.body13)
                        .foregroundStyle(CypressColor.textMuted)
                }
                .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(.top, GroveMetrics.progressTop)
            .padding(.horizontal, CypressSpacing.gutterLabel)
            // One element, one sentence: a ring and a fraction read twice otherwise.
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Celebration (C14 gradient)

    /// §4: `margin:14px 16px 0`.
    @ViewBuilder
    private func celebration(_ presentation: GrovePresentation) -> some View {
        if let celebration = presentation.celebration {
            Callout(celebration.body, style: .gradient, leadIn: celebration.leadIn)
                .padding(.top, GroveMetrics.calloutTop)
                .padding(.horizontal, CypressSpacing.gutter)
        }
    }

    // MARK: - The grid (C29)

    /// §5: `grid-template-columns:repeat(3,1fr); gap:9px; padding:14px 16px 0`.
    @ViewBuilder
    private func grid(_ presentation: GrovePresentation) -> some View {
        if !presentation.tiles.isEmpty {
            SpeciesGrid {
                ForEach(presentation.tiles) { tile in
                    switch tile {
                    case let .known(id, label, art):
                        SpeciesTile(
                            content: .known(art),
                            // The species' own name, never the artwork's — the two are the same
                            // only for the seven species SCREENS.md happens to draw (ERRATA E51).
                            label: label,
                            // The caption's own sentence: "Tapping a tile opens the species page."
                            action: onOpenSpecies.map { open in { open(id) } }
                        )
                    case .locked:
                        SpeciesTile(content: .locked)
                    }
                }
            }
            .padding(.top, GroveMetrics.gridTop)
            .padding(.horizontal, CypressSpacing.gutter)
        }
    }

    // MARK: - Failure

    /// **NOT SPECIFIED** by SCREENS.md 08, which draws no error state.
    ///
    /// Without this arm a failed read drew the empty grove — title, tab row, and a column of nothing
    /// between them. `GroveModel.Phase` had already refused to conflate those two, on the
    /// grounds that they look identical and mean opposite things; the view then conflated them
    /// anyway by having only one branch, so the distinction the model paid for was spent nowhere
    /// (ERRATA E126).
    ///
    /// The shape is the one the other failed reads in this app use — one sentence, then a retry that
    /// re-runs the load — rather than a new one, because a reader meeting a second failure should be
    /// meeting a screen they already know how to leave.
    ///
    /// It sits on §3's gutter, the block it stands in place of. §6's footnote used to close the
    /// column beneath it; the copy audit of 2026-08-23 removed it, so this sentence is now the last
    /// thing on a failed read.
    private var failure: some View {
        VStack(alignment: .leading, spacing: CypressSpacing.gapRows) {
            Text(GroveCopy.loadFailed)
                .cypressBody135()
                .fixedSize(horizontal: false, vertical: true)

            SecondaryOutlineButton(GroveCopy.loadRetry, style: .compact) {
                Task { await model.retry() }
            }
            .fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, CypressSpacing.labelSectionTop)
        .padding(.horizontal, CypressSpacing.gutterLabel)
    }

    /// The `Trees` read that did not arrive.
    ///
    /// Its own arm rather than a share of the species one, because they are two endpoints: a reader
    /// whose species read failed must still be able to see their trees, and the reverse. Same shape
    /// and same words as the arm above it, because it is the same event on a different read.
    private var treesFailure: some View {
        VStack(alignment: .leading, spacing: CypressSpacing.gapRows) {
            Text(GroveCopy.treesLoadFailed)
                .cypressBody135()
                .fixedSize(horizontal: false, vertical: true)

            SecondaryOutlineButton(GroveCopy.loadRetry, style: .compact) {
                Task { await model.retryTrees() }
            }
            .fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, CypressSpacing.labelSectionTop)
        .padding(.horizontal, CypressSpacing.gutterLabel)
    }

    // §6's footnote was removed by the copy audit of 2026-08-23 (owner ruling). SCREENS.md 08 §6 is
    // struck to match.

    // MARK: - Bottom bar

    /// C16 speaks `Map / My Grove / Journal / You` and `AppRouter` speaks `map / grove / journal /
    /// you`. One translation for all four tab roots, in `AppRouter.bottomTabSelection`.
    private var tabBinding: Binding<BottomTabBar.Tab> {
        router?.bottomTabSelection ?? .constant(.myGrove)
    }
}

// MARK: - The tab row

/// SCREENS.md 08 §2: `padding:8px 18px 14px`, `gap:8px`, `flex:1` pills, `padding:9px 2px`,
/// radius 11px, 13.5px.
///
/// Not C5. C5 is one bordered container with `border-left` dividers and no gap; this is separate
/// bordered pills with 8px between them, at a different radius, and §2's C5 entry does not list 08
/// among its users. Building it as a C5 variant would have meant widening a shared component to hold
/// a control it is not (ERRATA E46).
///
/// **Every pill is a control, and there are two of them where 08 draws three.** The row shipped as
/// three `Text`s, on the stated grounds that "a control that looks pressable and does nothing is
/// worse than a label". `Trees` became a button because its destination turned out to be built and
/// merely unreachable; `Journal` is gone because its destination was the Journal tab, drawn a second
/// time. `flex:1` still holds — the pills divide the width they are given — so the row's geometry is
/// 08's with one cell fewer. See `GroveTab`.
///
/// The drawn appearance is unchanged. What is added is the `Button`, a ≥44pt hit area (the pill is
/// ~33pt as drawn, the same shortfall C5 solves the same way), and the `.isSelected` trait, which
/// was already here and now describes something a reader can change.
struct GroveTabRow: View {

    @Binding var selection: GroveTab

    var body: some View {
        HStack(spacing: GroveMetrics.tabRowGap) {
            ForEach(GroveTab.allCases) { tab in
                pill(tab, isSelected: tab == selection)
            }
        }
        .padding(.top, GroveMetrics.tabRowTop)
        .padding(.bottom, GroveMetrics.tabRowBottom)
        .padding(.horizontal, CypressSpacing.gutterLabel)
    }

    private func pill(_ tab: GroveTab, isSelected: Bool) -> some View {
        Button {
            selection = tab
        } label: {
            Text(tab.label)
                // §1.3's face set has no 600: the ramp's own note maps 600 → Bold, so both weights
                // resolve to the same face and the selected pill is distinguished by its fill.
                .font(CypressFont.body135Bold)
                .foregroundStyle(isSelected ? CypressColor.ctaLabel : CypressColor.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, GroveMetrics.tabPillPaddingV)
                .padding(.horizontal, GroveMetrics.tabPillPaddingH)
                .background {
                    RoundedRectangle(cornerRadius: CypressRadius.grovePill, style: .continuous)
                        .fill(isSelected ? CypressColor.ctaFill : CypressColor.surfaceCard)
                }
                .cypressBorder(
                    isSelected ? CypressColor.ctaFill : CypressColor.borderCool,
                    radius: CypressRadius.grovePill
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cypressHitArea()
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - A sentence where a list would be

/// The card the empty and failed states sit in — one shape, so the difference between them is in the
/// words and never in the drawing (ERRATA E126, and `PrivateReminderList`'s `note`).
struct GroveNote: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(CypressFont.body13)
            .foregroundStyle(CypressColor.textMuted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, YouMetrics.settingPaddingV)
            .padding(.horizontal, YouMetrics.settingPaddingH)
            .background {
                RoundedRectangle(cornerRadius: CypressRadius.cardSm, style: .continuous)
                    .fill(CypressColor.surfaceCard)
            }
            .cypressBorder(CypressColor.borderCool, radius: CypressRadius.cardSm)
    }
}
