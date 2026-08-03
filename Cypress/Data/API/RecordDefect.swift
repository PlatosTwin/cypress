//
//  RecordDefect.swift
//  Cypress — Data/API
//
//  "There is no tree here and there never was" — task **#125**, from the owner walking the product:
//  *"We need a way to flag that a tree that is listed on the map doesn't appear to exist at all."*
//
//  ── Why this is not a removal, and therefore not `appearsRemoved` ───────────────────────────────
//  `RULINGS R46` decided it before anything was built, and AppSchema v14 reserved the
//  `review_flags.kind` value. Confirming `appears_removed` writes `TreeStatus.removed`, which this
//  product has settled as a **memorial** — grey pin spoken as "Removed tree, memorial", screen 19,
//  `acceptsNewContributions == false` (E170, R19). A record that never had a tree behind it would
//  get a memorial page for a tree that never lived. That is R7's vacant-site argument, arriving at
//  the case where the map's assertion is not merely imprecise but false, and D16 needs the two apart
//  in the merged national inventory: a dated lifecycle event, against a row that should not be in
//  the table at all.
//
//  ── Why it is not `vacantSite` either ───────────────────────────────────────────────────────────
//  R46 left that open — `TreeStatus.vacantSite` exists and looks like the truthful confirmed state.
//  It is not. A vacant site is a planting *site* with its tree missing, drawn as a hollow ring
//  exactly so it does not borrow the removed pin's meaning. A duplicate pin two metres from another,
//  or a record standing in the middle of a building, is not a vacant planting site; writing one
//  would leave the map asserting a site where there is nothing. See
//  `ReviewFlag.Kind.confirmedStatus`, which stays nil for this kind and must.
//
//  ── The seam, beside E170's rather than inside it ───────────────────────────────────────────────
//  `ReviewFlag.Kind.resolution` gains a fourth arm, `.recordWithdrawal`, and `confirmedStatus` is
//  still derived from it — so `statusReviewKinds` does not grow, the lead queue does not gain a
//  record defect, and E170's property holds: one exhaustive switch that both the raise and the
//  resolve read, so a kind that can be raised and never resolved is a compile error. This is R45's
//  shape for the species seam, applied a second time because the alternative is the tempting
//  one-liner that would move trees on grounds nobody made.
//
//  ── Community rows only, and the refusal is the point ───────────────────────────────────────────
//  A city row lives in the ATTACHed read-only seed. Nothing on this device can withdraw one, and
//  there is no suppression path parallel to `tree_status_overrides` for a row that should not be
//  there. So a raise on a city row is a report nothing can resolve, which is precisely the E170
//  defect, and it is refused with `.forbidden` — the same refusal `flagWrongSpecies` gives a city
//  row, for the same stated reason. What that leaves undone is named in the pending ruling rather
//  than left to be discovered.
//

import Foundation

public extension CypressAPI {

    /// The honest answer from an implementation with no store: there is no such record here.
    ///
    /// Not `.serverError` — nothing failed — and not a silent success, which would let a preview
    /// report a defect it never recorded. Same bargain as `SpeciesClaim`'s defaults.
    func flagNeverExisted(treeID: UUID) async throws {
        throw APIError.notFound
    }

    func withdrawRecord(flagID: UUID) async throws {
        throw APIError.notFound
    }

    func dismissRecordReview(flagID: UUID) async throws {
        throw APIError.notFound
    }
}

/// What a viewer may do about a record they believe was never a tree — the whole surface of #125,
/// decided in `Data` and carried on the profile payload.
///
/// One value rather than a pair of booleans, for `SpeciesCorrectionOffer`'s reason: "reportable" and
/// "already reported" are mutually exclusive states of one record, and a view assembling them from
/// separate flags could draw both controls or neither. The decision needs the viewer's role and a
/// `review_flags` read, neither of which a presentation has any business holding.
public enum RecordDefectOffer: Hashable, Sendable {
    /// Nothing to report: a city row (whose withdrawal this app cannot perform), or a record already
    /// withdrawn.
    ///
    /// Not spelled `none`, for the reason `SpeciesCorrectionOffer.unavailable` gives: a case by that
    /// name shadows `Optional.none` at every call site comparing against a leading dot, and the
    /// compiler resolves the ambiguity silently.
    case unavailable
    /// This record may be reported as never having held a tree. `flagNeverExisted`.
    case reportable
    /// A report is open. `canResolve` is whether *this* viewer may answer it — a lead, and only a
    /// lead, because `community_trees` records no author (R45's finding, unchanged) and so there is
    /// nobody whose own record this is to withdraw.
    case underReview(flagID: UUID, canResolve: Bool)
}
