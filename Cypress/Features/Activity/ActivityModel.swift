//
//  ActivityModel.swift
//  Cypress — Features/Activity
//
//  Screen 13's one `@Observable` model (ARCHITECTURE §3: "One `@Observable` model per feature
//  folder, owned by the feature's root view via `@State`"). It talks to `CypressAPI` and to nothing
//  else — no store, no GRDB, no network (ARCHITECTURE §4).
//
//  It reads `GET /trees/{id}` and adds no method of its own. The profile payload already carried
//  photos, visits and care events as whole `Series`; the one thing it did not carry was the check-in
//  series, and that is a field on `TreeProfile` rather than a second endpoint, because a check-in is
//  part of a tree's profile in exactly the way a visit is. See `TreeProfile.observations`.
//
//  The read is whole on every series, which matters more here than anywhere: this screen's three
//  charts share one scale, and a page understates it silently (ERRATA E38).
//

import Foundation
import Observation

@MainActor
@Observable
final class ActivityModel {

    /// A failed read is its own case rather than an empty screen. They look the same and mean
    /// opposite things, and this screen's whole subject is what is and is not on a tree's record —
    /// the last place to conflate "nothing happened" with "we could not ask".
    enum Phase: Equatable {
        case loading
        case loaded(TreeProfile)
        case failed(APIError)
    }

    private(set) var phase: Phase = .loading

    let treeID: UUID
    private let api: any CypressAPI
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    /// The profile again with the community half merged in, or nil with no service to merge from
    /// (`DataLayer.refreshTreeProfile`). Nil means no background task at all.
    ///
    /// **This screen counts photographs and therefore needs it** — `ActivityPresentation` reads
    /// `visiblePhotos` for the per-month counts and for the first-photo date, and the phone cannot
    /// supply a row it never wrote. PR #147's review found this screen excluded on a wrong premise.
    private let refreshProfile: ((UUID) async -> TreeProfile?)?

    /// The background merge in flight, or nil. Held so a test can await it rather than time it.
    @ObservationIgnored private(set) var profileRefresh: Task<Void, Never>?

    init(
        treeID: UUID,
        api: any CypressAPI,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() },
        refreshProfile: ((UUID) async -> TreeProfile?)? = nil
    ) {
        self.treeID = treeID
        self.api = api
        self.calendar = calendar
        self.now = now
        self.refreshProfile = refreshProfile
    }

    /// Merges the community half in behind the painted screen. A nil answer leaves it standing
    /// (R72 ruling 1).
    private func startProfileRefresh() {
        guard let refreshProfile else { return }
        profileRefresh?.cancel()
        let treeID = self.treeID
        profileRefresh = Task { [weak self] in
            let merged = await refreshProfile(treeID)
            guard !Task.isCancelled, let self, let merged, case .loaded = self.phase else { return }
            self.phase = .loaded(merged)
        }
    }

    var presentation: ActivityPresentation? {
        guard case let .loaded(profile) = phase else { return nil }
        return ActivityPresentation(profile: profile, now: now(), calendar: calendar)
    }

    func load() async {
        do {
            phase = .loaded(try await api.treeProfile(id: treeID))
            startProfileRefresh()
        } catch let error as APIError {
            phase = .failed(error)
        } catch {
            phase = .failed(.serverError)
        }
    }

    /// The load writes nothing, so a retry is free.
    func reload() async {
        phase = .loading
        await load()
    }
}
