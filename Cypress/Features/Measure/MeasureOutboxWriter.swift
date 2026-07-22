//
//  MeasureOutboxWriter.swift
//  Cypress — Features/Measure
//
//  ARCHITECTURE §4: "Every mutation is idempotent on a client-generated `clientUUID`, written to
//  the outbox *first*, and only then attempted against the API."
//
//  So `save` does exactly that, in that order, and returns as soon as the row is durable. The drain
//  is a separate, best-effort step whose failure the caller must not treat as a failed save — a
//  measurement taken in a dead zone is saved, not lost. Same shape as `CheckInOutboxWriter` and
//  `CareLogOutboxWriter`, deliberately.
//
//  Foundation only: this is the half of the screen that has to be runnable without a renderer.
//

import Foundation

/// What a save produced.
struct MeasureSaveReceipt {
    let measurement: TreeMeasurement
    /// The outbox row as stored. Its `id` is what screen 17 shows.
    let item: OutboxItem
    /// Whether the drain that followed the enqueue managed to apply it. **Not** a success flag —
    /// `false` means "waiting", which is a designed state, not an error.
    let syncedImmediately: Bool
}

enum MeasureOutboxWriter {

    /// Writes a measurement to the outbox and then, separately, tries to drain it.
    ///
    /// - Parameter gpsAccuracyM: the accuracy of the fix this reading was taken on, straight from
    ///   the composition root's location provider. **It is passed through unchanged, including when
    ///   it is nil.** D6 stores per-contribution GPS accuracy and excludes readings worse than 15 m
    ///   from growth charting; `FieldCaptured.isEligibleForGrowthCharting` also excludes a reading
    ///   with no accuracy at all, so substituting an optimistic default here would charter a point
    ///   nobody could attribute, and substituting a pessimistic one would silently empty every chart
    ///   on the tree. Neither is this function's decision to make (ERRATA E65).
    /// - Throws: only if the *enqueue* fails.
    @discardableResult
    static func save(
        _ draft: MeasureDraft,
        treeID: UUID,
        attribution: Attribution,
        outbox: OutboxQueue,
        gpsAccuracyM: Double? = nil,
        now: Date = Date()
    ) async throws -> MeasureSaveReceipt {
        // ── 1. Durable, before anything else is attempted. ────────────────────────────────────
        let (measurement, item) = try await enqueue(
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

        return MeasureSaveReceipt(measurement: measurement, item: item, syncedImmediately: synced)
    }

    /// Step one on its own: the measurement becomes durable and nothing is attempted.
    ///
    /// Split out for the reason the visit and check-in writers split it — the proof that a
    /// contribution survives termination is only a proof if the process can die *between* the
    /// enqueue and the drain.
    ///
    /// - Throws: `APIError.validationFailed` when the draft holds no readable number. That is not
    ///   the "never block submission" rule being bent (DECISIONS §2.5): the rule is about rigour,
    ///   and an empty keypad is not an imprecise reading, it is no reading. The screen's CTA is
    ///   already disabled there; this is the boundary saying the same thing.
    static func enqueue(
        _ draft: MeasureDraft,
        treeID: UUID,
        attribution: Attribution,
        outbox: OutboxQueue,
        gpsAccuracyM: Double? = nil,
        now: Date = Date()
    ) async throws -> (measurement: TreeMeasurement, item: OutboxItem) {

        // The one door to a number in this app. `Quantity` has no initializer that omits `method`,
        // so there is no branch here in which a method-less measurement could be built (D7).
        guard let quantity = draft.quantity else { throw APIError.validationFailed }

        // Two factories, because DBH carries `measurement_height_m` and height does not
        // (BUILD-PLAN §4). Neither takes a bare number.
        let measurement: TreeMeasurement
        switch draft.kind {
        case .dbh:
            measurement = TreeMeasurement.dbh(
                treeID: treeID,
                attribution: attribution,
                capturedAt: now,
                gpsAccuracyM: gpsAccuracyM,
                quantity: quantity,
                createdAt: now,
                updatedAt: now
            )
        case .height:
            measurement = TreeMeasurement.height(
                treeID: treeID,
                attribution: attribution,
                capturedAt: now,
                gpsAccuracyM: gpsAccuracyM,
                quantity: quantity,
                createdAt: now,
                updatedAt: now
            )
        }

        // `TreeMeasurement.clientUUID` is minted with the measurement and is the idempotency key:
        // stable across every retry of this row, which is what makes a replayed item come back
        // `.duplicate` rather than a second reading on an append-only record (DECISIONS §3.8).
        let item = try await outbox.enqueue(.measurement(measurement))
        return (measurement, item)
    }
}
