//
//  ScreenHeaderRowsTests.swift
//  CypressTests
//
//  F29 (docs/ROADMAP.md): C1 goes to two rows whenever the title cannot share one with the pill,
//  at every type size — and stays on one row at every length the mocks draw.
//
//  ── How a row count is read without a render tree ─────────────────────────────────────────
//  SwiftUI gives a test no frames to read in-process (AX5ReflowTests' header), so the row count is
//  read off heights, as two exact identities against the same header with no pill:
//
//  - **One row**: adding the pill adds no height. The pill (~24 pt) is shorter than the back circle
//    (44 pt), so a pill beside the title leaves the row exactly as tall as it was.
//  - **Two rows**: adding the pill adds exactly `headerSpacing` plus the pill's own height, and
//    nothing else. The title keeps the whole row it would have had with no pill.
//
//  The defect satisfies neither. With the pill squeezing it, the title wraps into far more lines
//  than it needs, so the header grows by much more than one pill row.
//

#if DEBUG
import SwiftUI
import Testing
@testable import Cypress

@MainActor
@Suite("C1 header rows (F29)")
struct ScreenHeaderRowsTests {

    /// The tester's phone (iPhone17_5, 390 pt), then every other width the app runs on.
    static let widths: [CGFloat] = [390, 375, 393, 402, 430, 440]

    /// A rounding margin, not a tolerance for layout: every quantity here is a sum of text line
    /// heights and tokens, and they agree to well under a point when the layout is the one claimed.
    static let epsilon: CGFloat = 0.5

    private static func height(of view: some View, width: CGFloat) async -> CGFloat {
        await AX5ReflowTests.ax5Size(
            of: view,
            width: width,
            settleIterations: 2,
            size: .large
        ).height
    }

    // MARK: - The reported case, and the pill-driven one

    /// F29 verbatim: the pin-set map for this tree, with this pill, on a 390 pt screen.
    @Test("the reported title and pill take two rows", arguments: widths)
    func theReportedHeaderTakesTwoRows(width: CGFloat) async {
        await Self.expectTwoRows(
            title: "Indian Laurel Fig Tree 'Green Gem'",
            pill: "Financial District/South Beach",
            width: width
        )
    }

    /// The same state reached from the other side: a short title and a record's name as the pill,
    /// which is what Measure, Growth and Activity carry. `Helene Strybing New Zealand Tea Tree` is
    /// the longest common name in the bundled seed (36 characters, tied).
    ///
    /// Only the widths where the pair genuinely cannot share a row. The first draft of this test
    /// also claimed `Indian Laurel Fig Tree 'Green Gem'` beside `Measure` needed two rows at 390 pt;
    /// it measured one row, title on one line, and that is the correct layout for it.
    @Test("a short title with the longest tree-name pill takes two rows", arguments: [375, 390] as [CGFloat])
    func aLongPillTakesTwoRows(width: CGFloat) async {
        await Self.expectTwoRows(
            title: MeasureCopy.screenTitle,
            pill: "Helene Strybing New Zealand Tea Tree",
            width: width
        )
    }

    private static func expectTwoRows(title: String, pill: String, width: CGFloat) async {
        let withPill = await height(of: ScreenHeader(title: title, trailingPill: pill, onBack: {}), width: width)
        let without = await height(of: ScreenHeader(title: title, onBack: {}), width: width)
        let pillAlone = await height(of: HeaderPill(pill), width: width)
        let expected = without + CypressSpacing.Component.headerSpacing + pillAlone

        #expect(
            abs(withPill - expected) <= epsilon,
            """
            at \(width) pt, '\(title)' with the pill '\(pill)' measured \(withPill) pt tall; two rows \
            would be \(expected) pt (\(without) for the title's row, \
            \(CypressSpacing.Component.headerSpacing) spacing, \(pillAlone) for the pill's)
            """
        )
    }

    // MARK: - The mocks' own lengths

    /// Every C1 pair SCREENS.md draws with a pill: 05, 11, 12, 13, 16 and 17.
    static let mockPairs: [(title: String, pill: String, style: HeaderPill.Style)] = [
        ("Check-in", "under a minute", .neutral),
        ("Growth", "Grandmother Cypress", .neutral),
        ("Almanac", "Outer Sunset", .neutral),
        ("Activity", "Grandmother Cypress", .neutral),
        ("Measure", "Grandmother Cypress", .neutral),
        ("Outbox", "3 waiting \u{00B7} offline", .amber),
    ]

    @Test("every pair the mocks draw stays on one row", arguments: widths)
    func mockPairsStayOnOneRow(width: CGFloat) async {
        for pair in Self.mockPairs {
            let withPill = await Self.height(
                of: ScreenHeader(title: pair.title, trailingPill: pair.pill, pillStyle: pair.style, onBack: {}),
                width: width
            )
            let without = await Self.height(of: ScreenHeader(title: pair.title, onBack: {}), width: width)
            #expect(
                abs(withPill - without) <= Self.epsilon,
                "at \(width) pt, '\(pair.title)' with '\(pair.pill)' measured \(withPill) pt, not the one-row \(without) pt"
            )
        }
    }

    /// Screen 12's pill is the control (`HeaderPillButton`), and it is the same row.
    @Test("the almanac's pill button stays on the title's row at the mock's length", arguments: widths)
    func pillButtonStaysOnOneRow(width: CGFloat) async {
        let withPill = await Self.height(
            of: ScreenHeader(
                title: "Almanac",
                trailingPill: "Outer Sunset",
                pillHint: "",
                onBack: {},
                onTapPill: {}
            ),
            width: width
        )
        let without = await Self.height(of: ScreenHeader(title: "Almanac", onBack: {}), width: width)
        #expect(
            abs(withPill - without) <= Self.epsilon,
            "at \(width) pt, 'Almanac' with the 'Outer Sunset' button measured \(withPill) pt, not the one-row \(without) pt"
        )
    }
}
#endif
