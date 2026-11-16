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
//  A row of the note opens that tree's profile over the add screen, and Back returns to the add
//  screen with the draft kept: the owner's decision of 2026-11-15, "Keep the draft".
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
        /// The land row's sentence once a chip is chosen (`VisitAddTreeCopy.land`), for City park.
        static let landChosen = "This will be recorded as your answer that it stands in a city park."
        static let cityPark = "City park"
        static let back = "Back"
        /// `MovePinCopy`'s north nudge and save, repeated by hand.
        static let nudgeNorth = "Move the pin north"
        static let save = "Save"
        /// `VisitAddTreeCopy.footnote(for: .signedOut)` and `(for: .unknown)`, repeated by hand.
        static let signedOutNote = "Recorded as community-added and unverified. Only you can see it. "
            + "Everyone using Cypress can see it after you sign in."
        static let unknownNote = "Recorded as community-added and unverified, on this phone."
        /// `VisitAddTreeCopy.land(nil)`, a row of the form with nothing chosen.
        static let landUnanswered = "Where it stands will not be recorded."
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
        // Exactly one: `.addTreeNearby` puts one tree on a fresh slot per launch, so the rows earlier
        // runs added on this simulator are not under this pin.
        let rows = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", Copy.candidate))
        XCTAssertEqual(rows.count, 1, "the note lists \(rows.count) trees, not the one this launch put there")

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

    /// The owner's decision of 2026-11-15, "Keep the draft": a row of the note opens that tree's
    /// profile over the add screen, and Back returns to the add screen with the draft still there.
    /// The draft is checked by the land answer, which nothing but the reader's tap sets. A photo
    /// alone would not tell a kept draft from a rebuilt one, because a rebuilt screen is handed the
    /// harness photograph again. Then one tap adds the tree.
    ///
    /// Red-proof: wire the row to `onAdded`, which is what the old `onOpenExisting` was (it closed
    /// the flow and pushed the profile onto the app's stack) — red on "the add screen is gone".
    func testARowOpensTheProfileOverTheDraftAndBackKeepsIt() {
        let app = launch("addTreeNearby")

        let label = app.staticTexts[Copy.label]
        guard label.waitForExistence(timeout: 60) else {
            XCTFail(
                deepLinkFailure(app).map { "addTreeNearby: \($0)" }
                    ?? "addTreeNearby: the add screen drew no '\(Copy.label)' note before any tap"
            )
            return
        }
        let rows = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", Copy.candidate))
        XCTAssertEqual(rows.count, 1, "the note lists \(rows.count) trees, not the one this launch put there")

        // A piece of draft only the reader sets: the land answer.
        let park = app.buttons[Copy.cityPark]
        scroll(app, until: park, up: true)
        assertReachable(park, "the City park chip")
        park.tap()
        let chosen = app.staticTexts[Copy.landChosen]
        XCTAssertTrue(chosen.waitForExistence(timeout: 10), "the City park answer did not take")

        let row = rows.firstMatch
        scroll(app, until: row, up: false)
        assertReachable(row, "the note's row")
        row.tap()

        // The profile, over the add screen: its own Move pin, and the add screen's button covered.
        XCTAssertTrue(
            app.buttons[Copy.movePin].waitForExistence(timeout: 30),
            "a row of the note did not open that tree's profile"
        )
        record(app, named: "profile-from-note")
        let add = app.buttons[Copy.cta]
        XCTAssertFalse(
            add.exists && add.isHittableWithoutRaising(onScreen: app.frame),
            "the add screen's button is still reachable, so the profile did not open over it"
        )

        let back = hittableBack(in: app)
        XCTAssertNotNil(back, "the profile has no Back to press")
        back?.tap()

        // The add screen, with the draft.
        assertReachable(label, "the note on the add screen after Back (the add screen is gone)")
        XCTAssertTrue(
            app.staticTexts[Copy.landChosen].waitForExistence(timeout: 10),
            "the add screen came back without the City park answer, so the draft was lost"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)[Copy.well].firstMatch.exists,
            "the add screen came back without its photograph"
        )
        record(app, named: "after-back")
        let kept = app.staticTexts[Copy.landChosen]
        scroll(app, until: kept, up: true)
        record(app, named: "after-back-land")
        assertReachable(add, "the Add this tree button after Back")
        XCTAssertTrue(add.isEnabled, "the Add this tree button is not active after Back")
        add.tap()

        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", Copy.fromGPS)).firstMatch
                .waitForExistence(timeout: 30),
            "one tap on Add this tree after Back did not open the new tree's profile"
        )
    }

    /// The note is read again when the profile opened from it closes. The harness's tree is this
    /// phone's own, so its profile offers Move pin: three 5 m nudges north put it 15 m north of where
    /// it was, which is about 11 m from the pin 4 m north of its old spot. That is inside the 15 m a
    /// listed tree is kept for (the owner's decision of 2026-11-15), so after Back the row stays and
    /// must say where the tree is now.
    ///
    /// Red-proof: take out the read on dismissal — red on "the row still says 4 m".
    func testAMovedListedTreeShowsItsNewDistanceAfterBack() {
        let app = launch("addTreeNearby")

        let label = app.staticTexts[Copy.label]
        guard label.waitForExistence(timeout: 60) else {
            XCTFail(
                deepLinkFailure(app).map { "addTreeNearby: \($0)" }
                    ?? "addTreeNearby: the add screen drew no '\(Copy.label)' note before any tap"
            )
            return
        }
        let rows = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", Copy.candidate))
        XCTAssertEqual(rows.count, 1, "the note lists \(rows.count) trees, not the one this launch put there")
        let row = rows.firstMatch
        XCTAssertTrue(row.label.contains("4 m"), "the row does not start at 4 m: \(row.label)")
        assertReachable(row, "the note's row")
        row.tap()

        let movePin = app.buttons[Copy.movePin]
        assertReachable(movePin, "the opened profile's Move pin")
        movePin.tap()
        let north = app.buttons[Copy.nudgeNorth]
        for step in 1...3 {
            assertReachable(north, "the north nudge")
            north.tap()
            XCTAssertTrue(
                app.staticTexts["\(step * 5) m north of where it was."].waitForExistence(timeout: 10),
                "nudge \(step) did not put the pin \(step * 5) m north"
            )
        }
        let save = app.buttons[Copy.save]
        assertReachable(save, "the Save button")
        save.tap()

        XCTAssertTrue(movePin.waitForExistence(timeout: 15), "Save did not return to the profile")
        let back = hittableBack(in: app)
        XCTAssertNotNil(back, "the profile has no Back to press")
        back?.tap()

        assertReachable(label, "the note on the add screen after Back")
        let moved = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "11 m")).firstMatch
        XCTAssertTrue(
            moved.waitForExistence(timeout: 10),
            "the row still says 4 m after the tree moved 15 m north: \(row.exists ? row.label : "no row")"
        )
        record(app, named: "after-move-back")
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
        assertReachable(label, "the note's label, without scrolling, at the largest text size")
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

    /// Round C3, the owner's ruling of 2026-11-15 on the note under the Add this tree button. The
    /// harness's add screen runs on a fresh install with nobody signed in, so the note says the
    /// signed-out sentence, and below the accessibility sizes it is pinned under the button,
    /// outside the form. Nothing is tapped, so this test adds no tree.
    ///
    /// **It runs at the largest size below the accessibility sizes (XXXL), not the default.** With a
    /// photo chosen, the form at the default size can fit the screen and not scroll, and then "the
    /// note did not move after a swipe" would hold for a note in the form too. At XXXL the form
    /// scrolls, so the test checks that a row of the form moved while the note stayed.
    ///
    /// Red-proofs: make the add screen read no state (drop `await refreshSharing()` from
    /// `VisitAddTreeModel.load()`) — red on "no signed-out note". Return `.scroll` for every size
    /// from `VisitAddTreeLayout.footnotePlace` — red on the note not being reachable without
    /// scrolling.
    func testTheSignedOutNoteIsPinnedUnderTheButton() {
        let app = XCUIApplication()
        app.launchEnvironment[Self.deepLinkScreenKey] = "addTreeAlone"
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXXL"
        ]
        DebugMapCamera.pin(app)
        app.launch()

        let note = app.staticTexts[Copy.signedOutNote]
        guard note.waitForExistence(timeout: 60) else {
            XCTFail(
                deepLinkFailure(app).map { "addTreeAlone: \($0)" }
                    ?? "addTreeAlone: no signed-out note under the button"
            )
            return
        }
        record(app, named: "signed-out-note-xxxl")
        XCTAssertFalse(
            app.staticTexts[Copy.unknownNote].exists,
            "the screen still says the note for a phone that does not know the account"
        )
        let add = app.buttons[Copy.cta]
        assertReachable(add, "the Add this tree button")
        assertReachable(note, "the note under the button, without scrolling")
        XCTAssertGreaterThanOrEqual(
            note.frame.minY, add.frame.maxY,
            "the note is not under the button: note \(note.frame), button \(add.frame)"
        )
        // Pinned: a swipe scrolls the form, so a row of the form moves, and the note stays.
        let row = app.staticTexts[Copy.landUnanswered]
        XCTAssertTrue(row.exists, "no land row to watch the form scroll by")
        let noteBefore = note.frame
        let rowBefore = row.frame
        app.swipeUp()
        XCTAssertTrue(note.waitForExistence(timeout: 5), "the note is gone after a swipe")
        XCTAssertLessThan(
            row.frame.minY, rowBefore.minY,
            "the form did not scroll at XXXL (land row \(rowBefore) → \(row.frame)), so the swipe proves nothing"
        )
        XCTAssertEqual(
            note.frame, noteBefore,
            "the note moved with the form below the accessibility sizes, so it is not pinned"
        )
        record(app, named: "signed-out-note-xxxl-after-swipe")
    }

    /// The same ruling, "move into the scroll": at the largest accessibility text size the note is
    /// the last row of the scrolling form, and only the button stays pinned. The reader scrolls to
    /// the note, and it is then above the button. Nothing is tapped, so this test adds no tree.
    ///
    /// Red-proof: return `.footer` for both sizes from `VisitAddTreeLayout.footnotePlace` — red on
    /// "the note is not in the scrolling form above the pinned button".
    func testTheNoteMovesIntoTheFormAtTheLargestTextSize() {
        let app = XCUIApplication()
        app.launchEnvironment[Self.deepLinkScreenKey] = "addTreeAlone"
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        DebugMapCamera.pin(app)
        app.launch()

        let add = app.buttons[Copy.cta]
        guard add.waitForExistence(timeout: 60) else {
            XCTFail(
                deepLinkFailure(app).map { "addTreeAlone: \($0)" }
                    ?? "addTreeAlone: no Add this tree button at the largest text size"
            )
            return
        }
        let note = app.staticTexts[Copy.signedOutNote]
        XCTAssertTrue(note.waitForExistence(timeout: 10), "no signed-out note at the largest text size")
        assertReachable(add, "the pinned Add this tree button at the largest text size")
        record(app, named: "signed-out-note-ax5-top")

        // In the form: the reader scrolls to it, and it is then above the pinned button. Pinned
        // under the button, as at the drawn size, it would sit below the button's top edge.
        scroll(app, until: note, up: true)
        // A note whose first line is on screen can still have its other lines behind the pinned
        // button (iPhone Air, 2026-11-15: the scroll stopped with the note at y 718 to 1019 and the
        // button at 754). Scroll on until the note clears the button or the form stops moving, so
        // the assertion below is about where the form can put the note.
        for _ in 0..<6 where note.frame.maxY > add.frame.minY {
            let before = note.frame
            app.swipeUp()
            if note.frame == before { break }
        }
        record(app, named: "signed-out-note-ax5-scrolled")
        assertReachable(note, "the note, after scrolling the form")
        XCTAssertLessThanOrEqual(
            note.frame.maxY, add.frame.minY,
            "the note is not in the scrolling form above the pinned button: note \(note.frame), button \(add.frame)"
        )
        assertReachable(add, "the Add this tree button after scrolling, which must stay pinned")
    }

    /// The note's label and both its sentences sit inside the visible form, above the pinned button,
    /// and above the photo — without any scroll having happened.
    private func assertOnScreenAboveThePhoto(
        _ label: XCUIElement, body: XCUIElement, add: XCUIElement, in app: XCUIApplication,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let screen = app.windows.firstMatch.frame
        assertReachable(label, "the note's label, without scrolling", file: file, line: line)
        assertReachable(body, "the note's sentences, without scrolling", file: file, line: line)
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

    /// Swipes the form until `element` can be tapped. Bounded, per this target's rule on waits;
    /// `isHittableWithoutRaising` because this is a filter position (`HittabilityFilterGateTests`).
    private func scroll(_ app: XCUIApplication, until element: XCUIElement, up: Bool) {
        let screen = app.frame
        for _ in 0..<6 {
            if element.isHittableWithoutRaising(onScreen: screen) { return }
            if up { app.swipeUp() } else { app.swipeDown() }
        }
    }

    /// The Back that can be pressed. The add screen's own Back is still in the accessibility tree
    /// under the profile's cover, so the first match is not necessarily the one on top.
    private func hittableBack(in app: XCUIApplication) -> XCUIElement? {
        let screen = app.frame
        let backs = app.buttons.matching(identifier: Copy.back)
        for index in 0..<backs.count {
            let candidate = backs.element(boundBy: index)
            if candidate.isHittableWithoutRaising(onScreen: screen) { return candidate }
        }
        return nil
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
