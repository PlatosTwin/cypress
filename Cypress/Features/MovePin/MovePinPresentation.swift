//
//  MovePinPresentation.swift
//  Cypress — Features/MovePin
//
//  **NOT SPECIFIED.** No mock draws this screen. The owner approved a minimal Move pin control on
//  2026-11-12 as an exception to DECISIONS constraint 21: on the profile of a community tree the
//  reader added, a "Move pin" action opens a map centered on the tree, the reader moves the pin, and
//  then saves or cancels. Every string below is a draft the owner has yet to ratify.
//
//  ── No distance limit, because the service has none ───────────────────────────────────────────
//  The service's `location_correction` checks only that the position is on the map, that the
//  placement is one it knows, and that no other tree is within the 10 m dedupe radius
//  (`server/internal/api/sync.go`, `store.applyLocationCorrection`). It sets no bound on how far a
//  pin may move. This screen sets none either: the phone refuses what the service refuses, through
//  `LocalAPI.correctLocation`, and says so when it does.
//

import Foundation

/// The sentence above the map, from two coordinates: where the pin was when the screen opened, and
/// where it is now.
struct MovePinPresentation: Equatable {

    /// Meters from where the pin was to where it is.
    let distanceM: Double

    /// The pin has not moved far enough for the record to notice, so Save has nothing to save.
    let isUnmoved: Bool

    /// `The pin has not moved.` / `10 m north of where it was.`
    let placement: String

    init(original: Coordinate, pin: Coordinate) {
        let distance = pin.distance(to: original)
        self.distanceM = distance
        self.isUnmoved = distance < VisitPinAdjust.fixToleranceM
        self.placement = MovePinCopy.placement(distanceM: distance, from: original, to: pin)
    }
}

/// Every string the Move pin control draws. Drafts, for the owner to ratify.
enum MovePinCopy {

    /// The profile's action and the screen's title are the same words, for
    /// `VisitPinAdjustCopy.title`'s reason: the control and the screen it opens are one act.
    static let action = "Move pin"
    static let title = action

    /// The qualifier under the placement: the one rule the move is held to.
    static var rule: String {
        "Drag the map to put the pin on the tree. A pin cannot be within "
            + "\(Int(TreeDraft.proximityDedupeRadiusM)) m of another tree."
    }

    static let unmoved = "The pin has not moved."

    /// `10 m north of where it was.` Whole meters, for `VisitPinAdjustCopy.placement`'s reason.
    static func placement(distanceM: Double, from original: Coordinate, to pin: Coordinate) -> String {
        guard distanceM >= VisitPinAdjust.fixToleranceM else { return unmoved }
        let meters = Int(distanceM.rounded())
        let heading = VisitPinAdjustCopy.spelledOut(VisitBearing.compass(from: original, to: pin))
        return "\(meters) m \(heading) of where it was."
    }

    static let save = "Save"
    static let cancel = "Cancel"
    static let recenter = "Back to where it was"

    /// The 10 m dedupe refused the spot: the same rule the service applies.
    static var tooClose: String {
        "Another tree is recorded within \(Int(TreeDraft.proximityDedupeRadiusM)) m of that spot. "
            + "Move the pin farther from it."
    }

    /// `forbidden` or `notFound`: the tree is not this reader's to move, or it is gone.
    static let notYours = "This pin can no longer be moved from this phone."

    /// Anything else.
    static let failed = "The pin could not be moved. Try again."
}
