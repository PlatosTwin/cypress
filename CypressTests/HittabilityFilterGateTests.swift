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
/// **Filter positions, and separately claims.** A test that uses the property to decide whether an
/// element is looked at at all is asking a question it must get an answer to rather than an
/// exception; that is the first scanner below. A test that *asserts* reachability is making a
/// claim, and a claim must wait for its answer rather than read it once: that is the second
/// scanner (`oneShotClaims`), which sends a positive claim to `assertReachable`. A negative claim,
/// `XCTAssertFalse(tab.isHittable, "…")`, is neither, and the raw property stays right there.
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
    /// - **A boolean composition on a continuation line of a multi-line assertion.** A line such as
    ///   `control.exists && control.isHittable,` inside an `XCTAssertTrue(` carries no keyword and
    ///   no call, and `&&` is deliberately *not* in the vocabulary, because on one line it cannot be
    ///   told apart from the same operator inside an assertion. A `&&` composition that is a
    ///   genuine filter is caught by whatever introduces it (`let`, `return`, `guard`, `if`); one
    ///   written as a bare continuation line is not. (Inside a positive assertion, that line is
    ///   now refused by `oneShotClaims` instead.)
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

    // MARK: - One-shot claims

    /// **A positive hittability claim waits; it is never one read.**
    ///
    /// `XCTAssertTrue(pill.isHittable, "…")` asks once, at whatever instant the line runs. On a
    /// contended CI runner that instant can be before layout, before a scroll has come to rest, or
    /// while the launch animation is still drawing, and the claim then fails with a sentence that
    /// reads like an accessibility defect. Two `PhotoDeletionReachabilityTests` failures were
    /// exactly this (ROADMAP 103, #210), and a catalog of 70 CI runs from 2026-10-23 to 2026-11-14
    /// found nineteen more sites of the same shape waiting their turn. `assertReachable`
    /// (`UIWait.swift`) is the waiting spelling of the same claim.
    ///
    /// **Positive claims only.** `XCTAssertFalse(tab.isHittable)` is a different sentence: waiting
    /// for something to *stop* being hittable would let a slow runner pass it by never having drawn
    /// (`UIWait.swift` says so where `assertReachable` is defined). This scanner does not look at
    /// `XCTAssertFalse` at all.
    ///
    /// What counts as a claim: `XCTAssertTrue(` or `XCTAssert(` whose **first argument** reads the
    /// raw property, and `XCTAssertEqual(` whose first two arguments are a raw read and `true`. The
    /// argument is read across lines with parentheses counted, because most claims in the suite put
    /// their condition on the line after the call. String prose is removed first (with
    /// interpolations kept, `codeOutsideStringLiterals`), and comments are already removed by
    /// `DragGestureGateTests.uiTestSources`, so a sentence that mentions the property is not a read.
    static let claimCalls = ["XCTAssertTrue", "XCTAssert", "XCTAssertEqual"]

    /// The 1-based lines on which a positive one-shot hittability claim starts.
    static func oneShotClaims(in code: String) -> [Int] {
        assertions(in: code).compactMap { assertion in
            let arguments = assertion.arguments
            switch assertion.call {
            case "XCTAssertTrue", "XCTAssert":
                guard let first = arguments.first, readsRawProperty(first) else { return nil }
                return assertion.line
            case "XCTAssertEqual":
                guard arguments.count >= 2 else { return nil }
                let pair = [arguments[0], arguments[1]].map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                let claims = (readsRawProperty(pair[0]) && pair[1] == "true")
                    || (readsRawProperty(pair[1]) && pair[0] == "true")
                return claims ? assertion.line : nil
            default:
                return nil
            }
        }
    }

    /// Every assertion call in `code` that this gate knows by name, with its top-level arguments.
    ///
    /// `call` is one of `claimCalls` or `XCTAssertFalse` (kept so the calibration below can prove
    /// the parser reads negative claims too, which it then leaves alone). A name only counts as a
    /// whole word followed directly by `(`, so `XCTAssertTrue` is never read as `XCTAssert`.
    static func assertions(in code: String) -> [(call: String, line: Int, arguments: [String])] {
        // Prose removed per line, then the lines joined again, so an argument can span lines.
        // Lines inside a `"""` literal are dropped whole: `codeOutsideStringLiterals` reads a line
        // at a time and cannot see that it is inside one.
        var inBlock = false
        let lines = code.split(separator: "\n", omittingEmptySubsequences: false).map { raw -> String in
            let line = String(raw)
            let fences = line.components(separatedBy: "\"\"\"").count - 1
            if inBlock {
                if fences % 2 == 1 { inBlock = false }
                return ""
            }
            if fences % 2 == 1 {
                inBlock = true
                return codeOutsideStringLiterals(in: line.components(separatedBy: "\"\"\"")[0])
            }
            return codeOutsideStringLiterals(in: line)
        }
        let text = Array(lines.joined(separator: "\n"))
        let names = claimCalls + ["XCTAssertFalse"]
        let continues: (Character) -> Bool = { $0.isLetter || $0.isNumber || $0 == "_" }

        var found: [(call: String, line: Int, arguments: [String])] = []
        var line = 1
        var index = 0
        while index < text.count {
            if text[index] == "\n" { line += 1; index += 1; continue }
            guard text[index] == "X", index == 0 || !continues(text[index - 1]),
                  let name = names.first(where: { name in
                      let end = index + name.count
                      return end < text.count && String(text[index..<end]) == name && text[end] == "("
                  })
            else { index += 1; continue }

            // Arguments to the matching `)`, split at commas outside any bracket.
            var depth = 0
            var arguments: [String] = []
            var current = ""
            var cursor = index + name.count + 1
            while cursor < text.count {
                let character = text[cursor]
                if "([{".contains(character) { depth += 1 }
                if ")]}".contains(character) {
                    if depth == 0 { break }
                    depth -= 1
                }
                if character == "," && depth == 0 {
                    arguments.append(current)
                    current = ""
                } else {
                    current.append(character)
                }
                cursor += 1
            }
            arguments.append(current)
            found.append((call: name, line: line, arguments: arguments))
            // Continue just past the name, so a claim nested in another call's arguments is seen.
            index += name.count
        }
        return found
    }

    /// **The calibration for the claim scanner**, in both directions, the same house style as
    /// `scannerIsCalibrated`.
    @Test("the claim scanner catches a one-shot positive claim and leaves everything else alone")
    func claimScannerIsCalibrated() {
        let mustCatch = """
        XCTAssertTrue(pill.isHittable, "the header pill is a button nobody can press")
        XCTAssert(row.isHittable)
        XCTAssertTrue(
            door.isHittable,
            "the way onward is in the viewer's tree and nothing could press it"
        )
        XCTAssertTrue(
            control.exists && control.isHittable,
            "\\(screen): the arming control never became reachable"
        )
        XCTAssertEqual(
            revealedChip(Self.clear, app).isHittable, true,
            "with a filter set behind a shut control there is no reachable chip"
        )
        XCTAssertTrue(revealedChip(label, app).isHittable, "at AX5 the \\(label) chip cannot be pressed")
        """
        #expect(
            Self.oneShotClaims(in: mustCatch) == [1, 2, 3, 7, 11, 15],
            """
            the claim scanner found \(Self.oneShotClaims(in: mustCatch)) where lines 1, 2, 3, 7, 11 \
            and 15 each start a positive one-shot claim this suite has contained (single-line, \
            `XCTAssert`, multi-line, a composition, an `XCTAssertEqual` against `true`, and a read \
            through a call)
            """
        )

        let mustNotCatch = """
        XCTAssertFalse(tab.isHittable, "a tab behind a modal cover must stay unreachable")
        XCTAssertFalse(
            blank.isHittable,
            "an unlabeled control at \\(blank.frame) is reachable inside the filter row"
        )
        XCTAssertTrue(row.exists, "the row is drawn but its isHittable answer was never asked")
        XCTAssertTrue(element.isHittableWithoutRaising(in: app), "the helper is not the raw read")
        XCTAssertTrue(cta.isEnabled, "the CTA is drawn disabled; isHittable is a later line")
        XCTAssertTrue(wait { self.chips(app).isEmpty }, "chips at \\(chip.isHittable)")
        XCTAssertEqual(row.isHittable, false, "a negative claim spelled as an equality")
        let message = \"\"\"
            XCTAssertTrue(pill.isHittable, "inside a multi-line literal")
            \"\"\"
        assertReachable(pill, "the header pill")
        """
        #expect(
            Self.oneShotClaims(in: mustNotCatch).isEmpty,
            """
            the claim scanner flagged \(Self.oneShotClaims(in: mustNotCatch)), and every one of \
            those lines is a negative claim, a different property, the helper, a read inside a \
            message's interpolation, text inside a multi-line literal, or the waiting spelling
            """
        )
    }

    @Test("no UI test makes a positive hittability claim with a single read")
    func everyPositiveClaimWaits() throws {
        let root = AppSourceLiterals.repositoryRoot()
        let sources = try DragGestureGateTests.uiTestSources(root: root)

        // The controls: an empty read, or a parser that sees no assertions, satisfies the check
        // below vacuously. The suite has hundreds of `XCTAssertTrue` calls, and its negative
        // hittability claims (`AreaPickerUITests`, `MapFilterAccessibilityTests`) are written
        // across lines, so seeing them proves the multi-line reading works on the real files.
        #expect(sources.count >= 10, "found only \(sources.count) UI test files; the scanner is not reading the source")
        let parsed = sources.flatMap { Self.assertions(in: $0.code) }
        let positives = parsed.filter { $0.call == "XCTAssertTrue" }.count
        #expect(
            positives >= 100,
            "the parser found only \(positives) `XCTAssertTrue` calls in the UI suite, so it is not reading real code"
        )
        let negatives = parsed.filter {
            $0.call == "XCTAssertFalse" && $0.arguments.first.map(Self.readsRawProperty) == true
        }.count
        #expect(
            negatives >= 3,
            """
            the parser found only \(negatives) `XCTAssertFalse(… .isHittable …)` claims, and the \
            suite has at least three written across lines. A scanner that cannot see those cannot \
            see a multi-line positive claim either
            """
        )

        let offenders = sources
            .map { (name: $0.name, lines: Self.oneShotClaims(in: $0.code)) }
            .filter { !$0.lines.isEmpty }
            .map { "\($0.name) \($0.lines)" }
        #expect(
            offenders.isEmpty,
            """
            \(offenders.joined(separator: ", ")) assert `isHittable` is true with a single read. \
            That read happens at whatever instant the line runs, and on a contended runner the \
            element is often not laid out yet, so the claim fails with a sentence that reads like \
            an accessibility defect (ROADMAP 103). Call `assertReachable(element, "…")` \
            (`UIWait.swift`), which waits for the same claim and says which half of it failed.
            """
        )
    }
}
