//
//  SiteModel.swift
//  Cypress — Features/Site
//
//  The site screen's one `@Observable` model (ARCHITECTURE §3). It talks to `CypressAPI` and to
//  nothing else — no store, no network (ARCHITECTURE §4).
//
//  It makes two reads and treats them very differently: the profile *is* the screen, and the
//  nearest standing tree is one row on it. A failure of the second must not take the first down,
//  because the sentence this screen exists to say does not depend on there being a tree nearby.
//

import Foundation
import Observation

@MainActor
@Observable
final class SiteModel {

    /// Where the one required read is.
    ///
    /// `notASite` is a case rather than an error for the reason `MemorialModel.notMemorial` is: it
    /// is a real and reachable answer. The only thing that makes a record a site is `trees.status`,
    /// a moderator can move that status (DECISIONS §3.7) and so can the weekly city diff
    /// (BUILD-PLAN §7), so a link to this screen can be stale by the time it is followed. "There is
    /// a tree here now" is a different fact from "this could not be loaded", and this screen's whole
    /// content is the claim that there is no tree — which makes it the worst thing in the app to get
    /// wrong in that direction.
    enum Phase: Equatable {
        case loading
        case loaded(TreeProfile)
        case notASite
        case failed(APIError)
    }

    let treeID: UUID
    private(set) var phase: Phase = .loading

    /// The nearest tree that is actually standing, once the second read lands. Nil while it is in
    /// flight, nil when there is none within reach, and nil when the read failed — all three render
    /// the same way, which is with no row at all.
    private(set) var nearest: NearbyTree?

    private let api: any CypressAPI

    init(treeID: UUID, api: any CypressAPI) {
        self.treeID = treeID
        self.api = api
    }

    /// The derivation the view draws, or nil in every other phase.
    var presentation: SitePresentation? {
        guard case let .loaded(profile) = phase else { return nil }
        return SitePresentation(profile: profile, nearest: nearest)
    }

    // MARK: - Reads

    func load() async {
        phase = .loading
        nearest = nil
        do {
            let profile = try await api.treeProfile(id: treeID)
            // The one gate, asked of the record rather than of anything a contributor wrote: an
            // observation never mutates `trees.status` (DECISIONS §3.7), so this screen cannot be
            // reached by somebody's opinion of a basin.
            guard profile.tree.status == .vacantSite else {
                phase = .notASite
                return
            }
            phase = .loaded(profile)
            await loadNearestTree(to: profile.tree)
        } catch let error as APIError {
            phase = .failed(error)
        } catch {
            phase = .failed(.serverError)
        }
    }

    /// The nearest standing tree to *the site*, not to the reader.
    ///
    /// Deliberately keyed on the site's own coordinate: a person can open this screen from anywhere,
    /// and a row that quietly measured from the reader's fix would answer a question nobody asked.
    /// The site needs no GPS permission to know where it is.
    ///
    /// Errors are swallowed, and that is the difference between this read and the profile: nothing
    /// on screen claims a nearby tree exists, so nothing on screen can be lying when the row is
    /// absent. The same argument `MapModel.loadFailure` makes for not blanking the map.
    private func loadNearestTree(to site: Tree) async {
        let nearby = try? await api.treesNear(
            site.coordinate,
            radiusM: SiteModel.nearestSearchRadiusM,
            limit: SiteModel.nearestSearchLimit
        )
        guard let nearby else { return }
        // `TreeQueries.nearest` returns rows in ascending distance, so the first standing row is the
        // nearest standing tree full stop: anything the `LIMIT` dropped is farther than every row it
        // kept. That is what makes the word `nearest` in the copy true rather than approximate.
        //
        // The site is in that list itself, at distance zero, and it is excluded by the same test
        // that excludes every other basin around it rather than by its id — one rule, so a site
        // cannot end up pointing at itself through a gap between two of them.
        nearest = nearby.first { SiteModel.isStanding($0.tree.status) }
    }

    /// Whether a tree stands at that record.
    ///
    /// Written out rather than borrowed from `TreeStatus.acceptsNewContributions`, which happens to
    /// partition the five statuses the same way today and means something else: one is a question
    /// about whether a contribution may be written, this is a question about whether there is
    /// anything there to look at. A tree reported dead is still standing until somebody confirms it,
    /// and it is still the nearest tree to this basin. Exhaustive, so a sixth status is a compile
    /// error rather than a silent "yes, point at it".
    static func isStanding(_ status: TreeStatus) -> Bool {
        switch status {
        case .alive, .declining, .deadReported:
            return true
        case .removed, .vacantSite:
            return false
        }
    }

    /// **Judgment call, not a spec value.** 150 m is roughly two SF blocks — far enough that a site
    /// in the middle of a bare stretch still finds something, near enough that the row means "that
    /// one, over there" rather than "somewhere in this neighbourhood".
    static let nearestSearchRadiusM: Double = 150

    /// Enough rows that a run of vacant sites around this one does not exhaust the read before a
    /// standing tree appears. 6.4% of the inventory is vacant, so thirty is a wide margin; the cost
    /// is one indexed range read.
    static let nearestSearchLimit = 30
}
