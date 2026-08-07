import XCTest

/// TEMPORARY diagnostic — task #252. Not for merge. Deleted before the PR.
final class FABFlakeDiagTests: XCTestCase {

    private static let locationKey = "CYPRESS_LOCATION"
    private static let fabLabel = "What tree is this?"
    private static let recenterLabel = "Center the map on you"

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    private func launchAtAX5Denied() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment[Self.locationKey] = "denied"
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()
        return app
    }

    @discardableResult
    private func sample(_ app: XCUIApplication, _ tag: String) -> Bool {
        let fab = app.buttons[Self.fabLabel]
        let rec = app.buttons[Self.recenterLabel]
        let t0 = Date()
        let fabExists = fab.exists
        let tExists = Date().timeIntervalSince(t0)
        let t1 = Date()
        let fabHit = fabExists ? fab.isHittable : false
        let tHit = Date().timeIntervalSince(t1)
        let fabFrame = fabExists ? fab.frame : .zero
        let recHit = rec.exists ? rec.isHittable : false
        print("DIAG[\(tag)] fab exists=\(fabExists) hit=\(fabHit) frame=\(fabFrame) "
            + "| recenter exists=\(rec.exists) hit=\(recHit) frame=\(rec.frame) "
            + "| t_exists=\(String(format: "%.3f", tExists))s t_hit=\(String(format: "%.3f", tHit))s")
        return fabHit
    }

    /// Dump every element whose frame contains the FAB's center point, in tree order.
    private func dumpOverlaps(_ app: XCUIApplication, _ tag: String) {
        let fab = app.buttons[Self.fabLabel]
        guard fab.exists else { print("DIAG[\(tag)] no fab"); return }
        let f = fab.frame
        let center = CGPoint(x: f.midX, y: f.midY)
        print("DIAG[\(tag)] fab center \(center)")
        for (type, name) in [
            (XCUIElement.ElementType.button, "button"),
            (.other, "other"),
            (.image, "image"),
            (.staticText, "staticText")
        ] {
            let all = app.descendants(matching: type).allElementsBoundByAccessibilityElement
            let hits = all.filter { $0.frame.contains(center) }
            print("DIAG[\(tag)] \(name): total=\(all.count) containing-center=\(hits.count)")
            for h in hits.prefix(25) {
                print("DIAG[\(tag)]   \(name) label=\"\(h.label)\" id=\"\(h.identifier)\" "
                    + "frame=\(h.frame) hit=\(h.isHittable)")
            }
        }
    }

    /// Escalating accessibility pressure. Does the FAB's hittability degrade with it?
    func testEscalatingEnumerationPressure() {
        let app = launchAtAX5Denied()
        XCTAssertTrue(app.buttons[Self.fabLabel].waitForExistence(timeout: 30), "fab never appeared")
        sample(app, "t0-baseline")

        for round in 1...5 {
            let t0 = Date()
            let buttons = app.buttons.allElementsBoundByAccessibilityElement
            let dt = Date().timeIntervalSince(t0)
            print("DIAG[round\(round)] buttons enumerated=\(buttons.count) in "
                + "\(String(format: "%.2f", dt))s")
            let hit = sample(app, "after-round\(round)")
            if !hit {
                print("DIAG[round\(round)] *** FAB NOT HITTABLE — dumping overlaps ***")
                dumpOverlaps(app, "round\(round)")
                // Does it recover on its own?
                for t in 1...10 {
                    Thread.sleep(forTimeInterval: 1)
                    if sample(app, "recover-r\(round)-t\(t)") { break }
                }
                return
            }
        }
        print("DIAG: never went unhittable under 5 rounds of enumeration")
    }

    /// The suite's own shape: does an app relaunch inside one test process behave differently?
    func testRepeatedRelaunches() {
        for launchIndex in 1...4 {
            let app = launchAtAX5Denied()
            XCTAssertTrue(
                app.buttons[Self.fabLabel].waitForExistence(timeout: 30),
                "fab never appeared on launch \(launchIndex)"
            )
            sample(app, "launch\(launchIndex)-t0")
            let buttons = app.buttons.allElementsBoundByAccessibilityElement
            print("DIAG[launch\(launchIndex)] buttons=\(buttons.count)")
            let hit = sample(app, "launch\(launchIndex)-after-enum")
            if !hit {
                print("DIAG[launch\(launchIndex)] *** NOT HITTABLE ***")
                dumpOverlaps(app, "launch\(launchIndex)")
            }
            app.terminate()
        }
    }

    /// What is actually under the FAB on a healthy launch — the annotation-overlap hypothesis's
    /// own evidence, taken when nothing is failing.
    func testWhatSitsUnderTheFAB() {
        let app = launchAtAX5Denied()
        XCTAssertTrue(app.buttons[Self.fabLabel].waitForExistence(timeout: 30), "fab never appeared")
        sample(app, "healthy")
        dumpOverlaps(app, "healthy")
    }
}
