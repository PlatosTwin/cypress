//
//  DataDisputeModel.swift
//  Cypress — Features/DataDispute
//
//  The data-dispute screen's one `@Observable` model (ARCHITECTURE §3). It talks to `CypressAPI`
//  and to nothing else; the location arrives as `DataDisputeFixReading` values the view hands over,
//  so the model can be driven by a test without a provider at all.
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

    /// The record's own values, for the "The city has: …" line under each opened section. `nil`
    /// until `loadOnFile()` has read the profile, and after a read that failed: the lines are an
    /// aid to the reporter, and a screen that cannot say what the city has says nothing about it.
    private(set) var onFile: DataDisputeOnFile?

    let treeID: UUID
    private let api: any CypressAPI
    private let currentYear: Int

    /// How the model waits out `DataDisputeLocation.fixTimeout`. `Task.sleep` in the app; a test
    /// hands in one it releases itself, so the 15 s is asserted without being spent.
    private let sleep: @Sendable (Duration) async throws -> Void

    /// The error count the provider had when the block last started waiting. Only an error *after*
    /// that ends the wait — an old one must not answer a new request (`MapLocationProvider
    /// .failureCount`). Taken again whenever the block starts a new wait, not only at the ask
    /// (`locationChanged`).
    @ObservationIgnored
    private var failuresWhenAsked = 0
    /// Which wait the pending timeout belongs to. Every new timeout and every dropped one bumps it,
    /// so a timeout left over from an earlier request cannot end a later one.
    @ObservationIgnored
    private var waitGeneration = 0
    @ObservationIgnored
    private var timeout: Task<Void, Never>?

    init(
        treeID: UUID,
        api: any CypressAPI,
        currentYear: Int = Calendar.current.component(.year, from: Date()),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.treeID = treeID
        self.api = api
        self.currentYear = currentYear
        self.sleep = sleep
    }

    /// What will be sent, for the view to restate what it holds.
    var suggestions: TreeDataDispute.Suggestions { draft.suggestions(currentYear: currentYear) }

    /// Whether the year field holds something this screen will refuse. Drawn under the field as
    /// soon as it is true, not only after a tap on the button.
    var plantedYearIsInvalid: Bool { draft.plantedYear(currentYear: currentYear) == .invalid }

    /// Whether *Send report* can be pressed. Not while a raise is in flight or done, and not while
    /// the position the reporter asked for is still arriving (`DataDisputeDraft.isAwaitingFix`).
    var canSend: Bool { !isRaising && !didRaise && !draft.isAwaitingFix }

    // MARK: - What the city has

    /// Reads the record once, for the "The city has: …" lines. A failure leaves `onFile` `nil`.
    func loadOnFile() async {
        guard onFile == nil else { return }
        onFile = try? await DataDisputeOnFile(api.treeProfile(id: treeID))
    }

    // MARK: - Editing

    /// See `DataDisputeDraft.toggle` for the rule "There's no tree here" follows.
    func toggle(_ choice: DataDisputeChoice) {
        draft.toggle(choice)
        problem = nil
    }

    /// The reporter tapped "use my current location".
    ///
    /// Answers the provider's state as it is right now; `waiting` is resolved by `locationChanged`
    /// when the provider publishes. The view starts the provider — the model has none.
    ///
    /// Also the retry after `.unavailable` (owner ruling 11): it starts a fresh wait, with a fresh
    /// timeout and a fresh baseline for errors. The timeout does not start while iOS's permission
    /// prompt is still up — see `armTimeoutIfWaiting`.
    func useLocation(_ reading: DataDisputeFixReading) {
        failuresWhenAsked = reading.failureCount
        dropTimeout()
        draft.location = .reading(reading)
        armTimeoutIfWaiting(reading)
        problem = nil
    }

    /// The provider published, or Precise Location changed.
    ///
    /// Taken by a block that is waiting, refused or off (`DataDisputeLocation.followsTheProvider`):
    /// a later, better fix replaces a refused one while the screen is open (ruling 7). A fix the
    /// reporter already has captured is theirs until they ask again, so a later, different fix
    /// cannot quietly replace the position they were standing at when they tapped.
    ///
    /// Owner ruling 11: while the block is waiting, an error CoreLocation reported *since the
    /// block started waiting* ends the wait as `.unavailable`. And an `.unavailable` block is not
    /// put back to waiting by a reading with no fix in it — only a fix, or location going off,
    /// replaces it; asking again is the reporter's to do.
    ///
    /// The error baseline is taken again whenever the block starts a new wait from a state that was
    /// not waiting — Location turned off and back on, say. Turning it off may make CoreLocation
    /// report an error to the running update (`kCLErrorDenied`; not yet seen on a phone), and
    /// measured from the original ask that error would end the new wait the moment it began (PR
    /// #185's verifier, finding 2). While iOS's permission prompt is up (`.notAsked`) the block
    /// waits and judges no error either: the reporter has not answered, and the wait that can fail
    /// starts at the grant (the owner's ruling of 2026-09-29).
    func locationChanged(_ reading: DataDisputeFixReading) {
        guard draft.location.followsTheProvider else { return }
        let next = DataDisputeLocation.reading(reading)
        if next == .waiting {
            if draft.location == .unavailable { return }
            if draft.location != .waiting || reading.availability == .notAsked {
                failuresWhenAsked = reading.failureCount
            } else if reading.failureCount > failuresWhenAsked {
                failuresWhenAsked = reading.failureCount
                endWait(as: .unavailable)
                return
            }
        }
        draft.location = next
        armTimeoutIfWaiting(reading)
    }

    // MARK: - The bounded wait (owner ruling 11)

    /// Starts the timeout when the block has just begun waiting, and drops it when it has stopped.
    ///
    /// **The clock starts at the grant, not at the ask** (the owner's ruling of 2026-09-29). While
    /// iOS's location-permission prompt is on screen the provider reads `.notAsked` (authorization
    /// `notDetermined`), and the block waits with no clock: a reporter slow to answer the prompt
    /// must not come back to "couldn't find your location". Allowing moves the provider to
    /// `.waitingForFix`, and the 15 s start then. Refusing moves it to `.denied`, which the block
    /// already answers as location off (`DataDisputeLocation.off`), with its way to Settings.
    private func armTimeoutIfWaiting(_ reading: DataDisputeFixReading) {
        guard draft.location == .waiting, reading.availability != .notAsked else {
            dropTimeout()
            return
        }
        guard timeout == nil else { return }
        waitGeneration += 1
        let generation = waitGeneration
        let sleep = self.sleep
        timeout = Task { [weak self] in
            do { try await sleep(DataDisputeLocation.fixTimeout) } catch { return }
            self?.timeoutElapsed(generation: generation)
        }
    }

    private func timeoutElapsed(generation: Int) {
        guard generation == waitGeneration, draft.location == .waiting else { return }
        endWait(as: .unavailable)
    }

    private func endWait(as location: DataDisputeLocation) {
        dropTimeout()
        draft.location = location
    }

    /// Cancels the pending timeout **and** retires its generation, so a sleep that had already
    /// returned when it was cancelled cannot end a wait it no longer belongs to.
    private func dropTimeout() {
        timeout?.cancel()
        timeout = nil
        waitGeneration += 1
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
        // The button is disabled for all three; this is the same rule for any other caller, so a
        // report is never filed while the block is still promising the position (ruling 8).
        guard canSend else { return }
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
