//
//  GrovePresentation.swift
//  Cypress — Features/Grove
//
//  Screen 08 · Species you know (My Grove · Species tab). SCREENS.md lines 923–957.
//
//  The first screen keyed on the contributor rather than on a tree, which is why it is the one most
//  exposed to DECISIONS §3.1. Three rules do most of the work here, and all three are about what
//  this screen must NOT say:
//
//  - **D1 / ARCHITECTURE §5.1 — nothing counts a person's actions.** The ring's numerator is how
//    many *species* the contributor can recognise, not how many visits, photographs or care events
//    they logged; the tiles carry a species name and no history; `KnownSpecies` has no count on it
//    at all. The screen's own footnote — "Quiet collecting. There are no streaks and no
//    leaderboards." — is not decoration, it is the specification of this file.
//  - **D11 — private by default.** Every number here is about the viewer's own device and never
//    leaves it. There is no comparison to anybody, because there is no other body of data to
//    compare against; the API has no method that could fetch one.
//  - **Pages are not totals (ERRATA E38).** The ring prints two numbers. Both come from
//    `Series.totalCount`, which is `nil` unless the read proved it had everything, and a `nil` on
//    either side removes the whole block rather than printing a plausible wrong fraction.
//
//  No SwiftUI in this file. Everything the view draws is decided here, so the rules above can be
//  tested without a renderer (`CypressTests/GrovePresentationTests.swift`).
//

import Foundation

// MARK: - Sub-tabs

/// The three pills SCREENS.md 08 §2 draws under the title: `Trees`, `Journal`, `Species`.
///
/// Only `species` has a screen. The prototype makes the other two inert on this screen
/// (PROTOTYPE-FLOW §1.5 `grove`: "Progress card, neighborhood callout, steward card, tabs My Grove /
/// Journal / You — **inert**"), and BUILD-PLAN §9 M2 lists the empty journal as a build requirement
/// that has not been built. So they are drawn, because 08 draws them, and they do nothing, because
/// there is nowhere for them to go (DECISIONS constraint 21). See ERRATA E46.
enum GroveTab: String, CaseIterable, Identifiable {
    case trees
    case journal
    case species

    var id: String { rawValue }

    /// Verbatim from SCREENS.md 08 §2.
    var label: String {
        switch self {
        case .trees: return "Trees"
        case .journal: return "Journal"
        case .species: return "Species"
        }
    }

    /// Whether tapping the pill leads anywhere. Screen 08 is the Species tab; the other two have no
    /// built destination and no mocked one.
    var hasDestination: Bool { self == .species }
}

// MARK: - Presentation

/// Everything screen 08 renders, derived from one `GroveSpecies` payload.
struct GrovePresentation: Equatable {

    /// The ring and the sentence beside it (SCREENS.md 08 §3).
    struct Progress: Equatable {
        /// 0…1, for C27. `12 of 40` draws at 30%, which is what the mock's conic gradient states.
        let fraction: Double
        /// The ring's own label, `30%`.
        let ringLabel: String
        /// `12 of 40 species`.
        let headline: String
        /// `you can recognize in the Outer Sunset`.
        let caption: String
    }

    /// One cell of the C29 grid.
    enum Tile: Equatable, Identifiable {
        case known(id: UUID, label: String, art: CypressGradient.SpeciesTileArt)
        /// SCREENS.md 08 §5 rows 7 and 9 — `#E9ECDE` with a centred `?`.
        case locked(index: Int)

        var id: String {
            switch self {
            case let .known(id, _, _): return id.uuidString
            case let .locked(index): return "locked-\(index)"
            }
        }
    }

    /// The gradient callout (C14 gradient, SCREENS.md 08 §4).
    struct Celebration: Equatable {
        /// `New species!`
        let leadIn: String
        /// ` First Victorian Box, spotted yesterday on Noriega.` — the leading space is the mock's.
        let body: String
    }

    let progress: Progress?
    let celebration: Celebration?
    let tiles: [Tile]

    /// Always drawn. It is the only content the empty grove has, and it is the sentence that makes
    /// the screen honest whatever else is on it.
    var footnote: String { GroveCopy.footnote }

    /// Whether anything at all sits between the tab row and the footnote.
    ///
    /// BUILD-PLAN §9 M2 requires an "empty grove" and no mock draws one, so what is *absent* here is
    /// the design decision: the ring, the callout and the grid are all derived from contributions,
    /// and a device that has made none renders none of them (ARCHITECTURE §5.6). See ERRATA E48.
    var isEmpty: Bool { progress == nil && celebration == nil && tiles.isEmpty }

    // MARK: - Derivation

    init(grove: GroveSpecies, now: Date = .now, calendar: Calendar = .current) {
        // Oldest first: a collection reads in the order it was built, and a new find appends rather
        // than reshuffling everything above it. **NOT SPECIFIED** — SCREENS.md 08 §5 gives nine
        // tiles in a fixed order with no rule behind it (its own "New species!", Victorian Box,
        // sits fourth, so the mock is not recency-ordered either). See ERRATA E49.
        //
        // `Series.sorted` is used rather than sorting `items`, because sorting through the `Series`
        // is what keeps the completeness attached to the rows all the way to the counts below.
        let known = grove.known.sorted { $0.firstMetAt < $1.firstMetAt }

        let recognisedHere = grove.neighborhood.map { neighborhood in
            // Intersection, with `Series.filter` so a page cannot become a total on the way through.
            // Both sides have to be whole for the result to be whole, which `filter` preserves and
            // `Progress` then checks.
            known.filter { Set(neighborhood.species.items).contains($0.speciesID) }
        }

        self.progress = Self.progress(
            recognisedHere: recognisedHere,
            neighborhood: grove.neighborhood
        )
        self.tiles = Self.tiles(known: known, neighborhood: grove.neighborhood, recognisedHere: recognisedHere)
        self.celebration = Self.celebration(known: known, now: now, calendar: calendar)
    }

    // MARK: - The ring

    /// SCREENS.md 08 §3: C27 at `30%`, beside `12 of 40 species` / `you can recognize in the Outer
    /// Sunset`.
    ///
    /// **What the ring measures, precisely.** Numerator: species this contributor has met that also
    /// grow in their own neighbourhood. Denominator: every species the *city's* inventory records in
    /// that neighbourhood. So it is not a score — nothing the contributor does can raise the
    /// denominator, and no other person appears in either half. It is "how much of what grows around
    /// you do you now know", which is knowledge rather than activity, and is the replacement loop
    /// DECISIONS §2.6 adopted in place of the leaderboard ("recognition through knowing trees over
    /// time").
    ///
    /// Renders only when **both** reads were complete and at least one species is recognised.
    /// - Incomplete either side → nothing, because a page counted as a total is E38 again, and here
    ///   it would flatter: a short denominator makes the ring too full.
    /// - Zero recognised → nothing, per A9 and ARCHITECTURE §5.6 ("aggregate surfaces below their
    ///   cold-start threshold do not render at all"). A ring at 0% captioned "you can recognize in
    ///   the Sunset" is an aggregate with no data in it.
    private static func progress(
        recognisedHere: Series<KnownSpecies>?,
        neighborhood: GroveNeighborhood?
    ) -> Progress? {
        guard let neighborhood, let recognisedHere else { return nil }
        guard let numerator = recognisedHere.totalCount,
              let denominator = neighborhood.species.totalCount,
              denominator > 0,
              numerator >= GroveThresholds.minimumRecognisedSpecies
        else { return nil }

        let fraction = min(Double(numerator) / Double(denominator), 1)
        return Progress(
            fraction: fraction,
            ringLabel: GroveCopy.ringLabel(fraction: fraction),
            headline: GroveCopy.headline(recognised: numerator, total: denominator),
            caption: GroveCopy.caption(neighborhood: neighborhood.name)
        )
    }

    // MARK: - The grid

    /// The known tiles, then locked tiles to square off the last row.
    ///
    /// **NOT SPECIFIED.** SCREENS.md 08 §5 draws nine cells — seven species and two locked — and
    /// states no rule for how many locked tiles there are or where they sit (its two are at
    /// positions 7 and 9, interleaved, under no stated pattern). Padding the final row is the
    /// smallest rule that reproduces the drawn grid for the drawn data and never asserts a number:
    /// it is a layout decision, and a locked tile means "a species you have not met", which stays
    /// true whether two or two hundred remain.
    ///
    /// The cap is the honesty clause. A contributor who knows all but one of their neighbourhood's
    /// species sees one locked tile, not two — the padding can never claim there is more left to
    /// meet than there is. Where the neighbourhood is unknown there is nothing to cap against and
    /// no locked tile is drawn at all. See ERRATA E49.
    private static func tiles(
        known: Series<KnownSpecies>,
        neighborhood: GroveNeighborhood?,
        recognisedHere: Series<KnownSpecies>?
    ) -> [Tile] {
        // A page of species is a real collection of species — every row in it is one the contributor
        // genuinely met — so unlike the counts, the grid may render from an incomplete read. What it
        // must not do is pad it: the last row of a page is not the last row of the series.
        let cells = known.items.map { species in
            Tile.known(
                id: species.speciesID,
                label: species.commonName,
                art: SpeciesTileArtwork.art(for: species)
            )
        }
        guard !cells.isEmpty, known.isComplete else { return cells }

        let remainderOfRow = (GroveMetrics.gridColumns - cells.count % GroveMetrics.gridColumns)
            % GroveMetrics.gridColumns
        guard remainderOfRow > 0 else { return cells }

        guard let neighborhood,
              let total = neighborhood.species.totalCount,
              let recognised = recognisedHere?.totalCount
        else { return cells }

        let leftToMeet = max(total - recognised, 0)
        let lockedCount = min(remainderOfRow, leftToMeet)
        return cells + (0..<lockedCount).map { Tile.locked(index: $0) }
    }

    // MARK: - The celebration

    /// SCREENS.md 08 §4, and the caption's "a new find gets a small celebration".
    ///
    /// **The window is the vocabulary.** The mock's one drawn instance says `spotted yesterday`, and
    /// no other relative phrasing for this callout exists anywhere in the sources. Rather than
    /// invent a ramp ("3 days ago", "last week") and a window to go with it, the callout renders for
    /// exactly the two days the drawn copy can describe — today and yesterday — and says one of
    /// those two words. Nothing here is generated for a day the mock has no word for. See ERRATA E49.
    private static func celebration(
        known: Series<KnownSpecies>,
        now: Date,
        calendar: Calendar
    ) -> Celebration? {
        guard let newest = known.items.max(by: { $0.firstMetAt < $1.firstMetAt }) else { return nil }
        guard let day = GroveCopy.recentDay(newest.firstMetAt, now: now, calendar: calendar) else {
            return nil
        }
        return Celebration(
            leadIn: GroveCopy.celebrationLeadIn,
            body: GroveCopy.celebrationBody(
                species: newest.commonName,
                day: day,
                street: GroveCopy.street(from: newest.firstMetAddress)
            )
        )
    }
}

// MARK: - Thresholds

/// The cold-start floors this screen holds (ARCHITECTURE §5.6, A9).
enum GroveThresholds {
    /// A9's shape, applied here: "bloom sightings need 1". One recognised species is the least a
    /// ring captioned "you can recognize in ___" can be about. A8's 3 is not the analogue — that
    /// threshold protects *other people's* identities on a public surface, and this surface has
    /// neither.
    static let minimumRecognisedSpecies = 1
}

// MARK: - Copy

/// Screen 08's strings, verbatim from SCREENS.md including its typographic characters.
enum GroveCopy {

    static let screenTitle = "My Grove"

    /// §6, verbatim. Centred, 12px, `text.faintAlt`.
    static let footnote = "Quiet collecting. There are no streaks and no leaderboards."

    /// §4's bold lead-in, verbatim.
    static let celebrationLeadIn = "New species!"

    /// §3: `12 of 40 species`. The numbers are the contributor's and the city's; the words are the
    /// mock's.
    static func headline(recognised: Int, total: Int) -> String {
        "\(recognised) of \(total) species"
    }

    /// §3: `you can recognize in the Outer Sunset`.
    ///
    /// The definite article is the mock's and it is kept, which is what makes the neighbourhood name
    /// read as a place. The name itself is the seed's, verbatim — SF's own polygon set (A4) has no
    /// "Outer Sunset"; the Sunset is one neighbourhood named `Sunset/Parkside`. See ERRATA E47.
    static func caption(neighborhood: String) -> String {
        "you can recognize in the \(neighborhood)"
    }

    /// C27's inner label, `30%`. Rounded down, so a ring that is not yet full never says it is.
    static func ringLabel(fraction: Double) -> String {
        "\(Int((fraction * 100).rounded(.down)))%"
    }

    /// §4: ` First Victorian Box, spotted yesterday on Noriega.`
    ///
    /// The leading space belongs to the string: SCREENS.md writes the callout as a bold run followed
    /// by this, and C14 renders the two adjacent.
    static func celebrationBody(species: String, day: RecentDay, street: String?) -> String {
        var sentence = " First \(species), spotted \(day.word)"
        if let street { sentence += " on \(street)" }
        return sentence + "."
    }

    /// The two days the drawn copy has a word for.
    enum RecentDay: String, Equatable {
        case today
        case yesterday

        var word: String { rawValue }
    }

    /// `today` / `yesterday`, or nil for anything older — see `GrovePresentation.celebration`.
    static func recentDay(_ date: Date, now: Date, calendar: Calendar) -> RecentDay? {
        if calendar.isDate(date, inSameDayAs: now) { return .today }
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else { return nil }
        return calendar.isDate(date, inSameDayAs: yesterday) ? .yesterday : nil
    }

    /// `1450 Noriega St` → `Noriega St`.
    ///
    /// The house number is dropped and nothing else is: the mock writes `on Noriega`, which also
    /// drops the `St`, but stripping a street *type* means deciding which trailing words are types,
    /// and getting that wrong renames a street. Dropping the leading number is unambiguous — it is
    /// the part that is a number — and it is the part that would otherwise put a specific doorway in
    /// a sentence about a species (DECISIONS §3.11's principle, on a private screen).
    ///
    /// Returns nil when the city recorded no address, which drops the clause rather than inventing
    /// a location.
    static func street(from address: String?) -> String? {
        guard let address else { return nil }
        let trimmed = address.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        var parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
        if parts.count > 1, parts[0].first?.isNumber == true {
            parts.removeFirst()
        }
        let street = parts.joined(separator: " ")
        return street.isEmpty ? nil : street
    }
}

// MARK: - Tile artwork

/// Which of C29's seven gradients a species is drawn with.
///
/// SCREENS.md §2 authors artwork for exactly the seven species screen 08 happens to draw; the seed
/// carries 569 and no photograph exists for any of them. This is the same problem `MapModel`
/// already solved for C22, and deliberately the same answer: genus decides where it can, a stable
/// hash of the name decides the rest, the same species always gets the same tile, and **none of it
/// claims to be a picture of that species** — a C29 tile is an abstract gradient with a name written
/// on it. Fabricating a likeness would be fabricating content (BUILD-PLAN §15).
enum SpeciesTileArtwork {

    /// Genus → the art the design itself labels with that genus's common name. Nothing is asserted
    /// here that SCREENS.md 08 §5 does not already assert by naming its own tiles.
    private static let byGenus: [String: CypressGradient.SpeciesTileArt] = [
        "cupressus": .montereyCypress,
        "hesperocyparis": .montereyCypress,
        "ginkgo": .ginkgo,
        "platanus": .londonPlane,
        "pittosporum": .victorianBox,
        "corymbia": .redFloweringGum,
        "eucalyptus": .redFloweringGum,
        "metrosideros": .pohutukawa,
        "lophostemon": .brisbaneBox,
        "tristania": .brisbaneBox
    ]

    static func art(for species: KnownSpecies) -> CypressGradient.SpeciesTileArt {
        let latin = species.scientificName.lowercased()
        if let genus = latin.split(separator: " ").first.map(String.init),
           let art = byGenus[genus] {
            return art
        }
        let all = CypressGradient.SpeciesTileArt.allCases
        let bucket = abs(latin.utf8.reduce(0) { ($0 &* 31 &+ Int($1)) % 9_973 })
        return all[bucket % all.count]
    }
}

// MARK: - Screen metrics

/// The margins SCREENS.md gives screen 08 that `CypressSpacing` does not already name.
///
/// Same arrangement as `ReportMetrics` and `TreeProfileMetrics`: screen-specific geometry is named
/// once here so the view body carries no loose numbers, while every colour and font stays a
/// `DesignSystem` token (ARCHITECTURE §6).
enum GroveMetrics {
    /// §5: `grid-template-columns:repeat(3,1fr)`.
    static let gridColumns = 3

    /// §1: title `padding:10px 18px 4px` — the same rhythm C1 uses, without a back button (08 is a
    /// tab root, so there is nothing to go back to).
    static let titleTop: CGFloat = CypressSpacing.headerPaddingTop
    static let titleBottom: CGFloat = CypressSpacing.headerPaddingBottom

    /// §2: tab row `padding:8px 18px 14px`, `gap:8px`.
    static let tabRowTop: CGFloat = 8
    static let tabRowBottom: CGFloat = 14
    static let tabRowGap: CGFloat = CypressSpacing.gapRows
    /// §2: each pill `padding:9px 2px`, radius 11px (`CypressRadius.grovePill`).
    static let tabPillPaddingV: CGFloat = 9
    static let tabPillPaddingH: CGFloat = 2

    /// §3: progress block `padding:2px 18px 0`, `HStack(spacing:16)`.
    static let progressTop: CGFloat = 2
    static let progressSpacing: CGFloat = 16
    /// Gap between the headline and the caption beneath it. **NOT SPECIFIED** — §3 gives the two
    /// lines and no gap. Zero, so they set as one block, which is what the mock's line box shows.
    static let progressLineGap: CGFloat = 0

    /// §4: celebration callout `margin:14px 16px 0`.
    static let calloutTop: CGFloat = CypressSpacing.labelSectionTop

    /// §5: grid `padding:14px 16px 0`.
    static let gridTop: CGFloat = CypressSpacing.labelSectionTop

    /// §6: footnote `padding:14px 18px`, `margin-top:auto`.
    static let footnoteTop: CGFloat = CypressSpacing.labelSectionTop
    static let footnoteBottom: CGFloat = CypressSpacing.labelSectionTop
}
