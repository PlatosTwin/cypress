//
//  VitalityRubricTests.swift
//  Cypress — CypressTests
//
//  Ticket #261. Two things this file has to hold, and they are different in kind.
//
//  1. **The quantity.** Each class's dieback band is its operational definition — it is what makes
//     level 1 level 1 — and RULINGS R13 reserves a class's meaning to `PRODUCT.md`. The band is a
//     fact; the register it is written in is `SCREENS.md`'s and is not this file's business.
//  2. **The agreement.** The whole purpose of #261 is that `Vitality.anchor`, `PRODUCT.md` §3 and
//     `SCREENS.md` 05 §3 state one rubric instead of two. A prose note in each document asks a
//     future reader to notice a drift; §2 below refuses to let one land.
//
//  ── What the first version of this file got wrong, because the shape recurs ──────────────────
//  `VitalityBand` used to carry `percents` and a hand-written `phrase` as two independent fields,
//  and `everyClassStatesItsBand` computed the correct phrase from `percents` and then used it only
//  in the failure message. PR #59's reviewer set `.fair`'s anchor to "10 to 25%…" with a matching
//  `phrase`, left `percents: 11...25`, and got four green tests while 10 percent was once again
//  claimed by two rows — the exact defect this suite exists to prevent, under a green suite. **A
//  guard that computes the truth and does not assert on it is indistinguishable from one that
//  works.** The band statement is now derived from `percents` and nothing else, so the anchor and
//  the range cannot be edited into agreement with each other while both drift from the rubric.
//

import Foundation
import Testing

@testable import Cypress

// MARK: - How a band must be stated

/// The claim an anchor sentence has to make to own a band, derived from the band itself.
///
/// **Derived, never authored beside the range.** If this were a string written next to `percents`,
/// the two could be edited into agreement and both drift; that is the failure recorded in the file
/// header. Every case below is a predicate over what the sentence *asserts*, not over how it is
/// worded, so a re-word that keeps the quantity passes and a re-word that loses it does not.
private enum BandStatement: Sendable {

    /// No dieback at all. The sentence must negate dead wood and must name no percentage.
    case none
    /// The top of the scale, open-ended above half. "Over half", "more than half" and "over 50%"
    /// are the same claim.
    case moreThanHalf
    /// A closed band. The sentence must name both endpoints, in order, as a percentage.
    case range(low: Int, high: Int)

    static func forPercents(_ percents: ClosedRange<Int>) -> BandStatement {
        if percents == 0...0 { return .none }
        if percents.upperBound == 100 { return .moreThanHalf }
        return .range(low: percents.lowerBound, high: percents.upperBound)
    }

    /// What a reader of the failure message needs: the claim in words.
    var described: String {
        switch self {
        case .none: return "no dieback at all, stated as such and with no percentage"
        case .moreThanHalf: return "more than half the crown"
        case .range(let low, let high): return "the band \(low) to \(high)%"
        }
    }

    func isStated(by anchor: String) -> Bool {
        switch self {
        case .none:
            return !anchor.contains("%") && Self.matches(Self.negatedDeadWood, anchor)
        case .moreThanHalf:
            return Self.matches(Self.overHalf, anchor)
        case .range(let low, let high):
            let separator = #"\s*(?:to|-|\#u{2013}|\#u{2014})\s*"#
            return Self.matches(#"\b\#(low)\#(separator)\#(high)\s*%"#, anchor)
        }
    }

    /// "no … dead wood", "none of the crown is dead", "zero dieback" — the negation and the noun in
    /// the same clause, so a sentence that merely contains the word "no" elsewhere does not qualify.
    private static let negatedDeadWood = #"\b(?:no|none|zero)\b[^;.]*\b(?:dead wood|dieback|dead)\b"#

    /// "over half", "more than half", "over 50%".
    private static let overHalf = #"\b(?:over|more than)\s+(?:half|50\s*%)"#

    private static func matches(_ pattern: String, _ subject: String) -> Bool {
        guard let expression = try? NSRegularExpression(
            pattern: pattern, options: [.caseInsensitive]
        ) else { return false }
        let range = NSRange(location: 0, length: (subject as NSString).length)
        return expression.firstMatch(in: subject, range: range) != nil
    }
}

/// One class of the rubric and the whole percents of crown dieback it claims. Ticket #261,
/// Candidate A. The sentence it must state is `statement`, which is a function of `percents`.
private struct VitalityBand: Sendable, CustomStringConvertible {
    let vitality: Vitality
    let percents: ClosedRange<Int>

    var statement: BandStatement { .forPercents(percents) }
    var description: String { "\(vitality.classNumber) \u{00b7} \(vitality.label)" }
}

// MARK: - Reading the rubric back out of the distilled documents

/// The two markdown tables that are supposed to say what `Vitality.anchor` says.
///
/// A parser rather than a copy of the text, deliberately: a fixture holding the five sentences a
/// third time would go stale on its own and would not notice a document drifting, which is the
/// failure being guarded. The column is found by its **header** (`Anchor …`), not by position, so
/// the two tables' different shapes — `PRODUCT.md` carries a trailing band column, `SCREENS.md`
/// carries a title column — need no per-document arithmetic.
enum RubricTable {

    struct ParseFailure: Error, CustomStringConvertible {
        let reason: String
        var description: String { reason }
    }

    /// Every `| level | … | anchor | …` row of the first table inside the section headed `heading`.
    ///
    /// Cells are trimmed and unwrapped from backticks, because `SCREENS.md` quotes its copy strings
    /// and `PRODUCT.md` does not, and that difference is presentation rather than content.
    static func anchors(underHeading heading: String, in markdown: String) throws -> [Int: String] {
        let lines = markdown.components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: { $0.hasPrefix(heading) }) else {
            throw ParseFailure(reason: "no line begins \u{201c}\(heading)\u{201d}")
        }
        let rest = lines[(start + 1)...]
        let end = rest.firstIndex { $0.hasPrefix("#") } ?? rest.endIndex
        let section = rest[..<end]

        let rows = section.filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("|") }
        guard let header = rows.first else {
            throw ParseFailure(reason: "the section headed \u{201c}\(heading)\u{201d} has no table")
        }
        guard let column = cells(of: header).firstIndex(where: { $0.hasPrefix("Anchor") }) else {
            throw ParseFailure(
                reason: "no column of \u{201c}\(heading)\u{201d}'s table is headed \u{201c}Anchor\u{201d}"
                    + " — its header row reads \(cells(of: header))"
            )
        }

        var found: [Int: String] = [:]
        for row in rows.dropFirst() {
            let cells = cells(of: row)
            guard cells.count > column, let level = Int(cells[0]), (1...5).contains(level) else {
                continue
            }
            found[level] = cells[column]
        }
        return found
    }

    private static func cells(of row: String) -> [String] {
        let parts = row.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count > 2 else { return [] }
        return parts.dropFirst().dropLast().map {
            $0.trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "`"))
        }
    }
}

// MARK: - The suite

@Suite("Vitality rubric")
struct VitalityRubricTests {

    fileprivate static let bands: [VitalityBand] = [
        VitalityBand(vitality: .thriving, percents: 0...0),
        VitalityBand(vitality: .good, percents: 1...10),
        VitalityBand(vitality: .fair, percents: 11...25),
        VitalityBand(vitality: .poor, percents: 26...50),
        VitalityBand(vitality: .severeDecline, percents: 51...100),
    ]

    private static let productHeading = "### Vitality scale"
    private static let screensHeading = "#### 05 \u{00b7} Light check-in"

    private static func document(_ relative: String) throws -> String {
        let url = AppSourceLiterals.repositoryRoot().appendingPathComponent(relative)
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - 1. The bands, and the copy that has to state them

    /// The assertion is on the derived statement. Nothing in this suite holds a phrase that could
    /// be edited to match a drifting anchor — see the file header for what that cost once.
    @Test("every class's anchor states the band that class claims", arguments: VitalityRubricTests.bands)
    fileprivate func everyClassStatesItsBand(band: VitalityBand) {
        let message =
            "\(band) claims \(band.percents.lowerBound)\u{2013}\(band.percents.upperBound)% crown "
            + "dieback, so its anchor has to state \(band.statement.described). It reads "
            + "\u{201c}\(band.vitality.anchor)\u{201d}. A class's band is its operational definition "
            + "(RULINGS R13 reserves a class's meaning to PRODUCT.md); a rater holding a percentage "
            + "must find the row that names it."
        #expect(band.statement.isStated(by: band.vitality.anchor), "\(message)")
    }

    @Test("the band table names all five classes, worst first")
    func theTableCoversTheRubric() {
        #expect(Self.bands.map(\.vitality) == Array(Vitality.rubric.reversed()))
    }

    @Test("every whole percent from 0 to 100 belongs to exactly one class")
    func bandsPartitionTheWholePercents() {
        for percent in 0...100 {
            let owners = Self.bands.filter { $0.percents.contains(percent) }
            let named: String = owners.map(\.description).joined(separator: ", ")
            let consequence: String = owners.isEmpty ? "no row to tap" : "more than one row that fits"
            let message: String =
                "\(percent)% crown dieback is claimed by \(owners.count) classes (\(named)). "
                + "A rater who reads that value off a crown has \(consequence)."
            #expect(owners.count == 1, "\(message)")
        }
    }

    // MARK: - 2. The three sources state one rubric

    /// The fork #261 closed, held shut.
    ///
    /// `PRODUCT.md` §3 and `SCREENS.md` 05 §3 disagreed on all five sentences from the day both were
    /// distilled — two handoff artifacts, each transcribed faithfully — and the app drew one of
    /// them. Nothing detected that for two weeks, because nothing in the repository read the two
    /// tables. The failure below names **which** of the three sources moved, because "they disagree"
    /// is not actionable when there are three of them.
    @Test("Vitality.swift, PRODUCT \u{a7}3 and SCREENS 05 \u{a7}3 state the same five anchors")
    func allThreeSourcesStateTheSameRubric() throws {
        let product = try RubricTable.anchors(
            underHeading: Self.productHeading, in: Self.document("docs/distilled/PRODUCT.md")
        )
        let screens = try RubricTable.anchors(
            underHeading: Self.screensHeading, in: Self.document("docs/distilled/SCREENS.md")
        )

        for vitality in Vitality.rubric {
            let level = vitality.classNumber
            let shipped = vitality.anchor

            let inProduct = try #require(
                product[level],
                "PRODUCT \u{a7}3's rubric table has no row for level \(level); it parsed as \(product)"
            )
            let inScreens = try #require(
                screens[level],
                "SCREENS 05 \u{a7}3's rubric table has no row for level \(level); it parsed as \(screens)"
            )

            #expect(
                inProduct == shipped,
                "level \(level) (\(vitality.label)): **PRODUCT \u{a7}3 has drifted from the shipped "
                    + "copy**. PRODUCT says \u{201c}\(inProduct)\u{201d}; Vitality.anchor says "
                    + "\u{201c}\(shipped)\u{201d}. Ticket #261 landed one rubric in three places on "
                    + "purpose \u{2014} whichever is right, they cannot differ."
            )
            #expect(
                inScreens == shipped,
                "level \(level) (\(vitality.label)): **SCREENS 05 \u{a7}3 has drifted from the "
                    + "shipped copy**. SCREENS says \u{201c}\(inScreens)\u{201d}; Vitality.anchor "
                    + "says \u{201c}\(shipped)\u{201d}. Ticket #261 landed one rubric in three "
                    + "places on purpose \u{2014} whichever is right, they cannot differ."
            )
        }
    }

    /// **The parser can see what it claims to have checked.** An equality test over an empty
    /// dictionary passes vacuously, and a heading rename or a table reshape would empty it silently
    /// — the same shape as a sweep that drops its own input. Both documents must yield exactly five
    /// levels before any comparison above means anything.
    @Test("both distilled tables parse to five levels")
    func theParserFindsBothTables() throws {
        let documents = [
            ("docs/distilled/PRODUCT.md", Self.productHeading),
            ("docs/distilled/SCREENS.md", Self.screensHeading),
        ]
        for (path, heading) in documents {
            let parsed = try RubricTable.anchors(underHeading: heading, in: Self.document(path))
            #expect(
                Set(parsed.keys) == Set(1...5),
                "\(path): the rubric table under \u{201c}\(heading)\u{201d} parsed to levels "
                    + "\(parsed.keys.sorted()), not 1\u{2013}5. The parser is reading the wrong "
                    + "table or no table, and every comparison that depends on it is passing on "
                    + "nothing."
            )
            for (level, anchor) in parsed {
                #expect(!anchor.isEmpty, "\(path): level \(level)'s anchor cell parsed empty")
            }
        }
    }

    /// The red-proof of §2's parser, run on every build rather than once by hand: a specimen whose
    /// answer is known, and a near-miss that must yield nothing rather than yielding a wrong row.
    @Test("the table parser reads the column its header names, and declines what it cannot read")
    func theParserIsCalibrated() throws {
        let specimen = """
        ## Something else
        | Level | Anchor line |
        |---|---|
        | 1 | not this table |

        ### Vitality scale (draft)
        Prose in between, and a stray pipe | that starts no row.
        | Level | Title | Anchor line | Band |
        |---|---|---|---|
        | 1 | `1 · Severe decline` | `first` | 51–100% |
        | 2 | `2 · Poor` | `second` | 26–50% |

        ### The next section
        | Level | Anchor line |
        |---|---|
        | 3 | nor this one |
        """

        let parsed = try RubricTable.anchors(underHeading: "### Vitality scale", in: specimen)
        #expect(
            parsed == [1: "first", 2: "second"],
            "the parser read \(parsed) — it should take the third column, because that is the one "
                + "headed \u{2018}Anchor line\u{2019}, and only rows inside the named section"
        )

        // A section with no table must throw rather than return an empty dictionary that a caller
        // would compare successfully against nothing.
        #expect(throws: RubricTable.ParseFailure.self) {
            try RubricTable.anchors(underHeading: "### The next section", in: """
            ### The next section
            no table here at all
            """)
        }
        #expect(throws: RubricTable.ParseFailure.self) {
            try RubricTable.anchors(underHeading: "### Absent", in: specimen)
        }
    }

    // MARK: - 3. The one clause the seasonality gate cannot rescue

    /// The single absence assertion here, and it earns its place: no gate change can fix this one.
    ///
    /// `Vitality.isRatingPermitted` suppresses the section only for a deciduous species out of leaf,
    /// and `Species.leafOnMonths` runs the deciduous window to the *close of the fall-color season*,
    /// so fall color sits inside leaf-on by construction — intended behavior, and the derivation
    /// ERRATA E33 repaired for a different bug. A tree in fall color is therefore in leaf, ratable
    /// and discolored. Draft v0's row 3 said "Noticeable thinning or discoloration" and pointed that
    /// rater at a decline class. Adding a second condition to the gate would suppress the rubric in
    /// the fall for trees that are in leaf, which is what E33 exists to prevent, so the repair is
    /// copy — and copy that has to stay repaired.
    @Test("no anchor asks about discoloration", arguments: Vitality.allCases)
    func noAnchorAsksAboutDiscoloration(vitality: Vitality) {
        let row = "\(vitality.classNumber) \u{00b7} \(vitality.label)"
        let message =
            "\(row) asks about discoloration: \u{201c}\(vitality.anchor)\u{201d}. A deciduous "
            + "species in fall color is in leaf, so the seasonality gate does not and must not "
            + "suppress the rubric for it (ERRATA E33), and a rater cannot tell seasonal color "
            + "from stress color by looking."
        #expect(!vitality.anchor.lowercased().contains("discolor"), "\(message)")
    }
}
