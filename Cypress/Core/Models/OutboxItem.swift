import Foundation

/// A photo binary waiting in the outbox, and the framing the contributor chose for it.
///
/// The shot type travels **with** the path because it is not recoverable from anything else: the
/// file is a JPEG on disk, the payload beside it is a `Visit`, and `photos.shot_type` is written at
/// upload from whatever the transport was handed (BUILD-PLAN §4, §6 `POST /photos/begin`). A path
/// on its own forces the upload to guess, and a guess is permanent on an append-only record.
public struct OutboxPhoto: Codable, Hashable, Sendable {
    /// Where the binary is staged on device. See `VisitPhotoStaging`.
    public let path: String
    /// The chip the contributor tapped on screen 04.
    public let shotType: ShotType

    public init(path: String, shotType: ShotType) {
        self.path = path
        self.shotType = shotType
    }

    /// Decodes both the current object form and the bare-string form this column held before shot
    /// types travelled with paths.
    ///
    /// The outbox is durable across launches, so an upgrade can meet rows written by the previous
    /// build. `AppSchema` v2 rewrites those rows, but this decoder handles the shape too: a decode
    /// failure here would drop a contributor's pending visit, which is worse than any labelling
    /// mistake. Old rows become `.other` for the reason given on that migration.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let path = try? container.decode(String.self) {
            self.path = path
            self.shotType = OutboxPhoto.shotTypeForRowsWrittenBeforeShotTypesTravelled
            return
        }
        let keyed = try decoder.container(keyedBy: CodingKeys.self)
        self.path = try keyed.decode(String.self, forKey: .path)
        self.shotType = try keyed.decode(ShotType.self, forKey: .shotType)
    }

    /// What a photo queued by a build that did not record shot types is called.
    ///
    /// `.other` rather than `.fullTree`. The old code labelled every upload `full_tree`, and that is
    /// exactly the labelling this change exists to stop: a full-tree label is what makes a photo
    /// eligible to be a ghost-overlay reference and the tree's best photo (A3, `supportsGhostOverlay`
    /// and `Photo.isBestPhotoShot`). Carrying that guess forward would keep offering a leaf
    /// close-up as the framing reference for a whole tree, permanently, with no way to tell which
    /// records were guesses. `.other` is the stored vocabulary's "unclassified" (BUILD-PLAN §4): the
    /// photo still reaches the timeline, it just does not get promoted on a label nobody chose.
    public static let shotTypeForRowsWrittenBeforeShotTypesTravelled: ShotType = .other
}

/// The client-side outbox row (BUILD-PLAN §4, "Client-side outbox (SQLite on device)").
///
/// Every mutation is written here *first* and only then attempted against the API — true even
/// though the API is currently local: "the outbox is the feature, not a network workaround"
/// (ARCHITECTURE §4). The outbox is visible in the UI and never gets silently stuck (PRODUCT §3).
public struct OutboxItem: CoreEntity {
    /// `outbox.kind` (BUILD-PLAN §4), verbatim. One case per syncable mutation type.
    public enum Kind: String, Codable, Sendable, Hashable, CaseIterable {
        case visit = "visit"
        case observation = "observation"
        case measurement = "measurement"
        case careEvent = "care_event"
        case favoriteToggle = "favorite_toggle"
        /// D4's private reminder. Not in §4's original list, because §4 was written while the
        /// reminder needed an account it could not have (ERRATA E23); §6 already says its POST is
        /// separate from the hazard-redirect log, so it is a mutation like any other and queues like
        /// one. `AppSchema` v4 widens the stored vocabulary to match.
        case privateReminder = "private_reminder"
    }

    /// `outbox.state` (BUILD-PLAN §4), verbatim. Screen 17 shows per-item state and retry.
    public enum State: String, Codable, Sendable, Hashable, CaseIterable {
        case pending = "pending"
        case uploading = "uploading"
        case failed = "failed"
        case done = "done"

        /// `failed` is terminal until the user taps the visible retry button (BUILD-PLAN §4).
        public var isTerminal: Bool { self == .done || self == .failed }
    }

    public let id: UUID
    public let kind: Kind
    /// The idempotency key the server dedupes on. Identical to the `clientUUID` of the mutation
    /// carried in `payload` (BUILD-PLAN §4 and §6, DECISIONS §3.8).
    public let clientUUID: UUID
    /// The mutation, JSON-encoded. `Core` stays serialization-agnostic; `Data` owns the codecs.
    public let payload: Data
    /// Photo binaries not yet uploaded, each with its shot type. Photos stay on device until upload
    /// is confirmed; the wifi-only toggle applies to these binaries only (BUILD-PLAN §4, PRODUCT §8).
    public var photos: [OutboxPhoto]
    public var state: State
    public var failCount: Int
    /// The "says why" line on screen 17 (BUILD-PLAN §6 `GET /me/outbox-status`).
    public var lastError: String?
    /// The taxonomy code behind `lastError`, when the failure came from the API. Drives whether the
    /// item is retried at all.
    public var lastErrorCode: APIError?
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        kind: Kind,
        clientUUID: UUID,
        payload: Data,
        photos: [OutboxPhoto] = [],
        state: State = .pending,
        failCount: Int = 0,
        lastError: String? = nil,
        lastErrorCode: APIError? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.clientUUID = clientUUID
        self.payload = payload
        self.photos = photos
        self.state = state
        self.failCount = failCount
        self.lastError = lastError
        self.lastErrorCode = lastErrorCode
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// The retry schedule, verbatim from BUILD-PLAN §4:
/// "exponential backoff 30 s, 2 m, 10 m, 1 h, then hourly; cap 48 h then state failed with a
/// visible retry button (screen 17)".
public enum OutboxRetryPolicy {
    /// Delays after failure 1, 2, 3, 4. Failures beyond that repeat the last entry (hourly).
    public static let backoff: [TimeInterval] = [30, 120, 600, 3600]
    /// After 48 h of trying, the item goes to `failed` and waits for the user.
    public static let cap: TimeInterval = 48 * 60 * 60

    /// The delay before the next attempt, given how many attempts have already failed.
    public static func delay(afterFailures failCount: Int) -> TimeInterval {
        guard failCount > 0 else { return 0 }
        let index = min(failCount, backoff.count) - 1
        return backoff[index]
    }

    /// Whether an item has exhausted the 48 h window and should move to `failed`.
    public static func hasExpired(createdAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(createdAt) >= cap
    }

    /// The next state for an item that just failed, honouring both the taxonomy and the cap.
    /// A non-retryable code (`validation_failed`, `conflict`, …) fails immediately rather than
    /// burning 48 h of backoff on an answer that will not change (BUILD-PLAN §6).
    public static func nextState(
        for item: OutboxItem,
        error: APIError?,
        now: Date
    ) -> OutboxItem.State {
        if let error, !error.retryable { return .failed }
        if hasExpired(createdAt: item.createdAt, now: now) { return .failed }
        return .pending
    }

    /// When the next attempt is due, or nil once the item is terminal.
    public static func nextAttempt(for item: OutboxItem, now: Date) -> Date? {
        guard item.state == .pending else { return nil }
        return now.addingTimeInterval(delay(afterFailures: item.failCount))
    }
}

/// Per-item result of `POST /sync` (BUILD-PLAN §6).
///
/// `duplicate` is a success: the server deduped on `client_uuid`, which is exactly what makes the
/// outbox chaos test's "zero duplicates" assertion hold (DECISIONS §3.8, BUILD-PLAN §13).
public struct SyncResult: Hashable, Codable, Sendable {
    public enum Status: String, Codable, Sendable, Hashable, CaseIterable {
        case applied = "applied"
        case duplicate = "duplicate"
        case failed = "failed"
    }

    public let clientUUID: UUID
    public let status: Status
    public let error: APIError?

    public init(clientUUID: UUID, status: Status, error: APIError? = nil) {
        self.clientUUID = clientUUID
        self.status = status
        self.error = error
    }

    public var isSuccess: Bool { status == .applied || status == .duplicate }
}
