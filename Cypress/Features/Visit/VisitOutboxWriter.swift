//
//  VisitOutboxWriter.swift
//  Cypress — Features/Visit
//
//  The M0 acceptance criterion, in one function: "a visit round-trips through the outbox and
//  appears on that tree's timeline after relaunch" (ARCHITECTURE §8).
//
//  ARCHITECTURE §4: "Every mutation is idempotent on a client-generated `clientUUID`, written to
//  the outbox *first*, and only then attempted against the API. This is true even though the API
//  is currently local: **the outbox is the feature, not a network workaround**."
//
//  So `save` does exactly that, in that order, and it returns as soon as the row is durable. The
//  drain is a separate, best-effort step whose failure the caller is not allowed to treat as a
//  failed save — because it is not one. Screen 04's copy says so out loud: "saved to outbox, syncs
//  automatically", and there is no spinner.
//
//  Foundation only, deliberately: this file is the thing the round-trip gate drives, and a gate
//  that needed SwiftUI to run would not run.
//

import Foundation

/// Everything screen 04 collects, before it becomes a `Visit`.
struct VisitDraft {
    /// Minted when the camera screen opens, not when the button is tapped — it is also the name of
    /// the photo file on disk, so it has to exist before the shutter does.
    let visitID: UUID
    let treeID: UUID
    var note: String?
    var phenologyTags: [PhenologyTag]
    /// D6: "Store per-contribution GPS accuracy." Nil only when there was no fix at all.
    var gpsAccuracyM: Double?
    /// The photo the visit is about, and the framing chip it was taken under. A visit without one
    /// cannot be saved — "Log visit" is disabled until a photo is snapped (PROTOTYPE-FLOW §1.6.1).
    ///
    /// Path and shot type are one value because they are written together and read together: the
    /// upload records `photos.shot_type` from whatever it is handed, and that record is append-only.
    var photo: OutboxPhoto?
    var capturedAt: Date

    init(
        visitID: UUID = UUID(),
        treeID: UUID,
        note: String? = nil,
        phenologyTags: [PhenologyTag] = [],
        gpsAccuracyM: Double? = nil,
        photo: OutboxPhoto? = nil,
        capturedAt: Date = Date()
    ) {
        self.visitID = visitID
        self.treeID = treeID
        self.note = note
        self.phenologyTags = phenologyTags
        self.gpsAccuracyM = gpsAccuracyM
        self.photo = photo
        self.capturedAt = capturedAt
    }

    var photoPath: String? { photo?.path }
    var hasPhoto: Bool { photo != nil }
}

/// What a save produced, for the confirmation screen.
struct VisitSaveReceipt {
    let visit: Visit
    /// The outbox row as stored. Its `id` is what screen 17 would show.
    let item: OutboxItem
    /// Whether the drain that followed the enqueue managed to apply it. **Not** a success flag —
    /// `false` means "waiting", which is a normal, designed state, not an error.
    let syncedImmediately: Bool
}

enum VisitOutboxWriter {

    /// Writes a visit to the outbox and then, separately, tries to drain it.
    ///
    /// - Throws: only if the *enqueue* fails. A drain failure is swallowed on purpose: the row is
    ///   already durable and the outbox owns retrying it. Anything else would turn a designed
    ///   offline state into an error dialog.
    @discardableResult
    static func save(
        _ draft: VisitDraft,
        attribution: Attribution,
        outbox: OutboxQueue,
        species: Species? = nil,
        now: Date = Date()
    ) async throws -> VisitSaveReceipt {
        // ── 1. Durable, before anything else is attempted. ────────────────────────────────────
        let (visit, item) = try await enqueue(
            draft, attribution: attribution, outbox: outbox, species: species, now: now
        )

        // ── 2. Best effort, after. ────────────────────────────────────────────────────────────
        var synced = false
        if let report = try? await outbox.drain() {
            synced = report.synced > 0
        }

        return VisitSaveReceipt(visit: visit, item: item, syncedImmediately: synced)
    }

    /// Step one on its own: the visit becomes durable and nothing is attempted.
    ///
    /// Split out because it is the half the round-trip gate has to be able to run alone — the proof
    /// that a visit survives termination is only a proof if the process can die *between* the
    /// enqueue and the drain, which is exactly the window a field visit in a basement lives in.
    static func enqueue(
        _ draft: VisitDraft,
        attribution: Attribution,
        outbox: OutboxQueue,
        species: Species? = nil,
        now: Date = Date()
    ) async throws -> (visit: Visit, item: OutboxItem) {
        guard let photo = draft.photo else { throw APIError.validationFailed }

        // D5, enforced at the boundary as well as in the chip row: an evergreen never carries
        // `fall_color`, whatever the UI thought it was offering.
        let tags = species.map { PhenologyTag.validated(draft.phenologyTags, for: $0) } ?? draft.phenologyTags

        let visit = Visit(
            id: draft.visitID,
            treeID: draft.treeID,
            attribution: attribution,
            // The idempotency key. Client-generated, stable across every retry of this save, which
            // is what makes a replayed item come back `.duplicate` instead of a second row.
            clientUUID: draft.visitID,
            note: draft.note?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
            phenologyTags: tags,
            gpsAccuracyM: draft.gpsAccuracyM,
            capturedAt: draft.capturedAt,
            createdAt: now,
            updatedAt: now
        )

        // The shot type rides along with the binary. It is the only carrier: the payload beside it
        // is a `Visit`, which has no photo columns, and the upload is what writes `photos.shot_type`.
        let item = try await outbox.enqueue(.visit(visit), photos: [photo])
        return (visit, item)
    }
}

// MARK: - Where a captured photo waits

/// The staging directory for photo binaries that have been captured but not yet handed to the API.
///
/// It is in Application Support, next to the database, and **not** in `tmp`: the whole point of the
/// outbox is that a visit taken in a basement survives the app being killed, and iOS reclaims `tmp`
/// whenever it likes. `LocalAPI.uploadPhoto` *moves* the file out of here into its own photo
/// directory, so a file still present is a file still owed.
///
/// **The metadata is dropped here, at the shutter, and not further down.** This used to be
/// `data.write(to:)` and nothing else, on the reading that `uploadPhoto` is the ingest path
/// DECISIONS §3.10 requires the strip on. That reading was true of the check-in flow and false of the
/// community add, which stages a capture the same way and then hands the *staged path* to
/// `addTree` — no upload, no strip, and a `photos.local_path` pointing at the camera's original bytes
/// with the exact GPS of somebody's front garden in them, in a directory iCloud backs up (E148).
///
/// A screen that stages bytes cannot know whether the path it is on ends in an upload. So the strip
/// moved to the one place both capture screens already go through, where it is a property of *the
/// staged file* rather than of a particular flow's onward journey. `uploadPhoto` still strips on the
/// way into the photo directory: the second pass is a no-op on a clean file and it is what keeps
/// files that reached the outbox by some other route honest.
enum VisitPhotoStaging {

    static func directory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let directory = base.appendingPathComponent("VisitCaptures", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// One file per visit id, so a re-save of the same draft overwrites rather than accumulating.
    static func url(for visitID: UUID) throws -> URL {
        try directory().appendingPathComponent("\(visitID.uuidString).jpg")
    }

    /// Stages a capture, without its metadata sidecar.
    ///
    /// - Throws: whatever `PhotoBinary.write(_:strippingMetadataTo:)` throws for bytes it cannot
    ///   rewrite, which both capture screens already handle as "that photo could not be saved" — the
    ///   state a contributor answers by retaking. Nothing raw is left behind on that path.
    @discardableResult
    static func write(_ data: Data, for visitID: UUID) throws -> String {
        let url = try url(for: visitID)
        try PhotoBinary.write(data, strippingMetadataTo: url)
        return url.path
    }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
