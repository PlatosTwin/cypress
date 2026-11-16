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
//  `RULINGS R45`. What follows is still true, and is now a division
//  of labor between two verbs rather than a limit:
//
//  1. **Community rows only.** `main` has no writable `trees`; a city row's species is the city's,
//     sitting in an ATTACHed read-only database. Letting a contributor overwrite the inventory would
//     need an override table and a policy about what the export then says, which is a larger
//     decision than this. `.forbidden` says so rather than failing silently — and the same refusal
//     covers `correctSpecies` and `flagWrongSpecies`, for the same reason.
//
//     **That larger decision was taken, it went the other way for *disputing*, and it is built**
//     (RULINGS R79, `AppSchema` v22). A city row is disputable from the UI: the dispute is a row in
//     the app's writable database referencing the city tree, never a write to the attached file. So
//     the inventory stays read-only and **the refusal above stands exactly as written for
//     `claimSpecies` and `correctSpecies`** — R79 changed disputing, not writing, and nothing in the
//     dispute round weakens either of those two `.forbidden`s.
//
//     What changed is `flagWrongSpecies`' half of it. A city row no longer answers `.unavailable`
//     here; it answers `.dataDispute`, and the surface behind that is richer than this boolean pair
//     — checked issue kinds, per-field suggested values, free text (`DataDispute.swift`,
//     `TreeDataDispute`). Sync-back to the city's own dataset remains explicitly deferred, and
//     nothing on this device adjudicates a dispute.
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
    /// Nothing to correct: an unnamed tree, or a claim with no chain behind it.
    ///
    /// **A city row is no longer one of these** — it was, and R79 is what changed it; see
    /// `.dataDispute` below.
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
    /// A report is open against a species this viewer named on a tree somebody else added
    /// (ROADMAP 144). The namer may still correct their own answer (the owner's answer of
    /// 2026-11-16, "Yes, until the adder corrects it"), and only the adder may keep it, so the
    /// screen draws the reported line and the correction, and no "Keep the species".
    case reportedYoursToCorrect
    /// A **city** row, whose species is disputed through R79's surface rather than through this one.
    ///
    /// The answer this case replaces was `.unavailable`, and that answer had become false: R79 made
    /// city data disputable, so "nothing to do about the species here" stopped being true the day
    /// `AppSchema` v22 landed.
    ///
    /// **The identical value is on `RecordDefectOffer` too, and one control is drawn from it, never
    /// two.** R79's city surface is a single sheet whose three checkboxes cover both of these seams
    /// — the species one and the record one — so both offers point at it and the state lives in one
    /// place. `TreeProfile.cityDataDispute` is the accessor a view should use;
    /// `DataDisputeTests.theTwoOffersAgreeOnACityRow` is what keeps them from disagreeing.
    case dataDispute(DataDisputeOffer)
}

/// This phone's own species acts on one community tree that the service may not include yet
/// (ROADMAP 144). `LocalAPI.speciesAnswerState(treeID:)` reads it; `RoutedAPI` lays it over the
/// service's answer.
public struct SpeciesAnswerState: Hashable, Sendable {
    /// The reader's naming or correction is still queued.
    public let answerQueued: Bool
    /// The reader's report is still queued.
    public let reportQueued: Bool
    /// The reader's "Keep the species" is still queued.
    public let keepQueued: Bool
    /// Any species act on this tree is still queued, by anybody on this phone.
    public let anyActQueued: Bool
    /// An open species report raised on this phone.
    public let openFlagID: UUID?

    public init(answerQueued: Bool, reportQueued: Bool, keepQueued: Bool, anyActQueued: Bool, openFlagID: UUID?) {
        self.answerQueued = answerQueued
        self.reportQueued = reportQueued
        self.keepQueued = keepQueued
        self.anyActQueued = anyActQueued
        self.openFlagID = openFlagID
    }
}

/// What the species offer on a **community** tree is decided from (ROADMAP 144).
///
/// The rules are the service's (`server/internal/store/species.go`), so the phone never draws a
/// control whose act the service would record and apply to nobody:
/// - **The adder** may always correct, and keeps a reported species with "Keep the species".
/// - **The namer** (somebody who is not the adder and named an unnamed tree) may correct their own
///   answer until the adder corrects or keeps it, or the operator corrects it. A namer who does not
///   share counts for nothing on the service, so the namer's arm needs `readerShares`.
/// - **Anybody else who shares** may report a named species as wrong.
/// - **Nobody else** gets a control. The reported line is drawn to everybody, because it is a fact
///   about the tree and not a control.
///
/// `LocalAPI` fills it from this phone's tables; `RoutedAPI` fills it again with the service's
/// answer when the service sent one. Both decide through `offer(placeholderFlagID:)`, so the two
/// paths cannot draw different controls for the same facts.
public struct SpeciesAnswerFacts: Hashable, Sendable {
    /// The profile shows a species (on a cached tree, after the reader's own answer is laid over it).
    public var hasSpecies: Bool
    /// The reader added the tree, by this phone's own record.
    public var isAdder: Bool
    /// The species in force is the reader's own naming, and the adder has not stepped in.
    public var isNamer: Bool
    /// The reader is signed in and agreed to share tree records (`ContributionSharing.sharing`).
    public var readerShares: Bool
    /// Somebody's report against the species in force counts.
    public var isReported: Bool
    /// The report the adder's "Keep the species" answers: this phone's own flag, or the service's
    /// `species_report_flag_id`. Nil for anybody but the adder on the service's answer.
    public var reportFlagID: UUID?

    public init(
        hasSpecies: Bool,
        isAdder: Bool,
        isNamer: Bool,
        readerShares: Bool,
        isReported: Bool,
        reportFlagID: UUID?
    ) {
        self.hasSpecies = hasSpecies
        self.isAdder = isAdder
        self.isNamer = isNamer
        self.readerShares = readerShares
        self.isReported = isReported
        self.reportFlagID = reportFlagID
    }

    /// The one control (or none) these facts allow.
    ///
    /// - Parameter placeholderFlagID: the id carried by an `.underReview` that the reader cannot
    ///   resolve. Nothing reads it in that state; the tree's id is what callers pass.
    public func offer(placeholderFlagID: UUID) -> SpeciesCorrectionOffer {
        // An unnamed tree has nothing to correct or report; naming it is the claim control's job.
        guard hasSpecies else { return .unavailable }
        if isAdder {
            if isReported, let reportFlagID { return .underReview(flagID: reportFlagID, canResolve: true) }
            return .correctable
        }
        if isNamer && readerShares {
            return isReported ? .reportedYoursToCorrect : .correctable
        }
        if isReported { return .underReview(flagID: reportFlagID ?? placeholderFlagID, canResolve: false) }
        return readerShares ? .reportable : .unavailable
    }
}
