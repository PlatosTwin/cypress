//
//  MapSwipeOrderDeclarationTests.swift
//  CypressTests
//
//  The one automatable half of ERRATA E230's open question.
//
//  ── The gap this closes, and the much larger one it does not ────────────────────────────────────
//  Task #143 declared screen 01's swipe order with `accessibilitySortPriority` (E192's fix note).
//  E230 then found that `debugDescription`'s element order does not move under that modifier, so
//  nothing in `CypressUITests` verifies the mechanism. The pending erratum filed with this ticket
//  extends that measurement to every ordering API the black-box target can reach — the query
//  engine under both binding strategies, the snapshot's own `children` arrays, and
//  `.children(matching:)` walked level by level — and finds the same thing for a stronger reason:
//  every one of them reports raw view-composition order. Measured on the 16e, a purely GEOMETRIC
//  inversion (the chips drawn 125 pt above the field, composition untouched, sort priorities equal)
//  moved none of them, while a composition inversion moved all of them. An API that cannot see a
//  view move on the glass cannot see a sort priority either, and no amount of choosing between them
//  will help.
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
        // Six as of this ticket: the field, the suggestion list, the chips, the toast, the search
        // status and the legend. A floor rather than an equality, so adding a seventh stop is not
        // a test edit — but a floor that a deletion of the mechanism cannot slip under.
        #expect(
            declarations.count >= 5,
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
