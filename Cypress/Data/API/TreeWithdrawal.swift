//
//  TreeWithdrawal.swift
//  Cypress — Data/API
//
//  The default for `CypressAPI.withdrawTree`, the offer a tree's profile carries for it, and the
//  rule both implement, stated once.
//
//  ── Who may withdraw a tree ────────────────────────────────────────────────────────────────────
//
//  The tree's adder, for everyone, while nobody else has visited or photographed it (the owner's
//  decision 8). On this phone the adder test is `CommunityTreeStore.adder(treeID:)` read through
//  `ContributionOwner.isOwned(by:)`, the predicate `LocationCorrection.swift` uses for a pin move.
//  The same three consequences follow from it:
//
//  - **A tree whose adder is nobody cannot be withdrawn.** The service answers `forbidden`.
//  - **A signed-out phone cannot withdraw a tree its account added.** After sign-in the account owns
//    the tree, and the service treats the device's own credential as a stranger to it. The phone
//    never queues an act the service would refuse for that reason.
//  - **Somebody else's tree cannot be withdrawn from here.** It is a cache row.
//
//  The "nobody else" half is the service's to decide (`othersHaveBuiltOn`): this phone does not
//  see other people's visits. The phone withdraws at once and the service's answer settles it. A
//  `conflict` puts the tree back (`OutboxQueue.settle`). `TreeWithdrawalOffer.othersHaveAddedToIt`
//  is drawn only where the phone already holds a fact that says the refusal will come.
//
//  Foundation only.
//

import Foundation

/// What a tree's profile offers about withdrawing the tree (the owner's answers of 2026-11-16).
public enum TreeWithdrawalOffer: Hashable, Sendable {
    /// No control and no line: a city tree, somebody else's tree, a tree whose adder is not the
    /// reader, every stub and every preview.
    case unavailable
    /// The control. The reader added this tree, and this phone knows of nobody else's visit or
    /// photograph on it.
    case available
    /// The line `Other people have added to this tree, so it stays on the map.` in place of the
    /// control. The reader added this tree, and this phone already holds one of these facts:
    ///
    /// - a photograph of the tree the service served this reader as somebody else's
    ///   (`RoutedAPI.refreshedTreeProfile`). The service serves another identity's photograph only
    ///   when it is approved, not deleted and its bytes arrived, which is a photograph its own rule
    ///   counts;
    /// - a visit, check-in, measurement or care event on this phone's own tables, not deleted, by
    ///   another account, whose queue row is no longer waiting or failed;
    /// - a withdrawal of this tree the service already refused with `conflict`.
    ///
    /// Nothing else counts. The phone never sees other people's visits, so a tree somebody else
    /// only visited still shows the control, and the service's refusal brings the tree back.
    case othersHaveAddedToIt
}

// MARK: - Default implementation
//
// **Declared on the protocol as well**, for `LocationCorrection.swift`'s reason (ERRATA E125).

public extension CypressAPI {

    /// The honest answer from an implementation with no store: there is no such tree here to
    /// withdraw. `notFound` rather than a silent success, for `correctLocation`'s reason.
    func withdrawTree(treeID: UUID) async throws {
        throw APIError.notFound
    }
}
