import Foundation
import Testing
@testable import Cypress

/// Screen 11, derived.
///
/// Two rules carry this screen and both fail *quietly* when they break: a chart with an extra dot
/// looks like a chart, and a chart whose two series were joined looks like a trend. So most of what
/// is pinned here is what does **not** reach a plot.
///
/// - **D6** — a reading whose GPS fix was worse than 15 m, or whose fix was never recorded, is
///   excluded from growth charting. The fix for "the chart looks empty" is one `?? 0` on
///   `gpsAccuracyM` away, and nothing on screen would show that it had been applied.
/// - **D7** — estimated and measured are never one series. The fix for "the line has a gap in it"
///   is one `sorted(by: capturedAt)` over the union away, and the result is a curve nobody measured.
@Suite("Growth history presentation")
struct GrowthHistoryPresentationTests {

    // MARK: - Fixtures

    private static let treeID = UUID(uuidString: "9F3A0000-0000-4000-8000-0000000000B1")!
    private static let deviceID = UUID(uuidString: "9F3A0000-0000-4000-8000-0000000000DE")!

    private static func date(_ year: Int, _ month: Int) -> Date {
        Calendar(identifier: .gregorian).date(
            from: DateComponents(timeZone: TimeZone(identifier: "UTC"), year: year, month: month, day: 12)
        )!
    }

    private static func dbh(
        _ year: Int,
        _ centimetres: Double,
        _ method: MeasurementMethod,
        accuracyM: Double? = 6
    ) -> TreeMeasurement {
        TreeMeasurement.dbh(
            treeID: treeID,
            attribution: .anonymous(deviceID: deviceID),
            capturedAt: date(year, 6),
            gpsAccuracyM: accuracyM,
            quantity: Quantity(value: centimetres, unit: .centimetres, method: method)
        )
    }

    private static func height(
        _ year: Int,
        _ metres: Double,
        _ method: MeasurementMethod,
        accuracyM: Double? = 6
    ) -> TreeMeasurement {
        TreeMeasurement.height(
            treeID: treeID,
            attribution: .anonymous(deviceID: deviceID),
            capturedAt: date(year, 6),
            gpsAccuracyM: accuracyM,
            quantity: Quantity(value: metres, unit: .metres, method: method)
        )
    }

    private static func presentation(_ measurements: [TreeMeasurement]) -> GrowthHistoryPresentation {
        GrowthHistoryPresentation(
            profile: TreeProfile(
                tree: Tree(
                    id: treeID,
                    source: .cityImport,
                    coordinate: Coordinate(latitude: 37.7601, longitude: -122.5054),
                    verificationState: .cityRecord
                ),
                measurements: measurements
            ),
            calendar: {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(identifier: "UTC")!
                return calendar
            }()
        )
    }

    // MARK: - D6 · an ineligible reading never reaches a chart

    @Test("a reading with a GPS fix worse than 15 m is never plotted")
    func lowAccuracyIsNotCharted() {
        let page = Self.presentation([
            Self.dbh(2023, 60, .tape, accuracyM: 6),
            Self.dbh(2024, 62, .tape, accuracyM: 22),
            Self.dbh(2025, 64, .tape, accuracyM: 48),
        ])

        let chart = try! #require(page.chart(for: .dbh))
        #expect(chart.points.count == 1)
        #expect(chart.points.map(\.quantity.value) == [60])
        // The whole record is still the record — the log is not the chart.
        #expect(page.logRows.count == 3)
    }

    @Test("a reading with no recorded fix is never plotted either")
    func unknownAccuracyIsNotCharted() {
        // `CoreEntity`: "Unknown accuracy is treated as unusable rather than assumed good." A
        // `?? 0` here would silently admit every city-imported row ever written.
        let page = Self.presentation([
            Self.dbh(2024, 62, .tape, accuracyM: nil),
            Self.dbh(2025, 64, .tape, accuracyM: nil),
        ])

        #expect(page.chart(for: .dbh) == nil)
        #expect(page.charts.isEmpty)
        #expect(page.logRows.count == 2)
        // Not the empty screen: there *is* a record, and the screen says which state it is in.
        #expect(page.isEmpty == false)
        #expect(page.hasRecordButNoChart)
    }

    @Test("the 15 m boundary is inclusive, and 15.01 m is not")
    func theBoundaryItself() {
        #expect(Self.presentation([Self.dbh(2025, 64, .tape, accuracyM: 15)]).charts.count == 1)
        #expect(Self.presentation([Self.dbh(2025, 64, .tape, accuracyM: 15.01)]).charts.isEmpty)
        #expect(GPSAccuracy.growthChartingLimitM == 15)
    }

    @Test("a soft-deleted reading is neither charted nor logged")
    func softDeletedIsGone() {
        var deleted = Self.dbh(2024, 62, .tape)
        deleted.deletedAt = Self.date(2025, 1)
        let page = Self.presentation([Self.dbh(2025, 64, .tape), deleted])

        #expect(page.chart(for: .dbh)?.points.count == 1)
        #expect(page.logRows.count == 1)
    }

    @Test("an ineligible reading does not move the scale of the points that survive it")
    func excludedReadingsDoNotSetTheAxis() {
        // The excluded reading is far outside the plotted range. If it reached the normalisation,
        // the two real points would collapse toward one end of the band.
        let withOutlier = Self.presentation([
            Self.dbh(2024, 60, .tape),
            Self.dbh(2025, 64, .tape),
            Self.dbh(2023, 400, .tape, accuracyM: 40),
        ])
        let without = Self.presentation([
            Self.dbh(2024, 60, .tape),
            Self.dbh(2025, 64, .tape),
        ])

        #expect(withOutlier.chart(for: .dbh)?.points.map(\.y) == without.chart(for: .dbh)?.points.map(\.y))
        #expect(withOutlier.chart(for: .dbh)?.baselineLabel == "60 cm")
        #expect(withOutlier.chart(for: .dbh)?.range == "since 2024")
    }

    // MARK: - D7 · estimated and measured never merge

    @Test("a chart carrying both methods keeps them in two series")
    func twoSeriesNeverBecomeOne() {
        let page = Self.presentation([
            Self.dbh(2019, 47, .estimate),
            Self.dbh(2021, 51, .tape),
            Self.dbh(2023, 58, .estimate),
            Self.dbh(2025, 64, .tape),
        ])

        let chart = try! #require(page.chart(for: .dbh))
        #expect(chart.points.count == 4)
        #expect(chart.seriesPresent == [.measured, .estimated])

        let estimated = chart.points.filter { $0.series == .estimated }
        let measured = chart.points.filter { $0.series == .measured }
        #expect(estimated.map(\.quantity.value) == [47, 58])
        #expect(measured.map(\.quantity.value) == [51, 64])
        // No point belongs to both, and there is no third bucket for one to hide in.
        #expect(estimated.count + measured.count == chart.points.count)
    }

    @Test("the split is by method, not by the order the readings arrived in")
    func splitIsByMethod() {
        for method in MeasurementMethod.allCases {
            let page = Self.presentation([Self.dbh(2025, 64, method)])
            let chart = try! #require(page.chart(for: .dbh))
            #expect(chart.points.map(\.series) == [method.series])
        }
        // A caliper and a laser are measurements, not estimates — they belong on the taped series
        // and must never be filed as "estimated" for want of a case.
        #expect(MeasurementMethod.caliper.series == .measured)
        #expect(MeasurementMethod.laser.series == .measured)
    }

    @Test("the legend only names series that were actually drawn")
    func legendMatchesTheDots() {
        #expect(Self.presentation([Self.dbh(2025, 64, .estimate)]).legendSeries == [.estimated])
        #expect(Self.presentation([Self.dbh(2025, 64, .tape)]).legendSeries == [.measured])
        #expect(
            Self.presentation([Self.dbh(2024, 60, .tape), Self.dbh(2025, 64, .estimate)])
                .legendSeries == [.measured, .estimated]
        )
        #expect(Self.presentation([]).legendSeries.isEmpty)
    }

    @Test("DBH and height are separate charts and never share a plot")
    func kindsDoNotMerge() {
        let page = Self.presentation([
            Self.dbh(2025, 64, .tape),
            Self.height(2025, 18, .estimate),
        ])

        #expect(page.charts.map(\.kind) == [.dbh, .height])
        #expect(page.chart(for: .dbh)?.points.map(\.quantity.value) == [64])
        #expect(page.chart(for: .height)?.points.map(\.quantity.value) == [18])
        #expect(page.chart(for: .dbh)?.baselineLabel == "64 cm")
        #expect(page.chart(for: .height)?.baselineLabel == "18 m")
    }

    // MARK: - Sparse and empty are outputs, not failures

    @Test("two readings four years apart produce two points and nothing between them")
    func sparseIsCorrectOutput() {
        let page = Self.presentation([
            Self.dbh(2021, 58, .estimate),
            Self.dbh(2025, 64, .estimate),
        ])

        let chart = try! #require(page.chart(for: .dbh))
        #expect(chart.points.count == 2)
        #expect(chart.points.map(\.x) == [0, 1])
        #expect(chart.axisLabels == ["2021", "2022", "2024", "2025"])
        #expect(chart.latestLabel == "64")
        #expect(chart.baselineLabel == "58 cm")
    }

    @Test("one reading is a dot at the left edge with a single axis year")
    func onePointDoesNotSpanASpanThatDoesNotExist() {
        let chart = try! #require(Self.presentation([Self.dbh(2025, 64, .tape)]).chart(for: .dbh))
        #expect(chart.points.map(\.x) == [0])
        #expect(chart.axisLabels == ["2025"])
    }

    @Test("readings that never change sit on the middle of the band, not at the bottom of it")
    func flatSeriesIsNotDrawnAsAFloor() {
        let chart = try! #require(
            Self.presentation([Self.dbh(2023, 64, .tape), Self.dbh(2025, 64, .tape)]).chart(for: .dbh)
        )
        let middle = (GrowthHistoryMetrics.plotFloor + GrowthHistoryMetrics.plotCeiling) / 2
        #expect(chart.points.allSatisfy { $0.y == middle })
    }

    @Test("no tree has ever been measured, which is every tree in the shipped seed")
    func emptyIsAState() {
        let page = Self.presentation([])
        #expect(page.charts.isEmpty)
        #expect(page.logRows.isEmpty)
        #expect(page.isEmpty)
        #expect(page.hasRecordButNoChart == false)
    }

    @Test("every plotted point stays inside the band the mock draws its dots in")
    func pointsStayInsideTheDrawnBand() {
        let page = Self.presentation([
            Self.dbh(2019, 47, .estimate),
            Self.dbh(2022, 56, .tape),
            Self.dbh(2025, 64, .tape),
        ])
        for point in page.chart(for: .dbh)?.points ?? [] {
            #expect(point.y >= GrowthHistoryMetrics.plotFloor)
            #expect(point.y <= GrowthHistoryMetrics.plotCeiling)
            #expect(point.x >= 0)
            #expect(point.x <= 1)
        }
    }

    // MARK: - Every number keeps its method

    @Test("a log row cannot exist without the method of the number on it")
    func everyLoggedNumberCarriesItsMethod() {
        let page = Self.presentation([
            Self.dbh(2025, 64, .tape, accuracyM: 40),
            Self.dbh(2023, 60, .estimate),
        ])
        #expect(page.logRows.count == 2)
        // Newest first, and each row's `quantity` is the whole of what the row renders — there is no
        // bare-number field on `GrowthLogRow` for a view to reach for instead.
        #expect(page.logRows.map(\.quantity.method) == [.tape, .estimate])
        #expect(page.logRows.map(\.dateText) == ["Jun 2025", "Jun 2023"])
    }

    @Test("the axis never prints a year the readings do not span")
    func axisStaysInsideTheSpan() {
        for (first, last) in [(2019, 2025), (2024, 2025), (2020, 2022), (2025, 2025)] {
            let page = Self.presentation([
                Self.dbh(first, 47, .tape),
                Self.dbh(last, 64, .tape),
            ])
            let labels = (page.chart(for: .dbh)?.axisLabels ?? []).compactMap(Int.init)
            #expect(labels.first == first)
            #expect(labels.last == last)
            #expect(labels.allSatisfy { $0 >= first && $0 <= last })
            #expect(labels.count <= GrowthHistoryMetrics.axisTicks)
        }
    }
}
