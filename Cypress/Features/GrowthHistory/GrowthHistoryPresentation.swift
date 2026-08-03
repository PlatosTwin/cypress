//
//  GrowthHistoryPresentation.swift
//  Cypress — Features/GrowthHistory
//
//  Screen 11 · Growth history. SCREENS.md lines 1015–1049.
//
//  The measurement record behind every number the app prints, with the method preserved. Its whole
//  caption is two rules: "filled dots were taped, hollow ones estimated, and the chart never blends
//  the two."
//
//  ── The two rules, and where each is enforced ─────────────────────────────────────────────
//  **D7 — estimated and measured are never one series.** Not enforced here by convention; enforced
//  by construction, in three places that would each have to be defeated separately. `Quantity` has
//  no initializer without a `method`. `MeasurementSeries` has exactly two cases and no "combined"
//  one, so a joined series is unrepresentable. `Collection<TreeMeasurement>.splitBySeries(kind:)` is
//  the only way a chart's points are obtained in this file, and it returns a pair. `LineChart` then
//  strokes one polyline per series and never joins across them.
//
//  **D6 — low-accuracy readings are not chartable.** `TreeMeasurement.isChartable` is
//  `isEligibleForGrowthCharting && deletedAt == nil`, and `isEligibleForGrowthCharting` excludes a
//  fix worse than 15 m *and* a fix that was never recorded ("Unknown accuracy is treated as unusable
//  rather than assumed good", `CoreEntity`). `splitBySeries` applies it. Nothing in this file
//  re-admits an excluded point, and no code path here can plot one.
//
//  A **sparse chart is the correct output**, not a gap to fill. Two dots and no line between them is
//  what two estimates four years apart look like; interpolating, extending to the axis, or borrowing
//  the other series' points would each manufacture a trend nobody measured. There is no smoothing,
//  no zero-baseline and no "no data" substitution anywhere below.
//
//  No SwiftUI in this file. The normalization, the axis, the labels and the series split are all
//  decided here, so D6 and D7 can be tested without a renderer.
//

import Foundation

// MARK: - A plotted point

/// One measurement, positioned.
///
/// It carries its `Quantity`, so its method — and therefore its series and its dot styling — is not
/// optional (D7). There is no initializer that takes a bare number.
struct GrowthPoint: Hashable, Identifiable {
    let id: UUID
    /// Position along the x axis, 0…1 (oldest → newest).
    let x: Double
    /// Position along the y axis, 0…1 (bottom → top of the plot).
    let y: Double
    let quantity: Quantity
    let capturedAt: Date

    var series: MeasurementSeries { quantity.series }
}

// MARK: - A chart

/// One C23 card: a kind of measurement, its points, and the labels around them.
struct GrowthChart: Identifiable {

    let kind: MeasurementKind
    /// `Trunk diameter · DBH` / `Height` — 11 §2–3, verbatim.
    let title: String
    /// `since 2019` — the mono range in the card's header.
    let range: String
    /// Every chartable point of this kind, both series, positioned. Splitting them into the two
    /// polylines is `LineChart`'s job and it does it by `series`.
    let points: [GrowthPoint]
    /// `64` — the newest value, bare, exactly as the mock prints it. The *method* of that value is
    /// carried by the dot beside it (filled or hollow) and named in the legend below, which is how
    /// SCREENS.md encodes it on a chart.
    let latestLabel: String
    /// `47 cm` — the oldest value, with its unit.
    let baselineLabel: String
    /// `2019 2021 2023 2025`, derived from the span rather than fixed.
    let axisLabels: [String]

    var id: MeasurementKind { kind }

    /// Which of the two legend pills this screen needs. A pill for a series with no dot on any chart
    /// would be a key to a mark nobody drew.
    var seriesPresent: Set<MeasurementSeries> { Set(points.map(\.series)) }
}

// MARK: - A log row

/// One row of 11 §5's measurement log.
///
/// **The log is the record, not the chart.** D6 excludes a low-accuracy reading from *charting*; it
/// does not delete it, and hiding somebody's own contribution because the GPS was poor when they
/// made it would be worse than showing it. So every non-deleted measurement appears here, including
/// ones with no dot above.
///
/// SCREENS.md 11 §5 draws a `role` column (`steward`, `member`). Nothing in the profile payload
/// carries it: `TreeMeasurement` holds a `userID` and `TreeProfile` holds no user records, so the
/// role is not a fact this screen has. The column is absent rather than guessed. Recorded in
/// ERRATA (E62).
struct GrowthLogRow: Identifiable {
    let id: UUID
    let quantity: Quantity
    /// `Oct 2025`.
    let dateText: String
}

// MARK: - Presentation

struct GrowthHistoryPresentation {

    let profile: TreeProfile
    private let calendar: Calendar

    init(profile: TreeProfile, calendar: Calendar = .current) {
        self.profile = profile
        self.calendar = calendar
    }

    /// C1's trailing pill — the tree, named the same way every other surface names it.
    var treeDisplayName: String { TreeProfilePresentation(profile: profile).title }

    // MARK: Charts

    /// The cards, in SCREENS.md 11's order: DBH, then height.
    ///
    /// A kind with no chartable point produces **no card**. That is not an error state: a card whose
    /// plot is empty is an assertion that there is a series here, and there is not.
    var charts: [GrowthChart] {
        [MeasurementKind.dbh, .height].compactMap(chart(for:))
    }

    /// Every measurement of one kind that D6 admits, positioned — or nil when none is admitted.
    func chart(for kind: MeasurementKind) -> GrowthChart? {
        // The only door. `splitBySeries` filters on `isChartable` and sorts by capture date, so a
        // point excluded by D6 never reaches this function's body.
        let split = profile.measurements.splitBySeries(kind: kind)
        let admitted = (split.measured + split.estimated).sorted { $0.capturedAt < $1.capturedAt }
        guard let oldest = admitted.first, let newest = admitted.last else { return nil }

        let points = position(admitted)
        return GrowthChart(
            kind: kind,
            title: GrowthHistoryCopy.title(for: kind),
            range: GrowthHistoryCopy.rangePrefix + String(calendar.component(.year, from: oldest.capturedAt)),
            points: points,
            latestLabel: MeasuredValue.number(newest.quantity.value),
            baselineLabel: MeasuredValue.formatted(oldest.quantity),
            axisLabels: axisLabels(from: oldest.capturedAt, to: newest.capturedAt)
        )
    }

    /// Maps capture dates onto 0…1 and values onto the plot band the mock draws its dots in.
    ///
    /// Both axes are normalized over **the points that are actually plotted**. Scaling to an
    /// excluded reading would leave a visible gap at a value nothing explains, and scaling to zero
    /// would flatten every real street tree's growth into one line at the top of the card.
    private func position(_ measurements: [TreeMeasurement]) -> [GrowthPoint] {
        let times = measurements.map(\.capturedAt.timeIntervalSince1970)
        let values = measurements.map(\.quantity.siValue)
        guard let firstTime = times.min(), let lastTime = times.max(),
              let lowest = values.min(), let highest = values.max()
        else { return [] }

        let timeSpan = lastTime - firstTime
        let valueSpan = highest - lowest

        return measurements.map { measurement in
            // A single reading, or several taken the same day, sit at the left edge — where the
            // oldest point always sits — rather than being spread across a span that does not exist.
            let x = timeSpan > 0
                ? (measurement.capturedAt.timeIntervalSince1970 - firstTime) / timeSpan
                : 0
            // A series whose values never change sits on the middle of the band rather than at one
            // end of it, which would read as "at the bottom of its range".
            let y = valueSpan > 0
                ? GrowthHistoryMetrics.plotFloor
                    + (measurement.quantity.siValue - lowest) / valueSpan
                    * (GrowthHistoryMetrics.plotCeiling - GrowthHistoryMetrics.plotFloor)
                : (GrowthHistoryMetrics.plotFloor + GrowthHistoryMetrics.plotCeiling) / 2
            return GrowthPoint(
                id: measurement.id,
                x: x,
                y: y,
                quantity: measurement.quantity,
                capturedAt: measurement.capturedAt
            )
        }
    }

    /// `2019 2021 2023 2025` — up to four evenly spaced years across the plotted span.
    ///
    /// Derived rather than fixed: the mock's four labels describe the mock's eight-year series, and
    /// printing four years across a span of one would put three years on the axis that no reading
    /// falls in.
    private func axisLabels(from start: Date, to end: Date) -> [String] {
        let firstYear = calendar.component(.year, from: start)
        let lastYear = calendar.component(.year, from: end)
        guard lastYear > firstYear else { return [String(firstYear)] }

        let span = lastYear - firstYear
        let ticks = min(GrowthHistoryMetrics.axisTicks, span + 1)
        // Rounded rather than truncated: integer division puts four labels across a four-year span
        // at 2021·2022·2023·2025, which reads as an axis that skips a year and then jumps two.
        // `ticks` never exceeds `span + 1`, so rounding cannot produce the same year twice.
        return (0..<ticks).map { index in
            let offset = (Double(span * index) / Double(ticks - 1)).rounded()
            return String(firstYear + Int(offset))
        }
    }

    // MARK: Legend

    /// The pills 11 §4 draws, reduced to the series that actually appear on a chart above.
    var legendSeries: [MeasurementSeries] {
        let present = charts.reduce(into: Set<MeasurementSeries>()) { $0.formUnion($1.seriesPresent) }
        return MeasurementSeries.allCases.filter { present.contains($0) }
    }

    // MARK: Log

    /// Every non-deleted measurement, newest first. See `GrowthLogRow` for why the set is wider than
    /// the charts'.
    var logRows: [GrowthLogRow] {
        profile.measurements
            .filter { $0.deletedAt == nil }
            .sorted { $0.capturedAt > $1.capturedAt }
            .map { measurement in
                GrowthLogRow(
                    id: measurement.id,
                    quantity: measurement.quantity,
                    dateText: TreeProfilePresentation.monthYear.string(from: measurement.capturedAt)
                )
            }
    }

    // MARK: The empty screen

    /// Nothing has ever been measured on this tree, so there is no chart and no log.
    ///
    /// This is the state **every tree in the shipped inventory is in**: the seed carries no
    /// measurements table at all, and screen 16 (the measure sheet) is the only thing that can
    /// create one. It is also unreachable through the drawn affordance — 11's one entrance is a
    /// measurement stat card on screen 03, which exists only when a measurement does — so nobody is
    /// routed here by the app. The view still has to answer for it. See ERRATA (E63).
    var isEmpty: Bool { charts.isEmpty && logRows.isEmpty }

    /// Measurements exist but D6 admits none of them to a chart. Distinct from `isEmpty`: the log
    /// renders, the charts do not, and neither fact is an error.
    var hasRecordButNoChart: Bool { charts.isEmpty && !logRows.isEmpty }

    /// The sentence that stands where the cards would have been, or nil when there are cards.
    ///
    /// **Two sentences and not one**, for exactly the reason `MeasurePresentation.ChartEligibility`
    /// has three cases and not two: "no fix" and "a fix too poor to use" are different facts about
    /// the world although `isEligibleForGrowthCharting` treats them the same, and screen 16 already
    /// says which of them applies *before* the save. This screen said `too weak` over readings whose
    /// accuracy was never recorded at all — describing a bad fix to somebody whose phone had not
    /// answered yet, which is a claim about their GPS the app is not entitled to make.
    ///
    /// It was reachable, and until this round it was the *common* case: every one of these four
    /// forms froze its accuracy at mount, so a contribution begun before the first fix carried a
    /// `nil` for ever (ERRATA E158).
    var noChartReason: String? {
        guard hasRecordButNoChart else { return nil }
        // Any recorded accuracy at all means at least one of these readings really was measured and
        // really was too poor; with none, nothing here was ever weighed.
        let anyFixRecorded = profile.measurements
            .contains { $0.deletedAt == nil && $0.gpsAccuracyM != nil }
        return anyFixRecorded
            ? GrowthHistoryCopy.noChartableState
            : GrowthHistoryCopy.noFixRecordedState
    }

    // MARK: The general entrance to screen 16 (RULINGS R15)

    /// Whether this screen offers to add a reading — **the app's only measure entrance that is not
    /// tied to one measurement, and the only one that survives a fully measured tree.**
    ///
    /// ── Why it is here and not on 03 ──────────────────────────────────────────────────────────
    /// E74 named this exact control — "an 'add a reading' control under 11's measurement log" — as
    /// the least-invented candidate, and E74/E98 then resolved against it, putting the entrance on
    /// screen 03 as an *empty* measurement stat card. That argument was about a **first** reading and
    /// it still holds: somebody standing at a tree with a tape should not have to find a history
    /// screen, and does not, because the empty slots are on the profile where every other field
    /// action starts.
    ///
    /// What it left unanswered is the **repeat** reading. An empty slot is drawn only while its
    /// measurement is missing, so a tree carrying both a height and a DBH has no slot, no door and no
    /// route to 16 anywhere in the app — the trees with the most growth to record being precisely the
    /// ones with no way to record it. That is E74's own gap reopened, and it passed 819 tests for
    /// weeks. Somebody adding a second height is by definition interested in the series, and this is
    /// the screen that draws the series. See RULINGS R15.
    ///
    /// ── When it draws ─────────────────────────────────────────────────────────────────────────
    /// Whenever the record can take a contribution, including over the empty state: `isEmpty` is the
    /// state every tree in the shipped inventory is in, and a screen that says
    /// `No measurements on this tree yet.` with no way to add one is the emptiest room in the app.
    /// This is R11's rule — an empty state must name what would fill it — with the naming made into
    /// a control.
    ///
    /// Gated on `acceptsNewContributions` and nothing else, which is E95's rule and the same gate
    /// `TreeProfilePresentation.offersMeasurement` applies from the other side: 11 is reachable with
    /// a removed tree (a memorial's readings are still readings), and a read-only record must not be
    /// handed a write.
    var offersAddReading: Bool { profile.tree.status.acceptsNewContributions }

    /// Which of 16 §2's two segments the general link opens on.
    ///
    /// `.dbh`, which is SCREENS.md 16 §2's drawn selection — this is the one entrance in the app
    /// that names no measurement, so it has none to carry.
    ///
    /// **Named here rather than written into the view's `Button`**, for the reason
    /// `TreeProfileView.route(for:treeID:)` is `static`: a kind that only the renderer can reach is
    /// a kind nothing checks, and a hardcoded one in a view body is exactly the hop that let R15's
    /// defect survive its first fix.
    static let addReadingKind: MeasurementKind = .dbh
}

// MARK: - Copy

/// Every string screen 11 renders, verbatim from SCREENS.md 11 unless noted.
enum GrowthHistoryCopy {

    /// 11 §1's header title.
    static let screenTitle = "Growth"

    /// 11 §2–3's card titles, verbatim.
    static func title(for kind: MeasurementKind) -> String {
        switch kind {
        case .dbh: return "Trunk diameter · DBH"
        case .height: return "Height"
        }
    }

    /// The card header's mono range, e.g. `since 2019`.
    static let rangePrefix = "since "

    /// 11 §4's two legend pills, verbatim.
    static func legendLabel(for series: MeasurementSeries) -> String {
        switch series {
        case .measured: return "taped"
        case .estimated: return "estimated"
        }
    }

    /// **NOT SPECIFIED.** SCREENS.md 11 draws no empty state, and per DECISIONS constraint 21 one is
    /// not invented — this is a subtraction, in the shape `TreeProfilePresentation.coldStartFootnote`
    /// already uses: say only what the record supports and drop the rest of the screen. See ERRATA
    /// (E63).
    static let emptyState = "No measurements on this tree yet."

    /// **NOT SPECIFIED**, same reasoning. Readings exist, at least one carries a real fix, and none
    /// of them is good enough to chart.
    static let noChartableState =
        "These readings were taken with a GPS fix too weak to attribute them to this tree, so none of them is charted."

    /// **NOT SPECIFIED**, same reasoning again — and a separate sentence because a reading with no
    /// accuracy at all was not taken on a weak fix, it was taken before the phone had one. Saying
    /// `too weak` over it describes a measurement nobody made. See `noChartReason`.
    static let noFixRecordedState =
        "These readings were saved before the phone had a location fix, so none of them can be attributed to this tree and none is charted."

    /// 11 §6's footnote is **deliberately not rendered**. It reads `Tap any point to open the
    /// observation behind it.`, and there is nothing behind a point to open: a measurement is not an
    /// observation, `Route` has no case for either, and no screen in SCREENS.md is drawn as that
    /// destination. Printing an instruction for an affordance that does not exist is the same class
    /// of claim as "sent to the city" (ARCHITECTURE §5.4) — small, and still a promise the app does
    /// not keep. Recorded in ERRATA (E64), with the string kept here so it returns unedited the day
    /// the destination is designed.
    static let unrenderedFootnote = "Tap any point to open the observation behind it."

    /// **NOT SPECIFIED**; decided in RULINGS R15, see `GrowthHistoryPresentation.offersAddReading`.
    ///
    /// E74's own phrase, which is also `TreeProfilePresentation.emptyMeasurementValue` — so the two
    /// controls that write a reading call the thing by the same name, as
    /// `TreeProfilePresentation.growthLinkTitle` already does for the control that reads them back.
    static let addReadingTitle = "Add a reading"
}

// MARK: - Screen metrics

/// The geometry SCREENS.md 11 gives this screen that `CypressSpacing` does not already name.
enum GrowthHistoryMetrics {

    /// The band the mock's dots occupy inside C23's 100pt plot, as `ChartPoint.y` (0 = bottom).
    ///
    /// 11 §2's lowest drawn point is at SVG `y=80` and its highest at `y=16`, which are `1 - 80/100`
    /// and `1 - 16/100`. Taking the drawn band rather than the full height keeps the oldest dot off
    /// the card's bottom edge and the newest clear of its value label.
    static let plotFloor: Double = 0.20
    static let plotCeiling: Double = 0.84

    /// 11 §2–3 both draw four axis years.
    static let axisTicks = 4

    /// 11 §4: `padding:12px 18px 4px`, `gap:8px`.
    static let legendTop: CGFloat = 12
    static let legendBottom: CGFloat = 4
    /// 11 §5: `padding:6px 16px 0`, `VStack(spacing:7)`, row `padding:10px 13px`, `gap:10px`.
    static let logTop: CGFloat = 6
    static let logRowPaddingV: CGFloat = 10
    static let logRowPaddingH: CGFloat = 13
    static let logRowSpacing: CGFloat = 10
    /// C23: `margin:10px 16px 0`.
    static let chartTop: CGFloat = 10
}
