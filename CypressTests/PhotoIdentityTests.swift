//
//  PhotoIdentityTests.swift
//  CypressTests
//
//  One photograph, one row on its uploader's own profile — report F30.
//
//  ── The defect ─────────────────────────────────────────────────────────────────────────────────
//
//  A photograph this phone takes and sends had three unlinked ids: the phone's `photos.id`, the
//  begin's `client_uuid` (`outbox_photos.id`, deleted from the phone the moment the send completes),
//  and the service's own `photo_id`. `GET /trees/{id}` returns the uploader's photograph to them
//  under the service's id, `RoutedAPI.refreshedTreeProfile` deduped the two halves by id alone, and
//  no id matched — so the phone's copy and the service's copy both reached `visiblePhotos`, and the
//  hero pill on screen 03 read `2 photos` over one visit with one picture.
//
//  ── Why these run the real composition root ─────────────────────────────────────────────────────
//
//  Every link in the chain is a different layer: the apply mints the phone's id (`LocalAPI`), the
//  send mints the begin's key (`APIOutboxSendSink`), the service answers in its own shape, and the
//  merge (`RoutedAPI`) decides what the screen counts. A test that stubbed any one of them would be
//  asserting the stub. So these boot `DataLayer` over a scripted wire, drain a real photograph
//  through the real queue, and read the profile through the closure screen 03 is handed.
//
//  The service's answer is scripted in the shape `server/internal/api/reads.go` writes, and the key
//  it echoes is read off the begin this phone actually sent — never a value the test chose.
//  `GoldenWireFixtureTests` holds the shape itself to the service's real encoder.
//

import Foundation
import Testing
import UIKit
@testable import Cypress

@Suite("Photo identity — one photograph, one row (F30)", .serialized, .timeLimit(.minutes(1)))
struct PhotoIdentityTests {

    // MARK: - Fixtures

    private static func databaseURL() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cypress-photo-identity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("cypress.sqlite")
    }

    /// A real JPEG, because `PhotoBinary` decodes the frame before it accepts one.
    @MainActor
    private static func jpeg() throws -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2))
        let image = renderer.image { context in
            UIColor.darkGray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        return try #require(image.jpegData(compressionQuality: 1))
    }

    private static func boot(_ transport: ScriptedTransport) async throws -> DataLayer {
        try await DataLayer.boot(
            databaseURL: try databaseURL(),
            seedURL: nil,
            baseURL: URL(string: "https://cypress-sync.invalid/api/v1")!,
            transport: transport,
            storageSession: StubStorageProtocol.session()
        )
    }

    /// A community-added tree, which carries its own add-a-tree photograph. That one is local-only
    /// (`addTree` queues no binary), so every profile below also carries one photograph the service
    /// has never seen — a standing control that a local-only photograph still shows.
    private static func makeTree(_ data: DataLayer) async throws -> Tree {
        let tree = try await data.local.addTree(
            TreeDraft(
                coordinate: Coordinate(latitude: 37.79, longitude: -122.40),
                photoLocalPath: "/tmp/cypress-photo-identity.jpg",
                attribution: Attribution.anonymous(deviceID: data.deviceID)
            )
        )
        try await OutboxTestSupport.discardFixtureRows(in: data.store)
        return tree
    }

    /// What the phone sent in `POST /photos/begin`, read back off the wire.
    struct SentBegin {
        let clientUUID: UUID
        let capturedAt: String
        let shotType: String
    }

    /// Stages one photograph on a visit, drains it through the real queue, and answers the begin
    /// with `serverID` — the id the service mints, which the phone never keeps.
    ///
    /// `beginSucceeds: false` answers the begin with a retryable failure instead, which leaves the
    /// photograph applied on the phone and absent from the service.
    @MainActor
    private static func takeAndSendPhoto(
        _ data: DataLayer,
        transport: ScriptedTransport,
        tree: Tree,
        serverID: UUID,
        beginSucceeds: Bool = true
    ) async throws -> SentBegin? {
        let staged = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cypress-photo-identity-\(UUID().uuidString).jpg")
        try jpeg().write(to: staged)

        let visit = Visit(
            treeID: tree.id,
            attribution: Attribution.anonymous(deviceID: data.deviceID),
            capturedAt: Date()
        )
        _ = try await data.outbox.enqueue(
            .visit(visit),
            photos: [OutboxPhoto(path: staged.path, shotType: .fullTree)]
        )
        transport.answer(
            "POST /sync",
            with: #"{"results":[{"client_uuid":"\#(visit.clientUUID.uuidString)","status":"applied"}]}"#
        )
        if beginSucceeds {
            let destination = URL(string: "https://storage.invalid/photos/\(UUID().uuidString).jpg")!
            StubStorageProtocol.park(destination)
            transport.answer(
                "POST /photos/begin",
                with: #"{"photo_id":"\#(serverID.uuidString)","presigned_put_url":"\#(destination.absoluteString)","moderation_state":"approved"}"#
            )
            transport.answer("POST /photos/\(serverID.uuidString)/received", with: #"{"received":true}"#)
        } else {
            transport.answer("POST /photos/begin", throwing: APIError.serverError)
        }

        let report = try await data.outbox.drain(photoUploadsAllowed: true)
        guard beginSucceeds else {
            #expect(report.photosSent == 0)
            return nil
        }
        #expect(report.photosSent == 1, "the photograph never left, so nothing below is about F30")

        let body = try #require(transport.call("POST /photos/begin")?.body)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let key = try #require(json["client_uuid"] as? String, "the begin carried no idempotency key")
        let clientUUID = try #require(UUID(uuidString: key))
        let capturedAt = try #require(json["captured_at"] as? String)
        let shotType = try #require(json["shot_type"] as? String)
        return SentBegin(clientUUID: clientUUID, capturedAt: capturedAt, shotType: shotType)
    }

    /// One row of `GET /trees/{id}`'s `photos`, in `reads.go`'s shape. `clientUUID` is present only
    /// for the caller's own photograph, which is the service's rule and not the test's.
    private static func row(
        _ id: UUID,
        shotType: String = "full_tree",
        capturedAt: String,
        isPubliclyVisible: Bool = true,
        clientUUID: UUID? = nil
    ) -> String {
        var fields = [
            #""photo_id":"\#(id.uuidString.lowercased())""#,
            #""shot_type":"\#(shotType)""#,
            #""captured_at":"\#(capturedAt)""#,
            #""is_publicly_visible":\#(isPubliclyVisible)"#,
        ]
        if let clientUUID {
            fields.append(#""client_uuid":"\#(clientUUID.uuidString.lowercased())""#)
        }
        return "{" + fields.joined(separator: ",") + "}"
    }

    private static func answerProfile(
        _ transport: ScriptedTransport,
        tree: Tree,
        rows: [String],
        own: [UUID]
    ) {
        let ownList = own.map { #""\#($0.uuidString.lowercased())""# }.joined(separator: ",")
        transport.answer(
            "GET /trees/\(tree.id.uuidString)",
            with: """
            {"tree_uuid":"\(tree.id.uuidString.lowercased())","photos":[\(rows.joined(separator: ","))],
             "photo_count":\(rows.count),"visit_count":1,
             "own_photo_ids":[\(ownList)],"deletable_photo_ids":[\(ownList)]}
            """
        )
    }

    /// The profile screen 03 draws once the refresh lands, through the closure it is handed.
    private static func refreshed(_ data: DataLayer, tree: Tree) async throws -> TreeProfile {
        let refresh = try #require(data.refreshTreeProfile, "the refresh is not wired, so nothing merges")
        let profile = try #require(await refresh(tree.id))
        #expect(
            await data.readLog.outcome(of: .treeProfile) == .live,
            "the service's half never arrived, so this test proves nothing about the merge"
        )
        return profile
    }

    /// Every live photograph on the phone for this tree — the rows the service's copies must fold
    /// into rather than sit beside.
    private static func localPhotoIDs(_ data: DataLayer, tree: Tree) async throws -> Set<UUID> {
        Set(try await data.local.treeProfile(id: tree.id).photos.items.map(\.id))
    }

    // MARK: - 1. The headline: an uploader's own photograph counts once

    /// **F30's mechanism, end to end.** One photograph taken, sent, approved, and read back: the pill
    /// must say what the phone holds, and the browser (same series, ERRATA E215) must list it once.
    @Test("an uploader's own approved photograph counts once on its profile")
    @MainActor
    func anUploadersOwnPhotographCountsOnce() async throws {
        let transport = ScriptedTransport()
        let data = try await Self.boot(transport)
        let tree = try await Self.makeTree(data)
        let serverID = UUID()

        let sent = try #require(try await Self.takeAndSendPhoto(data, transport: transport, tree: tree, serverID: serverID))
        let onThePhone = try await Self.localPhotoIDs(data, tree: tree)
        #expect(onThePhone.count == 2, "fixture: the add-a-tree photograph and the visit's")

        // What the service answers its own contributor, key and all (`reads.go`).
        Self.answerProfile(
            transport, tree: tree,
            rows: [Self.row(serverID, shotType: sent.shotType, capturedAt: sent.capturedAt, clientUUID: sent.clientUUID)],
            own: [serverID]
        )
        let profile = try await Self.refreshed(data, tree: tree)
        let shown = profile.visiblePhotos.items.map(\.id)

        #expect(
            shown.count == onThePhone.count,
            """
            the profile shows \(shown.count) photographs for \(onThePhone.count) on the phone — the \
            service's copy of this device's own photograph (\(serverID)) was counted beside the \
            phone's, which is F30's "2 photos" over one picture
            """
        )
        #expect(Set(shown) == onThePhone, "the rows shown are not the phone's own: \(shown)")
        let pill = TreeProfilePresentation(profile: profile).heroMetaPill
        #expect(pill?.hasPrefix("\(onThePhone.count) photos") == true, "the hero pill reads \(pill ?? "nil")")
    }

    // MARK: - 2. Somebody else's photograph still counts

    @Test("a stranger's photograph still counts beside the uploader's own")
    @MainActor
    func aStrangersPhotographStillCounts() async throws {
        let transport = ScriptedTransport()
        let data = try await Self.boot(transport)
        let tree = try await Self.makeTree(data)
        let serverID = UUID()
        let strangers = UUID()

        let sent = try #require(try await Self.takeAndSendPhoto(data, transport: transport, tree: tree, serverID: serverID))
        let onThePhone = try await Self.localPhotoIDs(data, tree: tree)

        // The stranger's row is taken **in the same second, with the same framing** as this
        // device's own — the closest a photograph that is not this one can come — and it carries no
        // key, because the service never sends another person's.
        Self.answerProfile(
            transport, tree: tree,
            rows: [
                Self.row(serverID, shotType: sent.shotType, capturedAt: sent.capturedAt, clientUUID: sent.clientUUID),
                Self.row(strangers, shotType: sent.shotType, capturedAt: sent.capturedAt),
            ],
            own: [serverID]
        )
        let profile = try await Self.refreshed(data, tree: tree)
        let shown = Set(profile.visiblePhotos.items.map(\.id))

        #expect(shown.contains(strangers), "a stranger's photograph was folded away as if it were this device's")
        #expect(shown == onThePhone.union([strangers]), "shown: \(shown)")
        #expect(profile.visiblePhotos.items.count == onThePhone.count + 1)
    }

    // MARK: - 3. A photograph that never reached the service still shows

    @Test("a photograph that never left the phone still shows")
    @MainActor
    func aLocalOnlyPhotographStillShows() async throws {
        let transport = ScriptedTransport()
        let data = try await Self.boot(transport)
        let tree = try await Self.makeTree(data)
        let strangers = UUID()

        // The begin is refused, so the photograph is applied on the phone and absent from the
        // service — the state every photograph is in between the shutter and the send.
        _ = try await Self.takeAndSendPhoto(data, transport: transport, tree: tree, serverID: UUID(), beginSucceeds: false)
        let onThePhone = try await Self.localPhotoIDs(data, tree: tree)
        #expect(onThePhone.count == 2, "fixture: the add-a-tree photograph and the unsent visit's")

        Self.answerProfile(
            transport, tree: tree,
            rows: [Self.row(strangers, capturedAt: "2026-09-24T19:00:00Z")],
            own: []
        )
        let profile = try await Self.refreshed(data, tree: tree)
        let shown = Set(profile.visiblePhotos.items.map(\.id))

        #expect(shown.isSuperset(of: onThePhone), "a photograph only this phone holds was dropped: \(shown)")
        #expect(shown == onThePhone.union([strangers]))
    }
}
