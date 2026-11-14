import Foundation

/// One position a community tree's pin has held (`tree_locations`, `AppSchema` v23).
///
/// A pin move supersedes rather than overwrites (the owner's decision 2 of 2026-09-28), so a tree's
/// positions are a chain: the root is where it was added, and each correction is appended and
/// stamps the row it replaces with `supersededBy`. `SpeciesAssertion`'s shape, for positions, and
/// for the same reason — the history is the record.
///
/// **The root row's id is the tree's id.** A correction's is its own, minted on the phone and sent
/// as `TreeLocationCorrection.id`, so the service's chain and this one name every row alike.
public struct TreeLocation: CoreEntity {
    public let id: UUID
    public let treeID: UUID
    /// The act that put the pin here: the add's key for the root, the correction's queue key for
    /// every other row.
    public let clientUUID: UUID
    public let coordinate: Coordinate
    public let placement: TreePlacement
    /// The fix's horizontal accuracy (D6). Nil when the act did not say.
    public let locationAccuracyM: Double?
    /// Who moved the pin here, as the two columns `SpeciesAssertion` stores for the same reason:
    /// `ContributionOwner` is not `Codable`, and the pair is what the schema holds. Both nil is
    /// nobody — every root written before v23, whose adder the phone never recorded (R45 arm 3),
    /// and every row an account deletion anonymized.
    public let movedByUser: UUID?
    public let movedByDevice: UUID?
    public var supersededBy: UUID?
    /// When the person did it.
    public let occurredAt: Date
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        treeID: UUID,
        clientUUID: UUID,
        coordinate: Coordinate,
        placement: TreePlacement,
        locationAccuracyM: Double? = nil,
        owner: ContributionOwner,
        supersededBy: UUID? = nil,
        occurredAt: Date,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.treeID = treeID
        self.clientUUID = clientUUID
        self.coordinate = coordinate
        self.placement = placement
        self.locationAccuracyM = locationAccuracyM
        self.movedByUser = owner.userID
        self.movedByDevice = owner.deviceID
        self.supersededBy = supersededBy
        self.occurredAt = occurredAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// The two columns read back as the one fact they encode.
    public var owner: ContributionOwner {
        if let movedByUser { return .user(movedByUser) }
        if let movedByDevice { return .device(movedByDevice) }
        return .nobody
    }

    /// The head of the chain is the row nothing supersedes.
    public var isCurrent: Bool { supersededBy == nil }

    /// Whether this is the position the tree was added at.
    public var isRoot: Bool { id == treeID }
}
