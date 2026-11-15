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
//  Where the note sits is the owner's decision of 2026-11-15: at the top of the scrolling form,
//  above the photo, so it is on screen without scrolling. With no tree within 10 m
//  (`CYPRESS_SCREEN=addTreeAlone`) it is not drawn and the form starts at the photo.
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
        /// `VisitAddTreeCopy.wellFilled`, the photo well's spoken label once a photo is chosen.
        static let well = "Photo of the tree you are adding"
        /// The GPS chip pinned above the form: `GPS ±5 m` on the harness's pinned fix.
        static let gpsChip = "GPS"
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
        let body = app.staticTexts[Copy.body]
        XCTAssertTrue(body.exists, "the note does not say the owner's two sentences")
        for sentence in Copy.refused {
            let old = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", sentence)).firstMatch
            XCTAssertFalse(old.exists, "the screen still says '\(sentence)'")
        }
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", Copy.candidate)).firstMatch
        XCTAssertTrue(row.exists, "the note lists no tree under it")

        // The owner's decision of 2026-11-15: on screen without scrolling, above the photo.
        let add = app.buttons[Copy.cta]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "no Add this tree button")
        record(app, named: "note-default")
        assertOnScreenAboveThePhoto(label, body: body, add: add, in: app)

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

    /// With no tree within 10 m the note is not drawn and leaves no gap: the photo starts right
    /// under the pinned GPS chip, as it did before the note existed. Nothing is tapped, so this test
    /// adds no tree, and the spot stays empty for the next run.
    func testNoTreeWithinTenMetersDrawsNoNoteAndNoGap() {
        let app = launch("addTreeAlone")

        let well = app.descendants(matching: .any)[Copy.well].firstMatch
        guard well.waitForExistence(timeout: 60) else {
            XCTFail(
                deepLinkFailure(app).map { "addTreeAlone: \($0)" }
                    ?? "addTreeAlone: the add screen drew no photo well"
            )
            return
        }
        record(app, named: "no-note-default")
        XCTAssertFalse(app.staticTexts[Copy.label].exists, "a note drew with no tree within 10 m")

        let chip = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", Copy.gpsChip)).firstMatch
        XCTAssertTrue(chip.exists, "no GPS chip to measure the form's top from")
        let gap = well.frame.minY - chip.frame.maxY
        XCTAssertGreaterThanOrEqual(gap, 0, "the photo well overlaps the GPS chip: chip \(chip.frame), well \(well.frame)")
        XCTAssertLessThanOrEqual(
            gap, 40,
            "the photo starts \(gap) pt below the GPS chip, so the form's top has a gap where no note is drawn"
        )
    }

    /// At the largest accessibility text size the note is still the first thing in the form, on
    /// screen without scrolling, and the button under it is still active and reachable. The form is
    /// a strip about 70 pt tall at this size (the pinned header and footer take the rest), so the
    /// test asks for the note's label, not the whole note, which is taller than the strip. Nothing
    /// is tapped, so this test adds no tree.
    func testTheNoteAndAnActiveButtonAtTheLargestTextSize() {
        let app = XCUIApplication()
        app.launchEnvironment[Self.deepLinkScreenKey] = "addTreeNearby"
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        DebugMapCamera.pin(app)
        app.launch()

        let label = app.staticTexts[Copy.label]
        guard label.waitForExistence(timeout: 60) else {
            XCTFail(
                deepLinkFailure(app).map { "addTreeNearby: \($0)" }
                    ?? "addTreeNearby: no note at the largest text size"
            )
            return
        }
        record(app, named: "note-ax5")
        XCTAssertTrue(
            label.isHittable,
            "the note's label is not on screen without scrolling at the largest text size; its frame is \(label.frame)"
        )
        let well = app.descendants(matching: .any)[Copy.well].firstMatch
        XCTAssertTrue(well.exists, "no photo well at the largest text size")
        XCTAssertLessThan(
            label.frame.maxY, well.frame.minY,
            "the note is not above the photo at the largest text size: label \(label.frame), well \(well.frame)"
        )

        let add = app.buttons[Copy.cta]
        assertReachable(add, "the Add this tree button at the largest text size")
        XCTAssertTrue(add.isEnabled, "the note disabled the Add this tree button at the largest text size")
    }

    /// The note's label and both its sentences sit inside the visible form, above the pinned button,
    /// and above the photo — without any scroll having happened.
    private func assertOnScreenAboveThePhoto(
        _ label: XCUIElement, body: XCUIElement, add: XCUIElement, in app: XCUIApplication,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let screen = app.windows.firstMatch.frame
        XCTAssertTrue(label.isHittable, "the note's label is not on screen without scrolling: \(label.frame)", file: file, line: line)
        XCTAssertTrue(body.isHittable, "the note's sentences are not on screen without scrolling: \(body.frame)", file: file, line: line)
        XCTAssertGreaterThanOrEqual(body.frame.minY, screen.minY, "the note starts above the screen: \(body.frame)", file: file, line: line)
        XCTAssertLessThan(
            body.frame.maxY, add.frame.minY,
            "the note's sentences run under the pinned button: body \(body.frame), button \(add.frame)",
            file: file, line: line
        )
        let well = app.descendants(matching: .any)[Copy.well].firstMatch
        XCTAssertTrue(well.exists, "no photo well to measure the note against", file: file, line: line)
        XCTAssertLessThan(
            body.frame.maxY, well.frame.minY,
            "the note is not above the photo: body \(body.frame), well \(well.frame)",
            file: file, line: line
        )
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
