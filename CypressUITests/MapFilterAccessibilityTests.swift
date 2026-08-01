import XCTest

/// **Screen 01's filter row, its expandable control, its result line and its empty notice, driven the
/// way an assistive technology reaches them** (task #135; the design is RULINGS **R23** as amended by
/// **R23.1**, restructured again by task #145, with R31's disabled chips from task #136, and the
/// dropdown beside it is **R25**).
///
/// ── Why this file exists ─────────────────────────────────────────────────────────────────────────
/// #116 shipped the row and its own report says plainly: "No UI tests written — `CypressUITests` was
/// not run at all." Everything about it was verified by driving the simulator by hand.
/// `CypressTests/MapFilterTests` proves the *values* are right; it cannot prove any of them reach a
/// finger or a VoiceOver reader, because SwiftUI builds no in-process accessibility tree
/// (ARCHITECTURE §7, E116).
///
/// ── What #145 and #136 changed about this file's subject ────────────────────────────────────────
/// The row is now `Yours · In bloom · Needs care · More filters`; `Favorites` **and `Year`** live
/// behind that last control. And the two condition chips are R31 controls: while no tree anywhere
/// could match one it renders disabled with the reason on the chip, so this file can no longer use
/// `In bloom` as its reliable map-emptier — in the shipped seed `In bloom` has *seasons* (11 species
/// carry bloom calendars; October–December name no blooming tree), so its enabled state depends on
/// the month the suite runs in. What is stable on every machine and in every month:
///
///   · `Needs care` is **always disabled** — the seed's only statuses are `alive` and `vacant_site`,
///     and no UI test can stand a declining tree.
///   · `Favorites` empties the map on any device that has never favorited a tree, and the one test
///     that needs that states it as a precondition and announces the skip when it does not hold.
///
/// ── The rules this file inherits, and obeys ──────────────────────────────────────────────────────
/// **A test states its own preconditions or it does not have any** (`MapSearchUITests`, tasks #101
/// and #104). **A species name is never hardcoded** — the legend is read off the glass, and the one
/// query typed into C20 is matched by prefix. **The seed is two cities**, so nothing here counts
/// trees or assumes a row is in San Francisco.
final class MapFilterAccessibilityTests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: - The row, as words

    /// The one toggle drawn in the row that is live on every machine in every month. `In bloom` and
    /// `Needs care` are checked on R31's terms instead; `More filters` is a disclosure carrying a
    /// state and is checked on its own.
    private static let alwaysOnToggle = "Yours"

    /// `MapFilter.Condition.allCases.map(\.label)`, the owner's order.
    private static let conditionChips = ["In bloom", "Needs care"]

    /// The chip R31 keeps disabled against the shipped seed in *every* month: `Needs care` is
    /// `status == .declining`, the seed carries `alive` (174,425) and `vacant_site` (24,200), and
    /// no black-box test can inject a community observation.
    private static let alwaysDisabledChip = "Needs care"

    /// `MapYearFilterCopy.label`, and the value it carries when no decade is chosen. Behind the
    /// expandable control since #145.
    private static let yearChip = "Year"
    private static let anyYear = "Any year"

    /// `MapFilterCopy.moreLabel` — the expandable control, and the name of the group it opens.
    ///
    /// **The accessibility label is stable while the drawn label is not.** The chip draws
    /// `More filters (1)` when something is set inside it and overrides its accessibility label back
    /// to `More filters`, so the count is not read out ahead of the value that names what is on.
    /// `MapFilterTests` pins the drawn string; this file pins the spoken one.
    private static let moreChip = "More filters"

    /// The narrowing behind that control this file drives — `MapExtraFilter.favorites`. American
    /// spelling on the owner's instruction (R23.1); they named this word.
    private static let hiddenChip = "Favorites"

    /// `MapFilterCopy.chipValue(isOn:)`.
    private static let on = "On"
    private static let off = "Off"

    /// `MapFilterCopy.clearLabel`. It is the chip **and** the empty notice's button — R23's "two ways
    /// out, both labelled" — so every lookup of it below has to say which one it means.
    private static let clear = "Clear filters"

    /// `MapFilterCopy.rowLabel`, the container's own name.
    private static let rowLabel = "Filter trees"

    /// `MapFilterCopy.emptyTitle` for an empty `Favorites` map — the state this file uses whenever
    /// it wants an emptied map on purpose, and the precondition it guards: a device that has
    /// favorited a tree cannot run those tests, and they say so out loud rather than failing.
    private static let favoritesEmptyTitle = "No favorites here"

    // MARK: - Launching

    /// The default text size.
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        return app
    }

    /// AX5 — `accessibilityExtraExtraExtraLarge`, the top of the ramp — on a 390 pt phone.
    private func launchAtAX5() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()
        return app
    }

    /// Polls. The map debounces the camera and the search independently and then reads a 108 MB
    /// attached database; what is worth asserting is where the screen settles, never when.
    @discardableResult
    private func wait(timeout: TimeInterval = 20, for condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            usleep(200_000)
        }
        return condition()
    }

    private func requireField(_ app: XCUIApplication) -> XCUIElement {
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 25), "the map's search field never appeared")
        return field
    }

    /// Waits for the row to be drawn, and returns the chip named.
    private func chip(_ label: String, _ app: XCUIApplication) -> XCUIElement {
        let element = app.buttons[label]
        XCTAssertTrue(
            element.waitForExistence(timeout: 25),
            "screen 01's filter row has no chip labelled “\(label)”"
        )
        return element
    }

    /// Opens the expandable control and returns the chip inside it.
    @discardableResult
    private func openDrawer(_ app: XCUIApplication) -> XCUIElement {
        chip(Self.moreChip, app).tap()
        let hidden = app.buttons[Self.hiddenChip]
        XCTAssertTrue(
            hidden.waitForExistence(timeout: 15),
            "pressing “\(Self.moreChip)” opened nothing: “\(Self.hiddenChip)” is not in the tree"
        )
        return hidden
    }

    /// Shuts the drawer and waits for its contents to leave the tree.
    private func shutDrawer(_ app: XCUIApplication) {
        chip(Self.moreChip, app).tap()
        XCTAssertTrue(
            wait(timeout: 10) { !app.buttons[Self.hiddenChip].exists },
            "the control did not close"
        )
    }

    /// Turns `Favorites` on through the drawer and shuts the drawer again — the row's most reliable
    /// way to have a filter on, because both condition chips can be R31-disabled.
    private func turnFavoritesOn(_ app: XCUIApplication) {
        let hidden = openDrawer(app)
        hidden.tap()
        XCTAssertTrue(wait { (hidden.value as? String) == Self.on }, "the hidden chip did not come on")
        shutDrawer(app)
    }

    /// Turns `Favorites` on and requires it to have emptied the map. On a device that has favorited
    /// a tree the state under test does not exist, so the caller skips — announced, per #121.
    private func requireAnEmptyFavoritesMap(_ app: XCUIApplication, caller: String) throws {
        turnFavoritesOn(app)
        let title = app.staticTexts[Self.favoritesEmptyTitle]
        guard title.waitForExistence(timeout: 25) else {
            let message =
                "turning “\(Self.hiddenChip)” on did not empty the map, so this device has "
                + "favorited trees and the empty state under test does not exist here. Erase the "
                + "app's data (or use a fresh simulator) to run it."
            announceSkip(message, test: caller)
            throw XCTSkip(message)
        }
    }

    /// Every control labelled `Clear filters`, whichever surface it is on.
    private func clearControls(_ app: XCUIApplication) -> [XCUIElement] {
        app.buttons.matching(NSPredicate(format: "label == %@", Self.clear)).allElementsBoundByIndex
    }

    /// The `Clear filters` **chip**, found by scoping the query to the filter row's own accessibility
    /// container.
    ///
    /// **It was sorted by `frame.minY` and that was wrong at AX5** (E183 §2): the notice's own button
    /// can sit above the top of the display with a negative `minY`, so "topmost" resolved to the
    /// wrong control. Scoping to the container asks the question that was meant.
    private func clearChip(_ app: XCUIApplication) -> XCUIElement {
        app.otherElements[Self.rowLabel].buttons[Self.clear]
    }

    /// The `Clear filters` **button on the empty notice** — the one that is not the row's chip.
    private func clearOnTheNotice(_ app: XCUIApplication) -> XCUIElement? {
        let chipFrame = clearChip(app).exists ? clearChip(app).frame : .null
        return clearControls(app).first { $0.frame != chipFrame }
    }

    // MARK: - 1 · Every chip is in the tree, labelled, and says its state

    /// The row at rest: the toggle announces `Off`, each condition chip is either a live toggle
    /// announcing `Off` or R31's disabled control announcing its reason, the expandable control is
    /// reachable, and neither `Favorites` nor `Year` is in the row (R23.1, #145).
    func testTheFilterRowIsReachableAndEveryChipSaysItsState() {
        let app = launch()
        _ = requireField(app)

        XCTAssertTrue(
            app.otherElements[Self.rowLabel].waitForExistence(timeout: 25),
            "the filter row is not a named container in the accessibility tree, so its chips arrive "
                + "unannounced between the search field and the map"
        )

        let yours = chip(Self.alwaysOnToggle, app)
        XCTAssertTrue(yours.isHittable, "the “\(Self.alwaysOnToggle)” chip cannot be activated")
        XCTAssertEqual(
            yours.value as? String, Self.off,
            "the “\(Self.alwaysOnToggle)” chip announces "
                + "“\(yours.value as? String ?? "nothing")” at rest"
        )
        XCTAssertFalse(yours.isSelected, "the chip carries the selected trait while nothing is on")

        // The two condition chips are R31 controls: enabled is a toggle like any other, disabled
        // must still be in the tree, dimmed, with the *reason* as its value — a disabled chip that
        // announced `Off` would tell a listener it can be turned on.
        for label in Self.conditionChips {
            let element = chip(label, app)
            let value = element.value as? String ?? ""
            if element.isEnabled {
                XCTAssertEqual(
                    value, Self.off,
                    "the enabled “\(label)” chip announces “\(value)” at rest"
                )
            } else {
                XCTAssertFalse(
                    value.isEmpty || value == Self.off || value == Self.on,
                    "the disabled “\(label)” chip announces “\(value)”, so a listener is not told "
                        + "why the control cannot be used (R31)"
                )
            }
        }

        // #145: the row is the owner's three and the control. `Year` and `Favorites` are behind it.
        XCTAssertTrue(chip(Self.moreChip, app).isHittable, "the expandable control cannot be opened")
        XCTAssertFalse(
            app.otherElements[Self.rowLabel].buttons[Self.yearChip].exists,
            "“\(Self.yearChip)” is still a chip in the row; #145 moved it behind “\(Self.moreChip)”"
        )
        XCTAssertFalse(
            app.buttons[Self.hiddenChip].exists,
            "“\(Self.hiddenChip)” is still a chip in the row; R23.1 moved it behind "
                + "“\(Self.moreChip)”"
        )

        // And nothing is offering a way out of a filter nobody has set.
        XCTAssertTrue(
            clearControls(app).isEmpty,
            "“\(Self.clear)” is drawn over an unfiltered map, with nothing to clear"
        )
    }

    /// Turning a chip on changes what it announces, in both channels a listener has.
    ///
    /// `Yours`, because it is the one row toggle that is live on every machine in every month.
    func testTurningAChipOnIsAnnouncedInBothChannels() {
        let app = launch()
        _ = requireField(app)

        let yours = chip(Self.alwaysOnToggle, app)
        yours.tap()
        XCTAssertTrue(
            wait { (yours.value as? String) == Self.on },
            "after tapping it the “\(Self.alwaysOnToggle)” chip still announces "
                + "“\(yours.value as? String ?? "nothing")”"
        )
        XCTAssertTrue(
            yours.isSelected,
            "the “\(Self.alwaysOnToggle)” chip is on and does not carry the selected trait"
        )

        // Off again: every live chip in this row is a toggle (R23 §1).
        yours.tap()
        XCTAssertTrue(
            wait { (yours.value as? String) == Self.off },
            "tapping an on chip did not turn it off — it announces "
                + "“\(yours.value as? String ?? "nothing")”"
        )
    }

    /// **A chip that cannot match spends no tap** (task #136, RULINGS R31).
    ///
    /// `Needs care` is the chip this holds for on every machine: no data anywhere could satisfy it,
    /// so it is dimmed, its value is the reason rather than a state, and pressing where it draws
    /// activates nothing — no filter, no `Clear filters`, and never E126's card, which would only
    /// repeat what the chip already said.
    func testADisabledConditionChipSaysWhyAndSpendsNoTap() {
        let app = launch()
        _ = requireField(app)

        let needsCare = chip(Self.alwaysDisabledChip, app)
        XCTAssertFalse(
            needsCare.isEnabled,
            "no tree in the shipped seed or this device's store is declining, and the "
                + "“\(Self.alwaysDisabledChip)” chip is enabled — a control that promises and "
                + "cannot deliver (R31)"
        )
        let reason = needsCare.value as? String ?? ""
        XCTAssertFalse(
            reason.isEmpty || reason == Self.off || reason == Self.on,
            "the disabled chip announces “\(reason)” instead of the reason it is disabled"
        )

        // A press lands where the chip draws, and nothing happens.
        needsCare.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        _ = wait(timeout: 3) { false }
        XCTAssertTrue(
            clearControls(app).isEmpty,
            "pressing a disabled chip activated a filter: “\(Self.clear)” is on screen"
        )
        XCTAssertFalse(
            app.staticTexts["Nothing matches here"].exists,
            "pressing a disabled chip reached E126's card — the tap R31 says must never be spent"
        )
    }

    // MARK: - 2 · The expandable control (R23.1, #145)

    /// **Shut means shut: the drawer's contents are out of the accessibility tree, not merely out of
    /// sight** — both of them, the toggle and the year menu.
    func testTheHiddenFiltersAreOnlyInTheTreeWhileTheControlIsOpen() {
        let app = launch()
        _ = requireField(app)
        _ = chip(Self.moreChip, app)

        XCTAssertFalse(
            app.buttons[Self.hiddenChip].exists,
            "“\(Self.hiddenChip)” is reachable while the control holding it is shut — a filter a "
                + "sighted reader cannot see and an assistive technology can still press"
        )
        XCTAssertFalse(
            app.buttons[Self.yearChip].exists,
            "“\(Self.yearChip)” is reachable while the control holding it is shut (#145)"
        )

        let hidden = openDrawer(app)
        XCTAssertTrue(
            hidden.isHittable,
            "“\(Self.hiddenChip)” is in the tree with the control open and nothing can activate it"
        )
        XCTAssertEqual(
            hidden.value as? String, Self.off,
            "“\(Self.hiddenChip)” announces “\(hidden.value as? String ?? "nothing")” at rest"
        )

        // The year control kept its whole contract through the move: a `Menu` carrying a value,
        // announcing `Any year` before a decade is chosen.
        let year = app.buttons[Self.yearChip]
        XCTAssertTrue(
            year.waitForExistence(timeout: 10),
            "#145 moved “\(Self.yearChip)” into the control and the open control does not hold it"
        )
        XCTAssertTrue(year.isHittable, "the year control is in the open drawer and cannot be opened")
        XCTAssertEqual(
            year.value as? String, Self.anyYear,
            "the year control announces “\(year.value as? String ?? "nothing")” before a decade is "
                + "chosen, so a listener is not told the map is unnarrowed by year"
        )

        // The group has a name of its own, so a reader navigating by element is told they have
        // arrived inside the control they just opened.
        XCTAssertTrue(
            app.otherElements[Self.moreChip].exists,
            "the opened control is not a named container, so its chips arrive unannounced"
        )

        shutDrawer(app)
        XCTAssertFalse(
            app.buttons[Self.yearChip].exists,
            "closing the control left “\(Self.yearChip)” in the accessibility tree"
        )
    }

    /// **A filter set behind a shut control says that it is set, and says what it is.**
    func testAShutControlSaysWhatIsSetInsideIt() {
        let app = launch()
        _ = requireField(app)

        let more = chip(Self.moreChip, app)
        XCTAssertEqual(
            more.value as? String, "Collapsed",
            "the control announces “\(more.value as? String ?? "nothing")” while shut and empty, so "
                + "a listener is not told whether pressing it opens or closes anything"
        )

        // `Yours` first, so the swap has something to take away.
        let yours = chip(Self.alwaysOnToggle, app)
        yours.tap()
        XCTAssertTrue(wait { (yours.value as? String) == Self.on }, "the “Yours” chip did not come on")

        let hidden = openDrawer(app)
        XCTAssertEqual(
            chip(Self.moreChip, app).value as? String, "Expanded",
            "the control does not announce that it is open"
        )
        hidden.tap()
        XCTAssertTrue(
            wait {
                (hidden.value as? String) == Self.on && (yours.value as? String) == Self.off
            },
            "turning “\(Self.hiddenChip)” on inside the control left the row announcing "
                + "Yours=\(yours.value as? String ?? "nil"); membership is single-select within "
                + "itself and the swap now has to cross two surfaces"
        )

        // Shut it again. This is the state the hazard is about.
        shutDrawer(app)
        let shut = chip(Self.moreChip, app)
        XCTAssertEqual(
            shut.value as? String, "Collapsed, on: \(Self.hiddenChip)",
            "the map is narrowed by “\(Self.hiddenChip)” and the shut control announces "
                + "“\(shut.value as? String ?? "nothing")” — a listener is given no way to find out "
                + "what is thinning the map"
        )
        XCTAssertTrue(
            shut.isSelected,
            "the shut control does not carry the selected trait while something inside it is on"
        )

        // …and the way out is still on screen, in the row, where it can be found without knowing the
        // filter exists (R23.1 §3).
        XCTAssertEqual(
            clearChip(app).isHittable, true,
            "with a filter set behind a shut control there is no reachable “\(Self.clear)”"
        )
    }

    // MARK: - 3 · The way out appears with the thing it undoes

    /// `Clear filters` appears only when something is on, is a real labelled control, and works —
    /// **including on a filter that is set behind the shut control**, which is R23.1 §3's whole
    /// argument for there being one of these rather than two.
    func testClearFiltersAppearsWithTheFilterAndTakesAwayEvenTheHiddenOne() {
        let app = launch()
        _ = requireField(app)

        XCTAssertTrue(clearControls(app).isEmpty, "“\(Self.clear)” is drawn before anything is on")

        turnFavoritesOn(app)

        XCTAssertTrue(
            wait { !self.clearControls(app).isEmpty },
            "a filter is on behind a shut control and no “\(Self.clear)” is drawn, so the only way "
                + "out is to remember that it is there"
        )
        let chipOut = clearChip(app)
        XCTAssertTrue(
            chipOut.isHittable,
            "the “\(Self.clear)” chip is in the tree but nothing can activate it"
        )
        XCTAssertEqual(
            chipOut.value as? String, Self.off,
            "the “\(Self.clear)” chip announces “\(chipOut.value as? String ?? "nothing")”; it is "
                + "not a state, so it must not claim to be one"
        )

        chipOut.tap()
        XCTAssertTrue(
            wait { self.clearControls(app).isEmpty },
            "“\(Self.clear)” stayed on screen after clearing the filter"
        )
        XCTAssertEqual(
            chip(Self.moreChip, app).value as? String, "Collapsed",
            "clearing the filters left the control announcing "
                + "“\(chip(Self.moreChip, app).value as? String ?? "nothing")”, so a narrowing that "
                + "is gone from the map is still being reported in the row"
        )
    }

    /// The empty notice says why the map is empty **and** offers a reachable control that fixes it.
    ///
    /// The precondition is stated and guarded rather than assumed: `Favorites` empties the map on
    /// any device that has never favorited a tree, and the guard announces the skip when that does
    /// not hold (#121).
    func testTheEmptyNoticeOffersASecondWayOutAndItWorks() throws {
        let app = launch()
        _ = requireField(app)

        try requireAnEmptyFavoritesMap(app, caller: "testTheEmptyNoticeOffersASecondWayOutAndItWorks")
        let title = app.staticTexts[Self.favoritesEmptyTitle]

        // Two ways out, both labelled — the chip in the row and the button on the card (R23 §1).
        XCTAssertTrue(
            wait { self.clearControls(app).count == 2 },
            "an emptied map offers \(clearControls(app).count) controls labelled “\(Self.clear)”, "
                + "and R23 requires two: the chip in the row and the button on the notice"
        )
        let noticeButton = try XCTUnwrap(clearOnTheNotice(app), "the notice drew no way out")
        XCTAssertTrue(
            noticeButton.isHittable,
            "the notice's way out is in the accessibility tree and nothing can touch it — which is "
                + "the covered-but-reachable failure this screen has shipped before"
        )
        XCTAssertGreaterThan(
            noticeButton.frame.minY, chip(Self.moreChip, app).frame.maxY,
            "the “\(Self.clear)” this test took for the notice's is up in the filter row"
        )

        noticeButton.tap()
        XCTAssertTrue(
            wait { !title.exists },
            "pressing the notice's way out left the notice on screen"
        )
        XCTAssertEqual(
            chip(Self.moreChip, app).value as? String, "Collapsed",
            "the notice's way out did not clear the hidden filter: the control still announces "
                + "“\(chip(Self.moreChip, app).value as? String ?? "nothing")”"
        )
    }

    // MARK: - 4 · The line over the map

    /// `MapFilterCopy.result`'s two forms and nothing else: `31 trees`, `1 tree`, or
    /// `1458 trees—showing 151`. An em dash with no spaces around it (ARCHITECTURE §5.7).
    private static let countGrammar = "^[0-9]+ tree(s)?(—showing [0-9]+)?$"

    /// Any element that is only *part* of a count — a bare number, or the tail of the thinned form.
    private static let fragmentGrammar = "^([0-9]+|trees?|showing [0-9]+|—showing [0-9]+)$"

    private func countLines(_ app: XCUIApplication) -> [XCUIElement] {
        app.staticTexts
            .matching(NSPredicate(format: "label MATCHES %@", Self.countGrammar))
            .allElementsBoundByIndex
    }

    private func countFragments(_ app: XCUIApplication) -> [XCUIElement] {
        app.staticTexts
            .matching(NSPredicate(format: "label MATCHES %@", Self.fragmentGrammar))
            .allElementsBoundByIndex
    }

    /// **The count yields when the notice is already speaking** (R23 §5).
    func testTheCountYieldsToTheNotice() throws {
        let app = launch()
        _ = requireField(app)

        try requireAnEmptyFavoritesMap(app, caller: "testTheCountYieldsToTheNotice")

        // Settled: the notice and the count are published from the same model pass, so a read taken
        // the instant the notice appears can catch a count on its way out.
        _ = wait(timeout: 3) { false }
        XCTAssertEqual(
            countLines(app).map(\.label), [],
            "the map is empty and the notice is explaining why, and a count is sitting in the "
                + "chrome above it saying the same thing in weaker words (R23 §5)"
        )
    }

    // ── The year control's caveat, and why there is no UI test for it ───────────────────────────
    //
    // A SwiftUI `Menu`'s platter is in no element tree XCUITest hands back (E183 §4): tapping
    // `Year` draws `Any year · Before 1990 · …` on the glass and `app.buttons["2010s"]` finds
    // nothing, here or on springboard. So no test drives a decade on, and the caveat sentence's
    // rendering path is covered the way E183 records — its text and the 80.78 % by the unit suite,
    // the one-element mechanism by `testTheResultLineIsOneCountingPhrase` below. #145 moves the
    // menu inside the drawer and changes none of that.

    /// **The result line is one counting phrase, not a number and some words beside it** (E38).
    ///
    /// The one precondition in this file that depends on the viewport, stated and announced: the
    /// legend needs a species coloured on the glass.
    func testTheResultLineIsOneCountingPhrase() throws {
        let app = launch()
        _ = requireField(app)

        // Read off the glass, never assumed: `MapSpeciesLegendCopy.chipLabel` is
        // "<name>, <colour> pins marked <mark>".
        let legend = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", " pins marked "))
        _ = wait(timeout: 25) { legend.count > 0 }
        guard legend.count > 0 else {
            let message =
                "screen 01 has coloured no species in this viewport, so its legend — which R23 made "
                + "the species filter — has no entry to tap, and there is no filter available that "
                + "leaves the map holding anything to count. The map colours a species only where it "
                + "drew at least two of its pins. Put the map over some streets: xcrun simctl "
                + "location DE8E11AE-4375-4C3B-A296-9B60A7DF1DB3 set 37.78485,-122.4215 (and note "
                + "that `simctl location clear` does not unfix a device — revoke the app's location "
                + "grant to do that)."
            announceSkip(message, test: "testTheResultLineIsOneCountingPhrase")
            throw XCTSkip(message)
        }
        let entry = legend.element(boundBy: 0)
        let name = entry.label
        entry.tap()

        XCTAssertTrue(
            wait { (entry.value as? String) == Self.on },
            "tapping the legend entry “\(name)” did not turn the species filter on; it announces "
                + "“\(entry.value as? String ?? "nothing")”"
        )
        XCTAssertTrue(
            wait { self.countLines(app).count == 1 },
            "narrowing the map to “\(name)” — a species this very viewport is drawing at least two "
                + "pins of — put \(countLines(app).count) result lines over the map. The tree holds "
                + "\(countLines(app).map(\.label))"
        )
        // And nothing beside it is a piece of the same sentence.
        XCTAssertEqual(
            countFragments(app).map(\.label), [],
            "the result line has been split: the tree also holds "
                + "\(countFragments(app).map(\.label)), which a reader meets as separate facts"
        )
        XCTAssertGreaterThan(
            countLines(app)[0].frame.height, 0,
            "the result line has no frame, so it is in the tree and on nobody's screen"
        )
    }

    /// A skip nobody has to go looking for (#121).
    private func announceSkip(_ message: String, test: String) {
        let banner = String(repeating: "=", count: 78)
        print("\n\(banner)\nSKIPPED · MapFilterAccessibilityTests.\(test)")
        print("\(message)\n\(banner)\n")
        fflush(stdout)
    }

    // MARK: - 5 · AX5 on a 390 pt phone

    /// **The row wraps rather than running off the edge of the phone, and every control stays on
    /// it — including R31's disabled chips, which carry a whole sentence, and the drawer's two.**
    ///
    /// This is #98 restated, and the disabled chips are its likeliest new instance: `FlowRow`
    /// measures children unconstrained, so a chip holding a sentence takes the width it asks for —
    /// which is why `MapLayout.unavailableChipWidth` is fixed, and why this test measures rather
    /// than trusts.
    func testTheFilterRowWrapsAndStaysOnThePhoneAtAX5() {
        let app = launchAtAX5()
        _ = requireField(app)

        // The `Clear filters` chip only exists once something is on — so the widest state of this
        // row is only reachable by turning a filter on first, through the drawer.
        turnFavoritesOn(app)
        XCTAssertTrue(
            wait { !self.clearControls(app).isEmpty },
            "no “\(Self.clear)” chip at AX5, so the row's widest state cannot be measured"
        )

        // The claims below are about *this* phone's edges, whatever its width — E183 measured on a
        // 390 pt 16e; this branch's assigned simulator is a 440 pt Pro Max, and a hard-coded 390
        // would fail the test for owning the wrong hardware rather than for any defect. The wrap
        // and the edges are the assertions; the width is wherever the suite runs.
        let screen = app.windows.firstMatch.frame
        XCTAssertLessThan(
            screen.width, 500,
            "this looks like an iPad (\(screen.width) pt); the wrap claim is about phones"
        )

        var boxes: [(String, CGRect)] = []
        for label in [Self.alwaysOnToggle] + Self.conditionChips + [Self.moreChip] {
            boxes.append((label, chip(label, app).frame))
        }
        boxes.append((Self.clear, clearChip(app).frame))

        // **AX5 actually arrived.** A filter chip is ~30 pt tall as drawn and cannot be at the top
        // of the ramp; an argument that stopped working would make everything below a statement
        // about the drawn size.
        let tallest = boxes.map(\.1.height).max() ?? 0
        XCTAssertGreaterThan(
            tallest, 44,
            "the tallest chip in the row is \(tallest) pt, which is the drawn size — "
                + "-UIPreferredContentSizeCategoryName did not take, so nothing below is a "
                + "statement about AX5"
        )

        assertOnThePhone(boxes, screen: screen, where: "the row")

        // It wrapped. Five controls at AX5 — two of them carrying sentences — cannot be one line
        // on this phone, so a row reporting one line is a row that stopped wrapping.
        let lines = Set(boxes.map { Int(($0.1.minY / 4).rounded()) })
        XCTAssertGreaterThan(
            lines.count, 1,
            "at AX5 all the row's chips report the same line: \(boxes.map { "\($0.0) \($0.1)" })"
        )

        // And every live control can still be pressed there.
        for label in [Self.alwaysOnToggle, Self.moreChip] {
            XCTAssertTrue(
                chip(label, app).isHittable,
                "at AX5 the “\(label)” chip is in the accessibility tree and cannot be activated. "
                    + "Its frame is \(chip(label, app).frame) on a \(screen.width)×\(screen.height) "
                    + "screen"
            )
        }
        XCTAssertTrue(
            clearChip(app).isHittable,
            "at AX5 the “\(Self.clear)” chip cannot be activated"
        )

        // The drawer is the surface nobody looks at above the drawn size. It opens *below* an
        // already-wrapped row, holding a toggle and a menu, on the tallest text size the ramp has.
        let hidden = openDrawer(app)
        let year = app.buttons[Self.yearChip]
        XCTAssertTrue(year.waitForExistence(timeout: 10), "the open drawer holds no year control")
        assertOnThePhone(
            [(Self.hiddenChip, hidden.frame), (Self.yearChip, year.frame)],
            screen: screen,
            where: "the open control"
        )
        XCTAssertTrue(
            hidden.isHittable,
            "at AX5 the chip inside the expandable control is in the tree and cannot be activated. "
                + "Its frame is \(hidden.frame) on a \(screen.width)×\(screen.height) screen"
        )
        XCTAssertTrue(
            year.isHittable,
            "at AX5 the year control inside the drawer is in the tree and cannot be activated"
        )
    }

    /// **The empty notice at AX5 — E183 §2's pinned defect, unchanged in substance by the
    /// restructure.** Strict `XCTExpectFailure`: the test passes today *because* the defect is
    /// there, and turns red the day somebody fixes the layout, at which point they delete the
    /// wrapper.
    func testTheEmptyNoticesWayOutIsUnreachableAtAX5() throws {
        let app = launchAtAX5()
        _ = requireField(app)
        try requireAnEmptyFavoritesMap(app, caller: "testTheEmptyNoticesWayOutIsUnreachableAtAX5")

        XCTAssertTrue(
            wait { self.clearControls(app).count == 2 },
            "at AX5 an emptied map drew \(clearControls(app).count) controls labelled "
                + "“\(Self.clear)”; this test is about the second one"
        )
        let screen = app.windows.firstMatch.frame
        let notice = clearOnTheNotice(app)

        // **The defect is a function of the phone's size, measured rather than assumed.** E183
        // pinned it on a 390 pt 16e; on this branch's assigned 440 pt Pro Max the same notice fits
        // and its button works, so a strict expected-failure here would fail for owning the wrong
        // hardware. The two arms are the two honest sentences: where the defect reproduces it is
        // pinned (strict — red the day it is fixed, delete the wrapper), and where it does not,
        // E126's contract must simply hold.
        let defectReproduces: Bool = {
            guard let notice else { return true }
            return !screen.contains(notice.frame) || !notice.isHittable
        }()
        if defectReproduces {
            XCTExpectFailure(
                "E183: at AX5 the empty notice is taller than the phone and grows off the top of "
                    + "it, taking E126's way out with it. Not fixed here — the fix is a layout "
                    + "ruling R23 left open. Delete this wrapper when it is."
            ) {
                XCTAssertNotNil(notice, "at AX5 the notice drew no way out at all")
                if let notice {
                    XCTAssertTrue(
                        screen.contains(notice.frame),
                        "at AX5 the notice's “\(Self.clear)” is at \(notice.frame) on a "
                            + "\(screen.width)×\(screen.height) screen"
                    )
                    XCTAssertTrue(
                        notice.isHittable,
                        "at AX5 the notice's “\(Self.clear)” is in the tree at \(notice.frame) and "
                            + "cannot be activated"
                    )
                }
            }
        } else {
            XCTAssertTrue(
                notice?.isHittable == true,
                "on a \(screen.width) pt phone the notice's way out fits and still cannot be "
                    + "activated — a new defect, not E183's"
            )
        }

        // What *is* still true at AX5, and is the reason the screen is not a dead end: the chip in
        // the row is the other way out, it is on the phone, and it works (R23.1 §3).
        XCTAssertTrue(
            clearChip(app).isHittable,
            "at AX5 neither way out of an emptied map can be activated: the notice's button is off "
                + "the top of the screen and the row's chip is at \(clearChip(app).frame)"
        )
        clearChip(app).tap()
        XCTAssertTrue(
            wait { self.clearControls(app).isEmpty },
            "at AX5 the row's chip did not clear the filter"
        )
    }

    /// Every frame inside the display, left edge and right edge (#98).
    private func assertOnThePhone(
        _ boxes: [(String, CGRect)],
        screen: CGRect,
        where place: String
    ) {
        for (label, box) in boxes {
            XCTAssertGreaterThanOrEqual(
                box.minX, screen.minX - 0.5,
                "at AX5 the “\(label)” chip in \(place) starts \(box.minX) pt from the left edge of "
                    + "a \(screen.width) pt screen — it is off the phone"
            )
            XCTAssertLessThanOrEqual(
                box.maxX, screen.maxX + 0.5,
                "at AX5 the “\(label)” chip in \(place) runs to \(box.maxX) pt on a "
                    + "\(screen.width) pt screen, so the end of its label is off the edge. Its "
                    + "frame is \(box)"
            )
        }
    }

    // MARK: - 6 · The two features, together

    /// **The suggestion list and the filter row, with a filter already on** (R25 §1's other half).
    ///
    /// The claim: the chips move rather than being covered, they stay hittable, and the row's own
    /// order is unchanged — the owner's three, the control, the way out.
    func testAnOpenSuggestionListLeavesTheWholeFilterRowOrderedAndHittable() {
        let app = launch()
        let field = requireField(app)

        turnFavoritesOn(app)
        XCTAssertTrue(
            wait { !self.clearControls(app).isEmpty },
            "turning a filter on drew no “\(Self.clear)” chip, so the state this test is about "
                + "does not exist"
        )

        let yours = chip(Self.alwaysOnToggle, app)
        let before = (yours: yours.frame.minY, clear: clearChip(app).frame.minY)

        field.tap()
        field.typeText(Self.query)

        let row = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", Self.rowPrefix))
            .firstMatch
        XCTAssertTrue(
            row.waitForExistence(timeout: 25),
            "typing “\(Self.query)” drew no row beginning “\(Self.rowPrefix)”"
        )
        XCTAssertFalse(
            String(row.label.dropFirst(Self.rowPrefix.count))
                .trimmingCharacters(in: .whitespaces).isEmpty,
            "the suggestion row announces “\(row.label)” and nothing behind the comma"
        )

        // Moved down, not covered — for the ordinary chips and for the one that is new.
        XCTAssertTrue(
            wait { yours.frame.minY > before.yours },
            "the suggestion list did not push the “\(Self.alwaysOnToggle)” chip down "
                + "(\(before.yours) → \(yours.frame.minY)), so it is drawn over it"
        )
        XCTAssertTrue(
            wait { self.clearChip(app).frame.minY > before.clear },
            "the suggestion list did not push the “\(Self.clear)” chip down "
                + "(\(before.clear) → \(clearChip(app).frame.minY))"
        )
        XCTAssertTrue(
            yours.isHittable,
            "with the list open the “\(Self.alwaysOnToggle)” chip is in the tree and cannot be "
                + "activated"
        )
        XCTAssertTrue(
            clearChip(app).isHittable,
            "with the list open the “\(Self.clear)” chip is in the tree and cannot be activated"
        )

        // **The row's own order in the element tree** — the owner's three, the control, the way
        // out (#145). Scoped to the row's container because the notice's `Clear filters` shares a
        // label with the chip.
        let rowButtons = app.otherElements[Self.rowLabel].buttons.allElementsBoundByIndex
        let rowOrder = rowButtons.map(\.label).filter { !$0.isEmpty }
        XCTAssertEqual(
            rowOrder,
            [Self.alwaysOnToggle] + Self.conditionChips + [Self.moreChip, Self.clear],
            "with the suggestion list open the filter row is reached in this order: \(rowOrder)"
        )
        // **The row holds no reachable unlabelled control** (E103, structurally). The `Menu`'s
        // unlabelled leftover element moved into the drawer with the year chip (#145), so at rest
        // there should be none at all — and any that appears must stay unreachable.
        for blank in rowButtons where blank.label.isEmpty {
            XCTAssertFalse(
                blank.isHittable,
                "an unlabelled control at \(blank.frame) is reachable inside the filter row"
            )
        }
    }

    // ── The swipe order, and why there is no XCUITest for it (task #143) ────────────────────────
    //
    // #143 fixed R25 §1's swipe order with explicit `accessibilitySortPriority` values on screen
    // 01's chrome, and the swipe-order test this file was told to carry was written, run against
    // the pre-fix tree (red, for E183 §3's own reasons), and then run against the fixed tree —
    // where it stayed red, with `app.buttons` returning the **identical 24-element order** it
    // returned before the fix. Two further instrumented runs pinned the instrument rather than the
    // fix:
    //
    //   · the global `app.buttons` order violates the view hierarchy (the top block's ✕ and its
    //     chips enumerate on opposite sides of the tab bar, which is a different ZStack sibling),
    //     violates geometry (the bottom chrome enumerates before elements far above it), violates
    //     creation order, and does not move by a single transposition under sort priorities;
    //   · wrapping the sorted siblings in an explicit `.accessibilityElement(children: .contain)`
    //     changes the order — so the channel does see structure — but still not to the priority
    //     order, and forcing the container to rebuild on focus (`.id`) hangs the run loop under
    //     `typeText` for 30 s.
    //
    // So `app.buttons` enumeration is **not the VoiceOver reading order and cannot witness this
    // fix** — which also means E183 §3's measurement was a fact about XCUITest's enumeration, not
    // about a listener's swipe order (its own listing already contradicted its prose: `Clear
    // search` sat *before* the four tabs). Asserting the reading order through this channel would
    // be E183 §4's mistake — a sentence about XCUITest presented as a sentence about the app —
    // and driving real VoiceOver is not something XCUITest can do. The fix ships on Apple's
    // documented contract for `accessibilitySortPriority`; **verification is owed on the phone
    // with VoiceOver on**, and the pending erratum for #143 records the debt. What this file
    // still asserts about the same surface: the chips move rather than being covered, they stay
    // hittable, and the row's own internal order is the owner's (the test above).

    /// The query typed into C20, and the prefix a row for it must begin with.
    ///
    /// Borrowed from `MapSuggestionUITests` and for its reasons: the *catalogue* is bundled with the
    /// app and is the same on every machine, so this resolves to the same suggestions wherever the
    /// map is pointed. The scientific name is deliberately not written down.
    private static let query = "cypress"
    private static let rowPrefix = "Monterey Cypress, "
}
