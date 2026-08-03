//
//  DrawnGlyphGuardTests.swift
//  CypressTests
//
//  #130: the app's rule is that every glyph in it is a `Shape` drawn in this repo — no SF Symbols,
//  no icon font. `ShareDestinationGlyph` states the policy; the ruling is
//  `docs/rulings-pending/drawn-glyphs.md`. **This file is what makes the rule true tomorrow.**
//
//  ── Why a test and not a comment ────────────────────────────────────────────────────────────────
//  For months the app shipped five `Image(systemName:)` calls while `ShareDestinationGlyph` said
//  there were none and `MapChrome` said there were two, both inside a photo picker. Neither
//  sentence was checked by anything, so both drifted, and the false one was being copied into
//  briefs as a description of the codebase. A stale comment is invisible; a stale gate is red.
//
//  Modelled on `BritishSpellingGuardTests`, and it reuses that file's source walk
//  (`AppSourceLiterals.repositoryRoot` / `.sourceFiles`) rather than growing a second one.
//
//  ── What it checks, exactly ─────────────────────────────────────────────────────────────────────
//  Every `.swift` file in the **app target**, read off disk, with comments and string-literal
//  interiors blanked out first. Comments have to go: this repo deliberately writes the token
//  `Image(systemName:)` inside prose — in `MapChrome`, in `ShareDestinationGlyph`, in
//  `PhotoGlyphs`, and above these very lines — to record what was removed and why. A guard that
//  could not tell those from a call would have to be turned off within a day of being written.
//
//  ── What it cannot check ────────────────────────────────────────────────────────────────────────
//  A symbol reached through a name this file does not know — a `String` built at runtime and handed
//  to an `Image` initializer resolved by type inference, or a UIKit view configured in a way that
//  never spells `systemName`. Saying so is the point: the guard covers the spellings below, which
//  are the ones SwiftUI and UIKit actually offer, and claims nothing beyond them.
//

import Foundation
import Testing

// MARK: - The APIs that borrow a glyph

enum BorrowedGlyphAPI {

    /// The spellings that reach an SF Symbol. `systemName:` covers `Image(systemName:)`,
    /// `Image(_:systemName:)` and `UIImage(systemName:)`; `systemImage:` covers the `Label`,
    /// `Button`, `Toggle` and `Link` conveniences that take a symbol name instead of a view.
    static let tokens = ["systemName:", "systemImage:"]

    struct Use {
        let path: String
        let line: Int
        let token: String
        /// The line as it stands in the file, for a failure somebody can act on without a debugger.
        let source: String
    }

    /// The source with every comment and string-literal interior replaced by spaces.
    ///
    /// Line count and column positions are preserved, so a hit still reports the line it is on.
    /// Written as a scanner rather than a regex for the reason the spelling guard gives: `"` inside
    /// a `//` comment, an escaped `\"`, and `"""` blocks all occur in this codebase and all three
    /// break the regex version.
    static func codeOnly(in source: String) -> String {
        enum State { case code, line, block, string, multiline }
        var state = State.code
        var blockDepth = 0
        var out: [Character] = []
        out.reserveCapacity(source.count)

        let chars = Array(source)
        var i = 0

        func peek(_ s: String, _ at: Int) -> Bool {
            let t = Array(s)
            guard at + t.count <= chars.count else { return false }
            return Array(chars[at..<(at + t.count)]) == t
        }
        /// Emit a blank for `count` characters, keeping any newlines among them.
        func blank(_ count: Int, from at: Int) {
            for k in at..<min(at + count, chars.count) {
                out.append(chars[k] == "\n" ? "\n" : " ")
            }
        }

        while i < chars.count {
            let c = chars[i]
            switch state {
            case .code:
                if peek("//", i) { state = .line; blank(2, from: i); i += 2; continue }
                if peek("/*", i) { state = .block; blockDepth = 1; blank(2, from: i); i += 2; continue }
                if peek("\"\"\"", i) { state = .multiline; blank(3, from: i); i += 3; continue }
                if c == "\"" { state = .string; out.append(" "); i += 1; continue }
                out.append(c)
                i += 1

            case .line:
                if c == "\n" { state = .code; out.append("\n"); i += 1; continue }
                out.append(" ")
                i += 1

            case .block:
                if peek("/*", i) { blockDepth += 1; blank(2, from: i); i += 2; continue }
                if peek("*/", i) {
                    blockDepth -= 1
                    blank(2, from: i)
                    i += 2
                    if blockDepth == 0 { state = .code }
                    continue
                }
                out.append(c == "\n" ? "\n" : " ")
                i += 1

            case .string, .multiline:
                // An interpolation is code, and code inside one still counts.
                if c == "\\", peek("\\(", i) {
                    var depth = 1
                    var j = i + 2
                    out.append(" ")
                    out.append(" ")
                    while j < chars.count, depth > 0 {
                        if chars[j] == "(" { depth += 1 }
                        if chars[j] == ")" { depth -= 1 }
                        out.append(chars[j])
                        j += 1
                    }
                    i = j
                    continue
                }
                if c == "\\" { blank(2, from: i); i += 2; continue }
                if state == .string, c == "\"" { state = .code; out.append(" "); i += 1; continue }
                if state == .string, c == "\n" { state = .code; out.append("\n"); i += 1; continue }
                if state == .multiline, peek("\"\"\"", i) {
                    state = .code
                    blank(3, from: i)
                    i += 3
                    continue
                }
                out.append(c == "\n" ? "\n" : " ")
                i += 1
            }
        }
        return String(out)
    }

    /// Every borrowed-glyph call in one file's source.
    static func uses(in source: String, path: String) -> [Use] {
        let code = codeOnly(in: source)
        let rawLines = source.components(separatedBy: "\n")
        var found: [Use] = []
        for (index, line) in code.components(separatedBy: "\n").enumerated() {
            for token in tokens where line.contains(token) {
                found.append(
                    Use(
                        path: path,
                        line: index + 1,
                        token: token,
                        source: index < rawLines.count
                            ? rawLines[index].trimmingCharacters(in: .whitespaces)
                            : ""
                    )
                )
            }
        }
        return found
    }
}

// MARK: - The guard

@Suite("Every glyph in the app is drawn in this repo (#130)")
struct DrawnGlyphGuardTests {

    /// **The gate.** `ShareDestinationGlyph` states the rule in prose; this is the copy that fails.
    @Test("no SF Symbol is reached from the app target")
    func theAppBorrowsNoGlyphs() throws {
        let root = AppSourceLiterals.repositoryRoot()
        let files = AppSourceLiterals.sourceFiles(root: root)

        var uses: [BorrowedGlyphAPI.Use] = []
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let relative = file.path.replacingOccurrences(of: root.path + "/", with: "")
            uses += BorrowedGlyphAPI.uses(in: source, path: relative)
        }

        #expect(
            uses.isEmpty,
            """
            \(uses.count) SF Symbol call(s) in the app target. Every glyph in Cypress is a Shape \
            drawn in this repo — the policy is stated in ShareDestinationGlyph and ruled in \
            docs/rulings-pending/drawn-glyphs.md. Draw the mark instead, beside the screen that \
            uses it, or change the ruling; do not change this test to match the code.
            \(uses.map { "  \($0.path):\($0.line): \($0.source)" }.joined(separator: "\n"))
            """
        )
    }

    // MARK: The guard's own provenance — it must not pass by seeing nothing

    /// This project's signature failure is a green result from a check that ran on nothing.
    @Test("the guard can see the source it claims to check")
    func theGuardCanSeeTheSource() throws {
        let root = AppSourceLiterals.repositoryRoot()
        #expect(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("Cypress").path),
            """
            the guard cannot find \(root.path)/Cypress, so it checked nothing at all. It reads the \
            source tree through #filePath; if the tree can move away from the binary in this \
            environment, the guard needs a different source of truth, not a skip.
            """
        )
        let files = AppSourceLiterals.sourceFiles(root: root)
        #expect(
            files.count >= 150,
            "the guard swept \(files.count) files; the app target had 181 at #130, so this is not it"
        )
    }

    /// **A positive control taken from the repo, not from a fixture.** #130 wrote the token
    /// `Image(systemName:)` into prose in three files on purpose, to record what was removed. If
    /// the scanner ever stops stripping comments, the gate above goes red on those sentences and
    /// the next reader deletes it. So: the mentions must still be there, and must not be counted.
    @Test("the token appears in this repo's comments, and the scanner does not count it")
    func commentsMentioningSymbolsAreNotCounted() throws {
        let root = AppSourceLiterals.repositoryRoot()
        var filesMentioningInProse = 0
        for file in AppSourceLiterals.sourceFiles(root: root) {
            let source = try String(contentsOf: file, encoding: .utf8)
            guard source.contains("Image(systemName:") else { continue }
            filesMentioningInProse += 1
            #expect(
                BorrowedGlyphAPI.uses(in: source, path: file.lastPathComponent).isEmpty,
                "\(file.lastPathComponent) mentions the token in prose and the scanner read it as a call"
            )
        }
        #expect(
            filesMentioningInProse >= 2,
            """
            no app file mentions Image(systemName:) in prose any more, so the control above proves \
            nothing. #130 left those mentions in MapChrome, ShareDestinationGlyph and PhotoGlyphs \
            deliberately; if they were removed, this control needs rewriting, not deleting.
            """
        )
    }

    /// The other half: the scanner has to actually catch a call. A gate that matches nothing passes
    /// every sweep, which is exactly how this codebase came to believe it had no symbols in it.
    @Test("the scanner catches every spelling that reaches a symbol")
    func theScannerCatchesRealCalls() {
        let source = """
        // Image(systemName: "trash") in a comment does not count
        /* nor Label("x", systemImage: "trash") in a block */
        let a = "a literal saying systemName: trash"
        struct V: View {
            var body: some View {
                Image(systemName: "trash")
                Label("Delete", systemImage: "trash")
                Image(uiImage: UIImage(systemName: "xmark")!)
                LeafGlyph()
            }
        }
        """
        // Lines 6, 7 and 8 each carry one token; lines 1–3 carry one each in a comment or a literal.
        let uses = BorrowedGlyphAPI.uses(in: source, path: "spec.swift")
        #expect(uses.count == 3, "expected 3 calls, found \(uses.map { "\($0.line):\($0.token)" })")
        #expect(uses.allSatisfy { $0.line >= 6 }, "a comment or literal was counted: \(uses)")
        #expect(uses.filter { $0.token == "systemImage:" }.count == 1)
        #expect(uses.filter { $0.token == "systemName:" }.count == 2)
    }

    /// The token list is the whole gate; an empty one passes everything.
    @Test("the token list is not empty")
    func theTokenListIsPopulated() {
        #expect(BorrowedGlyphAPI.tokens.contains("systemName:"))
        #expect(BorrowedGlyphAPI.tokens.contains("systemImage:"))
    }
}
