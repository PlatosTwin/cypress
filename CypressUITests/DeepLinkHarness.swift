import XCTest

/// The shared harness behind every deep-linked-screen test: launch a screen through the DEBUG
/// deep-link door (#36), confirm it actually arrived, and read the element tree it drew.
///
/// **Why it moved out of `DeepLinkVoiceOverTests` (#204).** That class was 35% of the entire UI
/// suite — 462.8s measured on run 30874574621, more than twice the next class — and its shard was
/// the longest CI job at 18 minutes, so it set the release gate's pace on its own. Two of its 28
/// tests accounted for 148s of that: both sweep EVERY deep-linked screen, launching the app once
/// per screen, where the other 26 examine one screen each. They are a different kind of test that
/// had grown inside a class of single-screen ones.
///
/// Splitting them into `DeepLinkSweepTests` lets the existing CLASS-level shard file balance them,
/// which is the whole reason not to reach for a per-method shard list: a list of method names is a
/// list that a rename breaks, and `UITestShardCoverageTests` can only guard what the file names.
/// A class is a thing the compiler already knows about.
///
/// **A protocol, not an extension on `XCTestCase`.** The first cut extended `XCTestCase` the way
/// `UIWait.swift` does, and the build refused it: `SheetExitUITests` and `SheetHeightUITests` have
/// their own private `launch(_:)` taking a screen name, and an internal method of the same
/// signature on the base class collides with both. That is the argument for scoping — `UIWait`'s
/// `assertReachable` is a thing any UI test may want, while launching a DEEP LINK is a thing four
/// files want, and a name as ordinary as `launch` should not be visible to the rest.
protocol DeepLinkHarness: XCTestCase {}

extension DeepLinkHarness {


    func launch(_ screen: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment[Self.deepLinkScreenKey] = screen
        app.launch()
        return app
    }

    static var deepLinkScreenKey: String { "CYPRESS_SCREEN" }

    /// The one banner that means the harness itself failed, rather than the screen.
    ///
    /// `DebugDeepLink` draws its failures instead of logging them, so that a resolution that found no
    /// record cannot masquerade as a screen that opened. Checked before anything else is reported,
    /// because "no record nearest 37.7596, -122.4269" is an answer and "'Growth' is not in the tree"
    /// is a riddle.
    func deepLinkFailure(_ app: XCUIApplication) -> String? {
        let banner = app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH %@", "DEEP LINK FAILED"))
            .firstMatch
        return banner.exists ? banner.label : nil
    }

    /// Waits for the screen and reports precisely which way it did not arrive.
    @discardableResult
    func arrive(
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
    func check(
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
    func assertEveryControlIsLabeled(
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
                  let labelRange = trimmed.range(of: "label: '")
            else { continue }
            // The label's own closing quote, not the line's last one (found live, task #221: a
            // focused `TextField` prints `label: 'Search', placeholderValue: 'Search a
            // species…', value: cypress, Keyboard Focused` — a second quoted field *after* the
            // label). Taking the line's last quote grabbed `placeholderValue`'s closing quote
            // instead and returned "Search', placeholderValue: 'Search a species…" as the label.
            //
            // The fix: the label ends at the first `'` immediately followed by `, ` (the start of
            // the next field), searched from where the label opens. A label that itself embeds a
            // quoted phrase — the cultivar name in `testTreeOrderParserReportsAnInvertedTree`'s own
            // fixture, "Indian Laurel Fig Tree 'Green Gem'" — has no `', ` *inside* it, only at its
            // true end if anything follows, so that case is unaffected. A label with nothing after
            // it on the line — most of them — has no `', ` anywhere, and falls back to the line's
            // last quote exactly as before.
            let close: String.Index
            if let boundary = trimmed.range(
                of: "', ", range: labelRange.upperBound..<trimmed.endIndex
            ) {
                close = boundary.lowerBound
            } else if let last = trimmed.lastIndex(of: "'") {
                close = last
            } else {
                continue
            }
            guard labelRange.upperBound < close else { continue }
            result.append((String(trimmed[trimmed.startIndex..<comma]),
                           String(trimmed[labelRange.upperBound..<close])))
        }
        return result
    }
}
