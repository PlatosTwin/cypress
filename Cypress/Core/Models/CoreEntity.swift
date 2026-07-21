import Foundation

/// Every table gets `id uuid primary key, created_at, updated_at` (BUILD-PLAN §4).
///
/// Coding-key convention for the whole of `Core`: keys are the Swift property names. The
/// snake_case column, jsonb, and wire names of BUILD-PLAN §4 and §6 are produced by the coder's
/// key-conversion strategy in `Data`, in one place, rather than restated on every type. Enum *raw
/// values* are the opposite: those are written out verbatim, because they are the stored values.
public protocol CoreEntity: Identifiable, Hashable, Codable, Sendable {
    var id: UUID { get }
    var createdAt: Date { get }
    var updatedAt: Date { get }
}

/// "Every table that users touch gets soft delete via deleted_at" (BUILD-PLAN §4).
///
/// Nothing in `Core` ever hard-deletes: sync needs the tombstone (BUILD-PLAN §4, favorites), and
/// account deletion anonymizes attributed rows rather than removing them (DECISIONS §3.12).
public protocol SoftDeletable {
    var deletedAt: Date? { get }
}

extension SoftDeletable {
    public var isDeleted: Bool { deletedAt != nil }
}

/// A contribution that travels through the outbox.
///
/// `clientUUID` is the idempotency key the server dedupes on; zero loss and zero duplicates across
/// network flaps is a CI-enforced acceptance criterion (DECISIONS §3.8, BUILD-PLAN §13).
public protocol SyncableMutation: CoreEntity, SoftDeletable {
    var clientUUID: UUID { get }
}

/// A contribution captured in the field, carrying the GPS accuracy of the moment of capture (D6).
public protocol FieldCaptured: SyncableMutation {
    var capturedAt: Date { get }
    var gpsAccuracyM: Double? { get }
}

extension FieldCaptured {
    /// Points captured with GPS accuracy worse than 15 m are excluded from per-tree growth charts
    /// (D6, BUILD-PLAN §4). Unknown accuracy is treated as unusable rather than assumed good.
    public var isEligibleForGrowthCharting: Bool {
        guard let gpsAccuracyM else { return false }
        return gpsAccuracyM <= GPSAccuracy.growthChartingLimitM
    }
}

public enum GPSAccuracy {
    /// "Points with gps_accuracy_m above 15 are excluded from per-tree charts" (D6, BUILD-PLAN §4).
    public static let growthChartingLimitM: Double = 15
}

/// Authorship of a contribution.
///
/// `userID` is nullable everywhere because first saves are anonymous and local to the device under
/// a device id, migrating to the user at `POST /devices/claim` (D9, BUILD-PLAN §4). Account
/// deletion nulls `userID` and severs the device link rather than deleting the row (DECISIONS §3.12).
public struct Attribution: Hashable, Codable, Sendable {
    public let userID: UUID?
    public let deviceID: UUID

    public init(userID: UUID?, deviceID: UUID) {
        self.userID = userID
        self.deviceID = deviceID
    }

    public static func anonymous(deviceID: UUID) -> Attribution {
        Attribution(userID: nil, deviceID: deviceID)
    }

    public var isAnonymous: Bool { userID == nil }
}
