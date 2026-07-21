//
//  TreeProfileModel.swift
//  Cypress — Features/TreeProfile
//
//  Screen 03 / 14's one `@Observable` model (ARCHITECTURE §3: "One `@Observable` model per feature
//  folder, owned by the feature's root view via `@State`").
//
//  It talks to `CypressAPI` and to nothing else — no GRDB, no SQLite, no network (ARCHITECTURE §4).
//

import Foundation
import Observation

@MainActor
@Observable
final class TreeProfileModel {

    enum Phase {
        case loading
        /// Carries the derivation, not the raw payload: everything the view draws is decided in
        /// `TreeProfilePresentation`, which has no SwiftUI in it and can be reasoned about alone.
        case loaded(TreeProfilePresentation)
        case failed(APIError)
    }

    private(set) var phase: Phase = .loading

    let treeID: UUID
    private let api: any CypressAPI

    /// Initials for the regulars row (C26).
    ///
    /// `TreeProfile` carries caretakers as bare `UUID`s — there is no name, handle or initial in
    /// the payload — so this cannot be derived from a real read today, and deriving a letter from a
    /// UUID would be fabricating an identity. It is injected instead: when the API grows caretaker
    /// identities (ARCHITECTURE §4: "if a screen needs data, the protocol grows a method") this is
    /// the one line that changes. Empty against `LocalAPI`, which is why the row does not render.
    var caretakerInitials: [String]

    init(treeID: UUID, api: any CypressAPI, caretakerInitials: [String] = []) {
        self.treeID = treeID
        self.api = api
        self.caretakerInitials = caretakerInitials
    }

    var presentation: TreeProfilePresentation? {
        if case let .loaded(presentation) = phase { return presentation }
        return nil
    }

    func load() async {
        do {
            let profile = try await api.treeProfile(id: treeID)
            phase = .loaded(
                TreeProfilePresentation(profile: profile, caretakerInitials: caretakerInitials)
            )
        } catch let error as APIError {
            phase = .failed(error)
        } catch {
            phase = .failed(.serverError)
        }
    }

    /// Re-reads after a contribution lands. The screen keeps what it has while the read runs, so a
    /// visit that just synced does not blank the profile it was made from.
    func reload() async {
        await load()
    }
}
