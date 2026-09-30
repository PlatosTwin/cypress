//
//  LocationCorrection.swift
//  Cypress — Data/API
//
//  The default for `CypressAPI.correctLocation`, and the rule it implements stated once.
//
//  ── Who may move a pin ─────────────────────────────────────────────────────────────────────────
//
//  The tree's adder, and nobody else (the owner's decision 5 of 2026-09-28). On this phone that is
//  `CommunityTreeStore.adder(treeID:)` read through `ContributionOwner.isOwned(by:)` — the same
//  predicate `SpeciesAssertion.isSupersedable(by:)` uses for a species claim, so "this record is
//  mine to act on" is one rule, not two that drift (RULINGS R45 arm 1).
//
//  Three consequences follow from the predicate rather than from extra code, and each is a rule the
//  service applies too:
//
//  - **A tree whose adder is nobody cannot be moved.** Every tree added before `AppSchema` v23 is
//    nobody's, because the phone never recorded who added it and the migration declines to guess
//    (R45 arm 3). So is every tree an account deletion anonymized; the service answers `forbidden`
//    to everybody for one of those.
//  - **A signed-out phone cannot move a tree its account added.** After sign-in the account owns the
//    tree, and the service treats the device's own credential as a stranger to it — `forbidden` if
//    the tree is published, `not_found` if it is not. The phone never queues an act the service
//    would refuse for that reason (the S1 ruling on `location_correction`).
//  - **Somebody else's tree cannot be moved from here at all.** It is a cache row, and this verb
//    reads only the trees this phone added (`CommunityLayer`'s header says which verbs do which).
//
//  Foundation only.
//

import Foundation

// MARK: - Default implementation
//
// **Declared on the protocol as well**, and `CypressAPI` says at length why: a default that is
// *only* an extension member dispatches statically, so an implementation's override is unreachable
// through `any CypressAPI` — which is what every screen holds (ERRATA E125).

public extension CypressAPI {

    /// The honest answer from an implementation with no store: there is no such tree here to move.
    ///
    /// `notFound` rather than a silent success, for `SpeciesClaim.swift`'s reason: a preview that
    /// reported a move it never recorded would tell somebody their pin had moved while nothing
    /// anywhere held the new position.
    func correctLocation(
        treeID: UUID,
        to coordinate: Coordinate,
        placement: TreePlacement,
        locationAccuracyM: Double?
    ) async throws -> Tree {
        throw APIError.notFound
    }
}
