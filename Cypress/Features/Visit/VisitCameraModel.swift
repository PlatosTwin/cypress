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
    /// The frames taken so far, by framing — each shown in place of the live preview while its own chip
    /// is selected. A dictionary and not one `snapshot`, because all three photographs of a session are
    /// live at once and switching chips has to be able to show you what you already have (E150).
    private(set) var snapshots: [ShotType: UIImage] = [:]
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
    ///
    /// **Any** photograph, not all three. See `VisitOutboxWriter.enqueue` for why two of three is a
    /// complete contribution rather than a draft.
    var canLogVisit: Bool { draft.hasPhoto && !isSaving }

    /// Whether the framing now selected has been photographed. This is the viewfinder's question — it
    /// decides whether the screen shows a photograph or a live preview — and it is per framing, so
    /// choosing `Trunk` after shooting the full tree opens the camera again rather than showing the
    /// tree (E150).
    var hasSnapped: Bool { draft.hasPhoto(shotType: shotType) }

    /// The photograph for the framing now selected, if there is one.
    var snapshot: UIImage? { snapshots[shotType] }

    /// The framings photographed so far, in the order the chips are drawn. Read by the chip row so a
    /// contributor can see what they already have without tapping through it.
    var capturedShotTypes: Set<ShotType> { Set(draft.photos.map(\.shotType)) }

    /// How many of this session's photographs are staged. Drives the CTA's own label, because the one
    /// thing the screen must not do is let somebody save two photographs believing they saved three.
    var capturedCount: Int { draft.photos.count }

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
    /// offered — nothing on this screen means "other". This is also the vocabulary one session can now
    /// fill: three chips, up to three photographs, one per chip.
    var shotTypes: [ShotType] { [.fullTree, .trunk, .leaf] }

    /// What "Log visit" says, which has to name how many photographs are about to be saved.
    ///
    /// Two of three is a complete contribution, so the button must not read as though it were waiting
    /// for a third — but it must not hide the count either, because the whole failure this replaces was
    /// a contributor believing they had three photographs when they had one. A count is not a score: it
    /// describes the thing on screen, not the person, and D1 forbids the latter.
    var logVisitLabel: String {
        switch capturedCount {
        case 0, 1: return "Log visit"
        default: return "Log visit · \(capturedCount) photos"
        }
    }

    /// The line under the chips that names the framings still open, or nothing once all three are taken.
    ///
    /// An invitation, not a requirement: it says what else this session *could* hold. It disappears
    /// rather than turning into a tick, because a screen that congratulates somebody for taking three
    /// photographs is a screen keeping score.
    var remainingShotsLine: String? {
        guard capturedCount > 0 else { return nil }
        let remaining = shotTypes.filter { !capturedShotTypes.contains($0) }
        guard !remaining.isEmpty else { return nil }
        return "Also worth having: " + remaining.map { label(for: $0).lowercased() }.joined(separator: ", ")
    }

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
        // Frozen for the whole of this capture. The chip row stays tappable, and it used to be re-read
        // at save — which was harmless when a visit held one photograph and is wrong now: with three
        // staged files the framing is what names each one on disk, so the label has to be decided at
        // the shutter or the file and the row can disagree about which photograph this is (E150).
        let framing = shotType
        do {
            let path = try VisitPhotoStaging.write(imageData, for: draft.visitID, shotType: framing)
            draft.stage(OutboxPhoto(path: path, shotType: framing))
            draft.capturedAt = Date()
            snapshots[framing] = image
            saveError = nil
        } catch {
            // A photo that cannot be written to disk is a photo that cannot survive termination, so
            // it is not a photo. This framing stays unphotographed and the screen says why; any
            // photographs already taken in this session are untouched and still saveable.
            saveError = "That photo could not be saved to this phone: \(error.localizedDescription)"
        }
    }

    /// The shutter, when the selected framing already has a photograph: throw that one away and go back
    /// to the viewfinder. Only that one — the other framings are separate photographs, and a retake of
    /// the trunk has never meant "discard the full tree as well".
    ///
    /// The staged file is left where it is. A replacement writes to the same path (that is what the
    /// framing in the filename buys), and if the contributor logs the visit without retaking, the row
    /// no longer references it — `VisitPhotoStaging` is a staging directory, and an unreferenced file in
    /// it is the same condition an abandoned draft has always left behind.
    func retake() {
        draft.discardPhoto(shotType: shotType)
        snapshots[shotType] = nil
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
        // The framing is **not** re-read here any more. It used to be, on the argument that "the chip
        // row stays live after the shutter and the last tap before Log visit is the answer" — true of
        // one photograph, and destructive with three: it would relabel every staged photograph as
        // whichever chip happened to be selected when the button was pressed. `apply(imageData:)` freezes
        // it at the shutter now, which is also where the filename is decided (E150).

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
            //
            // **The full-tree photograph specifically**, not "the one that was on screen". The ghost is
            // the last full-tree photo and `VisitGhostStore.record` refuses anything else, so with three
            // photographs in hand the right one has to be picked rather than guessed at: passing the
            // selected chip would have made whether the alignment layer got recorded depend on which
            // chip a contributor happened to leave selected (E150).
            if let fullTree = draft.photo(shotType: .fullTree) {
                if let data = try? Data(contentsOf: URL(fileURLWithPath: fullTree.path)) {
                    VisitGhostStore.record(data, for: treeID, shotType: fullTree.shotType)
                } else if let image = snapshots[.fullTree], let data = image.jpegData(compressionQuality: 0.9) {
                    VisitGhostStore.record(data, for: treeID, shotType: fullTree.shotType)
                }
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
