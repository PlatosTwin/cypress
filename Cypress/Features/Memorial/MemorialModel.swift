//
//  MemorialModel.swift
//  Cypress — Features/Memorial
//
//  Screen 19's one `@Observable` model (ARCHITECTURE §3). It talks to `CypressAPI` and to nothing
//  else — no store, no network (ARCHITECTURE §4).
//

import Foundation
import Observation

@MainActor
@Observable
final class MemorialModel {

    /// Where the one read is.
    ///
    /// `notMemorial` is a case rather than an error because it is a real and reachable answer: the
    /// only thing that makes a tree a memorial is `trees.status`, a moderator can move that status
    /// (DECISIONS §3.7), and a link to this screen can therefore be stale by the time it is
    /// followed. "This tree is not removed" is a different fact from "this tree could not be
    /// loaded", and the screen is about a tree that is gone — showing a memorial for a living tree
    /// would be the worst possible thing for it to get wrong.
    enum Phase: Equatable {
        case loading
        case loaded(TreeProfile)
        case notMemorial
        case failed(APIError)
    }

    let treeID: UUID
    private(set) var phase: Phase = .loading

    private let api: any CypressAPI
    private let now: @Sendable () -> Date

    /// The profile again with the community half merged in, or nil with no service to merge from
    /// (`DataLayer.refreshTreeProfile`). Nil means no background task at all.
    ///
    /// **This screen draws photographs and therefore needs it** — the hero, the `Last photo` eyebrow,
    /// the `First photo` milestone and the `N photos · since <year>` pill all read
    /// `TreeProfile.visiblePhotos`, and the phone cannot supply a row it never wrote: nothing syncs
    /// anybody else's photographs down (`ContributionStore`), and the seed carries no photo table at
    /// all. PR #147's review found this screen excluded from the merge on a wrong premise.
    private let refreshProfile: ((UUID) async -> TreeProfile?)?

    /// The background merge in flight, or nil. Held so a test can await it rather than time it —
    /// `GroveModel.speciesRefresh`'s reasoning, and its `@ObservationIgnored` for its reason.
    @ObservationIgnored private(set) var profileRefresh: Task<Void, Never>?

    init(
        treeID: UUID,
        api: any CypressAPI,
        now: @escaping @Sendable () -> Date = { Date() },
        refreshProfile: ((UUID) async -> TreeProfile?)? = nil
    ) {
        self.refreshProfile = refreshProfile
        self.treeID = treeID
        self.api = api
        self.now = now
    }

    /// The derivation the view draws, or nil in every other phase.
    var presentation: MemorialPresentation? {
        guard case let .loaded(profile) = phase else { return nil }
        return MemorialPresentation(profile: profile, facts: facts(for: profile), now: now())
    }

    /// What the record knows about the removal itself.
    ///
    /// Nothing, today, and deliberately assembled in one place rather than left implicit: BUILD-PLAN
    /// §4's `trees` has no `removed_at` and no removal reason, so there is no column to read and no
    /// method on `CypressAPI` that would return one. See `MemorialFacts` for the two candidate
    /// sources and why choosing between them is a schema decision rather than this screen's.
    ///
    /// When one of them lands, this is the single line that changes.
    private func facts(for profile: TreeProfile) -> MemorialFacts { .unknown }

    func load() async {
        phase = .loading
        do {
            let profile = try await api.treeProfile(id: treeID)
            // The one gate. `TreeStatus.isMemorial` is the whole test, and it is asked of the tree
            // rather than of anything a contributor wrote: an observation reporting a removal opens
            // a review flag and never moves the status (DECISIONS §3.7), so this screen cannot be
            // reached by somebody's opinion of a tree.
            phase = profile.tree.status.isMemorial ? .loaded(profile) : .notMemorial
            startProfileRefresh()
        } catch let error as APIError {
            phase = .failed(error)
        } catch {
            phase = .failed(.serverError)
        }
    }

    /// Merges the community half in behind the painted memorial.
    ///
    /// **The memorial gate is re-applied to the merged profile rather than assumed.** The status is
    /// a local fact and the merge carries it over unchanged, so it cannot flip — but re-asking is one
    /// line and assuming is the shape of comment this repository has been bitten by. A nil answer
    /// leaves the painted screen exactly as it is (R72 ruling 1).
    private func startProfileRefresh() {
        guard let refreshProfile else { return }
        profileRefresh?.cancel()
        let treeID = self.treeID
        profileRefresh = Task { [weak self] in
            let merged = await refreshProfile(treeID)
            guard !Task.isCancelled, let self, let merged, case .loaded = self.phase,
                  merged.tree.status.isMemorial
            else { return }
            self.phase = .loaded(merged)
        }
    }
}
