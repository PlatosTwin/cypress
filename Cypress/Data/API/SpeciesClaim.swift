//
//  SpeciesClaim.swift
//  Cypress — Data/API
//
//  Naming the species on a tree that is already on record. The owner's request was "add tree species
//  after/at same time as adding a custom tree"; `VisitAddTreeModel.species` is the *at the same time*
//  half, and this is *after*.
//
//  ── The one transition this can honestly perform, and why it is only one ────────────────────────
//  BUILD-PLAN §4 makes `species_assertions` the source of truth for what a tree is: append-only,
//  every claim keeping its row and pointing forward through `superseded_by`, so a correction never
//  silently overwrites the thing it corrects. `trees.species_current` is explicitly "denormalized
//  from the latest accepted assertion … a read cache" (`Tree.speciesCurrentID`).
//
//  That table is in the **read-only seed database**. `AppSchema` does not create a copy of it in
//  `main`, and this round did not add one: a supersession chain is a moderation surface — who
//  asserted, with what confidence, which claim replaced which — and standing one up on the strength
//  of a two-clause feature request would be inventing a product.
//
//  So the only species write available on device is over `community_trees.species_current`, and the
//  only edit to it that does not need a chain is the one where **there is nothing to supersede**.
//  Hence two refusals, both enforced in `LocalAPI.claimSpecies` and both asserted in
//  `SpeciesClaimTests`:
//
//  1. **Community rows only.** `main` has no writable `trees`; a city row's species is the city's,
//     sitting in an ATTACHed read-only database. Letting a contributor overwrite the inventory would
//     need an override table and a policy about what the export then says, which is a larger
//     decision than this. `.forbidden` says so rather than failing silently.
//
//  2. **First claim wins; a second is `.conflict`, not an overwrite.** Replacing an existing claim is
//     a correction, and a correction with no history is precisely what `species_assertions` was
//     designed to prevent. `tree_names` already keeps this rule for the same reason and in the same
//     words — "one active name per tree; first namer wins" (D15). A contributor who thinks the
//     species is wrong needs the moderation route, and that route does not exist yet; saying so is
//     honest, and quietly discarding somebody else's statement is not.
//
//  The `WHERE species_current IS NULL` in the UPDATE is rule 2 in SQL rather than in Swift. A
//  read-then-write would leave a window in which two callers both see NULL and the second one wins,
//  which is the same class of bug the `ON CONFLICT(client_uuid) DO NOTHING` on every other
//  contribution write exists to close.
//
//  ── Why this is a protocol *requirement* and not just an extension method ───────────────────────
//  It is declared in `CypressAPI`'s body, with the default below. A method that lived only in an
//  extension would have no witness-table entry, would dispatch statically, and `LocalAPI`'s
//  implementation would be unreachable through `any CypressAPI` — every caller in the app holds one.
//  This project has been bitten by exactly that before.
//
//  The default exists so that the eighteen preview and test stubs conforming to `CypressAPI` do not
//  each have to grow a body for a write they have no store to perform, which is the same bargain
//  `speciesGuide` and `almanac` already make.
//

import Foundation

public extension CypressAPI {

    /// The honest answer from an implementation with no store: there is no such tree here to name.
    ///
    /// Not `.serverError` — nothing failed — and not a silent success, which would let a preview
    /// report a claim it never recorded.
    func claimSpecies(treeID: UUID, speciesID: UUID) async throws -> Tree {
        throw APIError.notFound
    }
}
