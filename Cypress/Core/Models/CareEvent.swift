import Foundation

/// `care_events.actions text[]` (BUILD-PLAN §4), verbatim.
///
/// PRODUCT §3 records two other wordings for this vocabulary ("weeded basin, litter cleared, other"
/// and "stake removed"); BUILD-PLAN wins on data (ARCHITECTURE §1). There is no free-text "other"
/// action in the BUILD-PLAN set — free text goes in `note`.
public enum CareAction: String, Codable, Sendable, Hashable, CaseIterable {
    case watered = "watered"
    case mulched = "mulched"
    case weeded = "weeded"
    case litterCleared = "litter_cleared"
    case staked = "staked"
}

/// A quick care log, ≤30 s (BUILD-PLAN §4 `care_events`, PRODUCT §5 M5).
///
/// "Never publicly counted or ranked" (D1, BUILD-PLAN §4). Nothing in this type exposes a count,
/// and nothing may aggregate it into a user-visible total (DECISIONS §3.1).
public struct CareEvent: FieldCaptured {
    public let id: UUID
    public let treeID: UUID
    public let userID: UUID?
    public let deviceID: UUID
    public let clientUUID: UUID
    public let capturedAt: Date
    /// Care events are not charted; accuracy is stored for consistency with the other field
    /// contributions (D6).
    public let gpsAccuracyM: Double?
    public var actions: [CareAction]
    public var note: String?
    /// Photo optional (BUILD-PLAN §4).
    public var photoID: UUID?
    public let createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        treeID: UUID,
        attribution: Attribution,
        clientUUID: UUID = UUID(),
        capturedAt: Date,
        gpsAccuracyM: Double? = nil,
        actions: [CareAction],
        note: String? = nil,
        photoID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.treeID = treeID
        self.userID = attribution.userID
        self.deviceID = attribution.deviceID
        self.clientUUID = clientUUID
        self.capturedAt = capturedAt
        self.gpsAccuracyM = gpsAccuracyM
        self.actions = actions
        self.note = note
        self.photoID = photoID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    public var attribution: Attribution { Attribution(userID: userID, deviceID: deviceID) }
}

/// `favorites` (BUILD-PLAN §4).
///
/// The unique pair is (userID, treeID). Deletion is a tombstone, never a hard delete: sync needs
/// the tombstone, and favorites are the one non-append-only contribution — they sync as toggle
/// events (BUILD-PLAN §4 and §6, DECISIONS §3.7).
public struct Favorite: CoreEntity, SoftDeletable, SyncableMutation {
    public let id: UUID
    public let userID: UUID
    public let treeID: UUID
    public let clientUUID: UUID
    public let createdAt: Date
    public var updatedAt: Date
    /// Tombstone. An unfavorite sets this; the row stays (BUILD-PLAN §4).
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        userID: UUID,
        treeID: UUID,
        clientUUID: UUID = UUID(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.userID = userID
        self.treeID = treeID
        self.clientUUID = clientUUID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    /// The current state of the toggle.
    public var isActive: Bool { deletedAt == nil }
}
