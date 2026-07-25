//
//  Moderation.swift
//  Cypress — Data/API
//
//  The local moderation route (ERRATA E124-B), the project owner's answer to "designate some people
//  as community leads and they can verify removals."
//
//  ── Why these types live here, and not on `CypressAPI` ──────────────────────────────────────
//  `CypressAPI`'s header lists the `/admin/*` moderator surfaces among its deliberate omissions:
//  confirming a review flag into a tree-status transition was a *web* deliverable, because the seed
//  is read-only and no phone had a reason — or a right — to move a city record. The local beta has
//  no web, so the confirmation happens on-device, and these methods sit on `LocalAPI` beside
//  `deleteAccount` and `privateReminders` for the same reason those do: they are real, local, and
//  have no server half to stub. When a moderator service exists, they become the local cache of it.
//

import Foundation

/// One open `appears_removed` flag, resolved for a lead to act on: the tree it names, where it is,
/// and when the concern was raised. `flagID` is what a confirmation acts on; `treeID` is what the
/// resulting memorial is reached by.
public struct RemovalReviewItem: Identifiable, Sendable, Hashable {
    public let flagID: UUID
    public let treeID: UUID
    /// The tree's active name, or its species common name — the same fallback the rest of the app
    /// uses (`activeName` → species). Never a bare UUID.
    public let treeName: String
    public let address: String?
    public let coordinate: Coordinate
    public let raisedAt: Date

    public var id: UUID { flagID }

    public init(
        flagID: UUID,
        treeID: UUID,
        treeName: String,
        address: String?,
        coordinate: Coordinate,
        raisedAt: Date
    ) {
        self.flagID = flagID
        self.treeID = treeID
        self.treeName = treeName
        self.address = address
        self.coordinate = coordinate
        self.raisedAt = raisedAt
    }
}
