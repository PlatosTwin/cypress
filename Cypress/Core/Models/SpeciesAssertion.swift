import Foundation

/// `species_assertions.source` (BUILD-PLAN §4).
public enum SpeciesAssertionSource: String, Codable, Sendable, Hashable, CaseIterable {
    case cityImport = "city_import"
    case community = "community"
    case org = "org"
    case aiSuggestion = "ai_suggestion"
}

/// Authorship of a contribution, as the schema stores it: the signed-in account when there is one,
/// this device otherwise, and nobody once a deletion has severed both (D9, AppSchema v9/v12).
///
/// A spelling of `PhotoOwner`, not a second type. The encoding — at most one of `user_id` and
/// `device_id`, both null meaning nobody — is the house's, it is a CHECK on three tables already,
/// and `isOwned(by:)` is exactly the predicate a supersession rule needs. The name is historical:
/// it was written for photographs and is not about photographs. Renaming it would break every other
/// live branch for no gain, so the alias carries the meaning and the original keeps the identity.
public typealias ContributionOwner = PhotoOwner

/// A versioned species claim about a tree (BUILD-PLAN §4 `species_assertions`, PRODUCT §3).
///
/// Append-only: corrections never silently overwrite. A superseded assertion keeps its row and
/// points forward via `supersededBy`, so the full ID history is preserved (PRODUCT §3,
/// DECISIONS §2.5 P-M3).
///
/// No `deletedAt`: this table is not user-touchable in the soft-delete sense — history is the point.
///
/// ── Authorship is two columns, not one, and that is D9 rather than an embellishment ─────────────
/// BUILD-PLAN §4 writes `asserted_by fk users`, which is the right column for a server where every
/// claim arrives with a session. On the phone it is the wrong one on its own: first saves are
/// anonymous under a device id and migrate to an account later (D9), so an `asserted_by` that only
/// ever holds a user id records *nothing at all* for the contributor this app is built around. The
/// two columns are `photos`' pair (AppSchema v12) and carry `photos`' CHECK, so `.nobody` — both
/// null — is reachable and means what it means everywhere else: this row belongs to no one.
///
/// Which matters here more than anywhere, because supersession authority is read off it. See
/// `RULINGS R45`.
public struct SpeciesAssertion: CoreEntity {
    public let id: UUID
    public let treeID: UUID
    /// Nullable for a genus-only or unknown claim (PRODUCT §3).
    public let speciesID: UUID?
    public let source: SpeciesAssertionSource
    /// `confidence numeric nullable` (BUILD-PLAN §4). 0…1.
    public let confidence: Double?
    /// BUILD-PLAN §4's `asserted_by fk users`. Null for an anonymous claim — see `assertedByDevice`.
    public let assertedByUser: UUID?
    /// The device half of D9. Null when the claim is an account's, and null *with* `assertedByUser`
    /// when the claim is nobody's.
    public let assertedByDevice: UUID?
    /// Self-reference to the assertion that replaced this one.
    public var supersededBy: UUID?
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        treeID: UUID,
        speciesID: UUID?,
        source: SpeciesAssertionSource,
        confidence: Double? = nil,
        owner: ContributionOwner = .nobody,
        supersededBy: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.treeID = treeID
        self.speciesID = speciesID
        self.source = source
        self.confidence = confidence
        self.assertedByUser = owner.userID
        self.assertedByDevice = owner.deviceID
        self.supersededBy = supersededBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// The two columns read back as the one fact they encode.
    public var owner: ContributionOwner {
        if let assertedByUser { return .user(assertedByUser) }
        if let assertedByDevice { return .device(assertedByDevice) }
        return .nobody
    }

    /// The current assertion is the one nothing supersedes.
    public var isCurrent: Bool { supersededBy == nil }

    /// Whether `attribution` may supersede this claim with no review — the whole of ticket #86, and
    /// the reason #124 is a separate verb.
    ///
    /// `ContributionOwner.isOwned(by:)` decides, and its `.nobody` arm is load-bearing rather than
    /// incidental: an assertion with no recorded author is **nobody's**, so it is nobody's to
    /// overwrite either. Every claim this database held before AppSchema v14 is in exactly that
    /// state — `community_trees` has never had an author column — and the migration declines to
    /// guess one. Those claims are corrected through the review route, like a stranger's.
    public func isSupersedable(by attribution: Attribution) -> Bool {
        owner.isOwned(by: attribution)
    }
}
