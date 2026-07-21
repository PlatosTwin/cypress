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

    /// Search text only. The results surface is **NOT SPECIFIED** (SCREENS.md §5 gap 7 and 01's own
    /// "NOT SPECIFIED: search results"), so nothing here interprets it — ARCHITECTURE §5.8.
    var searchText: String = ""

    var filter: Filter = .all {
        didSet { if filter != oldValue { filterDidChange() } }
    }

    private(set) var viewport: MapViewport?
    private(set) var content: MapContent = .pins([])
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
    private var species: [UUID: Species] = [:]
    private var speciesMisses: Set<UUID> = []

    private var fetchTask: Task<Void, Never>?
    private var selectionTask: Task<Void, Never>?
    private var speciesTask: Task<Void, Never>?

    /// A pan emits camera changes every frame. 200 ms is long enough that a flick costs one read
    /// and short enough that letting go feels like the map answered immediately.
    static let cameraDebounce: Duration = .milliseconds(200)

    // MARK: The pin budget, and why it is spent in bands
    //
    // `TreeQueries.pins` answers from `idx_trees_lat_lon`, so `LIMIT` truncates in **latitude
    // order**: the rows it keeps are the southernmost ones in the box, never a spread across it.
    // A cap that actually bites therefore does not thin the map — it clips the top of the screen
    // off and piles every pin into a strip along the bottom edge, which is exactly what it did
    // the first time this screen ran against real data.
    //
    // And it does bite. `TreeQueries` measures a zoom-16 viewport at 1,321 pins; a zoom-16
    // viewport over the densest part of the Sunset is roughly twice that. A1 puts individual pins
    // at zoom ≥ 16, so this is the normal case, not the edge.
    //
    // So the viewport is read as `pinBands` horizontal strips, each with its own share of the
    // budget. When the budget runs out it now runs out evenly, top to bottom, and the map thins
    // instead of losing its northern half. Five reads of an index range cost single-digit
    // milliseconds together, which is the price.

    /// Horizontal strips the viewport is read in.
    static let pinBands = 5
    /// Per-strip cap. Five of these is ~1,300 — one zoom-16 screenful by `TreeQueries`' own
    /// measurement, and about as many annotation views as MapKit draws without complaint.
    static let pinsPerBand = 260

    // MARK: - Derived content

    var clusters: [TreeCluster] {
        if case let .clusters(clusters) = content { return clusters }
        return []
    }

    /// The pins the current filter admits.
    var pins: [TreePin] {
        guard case let .pins(pins) = content else { return [] }
        switch filter {
        case .all:
            return pins
        case .needsCare:
            return pins.filter { MapPinKind.needsCare(status: $0.status) }
        case .inBloom:
            // Answered from `species.seasonal.bloom_months` and from nothing else. The curated
            // species pipeline (BUILD-PLAN §8) has not landed, so every `seasonal` in the shipped
            // seed is `{}` and this chip currently matches no tree in any month. That is the honest
            // answer to the question the chip asks; inventing bloom months so it looks alive is
            // precisely what BUILD-PLAN §15 and DECISIONS §3.15 forbid.
            let month = calendar.component(.month, from: now())
            return pins.filter { pin in
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
        let next = MapViewport(bounds: bounds.expanded(by: 0.08), zoom: zoom, pinLimit: Self.pinsPerBand)
        guard next != viewport else { return }
        // The clustering threshold is the one boundary where the *shape* of the answer changes, so
        // it never waits behind a debounce that a slow pan could keep re-arming.
        let crossedClusteringThreshold = next.shouldCluster != viewport?.shouldCluster
        viewport = next
        scheduleFetch(immediate: crossedClusteringThreshold)
    }

    private func scheduleFetch(immediate: Bool) {
        fetchTask?.cancel()
        fetchTask = Task { [weak self] in
            if !immediate {
                try? await Task.sleep(for: Self.cameraDebounce)
                if Task.isCancelled { return }
            }
            await self?.fetch()
        }
    }

    /// The one read. Bounded by the viewport, never by anything else.
    func fetch() async {
        guard let viewport else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let content = try await load(viewport)
            guard !Task.isCancelled else { return }
            self.content = content
            loadFailure = nil
            if filter.needsSeasonalData { resolveSpeciesForVisiblePins() }
        } catch let error as APIError {
            loadFailure = error
        } catch {
            loadFailure = .serverError
        }
    }

    /// One viewport, one answer — but the pin half of it is read in bands. See the budget note above.
    private func load(_ viewport: MapViewport) async throws -> MapContent {
        // Clustering aggregates in SQL with no `LIMIT` at all, so a clustered viewport is one read
        // and the banding would buy nothing.
        guard !viewport.shouldCluster else { return try await api.mapContent(in: viewport) }

        let bounds = viewport.bounds
        let step = (bounds.maxLatitude - bounds.minLatitude) / Double(Self.pinBands)
        var pins: [TreePin] = []
        var seen: Set<UUID> = []
        for band in 0..<Self.pinBands {
            let strip = BoundingBox(
                minLatitude: bounds.minLatitude + step * Double(band),
                maxLatitude: bounds.minLatitude + step * Double(band + 1),
                minLongitude: bounds.minLongitude,
                maxLongitude: bounds.maxLongitude
            )
            let read = MapViewport(bounds: strip, zoom: viewport.zoom, pinLimit: Self.pinsPerBand)
            guard case let .pins(found) = try await api.mapContent(in: read) else { continue }
            // Band edges are inclusive on both sides, so a tree sitting exactly on one would come
            // back twice and `ForEach` would rightly complain.
            for pin in found where seen.insert(pin.id).inserted { pins.append(pin) }
        }
        return .pins(pins)
    }

    // MARK: - Filters

    private func filterDidChange() {
        clearSelection()
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
        case .deadReported, .removed, .vacantSite:
            // The gray pin means "no living tree at this site". A `vacant_site` is exactly that,
            // and it routes to the same profile, which decides between 03 and 19.
            return .removed
        case .declining:
            return .needsCare
        }
    }

    static func needsCare(status: TreeStatus) -> Bool { status == .declining }
}

// MARK: - The bottom card's subject

/// What the bottom tree card draws. Starts as the pin (instant, from data already on screen) and is
/// replaced by the full profile when `GET /trees/{id}` returns.
struct MapCardSubject: Identifiable, Equatable {
    let pin: TreePin
    var profile: TreeProfile?

    var id: UUID { pin.id }

    /// The active name if the tree has one, else the species common name — "the species common name
    /// is the fallback display everywhere" (D15).
    var title: String {
        if let name = profile?.activeName, name.isDisplayable { return name.name }
        if let common = profile?.species?.commonName, !common.isEmpty { return common }
        return "Unidentified"
    }

    var scientificName: String? {
        guard let latin = profile?.species?.scientificName, !latin.isEmpty else { return nil }
        return latin
    }

    var badge: StatusBadge.Kind? {
        guard let profile else { return nil }
        return StatusBadge.kind(
            status: profile.tree.status,
            vitality: profile.latestObservation?.vitality,
            plantedYear: profile.tree.plantedYear
        )
    }

    var lastVisitedAt: Date? {
        profile?.visits.map(\.capturedAt).max()
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
