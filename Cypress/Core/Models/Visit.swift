import Foundation

/// A ten-second "I was here": photo plus optional note (BUILD-PLAN §4 `visits`, PRODUCT §3).
///
/// No judgment is required on the visit path (PRODUCT §1); every field beyond the photo is optional.
public struct Visit: FieldCaptured {
    public let id: UUID
    public let treeID: UUID
    /// Nil for an anonymous, device-local first save (D9).
    public let userID: UUID?
    public let deviceID: UUID
    /// Idempotency key the server dedupes on (BUILD-PLAN §4, DECISIONS §3.8).
    public let clientUUID: UUID
    public var note: String?
    /// Validated against the species seasonal vocabulary (BUILD-PLAN §4). Build these with
    /// `PhenologyTag.validated(_:for:)` so an evergreen never carries `fall_color` (D5).
    public var phenologyTags: [PhenologyTag]
    /// Per-contribution GPS accuracy (D6). Feeds `isEligibleForGrowthCharting`.
    public let gpsAccuracyM: Double?
    public let capturedAt: Date
    public let createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        treeID: UUID,
        attribution: Attribution,
        clientUUID: UUID = UUID(),
        note: String? = nil,
        phenologyTags: [PhenologyTag] = [],
        gpsAccuracyM: Double? = nil,
        capturedAt: Date,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.treeID = treeID
        self.userID = attribution.userID
        self.deviceID = attribution.deviceID
        self.clientUUID = clientUUID
        self.note = note
        self.phenologyTags = phenologyTags
        self.gpsAccuracyM = gpsAccuracyM
        self.capturedAt = capturedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    public var attribution: Attribution { Attribution(userID: userID, deviceID: deviceID) }
}
