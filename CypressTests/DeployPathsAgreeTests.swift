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

    /// The line carrying the `ships` predicate's regex.
    static func shipsPredicate(root: URL) throws -> String {
        let text = try String(contentsOf: root.appendingPathComponent(workflow), encoding: .utf8)
        let line = text.split(separator: "\n").first { $0.contains("grep -vE") && $0.contains(".github/") }
        return line.map(String.init) ?? ""
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
        let predicate = try Self.shipsPredicate(root: root)

        // Controls. Either read coming back empty would make every check below vacuous — the
        // failure shape ARCHITECTURE §7 records and #93 shipped once already.
        #expect(
            ignored.count >= 3,
            """
            found only \(ignored.count) paths-ignore entries in \(Self.workflow) — the scanner is \
            not reading the trigger, so this gate passes without checking anything
            """
        )
        #expect(
            !predicate.isEmpty,
            """
            found no `grep -vE` line mentioning .github/ in \(Self.workflow) — either the ships \
            predicate was removed, in which case every push mints a build again, or it moved and \
            this gate needs to be told where to.
            """
        )

        for glob in ignored {
            let token = Self.token(for: glob)
            #expect(
                predicate.contains(token),
                """
                `\(glob)` is ignored by the push trigger but the ships predicate never mentions \
                `\(token)`. The two lists have drifted: a push touching only \(glob) would start no \
                run — or, alongside a .github/ change, would start one AND mint a build whose app \
                is byte-identical to the last (#212). Add it to the predicate in the `ships` step.
                """
            )
        }

        // Three paths are in the predicate and deliberately NOT in the trigger, because for them
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
        for (token, ticket, change) in [
            (".github/", "#212", "a pipeline-only change"),
            ("CypressTests/", "#215", "a unit-test-only change"),
            ("CypressUITests/", "#215", "a UI-test-only change"),
        ] {
            #expect(
                predicate.contains(token),
                """
                the ships predicate no longer mentions `\(token)`. That restores \(ticket) exactly: \
                \(change) would mint a build whose app is byte-identical to the last one, expiring \
                the build before it and notifying every tester about nothing.
                """
            )
        }
    }
}
