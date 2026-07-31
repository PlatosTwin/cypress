import Foundation

/// The status a check-in can report (PRODUCT §5 M6: "alive, declining, appears dead, appears
/// removed"; BUILD-PLAN §4 `observations.status text nullable`).
///
/// Deliberately **not** `TreeStatus`. An observation never mutates `trees.status`: the last two
/// cases open a review flag that a moderator or org coordinator confirms (DECISIONS §3.7,
/// BUILD-PLAN §6). Keeping the two vocabularies as separate types means no code path can assign a
/// reported status straight onto a tree.
public enum ObservationStatus: String, Codable, Sendable, Hashable, CaseIterable {
    case alive = "alive"
    case declining = "declining"
    case appearsDead = "appears_dead"
    case appearsRemoved = "appears_removed"

    /// The two cases that trigger a confirmation dialog and a review flag (PRODUCT §5 M6).
    ///
    /// **Both halves of that sentence are now true** (ERRATA E170). The flag half always was — see
    /// `reviewFlagKind` and `LocalAPI.apply(_:)`. The dialog half was documentation of a feature that
    /// did not exist: this property had no caller in shipping code, and screen 05 changed the segment
    /// on one tap with nothing asked. `CheckInModel.select(status:)` now reads it, holds the tap in
    /// `pendingStatus`, and `CheckInView` asks before the claim is made — which is worth the second
    /// tap, because these are the only two segments on the card that put work in front of another
    /// person. It also gates the sentence screen 05 draws about where that work goes
    /// (`CheckInCopy.reviewNotice`).
    public var opensReviewFlag: Bool {
        switch self {
        case .appearsDead, .appearsRemoved: return true
        case .alive, .declining: return false
        }
    }

    /// The review flag this status raises, if any (BUILD-PLAN §4 `review_flags.kind`).
    public var reviewFlagKind: ReviewFlag.Kind? {
        switch self {
        case .appearsDead: return .appearsDead
        case .appearsRemoved: return .appearsRemoved
        case .alive, .declining: return nil
        }
    }
}

/// Foliage density (PRODUCT §5 M6, step 3).
public enum FoliageDensity: String, Codable, Sendable, Hashable, CaseIterable {
    case full = "full"
    case thinning = "thinning"
    case sparse = "sparse"
    case bareInSeason = "bare_in_season"
}

/// Foliage discoloration (PRODUCT §5 M6, step 3).
public enum FoliageDiscoloration: String, Codable, Sendable, Hashable, CaseIterable {
    case none = "none"
    case some = "some"
    case severe = "severe"
}

/// Foliage damage (PRODUCT §5 M6, step 3).
public enum FoliageDamage: String, Codable, Sendable, Hashable, CaseIterable {
    case none = "none"
    case chewed = "chewed"
    case spotted = "spotted"
    case scorched = "scorched"
}

/// The three foliage axes of the light check-in (PRODUCT §5 M6).
///
/// BUILD-PLAN §4 stores this as a single `foliage text nullable` column; this struct is what
/// serializes into it. Every axis is optional — everything on the check-in card can be skipped
/// (PRODUCT §5 M6: "Everything can be skipped; only status has a default (alive)").
public struct FoliageAssessment: Hashable, Codable, Sendable {
    public var density: FoliageDensity?
    public var discoloration: FoliageDiscoloration?
    public var damage: FoliageDamage?

    public init(
        density: FoliageDensity? = nil,
        discoloration: FoliageDiscoloration? = nil,
        damage: FoliageDamage? = nil
    ) {
        self.density = density
        self.discoloration = discoloration
        self.damage = damage
    }

    public var isEmpty: Bool { density == nil && discoloration == nil && damage == nil }
}

/// `observations.structure_flags text[]` (BUILD-PLAN §4, PRODUCT §5 M6 step 4).
///
/// Carries the UI label "informal observations, not a risk assessment", which is also written into
/// the export header (BUILD-PLAN §4). Structure flags stay available year-round, including when
/// vitality is suppressed off-season (PRODUCT §3 seasonality rule).
public enum StructureFlag: String, Codable, Sendable, Hashable, CaseIterable {
    case lean = "lean"
    case brokenLimb = "broken_limb"
    case trunkWound = "trunk_wound"
    case rootHeave = "root_heave"
    case hardwareIssue = "hardware_issue"

    /// The disclaimer that must accompany any surface showing these flags, and that is carried into
    /// the export header (BUILD-PLAN §4).
    public static let disclaimer = "informal observations, not a risk assessment"
}

/// A light check-in (BUILD-PLAN §4 `observations`, PRODUCT §5 M6).
///
/// One scrollable card, not a step wizard, ≤60 s. Everything is optional except `status`, which
/// defaults to `.alive`.
public struct TreeObservation: FieldCaptured {
    public let id: UUID
    public let treeID: UUID
    public let userID: UUID?
    public let deviceID: UUID
    public let clientUUID: UUID
    public let capturedAt: Date
    public let gpsAccuracyM: Double?
    public var status: ObservationStatus?
    /// The anchored 1–5 class. Suppressed off-season for deciduous species — see
    /// `Vitality.isRatingPermitted(for:month:)` (PRODUCT §3).
    public var vitality: Vitality?
    public var foliage: FoliageAssessment?
    public var structureFlags: [StructureFlag]
    public var note: String?
    /// Every observation carries a verification state (D12, BUILD-PLAN §4).
    public var verificationState: VerificationState
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
        status: ObservationStatus? = .alive,
        vitality: Vitality? = nil,
        foliage: FoliageAssessment? = nil,
        structureFlags: [StructureFlag] = [],
        note: String? = nil,
        verificationState: VerificationState = .unverified,
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
        self.status = status
        self.vitality = vitality
        self.foliage = foliage
        self.structureFlags = structureFlags
        self.note = note
        self.verificationState = verificationState
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    public var attribution: Attribution { Attribution(userID: userID, deviceID: deviceID) }

    /// The review flag this check-in raises, if any. Raising it is the *only* effect a reported
    /// status has on the tree (DECISIONS §3.7).
    public var raisesReviewFlagKind: ReviewFlag.Kind? { status?.reviewFlagKind }
}
