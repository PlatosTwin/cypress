//
//  VisitIdentifyModel.swift
//  Cypress — Features/Visit
//
//  Screen 02's state. One `@Observable` per feature folder's screen, owned by the view (§3).
//

import Foundation
import Observation

@MainActor
@Observable
final class VisitIdentifyModel {

    private let api: any CypressAPI
    let location: VisitLocationProvider

    private(set) var shortlist: VisitShortlist = .empty
    private(set) var isLoading = true
    /// A load that threw. Rendered as a line, never as a dialog — the footer's "add this tree"
    /// still works and is the honest way out.
    private(set) var loadError: String?

    /// D6: in the ambiguous case a tap **selects**; a second, explicit tap on the confirm button is
    /// what commits. `nil` means nothing is chosen yet.
    var selectedID: UUID?

    /// The fix the currently-displayed shortlist was built from. Re-querying on every one-meter
    /// update would re-sort the list under the user's thumb.
    private var lastQueriedCoordinate: Coordinate?
    /// Far enough that the ranking can genuinely change; short enough that stepping to the next
    /// tree refreshes it.
    private let requeryDistanceM: Double = 5

    init(api: any CypressAPI, location: VisitLocationProvider) {
        self.api = api
        self.location = location
    }

    // MARK: - Derived

    var origin: Coordinate? { location.fix.coordinate }

    /// The candidate a tap would commit to, if any.
    var selectedCandidate: VisitCandidate? {
        guard let selectedID else { return nil }
        return shortlist.candidates.first { $0.id == selectedID }
    }

    /// The card drawn in the "selected" treatment — the auto-highlighted top candidate, or whatever
    /// the user actually tapped.
    var highlightedID: UUID? {
        if let selectedID { return selectedID }
        return shortlist.highlightsTopCandidate ? shortlist.candidates.first?.id : nil
    }

    /// D6's pair: the two nearest, shown side by side with a distinguishing trait each.
    var confirmationPair: (first: VisitCandidate, second: VisitCandidate)? {
        guard shortlist.requiresConfirmation, shortlist.candidates.count >= 2 else { return nil }
        return (shortlist.candidates[0], shortlist.candidates[1])
    }

    var distinguishingTraits: (first: VisitDistinguishingTrait, second: VisitDistinguishingTrait)? {
        guard let pair = confirmationPair else { return nil }
        return VisitDistinguisher.traits(pair.first, pair.second)
    }

    /// `GPS ±9 m`, the status chip. `nil` when there is no fix to describe.
    var gpsChipLabel: String? {
        guard let accuracy = shortlist.accuracyM ?? location.fix.accuracyM else { return nil }
        return "GPS ±\(Int(accuracy.rounded())) m"
    }

    /// Verbatim from SCREENS 02's second status chip.
    var confirmChipLabel: String? {
        shortlist.requiresConfirmation && shortlist.candidates.count >= 2
            ? "Two trees in range · confirm by eye"
            : nil
    }

    // MARK: - Loading

    /// Follows the fix for as long as the screen is on screen.
    func run() async {
        location.start()
        while !Task.isCancelled {
            await refreshIfNeeded()
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    private func refreshIfNeeded() async {
        switch location.fix {
        case .denied:
            isLoading = false
            shortlist = .empty
        case .pending:
            break
        case let .located(coordinate, accuracy):
            let moved = lastQueriedCoordinate.map { $0.distance(to: coordinate) >= requeryDistanceM } ?? true
            guard moved else {
                // Accuracy can change without the position moving — an error circle that shrinks
                // below the threshold turns a low-GPS screen into a ranked one, with no new query.
                if shortlist.accuracyM != accuracy, !shortlist.candidates.isEmpty {
                    shortlist = VisitShortlist.rank(shortlist.candidates.map(\.nearby), accuracyM: accuracy)
                }
                return
            }
            lastQueriedCoordinate = coordinate
            await load(at: coordinate, accuracyM: accuracy)
        }
    }

    private func load(at coordinate: Coordinate, accuracyM: Double) async {
        do {
            let rows = try await api.treesNear(
                coordinate,
                radiusM: VisitShortlist.searchRadiusM,
                limit: VisitShortlist.maximumCandidates
            )
            shortlist = VisitShortlist.rank(rows, accuracyM: accuracyM)
            loadError = nil
            // A re-rank must not silently keep a selection that is no longer on the list.
            if let selectedID, !shortlist.candidates.contains(where: { $0.id == selectedID }) {
                self.selectedID = nil
            }
        } catch {
            loadError = String(describing: error)
        }
        isLoading = false
    }

    // MARK: - Selection

    /// A tap on a candidate card.
    ///
    /// Returns the candidate to open the camera for, or `nil` when D6 requires a confirmation tap
    /// first — in which case the tap has selected, and the confirm bar is now on screen.
    func tap(_ candidate: VisitCandidate) -> VisitCandidate? {
        guard shortlist.requiresConfirmation else { return candidate }
        selectedID = candidate.id
        return nil
    }

    /// The confirm button. Only reachable once something is selected.
    func confirm() -> VisitCandidate? { selectedCandidate }
}
