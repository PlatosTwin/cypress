import Foundation
import Testing

/// **One spelling of "is this element worth examining", enforced from the unit suite.**
///
/// `XCUIElement.isHittable` does not answer `false` for an element XCUITest cannot compute an
/// activation point for. It **raises**:
///
///     Failed to determine hittability of StaticText at {{inf, inf}, {0.0, 0.0}}:
///     Activation point invalid and no suggested hit points based on element frame
///
/// and the raise is the test failure — a sentence about nothing, attached to whichever test
/// happened to be walking the tree when a background map annotation landed in that state.
///
/// **The reason this is a gate and not three careful edits.** `AccessibilityTreeTests
/// .testNoUnlabeledButtonsOnLaunch` found this on task #121's branch and fixed it *at that one call
/// site*, with a hand-rolled frame check and a comment explaining the whole mechanism. It then came
/// back twice under other tests' names, months apart, each time reading as a new mystery:
/// `DeepLinkVoiceOverTests.testPinAdjust` (the run task #71 was written from, addressed there at the
/// harness level and not at the test level) and `DeepLinkSweepTests.testNothingIsAnnouncedTwice`
/// (CI run 31300530216, shard `ui (3)`). That is `DragGestureGateTests`' story exactly, with a
/// property in place of a gesture, and it gets the same answer: `XCUIElement
/// .isHittableWithoutRaising` in `UIWait.swift` is the suite's only filter-position spelling, and
/// this fails the build if a second one appears.
///
/// **Filter positions only, and the distinction is the whole design.** A test that *asserts*
/// reachability — `XCTAssertTrue(delete.isHittable, "…")` — is making a claim, and the raw property
/// is the right thing to say there: nothing is being skipped, and the assertion's own message is
/// what a reader wants. A test that uses the property to decide whether an element is looked at at
/// all is asking a question it must get an answer to rather than an exception.
///
/// Checked from the unit suite for `DragGestureGateTests`' reason: it runs on every build and every
/// shard, where a gate living inside the UI suite could be skipped by the very sharding it protects.
@Suite("Every filter-position hittability read goes through one helper")
struct HittabilityFilterGateTests {

    /// The file allowed to read the raw property in a filter position: the helper's own definition.
    static let helperFile = "UIWait.swift"

    /// The helper every other file must call instead.
    static let helper = "isHittableWithoutRaising"

    /// Swift keywords that make a line a *filter* rather than a claim, matched as whole words.
    ///
    /// **Whole words, not substrings.** `delete.isHittable` contains `let`, `notify` contains `if`,
    /// and `identifier` contains both — a substring test would flag ordinary assertions and the
    /// gate would be unsatisfiable. A word counts only when neither neighbouring character can
    /// continue an identifier.
    ///
    /// The first version of this list held six entries and no `if`, which meant the most ordinary
    /// filter spelling in Swift — `if x.isHittable { … }` — passed while the same line written as
    /// `guard` failed. That was red-proved on PR #66 with a probe and a control at one insertion
    /// point, and it is the reason the list is now long enough to be boring.
    static let filterKeywords = [
        "guard", "if", "else", "while", "for", "where", "switch", "case", "return", "let", "var"
    ]

    /// Method calls that make a line a filter, matched as a call — the leading `.` is part of each
    /// one, so a local named `map` or a label containing the word `contains` is not a match.
    static let filterCalls = [
        ".filter", ".map", ".compactMap", ".flatMap", ".reduce", ".allSatisfy", ".contains",
        ".first(", ".firstIndex", ".drop", ".prefix", ".sorted", ".min(", ".max(", ".partition"
    ]

    /// **What this gate can and cannot see, stated as what it is.**
    ///
    /// It sees a read only when one of the words above appears on the *same line*, in the part of
    /// that line which is code rather than prose. A real parser would be a parser with its own bugs
    /// standing between a red gate and a fix, and `DragGestureGateTests` already records why this
    /// suite prefers a blunt instrument it can calibrate. Two holes follow from that, and they are
    /// written here rather than papered over:
    ///
    /// - **A boolean composition on a continuation line of a multi-line assertion.**
    ///   `PrimaryCTAReachabilityTests` has one: `control.exists && control.isHittable,` sitting on
    ///   its own line inside an `XCTAssertTrue(`. That line carries no keyword and no call, and
    ///   `&&` is deliberately *not* in the vocabulary, because on one line it cannot be told apart
    ///   from the same operator inside an assertion — which this suite allows on purpose. A `&&`
    ///   composition that is a genuine filter is caught by whatever introduces it (`let`, `return`,
    ///   `guard`, `if`); one written as a bare continuation line is not.
    /// - **A filter split so that the keyword and the read land on different lines.** No instance
    ///   exists in the suite today; the two that were once cited here as examples
    ///   (`DeepLinkHarness.waitForCoverToArrive`'s `return … && title.isHittable` and
    ///   `PrimaryCTAReachabilityTests.buttonLabels`' `.map`) were *single-line* reads missed for
    ///   the other reason — the vocabulary was too short — and both are now matched by `return`
    ///   and `.map`. Recording them as the split-line hole was worse than recording no hole at
    ///   all, because it told a reader that keeping a filter on one line made it visible here.
    static func filterPositionReads(in code: String) -> [Int] {
        var found: [Int] = []
        for (index, line) in code.split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated() {
            let source = codeOutsideStringLiterals(in: String(line))
            guard filterKeywords.contains(where: { containsWord($0, in: source) })
                || filterCalls.contains(where: { source.contains($0) }) else { continue }
            guard readsRawProperty(source) else { continue }
            found.append(index + 1)
        }
        return found
    }

    /// `line` with the prose of its string literals removed and their **interpolations kept**.
    ///
    /// Both halves are load-bearing, and each was chosen against a line in the suite:
    ///
    /// - Dropping the prose is what lets `XCTAssertTrue(row.isHittable, "the row **for** the
    ///   photograph nobody owns could not be reached")` stay legal. `for` is a filter keyword and
    ///   an ordinary English word, and `AnonymizedPhotoNoticeUITests` writes both on one line.
    /// - Keeping the interpolations is what lets `PrimaryCTAReachabilityTests.buttonLabels`'
    ///   `.map { "…\\($0.isHittable ? …)" }` be seen at all: the read there lives *inside* the
    ///   message it builds. A version that dropped whole literals would have called that line
    ///   clean, which is the shape of blind spot this file exists to not have.
    ///
    /// Nested quotes inside an interpolation are not tracked — inside `\\(…)` this counts
    /// parentheses only, and every such expression written so far has balanced ones.
    static func codeOutsideStringLiterals(in line: String) -> String {
        var out = ""
        var inString = false
        var escaped = false
        var interpolation = 0
        for character in line {
            if interpolation > 0 {
                if character == "(" { interpolation += 1 }
                if character == ")" {
                    interpolation -= 1
                    if interpolation == 0 { continue }
                }
                out.append(character)
                continue
            }
            if inString {
                if escaped {
                    escaped = false
                    if character == "(" { interpolation = 1 }
                    continue
                }
                if character == "\\" { escaped = true; continue }
                if character == "\"" { inString = false }
                continue
            }
            if character == "\"" { inString = true; continue }
            out.append(character)
        }
        return out
    }

    /// Whether `word` appears in `source` with no identifier character on either side of it.
    static func containsWord(_ word: String, in source: String) -> Bool {
        var searched = source[...]
        while let range = searched.range(of: word) {
            let continues: (Character) -> Bool = { $0.isLetter || $0.isNumber || $0 == "_" }
            let before = range.lowerBound == searched.startIndex
                ? nil
                : searched[searched.index(before: range.lowerBound)]
            let after = range.upperBound == searched.endIndex ? nil : searched[range.upperBound]
            if !(before.map(continues) ?? false) && !(after.map(continues) ?? false) { return true }
            searched = searched[range.upperBound...]
        }
        return false
    }

    /// Whether `line` reads `isHittable` itself, rather than a longer identifier starting with it.
    ///
    /// **`line.contains("isHittable")` is true of `isHittableWithoutRaising`**, so a substring test
    /// would report every fixed call site as an offender and the gate would be unfixable. The read
    /// counts only when the next character cannot continue an identifier.
    static func readsRawProperty(_ line: String) -> Bool {
        var searched = line[...]
        while let range = searched.range(of: "isHittable") {
            let next = range.upperBound
            let continues = next < searched.endIndex
                && (searched[next].isLetter || searched[next].isNumber || searched[next] == "_")
            if !continues { return true }
            searched = searched[next...]
        }
        return false
    }

    // MARK: - The scanner, run against cases whose answers are already known

    /// **The calibration.** A gate that reported nothing would look identical to a clean suite, and
    /// this suite has filed a defect for exactly that shape. Both directions are checked: the
    /// spellings that must be caught, and the ones that must not.
    @Test("the scanner catches a filter-position read and leaves assertions alone")
    func scannerIsCalibrated() {
        let mustCatch = """
        guard element.exists, element.isHittable else { continue }
        let texts = app.staticTexts.allElementsBoundByIndex.filter { $0.isHittable }
        for _ in 0..<6 where !element.isHittable { swipeRow(app, left: true) }
        while !row.isHittable && swipes < 4 { app.swipeUp() }
        .first(where: { $0.exists && $0.isHittable })
        notices.allElementsBoundByAccessibilityElement.contains { $0.isHittable }
        if app.buttons.firstMatch.isHittable { _ = app.buttons.firstMatch.label }
        let ok = app.buttons.allElementsBoundByIndex.allSatisfy { $0.isHittable }
        let flags = app.buttons.allElementsBoundByIndex.map { $0.isHittable }
        let n = list.reduce(0) { $0 + ($1.isHittable ? 1 : 0) }
        for e in list { if e.isHittable { count += 1 } }
        switch (element.isHittable, element.exists) { case (true, true): break }
        return title.exists && title.isHittable
        .map { "“\\($0.label)”\\($0.isHittable ? "" : " (not hittable)")" }
        """
        #expect(
            Self.filterPositionReads(in: mustCatch) == Array(1...14),
            """
            the scanner missed a filter-position read it must catch: it found \
            \(Self.filterPositionReads(in: mustCatch)) where every one of those fourteen lines is \
            a spelling this suite has contained or a reviewer has red-proved against it (PR #66, \
            lines 7 to 14)
            """
        )

        let mustNotCatch = """
        XCTAssertTrue(delete.isHittable, "the delete is in the tree and nothing could press it")
        XCTAssertFalse(tab.isHittable, "a tab behind a modal cover must stay unreachable")
        guard element.exists, element.isHittableWithoutRaising(in: app) else { continue }
        for _ in 0..<6 where !element.isHittableWithoutRaising(in: app) { swipeRow(app, left: true) }
        guard control.exists, control.isReachable else { return }
        XCTAssertTrue(row.isHittable, "the row for the photograph nobody owns could not be reached")
        XCTAssertTrue(door.isHittable, "let nothing switch while the case for it is in the tree")
            cta.isHittable,
            + "`isHittable` is asked about it, if the frame is not finite"
        """
        #expect(
            Self.filterPositionReads(in: mustNotCatch).isEmpty,
            """
            the scanner flagged a line it must leave alone: \
            \(Self.filterPositionReads(in: mustNotCatch)). An assertion is a claim, not a filter, \
            and `isHittableWithoutRaising` is the fix rather than the defect — a gate that cannot \
            be satisfied is not a gate. Lines 6 to 9 are the prose cases: a filter keyword inside \
            an assertion's *message* (`for`, `let`, `switch`, `case`, `if`) is English, not code, \
            and a line that only mentions the property in a sentence is not a read of it
            """
        )
    }

    // MARK: - The suite

    @Test("no UI test reads isHittable in a filter position")
    func onlyTheHelperReadsTheRawProperty() throws {
        let root = AppSourceLiterals.repositoryRoot()
        let sources = try DragGestureGateTests.uiTestSources(root: root)

        // The scanner's own control, for `DragGestureGateTests`' reason: an empty read satisfies
        // every check below vacuously.
        #expect(
            sources.count >= 10,
            """
            found only \(sources.count) Swift files under CypressUITests/ — the scanner is not \
            reading the source, so this gate passes without checking anything
            """
        )

        // The helper must still exist. Without this the gate goes green if `isHittableWithoutRaising`
        // is deleted, which is the opposite of what it is for.
        let helperSource = sources.first { $0.name == Self.helperFile }
        #expect(
            helperSource?.code.contains("func \(Self.helper)(onScreen screen: CGRect) -> Bool") == true
                && helperSource?.code.contains("func \(Self.helper)(in app: XCUIApplication) -> Bool") == true,
            """
            \(Self.helperFile) no longer defines `\(Self.helper)`. Either the helper was removed — \
            in which case every filter position in the suite is unguarded again — or it moved, and \
            this gate needs to be told where to.
            """
        )

        let offenders = sources
            .filter { $0.name != Self.helperFile }
            .map { (name: $0.name, lines: Self.filterPositionReads(in: $0.code)) }
            .filter { !$0.lines.isEmpty }
            .map { "\($0.name) \($0.lines)" }
        #expect(
            offenders.isEmpty,
            """
            \(offenders.joined(separator: ", ")) read `isHittable` where it decides whether an \
            element is examined. `isHittable` RAISES on an element whose frame has no interior or \
            is not finite — it does not answer `false` — so a filter written that way fails the \
            test it is in, with a sentence about a map annotation nobody asked about. Call \
            `\(Self.helper)` (`UIWait.swift`). If the read is an assertion rather than a filter, \
            the raw property is correct and this gate should not see it: put the claim on its own \
            line, away from the guard or loop that led to it.
            """
        )
    }
}
