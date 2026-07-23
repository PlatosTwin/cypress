import XCTest

/// The accessibility tree of every screen behind the map (ERRATA E117).
///
/// `AccessibilityTreeTests` (E116) reads the tree of screen 01 and its chrome. That is one screen out
/// of nineteen, and it is the only one reachable from a cold launch without tapping a MapKit
/// annotation — which is not a thing a test can do reliably, because the basemap renders
/// asynchronously and puts its pins wherever the camera settles. So the other sixteen had never been
/// read by anything, and "the app is accessible" rested on a suite that had only ever seen the map.
///
/// `DebugDeepLink` is the door: the test names a screen in the launch environment and the app opens
/// it, resolving a real record out of the real 195,309-row seed. What is asserted here is what E116
/// asserts, on screens E116 cannot reach.
///
/// **Still black-box.** Nothing here imports `Cypress`. The screen names are strings and the anchors
/// are the words the app says out loud, which is the whole point: if a label changes, a test that
/// pins the old one should fail, because a VoiceOver user's map of the app just changed too.
///
/// **What each test proves, in order:**
/// 1. The screen *arrived* — the deep link is not a no-op that quietly leaves the app on screen 01
///    while fourteen tests report the names of screens they never visited.
/// 2. Nothing interactive on it is unlabelled — the E103 failure mode.
/// 3. It can be left again — a pushed screen with no reachable Back is a trap.
final class DeepLinkVoiceOverTests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: - Screens

    func testTreeProfile()   { check("treeProfile",   anchor: "Tree",            pushed: true) }
    func testVacantSite()    { check("site",          anchor: "No tree at this site", pushed: true) }
    func testSpecies()       { check("species",       anchor: "Field guide",     pushed: true) }
    func testCheckIn()       { check("checkIn",       anchor: "Check-in",        pushed: true) }
    func testReport()        { check("report",        anchor: "Report an issue", pushed: true) }
    func testGrowthHistory() { check("growthHistory", anchor: "Growth",          pushed: true) }
    func testActivity()      { check("activity",      anchor: "Activity",        pushed: true) }
    func testMeasure()       { check("measure",       anchor: "Measure",         pushed: true) }
    func testOutbox()        { check("outbox",        anchor: "Outbox",          pushed: true) }

    /// 09 and 10 are `fullScreenCover`s rather than pushes, so they have no Back button — they have a
    /// close, and the screen they cover stays in the hierarchy underneath. That difference is what
    /// `testAModalIsolatesTheScreenBehindIt` is about.
    func testCareLog()       { check("careLog",       anchor: "Care log",        pushed: false) }
    func testShare()         { check("share",         anchor: "Share this tree", pushed: false) }

    /// The three tab roots other than the map. No Back, because a tab root has nowhere to go back to.
    func testGroveTab()      { check("grove",         anchor: "Quiet collecting", pushed: false) }
    func testJournalTab()    { check("journal",       anchor: "Almanac",          pushed: false) }
    func testYouTab()        { check("you",           anchor: "Your contributions", pushed: false) }

    // MARK: - What a modal owes the screen it covers

    /// A VoiceOver user must not be able to swipe onto the screen behind a modal.
    ///
    /// This is the failure that is invisible to everyone who can see: sighted users cannot reach the
    /// map behind the care-log sheet because the sheet is drawn over it, and that feels like
    /// containment. It is only containment if the accessibility runtime agrees — otherwise the swipe
    /// order runs straight off the sheet and onto a map the user cannot see, and the "Search" they
    /// then activate belongs to a screen that is not on screen.
    ///
    /// Both of these covers are presented over screen 01, whose chrome is the thing that must go
    /// quiet. Asserted through `isHittable` rather than `exists`, because the presenting screen stays
    /// in the hierarchy by design (`RootView`'s one `fullScreenCover`) — being *there* is fine, being
    /// *reachable* is not.
    func testAModalIsolatesTheScreenBehindIt() {
        for screen in ["careLog", "share"] {
            let app = launch(screen)
            guard arrive(app, screen: screen, anchor: screen == "careLog" ? "Care log" : "Share this tree") else {
                continue
            }
            for behind in ["Map", "My Grove", "Journal", "You"] {
                let tab = app.buttons[behind]
                if tab.exists {
                    XCTAssertFalse(
                        tab.isHittable,
                        "\(screen): the \(behind) tab behind the cover can still be activated, so an "
                            + "assistive technology can walk off the sheet onto a screen that is not visible"
                    )
                }
            }
            app.terminate()
        }
    }

    // MARK: - Duplication

    /// Nothing may be announced twice.
    ///
    /// The E104 failure mode as a rule rather than a component: a container that carries a label *and*
    /// exposes a child carrying the same one is two stops on the same words, and a screen full of them
    /// is a screen that takes twice as long to hear. Checked as containment rather than adjacency,
    /// because that is the shape the defect actually takes — a labelled wrapper around a labelled leaf.
    ///
    /// **`allElementsBoundByIndex` is used here as a set, never as an order, and that restriction is
    /// load-bearing (ERRATA E118).** Its sequence is the query engine's match order, which is neither
    /// the accessibility hierarchy's nor the screen's geometry: on screen 05 it returns the pinned
    /// `Save check-in` at y=710 *before* the `Back` at y=69, while the hierarchy has Back nine
    /// positions earlier. A reading-order assertion built on it reports defects that do not exist. If
    /// VoiceOver's order is ever tested here, it has to come from recursing the element tree.
    func testNothingIsAnnouncedTwice() {
        continueAfterFailure = true
        defer { continueAfterFailure = false }

        for (screen, anchor) in [
            ("treeProfile", "Tree"), ("site", "No tree at this site"), ("species", "Field guide"),
            ("growthHistory", "Growth"), ("activity", "Activity"), ("outbox", "Outbox"),
        ] {
            let app = launch(screen)
            guard arrive(app, screen: screen, anchor: anchor) else { continue }

            let texts = app.staticTexts.allElementsBoundByIndex.filter { $0.isHittable }
            for (index, outer) in texts.enumerated() {
                let label = outer.label.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !label.isEmpty else { continue }
                for inner in texts[(index + 1)...] where inner.label
                    .trimmingCharacters(in: .whitespacesAndNewlines) == label {
                    // Containment, not mere repetition: two different rows may legitimately say the
                    // same words. One element drawn inside another saying them is the defect.
                    XCTAssertFalse(
                        outer.frame.contains(inner.frame),
                        "\(screen): '\(label)' is announced by an element at \(outer.frame) and again "
                            + "by one inside it at \(inner.frame), so it is heard twice"
                    )
                }
            }
            app.terminate()
        }
    }

    // MARK: - Harness

    private func launch(_ screen: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment[Self.screenKey] = screen
        app.launch()
        return app
    }

    private static let screenKey = "CYPRESS_SCREEN"

    /// The one banner that means the harness itself failed, rather than the screen.
    ///
    /// `DebugDeepLink` draws its failures instead of logging them, so that a resolution that found no
    /// record cannot masquerade as a screen that opened. Checked before anything else is reported,
    /// because "no record nearest 37.7596, -122.4269" is an answer and "'Growth' is not in the tree"
    /// is a riddle.
    private func deepLinkFailure(_ app: XCUIApplication) -> String? {
        let banner = app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH %@", "DEEP LINK FAILED"))
            .firstMatch
        return banner.exists ? banner.label : nil
    }

    /// Waits for the screen and reports precisely which way it did not arrive.
    @discardableResult
    private func arrive(
        _ app: XCUIApplication,
        screen: String,
        anchor: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        let target = app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH %@", anchor))
            .firstMatch
        // Generous: a cold launch opens the database, runs migrations and attaches a 195,309-row seed
        // before the first screen can resolve a record.
        guard target.waitForExistence(timeout: 30) else {
            if let failure = deepLinkFailure(app) {
                XCTFail("\(screen): \(failure)", file: file, line: line)
            } else {
                XCTFail(
                    "\(screen): the app launched but '\(anchor)' never appeared in the accessibility "
                        + "tree — either the screen did not open, or its title is not exposed",
                    file: file, line: line
                )
            }
            return false
        }
        return true
    }

    /// Arrive, then read the tree.
    private func check(
        _ screen: String,
        anchor: String,
        pushed: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let app = launch(screen)
        guard arrive(app, screen: screen, anchor: anchor, file: file, line: line) else { return }

        assertEveryControlIsLabelled(app, screen: screen, file: file, line: line)

        if pushed {
            // A pushed screen covers the tab root, so the bottom bar is gone. Its absence is a second,
            // independent witness that the deep link actually navigated rather than landing on a tab
            // root that happens to contain the anchor text somewhere.
            XCTAssertFalse(
                app.buttons["My Grove"].isHittable,
                "\(screen): the bottom tab bar is still reachable, so this is a tab root rather than "
                    + "the pushed screen the test asked for",
                file: file, line: line
            )

            let back = app.buttons["Back"]
            XCTAssertTrue(
                back.exists,
                "\(screen): there is no Back control in the accessibility tree, so this screen cannot "
                    + "be left without a swipe gesture an assistive technology may not perform",
                file: file, line: line
            )
            XCTAssertTrue(
                back.isHittable,
                "\(screen): Back is in the tree but cannot be activated",
                file: file, line: line
            )
        }

        app.terminate()
    }

    /// No interactive element anywhere in the tree may be unlabelled.
    ///
    /// Scoped to what is *hittable*, for the same reason E116's version is: an element behind a cover
    /// or scrolled off the bottom is in the hierarchy without being reachable, and holding it to the
    /// same standard would report failures a user cannot encounter.
    private func assertEveryControlIsLabelled(
        _ app: XCUIApplication,
        screen: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let controls: [(String, XCUIElementQuery)] = [
            ("button", app.buttons),
            ("text field", app.textFields),
            ("search field", app.searchFields),
            ("secure field", app.secureTextFields),
            ("switch", app.switches),
            ("slider", app.sliders),
            ("link", app.links),
        ]
        var checked = 0
        for (kind, query) in controls {
            for index in 0..<query.count {
                let element = query.element(boundBy: index)
                guard element.exists, element.isHittable else { continue }
                checked += 1
                XCTAssertFalse(
                    element.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "\(screen): a \(kind) at \(element.frame) has no accessibility label, so an "
                        + "assistive technology announces it as its type and nothing else",
                    file: file, line: line
                )
            }
        }
        // A screen with no reachable control at all is not a screen this test read — it is a screen
        // that had not finished loading. Every one of these has at least a Back or a close.
        XCTAssertGreaterThan(
            checked, 0,
            "\(screen): no interactive control was reachable, so nothing was actually checked",
            file: file, line: line
        )
    }
}
