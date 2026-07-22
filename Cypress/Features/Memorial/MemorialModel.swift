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

    init(treeID: UUID, api: any CypressAPI, now: @escaping @Sendable () -> Date = { Date() }) {
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
        } catch let error as APIError {
            phase = .failed(error)
        } catch {
            phase = .failed(.serverError)
        }
    }
}
