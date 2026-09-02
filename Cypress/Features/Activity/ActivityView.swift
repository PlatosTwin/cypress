//
//  ActivityView.swift
//  Cypress — Features/Activity
//
//  Screen 13 · Tree activity. SCREENS.md lines 1095–1133.
//
//  A pushed screen, not a sheet: it is a whole 812pt frame with its own C1 header and a back circle,
//  which is what every pushed screen in the app draws and what no sheet in it does.
//
//  Composed from C1 (header + trailing pill), C23 (the chart card, its bar variant, its month axis
//  and its per-series legend line) and C10 (the moments rows). §4's photo strip has no C-number —
//  SCREENS.md §2's catalog does not carry it and §4 describes it inline — so it is built here from
//  tokens, the same way 12's composition card was.
//
//  **C26 · AvatarStack is not on this screen, and its absence is the finding rather than an
//  omission.** SCREENS.md 13 does not draw one: 13's parts are a header, a chart card, three C10
//  rows and a photo strip — and a §5 footnote, until the copy audit of 2026-08-23 struck it. The
//  stack is absent from every one of those enumerations, before and after. Nor could one be filled
//  if it were drawn — contribution feeds are private by default and public attribution is opt-in
//  (D11), `User.isPublicAttributionEffective` is the only predicate allowed to answer it, and
//  there is no `User` anywhere near this payload because there is no account system yet and every
//  contribution is anonymous under a device id (D9). A stack of blank circles on a screen about who
//  has looked after a tree would be worse than no stack. See ERRATA.
//
//  Not a raw hex or a raw font size in the file (ARCHITECTURE §6). The numbers that remain are
//  SCREENS.md 13's own margins, named in `ActivityMetrics`.
//
//  Everything about *whether* a block appears is decided in `ActivityPresentation`. This file draws
//  what it is given, which is what makes §5.6 testable without a renderer.
//

import SwiftUI

struct ActivityView: View {

    @State private var model: ActivityModel
    @Environment(AppRouter.self) private var router: AppRouter?

    init(
        treeID: UUID,
        api: any CypressAPI,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() },
        refreshProfile: ((UUID) async -> TreeProfile?)? = nil
    ) {
        _model = State(
            wrappedValue: ActivityModel(
                treeID: treeID, api: api, calendar: calendar, now: now, refreshProfile: refreshProfile
            )
        )
    }

    var body: some View {
        ActivityScreen(
            presentation: model.presentation,
            failure: model.failureError,
            onBack: { router?.pop() },
            onRetry: { Task { await model.reload() } }
        )
        .task { if model.presentation == nil { await model.load() } }
    }
}

// MARK: - The screen itself

/// Screen 13's layout, given a finished derivation.
///
/// Split from `ActivityView` for the reason `AlmanacScreen` is split from `AlmanacView`: this
/// screen's whole subject is which blocks are and are not there, and a layout whose content only
/// exists after an `async` read cannot be photographed offscreen at all — the `.task` never runs in
/// a detached window, so every state renders as the loading one. With the split, any state can be
/// handed straight in and looked at.
struct ActivityScreen: View {

    let presentation: ActivityPresentation?
    var failure: APIError?
    var onBack: (() -> Void)?
    var onRetry: (() -> Void)?

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    if let failure {
                        failureBlock(failure)
                    } else if let presentation {
                        glanceCard(presentation)
                        momentsBlock(presentation)
                        sameWeekBlock(presentation)

                        if presentation.isEmpty {
                            emptyState
                        }
                    }

                    // §5's footnote sat here, under the strip, and was removed by the copy audit of
                    // 2026-08-23 (owner ruling). The `Spacer` went with it: it existed only to push
                    // the footnote to the bottom of a short screen, and the `minHeight` frame below
                    // is what top-aligns the content either way.
                    //
                    // **The 36pt the footnote carried is not the footnote and stays**, on the column
                    // — it is the screen's closing space above the home indicator, and without it
                    // the photo strip sits on the edge.
                }
                // The closing space goes on **before** the `minHeight` frame, not after. Padding a
                // view that has already been sized to the viewport makes the scroll content
                // `proxy.size.height + 36`, which is a permanent overhang on a screen with nothing
                // to scroll. Inside the frame it is space the viewport already accounts for.
                // Every sibling column orders it this way; `ScrollOverhangGuardTests` pins it.
                .padding(.bottom, CypressSpacing.bottomFootnote)
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

    /// `title: Activity`, trailing pill `Grandmother Cypress`.
    ///
    /// No pill until the read lands, and none after it fails: an empty pill is a claim that this
    /// tree has no name. Same rule as 11's.
    @ViewBuilder
    private var header: some View {
        if let name = presentation?.treeDisplayName {
            ScreenHeader(title: ActivityCopy.screenTitle, trailingPill: name, onBack: onBack)
        } else {
            ScreenHeader(title: ActivityCopy.screenTitle, onBack: onBack)
        }
    }

    // MARK: - §2 This year at a glance (C23)

    @ViewBuilder
    private func glanceCard(_ presentation: ActivityPresentation) -> some View {
        if let glance = presentation.glance {
            ChartCard(title: ActivityCopy.glanceTitle, range: glance.year, size: .bars) {
                VStack(alignment: .leading, spacing: ActivityMetrics.seriesGap) {
                    ForEach(glance.rows) { row in
                        VStack(alignment: .leading, spacing: ActivityMetrics.legendGap) {
                            ChartSeriesLegend(
                                name: row.name,
                                // The Care row prints no total (BUILD-PLAN §4). An empty string
                                // rather than a missing view keeps the three legend lines on the
                                // same baseline rhythm.
                                total: row.total ?? "",
                                tint: tint(for: row.kind)
                            )
                            BarChart(
                                heights: row.heights,
                                accessibilityLabel: accessibilityLabel(for: row),
                                tint: tint(for: row.kind),
                                emptyMonths: row.emptyMonths
                            )
                        }
                    }

                    // The month axis is shared, drawn once under all three rows — which is the
                    // visual form of D2's one scale.
                    ChartMonthAxis()
                }
            }
            .padding(.horizontal, CypressSpacing.gutter)
            .padding(.top, ActivityMetrics.chartTop)
        }
    }

    /// Twelve rectangles are nothing to a screen reader, so the row reads its months out.
    private func accessibilityLabel(for row: ActivityPresentation.SeriesRow) -> String {
        let months = row.counts.enumerated()
            .filter { $0.element > 0 }
            .map { "\(TreeProfilePresentation.monthNames[$0.offset]) \($0.element)" }
        guard !months.isEmpty else { return "\(row.name). None this year." }
        return "\(row.name) by month. " + months.joined(separator: ", ") + "."
    }

    /// Never a color of its own (ARCHITECTURE §6) — the three C23 series tokens, in SCREENS.md's
    /// own order: Canopy, New Growth, Bark.
    private func tint(for kind: ActivitySeriesKind) -> Color {
        switch kind {
        case .photos: return CypressColor.chartSeriesPrimary
        case .checkIns: return CypressColor.chartSeriesSecondary
        case .care: return CypressColor.chartSeriesTertiary
        }
    }

    // MARK: - §3 Moments (C10)

    /// Micro-label plus up to three C10 rows.
    ///
    /// The label goes with the rows, as 12's does: a heading over nothing promises something.
    @ViewBuilder
    private func momentsBlock(_ presentation: ActivityPresentation) -> some View {
        let moments = presentation.moments
        if !moments.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text(ActivityCopy.momentsLabel)
                    .cypressMicroLabel()
                    .padding(.bottom, CypressSpacing.gapVitality)

                VStack(spacing: ActivityMetrics.momentGap) {
                    ForEach(moments) { moment in
                        // Inert. SCREENS.md 13 states no affordance for a moment row, and inventing
                        // a destination is what DECISIONS constraint 21 forbids.
                        IconTextRow(accent: moment.accent, title: moment.title, subtitle: moment.subtitle)
                    }
                }
            }
            .padding(.top, CypressSpacing.labelSectionTop)
            .padding(.horizontal, CypressSpacing.gutter)
        }
    }

    // MARK: - §4 Same week, other years

    @ViewBuilder
    private func sameWeekBlock(_ presentation: ActivityPresentation) -> some View {
        let cells = presentation.sameWeek
        if !cells.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text(ActivityCopy.sameWeekLabel)
                    .cypressMicroLabel()
                    .padding(.bottom, CypressSpacing.gapVitality)

                HStack(spacing: ActivityMetrics.stripGap) {
                    ForEach(cells) { cell in
                        ActivityStripTile(cell: cell)
                    }
                }
            }
            .padding(.top, CypressSpacing.labelSectionTop)
            .padding(.horizontal, CypressSpacing.gutter)
        }
    }

    // §5's footnote block was removed by the copy audit of 2026-08-23 (owner ruling); SCREENS.md 13
    // §5 is struck to match. See `ActivityCopy`.

    // MARK: - The states SCREENS.md does not draw

    /// Every tree in the shipped app, on launch day. See `ActivityCopy.emptyState` and ERRATA.
    private var emptyState: some View {
        Text(ActivityCopy.emptyState)
            .cypressBody135(color: CypressColor.textMuted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, CypressSpacing.gutterLabel)
            .padding(.top, CypressSpacing.labelSectionTop)
    }

    private func failureBlock(_ error: APIError) -> some View {
        VStack(alignment: .leading, spacing: CypressSpacing.gapRows) {
            Text(error == .notFound ? ActivityCopy.notFound : ActivityCopy.loadFailed)
                .cypressBody135()
                .fixedSize(horizontal: false, vertical: true)
            if error.retryable, let onRetry {
                SecondaryOutlineButton(ActivityCopy.retry, style: .compact, action: onRetry)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, CypressSpacing.gutterLabel)
        .padding(.top, CypressSpacing.labelSectionTop)
    }
}

// MARK: - §4's tile

/// One tile of the "same week, other years" strip: `flex:1`, height 88, radius 12, with a
/// bottom-left chip naming the year.
///
/// The artwork is a `CypressGradient` placeholder because every image in this app is (SCREENS.md §2
/// preamble). The tile is only ever drawn where a photograph actually exists — see
/// `ActivityPresentation.sameWeek` — so the placeholder stands in for a real frame rather than
/// standing for nothing.
struct ActivityStripTile: View {

    let cell: ActivityPresentation.StripCell

    var body: some View {
        CypressGradientField(recipe)
            .frame(maxWidth: .infinity)
            .frame(height: ActivityMetrics.stripHeight)
            .cypressCornerRadius(CypressRadius.control)
            .overlay(alignment: .bottomLeading) { chip }
            .overlay {
                // §4: the current week takes a 2pt Canopy border; the other two take none at all,
                // which is how the strip says which tile is now without printing a word.
                if cell.isCurrentWeek {
                    RoundedRectangle(cornerRadius: CypressRadius.control, style: .continuous)
                        .strokeBorder(
                            CypressColor.selectionFill,
                            lineWidth: ActivityMetrics.stripCurrentBorder
                        )
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(cell.isCurrentWeek ? "This week" : cell.label)
    }

    private var chip: some View {
        Text(cell.label)
            .font(CypressFont.mono10)
            .foregroundStyle(cell.isCurrentWeek ? CypressColor.onSelectionFill : CypressColor.textBody)
            .padding(.vertical, ActivityMetrics.stripChipPaddingV)
            .padding(.horizontal, ActivityMetrics.stripChipPaddingH)
            .background {
                RoundedRectangle(cornerRadius: CypressRadius.badge, style: .continuous)
                    .fill(cell.isCurrentWeek ? CypressColor.selectionFill : CypressColor.photoStripChipFill)
            }
            .padding(ActivityMetrics.stripChipInset)
    }

    private var recipe: CypressGradientRecipe {
        switch cell.art {
        case .priorEarlier: return CypressGradient.photoStrip2024
        case .priorRecent: return CypressGradient.photoStrip2025
        case .currentWeek: return CypressGradient.photoStripThisWeek
        }
    }
}

// MARK: - Failure plumbing

extension ActivityModel {
    /// The error the screen draws, or nil. Kept off `presentation` so a failure and an empty record
    /// stay two different things all the way to the view.
    var failureError: APIError? {
        guard case let .failed(error) = phase else { return nil }
        return error
    }
}
