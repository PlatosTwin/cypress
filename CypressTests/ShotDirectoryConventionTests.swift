//
//  ShotDirectoryConventionTests.swift
//  CypressTests
//
//  **The screenshot directory has one key and one channel, and this is the copy that fails.**
//
//  Four suites write PNGs to a directory an operator chooses — `ScreenSweepShots` and
//  `DynamicTypeScreenshotTests` here, `AreaPickerUITests` and `AlmanacGroupTapTests` in
//  `CypressUITests`. All four read the key out of the environment of the process they run in, and
//  the operator puts it there by exporting the same name with `xcodebuild`'s `TEST_RUNNER_` prefix
//  before `Tools/run_tests.sh`. Two facts hold that arrangement together and neither has ever been
//  checked:
//
//   1. the four writers read the SAME key — a rename in one of them makes that one silently write
//      to a temporary directory while the other three obey;
//   2. the name the prose tells an operator to export is the prefix followed by exactly that key —
//      one character out and the forwarding delivers a variable nobody reads, which fails by doing
//      nothing at all.
//
//  Both failures are silent, and the round that produced this file is a receipt for what silent
//  costs: the UI-test files instructed a spelling that reached no process, the tests passed, and
//  the shots went to a directory inside the simulator container for weeks.
//
//  ── What this guard deliberately does NOT do ──────────────────────────────────────────────────
//  It does not police the prose that says HOW to set the variable. The defect it comes from was a
//  doc comment prescribing an `xcodebuild` argument instead of an exported shell variable, and the
//  obvious gate — refuse a line mentioning the variable and the words "command line" — would be a
//  gate on phrasing: rewrite the same false instruction as "pass it to xcodebuild" and the gate
//  goes green on the defect, which is the worst shape a guard has here. The argument itself lives
//  in `Tools/run_tests.sh`'s header, in one place, with the both-ways evidence, and every other
//  file points at it rather than restating it.
//
//  That leaves the originating defect with no regression guard, and #152's review proved it by
//  planting a reworded false instruction and watching all three tests below pass. The decision is
//  deliberate; the residual risk is filed in `docs/ROADMAP.md` — backlog item 7, gaps (a) and (b),
//  (b) being that this sweep does not read `docs/` — so a later round meets it there rather than
//  only by opening this file.
//

import Foundation
import Testing

@Suite("The screenshot directory has one name and one channel")
struct ShotDirectoryConventionTests {

    /// The key every shot writer reads out of its own process's environment.
    static let runnerKey = "CYPRESS_SHOT_DIR"

    /// What `xcodebuild` strips. A variable carrying this prefix in `xcodebuild`'s **environment**
    /// arrives in the test runner's environment with the prefix gone; the runner is the app under
    /// test for `CypressTests` and the XCTRunner app for `CypressUITests`.
    ///
    /// Kept apart from `runnerKey` rather than written out joined, so this file does not contain
    /// the token it sweeps for and cannot match itself.
    static let forwardingPrefix = "TEST_RUNNER_"

    /// The four files that write shots, relative to the worktree root.
    static let writers = [
        "CypressTests/ScreenSweepShots.swift",
        "CypressTests/DynamicTypeScreenshotTests.swift",
        "CypressUITests/AreaPickerUITests.swift",
        "CypressUITests/AlmanacGroupTapTests.swift"
    ]

    /// The operator-facing statement of the convention. Every doc comment in `writers` points here.
    static let harness = "Tools/run_tests.sh"

    // MARK: - Reading the tree

    private static func source(_ relative: String) throws -> String {
        let url = AppSourceLiterals.repositoryRoot().appendingPathComponent(relative)
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Every `.swift` file in the three targets, plus the harness script — the whole surface on
    /// which the exported name can be written down.
    private static func filesThatCanStateTheConvention() -> [String] {
        let root = AppSourceLiterals.repositoryRoot()
        var found: [String] = []
        for target in ["Cypress", "CypressTests", "CypressUITests"] {
            let directory = root.appendingPathComponent(target).resolvingSymlinksInPath()
            guard let walker = FileManager.default.enumerator(
                at: directory, includingPropertiesForKeys: nil
            ) else { continue }
            found += walker.compactMap { $0 as? URL }
                .map { $0.resolvingSymlinksInPath() }
                .filter { $0.pathExtension == "swift" }
                .map { $0.path.replacingOccurrences(of: root.path + "/", with: "") }
        }
        return (found + [harness]).sorted()
    }

    private static func matches(_ pattern: String, in text: String, group: Int) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let whole = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: whole).compactMap { match in
            Range(match.range(at: group), in: text).map { String(text[$0]) }
        }
    }

    /// Keys read out of `ProcessInfo.processInfo.environment` whose name mentions a shot.
    ///
    /// Matched on `SHOT` rather than on the expected key, on purpose: a guard that looked for
    /// `CYPRESS_SHOT_DIR` could only ever find `CYPRESS_SHOT_DIR`, and would report a file that had
    /// been renamed to `CYPRESS_SHOTS_DIR` as having no shot key at all — which reads as "not a
    /// writer" rather than as the rename it is.
    private static func shotKeysRead(in source: String) -> [String] {
        matches(#"environment\["([A-Z0-9_]*SHOT[A-Z0-9_]*)"\]"#, in: source, group: 1)
    }

    /// Names written down as the thing to export. Requires at least one character after the
    /// prefix, so the bare `TEST_RUNNER_` that three doc comments use when discussing the prefix
    /// itself is prose and is not read as a name.
    private static func forwardedNames(in source: String) -> [String] {
        matches("(\(forwardingPrefix)[A-Z0-9_]+)", in: source, group: 1)
    }

    // MARK: - The gate

    @Test("every shot writer reads the same key")
    func theWritersAgreeOnTheKey() throws {
        for path in Self.writers {
            let keys = try Self.shotKeysRead(in: Self.source(path))
            #expect(
                keys == [Self.runnerKey],
                """
                \(path) reads \(keys.isEmpty ? "no shot key at all" : keys.description) out of its \
                environment, not exactly [\(Self.runnerKey)]. All four shot writers have to read \
                one key: an operator exports one name, and a writer reading a different one falls \
                back to a temporary directory without saying so.
                """
            )
        }
    }

    @Test("every exported name this repository writes down is the prefix plus that key")
    func theDocumentedNameIsTheForwardedKey() throws {
        let expected = Self.forwardingPrefix + Self.runnerKey
        var wrong: [String] = []
        for path in Self.filesThatCanStateTheConvention() {
            for name in try Self.forwardedNames(in: Self.source(path)) where name != expected {
                wrong.append("\(path): \(name)")
            }
        }
        #expect(
            wrong.isEmpty,
            """
            \(wrong.count) place(s) tell an operator to export a name that is not \(expected), so \
            the forwarding would deliver a variable nothing reads — a failure that looks exactly \
            like not setting it at all:
            \(wrong.joined(separator: "\n"))
            """
        )
    }

    // MARK: - The guard's own provenance: it must not pass by reading nothing

    /// This project's signature failure is a green result from a check that ran on nothing, and
    /// both gates above are "no counterexample found" — the shape that passes hardest on an empty
    /// sweep. So, in order: the sweep has to have seen a plausible amount of the tree, it has to
    /// have seen **by name** every file this test then reads directly, and each of those files has
    /// to be carrying the convention. The middle step is the one that makes the third mean
    /// anything — without it the reads below go around the sweep and certify only themselves.
    @Test("the guard read the files it claims to have checked")
    func theGuardCanSeeTheSource() throws {
        let swept = Self.filesThatCanStateTheConvention()
        #expect(
            swept.count >= AppSourceLiterals.swiftFileCountFloor,
            """
            the sweep found \(swept.count) files across three targets and the harness, which is \
            below the app target's own floor of \(AppSourceLiterals.swiftFileCountFloor) — it is \
            reading the wrong root, so both gates above proved nothing
            """
        )

        // A count cannot stand in for membership. The real sweep is ~507 files against a floor of
        // 220, so losing an entire target to one character of path drift (`CypressUiTests`) still
        // clears the floor by more than twice over, and the loop below reads each file through
        // `source(_:)` — a direct path read that never consults `swept` at all. So the loop below
        // proved nothing about the sweep, and the sweep is what gate 2 runs on. Assert membership.
        let missing = Set(Self.writers + [Self.harness]).subtracting(swept)
        #expect(
            missing.isEmpty,
            """
            the sweep reached \(swept.count) files but not \
            \(missing.sorted().joined(separator: ", ")) — gate 2 therefore proved nothing about \
            \(missing.count) of the files that most need it, whatever the checks below say about \
            the same paths read directly
            """
        )

        for path in Self.writers + [Self.harness] {
            let names = try Self.forwardedNames(in: Self.source(path))
            #expect(
                !names.isEmpty,
                """
                \(path) does not name the variable to export anywhere. Either the sweep is not \
                reading this file — in which case the gates above are checking less than they say \
                — or the file stopped telling a reader how to choose a directory.
                """
            )
        }
    }
}
