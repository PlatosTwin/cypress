//
//  CareLogModel.swift
//  Cypress — Features/CareLog
//
//  Screen 09's one `@Observable` model (ARCHITECTURE §3: "One `@Observable` model per feature
//  folder, owned by the feature's root view via `@State`").
//
//  It talks to `CypressAPI` and to the outbox, and to nothing else — no store, no GRDB, no network
//  (ARCHITECTURE §4).
//

import Foundation
import Observation

@MainActor
@Observable
final class CareLogModel {

    /// What the contributor has toggled. The sheet is usable the instant it appears; nothing here
    /// waits on a read, which is the whole point of a thirty-second surface.
    private(set) var draft: CareLogDraft

    /// The tree's display name, once the profile read lands. Nil until then, and nil forever if the
    /// read fails — see `CareLogPresentation.title` for what that renders.
    private(set) var treeDisplayName: String?

    // MARK: - The optional well, no longer inert (task #147)
    //
    // Reported from the owner's device walk of 2026-07-31: "the care log has a space for photo/note
    // but neither can be added." This was the drawn-but-inert class — ERRATA E25 recorded the well
    // with no editor behind it, `CareLogDraft` has carried `note` and `photos` since it was
    // written, and `CareLogOutboxWriter` has persisted both all along. The owner's report is the
    // ask E25 was waiting on, so the well now opens the two fields the record already takes.
    // `care_events.note` and the photo path both exist in the schema as shipped — no migration.

    /// Whether the well has been opened into its two fields. One-way per sheet: collapsing again
    /// would hide a note that was just typed, which reads as losing it.
    var isEditingExtras = false

    /// The note, bound by the view and written into the draft at save — the same shape screen 04
    /// gives its note. The writer trims it and stores blank as NULL.
    var note: String

    /// Why the picked photo did not attach, or nil. The same register as the camera's own line:
    /// a control that silently does nothing reads as a broken control.
    private(set) var photoError: String?

    /// Names the staged file, the way a visit's id names its captures. Minted with the sheet so a
    /// re-pick replaces the same file rather than accumulating staged bytes.
    private let draftID = UUID()

    var hasPhoto: Bool { !draft.photos.isEmpty }

    /// Stages a picked photo for the outbox, through the one funnel every capture in the app uses
    /// (`VisitPhotoStaging`), so the metadata strip of E148 applies to a care photo too. Staged as
    /// `.other`: nothing on this sheet frames a subject, and `.other` is the stored vocabulary's
    /// word for exactly that — the browser captions it "Photo".
    func attachPhoto(_ data: Data) {
        do {
            let path = try VisitPhotoStaging.write(data, for: draftID, shotType: .other)
            draft.photos = [OutboxPhoto(path: path, shotType: .other)]
            photoError = nil
        } catch {
            photoError = "That photo could not be added: \(error.localizedDescription)"
        }
    }

    /// Every field on this sheet is optional and reversible — the photo too. The staged file is
    /// left where it is, the same condition an abandoned visit draft has always left behind.
    func removePhoto() {
        draft.photos = []
    }

    private(set) var isSaving = false
    /// Set when the *enqueue* failed, which is the only failure a contributor can act on. A drain
    /// failure is not one — the row is already durable (see `CareLogOutboxWriter`).
    private(set) var saveFailed = false

    let treeID: UUID
    private let api: any CypressAPI
    private let outbox: OutboxQueue
    private let attribution: Attribution
    /// D6's per-contribution accuracy, asked of the composition root's provider at the moment the
    /// care event is written rather than when the sheet was built
    /// (ERRATA E158). A closure for the same reason
    /// `now` beside it is one: `@State` builds this model once, so a `Double?` handed in froze at
    /// the first frame and recorded `nil` on any sheet opened before the first fix.
    private let gpsAccuracyM: @MainActor () -> Double?
    private let now: () -> Date
    private let onSaved: (CareLogSaveReceipt) -> Void

    /// `initialDraft` exists so the previews can stand up the state SCREENS.md 09 draws — two chips
    /// on — without driving taps. The sheet itself always opens empty; see `CareLogDraft`.
    init(
        treeID: UUID,
        api: any CypressAPI,
        outbox: OutboxQueue,
        attribution: Attribution,
        gpsAccuracyM: @escaping @MainActor () -> Double? = { nil },
        treeDisplayName: String? = nil,
        initialDraft: CareLogDraft = CareLogDraft(),
        now: @escaping () -> Date = { Date() },
        onSaved: @escaping (CareLogSaveReceipt) -> Void = { _ in }
    ) {
        self.treeID = treeID
        self.api = api
        self.outbox = outbox
        self.attribution = attribution
        self.gpsAccuracyM = gpsAccuracyM
        self.treeDisplayName = treeDisplayName
        self.draft = initialDraft
        self.note = initialDraft.note ?? ""
        self.now = now
        self.onSaved = onSaved
    }

    var presentation: CareLogPresentation {
        CareLogPresentation(treeDisplayName: treeDisplayName, draft: draft)
    }

    // MARK: - Loading

    /// Reads the profile for the one thing the title needs.
    ///
    /// A failure is swallowed on purpose. This sheet records care, and none of it needs the tree's
    /// record to be readable — refusing to open because a name did not arrive would cost the
    /// contribution to save the caption.
    func loadName() async {
        guard treeDisplayName == nil else { return }
        guard let profile = try? await api.treeProfile(id: treeID) else { return }
        treeDisplayName = TreeProfilePresentation(profile: profile).title
    }

    // MARK: - Filling in

    /// Tapping an on chip turns it off. Every field on this sheet is optional and reversible; a
    /// contributor who mistapped `Mulched` has to be able to say so before the record is written.
    func toggle(_ action: CareAction) {
        if draft.actions.contains(action) {
            draft.actions.remove(action)
        } else {
            draft.actions.insert(action)
        }
    }

    // MARK: - Saving

    /// The `Done` CTA.
    ///
    /// Guarded on a non-empty draft, per PROTOTYPE-FLOW §1.3 (`logCare`: "no-op if no care chip is
    /// on"). This is the one place in the app where a guard on submission is correct and does not
    /// contradict "never block submission for lack of rigor" (DECISIONS §2.5): the rule there is
    /// about *precision* — an estimate is as welcome as a tape — while an empty care event names no
    /// act at all, and there is nothing for a coordinator to read in it.
    func save() async {
        guard !isSaving, presentation.canSave else { return }
        isSaving = true
        saveFailed = false
        defer { isSaving = false }

        // The note joins the draft here, beside the save that makes the record exist — the same
        // moment screen 04 reads its own field. The writer trims it and stores blank as NULL.
        draft.note = note

        do {
            let receipt = try await CareLogOutboxWriter.save(
                draft,
                treeID: treeID,
                attribution: attribution,
                outbox: outbox,
                gpsAccuracyM: gpsAccuracyM(),
                now: now()
            )
            onSaved(receipt)
        } catch {
            saveFailed = true
        }
    }
}
