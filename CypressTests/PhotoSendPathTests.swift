import Foundation
import Testing
@testable import Cypress

/// The photo **send** path — `AppSchema` v18 and the sink ERRATA **E264** said could not be built.
///
/// ── What every test here asserts, and what none of them asserts ────────────────────────────────
///
/// The property under test is always **whether a binary actually left, and whether the row says so
/// truthfully**. Never `outbox_photos.state` on its own: a drain that marked every binary `applied`
/// and sent nothing would satisfy a state assertion perfectly, and that is precisely the false green
/// this project's rules are written against. So the questions are "what was the send sink offered",
/// "did the item settle", and "is the photograph still outstanding" — three facts that cannot all be
/// right while the path is broken.
///
/// ── The `#expect` hang, which bites exactly here ───────────────────────────────────────────────
///
/// `#expect(dataA == dataB)` on two large `Data` values hangs in Swift Testing's diff (CLAUDE.md).
/// Photo tests are where that lives, so nothing below compares binaries; the bytes are compared as a
/// `Bool` before the macro sees them.
@Suite(.serialized)
struct PhotoSendPathTests {

    static let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-0000000005E4")!

    private static func stagedFile(_ name: String) throws -> String {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cypress-send-\(name)-\(UUID().uuidString).jpg")
        try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: url)
        return url.path
    }

    private static func visit() -> Visit {
        Visit(
            treeID: UUID(),
            attribution: Attribution.anonymous(deviceID: deviceID),
            capturedAt: Date()
        )
    }

    // MARK: - 1. The headline: a binary reaches the send sink and the item settles

    @Test("a staged binary is applied locally, then sent, and only then is the item done")
    func aBinaryIsAppliedThenSent() async throws {
        let store = try await CypressStore.inMemory()
        let apply = OutboxTestSupport.ScriptedTransport(script: .allSucceed)
        let send = OutboxTestSupport.ScriptedSendSink(script: .allSucceed)
        let queue = OutboxQueue(queue: store.queue, apply: apply, send: send)

        let path = try Self.stagedFile("headline")
        _ = try await queue.enqueue(.visit(Self.visit()), photos: [OutboxPhoto(path: path, shotType: .fullTree)])

        let report = try await queue.drain()

        #expect(report.photosSent == 1, "the send sink was never handed the binary")
        let offered = await send.sentPhotos
        #expect(offered.count == 1, "the send sink saw \(offered.count) binaries")

        // The source it was given is the *container* copy, not the staged file. The apply consumes
        // the staged one, so a send reading `path` would be reading something that is gone — which
        // is the first of E264's three missing pieces.
        let paths = await send.sentPhotoPaths
        #expect(paths.first != path, "the send was handed the staged path, which the apply consumed")
        #expect(paths.count == 1)

        let record = try #require(try await queue.records().first)
        #expect(record.item.state == .done, "the item is \(record.item.state)")
        #expect(record.item.photos.isEmpty, "a sent binary is still listed as staged")
    }

    // MARK: - 2. A refused binary does not take its note down with it

    /// The answer to the third question ERRATA **E264** left open — "whether a binary that failed to
    /// send should hold its row out of `done`" — is **no** for the note and **yes** for the row.
    ///
    /// The note is a contribution in its own right: applied locally, and by this point accepted by
    /// the service. Failing the whole item over a photograph would put it back in the retry window,
    /// whose 48 h cap eventually expires *everything* — losing the note to protect the picture. What
    /// must not happen instead is the item settling `done` while a binary never left, so the row
    /// stays outstanding and the item stays unsettled.
    @Test("a binary that will not send leaves the note sent and the item unsettled")
    func aFailedBinaryDoesNotFailItsNote() async throws {
        let store = try await CypressStore.inMemory()
        let apply = OutboxTestSupport.ScriptedTransport(script: .allSucceed)
        let send = OutboxTestSupport.ScriptedSendSink(script: .photosFail)
        let queue = OutboxQueue(queue: store.queue, apply: apply, send: send)

        let path = try Self.stagedFile("refused")
        _ = try await queue.enqueue(.visit(Self.visit()), photos: [OutboxPhoto(path: path, shotType: .trunk)])

        let report = try await queue.drain()

        #expect(report.sent == 1, "the note did not go, so this proves nothing about the binary")
        #expect(report.photosFailed == 1, "the failed binary was not counted")

        let record = try #require(try await queue.records().first)
        #expect(record.remoteSent, "the note was sent; nothing about the photograph changes that")
        #expect(record.item.state != .done, "the item settled while its photograph had not been sent")

        // The row is still outstanding, which is *why* the item cannot settle. Asserting the
        // consequence and the mechanism together, because the consequence alone would also hold if
        // the drain had failed the item outright — which is the behavior this test rules out above.
        let outstanding = try await store.queue.read { connection in
            try OutboxStore().outstandingPhotoCount(for: record.id, connection: connection)
        }
        #expect(outstanding == 1, "the binary stopped being outstanding without having been sent")
    }

    // MARK: - 3. R77: a binary the migration carried over never travels

    /// RULINGS **R77**, in the drain rather than in the migration: "no retroactive photo upload, not
    /// now and not as a later phase of the photo send-path work."
    ///
    /// The binary is marked `sendable = 0` exactly as `AppSchema` v18 marks the ones it migrates.
    /// It must still be **applied** — dropping it would lose a contribution — and it must never be
    /// offered to the send sink. It must also not strand its item: a local-only binary left
    /// `applied` forever would hold `photos_outstanding` above zero and keep the mutation on screen
    /// 17 permanently, for a rule the contributor cannot see and did not choose.
    @Test("a binary staged before the send path is applied, never sent, and does not strand its item")
    func aLocalOnlyBinaryIsAppliedButNeverSent() async throws {
        let store = try await CypressStore.inMemory()
        let apply = OutboxTestSupport.ScriptedTransport(script: .allSucceed)
        let send = OutboxTestSupport.ScriptedSendSink(script: .allSucceed)
        let queue = OutboxQueue(queue: store.queue, apply: apply, send: send)

        let path = try Self.stagedFile("r77")
        let item = try await queue.enqueue(
            .visit(Self.visit()), photos: [OutboxPhoto(path: path, shotType: .fullTree)]
        )
        // What v18 does to everything already queued when it runs.
        try await store.queue.write { connection in
            try connection.execute("UPDATE outbox_photos SET sendable = 0")
        }

        let report = try await queue.drain()

        let uploaded = await apply.uploadedPhotoPaths
        #expect(uploaded == [path], "a local-only binary must still be committed to this device")
        #expect(report.photosSent == 0, "a pre-send-path binary was uploaded; R77 forbids exactly this")
        let offered = await send.sentPhotos
        #expect(offered.isEmpty, "the send sink was offered \(offered.count) binaries it must never see")

        let record = try #require(try await queue.records().first)
        #expect(record.item.state == .done, "a local-only binary stranded its item at \(record.item.state)")
        let outstanding = try await store.queue.read { connection in
            try OutboxStore().outstandingPhotoCount(for: item.id, connection: connection)
        }
        #expect(outstanding == 0, "the local-only binary is still outstanding and will never clear")
    }

    // MARK: - 4. A photograph withdrawn between the apply and the send is not published

    /// The window that only exists once there are two sinks: the contributor deletes the photograph
    /// after it has been committed locally and before the drain sends it. ERRATA **E147** is the
    /// harm — "the person who took it has to be able to take it back" — and this is the one door
    /// that opens *after* the deletion gate has already run.
    @Test("a photograph deleted after its local commit is never sent")
    func aWithdrawnPhotographIsNotSent() async throws {
        let store = try await CypressStore.inMemory()
        let apply = OutboxTestSupport.ScriptedTransport(script: .allSucceed)
        let send = OutboxTestSupport.ScriptedSendSink(script: .photosFail)
        let queue = OutboxQueue(queue: store.queue, apply: apply, send: send)

        let path = try Self.stagedFile("withdrawn")
        _ = try await queue.enqueue(.visit(Self.visit()), photos: [OutboxPhoto(path: path, shotType: .fullTree)])

        // **Applied but not sent**, which is the window this test is about. A metered drain would
        // not do — `photoUploadsAllowed: false` defers the *apply* as well, so the binary would
        // never reach the state where a send is owed. A send that fails is what leaves it there,
        // and it is also what happens on a real phone with no signal.
        _ = try await queue.drain()
        let offeredBeforeDeletion = await send.sentPhotos.count

        // The photograph is tombstoned the way `ContributionStore.deletePhoto` leaves it.
        let photoID = try await store.queue.read { connection -> UUID? in
            let statement = try connection.prepare("SELECT photo_id FROM outbox_photos LIMIT 1")
            defer { statement.finalize() }
            return try statement.fetchOne { try $0.uuidIfPresent("photo_id") } ?? nil
        }
        let tombstoned = try #require(photoID, "the binary was never applied, so nothing is owed a send")
        try await store.queue.write { connection in
            try connection.execute("""
                INSERT INTO photos (id, tree_uuid, shot_type, captured_at, deleted_at, created_at, updated_at)
                VALUES ('\(tombstoned.uuidString)','\(UUID().uuidString)','full_tree',
                        '2026-08-22T00:00:00Z','2026-08-22T00:00:00Z','2026-08-22T00:00:00Z',
                        '2026-08-22T00:00:00Z')
                """)
        }

        // Now the send would succeed if it were attempted. It must not be attempted.
        await send.setScript(.allSucceed)
        let report = try await queue.drain()

        #expect(report.photosSent == 0, "a withdrawn photograph was published")
        let offeredAfter = await send.sentPhotos.count
        #expect(
            offeredAfter == offeredBeforeDeletion,
            "the send sink was offered a photograph the contributor had already deleted"
        )
    }

    // MARK: - 5. The binary's idempotency key is the row's own id

    /// Server migration 003 dedupes `POST /photos/begin` on the key the client mints, so the key has
    /// to be the same value on a retry. `OutboxPhoto.id` is minted when the shutter closes and is
    /// stored, so it survives the process — which is the whole point of it, and is what a
    /// per-drain-minted key would not do.
    @Test("the key the send carries is the binary's stored id, not one minted per attempt")
    func theIdempotencyKeyIsStable() async throws {
        let store = try await CypressStore.inMemory()
        let apply = OutboxTestSupport.ScriptedTransport(script: .allSucceed)
        let send = OutboxTestSupport.ScriptedSendSink(script: .photosFail)
        let queue = OutboxQueue(queue: store.queue, apply: apply, send: send)

        let staged = OutboxPhoto(path: try Self.stagedFile("key"), shotType: .leaf)
        _ = try await queue.enqueue(.visit(Self.visit()), photos: [staged])

        _ = try await queue.drain()
        _ = try await queue.drain()

        let offered = await send.sentPhotos
        #expect(offered.count >= 2, "the binary was not retried, so stability proves nothing")
        let keys = offered.map(\.id)
        #expect(
            offered.allSatisfy { $0.id == staged.id },
            """
            the key changed between attempts: \(keys) — a begin retried under a new key creates a \
            second photograph, which is what server migration 003 exists to stop
            """
        )
    }
}
