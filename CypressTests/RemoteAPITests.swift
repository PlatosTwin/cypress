//
//  RemoteAPITests.swift
//  CypressTests
//
//  `RemoteAPI` against a scripted service (#158 step 4).
//
//  ── What is scripted and what is not ───────────────────────────────────────────────────────────
//
//  The network is never a test dependency here, for the reason `CityDownloader` states about its
//  own injected session: a test that called `cypress-sync` would be measuring Fly's uptime and
//  would pass by being skipped on a machine with no network. So the authorized half is a scripted
//  `AuthorizedTransport` and the unauthenticated half — the presigned `PUT` and the presigned photo
//  `GET`, which must not carry a bearer — is a `URLProtocol` stub.
//
//  What is *not* faked is the wire: every body asserted below is compared against
//  `server/internal/api`'s own structs, key for key, and the two refusal families are checked
//  against the service's actual route table rather than against a list in this file.
//

import Foundation
import Testing
@testable import Cypress

// MARK: - Doubles

/// A scripted `AuthorizedTransport`: answers by path, and records what it was asked.
///
/// Deliberately **not** a refresh-and-replay double. That behavior lives in `SessionTransport` and
/// is tested there; a second implementation of it here would be a second place for the "once" to be
/// wrong (spec §5.8).
final class ScriptedTransport: AuthorizedTransport, @unchecked Sendable {

    struct Call: Sendable {
        let method: String
        let path: String
        let query: String?
        let body: Data?
    }

    private let lock = NSLock()
    private var answers: [String: Result<Data, any Error>] = [:]
    private var recorded: [Call] = []

    init() {}

    /// Scripts `METHOD /path`, e.g. `"POST /sync"`.
    func answer(_ route: String, with json: String) {
        lock.lock(); defer { lock.unlock() }
        answers[route] = .success(Data(json.utf8))
    }

    func answer(_ route: String, throwing error: any Error) {
        lock.lock(); defer { lock.unlock() }
        answers[route] = .failure(error)
    }

    var calls: [Call] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    func call(_ route: String) -> Call? {
        calls.first { "\($0.method) \($0.path)" == route }
    }

    func send(_ request: URLRequest) async throws -> Data {
        guard let url = request.url else { throw SessionError.malformedResponse }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        // `/api/v1` is the mount point; the route table is written without it, exactly as
        // `server/internal/api/server.go` writes it.
        let path = (components?.path ?? "").replacingOccurrences(of: "/api/v1", with: "")
        let method = request.httpMethod ?? "GET"

        // Taken through a synchronous helper: `NSLock.lock()` is unavailable from an async context
        // and is an error in the Swift 6 language mode, which this target will one day be built in.
        switch record(Call(method: method, path: path, query: components?.query, body: request.httpBody)) {
        case let .success(data): return data
        case let .failure(error): throw error
        case nil:
            // An unscripted route is a test asking for something the service was never told to
            // answer. Failing loudly beats returning empty data that decodes into a silence.
            throw APIError.notFound
        }
    }

    private func record(_ call: Call) -> Result<Data, any Error>? {
        lock.lock(); defer { lock.unlock() }
        recorded.append(call)
        return answers["\(call.method) \(call.path)"]
    }
}

/// The unauthenticated half: a `URLProtocol` that answers whatever the test parked for a URL.
///
/// A `file://` URL will not do here. `AuthHTTP`'s `URLSession` conformance requires an
/// `HTTPURLResponse` and throws `SessionError.malformedResponse` without one, so a file URL would
/// exercise the failure path in every test that meant to exercise the success path.
final class StubStorageProtocol: URLProtocol {

    struct Answer: Sendable {
        let status: Int
        let body: Data
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var answers: [String: Answer] = [:]
    nonisolated(unsafe) private static var received: [(method: String, url: String, body: Data?, authorization: String?)] = []

    static func park(_ url: URL, status: Int = 200, body: Data = Data()) {
        lock.lock(); defer { lock.unlock() }
        answers[url.absoluteString] = Answer(status: status, body: body)
    }

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        answers = [:]
        received = []
    }

    static var requests: [(method: String, url: String, body: Data?, authorization: String?)] {
        lock.lock(); defer { lock.unlock() }
        return received
    }

    /// A `URLSession` that answers only through this protocol.
    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubStorageProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url?.absoluteString ?? ""
        Self.lock.lock()
        // `URLProtocol` strips `httpBody` from the request it hands the loader and exposes the
        // stream instead; reading the stream is what lets a test assert the bytes that were sent.
        Self.received.append((request.httpMethod ?? "GET", url, Self.bodyOf(request), request.value(forHTTPHeaderField: "Authorization")))
        let answer = Self.answers[url]
        Self.lock.unlock()

        guard let answer, let requestURL = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let response = HTTPURLResponse(url: requestURL, statusCode: answer.status, httpVersion: "HTTP/1.1", headerFields: nil)
        client?.urlProtocol(self, didReceive: response!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: answer.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func bodyOf(_ request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

// MARK: - The gates

@Suite("RemoteAPI (#158 step 4)", .serialized)
struct RemoteAPITests {

    static let base = URL(string: "https://service.invalid/api/v1")!

    static func api(
        _ transport: ScriptedTransport,
        session: URLSession = .shared,
        pendingOutboxKeys: (@Sendable () async throws -> [UUID])? = nil
    ) -> RemoteAPI {
        RemoteAPI(baseURL: base, transport: transport, session: session, pendingOutboxKeys: pendingOutboxKeys)
    }

    // MARK: Calibration

    /// **Calibrate the instrument before trusting the reading.** Two answers known before any gate
    /// ran: the scripted transport records the request it was given, and an unscripted route fails
    /// rather than answering emptily.
    ///
    /// Without the first, every "it sent the right body" assertion below is reading an empty list
    /// and agreeing with it; without the second, a typo in a route string would look like a pass.
    @Test("the scripted transport records and refuses")
    func theScriptedTransportRecordsAndRefuses() async throws {
        let transport = ScriptedTransport()
        transport.answer("GET /me/grove", with: #"{"entries":[],"total":0}"#)
        _ = try await Self.api(transport).groveDelta()

        let call = try #require(transport.call("GET /me/grove"), "the double recorded no call")
        #expect(call.method == "GET")

        await #expect(throws: APIError.notFound) {
            _ = try await Self.api(ScriptedTransport()).groveDelta()
        }
    }

    // MARK: The two refusal families

    /// The Class L reads refuse, and they refuse with the reason.
    ///
    /// **This gate is about the service's route table, not about a preference.**
    /// `server/internal/api/server.go` mounts eighteen routes and not one of them is city-layer;
    /// `server/README.md`'s "What this service is not" says why. A body that called
    /// `GET /species/{id}` would take Go's `ServeMux` 404 — which is not an `{error: …}` envelope —
    /// and dress it as a species that is not there.
    @Test("every Class L read refuses as a fact about the service")
    func everyClassLReadRefuses() async throws {
        let api = Self.api(ScriptedTransport())
        let viewport = MapViewport(
            bounds: BoundingBox(minLatitude: 37.7, maxLatitude: 37.8, minLongitude: -122.5, maxLongitude: -122.4),
            zoom: 16
        )
        let here = Coordinate(latitude: 37.77, longitude: -122.44)

        await #expect(throws: RemoteSurface.cityLayerIsAnsweredLocally) { _ = try await api.mapContent(in: viewport) }
        await #expect(throws: RemoteSurface.cityLayerIsAnsweredLocally) {
            _ = try await api.treesNear(here, radiusM: 50, limit: 10)
        }
        await #expect(throws: RemoteSurface.cityLayerIsAnsweredLocally) { _ = try await api.species(id: UUID()) }
        await #expect(throws: RemoteSurface.cityLayerIsAnsweredLocally) {
            _ = try await api.searchSpecies(query: "oak", limit: 5)
        }
        await #expect(throws: RemoteSurface.cityLayerIsAnsweredLocally) {
            _ = try await api.speciesGuide(id: UUID(), near: here)
        }
        await #expect(throws: RemoteSurface.cityLayerIsAnsweredLocally) { _ = try await api.almanac(near: here) }
        await #expect(throws: RemoteSurface.cityLayerIsAnsweredLocally) { _ = try await api.city(near: here) }
    }

    /// The mutations of spec §3.4 that have no route refuse, and none of them reaches the wire.
    ///
    /// §3.4's conclusion is that these "stay Class L until they are queued", which needs a widened
    /// `outbox.kind` `CHECK` — its own ticket and its own migration author. The service was built to
    /// match, so a call that reached the transport would be calling something that does not exist.
    @Test("the unqueued mutations refuse without touching the wire")
    func theUnqueuedMutationsRefuse() async throws {
        let transport = ScriptedTransport()
        let api = Self.api(transport)

        await #expect(throws: RemoteSurface.noRouteOnThisService) {
            _ = try await api.claimSpecies(treeID: UUID(), speciesID: UUID())
        }
        await #expect(throws: RemoteSurface.noRouteOnThisService) {
            _ = try await api.correctSpecies(treeID: UUID(), speciesID: UUID())
        }
        await #expect(throws: RemoteSurface.noRouteOnThisService) { try await api.flagWrongSpecies(treeID: UUID()) }
        await #expect(throws: RemoteSurface.noRouteOnThisService) { try await api.dismissSpeciesReview(flagID: UUID()) }
        await #expect(throws: RemoteSurface.noRouteOnThisService) { try await api.flagNeverExisted(treeID: UUID()) }
        await #expect(throws: RemoteSurface.noRouteOnThisService) { try await api.withdrawRecord(flagID: UUID()) }
        await #expect(throws: RemoteSurface.noRouteOnThisService) { try await api.dismissRecordReview(flagID: UUID()) }
        await #expect(throws: RemoteSurface.noRouteOnThisService) {
            try await api.setPhotoVote(photoID: UUID(), vote: .up)
        }
        await #expect(throws: RemoteSurface.noRouteOnThisService) {
            try await api.logHazardRedirect(HazardRedirectEvent(treeID: UUID(), category: .uprooted))
        }
        await #expect(throws: RemoteSurface.noRouteOnThisService) { _ = try await api.exportLatest(.csv) }

        #expect(transport.calls.isEmpty, "a refusal reached the wire: \(transport.calls.map(\.path))")
    }

    /// The four reads the service answers only half of refuse **as `CypressAPI`**, and answer as
    /// deltas.
    ///
    /// This is the finding of the round, and the gate is the pair: the conformance must not hand
    /// back a `GroveEntry` with an invented name at an invented coordinate, and the delta accessor
    /// must return the half that does exist.
    @Test("the community-half reads refuse the whole type and answer the half")
    func theCommunityHalfReadsRefuseTheWholeType() async throws {
        let transport = ScriptedTransport()
        transport.answer("GET /me/grove", with: #"{"entries":[],"total":0}"#)
        transport.answer("GET /me/grove/species", with: #"{"known":[],"total":0}"#)
        let treeID = UUID()
        transport.answer(
            "GET /trees/\(treeID.uuidString)",
            with: """
            {"tree_uuid":"\(treeID.uuidString)","photos":[],"photo_count":0,"visit_count":0,
             "own_photo_ids":[],"deletable_photo_ids":[]}
            """
        )
        let api = Self.api(transport)

        await #expect(throws: RemoteSurface.communityHalfOnly) { _ = try await api.grove() }
        await #expect(throws: RemoteSurface.communityHalfOnly) { _ = try await api.groveSpecies() }
        await #expect(throws: RemoteSurface.communityHalfOnly) { _ = try await api.journal(cursor: nil, limit: 20) }
        await #expect(throws: RemoteSurface.communityHalfOnly) { _ = try await api.treeProfile(id: treeID) }
        await #expect(throws: RemoteSurface.communityHalfOnly) { _ = try await api.deletePhoto(id: UUID()) }

        #expect(try await api.groveDelta().isEmpty)
        #expect(try await api.groveSpeciesDelta().isEmpty)
        #expect(try await api.treeCommunityHalf(id: treeID).treeID == treeID)
    }

    /// Class D is written down rather than inherited (§3.3), and it does not reach the wire.
    @Test("deviceContributions is device-only and says so")
    func deviceContributionsIsDeviceOnly() async throws {
        let transport = ScriptedTransport()
        #expect(try await Self.api(transport).deviceContributions() == .none)
        #expect(transport.calls.isEmpty)
    }

    // MARK: The reads the service answers whole

    @Test("isFavorite reads the one bit the service sends")
    func isFavoriteReadsTheOneBit() async throws {
        let treeID = UUID()
        let transport = ScriptedTransport()
        transport.answer("GET /me/grove/\(treeID.uuidString)/favorite", with: #"{"is_favorite":true}"#)

        #expect(try await Self.api(transport).isFavorite(treeID: treeID))
    }

    /// `mapMembership` carries its kind as a query parameter, spelled the American way (R23.1).
    ///
    /// The service answers `validation_failed` for anything outside `{yours, favorites}` — "an empty
    /// set is a *claim*" — so the spelling is not cosmetic.
    @Test("mapMembership sends the kind and reads the id set")
    func mapMembershipSendsTheKind() async throws {
        let first = UUID()
        let second = UUID()
        let transport = ScriptedTransport()
        transport.answer(
            "GET /me/map-membership",
            with: #"{"kind":"favorites","tree_ids":["\#(first.uuidString)","\#(second.uuidString)"]}"#
        )

        let ids = try await Self.api(transport).mapMembership(.favorites)
        #expect(ids == [first, second])
        #expect(transport.call("GET /me/map-membership")?.query == "kind=favorites")
    }

    // MARK: Sync

    /// The batch body, field by field against `server/internal/api/sync.go`'s `syncItem`.
    ///
    /// That struct is decoded with `DisallowUnknownFields`, so this body is exact and not
    /// approximate: one extra key fails that item with `validation_failed`, which is non-retryable.
    @Test("sync sends the item the service decodes, and the payload verbatim")
    func syncSendsTheItemTheServiceDecodes() async throws {
        let deviceID = UUID()
        let treeID = UUID()
        let capturedAt = Date(timeIntervalSince1970: 1_786_000_000)
        let visit = Visit(treeID: treeID, attribution: .anonymous(deviceID: deviceID), capturedAt: capturedAt)
        let item = try OutboxPayload.visit(visit).makeItem()

        let transport = ScriptedTransport()
        transport.answer(
            "POST /sync",
            with: #"{"results":[{"client_uuid":"\#(item.clientUUID.uuidString)","status":"applied"}]}"#
        )

        let results = try await Self.api(transport).sync([item])
        #expect(results.count == 1)
        #expect(results[0].status == .applied)
        #expect(results[0].isSuccess)

        let body = try #require(transport.call("POST /sync")?.body)
        let sent = try #require(
            try JSONSerialization.jsonObject(with: body) as? [String: Any],
            "the sync body was not a JSON object"
        )
        let items = try #require(sent["items"] as? [[String: Any]])
        #expect(items.count == 1)
        let sentItem = items[0]

        #expect(sentItem["client_uuid"] as? String == item.clientUUID.uuidString)
        #expect(sentItem["kind"] as? String == "visit")
        #expect(sentItem["tree_uuid"] as? String == treeID.uuidString)
        // The **contribution's** capture time, not the queue row's `createdAt`: a visit staged
        // offline and enqueued later must not be dated to the moment the network came back.
        #expect(sentItem["occurred_at"] as? String == "2026-08-06T07:06:40Z")
        #expect(sentItem["device_id"] as? String == deviceID.uuidString)
        #expect(sentItem["user_id"] == nil, "an anonymous item claimed an account")
        // Omitted on the five kinds that are not a toggle: a present `is_favorite` is read as a
        // decision, and a defaulted `false` is how a heart goes off with everything reporting success.
        #expect(sentItem["is_favorite"] == nil)

        // The payload travels verbatim — it is "the mutation the outbox promised to send".
        let payload = try #require(sentItem["payload"] as? [String: Any])
        #expect(payload["treeID"] as? String == treeID.uuidString)
        #expect(payload["clientUUID"] as? String == visit.clientUUID.uuidString)

        // Only the eight keys `syncItem` declares, and no more.
        #expect(
            Set(sentItem.keys).isSubset(of: [
                "client_uuid", "kind", "tree_uuid", "occurred_at", "payload", "user_id", "device_id", "is_favorite"
            ]),
            "the item carried a key `syncItem` does not declare: \(Set(sentItem.keys))"
        )
    }

    /// A favorite toggle carries the mirror, and it agrees with its own payload.
    ///
    /// The service rejects an item that disagrees with itself about this, and reads a missing
    /// answer as a validation failure rather than as `false`.
    @Test("a favorite toggle sends the mirror the service checks")
    func aFavoriteToggleSendsTheMirror() async throws {
        let toggle = FavoriteToggle(owner: .device(UUID()), treeID: UUID(), isFavorite: true)
        let item = try OutboxPayload.favoriteToggle(toggle).makeItem()

        let transport = ScriptedTransport()
        transport.answer(
            "POST /sync",
            with: #"{"results":[{"client_uuid":"\#(item.clientUUID.uuidString)","status":"duplicate"}]}"#
        )

        let results = try await Self.api(transport).sync([item])
        // `duplicate` is a success: the service deduped on `client_uuid` and changed nothing.
        #expect(results[0].status == .duplicate)
        #expect(results[0].isSuccess)

        let body = try #require(transport.call("POST /sync")?.body)
        let sent = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let item0 = try #require((sent?["items"] as? [[String: Any]])?.first)
        #expect(item0["is_favorite"] as? Bool == true)
        #expect((item0["payload"] as? [String: Any])?["isFavorite"] as? Bool == true)
    }

    /// **An item the response does not name is failed retryably, never dropped.**
    ///
    /// A dropped verdict settles a queue row that nothing decided. `serverError` is the one code
    /// that keeps it alive on the backoff, which is the correct reading of "the service answered and
    /// did not mention this item".
    @Test("an unanswered item comes back retryably failed")
    func anUnansweredItemComesBackRetryablyFailed() async throws {
        let first = try OutboxPayload.visit(
            Visit(treeID: UUID(), attribution: .anonymous(deviceID: UUID()), capturedAt: Date())
        ).makeItem()
        let second = try OutboxPayload.visit(
            Visit(treeID: UUID(), attribution: .anonymous(deviceID: UUID()), capturedAt: Date())
        ).makeItem()

        let transport = ScriptedTransport()
        transport.answer(
            "POST /sync",
            with: #"{"results":[{"client_uuid":"\#(first.clientUUID.uuidString)","status":"applied"}]}"#
        )

        let results = try await Self.api(transport).sync([first, second])
        #expect(results.count == 2)
        #expect(results[0].status == .applied)
        #expect(results[1].clientUUID == second.clientUUID)
        #expect(results[1].status == .failed)
        #expect(results[1].error == .serverError)
        #expect(results[1].error?.retryable == true, "the unanswered item was failed terminally")
    }

    /// A per-item `forbidden` is carried through as itself — never as `unauthorized`.
    ///
    /// `server/README.md`: "A 401 means the session, never the item." An `unauthorized` on an item
    /// is non-retryable and prints "Sign in to send this" to somebody who is signed in (E261 §3).
    @Test("a per-item failure keeps the service's own code")
    func aPerItemFailureKeepsTheServicesOwnCode() async throws {
        let item = try OutboxPayload.visit(
            Visit(treeID: UUID(), attribution: .anonymous(deviceID: UUID()), capturedAt: Date())
        ).makeItem()

        let transport = ScriptedTransport()
        transport.answer(
            "POST /sync",
            with: """
            {"results":[{"client_uuid":"\(item.clientUUID.uuidString)","status":"failed",
             "error":"forbidden","message":"That item belongs to a different device."}]}
            """
        )

        let results = try await Self.api(transport).sync([item])
        #expect(results[0].error == .forbidden)
    }

    @Test("an empty batch is not a request")
    func anEmptyBatchIsNotARequest() async throws {
        let transport = ScriptedTransport()
        #expect(try await Self.api(transport).sync([]).isEmpty)
        #expect(transport.calls.isEmpty)
    }

    // MARK: Photos — the transport half of spec §1.1

    @Test("beginPhotoUpload sends the framing and reads the presigned destination")
    func beginPhotoUploadReadsTheDestination() async throws {
        let photoID = UUID()
        let treeID = UUID()
        let transport = ScriptedTransport()
        transport.answer(
            "POST /photos/begin",
            with: """
            {"photo_id":"\(photoID.uuidString)",
             "presigned_put_url":"https://storage.invalid/photos/\(photoID.uuidString).jpg?sig=abc",
             "moderation_state":"approved","approval_reason":"auto_approved_launch"}
            """
        )

        let ticket = try await Self.api(transport).beginPhotoUpload(
            PhotoUploadRequest(
                treeID: treeID,
                shotType: .trunk,
                localPath: "/tmp/x.jpg",
                capturedAt: Date(timeIntervalSince1970: 1_786_000_000),
                width: 100,
                height: 200
            )
        )

        #expect(ticket.photoID == photoID)
        #expect(ticket.destination.host == "storage.invalid")

        let body = try #require(transport.call("POST /photos/begin")?.body)
        let sent = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(sent["tree_uuid"] as? String == treeID.uuidString)
        // The chip the contributor tapped, in `photos.shot_type`'s own vocabulary. It is append-only
        // and this is the last moment the true framing exists to be recorded.
        #expect(sent["shot_type"] as? String == "trunk")
        #expect(sent["captured_at"] as? String == "2026-08-06T07:06:40Z")
        #expect(sent["width"] as? Int == 100)
        // ERRATA E42: not storing a location is the privacy-safe direction, and nothing that ships
        // sets one.
        #expect(sent["public_lat"] == nil)
    }

    /// The binary goes **straight to storage, with no bearer**, and the receipt comes after it.
    ///
    /// Both halves are the gate. Presenting this service's credential to a storage host sends it
    /// somewhere it has no business being; marking a photograph received before its bytes landed
    /// keeps a record alive with nothing behind it (`PhotoUploadTicket.binaryGracePeriod`).
    @Test("the photo binary is PUT to storage unauthenticated, then receipted")
    func thePhotoBinaryIsPutToStorageUnauthenticated() async throws {
        StubStorageProtocol.reset()
        let photoID = UUID()
        let destination = URL(string: "https://storage.invalid/photos/\(photoID.uuidString).jpg?sig=abc")!
        StubStorageProtocol.park(destination, status: 200)

        let staged = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cypress-remote-put-\(UUID().uuidString).jpg")
        let bytes = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])
        try bytes.write(to: staged)
        defer { try? FileManager.default.removeItem(at: staged) }

        let transport = ScriptedTransport()
        transport.answer("POST /photos/\(photoID.uuidString)/received", with: #"{"received":true}"#)

        try await Self.api(transport, session: StubStorageProtocol.session()).uploadPhoto(
            at: staged.path,
            ticket: PhotoUploadTicket(photoID: photoID, destination: destination)
        )

        let put = try #require(StubStorageProtocol.requests.first { $0.method == "PUT" })
        #expect(put.url == destination.absoluteString)
        #expect(put.body == bytes, "the staged bytes were not the ones PUT")
        #expect(
            put.authorization == nil,
            "the presigned PUT carried this service's credential to a storage host"
        )
        #expect(transport.call("POST /photos/\(photoID.uuidString)/received") != nil, "the receipt was not sent")
    }

    /// A storage refusal is retryable, and the receipt is not sent.
    ///
    /// Storage answers in its own vocabulary — S3-style XML, not this service's envelope — so there
    /// is no taxonomy code to read out of it. A presigned signature expires in thirty minutes and
    /// the next attempt mints a fresh one, which is what makes `serverError` the true reading.
    @Test("a refused PUT is retryable and does not receipt")
    func aRefusedPutIsRetryableAndDoesNotReceipt() async throws {
        StubStorageProtocol.reset()
        let photoID = UUID()
        let destination = URL(string: "https://storage.invalid/photos/\(photoID.uuidString).jpg")!
        StubStorageProtocol.park(destination, status: 403, body: Data("<Error/>".utf8))

        let staged = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cypress-remote-put-\(UUID().uuidString).jpg")
        try Data([0xFF, 0xD8]).write(to: staged)
        defer { try? FileManager.default.removeItem(at: staged) }

        let transport = ScriptedTransport()
        let api = Self.api(transport, session: StubStorageProtocol.session())

        await #expect(throws: APIError.serverError) {
            try await api.uploadPhoto(
                at: staged.path,
                ticket: PhotoUploadTicket(photoID: photoID, destination: destination)
            )
        }
        #expect(APIError.serverError.retryable, "a storage refusal must keep the item alive")
        #expect(transport.calls.isEmpty, "a photograph was receipted whose bytes never landed")
    }

    /// A staged file that is not there is a fact about this device, not about the service.
    ///
    /// **This branch had no test at all, and review of PR #78 is how that was found**: the reviewer
    /// changed it to throw a `RemoteSurface` — the containment invariant breaking in exactly the way
    /// `RemoteSurface`'s header names — and all 1,434 tests stayed green. Two things follow, and this
    /// test is the first of them.
    ///
    /// What it must not throw is as load-bearing as what it must. A taxonomy code here would be an
    /// answer about the service for a file this device lost, and a non-retryable one
    /// (`validationFailed`) would fail an outbox item terminally over a local condition. A
    /// `RemoteSurface` would print "No connection." to somebody with four bars
    /// (`OutboxFailureReason.sentence(for:)`). `SessionError.malformedResponse` is neither: outside
    /// the taxonomy, so the item stays alive on the backoff (ERRATA **E261** §3).
    @Test("a missing staged file is neither a taxonomy code nor a RemoteSurface")
    func aMissingStagedFileIsNeitherATaxonomyCodeNorARemoteSurface() async throws {
        StubStorageProtocol.reset()
        let photoID = UUID()
        let destination = URL(string: "https://storage.invalid/photos/\(photoID.uuidString).jpg")!
        StubStorageProtocol.park(destination, status: 200)

        let transport = ScriptedTransport()
        let api = Self.api(transport, session: StubStorageProtocol.session())
        let absent = NSTemporaryDirectory() + "/cypress-absent-\(UUID().uuidString).jpg"

        await #expect(throws: SessionError.malformedResponse) {
            try await api.uploadPhoto(
                at: absent,
                ticket: PhotoUploadTicket(photoID: photoID, destination: destination)
            )
        }
        #expect(
            StubStorageProtocol.requests.isEmpty,
            "a PUT was attempted for bytes this device does not have"
        )
        #expect(transport.calls.isEmpty, "a photograph was receipted whose bytes were never read")
    }

    /// **The containment invariant, held from the source: no path through the two send-sink methods
    /// throws a `RemoteSurface`.**
    ///
    /// ── Why this is a source gate and the test above is not enough ─────────────────────────────
    ///
    /// The invariant is over *every* path through two bodies. A behavioral test can only assert the
    /// paths it can reach, and reaching all of them means driving `sync` through a decode failure, an
    /// encode failure, a transport failure and an unreadable success body, plus `uploadPhoto` through
    /// four more — eight tests that would still say nothing about the ninth branch somebody adds next
    /// year. The property "this body cannot throw that type" is a property of the *text*, and the
    /// text is what a gate should read. `theClassLBodiesNeverNameTheService` in `RoutedAPITests` is
    /// the same instrument for the same reason, and this round's review is what pointed it here.
    ///
    /// ── What it does not cover, stated rather than implied ─────────────────────────────────────
    ///
    /// Callees. The gate reads the two methods and the two private helpers they call into
    /// (`request`, `decode`); a `RemoteSurface` thrown by something further down — `OutboxPayload`,
    /// `JSONValue`, the transport — would evade it. Those were read once, by hand, when this was
    /// written: none of them can name a type declared in `RemoteWire.swift` from where they sit, and
    /// `AuthorizedTransport` is a seam whose documented error set is `APIError` and `SessionError`.
    /// That is a smaller claim than the gate makes, and it is the honest boundary of it.
    @Test("no send-sink body can throw a RemoteSurface")
    func theSendSinkBodiesCannotThrowARemoteSurface() throws {
        let source = try String(
            contentsOf: AppSourceLiterals.repositoryRoot()
                .appendingPathComponent("Cypress/Data/API/RemoteAPI.swift"),
            encoding: .utf8
        )

        /// A method's body, from its `func` line to the line that closes it at the same indent.
        func body(of signature: String) -> String? {
            let lines = source.components(separatedBy: "\n")
            guard let start = lines.firstIndex(where: { $0.contains("func \(signature)") }) else { return nil }
            let indent = lines[start].prefix { $0 == " " }
            guard let end = lines[(start + 1)...].firstIndex(where: { $0 == indent + "}" }) else { return nil }
            return lines[(start + 1)..<end].joined(separator: "\n")
        }

        // Calibration, three parts: the extractor finds a body, it is the right body, and — the
        // negative control — a method that *does* throw a `RemoteSurface` reads as one. Without the
        // last, an extractor returning the empty string would certify every method clean.
        let sync = try #require(body(of: "sync(_ items:"), "the body extractor found nothing — this gate is vacuous")
        #expect(sync.contains("POST"), "the extractor did not read sync's body")
        #expect(
            body(of: "grove()")?.contains("RemoteSurface") == true,
            "the negative control did not read as a refusal — this gate cannot tell the two apart"
        )
        #expect(body(of: "notAMethodOnThisType()") == nil, "the extractor answered for a method that does not exist")

        // The two an `OutboxSendSink` can call, and the two private helpers they call into.
        //
        // `decode<T` and not `decode(`: the helper is generic, so its `func` line reads
        // `func decode<T: Decodable>(…`. The `#require` above is what said so rather than the gate
        // quietly checking three methods and calling it four.
        for signature in ["sync(_ items:", "uploadPhoto(at localPath:", "request(", "decode<T"] {
            let found = try #require(body(of: signature), "no body found for \(signature)")
            #expect(
                !found.contains("RemoteSurface"),
                """
                \(signature) can throw a RemoteSurface. An outbox item that reached one would print \
                "No connection." to somebody with four bars — see RemoteSurface's header.
                """
            )
        }
    }

    /// `GET /photos/{id}` answers a presigned source, and the bytes come from there.
    ///
    /// Two round trips on purpose: a 256 MB machine that streamed every photograph on every profile
    /// read is the one way this service falls over under success.
    @Test("photoData follows the presigned source and returns the bytes")
    func photoDataFollowsThePresignedSource() async throws {
        StubStorageProtocol.reset()
        let photoID = UUID()
        let source = URL(string: "https://storage.invalid/read/\(photoID.uuidString).jpg?sig=xyz")!
        let bytes = Data([0xFF, 0xD8, 0xFF, 0xDB, 0x01, 0x02, 0x03])
        StubStorageProtocol.park(source, status: 200, body: bytes)

        let transport = ScriptedTransport()
        transport.answer(
            "GET /photos/\(photoID.uuidString)",
            with: """
            {"photo_id":"\(photoID.uuidString)","url":"\(source.absoluteString)","expires_in":1800,
             "shot_type":"full_tree","captured_at":"2026-08-09T18:41:46Z"}
            """
        )

        let data = try await Self.api(transport, session: StubStorageProtocol.session()).photoData(id: photoID)
        #expect(data == bytes)
        #expect(
            StubStorageProtocol.requests.first { $0.url == source.absoluteString }?.authorization == nil,
            "the presigned read carried this service's credential"
        )
    }

    /// A rejected photograph is `moderation_rejected`, which has a sentence in the client and had
    /// never been thrown until this route existed.
    @Test("a rejected photograph surfaces as moderation_rejected")
    func aRejectedPhotographSurfacesAsModerationRejected() async throws {
        let transport = ScriptedTransport()
        transport.answer("GET /photos/\(UUID().uuidString)", throwing: APIError.moderationRejected)
        let id = UUID()
        transport.answer("GET /photos/\(id.uuidString)", throwing: APIError.moderationRejected)

        await #expect(throws: APIError.moderationRejected) {
            _ = try await Self.api(transport).photoData(id: id)
        }
    }

    @Test("deletePhotoRemotely calls the takedown the ruling requires to exist")
    func deletePhotoRemotelyCallsTheTakedown() async throws {
        let id = UUID()
        let transport = ScriptedTransport()
        transport.answer("DELETE /photos/\(id.uuidString)", with: #"{"deleted":true}"#)

        try await Self.api(transport).deletePhotoRemotely(id: id)
        #expect(transport.call("DELETE /photos/\(id.uuidString)") != nil)
    }

    // MARK: Trees

    /// `POST /trees` sends the draft the service's `addTreeRequest` declares, and the returned
    /// `Tree` is the draft's own facts under the id the service confirmed.
    @Test("addTree sends the draft and echoes it under the confirmed id")
    func addTreeSendsTheDraft() async throws {
        let clientUUID = UUID()
        let speciesID = UUID()
        let draft = TreeDraft(
            clientUUID: clientUUID,
            coordinate: Coordinate(latitude: 37.7601, longitude: -122.505),
            placement: .contributorPlaced,
            speciesID: speciesID,
            photoLocalPath: "/tmp/tree.jpg",
            attribution: .anonymous(deviceID: UUID()),
            address: "1 Main St",
            landContext: .street
        )

        let transport = ScriptedTransport()
        transport.answer("POST /trees", with: #"{"id":"\#(clientUUID.uuidString)","status":"applied"}"#)

        let tree = try await Self.api(transport).addTree(draft)
        #expect(tree.id == clientUUID, "the tree's id is the client_uuid the service treats as its id")
        #expect(tree.source == .community)
        #expect(tree.verificationState == .unverified)
        #expect(tree.status == .alive)
        #expect(tree.placement == .contributorPlaced)
        #expect(tree.statedLandContext == .street)
        #expect(tree.speciesCurrentID == speciesID)
        #expect(tree.address == "1 Main St")

        let body = try #require(transport.call("POST /trees")?.body)
        let sent = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(sent["client_uuid"] as? String == clientUUID.uuidString)
        #expect(sent["lat"] as? Double == 37.7601)
        #expect(sent["lon"] as? Double == -122.505)
        #expect(sent["placement"] as? String == "contributor_placed")
        #expect(sent["land_context"] as? String == "street")
    }

    /// "Community add: requires photo" (BUILD-PLAN §6), refused before the wire rather than after.
    @Test("a photoless draft is refused without a request")
    func aPhotolessDraftIsRefused() async throws {
        let transport = ScriptedTransport()
        await #expect(throws: APIError.validationFailed) {
            _ = try await Self.api(transport).addTree(
                TreeDraft(
                    coordinate: Coordinate(latitude: 37.77, longitude: -122.44),
                    photoLocalPath: "",
                    attribution: .anonymous(deviceID: UUID())
                )
            )
        }
        #expect(transport.calls.isEmpty)
    }

    // MARK: The account

    @Test("claimDevice sends both identities")
    func claimDeviceSendsBothIdentities() async throws {
        let deviceUUID = UUID()
        let userID = UUID()
        let transport = ScriptedTransport()
        transport.answer("POST /devices/claim", with: #"{"claimed":true}"#)

        try await Self.api(transport).claimDevice(deviceUUID: deviceUUID, userID: userID)

        let body = try #require(transport.call("POST /devices/claim")?.body)
        let sent = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(sent["device_uuid"] as? String == deviceUUID.uuidString)
        #expect(sent["user_id"] as? String == userID.uuidString)
    }

    /// **`DELETE /me` refuses rather than claiming the queue is empty.**
    ///
    /// The keys still queued at the moment of deletion are tombstoned by the service so that an item
    /// queued on Tuesday cannot resurrect an account deleted on Wednesday. `RemoteAPI` holds no
    /// queue, and an empty array is the *claim* that there is nothing to tombstone — R3's stated
    /// failure mode is deleting differently from what the person asked for.
    @Test("deleteAccount refuses with no way to know what is queued")
    func deleteAccountRefusesWithNoPendingKeys() async throws {
        let transport = ScriptedTransport()
        transport.answer("DELETE /me", with: #"{"deleted":true,"choice":"leaveRecords","contributions":0,"photos":0,"tombstones":0}"#)

        await #expect(throws: RemoteSurface.communityHalfOnly) {
            _ = try await Self.api(transport).deleteAccount(.leaveRecords)
        }
        #expect(transport.calls.isEmpty, "a deletion was sent that could not say what was queued")
    }

    /// The choice travels, the queued keys travel, and the counters land on the door that was used.
    @Test("deleteAccount carries the choice and the queued keys, and maps the door it used")
    func deleteAccountCarriesTheChoiceAndTheQueuedKeys() async throws {
        let queued = [UUID(), UUID()]
        let transport = ScriptedTransport()
        transport.answer(
            "DELETE /me",
            with: #"{"deleted":true,"choice":"eraseEverything","contributions":7,"photos":3,"tombstones":2}"#
        )

        let outcome = try await Self.api(transport, pendingOutboxKeys: { queued })
            .deleteAccount(.eraseEverything)

        #expect(outcome.choice == .eraseEverything)
        // The erasing door deleted; nothing was anonymized. Writing these into the other pair would
        // tell somebody their records were kept when they were destroyed.
        #expect(outcome.deletedContributions == 7)
        #expect(outcome.deletedPhotos == 3)
        #expect(outcome.anonymizedContributions == 0)
        #expect(outcome.anonymizedPhotos == 0)

        let body = try #require(transport.call("DELETE /me")?.body)
        let sent = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(sent["choice"] as? String == "eraseEverything")
        #expect(sent["pending_client_uuids"] as? [String] == queued.map(\.uuidString))
    }

    @Test("the keeping door's counters land on the anonymized fields")
    func theKeepingDoorsCountersLandOnTheAnonymizedFields() async throws {
        let transport = ScriptedTransport()
        transport.answer(
            "DELETE /me",
            with: #"{"deleted":true,"choice":"leaveRecords","contributions":4,"photos":1,"tombstones":0}"#
        )

        let outcome = try await Self.api(transport, pendingOutboxKeys: { [] }).deleteAccount(.leaveRecords)
        #expect(outcome.anonymizedContributions == 4)
        #expect(outcome.anonymizedPhotos == 1)
        #expect(outcome.deletedContributions == 0)
        #expect(outcome.deletedPhotos == 0)
    }

    // MARK: The deltas

    @Test("the grove delta reads the account's half, record and all")
    func theGroveDeltaReadsTheAccountsHalf() async throws {
        let treeID = UUID()
        let heroID = UUID()
        let transport = ScriptedTransport()
        transport.answer(
            "GET /me/grove",
            with: """
            {"entries":[{"tree_uuid":"\(treeID.uuidString)","last_visited_at":"2026-08-09T18:41:46Z",
             "is_favorite":true,"record":{"visits":3,"checkIns":1,"measurements":2,"careEvents":0},
             "hero_photo_id":"\(heroID.uuidString)"}],"total":1}
            """
        )

        let delta = try await Self.api(transport).groveDelta()
        #expect(delta.count == 1)
        #expect(delta[0].treeID == treeID)
        #expect(delta[0].isFavorite)
        #expect(delta[0].record?.checkIns == 1)
        #expect(delta[0].heroPhotoID == heroID)
    }

    /// The community half of a profile, and the one field the wire cannot carry.
    ///
    /// `is_publicly_visible` pins `approved` exactly when true; false is `pending` or `rejected` and
    /// there is no third fact on the payload. Every visibility predicate in the app answers the same
    /// on both readings, which is why `.pending` is a safe choice and still a documented guess.
    @Test("the community half becomes photographs with the visibility the wire states")
    func theCommunityHalfBecomesPhotographs() async throws {
        let treeID = UUID()
        let published = UUID()
        let mine = UUID()
        let transport = ScriptedTransport()
        transport.answer(
            "GET /trees/\(treeID.uuidString)",
            with: """
            {"tree_uuid":"\(treeID.uuidString)","photos":[
              {"photo_id":"\(published.uuidString)","shot_type":"full_tree",
               "captured_at":"2026-08-09T18:41:46Z","is_publicly_visible":true},
              {"photo_id":"\(mine.uuidString)","shot_type":"leaf",
               "captured_at":"2026-08-08T10:00:00Z","is_publicly_visible":false}],
             "photo_count":2,"visit_count":9,
             "own_photo_ids":["\(mine.uuidString)"],"deletable_photo_ids":["\(mine.uuidString)"]}
            """
        )

        // The response carries `visit_count: 9` and the delta deliberately has no field for it —
        // `Series` forbids a count with no rows behind it (ERRATA E38) and ARCHITECTURE §5.1 names
        // this identifier as the thing not to write into a user-visible string. The wire fact is
        // asserted where the wire is described (`TreeCommunityHalfResponse`), not here, and there is
        // deliberately no assertion on it in this test: a value nothing depends on, pinned, is a
        // test that only makes the field harder to remove.
        let half = try await Self.api(transport).treeCommunityHalf(id: treeID)
        #expect(half.photos.count == 2)
        #expect(half.ownPhotoIDs == [mine])
        #expect(half.deletablePhotoIDs == [mine])

        let publishedPhoto = try #require(half.photos.first { $0.id == published })
        #expect(publishedPhoto.isPubliclyVisible, "a photograph the service published is not visible")
        #expect(publishedPhoto.treeID == treeID)
        #expect(publishedPhoto.shotType == .fullTree)

        let ownPhoto = try #require(half.photos.first { $0.id == mine })
        #expect(!ownPhoto.isPubliclyVisible)
        #expect(ownPhoto.isVisibleToItsContributor, "a contributor cannot see their own photograph")
    }

    /// A body this client cannot read is `SessionError.malformedResponse` and never a taxonomy code.
    ///
    /// The service answered, and answered a success; what failed is the reading. A retryable code
    /// here would put a backoff schedule on a shape mismatch that no number of retries changes.
    @Test("an unreadable success body is not a taxonomy code")
    func anUnreadableSuccessBodyIsNotATaxonomyCode() async throws {
        let transport = ScriptedTransport()
        transport.answer("GET /me/grove", with: #"{"entries":"not an array"}"#)

        await #expect(throws: SessionError.malformedResponse) {
            _ = try await Self.api(transport).groveDelta()
        }
    }
}
