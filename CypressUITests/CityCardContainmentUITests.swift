//
//  CityCardContainmentUITests.swift
//  Cypress — UI tests
//
//  **The owner's rendering ruling of 2026-08-25, as pixels.** The cities the app ships with are
//  drawn INSIDE the built-in inventory's card — one card, its `Built-in inventory` /
//  `Ships with the app and cannot be removed` / `Includes …` header, and San Francisco and San Jose
//  contained within its boundary. Never as peer cards beside it.
//
//  ── Why this test exists in this target and not the unit suite ──────────────────────────────────
//  Because the previous version of this rule was pinned by a unit test and the rule was absent.
//  That test asserted the built-in group carried `isCityGroup == true` and an empty title. Both were
//  true. Together they were precisely what made the flag unreadable: `isCityGroup` reached
//  `CityDownloadsView` through one `.padding(.top, …)` on a section heading, and that modifier sits
//  inside `if !section.title.isEmpty`. The screen drew three cards of identical width and inset in
//  one undifferentiated column, and the suite was green.
//
//  `CumulativeInventoryTests.bundledCitiesNestUnderTheBuiltInCard` now asserts
//  `CityDownloadSection.cards`, which is what the view draws from, and that is a real improvement —
//  but it is still a claim about a value. **Whether one rectangle encloses another is not a fact any
//  value in this repository holds.** This file is the only place it can be asked, and it asks it of
//  frames read off the running screen.
//
//  ── The identifier, and why the frame comes from it rather than from the text ───────────────────
//  `CityDownloadsView` gives each card an accessibility container named `cities.card.<row id>`, so
//  the card's own frame is readable. Deriving it from the header text's frame instead would measure
//  the label, not the card, and a label sits inside its card under either arrangement — the test
//  would pass on the screen it exists to reject.
//

import XCTest

final class CityCardContainmentUITests: XCTestCase {

    /// `CityDownloadsView.cardIdentifier(CityDownloadRow.builtInID)`, hand-copied — this target does
    /// not import `Cypress` (see `PrimaryCTAReachabilityTests`' file comment).
    private static let builtInCard = "cities.card.built-in"

    /// `CityDownloadsCopy.builtInTitle` and the name the shipped seed states for its first city.
    ///
    /// **`San Francisco` is read out of the bundled seed's `dim_city.display_name`**, not written
    /// down in the app, so this literal is checked against the running screen rather than against a
    /// constant — which is what makes the first assertion below a harness check with its own
    /// message.
    private static let builtInTitle = "Built-in inventory"
    private static let bundledCity = "San Francisco"

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// The built-in card's rectangle encloses the San Francisco entry's rectangle.
    ///
    /// Read as two frames, next to each other, in the assertion that uses them — never inferred from
    /// one and remembered.
    func testTheBundledCitiesAreDrawnInsideTheBuiltInCard() {
        let app = launchAtCities()

        let card = app.otherElements[Self.builtInCard]
        XCTAssertTrue(
            card.waitForExistence(timeout: 30),
            "the Cities screen drew no element named '\(Self.builtInCard)', so this test measured "
                + "nothing — a harness failure, not a containment failure"
        )

        let entry = app.staticTexts[Self.bundledCity]
        XCTAssertTrue(
            entry.waitForExistence(timeout: 30),
            "the screen never drew a '\(Self.bundledCity)' entry. That name is read out of the "
                + "bundled seed's dim_city.display_name, so either the seed is not attached or the "
                + "built-in card lists nothing — a harness failure either way"
        )

        let cardFrame = card.frame
        let entryFrame = entry.frame
        XCTAssertTrue(
            cardFrame.contains(entryFrame),
            """
            '\(Self.bundledCity)' is drawn OUTSIDE the built-in inventory's card, which is the peer \
            arrangement the owner ruled out on 2026-08-25 — the bundled cities belong inside that \
            card's boundary, under its `Includes …` line.

            built-in card: \(cardFrame)
            \(Self.bundledCity): \(entryFrame)
            """
        )
    }

    /// And it is a real card, not a container drawn around the whole screen.
    ///
    /// **The check above is satisfiable by cheating**, and this is what stops it: a `cities.card.…`
    /// element spanning the entire scroll view would contain every entry on the screen and prove
    /// nothing. So this asserts that the built-in card does **not** contain the disclaimer at the
    /// bottom of the screen, which is outside every card by construction.
    func testTheBuiltInCardIsACardAndNotTheWholeScreen() {
        let app = launchAtCities()

        let card = app.otherElements[Self.builtInCard]
        XCTAssertTrue(
            card.waitForExistence(timeout: 30),
            "no '\(Self.builtInCard)' element — a harness failure"
        )
        let disclaimerHeading = app.staticTexts["Data disclaimer"]
        XCTAssertTrue(
            disclaimerHeading.waitForExistence(timeout: 30),
            "the Cities screen drew no 'Data disclaimer' heading, so the control this test needs is "
                + "absent — a harness failure"
        )

        let cardFrame = card.frame
        let outsideFrame = disclaimerHeading.frame
        XCTAssertFalse(
            cardFrame.contains(outsideFrame),
            """
            the built-in inventory's card encloses the screen's own footer copy, so it is not a card \
            — and the containment assertion in this file would pass over any arrangement at all.

            built-in card: \(cardFrame)
            'Data disclaimer': \(outsideFrame)
            """
        )
    }

    // MARK: - Harness

    /// The reader's own route to the screen: the You tab, its `Cities` row, the Cities screen.
    ///
    /// The same walk `CityDisclaimerUITests` makes, and for the same reason — `DebugDeepLink.Screen`
    /// has no `cityDownloads` case, and a deep link that bypassed the row would prove less.
    private func launchAtCities() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CYPRESS_SCREEN"] = "you"
        // R58's pin. Nothing here reads a fix, but a launch on a fixless device takes a different
        // path through the map root behind the tab and this test should not depend on which.
        app.launchEnvironment["CYPRESS_LOCATION"] = "37.7596,-122.4269"
        app.launch()

        guard app.staticTexts["City data"].waitForExistence(timeout: 60) else {
            XCTFail("the You tab never drew its City data section, so the deep link did not arrive")
            return app
        }
        // Matched by label PREFIX: `IconTextRow` merges its title and subtitle into one button
        // label, so the exact-match lookup finds nothing.
        let citiesRow = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Cities"))
            .firstMatch
        guard citiesRow.waitForExistence(timeout: 30) else {
            XCTFail("the You tab drew no Cities row — a harness failure")
            return app
        }
        citiesRow.tap()

        guard app.staticTexts[Self.builtInTitle].waitForExistence(timeout: 30) else {
            XCTFail("the Cities screen never drew its built-in card, so the tap did not arrive")
            return app
        }
        return app
    }
}
