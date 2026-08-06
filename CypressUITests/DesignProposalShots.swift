import XCTest

/// ⚠️ THROWAWAY CAMERA RIG (branch `design/14-proposals`). Not a test — it asserts almost nothing.
///
/// It launches the deep-link door once per (screen, variant, type size) and writes a PNG, so the
/// proposals in `docs/design-proposals/2026-08-06-task14.md` can be looked at in the real app on a
/// real seed rather than described. Light/dark is chosen OUTSIDE this file, with
/// `xcrun simctl ui <udid> appearance <light|dark>`, so the same list runs twice.
///
/// `CYPRESS_SHOT_DIR` (forwarded as `TEST_RUNNER_CYPRESS_SHOT_DIR`) chooses where the PNGs land.
final class DesignProposalShots: XCTestCase, DeepLinkHarness {

    private static var appearanceTag: String {
        ProcessInfo.processInfo.environment["CYPRESS_SHOT_TAG"] ?? "untagged"
    }

    /// Every shot the proposal document references, in one launch loop.
    func testPhotographEveryCandidate() {
        continueAfterFailure = true

        let shots: [(screen: String, anchor: String, variant: String, ax5: Bool, name: String)] = [
            // Item 1 · screen 16's readout, and screen 17's amber.
            ("measure", "Measure", "",     false, "16-measure-shipped"),
            ("measure", "Measure", "16a",  false, "16-measure-16a"),
            ("measure", "Measure", "16b",  false, "16-measure-16b"),
            ("outbox",  "Outbox",  "",     false, "17-outbox-shipped"),
            ("outbox",  "Outbox",  "17a",  false, "17-outbox-17a"),
            ("outbox",  "Outbox",  "17b",  false, "17-outbox-17b"),
            // Item 2 · screen 10's share card. Layout is at stake, so AX5 too.
            ("share",   "Share",   "",     false, "10-share-shipped"),
            ("share",   "Share",   "10a",  false, "10-share-10a"),
            ("share",   "Share",   "10b",  false, "10-share-10b"),
            ("share",   "Share",   "10c",  false, "10-share-10c"),
            ("share",   "Share",   "",     true,  "10-share-shipped-ax5"),
            ("share",   "Share",   "10a",  true,  "10-share-10a-ax5"),
            // Item 3 · the vacant-site tile on screen 12.
            ("journal", "",        "",     false, "12-journal-shipped"),
            ("journal", "",        "12a",  false, "12-journal-12a"),
            ("journal", "",        "12b",  false, "12-journal-12b"),
        ]

        for shot in shots {
            let app = XCUIApplication()
            app.launchEnvironment["CYPRESS_SCREEN"] = shot.screen
            // R58: pin the app's location state so the almanac has a neighborhood to speak about
            // and nothing depends on whether this device happens to hold a fix.
            app.launchEnvironment["CYPRESS_LOCATION"] = "37.78485,-122.4215"
            if !shot.variant.isEmpty {
                app.launchEnvironment["CYPRESS_DESIGN"] = shot.variant
            }
            if shot.ax5 {
                app.launchArguments += [
                    "-UIPreferredContentSizeCategoryName",
                    "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
                ]
            }
            app.launch()

            if !shot.anchor.isEmpty {
                let target = app.staticTexts
                    .matching(NSPredicate(format: "label BEGINSWITH %@", shot.anchor))
                    .firstMatch
                if !target.waitForExistence(timeout: 60) {
                    XCTFail("\(shot.name): never arrived — \(deepLinkFailure(app) ?? "no banner")")
                    app.terminate()
                    continue
                }
            } else {
                // The journal tab has no single unambiguous anchor string; wait for the tab bar,
                // which only exists once a tab root has drawn.
                _ = app.buttons["Journal"].waitForExistence(timeout: 60)
            }
            // Let the push/tab transition settle before the shutter — a screenshot taken mid-slide
            // is a screenshot of two screens.
            Thread.sleep(forTimeInterval: 2.0)

            record(app, named: "\(shot.name)-\(Self.appearanceTag)")
            app.terminate()
        }
    }

    private func record(_ app: XCUIApplication, named name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let directory = ProcessInfo.processInfo.environment["CYPRESS_SHOT_DIR"]
            ?? NSTemporaryDirectory()
        let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
        try? shot.pngRepresentation.write(to: url)
        print("DESIGN SHOT \(url.path)")
    }
}
