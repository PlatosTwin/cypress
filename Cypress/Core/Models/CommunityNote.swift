import Foundation

/// A pinned, publicly visible note on a tree (BUILD-PLAN §4 `community_notes`).
///
/// Labelled "Community-reported. The city has not been notified." wherever it renders
/// (PRODUCT §9 copy table). Never write "sent to the city" copy (DECISIONS §3.3).
public struct CommunityNote: CoreEntity, SoftDeletable {
    /// `community_notes.category` (BUILD-PLAN §4), verbatim and exhaustive.
    ///
    /// **Hazard categories are not in this type and cannot be added to it at a call site.**
    /// `HazardCategory` is a separate type with a disjoint raw-value space, so
    /// `Category(rawValue: hazard.rawValue)` is always nil and there is no initializer,
    /// conversion, or shared protocol linking the two (D4, DECISIONS §3.4). On the server the same
    /// invariant is a check constraint; here it is the type.
    ///
    /// PRODUCT §5 M7 also mentions a "hardware" non-hazard category; BUILD-PLAN §4 lists only these
    /// three, and BUILD-PLAN wins on data (ARCHITECTURE §1).
    public enum Category: String, Codable, Sendable, Hashable, CaseIterable {
        case needsWater = "needs_water"
        case pest = "pest"
        case vandalism = "vandalism"
    }

    public let id: UUID
    public let treeID: UUID
    public let userID: UUID
    public var category: Category
    public var note: String?
    public var photoID: UUID?
    /// 90 days, "non-safety categories only by construction" (BUILD-PLAN §4) — which holds because
    /// `Category` cannot express a safety category at all.
    public var staleAt: Date
    public let createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    /// Notes go stale automatically after 90 days without activity (PRODUCT §3, BUILD-PLAN §4).
    public static let staleAfter: TimeInterval = 90 * 24 * 60 * 60

    public init(
        id: UUID = UUID(),
        treeID: UUID,
        userID: UUID,
        category: Category,
        note: String? = nil,
        photoID: UUID? = nil,
        createdAt: Date = Date(),
        staleAt: Date? = nil,
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.treeID = treeID
        self.userID = userID
        self.category = category
        self.note = note
        self.photoID = photoID
        self.createdAt = createdAt
        self.staleAt = staleAt ?? createdAt.addingTimeInterval(CommunityNote.staleAfter)
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    public func isStale(at date: Date) -> Bool { date >= staleAt }
}

/// `review_flags` (BUILD-PLAN §4). Surfaced in the admin view from M2.
///
/// A tree status transition requires a moderator or org coordinator confirming a flag; an
/// observation never mutates status directly (DECISIONS §3.7). Two offline users flagging the same
/// tree produce two flags on one thread, not a conflict (BUILD-PLAN §6).
public struct ReviewFlag: CoreEntity, SoftDeletable {
    public enum Kind: String, Codable, Sendable, Hashable, CaseIterable {
        case appearsDead = "appears_dead"
        case appearsRemoved = "appears_removed"
        case duplicateSuspected = "duplicate_suspected"
        case wrongSpecies = "wrong_species"
        /// Opened by the weekly city diff when a row leaves the source but the tree has recent
        /// community activity (BUILD-PLAN §7). Not in the §4 list; §7 names it explicitly.
        case removedButActive = "removed_but_active"

        /// The `TreeStatus` a confirmation of this flag writes, or nil for a kind that is not a
        /// status claim at all.
        ///
        /// **This is the seam that makes the review queue kind-agnostic** (ERRATA E170). It used to
        /// be a literal `.removed` inside `LocalAPI.confirmRemoval`, which is why `appears_dead` was
        /// raisable from screen 05 and resolvable by nothing: the raise switched over both cases and
        /// the resolve hard-coded one. Both sides now read the same exhaustive switch, so a kind that
        /// can be raised as a status claim and not confirmed is a compile error rather than a flag
        /// that sits open forever.
        ///
        /// `duplicateSuspected` and `wrongSpecies` are nil because neither is a statement about
        /// whether the tree is alive — they are corrections to the record, and confirming one must
        /// not move `trees.status`. `removedButActive` is nil for a sharper reason: the weekly diff
        /// opens it precisely *because* the city and the community disagree, and the whole point is
        /// that a person looks rather than a status being written (BUILD-PLAN §7).
        public var confirmedStatus: TreeStatus? {
            switch self {
            case .appearsRemoved: return .removed
            case .appearsDead: return .deadReported
            case .duplicateSuspected, .wrongSpecies, .removedButActive: return nil
            }
        }

        /// The kinds a lead's queue serves: exactly those a confirm can resolve into a status.
        ///
        /// Derived rather than listed, so the queue cannot drift out of step with `confirmedStatus`
        /// the way it did before E170.
        public static var statusReviewKinds: [Kind] {
            allCases.filter { $0.confirmedStatus != nil }
        }
    }

    public enum Status: String, Codable, Sendable, Hashable, CaseIterable {
        case open = "open"
        case confirmed = "confirmed"
        case dismissed = "dismissed"
    }

    public let id: UUID
    public let treeID: UUID
    public var kind: Kind
    public let raisedBy: UUID?
    public var status: Status
    public let createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        treeID: UUID,
        kind: Kind,
        raisedBy: UUID?,
        status: Status = .open,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.treeID = treeID
        self.kind = kind
        self.raisedBy = raisedBy
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

/// `neighborhoods` (BUILD-PLAN §4). Source: the SF Analysis Neighborhoods dataset — the one
/// official set (A4).
public struct Neighborhood: CoreEntity {
    public let id: UUID
    public var name: String
    public var geometry: MultiPolygon
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        geometry: MultiPolygon,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.geometry = geometry
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
