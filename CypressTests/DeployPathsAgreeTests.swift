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
/// **The `scope` step now has FOUR predicates, and this test derives the ones that matter rather
/// than naming them.** `DOC_ONLY` (prose), `WEB_ONLY` (tested, on ubuntu, by `web.yml`),
/// `GIT_METADATA` (root git metadata, runs but never ships) and `NO_ARCHIVE` (the union that
/// decides `ships`). Adversarial review on #162 found that this file read `DOC_ONLY` alone while
/// the step subtracted `$WEB_ONLY|$DOC_ONLY`, so one alternative added to `WEB_ONLY` could move a
/// must-RUN path into the run-nothing set and this suite still reported
/// `Test run with 2 tests in 1 suite passed`. Green, with the defect present — this project's
/// dominant test-suite defect class, in the guard that was supposed to prevent it.
///
/// The fix is not a longer list. `runNothingPredicateNames` reads the `testable=` line and checks
/// **every** predicate it finds, so the fifth one cannot be unguarded the way the third was.
///
/// **What this deliberately does NOT check:** that the regex is *correct*, only that it mentions
/// every path the trigger ignores, and that no must-RUN path is mentioned by anything that
/// decides whether the suite runs. A regex that mentions `docs/` and matches it wrongly would pass
/// here. The predicate's behavior is checked by replaying the real step over a literal path list,
/// which is a shell concern and lives in the workflow's own comments and the pull requests that
/// changed it.
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

    /// **The names of every predicate the `scope` step subtracts to decide `tests`.**
    ///
    /// Read out of the `testable=` line rather than listed here, and that is the whole point of
    /// this function. Adversarial review's finding on #162 was not that some particular predicate
    /// was wrong — it was that a predicate could be ADDED. The step said
    ///
    ///     testable="$(printf '%s\n' "$changed" | grep -vE "^($WEB_ONLY|$DOC_ONLY)" || true)"
    ///
    /// and this test read `DOC_ONLY` alone. So a widening of `WEB_ONLY` could move a must-RUN path
    /// into the run-nothing set with nothing noticing, where the same widening of `DOC_ONLY` went
    /// red. Red-proved before the fix: one alternative added to `WEB_ONLY`
    /// (`\.github/workflows/web\.yml$`) made a `web.yml`-only push `tests=false ships=false` —
    /// #212's guarantee that a pipeline change proves itself by running, gone — and this suite
    /// reported `Test run with 2 tests in 1 suite passed`.
    ///
    /// A list of predicate names in this file would have the same defect one edit later: the
    /// fifth predicate would be unguarded exactly as the third was. So the set is derived from the
    /// line that uses it, and every name in it is then checked. Adding a predicate to `testable`
    /// without an assignment this can find turns the suite red, which is the intended cost.
    static func runNothingPredicateNames(root: URL) throws -> [String] {
        let text = try String(contentsOf: root.appendingPathComponent(workflow), encoding: .utf8)
        guard let line = text.split(separator: "\n").first(where: {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("testable=")
        }) else { return [] }
        // **Only the anchored alternation is read, not the whole line.** The line also names
        // `$changed`, which is the input rather than a predicate; a first version of this scanner
        // collected it and the suite went red naming `$changed` — the control working, one edit
        // before it would have mattered. The alternation is the thing that decides membership, so
        // that is the thing parsed: everything between `^(` and the `)` that closes it.
        guard let open = line.range(of: "^(") else { return [] }
        let afterOpen = line[open.upperBound...]
        guard let close = afterOpen.firstIndex(of: ")") else { return [] }
        let alternation = afterOpen[afterOpen.startIndex..<close]

        // `$NAME` occurrences, in order, deduplicated.
        var names: [String] = []
        var current = ""
        var reading = false
        for character in alternation {
            if character == "$" {
                if reading, !current.isEmpty, !names.contains(current) { names.append(current) }
                current = ""
                reading = true
                continue
            }
            guard reading else { continue }
            if character.isLetter || character.isNumber || character == "_" {
                current.append(character)
            } else {
                if !current.isEmpty, !names.contains(current) { names.append(current) }
                current = ""
                reading = false
            }
        }
        if reading, !current.isEmpty, !names.contains(current) { names.append(current) }
        return names
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

        // ── The run-nothing set, whatever it is made of today ────────────────────────────────
        //
        // `runNothingPredicateNames` reads the `testable=` line; everything below checks every
        // name it finds. See that function for the finding this replaces — the short version is
        // that reading `DOC_ONLY` alone left `WEB_ONLY` unguarded, and enumerating the predicates
        // here would leave the next one unguarded in the same way.
        let runNothing = try Self.runNothingPredicateNames(root: root)
        var runNothingValues: [String: String] = [:]
        for name in runNothing {
            runNothingValues[name] = try Self.assignment(name, root: root)
        }

        // Controls, in the order they can go wrong. A parser that found nothing, or found names
        // with no assignments, makes every check below vacuous — which is this project's dominant
        // test-suite defect and the exact shape the finding above had.
        #expect(
            runNothing.count >= 2,
            """
            found only \(runNothing.count) predicate name(s) in \(Self.workflow)'s `testable=` \
            line \(runNothing) — the scanner is not reading the line that decides whether the \
            suite runs, so this gate passes without checking anything. Fix the scanner, not the \
            assertion.
            """
        )
        #expect(
            runNothing.contains("DOC_ONLY"),
            """
            \(Self.workflow)'s `testable=` line no longer subtracts $DOC_ONLY \(runNothing). \
            Either the prose carve-out was removed, or this scanner is reading the wrong line — \
            DOC_ONLY is the known positive that says the scanner works at all.
            """
        )
        for name in runNothing {
            #expect(
                !(runNothingValues[name] ?? "").isEmpty,
                """
                `testable=` subtracts `$\(name)` and \(Self.workflow) has no `\(name)=` assignment \
                this test can find. A predicate it cannot read is a predicate it cannot check, so \
                every absence assertion below is passing vacuously for that one. Either the \
                assignment moved off its own first line, or a new predicate arrived without \
                telling this gate about it.
                """
            )
        }

        // **`GIT_METADATA` must NOT be one of them.** A root `.gitignore` or `.gitattributes` is
        // in the run-but-do-not-ship set for the reason `.github/` is: it cannot reach the archive,
        // and `DocumentCitationGuardTests` reasons about what a fresh clone contains, so a change
        // to what this repository tracks proves itself by running. Moving it into `testable`'s
        // subtraction would skip the suite for it.
        #expect(
            !runNothing.contains("GIT_METADATA"),
            """
            `testable=` now subtracts $GIT_METADATA, so a change to a root .gitignore or \
            .gitattributes would SKIP the entire suite and `gate` would report success having \
            tested nothing. GIT_METADATA belongs in NO_ARCHIVE only — it is the run-but-do-not-ship \
            set, the same as .github/ and the two test directories.
            """
        )
        // …and it must still be in NO_ARCHIVE, interpolated by name like the other two. This is
        // the assertion that keeps 57b93e4 from being undone: without it a root .gitignore ships,
        // and merging a diff that touches one mints a TestFlight build byte-identical to the last.
        #expect(
            noArchive.contains("$GIT_METADATA"),
            """
            NO_ARCHIVE no longer interpolates $GIT_METADATA. That restores the defect 57b93e4 \
            fixed, which was found inside the pull request written to prevent it: a diff touching \
            a root .gitignore or .gitattributes would mint a TestFlight build whose app is \
            byte-identical to the last one (#212 / #215 / #31).
            """
        )
        #expect(
            !(try Self.assignment("GIT_METADATA", root: root)).isEmpty,
            "found no `GIT_METADATA=` assignment in \(Self.workflow)'s `scope` step (see above)"
        )
        for name in runNothing {
            #expect(
                noArchive.contains("$\(name)"),
                """
                NO_ARCHIVE does not interpolate $\(name), which `testable=` subtracts. The \
                containment that makes `ships=true` imply `tests=true` is broken: a path can now \
                be buildable without being testable, and the release job becomes reachable by a \
                run whose suite did not execute. That is #215's shape exactly — two literals \
                where there should be one derivation.
                """
            )
        }

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
        //
        // The three harness scripts are #153. Their exemption rests on the same fact as the test
        // directories' — the scheme's only buildable is the app — plus one more: `project.pbxproj`
        // has no `PBXShellScriptBuildPhase`, so nothing under `Tools/` runs during a build. That
        // second half is asserted in its own test below rather than described here, because it is
        // the one that could change without anyone thinking about this file. **`Tools/` is
        // deliberately NOT exempted broadly: `Tools/fetch_seed.sh` runs in every CI job and places
        // the seed the app bundles, so it is a genuine build input and must keep shipping.**
        // `server/` is #156. The fact that carries it is **membership**: the project uses
        // `PBXFileSystemSynchronizedRootGroup`, and the three groups are `Cypress`,
        // `CypressTests` and `CypressUITests` — `server/` is in none of them, so nothing under it
        // is an archive input. Note what does NOT carry it: "not referenced by project.pbxproj"
        // is equally true of every file that DOES ship, because that file names no sources at all
        // (#157's reviewer calibrated this: `APIError.swift` → 0 hits). Nothing yet asserts the
        // synchronized-group list; until something does, this bullet is the weakest of the four.
        for (token, ticket, change) in [
            ("\\.github/", "#212", "a pipeline-only change"),
            ("CypressTests/", "#215", "a unit-test-only change"),
            ("CypressUITests/", "#215", "a UI-test-only change"),
            ("server/", "#156", "a Go-service-only change"),
            ("Tools/ui-test-shards\\.txt$", "#31", "a shard-list-only change"),
            ("Tools/run_tests\\.sh$", "#153", "a test-runner-only change"),
            ("Tools/verify_test_log\\.sh$", "#153", "a log-judge-only change"),
            ("Tools/test_harness_guards\\.sh$", "#153", "a harness-seam-only change"),
        ] {
            // Compared as a WHOLE ALTERNATIVE, not as a substring. A bare `contains` is a
            // substring test, and `"Tools/observer/".contains("server/")` is true — a lookalike
            // token satisfies the loop while the predicate ships every Go-only push, which is
            // what #157's reviewer demonstrated end to end.
            //
            // Two details, both of which bit the first attempt at this fix and were caught by
            // this very assertion. The alternation's FIRST alternative has no `|` in front of it,
            // so the haystack is prefixed with one before the search. And the tokens must be
            // spelled the way the assignment spells them — `\.github/` escaped, not `.github/` —
            // because that is what an alternative-for-alternative comparison means.
            #expect(
                ("|" + noArchive).contains("|" + token),
                """
                NO_ARCHIVE no longer mentions `\(token)`. That restores \(ticket) exactly: \
                \(change) would mint a build whose app is byte-identical to the last one, expiring \
                the build before it and notifying every tester about nothing.
                """
            )
            // And the converse, which is the newer half: these must NOT be in ANY predicate that
            // `testable=` subtracts. Putting one there would skip the suite for a change to the
            // pipeline or to the tests themselves — a green required check over code nothing ran.
            //
            // **Checked against every run-nothing predicate, not against DOC_ONLY alone**, which
            // is #162's B1. Compared as a plain substring on purpose, unlike the presence check
            // above: for an ABSENCE assertion a substring match is the strict direction, so a
            // token buried inside a longer alternative (`\.github/workflows/web\.yml$` containing
            // `\.github/`) still fires.
            for name in runNothing {
                let value = runNothingValues[name] ?? ""
                #expect(
                    !value.contains(token),
                    """
                    \(name) now mentions `\(token)`, and `testable=` subtracts $\(name), so \
                    \(change) would SKIP the entire suite and `gate` would report success having \
                    tested nothing. \(ticket) is what that costs. \(token) belongs in NO_ARCHIVE, \
                    which is the run-but-do-not-ship set — never in a predicate that decides \
                    whether the suite runs at all.
                    """
                )
            }
        }
    }

    /// **The premise under two separate exemptions, pinned instead of asserted in prose (#153).**
    ///
    /// Two things in this repository are true because no target shells out during a build:
    ///
    /// 1. `NO_ARCHIVE` exempts `Tools/run_tests.sh`, `Tools/verify_test_log.sh` and
    ///    `Tools/test_harness_guards.sh` — they cannot reach the archive, so a change to them
    ///    must not mint a TestFlight build byte-identical to the last (#1, #215, #31);
    /// 2. `Tools/run_tests.sh`'s collision guard skips its own ancestor chain on the ground that
    ///    "no real xcodebuild can be an ancestor of this script" (E283). Adversarial review built
    ///    a process whose `ps` line was a real build's and which WAS an ancestor, and the guard
    ///    passed it silently — correctly, and only because that premise holds.
    ///
    /// A `PBXShellScriptBuildPhase` breaks both at once, quietly: a script phase can run anything
    /// in `Tools/` as part of the build, which makes those files archive inputs and makes an
    /// `xcodebuild` a legitimate ancestor of whatever it launches. Nothing else in the repository
    /// notices. This test is the notice.
    ///
    /// It says nothing about whether a script phase would be a good idea. It says that adding one
    /// is a decision that has to visit two other places, and names them.
    @Test("no build phase shells out, which is what two exemptions rest on")
    func theProjectRunsNoShellScriptBuildPhase() throws {
        let root = AppSourceLiterals.repositoryRoot()
        let pbxproj = root.appendingPathComponent("Cypress.xcodeproj/project.pbxproj")
        let text = try String(contentsOf: pbxproj, encoding: .utf8)

        // The control first: a read that came back empty, or a file that is no longer a project
        // file, would make the assertion below pass while checking nothing — the vacuous-guard
        // shape this repository has shipped before.
        #expect(
            text.contains("PBXNativeTarget"),
            """
            \(pbxproj.path) does not read as an Xcode project file (no `PBXNativeTarget`), so the \
            assertion below is passing without checking anything. Fix the path, not the assertion.
            """
        )

        #expect(
            !text.contains("PBXShellScriptBuildPhase"),
            """
            `Cypress.xcodeproj/project.pbxproj` now has a `PBXShellScriptBuildPhase`, and two \
            things elsewhere assume it does not. (1) `.github/workflows/testflight.yml` exempts \
            Tools/run_tests.sh, Tools/verify_test_log.sh and Tools/test_harness_guards.sh from \
            minting a build because nothing in Tools/ can reach the archive — if the new phase \
            runs any of them, that exemption is now wrong and a change to them ships untested \
            code as an unchanged app. (2) Tools/run_tests.sh's collision guard skips its whole \
            ancestor chain because no real xcodebuild can be an ancestor of it (E283) — if the \
            new phase invokes run_tests.sh, one now can, and a genuine second build on the same \
            simulator would go undetected. Decide both before deleting this test.
            """
        )
    }
}
