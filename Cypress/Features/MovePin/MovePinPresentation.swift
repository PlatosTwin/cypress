//
//  MovePinPresentation.swift
//  Cypress — Features/MovePin
//
//  **NOT SPECIFIED.** No mock draws this screen. The owner approved a minimal Move pin control on
//  2026-11-12 as an exception to DECISIONS constraint 21: on the profile of a community tree the
//  reader added, a "Move pin" action opens a map centered on the tree, the reader moves the pin, and
//  then saves or cancels. The owner kept these strings as drafted on 2026-11-14, except the two that
//  stated the 10 m rule, which went with the rule.
//
//  ── No distance limit, and no 10 m rule ───────────────────────────────────────────────────────
//  The owner's answers of 2026-11-14: a pin "can go anywhere, and also fine to go within 10m of
//  another tree". So this screen sets no bound on how far a pin may move and says nothing about
//  trees nearby. `LocalAPI.correctLocation` still refuses a position off the map and a tree that is
//  not this reader's, and the screen says so when it does.
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

    /// The qualifier under the placement: how to move the pin.
    static let rule = "Drag the map to put the pin on the tree."

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

    /// `forbidden` or `notFound`: the tree is not this reader's to move, or it is gone.
    static let notYours = "This pin can no longer be moved from this phone."

    /// Anything else.
    static let failed = "The pin could not be moved. Try again."
}
