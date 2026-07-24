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
/// 2. Nothing interactive on it is unlabelled — the E103 failure mode.
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
    /// The last of the three structural questions. E116 and E117 asked whether elements are *labelled*;
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

        for caption in ["DBH", "Site", "City record", "Watch for"] {
            let joined = app.staticTexts
                .matching(NSPredicate(format: "label BEGINSWITH %@", "\(caption), "))
                .firstMatch
            XCTAssertTrue(
                joined.exists,
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
    /// because that is the shape the defect actually takes — a labelled wrapper around a labelled leaf.
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

        assertEveryControlIsLabelled(app, screen: screen, file: file, line: line)

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
            XCTAssertTrue(
                back.exists,
                "\(screen): there is no Back control in the accessibility tree, so this screen cannot "
                    + "be left without a swipe gesture an assistive technology may not perform",
                file: file, line: line
            )
            XCTAssertTrue(
                back.isHittable,
                "\(screen): Back is in the tree but cannot be activated",
                file: file, line: line
            )
        }

        app.terminate()
    }

    /// No interactive element anywhere in the tree may be unlabelled.
    ///
    /// Scoped to what is *hittable*, for the same reason E116's version is: an element behind a cover
    /// or scrolled off the bottom is in the hierarchy without being reachable, and holding it to the
    /// same standard would report failures a user cannot encounter.
    private func assertEveryControlIsLabelled(
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
