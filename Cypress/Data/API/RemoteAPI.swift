import Foundation

/// The `cypress-sync` service (RULINGS **R72**, `server/README.md`), as `CypressAPI`.
///
/// ── What this type is now, and what it was ─────────────────────────────────────────────────────
///
/// It was a stub whose every method threw, and whose job was to prove the boundary held: `RemoteAPI`
/// conforms to exactly the same `CypressAPI` as `LocalAPI`, imports nothing from `Store` or
/// `Outbox`, and holds no database handle. That is still true and is still the reason the file is
/// shaped this way. What changed is that the service exists, so the methods it has a route for make
/// the call.
///
/// ── The finding that shapes this file, checked against the built service ───────────────────────
///
/// **The brief for this round said "implement the 32 method bodies", and 32 network calls is not
/// what the service can support.** The routes were read out of `server/internal/api/server.go` —
/// the router, not the documentation — and there are eighteen of them. Three facts follow, and each
/// one is a `RemoteSurface` case rather than an invented endpoint:
///
/// 1. **There is no city-layer route at all, on purpose.** `server/README.md`'s own "What this
///    service is not" says it: "The city layer — the map's pan loop, species, the almanac — is
///    answered on the phone from the installed city file and never reaches here." So `mapContent`,
///    `treesNear`, `species`, `searchSpecies`, `speciesGuide`, `almanac` and `city` have nothing to
///    call. A body that `GET`s `/species/{id}` would take Go's `http.ServeMux` 404 — which is not
///    even an `{error: …}` envelope — and dress it as a species that is not there.
///    **This contradicts spec §3.1's "the remote implementation exists, is tested, and is not on
///    the hot path" for Class L**, and the contradiction is recorded in
///    this round's errata entry rather than papered over here.
///
/// 2. **Nine of the eleven mutations spec §3.4 names have no route either.** §3.4 counts "eleven
///    mutating methods… called **directly** by feature models with no queue behind them", of which
///    nine have a shipping caller in `Cypress/Features`. The eleven are `addTree`, `claimSpecies`,
///    `correctSpecies`, `flagWrongSpecies`, `dismissSpeciesReview`, `flagNeverExisted`,
///    `withdrawRecord`, `dismissRecordReview`, `setPhotoVote`, `deletePhoto` and
///    `logHazardRedirect`. **Two of them have a route** — `addTree` (`POST /trees`) and
///    `deletePhoto` (`DELETE /photos/{id}`) — which leaves nine with none, and that nine is exactly
///    the set `RemoteAPITests.theUnqueuedMutationsRefuse` pins. §3.4's conclusion is unchanged
///    either way: they "stay Class L until they are queued", which needs a widened `outbox.kind`
///    `CHECK` and therefore its own ticket and its own migration author, and the service was built
///    to match.
///
///    **Of the two that do have a route, only `addTree` returns what its signature promises.**
///    `deletePhoto` refuses: `DELETE /photos/{id}` answers `{"deleted": true}` and none of
///    `PhotoDeletion`'s five facts, so it is a half like the four in (3) below. The route is reached
///    through the `deletePhotoRemotely(id:)` delta accessor instead. See both methods below.
///
/// 3. **Four reads answer the community half and the whole client type needs the city file.**
///    `GET /me/grove` sends no display name and no coordinate; `GET /me/grove/species` sends no
///    species names; `GET /trees/{id}` sends no `Tree`. Each is deliberate and `reads.go` argues it
///    in the same words R36 does. So those four conformance methods refuse, the **delta accessors**
///    below make the call, and `RoutedAPI` is what joins the two halves into the protocol's type.
///    Returning a `GroveEntry` with an empty name at Null Island would be the §3.3 hazard exactly:
///    a conformance answering a question it never asked.
///
/// ── Why the refusals are `RemoteSurface` and not `APIError` ────────────────────────────────────
///
/// See `RemoteSurface`. In one line: every code in the taxonomy is a statement about the *record*,
/// and none of these is about a record.
///
/// ── Why every requirement is still written out, including the ones a default would satisfy ─────
///
/// **Task #76.** This type used to declare 17 of the protocol's requirements and inherit the rest
/// from protocol extensions. That compiled, and "it compiles" was the whole of the evidence: ten of
/// the inherited defaults threw `.notFound`, and four *returned a value* — a species guide with no
/// population line, an empty `mapMembership`, `.none` contributions, and an `isFavorite` derived
/// from `grove()`. A conformance that answers a question it never asked is indistinguishable, from
/// the caller's side, from one that answered it correctly. `CypressTests/APIConformanceGuardTests`
/// is what keeps every requirement declared here; spec §3.3 is the rule it enforces — "a refusal is
/// an implementation, an inherited default is not".
public struct RemoteAPI: CypressAPI {
    /// `/api/v1`.
    public let baseURL: URL

    /// **The session-owning type, injected** — spec §3.2: the `/auth/*` routes stay off `CypressAPI`
    /// and belong "to the type that owns the session, injected into `RemoteAPI`".
    ///
    /// Every authenticated call goes through this rather than through `session` below, and the
    /// difference is spec §5.8: it attaches the credential, refreshes once and replays on a 401, and
    /// never lets a session failure reach a caller as `APIError.unauthorized` — which would move an
    /// outbox item to `.failed` immediately, on a session that only needed refreshing (ERRATA
    /// **E261** §3). This line used to name the sentence that row would print, "Sign in to send
    /// this"; since the owner's ruling 1 of 2026-08-14 it reads "This couldn't be sent." instead.
    ///
    /// **There is no second retry layer in this file.** Refresh-and-replay lives there, once.
    public let transport: any AuthorizedTransport

    /// The unauthenticated half of the wire.
    ///
    /// Kept beside `transport` for the two calls that must **not** carry a bearer: the photo binary
    /// goes straight to storage at the presigned URL `POST /photos/begin` returns, and comes back
    /// from the presigned URL `GET /photos/{id}` returns (spec §1.1). Presenting this service's
    /// credential to a storage host sends it somewhere it has no business being.
    public let session: URLSession

    /// What is still in this device's outbox, for `DELETE /me`.
    ///
    /// **Injected, and nil by default, because the honest alternative is a lie.** `me.go` tombstones
    /// the keys still queued at the moment of deletion, "even though this service has never seen
    /// them", so that an item queued on Tuesday against an account deleted on Wednesday cannot
    /// resurrect it on Thursday. `RemoteAPI` holds no queue — it holds no store of any kind, which
    /// is the property that made it a boundary proof in the first place — so with no provider it
    /// **refuses** rather than sending an empty array, because an empty array is the claim that
    /// nothing is queued and R3's stated failure mode is deleting differently from what was asked.
    ///
    /// The composition root is what has both, and **it fills this** — `DataLayer.boot` passes a
    /// provider that reads the outbox table.
    ///
    /// This line used to end "wiring it is the account step (spec §10 step 5), not this one", and
    /// that sentence outlived the round it described: step 5 landed, the seam was filled, and
    /// `RoutedAPI.deleteAccount` went on routing local anyway — so `DELETE /me` had a working
    /// implementation and no shipping caller. ERRATA **E272** recorded the gap; the owner's ruling
    /// of 2026-08-23 closed it by pointing the router at this method. The default stays nil, because
    /// a `RemoteAPI` built without a queue behind it still must not claim that nothing is queued.
    public let pendingOutboxKeys: (@Sendable () async throws -> [UUID])?

    public init(
        baseURL: URL = SyncService.defaultBaseURL,
        transport: any AuthorizedTransport,
        session: URLSession = .shared,
        pendingOutboxKeys: (@Sendable () async throws -> [UUID])? = nil
    ) {
        self.baseURL = baseURL
        self.transport = transport
        self.session = session
        self.pendingOutboxKeys = pendingOutboxKeys
    }

    // MARK: - Map and discovery

    /// **Class L, no route.** ARCHITECTURE §1 replaces PMTiles with MapKit, so the viewport would be
    /// a bbox query rather than `GET /tiles/{z}/{x}/{y}` — and there is no bbox route either,
    /// because R36 keeps the pan loop on the phone and two performance campaigns bought it there
    /// (spec §4.1). `RoutedAPI` answers this from the installed city file and never asks here.
    public func mapContent(in viewport: MapViewport) async throws -> MapContent {
        throw RemoteSurface.cityLayerIsAnsweredLocally
    }

    /// **Class L, no route.** `GET /trees?near=` is not on this service; the shortlist is a query
    /// over the installed inventory. §4.2: a live query returns a row exactly as old as a published
    /// file.
    public func treesNear(_ coordinate: Coordinate, radiusM: Double, limit: Int) async throws -> [NearbyTree] {
        throw RemoteSurface.cityLayerIsAnsweredLocally
    }

    /// **Community half only.** `GET /trees/{id}` answers photographs, own/deletable sets and a
    /// visit count, and carries no `Tree` at all — `reads.go` says why in R36's own terms. A
    /// `TreeProfile` needs the tree, so this refuses and `treeCommunityHalf(id:)` below is what the
    /// router calls.
    ///
    /// **This is the R-required read of spec §3.1** and the acceptance criterion's last mile: "the
    /// photo propagates to all other users" *is* this payload carrying a photograph the reading
    /// device never wrote. The join is in `RoutedAPI.treeProfile(id:)`; the refusal here is what
    /// stops a half-answer being drawn as the tree.
    public func treeProfile(id: UUID) async throws -> TreeProfile {
        throw RemoteSurface.communityHalfOnly
    }

    /// `POST /trees` — community add, with the 10 m proximity dedupe.
    ///
    /// ── The candidate list does not survive the transport seam, and that is a real loss ────────
    ///
    /// `LocalAPI` throws `ProximityConflict` carrying the candidates, because the candidates are the
    /// whole point of the refusal — "a `conflict` with nothing in it is a dead end wearing the same
    /// code" (`sync.go`). The service sends them, as a sibling of `error` rather than inside it,
    /// because `APIError.Envelope`'s nested container decodes exactly `code`, `message` and
    /// `retryable`. **They are dropped one layer below this one**: `AuthorizedTransport.send` hands
    /// back a 2xx body or throws the taxonomy code, so by the time a `conflict` reaches here the
    /// body that carried `detail.candidates` is gone.
    ///
    /// This throws the bare `.conflict` rather than a `ProximityConflict` with an empty list, which
    /// would be the dead end wearing the right type as well as the right code. Re-sending the draft
    /// to read the body a second time is **not** the fix and is not done: it would need the bearer,
    /// which only `transport` holds, and asking the seam for the error body is a change to the
    /// session layer that every other caller of it would then have to understand. It is written up
    /// in this round's errata entry as work for the round that wires this method,
    /// and it costs nothing today because §3.4 keeps `addTree` routed local, where the candidates
    /// are produced from the installed inventory.
    ///
    /// **The returned `Tree` is this client's own echo of the draft it just sent.** The service
    /// answers `{id, status}` and nothing else, so every other column comes from the `TreeDraft` —
    /// which is the authority for all of them — plus the three values `candidateFrom` in `sync.go`
    /// fixes for every row of this table: community source, unverified, alive. The two timestamps
    /// are this device's clock and not the row's, which is the one place this value differs from a
    /// re-read; it is stated here rather than left to be discovered.
    public func addTree(_ draft: TreeDraft) async throws -> Tree {
        guard !draft.photoLocalPath.isEmpty else { throw APIError.validationFailed }

        let body = AddTreeBody(
            clientUUID: draft.clientUUID,
            lat: draft.coordinate.latitude,
            lon: draft.coordinate.longitude,
            address: draft.address,
            placement: draft.placement.rawValue,
            speciesID: draft.speciesID,
            landContext: draft.landContext?.rawValue
        )

        let data = try await transport.send(try request("trees", method: "POST", body: body))
        let response = try decode(AddTreeResponse.self, from: data)
        return Tree(
            id: response.id,
            source: .community,
            coordinate: draft.coordinate,
            address: draft.address,
            status: .alive,
            speciesCurrentID: draft.speciesID,
            verificationState: .unverified,
            placement: draft.placement,
            statedLandContext: draft.landContext
        )
    }

    /// **No route.** A first species claim is one of spec §3.4's nine, and §3.4 rules them Class L
    /// "until they are queued" — which is a widened `outbox.kind` `CHECK`, its own ticket and its
    /// own migration author. The service was built to match and exposes nothing to call.
    ///
    /// Overrides `SpeciesClaim.swift`'s `.notFound` default, whose sentence would be "there is no
    /// such tree" about a tree nothing was asked about.
    public func claimSpecies(treeID: UUID, speciesID: UUID) async throws -> Tree {
        throw RemoteSurface.noRouteOnThisService
    }

    /// **No route** — see `claimSpecies`. Overrides `SpeciesClaim.swift`'s default for its reason.
    public func correctSpecies(treeID: UUID, speciesID: UUID) async throws -> Tree {
        throw RemoteSurface.noRouteOnThisService
    }

    /// **No route** — see `claimSpecies`.
    public func flagWrongSpecies(treeID: UUID) async throws {
        throw RemoteSurface.noRouteOnThisService
    }

    /// **No route** — see `claimSpecies`. The review dismissals are behind moderation, which
    /// ARCHITECTURE §8 makes a web deliverable; this service's only operator surface is the photo
    /// takedown.
    public func dismissSpeciesReview(flagID: UUID) async throws {
        throw RemoteSurface.noRouteOnThisService
    }

    // MARK: - The record itself

    /// **No route** — see `claimSpecies`.
    public func flagNeverExisted(treeID: UUID) async throws {
        throw RemoteSurface.noRouteOnThisService
    }

    /// **No route** — see `dismissSpeciesReview`. A lead's authority is a moderation surface.
    public func withdrawRecord(flagID: UUID) async throws {
        throw RemoteSurface.noRouteOnThisService
    }

    /// **No route** — see `dismissSpeciesReview`.
    public func dismissRecordReview(flagID: UUID) async throws {
        throw RemoteSurface.noRouteOnThisService
    }

    // MARK: - Species

    /// **Class L, no route.** The field-guide entry is in the installed city file.
    public func species(id: UUID) async throws -> Species {
        throw RemoteSurface.cityLayerIsAnsweredLocally
    }

    /// **Class L, no route.** The trigram index BUILD-PLAN §6 describes is a server that was not
    /// built; `SpeciesQueries.search` is what answers this, on device.
    public func searchSpecies(query: String, limit: Int) async throws -> [Species] {
        throw RemoteSurface.cityLayerIsAnsweredLocally
    }

    /// **Class L, no route.** §4.2 is explicit that this gains nothing from a live query: it is an
    /// aggregate over the *installed* inventory, and under D16 that is a property of which cities
    /// are installed — which the service does not know.
    ///
    /// Overrides `SpeciesGuide.swift`'s default, which is the sharpest of the four #76 cases: it
    /// returns the entry with no population facts attached, which screen 07 draws identically to a
    /// species genuinely absent from the inventory.
    public func speciesGuide(id: UUID, near coordinate: Coordinate?) async throws -> SpeciesGuide {
        throw RemoteSurface.cityLayerIsAnsweredLocally
    }

    // MARK: - Almanac

    /// **Class L, no route.** §4.2 records that the almanac straddles — its city aggregates gain
    /// nothing and its first-bloom sightings are community observations — and rules it "routed L
    /// with its community half arriving from the same delta that feeds `treeProfile`". That delta
    /// route does not exist on this service, so there is nothing here to call yet.
    ///
    /// Overrides the protocol's `.empty` default deliberately: an empty almanac draws "nothing is
    /// happening in your neighborhood" over "we could not ask".
    public func almanac(near coordinate: Coordinate?, in area: AreaSelection) async throws -> Almanac {
        throw RemoteSurface.cityLayerIsAnsweredLocally
    }

    /// **Class L, no route**, and the override matters here more than most: the protocol's default
    /// is `AreaChoices.none`, and an empty picker list is an *answer* — it draws no picker at all,
    /// which reads as "this record has nothing to offer" rather than "nobody asked". That is the
    /// distinction this whole file's guard (`APIConformanceGuardTests`) exists to keep.
    public func areaChoices() async throws -> AreaChoices {
        throw RemoteSurface.cityLayerIsAnsweredLocally
    }

    // MARK: - City

    /// **Class L, no route** — §4.2 puts this beside `speciesGuide`: an aggregate over the installed
    /// inventory, which under D16 the service cannot know. Overrides the protocol's `.empty` default
    /// for `almanac`'s reason.
    public func city(near coordinate: Coordinate?, in city: CitySelection) async throws -> CityAlmanac {
        throw RemoteSurface.cityLayerIsAnsweredLocally
    }

    // MARK: - Sync

    /// `POST /sync` — the batch, with one verdict per item.
    ///
    /// **A verdict for every item, matched on `client_uuid`, and never a batch-wide failure that the
    /// service answered.** `OutboxRetryPolicy.nextState` reads each item's own code, and the service
    /// is written to the same contract: it decodes items one at a time so that one unrecognized
    /// field cannot fail a queue terminally. An item this response does not name is reported here as
    /// `.failed` with `.serverError` — retryable, so it stays alive — rather than being dropped,
    /// which would settle a row nothing decided.
    ///
    /// `duplicate` is a success (`SyncResult.isSuccess`), which is what lets a batch be replayed
    /// after a flap without creating a second visit.
    public func sync(_ items: [OutboxItem]) async throws -> [SyncResult] {
        guard !items.isEmpty else { return [] }

        let bodies = try items.map { item -> SyncItemBody in
            let payload = try OutboxPayload.decode(kind: item.kind, from: item.payload)
            return SyncItemBody(
                clientUUID: item.clientUUID,
                kind: item.kind.rawValue,
                treeUUID: payload.treeID,
                occurredAt: payload.occurredAt,
                payload: try JSONValue.parse(item.payload),
                userID: payload.ownerUserID,
                deviceID: payload.ownerDeviceID,
                isFavorite: payload.isFavorite
            )
        }

        let data = try await transport.send(
            try request("sync", method: "POST", body: SyncRequestBody(items: bodies))
        )
        let response = try decode(SyncResultsResponse.self, from: data)
        let verdicts = Dictionary(response.results.map { ($0.clientUUID, $0) }, uniquingKeysWith: { first, _ in first })

        return items.map { item in
            guard let verdict = verdicts[item.clientUUID] else {
                return SyncResult(clientUUID: item.clientUUID, status: .failed, error: .serverError)
            }
            return SyncResult(clientUUID: verdict.clientUUID, status: verdict.status, error: verdict.error)
        }
    }

    /// `POST /photos/begin` — reserves the photo id and returns the presigned `PUT` (spec §1.1
    /// step 3).
    ///
    /// `moderation_state` and `approval_reason` also come back and are deliberately not read: the
    /// service returns them so the upload's own log says which rule published the photograph, and
    /// `Photo.isPubliclyVisible` is evaluated at render time from the row rather than from this
    /// answer.
    public func beginPhotoUpload(_ request: PhotoUploadRequest) async throws -> PhotoUploadTicket {
        let body = BeginPhotoBody(
            treeUUID: request.treeID,
            visitClientUUID: request.visitID,
            shotType: request.shotType.rawValue,
            capturedAt: request.capturedAt,
            width: request.width,
            height: request.height,
            // Nil by every path that ships, and ERRATA **E42** is why: the tree's own pin is already
            // exact and public, so a photo location adds nothing a public surface needs and does add
            // a second, independent record of where the contributor was standing.
            publicLat: request.publicCoordinate?.latitude,
            publicLon: request.publicCoordinate?.longitude,
            // The binary's own id, so a begin retried after a flap finds the row it already made
            // instead of making a second photograph (ERRATA E264).
            clientUUID: request.idempotencyKey
        )
        let data = try await transport.send(try self.request("photos/begin", method: "POST", body: body))
        let response = try decode(BeginPhotoResponse.self, from: data)
        return PhotoUploadTicket(photoID: response.photoID, destination: response.presignedPutURL)
    }

    /// `PUT`s the binary **straight to storage** at the presigned destination (spec §1.1 step 4),
    /// then closes the 72 h grace window with `POST /photos/{id}/received`.
    ///
    /// ── Two things about this call that are not incidental ─────────────────────────────────────
    ///
    /// **It carries no bearer.** The destination is a presigned URL on the storage host, and the
    /// signature *is* the authorization; attaching this service's credential would send it to a
    /// third party that has no business holding it. That is the whole reason `session` exists beside
    /// `transport` on this type.
    ///
    /// **The receipt is a separate, authorized call, and it comes second.** A photo record whose
    /// binary never arrives is garbage-collected after 72 h (`PhotoUploadTicket.binaryGracePeriod`),
    /// so marking it received before the bytes landed would keep a record alive with nothing behind
    /// it. If the `PUT` succeeds and the receipt fails, the row is collected and the photograph is
    /// lost rather than silently half-published — which is the safe direction, and the reason the
    /// receipt failure is thrown rather than swallowed.
    ///
    /// This is transport, not wiring: `OutboxQueue`'s send sink does not carry a photo method at
    /// all, deliberately (`OutboxSendSink`), and nothing in this round puts this on a drain.
    public func uploadPhoto(at localPath: String, ticket: PhotoUploadTicket) async throws {
        let binary: Data
        do {
            binary = try Data(contentsOf: URL(fileURLWithPath: localPath))
        } catch {
            // The staged file is this device's own. A missing one is not something the service did,
            // and `validationFailed` would fail an outbox item terminally over a local condition.
            throw SessionError.malformedResponse
        }

        var put = URLRequest(url: ticket.destination)
        put.httpMethod = "PUT"
        put.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        put.httpBody = binary

        let (_, response) = try await session.send(put)
        guard (200...299).contains(response.statusCode) else {
            // Storage answers in its own vocabulary — S3-style XML, not this service's envelope —
            // so there is no taxonomy code to read out of it. `serverError` is retryable, which is
            // the correct reading of a storage host refusing a presigned write: the signature
            // expires in thirty minutes and the next attempt mints a fresh one.
            throw APIError.serverError
        }

        _ = try await transport.send(
            try request("photos/\(ticket.photoID.uuidString)/received", method: "POST")
        )
    }

    /// `GET /photos/{id}`, then the bytes from the presigned source it names.
    ///
    /// **Two round trips, and the service's own comment argues the shape**: a 256 MB machine that
    /// streamed every photograph on every profile read is the one way it falls over under success,
    /// so it answers a presigned `GET` URL and the client fetches. The second fetch is
    /// unauthenticated for `uploadPhoto`'s reason — the signature is the authorization.
    ///
    /// **This is the R-required grade** (spec §3.1): the bytes of a photograph this device never
    /// wrote. Overrides `PhotoAccess.swift`'s `.notFound` default, which tells a reader the
    /// photograph does not exist when the truth is that nothing was asked (ERRATA **E125**).
    public func photoData(id: UUID) async throws -> Data {
        let data = try await transport.send(try request("photos/\(id.uuidString)", method: "GET"))
        let source = try decode(PhotoSourceResponse.self, from: data)

        let (bytes, response) = try await session.send(URLRequest(url: source.url))
        guard (200...299).contains(response.statusCode) else { throw APIError.serverError }
        guard !bytes.isEmpty else {
            // A zero-byte JPEG is a corrupt photograph, and the caller decides nothing by decoding
            // one. `PhotoAccess.swift` refuses to hand back empty `Data` for the same reason.
            throw SessionError.malformedResponse
        }
        return bytes
    }

    /// **No route.** A photo vote is one of spec §3.4's nine — see `claimSpecies` — and the service
    /// exposes no vote endpoint: `photos.go` says the vote "is a ranking signal rather than a
    /// report", and the moderation surface it would feed is a web deliverable (ARCHITECTURE §8).
    ///
    /// Overrides `PhotoAccess.swift`'s `.notFound` default, which says the photograph is not there.
    public func setPhotoVote(photoID: UUID, vote: PhotoVote?) async throws {
        throw RemoteSurface.noRouteOnThisService
    }

    /// **A route exists and the answer is still a half.** `DELETE /photos/{id}` returns
    /// `{deleted: true}`; `PhotoDeletion` carries the tree the photograph was on and four counts,
    /// and the service sends none of them.
    ///
    /// Those numbers are not decoration — `PhotoDeletion`'s own header says every one of them "is a
    /// claim the app makes to a person about something irreversible", and `removedFiles` in
    /// particular is the assertion a green "the call did not throw" cannot make. Returning zeros
    /// beside a `treeID` this client would have to invent is exactly the shape §3.3 forbids. So the
    /// conformance refuses, `deletePhotoRemotely(id:)` below performs the deletion for a caller that
    /// wants the act rather than the report, and the local half keeps owning the numbers.
    public func deletePhoto(id: UUID) async throws -> PhotoDeletion {
        throw RemoteSurface.communityHalfOnly
    }

    // MARK: - Personal surfaces

    /// **Community half only.** `GET /me/grove` sends `tree_uuid`, the favorite bit, the last visit,
    /// the `GroveRecord` and the hero photo — and no display name and no coordinate, because both
    /// are city-inventory facts. `GroveEntry` requires both, and a coordinate is not optional.
    ///
    /// `groveDelta()` is what the router calls; `RoutedAPI.refreshedGrove()` is where the halves
    /// meet — `grove()` itself is the local-first paint and never reaches this route.
    public func grove() async throws -> [GroveEntry] {
        throw RemoteSurface.communityHalfOnly
    }

    /// **Community half only, for `grove()`'s reason**, which is why this refuses rather than
    /// paging: the service's `GET /me/grove` carries no display name and no coordinate, so there is
    /// no `GroveEntry` to cut into pages here at all. The paged read screen 08 runs is the phone's
    /// (`LocalAPI.grovePage`), routed straight through by `RoutedAPI`.
    ///
    /// Declared rather than left to the protocol's default, which would call `grove()` above and
    /// arrive at the same refusal by a longer road — every shipping conformance answers every
    /// requirement in its own body (ERRATA E125, `APIConformanceGuardTests`).
    public func grovePage(cursor: String?, limit: Int) async throws -> Page<GroveEntry> {
        throw RemoteSurface.communityHalfOnly
    }

    /// `GET /me/grove/{treeID}/favorite` — the whole answer, in one bit (#167).
    ///
    /// **One of exactly two reads whose remote answer is complete on its own**, the other being
    /// `mapMembership`. That is what makes them the clean Class R wins: nothing about a favorite
    /// needs the city file.
    ///
    /// Overrides the grove-derived default in `CypressAPI.swift`, which is the whole-list read #167
    /// exists to stop screen 03's heart making after every write.
    public func isFavorite(treeID: UUID) async throws -> Bool {
        let data = try await transport.send(
            try request("me/grove/\(treeID.uuidString)/favorite", method: "GET")
        )
        return try decode(IsFavoriteResponse.self, from: data).isFavorite
    }

    /// **Community half only.** `GET /me/grove/species` sends species ids and first-met dates.
    /// `KnownSpecies` carries a scientific name, a common name and the address of the first
    /// meeting, and `GroveSpecies.neighborhood` carries the ring's denominator — which `reads.go`
    /// declines to answer in R36's own words, because it is a fact about the city's inventory.
    ///
    /// Overrides the protocol's `.empty` default: an empty grove would draw a contributor's real
    /// collection as a cold start.
    public func groveSpecies() async throws -> GroveSpecies {
        throw RemoteSurface.communityHalfOnly
    }

    /// **Community half only, and this one cannot be joined by the router either.**
    ///
    /// `GET /me/journal` sends `{client_uuid, kind, tree_uuid, occurred_at, payload}`.
    /// `JournalEntry` needs a `treeDisplayName` — a city-layer fact the router can resolve — and a
    /// `summary`, which it cannot: the summary is built by the `UNION ALL` in
    /// `ContributionStore.journal`, out of columns of the local tables, and reconstructing it here
    /// from the raw mutation would be a **second implementation of the same sentence** in a second
    /// language. Two places for one fact is how the sentences drift.
    ///
    /// So `RoutedAPI` routes the journal local for now and says so, and the finding is written down
    /// in this round's errata entry rather than fixed by inventing prose the
    /// service did not send (DECISIONS constraint 15).
    public func journal(cursor: String?, limit: Int) async throws -> Page<JournalEntry> {
        throw RemoteSurface.communityHalfOnly
    }

    /// `POST /devices/claim` — the idempotent sweep that re-homes a device's unattributed rows onto
    /// an account (D9).
    public func claimDevice(deviceUUID: UUID, userID: UUID) async throws {
        _ = try await transport.send(
            try request("devices/claim", method: "POST", body: ClaimDeviceBody(deviceUUID: deviceUUID, userID: userID))
        )
    }

    /// `DELETE /me` — deletion in the two-part sense RULINGS **R3** settles.
    ///
    /// Carries the choice, which has **no server default on purpose** (`me.go`: "A server that
    /// picked a door would be overriding the one control the person was given"), and the client's
    /// still-queued `client_uuid`s so the service can tombstone work that has not arrived yet.
    ///
    /// ── What the returned `Outcome` may say, and what it may not ───────────────────────────────
    ///
    /// The service reports three counters — contributions, photos, tombstones — against `Outcome`'s
    /// twenty. **Only the fields those three actually name are filled**, and which ones they are
    /// depends on the door: under `leaveRecords` the rows were anonymized, under `eraseEverything`
    /// they were deleted, and writing a count into the wrong pair would tell somebody their records
    /// were destroyed when they were kept. Everything else stays zero, which is the same "an
    /// unproven read says nothing" rule `GroveEntry.record` states as an optional.
    ///
    /// `tombstones` has no field on `Outcome` at all — it counts marks the *service* wrote, over
    /// keys that are still in this device's queue — so it is deliberately not mapped onto
    /// `discardedOutboxItems`, which counts what the local half discarded. Two different acts.
    ///
    /// ── The one arm where a throw does not mean "not deleted" ──────────────────────────────────
    ///
    /// The response is decoded **after** the request succeeded, so a decode failure throws on a
    /// deletion the service has already performed. `RoutedAPI.deleteAccount` reads any throw from
    /// here as "abort, touch nothing locally", and the sheet then says nothing was deleted — while
    /// the account is in fact gone on the far side. It is reachable only through contract skew: a
    /// 2xx whose body is not `DeleteAccountResponse`, which today means a client and a service that
    /// disagree about this route. It self-corrects in the direction of the deletion, by the same
    /// path the header above describes — the next request presenting that session is refused — so
    /// the person ends up signed out rather than stranded. Written down because the symptom
    /// ("it says it failed but my account is gone") reads as a defect in the opposite component
    /// from the one that has it.
    ///
    /// - Throws: `RemoteSurface.communityHalfOnly` when no `pendingOutboxKeys` provider was
    ///   injected — see that property for why an empty array is not an acceptable substitute.
    @discardableResult
    public func deleteAccount(_ choice: AccountDeletionChoice) async throws -> AccountDeletion.Outcome {
        guard let pendingOutboxKeys else { throw RemoteSurface.communityHalfOnly }
        let pending = try await pendingOutboxKeys()

        let data = try await transport.send(
            try request(
                "me",
                method: "DELETE",
                body: DeleteAccountBody(choice: choice.rawValue, pendingClientUUIDs: pending)
            )
        )
        let response = try decode(DeleteAccountResponse.self, from: data)

        var outcome = AccountDeletion.Outcome()
        outcome.choice = choice
        switch choice {
        case .leaveRecords:
            outcome.anonymizedContributions = response.contributions
            outcome.anonymizedPhotos = response.photos
        case .eraseEverything:
            outcome.deletedContributions = response.contributions
            outcome.deletedPhotos = response.photos
        }
        return outcome
    }

    /// **Class D — device-only, never remote** (spec §3.1).
    ///
    /// What a device is holding unattributed is a local fact by definition: the rows have not been
    /// sent. So the body is the same `.none` the extension in `DeviceContributions.swift` supplies,
    /// and the difference between this and inheriting it is the entire point of task #76 — the
    /// answer is **written down here, with the reason beside it**, rather than arrived at by a
    /// conformance having nothing to say. §3.3: "the method's honest remote implementation *is* the
    /// inherited local answer, and §3.3 is why that has to be said out loud."
    ///
    /// Read the `.none` as "this transport is not where a device's own unsent rows live", not as
    /// "this device has contributed nothing" — which is why it is `.none` and not a throw: a throw
    /// would put an error on screen 15 for a question that was answered correctly.
    public func deviceContributions() async throws -> DeviceContributions {
        .none
    }

    /// `GET /me/map-membership?kind=` — the `Yours` and `Favorites` sets (#116, RULINGS R23).
    ///
    /// The second of the two reads whose remote answer is complete: it returns ids and nothing else,
    /// deliberately, and an id set needs no city fact to be whole.
    ///
    /// Overrides `MapMembership.swift`'s empty-set default, which is the #76 case that answers
    /// without borrowing anything — an empty `Set<UUID>` reaches `MapModel` as a narrowing that
    /// matched nothing, and screen 01 draws a map on which this reader owns and hearts no tree.
    public func mapMembership(_ kind: MapMembership) async throws -> Set<UUID> {
        let data = try await transport.send(
            try request("me/map-membership", method: "GET", query: [URLQueryItem(name: "kind", value: kind.rawValue)])
        )
        return Set(try decode(MapMembershipResponse.self, from: data).treeIDs)
    }

    /// **Empty, and it is a true answer rather than a missing route** — which is why it is written
    /// out here instead of inherited from `ContributedPlace.swift`'s default.
    ///
    /// The set of ids above is joinable and is joined. A *coordinate* is not: it comes from the
    /// inventory files attached on this device, and the service has no view of which packs this
    /// phone has installed — R84 made that set cumulative and per-install. A `[ContributedPlace]`
    /// assembled anywhere else would be pins for a map that has no trees under them.
    ///
    /// The caller reads empty as "aim no fit" — the suppression ends and screen 01's own opening
    /// fly-to-you may still run — so a composition with no local half behaves exactly as screen 01
    /// did before this method existed. Declared rather than inherited
    /// for `APIConformanceGuardTests`' reason and E125's: a default satisfying a requirement on a
    /// shipping conformance is a member nobody chose.
    public func contributedPlaces() async throws -> [ContributedPlace] {
        []
    }

    // MARK: - Reports and export

    /// **No route.** The hazard-redirect log is one of spec §3.4's nine — see `claimSpecies` — and
    /// `POST /reports/hazard-redirect` is not on this service.
    public func logHazardRedirect(_ event: HazardRedirectEvent) async throws {
        throw RemoteSurface.noRouteOnThisService
    }

    /// **No route.** D12's nightly open export over the merged corpus is a real deliverable and a
    /// different artifact from the local one (§4.2 says so in as many words), and it has not been
    /// built: there is no `GET /export/latest.csv` on this service.
    public func exportLatest(_ format: ExportFormat) async throws -> Data {
        throw RemoteSurface.noRouteOnThisService
    }
}

// MARK: - The delta accessors

/// The calls that answer a **half**, for the router that owns the other half.
///
/// These are not `CypressAPI` requirements and must not become them. The protocol is "every read and
/// write the UI performs" (ARCHITECTURE §4), and no screen performs one of these: a screen asks for a
/// grove, and what a grove is includes the tree's name. Adding them to the protocol would oblige
/// fourteen preview doubles and every test double to answer questions about a wire shape — the tax
/// `CypressAPI`'s own "two methods that were requirements and are not any more" note records paying
/// once already.
public extension RemoteAPI {

    /// One account-half grove row: what the service knows and the city file does not.
    struct GroveDelta: Hashable, Sendable {
        public let treeID: UUID
        public let lastVisitedAt: Date?
        public let isFavorite: Bool
        /// Nil when the service sent no record, which `GroveEntry.record` already reads as "this
        /// read did not answer that" rather than as zero (ERRATA E38).
        public let record: GroveRecord?
        public let heroPhotoID: UUID?
    }

    /// One species the account has met, without the names.
    struct KnownSpeciesDelta: Hashable, Sendable {
        public let speciesID: UUID
        public let firstMetAt: Date
    }

    /// A tree's community half: the photographs, and which of them are this caller's.
    ///
    /// **`visit_count` is on the wire and is deliberately not here.** The service sends it; nothing
    /// this client could do with it is allowed. `TreeProfile.visits` is a `Series<Visit>` — rows
    /// plus whether they are all of them — and a bare number cannot enter one without becoming the
    /// exact claim `Series` exists to make unwritable (ERRATA **E38**): a count with no rows behind
    /// it, rendered as if it had been counted. Drawing it on its own is the other forbidden
    /// direction, and ARCHITECTURE §5.1 names this very identifier doing it: "if you find yourself
    /// writing `visitCount` into a user-visible string, stop."
    ///
    /// So it stops here rather than travelling to a router that would have to drop it anyway. It is
    /// still decoded, one layer out, so that `TreeCommunityHalfResponse` remains a complete
    /// statement of what the service sends — see the note on that field.
    struct TreeCommunityDelta: Hashable, Sendable {
        public let treeID: UUID
        public let photos: [Photo]
        public let ownPhotoIDs: Set<UUID>
        public let deletablePhotoIDs: Set<UUID>
    }

    /// `GET /me/grove`.
    func groveDelta() async throws -> [GroveDelta] {
        let data = try await transport.send(try request("me/grove", method: "GET"))
        return try decode(GroveDeltaResponse.self, from: data).entries.map {
            GroveDelta(
                treeID: $0.treeUUID,
                lastVisitedAt: $0.lastVisitedAt,
                isFavorite: $0.isFavorite,
                record: $0.record,
                heroPhotoID: $0.heroPhotoID
            )
        }
    }

    /// `GET /me/grove/species`.
    func groveSpeciesDelta() async throws -> [KnownSpeciesDelta] {
        let data = try await transport.send(try request("me/grove/species", method: "GET"))
        return try decode(GroveSpeciesDeltaResponse.self, from: data).known.map {
            KnownSpeciesDelta(speciesID: $0.speciesID, firstMetAt: $0.firstMet)
        }
    }

    /// `GET /trees/{id}` — the community half of a profile.
    ///
    /// ── The one field this cannot read off the wire, said out loud ─────────────────────────────
    ///
    /// The service sends `is_publicly_visible` and not `moderation_state`. `Photo.isPubliclyVisible`
    /// is `moderationState == .approved && deletedAt == nil`, so `true` pins the state exactly;
    /// `false` is either `pending` or `rejected` and there is no third fact on the payload to tell
    /// them apart. A rejected photograph reaches this response only for its own contributor, whose
    /// visibility rule is `deletedAt == nil` and therefore identical either way — so **every
    /// predicate in the app answers the same on both readings**, and `.pending` is chosen because it
    /// is the state the app writes and the one nothing in it has ever moved off.
    ///
    /// It is still a guess where the wire could carry a fact, and it is written down in
    /// this round's errata entry as the one field on this payload that a server
    /// round should close.
    func treeCommunityHalf(id: UUID) async throws -> TreeCommunityDelta {
        let data = try await transport.send(try request("trees/\(id.uuidString)", method: "GET"))
        let response = try decode(TreeCommunityHalfResponse.self, from: data)
        return TreeCommunityDelta(
            treeID: response.treeUUID,
            photos: response.photos.map {
                Photo(
                    id: $0.photoID,
                    treeID: response.treeUUID,
                    shotType: $0.shotType,
                    moderationState: $0.isPubliclyVisible ? .approved : .pending,
                    capturedAt: $0.capturedAt,
                    createdAt: $0.capturedAt,
                    updatedAt: $0.capturedAt
                )
            },
            ownPhotoIDs: Set(response.ownPhotoIDs),
            deletablePhotoIDs: Set(response.deletablePhotoIDs)
        )
    }

    /// `DELETE /photos/{id}` — the contributor taking their own photograph back.
    ///
    /// Returns nothing, which is the honest shape of what the service answers: `{deleted: true}` and
    /// no counts. `deletePhoto(id:)` above is the requirement, and it refuses rather than reporting
    /// numbers this call cannot produce.
    ///
    /// **Nothing in this round calls this**, and that is deliberate on the same terms as the photo
    /// transport: §3.4 keeps `deletePhoto` Class L until the outbox can carry it, so the router does
    /// not send it. It is built and tested here because R72 ruling 5 requires the way down to exist
    /// wherever the way up does, and wiring it is a conscious act rather than an inherited one.
    func deletePhotoRemotely(id: UUID) async throws {
        _ = try await transport.send(try request("photos/\(id.uuidString)", method: "DELETE"))
    }
}

// MARK: - The wire

private extension RemoteAPI {

    /// One request against `baseURL`.
    ///
    /// `appendingPathComponent`, so a base URL with or without a trailing slash behaves the same —
    /// `AuthClient.post` makes the same choice for the same reason, and the two halves of this
    /// client should not differ about what a base URL is.
    func request(
        _ path: String,
        method: String,
        query: [URLQueryItem] = [],
        body: (some Encodable)? = Optional<Never>.none
    ) throws -> URLRequest {
        var url = baseURL.appendingPathComponent(path)
        if !query.isEmpty, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.queryItems = query
            url = components.url ?? url
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try RemoteCoding.encoder.encode(body)
        }
        return request
    }

    /// A request with no body, spelled without the caller having to name a type it does not have.
    func request(_ path: String, method: String, query: [URLQueryItem] = []) throws -> URLRequest {
        try request(path, method: method, query: query, body: Optional<Never>.none)
    }

    /// Decodes a 2xx body, or `SessionError.malformedResponse`.
    ///
    /// **Not `APIError.serverError`.** The service answered and the answer was a success; what
    /// failed is this client's reading of it, and a taxonomy code here would put a retry schedule on
    /// a shape mismatch that no number of retries changes. `AuthResponse.decode` draws the same line
    /// in the same place.
    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try RemoteCoding.decoder.decode(T.self, from: data)
        } catch {
            throw SessionError.malformedResponse
        }
    }

}
