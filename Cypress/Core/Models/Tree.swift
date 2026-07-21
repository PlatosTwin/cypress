import Foundation

/// `trees.status` (BUILD-PLAN §4), verbatim.
///
/// Note the conflict with PRODUCT §3, which lists `dead_standing` and `stump`. BUILD-PLAN wins on
/// product and data (ARCHITECTURE §1 precedence), so `dead_reported` is the case and there is no
/// `stump`.
///
/// A status transition is never a side effect of an observation: `appears_dead` / `appears_removed`
/// open a review flag that a moderator or org coordinator confirms (DECISIONS §3.7, BUILD-PLAN §6).
public enum TreeStatus: String, Codable, Sendable, Hashable, CaseIterable {
    case alive = "alive"
    case declining = "declining"
    case deadReported = "dead_reported"
    case removed = "removed"
    case vacantSite = "vacant_site"

    /// A removed tree's profile becomes a read-only memorial record, not a 404
    /// (PRODUCT §3, DECISIONS §3.17).
    public var isMemorial: Bool { self == .removed }
}

/// `trees.source` (BUILD-PLAN §4).
///
/// Community-added trees stay in a visually distinct layer and never render as part of the official
/// city inventory until verified (DECISIONS §3.16).
public enum TreeSource: String, Codable, Sendable, Hashable, CaseIterable {
    case cityImport = "city_import"
    case community = "community"
}

/// `verification_state` on trees and observations (D12, BUILD-PLAN §4 and §5).
///
/// "There is no UI-only provenance; every provenance fact is a queryable column" (BUILD-PLAN §5).
public enum VerificationState: String, Codable, Sendable, Hashable, CaseIterable {
    /// Everything that is neither a city row nor org-confirmed.
    case unverified = "unverified"
    /// Made or confirmed by an org member with the steward or coordinator role (BUILD-PLAN §5).
    case orgVerified = "org_verified"
    /// Came from the city import untouched (BUILD-PLAN §5).
    case cityRecord = "city_record"

    /// The export README states plainly that unverified rows are not fit for inventory ingestion
    /// (D12, BUILD-PLAN §5).
    public var isFitForInventoryIngestion: Bool { self != .unverified }
}

/// `trees.site_type` — the DataSF `qSiteInfo` value, kept as free text because the source
/// vocabulary is open-ended (BUILD-PLAN §7). Not an enum for that reason.
public typealias SiteType = String

/// A tree (BUILD-PLAN §4 `trees`, PRODUCT §3 "Tree").
///
/// `id` is immutable and persists through death, removal, and replanting; it is stable and citable
/// from day one (PRODUCT §3, DECISIONS §3.13).
public struct Tree: CoreEntity, SoftDeletable {
    public let id: UUID
    /// DataSF `TreeID`. Nullable and unique; the key the weekly diff matches on (BUILD-PLAN §7).
    public var externalRef: String?
    public var source: TreeSource
    /// `geom geometry(Point, 4326)`. Tree pins are exact; only photo locations are fuzzed
    /// (BUILD-PLAN §10).
    public var coordinate: Coordinate
    public var address: String?
    public var siteType: SiteType?
    public var neighborhoodID: UUID?
    public var status: TreeStatus
    /// Denormalized from the latest accepted assertion (BUILD-PLAN §4). The assertion chain in
    /// `SpeciesAssertion` is the source of truth; this is a read cache.
    public var speciesCurrentID: UUID?
    public var plantedYear: Int?
    /// "seed data is a range, never a point" (BUILD-PLAN §4). Must never render as a measured DBH;
    /// use `TreeMeasurement` for that.
    public var dbhCityCmRange: IntRange?
    /// Links a replanted site to the removed tree that preceded it (BUILD-PLAN §4, PRODUCT §3).
    public var siteLineage: UUID?
    public var verificationState: VerificationState
    public let createdAt: Date
    public var updatedAt: Date
    /// City sync never deletes community contributions; removal is a status, not a delete
    /// (DECISIONS §3.17).
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        externalRef: String? = nil,
        source: TreeSource,
        coordinate: Coordinate,
        address: String? = nil,
        siteType: SiteType? = nil,
        neighborhoodID: UUID? = nil,
        status: TreeStatus = .alive,
        speciesCurrentID: UUID? = nil,
        plantedYear: Int? = nil,
        dbhCityCmRange: IntRange? = nil,
        siteLineage: UUID? = nil,
        verificationState: VerificationState = .unverified,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.externalRef = externalRef
        self.source = source
        self.coordinate = coordinate
        self.address = address
        self.siteType = siteType
        self.neighborhoodID = neighborhoodID
        self.status = status
        self.speciesCurrentID = speciesCurrentID
        self.plantedYear = plantedYear
        self.dbhCityCmRange = dbhCityCmRange
        self.siteLineage = siteLineage
        self.verificationState = verificationState
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

/// `tree_names` (D15, BUILD-PLAN §4).
///
/// One active name per tree; first namer wins; renames go through the same moderation queue as
/// photos. The species common name is the fallback display everywhere.
public struct TreeName: CoreEntity, SoftDeletable {
    public enum Status: String, Codable, Sendable, Hashable, CaseIterable {
        case active = "active"
        case retired = "retired"
        case removedByModeration = "removed_by_moderation"
    }

    public let id: UUID
    public let treeID: UUID
    public var name: String
    /// `given_by fk users`.
    public let givenBy: UUID?
    public var status: Status
    public let createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        treeID: UUID,
        name: String,
        givenBy: UUID?,
        status: Status = .active,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.treeID = treeID
        self.name = name
        self.givenBy = givenBy
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    public var isDisplayable: Bool { status == .active && deletedAt == nil }
}
