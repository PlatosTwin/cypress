//
//  AX5ReflowTests.swift
//  CypressTests
//
//  Structural guards for the AX5 fixes tickets #171 and #172 made against the E196 inventory.
//
//  ── What these tests can and cannot decide ────────────────────────────────────────────────
//  The house position (VisitCameraSessionTests, `theChipRowFitsTheWidthItIsGivenAtAX5`): SwiftUI
//  builds no in-process accessibility tree and no render tree a test can walk, so "the label is
//  legible" is verified by looking at the sweep's renders. What a test *can* decide honestly:
//
//  - **Width.** A screen that measures wider than the phone it was proposed is off both edges of
//    the glass — E196 §1 and §3 exactly. `sizeThatFits` reads that geometry.
//  - **Compression resistance.** A control label that reports a smaller height under a starved
//    proposal than under an unbounded one is a label that folded its own words — E196 §6's
//    `Continue with Goo…`.
//  - **The reflow decisions that were made values** for exactly this reason (the
//    `QuadActionRow.appearance` precedent): `StatGrid.columnCount` and `QuadActionRow.rows`.
//
//  Each guard was watched fail against the pre-fix layout (the fix reverted locally) before it
//  was trusted; the red/green pairs are in the branch report for #171/#172.
//

#if DEBUG
import SwiftUI
import Testing
import UIKit
@testable import Cypress

@MainActor
@Suite("AX5 reflow guards (#171, #172)")
struct AX5ReflowTests {

    /// The phone the sweep photographs: 393 pt.
    ///
    /// `nonisolated` because it is `ax5Size`'s default argument, and a default argument is evaluated
    /// at the call site rather than inside the isolated body.
    nonisolated static let phoneWidth: CGFloat = 393
    static let phoneHeight: CGFloat = 852

    /// Hosts `content` at AX5 in an off-screen window and returns what it says it needs when
    /// offered the phone's width and unbounded height — `ScreenSweepShots.capture`'s mechanism,
    /// reduced to the measurement.
    ///
    /// **The running device's safe-area insets come back off the result** (ticket #30). `host.view`
    /// is mounted in a real `UIWindow`, and a hosted root view inherits the *simulator's* safe-area
    /// insets even though this window is parked off-screen and has no `windowScene`: 47 pt at the
    /// top on an iPhone 16e, 54 pt on a 16 Pro — both measured, on the same tree, minutes apart.
    /// `UIHostingController.sizeThatFits` adds them to the height it reports, so every height this
    /// helper returned carried a term that said which simulator the suite was running on rather
    /// than anything about the view: a `MapRecenterButton`, a fixed `CypressSpacing.minTapTarget`
    /// square, came back 98 pt on the 16 Pro and 91 pt on the 16e, and the same 7 pt appeared on
    /// the FAB because it is the same inset added once. Widths were never affected — the left and
    /// right insets are 0 on both — which is why the width guards below never noticed, and why
    /// this reached main inside the two assertions that read a height.
    ///
    /// **`size` is a parameter and defaults to `.accessibility5`**, which is every caller in this
    /// file but one. Task #258's `MapLayout.legendChipHeightLarge` is a bound on the largest
    /// *ordinary* size, because it is a reservation multiplied by up to four and an AX5 figure
    /// applied at the default size would take 276 pt out of another control's budget for no reason.
    /// The default keeps this helper's name honest for everyone else.
    static func ax5Size(
        of content: some View,
        width: CGFloat = phoneWidth,
        settleIterations: Int = 8,
        size: DynamicTypeSize = .accessibility5
    ) async -> CGSize {
        let host = UIHostingController(
            rootView: AnyView(content.environment(\.dynamicTypeSize, size))
        )
        let frame = CGRect(x: 0, y: 0, width: width, height: phoneHeight)
        host.view.frame = frame
        let window = UIWindow(frame: CGRect(x: -2_000, y: 0, width: width, height: phoneHeight))
        window.rootViewController = host
        window.isHidden = false
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        for _ in 0..<settleIterations {
            try? await Task.sleep(for: .milliseconds(120))
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
        }
        let insets = host.view.safeAreaInsets
        let measured = host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(
            width: measured.width - insets.left - insets.right,
            height: measured.height - insets.top - insets.bottom
        )
    }

    // MARK: - #171 · Horizontal overflow

    /// E196 §1: screen 02's populated shortlist forced the screen wider than the phone — the
    /// amber status pill was `.fixedSize()` in both axes — and everything from the title to the
    /// footer drew clipped at both edges. The screen must report the width it is offered.
    @Test("screen 02 (identify, populated) stays inside the phone's width at AX5")
    func identifyFitsThePhoneWidthAtAX5() async {
        let measured = await Self.ax5Size(of: VisitPreviewFixtures.identify())
        #expect(
            measured.width <= Self.phoneWidth,
            "screen 02 measured \(measured.width) pt wide on a \(Self.phoneWidth) pt phone"
        )
    }

    /// The pill on its own, because it was the widest thing on the screen: offered the phone's
    /// width, it must wrap rather than insist on its intrinsic width.
    @Test("the amber status pill wraps at AX5 instead of forcing the row wide")
    func amberStatusPillWrapsAtAX5() async {
        let label = "Two trees in range \u{00B7} confirm by eye"
        let measured = await Self.ax5Size(
            of: VisitAmberStatusChip(label),
            settleIterations: 2
        )
        #expect(
            measured.width <= Self.phoneWidth,
            "the amber pill measured \(measured.width) pt in the \(Self.phoneWidth) pt it was offered"
        )
    }

    // E196 §3 — screen 11's overflow — deliberately has NO width guard here. The overflow lived
    // in the log rows *inside the screen's `ScrollView`*, and a vertical `ScrollView` clamps the
    // width it reports to the width it is proposed, so a `sizeThatFits` probe on the screen
    // measured 393 pt with the defect present — a guard that was watched NOT fail against the
    // broken layout, and a test that cannot fail is not evidence (the #144 lesson, again). The
    // fix is `GrowthHistoryView.logRow`'s `ViewThatFits`; the sweep's
    // `11-growth-history-*-ax5` renders are what verify it, per ARCHITECTURE §7.

    // The two guards below are screen 11's *other* half, found in the same renders a round later:
    // E199 fixed the log rows and never reached the chart C23 draws above them. Both measure
    // through `LineChart` / `ChartPlotLabel` themselves rather than through a copy of their
    // styling — a probe that applied its own `cypressTypographicFurniture()` would go on passing
    // with the cap deleted from the component, which is the shape of guard this file already threw
    // away once.

    /// The width `LineChart` is drawn in on screen 11: the phone less the screen gutter each side
    /// (`GrowthHistoryView.chartCard`) and the card's own horizontal padding each side.
    static let growthPlotWidth: CGFloat = phoneWidth
        - 2 * CypressSpacing.gutter
        - 2 * CypressSpacing.Component.chartPaddingH

    /// The axis labels mark x positions in the plot above them, so a year that wrapped marks
    /// nothing: at AX5 four unclamped years measure 356 pt, and their row adds 4 pt of horizontal
    /// padding each side, so it needs 364 pt of a 329 pt plot and broke
    /// `2019` into `201` over `9`. One line for four labels is the property — measured as "four
    /// labels are no taller than one", so the guard names the wrap rather than a pixel count.
    @Test("the growth chart's year axis stays on one line at AX5")
    func theGrowthChartsYearAxisStaysOnOneLineAtAX5() async {
        func chartHeight(_ labels: [String]) async -> CGFloat {
            await Self.ax5Size(
                of: LineChart(points: [], axisLabels: labels),
                width: Self.growthPlotWidth,
                settleIterations: 2
            ).height
        }
        let four = await chartHeight(["2019", "2021", "2023", "2025"])
        let one = await chartHeight(["2019"])
        #expect(
            four == one,
            "four year labels made the chart \(four) pt tall against \(one) pt for a single label — the axis row wrapped, and a wrapped year is two numbers"
        )
    }

    /// `LineChart` places the baseline label with `.position`, which centers it: half its width
    /// hangs to the left of `baselineLabelCenterX`, and the only thing between that and the page
    /// behind the card is the card's own horizontal padding. Unclamped at AX5 the label measured
    /// 111 pt against a 26 pt center and was drawn outside the card in both appearances.
    ///
    /// `.position` draws outside its own frame without changing the size anything reports, so no
    /// width probe on the screen can see this — the label's own measurement against the budget it
    /// is placed in is the whole of the evidence available in-process.
    @Test("the baseline chart label stays inside its card at AX5")
    func theBaselineChartLabelStaysInsideItsCardAtAX5() async {
        let scale = Self.growthPlotWidth / CypressSpacing.Component.chartLineViewWidth
        let centerX = LineChart.baselineLabelCenterX(scale: scale)
        let budget = centerX + CypressSpacing.Component.chartPaddingH
        let measured = await Self.ax5Size(
            of: ChartPlotLabel("47 cm", role: .baseline).fixedSize(),
            width: Self.phoneWidth,
            settleIterations: 2
        )
        #expect(
            measured.width / 2 <= budget,
            "the baseline label measured \(measured.width) pt, so centered at \(centerX) pt it reaches \(measured.width / 2 - budget) pt past the card's leading edge"
        )
    }

    // MARK: - #172 · Labels that fold

    /// E196 §6: the account sheet is a content-sized card with no scroll, and under vertical
    /// compression its provider buttons folded to one line — `Continue with Goo…`, an ellipsis
    /// inside a control. With the fix the label insists on every line it needs: squeezed to a
    /// starved height, it reports the same height it wants unbounded.
    @Test("the account provider label refuses vertical compression at AX5")
    func accountProviderLabelRefusesCompressionAtAX5() async {
        let button = AccountProviderButton(
            title: "Continue with Google",
            isPrimary: false,
            action: {}
        )
        let host = UIHostingController(
            rootView: AnyView(button.environment(\.dynamicTypeSize, .accessibility5))
        )
        let width = Self.phoneWidth - CypressSpacing.Component.sheetPaddingHAccount * 2
        let unbounded = host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
        let squeezed = host.sizeThatFits(in: CGSize(width: width, height: 10))
        #expect(
            squeezed.height >= unbounded.height,
            "squeezed to 10 pt the label reported \(squeezed.height) pt against an unbounded \(unbounded.height) pt — it gave up lines, which is where the ellipsis comes from"
        )
    }

    /// E196 §8: the C11 grid halves the phone at every size, and half a phone at AX5 is where the
    /// city's strings broke mid-word. The decision is a value (the `QuadActionRow.appearance`
    /// precedent); the renders are the legibility evidence.
    @Test("the stat grid is two columns drawn, one column at accessibility sizes")
    func statGridColumnCount() {
        #expect(StatGrid<EmptyView>.columnCount(isAccessibilitySize: false) == 2)
        #expect(StatGrid<EmptyView>.columnCount(isAccessibilitySize: true) == 1)
    }

    /// E196 §8's other half: four cells across at AX5 left each label `Favo…`. Two rows of two at
    /// the accessibility sizes, the drawn single row otherwise — and the split never loses a cell.
    @Test("the quad action row is one row drawn, two rows of two at accessibility sizes")
    func quadActionRowRows() {
        let all = QuadActionRow.Action.allCases
        #expect(QuadActionRow.rows(of: all, isAccessibilitySize: false) == [all])
        #expect(
            QuadActionRow.rows(of: all, isAccessibilitySize: true)
                == [[.favorite, .care], [.share, .report]]
        )
        // The reflow reorders nothing and drops nothing, at either setting.
        #expect(
            QuadActionRow.rows(of: all, isAccessibilitySize: true).flatMap(\.self) == all
        )
    }

    // MARK: - Task #14 item 2 · screen 10's link releases its clamp at AX5 (E60)

    /// **The reflow decision, as a value.** `StatGrid.columnCount` and `QuadActionRow.rows` are the
    /// precedent: a layout choice that depends on the type size is a function a test can read,
    /// because a ternary buried inside a `.lineLimit` modifier can be inverted without anything
    /// going red.
    ///
    /// Two lines at the drawn sizes, no cap above the accessibility threshold. E60's governing
    /// sentence is that half a link with an ellipsis on the end is worse than a link on two lines —
    /// and at AX5 `lineLimit(2)` was delivering `cypress.app/sf/tree/0…`, which is not half the
    /// link but a fifth of it.
    @Test("the share link's line cap comes off above the accessibility threshold")
    func shareURLLineLimitReleasesAtAccessibilitySizes() {
        #expect(ShareMetrics.urlLineLimit(isAccessibilitySize: false) == 2)
        #expect(ShareMetrics.urlLineLimit(isAccessibilitySize: true) == nil)
    }

    /// …and releasing it is not cosmetic, which the value test alone cannot say.
    ///
    /// The same string, in the same font, offered the same width the card gives it, measured at AX5
    /// with the cap and without: uncapped must be **strictly taller**. Equal heights would mean the
    /// cap was never binding, the release buys the reader nothing, and the test above would be
    /// pinning a decision with no effect — a guard that cannot fail is not evidence. The width is
    /// the card's full inner width, which is what item 2's layout change gives the link: the
    /// phone's width less `cardPadding` on each side.
    @Test("uncapping the link at AX5 actually buys the reader more of it")
    func releasingTheShareURLClampAddsLines() async {
        let link = "cypress.app/sf/tree/0300b83f-6a1e-4c9b-8f2d-1b7e5a904c31"
        let innerWidth = Self.phoneWidth - (ShareMetrics.cardPadding * 2)
        func height(lineLimit: Int?) async -> CGFloat {
            await Self.ax5Size(
                of: Text(link)
                    .font(CypressFont.mono105)
                    .lineLimit(lineLimit)
                    .fixedSize(horizontal: false, vertical: true),
                width: innerWidth,
                settleIterations: 2
            ).height
        }
        let capped = await height(lineLimit: ShareMetrics.urlLineLimit)
        let released = await height(lineLimit: nil)
        #expect(
            released > capped,
            """
            at AX5 the link measured \(released) pt uncapped against \(capped) pt at \
            lineLimit(\(ShareMetrics.urlLineLimit)), in the \(innerWidth) pt the card gives it. \
            Equal heights would mean the cap never bound and the release buys the reader nothing — \
            E60's whole objection is that the capped rendering shows a fifth of the identifier.
            """
        )
    }

    /// E196 §5, post-#146 shape: the three-destination share row. Fragmentation is judged by
    /// looking; what geometry can hold is that the row never forces the sheet wide — a regression
    /// to intrinsic-width cells would.
    ///
    /// It also guards item 2's layout change from the other side: the link is now a full-width row
    /// of its own, and a full-width row that insisted on its intrinsic width would push screen 10
    /// off both edges of the glass exactly as E196 §1's amber pill did.
    @Test("the share sheet stays inside the phone's width at AX5")
    func shareSheetFitsThePhoneWidthAtAX5() async {
        let measured = await Self.ax5Size(
            of: ShareView(treeID: SharePreviewFixtures.treeID, api: SharePreviewAPI())
        )
        #expect(
            measured.width <= Self.phoneWidth,
            "screen 10 measured \(measured.width) pt wide on a \(Self.phoneWidth) pt phone"
        )
    }

    // MARK: - RULINGS R53 §6's AX5 ruling (owner decision 2026-08-05) · MapLocationNotice scrolls rather than overflows

    /// `MapLayout.locateButtonHeightAX5` and `.fabHeightAX5`, the inputs to
    /// `noticeMaxHeight(screenHeight:topInset:namedSpecies:isAccessibilitySize:)`, are what the
    /// bottom slot reserves for the two
    /// controls stacked above the notice. Guarded here so a control that outgrows its reservation fails
    /// loudly instead of quietly under-reserving the notice's scroll budget.
    ///
    /// **`<=`, not `==`, and the difference is the whole of ticket #30.** These two assertions were
    /// written as equalities against 98 and 137, and both numbers were the control's real footprint
    /// plus the 54 pt top safe-area inset that `ax5Size`'s measuring window inherited from the
    /// iPhone 16 Pro it was recorded on. On an iPhone 16e the same inset is 47 pt, so the same
    /// unmodified tree measured 91 and 130 and this test failed on the device rather than on the
    /// code. `ax5Size` now takes the inset back off (see its own note), which makes the measurement
    /// device-independent. Under-reserving is E183 §2, the card growing off the top of the screen;
    /// `<=` is the assertion that names that direction as the only defect.
    ///
    /// **`MapLayout.locateButtonHeightAX5` and `.fabHeightAX5` were corrected to the bare footprints
    /// this test measures (44 and 83) on 2026-08-06, by direct owner ruling** — superseding
    /// RULINGS R53 §6's conservative stance for these two constants specifically. `<=` is kept
    /// rather than tightened to `==` because the guard's job is catching under-reservation if a
    /// control's footprint ever grows again, not asserting today's exact numbers a second time.
    @Test("the recenter control and the FAB fit what the notice's scroll budget reserves at AX5")
    func bottomChromeControlsFitTheReservedBudgetAtAX5() async {
        let recenter = await Self.ax5Size(of: MapRecenterButton(engagement: .away, action: {}))
        let fab = await Self.ax5Size(of: IdentifyFAB(action: {}))
        #expect(
            recenter.height <= MapLayout.locateButtonHeightAX5,
            """
            MapRecenterButton now measures \(recenter.height) pt at AX5, past the \
            \(MapLayout.locateButtonHeightAX5) pt the notice's scroll budget reserves for it
            """
        )
        #expect(
            fab.height <= MapLayout.fabHeightAX5,
            """
            IdentifyFAB now measures \(fab.height) pt at AX5, past the \
            \(MapLayout.fabHeightAX5) pt the notice's scroll budget reserves for it
            """
        )
        // The exact half, kept exact: the recenter control is a fixed `minTapTarget` square and
        // does not grow with Dynamic Type at all — measured 44 pt at AX5 on both the 16e and the
        // 16 Pro. `MapKitBasemap` used to claim in a comment that iOS grew this control's hit
        // target across the accessibility range and that 98 pt was the grown frame; the 98 was the
        // safe-area inset, and the claim was never true.
        #expect(
            recenter.height == CypressSpacing.minTapTarget,
            """
            MapRecenterButton measures \(recenter.height) pt at AX5 against the \
            \(CypressSpacing.minTapTarget) pt frame it declares — it is no longer a fixed square
            """
        )
    }

    // MARK: - Task #250 · The top chrome's own reservation

    /// `MapLayout.searchBarHeightAX5` and `.chipRowHeightAX5` are the inputs to
    /// `topChromeReservedAX5(topInset:)`, which
    /// `noticeMaxHeight(screenHeight:topInset:namedSpecies:isAccessibilitySize:)` subtracts so the
    /// recenter control — first in `bottomChrome`'s bottom-anchored stack — cannot
    /// rise above the filter chip row's own bottom edge no matter how tall the notice below it
    /// grows. Guarded the same way `bottomChromeControlsFitTheReservedBudgetAtAX5` guards the other
    /// two reservation inputs: `<=`, so either control growing past what is reserved for it fails
    /// loudly instead of quietly under-reserving.
    ///
    /// **Both grow with Dynamic Type, unlike `MapRecenterButton`.** `SearchBar`'s field and
    /// `MapFilterChips`'s pills carry `CypressFont.body145` text, and the row stays one line at
    /// every size (#166) rather than wrapping, so neither is a fixed frame the way the recenter
    /// square is — the bound is a footprint, not an exact measurement repeated.
    @Test("the search bar and the filter chip row fit what the top-chrome reservation gives them at AX5")
    func topChromeFitsItsReservedBudgetAtAX5() async {
        let bar = await Self.ax5Size(of: SearchBar(text: .constant("")))
        let chips = await Self.ax5Size(of: MapFilterChips(filter: .constant(.all)))
        #expect(
            bar.height <= MapLayout.searchBarHeightAX5,
            """
            SearchBar now measures \(bar.height) pt at AX5, past the \
            \(MapLayout.searchBarHeightAX5) pt the top-chrome reservation gives it
            """
        )
        #expect(
            chips.height <= MapLayout.chipRowHeightAX5,
            """
            MapFilterChips now measures \(chips.height) pt at AX5, past the \
            \(MapLayout.chipRowHeightAX5) pt the top-chrome reservation gives it
            """
        )
    }

    // MARK: - Task #258 · The species legend, which the top-chrome reservation used not to name

    /// A legend of `count` chips with names long enough that none of them pair up on a line.
    ///
    /// The names are the long ones `MapSpeciesLegend`'s header quotes — the point of the fixture is
    /// to force the *worst* shape, one chip per line, which is what
    /// `MapLayout.legendReserved(namedSpecies:isAccessibilitySize:)` claims to bound.
    private static func legend(count: Int) -> MapSpeciesLegend {
        let names = ["New Zealand Christmas Tree", "Southern Magnolia", "Brisbane Box", "Chinese Elm"]
        let entries = MapSpeciesSlot.allCases.prefix(count).enumerated().map { index, slot in
            MapSpeciesPalette.Entry(slot: slot, speciesID: UUID(), count: 10, name: names[index])
        }
        return MapSpeciesLegend(
            palette: MapSpeciesPalette(entries: Array(entries)),
            selection: .constant(nil)
        )
    }

    /// **`MapLayout.legendReserved` is an upper bound on what `MapSpeciesLegend` occupies, at both
    /// ends of the type ramp.**
    ///
    /// This is the guard task #258's fix rests on. `MapHomeView` deliberately does not measure where
    /// the top chrome ends — a measurement handed back through `@State` froze on roughly one launch
    /// in eight, with the `GeometryReader` computing the right number and `onChange` never firing
    /// for the last transition — so the room the legend needs is *computed* from the number of chips
    /// it will draw. A computed reservation is only as good as the per-chip bound it multiplies, and
    /// that bound is what this measures.
    ///
    /// `<=`, and the direction is the defect: under-reserving is what put the species legend on top
    /// of the identify FAB, screen 01's only entrance to the visit flow. Over-reserving only costs
    /// `MapLocationNotice` scroll budget it is nowhere near using.
    ///
    /// Measured for all four counts rather than only the worst, because the reservation is a
    /// *formula* in the count — `count` chips, `count − 1` gaps — and a formula that is right at 4
    /// and wrong at 1 is a formula nobody checked. The gap above the legend (`chipRowTop`) is the
    /// `VStack`'s own spacing and is not part of what this view measures, so it comes back off.
    @Test("the species legend fits what the top-chrome reservation gives it, at AX5 and at xxxLarge")
    func theSpeciesLegendFitsItsReservationAtAX5() async {
        for count in 1...MapSpeciesSlot.allCases.count {
            for isAccessibilitySize in [true, false] {
                let size: DynamicTypeSize = isAccessibilitySize ? .accessibility5 : .xxxLarge
                let measured = await Self.ax5Size(
                    of: Self.legend(count: count),
                    settleIterations: 2,
                    size: size
                )
                let reserved = MapLayout.legendNaturalHeight(
                    namedSpecies: count,
                    isAccessibilitySize: isAccessibilitySize
                )
                #expect(
                    measured.height <= reserved,
                    """
                    MapSpeciesLegend with \(count) chip(s) measures \(measured.height) pt at \
                    \(size), past the \(reserved) pt MapLayout.legendNaturalHeight bounds it at — \
                    the top \
                    chrome then reaches further down screen 01 than MapLayout.noticeMaxHeight holds \
                    the bottom chrome back from, which is the identify FAB covered by the legend \
                    (task #258)
                    """
                )
            }
        }
    }

    /// **The reservation is zero when the legend draws nothing**, which is a real and common state
    /// rather than an edge case — a clustered viewport ranks no species and `MapSpeciesLegend`
    /// renders nothing at all. Reserving for it anyway would take the notice's budget for a control
    /// that is not on the screen.
    @Test("an empty species legend reserves nothing and is given no ceiling")
    func anEmptySpeciesLegendReservesNothing() {
        for isAccessibilitySize in [true, false] {
            #expect(
                MapLayout.legendReserved(
                    screenHeight: 874,
                    topInset: 54,
                    namedSpecies: 0,
                    isAccessibilitySize: isAccessibilitySize
                ) == 0
            )
            #expect(
                MapLayout.legendMaxHeight(
                    screenHeight: 874,
                    topInset: 54,
                    namedSpecies: 0,
                    isAccessibilitySize: isAccessibilitySize
                ) == nil
            )
        }
    }

    /// **The ceiling does not bind on any device the suite runs on**, which is the claim that makes
    /// "unchanged where there is room" true rather than hoped for: `legendMaxHeight` returns `nil`
    /// there, so no `ScrollView` is introduced over the map and the legend renders as it always has.
    ///
    /// The four assigned simulators' screen heights, at both ends of the type ramp, with the palette
    /// full. If this ever goes red the trade has changed and somebody should be told, not have it
    /// quietly start scrolling.
    @Test("the legend's ceiling does not bind on the devices this suite runs on")
    func theLegendCeilingDoesNotBindOnTestedDevices() {
        for screenHeight in [852.0, 874.0, 932.0, 956.0] as [CGFloat] {
            for isAccessibilitySize in [true, false] {
                let ceiling = MapLayout.legendMaxHeight(
                    screenHeight: screenHeight,
                    topInset: 54,
                    namedSpecies: MapSpeciesSlot.allCases.count,
                    isAccessibilitySize: isAccessibilitySize
                )
                #expect(
                    ceiling == nil,
                    """
                    a full legend on a \(screenHeight) pt screen (isAccessibilitySize=\
                    \(isAccessibilitySize)) is now capped at \(ceiling as Any) — it would be put \
                    in a ScrollView over the map, which takes touches the bare FlowRow does not
                    """
                )
            }
        }
    }

    /// **A slot whose species name has not arrived is not a chip**, and the reservation counts chips.
    ///
    /// `MapSpeciesLegend.named(in:)` is the one definition of which entries are drawn, and
    /// `MapHomeView` reserves through it rather than through `palette.entries`. A second copy of
    /// that filter would disagree with this one exactly when a name was still resolving — which is
    /// the first second of every launch.
    @Test("the reservation counts the chips the legend draws, not the slots it holds")
    func theReservationCountsNamedEntriesOnly() {
        let palette = MapSpeciesPalette(entries: [
            .init(slot: .a, speciesID: UUID(), count: 9, name: "Southern Magnolia"),
            .init(slot: .b, speciesID: UUID(), count: 8, name: nil),
            .init(slot: .c, speciesID: UUID(), count: 7, name: ""),
            .init(slot: .d, speciesID: UUID(), count: 6, name: "Chinese Elm")
        ])
        #expect(MapSpeciesLegend.named(in: palette).count == 2)
    }

    /// **The two blocks screen 01 draws its chrome in cannot meet**, said as arithmetic rather than
    /// as a screenshot.
    ///
    /// The top chrome's bottom edge is `topChromeBottomAX5`; the bottom chrome's top edge is the
    /// screen's height less what `bottomSlotReservedAboveAX5` stacks above the notice and the notice
    /// itself, and the notice cannot exceed `noticeMaxHeight`. Asserted over every screen size this
    /// app runs on and every legend size, in the worst case for the notice (it takes its whole
    /// budget), so the ordering holds by arithmetic and the UI guard confirms rather than discovers.
    ///
    /// The heights are the four assigned simulators' own plus the smallest phone the app supports;
    /// the insets span what those devices report.
    @Test("the reserved top chrome always ends above the reserved bottom chrome")
    func theReservedBlocksNeverMeet() {
        for screenHeight in [667.0, 852.0, 874.0, 932.0, 956.0] as [CGFloat] {
            for topInset in [20.0, 47.0, 54.0, 62.0] as [CGFloat] {
                for namedSpecies in 0...MapSpeciesSlot.allCases.count {
                    for isAccessibilitySize in [true, false] {
                        let top = MapLayout.topChromeBottomAX5(
                            screenHeight: screenHeight,
                            topInset: topInset,
                            namedSpecies: namedSpecies,
                            isAccessibilitySize: isAccessibilitySize
                        )
                        let notice = MapLayout.noticeMaxHeight(
                            screenHeight: screenHeight,
                            topInset: topInset,
                            namedSpecies: namedSpecies,
                            isAccessibilitySize: isAccessibilitySize
                        )
                        let bottom = screenHeight - MapLayout.bottomSlotReservedAboveAX5 - notice
                        #expect(
                            top <= bottom,
                            """
                            on a \(screenHeight) pt screen with a \(topInset) pt top inset, \
                            \(namedSpecies) legend chip(s), isAccessibilitySize=\
                            \(isAccessibilitySize): the reserved top chrome ends at y \(top) and \
                            the bottom chrome begins at y \(bottom) — MapLayout.noticeMaxHeight is \
                            handing the notice room the top block has already claimed
                            """
                        )
                    }
                }
            }
        }
    }

    /// **Engages.** Offered a budget the card's own unbounded AX5 height is known to exceed — half
    /// of it — the card must not grow past that budget. The budget is derived from a real
    /// measurement rather than a literal so this stays true if the shipped copy ever changes: it is
    /// always something this card needs more than.
    ///
    /// **Not through `ax5Size`.** That helper mounts in a real window with a fixed, bounded frame
    /// through several settle passes before its final unbounded `sizeThatFits` query — and once a
    /// `ScrollView` has been laid out that way, the query it ends on reports the scroll content's
    /// full, unclamped size instead of the frame's cap (watched directly: a 200pt-capped `ScrollView`
    /// measured 254pt through `ax5Size`'s exact sequence, and 200pt through a bare
    /// `UIHostingController` never mounted in a window — same view, same proposal, two different
    /// numbers). `accountProviderLabelRefusesCompressionAtAX5` above already establishes the
    /// bare-hosting-plus-`.accessibility5`-environment pattern this uses instead; a small rounding
    /// tolerance covers the sub-point remainder `ScrollView`'s own line-height quantization leaves.
    @Test("MapLocationNotice does not grow past a maxHeight it cannot fit in at AX5")
    func mapLocationNoticeScrollsWhenOfferedLessThanItNeedsAtAX5() {
        let width = Self.phoneWidth
        func size(maxHeight: CGFloat?) -> CGSize {
            let host = UIHostingController(rootView: AnyView(
                MapLocationNotice(
                    title: MapInventoryCopy.title,
                    message: MapInventoryCopy.message,
                    maxHeight: maxHeight
                )
                .environment(\.dynamicTypeSize, .accessibility5)
            ))
            return host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
        }
        let unbounded = size(maxHeight: nil)
        let budget = unbounded.height / 2
        let bounded = size(maxHeight: budget)
        let tolerance: CGFloat = 1
        #expect(
            bounded.height <= budget + tolerance,
            """
            MapLocationNotice measured \(bounded.height) pt against a \(budget) pt maxHeight (its \
            own unbounded AX5 height is \(unbounded.height) pt) — it grew past the bound it was \
            given instead of scrolling
            """
        )
    }

    /// **Unchanged at ordinary sizes.** At the default dynamic type size the shipped copy never
    /// approaches any budget large enough to matter, so a `maxHeight` generous enough to be a real
    /// screen's worth of room must make no difference at all — the same height with or without it.
    @Test("MapLocationNotice is unchanged at ordinary sizes when it is given a maxHeight")
    func mapLocationNoticeUnchangedAtOrdinarySizeWithAMaxHeight() {
        let width = Self.phoneWidth
        func size(maxHeight: CGFloat?) -> CGSize {
            let host = UIHostingController(
                rootView: MapLocationNotice(
                    title: MapInventoryCopy.title,
                    message: MapInventoryCopy.message,
                    maxHeight: maxHeight
                )
            )
            return host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
        }
        let plain = size(maxHeight: nil)
        let budgeted = size(maxHeight: Self.phoneHeight)
        #expect(
            budgeted == plain,
            """
            MapLocationNotice measured \(budgeted) with a \(Self.phoneHeight) pt maxHeight against \
            \(plain) with none, at an ordinary text size — a budget no ordinary card ever reaches \
            changed the card's rendering anyway
            """
        )
    }
}
#endif
