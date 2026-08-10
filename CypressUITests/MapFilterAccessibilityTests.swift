import XCTest

/// **Screen 01's filter row and its expandable control, driven the way an assistive technology
/// reaches them** (task #135; the design is RULINGS **R23** as amended by **R23.1**, restructured
/// by task #145, and re-cut by the owner's directives in tasks #165, #166 and #180; the dropdown
/// beside it is **R25**).
///
/// The result line this file used to drive is gone — **RULINGS R41**, task #180: no message ever
/// accompanies a filter. Section 4 is now the structural test that keeps it gone.
///
/// ── Why this file exists ─────────────────────────────────────────────────────────────────────────
/// #116 shipped the row and its own report says plainly: "No UI tests written — `CypressUITests` was
/// not run at all." Everything about it was verified by driving the simulator by hand.
/// `CypressTests/MapFilterTests` proves the *values* are right; it cannot prove any of them reach a
/// finger or a VoiceOver reader, because SwiftUI builds no in-process accessibility tree
/// (ARCHITECTURE §7, E116).
///
/// ── What #165 and #166 changed about this file's subject ────────────────────────────────────────
/// The row is `Yours · In bloom · Needs care · More filters`, with `Favorites` and `Year` behind
/// that last control (#145). Two owner directives then re-cut the presentation, and this file pins
/// both:
///
///   · **#165 — every chip is an ordinary tappable pill, always.** R31's disabled-with-reason
///     chips and E126's empty-notice card are both gone; a filter that matches nothing renders
///     the empty map, and the `Clear filters` chip in the row is the one way out. `Needs care` —
///     which R31 kept disabled on every machine, the seed carrying only `alive` and `vacant_site`
///     — is therefore this file's reliable live-pill-that-matches-nothing.
///   · **#166 — the row is one horizontally scrolling line, never a second one.** The wrap this
///     row shipped with (`FlowRow`) is gone; chips past the trailing edge are reached by
///     scrolling the row, not by a second line. The one-line fact and the reachability of the
///     off-edge chips are both asserted, at the default size and at AX5.
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

    /// The first chip in the row, always on-screen without scrolling.
    private static let alwaysOnToggle = "Yours"

    /// `MapFilter.Condition.allCases.map(\.label)`, the owner's order.
    private static let conditionChips = ["In bloom", "Needs care"]

    /// The pill that matches nothing on every machine (#165): the seed's only statuses are `alive`
    /// (174,425) and `vacant_site` (24,200), and no black-box test can inject a community
    /// observation — so tapping it is this file's reliable way to a live filter over an empty map.
    private static let matchlessChip = "Needs care"

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

    /// `MapFilterCopy.clearLabel`. Since #165 removed the empty notice, the chip in the row is the
    /// **only** control that carries this label — `testNoMessageBoxStandsInForAnEmptyFilter` pins
    /// that.
    private static let clear = "Clear filters"

    /// `MapFilterCopy.rowLabel`, the container's own name.
    private static let rowLabel = "Filter trees"

    /// The three titles the deleted empty-notice card used to draw (#165). Any of them on screen
    /// is the message box the owner struck, back from the dead.
    private static let struckNoticeTitles = [
        "No trees of yours here", "No favorites here", "Nothing matches here"
    ]

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
            "screen 01's filter row has no chip labeled “\(label)”"
        )
        return element
    }

    /// The row's named container, resolved to whichever element type it has settled into.
    ///
    /// It rides on the `ScrollView` since the row became one (#166) — `MapChrome` puts the label on
    /// the scroller, and its own comment records that the outer `VStack`'s group vanished from the
    /// tree when the chips moved inside. That is the app's decision and not a fact about XCUITest,
    /// which is exactly why this waits for it rather than reading it once: see
    /// `ContainerSpellingResolution` (`UIWait.swift`), where the same pattern's un-waited read
    /// intermittently bound the *species legend* to a spelling that was about to disappear.
    ///
    /// **The default ceiling, not the 25 s the line it replaced used.** The old spelling gave the
    /// container 25 s to *exist*; this one needs it to exist and then hold one spelling still for
    /// `ContainerSpellingResolution.settlingWindow` within the same budget, so 25 s here would have
    /// been a real four-second cut to a row that has never been measured arriving late.
    private func rowContainer(_ app: XCUIApplication) -> XCUIElement {
        resolvedContainer(
            app,
            labeled: Self.rowLabel,
            "the filter row's named container (“\(Self.rowLabel)”) — without it the row's chips "
                + "arrive unannounced between the search field and the map"
        )
    }

    /// Drags the row one screen's worth, anchored on whichever chip is currently on the glass —
    /// a drag that starts on a chip scrolls the row, which is #166's own interaction.
    private func swipeRow(_ app: XCUIApplication, left: Bool) {
        let anchors = [Self.alwaysOnToggle] + Self.conditionChips + [Self.moreChip, Self.clear]
        // `app.frame` is a query; read once rather than once per anchor, and this helper is called
        // from inside `revealedChip`'s swipe loops. See `isHittableWithoutRaising(onScreen:)`.
        let appFrame = app.frame
        guard let anchor = anchors.map({ app.buttons[$0] })
            .first(where: { $0.exists && $0.isHittableWithoutRaising(onScreen: appFrame) }) else { return }
        left ? anchor.swipeLeft() : anchor.swipeRight()
    }

    /// **Scrolls the one-line row until the chip is on the glass** (#166), and returns it.
    ///
    /// The row scrolls where it used to wrap, so a chip past the trailing edge *exists* in the
    /// tree with a frame beyond the display and cannot be pressed until the row is dragged. The
    /// loops are bounded (a stalled scroll must fail the caller's assertion, not hang the suite),
    /// and the second loop drags back for callers that need a chip near the leading edge.
    ///
    /// **`isHittable` alone is not the same claim as "safe to tap".** It is a snapshot of this
    /// instant; a chip mid-momentum-scroll can be hittable the moment this loop checks and be
    /// somewhere else — under an adjacent chip's coordinates — by the time a caller's `.tap()`
    /// actually synthesizes. Every caller here either taps the return value directly or asserts
    /// `isHittable` on it and then taps a moment later, so once the loops above have found it
    /// hittable, this also waits for the row's drag to have finished settling before handing the
    /// chip back — through the same `settledFrame` every other geometry read in this suite goes
    /// through, not a second wait spelled out here. An element that never became hittable is
    /// returned exactly as before: every caller already has its own assertion, and its own
    /// message, for that case.
    @discardableResult
    private func revealedChip(_ label: String, _ app: XCUIApplication) -> XCUIElement {
        let element = chip(label, app)
        let appFrame = app.frame
        for _ in 0..<6 where !element.isHittableWithoutRaising(onScreen: appFrame) { swipeRow(app, left: true) }
        for _ in 0..<6 where !element.isHittableWithoutRaising(onScreen: appFrame) { swipeRow(app, left: false) }
        if element.isHittableWithoutRaising(onScreen: appFrame) {
            _ = settledFrame(element, "the “\(label)” chip", timeout: 5)
        }
        return element
    }

    /// Opens the expandable control and returns the chip inside it.
    @discardableResult
    private func openDrawer(_ app: XCUIApplication) -> XCUIElement {
        revealedChip(Self.moreChip, app).tap()
        let hidden = app.buttons[Self.hiddenChip]
        XCTAssertTrue(
            hidden.waitForExistence(timeout: 15),
            "pressing “\(Self.moreChip)” opened nothing: “\(Self.hiddenChip)” is not in the tree"
        )
        return hidden
    }

    /// Shuts the drawer and waits for its contents to leave the tree.
    private func shutDrawer(_ app: XCUIApplication) {
        revealedChip(Self.moreChip, app).tap()
        XCTAssertTrue(
            wait(timeout: 10) { !app.buttons[Self.hiddenChip].exists },
            "the control did not close"
        )
    }

    /// Turns `Favorites` on through the drawer and shuts the drawer again.
    private func turnFavoritesOn(_ app: XCUIApplication) {
        let hidden = openDrawer(app)
        hidden.tap()
        XCTAssertTrue(wait { (hidden.value as? String) == Self.on }, "the hidden chip did not come on")
        shutDrawer(app)
    }

    /// Every control labeled `Clear filters`. Since #165 there is at most one — the row's chip —
    /// and a second is the deleted notice's button resurrected.
    private func clearControls(_ app: XCUIApplication) -> [XCUIElement] {
        app.buttons.matching(NSPredicate(format: "label == %@", Self.clear)).allElementsBoundByIndex
    }

    // MARK: - 1 · Every chip is in the tree, labeled, live, and says its state

    /// The row at rest: every chip — the toggle, **both** condition chips (#165: never disabled,
    /// never a box), the expandable control — is an enabled button announcing its state, neither
    /// `Favorites` nor `Year` is in the row (R23.1, #145), and the chips sit on **one line**
    /// (#166).
    func testTheFilterRowIsReachableAndEveryChipIsALivePill() {
        let app = launch()
        _ = requireField(app)

        // `rowContainer` waits, and fails with its own sentence — naming both spellings it watched
        // and which of them it actually saw — if the row never settles into a named container.
        // Nothing is asserted on what it returns afterwards on purpose: on timeout the helper has
        // already failed and returns a fallback so that *something* can be returned, so an
        // `XCTAssertTrue(….exists)` here produced a SECOND failure for the one cause, carrying the
        // older sentence ("the filter row is not a named container") as though it were the only
        // explanation — and it was invisible only because this class sets `continueAfterFailure`
        // to false, which is a setting about something else.
        _ = rowContainer(app)

        let yours = chip(Self.alwaysOnToggle, app)
        assertReachable(yours, "the “\(Self.alwaysOnToggle)” chip")
        XCTAssertEqual(
            yours.value as? String, Self.off,
            "the “\(Self.alwaysOnToggle)” chip announces "
                + "“\(yours.value as? String ?? "nothing")” at rest"
        )
        XCTAssertFalse(yours.isSelected, "the chip carries the selected trait while nothing is on")

        // #165: both condition chips are ordinary toggles on every machine in every month. A
        // disabled one, or one whose value is a sentence instead of a state, is R31's presentation
        // back from the dead.
        for label in Self.conditionChips {
            let element = chip(label, app)
            XCTAssertTrue(
                element.isEnabled,
                "the “\(label)” chip renders disabled; #165 says every filter is a live pill "
                    + "whatever the data holds"
            )
            XCTAssertEqual(
                element.value as? String, Self.off,
                "the “\(label)” chip announces “\(element.value as? String ?? "nothing")” at rest"
            )
        }

        // #145: the row is the owner's three and the control. `Year` and `Favorites` are behind it.
        XCTAssertTrue(chip(Self.moreChip, app).exists, "the expandable control is not in the row")
        XCTAssertFalse(
            app.buttons[Self.yearChip].exists,
            "“\(Self.yearChip)” is still a chip in the row; #145 moved it behind “\(Self.moreChip)”"
        )
        XCTAssertFalse(
            app.buttons[Self.hiddenChip].exists,
            "“\(Self.hiddenChip)” is still a chip in the row; R23.1 moved it behind "
                + "“\(Self.moreChip)”"
        )

        // #166: one line. Whatever the phone's width, every chip in the row reports the same
        // vertical position — a second value is a second line.
        let lines = Set(
            ([Self.alwaysOnToggle] + Self.conditionChips + [Self.moreChip])
                .map { Int((chip($0, app).frame.minY / 4).rounded()) }
        )
        XCTAssertEqual(
            lines.count, 1,
            "at the default size the row's chips sit on \(lines.count) lines; the owner asked for "
                + "one row of filters, and the width past the edge belongs to the scroll (#166)"
        )

        // And nothing is offering a way out of a filter nobody has set.
        XCTAssertTrue(
            clearControls(app).isEmpty,
            "“\(Self.clear)” is drawn over an unfiltered map, with nothing to clear"
        )
    }

    /// Turning a chip on changes what it announces, in both channels a listener has.
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

        // Off again: every chip in this row is a toggle (R23 §1).
        yours.tap()
        XCTAssertTrue(
            wait { (yours.value as? String) == Self.off },
            "tapping an on chip did not turn it off — it announces "
                + "“\(yours.value as? String ?? "nothing")”"
        )
    }

    /// **A filter that matches nothing is still a pill, spends its tap, and no message box stands
    /// in for it or answers it** (task #165, overriding R31's presentation and E126's card).
    ///
    /// `Needs care` matches nothing on every machine — the seed's only statuses are `alive` and
    /// `vacant_site` — which under R31 kept it disabled and under #165 makes it exactly the state
    /// the owner ruled on: the pill toggles on, the map is allowed to be empty, the row's
    /// `Clear filters` chip is the one way out, and none of the deleted card's titles is on screen.
    func testNoMessageBoxStandsInForAnEmptyFilter() {
        let app = launch()
        _ = requireField(app)

        let needsCare = revealedChip(Self.matchlessChip, app)
        XCTAssertTrue(
            needsCare.isEnabled,
            "“\(Self.matchlessChip)” renders disabled; #165 struck that presentation — the pill is "
                + "always live, and a filter that matches nothing just empties the map"
        )
        needsCare.tap()
        XCTAssertTrue(
            wait { (needsCare.value as? String) == Self.on },
            "tapping “\(Self.matchlessChip)” did not turn it on — it announces "
                + "“\(needsCare.value as? String ?? "nothing")” (#165: the tap is spent, always)"
        )

        // The way out arrives with the filter, and it is the *only* control wearing the label:
        // the notice used to add a second one, and a second one is the notice back.
        XCTAssertTrue(
            wait { self.clearControls(app).count == 1 },
            "a filter is on and \(clearControls(app).count) controls are labeled “\(Self.clear)”; "
                + "#165 leaves exactly one — the chip in the row"
        )

        // Settled, then read: the titles the deleted card drew. The map behind them may or may not
        // be empty on this device — the claim #165 makes is that no such card exists on *any*
        // path, which is why the titles are checked rather than the emptiness.
        _ = wait(timeout: 3) { false }
        for title in Self.struckNoticeTitles {
            XCTAssertFalse(
                app.staticTexts[title].exists,
                "“\(title)” is on screen — the message box #165 deleted is back"
            )
        }

        // Off again, and the way out leaves with the filter.
        needsCare.tap()
        XCTAssertTrue(
            wait { self.clearControls(app).isEmpty },
            "clearing the condition left “\(Self.clear)” on screen"
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
        assertReachable(
            year,
            "“\(Self.yearChip)”, which #145 moved into the control the open drawer must hold"
        )
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
            revealedChip(Self.clear, app).isHittable, true,
            "with a filter set behind a shut control there is no reachable “\(Self.clear)”"
        )
    }

    // MARK: - 3 · The way out appears with the thing it undoes

    /// `Clear filters` appears only when something is on, is a real labeled control, and works —
    /// **including on a filter that is set behind the shut control**, which is R23.1 §3's whole
    /// argument for there being one of these rather than two. Since #165 it is also the *only*
    /// way out the screen draws, which raises the price of it not working.
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
        let chipOut = revealedChip(Self.clear, app)
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

    // MARK: - 4 · The line over the map, which must never exist again (RULINGS R41, task #180)
    //
    // ── R41's carve-out has exactly one occupant since task #247, and this section does not see
    //    it. Read this before adding a fourth narrowing below. ─────────────────────────────────
    //
    // R41 permits one form for anything judged genuinely essential — a popup, "never persistent on
    // the glass" — and judged that nothing qualified. The owner's instruction of 2026-08-06 put one
    // thing in it: pressing `Needs care` **on its own** over a map that comes back with nothing
    // draws a brief, self-dismissing toast reading `MapNeedsCareToastCopy.message`. It is text that
    // appears because a filter did something, and `assertNoCompanionText` would correctly fail on
    // it — the rule is unchanged and the exception is the owner's, not this file's.
    //
    // **It does not fire for any narrowing `testNoTextAccompaniesAFilter` drives**, and that is a
    // property of the gate rather than luck: `MapNeedsCareToast.isOwed` compares the whole
    // `MapFilter` against `.needsCare`, so the species entry alone, the species *conjoined with*
    // `Needs care`, and a filter set inside the drawer are all outside it. The narrowing that would
    // produce it is `Needs care` and nothing else, which this section never sets.
    //
    // So: a fourth case that turns `Needs care` on alone will see the toast, and must **not** be
    // "fixed" by excluding the sentence by name — that is the hard-coded-copy tolerance this file's
    // own comments forbid. The scope of the exception is pinned where it belongs, in
    // `CypressTests/MapNeedsCareToastTests`, which fails if any other filter can open the gate.

    /// `MapFilterCopy.result`'s two forms, kept as a *forbidden* shape: `31 trees`, `1 tree`, or
    /// `1458 trees—showing 151`. Nothing may match this any more.
    private static let countGrammar = "^[0-9]+ tree(s)?(—showing [0-9]+)?$"

    /// The year caveat R41 removed, matched on the *fact* it stated rather than its wording — a
    /// rewritten sentence that still said this would be the same defect (assert facts, not
    /// phrasing). Note it is a substring of the removed message and not of any chip: #179's
    /// `Empty planting site` says planting *site*, never planting *date*.
    private static let caveatSubstring = "planting date"

    /// Every static text on the glass right now.
    private func texts(_ app: XCUIApplication) -> Set<String> {
        Set(app.staticTexts.allElementsBoundByIndex.compactMap { $0.exists ? $0.label : nil })
    }

    /// Every control's label right now — the set of things that are a *chip's own voice*.
    ///
    /// **Buttons only, and that exclusion was measured rather than assumed.** This started as
    /// buttons ∪ `otherElements`, and the red-proof caught it: with a companion sentence deliberately
    /// restored to the map, the named caveat check failed and this diff did **not**, because a
    /// SwiftUI container is an `otherElement` that carries its child text's label — so every message
    /// exempted itself as its own wrapper. A container is not a control, and R41's sanctioned
    /// channels are chips. Narrowing this to `buttons` is what makes the diff able to fail.
    private func controlLabels(_ app: XCUIApplication) -> Set<String> {
        Set(app.buttons.allElementsBoundByIndex.compactMap { $0.exists ? $0.label : nil })
    }

    /// **The structural test RULINGS R41 asks for: no message ever accompanies a filter.**
    ///
    /// This file used to hold `testTheResultLineIsOneCountingPhrase`, which asserted that turning a
    /// filter on put *exactly one* counting phrase over the map. R41 reversed the requirement, so
    /// the test is inverted rather than deleted — the same treatment R38 gave the AX5 wrap test it
    /// replaced, and for the same reason: the file should still testify about this surface, and a
    /// deleted test testifies to nothing.
    ///
    /// ── Why it is a diff and not a list of forbidden strings ──────────────────────────────────
    /// R41's own test is "**does text appear because a filter did something?**", and that is a
    /// difference of sets. A test that banned today's two sentences by name would be the thing R41
    /// was written against: this is the third filter-adjacent message to be ruled out and the first
    /// two "survived under a different mechanism", so a guard that only knows the current mechanism
    /// is a guard that will be walked around. Anything that appears with a narrowing fails here,
    /// whatever it says and whichever view drew it.
    ///
    /// **The one thing that may appear is a control's own label.** R23.1's three channels are the
    /// sanctioned way for a narrowing to speak — the chip's fill, a count *on the chip*
    /// (`More filters (1)`), and its spoken value — and R41 keeps them explicitly: "on the chip is
    /// the chip's voice, not a companion message". So text is a violation exactly when nothing on
    /// screen answers to it as a control. `Clear filters` appearing is fine; a capsule saying
    /// `31 trees` is not.
    ///
    /// Each of the three narrowings below is applied and then **cleared**, and the reading with it
    /// on is compared against the readings either side of it. `assertNoCompanionText` explains why
    /// that is the whole of the fix for a false red this test produced on the merged tree.
    func testNoTextAccompaniesAFilter() throws {
        let app = launch()
        _ = requireField(app)

        // Read off the glass, never assumed: `MapSpeciesLegendCopy.chipLabel` is
        // "<name>, <color> pins marked <mark>". The legend is R23's species filter, and it is the
        // one narrowing this file can drive that leaves the map holding something to count — the
        // state the removed line used to appear in.
        let legend = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", " pins marked "))
        _ = wait(timeout: 25) { legend.count > 0 }
        guard legend.count > 0 else {
            let message =
                "screen 01 has colored no species in this viewport, so its legend — which R23 made "
                + "the species filter — has no entry to tap, and there is no filter available that "
                + "leaves the map holding anything to count. The map colors a species only where it "
                + "drew at least two of its pins. Put the map over some streets: xcrun simctl "
                + "location \(runningDeviceUDID) set 37.78485,-122.4215 (and note "
                + "that `simctl location clear` does not unfix a device — revoke the app's location "
                + "grant to do that). ERRATA E202 is worth reading before believing a red here."
            announceSkip(message, test: "testNoTextAccompaniesAFilter")
            throw XCTSkip(message)
        }
        let entry = legend.element(boundBy: 0)
        let species = entry.label

        // One narrowing, from the row's own surface.
        assertNoCompanionText(app, narrowing: "the species “\(species)”") {
            entry.tap()
            XCTAssertTrue(
                self.wait { (entry.value as? String) == Self.on },
                "tapping the legend entry “\(species)” did not turn the species filter on; it "
                    + "announces “\(entry.value as? String ?? "nothing")”, so nothing that follows "
                    + "is a statement about a narrowed map"
            )
        }

        // Two at once, because R41 is about *any* filter state and a conjunction is the state most
        // likely to grow a summarizing sentence.
        assertNoCompanionText(
            app, narrowing: "the species “\(species)” and “\(Self.conditionChips[1])”"
        ) {
            entry.tap()
            self.chip(Self.conditionChips[1], app).tap()
            XCTAssertTrue(
                self.wait { (self.chip(Self.conditionChips[1], app).value as? String) == Self.on },
                "“\(Self.conditionChips[1])” did not turn on"
            )
        }

        // And a narrowing set from *inside* the drawer — the surface #179 adds a control to, and
        // the one R23.1 warns can narrow the map with nothing visible saying so.
        assertNoCompanionText(app, narrowing: "a filter set inside “\(Self.moreChip)”") {
            self.turnFavoritesOn(app)
        }
    }

    /// **The assertion, and it asks R41's question the way R41 asks it.**
    ///
    /// ── Why this turns the filter back off instead of trusting a baseline ────────────────────
    /// This began as a straight before/after diff: record the text on the un-narrowed map, narrow,
    /// and fail on anything new. That is a *temporal* test, and R41's question is a **causal** one —
    /// "does text appear because a filter did something?" On a device where the two coincide the
    /// difference does not show. On one where they do not, the test lies.
    ///
    /// It lied on the merged tree. Screen 01 posts a location notice `MapOpening.patience` — three
    /// seconds — after launch when permission is granted and no fix has arrived
    /// (`MapHomeView.standingNotice`). That is after the baseline is taken and before the assertion
    /// runs, so the notice was attributed to the filter and the guard failed with
    /// `"Finding you"` in its message. The rule was right and the instrument was wrong: a
    /// location-denied simulator (which is what this was first proved on) never posts it, and a
    /// granted-but-fixless one posts it every run. **R41 explicitly permits it** — "E126's carve-out
    /// (location notices and search status) survives for *location* and *search* — those are not
    /// filters."
    ///
    /// So the narrowing is applied, read, and then **cleared**, and text is a violation only when it
    /// is present with the filter on and absent from *both* readings with it off. Anything that
    /// arrived on its own schedule is still there after `Clear filters` and cancels itself out,
    /// whenever it happened to appear. Nothing here knows what the location notice says, and
    /// nothing here knows how long the app waits before saying it — which is the point. Excluding
    /// the notice's sentences by name was the obvious alternative and is the one thing this must
    /// not do: CLAUDE.md says assert facts, not phrasing, and a guard that hard-codes the copy it
    /// tolerates rots the moment that copy changes.
    ///
    /// ── Why the whole screen, and not just the filter row's subtree ──────────────────────────
    /// Scoping the diff to the top chrome would also have fixed the false red, and was rejected:
    /// the E126-shaped card that task #165 struck lived in `MapHomeView.bottomSlot`, at the other
    /// end of the screen, and a guard that cannot see that end cannot see the most recently
    /// deleted filter message coming back. R41 exists because filter messages keep returning
    /// "under a different mechanism"; narrowing where the guard can look invites the next one.
    ///
    /// The permanent fix is a launch environment key that pins the location state, which is #121's
    /// remedy and what ERRATA E202 says the harness owes. That is a change to shared UI-test setup
    /// and belongs to that ticket, not to this one.
    private func assertNoCompanionText(
        _ app: XCUIApplication,
        narrowing description: String,
        turnOn: () -> Void
    ) {
        let quietBefore = texts(app)

        turnOn()
        XCTAssertTrue(
            wait { !self.clearControls(app).isEmpty },
            "no “\(Self.clear)” chip appeared after narrowing by \(description), so the filter "
                + "never took and nothing below is a statement about a narrowed map"
        )
        let narrowed = texts(app)
        let controls = controlLabels(app)

        // The same screen with the narrowing taken away. `Clear filters` clears every dimension,
        // drawn or hidden (R23.1 §3), so one tap returns the map to the un-narrowed state whichever
        // of the three cases above ran.
        revealedChip(Self.clear, app).tap()
        XCTAssertTrue(
            wait { self.clearControls(app).isEmpty },
            "“\(Self.clear)” did not clear the filter set by \(description), so the reading below "
                + "is not of an un-narrowed map"
        )
        let quietAfter = texts(app)

        // **The general form.** Text that is there with the filter on, gone with it off, and that
        // no control on screen answers to.
        let appeared = narrowed
            .subtracting(quietBefore)
            .subtracting(quietAfter)
            .subtracting(controls)
        XCTAssertEqual(
            appeared.sorted(), [],
            "narrowing by \(description) made text appear that is not on the un-narrowed map "
                + "either side of it, and that no control on screen answers to: \(appeared.sorted()). "
                + "RULINGS R41 is categorical — “does text appear because a filter did something?” — "
                + "and the only sanctioned channels are the chip's fill, a count on the chip, and "
                + "its spoken value (R23.1). If this is a new legitimate *chip*, it should be "
                + "reachable as a control and this test will pass once it is."
        )

        // The two specimens, redundant with the diff by construction and kept anyway: they name
        // the exact surfaces task #180 removed, so a regression reports in the words of the ticket
        // rather than as an anonymous set difference. They would also survive a refactor that
        // weakened the diff — which is not hypothetical, see `controlLabels`. Read off `narrowed`,
        // the state with the filter on.
        XCTAssertEqual(
            narrowed.filter { $0.range(of: Self.countGrammar, options: .regularExpression) != nil },
            [],
            "narrowing by \(description) put a result count over the map. RULINGS R41: a filter's "
                + "entire voice is its chip, and a count belongs on the chip or nowhere."
        )
        XCTAssertEqual(
            narrowed.filter { $0.localizedCaseInsensitiveContains(Self.caveatSubstring) },
            [],
            "narrowing by \(description) put a sentence about planting dates over the map. That is "
                + "the message task #180 removed by name; R41 forbids it returning in any wording."
        )
    }

    /// The device this test is running on, for remediation messages that name a real `simctl`
    /// target.
    ///
    /// A skip message used to hard-code one agent's simulator UDID, which made its advice wrong
    /// on every other device — including the CI runner, whose simulator is chosen from a candidate
    /// list and is not any of the four an agent uses. The runner sets `SIMULATOR_UDID` in the test
    /// process's environment; when it is absent the message says so rather than inventing one.
    private var runningDeviceUDID: String {
        ProcessInfo.processInfo.environment["SIMULATOR_UDID"] ?? "<this device's UDID>"
    }

    /// A skip nobody has to go looking for (#121).
    private func announceSkip(_ message: String, test: String) {
        let banner = String(repeating: "=", count: 78)
        print("\n\(banner)\nSKIPPED · MapFilterAccessibilityTests.\(test)")
        print("\(message)\n\(banner)\n")
        fflush(stdout)
    }

    // MARK: - 5 · One line, at AX5, on a phone

    /// **The row is one horizontally scrolling line at the top of the ramp, and every chip on it
    /// can still be reached and pressed** (task #166; #98's off-the-phone hazard, restated for a
    /// scroller).
    ///
    /// The wrap this test used to pin is the thing #166 deleted, so the assertions inverted: chips
    /// now share a single line however wide they grow, nothing hangs off the *vertical* edges, and
    /// a chip past the trailing edge is not a defect — it is the scroll — provided dragging the
    /// row brings it onto the glass and it works there.
    func testTheFilterRowIsOneLineAndScrollsAtAX5() {
        let app = launchAtAX5()
        _ = requireField(app)

        // The `Clear filters` chip only exists once something is on — so the row's fullest state
        // is only reachable by turning a filter on first, through the drawer.
        turnFavoritesOn(app)
        XCTAssertTrue(
            wait { !self.clearControls(app).isEmpty },
            "no “\(Self.clear)” chip at AX5, so the row's fullest state cannot be measured"
        )

        let screen = app.windows.firstMatch.frame
        XCTAssertLessThan(
            screen.width, 500,
            "this looks like an iPad (\(screen.width) pt); the one-line claim is about phones"
        )

        let labels = [Self.alwaysOnToggle] + Self.conditionChips + [Self.moreChip, Self.clear]
        var boxes: [(String, CGRect)] = []
        for label in labels {
            boxes.append((label, chip(label, app).frame))
        }

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

        // **One line** (#166). Five controls at AX5 are far wider than any phone, which is exactly
        // what makes this the assertion: a row that wraps reports a second minY here.
        let lines = Set(boxes.map { Int(($0.1.minY / 4).rounded()) })
        XCTAssertEqual(
            lines.count, 1,
            "at AX5 the row's chips sit on \(lines.count) lines: "
                + "\(boxes.map { "\($0.0) \($0.1)" }) — the owner asked for one row, and the width "
                + "past the edge belongs to the scroll"
        )

        // Nothing clipped on the row's own axis: every chip's top and bottom are on the phone.
        for (label, box) in boxes {
            XCTAssertGreaterThanOrEqual(
                box.minY, screen.minY - 0.5,
                "at AX5 the “\(label)” chip starts above the display (\(box))"
            )
            XCTAssertLessThanOrEqual(
                box.maxY, screen.maxY + 0.5,
                "at AX5 the “\(label)” chip runs off the bottom of the display (\(box)), so the "
                    + "one-line row is clipping its own contents"
            )
        }

        // **Every chip is reachable through the scroll, and works there.** The trailing chips are
        // off the glass at this size on every phone; `revealedChip` drags the row, which is the
        // interaction #166 traded the wrap for.
        for label in labels {
            let element = revealedChip(label, app)
            XCTAssertTrue(
                element.isHittable,
                "at AX5 the “\(label)” chip cannot be scrolled onto the glass and pressed. Its "
                    + "frame is \(element.frame) on a \(screen.width)×\(screen.height) screen"
            )
        }

        // The drawer still opens *below* the one-line row at the tallest size, holding its toggle
        // and its menu, both on the phone and both pressable.
        let hidden = openDrawer(app)
        let year = app.buttons[Self.yearChip]
        XCTAssertTrue(year.waitForExistence(timeout: 10), "the open drawer holds no year control")
        for (label, box) in [(Self.hiddenChip, hidden.frame), (Self.yearChip, year.frame)] {
            XCTAssertGreaterThanOrEqual(
                box.minX, screen.minX - 0.5,
                "at AX5 the “\(label)” chip in the open control starts off the phone (\(box))"
            )
            XCTAssertLessThanOrEqual(
                box.maxX, screen.maxX + 0.5,
                "at AX5 the “\(label)” chip in the open control runs off the phone (\(box))"
            )
        }
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

    /// **#165 at AX5: the matchless pill is live at the top of the ramp too**, where R31's box
    /// was at its widest and the temptation to bring it back will be strongest.
    func testTheMatchlessPillIsLiveAtAX5() {
        let app = launchAtAX5()
        _ = requireField(app)

        let needsCare = revealedChip(Self.matchlessChip, app)
        XCTAssertTrue(
            needsCare.isEnabled,
            "at AX5 “\(Self.matchlessChip)” renders disabled — R31's presentation, struck by #165"
        )
        XCTAssertTrue(
            needsCare.isHittable,
            "at AX5 “\(Self.matchlessChip)” cannot be scrolled onto the glass and pressed"
        )
        needsCare.tap()
        XCTAssertTrue(
            wait { (needsCare.value as? String) == Self.on },
            "at AX5 tapping “\(Self.matchlessChip)” did not turn it on — it announces "
                + "“\(needsCare.value as? String ?? "nothing")”"
        )
        _ = wait(timeout: 3) { false }
        for title in Self.struckNoticeTitles {
            XCTAssertFalse(
                app.staticTexts[title].exists,
                "at AX5 “\(title)” is on screen — the message box #165 deleted is back"
            )
        }
        XCTAssertTrue(
            wait { self.clearControls(app).count == 1 },
            "at AX5 a filter is on and \(clearControls(app).count) controls are labeled "
                + "“\(Self.clear)”; #165 leaves exactly one — the chip in the row"
        )
    }

    // MARK: - 6 · The two features, together

    /// **The suggestion list and the filter row, with a filter already on** (R25 §1's other half).
    ///
    /// The claim: the chips move rather than being covered, they stay reachable, and the row's own
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
        let before = (yours: yours.frame.minY, clear: chip(Self.clear, app).frame.minY)

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

        // Moved down, not covered — for the first chip and for the last one.
        XCTAssertTrue(
            wait { yours.frame.minY > before.yours },
            "the suggestion list did not push the “\(Self.alwaysOnToggle)” chip down "
                + "(\(before.yours) → \(yours.frame.minY)), so it is drawn over it"
        )
        XCTAssertTrue(
            wait { self.chip(Self.clear, app).frame.minY > before.clear },
            "the suggestion list did not push the “\(Self.clear)” chip down "
                + "(\(before.clear) → \(chip(Self.clear, app).frame.minY))"
        )
        XCTAssertTrue(
            yours.isHittable,
            "with the list open the “\(Self.alwaysOnToggle)” chip is in the tree and cannot be "
                + "activated"
        )
        XCTAssertTrue(
            revealedChip(Self.clear, app).isHittable,
            "with the list open the “\(Self.clear)” chip cannot be scrolled onto the glass and "
                + "activated"
        )

        // **The row's own order** — the owner's three, the control, the way out (#145). Since
        // #166 made the row one line, geometry *is* the reading order: five chips on one minY,
        // minX ascending in the owner's order. Asserted from frames rather than from a
        // container-scoped tree walk, because the labeled scroller's descendant enumeration is
        // XCUITest's business and has already returned nothing here once (the flattening the
        // MapChrome comment records).
        let rowLabels = [Self.alwaysOnToggle] + Self.conditionChips + [Self.moreChip, Self.clear]
        let frames = rowLabels.map { chip($0, app).frame }
        XCTAssertEqual(
            Set(frames.map { Int(($0.minY / 4).rounded()) }).count, 1,
            "with the suggestion list open the row is not one line: "
                + "\(zip(rowLabels, frames).map { "\($0) \($1)" })"
        )
        XCTAssertEqual(
            zip(rowLabels, frames).sorted { $0.1.minX < $1.1.minX }.map(\.0),
            rowLabels,
            "with the suggestion list open the filter row reads in this order: "
                + "\(zip(rowLabels, frames).sorted { $0.1.minX < $1.1.minX }.map(\.0))"
        )
        // **The row holds no reachable unlabeled control** (E103, structurally). The `Menu`'s
        // unlabeled leftover element moved into the drawer with the year chip (#145), so on the
        // row's own line there should be none at all — and any that appears must stay
        // unreachable. The line is identified by its band of the screen, for the same reason the
        // order is: frames are the one channel the scroller cannot hide.
        let band = chip(Self.alwaysOnToggle, app).frame
        let blanks = app.buttons.matching(NSPredicate(format: "label == ''"))
            .allElementsBoundByIndex
        for blank in blanks where blank.frame.intersects(band) {
            XCTAssertFalse(
                blank.isHittable,
                "an unlabeled control at \(blank.frame) is reachable inside the filter row"
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
    // with VoiceOver on**, and ERRATA E192's *The debt* records it. What this file
    // still asserts about the same surface: the chips move rather than being covered, they stay
    // hittable, and the row's own internal order is the owner's (the test above).

    /// The query typed into C20, and the prefix a row for it must begin with.
    ///
    /// Borrowed from `MapSuggestionUITests` and for its reasons: the *catalog* is bundled with the
    /// app and is the same on every machine, so this resolves to the same suggestions wherever the
    /// map is pointed. The scientific name is deliberately not written down.
    private static let query = "cypress"
    private static let rowPrefix = "Monterey Cypress, "
}
