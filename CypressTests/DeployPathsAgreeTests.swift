import Foundation
import Testing

/// **The deploy deny-list is written twice, and this is what stops the copies from drifting.**
///
/// `.github/workflows/testflight.yml` states the same fact in two places, because GitHub gives no
/// way to state it once:
///
/// 1. `on.push.paths-ignore` — which pushes start a run at all;
/// 2. the `ships` step's regex — which runs, having started, are allowed to mint a build.
///
/// They answer different questions and must cover the same paths. Add `Fixtures/**` to the trigger
/// and forget the predicate, and a `Fixtures`-only push quietly starts shipping builds again — the
/// #212 defect, restored by an edit nobody would think to connect to it. Add it to the predicate
/// and forget the trigger, and nothing breaks, which is worse: the drift sits there until the day
/// the other half matters.
///
/// This is the same argument `Tools/ui-test-shards.txt` makes for the shard matrix — a second copy
/// of a fact is a false green waiting for someone to edit one of them. There the matrix is derived;
/// here it cannot be, so the agreement is asserted instead.
///
/// **What this deliberately does NOT check:** that the regex is *correct*, only that it mentions
/// every path the trigger ignores. A regex that mentions `docs/` and matches it wrongly would pass
/// here. The predicate's behavior is checked by replaying it over real history, which is a shell
/// concern and lives in the workflow's own comments.
@Suite("The deploy deny-list agrees with the ships predicate")
struct DeployPathsAgreeTests {

    static let workflow = ".github/workflows/testflight.yml"

    /// The `paths-ignore` entries under `on.push`, as written.
    ///
    /// Read by line rather than by parsing YAML: this repo has no YAML dependency and will not gain
    /// one for a test. The scan is anchored on `paths-ignore:` and stops at the first line that is
    /// not a list item, which is the shape the file has and the shape a reviewer would notice
    /// changing.
    static func pathsIgnore(root: URL) throws -> [String] {
        let text = try String(contentsOf: root.appendingPathComponent(workflow), encoding: .utf8)
        var entries: [String] = []
        var inList = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "paths-ignore:" { inList = true; continue }
            guard inList else { continue }
            guard trimmed.hasPrefix("- ") else { break }
            entries.append(
                trimmed.dropFirst(2).trimmingCharacters(in: CharacterSet(charactersIn: "'\" "))
            )
        }
        return entries
    }

    /// The right-hand side of a shell assignment in the `scope` step, e.g. `DOC_ONLY='…'`.
    ///
    /// Matched on the assignment rather than on a `grep` line, because the two predicates are now
    /// built from named variables and used further down. Quotes are stripped; the value is
    /// returned as written otherwise.
    static func assignment(_ name: String, root: URL) throws -> String {
        let text = try String(contentsOf: root.appendingPathComponent(workflow), encoding: .utf8)
        guard let line = text.split(separator: "\n").first(where: {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("\(name)=")
        }) else { return "" }
        let value = line.drop { $0 != "=" }.dropFirst()
        return value.trimmingCharacters(in: CharacterSet(charactersIn: "'\" "))
    }

    /// What a `paths-ignore` glob must leave a trace of in the predicate.
    ///
    /// `docs/**` → `docs/`, `graphify-out/**` → `graphify-out/`, `*.md` → `.md`. Everything up to
    /// the first `*`, or the extension when the glob leads with one.
    static func token(for glob: String) -> String {
        if let star = glob.firstIndex(of: "*") {
            let head = String(glob[glob.startIndex..<star])
            return head.isEmpty ? String(glob[glob.index(after: star)...]) : head
        }
        return glob
    }

    @Test("every ignored path is also a path that mints no build")
    func theTwoListsAgree() throws {
        let root = AppSourceLiterals.repositoryRoot()
        let ignored = try Self.pathsIgnore(root: root)
        let docOnly = try Self.assignment("DOC_ONLY", root: root)
        let noArchive = try Self.assignment("NO_ARCHIVE", root: root)

        // Controls. Any read coming back empty would make every check below vacuous — the
        // failure shape ARCHITECTURE §7 records and #93 shipped once already.
        #expect(
            ignored.count >= 3,
            """
            found only \(ignored.count) paths-ignore entries in \(Self.workflow) — the scanner is \
            not reading the trigger, so this gate passes without checking anything
            """
        )
        #expect(
            !docOnly.isEmpty,
            """
            found no `DOC_ONLY=` assignment in \(Self.workflow)'s `scope` step. Either it was \
            renamed — in which case this gate needs to be told the new name, and is passing \
            without checking anything until it is — or the whole two-question derivation was \
            removed.
            """
        )
        #expect(
            !noArchive.isEmpty,
            "found no `NO_ARCHIVE=` assignment in \(Self.workflow)'s `scope` step (see above)"
        )

        // **`NO_ARCHIVE` must be DERIVED from `DOC_ONLY`, not repeat it.** This is the assertion
        // that keeps a third copy of the deny-list from appearing. Written as two literals, the
        // pair drifts — that is #215, which happened within a day of the pair being created.
        #expect(
            noArchive.contains("$DOC_ONLY"),
            """
            NO_ARCHIVE no longer interpolates $DOC_ONLY, so the doc deny-list is now written twice \
            inside one shell step. Whichever copy someone edits next, the other is the bug: the \
            suite would skip a change it should test, or mint a build for prose. Build NO_ARCHIVE \
            by extending DOC_ONLY.
            """
        )

        for glob in ignored {
            let token = Self.token(for: glob)
            #expect(
                docOnly.contains(token),
                """
                `\(glob)` is ignored by the push trigger but DOC_ONLY never mentions `\(token)`. \
                The two lists have drifted, and both directions are broken: a push touching only \
                \(glob) starts no run, while a PR touching only \(glob) runs the entire 26-minute \
                suite it was meant to skip — and, alongside a .github/ change, would mint a build \
                whose app is byte-identical to the last (#212). Add it to DOC_ONLY.
                """
            )
        }

        // Four paths are in the predicate and deliberately NOT in the trigger, because for them
        // the two questions have different answers: they must RUN and must not SHIP. The check
        // above only runs trigger → predicate, so nothing there would notice one of these being
        // deleted. Named individually so that removing one is a decision someone had to make.
        //
        // `.github/` is #212 — a pipeline change proves itself by running, and that rule caught the
        // wrong SDK, the wrong simulator name and the tag permission.
        //
        // The two test directories are #215, and their exemption is a fact about the scheme rather
        // than a judgement: `Cypress.xcscheme` has exactly one `BuildActionEntry`, the app target,
        // `buildForArchiving="YES"`. Nothing under them is an archive input. **If that stops being
        // true — a test target becomes an app dependency, a fixture gets bundled — this assertion
        // is the wrong one and should be deleted along with the tokens.** It is guarding the
        // predicate, not the scheme.
        //
        // `Tools/ui-test-shards\.txt$` is #31 — build 16 shipped byte-identical to build 15 when a
        // shard-list-only change slipped through unexempted. The token is matched with its own
        // escaping and anchor intact (`\.txt$`, not a bare `.txt`) rather than a loose prefix like
        // the other three, because unlike a directory this is a single file: a token that dropped
        // the anchor (`Tools/ui-test-shards.txt` with an unescaped dot) would still read as present
        // by a plain substring check even after silently widening to match a lookalike path or a
        // directory of the same name — the exact regex text is the thing #31 depends on, so this
        // assertion checks for exactly that text.
        for (token, ticket, change) in [
            (".github/", "#212", "a pipeline-only change"),
            ("CypressTests/", "#215", "a unit-test-only change"),
            ("CypressUITests/", "#215", "a UI-test-only change"),
            ("Tools/ui-test-shards\\.txt$", "#31", "a shard-list-only change"),
        ] {
            #expect(
                noArchive.contains(token),
                """
                NO_ARCHIVE no longer mentions `\(token)`. That restores \(ticket) exactly: \
                \(change) would mint a build whose app is byte-identical to the last one, expiring \
                the build before it and notifying every tester about nothing.
                """
            )
            // And the converse, which is the newer half: these three must NOT be in DOC_ONLY.
            // Putting one there would skip the suite for a change to the pipeline or to the tests
            // themselves — a green required check over code nothing ran.
            #expect(
                !docOnly.contains(token),
                """
                DOC_ONLY now mentions `\(token)`, so \(change) would SKIP the entire suite and \
                `gate` would report success having tested nothing. Only prose belongs in \
                DOC_ONLY; \(token) belongs in NO_ARCHIVE, which is the run-but-do-not-ship set.
                """
            )
        }
    }
}
