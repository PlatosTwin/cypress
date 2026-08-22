import XCTest

/// **Screen 01's one entrance to the visit flow, at the top of the type ramp.**
///
/// `CypressTests/AX5ReflowTests` measures `IdentifyFAB`'s own AX5 height against
/// `MapLayout.fabHeightAX5` — the guard ERRATA E243 corrected so that it measures the view rather
/// than the simulator's safe-area inset. What a measurement of the view in isolation cannot say is
/// whether the control it measured is still *reachable* once screen 01 has stacked it between the
/// recenter control above it and the location notice below it, inside one bottom-anchored block
/// whose vertical budget all three share — and, as task #252 found, underneath a top-anchored block
/// that is drawn over it and had no budget at all below the filter chip row.
///
/// Nothing in `CypressUITests` guarded this control at AX5 before this file.
/// `AccessibilityTreeTests.testMapChromeIsReachable` asserts the search field alone, and
/// `testNoUnlabeledButtonsOnLaunch` constrains only the buttons it finds, so it passes whether or
/// not this one is in the tree. `SheetExitUITests` names the FAB, as the witness that a sheet
/// finished leaving, at the default content size.
///
/// **Why this stops at reachability rather than pressing the control.** Screen 02 is `VisitFlowView`,
/// a camera flow, and a press here would make every run of this file depend on a camera session and
/// its privacy grant.
///
/// ── Why the geometry is asserted and not only the hittability ────────────────────────────────
/// This file's first version (PR #51) asserted `isHittable` and was intermittent: six runs, four
/// green and two red, on two devices, at the same commit. The cause was not the test. At AX5 the
/// species legend wrapped to four lines, the top chrome's real bottom edge reached y 492.67 on a
/// 402 pt device, and this control — at y 371–454 — was **drawn over** by a legend row for all but
/// a 14 pt band of its own height. XCUITest resolves `isHittable` by hit-testing the element's
/// activation point and then, failing that, points sampled inside its frame, so a control covered
/// everywhere except a band reports reachable exactly when the sampling happens to find the band.
/// The green runs were the luck, not the red ones.
///
/// The fix is `MapLayout.legendReserved` and `.noticeMaxHeight`, which split the room below the
/// filter chip row between the legend and the notice instead of giving all of it to the notice.
/// **It is arithmetic on the palette rather than a measurement of the rendered block**, and this
/// file is the only thing that can catch it being wrong: the first repair measured the top block's
/// real bottom edge and handed it back through `@State`, which froze on roughly one launch in
/// eight — the `GeometryReader` computing the right number while `onChange` never fired for the
/// last transition. What this file takes from the episode is that **a hittability check cannot be
/// relied on to report an occlusion it can route around**, so the occlusion is asserted directly,
/// as rectangles that must not intersect. Reachability is asserted too, and is now a claim worth
/// making rather than a coin toss.
///
/// **And the frames are read without waiting on hittability** — `settledFrame(…,
/// requireHittable: false)`. The first version of this file did wait, and a full-suite run on a
/// loaded machine caught it: `settledFrame` on the recenter control spent 30 s waiting for a
/// hittability that never came and reported *that*, where the two rectangles it was about to
/// compare were sitting there readable the whole time. Hittability is the thing an occlusion
/// removes, so a guard against occlusion cannot be allowed to depend on it. The reachability claim
/// is made by its own test, once, where a 30 s wait is the point rather than an obstacle.
final class IdentifyFABReachabilityTests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// `DebugLocationOverride.environmentKey`, repeated as a literal because this target imports
    /// nothing from `Cypress` — the same bargain every other anchor in this suite makes.
    private static let locationKey = "CYPRESS_LOCATION"

    /// `IdentifyFAB.label`, verbatim from SCREENS.md 01 §13.
    private static let fabLabel = "What tree is this?"

    /// `MapRecenterCopy.label`.
    private static let recenterLabel = "Center the map on you"

    /// `MapSpeciesLegendCopy.rowLabel`. **The last child of the top-anchored block**, and therefore
    /// the one whose bottom edge is that block's bottom edge — which is the whole of #252.
    private static let legendLabel = "Species shown in color on this map"

    /// What an absent legend means, said in the failure rather than left for the next agent to work
    /// out. `MapSpeciesLegend` "draws nothing when it has colored none", so the only way it is
    /// missing is that screen 01's camera is showing no trees.
    ///
    /// **That used to be a device-state question and is no longer one.** `launchAtAX5Denied` pins
    /// the opening camera at `DebugMapCamera.dense`, so a legend that is absent now means the map
    /// did not draw the trees that are demonstrably under it — a defect in the app or in the seed
    /// this build carries, not a camera the last run left behind. The previous wording sent three
    /// CI failures (runs 31291434427, 31294993494, 31300530216) to E216 and the harness, where
    /// there was nothing to find.
    private static let legendDescription =
        "the species legend (“\(legendLabel)”) — absent only when the map has colored no species, "
            + "and the opening camera is pinned somewhere the seed has 780 trees"

    /// AX5 with location denied. Denied is the state that puts the *longest* of the three standing
    /// sentences (`MapLocationCopy.message`) into the notice slot, which is what drives the shared
    /// block closest to its budget — the same state task #250 measured its occlusion in.
    private func launchAtAX5Denied() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment[Self.locationKey] = "denied"
        // **The legend is only in the tree when the camera has trees under it**, and until this line
        // which camera that was came from whatever the previous launch left in `map.lastCamera`. CI
        // runs 31291434427, 31294993494 and 31300530216 all failed the third test in this class after
        // the first two had passed on the same install minutes earlier — the same tree, the same
        // device, a different camera. `DebugMapCamera` carries the whole argument and the coordinate.
        DebugMapCamera.pin(app)
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()
        return app
    }

    /// **The control is in the tree and a finger can land on it.**
    ///
    /// `exists` alone would pass on the defect this guards: E248's control was in the tree the whole
    /// time it could not be pressed. `assertReachable` waits on `hittable` as well.
    ///
    /// Kept even though the test below is the stronger claim, because the two fail differently and a
    /// reader wants both sentences: this one says a finger cannot land, that one says what is in the
    /// way. Under #252's occlusion this test was the one that only *sometimes* went red.
    func testTheFABIsReachableAtAX5WithLocationDenied() {
        let app = launchAtAX5Denied()
        assertReachable(
            app.buttons[Self.fabLabel],
            "screen 01's identify control labeled “\(Self.fabLabel)”, at AX5 with location denied"
        )
    }

    /// **Reachable is not the same as unobstructed, and only one of them can be measured honestly.**
    ///
    /// `isHittable` samples points; an overlap has to reach a sampled point before the flag flips,
    /// and #252 is the record of a control that was covered for 83 % of its own area and reported
    /// reachable in four runs out of six. Two rectangles either intersect or they do not.
    ///
    /// Two neighbors, each read immediately before the assertion that uses it so that a failure
    /// names the pair it is about:
    ///
    /// - the **species legend**, the last child of the top-anchored block, which is drawn *over*
    ///   this one (`MapHomeView.chrome` applies the bottom block first, deliberately) and whose
    ///   height at AX5 is a function of how many species the visible camera has colored;
    /// - the **recenter control**, immediately above this one in the same bottom-anchored `VStack`
    ///   and the first thing pushed into it when the notice below claims more room than
    ///   `MapLayout.bottomSlotReservedAboveAX5` reserved.
    ///
    /// **The filter chip row is deliberately not a third**, and it was, in PR #51's version of this
    /// file. With the legend present its rectangle lies strictly between this control and the chip
    /// row — measured on an iPhone 16 Pro at AX5: chip row `y 158.33–218`, legend `y 230–492.67` —
    /// so no geometry reaches the chip row without crossing the legend first, and the assertion
    /// could never be the one that fires. Nor could it be red-proved for its own reason: lifting the
    /// bottom block the 430 pt needed to put the FAB on the chip row puts the chip row *over* the
    /// FAB, and the run then dies on this control's own hittability instead. An assertion that
    /// cannot be driven red is not a guard. The pair it was standing in for —
    /// `MapRecenterUITests.testTheRecenterControlClearsTheFilterChipRowAtAX5WithLocationDenied` —
    /// is guarded, on another shard, for the control immediately above this one.
    func testTheFABClearsTheChromeAroundItAtAX5WithLocationDenied() {
        let app = launchAtAX5Denied()

        let fabFrame = settledFrame(
            app.buttons[Self.fabLabel],
            "the identify control (“\(Self.fabLabel)”), at AX5 with location denied",
            requireHittable: false
        )

        let legendFrame = settledFrame(
            resolvedContainer(app, labeled: Self.legendLabel, Self.legendDescription),
            Self.legendDescription,
            requireHittable: false
        )
        XCTAssertFalse(
            fabFrame.intersects(legendFrame),
            "the identify control \(fabFrame) overlaps the species legend \(legendFrame) — the top "
                + "chrome is drawn over the bottom chrome, so this is the control covered rather "
                + "than merely crowded, and `MapLayout.noticeMaxHeight` is no longer holding the "
                + "two blocks apart (tasks #252, #258)"
        )

        // PR #51 read this frame last, and argued in a comment that the order was load-bearing:
        // `settledFrame` waited on hittability, so reading the recenter control earlier let its own
        // reachability decide the run — a red-proof of the assertion below went red on "the
        // recenter control … never became hittable" instead of on the overlap. **The order is no
        // longer load-bearing, because the coupling it worked around is gone**: every read in this
        // test passes `requireHittable: false`, so no measurement can be blocked by an occlusion,
        // which is the one thing these assertions exist to find. Kept in this order only because a
        // reader meets the neighbors in the order the screen stacks them.
        let recenterFrame = settledFrame(
            app.buttons[Self.recenterLabel],
            "the recenter control (“\(Self.recenterLabel)”)",
            requireHittable: false
        )
        XCTAssertFalse(
            fabFrame.intersects(recenterFrame),
            "the identify control \(fabFrame) overlaps the recenter control \(recenterFrame) — the "
                + "bottom block's own stack has collapsed onto itself, so the room "
                + "`MapLayout.bottomSlotReservedAboveAX5` reserves above the notice is smaller than "
                + "what the two controls actually occupy at AX5"
        )
    }

    /// `MapLayout.compassColumnReserved` — `compassSize` (44) + `chipRowTop` (12). A literal for the
    /// same reason every label in this file is one: this target imports nothing from `Cypress`.
    private static let compassColumnReserved: CGFloat = 56

    /// **The species legend keeps out of MapKit's compass column, and inside the phone** (PR #102).
    ///
    /// The owner ruled a compass onto screen 01 on 2026-08-21 (RULINGS R80, item 6b). MapKit draws
    /// it in the map's top-**trailing** ornament slot, *underneath* this chrome, and the legend
    /// hangs down the same side — so a chip long enough to reach the trailing edge does not crowd
    /// the compass, it covers it and takes its taps. Measured on an iPhone 16 Pro Max at AX5 before
    /// the fix: the legend reported `(16.0, 230.0, 446.0, 262.67)` — **446 pt wide on a 440 pt
    /// screen**, running to x 462 — against a compass at x 391–435. A tap aimed at "put me back to
    /// north" selected `Sycamore, London Plane` and narrowed the map to London planes instead.
    ///
    /// **Two assertions, because there were two defects and either can return alone.** The legend
    /// running past the screen is `FlowRow`'s: it measured every chip at its *ideal* width and placed
    /// it there, so a chip wider than its column simply overflowed. The legend reaching the compass
    /// is `MapSpeciesLegend.trailingReserve`'s. Fixing the second without the first buys nothing —
    /// a reserve on a row that overflows its column is not a reserve — so both are named here.
    ///
    /// **Where this bites, and where it cannot** (PR #102 verification). The column assertion goes
    /// red on widths where the legend actually reaches the compass's column — measured on a 402 pt
    /// iPhone 16 Pro, where removing `MapSpeciesLegend.trailingReserve` takes the legend's `maxX`
    /// from 330 to 373.67 against a column starting at 346. On a 440 pt iPhone 16 Pro Max the legend
    /// frame is byte-identical with and without the reserve, so **a red-proof attempted only there
    /// will look like a dead assertion and it is not one**. Check it at 402 pt before concluding
    /// this test does nothing.
    ///
    /// **Asserted as arithmetic against the screen's own trailing edge, not against the compass.**
    /// MapKit's compass is not a child of the map element in the accessibility tree — the map's
    /// subtree dump is a leaf — so there is no handle to read a rectangle from, and the two-rectangle
    /// pattern the test above uses is unavailable. What *is* available is the column the compass is
    /// known to occupy, which is a constant off the trailing edge on every width. That is the same
    /// bargain `MapLayout`'s own comment strikes for the reservation it cannot measure.
    func testTheSpeciesLegendClearsTheCompassColumnAtAX5WithLocationDenied() {
        let app = launchAtAX5Denied()

        let screen = app.windows.firstMatch.frame
        let legendFrame = settledFrame(
            resolvedContainer(app, labeled: Self.legendLabel, Self.legendDescription),
            Self.legendDescription,
            requireHittable: false
        )

        XCTAssertLessThanOrEqual(
            legendFrame.maxX,
            screen.maxX,
            "the species legend \(legendFrame) runs past the trailing edge of the \(screen.width) pt "
                + "screen — `FlowRow` is placing a chip at its ideal width instead of the width of "
                + "the column it was given, so the widest species name in view is drawn off the "
                + "side of the phone (PR #102)"
        )

        let compassColumnStart = screen.maxX - Self.compassColumnReserved
        XCTAssertLessThanOrEqual(
            legendFrame.maxX,
            compassColumnStart,
            "the species legend \(legendFrame) reaches into the trailing "
                + "\(Self.compassColumnReserved) pt that MapKit's compass occupies (x "
                + "\(compassColumnStart) onward on this \(screen.width) pt screen). The legend is "
                + "drawn OVER the basemap, so this is the compass covered and its taps taken, not "
                + "merely crowded — a press meant for north applies a species filter instead. "
                + "`MapSpeciesLegend.trailingReserve` is what holds this column open (PR #102)"
        )
    }

    /// **The two blocks screen 01 draws its chrome in do not meet** (task #252).
    ///
    /// The test above is about one control. This is about the reservation that keeps every control
    /// in the bottom block clear of every element in the top one, asserted where it is decided: the
    /// legend is the last child of the top block, the recenter control is the first child of the
    /// bottom block, and `MapLayout.noticeMaxHeight` exists to keep the second below the first.
    ///
    /// It is the **tighter** of the two guards and the one that goes red first, because
    /// `noticeMaxHeight` holds back exactly `MapLayout.chipRowTop` between them while the FAB sits a
    /// further 56 pt down the stack. Asserted as an ordering of edges rather than as that gap's
    /// value: the number is `MapLayout`'s to choose and this suite has no business pinning it, but
    /// which edge is above which is the claim the reservation actually makes.
    func testTheTopChromeStaysClearOfTheBottomChromeAtAX5WithLocationDenied() {
        let app = launchAtAX5Denied()

        let legendFrame = settledFrame(
            resolvedContainer(app, labeled: Self.legendLabel, Self.legendDescription),
            Self.legendDescription,
            requireHittable: false
        )
        let recenterFrame = settledFrame(
            app.buttons[Self.recenterLabel],
            "the recenter control (“\(Self.recenterLabel)”)",
            requireHittable: false
        )
        XCTAssertLessThanOrEqual(
            legendFrame.maxY,
            recenterFrame.minY,
            "the top chrome ends at y \(legendFrame.maxY) and the bottom chrome begins at y "
                + "\(recenterFrame.minY) — the top block is drawn over the bottom one, so every "
                + "point of that overlap is a control the reader cannot see or press. "
                + "`MapLayout.noticeMaxHeight` is reserving less than the top chrome actually "
                + "occupies — either `legendChipHeightAX5` no longer bounds one legend chip, or "
                + "something new has been added to the top block below the chip row without a "
                + "reservation of its own (task #258)"
        )
    }
}
