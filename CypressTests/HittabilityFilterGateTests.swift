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

    /// The words that make a line a *filter* rather than a claim.
    ///
    /// Matched on the line the property is read on, deliberately: a real parser would be a parser
    /// with its own bugs standing between a red gate and a fix, and `DragGestureGateTests` already
    /// records why this suite prefers a blunt instrument it can calibrate. The blind spot is
    /// written down rather than papered over — a filter split across two lines, so that the keyword
    /// and the read are not on the same one, passes this gate. Two of those exist in the suite and
    /// are guarded by nothing but review (`DeepLinkHarness.waitForCoverToArrive`'s `return`, and
    /// `PrimaryCTAReachabilityTests.buttonLabels`' `.map`), which is why both now call the helper.
    static let filterWords = ["guard", "filter", "where", "contains", "first(", "while"]

    /// Line numbers (1-based) at which `code` reads the raw property in a filter position.
    ///
    /// A free function of a string so the scanner can be run against a case whose answer is already
    /// known, which is the only thing separating this measurement from a coincidence.
    static func filterPositionReads(in code: String) -> [Int] {
        var found: [Int] = []
        for (index, line) in code.split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated() where filterWords.contains(where: { line.contains($0) }) {
            guard readsRawProperty(String(line)) else { continue }
            found.append(index + 1)
        }
        return found
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
        """
        #expect(
            Self.filterPositionReads(in: mustCatch) == Array(1...6),
            """
            the scanner missed a filter-position read it must catch: it found \
            \(Self.filterPositionReads(in: mustCatch)) where every one of those six lines is a \
            spelling this suite has actually contained
            """
        )

        let mustNotCatch = """
        XCTAssertTrue(delete.isHittable, "the delete is in the tree and nothing could press it")
        XCTAssertFalse(tab.isHittable, "a tab behind a modal cover must stay unreachable")
        guard element.exists, element.isHittableWithoutRaising else { continue }
        for _ in 0..<6 where !element.isHittableWithoutRaising { swipeRow(app, left: true) }
        guard control.exists, control.isReachable else { return }
        """
        #expect(
            Self.filterPositionReads(in: mustNotCatch).isEmpty,
            """
            the scanner flagged a line it must leave alone: \
            \(Self.filterPositionReads(in: mustNotCatch)). An assertion is a claim, not a filter, \
            and `isHittableWithoutRaising` is the fix rather than the defect — a gate that cannot \
            be satisfied is not a gate
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
            helperSource?.code.contains("var \(Self.helper): Bool") == true,
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
