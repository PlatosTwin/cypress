//
//  CheckInOutboxWriter.swift
//  Cypress — Features/CheckIn
//
//  ARCHITECTURE §4: "Every mutation is idempotent on a client-generated `clientUUID`, written to
//  the outbox *first*, and only then attempted against the API. This is true even though the API
//  is currently local: the outbox is the feature, not a network workaround."
//
//  So `save` does exactly that, in that order, and returns as soon as the row is durable. The drain
//  is a separate, best-effort step whose failure the caller must not treat as a failed save — a
//  check-in taken with no signal is saved, not lost. Same shape as `VisitOutboxWriter`, deliberately.
//
//  Foundation only: this is the half of the screen that has to be runnable without a renderer.
//

import Foundation

/// What a save produced.
struct CheckInSaveReceipt {
    let observation: TreeObservation
    /// The outbox row as stored. Its `id` is what screen 17 would show.
    let item: OutboxItem
    /// Whether the drain that followed the enqueue managed to apply it. **Not** a success flag —
    /// `false` means "waiting", which is a designed state, not an error.
    let syncedImmediately: Bool
}

enum CheckInOutboxWriter {

    /// Writes a check-in to the outbox and then, separately, tries to drain it.
    ///
    /// - Parameters:
    ///   - species: the tree's species, used to re-check the seasonal rule at the boundary. Nil
    ///     permits the rating (ERRATA E9).
    ///   - month: the calendar month the observation was captured in.
    /// - Throws: only if the *enqueue* fails.
    @discardableResult
    static func save(
        _ draft: CheckInDraft,
        treeID: UUID,
        attribution: Attribution,
        outbox: OutboxQueue,
        species: Species? = nil,
        gpsAccuracyM: Double? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async throws -> CheckInSaveReceipt {
        // ── 1. Durable, before anything else is attempted. ────────────────────────────────────
        let (observation, item) = try await enqueue(
            draft,
            treeID: treeID,
            attribution: attribution,
            outbox: outbox,
            species: species,
            gpsAccuracyM: gpsAccuracyM,
            now: now,
            calendar: calendar
        )

        // ── 2. Best effort, after. ────────────────────────────────────────────────────────────
        var synced = false
        if let report = try? await outbox.drain() {
            synced = report.synced > 0
        }

        return CheckInSaveReceipt(observation: observation, item: item, syncedImmediately: synced)
    }

    /// Step one on its own: the check-in becomes durable and nothing is attempted.
    ///
    /// Split out for the same reason the visit writer splits it — the proof that a contribution
    /// survives termination is only a proof if the process can die *between* the enqueue and the
    /// drain.
    static func enqueue(
        _ draft: CheckInDraft,
        treeID: UUID,
        attribution: Attribution,
        outbox: OutboxQueue,
        species: Species? = nil,
        gpsAccuracyM: Double? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async throws -> (observation: TreeObservation, item: OutboxItem) {

        // PRODUCT §3's seasonality rule, enforced at the boundary as well as in the section that
        // draws the rows — the same belt-and-braces `VisitOutboxWriter` applies to phenology tags
        // for D5. A rating collected while the section was visible and then suppressed by a species
        // read landing late must not reach the record.
        let month = calendar.component(.month, from: now)
        let ratingPermitted = species.map { Vitality.isRatingPermitted(for: $0, month: month) } ?? true

        let observation = TreeObservation(
            treeID: treeID,
            attribution: attribution,
            capturedAt: now,
            // D6: "Store per-contribution GPS accuracy." Nil when there was no fix at all.
            gpsAccuracyM: gpsAccuracyM,
            status: draft.status,
            vitality: ratingPermitted ? draft.vitality : nil,
            foliage: draft.foliage,
            structureFlags: draft.orderedStructureFlags,
            note: draft.note?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
            createdAt: now,
            updatedAt: now
        )

        // `TreeObservation.clientUUID` is minted with the observation and is the idempotency key:
        // stable across every retry of this row, which is what makes a replayed item come back
        // `.duplicate` rather than a second check-in (DECISIONS §3.8).
        //
        // Photos ride alongside as `OutboxPhoto`, each carrying the shot type it was framed as —
        // the payload beside them is a `TreeObservation`, which has no photo columns, and the
        // upload is what writes `photos.shot_type` (BUILD-PLAN §4).
        let item = try await outbox.enqueue(.observation(observation), photos: draft.photos)
        return (observation, item)
    }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
