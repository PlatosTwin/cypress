//
//  MovePinModel.swift
//  Cypress — Features/MovePin
//
//  The Move pin screen's one `@Observable` model (ARCHITECTURE §3). It holds where the pin is and
//  sends the move through `CypressAPI.correctLocation`, which writes it on this phone first and
//  queues it as a `location_correction` (`AppSchema` v23).
//

import Foundation
import Observation

@MainActor
@Observable
final class MovePinModel {

    let treeID: UUID
    /// Where the pin was when the screen opened. Every distance on the screen is measured from it.
    let original: Coordinate

    /// Where the pin is now: the center of the map.
    var pin: Coordinate
    private(set) var isSaving = false
    /// The last refusal, in words, until the pin moves again.
    var failure: String?
    /// Set once the move is written. The view hands control back to the profile.
    private(set) var didSave = false

    private let api: any CypressAPI

    init(treeID: UUID, original: Coordinate, api: any CypressAPI) {
        self.treeID = treeID
        self.original = original
        self.pin = original
        self.api = api
    }

    var presentation: MovePinPresentation {
        MovePinPresentation(original: original, pin: pin)
    }

    /// Save is offered only when there is a move to save and no save is in flight.
    var canSave: Bool { !presentation.isUnmoved && !isSaving }

    func save() async {
        guard canSave else { return }
        isSaving = true
        failure = nil
        defer { isSaving = false }
        do {
            // Placed by hand: the reader put the pin there, not the GPS. No accuracy, because no
            // instrument measured this position (D6 records an accuracy only for a fix).
            _ = try await api.correctLocation(
                treeID: treeID, to: pin, placement: .contributorPlaced, locationAccuracyM: nil
            )
            didSave = true
        } catch is ProximityConflict {
            didSave = true // RED-PROOF B
        } catch let error as APIError where error == .forbidden || error == .notFound {
            failure = MovePinCopy.notYours
        } catch {
            failure = MovePinCopy.failed
        }
    }
}
