import Foundation
import Testing

/// **A backtick inside a double-quoted shell string is command substitution, and CI is where that
/// goes unnoticed longest.**
///
/// `.github/workflows/testflight.yml` shipped this on 2026-08-04:
///
/// ```bash
/// echo "::notice::… The suite is skipped deliberately and `gate` checks that it was skipped …"
/// ```
///
/// The author meant the backticks as markdown emphasis. The shell read them as a command: it ran
/// `gate`, got nothing, and substituted the empty string — so the notice a reader actually saw said
/// "skipped deliberately and ␣ checks that it was skipped". The word was **deleted from the output
/// without any error anywhere.**
///
/// That instance was harmless. The class is not, and it fails in two ways at once:
///
/// 1. **It silently edits the text.** Nobody proof-reads a notice against its source, so the
///    workflow says one thing and the log says another, indefinitely.
/// 2. **It executes whatever it contains.** `` `gate` `` is a missing command; a phrase that
///    happens to name a real one runs it on the runner, in a job that holds `contents: write`.
///
/// Neither is caught by anything else here: the YAML parses, the shell exits zero, and the job goes
/// green. This is the same family as the zsh word-splitting traps in CLAUDE.md — a difference
/// between what the text looks like and what the shell does with it, invisible in review.
///
/// **The fix is always to reword, never to escape.** These are human-readable notices; there is no
/// reason for a backtick to be in one. Say `the gate job`.
///
/// Single quotes are deliberately allowed: inside `'…'` a backtick is a literal, so `echo '…`x`…'`
/// prints the backticks and runs nothing. Only double-quoted strings are scanned.
@Suite("Workflow shell strings do not run commands by accident")
struct WorkflowShellQuotingTests {

    static let workflowDirectory = ".github"

    /// Every `.yml` under `.github/`, so a new workflow or composite action is covered the day it
    /// is added rather than the day someone remembers to list it here.
    ///
    /// **Enumerated URLs are resolved before they leave this function (#229).** `noAccidentalCommandSubstitution`
    /// below computes each offender's displayed path with
    /// `file.path.replacingOccurrences(of: root.path + "/", with: "")` — `root` arrives resolved
    /// from `AppSourceLiterals.repositoryRoot()`, but `FileManager`'s enumerator hands back its own
    /// spelling regardless, and an unresolved/resolved mismatch there does not fail safe: the
    /// shorter, unresolved needle still matches one component in from the front of the longer,
    /// resolved path, and `replacingOccurrences` removes that inner match rather than reporting no
    /// match at all — see `AppSourceLiterals.sourceFiles` for the exact worked example this mirrors.
    /// Resolving here keeps a future offender's `file:line` readable instead of garbled.
    static func workflowFiles(root: URL) throws -> [URL] {
        let dir = root.appendingPathComponent(workflowDirectory).resolvingSymlinksInPath()
        guard let walker = FileManager.default.enumerator(
            at: dir, includingPropertiesForKeys: nil
        ) else { return [] }
        return walker.compactMap { $0 as? URL }
            .map { $0.resolvingSymlinksInPath() }
            .filter { $0.pathExtension == "yml" }
    }

    /// Whether `line` contains a backtick inside a double-quoted span.
    ///
    /// Scanned character by character rather than by regular expression: a regex for "quoted span"
    /// has to decide what an escaped quote is, and getting that subtly wrong yields a gate that
    /// passes because it matched nothing — the vacuous-green shape ARCHITECTURE §7 records. A
    /// left-to-right walk tracking one bit of state has no such failure mode.
    ///
    /// A `#` outside quotes starts a YAML comment, and the prose in this file's comments is full of
    /// backticks — including the ones documenting this very bug. Comments stop the scan.
    static func hasBacktickInDoubleQuotes(_ line: String) -> Bool {
        var inSingle = false, inDouble = false, previous: Character = " "
        for character in line {
            let escaped = previous == "\\"
            defer { previous = escaped ? " " : character }
            if escaped { continue }
            switch character {
            case "'" where !inDouble: inSingle.toggle()
            case "\"" where !inSingle: inDouble.toggle()
            case "#" where !inSingle && !inDouble: return false
            case "`" where inDouble: return true
            default: break
            }
        }
        return false
    }

    @Test("no workflow runs a command it meant to quote")
    func noAccidentalCommandSubstitution() throws {
        let root = AppSourceLiterals.repositoryRoot()
        let files = try Self.workflowFiles(root: root)

        // Control. An empty file list would make the scan below pass without reading anything —
        // and this gate lives or dies on actually finding the files.
        #expect(
            files.count >= 2,
            """
            found only \(files.count) .yml files under \(Self.workflowDirectory)/ — expected at \
            least the TestFlight workflow and the prepare action. The walker is not reading the \
            directory, so this gate passes without checking anything.
            """
        )

        var offenders: [String] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            where Self.hasBacktickInDoubleQuotes(String(line)) {
                let name = file.path.replacingOccurrences(of: root.path + "/", with: "")
                offenders.append("\(name):\(index + 1)")
            }
        }

        #expect(
            offenders.isEmpty,
            """
            a backtick appears inside a double-quoted shell string at \(offenders.joined(separator: ", ")). \
            The shell will run whatever is between the backticks and substitute its output, so the \
            text is silently edited and something executes on the runner. Reword it — say `the gate \
            job` rather than backticks — instead of escaping. Single quotes are fine if you truly \
            need the character.
            """
        )
    }

    /// The scanner itself, checked against cases whose answers are known.
    ///
    /// Without this, the gate above is one bad branch away from being a function that always returns
    /// false — which is indistinguishable from a clean repository. CLAUDE.md's rule: calibrate the
    /// instrument before trusting the reading.
    @Test("the scanner distinguishes the cases it is claiming to distinguish")
    func scannerIsCalibrated() {
        let cases: [(String, Bool, String)] = [
            (#"echo "the `gate` job""#,          true,  "the shipped bug"),
            (#"echo "plain text""#,              false, "no backtick at all"),
            (#"echo 'the `gate` job'"#,          false, "single quotes make it a literal"),
            (#"# a comment about `gate`"#,       false, "a whole-line YAML comment"),
            (#"echo "ok"  # see `gate` above"#,  false, "a trailing comment after a clean string"),
            (#"echo "a" && echo "the `x` b""#,   true,  "second string on the line"),
            (#"run: echo "$(date)""#,            false, "$( ) is not a backtick"),
            (#"echo "\`escaped\`""#,             false, "an explicitly escaped backtick"),
        ]
        for (line, expected, why) in cases {
            #expect(
                Self.hasBacktickInDoubleQuotes(line) == expected,
                """
                the scanner is wrong about \(why): expected \(expected) for `\(line)`. Until this \
                passes, the gate above proves nothing about the workflows.
                """
            )
        }
    }
}
