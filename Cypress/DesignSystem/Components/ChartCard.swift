//
//  ChartCard.swift
//  Cypress — DesignSystem/Components
//
//  C23 · `ChartCard` — SCREENS.md §2. Growth history (11) and tree activity (13).
//
//  ══════════════════════════════════════════════════════════════════════════════════════════
//  ONE DELIBERATE DEVIATION FROM THE MOCK
//  ══════════════════════════════════════════════════════════════════════════════════════════
//  §2 C23 describes a single `polyline` through every point with filled dots for taped values and
//  hollow dots for estimated ones. D7 forbids exactly that: "estimated and taped points render as
//  separate series and are never connected... one connecting line across estimated + taped values
//  manufactures a trend that is not there." DECISIONS outranks SCREENS.md (ARCHITECTURE §1
//  precedence), so `LineChart` strokes **one polyline per `MeasurementSeries`** and never joins a
//  measured point to an estimated one. Dot styling, stroke width, radius and color are unchanged.
//
//  Every point is a `Quantity`, so a series cannot exist without its method.
//
//  Both charts scale the source viewBox horizontally to the available width and keep its vertical
//  units 1:1 — the mocks' 100pt and 36pt plot heights are the drawn heights, and scaling them with
//  the width would make a chart's meaning depend on the device.
//  ══════════════════════════════════════════════════════════════════════════════════════════
//

import SwiftUI

struct ChartCard<Content: View>: View {

    /// `padding:14px 16px 10px` (11) or `14px 16px 8px` (13).
    enum Size {
        case line
        case bars

        var paddingBottom: CGFloat {
            switch self {
            case .line: return CypressSpacing.Component.chartPaddingBottom
            case .bars: return CypressSpacing.Component.chartPaddingBottomBars
            }
        }
    }

    let title: String
    /// The mono range on the right of the header, e.g. `since 2019` or `2026`.
    var range: String?
    var size: Size = .line
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(CypressFont.body145Bold)
                    .foregroundStyle(CypressColor.textInk)
                Spacer(minLength: CypressSpacing.gapDense)
                if let range {
                    Text(range)
                        .font(CypressFont.mono11)
                        .foregroundStyle(CypressColor.textFaint)
                }
            }
            .padding(.bottom, CypressSpacing.Component.chartHeaderBottom)

            content
        }
        .padding(.top, CypressSpacing.Component.chartPaddingTop)
        .padding(.horizontal, CypressSpacing.Component.chartPaddingH)
        .padding(.bottom, size.paddingBottom)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: CypressRadius.cardMd, style: .continuous)
                .fill(CypressColor.surfaceCard)
        }
        .cypressBorder(CypressColor.borderCool, radius: CypressRadius.cardMd)
        .cypressCardShadow()
    }
}

// MARK: - Line chart (11)

/// One measurement in a growth series. The value is a `Quantity`, so its method — and therefore
/// its series and its dot styling — is not optional (D7).
struct ChartPoint: Identifiable {
    let id = UUID()
    /// Position along the x axis, 0…1 (oldest → newest).
    let x: Double
    /// Position along the y axis, 0…1 (bottom → top of the plot).
    let y: Double
    let quantity: Quantity

    var series: MeasurementSeries { quantity.series }

    init(x: Double, y: Double, quantity: Quantity) {
        self.x = x
        self.y = y
        self.quantity = quantity
    }
}

/// C23's line chart. `viewBox="0 0 330 100"`, gridlines at y=28/50/72 from x=10 to x=300.
struct LineChart: View {
    let points: [ChartPoint]
    /// The right-hand latest-value label, e.g. `64`.
    var latestLabel: String?
    /// The bottom-left baseline label, e.g. `47 cm`.
    var baselineLabel: String?
    /// Axis labels under the plot, e.g. `2019 2021 2023 2025`.
    var axisLabels: [String] = []

    private let viewBox = CGSize(
        width: CypressSpacing.Component.chartLineViewWidth,
        height: CypressSpacing.Component.chartLineViewHeight
    )

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                let scale = proxy.size.width / viewBox.width
                ZStack(alignment: .topLeading) {
                    gridlines(scale: scale)
                    ForEach(MeasurementSeries.allCases, id: \.self) { series in
                        seriesPath(series, scale: scale)
                    }
                    dots(scale: scale)
                    labels(scale: scale)
                }
            }
            .frame(height: viewBox.height)
            // ══════════════════════════════════════════════════════════════════════════════════
            // The plot speaks as one element per series, and never as one across both.
            //
            // D7 is not only a drawing rule. "One connecting line across estimated + taped values
            // manufactures a trend that is not there" is a statement about what a reader is
            // allowed to conclude, and a spoken summary that ran from the oldest estimate to the
            // newest tape reading would manufacture exactly the same trend with words instead of
            // a polyline. So each series says its own first and last value, with its own method,
            // and the listener joins them or does not — the same choice the two polylines leave a
            // sighted reader.
            //
            // The per-point dots are deliberately not elements. They were labeled before this
            // pass, on bare `Circle()` shapes with no `.accessibilityElement`, so they were silent
            // anyway; and screen 11 lists every reading underneath in its measurement log, where
            // each row is one stop carrying the value and its badge. Twenty dots would be the
            // same twenty numbers a second time, in an order the plot chose.
            // ══════════════════════════════════════════════════════════════════════════════════
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)

            if !axisLabels.isEmpty {
                HStack {
                    ForEach(Array(axisLabels.enumerated()), id: \.offset) { index, label in
                        Text(label)
                            .font(CypressFont.mono10)
                            .foregroundStyle(CypressColor.textFaint)
                        if index < axisLabels.count - 1 { Spacer(minLength: 0) }
                    }
                }
                .padding(.top, 2)
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
            }
        }
    }

    private func point(_ chartPoint: ChartPoint, scale: CGFloat) -> CGPoint {
        CGPoint(
            x: (CypressSpacing.Component.chartGridlineX0
                + chartPoint.x * (CypressSpacing.Component.chartGridlineX1
                    - CypressSpacing.Component.chartGridlineX0)) * scale,
            y: viewBox.height * (1 - chartPoint.y)
        )
    }

    private func gridlines(scale: CGFloat) -> some View {
        ForEach(CypressSpacing.Component.chartGridlineY, id: \.self) { y in
            Path { path in
                path.move(to: CGPoint(x: CypressSpacing.Component.chartGridlineX0 * scale, y: y))
                path.addLine(to: CGPoint(x: CypressSpacing.Component.chartGridlineX1 * scale, y: y))
            }
            .stroke(CypressColor.chartGridline, lineWidth: CypressSpacing.Component.hairline)
        }
    }

    /// One polyline per series. Never across series — D7.
    private func seriesPath(_ series: MeasurementSeries, scale: CGFloat) -> some View {
        let seriesPoints = points.filter { $0.series == series }.sorted { $0.x < $1.x }
        return Path { path in
            for (index, chartPoint) in seriesPoints.enumerated() {
                let position = point(chartPoint, scale: scale)
                if index == 0 {
                    path.move(to: position)
                } else {
                    path.addLine(to: position)
                }
            }
        }
        .stroke(
            CypressColor.chartSeriesPrimary,
            style: StrokeStyle(
                lineWidth: CypressSpacing.Component.chartSeriesStroke,
                lineCap: .round,
                lineJoin: .round
            )
        )
        .opacity(series == .estimated ? 0.55 : 1)
    }

    /// Filled dot = measured, hollow dot = estimated. §2 C23, verbatim.
    private func dots(scale: CGFloat) -> some View {
        ForEach(points) { chartPoint in
            let position = point(chartPoint, scale: scale)
            let radius = CypressSpacing.Component.chartPointRadius
            Group {
                if chartPoint.series == .measured {
                    Circle().fill(CypressColor.chartSeriesPrimary)
                } else {
                    Circle()
                        .fill(CypressColor.surfaceCard)
                        .overlay {
                            Circle().strokeBorder(
                                CypressColor.chartSeriesPrimary,
                                lineWidth: CypressSpacing.Component.chartSeriesStroke
                            )
                        }
                }
            }
            .frame(width: radius * 2, height: radius * 2)
            .position(position)
        }
    }

    /// What the plot says out loud. See the note in `body`.
    ///
    /// Each series contributes one clause naming how many readings it holds, its method, and the
    /// two ends of it. A series with one reading says the reading rather than "47 to 47"; a plot
    /// with no points at all says so, because an empty chart that announces nothing is a chart a
    /// listener cannot tell from one that failed to load.
    var accessibilityLabel: String {
        let clauses = MeasurementSeries.allCases.compactMap { series -> String? in
            let ordered = points.filter { $0.series == series }.sorted { $0.x < $1.x }
            guard let first = ordered.first, let last = ordered.last else { return nil }

            // The method comes off the quantity, so a series cannot be spoken without it (D7).
            let method = MethodBadge(first.quantity).accessibilityLabel
            let reading = ordered.count == 1 ? "1 reading" : "\(ordered.count) readings"
            guard ordered.count > 1 else {
                return "\(reading) \(method): \(MeasuredValue.formatted(first.quantity))"
            }
            return "\(reading) \(method): "
                + "\(MeasuredValue.formatted(first.quantity)) to \(MeasuredValue.formatted(last.quantity))"
        }
        guard !clauses.isEmpty else { return "Growth plot with no readings." }
        return "Growth plot. " + clauses.joined(separator: ". ") + "."
    }

    @ViewBuilder
    private func labels(scale: CGFloat) -> some View {
        if let latestLabel, let last = points.max(by: { $0.x < $1.x }) {
            Text(latestLabel)
                .font(CypressFont.mono13SemiBold)
                .foregroundStyle(CypressColor.textInk)
                .position(
                    x: viewBox.width * scale - 14,
                    y: point(last, scale: scale).y
                )
        }
        if let baselineLabel {
            Text(baselineLabel)
                .font(CypressFont.mono10)
                .foregroundStyle(CypressColor.textFaint)
                .position(
                    x: CypressSpacing.Component.chartGridlineX0 * scale + 16,
                    y: 92
                )
        }
    }
}

// MARK: - Bar chart (13)

/// C23's 12-month bar row. `viewBox="0 0 330 36"`, bars 18 wide at `x = 10 + 26*i`, baseline at 36.
/// A month with no activity is drawn in `chartGridline` rather than omitted.
struct BarChart: View {
    /// Twelve heights in the source's 0…34 scale, January first.
    let heights: [CGFloat]
    /// What the twelve bars say out loud. **Required**, and the only required label in the
    /// catalog besides C25's.
    ///
    /// The component cannot write this one for itself and must not try. `heights` are drawing
    /// units in the mock's 0…34 viewBox — the bars have already been scaled against whatever
    /// maximum the caller chose, and on 13 that maximum is *shared across three series* so the
    /// rows can be compared (D2, one scale for a small-multiple set). Reading a height back out
    /// would announce a number that is a fraction of someone else's maximum, which is a wrong
    /// count rather than no count. The caller holds the real counts; it hands over the sentence.
    let accessibilityLabel: String
    var tint: Color = CypressColor.chartSeriesPrimary
    /// Months whose bar is drawn empty (`#EAEDDF`) because nothing happened.
    var emptyMonths: Set<Int> = []

    init(
        heights: [CGFloat],
        accessibilityLabel: String,
        tint: Color = CypressColor.chartSeriesPrimary,
        emptyMonths: Set<Int> = []
    ) {
        self.heights = heights
        self.accessibilityLabel = accessibilityLabel
        self.tint = tint
        self.emptyMonths = emptyMonths
    }

    private let viewBox = CGSize(
        width: CypressSpacing.Component.chartBarViewWidth,
        height: CypressSpacing.Component.chartBarViewHeight
    )

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / viewBox.width
            ZStack(alignment: .topLeading) {
                ForEach(Array(heights.prefix(12).enumerated()), id: \.offset) { index, height in
                    RoundedRectangle(cornerRadius: radius(for: height), style: .continuous)
                        .fill(emptyMonths.contains(index) ? CypressColor.chartGridline : tint)
                        .frame(
                            width: CypressSpacing.Component.chartBarWidth * scale,
                            height: height
                        )
                        .offset(
                            x: (CypressSpacing.Component.chartBarX0
                                + CypressSpacing.Component.chartBarStep * CGFloat(index)) * scale,
                            y: viewBox.height - height
                        )
                }
            }
        }
        .frame(height: viewBox.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    /// `rx` 2 at h=4, 2.5 at h≥8, 3 at h=34 — §2, verbatim.
    private func radius(for height: CGFloat) -> CGFloat {
        if height >= 34 { return CypressRadius.chartBarLg }
        if height >= 8 { return CypressRadius.chartBarSm }
        return CypressRadius.chartBarXs
    }
}

/// 13's shared month axis — mono 9pt letters centered at `x = 19 + 26*i`.
struct ChartMonthAxis: View {
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(FoliageStrip.monthLetters.enumerated()), id: \.offset) { _, letter in
                Text(letter)
                    .font(CypressFont.mono9)
                    .foregroundStyle(CypressColor.textFaint)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
        // Twelve letters under twelve bars, and the alignment is the whole point of the axis.
        .cypressTypographicFurniture()
    }
}

/// 13's per-series legend line: swatch · name · mono total, pushed apart.
struct ChartSeriesLegend: View {
    let name: String
    let total: String
    var tint: Color = CypressColor.chartSeriesPrimary

    var body: some View {
        HStack(spacing: CypressSpacing.gapDense) {
            RoundedRectangle(cornerRadius: CypressRadius.legendSwatch, style: .continuous)
                .fill(tint)
                .frame(
                    width: CypressSpacing.Component.chipLegendDot,
                    height: CypressSpacing.Component.chipLegendDot
                )
                // The swatch is the color key for the row directly beneath it, and the row names
                // itself in the same breath. Spoken, it is a duplicate of the adjacent text.
                .accessibilityHidden(true)
            Text(name)
                .font(CypressFont.body125Bold)
                .foregroundStyle(CypressColor.textInk)
            Spacer(minLength: 0)
            Text(total)
                .font(CypressFont.mono12)
                .foregroundStyle(CypressColor.textMuted)
        }
    }
}
