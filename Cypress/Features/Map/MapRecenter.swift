//
//  MapRecentre.swift
//  Cypress — Features/Map
//
//  What screen 01's "take me back to me" control does, and the words it says.
//
//  ── NOT SPECIFIED ────────────────────────────────────────────────────────────────────────────────
//  SCREENS.md 01 draws the GPS dot and no control for it; its own **NOT SPECIFIED** list covers the
//  map's zoom controls, and this is one of them by any reading. So the control is designed here under
//  ARCHITECTURE §8 rule 8, and this file is the reasoning rather than a stray comment on a view.
//
//  The defect it closes is small and constant: the map opens on the user, one pan later the dot is
//  off screen, and the only way back is to remember the street. Every other map the reader has ever
//  used has this button, which is also why its absence is felt rather than noticed.
//
//  ── Why not `MapUserLocationButton` ──────────────────────────────────────────────────────────────
//  MapKit ships the control, it handles its own tracking modes, and it was the first thing tried. It
//  is not usable here, for four reasons in ascending order of how much they matter:
//
//  1. **It can only be placed by MapKit.** `MapUserLocationButton` is a `MapControl`; it goes inside
//     `.mapControls { }` and MapKit positions it against the map's own safe area. Screen 01's map
//     *ignores* the safe area — the frame is full-bleed by spec, "content is absolutely positioned
//     below the notch" — and every piece of chrome on it is placed by arithmetic against an inset
//     measured once at the root. ERRATA E110 is the record of how delicate that arithmetic is: with a
//     navigation bar present the same inset read **0** and the search bar landed 8pt below the wrong
//     edge. A control this screen cannot position is a control that will sit under the search bar or
//     behind the tab bar, and there is no modifier that moves it.
//  2. **It drives a camera mode this screen does not have.** The button switches
//     `MapCameraPosition` to `.userLocation(followsHeading:fallback:)`, a *following* camera. Screen
//     01's camera is a plain region that `MapModel.cameraDidChange` reads to bound every database
//     read; a follow mode re-aims it on every fix, which is a camera change every 5 m of walking —
//     the pin-budget work (ERRATA E130) went to some trouble to make camera changes cheap, and this
//     would spend that back on a mode nothing else on the screen asks for.
//  3. **It reads a different location than the map draws.** The GPS dot on 01 is one of *our*
//     annotations, fed by `MapLocationProvider`, whose accuracy is load-bearing for screen 02.
//     `MapUserLocationButton` follows MapKit's own manager and expects a `UserAnnotation`. Two
//     managers, two answers, and the button could aim at a fix the dot is not drawn at.
//  4. **It has nothing to say when it cannot work, and that is the whole ask.** With permission
//     denied the system control is simply inert: press it, and the map does not move and nothing
//     appears. That is exactly the defect class being reported all week. Its behaviour is not
//     configurable, and there is no callback to hang an explanation off.
//
//  So the control is ours, it lives in the chrome overlay with the FAB where this screen's own
//  arithmetic can place it, and every state it can be in answers the press.
//
//  ── What a press does about the zoom ─────────────────────────────────────────────────────────────
//  **First press centres and keeps the zoom. A press that is already centred zooms in to the
//  screen's own opening scale.**
//
//  The alternative — always snapping to the opening 120 m — is the obnoxious one, and it is obnoxious
//  for a specific reason rather than an aesthetic one. Somebody looking at the Mission at
//  neighbourhood scale who presses this button is asking *where am I in what I am looking at*; an
//  answer that throws the neighbourhood away and replaces it with one intersection has not answered
//  that question, it has asked a different one. Keeping the span answers the question actually asked
//  and is the same rule `VisitPinAdjustView.move(to:)` already follows when it recentres its pin: the
//  span is whatever the reader last zoomed to.
//
//  But "closer" is the only question left once the dot is under the crosshair, so the second press
//  asks it, and the scale it goes to is `MapLayout.defaultSpanMetres` — 120 m, the scale ERRATA E12
//  measured as the one where San Francisco's street trees stop fusing into a mat. There is no third
//  step: past 120 m the pins are individually tappable and the reader has a pinch.
//
//  The step is skipped when the camera is already inside 1.5 × the opening span, because "zoom in"
//  must never quietly zoom *out* on somebody who has pinched closer than 120 m.
//

import Foundation

/// The decision behind screen 01's recentre control: given what the app knows about the user and
/// where the camera is, what should a press do?
///
/// Pure, and deliberately free of MapKit and SwiftUI, so the whole of it can be asserted in
/// `CypressTests/MapRecentreTests` without a camera or a view.
enum MapRecenter {

    /// Where the camera is, in the terms this decision needs. Degrees, because that is what
    /// `MKCoordinateRegion` carries and converting to metres to compare a fraction of a span to
    /// itself would only add a rounding.
    struct Camera: Equatable {
        var center: Coordinate
        var latitudeSpan: Double
        var longitudeSpan: Double

        init(center: Coordinate, latitudeSpan: Double, longitudeSpan: Double) {
            self.center = center
            self.latitudeSpan = latitudeSpan
            self.longitudeSpan = longitudeSpan
        }

        /// Whether the dot is close enough to the middle that "centre me" has nothing left to do.
        ///
        /// A fraction of the visible span rather than a distance in metres, because the question is
        /// about the picture and not about the ground: 20 m off centre is dead centre on a city-wide
        /// camera and half a screen away at 120 m. `centredFraction` is 5 % of the span on each axis,
        /// which on this phone is about 20 pt across and 44 pt down — less than a fingertip of drift,
        /// so a reader who nudged the map by accident still counts as centred and gets the zoom step
        /// they were reaching for.
        ///
        /// A zero span is the camera before MapKit has settled once. It is not centred on anything.
        func isCentered(on coordinate: Coordinate) -> Bool {
            guard latitudeSpan > 0, longitudeSpan > 0 else { return false }
            return abs(center.latitude - coordinate.latitude) <= latitudeSpan * MapRecenter.centeredFraction
                && abs(center.longitude - coordinate.longitude) <= longitudeSpan * MapRecenter.centeredFraction
        }

        /// Roughly how much ground the short edge of the camera covers. Latitude only: a degree of
        /// latitude is 111.32 km everywhere, and this number is compared against a threshold with a
        /// 50 % margin on it, so the longitude convergence San Francisco does not need is not worth
        /// the cosine.
        var metersAcross: Double { latitudeSpan * MapRecenter.metersPerDegreeLatitude }
    }

    /// What the press means. Every case is something the reader can see happen — that is the point of
    /// the type, and the reason the two states that cannot move the camera are cases here rather than
    /// an early `return` in the view.
    enum Press: Equatable {
        /// Nobody has been asked yet. The press asks, and the system sheet is the visible answer.
        case ask
        /// Asked and refused. The press cannot move the camera and must say why.
        case explainRefusal
        /// Permission granted, no fix yet. The press says so, and the map moves when one lands.
        case waitForFix
        /// Move the camera to the user, keeping whatever span the reader is looking at.
        case center(Coordinate)
        /// Already centred and looking at more than one intersection: go to the opening scale.
        case centerAndZoomIn(Coordinate)
    }

    /// How the control draws itself, which is a continuous answer rather than a reaction to a press.
    ///
    /// **Five cases, and it used to be three (#100).** `away` carried all of "I know where you are
    /// and the map is not there", "nobody has answered the permission ask" and "I am still looking",
    /// and `MapRecentreCopy.value` spoke one word — `Not centred` — over all three. For a sighted
    /// reader that word is a caption on a picture they can also see. For a VoiceOver reader it is the
    /// *entire* report on where the map is, and in two of the three states it is not merely thin, it
    /// is wrong: there is no "centred" to be short of, because the app does not know where the reader
    /// is and pressing the control will not move the camera at all.
    ///
    /// That is ERRATA E126's rule — a screen showing something other than what you asked for must say
    /// why — arriving at the one control whose whole reason for existing is that no press is ever
    /// silent. A control that cannot move the camera has to say so *before* it is pressed, not only
    /// after.
    enum Engagement: Equatable {
        /// There is a fix and the camera is on it.
        case centered
        /// There is a fix, and it is somewhere other than the middle of the map. A press moves it.
        case away
        /// Nobody has answered the permission ask. A press asks.
        case askable
        /// Permission granted, no fix yet. A press promises the move and keeps the promise.
        case searching
        /// Refused, or Location Services off. Pressing explains rather than moving anything.
        case unavailable
    }

    /// 5 % of the visible span on each axis. See `Camera.isCentred(on:)`.
    static let centeredFraction: Double = 0.05

    /// One degree of latitude, in metres. WGS-84's mean; the meridian is 20,003.93 km / 180°.
    static let metersPerDegreeLatitude: Double = 111_320

    /// How much wider than the opening scale the camera has to be before a second press is allowed to
    /// zoom in. Half again: inside that the step is a few points of movement and the risk on the
    /// other side is a "zoom in" that pulls a closely-pinched camera back out.
    static let zoomInThreshold: Double = 1.5

    /// The whole decision.
    static func press(availability: MapLocationProvider.Availability, camera: Camera) -> Press {
        switch availability {
        case .notAsked:
            return .ask
        case .denied, .servicesOff:
            return .explainRefusal
        case .waitingForFix:
            return .waitForFix
        case let .located(coordinate, _):
            guard camera.isCentered(on: coordinate) else { return .center(coordinate) }
            guard camera.metersAcross > MapLayout.defaultSpanMeters * zoomInThreshold else {
                // Centred and already close. The press is honoured — the camera is driven to the
                // fix, which is where it very nearly is — rather than being swallowed.
                return .center(coordinate)
            }
            return .centerAndZoomIn(coordinate)
        }
    }

    /// What the button draws, before anybody presses it.
    ///
    /// It answers the same five-way question `press(availability:camera:)` does, and deliberately
    /// mirrors its shape: every state in which a press produces something different is a state the
    /// control reports differently, which is what makes the spoken value a prediction of the press
    /// rather than a decoration on it.
    ///
    /// **`askable` and `searching` are still not drawn struck through.** That is unchanged from when
    /// they were both `away`, and it is still right: pressing in either state is a reasonable thing
    /// to do and gets a real answer, so the *picture* must not tell the reader not to bother. Only
    /// the words got more precise — see `Engagement` and #100.
    static func engagement(availability: MapLocationProvider.Availability, camera: Camera) -> Engagement {
        switch availability {
        case .notAsked:
            return .askable
        case .waitingForFix:
            return .searching
        case .denied, .servicesOff:
            return .unavailable
        case let .located(coordinate, _):
            return camera.isCentered(on: coordinate) ? .centered : .away
        }
    }
}

// MARK: - The words

/// Screen 01's recentre control, spoken and written.
///
/// Out of the view for the reason every other `*Copy` in this app is: the sentence a state produces
/// is a decision worth a test, and a test should not have to render a `View` to read it.
enum MapRecenterCopy {

    /// The control's accessibility label. It says what the control *does*, not what it looks like —
    /// "Locate" names a picture, and a reader who cannot see the picture learns nothing from it.
    ///
    /// American spelling, at the owner's instruction (#140): every user-visible string in this
    /// app is American, and `BritishSpellingGuardTests` holds the line.
    static let label = "Center the map on you"

    /// The state, spoken. `accessibilityValue` rather than a second label, so VoiceOver reads
    /// "Center the map on you, centered on you" — the control, then what it is currently doing.
    ///
    /// **Five sentences for five states (#100).** `Not centered` is kept for the one state it was ever
    /// true of — there is a fix, and the map is not on it — and the two states it used to be borrowed
    /// for now say what is actually the case. Neither of them is a degree of "centred": in both, the
    /// app does not know where the reader is, so there is nothing to be off-centre from.
    static func value(_ engagement: MapRecenter.Engagement) -> String {
        switch engagement {
        case .centered: return "Centered on you"
        case .away: return "Not centered"
        case .askable: return "Cypress has not been given your location"
        case .searching: return "Finding you"
        case .unavailable: return "Location is off"
        }
    }

    /// What the next press will do, when that is not obvious from the value.
    ///
    /// `away` is the one state with nothing to add: the label already says the control centres the
    /// map on you and the value says it is not centred, so a hint would be the same sentence a third
    /// time. The other four each promise something the label does not — a zoom, a permission sheet, a
    /// held press, an explanation.
    static func hint(_ engagement: MapRecenter.Engagement) -> String? {
        switch engagement {
        case .centered: return "Zooms in to street level"
        case .away: return nil
        case .askable: return "Asks for permission to use your location"
        case .searching: return "The map moves to you as soon as a first fix arrives"
        case .unavailable: return "Explains why the map cannot find you"
        }
    }

    /// Said out loud after a press that moved the camera.
    ///
    /// The map has changed under a VoiceOver reader's finger and nothing else reports it — the same
    /// argument `VisitPinAdjustView.speak(_:)` makes for the nudge pad. Focus stays on the button, so
    /// the reader can press again and hear the second step.
    static let spokenCentered = "The map is on you."
    static let spokenZoomedIn = "The map is on you, at street level."

    // MARK: The two presses that cannot move the camera

    /// Granted, but CoreLocation has not produced a fix yet.
    ///
    /// It states the promise as well as the state, because the promise is kept: the press is
    /// remembered and the first fix to arrive centres the map.
    static let waitingTitle = "Finding you"
    static let waitingMessage =
        "Cypress has permission and is waiting for the first fix. The map will move to you as soon "
        + "as one arrives."

    /// Refused.
    ///
    /// The shape of the sentence is `VisitAddTreeCopy.noLocationDenied`'s — name the limit, say what
    /// it costs *here*, then the one thing that undoes it — and the middle clause is different
    /// because the situation is. There a tree could not be added, because a tree is a place; here
    /// there is simply nowhere to put the camera.
    static func refusalTitle(_ availability: MapLocationProvider.Availability) -> String {
        availability == .servicesOff ? "Location Services are off" : "Location is off"
    }

    static let refusalMessage =
        "Cypress cannot see where you are, so there is nowhere to center the map. Turn location on "
        + "in Settings, or pan to the street you want."
}
