import Foundation
import Testing
@testable import Cypress

/// **The NYC.gov Data Mine disclaimer, checked against the document of record.**
///
/// RULINGS **R78 ruling 2** puts the verbatim block on the city-downloads screen and is the
/// constraint-21 sign-off for putting it there; **R78 ruling 3** says the manifest's
/// machine-readable `attribution` array does not discharge the obligation, so the text has to be
/// rendered and human-visible. `docs/operations/nyc-data-obligations.md` §1 carries the terms'
/// own wording, quoted from `Fixtures/raw/nyc/datamine_terms.html` and re-fetched live 2026-08-21
/// with identical text; §4 repeats it as the block to render.
///
/// ── What this file is for, and what it is not ────────────────────────────────────────────────
/// It is a **drift guard between two files**, and that is the only claim it makes. A test that
/// compared `CityDownloadsCopy.nycDisclaimerRequired` against a literal typed into this file would
/// be comparing one hand-copy against another: the two would be edited together by whoever got the
/// wording wrong, and the guard would agree with the mistake. So the expected text is READ OUT OF
/// the document at test time, and the only way to make this suite green with the wrong sentence on
/// screen is to also change the document that records what the City requires.
///
/// It cannot see a screen. `CityDisclaimerUITests` is the half that proves a reader gets it; this
/// half proves what they get is the City's words.
@Suite("NYC Data Mine disclaimer")
struct NYCDisclaimerTests {

    // MARK: - Reading the document

    private static let documentPath = "docs/operations/nyc-data-obligations.md"

    /// The obligations document, whitespace-collapsed and stripped of the markdown that only
    /// decorates it.
    ///
    /// Blockquote markers and bold markers are removed because the document quotes the disclaimer
    /// inside a `>` block and the app renders a paragraph; every run of whitespace becomes one
    /// space because the document hard-wraps at 95 columns and Swift's `\` continuations wrap
    /// somewhere else entirely. Nothing else is touched — in particular no letter, no punctuation
    /// mark and no word boundary — so a `cannot` for `can not` survives into the comparison.
    private static func normalizedDocument() throws -> String {
        let url = AppSourceLiterals.repositoryRoot().appendingPathComponent(documentPath)
        let raw = try String(contentsOf: url, encoding: .utf8)
        let unquoted = raw
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                var text = String(line)
                while text.hasPrefix(">") { text.removeFirst() }
                return text
            }
            .joined(separator: " ")
            .replacingOccurrences(of: "**", with: "")
        return normalize(unquoted)
    }

    /// One space per run of whitespace, trimmed. Used on both sides of every comparison so that
    /// neither file's line breaks can be the reason a check passes or fails.
    private static func normalize(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    // MARK: - 1. The document is really being read

    /// The calibration this whole file rests on, and it runs first on purpose.
    ///
    /// Every check below is `document.contains(…)`, which is exactly the shape that passes
    /// vacuously when the document could not be read and `normalizedDocument()` returns something
    /// empty or wrong. Two sentinels the document is known to carry — one from §0's ruling table,
    /// one from §1's quote of the terms — say the file on disk is the file this suite means.
    @Test("the obligations document is on disk and is the one that carries R78")
    func theDocumentIsReadable() throws {
        let document = try Self.normalizedDocument()

        #expect(document.count > 5_000,
                """
                \(Self.documentPath) collapsed to \(document.count) characters; every check in \
                this suite is a `contains` and would pass vacuously against a stub
                """)
        #expect(document.contains("RULINGS R78"),
                """
                \(Self.documentPath) does not mention R78, so it is not the document this suite \
                thinks it is reading
                """)
        #expect(document.contains("NYC DataPortal Terms of Use"),
                """
                \(Self.documentPath) does not quote the terms page, so §1's verbatim block is \
                not in the text being searched
                """)
    }

    // MARK: - 2. The shipped string is the City's, character for character

    /// The check the obligation actually turns on.
    ///
    /// `contains` rather than an equality against an extracted span: the document presents the
    /// block twice, once inside §1's quotation of the terms and once as §4's render-this draft, and
    /// a extractor that had to find the boundaries of either would be a second thing to get wrong.
    /// What matters is that the sentence the app ships appears in the document unaltered.
    @Test("the shipped disclaimer appears verbatim in the document of record")
    func theShippedTextIsVerbatim() throws {
        let document = try Self.normalizedDocument()
        let shipped = Self.normalize(CityDownloadsCopy.nycDisclaimerRequired)

        #expect(document.contains(shipped),
                """
                CityDownloadsCopy.nycDisclaimerRequired is not in \(Self.documentPath).

                shipped: \(shipped)

                The City's wording is the obligation, so one of these is wrong and it is not \
                automatically the document. If the terms page changed, re-fetch it, update \
                §1 and §4, and change the constant to match — in that order.
                """)
    }

    /// Both of the document's copies say the same thing, so "which §" is never a live question.
    ///
    /// §1 is the terms quoted; §4 is the block to render. If they ever disagree, the check above
    /// would still pass against whichever one the constant happened to match, and the document
    /// would be quietly contradicting itself about a legal obligation.
    @Test("the document carries the block twice and both copies agree")
    func bothCopiesInTheDocumentAgree() throws {
        let document = try Self.normalizedDocument()
        let shipped = Self.normalize(CityDownloadsCopy.nycDisclaimerRequired)
        let occurrences = document.components(separatedBy: shipped).count - 1

        #expect(occurrences == 2,
                """
                the disclaimer appears \(occurrences) time(s) in \(Self.documentPath); §1 \
                quotes the terms and §4 gives the block to render, so it should appear exactly \
                twice and both should be identical
                """)
    }

    // MARK: - 3. The comparison can tell a difference

    /// **The calibration for check 2**, and the reason it is here is that `contains` against a
    /// 15,000-character document is a check that could plausibly match almost anything.
    ///
    /// Each specimen below is the shipped text with one edit an ordinary house-style pass would
    /// make — and each must NOT be found. If any of them is, the comparison is too loose to be
    /// protecting the wording it exists to protect.
    @Test("a house-style edit of the disclaimer is not found in the document")
    func anAlteredDisclaimerIsNotFound() throws {
        let document = try Self.normalizedDocument()
        let shipped = Self.normalize(CityDownloadsCopy.nycDisclaimerRequired)

        let edits: [(name: String, text: String)] = [
            ("\"can not\" tidied to \"cannot\"",
             shipped.replacingOccurrences(of: "can not", with: "cannot")),
            ("\"web site\" tidied to \"website\"",
             shipped.replacingOccurrences(of: "web site", with: "website")),
            ("the second sentence dropped",
             String(shipped.prefix(shipped.count / 2)) + " and nothing else."),
        ]

        for (name, specimen) in edits {
            #expect(specimen != shipped, """
                specimen \(name) did not change the text, so it calibrates nothing
                """)
            #expect(!document.contains(specimen),
                    """
                    the document contains the \(name) variant of the disclaimer, so check 2's \
                    `contains` cannot distinguish the City's wording from an edited one
                    """)
        }
    }

    // MARK: - 4. The two constants stay apart

    /// The attribution line is **ours** and the required block is the City's, and the reason they
    /// are separate constants is that editing the first must never be able to reach the second.
    /// This check fails if someone folds them together.
    @Test("the attribution line is a separate string and names both datasets")
    func theAttributionLineIsSeparate() {
        let required = CityDownloadsCopy.nycDisclaimerRequired
        let attribution = CityDownloadsCopy.nycDisclaimerAttribution

        #expect(!required.contains("Forestry Tree Points"),
                """
                the required block has grown our attribution sentence; the terms' text must \
                stand alone so that editing ours cannot alter theirs
                """)
        #expect(!attribution.contains("can not vouch"),
                "the attribution line has absorbed the City's text")
        for dataset in ["Forestry Tree Points", "Forestry Planting Spaces", "NYC Open Data"] {
            #expect(attribution.contains(dataset),
                    """
                    the attribution line does not name \(dataset), so the disclaimer above it \
                    is a sentence about an unidentified source
                    """)
        }
    }
}
