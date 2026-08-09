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
//  **Paths whose first component is not a real top-level directory.** `dist/upload.sh` is cited
//  three times in ERRATA E247 and does not exist: `dist/` is *generated per run* by
//  `Tools/publish_cities.py` (see `docs/investigations/city-publishing.md`). A generated artifact is
//  a legitimate thing to name and an illegitimate thing to require on disk. Rather than carry an
//  exemption list — which rots silently, and is the "input deletion" shape this repo has already
//  been bitten by — the rule is structural: a first component that is not a directory in this
//  repository is not a repo-relative path, so it is not this guard's business. §2's per-prefix
//  floors are what stop that rule from quietly swallowing a prefix that *should* be checked.
//
//  **Whether a citation names the right file.** `Tools/run_tests.sh` and `Tools/verify_test_log.sh`
//  are indistinguishable to a scanner. Same limit `PendingCitationGuardTests` records: this catches
//  the citation that resolves to nothing, not the one that resolves wrongly.
//
//  **Anchors and URLs.** `#section` and anything with a scheme are skipped.
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
    private static var backtickedPattern: String {
        "`([A-Za-z0-9_][A-Za-z0-9_.-]*(?:/[A-Za-z0-9_.-]+)+\\.(?:" + extensions.joined(separator: "|") + "))`"
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
    private static func matches(
        of pattern: String, in source: String, document: String
    ) -> [Citation] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        var found: [Citation] = []
        for (index, line) in source.components(separatedBy: "\n").enumerated() {
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
        var missing: [DocumentCitationGuard.Citation] = []

        for document in DocumentCitationGuard.documents(root: root) {
            let source = try String(contentsOf: document.url, encoding: .utf8)
            for citation in DocumentCitationGuard.backtickedPaths(
                in: source, document: document.relative
            ) {
                guard let head = citation.target.split(separator: "/").first,
                      prefixes.contains(String(head)) else { continue }
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
    /// scan that read no documents, or matched no citations, satisfies that perfectly. Both floors
    /// below are measured, not remembered — `find docs -name '*.md'` and the extractor itself, on
    /// this worktree, 2026-08-08 — and both sit under the measurement, because their job is to
    /// catch a sweep that found the wrong tree, not to track how the documents grow.
    ///
    /// **Per prefix, not in total.** A combined floor would let `CypressUITests` (2 citations) or
    /// `server` (1) drop out of the scan entirely while `Cypress` and `CypressTests` alone cleared
    /// the bar — and a prefix silently dropping out is precisely the failure mode the structural
    /// `dist/` rule in this file's header could otherwise introduce. Only the four large prefixes
    /// are floored: the small ones move by one when a single sentence is rewritten, and a floor
    /// that fails on ordinary editing teaches people to raise floors rather than read them.
    @Test("the sweep read the real documents and matched real citations")
    func theGuardCanSeeWhatItClaimsToCheck() throws {
        let root = AppSourceLiterals.repositoryRoot()

        let documents = DocumentCitationGuard.documents(root: root)
        #expect(
            documents.count >= 28,
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
            ("CypressTests", 30, 36), ("Cypress", 28, 34), ("Tools", 14, 17), ("docs", 12, 15)
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
        1 · a real one: `Tools/run_tests.sh` is how the suite runs.
        2 · another, nested: `docs/distilled/SCREENS.md` holds the wording.
        3 · a test symbol, slash-bearing and extensionless: `CypressTests/AX5ReflowTests`
        4 · a test symbol with a dotted member: `MapMarkerRenderingTests.clusterBadgeFollowsItsCount`
        5 · an errata range, which is not a path: `E119/E122` and `§9b/§10`
        6 · a bare filename, deliberately uncovered: `Package.swift`
        7 · a generated artifact, structurally excluded by §1: `dist/upload.sh`
        """

        let hits = DocumentCitationGuard.backtickedPaths(in: specimen, document: "specimen.md")
        #expect(
            hits.map(\.target) == ["Tools/run_tests.sh", "docs/distilled/SCREENS.md", "dist/upload.sh"],
            "the extractor reported \(hits.map(\.target))"
        )
        #expect(hits.map(\.line) == [1, 2, 7], "the extractor mislocated: \(hits.map(\.line))")

        // `dist/upload.sh` is matched here on purpose and dropped by §1's prefix rule, not by the
        // pattern. Proving that split matters: if the pattern declined it instead, §2's per-prefix
        // floors could not tell a structurally-excluded prefix from one that stopped matching.
        #expect(
            !DocumentCitationGuard.topLevelDirectories(
                root: AppSourceLiterals.repositoryRoot()
            ).contains("dist"),
            "dist/ now exists, so §1 would begin requiring generated artifacts on disk"
        )

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
