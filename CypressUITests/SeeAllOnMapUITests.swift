//
//  SeeAllOnMapUITests.swift
//  Cypress — UI tests
//
//  **Tester report F23, end to end**: the Journal tab's `Yours` segment draws a link, pressing it
//  lands on screen 01 with the `Yours` chip already on, and the chip row can take it off again.
//
//  ── What this file exists for, next to the unit suite ────────────────────────────────────────
//  `CypressTests/SeeAllOnMapTests` proves the value half — that the route arms the narrowing, that
//  the arming is spent once, and that every tree the journal names is under the map's `Yours`. None
//  of it can prove that a finger reaches the link or that the map draws the chip it arrived under:
//  SwiftUI builds no in-process accessibility tree (ARCHITECTURE §7, E116), and this project has
//  twice shipped something correct that nobody could reach (E110's untappable `Back`, E173's
//  unreachable delete).
//
//  ── The escape is the assertion, not a courtesy ──────────────────────────────────────────────
//  A map that opens narrowed with no visible cause is E126's screen showing something other than
//  what was asked for. Screen 01 answers that with the chip's selected state and the `Clear filters`
//  chip, which is in the row for exactly as long as any dimension is set — so this test presses it
//  and watches it go, because "the way out is drawn" and "the way out works" are two claims.
//
//  **And there is a third claim, which the first version of this file could not make** (PR #130
//  review, F2): that the way out is *on screen*. `isHittable` and `.tap()` cannot say it, because
//  XCUITest scrolls an element into view before answering either — so this file measures the chip's
//  frame against the window before it touches anything.
//
//  ── Why the journal has to be seeded ─────────────────────────────────────────────────────────
//  The link draws only over a list (`JournalPresentation.offersMapLink`), and this device has made
//  no contributions — `CYPRESS_SCREEN=journalList` is deliberately the cold-start state. The
//  `journalContributions` case writes one check-in first, onto a tree of its own, under a fixed
//  `client_uuid` so a second run adds nothing.
//

import XCTest

final class SeeAllOnMapUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// `JournalCopy.seeAllOnMap`, spelled out because a UI test cannot import the app target.
    private static let link = "See them all on the map"

    /// `MapFilterCopy.membershipLabel(.yours)` and `MapFilterCopy.clearLabel`.
    private static let yoursChip = "Yours"
    private static let clearChip = "Clear filters"

    /// `MapFilterCopy.chipValue(isOn:)`. The chip's drawn state is a fill and a weight, and neither
    /// is available to this target — the spoken value is the only channel that carries it.
    private static let on = "On"
    private static let off = "Off"

    func testTheLinkOpensTheMapNarrowedToYoursAndTheNarrowingCanBeCleared() {
        let app = launch()
        guard arrive(app) else { return }

        let link = app.buttons[Self.link]
        assertReachable(link, "the journal drew rows and no way onto the map")
        link.tap()

        // Arrived, and arrived narrowed. The chip is the whole of screen 01's voice about a filter
        // (RULINGS R41), so it is both the proof that the route carried the narrowing and the proof
        // that the reader can see it.
        let yours = app.buttons[Self.yoursChip]
        XCTAssertTrue(
            yours.waitForExistence(timeout: 30),
            "the map never drew its filter row, so the link did not land on screen 01"
        )
        XCTAssertTrue(
            wait { (yours.value as? String) == Self.on },
            "the map opened with the “Yours” chip off — the link arrived somewhere unnarrowed, "
                + "which is the whole of what F23 asked for. Chip value: "
                + "\(yours.value as? String ?? "nil")"
        )

        // ══════════════════════════════════════════════════════════════════════════════════════
        // **The way out is ON SCREEN, measured from its frame** (PR #130 review, F2).
        //
        // `assertReachable` and `.tap()` were the whole of this check and they cannot make this
        // claim: XCUITest scrolls an element inside a `ScrollView` into view before it answers
        // `isHittable` and before it synthesizes a tap, so both passed while `Clear filters` sat
        // past the trailing edge of the one-line chip row on this 390 pt phone — reachable by a
        // drag nobody had been told about. That is the E126 hazard on the one entrance where the
        // reader did not press a filter to get here.
        //
        // So the frame is read FIRST, before anything can scroll the row, and it is read against
        // the window rather than against a constant — this suite must say the same true thing on a
        // 440 pt phone. The same lesson `MapFilterAccessibilityTests` learned at AX5: frames are
        // the one channel a scroller cannot hide.
        // ══════════════════════════════════════════════════════════════════════════════════════
        let clear = app.buttons[Self.clearChip]
        XCTAssertTrue(
            clear.waitForExistence(timeout: 30),
            "a map that arrived filtered drew no “\(Self.clearChip)” chip at all"
        )
        let screen = app.windows.firstMatch.frame
        let clearBox = clear.frame
        XCTAssertGreaterThanOrEqual(
            clearBox.minX, screen.minX - 0.5,
            "the “\(Self.clearChip)” chip starts off the leading edge (\(clearBox) on a "
                + "\(screen.width)×\(screen.height) screen)"
        )
        XCTAssertLessThanOrEqual(
            clearBox.maxX, screen.maxX + 0.5,
            "the “\(Self.clearChip)” chip is clipped past the trailing edge (\(clearBox) on a "
                + "\(screen.width)×\(screen.height) screen), so a reader who arrived narrowed from "
                + "the journal has to discover a horizontal drag to find the way out. XCUITest "
                + "would still tap it, which is why this measures the frame."
        )
        // And the cause stays on screen beside it — a visible way out that had scrolled the
        // selected chip off would be the same defect with the halves swapped.
        let yoursBox = yours.frame
        XCTAssertLessThanOrEqual(
            yoursBox.maxX, screen.maxX + 0.5,
            "the “\(Self.yoursChip)” chip is off the trailing edge (\(yoursBox)), so the map is "
                + "narrowed with nothing on screen saying by what"
        )

        clear.tap()

        // **Presence, not absence** (CLAUDE.md; PR #130 review, F6). The `Yours` chip is drawn
        // unconditionally, so its off state is a value this target can read and assert — strictly
        // stronger than "not on", which a chip that had vanished would also satisfy. The clear
        // chip's departure is the second half: it is in the row for as long as any dimension is set
        // and for no longer.
        XCTAssertTrue(
            wait { (yours.value as? String) == Self.off && !clear.exists },
            "the narrowing survived “\(Self.clearChip)” — a reader routed here from the journal "
                + "cannot get back to the whole map. Chip value: "
                + "\(yours.value as? String ?? "nil"), clear chip present: \(clear.exists)"
        )
    }

    // MARK: - Harness

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CYPRESS_SCREEN"] = "journalContributions"
        // The map this test lands on inherits whatever camera the last launch left (E216, and
        // `DebugMapCamera`'s own header). Nothing here reads a pin, but a camera over open water
        // draws no map chrome worth waiting on and the failure would read as a defect in the link.
        DebugMapCamera.pin(app)
        app.launch()
        return app
    }

    /// Arrives on the Journal tab's `Yours` segment, reporting a harness failure as a harness
    /// failure — `DebugDeepLink` draws its failures over the app for exactly this reason.
    private func arrive(_ app: XCUIApplication) -> Bool {
        let banner = app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH %@", "DEEP LINK FAILED"))
            .firstMatch
        // Generous: a cold launch opens the database, runs migrations and attaches the seed before
        // it can resolve a tree, write a check-in and read a journal back.
        guard app.buttons[Self.link].waitForExistence(timeout: 60) else {
            XCTFail(
                banner.exists
                    ? banner.label
                    : "the journal never drew its map link, so this test could not have failed for "
                        + "its own reason"
            )
            return false
        }
        return true
    }

    /// Polls. The map debounces the camera and then reads an attached database; what is worth
    /// asserting is where the screen settles, never when.
    @discardableResult
    private func wait(timeout: TimeInterval = 20, for condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            usleep(200_000)
        }
        return condition()
    }
}
