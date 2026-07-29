//
//  GrowthHistoryView.swift
//  Cypress — Features/GrowthHistory
//
//  Screen 11 · Growth history. SCREENS.md lines 1015–1049.
//
//  A pushed screen, not a sheet — 11 is reached from a measurement stat card on the tree profile
//  ("Lives under Details on the tree profile", 11's caption), and `TreeProfileView.statGrid` pushes
//  `.growthHistory`.
//
//  Composed from C1 (header), C23 (the two chart cards), C4's method-legend pills and C12 (the
//  badge on every logged number). Nothing new is drawn here.
//
//  Every number on this screen is a `Quantity` rendered through `MeasuredValue`, which is the one
//  view in the design system that renders a value — and it renders its `MethodBadge` beside it, by
//  construction. There is no path through this file that puts a bare number in the log.
//
//  Not a raw hex or a raw font size in the file (ARCHITECTURE §6). The numbers that remain are
//  SCREENS.md 11's own margins, named in `GrowthHistoryMetrics`.
//

import SwiftUI

struct GrowthHistoryView: View {

    @State private var model: GrowthHistoryModel
    @Environment(AppRouter.self) private var router: AppRouter?

    init(treeID: UUID, api: any CypressAPI, calendar: Calendar = .current) {
        _model = State(wrappedValue: GrowthHistoryModel(treeID: treeID, api: api, calendar: calendar))
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CypressColor.surfaceScreen)
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .task { if model.presentation == nil { await model.load() } }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            VStack(spacing: 0) {
                header(pill: nil)
                Spacer()
                ProgressView()
                Spacer()
            }
        case let .failed(error):
            VStack(spacing: 0) {
                header(pill: nil)
                failure(error)
                Spacer()
            }
        case .loaded:
            if let presentation = model.presentation {
                screen(presentation)
            }
        }
    }

    // MARK: - The screen

    private func screen(_ presentation: GrowthHistoryPresentation) -> some View {
        VStack(spacing: 0) {
            header(pill: presentation.treeDisplayName)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // 2–3 · The chart cards. A kind with no chartable reading has no card at all;
                    // see `GrowthHistoryPresentation.chart(for:)`.
                    ForEach(presentation.charts) { chart in
                        chartCard(chart)
                    }

                    // 4 · The legend, reduced to the series that appear above it.
                    if !presentation.legendSeries.isEmpty {
                        legend(presentation)
                    }

                    // The line that explains a missing chart sits where the chart would have been,
                    // above the readings it is about — under the log it reads as a footnote to the
                    // list rather than as the reason the cards are absent.
                    // Which sentence is `noChartReason`'s to decide: a fix too poor and no fix at
                    // all are different facts, and screen 16 already distinguishes them before the
                    // save.
                    if let reason = presentation.noChartReason {
                        emptyState(reason)
                    }

                    // 5 · The measurement log — the record, wider than the charts by design.
                    if !presentation.logRows.isEmpty {
                        log(presentation)
                    }

                    if presentation.isEmpty {
                        emptyState(GrowthHistoryCopy.emptyState)
                    }

                    // 5b · Screen 16's general entrance — the one that is not tied to a measurement
                    // and does not vanish once the tree has both. See
                    // `GrowthHistoryPresentation.offersAddReading` and RULINGS R15.
                    if presentation.offersAddReading {
                        addReadingLink
                    }

                    // 6 · SCREENS.md's footnote is deliberately absent. See
                    // `GrowthHistoryCopy.unrenderedFootnote` and ERRATA (E64).
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, CypressSpacing.bottomFootnote)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    // MARK: - 1 · Header (C1)

    /// The pill names the tree. It is absent while the read is in flight and after it fails, rather
    /// than carrying a placeholder: an empty pill is a claim that this tree has no name.
    @ViewBuilder
    private func header(pill: String?) -> some View {
        if let pill {
            ScreenHeader(
                title: GrowthHistoryCopy.screenTitle,
                trailingPill: pill,
                onBack: { router?.pop() }
            )
        } else {
            ScreenHeader(title: GrowthHistoryCopy.screenTitle, onBack: { router?.pop() })
        }
    }

    // MARK: - 2–3 · Chart cards (C23)

    private func chartCard(_ chart: GrowthChart) -> some View {
        ChartCard(title: chart.title, range: chart.range, size: .line) {
            LineChart(
                points: chart.points.map { ChartPoint(x: $0.x, y: $0.y, quantity: $0.quantity) },
                latestLabel: chart.latestLabel,
                baselineLabel: chart.baselineLabel,
                axisLabels: chart.axisLabels
            )
        }
        .padding(.horizontal, CypressSpacing.gutter)
        .padding(.top, GrowthHistoryMetrics.chartTop)
    }

    // MARK: - 4 · Legend (C4)

    private func legend(_ presentation: GrowthHistoryPresentation) -> some View {
        HStack(spacing: CypressSpacing.gapRows) {
            ForEach(presentation.legendSeries, id: \.self) { series in
                Chip(
                    GrowthHistoryCopy.legendLabel(for: series),
                    style: series == .measured ? .methodLegendTaped : .methodLegendEstimated
                )
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, CypressSpacing.gutterLabel)
        .padding(.top, GrowthHistoryMetrics.legendTop)
        .padding(.bottom, GrowthHistoryMetrics.legendBottom)
    }

    // MARK: - 5 · Measurement log

    private func log(_ presentation: GrowthHistoryPresentation) -> some View {
        VStack(spacing: CypressSpacing.gapDense) {
            ForEach(presentation.logRows) { row in
                logRow(row)
            }
        }
        .padding(.horizontal, CypressSpacing.gutter)
        .padding(.top, GrowthHistoryMetrics.logTop)
    }

    private func logRow(_ row: GrowthLogRow) -> some View {
        HStack(spacing: GrowthHistoryMetrics.logRowSpacing) {
            // The value and its method badge, inseparable (D7). The `role` column SCREENS.md draws
            // between them is absent — see `GrowthLogRow`.
            MeasuredValue(
                quantity: row.quantity,
                size: .growthLog,
                font: CypressFont.mono135SemiBold
            )
            Spacer(minLength: 0)
            Text(row.dateText)
                .font(CypressFont.mono11)
                .foregroundStyle(CypressColor.textFaint)
                .fixedSize()
        }
        .padding(.vertical, GrowthHistoryMetrics.logRowPaddingV)
        .padding(.horizontal, GrowthHistoryMetrics.logRowPaddingH)
        .background {
            RoundedRectangle(cornerRadius: CypressRadius.control, style: .continuous)
                .fill(CypressColor.surfaceCard)
        }
        .cypressBorder(CypressColor.borderCool, radius: CypressRadius.control)
        .accessibilityElement(children: .combine)
    }

    // MARK: - 5b · Add a reading (screen 16's general entrance, RULINGS R15)

    /// Built exactly like `TreeProfileView.growthLink`, which is the control this one answers: same
    /// font, same colour, same 44pt hit area, a quiet text link under the block it belongs to. The
    /// two are a pair — one reads the series back, one adds to it — and a reader who has used either
    /// should recognise the other. C1–C30 is a closed catalogue with no link in it, so a screen-local
    /// control from tokens is what this codebase does here (ERRATA E46).
    ///
    /// It opens 16 on `MeasurementKind.dbh`, SCREENS.md 16 §2's drawn selection. This is the one
    /// entrance in the app that names no measurement, so there is none to carry — and 16's kind
    /// control is the first thing under its header.
    private var addReadingLink: some View {
        Button {
            router?.push(.measure(model.treeID, .dbh))
        } label: {
            Text(GrowthHistoryCopy.addReadingTitle)
                .font(CypressFont.body13Bold)
                .foregroundStyle(CypressColor.ctaFill)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cypressHitArea()
        .padding(.horizontal, CypressSpacing.gutter)
        .padding(.top, GrowthHistoryMetrics.logTop)
    }

    // MARK: - The states SCREENS.md does not draw

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .cypressBody135(color: CypressColor.textMuted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, CypressSpacing.gutterLabel)
            .padding(.top, CypressSpacing.labelSectionTop)
    }

    private func failure(_ error: APIError) -> some View {
        VStack(alignment: .leading, spacing: CypressSpacing.gapRows) {
            Text(error == .notFound ? GrowthHistoryCopy.notFound : GrowthHistoryCopy.loadFailed)
                .cypressBody135()
                .fixedSize(horizontal: false, vertical: true)
            if error.retryable {
                SecondaryOutlineButton(GrowthHistoryCopy.retry, style: .compact) {
                    Task { await model.reload() }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, CypressSpacing.gutterLabel)
        .padding(.top, CypressSpacing.labelSectionTop)
    }
}

// MARK: - Failure copy

/// **NOT SPECIFIED** by SCREENS.md 11, which draws no error state. Same shape as screen 03's.
extension GrowthHistoryCopy {
    static let notFound = "No record for this tree."
    static let loadFailed = "This growth record could not be loaded."
    static let retry = "Try again"
}
