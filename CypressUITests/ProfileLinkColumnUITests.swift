//
//  ProfileLinkColumnUITests.swift
//  CypressUITests
//
//  ROADMAP 119: the column of text links under a tree's name on screen 03.
//
//  On the profile of a tree this phone added with no species, four links sit one under the next:
//  `Show me where this is`, `Move pin`, `Say what species you think this is` and `Report that there
//  is no tree here`. Their label centers are about 18 pt apart, and each link's tap area is 44 pt
//  tall, so the tap areas of two neighbors can overlap. The owner wants the column tight
//  (2026-11-14), so the fix is in the tap areas and not in the spacing.
//
//  1. A tap just inside one link's side of the midpoint between two neighbors opens that link and
//     not its neighbor, for every neighboring pair in the column.
//  2. The links still sit at one even pitch: the column's own spacing is the reference, so a fix
//     that pushed the links apart fails here.
//
//  Black-box like the rest of this target: nothing imports `Cypress`, and every literal is a copy
//  constant repeated by hand. If a string is renamed this fails, which is correct.
//

import XCTest

final class ProfileLinkColumnUITests: XCTestCase, DeepLinkHarness {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private enum Copy {
        /// `PinSetCopy.showWhereAction`
        static let showWhere = "Show me where this is"
        /// `MovePinCopy.action`
        static let movePin = "Move pin"
        /// `TreeProfileCopy.claimSpeciesAction`
        static let claimSpecies = "Say what species you think this is"
        /// `TreeProfileCopy.reportNeverExistedAction`
        static let reportNoTree = "Report that there is no tree here"

        /// `PinSetCopy.recenterLabel(_:)`: the screen `Show me where this is` opens.
        static let pinSetRecenterPrefix = "Center the map on"
        /// `MovePinCopy`: the screen `Move pin` opens.
        static let movePinUnmoved = "The pin has not moved."
        /// `SpeciesPickCopy.title`: the cover `Say what species you think this is` opens.
        static let speciesPickTitle = "Which species?"
        /// `SpeciesPickCopy.skip`: how that cover is left without a claim.
        static let speciesPickSkip = "I'm not sure"
        /// `TreeProfileCopy.recordReported`: what the profile says after `Report` was pressed.
        static let recordReported = "This record has been reported as never having held a tree."
        static let back = "Back"
    }

    /// The column, top to bottom. A link's position in this list is its position on screen.
    private static let column = [Copy.showWhere, Copy.movePin, Copy.claimSpecies, Copy.reportNoTree]

    // MARK: - 1 · Each tap reaches the link it was meant for

    /// For each pair of neighbors, one tap 2 pt above the midpoint between the two labels and one
    /// 2 pt below it. Each tap must open the link on its own side.
    ///
    /// The taps are placed from the frames the screen reports, not from numbers chosen here, so the
    /// test follows the layout wherever it is. `Report` writes a flag on the record and its link then
    /// goes away, so the one tap that may press it is the last tap of the run.
    func testATapOnEitherSideOfTheMidpointOpensThatLinkAndNotItsNeighbor() {
        let app = launchColumn()
        guard arriveAtColumn(app) else { return }

        for index in 0..<(Self.column.count - 1) {
            let upper = Self.column[index]
            let lower = Self.column[index + 1]

            tapPoint(between: upper, and: lower, side: .upper, in: app).tap()
            let fromUpper = opened(in: app)
            XCTAssertEqual(
                fromUpper, upper,
                "a tap 2 pt above the midpoint between '\(upper)' and '\(lower)' opened "
                    + "\(fromUpper.map { "'\($0)'" } ?? "nothing") instead of '\(upper)'"
            )
            returnToProfile(from: upper, in: app)

            tapPoint(between: upper, and: lower, side: .lower, in: app).tap()
            let fromLower = opened(in: app)
            XCTAssertEqual(
                fromLower, lower,
                "a tap 2 pt below the midpoint between '\(upper)' and '\(lower)' opened "
                    + "\(fromLower.map { "'\($0)'" } ?? "nothing") instead of '\(lower)'"
            )
            returnToProfile(from: lower, in: app)
        }
    }

    // MARK: - 2 · The column did not move

    /// The center-to-center distance between each pair of neighbors equals the others, within a
    /// point. The reference is the column itself: the four labels are the same font, one line each,
    /// in one stack with one spacing, so equal pitches are what an untouched column draws. A fix that
    /// padded one link to keep its tap area clear of a neighbor's makes one pitch larger than the
    /// rest, which is what builds 87 and 88 did to `Move pin`.
    func testTheLinksSitOneEvenPitchApart() {
        let app = launchColumn()
        guard arriveAtColumn(app) else { return }

        let frames = Self.column.map { settledFrame(app.buttons[$0], "'\($0)'") }
        let pitches = zip(frames, frames.dropFirst()).map { $1.midY - $0.midY }
        for (index, pitch) in pitches.enumerated() {
            XCTAssertGreaterThan(
                pitch, frames[index].height / 2,
                "'\(Self.column[index + 1])' is not below '\(Self.column[index])'"
            )
        }
        let reference = pitches[0]
        for (index, pitch) in pitches.enumerated().dropFirst() {
            XCTAssertEqual(
                pitch, reference, accuracy: 1,
                "'\(Self.column[index])' to '\(Self.column[index + 1])' is \(pitch) pt center to "
                    + "center, where '\(Self.column[0])' to '\(Self.column[1])' is \(reference) pt: "
                    + "the column is no longer evenly spaced (pitches \(pitches))"
            )
        }
    }

    // MARK: - Helpers

    private enum Side { case upper, lower }

    /// `MapLayout.defaultCenter` with a 6 m fix, spelled out because a UI test cannot import the app
    /// target. `DataDisputeUITests.goodFix` is the same value.
    private static let fix = "37.7596,-122.4269,6"

    /// Opens the profile with the location pinned, the way `DataDisputeUITests.launch(fix:)` does.
    ///
    /// **Pinned because this test taps by coordinate.** On a simulator whose location was never
    /// answered, the system's location prompt can come up over the profile, and a coordinate tap
    /// then lands on the prompt instead of the link it was aimed at. Seen by hand on a fresh slot
    /// simulator, with the app launched without `CYPRESS_LOCATION`.
    private func launchColumn() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment[Self.deepLinkScreenKey] = "profileLinks"
        app.launchEnvironment["CYPRESS_LOCATION"] = Self.fix
        DebugMapCamera.pin(app)
        app.launch()
        return app
    }

    /// Waits for every link in the column to be on screen and reachable.
    private func arriveAtColumn(_ app: XCUIApplication) -> Bool {
        let first = app.buttons[Self.column[0]]
        guard first.waitForExistence(timeout: 60) else {
            XCTFail(
                deepLinkFailure(app).map { "profileLinks: \($0)" }
                    ?? "profileLinks: the profile never drew '\(Self.column[0])'"
            )
            return false
        }
        for label in Self.column {
            assertReachable(app.buttons[label], "'\(label)'")
        }
        return true
    }

    /// A point 2 pt to one side of the midpoint between two neighboring labels, 8 pt in from the
    /// labels' shared left edge, which is on the words of both.
    private func tapPoint(
        between upper: String, and lower: String, side: Side, in app: XCUIApplication
    ) -> XCUICoordinate {
        let top = settledFrame(app.buttons[upper], "'\(upper)'")
        let bottom = settledFrame(app.buttons[lower], "'\(lower)'")
        XCTAssertLessThan(top.midY, bottom.midY, "'\(upper)' is not above '\(lower)'")
        let midpoint = (top.maxY + bottom.minY) / 2
        let y = side == .upper ? midpoint - 2 : midpoint + 2
        let x = max(top.minX, bottom.minX) + 8
        return app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y))
    }

    /// Which link the last tap opened, read off what it opened. `nil` when nothing opened.
    private func opened(in app: XCUIApplication) -> String? {
        let outcomes: [(String, XCUIElement)] = [
            (
                Copy.showWhere,
                app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", Copy.pinSetRecenterPrefix))
                    .firstMatch
            ),
            (Copy.movePin, app.staticTexts[Copy.movePinUnmoved]),
            (Copy.claimSpecies, app.staticTexts[Copy.speciesPickTitle]),
            (Copy.reportNoTree, app.staticTexts[Copy.recordReported]),
        ]
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if let hit = outcomes.first(where: { $0.1.exists }) { return hit.0 }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return nil
    }

    /// Back to the profile after `link` opened, with the column reachable again. `Report` opens
    /// nothing, so after it there is nothing to leave.
    private func returnToProfile(from link: String, in app: XCUIApplication) {
        switch link {
        case Copy.claimSpecies:
            let skip = app.buttons[Copy.speciesPickSkip]
            assertReachable(skip, "the species picker's '\(Copy.speciesPickSkip)'")
            skip.tap()
        case Copy.reportNoTree:
            return
        default:
            let back = app.buttons[Copy.back]
            assertReachable(back, "the Back control after '\(link)'")
            back.tap()
        }
        assertReachable(app.buttons[Self.column[0]], "'\(Self.column[0])' back on the profile")
    }
}
