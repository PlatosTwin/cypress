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

    init(treeID: UUID, api: any CypressAPI, calendar: Calendar = .current) {
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
        } catch {
            phase = .failed
        }
    }

    /// Re-reads after a failure. The load writes nothing, so a retry is free.
    func retry() async {
        phase = .loading
        await load()
    }
}
