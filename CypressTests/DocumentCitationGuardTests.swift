//
//  DocumentCitationGuardTests.swift
//  Cypress — CypressTests
//
//  The sibling rule to `PendingCitationGuardTests`, pointed the other way. That guard reads Swift
//  source and asks whether a citation names a document a reader can find. This one reads the
//  documents and asks whether a citation names a **file** a reader can open.
//
//  ── What went wrong, and why prose was the wrong place to fix it ─────────────────────────────
//  RULINGS R68 and ERRATA E249 — both numbered, both permanent — cited
//  `docs/design-proposals/2026-08-06-task14.md`, which existed only on the throwaway branch it was
//  written on. The branch's remote copy was deleted when its PR closed; the local copy survived on
//  one laptop for two days by accident. Two numbered entries were one `git branch -D` away from
//  pointing at nothing, and nothing would have said so.
//
//  The instance is fixed by landing the document. The **class** is that a permanent document may
//  cite an ephemeral artifact, and prose cannot enforce its own referential integrity. This is the
//  enforcement.
//
//  ── What it checks ──────────────────────────────────────────────────────────────────────────
//  Every `.md` under `docs/`, for two shapes:
//    1. a backticked repo-relative path carrying a file extension — `` `Tools/run_tests.sh` ``
//    2. a relative markdown link or image target — `![](images/17-dark-17b.png)`
//  Both must resolve to something on disk.
//
//  ── What it does not check, and why ─────────────────────────────────────────────────────────
//  **Bare filenames.** A citation must carry at least one `/` to be checked. `` `Package.swift` ``
//  in prose usually names a kind of file rather than a file, and the false-positive rate is not
//  worth the two root-level documents it would cover.
//
//  **Generated paths.** `dist/upload.sh` is cited four times across ERRATA E247 and
//  `docs/investigations/city-publishing.md`, and `Fixtures/raw/…` several more; both are gitignored
//  and regenerable. A generated artifact is a legitimate thing to name and an illegitimate thing to
//  require on disk, so `generatedPrefixes` reads `.gitignore` rather than carrying a list here —
//  see its own note for what the earlier "is it a real top-level directory" rule got wrong in both
//  directions.
//
//  **Whether a citation names the right file.** `Tools/run_tests.sh` and `Tools/verify_test_log.sh`
//  are indistinguishable to a scanner. Same limit `PendingCitationGuardTests` records: this catches
//  the citation that resolves to nothing, not the one that resolves wrongly.
//
//  **Anchors, URLs, and fenced blocks.** `#section`, anything with a scheme, and anything inside a
//  ``` fence are skipped.
//
//  ── Shapes it knowingly lets through ────────────────────────────────────────────────────────
//  Measured against a probe document, not assumed. Each is a real dangling citation this guard
//  reports as clean, listed so the next reader does not mistake its silence for a proof:
//    · an extension outside the allowlist — `.csv`, `.html`, `.sql`, `.xcconfig`, `.geojson`.
//      `mocks/cypress-mocks.html` is cited six times and is invisible for exactly this reason.
//    · a leading `~` or `..`.
//    · a hidden top-level directory — `.github/workflows/…` is excluded twice over, by the
//      pattern's first-character class and by `contentsOfDirectory`'s defaults.
//    · a path that resolves to a *directory* rather than a file.
//    · a citation broken across a line break.
//  Widening the extension list is the tempting fix and is not free: `.csv` alone turns five
//  committed `Fixtures/raw/…` citations red, which is why `generatedPrefixes` had to land first.
//

import Foundation
import Testing

/// The scan, separated from the tests so §3 can point it at source it builds itself.
enum DocumentCitationGuard {

    struct Citation: Equatable, CustomStringConvertible {
        let document: String
        let line: Int
        let target: String

        var description: String { "\(document):\(line)  \(target)" }
    }

    /// The extensions that make a slash-bearing token a *file* citation rather than prose. Kept
    /// explicit rather than "anything after a dot": `E119/E122` and `§9b/§10` are cited constantly
    /// and neither is a path.
    static let extensions = [
        "md", "swift", "py", "sh", "json", "yml", "yaml", "sqlite", "txt", "png", "plist", "pbxproj"
    ]

    /// A backticked, slash-bearing, extension-carrying token.
    ///
    /// **The close is a lookahead, not a backtick.** The repo's most common tool citation is
    /// `` `Tools/verify_test_log.sh <log>` `` — path, then arguments, then the backtick. Anchoring
    /// on the backtick made 17 occurrences across 5 distinct tools invisible, including every
    /// citation of the two scripts CLAUDE.md requires be used to judge a run.
    private static var backtickedPattern: String {
        "`([A-Za-z0-9_][A-Za-z0-9_.-]*(?:/[A-Za-z0-9_.-]+)+\\.(?:"
            + extensions.joined(separator: "|") + "))(?=`|\\s)"
    }

    /// Directory prefixes the repository itself declares generated, read from `.gitignore`.
    ///
    /// **This replaces "is the first component a real top-level directory", which was wrong in both
    /// directions.** `dist/` is created at the repo root by `Tools/publish_cities.py --out` during
    /// the seed publish, so on any machine mid-publish that rule flipped and four committed prose
    /// citations went red — a unit result depending on untracked working-tree state, during a
    /// workflow CLAUDE.md documents as recurring and agent-side. In the other direction
    /// `Fixtures/raw/` is `dist/`'s exact twin — gitignored, regenerable — but *is* a real
    /// top-level path, so five absent citations under it escaped only because their extensions
    /// happened not to be allowlisted; adding `csv` would have turned committed ERRATA prose red.
    ///
    /// Reading `.gitignore` fixes both and cannot drift from the repository the way a list here
    /// would: the repo already states what it generates.
    static func generatedPrefixes(root: URL) -> [String] {
        guard let text = try? String(
            contentsOf: root.appendingPathComponent(".gitignore"), encoding: .utf8
        ) else { return [] }
        return text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.hasPrefix("#") && !$0.hasPrefix("!") && $0.hasSuffix("/") }
            .map { $0.hasPrefix("/") ? String($0.dropFirst()) : $0 }
            .filter { !$0.isEmpty }
    }

    /// A markdown link or image target. The `!` is optional because an image is a link that draws.
    private static let linkPattern = #"!?\[[^\]]*\]\(([^)\s]+)\)"#

    /// Every backticked path citation in one document's text.
    static func backtickedPaths(in source: String, document: String) -> [Citation] {
        matches(of: backtickedPattern, in: source, document: document)
    }

    /// Every relative link or image target in one document's text.
    ///
    /// Absolute URLs and pure anchors are dropped here rather than at the pattern, so that a
    /// malformed scheme shows up as a miss instead of vanishing.
    static func linkTargets(in source: String, document: String) -> [Citation] {
        matches(of: linkPattern, in: source, document: document).filter {
            !$0.target.contains("://") && !$0.target.hasPrefix("#") && !$0.target.hasPrefix("mailto:")
        }
    }

    /// One pattern's capture group 1, with the line each match starts on.
    ///
    /// **Fenced blocks are skipped, and that is not a nicety.** A fence is where a document shows
    /// what a citation *looks like* rather than making one — and the link pattern needs no
    /// extension, so any `x[i](y)` in any snippet under `docs/` would be required to resolve on
    /// disk. A ```` ```markdown ```` fence demonstrating `![](images/EXAMPLE.png)` and a Python
    /// snippet containing `handlers[key](fallback.png)` both failed the suite before this. There
    /// are no live instances today; the next document that explains markdown syntax was the bug.
    private static func matches(
        of pattern: String, in source: String, document: String
    ) -> [Citation] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        var found: [Citation] = []
        var fenced = false
        for (index, line) in source.components(separatedBy: "\n").enumerated() {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                fenced.toggle()
                continue
            }
            guard !fenced else { continue }

            let text = line as NSString
            for match in expression.matches(
                in: line, range: NSRange(location: 0, length: text.length)
            ) where match.numberOfRanges > 1 {
                found.append(
                    Citation(document: document, line: index + 1,
                             target: text.substring(with: match.range(at: 1)))
                )
            }
        }
        return found
    }

    /// Every directory sitting at the repository root, by name.
    ///
    /// This is what decides whether a citation is repo-relative at all — see the header on
    /// `dist/upload.sh`.
    static func topLevelDirectories(root: URL) -> Set<String> {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey]
        )) ?? []
        return Set(
            contents
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                .map(\.lastPathComponent)
        )
    }

    /// Every `.md` under `docs/`, sorted, each with its repo-relative path.
    ///
    /// Both sides of the prefix arithmetic are resolved before it runs, for the reason
    /// `PendingCitationGuard.sourceFiles` records at length (#229): when the two spellings disagree
    /// the character counts stop describing each other and the drop silently takes the wrong slice.
    static func documents(root: URL) -> [(url: URL, relative: String)] {
        let directory = root.appendingPathComponent("docs").resolvingSymlinksInPath()
        guard let walker = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: nil
        ) else { return [] }

        var out: [(url: URL, relative: String)] = []
        for case let url as URL in walker where url.pathExtension == "md" {
            let resolved = url.resolvingSymlinksInPath()
            out.append((resolved, "docs" + resolved.path.dropFirst(directory.path.count)))
        }
        return out.sorted { $0.relative < $1.relative }
    }

    /// Whether one citation resolves, given the document it was found in.
    ///
    /// A backticked path is resolved from the repository root; a link target from the directory of
    /// the document that carries it, which is how markdown itself reads them.
    static func resolves(_ citation: Citation, root: URL, relativeToDocument: Bool) -> Bool {
        let base = relativeToDocument
            ? root.appendingPathComponent(citation.document).deletingLastPathComponent()
            : root
        return FileManager.default.fileExists(
            atPath: base.appendingPathComponent(citation.target).path
        )
    }
}

@Suite("A document's citation names a file a reader can open")
struct DocumentCitationGuardTests {

    // MARK: - 1. The sweep

    @Test("every repo-relative path cited under docs/ exists")
    func everyCitedPathResolves() throws {
        let root = AppSourceLiterals.repositoryRoot()
        let prefixes = DocumentCitationGuard.topLevelDirectories(root: root)
        let generated = DocumentCitationGuard.generatedPrefixes(root: root)
        var missing: [DocumentCitationGuard.Citation] = []

        for document in DocumentCitationGuard.documents(root: root) {
            let source = try String(contentsOf: document.url, encoding: .utf8)
            for citation in DocumentCitationGuard.backtickedPaths(
                in: source, document: document.relative
            ) {
                guard let head = citation.target.split(separator: "/").first,
                      prefixes.contains(String(head)),
                      !generated.contains(where: { citation.target.hasPrefix($0) })
                else { continue }
                if !DocumentCitationGuard.resolves(citation, root: root, relativeToDocument: false) {
                    missing.append(citation)
                }
            }
        }

        #expect(
            missing.isEmpty,
            """
            \(missing.count) citation(s) under docs/ name a repo-relative file that does not \
            exist. A numbered entry is permanent and the thing it points at must be too: land the \
            file, or reword the sentence so it reads as history rather than as a pointer. R68 and \
            E249 spent two days one `git branch -D` away from citing nothing, which is why this \
            guard exists.
            \(missing.map { "  \($0)" }.joined(separator: "\n"))
            """
        )
    }

    @Test("every relative link and image target under docs/ resolves")
    func everyLinkTargetResolves() throws {
        let root = AppSourceLiterals.repositoryRoot()
        var missing: [DocumentCitationGuard.Citation] = []

        for document in DocumentCitationGuard.documents(root: root) {
            let source = try String(contentsOf: document.url, encoding: .utf8)
            for citation in DocumentCitationGuard.linkTargets(
                in: source, document: document.relative
            ) where !DocumentCitationGuard.resolves(
                citation, root: root, relativeToDocument: true
            ) {
                missing.append(citation)
            }
        }

        #expect(
            missing.isEmpty,
            """
            \(missing.count) markdown link or image target(s) under docs/ resolve to nothing. An \
            image that 404s is the same defect as a dangling path citation, one rendering layer \
            down — and it is how a document whose whole value is its renders arrives with none.
            \(missing.map { "  \($0)" }.joined(separator: "\n"))
            """
        )
    }

    // MARK: - 2. The guard can see what it claims to have checked

    /// **An absence is what a broken sweep reports too.** §1 asserts that nothing is missing, and a
    /// scan that read no documents, or matched no citations, satisfies that perfectly.
    ///
    /// **These are OCCURRENCES, not distinct paths, and every number here came out of this test's
    /// own counter.** That distinction is not pedantry: the first version of these floors was
    /// measured with a shell `grep … | sort -u` while the loop below counts every hit, so they were
    /// pinned at 30/28/14/12 against true values of 47/57/134/53 — up to 8.4× of slack, and a
    /// failure message that would have read *"matched 134 citation(s) under Tools/; there were 17
    /// when this was written"* to whoever hit it next. To re-measure, raise a floor to 9999 and
    /// read the number the failure prints. Do not use a different instrument, and do not repin from
    /// memory.
    ///
    /// The margin is ~12% under each measurement: enough that ordinary editing does not trip it,
    /// tight enough that a *partial* blinding does. That mattered — dropping `-` from the
    /// extractor's character class leaves `Cypress` at 46 and `docs` at 37, both under these
    /// floors, and both over the old ones.
    ///
    /// **Per prefix, not in total.** A combined floor would let `CypressUITests` (1 citation) or
    /// `server` (4) drop out of the scan entirely while `Cypress` and `CypressTests` alone cleared
    /// the bar. Only the four large prefixes are floored: the small ones move by one when a single
    /// sentence is rewritten, and a floor that fails on ordinary editing teaches people to raise
    /// floors rather than read them.
    @Test("the sweep read the real documents and matched real citations")
    func theGuardCanSeeWhatItClaimsToCheck() throws {
        let root = AppSourceLiterals.repositoryRoot()

        let documents = DocumentCitationGuard.documents(root: root)
        #expect(
            documents.count >= 29,
            """
            the sweep found \(documents.count) documents under docs/; it held 33 when this was \
            written, so this is not that tree. Re-measure before repinning — do not repin from \
            memory.
            """
        )

        // The two numbered documents are the reason this guard exists; a sweep that misses them
        // has missed the point regardless of how many others it read.
        for required in ["docs/ERRATA.md", "docs/RULINGS.md"] {
            #expect(
                documents.contains { $0.relative == required },
                "the sweep did not read \(required), the document this guard was written for"
            )
        }

        var counted: [String: Int] = [:]
        var links = 0
        for document in documents {
            let source = try String(contentsOf: document.url, encoding: .utf8)
            for citation in DocumentCitationGuard.backtickedPaths(
                in: source, document: document.relative
            ) {
                guard let head = citation.target.split(separator: "/").first else { continue }
                counted[String(head), default: 0] += 1
            }
            links += DocumentCitationGuard.linkTargets(
                in: source, document: document.relative
            ).count
        }

        let floors: [(prefix: String, floor: Int, measured: Int)] = [
            ("CypressTests", 41, 47), ("Cypress", 50, 57), ("Tools", 118, 134), ("docs", 46, 53)
        ]
        for target in floors {
            let found = counted[target.prefix] ?? 0
            #expect(
                found >= target.floor,
                """
                the extractor matched \(found) citation(s) under \(target.prefix)/; there were \
                \(target.measured) when this was written. Either the pattern stopped matching a \
                shape it used to, or that prefix left the scan — both make §1's silence worthless.
                """
            )
        }

        #expect(
            links >= 18,
            """
            the extractor matched \(links) relative link target(s); there were 21 when this was \
            written, all of them the task-14 proposal renders
            """
        )
    }

    // MARK: - 3. The extractors find each shape, and decline the near-misses

    /// **The red-proof, run on every build rather than once by hand.** §1 and §2 both rest on the
    /// extractors being able to see a citation at all, and a regex that matches nothing is
    /// indistinguishable from a corpus that is clean.
    ///
    /// The near-misses are not hypothetical. Every one of them was a false positive on the first
    /// measurement of this corpus: `CypressTests/AX5ReflowTests` and
    /// `MapMarkerRenderingTests.clusterBadgeFollowsItsCount` are **test symbols**, cited in exactly
    /// the same backticked, slash-bearing way as a file and legitimately not files — 29 of them
    /// reported as missing before the extension requirement was added.
    @Test("the path extractor finds a cited file, and declines a cited test symbol")
    func thePathExtractorDeclinesItsNearMisses() {
        let specimen = """
        1 · the citation this guard exists for: `docs/design-proposals/2026-08-06-task14.md`
        2 · a tool with arguments, the repo's commonest form: `Tools/verify_test_log.sh <log>`
        3 · a plain one: `Tools/run_tests.sh` is how the suite runs.
        4 · another, nested: `docs/distilled/SCREENS.md` holds the wording.
        5 · a test symbol, slash-bearing and extensionless: `CypressTests/AX5ReflowTests`
        6 · a test symbol with a dotted member: `MapMarkerRenderingTests.clusterBadgeFollowsItsCount`
        7 · an errata range, which is not a path: `E119/E122` and `§9b/§10`
        8 · a bare filename, deliberately uncovered: `Package.swift`
        9 · a generated artifact, dropped by §1's .gitignore rule, not by this pattern: `dist/upload.sh`
        """

        let hits = DocumentCitationGuard.backtickedPaths(in: specimen, document: "specimen.md")
        #expect(
            hits.map(\.target) == [
                "docs/design-proposals/2026-08-06-task14.md",
                "Tools/verify_test_log.sh",
                "Tools/run_tests.sh",
                "docs/distilled/SCREENS.md",
                "dist/upload.sh"
            ],
            "the extractor reported \(hits.map(\.target))"
        )
        #expect(hits.map(\.line) == [1, 2, 3, 4, 9], "the extractor mislocated: \(hits.map(\.line))")

        // Line 1 is not decoration. Every path in the first version of this specimen was
        // hyphen-free, so dropping `-` from the pattern's character class left all four §2 floors
        // clear, this test green — and `2026-08-06-task14.md` unmatched, meaning R68's and E249's
        // citations silently stopped being checked. A guard fully green and blind to the one
        // citation it was written for. The specimen must contain the real thing, not a likeness.
        //
        // Line 9 is matched here on purpose and dropped by §1's `.gitignore` rule rather than by
        // this pattern: keeping the split visible is what lets §2's floors tell a deliberately
        // excluded prefix from one that stopped matching.

        // The control §1's silence needs: prose with none of the shape must come back empty.
        let clean = DocumentCitationGuard.backtickedPaths(
            in: "drawn exactly as RULINGS R43 specifies (§§2-3), see `E119/E122`.",
            document: "clean.md"
        )
        #expect(clean.isEmpty, "the extractor matched prose: \(clean)")
    }

    @Test("the link extractor finds images and relative links, and declines URLs and anchors")
    func theLinkExtractorDeclinesItsNearMisses() {
        let specimen = """
        1 · an image: ![](images/17-dark-17b.png)
        2 · a relative link with text: [the runbook](../CONTRIBUTING.md)
        3 · an absolute URL, skipped: [the repo](https://github.com/PlatosTwin/cypress)
        4 · a pure anchor, skipped: [above](#item-1a)
        5 · a mail link, skipped: [write](mailto:nobody@example.com)
        """

        let hits = DocumentCitationGuard.linkTargets(in: specimen, document: "docs/specimen.md")
        #expect(
            hits.map(\.target) == ["images/17-dark-17b.png", "../CONTRIBUTING.md"],
            "the link extractor reported \(hits.map(\.target))"
        )

        let clean = DocumentCitationGuard.linkTargets(
            in: "no links here, only prose about `Tools/run_tests.sh`.", document: "clean.md"
        )
        #expect(clean.isEmpty, "the link extractor matched prose: \(clean)")
    }
}
