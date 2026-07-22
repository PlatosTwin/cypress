import Foundation

/// The Fastify service, when it exists (ARCHITECTURE §4).
///
/// **This type is a stub on purpose and every method throws.** It exists to prove the boundary
/// holds: `RemoteAPI` conforms to exactly the same `CypressAPI` as `LocalAPI`, imports nothing from
/// `Store` or `Outbox`, and holds no database handle. If a method could not be expressed here
/// without reaching for SQLite, the protocol had leaked local storage into the app's vocabulary and
/// would need changing before the server arrived — not after.
///
/// Each method names the BUILD-PLAN §6 endpoint it will call. When the service lands, the bodies
/// become one `URLSession` call each against `\(baseURL)`, decoding `{error: {code, message,
/// retryable}}` into `APIError.Envelope`, which `Core` already knows how to read.
///
/// At that point `LocalAPI` does not go away. It becomes the offline cache behind this: writes go
/// to the outbox first regardless (ARCHITECTURE §4), the drain targets `RemoteAPI`, and reads fall
/// back to the local store when the network is absent.
public struct RemoteAPI: CypressAPI {
    /// `/api/v1`.
    public let baseURL: URL
    /// Injected so the eventual implementation is testable without a live host.
    public let session: URLSession

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    /// Every stub throws this. `server_error` is retryable, so an outbox item that reached the
    /// stub stays alive on the backoff rather than being discarded — which is the correct
    /// behaviour for "the server is not built yet".
    private var unimplemented: APIError { .serverError }

    // MARK: - Map and discovery

    /// Will call `GET /tiles/{z}/{x}/{y}` — or rather, will not: ARCHITECTURE §1 replaces PMTiles
    /// with MapKit, so the viewport is served by a bbox query against `GET /trees`. The tile
    /// endpoint stays a server concern for the public web map.
    public func mapContent(in viewport: MapViewport) async throws -> MapContent {
        throw unimplemented
    }

    /// Will call `GET /trees?near=lng,lat&radius=m`.
    public func treesNear(_ coordinate: Coordinate, radiusM: Double, limit: Int) async throws -> [NearbyTree] {
        throw unimplemented
    }

    /// Will call `GET /trees/{id}`.
    public func treeProfile(id: UUID) async throws -> TreeProfile {
        throw unimplemented
    }

    /// Will call `POST /trees`. Returns `conflict` with the candidate list when the 10 m proximity
    /// dedupe trips, which the client surfaces as `ProximityConflict`.
    public func addTree(_ draft: TreeDraft) async throws -> Tree {
        throw unimplemented
    }

    // MARK: - Species

    /// Will call `GET /species/{id}`.
    public func species(id: UUID) async throws -> Species {
        throw unimplemented
    }

    /// Will call `GET /species?query=`, which has the trigram index on both names that the
    /// on-device prefix scan approximates (see `SpeciesQueries.search`).
    public func searchSpecies(query: String, limit: Int) async throws -> [Species] {
        throw unimplemented
    }

    // MARK: - Almanac

    /// Will call the server's neighbourhood almanac read (screen 12).
    ///
    /// Overrides the protocol's `.empty` default deliberately, exactly as `groveSpecies()` does: an
    /// unbuilt server has no answer, and an empty almanac would draw "nothing is happening in your
    /// neighbourhood" over "we could not ask".
    public func almanac(near coordinate: Coordinate?) async throws -> Almanac {
        throw unimplemented
    }

    // MARK: - Sync

    /// Will call `POST /sync` with the array of outbox items, and decode the per-item
    /// `{client_uuid, status, error}` response. The server dedupes on `client_uuid`.
    public func sync(_ items: [OutboxItem]) async throws -> [SyncResult] {
        throw unimplemented
    }

    /// Will call `POST /photos/begin` and return `{photo_id, presigned_put_url}`.
    public func beginPhotoUpload(_ request: PhotoUploadRequest) async throws -> PhotoUploadTicket {
        throw unimplemented
    }

    /// Will `PUT` the binary to the presigned URL from `beginPhotoUpload`. Not a Fastify route: it
    /// goes straight to storage. A photo record with no arriving binary after 72 h is
    /// garbage-collected server-side.
    public func uploadPhoto(at localPath: String, ticket: PhotoUploadTicket) async throws {
        throw unimplemented
    }

    /// Will call `GET /me/outbox-status`.
    public func outboxStatus() async throws -> [SyncResult] {
        throw unimplemented
    }

    // MARK: - Personal surfaces

    /// Will call `GET /me/grove`.
    public func grove() async throws -> [GroveEntry] {
        throw unimplemented
    }

    /// Will call `GET /me/grove` for the Species tab (screen 08).
    ///
    /// Overrides the protocol's `.empty` default deliberately: an unbuilt server has no answer,
    /// and returning the empty grove would draw a contributor's real collection as a cold start.
    public func groveSpecies() async throws -> GroveSpecies {
        throw unimplemented
    }

    /// Will call `GET /me/journal?cursor=&limit=`.
    public func journal(cursor: String?, limit: Int) async throws -> Page<JournalEntry> {
        throw unimplemented
    }

    /// Will call `POST /devices/claim`.
    public func claimDevice(deviceUUID: UUID, userID: UUID) async throws {
        throw unimplemented
    }

    // MARK: - Reports and export

    /// Will call `POST /reports/hazard-redirect`.
    public func logHazardRedirect(_ event: HazardRedirectEvent) async throws {
        throw unimplemented
    }

    /// Will call the separate `private_reminders` POST (BUILD-PLAN §6). The owner travels in the
    /// body: a reminder written before sign-in is the device's, and the server adopts it at
    /// `POST /devices/claim` exactly as the local store does (D9, ERRATA E23).
    @discardableResult
    public func savePrivateReminder(_ reminder: PrivateReminder) async throws -> SyncResult.Status {
        throw unimplemented
    }

    /// Will call `GET /export/latest.csv` or `GET /export/latest.geojson`.
    public func exportLatest(_ format: ExportFormat) async throws -> Data {
        throw unimplemented
    }
}
