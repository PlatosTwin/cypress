//
//  DataDisputeUITests.swift
//  CypressUITests
//
//  RULINGS R79, part 2 — reporting a mistake in a city record, end to end on the running app.
//
//  ── What these hold ────────────────────────────────────────────────────────────────────────
//  1. The whole trip a tester takes: the action on screen 03, the screen it pushes, a dispute with
//     every choice on and a suggestion under each, the profile it returns to drawing the
//     reporter's own standing dispute, and the take-back putting the action back. The take-back is
//     the half the owner has already reported missing from the community flow, so it is driven,
//     not assumed.
//  2. The 10 m floor refusing **out loud**. `CYPRESS_LOCATION`'s third field states a fix's
//     accuracy (`DebugLocationOverride.parse`), so a coarse fix is pinned rather than faked: the
//     app's one location provider reports 40 m, and the screen has to say both numbers and name
//     Precise Location. A floor that refused silently is the defect the owner ruled against.
//  3. An empty report is refused with its own sentence rather than sent or silently ignored.
//  4. PR #185's rulings, on the running app: "There's no tree here" clears and disables the other
//     three; each opened section quotes "The city has: …"; the take-back asks "Take back your
//     report?" first; a 40 m fix with Precise Location **on** is not sent to Settings, and one with
//     it **off** is (the fourth `CYPRESS_LOCATION` field pins that); and *Send report* is disabled
//     while the block is still finding the location.
//
//  Every control is scrolled to before it is touched (`reach`), so the file passes at the
//  accessibility text sizes, where the form runs well below the fold (PR #185's review, finding 7).
//
//  Black-box like the rest of this target: nothing imports `Cypress`, and every literal is a copy
//  constant repeated by hand — `DataDisputeCopy` / `TreeProfileCopy`. If a string is renamed this
//  fails, which is correct: the words a reader acts on changed.
//
//  ── Screenshots ────────────────────────────────────────────────────────────────────────────
//  Each state is written as a PNG for the owner's copy-and-layout ruling. `export
//  TEST_RUNNER_CYPRESS_SHOT_DIR=<dir>` in the shell **before** `Tools/run_tests.sh` chooses the
//  directory (that script's header has the one spelling that works); run once under
//  `xcrun simctl ui <udid> appearance dark` for the dark set — the file names carry the appearance
//  the runner read, so a light and a dark run into one directory do not overwrite each other.
//

import UIKit
import XCTest

final class DataDisputeUITests: XCTestCase, DeepLinkHarness {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: - The words, repeated by hand

    private enum Copy {
        static let action = "Report a mistake in the city’s record"
        static let raised = "You reported a mistake in the city’s record for this tree."
        static let takeBack = "Take back your report"
        static let screenTitle = "Report a mistake"
        static let wrongPlace = "Pin is in the wrong place"
        static let wrongSpecies = "Wrong species"
        static let wrongYear = "Wrong planted year"
        static let noTree = "There’s no tree here"
        static let useLocation = "Use my current location"
        static let captured = "Your location is recorded, good to within 6 m."
        static let chooseSpecies = "Choose the species"
        static let changeSpecies = "Choose a different species"
        static let plantedYear = "Planted year"
        static let send = "Send report"
        static let noIssue = "Choose at least one thing that’s wrong."
        static let openSettings = "Open Settings"
        static let cityHasPrefix = "The city has: "
        static let confirmTitle = "Take back your report?"
        static let keepIt = "Keep it"
        static let waiting = "Finding your location…"
        static let unavailable = "Your phone couldn’t find your location, so no position was used. "
            + "Try again in the open, then use your location again."
        static let preciseLocation = "Turn on Precise Location for Cypress in Settings, then try again."
        static let tryInTheOpen = "Try again in the open, or wait a moment."
    }

    /// `MapLayout.defaultCenter`, the deep link's own resolution point, spelled out because a UI
    /// test cannot import the app target. The camera stays inside the seed's coverage (E216).
    private static let goodFix = "37.7596,-122.4269,6"
    private static let coarseFix = "37.7596,-122.4269,40"
    /// The same 40 m, with Precise Location off for Cypress.
    private static let reducedFix = "37.7596,-122.4269,40,reduced"

    // MARK: - 1 · Raise, see it on the profile, take it back

    func testRaisingADisputeShowsItOnTheProfileAndItCanBeTakenBack() {
        let app = launch(fix: Self.goodFix)
        let action = app.buttons[Copy.action]
        guard arriveOnProfile(app, action: action) else { return }
        record(app, named: "01-profile-raisable")

        action.tap()
        guard arriveOnScreen(app) else { return }
        record(app, named: "02-screen-empty")

        // Three chips — not "There's no tree here", which would clear them (the no-tree test below).
        for chip in [Copy.wrongPlace, Copy.wrongSpecies, Copy.wrongYear] {
            let button = app.buttons[chip]
            reach(button, in: app, "the '\(chip)' chip")
            button.tap()
        }

        // Each opened section quotes the record: three sections, three "The city has:" lines, for
        // a city tree the deep link pins as having a species, a planted year and an address.
        let cityHas = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", Copy.cityHasPrefix))
        XCTAssertTrue(
            cityHas.firstMatch.waitForExistence(timeout: 10),
            "no opened section says what the city has on file"
        )

        // The location answer comes from the pinned provider: 6 m is under the floor, so it is
        // attached and the block says so with the number.
        let useLocation = app.buttons[Copy.useLocation]
        reach(useLocation, in: app, "the use-my-location control")
        useLocation.tap()
        XCTAssertTrue(
            app.staticTexts[Copy.captured].waitForExistence(timeout: 10),
            "a 6 m fix was not reported as recorded — the location block did not take the provider's fix"
        )

        // The species comes from the app's own picker, not a second one.
        let choose = app.buttons[Copy.chooseSpecies]
        reach(choose, in: app, "the choose-the-species control")
        choose.tap()
        let search = app.textFields.firstMatch
        assertReachable(search, "the species picker's search field")
        search.tap()
        search.typeText("Platanus")
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Platanus")).firstMatch
        assertReachable(row, "a Platanus row in the species picker")
        row.tap()
        assertReachable(
            app.buttons[Copy.changeSpecies],
            "the species section after a pick (it should offer to choose a different one)"
        )

        let year = app.textFields[Copy.plantedYear]
        reach(year, in: app, "the planted-year field")
        year.tap()
        year.typeText("1998")
        // The number pad has no return key; the keyboard toolbar's Done is the way to put it away,
        // and the screenshot needs the form rather than the pad.
        let done = app.toolbars.buttons["Done"]
        assertReachable(done, "the keyboard's Done control")
        done.tap()
        XCTAssertTrue(
            app.buttons[Copy.send].waitForExistence(timeout: 10),
            "the Send report button is gone after the keyboard was put away"
        )
        record(app, named: "03-screen-filled")

        let send = app.buttons[Copy.send]
        assertReachable(send, "the Send report button")
        send.tap()

        // Back on the profile, which re-read itself: the reporter's own dispute is standing.
        let raised = app.staticTexts[Copy.raised]
        XCTAssertTrue(
            raised.waitForExistence(timeout: 30),
            "after Send report the profile does not say a report was made — either the raise did "
                + "not land, or the profile did not re-read its offer"
        )
        XCTAssertFalse(
            app.buttons[Copy.action].exists,
            "the profile still offers to report a mistake while this reader's own report stands"
        )
        record(app, named: "04-profile-raised")

        // The take-back asks first (owner, 2026-09-28), in an alert, and "Keep it" leaves the report
        // standing. Queried inside `app.alerts` — the question's own buttons, never the link under
        // it that repeats the action's words. An alert rather than a confirmation dialog because on
        // iOS 26 the dialog left *Keep it* out of the tree entirely (CI, iPhone 17 Pro); these
        // queries are the same on every runtime, which is the point.
        let takeBack = app.buttons[Copy.takeBack].firstMatch
        reach(takeBack, in: app, "the take-back control")
        takeBack.tap()
        let question = app.alerts[Copy.confirmTitle]
        XCTAssertTrue(
            question.waitForExistence(timeout: 10),
            "Take back your report did not ask first — the report was withdrawn without a question"
        )
        record(app, named: "04b-profile-take-back-confirm")
        let keep = question.buttons[Copy.keepIt]
        assertReachable(keep, "the question's Keep it")
        keep.tap()
        XCTAssertTrue(
            raised.waitForExistence(timeout: 10) && !app.buttons[Copy.action].exists,
            "Keep it took the report back anyway"
        )

        reach(takeBack, in: app, "the take-back control, a second time")
        takeBack.tap()
        XCTAssertTrue(question.waitForExistence(timeout: 10), "the second take-back did not ask first")
        let confirmAction = question.buttons[Copy.takeBack]
        assertReachable(confirmAction, "the question's Take back your report")
        confirmAction.tap()
        XCTAssertTrue(
            app.buttons[Copy.action].waitForExistence(timeout: 30),
            "after taking the report back the profile does not offer to report again — the "
                + "withdrawal did not land, or the profile did not re-read its offer"
        )
        XCTAssertFalse(raised.exists, "the profile still says a report was made after it was taken back")
        record(app, named: "05-profile-taken-back")
    }

    // MARK: - 2 · The floor refuses out loud, and truthfully

    /// Precise Location **on**, a 40 m fix: refused with both numbers, told to try in the open —
    /// and not sent to Settings for a switch that is already on (ruling 6).
    func testACoarseFixWithPreciseLocationOnIsNotSentToSettings() {
        let app = launch(fix: Self.coarseFix)
        let action = app.buttons[Copy.action]
        guard arriveOnProfile(app, action: action) else { return }
        action.tap()
        guard arriveOnScreen(app) else { return }

        // Nothing chosen: refused with its own sentence, and the screen stays.
        let send = app.buttons[Copy.send]
        assertReachable(send, "the Send report button")
        send.tap()
        XCTAssertTrue(
            app.staticTexts[Copy.noIssue].waitForExistence(timeout: 10),
            "an empty report was not refused with its own sentence"
        )
        XCTAssertTrue(app.staticTexts[Copy.screenTitle].exists, "an empty report left the screen")

        let refusal = refuseTheFix(app)
        XCTAssertTrue(
            refusal.label.contains(Copy.tryInTheOpen),
            "a coarse fix with Precise Location on was not told what would help: '\(refusal.label)'"
        )
        XCTAssertFalse(
            refusal.label.contains("Precise Location"),
            "a coarse fix with Precise Location on was told to turn it on: '\(refusal.label)'"
        )
        XCTAssertFalse(
            app.buttons[Copy.openSettings].exists,
            "Open Settings is offered for a fix Settings cannot improve"
        )
        assertEveryControlIsLabeled(app, screen: "dataDispute (coarse fix, precise)")
        record(app, named: "06-screen-coarse-fix-precise")
    }

    /// Precise Location **off**: the one case where Settings is the answer, and the sentence says so.
    func testACoarseFixWithPreciseLocationOffNamesItAndOffersSettings() {
        let app = launch(fix: Self.reducedFix)
        let action = app.buttons[Copy.action]
        guard arriveOnProfile(app, action: action) else { return }
        action.tap()
        guard arriveOnScreen(app) else { return }

        let refusal = refuseTheFix(app)
        XCTAssertTrue(
            refusal.label.contains(Copy.preciseLocation),
            "reduced accuracy was not told to turn on Precise Location: '\(refusal.label)'"
        )
        let settings = app.buttons[Copy.openSettings]
        reach(settings, in: app, "the Open Settings control under the refusal")
        assertEveryControlIsLabeled(app, screen: "dataDispute (coarse fix, reduced)")
        record(app, named: "07-screen-coarse-fix-reduced")
    }

    // MARK: - 3 · "There's no tree here" stands alone

    func testNoTreeClearsAndDisablesTheOtherChips() {
        let app = launch(fix: Self.goodFix)
        let action = app.buttons[Copy.action]
        guard arriveOnProfile(app, action: action) else { return }
        action.tap()
        guard arriveOnScreen(app) else { return }

        let others = [Copy.wrongPlace, Copy.wrongSpecies, Copy.wrongYear]
        for chip in others {
            let button = app.buttons[chip]
            reach(button, in: app, "the '\(chip)' chip")
            button.tap()
            XCTAssertTrue(button.isSelected, "the '\(chip)' chip did not turn on")
        }

        let noTree = app.buttons[Copy.noTree]
        reach(noTree, in: app, "the no-tree chip")
        noTree.tap()
        XCTAssertTrue(noTree.isSelected, "the no-tree chip did not turn on")
        for chip in others {
            let button = app.buttons[chip]
            XCTAssertFalse(button.isSelected, "'\(chip)' stayed on beside There’s no tree here")
            XCTAssertFalse(button.isEnabled, "'\(chip)' can still be chosen beside There’s no tree here")
        }
        XCTAssertFalse(
            app.buttons[Copy.useLocation].exists,
            "the location section is still open after its chip was cleared"
        )
        record(app, named: "08-screen-no-tree")

        noTree.tap()
        XCTAssertFalse(noTree.isSelected, "the no-tree chip did not turn off")
        for chip in others {
            let button = app.buttons[chip]
            XCTAssertTrue(button.isEnabled, "'\(chip)' stayed disabled after no-tree was unticked")
            XCTAssertFalse(button.isSelected, "'\(chip)' came back on by itself")
        }
    }

    // MARK: - 4 · Send waits for a pending fix

    func testSendIsDisabledWhileTheLocationIsStillBeingFound() {
        let app = launch(fix: "waitingForFix")
        let action = app.buttons[Copy.action]
        guard arriveOnProfile(app, action: action) else { return }
        action.tap()
        guard arriveOnScreen(app) else { return }

        let wrongPlace = app.buttons[Copy.wrongPlace]
        reach(wrongPlace, in: app, "the pin chip")
        wrongPlace.tap()
        let useLocation = app.buttons[Copy.useLocation]
        reach(useLocation, in: app, "the use-my-location control")
        useLocation.tap()
        XCTAssertTrue(
            app.staticTexts[Copy.waiting].waitForExistence(timeout: 10),
            "the block does not say it is finding the location"
        )
        let send = app.buttons[Copy.send]
        XCTAssertTrue(send.waitForExistence(timeout: 10), "the Send report button is gone")
        XCTAssertFalse(
            send.isEnabled,
            "Send report can be pressed while the position the reporter asked for is still arriving"
        )
        record(app, named: "09-screen-finding-location")

        // Un-choosing the pin chip ends the wait: nothing about a position is promised any more.
        wrongPlace.tap()
        XCTAssertTrue(send.isEnabled, "Send report stayed disabled with the pin chip off")
    }

    // MARK: - 5 · A fix that never comes stops holding Send (owner ruling 11)

    /// `waitingForFix` pins a provider that never publishes a fix — "no fix, ever", which is the case
    /// the ruling is about. After `DataDisputeLocation.fixTimeout` (15 s) the block says so and *Send*
    /// works; *Use my current location* asks again and holds *Send* again.
    func testAFixThatNeverComesStopsHoldingSend() {
        let app = launch(fix: "waitingForFix")
        let action = app.buttons[Copy.action]
        guard arriveOnProfile(app, action: action) else { return }
        action.tap()
        guard arriveOnScreen(app) else { return }

        let wrongPlace = app.buttons[Copy.wrongPlace]
        reach(wrongPlace, in: app, "the pin chip")
        wrongPlace.tap()
        let useLocation = app.buttons[Copy.useLocation]
        reach(useLocation, in: app, "the use-my-location control")
        useLocation.tap()
        let send = app.buttons[Copy.send]
        XCTAssertTrue(app.staticTexts[Copy.waiting].waitForExistence(timeout: 10))
        XCTAssertFalse(send.isEnabled, "Send was not held while the location was being found")

        XCTAssertTrue(
            app.staticTexts[Copy.unavailable].waitForExistence(timeout: 40),
            "15 s with no fix and the block still does not say it could not find the location"
        )
        XCTAssertTrue(send.isEnabled, "Send is still held after the block gave up on the location")
        record(app, named: "10-screen-location-unavailable")

        reach(useLocation, in: app, "the use-my-location control, to try again")
        useLocation.tap()
        XCTAssertTrue(
            app.staticTexts[Copy.waiting].waitForExistence(timeout: 10),
            "Use my current location did not try again"
        )
        XCTAssertFalse(send.isEnabled, "a new request did not hold Send again")
    }

    // MARK: - Harness

    /// Chooses the pin chip, asks for the location, and returns the refusal the pinned 40 m fix
    /// draws — asserting both numbers, which every refusal of a stated radius quotes.
    private func refuseTheFix(_ app: XCUIApplication) -> XCUIElement {
        let wrongPlace = app.buttons[Copy.wrongPlace]
        reach(wrongPlace, in: app, "the pin chip")
        wrongPlace.tap()
        let useLocation = app.buttons[Copy.useLocation]
        reach(useLocation, in: app, "the use-my-location control")
        useLocation.tap()

        let refusal = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", "only good to within 40 m"))
            .firstMatch
        XCTAssertTrue(
            refusal.waitForExistence(timeout: 10),
            "a 40 m fix was not refused out loud with its own accuracy"
        )
        XCTAssertTrue(
            refusal.label.contains("within 10 m"),
            "the refusal does not quote the floor it refused against: '\(refusal.label)'"
        )
        return refusal
    }

    /// Scrolls until `element` can be pressed, then asserts it can.
    ///
    /// Bounded, for `AddReadingReachabilityTests.scrollIntoView`'s reason, and in both directions:
    /// at the accessibility sizes the form runs well below the fold, and a control the test already
    /// scrolled past sits above it. `isHittableWithoutRaising` because this is a filter position.
    private func reach(
        _ element: XCUIElement,
        in app: XCUIApplication,
        _ description: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        _ = element.waitForExistence(timeout: 10)
        let screen = app.frame
        for _ in 0..<6 where !element.isHittableWithoutRaising(onScreen: screen) {
            app.swipeUp()
        }
        for _ in 0..<6 where !element.isHittableWithoutRaising(onScreen: screen) {
            app.swipeDown()
        }
        assertReachable(element, description, file: file, line: line)
    }

    private func launch(fix: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment[Self.deepLinkScreenKey] = "dataDispute"
        app.launchEnvironment["CYPRESS_LOCATION"] = fix
        DebugMapCamera.pin(app)
        app.launch()
        return app
    }

    private func arriveOnProfile(_ app: XCUIApplication, action: XCUIElement) -> Bool {
        guard action.waitForExistence(timeout: 60) else {
            XCTFail(
                deepLinkFailure(app).map { "dataDispute: \($0)" }
                    ?? "dataDispute: the profile never drew '\(Copy.action)' — the city tree is not "
                        + "offered as raisable, or the deep link opened something else"
            )
            return false
        }
        assertReachable(action, "the profile's report-a-mistake action")
        return true
    }

    private func arriveOnScreen(_ app: XCUIApplication) -> Bool {
        guard arrive(app, screen: "dataDispute", anchor: Copy.screenTitle) else { return false }
        assertEveryControlIsLabeled(app, screen: "dataDispute")
        assertReachable(app.buttons["Back"], "dataDispute: the Back control")
        return true
    }

    /// A PNG per state, plus the same image on the result bundle — `AreaPickerUITests.record`.
    private func record(_ app: XCUIApplication, named name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let appearance = UITraitCollection.current.userInterfaceStyle == .dark ? "dark" : "light"
        let directory = ProcessInfo.processInfo.environment["CYPRESS_SHOT_DIR"] ?? NSTemporaryDirectory()
        let url = URL(fileURLWithPath: directory).appendingPathComponent("dispute-\(appearance)-\(name).png")
        try? shot.pngRepresentation.write(to: url)
        print("CYPRESS-SHOT: \(url.path)")
    }
}
