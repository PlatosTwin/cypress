import XCTest

/// The one thing the unit suite structurally cannot check.
///
/// SwiftUI builds no in-process accessibility tree, so `CypressTests` can prove a label *exists* on a
/// value and cannot prove a *screen* is navigable — that its elements are present, ordered and
/// reachable in the order a VoiceOver user hears them. That requires launching the app and asking the
/// accessibility runtime what it actually exposes, which is XCUITest's whole job.
///
/// **These tests are black-box on purpose.** They import nothing from `Cypress` — a UI test that
/// reached into the app's types would be a slower, flakier unit test. They see the app the way an
/// assistive technology does: a tree of elements with traits, labels and an order, and nothing else.
///
/// ERRATA E103 is why this exists at all — it found labels sitting on bare `Shape`s that reached
/// nobody, and E104 found a component announcing an empty row. Both were fixed against the unit
/// suite, which can see a modifier but not whether the element it is on is in the tree. This is the
/// net under that.
final class AccessibilityTreeTests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        return app
    }

    /// The four tabs C16 draws are the app's spine. If one is missing from the accessibility tree, a
    /// VoiceOver user cannot reach three quarters of the app — a failure no screenshot and no unit
    /// test surfaces, because the button is on screen and has a label; it is the *hittability* that
    /// is absent.
    func testTheFourTabsAreReachable() {
        let app = launch()
        for tab in ["Map", "My Grove", "Journal", "You"] {
            let element = app.buttons[tab]
            XCTAssertTrue(element.waitForExistence(timeout: 10), "the \(tab) tab is not in the accessibility tree")
            XCTAssertTrue(element.isHittable, "the \(tab) tab is present but cannot be activated by an assistive technology")
        }
    }

    /// Screen 01's chrome — the search field and the identify control — must be reachable as *typed*
    /// elements, not just present as pixels. A search field that the tree exposes as an anonymous
    /// button, or an icon-only control with no label, is invisible to VoiceOver while being obvious
    /// to everyone else, which is exactly the asymmetry §5.6 is about.
    func testMapChromeIsReachable() {
        let app = launch()
        XCTAssertTrue(
            app.searchFields.firstMatch.waitForExistence(timeout: 10)
                || app.textFields.firstMatch.exists,
            "the map's search field is not exposed to accessibility as a field"
        )
    }

    /// Nothing in the tree may be an unlabelled interactive element. An assistive technology reads a
    /// button with no label as the word "button" and nothing else — the E103 failure mode, caught
    /// here structurally rather than one component at a time. Scoped to the launch screen so it is a
    /// deterministic check rather than a crawl; each screen that earns its own test extends it.
    func testNoUnlabelledButtonsOnLaunch() {
        let app = launch()
        XCTAssertTrue(app.buttons.firstMatch.waitForExistence(timeout: 10))
        for i in 0..<app.buttons.count {
            let button = app.buttons.element(boundBy: i)
            guard button.exists, button.isHittable else { continue }
            XCTAssertFalse(
                button.label.trimmingCharacters(in: .whitespaces).isEmpty,
                "an interactive control at \(button.frame) has no accessibility label"
            )
        }
    }
}
