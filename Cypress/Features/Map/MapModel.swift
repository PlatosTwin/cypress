//
//  MapModel.swift
//  Cypress — Features/Map
//
//  Screen 01's one `@Observable` (ARCHITECTURE §3): viewport, fetched content, filter, selection.
//  It talks to `CypressAPI` and to nothing else — no GRDB, no MapKit (ARCHITECTURE §4).
//
//  ── The thing that must never regress ─────────────────────────────────────────────────────
//  The seed is 195,309 trees. Every read is bounded by the visible viewport and by an explicit pin
//  budget; there is no code path here that asks for "all trees". Camera changes are debounced and
//  filtered, because a pan emits a continuous stream of them and each one is a database read.
//

import Foundation
import Observation

@MainActor
@Observable
final class MapModel {

    // MARK: - Filters
    //
    // The filter *value* is `MapFilter`, in its own file, where the design decision (RULINGS R23)
    // and the seed measurement behind the year control (ERRATA E175) are argued. `Filter` remains as
    // an alias so the name screen 01 and its tests already use keeps working.

    typealias Filter = MapFilter

    // MARK: - Inputs

    private let api: any CypressAPI
    private let calendar: Calendar
    private let now: () -> Date
    /// How long the `Needs care` toast stays on the glass. Injected for the same reason `now` is:
    /// a test that had to wait out the shipped interval to watch the toast let go of the screen
    /// would put three seconds of wall clock into the suite for one assertion.
    private let needsCareToastDuration: Duration

    init(
        api: any CypressAPI,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init,
        needsCareToastDuration: Duration = MapModel.defaultNeedsCareToastDuration
    ) {
        self.api = api
        self.calendar = calendar
        self.now = now
        self.needsCareToastDuration = needsCareToastDuration
    }

    // MARK: - State

    /// What the user typed into C20.
    ///
    /// **NOT SPECIFIED** — SCREENS.md 01:664 states the intent, "search opens species/street/
    /// neighborhood search", and 01:667 then says "NOT SPECIFIED: search results". The intent is
    /// spec; the surface is not, so what is designed here is designed under ARCHITECTURE §8 rule 8
    /// and reasoned out in `MapSearch`. What it does *not* do is open a results screen: the map is
    /// the results, narrowed in place, because that is the surface the spec already draws and the one
    /// the owner asked for — "typing in a tree name brought up all and only those trees".
    var searchText: String = "" {
        // `isApplyingChoice` is set only by `chooseSuggestion`, which writes the chosen species'
        // name into the field and has already decided what the map should narrow to. Without the
        // guard that write would look exactly like a keystroke: the debounce would start, the
        // catalog would be re-read for the name we just resolved, and the answer could be wider
        // than the one row the reader tapped.
        didSet { if searchText != oldValue, !isApplyingChoice { searchDidChange() } }
    }

    /// The species the current query resolved to, and what the map is able to say about it.
    ///
    /// The `didSet` is task #190's: a search is a narrowing, and a narrowed map is never owed the
    /// empty-inventory sentence (RULINGS R41). See `recomputeInventoryEmptiness`.
    private(set) var search: MapSearch = .off {
        didSet {
            recomputeInventoryEmptiness()
            // A typed word is a sixth narrowing, so a toast that outlived one would be a sentence
            // about a map that is no longer the map it described (task #247). Gated on an actual
            // change because `fetch()` rewrites this on every settled read (`search.reporting`).
            if search != oldValue { hideNeedsCareToast() }
        }
    }

    /// What drops under C20 for the text currently in it (task #109, ruling R25).
    ///
    /// **NOT SPECIFIED** by SCREENS.md 01, which lists "search results" among the surfaces it does
    /// not draw. `MapSuggestions` is where the surface is reasoned out, and E38 is why it carries a
    /// remainder rather than just an array.
    private(set) var suggestions: MapSuggestions = .off

    /// The species picked off the dropdown, if the field's text is still that species' name.
    ///
    /// Kept so the pinning is visible to a test and to a reader — "the map is narrowed to this one
    /// species because somebody chose it" is a different fact from "the map is narrowed to whatever
    /// this string matched", and only one of them survives another keystroke.
    private(set) var chosenSpecies: Species?

    /// True only for the single assignment `chooseSuggestion` makes to `searchText`.
    private var isApplyingChoice = false

    /// The narrowing itself, as the viewport carries it. `nil` until a query resolves.
    ///
    /// **Two sources, intersected** (#116). The search bar resolves a typed word to a set of species
    /// — a genus match can be several — and a tap on a legend entry picks exactly one off the glass.
    /// Both are "narrow the map to a species", both write the same viewport field, and a reader can
    /// have both on at once. The intersection is the only combination that keeps each control's
    /// promise: typing "plane" and then tapping the London Plane legend chip must leave London
    /// Planes, not silently widen back to every plane or silently drop the typed word.
    ///
    /// An empty result is `[]` rather than nil, and that distinction is load-bearing all the way
    /// down: `[]` means "narrowed to nothing", which `TreeQueries.narrowing` answers with
    /// `.matchesNothing` and an empty map, while nil means "not narrowed at all".
    private var speciesIDs: Set<UUID>? {
        let searched: Set<UUID>? = {
            switch search {
            case .off: return nil
            case .noMatch: return []
            case let .narrowed(narrowed): return narrowed.speciesIDs
            }
        }()
        guard let picked = filter.speciesID else { return searched }
        guard let searched else { return [picked] }
        return searched.intersection([picked])
    }

    /// The trees the membership chip has narrowed to, or nil when no chip is on.
    ///
    /// Read once per press of the chip rather than once per pan — `membershipDidChange` fills it and
    /// the map refetches through it. `[]` is a real answer here (a reader with no favorites) and it
    /// narrows the map to nothing, which screen 01 renders as an empty map — the empty map is the
    /// whole answer, on the owner's instruction (task #165).
    private(set) var membershipIDs: Set<UUID>?

    private var membershipTask: Task<Void, Never>?

    private var searchTask: Task<Void, Never>?

    /// Typing is a keystroke stream exactly as a pan is a camera stream, and it is debounced for the
    /// same reason — every settled query is a catalog read *and* a refetch of the map. Longer than
    /// the camera's 200 ms because a word takes longer to finish than a flick.
    static let searchDebounce: Duration = .milliseconds(300)

    var filter: Filter = .all {
        didSet {
            if filter != oldValue {
                // Before `filterDidChange`, which refetches: the arming has to be in place by the
                // time an answer can come back, and `filterDidChange` returns early on a
                // membership press.
                needsCareChipDidChange(from: oldValue)
                filterDidChange(from: oldValue)
            }
            recomputeInventoryEmptiness()
        }
    }

    private(set) var viewport: MapViewport?
    private(set) var content: MapContent = .pins([]) {
        didSet {
            recomputeAdmittedPins()
            recomputeInventoryEmptiness()
        }
    }
    private(set) var isLoading = false
    /// A read that failed. Deliberately not drawn: SCREENS.md 01 lists no error state and
    /// ARCHITECTURE §5.8 says not to invent one. What it buys is that a failed read leaves the last
    /// good content on screen instead of blanking the map, and the reason is recorded rather than
    /// swallowed.
    private(set) var loadFailure: APIError? {
        didSet { recomputeInventoryEmptiness() }
    }

    /// Whether a read has ever completed for a viewport. See `MapInventoryNotice.isOwed`'s
    /// `hasSettled` — `content` opens at `.pins([])`, which is the same value an answered-and-empty
    /// viewport produces, so "empty" cannot be read off it until something has answered.
    private(set) var hasSettled = false {
        didSet { recomputeInventoryEmptiness() }
    }

    /// **Whether the inventory answered this screenful with nothing, unnarrowed** (task #190).
    ///
    /// Stored rather than computed for `pins`' reason (E130): screen 01's chrome is rebuilt on every
    /// frame of a pan, and this is read from it. The three things that can change the answer all
    /// write it — a completed read, a filter, a search.
    private(set) var inventoryIsEmptyHere = false

    /// Whether anything at all is narrowing the map — the filter row, the drawer, the legend, or
    /// the search bar.
    ///
    /// `MapFilter.isActive` covers the first three; the search is its own state and is deliberately
    /// counted here, because a typed species that matches nothing in this viewport empties the map
    /// exactly as a chip does, and RULINGS R41's question is about *any* narrowing.
    var isNarrowed: Bool { filter.isActive || search != .off }

    private func recomputeInventoryEmptiness() {
        let next = MapInventoryNotice.isOwed(
            hasSettled: hasSettled,
            isNarrowed: isNarrowed,
            readFailed: loadFailure != nil,
            markerCount: content.markerCount
        )
        guard next != inventoryIsEmptyHere else { return }
        inventoryIsEmptyHere = next
    }

    // MARK: - The `Needs care` toast (task #247, owner's instruction 2026-08-06)
    //
    // `MapNeedsCareToast` decides whether this is *the state*; everything here decides whether this
    // is *the moment*, and the two are deliberately separate. The state is true for as long as the
    // chip is on over an empty map — every pan, every refetch, every re-read of the same ground —
    // and a sentence posted every time it were true would be the permanent pollution the owner's
    // instruction rules out in its own words ("doesn't pollute the map permanently").

    /// Whether the toast is on the glass right now. Read by `MapHomeView`, written only by the two
    /// methods below.
    private(set) var needsCareToastIsShowing = false

    /// **One activation of the chip, one answer.** Raised when `Needs care` is switched on and
    /// lowered by the first read that *finishes* after that — whether it came back with trees,
    /// with nothing, or with an error, and whether or not it produced a toast. `noteReadFinished`
    /// is where that is spelled out, including why a cancelled read is not a finished one.
    ///
    /// This is the re-arm rule, and it is the conservative one on purpose. The alternative — post
    /// whenever the state holds — fires on every pan and every zoom across an empty filtered map,
    /// which is a toast that never stops arriving and is exactly what the owner excluded. What is
    /// left is a toast that is the *answer to the press*: the reader asked "what needs care around
    /// here", and the map answers once. Panning afterwards is a new question about the ground, not
    /// a second press of the chip, and the empty map is already its whole answer (task #165).
    private var needsCareToastArmed = false

    private var needsCareToastTask: Task<Void, Never>?

    /// How long the toast stays up before it takes itself off the screen.
    ///
    /// Three seconds: long enough to read four words at AX5 without hurrying, short enough that it
    /// is gone before a reader has finished the pan they started. The owner asked for "quick" and
    /// for something that "dismisses quick"; no number was specified, and this one is the smallest
    /// commitment that satisfies both halves of the sentence. It is a `static let` rather than a
    /// literal so the value has a name in the one place a future owner ruling would change it.
    ///
    /// `nonisolated` for `markerCellPoints`' reason: an immutable constant that took this type's
    /// `@MainActor` only by living on it, and it is read from `init`'s default argument list,
    /// which is not on the actor. Without it the Swift 5 mode warns and the Swift 6 mode refuses.
    nonisolated static let defaultNeedsCareToastDuration: Duration = .seconds(3)

    /// The chip was pressed, or something else about the narrowing moved.
    private func needsCareChipDidChange(from old: MapFilter) {
        // **Any** change to the filter invalidates a toast already up: it was a sentence about one
        // query's answer, and this is a different query. Turning the chip off is only the most
        // obvious case of it.
        hideNeedsCareToast()
        let wasOn = old.condition == .needsCare
        let isOn = filter.condition == .needsCare
        guard wasOn != isOn else { return }
        needsCareToastArmed = isOn
    }

    /// Called from **every terminal path of `fetch()`** — the answer, the `APIError`, and the
    /// unexpected error — always *after* the facts that read has published (`content`, `search`,
    /// `loadFailure`, `hasSettled`), because the gate reads three of them and a toast decided from
    /// a half-published read would be answering the previous question.
    ///
    /// **It was `noteSettledContent()` and only the success path called it, which was a defect**
    /// (found in review of task #247, reproduced against a fake API that throws once). A read that
    /// threw left the arm live *indefinitely*: the press had had its answer and nothing said so, so
    /// the next unrelated successful read — a plain pan, minutes and screens later, chip untouched
    /// — consumed the stale arm and posted the toast. The sentence then answered the pan rather
    /// than the press, which is the "fires on every pan" pollution the owner's instruction excludes
    /// by name, reached through a transient network failure instead of directly.
    ///
    /// **A press whose read failed got its answer too, and the answer was the error state.** So it
    /// spends the arm exactly as a successful read does; `MapNeedsCareToast.isOwed`'s `!readFailed`
    /// guard is what keeps it from also *showing* anything, which is "a failed read is not an empty
    /// answer" (E126) applied to the arm as well as to the gate. The name says `read finished`
    /// rather than `content settled` because a failed read has no settled content and never sets
    /// `hasSettled` — a method whose name asserted otherwise is exactly the confident comment this
    /// project keeps finding bugs behind.
    ///
    /// **A cancelled read is deliberately not a terminal path and must not disarm.** Every
    /// cancellation here means a *newer* fetch has already superseded this one (`scheduleFetch`
    /// cancels the outstanding task), so the press's answer is the read that actually lands. The
    /// three `guard !Task.isCancelled` returns in `fetch()` are therefore the only exits that leave
    /// the arm alone, and that is the rule: **an answer spends the press; being overtaken does
    /// not.**
    private func noteReadFinished() {
        guard needsCareToastArmed else { return }
        // Consumed however the read ended. Trees, no trees, or an error — each of them answers the
        // press completely, and none of them leaves anything owed to the next pan.
        needsCareToastArmed = false
        guard MapNeedsCareToast.isOwed(
            filter: filter,
            isSearching: search != .off,
            readFailed: loadFailure != nil,
            markerCount: content.markerCount
        ) else { return }
        showNeedsCareToast()
    }

    private func showNeedsCareToast() {
        needsCareToastTask?.cancel()
        needsCareToastIsShowing = true
        needsCareToastTask = Task { [weak self, needsCareToastDuration] in
            try? await Task.sleep(for: needsCareToastDuration)
            guard !Task.isCancelled else { return }
            self?.needsCareToastIsShowing = false
        }
    }

    private func hideNeedsCareToast() {
        needsCareToastTask?.cancel()
        needsCareToastTask = nil
        guard needsCareToastIsShowing else { return }
        needsCareToastIsShowing = false
    }

    private(set) var selection: MapCardSubject?
    private(set) var selectedPinID: UUID?

    /// Species resolved for the legend's names, keyed by id. Populated lazily and only for the ≤4
    /// species holding a color slot — the catalog is 731 rows and the map does not need it.
    ///
    /// **It used to serve the `In bloom` chip as well, and had a `didSet` that re-filtered the pins
    /// as each lookup landed** (task #240). That is gone with the post-fetch filter it fed: the
    /// chip is a `WHERE` clause now, so a pin's admission no longer waits on a species read that
    /// may never arrive. `resolveSpeciesForVisiblePins` — which resolved *every* species on screen
    /// rather than the four with slots — went with it.
    private var species: [UUID: Species] = [:]
    private var speciesMisses: Set<UUID> = []

    private var fetchTask: Task<Void, Never>?
    private var selectionTask: Task<Void, Never>?
    private var paletteNameTask: Task<Void, Never>?

    /// A pan emits camera changes every frame. 200 ms is long enough that a flick costs one read
    /// and short enough that letting go feels like the map answered immediately.
    static let cameraDebounce: Duration = .milliseconds(200)

    /// The floor under the clustering-threshold read, which does not wait out the full debounce
    /// because crossing it changes the *shape* of the answer rather than its contents.
    static let thresholdDebounce: Duration = .milliseconds(16)

    // MARK: The pin budget, and why it is a grid
    //
    // ── What was here before, and what it did ──────────────────────────────────────────────────
    // `TreeQueries.pins` answers from `idx_trees_lat_lon`, so a bare `LIMIT` truncates in **latitude
    // order**: the rows it keeps are the southernmost ones in the box, never a spread across it. A
    // cap that bites therefore does not thin the map — it clips the top of the screen off and piles
    // every pin into a strip along the bottom edge. The answer to that was to read the viewport as
    // five horizontal bands with 260 of the budget each, so the cap ran out evenly.
    //
    // It made the truncation even and it left the real defect untouched: **nothing bounded the drawn
    // pins by anything but the viewport's area.** 5 × 260 = 1,300 annotation views, each a
    // SwiftUI-hosted `Button`, and the ceiling was reached. Measured on the iPhone 16 Pro simulator
    // by a `CADisplayLink` counting main-thread frames (`MapFrameProbe`), over Dolores Park and the
    // Mission — before this round:
    //
    //     idle at zoom 18, 10 markers          60.0 fps   worst frame    16.7 ms
    //     the pinch out from 18 to 16          38.0 fps   worst frame   325.0 ms
    //     arriving at zoom 16, 1,300 markers   14.3 fps   worst frame   753.5 ms
    //     the window after that                 0.5 fps   worst frame 2,060.8 ms
    //     one pan at zoom 16                   18.7 fps   worst frame 1,286.0 ms
    //
    // Two pinches out is sixteen times the ground and was sixteen times the annotations. Further out
    // still it goes *fast again*, because zoom ≤ 15 clusters and clustering caps the badges — which
    // is why the report was "SUPER slow when you zoom out **a bit**", and why the SQL was never the
    // cause: the queries get more expensive in the direction the map gets faster.
    //
    // ── The rule now ──────────────────────────────────────────────────────────────────────────────
    // A budget, and a grid to spend it on. `TreeQueries.pins` grids the viewport into cells that are
    // `markerCellPoints` square on screen and takes one tree per occupied cell — in SQL, on the
    // covering index, so it reads a few hundred rows instead of thousands. The drawn count is then
    // bounded by screen area ÷ cell area, which does not change with zoom: pulling the camera back
    // stops adding annotations and starts making each pin stand for more ground.
    //
    // The grid is a *ceiling* rather than a rule. The same query counts what is in the box while it
    // groups it, so a viewport whose trees already fit inside `pinLimit` is answered un-thinned and
    // nothing is lost where nothing was wrong.
    //
    // And the bands are gone. A query that returns one row per cell has nothing left to truncate, so
    // there is no strip to spread evenly, and one read does what five did — which also ends the ten
    // redundant round-trips the other four were making through `LocalAPI`'s community and
    // status-override reads.

    /// How much screen one drawn pin is allowed to stand for, once the budget is exceeded.
    ///
    /// **44 points, because that is this app's own hit target.** `.cypressHitArea()` gives every
    /// interactive control ≥ 44 pt (ARCHITECTURE §6, SCREENS.md §5 gap 12), and a pin is a control —
    /// so two pins closer together than 44 pt cannot both be reliably tapped. The second one is not a
    /// pin the user can use; it is paint. One per 44 pt is therefore the *most* pins that are all
    /// still individually reachable, which makes it the honest cell for a budget that has to bite
    /// somewhere. `MapPin` itself already says this: "two pins closer than ~44pt have overlapping
    /// targets, which is precisely what clustering is for".
    ///
    /// What it comes to: on an iPhone 16 Pro the map is 402 × 874 pt and the fetched box is that with
    /// 8 % added on every side, so the grid touches **264 to 288 cells** — and it is the same 264 to
    /// 288 at zoom 16, 17, 18 and 21, because the screen does not change size when the camera pulls
    /// back. That is the whole property. Counted against the shipped seed over the densest zoom-16
    /// screenful in it (37.7788, −122.4247, in the Mission), cells that actually hold a tree:
    ///
    ///     zoom · trees in the fetched box · cells · occupied · drawn
    ///       21  ·                       6 ·   288 ·        6 ·     6
    ///       20  ·                      15 ·   288 ·       15 ·    15   ← under budget, un-thinned
    ///       19  ·                     109 ·   264 ·       54 ·   109   ← under budget, un-thinned
    ///       18  ·                     543 ·   288 ·      136 ·   136
    ///       17  ·                   2,072 ·   288 ·      220 ·   220
    ///       16  ·                   8,150 ·   288 ·      277 ·   277
    ///
    /// The pins do not fuse at that spacing either: C19 draws an 18 pt pin, so a full grid covers
    /// 15 % of the screen in pins, against the unbroken mat of green 1,300 of them drew.
    ///
    /// `nonisolated`: an immutable `Double` constant, not model state. It took `MapModel`'s
    /// `@MainActor` only by living on the type, and it is read to *build* a `MapViewport` — including
    /// from the off-actor query-plan suites — rather than to describe any one instance.
    nonisolated static let markerCellPoints: Double = 44

    /// How many individual pins one screenful may draw before the grid takes over.
    ///
    /// **It is the cell rule stated the other way round, not a second knob.** The fetched box on this
    /// phone is 472,000 pt²; divided by a 44 pt cell that is ~250 cells, and 400 trees spread over it
    /// is a mean spacing of 34 pt — already inside the 44 pt tap target, so past 400 the extra pins
    /// are paint rather than controls. Which means 400 sits *above* the grid's own ceiling on every
    /// current iPhone (264–288 cells here, at most ~350 on a 16 Pro Max) and far below the 1,300 that took the
    /// map to 14 fps. So the un-thinned query runs exactly where the un-thinned answer was already
    /// inside the grid's budget, and the grid runs everywhere else, and neither one is a cliff.
    ///
    /// It is the same `pinLimit` the API always took, doing the job its own comment claimed: "hard
    /// cap on individual pins returned in one response". What changed is that exceeding it now costs
    /// the densest pins rather than the northern half of the screen.
    ///
    /// `nonisolated` for the same reason as `markerCellPoints`: an immutable `Int` constant that
    /// belongs to the budget, not to an instance's state.
    nonisolated static let pinLimit = 400

    // MARK: - Derived content

    var clusters: [TreeCluster] {
        if case let .clusters(clusters) = content { return clusters }
        return []
    }

    /// The pins the current filter admits.
    ///
    /// **Stored rather than computed.** It was a computed property that re-ran the filter on every
    /// read, and it is read from `MapKitBasemap`'s body — which MapKit invalidates on every frame of
    /// a pan and on every GPS fix, so a filtered map re-filtered its whole pin set sixty times a
    /// second to arrive at the same array (ERRATA E130). Exactly three things can change the answer,
    /// and all three recompute it: `content`, `filter`, and the species the bloom chip reads.
    private(set) var pins: [TreePin] = [] {
        didSet { recomputeSpeciesPalette() }
    }

    /// Which four species hold the four color slots, for the pins that are drawn right now.
    ///
    /// **Derived from `pins`, which is why it is set here and nowhere else.** A filter chip changes
    /// which pins are admitted, and a palette ranked over the pins the reader cannot see would light
    /// up species that are not on the glass. `recomputeAdmittedPins` is the one place `pins` moves,
    /// so this follows it rather than the fetch.
    private(set) var speciesPalette: MapSpeciesPalette = .empty

    private func recomputeSpeciesPalette() {
        let next = MapSpeciesPalette.assign(pins: pins, previous: speciesPalette)
        // A pan across a block usually re-derives the palette it already had — same species, same
        // sticky slots. Writing it anyway would republish observable state sixty times a second and
        // put every annotation through the layer's kind comparison for nothing, which is the exact
        // shape of what E130 spent its time removing.
        guard next != speciesPalette else { return }
        speciesPalette = next
        resolveSpeciesNamesForPalette()
    }

    /// Reads the common names of the ≤4 species holding slots, so the legend can name them.
    ///
    /// Four reads at worst, against a 569-row catalog, and only when the palette actually changed.
    /// It reuses the cache the bloom chip already fills (`species`), so a species resolved for one is
    /// free for the other.
    private func resolveSpeciesNamesForPalette() {
        let wanted = speciesPalette.unnamedSpeciesIDs
        guard !wanted.isEmpty else { return }
        let alreadyKnown = wanted.compactMap { id in species[id].map { (id, Self.displayName(of: $0)) } }
        if !alreadyKnown.isEmpty {
            speciesPalette = speciesPalette.naming(Dictionary(uniqueKeysWithValues: alreadyKnown))
        }
        let missing = speciesPalette.unnamedSpeciesIDs.filter { !speciesMisses.contains($0) }
        guard !missing.isEmpty else { return }
        paletteNameTask?.cancel()
        paletteNameTask = Task { [weak self, api] in
            for id in missing {
                if Task.isCancelled { return }
                guard let resolved = try? await api.species(id: id) else {
                    self?.speciesMisses.insert(id)
                    continue
                }
                guard let self, !Task.isCancelled else { return }
                self.species[id] = resolved
                self.speciesPalette = self.speciesPalette.naming([id: Self.displayName(of: resolved)])
            }
        }
    }

    /// "The species common name is the fallback display everywhere" (D15) — and the scientific name
    /// is the fallback for *that*, because 150,000 seeded rows carry a Latin binomial and a stub
    /// common name is allowed to be empty.
    private static func displayName(of species: Species) -> String {
        species.commonName.isEmpty ? species.scientificName : species.commonName
    }

    private func recomputeAdmittedPins() {
        guard case let .pins(fetched) = content else {
            if !pins.isEmpty { pins = [] }
            return
        }
        // The search is *not* applied here, and that is the point. A chip narrows the pins already
        // fetched; a search narrows the query itself, so by the time content arrives it holds only
        // matches — which is what lets it hold *all* of them rather than whichever survived the
        // budget. Filtering here as well would be a second, redundant pass and would put the
        // "all and only" guarantee back downstream of the grid where it cannot be kept.
        //
        // **No dimension of the filter is applied here any more, and that is task #240's whole
        // fix.** `membership`, `decade`, `speciesID` and `siteKind` never were (#116): all four ride
        // on the viewport, so the answer that came back already holds only matches, and re-applying
        // them would put the "all and only" guarantee back downstream of the grid where a pin
        // thinned out of a 44 pt cell cannot be recovered.
        //
        // `condition` was the exception, and it was a defect rather than a design. A `switch` stood
        // here filtering the fetched pins by `needs care` and by `bloom_months` — which is correct
        // at zoom ≥ 16 and is *nothing at all* at zoom ≤ 15, because at zoom ≤ 15 this method takes
        // the branch above: `content` is `.clusters`, `pins` is emptied, and the badges the map
        // actually draws are read straight off `content` having never met a filter. Pressing
        // `In bloom` or `Needs care` over a clustered map changed the chip's fill and left every
        // badge and every count exactly where it was, including in the state where no tree in the
        // seed satisfies the chip at all.
        //
        // There is no version of this method that could have fixed it. A `TreeCluster` carries an
        // id, a centroid and a `COUNT(*)`; the trees it stands for are not in the answer and cannot
        // be recovered from it. So the predicate went into the `WHERE` clause, where all four map
        // statements read it (`TreeQueries.Narrowing`), and what is left here is the assignment.
        pins = fetched.items
    }

    // MARK: - What the filter row reports, which is nothing (RULINGS R41, task #180)

    // `filterResult` stood here and produced the result line — `31 trees`, or
    // `1458 trees—showing 151` when the 44 pt grid had thinned the answer. R41 forbids text that
    // appears because a filter did something and names a count among the surfaces it forbids, and
    // this property existed for no other purpose: it was nil unless `filter.isActive`. So it is
    // gone rather than left computing a string nobody renders.
    //
    // The thinning it reported is still real and still happens (`pinLimit`,
    // `MapViewport.markerCellPoints`). What is gone is the sentence about it, which E38 permits:
    // E38 forbids presenting a page as a total, and no number is presented at all now.

    // MARK: - Camera

    /// Called on every camera change, at `.continuous` frequency — so the first thing it does is
    /// decide whether this one is worth anything at all.
    ///
    /// A drag emits a new region every frame, each a hair different from the last. Taking every one
    /// of them would rewrite observable state sixty times a second and re-run the whole map's body
    /// with it. The rule instead: if the zoom has not changed and the new screen is still inside the
    /// box already fetched, there is nothing to draw that is not drawn, and this is a no-op.
    func cameraDidChange(bounds: BoundingBox, zoom: Int) {
        if let viewport, viewport.zoom == zoom, viewport.bounds.contains(bounds) { return }
        // A little more than the screen, so a short pan does not blank the edge it is heading for.
        // Kept small: every point of it is budget spent on pins the user cannot see.
        let next = makeViewport(bounds: bounds.expanded(by: 0.08), zoom: zoom)
        guard next != viewport else { return }
        // The clustering threshold is the one boundary where the *shape* of the answer changes, so
        // it does not wait out the full debounce that a slow pan could keep re-arming.
        let crossedClusteringThreshold = next.shouldCluster != viewport?.shouldCluster
        viewport = next
        scheduleFetch(immediate: crossedClusteringThreshold)
    }

    /// The one place a `MapViewport` is built, so the camera and the search bar cannot disagree
    /// about what the map is being asked for.
    private func makeViewport(bounds: BoundingBox, zoom: Int) -> MapViewport {
        let members = membershipIDs
        return MapViewport(
            bounds: bounds,
            zoom: zoom,
            pinLimit: Self.pinLimit,
            // Only the pin half of the answer has a level of detail to choose. A clustered viewport
            // is already one badge per 64 pt cell, which is the same rule with a count on it.
            //
            // **And a membership viewport takes no cell at all** (#116). The grid exists to bound an
            // answer that grows with the viewport's area; a membership set does not — it is bounded
            // by what one person tapped, which is tens. Handing it a 44 pt cell would thin a set
            // that fits on the screen twice over, and thinning it would put `matchesInView` on the
            // answer and make screen 01 say "showing 12 of 31" about a set it could have drawn
            // whole. `MapViewport.shouldCluster` suspends A1's badges on the same argument and says
            // so at length.
            markerCellPoints: members != nil || zoom <= MapViewport.highestClusteringZoom
                ? nil
                : Self.markerCellPoints,
            speciesIDs: speciesIDs,
            plantedYears: filter.decade?.years,
            treeIDs: members,
            siteKind: filter.siteKind,
            // Task #240. The month is read here, once per viewport, rather than stored: a map left
            // open across midnight on the 31st should answer the next month's question the next time
            // it is asked, and a `MapViewport` that carried a resolved species set instead would
            // have frozen the answer at the moment the chip was pressed.
            bloomMonth: condition?.bloomMonth,
            needsCare: condition?.needsCare ?? false
        )
    }

    /// What `filter.condition` asks the query for, with this model's clock supplying the month.
    ///
    /// One expression, read by the only place that builds a viewport, so the two chips cannot reach
    /// the pin query and miss the cluster query — which is the whole of task #240.
    private var condition: (bloomMonth: Int?, needsCare: Bool)? {
        filter.condition?.narrowing(month: calendar.component(.month, from: now()))
    }

    private func scheduleFetch(immediate: Bool) {
        fetchTask?.cancel()
        fetchTask = Task { [weak self] in
            // `immediate` used to mean no sleep at all, which made a pinch held across the zoom-15/16
            // boundary the one gesture in the app that could issue an unbounded number of reads: the
            // shape flips on every crossing and each crossing fired at once, and the read on the
            // clustered side is the whole-city aggregate. A floor of one frame coalesces an
            // oscillating pinch into a single read and is not a wait anybody can feel — it is a
            // twelfth of the pan debounce (ERRATA E130).
            try? await Task.sleep(for: immediate ? Self.thresholdDebounce : Self.cameraDebounce)
            if Task.isCancelled { return }
            await self?.fetch()
        }
    }

    /// The one read. Bounded by the viewport, never by anything else.
    ///
    /// Every `await` is followed by a cancellation check, because a pan supersedes its own reads
    /// constantly: `scheduleFetch` cancels the outstanding task on each camera change that matters,
    /// and a task that ignored that would publish a viewport the camera has already left and then
    /// spend a species lookup per pin resolving it.
    func fetch() async {
        guard let viewport, !Task.isCancelled else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let content = try await api.mapContent(in: viewport)
            guard !Task.isCancelled else { return }
            self.content = content
            #if DEBUG
            MapFrameProbe.shared.noteFetch()
            #endif
            // What the reader is told about their search is a fact about the answer that just
            // arrived, not about the query — "1,458 here, 151 drawn" is only knowable now. A search
            // whose species did not change still re-reads this on every pan, because panning is
            // exactly what changes how much of it fits.
            search = search.reporting(content)
            loadFailure = nil
            // **After `content`, never before.** This is the flag that lets an empty answer be told
            // apart from the empty value the model opens on (task #190), so it must not be raised
            // while `content` still holds the opening `.pins([])` — that ordering would post the
            // notice for one publish cycle on every launch, over any street in the city.
            hasSettled = true
            // **Last, deliberately.** The toast's gate reads `content`, `search` and `loadFailure`,
            // all of which are published above; asking it any earlier would decide this read's
            // sentence from the previous read's facts (task #247).
            noteReadFinished()
        } catch let error as APIError {
            guard !Task.isCancelled else { return }
            loadFailure = error
            // **After `loadFailure`, never before** — the same ordering rule as the success path,
            // and here it is what stops a failed read showing the toast off the *previous* read's
            // content. See `noteReadFinished`, and `MapNeedsCareToastTests.aFailedReadSpendsThePress`.
            noteReadFinished()
        } catch {
            guard !Task.isCancelled else { return }
            loadFailure = .serverError
            noteReadFinished()
        }
    }

    // MARK: - Search

    /// Resolves what was typed to a set of species, then refetches the map through it.
    ///
    /// The catalog read and the map read are deliberately two steps rather than one: 577 species
    /// answer a substring in 0.1 ms and 195,309 trees do not, so the narrow thing is resolved first and
    /// the wide query is asked once, already narrowed.
    private func searchDidChange() {
        searchTask?.cancel()

        // A keystroke is the reader taking the query back off the list. Whatever they chose a moment
        // ago is no longer what the field says, so the map must stop claiming it is — otherwise
        // deleting a letter from `Monterey Cypress` would leave the map pinned to Monterey Cypress
        // while the field says `Monterey Cypres`. See `chooseSuggestion`, which sets this.
        chosenSpecies = nil

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Clearing the field is not a search, and it must not wait out the debounce: the map is
        // narrowed *now* and the user has asked for it to stop being. The dropdown goes with it, for
        // the same reason and on the same frame.
        guard !query.isEmpty else {
            searchTask = nil
            suggestions = .off
            applySearch(.off)
            return
        }

        searchTask = Task { [weak self, api] in
            try? await Task.sleep(for: Self.searchDebounce)
            if Task.isCancelled { return }
            let matches = (try? await api.searchSpecies(query: query, limit: MapSearch.speciesLimit)) ?? []
            guard let self, !Task.isCancelled else { return }
            // **One read, two surfaces.** The dropdown and the narrowing are two readings of the
            // same array, so the list can never offer a species the map is not narrowed to — which
            // a second `searchSpecies` call at a second limit would eventually allow.
            self.suggestions = MapSuggestions(matches: matches)
            self.applySearch(MapSearch(query: query, matches: matches))
        }
    }

    /// A row in the dropdown was tapped: the map narrows to **that species**, not to everything its
    /// name happens to match.
    ///
    /// That difference is the whole of what the ticket asked for, and it is not cosmetic. Typing
    /// `Cypress` narrows to the six species whose names contain the word (E165). Picking
    /// `Monterey Cypress` off the list is a statement about one of those six, and the map must stop
    /// showing the other five — so the species set is pinned here rather than re-derived from the
    /// text, which would resolve `Monterey Cypress` back through the catalog and could pick up
    /// anything else that happens to contain the phrase.
    ///
    /// **The keyboard goes.** This is the deliberate opposite of R16's ✕, which clears and *keeps*
    /// focus because clearing starts the next query. Choosing ends one: the reader has said which
    /// tree they meant, and the thing they asked for is the map that the keyboard is covering.
    func chooseSuggestion(_ species: Species) {
        searchTask?.cancel()
        searchTask = nil
        isApplyingChoice = true
        // The field shows what was chosen rather than what was typed — the ticket's own words, and
        // the reason a chooser is not just a shortcut for typing the rest of the name.
        searchText = MapSuggestionCopy.name(species)
        isApplyingChoice = false
        chosenSpecies = species
        // Nothing left to suggest: the field now holds the answer the list was offering.
        suggestions = .off
        applySearch(MapSearch(query: searchText, matches: [species]))
    }

    private func applySearch(_ next: MapSearch) {
        guard next != search else { return }
        search = next
        clearSelection()
        // The narrowing lives on the viewport, so changing it is a new viewport — which is exactly
        // what the fetch path already knows how to answer, and why `MapViewport` had to carry the
        // species rather than take them as a second argument.
        guard let current = viewport else { return }
        viewport = makeViewport(bounds: current.bounds, zoom: current.zoom)
        scheduleFetch(immediate: true)
    }

    // MARK: - Filters

    /// A press of any chip. Three of the four dimensions change the *query*, so they go back to the
    /// database; the fourth filters the pins already in hand.
    private func filterDidChange(from old: MapFilter) {
        clearSelection()

        // The membership set is a read of its own, and it has to land before the map is refetched —
        // otherwise the first fetch after the press goes out with a nil `treeIDs` and draws the
        // whole city for a frame, which is the wrong answer shown first.
        if filter.membership != old.membership {
            membershipDidChange()
            return
        }

        recomputeAdmittedPins()
        guard filter.narrowsTheQuery || old.narrowsTheQuery else { return }
        refetchThroughNarrowing()
    }

    /// Reads the id set behind `Yours` or `Favorites`, then refetches the map through it.
    ///
    /// The same two-step shape as `searchDidChange`, and for the same reason: the narrow thing is
    /// resolved first — here from `main`, a table of tens of rows — and the wide query over 145,837
    /// trees is asked once, already narrowed.
    private func membershipDidChange() {
        membershipTask?.cancel()
        guard let kind = filter.membership else {
            membershipIDs = nil
            refetchThroughNarrowing()
            return
        }
        membershipTask = Task { [weak self, api] in
            let ids = (try? await api.mapMembership(kind)) ?? []
            guard let self, !Task.isCancelled, self.filter.membership == kind else { return }
            // `[]` is published deliberately rather than left nil. A reader with no favorites has
            // asked a question and the honest answer is an empty map that says why (ERRATA E126),
            // not the whole city.
            self.membershipIDs = ids
            self.refetchThroughNarrowing()
        }
    }

    /// Rebuilds the viewport around whatever the narrowing now is and refetches.
    ///
    /// Identical in shape to what `applySearch` does, and for the reason stated there: the narrowing
    /// lives on the viewport, so changing it is a *new viewport*, which is exactly what the fetch
    /// path already knows how to answer and what lets the debounce see that anything changed.
    private func refetchThroughNarrowing() {
        guard let current = viewport else { return }
        viewport = makeViewport(bounds: current.bounds, zoom: current.zoom)
        scheduleFetch(immediate: true)
    }

    // MARK: - What resolved the bloom filter, and does not any more (task #240)
    //
    // `resolveSpeciesForVisiblePins` stood here. It read the species of every pin on screen, one
    // `api.species(id:)` per distinct species, so that `recomputeAdmittedPins` could ask each one
    // whether it bloomed this month — a few dozen reads per settled camera, and a filter whose
    // answer arrived asynchronously and in pieces after the pins were already drawn.
    //
    // The chip is a `WHERE` clause now (`MapViewport.bloomMonth`), so the seed answers it in one
    // statement over 731 species rather than in dozens over the pins, before the map is drawn rather
    // than after, and — the point of the ticket — for the cluster query as well as the pin query.
    // `speciesTask` went with it; the palette's own name lookup keeps its own task.

    // MARK: - Selection

    /// Tapping a pin opens the bottom tree card. The profile read is what fills it in; until it
    /// lands the card shows what the pin already knows, so the tap feels answered.
    func select(_ pin: TreePin) {
        // Tapping the open pin again puts the card away. SCREENS.md documents no dismiss control on
        // the card, and this is the only dismissal the drawn screen can support.
        guard selectedPinID != pin.id else { return clearSelection() }
        selectedPinID = pin.id
        selection = MapCardSubject(pin: pin)
        selectionTask?.cancel()
        selectionTask = Task { [weak self, api] in
            let profile = try? await api.treeProfile(id: pin.id)
            guard let self, !Task.isCancelled, self.selectedPinID == pin.id else { return }
            if let profile {
                self.selection = MapCardSubject(pin: pin, profile: profile)
            }
        }
    }

    func clearSelection() {
        selectionTask?.cancel()
        selectedPinID = nil
        selection = nil
    }
}

// MARK: - Pin kind

/// The pin vocabulary of SCREENS.md 01, as a function of the four facts a `TreePin` carries.
///
/// > Green pins are city trees, dashed pins the community layer, amber marks an open care note,
/// > and gray dash-marked pins are removed trees—memorials.
enum MapPinKind {

    /// Community source wins over every status. A community-added tree "never renders as part of
    /// the official city inventory until verified" (DECISIONS §3.16), and the dashed ring is the
    /// only thing in C19 that says so — so a declining community tree gives up its amber rather
    /// than its dashes. There is no drawn pin that is both.
    static func kind(for pin: TreePin) -> MapPin.Kind {
        if pin.source == .community, pin.verificationState == .unverified { return .community }
        if needsCare(status: pin.status) { return .needsCare }
        switch pin.status {
        case .alive:
            return .cityTree
        case .deadReported, .removed:
            // The gray pin means "no living tree at this site".
            return .removed
        case .vacantSite:
            // Its own pin since RULINGS R7. It used to borrow `.removed`, and that made the map the
            // last surface still claiming a tree had been here — E107 and E113 removed exactly that
            // claim from the profile and the almanac, and E107 deferred this one because a new pin
            // was a design decision it had no standing to make.
            return .vacantSite
        case .declining:
            return .needsCare
        }
    }

    /// The same vocabulary, plus the four viewport species slots (task #80).
    ///
    /// **A slot is only ever added to a pin that would already have been `.cityTree`.** Every other
    /// pin's fill is carrying a meaning that outranks "which species is this" — amber says the tree
    /// needs something, dashes say the record is unverified, gray and hollow say there is no living
    /// tree here — so this delegates to `kind(for:)` first and only then looks the species up. The
    /// argument is in `MapSpeciesPalette`'s header; the guarantee is that no color of the map's
    /// existing vocabulary can be replaced by a species color.
    static func kind(for pin: TreePin, palette: MapSpeciesPalette) -> MapPin.Kind {
        let base = kind(for: pin)
        guard base == .cityTree, let slot = palette.slot(for: pin.speciesID) else { return base }
        return .cityTreeSpecies(slot)
    }

    /// Whether this status draws the amber pin.
    ///
    /// **It reads `TreeStatus.needsCare` rather than spelling `== .declining` here** (task #240).
    /// The chip and the pin are two renderings of one question, and they were two literals in two
    /// modules: the pin's was here, the chip's was a `switch` in `MapModel.recomputeAdmittedPins`,
    /// and the query layer had neither. `Core` now holds the one definition, `TreeQueries` builds
    /// its `IN` list from it, and this is the third reader rather than a second author.
    static func needsCare(status: TreeStatus) -> Bool { status.needsCare }

    /// What a pin announces to VoiceOver.
    ///
    /// C19's own labels, except on a vacant site, which speaks `SiteCopy`'s words.
    ///
    /// E107 wrote this override because the gray pin was shared with a memorial and its label —
    /// `Removed tree, memorial` — claimed a tree had been here; a site never had one. It noted that
    /// only the *spoken* half of the distinction could be made then, since a new pin was a design
    /// decision against a closed catalog. R7 made that decision, so the pin is now `.vacantSite`
    /// and the drawn half is fixed too.
    ///
    /// **The override survives anyway**, deliberately. `MapPin.Kind.vacantSite` carries a sane default
    /// of its own, but the words a basin says belong to the feature that owns basins — one place to
    /// change them, and `SiteCopy` is where the screen's own copy already lives. A component in
    /// `DesignSystem` must not reach into `Features` for a string, so the default stays where it is
    /// and this keeps overriding it.
    ///
    /// **A confirmed-dead tree is the second override, for the same reason** (ERRATA E170). It draws
    /// the gray pin, which is right — there is no living tree at this site, and `MapPin.Kind` is a
    /// closed catalog whose sixth entry took a ruling. But the gray pin *says* `Removed tree,
    /// memorial`, and a dead street tree has not been removed: it is standing there, over a pavement,
    /// and it keeps its profile and its REPORT button precisely because reporting it is the most
    /// useful thing a passer-by can do. A reader sweeping a block was told the one thing that would
    /// stop them walking over to it. Same split E107 made and same half — the words are fixable here
    /// without touching the catalog; whether a standing dead tree deserves its own drawn pin is a
    /// design decision, and it is left open rather than guessed at.
    static func accessibilityLabel(for pin: TreePin) -> String {
        switch kind(for: pin) {
        case .vacantSite:
            return SiteCopy.pinAccessibilityLabel
        // Only where the drawn pin is the memorial's, which is what makes the default a lie. A
        // community-added dead tree draws `.community` and says so, because "community source wins
        // over every status" (DECISIONS §3.16) is the rule in both channels, not only in the fill —
        // and `Community-added tree` is incomplete rather than untrue. Fixing the lie is this
        // errata's business; widening the rule is not.
        case .removed where pin.status == .deadReported:
            return MapPinCopy.deadReportedLabel
        case let other:
            return other.accessibilityLabel
        }
    }

    /// The same label, with the species named when the map has a color on this pin.
    ///
    /// **This is the third channel, and the only one that works with the screen off.** A slot is a
    /// hue plus a glyph, and both are things you have to see. A reader on VoiceOver sweeping a block
    /// gets `City tree, London Plane` from every plane on it, which answers "which of these are the
    /// same tree?" better than either drawn channel does — so the grouping is not a sighted-only
    /// feature that happens to have an accessible fallback.
    ///
    /// A pin with no slot says exactly what it said before. The name is deliberately not added to
    /// every pin: it is only knowable for the four species the legend has resolved, and a label that
    /// named some trees and not others would read as a claim about the ones it left out.
    static func accessibilityLabel(for pin: TreePin, palette: MapSpeciesPalette) -> String {
        let plain = accessibilityLabel(for: pin)
        guard kind(for: pin, palette: palette) != kind(for: pin),
              let slot = palette.slot(for: pin.speciesID),
              let name = palette.entries.first(where: { $0.slot == slot })?.name
        else { return plain }
        return "City tree, \(name)"
    }
}

/// The words the map says about a pin that the closed `MapPin.Kind` catalog has no case for.
///
/// **NOT SPECIFIED** — C19 names five pins and none of them is a standing dead tree. It lives in
/// `Features/Map` rather than in the component for the reason `SiteCopy.pinAccessibilityLabel` does:
/// a component in `DesignSystem` must not reach into `Features` for a string, so the catalog keeps
/// its own default and the feature overrides it.
enum MapPinCopy {
    /// Says the two things a listener needs and neither of the two it must not: that the tree is dead
    /// (so the gray dot is explained), that it is still standing (so nobody reads "gone"), and no
    /// word of "memorial" or "removed", which are the other status.
    static let deadReportedLabel = "Dead tree, still standing"
}

// MARK: - The bottom card's subject

/// What the bottom tree card draws. Starts as the pin (instant, from data already on screen) and is
/// replaced by the full profile when `GET /trees/{id}` returns.
struct MapCardSubject: Identifiable, Equatable {
    let pin: TreePin
    var profile: TreeProfile?

    var id: UUID { pin.id }

    /// Whether this pin has no tree behind it at all (ERRATA E107, closing E11).
    ///
    /// Read off the *pin*, not off the profile, so it is true from the instant the card appears —
    /// the card is drawn before the profile read lands, and a card that said "Unidentified" for
    /// half a second and then corrected itself would be the wrong answer shown first.
    var isVacantSite: Bool { pin.status == .vacantSite }

    /// The active name if the tree has one, else the species common name — "the species common name
    /// is the fallback display everywhere" (D15).
    ///
    /// A vacant site takes neither, and it must not fall through to `Unidentified`: that word means
    /// "a tree whose species nobody has resolved", and 12,518 pins used to carry it while having no
    /// tree to identify. It is named for what it is instead.
    var title: String {
        if isVacantSite { return SiteCopy.cardTitle }
        if let name = profile?.activeName, name.isDisplayable { return name.name }
        if let common = profile?.species?.commonName, !common.isEmpty { return common }
        return "Unidentified"
    }

    /// `nil` where there is no species, and also where the ingest never read a scientific name and
    /// `species.scientificName` holds DataSF's raw source string instead
    /// (`RULINGS R54`).
    ///
    /// The card carries no sentence in the missing clause's place, and that is the one surface where
    /// the ruling's second half deliberately does not apply. `MapTreeCard.meta` is a `·`-joined line
    /// that already drops any clause it has no fact for — no species, no fix, no visit — so a
    /// dropped clause here reads as every other absence on it, and the profile the card opens is one
    /// tap away with the whole sentence on it.
    var scientificName: String? {
        guard let species = profile?.species, !species.scientificNameIsUnread else { return nil }
        return species.scientificName.isEmpty ? nil : species.scientificName
    }

    /// C13's mapping, except on a site.
    ///
    /// `StatusBadge.kind` badges a tree with no check-in and a planted year as `PLANTED <year>`, and
    /// DataSF hands plant dates to rows that are now empty basins — so a vacant site could draw a
    /// badge asserting that something was planted in it. The badge is suppressed here rather than in
    /// the component, because C13's mapping is the *tree* vocabulary and is shared with screen 03.
    var badge: StatusBadge.Kind? {
        guard let profile, !isVacantSite else { return nil }
        return StatusBadge.kind(
            status: profile.tree.status,
            vitality: profile.latestObservation?.vitality,
            plantedYear: profile.tree.plantedYear
        )
    }

    var lastVisitedAt: Date? {
        profile?.visits.items.map(\.capturedAt).max()
    }

    /// This tree's own photograph, chosen by `PhotoHero` — the same rule the profile hero draws by
    /// (ERRATA E125) — over the same `photos`/`photoTallies` pair the profile already carries once
    /// `profile` has loaded (#176). No second read: the card and the profile it opens into would
    /// otherwise be free to disagree about which photograph is this tree's.
    ///
    /// `nil` before the profile read lands and for a vacant site, both of which draw `thumbnail`'s
    /// placeholder exactly as before.
    var heroPhoto: Photo? {
        guard let profile else { return nil }
        return PhotoHero.choose(from: profile.photos.items, tallies: profile.photoTallies)
    }

    /// The four canonical C22 thumbnails cover four species; the rest of the catalog has no
    /// authored artwork and no photograph yet. Genus decides where it can, and a stable hash of the
    /// name decides the rest — the same tree always gets the same placeholder, and none of it
    /// claims to be a picture of this tree.
    var thumbnail: CypressGradient.Thumbnail {
        guard let latin = scientificName ?? profile?.species?.commonName else { return .cypress }
        let lowercased = latin.lowercased()
        if lowercased.hasPrefix("ginkgo") { return .ginkgo }
        if lowercased.hasPrefix("platanus") { return .londonPlane }
        if lowercased.hasPrefix("pittosporum") { return .victorianBox }
        if lowercased.hasPrefix("cupressus") || lowercased.hasPrefix("hesperocyparis") {
            return .cypress
        }
        let choices: [CypressGradient.Thumbnail] = [.cypress, .ginkgo, .londonPlane, .victorianBox]
        let bucket = abs(lowercased.utf8.reduce(0) { ($0 &* 31 &+ Int($1)) % 9_973 })
        return choices[bucket % choices.count]
    }
}
