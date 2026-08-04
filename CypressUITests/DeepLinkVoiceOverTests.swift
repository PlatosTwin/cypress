import XCTest

/// The accessibility tree of every screen behind the map (ERRATA E117).
///
/// `AccessibilityTreeTests` (E116) reads the tree of screen 01 and its chrome. That is one screen out
/// of nineteen, and it is the only one reachable from a cold launch without tapping a MapKit
/// annotation — which is not a thing a test can do reliably, because the basemap renders
/// asynchronously and puts its pins wherever the camera settles. So the other sixteen had never been
/// read by anything, and "the app is accessible" rested on a suite that had only ever seen the map.
///
/// `DebugDeepLink` is the door: the test names a screen in the launch environment and the app opens
/// it, resolving a real record out of the real 195,309-row seed. What is asserted here is what E116
/// asserts, on screens E116 cannot reach.
///
/// **Still black-box.** Nothing here imports `Cypress`. The screen names are strings and the anchors
/// are the words the app says out loud, which is the whole point: if a label changes, a test that
/// pins the old one should fail, because a VoiceOver user's map of the app just changed too.
///
/// **What each test proves, in order:**
/// 1. The screen *arrived* — the deep link is not a no-op that quietly leaves the app on screen 01
///    while fourteen tests report the names of screens they never visited.
/// 2. Nothing interactive on it is unlabeled — the E103 failure mode.
/// 3. It can be left again — a pushed screen with no reachable Back is a trap.
final class DeepLinkVoiceOverTests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: - Screens

    func testTreeProfile()   { check("treeProfile",   anchor: "Tree",            pushed: true) }
    func testVacantSite()    { check("site",          anchor: "No tree at this site", pushed: true) }
    func testSpecies()       { check("species",       anchor: "Field guide",     pushed: true) }
    func testCheckIn()       { check("checkIn",       anchor: "Check-in",        pushed: true) }
    func testReport()        { check("report",        anchor: "Report an issue", pushed: true) }
    func testGrowthHistory() { check("growthHistory", anchor: "Growth",          pushed: true) }
    func testActivity()      { check("activity",      anchor: "Activity",        pushed: true) }
    func testMeasure()       { check("measure",       anchor: "Measure",         pushed: true) }
    func testOutbox()        { check("outbox",        anchor: "Outbox",          pushed: true) }

    /// 09 and 10 are `fullScreenCover`s rather than pushes, so they have no Back button — they have a
    /// close, and the screen they cover stays in the hierarchy underneath. That difference is what
    /// `testAModalIsolatesTheScreenBehindIt` is about.
    func testCareLog()       { check("careLog",       anchor: "Care log",        pushed: false) }
    func testShare()         { check("share",         anchor: "Share this tree", pushed: false) }

    /// The three tab roots other than the map. No Back, because a tab root has nowhere to go back to.
    func testGroveTab()      { check("grove",         anchor: "Quiet collecting", pushed: false) }
    func testJournalTab()    { check("journal",       anchor: "Almanac",          pushed: false) }
    func testYouTab()        { check("you",           anchor: "Your contributions", pushed: false) }

    /// Screen 19, reachable at last (ERRATA E124-B): the harness marks a real seed tree removed and
    /// opens its memorial, so the one screen E117 could not reach — there was no removed tree to open
    /// it with — finally has its accessibility tree read like every other. Pushed, so it owes a Back.
    func testMemorial()      { check("memorial",      anchor: "Removed by the city", pushed: true) }

    /// The local moderation surface (ERRATA E124-B): the You tab in a lead's state, with one open
    /// removal review in front of it. A tab root, so no Back. The anchor is the review's own caption —
    /// a plain static text, unlike the `Confirm removed` button whose label the tree exposes on the
    /// button rather than as free text.
    func testModerationReview() { check("moderationReview", anchor: "Reported removed", pushed: false) }

    /// Screen 20, the photo browser (ERRATA E125). The harness photographs a real seed tree first —
    /// the shipped inventory has no photographs, because every photograph in this app is one somebody
    /// took — so this reads a list of real records. The anchor is the explainer line rather than the
    /// `Hero` badge, which sits inside the image's own element.
    func testPhotos() {
        check("photos", anchor: "The photo with the most thumbs up leads this tree's page.", pushed: true)
    }

    /// Screen 03 with photographs on it, which is a different tree from the cold one `treeProfile`
    /// opens: the hero draws a photograph and becomes the control that opens screen 20.
    func testPhotoHero()     { check("photoHero",     anchor: "Best photo",      pushed: true) }

    // MARK: - The hardest screen in the app for VoiceOver

    /// The community add's pin step: a map with a movable pin.
    ///
    /// **A pan is a gesture the screen reader owns.** There is no labeling that turns "drag the world
    /// 30 m north-east" into something a swipe-and-double-tap can perform, so a draggable pin with
    /// nothing beside it is a control that simply does not exist for a VoiceOver user. The answer is
    /// four nudge buttons and a pin that says where it is, and this is the test that the answer is
    /// actually in the tree rather than in a comment.
    ///
    /// Presented over the tab root rather than pushed — it is a phase of `VisitAddTreeModel`, not a
    /// `Route` — so it owes no Back *button* by the pushed-screen rule, and has one anyway, because a
    /// screen with no navigation bar and no gesture out is a trap.
    func testPinAdjust() {
        let app = launch("pinAdjust")
        guard arrive(app, screen: "pinAdjust", anchor: "Move the pin") else { return }

        assertEveryControlIsLabeled(app, screen: "pinAdjust")

        for direction in ["north", "east", "south", "west"] {
            let nudge = app.buttons["Move the pin \(direction)"]
            assertReachable(nudge, "pinAdjust: the '\(direction)' nudge control")
        }

        assertReachable(
            app.buttons["Back to where you are standing"],
            "pinAdjust: the one-press way back to the fix"
        )

        let back = app.buttons["Back"]
        assertReachable(
            back,
            "pinAdjust: the way to leave the pin screen without confirming a placement"
        )

        app.terminate()
    }

    /// The nudge controls have to *move the pin*, and the pin has to *say so*.
    ///
    /// Asserted on the pin's own accessibility value rather than on the existence of the buttons,
    /// which is this suite's standing lesson (E118, E125): a labeled, hittable control that does
    /// nothing passes every test written about its presence. Three presses of a 5 m step is 15 m, and
    /// the pin has to announce exactly that — a value that stayed at "Right where you are standing"
    /// means the taps reached a button that moves nothing, and a value reading anything other than
    /// 15 m north means the step or the bearing is wrong.
    func testTheNudgeControlsActuallyMoveThePin() {
        let app = launch("pinAdjust")
        guard arrive(app, screen: "pinAdjust", anchor: "Move the pin") else { return }

        let pin = Self.pinElement(app)
        XCTAssertTrue(pin.waitForExistence(timeout: 10), "pinAdjust: the pin is not in the accessibility tree at all")
        XCTAssertEqual(
            pin.value as? String, "Right where you are standing.",
            "pinAdjust: the pin does not start on the fix, so this test's arithmetic means nothing"
        )

        let north = app.buttons["Move the pin north"]
        for _ in 0..<3 { north.tap() }

        XCTAssertEqual(
            pin.value as? String, "15 m north of where you are standing.",
            "pinAdjust: after three 5 m nudges north the pin reads "
                + "'\(pin.value as? String ?? "nothing")' — the control does not move the pin, or it "
                + "does not say where it went"
        )

        // And the way back is one press, not fifteen.
        app.buttons["Back to where you are standing"].tap()
        XCTAssertEqual(pin.value as? String, "Right where you are standing.")

        app.terminate()
    }

    /// **The bound has to be visible when it is reached.**
    ///
    /// A pin that silently stops moving is a bug report; a screen that says why it stopped is a rule.
    /// Fifteen 5 m nudges is exactly the 75 m limit and all fifteen must be accepted — an off-by-one
    /// here would be a limit that refuses a spot the screen is calling 75 m — and the sixteenth must
    /// be refused *out loud*, in the persistent line under the pin's position rather than only in a
    /// spoken announcement that a sighted reader never hears.
    func testThePinSaysWhenItHasGoneAsFarAsItGoes() {
        let app = launch("pinAdjust")
        guard arrive(app, screen: "pinAdjust", anchor: "Move the pin") else { return }

        let pin = Self.pinElement(app)
        XCTAssertTrue(pin.waitForExistence(timeout: 10), "pinAdjust: the pin is not in the accessibility tree at all")

        let north = app.buttons["Move the pin north"]
        for _ in 0..<15 { north.tap() }

        XCTAssertEqual(
            pin.value as? String, "75 m north of where you are standing.",
            "pinAdjust: fifteen 5 m nudges left the pin at '\(pin.value as? String ?? "nothing")' "
                + "rather than at the 75 m limit, so a nudge inside the circle is being refused"
        )
        XCTAssertTrue(
            app.buttons["Use this spot"].isEnabled,
            "pinAdjust: a pin exactly at the limit cannot be confirmed, so the limit is off by one"
        )

        let stopped = app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH %@", "That is as far as the pin goes"))
            .firstMatch
        XCTAssertFalse(stopped.exists, "pinAdjust: the screen says the pin has stopped before it has")

        north.tap()

        XCTAssertTrue(
            stopped.waitForExistence(timeout: 5),
            "pinAdjust: the sixteenth nudge did nothing and the screen said nothing about it — the "
                + "pin stops silently, which is exactly the bug report this bound would generate"
        )
        XCTAssertEqual(
            pin.value as? String, "75 m north of where you are standing.",
            "pinAdjust: the refused nudge moved the pin anyway"
        )

        app.terminate()
    }

    /// The pin, found by the words it says rather than by its type — the reticle is a drawn shape and
    /// XCUITest's opinion of what kind of element that is has changed between OS releases.
    private static func pinElement(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "This tree's pin"))
            .firstMatch
    }

    // MARK: - A control that is in the tree, labeled, hittable — and dead

    /// Tapping a thumb on screen 20 has to *do* something (ERRATA E125).
    ///
    /// **Why this is a UI test and not a model test.** `TreePhotosModel.vote` was never wrong, and
    /// `PhotoHeroTests.worksThroughTheProtocol` already drives `setPhotoVote` through the existential
    /// and passes. The defect was two layers above either of them: `PhotoFill` draws a `scaledToFill`
    /// photograph inside a `.clipped()` box, and `.clipped()` clips pixels but not touches, so each
    /// card's photograph kept an invisible 132 pt overhang that lay on top of the *previous* card's
    /// thumb row and swallowed the tap. Every thumb in the list was dead except the two on the last
    /// card, which has nothing drawn after it. No error, no log, no vote.
    ///
    /// That failure is invisible to everything except a real tap on a real layout. The screen renders
    /// correctly, every element is present with the right frame, every label is right, and
    /// `isHittable` is `true` — the accessibility hit test resolves to the button even while the touch
    /// hit test resolves to the photograph on top of it. So the assertion here is deliberately made on
    /// *consequences*: the glyph's own state, and the `Hero` badge physically moving to the card that
    /// was voted up. Anchoring on anything that merely exists would pass on the broken build, which is
    /// the whole lesson of E118 and of the defect this closes.
    ///
    /// **The top card is the subject, and it is chosen on purpose.** It is the one the bug covered
    /// first and the one a casual check would tap; the *last* card is the only one the bug spared, so a
    /// test that happened to pick it would have passed throughout. It is also the card `PhotoHero`
    /// picks when nothing has been voted — most recent, then most pixels — which is what makes the
    /// second assertion deterministic.
    ///
    /// **Thumbs *down*, and the test puts the vote back.** `debugSeedPhotos` is cumulative and the
    /// `photo_votes` rows outlive the launch, so a test that leaves a vote behind passes once and then
    /// fails against its own leftovers the next time the suite is run on the same device. A down-vote
    /// is the one move whose effect on the hero cannot be ambiguous — `PhotoHero.choose` drops anything
    /// scoring below zero outright, so the badge *must* leave this card — and tapping it a second time
    /// takes it back, leaving the device exactly as this test found it.
    func testAThumbActuallyVotes() {
        let app = launch("photos")
        guard arrive(app, screen: "photos", anchor: "The photo with the most thumbs up leads") else { return }

        let topPhoto = app.images
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Photo · "))
            .firstMatch
        let thumbDown = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Thumbs down, "))
            .firstMatch
        XCTAssertTrue(thumbDown.waitForExistence(timeout: 10), "photos: the top card has no thumbs-down")
        XCTAssertEqual(
            thumbDown.value as? String, "off",
            "photos: the top card is already down-voted before this test votes on it — a previous run "
                + "did not put its vote back"
        )

        let hero = app.staticTexts["Hero"]
        XCTAssertTrue(hero.exists, "photos: no Hero badge, so there is nothing to watch move")
        XCTAssertTrue(
            topPhoto.frame.contains(hero.frame),
            "photos: the Hero badge starts on some card other than the top one, so the move this test "
                + "watches for would not mean what it is read to mean"
        )

        thumbDown.tap()
        assertThumb(thumbDown, reads: "on", after: "being tapped")

        // The consequence a user actually sees. Containment in the card's own photograph, not mere
        // inequality of frames: the badge has to have left *this* card, not merely been redrawn.
        XCTAssertFalse(
            topPhoto.frame.contains(hero.frame),
            "photos: the Hero badge is still inside the top photograph at \(topPhoto.frame) after that "
                + "photograph was voted down, so the vote changed nothing"
        )

        // Put it back, and prove the toggle works in the other direction while doing so.
        thumbDown.tap()
        assertThumb(thumbDown, reads: "off", after: "being tapped a second time")
        XCTAssertTrue(
            topPhoto.frame.contains(hero.frame),
            "photos: taking the down-vote back did not return the Hero badge to the top photograph"
        )

        app.terminate()
    }

    /// A thumb's own state, waited for rather than read immediately: the vote is written and the whole
    /// list re-read before the glyph can change.
    ///
    /// `XCTWaiter` rather than `waitForExpectations`, so the failure reported is the sentence below
    /// rather than the framework's "unfulfilled expectations", which says nothing about what a thumb is.
    private func assertThumb(
        _ thumb: XCUIElement,
        reads expected: String,
        after action: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let settled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", expected),
            object: thumb
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [settled], timeout: 10), .completed,
            "photos: '\(thumb.label)' reads '\(thumb.value as? String ?? "nothing")' rather than "
                + "'\(expected)' after \(action), so the tap never reached the button — no vote was "
                + "written and no error was shown",
            file: file, line: line
        )
    }

    // MARK: - A save that acknowledged nothing and went nowhere

    /// Saving a measurement on screen 16 has to have a visible consequence (ERRATA **E131**).
    ///
    /// **Why this is a UI test and not a model test.** `MeasureModel.save()` was never wrong, and
    /// `MeasurementAccuracyTests` already drives it and passes. The defect was one line above both:
    /// `RootView`'s `.measure` call site omitted `onSaved`, so `MeasureView`'s `{ _ in }` default
    /// applied. The screen has a failure line and no success line, and the model clears the entry on
    /// its way out — so the only visible consequence of a reading that reached the disk was the
    /// keypad clearing, which is also what the screen looks like for the moment before a *failed*
    /// save draws its amber line. Compare screen 05, which was wired with `onSaved: { _ in
    /// router.pop() }` from the start; 16 was the odd one out.
    ///
    /// Anything asserted inside the model would have passed on the broken build. What could not is
    /// that the screen is *gone* afterwards, which is the assertion made here.
    ///
    /// **Nothing is put back, and nothing needs to be.** Unlike `testAThumbActuallyVotes`, this
    /// writes an ordinary measurement onto a real seed tree — an append-only contribution that no
    /// other test reads and that the app is designed to accumulate. The reading is 3, entered on the
    /// keypad, which is inside every sanity range for both DBH and height so no anomaly line changes
    /// the layout under the CTA.
    func testSavingAMeasurementLeavesTheScreen() {
        let app = launch("measure")
        guard arrive(app, screen: "measure", anchor: "Measure") else { return }

        let three = app.buttons["3"]
        XCTAssertTrue(three.waitForExistence(timeout: 10), "measure: the keypad has no '3'")
        three.tap()

        let save = app.buttons["Save measurement"]
        XCTAssertTrue(save.waitForExistence(timeout: 10), "measure: no save CTA")
        XCTAssertTrue(
            save.isEnabled,
            "measure: the CTA is still disabled after a digit was entered, so this test never "
                + "exercised a save at all"
        )
        save.tap()

        // The consequence. `Measure` is screen 16's C1 title; if it is still on screen ten seconds
        // after a successful save, the save went nowhere — which is exactly what shipped.
        let gone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: app.staticTexts["Measure"]
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [gone], timeout: 15), .completed,
            "measure: screen 16 is still on screen after saving a reading, so the only thing the "
                + "save changed was the keypad clearing — which is also what a failure looks like"
        )

        app.terminate()
    }

    // MARK: - What a modal owes the screen it covers

    /// A VoiceOver user must not be able to swipe onto the screen behind a modal.
    ///
    /// This is the failure that is invisible to everyone who can see: sighted users cannot reach the
    /// map behind the care-log sheet because the sheet is drawn over it, and that feels like
    /// containment. It is only containment if the accessibility runtime agrees — otherwise the swipe
    /// order runs straight off the sheet and onto a map the user cannot see, and the "Search" they
    /// then activate belongs to a screen that is not on screen.
    ///
    /// Both of these covers are presented over screen 01, whose chrome is the thing that must go
    /// quiet. Asserted through `isHittable` rather than `exists`, because the presenting screen stays
    /// in the hierarchy by design (`RootView`'s one `fullScreenCover`) — being *there* is fine, being
    /// *reachable* is not.
    func testAModalIsolatesTheScreenBehindIt() {
        for screen in ["careLog", "share"] {
            let app = launch(screen)
            guard arrive(app, screen: screen, anchor: screen == "careLog" ? "Care log" : "Share this tree") else {
                continue
            }
            for behind in ["Map", "My Grove", "Journal", "You"] {
                let tab = app.buttons[behind]
                if tab.exists {
                    XCTAssertFalse(
                        tab.isHittable,
                        "\(screen): the \(behind) tab behind the cover can still be activated, so an "
                            + "assistive technology can walk off the sheet onto a screen that is not visible"
                    )
                }
            }
            app.terminate()
        }
    }

    // MARK: - Order

    /// Every pushed screen says where it is before it says anything else.
    ///
    /// A VoiceOver user meets a screen from the top of its element tree. If the first control is not
    /// the way out, or the first words are content rather than the screen's name, they are told what
    /// is here before they are told where here is — and nine screens deep that is the difference
    /// between navigating and guessing.
    ///
    /// **The order comes from `debugDescription`, and that choice is the whole lesson of E118.** The
    /// obvious API, `allElementsBoundByIndex`, returns the query engine's match order: on screen 05 it
    /// puts the pinned `Save check-in` at y=710 ahead of the `Back` at y=69, and a test built on it
    /// reported a defect that does not exist. `debugDescription` is a depth-first rendering of the
    /// actual element tree — the same artifact E117's screen dumps were read from — and one call gets
    /// all of it, which matters because recursing `children(matching:)` is one IPC round trip per node.
    ///
    /// The cost is that this parses a debugging format that Apple does not version. That failure is at
    /// least loud rather than silent: a format change yields no parsed elements and the count assertion
    /// fails, rather than the test quietly passing on an empty list.
    func testEveryPushedScreenSaysWhereItIsFirst() {
        continueAfterFailure = true
        defer { continueAfterFailure = false }

        let screens: [(screen: String, anchor: String, title: String)] = [
            ("treeProfile", "Tree", "Tree"),
            ("site", "No tree at this site", "Site"),
            ("species", "Field guide", "Field guide"),
            ("checkIn", "Check-in", "Check-in"),
            ("report", "Report an issue", "Report an issue"),
            ("growthHistory", "Growth", "Growth"),
            ("activity", "Activity", "Activity"),
            ("measure", "Measure", "Measure"),
            ("outbox", "Outbox", "Outbox"),
        ]

        for case let (screen, anchor, title) in screens {
            let app = launch(screen)
            guard arrive(app, screen: screen, anchor: anchor) else { continue }

            let ordered = Self.treeOrder(app.debugDescription)
            XCTAssertGreaterThan(
                ordered.count, 3,
                "\(screen): the element tree could not be parsed — `debugDescription`'s format has "
                    + "probably changed, and this test is no longer reading an order at all"
            )

            XCTAssertEqual(
                ordered.first(where: { $0.kind == "Button" })?.label, "Back",
                "\(screen): the first control in the element tree is "
                    + "'\(ordered.first(where: { $0.kind == "Button" })?.label ?? "nothing")' rather "
                    + "than Back, so the way out is not the first thing offered"
            )
            XCTAssertEqual(
                ordered.first(where: { $0.kind == "StaticText" })?.label, title,
                "\(screen): the first words read are "
                    + "'\(ordered.first(where: { $0.kind == "StaticText" })?.label ?? "nothing")' "
                    + "rather than the screen's own name"
            )

            app.terminate()
        }
    }

    /// Depth-first `(kind, label)` pairs, in the order the element tree declares them.
    ///
    /// Lines look like `    Button, 0x105d18ac0, {{18.0, 69.0}, {44.0, 44.0}}, label: 'Back'`. Only
    /// the subtree is wanted: `debugDescription` repeats a "Path to element" and "Query chain" section
    /// afterwards, and parsing those would count some elements twice.
    static func treeOrder(_ description: String) -> [(kind: String, label: String)] {
        var result: [(kind: String, label: String)] = []
        for line in description.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("Path to element") || line.hasPrefix("Query chain") { break }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let comma = trimmed.firstIndex(of: ","),
                  let labelRange = trimmed.range(of: "label: '"),
                  let close = trimmed.lastIndex(of: "'"),
                  labelRange.upperBound < close
            else { continue }
            result.append((String(trimmed[trimmed.startIndex..<comma]),
                           String(trimmed[labelRange.upperBound..<close])))
        }
        return result
    }

    /// The parser, pinned against a tree whose order is deliberately wrong.
    ///
    /// `testEveryPushedScreenSaysWhereItIsFirst` passes on every screen, which on its own is exactly
    /// as reassuring as the test E118 deleted — that one passed too, on a premise that was false. This
    /// is the control: a synthetic `debugDescription` in which the save button precedes Back and a
    /// caption precedes the title, asserting that the parser reports the inversion rather than
    /// smoothing it over. It needs no simulator, so the order logic stays verified even when nobody is
    /// spending three minutes launching screens.
    ///
    /// It also pins the format itself. The awkward cases are real ones lifted from live output: a
    /// trailing `, Selected` trait after the closing quote, a `, value: 0%` suffix, an apostrophe
    /// inside a species cultivar name, and the `Path to element` footer that must not be parsed.
    func testTreeOrderParserReportsAnInvertedTree() {
        let inverted = """
        Attributes: Application, 0x105e24fe0, pid: 21188, label: 'Cypress'
        Element subtree:
         →Application, 0x105e24fe0, pid: 21188, label: 'Cypress'
            Other, 0x105d18760, {{0.0, 0.0}, {393.0, 852.0}}
              Button, 0x105a2f840, {{18.0, 710.0}, {357.0, 49.3}}, label: 'Save check-in'
              StaticText, 0x105d22ea0, {{291.7, 83.7}, {71.3, 14.7}}, label: 'under a minute'
              Button, 0x105d22b40, {{18.0, 69.0}, {44.0, 44.0}}, label: 'Back'
              StaticText, 0x105d22d80, {{74.0, 75.8}, {88.7, 30.3}}, label: 'Check-in'
              Button, 0x105d230e0, {{18.0, 142.3}, {89.3, 44.0}}, label: 'Alive', Selected
              StaticText, 0x102f2a060, {{51.0, 268.0}, {133.0, 17.0}}, label: 'Indian Laurel Fig Tree 'Green Gem''
              Other, 0x105929dd0, {{360.0, 49.0}, {30.0, 753.7}}, label: 'Vertical scroll bar, 2 pages', value: 0%
        Path to element:
         →Application, 0x105e24fe0, pid: 21188, label: 'Never parsed'
        """

        let ordered = Self.treeOrder(inverted)

        // The inversion is seen, not smoothed over.
        XCTAssertEqual(ordered.first(where: { $0.kind == "Button" })?.label, "Save check-in")
        XCTAssertEqual(ordered.first(where: { $0.kind == "StaticText" })?.label, "under a minute")

        // Traits and values after the label do not swallow it; the footer is not parsed.
        XCTAssertTrue(ordered.contains { $0.label == "Alive" })
        XCTAssertTrue(ordered.contains { $0.label == "Vertical scroll bar, 2 pages" })
        XCTAssertTrue(ordered.contains { $0.label == "Indian Laurel Fig Tree 'Green Gem'" })
        XCTAssertFalse(
            ordered.contains { $0.label == "Never parsed" },
            "the `Path to element` footer was parsed, so elements are being counted twice"
        )
    }

    // MARK: - Grouping

    /// A stat is one thing, so it is one stop.
    ///
    /// The last of the three structural questions. E116 and E117 asked whether elements are *labeled*;
    /// E118's duplication check asked whether anything is said *twice*; this asks whether things that
    /// belong together arrive together. A caption and the number it describes, split into two stops,
    /// hands a VoiceOver user "DBH", a swipe, and then "30–35 cm" — a value severed from the word that
    /// says what it measures, and no way to tell from inside either fragment that they are one fact.
    ///
    /// Screen 03's grid is where this showed: its one *interactive* card already read as a single
    /// element, because a `Button` forms one out of its content, while the four beside it drawn
    /// identically read as two and three. `StatCard` combines its children now.
    ///
    /// **Asserted positively, and the reason is E118's lesson a second time.** The obvious form —
    /// "the bare caption `DBH` must no longer be its own element" — cannot work, and the evidence was
    /// already on disk before it was written: E117's dump shows `Button 'Height, Add a reading'`
    /// listing `StaticText 'Height'` and `StaticText 'Add a reading'` as children, and a `Button`
    /// unquestionably forms a single accessibility element. **XCUITest enumerates the children of
    /// combined elements too**, so absence-of-fragment can never hold, even for content that is
    /// correctly grouped. Written that way the test fails on correct code, which is how it was caught.
    ///
    /// What *is* observable is the joint label: an element reading `DBH, 30–35 cm, …` exists only if
    /// the caption and its value were actually merged. So the assertion is that the whole is present,
    /// not that the parts are gone.
    func testAStatCardIsOneStop() {
        let app = launch("treeProfile")
        guard arrive(app, screen: "treeProfile", anchor: "Tree") else { return }

        // **Both element types, because a stat card legitimately becomes either one (ERRATA E133).**
        // A card whose value is a reading has somewhere to go — screen 11 — so it is wrapped in a
        // `Button`; a card holding the city's bucket has nowhere to go and stays a combined
        // `StaticText`. Both are one stop, which is the whole property under test. Looking only in
        // `staticTexts` asserted something narrower than this test's own name: that the card is not
        // interactive. That premise was false, and it took a saved measurement on the opened tree to
        // expose it — after which the suite failed on every run until the app was uninstalled.
        // **`Watch for` is not on this list any more, and the reason is a promise the app never
        // made** (task #173). `TreeProfilePresentation.watchForText` returns the species care note
        // covering the current month, and its own comment says 20 of the curated 40 carry any and "a
        // species with none simply has no card". `DebugDeepLink` picks this screen's tree by
        // *distance*, not by species — so requiring the card asserted a property of whichever record
        // happened to be nearest, on whichever month the suite ran.
        //
        // It held for as long as it did because the harness was frozen. `standingTree` filtered
        // `treesNear`, which returns the seed's status and not this device's overrides, so after
        // `.memorial` ran once it kept returning the same record forever — a Southern Magnolia, whose
        // species does carry an August note. With that repaired (see
        // `ERRATA E217`) resolution moves on to the
        // next standing tree, a Blackwood Acacia, whose `care_notes` in the seed are `[]`. Measured
        // against the shipped seed rather than guessed: the four nearest records to the harness's
        // center are Magnolias carrying 115 bytes of care notes, and the fifth is the Acacia with 2.
        //
        // The three below are what a city-import record always has, and they still cover both shapes
        // this property is about — a card wrapped in a `Button` and cards that stay `StaticText`.
        for caption in ["DBH", "Site", "City record"] {
            let joint = NSPredicate(format: "label BEGINSWITH %@", "\(caption), ")
            let asText = app.staticTexts.matching(joint).firstMatch
            let asButton = app.buttons.matching(joint).firstMatch
            XCTAssertTrue(
                asText.exists || asButton.exists,
                "treeProfile: nothing reads '\(caption)' together with its value, so the caption and "
                    + "the thing it describes are announced as separate fragments"
            )
        }

        app.terminate()
    }

    // MARK: - Duplication

    /// Nothing may be announced twice.
    ///
    /// The E104 failure mode as a rule rather than a component: a container that carries a label *and*
    /// exposes a child carrying the same one is two stops on the same words, and a screen full of them
    /// is a screen that takes twice as long to hear. Checked as containment rather than adjacency,
    /// because that is the shape the defect actually takes — a labeled wrapper around a labeled leaf.
    ///
    /// **`allElementsBoundByIndex` is used here as a set, never as an order, and that restriction is
    /// load-bearing (ERRATA E118).** Its sequence is the query engine's match order, which is neither
    /// the accessibility hierarchy's nor the screen's geometry: on screen 05 it returns the pinned
    /// `Save check-in` at y=710 *before* the `Back` at y=69, while the hierarchy has Back nine
    /// positions earlier. A reading-order assertion built on it reports defects that do not exist. If
    /// VoiceOver's order is ever tested here, it has to come from recursing the element tree.
    func testNothingIsAnnouncedTwice() {
        continueAfterFailure = true
        defer { continueAfterFailure = false }

        for (screen, anchor) in [
            ("treeProfile", "Tree"), ("site", "No tree at this site"), ("species", "Field guide"),
            ("growthHistory", "Growth"), ("activity", "Activity"), ("outbox", "Outbox"),
        ] {
            let app = launch(screen)
            guard arrive(app, screen: screen, anchor: anchor) else { continue }

            let texts = app.staticTexts.allElementsBoundByIndex.filter { $0.isHittable }
            for (index, outer) in texts.enumerated() {
                let label = outer.label.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !label.isEmpty else { continue }
                for inner in texts[(index + 1)...] where inner.label
                    .trimmingCharacters(in: .whitespacesAndNewlines) == label {
                    // Containment, not mere repetition: two different rows may legitimately say the
                    // same words. One element drawn inside another saying them is the defect.
                    XCTAssertFalse(
                        outer.frame.contains(inner.frame),
                        "\(screen): '\(label)' is announced by an element at \(outer.frame) and again "
                            + "by one inside it at \(inner.frame), so it is heard twice"
                    )
                }
            }
            app.terminate()
        }
    }

    // MARK: - Harness

    private func launch(_ screen: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment[Self.screenKey] = screen
        app.launch()
        return app
    }

    private static let screenKey = "CYPRESS_SCREEN"

    /// The one banner that means the harness itself failed, rather than the screen.
    ///
    /// `DebugDeepLink` draws its failures instead of logging them, so that a resolution that found no
    /// record cannot masquerade as a screen that opened. Checked before anything else is reported,
    /// because "no record nearest 37.7596, -122.4269" is an answer and "'Growth' is not in the tree"
    /// is a riddle.
    private func deepLinkFailure(_ app: XCUIApplication) -> String? {
        let banner = app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH %@", "DEEP LINK FAILED"))
            .firstMatch
        return banner.exists ? banner.label : nil
    }

    /// Waits for the screen and reports precisely which way it did not arrive.
    @discardableResult
    private func arrive(
        _ app: XCUIApplication,
        screen: String,
        anchor: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        let target = app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH %@", anchor))
            .firstMatch
        // Generous: a cold launch opens the database, runs migrations and attaches a 195,309-row seed
        // before the first screen can resolve a record.
        guard target.waitForExistence(timeout: 30) else {
            if let failure = deepLinkFailure(app) {
                XCTFail("\(screen): \(failure)", file: file, line: line)
            } else {
                XCTFail(
                    "\(screen): the app launched but '\(anchor)' never appeared in the accessibility "
                        + "tree — either the screen did not open, or its title is not exposed",
                    file: file, line: line
                )
            }
            return false
        }
        return true
    }

    /// Arrive, then read the tree.
    private func check(
        _ screen: String,
        anchor: String,
        pushed: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let app = launch(screen)
        guard arrive(app, screen: screen, anchor: anchor, file: file, line: line) else { return }

        assertEveryControlIsLabeled(app, screen: screen, file: file, line: line)

        if pushed {
            // A pushed screen covers the tab root, so the bottom bar is gone. Its absence is a second,
            // independent witness that the deep link actually navigated rather than landing on a tab
            // root that happens to contain the anchor text somewhere.
            XCTAssertFalse(
                app.buttons["My Grove"].isHittable,
                "\(screen): the bottom tab bar is still reachable, so this is a tab root rather than "
                    + "the pushed screen the test asked for",
                file: file, line: line
            )

            let back = app.buttons["Back"]
            // Without a reachable Back this screen cannot be left except by a swipe gesture an
            // assistive technology may not perform.
            assertReachable(back, "\(screen): the Back control", file: file, line: line)
        }

        app.terminate()
    }

    /// No interactive element anywhere in the tree may be unlabeled.
    ///
    /// Scoped to what is *hittable*, for the same reason E116's version is: an element behind a cover
    /// or scrolled off the bottom is in the hierarchy without being reachable, and holding it to the
    /// same standard would report failures a user cannot encounter.
    private func assertEveryControlIsLabeled(
        _ app: XCUIApplication,
        screen: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let controls: [(String, XCUIElementQuery)] = [
            ("button", app.buttons),
            ("text field", app.textFields),
            ("search field", app.searchFields),
            ("secure field", app.secureTextFields),
            ("switch", app.switches),
            ("slider", app.sliders),
            ("link", app.links),
        ]
        var checked = 0
        for (kind, query) in controls {
            for index in 0..<query.count {
                let element = query.element(boundBy: index)
                guard element.exists, element.isHittable else { continue }
                checked += 1
                XCTAssertFalse(
                    element.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "\(screen): a \(kind) at \(element.frame) has no accessibility label, so an "
                        + "assistive technology announces it as its type and nothing else",
                    file: file, line: line
                )
            }
        }
        // A screen with no reachable control at all is not a screen this test read — it is a screen
        // that had not finished loading. Every one of these has at least a Back or a close.
        XCTAssertGreaterThan(
            checked, 0,
            "\(screen): no interactive control was reachable, so nothing was actually checked",
            file: file, line: line
        )
    }
}
