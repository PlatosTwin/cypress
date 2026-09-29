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
    /// `beginSucceeds: false` answers the begin with `beginFailure` instead, which leaves the
    /// photograph applied on the phone and absent from the service. The default is retryable, so the
    /// send stays owed; a non-retryable one is refused for good and the send is given up.
    @MainActor
    private static func takeAndSendPhoto(
        _ data: DataLayer,
        transport: ScriptedTransport,
        tree: Tree,
        serverID: UUID,
        beginSucceeds: Bool = true,
        beginFailure: APIError = .serverError,
        shotType: ShotType = .fullTree
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
            photos: [OutboxPhoto(path: staged.path, shotType: shotType)]
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
            transport.answer("POST /photos/begin", throwing: beginFailure)
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
        #expect(
            onThePhone.contains(sent.clientUUID),
            "the begin's key \(sent.clientUUID) is not the phone's photos.id — the link the fix rests on is missing"
        )

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

    // MARK: - 4. Pending: visible to its contributor only, and still one row

    @Test("an uploader's own pending photograph counts once too")
    @MainActor
    func anUploadersOwnPendingPhotographCountsOnce() async throws {
        let transport = ScriptedTransport()
        let data = try await Self.boot(transport)
        let tree = try await Self.makeTree(data)
        let serverID = UUID()

        let sent = try #require(try await Self.takeAndSendPhoto(data, transport: transport, tree: tree, serverID: serverID))
        let onThePhone = try await Self.localPhotoIDs(data, tree: tree)

        // An anonymous device's photograph is `pending` on the service and reaches only its own
        // contributor, which is the one reader who also holds the phone's copy.
        Self.answerProfile(
            transport, tree: tree,
            rows: [Self.row(serverID, shotType: sent.shotType, capturedAt: sent.capturedAt,
                            isPubliclyVisible: false, clientUUID: sent.clientUUID)],
            own: [serverID]
        )
        let profile = try await Self.refreshed(data, tree: tree)
        #expect(Set(profile.visiblePhotos.items.map(\.id)) == onThePhone)
    }

    // MARK: - 5. Withdrawn here, still on the service

    /// The contributor withdrew the photograph on this phone; the service's copy is still live
    /// (the withdrawal is queued, or never reached it). It must not come back onto their profile.
    @Test("a photograph withdrawn on the phone does not come back from the service")
    @MainActor
    func aWithdrawnPhotographDoesNotComeBack() async throws {
        let transport = ScriptedTransport()
        let data = try await Self.boot(transport)
        let tree = try await Self.makeTree(data)
        let serverID = UUID()

        let sent = try #require(try await Self.takeAndSendPhoto(data, transport: transport, tree: tree, serverID: serverID))
        _ = try await data.api.deletePhoto(id: sent.clientUUID)
        let onThePhone = try await Self.localPhotoIDs(data, tree: tree)
        #expect(!onThePhone.contains(sent.clientUUID), "fixture: the withdrawal did not take on the phone")

        Self.answerProfile(
            transport, tree: tree,
            rows: [Self.row(serverID, shotType: sent.shotType, capturedAt: sent.capturedAt, clientUUID: sent.clientUUID)],
            own: [serverID]
        )
        let profile = try await Self.refreshed(data, tree: tree)
        let shown = Set(profile.visiblePhotos.items.map(\.id))
        #expect(!shown.contains(serverID), "the service's copy of a withdrawn photograph came back: \(shown)")
        #expect(shown == onThePhone)
    }

    // MARK: - 6. A photograph sent by an earlier build

    /// Sent before the phone's id was the begin's key: the service echoes a key the phone no longer
    /// holds (`outbox_photos.id`, deleted when the send completed). This is the tester's own tree in
    /// F30 after they update — the row must still fold, and an own row that is **not** this
    /// photograph (the same account's other phone, an hour earlier) must still show.
    @Test("a photograph sent by an earlier build counts once, and a different own photograph still shows")
    @MainActor
    func aPhotographSentByAnEarlierBuildCountsOnce() async throws {
        let transport = ScriptedTransport()
        let data = try await Self.boot(transport)
        let tree = try await Self.makeTree(data)
        let serverID = UUID()
        let otherPhone = UUID()

        let sent = try #require(try await Self.takeAndSendPhoto(data, transport: transport, tree: tree, serverID: serverID))
        let onThePhone = try await Self.localPhotoIDs(data, tree: tree)

        let formatter = ISO8601DateFormatter()
        let captured = try #require(formatter.date(from: sent.capturedAt))
        let anHourEarlier = formatter.string(from: captured.addingTimeInterval(-3600))

        Self.answerProfile(
            transport, tree: tree,
            rows: [
                Self.row(serverID, shotType: sent.shotType, capturedAt: sent.capturedAt, clientUUID: UUID()),
                Self.row(otherPhone, shotType: sent.shotType, capturedAt: anHourEarlier, clientUUID: UUID()),
            ],
            own: [serverID, otherPhone]
        )
        let profile = try await Self.refreshed(data, tree: tree)
        let shown = Set(profile.visiblePhotos.items.map(\.id))

        #expect(!shown.contains(serverID), "the earlier build's photograph was drawn twice: \(shown)")
        #expect(shown.contains(otherPhone), "a different photograph of the same account's was folded away")
        #expect(shown == onThePhone.union([otherPhone]))
    }

    // MARK: - 7. The pairing rule itself

    /// Two photographs from one visit share a capture time — they share an item — so the earlier
    /// build's pairing has to be one-to-one or the second service copy would fold into the first
    /// local row and the pair would read as one (or one would survive as a double).
    @Test("an earlier build's copies pair one-to-one with the phone's rows")
    func earlierBuildCopiesPairOneToOne() throws {
        let tree = UUID()
        let at = Date(timeIntervalSince1970: 1_790_000_000)
        let first = Photo(treeID: tree, shotType: .fullTree, capturedAt: at.addingTimeInterval(0.4))
        let second = Photo(treeID: tree, shotType: .fullTree, capturedAt: at.addingTimeInterval(0.4))
        let copies = (0..<3).map { _ in Photo(treeID: tree, shotType: .fullTree, moderationState: .approved, capturedAt: at) }

        func delta(_ rows: [Photo]) -> RemoteAPI.TreeCommunityDelta {
            RemoteAPI.TreeCommunityDelta(
                treeID: tree,
                photos: rows,
                ownPhotoIDs: Set(rows.map(\.id)),
                deletablePhotoIDs: Set(rows.map(\.id)),
                clientUUIDs: Dictionary(uniqueKeysWithValues: rows.map { ($0.id, UUID()) })
            )
        }

        let sent = PhotoIdentityEvidence(sent: [first.id, second.id], withdrawing: [])
        let both = RoutedAPI.communityPhotosNotOnThisPhone(
            delta(Array(copies.prefix(2))), onThisPhone: [first, second], evidence: sent
        )
        #expect(both.isEmpty, "two copies of two photographs left \(both.count) behind")

        let three = RoutedAPI.communityPhotosNotOnThisPhone(delta(copies), onThisPhone: [first, second, first], evidence: sent)
        #expect(three.count == 1, "three service rows for two phone rows (one listed twice) left \(three.count)")

        // And the framing is part of the match: a leaf is not the full-tree photograph.
        let leaf = Photo(treeID: tree, shotType: .leaf, moderationState: .approved, capturedAt: at)
        let unmatched = RoutedAPI.communityPhotosNotOnThisPhone(delta([leaf]), onThisPhone: [first], evidence: sent)
        #expect(unmatched.map(\.id) == [leaf.id])
    }

    // MARK: - 8. The pill and the browser agree, through the screens' own models

    /// F30 in the tester's words: "Pill says two photos but when I click in I see only one." The
    /// pill is screen 03's model and the list is screen 20's, each loading and refreshing itself
    /// through the closure the composition root hands it — so this asserts the two screens' own
    /// answers after the refresh lands, not a profile this test assembled.
    @Test("screen 03's pill and screen 20's list count the same photographs after the refresh")
    @MainActor
    func thePillAndTheBrowserAgree() async throws {
        let transport = ScriptedTransport()
        let data = try await Self.boot(transport)
        let tree = try await Self.makeTree(data)
        let serverID = UUID()
        let strangers = UUID()

        let sent = try #require(try await Self.takeAndSendPhoto(data, transport: transport, tree: tree, serverID: serverID))
        Self.answerProfile(
            transport, tree: tree,
            rows: [
                Self.row(serverID, shotType: sent.shotType, capturedAt: sent.capturedAt, clientUUID: sent.clientUUID),
                Self.row(strangers, capturedAt: "2026-09-24T19:00:00Z"),
            ],
            own: [serverID]
        )

        let profileModel = TreeProfileModel(treeID: tree.id, api: data.api, refreshProfile: data.refreshTreeProfile)
        await profileModel.load()
        await profileModel.profileRefresh?.value
        let pill = try #require(profileModel.presentation?.heroMetaPill, "screen 03 drew no pill")

        let browser = TreePhotosModel(treeID: tree.id, api: data.api, refreshProfile: data.refreshTreeProfile)
        await browser.load()
        await browser.profileRefresh?.value

        #expect(browser.photos.map(\.id).contains(strangers), "the refresh never reached screen 20")
        #expect(
            pill.hasPrefix("\(browser.photos.count) photos"),
            "screen 03's pill reads \(pill); screen 20 lists \(browser.photos.count)"
        )
        #expect(browser.photos.count == 3, "the add-a-tree photograph, the visit's, and the stranger's")
    }

    // MARK: - 9. A withdrawal names the photograph the way the service can find it

    /// The photograph the queued `photo_withdrawal` names, read off the queue the drain will send.
    private static func withdrawalNames(_ data: DataLayer) async throws -> UUID {
        let records = try await data.outbox.records()
        let withdrawals = try records.compactMap { record -> PhotoWithdrawal? in
            guard record.item.kind == .photoWithdrawal else { return nil }
            guard case let .photoWithdrawal(value) = try OutboxPayload.decode(
                kind: record.item.kind, from: record.item.payload
            ) else { return nil }
            return value
        }
        #expect(withdrawals.count == 1, "fixture: expected exactly one queued withdrawal, found \(withdrawals.count)")
        return try #require(withdrawals.first).photoID
    }

    /// A photograph sent by build 77 or earlier: its local id is unknown to the service and its key
    /// is gone from the phone, so a withdrawal by the local id matched nothing and it stayed public.
    /// Once a refresh has paired it, the withdrawal names the service's row.
    @Test("withdrawing an earlier build's photograph names the service's row for it")
    @MainActor
    func withdrawingAnEarlierBuildsPhotographNamesTheServiceRow() async throws {
        let transport = ScriptedTransport()
        let data = try await Self.boot(transport)
        let tree = try await Self.makeTree(data)
        let serverID = UUID()

        // `trunk`, so nothing about the tree's own add-a-tree photograph (`full_tree`, taken a moment
        // earlier, and never sent) bears on the pairing.
        let sent = try #require(try await Self.takeAndSendPhoto(
            data, transport: transport, tree: tree, serverID: serverID, shotType: .trunk
        ))
        #expect(sent.shotType == "trunk")
        Self.answerProfile(
            transport, tree: tree,
            rows: [Self.row(serverID, shotType: sent.shotType, capturedAt: sent.capturedAt, clientUUID: UUID())],
            own: [serverID]
        )
        _ = try await Self.refreshed(data, tree: tree)

        _ = try await data.api.deletePhoto(id: sent.clientUUID)

        let named = try await Self.withdrawalNames(data)
        #expect(
            named == serverID,
            """
            the withdrawal names \(named), not the service's \(serverID) — the service has never heard \
            of this photograph's local id, so it would withdraw nothing and the photograph stays public
            """
        )
        let onThePhone = try await Self.localPhotoIDs(data, tree: tree)
        #expect(!onThePhone.contains(sent.clientUUID), "the photograph was not withdrawn on the phone")
    }

    /// With no refresh this process, nothing is known, and the withdrawal names the phone's id —
    /// which for a photograph sent since F30's fix is the key the service withdraws by.
    @Test("with no refresh, a withdrawal names the phone's id, which is the begin's key")
    @MainActor
    func withNoRefreshAWithdrawalNamesThePhonesID() async throws {
        let transport = ScriptedTransport()
        let data = try await Self.boot(transport)
        let tree = try await Self.makeTree(data)

        let sent = try #require(try await Self.takeAndSendPhoto(data, transport: transport, tree: tree, serverID: UUID()))
        _ = try await data.api.deletePhoto(id: sent.clientUUID)

        #expect(try await Self.withdrawalNames(data) == sent.clientUUID)
    }

    /// Two photographs from one visit with the same framing share a capture second, so their service
    /// copies pair either way round. Naming one would risk withdrawing the photograph the person
    /// kept, so neither is named: the withdrawal carries the phone's id.
    @Test("an ambiguous pair is folded for display but never named in a withdrawal")
    @MainActor
    func anAmbiguousPairIsNeverNamed() async throws {
        let transport = ScriptedTransport()
        let data = try await Self.boot(transport)
        let tree = try await Self.makeTree(data)

        let first = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("pids-a-\(UUID().uuidString).jpg")
        let second = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("pids-b-\(UUID().uuidString).jpg")
        try Self.jpeg().write(to: first)
        try Self.jpeg().write(to: second)
        let visit = Visit(treeID: tree.id, attribution: Attribution.anonymous(deviceID: data.deviceID), capturedAt: Date())
        _ = try await data.outbox.enqueue(
            .visit(visit),
            photos: [OutboxPhoto(path: first.path, shotType: .trunk), OutboxPhoto(path: second.path, shotType: .trunk)]
        )
        transport.answer("POST /sync", with: #"{"results":[{"client_uuid":"\#(visit.clientUUID.uuidString)","status":"applied"}]}"#)
        // Both are sent. The profile below answers with keys this phone never minted, which is what
        // an earlier build's copies look like: the only link left is the framing and the second.
        let serverID = UUID()
        let destination = URL(string: "https://storage.invalid/photos/\(UUID().uuidString).jpg")!
        StubStorageProtocol.park(destination)
        transport.answer(
            "POST /photos/begin",
            with: #"{"photo_id":"\#(serverID.uuidString)","presigned_put_url":"\#(destination.absoluteString)","moderation_state":"approved"}"#
        )
        transport.answer("POST /photos/\(serverID.uuidString)/received", with: #"{"received":true}"#)
        let report = try await data.outbox.drain(photoUploadsAllowed: true)
        #expect(report.photosSent == 2, "fixture: both photographs must have left the phone")

        let local = try await data.local.treeProfile(id: tree.id).photos.items.filter { $0.visitID == visit.id }
        #expect(local.count == 2, "fixture: two photographs on one visit")
        let capturedAt = ISO8601DateFormatter().string(from: try #require(local.first).capturedAt)
        #expect(Set(local.map(\.capturedAt)).count == 1, "fixture: the pair must share a capture time")

        let copies = [UUID(), UUID()]
        Self.answerProfile(
            transport, tree: tree,
            rows: copies.map { Self.row($0, shotType: "trunk", capturedAt: capturedAt, clientUUID: UUID()) },
            own: copies
        )
        let profile = try await Self.refreshed(data, tree: tree)
        #expect(Set(profile.visiblePhotos.items.map(\.id)).isDisjoint(with: copies), "the pair was not folded for display")

        let withdrawn = try #require(local.first)
        _ = try await data.api.deletePhoto(id: withdrawn.id)
        let named = try await Self.withdrawalNames(data)
        #expect(!copies.contains(named), "an ambiguous pair's service row was named: \(named)")
        #expect(named == withdrawn.id)
    }

    /// The pairing rule for naming, on its own: unique pairs are named, a shared capture second is not.
    @Test("only unambiguous earlier-build pairs are named")
    func onlyUnambiguousPairsAreNamed() throws {
        let tree = UUID()
        let at = Date(timeIntervalSince1970: 1_790_000_000)
        let alone = Photo(treeID: tree, shotType: .leaf, capturedAt: at.addingTimeInterval(-600))
        let twinA = Photo(treeID: tree, shotType: .fullTree, capturedAt: at)
        let twinB = Photo(treeID: tree, shotType: .fullTree, capturedAt: at)
        let aloneCopy = Photo(treeID: tree, shotType: .leaf, moderationState: .approved, capturedAt: alone.capturedAt)
        let twinCopies = (0..<2).map { _ in Photo(treeID: tree, shotType: .fullTree, moderationState: .approved, capturedAt: at) }
        let rows = [aloneCopy] + twinCopies
        let delta = RemoteAPI.TreeCommunityDelta(
            treeID: tree, photos: rows,
            ownPhotoIDs: Set(rows.map(\.id)), deletablePhotoIDs: Set(rows.map(\.id)),
            clientUUIDs: Dictionary(uniqueKeysWithValues: rows.map { ($0.id, UUID()) })
        )
        let matched = RoutedAPI.photoIdentityMatch(
            delta, onThisPhone: [alone, twinA, twinB],
            evidence: PhotoIdentityEvidence(sent: [alone.id, twinA.id, twinB.id], withdrawing: [])
        )
        #expect(matched.added.isEmpty, "every copy should fold for display")
        #expect(matched.serviceIDs == [alone.id: aloneCopy.id], "named: \(matched.serviceIDs)")
    }

    // MARK: - 10. Review of #194: only a photograph that has left the phone may be paired

    /// Every queued `photo_withdrawal`, in queue order, as each names its photograph.
    private static func queuedWithdrawals(_ data: DataLayer) async throws -> [PhotoWithdrawal] {
        try await data.outbox.records().compactMap { record -> PhotoWithdrawal? in
            guard record.item.kind == .photoWithdrawal else { return nil }
            guard case let .photoWithdrawal(value) = try OutboxPayload.decode(
                kind: record.item.kind, from: record.item.payload
            ) else { return nil }
            return value
        }
    }

    /// Finding 1, in the reviewer's own shape. This phone's `trunk` photograph has not been sent (its
    /// begin failed), so the service has no copy of it. The account's other phone sent a `trunk` of
    /// the same tree in the same second. That one must be drawn, and withdrawing this phone's must
    /// never name it — the service would take it down, because the account owns it.
    @Test("another phone's photograph is neither hidden nor named by an unsent one")
    @MainActor
    func anUnsentPhotographNeverPairs() async throws {
        let transport = ScriptedTransport()
        let data = try await Self.boot(transport)
        let tree = try await Self.makeTree(data)

        _ = try await Self.takeAndSendPhoto(
            data, transport: transport, tree: tree, serverID: UUID(), beginSucceeds: false, shotType: .trunk
        )
        let unsent = try #require(
            try await data.local.treeProfile(id: tree.id).photos.items.first { $0.shotType == .trunk },
            "fixture: the unsent trunk photograph is not on the phone"
        )
        let addATree = try #require(
            try await data.local.treeProfile(id: tree.id).photos.items.first { $0.shotType == .fullTree },
            "fixture: the add-a-tree photograph is not on the phone"
        )

        // The other phone's two rows: one in the unsent photograph's second, one in the add-a-tree
        // photograph's. Both are this account's, so both carry a key — one this phone never minted.
        let stamp = ISO8601DateFormatter()
        let otherTrunk = UUID()
        let otherFullTree = UUID()
        Self.answerProfile(
            transport, tree: tree,
            rows: [
                Self.row(otherTrunk, shotType: "trunk", capturedAt: stamp.string(from: unsent.capturedAt), clientUUID: UUID()),
                Self.row(otherFullTree, shotType: "full_tree", capturedAt: stamp.string(from: addATree.capturedAt), clientUUID: UUID()),
            ],
            own: [otherTrunk, otherFullTree]
        )
        let profile = try await Self.refreshed(data, tree: tree)
        let shown = Set(profile.visiblePhotos.items.map(\.id))
        #expect(
            shown.contains(otherTrunk),
            "the account's other phone's photograph \(otherTrunk) was folded into this phone's unsent one — hidden"
        )
        #expect(
            shown.contains(otherFullTree),
            "the account's other phone's photograph \(otherFullTree) was folded into the add-a-tree photograph, which is never sent — hidden"
        )

        _ = try await data.api.deletePhoto(id: unsent.id)
        _ = try await data.api.deletePhoto(id: addATree.id)
        let named = try await Self.queuedWithdrawals(data).map(\.photoID)
        #expect(
            named == [unsent.id, addATree.id],
            """
            withdrawing this phone's unsent and add-a-tree photographs queued withdrawals naming \
            \(named) — a service id there is the OTHER phone's photograph, and it would be deleted \
            (unsent \(unsent.id), add-a-tree \(addATree.id), other phone \(otherTrunk), \(otherFullTree))
            """
        )
    }

    // MARK: - 11. Review of #194: the copy is in the second its stamp names

    /// Finding 2, the reviewer's reproduction. The wire truncates to whole seconds, so a local row at
    /// `t + 0.999` has its copy stamped `t`. The row stamped `t + 1` is a distinct photograph, 0.001 s
    /// away, and must be drawn — and the true copy must fold, and be the one named.
    @Test("a copy is paired in the second its stamp names, never the next one")
    func theCopyIsInTheSecondItsStampNames() throws {
        let tree = UUID()
        let base = Date(timeIntervalSince1970: 1_790_000_000)
        let local = Photo(treeID: tree, shotType: .trunk, capturedAt: base.addingTimeInterval(0.999))
        let copy = Photo(treeID: tree, shotType: .trunk, moderationState: .approved, capturedAt: base)
        let next = Photo(treeID: tree, shotType: .trunk, moderationState: .approved, capturedAt: base.addingTimeInterval(1))
        func delta(_ rows: [Photo]) -> RemoteAPI.TreeCommunityDelta {
            RemoteAPI.TreeCommunityDelta(
                treeID: tree, photos: rows,
                ownPhotoIDs: Set(rows.map(\.id)), deletablePhotoIDs: Set(rows.map(\.id)),
                clientUUIDs: Dictionary(uniqueKeysWithValues: rows.map { ($0.id, UUID()) })
            )
        }
        let sent = PhotoIdentityEvidence(sent: [local.id], withdrawing: [])

        let alone = RoutedAPI.photoIdentityMatch(delta([copy]), onThisPhone: [local], evidence: sent)
        #expect(alone.added.isEmpty, "the truncated-second copy did not fold")

        // `captured_at DESC` is the service's order, so the later row comes first.
        let both = RoutedAPI.photoIdentityMatch(delta([next, copy]), onThisPhone: [local], evidence: sent)
        #expect(
            both.added.map(\.id) == [next.id],
            """
            the DISTINCT photograph (next, t+1 s) was folded and the local photograph's own copy was \
            added as a double: added=\(both.added.map(\.id)) copy=\(copy.id) next=\(next.id)
            """
        )
        #expect(both.serviceIDs == [local.id: copy.id], "named: \(both.serviceIDs) (copy=\(copy.id), next=\(next.id))")
    }

    // MARK: - 12. Review of #194: hidden only while the withdrawal is on its way

    /// Answers the one queued withdrawal `applied` and drains it, as the service would.
    private static func drainWithdrawal(_ data: DataLayer, transport: ScriptedTransport) async throws {
        let withdrawal = try #require(try await Self.queuedWithdrawals(data).last, "fixture: nothing queued")
        transport.answer(
            "POST /sync",
            with: #"{"results":[{"client_uuid":"\#(withdrawal.clientUUID.uuidString)","status":"applied"}]}"#
        )
        _ = try await data.outbox.drain(photoUploadsAllowed: true)
        let pending = try await data.outbox.records().filter {
            $0.item.kind == .photoWithdrawal && !$0.item.state.isTerminal
        }
        #expect(pending.isEmpty, "fixture: the withdrawal is still queued after the drain")
    }

    /// Finding 3, as ruled. A withdrawal hides the service's copy only while it is queued. Once the
    /// service has answered it, a copy it still serves is still public — so its contributor sees it,
    /// and can delete it again, by the service's id.
    @Test("a copy is hidden only while its withdrawal is queued, and can be withdrawn again after")
    @MainActor
    func aCopyIsHiddenOnlyWhileItsWithdrawalIsQueued() async throws {
        let transport = ScriptedTransport()
        let data = try await Self.boot(transport)
        let tree = try await Self.makeTree(data)
        let serverID = UUID()

        let sent = try #require(try await Self.takeAndSendPhoto(data, transport: transport, tree: tree, serverID: serverID))
        _ = try await data.api.deletePhoto(id: sent.clientUUID)
        let copy = Self.row(serverID, shotType: sent.shotType, capturedAt: sent.capturedAt, clientUUID: sent.clientUUID)

        // Queued: the withdrawal is on its way, so the copy stays hidden.
        Self.answerProfile(transport, tree: tree, rows: [copy], own: [serverID])
        let queued = Set(try await Self.refreshed(data, tree: tree).visiblePhotos.items.map(\.id))
        #expect(!queued.contains(serverID), "the copy of a photograph whose withdrawal is queued came back: \(queued)")

        // Answered, and the service still serves it: it is still public, so it shows.
        try await Self.drainWithdrawal(data, transport: transport)
        let answered = Set(try await Self.refreshed(data, tree: tree).visiblePhotos.items.map(\.id))
        #expect(
            answered.contains(serverID),
            "a photograph still public on the service (\(serverID)) is hidden from its own contributor after its withdrawal was answered: \(answered)"
        )

        // And it can be withdrawn again, by the only id the service has for it.
        _ = try await data.api.deletePhoto(id: serverID)
        let again = try #require(try await Self.queuedWithdrawals(data).last)
        #expect(again.photoID == serverID, "the second withdrawal names \(again.photoID), not the service's \(serverID)")
        #expect(again.treeID == tree.id)
        let rehidden = Set(try await Self.refreshed(data, tree: tree).visiblePhotos.items.map(\.id))
        #expect(!rehidden.contains(serverID), "the copy came back while its second withdrawal is queued")
    }

    /// The reviewer's case B: a photograph an earlier build sent and this phone withdrew by its own
    /// id, which the service has never heard of. Nothing is on its way to take the copy down, so it
    /// shows — even while that withdrawal is still queued.
    @Test("an earlier build's withdrawn but still public photograph shows to its contributor")
    @MainActor
    func anEarlierBuildsStillPublicPhotographShows() async throws {
        let transport = ScriptedTransport()
        let data = try await Self.boot(transport)
        let tree = try await Self.makeTree(data)
        let serverID = UUID()

        let sent = try #require(try await Self.takeAndSendPhoto(
            data, transport: transport, tree: tree, serverID: serverID, shotType: .trunk
        ))
        _ = try await data.local.deletePhoto(id: sent.clientUUID)
        Self.answerProfile(
            transport, tree: tree,
            rows: [Self.row(serverID, shotType: sent.shotType, capturedAt: sent.capturedAt, clientUUID: UUID())],
            own: [serverID]
        )
        let shown = Set(try await Self.refreshed(data, tree: tree).visiblePhotos.items.map(\.id))
        #expect(
            shown.contains(serverID),
            "a photograph still public on the service (\(serverID)) is hidden from its own contributor because it folded into their withdrawn row"
        )
    }

    // MARK: - 13. Review of #194: a photograph refused for good has not left the phone either

    /// Finding 1 again, reached through a **non-retryable** refusal. The service refused this phone's
    /// `trunk` photograph's begin for good (`not_found`), so it has no copy of it. The drain gives
    /// the binary up and deletes its queue row, and a photograph with no queue row used to read as
    /// sent. The account's other phone sent a `trunk` of the same tree in the same second. That one
    /// must be drawn, and withdrawing this phone's must never name it.
    @Test("another phone's photograph is neither hidden nor named by one whose send was refused for good")
    @MainActor
    func aRefusedPhotographNeverPairs() async throws {
        let transport = ScriptedTransport()
        let data = try await Self.boot(transport)
        let tree = try await Self.makeTree(data)

        _ = try await Self.takeAndSendPhoto(
            data, transport: transport, tree: tree, serverID: UUID(),
            beginSucceeds: false, beginFailure: .notFound, shotType: .trunk
        )
        let refused = try #require(
            try await data.local.treeProfile(id: tree.id).photos.items.first { $0.shotType == .trunk },
            "fixture: the refused trunk photograph is not on the phone"
        )

        // The premise: the refusal was terminal, and it took the queue row with it. If either is
        // false this is the retryable case, which `anUnsentPhotographNeverPairs` already covers.
        let visit = try #require(
            try await data.outbox.records().first { $0.item.kind == .visit },
            "fixture: the visit that carried the photograph is not in the queue"
        )
        #expect(visit.item.state == .failed, "fixture: the item is \(visit.item.state), so the refusal was not terminal")
        #expect(visit.item.lastErrorCode == .notFound, "fixture: the item carries \(String(describing: visit.item.lastErrorCode))")
        let outstanding = try await data.store.queue.read { connection in
            try OutboxStore().outstandingPhotoCount(for: visit.id, connection: connection)
        }
        #expect(outstanding == 0, "fixture: the refused binary is still queued, so its send still reads as owed")

        let stamp = ISO8601DateFormatter()
        let otherTrunk = UUID()
        Self.answerProfile(
            transport, tree: tree,
            rows: [
                Self.row(otherTrunk, shotType: "trunk", capturedAt: stamp.string(from: refused.capturedAt), clientUUID: UUID()),
            ],
            own: [otherTrunk]
        )
        let shown = Set(try await Self.refreshed(data, tree: tree).visiblePhotos.items.map(\.id))
        #expect(
            shown.contains(otherTrunk),
            "the account's other phone's photograph \(otherTrunk) was folded into this phone's refused one — hidden"
        )

        _ = try await data.api.deletePhoto(id: refused.id)
        let named = try await Self.queuedWithdrawals(data).map(\.photoID)
        #expect(
            named == [refused.id],
            """
            withdrawing this phone's refused photograph queued withdrawals naming \(named) — a service \
            id there is the OTHER phone's photograph \(otherTrunk), and it would be deleted \
            (refused \(refused.id))
            """
        )
    }
}
