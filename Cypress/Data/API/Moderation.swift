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

/// One open status-review flag, resolved for a lead to act on: what was reported, the tree it names,
/// where it is, and when the concern was raised. `flagID` is what a confirmation or a dismissal acts
/// on; `treeID` is what the resulting record is reached by.
///
/// **`kind` is why this type is no longer called `RemovalReviewItem`** (ERRATA E170). The queue used
/// to be one kind wide, hard-coded to `appears_removed`, while screen 05 raised two — so every
/// `appears_dead` flag went into a table no surface read. A row now carries the kind it came from,
/// the confirm resolves it through `ReviewFlag.Kind.confirmedStatus`, and the copy beside it says
/// which of the two things was reported instead of calling both "removed".
public struct ReviewQueueItem: Identifiable, Sendable, Hashable {
    public let flagID: UUID
    public let treeID: UUID
    /// What was reported. Only kinds with a `confirmedStatus` reach this queue.
    public let kind: ReviewFlag.Kind
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
        kind: ReviewFlag.Kind,
        treeName: String,
        address: String?,
        coordinate: Coordinate,
        raisedAt: Date
    ) {
        self.flagID = flagID
        self.treeID = treeID
        self.kind = kind
        self.treeName = treeName
        self.address = address
        self.coordinate = coordinate
        self.raisedAt = raisedAt
    }
}
