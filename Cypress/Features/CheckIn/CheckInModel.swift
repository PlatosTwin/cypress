//
//  CheckInModel.swift
//  Cypress — Features/CheckIn
//
//  Screen 05's one `@Observable` model (ARCHITECTURE §3: "One `@Observable` model per feature
//  folder, owned by the feature's root view via `@State`").
//
//  It talks to `CypressAPI` and to the outbox, and to nothing else — no store, no GRDB, no network
//  (ARCHITECTURE §4).
//

import Foundation
import Observation

@MainActor
@Observable
final class CheckInModel {

    /// What the contributor has filled in. The screen is usable the instant it appears; nothing
    /// here waits on a read.
    private(set) var draft: CheckInDraft

    /// The tree's species, once `GET /trees/{id}` lands. It is read for exactly one reason: the
    /// seasonal rule that decides whether a vitality rating may be collected at all (PRODUCT §3).
    ///
    /// Nil while the read is in flight, and nil forever if it fails. Both permit the rating, which
    /// is the asymmetry ERRATA E9 settles: wrongly permitting costs one observation a rater can
    /// skip, wrongly suppressing removes the section with no way for anyone in the field to argue.
    private(set) var species: Species?

    private(set) var isSaving = false
    /// Set when the *enqueue* failed, which is the only failure a contributor can act on. A drain
    /// failure is not one — the row is already durable (see `CheckInOutboxWriter`).
    private(set) var saveFailed = false

    let treeID: UUID
    private let api: any CypressAPI
    private let outbox: OutboxQueue
    private let attribution: Attribution
    /// D6's per-contribution accuracy, asked of the composition root's provider at the moment the
    /// observation is written rather than when the screen was built
    /// (ERRATA — see docs/errata-pending/gps-accuracy-at-submit.md). A closure for the same reason
    /// `now` beside it is one: `@State` builds this model once, so a `Double?` handed in froze at
    /// the first frame and recorded `nil` on any check-in opened before the first fix.
    private let gpsAccuracyM: @MainActor () -> Double?
    private let now: () -> Date
    private let calendar: Calendar
    private let onSaved: (CheckInSaveReceipt) -> Void

    /// `initialDraft` exists so the previews can stand up the one state the design export draws,
    /// and the leaf-off state it does not, without driving taps. The screen itself always opens on
    /// an empty card: nothing is pre-filled for a contributor except `status`, which PRODUCT §5 M6
    /// gives the only default on the screen.
    init(
        treeID: UUID,
        api: any CypressAPI,
        outbox: OutboxQueue,
        attribution: Attribution,
        gpsAccuracyM: @escaping @MainActor () -> Double? = { nil },
        species: Species? = nil,
        initialDraft: CheckInDraft = CheckInDraft(),
        now: @escaping () -> Date = { Date() },
        calendar: Calendar = .current,
        onSaved: @escaping (CheckInSaveReceipt) -> Void = { _ in }
    ) {
        self.draft = initialDraft
        self.treeID = treeID
        self.api = api
        self.outbox = outbox
        self.attribution = attribution
        self.gpsAccuracyM = gpsAccuracyM
        self.species = species
        self.now = now
        self.calendar = calendar
        self.onSaved = onSaved
    }

    var presentation: CheckInPresentation {
        CheckInPresentation(
            draft: draft,
            species: species,
            month: calendar.component(.month, from: now())
        )
    }

    // MARK: - Loading

    /// Reads the profile for its species. A failure is swallowed on purpose: this screen collects
    /// observations, and none of them needs the tree's record to be readable.
    func loadSpecies() async {
        guard species == nil else { return }
        species = try? await api.treeProfile(id: treeID).species
    }

    // MARK: - Filling in

    func select(status: ObservationStatus) {
        draft.status = status
    }

    /// Tapping the selected row again clears it: every field is optional, so a rating a contributor
    /// no longer stands behind has to be removable (SCREENS.md 05, "all fields optional").
    func select(vitality: Vitality) {
        draft.vitality = draft.vitality == vitality ? nil : vitality
    }

    func select(foliageDensity: FoliageDensity) {
        draft.foliageDensity = draft.foliageDensity == foliageDensity ? nil : foliageDensity
    }

    func toggle(_ flag: StructureFlag) {
        if draft.structureFlags.contains(flag) {
            draft.structureFlags.remove(flag)
        } else {
            draft.structureFlags.insert(flag)
        }
    }

    // MARK: - Saving

    /// The CTA. Never blocked for lack of rigor — an empty card is a valid check-in and submission
    /// is never gated on it (DECISIONS §2.5, Open Question #3: "never block submission").
    func save() async {
        guard !isSaving else { return }
        isSaving = true
        saveFailed = false
        defer { isSaving = false }

        do {
            let receipt = try await CheckInOutboxWriter.save(
                draft,
                treeID: treeID,
                attribution: attribution,
                outbox: outbox,
                species: species,
                gpsAccuracyM: gpsAccuracyM(),
                now: now(),
                calendar: calendar
            )
            onSaved(receipt)
        } catch {
            saveFailed = true
        }
    }
}
