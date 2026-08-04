//
//  CityPresentation.swift
//  Cypress — Features/City
//
//  The Journal tab's third segment. `docs/rulings-pending/journal-city-segment.md`.
//
//  ── What this screen is, in one line ──────────────────────────────────────────────────────────
//  The owner's ask: "similar but not identical stats and views to what's on the neighborhood view
//  [the almanac]. Should be insightful, interesting, educative, not pure data porn and not
//  overwhelming." Three cards, each answering a question the almanac cannot: how your own street
//  differs from the city as a whole, what the whole city's canopy is made of, and how far back the
//  city's own paperwork goes.
//
//  ── The two rules this file exists to keep, both inherited from `AlmanacPresentation` ──────────
//  - **ARCHITECTURE §5.6 / A9 — an aggregate below its threshold does not render at all.** Every
//    block here is an optional, exactly as every block on screen 12 is, and `isEmpty` exists so a
//    caller never has to guess whether there is anything between the header and the footnote.
//  - **ARCHITECTURE §5.1 / D1 — no counts of user actions, no ranks, no leaderboards.** Every number
//    on this screen counts trees. Nothing here can be ordered by contributor and nothing here reads
//    a contributor's identity.
//
//  ── The rule this file adds, that `AlmanacPresentation` never needed ─────────────────────────
//  **Nothing on this screen, or in this file, ever prints a city's proper name.** See `City.swift`
//  for why: the fused seed carries no display name for a city, only for a city's *inventory*, and
//  the one place this app does carry a hand-entered civic name (`CityManifest.displayName`) is
//  fetched over a network this screen must not depend on. So the header names the segment, `City`,
//  and nothing lower on the screen ever tries to be more specific than the record can support.
//
//  No SwiftUI in this file, so all of the above is testable without a renderer
//  (`CypressTests/CityPresentationTests.swift`).
//

import Foundation

// MARK: - Presentation

/// Everything the City segment renders, derived from one `CityAlmanac` payload.
struct CityPresentation: Equatable {

    /// One sentence of card 1: one species, stated as a local share against a citywide one.
    struct ContrastRow: Equatable, Identifiable {
        var id: UUID { speciesID }
        let speciesID: UUID
        /// `Monterey cypress is 18% of the trees near you and 4% citywide.`
        let sentence: String
    }

    /// Card 1, `Your streets, against the city` — present only when at least one species clears
    /// both `CityLimits` floors (a real local sample, a real gap). This is the card the owner's
    /// brief calls the reason the screen exists, and the only one of the three that cannot be
    /// learned from either the almanac or the species page alone: the almanac never compares to the
    /// city, and the species page's citywide count (RULINGS R48) never compares to a street.
    struct Contrast: Equatable {
        let label: String
        let rows: [ContrastRow]
    }

    /// Card 3, `The oldest on file` — present only when the city holds at least one standing tree
    /// with a recorded planting date.
    struct OldestBlock: Equatable {
        /// The micro-label, fixed regardless of how many rows are drawn or why.
        let label: String
        /// The sentence that carries the hedge and, when it applies, the truncation caveat — see
        /// `CityCopy.recordNote`. Always present when the block is, because the coordinator's own
        /// instruction is that this card cannot rely on a per-row phrase alone to say what it is.
        let note: String
        let rows: [Row]

        struct Row: Equatable, Identifiable {
            let id: UUID
            /// The tree's own identity — its given name, then its species, then its street — never
            /// a rank or an ordinal (`CityCopy.recordSubject`).
            let title: String
            /// `in the city record since 1898` — `AlmanacCopy.elderSubtitle`'s own hedge, word for
            /// word, never "planted in".
            let subtitle: String
            let treeID: UUID
            let heroPhotoID: UUID?
        }
    }

    /// Whether a city resolved at all (ERRATA E182's distinction, applied here). `false` means the
    /// reader is standing somewhere the attached inventory does not reach — never a resolved city
    /// with nothing to say about it, which is `isEmpty` below.
    let hasCity: Bool

    let contrast: Contrast?
    /// Card 2, `Who lives here · N species` — `AlmanacPresentation.composition(_:locale:)`, reused
    /// verbatim and scoped to the whole city instead of a neighborhood, so the remainder-row math
    /// (unrounded shares, "Everyone else" credited with exactly what is left) cannot drift between
    /// the two cards a reader is meant to compare.
    let composition: AlmanacPresentation.Composition?
    let oldest: OldestBlock?

    /// Always drawn once a city has resolved — the screen's own closing line, in the almanac's
    /// voice and not its words (see `CityCopy.footnote`).
    var footnote: String { CityCopy.footnote }

    /// Whether anything sits between the header and the footnote, for a resolved city with nothing
    /// yet to report. Unreached by the shipped seed — both cities clear every floor below — but kept
    /// so a thin future inventory renders its chrome honestly rather than three absent optionals
    /// with no explanation, the same care `AlmanacPresentation.isEmpty` takes.
    var isEmpty: Bool { contrast == nil && composition == nil && oldest == nil }

    // MARK: - Derivation

    init(city: CityAlmanac, locale: Locale = .current) {
        guard let snapshot = city.snapshot else {
            self.hasCity = false
            self.contrast = nil
            self.composition = nil
            self.oldest = nil
            return
        }
        self.hasCity = true
        self.contrast = Self.contrast(
            local: snapshot.localComposition,
            city: snapshot.cityComposition,
            locale: locale
        )
        self.composition = AlmanacPresentation.composition(snapshot.cityComposition, locale: locale)
        self.oldest = Self.oldest(snapshot.oldest)
    }

    // MARK: - Card 1 · Your streets, against the city

    /// One internal candidate: a species, its local share, its citywide share and the gap between
    /// them — computed once so every downstream step reads the same three numbers.
    private struct Candidate {
        let share: SpeciesShare
        let localShare: Double
        let cityShare: Double
        var diffPoints: Double { (localShare - cityShare) * 100 }
    }

    /// The two or three species markedly more common near the reader than across the whole city.
    ///
    /// **Every floor named here is `CityLimits`'s, and every one is NOT SPECIFIED** — chosen and
    /// documented there rather than invented silently. Three gates, applied in order:
    /// 1. the local scope itself must hold a real sample
    ///    (`CityLimits.minimumLocalTreesForContrast`) — the almanac's own composition card asks for
    ///    nothing narrower than "the read came back non-empty", and this asks for slightly more,
    ///    because a comparison (unlike a listing) can be actively misleading at a tiny sample rather
    ///    than merely thin;
    /// 2. a candidate species needs enough of its own trees nearby
    ///    (`CityLimits.minimumLocalSpeciesCount`) that one planting cannot read as a pattern;
    /// 3. the gap itself has to be real (`CityLimits.minimumDivergencePoints`), which is A9 applied
    ///    to a comparison rather than to a count: no data behind a claim is not a smaller claim, it
    ///    is no card.
    private static func contrast(
        local: NeighborhoodComposition?,
        city: NeighborhoodComposition?,
        locale: Locale
    ) -> Contrast? {
        guard let local, let city,
              local.treeCount >= CityLimits.minimumLocalTreesForContrast,
              city.treeCount > 0
        else { return nil }

        let cityByID = Dictionary(uniqueKeysWithValues: city.leading.map { ($0.speciesID, $0) })
        let localTotal = Double(local.treeCount)
        let cityTotal = Double(city.treeCount)

        let candidates: [Candidate] = local.leading.compactMap { share in
            guard share.treeCount >= CityLimits.minimumLocalSpeciesCount else { return nil }
            let candidate = Candidate(
                share: share,
                localShare: Double(share.treeCount) / localTotal,
                cityShare: Double(cityByID[share.speciesID]?.treeCount ?? 0) / cityTotal
            )
            return candidate.diffPoints >= CityLimits.minimumDivergencePoints ? candidate : nil
        }
        .sorted { $0.diffPoints > $1.diffPoints }

        let rows = candidates.prefix(CityLimits.maximumDivergentSpecies).map { candidate in
            ContrastRow(
                speciesID: candidate.share.speciesID,
                sentence: CityCopy.contrastSentence(
                    name: candidate.share.name,
                    localShare: candidate.localShare,
                    cityShare: candidate.cityShare,
                    locale: locale
                )
            )
        }
        guard !rows.isEmpty else { return nil }
        return Contrast(label: CityCopy.contrastLabel, rows: rows)
    }

    // MARK: - Card 3 · The oldest on file

    /// Up to `CityLimits.oldestRowLimit` trees, and the one sentence that says whether there might
    /// be more tied for last place.
    ///
    /// `all` is handed one row past the cut (`CityQueries.oldestOnFile`'s own contract) precisely so
    /// this can tell: if a row past the cut shares the last drawn row's planting year, the list is
    /// not defensibly "the five oldest" — some other tree from the same year was left off arbitrarily
    /// — and the note says the truer, weaker thing instead (the coordinator's own instruction).
    private static func oldest(_ all: [ElderTree]) -> OldestBlock? {
        let shown = Array(all.prefix(CityLimits.oldestRowLimit))
        guard let last = shown.last else { return nil }

        let tiedAtBoundary = all.count > shown.count && all[shown.count].plantedYear == last.plantedYear

        let rows = shown.map { tree in
            OldestBlock.Row(
                id: tree.treeID,
                title: CityCopy.recordSubject(
                    name: tree.activeName,
                    species: tree.speciesCommonName,
                    street: AlmanacCopy.street(from: tree.address)
                ),
                subtitle: CityCopy.recordSince(tree.plantedYear),
                treeID: tree.treeID,
                heroPhotoID: tree.heroPhotoID
            )
        }

        return OldestBlock(
            label: CityCopy.recordLabel,
            note: CityCopy.recordNote(tiedAtBoundary: tiedAtBoundary),
            rows: rows
        )
    }
}

// MARK: - Copy

/// The City segment's strings. Every sentence states a fact and stops (ARCHITECTURE §5.7), sentence
/// case, no city named anywhere (see the file header).
enum CityCopy {

    /// The segment's own label on C5, and the screen's C1 title.
    static let segmentLabel = "City"

    // MARK: Card 1 — Your streets, against the city

    static let contrastLabel = "Your streets, against the city"

    /// `Monterey cypress is 18% of the trees near you and 4% citywide.`
    ///
    /// Two independently-rounded percentages (`AlmanacCopy.percent`), not a percentage and a
    /// difference — a reader can already see the gap, and printing it a second way as "14 points
    /// more" would be the same fact dressed as a second number, which is the kind of small excess
    /// "not pure data porn" is asking this screen to avoid.
    static func contrastSentence(name: String, localShare: Double, cityShare: Double, locale: Locale) -> String {
        "\(name) is \(AlmanacCopy.percent(localShare, locale: locale)) of the trees near you "
            + "and \(AlmanacCopy.percent(cityShare, locale: locale)) citywide."
    }

    // MARK: Card 3 — The oldest on file

    static let recordLabel = "The oldest on file"

    /// The card-level hedge the coordinator asked for: with one elder, the row's own "in the city
    /// record since" carries the whole distinction; with five, a reader skimming the list is more
    /// likely to read it as five old *trees* than as five old *dates*, so the card says the
    /// distinction once for itself rather than trusting five repetitions of one clause to do it.
    static func recordNote(tiedAtBoundary: Bool) -> String {
        let base = "These are the oldest planting dates on file, not the oldest trees — "
            + "most of the record carries no planting date at all."
        guard tiedAtBoundary else { return base }
        return base + " At least one more tree on file shares the last one's year."
    }

    /// `in the city record since 1898` — `AlmanacCopy.elderSubtitle`'s own hedge and its own reason:
    /// DataSF fills a planting date on a minority of rows, so this is the oldest *recorded* date,
    /// never "planted in".
    static func recordSince(_ plantedYear: Int) -> String {
        "in the city record since \(AlmanacCopy.year(plantedYear))"
    }

    /// A tree's own identity for a list row: its given name, then its species, then its street, then
    /// the app's own fallback — the same chain `AlmanacCopy.elderSubtitle` resolves for the almanac's
    /// single elder, split out here because a list of five needs a title *and* a subtitle rather than
    /// one combined sentence.
    static func recordSubject(name: String?, species: String?, street: String?) -> String {
        if let name { return name }
        if let species { return species }
        if let street { return "The tree on \(street)" }
        return TreeProfilePresentation.fallbackTitle
    }

    // MARK: Nowhere the record reaches (mirrors `AlmanacCopy`'s state, not its words)

    static let outOfRangeTitle = "No city inventory reaches here yet."
    static let outOfRangeBody = "This screen is built from city tree inventories, and none of the "
        + "ones on this phone covers where you are. It fills in as more cities join the record."

    // MARK: The read that did not arrive

    static let loadFailed = "The city could not be loaded."
    static let loadRetry = "Try again"

    // MARK: Location

    static let locationPromptTitle = "See your city"
    static let locationPromptSubtitle = "Turn on location and this screen fills in with your city's own record."

    // MARK: Footnote

    /// The screen's own closing line — the almanac's kind of sentence, not its words (the brief's
    /// own instruction). Same job: no rank, no counter, nothing measuring the reader.
    static let footnote = "No leaderboard, no city ranking. Just what the record holds."
}
