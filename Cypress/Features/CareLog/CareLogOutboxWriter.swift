//
//  CareLogOutboxWriter.swift
//  Cypress — Features/CareLog
//
//  ARCHITECTURE §4: "Every mutation is idempotent on a client-generated `clientUUID`, written to
//  the outbox *first*, and only then attempted against the API. This is true even though the API is
//  currently local: the outbox is the feature, not a network workaround."
//
//  So `save` does exactly that, in that order, and returns as soon as the row is durable. The drain
//  is a separate, best-effort step whose failure the caller must not treat as a failed save — care
//  logged in a fog bank with no signal is saved, not lost. Same shape as `CheckInOutboxWriter`,
//  deliberately.
//
//  Foundation only: this is the half of the screen that has to be runnable without a renderer.
//

import Foundation

/// What a save produced.
struct CareLogSaveReceipt {
    let careEvent: CareEvent
    /// The outbox row as stored. Its `id` is what screen 17 would show.
    let item: OutboxItem
    /// Whether the drain that followed the enqueue managed to apply it. **Not** a success flag —
    /// `false` means "waiting", which is a designed state, not an error.
    let syncedImmediately: Bool
}

enum CareLogOutboxWriter {

    /// Writes a care event to the outbox and then, separately, tries to drain it.
    ///
    /// - Throws: only if the *enqueue* fails.
    @discardableResult
    static func save(
        _ draft: CareLogDraft,
        treeID: UUID,
        attribution: Attribution,
        outbox: OutboxQueue,
        gpsAccuracyM: Double? = nil,
        now: Date = Date()
    ) async throws -> CareLogSaveReceipt {
        // ── 1. Durable, before anything else is attempted. ────────────────────────────────────
        let (careEvent, item) = try await enqueue(
            draft,
            treeID: treeID,
            attribution: attribution,
            outbox: outbox,
            gpsAccuracyM: gpsAccuracyM,
            now: now
        )

        // ── 2. Best effort, after. ────────────────────────────────────────────────────────────
        var synced = false
        if let report = try? await outbox.drain() {
            synced = report.synced > 0
        }

        return CareLogSaveReceipt(careEvent: careEvent, item: item, syncedImmediately: synced)
    }

    /// Step one on its own: the care event becomes durable and nothing is attempted.
    ///
    /// Split out for the same reason the check-in writer splits it — the proof that a contribution
    /// survives termination is only a proof if the process can die *between* the enqueue and the
    /// drain.
    static func enqueue(
        _ draft: CareLogDraft,
        treeID: UUID,
        attribution: Attribution,
        outbox: OutboxQueue,
        gpsAccuracyM: Double? = nil,
        now: Date = Date()
    ) async throws -> (careEvent: CareEvent, item: OutboxItem) {

        let careEvent = CareEvent(
            treeID: treeID,
            attribution: attribution,
            capturedAt: now,
            // D6: "Store per-contribution GPS accuracy." Care events are never charted, so this
            // number decides nothing here — it is stored for consistency with every other field
            // contribution, and because a coordinator reading the record later cannot ask for it
            // retroactively.
            gpsAccuracyM: gpsAccuracyM,
            actions: draft.orderedActions,
            note: draft.note?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
            createdAt: now,
            updatedAt: now
        )

        // `CareEvent.clientUUID` is minted with the event and is the idempotency key: stable across
        // every retry of this row, which is what makes a replayed item come back `.duplicate`
        // rather than a second watering (DECISIONS §3.8).
        //
        // Photos ride alongside as `OutboxPhoto`. `CareEvent.photoID` is filled by the upload, not
        // by this call: the binary has no id until `beginPhotoUpload` reserves one.
        let item = try await outbox.enqueue(.careEvent(careEvent), photos: draft.photos)
        return (careEvent, item)
    }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
