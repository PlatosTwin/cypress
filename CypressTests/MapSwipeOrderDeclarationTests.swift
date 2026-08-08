//
//  MapSwipeOrderDeclarationTests.swift
//  CypressTests
//
//  The one automatable half of ERRATA E230's open question.
//
//  ── The gap this closes, and the much larger one it does not ────────────────────────────────────
//  Task #143 declared screen 01's swipe order with `accessibilitySortPriority` (E192's fix note).
//  E230 then found that `debugDescription`'s element order does not move under that modifier, so
//  nothing in `CypressUITests` verifies the mechanism. **E230's amendment**, written with this
//  test, extends that measurement to five ways of reading the automation snapshot — the query
//  engine under both binding strategies, the snapshot's own `children` arrays, and
//  `.children(matching:)` walked level by level, alongside `debugDescription` — and finds the same
//  thing for a stronger reason: all five are traversals of ONE `XCUIElementSnapshot`, and that tree
//  is raw view-composition order. Measured on the 16e, a purely GEOMETRIC inversion (the chips
//  drawn 125 pt above the field, composition untouched, sort priorities equal) moved none of them,
//  while a composition inversion moved all of them. No traversal of a tree that cannot see a view
//  move on the glass will see a sort priority either, so choosing a different traversal is not the
//  answer.
//
//  **The scope of that, stated exactly, because it is easy to over-read.** What is closed is
//  snapshot traversal. Focus-driven order — a focus engine walked with key events, or a real
//  assistive technology — is a different mechanism and is **unprobed**: the PR #54 reviewer tried
//  `typeKey(.tab)` plus a `hasFocus` sweep and got no element reporting focus at all on a simulator
//  without Full Keyboard Access, which is no counterexample and no working probe. Untried, not
//  refuted, and the place for anyone who picks this up next to start.
//
//  What is left, then, is not a behavior test. It is this: the numbers themselves, read off the
//  source, checked for the one property that makes
//  `ReadingOrderAccessibilityTests.testMapFieldPrecedesSuggestionsPrecedesFilterChipsInComposition`
//  worth running at all — that the declared priorities DESCEND in the same order the block composes
//  its children. Those two orders agreeing is the entire reason a composition-order assertion says
//  anything about the reading order a listener walks. If they ever disagree, the UI test goes on
//  passing while asserting the opposite of what the app declares, and nothing anywhere says so.
//
//  ── What this does NOT prove, stated rather than implied ────────────────────────────────────────
//  Not that VoiceOver honors the numbers. Not that the reading order on the glass is the declared
//  one. That still needs VoiceOver running on a physical phone, the standing limit E192's "The
//  debt" section already recorded and this ticket did not lift. A green here means the declaration
//  is internally consistent, and nothing more.
//
//  ── Why a source sweep is an acceptable instrument here ─────────────────────────────────────────
//  `DrawnGlyphGuardTests` (R57) and `BritishSpellingGuardTests` (R56) both read the app's own source
//  off disk through `AppSourceLiterals`, for the same reason: the property being guarded is a
//  property of the source and there is no runtime surface that exposes it. This reuses their helper
//  rather than growing a second way to find the repository.
//

import Foundation
import Testing

/// The parse, kept apart from the assertions so its own failure mode is legible.
enum MapChromePrioritySweep {

    struct Declaration {
        let line: Int
        let priority: Double
        /// The source line, for a failure message that names what moved.
        let text: String
    }

    /// The `VStack` that composes screen 01's top chrome. Matched on its own construction rather
    /// than on a line number, which a single edit anywhere above would silently invalidate.
    static let blockOpener = "VStack(alignment: .leading, spacing: MapLayout.chipRowTop) {"

    static let modifier = ".accessibilitySortPriority("

    /// Every `accessibilitySortPriority` applied to a CHILD of that `VStack`, in source order.
    ///
    /// **Indentation is the discriminator, and it is doing real work.** The block's own
    /// `.accessibilitySortPriority(2)` — the one that ranks the whole top block against the bottom
    /// chrome beside it — sits at the `VStack`'s own indentation, after its closing brace. It is a
    /// priority in a different comparison (the two overlays', not the children's), so including it
    /// would compare numbers that never compete and would fail this suite for a correct tree.
    static func declarations(in source: String) -> [Declaration] {
        let lines = source.components(separatedBy: "\n")
        guard let openerIndex = lines.firstIndex(where: { $0.contains(blockOpener) }) else {
            return []
        }
        let blockIndent = indent(of: lines[openerIndex])

        var found: [Declaration] = []
        for index in (openerIndex + 1)..<lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // The `VStack`'s own closing brace: same indentation as its opener.
            if trimmed.hasPrefix("}"), indent(of: line) == blockIndent { break }
            guard trimmed.hasPrefix(modifier), indent(of: line) > blockIndent else { continue }
            guard let open = trimmed.firstIndex(of: "("),
                  let close = trimmed.lastIndex(of: ")"),
                  trimmed.index(after: open) < close,
                  let value = Double(trimmed[trimmed.index(after: open)..<close])
            else { continue }
            found.append(Declaration(line: index + 1, priority: value, text: trimmed))
        }
        return found
    }

    /// How many times the modifier appears among the block's children **at all**, parseable or not.
    ///
    /// **This exists because `declarations(in:)` fails open, and failing open here is the worst
    /// possible direction.** That function skips any occurrence it cannot read as a bare `Double`
    /// on a line of its own — a value written as a named token, a call broken across two lines, a
    /// modifier chained onto the end of another. Every one of those is a realistic edit in this
    /// file (`MapHomeView` already spells its `VStack` spacing as `MapLayout.chipRowTop`), and a
    /// skipped declaration does not merely weaken the check: it **removes the offending number from
    /// the list being tested**, so a field priority tokenised *and* dropped below the chips' — which
    /// is precisely ERRATA E183 §3, the defect task #143 fixed — leaves the remaining five
    /// descending and the whole suite green. Measured, not reasoned about: with the field written
    /// as `.accessibilitySortPriority(MapLayout.fieldReadingPriority)` at a value of 2, this suite
    /// passed both its tests.
    ///
    /// Counting occurrences rather than lines, and anywhere in the line rather than at its start,
    /// so that a chained or doubled-up modifier is counted where `declarations(in:)` would not see
    /// it. The two numbers agreeing is the assertion; neither alone is worth anything.
    static func rawModifierCount(in source: String) -> Int {
        let lines = source.components(separatedBy: "\n")
        guard let openerIndex = lines.firstIndex(where: { $0.contains(blockOpener) }) else {
            return 0
        }
        let blockIndent = indent(of: lines[openerIndex])

        var count = 0
        for index in (openerIndex + 1)..<lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("}"), indent(of: line) == blockIndent { break }
            guard indent(of: line) > blockIndent else { continue }
            count += line.components(separatedBy: modifier).count - 1
        }
        return count
    }

    private static func indent(of line: String) -> Int {
        line.prefix(while: { $0 == " " }).count
    }

    static func mapHomeSource() throws -> String {
        let url = AppSourceLiterals.repositoryRoot()
            .appendingPathComponent("Cypress/Features/Map/MapHomeView.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }
}

@Suite("Screen 01's declared swipe order agrees with the order it composes (ERRATA E230)")
struct MapSwipeOrderDeclarationTests {

    /// This project's signature failure is a green result from a check that ran on nothing, so the
    /// sweep's ability to see its subject is asserted before anything is concluded from it.
    @Test("the sweep can see the block it claims to check")
    func theSweepFindsTheChromeBlock() throws {
        let source = try MapChromePrioritySweep.mapHomeSource()
        #expect(
            source.contains(MapChromePrioritySweep.blockOpener),
            """
            MapHomeView.swift no longer contains `\(MapChromePrioritySweep.blockOpener)`, so the \
            sweep below found nothing and would pass on an empty list. The top chrome block was \
            renamed or restructured; point this at the new one rather than deleting the check.
            """
        )
        let declarations = MapChromePrioritySweep.declarations(in: source)
        let raw = MapChromePrioritySweep.rawModifierCount(in: source)

        // **The parse must have consumed everything it saw.** `declarations(in:)` fails open, and a
        // declaration it silently drops is a declaration removed from the descending check — which
        // is green precisely when the dropped number is the offending one. See
        // `rawModifierCount(in:)` for the measurement that put this assertion here.
        #expect(
            declarations.count == raw,
            """
            the sweep parsed \(declarations.count) of the \(raw) `accessibilitySortPriority` \
            occurrences among the top chrome block's children, so \(raw - declarations.count) \
            declaration(s) were skipped and are NOT being checked for descending order. The parse \
            reads a bare `Double` on a line of its own; a value written as a named token, split \
            across two lines, or chained onto another modifier will land here. Widen the parse — \
            do not widen the floor, and do not delete this check: a skipped declaration is exactly \
            how a field priority below the chips' (ERRATA E183 §3, the defect task #143 fixed) \
            passes this suite.
            """
        )

        // Six, exactly as many as task #143 declares: the field, the suggestion list, the chips,
        // the toast, the search status and the legend. **A floor, and it is the real count rather
        // than one under it** — at `>= 5` a single declaration could vanish with nothing going red,
        // which is the hole the equality above closes from the other side. Adding a seventh stop is
        // deliberately a test edit; this file's whole purpose is that these numbers do not move
        // unnoticed.
        #expect(
            declarations.count >= 6,
            """
            the sweep found \(declarations.count) `accessibilitySortPriority` declarations among \
            the top chrome block's children; task #143's fix declares six. Either the mechanism \
            was removed — in which case screen 01's swipe order is inherited again and E192's \
            defect is back — or the indentation this sweep reads structure from has changed.
            """
        )
    }

    /// **The invariant.** Composition order and declared priority order have to agree, because the
    /// only automated assertion anyone can make about this block is a composition-order one.
    @Test("the priorities descend in the order the block composes its children")
    func prioritiesDescendInCompositionOrder() throws {
        let source = try MapChromePrioritySweep.mapHomeSource()
        let declarations = MapChromePrioritySweep.declarations(in: source)
        let priorities = declarations.map(\.priority)

        let descending = zip(priorities, priorities.dropFirst()).allSatisfy { $0 > $1 }
        #expect(
            descending,
            """
            screen 01's top chrome declares \(priorities) down the block, which is not strictly \
            descending. Higher priorities sort FIRST, so a value that rises partway down the block \
            declares a reading order that disagrees with the order the block composes — and the \
            only test anyone can write against this tree
            (`ReadingOrderAccessibilityTests.testMapFieldPrecedesSuggestionsPrecedesFilterChipsInComposition`)
            reads composition order, so it would keep passing while asserting the opposite of what \
            the app declares. That is the exact shape of ERRATA E230's finding and the reason this \
            check exists. Lines:
            \(declarations.map { "  MapHomeView.swift:\($0.line): \($0.text)" }.joined(separator: "\n"))
            """
        )
    }
}
