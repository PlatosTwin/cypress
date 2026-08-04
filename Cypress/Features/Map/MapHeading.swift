//
//  MapHeading.swift
//  Cypress — Features/Map
//
//  Task #155: the reader's dot says where they are; this is the arithmetic that lets it also say
//  which way they are facing.
//
//  **Everything here is pure and takes doubles**, because none of it can be exercised any other way.
//  No simulator produces a heading — `simctl` can set a location and cannot set a magnetometer — so
//  the only parts of this feature a machine in this repo can judge are the rules below and the
//  wiring that calls them. What the cone actually points at on a street is device-only truth, and
//  this file being green says nothing about it.
//
//  Degrees throughout, clockwise from north, which is CoreLocation's own convention and MapKit's.
//

import Foundation

enum MapHeading {

    static let fullTurn: Double = 360

    /// How far the reader has to have turned before `MapLocationProvider` rewrites its heading.
    ///
    /// The same shape of gate as `MapLocationProvider.publishDistanceM`, and for the same measured
    /// reason: the provider is `@Observable` and screen 01 reads it, so every write re-runs that
    /// screen's view tree (ERRATA E139). A magnetometer reports far faster than a person turns, and
    /// an ungated heading would be the churn E139 is about arriving down a second channel.
    ///
    /// Five degrees is also handed to `CLLocationManager.headingFilter`, so CoreLocation is asked
    /// for the same thing first. It is asked *and* enforced here because this project has measured
    /// `distanceFilter` not being honored on a device — see `MapLocationProvider.publishDistanceM`,
    /// where a filter of five meters delivered a fix every fifteen centimeters. Whether
    /// `headingFilter` keeps its promise better is not something a simulator can tell us.
    ///
    /// At the drawn cone's size, five degrees is under a point of movement at its widest — below
    /// what a reader can see, and far above the jitter of a phone held in a hand.
    static let publishDegrees: Double = 5

    /// Any angle, brought into `0 ..< 360`.
    static func normalized(_ degrees: Double) -> Double {
        guard degrees.isFinite else { return 0 }
        let wrapped = degrees.truncatingRemainder(dividingBy: fullTurn)
        return wrapped < 0 ? wrapped + fullTurn : wrapped
    }

    /// The heading to draw, or `nil` for "do not draw one".
    ///
    /// **`nil` is the whole decision this app has taken about a bad magnetometer: degrade to the
    /// bare dot, never draw a wrong direction.** `CLHeading.headingAccuracy` is documented to go
    /// negative when the reading cannot be trusted — near a car, a speaker magnet, a laptop — and a
    /// cone pointing confidently the wrong way is worse than no cone in an app whose premise is
    /// standing in front of one specific tree. There is no permission state to fall back to and
    /// nothing to ask the reader for; the honest answer is silence.
    ///
    /// **True north only.** `magneticHeading` is not used as a fallback, because the basemap is
    /// drawn against true north and San Francisco's declination is about 13° — a cone that is
    /// quietly a hand's width off is exactly the confident wrong answer the rule above refuses.
    /// Apple documents `trueHeading` as negative until location updates are running, and this
    /// provider starts both together; the dot the cone attaches to needs a fix to exist at all.
    static func usable(trueHeading: Double, accuracyDegrees: Double) -> Double? {
        guard accuracyDegrees.isFinite, accuracyDegrees >= 0 else { return nil }
        guard trueHeading.isFinite, trueHeading >= 0 else { return nil }
        return normalized(trueHeading)
    }

    /// The short way round, in `-180 ..< 180` plus the half-turn itself.
    ///
    /// **This is the difference between a cone that turns with the reader and one that spins the
    /// long way round the compass.** A reader walking north-north-west crosses 0° constantly, and
    /// 359° to 1° is two degrees of turn, not three hundred and fifty-eight. Subtraction alone gets
    /// that wrong, and it gets it wrong in the most visible possible way — a full backwards
    /// rotation of the cone every time the reader wobbles past north.
    static func shortestDelta(from: Double, to: Double) -> Double {
        let delta = normalized(to) - normalized(from)
        if delta > fullTurn / 2 { return delta - fullTurn }
        if delta <= -fullTurn / 2 { return delta + fullTurn }
        return delta
    }

    /// Whether a heading says anything the last published one did not.
    ///
    /// Wrap-aware through `shortestDelta`, which is not a nicety: a reader facing north produces
    /// readings either side of 0°, and a naive comparison would call 359° → 1° a 358° turn and
    /// publish every one of them — the churn this gate exists to stop, at the one heading a reader
    /// standing on a north–south street holds most.
    static func isWorthPublishing(_ next: Double, over previous: Double?) -> Bool {
        guard let previous else { return true }
        return abs(shortestDelta(from: previous, to: next)) >= publishDegrees
    }

    /// Where the cone points **on the glass**, given where the map is pointing.
    ///
    /// `MapAnnotationLayer` leaves `isRotateEnabled` on, so the reader can turn the basemap under
    /// their own dot. An `MKAnnotationView` does not rotate with the map — it stays square to the
    /// screen — so a cone drawn at the raw compass heading would be right only while the map
    /// happens to be north-up, and would silently lie the moment the reader twisted it. Subtracting
    /// the camera's own heading is what keeps the cone pointing at the same piece of the world.
    static func screenAngleDegrees(heading: Double, cameraHeading: Double) -> Double {
        normalized(heading - cameraHeading)
    }

    /// Degrees to radians, for the one caller that rotates a layer.
    static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
}
