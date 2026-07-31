import XCTest

/// **Screen 01's filter row, its result line and its empty notice, driven the way an assistive
/// technology reaches them** (task #135; the design is RULINGS **R23**, the dropdown beside it is
/// **R25**).
///
/// ── Why this file exists ─────────────────────────────────────────────────────────────────────────
/// #116 shipped the row — `Yours · Favourites · Year ▾ · Needs care · In bloom`, a `Clear filters`
/// chip, a result line and an empty-state notice — and its own report says plainly: "No UI tests
/// written — `CypressUITests` was not run at all." Everything about it was verified by driving the
/// simulator by hand. `CypressTests/MapFilterTests` proves the *values* are right; it cannot prove any
/// of them reach a finger or a VoiceOver reader, because SwiftUI builds no in-process accessibility
/// tree (ARCHITECTURE §7, E116).
///
/// This project has been bitten at exactly this seam three times, which is why the ticket exists:
/// `.clipped()` once clipped drawing but not touches while `isHittable` reported true; the recentre
/// control told VoiceOver the map was not centred on you while a screenshot showed it was (#100,
/// E168); and screen 04's framing chips fell off the phone at AX5 (#98). A wrapping chip row with a
/// menu in it, floating over a map, is the same shape as all three.
///
/// ── The rules this file inherits, and obeys ──────────────────────────────────────────────────────
/// **A test states its own preconditions or it does not have any** (`MapSearchUITests`, tasks #101
/// and #104). Almost everything below is a claim about the *filter*, which is a control rather than a
/// viewport, so it holds wherever `xcrun simctl location` last left the device. The two chips that
/// need the map to hold something — the count line — say so and are the only place a guard appears,
/// and that guard **announces itself in the output** rather than skipping quietly (#121).
///
/// **A species name is never hardcoded.** An agent hardcoded `Hesperocyparis macrocarpa` out of
/// SCREENS.md 02 the day before this was written; the seed spells it `Cupressus macrocarpa`, and
/// three tests went red saying "the dropdown drew no suggestions" when they meant "the mock
/// disagrees with the seed". The legend below is read off the glass, and the one query typed into
/// C20 is matched by prefix with something asserted behind it, exactly as `MapSuggestionUITests`
/// does.
///
/// **The seed is two cities** — `sf` 145,837 rows and `us-ca-sj` 52,788 — so nothing here counts
/// trees or assumes a row is in San Francisco.
///
/// ── What is deliberately *not* here ──────────────────────────────────────────────────────────────
/// The five assertions `MapSuggestionUITests` already makes about the dropdown. The one thing this
/// file adds on that side is the interaction R25's agent could not have written: the chips under an
/// open list, **with a filter on and the `Clear filters` chip present**, which did not exist yet.
final class MapFilterAccessibilityTests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: - The row, as words

    /// Every toggle in the row, in the order `MapFilterChips` draws them. `Year` is deliberately not
    /// here: it is a `Menu` carrying a value rather than a toggle carrying a state, and it is checked
    /// on its own terms.
    private static let toggles = ["Yours", "Favourites", "Needs care", "In bloom"]

    /// `MapYearFilterCopy.label`, and the value it carries when no decade is chosen.
    private static let yearChip = "Year"
    private static let anyYear = "Any year"

    /// `MapFilterCopy.chipValue(isOn:)`. The fill and the weight say "on" and neither reaches a
    /// listener, which is the whole of #100's defect said about a different control.
    private static let on = "On"
    private static let off = "Off"

    /// `MapFilterCopy.clearLabel`. It is the chip **and** the empty notice's button — R23's "two ways
    /// out, both labelled" — so every lookup of it below has to say which one it means.
    private static let clear = "Clear filters"

    /// `MapFilterCopy.rowLabel`, the container's own name.
    private static let rowLabel = "Filter trees"

    /// The condition chip this file uses whenever it wants an empty map on purpose.
    ///
    /// **Both condition chips match nothing in the shipped seed, and only one of them is documented
    /// as doing so.** R23 says `In bloom` "still matches nothing, because every `seasonal` in the
    /// shipped seed is `{}`". `Needs care` is `status == .declining` (`MapPinKind.needsCare`) and the
    /// seed carries two statuses — `alive` 174,425 and `vacant_site` 24,200 — so it matches nothing
    /// either. That is a fact about the data rather than a defect in the chip, and it is what makes
    /// the empty state below reachable without touching the simulator's location.
    private static let emptyingChip = "In bloom"

    // MARK: - Launching

    /// The default text size.
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        return app
    }

    /// AX5 — `accessibilityExtraExtraExtraLarge`, the top of the ramp — on a 390 pt phone.
    ///
    /// Set through the preferred-content-size default rather than by `xcrun simctl ui`, so the size
    /// belongs to this process and this launch. A `simctl` call would leave the whole device at AX5
    /// for whatever ran next, which on a shared machine is somebody else's red suite.
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

    /// Every control labelled `Clear filters`, top of the screen first.
    ///
    /// There are two of them the moment the filter has emptied the map — the chip in the row and the
    /// button on the notice — and they are the same sentence on purpose (R23 §1). A lookup by label
    /// alone would resolve to whichever XCUITest felt like, which is how a green test ends up
    /// asserting nothing about the control it names.
    private func clearControls(_ app: XCUIApplication) -> [XCUIElement] {
        app.buttons
            .matching(NSPredicate(format: "label == %@", Self.clear))
            .allElementsBoundByIndex
            .sorted { $0.frame.minY < $1.frame.minY }
    }

    // MARK: - 1 · Every chip is in the tree, labelled, touchable, and says its state

    /// The row at rest: five controls, each reachable, each announcing that it is off.
    ///
    /// **The value is the assertion, not the label.** A chip that is drawn, hittable and correctly
    /// labelled while announcing nothing about whether it is on is precisely #100 — a control that
    /// told VoiceOver the map was not on the user for a whole 39-second run, beside a screenshot
    /// showing it centred. The fill and the weight are the only other channel and neither reaches a
    /// listener.
    func testTheFilterRowIsReachableAndEveryChipSaysItIsOff() {
        let app = launch()
        _ = requireField(app)

        // The group has a name, so a reader arriving on it by element is told what these five
        // controls are for rather than meeting `Yours` with no context.
        XCTAssertTrue(
            app.otherElements[Self.rowLabel].waitForExistence(timeout: 25),
            "the filter row is not a named container in the accessibility tree, so its chips arrive "
                + "unannounced between the search field and the map"
        )

        for label in Self.toggles {
            let element = chip(label, app)
            XCTAssertTrue(
                element.isHittable,
                "the “\(label)” chip is in the accessibility tree but nothing can activate it"
            )
            XCTAssertEqual(
                element.value as? String, Self.off,
                "the “\(label)” chip announces “\(element.value as? String ?? "nothing")” at rest, "
                    + "so a listener cannot tell it from a chip that is on"
            )
            XCTAssertFalse(
                element.isSelected,
                "the “\(label)” chip carries the selected trait while nothing is filtered"
            )
        }

        // The year control is a `Menu`, so it carries a *value* rather than a state — and a menu
        // whose label swallowed its value would leave a listener with `Year` and no answer.
        let year = chip(Self.yearChip, app)
        XCTAssertTrue(year.isHittable, "the year control is in the tree but cannot be opened")
        XCTAssertEqual(
            year.value as? String, Self.anyYear,
            "the year control announces “\(year.value as? String ?? "nothing")” before a decade is "
                + "chosen, so a listener is not told the map is unnarrowed by year"
        )

        // And nothing is offering a way out of a filter nobody has set.
        XCTAssertTrue(
            clearControls(app).isEmpty,
            "“\(Self.clear)” is drawn over an unfiltered map, with nothing to clear"
        )
    }

    /// Turning a chip on changes what it announces, in both channels a listener has.
    ///
    /// Two claims, and the second is the one that would rot silently: the value flips to `On`, **and**
    /// the element gains the selected trait. `Chip` adds `.isSelected` off its own style, so the two
    /// come from different places in the code and a change that broke one would leave the other
    /// standing.
    ///
    /// It also pins `membership`'s single-select-within-itself (R23 §1): tapping `Favourites` while
    /// `Yours` is on swaps rather than ANDing, and a listener has to hear both halves of that swap.
    func testTurningAChipOnIsAnnouncedInBothChannels() {
        let app = launch()
        _ = requireField(app)

        let needsCare = chip("Needs care", app)
        needsCare.tap()
        XCTAssertTrue(
            wait { (needsCare.value as? String) == Self.on },
            "after tapping it the “Needs care” chip still announces "
                + "“\(needsCare.value as? String ?? "nothing")”"
        )
        XCTAssertTrue(
            needsCare.isSelected,
            "the “Needs care” chip is on and does not carry the selected trait"
        )

        // Off again: every chip in this row is a toggle, because a conjunction with no way to remove
        // one term is a conjunction you can only escape wholesale (R23 §1).
        needsCare.tap()
        XCTAssertTrue(
            wait { (needsCare.value as? String) == Self.off },
            "tapping an on chip did not turn it off — it announces "
                + "“\(needsCare.value as? String ?? "nothing")”"
        )

        // The membership pair swaps rather than combining, and both chips have to say so.
        let yours = chip("Yours", app)
        let favourites = chip("Favourites", app)
        yours.tap()
        XCTAssertTrue(
            wait { (yours.value as? String) == Self.on },
            "the “Yours” chip did not come on"
        )
        favourites.tap()
        XCTAssertTrue(
            wait {
                (favourites.value as? String) == Self.on && (yours.value as? String) == Self.off
            },
            "tapping “Favourites” left the row announcing Yours=\(yours.value as? String ?? "nil") "
                + "Favourites=\(favourites.value as? String ?? "nil"); the membership pair is "
                + "single-select within itself and both chips have to say which one won"
        )
    }

    // MARK: - 2 · The way out appears with the thing it undoes

    /// `Clear filters` appears only when something is on, is a real labelled control, and works.
    ///
    /// The chip's whole reason for existing is that a conjunction needs a wholesale escape (R23 §1).
    /// A chip that appeared and did not clear, or cleared and did not go away, would leave the row
    /// saying something the map does not.
    func testClearFiltersAppearsWithTheFilterAndTakesItAway() {
        let app = launch()
        _ = requireField(app)

        let inBloom = chip(Self.emptyingChip, app)
        XCTAssertTrue(clearControls(app).isEmpty, "“\(Self.clear)” is drawn before anything is on")

        inBloom.tap()
        XCTAssertTrue(
            wait { !self.clearControls(app).isEmpty },
            "turning a chip on drew no “\(Self.clear)” control, so the only way out of the "
                + "conjunction is to remember which chips were pressed"
        )

        // The chip, not the notice's button: the topmost of the two.
        let chipOut = clearControls(app)[0]
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
            inBloom.value as? String, Self.off,
            "clearing the filters left the “\(Self.emptyingChip)” chip announcing "
                + "“\(inBloom.value as? String ?? "nothing")”"
        )
    }

    /// The empty notice says why the map is empty **and** offers a reachable control that fixes it.
    ///
    /// ERRATA E126's second half is the one that gets skipped: a surface with nothing on it must say
    /// how to leave, and a hint is not a way out. The button was hard-coded to `Settings` until #116
    /// parameterised it, which is exactly the kind of change that leaves a button on screen doing the
    /// old thing.
    ///
    /// The precondition is stated rather than assumed: `In bloom` cannot match a tree in the shipped
    /// seed under any viewport, so this empties the map on every machine.
    func testTheEmptyNoticeOffersASecondWayOutAndItWorks() {
        let app = launch()
        _ = requireField(app)

        let inBloom = chip(Self.emptyingChip, app)
        inBloom.tap()

        let title = app.staticTexts["Nothing matches here"]
        XCTAssertTrue(
            title.waitForExistence(timeout: 25),
            "a filter that matches nothing emptied the map and drew no notice saying why"
        )

        // Two ways out, both labelled — the chip in the row and the button on the card (R23 §1).
        XCTAssertTrue(
            wait { self.clearControls(app).count == 2 },
            "an emptied map offers \(clearControls(app).count) controls labelled “\(Self.clear)”, "
                + "and R23 requires two: the chip in the row and the button on the notice"
        )
        let noticeButton = clearControls(app)[1]
        XCTAssertTrue(
            noticeButton.isHittable,
            "the notice's way out is in the accessibility tree and nothing can touch it — which is "
                + "the covered-but-reachable failure this screen has shipped before"
        )
        XCTAssertGreaterThan(
            noticeButton.frame.minY, title.frame.minY,
            "the notice's button is not on the notice"
        )

        noticeButton.tap()
        XCTAssertTrue(
            wait { !title.exists },
            "pressing the notice's way out left the notice on screen"
        )
        XCTAssertEqual(
            inBloom.value as? String, Self.off,
            "the notice's way out did not clear the filter: “\(Self.emptyingChip)” still announces "
                + "“\(inBloom.value as? String ?? "nothing")”"
        )
    }

    // MARK: - 3 · The line over the map

    /// Anything on screen that looks like the result line, as the tree exposes it.
    private func countLines(_ app: XCUIApplication) -> [XCUIElement] {
        app.staticTexts
            .matching(NSPredicate(format: "label MATCHES %@", Self.countGrammar))
            .allElementsBoundByIndex
    }

    /// `MapFilterCopy.result`'s two forms and nothing else: `31 trees`, `1 tree`, or
    /// `1458 trees—showing 151`. An em dash with no spaces around it (ARCHITECTURE §5.7).
    private static let countGrammar = "^[0-9]+ tree(s)?(—showing [0-9]+)?$"

    /// Any element that is only *part* of a count — a bare number, or the tail of the thinned form.
    /// One of these on screen is the line having been split into fragments a VoiceOver reader has to
    /// swipe between and reassemble.
    private static let fragmentGrammar = "^([0-9]+|trees?|showing [0-9]+|—showing [0-9]+)$"

    private func countFragments(_ app: XCUIApplication) -> [XCUIElement] {
        app.staticTexts
            .matching(NSPredicate(format: "label MATCHES %@", Self.fragmentGrammar))
            .allElementsBoundByIndex
    }

    /// **The count yields when the notice is already speaking, and the year caveat is one phrase.**
    ///
    /// Two conditionals in one launch, both of the kind that rots because nothing looks at them:
    ///
    /// 1. R23 §5 — found by running the app, not by reading it — a `0 trees` pill sat in the chrome
    ///    while `No trees of yours here` sat in the card below: the same fact twice, weaker phrasing
    ///    on top. `MapModel.filterResult` now returns nil over an empty map. Nothing else in the
    ///    suite asks whether it still does.
    /// 2. The year control's caveat has to arrive as **one** element. It is two clauses joined by an
    ///    em dash, which is exactly the sentence somebody later splits into two `Text`s to get the
    ///    line breaks they want, leaving a listener to hear "About 4 in 5 trees have no recorded
    ///    planting date" and then, separately, "none of them can appear under a year".
    ///
    /// Both halves hold under any viewport: `In bloom` matches nothing anywhere, and the caveat is
    /// rendered off the chip's state rather than off the map's contents.
    func testTheCountYieldsToTheNoticeAndTheYearCaveatIsOnePhrase() {
        let app = launch()
        _ = requireField(app)

        chip(Self.emptyingChip, app).tap()

        let title = app.staticTexts["Nothing matches here"]
        XCTAssertTrue(
            title.waitForExistence(timeout: 25),
            "a filter that matches nothing drew no notice saying why the map is empty"
        )
        // Settled: the notice and the count are published from the same model pass, so a read taken
        // the instant the notice appears can catch a count on its way out.
        _ = wait(timeout: 3) { false }
        XCTAssertEqual(
            countLines(app).map(\.label), [],
            "the map is empty and the notice is explaining why, and a count is sitting in the "
                + "chrome above it saying the same thing in weaker words (R23 §5)"
        )

        // Now the year control, whose caveat draws whatever the map holds.
        chip(Self.emptyingChip, app).tap()
        chip(Self.yearChip, app).tap()
        let decade = app.buttons["2010s"]
        XCTAssertTrue(
            decade.waitForExistence(timeout: 15),
            "the year control opened no menu, so a decade cannot be chosen at all"
        )
        decade.tap()

        XCTAssertTrue(
            wait { (self.chip(Self.yearChip, app).value as? String) == "2010s" },
            "choosing a decade left the year control announcing "
                + "“\(chip(Self.yearChip, app).value as? String ?? "nothing")”"
        )

        let caveat = app.staticTexts[
            "About 4 in 5 trees have no recorded planting date—none of them can appear under a year."
        ]
        XCTAssertTrue(
            caveat.waitForExistence(timeout: 25),
            "the year control is on and the sentence that says what it cannot judge is not one "
                + "element in the tree — a listener hears the clauses apart, or not at all"
        )
    }

    /// **The result line is one counting phrase, not a number and some words beside it.**
    ///
    /// `1458 trees—showing 151` is E38's sentence: a page is not a total. Split across two elements
    /// it becomes "1458 trees" and "showing 151", which a VoiceOver reader meets as two unrelated
    /// facts — and the second one, read alone, is the total the app has never counted.
    ///
    /// ── The one precondition in this file, stated and announced ──────────────────────────────────
    /// A count needs a filter that is on *and* a map with something left under it. Every chip in the
    /// row that can be pressed without knowing where the map is pointed empties it: `Yours` and
    /// `Favourites` are empty on a fresh install, and both conditions match nothing in the shipped
    /// seed. What is left is the species dimension, which R23 made **the legend** — and the legend
    /// names species the map has actually drawn, so tapping one narrows to something that is
    /// certainly in view.
    ///
    /// The legend draws nothing when the viewport has coloured no species, which is a real state
    /// (`MapSpeciesPalette.minimumPinsForASlot`) and depends on wherever `xcrun simctl location` last
    /// left the device. So this is guarded — and #121 is open on two tests in this target that skip
    /// on ambient state without saying so anywhere a reader of the summary would see it. This one
    /// **prints a banner** before it skips.
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
                + "location 3A1F212D-8F3A-41F1-AF72-EC95E155A4C9 set 37.78485,-122.4215 (and note "
                + "that `simctl location clear` does not unfix a device — revoke the app's location "
                + "grant to do that)."
            announceSkip(message)
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
                + "pins of — put \(countLines(app).count) result lines over the map. The line is "
                + "\(countLines(app).map(\.label))"
        )
        // And nothing beside it is a piece of the same sentence.
        XCTAssertEqual(
            countFragments(app).map(\.label), [],
            "the result line has been split: the tree also holds "
                + "\(countFragments(app).map(\.label)), which a reader meets as separate facts"
        )
        XCTAssertTrue(
            countLines(app)[0].isHittable || countLines(app)[0].frame.height > 0,
            "the result line has no frame, so it is in the tree and on nobody's screen"
        )
    }

    /// A skip nobody has to go looking for. #121 is open because two tests in this target skip on
    /// ambient simulator state and the summary line does not say so.
    private func announceSkip(_ message: String) {
        let banner = String(repeating: "=", count: 78)
        print("\n\(banner)\nSKIPPED · MapFilterAccessibilityTests.testTheResultLineIsOneCountingPhrase")
        print("\(message)\n\(banner)\n")
        fflush(stdout)
    }

    // MARK: - 4 · AX5 on a 390 pt phone

    /// **The row wraps rather than running off the edge of the phone, and every chip stays
    /// touchable there.**
    ///
    /// This is #98 restated: screen 04 collapsed at AX5 with its framing chips falling off the phone,
    /// and the add-tree caption still truncates at AX5 today (#132). `MapFilterChips` borrows
    /// `FlowRow` from the legend and `FlowRow` places each subview at the width it asked for when
    /// unconstrained — so a chip whose label is wider than the row it is in does not wrap, it hangs
    /// over the edge. Six chips at AX5 on a 390 pt phone is the case where that would show.
    ///
    /// Two assertions, and both are about the row rather than about any one chip: it uses more than
    /// one line (so it wrapped rather than truncating), and no chip's frame leaves the display.
    func testTheFilterRowWrapsAndStaysOnThePhoneAtAX5() {
        let app = launchAtAX5()
        _ = requireField(app)

        // The `Clear filters` chip is the sixth, and it only exists once something is on — so the
        // widest case of this row is only reachable by pressing one first.
        chip(Self.emptyingChip, app).tap()
        XCTAssertTrue(
            wait { !self.clearControls(app).isEmpty },
            "no “\(Self.clear)” chip at AX5, so the row's widest state cannot be measured"
        )

        let screen = app.windows.firstMatch.frame
        XCTAssertEqual(
            screen.width, 390,
            accuracy: 1,
            "this test is written for the 390 pt phone the ticket names; the host is "
                + "\(screen.width) pt wide"
        )

        var boxes: [(String, CGRect)] = []
        for label in Self.toggles + [Self.yearChip] {
            boxes.append((label, chip(label, app).frame))
        }
        boxes.append((Self.clear, clearControls(app)[0].frame))

        for (label, box) in boxes {
            XCTAssertGreaterThanOrEqual(
                box.minX, screen.minX - 0.5,
                "at AX5 the “\(label)” chip starts \(box.minX) pt from the left edge of a "
                    + "\(screen.width) pt screen — it is off the phone"
            )
            XCTAssertLessThanOrEqual(
                box.maxX, screen.maxX + 0.5,
                "at AX5 the “\(label)” chip runs to \(box.maxX) pt on a \(screen.width) pt screen, "
                    + "so the end of its label is off the edge. Its frame is \(box), and the row is "
                    + "\(boxes.map { "\($0.0) \($0.1)" })"
            )
        }

        // It wrapped. Six chips at AX5 cannot be one line on this phone, so a row reporting one line
        // is a row that stopped wrapping — the state where the later chips are drawn past the edge
        // or on top of each other.
        let lines = Set(boxes.map { Int(($0.1.minY / 4).rounded()) })
        XCTAssertGreaterThan(
            lines.count, 1,
            "at AX5 all six chips report the same line of the row: \(boxes.map { "\($0.0) \($0.1)" })"
        )

        // And every one of them can still be pressed there. A chip that has been pushed under the
        // keyboard, off the bottom, or behind the suggestion card is in the tree and answers nobody.
        for label in Self.toggles + [Self.yearChip] {
            XCTAssertTrue(
                chip(label, app).isHittable,
                "at AX5 the “\(label)” chip is in the accessibility tree and cannot be activated. "
                    + "Its frame is \(chip(label, app).frame) on a \(screen.width)×\(screen.height) "
                    + "screen"
            )
        }
        XCTAssertTrue(
            clearControls(app)[0].isHittable,
            "at AX5 the “\(Self.clear)” chip cannot be activated"
        )
    }

    // MARK: - 5 · The two features, together

    /// **The suggestion list and the filter row, with a filter already on.**
    ///
    /// R25 put the list in the flow between the bar and the chips rather than over them, precisely so
    /// the chips are not left reachable by an assistive technology while invisible to everyone else —
    /// `DeepLinkVoiceOverTests.testAModalIsolatesTheScreenBehindIt`'s failure arriving by a different
    /// door. `MapSuggestionUITests.testTheChipsUnderTheListAreNotCoveredButReachable` asserts that for
    /// the row as it was: five chips, nothing on.
    ///
    /// This is the case that did not exist when that was written. With a filter on the row carries a
    /// **sixth** chip, `Clear filters`, which appears at the end of the flow and is therefore the one
    /// pushed furthest down — and the row is one line taller, so the list has more to move. The claim
    /// is the same and it has to hold in the taller state: the chips move rather than being covered,
    /// they stay hittable, and they stay *after* the suggestion rows in the element tree, which is
    /// where a reader who has just typed goes looking for them.
    func testAnOpenSuggestionListLeavesTheWholeFilterRowOrderedAndHittable() {
        let app = launch()
        let field = requireField(app)

        chip(Self.emptyingChip, app).tap()
        XCTAssertTrue(
            wait { !self.clearControls(app).isEmpty },
            "turning a filter on drew no “\(Self.clear)” chip, so the state this test is about "
                + "does not exist"
        )

        let inBloom = chip(Self.emptyingChip, app)
        let before = (bloom: inBloom.frame.minY, clear: clearControls(app)[0].frame.minY)

        field.tap()
        field.typeText(Self.query)

        let row = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", Self.rowPrefix))
            .firstMatch
        XCTAssertTrue(
            row.waitForExistence(timeout: 25),
            "typing “\(Self.query)” drew no row beginning “\(Self.rowPrefix)”"
        )
        // The seed spells this species' scientific name its own way and this file does not write it
        // down — `MapSuggestionUITests` has the whole story. What matters here is that a row arrived.
        XCTAssertFalse(
            String(row.label.dropFirst(Self.rowPrefix.count))
                .trimmingCharacters(in: .whitespaces).isEmpty,
            "the suggestion row announces “\(row.label)” and nothing behind the comma"
        )

        // Moved down, not covered — for the ordinary chips and for the one that is new.
        XCTAssertTrue(
            wait { inBloom.frame.minY > before.bloom },
            "the suggestion list did not push the “\(Self.emptyingChip)” chip down "
                + "(\(before.bloom) → \(inBloom.frame.minY)), so it is drawn over it"
        )
        XCTAssertTrue(
            wait { self.clearControls(app)[0].frame.minY > before.clear },
            "the suggestion list did not push the “\(Self.clear)” chip down "
                + "(\(before.clear) → \(clearControls(app)[0].frame.minY))"
        )
        XCTAssertTrue(
            inBloom.isHittable,
            "with the list open the “\(Self.emptyingChip)” chip is in the tree and cannot be "
                + "activated"
        )
        XCTAssertTrue(
            clearControls(app)[0].isHittable,
            "with the list open the “\(Self.clear)” chip is in the tree and cannot be activated"
        )

        // …and they are still *after* the rows in the element tree. A list drawn as an overlay would
        // leave the chips where they were in the order, which is the half of R25's argument that
        // geometry cannot see.
        let order = app.buttons.allElementsBoundByIndex.map(\.label)
        guard let rowIndex = order.firstIndex(where: { $0.hasPrefix(Self.rowPrefix) }),
              let bloomIndex = order.firstIndex(of: Self.emptyingChip),
              let clearIndex = order.firstIndex(of: Self.clear)
        else {
            return XCTFail("the element tree holds \(order)")
        }
        XCTAssertLessThan(
            rowIndex, bloomIndex,
            "a swipe reaches the “\(Self.emptyingChip)” chip before the suggestions it is under: "
                + "\(order)"
        )
        XCTAssertLessThan(
            bloomIndex, clearIndex,
            "the “\(Self.clear)” chip comes before the chip it undoes in the swipe order: \(order)"
        )
    }

    /// The query typed into C20, and the prefix a row for it must begin with.
    ///
    /// Borrowed from `MapSuggestionUITests` and for its reasons: the *catalogue* is bundled with the
    /// app and is the same on every machine, so this resolves to the same suggestions wherever the
    /// map is pointed. The scientific name is deliberately not written down.
    private static let query = "cypress"
    private static let rowPrefix = "Monterey Cypress, "
}
