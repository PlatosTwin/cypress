//
//  ShareModel.swift
//  Cypress — Features/Share
//
//  Screen 10's one `@Observable` model (ARCHITECTURE §3: "One `@Observable` model per feature
//  folder, owned by the feature's root view via `@State`"). It talks to `CypressAPI` and to nothing
//  else — no store, no GRDB, no network (ARCHITECTURE §4).
//

import Foundation
import Observation

@MainActor
@Observable
final class ShareModel {

    /// Where the one read is.
    ///
    /// A failed read is its own case rather than an empty card. The two look alike on screen and
    /// mean opposite things: one is a tree with nothing public about it yet, the other is "we could
    /// not tell" — and a share card built on a failed read would put a name and a link in front of
    /// somebody with nothing standing behind either.
    enum Phase: Equatable {
        case loading
        case loaded(SharePresentation)
        case failed
    }

    private(set) var phase: Phase = .loading

    let treeID: UUID
    private let api: any CypressAPI
    private let calendar: Calendar

    /// The profile again with the community half merged in, or nil with no service to merge from
    /// (`DataLayer.refreshTreeProfile`). Nil means no background task at all.
    ///
    /// **This sheet needs it more than any other surface in the app.** `SharePresentation` takes
    /// `publiclyVisiblePhotos`, which is `moderationState == .approved` — and `.approved` is produced
    /// in exactly one place in the shipping app, the community half's own decode
    /// (`RemoteAPI.treeCommunityHalf`). `moderation_state` defaults to `pending` and there is no
    /// local write path to change it, so without this closure the card's photo set is
    /// **unconditionally** empty rather than merely usually empty. The file header above says
    /// "nothing in the shipping app can set `.approved`"; this is the one thing that can, and it
    /// reaches this sheet only through here. PR #147's review found this.
    private let refreshProfile: ((UUID) async -> TreeProfile?)?

    /// The background merge in flight, or nil. Held so a test can await it rather than time it.
    @ObservationIgnored private(set) var profileRefresh: Task<Void, Never>?

    init(
        treeID: UUID,
        api: any CypressAPI,
        calendar: Calendar = .current,
        refreshProfile: ((UUID) async -> TreeProfile?)? = nil
    ) {
        self.refreshProfile = refreshProfile
        self.treeID = treeID
        self.api = api
        self.calendar = calendar
    }

    var presentation: SharePresentation? {
        guard case let .loaded(presentation) = phase else { return nil }
        return presentation
    }

    var hasFailed: Bool { phase == .failed }

    /// One read, and it is the whole sheet.
    func load() async {
        do {
            let profile = try await api.treeProfile(id: treeID)
            phase = .loaded(SharePresentation(profile: profile, calendar: calendar))
            startProfileRefresh()
        } catch {
            phase = .failed
        }
    }

    /// Merges the community half in behind the painted card — the only way an approved photograph
    /// reaches this sheet at all. See `refreshProfile`.
    ///
    /// A nil answer leaves the painted card standing (R72 ruling 1).
    private func startProfileRefresh() {
        guard let refreshProfile else { return }
        profileRefresh?.cancel()
        let treeID = self.treeID
        let calendar = self.calendar
        profileRefresh = Task { [weak self] in
            let merged = await refreshProfile(treeID)
            guard !Task.isCancelled, let self, let merged, case .loaded = self.phase else { return }
            self.phase = .loaded(SharePresentation(profile: merged, calendar: calendar))
        }
    }

    /// Re-reads after a failure. The load writes nothing, so a retry is free.
    func retry() async {
        phase = .loading
        await load()
    }
}
