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
//  most of the map. A sentence on the map used to say so (`MapYearFilterCopy.setAside`); **RULINGS
//  R41 removed it and every other message beside a filter** (task #180), so the fact survives as the
//  reason this control is shaped the way it is, pinned by test, and not as words on the glass.
//
//  ── What a year narrowing means, since task #178 ──────────────────────────────────────────────
//  **Only a site with a tree on it.** 9,237 of the seed's 24,200 vacant planting sites carry a
//  `planted_year` — the date of a tree that is no longer there — and a year narrowing used to
//  return them, so `2010s` drew empty basins as trees planted in the 2010s. E107 had already
//  refused the same claim one layer up, keeping the `PLANTED <year>` badge off the site screen
//  because it "would assert a planting on an empty basin"; the filter was asserting it anyway.
//  `TreeQueries.Narrowing` now excludes vacant sites whenever a decade is set. Task #179 gives
//  those sites their own way to be found (`MapSiteKind`), which is what keeps this a correction
//  rather than a disappearance.
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

    /// `Yours` / `Favorites`, or neither. Single-select **within this dimension only**: a tree is
    /// either one you have contributed to or one you have hearted, and asking for both at once means
    /// the intersection, which is a set so small and so unmotivated that offering it would be a
    /// control nobody wants. Tapping the other one swaps.
    ///
    /// **The two halves are no longer drawn in the same place** (R23.1): `Yours` is a chip in the
    /// row and `Favorites` is behind the row's expandable control. That is a change to where the
    /// question is asked and to nothing else — the swap still happens, across the two surfaces, and
    /// `MapExtraFilter.favorites` is the one place that arm is written.
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

    /// Whether the map is narrowed to sites with a tree, to empty planting sites, or neither
    /// (task #179). Behind `More filters`, beside `Year` — see `MapExtraFilter.siteKind`.
    var siteKind: MapSiteKind?

    /// The un-narrowed map — the mock's `All`, as the absence of everything rather than a chip.
    static let all = MapFilter()

    /// Kept as a named value because `CypressTests/MapDetailTests` sets it, and because the amber
    /// pin is a real thing on the map whatever else the row grows.
    static let needsCare = MapFilter(condition: .needsCare)

    static let inBloom = MapFilter(condition: .inBloom)

    /// Whether anything is narrowing the map.
    var isActive: Bool {
        membership != nil || decade != nil || speciesID != nil || condition != nil
            || siteKind != nil
    }

    /// Whether the *fetch* is narrowed, as opposed to the drawn pins being filtered afterwards.
    ///
    /// The distinction is the one `MapModel.recomputeAdmittedPins` turns on and it is load-bearing:
    /// `membership`, `decade` and `speciesID` go into the query, so the answer that comes back holds
    /// only matches; `condition` is applied to the pins already fetched, because neither "needs
    /// care" nor "in bloom" is a column the seed's map queries select on.
    /// `siteKind` is in the query for the same reason the other three are: it is `trees.status`, a
    /// column, and answering it after the fetch would spend the pin budget on rows that cannot
    /// match — the E36/E38 shape `TreeQueries.Narrowing` exists to prevent.
    var narrowsTheQuery: Bool {
        membership != nil || decade != nil || speciesID != nil || siteKind != nil
    }

    /// The narrowings currently set **inside the row's expandable control** — the ones a reader
    /// cannot see while it is shut.
    ///
    /// This is the value the collapsed control renders itself from, and it exists as a property on
    /// the filter rather than as a count in the view because the hazard R23.1 creates is a fact
    /// about the *filter*, not about the chrome: a dimension can be on while nothing on screen
    /// draws it. One expression, read by the chip's label, its fill and its spoken value, so those
    /// three cannot disagree about whether anything is hidden.
    var activeExtras: [MapExtraFilter] { MapExtraFilter.allCases.filter { $0.isOn(self) } }

    // MARK: - Conditions

    /// SCREENS.md 01 §12's own two, unchanged in meaning.
    ///
    /// **The declaration order is the row's drawn order and is load-bearing** (R23.1). The owner
    /// listed the chips as "yours, in bloom, needs care, and year", so `inBloom` comes first here;
    /// `MapFilterChips` draws `allCases` and does not re-sort it, which keeps the owner's order in
    /// one place rather than in a literal beside the view. (#145 later moved `Year` off the row
    /// into the expandable control; the order of these two is untouched by that.)
    enum Condition: String, CaseIterable, Identifiable, Sendable {
        case inBloom
        case needsCare

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

// MARK: - The narrowings that are not in the row

/// **Everything the filter can ask that the row does not have a chip for** (RULINGS **R23.1**, and
/// task #145 for `year`).
///
/// ── Why this is a type and not an `if` in the view ───────────────────────────────────────────
/// The owner's instruction was "favorites (and any others we add later) should go to a separate
/// expandable filter button". The parenthesis is the requirement: this is an **extension point**,
/// not a drawer that happens to hold one thing. A `Favorites` chip written inline behind an
/// `if isExpanded` would satisfy the sentence and none of it — the second narrowing to arrive would
/// be a second inline chip, the collapsed control would need a hand-updated count, and the day
/// somebody forgot to update it is the day a filter is on with nothing on screen saying so.
///
/// The drawer draws `allCases`, the collapsed chip counts `allCases`, and `MapFilter.activeExtras`
/// is the one expression all three channels read. Adding a narrowing later is one case here — its
/// `isOn` and its `label(in:)` — plus one arm in `MapFilterChips.drawer` saying what control draws
/// it. `year` is the case that proved the drawer could not assume its contents are toggles: a
/// decade is a *value*, chosen from a menu, and a uniform `toggle(in:)` had no honest meaning for
/// it, so the per-case surface here is the two questions every hidden narrowing must answer
/// (am I on; what am I called) and the control itself is the drawer's business.
///
/// ── Why the arms live here rather than on `MapFilter` ────────────────────────────────────────
/// `isOn` and `label(in:)` are the definition of what a hidden narrowing *means* to the three
/// channels that must not disagree (the collapsed chip's count, its fill, its spoken value), and
/// keeping them beside the case is what makes the case the only thing a new one has to write.
/// `favorites` reads `MapFilter.membership`, which is single-select within itself (R23 §1) — so
/// turning `Favorites` on from inside the drawer turns `Yours` off in the row above it, which is
/// the same swap R23 specified, now crossing a surface.
enum MapExtraFilter: String, CaseIterable, Identifiable, Sendable {

    /// Trees hearted on screen 03 (D9, E89). In the row until R23.1, behind the control since.
    case favorites

    /// The planting decade (#116, E175). In the row until #145; the owner's directive cut the
    /// visible chips to `Yours · In bloom · Needs care` and sent `Year` here beside `Favorites`.
    case year

    /// Tree or empty planting site (task #179). **Born in the drawer** — R38 fixed the visible row
    /// at one horizontally scrolling line and this was never a candidate for it. It is the second
    /// value-carrying narrowing, which is the case R23.1 predicted when it called this an extension
    /// point rather than a drawer with one thing in it: it arrives as one case here and one arm in
    /// `MapFilterChips.drawer`, and no other view changes.
    case siteKind

    var id: String { rawValue }

    /// What this narrowing is called, **carrying its value when it has one**.
    ///
    /// The collapsed control's spoken value is built from these, and it is the only channel that
    /// reaches a listener while the drawer is shut (R23.1 §2) — so `year` must speak its decade
    /// here. `Year` alone would tell a listener the map is narrowed by year and leave them opening
    /// the drawer to find out to what, which is the E126 hazard half-fixed.
    func label(in filter: MapFilter) -> String {
        switch self {
        case .favorites: return MapFilterCopy.membershipLabel(.favorites)
        case .year: return MapYearFilterCopy.label(filter.decade)
        case .siteKind: return MapSiteKindFilterCopy.label(filter.siteKind)
        }
    }

    func isOn(_ filter: MapFilter) -> Bool {
        switch self {
        case .favorites: return filter.membership == .favorites
        case .year: return filter.decade != nil
        case .siteKind: return filter.siteKind != nil
        }
    }

    /// Turns `Favorites` on or off. A toggle, like every other chip in this feature: a conjunction
    /// with no way to remove one term is a conjunction you can only escape wholesale (R23 §1).
    ///
    /// Deliberately not a uniform requirement of the enum — `year` is set through its menu and
    /// cleared by choosing `Any year` (or by `Clear filters`), and a `toggle` that had to invent a
    /// decade to mean "on" would be a control answering a question nobody asked.
    static func toggleFavorites(in filter: inout MapFilter) {
        filter.membership = filter.membership == .favorites ? nil : .favorites
    }
}

// MARK: - Copy

/// What the filter row and its result line say.
///
/// The words live here rather than inside the views for the reason `MapRecentreCopy` and
/// `MapLocationCopy` do: they are the part that has to be asserted without rendering anything, and
/// the result line's two forms are the *only* thing keeping this feature inside D1 and E38.
enum MapFilterCopy {

    static let rowLabel = "Filter trees"

    static func membershipLabel(_ kind: MapMembership) -> String {
        switch kind {
        case .yours: return "Yours"
        // American spelling, on the owner's instruction (R23.1). They named this word.
        case .favorites: return "Favorites"
        }
    }

    /// What a chip announces to VoiceOver when it is on. The drawn state is a fill and a weight, and
    /// neither is available to a listener.
    static func chipValue(isOn: Bool) -> String { isOn ? "On" : "Off" }

    /// The control that puts the map back.
    ///
    /// **One of these, not two, and R23.1 makes that load-bearing rather than tidy.** A narrowing set
    /// inside the expandable control is invisible while the control is shut; if the way out of it
    /// were also inside it, a reader would have to know a filter existed in order to find the control
    /// that removes it. `filter = .all` clears every dimension, drawn or hidden, and this chip is on
    /// screen whenever *any* of them is set.
    static let clearLabel = "Clear filters"

    // MARK: The expandable control (R23.1)

    /// The control's own name, and the name of the group it opens.
    static let moreLabel = "More filters"

    /// **What the chip says while it is shut and something inside it is on.**
    ///
    /// The hazard R23.1 creates, stated as a string: a filter behind a closed control is a map
    /// narrowed by a cause nobody can see, which is ERRATA E126's defect ("a screen showing something
    /// other than what you asked for must say why") wearing a new hat. The count is the visible half
    /// of the answer — it rides in the label so it survives a reader who cannot see the selected
    /// fill, and it is a number rather than a list of names because the control exists precisely
    /// because names do not fit in this row.
    ///
    /// The names are not lost; they are in `moreValue`, which is where a listener gets them and where
    /// they cost no width at all.
    static func moreChipLabel(active: Int) -> String {
        active == 0 ? moreLabel : "\(moreLabel) (\(active))"
    }

    /// **What the control announces: whether it is open, and what is set inside it.**
    ///
    /// Two facts in one value, and both are needed. A disclosure that does not say whether it is open
    /// leaves a listener pressing it to find out — and a listener is exactly the reader for whom
    /// "the panel appeared below" is not an observation. And a *shut* control that named no contents
    /// would be the E126 hazard with the visual half fixed and the spoken half left open: the fill
    /// and the count reach a sighted reader, and this sentence is the only thing that reaches anyone
    /// else.
    ///
    /// Names rather than a number here, because the constraint that made the label count instead —
    /// the width of a chip row on a phone — does not apply to a spoken string.
    ///
    /// Takes the names rather than the cases because a name can carry a value — `Year: 2010s` —
    /// and the value is read off the filter, which this copy type deliberately does not hold. The
    /// caller derives the names from `MapFilter.activeExtras`, the one expression all three
    /// channels read, via `MapExtraFilter.label(in:)`.
    static func moreValue(isExpanded: Bool, activeNames: [String]) -> String {
        let state = isExpanded ? "Expanded" : "Collapsed"
        guard !activeNames.isEmpty else { return state }
        return "\(state), on: " + activeNames.joined(separator: ", ")
    }

    /// Why a reader would open it. It says what is *behind* the control rather than what pressing it
    /// does, because "expands" is already the value's job.
    static let moreHint = "Holds the narrowings that are not chips in the row."

    // MARK: The result line there is no longer any of (RULINGS R41, task #180)

    // `result(drawn:matched:)` stood here and produced `31 trees` / `1458 trees—showing 151`.
    // R41 forbids any text that appears because a filter did something and lists *a count* among
    // the forbidden surfaces, so the line is gone and this formatter with it. The argument it used
    // to carry — that a filter result is not the personal total D1 forbids — was sound and is not
    // being reversed; the count is not forbidden for being a score, it is forbidden for being a
    // message beside a filter. The distinction matters to anyone tempted to reinstate it: D1 is not
    // what is in the way now.

    // MARK: The empty state there deliberately is none of (task #165)

    // A filtered map with no matches used to draw an E126-shaped card here — a title naming the
    // filter, a reason, and its own `Clear filters` button — and before that, R31 stood a disabled
    // chip carrying a sentence where a pill should be. The owner struck both presentations in one
    // instruction: "We should NEVER display a message box in place of an empty filter … if
    // nothing matches, fine." So there is no empty-state copy in this type any more. The empty
    // map is the answer, and the way out is the `Clear filters` chip, which is in the row
    // whenever any dimension is set (R23.1 §3 — the way out never hides).
}

/// The words the site-kind control says (task #179).
///
/// **Every word here is one the app already uses.** DECISIONS constraint 15 forbids inventing
/// civic or botanical content, and none is invented: `Site` is E107's own screen title, and
/// `Vacant site` is already the word `SegmentedControl` uses for this status. The two option labels
/// are written as answers to "what is here" so the menu reads as a sentence with the chip —
/// `Site: Has a tree`, `Site: Empty planting site` — which is exactly `MapYearFilterCopy`'s
/// `Year: 2010s` shape, so the drawer's two value-carrying controls speak the same grammar.
///
/// There is deliberately no sentence in this type beyond a label. R41 forbids one, and a control
/// that had to explain itself in prose beside the map would be the thing #180 removed arriving
/// through a new door.
enum MapSiteKindFilterCopy {

    static let label = "Site"

    /// The chip's label, carrying its value when it has one.
    static func label(_ kind: MapSiteKind?) -> String {
        guard let kind else { return label }
        return "\(label): \(optionLabel(kind))"
    }

    /// The menu's "no narrowing" row, in `MapYearFilterCopy.anyLabel`'s register.
    static let anyLabel = "Tree or site"

    static func optionLabel(_ kind: MapSiteKind) -> String {
        switch kind {
        case .hasTree: return "Has a tree"
        case .emptySite: return "Empty planting site"
        }
    }
}

/// The words the year control says.
enum MapYearFilterCopy {

    static let label = "Year"

    /// The chip's label when a decade is chosen — `Year: 2010s`.
    static func label(_ decade: MapFilter.Decade?) -> String {
        guard let decade else { return label }
        return "\(label): \(decade.label)"
    }

    static let anyLabel = "Any year"

    // ── The caveat sentence, and why there is none (RULINGS R41, task #180) ──────────────────────
    //
    // `setAside` stood here — "About 4 in 5 trees have no recorded planting date—none of them can
    // appear under a year." — beside the constant it rounded (`undatedShareOfSeed`, 0.8078) and,
    // since R43 §5, a `setAside(undatedShare:)` that re-derived the fraction from whatever
    // inventory was attached. **All three are gone.** The owner named this sentence: "Right now the
    // year filter has a message about 4 of 5 trees. That's stupid."
    //
    // **R41 and R43 §5 collide, and R41 wins.** R43 §5 generalized this sentence from a bundle
    // constant into a per-inventory measurement; it did not decide *whether* the sentence should
    // exist, because that was not its question. R41 decides exactly that, it is later, and it is
    // the owner's direct instruction rather than delegated authority. A measurement whose only
    // consumer is a forbidden sentence is dead code, so `CypressStore.seedUndatedShare` and its
    // `measureUndatedShare` went with it rather than being left unread (#62/E126).
    //
    // **What was lost, honestly stated.** The sentence existed for a real reason and the reason has
    // not gone away: 160,440 of the seed's 198,625 rows carry no `planted_year`, so a year
    // narrowing sets aside four rows in five before it judges anything, and their absence can read
    // as "there are no trees here from the 2010s" when the truth is "the city did not record when
    // most of these were planted". R41 weighed that and ruled the clutter worse, permitting a
    // single-dismiss popup for anything genuinely essential and judging that nothing in the product
    // qualifies. The seed fact itself is still pinned by
    // `MapFilterTests.plantingDateCoverageIsWhatTheDecadeBucketsWereBuiltFor`, because the
    // *control's design* still rests on it even though no sentence quotes it.
}

