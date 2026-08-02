import Foundation

/// The single boundary every read and write the UI performs goes through (ARCHITECTURE §4).
///
/// The method set mirrors BUILD-PLAN §6 endpoint for endpoint; each method names its endpoint. Two
/// implementations exist: `LocalAPI`, which ships, and `RemoteAPI`, which is a stub whose only job
/// today is to prove that nothing in the protocol assumes a local database.
///
/// **Deliberate omissions, with reasons.**
/// - `POST /auth/*`, `POST /auth/refresh`, `POST /auth/logout`, `DELETE /me` — there is no auth
///   server and no local equivalent of a token exchange. Adding throwing stubs would suggest a
///   sign-in flow exists. Screens 15 and 19 gate on a local account record, which `LocalAPI`
///   provides through `claimDevice`. `DELETE /me`'s *local* half is not a stub and is not omitted:
///   the rows it deletes and anonymizes are on this device, and `LocalAPI.deleteAccount()`
///   implements RULINGS R3 over them.
/// - `GET /tiles/{z}/{x}/{y}` — replaced by MapKit plus `mapContent(in:)` (ARCHITECTURE §1). PMTiles
///   range reads have no meaning in a native build with a vector basemap already on device.
/// - `Admin: /admin/*` — moderator and admin surfaces are a web deliverable, out of scope for the
///   iOS app (ARCHITECTURE §8).
///
/// Errors are `Core`'s `APIError`, never strings (ARCHITECTURE §4).
public protocol CypressAPI: Sendable {

    // MARK: - Map and discovery

    /// Map content for a viewport. Replaces `GET /tiles/{z}/{x}/{y}` for a MapKit basemap.
    ///
    /// Clustering is a property of the zoom, not of the caller: A1 fixes clusters at zoom ≤ 15 and
    /// individual pins at zoom ≥ 16, and `MapViewport` decides which it returns.
    func mapContent(in viewport: MapViewport) async throws -> MapContent

    /// `GET /trees?near=lng,lat&radius=m` — the what-tree-is-this shortlist, ordered by distance,
    /// each row carrying one `id_tip` as its tell (D6, BUILD-PLAN §6).
    func treesNear(_ coordinate: Coordinate, radiusM: Double, limit: Int) async throws -> [NearbyTree]

    /// `GET /trees/{id}` — the profile payload: tree, active name, species, latest observation
    /// summary, photo timeline page 1, measurement series.
    func treeProfile(id: UUID) async throws -> TreeProfile

    /// `POST /trees` — community add. Requires a photo, species optional; runs the 10 m proximity
    /// dedupe against any species and returns `.conflict` with the candidate list when it trips.
    func addTree(_ draft: TreeDraft) async throws -> Tree

    /// Names the species on a community tree that has none — the "after" half of "add tree species
    /// after/at same time as adding a custom tree".
    ///
    /// **Not a BUILD-PLAN §6 endpoint.** §6's species write is `POST /trees/{id}/species-assertions`,
    /// which appends to the versioned chain `SpeciesAssertion` models. That table lives in the
    /// read-only seed database and `main` has no copy of it, so the chain cannot be appended to on
    /// device. What *is* writable is `community_trees.species_current`, and this is the one transition
    /// over it that needs no chain: **nothing to nothing-in-particular**. See `SpeciesClaim` for the
    /// two refusals that fall out of that, both of which this method enforces rather than merely
    /// documenting.
    ///
    /// - Returns: the tree as it now stands.
    /// - Throws: `.notFound` when there is no such tree, `.forbidden` for a city-import row, and
    ///   `.conflict` when a species is already claimed — a correction, which needs the chain.
    ///
    /// Defaulted in `SpeciesClaim.swift` to `.notFound`, which is the truthful answer from an
    /// implementation with no store to find the tree in.
    func claimSpecies(treeID: UUID, speciesID: UUID) async throws -> Tree

    // MARK: - Species

    /// `GET /species/{id}` — the field guide entry.
    func species(id: UUID) async throws -> Species

    /// `GET /species?query=` — autocomplete over both the scientific and the common name.
    func searchSpecies(query: String, limit: Int) async throws -> [Species]

    /// `GET /species/{id}` as screen 07 needs it: the field-guide entry plus how common the species
    /// is nearby. `near` is the caller's fix, or nil when there is none.
    ///
    /// Defaulted in `SpeciesGuide.swift` to the entry with no population facts attached, which is
    /// the honest answer for an implementation that has no inventory to count.
    func speciesGuide(id: UUID, near coordinate: Coordinate?) async throws -> SpeciesGuide

    // MARK: - Almanac

    /// The neighbourhood almanac (screen 12). `near` is the caller's fix, or nil when there is none.
    ///
    /// Not a BUILD-PLAN §6 endpoint: §6 has no aggregate read at all, because the almanac arrived
    /// with D1 after the API contract was written. On a server it is one `GET /neighborhoods/{id}/
    /// almanac`; here the neighbourhood is resolved from the fix rather than named by the caller,
    /// because A4's mechanism for naming one does not exist (ERRATA E44).
    ///
    /// Defaulted in `Almanac.swift` to the empty almanac, which is what an implementation with no
    /// city inventory truthfully has.
    func almanac(near coordinate: Coordinate?) async throws -> Almanac

    // MARK: - Sync

    /// `POST /sync` — the batch endpoint. Takes outbox items carrying their `client_uuid`s and
    /// returns one result per item. Dedupe on `client_uuid` is the server's job and, here, the
    /// local store's: a re-sent item comes back `.duplicate`, which is a success.
    func sync(_ items: [OutboxItem]) async throws -> [SyncResult]

    /// `POST /photos/begin` — reserves a photo id and an upload destination. The client PUTs the
    /// binary, then includes the photo id in the visit's sync item.
    func beginPhotoUpload(_ request: PhotoUploadRequest) async throws -> PhotoUploadTicket

    /// Uploads one photo binary. Not a §6 endpoint — §6 hands back a presigned URL and the client
    /// PUTs to storage — but the outbox needs one call it can name for the binary phase, and
    /// `LocalAPI` implements it as a move into the app's photo directory.
    func uploadPhoto(at localPath: String, ticket: PhotoUploadTicket) async throws

    /// `GET /photos/{id}` — the bytes of a photograph this device may show. Defaulted in
    /// `PhotoAccess.swift`; `LocalAPI` overrides it.
    ///
    /// **Declared here, and that is the entire point of the line.** Both of these methods first
    /// existed only as extension members. An extension member is not a requirement, so it has no
    /// witness-table entry and dispatches *statically*: `LocalAPI`'s implementations were reached
    /// when the value was a `LocalAPI`, and the extension's `throw APIError.notFound` was reached the
    /// moment it was erased to `any CypressAPI` — which is what every screen holds. Every photograph
    /// failed to load and every vote failed to save, on a build whose tests all passed, because the
    /// tests held the concrete type (ERRATA E125).
    func photoData(id: UUID) async throws -> Data

    /// A thumb up or down on a photograph, or `nil` to withdraw it (`AppSchema` v8). Defaulted in
    /// `PhotoAccess.swift`; see `photoData` above for why it is declared here and not only there.
    func setPhotoVote(photoID: UUID, vote: PhotoVote?) async throws

    /// Removes one photograph this person contributed — the bytes from the device, the row from
    /// every surface that draws it (ERRATA E147, task #78).
    ///
    /// **Not a BUILD-PLAN §6 endpoint.** §6 has `POST /photos/begin` and nothing that unmakes a
    /// photograph; the nearest sentence in the corpus is SPEC-PHASE1 §"Sync never deletes community
    /// photos or visits", which is about what *sync* may do to somebody else's record and not about
    /// what a contributor may do to their own. The ask is the owner's, verbatim — "allow photo
    /// deletions for your own photos" — and it is a privacy control before it is a tidiness one: a
    /// photograph can hold a face, a licence plate or the inside of somebody's front garden, and the
    /// person who took it has to be able to take it back. When the service lands this becomes
    /// `DELETE /photos/{id}` and this signature does not move.
    ///
    /// - Throws: `.notFound` when there is no such live photograph, `.forbidden` when it is not this
    ///   person's — including when it is nobody's, which is what an account deletion through the
    ///   leaving door makes of it.
    ///
    /// **Declared here and not only in an extension**, for the reason `photoData` gives above at
    /// length: an extension member has no witness-table entry, and every screen holds
    /// `any CypressAPI`. A `deletePhoto` that only existed in an extension would return the
    /// default's `throw .notFound` from every screen in the app while passing every test that held a
    /// `LocalAPI` (ERRATA E125).
    func deletePhoto(id: UUID) async throws -> PhotoDeletion

    // MARK: - Personal surfaces (private by default, D11)

    /// `GET /me/grove`.
    func grove() async throws -> [GroveEntry]

    /// `GET /me/grove` narrowed to one tree: whether this contributor currently holds it (#167).
    ///
    /// Screen 03's heart re-reads its state after every write (RULINGS R2), and it used to do that
    /// through `grove()` — the whole list, resolved tree by tree, to answer one membership bit. This
    /// is the same question asked at the width it is asked at. `LocalAPI` answers it with one
    /// indexed SELECT over both ownership arms (the device's rows and the account's), the same two
    /// arms `grove()` reads and for the same E89 reason.
    ///
    /// Defaulted below to the grove-derived answer, which keeps every test double truthful without
    /// teaching it a second favorites vocabulary. **Declared here and not only in the extension** —
    /// see `photoData` above, and ERRATA E125, for the day a requirement that lived only in an
    /// extension dispatched statically past the implementation that had the real answer.
    func isFavorite(treeID: UUID) async throws -> Bool

    /// `GET /me/grove`, the Species tab (screen 08).
    ///
    /// A second read rather than a wider `GroveEntry` because the two tabs of My Grove are keyed on
    /// different things — one on the contributor's trees, one on the species they have come to know
    /// — and because the ring's denominator is a fact about the city's inventory that no list of
    /// the contributor's own trees contains. See `GroveSpecies`.
    func groveSpecies() async throws -> GroveSpecies

    /// `GET /me/journal`, cursor-paginated (`?cursor`, `?limit` max 100).
    func journal(cursor: String?, limit: Int) async throws -> Page<JournalEntry>

    /// `POST /devices/claim` — attach an anonymous device's contributions to the signed-in user (D9).
    func claimDevice(deviceUUID: UUID, userID: UUID) async throws

    /// What this device is holding that `claimDevice` would carry onto an account (D9).
    ///
    /// Not a BUILD-PLAN §6 endpoint. §6 has no read of a device's own unattributed rows because it
    /// was written for a server, where the device is the thing asking and already knows. On a
    /// local-first client the screen that has to say `Keep your three visits` is the one place the
    /// number is needed and the only honest source is the store — see `DeviceContributions` for why
    /// the ledger's save counter is not it, and why this is not the count D1 forbids.
    ///
    /// Defaulted in `DeviceContributions.swift` to `.none`, which is what an implementation with no
    /// contribution store truthfully holds.
    func deviceContributions() async throws -> DeviceContributions

    /// The trees this reader has a relationship with, by kind — the sets behind screen 01's `Yours`
    /// and `Favourites` chips (#116, RULINGS R23).
    ///
    /// Not a BUILD-PLAN §6 endpoint, for the reason `deviceContributions()` is not: §6 was written
    /// for a server, where the client's own rows are the client's own business. On a local-first
    /// build the map needs the id set before it can ask the seed for pins, and the seed cannot
    /// answer it — what this device has visited, measured or hearted is in `main`.
    ///
    /// **It returns ids and nothing else, deliberately.** A count of one's own contributions is
    /// exactly what D1 forbids as a user-visible figure, and the safest way not to render one is not
    /// to have one in hand: `Set<UUID>.count` is a number about trees on a map, which is what
    /// `PinAnswer` already reports, and the filter surface reads it from there.
    ///
    /// Defaulted in `MapMembership.swift` to the empty set, which is what an implementation with no
    /// contribution store truthfully holds. **Declared here and not only in an extension** — see
    /// `photoData` above for the full argument, and ERRATA E125 for the day every photograph in the
    /// app failed to load because a requirement lived in an extension and dispatched statically.
    func mapMembership(_ kind: MapMembership) async throws -> Set<UUID>

    // MARK: - Reports and export

    /// `POST /reports/hazard-redirect` — logs that a 311 redirect was shown. Analytics only, no
    /// public record. `private_reminders` is a separate write (D4).
    func logHazardRedirect(_ event: HazardRedirectEvent) async throws

    /// `GET /export/latest.csv` / `.geojson` — the nightly export, carrying `verification_state`
    /// (D12, BUILD-PLAN §5).
    func exportLatest(_ format: ExportFormat) async throws -> Data
}

public extension CypressAPI {
    /// The grove-derived default for `isFavorite(treeID:)` — one membership bit out of the same
    /// read the heart used before the per-tree read existed (#167). Correct for any conformance
    /// whose `grove()` tells the truth; `LocalAPI` overrides it with the narrow query.
    func isFavorite(treeID: UUID) async throws -> Bool {
        try await grove().first { $0.treeID == treeID }?.isFavorite ?? false
    }
}

// MARK: - Two methods that were requirements and are not any more
//
// `outboxStatus()` and `savePrivateReminder(_:)` were both declared here and implemented by every
// conformance — two shipping types, thirteen preview doubles, five test doubles — and **neither had
// a single caller.** Screen 17's "says why" line reads `OutboxViewState` directly, which is the
// live view of the queue rather than a snapshot fetched from it; screen 06 writes its reminder
// through `ReminderOutboxWriter`, because what goes into the outbox has to be the whole mutation
// (ARCHITECTURE §4) and a single-item door around the side of it was never the way in.
//
// A protocol requirement nobody calls is not free. Every new conformance has to answer it, and the
// twenty stubs that did were all `[]` or `throw .forbidden` — twenty places for a real
// implementation to be quietly missing, and twenty more lines between a reader and the methods that
// matter. Deleted rather than deprecated: there is one app and it is in this repository, so the
// compiler can find every caller, and there are none.
//
// **`LocalAPI.savePrivateReminder` stays**, as a method on the concrete type. It implements D4's
// separate `private_reminders` write and D9's ownership rules, `CypressTests/PrivateReminderTests`
// exercises both against the real store, and it is the natural single-item door for a `sync` batch
// of one. What it is not is something every conformance owes an answer to. If a caller ever needs it
// through `any CypressAPI`, it goes back **as a requirement and not as a protocol-extension member**
// — an extension member has no witness-table entry and dispatches statically, which is how every
// photograph in the app failed to load on a build whose tests all passed (ERRATA E125, and the note
// on `photoData` above).

// MARK: - Viewport

/// A WGS-84 bounding box. Normalized on construction so a caller cannot pass an inverted box and
/// silently get zero rows.
public struct BoundingBox: Hashable, Sendable {
    public let minLatitude: Double
    public let maxLatitude: Double
    public let minLongitude: Double
    public let maxLongitude: Double

    public init(minLatitude: Double, maxLatitude: Double, minLongitude: Double, maxLongitude: Double) {
        self.minLatitude = min(minLatitude, maxLatitude)
        self.maxLatitude = max(minLatitude, maxLatitude)
        self.minLongitude = min(minLongitude, maxLongitude)
        self.maxLongitude = max(minLongitude, maxLongitude)
    }

    /// A box around a point, sized in metres. Used to turn `?near=lng,lat&radius=m` into an
    /// index-usable range on `lat`/`lon`.
    public init(around centre: Coordinate, radiusM: Double) {
        let metresPerDegreeLatitude = 111_320.0
        let latitudeSpan = radiusM / metresPerDegreeLatitude
        // cos() collapses toward the poles; the floor keeps the longitude span finite there.
        let cosLatitude = max(cos(centre.latitude * .pi / 180), 0.000_01)
        let longitudeSpan = radiusM / (metresPerDegreeLatitude * cosLatitude)
        self.init(
            minLatitude: centre.latitude - latitudeSpan,
            maxLatitude: centre.latitude + latitudeSpan,
            minLongitude: centre.longitude - longitudeSpan,
            maxLongitude: centre.longitude + longitudeSpan
        )
    }

    public func contains(_ coordinate: Coordinate) -> Bool {
        coordinate.latitude >= minLatitude && coordinate.latitude <= maxLatitude
            && coordinate.longitude >= minLongitude && coordinate.longitude <= maxLongitude
    }
}

/// A map request: what the user can see, and how far in they are.
public struct MapViewport: Hashable, Sendable {
    public let bounds: BoundingBox
    /// Standard web-mercator zoom, as MapKit reports it.
    public let zoom: Int
    /// Hard cap on individual pins returned in one response. Above this the map is not readable
    /// anyway and the answer is to cluster.
    public let pinLimit: Int

    /// How many screen points one drawn pin may stand for, or `nil` for every pin in the box.
    ///
    /// **This is the level-of-detail rule between the clustering threshold and maximum zoom, and
    /// until ERRATA E130 there was none.** A1 puts individual pins at zoom ≥ 16 and nothing thinned
    /// them above it, so the size of the answer tracked the viewport's *area*. The camera opens at
    /// 120 m; one pinch out is four times the ground and two is sixteen, and at sixteen times the
    /// ground the map stopped answering — which is exactly "SUPER slow when you zoom out a bit", and
    /// why it went fast again further out, where clustering caps the badges.
    ///
    /// With a cell set, the box is gridded into cells this many points square *at this zoom* and one
    /// tree per occupied cell comes back — but only once the un-thinned answer would overrun
    /// `pinLimit`. What that buys is that the count is then bounded by screen area ÷ cell area, which
    /// is the same number at every zoom: pulling the camera back stops adding annotations and starts
    /// making each pin stand for more ground.
    ///
    /// `nil` by default, which is the un-thinned query, because `pinLimit` means exactly what it says
    /// to the callers that already depend on it — `CypressTests/MapContentBudgetTests` reaches its
    /// cap deliberately with a `pinLimit` of 3 over a block of the Marina, and a query that quietly
    /// returned fewer rows than the budget allows would change that contract. `MapModel` is what
    /// passes a cell, and `MapModel.markerCellPoints` is why 44.
    public let markerCellPoints: Double?

    /// The species the map has been narrowed to, or `nil` for every species.
    ///
    /// **NOT SPECIFIED** — SCREENS.md 01 says "search opens species/street/neighborhood search"
    /// (:664) and then "NOT SPECIFIED: search results" (:667). The intent is stated; the surface
    /// never was. This is the narrowing half of it, and `MapSearch` is the reasoning for the rest.
    ///
    /// It rides on the viewport rather than arriving as a second argument to `mapContent(in:)`
    /// deliberately, and for two reasons. The signature does not change, so none of the fifteen
    /// preview doubles and five test doubles that conform to `CypressAPI` have to be touched. And
    /// `MapViewport` is `Hashable`, which is what `MapModel`'s fetch debounce dedupes on — so a
    /// changed query is a *different viewport*, refetched, and an unchanged one coalesces exactly as
    /// a pan already does. Adding a parameter would have left the debounce unable to see the
    /// difference between the same box searched two ways.
    ///
    /// A tree the city recorded no species for can never be in this set: 12,830 of the 195,309 rows
    /// carry `species_current IS NULL`, and a narrowed map is expected to empty out over them.
    public let speciesIDs: Set<UUID>?

    /// The planting years the map has been narrowed to, or `nil` for every year (#116, RULINGS R23).
    ///
    /// **A tree with no recorded planting date is never in this range, and that is the whole design
    /// problem this field carries.** Measured against the shipped seed: 145,837 rows, of which
    /// **37,962 (26.03 %) carry `planted_year` at all** — and among the 133,424 *living* trees it is
    /// 28,725, or 21.5 %. So a year narrowing does not thin the map, it empties it: roughly four out
    /// of five living street trees can never satisfy any range a reader picks, not because they were
    /// planted outside it but because the city never wrote the date down.
    ///
    /// Silently dropping those rows is the defect ERRATA E175 records. The predicate is honest —
    /// `planted_year BETWEEN a AND b` is exactly what was asked — and the *surface* is what has to
    /// carry the rest: `MapYearFilterCopy` says how many trees in view were set aside for having no
    /// date, every time the narrowing is on. A filter that cannot judge a row must say so rather
    /// than let its absence read as an answer.
    ///
    /// A `ClosedRange` rather than a single year because the seed spans 1955–2026 and a per-year
    /// control would offer 72 options holding a citywide mean of 527 trees each — invisible in a
    /// viewport. `MapFilter.Decade` is what picks the range.
    public let plantedYears: ClosedRange<Int>?

    /// The trees this reader has a relationship with, when the map has been narrowed to them — the
    /// `Yours` and `Favourites` chips (#116, RULINGS R23). `nil` for every tree.
    ///
    /// **It is an explicit id set rather than a predicate because it is a fact about `main`, not
    /// about the inventory.** What this device has visited, photographed, checked in on, measured or
    /// hearted lives in the app's own tables; the seed knows none of it and no `WHERE` clause over
    /// `trees` could. So the set is resolved first — `CypressAPI.mapMembership(_:)` — and travels
    /// here, exactly as `speciesIDs` does, so that a changed membership is a *different viewport*
    /// and the fetch debounce can see the difference.
    ///
    /// **Empty means "the map is narrowed to nothing", never "no narrowing"**, on the same terms as
    /// `speciesIDs`: a reader with no favourites who taps `Favourites` has asked a question whose
    /// honest answer is an empty map with a sentence over it, not the whole city.
    ///
    /// It is bounded by what one person tapped — tens, not thousands — which is why the queries
    /// answering it need no pin budget. See `TreeQueries.Narrowing`.
    public let treeIDs: Set<UUID>?

    /// **A1, resolved**: "pins cluster at zoom 15 and below; individual pins at zoom 16 and above
    /// (the spec sentence was backwards)" — BUILD-PLAN §11. This constant is the only place that
    /// number appears.
    public static let highestClusteringZoom = 15

    public init(
        bounds: BoundingBox,
        zoom: Int,
        pinLimit: Int = 2_000,
        markerCellPoints: Double? = nil,
        speciesIDs: Set<UUID>? = nil,
        plantedYears: ClosedRange<Int>? = nil,
        treeIDs: Set<UUID>? = nil
    ) {
        self.bounds = bounds
        self.zoom = zoom
        self.pinLimit = pinLimit
        self.markerCellPoints = markerCellPoints
        self.speciesIDs = speciesIDs
        self.plantedYears = plantedYears
        self.treeIDs = treeIDs
    }

    /// Whether this viewport has been narrowed to a species at all.
    public var isNarrowed: Bool { speciesIDs != nil }

    /// Whether anything at all narrows this viewport — species, planting year, or membership.
    public var isFiltered: Bool {
        speciesIDs != nil || plantedYears != nil || treeIDs != nil
    }

    /// **A1's clustering rule, and the one narrowing that suspends it.**
    ///
    /// A1 fixes clusters at zoom ≤ 15 because the un-narrowed answer over 145,837 trees is unbounded
    /// and a badge is how an unbounded answer is made drawable. A membership narrowing is bounded by
    /// construction — it is the set of trees one person has touched, and a person cannot tap a
    /// hundred thousand hearts — so there is nothing for a badge to bound. Clustering it would take
    /// a reader who asked "where are my trees?" and answer with a number they then have to zoom into
    /// four times to see, when the whole set fits on one screen of the city.
    ///
    /// So this is a deliberate, argued deviation from A1 rather than a bug, and it is narrow: it
    /// applies only when `treeIDs` is set. Every other viewport, narrowed or not, clusters exactly
    /// where it always did — including a year narrowing, which can still match 37,962 trees.
    public var shouldCluster: Bool {
        if treeIDs != nil { return false }
        return zoom <= MapViewport.highestClusteringZoom
    }
}

/// One clustered cell.
///
/// **There is deliberately no representative tree id here.** An earlier version carried one, and it
/// cost 3.4× on the hottest query in the app: `MIN(trees.uuid)` is not in `idx_trees_lat_lon`, so
/// asking for it turns a covering-index scan into a table probe for every one of the 195,309 rows
/// and takes the whole-city cluster query from 104 ms to 355 ms. Nothing in SCREENS.md asks for it —
/// tapping a cluster zooms in, which is what the badge means — so the field is gone rather than
/// paid for.
public struct TreeCluster: Hashable, Sendable, Identifiable {
    /// Stable across pans at the same zoom, because the grid is absolute rather than relative to
    /// the viewport's corner — the same cell keeps the same id as the user drags, so the badge does
    /// not flicker and re-animate.
    public let id: String
    public let coordinate: Coordinate
    public let count: Int

    public init(id: String, coordinate: Coordinate, count: Int) {
        self.id = id
        self.coordinate = coordinate
        self.count = count
    }
}

/// One individual pin. Deliberately thin: the map draws thousands of these and needs four facts,
/// not a whole `Tree`.
public struct TreePin: Hashable, Sendable, Identifiable {
    public let id: UUID
    public let coordinate: Coordinate
    public let status: TreeStatus
    /// Community-added trees stay in a visually distinct layer (DECISIONS §3.16).
    public let source: TreeSource
    public let verificationState: VerificationState
    public let speciesID: UUID?

    public init(
        id: UUID,
        coordinate: Coordinate,
        status: TreeStatus,
        source: TreeSource,
        verificationState: VerificationState,
        speciesID: UUID?
    ) {
        self.id = id
        self.coordinate = coordinate
        self.status = status
        self.source = source
        self.verificationState = verificationState
        self.speciesID = speciesID
    }
}

/// The pin half of a viewport's answer, and whether it is the whole of it.
///
/// **It exists because "fewer pins" and "all the pins there are" look identical in an array.** The
/// marker grid (`MapViewport.markerCellPoints`) returns one tree per 44 pt cell once the budget is
/// overrun, so a `[TreePin]` of 151 can mean either "there are 151" or "there are 1,458 and these
/// are the ones that won their cells". Screen 01 could not tell those apart, and neither could
/// anything downstream — which is the shape of defect ERRATA E38 exists to forbid: a truncated set
/// presented as a complete one.
///
/// Before the search bar did anything the distinction was invisible, because an un-narrowed map is
/// *about* the neighbourhood rather than about a set the reader named, and nobody counts the trees
/// out of a window. Ask for London Planes and it is a claim: the reader has named a set and the map
/// is answering with it. So the count travels.
///
/// It is a `RandomAccessCollection` over its own pins so that the fifteen preview doubles and five
/// test doubles that write `.pins([])` keep compiling untouched — `ExpressibleByArrayLiteral` takes
/// the literal, and `count`, `map`, `filter`, `prefix` and `for…in` all reach the items directly.
public struct PinAnswer: Hashable, Sendable, RandomAccessCollection, ExpressibleByArrayLiteral {
    /// The pins to draw.
    public let items: [TreePin]

    /// How many trees actually satisfied the request, when that is more than `items` holds.
    ///
    /// `nil` means `items` **is** the complete answer — not "unknown". Every path that thins sets
    /// it, and every path that does not leaves it nil, so a reader may treat nil as a guarantee.
    public let matchesInView: Int?

    public init(_ items: [TreePin], matchesInView: Int? = nil) {
        self.items = items
        // A "sample" that dropped nothing is not a sample. Collapsing it here means no caller has to
        // remember the special case, and `isSample` cannot be true over a complete answer.
        self.matchesInView = matchesInView.flatMap { $0 > items.count ? $0 : nil }
    }

    public init(arrayLiteral elements: TreePin...) {
        self.init(elements)
    }

    /// Whether the map is drawing a spatial sample of the matches rather than all of them.
    public var isSample: Bool { matchesInView != nil }

    /// How many trees this answer stands for — the matches when it is a sample, else the pins drawn.
    public var treesRepresented: Int { matchesInView ?? items.count }

    public var startIndex: Int { items.startIndex }
    public var endIndex: Int { items.endIndex }
    public subscript(position: Int) -> TreePin { items[position] }

    /// The same answer over different pins, keeping what is known about how many matched.
    ///
    /// Used where the pins are rewritten but the population behind them is not — the status
    /// overrides in `LocalAPI.mapContent`, which change what a pin *is* and never which trees the
    /// query found.
    public func withItems(_ items: [TreePin]) -> PinAnswer {
        PinAnswer(items, matchesInView: matchesInView)
    }
}

/// What a viewport resolved to. An enum rather than two optional arrays: at any zoom exactly one of
/// the two is meaningful, and A1 decides which.
public enum MapContent: Hashable, Sendable {
    case clusters([TreeCluster])
    case pins(PinAnswer)

    /// How many trees this answer stands for.
    ///
    /// For a clustered viewport that is the sum of the badges; for pins it is the pins drawn, unless
    /// the grid thinned them, in which case it is how many actually matched. Both halves therefore
    /// answer the same question — "how many trees are we telling the reader about" — which is what
    /// makes `markerCount` below the *other* question rather than a duplicate of this one.
    public var pinCount: Int {
        switch self {
        case let .pins(pins): return pins.treesRepresented
        case let .clusters(clusters): return clusters.reduce(0) { $0 + $1.count }
        }
    }

    /// How many things the map has to *draw* for this answer — one annotation per pin, one per
    /// cluster badge.
    ///
    /// Not the same question as `pinCount`, which counts trees: a clustered viewport holds 29,390
    /// trees and draws 171 badges. This is the number the level-of-detail rule bounds, and the one
    /// that had no bound at all between zoom 16 and 21 (`MapViewport.markerCellPoints`).
    public var markerCount: Int {
        switch self {
        case let .pins(pins): return pins.count
        case let .clusters(clusters): return clusters.count
        }
    }
}

// MARK: - Shortlist

/// A row of the what-tree-is-this shortlist (screen 02).
public struct NearbyTree: Hashable, Sendable, Identifiable {
    public var id: UUID { tree.id }
    public let tree: Tree
    /// Great-circle metres from the query point. Screen 02 renders this as `17 m S`.
    public let distanceM: Double
    public let speciesScientificName: String?
    public let speciesCommonName: String?
    /// "each row carrying one id_tip as its tell" (BUILD-PLAN §6, D6).
    ///
    /// `nil` until the curated species pipeline (BUILD-PLAN §8) lands: the shipped seed declares
    /// `species.id_tips` and leaves it `[]`. The UI must render the row without a tell rather than
    /// invent one — no fabricated botany (BUILD-PLAN §15).
    public let tell: IDTip?

    public init(
        tree: Tree,
        distanceM: Double,
        speciesScientificName: String?,
        speciesCommonName: String?,
        tell: IDTip?
    ) {
        self.tree = tree
        self.distanceM = distanceM
        self.speciesScientificName = speciesScientificName
        self.speciesCommonName = speciesCommonName
        self.tell = tell
    }
}

// MARK: - Profile

/// `GET /trees/{id}`'s payload.
public struct TreeProfile: Hashable, Sendable {
    public let tree: Tree
    /// The one active name, if a tree has been named (D15). The species common name is the fallback
    /// display everywhere.
    public let activeName: TreeName?
    public let species: Species?
    /// The seed carries no UUID for a neighborhood — `name` is its external key — so `tree`'s
    /// `neighborhoodID` is nil and the name travels here instead.
    public let neighborhoodName: String?
    /// The most recent check-in, for the profile's summary line.
    public let latestObservation: TreeObservation?
    /// The check-in series.
    ///
    /// Added for screen 13, whose middle small multiple is a twelve-month `Check-ins` row and whose
    /// three charts share one scale (D2) — a scale set by the tallest bar across all three. Neither
    /// the row nor the shared scale can be drawn from `latestObservation`: one check-in in October
    /// renders as a year in which one check-in happened, which is the same class of wrong number
    /// `Series` exists to make unwritable (ERRATA E38). So the series travels, and it travels as a
    /// `Series` rather than an array for the same reason `visits` and `careEvents` do.
    ///
    /// It also completes A8. `TreeProfilePresentation.caretakers` counts "distinct users with 2 or
    /// more care_events **or observations**"; with only the latest observation in hand the second
    /// half of that sentence could contribute exactly one person, which the code said out loud and
    /// called a payload limit. It is not a limit any more.
    public let observations: Series<TreeObservation>
    /// The photo timeline. BUILD-PLAN §6 calls this "photo timeline page 1", and a `Series` is what
    /// carries that honestly: it says whether it *is* a page, so the hero's count and its `since`
    /// year cannot be taken off one (ERRATA E38).
    public let photos: Series<Photo>
    /// The full measurement series. Splitting it into the two never-connected chart series is
    /// `Collection<TreeMeasurement>.splitBySeries(kind:)`'s job (D7).
    public let measurements: [TreeMeasurement]
    public let visits: Series<Visit>
    public let careEvents: Series<CareEvent>
    /// Public notes only. Hazard categories cannot appear here — they cannot be stored (D4).
    public let communityNotes: [CommunityNote]
    /// The tree this site replaced, when the site has a lineage (memorial record, screen 19).
    public let siteLineageTreeID: UUID?

    /// Which of `photos` this installation contributed itself.
    ///
    /// Moderation gates *publication*, not a person's own screen (see `Photo.isPubliclyVisible` vs
    /// `Photo.isVisibleToItsContributor`). Deciding which photos are the viewer's own is not a
    /// judgement a view can make, and it is not one to infer from a `.pending` state either — every
    /// photo in the app is `.pending`, including, one day, other people's. So the fact travels on
    /// the payload, from whoever knows it.
    ///
    /// `LocalAPI` knows it absolutely: `main.photos` holds what this device wrote and nothing else,
    /// because there is no sync that brings anybody else's rows down. `RemoteAPI` will fill this
    /// from the server's attribution, and everything it does not list stays gated on `.approved`.
    public let ownPhotoIDs: Set<UUID>

    /// Which of `photos` this viewer may **delete** (`AppSchema` v12, ERRATA E147).
    ///
    /// A different question from `ownPhotoIDs` and therefore a different set, on the same principle
    /// that keeps `isPubliclyVisible` and `isVisibleToItsContributor` apart. `ownPhotoIDs` asks
    /// whether this device may *show* the photograph, and the answer is every row it holds.
    /// This asks whether this person may take it back, and the answer is the rows whose owner column
    /// names their account or this device. The two differ on exactly one kind of row and it is the
    /// kind that matters: a photograph anonymized by an account deletion is still shown — it is on
    /// the tree, that is what the leaving door promised — and is no longer anybody's to unmake.
    ///
    /// Empty on `RemoteAPI` until a server can answer it, which is the safe direction: a missing
    /// answer hides a control rather than offering one that would fail.
    public let deletablePhotoIDs: Set<UUID>

    /// What has been voted on `photos`, keyed by photo (`AppSchema` v8, ERRATA E125).
    ///
    /// It travels with the series rather than being fetched beside it because the hero and the
    /// browser both derive from the pair, and a screen that read the photographs at one moment and
    /// the votes at another could draw a hero that its own list disagrees with. Photos nobody has
    /// voted on are simply absent; `PhotoHero` reads a missing entry as zero.
    public let photoTallies: [UUID: PhotoTally]

    /// Which city inventory this record came out of, and when that inventory was read.
    ///
    /// **A property of the row, not of the file.** It read the other way once, and the sentence is
    /// corrected here rather than deleted because it is the belief that kept four surfaces on the
    /// tree profile saying `SF` (ERRATA E181): a value that is the same for every tree in a build is
    /// not worth asking a row for. It is not the same for every tree. `LocalAPI.provenance(of:in:)`
    /// resolves it from `trees.inventory_source`, and the shipped seed holds three inventories
    /// across two cities. It travels on the payload because the presentation layer may not reach
    /// past `CypressAPI` for it (ARCHITECTURE §4).
    ///
    /// `nil` for a community-added tree — nobody's inventory lists it, and the honest surface for
    /// that is no provenance line rather than one naming a source the record did not come from.
    /// Also nil for a seed built before the receipt carried these keys.
    public let inventorySource: InventorySource?

    public init(
        tree: Tree,
        activeName: TreeName? = nil,
        species: Species? = nil,
        neighborhoodName: String? = nil,
        latestObservation: TreeObservation? = nil,
        observations: Series<TreeObservation> = .empty,
        photos: Series<Photo> = .empty,
        measurements: [TreeMeasurement] = [],
        visits: Series<Visit> = .empty,
        careEvents: Series<CareEvent> = .empty,
        communityNotes: [CommunityNote] = [],
        siteLineageTreeID: UUID? = nil,
        ownPhotoIDs: Set<UUID> = [],
        deletablePhotoIDs: Set<UUID> = [],
        photoTallies: [UUID: PhotoTally] = [:],
        inventorySource: InventorySource? = nil
    ) {
        self.tree = tree
        self.activeName = activeName
        self.species = species
        self.neighborhoodName = neighborhoodName
        self.latestObservation = latestObservation
        self.observations = observations
        self.photos = photos
        self.measurements = measurements
        self.visits = visits
        self.careEvents = careEvents
        self.communityNotes = communityNotes
        self.siteLineageTreeID = siteLineageTreeID
        self.ownPhotoIDs = ownPhotoIDs
        self.deletablePhotoIDs = deletablePhotoIDs
        self.photoTallies = photoTallies
        self.inventorySource = inventorySource
    }

    /// Whether this device contributed the photo, and may therefore show it to the person who took
    /// it whatever moderation has or has not done with it yet.
    public func isOwnPhoto(_ photo: Photo) -> Bool { ownPhotoIDs.contains(photo.id) }

    /// Whether this person may delete the photo — see `deletablePhotoIDs` for why this is not the
    /// same question as `isOwnPhoto`.
    public func isDeletablePhoto(_ photo: Photo) -> Bool { deletablePhotoIDs.contains(photo.id) }
}

/// The body of `POST /trees`.
public struct TreeDraft: Hashable, Sendable {
    public let clientUUID: UUID
    public let coordinate: Coordinate
    /// How `coordinate` was arrived at, which the record keeps (`community_trees.placement`,
    /// AppSchema v10). It defaults to `.gps` so that the caller who does not offer a pin is not
    /// obliged to have an opinion, and so that the default on the boundary and the default in the
    /// column say the same thing.
    public let placement: TreePlacement
    public let speciesID: UUID?
    /// Required: "Community add: requires photo" (BUILD-PLAN §6).
    public let photoLocalPath: String
    public let attribution: Attribution
    public let address: String?
    /// What ground the contributor says the tree stands on (`community_trees.land_context`,
    /// AppSchema v11).
    ///
    /// **Optional, and nil means "they did not say" rather than any of the four.** It defaults to
    /// nil so that a caller with no picker is not obliged to have an opinion, and so that the
    /// default on the boundary and the absence of a default on the column say the same thing.
    /// Nothing may substitute a plausible answer here — a guessed `.street` on a tree in somebody's
    /// front yard is the failure this field must not have. The same argument BUILD-PLAN §6 makes for
    /// an optional species: a required field does not collect better answers, it collects guesses.
    public let landContext: LandContext?

    public init(
        clientUUID: UUID = UUID(),
        coordinate: Coordinate,
        placement: TreePlacement = .gps,
        speciesID: UUID? = nil,
        photoLocalPath: String,
        attribution: Attribution,
        address: String? = nil,
        landContext: LandContext? = nil
    ) {
        self.clientUUID = clientUUID
        self.coordinate = coordinate
        self.placement = placement
        self.speciesID = speciesID
        self.photoLocalPath = photoLocalPath
        self.attribution = attribution
        self.address = address
        self.landContext = landContext
    }

    /// "runs the proximity dedupe check (10 m, any species)" (BUILD-PLAN §6).
    public static let proximityDedupeRadiusM: Double = 10
}

/// Thrown alongside `APIError.conflict` when the 10 m dedupe trips, so the UI can show the
/// candidate list rather than a bare error.
public struct ProximityConflict: Error, Sendable {
    public let candidates: [NearbyTree]
    public init(candidates: [NearbyTree]) { self.candidates = candidates }
}

// MARK: - Photos

public struct PhotoUploadRequest: Hashable, Sendable {
    public let treeID: UUID
    public let visitID: UUID?
    public let shotType: ShotType
    public let localPath: String
    public let capturedAt: Date
    public let width: Int?
    public let height: Int?
    /// Snapped to the 25 m public grid before it reaches here (A7, BUILD-PLAN §10).
    public let publicCoordinate: Coordinate?

    public init(
        treeID: UUID,
        visitID: UUID? = nil,
        shotType: ShotType,
        localPath: String,
        capturedAt: Date,
        width: Int? = nil,
        height: Int? = nil,
        publicCoordinate: Coordinate? = nil
    ) {
        self.treeID = treeID
        self.visitID = visitID
        self.shotType = shotType
        self.localPath = localPath
        self.capturedAt = capturedAt
        self.width = width
        self.height = height
        self.publicCoordinate = publicCoordinate
    }
}

/// `{photo_id, presigned_put_url}` (BUILD-PLAN §6). `LocalAPI` returns a `file:` destination inside
/// the app container; `RemoteAPI` will return the presigned URL.
public struct PhotoUploadTicket: Hashable, Sendable {
    public let photoID: UUID
    public let destination: URL

    public init(photoID: UUID, destination: URL) {
        self.photoID = photoID
        self.destination = destination
    }

    /// "A photo record with no arriving binary after 72 h is garbage-collected" (BUILD-PLAN §6).
    public static let binaryGracePeriod: TimeInterval = 72 * 60 * 60
}

// MARK: - Personal surfaces

/// A row of `GET /me/grove`. Private by default (D11).
public struct GroveEntry: Hashable, Sendable, Identifiable {
    public var id: UUID { treeID }
    public let treeID: UUID
    public let displayName: String
    public let coordinate: Coordinate
    public let lastVisitedAt: Date?
    public let isFavorite: Bool

    /// What this contributor has done to this tree, by kind — or **nil when the implementation could
    /// not prove it counted everything** (ERRATA E38). See `GroveRecord`, which is also where D1 is
    /// argued.
    ///
    /// Optional and defaulted rather than required, so that an implementation with no contribution
    /// store behind it says nothing instead of saying zero. Zero is a claim about a person's history;
    /// nil is the truthful "this read did not answer that". The `Trees` list draws no tally when it
    /// is nil, exactly as screen 08's ring vanishes when `Series.totalCount` is.
    public let record: GroveRecord?

    public init(
        treeID: UUID,
        displayName: String,
        coordinate: Coordinate,
        lastVisitedAt: Date?,
        isFavorite: Bool,
        record: GroveRecord? = nil
    ) {
        self.treeID = treeID
        self.displayName = displayName
        self.coordinate = coordinate
        self.lastVisitedAt = lastVisitedAt
        self.isFavorite = isFavorite
        self.record = record
    }
}

/// A row of `GET /me/journal`.
///
/// Carries no counts of any kind. "No streaks, points, ranks, badges, or public counts of user
/// actions" (D1, ARCHITECTURE §5.1) — recency and identity phrasing only.
public struct JournalEntry: Hashable, Sendable, Identifiable {
    public enum Kind: String, Sendable, Hashable, Codable {
        case visit, observation, measurement, careEvent
    }

    public let id: UUID
    public let kind: Kind
    public let treeID: UUID
    public let treeDisplayName: String
    public let capturedAt: Date
    public let summary: String

    public init(id: UUID, kind: Kind, treeID: UUID, treeDisplayName: String, capturedAt: Date, summary: String) {
        self.id = id
        self.kind = kind
        self.treeID = treeID
        self.treeDisplayName = treeDisplayName
        self.capturedAt = capturedAt
        self.summary = summary
    }
}

/// Cursor pagination, "`?cursor`, `?limit` max 100" (BUILD-PLAN §6).
public struct Page<Element: Sendable>: Sendable {
    public let items: [Element]
    public let nextCursor: String?

    public init(items: [Element], nextCursor: String? = nil) {
        self.items = items
        self.nextCursor = nextCursor
    }

    public static var maximumLimit: Int { 100 }
}

public enum ExportFormat: String, Sendable, CaseIterable {
    case csv
    case geojson
}
