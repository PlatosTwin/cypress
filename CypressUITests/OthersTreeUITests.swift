//
//  OthersTreeUITests.swift
//  CypressUITests
//
//  Round C3, on the running app: community trees somebody else added, and the line that tells the
//  adder of a tree that only they can see it.
//
//  1. Somebody else's tree: the city tree's controls (Visit, Check in, Favorite, Care, Share,
//     Report), no Move pin, neither species control (the owner's ruling of 2026-11-15, "Hide
//     species controls for now"), and the "Added" row dated by the service's day.
//  2. Somebody else's unnamed tree: no "Say what species you think this is", whose tap used to fail.
//  3. Its pin on the map is the same dashed community pin as anybody's.
//  4. A tree this reader added while signed out, and one added signed in without agreeing to
//     share: each profile carries its line, in the owner's words.
//
//  The UI suite runs with the remote gate shut, so no tile is downloaded: the deep links write
//  somebody else's tree into the community cache through `LocalAPI.debugSeedCommunityCache`. The
//  cache holds no history, so only the "Added" row can show here; the other history rows are
//  proved by `CommunityHistoryRowsTests`.
//
//  Black-box like the rest of this target: nothing imports `Cypress`, and every literal is a copy
//  constant repeated by hand. If a string is renamed this fails, which is correct.
//

import XCTest

final class OthersTreeUITests: XCTestCase, DeepLinkHarness {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private enum Copy {
        static let added = "Added"
        /// `DebugDeepLink.othersTreeAddedDay`, midnight UTC of 2026-09-21, printed as its day.
        static let addedDay = "Sep 21"
        static let youAdded = "You added this tree"
        static let movePin = "Move pin"
        static let claim = "Say what species you think this is"
        static let report = "Report the species as wrong"
        static let checkIn = "Check in · under a minute"
        static let quad = ["Favorite", "Care", "Share", "Report"]
        static let communityPin = "Community-added tree"
        static let signedOut = "Only you can see this tree. Everyone can see it after you sign in."
        static let notSharing =
            "Only you can see this tree. Everyone can see it after you agree to share your tree records."
    }

    // MARK: - 1 · Somebody else's tree

    func testSomebodyElsesTreeOffersTheCityTreeControlsAndNoSpeciesControlOrMovePin() {
        let app = launch("othersTree")

        let added = app.staticTexts[Copy.added]
        guard added.waitForExistence(timeout: 60) else {
            XCTFail(deepLinkFailure(app).map { "othersTree: \($0)" }
                ?? "othersTree: somebody else's tree drew no '\(Copy.added)' row")
            return
        }
        XCTAssertTrue(app.staticTexts[Copy.addedDay].exists, "the Added row is not dated \(Copy.addedDay)")
        XCTAssertFalse(app.staticTexts[Copy.youAdded].exists, "somebody else's tree says you added it")

        for label in Copy.quad {
            XCTAssertTrue(app.buttons[label].exists, "somebody else's tree offers no '\(label)'")
        }
        XCTAssertTrue(app.buttons[Copy.checkIn].exists, "somebody else's tree offers no check-in")

        XCTAssertFalse(app.buttons[Copy.movePin].exists, "somebody else's tree offers Move pin")
        XCTAssertFalse(app.buttons[Copy.claim].exists, "somebody else's tree offers the species claim")
        XCTAssertFalse(app.buttons[Copy.report].exists, "somebody else's tree offers the species report")
        XCTAssertFalse(app.staticTexts[Copy.signedOut].exists, "somebody else's tree carries the adder's line")
        XCTAssertFalse(app.staticTexts[Copy.notSharing].exists, "somebody else's tree carries the adder's line")
    }

    // MARK: - 2 · Somebody else's unnamed tree

    func testSomebodyElsesUnnamedTreeDoesNotOfferTheClaim() {
        let app = launch("othersTreeUnnamed")

        guard app.staticTexts[Copy.added].waitForExistence(timeout: 60) else {
            XCTFail(deepLinkFailure(app).map { "othersTreeUnnamed: \($0)" }
                ?? "othersTreeUnnamed: the profile drew no '\(Copy.added)' row")
            return
        }
        XCTAssertFalse(app.buttons[Copy.claim].exists, "somebody else's unnamed tree offers the species claim")
        XCTAssertFalse(app.buttons[Copy.movePin].exists, "somebody else's unnamed tree offers Move pin")
    }

    // MARK: - 3 · Its pin on the map

    func testSomebodyElsesTreeDrawsTheCommunityPin() {
        let app = XCUIApplication()
        app.launchEnvironment[Self.deepLinkScreenKey] = "othersTreeOnMap"
        // `DebugDeepLink.othersTreeSeat(.othersTreeOnMap)`'s spot, 150 m across: individual pins,
        // and nothing of the city's inventory, which has no rows out at sea. A pinned camera is
        // never written back (`DebugMapCamera`).
        app.launchEnvironment[DebugMapCamera.key] = "37.7744,-122.5300,150"
        app.launch()

        let pin = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", Copy.communityPin))
            .firstMatch
        guard pin.waitForExistence(timeout: 60) else {
            XCTFail(deepLinkFailure(app).map { "othersTreeOnMap: \($0)" }
                ?? "othersTreeOnMap: the map drew no '\(Copy.communityPin)' pin over somebody else's tree")
            return
        }
    }

    // MARK: - 4 · Your own tree that only you can see

    func testYourTreeSaysOnlyYouCanSeeItWhetherSignedOutOrNotSharing() {
        // `unsharedNotSharing` leaves a debug account signed in. `unsharedSignedOut` signs out
        // first, so it runs last, and once more on the way out, which also covers a test that
        // stopped before it. The second run adds one more tree at sea; nothing reads it.
        addTeardownBlock {
            let reset = XCUIApplication()
            reset.launchEnvironment["CYPRESS_SCREEN"] = "unsharedSignedOut"
            DebugMapCamera.pin(reset)
            reset.launch()
            _ = reset.staticTexts[Copy.signedOut].waitForExistence(timeout: 60)
            reset.terminate()
        }

        let notSharing = launch("unsharedNotSharing")
        guard notSharing.staticTexts[Copy.notSharing].waitForExistence(timeout: 60) else {
            XCTFail(deepLinkFailure(notSharing).map { "unsharedNotSharing: \($0)" }
                ?? "unsharedNotSharing: your tree does not say only you can see it")
            return
        }
        XCTAssertTrue(notSharing.staticTexts[Copy.youAdded].exists, "your own tree does not say you added it")
        notSharing.terminate()

        let signedOut = launch("unsharedSignedOut")
        guard signedOut.staticTexts[Copy.signedOut].waitForExistence(timeout: 60) else {
            XCTFail(deepLinkFailure(signedOut).map { "unsharedSignedOut: \($0)" }
                ?? "unsharedSignedOut: your tree does not say only you can see it")
            return
        }
        XCTAssertFalse(signedOut.staticTexts[Copy.notSharing].exists, "the signed-out tree carries both lines")
    }
}
