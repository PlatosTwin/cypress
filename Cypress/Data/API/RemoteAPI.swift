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
///
/// ── Why every requirement is written out here, including the ones a default would satisfy ───────
///
/// **Task #76.** This type used to declare 17 of the protocol's 31 requirements and inherit the
/// other 14 from protocol extensions. That compiled, and "it compiles" was the whole of the
/// evidence: ten of the inherited defaults threw `.notFound`, and four *returned a value* — a
/// species guide with no population line, an empty `mapMembership`, `.none` contributions, and an
/// `isFavorite` derived from `grove()`. A conformance that answers a question it never asked is
/// indistinguishable, from the caller's side, from one that answered it correctly.
///
/// Two of those four only happened to be loud: `speciesGuide`'s default calls `species(id:)` and
/// `isFavorite`'s calls `grove()`, both of which this type throws from, so the *default* threw by
/// borrowing a refusal from a neighbouring stub. That is an accident of which methods were written
/// first, and it evaporates the moment `species(id:)` and `grove()` become real — which is step 4 of
/// the #158 plan. The other two, `mapMembership` and `deviceContributions`, answer today.
///
/// So the rule is the one `docs/design-proposals/2026-08-09-task158-live-layer.md` §3.3 states:
/// every method this type is declared to implement, it implements — a refusal is an implementation,
/// an inherited default is not. `CypressTests/APIConformanceGuardTests` is what keeps that true for
/// the thirty-third requirement as well as these thirty-two. `deleteAccount` was the thirty-second,
/// added by #158 §3.2, and the guard is what made adding it a compile-and-fix pass across
/// thirty-four conformances rather than an audit.
public struct RemoteAPI: CypressAPI {
    /// `/api/v1`.
    public let baseURL: URL

    /// **The session-owning type, injected** — spec §3.2: the `/auth/*` routes stay off `CypressAPI`
    /// and belong "to the type that owns the session, injected into `RemoteAPI`".
    ///
    /// Every authenticated call will go through this rather than through `session` below, and the
    /// difference is spec §5.8: it attaches the credential, refreshes once and replays on a 401, and
    /// never lets a session failure reach a caller as `APIError.unauthorized` — which would move an
    /// outbox item to `.failed` immediately and print "Sign in to send this" to somebody who is
    /// signed in (ERRATA **E261** §3).
    public let transport: any AuthorizedTransport

    /// The unauthenticated half of the wire.
    ///
    /// Kept beside `transport` for the one call that must **not** carry a bearer: the photo binary
    /// goes straight to storage at the presigned URL `POST /photos/begin` returns (spec §1.1), and
    /// presenting this service's credential to a storage host sends it somewhere it has no business
    /// being.
    public let session: URLSession

    public init(
        baseURL: URL = SyncService.defaultBaseURL,
        transport: any AuthorizedTransport,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.transport = transport
        self.session = session
    }

    /// Every stub throws this. `server_error` is retryable, so an outbox item that reached the
    /// stub stays alive on the backoff rather than being discarded — which is the correct
    /// behavior for "the server is not built yet".
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

    /// Will call `POST /trees/{id}/species-assertions`' first-claim arm. Overrides the
    /// `SpeciesClaim.swift` default, whose `.notFound` would say "there is no such tree" about a
    /// tree the server has never been asked for.
    public func claimSpecies(treeID: UUID, speciesID: UUID) async throws -> Tree {
        throw unimplemented
    }

    /// Will call `POST /trees/{id}/species-assertions` (BUILD-PLAN §6). Overrides the
    /// `SpeciesClaim.swift` default for `claimSpecies`' reason.
    public func correctSpecies(treeID: UUID, speciesID: UUID) async throws -> Tree {
        throw unimplemented
    }

    /// Will raise a `wrong_species` review flag server-side.
    public func flagWrongSpecies(treeID: UUID) async throws {
        throw unimplemented
    }

    /// Will close a species report server-side.
    public func dismissSpeciesReview(flagID: UUID) async throws {
        throw unimplemented
    }

    // MARK: - The record itself

    /// Will raise a `never_existed` review flag server-side.
    public func flagNeverExisted(treeID: UUID) async throws {
        throw unimplemented
    }

    /// Will withdraw the record server-side, on a lead's authority.
    public func withdrawRecord(flagID: UUID) async throws {
        throw unimplemented
    }

    /// Will close a `never_existed` report server-side, leaving the record where it is.
    public func dismissRecordReview(flagID: UUID) async throws {
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

    /// Will call `GET /species/{id}` with the caller's fix, so the server can count the inventory
    /// around it.
    ///
    /// **Overrides `SpeciesGuide.swift`'s default, which is the sharpest of the four #76 cases.**
    /// That default returns `SpeciesGuide(species: try await species(id: id))` — the entry with no
    /// population facts attached — and screen 07 draws exactly that: a guide with no population
    /// line, which is what it also draws for a species genuinely absent from the inventory. It
    /// happens to throw here today only because `species(id:)` above throws; once step 4 of #158
    /// makes `species(id:)` real, the inherited default would start rendering a truthful-looking
    /// guide with the nearby half silently missing.
    public func speciesGuide(id: UUID, near coordinate: Coordinate?) async throws -> SpeciesGuide {
        throw unimplemented
    }

    // MARK: - Almanac

    /// Will call the server's neighborhood almanac read (screen 12).
    ///
    /// Overrides the protocol's `.empty` default deliberately, exactly as `groveSpecies()` does: an
    /// unbuilt server has no answer, and an empty almanac would draw "nothing is happening in your
    /// neighborhood" over "we could not ask".
    public func almanac(near coordinate: Coordinate?) async throws -> Almanac {
        throw unimplemented
    }

    // MARK: - City

    /// Will call the server's city read. Overrides the protocol's `.empty` default for the same
    /// reason `almanac(near:)` does: an unbuilt server has no answer, which is a different fact from
    /// a city with nothing to report.
    public func city(near coordinate: Coordinate?) async throws -> CityAlmanac {
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

    /// Will call `GET /photos/{id}`. Overrides `PhotoAccess.swift`'s `.notFound` default, which
    /// tells a reader the photograph does not exist when the truth is that nothing was asked.
    /// ERRATA **E125** is the same sentence from the other direction.
    public func photoData(id: UUID) async throws -> Data {
        throw unimplemented
    }

    /// Will `POST` the thumb. Overrides `PhotoAccess.swift`'s `.notFound` default for `photoData`'s
    /// reason.
    public func setPhotoVote(photoID: UUID, vote: PhotoVote?) async throws {
        throw unimplemented
    }

    /// Will call `DELETE /photos/{id}` when the service lands (see the protocol's note on the
    /// method). Overrides `PhotoAccess.swift`'s `.notFound` default.
    public func deletePhoto(id: UUID) async throws -> PhotoDeletion {
        throw unimplemented
    }

    // MARK: - Personal surfaces

    /// Will call `GET /me/grove`.
    public func grove() async throws -> [GroveEntry] {
        throw unimplemented
    }

    /// Will call `GET /me/grove` narrowed to one tree (#167).
    ///
    /// **Overrides the grove-derived default in `CypressAPI.swift`.** That default is correct for
    /// any conformance whose `grove()` tells the truth — and this one's throws, so today the
    /// default refuses by borrowing this type's own refusal one call down. That is an accident of
    /// ordering, not a design: the day `grove()` becomes the real `GET /me/grove`, an inherited
    /// `isFavorite` would quietly become the whole-list read #167 exists to stop screen 03's heart
    /// making after every write.
    public func isFavorite(treeID: UUID) async throws -> Bool {
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

    /// Will call `DELETE /me`, carrying the `AccountDeletionChoice` and the client's still-queued
    /// `client_uuid`s so the server can tombstone work that has not arrived yet.
    ///
    /// **A refusal and not an empty `Outcome`**, which is the whole reason this is a requirement
    /// rather than a defaulted extension member (§3.2, §3.3): an implementation that returned
    /// `AccountDeletion.Outcome()` would report a deletion it did not perform, and every counter on
    /// the confirmation would read zero for a reason the screen cannot tell from "there was nothing
    /// to delete".
    public func deleteAccount(_ choice: AccountDeletionChoice) async throws -> AccountDeletion.Outcome {
        throw unimplemented
    }

    /// Will not call anything. What a device is holding unattributed is a local fact by definition —
    /// the rows have not been sent — so the offline cache answers it and the server never does.
    /// This is the #158 spec's **Class D**, the one method on the protocol that is device-only.
    ///
    /// So the body is the same `.none` the extension in `DeviceContributions.swift` supplies, and
    /// the difference between this and inheriting it is the entire point of task #76: the answer is
    /// **written down here, with the reason beside it**, rather than arrived at by a conformance
    /// having nothing to say. §3.3 of the spec: "the method's honest remote implementation *is* the
    /// inherited local answer, and §3.3 is why that has to be said out loud rather than left as an
    /// accident."
    ///
    /// Read the `.none` as "this transport is not where a device's own unsent rows live", not as
    /// "this device has contributed nothing" — which is why it is `.none` and not a throw: a throw
    /// would put an error on screen 15 for a question that was answered correctly. When `LocalAPI`
    /// becomes the cache behind this, it is the one that keeps answering it.
    public func deviceContributions() async throws -> DeviceContributions {
        .none
    }

    /// Will call the server's membership read for the `Yours` and `Favorites` chips (#116).
    ///
    /// **Overrides `MapMembership.swift`'s empty-set default, which is the second of the four #76
    /// cases that answers rather than refuses** — and, unlike `speciesGuide` and `isFavorite`, it
    /// answers today without borrowing anything: an empty `Set<UUID>` reaches `MapModel` as a
    /// narrowing that matched nothing, and screen 01 draws a map on which this reader owns and
    /// hearts no tree in the city. Nothing throws and nothing logs.
    public func mapMembership(_ kind: MapMembership) async throws -> Set<UUID> {
        throw unimplemented
    }

    // MARK: - Reports and export

    /// Will call `POST /reports/hazard-redirect`.
    public func logHazardRedirect(_ event: HazardRedirectEvent) async throws {
        throw unimplemented
    }

    /// Will call `GET /export/latest.csv` or `GET /export/latest.geojson`.
    public func exportLatest(_ format: ExportFormat) async throws -> Data {
        throw unimplemented
    }
}
