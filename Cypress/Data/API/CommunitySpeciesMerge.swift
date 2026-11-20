//
//  CommunitySpeciesMerge.swift
//  Cypress — Data/API
//
//  ROADMAP 144: a species answer on a community tree somebody else added counts for everyone. The
//  service decides who counts; this file is how the profile lays the service's answer over what
//  the phone knows, and the seam `RoutedAPI` reaches `LocalAPI` through for it.
//
//  ── Which answer wins ──────────────────────────────────────────────────────────────────────────
//  The service's, whenever it sent one (`species_reported`, `species_report_flag_id`,
//  `species_named_by_you`, and the tree's species), except for an act of the reader's that is still
//  queued, which the service cannot include yet:
//  - a queued naming or correction keeps the reader's own species on screen, and keeps the
//    reader's correction control;
//  - a queued report keeps the reported line;
//  - the adder's queued correction ends the line, because the service clears every report on it;
//  - the adder's queued "Keep the species" ends the line only when it names the report the service
//    sent (`species_report_flag_id`). The service clears up to the report the keep names, so a
//    newer report, with another flag id, keeps the line and the control. This is the owner's "the
//    line clears for everyone": without it, the read that follows the tap, which runs before the
//    queue drains, would draw the line and the control again.
//
//  A service that sent none of the keys (release v16 and older) leaves every answer the phone's.
//

import Foundation

/// How `RoutedAPI` reaches the parts of `LocalAPI` that `CypressAPI` does not carry, for
/// ROADMAP 144. `DataLayer.boot` wires it; a router without it keeps the phone's answers.
public struct CommunitySpeciesSeam: Sendable {
    /// `LocalAPI.speciesAnswerState(treeID:)`.
    public let state: @Sendable (UUID) async -> SpeciesAnswerState?
    /// `LocalAPI.adoptServedSpecies(treeID:observed:served:)`.
    public let adopt: @Sendable (UUID, UUID?, UUID) async -> Bool
    /// `LocalAPI.keepServedSpeciesReport(treeID:flagID:)`.
    public let keep: @Sendable (UUID, UUID) async throws -> Void

    public init(
        state: @escaping @Sendable (UUID) async -> SpeciesAnswerState?,
        adopt: @escaping @Sendable (UUID, UUID?, UUID) async -> Bool,
        keep: @escaping @Sendable (UUID, UUID) async throws -> Void
    ) {
        self.state = state
        self.adopt = adopt
        self.keep = keep
    }
}

/// The reports the service named to this phone's adder (`species_report_flag_id`), by flag id, with
/// the tree each is about. Written by `RoutedAPI.refreshedTreeProfile(id:)`, read by
/// `RoutedAPI.dismissSpeciesReview(flagID:)`, which needs the tree to queue the keep. The control
/// that sends the keep is drawn only from a profile read that wrote the entry, so an entry lost
/// with the app's memory is written again before the control can show.
public actor ServedSpeciesReports {
    private var trees: [UUID: UUID] = [:]

    public init() {}

    public func remember(flagID: UUID, treeID: UUID) {
        trees[flagID] = treeID
    }

    public func tree(of flagID: UUID) -> UUID? {
        trees[flagID]
    }
}

/// The merge itself, pure, so it can be tested without a store or a service.
public enum CommunitySpeciesMerge {

    /// The species control after the service's answer.
    ///
    /// - Parameters:
    ///   - local: the phone's own offer (`LocalAPI.treeProfile`).
    ///   - served: the service's answer, or nil when it sent none.
    ///   - state: the reader's queued acts, or nil when the phone could not say.
    ///   - isAdder: the reader added the tree, by this phone's own record.
    ///   - addedOnAnotherPhone: the service says the reader added a tree this phone holds only in
    ///     the cache. Nothing here can act as its adder, so it offers nothing.
    ///   - hasSpecies: the merged profile shows a species.
    public static func offer(
        local: SpeciesCorrectionOffer,
        served: RemoteAPI.TreeCommunityDelta.ServedSpecies?,
        state: SpeciesAnswerState?,
        isAdder: Bool,
        addedOnAnotherPhone: Bool,
        readerShares: Bool,
        hasSpecies: Bool,
        treeID: UUID
    ) -> SpeciesCorrectionOffer {
        if case .dataDispute = local { return local }
        if addedOnAnotherPhone { return .unavailable }
        guard let served else { return local }
        let answerQueued = state?.answerQueued ?? false
        let kept = isAdder && served.reportFlagID.map { state?.keptFlagIDs.contains($0) ?? false } == true
        let reported = (served.isReported && !(isAdder && answerQueued) && !kept) || (state?.reportQueued ?? false)
        return SpeciesAnswerFacts(
            hasSpecies: hasSpecies,
            isAdder: isAdder,
            isNamer: !isAdder && (served.namedByYou || answerQueued),
            readerShares: readerShares,
            isReported: reported,
            reportFlagID: isAdder ? (served.reportFlagID ?? state?.openFlagID) : state?.openFlagID
        ).offer(placeholderFlagID: treeID)
    }

    /// The species a cached tree's profile shows after the service's answer: the service's, unless
    /// the reader's own naming or correction is still queued, and nil when the service sent none.
    /// Only for a tree this phone holds in the cache; a tree this phone added shows its own row,
    /// which `LocalAPI.adoptServedSpecies` brings up to date.
    public static func shownSpecies(
        local: UUID?,
        served: RemoteAPI.TreeCommunityDelta.ServedSpecies?,
        state: SpeciesAnswerState?
    ) -> UUID? {
        guard let served, !(state?.answerQueued ?? false) else { return local }
        return served.speciesID
    }
}
