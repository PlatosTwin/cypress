import XCTest

/// **TEMPORARY (#258) — deleted before this work lands.**
///
/// The abandoned repair for this ticket passed `IdentifyFABReachabilityTests` and still shipped an
/// occlusion on roughly one launch in eight, because the number it depended on was delivered by an
/// edge-triggered channel out of the layout system that sometimes missed its last edge. Three
/// launches of a guard cannot see a defect at that rate. This launches many, asserts the same
/// ordering each time, and reports how many launches it took.
final class LaunchRepeatDiagTests: XCTestCase {

    private static let locationKey = "CYPRESS_LOCATION"
    private static let legendLabel = "Species shown in color on this map"
    private static let recenterLabel = "Center the map on you"
    private static let fabLabel = "What tree is this?"

    private static let launches = 40

    func testTheChromeNeverOverlapsAcrossManyLaunches() {
        var overlaps: [String] = []
        var observed = 0
        for launch in 1...Self.launches {
            let app = XCUIApplication()
            app.launchEnvironment[Self.locationKey] = "denied"
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
            ]
            app.launch()

            let legend = app.otherElements[Self.legendLabel].exists
                ? app.otherElements[Self.legendLabel]
                : app.scrollViews[Self.legendLabel]
            XCTAssertTrue(
                legend.waitForExistence(timeout: 30),
                "launch \(launch): the species legend never appeared — the opening camera is "
                    + "showing no trees (E216), which makes this launch no evidence either way"
            )
            // Well past the point the legend has finished growing from two rows to four: the
            // frozen launches of the abandoned repair were frozen from the first sample to the
            // last, and a hand launch of that build converged inside ten seconds.
            Thread.sleep(forTimeInterval: 6)

            let legendFrame = legend.frame
            let recenterFrame = app.buttons[Self.recenterLabel].frame
            let fabFrame = app.buttons[Self.fabLabel].frame
            observed += 1
            if legendFrame.maxY > recenterFrame.minY || legendFrame.intersects(fabFrame) {
                overlaps.append(
                    "launch \(launch): legend \(legendFrame) recenter \(recenterFrame) fab \(fabFrame)"
                )
            }
            print(
                "LAUNCH-REPEAT launch=\(launch) legendMaxY=\(legendFrame.maxY) "
                    + "recenterMinY=\(recenterFrame.minY) fabMinY=\(fabFrame.minY)"
            )
            app.terminate()
        }
        print("LAUNCH-REPEAT observed=\(observed) overlaps=\(overlaps.count)")
        XCTAssertTrue(
            overlaps.isEmpty,
            "the top chrome overlapped the bottom chrome on \(overlaps.count) of \(observed) "
                + "launches:\n" + overlaps.joined(separator: "\n")
        )
    }
}
