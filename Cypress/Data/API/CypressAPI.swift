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
///   provides through `claimDevice`.
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

    // MARK: - Species

    /// `GET /species/{id}` — the field guide entry.
    func species(id: UUID) async throws -> Species

    /// `GET /species?query=` — autocomplete over both the scientific and the common name.
    func searchSpecies(query: String, limit: Int) async throws -> [Species]

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

    /// `GET /me/outbox-status` — the server's view of recent sync results, for screen 17's
    /// "says why" line.
    func outboxStatus() async throws -> [SyncResult]

    // MARK: - Personal surfaces (private by default, D11)

    /// `GET /me/grove`.
    func grove() async throws -> [GroveEntry]

    /// `GET /me/journal`, cursor-paginated (`?cursor`, `?limit` max 100).
    func journal(cursor: String?, limit: Int) async throws -> Page<JournalEntry>

    /// `POST /devices/claim` — attach an anonymous device's contributions to the signed-in user (D9).
    func claimDevice(deviceUUID: UUID, userID: UUID) async throws

    // MARK: - Reports and export

    /// `POST /reports/hazard-redirect` — logs that a 311 redirect was shown. Analytics only, no
    /// public record. `private_reminders` is a separate write (D4).
    func logHazardRedirect(_ event: HazardRedirectEvent) async throws

    /// `GET /export/latest.csv` / `.geojson` — the nightly export, carrying `verification_state`
    /// (D12, BUILD-PLAN §5).
    func exportLatest(_ format: ExportFormat) async throws -> Data
}

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

    /// **A1, resolved**: "pins cluster at zoom 15 and below; individual pins at zoom 16 and above
    /// (the spec sentence was backwards)" — BUILD-PLAN §11. This constant is the only place that
    /// number appears.
    public static let highestClusteringZoom = 15

    public init(bounds: BoundingBox, zoom: Int, pinLimit: Int = 2_000) {
        self.bounds = bounds
        self.zoom = zoom
        self.pinLimit = pinLimit
    }

    public var shouldCluster: Bool { zoom <= MapViewport.highestClusteringZoom }
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

/// What a viewport resolved to. An enum rather than two optional arrays: at any zoom exactly one of
/// the two is meaningful, and A1 decides which.
public enum MapContent: Hashable, Sendable {
    case clusters([TreeCluster])
    case pins([TreePin])

    public var pinCount: Int {
        switch self {
        case let .pins(pins): return pins.count
        case let .clusters(clusters): return clusters.reduce(0) { $0 + $1.count }
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
    /// Photo timeline, page 1.
    public let photos: [Photo]
    /// The full measurement series. Splitting it into the two never-connected chart series is
    /// `Collection<TreeMeasurement>.splitBySeries(kind:)`'s job (D7).
    public let measurements: [TreeMeasurement]
    public let visits: [Visit]
    public let careEvents: [CareEvent]
    /// Public notes only. Hazard categories cannot appear here — they cannot be stored (D4).
    public let communityNotes: [CommunityNote]
    /// The tree this site replaced, when the site has a lineage (memorial record, screen 19).
    public let siteLineageTreeID: UUID?

    public init(
        tree: Tree,
        activeName: TreeName? = nil,
        species: Species? = nil,
        neighborhoodName: String? = nil,
        latestObservation: TreeObservation? = nil,
        photos: [Photo] = [],
        measurements: [TreeMeasurement] = [],
        visits: [Visit] = [],
        careEvents: [CareEvent] = [],
        communityNotes: [CommunityNote] = [],
        siteLineageTreeID: UUID? = nil
    ) {
        self.tree = tree
        self.activeName = activeName
        self.species = species
        self.neighborhoodName = neighborhoodName
        self.latestObservation = latestObservation
        self.photos = photos
        self.measurements = measurements
        self.visits = visits
        self.careEvents = careEvents
        self.communityNotes = communityNotes
        self.siteLineageTreeID = siteLineageTreeID
    }
}

/// The body of `POST /trees`.
public struct TreeDraft: Hashable, Sendable {
    public let clientUUID: UUID
    public let coordinate: Coordinate
    public let speciesID: UUID?
    /// Required: "Community add: requires photo" (BUILD-PLAN §6).
    public let photoLocalPath: String
    public let attribution: Attribution
    public let address: String?

    public init(
        clientUUID: UUID = UUID(),
        coordinate: Coordinate,
        speciesID: UUID? = nil,
        photoLocalPath: String,
        attribution: Attribution,
        address: String? = nil
    ) {
        self.clientUUID = clientUUID
        self.coordinate = coordinate
        self.speciesID = speciesID
        self.photoLocalPath = photoLocalPath
        self.attribution = attribution
        self.address = address
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

    public init(treeID: UUID, displayName: String, coordinate: Coordinate, lastVisitedAt: Date?, isFavorite: Bool) {
        self.treeID = treeID
        self.displayName = displayName
        self.coordinate = coordinate
        self.lastVisitedAt = lastVisitedAt
        self.isFavorite = isFavorite
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
