//
//  PhotoDeletionReachabilityTests.swift
//  Cypress — UI tests
//
//  **The test #78 did not have, and the reason it was reported as unshipped (ERRATA E173).**
//
//  #78 built the delete, walked it on a simulator, and closed green. What it walked was screen 20,
//  reached by tapping the hero's metadata pill. What the owner did was tap the *photograph* — which
//  is the gesture a person makes to act on a photograph, and which lands in `PhotoViewerView`. That
//  screen had no delete and no route onward, so the honest summary of the feature from the outside
//  was "I don't see that option".
//
//  Every unit test in `PhotoDeletionTests` passed throughout, and would have gone on passing: they
//  assert that `deletePhoto` removes a row and a file, which was true. Nothing asserted that a
//  person holding the phone could get to it. **That gap is the whole subject of this file**, so its
//  assertions are deliberately about reaching and pressing rather than about what a store returns.
//
//  ── Why it does not stop at `isHittable` ─────────────────────────────────────────────────
//  This project has shipped a control that `isHittable` reported `true` for and that no finger could
//  press (`.clipped()` clips drawing, not touches). So presence and hittability are checked, and
//  then the control is *used*: the confirmation is taken, and the surface underneath is read for the
//  photograph being gone. A test that stopped at `exists` would ratify the same class of defect it
//  was written to catch.
//
//  ── Why `communityPhotos` ────────────────────────────────────────────────────────────────
//  `DebugDeepLink` keeps one rule: a case that writes persistent state must not write it onto a tree
//  another case reads. This case was built by E147 precisely to have its photograph deleted — one
//  tree, one photograph, on a coordinate west of Ocean Beach that nothing else touches — and it
//  re-adds the photograph on each launch. Running this file does not disturb `photoHero`'s three,
//  which four `DeepLinkVoiceOverTests` cases anchor on.
//

import XCTest

final class PhotoDeletionReachabilityTests: XCTestCase {

    /// **The reported defect, as an assertion.** Tap the photograph on screen 03 — the affordance
    /// SCREENS.md names for the hero — and the delete has to be there, hittable, and real.
    func testTheHeroPhotographReachesADeleteThatWorks() {
        let app = launch()
        guard arrive(app) else { return }

        app.buttons[Self.hero].tap()
        guard openedTheViewer(app) else { return }

        let delete = app.buttons[Self.deleteControl]
        XCTAssertTrue(
            delete.waitForExistence(timeout: 5),
            "the viewer opened over a photograph this device owns and offered no way to delete it — "
                + "which is the whole of the owner's report on #78"
        )
        XCTAssertTrue(
            delete.isHittable,
            "the delete is in the viewer's tree but nothing could press it"
        )

        // Presence is not the claim. Pressing it is.
        delete.tap()
        let confirm = app.buttons[Self.confirmDelete]
        XCTAssertTrue(
            confirm.waitForExistence(timeout: 5),
            "the delete was pressed and no confirmation naming the consequence appeared — one tap "
                + "must open a question, and it must be a question somebody can answer"
        )
        confirm.tap()

        // The viewer's subject no longer exists, so the viewer has to go, and the surface underneath
        // has to have re-read itself. Both halves: a cover that stayed would draw "That photograph
        // could not be opened" over the thing that was just asked for, and a profile that did not
        // reload would keep drawing the photograph's count (ERRATA E127, and E147's own harness
        // defect).
        XCTAssertTrue(
            app.buttons[Self.hero].waitForNonExistence(timeout: 10),
            "the photograph was deleted and the hero is still drawn over the tree"
        )
        XCTAssertTrue(
            app.staticTexts[Self.coldWell].waitForExistence(timeout: 10),
            "the only photograph of this tree was deleted and the profile did not come back to the "
                + "cold state — the count under the hero is stale"
        )
    }

    /// The other door into the same screen. A person on screen 20 who taps a row to look properly
    /// before deciding lands in the viewer too, and must not have to go back to act on what they are
    /// looking at.
    func testAPhotographOpenedFromTheBrowserReachesTheSameDelete() {
        let app = launch()
        guard arrive(app) else { return }

        // The pill has no fixed label — it *is* its own text, `1 photo · since 2026`. The separator
        // is the stable part and nothing else on screen 03 carries it.
        let pill = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", Self.photoPillFragment))
            .firstMatch
        guard pill.waitForExistence(timeout: 10) else {
            XCTFail("screen 03 drew no photo-count pill, so the browser has no door")
            return
        }
        pill.tap()
        let row = app.images
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Photo · "))
            .firstMatch
        guard row.waitForExistence(timeout: 10) else {
            XCTFail("the metadata pill did not open the photo browser")
            return
        }
        row.tap()
        guard openedTheViewer(app) else { return }

        XCTAssertTrue(
            app.buttons[Self.deleteControl].waitForExistence(timeout: 5),
            "the browser's own row opened a viewer with no delete on it, so looking closer at a "
                + "photograph costs you the controls for it"
        )
    }

    // MARK: - Harness

    /// `PhotoViewerPresentation`/`TreeProfilePresentation` own these strings; they are spelled out
    /// rather than imported because a UI test drives the app from outside, and a label that changed
    /// without anybody noticing should fail here rather than follow the change silently.
    private static let hero = "Photo of this tree"
    private static let photoPillFragment = " · since "
    private static let deleteControl = "Delete this photo"
    private static let confirmDelete = "Delete photo"
    private static let coldWell = "No photos of this tree yet"

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CYPRESS_SCREEN"] = "communityPhotos"
        app.launch()
        return app
    }

    /// Arrives on screen 03 over the community add, and reports a harness failure as a harness
    /// failure. `DebugDeepLink` draws its failures rather than logging them for exactly this reason:
    /// "no record nearest 37.7636, -122.5300" is an answer, and "the delete is missing" would be a
    /// lie about the app.
    private func arrive(_ app: XCUIApplication) -> Bool {
        let banner = app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH %@", "DEEP LINK FAILED"))
            .firstMatch
        // Generous: a cold launch opens the database, runs migrations and attaches the seed before
        // it can add a tree and stage a photograph.
        guard app.buttons[Self.hero].waitForExistence(timeout: 60) else {
            XCTFail(
                banner.exists
                    ? banner.label
                    : "the community add never drew a hero photograph, so there was nothing to "
                        + "delete and this test could not have failed for its own reason"
            )
            return false
        }
        return true
    }

    /// The viewer is a cover with no bar of its own, so its `Close` is what proves it is on screen —
    /// and proves it independently of the control this file is actually about.
    private func openedTheViewer(_ app: XCUIApplication) -> Bool {
        guard app.buttons["Close"].waitForExistence(timeout: 10) else {
            XCTFail("tapping the photograph did not open the viewer")
            return false
        }
        return true
    }
}
