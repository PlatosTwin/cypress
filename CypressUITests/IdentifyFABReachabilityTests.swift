import XCTest

/// **Screen 01's one entrance to the visit flow, at the top of the type ramp.**
///
/// `CypressTests/AX5ReflowTests` measures `IdentifyFAB`'s own AX5 height against
/// `MapLayout.fabHeightAX5` — the guard ERRATA E243 corrected so that it measures the view rather
/// than the simulator's safe-area inset. What a
/// measurement of the view in isolation cannot say is whether the control it measured is still
/// *reachable* once screen 01 has stacked it between the recenter control above it and the location
/// notice below it, inside one bottom-anchored block whose vertical budget all three share. That is
/// exactly the shape ERRATA E248 found the recenter control failing in: present in the accessibility
/// tree, `isHittable == false`, under a green unit suite that had measured every constant correctly.
///
/// `MapRecenterUITests.testTheRecenterControlClearsTheFilterChipRowAtAX5WithLocationDenied` now
/// guards the control above this one. Nothing guarded this one. The FAB appears in
/// `SheetExitUITests` only as the witness that a sheet finished leaving, and only at the default
/// content size, so no run exercised it at AX5. This file is the permanent guard PR #45's review
/// asked for (task #252).
///
/// **Why this stops at reachability rather than pressing the control.** Screen 02 is `VisitFlowView`,
/// a camera flow, and a press here would make every run of this file depend on a camera session and
/// its privacy grant. `AccessibilityTreeTests` already asserts screen 01's identify control is in the
/// tree as a typed button; what was missing is whether AX5 leaves it somewhere a finger can land.
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

    /// `MapFilterCopy.rowLabel` — the chip row's own named accessibility group.
    private static let chipRowLabel = "Filter trees"

    /// AX5 with location denied. Denied is the state that puts the *longest* of the four standing
    /// sentences (`MapLocationCopy.message`) into the notice slot, which is what drives the shared
    /// block closest to its budget — the same state task #250 measured the occlusion in.
    private func launchAtAX5Denied() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment[Self.locationKey] = "denied"
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()
        return app
    }

    /// The row's named container rides on a `ScrollView` since the row became one (#166), and which
    /// element type XCUITest files a labeled SwiftUI scroller under is not a contract worth pinning
    /// (`MapFilterAccessibilityTests.rowContainer`) — both spellings are accepted.
    private func chipRow(_ app: XCUIApplication) -> XCUIElement {
        let other = app.otherElements[Self.chipRowLabel]
        return other.exists ? other : app.scrollViews[Self.chipRowLabel]
    }

    /// **The control is in the tree and a finger can land on it.**
    ///
    /// `exists` alone would pass on the defect this guards: E248's control was in the tree the whole
    /// time it could not be pressed. `assertReachable` waits on `hittable` as well.
    func testTheFABIsReachableAtAX5WithLocationDenied() {
        let app = launchAtAX5Denied()
        assertReachable(
            app.buttons[Self.fabLabel],
            "screen 01's identify control labeled “\(Self.fabLabel)”, at AX5 with location denied"
        )
    }

    /// **Reachable is not the same as disjoint, and only one of them stays true by accident.**
    ///
    /// A control can remain hittable while its frame already overlaps a neighbor, because
    /// `isHittable` samples a point rather than the rectangle: the overlap has to reach that one
    /// point before the flag flips. E248's occlusion was found at the moment it crossed that
    /// threshold, which means the geometry had already been wrong for some interval that every
    /// hittability check in the suite reported as healthy.
    ///
    /// So this asserts the geometry directly, against both neighbors that can reach the FAB: the
    /// filter chip row, which is anchored to the top and grows down, and the recenter control, which
    /// sits immediately above the FAB in the same bottom-anchored `VStack` and is the first thing
    /// pushed into it when the notice below claims more room than `bottomSlotReservedAboveAX5`
    /// reserved for the stack.
    func testTheFABClearsTheChromeAroundItAtAX5WithLocationDenied() {
        let app = launchAtAX5Denied()

        let fabFrame = settledFrame(
            app.buttons[Self.fabLabel],
            "the identify control (“\(Self.fabLabel)”), at AX5 with location denied"
        )
        let chipRowFrame = settledFrame(chipRow(app), "the filter chip row (“\(Self.chipRowLabel)”)")

        XCTAssertFalse(
            fabFrame.intersects(chipRowFrame),
            "the identify control \(fabFrame) overlaps the filter chip row \(chipRowFrame) — the "
                + "top chrome now reaches down into the control's own space, which is how a control "
                + "ends up present in the tree and not hittable (E248)"
        )

        // Read AFTER the assertion above, and the order is load-bearing rather than stylistic. The
        // recenter control sits between the chip row and the FAB, so any layout that pushes the FAB
        // up into the chip row has already pushed the recenter control further into it — and the
        // chip row draws over both (E248). Reading all three frames first therefore made the
        // assertion above unreachable: `settledFrame` waits on hittability, so the run died on the
        // recenter control's own reachability and reported that instead. Red-proving this test found
        // it; the first arrangement went red for the wrong reason.
        let recenterFrame = settledFrame(
            app.buttons[Self.recenterLabel],
            "the recenter control (“\(Self.recenterLabel)”)"
        )
        XCTAssertFalse(
            fabFrame.intersects(recenterFrame),
            "the identify control \(fabFrame) overlaps the recenter control \(recenterFrame) — the "
                + "bottom block's own stack has collapsed onto itself, so the room "
                + "`MapLayout.bottomSlotReservedAboveAX5` reserves above the notice is smaller than "
                + "what the two controls actually occupy at AX5"
        )
    }
}
