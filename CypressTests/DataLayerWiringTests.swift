//
//  DataLayerWiringTests.swift
//  CypressTests
//
//  The composition root, after #158's wiring round put a server behind it.
//
//  ── Why these read `DataLayer.boot` and not a queue they built themselves ──────────────────────
//
//  Every other outbox suite in this target constructs its own `OutboxQueue` with its own doubles,
//  which is right for testing the queue and useless for testing the *wiring*: one argument omitted
//  in `DataLayer.boot` is the whole of the difference between a contribution reaching a server and
//  not, and no test that builds its own queue can see it. `OutboxApplySendSplitTests
//  .dataLayerWiresNoSendSink` was that test for the previous truth — it read the real `boot` and
//  pinned that no send sink was wired — and this file is what replaces it now that one is.
//
//  ── The network is never a dependency here ─────────────────────────────────────────────────────
//
//  `boot(transport:)` takes the authorized wire, so these run the app's own composition root against
//  a scripted `AuthorizedTransport` (`ScriptedTransport`, from `RemoteAPITests`). A test that called
//  `cypress-sync` would be measuring Fly's uptime and would pass by being skipped on a machine with
//  no network — `CityDownloader` states the same rule about its own injected session. The live path
//  is proved separately, by hand, against the deployed service; that proof is in the PR body, not in
//  this target.
//

import Foundation
import Testing
import UIKit
@testable import Cypress

@Suite("DataLayer wiring")
struct DataLayerWiringTests {

    // MARK: - Fixtures

    /// A private database directory per test.
    ///
    /// Deliberately not removed on the way out, for the reason `dataLayerWiresNoSendSink` gave when
    /// it was the test here: `DataLayer` holds the SQLite connection past this function's scope, and
    /// unlinking the file under an open handle is what prints `BUG IN CLIENT OF libsqlite3.dylib: …
    /// vnode unlinked while in use`. The directory is a per-run UUID under `NSTemporaryDirectory()`;
    /// the simulator sweeps it.
    private static func databaseURL() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cypress-datalayer-wiring-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("cypress.sqlite")
    }

    /// A real 1×1 JPEG. Two bytes of a header are not enough: `PhotoBinary` decodes the frame
    /// before it accepts it, exactly as screen 04 does, so a fixture that skipped that would send the
    /// photo phase down its failure branch and the deferral under test would never be reached.
    @MainActor
    private static func jpeg() throws -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        let image = renderer.image { context in
            UIColor.darkGray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return try #require(image.jpegData(compressionQuality: 1))
    }

    private static func boot(_ transport: ScriptedTransport) async throws -> DataLayer {
        try await DataLayer.boot(
            databaseURL: try databaseURL(),
            seedURL: nil,
            baseURL: URL(string: "https://cypress-sync.invalid/api/v1")!,
            transport: transport
        )
    }

    /// A tree to attach contributions to. No seed here, so it is a community add — which
    /// `LocalAPI.requireTree` accepts and an invented UUID does not.
    private static func makeTree(_ data: DataLayer) async throws -> Tree {
        try await data.local.addTree(
            TreeDraft(
                coordinate: Coordinate(latitude: 37.77, longitude: -122.44),
                photoLocalPath: "/tmp/cypress-datalayer-wiring.jpg",
                attribution: Attribution.anonymous(deviceID: data.deviceID)
            )
        )
    }

    private static func enqueueVisit(_ data: DataLayer, tree: Tree) async throws -> UUID {
        let visit = Visit(
            treeID: tree.id,
            attribution: Attribution.anonymous(deviceID: data.deviceID),
            capturedAt: Date()
        )
        _ = try await data.outbox.enqueue(.visit(visit))
        return visit.clientUUID
    }

    /// `POST /sync`'s answer for one item, in the service's own wire shape (`sync.go`).
    private static func syncAccepting(_ clientUUID: UUID) -> String {
        """
        {"results":[{"client_uuid":"\(clientUUID.uuidString)","status":"applied"}]}
        """
    }

    // MARK: - 1. The send sink is wired, and it is the one that reaches the service

    /// **The replacement for `dataLayerWiresNoSendSink`, pinning the opposite truth.**
    ///
    /// That test existed to be flipped consciously, and this is the flip: the shipping composition
    /// root wires a send sink, a drain offers the item to it, and the row records `remote_sent`. It
    /// reads the real `DataLayer.boot` for the same reason its predecessor did — one omitted argument
    /// is the whole of the difference, and a test that builds its own queue cannot see it.
    ///
    /// The assertion that the request really left through `RemoteAPI` and not through some local
    /// shortcut is the scripted transport's own record: `POST /sync` was called, with this item's
    /// `client_uuid` in the body.
    @Test("the shipping composition root wires a send sink, and a drain reaches the service")
    func theCompositionRootWiresASendSink() async throws {
        let transport = ScriptedTransport()
        let data = try await Self.boot(transport)
        let tree = try await Self.makeTree(data)
        let clientUUID = try await Self.enqueueVisit(data, tree: tree)
        transport.answer("POST /sync", with: Self.syncAccepting(clientUUID))

        let report = try await data.outbox.drain()

        #expect(report.sent == 1, "the composition root wired no send sink: \(report.sent) items were sent")
        #expect(report.synced == 1)

        let record = try #require(try await data.outbox.records().first)
        #expect(record.locallyApplied, "the shipping wiring did not commit the contribution locally")
        #expect(record.remoteSent, "the row does not record that the service accepted it")
        #expect(record.item.state == .done)

        // The wire, not just the flag: one authorized call, to `POST /sync`, carrying this item.
        let call = try #require(transport.call("POST /sync"), "no POST /sync was made")
        let text = String(decoding: try #require(call.body), as: UTF8.self)
        #expect(
            text.contains(clientUUID.uuidString.lowercased()) || text.contains(clientUUID.uuidString),
            "the batch that reached the service did not carry this item's client_uuid"
        )

        // And the contribution really is on its tree, which is the property the split exists to
        // keep: the send is in addition to the local commit, never instead of it (ERRATA E261 §2).
        let held = try await data.local.deviceContributions()
        #expect(held.visits == 1, "the visit did not reach the local tables")
    }

    /// The apply sink is still the **phone**, which is the half a wiring mistake deletes silently.
    ///
    /// With a send sink now in the picture, the tempting one-line simplification is to hand one
    /// value to both positions. `APIOutboxTransport(api: local)` and `APIOutboxSendSink(remote:)` are
    /// two types over two values on purpose, and this asserts the consequence rather than the shape:
    /// **the service refusing does not take the local write with it.** ERRATA E261 §2 — "moving
    /// `LocalAPI` across does not add a network to a local write, it removes the local write" — is
    /// what would be violated, and it violates green.
    @Test("a service that refuses does not take the local commit with it")
    func aRefusedSendKeepsTheLocalWrite() async throws {
        let transport = ScriptedTransport()
        let data = try await Self.boot(transport)
        let tree = try await Self.makeTree(data)
        _ = try await Self.enqueueVisit(data, tree: tree)
        // Unscripted: the double throws `notFound` for a route nothing answered, which is a
        // taxonomy code arriving at the batch — the ordinary "the service said no" case.
        let report = try await data.outbox.drain()

        #expect(report.sent == 0)
        let record = try #require(try await data.outbox.records().first)
        #expect(record.locallyApplied, "a refused send deleted the local commit")
        #expect(!record.remoteSent)
        #expect(record.item.state != .done, "an item settled without the service having taken it")

        let held = try await data.local.deviceContributions()
        #expect(held.visits == 1, "the visit is not on its tree because the service was unreachable")
    }

    // MARK: - 2. The containment invariant, at the composition root

    /// **No `RemoteSurface` can reach an outbox item through the wiring this root builds.**
    ///
    /// `RemoteSurface` is this client's word for "the service has no route for that", and
    /// `OutboxFailureReason.sentence(for:)` has no sentence for it — anything outside the `APIError`
    /// taxonomy renders as **"No connection."**, which would be printed to somebody with four bars.
    /// PR #78's review broke that invariant in `RemoteAPI` without turning anything red, and
    /// `RemoteAPITests.theRemoteSurfaceIsConfinedToItsRefusals` is the source gate that now holds it.
    ///
    /// This is the *wiring's* half of the same invariant, and it is a different claim: the gate says
    /// no path through `RemoteAPI.sync` throws one, and this says the composition root put nothing
    /// else in the send position — a `RoutedAPI` there would reach `RemoteAPI.grove()` and friends,
    /// every one of which refuses with exactly that type.
    ///
    /// Asserted through the sentence a person would read, because that is the harm: the reason
    /// screen 17 shows for a real refusal must be the service's, not a false one about signal.
    @Test("no refusal reaches screen 17 as No connection. through this wiring")
    func theSendPathCannotProduceARemoteSurface() async throws {
        let transport = ScriptedTransport()
        let data = try await Self.boot(transport)
        let tree = try await Self.makeTree(data)
        let clientUUID = try await Self.enqueueVisit(data, tree: tree)
        // The service answering a real taxonomy code — a moderator declined this item.
        // The service's own wire shape (`sync.go`'s `syncResult`): the code is a bare string beside
        // a `message`, not a nested envelope. Copied from the Go struct rather than invented — the
        // first draft of this fixture used the envelope shape and the item failed with
        // `SessionError.malformedResponse`, which is a different finding wearing the same red.
        transport.answer(
            "POST /sync",
            with: """
            {"results":[{"client_uuid":"\(clientUUID.uuidString)","status":"failed",\
            "error":"moderation_rejected","message":"A moderator declined this."}]}
            """
        )

        _ = try await data.outbox.drain()

        let record = try #require(try await data.outbox.records().first)
        let reason = try #require(record.item.lastError)
        #expect(
            reason.contains("A moderator declined this."),
            "screen 17 would show \"\(reason)\" for a refusal the service explained"
        )
        #expect(
            !reason.contains("No connection."),
            "a refused item is telling somebody their connection is down: \"\(reason)\""
        )
        #expect(record.item.lastErrorCode == .moderationRejected)
    }

    // MARK: - 3. Phase B2 and the wi-fi deferral, with the real transport behind the send

    /// The wi-fi toggle gates **binaries only**, and it still does with a server on the other side.
    ///
    /// BUILD-PLAN §4 and screen 17 §3: "Notes and numbers sync on any connection." The photo phase
    /// runs before the send and records its deferral rather than acting on it, so that a photograph
    /// waiting for an unmetered connection never holds up a note. That ordering was rearranged once
    /// already and the first draft of it lost photographs (ERRATA **E264**); with a send sink wired
    /// it is no longer latent, so it is asserted here against the wiring rather than only against a
    /// hand-built queue.
    @Test("a binary waiting for wi-fi does not hold up the note's send through the real wiring")
    @MainActor
    func theWifiDeferralHoldsWithARealSendSink() async throws {
        let transport = ScriptedTransport()
        let data = try await Self.boot(transport)
        let tree = try await Self.makeTree(data)

        // A staged binary the apply sink can really ingest, so the photo phase is exercised rather
        // than short-circuited by a missing file.
        let staged = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cypress-wiring-photo-\(UUID().uuidString).jpg")
        try Self.jpeg().write(to: staged)

        let visit = Visit(
            treeID: tree.id,
            attribution: Attribution.anonymous(deviceID: data.deviceID),
            capturedAt: Date()
        )
        _ = try await data.outbox.enqueue(
            .visit(visit),
            photos: [OutboxPhoto(path: staged.path, shotType: .fullTree)]
        )
        transport.answer("POST /sync", with: Self.syncAccepting(visit.clientUUID))

        // Metered.
        let metered = try await data.outbox.drain(photoUploadsAllowed: false)
        #expect(metered.sent == 1, "a deferred binary stopped the note from being sent")
        #expect(metered.awaitingWifi == 1)
        #expect(metered.synced == 0, "an item waiting for wi-fi was counted as settled")

        var record = try #require(try await data.outbox.records().first)
        #expect(record.remoteSent, "the note was not sent while its photograph waited")
        #expect(record.item.photos.count == 1, "the binary was consumed on a metered connection")
        #expect(record.item.failCount == 0, "waiting for wi-fi counted as a failure")

        // Wi-fi arrives: only the binary is owed, and the service is not asked a second time.
        let unmetered = try await data.outbox.drain(photoUploadsAllowed: true)
        #expect(unmetered.sent == 0, "the note was sent to the service twice")
        record = try #require(try await data.outbox.records().first)
        #expect(record.item.state == .done)
        #expect(record.item.photos.isEmpty, "the binary was never ingested")
    }

    // MARK: - 4. `pendingOutboxKeys` — the seam `DELETE /me` cannot be honest without

    /// **`RemoteAPI.pendingOutboxKeys` is filled, and it reports the queue as it really is.**
    ///
    /// `me.go` tombstones the keys still queued at the moment of deletion, "even though this service
    /// has never seen them", so that an item queued on Tuesday against an account deleted on
    /// Wednesday cannot resurrect it on Thursday. `RemoteAPI` holds no queue, so with no provider it
    /// **refuses** rather than sending `[]` — an empty array is the claim that nothing is queued, and
    /// RULINGS R3's stated failure mode is deleting differently from what was asked. PR #78 left this
    /// as its fourth stop-and-ask; this is the composition root filling it.
    ///
    /// Asserted through `DELETE /me`'s actual request body, because that is the thing the service
    /// reads. A provider that returned the right array to a caller that never sent it would pass a
    /// weaker test.
    @Test("DELETE /me carries the queue as it really is, not a fabricated empty array")
    func deleteAccountCarriesTheTrueQueueState() async throws {
        let transport = ScriptedTransport()
        let data = try await Self.boot(transport)
        let tree = try await Self.makeTree(data)
        let queued = try await Self.enqueueVisit(data, tree: tree)
        // `me.go`'s response, whole: `DeleteAccountResponse` requires `deleted` and `choice` as well
        // as the three counters, and a fixture missing them decodes to
        // `SessionError.malformedResponse` — which is how this one was first written and how the
        // shape got checked against the Go handler instead of against memory.
        transport.answer(
            "DELETE /me",
            with: #"{"deleted":true,"choice":"leaveRecords","contributions":3,"photos":1,"tombstones":1}"#
        )

        let remote = try #require(Self.remote(of: data), "the composition root built no RemoteAPI")
        _ = try await remote.deleteAccount(.leaveRecords)

        let call = try #require(transport.call("DELETE /me"), "no DELETE /me was made")
        let body = String(decoding: try #require(call.body), as: UTF8.self)
        #expect(
            body.lowercased().contains(queued.uuidString.lowercased()),
            "DELETE /me did not name the item still in this device's queue: \(body)"
        )
        #expect(
            !body.contains("\"pending_client_uuids\":[]"),
            "DELETE /me claimed nothing was queued while an item was waiting"
        )

        // The control that makes the assertion above a measurement: with the queue drained and the
        // service having taken the item, there is nothing left to tombstone and the array is
        // *honestly* empty. Without this, "the array is non-empty" could be a constant.
        transport.answer("POST /sync", with: Self.syncAccepting(queued))
        _ = try await data.outbox.drain()
        _ = try await remote.deleteAccount(.leaveRecords)

        let second = String(decoding: try #require(transport.calls.last?.body), as: UTF8.self)
        #expect(
            !second.lowercased().contains(queued.uuidString.lowercased()),
            "an item the service has already accepted was sent as still queued: \(second)"
        )
    }

    /// The `RemoteAPI` the composition root built, reached through the router it put it in.
    ///
    /// `DataLayer.api` is `any CypressAPI`, so this is the one downcast in the suite and it is here
    /// rather than repeated: a test that constructed its own `RemoteAPI` would be testing
    /// `RemoteAPI`, which `RemoteAPITests` already does, instead of testing what `boot` wired.
    private static func remote(of data: DataLayer) -> RemoteAPI? {
        (data.api as? RoutedAPI)?.remote
    }

    /// The router is what every screen holds, and Class L still never leaves the phone.
    ///
    /// Two claims in one test because they are one wiring fact: `api` is a `RoutedAPI` over a
    /// `LocalAPI` and a `RemoteAPI`, and the §4.3 invariant "no Class L read is allowed to acquire a
    /// remote failure mode" survives the flip. The second is asserted against a transport that
    /// refuses **everything**: a `mapContent` that had become remote-routed would throw here.
    @Test("api is the router, and a Class L read still never asks the service")
    func theRouterIsWhatScreensHold() async throws {
        let transport = ScriptedTransport()
        let data = try await Self.boot(transport)
        let router = try #require(data.api as? RoutedAPI, "DataLayer.api is not the router")
        #expect(router.local is LocalAPI, "the router's local half is not LocalAPI")

        _ = try await Self.makeTree(data)
        let content = try await data.api.mapContent(
            in: MapViewport(
                bounds: BoundingBox(around: Coordinate(latitude: 37.77, longitude: -122.44), radiusM: 200),
                zoom: 17
            )
        )
        #expect(content.pinCount == 1, "the map read answered \(content.pinCount) trees, expected the one added")
        #expect(
            transport.calls.isEmpty,
            "a Class L read reached the service: \(transport.calls.map(\.path))"
        )
    }
}
