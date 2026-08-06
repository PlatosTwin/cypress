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

    /// Whether this is a tree screen 01's `Needs care` chip is asking for — "this tree needs
    /// something", the amber pin of SCREENS.md 01 §8.
    ///
    /// **It lives here, on the status, because three layers have to agree about it and two of them
    /// are in modules that cannot see each other.** `MapPinKind` draws the amber pin from it,
    /// `TreeQueries.Narrowing` builds `AND t.status IN (…)` from it, and `LocalAPI` filters the
    /// community layer with it. Before task #240 the drawn pin read `status == .declining` in
    /// `Features` and the query layer knew nothing about the chip at all — which is exactly how the
    /// chip came to narrow the pins and leave the cluster badges standing.
    ///
    /// Exhaustive for `acceptsNewContributions`' reason (E95): a new `TreeStatus` has to be a
    /// compile error here rather than a silent "no, that one never needs care".
    ///
    /// **`deadReported` is deliberately not in this arm**, and it is the one worth arguing. A
    /// reported death is a claim awaiting a lead's confirmation (DECISIONS §3.7), not a condition a
    /// passer-by can act on, and `MapPinKind` has never drawn it amber — admitting it here would
    /// make one word mean two things on one screen, with the chip and the pin disagreeing. `removed`
    /// and `vacantSite` have no tree to need anything.
    public var needsCare: Bool {
        switch self {
        case .declining:
            return true
        case .alive, .deadReported, .removed, .vacantSite:
            return false
        }
    }

    /// Whether a record in this state can take a new contribution.
    ///
    /// Two states cannot, for opposite reasons: a vacant site has no tree yet, and a memorial had
    /// one and no longer does. Neither may be offered a visit, a photo or a check-in.
    ///
    /// This lives here rather than in a presentation because it is a fact about the tree, not about
    /// a screen — and because it was previously two separate checks in one view, which is how a
    /// removed tree came to draw a REMOVED badge beside a live "say hello with a photo" button.
    /// Written as an exhaustive switch so that adding a status is a compile error rather than a
    /// silent "yes, offer a write". See ERRATA (E95).
    public var acceptsNewContributions: Bool {
        switch self {
        case .alive, .declining, .deadReported:
            return true
        case .removed, .vacantSite:
            return false
        }
    }
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

/// Where a community tree's coordinate came from — `community_trees.placement`.
///
/// **This is provenance, not a grade.** It sits beside `source` and `verification_state` because it
/// is the same kind of fact: how the record came to say what it says. Nothing here ranks the two,
/// and nothing downstream may read one as a warning. A contributor who moved the pin was very often
/// *more* accurate than the phone — they could see the tree and the phone could not, and a fix in an
/// SF street canyon is routinely 20–40 m out, which is the argument the movable pin was built on. The
/// column exists so that somebody correcting a coordinate later, or a moderator looking at one, can
/// tell a judgment from a reading; it does not exist so that either can be doubted on sight.
///
/// **Only community trees have one.** A city-import row's coordinate is the city's, arrived at by
/// neither of these means, and `main.community_trees` is the only table this column lives on. A
/// `Tree` decoded from the seed carries `.gps` because the type needs a value, and nothing renders a
/// placement for a record whose `source` is `.cityImport` — see `TreeProfilePresentation`.
///
/// The raw values are the stored vocabulary and are frozen by AppSchema v10's CHECK.
public enum TreePlacement: String, Codable, Sendable, Hashable, CaseIterable {
    /// The coordinate is the phone's fix, verbatim. The default, and what every community tree added
    /// before the pin could be moved was.
    case gps = "gps"
    /// The contributor moved the pin and confirmed it. `contributor` rather than `manual` or `user`
    /// because it names the author of the fact, the way `tree_names.given_by` and
    /// `review_flags.raised_by` do, and because "manual" carries a whiff of an override — which is
    /// exactly the reading this column must not invite.
    case contributorPlaced = "contributor_placed"
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
    /// The publishing inventory's own id for this record, verbatim. SF `TreeID`, San Jose
    /// `FACILITYID`. The key the weekly diff matches on (BUILD-PLAN §7).
    ///
    /// **Unique only within `idSpace`, never on its own.** San Jose FACILITYID 3 and San Francisco
    /// TreeID 3 are two different trees and both are in the seed (ERRATA E169, E176).
    public var externalRef: String?
    /// The numbering `externalRef` is drawn from — `sf`, `us-ca-sj` — or nil when the record does not
    /// say, which is how every seed built before the v14 pass reads and how a community-added tree
    /// reads always.
    ///
    /// It is on the model rather than left in the database because it changes what the app may
    /// *conclude* from the city's columns: `LandContext.inferred(from:idSpace:)` is a rule over one
    /// publisher's vocabulary and must not run against another's. See RULINGS R24.
    public var idSpace: String?
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
    /// How `coordinate` was arrived at, for a community-added tree. Meaningless on a city row, which
    /// has no `placement` column behind it — see `TreePlacement`.
    public var placement: TreePlacement
    /// What San Francisco has on file about this tree — six DataSF columns, verbatim.
    ///
    /// Non-nil only for `source == .cityImport`: a community-added tree is not in the city's
    /// inventory, and `main.community_trees` has no columns behind this. See `CityRecord`.
    public var cityRecord: CityRecord?
    /// Where a contributor said this tree stands (`community_trees.land_context`, AppSchema v11).
    ///
    /// Nil for a city row, which has no such column, and nil for a community row whose contributor
    /// did not say — the field is optional at the boundary and a "not stated" answer must stay
    /// distinguishable from a stated one. Read `landContext` rather than this, unless you
    /// specifically need "did a person state it".
    public var statedLandContext: LandContext?
    public let createdAt: Date
    public var updatedAt: Date
    /// City sync never deletes community contributions; removal is a status, not a delete
    /// (DECISIONS §3.17).
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        externalRef: String? = nil,
        idSpace: String? = nil,
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
        placement: TreePlacement = .gps,
        cityRecord: CityRecord? = nil,
        statedLandContext: LandContext? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.externalRef = externalRef
        self.idSpace = idSpace
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
        self.placement = placement
        self.cityRecord = cityRecord
        self.statedLandContext = statedLandContext
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    /// Where this tree stands, and how Cypress knows — or nil when nothing on the record says.
    ///
    /// A contributor's own answer always wins over a derivation, because it is the only one of the
    /// two made by somebody who was standing there. The fall-back reads the city's record through
    /// `LandContext.inferred(from:)`, whose doc comment carries the mapping and the numbers behind
    /// each bucket.
    ///
    /// The result names its own provenance so that a screen cannot show an inference with the
    /// confidence of an observation. Nothing here ranks the two — see `KnownLandContext`.
    public var landContext: KnownLandContext? {
        if let stated = statedLandContext {
            return KnownLandContext(context: stated, source: .statedByContributor)
        }
        guard let cityRecord,
              let inferred = LandContext.inferred(from: cityRecord, idSpace: idSpace)
        else { return nil }
        return KnownLandContext(context: inferred, source: .inferredFromCityRecord)
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
