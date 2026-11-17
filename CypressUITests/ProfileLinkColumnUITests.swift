//
//  ProfileLinkColumnUITests.swift
//  CypressUITests
//
//  ROADMAP 119: the column of text links under a tree's name on screen 03.
//
//  On the profile of a tree this phone added with no species, four links sit one under the next:
//  `Show me where this is`, `Move pin`, `Say what species you think this is` and `Withdraw this
//  tree`. (`Report that there is no tree here` stood fourth until the owner's answer of 2026-11-16
//  hid it while the withdraw link shows.) Their label centers are about 18 pt apart, and each link's tap area is 44 pt
//  tall, so the tap areas of two neighbors can overlap. The owner wants the column tight
//  (2026-11-14), so the fix is in the tap areas and not in the spacing.
//
//  1. A tap just inside one link's side of the midpoint between two neighbors opens that link and
//     not its neighbor, for every neighboring pair in the column.
//  2. The links still sit at one even pitch: the column's own spacing is the reference, so a fix
//     that pushed the links apart fails here.
//  3. At the largest text size, a link that wraps starts every line on the column's edge (ROADMAP
//     183), in light and dark.
//
//  Black-box like the rest of this target: nothing imports `Cypress`, and every literal is a copy
//  constant repeated by hand. If a string is renamed this fails, which is correct.
//

import UIKit
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
        /// `TreeProfileCopy.reportSpeciesAction`
        static let reportSpecies = "Report the species as wrong"
        /// `TreeProfileCopy.withdrawTreeAction`
        static let withdrawTree = "Withdraw this tree"

        /// `PinSetCopy.recenterLabel(_:)`: the screen `Show me where this is` opens.
        static let pinSetRecenterPrefix = "Center the map on"
        /// `MovePinCopy`: the screen `Move pin` opens.
        static let movePinUnmoved = "The pin has not moved."
        /// `SpeciesPickCopy.title`: the cover `Say what species you think this is` opens.
        static let speciesPickTitle = "Which species?"
        /// `SpeciesPickCopy.skip`: how that cover is left without a claim.
        static let speciesPickSkip = "I'm not sure"
        /// `TreeProfileCopy.withdrawTreeConfirmTitle`: the alert `Withdraw this tree` opens.
        static let withdrawTreeTitle = "Withdraw this tree?"
        /// `TreeProfileCopy.withdrawTreeCancel`: how that alert is left without withdrawing.
        static let withdrawTreeKeep = "Keep it"
        static let back = "Back"
    }

    /// The column, top to bottom. A link's position in this list is its position on screen.
    private static let column = [Copy.showWhere, Copy.movePin, Copy.claimSpecies, Copy.withdrawTree]

    // MARK: - 1 · Each tap reaches the link it was meant for

    /// For each pair of neighbors, one tap 2 pt above the midpoint between the two labels and one
    /// 2 pt below it. Each tap must open the link on its own side.
    ///
    /// The taps are placed from the frames the screen reports, not from numbers chosen here, so the
    /// test follows the layout wherever it is. `Withdraw this tree` only asks first, and the test
    /// answers `Keep it`, so the tree is still there for the next tap.
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
    ///
    /// **Measured on top edges, not centers, since the last link became `Withdraw this tree`.** A
    /// link's frame as XCUITest reports it includes the part of its hit area below the label that no
    /// later element covers. `Report that there is no tree here` had its caption right under it, and
    /// `Withdraw this tree` has open space, so its frame reaches about 13 pt further down and its
    /// center reads about 6.7 pt low (24.3 pt against 17.7 pt) while the labels on screen sit evenly
    /// (checked on a screenshot, 2026-11-16). Each frame's top is the label's top less the same
    /// `reachingAbove` cut, so top-to-top distances are the label pitches.
    func testTheLinksSitOneEvenPitchApart() {
        let app = launchColumn()
        guard arriveAtColumn(app) else { return }

        let frames = Self.column.map { settledFrame(app.buttons[$0], "'\($0)'") }
        let pitches = zip(frames, frames.dropFirst()).map { $1.minY - $0.minY }
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
                "'\(Self.column[index])' to '\(Self.column[index + 1])' is \(pitch) pt top to "
                    + "top, where '\(Self.column[0])' to '\(Self.column[1])' is \(reference) pt: "
                    + "the column is no longer evenly spaced (pitches \(pitches))"
            )
        }
    }

    // MARK: - 3 · A link that wraps keeps every line on the column's edge (ROADMAP 183)

    /// At the largest text size the longer links in this column wrap. Each line of a wrapped link
    /// must start on the same leading edge as its one-line neighbors. The test measures in the
    /// device's own appearance: run it once more under `xcrun simctl ui <udid> appearance dark` for
    /// dark, and the screenshots' names say which they are. On this Mac the device had to be shut
    /// down and booted again before a new appearance reached the app. Before
    /// the fix, a wrapped link drew its lines centered, so its second line started far to the right
    /// of the column's edge. The default size is measured too: there each link is one line on the
    /// same edge, which is what the fix must leave alone.
    ///
    /// **What this reads, and what it does not.** XCUITest cannot see text alignment: a link's
    /// accessibility frame is the whole width of the column whether its words sit on the left or in
    /// the middle. So the test reads the pixels. It takes the link's own screenshot, finds the rows
    /// that carry ink, groups them into lines of text, and finds where each line's ink starts. That
    /// start must be within `inkTolerance` of the column's edge, which is the frame of the one-line
    /// link `Show me where this is`. The tolerance covers a glyph's own side bearing ("R" and "t"
    /// start their ink a point or two apart). A centered second line starts tens of points in.
    ///
    /// It does not prove the lines are drawn in the right font, color, or spacing, and it does not
    /// prove anything about a link this list does not name. Each named link must wrap at AX5 on the
    /// device the test runs on, or the test fails and says so: a link on one line proves nothing
    /// about wrapping. It launches each screen twice, so one run adds two trees to each slot line
    /// it uses.
    func testEveryLineOfAColumnLinkStartsOnTheColumnEdge() {
        // Every screen, size, and link is measured even after one fails, so a red run says which
        // of them are off, not only the first.
        continueAfterFailure = true
        signTheSharerOutAfterwards()

        let cases: [(screen: String, links: [String])] = [
            // "Withdraw this tree" is drawn by the same helper and is one line at AX5 on a 440 pt
            // phone, so it cannot show a wrapped line here and is left out.
            ("profileLinks", [Copy.claimSpecies]),
            ("othersTreeSharing", [Copy.reportSpecies]),
            // `Report that there is no tree here` is hidden on the reader's own tree while the
            // withdraw link shows (the owner's answer of 2026-11-16), so it is measured where it
            // still shows: on a tree other people have added to, beside the reason line.
            ("withdrawTreeBuiltOn", [Copy.reportNoTree]),
        ]
        for (screen, links) in cases {
            for largest in [false, true] {
                let size = largest ? "ax5" : "default"
                let app = XCUIApplication()
                app.launchEnvironment[Self.deepLinkScreenKey] = screen
                app.launchEnvironment["CYPRESS_LOCATION"] = Self.fix
                if largest {
                    app.launchArguments += [
                        "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
                    ]
                }
                DebugMapCamera.pin(app)
                app.launch()

                let edgeLink = app.buttons[Copy.showWhere]
                guard edgeLink.waitForExistence(timeout: 60) else {
                    XCTFail(deepLinkFailure(app).map { "\(screen): \($0)" } ?? "\(screen): no '\(Copy.showWhere)'")
                    return
                }
                let edge = edgeLink.frame
                Self.dismissTheLocationAlert()
                // The appearance the screen was drawn in, read off the screen itself. Neither
                // `XCUIDevice.shared.appearance` set from here nor `UITraitCollection.current` in
                // the runner followed the device: the first left the "dark" shots byte for byte the
                // light ones, and the second read light on a device drawing dark.
                let appearance = Self.isDrawnDark(app) ? "dark" : "light"

                do {
                    let place = "on \(screen) (\(size), \(appearance))"
                    for label in links {
                        let link = app.buttons[label]
                        scrollWhollyOnScreen(link, in: app)
                        let frame = settledFrame(link, "'\(label)' \(place)")
                        recordScreen(named: "\(screen)-\(size)-\(appearance)-\(Self.slug(label))")
                        guard link.exists else { continue }

                        XCTAssertEqual(
                            frame.minX, edge.minX, accuracy: 1,
                            "'\(label)' \(place) starts its frame at \(frame.minX), where "
                                + "'\(Copy.showWhere)' starts at \(edge.minX)"
                        )
                        XCTAssertLessThanOrEqual(
                            frame.maxX, edge.maxX + 1,
                            "'\(label)' \(place) is wider than the column: it ends at "
                                + "\(frame.maxX), where the column ends at \(edge.maxX)"
                        )

                        let starts = Self.lineStarts(of: link)
                        if largest {
                            XCTAssertGreaterThanOrEqual(
                                starts.count, 2,
                                "'\(label)' \(place) drew \(starts.count) line(s), so this case does "
                                    + "not test a wrapped link"
                            )
                        } else {
                            XCTAssertEqual(
                                starts.count, 1,
                                "'\(label)' \(place) drew \(starts.count) lines at the default size"
                            )
                        }
                        for (index, start) in starts.enumerated() {
                            XCTAssertEqual(
                                start, edge.minX, accuracy: Self.inkTolerance,
                                "line \(index + 1) of '\(label)' \(place) starts its ink at \(start) pt, "
                                    + "where the column's edge is \(edge.minX) pt (all line starts: \(starts))"
                            )
                        }
                    }
                }
                app.terminate()
            }
        }
    }

    /// How far a line's first ink may sit from the column's edge, in points: a bold glyph's left
    /// side bearing at AX5. A line centered under a longer one starts tens of points in.
    private static let inkTolerance: CGFloat = 4

    /// Answers the system's location alert, when one is up, the way XCTest's default interruption
    /// handler does: with its last button, "Don’t Allow".
    ///
    /// On a fresh install the profile's first launch drew the alert over the column even with
    /// `CYPRESS_LOCATION` pinned (seen on 2026-11-16). The default handler answers it only at the
    /// next interaction with the app, and a screen that needs no scroll has none before the
    /// screenshot, so the alert stood over the links being measured.
    private static func dismissTheLocationAlert() {
        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        guard alert.waitForExistence(timeout: 3) else { return }
        alert.buttons.allElementsBoundByIndex.last?.tap()
        _ = alert.waitForNonExistence(timeout: 5)
    }

    /// Whether the screen's ground is dark: the mean brightness of the pixel row at the middle of
    /// the screen's height, which on this profile is the page's own background behind text.
    private static func isDrawnDark(_ app: XCUIApplication) -> Bool {
        guard let image = app.screenshot().image.cgImage else { return false }
        let width = image.width
        var row = [UInt8](repeating: 0, count: width * 4)
        guard let context = CGContext(
            data: &row, width: width, height: 1, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        context.draw(image, in: CGRect(x: 0, y: -image.height / 2, width: width, height: image.height))
        var total = 0
        for x in 0..<width {
            total += Int(row[x * 4]) + Int(row[x * 4 + 1]) + Int(row[x * 4 + 2])
        }
        return total / (width * 3) < 128
    }

    /// Where each line of text in `element` starts its ink, in screen points.
    ///
    /// The background is the color most of the element's top row carries. A pixel is ink when one
    /// of its channels differs from the background by more than a quarter of the range, which the
    /// link color does in light and in dark. Rows with ink are grouped into lines wherever a row
    /// with no ink separates them.
    private static func lineStarts(of element: XCUIElement) -> [CGFloat] {
        let frame = element.frame
        guard let image = element.screenshot().image.cgImage, frame.width > 0 else { return [] }
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return [] }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        func pixel(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            let offset = (y * width + x) * 4
            return (Int(pixels[offset]), Int(pixels[offset + 1]), Int(pixels[offset + 2]))
        }
        var counts: [Int: Int] = [:]
        for x in 0..<width {
            let (r, g, b) = pixel(x, 0)
            counts[(r << 16) | (g << 8) | b, default: 0] += 1
        }
        guard let key = counts.max(by: { $0.value < $1.value })?.key else { return [] }
        let background = (key >> 16, (key >> 8) & 0xFF, key & 0xFF)
        func isInk(_ x: Int, _ y: Int) -> Bool {
            let (r, g, b) = pixel(x, y)
            return max(abs(r - background.0), abs(g - background.1), abs(b - background.2)) > 64
        }

        let scale = CGFloat(width) / frame.width
        var starts: [CGFloat] = []
        var lineStart: Int?
        for y in 0..<height {
            let first = (0..<width).first { isInk($0, y) }
            if let first {
                lineStart = min(lineStart ?? first, first)
            } else if let start = lineStart {
                starts.append(frame.minX + CGFloat(start) / scale)
                lineStart = nil
            }
        }
        if let start = lineStart { starts.append(frame.minX + CGFloat(start) / scale) }
        return starts
    }

    /// Scrolls until the whole of `element` is on screen, since its screenshot is read pixel by
    /// pixel. A short drag at a time, so a link is not carried past the top of the screen.
    private func scrollWhollyOnScreen(_ element: XCUIElement, in app: XCUIApplication) {
        let screen = app.frame
        let safe = screen.insetBy(dx: 0, dy: screen.height * 0.12)
        for _ in 0..<20 {
            guard element.exists else {
                app.swipeUp()
                continue
            }
            let frame = element.frame
            if safe.contains(frame) { return }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let step = frame.midY > safe.midY ? -screen.height * 0.25 : screen.height * 0.25
            deliberateDrag(from: start, to: start.withOffset(CGVector(dx: 0, dy: step)))
        }
    }

    private static func slug(_ label: String) -> String {
        label.lowercased().split(separator: " ").joined(separator: "-")
    }

    /// A PNG of the screen, kept on the result bundle and written to `CYPRESS_SHOT_DIR` when the run
    /// sets it: `OthersTreeUITests.record`.
    private func recordScreen(named name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let directory = ProcessInfo.processInfo.environment["CYPRESS_SHOT_DIR"] ?? NSTemporaryDirectory()
        let url = URL(fileURLWithPath: directory).appendingPathComponent("links-\(name).png")
        try? shot.pngRepresentation.write(to: url)
        print("CYPRESS-SHOT: \(url.path)")
    }

    /// `othersTreeSharing` and `withdrawTreeBuiltOn` sign in as the sharing account. `othersTree`
    /// signs out again, the way
    /// `OthersTreeUITests.signTheSharerOutAfterwards` does, so no later test inherits the account.
    private func signTheSharerOutAfterwards() {
        addTeardownBlock {
            let reset = XCUIApplication()
            reset.launchEnvironment[Self.deepLinkScreenKey] = "othersTree"
            DebugMapCamera.pin(reset)
            reset.launch()
            _ = reset.staticTexts["Added"].waitForExistence(timeout: 60)
            reset.terminate()
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
            (Copy.withdrawTree, app.staticTexts[Copy.withdrawTreeTitle]),
        ]
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if let hit = outcomes.first(where: { $0.1.exists }) { return hit.0 }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return nil
    }

    /// Back to the profile after `link` opened, with the column reachable again. `Withdraw this
    /// tree` opens an alert, and `Keep it` leaves it without withdrawing.
    private func returnToProfile(from link: String, in app: XCUIApplication) {
        switch link {
        case Copy.claimSpecies:
            let skip = app.buttons[Copy.speciesPickSkip]
            assertReachable(skip, "the species picker's '\(Copy.speciesPickSkip)'")
            skip.tap()
        case Copy.withdrawTree:
            let keep = app.buttons[Copy.withdrawTreeKeep]
            assertReachable(keep, "the withdraw alert's '\(Copy.withdrawTreeKeep)'")
            keep.tap()
            XCTAssertTrue(app.staticTexts[Copy.withdrawTreeTitle].waitForNonExistence(timeout: 10),
                          "'\(Copy.withdrawTreeKeep)' left the withdraw alert up")
        default:
            let back = app.buttons[Copy.back]
            assertReachable(back, "the Back control after '\(link)'")
            back.tap()
        }
        assertReachable(app.buttons[Self.column[0]], "'\(Self.column[0])' back on the profile")
    }
}
