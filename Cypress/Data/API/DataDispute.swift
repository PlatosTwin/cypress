//
//  DataDispute.swift
//  Cypress — Data/API
//
//  Disputing a record's own data — `RULINGS R79`'s city surface, part 1 (`AppSchema` v22).
//
//  ── What R79 asked for, and what part 1 is ────────────────────────────────────────────────────
//
//  The owner's words: *"City data needs to be disputable via the UI. For now, we can just store it
//  in a separate DB, and later on we'll figure out how and whether to sync back to the city's DB."*
//  The refinement the same day made the city surface a checkbox set rather than a second pair of
//  booleans: pin in the wrong location, wrong species, wrong other metadata — with **suggested
//  values** for whatever is disputed and a free-text **notes** field beside them.
//
//  Part 1 builds the record, the two verbs, and the offer the profile payload carries. Deliberately
//  **not** here, each its own scheduled PR: the dispute sheet itself, the flag badge on the map and
//  the list, the "trees with data issues" filter, and the missing-tree entry point (a defect the
//  profile screen cannot host, because there is no record to open).
//
//  ── City rows only, this round, and the refusal is not the old one ────────────────────────────
//
//  `flagWrongSpecies` and `flagNeverExisted` refuse a **city** row and serve a community one.
//  These two verbs are the mirror image: they refuse a **community** row with `.forbidden` and
//  serve a city one. That is not an oversight and it is not permanent — R79 gives community trees
//  location and species disputes too, and the community round is where the two surfaces converge.
//  Until then a community tree keeps exactly the flags it has, and a control that exists only to be
//  refused is worse than no control (`RecordDefectOffer.unavailable`'s own argument).
//
//  ── What a dispute never does ─────────────────────────────────────────────────────────────────
//
//  It does not move the inventory. The city's rows sit in an ATTACHed read-only database; a dispute
//  is a row in `main` that *references* one, and R79 explicitly defers whether disputes ever reach
//  a city's own dataset. Nothing in this file writes `trees`, `tree_status_overrides` or
//  `species_assertions`, and nothing may be added here that does: adjudication is a web deliverable
//  (ARCHITECTURE §8), and a device that acted on an unadjudicated dispute would be moving city data
//  on a say-so nobody weighed.
//

import Foundation

// MARK: - Default implementations
//
// **Declared on the protocol as well**, and `CypressAPI` says at length why: a default that is
// *only* an extension member dispatches statically, so an implementation's override is unreachable
// through `any CypressAPI` — which is what every screen holds (ERRATA E125).

public extension CypressAPI {

    /// The honest answer from an implementation with no store: there is no such record here to
    /// dispute.
    ///
    /// `notFound` rather than a silent success, for the reason `SpeciesClaim`'s defaults give: a
    /// preview that reported a dispute it never recorded would tell somebody their objection was
    /// filed while nothing anywhere held it.
    func raiseDataDispute(
        treeID: UUID,
        issues: Set<TreeDataDispute.IssueKind>,
        suggestions: TreeDataDispute.Suggestions,
        notes: String?
    ) async throws -> TreeDataDispute {
        throw APIError.notFound
    }

    /// Same answer, for the same reason: a stub with no store holds no dispute to take back.
    func withdrawDataDispute(disputeID: UUID) async throws {
        throw APIError.notFound
    }
}

// MARK: - What the profile offers

/// What this viewer may do about the data on a record they disagree with — the whole surface of
/// R79's part 1, decided in `Data` and carried on the profile payload.
///
/// One value rather than a set of booleans, for `SpeciesCorrectionOffer`'s stated reason: "nothing
/// to dispute", "you may raise one" and "yours is standing" are mutually exclusive states of one
/// record and one viewer, and a view assembling them from separate flags could draw two controls or
/// none. The decision needs the viewer's identity, which a presentation has no business holding
/// (ARCHITECTURE §4).
public enum DataDisputeOffer: Hashable, Sendable {
    /// Nothing to dispute here: a community row, which keeps its own flags this round.
    ///
    /// Not spelled `none`, for the reason `SpeciesCorrectionOffer.unavailable` gives — a case by
    /// that name shadows `Optional.none` at every call site comparing against a leading dot, and the
    /// compiler resolves the ambiguity silently.
    case unavailable
    /// This viewer may raise a dispute against this record.
    ///
    /// True even when somebody *else* has one open: the conflict rule is per raiser, because two
    /// people disagreeing with one record is two disagreements and the merged inventory has to be
    /// able to count them. What a viewer may not do is raise a second one of their own.
    case raisable
    /// This viewer's own dispute is standing, and they may take it back.
    ///
    /// **Withdrawal is the author's and nobody else's**, which is the whole of `withdrawable` being
    /// absent as a flag: there is no state in which this case is drawn for somebody who may not
    /// withdraw. Shipping a new dispute surface that could be raised and not retracted would repeat
    /// the defect the owner has already reported against the community flagging flow.
    case raisedByYou(disputeID: UUID)
}

// MARK: - What a dispute has to say to be worth storing

/// The rules a raise has to satisfy before anything is written.
///
/// Pure functions over the arguments, kept out of `LocalAPI` so they can be exercised without a
/// database and so the sheet in a later round can pre-check exactly what the API will enforce
/// rather than a paraphrase of it.
public enum DataDisputeLimits {

    /// The radius a suggested position has to be able to resolve, in meters.
    ///
    /// **`TreeDraft.proximityDedupeRadiusM` — BUILD-PLAN §6's 10 m — and it is the existing number
    /// rather than a new one on purpose.** The owner's instruction was to follow the shape of
    /// `AlmanacLimits.fixCanResolveAnArea(accuracyM:withinM:)`, and the load-bearing half of that
    /// shape is that the bound belongs to the *caller's own read*: the almanac passes the radius its
    /// neighborhood resolution searches, the City segment passes the wider one its own search runs
    /// over, and keying both on one number blanked a segment that could still answer (F3).
    ///
    /// The read here is "which tree is this position the position of", and this app already has a
    /// measured answer to that: 10 m is the distance inside which `addTree` treats a new pin and an
    /// existing record as **the same tree**. A fix whose own error circle is wider than that cannot
    /// pick out the tree it is offered as a correction *to* — it is an answer to a different
    /// question, which is the shape this project's verification rules warn about.
    public static var positionResolutionRadiusM: Double { TreeDraft.proximityDedupeRadiusM }

    /// Whether a fix of this stated accuracy may be offered as a tree's correct position.
    ///
    /// `AlmanacLimits.fixCanResolveAnArea(accuracyM:withinM:)`'s shape, verbatim and for its stated
    /// reasons: the caller names the radius its own read runs over, and an **unknown** accuracy is
    /// permitted rather than refused — every live path supplies a number, and the callers that pass
    /// `nil` are previews and tests driving a bare coordinate.
    public static func fixCanPlaceATree(accuracyM: Double?, withinM radiusM: Double) -> Bool {
        guard let accuracyM else { return true }
        return accuracyM <= radiusM
    }

    /// The one status part 1 will write.
    ///
    /// R79's third issue kind is "wrong other metadata", and the owner named exactly two examples: a
    /// clearly wrong planted year, and a recorded tree whose plot is actually empty. The second is a
    /// status suggestion of `vacant_site`, which is already in the vocabulary
    /// (`community_trees.status`'s `CHECK`, and the seed's) — modelled that way rather than as a
    /// fresh boolean, on the owner's own instruction, so that the profile's existing vacant-site
    /// handling means something the day a dispute is adjudicated.
    ///
    /// **Narrowed here rather than in the table's `CHECK`**, and the round's contract says so: the
    /// column admits the vocabulary, the code admits one value of it. A widening is then a code
    /// change with a test behind it instead of a migration.
    public static let statusSuggestion: TreeStatus = .vacantSite

    /// Which of the four rules a raise broke.
    ///
    /// **The taxonomy answers *whether*; this answers *why*.** All four are `APIError
    /// .validationFailed` on the wire and that is correct — BUILD-PLAN §6's codes are a closed set
    /// and the non-retryable half is where all four belong. What a code cannot carry is the
    /// sentence a person needs, and the owner's ruling on the 10 m floor is exactly that sentence:
    /// the floor stays *and the sheet says why*, pointing at Precise Location rather than failing
    /// silently. A sheet handed one undifferentiated `.validationFailed` would have to re-implement
    /// the accuracy test to find out which rule fired, which is how the check in front of a user
    /// and the check that binds start to disagree.
    ///
    /// So `refusal(issues:suggestions:)` returns this, `LocalAPI.raiseDataDispute` throws
    /// `apiError`, and a screen pre-checking the same pure function gets the reason. Nothing here
    /// crosses the boundary into `APIError`: adding a code would change the taxonomy the outbox
    /// dispatches on, for a distinction only this one surface makes.
    ///
    /// The associated values are what the copy needs and nothing more — the numbers a sentence about
    /// accuracy has to quote, and the status that was refused.
    public enum Refusal: Hashable, Sendable {
        /// No checkbox is ticked. A dispute that checks nothing says nothing.
        case noIssueChecked
        /// A suggested value for an issue this dispute does not raise; the fields are the ones
        /// speaking out of turn.
        case suggestionOutsideCheckedIssues(Set<TreeDataDispute.SuggestedField>)
        /// The phone's own fix is too coarse to pick out the tree it corrects — the owner's floor.
        /// Both numbers travel because the sentence quotes both ("your fix is good to 40 m; a
        /// correction has to be good to 10").
        case locationFixTooCoarse(accuracyM: Double, requiredM: Double)
        /// A status part 1 does not write. See `statusSuggestion`.
        case unsupportedStatusSuggestion(TreeStatus)

        /// The taxonomy's answer, which is the same one for every arm.
        ///
        /// Non-retryable, which is the property that matters to the queue: an outbox row carrying
        /// one of these would fail on its first attempt rather than burn 48 h on an answer that will
        /// not change (BUILD-PLAN §6). None of them is reachable by a drain in any case — they are
        /// checked before the transaction that writes the row.
        public var apiError: APIError { .validationFailed }
    }

    /// Why this raise may not be written, or `nil` when it may.
    ///
    /// Pure and public so the sheet can ask the same question the API will, and get the same answer
    /// with its reason attached. See `Refusal`.
    public static func refusal(
        issues: Set<TreeDataDispute.IssueKind>,
        suggestions: TreeDataDispute.Suggestions
    ) -> Refusal? {
        // 1. A dispute that checks nothing says nothing. The round's contract names this refusal.
        guard !issues.isEmpty else { return .noIssueChecked }

        // 2. A suggested value for an issue this dispute does not raise is a statement the dispute
        //    does not make. Storing it would leave a suggested species on a record whose species
        //    nobody disputed — and a later adjudicator reading the suggestions table has no way to
        //    tell that from a species the reporter meant.
        let unchecked = suggestions.stored.keys.filter { !issues.contains($0.issue) }
        guard unchecked.isEmpty else {
            return .suggestionOutsideCheckedIssues(Set(unchecked))
        }

        // 3. A position too coarse to pick out the tree it corrects. See `fixCanPlaceATree`.
        if let location = suggestions.location, let accuracyM = location.accuracyM,
           !fixCanPlaceATree(accuracyM: accuracyM, withinM: positionResolutionRadiusM) {
            return .locationFixTooCoarse(
                accuracyM: accuracyM, requiredM: positionResolutionRadiusM
            )
        }

        // 4. Part 1's one status. See `statusSuggestion`.
        if let status = suggestions.status, status != statusSuggestion {
            return .unsupportedStatusSuggestion(status)
        }

        return nil
    }
}
