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
    static func ax5Size(
        of content: some View,
        width: CGFloat = phoneWidth,
        settleIterations: Int = 8
    ) async -> CGSize {
        let host = UIHostingController(
            rootView: AnyView(content.environment(\.dynamicTypeSize, .accessibility5))
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

    /// E196 §5, post-#146 shape: the three-destination share row. Fragmentation is judged by
    /// looking; what geometry can hold is that the row never forces the sheet wide — a regression
    /// to intrinsic-width cells would.
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
    /// `noticeMaxHeight(availableHeight:)`, are what the bottom slot reserves for the two controls
    /// stacked above the notice. Guarded here so a control that outgrows its reservation fails
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
