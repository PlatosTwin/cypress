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
    /// Which of D7's two series this reading is in. Carried for the withdraw confirmation, which
    /// names the chart the reading would take with it when it is the last of its kind.
    let kind: MeasurementKind
    /// `Oct 2025`.
    let dateText: String

    /// Whether this reader may take the reading back (report F27, `TreeProfile
    /// .withdrawableMeasurementIDs`).
    ///
    /// **Read off the payload, never derived here.** The question needs the viewer's `Attribution`,
    /// and a presentation that held one would be holding identity it has no business with
    /// (ARCHITECTURE §4). It is also not "is this reading on this device": a reading whose
    /// contributor left through the door that keeps their work in place is still drawn in this log
    /// and is nobody's to unmake.
    let isWithdrawable: Bool

    /// Whether withdrawing this reading would leave the tree with no chart of its kind — the one
    /// case where the confirmation says something extra.
    ///
    /// Derived from the loaded profile rather than asked of the API, because the profile already
    /// carries the whole series (`GrowthHistoryModel`'s header) and this is a count over it. The
    /// API answers the same question *after* the fact, in `WithdrawnMeasurement
    /// .leftTheKindWithNoReading`; the two are the same sentence read before and after the tap.
    let isLastOfItsKind: Bool
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
        let live = profile.measurements.filter { $0.deletedAt == nil }
        // One pass for the whole log rather than a count per row: a tree with twenty readings would
        // otherwise walk the series twenty times to answer the same question.
        let liveByKind = Dictionary(grouping: live, by: \.kind).mapValues(\.count)
        return live
            .sorted { $0.capturedAt > $1.capturedAt }
            .map { measurement in
                GrowthLogRow(
                    id: measurement.id,
                    quantity: measurement.quantity,
                    kind: measurement.kind,
                    dateText: TreeProfilePresentation.monthYear.string(from: measurement.capturedAt),
                    // **Ownership only, and deliberately not `acceptsNewContributions`.** That
                    // gate is E95's and `offersAddReading` applies it one block down, because
                    // adding a reading to a record the city has closed is a new contribution to a
                    // tree that is gone. Taking one back is not a contribution at all — it is the
                    // person unmaking their own — and the app already settles this question the
                    // same way one table over: screen 20 draws its delete on a photograph of a
                    // removed tree, gated on `deletablePhotoIDs` and on nothing else. A memorial's
                    // readings are still readings, and a mistyped one on a tree that has since been
                    // felled is exactly the reading somebody would want to withdraw.
                    isWithdrawable: profile.withdrawableMeasurementIDs.contains(measurement.id),
                    isLastOfItsKind: liveByKind[measurement.kind] == 1
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

    /// The sentence the withdraw confirmation shows for one row.
    ///
    /// Composed here rather than in the dialog's `message:` closure so it can be read without a
    /// renderer, which is this file's whole arrangement (`GrowthHistoryPresentation`'s header: "no
    /// SwiftUI in this file"). The second sentence appears only for the last reading of its kind —
    /// see `GrowthHistoryCopy.withdrawLastOfItsKind`.
    static func withdrawMessage(_ row: GrowthLogRow) -> String {
        guard row.isLastOfItsKind else { return GrowthHistoryCopy.withdrawMessage }
        return GrowthHistoryCopy.withdrawMessage + " "
            + GrowthHistoryCopy.withdrawLastOfItsKind(row.kind)
    }

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
    /// not invented — this is a subtraction, in the shape `OutboxCopy.emptyState` uses: say only
    /// what the record supports and drop the rest of the screen. See ERRATA (E63).
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

    // 11 §6's footnote — `Tap any point to open the observation behind it.` — was never rendered,
    // and the string is no longer kept here either.
    //
    // Why it was never drawn (ERRATA E64) is unchanged: there is nothing behind a point to open. A
    // measurement is not an observation, `Route` has no case for either, and no screen in SCREENS.md
    // is drawn as that destination, so printing the instruction would be a promise the app does not
    // keep — the same class of claim as "sent to the city" (ARCHITECTURE §5.4).
    //
    // Why the constant is gone: the copy audit of 2026-08-23 removed the footnote slot everywhere,
    // this site included (owner ruling). It had been kept "so it returns unedited the day the
    // destination is designed", and a mock sentence held in the source against a screen that may
    // never be built is exactly the route by which retired copy comes back. SCREENS.md 11 §6 is
    // struck, which is where it is preserved now, and E64 still says what it said.

    /// **NOT SPECIFIED**; decided in RULINGS R15, see `GrowthHistoryPresentation.offersAddReading`.
    ///
    /// E74's own phrase, which is also `TreeProfilePresentation.emptyMeasurementValue` — so the two
    /// controls that write a reading call the thing by the same name, as
    /// `TreeProfilePresentation.growthLinkTitle` already does for the control that reads them back.
    static let addReadingTitle = "Add a reading"

    // MARK: Withdrawing a reading (report F27)
    //
    // **NOT SPECIFIED.** SCREENS.md 11 §5 draws a log row as value · method · role · date and no
    // control on it, so every string below is this branch's, written under DECISIONS constraint 21
    // and ARCHITECTURE §5 rule 8's practice of going to the nearest specified thing. The nearest
    // specified thing is `TreePhotosView`'s deletion — the app's only other row-level control that
    // unmakes a contribution — and this copy is that copy's shape, clause for clause, with the
    // consequence swapped for the one a reading has.

    /// A question, because the tap that opens the dialog withdraws nothing — `TreePhotosCopy
    /// .deleteTitle`'s reason, in the same words.
    static let withdrawTitle = "Withdraw this reading?"

    /// The two facts an irreversible tap is owed, and the first of them is the one the ruling asked
    /// for: what withdrawal does to a chart.
    ///
    /// **"on this phone", exactly as the photo copy says it**, and for the harder of that clause's
    /// two reasons. `AppSchema` v21 does give the withdrawal a queue row, so this act *can* leave
    /// the device in a way a photo deletion cannot — but only once a drain reaches a service, and
    /// ERRATA **E212** is about two shipped sentences that promised a reader somebody was at the
    /// other end. The screen claims what it has done, and screen 17 is where the queue speaks for
    /// itself.
    static let withdrawMessage =
        "The reading comes off the growth chart and out of the record on this phone. This cannot be undone."

    /// The extra sentence when this is the only reading of its kind: the card for it disappears
    /// (`chart(for:)` draws none for a kind with no point), and that is a visible change to the
    /// screen the reader is standing on.
    static func withdrawLastOfItsKind(_ kind: MeasurementKind) -> String {
        "It is the only \(title(for: kind)) reading on this tree, so that chart goes with it."
    }

    /// The verb is on the button, so the destructive path cannot be taken without the word
    /// *withdraw* under your thumb — E136's rule for the account sheet, applied to a smaller thing.
    static let withdrawAction = "Withdraw reading"

    /// Not "Cancel": the button that does nothing should say what nothing means here.
    static let withdrawCancel = "Keep it"

    /// The VoiceOver hint on the control. Says what it does, in the copy's own terms.
    static let withdrawHint = "Removes this reading from this phone"

    /// The label, which names the reading rather than saying "withdraw" twice: a rotor listing four
    /// identical `Withdraw` actions is a list nobody can act on.
    static func withdrawLabel(_ row: GrowthLogRow) -> String {
        "Withdraw \(MeasuredValue.formatted(row.quantity)), \(row.dateText)"
    }

    /// **NOT SPECIFIED**, same shape as `TreePhotosCopy.deleteFailed`: it says the reading is still
    /// here, because a failure that only says "that did not work" leaves the reader unsure whether
    /// half of it did.
    ///
    /// It ends `Try again.`, so it is **only** for a failure a retry could clear. See
    /// `withdrawFailure(_:)`, which is what the screen actually calls.
    static let withdrawFailed = "That reading could not be withdrawn. It is still here. Try again."

    /// The same failure when trying again cannot work.
    ///
    /// `.forbidden` is reachable with a stale control: `withdrawableMeasurementIDs` is read when the
    /// screen loads, and the leaving door can unlink a reading between that read and the tap (R3's
    /// refusal, which on this table is a tombstone lookup rather than a null owner). Answering that
    /// with `Try again.` tells the reader to do the one thing guaranteed not to work.
    ///
    /// The reading really is still there in this case, so that half of the sentence stays.
    static let withdrawRefused = "That reading is not yours to withdraw. It is still here."

    /// `.notFound`: there is no such reading to withdraw — already withdrawn on another surface, or
    /// the row is gone. `It is still here` is false in exactly this direction, so it is not said.
    static let withdrawAlreadyGone = "That reading is no longer here to withdraw."

    /// Which of the three a failure gets, decided by the taxonomy rather than by a list of cases.
    ///
    /// `APIError.retryable` is the binding answer everywhere else in the app — `OutboxRetryPolicy`
    /// schedules from it and screen 17 offers its retry button on it — so a sentence that invites a
    /// retry follows that same property rather than holding a second opinion beside it. Anything
    /// that is not an `APIError` is a transport throw, where nothing has been decided against the
    /// reader and trying again is exactly the right advice.
    static func withdrawFailure(_ error: (any Error)?) -> String {
        guard let code = error as? APIError else { return withdrawFailed }
        if code == .notFound { return withdrawAlreadyGone }
        return code.retryable ? withdrawFailed : withdrawRefused
    }
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

    /// The withdraw control (report F27). **NOT SPECIFIED** — 11 §5 draws no control on a log row —
    /// so these are screen 20's numbers verbatim (`TreePhotosMetrics.thumbGlyph` / `.thumbTarget`),
    /// which is where the control comes from. 44 pt is the hit area this app gives every control,
    /// and a mark smaller than its target is how screen 20 keeps a row of glyphs from reading as a
    /// row of buttons.
    static let withdrawGlyph: CGFloat = 17
    static let withdrawTarget: CGFloat = 44
}
