//
//  VisitCameraModel.swift
//  Cypress — Features/Visit
//
//  Screen 04's state: the shot, the note, the species-aware chips, and the one write that makes
//  this whole feature the walking skeleton's acceptance criterion.
//

import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class VisitCameraModel {

    // MARK: Dependencies

    private let api: any CypressAPI
    private let outbox: OutboxQueue
    private let attribution: Attribution
    let camera = VisitCameraController()

    // MARK: Subject

    let treeID: UUID
    /// What the header calls this tree. Supplied by whoever pushed the screen so the camera does
    /// not have to load a profile before it can draw.
    let treeDisplayName: String

    /// The species record, once loaded. `nil` for the seed's long tail — and a `nil` species means
    /// **no phenology chips at all**, because there is no vocabulary to validate against (D5).
    private(set) var species: Species?

    /// The last full-tree photo of this tree, at 30 % opacity behind the viewfinder. `nil` on a
    /// first visit, which is a designed state (BUILD-PLAN §9).
    private(set) var ghost: UIImage?

    // MARK: The draft

    private(set) var draft: VisitDraft
    /// The frame just taken, shown in place of the live preview until it is replaced or saved.
    private(set) var snapshot: UIImage?
    var shotType: ShotType = .fullTree
    var note: String = ""
    var selectedTags: Set<PhenologyTag> = []

    private(set) var isSaving = false
    private(set) var saveError: String?

    // MARK: Init

    init(
        treeID: UUID,
        treeDisplayName: String,
        gpsAccuracyM: Double?,
        api: any CypressAPI,
        outbox: OutboxQueue,
        attribution: Attribution
    ) {
        self.treeID = treeID
        self.treeDisplayName = treeDisplayName
        self.api = api
        self.outbox = outbox
        self.attribution = attribution
        // The visit id exists before the shutter does: it names the file the photo is written to.
        self.draft = VisitDraft(treeID: treeID, gpsAccuracyM: gpsAccuracyM)
    }

    // MARK: - Derived

    /// PROTOTYPE-FLOW §1.6.1, the one hard gate on this screen: "Log visit is disabled until
    /// `snapped`. Both visually and functionally."
    var canLogVisit: Bool { draft.hasPhoto && !isSaving }

    var hasSnapped: Bool { draft.hasPhoto }

    /// Whether the alignment layer means anything for the subject now selected.
    ///
    /// The ghost is *the last full-tree photo*, and `ShotType.supportsGhostOverlay` has always said
    /// so — `VisitGhostStore.record` refuses to store a trunk close-up as one. The screen only ever
    /// read the storing half of that rule: it drew whatever ghost the tree had behind every chip,
    /// so choosing Trunk or Leaf left a whole tree hanging in the viewfinder to line a bark
    /// close-up up against, which is not a thing anybody can do (ERRATA E125).
    ///
    /// One property, read by the layer, the pill and the caption, so the three cannot disagree
    /// about what is on screen.
    var subjectTakesGhost: Bool { shotType.supportsGhostOverlay }

    /// Whether a ghost is in fact being drawn right now — a stored one, for a subject that takes
    /// one, before the shutter.
    var showsGhost: Bool { ghost != nil && subjectTakesGhost && !hasSnapped }

    /// The guidance pill. `cameraHint` in the prototype: with a ghost it asks you to match the last
    /// angle; without one it tells you this is the first photo, which is the honest version of the
    /// same sentence. On a subject that takes no ghost it says the third true thing — that this
    /// shot stands on its own — rather than asking for an angle there is nothing to match.
    var guidance: String {
        let subject: String
        switch shotType {
        case .fullTree: subject = "Full tree"
        case .trunk: subject = "Trunk"
        case .leaf: subject = "Leaf close-up"
        case .other: subject = "Photo"
        }
        if hasSnapped { return "Photo added to the timeline" }
        if !subjectTakesGhost { return "\(subject) · framed on its own" }
        return ghost == nil ? "\(subject) · its first photo" : "\(subject) · match last visit's angle"
    }

    /// The mono line in the bottom-left corner, which names what the viewfinder is doing.
    var ghostCaption: String {
        if !subjectTakesGhost { return "overlay off · full-tree only" }
        return ghost == nil ? "no ghost yet · first photo" : "ghost overlay 30%"
    }

    /// D5, the whole of it. See `VisitPhenologyVocabulary` for the two gates and why the row is
    /// empty against today's seed.
    var availablePhenologyTags: [PhenologyTag] {
        VisitPhenologyVocabulary.tags(for: species)
    }

    /// The three shot types SCREENS 04 draws. `.other` is in the stored vocabulary but is not
    /// offered — nothing on this screen means "other".
    var shotTypes: [ShotType] { [.fullTree, .trunk, .leaf] }

    func label(for shotType: ShotType) -> String {
        switch shotType {
        case .fullTree: return "Full tree"
        case .trunk: return "Trunk"
        case .leaf: return "Leaf close-up"
        case .other: return "Other"
        }
    }

    // MARK: - Lifecycle

    func load() async {
        // The ghost first, and off the main actor: it is the thing the screen exists for, it comes
        // off disk, and it must be up before the preview so there is nothing to line up against a
        // blank frame.
        let treeID = self.treeID
        ghost = await Task.detached(priority: .userInitiated) {
            VisitGhostStore.ghost(for: treeID)
        }.value

        async let session: Void = camera.start()
        if let profile = try? await api.treeProfile(id: treeID) {
            species = profile.species
        }
        await session
    }

    func stop() {
        camera.stop()
    }

    // MARK: - Capture

    /// The shutter.
    func snap() async {
        guard let data = await camera.capturePhoto() else { return }
        apply(imageData: data)
    }

    /// The photo-library fallback (BUILD-PLAN §9) — and the only path a simulator can take.
    func useLibraryImage(_ data: Data) {
        apply(imageData: data)
    }

    private func apply(imageData: Data) {
        guard let image = UIImage(data: imageData) else { return }
        do {
            let path = try VisitPhotoStaging.write(imageData, for: draft.visitID)
            // The chip as it stands at capture. It is re-read at save, below, because the chip row
            // stays live after the shutter and the last tap before "Log visit" is the answer.
            draft.photo = OutboxPhoto(path: path, shotType: shotType)
            draft.capturedAt = Date()
            snapshot = image
            saveError = nil
        } catch {
            // A photo that cannot be written to disk is a photo that cannot survive termination, so
            // it is not a photo. `canLogVisit` stays false and the screen says why.
            saveError = "That photo could not be saved to this phone: \(error.localizedDescription)"
        }
    }

    func retake() {
        draft.photo = nil
        snapshot = nil
    }

    // MARK: - The write

    /// "Log visit".
    ///
    /// Outbox first, drain second, per ARCHITECTURE §4. Returns the receipt for screen 18, or `nil`
    /// if the enqueue itself failed — which is the only failure this screen can have.
    func logVisit() async -> VisitSaveReceipt? {
        guard canLogVisit else { return nil }
        isSaving = true
        defer { isSaving = false }

        draft.note = note
        draft.phenologyTags = Array(selectedTags)
        // The chips stay tappable after the shutter, so the framing is resolved here, where the note
        // and the tags are, rather than being frozen at capture.
        if let path = draft.photoPath {
            draft.photo = OutboxPhoto(path: path, shotType: shotType)
        }

        do {
            let receipt = try await VisitOutboxWriter.save(
                draft,
                attribution: attribution,
                outbox: outbox,
                species: species
            )

            // The ghost is recorded only once the visit is durable — a shot the user backed out of
            // must not become the thing the next visit is lined up against. Read the staged file
            // back rather than holding the bytes: by now the drain may already have moved it, and
            // if it has, this tree's photo record is the ghost and the copy is redundant.
            if let path = draft.photoPath, let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                VisitGhostStore.record(data, for: treeID, shotType: shotType)
            } else if let snapshot, let data = snapshot.jpegData(compressionQuality: 0.9) {
                VisitGhostStore.record(data, for: treeID, shotType: shotType)
            }

            return receipt
        } catch {
            saveError = String(describing: error)
            return nil
        }
    }

    // MARK: - Chips

    func toggle(_ tag: PhenologyTag) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
    }
}
