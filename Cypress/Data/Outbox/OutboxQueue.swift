import Foundation

/// What the outbox needs from whatever is on the other side.
///
/// Narrower than `CypressAPI` on purpose: the drain's correctness — zero loss, zero duplicates,
/// the exact backoff schedule — is testable against scripted failures without standing up a store,
/// a seed, or a photo directory. `APIOutboxTransport` adapts the real API onto it.
///
/// **This is the *apply* sink** (RULINGS R72 §1). It is what commits a mutation to this device's
/// own tables, it runs first, and it runs whether or not there is a network — a contribution is on
/// its tree the moment the drain runs. **Both of its methods are apply-side**: `uploadPhoto` is the
/// local commit of the photograph, so it runs beside `sync` and never behind a send.
/// The send sink is `OutboxSendSink` below, and the two are
/// separate types rather than one type used twice because they are not interchangeable: swapping a
/// remote implementation into this position does not add a network to a local write, it removes the
/// local write (ERRATA E261 §2).
public protocol OutboxTransport: Sendable {
    /// `POST /sync`. One result per item, matched on `clientUUID`.
    func sync(_ items: [OutboxItem]) async throws -> [SyncResult]
    /// Uploads one photo binary, with the shot type it was framed as. Gated by the wifi-only
    /// toggle; the JSON above never is.
    func uploadPhoto(_ photo: OutboxPhoto, for item: OutboxItem) async throws
}

/// The **send** sink: the retryable half of a drain, and the half `OutboxRetryPolicy` was written
/// for (RULINGS R72 §1, spec §6.1).
///
/// Injected, and `nil` on every build shipped so far — there is no server yet, and with none wired
/// the queue's observable behavior is exactly what it was before the split. Nothing in this PR
/// wires `RemoteAPI` into this position.
///
/// **It carries `sync` and deliberately not `uploadPhoto`, which is a scope statement and not an
/// omission.** The apply sink's photo upload is a *move*: `LocalAPI.uploadPhoto` strips the
/// metadata into the app container and then removes the staged file, so by the time a send sink
/// could run there is nothing at `OutboxPhoto.path` left to send, and `beginPhotoUpload` mints a
/// fresh `photos` row per call, so re-running the local half to keep the bytes around would
/// duplicate the record. Sending binaries needs per-photo completion tracking and a source the
/// remote can still read — its own design, its own migration and its own ticket. The protocol has
/// no photo method so that a future author has to add one rather than inherit a silent no-op, which
/// is the failure ERRATA E125 records paying for once already.
///
/// **This argument is about the send side only.** It is not a licence to gate the *apply* sink's
/// `uploadPhoto` on a send — the first draft of this split did exactly that, and an offline drain
/// then committed the note and never the photograph. See the `OutboxQueue` type doc.
public protocol OutboxSendSink: Sendable {
    /// `POST /sync` against a real server. One result per item, matched on `clientUUID`.
    /// `duplicate` is a success here for the same reason it is on the apply side: the server dedupes
    /// on `client_uuid` exactly as the local unique index does.
    func sync(_ items: [OutboxItem]) async throws -> [SyncResult]
}

/// What one drain pass did. Returned for tests and for the outbox screen's summary line.
public struct DrainReport: Sendable, Equatable {
    public var attempted = 0
    public var synced = 0
    public var failedTemporarily = 0
    public var failedTerminally = 0
    /// Items whose JSON went but whose photos are waiting for wi-fi.
    public var awaitingWifi = 0
    /// Items a send sink accepted on this pass. Zero whenever no send sink is wired, which is what
    /// makes "the local write still happened" separable from "it went somewhere" in a test.
    public var sent = 0
}

/// The local-first mutation queue.
///
/// "The outbox is the feature, not a network workaround" (ARCHITECTURE §4): every mutation is
/// written here first and only then attempted, which is true even though `LocalAPI` is on the other
/// side today. Nothing here disappears silently — an item that cannot sync says so, says why, and
/// waits (screen 17).
///
/// # Two sinks, in order
///
/// A drain does two things that used to look like one (ERRATA E261 §2). **Apply** commits the
/// mutation to this device's own tables; it goes first and it is not conditional on anything, which
/// is why a visit saved in a park is on its tree before the phone has seen a network again.
/// **Send** forwards it to a server; it is injectable, it is `nil` on every build shipped so far,
/// and it is the half the 48 h backoff exists for. An item that fails to apply is never offered to
/// the send sink, and an item the send sink refuses keeps the local write it already has.
///
/// **Both halves of a mutation are apply-side, and that includes the photograph.** The binaries go
/// to the apply sink in phase B2, *before* any send is attempted, because `LocalAPI.uploadPhoto` is
/// the local commit of the photograph exactly as `sync` is the local commit of the note. Only the
/// decision to *defer* a binary for wi-fi is carried past the send, so that a photograph waiting for
/// an unmetered connection never holds up a note that syncs on any connection (BUILD-PLAN §4).
///
/// With no send sink wired every observable behavior of this type is what it was before the split:
/// the same states, the same counts, the same screen 17.
public actor OutboxQueue {
    private let queue: DatabaseQueue
    private let store = OutboxStore()
    /// Commits the mutation to this device. First, unconditional, offline or not.
    private let apply: any OutboxTransport
    /// Sends it on to a server, when there is one. `nil` on every build shipped so far.
    private let send: (any OutboxSendSink)?
    private let now: @Sendable () -> Date
    private var observers: [UUID: @Sendable () async -> Void] = [:]
    private var isDraining = false

    /// One row's progress through a single drain.
    ///
    /// It exists to carry two things across the phases: the row's own `settledAt`, so a row still
    /// takes one clock reading per drain rather than one per phase, and whether its binaries were
    /// held back for wi-fi — a decision made in the apply half and acted on after the send half, so
    /// that a waiting photograph never delays a note (BUILD-PLAN §4).
    private struct InFlight {
        let record: OutboxStore.Record
        let settledAt: Date
        var photosAwaitingWifi = false
    }

    /// How many items one `POST /sync` carries. §6 caps a page at 100; a field batch is smaller and
    /// a smaller batch loses less work to a single flap.
    public static let batchSize = 25

    /// How long a `done` receipt is kept before being swept. Screen 17 shows "Synced earlier
    /// today", so a day is the shortest span that keeps that section honest.
    public static let completedRetention: TimeInterval = 24 * 60 * 60

    /// - Parameters:
    ///   - apply: the sink that commits a mutation to this device's own tables. Named `apply` and
    ///     not `transport` on purpose: the one-line change that looks like the whole job is
    ///     replacing this value with a remote implementation, which would delete the local write
    ///     without any layer reporting an error (ERRATA E261 §2).
    ///   - send: the sink that forwards it to a server, when one exists. `nil` today, and with it
    ///     `nil` the drain behaves exactly as it did before the split.
    public init(
        queue: DatabaseQueue,
        apply: any OutboxTransport,
        send: (any OutboxSendSink)? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.queue = queue
        self.apply = apply
        self.send = send
        self.now = now
    }

    // MARK: - TreeObservation

    /// Registers a change handler. `OutboxViewState` uses this to refresh screen 17.
    @discardableResult
    public func addObserver(_ handler: @escaping @Sendable () async -> Void) -> UUID {
        let token = UUID()
        observers[token] = handler
        return token
    }

    public func removeObserver(_ token: UUID) {
        observers[token] = nil
    }

    private func notifyObservers() async {
        for handler in observers.values {
            await handler()
        }
    }

    // MARK: - Enqueue

    /// Writes a mutation to the outbox. Idempotent on `clientUUID`.
    ///
    /// Returns the row as stored, whether or not this call is the one that created it.
    @discardableResult
    public func enqueue(_ payload: OutboxPayload, photos: [OutboxPhoto] = []) async throws -> OutboxItem {
        let item = try payload.makeItem(photos: photos, createdAt: now())
        try await queue.write { connection in
            try store.enqueue(item, connection: connection)
        }
        await notifyObservers()
        // Re-read rather than returning the local value: if this was a duplicate enqueue, the
        // stored row is the earlier one and its state is the truth.
        let stored = try await queue.read { connection in
            try store.item(id: item.id, connection: connection)
        }
        return stored?.item ?? item
    }

    // MARK: - Drain

    /// Attempts every due item, oldest first.
    ///
    /// - Parameter photoUploadsAllowed: the wifi-only toggle, already resolved against the current
    ///   connection type. It gates **photo binaries only**; the JSON item syncs on any connection
    ///   (BUILD-PLAN §4, screen 17's "Notes and numbers sync on any connection").
    @discardableResult
    public func drain(photoUploadsAllowed: Bool = true) async throws -> DrainReport {
        guard !isDraining else { return DrainReport() }
        isDraining = true
        defer { isDraining = false }

        var report = DrainReport()
        let startedAt = now()

        // Anything left `uploading` belongs to a process that died mid-drain. Recovering it here is
        // what keeps "nothing disappears silently" true across a crash.
        let due: [OutboxStore.Record] = try await queue.write { connection in
            _ = try store.recoverInterrupted(at: startedAt, connection: connection)
            let records = try store.dueItems(now: startedAt, limit: Self.batchSize, connection: connection)
            try store.markUploading(records.map(\.id), at: startedAt, connection: connection)
            return records
        }
        guard !due.isEmpty else { return report }
        report.attempted = due.count

        // Expire anything that has been trying for longer than the 48 h cap before spending another
        // request on it.
        var live: [OutboxStore.Record] = []
        for record in due {
            if OutboxRetryPolicy.hasExpired(createdAt: record.windowStartedAt, now: startedAt) {
                try await settle(
                    record,
                    state: .failed,
                    failCount: record.item.failCount,
                    reason: OutboxFailureReason.expired,
                    code: record.item.lastErrorCode,
                    nextAttemptAt: nil,
                    at: startedAt
                )
                report.failedTerminally += 1
            } else {
                live.append(record)
            }
        }
        guard !live.isEmpty else {
            await notifyObservers()
            return report
        }

        // --- Phase A: apply, batched, because §6's /sync is a batch endpoint, and unconditional,
        // because neither the wifi toggle nor the absence of a network applies to it. This is the
        // local commit: after it, the contribution is on its tree (RULINGS R72 §1).
        let needingApply = live.filter { !$0.locallyApplied }
        var applyResults: [UUID: SyncResult] = [:]
        var applyFailure: Error?

        if !needingApply.isEmpty {
            do {
                let results = try await apply.sync(needingApply.map(\.item))
                for result in results { applyResults[result.clientUUID] = result }
            } catch {
                applyFailure = error
            }
        }

        // --- Phase B: settle the apply half, per item, in FIFO order. An item that could not be
        // applied drops out here and is not offered to the send sink: nothing may be sent that this
        // device has not committed, which is also `AppSchema` v15's second CHECK.
        //
        // `settledAt` is read once per record and carried through every later phase, so a row still
        // takes exactly one clock reading per drain, as it did before the split.
        var carrying: [InFlight] = []
        for record in live {
            let settledAt = now()
            guard !record.locallyApplied else {
                carrying.append(InFlight(record: record, settledAt: settledAt))
                continue
            }

            if let applyFailure {
                try await recordFailure(record, error: applyFailure, at: settledAt, report: &report)
                continue
            }
            guard let result = applyResults[record.item.clientUUID] else {
                // A batch that came back without an entry for an item we sent is a protocol
                // break, not a success. Treating it as a failure keeps the item alive.
                try await recordFailure(record, error: APIError.serverError, at: settledAt, report: &report)
                continue
            }
            guard result.isSuccess else {
                try await recordFailure(
                    record,
                    error: result.error ?? APIError.serverError,
                    at: settledAt,
                    report: &report
                )
                continue
            }
            try await queue.write { connection in
                try store.markLocallyApplied(record.id, at: settledAt, connection: connection)
            }
            carrying.append(InFlight(record: record, settledAt: settledAt))
        }

        // --- Phase B2: the photo binaries, and they belong to the **apply** half.
        //
        // `apply.uploadPhoto` is the local commit of the photograph — `LocalAPI` ingests the file
        // into the app container and writes the `photos` row — so it runs here, beside the JSON
        // apply, and not behind the send gate below. It sat behind that gate in the first draft of
        // this split: a drain with a send sink and no signal committed the note, skipped the
        // photograph, and after 48 h of that the row expired terminally with the binary never
        // ingested and nothing left holding a reference to it. That is the quiet loss this ticket
        // exists to prevent, moved from one half to the other.
        //
        // The wi-fi deferral is recorded rather than acted on, because a deferred *binary* must not
        // hold up a *JSON* send: notes and numbers sync on any connection (BUILD-PLAN §4, screen
        // 17). The reschedule happens in phase D, after the send has had its turn.
        //
        // **Forward, oldest first**, like every other phase and like `drain()`'s own contract. It
        // was written backwards at first, purely so that `remove(at:)` could not invalidate the
        // index under the loop — a convenience that quietly inverted the order of the one phase that
        // does something irreversible: ingesting a binary consumes the staged file. Failures are
        // collected and removed after the loop instead, which costs one array and keeps the order
        // honest.
        var failedPhotoIndices: [Int] = []
        for index in carrying.indices {
            let entry = carrying[index]
            let record = entry.record
            guard !record.item.photos.isEmpty else { continue }

            guard photoUploadsAllowed else {
                carrying[index].photosAwaitingWifi = true
                continue
            }

            var photoFailure: Error?
            for photo in record.item.photos {
                do {
                    // The apply sink only. `OutboxSendSink` carries no photo method and says why:
                    // the staged file is consumed by this call.
                    try await apply.uploadPhoto(photo, for: record.item)
                    try await queue.write { connection in
                        try store.removePhoto(
                            atPath: photo.path,
                            from: record.id,
                            at: entry.settledAt,
                            connection: connection
                        )
                    }
                } catch {
                    photoFailure = error
                    break
                }
            }
            if let photoFailure {
                try await recordFailure(record, error: photoFailure, at: entry.settledAt, report: &report)
                failedPhotoIndices.append(index)
            }
        }
        // Descending, so each removal leaves the indices still to be removed valid.
        for index in failedPhotoIndices.reversed() {
            carrying.remove(at: index)
        }

        // --- Phase C: send, batched, and only when a send sink is wired. With none, this is skipped
        // entirely and every row below settles on the apply result alone, which is the behavior that
        // shipped.
        var sendResults: [UUID: SyncResult] = [:]
        var sendFailure: Error?
        if let send {
            let needingSend = carrying.filter { !$0.record.remoteSent }
            if !needingSend.isEmpty {
                do {
                    let results = try await send.sync(needingSend.map(\.record.item))
                    for result in results { sendResults[result.clientUUID] = result }
                } catch {
                    sendFailure = error
                }
            }
        }

        // --- Phase D: settle the send half, then the row, per item, in FIFO order.
        for entry in carrying {
            let record = entry.record
            let settledAt = entry.settledAt

            if send != nil, !record.remoteSent {
                if let sendFailure {
                    try await recordFailure(record, error: sendFailure, at: settledAt, report: &report)
                    continue
                }
                guard let result = sendResults[record.item.clientUUID] else {
                    try await recordFailure(record, error: APIError.serverError, at: settledAt, report: &report)
                    continue
                }
                guard result.isSuccess else {
                    try await recordFailure(
                        record,
                        error: result.error ?? APIError.serverError,
                        at: settledAt,
                        report: &report
                    )
                    continue
                }
                try await queue.write { connection in
                    try store.markRemotelySent(record.id, at: settledAt, connection: connection)
                }
                report.sent += 1
            }

            // The binaries phase B2 held back for wi-fi. The note is saved and, with a sink, sent;
            // what is waiting is the photograph.
            if entry.photosAwaitingWifi {
                try await queue.write { connection in
                    try store.reschedule(
                        record.id,
                        reason: OutboxFailureReason.awaitingWifi(photoCount: record.item.photos.count),
                        at: settledAt,
                        connection: connection
                    )
                }
                report.awaitingWifi += 1
                continue
            }

            // `markDoneIfComplete` is a conditional `UPDATE`, so the count follows what it actually
            // matched rather than the fact that it ran.
            let settled = try await queue.write { connection in
                try store.markDoneIfComplete(
                    record.id,
                    requiringRemoteSend: send != nil,
                    at: settledAt,
                    connection: connection
                )
            }
            if settled { report.synced += 1 }
        }

        await notifyObservers()
        return report
    }

    // MARK: - Retry

    /// Screen 17's retry button.
    @discardableResult
    public func retry(id: UUID) async throws -> Bool {
        let changed = try await queue.write { connection in
            try store.retry(id, at: now(), connection: connection)
        }
        if changed { await notifyObservers() }
        return changed
    }

    @discardableResult
    public func retryAllFailed() async throws -> Int {
        let changed = try await queue.write { connection in
            try store.retryAllFailed(at: now(), connection: connection)
        }
        if changed > 0 { await notifyObservers() }
        return changed
    }

    /// Sweeps `done` receipts older than `completedRetention`.
    @discardableResult
    public func pruneCompleted() async throws -> Int {
        let removed = try await queue.write { connection in
            try store.pruneCompleted(olderThan: Self.completedRetention, now: now(), connection: connection)
        }
        if removed > 0 { await notifyObservers() }
        return removed
    }

    // MARK: - Reading

    public func records() async throws -> [OutboxStore.Record] {
        try await queue.read { connection in try store.allItems(connection: connection) }
    }

    /// The queue's word on one tree's favorite, if it is still holding one (#167).
    ///
    /// A favorite is durable the moment it is enqueued (ARCHITECTURE §4: "written to the outbox
    /// *first*, and only then attempted") — but it is not *applied* until a drain carries it
    /// across, and the drain that follows a save is best-effort: it can be skipped because another
    /// drain holds `isDraining`, or leave the toggle behind because a batch is `batchSize` items
    /// and older work fills it. In that window the store's `favorites` table and the contributor's
    /// last word disagree, and the last word is here.
    ///
    /// Returns the resulting state of the **newest** in-flight (`pending` or `uploading`) favorite
    /// toggle for this tree, or nil when the queue holds none — `done` items are already in the
    /// table's answer, and a terminally `failed` toggle is deliberately not counted: a write the
    /// queue has given up on is the one case where the heart going back is the truth (RULINGS R2;
    /// screen 17 is where that failure says why).
    public func pendingFavoriteState(treeID: UUID) async throws -> Bool? {
        let records = try await records()
        // `records()` is `ORDER BY seq`, so the last match is the newest statement.
        for record in records.reversed() {
            guard record.item.kind == .favoriteToggle,
                  record.item.state == .pending || record.item.state == .uploading,
                  case let .favoriteToggle(toggle)? =
                    try? OutboxPayload.decode(kind: record.item.kind, from: record.item.payload),
                  toggle.treeID == treeID
            else { continue }
            return toggle.isFavorite
        }
        return nil
    }

    public func counts() async throws -> [OutboxItem.State: Int] {
        try await queue.read { connection in try store.counts(connection: connection) }
    }

    /// Screen 17's whole model, in one read.
    ///
    /// The queue does not own the wi-fi preference — `OutboxViewState` does, and the store behind
    /// it — so the toggle arrives as an argument. It has no default here for the reason
    /// `OutboxSnapshot.init` gives (ERRATA E38).
    public func snapshot(
        treeNames: [UUID: String] = [:],
        syncPhotosOnWifiOnly: Bool
    ) async throws -> OutboxSnapshot {
        let records = try await records()
        return OutboxSnapshot(
            records: records,
            treeNames: treeNames,
            now: now(),
            syncPhotosOnWifiOnly: syncPhotosOnWifiOnly
        )
    }

    // MARK: - Failure accounting

    private func recordFailure(
        _ record: OutboxStore.Record,
        error: Error,
        at date: Date,
        report: inout DrainReport
    ) async throws {
        let apiError = OutboxFailureReason.apiError(from: error)
        let failCount = record.item.failCount + 1

        // `OutboxRetryPolicy.nextState` reads `createdAt` to apply the 48 h cap. The window the cap
        // measures is `windowStartedAt`, which the retry button restarts, so the shim below hands
        // the policy the window rather than the capture time. Everything else about the item is
        // unchanged.
        let shim = OutboxItem(
            id: record.item.id,
            kind: record.item.kind,
            clientUUID: record.item.clientUUID,
            payload: record.item.payload,
            photos: record.item.photos,
            state: .pending,
            failCount: failCount,
            createdAt: record.windowStartedAt,
            updatedAt: date
        )
        let state = OutboxRetryPolicy.nextState(for: shim, error: apiError, now: date)
        let nextAttempt: Date? = state == .pending
            ? date.addingTimeInterval(OutboxRetryPolicy.delay(afterFailures: failCount))
            : nil

        try await settle(
            record,
            state: state,
            failCount: failCount,
            reason: OutboxFailureReason.describe(error: error, failCount: failCount, state: state),
            code: apiError,
            nextAttemptAt: nextAttempt,
            at: date
        )

        if state == .failed { report.failedTerminally += 1 } else { report.failedTemporarily += 1 }
    }

    private func settle(
        _ record: OutboxStore.Record,
        state: OutboxItem.State,
        failCount: Int,
        reason: String,
        code: APIError?,
        nextAttemptAt: Date?,
        at date: Date
    ) async throws {
        try await queue.write { connection in
            try store.recordFailure(
                record.id,
                state: state,
                failCount: failCount,
                reason: reason,
                code: code,
                nextAttemptAt: nextAttemptAt,
                at: date,
                connection: connection
            )
        }
    }
}

/// Adapts a `CypressAPI` onto `OutboxTransport`, the **apply** sink.
///
/// In the shipping composition root the API behind it is `LocalAPI`, and that is what makes this
/// the local commit rather than a network call. It deliberately does not conform to
/// `OutboxSendSink`: a type that satisfied both would let one value be wired into both positions,
/// which is the confusion the split exists to end.
public struct APIOutboxTransport: OutboxTransport {
    private let api: any CypressAPI

    public init(api: any CypressAPI) {
        self.api = api
    }

    public func sync(_ items: [OutboxItem]) async throws -> [SyncResult] {
        try await api.sync(items)
    }

    public func uploadPhoto(_ photo: OutboxPhoto, for item: OutboxItem) async throws {
        // §6 splits this in two: POST /photos/begin reserves the id and the destination, then the
        // client PUTs the binary there. The ticket is therefore minted per upload; `LocalAPI` makes
        // it a move inside the app container.
        //
        // The shot type comes off the queued photo, which is where the chip the contributor tapped
        // on screen 04 ends up. `photos.shot_type` is append-only, so this is the last moment the
        // true framing exists to be recorded (BUILD-PLAN §4).
        let payload = try OutboxPayload.decode(kind: item.kind, from: item.payload)

        // The pixel size, read off the staged file before it is handed over. Without it every
        // `photos.width`/`height` was NULL, so `Photo.resolution` was 0 for every row and A3's
        // "ties broken by resolution" never ran — on a series where several photos share a capture
        // date, which is the only case the tie-break exists for (ERRATA E41).
        let size = PhotoBinary.pixelSize(atPath: photo.path)

        // `publicCoordinate` is deliberately not set. See ERRATA E42: the tree's own pin is already
        // exact and public, so a photo location adds nothing a public surface needs and does add a
        // second, independent record of where the contributor was standing — which is the thing
        // D11 exists to prevent. `Photo.publicCoordinate` and its 25 m snap stay in the model for
        // the surface that one day genuinely needs one; not storing a location is the privacy-safe
        // direction and is the one taken here.
        let ticket = try await api.beginPhotoUpload(
            PhotoUploadRequest(
                treeID: payload.treeID,
                visitID: {
                    if case let .visit(visit) = payload { return visit.id }
                    return nil
                }(),
                shotType: photo.shotType,
                localPath: photo.path,
                capturedAt: item.createdAt,
                width: size?.width,
                height: size?.height
            )
        )
        try await api.uploadPhoto(at: photo.path, ticket: ticket)
    }
}
