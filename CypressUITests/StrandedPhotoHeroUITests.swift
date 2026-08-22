//
//  StrandedPhotoHeroUITests.swift
//  Cypress — UI tests
//
//  **RULINGS R82, as a screen rather than as a predicate.** A photograph this installation took,
//  moved onto an account by `claimDevice` and stranded there when E270 made that account
//  impossible to sign into again, is drawn among this installation's own heroes in the species
//  guide's nearby section (07 §6). `CypressTests/PhotoProvenanceTests` pins the rule and the
//  staging seam; neither can see a screen, and this project has twice shipped something correct
//  that nobody could reach (E110's untappable `Back`, E173's unreachable delete).
//
//  ── What this file can assert, and what it deliberately leaves to a screenshot ────────────
//  The hero thumbnail is a `PhotoImage` inside a `ThumbnailGradient` and it is
//  `.accessibilityHidden(true)` — correctly, it is decoration beside a titled row. So **no test in
//  this target can tell a drawn photograph from the species-hashed placeholder**, and one that
//  claimed to would be asserting something it cannot see. The before/after pictures on PR #107 are
//  where that difference is recorded.
//
//  What is left is still worth having, and it is the half that rots silently: that the deep-link
//  case resolves, stages its row, and lands on a guide that actually draws a nearby section. A
//  staged state nothing opens is E117's silent-failure shape — the screenshot would be of an empty
//  screen and would look like a defect in the ruling rather than in the harness.
//
//  ── Why the fix is pinned ────────────────────────────────────────────────────────────────
//  07 §6 has no subject without a coordinate: `SpeciesGuideLimits` draws the two nearest trees of
//  the species within 500 m of the caller's fix, and `SpeciesView` draws no section at all when
//  `coordinate` is nil. An offscreen simulator that never got a fix would fail this test for a
//  reason that has nothing to do with R82 — the same argument `DeepLinkHarness.pin` makes for the
//  map. `CYPRESS_LOCATION` (R58) is this codebase's answer and the coordinate is the map's own
//  opening center, which is where `DebugDeepLink` resolves its records from.
//

import XCTest

final class StrandedPhotoHeroUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// The case stages E277's row and opens the guide that draws it.
    ///
    /// `Nearby individuals` is the assertion rather than the screen title alone: the title proves
    /// the push, the section proves the staging landed somewhere the screen reads. A guide that
    /// opened with no section would mean `strandedHeroSubject` chose a tree the guide does not draw,
    /// which is exactly the failure that helper exists to make impossible.
    func testTheGuideDrawsTheNearbySectionTheStagedRowIsIn() {
        let app = launch()
        guard arrive(app) else { return }

        XCTAssertTrue(
            app.staticTexts["Nearby individuals"].waitForExistence(timeout: 30),
            "the species guide opened with no nearby section, so the photograph the case staged is "
                + "on no screen — the deep link reported success and photographed nothing"
        )
    }

    // MARK: - Harness

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CYPRESS_SCREEN"] = "strandedPhotoHero"
        // `MapLayout.defaultCenter`, spelled out because a UI test cannot import the app target.
        // If this ever stops matching, the section thins rather than disappears — the guide would
        // be reading from a different place than `DebugDeepLink` staged from.
        app.launchEnvironment["CYPRESS_LOCATION"] = "37.7596,-122.4269"
        app.launch()
        return app
    }

    /// Arrives on screen 07, reporting a harness failure as a harness failure — `DebugDeepLink`
    /// draws its failures on top of the app for exactly this reason.
    private func arrive(_ app: XCUIApplication) -> Bool {
        let banner = app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH %@", "DEEP LINK FAILED"))
            .firstMatch
        // Generous: a cold launch opens the database, runs migrations and attaches the seed before
        // it can read a guide, seed a photograph and move it onto another account.
        guard app.staticTexts["Field guide"].waitForExistence(timeout: 60) else {
            XCTFail(
                banner.exists
                    ? banner.label
                    : "the species guide never opened, so this test could not have failed for its "
                        + "own reason"
            )
            return false
        }
        return true
    }
}
