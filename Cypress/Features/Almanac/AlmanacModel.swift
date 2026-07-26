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
    ///
    /// **It is a `var` now, and that is the whole of this defect's fix**
    /// (ERRATA — see docs/errata-pending/almanac-blank.md). It used to be a `let` set once, from a
    /// view whose `@State` initialiser runs exactly once — so an almanac built before CoreLocation
    /// answered read `almanac(near: nil)`, got `.empty` by contract, and stayed empty for the life
    /// of the view.
    private(set) var coordinate: Coordinate?

    /// The fix that the state currently *on screen* was derived from — not necessarily the one the
    /// model has been handed since.
    ///
    /// The two differ for exactly as long as a re-read is in flight, and that gap is the reason this
    /// property exists rather than the view asking `coordinate == nil`. The prompt has to be
    /// withdrawn at the moment the neighbourhood appears, not at the moment the fix arrives; those
    /// are one database read apart, and in between the screen has nothing on it and would be saying
    /// nothing about why (E126's invariant).
    private(set) var displayedCoordinate: Coordinate?

    private let now: @Sendable () -> Date

    init(api: any CypressAPI, coordinate: Coordinate?, now: @escaping @Sendable () -> Date = { Date() }) {
        self.api = api
        self.coordinate = coordinate
        self.displayedCoordinate = coordinate
        self.now = now
    }

    /// The derivation the view draws, or nil while loading or after a failure.
    var presentation: AlmanacPresentation? {
        guard case let .loaded(almanac) = phase else { return nil }
        return AlmanacPresentation(almanac: almanac, now: now())
    }

    var hasFailed: Bool { phase == .failed }

    /// Whether what is on screen is empty *because there is no fix* — E123's prompt condition.
    ///
    /// Asked of the model rather than computed at the view layer from the parameter, which is where
    /// E123 put it. A `let showsLocationPrompt = coordinate == nil` on the view is recomputed on
    /// every pass the parent makes, so it flipped to false the instant CoreLocation answered — while
    /// the model, built once, still held the empty almanac it had read from `nil`. The prompt was
    /// withdrawn from a screen that had nothing to replace it with. This reads the coordinate behind
    /// the *picture*, so the sentence and the picture cannot disagree.
    var needsLocation: Bool { displayedCoordinate == nil }

    func load() async {
        let requested = coordinate
        do {
            let almanac = try await api.almanac(near: requested)
            // A newer fix arrived while this read was in flight; its own read is authoritative and
            // this one's answer is about a place the reader has already left.
            guard requested == coordinate else { return }
            phase = .loaded(almanac)
        } catch {
            guard requested == coordinate else { return }
            phase = .failed
        }
        displayedCoordinate = requested
    }

    /// Take the fix the composition root has *now* and re-read if it is a different one.
    ///
    /// Called from `AlmanacView`'s `.task(id:)`, so it runs once on mount and again on every change
    /// — including the one that matters, `nil` → a coordinate, a second or so after a cold launch.
    /// The phase is deliberately **not** reset to `.loading` here: the almanac already on screen
    /// (empty, with the prompt over it, or a previous neighbourhood) stays until the replacement has
    /// actually been read, so the re-read costs the reader no blank frame.
    func update(coordinate newValue: Coordinate?) async {
        guard newValue != coordinate || phase == .loading else { return }
        coordinate = newValue
        await load()
    }

    /// Re-reads after a failure. The load writes nothing, so a retry is free — the same reason
    /// `ShareModel.retry` and `SpeciesModel.retry` can offer one (ERRATA E126).
    func retry() async {
        phase = .loading
        await load()
    }
}
