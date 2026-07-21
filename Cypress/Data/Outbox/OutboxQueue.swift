import Foundation

/// What the outbox needs from whatever is on the other side.
///
/// Narrower than `CypressAPI` on purpose: the drain's correctness — zero loss, zero duplicates,
/// the exact backoff schedule — is testable against scripted failures without standing up a store,
/// a seed, or a photo directory. `APIOutboxTransport` adapts the real API onto it.
public protocol OutboxTransport: Sendable {
    /// `POST /sync`. One result per item, matched on `clientUUID`.
    func sync(_ items: [OutboxItem]) async throws -> [SyncResult]
    /// Uploads one photo binary, with the shot type it was framed as. Gated by the wifi-only
    /// toggle; the JSON above never is.
    func uploadPhoto(_ photo: OutboxPhoto, for item: OutboxItem) async throws
}

/// What one drain pass did. Returned for tests and for the outbox screen's summary line.
public struct DrainReport: Sendable, Equatable {
    public var attempted = 0
    public var synced = 0
    public var failedTemporarily = 0
    public var failedTerminally = 0
    /// Items whose JSON went but whose photos are waiting for wi-fi.
    public var awaitingWifi = 0
}

/// The local-first mutation queue.
///
/// "The outbox is the feature, not a network workaround" (ARCHITECTURE §4): every mutation is
/// written here first and only then attempted, which is true even though `LocalAPI` is on the other
/// side today. Nothing here disappears silently — an item that cannot sync says so, says why, and
/// waits (screen 17).
public actor OutboxQueue {
    private let queue: DatabaseQueue
    private let store = OutboxStore()
    private let transport: OutboxTransport
    private let now: @Sendable () -> Date
    private var observers: [UUID: @Sendable () async -> Void] = [:]
    private var isDraining = false

    /// How many items one `POST /sync` carries. §6 caps a page at 100; a field batch is smaller and
    /// a smaller batch loses less work to a single flap.
    public static let batchSize = 25

    /// How long a `done` receipt is kept before being swept. Screen 17 shows "Synced earlier
    /// today", so a day is the shortest span that keeps that section honest.
    public static let completedRetention: TimeInterval = 24 * 60 * 60

    public init(queue: DatabaseQueue, transport: OutboxTransport, now: @escaping @Sendable () -> Date = { Date() }) {
        self.queue = queue
        self.transport = transport
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

        // --- Phase A: the JSON items. Batched, because §6's /sync is a batch endpoint, and
        // unconditional, because the wifi toggle does not apply to them.
        let needingJSON = live.filter { !$0.jsonSynced }
        var resultsByClientUUID: [UUID: SyncResult] = [:]
        var transportFailure: Error?

        if !needingJSON.isEmpty {
            do {
                let results = try await transport.sync(needingJSON.map(\.item))
                for result in results { resultsByClientUUID[result.clientUUID] = result }
            } catch {
                transportFailure = error
            }
        }

        // --- Phase B: apply, per item, in FIFO order.
        for record in live {
            let settledAt = now()

            if !record.jsonSynced {
                if let transportFailure {
                    try await recordFailure(record, error: transportFailure, at: settledAt, report: &report)
                    continue
                }
                guard let result = resultsByClientUUID[record.item.clientUUID] else {
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
                    try store.markJSONSynced(record.id, at: settledAt, connection: connection)
                }
            }

            // --- Photo binaries.
            if !record.item.photos.isEmpty {
                guard photoUploadsAllowed else {
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

                var photoFailure: Error?
                for photo in record.item.photos {
                    do {
                        try await transport.uploadPhoto(photo, for: record.item)
                        try await queue.write { connection in
                            try store.removePhoto(atPath: photo.path, from: record.id, at: settledAt, connection: connection)
                        }
                    } catch {
                        photoFailure = error
                        break
                    }
                }
                if let photoFailure {
                    try await recordFailure(record, error: photoFailure, at: settledAt, report: &report)
                    continue
                }
            }

            try await queue.write { connection in
                try store.markDoneIfComplete(record.id, at: settledAt, connection: connection)
            }
            report.synced += 1
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

    public func counts() async throws -> [OutboxItem.State: Int] {
        try await queue.read { connection in try store.counts(connection: connection) }
    }

    /// Screen 17's whole model, in one read.
    public func snapshot(treeNames: [UUID: String] = [:]) async throws -> OutboxSnapshot {
        let records = try await records()
        return OutboxSnapshot(records: records, treeNames: treeNames, now: now())
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

/// Adapts a `CypressAPI` onto `OutboxTransport`.
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
        let ticket = try await api.beginPhotoUpload(
            PhotoUploadRequest(
                treeID: payload.treeID,
                visitID: {
                    if case let .visit(visit) = payload { return visit.id }
                    return nil
                }(),
                shotType: photo.shotType,
                localPath: photo.path,
                capturedAt: item.createdAt
            )
        )
        try await api.uploadPhoto(at: photo.path, ticket: ticket)
    }
}
