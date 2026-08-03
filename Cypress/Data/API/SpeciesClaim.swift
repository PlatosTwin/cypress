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
//  That table used to be in the **read-only seed database** and nowhere else, which is why this file
//  once recorded that a correction could not be written at all. **AppSchema v14 put a writable copy
//  in `main`**, and `correctSpecies` is the correction; tickets #86 and #124, ruled in
//  `docs/rulings-pending/species-supersession.md`. What follows is still true, and is now a division
//  of labour between two verbs rather than a limit:
//
//  1. **Community rows only.** `main` has no writable `trees`; a city row's species is the city's,
//     sitting in an ATTACHed read-only database. Letting a contributor overwrite the inventory would
//     need an override table and a policy about what the export then says, which is a larger
//     decision than this. `.forbidden` says so rather than failing silently — and the same refusal
//     covers `correctSpecies` and `flagWrongSpecies`, for the same reason.
//
//  2. **First claim wins; a second `claimSpecies` is `.conflict`, not an overwrite.** Replacing an
//     existing claim is a *correction*, and it goes through the verb that keeps a history and asks
//     who is making it. `tree_names` keeps the same rule in the same words — "one active name per
//     tree; first namer wins" (D15) — and the ruling records where that rule stops: it protects one
//     contributor's statement from another's, not a contributor from their own mistake.
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

    /// Same answer, for the same reason: a stub with no store has no tree to correct.
    func correctSpecies(treeID: UUID, speciesID: UUID) async throws -> Tree {
        throw APIError.notFound
    }

    func flagWrongSpecies(treeID: UUID) async throws {
        throw APIError.notFound
    }

    func dismissSpeciesReview(flagID: UUID) async throws {
        throw APIError.notFound
    }
}

/// What a viewer may do about the species already on a tree — the correction path's whole surface,
/// decided in `Data` and carried on the profile payload.
///
/// It is one value rather than three booleans on purpose. "Yours to correct", "somebody else's to
/// report" and "already reported" are mutually exclusive states of one record, and a view that
/// assembled them from separate flags could draw two controls, or none, for a record that has
/// exactly one thing to offer. The decision needs the viewer's `Attribution` and role, neither of
/// which a view has any business holding — the same argument that put `deletablePhotoIDs` on the
/// payload rather than deriving it in `TreeProfilePresentation`.
public enum SpeciesCorrectionOffer: Hashable, Sendable {
    /// Nothing to correct: a city row, an unnamed tree, or a claim with no chain behind it.
    ///
    /// Not spelled `none`. A case by that name shadows `Optional.none` at every call site that
    /// compares against a leading dot, and the compiler resolves the ambiguity silently.
    case unavailable
    /// The claim in force is this contributor's own. `correctSpecies` (#86).
    case correctable
    /// The claim is somebody else's — or nobody's, which the ruling treats the same way.
    /// `flagWrongSpecies` (#124).
    case reportable
    /// A report is open. `canResolve` is whether *this* viewer may answer it: the author of the
    /// disputed claim, or a lead.
    case underReview(flagID: UUID, canResolve: Bool)
}
