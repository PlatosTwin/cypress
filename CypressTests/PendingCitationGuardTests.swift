//
//  PendingCitationGuardTests.swift
//  Cypress — CypressTests
//
//  Task #189. CLAUDE.md requires code to cite errata and rulings **by number**, because an entry
//  written on a branch is unnumbered until the orchestrator splices it, and a citation naming the
//  branch file is rewritten at merge. That rewrite is mechanical and it works — as long as there
//  is a filename to rewrite. What it cannot rewrite is a citation that names no document at all:
//  a comment deferring to a document that has not been numbered yet reads like provenance and
//  resolves to nothing, and it goes on resolving to nothing after the document is spliced,
//  because nothing points at it.
//
//  Eight shipped comments were in that state when this guard was written — five named in #189,
//  three more the sweep found. They resolved to R42 §1, R40 (twice), R35, R43 §2, R43 (twice) and
//  ERRATA E192. This file is what stops the ninth.
//
//  ── Why the needles are assembled at runtime ────────────────────────────────────────────────
//  So that this file is **not exempt from its own rule.** A guard that skips itself is the shape
//  CLAUDE.md warns about: a red-proof that exempted the thing it was guarding as its own wrapper.
//  Every needle here is built by concatenation, so no literal in this file matches the pattern,
//  and the sweep reads this file on exactly the terms it reads every other one. There is no
//  exemption list and no file the scan skips.
//
//  ── What it does not check ──────────────────────────────────────────────────────────────────
//  Whether a *numbered* citation names the right entry. `RULINGS R43 §2` and `RULINGS R7 §2` are
//  indistinguishable to a scanner; only reading both documents settles it, which is what #189 did
//  by hand. This guard catches the citation that resolves to nothing, not the one that resolves
//  wrongly — different failures, and only the first has a mechanical tell.
//

import Foundation
import Testing

/// The scan, separated from the tests so the red-proof can point it at source it builds itself.
enum PendingCitationGuard {

    struct Hit: Equatable {
        let path: String
        let line: Int
        let text: String
    }

    /// The app target, the unit target and the UI target, in sweep order.
    static let roots = ["Cypress", "CypressTests", "CypressUITests"]

    /// Never written whole, so this file carries no instance of the shape it looks for.
    private static let qualifier = "pend" + "ing"
    private static let citation = "(rulings?|errata|erratum)"

    /// The qualifier standing immediately in front of a citation word. Only whitespace, comment
    /// markers and markdown emphasis may sit between the two, which is what lets the pattern cross
    /// a doc comment's line wrap — two of the eight real sites broke the line right there — while
    /// still declining `` `.<qualifier>` (ERRATA E37) ``, where a backtick and a parenthesis
    /// intervene and the citation is numbered anyway. Those three moderation-state comments in the
    /// shipping tree are the reason this is an adjacency rule and not a same-line co-occurrence
    /// rule, which flagged all three.
    private static let adjacency = qualifier + #"[\s/*_]*"# + citation + #"\b"#

    /// The two shared branch directories, whose names are themselves the shape: a comment citing a
    /// path under either is citing a document whose number does not exist yet.
    private static let directories = ["errata", "rulings"].map { $0 + "-" + qualifier }

    /// Every hit in one file's text.
    ///
    /// The window is two lines wide because the real sites wrap. A match is attributed to the line
    /// it *starts* on, so a wrapped hit is reported once rather than once per line of the wrap.
    static func hits(in source: String, path: String) -> [Hit] {
        let lines = source.components(separatedBy: "\n")
        guard let expression = try? NSRegularExpression(
            pattern: adjacency, options: [.caseInsensitive]
        ) else { return [] }

        var found: [Hit] = []
        for (index, line) in lines.enumerated() {
            let next = index + 1 < lines.count ? lines[index + 1] : ""
            let window = line + "\n" + next
            let ownLength = (line as NSString).length

            let matches = expression.matches(
                in: window, range: NSRange(location: 0, length: (window as NSString).length)
            )
            let opensHere = matches.contains { $0.range.location < ownLength }
            let citesBranchDirectory = directories.contains {
                line.range(of: $0, options: .caseInsensitive) != nil
            }

            if opensHere || citesBranchDirectory {
                found.append(
                    Hit(path: path, line: index + 1,
                        text: line.trimmingCharacters(in: .whitespaces))
                )
            }
        }
        return found
    }

    /// Every `.swift` file under the three roots, sorted, each with its repo-relative path.
    static func sourceFiles(root: URL) -> [(url: URL, relative: String)] {
        var out: [(url: URL, relative: String)] = []
        for name in roots {
            let directory = root.appendingPathComponent(name)
            guard let walker = FileManager.default.enumerator(
                at: directory, includingPropertiesForKeys: nil
            ) else { continue }
            for case let url as URL in walker where url.pathExtension == "swift" {
                out.append((url, name + url.path.dropFirst(directory.path.count)))
            }
        }
        return out.sorted { $0.relative < $1.relative }
    }
}

@Suite("A citation resolves to a numbered document, or it is not provenance")
struct PendingCitationGuardTests {

    // MARK: - 1. The sweep

    @Test("no comment defers to a ruling or an erratum that has no number")
    func everyCitationNamesADocumentAReaderCanFind() throws {
        let root = AppSourceLiterals.repositoryRoot()
        var hits: [PendingCitationGuard.Hit] = []
        for file in PendingCitationGuard.sourceFiles(root: root) {
            let source = try String(contentsOf: file.url, encoding: .utf8)
            hits += PendingCitationGuard.hits(in: source, path: file.relative)
        }

        #expect(
            hits.isEmpty,
            """
            \(hits.count) citation(s) defer to a ruling or erratum that carries no number, so a \
            reader has nothing to look up and the merge rewrite has no filename to fix. Read the \
            entry, establish which numbered R/E it meant, and cite that. If it cannot be \
            established, say so in the comment rather than guessing — a wrong number is worse than \
            an admitted gap, because it looks checked (#189, CLAUDE.md "Numbering and shared \
            files").
            \(hits.map { "  \($0.path):\($0.line)  \($0.text)" }.joined(separator: "\n"))
            """
        )
    }

    // MARK: - 2. The guard can see what it claims to have checked

    /// **Floors derived, not remembered.** Measured on this worktree while writing #189:
    /// `Cypress` 257 files, `CypressTests` 106 before this one, `CypressUITests` 15 — 378 in all.
    /// The floors sit a little under each measurement, because their job is to catch a walk that
    /// found the wrong tree or no tree, not to track the targets' growth.
    ///
    /// **Each root is asserted separately on purpose.** A combined total would let
    /// `CypressUITests` drop out of the sweep entirely and still clear the bar on `Cypress`' 257
    /// alone — and `CypressUITests` is where one of the eight sites lived.
    @Test("the guard swept all three targets, not one of them")
    func theGuardCanSeeTheSourceItClaimsToCheck() throws {
        let root = AppSourceLiterals.repositoryRoot()
        for name in PendingCitationGuard.roots {
            #expect(
                FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path),
                "the guard cannot find \(root.path)/\(name), so it checked nothing there at all"
            )
        }

        let files = PendingCitationGuard.sourceFiles(root: root)
        var counted: [String: Int] = [:]
        for file in files {
            counted[String(file.relative.prefix { $0 != "/" }), default: 0] += 1
        }

        let expected: [(name: String, floor: Int, measured: Int)] = [
            ("Cypress", 240, 257), ("CypressTests", 95, 107), ("CypressUITests", 12, 15)
        ]
        for target in expected {
            let swept = counted[target.name] ?? 0
            #expect(
                swept >= target.floor,
                """
                the guard swept \(swept) files under \(target.name)/; that target held \
                \(target.measured) at #189, so this is not it. Re-measure before repinning this \
                floor — do not repin it from memory.
                """
            )
        }
    }

    // MARK: - 3. The scanner finds the shape, and declines the near-misses

    /// **The red-proof, run on every build rather than once by hand.** Section 1 asserts an
    /// absence, and an absence is exactly what a broken scanner reports too — the failure
    /// ARCHITECTURE §7 records about grepping for a symbol with no control string. So the scanner
    /// is pointed at source carrying all four shapes, including the two-line wrap two real sites
    /// had, and at the three comments in the shipping tree it must **not** flag: there
    /// `.<qualifier>` is a moderation state, and the `(ERRATA E37)` beside it resolves perfectly
    /// well.
    @Test("the scanner flags each shape it exists to find, and only those")
    func theScannerFindsTheShapeAndNotItsNearMisses() {
        let qualifier = "pend" + "ing"
        let citationWord = "rul" + "ing"
        let specimen = """
        // 1 · same line, lower case
        /// recorded in the \(qualifier) \(citationWord).
        // 2 · wrapped across the comment's line break, which two real sites were
        /// Boots preferring the reader's chosen city (the \(qualifier)
        /// RULINGS R43 §1: one inventory attaches).
        // 3 · the errata spelling, singular
        // the \(qualifier) erratum for #143 records the debt.
        // 4 · a shared branch directory, cited as a path
        /// see docs/errata-\(qualifier)/sheet-dismiss.md
        // ── and the near-misses, which must stay silent ──
        // 5 · a moderation state beside a numbered citation
        /// their moderation state is `.\(qualifier)` (ERRATA E37).
        // 6 · an outbox row
        guard item.state == .\(qualifier) else { return nil }
        // 7 · a numbered citation with no qualifier anywhere near it
        /// drawn exactly as RULINGS R43 specifies (§§2-3).
        """

        let hits = PendingCitationGuard.hits(in: specimen, path: "specimen.swift")
        #expect(
            hits.map(\.line) == [2, 4, 7, 9],
            "the scanner reported \(hits.map { "\($0.line): \($0.text)" })"
        )

        // The control section 1's absence needs: source with none of the shape must come back
        // empty, or "no hits" is not evidence of anything.
        let clean = PendingCitationGuard.hits(
            in: "/// recorded in RULINGS R42 §1.\n/// and in ERRATA E192.", path: "clean.swift"
        )
        #expect(clean.isEmpty, "the scanner flagged a numbered citation: \(clean)")
    }
}
