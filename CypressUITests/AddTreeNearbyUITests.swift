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
}
