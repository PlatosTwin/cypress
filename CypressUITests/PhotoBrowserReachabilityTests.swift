//
//  PhotoBrowserReachabilityTests.swift
//  Cypress — UI tests
//
//  **The other half of ERRATA E173, reported on its own.**
//
//  E173's account of the defect names two missing things — "no delete, **and no way onward to the
//  screen that has one**" — and shipped the first. `PhotoDeletionReachabilityTests` guards that half.
//  The second came back as its own report:
//
//  > when i click on the tree photo from a tree page, i can get to the view where I see all photos
//  > and can thumbs up/down them, change between all/full/trunk/leaf only very ocassionally, and
//  > sometimes not at all, instead seeing only the hero photo and no other photos and no option at
//  > all to thumbs up/down
//
//  Screen 20 has one door — the hero's metadata pill, a 44 × ~178 pt corner of a 430 × 224 pt
//  photograph — and every other press on the hero opens the viewer, which showed one photograph and
//  had nowhere to go. "Only very occasionally" is the pill being hit by accident.
//
//  ── Why this is a UI test, and why it walks rather than asks ─────────────────────────────
//  Nothing about this defect is visible to a unit test. Every predicate involved is correct:
//  `TreeProfilePresentation.visiblePhotos` and `TreePhotosModel.load` agree row for row today, the
//  browser draws its filter and its thumbs, and the viewer draws its photograph. What was wrong was
//  which surface a finger arrives at, which only a test that presses things can see — the same
//  argument E173 makes about `PhotoDeletionTests` passing throughout.
//
//  So this file starts where the reporter started: screen 03 with photographs on it, press the
//  photograph, and require that the three things the report names are then reachable — other
//  photographs, a thumb, and the subject filter.
//
//  ── Why `photoHero` ─────────────────────────────────────────────────────────────────────
//  It is the one deep link that puts **three** photographs of three framings on a tree, which is what
//  "no other photos" and "all/full/trunk/leaf" need in order to be assertable. `DebugDeepLink` keeps
//  the rule that a case which writes persistent state must not write it onto a tree another case
//  reads; this file writes nothing of its own — it votes on nothing and deletes nothing — so it
//  leaves that tree exactly as `DeepLinkVoiceOverTests` expects to find it.
//

import XCTest

final class PhotoBrowserReachabilityTests: XCTestCase {

    /// **The reported defect, as an assertion.** Press the photograph on screen 03 — the gesture the
    /// report describes — and every photograph of the tree, the vote, and the subject filter have to
    /// be reachable from where that press lands.
    func testTheHeroPhotographReachesTheBrowserItsPillHides() {
        let app = launch()
        guard arrive(app) else { return }

        app.buttons[Self.hero].tap()
        guard openedTheViewer(app) else { return }

        let door = app.buttons[Self.browserDoor]
        XCTAssertTrue(
            door.waitForExistence(timeout: 10),
            "the photograph was pressed, the viewer opened over one photograph, and there was no way "
                + "on from it to the tree's other photographs — which is the whole of the report"
        )
        XCTAssertTrue(
            door.isHittable,
            "the way onward is in the viewer's tree and nothing could press it"
        )

        // Presence is not the claim. Pressing it is, and what it lands on is.
        door.tap()
        assertTheBrowserIsOnScreen(app)
    }

    /// The same control from the browser's own door into the viewer. A person who taps a row on
    /// screen 20 to look closer must be able to get back to the set — and must not collect a second
    /// copy of the browser on the stack for doing it (`AppRouter.push(_:unlessAlreadyOnTop:)`).
    func testTheViewerReachedFromTheBrowserGoesBackToOneBrowser() {
        let app = launch()
        guard arrive(app) else { return }

        let pill = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", Self.photoPillFragment))
            .firstMatch
        guard pill.waitForExistence(timeout: 10) else {
            XCTFail("screen 03 drew no photo-count pill, so this test could not reach the browser")
            return
        }
        pill.tap()
        let row = app.images
            .matching(NSPredicate(format: "label BEGINSWITH %@", Self.rowPrefix))
            .firstMatch
        guard row.waitForExistence(timeout: 10) else {
            XCTFail("the metadata pill did not open the photo browser")
            return
        }
        row.tap()
        guard openedTheViewer(app) else { return }

        let door = app.buttons[Self.browserDoor]
        guard door.waitForExistence(timeout: 10) else {
            XCTFail("the browser's own row opened a viewer with no way back to the set")
            return
        }
        door.tap()
        assertTheBrowserIsOnScreen(app)

        // One browser, not two stacked. Going back once from here has to leave screen 20 behind —
        // if the door pushed a second copy, `Back` lands on an identical browser and the reader is
        // still looking at the screen they just left.
        app.buttons[Self.back].firstMatch.tap()
        XCTAssertTrue(
            app.buttons[Self.hero].waitForExistence(timeout: 10),
            "going back from the browser did not reach the tree profile, so the door stacked a "
                + "second copy of the browser it was pressed from"
        )
    }

    // MARK: - What the browser has to be

    /// The three things the report says are missing, asserted as present on the screen the door
    /// opens: the tree's other photographs, the vote, and the subject filter.
    private func assertTheBrowserIsOnScreen(_ app: XCUIApplication) {
        let rows = app.images.matching(NSPredicate(format: "label BEGINSWITH %@", Self.rowPrefix))
        XCTAssertTrue(
            rows.element(boundBy: 1).waitForExistence(timeout: 10),
            "the way onward did not reach a screen listing more than one photograph of this tree — "
                + "\"no other photos\" is the report's first clause"
        )

        let thumbUp = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", Self.thumbUpPrefix))
            .firstMatch
        XCTAssertTrue(
            thumbUp.waitForExistence(timeout: 10),
            "the photographs are listed and there is no thumbs up on them — \"no option at all to "
                + "thumbs up/down\" is the report's second clause"
        )
        XCTAssertTrue(thumbUp.isHittable, "the thumbs up is in the tree and nothing could press it")

        for segment in Self.subjectSegments {
            XCTAssertTrue(
                app.buttons[segment].waitForExistence(timeout: 10),
                "the browser drew no \"\(segment)\" segment — \"change between all/full/trunk/leaf\" "
                    + "is the report's third clause"
            )
        }
    }

    // MARK: - Harness

    /// The app owns these strings (`PhotoViewerCopy`, `TreePhotosPresentation`,
    /// `TreeProfilePresentation`); they are spelled out here rather than imported because a UI test
    /// drives the app from outside, and a label that changed without anybody noticing should fail
    /// here rather than follow the change silently.
    private static let hero = "Photo of this tree"
    private static let browserDoor = "All photos of this tree"
    private static let photoPillFragment = " · since "
    private static let rowPrefix = "Photo · "
    private static let thumbUpPrefix = "Thumbs up, "
    private static let back = "Back"
    private static let subjectSegments = ["All", "Full tree", "Trunk", "Leaf close-up"]

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CYPRESS_SCREEN"] = "photoHero"
        app.launch()
        return app
    }

    /// Arrives on screen 03 over the photographed tree, and reports a harness failure as a harness
    /// failure — `DebugDeepLink` draws its failures for exactly this reason.
    private func arrive(_ app: XCUIApplication) -> Bool {
        let banner = app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH %@", "DEEP LINK FAILED"))
            .firstMatch
        // Generous: a cold launch opens the database, runs migrations and attaches the seed before it
        // can write three photographs and their files.
        guard app.buttons[Self.hero].waitForExistence(timeout: 60) else {
            XCTFail(
                banner.exists
                    ? banner.label
                    : "the deep link never drew a hero photograph, so there was no photograph to "
                        + "press and this test could not have failed for its own reason"
            )
            return false
        }
        return true
    }

    /// The viewer is a cover with no bar of its own, so its `Close` is what proves it is on screen —
    /// and proves it independently of the control this file is about.
    private func openedTheViewer(_ app: XCUIApplication) -> Bool {
        guard app.buttons["Close"].waitForExistence(timeout: 10) else {
            XCTFail("pressing the photograph did not open the viewer")
            return false
        }
        return true
    }
}
