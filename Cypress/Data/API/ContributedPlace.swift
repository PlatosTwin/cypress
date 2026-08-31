import Foundation

/// One of the reader's own trees, reduced to the three facts a camera needs.
///
/// ── Why this exists beside `mapMembership(.yours)` rather than inside it ─────────────────────
/// `mapMembership(_:)` answers a set of ids and that is the whole of what the map's narrowing
/// needs: the pin query takes ids and the inventory supplies the geometry, per viewport, as the
/// reader pans. A camera cannot work that way — it has to know where the trees are **before** it
/// decides what to point at, and there is no viewport yet to ask.
///
/// So this is the same set with its geometry resolved, read once, for one decision. It is not a
/// second definition of `Yours`: `LocalAPI` builds it from `ContributionStore.contributedTreeIDs`,
/// the same statement the chip reads, and `SeeAllOnMapTests` pins that they cannot diverge.
///
/// ── What is deliberately absent ──────────────────────────────────────────────────────────────
/// **No count, no name, no species.** D1 and ARCHITECTURE §5.1 forbid the first; `CityQueries`'
/// header forbids the second — `idSpace` is a key (`sf`, `us-ca-sj`, `us-ny-nyc`) that carries no
/// display name for the city, and composing one from it is the guess R28 and R48 closed the door
/// on. Nothing derived from this type reaches a reader as words; it aims a camera and stops.
public struct ContributedPlace: Sendable, Hashable {

    public let treeID: UUID

    /// The city inventory holding this tree, or nil when nothing places it in one.
    ///
    /// Nil is reachable on two honest grounds and neither is an error: a file that carries no
    /// `id_space` column at all (`SeedSchema.hasIdSpace`), and a community-added tree standing
    /// further from the nearest inventoried row than `AlmanacLimits.fallbackRadiusM` — the same
    /// radius R29 gives the almanac for deciding whether a record reaches a reader at all.
    public let idSpace: String?

    public let coordinate: Coordinate

    /// When the reader last contributed to this tree, or nil when no contribution row explains it.
    ///
    /// A community-added tree the reader has never since visited carries its own `created_at`;
    /// nil is left reachable rather than defaulted to the epoch, because "no date" and "1970" sort
    /// the same way and only one of them is true.
    public let contributedAt: Date?

    public init(treeID: UUID, idSpace: String?, coordinate: Coordinate, contributedAt: Date?) {
        self.treeID = treeID
        self.idSpace = idSpace
        self.coordinate = coordinate
        self.contributedAt = contributedAt
    }
}

// MARK: - Default

public extension CypressAPI {

    /// An implementation with no inventory attached can place none of the reader's trees.
    ///
    /// The same shape and the same argument as `mapMembership(_:)`'s default next door: a true
    /// statement about such an implementation rather than a placeholder, so no preview double and
    /// no second client has to invent a geometry to compile.
    ///
    /// **Empty is a real answer, and the caller treats it as one**: no fit is aimed, the
    /// suppression ends, and screen 01's own opening fly-to-you may still run — the reader is shown
    /// where they are, exactly as before this method existed.
    func contributedPlaces() async throws -> [ContributedPlace] { [] }
}
