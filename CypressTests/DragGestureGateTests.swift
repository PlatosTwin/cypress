import Foundation
import Testing

/// **One spelling of a synthesized drag, enforced from the unit suite.**
///
/// #200 was a real diagnosis: `press(forDuration: 0.05, thenDragTo:)` at the default velocity gives
/// a gesture recognizer almost no intermediate touch events, and a loaded three-core CI runner
/// delivers fewer still, so the drag is not read as a drag at all. The fix — a quarter-second
/// settle, half the default velocity, a brief hold before release — went into `SheetExitUITests`.
///
/// It stopped there. `MapPanTabSwitchUITests` kept `press(forDuration: 0.1, thenDragTo:)` two files
/// away, and in run **30884912660** `testADeliberatePanSurvivesLeavingForJournalAndBack` failed on
/// its own precondition: *"panning the map did not move the camera off the reader"*. The same
/// defect, a different test's name, five days later — and it read as a new mystery rather than a
/// known one, because nothing connected the two call sites.
///
/// **The fix for that is not a third careful edit.** It is making the careless spelling
/// unrepresentable: every synthesized drag goes through `XCTestCase.deliberateDrag(from:to:)`, and
/// this gate fails the build if a second one appears. That is the rule ROADMAP states as *fix the
/// representation, not the instance*, applied to a test helper.
///
/// Checked from the unit suite because it runs on every build and on every shard — a gate that only
/// ran inside the UI suite could be skipped by the very sharding it protects.
@Suite("Every synthesized drag goes through one helper")
struct DragGestureGateTests {

    /// The file allowed to contain the gesture: the helper's own definition.
    static let helperFile = "UIWait.swift"

    /// The call this gate exists to keep to one site. Matched as a substring rather than a regex:
    /// the API's label is stable, and a regex here would be a second thing to get wrong.
    static let gesture = "thenDragTo:"

    /// Every `.swift` file under `CypressUITests/`, as (name, code) — **with comments removed**.
    ///
    /// The stripping is not incidental. Both files that used to spell this gesture now describe
    /// having done so, by name, in the doc comment explaining why they no longer do; a gate reading
    /// raw text would fail on the very comments that record the fix, and the obvious way out —
    /// rewording the history until the gate is quiet — would delete the explanation to satisfy the
    /// check. So prose may say `thenDragTo:` as often as it likes, and code may not.
    ///
    /// Line comments only. This codebase does not use `/* */`, and a gate that tried to parse
    /// Swift properly would be a parser with its own bugs standing between a red test and a fix.
    /// If a block comment ever hides a call here, the failure mode is a gate that passes when it
    /// should fail — recorded rather than papered over.
    static func uiTestSources(root: URL) throws -> [(name: String, code: String)] {
        let directory = root.appendingPathComponent("CypressUITests")
        return try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { url in
                let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                let code = text
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .map { line -> Substring in
                        guard let comment = line.range(of: "//") else { return line }
                        return line[line.startIndex..<comment.lowerBound]
                    }
                    .joined(separator: "\n")
                return (url.lastPathComponent, code)
            }
    }

    @Test("no UI test spells its own drag gesture")
    func onlyTheHelperSpellsTheGesture() throws {
        let root = AppSourceLiterals.repositoryRoot()
        let sources = try Self.uiTestSources(root: root)

        // The scanner's own control. An empty read would satisfy every check below vacuously,
        // which is the failure shape ARCHITECTURE §7 records and #93 shipped once already.
        #expect(
            sources.count >= 10,
            """
            found only \(sources.count) Swift files under CypressUITests/ — the scanner is not \
            reading the source, so this gate passes without checking anything
            """
        )

        // The helper must still contain the gesture. Without this the gate would go green if
        // `deliberateDrag` were gutted, which is the opposite of what it is for.
        let helper = sources.first { $0.name == Self.helperFile }
        #expect(
            helper?.code.contains(Self.gesture) == true,
            """
            \(Self.helperFile) no longer contains `\(Self.gesture)`. Either the helper was \
            removed — in which case every drag in the suite is now unguarded — or it moved, and \
            this gate needs to be told where to.
            """
        )

        let offenders = sources
            .filter { $0.name != Self.helperFile && $0.code.contains(Self.gesture) }
            .map(\.name)
        #expect(
            offenders.isEmpty,
            """
            \(offenders.joined(separator: ", ")) spell(s) a drag gesture directly instead of \
            calling `deliberateDrag(from:to:)`. A hand-rolled `press(forDuration:thenDragTo:)` is \
            how #200 came back as a different test's failure in run 30884912660: the durations \
            drift apart, one site gets fixed, and the other fails months later looking like a new \
            defect. Use the helper — and if this gesture genuinely needs different numbers, give \
            the helper a parameter and say why there, where the next reader will find it.
            """
        )
    }
}
