//
//  MemorialView.swift
//  Cypress — Features/Memorial
//
//  Screen 19 · Memorial. SCREENS.md lines 1315–1356.
//
//  Composed from C2 (`.memorial` hero, 200pt, desaturated), C13 (`REMOVED`), C14 (`.memorial`
//  banner and the green lineage callout), C9 (four timeline rows, including the `.sync` and
//  `.vitality` thumbs the component already carries for this screen) and C11.
//
//  **What is not here is the screen.** "no Visit CTA, no quad action row, no foliage strip. That
//  absence *is* the read-only state." So there is no disabled button anywhere in this file and no
//  greyed-out affordance: a read-only profile is one with nothing to press, not one with everything
//  pressed out.
//
//  Not a raw hex or a raw font size in the file (ARCHITECTURE §6).
//

import SwiftUI

struct MemorialView: View {

    @State private var model: MemorialModel

    /// The back affordance on the hero. Handed in rather than reached for through the router, so
    /// this feature can be previewed and harnessed without a navigation stack.
    private let onBack: (() -> Void)?

    /// Where §5's lineage points once a replanted profile exists. Nil today: nothing in the payload
    /// links *forward* from a removed tree to its replacement (`Tree.siteLineage` points backwards,
    /// from the new tree to this one), and the callout's own sentence is a promise about the future
    /// rather than a link. Left as a seam rather than invented (DECISIONS constraint 21).
    private let onOpenSuccessor: ((UUID) -> Void)?

    init(
        treeID: UUID,
        api: any CypressAPI,
        now: @escaping @Sendable () -> Date = { Date() },
        onBack: (() -> Void)? = nil,
        onOpenSuccessor: ((UUID) -> Void)? = nil
    ) {
        _model = State(wrappedValue: MemorialModel(treeID: treeID, api: api, now: now))
        self.onBack = onBack
        self.onOpenSuccessor = onOpenSuccessor
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CypressColor.surfaceScreen)
            // 19 draws its own back circle over the desaturated hero. See TreeProfileView.
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .task { if model.presentation == nil { await model.load() } }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView()
        case .loaded:
            if let presentation = model.presentation {
                MemorialScreen(presentation: presentation, onBack: onBack)
            }
        case .notMemorial:
            notMemorial
        case let .failed(error):
            failure(error)
        }
    }

    // MARK: - The two states that are not the screen

    /// A tree that is not removed. **NOT SPECIFIED**, and reachable: a moderator can move a status
    /// back, and a link is followed later than it was made.
    ///
    /// It says what is true and offers nothing, rather than silently redirecting to screen 03 —
    /// which would be this feature constructing another feature's view (ARCHITECTURE §3), and would
    /// also make "the memorial link opened the profile" a thing nobody could explain. Recorded in
    /// ERRATA.
    private var notMemorial: some View {
        VStack(spacing: CypressSpacing.gapRows) {
            Text(MemorialCopy.notAMemorial).cypressBody135()
        }
        .padding(CypressSpacing.gutter)
    }

    private func failure(_ error: APIError) -> some View {
        VStack(spacing: CypressSpacing.gapRows) {
            Text(error == .notFound ? MemorialCopy.noRecord : MemorialCopy.couldNotLoad)
                .cypressBody135()
            if error.retryable {
                SecondaryOutlineButton(MemorialCopy.tryAgain, style: .compact) {
                    Task { await model.load() }
                }
                .frame(maxWidth: MemorialLayout.retryButtonWidth)
            }
        }
        .padding(CypressSpacing.gutter)
    }
}

// MARK: - The screen itself

/// Screen 19's layout, given a finished derivation.
///
/// Split from `MemorialView` for the reason `AlmanacScreen` is: a layout whose content only arrives
/// after an `async` read cannot be photographed offscreen, because `.task` never runs in a detached
/// window. With the split, a tree with no photographs, a tree with no check-in and the fully
/// furnished memorial can each be handed straight in.
struct MemorialScreen: View {

    let presentation: MemorialPresentation
    var onBack: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                banner
                identity
                timeline
                lineage
                stats
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        // The hero runs to the top of the display, as 03's does; its own inset positions the back
        // circle under the status bar.
        .ignoresSafeArea(edges: .top)
    }

    // MARK: §1 · Hero (C2, desaturated)

    private var hero: some View {
        HeroPhotoHeader(
            style: .memorial,
            metaPill: presentation.heroMetaPill,
            eyebrow: presentation.heroEyebrow,
            onBack: onBack
        )
    }

    // MARK: §2 · The banner (C14 memorial)

    private var banner: some View {
        Callout(
            presentation.bannerBody,
            style: .memorial,
            leadIn: presentation.bannerLeadIn
        )
        .padding(.horizontal, CypressSpacing.gutter)
        .padding(.top, MemorialMetrics.bannerTop)
    }

    // MARK: §3 · Identity

    private var identity: some View {
        VStack(alignment: .leading, spacing: MemorialMetrics.latinTop) {
            HStack(alignment: .firstTextBaseline, spacing: CypressSpacing.gapCandidates) {
                Text(presentation.title)
                    .font(CypressFont.treeNameHero)
                    .foregroundStyle(CypressColor.textInk)
                    .fixedSize(horizontal: false, vertical: true)
                StatusBadge(presentation.badge)
                Spacer(minLength: 0)
            }
            // Absent when the record knows neither a species nor a span — an empty italic line is
            // still a line, and a memorial with nothing to say under the name says nothing.
            if !presentation.subtitle.isEmpty {
                Text(presentation.subtitle)
                    .cypressLatinName()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, CypressSpacing.gutter)
        .padding(.top, MemorialMetrics.identityTop)
    }

    // MARK: §4 · Timeline (C9 ×4)

    @ViewBuilder
    private var timeline: some View {
        if !presentation.moments.isEmpty {
            VStack(spacing: CypressSpacing.gapRows) {
                ForEach(presentation.moments) { moment in
                    ActivityRow(
                        leading: leading(for: moment.kind),
                        label: moment.label,
                        detail: moment.detail,
                        timestamp: moment.timestamp
                    )
                }
            }
            .padding(.horizontal, CypressSpacing.gutter)
            .padding(.top, MemorialMetrics.blockGap)
        }
    }

    /// C9 already carries every thumb this screen needs, including two — `.sync` and `.vitality` —
    /// that exist for no other screen.
    private func leading(for kind: MemorialPresentation.Moment.Kind) -> ActivityRow.Leading {
        switch kind {
        case .firstPhoto: return .photo(CypressGradient.activityFirstPhoto)
        case .visit: return .photo(CypressGradient.activityBloom)
        case let .checkIn(vitality): return .vitality(vitality)
        case .cityRecord: return .sync
        }
    }

    // MARK: §5 · Lineage (C14 green, large padding)

    @ViewBuilder
    private var lineage: some View {
        if let leadIn = presentation.lineageLeadIn, let body = presentation.lineageBody {
            Callout(body, style: .green, leadIn: leadIn, largePadding: true)
                .padding(.horizontal, CypressSpacing.gutter)
                .padding(.top, MemorialMetrics.blockGap)
        }
    }

    // MARK: §6 · Stat grid (C11)

    @ViewBuilder
    private var stats: some View {
        if !presentation.stats.isEmpty {
            StatGrid {
                ForEach(presentation.stats) { stat in
                    StatCard(label: stat.label, value: .text(stat.value))
                        .frame(maxHeight: .infinity)
                }
            }
            .padding(.horizontal, CypressSpacing.gutter)
            .padding(.top, MemorialMetrics.blockGap)
            .padding(.bottom, CypressSpacing.bottomBar)
        }
    }
}

// MARK: - Layout

enum MemorialLayout {
    /// Not a spec value — the retry control on the failure state, which SCREENS.md does not draw.
    static let retryButtonWidth: CGFloat = 200
}
