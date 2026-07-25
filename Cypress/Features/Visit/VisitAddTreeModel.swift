//
//  VisitAddTreeModel.swift
//  Cypress — Features/Visit
//
//  "None of these? Add this tree" — the community add (ERRATA E127).
//
//  ── What was here before ──────────────────────────────────────────────────────────────────
//  The button, at full opacity, wired to dismiss the flow and record nothing. PROTOTYPE-FLOW §1.5
//  drew it inert and *said so* in the label — "None of these? Add this tree · not in this prototype",
//  `opacity:.55` — and the build kept the button and dropped the honesty. Meanwhile
//  `LocalAPI.addTree` has been complete and tested since the data layer landed, with the 10 m
//  proximity dedupe in it and no caller anywhere in the app.
//
//  ── Why this is not an invented screen ────────────────────────────────────────────────────
//  BUILD-PLAN §9's M2 list names "**duplicate-proximity warning on add-a-tree**" as a required,
//  unmocked state, and §7's endpoint table specifies the behaviour it warns about: "`POST /trees` —
//  Community add: requires photo, species optional; runs the proximity dedupe check (10 m, any
//  species) and returns conflict with the candidate list when it trips". So the *flow* is required
//  and its one hard state is named; what is missing is a mock of it. Per ARCHITECTURE rule 8 the
//  layout follows the nearest specified thing rather than inventing a look: it is screen 02's frame
//  and header, screen 14's dashed photo well, screen 04's two photo sources, and C24 for the warning.
//
//  ── The three gates, all of them the data layer's rules restated on screen ────────────────
//  1. **A photo is required.** `addTree` throws `validationFailed` without one (BUILD-PLAN §6). The
//     CTA is disabled until there is one, so the boundary and the button agree.
//  2. **A fix is required.** A community tree *is* a coordinate; there is nothing to add without
//     one, and D6 has no notion of a tree whose position is a guess.
//  3. **The 10 m dedupe is the API's, not this screen's.** Nothing here pre-checks it. The screen
//     calls `addTree` and renders `ProximityConflict`'s own candidate list, so the warning can never
//     disagree with the refusal — which is the failure mode a client-side copy of the rule has.
//
//  ── The pin the reader places ─────────────────────────────────────────────────────────────
//  The coordinate used to be `location.fix.coordinate` verbatim, and rule 2 was read as though it
//  said the fix *is* the tree. It does not, and it never did: it says a tree without a coordinate is
//  not a record. So a fix is still required to start — nothing here adds a tree from a phone that
//  does not know where it is — and where the pin *ends* is now the reader's, inside a bound argued in
//  `VisitPinAdjust.radiusM`. The default is still the fix, so stand-shoot-save is still one tap and
//  nobody is walked through a map they did not need.
//
//  What the record cannot yet say is *which* of the two it got. See `Placement`.
//
//  No SwiftUI in this file.
//

import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class VisitAddTreeModel {

    /// What the screen is in.
    enum Phase: Equatable {
        /// Collecting a photo and waiting for a fix.
        case composing
        /// The map is up and the reader is placing the pin. A *phase* rather than a step in
        /// `VisitFlowView`, because the flow builds a fresh `VisitAddTreeModel` for each of its steps
        /// and a step would therefore throw away the photograph on the way to the map and back.
        /// This is the same screen, in a different state, holding the same draft.
        case placingPin
        /// `addTree` is running.
        case adding
        /// BUILD-PLAN §9 M2's "duplicate-proximity warning on add-a-tree". The candidates are the
        /// API's, and every one of them is inside 10 m of the spot — `LocalAPI.addTree` re-checks the
        /// exact metres before it refuses (ERRATA E35).
        case duplicate([NearbyTree])
        /// The add failed for a reason that is not a duplicate.
        case failed(String)
    }

    /// Where the coordinate on the record came from.
    ///
    /// ── This distinction is not persisted, and that is a boundary rather than an oversight ────
    /// `main.community_trees` has columns for `lat` and `lon` and nothing that could carry the
    /// provenance of the pair. Nothing else in the table could carry it honestly either: `address` is
    /// a street address, `external_ref` is the city's own identifier for an inventory row, and
    /// `site_type` is where a tree is planted. Writing a flag into any of them would make the column
    /// mean two things and the next reader would find out the hard way.
    ///
    /// So it needs a migration — a `placement TEXT NOT NULL DEFAULT 'gps'` on `community_trees`, an
    /// AppSchema v9, and `CommunityTreeStore.insert`/`decode` and `Tree` carrying it — and a
    /// migration is a decision about the shape of the record that is not this screen's to take alone
    /// (`Migration`'s own note: "checked in, never edited after shipping"). It is written up in the
    /// round's report instead.
    ///
    /// The type exists anyway, because the screen genuinely has the two states and says which one it
    /// is on: the reader is told whether the tree is going down where they stand or 23 m north-east
    /// of it, and that sentence is the honest part of the distinction that could be delivered without
    /// deciding the schema.
    enum Placement: Equatable {
        /// The phone's fix, verbatim. The default, and what every community tree added before this
        /// screen existed was.
        case gps
        /// The reader moved the pin, and this is where they put it. Carries the fix it was placed
        /// against, so the offset can be stated without asking the provider where the phone is *now*.
        case reader(Coordinate, from: Coordinate)
    }

    private let api: any CypressAPI
    private let location: VisitLocationProvider
    private let attribution: Attribution

    let camera = VisitCameraController()

    private(set) var phase: Phase = .composing
    /// The frame taken, and where it is staged on disk. Both, because the screen draws one and the
    /// API is handed the other — and a photo that could not be written to disk is not a photo.
    private(set) var snapshot: UIImage?
    private(set) var photoPath: String?
    /// Names the staged file. Minted once, so retaking overwrites rather than accumulating, exactly
    /// as `VisitPhotoStaging` names a visit's capture after the visit.
    private let captureID = UUID()

    /// Where this tree is going down. `.gps` until the reader says otherwise.
    private(set) var placement: Placement = .gps

    init(api: any CypressAPI, location: VisitLocationProvider, attribution: Attribution) {
        self.api = api
        self.location = location
        self.attribution = attribution
    }

    // MARK: - Derived

    var fix: VisitLocationProvider.Fix { location.fix }

    /// Where the tree goes.
    ///
    /// The fix while the placement is `.gps` — and *live*, so a draft composed while the first fix is
    /// still settling records the fix as it finally stood rather than as it first arrived. Once the
    /// reader has placed a pin it is that pin and it stops moving: the whole point of placing one is
    /// that the phone's opinion of where it is has been overruled.
    var coordinate: Coordinate? {
        if case let .reader(placed, _) = placement { return placed }
        return location.fix.coordinate
    }

    var hasPhoto: Bool { photoPath != nil }

    /// Whether the reader has moved the pin.
    var isReaderPlaced: Bool {
        if case .reader = placement { return true }
        return false
    }

    /// How far the pin was moved from the fix it was placed against, or nil when it was not moved.
    var pinOffsetM: Double? {
        guard case let .reader(placed, anchor) = placement else { return nil }
        return placed.distance(to: anchor)
    }

    /// Gate 2, on its own: there has to be a fix before there is anything to move the pin away from.
    ///
    /// This is what keeps the pin from becoming a way to add a tree with no GPS at all. A reader with
    /// a refused or pending fix gets no map, because a map with no anchor has no centre, no bound and
    /// nothing to measure a displacement against — and a coordinate typed onto a map from a sofa is
    /// exactly the record `VisitAddTreeModel`'s rule 2 exists to refuse.
    var canAdjustPin: Bool {
        location.fix.coordinate != nil || isReaderPlaced
    }

    /// Gates 1 and 2, together. The button is disabled for exactly the reasons the API would refuse.
    ///
    /// `.placingPin` disables it too, and not only because the CTA is off screen while the map is up:
    /// the model is one object and a phase that could still add would let a stale reference to the
    /// footer write a tree at the coordinate the reader is in the middle of changing.
    var canAdd: Bool {
        hasPhoto && coordinate != nil && phase != .adding && phase != .placingPin
    }

    /// `GPS ±8 m`, in screen 02's own words so the two screens of one flow say it the same way.
    var gpsChipLabel: String? {
        guard let accuracy = location.fix.accuracyM else { return nil }
        return "GPS ±\(Int(accuracy.rounded())) m"
    }

    /// Which sentence stands where the photo and the spot would be. `nil` once both gates are met.
    ///
    /// One property rather than a chain of `if`s in the view, so what the screen says about its own
    /// readiness is testable without a renderer — and so the reasons cannot be reported in an order
    /// that tells somebody to take a photo when the real obstacle is that the phone does not know
    /// where it is.
    var blockingReason: String? {
        // A placed pin satisfies gate 2 by itself: the fix that anchored it was real when it was
        // taken, and a reader who walks into a doorway and loses the signal has not stopped knowing
        // where the tree is.
        if coordinate == nil {
            return location.fix == .denied
                ? VisitAddTreeCopy.noLocationDenied
                : VisitAddTreeCopy.noLocationPending
        }
        if !hasPhoto { return VisitAddTreeCopy.noPhoto }
        return nil
    }

    // MARK: - Lifecycle

    func load() async {
        location.start()
        await camera.start()
    }

    func stop() {
        camera.stop()
    }

    // MARK: - The photo

    func snap() async {
        guard let data = await camera.capturePhoto() else { return }
        apply(imageData: data)
    }

    /// The photo-library path — BUILD-PLAN §9 M1's camera-denied fallback, and the only path a
    /// simulator can take.
    func useLibraryImage(_ data: Data) {
        apply(imageData: data)
    }

    func retake() {
        snapshot = nil
        photoPath = nil
    }

    private func apply(imageData: Data) {
        guard let image = UIImage(data: imageData) else { return }
        do {
            photoPath = try VisitPhotoStaging.write(imageData, for: captureID)
            snapshot = image
            if case .failed = phase { phase = .composing }
        } catch {
            // Same rule screen 04's camera keeps: a photo that cannot survive termination is not a
            // photo, so `canAdd` stays false and the screen says why.
            phase = .failed(VisitAddTreeCopy.photoNotStored(error))
        }
    }

    // MARK: - The pin

    /// The fix the map is anchored on, frozen for as long as the pin screen is up.
    ///
    /// Set when the map opens and kept afterwards, so re-opening the screen puts the reader back on
    /// the same circle rather than on a new one centred wherever they have since wandered. See
    /// `VisitPinAdjustView.anchor` for why a live anchor would be wrong.
    private(set) var pinAnchor: Coordinate?

    /// Opens the map. A no-op without a fix, which is `canAdjustPin`'s rule enforced rather than
    /// merely displayed — the control that calls this is hidden in that state, and a model whose
    /// method disagreed with its own predicate is a bug waiting for a second call site.
    func beginPlacingPin() {
        guard let anchor = pinAnchor ?? location.fix.coordinate else { return }
        pinAnchor = anchor
        phase = .placingPin
    }

    /// Left the map without confirming. The placement is untouched, which includes staying untouched
    /// when there already was one.
    func cancelPlacingPin() {
        guard phase == .placingPin else { return }
        phase = .composing
    }

    /// The reader pressed `Use this spot`.
    ///
    /// Two rules, both of them refusals, and both of them here rather than in the view so they hold
    /// however the coordinate arrived.
    ///
    /// **Out of range is dropped.** The screen disables its own confirm past the limit, but the bound
    /// is a rule about the record and not a rule about a button, and a rule enforced only by a
    /// disabled control is a rule that survives exactly until somebody adds a second way in.
    ///
    /// **A pin left at the fix is the fix.** A reader who opens the map, looks around and confirms
    /// without moving anything has not placed a coordinate, and recording that as reader-placed would
    /// claim a judgement nobody made. Below `VisitPinAdjust.fixToleranceM` the placement goes back to
    /// `.gps`, which also puts the coordinate back on the live fix — the honest state for somebody
    /// who is standing at the tree after all.
    func confirmPin(_ coordinate: Coordinate) {
        guard let anchor = pinAnchor, VisitPinAdjust.isWithinBound(coordinate, of: anchor) else { return }
        placement = coordinate.distance(to: anchor) < VisitPinAdjust.fixToleranceM
            ? .gps
            : .reader(coordinate, from: anchor)
        phase = .composing
    }

    // MARK: - The add

    /// Calls `POST /trees` and reports what came back.
    ///
    /// - Returns: the new tree's id, or nil. Nil is not always a failure the reader must fix —
    ///   `.duplicate` is the API doing its job, and the screen offers the tree it found instead.
    ///
    /// **No outbox.** Every other mutation in this app is enqueued first (ARCHITECTURE §4), and this
    /// one cannot be: `outbox.kind` has no `tree` value, the caller needs the new tree's id to be
    /// able to open it, and the dedupe answer is a *conversation* — a refusal the reader has to
    /// resolve by looking at the candidates — which is the one thing a fire-and-forget queue cannot
    /// carry. The API is local, so there is no round trip to survive; when a server exists this is
    /// the call that grows an outbox kind, and the shape of that work is the dedupe conflict arriving
    /// late rather than immediately.
    ///
    /// A success leaves the phase at `.adding`, which is not an oversight: the screen is on its way
    /// out — the flow opens the tree it just created — and `canAdd` staying false for those frames is
    /// what stops a second tap from writing a second tree 0 m from the first. The 10 m dedupe would
    /// refuse that one, so the consequence would be a duplicate warning naming the tree the reader
    /// had themselves just added, which is the most confusing sentence this screen could produce.
    ///
    /// The coordinate is `coordinate`, which is the fix unless the reader placed a pin — and the 10 m
    /// dedupe therefore runs against wherever the pin ended up, not against the phone. That is the
    /// behaviour the row-of-trees case needs in both directions: five trees photographed from one spot
    /// no longer collide with each other, and a pin dragged onto a tree that is already on record is
    /// still refused, by the same rule, with the same candidate list.
    func add() async -> UUID? {
        guard canAdd, let coordinate, let photoPath else { return nil }
        phase = .adding
        do {
            let tree = try await api.addTree(
                TreeDraft(
                    // `placement` is deliberately not on the draft: there is nowhere in
                    // `community_trees` for it to land, and a field the boundary accepts and discards
                    // is a lie told to the caller. See `Placement`.
                    coordinate: coordinate,
                    // Species is optional on the endpoint, and the screen asks for none: a species
                    // this app cannot confirm would be fabricated botany (BUILD-PLAN §15), and the
                    // record it writes says `community-added, unverified` for exactly that reason.
                    photoLocalPath: photoPath,
                    attribution: attribution
                )
            )
            return tree.id
        } catch let conflict as ProximityConflict {
            phase = .duplicate(conflict.candidates)
            return nil
        } catch {
            phase = .failed(VisitAddTreeCopy.addFailed)
            return nil
        }
    }
}
