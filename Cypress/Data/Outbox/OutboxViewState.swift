import Foundation
import Observation

/// The "says why" line on screen 17.
///
/// Screen 17's footnote is the contract this type implements: "Nothing here disappears silently. An
/// item that cannot sync says so, says why, and waits for you." Every failure path produces a
/// sentence a volunteer standing on a pavement can act on.
///
/// Copy rules (ARCHITECTURE §5.7): prose is sentence case, and there are no spaces around em
/// dashes — which is easiest to honour by not reaching for one.
public enum OutboxFailureReason {
    /// The 48 h cap, reached (BUILD-PLAN §4).
    public static let expired = "Tried for 48 hours without getting through. Tap retry when you have a connection."

    public static func awaitingWifi(photoCount: Int) -> String {
        photoCount == 1
            ? "The note is saved. One photo is waiting for wi-fi."
            : "The note is saved. \(photoCount) photos are waiting for wi-fi."
    }

    /// Narrows any thrown error to the §6 taxonomy, or `nil` when it did not come from the API at
    /// all (a dropped connection, a file that vanished).
    public static func apiError(from error: Error) -> APIError? {
        if let apiError = error as? APIError { return apiError }
        if let sqliteError = error as? SQLiteError { return sqliteError.asAPIError }
        // `APIError.Envelope` is the decoded `{error: {code, message, retryable}}` body, not an
        // `Error` — `RemoteAPI` will decode it and throw its `.error` member, which the first line
        // above catches.
        // The 10 m proximity dedupe on `POST /trees` carries its candidate list in a dedicated
        // error type, but its taxonomy code is `conflict` — and `conflict` is not retryable, so the
        // item fails immediately instead of spending 48 h on an answer only the user can give.
        if error is ProximityConflict { return .conflict }
        return nil
    }

    /// The sentence shown under an item.
    public static func describe(error: Error, failCount: Int, state: OutboxItem.State) -> String {
        let cause = sentence(for: error)
        guard state != .failed else {
            if let apiError = apiError(from: error), !apiError.retryable {
                return "\(cause) This one will not go through on its own."
            }
            return expired
        }
        switch failCount {
        case 1: return cause
        case 2: return "\(cause) Tried twice."
        default: return "\(cause) Tried \(failCount) times."
        }
    }

    /// One sentence per taxonomy code (BUILD-PLAN §6).
    static func sentence(for error: Error) -> String {
        guard let apiError = apiError(from: error) else {
            return "No connection."
        }
        switch apiError {
        case .unauthorized:
            return "Sign in to send this."
        case .forbidden:
            return "This account is not allowed to send that."
        case .notFound:
            return "That tree is no longer in the inventory."
        case .validationFailed:
            return "Something in this entry did not pass validation."
        case .conflict:
            return "This looks like something already recorded."
        case .moderationRejected:
            return "A moderator declined this."
        case .rateLimited:
            return "The server asked us to slow down."
        case .serverError:
            return "The server could not take it just now."
        }
    }
}

/// One row of screen 17.
public struct OutboxItemSnapshot: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let kind: OutboxItem.Kind
    public let state: OutboxItem.State
    /// How many attempts have failed. Screen 17 renders this as "upload failed twice".
    public let failCount: Int
    /// The human-readable reason, or `nil` when there is nothing to explain.
    public let reason: String?
    /// The BUILD-PLAN §6 code behind `reason`, when the failure came from the API.
    public let errorCode: APIError?
    public let treeID: UUID
    /// The tree's active name, or its species common name, resolved by the caller. `nil` renders as
    /// the species fallback in the view; this layer does not author display copy for a tree.
    public let treeName: String?
    /// Binaries still on device for this item.
    public let photoCount: Int
    public let createdAt: Date
    /// When the backoff will let it try again. `nil` when it is not waiting on a timer.
    public let nextAttemptAt: Date?

    /// Screen 17 draws the `retry` state as an amber attention card. That is exactly the terminal
    /// `failed` state, which is the only one with a retry affordance.
    public var showsRetryAffordance: Bool { state == .failed }
}

/// Everything screen 17 renders, in one value.
public struct OutboxSnapshot: Sendable, Equatable {
    public let items: [OutboxItemSnapshot]
    /// Items not yet sent. The header pill reads "3 waiting".
    public let waitingCount: Int
    /// Items that gave up and are asking for a tap.
    public let failedCount: Int
    /// Receipts from the last day. The "Synced earlier today" section.
    public let syncedRecentlyCount: Int
    /// Items whose JSON went and whose photos are queued behind the wi-fi toggle.
    public let awaitingWifiCount: Int
    /// Always zero, and that is the claim screen 17's summary line makes. It is computed rather
    /// than hard-coded so that if the invariant ever broke, the screen would say so.
    public let lostCount: Int

    public init(records: [OutboxStore.Record], treeNames: [UUID: String], now: Date) {
        let dayAgo = now.addingTimeInterval(-OutboxQueue.completedRetention)

        items = records.map { record in
            let payloadTreeID = (try? OutboxPayload.decode(kind: record.item.kind, from: record.item.payload))?.treeID
            let treeID = payloadTreeID ?? UUID()
            return OutboxItemSnapshot(
                id: record.id,
                kind: record.item.kind,
                state: record.item.state,
                failCount: record.item.failCount,
                reason: record.item.lastError,
                errorCode: record.item.lastErrorCode,
                treeID: treeID,
                treeName: treeNames[treeID],
                photoCount: record.item.photoPaths.count,
                createdAt: record.item.createdAt,
                nextAttemptAt: record.nextAttemptAt
            )
        }

        waitingCount = records.filter { $0.item.state == .pending || $0.item.state == .uploading }.count
        failedCount = records.filter { $0.item.state == .failed }.count
        syncedRecentlyCount = records.filter { $0.item.state == .done && $0.item.updatedAt >= dayAgo }.count
        awaitingWifiCount = records.filter { $0.item.state != .done && !$0.item.photoPaths.isEmpty }.count
        // A row that is neither waiting, failed, nor done has no state left to be in. The outbox's
        // four states are exhaustive, so this is structurally zero; it is here because the screen
        // claims it out loud.
        lostCount = records.filter {
            $0.item.state != .pending && $0.item.state != .uploading
                && $0.item.state != .failed && $0.item.state != .done
        }.count
    }
}

/// Screen 17's model.
///
/// TreeObservation-framework observable, not `ObservableObject` (ARCHITECTURE §3), and `@MainActor`
/// because it is UI state. It owns no database handle: every read goes through `OutboxQueue`, which
/// is the actor that owns the connection.
///
/// # Why the conformance is written out instead of using `@Observable`
///
/// `Core` defines `TreeObservation` — the domain type for a light check-in (BUILD-PLAN §4
/// `observations`). Inside this module that type name shadows the *module* named `TreeObservation`, and
/// the `@Observable` macro expands to fully qualified references (`TreeObservation.ObservationRegistrar`,
/// `TreeObservation.Observable`) which then resolve to `Cypress.TreeObservation` and fail to compile:
///
/// ```
/// error: 'Observable' is not a member type of struct 'Cypress.TreeObservation'
/// error: type 'TreeObservation' has no member 'ObservationRegistrar'
/// ```
///
/// There is no import that fixes this — a type in the current module always wins over a module of
/// the same name. Renaming `Core.TreeObservation` would be worse: it is the correct domain word and it
/// is what §4 calls the table. So the three lines the macro would have written are written here
/// instead. The observable behaviour is identical; `@State`, `@Bindable`, and SwiftUI's dependency
/// tracking all work exactly as they would have.
///
/// **This applies to every `@Observable` in the app, not just this one.** Any feature model in this
/// module needs the same treatment.
@MainActor
public final class OutboxViewState: Observable {
    private let registrar = ObservationRegistrar()

    private var storedSnapshot: OutboxSnapshot
    public private(set) var snapshot: OutboxSnapshot {
        get {
            registrar.access(self, keyPath: \.snapshot)
            return storedSnapshot
        }
        set {
            registrar.withMutation(of: self, keyPath: \.snapshot) { storedSnapshot = newValue }
        }
    }

    private var storedIsRefreshing = false
    public private(set) var isRefreshing: Bool {
        get {
            registrar.access(self, keyPath: \.isRefreshing)
            return storedIsRefreshing
        }
        set {
            registrar.withMutation(of: self, keyPath: \.isRefreshing) { storedIsRefreshing = newValue }
        }
    }

    private var storedRefreshError: String?
    /// The last error refreshing itself hit. Failing to *read* the outbox is a different problem
    /// from failing to *send* it, and the screen should not confuse the two.
    public private(set) var refreshError: String? {
        get {
            registrar.access(self, keyPath: \.refreshError)
            return storedRefreshError
        }
        set {
            registrar.withMutation(of: self, keyPath: \.refreshError) { storedRefreshError = newValue }
        }
    }

    private var storedSyncPhotosOnWifiOnly: Bool
    /// Screen 17's toggle: "Sync photos on wifi only". Applies to photo binaries only; notes and
    /// numbers sync on any connection (BUILD-PLAN §4).
    public var syncPhotosOnWifiOnly: Bool {
        get {
            registrar.access(self, keyPath: \.syncPhotosOnWifiOnly)
            return storedSyncPhotosOnWifiOnly
        }
        set {
            guard newValue != storedSyncPhotosOnWifiOnly else { return }
            registrar.withMutation(of: self, keyPath: \.syncPhotosOnWifiOnly) {
                storedSyncPhotosOnWifiOnly = newValue
            }
            Task { await self.persistWifiPreference(newValue) }
        }
    }

    private let queue: OutboxQueue
    private let store: CypressStore?
    /// Resolves a tree id to the name a row should show. Supplied by the composition root so this
    /// type does not reach into the API itself.
    private let treeNameResolver: @Sendable ([UUID]) async -> [UUID: String]
    private var observerToken: UUID?

    public init(
        queue: OutboxQueue,
        store: CypressStore? = nil,
        syncPhotosOnWifiOnly: Bool = true,
        treeNameResolver: @escaping @Sendable ([UUID]) async -> [UUID: String] = { _ in [:] }
    ) {
        self.queue = queue
        self.store = store
        self.storedSyncPhotosOnWifiOnly = syncPhotosOnWifiOnly
        self.treeNameResolver = treeNameResolver
        self.storedSnapshot = OutboxSnapshot(records: [], treeNames: [:], now: Date())
    }

    /// Subscribes to the queue so the screen follows a drain without polling.
    public func start() async {
        guard observerToken == nil else { return }
        observerToken = await queue.addObserver { [weak self] in
            await self?.refresh()
        }
        if let stored = try? await store?.appState(.syncPhotosOnWifiOnly) {
            syncPhotosOnWifiOnly = (stored as NSString).boolValue
        }
        await refresh()
    }

    public func stop() async {
        if let observerToken { await queue.removeObserver(observerToken) }
        observerToken = nil
    }

    public func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let records = try await queue.records()
            let treeIDs = records.compactMap {
                (try? OutboxPayload.decode(kind: $0.item.kind, from: $0.item.payload))?.treeID
            }
            let names = await treeNameResolver(Array(Set(treeIDs)))
            snapshot = OutboxSnapshot(records: records, treeNames: names, now: Date())
            refreshError = nil
        } catch {
            refreshError = "Could not read the outbox."
        }
    }

    /// The retry button on an amber attention card.
    public func retry(id: UUID) async {
        _ = try? await queue.retry(id: id)
    }

    public func retryAll() async {
        _ = try? await queue.retryAllFailed()
    }

    /// Drains, honouring the wi-fi toggle.
    ///
    /// - Parameter isOnWifi: whether the current connection is unmetered. The toggle only bites
    ///   when it is off.
    public func syncNow(isOnWifi: Bool) async {
        _ = try? await queue.drain(photoUploadsAllowed: isOnWifi || !syncPhotosOnWifiOnly)
    }

    private func persistWifiPreference(_ value: Bool) async {
        try? await store?.setAppState(.syncPhotosOnWifiOnly, to: value ? "true" : "false")
    }
}
