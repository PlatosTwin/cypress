//
//  OthersTreeUITests.swift
//  CypressUITests
//
//  Round C3, on the running app: community trees somebody else added, and the line that tells the
//  adder of a tree that only they can see it.
//
//  1. Somebody else's tree: the city tree's controls (Visit, Check in, Favorite, Care, Share,
//     Report), no Move pin, neither species control (the owner's ruling of 2026-11-15, "Hide
//     species controls for now"), and the "Added" row dated by the service's day. Then each control
//     is used: Favorite changes state, and Care, Share, Check in, a measure tile and Visit each
//     open their own screen or sheet.
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

    // MARK: - 1b · Each control on somebody else's tree works

    private enum Screens {
        static let careLog = "Care log"
        static let share = "Share this tree"
        static let checkIn = "Check-in"
        static let measure = "Measure"
        static let back = "Back"
        /// `TreeProfilePresentation`'s cold CTA: nobody has photographed this tree.
        static let visit = "Add the first photo of this tree"
        /// `VisitCameraModel.closeLabel` over the live viewfinder.
        static let closeCamera = "Close the camera"
        /// The stat card's label begins with its name; an empty one reads `Height, Add a reading`.
        static let heightTile = "Height, "
    }

    /// Favorite changes state; Care, Share, Check in, a measure tile and Visit each open their own
    /// screen or sheet, and the profile comes back after each. Visit goes last: it opens the
    /// camera, which this test closes and then ends.
    ///
    /// Camera access is granted once per install (CLAUDE.md). On a clean install the system's
    /// "Allow Cypress to use your location?" alert does appear in this test (the reviewer's logs
    /// of 2026-11-15 show it at the first Favorite tap), and XCUITest's own interruption monitor
    /// dismisses it on the next tap. The test passes because of that monitor, not because no
    /// alert shows.
    func testEachControlOnSomebodyElsesTreeOpensItsScreen() {
        let app = launch("othersTree")
        let added = app.staticTexts[Copy.added]
        guard added.waitForExistence(timeout: 60) else {
            XCTFail(deepLinkFailure(app).map { "othersTree: \($0)" }
                ?? "othersTree: somebody else's tree drew no '\(Copy.added)' row")
            return
        }

        // Favorite: the cell's selected state flips, and a second tap puts it back.
        let favorite = app.buttons["Favorite"]
        let before = favorite.isSelected
        favorite.tap()
        let flipped = expectation(for: NSPredicate(format: "isSelected == %@", NSNumber(value: !before)),
                                  evaluatedWith: favorite)
        wait(for: [flipped], timeout: 10)
        favorite.tap()
        let restored = expectation(for: NSPredicate(format: "isSelected == %@", NSNumber(value: before)),
                                   evaluatedWith: favorite)
        wait(for: [restored], timeout: 10)

        // Care and Share: each raises its sheet, and the scrim strip closes it (`SheetExitUITests`).
        for (control, title) in [("Care", Screens.careLog), ("Share", Screens.share)] {
            app.buttons[control].tap()
            let sheet = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
            XCTAssertTrue(sheet.waitForExistence(timeout: 10), "'\(control)' on somebody else's tree raised no '\(title)' sheet")
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.midX, dy: 58)).tap()
            XCTAssertTrue(waitForGone(sheet), "the '\(title)' sheet did not close")
            XCTAssertTrue(added.waitForExistence(timeout: 10), "the profile did not come back after '\(title)'")
        }

        // Check in: pushes screen 07, and Back returns.
        app.buttons[Copy.checkIn].tap()
        XCTAssertTrue(app.staticTexts[Screens.checkIn].waitForExistence(timeout: 10),
                      "check-in on somebody else's tree opened no '\(Screens.checkIn)' screen")
        app.buttons[Screens.back].tap()
        XCTAssertTrue(added.waitForExistence(timeout: 10), "the profile did not come back after check-in")

        // A measure tile: pushes screen 16, and Back returns.
        let height = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", Screens.heightTile)).firstMatch
        XCTAssertTrue(height.waitForExistence(timeout: 10), "somebody else's tree draws no Height tile")
        scrollToHittable(height, in: app)
        height.tap()
        XCTAssertTrue(app.staticTexts[Screens.measure].waitForExistence(timeout: 10),
                      "the Height tile on somebody else's tree opened no '\(Screens.measure)' screen")
        app.buttons[Screens.back].tap()
        XCTAssertTrue(height.waitForExistence(timeout: 10), "the profile did not come back after Measure")

        // Visit: opens the camera for this tree, and closing it returns to the profile.
        let visit = app.buttons[Screens.visit]
        XCTAssertTrue(visit.waitForExistence(timeout: 10), "somebody else's tree offers no '\(Screens.visit)'")
        scrollToHittable(visit, in: app, upward: true)
        visit.tap()
        let close = app.buttons[Screens.closeCamera]
        XCTAssertTrue(close.waitForExistence(timeout: 15), "Visit on somebody else's tree opened no camera")
        close.tap()
        XCTAssertTrue(visit.waitForExistence(timeout: 10), "the profile did not come back after the camera")
        app.terminate()
    }

    private func waitForGone(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)
        return XCTWaiter.wait(for: [gone], timeout: timeout) == .completed
    }

    private func scrollToHittable(_ element: XCUIElement, in app: XCUIApplication, upward: Bool = false) {
        let screen = app.frame
        for _ in 0..<6 where !element.isHittableWithoutRaising(onScreen: screen) {
            if upward { app.swipeDown() } else { app.swipeUp() }
        }
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
        // The map opens on the reader when it has a fix (`MapCenteredStateUITests`), so the fix is
        // pinned (`DebugLocationOverride`, `CYPRESS_LOCATION`). It sits 67 m south of the tree and
        // inside the 150 m camera, never on the tree: MapKit hides a pin that sits exactly under
        // the reader's location dot, and the pin then never draws on a clean install. The system's
        // location alert can still appear on a clean install with the fix pinned (the reviewer's
        // log of 2026-11-15 shows it during this test); XCUITest's interruption monitor dismisses
        // it on the next tap.
        app.launchEnvironment["CYPRESS_LOCATION"] = "37.7738,-122.5300"
        app.launch()

        let pin = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", Copy.communityPin))
            .firstMatch
        // The map reads its pins when it appears, and on a clean install the deep link writes the
        // tree into the cache after that read has started. A real tree arrives through the tile
        // refresh, which re-reads the map; the debug seam does not. So the test leaves the map
        // and comes back, which re-reads it, as a reader would. Three tries, so a slow write is
        // not a race.
        XCTAssertTrue(app.buttons["Map"].waitForExistence(timeout: 60), "othersTreeOnMap: the tab bar never appeared")
        var found = pin.waitForExistence(timeout: 10)
        for _ in 0..<3 where !found {
            app.buttons["My Grove"].tap()
            app.buttons["Map"].tap()
            found = pin.waitForExistence(timeout: 15)
        }
        guard found else {
            XCTFail(deepLinkFailure(app).map { "othersTreeOnMap: \($0)" }
                ?? "othersTreeOnMap: the map drew no '\(Copy.communityPin)' pin over somebody else's tree")
            return
        }
    }

    // MARK: - 4 · Your own tree that only you can see

    func testYourTreeSaysOnlyYouCanSeeItWhetherSignedOutOrNotSharing() {
        // `unsharedNotSharing` leaves a debug account signed in. Every other deep link signs that
        // account out first (`DebugDeepLink.open`). `unsharedSignedOut` also runs once more on the
        // way out, for a later launch that uses no deep link. That run adds one more tree at sea;
        // nothing reads it.
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
