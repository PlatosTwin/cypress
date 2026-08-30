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

    /// How good that fix is, in meters (`MapLocationProvider.Availability.accuracyM`).
    ///
    /// **Carried because the screen's honesty depends on it and nothing used to read it** — see
    /// `AlmanacLimits.fixCanResolveAnArea(accuracyM:)`, which is the whole of the rule and the whole
    /// of the reasoning. `nil` in previews and tests that drive a bare coordinate, which is the
    /// permitted case that leaves them behaving exactly as before.
    private(set) var accuracyM: Double?

    /// Which city this segment is about: the reader's own, or one they chose (`CitySelection`).
    ///
    /// **An input, like `coordinate`** — see `AlmanacModel.selection`, whose reasoning is this
    /// property's too: the picker is presented by the composition root and writes
    /// `AppRouter.journalCity`.
    private(set) var selection: CitySelection = .here

    /// The fix the state currently *on screen* was derived from, not necessarily the one the model
    /// has been handed since — `AlmanacModel.displayedCoordinate`'s own reasoning, unchanged. The
    /// accuracy and the selection ride along for the same reason: all three describe the picture
    /// that is drawn, and while a re-read is in flight they and the live values disagree.
    private(set) var displayedCoordinate: Coordinate?
    private(set) var displayedAccuracyM: Double?
    private(set) var displayedSelection: CitySelection = .here

    init(
        api: any CypressAPI,
        coordinate: Coordinate?,
        accuracyM: Double? = nil,
        selection: CitySelection = .here
    ) {
        self.api = api
        self.coordinate = coordinate
        self.accuracyM = accuracyM
        self.selection = selection
        self.displayedCoordinate = coordinate
        self.displayedAccuracyM = accuracyM
        self.displayedSelection = selection
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
    ///
    /// Asked only of `.here`: a reader who chose a city is not waiting on a fix and is not being
    /// asked to turn anything on.
    var needsLocation: Bool { displayedSelection.isHere && displayedCoordinate == nil }

    /// Whether the screen is empty because the fix, though present, is too coarse to say which city
    /// the reader is in — tester report F17.
    ///
    /// Distinct from `needsLocation`, and the distinction is the point: location is on, the reader
    /// granted it, and there is nothing to turn on. What there is, is a choice to make.
    ///
    /// **Bounded by `fallbackRadiusM`, which is this segment's own search radius and not the
    /// almanac's** (PR #132 review, F3). `CityQueries.resolveIDSpace(near:radiusM:)` is handed
    /// `AlmanacLimits.fallbackRadiusM` (1,200 m); keyed on the almanac's 400 m instead, a fix good to
    /// 600 m blanked a segment that could still answer, and did answer on main. The two segments ask
    /// different questions over different distances and each one's gate takes its own.
    var needsAreaChoice: Bool {
        displayedSelection.isHere
            && displayedCoordinate != nil
            && !AlmanacLimits.fixCanResolveAnArea(
                accuracyM: displayedAccuracyM,
                withinM: AlmanacLimits.fallbackRadiusM
            )
    }

    func load() async {
        let requestedCoordinate = coordinate
        let requestedAccuracy = accuracyM
        let requestedSelection = selection
        // **A fix too coarse to place the reader is not used to place the reader.** Handing it over
        // anyway is what produced F17: the read would search 400 m around a point the reader may be
        // two miles from and name whatever it found. `nil` here reaches `.empty` by contract, and
        // `needsAreaChoice` above is what tells the screen which empty this is.
        let fixForRead = AlmanacLimits.fixCanResolveAnArea(
            accuracyM: requestedAccuracy,
            withinM: AlmanacLimits.fallbackRadiusM
        ) ? requestedCoordinate : nil
        do {
            let city = try await api.city(near: fixForRead, in: requestedSelection)
            guard requestedCoordinate == coordinate, requestedSelection == selection else { return }
            phase = .loaded(city)
        } catch {
            guard requestedCoordinate == coordinate, requestedSelection == selection else { return }
            phase = .failed
        }
        displayedCoordinate = requestedCoordinate
        displayedAccuracyM = requestedAccuracy
        displayedSelection = requestedSelection
    }

    /// Take the selection the composition root holds *now* and re-read if it is a different one.
    func update(selection newValue: CitySelection) async {
        guard newValue != selection else { return }
        selection = newValue
        await load()
    }

    /// Take the fix the composition root has *now* and re-read if it is a different one. The phase
    /// is deliberately not reset to `.loading` — `AlmanacModel.update(coordinate:)`'s own reasoning.
    ///
    /// **Accuracy is compared too**, because a fix that stays put while its accuracy collapses from
    /// 8 m to 3,000 m is a change this screen has to react to: it is the difference between naming a
    /// city and admitting it cannot.
    func update(coordinate newValue: Coordinate?, accuracyM newAccuracy: Double? = nil) async {
        guard newValue != coordinate || newAccuracy != accuracyM || phase == .loading else { return }
        coordinate = newValue
        accuracyM = newAccuracy
        await load()
    }

    /// Re-reads after a failure. The load writes nothing, so a retry is free.
    func retry() async {
        phase = .loading
        await load()
    }
}
