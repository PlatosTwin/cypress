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
    /// The photographs the visit is about, each with the framing chip it was taken under, in the order
    /// they were taken. A visit without any cannot be saved — "Log visit" is disabled until a photo is
    /// snapped (PROTOTYPE-FLOW §1.6.1) — and it may now hold up to one per framing.
    ///
    /// ── A list, because one camera session takes three (ERRATA E152) ──────────────────────────
    /// This was a single `OutboxPhoto?`, so switching the chip and pressing the shutter again replaced
    /// the photograph that was there. `OutboxItem.photos` has been `[OutboxPhoto]` since it was
    /// written, and `outbox.enqueue(_:photos:)` has always taken a list; the draft was the narrow part
    /// of a pipe that was wide at both ends.
    ///
    /// **At most one per framing**, enforced by `stage(_:)` rather than by convention, because that is
    /// the same invariant the staged filename now carries: a second full-tree shot is a *retake* of the
    /// full-tree shot, writes to the same path, and must not become a second row pointing at one file.
    ///
    /// Path and shot type stay one value because they are written together and read together: the
    /// upload records `photos.shot_type` from whatever it is handed, and that record is append-only.
    private(set) var photos: [OutboxPhoto]
    var capturedAt: Date

    init(
        visitID: UUID = UUID(),
        treeID: UUID,
        note: String? = nil,
        phenologyTags: [PhenologyTag] = [],
        gpsAccuracyM: Double? = nil,
        photos: [OutboxPhoto] = [],
        capturedAt: Date = Date()
    ) {
        self.visitID = visitID
        self.treeID = treeID
        self.note = note
        self.phenologyTags = phenologyTags
        self.gpsAccuracyM = gpsAccuracyM
        self.photos = []
        self.capturedAt = capturedAt
        // Through the same door the shutter uses, so a draft built in a test or a preview cannot hold
        // two photographs of one framing when the app cannot.
        for photo in photos { stage(photo) }
    }

    /// Records a photograph, replacing any earlier one of the same framing.
    ///
    /// Replacing **in place** rather than appending and letting the last win: the order of this list is
    /// the order the photographs were taken, it is what the outbox row carries, and a retake of the
    /// trunk is not a later event than the leaf shot that followed it.
    mutating func stage(_ photo: OutboxPhoto) {
        if let index = photos.firstIndex(where: { $0.shotType == photo.shotType }) {
            photos[index] = photo
        } else {
            photos.append(photo)
        }
    }

    /// Forgets the photograph of one framing — the shutter's retake, before a replacement exists.
    mutating func discardPhoto(shotType: ShotType) {
        photos.removeAll { $0.shotType == shotType }
    }

    func photo(shotType: ShotType) -> OutboxPhoto? {
        photos.first { $0.shotType == shotType }
    }

    var photoPaths: [String] { photos.map(\.path) }
    var hasPhoto: Bool { !photos.isEmpty }
    func hasPhoto(shotType: ShotType) -> Bool { photo(shotType: shotType) != nil }
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
        // One photograph is enough and three is the most there can be. **Two of three is a complete
        // contribution** (ERRATA E152): nothing in BUILD-PLAN or PROTOTYPE-FLOW asks for a set, the
        // only stated gate is 1.6.1's "disabled until snapped", and a visit that refused to save
        // because the contributor did not find a leaf worth photographing would lose the two
        // photographs they did take. There is no draft state, so there is nothing left behind to nag
        // about either — what was taken is what is queued.
        guard !draft.photos.isEmpty else { throw APIError.validationFailed }

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

        // The shot type rides along with each binary. It is the only carrier: the payload beside it
        // is a `Visit`, which has no photo columns, and the upload is what writes `photos.shot_type`.
        // One row, several binaries — the drain uploads each in turn and takes it out of the row by
        // path, which is why the paths have to differ (`VisitPhotoStaging.url`).
        let item = try await outbox.enqueue(.visit(visit), photos: draft.photos)
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

    /// One file per **visit and framing**, which is one file per photograph a visit can hold.
    ///
    /// ── Why the framing is in the name (ERRATA E152) ──────────────────────────────────────────
    /// This was `\(visitID.uuidString).jpg`, and the sentence above it read "one file per visit id, so
    /// a re-save of the same draft overwrites rather than accumulating". That was true and it was the
    /// bug: one camera session can now take a full tree, a trunk and a leaf, and under the old name all
    /// three were the same path — so `PhotoBinary.write` removed the destination and moved the third
    /// capture on top of the first two, and a contributor who photographed a tree three ways kept the
    /// last one. Silently: nothing reads a staged file between the shutter and the drain, so there was
    /// no moment at which the loss could show.
    ///
    /// `ShotType.rawValue` and not a counter, an index or a fresh UUID, because the framing is the
    /// thing that actually distinguishes these files — a visit holds at most one photograph per
    /// framing, which is what makes a *retake* of the trunk overwrite the trunk and nothing else. A
    /// counter would make every retake a new file and leave the abandoned ones in a backed-up
    /// directory with nothing pointing at them.
    ///
    /// **Three things read this path and all three are fine with it, which was checked rather than
    /// assumed.** `photos.local_path` gets one row per photograph, each with its own path
    /// (`beginPhotoUpload`). `OutboxStore.removePhoto(atPath:from:)` keys on the path, so draining one
    /// of the three does not take its siblings out of the row — the invariant its comment states, "a
    /// row cannot stage the same file twice", is *more* true now, not less. And `LocalAPI.uploadPhoto`
    /// moves each staged file to `<photoID>.jpg` under a fresh photo id, so three staged files land as
    /// three stored files.
    static func url(for visitID: UUID, shotType: ShotType) throws -> URL {
        try directory().appendingPathComponent("\(visitID.uuidString)-\(shotType.rawValue).jpg")
    }

    /// Stages a capture, without its metadata sidecar.
    ///
    /// Every capture in the app comes through here, which is what E148 bought and what must not be
    /// routed around: the strip is a property of *the staged file*, not of a particular flow's onward
    /// journey. Three shots in one session are three calls to this function.
    ///
    /// - Throws: whatever `PhotoBinary.write(_:strippingMetadataTo:)` throws for bytes it cannot
    ///   rewrite, which both capture screens already handle as "that photo could not be saved" — the
    ///   state a contributor answers by retaking. Nothing raw is left behind on that path.
    @discardableResult
    static func write(_ data: Data, for visitID: UUID, shotType: ShotType) throws -> String {
        let url = try url(for: visitID, shotType: shotType)
        try PhotoBinary.write(data, strippingMetadataTo: url)
        return url.path
    }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
