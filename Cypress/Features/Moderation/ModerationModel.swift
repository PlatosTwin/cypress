//
//  ModerationModel.swift
//  Cypress — Features/Moderation
//
//  The local moderation route (ERRATA E124-B): a community lead's review queue, and the confirm that
//  turns a reported-removed tree into a memorial.
//
//  ── What a "lead" is here ───────────────────────────────────────────────────────────────────
//  In the product a role is granted by an org coordinator on a server (PRODUCT §2). The local beta
//  has no server and no `users` table (ERRATA E86), so the role is carried on the signed-in account
//  in `app_state` and the promote path is the DEBUG affordance in the You tab — the project owner
//  stepping into the mocked city-personnel lead role to verify removals, which is exactly the
//  "designate some people as community leads" the moderation route was chosen for.
//
//  This model owns the `LocalAPI` directly rather than a `CypressAPI`, for the reason the moderation
//  methods live on `LocalAPI` and not the protocol: confirming a flag into a status transition was a
//  web `/admin/*` deliverable the protocol deliberately omits. `OutboxViewState` depends on the
//  concrete store for the same kind of reason.
//

import Foundation
import Observation

@MainActor
@Observable
final class ModerationModel {

    /// Optional so a preview or a screenshot fixture can build an inert, non-lead model with no store
    /// behind it (`ModerationModel(api: nil)`) — which draws exactly the You tab a non-lead sees.
    private let api: LocalAPI?

    /// Whether the signed-in account may resolve a review (`UserRole.canConfirmReviewFlag`). The You
    /// tab shows the whole section only when this is true, so a non-lead never sees the queue — but
    /// the authority that actually protects a tree is on the write (`LocalAPI.confirmReview` and
    /// `dismissReview`), not on this flag.
    private(set) var canModerate = false

    /// The open status reviews, newest first, of every kind a confirm can resolve — `appears_removed`
    /// and `appears_dead` (ERRATA E170). Empty is a real, common state and reads as "nothing to
    /// review", not as a failure.
    private(set) var items: [ReviewQueueItem] = []

    private(set) var isBusy = false

    init(api: LocalAPI?) {
        self.api = api
    }

    /// Read the role, then — only if it can moderate — the open reviews. Called from the You tab's
    /// `.task`, so switching to the tab refreshes the queue, and again after a confirm or a promote.
    func load() async {
        guard let api else {
            canModerate = false
            items = []
            return
        }
        canModerate = await api.userRole.canConfirmReviewFlag
        guard canModerate else {
            items = []
            return
        }
        items = (try? await api.openReviews()) ?? []
    }

    /// Confirm one review. The tree takes the status the flag's kind resolves to and the flag closes;
    /// then the queue reloads, so the resolved row leaves the list and the map's next read shows it.
    func confirm(_ item: ReviewQueueItem) async {
        guard let api, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        try? await api.confirmReview(flagID: item.flagID)
        await load()
    }

    /// Dismiss one review: the flag closes and **the tree does not move** (ERRATA E170). The second
    /// verb the queue never had — before this, a lead who thought a report was wrong could only leave
    /// it open, and the list only ever grew in the direction of agreeing.
    func dismiss(_ item: ReviewQueueItem) async {
        guard let api, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        try? await api.dismissReview(flagID: item.flagID)
        await load()
    }

    #if DEBUG
    /// The DEBUG promote path: become a lead (a `coordinate`-role account) so the queue and its
    /// confirm are reachable on a device with no server to grant a role. `#if DEBUG` so it cannot
    /// ship — the Release build has no way to self-promote, exactly as a real moderation grant is not
    /// the account's own to make.
    func promoteToLeadForDebug() async {
        try? await api?.setRole(.coordinator)
        await load()
    }

    /// Step back down, so the section can be tested appearing and disappearing.
    func stepDownForDebug() async {
        try? await api?.setRole(.member)
        await load()
    }
    #endif
}
