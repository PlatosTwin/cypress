//
//  MeasureModel.swift
//  Cypress — Features/Measure
//
//  Screen 16's one `@Observable` model (ARCHITECTURE §3: "One `@Observable` model per feature
//  folder, owned by the feature's root view via `@State`").
//
//  It talks to `CypressAPI` and to the outbox, and to nothing else — no store, no GRDB, no network
//  (ARCHITECTURE §4).
//
//  **Nothing on this screen waits for a read.** The keypad, both segmented controls and the CTA are
//  live the instant it appears; the profile read only fills the header pill and the sanity pill, and
//  a failed read simply leaves both absent. That is the same rule `CareLogModel` follows, and it is
//  what lets `MeasureScreen` be handed any state directly.
//

import Foundation
import Observation

@MainActor
@Observable
final class MeasureModel {

    /// What the contributor has entered.
    private(set) var draft: MeasureDraft

    /// The tree's display name, once the profile read lands.
    private(set) var treeDisplayName: String?
    /// The tree's measurement record, once the profile read lands. Empty until then, which is the
    /// honest state: no previous reading is known yet, so no sanity pill is drawn.
    private(set) var measurements: [TreeMeasurement] = []

    private(set) var isSaving = false
    /// Set when the *enqueue* failed, which is the only failure a contributor can act on. A drain
    /// failure is not one — the row is already durable (see `MeasureOutboxWriter`).
    private(set) var saveFailed = false

    let treeID: UUID
    private let api: any CypressAPI
    private let outbox: OutboxQueue
    private let attribution: Attribution
    /// D6's per-contribution accuracy, from the composition root's shared location provider. Nil
    /// before the first fix, which is the honest answer then (ERRATA E65).
    private let gpsAccuracyM: Double?
    private let now: () -> Date
    private let calendar: Calendar
    private let onSaved: (MeasureSaveReceipt) -> Void

    init(
        treeID: UUID,
        api: any CypressAPI,
        outbox: OutboxQueue,
        attribution: Attribution,
        gpsAccuracyM: Double? = nil,
        treeDisplayName: String? = nil,
        measurements: [TreeMeasurement] = [],
        initialDraft: MeasureDraft = MeasureDraft(),
        now: @escaping () -> Date = { Date() },
        calendar: Calendar = .current,
        onSaved: @escaping (MeasureSaveReceipt) -> Void = { _ in }
    ) {
        self.treeID = treeID
        self.api = api
        self.outbox = outbox
        self.attribution = attribution
        self.gpsAccuracyM = gpsAccuracyM
        self.treeDisplayName = treeDisplayName
        self.measurements = measurements
        self.draft = initialDraft
        self.now = now
        self.calendar = calendar
        self.onSaved = onSaved
    }

    var presentation: MeasurePresentation {
        MeasurePresentation(
            draft: draft,
            treeDisplayName: treeDisplayName,
            previous: previousMeasurement,
            gpsAccuracyM: gpsAccuracyM,
            now: now(),
            calendar: calendar
        )
    }

    /// The most recent non-deleted reading of the drafted kind.
    ///
    /// `TreeProfile.measurements` is a whole array rather than a `Series` because
    /// `ContributionStore.measurements` reads the series entire and must keep doing so; a page here
    /// would make "last recorded" name the wrong reading (ERRATA E38).
    private var previousMeasurement: TreeMeasurement? {
        measurements
            .filter { $0.kind == draft.kind && $0.deletedAt == nil }
            .max { $0.capturedAt < $1.capturedAt }
    }

    // MARK: - Loading

    /// Reads the profile for the two things this screen borrows from it: the tree's name and its
    /// measurement record.
    ///
    /// A failure is swallowed on purpose, as `CareLogModel.loadName` swallows its own. This screen
    /// records a number; none of that needs the tree's record to be readable, and refusing to open
    /// because a name did not arrive would cost the contribution to save the caption.
    func load() async {
        guard let profile = try? await api.treeProfile(id: treeID) else { return }
        treeDisplayName = TreeProfilePresentation(profile: profile).title
        measurements = profile.measurements
    }

    // MARK: - Filling in

    func select(kind: MeasurementKind) { draft.select(kind: kind) }
    func select(method: MeasurementMethod) { draft.method = method }
    func switchUnit() { draft.switchUnit() }
    func press(_ key: MeasureKey) { draft.apply(key) }

    // MARK: - Saving

    /// §6's `Save measurement`.
    ///
    /// Guarded on a readable number and on nothing else. The anomaly line and the range warning are
    /// sentences, not gates: submission is never blocked for lack of rigor (DECISIONS §2.5).
    func save() async {
        guard !isSaving, draft.canSave else { return }
        isSaving = true
        saveFailed = false
        defer { isSaving = false }

        do {
            let receipt = try await MeasureOutboxWriter.save(
                draft,
                treeID: treeID,
                attribution: attribution,
                outbox: outbox,
                gpsAccuracyM: gpsAccuracyM,
                now: now()
            )
            // The reading is now part of this tree's record, so the sanity pill has to be able to
            // see it: a second measurement taken in the same standing compares against the first.
            measurements.append(receipt.measurement)
            draft.entry = ""
            onSaved(receipt)
        } catch {
            saveFailed = true
        }
    }
}
