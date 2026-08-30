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
//  review, F2): where these controls *are*. `isHittable` and `.tap()` cannot say it, because
//  XCUITest scrolls an element into view before answering either — so this file measures frames
//  against the window before it touches anything. The cause must be on screen; the way out must be
//  on the same line. `MapHomeView.applyPendingFilter` carries the measurement for why the second
//  of those is not "on screen" too, and it is in the PR's ratification list rather than fixed here.
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
        // **Measured from frames, not from hittability** (PR #130 review, F2).
        //
        // `assertReachable` and `.tap()` were the whole of the escape check here, and neither can
        // say where a control *is*: XCUITest scrolls an element inside a `ScrollView` into view
        // before it answers `isHittable` and before it synthesizes a tap, so both pass over a chip
        // sitting past the trailing edge. Frames are the one channel a scroller cannot hide — the
        // same lesson `MapFilterAccessibilityTests` learned at AX5 — and they are read here BEFORE
        // anything touches the row, and against the window rather than a constant, so this says the
        // same true thing on a 440 pt phone.
        //
        // **What is asserted is the cause, and it is the half that matters on this entrance.** A
        // reader who arrives narrowed without having pressed anything needs to see *why* the map is
        // narrowed; that is the filled `Yours` chip, and it is at the leading edge. `Clear filters`
        // is the fifth chip of a one-line row that does not fit five chips on a 390 pt phone, so it
        // is in the row and one drag away — see `MapHomeView.applyPendingFilter` for the measurement
        // and for why pinning it beside the scroller is a worse trade rather than a fix. Which chip
        // loses that width is the owner's call, so this file does not assert an answer to it.
        // ══════════════════════════════════════════════════════════════════════════════════════
        let screen = app.windows.firstMatch.frame
        let yoursBox = yours.frame
        XCTAssertGreaterThanOrEqual(
            yoursBox.minX, screen.minX - 0.5,
            "the “\(Self.yoursChip)” chip starts off the leading edge (\(yoursBox) on a "
                + "\(screen.width)×\(screen.height) screen)"
        )
        XCTAssertLessThanOrEqual(
            yoursBox.maxX, screen.maxX + 0.5,
            "the “\(Self.yoursChip)” chip is off the trailing edge (\(yoursBox) on a "
                + "\(screen.width)×\(screen.height) screen), so the map arrived narrowed with "
                + "nothing on screen saying by what — E126 through the one door where the reader "
                + "pressed no filter. XCUITest would still find it hittable, which is why this "
                + "measures the frame."
        )

        // **The way out is in the row, on the same line as the cause.** It cannot be asserted to be
        // on screen (see above), so what is pinned instead is that it has not moved somewhere else:
        // one drag along the row a reader is already looking at, and not a control that has drifted
        // onto another band of the chrome. The 4 pt rounding is the band `MapFilterAccessibility
        // Tests` uses for the same question.
        let clear = app.buttons[Self.clearChip]
        XCTAssertTrue(
            clear.waitForExistence(timeout: 30),
            "a map that arrived filtered drew no “\(Self.clearChip)” chip at all, so there is no "
                + "way out of a narrowing the reader did not ask for"
        )
        let clearBox = clear.frame
        XCTAssertEqual(
            Int((clearBox.minY / 4).rounded()), Int((yoursBox.minY / 4).rounded()),
            "the “\(Self.clearChip)” chip is not on the filter row's line: it is at \(clearBox) "
                + "against the “\(Self.yoursChip)” chip's \(yoursBox)"
        )

        assertReachable(clear, "a map that arrived filtered offered no way to clear the filter")
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
