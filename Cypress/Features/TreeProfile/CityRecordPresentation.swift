//
//  CityRecordPresentation.swift
//  Cypress — Features/TreeProfile
//
//  Screen 03/14 §9b · **What San Francisco has on file** — the city's own six columns, read out on
//  the tree's landing page.
//
//  **NOT SPECIFIED.** SCREENS.md has no such section. It exists because the project owner asked for
//  it in as many words — *"Want to see more city details about trees e.g. when planted next pruning
//  last pruning and others"* (#68) — and because ERRATA E143 landed the six columns
//  (`CityRecord`) with nothing drawing them. E143's closing line is that neither screen is built
//  there; this is one of the two.
//
//  ── The one thing this section must never become ──────────────────────────────────────────
//  A panel of facts that reads as *Cypress's* facts. BUILD-PLAN §5 makes provenance a queryable
//  property rather than something a screen remembers, and the profile's subtitle already tells a
//  reader whether this record is `SF city inventory` or `community-added, unverified`. So every card
//  here is a `StatCard.Value.cityRecord`, which is the vocabulary D7 already built for exactly this
//  distinction: the value in mono with C12's `city record` badge beside it, reading out as "from the
//  city record". No new badge, no new card, no second vocabulary for a distinction the app already
//  draws — that is `placementNote`'s argument about not describing one kind of fact twice.
//
//  The section is drawn under its own header for the same reason. A city column appended into the
//  existing stat grid would sit beside `Height 18 m est.`, which is a contributor's number, with
//  nothing between them saying they came from different places.
//
//  ── What is deliberately not here ─────────────────────────────────────────────────────────
//  **`permitNotes`.** See `permitNotesIsNotShown`.
//  **A pruning field.** There is none in the dataset. See `pruningNote`, which says so once, in the
//  section's own voice, rather than putting an `Unknown` on 195,309 trees.
//  **`Tree.landContext`.** It is an *inference from* this record, not a line in it, and it renders
//  outside this section. See `TreeProfilePresentation.landContextNote`.
//
//  Pure value code, no SwiftUI. It lives in `Features/` rather than in `Core` because every decision
//  in it is a display decision: `CityRecord`'s own documentation says the storage layer normalises
//  nothing and parses nothing, and nothing below has changed that. The seed still holds `FUF` and
//  `3X3`; this file is the reader.
//

import Foundation

/// The city's record, prepared for the two-up grid.
struct CityRecordPresentation {

    /// One card. `id` is stable across reloads so the grid does not re-identify its cells.
    struct Fact: Identifiable, Hashable {
        let id: String
        let label: String
        /// Always rendered through `StatCard.Value.cityRecord`, badge and all. There is no
        /// initializer here that produces a plain value, which is the point.
        let value: String
    }

    let record: CityRecord

    init(_ record: CityRecord) {
        self.record = record
    }

    // MARK: - The cards

    /// The city's columns, in the order a person standing at the tree can use them.
    ///
    /// Order is not the seed's column order and not the population order. `plantType` leads *when it
    /// draws at all*, because the only thing it ever says is that this record is not a tree; then the
    /// tree's standing in city law, then who tends it, then the hole it stands in.
    var facts: [Fact] {
        var facts: [Fact] = []

        if let listedAs = listedAsText {
            facts.append(Fact(id: "plantType", label: CityRecordCopy.plantTypeLabel, value: listedAs))
        }
        if let status = record.legalStatus, !status.isEmpty {
            // Verbatim, including `Section 806 (d)` and `Planning Code 138.1 required`. Those are
            // ordinance references, and glossing one would mean this file stating what a section of
            // San Francisco's Public Works Code says — which is authoring law, not reading a column.
            // `Undocumented` is verbatim for the plainer reason that it is the city's own word for
            // having nothing on file, and it is a better sentence than anything written to replace it.
            facts.append(Fact(id: "legalStatus", label: CityRecordCopy.legalStatusLabel, value: status))
        }
        if let caretaker = record.caretaker.flatMap(Self.agencyName) {
            facts.append(Fact(id: "caretaker", label: CityRecordCopy.caretakerLabel, value: caretaker))
        }
        if let assistant = record.careAssistant.flatMap(Self.agencyName) {
            facts.append(Fact(id: "careAssistant", label: CityRecordCopy.careAssistantLabel, value: assistant))
        }
        if let plot = record.plotSize.flatMap(Self.plotSizeText) {
            facts.append(Fact(id: "plotSize", label: CityRecordCopy.plotSizeLabel, value: plot))
        }

        return facts
    }

    /// Whether the section draws at all.
    ///
    /// Not `!record.isEmpty`: a record can be non-empty and still produce no card, because
    /// `plantType` is suppressed on the 194,991 rows that say `Tree` and `plotSize` is suppressed
    /// wherever it does not state a size. A header over an empty grid is the failure `CityRecord.isEmpty`
    /// was written to avoid, one level further in.
    var isEmpty: Bool { facts.isEmpty }

    // MARK: - `plantType` — the column that only speaks when it disagrees with the screen

    /// `Landscaping`, or nothing at all.
    ///
    /// The column is 100% populated and says `Tree` on 194,988 rows, `tree` on 3 and `Landscaping`
    /// on 318 (E143). A card reading `City lists this as — Tree`, on a tree page, reached from a tree
    /// map, under a photograph of a tree, is a row of the panel spent saying nothing. The 318 rows are
    /// the only place the city's inventory says a record on the tree map is **not** a tree, and that
    /// is worth a card.
    ///
    /// ── This is not `placementNote`'s "only the unusual case" mistake ─────────────────────────
    /// `placementNote` prints both of its values and argues that printing only the exceptional one
    /// turns a label into a warning. That argument does not reach here, because it is about two
    /// provenances of *one* fact, where marking one ranks it against the other. `Tree` and
    /// `Landscaping` are not two ways of arriving at the same thing: `Tree` restates what every other
    /// element on the screen has already said, and `Landscaping` contradicts it. Suppressing an echo
    /// is not the same act as suppressing an alternative.
    ///
    /// Case-folded, because the city typed `tree` three times and E143 rules that the builder does not
    /// correct the city's case — "readers compare case-folded". This is a reader.
    var listedAsText: String? {
        guard let raw = record.plantType?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        guard raw.lowercased() != CityRecordCopy.plantTypeTree else { return nil }
        return raw
    }

    // MARK: - `plotSize` — 588 values in three notations, and what happens to each

    /// The planting basin, said one way.
    ///
    /// ── The problem ───────────────────────────────────────────────────────────────────────────
    /// 146,951 rows carry a value and they are written in three incompatible notations plus junk:
    /// `Width 3ft` (86,905 rows including the zeroes), `3x3`/`3X3` (56,760), a bare integer of
    /// unstated unit (2,726), and 560 strings that are not sizes at all — `M6`, `TR`, `POT`, `CUT`,
    /// `On campus`, `within landscaping plot`, `aaa`, `?`. DataSF's published description of the
    /// column reads "date tree was planted", copied from `PlantDate`; the field is under-curated at
    /// the source. Printing all 588 verbatim is not showing the city's record, it is handing the
    /// reader the city's data-entry problem and calling it transparency.
    ///
    /// ── What is done, and what is refused ─────────────────────────────────────────────────────
    /// **Refused: any arithmetic.** No area is derived, no unit is converted, no notation is
    /// reconciled with another. `CityRecord.plotSize`'s own documentation forbids it and D7 is the
    /// reason — an area computed from `3x3` would be an estimate wearing a measurement's clothes, and
    /// the two notations do not even measure the same thing (one is a single dimension, the other is
    /// two).
    ///
    /// **Done: the notation is recognised and re-spelled, with the city's own digits and the city's
    /// own units.** `Width 3ft` → `3 ft wide`, because the city named both the dimension and the
    /// unit. `3x3` and `3X3` → `3 × 3`, with **no unit appended**, because the city named none and
    /// feet is a guess that would be right most of the time and invisible when it was wrong.
    /// Case-folding `x`/`X` is reading, not editing: E143 already rules that `3x3` and `3X3` are one
    /// value written twice.
    ///
    /// ── The three things that produce no card ─────────────────────────────────────────────────
    /// 1. **`Width 0ft` — 17,254 rows.** A basin zero feet wide is not a measurement of a basin; it is
    ///    the shape "not measured" takes in a form that wanted a number. E77 settled the same
    ///    question on screen 16, where a plain `0` in ink reads as a measurement of zero. Drawing
    ///    `0 ft wide` would be Cypress asserting a size the city did not observe.
    /// 2. **A bare integer — 2,726 rows.** `60`, `20`, `10`, `5`. No dimension, no unit. Sixty of
    ///    what, across what? A number with neither is not a size, and putting it under a label that
    ///    says it is one is the invention this section exists not to make.
    /// 3. **Everything else — 560 rows.** `M6` (96), `TR`, `POT`, `Plaza`, `3xe`, `2x`, `Width 4x5`.
    ///    These are plot *codes* and typing errors from inside a Public Works workflow. `M6` under a
    ///    card labelled `Plot size` is the app asserting that `M6` is a plot size.
    ///
    /// All three are absent rather than blank or `Unknown`, which is what this screen already does
    /// with every fact a record does not carry (`recognitionTip`, `watchForText`, `badge`). 126,411
    /// of the 146,951 populated rows (86.0%) render; the other 20,540 look exactly like the 48,358
    /// rows where the city wrote nothing, and in the sense that matters they are the same thing — the
    /// city has no plot size for this tree. Both totals are re-derived from every row by
    /// `everyPlotSizeInTheSeedIsShownOrRefusedOnPurpose`, so this paragraph cannot rot.
    static func plotSizeText(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if let feet = widthInFeet(trimmed) { return feet + CityRecordCopy.plotWidthSuffix }
        if let pair = dimensionPair(trimmed) { return pair }
        return nil
    }

    /// `Width 3ft` → `3`. Nil for anything else, and for `Width 0ft`.
    ///
    /// The number is returned as the city's own characters rather than re-formatted from a parsed
    /// `Double`, so `3` stays `3` and nothing acquires a decimal point it did not have.
    private static func widthInFeet(_ trimmed: String) -> String? {
        let lower = trimmed.lowercased()
        guard lower.hasPrefix(CityRecordCopy.plotWidthPrefix), lower.hasSuffix(CityRecordCopy.plotFeetSuffix) else {
            return nil
        }
        let start = trimmed.index(trimmed.startIndex, offsetBy: CityRecordCopy.plotWidthPrefix.count)
        let end = trimmed.index(trimmed.endIndex, offsetBy: -CityRecordCopy.plotFeetSuffix.count)
        guard start < end else { return nil }
        let number = trimmed[start..<end].trimmingCharacters(in: .whitespaces)
        return isPositiveNumber(number) ? number : nil
    }

    /// `3x3`, `3X3`, `.5x1` → `3 × 3`, `3 × 3`, `.5 × 1`. Nil for `2x`, `3xe`, `0x0`, `Width 4x5`.
    private static func dimensionPair(_ trimmed: String) -> String? {
        let parts = trimmed.lowercased().split(separator: CityRecordCopy.plotPairSeparator, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let left = parts[0].trimmingCharacters(in: .whitespaces)
        let right = parts[1].trimmingCharacters(in: .whitespaces)
        guard isPositiveNumber(left), isPositiveNumber(right) else { return nil }
        return left + CityRecordCopy.plotPairJoiner + right
    }

    /// Digits with at most one decimal point, and greater than zero.
    ///
    /// `Double(_:)` alone would accept `1e3`, `inf`, `nan` and a leading `+`, none of which are in the
    /// column and all of which would render as something nobody wrote. The character check runs
    /// first and the value check second, so `0`, `0.0` and `00` are all refused for `Width 0ft`'s
    /// reason.
    private static func isPositiveNumber(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        guard text.allSatisfy({ $0.isNumber || $0 == "." }) else { return false }
        guard text.filter({ $0 == "." }).count <= 1 else { return false }
        guard let value = Double(text) else { return false }
        return value > 0
    }

    // MARK: - `caretaker` / `careAssistant` — the codes, expanded

    /// The agency, in words a person who does not work for the city can read.
    ///
    /// ── Why a glossary and not verbatim ───────────────────────────────────────────────────────
    /// The brief this section answers singles out one value: `FUF` is `careAssistant` on 22,879 of its
    /// 25,199 rows, and it is Friends of the Urban Forest — a volunteer organisation whose name is a
    /// nice thing to be able to tell somebody, and a three-letter code that tells them nothing. Once
    /// `FUF` is expanded there is no principled place to stop: `PUC` and `SFUSD` are the same kind of
    /// opacity in the same two columns.
    ///
    /// ── Why this is not editing the city's record ─────────────────────────────────────────────
    /// Expanding an acronym does not change what the record claims; it says the same thing at length.
    /// Nothing here re-ranks, corrects a spelling, merges two values or fills a blank. Compare
    /// `plantType`, where the city typed `tree` three times and this file leaves the case alone in the
    /// one place it is shown — because *that* would be tidying, and tidying is E143's line.
    ///
    /// **Unknown values pass through untouched**, which is the property that makes this safe against
    /// the weekly refresh: `Port`, `Mission Verde`, `Cleary Bros. Landscape` and `CAN` are already
    /// readable or already unknown to this file, and a department the city renames next month renders
    /// as its new name rather than as a build failure. E143 refused a CHECK on these columns for
    /// exactly this reason and the reader has to hold the same shape.
    ///
    /// `nil` for an empty string, so `""` cannot become a card labelled `Cared for by` with nothing
    /// after it.
    static func agencyName(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return CityRecordCopy.agencyGlossary[trimmed] ?? trimmed
    }

    // MARK: - Pruning, and the two statuses that are the nearest thing to it

    /// The standing arrangement on the 254 trees that have one, or `nil`.
    ///
    /// `Prune Opt Out` (196 rows) and `Street Tree Maintenance Opt Out` (58) are the only values in
    /// the whole dataset with anything to do with pruning, and they are **facts about these specific
    /// trees** — somebody withdrew the site from a city programme — which is why they get a sentence
    /// rather than being folded into the general note below. They already render verbatim as the
    /// `Legal status` card; this says what the card means, because "Prune Opt Out" is exactly the
    /// string a reader looking for pruning history will read as pruning history.
    ///
    /// The clause that does the work is "with no date on the record". E143: *a standing policy about
    /// a tree, not a date on which anything happened to it, and it must never render as one.*
    func maintenanceOptOutNote() -> String? {
        switch record.legalStatus {
        case CityRecordCopy.pruneOptOutStatus: return CityRecordCopy.pruneOptOutNote
        case CityRecordCopy.maintenanceOptOutStatus: return CityRecordCopy.maintenanceOptOutNote
        default: return nil
        }
    }

    /// The answer to the half of #68 the data cannot give: **there is no pruning history, at any
    /// grain, for any tree.**
    ///
    /// ── Why this is on screen and not only in a report ────────────────────────────────────────
    /// The owner asked for "next pruning last pruning" on the tree page. Verified against DataSF
    /// `tkzw-k3nq`'s own published column metadata (E143), the dataset has eighteen real columns and
    /// not one records a pruning event, date or schedule. Answering that in an errata entry and
    /// leaving the screen silent means the question gets asked again — and the *next* round starts
    /// from the same wrong premise, that somebody simply had not got round to wiring the column up.
    /// That has a cost this project has already paid more than once.
    ///
    /// ── Why it is one sentence at the foot of a section, and not a field ──────────────────────
    /// The obvious alternative — a `Last pruned · Unknown` card, or a pair of them — was rejected,
    /// and not on grounds of taste. `Unknown` in a card is a claim about **this tree**: it says the
    /// value exists and Cypress has not got it. What is true is a claim about the **source**: San
    /// Francisco's street tree inventory does not carry the field. Those are different statements and
    /// only one of them is true. The card version would also be the first `Unknown` on a screen whose
    /// entire grammar for "no such fact" is to draw nothing (`recognitionTip`, `watchForText`,
    /// `badge`, and every absent card in `stats`), and it would sit on all 195,309 city rows, which is
    /// the definition of noise.
    ///
    /// So: a statement about the record, in the section that is about the record, in the same voice as
    /// the subtitle's `SF city inventory`. Provenance sentences repeat by nature — that one is on
    /// every screen too.
    ///
    /// ── The line this must not cross ──────────────────────────────────────────────────────────
    /// It is here because a person asked, not because absences are worth listing. The inventory also
    /// records no watering schedule, no soil volume, no root barrier and no inspection date, and none
    /// of those get a line. If this section ever grows a second one, the honest move is a single
    /// "what the city does not record" sentence rather than a growing list — and at that point this
    /// one should be folded into it rather than joined by it.
    static let pruningNote = CityRecordCopy.pruningNote

    /// **`permitNotes` is not shown, at all.** 52,580 rows, and it is two columns wearing one name.
    ///
    /// **52,114 of them are a permit reference** — `Permit Number 771729`, `Permit No. 49239`, and a
    /// few bare digits. It is a key into a Public Works permitting system this app cannot query,
    /// cannot link to, and cannot say anything about. On screen it is a number that looks like
    /// information and answers nothing a person standing at the tree asked. E143 refused `SiteOrder`
    /// on precisely this test: a key inside the city's table rather than a fact about a tree.
    ///
    /// **466 of them are somebody's free text**, and reading them is the argument: `I believe these
    /// were planted in 2010 by FUF. C.Buck` · `Resulted descion 9/7/16 -DE` · `privately planted on
    /// dpw street; unpermitted` · `Maintenance agreement ends 8/17/2010` · `witin landscaping plot`.
    /// These are staff working notes — a named clerk's guess, an internal decision reference, a
    /// misspelling, an accusation about a neighbour's planting. Publishing them under a card that says
    /// `city record` would dress one person's marginal note as San Francisco's finding, and it puts an
    /// employee's initials and an unverified claim about a private property owner on a public screen.
    ///
    /// **And the two cannot be told apart by a renderer**, only guessed at by prefix — which is the
    /// same class of mistake as parsing `plotSize`. There is no honest way to show one and not the
    /// other, and neither belongs on its own merits, so neither is shown.
    ///
    /// Kept as a documented decision rather than as silence, because the column *is* in `CityRecord`
    /// and the next reader will otherwise assume it was overlooked.
    static let permitNotesIsNotShown = true
}

// MARK: - Copy and vocabulary

/// Everything this section says, and the city's strings it matches against.
///
/// Out of the view for the reason every `*Copy` in this app is: a sentence a state produces is a
/// decision, and a decision is worth a test that does not have to render a `View` to read it.
enum CityRecordCopy {

    /// The section header. It names the city, because the section's whole job is to say whose facts
    /// these are before the first one is read.
    ///
    /// **Not "City record", which is already a card in the grid above it** (`SF #13284`, the DataSF
    /// `TreeID`, specified by SCREENS.md 14). That card stays where it is drawn — moving a specified
    /// element to make room for an unspecified one is not a trade this round had standing to make —
    /// so this header is worded to sit above it without colliding with it.
    static let header = "What San Francisco has on file"

    static let plantTypeLabel = "City lists this as"
    static let legalStatusLabel = "Legal status"

    /// **`Cared for by`, not `Caretaker` and never `Owner`.**
    ///
    /// DataSF's own description of `qCaretaker` reads "Agency or person that is primary caregiver to
    /// tree. **Owner of Tree**", and that second sentence is the single most expensive mistake
    /// available in this dataset: 163,955 rows say `Private`, of which 112,955 also carry
    /// `DPW Maintained`. They are sidewalk trees in the public right-of-way whose adjacent owner
    /// waters them. E143 measured what leading on this column does — 152,240 street trees relabelled
    /// as private property — and `LandContext.inferred(from:)` exists to not do it.
    ///
    /// A card labelled `Caretaker` invites the reader to make that same inference by hand. The label
    /// says what the column measures, which is care, and the `Stands on` sentence above the section
    /// answers the question the reader was actually asking.
    static let caretakerLabel = "Cared for by"
    static let careAssistantLabel = "Also cared for by"
    static let plotSizeLabel = "Plot size"

    /// The city's word for a record that is a tree, case-folded. See `listedAsText`.
    static let plantTypeTree = "tree"

    // ── `plotSize` notation ──────────────────────────────────────────────────────────────────

    static let plotWidthPrefix = "width "
    static let plotFeetSuffix = "ft"
    /// `3 ft wide` — the unit is the city's own `ft`, kept rather than spelled out, because "feet"
    /// is a word the city did not write and `ft` is unambiguous.
    static let plotWidthSuffix = " ft wide"
    static let plotPairSeparator: Character = "x"
    /// `×`, the multiplication sign, not the letter. The two dimensions are the city's; the sign
    /// between them is this file's, and it is the one ARCHITECTURE §5.7's copy rules would use.
    static let plotPairJoiner = " × "

    // ── Agencies ─────────────────────────────────────────────────────────────────────────────

    /// Codes a reader outside City Hall cannot expand, and only those. See `agencyName`.
    ///
    /// `Port`, `Fire Dept`, `Arts Commission`, `Mission Verde`, `Cleary Bros. Landscape`,
    /// `Conservation Corps`, `Clean City`, `Owner Water` and the rest are absent because they already
    /// read as English. `CAN` (19 rows) is absent for the opposite reason: this file does not know
    /// what it stands for, and guessing is how a glossary starts lying.
    static let agencyGlossary: [String: String] = [
        "FUF": "Friends of the Urban Forest",
        "DPW": "SF Public Works",
        "DPW for City Agency": "SF Public Works, for a city agency",
        "PUC": "SF Public Utilities Commission",
        "MTA": "SF Municipal Transportation Agency",
        "SFUSD": "SF Unified School District",
        "Rec/Park": "SF Recreation and Parks",
        // Not an agency, and the one entry here that is a rewording rather than an expansion: the
        // bare adjective `Private` in a card labelled `Cared for by` reads as a category, and the
        // category a reader will reach for is the property line. A noun phrase says a person.
        "Private": "A private party",
    ]

    // ── Pruning ──────────────────────────────────────────────────────────────────────────────

    static let pruneOptOutStatus = "Prune Opt Out"
    static let maintenanceOptOutStatus = "Street Tree Maintenance Opt Out"

    static let pruneOptOutNote =
        "This site is withdrawn from the city's pruning programme — a standing arrangement, "
        + "with no date on the record."
    static let maintenanceOptOutNote =
        "This site is withdrawn from the city's street-tree maintenance programme — a standing "
        + "arrangement, with no date on the record."

    /// See `CityRecordPresentation.pruningNote` for why this sentence is on screen at all.
    ///
    /// It names the *inventory*, not the city: San Francisco certainly prunes its trees, and a
    /// sentence reading "the city records no pruning" would say something false about a public works
    /// department. What has no pruning in it is this dataset.
    static let pruningNote = "The city's street tree inventory records no pruning dates or schedule."
}
