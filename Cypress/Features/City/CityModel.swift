//
//  CityModel.swift
//  Cypress — Features/City
//
//  The City segment's one `@Observable` model (ARCHITECTURE §3), the same shape `AlmanacModel`
//  keeps and for the same reasons — see that file's comments, which apply here unchanged. It talks
//  to `CypressAPI` and to nothing else.
//

import Foundation
import Observation

@MainActor
@Observable
final class CityModel {

    /// Where the one read is. A failed read is its own case rather than an empty city, the same
    /// distinction `AlmanacModel.Phase` draws: "nothing more to say about this city" and "we could
    /// not ask" are different sentences.
    enum Phase: Equatable {
        case loading
        case loaded(CityAlmanac)
        case failed
    }

    private(set) var phase: Phase = .loading

    private let api: any CypressAPI
    /// The caller's fix. `nil` when location has not been granted or has not arrived — without a fix
    /// there is no coordinate to resolve a city from, and this screen has no subject at all.
    private(set) var coordinate: Coordinate?

    /// The fix the state currently *on screen* was derived from, not necessarily the one the model
    /// has been handed since — `AlmanacModel.displayedCoordinate`'s own reasoning, unchanged.
    private(set) var displayedCoordinate: Coordinate?

    init(api: any CypressAPI, coordinate: Coordinate?) {
        self.api = api
        self.coordinate = coordinate
        self.displayedCoordinate = coordinate
    }

    /// The derivation the view draws, or nil while loading or after a failure.
    var presentation: CityPresentation? {
        guard case let .loaded(city) = phase else { return nil }
        return CityPresentation(city: city)
    }

    var hasFailed: Bool { phase == .failed }

    /// Whether what is on screen is empty because there is no fix — `AlmanacModel.needsLocation`'s
    /// own condition, asked of the model rather than computed from the parameter for the same reason:
    /// the sentence and the picture must not disagree while a re-read is in flight.
    var needsLocation: Bool { displayedCoordinate == nil }

    func load() async {
        let requested = coordinate
        do {
            let city = try await api.city(near: requested)
            guard requested == coordinate else { return }
            phase = .loaded(city)
        } catch {
            guard requested == coordinate else { return }
            phase = .failed
        }
        displayedCoordinate = requested
    }

    /// Take the fix the composition root has *now* and re-read if it is a different one. The phase
    /// is deliberately not reset to `.loading` — `AlmanacModel.update(coordinate:)`'s own reasoning.
    func update(coordinate newValue: Coordinate?) async {
        guard newValue != coordinate || phase == .loading else { return }
        coordinate = newValue
        await load()
    }

    /// Re-reads after a failure. The load writes nothing, so a retry is free.
    func retry() async {
        phase = .loading
        await load()
    }
}
