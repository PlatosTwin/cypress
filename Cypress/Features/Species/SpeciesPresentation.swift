//
//  SpeciesPresentation.swift
//  Cypress — Features/Species
//
//  Screen 07 · Species page. SCREENS.md lines 886–917.
//
//  The field-guide entry: what this kind of tree is, how to recognise it, what it does through the
//  year, and how common it is nearby.
//
//  ── The rule this screen exists to obey ───────────────────────────────────────────────────
//  It renders sourced content and it renders *nothing* where knowledge is absent. Three separate
//  absences run through it and none of them has a placeholder:
//
//  1. `Species.leafRetention` is optional. 59 of the 569 seeded species have no sourced habit, and
//     a species with `nil` gets **no** phenology surface — not a neutral chip, not a grey one,
//     nothing (D5, ERRATA E9, ARCHITECTURE §5.5). Nowhere in this folder is there a `?? .deciduous`
//     or any other default, because a default is the bug.
//  2. Only 40 of the 569 carry curated content. The other 529 render a hero, a family chip, a habit
//     chip if their habit is known, and the population cards. That mostly-empty page is the correct
//     output for a species nobody has authored (BUILD-PLAN §8: the long tail gets "name, family,
//     and a generic silhouette"). SCREENS.md draws no empty state for it and none is invented here
//     — see ERRATA (E43).
//  3. Without a location fix there is no "your area" and no distance, so the `Near you` card and
//     the nearby list are absent rather than empty.
//
//  No SwiftUI in this file. Everything the view draws is decided here, so the absences can be
//  reasoned about — and tested — without a renderer.
//

import Foundation

// MARK: - Taxonomy chips

/// One meta chip in 07 §2's row.
///
/// A `String` would have been enough to draw them, and that is precisely why this is not one: the
/// habit chip is the screen's phenology surface, and the only guarantee that an unsourced species
/// does not get one is that there is no way to construct `.habit` from a `nil` `LeafRetention`.
struct SpeciesTaxonomyChip: Hashable, Identifiable {

    enum Kind: Hashable {
        /// `Cupressaceae` — `species.family`. Absent for the 8 seeded species with no family.
        case family
        /// `Evergreen` — derived from `species.leafRetention`, and constructible from nothing else.
        case habit
    }

    let kind: Kind
    let label: String

    var id: Kind { kind }

    /// The family chip, or nothing when GBIF resolved no family for this string.
    static func family(_ family: String?) -> SpeciesTaxonomyChip? {
        guard let family, !family.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return SpeciesTaxonomyChip(kind: .family, label: family)
    }

    /// The habit chip, or nothing when nobody has established this species' habit (ERRATA E9).
    ///
    /// This is the whole of the phenology surface on screen 07, and `nil` in means nothing out.
    /// There is no other initializer for `.habit`.
    static func habit(_ retention: LeafRetention?) -> SpeciesTaxonomyChip? {
        guard let retention else { return nil }
        return SpeciesTaxonomyChip(kind: .habit, label: LeafRetentionLabel.text(for: retention))
    }
}

// MARK: - Recognize-it bullets

/// One bullet of 07 §3's `How to recognize it` card: a leaf glyph and an authored sentence.
struct SpeciesIDTipRow: Hashable, Identifiable {

    /// The three tints SCREENS.md 07 §3 gives the three glyphs, in the order it gives them.
    enum Tint: Int, Hashable, CaseIterable {
        case canopy
        case newGrowth
        case bark
    }

    let index: Int
    let tip: IDTip

    var id: Int { index }

    /// The glyph tint.
    ///
    /// **By position, not by icon.** SCREENS.md gives three colours against three bullets whose
    /// icons happen to be leaf, leaf and bark; reading a colour off `IDTip.icon` would mean
    /// inventing tints for `flower`, `fruit`, `cone`, `form` and `trunk`, which the spec never
    /// draws. Cycling the drawn three keeps a four-tip species (there are several) inside the
    /// palette that was actually specified.
    var tint: Tint { Tint.allCases[index % Tint.allCases.count] }
}

// MARK: - The seasonal callout

/// 07 §4's gradient callout — `In July:` followed by what to look for.
///
/// **It draws only from an authored care note whose month window is restricted**, and there is
/// exactly one such note in the shipped seed (Jacaranda, March–May, "Expect leaf drop in spring").
/// Twenty other curated species carry a care note whose window is `{start: 1, end: 12}`, and
/// `curated.yaml` says in its own header what that means: "the source attaches no month
/// restriction". Printing one of those under `In July:` would turn a year-round note into a claim
/// about July that no source makes.
///
/// The seasonal calendar is deliberately *not* a second source for this. `fall_color_months` says
/// that a Ginkgo colours in November; it does not say what to look for, and writing that sentence
/// would be writing botany (DECISIONS constraint 15).
struct SpeciesSeasonalNote: Hashable {
    /// The month the note is being shown in, 1…12.
    let month: Int
    /// The authored sentence, verbatim.
    let text: String
}

// MARK: - Presentation

/// The derivation the view renders. A value, recomputed from the payload.
struct SpeciesPresentation: Equatable {

    let species: Species
    let cityTreeCount: Int?
    let nearYou: SpeciesNeighborhoodCount?
    let nearby: Series<NearbySpeciesTree>
    /// The month the page is being read in, 1…12. Injected rather than read from `Date()` so the
    /// seasonal callout is testable and previewable.
    let month: Int

    init(guide: SpeciesGuide, month: Int) {
        self.species = guide.species
        self.cityTreeCount = guide.cityTreeCount
        self.nearYou = guide.nearYou
        self.nearby = guide.nearby
        self.month = month
    }

    // MARK: Hero

    /// `Monterey Cypress` — the common name, which `SpeciesQueries` falls back to the scientific
    /// name for when the city recorded none (11 of the 569 seeded species).
    var commonName: String { species.commonName }

    /// `Hesperocyparis macrocarpa` — set in serif italic, per §1.3's `latin.name` row.
    var scientificName: String { species.scientificName }

    // MARK: §2 · Taxonomy chips

    /// The chips 07 §2 draws, minus every one whose fact is absent.
    ///
    /// SCREENS.md draws three — `Cupressaceae` · `Evergreen conifer` · `Coastal` — and only the
    /// first two have anything behind them. `conifer` is a growth form and `Coastal` is a habitat;
    /// the schema stores neither, and no curated field carries them (BUILD-PLAN §4). Both are left
    /// out rather than guessed at from the family name. See ERRATA (E43).
    var taxonomyChips: [SpeciesTaxonomyChip] {
        [
            SpeciesTaxonomyChip.family(species.family),
            SpeciesTaxonomyChip.habit(species.leafRetention)
        ].compactMap { $0 }
    }

    /// Whether this species has any phenology surface at all.
    ///
    /// Exposed so a test can assert the absence directly rather than by counting chips: an
    /// unsourced habit means no habit chip *and* no autumn colour anywhere on the page, and the two
    /// have to move together (D5, ERRATA E9).
    var showsPhenology: Bool { species.leafRetention != nil }

    // MARK: §3 · How to recognize it

    /// The authored ID tips, as bullets. Empty for the 529 uncurated species.
    var idTipRows: [SpeciesIDTipRow] {
        species.idTips.enumerated().map { SpeciesIDTipRow(index: $0.offset, tip: $0.element) }
    }

    /// The card draws only when there is something authored to put in it. An empty card headed
    /// `How to recognize it` is a promise the record cannot keep.
    var showsRecognizeCard: Bool { !idTipRows.isEmpty }

    // MARK: §4 · The seasonal callout

    /// What to look for this month, or nothing.
    ///
    /// The first care note whose window both contains this month and is not the whole year. See
    /// `SpeciesSeasonalNote` for why a year-round note is not eligible.
    var seasonalNote: SpeciesSeasonalNote? {
        for note in species.careNotes {
            guard note.monthRange.months.count < 12, note.monthRange.contains(month) else { continue }
            return SpeciesSeasonalNote(month: month, text: note.text)
        }
        return nil
    }

    // MARK: §5 · Count cards

    /// `1,204` — grouped, in the reader's own locale.
    var cityTreeCountText: String? {
        cityTreeCount.map(SpeciesCopy.groupedNumber)
    }

    /// `61`, and the neighbourhood it counts inside.
    var nearYouCountText: String? {
        nearYou.map { SpeciesCopy.groupedNumber($0.count) }
    }

    /// The two cards are a pair in the mock, and either can be absent, so the row draws when at
    /// least one of them has a number.
    var showsCountCards: Bool { cityTreeCountText != nil || nearYouCountText != nil }

    // MARK: §6 · Nearby individuals

    var nearbyRows: [NearbySpeciesTree] { nearby.items }

    var showsNearby: Bool { !nearby.items.isEmpty }
}

// MARK: - Copy

/// Screen 07's strings, verbatim from SCREENS.md including its typographic characters — `·`
/// (U+00B7 middle dot).
enum SpeciesCopy {

    /// The hero eyebrow, uppercased by the type style rather than by the string.
    static let heroEyebrow = "Field guide"

    static let recognizeLabel = "How to recognize it"
    static let nearbyLabel = "Nearby individuals"

    /// 07 §5's two stat-card labels. `nearYouLabel` is verbatim; the other one is not, and the
    /// departure is `docs/rulings-pending/species-count-names-the-inventory.md`.
    ///
    /// ── It used to read `In San Francisco`, over a number that was never San Francisco's ──────
    /// The card's number is `SpeciesQueries.cityTreeCount`, a `COUNT(*)` over **the whole attached
    /// inventory**, and under R43 exactly one inventory is attached at a time: either the built-in
    /// bundle or one downloaded city file. The built-in bundle is fused across two id spaces
    /// (`sf`, 145,837 trees; `us-ca-sj`, 52,788), so the count has spanned two cities since San
    /// Jose was merged. Crape Myrtle is the clearest instance: 97 in San Francisco, 3,649 in San
    /// Jose, and the card read `In San Francisco · 3,746`.
    ///
    /// **So the reported defect — "it says San Francisco to a reader standing in San Jose" — is
    /// the smaller half.** The number was wrong for a San Francisco reader too. That also rules
    /// out the obvious fix: naming the *tree's* city would put one city's name over a two-city
    /// number, and this screen has no tree to ask anyway (`SpeciesModel` is entered by species id
    /// from a grove tile, the search list or the map legend — never with a row).
    ///
    /// The label therefore names the population that was actually counted. `inventory` is R43's
    /// own word for the attached unit (`Built-in inventory`, "one inventory is attached at a
    /// time"), and R28 §3's rule applies unchanged: a constant that is true of every municipal
    /// inventory the merged table will ever hold is not the defect a constant naming one city is.
    static let cityCountLabel = "In this inventory"
    static let nearYouLabel = "Near you"

    static let locationPromptTitle = "See it near you"
    static let locationPromptSubtitle = "Turn on location to find this species on the blocks around you."

    /// 07 §4's lead-in, e.g. `In July:`. The month is the reader's own month name, from the
    /// calendar, so the callout says what month it is actually being read in.
    static func seasonalLeadIn(month: Int, calendar: Calendar) -> String {
        let names = calendar.standaloneMonthSymbols
        guard (1...names.count).contains(month) else { return "" }
        return "In \(names[month - 1]):"
    }

    /// The sub-line of a nearby row: `214 photos · thriving`.
    ///
    /// Assembled from the parts that exist and nothing else. A tree nobody has photographed and
    /// nobody has checked in on has no sub-line at all — which is every seeded tree on a fresh
    /// install, and is the honest state of a city inventory the community has not touched yet.
    /// The photo count is `nil` unless the whole series was read (ERRATA E38).
    static func nearbySubtitle(photoCount: Int?, vitality: Vitality?) -> String? {
        var parts: [String] = []
        if let photoCount, photoCount > 0 {
            parts.append(photoCount == 1 ? "1 photo" : "\(groupedNumber(photoCount)) photos")
        }
        if let vitality {
            // The mock writes the class label in lower case mid-sentence — `· thriving`, `· good`.
            parts.append(vitality.label.lowercased())
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// **NOT SPECIFIED.** SCREENS.md 07 draws no failed-read state. These two say what happened and
    /// nothing about the species, because nothing about the species was read. Recorded in ERRATA
    /// (E43).
    static let loadFailed = "This field guide entry could not be opened."
    static let loadRetry = "Try again"

    /// `220 m` — mono, as §1.3's `mono.12` row and every other distance in the app.
    static func distance(_ metres: Double) -> String {
        "\(Int(metres.rounded())) m"
    }

    /// `1,204`. Grouping is the formatter's, so a reader in a locale that groups differently sees
    /// their own convention rather than the mock's.
    static func groupedNumber(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }
}

/// Display copy for the `LeafRetention` vocabulary. Sentence case, per ARCHITECTURE §5.7.
///
/// SCREENS.md 07 §2 draws `Evergreen conifer`; the noun is a growth form nothing stores, so the
/// chip carries the habit alone. There is no case for "unknown": absence is an `Optional` and never
/// a label (ERRATA E9).
enum LeafRetentionLabel {
    static func text(for retention: LeafRetention) -> String {
        switch retention {
        case .evergreen: return "Evergreen"
        case .deciduous: return "Deciduous"
        case .semiDeciduous: return "Semi-deciduous"
        }
    }
}

// MARK: - Screen metrics

/// The geometry SCREENS.md gives screen 07 that `CypressSpacing` does not already name.
///
/// Same arrangement as `ReportMetrics` and `CheckInMetrics`: screen-specific numbers are named once
/// here so the view body carries no loose values, while every colour, font and radius stays a
/// `DesignSystem` token (ARCHITECTURE §6).
enum SpeciesMetrics {
    /// 07 §1: the hero's text block sits at `left:18px; bottom:14px` — 2pt further in and 2pt
    /// higher than C2's shared 16/12, which is why it is stated here and not in the component.
    static let heroTextLeading: CGFloat = 18
    static let heroTextBottom: CGFloat = 14
    /// The gap between the eyebrow, the name and the latin line, all three drawn as one block.
    static let heroTextSpacing: CGFloat = 1

    /// 07 §2: taxonomy chips at `padding:14px 18px 0`, `gap:8px`.
    static let chipsTop: CGFloat = 14
    static let chipsGap: CGFloat = CypressSpacing.gapRows

    /// 07 §3: the recognize card, `margin:12px 16px 0`, `padding:14px 16px`, `VStack(spacing:10)`.
    static let cardTop: CGFloat = 12
    static let cardPaddingV: CGFloat = 14
    static let cardPaddingH: CGFloat = 16
    static let cardSpacing: CGFloat = 10
    /// The bullets' own `gap:10px` between glyph and sentence.
    static let bulletGap: CGFloat = 10
    /// The glyph is 10×10 and the sentence is 13.5px; nudging the glyph down sits it on the first
    /// line's baseline rather than its cap height.
    static let bulletGlyphTop: CGFloat = 4

    /// 07 §4: the seasonal callout, `margin:10px 16px 0`.
    static let calloutTop: CGFloat = 10

    /// 07 §5: the count cards, `padding:10px 16px 0`, `HStack(spacing:8)`.
    static let countsTop: CGFloat = 10

    /// 07 §6: `padding:10px 16px 36px`, `VStack(spacing:8)`.
    static let nearbyTop: CGFloat = 10
    static let nearbyBottom: CGFloat = CypressSpacing.bottomFootnote
    /// Each row: `padding:11px 13px`, `gap:12px`.
    static let rowPaddingV: CGFloat = 11
    static let rowPaddingH: CGFloat = 13
    static let rowGap: CGFloat = 12
    /// The gap between a row's title and its sub-line.
    static let rowTextSpacing: CGFloat = 1
}
