//
//  CityDisclaimerUITests.swift
//  Cypress — UI tests
//
//  **RULINGS R78 ruling 2, as a screen.** The NYC.gov Data Mine terms require the disclaimer "at
//  the site where the application can be accessed or downloaded", the owner ruled that the in-app
//  city-downloads screen is one of the two surfaces that carries it, and R78 ruling 3 says the
//  manifest's machine-readable `attribution` array does not discharge the obligation on its own:
//  **human-visible text is required.** "Human-visible" is not a property any unit test in this
//  repository can observe.
//
//  `CypressTests/NYCDisclaimerTests` pins `CityDownloadsCopy.nycDisclaimerRequired` against
//  `docs/operations/nyc-data-obligations.md`, so the constant is the City's words. That leaves
//  exactly one link unproved — that the constant reaches a screen — and this file is it. Delete the
//  `nycDisclaimer` property from `CityDownloadsView` and every test in this repository stays green
//  except this one.
//
//  ── The literal below is hand-copied, and that is deliberate ────────────────────────────────
//  This target does not import `Cypress` (see `PrimaryCTAReachabilityTests`' file comment), so the
//  expected sentence is written out here. That makes it an INDEPENDENT copy rather than a
//  tautology: a test reading the same constant the view reads would pass no matter what either
//  said. The chain is document → constant (unit suite) → pixels (here), and each link is checked
//  against something that is not itself.
//
//  ── Why the door is the You tab and not a deep link ─────────────────────────────────────────
//  `DebugDeepLink.Screen` has no `cityDownloads` case and this round did not add one. The row on
//  screen 18 is the only way a reader reaches this screen, so walking it proves the surface the
//  ruling names is the surface that carries the text — and a deep link that bypassed the row would
//  prove less, not more.
//

import XCTest

final class CityDisclaimerUITests: XCTestCase {

    /// The required block, verbatim. See the file header for why it is written out here.
    ///
    /// `can not` is two words because the City writes it as two words. `web site` is two words for
    /// the same reason. Neither is a typo and neither may be tidied — if this line and the app's
    /// constant ever disagree, the app's constant is the one checked against the document, so fix
    /// this one to match it rather than the other way round.
    private static let requiredDisclaimer = """
        The City of New York can not vouch for the accuracy or completeness of data provided by \
        this web site or application or for the usefulness or integrity of the web site or \
        application. This site provides applications using data that has been modified for use \
        from its original source, NYC.gov, the official web site of the City of New York.
        """

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// The whole obligation, in one walk: open the You tab, take the door a reader takes, and read
    /// the City's sentence off the screen it lands on.
    func testTheCitiesScreenCarriesTheNYCDisclaimerVerbatim() {
        let app = launchAtYouTab()
        guard openCities(app) else { return }

        XCTAssertTrue(
            Self.disclaimerText(in: app).waitForExistence(timeout: 10),
            """
            the Cities screen does not carry the NYC Data Mine disclaimer.

            RULINGS R78 ruling 2 makes this screen one of the two surfaces that must carry the \
            verbatim text before the first NYC pack is published, trial and beta included (D12). \
            Expected, as one static text:

            \(Self.requiredDisclaimer)
            """
        )
    }

    /// The disclaimer is drawn unconditionally — it does not wait for a catalog, and this is the
    /// test that says so.
    ///
    /// `CityDownloadsView.nycDisclaimer`'s doc comment gives the reasoning; the reason it is worth
    /// a second test is that the tempting refactor ("only show it when an NYC pack is listed")
    /// fails *silently*. This run has no network — `RemoteAccess` gives the screen an
    /// `OfflineSession` — so `model.rows` holds the built-in card and nothing else, which is
    /// precisely the state a conditional render would drop the text in.
    func testTheDisclaimerIsThereWithNoCatalogToShow() {
        let app = launchAtYouTab()
        guard openCities(app) else { return }

        // Which no-catalog state this run lands in is a property of the machine, not of the code:
        // `RemoteAccess` gives the screen an `OfflineSession` when the run forbids network, and a
        // run that allows it still gets no manifest from a host that is not there. Either way the
        // catalog is empty, which is the state this test is about — so the assertion is that it IS
        // one of them, rather than a guess at which.
        XCTAssertTrue(
            app.staticTexts[Self.offlineLine].waitForExistence(timeout: 30)
                || app.staticTexts[Self.checkingLine].exists,
            "the Cities screen has a catalog, so this run is not the no-catalog case this test "
                + "claims to cover"
        )

        XCTAssertTrue(
            Self.disclaimerText(in: app).waitForExistence(timeout: 10),
            "the disclaimer is absent on a catalog-less Cities screen, so it is conditional on "
                + "something — R78 ruling 2 and D12 require it wherever NYC packs are offered, "
                + "including before a catalog has ever loaded"
        )
    }

    /// The disclaimer as a query, because the subscript form is not available for a string this
    /// long.
    ///
    /// `app.staticTexts[<the sentence>]` raises rather than answering — measured, on the second run
    /// of this file: `NSInternalInconsistencyException: Invalid query - string identifier 'The City
    /// of New York can not vouch …'`. A raise reads as a failed assertion, so the first version of
    /// this test would have reported a missing disclaimer on a screen that carries it. A predicate
    /// on `label` asks the same question and answers it.
    private static func disclaimerText(in app: XCUIApplication) -> XCUIElement {
        app.staticTexts
            .matching(NSPredicate(format: "label == %@", requiredDisclaimer))
            .firstMatch
    }

    /// `CityDownloadsCopy.offline` and `.checking`, hand-copied for this target's usual reason.
    private static let offlineLine =
        "Couldn't check what's available. Downloaded cities still work."
    private static let checkingLine = "Checking what's available…"

    // MARK: - Harness

    private func launchAtYouTab() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CYPRESS_SCREEN"] = "you"
        // R58's pin. Nothing here reads a fix, but a launch on a fixless device takes a different
        // path through the map root behind the tab and this test should not depend on which.
        app.launchEnvironment["CYPRESS_LOCATION"] = "37.7596,-122.4269"
        app.launch()
        return app
    }

    /// Walks the reader's own route: screen 18, its `Cities` row, the Cities screen.
    ///
    /// Reports a harness failure as a harness failure at each of the three steps, because "the
    /// disclaimer is missing" and "this test never got to the screen" are different findings and a
    /// single assertion at the end would print the first message for both.
    ///
    /// **The row is matched by a label PREFIX, not by `app.buttons["Cities"]`.** `IconTextRow`
    /// wraps its title and subtitle in one `Button`, so SwiftUI merges both into the button's
    /// accessibility label and the exact-match lookup finds nothing — measured, on the first run of
    /// this file: `the You tab drew no Cities row`, 30 s, on a build that draws it.
    @discardableResult
    private func openCities(_ app: XCUIApplication) -> Bool {
        guard app.staticTexts["City data"].waitForExistence(timeout: 60) else {
            XCTFail("the You tab never drew its City data section, so the deep link did not arrive")
            return false
        }

        let citiesRow = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Cities"))
            .firstMatch
        guard citiesRow.waitForExistence(timeout: 30) else {
            XCTFail("the You tab drew no Cities row — a harness failure, not a disclaimer failure")
            return false
        }
        citiesRow.tap()

        guard app.staticTexts["Built-in inventory"].waitForExistence(timeout: 30) else {
            XCTFail("the Cities screen never drew its built-in card, so the tap did not arrive")
            return false
        }
        return true
    }
}
