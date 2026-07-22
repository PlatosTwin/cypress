//
//  SiteView.swift
//  Cypress — Features/Site
//
//  The vacant planting site — 12,518 of the seed's 195,309 records, and no mocked screen.
//  Decided in ERRATA E107, which closes E11; the copy and the reasoning are in
//  `SitePresentation.swift`.
//
//  Composed from four components that already exist: C1 (`ScreenHeader`), C14 (`Callout`, dashed —
//  the design's own treatment for absence), C11 (`StatCard` in a `StatGrid`) and C10
//  (`IconTextRow`). Nothing is invented and no component gained a variant.
//
//  **What is not here is half the screen.** No hero and no photo well, because there is no tree to
//  photograph; no foliage strip, because there is no canopy; no primary CTA, no check-in and no
//  measurement slot, because a site takes no contribution (`TreeStatus.acceptsNewContributions`);
//  no quad action row, because three of its four cells act on a tree. The one thing to press is a
//  row naming the nearest tree that is actually standing, which is a read.
//
//  Not a raw hex or a raw font size in the file (ARCHITECTURE §6).
//

import SwiftUI

struct SiteView: View {

    @State private var model: SiteModel

    /// The back affordance on C1. Handed in rather than reached for through the router, so this
    /// feature can be previewed and harnessed without a navigation stack.
    private let onBack: (() -> Void)?

    /// Where the nearest-tree row goes. A closure rather than a `Route` for the reason every other
    /// feature folder uses one: features push routes, they do not construct each other's views.
    private let onOpenTree: ((UUID) -> Void)?

    init(
        treeID: UUID,
        api: any CypressAPI,
        onBack: (() -> Void)? = nil,
        onOpenTree: ((UUID) -> Void)? = nil
    ) {
        _model = State(wrappedValue: SiteModel(treeID: treeID, api: api))
        self.onBack = onBack
        self.onOpenTree = onOpenTree
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CypressColor.surfaceScreen)
            // C1 draws its own back circle, so the system bar would put a second `‹ Back` above it.
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
                SiteScreen(presentation: presentation, onBack: onBack, onOpenTree: onOpenTree)
            }
        case .notASite:
            notASite
        case let .failed(error):
            failure(error)
        }
    }

    // MARK: - The two states that are not the screen

    /// A record with a tree standing on it. It says what is true and offers nothing — the mirror of
    /// `MemorialView.notMemorial`, and for the same reason: silently redirecting to screen 03 would
    /// be this feature constructing another feature's view, and would make "the site link opened a
    /// tree profile" something nobody could explain.
    private var notASite: some View {
        VStack(spacing: CypressSpacing.gapRows) {
            Text(SiteCopy.notASite).cypressBody135()
        }
        .padding(CypressSpacing.gutter)
    }

    private func failure(_ error: APIError) -> some View {
        VStack(spacing: CypressSpacing.gapRows) {
            Text(error == .notFound ? SiteCopy.noRecord : SiteCopy.couldNotLoad)
                .cypressBody135()
            if error.retryable {
                SecondaryOutlineButton(SiteCopy.tryAgain, style: .compact) {
                    Task { await model.load() }
                }
                .frame(maxWidth: SiteMetrics.retryButtonWidth)
            }
        }
        .padding(CypressSpacing.gutter)
    }
}

// MARK: - The screen itself

/// The site's layout, given a finished derivation.
///
/// Split from `SiteView` for the reason `MemorialScreen` and `AlmanacScreen` are: a layout whose
/// content only arrives after an `async` read cannot be photographed offscreen, because `.task`
/// never runs in a detached window. With the split, a site with no address, a site with no
/// neighbouring tree and the fully furnished record can each be handed straight in.
struct SiteScreen: View {

    let presentation: SitePresentation
    var onBack: (() -> Void)?
    var onOpenTree: ((UUID) -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                identity
                statement
                stats
                neighbour
                footnote
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: - C1

    private var header: some View {
        ScreenHeader(title: SiteCopy.headerTitle, onBack: onBack)
    }

    // MARK: - Identity

    /// The address, and under it what the record is. **No `StatusBadge`**: C13 draws three kinds,
    /// and the only one that could fire on this record is `PLANTED <year>` — a claim that something
    /// was planted, on a basin with nothing in it.
    private var identity: some View {
        VStack(alignment: .leading, spacing: SiteMetrics.latinTop) {
            Text(presentation.title)
                .font(CypressFont.treeNameColdStart)
                .foregroundStyle(CypressColor.textInk)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(presentation.subtitle)
                .cypressLatinName(CypressFont.latinName145)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, CypressSpacing.gutterLabel)
        .padding(.top, SiteMetrics.blockGap)
    }

    // MARK: - The statement (C14, dashed)

    private var statement: some View {
        Callout(
            presentation.statementBody,
            style: .dashed,
            leadIn: presentation.statementLeadIn
        )
        .padding(.horizontal, CypressSpacing.gutter)
        .padding(.top, SiteMetrics.calloutTop)
    }

    // MARK: - What the city recorded (C11)

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
            .padding(.top, SiteMetrics.calloutTop)
        }
    }

    // MARK: - The nearest standing tree (C10)

    /// The screen's only affordance, and it is a read. Absent when there is no standing tree within
    /// reach, rather than reworded into a row that says nothing.
    @ViewBuilder
    private var neighbour: some View {
        if let neighbour = presentation.neighbour {
            IconTextRow(
                accent: .elder,
                title: neighbour.title,
                subtitle: neighbour.detail,
                action: onOpenTree.map { open in { open(neighbour.id) } }
            )
            .padding(.horizontal, CypressSpacing.gutter)
            .padding(.top, SiteMetrics.calloutTop)
        }
    }

    // MARK: - Footnote

    private var footnote: some View {
        Text(presentation.footnote)
            .cypressBody135(color: CypressColor.textMuted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SiteMetrics.footnotePaddingH)
            .padding(.top, SiteMetrics.footnoteTop)
            .padding(.bottom, CypressSpacing.bottomFootnote)
    }
}
