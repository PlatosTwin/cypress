import Foundation

/// `photos.shot_type` (BUILD-PLAN §4), verbatim.
///
/// PRODUCT §3 lists a longer set (`trunk_dbh`, `canopy_up`, `leaf_closeup`, `site`); BUILD-PLAN
/// wins on data (ARCHITECTURE §1), so the four below are the stored vocabulary.
public enum ShotType: String, Codable, Sendable, Hashable, CaseIterable {
    case fullTree = "full_tree"
    case trunk = "trunk"
    case leaf = "leaf"
    case other = "other"

    /// The ghost overlay reuses the last full-tree photo at 30 % opacity (PRODUCT §5 M4).
    public var supportsGhostOverlay: Bool { self == .fullTree }
}

/// `photos.moderation_state` (BUILD-PLAN §4).
public enum ModerationState: String, Codable, Sendable, Hashable, CaseIterable {
    case pending = "pending"
    case approved = "approved"
    case rejected = "rejected"

    /// Only approved photos reach a public surface (BUILD-PLAN §10, A3).
    public var isPubliclyVisible: Bool { self == .approved }
}

/// A photo (BUILD-PLAN §4 `photos`).
///
/// EXIF, including GPS, is stripped server-side on ingest; the capture timestamp and the app's own
/// fuzzed coordinates live in columns, never in the file (BUILD-PLAN §3, DECISIONS §3.10). There is
/// therefore no `exifGPS` property here, and `publicCoordinate` is pre-snapped to the 25 m grid.
public struct Photo: CoreEntity, SoftDeletable {
    public let id: UUID
    public let treeID: UUID
    /// Nil when the photo was attached outside a visit (e.g. a care event or an observation).
    public let visitID: UUID?
    public var storageKey: String?
    public var shotType: ShotType
    public var moderationState: ModerationState
    /// Face and licence-plate blurring runs at upload (BUILD-PLAN §10).
    public var blurApplied: Bool
    public var width: Int?
    public var height: Int?
    public let capturedAt: Date
    /// The app's own coordinate for this photo, already snapped to the universal 25 m grid
    /// (A7, BUILD-PLAN §10). Nil when no location was captured.
    public var publicCoordinate: Coordinate?
    public let createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        treeID: UUID,
        visitID: UUID? = nil,
        storageKey: String? = nil,
        shotType: ShotType,
        moderationState: ModerationState = .pending,
        blurApplied: Bool = false,
        width: Int? = nil,
        height: Int? = nil,
        capturedAt: Date,
        publicCoordinate: Coordinate? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.treeID = treeID
        self.visitID = visitID
        self.storageKey = storageKey
        self.shotType = shotType
        self.moderationState = moderationState
        self.blurApplied = blurApplied
        self.width = width
        self.height = height
        self.capturedAt = capturedAt
        self.publicCoordinate = publicCoordinate.map { $0.snappedToPublicPhotoGrid() }
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    /// Pixel count, the tie-breaker for "best photo" (A3).
    public var resolution: Int { (width ?? 0) * (height ?? 0) }

    /// "Best photo" = most recent approved `full_tree` photo, ties broken by resolution; a manual
    /// pin by any org member overrides (A3). This predicate covers the eligibility half.
    public var isBestPhotoCandidate: Bool {
        shotType == .fullTree && moderationState == .approved && deletedAt == nil
    }
}
