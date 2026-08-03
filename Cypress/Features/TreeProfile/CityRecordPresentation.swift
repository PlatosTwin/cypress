//
//  CityRecordPresentation.swift
//  Cypress — Features/TreeProfile
//
//  Screen 03/14 §9b · **What the city has on file** — the publishing inventory's own six columns,
//  read out on the tree's landing page. It said *San Francisco* until #137; RULINGS R28 has why the
//  header, the subtitle label, the record number and the pruning sentence all stopped naming one city.
//
//  **NOT SPECIFIED.** SCREENS.md has no such section. It exists because the project owner asked for
//  it in as many words — *"Want to see more city details about trees e.g. when planted next pruning
//  last pruning and others"* (#68) — and because ERRATA E143 landed the six columns
//  (`CityRecord`) with nothing drawing them. E143's closing line is that neither screen is built
//  there; this is one of the two. The whole design is argued in ERRATA (E145).
//
//  ── The one thing this section must never become ──────────────────────────────────────────
//  A panel of facts that reads as *Cypress's* facts. BUILD-PLAN §5 makes provenance a queryable
//  property rather than something a screen remembers, and the profile's subtitle already tells a
//  reader which inventory this record is from, or that it is `community-added, unverified`. So every card
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

    /// The numbering this record was published under — `sf`, `us-ca-sj`, or nil for a seed built
    /// before the column existed.
    ///
    /// Held because two of this file's rules are **readings of one publisher's vocabulary** and R24
    /// requires those to decline outside the id space they were written from. `pruningNote` already
    /// took it as an argument; `listedAsText` needs it for the same reason and could not ask for it,
    /// so the value moves onto the type. See `listedAsText`.
    let idSpace: String?

    init(_ record: CityRecord, idSpace: String?) {
        self.record = record
        self.idSpace = idSpace
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
        if let status = record.legalStatus.flatMap(Self.statedValue) {
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

    /// `Landscaping`, or nothing at all — **and nothing at all outside San Francisco** (R24).
    ///
    /// In DataSF's export the column says `Tree` on 194,988 rows, `tree` on 3 and `Landscaping` on
    /// 318 (E143); in the shipped `--source city` seed it is `Tree` on 145,671 and `Landscaping` on
    /// 166. A card reading `City lists this as — Tree`, on a tree page, reached from a tree map,
    /// under a photograph of a tree, is a row of the panel spent saying nothing. The `Landscaping`
    /// rows are the only place the city's inventory says a record on the tree map is **not** a tree,
    /// and that is worth a card.
    ///
    /// ── Why it declines outside `sf`, and what it was doing before ────────────────────────────
    /// Everything in the paragraph above is a reading of **DataSF's `PlantType`** — a column whose
    /// vocabulary is `Tree` plus a rare disagreement, which is what makes "suppress the agreement,
    /// draw the disagreement" the right rule. San Jose's `plant_type` is not that column. It is
    /// `GROWSPACE` (`SanJoseStreetTreeAdapter.CITY_RECORD_COLUMNS`), a growing-space category, and
    /// the rule read against it produced a card on **51,689 of 52,788 San Jose rows, 25,032 of them
    /// reading `N/A`** — the app telling a reader, under a photograph of a tree, that the city's
    /// record says this is not a tree. San Jose's record says no such thing; it says nothing at all,
    /// in the string a form writes when nobody filled the field in.
    ///
    /// This is R24 exactly: *a derivation over a publisher's own vocabulary is qualified by the id
    /// space it was written for, and must decline outside it.* The test R24 sets is not "does it
    /// return something sensible for the new source" but "was this rule written from **this**
    /// publisher's documentation" — and for `GROWSPACE` it was not. So it declines, in the same
    /// shape and for the same reason as `pruningNote(idSpace:)` and
    /// `LandContext.inferred(from:idSpace:)`.
    ///
    /// **It declines rather than being taught San Jose's vocabulary**, because teaching it would
    /// mean this file stating what `Park Strip`, `Well/Pit` and `Tree Lawn` mean in San Jose's
    /// asset system, on the strength of one adapter's column list rather than the city's published
    /// metadata — the invention DECISIONS constraint 15 forbids. What a San Jose reader loses is a
    /// card that was never about their tree; `Legal status` and `Cared for by` both still draw on
    /// every one of their rows, so the section is not emptied and E126's "a surface with nothing on
    /// it must say why" is not engaged. That is `pruningNote`'s argument, and it is checked rather
    /// than assumed by `everySurfaceDrawsOnlyColumnsItsIdSpaceCanSpeakFor`.
    ///
    /// **Nil `idSpace` keeps the rule**, matching `pruningNote(idSpace:)` and
    /// `LandContext.inferred(from:idSpace:)` exactly: a seed built before the column existed is San
    /// Francisco's alone, and the reading is true of it.
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
        guard idSpace == nil || idSpace == CityRecordCopy.sanFranciscoIDSpace else { return nil }
        guard let raw = record.plantType?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        guard raw.lowercased() != CityRecordCopy.plantTypeTree else { return nil }
        return raw
    }

    // MARK: - The string a form writes when nobody filled the field in

    /// The city's value, or `nil` when the "value" is the source's own way of writing *blank*.
    ///
    /// ── The problem this exists for ───────────────────────────────────────────────────────────
    /// A column can be populated and still say nothing. San Jose's `GROWSPACE` reaches the seed as
    /// both `plant_type` and `site_type`, and on **25,032 rows it is the literal `N/A`** with a
    /// further **805 reading `Unassigned`**; San Francisco's `qSiteInfo` is a composite of two
    /// halves joined by a colon, and on **4,608 rows both halves are empty and the string is the
    /// bare separator `:`**. All three are `NOT NULL` as far as SQLite is concerned and all three
    /// used to reach the screen, so a reader got `Site — N/A` and `Site — :` under a label
    /// asserting the city had recorded a placement.
    ///
    /// ── Why they are refused rather than shown, and why that is not editing the record ─────────
    /// This is the argument `plotSizeText` already makes about `Width 0ft` on 17,254 rows: a basin
    /// zero feet wide is not a measurement of a basin, it is the shape "not measured" takes in a
    /// form that wanted a number. `N/A` is that shape in a form that wanted a word. Drawing it is
    /// not transparency about the city's record — it is Cypress asserting that the city recorded
    /// something, when what the city recorded was the absence.
    ///
    /// Nothing here corrects a spelling, merges two values, ranks one above another or fills a
    /// blank. It recognises **the absence of a value** and renders it the way this screen renders
    /// every absence — by drawing nothing (E9, and `recognitionTip`/`watchForText`/`badge`). It is
    /// deliberately *not* a judgment about what any real value means: `Park Strip` and
    /// `Sidewalk: Curb side : Cutout` pass through untouched, because reading them would be the
    /// invention DECISIONS constraint 15 forbids and is not needed to know that `N/A` is not a place.
    ///
    /// ── The two arms ──────────────────────────────────────────────────────────────────────────
    /// 1. **No letter and no digit anywhere.** `:`, `-`, `--`, `?`. A string with nothing to read in
    ///    it cannot be a fact about a tree whatever the column meant. This arm is what catches
    ///    San Francisco's 4,608 bare separators, and it needs no vocabulary at all.
    /// 2. **A source-neutral null placeholder**, case-folded. Of the list below, only `n/a` and
    ///    `unassigned` occur in the shipped seed (25,032 and 805 rows, both `us-ca-sj`); the rest
    ///    are the same idiom spelled the other common ways and are carried against the weekly
    ///    refresh, not against a measurement. These are **not** city vocabulary — they are what a
    ///    data-entry form emits for "no answer", in any city, which is exactly why matching them is
    ///    not a reading of one publisher's dialect and does not need R24's id-space guard.
    ///
    /// Applied to every card in the section and to the `Site` card on 03/14 and 19, so a column that
    /// starts emitting a placeholder tomorrow cannot reach a label. Re-derived over every row of
    /// every id space by `everySurfaceDrawsOnlyColumnsItsIdSpaceCanSpeakFor`.
    static func statedValue(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.contains(where: { $0.isLetter || $0.isNumber }) else { return nil }
        guard !CityRecordCopy.noValueMarkers.contains(trimmed.lowercased()) else { return nil }
        return trimmed
    }

    /// The `Site` card's value on screens 03/14 and 19, or nothing.
    ///
    /// One function for both screens because they draw the same column under the same label and had
    /// drifted into two copies of the same comment; E209-B2 is what a second copy costs. The value
    /// is still the city's string verbatim — an open vocabulary kept as free text (BUILD-PLAN §7),
    /// so `Sidewalk: Curb side : Cutout` and `Park Strip` are both printed as the city wrote them.
    /// The only thing removed is the string that is not a value at all; see `statedValue`.
    static func siteTypeText(_ raw: String) -> String? { statedValue(raw) }

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
    /// after it — and `nil` for the placeholders `statedValue` refuses, so `N/A` cannot become one
    /// either. Neither column holds one in the shipped seed; the gate is here so that the section's
    /// every card obeys one rule rather than four, which is the property the sweep asserts.
    static func agencyName(_ raw: String) -> String? {
        guard let stated = statedValue(raw) else { return nil }
        return CityRecordCopy.agencyGlossary[stated] ?? stated
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
    /// the subtitle's provenance element, which names the same inventory (`recordSource`).
    /// Provenance sentences repeat by nature — that one is on every screen too.
    ///
    /// ── The line this must not cross ──────────────────────────────────────────────────────────
    /// It is here because a person asked, not because absences are worth listing. The inventory also
    /// records no watering schedule, no soil volume, no root barrier and no inspection date, and none
    /// of those get a line. If this section ever grows a second one, the honest move is a single
    /// "what the city does not record" sentence rather than a growing list — and at that point this
    /// one should be folded into it rather than joined by it.
    ///
    /// ── And it is San Francisco's sentence, so it does not run anywhere else (RULINGS R28) ────
    /// Nil for any id space but `sf`. This is `LandContext.inferred(from:idSpace:)`'s shape and
    /// R24's rule applied to copy rather than to an inference: *a statement about a publisher's
    /// column list is qualified by the id space it was written for, and must decline outside it.*
    ///
    /// The sentence is not a label that could be translated — it is a specific, sourced claim about
    /// what San Francisco publishes: DataSF `tkzw-k3nq` has eighteen columns and no pruning event,
    /// and SF Public Works' own layer carries `Prune_Status` and `Prune_Year` **at keymap-grid
    /// grain**, which is what "by block, not by tree" reports (E143, #91). San Jose's Street Tree
    /// layer publishes no pruning field at all, so the true sentence there is a *different* claim —
    /// "this inventory records nothing about pruning" rather than "it records it at the wrong
    /// grain" — and it would be Cypress stating what is and is not in another city's field list on
    /// the strength of one adapter's column list rather than the city's published metadata. R24's
    /// test is "was this rule written from **this** publisher's documentation", and for San Jose it
    /// was not.
    ///
    /// **So a San Jose reader gets one fewer sentence, and that is the honest outcome rather than a
    /// gap to fill.** The section is not empty for them — the cards and the provenance line both
    /// draw — so E126's "a surface with nothing on it must say why" is not engaged; what E126 and E9
    /// do govern is the temptation to pad, and a translated sentence would be exactly the
    /// plausible-looking stand-in both refuse. Absence renders as absence.
    ///
    /// Nil `idSpace` keeps the sentence, matching `LandContext.inferred(from:idSpace:)` exactly: a
    /// seed built before the column existed is San Francisco's alone, and the sentence is true of it.
    static func pruningNote(idSpace: String?) -> String? {
        guard idSpace == nil || idSpace == CityRecordCopy.sanFranciscoIDSpace else { return nil }
        return CityRecordCopy.pruningNote
    }

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

    /// The section header. It says whose facts these are before the first one is read.
    ///
    /// **Not "City record", which is already a card in the grid above it** (`#13284`, the publisher's
    /// own id, specified by SCREENS.md 14). That card stays where it is drawn — moving a specified
    /// element to make room for an unspecified one is not a trade this round had standing to make —
    /// so this header is worded to sit above it without colliding with it.
    ///
    /// ── It used to read `What San Francisco has on file`, and RULINGS R28 overruled it ─────────
    /// It was drawn when San Francisco was the only city in the file. It is now one of two and D16
    /// makes it one of many, so the header stated the wrong city on 52,788 rows while the provenance
    /// line **inside the same section** named San Jose correctly.
    ///
    /// **This is the one of the four surfaces R28 fixed that does not derive from the row, and the
    /// reason is the type.** The header is a micro-label — uppercase mono with letter-spacing — and
    /// the value the row can honestly supply is the inventory's own published name
    /// (`City of San Jose Street Tree inventory`, 38 characters). Set in that face at that width it
    /// is four wrapped lines of shouting above a two-card grid. So the header names the *kind* of
    /// source, which is true of every municipal inventory the merged table will ever hold, and the
    /// section's own last line names *which one*, in full, with the day it was read
    /// (`inventoryProvenanceNote`). A constant that is true everywhere is not the same defect as a
    /// constant that is true in one city.
    static let header = "What the city has on file"

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

    /// What a data-entry form writes when nobody answered, case-folded. See
    /// `CityRecordPresentation.statedValue` for why matching these is not reading a city's dialect.
    ///
    /// Only `n/a` and `unassigned` occur in the shipped seed. The others are the same idiom spelled
    /// the other common ways, kept against the weekly refresh rather than against a measurement —
    /// which is why this set must never grow a value that could be somebody's real answer.
    static let noValueMarkers: Set<String> = [
        "n/a", "n.a.", "na", "none", "null", "nil", "unassigned", "unknown", "tbd",
        "not applicable", "not available", "not recorded", "no data",
    ]

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

    /// The id space `pruningNote` was written from, and the only one it runs in. The same literal
    /// `LandContext.inferred(from:idSpace:)` guards on, for the same reason (R24).
    static let sanFranciscoIDSpace = "sf"

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
    /// department. What has no per-tree pruning in it is this dataset.
    ///
    /// **This sentence changed with #91 and the change is the point.** It used to read "records no
    /// pruning dates or schedule", which was true of the DataSF export and is not true of the
    /// inventory we now ship: SF Public Works' own layer carries `Prune_Status` and `Prune_Year` on
    /// every record. Those fields are **properties of the keymap grid the tree stands in, not of the
    /// tree** — 133,577 records share 106 distinct `Prune_Year` values, 5,147 of them the single
    /// string `Completed 20210601`, and the city's own About panel says "Last Pruned is the date
    /// associated with the status of a Keymap Grid". So the seed does not carry them and this screen
    /// does not show them. Rendering `Last pruned June 2021` under one tree's name would be the
    /// `Owner of Tree` mistake again (E143): a column read at the wrong grain and asserted as a fact
    /// about the thing in front of you.
    ///
    /// Saying nothing at all was the other option and it is worse. The reader asked when this tree
    /// was last pruned (#68); "we know, per block, and that is not an answer about your tree" is a
    /// real answer, and it is the one that stops the next reader from going to look for the field.
    static let pruningNote =
        "The city's street tree inventory records pruning by block, not by tree, so it says "
        + "nothing about when this tree was last pruned."

    // ── Provenance ───────────────────────────────────────────────────────────────────────────

    /// **Where this record came from, in the subtitle's voice — asked of the row, never of the copy.**
    ///
    /// SCREENS.md 14 draws `Lophostemon confertus · SF city inventory`, and until RULINGS R28 that
    /// second element was a literal on a `switch` over `TreeSource`. It was written when the seed
    /// held one city; it now holds two and D16 makes it one of many, so it said *San Francisco* over
    /// 52,788 San Jose rows while the provenance line at the foot of the same screen said San Jose.
    ///
    /// **The string returned here is `InventorySource.name` — byte for byte the one
    /// `provenanceNote` puts at the bottom of the screen.** That is the point rather than a
    /// coincidence: the top of the profile and the bottom of it now read from one value, so they
    /// cannot disagree again for any city, in any seed. `InventorySource`'s own documentation
    /// already declared `name` to be "the phrase the app puts on screen"; this line simply was not
    /// asking for it.
    ///
    /// **The fallback is city-neutral rather than San Francisco.** A seed built before the
    /// `inventory_*` receipt keys, or a row whose inventory the receipt does not name, cannot say
    /// *which* inventory — but `source == .cityImport` still says it is a municipal one, and that is
    /// the distinction SCREENS.md drew this element for (`city inventory` against
    /// `community-added, unverified`). Naming a city we cannot derive is the defect; naming the
    /// category we can is not.
    static func recordSource(_ source: TreeSource, inventory: InventorySource?) -> String {
        switch source {
        case .cityImport: return inventory?.name ?? unnamedCityInventory
        case .community: return communityAdded
        }
    }

    /// See `recordSource`. Not `SF city inventory`, and never again a city this app cannot derive.
    static let unnamedCityInventory = "city inventory"
    static let communityAdded = "community-added, unverified"

    /// `#167879` — the publishing inventory's own id for this record, which is the citable one
    /// (BUILD-PLAN §7, RULINGS R18).
    ///
    /// **The `SF ` that used to lead it is gone, and R28 records why the number survived and the
    /// city half did not.** `SF #167879` was doing two jobs. The number is San Francisco's `TreeID`
    /// or San Jose's `FACILITYID` — different columns, same kind of thing, and the only string a
    /// reader can carry back to the city that issued it. The prefix named a city, and on a San Jose
    /// row it named the wrong one.
    ///
    /// **It is not replaced by the qualified identity.** `us-ca-sj:167879` is R18's *identity* key —
    /// the string the uuid is derived from — and it exists so two cities' numberings cannot collide
    /// in one table. It is Cypress's namespacing, not the city's record number, and printing it
    /// would hand the reader a slug that means nothing in San Jose's own asset system.
    ///
    /// Nothing is lost by dropping the prefix, because the card's label already reads `City record`
    /// and *which* city is stated twice more on the same screen — in the subtitle (`recordSource`)
    /// and in the section's provenance line (`provenanceNote`), both derived from the row.
    static func recordNumber(_ ref: String) -> String { "#\(ref)" }

    /// `From the SF Public Works street tree inventory, 26 July 2026.`
    ///
    /// The last line of the section, and the one that makes every line above it checkable. Before
    /// #91 the app named no source and no date for any of these facts, so "is our data stale?" had
    /// no answer anywhere in the product — not on screen, not in a log, not in the database. A
    /// reader who disagrees with a card can now go to the same inventory on the same day and see for
    /// themselves.
    ///
    /// **The date is the source's, never today's.** It comes from `seed_meta.trees_snapshot_on`,
    /// which the build writes from the extraction's own record. If it is absent the whole sentence
    /// is absent: a provenance line carrying a date the app inferred would be worse than no line.
    static func provenanceNote(source: String, snapshot: String) -> String {
        "From the \(source), \(snapshot)."
    }
}
