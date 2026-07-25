//
//  AlmanacModel.swift
//  Cypress — Features/Almanac
//
//  Screen 12's one `@Observable` model (ARCHITECTURE §3: "One `@Observable` model per feature
//  folder, owned by the feature's root view via `@State`"). It talks to `CypressAPI` and to nothing
//  else — no store, no network (ARCHITECTURE §4).
//

import Foundation
import Observation

@MainActor
@Observable
final class AlmanacModel {

    /// Where the one read is.
    ///
    /// A failed read is its own case rather than an empty almanac, for the reason `GroveModel` keeps
    /// the same distinction: the two look identical on screen and mean opposite things. "Nothing is
    /// happening in your neighbourhood" and "we could not ask" are different sentences, and this
    /// screen — whose entire subject is what is and is not there — is the last place to conflate
    /// them.
    enum Phase: Equatable {
        case loading
        case loaded(Almanac)
        case failed
    }

    private(set) var phase: Phase = .loading

    private let api: any CypressAPI
    /// The caller's fix, from the composition root (ARCHITECTURE §3 puts `LocationProvider` there).
    /// `nil` when location has not been granted or has not arrived, which is a real state: without
    /// a fix there is no area and the almanac has no subject at all (A4, ERRATA E44).
    private let coordinate: Coordinate?
    private let now: @Sendable () -> Date

    init(api: any CypressAPI, coordinate: Coordinate?, now: @escaping @Sendable () -> Date = { Date() }) {
        self.api = api
        self.coordinate = coordinate
        self.now = now
    }

    /// The derivation the view draws, or nil while loading or after a failure.
    var presentation: AlmanacPresentation? {
        guard case let .loaded(almanac) = phase else { return nil }
        return AlmanacPresentation(almanac: almanac, now: now())
    }

    var hasFailed: Bool { phase == .failed }

    func load() async {
        do {
            phase = .loaded(try await api.almanac(near: coordinate))
        } catch {
            phase = .failed
        }
    }

    /// Re-reads after a failure. The load writes nothing, so a retry is free — the same reason
    /// `ShareModel.retry` and `SpeciesModel.retry` can offer one (ERRATA E126).
    func retry() async {
        phase = .loading
        await load()
    }
}
