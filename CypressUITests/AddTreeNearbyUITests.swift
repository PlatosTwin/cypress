//
//  AddTreeNearbyUITests.swift
//  CypressUITests
//
//  The owner's ruling of 2026-11-14 on the running app: a tree within 10 m of another is noted, not
//  refused. The Add this tree screen opens 4 m from a community tree already on record
//  (`CYPRESS_SCREEN=addTreeNearby`, with a photograph already chosen). Before any tap it shows the
//  "ALREADY ON RECORD" note in the owner's words, with the tree listed under it, and the Add this
//  tree button is active. One tap adds the tree, and the profile of the new tree opens with the
//  Move pin control that only a tree this phone added offers.
//
//  Black-box like the rest of this target: nothing imports `Cypress`, and every literal is a copy
//  constant repeated by hand (`VisitAddTreeCopy`, `MovePinCopy`). If a string is renamed this fails,
//  which is correct: the words a reader acts on changed.
//

import XCTest

final class AddTreeNearbyUITests: XCTestCase, DeepLinkHarness {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private enum Copy {
        static let label = "ALREADY ON RECORD"
        static let body =
            "Something is already on record within 10 m of here. Add this tree only if it is a different one."
        static let cta = "Add this tree"
        static let candidate = "Unidentified tree"
        static let movePin = "Move pin"
        static let fromGPS = "position from GPS"
        /// The two sentences of the refusal the ruling removed.
        static let refused = ["Nothing was added.", "If one of these is the tree in front of you, open it."]
    }

    func testATreeWithinTenMetersIsNotedAndOneTapAddsIt() {
        let app = launch("addTreeNearby")

        let label = app.staticTexts[Copy.label]
        guard label.waitForExistence(timeout: 60) else {
            XCTFail(
                deepLinkFailure(app).map { "addTreeNearby: \($0)" }
                    ?? "addTreeNearby: the add screen drew no '\(Copy.label)' note before any tap"
            )
            return
        }
        XCTAssertTrue(app.staticTexts[Copy.body].exists, "the note does not say the owner's two sentences")
        for sentence in Copy.refused {
            let old = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", sentence)).firstMatch
            XCTAssertFalse(old.exists, "the screen still says '\(sentence)'")
        }
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", Copy.candidate)).firstMatch
        XCTAssertTrue(row.exists, "the note lists no tree under it")
        scrollIntoView(app.staticTexts[Copy.body], in: app)
        record(app, named: "note-default")

        let add = app.buttons[Copy.cta]
        assertReachable(add, "the Add this tree button")
        XCTAssertTrue(add.isEnabled, "the note disabled the Add this tree button")
        add.tap()

        // A profile opens from the CTA only through a successful add: a refused or failed add keeps
        // the screen up with its reason. And it is a tree this phone added, placed by its GPS fix,
        // which is the only kind of tree that offers Move pin.
        XCTAssertTrue(
            app.buttons[Copy.movePin].waitForExistence(timeout: 30),
            "one tap on Add this tree did not open the profile of a tree this phone added"
        )
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", Copy.fromGPS)).firstMatch.exists,
            "the opened profile does not say its position came from GPS"
        )
    }

    /// At the largest accessibility text size the note can be scrolled to, and the button under it
    /// is still active and reachable. The form is a strip about 70 pt tall at this size (the pinned
    /// header and footer take the rest), so the test scrolls to the note's label rather than to the
    /// whole note, which is taller than the strip. Nothing is tapped, so this test adds no tree.
    func testTheNoteAndAnActiveButtonAtTheLargestTextSize() {
        let app = XCUIApplication()
        app.launchEnvironment[Self.deepLinkScreenKey] = "addTreeNearby"
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        DebugMapCamera.pin(app)
        app.launch()

        let body = app.staticTexts[Copy.body]
        guard body.waitForExistence(timeout: 60) else {
            XCTFail(
                deepLinkFailure(app).map { "addTreeNearby: \($0)" }
                    ?? "addTreeNearby: no note at the largest text size"
            )
            return
        }
        let label = app.staticTexts[Copy.label]
        scrollIntoView(label, in: app)
        record(app, named: "note-ax5")
        XCTAssertTrue(
            label.isHittable,
            "the note cannot be scrolled into view at the largest text size; its label's frame is \(label.frame)"
        )

        let add = app.buttons[Copy.cta]
        assertReachable(add, "the Add this tree button at the largest text size")
        XCTAssertTrue(add.isEnabled, "the note disabled the Add this tree button at the largest text size")
    }

    /// Swipes the form up until `element` can be pressed, at most thirty times.
    ///
    /// On the form's own scroll view, not on the app: at the largest text size the pinned header
    /// and footer leave the form a strip about 70 pt tall, and a swipe from the middle of the
    /// screen lands on the footer and scrolls nothing.
    ///
    /// A slow drag rather than a swipe, so the form moves by about its own height with no
    /// momentum: a swipe in that strip flings the form past a short element and out the other side.
    private func scrollIntoView(_ element: XCUIElement, in app: XCUIApplication) {
        let form = app.scrollViews.firstMatch
        for _ in 0..<30 where !element.isHittable {
            let start = form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
            let end = form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
        }
    }

    /// A PNG of the screen, plus the same image on the result bundle — `AreaPickerUITests.record`.
    private func record(_ app: XCUIApplication, named name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let directory = ProcessInfo.processInfo.environment["CYPRESS_SHOT_DIR"] ?? NSTemporaryDirectory()
        let url = URL(fileURLWithPath: directory).appendingPathComponent("add-tree-\(name).png")
        try? shot.pngRepresentation.write(to: url)
        print("CYPRESS-SHOT: \(url.path)")
    }
}
