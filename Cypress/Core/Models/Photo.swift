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
    ///
    /// **This is not the predicate a screen on the contributor's own device asks.** Nothing in the
    /// shipping app can set `.approved` — there is no moderation service, both `beginPhotoUpload`
    /// and `addTree` construct photos as `.pending`, and the schema's default is `'pending'` — so a
    /// surface gated on this shows nothing at all. Which is right for a *public* surface, and wrong
    /// for showing somebody the photograph they just took. See `Photo.isPubliclyVisible` and
    /// `Photo.isVisibleToItsContributor` for the two halves, kept apart on purpose (ERRATA E37).
    public var isPubliclyVisible: Bool { self == .approved }
}

/// A photo (BUILD-PLAN §4 `photos`).
///
/// EXIF, including GPS, is stripped on ingest; the capture timestamp and the app's own fuzzed
/// coordinates live in columns, never in the file (BUILD-PLAN §3, DECISIONS §3.10). There is
/// therefore no `exifGPS` property here, and `publicCoordinate` is pre-snapped to the 25 m grid.
///
/// This paragraph used to say "server-side", and it was a description of a thing nobody did: there
/// is no server, and the local ingest path moved the camera's file across untouched. It is
/// `PhotoBinary.writeStrippingMetadata`, called from `LocalAPI.uploadPhoto`, that makes the sentence
/// true (ERRATA E40). `publicCoordinate` is deliberately left nil by everything that ships — not
/// storing a location is the privacy-safe direction, and E42 says why.
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

    // MARK: - Who may see it
    //
    // Two questions, deliberately two names. "The world can see this" is moderation's answer and it
    // gates every public surface. "I can see this" is a different question with a different answer:
    // moderation is a gate on publication, not a gate between a contributor and the photograph they
    // took on the device they took it with. DECISIONS §3 puts moderation on public timelines,
    // published locations and the open export, and says nothing about a person's own screen.
    //
    // A predicate that meant both would have to pick one, and picking the public one is what left
    // the app with no photograph anywhere: no hero, no season strip, no best photo, on every tree
    // (ERRATA E37).

    /// Whether this photo may be shown on a **public** surface — the shared tree page, the share
    /// card, anything a stranger can reach (BUILD-PLAN §10, A3).
    ///
    /// Nothing in the app today can make this true, because nothing moderates. That is honest: a
    /// `.pending` photo has in fact not been moderated, and marking it `.approved` to make a screen
    /// render would be a claim about a review that never happened.
    public var isPubliclyVisible: Bool {
        moderationState.isPubliclyVisible && deletedAt == nil
    }

    /// Whether the person who contributed this photo may see it on their own device.
    ///
    /// Moderation does not enter into it. What does is deletion: a removed photo is removed for
    /// everybody. The caller is responsible for having established that the photo is in fact this
    /// contributor's — `TreeProfile.ownPhotoIDs` is where that fact is carried.
    public var isVisibleToItsContributor: Bool { deletedAt == nil }

    /// A3's eligibility half for the **public** best photo: most recent approved `full_tree`, ties
    /// broken by resolution; a manual pin by any org member overrides.
    public var isPublicBestPhotoCandidate: Bool {
        shotType == .fullTree && isPubliclyVisible
    }

    /// A3's framing half alone, for choosing the best photo out of a set whose visibility the
    /// caller has already decided. Applying this to an unfiltered series would publish a photo
    /// nobody approved; applying `isPublicBestPhotoCandidate` to a device-local set would show the
    /// contributor nothing.
    public var isBestPhotoShot: Bool {
        shotType == .fullTree && deletedAt == nil
    }
}
