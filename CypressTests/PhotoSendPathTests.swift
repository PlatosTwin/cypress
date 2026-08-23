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

        // ── The assertion this test was one short of, and what its absence cost ────────────────
        //
        // Everything above is about the *sink*, and all of it stayed green while the item wedged
        // permanently: the orphaned `outbox_photos` row kept `photos_outstanding` at 1, so
        // `markDoneIfComplete` never matched, phase B3 skipped the item without recording a reason,
        // and the row sat in `uploading` forever still saying "One photo hasn't gone through yet"
        // about a photograph the contributor had deleted — with no retry affordance, because
        // `retry` requires `failed`. #116's review found it by measuring five consecutive drains.
        //
        // So the item is asserted too, and it is asserted **after more drains than one**: a single
        // drain cannot tell "settled" from "not yet reached", and the defect's whole signature was
        // that repetition changed nothing.
        for _ in 0..<4 { _ = try await queue.drain() }

        let settled = try #require(try await queue.records().first)
        let outstanding = try await store.queue.read { connection in
            try OutboxStore().outstandingPhotoCount(for: settled.id, connection: connection)
        }
        #expect(outstanding == 0, "the withdrawn photograph is still outstanding after five drains")
        #expect(
            settled.item.state == .done,
            """
            the item is \(settled.item.state) after five drains, and its reason reads \
            \(settled.item.lastError ?? "nothing") — a withdrawn photograph must not wedge the \
            mutation it rode on, and it must not leave a sentence promising a photograph in flight
            """
        )
    }

    // MARK: - 3b. R77's second gate, on its own

    /// #116's review N1: removing `AND sendable = 1` from `sendablePhotos` left the whole 1653-test
    /// suite green, because gate 1 — `settleAppliedPhoto`'s delete — had already removed the row
    /// before that statement could be reached. Documenting an uncovered guard is not covering it,
    /// and the stated reason both gates exist is that one guard is one edit away from none.
    ///
    /// So this reaches gate 2 by stepping **around** gate 1 rather than by disabling it: the binary
    /// is applied while it is still sendable, so the delete does not fire, and only then is it
    /// marked local-only. That is not a contrivance — it is the shape of the v18 migration itself,
    /// which marks rows `sendable = 0` that are already in the queue.
    @Test("a binary marked local-only after its apply is still never offered to the send sink")
    func gateTwoAloneRefusesALocalOnlyBinary() async throws {
        let store = try await CypressStore.inMemory()
        let apply = OutboxTestSupport.ScriptedTransport(script: .allSucceed)
        let send = OutboxTestSupport.ScriptedSendSink(script: .photosFail)
        let queue = OutboxQueue(queue: store.queue, apply: apply, send: send)

        _ = try await queue.enqueue(
            .visit(Self.visit()),
            photos: [OutboxPhoto(path: try Self.stagedFile("gate2"), shotType: .fullTree)]
        )

        // Applied while sendable, so gate 1 keeps the row. The send fails, which is what leaves it
        // `applied` and outstanding rather than completed.
        _ = try await queue.drain()
        let offeredBefore = await send.sentPhotos.count
        #expect(offeredBefore == 1, "fixture: gate 1 removed the row, so gate 2 is not under test")

        // Now it becomes local-only, exactly as v18 marks a pre-existing binary.
        try await store.queue.write { connection in
            try connection.execute("UPDATE outbox_photos SET sendable = 0")
        }
        await send.setScript(.allSucceed)
        let report = try await queue.drain()

        #expect(report.photosSent == 0, "gate 2 let a local-only binary through; R77 forbids it")
        #expect(
            await send.sentPhotos.count == offeredBefore,
            "the send sink was offered a binary R77 keeps on the device"
        )
    }

    // MARK: - 4b. The row says why, which is what screen 17 promises

    /// Screen 17 used to make this promise in a footnote — "Nothing here disappears silently. An
    /// item that cannot sync says so, says why, and waits for you." — which the copy audit of
    /// 2026-08-23 removed by owner ruling. **The promise is unchanged; only the screen's narration
    /// of it went**, and this test is one of the three that now carry it (see
    /// `OutboxPresentationTests.copyRules` for the other two).
    ///
    /// The photo send path creates the first state that could break it — the note sent, the
    /// photograph not — because the failure is recorded against the *binary* and the item is
    /// neither failed nor done. Without a sentence the row would sit in `waiting` explaining
    /// nothing, indefinitely.
    ///
    /// **PROPOSED copy, pending ratification.** What is pinned here is that the row says *something*
    /// true and names the photograph; the exact wording is the owner's to choose, and if it changes
    /// this assertion changes with it.
    @Test("an item whose photograph would not send says so, and is not drawn as failed")
    func anUnsentPhotographSaysWhy() async throws {
        let store = try await CypressStore.inMemory()
        let apply = OutboxTestSupport.ScriptedTransport(script: .allSucceed)
        let send = OutboxTestSupport.ScriptedSendSink(script: .photosFail)
        let queue = OutboxQueue(queue: store.queue, apply: apply, send: send)

        _ = try await queue.enqueue(
            .visit(Self.visit()),
            photos: [OutboxPhoto(path: try Self.stagedFile("saysWhy"), shotType: .fullTree)]
        )
        _ = try await queue.drain()

        let record = try #require(try await queue.records().first)
        let reason = try #require(record.item.lastError, "the row is outstanding and says nothing")
        #expect(
            reason == OutboxFailureReason.photoNotSentYet(photoCount: 1),
            "the row says \(reason)"
        )
        // Not `retry`: the note went and the photograph has not given up. `OutboxPresentation` draws
        // `retry` only for `.failed`, so this is the assertion that keeps the row in `waiting`.
        #expect(record.item.state != .failed, "an unsent photograph drew the note as terminally failed")
    }

    // MARK: - 4c. A refusal that will not change is not retried

    /// #116's review F4. `POST /photos/begin` answers 404 for a photograph withdrawn on another
    /// install or taken down by an operator, and `APIError.notFound` is non-retryable — but the
    /// photo path never asked. The binary was replayed on **every drain with no backoff**, because
    /// the reschedule sets `next_attempt_at` NULL and `dueItems` reads NULL as due; after 48 h the
    /// cap expired the item, taking down a note the service had already accepted.
    ///
    /// The assertions are about **drain count** and **the item's fate**, not about a state column:
    /// a version that recorded the code correctly and still looped would satisfy any single-drain
    /// check. Five drains is the same measurement the review used.
    @Test("a photograph refused for good is not replayed, and does not expire its accepted note")
    func aNonRetryableBinaryStopsBeingRetried() async throws {
        let store = try await CypressStore.inMemory()
        let apply = OutboxTestSupport.ScriptedTransport(script: .allSucceed)
        let send = OutboxTestSupport.ScriptedSendSink(script: .photosRefused(.notFound))
        let queue = OutboxQueue(queue: store.queue, apply: apply, send: send)

        _ = try await queue.enqueue(
            .visit(Self.visit()),
            photos: [OutboxPhoto(path: try Self.stagedFile("refused-for-good"), shotType: .fullTree)]
        )

        let first = try await queue.drain()
        #expect(first.sent == 1, "fixture: the note did not go, so this proves nothing about the binary")
        let attemptsAfterFirst = await send.sentPhotos.count
        #expect(attemptsAfterFirst == 1, "fixture: the binary was never offered")

        for _ in 0..<4 { _ = try await queue.drain() }

        // **The property.** A non-retryable refusal is asked once. Anything above one is the loop.
        let attempts = await send.sentPhotos.count
        #expect(
            attempts == attemptsAfterFirst,
            """
            the binary was offered \(attempts) times across five drains — a refusal that will not \
            change is being replayed with no backoff, and at 48 h the cap expires the note the \
            service already accepted
            """
        )

        let record = try #require(try await queue.records().first)
        #expect(record.remoteSent, "the note was accepted and must stay accepted")
        // Discarded rather than held: keeping it would wedge the item the way F1 did.
        let outstanding = try await store.queue.read { connection in
            try OutboxStore().outstandingPhotoCount(for: record.id, connection: connection)
        }
        #expect(outstanding == 0, "a permanently refused binary is still outstanding")
        // Said once, visibly, rather than silently evaporating: screen 17 draws `failed` as `retry`.
        #expect(record.item.state == .failed, "the item is \(record.item.state)")
        #expect(record.item.lastErrorCode == .notFound, "the refusal's code was not carried onto the item")

        // ── The sentence, which is the half a person actually reads ───────────────────────────
        //
        // `refusedTerminally` is "This couldn't be sent." — a claim about the whole contribution,
        // and false here, because `remoteSent` above is true. That is the error the owner corrected
        // on 2026-08-15 for `moderation_rejected`, and a photo refusal is a second code in the same
        // position. Asserting the *specific* sentence rather than `!= nil` is the difference: the
        // nil check passed while the row said the wrong thing.
        #expect(
            record.item.lastError == OutboxFailureReason.photoGivenUp(photoCount: 1),
            "the row reads \(record.item.lastError ?? "nothing")"
        )
        #expect(
            record.item.lastError != OutboxFailureReason.refusedTerminally,
            "the row tells a contributor whose note reached the service that it could not be sent"
        )
    }

    /// The other half of the terminal state: what a contributor sees **after** tapping retry.
    ///
    /// The sequence the r3 review measured was "This couldn't be sent." → retry → `done` with no
    /// sentence at all, drawn as an ordinary synced receipt. The contribution was called failed,
    /// then called synced, and nothing in between said the photograph had been given up.
    ///
    /// With the honest sentence the sequence reads correctly — the person is told the note went and
    /// the picture did not, and the retry is their acknowledgement — but two things still have to be
    /// true, and they are what this pins: retry must not resurrect a binary that was discarded, and
    /// the settled row must not carry the **stale** sentence forward as though it were current.
    @Test("retrying a given-up photograph settles the note and leaves no stale sentence behind")
    func retryingAfterAPhotographIsGivenUp() async throws {
        let store = try await CypressStore.inMemory()
        let apply = OutboxTestSupport.ScriptedTransport(script: .allSucceed)
        let send = OutboxTestSupport.ScriptedSendSink(script: .photosRefused(.notFound))
        let queue = OutboxQueue(queue: store.queue, apply: apply, send: send)

        _ = try await queue.enqueue(
            .visit(Self.visit()),
            photos: [OutboxPhoto(path: try Self.stagedFile("given-up-retry"), shotType: .fullTree)]
        )
        _ = try await queue.drain()

        let failed = try #require(try await queue.records().first)
        #expect(failed.item.state == .failed, "fixture: the item is \(failed.item.state), not terminal")

        // The person reads the sentence and taps retry.
        _ = try await store.queue.write { connection in
            try OutboxStore().retry(failed.id, at: Date(), connection: connection)
        }
        let offeredBeforeRetry = await send.sentPhotos.count
        _ = try await queue.drain()

        let settled = try #require(try await queue.records().first)
        #expect(settled.item.state == .done, "the item is \(settled.item.state) after retry")
        #expect(
            await send.sentPhotos.count == offeredBeforeRetry,
            """
            retry re-offered a binary that had been discarded — the photograph was given up, so \
            there is nothing left to send and the attempt would refuse again
            """
        )
        // A settled row must not keep the sentence of the failure it recovered from: on a synced
        // receipt a stale sentence reads as current.
        #expect(
            settled.item.lastError == nil,
            "the settled row still reads \(settled.item.lastError ?? "")"
        )
    }

    /// A row that recovers on its own must not keep the sentence of the failure it recovered from.
    ///
    /// **The path that reaches `markDoneIfComplete` with a sentence still on the row**, which the
    /// retry test above does not: retry clears `last_error` itself, so an item that goes
    /// fail → retry → done is nil by the time it settles. An item that goes fail → *succeed on a
    /// later drain* never passes through retry, and used to settle carrying "The note is sent. One
    /// photo hasn't gone through yet." — about a photograph that had, by then, gone through.
    ///
    /// Invisible today, because screen 17 draws no sentence on a synced receipt. It stops being
    /// invisible the moment anything reads `lastError` off a `done` row, and a stale sentence is
    /// worse than none: it reads as current (#116 r3, recorded as cosmetic and fixed).
    @Test("an item that recovers on a later drain does not keep its old failure sentence")
    func recoveringDoesNotKeepTheOldSentence() async throws {
        let store = try await CypressStore.inMemory()
        let apply = OutboxTestSupport.ScriptedTransport(script: .allSucceed)
        let send = OutboxTestSupport.ScriptedSendSink(script: .photosFail)
        let queue = OutboxQueue(queue: store.queue, apply: apply, send: send)

        _ = try await queue.enqueue(
            .visit(Self.visit()),
            photos: [OutboxPhoto(path: try Self.stagedFile("recovers"), shotType: .fullTree)]
        )

        // Retryable failure: the sentence lands on the row and the item stays live.
        _ = try await queue.drain()
        let stalled = try #require(try await queue.records().first)
        #expect(
            stalled.item.lastError == OutboxFailureReason.photoNotSentYet(photoCount: 1),
            """
            fixture: the row reads \(stalled.item.lastError ?? "nothing"), so there is no stale \
            sentence for the next drain to carry
            """
        )

        // The connection comes back and the binary goes. No retry tap anywhere in this sequence.
        await send.setScript(.allSucceed)
        _ = try await queue.drain()

        let settled = try #require(try await queue.records().first)
        #expect(settled.item.state == .done, "fixture: the item is \(settled.item.state)")
        #expect(
            settled.item.lastError == nil,
            """
            the settled row still reads \(settled.item.lastError ?? "") — the photograph did go, \
            and a synced receipt carrying the sentence of a failure it recovered from reads as current
            """
        )
        #expect(settled.item.lastErrorCode == nil, "the settled row kept its old error code")
    }

    // MARK: - 4d. The other F1 door, on its own

    /// #116's review N10. F1 was repaired at two doors — `discardPhoto` (what
    /// `LocalAPI.deletePhoto` calls) and the drain's own `discardWithdrawnPhotos` — and only the
    /// drain door was covered: reverting `discardPhoto` to path-only matching left the full suite
    /// green, because the drain cleaned up on the next pass and hid it.
    ///
    /// What that concealed is not the wedge but a **lie to the contributor**: `discardPhoto`'s
    /// return value is surfaced as `PhotoDeletion.dequeuedBinaries`, so an applied binary's
    /// withdrawal reported **0** queued rows removed when it had removed one. And a `failed` item is
    /// never re-drained, so for that item the drain door never runs at all.
    ///
    /// So this asserts the count, not just the absence of the row — the count is the half that was
    /// wrong while everything else looked right.
    @Test("withdrawing an applied binary reports the queue row it removed")
    func discardPhotoReportsAnAppliedBinary() async throws {
        let store = try await CypressStore.inMemory()
        let apply = OutboxTestSupport.ScriptedTransport(script: .allSucceed)
        let send = OutboxTestSupport.ScriptedSendSink(script: .photosFail)
        let queue = OutboxQueue(queue: store.queue, apply: apply, send: send)

        let staged = OutboxPhoto(path: try Self.stagedFile("n10"), shotType: .fullTree)
        let item = try await queue.enqueue(.visit(Self.visit()), photos: [staged])

        // Applied, so `path` is now NULL and only `photo_id` can find it — which is exactly the
        // state the path-only matcher could not see.
        _ = try await queue.drain()
        let photoID = try await store.queue.read { connection -> UUID in
            let st = try connection.prepare("SELECT photo_id FROM outbox_photos WHERE outbox_id = :i")
            defer { st.finalize() }
            _ = try st.bind(item.id, forName: ":i")
            return try st.fetchOne { try $0.uuid("photo_id") } ?? UUID()
        }

        let removed = try await store.queue.write { connection in
            try OutboxStore().discardPhoto(
                id: photoID,
                // The staged path as `LocalAPI.deletePhoto` passes it — `photos.local_path`, which
                // after the apply is the container copy and no longer matches `outbox_photos.path`.
                stagedPath: staged.path,
                at: Date(),
                connection: connection
            )
        }
        #expect(
            removed == 1,
            """
            discardPhoto reported \(removed) queued rows for a binary that was still queued — the \
            contributor is told nothing was dequeued while a row was removed, and for a `failed` \
            item the drain never runs to correct it
            """
        )

        let left = try await store.queue.read { connection in
            try OutboxStore().outstandingPhotoCount(for: item.id, connection: connection)
        }
        #expect(left == 0, "the withdrawn binary is still queued")
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
