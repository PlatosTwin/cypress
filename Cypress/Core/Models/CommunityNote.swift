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
        /// "There is no tree here and there never was" — a defect in the **record**, not an event in
        /// a tree's life (task #125, ruled in `RULINGS R46`; the surface and the resolution are
        /// `RULINGS R50`).
        ///
        /// Reserved in the `review_flags` CHECK by AppSchema v14 and unreachable until this case
        /// existed. It is deliberately **not** `appearsRemoved`: confirming that writes
        /// `TreeStatus.removed`, which this product has settled as a memorial — grey pin spoken as
        /// "Removed tree, memorial", screen 19, `acceptsNewContributions == false` (E170, R19) — and
        /// a record that never had a tree behind it would get a memorial for a tree that never
        /// lived. That is R7's vacant-site argument, and D16's merged inventory needs the two apart:
        /// a dated lifecycle event, against a row that should not be in the table at all.
        case neverExisted = "never_existed"

        /// What resolving a flag of this kind is allowed to write.
        ///
        /// **The exhaustive switch E170 built, widened along its own grain rather than across it.**
        /// E170's defect was that the raise switched over two cases while the resolve hard-coded
        /// one, so `appears_dead` was raisable from screen 05 and resolvable by nothing. The fix was
        /// a single exhaustive switch both sides read; this is that switch, and it now names *which
        /// seam* resolves a kind instead of only which status. A kind that can be raised and not
        /// resolved is still a compile error — there is nowhere to put a new case without saying how
        /// it closes.
        ///
        /// The two seams are parallel and must stay parallel. `.status` moves `trees.status` through
        /// `tree_status_overrides`; `.speciesAssertion` appends to the `species_assertions` chain and
        /// **never touches status**. A wrong species is not a statement about whether the tree is
        /// alive, and a species correction that quietly marked a tree removed would be the worst
        /// version of the bug E170 fixed rather than a repeat of it.
        public enum Resolution: Hashable, Sendable {
            /// Confirming writes this status (`LocalAPI.confirmReview`).
            case status(TreeStatus)
            /// Confirming appends a species assertion (`LocalAPI.resolveSpeciesReview`).
            case speciesAssertion
            /// Confirming withdraws the **record**: the `community_trees` row is soft-deleted and
            /// the pin goes (`LocalAPI.withdrawRecord`). `trees.status` is not touched, and that is
            /// the point rather than an omission — see `neverExisted`.
            case recordWithdrawal
            /// Nothing is written. `removedButActive` is the weekly diff saying the city and the
            /// community disagree, and the whole point is that a person looks (BUILD-PLAN §7);
            /// `duplicateSuspected` has no resolution route built yet and no surface raises it.
            case byHand
        }

        public var resolution: Resolution {
            switch self {
            case .appearsRemoved: return .status(.removed)
            case .appearsDead: return .status(.deadReported)
            case .wrongSpecies: return .speciesAssertion
            case .neverExisted: return .recordWithdrawal
            case .duplicateSuspected, .removedButActive: return .byHand
            }
        }

        /// The `TreeStatus` a confirmation of this flag writes, or nil for a kind that is not a
        /// status claim at all.
        ///
        /// Derived from `resolution` since the species seam was added, rather than switching a
        /// second time. Two switches over the same enum answering two halves of one question is the
        /// shape E170 was: they agree until somebody edits one of them.
        ///
        /// `duplicateSuspected`, `wrongSpecies` and `neverExisted` are nil because none of them is a
        /// statement about whether the tree is alive — they are corrections to the record, and
        /// confirming one must not move `trees.status`. `removedButActive` is nil for a sharper
        /// reason: the weekly diff opens it precisely *because* the city and the community disagree,
        /// and the whole point is that a person looks rather than a status being written
        /// (BUILD-PLAN §7).
        ///
        /// **`neverExisted` is the one this property was most likely to be widened for, and it must
        /// not be.** `TreeStatus.vacantSite` exists and reads like the truthful confirmed state; it
        /// is not. A vacant site is a planting site with a tree missing from it, drawn as a hollow
        /// ring precisely so it does not borrow the removed pin's meaning (R7). A duplicate pin two
        /// metres from another, or a record standing in the middle of a building, is not a vacant
        /// planting site, and writing one would leave the map asserting a site where there is
        /// nothing — R7's own argument, arriving at the case where the assertion is not imprecise
        /// but false. Pointing this at any status to make the kind resolvable is the E170 defect in
        /// its worse form: the queue would look right while the trees moved.
        public var confirmedStatus: TreeStatus? {
            guard case let .status(status) = resolution else { return nil }
            return status
        }

        /// The kinds a lead's queue serves: exactly those a confirm can resolve into a status.
        ///
        /// Derived rather than listed, so the queue cannot drift out of step with `confirmedStatus`
        /// the way it did before E170. **`wrongSpecies` is deliberately not here** and must never be
        /// added by widening `confirmedStatus`: it resolves on the tree's own profile, through the
        /// species seam, and a species correction arriving down the status queue would write
        /// `trees.status` on grounds nobody made.
        public static var statusReviewKinds: [Kind] {
            allCases.filter { $0.confirmedStatus != nil }
        }

        /// The kinds the species seam resolves. Derived from the same switch, for the same reason.
        public static var speciesReviewKinds: [Kind] {
            allCases.filter { $0.resolution == .speciesAssertion }
        }

        /// The kinds the record-defect seam resolves (task #125). Derived from the same switch, for
        /// the same reason: a third list written by hand is a third thing that can disagree with the
        /// one that decides.
        public static var recordReviewKinds: [Kind] {
            allCases.filter { $0.resolution == .recordWithdrawal }
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
