//
//  GroveModel.swift
//  Cypress — Features/Grove
//
//  Screen 08's one `@Observable` model (ARCHITECTURE §3: "One `@Observable` model per feature
//  folder, owned by the feature's root view via `@State`"). It talks to `CypressAPI` and to nothing
//  else — no store, no network (ARCHITECTURE §4).
//

import Foundation
import Observation

@MainActor
@Observable
final class GroveModel {

    /// Where the one read is.
    ///
    /// A failed read is its own case rather than an empty grove, because the two look identical on
    /// screen and mean opposite things: one says "you have not met a species yet", the other says
    /// "we could not tell". Drawing the cold-start state over a failure would be the same class of
    /// mistake as printing a page's size as a total.
    enum Phase: Equatable {
        case loading
        case loaded(GroveSpecies)
        case failed
    }

    private(set) var phase: Phase = .loading

    /// Which of the three pills SCREENS.md 08 §2 is on. Always `.species`: this screen *is* the
    /// Species tab, and the other two have nowhere to go (see `GroveTab.hasDestination`).
    let tab: GroveTab = .species

    private let api: any CypressAPI
    private let now: @Sendable () -> Date

    init(api: any CypressAPI, now: @escaping @Sendable () -> Date = { Date() }) {
        self.api = api
        self.now = now
    }

    /// The derivation the view draws, or nil while loading or after a failure.
    var presentation: GrovePresentation? {
        guard case let .loaded(grove) = phase else { return nil }
        return GrovePresentation(grove: grove, now: now())
    }

    var hasFailed: Bool { phase == .failed }

    func load() async {
        do {
            phase = .loaded(try await api.groveSpecies())
        } catch {
            phase = .failed
        }
    }
}
