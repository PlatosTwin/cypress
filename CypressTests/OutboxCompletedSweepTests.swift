//
//  OutboxCompletedSweepTests.swift
//  CypressTests
//
//  ROADMAP 184: finished Outbox rows are swept. `OutboxQueue.pruneCompleted` deletes `done` rows
//  older than `OutboxQueue.completedRetention` (a day), and no build called it until
//  `DataLayer.boot` did, once per launch. These cases go through that launch, over a database file,
//  and through the two readers whose answer changes when a `done` row goes: the one-time send of a
//  community tree (`CommunityTreeBackfill`), and a namer's correction on somebody else's tree
//  (`LocalAPI.localSpeciesAnswers`, ROADMAP 185).
//

#if DEBUG
import Foundation
import Testing
@testable import Cypress

@Suite("Outbox · finished rows are swept at launch (ROADMAP 184)")
struct OutboxCompletedSweepTests {

    private static func temporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cypress-184-sweep-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func boot(_ url: URL, _ access: RemoteAccess = .disabled) async throws -> DataLayer {
        try await DataLayer.boot(
            databaseURL: url, seedURL: nil,
            baseURL: URL(string: "https://cypress-sync.invalid/api/v1")!,
            transport: access.allowsNetwork ? ScriptedTransport() : nil,
            remoteAccess: access,
            credentials: InMemoryCredentialStore(),
            storageSession: StubStorageProtocol.session()
        )
    }

    /// Queues one favorite, applied here, then sets its state and its `updated_at`.
    private static func row(
        _ state: OutboxItem.State,
        updatedAt: Date,
        device: UUID,
        connection: SQLiteConnection
    ) throws -> UUID {
        let item = try OutboxPayload.favoriteToggle(
            FavoriteToggle(owner: .device(device), treeID: UUID(), isFavorite: true, occurredAt: updatedAt)
        ).makeItem(createdAt: updatedAt)
        #expect(try OutboxStore().enqueueLocallyApplied(item, connection: connection), "fixture: the row was not queued")
        let statement = try connection.cachedStatement(
            "UPDATE outbox SET state = :state, updated_at = :at WHERE id = :id"
        )
        _ = try statement.bind([":state": state.rawValue, ":at": updatedAt, ":id": item.id])
        try statement.run()
        _ = try statement.reset()
        return item.id
    }

    /// The launch removes a `done` row older than a day and keeps everything else: a newer `done`
    /// row, and a pending, uploading or failed row however old.
    ///
    /// Red-proof: remove `_ = try? await outbox.pruneCompleted()` from `DataLayer.boot` — red on
    /// "a done row older than a day is still in the outbox after a launch".
    @Test("a launch sweeps done rows older than a day, and keeps newer done rows and every unfinished row")
    func theLaunchSweepsOldDoneRows() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("cypress.sqlite")

        let first = try await Self.boot(url)
        let now = Date()
        let hour: TimeInterval = 3600
        let month = 30 * 24 * hour
        let device = first.deviceID
        let ids = try await first.store.queue.write { connection in
            (
                oldDone: try Self.row(.done, updatedAt: now.addingTimeInterval(-25 * hour), device: device, connection: connection),
                newDone: try Self.row(.done, updatedAt: now.addingTimeInterval(-23 * hour), device: device, connection: connection),
                oldPending: try Self.row(.pending, updatedAt: now.addingTimeInterval(-month), device: device, connection: connection),
                oldUploading: try Self.row(.uploading, updatedAt: now.addingTimeInterval(-month), device: device, connection: connection),
                oldFailed: try Self.row(.failed, updatedAt: now.addingTimeInterval(-month), device: device, connection: connection)
            )
        }
        let before = Set(try await first.outbox.records().map(\.id))
        #expect(before.contains(ids.oldDone), "fixture: the old done row is not there before the launch")

        let second = try await Self.boot(url)
        let after = Set(try await second.outbox.records().map(\.id))
        #expect(!after.contains(ids.oldDone), "a done row older than a day is still in the outbox after a launch")
        #expect(after.contains(ids.newDone), "a done row from the last day was swept")
        #expect(after.contains(ids.oldPending), "a pending row was swept")
        // `recoverInterrupted` turns the uploading row back to pending at the same launch; it stays.
        #expect(after.contains(ids.oldUploading), "an uploading row was swept")
        #expect(after.contains(ids.oldFailed), "a failed row was swept")
        #expect(after.count == 4, "the launch removed \(before.count - after.count) rows, not one")
    }

    /// The reader that changes most: the one-time send of a tree an older build added. Its `done`
    /// add row made the backfill leave the tree alone ("a done row is seen again once it is
    /// pruned"), and with no sweep it was never seen again, so its add photo never went. With the
    /// sweep, the launch that removes the row queues the tree's add again (the service answers
    /// `duplicate`) with the add photo on it, and writes the tree's key.
    ///
    /// Red-proof: remove `_ = try? await outbox.pruneCompleted()` from `DataLayer.boot` — red on
    /// "the launch did not send the add photo of a tree whose done add row is a day old".
    @Test("a launch that sweeps an older build's done add row sends that tree's add photo once")
    func theSweptAddRowLetsTheBackfillSendTheAddPhoto() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("cypress.sqlite")

        let first = try await Self.boot(url)
        let tree = try await first.local.addTree(TreeDraft(
            coordinate: LocationCorrectionTests.offshore,
            photoLocalPath: try CommunityTreeBackfillTests.jpeg(in: directory),
            attribution: .anonymous(deviceID: first.deviceID)
        ))
        // As an older build left it: the add was sent and settled `done` a day and an hour ago, its
        // add photo was never staged, and no key was written.
        let dayAndAnHourAgo = Date().addingTimeInterval(-25 * 3600)
        try await first.store.queue.write { connection in
            try connection.execute("DELETE FROM outbox_photos")
            let settle = try connection.cachedStatement(
                "UPDATE outbox SET state = 'done', remote_sent = 1, updated_at = :at WHERE kind = 'add_tree'"
            )
            _ = try settle.bind(dayAndAnHourAgo, forName: ":at")
            try settle.run()
            _ = try settle.reset()
            try connection.execute(
                "DELETE FROM app_state WHERE key LIKE '\(CommunityTreeStore.queuedOnceKeyPrefix)%'"
            )
        }
        let oldAdd = try #require(try await first.outbox.records().first { $0.item.kind == .addTree })
        #expect(oldAdd.item.state == .done, "fixture: the add row is not done")

        let live = try await Self.boot(url, .live)
        let rows = try await live.outbox.records()
        #expect(!rows.contains { $0.id == oldAdd.id }, "the done add row was not swept")
        let add = try #require(
            rows.first { $0.item.kind == .addTree },
            "the launch did not send the add photo of a tree whose done add row is a day old: \(rows.map(\.item.kind))"
        )
        #expect(add.item.clientUUID == oldAdd.item.clientUUID, "the new add is not under the tree's own key")
        let staged = try await live.store.queue.read { try OutboxStore().sendablePhotos(for: add.id, connection: $0) }
        #expect(staged.count == 1, "the add photo is not on the new add: \(staged.count)")
        #expect(try await live.store.queue.read { try CommunityTreeBackfill.isQueued(treeID: tree.id, connection: $0) },
                "the tree's key was not written")

        // Once: the next launch queues nothing more.
        let again = try await Self.boot(url, .live)
        #expect(try await again.outbox.records().filter { $0.item.kind == .addTree }.count == 1)
    }

    /// ROADMAP 185. The namer's correction that the service applied to nobody stays on the namer's
    /// profile while the correction's `done` row lives, because `localSpeciesAnswers` reads its
    /// `updated_at` as the moment the service accepted it. The sweep bounds that: once the row is
    /// older than a day, the sweep removes it, and the profile shows the cache's species.
    ///
    /// Red-proof: make `OutboxStore.pruneCompleted` delete nothing (`AND 0`) — red on "the namer's
    /// correction is still shown after the sweep".
    @Test("a namer's correction the service applied to nobody leaves the namer's profile once its row is a day old and swept")
    func theSweepEndsANamersStaleCorrection() async throws {
        let store = try await OthersTreeControlsTests.seededStore()
        let api = LocalAPI(store: store, deviceID: OthersTreeControlsTests.readerDevice)
        try await OthersTreeControlsTests.signIn(api)
        let plane = try await OthersTreeControlsTests.plane(api)
        let oak = try await OthersTreeControlsTests.oak(api, besides: plane)
        let id = try await OthersTreeControlsTests.cached(api, species: nil)
        let day = { (n: Double) in Date(timeIntervalSince1970: 1_790_000_000 + n * 86_400) }

        // The namer names it plane; it is accepted, and a page serves plane.
        _ = try await api.claimSpecies(treeID: id, speciesID: plane.id)
        try await OthersTreeControlsTests.acceptEverything(store, at: day(1))
        try await OthersTreeControlsTests.serve(api, store, id: id, species: plane.id, at: day(2))
        // The namer corrects it to oak, and the service records the correction at day 3 and
        // applies it to nobody (the adder kept plane first), so no page brings the tree again.
        _ = try await api.correctSpecies(treeID: id, speciesID: oak.id)
        try await OthersTreeControlsTests.acceptEverything(store, at: day(3))

        func sweep(at moment: Date) async throws {
            _ = try await OutboxQueue(
                queue: store.queue, apply: APIOutboxTransport(api: api), now: { moment }
            ).pruneCompleted()
        }

        // Inside the day: the row stays, and the namer still sees their correction.
        try await sweep(at: day(3).addingTimeInterval(23 * 3600))
        var profile = try await api.treeProfile(id: id)
        #expect(profile.species?.id == oak.id, "calibration: the namer's correction is not shown inside the day")
        #expect(profile.speciesCorrection == .correctable, "\(profile.speciesCorrection)")

        // A day and a minute after the service accepted it: the sweep removes the row, and the
        // cache's species is on the profile.
        try await sweep(at: day(4).addingTimeInterval(60))
        profile = try await api.treeProfile(id: id)
        #expect(profile.species?.id == plane.id, "the namer's correction is still shown after the sweep: \(String(describing: profile.species?.id))")
        #expect(profile.speciesCorrection == .reportable, "\(profile.speciesCorrection)")
    }
}
#endif
