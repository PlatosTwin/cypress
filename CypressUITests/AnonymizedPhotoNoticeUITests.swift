//
//  AnonymizedPhotoNoticeUITests.swift
//  Cypress — UI tests
//
//  **Task #131, as a walk rather than as a value.** A photograph whose contributor deleted their
//  account through the door that leaves the work behind is shown on both photo surfaces and has no
//  delete on either. That gating is right and `PhotoOwnershipTests` has pinned it since #78. What
//  neither surface did was *say so* — the row simply had one fewer control and the viewer simply had
//  an empty corner — which is the shape ERRATA **E126** rules against.
//
//  `CypressTests/AnonymizedPhotoNoticeTests` pins which photograph the sentence belongs to. It
//  cannot see a screen, and this project has twice shipped something correct that nobody could reach
//  (E110's untappable `Back`, E173's unreachable delete). So this file starts at a launch, reads the
//  browser, taps its way into the viewer, and asserts the sentence is on both — beside the absence
//  it explains.
//
//  ── Why `anonymizedPhotos` ───────────────────────────────────────────────────────────────
//  `DebugDeepLink` keeps one rule: a case that writes persistent state must not write it onto a tree
//  another case reads. This case has its own tree — a quarter of the way out from the map's opening
//  centre, between `.measure`'s middle and `.memorial`'s marching near end — and it re-seeds and
//  re-anonymizes on every launch, so running this file disturbs nothing the other photo cases
//  anchor on.
//

import XCTest

final class AnonymizedPhotoNoticeUITests: XCTestCase {

    /// **The defect, on the browser.** The tree carries three photographs and exactly one of them is
    /// nobody's; the row for that one has to carry the sentence, and it has to be the only one.
    func testTheBrowserSaysWhyOneRowHasNoDelete() {
        let app = launch()
        guard arrive(app) else { return }

        let notice = app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH %@", Self.noticeOpening))
            .firstMatch
        XCTAssertTrue(
            notice.waitForExistence(timeout: 20),
            "screen 20 drew a photograph nobody owns with no delete on it and said nothing about "
                + "why — the row simply has one control fewer than the row above it"
        )

        // One sentence, not one per row: the tree's other two photographs are this device's and
        // carry their delete. A notice on all three would mean the screen is talking about the tree
        // rather than about the photograph.
        XCTAssertEqual(
            app.staticTexts
                .matching(NSPredicate(format: "label BEGINSWITH %@", Self.noticeOpening))
                .count,
            1,
            "the browser drew the sentence on more than the one row it is true of"
        )

        // And the controls it is explaining. Two deletes for the two owned photographs, and the
        // sentence standing where the third would have been — the assertion that ties the words to
        // the absence rather than leaving them a free-floating string on the screen.
        XCTAssertEqual(
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Delete, ")).count,
            2,
            "the tree has three photographs, one of them nobody's, so the browser should offer "
                + "exactly two deletes"
        )
    }

    /// **The same defect on the other surface.** The viewer is handed one photograph and has room
    /// for the whole sentence; RULINGS R21 put the delete here for that reason and the explanation
    /// belongs on the same grounds.
    func testTheViewerSaysWhyItHasNoDelete() {
        let app = launch()
        guard arrive(app) else { return }

        let notice = app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH %@", Self.noticeOpening))
            .firstMatch
        guard notice.waitForExistence(timeout: 20) else {
            XCTFail("screen 20 never drew the sentence, so there was no row to open the viewer from")
            return
        }

        // The ownerless photograph is the oldest of the three, so it is the last row. Found through
        // its own image element rather than by index: `PhotoFill` publishes each photograph as an
        // image labelled with its subject and date, and the seam frames the third as a leaf.
        let row = app.images
            .matching(NSPredicate(format: "label BEGINSWITH %@", Self.ownerlessRowPrefix))
            .firstMatch
        guard row.waitForExistence(timeout: 10) else {
            XCTFail("the browser drew no row for the photograph nobody owns")
            return
        }
        // It is the third of three on a scrolling screen, so it is in the tree before it is under a
        // finger. Scrolled to deliberately rather than left to `tap()`'s own attempt, which is the
        // difference between a test that fails on the sentence and one that fails on the geometry.
        var swipes = 0
        while !row.isHittable && swipes < 4 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(row.isHittable, "the row for the photograph nobody owns could not be reached")
        row.tap()

        guard app.buttons["Close"].waitForExistence(timeout: 10) else {
            XCTFail("tapping the photograph did not open the viewer")
            return
        }

        XCTAssertTrue(
            app.staticTexts
                .matching(NSPredicate(format: "label BEGINSWITH %@", Self.noticeOpening))
                .firstMatch
                .waitForExistence(timeout: 10),
            "the viewer opened over a photograph nobody owns, drew no delete, and said nothing "
                + "about why — an empty corner is not an explanation"
        )
        // The half that makes the sentence true. A viewer carrying both would be contradicting
        // itself out loud.
        XCTAssertFalse(
            app.buttons[Self.deleteControl].exists,
            "the viewer said the photograph is nobody's to remove and drew a delete beside it"
        )
    }

    // MARK: - Harness

    /// The opening of `TreePhotosCopy.nobodysToRemove`, spelled out rather than imported for the
    /// reason `PhotoDeletionReachabilityTests` gives: a UI test drives the app from outside, and
    /// copy that changed without anybody noticing should fail here rather than follow the change.
    /// A prefix rather than the whole sentence — the ruling owns the words, this file owns the fact
    /// that they reach a screen.
    private static let noticeOpening = "Nothing on this photo says whose it is"
    /// The seam frames its third photograph as a leaf close-up, and that is the one it anonymizes.
    private static let ownerlessRowPrefix = "Photo · Leaf close-up"
    private static let deleteControl = "Delete this photo"

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CYPRESS_SCREEN"] = "anonymizedPhotos"
        app.launch()
        return app
    }

    /// Arrives on screen 20, and reports a harness failure as a harness failure — `DebugDeepLink`
    /// draws its failures on top of the app for exactly this reason.
    private func arrive(_ app: XCUIApplication) -> Bool {
        let banner = app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH %@", "DEEP LINK FAILED"))
            .firstMatch
        // Generous: a cold launch opens the database, runs migrations and attaches the seed before
        // it can seed three photographs and take the owner off one.
        guard app.staticTexts["Photos"].waitForExistence(timeout: 60) else {
            XCTFail(
                banner.exists
                    ? banner.label
                    : "the photo browser never opened, so this test could not have failed for its "
                        + "own reason"
            )
            return false
        }
        return true
    }
}
