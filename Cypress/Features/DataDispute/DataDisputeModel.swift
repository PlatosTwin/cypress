//
//  DataDisputeModel.swift
//  Cypress — Features/DataDispute
//
//  The data-dispute screen's one `@Observable` model (ARCHITECTURE §3). It talks to `CypressAPI`
//  and to nothing else; the location arrives as `MapLocationProvider.Availability` values the view
//  hands over, so the model can be driven by a test without a provider at all.
//

import Foundation
import Observation

@MainActor
@Observable
final class DataDisputeModel {

    var draft = DataDisputeDraft()

    /// The sentence above the button: a refusal, a failed raise, or nothing.
    ///
    /// Cleared by every edit, because a sentence about the draft the reporter has since changed is a
    /// sentence about a draft that no longer exists.
    private(set) var problem: String?

    /// While a raise is in flight. The button ignores a second tap rather than raising twice; the
    /// store would refuse the second as a `conflict` anyway, and the reporter would read a sentence
    /// telling them they already have a report they are in the middle of sending.
    private(set) var isRaising = false

    /// Set once the dispute is written. The view watches it and returns to the profile, which
    /// re-reads itself on reappearing and draws the "you reported" state from the store.
    private(set) var didRaise = false

    /// Whether the species picker is up.
    var isChoosingSpecies = false

    let treeID: UUID
    private let api: any CypressAPI
    private let currentYear: Int

    init(
        treeID: UUID,
        api: any CypressAPI,
        currentYear: Int = Calendar.current.component(.year, from: Date())
    ) {
        self.treeID = treeID
        self.api = api
        self.currentYear = currentYear
    }

    /// What will be sent, for the view to restate what it holds.
    var suggestions: TreeDataDispute.Suggestions { draft.suggestions(currentYear: currentYear) }

    /// Whether the year field holds something this screen will refuse. Drawn under the field as
    /// soon as it is true, not only after a tap on the button.
    var plantedYearIsInvalid: Bool { draft.plantedYear(currentYear: currentYear) == .invalid }

    // MARK: - Editing

    func toggle(_ choice: DataDisputeChoice) {
        if draft.choices.contains(choice) {
            draft.choices.remove(choice)
        } else {
            draft.choices.insert(choice)
        }
        problem = nil
    }

    /// The reporter tapped "use my current location".
    ///
    /// Answers the provider's state as it is right now; `waiting` is resolved by `locationChanged`
    /// when the provider publishes. The view starts the provider — the model has none.
    func useLocation(_ availability: MapLocationProvider.Availability) {
        draft.location = .reading(availability)
        problem = nil
    }

    /// The provider published. Only a block that is waiting takes it: a fix the reporter already
    /// accepted is theirs until they ask again, so a later, different fix cannot quietly replace the
    /// position they were standing at when they tapped.
    func locationChanged(_ availability: MapLocationProvider.Availability) {
        guard draft.location == .waiting else { return }
        draft.location = .reading(availability)
    }

    func chooseSpecies(_ species: Species) {
        draft.species = species
        isChoosingSpecies = false
        problem = nil
    }

    func cancelChoosingSpecies() {
        isChoosingSpecies = false
    }

    func editedText() {
        problem = nil
    }

    // MARK: - Sending

    func raise() async {
        guard !isRaising, !didRaise else { return }
        if let problem = draft.problem(currentYear: currentYear) {
            self.problem = problem
            return
        }
        isRaising = true
        defer { isRaising = false }
        do {
            _ = try await api.raiseDataDispute(
                treeID: treeID,
                issues: draft.issues,
                suggestions: suggestions,
                notes: draft.trimmedNotes
            )
            problem = nil
            didRaise = true
        } catch let error as APIError {
            problem = DataDisputeCopy.raiseFailure(error)
        } catch {
            problem = DataDisputeCopy.raiseFailure(.serverError)
        }
    }
}
