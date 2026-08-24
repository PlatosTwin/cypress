//
//  ScrollOverhangGuardTests.swift
//  CypressTests
//
//  PR #119 review finding F1. Screen 13's scrolling column applied its closing space **after** the
//  frame that sizes the column to the viewport:
//
//      }
//      .frame(maxWidth: .infinity, alignment: .leading)
//      .frame(minHeight: proxy.size.height, alignment: .top)
//      .padding(.bottom, CypressSpacing.bottomFootnote)   // ← outside the sized frame
//
//  `minHeight: proxy.size.height` makes the column exactly as tall as the scroll viewport. Padding
//  applied to the *result* of that frame adds its 36pt outside it, so the scroll content becomes
//  `proxy.size.height + 36` on a screen that has nothing to scroll — a permanent overhang. The
//  screen drags up and stays up, sliding its own header under the status bar. Inside the frame, the
//  same 36pt is space the viewport has already accounted for and nothing moves.
//
//  Five sibling columns had the order right and one did not, and nothing in the suite could tell
//  the difference — the defect is invisible to every presentation test, because it is not in the
//  presentation. It is one modifier's position in a chain. That is what this file reads.
//
//  ── Why a source scan and not a rendered measurement ────────────────────────────────────────────
//  The rendered version of this check is a UI test that drags a short screen and asserts the header
//  came back — which is what found F1, and which costs a device, an install and a launch per screen
//  covered. This gate costs a file read. It cannot see a layout defect of any other shape, and does
//  not claim to: it checks one thing, that no bottom padding is applied downstream of a
//  viewport-sizing frame, on every column in the app target at once.
//
//  Reuses `AppSourceLiterals.repositoryRoot()` / `.sourceFiles(root:)` from
//  `BritishSpellingGuardTests` rather than growing a third source walk, the same way
//  `DrawnGlyphGuardTests` does.
//

import Foundation
import Testing

// MARK: - The scan

enum ViewportSizedColumn {

    /// The modifier that sizes a scrolling column to its viewport.
    ///
    /// Spelled as the substring the codebase actually writes at all eight sites. A column sized
    /// some other way — a hand-passed height, a `containerRelativeFrame` — is outside this gate,
    /// and `theGuardSeesEveryKnownSite` is what makes a change to the spelling visible rather than
    /// silently reducing the scan to nothing.
    static let sizingModifier = ".frame(minHeight: proxy.size.height"

    /// A bottom padding applied *after* the sizing frame, in the same modifier chain.
    struct Overhang {
        let path: String
        /// The line the sizing frame is on.
        let sizedAt: Int
        /// The line the padding is on.
        let paddedAt: Int
        /// The padding line as it stands in the file, so a failure names the fix without a debugger.
        let source: String
    }

    /// Every site where a column is sized to the viewport, by file and line.
    static func sizingSites(in source: String, path: String) -> [(path: String, line: Int)] {
        source.components(separatedBy: "\n").enumerated().compactMap { index, line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(sizingModifier) else { return nil }
            return (path, index + 1)
        }
    }

    /// Every bottom padding downstream of a sizing frame.
    ///
    /// **What "downstream" means here, concretely:** from the sizing frame's line, walk forward
    /// while the file is still spelling the same modifier chain — a chain continues on any line
    /// whose first non-whitespace character is `.`, and blank lines and `//` comments between
    /// modifiers do not end it (this codebase comments *inside* chains, including at the site this
    /// gate was written for). The first line that is neither ends the chain. A `.padding` naming
    /// `.bottom` seen before that is applied to the sized frame's result, which is the defect.
    ///
    /// `.padding(.horizontal, …)`, `.background(…)` and the rest are not offenses: they add no
    /// height. Only a bottom inset does, and `.padding(.bottom, …)` is how this codebase spells
    /// one — checked against every `padding` call under `Cypress/Features/` before the rule was
    /// written this narrowly.
    static func overhangs(in source: String, path: String) -> [Overhang] {
        let lines = source.components(separatedBy: "\n")
        var found: [Overhang] = []

        for (index, line) in lines.enumerated()
        where line.trimmingCharacters(in: .whitespaces).hasPrefix(sizingModifier) {
            var cursor = index + 1
            while cursor < lines.count {
                let trimmed = lines[cursor].trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || trimmed.hasPrefix("//") {
                    cursor += 1
                    continue
                }
                guard trimmed.hasPrefix(".") else { break }   // the chain ended
                if trimmed.hasPrefix(".padding(.bottom") || trimmed.hasPrefix(".padding(.vertical") {
                    found.append(
                        Overhang(
                            path: path,
                            sizedAt: index + 1,
                            paddedAt: cursor + 1,
                            source: trimmed
                        )
                    )
                }
                cursor += 1
            }
        }
        return found
    }
}

// MARK: - The gate

@Suite("A column sized to its viewport carries no padding outside that frame (#119 F1)")
struct ScrollOverhangGuardTests {

    /// Every site the app spells today, re-measured by the walk this gate uses.
    ///
    /// A floor rather than an equality: screens are added, and a new one should not turn this file
    /// red for existing. It is here so that a rename of the sizing modifier — which would leave the
    /// offense test passing over nothing at all — is caught by something.
    static let sizingSiteFloor = 6

    @Test("no bottom padding is applied downstream of a viewport-sizing frame")
    func noColumnPadsOutsideItsSizedFrame() throws {
        let root = AppSourceLiterals.repositoryRoot()
        let files = AppSourceLiterals.sourceFiles(root: root)

        var offenses: [ViewportSizedColumn.Overhang] = []
        for file in files {
            let relative = file.path.replacingOccurrences(of: root.path + "/", with: "")
            let source = try String(contentsOf: file, encoding: .utf8)
            offenses.append(contentsOf: ViewportSizedColumn.overhangs(in: source, path: relative))
        }

        #expect(
            offenses.isEmpty,
            """
            a scrolling column pads below the frame that sizes it to the viewport, which makes its \
            scroll content taller than the screen and leaves a permanent overhang:
            \(offenses.map {
                "  \($0.path):\($0.paddedAt) — \($0.source)  (sized at line \($0.sizedAt))"
            }.joined(separator: "\n"))
            Move the padding above the .frame(minHeight:) line, as every other column does.
            """
        )
    }

    @Test("the guard sees the sites it claims to check")
    func theGuardSeesEveryKnownSite() throws {
        let root = AppSourceLiterals.repositoryRoot()
        let files = AppSourceLiterals.sourceFiles(root: root)

        #expect(
            files.count >= AppSourceLiterals.swiftFileCountFloor,
            "the source walk found \(files.count) files — it is not reading the app target"
        )

        var sites: [(path: String, line: Int)] = []
        for file in files {
            let relative = file.path.replacingOccurrences(of: root.path + "/", with: "")
            let source = try String(contentsOf: file, encoding: .utf8)
            sites.append(contentsOf: ViewportSizedColumn.sizingSites(in: source, path: relative))
        }

        #expect(
            sites.count >= Self.sizingSiteFloor,
            """
            only \(sites.count) viewport-sizing frames found, below the floor of \
            \(Self.sizingSiteFloor) — the spelling this gate scans for \
            ("\(ViewportSizedColumn.sizingModifier)") has probably changed, in which case the \
            offense test above is passing over nothing. Sites: \
            \(sites.map { "\($0.path):\($0.line)" }.joined(separator: ", "))
            """
        )

        #expect(
            sites.contains { $0.path.hasSuffix("ActivityView.swift") },
            "screen 13 is the site this gate was written for and the scan no longer finds it"
        )
    }

    @Test("the scanner reports the defect and clears the fix")
    func theScannerTellsTheTwoOrdersApart() {
        let broken = """
            VStack {
                Text("x")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: proxy.size.height, alignment: .top)
            .padding(.bottom, CypressSpacing.bottomFootnote)
            """
        let fixed = """
            VStack {
                Text("x")
            }
            .padding(.bottom, CypressSpacing.bottomFootnote)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: proxy.size.height, alignment: .top)
            """

        let onBroken = ViewportSizedColumn.overhangs(in: broken, path: "Broken.swift")
        #expect(onBroken.count == 1, "the scanner missed the defect it exists to find")
        #expect(onBroken.first?.paddedAt == 6)
        #expect(onBroken.first?.sizedAt == 5)

        #expect(
            ViewportSizedColumn.overhangs(in: fixed, path: "Fixed.swift").isEmpty,
            "the scanner flags the correct order, which would make it unusable"
        )
    }

    @Test("a comment inside the chain does not hide the padding that follows it")
    func commentsDoNotEndTheChain() {
        // The site this gate was written for has a six-line comment between the column's closing
        // brace and its modifiers. A scanner that stopped at the first comment would have cleared
        // the very file it was written for.
        let commented = """
            }
            .frame(minHeight: proxy.size.height, alignment: .top)
            // a note about the closing space
            //
            // and a second paragraph of it
            .padding(.bottom, CypressSpacing.bottomFootnote)
            """
        #expect(
            ViewportSizedColumn.overhangs(in: commented, path: "Commented.swift").count == 1,
            "a comment between the frame and the padding hid the padding"
        )
    }

    @Test("a padding on a later, separate chain is not reported")
    func theChainEndsWhereTheChainEnds() {
        // `.padding(.bottom, …)` on some other view further down the file is not this defect, and a
        // scanner that reported it would be turned off within a day.
        let separate = """
            }
            .frame(minHeight: proxy.size.height, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)

            private var footer: some View {
                Text("x")
                    .padding(.bottom, CypressSpacing.bottomFootnote)
            }
            """
        #expect(
            ViewportSizedColumn.overhangs(in: separate, path: "Separate.swift").isEmpty,
            "the scan ran past the end of the chain"
        )
    }
}
