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

    /// The three chips of SCREENS.md 01, verbatim, single-select with `All` default.
    enum Filter: String, CaseIterable, Identifiable {
        case all
        case inBloom
        case needsCare

        var id: String { rawValue }

        var label: String {
            switch self {
            case .all: return "All"
            case .inBloom: return "In bloom"
            case .needsCare: return "Needs care"
            }
        }

        /// `In bloom` is the only chip that needs a species lookup to answer.
        var needsSeasonalData: Bool { self == .inBloom }
    }

    // MARK: - Inputs

    private let api: any CypressAPI
    private let calendar: Calendar
    private let now: () -> Date

    init(api: any CypressAPI, calendar: Calendar = .current, now: @escaping () -> Date = Date.init) {
        self.api = api
        self.calendar = calendar
        self.now = now
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
        didSet { if searchText != oldValue { searchDidChange() } }
    }

    /// The species the current query resolved to, and what the map is able to say about it.
    private(set) var search: MapSearch = .off

    /// The narrowing itself, as the viewport carries it. `nil` until a query resolves.
    private var speciesIDs: Set<UUID>? {
        switch search {
        case .off: return nil
        case .noMatch: return []
        case let .narrowed(narrowed): return narrowed.speciesIDs
        }
    }

    private var searchTask: Task<Void, Never>?

    /// Typing is a keystroke stream exactly as a pan is a camera stream, and it is debounced for the
    /// same reason — every settled query is a catalogue read *and* a refetch of the map. Longer than
    /// the camera's 200 ms because a word takes longer to finish than a flick.
    static let searchDebounce: Duration = .milliseconds(300)

    var filter: Filter = .all {
        didSet { if filter != oldValue { filterDidChange() } }
    }

    private(set) var viewport: MapViewport?
    private(set) var content: MapContent = .pins([]) {
        didSet { recomputeAdmittedPins() }
    }
    private(set) var isLoading = false
    /// A read that failed. Deliberately not drawn: SCREENS.md 01 lists no error state and
    /// ARCHITECTURE §5.8 says not to invent one. What it buys is that a failed read leaves the last
    /// good content on screen instead of blanking the map, and the reason is recorded rather than
    /// swallowed.
    private(set) var loadFailure: APIError?

    private(set) var selection: MapCardSubject?
    private(set) var selectedPinID: UUID?

    /// Species resolved for the bloom filter, keyed by id. Populated lazily and only for species
    /// that are actually on screen — the catalogue is 569 rows and the map does not need it.
    private var species: [UUID: Species] = [:] {
        didSet { if filter.needsSeasonalData { recomputeAdmittedPins() } }
    }
    private var speciesMisses: Set<UUID> = []

    private var fetchTask: Task<Void, Never>?
    private var selectionTask: Task<Void, Never>?
    private var speciesTask: Task<Void, Never>?

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
    static let markerCellPoints: Double = 44

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
    static let pinLimit = 400

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
    private(set) var pins: [TreePin] = []

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
        switch filter {
        case .all:
            pins = fetched.items
        case .needsCare:
            pins = fetched.items.filter { MapPinKind.needsCare(status: $0.status) }
        case .inBloom:
            // Answered from `species.seasonal.bloom_months` and from nothing else. The curated
            // species pipeline (BUILD-PLAN §8) has not landed, so every `seasonal` in the shipped
            // seed is `{}` and this chip currently matches no tree in any month. That is the honest
            // answer to the question the chip asks; inventing bloom months so it looks alive is
            // precisely what BUILD-PLAN §15 and DECISIONS §3.15 forbid.
            let month = calendar.component(.month, from: now())
            pins = fetched.items.filter { pin in
                guard let id = pin.speciesID, let species = species[id] else { return false }
                return species.seasonal.bloomMonths.contains(month)
            }
        }
    }

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
        MapViewport(
            bounds: bounds,
            zoom: zoom,
            pinLimit: Self.pinLimit,
            // Only the pin half of the answer has a level of detail to choose. A clustered viewport
            // is already one badge per 64 pt cell, which is the same rule with a count on it.
            markerCellPoints: zoom <= MapViewport.highestClusteringZoom ? nil : Self.markerCellPoints,
            speciesIDs: speciesIDs
        )
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
            // What the reader is told about their search is a fact about the answer that just
            // arrived, not about the query — "1,458 here, 151 drawn" is only knowable now. A search
            // whose species did not change still re-reads this on every pan, because panning is
            // exactly what changes how much of it fits.
            search = search.reporting(content)
            loadFailure = nil
            if filter.needsSeasonalData { resolveSpeciesForVisiblePins() }
        } catch let error as APIError {
            guard !Task.isCancelled else { return }
            loadFailure = error
        } catch {
            guard !Task.isCancelled else { return }
            loadFailure = .serverError
        }
    }

    // MARK: - Search

    /// Resolves what was typed to a set of species, then refetches the map through it.
    ///
    /// The catalogue read and the map read are deliberately two steps rather than one: 569 species
    /// answer a prefix in 0.1 ms and 195,309 trees do not, so the narrow thing is resolved first and
    /// the wide query is asked once, already narrowed.
    private func searchDidChange() {
        searchTask?.cancel()
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Clearing the field is not a search, and it must not wait out the debounce: the map is
        // narrowed *now* and the user has asked for it to stop being.
        guard !query.isEmpty else {
            searchTask = nil
            applySearch(.off)
            return
        }

        searchTask = Task { [weak self, api] in
            try? await Task.sleep(for: Self.searchDebounce)
            if Task.isCancelled { return }
            let matches = (try? await api.searchSpecies(query: query, limit: MapSearch.speciesLimit)) ?? []
            guard let self, !Task.isCancelled else { return }
            self.applySearch(MapSearch(query: query, matches: matches))
        }
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

    private func filterDidChange() {
        clearSelection()
        recomputeAdmittedPins()
        if filter.needsSeasonalData { resolveSpeciesForVisiblePins() }
    }

    /// Resolves the species of the pins currently on screen, once each, so `In bloom` can answer
    /// from real seasonal data. Bounded by the pin budget and by the distinct species in view — in
    /// SF that is a few dozen, not the whole 569-row catalogue.
    private func resolveSpeciesForVisiblePins() {
        guard case let .pins(pins) = content else { return }
        let wanted = Set(pins.compactMap(\.speciesID))
            .subtracting(species.keys)
            .subtracting(speciesMisses)
        guard !wanted.isEmpty else { return }

        speciesTask?.cancel()
        speciesTask = Task { [weak self, api] in
            for id in wanted {
                if Task.isCancelled { return }
                let resolved = try? await api.species(id: id)
                guard let self else { return }
                if let resolved {
                    self.species[id] = resolved
                } else {
                    self.speciesMisses.insert(id)
                }
            }
        }
    }

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

    static func needsCare(status: TreeStatus) -> Bool { status == .declining }

    /// What a pin announces to VoiceOver.
    ///
    /// C19's own labels, except on a vacant site, which speaks `SiteCopy`'s words.
    ///
    /// E107 wrote this override because the grey pin was shared with a memorial and its label —
    /// `Removed tree, memorial` — claimed a tree had been here; a site never had one. It noted that
    /// only the *spoken* half of the distinction could be made then, since a new pin was a design
    /// decision against a closed catalogue. R7 made that decision, so the pin is now `.vacantSite`
    /// and the drawn half is fixed too.
    ///
    /// **The override survives anyway**, deliberately. `MapPin.Kind.vacantSite` carries a sane default
    /// of its own, but the words a basin says belong to the feature that owns basins — one place to
    /// change them, and `SiteCopy` is where the screen's own copy already lives. A component in
    /// `DesignSystem` must not reach into `Features` for a string, so the default stays where it is
    /// and this keeps overriding it.
    static func accessibilityLabel(for pin: TreePin) -> String {
        guard kind(for: pin) == .vacantSite else {
            return kind(for: pin).accessibilityLabel
        }
        return SiteCopy.pinAccessibilityLabel
    }
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

    var scientificName: String? {
        guard let latin = profile?.species?.scientificName, !latin.isEmpty else { return nil }
        return latin
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

    /// The four canonical C22 thumbnails cover four species; the rest of the catalogue has no
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
