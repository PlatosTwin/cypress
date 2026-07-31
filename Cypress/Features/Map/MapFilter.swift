//
//  MapFilter.swift
//  Cypress — Features/Map
//
//  Screen 01's filter interface (#116). The design decision is RULINGS **R23**; the seed measurement
//  the year control is built on is ERRATA **E175**. This file is the value it all reduces to, plus
//  the words the screen says about it.
//
//  ── What replaced what ────────────────────────────────────────────────────────────────────────
//  SCREENS.md 01 §12 draws three chips — `All`, `In bloom`, `Needs care` — "single-select with `All`
//  default". The owner asked for four narrowings in priority order: **Yours, Favourites, species,
//  year**. Those are not three more entries in a single-select list, because they are not
//  alternatives: "my trees" and "planted in the 2010s" are questions a reader can sensibly ask at
//  once, and a single-select row would silently drop the first when they asked the second.
//
//  So the shape changes from an enum to a **conjunction of independent dimensions**, and the mock's
//  own two conditions keep their places inside it. `All` stops being a chip and becomes what the row
//  looks like with nothing on — a chip that means "no filter" is a control whose selected state is
//  indistinguishable from the resting state of the row, and it cost a slot that `Yours` needed.
//
//  ── Where the species dimension went ─────────────────────────────────────────────────────────
//  **It is the legend (#96), made tappable, and there is no species chip at all.** The owner's own
//  constraint was that the filter and the legend "must agree with each other and must not fight for
//  the same screen space". The strongest available guarantee that two controls agree is that they
//  are one control: the legend already names the ≤4 species the map has coloured (`MapSpeciesPalette`),
//  already sits in the chrome, and already costs the space it costs. Tapping an entry narrows to that
//  species; tapping it again clears. A species that is not one of the four is reached the way it
//  always was — by typing it into C20, which writes the same narrowing (`MapSearch`).
//
//  That is also the only version that could not regress the bug the owner remembered: the legend
//  covered the map once, and adding a *second* species surface beside it would have been a second
//  block of chrome competing for the same strip of glass.
//
//  ── Why the year control is a decade and says so out loud ────────────────────────────────────
//  Counted against the shipped seed, not assumed (ERRATA E175): **198,625 trees, 38,185 with a
//  planting year — 19.22 %.** The two cities are nothing alike on this column: San Francisco records
//  a year for 26.03 % of its rows and San Jose for **0.42 %** (222 of 52,788), which is why adding a
//  city made the control's caveat *stronger* rather than weaker (E176). A year filter therefore
//  cannot be a plain predicate with a silent complement; four out of five trees are unjudgeable, and
//  a control that quietly dropped them would be answering "when was this planted?" with "never" for
//  most of the map. `MapYearFilterCopy.setAside` is the sentence that keeps it honest, and it is
//  rendered whenever the narrowing is on.
//
//  Decades rather than years because the seed spans 1955–2026: 72 options holding a mean of 530 dated
//  trees each, which is invisible in a viewport. Five buckets, sized off the real distribution —
//  pre-1990 7,742 · 1990s 8,746 · 2000s 10,134 · 2010s 8,493 · 2020s 3,070. San Jose's 222 dated rows
//  all landed in the last bucket and moved no boundary; the shape of this control is San Francisco's,
//  and the first city that records planting dates properly is the one that should revisit it.
//

import Foundation

/// Everything screen 01 has been narrowed to, as one value.
///
/// **A conjunction.** Every dimension that is set must be satisfied; a dimension that is nil asks
/// nothing. That makes the empty value — `.all` — the un-narrowed map, which is what the mock's
/// `All` chip selected, so the default behaviour is unchanged.
struct MapFilter: Equatable, Sendable {

    /// `Yours` / `Favourites`, or neither. Single-select **within this dimension only**: a tree is
    /// either one you have contributed to or one you have hearted, and asking for both at once means
    /// the intersection, which is a set so small and so unmotivated that offering it would be a
    /// control nobody wants. Tapping the other one swaps.
    var membership: MapMembership?

    /// The planting decade, or nil for every year. See the header, and ERRATA E175.
    var decade: Decade?

    /// The one species the map is narrowed to, set by tapping a legend entry.
    ///
    /// It is deliberately *not* the same storage as `MapModel.searchText`'s resolved species, though
    /// both end up in `MapViewport.speciesIDs`: the search resolves a typed word to a *set* (a genus
    /// match can be several species) and this is one species picked off the glass. `MapModel`
    /// combines them, and the header says why there is no third surface.
    var speciesID: UUID?

    /// The two chips SCREENS.md 01 §12 draws, kept.
    var condition: Condition?

    /// The un-narrowed map — the mock's `All`, as the absence of everything rather than a chip.
    static let all = MapFilter()

    /// Kept as a named value because `CypressTests/MapDetailTests` sets it, and because the amber
    /// pin is a real thing on the map whatever else the row grows.
    static let needsCare = MapFilter(condition: .needsCare)

    static let inBloom = MapFilter(condition: .inBloom)

    /// Whether anything is narrowing the map.
    var isActive: Bool {
        membership != nil || decade != nil || speciesID != nil || condition != nil
    }

    /// Whether the *fetch* is narrowed, as opposed to the drawn pins being filtered afterwards.
    ///
    /// The distinction is the one `MapModel.recomputeAdmittedPins` turns on and it is load-bearing:
    /// `membership`, `decade` and `speciesID` go into the query, so the answer that comes back holds
    /// only matches; `condition` is applied to the pins already fetched, because neither "needs
    /// care" nor "in bloom" is a column the seed's map queries select on.
    var narrowsTheQuery: Bool {
        membership != nil || decade != nil || speciesID != nil
    }

    // MARK: - Conditions

    /// SCREENS.md 01 §12's own two, unchanged in meaning.
    enum Condition: String, CaseIterable, Identifiable, Sendable {
        case needsCare
        case inBloom

        var id: String { rawValue }

        var label: String {
            switch self {
            case .needsCare: return "Needs care"
            case .inBloom: return "In bloom"
            }
        }

        /// `In bloom` is the only one that needs a species lookup to answer.
        var needsSeasonalData: Bool { self == .inBloom }
    }

    // MARK: - Decades

    /// The planting-year buckets, sized off what the seed actually carries (ERRATA E175).
    ///
    /// The open-ended first bucket is not laziness: the seed's earliest planting date is 1955 and
    /// the pre-1990 rows are 7,742 spread over 35 years, so splitting them further would produce
    /// buckets no viewport could ever show a pin from. The lower bound is well below 1955 so that a
    /// re-ingest carrying an older date cannot silently fall out of every bucket.
    enum Decade: String, CaseIterable, Identifiable, Sendable {
        case before1990
        case nineties
        case twoThousands
        case twentyTens
        case twentyTwenties

        var id: String { rawValue }

        var years: ClosedRange<Int> {
            switch self {
            case .before1990: return 1800...1989
            case .nineties: return 1990...1999
            case .twoThousands: return 2000...2009
            case .twentyTens: return 2010...2019
            case .twentyTwenties: return 2020...2099
            }
        }

        /// No spaces around em dashes (ARCHITECTURE §5.7). None here needs one.
        var label: String {
            switch self {
            case .before1990: return "Before 1990"
            case .nineties: return "1990s"
            case .twoThousands: return "2000s"
            case .twentyTens: return "2010s"
            case .twentyTwenties: return "2020s"
            }
        }
    }
}

// MARK: - Copy

/// What the filter row and its result line say.
///
/// The words live here rather than inside the views for the reason `MapRecentreCopy` and
/// `MapLocationCopy` do: they are the part that has to be asserted without rendering anything, and
/// three of these sentences are the *only* thing keeping this feature inside D1, E38 and E126.
enum MapFilterCopy {

    static let rowLabel = "Filter trees"

    static func membershipLabel(_ kind: MapMembership) -> String {
        switch kind {
        case .yours: return "Yours"
        case .favourites: return "Favourites"
        }
    }

    /// What a chip announces to VoiceOver when it is on. The drawn state is a fill and a weight, and
    /// neither is available to a listener.
    static func chipValue(isOn: Bool) -> String { isOn ? "On" : "Off" }

    /// The control that puts the map back.
    static let clearLabel = "Clear filters"

    // MARK: The result line

    /// **What the map has narrowed to, as a number — and the one place D1 and E38 both bite.**
    ///
    /// ── Why a number is allowed here at all ───────────────────────────────────────────────────
    /// D1 kills "counts of user actions", and the owner's brief restates it: "a neutral count as a
    /// *filter result* ('31 trees') is fine — a count that reads as a personal total is not". The
    /// difference is what the number is *of*. `31 trees` is a fact about the map — how many pins are
    /// under this viewport satisfying this filter — and it changes when the reader pans, which is
    /// exactly what makes it not a score. `You have visited 31 trees` would be a total: stable,
    /// about the person, and the sentence D1 exists to forbid.
    ///
    /// So the noun is always **trees**, never "yours", never "your visits", and the sentence never
    /// takes a second person. `Yours · 31 trees` reads as a filter and its result, which is what it
    /// is. There is deliberately no phrasing available here that could say otherwise.
    ///
    /// ── Why it is not simply `pins.count` (ERRATA E38) ────────────────────────────────────────
    /// "A page is not a total." The map draws at most `MapModel.pinLimit` individually tappable pins
    /// and thins with a 44 pt grid above that (`MapViewport.markerCellPoints`), so the drawn array
    /// can be a *spatial sample* of the matches. `PinAnswer.matchesInView` is non-nil exactly when
    /// that happened, and this renders the two cases in different words: a complete answer gets a
    /// plain count, a thinned one says how many matched and that not all are drawn. Reporting `151`
    /// when 1,458 matched is precisely the defect E38 names.
    ///
    /// - Parameters:
    ///   - drawn: how many pins are on the glass.
    ///   - matched: how many trees satisfied the filter in view, when that is more than `drawn`.
    static func result(drawn: Int, matched: Int?) -> String {
        guard let matched, matched > drawn else {
            return drawn == 1 ? "1 tree" : "\(drawn) trees"
        }
        return "\(matched) trees—showing \(drawn)"
    }

    /// The empty state (ERRATA E126): why the map is empty, and how to leave.
    ///
    /// E126's rule is that "a filtered map with no matches must say why it is empty, and how to get
    /// out of it", and the second half is the one that is easy to skip. The sentence names the
    /// filter that emptied it — so the reader knows which chip to reach for — and the notice this
    /// goes into carries a `Clear` button, so the way out is a control rather than a hint.
    ///
    /// `Yours` and `Favourites` get their own reasons, because on a fresh install the honest answer
    /// is not "no matches here" but "you have not made any yet", and telling somebody to pan around
    /// looking for trees they have never visited is the dead end D16 (b) warns about.
    static func emptyTitle(_ filter: MapFilter) -> String {
        if filter.membership == .yours { return "No trees of yours here" }
        if filter.membership == .favourites { return "No favourites here" }
        return "Nothing matches here"
    }

    static func emptyMessage(_ filter: MapFilter, hasAnyMembers: Bool) -> String {
        switch filter.membership {
        case .yours where !hasAnyMembers:
            return "You have not added a photo, a check-in or a measurement to any tree yet. "
                + "Visit one and it will appear here."
        // **Names the control the app actually draws, which is not a heart** (task #139, E184).
        //
        // This sentence used to read "Tap the heart on any tree's page". There is no heart anywhere
        // in this app and there never has been: SCREENS.md §2 C8 marks the four cells' icons NOT
        // SPECIFIED, §5 gap 3 repeats it, `mocks/cypress-mocks.html` contains no heart, and RULINGS
        // R2 corrects its own first draft on exactly this point — "C8 has no glyph … there was
        // nothing to fill". The row is four text cells reading `Favorite · Care · Share · Report`.
        //
        // So the reader was sent to look for an affordance that does not exist, on the one screen
        // this notice's whole job is to route them to. `QuadActionRow.Action.favorite.label` is the
        // string on the cell, quoted rather than paraphrased so the two cannot drift.
        // Written out rather than interpolated from `QuadActionRow.Action.favorite.label`, so this
        // file keeps its `Foundation`-only import; `MapFilterCopyNamesTheDrawnControlTests` asserts
        // the two strings agree, which is the drift protection the interpolation would have bought.
        case .favourites where !hasAnyMembers:
            return "You have not favorited a tree yet. Tap Favorite on any tree's page and it will "
                + "appear here."
        case .some:
            return "Nothing in this part of the map. Pan or zoom out to look further, or clear the "
                + "filter to see every tree again."
        case nil:
            return "No tree in view matches this filter. Pan or zoom out to look further, or clear "
                + "the filter to see every tree again."
        }
    }
}

/// The words the year control says, including the one that keeps it honest.
enum MapYearFilterCopy {

    static let label = "Year"

    /// The chip's label when a decade is chosen — `Year: 2010s`.
    static func label(_ decade: MapFilter.Decade?) -> String {
        guard let decade else { return label }
        return "\(label): \(decade.label)"
    }

    static let anyLabel = "Any year"

    /// **The sentence the owner asked for by name: what the control says about rows it cannot
    /// judge** (#116, ERRATA E175).
    ///
    /// Counted before it was designed, which was the instruction: **160,440 of the shipped seed's
    /// 198,625 rows carry no `planted_year` at all — 80.78 %.** So a year narrowing sets aside
    /// roughly four trees in five *before* it judges
    /// anything, and saying nothing would make their absence read as an answer: "there are no trees
    /// here from the 2010s", when the truth is "the city did not record when most of these were
    /// planted". Those are very different claims about the same empty patch of map, and the second
    /// one is the only one this app is entitled to make.
    ///
    /// ── Why the proportion and not a count in view ────────────────────────────────────────────
    /// A per-viewport number ("214 more trees here have no date") would be the better sentence and
    /// it is deliberately not built, because getting it honestly costs a **second full fetch of the
    /// same box with the year predicate removed** — the map's hot path, doubled, on every pan while
    /// the chip is on, to produce a caveat that does not change in kind as the reader moves. The
    /// proportion is a fact about the inventory the map is drawn from, it is true on every screenful,
    /// and it is pinned by `MapYearCoverageTests` against the shipped seed so it cannot quietly rot
    /// when the seed is rebuilt. R23 records this as the trade it is rather than an oversight.
    ///
    /// No spaces around em dashes (ARCHITECTURE §5.7).
    static let setAside =
        "About 4 in 5 trees have no recorded planting date—none of them can appear under a year."

    /// The share of the shipped seed carrying no planting year, as `MapYearCoverageTests` measures
    /// it. The copy above rounds this to "4 in 5"; the test asserts the rounding is still true, so a
    /// re-ingest that moved coverage would fail rather than leave the sentence lying.
    ///
    /// **It has already fired once, on the day it was written.** This constant was `0.7397` and the
    /// sentence read "3 in 4", both measured against a seed holding San Francisco alone. San Jose
    /// landed the same afternoon (E176) and the test went red on the merge: San Jose publishes a
    /// planting date for **222 of its 52,788 rows — 0.42 %** — against San Francisco's 26.03 %, so
    /// two cities in one seed is 80.78 % undated where one was 73.97 %.
    ///
    /// The lesson is worth more than the number. Under D16 the seed is a *merged* inventory, so the
    /// coverage of any field is not a property of this app at all — it is a weighted average over
    /// whichever cities happen to be in, and it moves every time one is added. A sentence quoting a
    /// coverage figure is therefore always provisional, and the only thing keeping it honest is that
    /// this constant is asserted against the seed rather than remembered from the day it was true.
    static let undatedShareOfSeed = 0.8078
}
