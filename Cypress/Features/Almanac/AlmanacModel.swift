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
    /// happening in your neighborhood" and "we could not ask" are different sentences, and this
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
    /// (ERRATA E155). It used to be a `let` set once, from a
    /// view whose `@State` initializer runs exactly once — so an almanac built before CoreLocation
    /// answered read `almanac(near: nil)`, got `.empty` by contract, and stayed empty for the life
    /// of the view.
    private(set) var coordinate: Coordinate?

    /// The fix that the state currently *on screen* was derived from — not necessarily the one the
    /// model has been handed since.
    ///
    /// The two differ for exactly as long as a re-read is in flight, and that gap is the reason this
    /// property exists rather than the view asking `coordinate == nil`. The prompt has to be
    /// withdrawn at the moment the neighborhood appears, not at the moment the fix arrives; those
    /// are one database read apart, and in between the screen has nothing on it and would be saying
    /// nothing about why (E126's invariant).
    private(set) var displayedCoordinate: Coordinate?

    /// How good the fix is, in meters (`MapLocationProvider.Availability.accuracyM`).
    ///
    /// **Carried because this screen's honesty depends on it and nothing used to read it.** The
    /// rule and the whole of the reasoning are in `AlmanacLimits.fixCanResolveAnArea(accuracyM:)`;
    /// the short version is that a fix good to ±3,000 m cannot pick out the tree 400 m away whose
    /// neighborhood this header prints, and it used to be allowed to try. `nil` in previews and
    /// tests driving a bare coordinate, which the rule permits and which leaves them unchanged.
    private(set) var accuracyM: Double?
    private(set) var displayedAccuracyM: Double?

    /// Which neighborhood this almanac is about: the reader's own, or one they chose
    /// (`AreaSelection`). `displayedSelection` is the one the picture on screen was read for, for
    /// `displayedCoordinate`'s reason.
    private(set) var selection: AreaSelection = .here
    private(set) var displayedSelection: AreaSelection = .here

    /// What the picker may offer — every neighborhood the live inventories carry, most trees first.
    /// Empty until `loadChoices()` has answered, and no picker is drawn while it is empty.
    private(set) var choices: [NeighborhoodChoice] = []

    private let now: @Sendable () -> Date

    /// The provider this model was built against (ERRATA E123's residual, #223).
    ///
    /// `nil` in every unit test and preview that drives the model with `update(coordinate:)`
    /// directly — the shape E155 already established, kept working unmodified below. Set only by
    /// the composition root's real wiring, where it is the same shared instance `RootView` starts
    /// and stops (ARCHITECTURE §3).
    private let location: MapLocationProvider?

    /// How often `observeLocation()` checks `location.availability` for a fix boundary.
    ///
    /// A poll, deliberately, the same shape `VisitIdentifyModel.run()` already uses to follow a
    /// location provider for the life of a screen — and for the same reason that shape was chosen
    /// over `withObservationTracking`'s continuation recipe: a continuation left unresumed when the
    /// owning `Task` is cancelled does not resume itself, so a change that never arrives again after
    /// the screen goes away would leak the wait (and everything it closed over) rather than end it.
    /// `Task.sleep` has no such failure mode — cancellation throws through it immediately, which is
    /// what lets this loop's own `while !Task.isCancelled` actually be the thing that stops it.
    /// Injectable so a test can wait milliseconds instead of half a second.
    private let locationPollInterval: Duration

    init(
        api: any CypressAPI,
        coordinate: Coordinate?,
        accuracyM: Double? = nil,
        location: MapLocationProvider? = nil,
        locationPollInterval: Duration = .milliseconds(500),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.api = api
        self.coordinate = coordinate
        self.displayedCoordinate = coordinate
        self.accuracyM = accuracyM
        self.displayedAccuracyM = accuracyM
        self.location = location
        self.locationPollInterval = locationPollInterval
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
    ///
    /// Asked only of `.here`: a reader who chose a neighborhood is not waiting on a fix.
    var needsLocation: Bool { displayedSelection.isHere && displayedCoordinate == nil }

    /// Whether the screen is empty because the fix, though present, is too coarse to say which
    /// neighborhood the reader is in — `AlmanacLimits.fixCanResolveAnArea(accuracyM:)`, tester
    /// report F17.
    ///
    /// **Deliberately not folded into `needsLocation`.** Location is granted and a fix has arrived;
    /// there is nothing to turn on, and a prompt saying otherwise would be the screen's second lie
    /// on top of the one this fixes. What there is, is a choice to make.
    var needsAreaChoice: Bool {
        displayedSelection.isHere
            && displayedCoordinate != nil
            && !AlmanacLimits.fixCanResolveAnArea(accuracyM: displayedAccuracyM)
    }

    func load() async {
        let requestedCoordinate = coordinate
        let requestedAccuracy = accuracyM
        let requestedSelection = selection
        // **A fix too coarse to place the reader is not used to place the reader** (F17). Handed
        // over anyway, the read searches 400 m around a point the reader may be two miles from and
        // names whatever it finds, in a header that states it as fact. `nil` reaches `.empty` by
        // contract and `needsAreaChoice` above tells the screen which empty this is.
        let fixForRead = AlmanacLimits.fixCanResolveAnArea(accuracyM: requestedAccuracy)
            ? requestedCoordinate : nil
        do {
            let almanac = try await api.almanac(near: fixForRead, in: requestedSelection)
            // A newer fix arrived while this read was in flight; its own read is authoritative and
            // this one's answer is about a place the reader has already left.
            guard requestedCoordinate == coordinate, requestedSelection == selection else { return }
            phase = .loaded(almanac)
        } catch {
            guard requestedCoordinate == coordinate, requestedSelection == selection else { return }
            phase = .failed
        }
        displayedCoordinate = requestedCoordinate
        displayedAccuracyM = requestedAccuracy
        displayedSelection = requestedSelection
    }

    /// Reads what the picker may offer, once per screen.
    ///
    /// A failure costs the reader the button, not the page, so it is swallowed to an empty list
    /// rather than routed into `Phase.failed` — the stats are what the screen is for.
    func loadChoices() async {
        choices = ((try? await api.areaChoices()) ?? .none).neighborhoods
    }

    /// The reader picked a neighborhood, or picked their own back.
    func choose(_ newValue: AreaSelection) async {
        guard newValue != selection else { return }
        selection = newValue
        await load()
    }

    /// Take the fix the composition root has *now* and re-read if it is a different one.
    ///
    /// Called from `AlmanacView`'s `.task(id:)`, so it runs once on mount and again on every change
    /// — including the one that matters, `nil` → a coordinate, a second or so after a cold launch.
    /// The phase is deliberately **not** reset to `.loading` here: the almanac already on screen
    /// (empty, with the prompt over it, or a previous neighborhood) stays until the replacement has
    /// actually been read, so the re-read costs the reader no blank frame.
    ///
    /// **Accuracy is compared too**: a fix that stays put while its accuracy collapses from 8 m to
    /// 3,000 m is the difference between naming a neighborhood and admitting we cannot.
    func update(coordinate newValue: Coordinate?, accuracyM newAccuracy: Double? = nil) async {
        guard newValue != coordinate || newAccuracy != accuracyM || phase == .loading else { return }
        coordinate = newValue
        accuracyM = newAccuracy
        await load()
    }

    /// Re-reads after a failure. The load writes nothing, so a retry is free — the same reason
    /// `ShareModel.retry` and `SpeciesModel.retry` can offer one (ERRATA E126).
    func retry() async {
        phase = .loading
        await load()
    }

    // MARK: - Following the shared provider (ERRATA E123's residual, #223)

    /// Whether the change from `previous` to `current` is a fix boundary being crossed, in either
    /// direction — the only change this screen reloads for.
    ///
    /// Pure and `static`, mirroring `MapLocationProvider.isWorthPublishing`'s own shape and for the
    /// same reason its doc comment gives: the rule can be tested at its boundary without a running
    /// `MapLocationProvider`, and the wiring that actually calls it is tested separately
    /// (`observeLocation` below), because a predicate that is right and never called is exactly the
    /// defect this entry exists to catch.
    ///
    /// **Deliberately blind to which fix, only to whether there is one.** `MapLocationProvider`
    /// rewrites `availability` on every publish worth making — walking, five meters at a time
    /// (`MapLocationProvider.publishDistanceM`) — and a screen 12 that reloaded on each of those
    /// would re-read the whole almanac once per five meters of walking, the exact "per tick" churn
    /// this entry's ticket forbids. `.located(A) → .located(B)` is therefore `false` here, on
    /// purpose, even though `A != B`: neither side is a fix the reader did not already have.
    /// `.located → .notAsked/.denied/.servicesOff/.waitingForFix` is `true` for the reverse reason —
    /// that is E126's invariant reappearing in the other direction, and `update(coordinate:)` below
    /// already knows what to do with a `nil` coordinate.
    /// **Two boundaries, not one, since the F17 fix.** The second is whether the fix is accurate
    /// enough to name an area at all (`AlmanacLimits.fixCanResolveAnArea(accuracyM:)`). It has to be
    /// here rather than nowhere: `MapLocationProvider` rewrites `availability` on every publish, and
    /// with only the first clause a reader whose first fix was approximate and who then turned
    /// Precise Location on would sit in the "pick an area" state for the life of the screen, being
    /// told we cannot tell where they are by an app that now can.
    ///
    /// It costs nothing of the churn rule above. Both sides of a walking-pace `.located(A) →
    /// .located(B)` are precise fixes, so the second clause is `true != true` and the whole
    /// predicate is still `false` — which is the property the paragraph above is protecting and the
    /// one `AlmanacLocationTransitionTests` pins.
    static func isFixAvailabilityTransition(
        from previous: MapLocationProvider.Availability,
        to current: MapLocationProvider.Availability
    ) -> Bool {
        if (previous.coordinate == nil) != (current.coordinate == nil) { return true }
        return AlmanacLimits.fixCanResolveAnArea(accuracyM: previous.accuracyM)
            != AlmanacLimits.fixCanResolveAnArea(accuracyM: current.accuracyM)
    }

    /// Watches `location` for the life of the screen and reloads on the one change that matters.
    ///
    /// Replaces `AlmanacView`'s old `.task(id: coordinate)` as the reload trigger whenever a live
    /// provider is supplied — that task keyed on the coordinate itself, which is what made E155's
    /// fix over-correct: the almanac reloaded once per published fix rather than once per grant.
    /// This performs the mount-time read itself (whatever `location.availability` already is, which
    /// on a cold launch is `nil` and on a screen reached after the map already has a fix is not),
    /// then reloads again only when `isFixAvailabilityTransition` says the fix boundary moved.
    ///
    /// A no-op when `location` is `nil` — every unit test and preview that drives the model with
    /// `update(coordinate:)` directly is unaffected, and `AlmanacView` falls back to its original
    /// `.task(id: coordinate)` for exactly those callers.
    func observeLocation() async {
        guard let location else { return }
        var previous = location.availability
        await update(coordinate: previous.coordinate, accuracyM: previous.accuracyM)
        while !Task.isCancelled {
            try? await Task.sleep(for: locationPollInterval)
            guard !Task.isCancelled else { return }
            let current = location.availability
            if Self.isFixAvailabilityTransition(from: previous, to: current) {
                await update(coordinate: current.coordinate, accuracyM: current.accuracyM)
            }
            previous = current
        }
    }
}
