//
//  BritishSpellingGuardTests.swift
//  CypressTests
//
//  #140: "Use English spellings (eg not favourites)" — the owner meant American, and
//  they said it while looking at the app, so what a reader can see is what this guards.
//
//  Design and scope are recorded in `docs/rulings-pending/american-spelling-guard.md`.
//  Read that before widening or narrowing anything here; the short version is below.
//
//  ── What this checks, exactly ────────────────────────────────────────────────────────────────────
//  Every string literal in the **app target's own source**, read off disk. That is a superset of the
//  user-visible strings — it also sweeps SQL, log lines and gate messages — which is the point: it
//  needs no list of which literals are copy, so a string added tomorrow is covered without anybody
//  remembering to add it.
//
//  ── What it cannot check, and why saying so matters ──────────────────────────────────────────────
//  1. **Strings the app reads out of the database.** `species.id_tips` carries 18 rows of British
//     botanical prose in the shipped seed. They are user-visible and this guard is blind to them:
//     they are not literals, and their source (`Fixtures/species/curated.yaml`) cites a fetched
//     source per value and forbids hand-editing (DECISIONS constraint 15). Recorded in the ruling.
//  2. **Strings composed at runtime** by a `Formatter`, or assembled from fragments where no
//     fragment is British on its own.
//  3. **Identifiers and comments.** Renamed by hand in #140 and deliberately not guarded — see
//     `theWordListLeavesCorrectEnglishAlone` for why a symbol-level guard would need a permanent
//     exception list ("Alegreya", "flameTree", "optimistic", "specialist" all contain a British
//     spelling as a substring).
//
//  A guard that claimed to cover 1 and 2 would be claiming more than it checks, which is worse than
//  one that states its limits.
//

import Foundation
import Testing

// MARK: - The word list

/// British spellings and the American form each should take.
///
/// A **named list, not a dictionary**: it catches the forms it names. Every form that occurred in
/// this repo at #140 is here, plus the rest of each family, so the next one written is caught too.
enum BritishSpelling {

    struct Form: Sendable {
        /// Matched case-insensitively. Word boundaries appear only where a bare substring would
        /// strike correct English — each one is load-bearing and tested below.
        let pattern: String
        let american: String
    }

    static let forms: [Form] = [
        // -re → -er.  `centred` before `centre`, or "centre"+"d" suggests "centerd".
        Form(pattern: "centred", american: "centered"),
        Form(pattern: "centring", american: "centering"),
        Form(pattern: "centre", american: "center"),
        // `metre` is word-initial, or behind a metric prefix, or a camelCase hump.
        // Bare "metre" would strike "flameTree" — "fla-meTre-e".
        Form(pattern: "millimetre", american: "millimeter"),
        Form(pattern: "centimetre", american: "centimeter"),
        Form(pattern: "kilometre", american: "kilometer"),
        Form(pattern: "(?<![A-Za-z])metre", american: "meter"),
        Form(pattern: "theatre", american: "theater"),
        Form(pattern: "fibre", american: "fiber"),
        Form(pattern: "litre", american: "liter"),
        Form(pattern: "sombre", american: "somber"),
        Form(pattern: "calibre", american: "caliber"),
        // -our → -or.  favourite and neighbourhood fall out of favour and neighbour.
        Form(pattern: "favour", american: "favor"),
        Form(pattern: "neighbour", american: "neighbor"),
        Form(pattern: "colour", american: "color"),
        Form(pattern: "behaviour", american: "behavior"),
        Form(pattern: "honour", american: "honor"),
        Form(pattern: "labour", american: "labor"),
        Form(pattern: "humour", american: "humor"),
        Form(pattern: "flavour", american: "flavor"),
        Form(pattern: "harbour", american: "harbor"),
        Form(pattern: "rumour", american: "rumor"),
        Form(pattern: "savour", american: "savor"),
        Form(pattern: "vapour", american: "vapor"),
        Form(pattern: "vigour", american: "vigor"),
        Form(pattern: "odour", american: "odor"),
        Form(pattern: "parlour", american: "parlor"),
        Form(pattern: "armour", american: "armor"),
        Form(pattern: "endeavour", american: "endeavor"),
        Form(pattern: "splendour", american: "splendor"),
        Form(pattern: "rigour", american: "rigor"),
        // -ise → -ize, named stems only. A blanket -ise rule would strike "advertise",
        // "surprise", "exercise", "comprise", "premise", "expertise", "otherwise".
        // Each stem needs an ending after it, or it strikes "optimistic", "specialist",
        // "organism", "capitalism", "realistic", "generalist", "initialisms".
        Form(pattern: "recognis\(Self.verbEnding)", american: "recogniz…"),
        Form(pattern: "normalis\(Self.verbEnding)", american: "normaliz…"),
        Form(pattern: "organis\(Self.verbEnding)", american: "organiz…"),
        Form(pattern: "realis\(Self.verbEnding)", american: "realiz…"),
        Form(pattern: "customis\(Self.verbEnding)", american: "customiz…"),
        Form(pattern: "utilis\(Self.verbEnding)", american: "utiliz…"),
        Form(pattern: "apologis\(Self.verbEnding)", american: "apologiz…"),
        Form(pattern: "summaris\(Self.verbEnding)", american: "summariz…"),
        Form(pattern: "prioritis\(Self.verbEnding)", american: "prioritiz…"),
        Form(pattern: "specialis\(Self.verbEnding)", american: "specializ…"),
        Form(pattern: "categoris\(Self.verbEnding)", american: "categoriz…"),
        Form(pattern: "minimis\(Self.verbEnding)", american: "minimiz…"),
        Form(pattern: "maximis\(Self.verbEnding)", american: "maximiz…"),
        Form(pattern: "optimis\(Self.verbEnding)", american: "optimiz…"),
        Form(pattern: "standardis\(Self.verbEnding)", american: "standardiz…"),
        Form(pattern: "characteris\(Self.verbEnding)", american: "characteriz…"),
        Form(pattern: "authoris\(Self.verbEnding)", american: "authoriz…"),
        Form(pattern: "initialis\(Self.verbEnding)", american: "initializ…"),
        Form(pattern: "serialis\(Self.verbEnding)", american: "serializ…"),
        Form(pattern: "synchronis\(Self.verbEnding)", american: "synchroniz…"),
        Form(pattern: "visualis\(Self.verbEnding)", american: "visualiz…"),
        Form(pattern: "sanitis\(Self.verbEnding)", american: "sanitiz…"),
        Form(pattern: "anonymis\(Self.verbEnding)", american: "anonymiz…"),
        Form(pattern: "randomis\(Self.verbEnding)", american: "randomiz…"),
        Form(pattern: "capitalis\(Self.verbEnding)", american: "capitaliz…"),
        Form(pattern: "generalis\(Self.verbEnding)", american: "generaliz…"),
        Form(pattern: "localis\(Self.verbEnding)", american: "localiz…"),
        Form(pattern: "personalis\(Self.verbEnding)", american: "personaliz…"),
        Form(pattern: "penalis\(Self.verbEnding)", american: "penaliz…"),
        // "analysis" and "emphasis" are correct American; only the verbs move.
        //
        // `analyses` and `paralyses` are deliberately **not** matched, and this is a real limit
        // rather than an oversight: "analyses" is both the British verb (→ "analyzes") and the
        // correct American plural of "analysis", and nothing about the spelling tells them apart.
        // Matching it would put a false positive in front of anyone writing about analyses, which
        // disables a guard faster than a missed word does. "emphasises" has no such twin — the
        // noun plural is "emphases" — so it stays matched.
        Form(pattern: "analys(?=e\\b|ed|ing)", american: "analyz…"),
        Form(pattern: "emphasis(?=e|ed|es|ing)", american: "emphasiz…"),
        Form(pattern: "paralys(?=e\\b|ed|ing)", american: "paralyz…"),
        // -ce → -se nouns, -gement → -gment
        Form(pattern: "licence", american: "license"),
        Form(pattern: "defence", american: "defense"),
        Form(pattern: "offence", american: "offense"),
        Form(pattern: "pretence", american: "pretense"),
        Form(pattern: "judgement", american: "judgment"),
        Form(pattern: "acknowledgement", american: "acknowledgment"),
        // Doubled consonants Britain keeps.  `\b` on cancelled: `Task.isCancelled` is Apple's.
        Form(pattern: "labelled", american: "labeled"),
        Form(pattern: "labelling", american: "labeling"),
        Form(pattern: "\\bcancelled", american: "canceled"),
        Form(pattern: "\\bcancelling", american: "canceling"),
        Form(pattern: "travelled", american: "traveled"),
        Form(pattern: "travelling", american: "traveling"),
        Form(pattern: "traveller", american: "traveler"),
        Form(pattern: "modelling", american: "modeling"),
        Form(pattern: "modelled", american: "modeled"),
        Form(pattern: "signalling", american: "signaling"),
        Form(pattern: "levelled", american: "leveled"),
        Form(pattern: "fuelled", american: "fueled"),
        Form(pattern: "marvellous", american: "marvelous"),
        Form(pattern: "jewellery", american: "jewelry"),
        // Single → double
        Form(pattern: "enrolment", american: "enrollment"),
        Form(pattern: "instalment", american: "installment"),
        Form(pattern: "fulfilment", american: "fulfillment"),
        Form(pattern: "skilful", american: "skillful"),
        // Miscellaneous.  `\b` on grey: the body font is "AlegreyaSans-Regular", and
        // "Alegreya" carries "grey" mid-word.
        Form(pattern: "\\bgrey", american: "gray"),
        Form(pattern: "catalogue", american: "catalog"),
        Form(pattern: "catalogu(?=ed|ing)", american: "catalog…"),
        Form(pattern: "artefact", american: "artifact"),
        // Not "programmer" or "programming", which are correct American.
        Form(pattern: "programme(?=s\\b|\\b)", american: "program"),
        Form(pattern: "\\bkerb", american: "curb"),
        Form(pattern: "aluminium", american: "aluminum"),
        Form(pattern: "\\bstorey", american: "story"),
        Form(pattern: "\\bmould", american: "mold"),
        Form(pattern: "smoulder", american: "smolder"),
        Form(pattern: "draught", american: "draft"),
        Form(pattern: "\\bplough", american: "plow"),
        Form(pattern: "sceptic", american: "skeptic"),
        Form(pattern: "\\bwhilst\\b", american: "while"),
        Form(pattern: "\\bamongst\\b", american: "among"),
        Form(pattern: "practis(?=e|ed|es|ing)", american: "practic…"),
        Form(pattern: "speciality", american: "specialty"),
        Form(pattern: "orientated", american: "oriented"),
    ]

    /// The endings that make an `-ise` stem a verb rather than the start of another word.
    private static let verbEnding = "(?=e|ed|es|ing|ation|ations|er|ers|able|ably|ability)"

    /// Every British spelling in `text`, as (the form, the text that matched).
    static func offenses(in text: String) -> [(form: Form, matched: String)] {
        var found: [(Form, String)] = []
        let whole = NSRange(text.startIndex..<text.endIndex, in: text)
        for form in forms {
            guard let regex = try? NSRegularExpression(
                pattern: form.pattern, options: [.caseInsensitive]
            ) else {
                found.append((form, "<the pattern itself does not compile>"))
                continue
            }
            for match in regex.matches(in: text, range: whole) {
                if let range = Range(match.range, in: text) {
                    found.append((form, String(text[range])))
                }
            }
        }
        return found
    }
}

// MARK: - Reading the app's own source

/// The app target's source, as literals.
///
/// Reads from disk rather than from the bundle: `#filePath` is this file's absolute path at compile
/// time, and a simulator test process is an ordinary macOS process that can read it back.
enum AppSourceLiterals {

    /// The worktree root, derived from this file's own compile-time path.
    static func repositoryRoot(from file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()   // CypressTests/
            .deletingLastPathComponent()   // the worktree root
    }

    struct Literal {
        let path: String
        let line: Int
        let text: String
    }

    /// Every `.swift` file under `Cypress/`.
    static func sourceFiles(root: URL) -> [URL] {
        let appRoot = root.appendingPathComponent("Cypress")
        guard let walker = FileManager.default.enumerator(
            at: appRoot, includingPropertiesForKeys: nil
        ) else { return [] }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }.sorted {
            $0.path < $1.path
        }
    }

    /// The string literals in one file, with comments and interpolation interiors skipped.
    ///
    /// A deliberately small scanner rather than a regex: `"` inside a `//` comment, an escaped `\"`
    /// inside a literal, and a `"""` block each break the regex versions of this, and all three
    /// occur in this codebase.
    static func literals(in source: String, path: String) -> [Literal] {
        enum State { case code, line, block, string, multiline }
        var state = State.code
        var blockDepth = 0
        var out: [Literal] = []
        var buffer = ""
        var startLine = 1
        var line = 1

        let chars = Array(source)
        var i = 0

        func peek(_ s: String, _ at: Int) -> Bool {
            let t = Array(s)
            guard at + t.count <= chars.count else { return false }
            return Array(chars[at..<(at + t.count)]) == t
        }

        while i < chars.count {
            let c = chars[i]
            if c == "\n" { line += 1 }

            switch state {
            case .code:
                if peek("//", i) { state = .line; i += 2; continue }
                if peek("/*", i) { state = .block; blockDepth = 1; i += 2; continue }
                if peek("\"\"\"", i) {
                    state = .multiline; buffer = ""; startLine = line; i += 3; continue
                }
                if c == "\"" { state = .string; buffer = ""; startLine = line; i += 1; continue }
                i += 1

            case .line:
                if c == "\n" { state = .code }
                i += 1

            case .block:
                if peek("/*", i) { blockDepth += 1; i += 2; continue }
                if peek("*/", i) {
                    blockDepth -= 1
                    i += 2
                    if blockDepth == 0 { state = .code }
                    continue
                }
                i += 1

            case .string, .multiline:
                // \( … ) is code, not prose: skip to the matching paren.
                if c == "\\", peek("\\(", i) {
                    var depth = 1
                    var j = i + 2
                    while j < chars.count, depth > 0 {
                        if chars[j] == "(" { depth += 1 }
                        if chars[j] == ")" { depth -= 1 }
                        if chars[j] == "\n" { line += 1 }
                        j += 1
                    }
                    i = j
                    continue
                }
                if c == "\\" { i += 2; continue }
                if state == .string, c == "\"" {
                    out.append(Literal(path: path, line: startLine, text: buffer))
                    state = .code
                    i += 1
                    continue
                }
                if state == .string, c == "\n" {   // unterminated: bail rather than run away
                    state = .code; i += 1; continue
                }
                if state == .multiline, peek("\"\"\"", i) {
                    out.append(Literal(path: path, line: startLine, text: buffer))
                    state = .code
                    i += 3
                    continue
                }
                buffer.append(c)
                i += 1
            }
        }
        return out
    }

    /// Literals that are allowed to carry a British spelling, because they cross a boundary into
    /// data this repo did not write. Anything added here needs a reason of the same kind.
    static let contractual: Set<String> = [
        // A `seed_meta` key written by Tools/build_seed.py into the published seed file.
        // Renaming the Swift string would stop the gate finding a key that is already shipped.
        "case_normalised_columns",
        // An `id_tips` row quoted verbatim from Fixtures/species/curated.yaml, whose header cites a
        // fetched source per value and forbids hand-editing (DECISIONS constraint 15). The same
        // string is in the shipped seed, so the fixture stops being verbatim if it is corrected.
        "Dark grey to red-brown bark, fibrous and rough with irregular furrows.",
    ]
}

// MARK: - The guard

@Suite("American spellings, over every string the app ships (#140)")
struct BritishSpellingGuardTests {

    // MARK: The guard itself

    /// **The one-time job.** E182 asserted this over three strings on screen 12; this asserts it
    /// over every string literal in the app target, so a British spelling written next month is
    /// caught by a test nobody has to remember to extend.
    @Test("every string literal in the app target is spelled in American English")
    func everyAppStringLiteralIsAmerican() throws {
        let root = AppSourceLiterals.repositoryRoot()
        let files = AppSourceLiterals.sourceFiles(root: root)

        var failures: [String] = []
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let relative = file.path.replacingOccurrences(of: root.path + "/", with: "")
            for literal in AppSourceLiterals.literals(in: source, path: relative) {
                guard !AppSourceLiterals.contractual.contains(literal.text) else { continue }
                for (form, matched) in BritishSpelling.offenses(in: literal.text) {
                    failures.append(
                        "\(literal.path):\(literal.line): “\(matched)” should be "
                            + "“\(form.american)” — in \"\(literal.text.prefix(90))\""
                    )
                }
            }
        }

        #expect(
            failures.isEmpty,
            """
            \(failures.count) British spelling(s) in the app's own string literals:
            \(failures.prefix(25).joined(separator: "\n"))
            """
        )
    }

    // MARK: The guard's own provenance — it must not pass by seeing nothing

    /// This project's signature failure is a green result from a check that ran on nothing. A source
    /// scan can produce one in two ways: the tree moved after compilation, or the walk found no
    /// files. Both are failures here, never skips — a skip would read as "checked and clean".
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
            """
            the guard swept \(files.count) files; the app target had 180 at #140, so this is not \
            the app target
            """
        )

        var literals = 0
        var copyStrings = 0
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let found = AppSourceLiterals.literals(in: source, path: file.lastPathComponent)
            literals += found.count
            copyStrings += found.filter { $0.text.count > 25 && $0.text.contains(" ") }.count
        }
        #expect(literals >= 3_000, "only \(literals) literals found; the scanner is not reading")
        #expect(
            copyStrings >= 300,
            """
            only \(copyStrings) sentence-shaped literals found, so the sweep is not reaching the \
            copy it exists to check
            """
        )
    }

    /// The scanner has to actually skip what it claims to skip, or the guard is checking comments
    /// and calling them copy.
    @Test("the scanner reads literals, not comments, and not interpolated code")
    func theScannerReadsWhatItSaysItReads() {
        let source = #"""
        // a comment saying favourite
        /* a block comment saying colour */
        let a = "a real favourite"
        let b = "count: \(neighbourCount) here"
        let c = """
            a multiline favourite
            """
        let d = "an escaped \" quote and a centre"
        """#
        let found = AppSourceLiterals.literals(in: source, path: "spec.swift")
        let texts = found.map(\.text)

        #expect(texts.contains("a real favourite"))
        #expect(texts.contains { $0.contains("a multiline favourite") })
        #expect(texts.contains { $0.contains("an escaped") && $0.contains("centre") })
        #expect(
            texts.contains { $0.contains("count:") && !$0.contains("neighbour") },
            "the interpolation's identifier was read as prose: \(texts)"
        )
        #expect(
            texts.allSatisfy { !$0.contains("a comment saying") && !$0.contains("block comment") },
            "a comment was read as a string literal: \(texts)"
        )
    }

    // MARK: The word list, both ways

    /// A word list that matches nothing passes every sweep. These are the forms this repo actually
    /// carried at #140, one per family.
    @Test(
        "the word list catches the forms it names",
        arguments: [
            "favourite", "favourites", "neighbourhood", "colour", "coloured", "behaviour",
            "analyse", "analysed", "paralysed", "emphasised",
            "centre", "centred", "recentred", "metres", "millimetres", "honour", "grey",
            "greyscale", "catalogue", "catalogued", "labelled", "unlabelled", "recognised",
            "normalised", "anonymised", "organise", "judgement", "licence", "defence",
            "programme", "artefact", "kerb", "travelled", "instalment", "apologise",
            "initialiser", "specialise", "optimise", "capitalised", "whilst", "amongst",
        ]
    )
    func theWordListCatchesWhatItNames(_ british: String) {
        #expect(
            BritishSpelling.offenses(in: british).isEmpty == false,
            "“\(british)” is British and the word list does not catch it"
        )
    }

    /// **The other half, and the reason every word boundary in the list is there.** Each of these is
    /// correct English or an external name that carries a British spelling as a substring; a guard
    /// that flagged them would be turned off within a week.
    ///
    /// `AlegreyaSans-Regular` is not hypothetical — it is the app's body font, a literal in
    /// `CypressFont`, and a bare `grey` pattern goes red on it on the first run.
    @Test(
        "the word list leaves correct English alone",
        arguments: [
            "AlegreyaSans-Regular", "Alegreya", "flameTree", "flameTreeID",
            "Task.isCancelled", "isCancelled", "programmer", "programming",
            "analysis", "analyses of the record", "emphasis", "expertise", "otherwise",
            "advertise", "surprise", "exercise", "comprise", "premise", "franchise",
            "optimistic", "optimism", "specialist", "capitalism", "organism", "realistic",
            "generalist", "initialisms", "metric", "symmetrical", "concentrate", "central",
            "cancellation", "LabeledContent", "story", "curbside parking is american",
        ]
    )
    func theWordListLeavesCorrectEnglishAlone(_ correct: String) {
        let hits = BritishSpelling.offenses(in: correct)
        #expect(
            hits.isEmpty,
            """
            “\(correct)” is correct and the word list flagged \(hits.map(\.matched)) — \
            a false positive here disables the guard
            """
        )
    }

    /// Every pattern has to compile, or `offenses(in:)` silently checks nothing for that form.
    @Test("every pattern in the word list compiles")
    func everyPatternCompiles() {
        for form in BritishSpelling.forms {
            #expect(
                (try? NSRegularExpression(pattern: form.pattern, options: [.caseInsensitive])) != nil,
                "the pattern for “\(form.american)” does not compile: \(form.pattern)"
            )
        }
        #expect(BritishSpelling.forms.count >= 90, "the word list has been emptied out")
    }
}
